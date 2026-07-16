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
        private const int JobObjectExtendedLimitInformation = 9;

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
            using (var process = new Process()) {
                process.StartInfo = info;
                try {
                    if (!process.Start()) throw new InvalidOperationException("Process did not start.");
                    if (!AssignProcessToJobObject(job, process.Handle)) {
                        try { process.Kill(); } catch { }
                        throw new InvalidOperationException("Process job assignment failed.");
                    }
                var output = new Capture();
                var error = new Capture();
                int perStreamLimit = Math.Max(256, maximumOutputBytes / 2);
                var outputThread = new Thread(() => Drain(process.StandardOutput, output, perStreamLimit));
                var errorThread = new Thread(() => Drain(process.StandardError, error, perStreamLimit));
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
                if (!exited) {
                    try { TerminateJobObject(job, 137); } catch { }
                    try { process.Kill(); } catch { }
                    process.WaitForExit(5000);
                }
                outputThread.Join(5000);
                errorThread.Join(5000);
                return new BoundedProcessResult {
                    ExitCode = exited ? process.ExitCode : -1,
                    TimedOut = !exited,
                    Truncated = output.Truncated || error.Truncated,
                    JobAssigned = true,
                    ProcessTreeTerminated = !exited,
                    StandardOutput = output.Text.ToString(),
                    StandardError = error.Text.ToString()
                };
                }
                finally { if (job != IntPtr.Zero) CloseHandle(job); }
            }
        }
    }
}
'@
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
        '-c', 'core.longpaths=true'
    )
    if ($Context.ContainsKey('SshCommand') -and -not [string]::IsNullOrEmpty([string]$Context.SshCommand)) {
        $allArguments += @('-c', ('core.sshCommand=' + [string]$Context.SshCommand))
    }
    $allArguments += $Arguments
    $argumentText = (@($allArguments | ForEach-Object { ConvertTo-CddsiFastLaneGitQuotedArgument -Value $_ }) -join ' ')
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
    $result = [Cddsi.FastLane.BoundedProcessRunner]::Run(
        $Context.GitExecutable, $argumentText, $Context.StateRoot, $environment,
        $StandardInput, $commandTimeout, $Context.MaximumOutputBytes)
    if (-not $result.JobAssigned) { throw 'PROCESS_JOB_ASSIGNMENT_REQUIRED' }
    $Context.JobAssignmentCount = [int]$Context.JobAssignmentCount + 1
    if ($result.ProcessTreeTerminated) { $Context.ProcessTreeTerminationCount = [int]$Context.ProcessTreeTerminationCount + 1 }
    if ($result.TimedOut) { throw 'GIT_COMMAND_TIMEOUT' }
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
    $temporary = Join-Path $parent ('.cddsi-atomic-' + [guid]::NewGuid().ToString('D') + '.tmp')
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
            $backup = Join-Path $parent ('.cddsi-replace-' + [guid]::NewGuid().ToString('D') + '.bak')
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
        [string]$RepositoryPath,
        [string]$RepositoryUri
    )
    if (-not [IO.Directory]::Exists($RepositoryPath)) {
        [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @('init', '--bare', '--quiet', $RepositoryPath) -LocalMutation)
        [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(('--git-dir=' + $RepositoryPath), 'remote', 'add', 'origin', $RepositoryUri) -LocalMutation)
    }
    $remote = Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(('--git-dir=' + $RepositoryPath), 'remote', 'get-url', 'origin')
    if ($remote.StandardOutput.TrimEnd("`r", "`n") -cne $RepositoryUri) { throw 'LOCAL_REMOTE_BINDING_MISMATCH' }
}

function Get-CddsiFastLaneRemoteSnapshot {
    param(
        [hashtable]$Context,
        [string]$RepositoryPath,
        [string]$RemoteRef,
        [string]$ExpectedGenesisCommit,
        [AllowNull()][string]$AcceptedRemoteHead
    )
    $stagingRef = 'refs/cddsi/remote-snapshot'
    [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(('--git-dir=' + $RepositoryPath), 'update-ref', '-d', $stagingRef) -LocalMutation)
    [void](Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments @(
        ('--git-dir=' + $RepositoryPath), 'fetch', '--quiet', '--no-tags', 'origin', ($RemoteRef + ':' + $stagingRef)
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
        'Get-CddsiVmTestRelayMessageSha256',
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
            MaximumMessageCount = $MaximumMessageCount; MaximumRuntimeSeconds = $MaximumRuntimeSeconds
            MaximumOutputBytes = $MaximumOutputBytes; MaximumMessageBodyBytes = $MaximumMessageBodyBytes
            MaximumAgeSeconds = $MaximumAgeSeconds; MaximumClockSkewSeconds = $MaximumClockSkewSeconds
            MaximumRetryCount = $MaximumRetryCount; RetryCount = 0
            ChildEnvironmentInheritedCount = 0; ProcessJobRequired = $true; RelayState = $null
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
        $repositoryPath = Get-CddsiFastLaneGitRepositoryPath $fullStateRoot $RepositoryIdentity
        Initialize-CddsiFastLaneLocalGitRepository $context $repositoryPath $RepositoryUri
        $uriSha = Get-CddsiSupplyChainTextBindingToken -Text $RepositoryUri
        $entry = Get-CddsiFastLaneRepositoryEntry $state $RepositoryIdentity
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
        $snapshot = Get-CddsiFastLaneRemoteSnapshot $context $repositoryPath $RemoteRef $ExpectedGenesisCommit $acceptedHead
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
            while ($remaining -gt 0 -and $processed -lt $MaximumMessageCount) {
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
                ('--git-dir=' + $repositoryPath), 'ls-remote', '--refs', 'origin', $RemoteRef
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
                ('--git-dir=' + $repositoryPath), 'push', '--porcelain', 'origin', ($publishedCommit + ':' + $RemoteRef)
            ) -OperatorTransport)
            $context.OperatorRemoteMutationCount = [int]$context.OperatorRemoteMutationCount + 1
            $verify = Invoke-CddsiFastLaneGitCommand -Context $context -Arguments @(
                ('--git-dir=' + $repositoryPath), 'ls-remote', '--refs', 'origin', $RemoteRef
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
            MaximumMessageCount = $MaximumMessageCount; MaximumRuntimeSeconds = $MaximumRuntimeSeconds
            MaximumOutputBytes = $MaximumOutputBytes; MaximumMessageBodyBytes = $MaximumMessageBodyBytes
            MaximumAgeSeconds = $MaximumAgeSeconds; MaximumClockSkewSeconds = $MaximumClockSkewSeconds
            ChildEnvironmentInheritedCount = 0; ProcessJobRequired = $true
            RelayState = $state.RelayState
        }
    }
    finally { $lock.Dispose() }
}
