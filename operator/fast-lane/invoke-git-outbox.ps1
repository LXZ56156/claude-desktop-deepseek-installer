# Deterministic Git transport for the DevelopmentOnly Fast Lane operator plane.
# Callers must load lib/common.ps1 and lib/vm-test-relay.ps1 first. Relay
# payloads are canonical data only and are never evaluated as commands.

$script:CddsiFastLaneGitOutboxOwnerContract = 'cddsi-fast-lane-git-outbox-owner-v1'
$script:CddsiFastLaneGitOutboxStateContract = 'cddsi-fast-lane-git-outbox-state-v1'
$script:CddsiFastLaneGitOutboxResultContract = 'cddsi-fast-lane-git-outbox-result-v1'
$script:CddsiFastLaneGitOutboxRunnerPath = $PSCommandPath

function Test-CddsiFastLaneGitSha {
    param([AllowNull()]$Value)
    return ($Value -is [string] -and $Value -cmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
}

function Get-CddsiFastLaneGitFileSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [IO.File]::Open($Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    try {
        $sha = [Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }
    finally { $stream.Dispose() }
}

function ConvertTo-CddsiFastLaneGitQuotedArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    if ($Value.Length -gt 0 -and $Value -notmatch '[\s"]') { return $Value }
    $builder = New-Object Text.StringBuilder
    [void]$builder.Append('"')
    $slashes = 0
    foreach ($character in $Value.ToCharArray()) {
        if ($character -ceq '\') {
            $slashes++
            continue
        }
        if ($character -ceq '"') {
            [void]$builder.Append(('\' * (($slashes * 2) + 1)))
            [void]$builder.Append('"')
            $slashes = 0
            continue
        }
        if ($slashes -gt 0) { [void]$builder.Append(('\' * $slashes)); $slashes = 0 }
        [void]$builder.Append($character)
    }
    if ($slashes -gt 0) { [void]$builder.Append(('\' * ($slashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Initialize-CddsiFastLaneBoundedProcessType {
    if ($null -ne ('Cddsi.FastLane.BoundedProcessRunner' -as [type])) { return }

    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.Diagnostics;
using System.IO;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Cddsi.FastLane {
    public sealed class BoundedProcessResult {
        public int ExitCode;
        public bool TimedOut;
        public bool Truncated;
        public bool JobAssigned;
        public bool ProcessTreeTerminated;
        public string StandardOutput;
        public string StandardError;
    }

    public static class BoundedProcessRunner {
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const int JobObjectBasicAccountingInformation = 1;
        private const int JobObjectExtendedLimitInformation = 9;
        private const int NaturalJobQuiescenceMilliseconds = 250;
        private const int ProcessTreeCleanupMilliseconds = 5000;

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION {
            internal long TotalUserTime, TotalKernelTime;
            internal long ThisPeriodTotalUserTime, ThisPeriodTotalKernelTime;
            internal uint TotalPageFaultCount, TotalProcesses;
            internal uint ActiveProcesses, TotalTerminatedProcesses;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS {
            internal ulong ReadOperationCount, WriteOperationCount, OtherOperationCount;
            internal ulong ReadTransferCount, WriteTransferCount, OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
            internal long PerProcessUserTimeLimit, PerJobUserTimeLimit;
            internal uint LimitFlags;
            internal UIntPtr MinimumWorkingSetSize, MaximumWorkingSetSize;
            internal uint ActiveProcessLimit;
            internal UIntPtr Affinity;
            internal uint PriorityClass, SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            internal JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            internal IO_COUNTERS IoInfo;
            internal UIntPtr ProcessMemoryLimit, JobMemoryLimit, PeakProcessMemoryUsed, PeakJobMemoryUsed;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool SetInformationJobObject(IntPtr job, int infoClass, IntPtr info, uint length);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);
        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern bool CreateDirectoryW(string path, IntPtr securityAttributes);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool QueryInformationJobObject(
            IntPtr job, int infoClass, IntPtr info, uint length, IntPtr returnLength);
        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern bool CloseHandle(IntPtr handle);

        private static IntPtr CreateKillOnCloseJob() {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new InvalidOperationException("Job creation failed.");
            var info = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
            info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
            int size = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
            IntPtr pointer = Marshal.AllocHGlobal(size);
            try {
                Marshal.StructureToPtr(info, pointer, false);
                if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, pointer, (uint)size)) {
                    CloseHandle(job);
                    throw new InvalidOperationException("Job policy failed.");
                }
            }
            finally { Marshal.FreeHGlobal(pointer); }
            return job;
        }

        public static bool TryCreateDirectory(string path) {
            if (CreateDirectoryW(path, IntPtr.Zero)) return true;
            int error = Marshal.GetLastWin32Error();
            if (error == 80 || error == 183) return false;
            throw new IOException("Directory creation failed with Win32 error " + error + ".");
        }

        private static uint GetActiveProcessCount(IntPtr job) {
            int size = Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
            IntPtr pointer = Marshal.AllocHGlobal(size);
            try {
                if (!QueryInformationJobObject(
                        job, JobObjectBasicAccountingInformation, pointer, (uint)size, IntPtr.Zero)) {
                    throw new InvalidOperationException("Job accounting query failed.");
                }
                var accounting = (JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)Marshal.PtrToStructure(
                    pointer, typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
                return accounting.ActiveProcesses;
            }
            finally { Marshal.FreeHGlobal(pointer); }
        }

        private static bool WaitForJobQuiescence(IntPtr job, int timeoutMilliseconds) {
            var stopwatch = Stopwatch.StartNew();
            while (true) {
                if (GetActiveProcessCount(job) == 0) return true;
                if (stopwatch.ElapsedMilliseconds >= timeoutMilliseconds) return false;
                Thread.Sleep(10);
            }
        }

        private static int GetRemainingCleanupMilliseconds(Stopwatch cleanupStopwatch) {
            long remaining = ProcessTreeCleanupMilliseconds - cleanupStopwatch.ElapsedMilliseconds;
            return remaining > 0 ? (int)remaining : 0;
        }

        private static void TerminateAndRequireJobQuiescence(
            IntPtr job, Stopwatch cleanupStopwatch) {
            if (!TerminateJobObject(job, 137)) {
                throw new InvalidOperationException("Process tree termination failed.");
            }
            if (!WaitForJobQuiescence(job, GetRemainingCleanupMilliseconds(cleanupStopwatch))) {
                throw new InvalidOperationException("Process tree remained active after termination.");
            }
        }

        private static void RequireUnassignedProcessExit(Process process) {
            bool exited = false;
            try {
                if (!process.HasExited) process.Kill();
                exited = process.WaitForExit(ProcessTreeCleanupMilliseconds);
            }
            catch { exited = false; }
            if (!exited) {
                throw new InvalidOperationException("Unassigned process cleanup failed.");
            }
        }

        private static bool CleanupAssignedProcess(
            Process process, IntPtr job, Thread outputThread, Thread errorThread,
            Stopwatch cleanupStopwatch, bool mainExitAlreadyProven) {
            if (cleanupStopwatch == null) cleanupStopwatch = Stopwatch.StartNew();
            bool terminated = false;
            bool quiescent = false;
            bool mainExited = mainExitAlreadyProven;
            bool outputJoined = outputThread == null;
            bool errorJoined = errorThread == null;
            bool finalZero = false;
            try { terminated = TerminateJobObject(job, 137); } catch { terminated = false; }
            try {
                quiescent = WaitForJobQuiescence(
                    job, GetRemainingCleanupMilliseconds(cleanupStopwatch));
            }
            catch { quiescent = false; }
            if (!mainExited) {
                try {
                    mainExited = process.HasExited || process.WaitForExit(
                        GetRemainingCleanupMilliseconds(cleanupStopwatch));
                }
                catch { mainExited = false; }
            }
            if (outputThread != null) {
                try {
                    outputJoined = outputThread.Join(
                        GetRemainingCleanupMilliseconds(cleanupStopwatch));
                }
                catch { outputJoined = false; }
            }
            if (errorThread != null) {
                try {
                    errorJoined = errorThread.Join(
                        GetRemainingCleanupMilliseconds(cleanupStopwatch));
                }
                catch { errorJoined = false; }
            }
            try { finalZero = GetActiveProcessCount(job) == 0; } catch { finalZero = false; }
            return terminated && quiescent && mainExited && outputJoined && errorJoined && finalZero;
        }

        private sealed class Capture {
            internal readonly StringBuilder Text = new StringBuilder();
            internal bool Truncated;
        }

        private static void Drain(StreamReader reader, Capture capture, int maximumCharacters) {
            char[] buffer = new char[1024];
            try {
                int count;
                while ((count = reader.Read(buffer, 0, buffer.Length)) > 0) {
                    int remaining = maximumCharacters - capture.Text.Length;
                    if (remaining > 0) capture.Text.Append(buffer, 0, Math.Min(remaining, count));
                    if (count > remaining) capture.Truncated = true;
                }
            }
            catch { capture.Truncated = true; }
        }

        public static BoundedProcessResult Run(
            string executable, string arguments, string workingDirectory,
            IDictionary environment, string standardInput, int timeoutMilliseconds,
            int maximumOutputBytes) {
            var info = new ProcessStartInfo();
            info.FileName = executable;
            info.Arguments = arguments;
            info.WorkingDirectory = workingDirectory;
            info.UseShellExecute = false;
            info.CreateNoWindow = true;
            info.RedirectStandardOutput = true;
            info.RedirectStandardError = true;
            info.RedirectStandardInput = standardInput != null;
            info.StandardOutputEncoding = new UTF8Encoding(false, true);
            info.StandardErrorEncoding = new UTF8Encoding(false, true);
            info.EnvironmentVariables.Clear();
            foreach (DictionaryEntry item in environment) {
                info.EnvironmentVariables[Convert.ToString(item.Key)] = Convert.ToString(item.Value);
            }

            IntPtr job = CreateKillOnCloseJob();
            Process process = new Process();
            Thread outputThread = null;
            Thread errorThread = null;
            bool processStarted = false;
            bool jobAssigned = false;
            bool mainExitProven = false;
            Stopwatch cleanupStopwatch = null;
            try {
                process.StartInfo = info;
                if (!process.Start()) throw new InvalidOperationException("Process did not start.");
                processStarted = true;
                if (!AssignProcessToJobObject(job, process.Handle)) {
                    throw new InvalidOperationException("Process job assignment failed.");
                }
                jobAssigned = true;
                var output = new Capture();
                var error = new Capture();
                int perStreamLimit = Math.Max(256, maximumOutputBytes / 2);
                outputThread = new Thread(() => Drain(process.StandardOutput, output, perStreamLimit));
                errorThread = new Thread(() => Drain(process.StandardError, error, perStreamLimit));
                outputThread.IsBackground = true;
                errorThread.IsBackground = true;
                outputThread.Start();
                errorThread.Start();
                if (standardInput != null) {
                    byte[] inputBytes = new UTF8Encoding(false, true).GetBytes(standardInput);
                    Stream inputStream = process.StandardInput.BaseStream;
                    inputStream.Write(inputBytes, 0, inputBytes.Length);
                    inputStream.Flush();
                    inputStream.Close();
                }
                bool exited = process.WaitForExit(timeoutMilliseconds);
                bool processTreeTerminated = false;
                cleanupStopwatch = Stopwatch.StartNew();
                if (!exited) {
                    TerminateAndRequireJobQuiescence(job, cleanupStopwatch);
                    processTreeTerminated = true;
                }
                else if (!WaitForJobQuiescence(job, Math.Min(
                        NaturalJobQuiescenceMilliseconds,
                        GetRemainingCleanupMilliseconds(cleanupStopwatch)))) {
                    TerminateAndRequireJobQuiescence(job, cleanupStopwatch);
                    processTreeTerminated = true;
                }
                if (!process.WaitForExit(GetRemainingCleanupMilliseconds(cleanupStopwatch))) {
                    throw new InvalidOperationException("Main process remained active after termination.");
                }
                mainExitProven = true;
                bool outputJoined = outputThread.Join(
                    GetRemainingCleanupMilliseconds(cleanupStopwatch));
                bool errorJoined = errorThread.Join(
                    GetRemainingCleanupMilliseconds(cleanupStopwatch));
                if (!outputJoined || !errorJoined) {
                    throw new InvalidOperationException("Process output drain did not quiesce.");
                }
                var result = new BoundedProcessResult {
                    ExitCode = exited ? process.ExitCode : -1,
                    TimedOut = !exited,
                    Truncated = output.Truncated || error.Truncated,
                    JobAssigned = true,
                    ProcessTreeTerminated = processTreeTerminated,
                    StandardOutput = output.Text.ToString(),
                    StandardError = error.Text.ToString()
                };
                process.Dispose();
                process = null;
                if (GetActiveProcessCount(job) != 0) {
                    throw new InvalidOperationException("Process tree became active after disposal.");
                }
                return result;
            }
            catch {
                if (processStarted && !jobAssigned) {
                    RequireUnassignedProcessExit(process);
                }
                if (jobAssigned && !CleanupAssignedProcess(
                        process, job, outputThread, errorThread, cleanupStopwatch,
                        mainExitProven)) {
                    throw new InvalidOperationException("Assigned process cleanup failed.");
                }
                throw;
            }
            finally {
                try { if (process != null) process.Dispose(); }
                finally { if (job != IntPtr.Zero) CloseHandle(job); }
            }
        }
    }
}
'@
}

function Invoke-CddsiFastLaneBoundedGitProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [AllowNull()][string]$StandardInput,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory = $true)][int]$MaximumOutputBytes
    )

    $argumentText = (@($Arguments | ForEach-Object {
        ConvertTo-CddsiFastLaneGitQuotedArgument -Value $_
    }) -join ' ')
    return [Cddsi.FastLane.BoundedProcessRunner]::Run(
        $Executable, $argumentText, $WorkingDirectory, $Environment,
        $StandardInput, $TimeoutMilliseconds, $MaximumOutputBytes)
}

function Invoke-CddsiFastLaneGitCommand {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [AllowNull()][string]$StandardInput = $null,
        [int[]]$AllowedExitCodes = @(0),
        [hashtable]$AdditionalEnvironment = @{},
        [switch]$OperatorTransport,
        [switch]$LocalMutation
    )

    foreach ($counterName in @(
        'GitInvocationCount', 'OperatorGitTransportCount', 'LocalStateMutationCount',
        'JobAssignmentCount', 'ProcessTreeTerminationCount'
    )) {
        if (-not $Context.ContainsKey($counterName)) { $Context[$counterName] = 0 }
    }

    $remainingMilliseconds = [int](($Context.MaximumRuntimeSeconds * 1000) - $Context.Stopwatch.ElapsedMilliseconds)
    if ($remainingMilliseconds -le 0) { throw 'FAST_LANE_RUNTIME_LIMIT' }
    $commandTimeout = [Math]::Min($remainingMilliseconds, $Context.MaximumGitCommandSeconds * 1000)
    $allArguments = @(
        '--no-pager', '-c', 'core.hooksPath=NUL', '-c', 'credential.helper=',
        '-c', 'core.longpaths=true', '-c', 'gc.auto=0', '-c', 'maintenance.auto=false'
    )
    if ($Context.ContainsKey('SshCommand') -and -not [string]::IsNullOrEmpty([string]$Context.SshCommand)) {
        $allArguments += @('-c', ('core.sshCommand=' + [string]$Context.SshCommand))
    }
    $allArguments += $Arguments
    $environment = @{
        SystemRoot          = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
        WINDIR              = [Environment]::GetEnvironmentVariable('WINDIR', 'Machine')
        GIT_CONFIG_NOSYSTEM = '1'
        GIT_CONFIG_GLOBAL   = 'NUL'
        GIT_TERMINAL_PROMPT = '0'
        GCM_INTERACTIVE     = 'Never'
        HOME                = $Context.StateRoot
        USERPROFILE         = $Context.StateRoot
        TEMP                = $Context.StateRoot
        TMP                 = $Context.StateRoot
        LC_ALL              = 'C'
    }
    if ($Context.ContainsKey('TransportKind') -and $Context.TransportKind -ceq 'Ssh') {
        $environment.GIT_SSH_VARIANT = 'ssh'
    }
    foreach ($name in $AdditionalEnvironment.Keys) { $environment[$name] = [string]$AdditionalEnvironment[$name] }
    $Context.GitInvocationCount = [int]$Context.GitInvocationCount + 1
    if ($OperatorTransport) { $Context.OperatorGitTransportCount = [int]$Context.OperatorGitTransportCount + 1 }
    if ($LocalMutation) { $Context.LocalStateMutationCount = [int]$Context.LocalStateMutationCount + 1 }
    $result = Invoke-CddsiFastLaneBoundedGitProcess -Executable $Context.GitExecutable `
        -Arguments $allArguments -WorkingDirectory $Context.StateRoot `
        -Environment $environment -StandardInput $StandardInput `
        -TimeoutMilliseconds $commandTimeout -MaximumOutputBytes $Context.MaximumOutputBytes
    if (-not $result.JobAssigned) { throw 'PROCESS_JOB_ASSIGNMENT_REQUIRED' }
    $Context.JobAssignmentCount = [int]$Context.JobAssignmentCount + 1
    if ($result.ProcessTreeTerminated) { $Context.ProcessTreeTerminationCount = [int]$Context.ProcessTreeTerminationCount + 1 }
    if ($result.TimedOut) { throw 'GIT_COMMAND_TIMEOUT' }
    if ($result.ProcessTreeTerminated) { throw 'GIT_PROCESS_TREE_QUIESCENCE_FORCED' }
    if ($result.Truncated) { throw 'GIT_OUTPUT_LIMIT' }
    if ($AllowedExitCodes -cnotcontains $result.ExitCode) {
        throw ('GIT_COMMAND_FAILED:{0}:{1}' -f [int]$Context.GitInvocationCount, [int]$result.ExitCode)
    }
    return $result
}

function Write-CddsiFastLaneAtomicBytes {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [switch]$CreateOnly
    )

    $parent = [IO.Path]::GetDirectoryName($Path)
    if (-not [IO.Directory]::Exists($parent)) { throw 'STATE_PARENT_MISSING' }
    if ($CreateOnly -and [IO.File]::Exists($Path)) { throw 'APPEND_ONLY_PATH_EXISTS' }
    # Keep the full 128-bit nonce while staying below the Windows PowerShell
    # MAX_PATH ceiling when the fixed owner roots are nested in HostSandbox.
    $temporary = Join-Path $parent ('.t' + [guid]::NewGuid().ToString('N'))
    $stream = [IO.File]::Open($temporary, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
    try {
        $stream.Write($Bytes, 0, $Bytes.Length)
        $stream.Flush($true)
    }
    finally { $stream.Dispose() }
    try {
        if ($CreateOnly -or -not [IO.File]::Exists($Path)) {
            [IO.File]::Move($temporary, $Path)
        }
        else {
            $backup = Join-Path $parent ('.b' + [guid]::NewGuid().ToString('N'))
            try { [IO.File]::Replace($temporary, $Path, $backup, $true) }
            finally { if ([IO.File]::Exists($backup)) { [IO.File]::Delete($backup) } }
        }
    }
    finally {
        if ([IO.File]::Exists($temporary)) { [IO.File]::Delete($temporary) }
    }
}

function Write-CddsiFastLaneCanonicalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value,
        [switch]$CreateOnly
    )
    $canonical = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Value
    $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes($canonical + "`n")
    Write-CddsiFastLaneAtomicBytes -Path $Path -Bytes $bytes -CreateOnly:$CreateOnly
}

function ConvertTo-CddsiFastLaneJsonData {
    param([AllowNull()]$Value)
    if ($null -eq $Value) { return $null }
    if ($Value -is [DateTime]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [DateTimeOffset]) {
        return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', [Globalization.CultureInfo]::InvariantCulture)
    }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $copy = [ordered]@{}
        foreach ($key in $Value.Keys) { $copy[[string]$key] = ConvertTo-CddsiFastLaneJsonData $Value[$key] }
        return [pscustomobject]$copy
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = [object[]]@($Value | ForEach-Object { ConvertTo-CddsiFastLaneJsonData $_ })
        return ,$items
    }
    $properties = [ordered]@{}
    foreach ($property in $Value.PSObject.Properties) {
        $properties[$property.Name] = ConvertTo-CddsiFastLaneJsonData $property.Value
    }
    return [pscustomobject]$properties
}

function Read-CddsiFastLaneCanonicalFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][int]$MaximumBytes
    )
    if (-not [IO.File]::Exists($Path)) { throw 'CANONICAL_FILE_MISSING' }
    $info = [IO.FileInfo]::new($Path)
    if ($info.Length -lt 3 -or $info.Length -gt $MaximumBytes) { throw 'CANONICAL_FILE_SIZE_INVALID' }
    $bytes = [IO.File]::ReadAllBytes($Path)
    $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
    if (-not $text.EndsWith("`n") -or $text.EndsWith("`r`n")) { throw 'CANONICAL_FILE_TERMINATOR_INVALID' }
    $json = $text.Substring(0, $text.Length - 1)
    try { $value = ConvertTo-CddsiFastLaneJsonData (ConvertFrom-Json -InputObject $json -ErrorAction Stop) }
    catch { throw 'CANONICAL_JSON_INVALID' }
    if ((ConvertTo-CddsiVmTestRelayCanonicalJson -Value $value) -cne $json) { throw 'CANONICAL_JSON_MISMATCH' }
    return $value
}

function Get-CddsiFastLanePendingPublishPath {
    param([Parameter(Mandatory = $true)][string]$StateRoot)

    return Join-Path $StateRoot 'pending-publish.json'
}

function Read-CddsiFastLanePendingPublish {
    param([Parameter(Mandatory = $true)][string]$Path)

    $journal = Read-CddsiFastLaneCanonicalFile -Path $Path -MaximumBytes 32768
    $properties = @(
        'SchemaVersion', 'ContractVersion', 'RepositoryIdentity', 'RepositoryUriSha256',
        'RemoteRef', 'ExpectedRemoteHead', 'PublishedCommit', 'PublishedPath',
        'CanonicalMessageSha256', 'RelayPreviousStateBindingToken',
        'RelayNextStateBindingToken', 'TransitionValidationTimeUtc',
        'AuthenticatedSenderRole', 'AuthenticatedOutbox', 'CredentialProfileId',
        'SnapshotTrustAssertionSha256'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $journal -Expected $properties)) {
        throw 'PENDING_PUBLISH_SCHEMA_INVALID'
    }
    if (
        $journal.SchemaVersion -ne 1 -or
        $journal.ContractVersion -cne 'cddsi-fast-lane-pending-publish-v1' -or
        $journal.RepositoryIdentity -isnot [string] -or $journal.RepositoryIdentity.Length -lt 1 -or
        $journal.RepositoryUriSha256 -isnot [string] -or $journal.RepositoryUriSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $journal.RemoteRef -cne 'refs/heads/main' -or
        -not (Test-CddsiFastLaneGitSha $journal.ExpectedRemoteHead) -or
        -not (Test-CddsiFastLaneGitSha $journal.PublishedCommit) -or
        $journal.PublishedPath -isnot [string] -or
        $journal.PublishedPath -cnotmatch '^outbox/[0-9]{12}-[a-f0-9-]{36}\.json$' -or
        $journal.CanonicalMessageSha256 -isnot [string] -or $journal.CanonicalMessageSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $journal.RelayPreviousStateBindingToken -isnot [string] -or $journal.RelayPreviousStateBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
        $journal.RelayNextStateBindingToken -isnot [string] -or $journal.RelayNextStateBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
        -not (Test-CddsiUtcTimestampValue $journal.TransitionValidationTimeUtc) -or
        @('HostCoordinator', 'VmTester') -cnotcontains $journal.AuthenticatedSenderRole -or
        @('host-to-vm', 'vm-to-host') -cnotcontains $journal.AuthenticatedOutbox -or
        $journal.CredentialProfileId -isnot [string] -or
        $journal.CredentialProfileId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
        ($null -ne $journal.SnapshotTrustAssertionSha256 -and (
            $journal.SnapshotTrustAssertionSha256 -isnot [string] -or
            $journal.SnapshotTrustAssertionSha256 -cnotmatch '^[a-f0-9]{64}$'
        ))
    ) { throw 'PENDING_PUBLISH_INVALID' }
    return $journal
}

function Test-CddsiFastLaneSafeStateRoot {
    param([Parameter(Mandatory = $true)][string]$StateRoot)

    if (-not [IO.Path]::IsPathRooted($StateRoot)) { return $false }
    $full = [IO.Path]::GetFullPath($StateRoot)
    $leaf = [IO.Path]::GetFileName($full.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    if ($leaf -cnotmatch '^fl-[a-f0-9]{32}$') { return $false }
    $current = [IO.Path]::GetDirectoryName($full)
    if (-not [IO.Directory]::Exists($current)) { return $false }
    while ($null -ne $current -and $current.Length -gt 0) {
        $item = [IO.DirectoryInfo]::new($current)
        if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $parent = [IO.Path]::GetDirectoryName($current.TrimEnd([IO.Path]::DirectorySeparatorChar))
        if ($parent -ceq $current) { break }
        $current = $parent
    }
    return $true
}

function New-CddsiFastLaneGitOwner {
    param(
        [string]$HostToVmRepositoryIdentity,
        [string]$VmToHostRepositoryIdentity,
        [string]$ProductRepositoryIdentity,
        [string]$GitExecutableSha256,
        [string]$RunnerSha256,
        [string]$ProductRootPathSha256,
        [string]$OperatorWorkspacePathSha256
    )
    return [pscustomobject][ordered]@{
        SchemaVersion              = 1
        ContractVersion            = $script:CddsiFastLaneGitOutboxOwnerContract
        Owner                      = 'CDDsiFastLaneGitOutbox'
        OperatorPlaneOnly          = $true
        HostToVmRepositoryIdentity = $HostToVmRepositoryIdentity
        VmToHostRepositoryIdentity = $VmToHostRepositoryIdentity
        ProductRepositoryIdentity  = $ProductRepositoryIdentity
        GitExecutableSha256         = $GitExecutableSha256
        RunnerSha256                = $RunnerSha256
        ProductRootPathSha256       = $ProductRootPathSha256
        OperatorWorkspacePathSha256 = $OperatorWorkspacePathSha256
    }
}

function New-CddsiFastLaneGitState {
    param(
        [string]$HostToVmRepositoryIdentity,
        [string]$VmToHostRepositoryIdentity,
        [string]$ProductRepositoryIdentity,
        [string]$GitExecutableSha256,
        [string]$RunnerSha256,
        [string]$ProductRootPathSha256,
        [string]$OperatorWorkspacePathSha256
    )
    return [pscustomobject][ordered]@{
        SchemaVersion              = 1
        ContractVersion            = $script:CddsiFastLaneGitOutboxStateContract
        HostToVmRepositoryIdentity = $HostToVmRepositoryIdentity
        VmToHostRepositoryIdentity = $VmToHostRepositoryIdentity
        ProductRepositoryIdentity  = $ProductRepositoryIdentity
        GitExecutableSha256         = $GitExecutableSha256
        RunnerSha256                = $RunnerSha256
        ProductRootPathSha256       = $ProductRootPathSha256
        OperatorWorkspacePathSha256 = $OperatorWorkspacePathSha256
        Revision                   = 0
        RelayState                 = New-CddsiVmTestRelayState `
            -HostToVmRepositoryIdentity $HostToVmRepositoryIdentity `
            -VmToHostRepositoryIdentity $VmToHostRepositoryIdentity `
            -ProductRepositoryIdentity $ProductRepositoryIdentity
        Repositories               = @()
    }
}

function Assert-CddsiFastLaneGitState {
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$HostToVmRepositoryIdentity,
        [string]$VmToHostRepositoryIdentity,
        [string]$ProductRepositoryIdentity,
        [string]$GitExecutableSha256,
        [string]$RunnerSha256,
        [string]$ProductRootPathSha256,
        [string]$OperatorWorkspacePathSha256
    )
    $properties = @(
        'SchemaVersion', 'ContractVersion', 'HostToVmRepositoryIdentity',
        'VmToHostRepositoryIdentity', 'ProductRepositoryIdentity',
        'GitExecutableSha256', 'RunnerSha256', 'ProductRootPathSha256',
        'OperatorWorkspacePathSha256', 'Revision', 'RelayState', 'Repositories'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $State -Expected $properties)) { throw 'TRANSPORT_STATE_SCHEMA_INVALID' }
    if ($State.SchemaVersion -ne 1 -or $State.ContractVersion -cne $script:CddsiFastLaneGitOutboxStateContract) { throw 'TRANSPORT_STATE_VERSION_INVALID' }
    if (
        $State.HostToVmRepositoryIdentity -cne $HostToVmRepositoryIdentity -or
        $State.VmToHostRepositoryIdentity -cne $VmToHostRepositoryIdentity -or
        $State.ProductRepositoryIdentity -cne $ProductRepositoryIdentity -or
        $State.GitExecutableSha256 -cne $GitExecutableSha256 -or
        $State.RunnerSha256 -cne $RunnerSha256 -or
        $State.ProductRootPathSha256 -cne $ProductRootPathSha256 -or
        $State.OperatorWorkspacePathSha256 -cne $OperatorWorkspacePathSha256
    ) { throw 'TRANSPORT_STATE_IDENTITY_MISMATCH' }
    if (($State.Revision -isnot [int] -and $State.Revision -isnot [long]) -or [long]$State.Revision -lt 0) { throw 'TRANSPORT_STATE_REVISION_INVALID' }
    if (-not (Test-CddsiVmTestRelayState -State $State.RelayState)) { throw 'TRANSPORT_RELAY_STATE_INVALID' }
    $seen = @{}
    foreach ($repository in @($State.Repositories)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $repository -Expected @(
            'RepositoryIdentity', 'RepositoryUriSha256', 'RepositoryNumericId',
            'RepositoryNodeId', 'ProtectionAuthority', 'ProtectionPolicySha256',
            'ProtectionAuthorityBindingToken', 'ProtectionAuthorityAssertionSha256',
            'ProtectionEvidenceSha256', 'ProtectionObservedAtUtc', 'ProtectionValidUntilUtc',
            'ProtectionReceiptId', 'CredentialProfileId',
            'TransportKind', 'SshExecutableSha256', 'DeployKeySha256', 'KnownHostsSha256',
            'GenesisCommit', 'RemoteRef', 'AcceptedRemoteHead'
        ))) { throw 'TRANSPORT_REPOSITORY_STATE_INVALID' }
        if ($seen.ContainsKey($repository.RepositoryIdentity)) { throw 'TRANSPORT_REPOSITORY_DUPLICATE' }
        $seen[$repository.RepositoryIdentity] = $true
        if (
            $repository.RepositoryIdentity -isnot [string] -or
            $repository.RepositoryUriSha256 -isnot [string] -or $repository.RepositoryUriSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            ($repository.RepositoryNumericId -isnot [int] -and $repository.RepositoryNumericId -isnot [long]) -or [long]$repository.RepositoryNumericId -lt 1 -or
            $repository.RepositoryNodeId -isnot [string] -or $repository.RepositoryNodeId -cnotmatch '^[A-Za-z0-9_=-]{1,128}$' -or
            $repository.ProtectionAuthority -isnot [string] -or $repository.ProtectionAuthority.Length -lt 1 -or
            $repository.ProtectionPolicySha256 -isnot [string] -or $repository.ProtectionPolicySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $repository.ProtectionAuthorityBindingToken -isnot [string] -or $repository.ProtectionAuthorityBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $repository.ProtectionAuthorityAssertionSha256 -isnot [string] -or $repository.ProtectionAuthorityAssertionSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $repository.ProtectionEvidenceSha256 -isnot [string] -or $repository.ProtectionEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            -not (Test-CddsiUtcTimestampValue $repository.ProtectionObservedAtUtc) -or
            -not (Test-CddsiUtcTimestampValue $repository.ProtectionValidUntilUtc) -or
            -not (Test-CddsiCanonicalUuidValue $repository.ProtectionReceiptId) -or
            $repository.CredentialProfileId -isnot [string] -or $repository.CredentialProfileId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$' -or
            @('LocalFile', 'Ssh') -cnotcontains $repository.TransportKind -or
            -not (Test-CddsiFastLaneGitSha $repository.GenesisCommit) -or
            $repository.RemoteRef -cne 'refs/heads/main' -or
            -not (Test-CddsiFastLaneGitSha $repository.AcceptedRemoteHead)
        ) { throw 'TRANSPORT_REPOSITORY_BINDING_INVALID' }
        foreach ($hashName in @('SshExecutableSha256', 'DeployKeySha256', 'KnownHostsSha256')) {
            if ($repository.TransportKind -ceq 'Ssh') {
                if ($repository.$hashName -isnot [string] -or $repository.$hashName -cnotmatch '^[a-f0-9]{64}$') { throw 'TRANSPORT_SSH_BINDING_INVALID' }
            }
            elseif ($null -ne $repository.$hashName) { throw 'TRANSPORT_LOCAL_SSH_BINDING_FORBIDDEN' }
        }
        if ([DateTimeOffset]::Parse($repository.ProtectionValidUntilUtc) -le
            [DateTimeOffset]::Parse($repository.ProtectionObservedAtUtc)) {
            throw 'TRANSPORT_PROTECTION_RECEIPT_WINDOW_INVALID'
        }
    }
}

function Get-CddsiFastLaneRepositoryEntry {
    param([Parameter(Mandatory = $true)]$State, [string]$RepositoryIdentity)
    return @($State.Repositories | Where-Object { $_.RepositoryIdentity -ceq $RepositoryIdentity }) | Select-Object -First 1
}

function Set-CddsiFastLaneRepositoryEntry {
    param([Parameter(Mandatory = $true)]$State, [Parameter(Mandatory = $true)]$Entry)
    $others = @($State.Repositories | Where-Object { $_.RepositoryIdentity -cne $Entry.RepositoryIdentity })
    $State.Repositories = @($others) + @($Entry)
}

function Assert-CddsiFastLaneProtectionEvidence {
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][string]$EvidenceSha256,
        [Parameter(Mandatory = $true)][string]$RepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$RemoteRef,
        [Parameter(Mandatory = $true)][long]$ExpectedRepositoryNumericId,
        [Parameter(Mandatory = $true)][string]$ExpectedRepositoryNodeId,
        [Parameter(Mandatory = $true)][ValidateSet('PUBLIC')][string]$ExpectedRepositoryVisibility,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthority,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionPolicySha256,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][int]$MaximumAgeSeconds,
        [Parameter(Mandatory = $true)][int]$MaximumClockSkewSeconds
    )
    $properties = @(
        'SchemaVersion', 'ContractVersion', 'RepositoryIdentity',
        'RepositoryNumericId', 'RepositoryNodeId', 'Visibility', 'RemoteRef',
        'ForcePushAllowed', 'BranchDeletionAllowed', 'HistoryRewriteAllowed',
        'Authority', 'ProtectionPolicySha256', 'PreviousReceiptSha256',
        'ObservedAtUtc', 'ValidUntilUtc', 'ReceiptId'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $properties)) { throw 'PROTECTION_EVIDENCE_SCHEMA_INVALID' }
    if (
        $Evidence.SchemaVersion -ne 2 -or
        $Evidence.ContractVersion -cne 'cddsi-fast-lane-control-repo-protection-v3' -or
        $Evidence.RepositoryIdentity -cne $RepositoryIdentity -or
        ($Evidence.RepositoryNumericId -isnot [int] -and $Evidence.RepositoryNumericId -isnot [long]) -or
        [long]$Evidence.RepositoryNumericId -lt 1 -or
        [long]$Evidence.RepositoryNumericId -ne $ExpectedRepositoryNumericId -or
        $Evidence.RepositoryNodeId -isnot [string] -or $Evidence.RepositoryNodeId -cnotmatch '^[A-Za-z0-9_=-]{1,128}$' -or
        $Evidence.RepositoryNodeId -cne $ExpectedRepositoryNodeId -or
        $Evidence.Authority -isnot [string] -or $Evidence.Authority -cne $ExpectedProtectionAuthority -or
        $Evidence.ProtectionPolicySha256 -isnot [string] -or
        $Evidence.ProtectionPolicySha256 -cne $ExpectedProtectionPolicySha256 -or
        $ExpectedProtectionPolicySha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $Evidence.Visibility -isnot [string] -or $Evidence.Visibility -cne $ExpectedRepositoryVisibility -or
        $Evidence.RemoteRef -cne $RemoteRef -or
        $Evidence.ForcePushAllowed -isnot [bool] -or $Evidence.ForcePushAllowed -or
        $Evidence.BranchDeletionAllowed -isnot [bool] -or $Evidence.BranchDeletionAllowed -or
        $Evidence.HistoryRewriteAllowed -isnot [bool] -or $Evidence.HistoryRewriteAllowed -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.ObservedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.ValidUntilUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.ReceiptId)
    ) { throw 'PROTECTION_EVIDENCE_INVALID' }
    if ($null -ne $Evidence.PreviousReceiptSha256 -and (
        $Evidence.PreviousReceiptSha256 -isnot [string] -or $Evidence.PreviousReceiptSha256 -cnotmatch '^[a-f0-9]{64}$'
    )) { throw 'PROTECTION_EVIDENCE_PREVIOUS_RECEIPT_INVALID' }
    $observed = [DateTimeOffset]::Parse($Evidence.ObservedAtUtc)
    $validUntil = [DateTimeOffset]::Parse($Evidence.ValidUntilUtc)
    $validation = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if (
        $validUntil -le $observed -or $validUntil -gt $observed.AddHours(1) -or
        $validation -ge $validUntil -or
        $observed -gt $validation.AddSeconds($MaximumClockSkewSeconds) -or
        ($validation - $observed).TotalSeconds -gt $MaximumAgeSeconds
    ) { throw 'PROTECTION_EVIDENCE_EXPIRED_OR_STALE' }
    if ($EvidenceSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'PROTECTION_EVIDENCE_HASH_INVALID' }
    $actual = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Evidence)
    if ($actual -cne $EvidenceSha256) { throw 'PROTECTION_EVIDENCE_HASH_MISMATCH' }
}

function Assert-CddsiFastLaneProtectionAuthorityAssertion {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$OperatorWorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$ProtectionTrustRoot,
        [Parameter(Mandatory = $true)][string]$ProtectionAuthorityAssertionPath,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthorityAssertionSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthorityBindingToken,
        [Parameter(Mandatory = $true)]$ProtectionEvidence,
        [Parameter(Mandatory = $true)][string]$ProtectionEvidenceSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthority,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionPolicySha256,
        [Parameter(Mandatory = $true)][string]$RepositoryIdentity,
        [Parameter(Mandatory = $true)][long]$ExpectedRepositoryNumericId,
        [Parameter(Mandatory = $true)][string]$ExpectedRepositoryNodeId,
        [Parameter(Mandatory = $true)][string]$RemoteRef
    )

    if (
        $ExpectedProtectionAuthorityAssertionSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ExpectedProtectionAuthorityBindingToken -cnotmatch '^[a-f0-9]{64}$'
    ) { throw 'PROTECTION_AUTHORITY_TRUST_INPUT_INVALID' }
    foreach ($path in @($ProtectionTrustRoot, $ProtectionAuthorityAssertionPath)) {
        if (-not [IO.Path]::IsPathRooted($path) -or -not (Test-CddsiFastLanePathWithoutReparsePoint $path)) {
            throw 'PROTECTION_AUTHORITY_TRUST_PATH_INVALID'
        }
    }
    $fullTrustRoot = [IO.Path]::GetFullPath($ProtectionTrustRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullAssertionPath = [IO.Path]::GetFullPath($ProtectionAuthorityAssertionPath)
    $fullWorkspace = [IO.Path]::GetFullPath($OperatorWorkspaceRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (
        [IO.Path]::GetFileName($fullTrustRoot) -cne 'control-protection-trust' -or
        [IO.Path]::GetDirectoryName($fullTrustRoot) -cne $fullWorkspace -or
        [IO.Path]::GetDirectoryName($fullAssertionPath) -cne $fullTrustRoot -or
        (Test-CddsiFastLanePathWithinRoot $fullTrustRoot $StateRoot) -or
        (Test-CddsiFastLanePathWithinRoot $StateRoot $fullTrustRoot) -or
        (Test-CddsiFastLanePathWithinRoot $fullTrustRoot $ProductRoot)
    ) { throw 'PROTECTION_AUTHORITY_TRUST_ROOT_BOUNDARY_INVALID' }

    $rootMarker = Read-CddsiFastLaneCanonicalFile -Path (Join-Path $fullTrustRoot '.cddsi-owner.json') -MaximumBytes 8192
    $expectedRootMarker = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-protection-authority-trust-root-v1'
        Owner = 'CDDsiFastLaneProtectionAuthorityTrust'; OperatorPlaneOnly = $true
        ProtectionAuthority = $ExpectedProtectionAuthority
        ProtectionAuthorityBindingToken = $ExpectedProtectionAuthorityBindingToken
        ProductRootPathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $ProductRoot
        OperatorWorkspacePathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $OperatorWorkspaceRoot
    }
    if ((ConvertTo-CddsiVmTestRelayCanonicalJson $rootMarker) -cne
        (ConvertTo-CddsiVmTestRelayCanonicalJson $expectedRootMarker)) {
        throw 'PROTECTION_AUTHORITY_TRUST_ROOT_OWNER_INVALID'
    }
    if ((Get-CddsiFastLaneGitFileSha256 $fullAssertionPath) -cne
        $ExpectedProtectionAuthorityAssertionSha256) {
        throw 'PROTECTION_AUTHORITY_ASSERTION_HASH_MISMATCH'
    }
    $assertion = Read-CddsiFastLaneCanonicalFile -Path $fullAssertionPath -MaximumBytes 32768
    $properties = @(
        'SchemaVersion', 'ContractVersion', 'ExternallyVerified', 'ProtectionAuthority',
        'ProtectionAuthorityBindingToken', 'ProtectionPolicySha256', 'ProtectionEvidenceSha256',
        'RepositoryIdentity', 'RepositoryNumericId', 'RepositoryNodeId', 'RemoteRef',
        'PreviousReceiptSha256', 'ObservedAtUtc', 'ValidUntilUtc', 'ReceiptId'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $assertion -Expected $properties)) {
        throw 'PROTECTION_AUTHORITY_ASSERTION_SCHEMA_INVALID'
    }
    if (
        $assertion.SchemaVersion -ne 1 -or
        $assertion.ContractVersion -cne 'cddsi-fast-lane-protection-authority-assertion-v1' -or
        $assertion.ExternallyVerified -isnot [bool] -or -not $assertion.ExternallyVerified -or
        $assertion.ProtectionAuthority -cne $ExpectedProtectionAuthority -or
        $assertion.ProtectionAuthorityBindingToken -cne $ExpectedProtectionAuthorityBindingToken -or
        $assertion.ProtectionPolicySha256 -cne $ExpectedProtectionPolicySha256 -or
        $assertion.ProtectionEvidenceSha256 -cne $ProtectionEvidenceSha256 -or
        $assertion.RepositoryIdentity -cne $RepositoryIdentity -or
        ($assertion.RepositoryNumericId -isnot [int] -and $assertion.RepositoryNumericId -isnot [long]) -or
        [long]$assertion.RepositoryNumericId -ne $ExpectedRepositoryNumericId -or
        $assertion.RepositoryNodeId -cne $ExpectedRepositoryNodeId -or
        $assertion.RemoteRef -cne $RemoteRef -or
        $assertion.PreviousReceiptSha256 -cne $ProtectionEvidence.PreviousReceiptSha256 -or
        $assertion.ObservedAtUtc -cne $ProtectionEvidence.ObservedAtUtc -or
        $assertion.ValidUntilUtc -cne $ProtectionEvidence.ValidUntilUtc -or
        $assertion.ReceiptId -cne $ProtectionEvidence.ReceiptId
    ) { throw 'PROTECTION_AUTHORITY_ASSERTION_INVALID' }
    if ([IO.Path]::GetFileName($fullAssertionPath) -cne
        ('protection-' + $ProtectionEvidence.ReceiptId + '.json')) {
        throw 'PROTECTION_AUTHORITY_ASSERTION_FILENAME_INVALID'
    }
    return [pscustomobject]@{
        AssertionSha256 = $ExpectedProtectionAuthorityAssertionSha256
        AuthorityBindingToken = $ExpectedProtectionAuthorityBindingToken
    }
}

function Test-CddsiFastLanePathWithoutReparsePoint {
    param([Parameter(Mandatory = $true)][string]$Path)
    $current = [IO.Path]::GetFullPath($Path)
    while (-not [string]::IsNullOrEmpty($current)) {
        if ([IO.File]::Exists($current)) { $attributes = [IO.FileInfo]::new($current).Attributes }
        elseif ([IO.Directory]::Exists($current)) { $attributes = [IO.DirectoryInfo]::new($current).Attributes }
        else { return $false }
        if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
        $parent = [IO.Path]::GetDirectoryName($current.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
        if ($parent -ceq $current) { break }
        $current = $parent
    }
    return $true
}

function Assert-CddsiFastLanePinnedFile {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Sha256,
        [Parameter(Mandatory = $true)][string]$ErrorPrefix
    )
    if (-not [IO.Path]::IsPathRooted($Path) -or -not [IO.File]::Exists($Path)) { throw ($ErrorPrefix + '_PATH_INVALID') }
    if (-not (Test-CddsiFastLanePathWithoutReparsePoint -Path $Path)) { throw ($ErrorPrefix + '_REPARSE_POINT_FORBIDDEN') }
    if ($Sha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-CddsiFastLaneGitFileSha256 $Path) -cne $Sha256) {
        throw ($ErrorPrefix + '_HASH_MISMATCH')
    }
}

function Test-CddsiFastLanePathWithinRoot {
    param([Parameter(Mandatory = $true)][string]$Path, [Parameter(Mandatory = $true)][string]$Root)
    $fullPath = [IO.Path]::GetFullPath($Path)
    $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if ($fullPath.Equals($fullRoot, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    return $fullPath.StartsWith(($fullRoot + [IO.Path]::DirectorySeparatorChar), [StringComparison]::OrdinalIgnoreCase)
}

function Get-CddsiFastLaneCanonicalPathSha256 {
    param([Parameter(Mandatory = $true)][string]$Path)
    $canonical = [IO.Path]::GetFullPath($Path).TrimEnd(
        [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar).ToLowerInvariant()
    return Get-CddsiSupplyChainTextBindingToken -Text $canonical
}

function Assert-CddsiFastLaneOperatorWorkspace {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$OperatorWorkspaceRoot
    )
    foreach ($root in @($ProductRoot, $OperatorWorkspaceRoot)) {
        if (-not [IO.Path]::IsPathRooted($root) -or -not [IO.Directory]::Exists($root)) { throw 'WORKSPACE_ROOT_INVALID' }
        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $root)) { throw 'WORKSPACE_REPARSE_POINT_FORBIDDEN' }
    }
    $fullState = [IO.Path]::GetFullPath($StateRoot)
    $fullProduct = [IO.Path]::GetFullPath($ProductRoot)
    $fullWorkspace = [IO.Path]::GetFullPath($OperatorWorkspaceRoot)
    if (Test-CddsiFastLanePathWithinRoot $fullState $fullProduct) { throw 'STATE_ROOT_INSIDE_PRODUCT_ROOT_FORBIDDEN' }
    if (
        (Test-CddsiFastLanePathWithinRoot $fullWorkspace $fullProduct) -or
        (Test-CddsiFastLanePathWithinRoot $fullProduct $fullWorkspace)
    ) { throw 'OPERATOR_PRODUCT_WORKSPACE_OVERLAP' }
    if (-not (Test-CddsiFastLanePathWithinRoot $fullState $fullWorkspace)) { throw 'STATE_ROOT_OUTSIDE_OPERATOR_WORKSPACE' }
    if ([IO.Path]::GetDirectoryName($fullState.TrimEnd([IO.Path]::DirectorySeparatorChar)) -cne
        $fullWorkspace.TrimEnd([IO.Path]::DirectorySeparatorChar)) {
        throw 'STATE_ROOT_MUST_BE_DIRECT_OPERATOR_WORKSPACE_CHILD'
    }
    $productSha = Get-CddsiFastLaneCanonicalPathSha256 $fullProduct
    $workspaceSha = Get-CddsiFastLaneCanonicalPathSha256 $fullWorkspace
    $marker = Read-CddsiFastLaneCanonicalFile -Path (Join-Path $fullWorkspace '.cddsi-owner.json') -MaximumBytes 8192
    $expected = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-operator-workspace-owner-v1'
        Owner = 'CDDsiFastLaneOperatorWorkspace'; OperatorPlaneOnly = $true
        ProductRootPathSha256 = $productSha; OperatorWorkspacePathSha256 = $workspaceSha
    }
    if ((ConvertTo-CddsiVmTestRelayCanonicalJson $marker) -cne (ConvertTo-CddsiVmTestRelayCanonicalJson $expected)) {
        throw 'OPERATOR_WORKSPACE_OWNER_MARKER_INVALID'
    }
    return [pscustomobject]@{ ProductRootPathSha256 = $productSha; OperatorWorkspacePathSha256 = $workspaceSha }
}

function Assert-CddsiFastLaneExternalSnapshotTrust {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$OperatorWorkspaceRoot,
        [AllowNull()][string]$SnapshotTrustRoot,
        [AllowNull()][string]$SnapshotTrustAssertionPath,
        [AllowNull()][string]$ExpectedSnapshotTrustAssertionSha256,
        [AllowNull()][string]$ExternallyVerifiedSnapshotReceiptSha256,
        [AllowNull()][string]$ExternallyVerifiedSnapshotAuthorityBindingToken,
        [Parameter(Mandatory = $true)][string]$HostToVmRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$VmToHostRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$ProductRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$RepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$AuthenticatedOutbox,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][int]$MaximumAgeSeconds,
        [Parameter(Mandatory = $true)][int]$MaximumClockSkewSeconds
    )

    $inputs = @(
        $SnapshotTrustRoot, $SnapshotTrustAssertionPath, $ExpectedSnapshotTrustAssertionSha256,
        $ExternallyVerifiedSnapshotReceiptSha256,
        $ExternallyVerifiedSnapshotAuthorityBindingToken
    )
    $presentCount = @($inputs | Where-Object { -not [string]::IsNullOrEmpty([string]$_) }).Count
    if ($presentCount -eq 0) { return $null }
    if ($presentCount -ne $inputs.Count) { throw 'SNAPSHOT_TRUST_INPUT_INCOMPLETE' }
    if (
        $ExpectedSnapshotTrustAssertionSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ExternallyVerifiedSnapshotReceiptSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ExternallyVerifiedSnapshotAuthorityBindingToken -cnotmatch '^[a-f0-9]{64}$'
    ) { throw 'SNAPSHOT_TRUST_INPUT_INVALID' }
    foreach ($path in @($SnapshotTrustRoot, $SnapshotTrustAssertionPath)) {
        if (-not [IO.Path]::IsPathRooted($path) -or -not (Test-CddsiFastLanePathWithoutReparsePoint $path)) {
            throw 'SNAPSHOT_TRUST_PATH_INVALID'
        }
    }
    $fullTrustRoot = [IO.Path]::GetFullPath($SnapshotTrustRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    $fullAssertionPath = [IO.Path]::GetFullPath($SnapshotTrustAssertionPath)
    $fullWorkspace = [IO.Path]::GetFullPath($OperatorWorkspaceRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
    if (
        [IO.Path]::GetFileName($fullTrustRoot) -cne 'external-snapshot-trust' -or
        [IO.Path]::GetDirectoryName($fullTrustRoot) -cne $fullWorkspace -or
        [IO.Path]::GetDirectoryName($fullAssertionPath) -cne $fullTrustRoot -or
        (Test-CddsiFastLanePathWithinRoot $fullTrustRoot $StateRoot) -or
        (Test-CddsiFastLanePathWithinRoot $StateRoot $fullTrustRoot) -or
        (Test-CddsiFastLanePathWithinRoot $fullTrustRoot $ProductRoot)
    ) { throw 'SNAPSHOT_TRUST_ROOT_BOUNDARY_INVALID' }

    $productSha = Get-CddsiFastLaneCanonicalPathSha256 $ProductRoot
    $workspaceSha = Get-CddsiFastLaneCanonicalPathSha256 $OperatorWorkspaceRoot
    $rootMarker = Read-CddsiFastLaneCanonicalFile -Path (Join-Path $fullTrustRoot '.cddsi-owner.json') -MaximumBytes 8192
    $expectedRootMarker = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-external-snapshot-trust-root-v1'
        Owner = 'CDDsiFastLaneExternalSnapshotTrust'; OperatorPlaneOnly = $true
        ExternalReceiptAuthority = 'HypervisorSupervisor'
        ProductRootPathSha256 = $productSha; OperatorWorkspacePathSha256 = $workspaceSha
    }
    if ((ConvertTo-CddsiVmTestRelayCanonicalJson $rootMarker) -cne
        (ConvertTo-CddsiVmTestRelayCanonicalJson $expectedRootMarker)) {
        throw 'SNAPSHOT_TRUST_ROOT_OWNER_INVALID'
    }
    if ((Get-CddsiFastLaneGitFileSha256 $fullAssertionPath) -cne $ExpectedSnapshotTrustAssertionSha256) {
        throw 'SNAPSHOT_TRUST_ASSERTION_HASH_MISMATCH'
    }
    $assertion = Read-CddsiFastLaneCanonicalFile -Path $fullAssertionPath -MaximumBytes 32768
    $properties = @(
        'SchemaVersion', 'ContractVersion', 'ExternalReceiptAuthority', 'ExternallyVerified',
        'SnapshotReceiptSha256', 'SnapshotAuthorityBindingToken',
        'HostToVmRepositoryIdentity', 'VmToHostRepositoryIdentity', 'ProductRepositoryIdentity',
        'RepositoryIdentity', 'AuthenticatedOutbox', 'CycleId', 'RunId',
        'ObservedAtUtc', 'ValidUntilUtc'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $assertion -Expected $properties)) {
        throw 'SNAPSHOT_TRUST_ASSERTION_SCHEMA_INVALID'
    }
    if (
        $assertion.SchemaVersion -ne 1 -or
        $assertion.ContractVersion -cne 'cddsi-fast-lane-external-snapshot-trust-v1' -or
        $assertion.ExternalReceiptAuthority -cne 'HypervisorSupervisor' -or
        $assertion.ExternallyVerified -isnot [bool] -or -not $assertion.ExternallyVerified -or
        $assertion.SnapshotReceiptSha256 -cne $ExternallyVerifiedSnapshotReceiptSha256 -or
        $assertion.SnapshotAuthorityBindingToken -cne $ExternallyVerifiedSnapshotAuthorityBindingToken -or
        $assertion.HostToVmRepositoryIdentity -cne $HostToVmRepositoryIdentity -or
        $assertion.VmToHostRepositoryIdentity -cne $VmToHostRepositoryIdentity -or
        $assertion.ProductRepositoryIdentity -cne $ProductRepositoryIdentity -or
        $assertion.RepositoryIdentity -cne $RepositoryIdentity -or
        $assertion.AuthenticatedOutbox -cne $AuthenticatedOutbox -or
        -not (Test-CddsiCanonicalUuidValue $assertion.CycleId) -or
        -not (Test-CddsiCanonicalUuidValue $assertion.RunId) -or
        -not (Test-CddsiUtcTimestampValue $assertion.ObservedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue $assertion.ValidUntilUtc) -or
        -not (Test-CddsiUtcTimestampValue $ValidationTimeUtc)
    ) { throw 'SNAPSHOT_TRUST_ASSERTION_INVALID' }
    $observed = [DateTimeOffset]::Parse($assertion.ObservedAtUtc)
    $validUntil = [DateTimeOffset]::Parse($assertion.ValidUntilUtc)
    $validation = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if (
        $validUntil -le $observed -or $validUntil -gt $observed.AddHours(1) -or
        $validation -ge $validUntil -or
        $observed -gt $validation.AddSeconds($MaximumClockSkewSeconds) -or
        ($validation - $observed).TotalSeconds -gt $MaximumAgeSeconds
    ) { throw 'SNAPSHOT_TRUST_ASSERTION_EXPIRED_OR_STALE' }
    $expectedName = 'snapshot-trust-' + $assertion.CycleId + '.json'
    if ([IO.Path]::GetFileName($fullAssertionPath) -cne $expectedName) {
        throw 'SNAPSHOT_TRUST_ASSERTION_FILENAME_INVALID'
    }
    return [pscustomobject]@{
        AssertionSha256 = $ExpectedSnapshotTrustAssertionSha256
        SnapshotReceiptSha256 = $ExternallyVerifiedSnapshotReceiptSha256
        SnapshotAuthorityBindingToken = $ExternallyVerifiedSnapshotAuthorityBindingToken
        CycleId = [string]$assertion.CycleId; RunId = [string]$assertion.RunId
    }
}

function Resolve-CddsiFastLaneBoundRelayTransition {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Message,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][string]$AuthenticatedSenderRole,
        [Parameter(Mandatory = $true)][string]$AuthenticatedOutbox,
        [AllowNull()]$SnapshotTrust,
        [Parameter(Mandatory = $true)][int]$MaximumAgeSeconds,
        [Parameter(Mandatory = $true)][int]$MaximumClockSkewSeconds,
        [Parameter(Mandatory = $true)][int]$MaximumMessageBodyBytes
    )

    $isSnapshotReady = $Message.Envelope.MessageType -ceq 'SNAPSHOT_READY'
    if ($isSnapshotReady) {
        if ($null -eq $SnapshotTrust) { throw 'SNAPSHOT_TRUST_ASSERTION_REQUIRED' }
        if (
            $Message.Envelope.CycleId -cne $SnapshotTrust.CycleId -or
            $Message.Envelope.RunId -cne $SnapshotTrust.RunId -or
            $Message.Envelope.SnapshotReceiptSha256 -cne $SnapshotTrust.SnapshotReceiptSha256 -or
            $Message.Payload.ExternalReceiptAuthorityBindingToken -cne
                $SnapshotTrust.SnapshotAuthorityBindingToken
        ) { throw 'SNAPSHOT_TRUST_MESSAGE_BINDING_MISMATCH' }
    }
    elseif ($null -ne $SnapshotTrust) { throw 'SNAPSHOT_TRUST_INPUT_NOT_APPLICABLE' }

    return Resolve-CddsiVmTestRelayTransition -State $State -Envelope $Message.Envelope `
        -Payload $Message.Payload -ValidationTimeUtc $ValidationTimeUtc `
        -AuthenticatedSenderRole $AuthenticatedSenderRole -AuthenticatedOutbox $AuthenticatedOutbox `
        -ExternallyVerifiedSnapshotReceiptSha256 $(if ($isSnapshotReady) { $SnapshotTrust.SnapshotReceiptSha256 } else { $null }) `
        -ExternallyVerifiedSnapshotAuthorityBindingToken $(if ($isSnapshotReady) { $SnapshotTrust.SnapshotAuthorityBindingToken } else { $null }) `
        -MaximumAgeSeconds $MaximumAgeSeconds -MaximumClockSkewSeconds $MaximumClockSkewSeconds `
        -MaximumMessageBodyBytes $MaximumMessageBodyBytes
}

function ConvertTo-CddsiFastLaneSshCommandArgument {
    param([Parameter(Mandatory = $true)][string]$Value)
    if (
        $Value.Length -lt 1 -or $Value.Contains("'") -or $Value.Contains("`r") -or
        $Value.Contains("`n") -or $Value.IndexOf([char]0) -ge 0
    ) { throw 'SSH_COMMAND_ARGUMENT_INVALID' }
    return "'" + $Value + "'"
}

function Get-CddsiFastLaneTransportProfile {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryUri,
        [Parameter(Mandatory = $true)][string]$RepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$CredentialProfileId
    )
    $frozen = @(
        'github.com/LXZ56156/claude-desktop-deepseek-installer',
        'github.com/LXZ56156/cddsi-host-to-vm',
        'github.com/LXZ56156/cddsi-vm-to-host'
    )
    $sshIdentity = $null
    if ($RepositoryUri -cmatch '^git@github\.com:([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)\.git$') { $sshIdentity = 'github.com/' + $Matches[1] }
    elseif ($RepositoryUri -cmatch '^ssh://git@github\.com/([A-Za-z0-9._-]+/[A-Za-z0-9._-]+)\.git$') { $sshIdentity = 'github.com/' + $Matches[1] }
    if ($null -ne $sshIdentity) {
        if ($sshIdentity -cne $RepositoryIdentity -or $frozen -cnotcontains $RepositoryIdentity) { throw 'SSH_REPOSITORY_IDENTITY_MISMATCH' }
        return [pscustomobject]@{ Kind = 'Ssh'; OwnerRoot = $null }
    }

    if (-not [IO.Path]::IsPathRooted($RepositoryUri) -or -not [IO.Directory]::Exists($RepositoryUri)) {
        throw 'REPOSITORY_TRANSPORT_NOT_ALLOWED'
    }
    $full = [IO.Path]::GetFullPath($RepositoryUri)
    if (-not (Test-CddsiFastLanePathWithoutReparsePoint $full)) { throw 'LOCAL_TRANSPORT_REPARSE_POINT_FORBIDDEN' }
    $current = [IO.Path]::GetDirectoryName($full.TrimEnd([IO.Path]::DirectorySeparatorChar))
    $ownerRoot = $null
    while (-not [string]::IsNullOrEmpty($current)) {
        $leaf = [IO.Path]::GetFileName($current.TrimEnd([IO.Path]::DirectorySeparatorChar))
        if ($leaf -cmatch '^cddsi-test-[a-f0-9]{32}$') {
            $ownerRoot = $current
            break
        }
        $parent = [IO.Path]::GetDirectoryName($current.TrimEnd([IO.Path]::DirectorySeparatorChar))
        if ($parent -ceq $current) { break }
        $current = $parent
    }
    if ($null -eq $ownerRoot) { throw 'LOCAL_TRANSPORT_OWNER_ROOT_MISSING' }
    $marker = Read-CddsiFastLaneCanonicalFile -Path (Join-Path $ownerRoot '.cddsi-owner.json') -MaximumBytes 8192
    $expected = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-local-transport-owner-v1'
        Owner = 'CDDsiFastLaneGitOutboxTests'; SyntheticOnly = $true
    }
    if ((ConvertTo-CddsiVmTestRelayCanonicalJson $marker) -cne (ConvertTo-CddsiVmTestRelayCanonicalJson $expected)) {
        throw 'LOCAL_TRANSPORT_OWNER_MARKER_INVALID'
    }
    return [pscustomobject]@{ Kind = 'LocalFile'; OwnerRoot = $ownerRoot }
}

function Get-CddsiFastLaneCredentialBinding {
    param(
        [Parameter(Mandatory = $true)][string]$RepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$AuthenticatedOutbox,
        [Parameter(Mandatory = $true)][string]$CredentialProfileId,
        [Parameter(Mandatory = $true)][string]$TransportKind,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthority,
        [Parameter(Mandatory = $true)][ValidateSet('Poll', 'Publish')][string]$Operation
    )
    if ($TransportKind -ceq 'LocalFile') {
        $bindings = @{
            'synthetic/host-to-vm' = [pscustomobject]@{
                Outbox = 'host-to-vm'; Role = 'HostCoordinator'
                Profiles = @{ Poll = 'synthetic.host-to-vm.read'; Publish = 'synthetic.host-to-vm.write' }
                Authority = 'synthetic/CddsiFastLaneProtectionAuthority'
            }
            'synthetic/vm-to-host' = [pscustomobject]@{
                Outbox = 'vm-to-host'; Role = 'VmTester'
                Profiles = @{ Poll = 'synthetic.vm-to-host.read'; Publish = 'synthetic.vm-to-host.write' }
                Authority = 'synthetic/CddsiFastLaneProtectionAuthority'
            }
        }
    }
    else {
        $bindings = @{
            'github.com/LXZ56156/cddsi-host-to-vm' = [pscustomobject]@{
                Outbox = 'host-to-vm'; Role = 'HostCoordinator'
                Profiles = @{ Poll = 'vm.host-to-vm.read'; Publish = 'host.host-to-vm.write' }
                Authority = 'github.com/LXZ56156/cddsi-control-protection-authority-v1'
            }
            'github.com/LXZ56156/cddsi-vm-to-host' = [pscustomobject]@{
                Outbox = 'vm-to-host'; Role = 'VmTester'
                Profiles = @{ Poll = 'host.vm-to-host.read'; Publish = 'vm.vm-to-host.write' }
                Authority = 'github.com/LXZ56156/cddsi-control-protection-authority-v1'
            }
        }
    }
    if (-not $bindings.ContainsKey($RepositoryIdentity)) { throw 'CREDENTIAL_REPOSITORY_BINDING_NOT_FROZEN' }
    $binding = $bindings[$RepositoryIdentity]
    if (
        $binding.Outbox -cne $AuthenticatedOutbox -or
        $binding.Profiles[$Operation] -cne $CredentialProfileId -or
        $binding.Authority -cne $ExpectedProtectionAuthority
    ) { throw 'CREDENTIAL_DIRECTION_ROLE_AUTHORITY_MISMATCH' }
    return $binding
}

function Assert-CddsiFastLaneRepositoryUri {
    param([Parameter(Mandatory = $true)][string]$RepositoryUri)
    if (
        $RepositoryUri.Length -lt 1 -or $RepositoryUri.Length -gt 1024 -or
        $RepositoryUri[0] -ceq '-' -or $RepositoryUri.IndexOf([char]0) -ge 0 -or
        $RepositoryUri.Contains("`r") -or $RepositoryUri.Contains("`n")
    ) { throw 'REPOSITORY_URI_INVALID' }
}

function Get-CddsiFastLaneGitRepositoryPath {
    param([string]$StateRoot, [string]$RepositoryIdentity)
    $token = Get-CddsiSupplyChainTextBindingToken -Text $RepositoryIdentity
    # This short discriminator is only a cache path. Full repository identity
    # and URI hashes remain bound in owner/state records, so any collision
    # fails closed while WinPS 5.1 teardown stays below MAX_PATH.
    return Join-Path $StateRoot ('r-' + $token.Substring(0, 16))
}

function Initialize-CddsiFastLaneLocalGitRepository {
    param(
        [hashtable]$Context,
        [string]$RepositoryPath
    )
    if (-not [IO.Directory]::Exists($RepositoryPath)) {
        [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @('init', '--bare', '--quiet', $RepositoryPath) -LocalMutation)
    }
}

function Get-CddsiFastLaneRemoteSnapshot {
    param(
        [hashtable]$Context,
        [string]$RepositoryPath,
        [string]$RepositoryUri,
        [string]$RemoteRef,
        [string]$ExpectedGenesisCommit,
        [AllowNull()][string]$AcceptedRemoteHead
    )
    $stagingRef = 'refs/cddsi/remote-snapshot'
    [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'fetch', '--quiet', '--no-tags',
        '--no-write-fetch-head', '--no-recurse-submodules',
        $RepositoryUri, ('+' + $RemoteRef + ':' + $stagingRef)
    ) -OperatorTransport -LocalMutation)
    $headResult = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(('--git-dir=' + $RepositoryPath), 'rev-parse', '--verify', $stagingRef)
    $head = $headResult.StandardOutput.Trim()
    if (-not (Test-CddsiFastLaneGitSha $head)) { throw 'REMOTE_HEAD_INVALID' }
    $rootsResult = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(('--git-dir=' + $RepositoryPath), 'rev-list', '--max-parents=0', $head)
    $roots = @($rootsResult.StandardOutput -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    if ($roots.Count -ne 1 -or $roots[0] -cne $ExpectedGenesisCommit) { throw 'PINNED_GENESIS_MISMATCH' }
    $genesisCheck = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'merge-base', '--is-ancestor', $ExpectedGenesisCommit, $head
    ) -AllowedExitCodes @(0, 1)
    if ($genesisCheck.ExitCode -ne 0) { throw 'PINNED_GENESIS_NOT_ANCESTOR' }
    if (-not [string]::IsNullOrEmpty($AcceptedRemoteHead)) {
        $ancestry = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
            ('--git-dir=' + $RepositoryPath), 'merge-base', '--is-ancestor', $AcceptedRemoteHead, $head
        ) -AllowedExitCodes @(0, 1)
        if ($ancestry.ExitCode -ne 0) { throw 'REMOTE_HISTORY_REWRITE' }
    }
    return [pscustomobject]@{ Head = $head; StagingRef = $stagingRef }
}

function Get-CddsiFastLaneNextCommit {
    param(
        [hashtable]$Context,
        [string]$RepositoryPath,
        [string]$Cursor,
        [string]$Head,
        [long]$RemainingCount
    )
    $skip = $RemainingCount - 1
    $result = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'rev-list', '--first-parent', '--max-count=1', ('--skip=' + $skip), ($Cursor + '..' + $Head)
    )
    $commit = $result.StandardOutput.Trim()
    if (-not (Test-CddsiFastLaneGitSha $commit)) { throw 'REMOTE_COMMIT_INVALID' }
    $parentsResult = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'rev-list', '--parents', '--max-count=1', $commit
    )
    $parts = @($parentsResult.StandardOutput.Trim() -split ' ')
    if ($parts.Count -ne 2 -or $parts[0] -cne $commit -or $parts[1] -cne $Cursor) { throw 'REMOTE_HISTORY_NOT_LINEAR' }
    return $commit
}

function Read-CddsiFastLaneMessageAtCommit {
    param(
        [hashtable]$Context,
        [string]$RepositoryPath,
        [string]$Commit
    )
    $diff = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'diff-tree', '--no-commit-id', '--name-status', '-r', '--no-renames', $Commit
    )
    $lines = @($diff.StandardOutput -split "`r?`n" | Where-Object { $_.Length -gt 0 })
    if ($lines.Count -ne 1 -or $lines[0] -cnotmatch '^A\toutbox/([0-9]{12})-([a-f0-9-]{36})\.json$') {
        throw 'OUTBOX_APPEND_ONLY_COMMIT_INVALID'
    }
    $sequenceText = $Matches[1]
    $messageId = $Matches[2]
    $path = $lines[0].Substring(2)
    $blob = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'show', ($Commit + ':' + $path)
    )
    $text = $blob.StandardOutput
    if (-not $text.EndsWith("`n") -or $text.EndsWith("`r`n")) { throw 'OUTBOX_CANONICAL_TERMINATOR_INVALID' }
    $json = $text.Substring(0, $text.Length - 1)
    try { $message = ConvertTo-CddsiFastLaneJsonData (ConvertFrom-Json -InputObject $json -ErrorAction Stop) }
    catch { throw 'OUTBOX_JSON_INVALID' }
    if (-not (Test-CddsiExactPropertySet -InputObject $message -Expected @('Envelope', 'Payload'))) { throw 'OUTBOX_MESSAGE_SCHEMA_INVALID' }
    if ((ConvertTo-CddsiVmTestRelayCanonicalJson -Value $message) -cne $json) { throw 'OUTBOX_JSON_NOT_CANONICAL' }
    $expectedSequenceText = ([long]$message.Envelope.Sequence).ToString('D12', [Globalization.CultureInfo]::InvariantCulture)
    if ($expectedSequenceText -cne $sequenceText -or $message.Envelope.MessageId -cne $messageId) {
        throw 'OUTBOX_FILENAME_BINDING_MISMATCH'
    }
    return [pscustomobject]@{ Path = $path; Message = $message }
}

function Assert-CddsiFastLaneExpectedWakePointer {
    param(
        [Parameter(Mandatory = $true)]$Pointer,
        [Parameter(Mandatory = $true)][ValidateSet('Poll', 'Publish')][string]$Operation,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$AuthenticatedOutbox,
        [Parameter(Mandatory = $true)][long]$ExpectedRepositoryNumericId,
        [Parameter(Mandatory = $true)][string]$RemoteRef
    )

    if ($Operation -cne 'Poll') { throw 'WAKE_POINTER_POLL_ONLY' }
    if (-not (Test-CddsiExactPropertySet -InputObject $Pointer -Expected @(
        'SchemaVersion', 'Verb', 'Lane', 'MessageId', 'Sequence',
        'RepositoryId', 'Ref', 'Commit', 'PayloadSha256'
    ))) { throw 'WAKE_POINTER_SCHEMA_INVALID' }
    foreach ($propertyName in @(
        'SchemaVersion', 'Verb', 'Lane', 'MessageId', 'RepositoryId',
        'Ref', 'Commit', 'PayloadSha256'
    )) {
        if ($Pointer.$propertyName -isnot [string]) { throw 'WAKE_POINTER_FIELD_TYPE_INVALID' }
    }
    if (
        $Pointer.SchemaVersion -cne 'cddsi-realtime-relay-wake-event-v1' -or
        $Pointer.Verb -cne 'CONTROL_REPO_POINTER_AVAILABLE'
    ) { throw 'WAKE_POINTER_CONTRACT_INVALID' }
    if ($Pointer.Lane -cne $AuthenticatedOutbox) { throw 'WAKE_POINTER_OUTBOX_MISMATCH' }
    if ($Pointer.MessageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
        throw 'WAKE_POINTER_MESSAGE_ID_INVALID'
    }
    if (
        ($Pointer.Sequence -isnot [int] -and $Pointer.Sequence -isnot [long]) -or
        [long]$Pointer.Sequence -lt 1 -or [long]$Pointer.Sequence -gt 9007199254740991L
    ) { throw 'WAKE_POINTER_SEQUENCE_INVALID' }
    $expectedRepositoryId = $ExpectedRepositoryNumericId.ToString(
        [Globalization.CultureInfo]::InvariantCulture)
    if (
        $Pointer.RepositoryId -cnotmatch '^[1-9][0-9]{0,18}$' -or
        $Pointer.RepositoryId -cne $expectedRepositoryId
    ) { throw 'WAKE_POINTER_REPOSITORY_ID_MISMATCH' }
    if ($Pointer.Ref -cne 'refs/heads/main' -or $Pointer.Ref -cne $RemoteRef) {
        throw 'WAKE_POINTER_REF_MISMATCH'
    }
    if ($Pointer.Commit -cnotmatch '^[a-f0-9]{40}$') { throw 'WAKE_POINTER_COMMIT_INVALID' }
    if ($Pointer.PayloadSha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'WAKE_POINTER_PAYLOAD_HASH_INVALID' }
}

function Assert-CddsiFastLaneWakePointerTarget {
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$RepositoryPath,
        [Parameter(Mandatory = $true)]$Pointer
    )

    $record = Read-CddsiFastLaneMessageAtCommit -Context $Context `
        -RepositoryPath $RepositoryPath -Commit $Pointer.Commit
    if ($record.Message.Envelope.MessageId -cne $Pointer.MessageId) {
        throw 'WAKE_POINTER_MESSAGE_ID_MISMATCH'
    }
    $payloadSha256 = Get-CddsiVmTestRelayPayloadSha256 -Payload $record.Message.Payload
    if (
        $payloadSha256 -cne $Pointer.PayloadSha256 -or
        $record.Message.Envelope.PayloadSha256 -cne $Pointer.PayloadSha256
    ) { throw 'WAKE_POINTER_PAYLOAD_HASH_MISMATCH' }
    return $record
}

function New-CddsiFastLaneWakeReceipt {
    param(
        [Parameter(Mandatory = $true)]$Pointer,
        [Parameter(Mandatory = $true)][ValidateSet('CONSUMED_NOW', 'ALREADY_CONSUMED')][string]$Status
    )

    return [pscustomobject][ordered]@{
        SchemaVersion              = 1
        ContractVersion            = 'cddsi-fast-lane-wake-receipt-v1'
        Status                     = $Status
        Lane                       = $Pointer.Lane
        MessageId                  = $Pointer.MessageId
        Sequence                   = [long]$Pointer.Sequence
        RepositoryId               = $Pointer.RepositoryId
        Ref                        = $Pointer.Ref
        Commit                     = $Pointer.Commit
        PayloadSha256              = $Pointer.PayloadSha256
        FixedEntryInvoked          = $true
        Consumed                   = $true
        RepositoryIdentityVerified = $true
        PayloadSha256Verified      = $true
    }
}

function New-CddsiFastLaneGitCommit {
    param(
        [hashtable]$Context,
        [string]$RepositoryPath,
        [string]$BaseCommit,
        [string]$FileName,
        [string]$CanonicalMessage
    )
    $existing = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'ls-tree', '-r', '--name-only', $BaseCommit, '--', ('outbox/' + $FileName)
    )
    if ($existing.StandardOutput.Trim().Length -ne 0) { throw 'PUBLISHED_MESSAGE_PATH_EXISTS' }
    $outboxDirectory = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'ls-tree', '-d', '--name-only', $BaseCommit, '--', 'outbox'
    )
    if ($outboxDirectory.StandardOutput.Trim() -cne 'outbox') { throw 'OUTBOX_DIRECTORY_MISSING' }

    $messageInputPath = Join-Path $Context.StateRoot ('.cddsi-git-message-' + [guid]::NewGuid().ToString('D') + '.tmp')
    $messageBytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes($CanonicalMessage + "`n")
    Write-CddsiFastLaneAtomicBytes -Path $messageInputPath -Bytes $messageBytes -CreateOnly
    $Context.LocalStateMutationCount = [int]$Context.LocalStateMutationCount + 1
    try {
        $blobResult = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
            ('--git-dir=' + $RepositoryPath), 'hash-object', '--no-filters', '-w', '--', $messageInputPath
        ) -LocalMutation
        $blob = $blobResult.StandardOutput.Trim()
    }
    finally {
        if ([IO.File]::Exists($messageInputPath)) {
            [IO.File]::Delete($messageInputPath)
            $Context.LocalStateMutationCount = [int]$Context.LocalStateMutationCount + 1
        }
    }
    if (-not (Test-CddsiFastLaneGitSha $blob)) { throw 'PUBLISHED_BLOB_INVALID' }

    $indexPath = Join-Path $Context.StateRoot ('.cddsi-git-index-' + [guid]::NewGuid().ToString('D'))
    $indexEnvironment = @{ GIT_INDEX_FILE = $indexPath }
    try {
        [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
            ('--git-dir=' + $RepositoryPath), 'read-tree', $BaseCommit
        ) -AdditionalEnvironment $indexEnvironment -LocalMutation)
        [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
            ('--git-dir=' + $RepositoryPath), 'update-index', '--add', '--cacheinfo',
            '100644', $blob, ('outbox/' + $FileName)
        ) -AdditionalEnvironment $indexEnvironment -LocalMutation)
        $rootTreeResult = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
            ('--git-dir=' + $RepositoryPath), 'write-tree'
        ) -AdditionalEnvironment $indexEnvironment -LocalMutation
        $rootTree = $rootTreeResult.StandardOutput.Trim()
    }
    finally {
        foreach ($temporaryIndexPath in @($indexPath + '.lock', $indexPath)) {
            if ([IO.File]::Exists($temporaryIndexPath)) {
                [IO.File]::Delete($temporaryIndexPath)
                $Context.LocalStateMutationCount = [int]$Context.LocalStateMutationCount + 1
            }
        }
    }
    if (-not (Test-CddsiFastLaneGitSha $rootTree)) { throw 'PUBLISHED_ROOT_TREE_INVALID' }

    $timestamp = [DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ssZ')
    $commitResult = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'commit-tree', $rootTree, '-p', $BaseCommit,
        '-m', ('CDDsi Fast Lane append ' + $FileName)
    ) -AdditionalEnvironment @{
        GIT_AUTHOR_NAME = 'CDDsi Fast Lane Operator'; GIT_AUTHOR_EMAIL = 'cddsi-fast-lane@invalid'
        GIT_COMMITTER_NAME = 'CDDsi Fast Lane Operator'; GIT_COMMITTER_EMAIL = 'cddsi-fast-lane@invalid'
        GIT_AUTHOR_DATE = $timestamp; GIT_COMMITTER_DATE = $timestamp
    } -LocalMutation
    $commit = $commitResult.StandardOutput.Trim()
    if (-not (Test-CddsiFastLaneGitSha $commit)) { throw 'PUBLISHED_COMMIT_INVALID' }
    return $commit
}

function Invoke-CddsiFastLaneGitOutbox {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Poll', 'Publish')][string]$Operation,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeOperatorPlaneLive,
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$OperatorWorkspaceRoot,
        [Parameter(Mandatory = $true)][string]$GitExecutable,
        [Parameter(Mandatory = $true)][string]$GitExecutableSha256,
        [Parameter(Mandatory = $true)][string]$RunnerSha256,
        [Parameter(Mandatory = $true)][string]$RepositoryUri,
        [Parameter(Mandatory = $true)][string]$RepositoryIdentity,
        [Parameter(Mandatory = $true)]$ProtectionEvidence,
        [Parameter(Mandatory = $true)][string]$ProtectionEvidenceSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedRepositoryNumericId,
        [Parameter(Mandatory = $true)][string]$ExpectedRepositoryNodeId,
        [Parameter(Mandatory = $true)][ValidateSet('PUBLIC')][string]$ExpectedRepositoryVisibility,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthority,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionPolicySha256,
        [Parameter(Mandatory = $true)][string]$ProtectionTrustRoot,
        [Parameter(Mandatory = $true)][string]$ProtectionAuthorityAssertionPath,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthorityAssertionSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProtectionAuthorityBindingToken,
        [Parameter(Mandatory = $true)][string]$CredentialProfileId,
        [AllowNull()][string]$SshExecutable = $null,
        [AllowNull()][string]$SshExecutableSha256 = $null,
        [AllowNull()][string]$ExpectedSshExecutableSha256 = $null,
        [AllowNull()][string]$DeployKeyPath = $null,
        [AllowNull()][string]$DeployKeySha256 = $null,
        [AllowNull()][string]$ExpectedDeployKeySha256 = $null,
        [AllowNull()][string]$KnownHostsPath = $null,
        [AllowNull()][string]$KnownHostsSha256 = $null,
        [AllowNull()][string]$ExpectedKnownHostsSha256 = $null,
        [Parameter(Mandatory = $true)][string]$ExpectedGenesisCommit,
        [string]$RemoteRef = 'refs/heads/main',
        [Parameter(Mandatory = $true)][string]$HostToVmRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$VmToHostRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$ProductRepositoryIdentity,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$AuthenticatedOutbox,
        [Parameter(Mandatory = $true)][ValidateSet('HostCoordinator', 'VmTester')][string[]]$AuthenticatedSenderRoles,
        [AllowNull()]$ExpectedWakePointer = $null,
        [AllowNull()]$Message = $null,
        [AllowNull()][string]$ExpectedRemoteHead = $null,
        [AllowNull()][string]$SnapshotTrustRoot = $null,
        [AllowNull()][string]$SnapshotTrustAssertionPath = $null,
        [AllowNull()][string]$ExpectedSnapshotTrustAssertionSha256 = $null,
        [AllowNull()][string]$ExternallyVerifiedSnapshotReceiptSha256 = $null,
        [AllowNull()][string]$ExternallyVerifiedSnapshotAuthorityBindingToken = $null,
        [ValidateSet('None', 'AfterRemotePushBeforeStatePersist')][string]$FailureInjection = 'None',
        [string]$ValidationTimeUtc = ([DateTimeOffset]::UtcNow.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')),
        [ValidateRange(1, 32)][int]$MaximumMessageCount = 32,
        [ValidateRange(0, 0)][int]$MaximumRetryCount = 0,
        [ValidateRange(5, 45)][int]$MaximumRuntimeSeconds = 45,
        [ValidateRange(1, 45)][int]$MaximumGitCommandSeconds = 30,
        [ValidateRange(4096, 65536)][int]$MaximumOutputBytes = 65536,
        [ValidateRange(64, 65536)][int]$MaximumMessageBodyBytes = 65536,
        [ValidateRange(1, 900)][int]$MaximumAgeSeconds = 900,
        [ValidateRange(0, 120)][int]$MaximumClockSkewSeconds = 120,
        [ValidateRange(60, 3600)][int]$ProtectionEvidenceMaximumAgeSeconds = 3600,
        [ValidateRange(60, 3600)][int]$SnapshotTrustMaximumAgeSeconds = 3600
    )

    foreach ($required in @(
        'ConvertTo-CddsiVmTestRelayCanonicalJson', 'Get-CddsiSupplyChainTextBindingToken',
        'Get-CddsiVmTestRelayMessageSha256', 'Get-CddsiVmTestRelayPayloadSha256',
        'New-CddsiVmTestRelayState', 'Test-CddsiVmTestRelayState',
        'Resolve-CddsiVmTestRelayTransition', 'Test-CddsiExactPropertySet'
    )) {
        if ($null -eq (Get-Command -Name $required -CommandType Function -ErrorAction SilentlyContinue)) {
            throw ('REQUIRED_CONTRACT_NOT_LOADED:' + $required)
        }
    }
    if (-not (Test-CddsiFastLaneSafeStateRoot -StateRoot $StateRoot)) { throw 'STATE_ROOT_NOT_OWNER_SCOPED' }
    $fullStateRoot = [IO.Path]::GetFullPath($StateRoot)
    $workspaceBinding = Assert-CddsiFastLaneOperatorWorkspace -StateRoot $fullStateRoot `
        -ProductRoot $ProductRoot -OperatorWorkspaceRoot $OperatorWorkspaceRoot
    if (-not [IO.Path]::IsPathRooted($GitExecutable) -or -not [IO.File]::Exists($GitExecutable)) { throw 'GIT_EXECUTABLE_INVALID' }
    if ($GitExecutableSha256 -cnotmatch '^[a-f0-9]{64}$' -or (Get-CddsiFastLaneGitFileSha256 -Path $GitExecutable) -cne $GitExecutableSha256) {
        throw 'GIT_EXECUTABLE_HASH_MISMATCH'
    }
    if (
        $RunnerSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]::IsNullOrEmpty($script:CddsiFastLaneGitOutboxRunnerPath) -or
        (Get-CddsiFastLaneGitFileSha256 -Path $script:CddsiFastLaneGitOutboxRunnerPath) -cne $RunnerSha256
    ) { throw 'RUNNER_HASH_MISMATCH' }
    Assert-CddsiFastLaneRepositoryUri -RepositoryUri $RepositoryUri
    if (-not (Test-CddsiFastLaneGitSha $ExpectedGenesisCommit)) { throw 'EXPECTED_GENESIS_INVALID' }
    if ($RemoteRef -cne 'refs/heads/main') { throw 'REMOTE_REF_NOT_ALLOWED' }
    if (
        $HostToVmRepositoryIdentity -ceq $VmToHostRepositoryIdentity -or
        $HostToVmRepositoryIdentity -ceq $ProductRepositoryIdentity -or
        $VmToHostRepositoryIdentity -ceq $ProductRepositoryIdentity
    ) { throw 'REPOSITORY_IDENTITIES_NOT_DISTINCT' }
    $expectedPhysicalIdentity = if ($AuthenticatedOutbox -ceq 'host-to-vm') { $HostToVmRepositoryIdentity } else { $VmToHostRepositoryIdentity }
    if ($RepositoryIdentity -cne $expectedPhysicalIdentity -or $RepositoryIdentity -ceq $ProductRepositoryIdentity) {
        throw 'OPERATOR_CONTROL_REPOSITORY_IDENTITY_MISMATCH'
    }
    if ($CredentialProfileId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$') { throw 'CREDENTIAL_PROFILE_ID_INVALID' }
    $transportProfile = Get-CddsiFastLaneTransportProfile -RepositoryUri $RepositoryUri `
        -RepositoryIdentity $RepositoryIdentity -CredentialProfileId $CredentialProfileId
    $credentialBinding = Get-CddsiFastLaneCredentialBinding -RepositoryIdentity $RepositoryIdentity `
        -AuthenticatedOutbox $AuthenticatedOutbox -CredentialProfileId $CredentialProfileId `
        -TransportKind $transportProfile.Kind -ExpectedProtectionAuthority $ExpectedProtectionAuthority `
        -Operation $Operation
    if ($null -ne $ExpectedWakePointer) {
        Assert-CddsiFastLaneExpectedWakePointer -Pointer $ExpectedWakePointer -Operation $Operation `
            -AuthenticatedOutbox $AuthenticatedOutbox `
            -ExpectedRepositoryNumericId $ExpectedRepositoryNumericId -RemoteRef $RemoteRef
    }
    $sshCommand = $null
    if ($transportProfile.Kind -ceq 'Ssh') {
        foreach ($requiredSshValue in @(
            $SshExecutable, $SshExecutableSha256, $ExpectedSshExecutableSha256,
            $DeployKeyPath, $DeployKeySha256, $ExpectedDeployKeySha256,
            $KnownHostsPath, $KnownHostsSha256, $ExpectedKnownHostsSha256
        )) {
            if ([string]::IsNullOrEmpty([string]$requiredSshValue)) { throw 'SSH_PROFILE_BINDING_REQUIRED' }
        }
        if (
            $ExpectedSshExecutableSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedDeployKeySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedKnownHostsSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $SshExecutableSha256 -cne $ExpectedSshExecutableSha256 -or
            $DeployKeySha256 -cne $ExpectedDeployKeySha256 -or
            $KnownHostsSha256 -cne $ExpectedKnownHostsSha256
        ) { throw 'SSH_FROZEN_TRUST_BINDING_MISMATCH' }
        Assert-CddsiFastLanePinnedFile $SshExecutable $SshExecutableSha256 'SSH_EXECUTABLE'
        if (Test-CddsiFastLanePathWithinRoot -Path $DeployKeyPath -Root $fullStateRoot) {
            throw 'DEPLOY_KEY_INSIDE_STATE_ROOT_FORBIDDEN'
        }
        Assert-CddsiFastLanePinnedFile $DeployKeyPath $DeployKeySha256 'DEPLOY_KEY'
        Assert-CddsiFastLanePinnedFile $KnownHostsPath $KnownHostsSha256 'KNOWN_HOSTS'
        $sshCommand = (ConvertTo-CddsiFastLaneSshCommandArgument ([IO.Path]::GetFullPath($SshExecutable))) +
            ' -F NUL -i ' + (ConvertTo-CddsiFastLaneSshCommandArgument ([IO.Path]::GetFullPath($DeployKeyPath))) +
            ' -o ' + (ConvertTo-CddsiFastLaneSshCommandArgument ('UserKnownHostsFile=' + [IO.Path]::GetFullPath($KnownHostsPath))) +
            ' -o StrictHostKeyChecking=yes -o IdentitiesOnly=yes -o BatchMode=yes' +
            ' -o PasswordAuthentication=no -o KbdInteractiveAuthentication=no'
    }
    elseif (@(@(
        $SshExecutable, $SshExecutableSha256, $ExpectedSshExecutableSha256,
        $DeployKeyPath, $DeployKeySha256, $ExpectedDeployKeySha256,
        $KnownHostsPath, $KnownHostsSha256, $ExpectedKnownHostsSha256
    ) |
        Where-Object { -not [string]::IsNullOrEmpty([string]$_) }).Count -ne 0) {
        throw 'LOCAL_TRANSPORT_SSH_BINDING_FORBIDDEN'
    }
    Assert-CddsiFastLaneProtectionEvidence -Evidence $ProtectionEvidence `
        -EvidenceSha256 $ProtectionEvidenceSha256 -RepositoryIdentity $RepositoryIdentity -RemoteRef $RemoteRef `
        -ExpectedRepositoryNumericId $ExpectedRepositoryNumericId -ExpectedRepositoryNodeId $ExpectedRepositoryNodeId `
        -ExpectedRepositoryVisibility $ExpectedRepositoryVisibility `
        -ExpectedProtectionAuthority $ExpectedProtectionAuthority `
        -ExpectedProtectionPolicySha256 $ExpectedProtectionPolicySha256 `
        -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $ProtectionEvidenceMaximumAgeSeconds `
        -MaximumClockSkewSeconds $MaximumClockSkewSeconds
    $protectionAuthorityTrust = Assert-CddsiFastLaneProtectionAuthorityAssertion `
        -StateRoot $fullStateRoot -ProductRoot $ProductRoot -OperatorWorkspaceRoot $OperatorWorkspaceRoot `
        -ProtectionTrustRoot $ProtectionTrustRoot `
        -ProtectionAuthorityAssertionPath $ProtectionAuthorityAssertionPath `
        -ExpectedProtectionAuthorityAssertionSha256 $ExpectedProtectionAuthorityAssertionSha256 `
        -ExpectedProtectionAuthorityBindingToken $ExpectedProtectionAuthorityBindingToken `
        -ProtectionEvidence $ProtectionEvidence -ProtectionEvidenceSha256 $ProtectionEvidenceSha256 `
        -ExpectedProtectionAuthority $ExpectedProtectionAuthority `
        -ExpectedProtectionPolicySha256 $ExpectedProtectionPolicySha256 `
        -RepositoryIdentity $RepositoryIdentity -ExpectedRepositoryNumericId $ExpectedRepositoryNumericId `
        -ExpectedRepositoryNodeId $ExpectedRepositoryNodeId -RemoteRef $RemoteRef
    if ($AuthenticatedSenderRoles.Count -ne 1 -or $AuthenticatedSenderRoles[0] -cne $credentialBinding.Role) {
        throw 'AUTHENTICATED_ROLE_NOT_FROZEN_FOR_CREDENTIAL'
    }
    $snapshotTrust = Assert-CddsiFastLaneExternalSnapshotTrust -StateRoot $fullStateRoot `
        -ProductRoot $ProductRoot -OperatorWorkspaceRoot $OperatorWorkspaceRoot `
        -SnapshotTrustRoot $SnapshotTrustRoot -SnapshotTrustAssertionPath $SnapshotTrustAssertionPath `
        -ExpectedSnapshotTrustAssertionSha256 $ExpectedSnapshotTrustAssertionSha256 `
        -ExternallyVerifiedSnapshotReceiptSha256 $ExternallyVerifiedSnapshotReceiptSha256 `
        -ExternallyVerifiedSnapshotAuthorityBindingToken $ExternallyVerifiedSnapshotAuthorityBindingToken `
        -HostToVmRepositoryIdentity $HostToVmRepositoryIdentity `
        -VmToHostRepositoryIdentity $VmToHostRepositoryIdentity `
        -ProductRepositoryIdentity $ProductRepositoryIdentity -RepositoryIdentity $RepositoryIdentity `
        -AuthenticatedOutbox $AuthenticatedOutbox -ValidationTimeUtc $ValidationTimeUtc `
        -MaximumAgeSeconds $SnapshotTrustMaximumAgeSeconds -MaximumClockSkewSeconds $MaximumClockSkewSeconds
    if ($FailureInjection -cne 'None' -and ($Operation -cne 'Publish' -or $transportProfile.Kind -cne 'LocalFile')) {
        throw 'FAILURE_INJECTION_SYNTHETIC_PUBLISH_ONLY'
    }
    if ($Operation -ceq 'Publish') {
        if (
            $null -eq $Message -or -not (Test-CddsiFastLaneGitSha $ExpectedRemoteHead) -or
            -not (Test-CddsiExactPropertySet -InputObject $Message -Expected @('Envelope', 'Payload'))
        ) { throw 'PUBLISH_INPUT_REQUIRED' }
        if ($Message.Envelope.MessageType -ceq 'SNAPSHOT_READY') {
            if ($null -eq $snapshotTrust) { throw 'SNAPSHOT_TRUST_ASSERTION_REQUIRED' }
        }
        elseif ($null -ne $snapshotTrust) { throw 'SNAPSHOT_TRUST_INPUT_NOT_APPLICABLE' }
    }
    elseif ($null -ne $Message -or -not [string]::IsNullOrEmpty($ExpectedRemoteHead)) { throw 'POLL_INPUT_INVALID' }

    $effectiveMaximumMessageCount = if ($null -ne $ExpectedWakePointer) { 1 } else { $MaximumMessageCount }

    if ($Mode -cne 'Live') {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = $script:CddsiFastLaneGitOutboxResultContract
            Operation = $Operation; Mode = $Mode; Status = 'PLANNED'; OperatorPlaneOnly = $true
            RepositoryIdentity = $RepositoryIdentity; RemoteHead = $null; ProcessedMessageCount = 0
            PublishedPath = $null; PublishedCommit = $null; MoreAvailable = $false
            RecoveredPublishCount = 0; ProtectionReceiptRotated = $false
            GitExecutableSha256 = $GitExecutableSha256; RunnerSha256 = $RunnerSha256
            ProtectionEvidenceSha256 = $ProtectionEvidenceSha256; CredentialProfileId = $CredentialProfileId
            ProtectionAuthority = $ExpectedProtectionAuthority; ProtectionPolicySha256 = $ExpectedProtectionPolicySha256
            ProtectionAuthorityAssertionSha256 = $protectionAuthorityTrust.AssertionSha256
            ProtectionAuthorityBindingToken = $protectionAuthorityTrust.AuthorityBindingToken
            ProductRootPathSha256 = $workspaceBinding.ProductRootPathSha256
            OperatorWorkspacePathSha256 = $workspaceBinding.OperatorWorkspacePathSha256
            SnapshotTrustAssertionSha256 = $(if ($null -ne $snapshotTrust) { $snapshotTrust.AssertionSha256 } else { $null })
            SnapshotTrustInputSource = $(if ($null -ne $snapshotTrust) { 'ProtectedOperatorWorkspace' } else { $null })
            AuthenticatedSenderRole = $credentialBinding.Role
            TransportKind = $transportProfile.Kind
            SshExecutableSha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $SshExecutableSha256 } else { $null })
            DeployKeySha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $DeployKeySha256 } else { $null })
            KnownHostsSha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $KnownHostsSha256 } else { $null })
            GitInvocationCount = 0; OperatorGitTransportCount = 0; OperatorRemoteMutationCount = 0
            JobAssignmentCount = 0; ProcessTreeTerminationCount = 0
            LocalStateMutationCount = 0; ProductNetworkRequestCount = 0
            HostProductLiveInvocationCount = 0; VmProductWriteCount = 0
            MaximumMessageCount = $effectiveMaximumMessageCount; MaximumRuntimeSeconds = $MaximumRuntimeSeconds
            MaximumOutputBytes = $MaximumOutputBytes; MaximumMessageBodyBytes = $MaximumMessageBodyBytes
            MaximumAgeSeconds = $MaximumAgeSeconds; MaximumClockSkewSeconds = $MaximumClockSkewSeconds
            MaximumRetryCount = $MaximumRetryCount; RetryCount = 0
            ChildEnvironmentInheritedCount = 0; ProcessJobRequired = $true; RelayState = $null
            WakeReceipt = $null
        }
    }
    if (-not $AcknowledgeOperatorPlaneLive) { throw 'OPERATOR_PLANE_LIVE_CONFIRMATION_REQUIRED' }

    Initialize-CddsiFastLaneBoundedProcessType
    $rootExisted = [IO.Directory]::Exists($fullStateRoot)
    if (-not $rootExisted) { [void][IO.Directory]::CreateDirectory($fullStateRoot) }
    if (([IO.DirectoryInfo]::new($fullStateRoot).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'STATE_ROOT_REPARSE_POINT_FORBIDDEN' }
    $lockPath = Join-Path $fullStateRoot '.cddsi.lock'
    try { $lock = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None) }
    catch { throw 'FAST_LANE_SINGLE_INSTANCE_LOCKED' }
    try {
        $ownerPath = Join-Path $fullStateRoot '.cddsi-owner.json'
        $statePath = Join-Path $fullStateRoot 'state.json'
        $expectedOwner = New-CddsiFastLaneGitOwner $HostToVmRepositoryIdentity $VmToHostRepositoryIdentity `
            $ProductRepositoryIdentity $GitExecutableSha256 $RunnerSha256 `
            $workspaceBinding.ProductRootPathSha256 $workspaceBinding.OperatorWorkspacePathSha256
        if (-not $rootExisted) {
            Write-CddsiFastLaneCanonicalFile -Path $ownerPath -Value $expectedOwner -CreateOnly
            $state = New-CddsiFastLaneGitState $HostToVmRepositoryIdentity $VmToHostRepositoryIdentity `
                $ProductRepositoryIdentity $GitExecutableSha256 $RunnerSha256 `
                $workspaceBinding.ProductRootPathSha256 $workspaceBinding.OperatorWorkspacePathSha256
            Write-CddsiFastLaneCanonicalFile -Path $statePath -Value $state -CreateOnly
        }
        else {
            $owner = Read-CddsiFastLaneCanonicalFile -Path $ownerPath -MaximumBytes 8192
            if ((ConvertTo-CddsiVmTestRelayCanonicalJson $owner) -cne (ConvertTo-CddsiVmTestRelayCanonicalJson $expectedOwner)) {
                throw 'STATE_ROOT_OWNER_MISMATCH'
            }
            $state = Read-CddsiFastLaneCanonicalFile -Path $statePath -MaximumBytes 1048576
        }
        Assert-CddsiFastLaneGitState $state $HostToVmRepositoryIdentity $VmToHostRepositoryIdentity `
            $ProductRepositoryIdentity $GitExecutableSha256 $RunnerSha256 `
            $workspaceBinding.ProductRootPathSha256 $workspaceBinding.OperatorWorkspacePathSha256

        $context = @{
            StateRoot = $fullStateRoot; GitExecutable = [IO.Path]::GetFullPath($GitExecutable)
            MaximumRuntimeSeconds = $MaximumRuntimeSeconds; MaximumGitCommandSeconds = $MaximumGitCommandSeconds
            MaximumOutputBytes = $MaximumOutputBytes; Stopwatch = [Diagnostics.Stopwatch]::StartNew()
            GitInvocationCount = 0; OperatorGitTransportCount = 0; OperatorRemoteMutationCount = 0
            JobAssignmentCount = 0; ProcessTreeTerminationCount = 0
            LocalStateMutationCount = $(if ($rootExisted) { 0 } else { 4 })
            TransportKind = $transportProfile.Kind; SshCommand = $sshCommand
        }
        $uriSha = Get-CddsiSupplyChainTextBindingToken -Text $RepositoryUri
        $entry = Get-CddsiFastLaneRepositoryEntry $state $RepositoryIdentity
        if ($null -ne $entry -and $entry.RepositoryUriSha256 -cne $uriSha) {
            throw 'LOCAL_REMOTE_BINDING_MISMATCH'
        }
        $repositoryPath = Get-CddsiFastLaneGitRepositoryPath $fullStateRoot $RepositoryIdentity
        Initialize-CddsiFastLaneLocalGitRepository $context $repositoryPath
        $receiptRotated = $false
        if ($null -ne $entry) {
            if (
                $entry.RepositoryUriSha256 -cne $uriSha -or $entry.GenesisCommit -cne $ExpectedGenesisCommit -or
                $entry.RemoteRef -cne $RemoteRef -or
                [long]$entry.RepositoryNumericId -ne [long]$ProtectionEvidence.RepositoryNumericId -or
                $entry.RepositoryNodeId -cne $ProtectionEvidence.RepositoryNodeId -or
                $entry.ProtectionAuthority -cne $ExpectedProtectionAuthority -or
                $entry.ProtectionPolicySha256 -cne $ExpectedProtectionPolicySha256 -or
                $entry.ProtectionAuthorityBindingToken -cne $protectionAuthorityTrust.AuthorityBindingToken -or
                $entry.CredentialProfileId -cne $CredentialProfileId -or
                $entry.TransportKind -cne $transportProfile.Kind -or
                $entry.SshExecutableSha256 -cne $(if ($transportProfile.Kind -ceq 'Ssh') { $SshExecutableSha256 } else { $null }) -or
                $entry.DeployKeySha256 -cne $(if ($transportProfile.Kind -ceq 'Ssh') { $DeployKeySha256 } else { $null }) -or
                $entry.KnownHostsSha256 -cne $(if ($transportProfile.Kind -ceq 'Ssh') { $KnownHostsSha256 } else { $null })
            ) { throw 'CONTROL_REPOSITORY_BINDING_MISMATCH' }
            if ($entry.ProtectionEvidenceSha256 -ceq $ProtectionEvidenceSha256) {
                if (
                    $entry.ProtectionObservedAtUtc -cne $ProtectionEvidence.ObservedAtUtc -or
                    $entry.ProtectionValidUntilUtc -cne $ProtectionEvidence.ValidUntilUtc -or
                    $entry.ProtectionReceiptId -cne $ProtectionEvidence.ReceiptId -or
                    $entry.ProtectionAuthorityAssertionSha256 -cne $protectionAuthorityTrust.AssertionSha256
                ) { throw 'PROTECTION_RECEIPT_STATE_MISMATCH' }
            }
            else {
                if ($ProtectionEvidence.PreviousReceiptSha256 -cne $entry.ProtectionEvidenceSha256) {
                    throw 'PROTECTION_RECEIPT_ROLLBACK_OR_FORK'
                }
                $previousObserved = [DateTimeOffset]::Parse($entry.ProtectionObservedAtUtc)
                $previousValidUntil = [DateTimeOffset]::Parse($entry.ProtectionValidUntilUtc)
                $nextObserved = [DateTimeOffset]::Parse($ProtectionEvidence.ObservedAtUtc)
                $nextValidUntil = [DateTimeOffset]::Parse($ProtectionEvidence.ValidUntilUtc)
                if (
                    $nextObserved -le $previousObserved -or
                    $nextValidUntil -le $previousValidUntil -or
                    $ProtectionEvidence.ReceiptId -ceq $entry.ProtectionReceiptId
                ) { throw 'PROTECTION_RECEIPT_NOT_MONOTONIC' }
                $entry.ProtectionEvidenceSha256 = $ProtectionEvidenceSha256
                $entry.ProtectionAuthorityAssertionSha256 = $protectionAuthorityTrust.AssertionSha256
                $entry.ProtectionObservedAtUtc = [string]$ProtectionEvidence.ObservedAtUtc
                $entry.ProtectionValidUntilUtc = [string]$ProtectionEvidence.ValidUntilUtc
                $entry.ProtectionReceiptId = [string]$ProtectionEvidence.ReceiptId
                $receiptRotated = $true
            }
        }
        $acceptedHead = if ($null -eq $entry) { $null } else { [string]$entry.AcceptedRemoteHead }
        $snapshot = Get-CddsiFastLaneRemoteSnapshot $context $repositoryPath $RepositoryUri `
            $RemoteRef $ExpectedGenesisCommit $acceptedHead
        if ($null -eq $entry) {
            if ($null -ne $ProtectionEvidence.PreviousReceiptSha256) { throw 'PROTECTION_RECEIPT_GENESIS_PREDECESSOR_FORBIDDEN' }
            $entry = [pscustomobject][ordered]@{
                RepositoryIdentity = $RepositoryIdentity; RepositoryUriSha256 = $uriSha
                RepositoryNumericId = [long]$ProtectionEvidence.RepositoryNumericId
                RepositoryNodeId = [string]$ProtectionEvidence.RepositoryNodeId
                ProtectionAuthority = $ExpectedProtectionAuthority
                ProtectionPolicySha256 = $ExpectedProtectionPolicySha256
                ProtectionAuthorityBindingToken = $protectionAuthorityTrust.AuthorityBindingToken
                ProtectionAuthorityAssertionSha256 = $protectionAuthorityTrust.AssertionSha256
                ProtectionEvidenceSha256 = $ProtectionEvidenceSha256
                ProtectionObservedAtUtc = [string]$ProtectionEvidence.ObservedAtUtc
                ProtectionValidUntilUtc = [string]$ProtectionEvidence.ValidUntilUtc
                ProtectionReceiptId = [string]$ProtectionEvidence.ReceiptId
                CredentialProfileId = $CredentialProfileId
                TransportKind = $transportProfile.Kind
                SshExecutableSha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $SshExecutableSha256 } else { $null })
                DeployKeySha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $DeployKeySha256 } else { $null })
                KnownHostsSha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $KnownHostsSha256 } else { $null })
                GenesisCommit = $ExpectedGenesisCommit; RemoteRef = $RemoteRef; AcceptedRemoteHead = $ExpectedGenesisCommit
            }
            Set-CddsiFastLaneRepositoryEntry $state $entry
            $state.Revision = [long]$state.Revision + 1
            Write-CddsiFastLaneCanonicalFile $statePath $state
            $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
        }
        elseif ($receiptRotated) {
            Set-CddsiFastLaneRepositoryEntry $state $entry
            $state.Revision = [long]$state.Revision + 1
            Write-CddsiFastLaneCanonicalFile $statePath $state
            $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
        }

        $processed = 0
        $publishedPath = $null
        $publishedCommit = $null
        $more = $false
        $recoveredPublishCount = 0
        $resultStatus = 'SUCCEEDED'
        $wakeReceipt = $null
        $skipRequestedOperation = $false
        $pendingPublishPath = Get-CddsiFastLanePendingPublishPath -StateRoot $fullStateRoot
        if ([IO.File]::Exists($pendingPublishPath)) {
            $journal = Read-CddsiFastLanePendingPublish -Path $pendingPublishPath
            if (
                $journal.RepositoryIdentity -cne $RepositoryIdentity -or
                $journal.RepositoryUriSha256 -cne $uriSha -or
                $journal.RemoteRef -cne $RemoteRef -or
                $journal.AuthenticatedSenderRole -cne $credentialBinding.Role -or
                $journal.AuthenticatedOutbox -cne $AuthenticatedOutbox -or
                $journal.CredentialProfileId -cne $CredentialProfileId -or
                $journal.SnapshotTrustAssertionSha256 -cne $(if ($null -ne $snapshotTrust) {
                    $snapshotTrust.AssertionSha256
                } else { $null })
            ) { throw 'PENDING_PUBLISH_CONTEXT_MISMATCH' }
            if ($snapshot.Head -ceq $journal.ExpectedRemoteHead) {
                if ($entry.AcceptedRemoteHead -cne $journal.ExpectedRemoteHead) {
                    throw 'PENDING_PUBLISH_LOCAL_STATE_CONFLICT'
                }
                [IO.File]::Delete($pendingPublishPath)
                $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
            }
            elseif ($snapshot.Head -ceq $journal.PublishedCommit) {
                if (@($entry.AcceptedRemoteHead, $journal.ExpectedRemoteHead, $journal.PublishedCommit) |
                    Where-Object { -not (Test-CddsiFastLaneGitSha $_) } | Select-Object -First 1) {
                    throw 'PENDING_PUBLISH_HEAD_INVALID'
                }
                $parentCursor = if ($entry.AcceptedRemoteHead -ceq $journal.PublishedCommit) {
                    $journal.ExpectedRemoteHead
                }
                elseif ($entry.AcceptedRemoteHead -ceq $journal.ExpectedRemoteHead) {
                    $entry.AcceptedRemoteHead
                }
                else { throw 'PENDING_PUBLISH_LOCAL_STATE_CONFLICT' }
                $verifiedCommit = Get-CddsiFastLaneNextCommit $context $repositoryPath `
                    $parentCursor $journal.PublishedCommit 1
                if ($verifiedCommit -cne $journal.PublishedCommit) { throw 'PENDING_PUBLISH_COMMIT_MISMATCH' }
                $record = Read-CddsiFastLaneMessageAtCommit $context $repositoryPath $journal.PublishedCommit
                $canonicalRecoveredMessage = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $record.Message
                $recoveredMessageSha = Get-CddsiSupplyChainTextBindingToken -Text $canonicalRecoveredMessage
                $relayMessageSha = Get-CddsiVmTestRelayMessageSha256 `
                    -Envelope $record.Message.Envelope -Payload $record.Message.Payload
                if (
                    $record.Path -cne $journal.PublishedPath -or
                    $recoveredMessageSha -cne $journal.CanonicalMessageSha256 -or
                    $relayMessageSha -cne $journal.CanonicalMessageSha256 -or
                    $record.Message.Envelope.SenderRole -cne $journal.AuthenticatedSenderRole
                ) { throw 'PENDING_PUBLISH_MESSAGE_BINDING_MISMATCH' }

                if ($entry.AcceptedRemoteHead -ceq $journal.ExpectedRemoteHead) {
                    if ($state.RelayState.StateBindingToken -cne $journal.RelayPreviousStateBindingToken) {
                        throw 'PENDING_PUBLISH_RELAY_STATE_CONFLICT'
                    }
                    $recoveryTransition = Resolve-CddsiFastLaneBoundRelayTransition -State $state.RelayState `
                        -Message $record.Message `
                        -ValidationTimeUtc $journal.TransitionValidationTimeUtc `
                        -AuthenticatedSenderRole $journal.AuthenticatedSenderRole `
                        -AuthenticatedOutbox $journal.AuthenticatedOutbox -SnapshotTrust $snapshotTrust `
                        -MaximumAgeSeconds $MaximumAgeSeconds `
                        -MaximumClockSkewSeconds $MaximumClockSkewSeconds `
                        -MaximumMessageBodyBytes $MaximumMessageBodyBytes
                    if (
                        -not $recoveryTransition.Accepted -or -not $recoveryTransition.Advanced -or
                        $recoveryTransition.State.StateBindingToken -cne $journal.RelayNextStateBindingToken
                    ) { throw ('PENDING_PUBLISH_RELAY_REJECTED:' + $recoveryTransition.ErrorCode) }
                    $state.RelayState = $recoveryTransition.State
                    $entry.AcceptedRemoteHead = $journal.PublishedCommit
                    Set-CddsiFastLaneRepositoryEntry $state $entry
                    $state.Revision = [long]$state.Revision + 1
                    Write-CddsiFastLaneCanonicalFile $statePath $state
                    $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
                }
                elseif ($state.RelayState.StateBindingToken -cne $journal.RelayNextStateBindingToken) {
                    throw 'PENDING_PUBLISH_PERSISTED_STATE_MISMATCH'
                }
                [IO.File]::Delete($pendingPublishPath)
                $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
                $processed = 1
                $publishedPath = [string]$journal.PublishedPath
                $publishedCommit = [string]$journal.PublishedCommit
                $recoveredPublishCount = 1
                $resultStatus = 'RECOVERED'
                $skipRequestedOperation = $true
            }
            else { throw 'PENDING_PUBLISH_REMOTE_HEAD_CONFLICT' }
        }
        if (-not $skipRequestedOperation -and $Operation -ceq 'Poll') {
            $countResult = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                ('--git-dir=' + $repositoryPath), 'rev-list', '--first-parent', '--count', ($entry.AcceptedRemoteHead + '..' + $snapshot.Head)
            )
            $remaining = 0L
            if (-not [long]::TryParse($countResult.StandardOutput.Trim(), [ref]$remaining) -or $remaining -lt 0) { throw 'REMOTE_COMMIT_COUNT_INVALID' }
            if ($null -ne $ExpectedWakePointer) {
                $protectedHistory = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                    ('--git-dir=' + $repositoryPath), 'merge-base', '--is-ancestor',
                    $ExpectedWakePointer.Commit, $snapshot.Head
                ) -AllowedExitCodes @(0, 1)
                if ($protectedHistory.ExitCode -ne 0) { throw 'WAKE_POINTER_COMMIT_NOT_IN_PROTECTED_HISTORY' }
                $record = Assert-CddsiFastLaneWakePointerTarget -Context $context `
                    -RepositoryPath $repositoryPath -Pointer $ExpectedWakePointer
                $acceptedHistory = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                    ('--git-dir=' + $repositoryPath), 'merge-base', '--is-ancestor',
                    $ExpectedWakePointer.Commit, $entry.AcceptedRemoteHead
                ) -AllowedExitCodes @(0, 1)
                $messageWasSeen = $state.RelayState.SeenMessageIds -ccontains $ExpectedWakePointer.MessageId
                if ($messageWasSeen) {
                    if ($acceptedHistory.ExitCode -ne 0) { throw 'WAKE_POINTER_CONSUMED_STATE_MISMATCH' }
                    $messageHistory = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                        ('--git-dir=' + $repositoryPath), 'rev-list', '--first-parent', '--max-count=2',
                        $entry.AcceptedRemoteHead, '--', ('outbox/*-' + $ExpectedWakePointer.MessageId + '.json')
                    )
                    $matchingCommits = @($messageHistory.StandardOutput -split "`r?`n" | Where-Object { $_.Length -gt 0 })
                    if ($matchingCommits.Count -ne 1 -or $matchingCommits[0] -cne $ExpectedWakePointer.Commit) {
                        throw 'WAKE_POINTER_CONSUMED_HISTORY_MISMATCH'
                    }
                    $wakeReceipt = New-CddsiFastLaneWakeReceipt -Pointer $ExpectedWakePointer `
                        -Status ALREADY_CONSUMED
                }
                else {
                    if ($acceptedHistory.ExitCode -eq 0) { throw 'WAKE_POINTER_CONSUMED_STATE_MISMATCH' }
                    if ($remaining -lt 1) { throw 'WAKE_POINTER_TARGET_NOT_PENDING' }
                    if ($context.Stopwatch.Elapsed.TotalSeconds -ge $MaximumRuntimeSeconds) {
                        throw 'WAKE_POINTER_RUNTIME_EXHAUSTED'
                    }
                    $commit = Get-CddsiFastLaneNextCommit $context $repositoryPath `
                        $entry.AcceptedRemoteHead $snapshot.Head $remaining
                    if ($commit -cne $ExpectedWakePointer.Commit) { throw 'WAKE_POINTER_SEQUENCE_GAP' }
                    $role = [string]$record.Message.Envelope.SenderRole
                    if ($AuthenticatedSenderRoles -cnotcontains $role) { throw 'OUTBOX_SENDER_ROLE_NOT_AUTHENTICATED' }
                    $transition = Resolve-CddsiFastLaneBoundRelayTransition -State $state.RelayState `
                        -Message $record.Message `
                        -ValidationTimeUtc $ValidationTimeUtc -AuthenticatedSenderRole $role `
                        -AuthenticatedOutbox $AuthenticatedOutbox -SnapshotTrust $snapshotTrust `
                        -MaximumAgeSeconds $MaximumAgeSeconds `
                        -MaximumClockSkewSeconds $MaximumClockSkewSeconds -MaximumMessageBodyBytes $MaximumMessageBodyBytes
                    if (-not $transition.Accepted -or -not $transition.Advanced) { throw ('RELAY_REJECTED:' + $transition.ErrorCode) }
                    $state.RelayState = $transition.State
                    $entry.AcceptedRemoteHead = $commit
                    Set-CddsiFastLaneRepositoryEntry $state $entry
                    $state.Revision = [long]$state.Revision + 1
                    Write-CddsiFastLaneCanonicalFile $statePath $state
                    $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
                    $processed = 1
                    $remaining--
                    $wakeReceipt = New-CddsiFastLaneWakeReceipt -Pointer $ExpectedWakePointer `
                        -Status CONSUMED_NOW
                }
            }
            else {
                while ($remaining -gt 0 -and $processed -lt $effectiveMaximumMessageCount) {
                    if ($context.Stopwatch.Elapsed.TotalSeconds -ge $MaximumRuntimeSeconds) { $more = $true; break }
                    $commit = Get-CddsiFastLaneNextCommit $context $repositoryPath $entry.AcceptedRemoteHead $snapshot.Head $remaining
                    $record = Read-CddsiFastLaneMessageAtCommit $context $repositoryPath $commit
                    $role = [string]$record.Message.Envelope.SenderRole
                    if ($AuthenticatedSenderRoles -cnotcontains $role) { throw 'OUTBOX_SENDER_ROLE_NOT_AUTHENTICATED' }
                    $transition = Resolve-CddsiFastLaneBoundRelayTransition -State $state.RelayState `
                        -Message $record.Message `
                        -ValidationTimeUtc $ValidationTimeUtc -AuthenticatedSenderRole $role `
                        -AuthenticatedOutbox $AuthenticatedOutbox -SnapshotTrust $snapshotTrust `
                        -MaximumAgeSeconds $MaximumAgeSeconds `
                        -MaximumClockSkewSeconds $MaximumClockSkewSeconds -MaximumMessageBodyBytes $MaximumMessageBodyBytes
                    if (-not $transition.Accepted -or -not $transition.Advanced) { throw ('RELAY_REJECTED:' + $transition.ErrorCode) }
                    $state.RelayState = $transition.State
                    $entry.AcceptedRemoteHead = $commit
                    Set-CddsiFastLaneRepositoryEntry $state $entry
                    $state.Revision = [long]$state.Revision + 1
                    Write-CddsiFastLaneCanonicalFile $statePath $state
                    $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
                    $processed++
                    $remaining--
                }
            }
            $more = $more -or $remaining -gt 0
        }
        elseif (-not $skipRequestedOperation) {
            if ($snapshot.Head -cne $ExpectedRemoteHead) { throw 'REMOTE_CAS_MISMATCH' }
            if ($entry.AcceptedRemoteHead -cne $snapshot.Head) { throw 'OUTGOING_STATE_RECOVERY_REQUIRED' }
            if (-not (Test-CddsiExactPropertySet -InputObject $Message -Expected @('Envelope', 'Payload'))) { throw 'PUBLISH_MESSAGE_SCHEMA_INVALID' }
            $role = [string]$Message.Envelope.SenderRole
            if ($AuthenticatedSenderRoles -cnotcontains $role) { throw 'PUBLISH_SENDER_ROLE_NOT_AUTHENTICATED' }
            $transition = Resolve-CddsiFastLaneBoundRelayTransition -State $state.RelayState -Message $Message `
                -ValidationTimeUtc $ValidationTimeUtc -AuthenticatedSenderRole $role `
                -AuthenticatedOutbox $AuthenticatedOutbox -SnapshotTrust $snapshotTrust `
                -MaximumAgeSeconds $MaximumAgeSeconds -MaximumClockSkewSeconds $MaximumClockSkewSeconds `
                -MaximumMessageBodyBytes $MaximumMessageBodyBytes
            if (-not $transition.Accepted -or -not $transition.Advanced) { throw ('RELAY_REJECTED:' + $transition.ErrorCode) }
            $sequenceText = ([long]$Message.Envelope.Sequence).ToString('D12', [Globalization.CultureInfo]::InvariantCulture)
            $publishedPath = 'outbox/' + $sequenceText + '-' + [string]$Message.Envelope.MessageId + '.json'
            if ($publishedPath -cnotmatch '^outbox/[0-9]{12}-[a-f0-9-]{36}\.json$') { throw 'PUBLISH_FILENAME_INVALID' }
            $canonicalMessage = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Message
            $publishedCommit = New-CddsiFastLaneGitCommit $context $repositoryPath $snapshot.Head `
                ([IO.Path]::GetFileName($publishedPath)) $canonicalMessage
            $remoteCheck = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                ('--git-dir=' + $repositoryPath), 'ls-remote', '--refs', $RepositoryUri, $RemoteRef
            ) -OperatorTransport
            $remoteParts = @($remoteCheck.StandardOutput.Trim() -split "\s+")
            if ($remoteParts.Count -ne 2 -or $remoteParts[0] -cne $ExpectedRemoteHead -or $remoteParts[1] -cne $RemoteRef) {
                throw 'REMOTE_CAS_MISMATCH'
            }
            $journal = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-pending-publish-v1'
                RepositoryIdentity = $RepositoryIdentity; RepositoryUriSha256 = $uriSha
                RemoteRef = $RemoteRef; ExpectedRemoteHead = $ExpectedRemoteHead
                PublishedCommit = $publishedCommit; PublishedPath = $publishedPath
                CanonicalMessageSha256 = (Get-CddsiSupplyChainTextBindingToken -Text $canonicalMessage)
                RelayPreviousStateBindingToken = $state.RelayState.StateBindingToken
                RelayNextStateBindingToken = $transition.State.StateBindingToken
                TransitionValidationTimeUtc = $ValidationTimeUtc
                AuthenticatedSenderRole = $credentialBinding.Role
                AuthenticatedOutbox = $AuthenticatedOutbox; CredentialProfileId = $CredentialProfileId
                SnapshotTrustAssertionSha256 = $(if ($Message.Envelope.MessageType -ceq 'SNAPSHOT_READY') {
                    $snapshotTrust.AssertionSha256
                } else { $null })
            }
            Write-CddsiFastLaneCanonicalFile -Path $pendingPublishPath -Value $journal -CreateOnly
            $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
            [void](Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                ('--git-dir=' + $repositoryPath), 'push', '--porcelain', $RepositoryUri,
                ($publishedCommit + ':' + $RemoteRef)
            ) -OperatorTransport)
            $context.OperatorRemoteMutationCount = [int]$context.OperatorRemoteMutationCount + 1
            $verify = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                ('--git-dir=' + $repositoryPath), 'ls-remote', '--refs', $RepositoryUri, $RemoteRef
            ) -OperatorTransport
            $verifyParts = @($verify.StandardOutput.Trim() -split "\s+")
            if ($verifyParts.Count -ne 2 -or $verifyParts[0] -cne $publishedCommit) { throw 'PUBLISHED_REMOTE_HEAD_MISMATCH' }
            if ($FailureInjection -ceq 'AfterRemotePushBeforeStatePersist') {
                throw 'INJECTED_AFTER_REMOTE_PUSH_BEFORE_STATE_PERSIST'
            }
            $state.RelayState = $transition.State
            $entry.AcceptedRemoteHead = $publishedCommit
            Set-CddsiFastLaneRepositoryEntry $state $entry
            $state.Revision = [long]$state.Revision + 1
            Write-CddsiFastLaneCanonicalFile $statePath $state
            $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
            [IO.File]::Delete($pendingPublishPath)
            $context.LocalStateMutationCount = [int]$context.LocalStateMutationCount + 1
            $processed = 1
        }

        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = $script:CddsiFastLaneGitOutboxResultContract
            Operation = $Operation; Mode = $Mode; Status = $resultStatus; OperatorPlaneOnly = $true
            RepositoryIdentity = $RepositoryIdentity
            RemoteHead = $(if ($null -ne $publishedCommit) { $publishedCommit } else { $snapshot.Head })
            ProcessedMessageCount = $processed; PublishedPath = $publishedPath; PublishedCommit = $publishedCommit
            RecoveredPublishCount = $recoveredPublishCount; ProtectionReceiptRotated = $receiptRotated
            MoreAvailable = $more; GitInvocationCount = [int]$context.GitInvocationCount
            GitExecutableSha256 = $GitExecutableSha256; RunnerSha256 = $RunnerSha256
            ProtectionEvidenceSha256 = $ProtectionEvidenceSha256; CredentialProfileId = $CredentialProfileId
            ProtectionAuthority = $ExpectedProtectionAuthority; ProtectionPolicySha256 = $ExpectedProtectionPolicySha256
            ProtectionAuthorityAssertionSha256 = $protectionAuthorityTrust.AssertionSha256
            ProtectionAuthorityBindingToken = $protectionAuthorityTrust.AuthorityBindingToken
            ProductRootPathSha256 = $workspaceBinding.ProductRootPathSha256
            OperatorWorkspacePathSha256 = $workspaceBinding.OperatorWorkspacePathSha256
            SnapshotTrustAssertionSha256 = $(if ($null -ne $snapshotTrust) { $snapshotTrust.AssertionSha256 } else { $null })
            SnapshotTrustInputSource = $(if ($null -ne $snapshotTrust) { 'ProtectedOperatorWorkspace' } else { $null })
            AuthenticatedSenderRole = $credentialBinding.Role
            TransportKind = $transportProfile.Kind
            SshExecutableSha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $SshExecutableSha256 } else { $null })
            DeployKeySha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $DeployKeySha256 } else { $null })
            KnownHostsSha256 = $(if ($transportProfile.Kind -ceq 'Ssh') { $KnownHostsSha256 } else { $null })
            OperatorGitTransportCount = [int]$context.OperatorGitTransportCount
            OperatorRemoteMutationCount = [int]$context.OperatorRemoteMutationCount
            JobAssignmentCount = [int]$context.JobAssignmentCount
            ProcessTreeTerminationCount = [int]$context.ProcessTreeTerminationCount
            LocalStateMutationCount = [int]$context.LocalStateMutationCount
            ProductNetworkRequestCount = 0; HostProductLiveInvocationCount = 0; VmProductWriteCount = 0
            MaximumRetryCount = $MaximumRetryCount; RetryCount = 0
            MaximumMessageCount = $effectiveMaximumMessageCount; MaximumRuntimeSeconds = $MaximumRuntimeSeconds
            MaximumOutputBytes = $MaximumOutputBytes; MaximumMessageBodyBytes = $MaximumMessageBodyBytes
            MaximumAgeSeconds = $MaximumAgeSeconds; MaximumClockSkewSeconds = $MaximumClockSkewSeconds
            ChildEnvironmentInheritedCount = 0; ProcessJobRequired = $true
            RelayState = $state.RelayState
            WakeReceipt = $wakeReceipt
        }
    }
    finally { $lock.Dispose() }
}

# Bootstrap-only VM onboarding helpers. These functions deliberately do not
# call the Poll or Publish paths above. The package is verified from one
# immutable in-memory byte array before any ZIP entry is inspected.
$script:CddsiFastLaneVmBootstrapOwnerContract = 'cddsi-fast-lane-vm-bootstrap-owner-v1'
$script:CddsiFastLaneVmBootstrapResultContract = 'cddsi-fast-lane-vm-bootstrap-result-v1'
$script:CddsiFastLaneVmBootstrapMaximumBundleBytes = 67108864
$script:CddsiFastLaneVmBootstrapMaximumEntryBytes = 16777216
$script:CddsiFastLaneVmBootstrapMaximumEntryCount = 256
$script:CddsiFastLaneVmBootstrapProfiles = @(
    'vm.host-to-vm.read',
    'vm.vm-to-host.write',
    'vm.product.read'
)

function Test-CddsiFastLaneVmBootstrapSafeRelativePath {
    param([AllowNull()]$Value)

    if ($Value -isnot [string] -or $Value.Length -lt 1 -or $Value.Length -gt 512 -or
        $Value -cnotmatch '^[A-Za-z0-9._/-]+$' -or $Value.Contains('\') -or
        $Value.StartsWith('/') -or $Value.EndsWith('/')) { return $false }
    foreach ($segment in @($Value -split '/')) {
        if ($segment.Length -lt 1 -or $segment -ceq '.' -or $segment -ceq '..' -or
            $segment.EndsWith('.') -or $segment.EndsWith(' ')) { return $false }
        $deviceStem = @($segment -split '\.')[0]
        if ($deviceStem -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])$') { return $false }
    }
    return $true
}

function Get-CddsiFastLaneVmBootstrapBytesSha256 {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Test-CddsiFastLaneVmBootstrapStoreZipBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][int]$ExpectedEntryCount
    )

    $stream = $null
    $reader = $null
    try {
        if ($Bytes.LongLength -lt 22 -or $ExpectedEntryCount -lt 1) { return $false }
        $stream = New-Object IO.MemoryStream(, $Bytes)
        $reader = New-Object IO.BinaryReader($stream, (New-Object Text.UTF8Encoding($false, $true)), $true)
        $eocdOffset = $stream.Length - 22
        $stream.Position = $eocdOffset
        if ($reader.ReadUInt32() -ne [uint32]0x06054b50 -or
            $reader.ReadUInt16() -ne 0 -or $reader.ReadUInt16() -ne 0) { return $false }
        $entriesOnDisk = [int]$reader.ReadUInt16()
        $entryCount = [int]$reader.ReadUInt16()
        $centralSize = [long]$reader.ReadUInt32()
        $centralOffset = [long]$reader.ReadUInt32()
        $commentLength = [int]$reader.ReadUInt16()
        if ($entriesOnDisk -ne $ExpectedEntryCount -or $entryCount -ne $ExpectedEntryCount -or
            $commentLength -ne 0 -or $centralOffset -lt 0 -or $centralSize -lt 1 -or
            ($centralOffset + $centralSize) -ne $eocdOffset) { return $false }

        $entries = [Collections.Generic.List[object]]::new()
        $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $foldedNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $stream.Position = $centralOffset
        while ($stream.Position -lt ($centralOffset + $centralSize)) {
            if ($entries.Count -ge $ExpectedEntryCount -or $reader.ReadUInt32() -ne [uint32]0x02014b50) {
                return $false
            }
            [void]$reader.ReadUInt16(); [void]$reader.ReadUInt16()
            $flags = $reader.ReadUInt16(); $method = $reader.ReadUInt16()
            $time = $reader.ReadUInt16(); $date = $reader.ReadUInt16()
            $crc32 = $reader.ReadUInt32(); $compressed = $reader.ReadUInt32(); $uncompressed = $reader.ReadUInt32()
            $nameLength = [int]$reader.ReadUInt16(); $extraLength = [int]$reader.ReadUInt16()
            $entryCommentLength = [int]$reader.ReadUInt16(); $diskStart = $reader.ReadUInt16()
            [void]$reader.ReadUInt16(); [void]$reader.ReadUInt32()
            $localOffset = [long]$reader.ReadUInt32()
            if ($flags -ne 0x0800 -or $method -ne 0 -or $time -ne 0 -or $date -ne 0x0021 -or
                $compressed -ne $uncompressed -or $nameLength -lt 1 -or $extraLength -ne 0 -or
                $entryCommentLength -ne 0 -or $diskStart -ne 0 -or $localOffset -ge $centralOffset) {
                return $false
            }
            $nameBytes = $reader.ReadBytes($nameLength)
            if ($nameBytes.Length -ne $nameLength) { return $false }
            try { $name = (New-Object Text.UTF8Encoding($false, $true)).GetString($nameBytes) }
            catch { return $false }
            if (-not (Test-CddsiFastLaneVmBootstrapSafeRelativePath $name) -or
                -not $names.Add($name) -or -not $foldedNames.Add($name)) { return $false }
            $entries.Add([pscustomobject]@{
                Name = $name; Flags = $flags; Method = $method; Time = $time; Date = $date
                Crc32 = $crc32; Size = [long]$uncompressed; LocalOffset = $localOffset
            })
        }
        if ($stream.Position -ne ($centralOffset + $centralSize) -or $entries.Count -ne $ExpectedEntryCount) {
            return $false
        }

        $ordered = @($entries | Sort-Object LocalOffset)
        $nextOffset = [long]0
        foreach ($entry in $ordered) {
            if ([long]$entry.LocalOffset -ne $nextOffset) { return $false }
            $stream.Position = [long]$entry.LocalOffset
            if ($reader.ReadUInt32() -ne [uint32]0x04034b50) { return $false }
            [void]$reader.ReadUInt16()
            $flags = $reader.ReadUInt16(); $method = $reader.ReadUInt16()
            $time = $reader.ReadUInt16(); $date = $reader.ReadUInt16()
            $crc32 = $reader.ReadUInt32(); $compressed = $reader.ReadUInt32(); $uncompressed = $reader.ReadUInt32()
            $nameLength = [int]$reader.ReadUInt16(); $extraLength = [int]$reader.ReadUInt16()
            if ($flags -ne 0x0800 -or $method -ne 0 -or $time -ne 0 -or $date -ne 0x0021 -or
                $crc32 -ne [uint32]$entry.Crc32 -or $compressed -ne $uncompressed -or
                [long]$uncompressed -ne [long]$entry.Size -or $nameLength -lt 1 -or $extraLength -ne 0) {
                return $false
            }
            $nameBytes = $reader.ReadBytes($nameLength)
            if ($nameBytes.Length -ne $nameLength) { return $false }
            try { $name = (New-Object Text.UTF8Encoding($false, $true)).GetString($nameBytes) }
            catch { return $false }
            if ($name -cne $entry.Name) { return $false }
            $nextOffset = $stream.Position + [long]$entry.Size
            if ($nextOffset -gt $centralOffset) { return $false }
        }
        return ($nextOffset -eq $centralOffset)
    }
    catch { return $false }
    finally {
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-CddsiFastLaneVmBootstrapBindingToken {
    param([Parameter(Mandatory = $true)]$Value)

    return Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Value)
}

function Get-CddsiFastLaneVmBootstrapZipEntryBytes {
    param(
        [Parameter(Mandatory = $true)][IO.Compression.ZipArchive]$Archive,
        [Parameter(Mandatory = $true)][string]$Name
    )

    $entry = $Archive.GetEntry($Name)
    if ($null -eq $entry) { throw 'VM_BOOTSTRAP_ZIP_ENTRY_MISSING' }
    if ($entry.Length -lt 0 -or $entry.Length -gt $script:CddsiFastLaneVmBootstrapMaximumEntryBytes) {
        throw 'VM_BOOTSTRAP_ZIP_ENTRY_SIZE_INVALID'
    }
    $input = $entry.Open()
    $output = New-Object IO.MemoryStream
    try {
        $input.CopyTo($output)
        return $output.ToArray()
    }
    finally {
        $input.Dispose()
        $output.Dispose()
    }
}

function ConvertFrom-CddsiFastLaneVmBootstrapCanonicalJsonBytes {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes,
        [Parameter(Mandatory = $true)][ValidateSet('Manifest', 'Inventory')][string]$Kind
    )

    if ($Bytes.Length -lt 3 -or $Bytes[0] -eq 0xEF) { throw ('VM_BOOTSTRAP_' + $Kind.ToUpperInvariant() + '_ENCODING_INVALID') }
    try { $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($Bytes) }
    catch { throw ('VM_BOOTSTRAP_' + $Kind.ToUpperInvariant() + '_ENCODING_INVALID') }
    if (-not $text.EndsWith("`n") -or $text.EndsWith("`r`n")) {
        throw ('VM_BOOTSTRAP_' + $Kind.ToUpperInvariant() + '_TERMINATOR_INVALID')
    }
    try { $value = ConvertFrom-Json -InputObject $text.Substring(0, $text.Length - 1) -ErrorAction Stop }
    catch { throw ('VM_BOOTSTRAP_' + $Kind.ToUpperInvariant() + '_JSON_INVALID') }
    if ($Kind -ceq 'Manifest' -and $null -ne $value.Zip) {
        # PowerShell 7 infers this ISO string as DateTime; the manifest contract
        # intentionally binds the literal deterministic ZIP timestamp.
        $value.Zip.EntryTimestampUtc = '1980-01-01T00:00:00Z'
    }
    if (((ConvertTo-CddsiVmTestRelayCanonicalJson -Value $value) + "`n") -cne $text) {
        throw ('VM_BOOTSTRAP_' + $Kind.ToUpperInvariant() + '_NOT_CANONICAL')
    }
    return [pscustomobject]@{ Value = $value; Text = $text }
}

function Test-CddsiFastLaneVmOnboardingPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$ExpectedZipSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedZipLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedManifestLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedInventorySha256,
        [Parameter(Mandatory = $true)][long]$ExpectedInventoryLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedInventoryBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedBundleContentDigestSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProductCommitSha,
        [Parameter(Mandatory = $true)][string]$ExpectedProductTreeSha,
        [Parameter(Mandatory = $true)][string]$ProgramFilesRoot,
        [Parameter(Mandatory = $true)][string]$SystemRoot,
        [Parameter(DontShow = $true)][AllowNull()][byte[]]$BoundZipBytes = $null
    )

    foreach ($shaValue in @(
        $ExpectedZipSha256, $ExpectedManifestSha256, $ExpectedManifestBindingToken,
        $ExpectedInventorySha256, $ExpectedInventoryBindingToken, $ExpectedBundleContentDigestSha256
    )) {
        if ($shaValue -cnotmatch '^[a-f0-9]{64}$') { throw 'VM_BOOTSTRAP_EXPECTED_BINDING_INVALID' }
    }
    if ($ExpectedProductCommitSha -cnotmatch '^[a-f0-9]{40}$' -or $ExpectedProductTreeSha -cnotmatch '^[a-f0-9]{40}$') {
        throw 'VM_BOOTSTRAP_EXPECTED_PRODUCT_BINDING_INVALID'
    }
    if ($ExpectedZipLengthBytes -lt 1 -or $ExpectedZipLengthBytes -gt $script:CddsiFastLaneVmBootstrapMaximumBundleBytes -or
        $ExpectedManifestLengthBytes -lt 3 -or $ExpectedManifestLengthBytes -gt $script:CddsiFastLaneVmBootstrapMaximumEntryBytes -or
        $ExpectedInventoryLengthBytes -lt 3 -or $ExpectedInventoryLengthBytes -gt $script:CddsiFastLaneVmBootstrapMaximumEntryBytes) {
        throw 'VM_BOOTSTRAP_EXPECTED_LENGTH_INVALID'
    }
    if (-not [IO.Path]::IsPathRooted($ZipPath) -or -not [IO.File]::Exists($ZipPath) -or
        -not (Test-CddsiFastLanePathWithoutReparsePoint -Path $ZipPath)) {
        throw 'VM_BOOTSTRAP_ZIP_PATH_INVALID'
    }

    # This is intentionally the first content operation. All later validation
    # consumes this same byte array, eliminating a path-based ZIP TOCTOU gap.
    $zipInfo = [IO.FileInfo]::new($ZipPath)
    if ([long]$zipInfo.Length -ne $ExpectedZipLengthBytes) { throw 'VM_BOOTSTRAP_ZIP_LENGTH_MISMATCH' }
    $zipBytes = if ($null -ne $BoundZipBytes) { $BoundZipBytes } else { [IO.File]::ReadAllBytes($ZipPath) }
    if ($zipBytes.LongLength -ne $ExpectedZipLengthBytes) { throw 'VM_BOOTSTRAP_ZIP_LENGTH_MISMATCH' }
    if ((Get-CddsiFastLaneVmBootstrapBytesSha256 -Bytes $zipBytes) -cne $ExpectedZipSha256) {
        throw 'VM_BOOTSTRAP_ZIP_HASH_MISMATCH'
    }
    if (-not (Test-CddsiFastLaneVmBootstrapStoreZipBytes -Bytes $zipBytes -ExpectedEntryCount 18)) {
        throw 'VM_BOOTSTRAP_ZIP_STORE_HEADERS_INVALID'
    }

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    $memory = New-Object IO.MemoryStream(, $zipBytes)
    try { $archive = New-Object IO.Compression.ZipArchive($memory, [IO.Compression.ZipArchiveMode]::Read, $false) }
    catch { $memory.Dispose(); throw 'VM_BOOTSTRAP_ZIP_INVALID' }
    try {
        $entries = @($archive.Entries)
        if ($entries.Count -ne 18) {
            throw 'VM_BOOTSTRAP_ZIP_ENTRY_COUNT_INVALID'
        }
        $names = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $foldedNames = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
        $totalLength = [long]0
        foreach ($entry in $entries) {
            $name = [string]$entry.FullName
            if (-not (Test-CddsiFastLaneVmBootstrapSafeRelativePath $name) -or
                -not $names.Add($name) -or -not $foldedNames.Add($name)) {
                throw 'VM_BOOTSTRAP_ZIP_ENTRY_PATH_INVALID'
            }
            if ($entry.Length -lt 0 -or $entry.Length -gt $script:CddsiFastLaneVmBootstrapMaximumEntryBytes -or
                $entry.CompressedLength -ne $entry.Length) {
                throw 'VM_BOOTSTRAP_ZIP_ENTRY_STORAGE_INVALID'
            }
            $stamp = $entry.LastWriteTime
            if ($stamp.Year -ne 1980 -or $stamp.Month -ne 1 -or $stamp.Day -ne 1 -or
                $stamp.Hour -ne 0 -or $stamp.Minute -ne 0 -or $stamp.Second -ne 0) {
                throw 'VM_BOOTSTRAP_ZIP_ENTRY_TIMESTAMP_INVALID'
            }
            $totalLength += [long]$entry.Length
            if ($totalLength -gt $script:CddsiFastLaneVmBootstrapMaximumBundleBytes) {
                throw 'VM_BOOTSTRAP_ZIP_AGGREGATE_SIZE_INVALID'
            }
        }

        $manifestBytes = Get-CddsiFastLaneVmBootstrapZipEntryBytes -Archive $archive -Name 'manifest.json'
        $inventoryBytes = Get-CddsiFastLaneVmBootstrapZipEntryBytes -Archive $archive -Name 'inventory.json'
        if ($manifestBytes.LongLength -ne $ExpectedManifestLengthBytes -or
            (Get-CddsiFastLaneVmBootstrapBytesSha256 $manifestBytes) -cne $ExpectedManifestSha256) {
            throw 'VM_BOOTSTRAP_MANIFEST_EXTERNAL_BINDING_MISMATCH'
        }
        if ($inventoryBytes.LongLength -ne $ExpectedInventoryLengthBytes -or
            (Get-CddsiFastLaneVmBootstrapBytesSha256 $inventoryBytes) -cne $ExpectedInventorySha256) {
            throw 'VM_BOOTSTRAP_INVENTORY_EXTERNAL_BINDING_MISMATCH'
        }
        $manifestData = ConvertFrom-CddsiFastLaneVmBootstrapCanonicalJsonBytes -Bytes $manifestBytes -Kind Manifest
        $inventoryData = ConvertFrom-CddsiFastLaneVmBootstrapCanonicalJsonBytes -Bytes $inventoryBytes -Kind Inventory
        $manifest = $manifestData.Value
        $inventory = $inventoryData.Value
        if ($manifest.SchemaVersion -ne 3 -or
            $manifest.ContractVersion -cne 'cddsi-fast-lane-vm-onboarding-manifest-v3' -or
            $manifest.Purpose -cne 'P10A_0A_VM_ONBOARDING_DIAGNOSTIC_ONLY' -or
            $manifest.EvidenceClass -cne 'DIAGNOSTIC_ONLY' -or $manifest.Mode -cne 'DryRun') {
            throw 'VM_BOOTSTRAP_MANIFEST_CLASSIFICATION_INVALID'
        }
        $manifestPayload = [ordered]@{}
        foreach ($property in $manifest.PSObject.Properties) {
            if ($property.Name -cne 'ManifestBindingToken') { $manifestPayload[$property.Name] = $property.Value }
        }
        if ($manifest.ManifestBindingToken -cne $ExpectedManifestBindingToken -or
            $manifest.ManifestBindingToken -cne (Get-CddsiFastLaneVmBootstrapBindingToken $manifestPayload)) {
            throw 'VM_BOOTSTRAP_MANIFEST_BINDING_MISMATCH'
        }
        if ($inventory.SchemaVersion -ne 1 -or
            $inventory.ContractVersion -cne 'cddsi-fast-lane-vm-onboarding-inventory-v1') {
            throw 'VM_BOOTSTRAP_INVENTORY_SCHEMA_INVALID'
        }
        $inventoryPayload = [ordered]@{}
        foreach ($property in $inventory.PSObject.Properties) {
            if ($property.Name -cne 'InventoryBindingToken') { $inventoryPayload[$property.Name] = $property.Value }
        }
        if ($inventory.InventoryBindingToken -cne $ExpectedInventoryBindingToken -or
            $inventory.InventoryBindingToken -cne (Get-CddsiFastLaneVmBootstrapBindingToken $inventoryPayload)) {
            throw 'VM_BOOTSTRAP_INVENTORY_BINDING_MISMATCH'
        }
        $inventoryEntries = @($inventory.Entries)
        if ([long]$inventory.EntryCount -ne 16 -or $inventoryEntries.Count -ne 16) {
            throw 'VM_BOOTSTRAP_INVENTORY_ENTRY_COUNT_INVALID'
        }
        foreach ($inventoryEntry in $inventoryEntries) {
            if (-not (Test-CddsiFastLaneVmBootstrapSafeRelativePath $inventoryEntry.Path) -or
                $inventoryEntry.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
                [long]$inventoryEntry.LengthBytes -lt 0 -or
                [long]$inventoryEntry.LengthBytes -gt $script:CddsiFastLaneVmBootstrapMaximumEntryBytes) {
                throw 'VM_BOOTSTRAP_INVENTORY_ENTRY_INVALID'
            }
            $content = Get-CddsiFastLaneVmBootstrapZipEntryBytes -Archive $archive -Name ([string]$inventoryEntry.Path)
            if ($content.LongLength -ne [long]$inventoryEntry.LengthBytes -or
                (Get-CddsiFastLaneVmBootstrapBytesSha256 $content) -cne [string]$inventoryEntry.Sha256) {
                throw 'VM_BOOTSTRAP_INVENTORY_CONTENT_MISMATCH'
            }
        }
        $contentPayload = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-fast-lane-vm-onboarding-content-v1'
            Entries = @($inventoryEntries)
        }
        $contentDigest = Get-CddsiFastLaneVmBootstrapBindingToken $contentPayload
        if ($contentDigest -cne $ExpectedBundleContentDigestSha256 -or
            $inventory.BundleContentDigestSha256 -cne $contentDigest -or
            $manifest.Inventory.BundleContentDigestSha256 -cne $contentDigest -or
            $manifest.Inventory.Sha256 -cne $ExpectedInventorySha256 -or
            $manifest.Inventory.InventoryBindingToken -cne $ExpectedInventoryBindingToken) {
            throw 'VM_BOOTSTRAP_CONTENT_BINDING_MISMATCH'
        }
        $policyProperties = @(
            'Path', 'Sha256', 'ProtocolVersion', 'ProductRepository', 'HostToVmRepository',
            'VmToHostRepository', 'Automation', 'Envelope', 'SshTrust'
        )
        $repositoryIdentityProperties = @('Id', 'NodeId', 'FullName')
        $productPolicyProperties = @(
            'RepositoryToken', 'Id', 'NodeId', 'FullName', 'Visibility', 'HostWriteRefPattern'
        )
        $controlPolicyProperties = @(
            'RepositoryToken', 'Id', 'NodeId', 'FullName', 'Visibility', 'Ref', 'GenesisSha'
        )
        $productProperties = @(
            'Repository', 'CommitSha', 'RepairRef', 'TreeSha', 'SourceCommitVerified',
            'GitExecutableSha256', 'VmAccess', 'CodeWriteAuthority'
        )
        $controlRepositoriesProperties = @('HostToVm', 'VmToHost')
        $controlRepositoryProperties = @('Repository', 'GenesisSha', 'VmAccess', 'HostAccess')
        if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Policy -Expected $policyProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.Policy.ProductRepository `
                -Expected $productPolicyProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.Policy.HostToVmRepository `
                -Expected $controlPolicyProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.Policy.VmToHostRepository `
                -Expected $controlPolicyProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.Product -Expected $productProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.Product.Repository `
                -Expected $repositoryIdentityProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.ControlRepositories `
                -Expected $controlRepositoriesProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.ControlRepositories.HostToVm `
                -Expected $controlRepositoryProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.ControlRepositories.HostToVm.Repository `
                -Expected $repositoryIdentityProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.ControlRepositories.VmToHost `
                -Expected $controlRepositoryProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $manifest.ControlRepositories.VmToHost.Repository `
                -Expected $repositoryIdentityProperties)) {
            throw 'VM_BOOTSTRAP_REPOSITORY_FACT_SCHEMA_INVALID'
        }
        $repositoryBindings = @(
            [pscustomobject][ordered]@{
                Role = 'Product'; Manifest = $manifest.Product.Repository
                Policy = $manifest.Policy.ProductRepository; Ref = $manifest.Product.RepairRef
                IntendedAccess = $manifest.Product.VmAccess; GenesisCommitSha = $null
            },
            [pscustomobject][ordered]@{
                Role = 'HostToVm'; Manifest = $manifest.ControlRepositories.HostToVm.Repository
                Policy = $manifest.Policy.HostToVmRepository
                Ref = $manifest.Policy.HostToVmRepository.Ref
                IntendedAccess = $manifest.ControlRepositories.HostToVm.VmAccess
                GenesisCommitSha = $manifest.ControlRepositories.HostToVm.GenesisSha
            },
            [pscustomobject][ordered]@{
                Role = 'VmToHost'; Manifest = $manifest.ControlRepositories.VmToHost.Repository
                Policy = $manifest.Policy.VmToHostRepository
                Ref = $manifest.Policy.VmToHostRepository.Ref
                IntendedAccess = $manifest.ControlRepositories.VmToHost.VmAccess
                GenesisCommitSha = $manifest.ControlRepositories.VmToHost.GenesisSha
            }
        )
        foreach ($binding in $repositoryBindings) {
            if (($binding.Manifest.Id -isnot [int] -and $binding.Manifest.Id -isnot [long]) -or
                [long]$binding.Manifest.Id -lt 1 -or
                $binding.Manifest.NodeId -isnot [string] -or
                $binding.Manifest.NodeId -cnotmatch '^[A-Za-z0-9_=-]{4,128}$' -or
                $binding.Manifest.FullName -isnot [string] -or
                $binding.Manifest.FullName -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
                $binding.Policy.RepositoryToken -cne ('github.com/' + $binding.Manifest.FullName) -or
                ($binding.Policy.Id -isnot [int] -and $binding.Policy.Id -isnot [long]) -or
                [long]$binding.Policy.Id -ne [long]$binding.Manifest.Id -or
                $binding.Policy.NodeId -cne $binding.Manifest.NodeId -or
                $binding.Policy.FullName -cne $binding.Manifest.FullName -or
                $binding.Policy.Visibility -cne 'PUBLIC' -or
                $binding.Ref -isnot [string] -or
                $binding.Ref -cnotmatch '^refs/heads/[A-Za-z0-9._*/-]+$') {
                throw ('VM_BOOTSTRAP_REPOSITORY_FACT_BINDING_INVALID:' + $binding.Role)
            }
        }
        if ($manifest.Policy.Path -cne 'payload/git/config/fast-lane-policy.psd1' -or
            $manifest.Policy.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $manifest.Policy.ProtocolVersion -cne 'cddsi-vm-test-relay-v1' -or
            $manifest.Policy.ProductRepository.HostWriteRefPattern -cne 'refs/heads/codex/repair/*' -or
            $manifest.Product.RepairRef -cnotlike $manifest.Policy.ProductRepository.HostWriteRefPattern -or
            $manifest.Policy.HostToVmRepository.Ref -cne 'refs/heads/main' -or
            $manifest.Policy.VmToHostRepository.Ref -cne 'refs/heads/main' -or
            $manifest.ControlRepositories.HostToVm.GenesisSha -cne
                $manifest.Policy.HostToVmRepository.GenesisSha -or
            $manifest.ControlRepositories.VmToHost.GenesisSha -cne
                $manifest.Policy.VmToHostRepository.GenesisSha -or
            $manifest.ControlRepositories.HostToVm.GenesisSha -cnotmatch '^[a-f0-9]{40}$' -or
            $manifest.ControlRepositories.VmToHost.GenesisSha -cnotmatch '^[a-f0-9]{40}$' -or
            $manifest.ControlRepositories.HostToVm.VmAccess -cne 'READ_ONLY' -or
            $manifest.ControlRepositories.HostToVm.HostAccess -cne 'APPEND_ONLY' -or
            $manifest.ControlRepositories.VmToHost.VmAccess -cne 'APPEND_ONLY' -or
            $manifest.ControlRepositories.VmToHost.HostAccess -cne 'READ_ONLY') {
            throw 'VM_BOOTSTRAP_REPOSITORY_POLICY_BINDING_INVALID'
        }
        if ($manifest.Product.CommitSha -cne $ExpectedProductCommitSha -or
            $manifest.Product.TreeSha -cne $ExpectedProductTreeSha -or
            -not $manifest.Product.SourceCommitVerified -or
            $manifest.Product.GitExecutableSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $manifest.Product.VmAccess -cne 'READ_ONLY_EXACT_COMMIT' -or
            $manifest.Product.CodeWriteAuthority -cne 'HOST_ONLY_REPAIR_REF') {
            throw 'VM_BOOTSTRAP_PRODUCT_BINDING_MISMATCH'
        }
        if ($manifest.Automation.VmAutomationId -cne 'cddsi-fast-lane-vmtester-minute-poll' -or
            $manifest.Automation.VmInitialStatus -cne 'PAUSED' -or
            [long]$manifest.Automation.IntervalMinutes -ne 1 -or
            $manifest.Constraints.VmMayEditProductCode -or
            $manifest.Constraints.VmMayCommitOrPushProductCode -or
            $manifest.Constraints.HostMayRunProductLive -or
            $manifest.Constraints.CredentialsIncluded -or
            $manifest.Constraints.AutoMerge -or $manifest.Constraints.AutoPromotion -or
            $manifest.Constraints.AutoRelease) {
            throw 'VM_BOOTSTRAP_FAIL_CLOSED_CONSTRAINT_MISMATCH'
        }
        $expectedEntryNames = [string[]]@('manifest.json', 'inventory.json') +
            [string[]]@($inventoryEntries | ForEach-Object { [string]$_.Path })
        [Array]::Sort($expectedEntryNames, [StringComparer]::Ordinal)
        $actualEntryNames = [string[]]@($entries | ForEach-Object { [string]$_.FullName })
        [Array]::Sort($actualEntryNames, [StringComparer]::Ordinal)
        $manifestEntryNames = [string[]]@($manifest.Zip.ExpectedEntries)
        [Array]::Sort($manifestEntryNames, [StringComparer]::Ordinal)
        if (($expectedEntryNames -join "`n") -cne ($actualEntryNames -join "`n") -or
            ($expectedEntryNames -join "`n") -cne ($manifestEntryNames -join "`n")) {
            throw 'VM_BOOTSTRAP_ZIP_INVENTORY_NOT_EXACT'
        }

        $requiredTools = [ordered]@{
            Git = [pscustomobject]@{ VmPath = '%PROGRAMFILES%\Git\cmd\git.exe'; RelativePath = 'Git\cmd\git.exe' }
            OpenSSH = [pscustomobject]@{ VmPath = '%PROGRAMFILES%\Git\usr\bin\ssh.exe'; RelativePath = 'Git\usr\bin\ssh.exe' }
            OpenSSHKeygen = [pscustomobject]@{ VmPath = '%PROGRAMFILES%\Git\usr\bin\ssh-keygen.exe'; RelativePath = 'Git\usr\bin\ssh-keygen.exe' }
            PowerShell7 = [pscustomobject]@{ VmPath = '%PROGRAMFILES%\PowerShell\7\pwsh.exe'; RelativePath = 'PowerShell\7\pwsh.exe' }
            WindowsPowerShell = [pscustomobject]@{ VmPath = '%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe'; RelativePath = 'System32\WindowsPowerShell\v1.0\powershell.exe' }
        }
        if (-not [IO.Path]::IsPathRooted($ProgramFilesRoot) -or -not [IO.Path]::IsPathRooted($SystemRoot) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $ProgramFilesRoot) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $SystemRoot)) {
            throw 'VM_BOOTSTRAP_TOOL_ROOT_INVALID'
        }
        $toolManifest = @($manifest.Tools)
        if ($toolManifest.Count -ne $requiredTools.Count) { throw 'VM_BOOTSTRAP_TOOL_SET_INVALID' }
        $verifiedTools = @()
        foreach ($toolId in $requiredTools.Keys) {
            $toolMatches = @($toolManifest | Where-Object { $_.ToolId -ceq $toolId })
            if ($toolMatches.Count -ne 1 -or $toolMatches[0].VmPath -cne $requiredTools[$toolId].VmPath -or
                $toolMatches[0].Sha256 -cnotmatch '^[a-f0-9]{64}$') {
                throw ('VM_BOOTSTRAP_TOOL_BINDING_INVALID:' + $toolId)
            }
            $toolRoot = if ($toolId -ceq 'WindowsPowerShell') { $SystemRoot } else { $ProgramFilesRoot }
            $toolPath = Join-Path $toolRoot $requiredTools[$toolId].RelativePath
            Assert-CddsiFastLanePinnedFile -Path $toolPath -Sha256 $toolMatches[0].Sha256 -ErrorPrefix 'VM_BOOTSTRAP_TOOL'
            $verifiedTools += [pscustomobject][ordered]@{
                ToolId = $toolId
                Sha256 = [string]$toolMatches[0].Sha256
                PathBindingToken = Get-CddsiFastLaneCanonicalPathSha256 $toolPath
            }
        }
        if ($manifest.Policy.SshTrust.OpenSshKeygenToolId -cne 'OpenSSHKeygen' -or
            $manifest.Policy.SshTrust.OpenSshKeygenVmPath -cne '%PROGRAMFILES%\Git\usr\bin\ssh-keygen.exe' -or
            $manifest.Policy.SshTrust.KnownHostsSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            -not $manifest.Policy.SshTrust.StrictHostKeyCheckingRequired) {
            throw 'VM_BOOTSTRAP_SSH_TRUST_BINDING_INVALID'
        }
        $requiredSourceBindings = [ordered]@{
            Policy = 'config/fast-lane-policy.psd1'
            KnownHosts = 'operator/fast-lane/trust/github-known-hosts'
            Runner = 'operator/fast-lane/invoke-git-outbox.ps1'
            VmPollPrompt = 'operator/fast-lane/prompts/vm-poll.md'
            ResetLibrary = 'lib/vm-reset.ps1'
            ResetRunner = 'operator/fast-lane/invoke-vm-reset-live.ps1'
            ResetProvider = 'operator/fast-lane/providers/windows-vm-reset.ps1'
        }
        $sourceBindings = [ordered]@{}
        foreach ($bindingName in $requiredSourceBindings.Keys) {
            $bindingMatches = @($inventoryEntries | Where-Object {
                $_.SourcePath -ceq $requiredSourceBindings[$bindingName]
            })
            if ($bindingMatches.Count -ne 1 -or $bindingMatches[0].Sha256 -cnotmatch '^[a-f0-9]{64}$') {
                throw ('VM_BOOTSTRAP_SOURCE_BINDING_INVALID:' + $bindingName)
            }
            $sourceBindings[$bindingName + 'Sha256'] = [string]$bindingMatches[0].Sha256
        }
        if ($sourceBindings.PolicySha256 -cne $manifest.Policy.Sha256 -or
            $sourceBindings.KnownHostsSha256 -cne $manifest.Policy.SshTrust.KnownHostsSha256) {
            throw 'VM_BOOTSTRAP_POLICY_SOURCE_BINDING_MISMATCH'
        }
        $repositoryFacts = [pscustomobject][ordered]@{
            Product = [pscustomobject][ordered]@{
                RepositoryIdentity = 'github.com/' + [string]$manifest.Product.Repository.FullName
                RepositoryNumericId = [long]$manifest.Product.Repository.Id
                RepositoryNodeId = [string]$manifest.Product.Repository.NodeId
                Visibility = 'PUBLIC'
                Ref = [string]$manifest.Product.RepairRef
                IntendedAccess = 'READ_ONLY_EXACT_COMMIT'
            }
            HostToVm = [pscustomobject][ordered]@{
                RepositoryIdentity = 'github.com/' + [string]$manifest.ControlRepositories.HostToVm.Repository.FullName
                RepositoryNumericId = [long]$manifest.ControlRepositories.HostToVm.Repository.Id
                RepositoryNodeId = [string]$manifest.ControlRepositories.HostToVm.Repository.NodeId
                Visibility = 'PUBLIC'
                Ref = [string]$manifest.Policy.HostToVmRepository.Ref
                IntendedAccess = 'READ_ONLY'
                GenesisCommitSha = [string]$manifest.ControlRepositories.HostToVm.GenesisSha
            }
            VmToHost = [pscustomobject][ordered]@{
                RepositoryIdentity = 'github.com/' + [string]$manifest.ControlRepositories.VmToHost.Repository.FullName
                RepositoryNumericId = [long]$manifest.ControlRepositories.VmToHost.Repository.Id
                RepositoryNodeId = [string]$manifest.ControlRepositories.VmToHost.Repository.NodeId
                Visibility = 'PUBLIC'
                Ref = [string]$manifest.Policy.VmToHostRepository.Ref
                IntendedAccess = 'APPEND_ONLY'
                GenesisCommitSha = [string]$manifest.ControlRepositories.VmToHost.GenesisSha
            }
        }
        $protectionFacts = [pscustomobject][ordered]@{
            RepositoryVisibility = 'PUBLIC'
            PolicySha256 = [string]$sourceBindings.PolicySha256
            HostProtectionFactsAreSenderAuthority = $false
            RemoteAuthorizationStatus = 'UNPROVISIONED'
            RuntimeProtectionAssertionStatus = 'UNPROVISIONED'
        }
        $credentialProfiles = @(
            [pscustomobject][ordered]@{
                ProfileId = 'vm.host-to-vm.read'; Repository = $manifest.ControlRepositories.HostToVm.Repository
                Ref = $manifest.Policy.HostToVmRepository.Ref; IntendedAccess = 'READ_ONLY'
            },
            [pscustomobject][ordered]@{
                ProfileId = 'vm.vm-to-host.write'; Repository = $manifest.ControlRepositories.VmToHost.Repository
                Ref = $manifest.Policy.VmToHostRepository.Ref; IntendedAccess = 'APPEND_ONLY'
            },
            [pscustomobject][ordered]@{
                ProfileId = 'vm.product.read'; Repository = $manifest.Product.Repository
                Ref = $manifest.Product.RepairRef; IntendedAccess = 'READ_ONLY_EXACT_COMMIT'
            }
        )
        foreach ($profile in $credentialProfiles) {
            if ($profile.Repository.Id -isnot [int] -and $profile.Repository.Id -isnot [long]) {
                throw 'VM_BOOTSTRAP_CREDENTIAL_REPOSITORY_BINDING_INVALID'
            }
            if ([long]$profile.Repository.Id -lt 1 -or
                $profile.Repository.NodeId -cnotmatch '^[A-Za-z0-9_=-]{4,128}$' -or
                $profile.Repository.FullName -cnotmatch '^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
                $profile.Ref -cnotmatch '^refs/heads/[A-Za-z0-9._*/-]+$') {
                throw 'VM_BOOTSTRAP_CREDENTIAL_REPOSITORY_BINDING_INVALID'
            }
        }
        $bootstrapAutomationProperties = @(
            'Id', 'Kind', 'Name', 'Status', 'RRule', 'CadenceMinutes',
            'DestinationContract', 'TargetTaskToken', 'ReconcileMode'
        )
        $bootstrapAutomation = $manifest.BootstrapAutomation
        if (-not (Test-CddsiExactPropertySet -InputObject $bootstrapAutomation -Expected $bootstrapAutomationProperties) -or
            $bootstrapAutomation.Id -cne 'cddsi-fast-lane-vmtester-minute-poll' -or
            $bootstrapAutomation.Kind -cne 'heartbeat' -or
            $bootstrapAutomation.Name -cne 'CDDsi Fast Lane VmTester minute poll' -or
            $bootstrapAutomation.Status -cne 'PAUSED' -or
            $bootstrapAutomation.RRule -cne 'FREQ=MINUTELY;INTERVAL=1' -or
            [long]$bootstrapAutomation.CadenceMinutes -ne 1 -or
            $bootstrapAutomation.DestinationContract -cne 'local' -or
            $bootstrapAutomation.TargetTaskToken -cne 'CURRENT_TASK' -or
            $bootstrapAutomation.ReconcileMode -cne 'CREATE_OR_UPDATE_EXACTLY_ONE') {
            throw 'VM_BOOTSTRAP_AUTOMATION_CONTRACT_INVALID'
        }
        [byte[]]$internalBoundZipBytes = $null
        if ($null -ne $BoundZipBytes) { $internalBoundZipBytes = $zipBytes }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-onboarding-package-verification-v1'
            Status = 'VERIFIED'; IsValid = $true; EvidenceClass = 'DIAGNOSTIC_ONLY'
            ZipSha256 = $ExpectedZipSha256; ZipLengthBytes = $ExpectedZipLengthBytes
            ManifestSha256 = $ExpectedManifestSha256; ManifestLengthBytes = $ExpectedManifestLengthBytes
            ManifestBindingToken = $ExpectedManifestBindingToken
            InventorySha256 = $ExpectedInventorySha256; InventoryLengthBytes = $ExpectedInventoryLengthBytes
            InventoryBindingToken = $ExpectedInventoryBindingToken
            BundleContentDigestSha256 = $contentDigest
            ProductCommitSha = $ExpectedProductCommitSha; ProductTreeSha = $ExpectedProductTreeSha
            VmAutomationId = 'cddsi-fast-lane-vmtester-minute-poll'; VmAutomationStatus = 'PAUSED'
            Tools = @($verifiedTools); ToolCount = $verifiedTools.Count
            SourceBindings = [pscustomobject]$sourceBindings
            RepositoryFacts = $repositoryFacts
            ProtectionFacts = $protectionFacts
            CredentialProfiles = @($credentialProfiles | ForEach-Object {
                [pscustomobject][ordered]@{
                    ProfileId = $_.ProfileId; RepositoryIdentity = 'github.com/' + $_.Repository.FullName
                    RepositoryId = [long]$_.Repository.Id; RepositoryNodeId = [string]$_.Repository.NodeId
                    Ref = [string]$_.Ref; IntendedAccess = [string]$_.IntendedAccess
                }
            })
            AutomationContract = [pscustomobject][ordered]@{
                Id = $bootstrapAutomation.Id; Kind = $bootstrapAutomation.Kind; Name = $bootstrapAutomation.Name
                Status = $bootstrapAutomation.Status; RRule = $bootstrapAutomation.RRule
                CadenceMinutes = [long]$bootstrapAutomation.CadenceMinutes
                DestinationContract = $bootstrapAutomation.DestinationContract
                TargetTaskToken = $bootstrapAutomation.TargetTaskToken
                ReconcileMode = $bootstrapAutomation.ReconcileMode
            }
            InventoryEntries = @($inventoryEntries | ForEach-Object {
                [pscustomobject][ordered]@{
                    Path = [string]$_.Path; Sha256 = [string]$_.Sha256; LengthBytes = [long]$_.LengthBytes
                }
            })
            InternalBoundZipBytes = $internalBoundZipBytes
            ArchiveReadOnly = $true; CredentialStatus = 'UNPROVISIONED'; RuntimeProtectionAssertionStatus = 'UNPROVISIONED'
            NetworkRequestCount = 0; GitInvocationCount = 0; ProductLiveInvocationCount = 0; ProductWriteCount = 0
        }
    }
    finally {
        $archive.Dispose()
        $memory.Dispose()
    }
}

function New-CddsiFastLaneVmBootstrapPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$CredentialRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe'
    )

    if ($Package.IsValid -ne $true -or $Package.Status -cne 'VERIFIED' -or $Package.ToolCount -ne 5) {
        throw 'VM_BOOTSTRAP_PACKAGE_NOT_VERIFIED'
    }
    if (-not [IO.Path]::IsPathRooted($CredentialRoot) -or -not [IO.Path]::IsPathRooted($ProductRoot)) {
        throw 'VM_BOOTSTRAP_ROOT_NOT_ABSOLUTE'
    }
    $credentialFull = [IO.Path]::GetFullPath($CredentialRoot).TrimEnd('\', '/')
    $productFull = [IO.Path]::GetFullPath($ProductRoot).TrimEnd('\', '/')
    if ([IO.Path]::GetFileName($credentialFull) -cnotmatch '^cddsi-vm-bootstrap-[a-f0-9]{32}$' -or
        (Test-CddsiFastLanePathWithinRoot -Path $credentialFull -Root $productFull) -or
        (Test-CddsiFastLanePathWithinRoot -Path $productFull -Root $credentialFull)) {
        throw 'VM_BOOTSTRAP_CREDENTIAL_ROOT_FORBIDDEN'
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-plan-v1'
        Status = 'PLANNED'; Mode = $Mode; EvidenceClass = 'DIAGNOSTIC_ONLY'; BootstrapOnly = $true
        CredentialRootBindingToken = Get-CddsiFastLaneCanonicalPathSha256 $credentialFull
        ProductRootBindingToken = Get-CddsiFastLaneCanonicalPathSha256 $productFull
        KeyAlgorithm = 'ed25519'; KeyDerivationRounds = 64; Profiles = @($script:CddsiFastLaneVmBootstrapProfiles)
        PrivateKeyIncluded = $false; RealPathIncluded = $false; SidIncluded = $false
        AutomationId = 'cddsi-fast-lane-vmtester-minute-poll'; AutomationStatus = 'PAUSED'
        CredentialStatus = 'UNPROVISIONED'; VmCredentialReady = $false
        RuntimeProtectionAssertionStatus = 'UNPROVISIONED'
        DirectoryCreateCount = 0; FileWriteCount = 0; AclMutationCount = 0
        ProcessInvocationCount = 0; NetworkRequestCount = 0; GitInvocationCount = 0
        ProductLiveInvocationCount = 0; ProductWriteCount = 0
    }
}

function Set-CddsiFastLaneVmBootstrapProtectedAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Directory', 'File')][string]$PathKind = 'Directory'
    )

    throw 'VM_BOOTSTRAP_MUTATION_HELPER_DIRECT_INVOCATION_FORBIDDEN'
}

function Test-CddsiFastLaneVmBootstrapProtectedAcl {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Directory', 'File')][string]$PathKind = 'Directory'
    )

    try {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
        if ($null -eq $currentSid) { return $false }
        $sections = [Security.AccessControl.AccessControlSections]::Access -bor
            [Security.AccessControl.AccessControlSections]::Owner
        $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
        $security = if ($null -ne $aclExtensions -and $PathKind -ceq 'Directory') {
            [IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($Path), $sections)
        }
        elseif ($null -ne $aclExtensions) {
            [IO.FileSystemAclExtensions]::GetAccessControl([IO.FileInfo]::new($Path), $sections)
        }
        elseif ($PathKind -ceq 'Directory') {
            [IO.DirectoryInfo]::new($Path).GetAccessControl($sections)
        }
        else { [IO.FileInfo]::new($Path).GetAccessControl($sections) }
        if (-not $security.AreAccessRulesProtected -or
            $security.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $currentSid.Value) {
            return $false
        }
        $expected = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        [void]$expected.Add($currentSid.Value)
        [void]$expected.Add($systemSid.Value)
        $seen = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        $expectedInheritance = if ($PathKind -ceq 'Directory') {
            [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else { [Security.AccessControl.InheritanceFlags]::None }
        $rules = @($security.GetAccessRules($true, $true, [Security.Principal.SecurityIdentifier]))
        foreach ($rule in $rules) {
            $sid = $rule.IdentityReference.Value
            if ($rule.IsInherited -or $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
                -not $expected.Contains($sid) -or -not $seen.Add($sid) -or
                $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or
                $rule.InheritanceFlags -ne $expectedInheritance -or
                $rule.PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None) {
                return $false
            }
        }
        return ($seen.Count -eq $expected.Count)
    }
    catch { return $false }
}

function Get-CddsiFastLaneVmBootstrapAclBindingToken {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [ValidateSet('Directory', 'File')][string]$PathKind = 'Directory'
    )

    $sections = [Security.AccessControl.AccessControlSections]::Access -bor
        [Security.AccessControl.AccessControlSections]::Owner
    $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
    $security = if ($null -ne $aclExtensions -and $PathKind -ceq 'Directory') {
        [IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($Path), $sections)
    }
    elseif ($null -ne $aclExtensions) {
        [IO.FileSystemAclExtensions]::GetAccessControl([IO.FileInfo]::new($Path), $sections)
    }
    elseif ($PathKind -ceq 'Directory') {
        [IO.DirectoryInfo]::new($Path).GetAccessControl($sections)
    }
    else { [IO.FileInfo]::new($Path).GetAccessControl($sections) }
    return Get-CddsiSupplyChainTextBindingToken -Text `
        ($security.GetSecurityDescriptorSddlForm($sections))
}

function Get-CddsiFastLaneVmBootstrapOwnedDirectoryBindingToken {
    param([Parameter(Mandatory = $true)][string]$Path)

    $canonical = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/').ToUpperInvariant()
    return Get-CddsiSupplyChainTextBindingToken -Text $canonical
}

function Test-CddsiFastLaneVmBootstrapOwnedParent {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet(
            'Project', 'FastLane', 'PackageParent', 'CredentialParent')][string]$Role
    )

    try {
        $full = [IO.Path]::GetFullPath($Path).TrimEnd('\', '/')
        if (-not [IO.Directory]::Exists($full) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $full) -or
            -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $full -PathKind Directory)) {
            return $false
        }
        $markerPath = Join-Path $full '.cddsi-directory-owner.json'
        if (-not [IO.File]::Exists($markerPath) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
            return $false
        }
        $marker = Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 16384
        return (
            (Test-CddsiExactPropertySet -InputObject $marker -Expected @(
                    'SchemaVersion','ContractVersion','Role','RootBindingSha256','AclBindingSha256'
                )) -and
            $marker.SchemaVersion -eq 1 -and
            $marker.ContractVersion -ceq 'cddsi-fast-lane-bootstrap-directory-owner-v1' -and
            $marker.Role -ceq $Role -and
            $marker.RootBindingSha256 -ceq
                (Get-CddsiFastLaneVmBootstrapOwnedDirectoryBindingToken $full) -and
            $marker.AclBindingSha256 -ceq
                (Get-CddsiFastLaneVmBootstrapAclBindingToken -Path $full -PathKind Directory)
        )
    }
    catch { return $false }
}

function Test-CddsiFastLaneVmBootstrapOwnedParentChain {
    param(
        [Parameter(Mandatory = $true)][string]$LeafParent,
        [Parameter(Mandatory = $true)][ValidateSet('PackageParent', 'CredentialParent')][string]$LeafRole
    )

    try {
        $leafFull = [IO.Path]::GetFullPath($LeafParent).TrimEnd('\', '/')
        $fastLaneRoot = [IO.Path]::GetDirectoryName($leafFull).TrimEnd('\', '/')
        $projectRoot = [IO.Path]::GetDirectoryName($fastLaneRoot).TrimEnd('\', '/')
        $expectedLeaf = if ($LeafRole -ceq 'PackageParent') { 'packages' } else { 'credentials' }
        if ([IO.Path]::GetFileName($leafFull) -cne $expectedLeaf -or
            [IO.Path]::GetFileName($fastLaneRoot) -cne 'FastLane' -or
            [IO.Path]::GetFileName($projectRoot) -cne 'CDDsi') {
            return $false
        }
        return (
            (Test-CddsiFastLaneVmBootstrapOwnedParent -Path $projectRoot -Role Project) -and
            (Test-CddsiFastLaneVmBootstrapOwnedParent -Path $fastLaneRoot -Role FastLane) -and
            (Test-CddsiFastLaneVmBootstrapOwnedParent -Path $leafFull -Role $LeafRole)
        )
    }
    catch { return $false }
}

function Test-CddsiFastLaneVmBootstrapGuidD {
    param([AllowNull()]$Value)

    if ($Value -isnot [string]) { return $false }
    $parsed = [guid]::Empty
    return ([guid]::TryParseExact($Value, 'D', [ref]$parsed) -and
        $Value -ceq $parsed.ToString('D'))
}

function New-CddsiFastLaneVmBootstrapCredentialMarker {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ExpectedSshKeygenSha256,
        [Parameter(Mandatory = $true)][ValidateSet('Provisioning', 'Ready')][string]$Stage,
        [Parameter(Mandatory = $true)][ValidateSet('UNPROVISIONED', 'KEYPAIR_STAGED')][string]$CredentialStatus,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ProfileReceipts
    )

    if (-not (Test-CddsiFastLaneVmBootstrapGuidD $RunId) -or
        ($Stage -ceq 'Provisioning' -and (
            $CredentialStatus -cne 'UNPROVISIONED' -or $ProfileReceipts.Count -ne 0)) -or
        ($Stage -ceq 'Ready' -and (
            $CredentialStatus -cne 'KEYPAIR_STAGED' -or $ProfileReceipts.Count -ne 3))) {
        throw 'VM_BOOTSTRAP_CREDENTIAL_MARKER_INPUT_INVALID'
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = $script:CddsiFastLaneVmBootstrapOwnerContract
        Owner = 'CDDsiFastLaneVmBootstrap'; OperatorPlaneOnly = $true; RunId = $RunId
        CredentialRootBindingToken = $Plan.CredentialRootBindingToken; Stage = $Stage
        ProductCommitSha = $Package.ProductCommitSha; ProductTreeSha = $Package.ProductTreeSha
        ZipSha256 = $Package.ZipSha256; ZipLengthBytes = [long]$Package.ZipLengthBytes
        ManifestSha256 = $Package.ManifestSha256; ManifestLengthBytes = [long]$Package.ManifestLengthBytes
        ManifestBindingToken = $Package.ManifestBindingToken
        InventorySha256 = $Package.InventorySha256; InventoryLengthBytes = [long]$Package.InventoryLengthBytes
        InventoryBindingToken = $Package.InventoryBindingToken
        BundleContentDigestSha256 = $Package.BundleContentDigestSha256
        SshKeygenSha256 = $ExpectedSshKeygenSha256; CredentialStatus = $CredentialStatus
        VmCredentialReady = $false; ProfileReceipts = @($ProfileReceipts)
    }
}

function Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [ValidateSet('Generate', 'DerivePublic')][string]$Operation = 'Generate'
    )

    throw 'VM_BOOTSTRAP_MUTATION_HELPER_DIRECT_INVOCATION_FORBIDDEN'
}

function New-CddsiFastLaneVmBootstrapProfileReceipt {
    param(
        [Parameter(Mandatory = $true)][string]$ProfileId,
        [Parameter(Mandatory = $true)][string]$PublicKey,
        [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
        [Parameter(Mandatory = $true)]$Package
    )

    if ($script:CddsiFastLaneVmBootstrapProfiles -cnotcontains $ProfileId -or
        $PublicKey -cnotmatch '^ssh-ed25519 ([A-Za-z0-9+/]+={0,3}) cddsi:([a-z0-9.-]+)$' -or
        $Matches[2] -cne $ProfileId) {
        throw 'VM_BOOTSTRAP_PUBLIC_KEY_INVALID'
    }
    try { $blob = [Convert]::FromBase64String($Matches[1]) }
    catch { throw 'VM_BOOTSTRAP_PUBLIC_KEY_INVALID' }
    if ($blob.Length -lt 32 -or $blob.Length -gt 4096) { throw 'VM_BOOTSTRAP_PUBLIC_KEY_INVALID' }
    $sha = [Security.Cryptography.SHA256]::Create()
    try { $fingerprint = 'SHA256:' + [Convert]::ToBase64String($sha.ComputeHash($blob)).TrimEnd('=') }
    finally { $sha.Dispose() }
    if (-not [IO.Path]::IsPathRooted($PrivateKeyPath) -or -not [IO.File]::Exists($PrivateKeyPath) -or
        -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $PrivateKeyPath -PathKind File)) {
        throw 'VM_BOOTSTRAP_PRIVATE_KEY_BINDING_INVALID'
    }
    $profileBinding = @($Package.CredentialProfiles | Where-Object { $_.ProfileId -ceq $ProfileId })
    if ($profileBinding.Count -ne 1 -or $profileBinding[0].RepositoryId -lt 1 -or
        $profileBinding[0].RepositoryNodeId -cnotmatch '^[A-Za-z0-9_=-]{4,128}$' -or
        $profileBinding[0].Ref -cnotmatch '^refs/heads/[A-Za-z0-9._*/-]+$') {
        throw 'VM_BOOTSTRAP_PRIVATE_KEY_AUTHORITY_BINDING_INVALID'
    }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
    if ($null -eq $currentSid) { throw 'VM_BOOTSTRAP_CURRENT_SID_UNAVAILABLE' }
    $aclPayload = [pscustomobject][ordered]@{
        ContractVersion = 'cddsi-fast-lane-vm-key-acl-v1'; Protected = $true
        OwnerSid = $currentSid.Value; SystemSid = 'S-1-5-18'; Rights = 'FullControl'; PathKind = 'File'
    }
    $receipt = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-key-profile-receipt-v1'
        ProfileId = $ProfileId; Algorithm = 'ssh-ed25519'; PublicKey = $PublicKey
        PublicKeySha256 = Get-CddsiSupplyChainTextBindingToken -Text $PublicKey
        PublicKeyFingerprint = $fingerprint; State = 'KEYPAIR_STAGED'
        PrivateKeySha256 = Get-CddsiFastLaneGitFileSha256 $PrivateKeyPath
        PrivateKeyPathBindingToken = Get-CddsiFastLaneCanonicalPathSha256 $PrivateKeyPath
        PrivateKeyAclBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $aclPayload
        CurrentSidBindingToken = Get-CddsiSupplyChainTextBindingToken -Text $currentSid.Value
        RepositoryIdentity = $profileBinding[0].RepositoryIdentity
        RepositoryId = [long]$profileBinding[0].RepositoryId
        RepositoryNodeId = $profileBinding[0].RepositoryNodeId
        Ref = $profileBinding[0].Ref; IntendedAccess = $profileBinding[0].IntendedAccess
        ZipSha256 = $Package.ZipSha256; ZipLengthBytes = [long]$Package.ZipLengthBytes
        ManifestSha256 = $Package.ManifestSha256; ManifestLengthBytes = [long]$Package.ManifestLengthBytes
        ManifestBindingToken = $Package.ManifestBindingToken
        InventorySha256 = $Package.InventorySha256; InventoryLengthBytes = [long]$Package.InventoryLengthBytes
        InventoryBindingToken = $Package.InventoryBindingToken
        BundleContentDigestSha256 = $Package.BundleContentDigestSha256
        ProductCommitSha = $Package.ProductCommitSha; ProductTreeSha = $Package.ProductTreeSha
        RemoteAuthorizationStatus = 'UNPROVISIONED'; VmCredentialReady = $false
        ReceiptBindingToken = $null
    }
    $payload = [ordered]@{}
    foreach ($property in $receipt.PSObject.Properties) {
        if ($property.Name -cne 'ReceiptBindingToken') { $payload[$property.Name] = $property.Value }
    }
    $receipt.ReceiptBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $payload
    return $receipt
}

function New-CddsiFastLaneVmBootstrapSafeResult {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][object[]]$Profiles,
        [Parameter(Mandatory = $true)][bool]$Changed,
        [Parameter(Mandatory = $true)][bool]$ReusedExisting,
        [Parameter(Mandatory = $true)][int]$DirectoryCreateCount,
        [Parameter(Mandatory = $true)][int]$FileWriteCount,
        [Parameter(Mandatory = $true)][int]$AclMutationCount,
        [Parameter(Mandatory = $true)][int]$ProcessInvocationCount
    )

    if ($Profiles.Count -ne 3 -or
        (@($Profiles.ProfileId | Sort-Object) -join "`n") -cne (@($script:CddsiFastLaneVmBootstrapProfiles | Sort-Object) -join "`n") -or
        @($Profiles.PublicKeyFingerprint | Select-Object -Unique).Count -ne 3 -or
        @($Profiles.ReceiptBindingToken | Select-Object -Unique).Count -ne 3 -or
        @($Profiles.ReceiptSha256 | Select-Object -Unique).Count -ne 3) {
        throw 'VM_BOOTSTRAP_PROFILE_SET_NOT_DISTINCT'
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = $script:CddsiFastLaneVmBootstrapResultContract
        Status = 'VM_BOOTSTRAP_LOCAL_STAGED'; Mode = 'Live'; Changed = $Changed; ReusedExisting = $ReusedExisting
        EvidenceClass = 'DIAGNOSTIC_ONLY'; BootstrapOnly = $true
        CredentialRootBindingToken = $Plan.CredentialRootBindingToken
        ProductCommitSha = $Package.ProductCommitSha; ProductTreeSha = $Package.ProductTreeSha
        ZipSha256 = $Package.ZipSha256; ZipLengthBytes = [long]$Package.ZipLengthBytes
        ManifestSha256 = $Package.ManifestSha256; ManifestLengthBytes = [long]$Package.ManifestLengthBytes
        ManifestBindingToken = $Package.ManifestBindingToken
        InventorySha256 = $Package.InventorySha256; InventoryLengthBytes = [long]$Package.InventoryLengthBytes
        InventoryBindingToken = $Package.InventoryBindingToken
        BundleContentDigestSha256 = $Package.BundleContentDigestSha256
        Profiles = @($Profiles); ProfileCount = $Profiles.Count
        ProfileReceiptSetBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken @($Profiles)
        PrivateKeyIncluded = $false; RealPathIncluded = $false; SidIncluded = $false
        CredentialStatus = 'KEYPAIR_STAGED'; RemoteAuthorizationStatus = 'UNPROVISIONED'
        VmCredentialReady = $false; RuntimeProtectionAssertionStatus = 'UNPROVISIONED'
        AutomationId = $Package.AutomationContract.Id; AutomationStatus = $Package.AutomationContract.Status
        DirectoryCreateCount = $DirectoryCreateCount
        FileWriteCount = $FileWriteCount; AclMutationCount = $AclMutationCount
        ProcessInvocationCount = $ProcessInvocationCount
        NetworkRequestCount = 0; GitInvocationCount = 0; ProductLiveInvocationCount = 0; ProductWriteCount = 0
    }
}

function Test-CddsiFastLaneVmBootstrapCredentialRootExactFiles {
    param([Parameter(Mandatory = $true)][string]$CredentialRoot)

    if (-not [IO.Directory]::Exists($CredentialRoot) -or
        -not (Test-CddsiFastLanePathWithoutReparsePoint $CredentialRoot)) { return $false }
    $expectedFiles = @('.cddsi-owner.json')
    foreach ($profileId in $script:CddsiFastLaneVmBootstrapProfiles) {
        $expectedFiles += ($profileId + '.key')
        $expectedFiles += ($profileId + '.key.pub')
        $expectedFiles += ($profileId + '.receipt.json')
    }
    $actualPaths = @([IO.Directory]::EnumerateFiles($CredentialRoot))
    $actualFiles = @($actualPaths | ForEach-Object { [IO.Path]::GetFileName($_) } | Sort-Object)
    if ((@($expectedFiles | Sort-Object) -join "`n") -cne ($actualFiles -join "`n") -or
        @([IO.Directory]::EnumerateDirectories($CredentialRoot)).Count -ne 0) { return $false }
    foreach ($path in $actualPaths) {
        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $path)) { return $false }
    }
    return $true
}

function Get-CddsiFastLaneVmBootstrapExistingResult {
    param(
        [Parameter(Mandatory = $true)][string]$CredentialRoot,
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][string]$ExpectedSshKeygenSha256,
        [Parameter(Mandatory = $true)][string]$SshKeygenExecutable
    )

    $processInvocationCount = 0
    try {
        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $CredentialRoot) -or
            -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $CredentialRoot -PathKind Directory)) {
            throw 'VM_BOOTSTRAP_EXISTING_ROOT_INVALID'
        }
        $markerPath = Join-Path $CredentialRoot '.cddsi-owner.json'
        if (-not [IO.File]::Exists($markerPath) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath) -or
            -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $markerPath -PathKind File)) {
            throw 'VM_BOOTSTRAP_EXISTING_ROOT_INVALID'
        }
        $marker = Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768
        $markerProperties = @(
            'SchemaVersion','ContractVersion','Owner','OperatorPlaneOnly','RunId',
            'CredentialRootBindingToken','Stage','ProductCommitSha','ProductTreeSha',
            'ZipSha256','ZipLengthBytes','ManifestSha256','ManifestLengthBytes',
            'ManifestBindingToken','InventorySha256','InventoryLengthBytes',
            'InventoryBindingToken','BundleContentDigestSha256','SshKeygenSha256',
            'CredentialStatus','VmCredentialReady','ProfileReceipts'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $marker -Expected $markerProperties) -or
            $marker.SchemaVersion -ne 1 -or
            $marker.ContractVersion -cne $script:CddsiFastLaneVmBootstrapOwnerContract -or
            $marker.Owner -cne 'CDDsiFastLaneVmBootstrap' -or $marker.OperatorPlaneOnly -ne $true -or
            -not (Test-CddsiFastLaneVmBootstrapGuidD $marker.RunId) -or
            $marker.Stage -cne 'Ready' -or $marker.CredentialStatus -cne 'KEYPAIR_STAGED' -or
            $marker.VmCredentialReady -ne $false -or @($marker.ProfileReceipts).Count -ne 3 -or
            $marker.CredentialRootBindingToken -cne $Plan.CredentialRootBindingToken) {
            throw 'VM_BOOTSTRAP_EXISTING_ROOT_INVALID'
        }
        if (-not (Test-CddsiFastLaneVmBootstrapCredentialRootExactFiles $CredentialRoot)) {
            throw 'VM_BOOTSTRAP_EXISTING_ROOT_INVALID'
        }
        $profiles = @()
        foreach ($profileId in $script:CddsiFastLaneVmBootstrapProfiles) {
            $privatePath = Join-Path $CredentialRoot ($profileId + '.key')
            $publicPath = $privatePath + '.pub'
            $receiptPath = Join-Path $CredentialRoot ($profileId + '.receipt.json')
            foreach ($path in @($privatePath, $publicPath, $receiptPath)) {
                if (-not [IO.File]::Exists($path) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $path) -or
                    -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $path -PathKind File)) {
                    throw 'VM_BOOTSTRAP_EXISTING_PROFILE_INVALID'
                }
            }
            if ([IO.FileInfo]::new($privatePath).Length -lt 32) {
                throw 'VM_BOOTSTRAP_EXISTING_PROFILE_INVALID'
            }
            $publicKey = [IO.File]::ReadAllText(
                $publicPath, (New-Object Text.UTF8Encoding($false, $true))).Trim()
            $processInvocationCount++
            $derive = Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Executable $SshKeygenExecutable `
                -PrivateKeyPath $privatePath -ProfileId $profileId -Operation DerivePublic
            if ($null -eq $derive -or $derive.ExitCode -ne 0 -or $derive.TimedOut -or
                $derive.Truncated -or $derive.JobAssigned -ne $true -or
                $derive.StandardOutput -isnot [string]) {
                throw 'VM_BOOTSTRAP_EXISTING_KEYPAIR_DERIVATION_FAILED'
            }
            $publicParts = @($publicKey -split ' ')
            $derivedParts = @($derive.StandardOutput.Trim() -split ' ')
            if ($publicParts.Count -ne 3 -or $derivedParts.Count -ne 2 -or
                $publicParts[0] -cne $derivedParts[0] -or $publicParts[1] -cne $derivedParts[1]) {
                throw 'VM_BOOTSTRAP_EXISTING_KEYPAIR_MISMATCH'
            }
            $expectedReceipt = New-CddsiFastLaneVmBootstrapProfileReceipt -ProfileId $profileId `
                -PublicKey $publicKey -PrivateKeyPath $privatePath -Package $Package
            $receipt = Read-CddsiFastLaneCanonicalFile -Path $receiptPath -MaximumBytes 16384
            if ((ConvertTo-CddsiVmTestRelayCanonicalJson $receipt) -cne
                (ConvertTo-CddsiVmTestRelayCanonicalJson $expectedReceipt)) {
                throw 'VM_BOOTSTRAP_EXISTING_PROFILE_INVALID'
            }
            $receiptSha = Get-CddsiFastLaneGitFileSha256 $receiptPath
            $profiles += [pscustomobject][ordered]@{
                ProfileId = $profileId; Algorithm = 'ssh-ed25519'; PublicKey = $receipt.PublicKey
                PublicKeySha256 = $receipt.PublicKeySha256; PublicKeyFingerprint = $receipt.PublicKeyFingerprint
                State = 'KEYPAIR_STAGED'; RemoteAuthorizationStatus = 'UNPROVISIONED'; VmCredentialReady = $false
                ReceiptBindingToken = $receipt.ReceiptBindingToken; ReceiptSha256 = $receiptSha
            }
        }
        $expectedMarkerReceipts = @($profiles | ForEach-Object {
            [pscustomobject][ordered]@{
                ProfileId = $_.ProfileId; PublicKeyFingerprint = $_.PublicKeyFingerprint
                ReceiptBindingToken = $_.ReceiptBindingToken; ReceiptSha256 = $_.ReceiptSha256
            }
        })
        $expectedMarker = New-CddsiFastLaneVmBootstrapCredentialMarker `
            -Package $Package -Plan $Plan -RunId $marker.RunId `
            -ExpectedSshKeygenSha256 $ExpectedSshKeygenSha256 -Stage Ready `
            -CredentialStatus KEYPAIR_STAGED -ProfileReceipts $expectedMarkerReceipts
        if ((ConvertTo-CddsiVmTestRelayCanonicalJson $marker) -cne
            (ConvertTo-CddsiVmTestRelayCanonicalJson $expectedMarker)) {
            throw 'VM_BOOTSTRAP_EXISTING_ROOT_INVALID'
        }
        return New-CddsiFastLaneVmBootstrapSafeResult `
            -Package $Package -Plan $Plan -Profiles $profiles -Changed $false `
            -ReusedExisting $true -DirectoryCreateCount 0 -FileWriteCount 0 `
            -AclMutationCount 0 -ProcessInvocationCount $processInvocationCount
    }
    catch {
        Set-CddsiFastLaneVmBootstrapFailureAccounting -Exception $_.Exception `
            -DirectoryCreateCount 0 -FileWriteCount 0 -AclMutationCount 0 `
            -ProcessInvocationCount $processInvocationCount -DirectoryDeleteCount 0 `
            -CleanupRequired $false -CleanupSucceeded $true
        throw
    }
}

function Remove-CddsiFastLaneVmBootstrapOwnedRoot {
    param(
        [Parameter(Mandatory = $true)][string]$CredentialRoot,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    throw 'VM_BOOTSTRAP_MUTATION_HELPER_DIRECT_INVOCATION_FORBIDDEN'
}

function Set-CddsiFastLaneVmBootstrapFailureAccounting {
    param(
        [Parameter(Mandatory = $true)][Exception]$Exception,
        [Parameter(Mandatory = $true)][int]$DirectoryCreateCount,
        [Parameter(Mandatory = $true)][int]$FileWriteCount,
        [Parameter(Mandatory = $true)][int]$AclMutationCount,
        [Parameter(Mandatory = $true)][int]$ProcessInvocationCount,
        [Parameter(Mandatory = $true)][int]$DirectoryDeleteCount,
        [Parameter(Mandatory = $true)][bool]$CleanupRequired,
        [Parameter(Mandatory = $true)][bool]$CleanupSucceeded
    )

    $Exception.Data['CddsiDirectoryCreateCount'] = $DirectoryCreateCount
    $Exception.Data['CddsiFileWriteCount'] = $FileWriteCount
    $Exception.Data['CddsiAclMutationCount'] = $AclMutationCount
    $Exception.Data['CddsiProcessInvocationCount'] = $ProcessInvocationCount
    $Exception.Data['CddsiDirectoryDeleteCount'] = $DirectoryDeleteCount
    $Exception.Data['CddsiCleanupRequired'] = $CleanupRequired
    $Exception.Data['CddsiCleanupSucceeded'] = $CleanupSucceeded
}

function Get-CddsiFastLaneVmBootstrapFailureAccounting {
    param([Parameter(Mandatory = $true)][Exception]$Exception)

    $integerKeys = @(
        'CddsiDirectoryCreateCount', 'CddsiFileWriteCount', 'CddsiAclMutationCount',
        'CddsiProcessInvocationCount', 'CddsiDirectoryDeleteCount'
    )
    $values = [ordered]@{}
    foreach ($key in $integerKeys) {
        $values[$key.Substring(5)] = if ($Exception.Data.Contains($key)) { [int]$Exception.Data[$key] } else { 0 }
    }
    $values.CleanupRequired = if ($Exception.Data.Contains('CddsiCleanupRequired')) {
        [bool]$Exception.Data['CddsiCleanupRequired']
    } else { $false }
    $values.CleanupSucceeded = if ($Exception.Data.Contains('CddsiCleanupSucceeded')) {
        [bool]$Exception.Data['CddsiCleanupSucceeded']
    } else { $true }
    return [pscustomobject]$values
}

function Invoke-CddsiFastLaneVmBootstrap {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$CredentialRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$SshKeygenExecutable,
        [Parameter(Mandatory = $true)][string]$ExpectedSshKeygenSha256,
        [switch]$AcknowledgeVmBootstrapLive
    )

    throw 'VM_BOOTSTRAP_CORE_DIRECT_INVOCATION_FORBIDDEN'
}

$script:CddsiFastLaneVmPackageStagingOwnerContract = 'cddsi-fast-lane-vm-package-staging-owner-v1'

function Get-CddsiFastLaneVmBootstrapPackageMarker {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('Extracting', 'Extracted')][string]$Stage,
        [Parameter(Mandatory = $true)][string]$StagingRootBindingToken
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = $script:CddsiFastLaneVmPackageStagingOwnerContract
        Owner = 'CDDsiFastLaneVmPackageStaging'; OperatorPlaneOnly = $true; RunId = $RunId; Stage = $Stage
        StagingRootBindingToken = $StagingRootBindingToken
        ZipSha256 = $Package.ZipSha256; ZipLengthBytes = [long]$Package.ZipLengthBytes
        ManifestSha256 = $Package.ManifestSha256; ManifestLengthBytes = [long]$Package.ManifestLengthBytes
        ManifestBindingToken = $Package.ManifestBindingToken
        InventorySha256 = $Package.InventorySha256; InventoryLengthBytes = [long]$Package.InventoryLengthBytes
        InventoryBindingToken = $Package.InventoryBindingToken
        BundleContentDigestSha256 = $Package.BundleContentDigestSha256
        ProductCommitSha = $Package.ProductCommitSha; ProductTreeSha = $Package.ProductTreeSha
    }
}

function Test-CddsiFastLaneVmBootstrapPackageMarker {
    param(
        [Parameter(Mandatory = $true)]$Marker,
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$StagingRootBindingToken,
        [ValidateSet('Extracting', 'Extracted')][string]$ExpectedStage = 'Extracted'
    )

    $expected = Get-CddsiFastLaneVmBootstrapPackageMarker -Package $Package -RunId ([string]$Marker.RunId) `
        -Stage $ExpectedStage -StagingRootBindingToken $StagingRootBindingToken
    return ((Test-CddsiFastLaneVmBootstrapGuidD $Marker.RunId) -and
        (ConvertTo-CddsiVmTestRelayCanonicalJson $Marker) -ceq
        (ConvertTo-CddsiVmTestRelayCanonicalJson $expected))
}

function Remove-CddsiFastLaneVmBootstrapOwnedPackageRoot {
    param(
        [Parameter(Mandatory = $true)][string]$StagingRoot,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    throw 'VM_BOOTSTRAP_MUTATION_HELPER_DIRECT_INVOCATION_FORBIDDEN'
}

function Get-CddsiFastLaneVmBootstrapExpectedStagedFiles {
    param([Parameter(Mandatory = $true)]$Package)

    return @(
        [pscustomobject]@{ Path = 'manifest.json'; Sha256 = $Package.ManifestSha256; LengthBytes = [long]$Package.ManifestLengthBytes },
        [pscustomobject]@{ Path = 'inventory.json'; Sha256 = $Package.InventorySha256; LengthBytes = [long]$Package.InventoryLengthBytes }
    ) + @($Package.InventoryEntries)
}

function Test-CddsiFastLaneVmBootstrapStagedPackage {
    param(
        [Parameter(Mandatory = $true)][string]$StagingRoot,
        [Parameter(Mandatory = $true)]$Package
    )

    try {
        $rootFull = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\', '/')
        if (-not [IO.Directory]::Exists($rootFull) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $rootFull)) {
            return $false
        }
        $expected = @(Get-CddsiFastLaneVmBootstrapExpectedStagedFiles $Package)
        $expectedFileNames = @('.cddsi-owner.json') + @($expected.Path)
        $expectedDirectoryNames = New-Object `
            'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($item in $expected) {
            if (-not (Test-CddsiFastLaneVmBootstrapSafeRelativePath $item.Path)) {
                return $false
            }
            $segments = @([string]$item.Path -split '/')
            for ($index = 1; $index -lt $segments.Count; $index++) {
                [void]$expectedDirectoryNames.Add(($segments[0..($index - 1)] -join '/'))
            }
        }
        $actualFileNames = New-Object 'Collections.Generic.List[string]'
        $actualDirectoryNames = New-Object 'Collections.Generic.List[string]'
        $stack = New-Object 'Collections.Generic.Stack[string]'
        $stack.Push($rootFull)
        while ($stack.Count -gt 0) {
            $directory = [IO.Path]::GetFullPath($stack.Pop())
            if (-not [IO.Directory]::Exists($directory) -or
                -not (Test-CddsiFastLanePathWithinRoot $directory $rootFull) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $directory)) {
                return $false
            }
            foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries(
                    $directory, '*', [IO.SearchOption]::TopDirectoryOnly)) {
                $entryFull = [IO.Path]::GetFullPath($entry)
                if (-not (Test-CddsiFastLanePathWithinRoot $entryFull $rootFull) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $entryFull)) {
                    return $false
                }
                $relative = $entryFull.Substring($rootFull.Length + 1).Replace('\', '/')
                if ([IO.Directory]::Exists($entryFull)) {
                    $actualDirectoryNames.Add($relative)
                    $stack.Push($entryFull)
                }
                elseif ([IO.File]::Exists($entryFull)) { $actualFileNames.Add($relative) }
                else { return $false }
            }
        }
        if ((@($expectedFileNames | Sort-Object) -join "`n") -cne
                (@($actualFileNames | Sort-Object) -join "`n") -or
            (@($expectedDirectoryNames | Sort-Object) -join "`n") -cne
                (@($actualDirectoryNames | Sort-Object) -join "`n")) {
            return $false
        }
        foreach ($item in $expected) {
            $destination = [IO.Path]::GetFullPath(
                (Join-Path $rootFull $item.Path.Replace('/', '\')))
            if (-not (Test-CddsiFastLanePathWithinRoot -Path $destination -Root $rootFull) -or
                -not [IO.File]::Exists($destination) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $destination) -or
                [IO.FileInfo]::new($destination).Length -ne [long]$item.LengthBytes -or
                (Get-CddsiFastLaneGitFileSha256 $destination) -cne [string]$item.Sha256) {
                return $false
            }
        }
        return $true
    }
    catch { return $false }
}

function Expand-CddsiFastLaneVmBootstrapPackage {
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][string]$StagingRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$CredentialRoot
    )

    throw 'VM_BOOTSTRAP_MUTATION_HELPER_DIRECT_INVOCATION_FORBIDDEN'
}

function ConvertTo-CddsiFastLaneVmBootstrapPublicPackage {
    param([Parameter(Mandatory = $true)]$Package)

    $copy = [ordered]@{}
    foreach ($property in $Package.PSObject.Properties) {
        if ($property.Name -cne 'InternalBoundZipBytes' -and $property.Name -cne 'InventoryEntries') {
            $copy[$property.Name] = $property.Value
        }
    }
    return [pscustomobject]$copy
}

function Resolve-CddsiFastLaneVmBootstrapBlockerCode {
    param([AllowNull()][string]$Message)

    if ($Message -match 'CLEANUP') { return 'OWNED_CLEANUP_FAILED' }
    if ($Message -match 'ZIP_|MANIFEST_|INVENTORY_|CONTENT_BINDING|PACKAGE_ENTRY') { return 'PACKAGE_BINDING_INVALID' }
    if ($Message -match 'TOOL|KEYGEN') { return 'PINNED_TOOL_OR_KEYPAIR_INVALID' }
    if ($Message -match 'ACL|SID') { return 'CREDENTIAL_ACL_INVALID' }
    if ($Message -match 'STAGING|ROOT|REPARSE|OUTSIDE') { return 'OWNER_ROOT_INVALID' }
    if ($Message -match 'ACK_REQUIRED') { return 'LIVE_ACK_REQUIRED' }
    if ($Message -match 'AUTOMATION') { return 'AUTOMATION_CONTRACT_INVALID' }
    return 'INTERNAL_VALIDATION_FAILED'
}

function Get-CddsiFastLaneVmBootstrapFixedRoots {
    param(
        [Parameter(Mandatory = $true)][string]$LocalApplicationDataRoot,
        [Parameter(Mandatory = $true)][string]$ZipSha256,
        [Parameter(Mandatory = $true)][string]$ProductCommitSha
    )

    if (-not [IO.Path]::IsPathRooted($LocalApplicationDataRoot) -or
        $ZipSha256 -cnotmatch '^[a-f0-9]{64}$' -or $ProductCommitSha -cnotmatch '^[a-f0-9]{40}$') {
        throw 'VM_BOOTSTRAP_FIXED_ROOT_INPUT_INVALID'
    }
    $deviceRoot = [IO.Path]::GetFullPath((Join-Path $LocalApplicationDataRoot 'CDDsi\FastLane')).TrimEnd('\', '/')
    $packageStagingRoot = Join-Path (Join-Path $deviceRoot 'packages') `
        ('cddsi-vm-package-' + $ZipSha256.Substring(0, 32))
    return [pscustomobject][ordered]@{
        DeviceRoot = $deviceRoot
        PackageStagingRoot = [IO.Path]::GetFullPath($packageStagingRoot)
        CredentialRoot = [IO.Path]::GetFullPath((Join-Path (Join-Path $deviceRoot 'credentials') `
            ('cddsi-vm-bootstrap-' + $ProductCommitSha.Substring(0, 32))))
        ProductRoot = [IO.Path]::GetFullPath((Join-Path $packageStagingRoot 'payload'))
    }
}

function New-CddsiFastLaneVmBootstrapOnboardingFailureResult {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode,
        [Parameter(Mandatory = $true)][Exception]$FailureException,
        [AllowNull()]$Staging
    )

    throw 'VM_BOOTSTRAP_FAILURE_HANDLER_DIRECT_INVOCATION_FORBIDDEN'
}

function Invoke-CddsiFastLaneVmBootstrapOnboarding {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [Parameter(Mandatory = $true)]$BootstrapExecutionContext,
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$ExpectedZipSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedZipLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedManifestLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedInventorySha256,
        [Parameter(Mandatory = $true)][long]$ExpectedInventoryLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedInventoryBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedBundleContentDigestSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProductCommitSha,
        [Parameter(Mandatory = $true)][string]$ExpectedProductTreeSha,
        [Parameter(Mandatory = $true)][string]$ProgramFilesRoot,
        [Parameter(Mandatory = $true)][string]$SystemRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$PackageStagingRoot,
        [Parameter(Mandatory = $true)][string]$CredentialRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedAutomationTargetCurrentTaskToken,
        [switch]$AcknowledgeVmBootstrapLive
    )

    throw 'VM_BOOTSTRAP_PHASE1_DIRECT_INVOCATION_FORBIDDEN'
}

function Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [Parameter(Mandatory = $true)]$BootstrapExecutionContext,
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$ExpectedZipSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedZipLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedManifestLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedInventorySha256,
        [Parameter(Mandatory = $true)][long]$ExpectedInventoryLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedInventoryBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedBundleContentDigestSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProductCommitSha,
        [Parameter(Mandatory = $true)][string]$ExpectedProductTreeSha,
        [Parameter(Mandatory = $true)][string]$ProgramFilesRoot,
        [Parameter(Mandatory = $true)][string]$SystemRoot,
        [Parameter(Mandatory = $true)][string]$LocalApplicationDataRoot,
        [Parameter(Mandatory = $true)][string]$CodexHome,
        [Parameter(Mandatory = $true)][string]$ExpectedAutomationTargetCurrentTaskToken,
        [switch]$AcknowledgeVmBootstrapLive
    )

    function Test-CddsiFastLaneVmBootstrapExecutionContext {
        param(
            [Parameter(Mandatory = $true)]$Context,
            [Parameter(Mandatory = $true)][object[]]$BoundPaths,
            [object[]]$ProspectiveBoundPaths = @()
        )

        $contextProperties = @(
            'SchemaVersion', 'ContractVersion', 'Kind', 'SyntheticOnly', 'MutationAllowed',
            'SandboxRoot', 'SandboxRootBindingToken'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Context -Expected $contextProperties) -or
            $Context.SchemaVersion -ne 1 -or
            $Context.ContractVersion -cne 'cddsi-fast-lane-vm-bootstrap-execution-context-v1' -or
            @('VmDevice', 'HostSandboxFake') -cnotcontains $Context.Kind -or
            $Context.SyntheticOnly -isnot [bool] -or $Context.MutationAllowed -isnot [bool] -or
            $Context.SandboxRoot -isnot [string] -or
            $Context.SandboxRootBindingToken -isnot [string]) {
            return $false
        }
        if ($Context.Kind -ceq 'VmDevice') {
            return (
                -not $Context.SyntheticOnly -and $Context.MutationAllowed -and
                [string]::IsNullOrEmpty($Context.SandboxRoot) -and
                $Context.SandboxRootBindingToken -ceq ('0' * 64)
            )
        }
        if (-not $Context.SyntheticOnly -or $Context.MutationAllowed -or
            -not [IO.Path]::IsPathRooted($Context.SandboxRoot)) {
            return $false
        }
        try {
            $sandboxRoot = [IO.Path]::GetFullPath($Context.SandboxRoot).TrimEnd('\', '/')
            $temporaryRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\', '/')
            if ([IO.Path]::GetFileName($sandboxRoot) -cnotmatch '^cddsi-test-[a-f0-9]{32}$' -or
                (Get-CddsiFastLaneCanonicalPathSha256 ([IO.Path]::GetDirectoryName($sandboxRoot))) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $temporaryRoot) -or
                $Context.SandboxRootBindingToken -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $sandboxRoot) -or
                -not [IO.Directory]::Exists($sandboxRoot) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $sandboxRoot)) {
                return $false
            }
            $ownerPath = Join-Path $sandboxRoot '.cddsi-owner.json'
            if (-not [IO.File]::Exists($ownerPath) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $ownerPath)) {
                return $false
            }
            $owner = Read-CddsiFastLaneCanonicalFile -Path $ownerPath -MaximumBytes 16384
            if (-not (Test-CddsiExactPropertySet -InputObject $owner -Expected @(
                        'SchemaVersion','ContractVersion','Owner','SyntheticOnly'
                    )) -or $owner.SchemaVersion -ne 1 -or
                $owner.ContractVersion -cne 'cddsi-fast-lane-local-transport-owner-v1' -or
                $owner.Owner -isnot [string] -or [string]::IsNullOrWhiteSpace($owner.Owner) -or
                $owner.SyntheticOnly -isnot [bool] -or -not $owner.SyntheticOnly) {
                return $false
            }
            foreach ($boundPath in $BoundPaths) {
                if ($boundPath -isnot [string] -or -not [IO.Path]::IsPathRooted($boundPath) -or
                    -not (Test-CddsiFastLanePathWithinRoot $boundPath $sandboxRoot) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $boundPath)) {
                    return $false
                }
            }
            foreach ($boundPath in $ProspectiveBoundPaths) {
                if ($boundPath -isnot [string] -or -not [IO.Path]::IsPathRooted($boundPath) -or
                    -not (Test-CddsiFastLanePathWithinRoot $boundPath $sandboxRoot)) {
                    return $false
                }
                $boundFull = [IO.Path]::GetFullPath($boundPath).TrimEnd('\', '/')
                $existingAncestor = $boundFull
                while (-not [IO.File]::Exists($existingAncestor) -and
                    -not [IO.Directory]::Exists($existingAncestor)) {
                    $parent = [IO.Path]::GetDirectoryName($existingAncestor)
                    if ([string]::IsNullOrEmpty($parent) -or $parent -ceq $existingAncestor) {
                        return $false
                    }
                    $existingAncestor = $parent.TrimEnd('\', '/')
                }
                if (([IO.File]::Exists($existingAncestor) -and
                        -not $existingAncestor.Equals($boundFull, [StringComparison]::OrdinalIgnoreCase)) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $existingAncestor)) {
                    return $false
                }
            }
            return $true
        }
        catch { return $false }
    }

function Invoke-CddsiFastLaneVmBootstrapOnboardingClosure {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [Parameter(Mandatory = $true)]$BootstrapExecutionContext,
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$ExpectedZipSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedZipLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedManifestLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedManifestBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedInventorySha256,
        [Parameter(Mandatory = $true)][long]$ExpectedInventoryLengthBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedInventoryBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedBundleContentDigestSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProductCommitSha,
        [Parameter(Mandatory = $true)][string]$ExpectedProductTreeSha,
        [Parameter(Mandatory = $true)][string]$ProgramFilesRoot,
        [Parameter(Mandatory = $true)][string]$SystemRoot,
        [Parameter(Mandatory = $true)][string]$ProductRoot,
        [Parameter(Mandatory = $true)][string]$PackageStagingRoot,
        [Parameter(Mandatory = $true)][string]$CredentialRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedAutomationTargetCurrentTaskToken,
        [switch]$AcknowledgeVmBootstrapLive,
        [Parameter(Mandatory = $true)][ref]$InternalStagingOwnership,
        [Parameter(Mandatory = $true)][ref]$InternalCredentialOwnership,
        [AllowNull()]$InternalCompensationContext
    )

    $InternalStagingOwnership.Value = $null
    $InternalCredentialOwnership.Value = $null

    function New-CddsiFastLaneVmBootstrapDirectoryCreateOnly {
        param([Parameter(Mandatory = $true)][string]$Path)

        Initialize-CddsiFastLaneBoundedProcessType
        return [Cddsi.FastLane.BoundedProcessRunner]::TryCreateDirectory(
            [IO.Path]::GetFullPath($Path))
    }

    function Set-CddsiFastLaneVmBootstrapProtectedAcl {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [ValidateSet('Directory', 'File')][string]$PathKind = 'Directory',
            [AllowNull()][ref]$MutationCount
        )

        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($null -eq $currentSid) { throw 'VM_BOOTSTRAP_CURRENT_SID_UNAVAILABLE' }
        $systemSid = New-Object Security.Principal.SecurityIdentifier('S-1-5-18')
        $sections = [Security.AccessControl.AccessControlSections]::Access -bor
            [Security.AccessControl.AccessControlSections]::Owner
        $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
        $security = if ($null -ne $aclExtensions -and $PathKind -ceq 'Directory') {
            [IO.FileSystemAclExtensions]::GetAccessControl([IO.DirectoryInfo]::new($Path), $sections)
        }
        elseif ($null -ne $aclExtensions) {
            [IO.FileSystemAclExtensions]::GetAccessControl([IO.FileInfo]::new($Path), $sections)
        }
        elseif ($PathKind -ceq 'Directory') {
            [IO.DirectoryInfo]::new($Path).GetAccessControl($sections)
        }
        else { [IO.FileInfo]::new($Path).GetAccessControl($sections) }
        $security.SetAccessRuleProtection($true, $false)
        foreach ($existingRule in @($security.GetAccessRules(
            $true, $false, [Security.Principal.SecurityIdentifier]))) {
            $security.RemoveAccessRuleSpecific($existingRule)
        }
        if ($security.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $currentSid.Value) {
            $security.SetOwner($currentSid)
        }
        $inheritance = if ($PathKind -ceq 'Directory') {
            [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor
                [Security.AccessControl.InheritanceFlags]::ObjectInherit
        } else { [Security.AccessControl.InheritanceFlags]::None }
        $sidValues = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($sid in @($currentSid, $systemSid)) {
            if (-not $sidValues.Add($sid.Value)) { continue }
            $rule = New-Object Security.AccessControl.FileSystemAccessRule(
                $sid, [Security.AccessControl.FileSystemRights]::FullControl, $inheritance,
                [Security.AccessControl.PropagationFlags]::None, [Security.AccessControl.AccessControlType]::Allow)
            [void]$security.AddAccessRule($rule)
        }
        if ($null -ne $aclExtensions) {
            if ($PathKind -ceq 'Directory') {
                [IO.FileSystemAclExtensions]::SetAccessControl([IO.DirectoryInfo]::new($Path), $security)
            }
            else { [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($Path), $security) }
        }
        elseif ($PathKind -ceq 'Directory') { [IO.DirectoryInfo]::new($Path).SetAccessControl($security) }
        else { [IO.FileInfo]::new($Path).SetAccessControl($security) }
        if ($null -ne $MutationCount) {
            $MutationCount.Value = [int]$MutationCount.Value + 1
        }
        if (-not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $Path -PathKind $PathKind)) {
            throw 'VM_BOOTSTRAP_ACL_VERIFICATION_FAILED'
        }
    }

    function Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
        param(
            [Parameter(Mandatory = $true)][string]$Executable,
            [Parameter(Mandatory = $true)][string]$PrivateKeyPath,
            [Parameter(Mandatory = $true)][string]$ProfileId,
            [ValidateSet('Generate', 'DerivePublic')][string]$Operation = 'Generate'
        )

        Initialize-CddsiFastLaneBoundedProcessType
        $arguments = if ($Operation -ceq 'Generate') {
            @('-q', '-o', '-t', 'ed25519', '-a', '64', '-N', '', '-C', ('cddsi:' + $ProfileId), '-f', $PrivateKeyPath)
        } else { @('-y', '-f', $PrivateKeyPath) }
        $argumentText = (@($arguments | ForEach-Object {
            ConvertTo-CddsiFastLaneGitQuotedArgument $_
        }) -join ' ')
        $environment = @{
            SystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
            WINDIR = [Environment]::GetEnvironmentVariable('WINDIR', 'Machine')
            TEMP = [IO.Path]::GetDirectoryName($PrivateKeyPath)
            TMP = [IO.Path]::GetDirectoryName($PrivateKeyPath)
            HOME = [IO.Path]::GetDirectoryName($PrivateKeyPath)
            USERPROFILE = [IO.Path]::GetDirectoryName($PrivateKeyPath)
        }
        return [Cddsi.FastLane.BoundedProcessRunner]::Run(
            $Executable, $argumentText, [IO.Path]::GetDirectoryName($PrivateKeyPath),
            $environment, $null, 30000, 4096)
    }

    function Remove-CddsiFastLaneVmBootstrapOwnedTreeSafely {
        param([Parameter(Mandatory = $true)][string]$Root)

        $rootFull = [IO.Path]::GetFullPath($Root).TrimEnd('\', '/')
        if (-not [IO.Directory]::Exists($rootFull) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $rootFull)) {
            throw 'VM_BOOTSTRAP_CLEANUP_ROOT_INVALID'
        }
        $stack = New-Object 'Collections.Generic.Stack[string]'
        $directories = New-Object 'Collections.Generic.List[string]'
        $files = New-Object 'Collections.Generic.List[string]'
        $stack.Push($rootFull)
        while ($stack.Count -gt 0) {
            $directory = [IO.Path]::GetFullPath($stack.Pop())
            if (-not (Test-CddsiFastLanePathWithinRoot $directory $rootFull) -or
                -not [IO.Directory]::Exists($directory) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $directory)) {
                throw 'VM_BOOTSTRAP_CLEANUP_DESCENDANT_INVALID'
            }
            $directories.Add($directory)
            foreach ($entry in [IO.Directory]::EnumerateFileSystemEntries(
                    $directory, '*', [IO.SearchOption]::TopDirectoryOnly)) {
                $entryFull = [IO.Path]::GetFullPath($entry)
                if (-not (Test-CddsiFastLanePathWithinRoot $entryFull $rootFull) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $entryFull)) {
                    throw 'VM_BOOTSTRAP_CLEANUP_DESCENDANT_INVALID'
                }
                if ([IO.Directory]::Exists($entryFull)) { $stack.Push($entryFull) }
                elseif ([IO.File]::Exists($entryFull)) { $files.Add($entryFull) }
                else { throw 'VM_BOOTSTRAP_CLEANUP_DESCENDANT_INVALID' }
            }
        }
        foreach ($file in $files) {
            if (-not [IO.File]::Exists($file) -or
                -not (Test-CddsiFastLanePathWithinRoot $file $rootFull) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $file)) {
                throw 'VM_BOOTSTRAP_CLEANUP_DESCENDANT_CHANGED'
            }
            [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
            [IO.File]::Delete($file)
        }
        foreach ($directory in @($directories | Sort-Object { $_.Length } -Descending)) {
            if (-not [IO.Directory]::Exists($directory) -or
                -not (Test-CddsiFastLanePathWithinRoot $directory $rootFull) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $directory)) {
                throw 'VM_BOOTSTRAP_CLEANUP_DESCENDANT_CHANGED'
            }
            [IO.Directory]::Delete($directory, $false)
        }
    }

    function Remove-CddsiFastLaneVmBootstrapOwnedRoot {
        param(
            [Parameter(Mandatory = $true)][string]$CredentialRoot,
            [Parameter(Mandatory = $true)][string]$RunId,
            [Parameter(Mandatory = $true)][string]$ExpectedMarkerBindingToken
        )

        if (-not [IO.Directory]::Exists($CredentialRoot)) { return }
        $markerPath = Join-Path $CredentialRoot '.cddsi-owner.json'
        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $CredentialRoot) -or
            -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $CredentialRoot -PathKind Directory) -or
            -not [IO.File]::Exists($markerPath) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
            throw 'VM_BOOTSTRAP_CLEANUP_OWNER_MISSING'
        }
        $marker = Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 16384
        $markerProperties = @(
            'SchemaVersion','ContractVersion','Owner','OperatorPlaneOnly','RunId',
            'CredentialRootBindingToken','Stage','ProductCommitSha','ProductTreeSha',
            'ZipSha256','ZipLengthBytes','ManifestSha256','ManifestLengthBytes',
            'ManifestBindingToken','InventorySha256','InventoryLengthBytes',
            'InventoryBindingToken','BundleContentDigestSha256','SshKeygenSha256',
            'CredentialStatus','VmCredentialReady','ProfileReceipts'
        )
        $ready = $marker.Stage -ceq 'Ready' -and
            $marker.CredentialStatus -ceq 'KEYPAIR_STAGED' -and
            @($marker.ProfileReceipts).Count -eq 3
        $provisioning = $marker.Stage -ceq 'Provisioning' -and
            $marker.CredentialStatus -ceq 'UNPROVISIONED' -and
            @($marker.ProfileReceipts).Count -eq 0
        if (-not (Test-CddsiExactPropertySet -InputObject $marker -Expected $markerProperties) -or
            $ExpectedMarkerBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            (Get-CddsiFastLaneVmBootstrapBindingToken $marker) -cne $ExpectedMarkerBindingToken -or
            $marker.SchemaVersion -ne 1 -or
            $marker.ContractVersion -cne $script:CddsiFastLaneVmBootstrapOwnerContract -or
            $marker.Owner -cne 'CDDsiFastLaneVmBootstrap' -or $marker.OperatorPlaneOnly -ne $true -or
            -not (Test-CddsiFastLaneVmBootstrapGuidD $marker.RunId) -or $marker.RunId -cne $RunId -or
            $marker.CredentialRootBindingToken -cne
                (Get-CddsiFastLaneCanonicalPathSha256 $CredentialRoot) -or
            $marker.VmCredentialReady -ne $false -or (-not $ready -and -not $provisioning)) {
            throw 'VM_BOOTSTRAP_CLEANUP_OWNER_MISMATCH'
        }
        Remove-CddsiFastLaneVmBootstrapOwnedTreeSafely -Root $CredentialRoot
    }

    function Remove-CddsiFastLaneVmBootstrapOwnedPackageRoot {
        param(
            [Parameter(Mandatory = $true)][string]$StagingRoot,
            [Parameter(Mandatory = $true)][string]$RunId,
            [Parameter(Mandatory = $true)][string]$ExpectedMarkerBindingToken
        )

        if (-not [IO.Directory]::Exists($StagingRoot)) { return }
        $markerPath = Join-Path $StagingRoot '.cddsi-owner.json'
        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $StagingRoot) -or
            -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $StagingRoot -PathKind Directory) -or
            -not [IO.File]::Exists($markerPath) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
            throw 'VM_BOOTSTRAP_PACKAGE_CLEANUP_OWNER_MISSING'
        }
        $marker = Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768
        $markerProperties = @(
            'SchemaVersion','ContractVersion','Owner','OperatorPlaneOnly','RunId','Stage',
            'StagingRootBindingToken','ZipSha256','ZipLengthBytes','ManifestSha256',
            'ManifestLengthBytes','ManifestBindingToken','InventorySha256','InventoryLengthBytes',
            'InventoryBindingToken','BundleContentDigestSha256','ProductCommitSha','ProductTreeSha'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $marker -Expected $markerProperties) -or
            $ExpectedMarkerBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            (Get-CddsiFastLaneVmBootstrapBindingToken $marker) -cne $ExpectedMarkerBindingToken -or
            $marker.SchemaVersion -ne 1 -or
            $marker.ContractVersion -cne $script:CddsiFastLaneVmPackageStagingOwnerContract -or
            $marker.Owner -cne 'CDDsiFastLaneVmPackageStaging' -or
            $marker.OperatorPlaneOnly -ne $true -or
            -not (Test-CddsiFastLaneVmBootstrapGuidD $marker.RunId) -or $marker.RunId -cne $RunId -or
            @('Extracting','Extracted') -cnotcontains $marker.Stage -or
            $marker.StagingRootBindingToken -cne
                (Get-CddsiFastLaneCanonicalPathSha256 $StagingRoot)) {
            throw 'VM_BOOTSTRAP_PACKAGE_CLEANUP_OWNER_MISMATCH'
        }
        Remove-CddsiFastLaneVmBootstrapOwnedTreeSafely -Root $StagingRoot
    }

    function Expand-CddsiFastLaneVmBootstrapPackage {
        param(
            [Parameter(Mandatory = $true)]$Package,
            [Parameter(Mandatory = $true)][string]$StagingRoot,
            [Parameter(Mandatory = $true)][string]$ProductRoot,
            [Parameter(Mandatory = $true)][string]$CredentialRoot
        )

        if ($Package.InternalBoundZipBytes -isnot [byte[]] -or
            $Package.InternalBoundZipBytes.LongLength -ne $Package.ZipLengthBytes -or
            -not [IO.Path]::IsPathRooted($StagingRoot)) {
            throw 'VM_BOOTSTRAP_PACKAGE_STAGING_INPUT_INVALID'
        }
        $stagingFull = [IO.Path]::GetFullPath($StagingRoot).TrimEnd('\', '/')
        $expectedProductRoot = [IO.Path]::GetFullPath((Join-Path $stagingFull 'payload')).TrimEnd('\', '/')
        if ([IO.Path]::GetFileName($stagingFull) -cnotmatch '^cddsi-vm-package-[a-f0-9]{32}$' -or
            (Get-CddsiFastLaneCanonicalPathSha256 $ProductRoot) -cne
                (Get-CddsiFastLaneCanonicalPathSha256 $expectedProductRoot) -or
            (Test-CddsiFastLanePathWithinRoot $stagingFull $CredentialRoot) -or
            (Test-CddsiFastLanePathWithinRoot $CredentialRoot $stagingFull)) {
            throw 'VM_BOOTSTRAP_PACKAGE_STAGING_ROOT_FORBIDDEN'
        }
        $binding = Get-CddsiFastLaneCanonicalPathSha256 $stagingFull
        $parent = [IO.Path]::GetDirectoryName($stagingFull)
        if (-not (Test-CddsiFastLaneVmBootstrapOwnedParentChain `
                -LeafParent $parent -LeafRole PackageParent)) {
            throw 'VM_BOOTSTRAP_PACKAGE_STAGING_PARENT_INVALID'
        }
        $getExistingStaging = {
            $markerPath = Join-Path $stagingFull '.cddsi-owner.json'
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $stagingFull) -or
                -not (Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $stagingFull -PathKind Directory) -or
                -not [IO.File]::Exists($markerPath) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
                throw 'VM_BOOTSTRAP_PACKAGE_STAGING_OWNER_INVALID'
            }
            $marker = Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768
            if (-not (Test-CddsiFastLaneVmBootstrapPackageMarker -Marker $marker -Package $Package `
                -StagingRootBindingToken $binding -ExpectedStage Extracted) -or
                -not (Test-CddsiFastLaneVmBootstrapStagedPackage -StagingRoot $stagingFull -Package $Package)) {
                throw 'VM_BOOTSTRAP_PACKAGE_STAGING_REUSE_INVALID'
            }
            return [pscustomobject]@{
                Status = 'EXTRACTED'; Changed = $false; ReusedExisting = $true; RootBindingToken = $binding
                OwnerRunId = [string]$marker.RunId; DirectoryCreateCount = 0
                OwnerMarkerBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $marker
                FileWriteCount = 0; AclMutationCount = 0
            }
        }
        if ([IO.Directory]::Exists($stagingFull)) { return (& $getExistingStaging) }
        if ([IO.File]::Exists($stagingFull)) { throw 'VM_BOOTSTRAP_PACKAGE_STAGING_ROOT_FORBIDDEN' }
        $runId = [guid]::NewGuid().ToString('D')
        $created = $false; $ownerWritten = $false; $directoryCreateCount = 0
        $fileWriteCount = 0; $aclMutationCount = 0; $ownerMarkerBindingToken = $null
        try {
            if (-not (New-CddsiFastLaneVmBootstrapDirectoryCreateOnly -Path $stagingFull)) {
                if ([IO.Directory]::Exists($stagingFull)) { return (& $getExistingStaging) }
                throw 'VM_BOOTSTRAP_PACKAGE_STAGING_CREATION_COLLISION'
            }
            $created = $true; $directoryCreateCount++
            Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $stagingFull -PathKind Directory `
                -MutationCount ([ref]$aclMutationCount)
            $markerPath = Join-Path $stagingFull '.cddsi-owner.json'
            $marker = Get-CddsiFastLaneVmBootstrapPackageMarker -Package $Package -RunId $runId `
                -Stage Extracting -StagingRootBindingToken $binding
            $ownerMarkerBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $marker
            Write-CddsiFastLaneCanonicalFile -Path $markerPath -Value $marker -CreateOnly
            $ownerWritten = $true; $fileWriteCount++
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
                throw 'VM_BOOTSTRAP_PACKAGE_STAGING_OWNER_INVALID'
            }
            $memory = New-Object IO.MemoryStream(, ([byte[]]$Package.InternalBoundZipBytes))
            $archive = New-Object IO.Compression.ZipArchive(
                $memory, [IO.Compression.ZipArchiveMode]::Read, $false)
            try {
                foreach ($item in @(Get-CddsiFastLaneVmBootstrapExpectedStagedFiles $Package)) {
                    if (-not (Test-CddsiFastLaneVmBootstrapSafeRelativePath $item.Path)) {
                        throw 'VM_BOOTSTRAP_PACKAGE_ENTRY_PATH_INVALID'
                    }
                    $destination = [IO.Path]::GetFullPath((Join-Path $stagingFull $item.Path.Replace('/', '\')))
                    if (-not (Test-CddsiFastLanePathWithinRoot -Path $destination -Root $stagingFull)) {
                        throw 'VM_BOOTSTRAP_PACKAGE_ENTRY_OUTSIDE_ROOT'
                    }
                    $segments = @($item.Path -split '/')
                    $destinationParent = $stagingFull
                    for ($segmentIndex = 0; $segmentIndex -lt ($segments.Count - 1); $segmentIndex++) {
                        $destinationParent = [IO.Path]::GetFullPath((Join-Path $destinationParent $segments[$segmentIndex]))
                        if (-not (Test-CddsiFastLanePathWithinRoot -Path $destinationParent -Root $stagingFull) -or
                            [IO.File]::Exists($destinationParent)) {
                            throw 'VM_BOOTSTRAP_PACKAGE_ENTRY_OUTSIDE_ROOT'
                        }
                        if (-not [IO.Directory]::Exists($destinationParent)) {
                            [void][IO.Directory]::CreateDirectory($destinationParent)
                            $directoryCreateCount++
                        }
                        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $destinationParent)) {
                            throw 'VM_BOOTSTRAP_PACKAGE_ENTRY_REPARSE_FORBIDDEN'
                        }
                    }
                    if (-not (Test-CddsiFastLanePathWithoutReparsePoint $destinationParent) -or
                        [IO.File]::Exists($destination)) {
                        throw 'VM_BOOTSTRAP_PACKAGE_ENTRY_REPARSE_FORBIDDEN'
                    }
                    $bytes = Get-CddsiFastLaneVmBootstrapZipEntryBytes -Archive $archive -Name $item.Path
                    if ($bytes.LongLength -ne [long]$item.LengthBytes -or
                        (Get-CddsiFastLaneVmBootstrapBytesSha256 $bytes) -cne [string]$item.Sha256) {
                        throw 'VM_BOOTSTRAP_PACKAGE_ENTRY_BINDING_MISMATCH'
                    }
                    $output = [IO.File]::Open(
                        $destination, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
                    try { $output.Write($bytes, 0, $bytes.Length); $output.Flush($true) }
                    finally { $output.Dispose() }
                    $fileWriteCount++
                }
            }
            finally { $archive.Dispose(); $memory.Dispose() }
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath) -or
                (Get-CddsiFastLaneVmBootstrapBindingToken `
                    (Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768)) -cne
                        $ownerMarkerBindingToken) {
                throw 'VM_BOOTSTRAP_PACKAGE_STAGING_OWNER_CHANGED'
            }
            $marker.Stage = 'Extracted'
            $ownerMarkerBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $marker
            Write-CddsiFastLaneCanonicalFile -Path $markerPath -Value $marker
            $fileWriteCount++
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath) -or
                (Get-CddsiFastLaneVmBootstrapBindingToken `
                    (Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768)) -cne
                        $ownerMarkerBindingToken -or
                -not (Test-CddsiFastLaneVmBootstrapStagedPackage `
                -StagingRoot $stagingFull -Package $Package) -or
                -not (Test-CddsiFastLaneVmBootstrapProtectedAcl `
                    -Path $stagingFull -PathKind Directory)) {
                throw 'VM_BOOTSTRAP_PACKAGE_STAGING_FINAL_INVALID'
            }
            return [pscustomobject]@{
                Status = 'EXTRACTED'; Changed = $true; ReusedExisting = $false; RootBindingToken = $binding
                OwnerRunId = $runId; DirectoryCreateCount = $directoryCreateCount
                OwnerMarkerBindingToken = $ownerMarkerBindingToken
                FileWriteCount = $fileWriteCount; AclMutationCount = $aclMutationCount
            }
        }
        catch {
            $originalException = $_.Exception; $directoryDeleteCount = 0
            $cleanupRequired = $created; $cleanupSucceeded = -not $cleanupRequired
            if ($created) {
                try {
                    if ($ownerWritten) {
                        Remove-CddsiFastLaneVmBootstrapOwnedPackageRoot `
                            -StagingRoot $stagingFull -RunId $runId `
                            -ExpectedMarkerBindingToken $ownerMarkerBindingToken
                        $directoryDeleteCount++; $cleanupSucceeded = $true
                    }
                    else {
                        Remove-CddsiFastLaneVmBootstrapOwnedTreeSafely -Root $stagingFull
                        $directoryDeleteCount++; $cleanupSucceeded = $true
                    }
                }
                catch {
                    $cleanupFailure = New-Object InvalidOperationException('VM_BOOTSTRAP_PACKAGE_CLEANUP_FAILED')
                    Set-CddsiFastLaneVmBootstrapFailureAccounting -Exception $cleanupFailure `
                        -DirectoryCreateCount $directoryCreateCount -FileWriteCount $fileWriteCount `
                        -AclMutationCount $aclMutationCount -ProcessInvocationCount 0 `
                        -DirectoryDeleteCount $directoryDeleteCount `
                        -CleanupRequired $cleanupRequired -CleanupSucceeded $false
                    throw $cleanupFailure
                }
            }
            Set-CddsiFastLaneVmBootstrapFailureAccounting -Exception $originalException `
                -DirectoryCreateCount $directoryCreateCount -FileWriteCount $fileWriteCount `
                -AclMutationCount $aclMutationCount -ProcessInvocationCount 0 `
                -DirectoryDeleteCount $directoryDeleteCount `
                -CleanupRequired $cleanupRequired -CleanupSucceeded $cleanupSucceeded
            throw $originalException
        }
    }

    function New-CddsiFastLaneVmBootstrapOnboardingFailureResult {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode,
            [Parameter(Mandatory = $true)][Exception]$FailureException,
            [AllowNull()]$Staging,
            [AllowNull()]$Bootstrap,
            [AllowNull()]$CredentialOwnership
        )

        $accounting = Get-CddsiFastLaneVmBootstrapFailureAccounting -Exception $FailureException
        $directoryCreateCount = [int]$accounting.DirectoryCreateCount
        $fileWriteCount = [int]$accounting.FileWriteCount
        $aclMutationCount = [int]$accounting.AclMutationCount
        $processInvocationCount = [int]$accounting.ProcessInvocationCount
        $directoryDeleteCount = [int]$accounting.DirectoryDeleteCount
        $cleanupRequired = [bool]$accounting.CleanupRequired
        $cleanupSucceeded = [bool]$accounting.CleanupSucceeded
        $blockerMessage = $FailureException.Message
        if ($null -ne $Bootstrap) {
            $directoryCreateCount += [int]$Bootstrap.DirectoryCreateCount
            $fileWriteCount += [int]$Bootstrap.FileWriteCount
            $aclMutationCount += [int]$Bootstrap.AclMutationCount
            $processInvocationCount += [int]$Bootstrap.ProcessInvocationCount
        }
        if ($Mode -ceq 'Live' -and $null -ne $CredentialOwnership -and
            $CredentialOwnership.Changed -eq $true) {
            $cleanupRequired = $true
            try {
                Remove-CddsiFastLaneVmBootstrapOwnedRoot `
                    -CredentialRoot $CredentialOwnership.CredentialRoot `
                    -RunId $CredentialOwnership.OwnerRunId `
                    -ExpectedMarkerBindingToken $CredentialOwnership.OwnerMarkerBindingToken
                $directoryDeleteCount++
            }
            catch {
                $cleanupSucceeded = $false
                $blockerMessage = 'VM_BOOTSTRAP_CREDENTIAL_CLEANUP_FAILED'
            }
        }
        if ($null -ne $Staging) {
            $directoryCreateCount += [int]$Staging.DirectoryCreateCount
            $fileWriteCount += [int]$Staging.FileWriteCount
            $aclMutationCount += [int]$Staging.AclMutationCount
            if ($Mode -ceq 'Live' -and $Staging.Changed -eq $true) {
                $cleanupRequired = $true
                try {
                    Remove-CddsiFastLaneVmBootstrapOwnedPackageRoot `
                        -StagingRoot $Staging.StagingRoot -RunId $Staging.OwnerRunId `
                        -ExpectedMarkerBindingToken $Staging.OwnerMarkerBindingToken
                    $directoryDeleteCount++
                }
                catch {
                    $cleanupSucceeded = $false
                    $blockerMessage = 'VM_BOOTSTRAP_PACKAGE_CLEANUP_FAILED'
                }
            }
        }
        if (-not $cleanupRequired) { $cleanupSucceeded = $true }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-onboarding-v1'
            Status = 'VM_BOOTSTRAP_BLOCKED'; Mode = $Mode
            BlockerCode = Resolve-CddsiFastLaneVmBootstrapBlockerCode $blockerMessage
            Changed = ($cleanupRequired -and -not $cleanupSucceeded)
            Package = $null; BootstrapResult = $null; AutomationPrompt = $null
            ExpectedAutomationContract = $null; PackageStagingRootBindingToken = $null
            DirectoryCreateCount = $directoryCreateCount; FileWriteCount = $fileWriteCount
            AclMutationCount = $aclMutationCount; ProcessInvocationCount = $processInvocationCount
            DirectoryDeleteCount = $directoryDeleteCount
            CleanupRequired = $cleanupRequired; CleanupSucceeded = $cleanupSucceeded
            NetworkRequestCount = 0; GitInvocationCount = 0
            ProductLiveInvocationCount = 0; ProductWriteCount = 0
            PrivateKeyIncluded = $false; RealPathIncluded = $false; SidIncluded = $false
        }
    }

    function Invoke-CddsiFastLaneVmBootstrapMutationClosure {
        param(
            [Parameter(Mandatory = $true)]$Package,
            [Parameter(Mandatory = $true)][string]$CredentialRoot,
            [Parameter(Mandatory = $true)][string]$ProductRoot,
            [Parameter(Mandatory = $true)][string]$SshKeygenExecutable,
            [Parameter(Mandatory = $true)][string]$ExpectedSshKeygenSha256,
            [Parameter(Mandatory = $true)][ref]$CreatedOwnership
        )

        $CreatedOwnership.Value = $null
        $plan = New-CddsiFastLaneVmBootstrapPlan -Package $Package -CredentialRoot $CredentialRoot `
            -ProductRoot $ProductRoot -Mode Live
        $keygen = @($Package.Tools | Where-Object { $_.ToolId -ceq 'OpenSSHKeygen' })
        if ($keygen.Count -ne 1 -or $ExpectedSshKeygenSha256 -cne $keygen[0].Sha256) {
            throw 'VM_BOOTSTRAP_KEYGEN_PACKAGE_BINDING_MISMATCH'
        }
        Assert-CddsiFastLanePinnedFile -Path $SshKeygenExecutable -Sha256 $ExpectedSshKeygenSha256 `
            -ErrorPrefix 'VM_BOOTSTRAP_KEYGEN'
        if ((Get-CddsiFastLaneCanonicalPathSha256 $SshKeygenExecutable) -cne $keygen[0].PathBindingToken) {
            throw 'VM_BOOTSTRAP_KEYGEN_PATH_BINDING_MISMATCH'
        }
        $credentialFull = [IO.Path]::GetFullPath($CredentialRoot)
        $parent = [IO.Path]::GetDirectoryName($credentialFull.TrimEnd('\', '/'))
        if (-not (Test-CddsiFastLaneVmBootstrapOwnedParentChain `
                -LeafParent $parent -LeafRole CredentialParent)) {
            throw 'VM_BOOTSTRAP_CREDENTIAL_PARENT_INVALID'
        }
        $getExistingCredential = {
            $existing = Get-CddsiFastLaneVmBootstrapExistingResult -CredentialRoot $credentialFull `
                -Package $Package -Plan $plan -ExpectedSshKeygenSha256 $ExpectedSshKeygenSha256 `
                -SshKeygenExecutable $SshKeygenExecutable
            Assert-CddsiFastLanePinnedFile -Path $SshKeygenExecutable -Sha256 $ExpectedSshKeygenSha256 `
                -ErrorPrefix 'VM_BOOTSTRAP_KEYGEN_POST'
            return $existing
        }
        if ([IO.File]::Exists($credentialFull)) { throw 'VM_BOOTSTRAP_CREDENTIAL_ROOT_ALREADY_EXISTS' }
        if ([IO.Directory]::Exists($credentialFull)) { return (& $getExistingCredential) }
        $runId = [guid]::NewGuid().ToString('D')
        $created = $false; $ownerWritten = $false
        $directoryCreateCount = 0; $fileWriteCount = 0; $aclMutationCount = 0
        $processInvocationCount = 0; $ownerMarkerBindingToken = $null
        try {
            if (-not (New-CddsiFastLaneVmBootstrapDirectoryCreateOnly -Path $credentialFull)) {
                if ([IO.Directory]::Exists($credentialFull)) { return (& $getExistingCredential) }
                throw 'VM_BOOTSTRAP_CREDENTIAL_CREATION_COLLISION'
            }
            $created = $true; $directoryCreateCount++
            Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $credentialFull `
                -MutationCount ([ref]$aclMutationCount)
            $marker = New-CddsiFastLaneVmBootstrapCredentialMarker `
                -Package $Package -Plan $plan -RunId $runId `
                -ExpectedSshKeygenSha256 $ExpectedSshKeygenSha256 -Stage Provisioning `
                -CredentialStatus UNPROVISIONED -ProfileReceipts @()
            $ownerMarkerBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $marker
            $markerPath = Join-Path $credentialFull '.cddsi-owner.json'
            Write-CddsiFastLaneCanonicalFile -Path $markerPath -Value $marker -CreateOnly
            $ownerWritten = $true; $fileWriteCount++
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
                throw 'VM_BOOTSTRAP_MARKER_REPARSE_FORBIDDEN'
            }
            Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $markerPath -PathKind File `
                -MutationCount ([ref]$aclMutationCount)
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
                throw 'VM_BOOTSTRAP_MARKER_REPARSE_FORBIDDEN'
            }
            $publicProfiles = @()
            foreach ($profileId in $script:CddsiFastLaneVmBootstrapProfiles) {
                $privatePath = Join-Path $credentialFull ($profileId + '.key')
                $publicPath = $privatePath + '.pub'
                $processInvocationCount++
                try {
                    $process = Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Executable $SshKeygenExecutable `
                        -PrivateKeyPath $privatePath -ProfileId $profileId -Operation Generate
                }
                finally {
                    if ([IO.File]::Exists($privatePath)) { $fileWriteCount++ }
                    if ([IO.File]::Exists($publicPath)) { $fileWriteCount++ }
                }
                if ($null -eq $process -or $process.ExitCode -ne 0 -or $process.TimedOut -or $process.Truncated -or
                    $process.JobAssigned -ne $true) { throw 'VM_BOOTSTRAP_KEYGEN_FAILED' }
                if (-not [IO.File]::Exists($privatePath) -or -not [IO.File]::Exists($publicPath) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $privatePath) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $publicPath) -or
                    [IO.FileInfo]::new($privatePath).Length -lt 32 -or
                    [IO.FileInfo]::new($publicPath).Length -lt 32) {
                    throw 'VM_BOOTSTRAP_KEYPAIR_MISSING'
                }
                Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $privatePath -PathKind File `
                    -MutationCount ([ref]$aclMutationCount)
                Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $publicPath -PathKind File `
                    -MutationCount ([ref]$aclMutationCount)
                if (-not (Test-CddsiFastLanePathWithoutReparsePoint $privatePath) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $publicPath)) {
                    throw 'VM_BOOTSTRAP_KEYPAIR_REPARSE_FORBIDDEN'
                }
                $publicKey = [IO.File]::ReadAllText(
                    $publicPath, (New-Object Text.UTF8Encoding($false, $true))).Trim()
                $processInvocationCount++
                $derive = Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Executable $SshKeygenExecutable `
                    -PrivateKeyPath $privatePath -ProfileId $profileId -Operation DerivePublic
                if ($null -eq $derive -or $derive.ExitCode -ne 0 -or $derive.TimedOut -or $derive.Truncated -or
                    $derive.JobAssigned -ne $true -or $derive.StandardOutput -isnot [string]) {
                    throw 'VM_BOOTSTRAP_KEYGEN_PUBLIC_DERIVATION_FAILED'
                }
                $publicParts = @($publicKey -split ' '); $derivedParts = @($derive.StandardOutput.Trim() -split ' ')
                if ($publicParts.Count -ne 3 -or $derivedParts.Count -ne 2 -or
                    $publicParts[0] -cne $derivedParts[0] -or $publicParts[1] -cne $derivedParts[1]) {
                    throw 'VM_BOOTSTRAP_KEYPAIR_MISMATCH'
                }
                $receipt = New-CddsiFastLaneVmBootstrapProfileReceipt -ProfileId $profileId `
                    -PublicKey $publicKey -PrivateKeyPath $privatePath -Package $Package
                $receiptPath = Join-Path $credentialFull ($profileId + '.receipt.json')
                Write-CddsiFastLaneCanonicalFile -Path $receiptPath -Value $receipt -CreateOnly
                $fileWriteCount++
                if (-not (Test-CddsiFastLanePathWithoutReparsePoint $receiptPath)) {
                    throw 'VM_BOOTSTRAP_RECEIPT_REPARSE_FORBIDDEN'
                }
                Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $receiptPath -PathKind File `
                    -MutationCount ([ref]$aclMutationCount)
                if (-not (Test-CddsiFastLanePathWithoutReparsePoint $receiptPath)) {
                    throw 'VM_BOOTSTRAP_RECEIPT_REPARSE_FORBIDDEN'
                }
                $receiptSha = Get-CddsiFastLaneGitFileSha256 $receiptPath
                $publicProfiles += [pscustomobject][ordered]@{
                    ProfileId = $profileId; Algorithm = 'ssh-ed25519'; PublicKey = $receipt.PublicKey
                    PublicKeySha256 = $receipt.PublicKeySha256; PublicKeyFingerprint = $receipt.PublicKeyFingerprint
                    State = 'KEYPAIR_STAGED'; RemoteAuthorizationStatus = 'UNPROVISIONED'; VmCredentialReady = $false
                    ReceiptBindingToken = $receipt.ReceiptBindingToken; ReceiptSha256 = $receiptSha
                }
            }
            [void](New-CddsiFastLaneVmBootstrapSafeResult -Package $Package -Plan $plan -Profiles $publicProfiles `
                -Changed $true -ReusedExisting $false -DirectoryCreateCount $directoryCreateCount `
                -FileWriteCount $fileWriteCount -AclMutationCount $aclMutationCount `
                -ProcessInvocationCount $processInvocationCount)
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath) -or
                (Get-CddsiFastLaneVmBootstrapBindingToken `
                    (Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768)) -cne
                        $ownerMarkerBindingToken) {
                throw 'VM_BOOTSTRAP_MARKER_CHANGED'
            }
            $readyProfileReceipts = @($publicProfiles | ForEach-Object {
                [pscustomobject][ordered]@{
                    ProfileId = $_.ProfileId; PublicKeyFingerprint = $_.PublicKeyFingerprint
                    ReceiptBindingToken = $_.ReceiptBindingToken; ReceiptSha256 = $_.ReceiptSha256
                }
            })
            $marker = New-CddsiFastLaneVmBootstrapCredentialMarker `
                -Package $Package -Plan $plan -RunId $runId `
                -ExpectedSshKeygenSha256 $ExpectedSshKeygenSha256 -Stage Ready `
                -CredentialStatus KEYPAIR_STAGED -ProfileReceipts $readyProfileReceipts
            $ownerMarkerBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $marker
            Write-CddsiFastLaneCanonicalFile -Path $markerPath -Value $marker
            $fileWriteCount++
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath)) {
                throw 'VM_BOOTSTRAP_MARKER_REPARSE_FORBIDDEN'
            }
            Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $markerPath -PathKind File `
                -MutationCount ([ref]$aclMutationCount)
            if (-not (Test-CddsiFastLanePathWithoutReparsePoint $markerPath) -or
                (Get-CddsiFastLaneVmBootstrapBindingToken `
                    (Read-CddsiFastLaneCanonicalFile -Path $markerPath -MaximumBytes 32768)) -cne
                        $ownerMarkerBindingToken -or
                -not (Test-CddsiFastLaneVmBootstrapCredentialRootExactFiles $credentialFull)) {
                throw 'VM_BOOTSTRAP_FINAL_FILE_SET_INVALID'
            }
            Assert-CddsiFastLanePinnedFile -Path $SshKeygenExecutable -Sha256 $ExpectedSshKeygenSha256 `
                -ErrorPrefix 'VM_BOOTSTRAP_KEYGEN_POST'
            $result = New-CddsiFastLaneVmBootstrapSafeResult `
                -Package $Package -Plan $plan -Profiles $publicProfiles `
                -Changed $true -ReusedExisting $false -DirectoryCreateCount $directoryCreateCount `
                -FileWriteCount $fileWriteCount -AclMutationCount $aclMutationCount `
                -ProcessInvocationCount $processInvocationCount
            $CreatedOwnership.Value = [pscustomobject][ordered]@{
                CredentialRoot = $credentialFull; OwnerRunId = $runId
                OwnerMarkerBindingToken = $ownerMarkerBindingToken; Changed = $true
            }
            return $result
        }
        catch {
            $originalException = $_.Exception; $directoryDeleteCount = 0
            $cleanupRequired = $created; $cleanupSucceeded = -not $cleanupRequired
            if ($created) {
                try {
                    if ($ownerWritten) {
                        Remove-CddsiFastLaneVmBootstrapOwnedRoot `
                            -CredentialRoot $credentialFull -RunId $runId `
                            -ExpectedMarkerBindingToken $ownerMarkerBindingToken
                        $directoryDeleteCount++; $cleanupSucceeded = $true
                    }
                    else {
                        Remove-CddsiFastLaneVmBootstrapOwnedTreeSafely -Root $credentialFull
                        $directoryDeleteCount++; $cleanupSucceeded = $true
                    }
                }
                catch {
                    $cleanupFailure = New-Object InvalidOperationException('VM_BOOTSTRAP_CLEANUP_FAILED')
                    Set-CddsiFastLaneVmBootstrapFailureAccounting -Exception $cleanupFailure `
                        -DirectoryCreateCount $directoryCreateCount -FileWriteCount $fileWriteCount `
                        -AclMutationCount $aclMutationCount -ProcessInvocationCount $processInvocationCount `
                        -DirectoryDeleteCount $directoryDeleteCount -CleanupRequired $cleanupRequired `
                        -CleanupSucceeded $false
                    throw $cleanupFailure
                }
            }
            Set-CddsiFastLaneVmBootstrapFailureAccounting -Exception $originalException `
                -DirectoryCreateCount $directoryCreateCount -FileWriteCount $fileWriteCount `
                -AclMutationCount $aclMutationCount -ProcessInvocationCount $processInvocationCount `
                -DirectoryDeleteCount $directoryDeleteCount -CleanupRequired $cleanupRequired `
                -CleanupSucceeded $cleanupSucceeded
            throw $originalException
        }
    }

    if ($null -ne $InternalCompensationContext) {
        if ($Mode -cne 'Live' -or
            -not (Test-CddsiExactPropertySet -InputObject $InternalCompensationContext -Expected @(
                    'FailureException','Staging','Bootstrap','CredentialOwnership'
                )) -or
            $InternalCompensationContext.FailureException -isnot [Exception]) {
            throw 'VM_BOOTSTRAP_INTERNAL_COMPENSATION_CONTEXT_INVALID'
        }
        return New-CddsiFastLaneVmBootstrapOnboardingFailureResult -Mode Live `
            -FailureException $InternalCompensationContext.FailureException `
            -Staging $InternalCompensationContext.Staging `
            -Bootstrap $InternalCompensationContext.Bootstrap `
            -CredentialOwnership $InternalCompensationContext.CredentialOwnership
    }

    $staging = $null; $bootstrap = $null; $credentialOwnership = $null
    try {
        if (-not (Test-CddsiFastLaneVmBootstrapExecutionContext `
                -Context $BootstrapExecutionContext -BoundPaths @(
                    $ZipPath, $ProgramFilesRoot, $SystemRoot
                ) -ProspectiveBoundPaths @(
                    $ProductRoot, $PackageStagingRoot, $CredentialRoot
                ))) {
            throw 'VM_BOOTSTRAP_EXECUTION_CONTEXT_INVALID'
        }
        if ($ExpectedAutomationTargetCurrentTaskToken -cne 'CURRENT_TASK') {
            throw 'VM_BOOTSTRAP_AUTOMATION_TARGET_INVALID'
        }
        if ($Mode -ceq 'Live') {
            if ($BootstrapExecutionContext.Kind -cne 'VmDevice' -or $BootstrapExecutionContext.SyntheticOnly -or
                -not $BootstrapExecutionContext.MutationAllowed -or -not $AcknowledgeVmBootstrapLive) {
                throw 'VM_BOOTSTRAP_LIVE_ACK_REQUIRED'
            }
            $actualProgramFiles = [Environment]::GetEnvironmentVariable('ProgramFiles', 'Machine')
            $actualSystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
            if ([string]::IsNullOrWhiteSpace($actualProgramFiles)) { $actualProgramFiles = $env:ProgramFiles }
            if ([string]::IsNullOrWhiteSpace($actualSystemRoot)) { $actualSystemRoot = $env:SystemRoot }
            if ((Get-CddsiFastLaneCanonicalPathSha256 $ProgramFilesRoot) -cne
                (Get-CddsiFastLaneCanonicalPathSha256 $actualProgramFiles) -or
                (Get-CddsiFastLaneCanonicalPathSha256 $SystemRoot) -cne
                (Get-CddsiFastLaneCanonicalPathSha256 $actualSystemRoot)) {
                throw 'VM_BOOTSTRAP_LIVE_SYSTEM_ROOT_MISMATCH'
            }
            $actualLocalApplicationData = [Environment]::GetFolderPath(
                [Environment+SpecialFolder]::LocalApplicationData)
            if ([string]::IsNullOrWhiteSpace($actualLocalApplicationData)) {
                throw 'VM_BOOTSTRAP_LIVE_DEVICE_ROOT_UNAVAILABLE'
            }
            $fixedRoots = Get-CddsiFastLaneVmBootstrapFixedRoots `
                -LocalApplicationDataRoot $actualLocalApplicationData -ZipSha256 $ExpectedZipSha256 `
                -ProductCommitSha $ExpectedProductCommitSha
            foreach ($rootPair in @(
                @($PackageStagingRoot, $fixedRoots.PackageStagingRoot),
                @($CredentialRoot, $fixedRoots.CredentialRoot),
                @($ProductRoot, $fixedRoots.ProductRoot)
            )) {
                if ((Get-CddsiFastLaneCanonicalPathSha256 $rootPair[0]) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $rootPair[1])) {
                    throw 'VM_BOOTSTRAP_LIVE_DEVICE_ROOT_MISMATCH'
                }
            }
        }
        elseif ($BootstrapExecutionContext.Kind -cne 'HostSandboxFake') {
            throw 'VM_BOOTSTRAP_EXECUTION_CONTEXT_INVALID'
        }
        if (-not [IO.Path]::IsPathRooted($ZipPath) -or -not [IO.File]::Exists($ZipPath) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $ZipPath)) {
            throw 'VM_BOOTSTRAP_ZIP_PATH_INVALID'
        }
        $boundBytes = [IO.File]::ReadAllBytes($ZipPath)
        $packageParameters = @{
            ZipPath = $ZipPath; ExpectedZipSha256 = $ExpectedZipSha256; ExpectedZipLengthBytes = $ExpectedZipLengthBytes
            ExpectedManifestSha256 = $ExpectedManifestSha256; ExpectedManifestLengthBytes = $ExpectedManifestLengthBytes
            ExpectedManifestBindingToken = $ExpectedManifestBindingToken; ExpectedInventorySha256 = $ExpectedInventorySha256
            ExpectedInventoryLengthBytes = $ExpectedInventoryLengthBytes; ExpectedInventoryBindingToken = $ExpectedInventoryBindingToken
            ExpectedBundleContentDigestSha256 = $ExpectedBundleContentDigestSha256
            ExpectedProductCommitSha = $ExpectedProductCommitSha; ExpectedProductTreeSha = $ExpectedProductTreeSha
            ProgramFilesRoot = $ProgramFilesRoot; SystemRoot = $SystemRoot; BoundZipBytes = $boundBytes
        }
        $package = Test-CddsiFastLaneVmOnboardingPackage @packageParameters
        if ($package.AutomationContract.TargetTaskToken -cne $ExpectedAutomationTargetCurrentTaskToken) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TARGET_INVALID'
        }
        $keygen = @($package.Tools | Where-Object ToolId -CEQ 'OpenSSHKeygen')
        if ($keygen.Count -ne 1) { throw 'VM_BOOTSTRAP_KEYGEN_PACKAGE_BINDING_MISMATCH' }
        $keygenPath = Join-Path $ProgramFilesRoot 'Git\usr\bin\ssh-keygen.exe'
        if ($Mode -ceq 'Live') {
            $staging = Expand-CddsiFastLaneVmBootstrapPackage -Package $package -StagingRoot $PackageStagingRoot `
                -ProductRoot $ProductRoot -CredentialRoot $CredentialRoot
            if (-not [IO.Directory]::Exists($ProductRoot) -or
                -not (Test-CddsiFastLanePathWithoutReparsePoint $ProductRoot)) {
                throw 'VM_BOOTSTRAP_PACKAGE_PAYLOAD_ROOT_INVALID'
            }
        }
        $bootstrap = if ($Mode -ceq 'Live') {
            Invoke-CddsiFastLaneVmBootstrapMutationClosure -Package $package `
                -CredentialRoot $CredentialRoot -ProductRoot $ProductRoot -SshKeygenExecutable $keygenPath `
                -ExpectedSshKeygenSha256 $keygen[0].Sha256 `
                -CreatedOwnership ([ref]$credentialOwnership)
        }
        else {
            $plan = New-CddsiFastLaneVmBootstrapPlan -Package $package `
                -CredentialRoot $CredentialRoot -ProductRoot $ProductRoot -Mode $Mode
            Assert-CddsiFastLanePinnedFile -Path $keygenPath -Sha256 $keygen[0].Sha256 `
                -ErrorPrefix 'VM_BOOTSTRAP_KEYGEN'
            if ((Get-CddsiFastLaneCanonicalPathSha256 $keygenPath) -cne $keygen[0].PathBindingToken) {
                throw 'VM_BOOTSTRAP_KEYGEN_PATH_BINDING_MISMATCH'
            }
            $plan
        }
        $publicPackage = ConvertTo-CddsiFastLaneVmBootstrapPublicPackage $package
        $prompt = if ($Mode -ceq 'Live') {
            New-CddsiFastLaneVmAutomationPrompt -Package $publicPackage -BootstrapResult $bootstrap
        } else { $null }
        if ($Mode -ceq 'Live') {
            $staging | Add-Member -NotePropertyName StagingRoot -NotePropertyValue `
                ([IO.Path]::GetFullPath($PackageStagingRoot)) -Force
            $InternalStagingOwnership.Value = $staging
            $InternalCredentialOwnership.Value = $credentialOwnership
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-onboarding-v1'
            Status = $bootstrap.Status; Mode = $Mode; BlockerCode = $null; Package = $publicPackage
            Changed = $(if ($Mode -ceq 'Live') { $bootstrap.Changed -or $staging.Changed } else { $false })
            BootstrapResult = $bootstrap; AutomationPrompt = $prompt
            ExpectedAutomationContract = $publicPackage.AutomationContract
            PackageStagingRootBindingToken = $(if ($null -ne $staging) { $staging.RootBindingToken } else { $null })
            DirectoryCreateCount = [int]$bootstrap.DirectoryCreateCount + $(if ($null -ne $staging) { [int]$staging.DirectoryCreateCount } else { 0 })
            FileWriteCount = [int]$bootstrap.FileWriteCount + $(if ($null -ne $staging) { [int]$staging.FileWriteCount } else { 0 })
            AclMutationCount = [int]$bootstrap.AclMutationCount + $(if ($null -ne $staging) { [int]$staging.AclMutationCount } else { 0 })
            ProcessInvocationCount = $bootstrap.ProcessInvocationCount
            DirectoryDeleteCount = 0; CleanupRequired = $false; CleanupSucceeded = $true
            NetworkRequestCount = 0; GitInvocationCount = 0; ProductLiveInvocationCount = 0; ProductWriteCount = 0
        }
    }
    catch {
        if ($null -ne $staging) {
            $staging | Add-Member -NotePropertyName StagingRoot -NotePropertyValue `
                ([IO.Path]::GetFullPath($PackageStagingRoot)) -Force
        }
        return New-CddsiFastLaneVmBootstrapOnboardingFailureResult -Mode $Mode `
            -FailureException $_.Exception -Staging $staging -Bootstrap $bootstrap `
            -CredentialOwnership $credentialOwnership
    }
}

function Test-CddsiFastLaneVmBootstrapInteger {
    param(
        [AllowNull()]$Value,
        [long]$Minimum = 0,
        [long]$Maximum = [long]::MaxValue
    )
    return (($Value -is [int] -or $Value -is [long]) -and [long]$Value -ge $Minimum -and [long]$Value -le $Maximum)
}

function Test-CddsiFastLaneVmAutomationContract {
    param([AllowNull()]$AutomationContract)

    $properties = @(
        'Id', 'Kind', 'Name', 'Status', 'RRule', 'CadenceMinutes',
        'DestinationContract', 'TargetTaskToken', 'ReconcileMode'
    )
    return (
        $null -ne $AutomationContract -and
        (Test-CddsiExactPropertySet -InputObject $AutomationContract -Expected $properties) -and
        $AutomationContract.Id -ceq 'cddsi-fast-lane-vmtester-minute-poll' -and
        $AutomationContract.Kind -ceq 'heartbeat' -and
        $AutomationContract.Name -ceq 'CDDsi Fast Lane VmTester minute poll' -and
        $AutomationContract.Status -ceq 'PAUSED' -and
        $AutomationContract.RRule -ceq 'FREQ=MINUTELY;INTERVAL=1' -and
        (Test-CddsiFastLaneVmBootstrapInteger $AutomationContract.CadenceMinutes 1 1) -and
        $AutomationContract.DestinationContract -ceq 'local' -and
        $AutomationContract.TargetTaskToken -ceq 'CURRENT_TASK' -and
        $AutomationContract.ReconcileMode -ceq 'CREATE_OR_UPDATE_EXACTLY_ONE'
    )
}

function Test-CddsiFastLaneVmBootstrapResultBinding {
    param(
        [AllowNull()]$Package,
        [AllowNull()]$BootstrapResult
    )

    try {
        $resultProperties = @(
            'SchemaVersion', 'ContractVersion', 'Status', 'Mode', 'Changed', 'ReusedExisting',
            'EvidenceClass', 'BootstrapOnly', 'CredentialRootBindingToken', 'ProductCommitSha',
            'ProductTreeSha', 'ZipSha256', 'ZipLengthBytes', 'ManifestSha256', 'ManifestLengthBytes',
            'ManifestBindingToken', 'InventorySha256', 'InventoryLengthBytes', 'InventoryBindingToken',
            'BundleContentDigestSha256', 'Profiles', 'ProfileCount', 'ProfileReceiptSetBindingToken',
            'PrivateKeyIncluded', 'RealPathIncluded', 'SidIncluded', 'CredentialStatus',
            'RemoteAuthorizationStatus', 'VmCredentialReady', 'RuntimeProtectionAssertionStatus',
            'AutomationId', 'AutomationStatus', 'DirectoryCreateCount', 'FileWriteCount',
            'AclMutationCount', 'ProcessInvocationCount', 'NetworkRequestCount', 'GitInvocationCount',
            'ProductLiveInvocationCount', 'ProductWriteCount'
        )
        if ($null -eq $Package -or $Package.IsValid -ne $true -or
            -not (Test-CddsiFastLaneVmAutomationContract $Package.AutomationContract) -or
            $null -eq $BootstrapResult -or
            -not (Test-CddsiExactPropertySet -InputObject $BootstrapResult -Expected $resultProperties) -or
            -not (Test-CddsiFastLaneVmBootstrapInteger $BootstrapResult.SchemaVersion 1 1) -or
            $BootstrapResult.ContractVersion -cne $script:CddsiFastLaneVmBootstrapResultContract -or
            $BootstrapResult.Status -cne 'VM_BOOTSTRAP_LOCAL_STAGED' -or
            $BootstrapResult.Mode -cne 'Live' -or
            $BootstrapResult.EvidenceClass -cne 'DIAGNOSTIC_ONLY' -or
            $BootstrapResult.BootstrapOnly -ne $true -or
            $BootstrapResult.BootstrapOnly -isnot [bool] -or
            $BootstrapResult.Changed -isnot [bool] -or $BootstrapResult.ReusedExisting -isnot [bool] -or
            $BootstrapResult.Changed -eq $BootstrapResult.ReusedExisting -or
            $BootstrapResult.CredentialRootBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $BootstrapResult.ProfileReceiptSetBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $BootstrapResult.CredentialStatus -cne 'KEYPAIR_STAGED' -or
            $BootstrapResult.RemoteAuthorizationStatus -cne 'UNPROVISIONED' -or
            $BootstrapResult.VmCredentialReady -ne $false -or
            $BootstrapResult.RuntimeProtectionAssertionStatus -cne 'UNPROVISIONED' -or
            $BootstrapResult.PrivateKeyIncluded -isnot [bool] -or $BootstrapResult.PrivateKeyIncluded -ne $false -or
            $BootstrapResult.RealPathIncluded -isnot [bool] -or $BootstrapResult.RealPathIncluded -ne $false -or
            $BootstrapResult.SidIncluded -isnot [bool] -or $BootstrapResult.SidIncluded -ne $false -or
            $BootstrapResult.VmCredentialReady -isnot [bool] -or
            $BootstrapResult.NetworkRequestCount -ne 0 -or
            $BootstrapResult.GitInvocationCount -ne 0 -or
            $BootstrapResult.ProductLiveInvocationCount -ne 0 -or
            $BootstrapResult.ProductWriteCount -ne 0 -or
            $BootstrapResult.AutomationId -cne $Package.AutomationContract.Id -or
            $BootstrapResult.AutomationStatus -cne $Package.AutomationContract.Status) {
            return $false
        }
        foreach ($name in @(
            'ZipSha256', 'ManifestSha256', 'ManifestBindingToken', 'InventorySha256',
            'InventoryBindingToken', 'BundleContentDigestSha256', 'ProductCommitSha', 'ProductTreeSha'
        )) {
            if ([string]$BootstrapResult.$name -cne [string]$Package.$name) { return $false }
        }
        foreach ($name in @('ZipLengthBytes', 'ManifestLengthBytes', 'InventoryLengthBytes')) {
            if (-not (Test-CddsiFastLaneVmBootstrapInteger $BootstrapResult.$name 1) -or
                [long]$BootstrapResult.$name -ne [long]$Package.$name) { return $false }
        }
        foreach ($name in @(
            'DirectoryCreateCount', 'FileWriteCount', 'AclMutationCount', 'ProcessInvocationCount',
            'NetworkRequestCount', 'GitInvocationCount', 'ProductLiveInvocationCount', 'ProductWriteCount'
        )) {
            if (-not (Test-CddsiFastLaneVmBootstrapInteger $BootstrapResult.$name 0)) { return $false }
        }
        if (($BootstrapResult.Changed -and (
                [long]$BootstrapResult.DirectoryCreateCount -ne 1 -or
                [long]$BootstrapResult.FileWriteCount -ne 11 -or
                [long]$BootstrapResult.AclMutationCount -ne 12 -or
                [long]$BootstrapResult.ProcessInvocationCount -ne 6)) -or
            ($BootstrapResult.ReusedExisting -and (
                [long]$BootstrapResult.DirectoryCreateCount -ne 0 -or
                [long]$BootstrapResult.FileWriteCount -ne 0 -or
                [long]$BootstrapResult.AclMutationCount -ne 0 -or
                [long]$BootstrapResult.ProcessInvocationCount -ne 3))) {
            return $false
        }
        $profiles = @($BootstrapResult.Profiles)
        $profileProperties = @(
            'ProfileId', 'Algorithm', 'PublicKey', 'PublicKeySha256', 'PublicKeyFingerprint',
            'State', 'RemoteAuthorizationStatus', 'VmCredentialReady', 'ReceiptBindingToken', 'ReceiptSha256'
        )
        if (-not (Test-CddsiFastLaneVmBootstrapInteger $BootstrapResult.ProfileCount 3 3) -or
            $profiles.Count -ne 3) { return $false }
        for ($index = 0; $index -lt $script:CddsiFastLaneVmBootstrapProfiles.Count; $index++) {
            $profile = $profiles[$index]
            if (-not (Test-CddsiExactPropertySet -InputObject $profile -Expected $profileProperties) -or
                $profile.ProfileId -cne $script:CddsiFastLaneVmBootstrapProfiles[$index] -or
                $profile.Algorithm -cne 'ssh-ed25519' -or
                $profile.PublicKey -cnotmatch '^ssh-ed25519 [A-Za-z0-9+/]+={0,3} cddsi:[a-z0-9.-]+$' -or
                $profile.PublicKeySha256 -cne (Get-CddsiSupplyChainTextBindingToken -Text $profile.PublicKey) -or
                $profile.PublicKeyFingerprint -cnotmatch '^SHA256:[A-Za-z0-9+/]+$' -or
                $profile.State -cne 'KEYPAIR_STAGED' -or
                $profile.RemoteAuthorizationStatus -cne 'UNPROVISIONED' -or
                $profile.VmCredentialReady -isnot [bool] -or $profile.VmCredentialReady -ne $false -or
                $profile.ReceiptBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
                $profile.ReceiptSha256 -cnotmatch '^[a-f0-9]{64}$') {
                return $false
            }
        }
        if (@($profiles.PublicKeyFingerprint | Select-Object -Unique).Count -ne 3 -or
            @($profiles.ReceiptBindingToken | Select-Object -Unique).Count -ne 3 -or
            @($profiles.ReceiptSha256 | Select-Object -Unique).Count -ne 3 -or
            $BootstrapResult.ProfileReceiptSetBindingToken -cne
                (Get-CddsiFastLaneVmBootstrapBindingToken $profiles)) {
            return $false
        }
        return $true
    }
    catch { return $false }
}

function Test-CddsiFastLaneVmRepositoryAndProtectionFacts {
    param([AllowNull()]$Package)

    try {
        $repositoryRootProperties = @('Product', 'HostToVm', 'VmToHost')
        $productProperties = @(
            'RepositoryIdentity', 'RepositoryNumericId', 'RepositoryNodeId',
            'Visibility', 'Ref', 'IntendedAccess'
        )
        $controlProperties = @($productProperties) + @('GenesisCommitSha')
        $protectionProperties = @(
            'RepositoryVisibility', 'PolicySha256', 'HostProtectionFactsAreSenderAuthority',
            'RemoteAuthorizationStatus', 'RuntimeProtectionAssertionStatus'
        )
        if ($null -eq $Package -or
            -not (Test-CddsiExactPropertySet -InputObject $Package.RepositoryFacts `
                -Expected $repositoryRootProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $Package.RepositoryFacts.Product `
                -Expected $productProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $Package.RepositoryFacts.HostToVm `
                -Expected $controlProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $Package.RepositoryFacts.VmToHost `
                -Expected $controlProperties) -or
            -not (Test-CddsiExactPropertySet -InputObject $Package.ProtectionFacts `
                -Expected $protectionProperties)) {
            return $false
        }
        $expected = [ordered]@{
            Product = [pscustomobject]@{
                IntendedAccess = 'READ_ONLY_EXACT_COMMIT'; ProfileId = 'vm.product.read'; HasGenesis = $false
            }
            HostToVm = [pscustomobject]@{
                IntendedAccess = 'READ_ONLY'; ProfileId = 'vm.host-to-vm.read'; HasGenesis = $true
            }
            VmToHost = [pscustomobject]@{
                IntendedAccess = 'APPEND_ONLY'; ProfileId = 'vm.vm-to-host.write'; HasGenesis = $true
            }
        }
        $facts = @()
        foreach ($role in $expected.Keys) {
            $fact = $Package.RepositoryFacts.$role
            if ($fact.RepositoryIdentity -isnot [string] -or
                $fact.RepositoryIdentity -cnotmatch '^github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$' -or
                -not (Test-CddsiFastLaneVmBootstrapInteger $fact.RepositoryNumericId 1) -or
                $fact.RepositoryNodeId -isnot [string] -or
                $fact.RepositoryNodeId -cnotmatch '^[A-Za-z0-9_=-]{4,128}$' -or
                $fact.Visibility -isnot [string] -or $fact.Visibility -cne 'PUBLIC' -or
                $fact.Ref -isnot [string] -or
                $fact.Ref -cnotmatch '^refs/heads/[A-Za-z0-9._*/-]+$' -or
                $fact.IntendedAccess -isnot [string] -or
                $fact.IntendedAccess -cne $expected[$role].IntendedAccess) {
                return $false
            }
            if ($expected[$role].HasGenesis -and (
                    $fact.GenesisCommitSha -isnot [string] -or
                    $fact.GenesisCommitSha -cnotmatch '^[a-f0-9]{40}$')) {
                return $false
            }
            $profileMatches = @($Package.CredentialProfiles | Where-Object {
                $_.ProfileId -ceq $expected[$role].ProfileId
            })
            if ($profileMatches.Count -ne 1) { return $false }
            $profile = $profileMatches[0]
            if (-not (Test-CddsiExactPropertySet -InputObject $profile -Expected @(
                        'ProfileId', 'RepositoryIdentity', 'RepositoryId', 'RepositoryNodeId',
                        'Ref', 'IntendedAccess')) -or
                $profile.RepositoryIdentity -cne $fact.RepositoryIdentity -or
                -not (Test-CddsiFastLaneVmBootstrapInteger $profile.RepositoryId 1) -or
                [long]$profile.RepositoryId -ne [long]$fact.RepositoryNumericId -or
                $profile.RepositoryNodeId -cne $fact.RepositoryNodeId -or
                $profile.Ref -cne $fact.Ref -or
                $profile.IntendedAccess -cne $fact.IntendedAccess) {
                return $false
            }
            $facts += $fact
        }
        if (@($facts.RepositoryIdentity | Select-Object -Unique).Count -ne 3 -or
            @($facts.RepositoryNumericId | Select-Object -Unique).Count -ne 3 -or
            @($facts.RepositoryNodeId | Select-Object -Unique).Count -ne 3 -or
            @($Package.CredentialProfiles).Count -ne 3) {
            return $false
        }
        return (
            $Package.ProtectionFacts.RepositoryVisibility -is [string] -and
            $Package.ProtectionFacts.RepositoryVisibility -ceq 'PUBLIC' -and
            $Package.ProtectionFacts.PolicySha256 -is [string] -and
            $Package.ProtectionFacts.PolicySha256 -cmatch '^[a-f0-9]{64}$' -and
            $Package.ProtectionFacts.PolicySha256 -ceq $Package.SourceBindings.PolicySha256 -and
            $Package.ProtectionFacts.HostProtectionFactsAreSenderAuthority -is [bool] -and
            $Package.ProtectionFacts.HostProtectionFactsAreSenderAuthority -eq $false -and
            $Package.ProtectionFacts.RemoteAuthorizationStatus -is [string] -and
            $Package.ProtectionFacts.RemoteAuthorizationStatus -ceq 'UNPROVISIONED' -and
            $Package.ProtectionFacts.RuntimeProtectionAssertionStatus -is [string] -and
            $Package.ProtectionFacts.RuntimeProtectionAssertionStatus -ceq 'UNPROVISIONED'
        )
    }
    catch { return $false }
}

function New-CddsiFastLaneVmAutomationPrompt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)]$BootstrapResult
    )

    if (-not (Test-CddsiFastLaneVmBootstrapResultBinding -Package $Package -BootstrapResult $BootstrapResult)) {
        throw 'VM_BOOTSTRAP_AUTOMATION_INPUT_NOT_STAGED'
    }
    if (-not (Test-CddsiFastLaneVmRepositoryAndProtectionFacts -Package $Package)) {
        throw 'VM_BOOTSTRAP_AUTOMATION_REPOSITORY_FACTS_INVALID'
    }
    foreach ($value in @(
        $Package.SourceBindings.PolicySha256, $Package.SourceBindings.KnownHostsSha256,
        $Package.SourceBindings.RunnerSha256, $Package.SourceBindings.VmPollPromptSha256,
        $Package.SourceBindings.ResetLibrarySha256, $Package.SourceBindings.ResetRunnerSha256,
        $Package.SourceBindings.ResetProviderSha256
    )) { if ($value -cnotmatch '^[a-f0-9]{64}$') { throw 'VM_BOOTSTRAP_AUTOMATION_SOURCE_BINDING_INVALID' } }
    $profileFacts = @($BootstrapResult.Profiles | ForEach-Object {
        $_.ProfileId + '=' + $_.PublicKeyFingerprint + '/' + $_.ReceiptBindingToken + '/' + $_.ReceiptSha256
    }) -join ','
    $toolFacts = @($Package.Tools | Sort-Object ToolId | ForEach-Object {
        $_.ToolId + '=' + $_.Sha256 + '/' + $_.PathBindingToken
    }) -join ','
    $repositoryFactLines = @(
        foreach ($role in @('Product', 'HostToVm', 'VmToHost')) {
            $fact = $Package.RepositoryFacts.$role
            $line = 'Role=' + $role +
                ';RepositoryIdentity=' + $fact.RepositoryIdentity +
                ';RepositoryNumericId=' + ([long]$fact.RepositoryNumericId).ToString([Globalization.CultureInfo]::InvariantCulture) +
                ';RepositoryNodeId=' + $fact.RepositoryNodeId +
                ';Visibility=' + $fact.Visibility +
                ';Ref=' + $fact.Ref +
                ';IntendedAccess=' + $fact.IntendedAccess
            if ($role -cne 'Product') { $line += ';GenesisCommitSha=' + $fact.GenesisCommitSha }
            $line
        }
    )
    $protectionFactLine = 'RepositoryVisibility=' + $Package.ProtectionFacts.RepositoryVisibility +
        ';PolicySha256=' + $Package.ProtectionFacts.PolicySha256 +
        ';HostProtectionFactsAreSenderAuthority=false' +
        ';RemoteAuthorizationStatus=' + $Package.ProtectionFacts.RemoteAuthorizationStatus +
        ';RuntimeProtectionAssertionStatus=' + $Package.ProtectionFacts.RuntimeProtectionAssertionStatus
    return @"
ReconcileMode=$($Package.AutomationContract.ReconcileMode)
Id=$($Package.AutomationContract.Id)
Kind=$($Package.AutomationContract.Kind)
Name=$($Package.AutomationContract.Name)
Status=$($Package.AutomationContract.Status)
RRule=$($Package.AutomationContract.RRule)
CadenceMinutes=$($Package.AutomationContract.CadenceMinutes)
DestinationContract=$($Package.AutomationContract.DestinationContract)
TargetTaskToken=$($Package.AutomationContract.TargetTaskToken)
Create or update exactly one VM-local Codex automation with every value above exact; never create a duplicate.
This is bootstrap-only DIAGNOSTIC_ONLY work for product commit $($Package.ProductCommitSha), tree $($Package.ProductTreeSha), ZIP $($Package.ZipSha256)/$($Package.ZipLengthBytes), manifest $($Package.ManifestSha256)/$($Package.ManifestLengthBytes)/$($Package.ManifestBindingToken), inventory $($Package.InventorySha256)/$($Package.InventoryLengthBytes)/$($Package.InventoryBindingToken), and bundle $($Package.BundleContentDigestSha256).
Bind policy=$($Package.SourceBindings.PolicySha256), vm-poll=$($Package.SourceBindings.VmPollPromptSha256), runner=$($Package.SourceBindings.RunnerSha256), reset-library=$($Package.SourceBindings.ResetLibrarySha256), reset-runner=$($Package.SourceBindings.ResetRunnerSha256), reset-provider=$($Package.SourceBindings.ResetProviderSha256), known-hosts=$($Package.SourceBindings.KnownHostsSha256).
RepositoryFacts=$($repositoryFactLines -join '|')
ProtectionFacts=$protectionFactLine
Host protection observations are public safety facts only and are never sender authority.
Bind exactly five pinned tools: $toolFacts.
Device-local key profile receipts are KEYPAIR_STAGED only: $profileFacts. VmCredentialReady=false, remote credential authorization is UNPROVISIONED, and runtime protection assertion is UNPROVISIONED.
Fail closed while either value is UNPROVISIONED: do not poll, publish, clone, fetch, test, reset, run product Live, edit/commit/push product code, merge, promote, or release.
Never print private keys, credential paths, user paths, or SIDs. Return only the redacted automation id, PAUSED status, prompt hash, and the two UNPROVISIONED states.
"@.Trim()
}

    function ConvertFrom-CddsiFastLaneVmAutomationTomlBasicString {
        param([Parameter(Mandatory = $true)][string]$Literal)

        if ($Literal.Length -lt 2 -or $Literal[0] -ne [char]0x22 -or
            $Literal[$Literal.Length - 1] -ne [char]0x22) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_STRING_INVALID'
        }
        $builder = New-Object Text.StringBuilder
        for ($index = 1; $index -lt ($Literal.Length - 1); $index++) {
            $character = $Literal[$index]
            $code = [int][char]$character
            if ($character -eq [char]0x22 -or $code -lt 0x20 -or $code -eq 0x7f) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_STRING_INVALID'
            }
            if ($character -ne [char]0x5c) {
                [void]$builder.Append($character)
                continue
            }
            $index++
            if ($index -ge ($Literal.Length - 1)) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_ESCAPE_INVALID'
            }
            $escape = $Literal[$index]
            if ($escape -eq [char]0x22) { [void]$builder.Append([char]0x22); continue }
            if ($escape -eq [char]0x5c) { [void]$builder.Append([char]0x5c); continue }
            if ($escape -eq 'b') { [void]$builder.Append([char]0x08); continue }
            if ($escape -eq 't') { [void]$builder.Append([char]0x09); continue }
            if ($escape -eq 'n') { [void]$builder.Append([char]0x0a); continue }
            if ($escape -eq 'f') { [void]$builder.Append([char]0x0c); continue }
            if ($escape -eq 'r') { [void]$builder.Append([char]0x0d); continue }
            if ($escape -eq 'u') { $digitCount = 4 }
            elseif ($escape -eq 'U') { $digitCount = 8 }
            else { throw 'VM_BOOTSTRAP_AUTOMATION_TOML_ESCAPE_INVALID' }
            if (($index + $digitCount) -ge $Literal.Length) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_ESCAPE_INVALID'
            }
            $digits = $Literal.Substring($index + 1, $digitCount)
            if ($digits -cnotmatch ('^[a-fA-F0-9]{' + $digitCount + '}$')) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_ESCAPE_INVALID'
            }
            $scalar = [Convert]::ToInt32($digits, 16)
            if ($scalar -gt 0x10ffff -or ($scalar -ge 0xd800 -and $scalar -le 0xdfff)) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_ESCAPE_INVALID'
            }
            [void]$builder.Append([char]::ConvertFromUtf32($scalar))
            $index += $digitCount
        }
        return $builder.ToString()
    }

    function Read-CddsiFastLaneVmAutomationToml {
        param([Parameter(Mandatory = $true)][IO.FileStream]$Stream)

        if ($Stream.Length -lt 32 -or $Stream.Length -gt 262144 -or
            $Stream.Length -gt [int]::MaxValue) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_LENGTH_INVALID'
        }
        $Stream.Position = 0
        $bytes = New-Object byte[] ([int]$Stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'VM_BOOTSTRAP_AUTOMATION_TOML_READ_FAILED' }
            $offset += $read
        }
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and $bytes[2] -eq 0xbf) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_BOM_FORBIDDEN'
        }
        $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
        if ($text.IndexOf("`0", [StringComparison]::Ordinal) -ge 0 -or $text -match "`r(?!`n)") {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_TEXT_INVALID'
        }
        $expectedKeys = @(
            'version', 'id', 'kind', 'name', 'prompt', 'status', 'rrule',
            'target_thread_id', 'created_at', 'updated_at'
        )
        $values = [ordered]@{}
        foreach ($line in @($text -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -cnotmatch '^([a-z_]+)[ \t]*=[ \t]*(.+)$') {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_LINE_INVALID'
            }
            $key = [string]$Matches[1]; $literal = ([string]$Matches[2]).Trim()
            if ($expectedKeys -cnotcontains $key -or $values.Contains($key)) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_KEY_INVALID'
            }
            if (@('version', 'created_at', 'updated_at') -ccontains $key) {
                if ($literal -cnotmatch '^(0|[1-9][0-9]*)$') {
                    throw 'VM_BOOTSTRAP_AUTOMATION_TOML_INTEGER_INVALID'
                }
                $number = 0L
                if (-not [long]::TryParse(
                    $literal, [Globalization.NumberStyles]::None,
                    [Globalization.CultureInfo]::InvariantCulture, [ref]$number)) {
                    throw 'VM_BOOTSTRAP_AUTOMATION_TOML_INTEGER_INVALID'
                }
                $values[$key] = $number
            }
            else {
                $values[$key] = ConvertFrom-CddsiFastLaneVmAutomationTomlBasicString $literal
            }
        }
        if ($values.Count -ne $expectedKeys.Count -or
            (@($values.Keys | Sort-Object) -join "`n") -cne (@($expectedKeys | Sort-Object) -join "`n")) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_KEY_SET_INVALID'
        }
        if ([long]$values.version -ne 1 -or [long]$values.created_at -lt 0 -or
            [long]$values.updated_at -lt [long]$values.created_at -or
            $values.id -cnotmatch '^[a-z0-9][a-z0-9._-]{0,127}$' -or
            $values.kind -cnotmatch '^[a-z][a-z0-9_-]{0,31}$' -or
            [string]::IsNullOrWhiteSpace([string]$values.name) -or
            ([string]$values.name).Length -gt 256 -or
            ([string]$values.prompt).Length -gt 262144 -or
            $values.status -cnotmatch '^[A-Z][A-Z_]{0,31}$' -or
            [string]::IsNullOrWhiteSpace([string]$values.rrule) -or
            ([string]$values.rrule).Length -gt 512 -or
            $values.target_thread_id -cnotmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_VALUE_INVALID'
        }
        return [pscustomobject][ordered]@{
            Version = [long]$values.version; Id = [string]$values.id; Kind = [string]$values.kind
            Name = [string]$values.name; Prompt = [string]$values.prompt; Status = [string]$values.status
            RRule = [string]$values.rrule; TargetThreadId = [string]$values.target_thread_id
            CreatedAt = [long]$values.created_at; UpdatedAt = [long]$values.updated_at
            TomlSha256 = Get-CddsiFastLaneVmBootstrapBytesSha256 $bytes
            TomlLengthBytes = [long]$bytes.LongLength
        }
    }

    function Read-CddsiFastLaneVmAutomationTomlIdentity {
        param([Parameter(Mandatory = $true)][IO.FileStream]$Stream)

        if ($Stream.Length -lt 1 -or $Stream.Length -gt 262144 -or
            $Stream.Length -gt [int]::MaxValue) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_LENGTH_INVALID'
        }
        $Stream.Position = 0
        $bytes = New-Object byte[] ([int]$Stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $Stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) { throw 'VM_BOOTSTRAP_AUTOMATION_TOML_READ_FAILED' }
            $offset += $read
        }
        if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xef -and $bytes[1] -eq 0xbb -and
            $bytes[2] -eq 0xbf) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_BOM_FORBIDDEN'
        }
        $text = (New-Object Text.UTF8Encoding($false, $true)).GetString($bytes)
        if ($text.IndexOf("`0", [StringComparison]::Ordinal) -ge 0 -or $text -match "`r(?!`n)") {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_TEXT_INVALID'
        }
        $identity = [ordered]@{ id = $null; name = $null }
        $seenKeys = New-Object 'Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
        foreach ($line in @($text -split "`r?`n")) {
            if ([string]::IsNullOrWhiteSpace($line)) { continue }
            if ($line -cnotmatch '^([a-z_]+)[ \t]*=[ \t]*(.+)$') {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_IDENTITY_LINE_INVALID'
            }
            $key = [string]$Matches[1]
            if (-not $seenKeys.Add($key)) {
                throw 'VM_BOOTSTRAP_AUTOMATION_TOML_IDENTITY_DUPLICATE'
            }
            if (@('id', 'name') -ccontains $key) {
                $identity[$key] = ConvertFrom-CddsiFastLaneVmAutomationTomlBasicString `
                    (([string]$Matches[2]).Trim())
            }
        }
        if ([string]::IsNullOrEmpty([string]$identity.id) -or
            [string]::IsNullOrEmpty([string]$identity.name)) {
            throw 'VM_BOOTSTRAP_AUTOMATION_TOML_IDENTITY_MISSING'
        }
        return [pscustomobject][ordered]@{
            Id = [string]$identity.id
            Name = [string]$identity.name
        }
    }

    function Get-CddsiFastLaneVmAutomationTomlMatch {
        param([Parameter(Mandatory = $true)][string]$AutomationRoot)

        $targetId = 'cddsi-fast-lane-vmtester-minute-poll'
        $targetName = 'CDDsi Fast Lane VmTester minute poll'
        if ([IO.File]::Exists($AutomationRoot)) {
            throw 'VM_BOOTSTRAP_AUTOMATION_ROOT_INVALID'
        }
        if (-not [IO.Directory]::Exists($AutomationRoot)) {
            return [pscustomobject][ordered]@{
                MatchCount = 0; AutomationDirectory = $null; TomlPath = $null
                Toml = $null; Stream = $null
            }
        }
        if (-not (Test-CddsiFastLanePathWithoutReparsePoint $AutomationRoot)) {
            throw 'VM_BOOTSTRAP_AUTOMATION_ROOT_INVALID'
        }

        $match = $null
        try {
            foreach ($directoryPath in @([IO.Directory]::EnumerateDirectories(
                        $AutomationRoot, '*', [IO.SearchOption]::TopDirectoryOnly))) {
                $directory = [IO.Path]::GetFullPath($directoryPath)
                if (-not (Test-CddsiFastLanePathWithinRoot $directory $AutomationRoot) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $directory)) {
                    throw 'VM_BOOTSTRAP_AUTOMATION_DIRECTORY_INVALID'
                }
                $tomlPath = [IO.Path]::GetFullPath((Join-Path $directory 'automation.toml'))
                $directoryLeaf = [IO.Path]::GetFileName($directory)
                if (-not [IO.File]::Exists($tomlPath)) {
                    if ($directoryLeaf.Equals($targetId, [StringComparison]::OrdinalIgnoreCase)) {
                        throw 'VM_BOOTSTRAP_AUTOMATION_TOML_PATH_INVALID'
                    }
                    continue
                }
                if (-not (Test-CddsiFastLanePathWithinRoot $tomlPath $directory) -or
                    -not (Test-CddsiFastLanePathWithoutReparsePoint $tomlPath)) {
                    throw 'VM_BOOTSTRAP_AUTOMATION_TOML_PATH_INVALID'
                }
                $stream = [IO.File]::Open(
                    $tomlPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
                $keepStream = $false
                try {
                    if (-not (Test-CddsiFastLanePathWithoutReparsePoint $tomlPath)) {
                        throw 'VM_BOOTSTRAP_AUTOMATION_TOML_PATH_INVALID'
                    }
                    $directoryTargetsId = $directoryLeaf.Equals(
                        $targetId, [StringComparison]::OrdinalIgnoreCase)
                    $identity = Read-CddsiFastLaneVmAutomationTomlIdentity -Stream $stream
                    $isIdMatch = $identity.Id -ceq $targetId
                    $isNameMatch = $identity.Name -ceq $targetName
                    $toml = $null
                    if ($directoryTargetsId -or $isIdMatch -or $isNameMatch) {
                        $toml = Read-CddsiFastLaneVmAutomationToml -Stream $stream
                        $isIdMatch = $toml.Id -ceq $targetId
                        $isNameMatch = $toml.Name -ceq $targetName
                    }
                    if ($directoryTargetsId -and (-not $isIdMatch -or -not $isNameMatch)) {
                        throw 'VM_BOOTSTRAP_AUTOMATION_MATCH_COUNT_INVALID'
                    }
                    if ($isIdMatch -or $isNameMatch) {
                        if ($null -ne $match -or -not $isIdMatch -or -not $isNameMatch -or
                            $directoryLeaf -cne $targetId -or
                            $toml.Kind -cne 'heartbeat' -or $toml.Status -cne 'PAUSED' -or
                            $toml.RRule -cne 'FREQ=MINUTELY;INTERVAL=1') {
                            throw 'VM_BOOTSTRAP_AUTOMATION_MATCH_COUNT_INVALID'
                        }
                        $match = [pscustomobject][ordered]@{
                            MatchCount = 1; AutomationDirectory = $directory; TomlPath = $tomlPath
                            Toml = $toml; Stream = $stream
                        }
                        $keepStream = $true
                    }
                }
                finally {
                    if (-not $keepStream) { $stream.Dispose() }
                }
            }
            if ($null -eq $match) {
                return [pscustomobject][ordered]@{
                    MatchCount = 0; AutomationDirectory = $null; TomlPath = $null
                    Toml = $null; Stream = $null
                }
            }
            return $match
        }
        catch {
            if ($null -ne $match -and $null -ne $match.Stream) { $match.Stream.Dispose() }
            throw
        }
    }

    function Get-CddsiFastLaneVmAutomationTomlReadback {
        param(
            [Parameter(Mandatory = $true)][string]$AutomationRoot,
            [Parameter(Mandatory = $true)]$OriginalMatch
        )

        if (-not (Test-CddsiExactPropertySet -InputObject $OriginalMatch -Expected @(
                    'MatchCount','AutomationDirectory','TomlPath','Toml','Stream'
                )) -or $OriginalMatch.MatchCount -ne 1 -or
            $OriginalMatch.Stream -isnot [IO.FileStream] -or -not $OriginalMatch.Stream.CanRead -or
            $null -eq $OriginalMatch.Toml) {
            throw 'VM_BOOTSTRAP_AUTOMATION_ORIGINAL_LEASE_INVALID'
        }
        $readback = $null
        $keepStream = $false
        try {
            $readback = Get-CddsiFastLaneVmAutomationTomlMatch -AutomationRoot $AutomationRoot
            if ($readback.MatchCount -ne 1 -or $readback.Stream -isnot [IO.FileStream] -or
                -not $readback.Stream.CanRead -or
                (Get-CddsiFastLaneCanonicalPathSha256 $readback.AutomationDirectory) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $OriginalMatch.AutomationDirectory) -or
                (Get-CddsiFastLaneCanonicalPathSha256 $readback.TomlPath) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $OriginalMatch.TomlPath) -or
                $readback.Toml.TomlSha256 -cne $OriginalMatch.Toml.TomlSha256 -or
                [long]$readback.Toml.TomlLengthBytes -ne
                    [long]$OriginalMatch.Toml.TomlLengthBytes -or
                (ConvertTo-CddsiVmTestRelayCanonicalJson $readback.Toml) -cne
                    (ConvertTo-CddsiVmTestRelayCanonicalJson $OriginalMatch.Toml)) {
                throw 'VM_BOOTSTRAP_AUTOMATION_READBACK_INVALID'
            }
            $keepStream = $true
            return $readback
        }
        finally {
            if (-not $keepStream -and $null -ne $readback -and $null -ne $readback.Stream) {
                $readback.Stream.Dispose()
            }
        }
    }

    function New-CddsiFastLaneVmBootstrapHandoffClosure {
        param(
            [Parameter(Mandatory = $true)]$Package,
            [Parameter(Mandatory = $true)]$BootstrapResult,
            [Parameter(Mandatory = $true)]$AutomationToml,
            [Parameter(Mandatory = $true)][string]$ExpectedCurrentThreadId
        )

        if (-not (Test-CddsiFastLaneVmBootstrapResultBinding `
            -Package $Package -BootstrapResult $BootstrapResult)) {
            throw 'VM_BOOTSTRAP_HANDOFF_RESULT_BINDING_INVALID'
        }
        $expectedPrompt = New-CddsiFastLaneVmAutomationPrompt `
            -Package $Package -BootstrapResult $BootstrapResult
        $promptSha = Get-CddsiSupplyChainTextBindingToken -Text $expectedPrompt
        $tomlProperties = @(
            'Version', 'Id', 'Kind', 'Name', 'Prompt', 'Status', 'RRule', 'TargetThreadId',
            'CreatedAt', 'UpdatedAt', 'TomlSha256', 'TomlLengthBytes'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $AutomationToml -Expected $tomlProperties) -or
            -not (Test-CddsiFastLaneVmBootstrapInteger $AutomationToml.Version 1 1) -or
            $AutomationToml.Id -cne $Package.AutomationContract.Id -or
            $AutomationToml.Kind -cne $Package.AutomationContract.Kind -or
            $AutomationToml.Name -cne $Package.AutomationContract.Name -or
            $AutomationToml.Prompt -cne $expectedPrompt -or
            $AutomationToml.Status -cne $Package.AutomationContract.Status -or
            $AutomationToml.RRule -cne $Package.AutomationContract.RRule -or
            -not (Test-CddsiFastLaneVmAutomationCurrentTaskBinding `
                -ObservedTargetThreadId $AutomationToml.TargetThreadId `
                -ExpectedCurrentThreadId $ExpectedCurrentThreadId) -or
            -not (Test-CddsiFastLaneVmBootstrapInteger $AutomationToml.CreatedAt 0) -or
            -not (Test-CddsiFastLaneVmBootstrapInteger $AutomationToml.UpdatedAt $AutomationToml.CreatedAt) -or
            $AutomationToml.TomlSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            -not (Test-CddsiFastLaneVmBootstrapInteger $AutomationToml.TomlLengthBytes 32 262144)) {
            throw 'VM_BOOTSTRAP_HANDOFF_BINDING_INVALID'
        }
        $automationObservation = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-automation-observation-v3'
            MatchCount = 1; Id = $AutomationToml.Id; Kind = $AutomationToml.Kind
            Name = $AutomationToml.Name; Status = $AutomationToml.Status
            RRule = $AutomationToml.RRule; TargetThreadId = $AutomationToml.TargetThreadId
            CadenceMinutes = [long]$Package.AutomationContract.CadenceMinutes
            DestinationContract = $Package.AutomationContract.DestinationContract
            TargetTaskToken = $Package.AutomationContract.TargetTaskToken
            ReconcileMode = $Package.AutomationContract.ReconcileMode
            Prompt = $AutomationToml.Prompt; PromptSha256 = $promptSha
            TomlSha256 = $AutomationToml.TomlSha256
            TomlLengthBytes = [long]$AutomationToml.TomlLengthBytes
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-handoff-v2'
            Status = 'VM_BOOTSTRAP_STAGED'; EvidenceClass = 'DIAGNOSTIC_ONLY'; BootstrapOnly = $true
            PackageRevalidated = $true
            ProductCommitSha = $Package.ProductCommitSha; ProductTreeSha = $Package.ProductTreeSha
            ZipSha256 = $Package.ZipSha256; ZipLengthBytes = $Package.ZipLengthBytes
            ManifestSha256 = $Package.ManifestSha256; ManifestLengthBytes = $Package.ManifestLengthBytes
            ManifestBindingToken = $Package.ManifestBindingToken
            InventorySha256 = $Package.InventorySha256; InventoryLengthBytes = $Package.InventoryLengthBytes
            InventoryBindingToken = $Package.InventoryBindingToken
            BundleContentDigestSha256 = $Package.BundleContentDigestSha256
            PublicProfiles = @($BootstrapResult.Profiles); PublicProfileCount = $BootstrapResult.ProfileCount
            AutomationContract = $Package.AutomationContract
            AutomationId = $Package.AutomationContract.Id; AutomationStatus = $Package.AutomationContract.Status
            AutomationPromptSha256 = $promptSha
            AutomationTomlSha256 = $AutomationToml.TomlSha256
            AutomationTomlLengthBytes = [long]$AutomationToml.TomlLengthBytes
            AutomationTargetThreadBindingToken = Get-CddsiSupplyChainTextBindingToken `
                -Text $AutomationToml.TargetThreadId
            AutomationReadbackBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $automationObservation
            CredentialStatus = 'KEYPAIR_STAGED'; RemoteAuthorizationStatus = 'UNPROVISIONED'
            VmCredentialReady = $false; RuntimeProtectionAssertionStatus = 'UNPROVISIONED'
            PrivateKeyIncluded = $false; RealPathIncluded = $false; SidIncluded = $false
            NetworkRequestCount = 0; GitInvocationCount = 0
            ProductLiveInvocationCount = 0; ProductWriteCount = 0
            CanStartVmIntegration = $false; P10A0AComplete = $false; CanStartFormalP10A = $false
        }
    }

    function Test-CddsiFastLaneVmAutomationCurrentTaskBinding {
        param(
            [Parameter(Mandatory = $true)][string]$ObservedTargetThreadId,
            [Parameter(Mandatory = $true)][string]$ExpectedCurrentThreadId
        )

        return (
            $ObservedTargetThreadId -cmatch
                '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -and
            $ExpectedCurrentThreadId -cmatch
                '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$' -and
            $ObservedTargetThreadId -ceq $ExpectedCurrentThreadId
        )
    }

    $automationStream = $null
    $automationMatch = $null
    $automationReadbackStream = $null
    $automationReadbackMatch = $null
    $automationReadbackAttempted = $false
    $automationReadbackObservedCount = $null
    $phaseOne = $null
    $phaseOneStagingOwnership = $null
    $phaseOneCredentialOwnership = $null
    $packageRevalidated = $false
    $expectedCurrentThreadId = $null
    try {
        if (-not (Test-CddsiFastLaneVmBootstrapExecutionContext `
                -Context $BootstrapExecutionContext -BoundPaths @(
                    $ZipPath, $ProgramFilesRoot, $SystemRoot, $LocalApplicationDataRoot, $CodexHome
                ))) {
            throw 'VM_BOOTSTRAP_EXECUTION_CONTEXT_INVALID'
        }
        if ($ExpectedAutomationTargetCurrentTaskToken -cne 'CURRENT_TASK') {
            throw 'VM_BOOTSTRAP_AUTOMATION_TARGET_INVALID'
        }
        if (-not [IO.Path]::IsPathRooted($ProgramFilesRoot) -or
            -not [IO.Path]::IsPathRooted($SystemRoot) -or
            -not [IO.Path]::IsPathRooted($LocalApplicationDataRoot) -or
            -not [IO.Path]::IsPathRooted($CodexHome)) {
            throw 'VM_BOOTSTRAP_HANDOFF_ROOT_INVALID'
        }
        if ($Mode -ceq 'Live') {
            if ($BootstrapExecutionContext.Kind -cne 'VmDevice' -or
                $BootstrapExecutionContext.SyntheticOnly -or
                -not $BootstrapExecutionContext.MutationAllowed -or
                -not $AcknowledgeVmBootstrapLive) {
                throw 'VM_BOOTSTRAP_LIVE_ACK_REQUIRED'
            }
            $actualProgramFiles = [Environment]::GetEnvironmentVariable('ProgramFiles', 'Machine')
            $actualSystemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
            if ([string]::IsNullOrWhiteSpace($actualProgramFiles)) { $actualProgramFiles = $env:ProgramFiles }
            if ([string]::IsNullOrWhiteSpace($actualSystemRoot)) { $actualSystemRoot = $env:SystemRoot }
            $actualLocalApplicationData = [Environment]::GetFolderPath(
                [Environment+SpecialFolder]::LocalApplicationData)
            $actualCodexHome = [Environment]::GetEnvironmentVariable('CODEX_HOME', 'Process')
            if ([string]::IsNullOrWhiteSpace($actualCodexHome)) {
                $actualUserProfile = [Environment]::GetFolderPath([Environment+SpecialFolder]::UserProfile)
                if ([string]::IsNullOrWhiteSpace($actualUserProfile)) {
                    throw 'VM_BOOTSTRAP_CODEX_HOME_UNAVAILABLE'
                }
                $actualCodexHome = Join-Path $actualUserProfile '.codex'
            }
            $expectedCurrentThreadId = [Environment]::GetEnvironmentVariable(
                'CODEX_THREAD_ID', 'Process')
            if ([string]::IsNullOrWhiteSpace($expectedCurrentThreadId) -or
                $expectedCurrentThreadId -cnotmatch
                    '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') {
                throw 'VM_BOOTSTRAP_CURRENT_TASK_THREAD_ID_UNAVAILABLE'
            }
            if ([string]::IsNullOrWhiteSpace($actualProgramFiles) -or
                [string]::IsNullOrWhiteSpace($actualSystemRoot) -or
                [string]::IsNullOrWhiteSpace($actualLocalApplicationData) -or
                (Get-CddsiFastLaneCanonicalPathSha256 $ProgramFilesRoot) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $actualProgramFiles) -or
                (Get-CddsiFastLaneCanonicalPathSha256 $SystemRoot) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $actualSystemRoot) -or
                (Get-CddsiFastLaneCanonicalPathSha256 $LocalApplicationDataRoot) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $actualLocalApplicationData) -or
                (Get-CddsiFastLaneCanonicalPathSha256 $CodexHome) -cne
                    (Get-CddsiFastLaneCanonicalPathSha256 $actualCodexHome)) {
                throw 'VM_BOOTSTRAP_LIVE_SYSTEM_ROOT_MISMATCH'
            }
        }
        elseif ($BootstrapExecutionContext.Kind -cne 'HostSandboxFake') {
            throw 'VM_BOOTSTRAP_EXECUTION_CONTEXT_INVALID'
        }

        $codexHomeFull = [IO.Path]::GetFullPath($CodexHome).TrimEnd('\', '/')
        if (-not [IO.Directory]::Exists($codexHomeFull) -or
            -not (Test-CddsiFastLanePathWithoutReparsePoint $codexHomeFull)) {
            throw 'VM_BOOTSTRAP_CODEX_HOME_INVALID'
        }
        $automationRoot = [IO.Path]::GetFullPath((Join-Path $codexHomeFull 'automations'))
        $automationMatch = Get-CddsiFastLaneVmAutomationTomlMatch -AutomationRoot $automationRoot
        if ($automationMatch.MatchCount -eq 1) {
            $automationStream = $automationMatch.Stream
            if ($Mode -ceq 'Live' -and -not (
                    Test-CddsiFastLaneVmAutomationCurrentTaskBinding `
                        -ObservedTargetThreadId $automationMatch.Toml.TargetThreadId `
                        -ExpectedCurrentThreadId $expectedCurrentThreadId)) {
                throw 'VM_BOOTSTRAP_AUTOMATION_CURRENT_TASK_BINDING_INVALID'
            }
        }

        $fixedRoots = Get-CddsiFastLaneVmBootstrapFixedRoots `
            -LocalApplicationDataRoot $LocalApplicationDataRoot `
            -ZipSha256 $ExpectedZipSha256 -ProductCommitSha $ExpectedProductCommitSha
        if ($Mode -ceq 'Live' -and $automationMatch.MatchCount -eq 1 -and (
                -not [IO.Directory]::Exists($fixedRoots.PackageStagingRoot) -or
                -not [IO.Directory]::Exists($fixedRoots.CredentialRoot))) {
            throw 'VM_BOOTSTRAP_AUTOMATION_PRECEDES_LOCAL_STAGING'
        }
        $phaseOneArguments = @{
            Mode = $Mode; BootstrapExecutionContext = $BootstrapExecutionContext
            ZipPath = $ZipPath; ExpectedZipSha256 = $ExpectedZipSha256
            ExpectedZipLengthBytes = $ExpectedZipLengthBytes
            ExpectedManifestSha256 = $ExpectedManifestSha256
            ExpectedManifestLengthBytes = $ExpectedManifestLengthBytes
            ExpectedManifestBindingToken = $ExpectedManifestBindingToken
            ExpectedInventorySha256 = $ExpectedInventorySha256
            ExpectedInventoryLengthBytes = $ExpectedInventoryLengthBytes
            ExpectedInventoryBindingToken = $ExpectedInventoryBindingToken
            ExpectedBundleContentDigestSha256 = $ExpectedBundleContentDigestSha256
            ExpectedProductCommitSha = $ExpectedProductCommitSha
            ExpectedProductTreeSha = $ExpectedProductTreeSha
            ProgramFilesRoot = $ProgramFilesRoot; SystemRoot = $SystemRoot
            ProductRoot = $fixedRoots.ProductRoot
            PackageStagingRoot = $fixedRoots.PackageStagingRoot
            CredentialRoot = $fixedRoots.CredentialRoot
            ExpectedAutomationTargetCurrentTaskToken = $ExpectedAutomationTargetCurrentTaskToken
            AcknowledgeVmBootstrapLive = $AcknowledgeVmBootstrapLive
            InternalStagingOwnership = ([ref]$phaseOneStagingOwnership)
            InternalCredentialOwnership = ([ref]$phaseOneCredentialOwnership)
        }
        $phaseOne = Invoke-CddsiFastLaneVmBootstrapOnboardingClosure @phaseOneArguments
        if ($phaseOne.Status -ceq 'VM_BOOTSTRAP_BLOCKED' -or $null -eq $phaseOne.Package) {
            return $phaseOne
        }
        $packageRevalidated = $true
        if ($Mode -cne 'Live') {
            if ($phaseOne.Status -cne 'PLANNED' -or $phaseOne.DirectoryCreateCount -ne 0 -or
                $phaseOne.FileWriteCount -ne 0 -or $phaseOne.AclMutationCount -ne 0 -or
                $phaseOne.ProcessInvocationCount -ne 0) {
                throw 'VM_BOOTSTRAP_HANDOFF_PLAN_SIDE_EFFECT_INVALID'
            }
            $automationToml = $automationMatch.Toml
            return [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-fast-lane-vm-bootstrap-handoff-onboarding-plan-v1'
                Status = 'PLANNED'; Mode = $Mode; EvidenceClass = 'DIAGNOSTIC_ONLY'; BootstrapOnly = $true
                Changed = $false; PackageRevalidated = $true
                AutomationTomlSchemaVerified = ($automationMatch.MatchCount -eq 1)
                AutomationTargetCurrentTaskVerified = $false
                AutomationPromptBindingDeferred = $true
                AutomationMatchCount = [int]$automationMatch.MatchCount
                AutomationTomlSha256 = $(if ($null -ne $automationToml) { $automationToml.TomlSha256 } else { $null })
                AutomationTomlLengthBytes = $(if ($null -ne $automationToml) { $automationToml.TomlLengthBytes } else { $null })
                AutomationPromptReadbackSha256 = $(if ($null -ne $automationToml) {
                    Get-CddsiSupplyChainTextBindingToken -Text $automationToml.Prompt
                } else { $null })
                DirectoryCreateCount = 0; FileWriteCount = 0; AclMutationCount = 0
                ProcessInvocationCount = 0; DirectoryDeleteCount = 0
                CleanupRequired = $false; CleanupSucceeded = $true
                NetworkRequestCount = 0; GitInvocationCount = 0
                ProductLiveInvocationCount = 0; ProductWriteCount = 0
                CanStartVmIntegration = $false; P10A0AComplete = $false; CanStartFormalP10A = $false
                PrivateKeyIncluded = $false; RealPathIncluded = $false; SidIncluded = $false
            }
        }
        if ($phaseOne.Status -cne 'VM_BOOTSTRAP_LOCAL_STAGED' -or
            $null -eq $phaseOne.BootstrapResult -or
            [string]::IsNullOrEmpty([string]$phaseOne.AutomationPrompt)) {
            throw 'VM_BOOTSTRAP_PHASE1_REVALIDATION_FAILED'
        }
        if ($automationMatch.MatchCount -eq 0) {
            $automationReadbackAttempted = $true
            $automationReadbackMatch = Get-CddsiFastLaneVmAutomationTomlMatch `
                -AutomationRoot $automationRoot
            $automationReadbackStream = $automationReadbackMatch.Stream
            $automationReadbackObservedCount = [int]$automationReadbackMatch.MatchCount
            if ($automationReadbackObservedCount -eq 0) {
                return $phaseOne
            }
            throw 'VM_BOOTSTRAP_AUTOMATION_STATE_CHANGED_DURING_PHASE1'
        }
        if ($automationMatch.MatchCount -ne 1) {
            throw 'VM_BOOTSTRAP_AUTOMATION_PROMPT_BINDING_INVALID'
        }
        $automationReadbackAttempted = $true
        $automationReadbackMatch = Get-CddsiFastLaneVmAutomationTomlReadback `
            -AutomationRoot $automationRoot -OriginalMatch $automationMatch
        $automationReadbackStream = $automationReadbackMatch.Stream
        $automationReadbackObservedCount = [int]$automationReadbackMatch.MatchCount
        if ($automationReadbackMatch.Toml.Prompt -cne [string]$phaseOne.AutomationPrompt) {
            throw 'VM_BOOTSTRAP_AUTOMATION_PROMPT_BINDING_INVALID'
        }
        $handoff = New-CddsiFastLaneVmBootstrapHandoffClosure `
            -Package $phaseOne.Package -BootstrapResult $phaseOne.BootstrapResult `
            -AutomationToml $automationReadbackMatch.Toml `
            -ExpectedCurrentThreadId $expectedCurrentThreadId
        $handoff | Add-Member -NotePropertyName Changed -NotePropertyValue ([bool]$phaseOne.Changed)
        $handoff | Add-Member -NotePropertyName AutomationTargetCurrentTaskVerified -NotePropertyValue $true
        foreach ($accountingName in @(
            'DirectoryCreateCount', 'FileWriteCount', 'AclMutationCount', 'ProcessInvocationCount',
            'DirectoryDeleteCount', 'CleanupRequired', 'CleanupSucceeded'
        )) {
            $handoff | Add-Member -NotePropertyName $accountingName `
                -NotePropertyValue $phaseOne.$accountingName
        }
        return $handoff
    }
    catch {
        $caughtException = $_.Exception
        $postPhaseCompensationFailed = $false
        if ($Mode -ceq 'Live' -and $null -ne $phaseOne -and
            $phaseOne.Status -ceq 'VM_BOOTSTRAP_LOCAL_STAGED') {
            $preCompensationPhaseOne = $phaseOne
            $compensationContext = [pscustomobject][ordered]@{
                FailureException = $caughtException
                Staging = $phaseOneStagingOwnership
                Bootstrap = $phaseOne.BootstrapResult
                CredentialOwnership = $phaseOneCredentialOwnership
            }
            $compensationArguments = @{} + $phaseOneArguments
            $compensationArguments.InternalCompensationContext = $compensationContext
            try {
                $phaseOne = Invoke-CddsiFastLaneVmBootstrapOnboardingClosure `
                    @compensationArguments
                if ($phaseOne.CleanupSucceeded -ne $true) {
                    $caughtException = New-Object InvalidOperationException(
                        'VM_BOOTSTRAP_POST_PHASE_CLEANUP_FAILED')
                }
            }
            catch {
                $phaseOne = $preCompensationPhaseOne
                $caughtException = New-Object InvalidOperationException(
                    'VM_BOOTSTRAP_POST_PHASE_CLEANUP_FAILED')
                $postPhaseCompensationFailed = $true
            }
        }
        $changed = $false
        $directoryCreateCount = 0; $fileWriteCount = 0; $aclMutationCount = 0
        $processInvocationCount = 0; $directoryDeleteCount = 0
        $cleanupRequired = $false; $cleanupSucceeded = $true
        if ($null -ne $phaseOne) {
            $changed = [bool]$phaseOne.Changed
            $directoryCreateCount = [int]$phaseOne.DirectoryCreateCount
            $fileWriteCount = [int]$phaseOne.FileWriteCount
            $aclMutationCount = [int]$phaseOne.AclMutationCount
            $processInvocationCount = [int]$phaseOne.ProcessInvocationCount
            $directoryDeleteCount = [int]$phaseOne.DirectoryDeleteCount
            $cleanupRequired = [bool]$phaseOne.CleanupRequired
            $cleanupSucceeded = [bool]$phaseOne.CleanupSucceeded
        }
        if ($postPhaseCompensationFailed) {
            $changed = [bool]$phaseOne.Changed
            $cleanupRequired = [bool]$phaseOne.Changed
            $cleanupSucceeded = -not $cleanupRequired
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-fast-lane-vm-bootstrap-handoff-onboarding-v1'
            Status = 'VM_BOOTSTRAP_BLOCKED'; Mode = $Mode
            BlockerCode = Resolve-CddsiFastLaneVmBootstrapBlockerCode $caughtException.Message
            Changed = $changed; PackageRevalidated = $packageRevalidated
            AutomationMatchCount = $(if ($automationReadbackAttempted -and
                    $null -eq $automationReadbackObservedCount) {
                -1
            } elseif ($null -ne $automationReadbackObservedCount) {
                [int]$automationReadbackObservedCount
            } elseif ($null -ne $automationMatch) {
                [int]$automationMatch.MatchCount
            } else { 0 })
            AutomationTargetCurrentTaskVerified = $false
            DirectoryCreateCount = $directoryCreateCount; FileWriteCount = $fileWriteCount
            AclMutationCount = $aclMutationCount; ProcessInvocationCount = $processInvocationCount
            DirectoryDeleteCount = $directoryDeleteCount
            CleanupRequired = $cleanupRequired; CleanupSucceeded = $cleanupSucceeded
            NetworkRequestCount = 0; GitInvocationCount = 0
            ProductLiveInvocationCount = 0; ProductWriteCount = 0
            CanStartVmIntegration = $false; P10A0AComplete = $false; CanStartFormalP10A = $false
            PrivateKeyIncluded = $false; RealPathIncluded = $false; SidIncluded = $false
        }
    }
    finally {
        if ($null -ne $automationReadbackStream) { $automationReadbackStream.Dispose() }
        if ($null -ne $automationStream) { $automationStream.Dispose() }
    }
}

function New-CddsiFastLaneVmBootstrapHandoff {
    [CmdletBinding()]
    param()

    throw 'VM_BOOTSTRAP_HANDOFF_DIRECT_INVOCATION_FORBIDDEN'
}
