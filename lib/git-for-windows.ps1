# git-for-windows.ps1 - Git for Windows detection and official-install contracts.
# This project never changes global Git configuration.

$script:CddsiGitExecutableSignerSubjectPattern = '^CN=Johannes Schindelin, O=Johannes Schindelin, (?:L=Bruehl|S=Nordrhein-Westfalen), C=DE$'
$script:CddsiGitExecutableMaximumBytes = [long](64MB)
$script:CddsiGitProtectedWriterSids = @(
    'S-1-5-18',
    'S-1-5-32-544',
    'S-1-5-80-956008885-3418522649-1831038044-1853292631-2271478464'
)
$script:CddsiGitCreatorOwnerSid = 'S-1-3-0'
$script:CddsiGitDangerousAccessMask = [uint32]0x500D0156

function Test-CddsiD027Windows11X64Platform {
    [CmdletBinding()]
    param()

    try {
        if ($null -eq ('Cddsi.D027.WindowsPlatform' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Cddsi.D027 {
    public static class WindowsPlatform {
        private const ushort IMAGE_FILE_MACHINE_AMD64 = 0x8664;
        private const byte VER_NT_WORKSTATION = 1;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct RTL_OSVERSIONINFOEX {
            internal uint dwOSVersionInfoSize;
            internal uint dwMajorVersion;
            internal uint dwMinorVersion;
            internal uint dwBuildNumber;
            internal uint dwPlatformId;
            [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 128)]
            internal string szCSDVersion;
            internal ushort wServicePackMajor;
            internal ushort wServicePackMinor;
            internal ushort wSuiteMask;
            internal byte wProductType;
            internal byte wReserved;
        }

        [DllImport("kernel32.dll")]
        private static extern IntPtr GetCurrentProcess();

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWow64Process2(
            IntPtr process,
            out ushort processMachine,
            out ushort nativeMachine);

        [DllImport("ntdll.dll", CharSet = CharSet.Unicode)]
        private static extern int RtlGetVersion(ref RTL_OSVERSIONINFOEX version);

        public static bool IsWindows11X64Workstation() {
            ushort processMachine;
            ushort nativeMachine;
            if (!IsWow64Process2(GetCurrentProcess(), out processMachine, out nativeMachine)) {
                return false;
            }
            if (nativeMachine != IMAGE_FILE_MACHINE_AMD64) return false;

            var version = new RTL_OSVERSIONINFOEX();
            version.dwOSVersionInfoSize = (uint)Marshal.SizeOf(typeof(RTL_OSVERSIONINFOEX));
            if (RtlGetVersion(ref version) != 0) return false;
            return
                version.dwMajorVersion == 10 &&
                version.dwBuildNumber >= 22000 &&
                version.wProductType == VER_NT_WORKSTATION;
        }
    }
}
'@
        }
        return [Cddsi.D027.WindowsPlatform]::IsWindows11X64Workstation()
    }
    catch {
        return $false
    }
}

function Assert-CddsiD027GitLiveContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    $localTempValid = $false
    if (
        $null -ne $Context -and
        $null -ne $Context.Paths -and
        $Context.Paths.Temp -is [string] -and
        -not [string]::IsNullOrWhiteSpace($Context.Paths.Temp) -and
        $Context.Paths.Temp.IndexOfAny([char[]]@('*', '?', [char]0)) -lt 0 -and
        $Context.Paths.Temp -match '^[A-Za-z]:\\' -and
        [System.IO.Path]::IsPathRooted($Context.Paths.Temp)
    ) {
        try {
            $tempPath = [System.IO.Path]::GetFullPath($Context.Paths.Temp).TrimEnd('\')
            $tempRoot = [System.IO.Path]::GetPathRoot($tempPath)
            $tempDrive = New-Object System.IO.DriveInfo($tempRoot)
            if (
                $tempDrive.DriveType -ne [System.IO.DriveType]::Fixed -or
                -not [System.IO.Directory]::Exists($tempPath)
            ) {
                throw 'Product temp was not an existing fixed-volume directory.'
            }
            $tempAncestors = New-Object System.Collections.Generic.List[string]
            $tempAncestors.Add($tempRoot)
            $tempAncestor = $tempRoot
            foreach ($segment in @($tempPath.Substring($tempRoot.Length).Split(
                [char[]]@('\'),
                [System.StringSplitOptions]::RemoveEmptyEntries
            ))) {
                $tempAncestor = [System.IO.Path]::Combine($tempAncestor, $segment)
                $tempAncestors.Add($tempAncestor)
            }
            foreach ($tempAncestorPath in $tempAncestors) {
                $attributes = [System.IO.File]::GetAttributes($tempAncestorPath)
                if (
                    ($attributes -band [System.IO.FileAttributes]::Directory) -eq 0 -or
                    ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
                ) {
                    throw 'Product temp had an unsupported ancestor.'
                }
            }
            $localTempValid = $true
        }
        catch {
            $localTempValid = $false
        }
    }

    if (
        $null -eq $Context -or
        $Context.Mode -isnot [string] -or $Context.Mode -cne 'Live' -or
        $null -eq $Context.Paths -or
        $Context.Paths.Temp -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Context.Paths.Temp) -or
        $Context.Paths.Temp.IndexOfAny([char[]]@('*', '?', [char]0)) -ge 0 -or
        $Context.Paths.Temp -notmatch '^[A-Za-z]:\\' -or
        -not [System.IO.Path]::IsPathRooted($Context.Paths.Temp) -or
        -not $localTempValid -or
        -not [Environment]::Is64BitOperatingSystem -or
        -not [Environment]::Is64BitProcess -or
        $PSVersionTable.PSVersion.Major -ne 5 -or
        $PSVersionTable.PSVersion.Minor -ne 1 -or
        -not (Test-CddsiD027Windows11X64Platform)
    ) {
        throw 'D-027 Git Live context requires Windows 11 x64, 64-bit Windows PowerShell 5.1, Live mode and an explicit local product temp path.'
    }
    return $true
}

function ConvertFrom-CddsiGitVersionProbeResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ProbeResult
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ProbeResult -Expected @(
        'SchemaVersion', 'Started', 'TimedOut', 'TerminationComplete', 'OutputTruncated',
        'ExitCode', 'StdOut', 'StdErr'
    ))) {
        throw 'Git version probe result does not match the exact schema.'
    }
    if (
        $ProbeResult.SchemaVersion -isnot [int] -or $ProbeResult.SchemaVersion -ne 1 -or
        $ProbeResult.Started -isnot [bool] -or
        $ProbeResult.TimedOut -isnot [bool] -or
        $ProbeResult.TerminationComplete -isnot [bool] -or
        $ProbeResult.OutputTruncated -isnot [bool] -or
        ($null -ne $ProbeResult.ExitCode -and $ProbeResult.ExitCode -isnot [int]) -or
        $ProbeResult.StdOut -isnot [string] -or
        $ProbeResult.StdErr -isnot [string]
    ) {
        throw 'Git version probe result contains invalid field types.'
    }

    $reasonCode = $null
    if (-not $ProbeResult.Started) {
        $reasonCode = 'GIT_VERSION_PROBE_NOT_STARTED'
    }
    elseif ($ProbeResult.TimedOut) {
        $reasonCode = 'GIT_VERSION_PROBE_TIMEOUT'
    }
    elseif (-not $ProbeResult.TerminationComplete) {
        $reasonCode = 'GIT_VERSION_PROBE_TERMINATION_INCOMPLETE'
    }
    elseif ($ProbeResult.OutputTruncated) {
        $reasonCode = 'GIT_VERSION_OUTPUT_LIMIT_EXCEEDED'
    }
    elseif ($null -eq $ProbeResult.ExitCode -or $ProbeResult.ExitCode -ne 0) {
        $reasonCode = 'GIT_VERSION_PROBE_NONZERO'
    }
    elseif ($ProbeResult.StdErr.Length -ne 0) {
        $reasonCode = 'GIT_VERSION_PROBE_STDERR'
    }
    elseif ($ProbeResult.StdOut.Length -gt 128) {
        $reasonCode = 'GIT_VERSION_OUTPUT_INVALID'
    }

    $match = $null
    if ($null -eq $reasonCode) {
        $component = '(?:0|[1-9][0-9]*)'
        $match = [regex]::Match(
            $ProbeResult.StdOut,
            ('\Agit version (?<base>{0}\.{0}\.{0})\.windows\.(?<revision>[1-9][0-9]*)(?:\r?\n)?\z' -f $component),
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (-not $match.Success) {
            $reasonCode = 'GIT_VERSION_OUTPUT_INVALID'
        }
    }

    $comparisonVersion = $null
    $revision = 0
    if ($null -eq $reasonCode) {
        if (
            -not [int]::TryParse($match.Groups['revision'].Value, [ref]$revision) -or
            $revision -lt 1 -or
            -not [version]::TryParse(
                ('{0}.{1}' -f $match.Groups['base'].Value, $revision),
                [ref]$comparisonVersion
            )
        ) {
            $reasonCode = 'GIT_VERSION_OUTPUT_INVALID'
        }
    }

    return [pscustomobject][ordered]@{
        SchemaVersion     = 1
        Valid             = ($null -eq $reasonCode)
        ReasonCode        = $reasonCode
        Version           = if ($null -eq $reasonCode) { '{0}.windows.{1}' -f $match.Groups['base'].Value, $revision } else { $null }
        ComparisonVersion = if ($null -eq $comparisonVersion) { $null } else { $comparisonVersion.ToString() }
        WindowsRevision   = if ($null -eq $reasonCode) { $revision } else { $null }
    }
}

function ConvertTo-CddsiGitInstallerReceiptVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GitVersion
    )

    $component = '(?:0|[1-9][0-9]*)'
    $match = [regex]::Match(
        $GitVersion,
        ('\A(?<base>{0}\.{0}\.{0})\.windows\.(?<revision>[1-9][0-9]*)\z' -f $component),
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $match.Success) {
        throw 'Git installer receipt version requires an exact Git for Windows version.'
    }
    $revision = 0
    if (-not [int]::TryParse($match.Groups['revision'].Value, [ref]$revision) -or $revision -lt 1) {
        throw 'Git installer receipt revision was invalid.'
    }
    if ($revision -eq 1) {
        return $match.Groups['base'].Value
    }
    return '{0}.{1}' -f $match.Groups['base'].Value, $revision
}

function ConvertFrom-CddsiGitPeHeader {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$HeaderBytes,
        [Parameter(Mandatory = $true)][long]$ImageLength
    )

    if ($ImageLength -lt 64 -or $HeaderBytes.Length -lt 64) { return 'Invalid' }
    if ($HeaderBytes[0] -ne 0x4d -or $HeaderBytes[1] -ne 0x5a) { return 'Invalid' }
    $peOffset = [BitConverter]::ToInt32($HeaderBytes, 0x3c)
    if (
        $peOffset -lt 64 -or
        ([long]$peOffset + 6L) -gt $ImageLength -or
        ([long]$peOffset + 6L) -gt $HeaderBytes.LongLength
    ) {
        return 'Invalid'
    }
    if ([BitConverter]::ToUInt32($HeaderBytes, $peOffset) -ne 0x00004550) { return 'Invalid' }
    switch ([BitConverter]::ToUInt16($HeaderBytes, $peOffset + 4)) {
        0x8664 { return 'x64' }
        0x014c { return 'x86' }
        0xaa64 { return 'arm64' }
        default { return 'Other' }
    }
}

function Test-CddsiCurrentProcessElevated {
    [CmdletBinding()]
    param()

    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    try {
        $principal = New-Object Security.Principal.WindowsPrincipal($identity)
        return $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    finally {
        $identity.Dispose()
    }
}

function Get-CddsiGitForWindowsRegistryObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ExpectedInstallRoot,
        [Parameter(Mandatory = $true)][string]$ExpectedReceiptVersion
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    if (
        [string]::IsNullOrWhiteSpace($ExpectedInstallRoot) -or
        -not [System.IO.Path]::IsPathRooted($ExpectedInstallRoot) -or
        $ExpectedReceiptVersion -notmatch '^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\.[1-9][0-9]*)?$'
    ) {
        throw 'Git registry observation requires an exact install root and installer receipt version.'
    }

    $expectedRoot = [System.IO.Path]::GetFullPath($ExpectedInstallRoot).TrimEnd('\')
    $expectedLibexec = [System.IO.Path]::GetFullPath(
        (Join-Path $expectedRoot 'mingw64\libexec\git-core')
    ).TrimEnd('\')
    $gitKey = $null
    $uninstallKey = $null
    $registry32GitKey = $null
    $registry32UninstallKey = $null
    $base64 = $null
    $base32 = $null
    $registryKindsValid = $false
    try {
        $base64 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $base32 = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry32
        )
        $gitKey = $base64.OpenSubKey('SOFTWARE\GitForWindows', $false)
        $uninstallKey = $base64.OpenSubKey(
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1',
            $false
        )
        $registry32GitKey = $base32.OpenSubKey('SOFTWARE\GitForWindows', $false)
        $registry32UninstallKey = $base32.OpenSubKey(
            'SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Git_is1',
            $false
        )
        if ($null -eq $gitKey -or $null -eq $uninstallKey) {
            return New-CddsiOperationResult -Operation 'ObserveGitForWindowsRegistry' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The machine Git installation receipt was not uniquely present.' -Data ([pscustomobject][ordered]@{
                SchemaVersion = 1
                RegistryStatus = 'Untrusted'
                InstallRootBindingToken = $null
                RegistryIdentityToken = $null
                CurrentVersion = $null
                ReasonCodes = @('GIT_INSTALL_REGISTRY_MISSING')
            })
        }

        $registryKindsValid = $true
        foreach ($kindCheck in @(
            [pscustomobject]@{
                Key = $gitKey
                Names = @('InstallPath', 'LibexecPath', 'CurrentVersion')
            },
            [pscustomobject]@{
                Key = $uninstallKey
                Names = @('DisplayName', 'DisplayVersion', 'Publisher', 'InstallLocation')
            }
        )) {
            foreach ($valueName in $kindCheck.Names) {
                try {
                    if (
                        $kindCheck.Key.GetValueKind($valueName) -ne
                        [Microsoft.Win32.RegistryValueKind]::String
                    ) {
                        $registryKindsValid = $false
                    }
                }
                catch {
                    $registryKindsValid = $false
                }
            }
        }

        $options = [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
        $installPath = $gitKey.GetValue('InstallPath', $null, $options)
        $libexecPath = $gitKey.GetValue('LibexecPath', $null, $options)
        $currentVersion = $gitKey.GetValue('CurrentVersion', $null, $options)
        $displayName = $uninstallKey.GetValue('DisplayName', $null, $options)
        $displayVersion = $uninstallKey.GetValue('DisplayVersion', $null, $options)
        $publisher = $uninstallKey.GetValue('Publisher', $null, $options)
        $installLocation = $uninstallKey.GetValue('InstallLocation', $null, $options)
    }
    catch {
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsRegistry' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALL_REGISTRY_OBSERVATION_FAILED' -MessageSafe 'The machine Git installation receipt could not be read safely.'
    }
    finally {
        foreach ($key in @($registry32UninstallKey, $registry32GitKey, $uninstallKey, $gitKey, $base32, $base64)) {
            if ($null -ne $key) { $key.Dispose() }
        }
    }

    $reasonCodes = New-Object System.Collections.Generic.List[string]
    if (-not $registryKindsValid) {
        $reasonCodes.Add('GIT_INSTALL_REGISTRY_VALUE_KIND_INVALID')
    }
    if ($null -ne $registry32GitKey -or $null -ne $registry32UninstallKey) {
        $reasonCodes.Add('GIT_INSTALL_REGISTRY_AMBIGUOUS')
    }
    foreach ($value in @($installPath, $libexecPath, $currentVersion, $displayName, $displayVersion, $publisher, $installLocation)) {
        if ($value -isnot [string] -or [string]::IsNullOrWhiteSpace($value)) {
            $reasonCodes.Add('GIT_INSTALL_REGISTRY_INVALID')
            break
        }
    }
    if ($reasonCodes.Count -eq 0) {
        try {
            $observedRoot = [System.IO.Path]::GetFullPath($installPath).TrimEnd('\')
            $observedLibexec = [System.IO.Path]::GetFullPath($libexecPath).TrimEnd('\')
            $observedInstallLocation = [System.IO.Path]::GetFullPath($installLocation).TrimEnd('\')
        }
        catch {
            $reasonCodes.Add('GIT_INSTALL_REGISTRY_INVALID')
        }
    }
    if (
        $reasonCodes.Count -eq 0 -and (
            -not [string]::Equals($observedRoot, $expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($observedInstallLocation, $expectedRoot, [StringComparison]::OrdinalIgnoreCase) -or
            -not [string]::Equals($observedLibexec, $expectedLibexec, [StringComparison]::OrdinalIgnoreCase)
        )
    ) {
        $reasonCodes.Add('GIT_INSTALL_REGISTRY_PATH_MISMATCH')
    }
    if (
        $reasonCodes.Count -eq 0 -and (
            $currentVersion -cne $ExpectedReceiptVersion -or
            $displayVersion -cne $ExpectedReceiptVersion -or
            $displayName -cne 'Git' -or
            $publisher -cne 'The Git Development Community'
        )
    ) {
        $reasonCodes.Add('GIT_INSTALL_REGISTRY_IDENTITY_MISMATCH')
    }

    $trusted = ($reasonCodes.Count -eq 0)
    $installRootBindingToken = if ($trusted) { Get-CddsiPathBindingToken -Path $expectedRoot } else { $null }
    return New-CddsiOperationResult -Operation 'ObserveGitForWindowsRegistry' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The machine Git installation receipt was observed.' -Data ([pscustomobject][ordered]@{
        SchemaVersion = 1
        RegistryStatus = if ($trusted) { 'Trusted' } else { 'Untrusted' }
        InstallRootBindingToken = $installRootBindingToken
        RegistryIdentityToken = if ($trusted) {
            Get-CddsiSupplyChainTextBindingToken -Text (
                '{0}|{1}|Git|The Git Development Community' -f
                $installRootBindingToken,
                $currentVersion
            )
        } else {
            $null
        }
        CurrentVersion = if ($trusted) { $currentVersion } else { $null }
        ReasonCodes = @($reasonCodes.ToArray())
    })
}

function Test-CddsiGitProtectedInstallPathSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$InstallRoot,
        [Parameter(Mandatory = $true)][string[]]$RequiredPaths
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    if (
        [string]::IsNullOrWhiteSpace($InstallRoot) -or
        -not [System.IO.Path]::IsPathRooted($InstallRoot) -or
        $RequiredPaths.Count -lt 1
    ) {
        throw 'Git install protection observation requires an exact root and required path set.'
    }

    $root = [System.IO.Path]::GetFullPath($InstallRoot).TrimEnd('\')
    $programFiles = [System.IO.Path]::GetFullPath(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    ).TrimEnd('\')
    $expectedRoot = [System.IO.Path]::GetFullPath((Join-Path $programFiles 'Git')).TrimEnd('\')
    $reasonCodes = New-Object System.Collections.Generic.List[string]
    if (-not [string]::Equals($root, $expectedRoot, [StringComparison]::OrdinalIgnoreCase)) {
        $reasonCodes.Add('GIT_INSTALL_LAYOUT_UNSUPPORTED')
    }
    if (Test-CddsiCurrentProcessElevated) {
        $reasonCodes.Add('GIT_OBSERVER_ELEVATED_UNSUPPORTED')
    }
    try {
        $drive = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($root))
        if ($drive.DriveType -ne [System.IO.DriveType]::Fixed -or $drive.DriveFormat -cne 'NTFS') {
            $reasonCodes.Add('GIT_INSTALL_VOLUME_UNSUPPORTED')
        }
    }
    catch {
        $reasonCodes.Add('GIT_INSTALL_VOLUME_UNSUPPORTED')
    }

    $paths = @($programFiles, $root) + @($RequiredPaths)
    $seen = @{}
    foreach ($candidate in $paths) {
        try {
            if ([string]::IsNullOrWhiteSpace($candidate) -or -not [System.IO.Path]::IsPathRooted($candidate)) {
                throw 'Invalid required path.'
            }
            $path = [System.IO.Path]::GetFullPath($candidate).TrimEnd('\')
            if (
                -not [string]::Equals($path, $programFiles, [StringComparison]::OrdinalIgnoreCase) -and
                -not [string]::Equals($path, $root, [StringComparison]::OrdinalIgnoreCase) -and
                -not $path.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)
            ) {
                throw 'Required path escapes the install root.'
            }
            $pathKey = $path.ToUpperInvariant()
            if ($seen.ContainsKey($pathKey)) { continue }
            $seen[$pathKey] = $true

            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reasonCodes.Add('GIT_INSTALL_REPARSE_UNSUPPORTED')
                continue
            }
            $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
            $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate(
                [Security.Principal.SecurityIdentifier]
            ).Value
            if ($script:CddsiGitProtectedWriterSids -cnotcontains $ownerSid) {
                $reasonCodes.Add('GIT_INSTALL_OWNER_UNTRUSTED')
            }
            $sddl = $acl.GetSecurityDescriptorSddlForm(
                [Security.AccessControl.AccessControlSections]::Access
            )
            if ($sddl -notmatch '^D:' -or $sddl -match 'NO_ACCESS_CONTROL') {
                $reasonCodes.Add('GIT_INSTALL_DACL_INVALID')
                continue
            }
            $rules = $acl.GetAccessRules(
                $true,
                $true,
                [Security.Principal.SecurityIdentifier]
            )
            foreach ($rule in @($rules)) {
                if ($rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow) {
                    continue
                }
                $rightsBytes = [BitConverter]::GetBytes([int]$rule.FileSystemRights)
                $rights = [BitConverter]::ToUInt32($rightsBytes, 0)
                if (($rights -band $script:CddsiGitDangerousAccessMask) -eq 0) {
                    continue
                }
                $sid = ([Security.Principal.SecurityIdentifier]$rule.IdentityReference).Value
                $creatorOwnerInheritOnly = (
                    $sid -ceq $script:CddsiGitCreatorOwnerSid -and
                    ($rule.PropagationFlags -band [Security.AccessControl.PropagationFlags]::InheritOnly) -ne 0
                )
                if (
                    $script:CddsiGitProtectedWriterSids -cnotcontains $sid -and
                    -not $creatorOwnerInheritOnly
                ) {
                    $reasonCodes.Add('GIT_INSTALL_USER_WRITABLE')
                    break
                }
            }
        }
        catch {
            $reasonCodes.Add('GIT_INSTALL_PROTECTION_OBSERVATION_FAILED')
        }
    }

    $distinctReasons = @($reasonCodes.ToArray() | Select-Object -Unique)
    $protected = ($distinctReasons.Count -eq 0)
    return New-CddsiOperationResult -Operation 'ObserveGitForWindowsInstallProtection' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Git installation path protection was observed.' -Data ([pscustomobject][ordered]@{
        SchemaVersion = 1
        ProtectionStatus = if ($protected) { 'Protected' } else { 'Untrusted' }
        InstallRootBindingToken = if ($protected) { Get-CddsiPathBindingToken -Path $root } else { $null }
        RequiredPathCount = @($seen.Keys).Count
        ReasonCodes = $distinctReasons
    })
}

function Get-CddsiGitForWindowsPrivateDllObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$BinPath,
        [Parameter(Mandatory = $true)][string[]]$ExpectedPaths
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    $programFiles = [System.IO.Path]::GetFullPath(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    ).TrimEnd('\')
    $expectedBin = [System.IO.Path]::GetFullPath(
        (Join-Path $programFiles 'Git\mingw64\bin')
    ).TrimEnd('\')
    if (
        [string]::IsNullOrWhiteSpace($BinPath) -or
        -not [System.IO.Path]::IsPathRooted($BinPath) -or
        -not [string]::Equals(
            [System.IO.Path]::GetFullPath($BinPath).TrimEnd('\'),
            $expectedBin,
            [StringComparison]::OrdinalIgnoreCase
        )
    ) {
        throw 'Git private DLL observation requires the exact protected Git bin directory.'
    }

    $newData = {
        param(
            [string]$IdentityStatus,
            [AllowNull()][string]$IdentityToken,
            [int]$DependencyCount,
            [string[]]$ReasonCodes
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            IdentityStatus = $IdentityStatus
            DependencyIdentityToken = $IdentityToken
            DependencyCount = $DependencyCount
            ReasonCodes = @($ReasonCodes)
        }
    }

    $reasonCodes = New-Object System.Collections.Generic.List[string]
    $expectedSet = @{}
    if ($ExpectedPaths.Count -lt 5 -or $ExpectedPaths.Count -gt 256) {
        $reasonCodes.Add('GIT_PRIVATE_DLL_SET_INVALID')
    }
    foreach ($candidate in @($ExpectedPaths)) {
        try {
            if (
                [string]::IsNullOrWhiteSpace($candidate) -or
                -not [System.IO.Path]::IsPathRooted($candidate)
            ) {
                throw 'Invalid DLL path.'
            }
            $path = [System.IO.Path]::GetFullPath($candidate)
            $parent = [System.IO.Path]::GetDirectoryName($path).TrimEnd('\')
            $name = [System.IO.Path]::GetFileName($path)
            if (
                -not [string]::Equals($parent, $expectedBin, [StringComparison]::OrdinalIgnoreCase) -or
                $name -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,126}\.dll$'
            ) {
                throw 'DLL path escaped the exact bin directory.'
            }
            $key = $name.ToUpperInvariant()
            if ($expectedSet.ContainsKey($key)) {
                throw 'Duplicate DLL name.'
            }
            $expectedSet[$key] = $path
        }
        catch {
            $reasonCodes.Add('GIT_PRIVATE_DLL_SET_INVALID')
            break
        }
    }

    foreach ($requiredName in @(
        'libiconv-2.dll',
        'libintl-8.dll',
        'libpcre2-8-0.dll',
        'libwinpthread-1.dll',
        'zlib1.dll'
    )) {
        if (-not $expectedSet.ContainsKey($requiredName.ToUpperInvariant())) {
            $reasonCodes.Add('GIT_PRIVATE_DLL_REQUIRED_MISSING')
        }
    }
    if ($reasonCodes.Count -gt 0) {
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsPrivateDlls' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git private dependency set was rejected.' -Data (
            & $newData 'Untrusted' $null 0 @($reasonCodes.ToArray() | Select-Object -Unique)
        )
    }

    try {
        $actualItems = @(
            Get-ChildItem -LiteralPath $expectedBin -Filter '*.dll' -File -Force -ErrorAction Stop
        )
        if ($actualItems.Count -lt 5 -or $actualItems.Count -gt 256) {
            throw 'Git private DLL count was outside the supported bound.'
        }
        $actualSet = @{}
        foreach ($actualItem in $actualItems) {
            $actualPath = [System.IO.Path]::GetFullPath([string]$actualItem.FullName)
            $actualParent = [System.IO.Path]::GetDirectoryName($actualPath).TrimEnd('\')
            $actualName = [System.IO.Path]::GetFileName($actualPath)
            if (
                -not [string]::Equals($actualParent, $expectedBin, [StringComparison]::OrdinalIgnoreCase) -or
                $actualName -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,126}\.dll$' -or
                $actualSet.ContainsKey($actualName.ToUpperInvariant())
            ) {
                throw 'Git private DLL enumeration was invalid.'
            }
            $actualSet[$actualName.ToUpperInvariant()] = $actualPath
        }
        if (
            $actualSet.Count -ne $expectedSet.Count -or
            @($expectedSet.Keys | Where-Object { -not $actualSet.ContainsKey($_) }).Count -ne 0
        ) {
            $data = & $newData 'Untrusted' $null 0 @('GIT_PRIVATE_DLL_SET_CHANGED')
            return New-CddsiOperationResult -Operation 'ObserveGitForWindowsPrivateDlls' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git private dependency set changed during observation.' -Data $data
        }

        $orderedNames = [string[]]@($expectedSet.Keys)
        [Array]::Sort($orderedNames, [StringComparer]::OrdinalIgnoreCase)
        $identityText = New-Object System.Text.StringBuilder
        [void]$identityText.Append((Get-CddsiPathBindingToken -Path $expectedBin))
        foreach ($nameKey in $orderedNames) {
            $path = $expectedSet[$nameKey]
            $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
            if (
                $item.PSIsContainer -or
                [long]$item.Length -lt 1 -or
                [long]$item.Length -gt $script:CddsiGitExecutableMaximumBytes -or
                ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            ) {
                throw 'Git private DLL type, size or path was invalid.'
            }
            $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            if ($hash -notmatch '^[a-f0-9]{64}$') {
                throw 'Git private DLL hash was invalid.'
            }
            [void]$identityText.Append('|')
            [void]$identityText.Append(([System.IO.Path]::GetFileName($path)).ToLowerInvariant())
            [void]$identityText.Append('|')
            [void]$identityText.Append(([long]$item.Length).ToString([Globalization.CultureInfo]::InvariantCulture))
            [void]$identityText.Append('|')
            [void]$identityText.Append($hash)
        }
        $identityToken = Get-CddsiSupplyChainTextBindingToken -Text $identityText.ToString()
    }
    catch {
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsPrivateDlls' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_PRIVATE_DLL_OBSERVATION_FAILED' -MessageSafe 'The Git private dependency set could not be observed safely.'
    }

    return New-CddsiOperationResult -Operation 'ObserveGitForWindowsPrivateDlls' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The protected Git private dependency set was observed.' -Data (
        & $newData 'Trusted' $identityToken $expectedSet.Count @()
    )
}

function Get-CddsiGitForWindowsSignedComponentObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ComponentPath,
        [Parameter(Mandatory = $true)][ValidateSet('PathLauncher', 'Core', 'HttpsTransport')][string]$ComponentRole
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    if ([string]::IsNullOrWhiteSpace($ComponentPath) -or -not [System.IO.Path]::IsPathRooted($ComponentPath)) {
        throw 'Git component observation requires an exact absolute component path.'
    }
    $path = [System.IO.Path]::GetFullPath($ComponentPath)
    $expectedFileName = if ($ComponentRole -ceq 'HttpsTransport') { 'git-remote-https.exe' } else { 'git.exe' }
    if (-not [string]::Equals([System.IO.Path]::GetFileName($path), $expectedFileName, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Git component role and file name do not match.'
    }

    try {
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (
            $item.PSIsContainer -or
            [long]$item.Length -lt 1 -or
            [long]$item.Length -gt $script:CddsiGitExecutableMaximumBytes -or
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw 'Git component size, type or path is invalid.'
        }
        $headerLength = [int][Math]::Min([long]4096, [long]$item.Length)
        $header = New-Object byte[] $headerLength
        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $offset = 0
            while ($offset -lt $headerLength) {
                $read = $stream.Read($header, $offset, $headerLength - $offset)
                if ($read -le 0) { break }
                $offset += $read
            }
        }
        finally {
            $stream.Dispose()
        }
        if ($offset -ne $headerLength) { throw 'Git component header was truncated.' }
        $peMachine = ConvertFrom-CddsiGitPeHeader -HeaderBytes $header -ImageLength ([long]$item.Length)
        $artifactSha256 = (Get-FileHash -LiteralPath $path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        $versionInfo = $item.VersionInfo
    }
    catch {
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsSignedComponent' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_COMPONENT_OBSERVATION_FAILED' -MessageSafe 'A required Git installation component could not be observed safely.'
    }

    $fileDescription = if ($null -eq $versionInfo.FileDescription) { '' } else { $versionInfo.FileDescription.Trim() }
    $productName = if ($null -eq $versionInfo.ProductName) { '' } else { $versionInfo.ProductName.Trim() }
    $companyName = if ($null -eq $versionInfo.CompanyName) { '' } else { $versionInfo.CompanyName.Trim() }
    $originalFilename = if ($null -eq $versionInfo.OriginalFilename) { '' } else { $versionInfo.OriginalFilename.Trim() }
    $fileVersion = if ($null -eq $versionInfo.FileVersion) { '' } else { $versionInfo.FileVersion.Trim() }
    $productVersion = if ($null -eq $versionInfo.ProductVersion) { '' } else { $versionInfo.ProductVersion.Trim() }
    $versionObservation = ConvertFrom-CddsiGitVersionProbeResult -ProbeResult ([pscustomobject][ordered]@{
        SchemaVersion = 1
        Started = $true
        TimedOut = $false
        TerminationComplete = $true
        OutputTruncated = $false
        ExitCode = 0
        StdOut = 'git version ' + $fileVersion
        StdErr = ''
    })
    $authenticodeStatus = [string]$signature.Status
    $signerSubject = if ($null -eq $signature.SignerCertificate) { '' } else { [string]$signature.SignerCertificate.Subject }
    $signerThumbprint = if ($null -eq $signature.SignerCertificate) { '' } else { ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant() }
    $reasonCodes = New-Object System.Collections.Generic.List[string]
    if ($peMachine -cne 'x64') { $reasonCodes.Add('GIT_COMPONENT_ARCHITECTURE_UNSUPPORTED') }
    if ($authenticodeStatus -cne 'Valid' -or $null -eq $signature.TimeStamperCertificate) { $reasonCodes.Add('GIT_COMPONENT_AUTHENTICODE_INVALID') }
    if ($signerSubject -notmatch $script:CddsiGitExecutableSignerSubjectPattern -or $signerThumbprint -notmatch '^[a-f0-9]{40}$') {
        $reasonCodes.Add('GIT_COMPONENT_SIGNER_UNTRUSTED')
    }
    if (
        $fileDescription -cne 'Git for Windows' -or
        $productName -cne 'Git' -or
        $companyName -cne 'The Git Development Community' -or
        $originalFilename -cne 'git.exe'
    ) {
        $reasonCodes.Add('GIT_COMPONENT_IDENTITY_MISMATCH')
    }
    if (-not $versionObservation.Valid -or $productVersion -cne $fileVersion) {
        $reasonCodes.Add('GIT_COMPONENT_VERSION_INVALID')
    }

    $pathBindingToken = Get-CddsiPathBindingToken -Path $path
    $trusted = ($reasonCodes.Count -eq 0)
    $fileIdentityToken = Get-CddsiSupplyChainTextBindingToken -Text (
        '{0}|{1}|{2}|{3}|{4}|{5}' -f
        $ComponentRole,
        $pathBindingToken,
        $artifactSha256,
        [long]$item.Length,
        $fileVersion,
        $signerThumbprint
    )
    return New-CddsiOperationResult -Operation 'ObserveGitForWindowsSignedComponent' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'A required Git installation component was observed.' -Data ([pscustomobject][ordered]@{
        SchemaVersion = 1
        ComponentRole = $ComponentRole
        PathBindingToken = $pathBindingToken
        FileIdentityToken = $fileIdentityToken
        ArtifactSha256 = $artifactSha256
        ArtifactSizeBytes = [long]$item.Length
        FileVersion = if ($versionObservation.Valid) { $versionObservation.Version } else { $null }
        PeMachine = $peMachine
        AuthenticodeStatus = $authenticodeStatus
        SignerThumbprint = if ($signerThumbprint -match '^[a-f0-9]{40}$') { $signerThumbprint } else { $null }
        IdentityStatus = if ($trusted) { 'Trusted' } else { 'Untrusted' }
        ReasonCodes = @($reasonCodes.ToArray())
    })
}

function Resolve-CddsiGitExecutablePathSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$CandidatePaths,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ShadowPaths
    )

    $canonicalPaths = New-Object System.Collections.Generic.List[string]
    $seen = @{}
    foreach ($path in @($CandidatePaths)) {
        if (
            [string]::IsNullOrWhiteSpace($path) -or
            $path.IndexOfAny([char[]]@('*', '?', [char]0)) -ge 0 -or
            $path -notmatch '^[A-Za-z]:\\' -or
            -not [System.IO.Path]::IsPathRooted($path) -or
            -not [string]::Equals([System.IO.Path]::GetFileName($path), 'git.exe', [StringComparison]::OrdinalIgnoreCase)
        ) {
            return [pscustomobject][ordered]@{
                SchemaVersion = 1; Status = 'INVALID'; CandidateCount = 0
                CanonicalPaths = @(); ReasonCodes = @('GIT_PATH_INVALID')
            }
        }
        try {
            $canonical = [System.IO.Path]::GetFullPath($path)
        }
        catch {
            return [pscustomobject][ordered]@{
                SchemaVersion = 1; Status = 'INVALID'; CandidateCount = 0
                CanonicalPaths = @(); ReasonCodes = @('GIT_PATH_INVALID')
            }
        }
        $key = $canonical.ToUpperInvariant()
        if (-not $seen.ContainsKey($key)) {
            $seen[$key] = $true
            $canonicalPaths.Add($canonical)
        }
    }

    foreach ($path in @($ShadowPaths)) {
        if (
            [string]::IsNullOrWhiteSpace($path) -or
            $path.IndexOfAny([char[]]@('*', '?', [char]0)) -ge 0 -or
            $path -notmatch '^[A-Za-z]:\\' -or
            -not [System.IO.Path]::IsPathRooted($path) -or
            ([System.IO.Path]::GetFileName($path).ToLowerInvariant()) -notmatch '^git\.[a-z0-9]{1,8}$' -or
            [string]::Equals([System.IO.Path]::GetFileName($path), 'git.exe', [StringComparison]::OrdinalIgnoreCase)
        ) {
            return [pscustomobject][ordered]@{
                SchemaVersion = 1; Status = 'INVALID'; CandidateCount = 0
                CanonicalPaths = @(); ReasonCodes = @('GIT_PATH_INVALID')
            }
        }
    }

    $paths = @($canonicalPaths.ToArray())
    if (@($ShadowPaths).Count -gt 0) {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; Status = 'SHADOWED'; CandidateCount = $paths.Count
            CanonicalPaths = $paths; ReasonCodes = @('GIT_PATH_SHADOWED')
        }
    }
    if ($paths.Count -eq 0) {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; Status = 'MISSING'; CandidateCount = 0
            CanonicalPaths = @(); ReasonCodes = @('GIT_MISSING')
        }
    }
    if ($paths.Count -gt 1) {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; Status = 'AMBIGUOUS'; CandidateCount = $paths.Count
            CanonicalPaths = @(); ReasonCodes = @('GIT_PATH_AMBIGUOUS')
        }
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1; Status = 'READY'; CandidateCount = 1
        CanonicalPaths = $paths; ReasonCodes = @()
    }
}

function New-CddsiGitVersionProbeStartInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][string]$SystemRootPath,
        [Parameter(Mandatory = $true)][string]$ProductTempPath
    )

    foreach ($path in @($ExecutablePath, $SystemRootPath, $ProductTempPath)) {
        if ([string]::IsNullOrWhiteSpace($path) -or -not [System.IO.Path]::IsPathRooted($path)) {
            throw 'Git version probe paths must be explicit absolute paths.'
        }
    }
    $executable = [System.IO.Path]::GetFullPath($ExecutablePath)
    $systemRoot = [System.IO.Path]::GetFullPath($SystemRootPath)
    $productTemp = [System.IO.Path]::GetFullPath($ProductTempPath)
    if (-not [string]::Equals([System.IO.Path]::GetFileName($executable), 'git.exe', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Git version probe requires the exact git.exe executable.'
    }

    $startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $executable
    $startInfo.Arguments = '--version'
    $startInfo.WorkingDirectory = [System.IO.Path]::GetDirectoryName($executable)
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.LoadUserProfile = $false
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
    $startInfo.StandardOutputEncoding = $utf8
    $startInfo.StandardErrorEncoding = $utf8
    $startInfo.EnvironmentVariables.Clear()
    $startInfo.EnvironmentVariables['SystemRoot'] = $systemRoot
    $startInfo.EnvironmentVariables['WINDIR'] = $systemRoot
    $startInfo.EnvironmentVariables['ComSpec'] = Join-Path $systemRoot 'System32\cmd.exe'
    $startInfo.EnvironmentVariables['HOME'] = $productTemp
    $startInfo.EnvironmentVariables['USERPROFILE'] = $productTemp
    $startInfo.EnvironmentVariables['XDG_CONFIG_HOME'] = $productTemp
    $startInfo.EnvironmentVariables['TEMP'] = $productTemp
    $startInfo.EnvironmentVariables['TMP'] = $productTemp
    $startInfo.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] = '1'
    $startInfo.EnvironmentVariables['GIT_CONFIG_SYSTEM'] = 'NUL'
    $startInfo.EnvironmentVariables['GIT_CONFIG_GLOBAL'] = 'NUL'
    $startInfo.EnvironmentVariables['GIT_CONFIG_COUNT'] = '0'
    $startInfo.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
    $startInfo.EnvironmentVariables['GCM_INTERACTIVE'] = 'Never'
    $startInfo.EnvironmentVariables['LC_ALL'] = 'C'
    return $startInfo
}

function Initialize-CddsiD027GitProbeRunnerType {
    [CmdletBinding()]
    param()

    if ($null -ne ('Cddsi.D027.GitProbeRunner' -as [type])) { return }
    Add-Type -TypeDefinition @'
using System;
using System.Collections;
using System.ComponentModel;
using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;

namespace Cddsi.D027 {
    public sealed class GitProbeRunResult {
        public bool Started;
        public bool TimedOut;
        public bool TerminationComplete;
        public bool OutputTruncated;
        public bool JobAssigned;
        public bool ProcessCountExact;
        public int ExitCode;
        public string StdOut;
        public string StdErr;
    }

    public static class GitProbeRunner {
        private const uint CREATE_SUSPENDED = 0x00000004;
        private const uint CREATE_UNICODE_ENVIRONMENT = 0x00000400;
        private const uint EXTENDED_STARTUPINFO_PRESENT = 0x00080000;
        private const uint DETACHED_PROCESS = 0x00000008;
        private const uint STARTF_USESTDHANDLES = 0x00000100;
        private const uint HANDLE_FLAG_INHERIT = 0x00000001;
        private const uint THREAD_TERMINATE = 0x00000001;
        private const uint JOB_OBJECT_LIMIT_ACTIVE_PROCESS = 0x00000008;
        private const uint JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION = 0x00000400;
        private const uint JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE = 0x00002000;
        private const int JobObjectBasicAccountingInformation = 1;
        private const int JobObjectExtendedLimitInformation = 9;
        private const int PROC_THREAD_ATTRIBUTE_HANDLE_LIST = 0x00020002;
        private const uint WAIT_OBJECT_0 = 0x00000000;
        private const uint WAIT_TIMEOUT = 0x00000102;
        private const uint INFINITE = 0xffffffff;
        private const int ERROR_BROKEN_PIPE = 109;
        private const int ERROR_OPERATION_ABORTED = 995;
        private const int ERROR_NOT_FOUND = 1168;

        [StructLayout(LayoutKind.Sequential)]
        private struct SECURITY_ATTRIBUTES {
            internal int nLength;
            internal IntPtr lpSecurityDescriptor;
            [MarshalAs(UnmanagedType.Bool)] internal bool bInheritHandle;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFO {
            internal int cb;
            internal IntPtr lpReserved;
            internal IntPtr lpDesktop;
            internal IntPtr lpTitle;
            internal int dwX;
            internal int dwY;
            internal int dwXSize;
            internal int dwYSize;
            internal int dwXCountChars;
            internal int dwYCountChars;
            internal int dwFillAttribute;
            internal uint dwFlags;
            internal short wShowWindow;
            internal short cbReserved2;
            internal IntPtr lpReserved2;
            internal IntPtr hStdInput;
            internal IntPtr hStdOutput;
            internal IntPtr hStdError;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct STARTUPINFOEX {
            internal STARTUPINFO StartupInfo;
            internal IntPtr lpAttributeList;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct PROCESS_INFORMATION {
            internal IntPtr hProcess;
            internal IntPtr hThread;
            internal uint dwProcessId;
            internal uint dwThreadId;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_LIMIT_INFORMATION {
            internal long PerProcessUserTimeLimit;
            internal long PerJobUserTimeLimit;
            internal uint LimitFlags;
            internal UIntPtr MinimumWorkingSetSize;
            internal UIntPtr MaximumWorkingSetSize;
            internal uint ActiveProcessLimit;
            internal UIntPtr Affinity;
            internal uint PriorityClass;
            internal uint SchedulingClass;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct IO_COUNTERS {
            internal ulong ReadOperationCount;
            internal ulong WriteOperationCount;
            internal ulong OtherOperationCount;
            internal ulong ReadTransferCount;
            internal ulong WriteTransferCount;
            internal ulong OtherTransferCount;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_EXTENDED_LIMIT_INFORMATION {
            internal JOBOBJECT_BASIC_LIMIT_INFORMATION BasicLimitInformation;
            internal IO_COUNTERS IoInfo;
            internal UIntPtr ProcessMemoryLimit;
            internal UIntPtr JobMemoryLimit;
            internal UIntPtr PeakProcessMemoryUsed;
            internal UIntPtr PeakJobMemoryUsed;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct JOBOBJECT_BASIC_ACCOUNTING_INFORMATION {
            internal long TotalUserTime;
            internal long TotalKernelTime;
            internal long ThisPeriodTotalUserTime;
            internal long ThisPeriodTotalKernelTime;
            internal uint TotalPageFaultCount;
            internal uint TotalProcesses;
            internal uint ActiveProcesses;
            internal uint TotalTerminatedProcesses;
        }

        private sealed class Capture {
            internal readonly byte[] Bytes;
            internal int Count;
            internal volatile bool Truncated;
            internal volatile int NativeThreadId;
            internal Exception Error;
            internal Capture(int capacity) { Bytes = new byte[capacity]; }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern IntPtr CreateJobObject(IntPtr attributes, string name);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetInformationJobObject(
            IntPtr job, int informationClass, IntPtr information, uint informationLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool AssignProcessToJobObject(IntPtr job, IntPtr process);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateJobObject(IntPtr job, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool QueryInformationJobObject(
            IntPtr job, int informationClass, IntPtr information,
            uint informationLength, IntPtr returnLength);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreatePipe(
            out IntPtr readPipe, out IntPtr writePipe,
            ref SECURITY_ATTRIBUTES attributes, uint size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool SetHandleInformation(
            IntPtr handle, uint mask, uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint ResumeThread(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool TerminateProcess(IntPtr process, uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint WaitForSingleObject(IntPtr handle, uint milliseconds);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetExitCodeProcess(IntPtr process, out uint exitCode);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool ReadFile(
            IntPtr handle, byte[] buffer, uint bytesToRead,
            out uint bytesRead, IntPtr overlapped);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CloseHandle(IntPtr handle);

        [DllImport("kernel32.dll", SetLastError = false)]
        private static extern uint GetCurrentThreadId();

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern IntPtr OpenThread(
            uint desiredAccess,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandle,
            uint threadId);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CancelSynchronousIo(IntPtr thread);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool InitializeProcThreadAttributeList(
            IntPtr attributeList, int attributeCount, uint flags, ref UIntPtr size);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool UpdateProcThreadAttribute(
            IntPtr attributeList, uint flags, IntPtr attribute,
            IntPtr value, UIntPtr size, IntPtr previousValue, IntPtr returnSize);

        [DllImport("kernel32.dll", SetLastError = false)]
        private static extern void DeleteProcThreadAttributeList(IntPtr attributeList);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool CreateProcessW(
            string applicationName, StringBuilder commandLine,
            IntPtr processAttributes, IntPtr threadAttributes,
            [MarshalAs(UnmanagedType.Bool)] bool inheritHandles,
            uint creationFlags, IntPtr environment, string currentDirectory,
            ref STARTUPINFOEX startupInfo, out PROCESS_INFORMATION processInformation);

        private static void Require(bool condition, string message) {
            if (!condition) {
                throw new Win32Exception(Marshal.GetLastWin32Error(), message);
            }
        }

        private static void CreateOwnedPipe(
            ref IntPtr ownedRead, ref IntPtr ownedWrite,
            ref SECURITY_ATTRIBUTES attributes, string message) {
            IntPtr createdRead;
            IntPtr createdWrite;
            if (!CreatePipe(out createdRead, out createdWrite, ref attributes, 0)) {
                int error = Marshal.GetLastWin32Error();
                throw new Win32Exception(error, message);
            }
            ownedRead = createdRead;
            ownedWrite = createdWrite;
        }

        private static IntPtr CreateConfiguredJob() {
            IntPtr job = CreateJobObject(IntPtr.Zero, null);
            if (job == IntPtr.Zero) throw new Win32Exception(Marshal.GetLastWin32Error(), "Git probe job creation failed.");
            IntPtr pointer = IntPtr.Zero;
            try {
                var limits = new JOBOBJECT_EXTENDED_LIMIT_INFORMATION();
                limits.BasicLimitInformation.LimitFlags =
                    JOB_OBJECT_LIMIT_ACTIVE_PROCESS |
                    JOB_OBJECT_LIMIT_DIE_ON_UNHANDLED_EXCEPTION |
                    JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
                limits.BasicLimitInformation.ActiveProcessLimit = 1;
                int size = Marshal.SizeOf(typeof(JOBOBJECT_EXTENDED_LIMIT_INFORMATION));
                pointer = Marshal.AllocHGlobal(size);
                Marshal.StructureToPtr(limits, pointer, false);
                if (!SetInformationJobObject(job, JobObjectExtendedLimitInformation, pointer, (uint)size)) {
                    int error = Marshal.GetLastWin32Error();
                    throw new Win32Exception(error, "Git probe job policy failed.");
                }
                return job;
            }
            catch {
                CloseHandle(job);
                throw;
            }
            finally {
                if (pointer != IntPtr.Zero) Marshal.FreeHGlobal(pointer);
            }
        }

        private static JOBOBJECT_BASIC_ACCOUNTING_INFORMATION QueryAccounting(IntPtr job) {
            int size = Marshal.SizeOf(typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
            IntPtr pointer = Marshal.AllocHGlobal(size);
            try {
                Require(
                    QueryInformationJobObject(
                        job, JobObjectBasicAccountingInformation,
                        pointer, (uint)size, IntPtr.Zero),
                    "Git probe job accounting failed.");
                return (JOBOBJECT_BASIC_ACCOUNTING_INFORMATION)Marshal.PtrToStructure(
                    pointer, typeof(JOBOBJECT_BASIC_ACCOUNTING_INFORMATION));
            }
            finally {
                Marshal.FreeHGlobal(pointer);
            }
        }

        private static bool WaitForQuiescence(IntPtr job, int milliseconds) {
            Stopwatch clock = Stopwatch.StartNew();
            while (true) {
                if (QueryAccounting(job).ActiveProcesses == 0) return true;
                int remaining = milliseconds - (int)Math.Min(Int32.MaxValue, clock.ElapsedMilliseconds);
                if (remaining <= 0) return false;
                Thread.Sleep(10);
            }
        }

        private static int RemainingMilliseconds(Stopwatch clock, int maximumMilliseconds) {
            long remaining = maximumMilliseconds - clock.ElapsedMilliseconds;
            if (remaining <= 0) return 0;
            if (remaining >= Int32.MaxValue) return Int32.MaxValue;
            return (int)remaining;
        }

        private static bool CancelCaptureRead(Capture capture) {
            int threadId = capture.NativeThreadId;
            if (threadId == 0) return false;
            IntPtr thread = OpenThread(
                THREAD_TERMINATE,
                false,
                unchecked((uint)threadId)
            );
            if (thread == IntPtr.Zero) return false;
            try {
                if (CancelSynchronousIo(thread)) return true;
                return Marshal.GetLastWin32Error() == ERROR_NOT_FOUND;
            }
            finally {
                CloseHandle(thread);
            }
        }

        private static IntPtr BuildEnvironmentBlock(IDictionary environment) {
            var keys = new string[environment.Count];
            int index = 0;
            foreach (DictionaryEntry entry in environment) {
                string key = Convert.ToString(entry.Key);
                string value = Convert.ToString(entry.Value);
                if (String.IsNullOrEmpty(key) || key.IndexOf('=') >= 0 || key.IndexOf('\0') >= 0 || value.IndexOf('\0') >= 0) {
                    throw new InvalidOperationException("Git probe environment entry was invalid.");
                }
                keys[index++] = key;
            }
            Array.Sort(keys, StringComparer.OrdinalIgnoreCase);
            var builder = new StringBuilder();
            foreach (string key in keys) {
                builder.Append(key);
                builder.Append('=');
                builder.Append(Convert.ToString(environment[key]));
                builder.Append('\0');
            }
            builder.Append('\0');
            return Marshal.StringToHGlobalUni(builder.ToString());
        }

        private static void DrainPipe(IntPtr pipe, Capture capture) {
            byte[] scratch = new byte[512];
            capture.NativeThreadId = unchecked((int)GetCurrentThreadId());
            try {
                while (true) {
                    uint read;
                    bool ok = ReadFile(pipe, scratch, (uint)scratch.Length, out read, IntPtr.Zero);
                    if (!ok) {
                        int error = Marshal.GetLastWin32Error();
                        if (error == ERROR_BROKEN_PIPE || error == ERROR_OPERATION_ABORTED) return;
                        throw new Win32Exception(error, "Git probe output read failed.");
                    }
                    if (read == 0) return;
                    int remaining = capture.Bytes.Length - capture.Count;
                    int copy = Math.Min(remaining, (int)read);
                    if (copy > 0) {
                        Buffer.BlockCopy(scratch, 0, capture.Bytes, capture.Count, copy);
                        capture.Count += copy;
                    }
                    if (copy < (int)read) capture.Truncated = true;
                }
            }
            catch (Exception error) {
                capture.Error = error;
            }
            finally {
                CloseHandle(pipe);
            }
        }

        private static void Close(ref IntPtr handle) {
            if (handle != IntPtr.Zero && handle != new IntPtr(-1)) {
                if (CloseHandle(handle)) handle = IntPtr.Zero;
            }
        }

        public static GitProbeRunResult Run(
            string executable, string workingDirectory, IDictionary environment,
            int timeoutMilliseconds, int capacityPerStream, int cleanupMilliseconds) {
            if (
                String.IsNullOrWhiteSpace(executable) ||
                String.IsNullOrWhiteSpace(workingDirectory) ||
                environment == null ||
                timeoutMilliseconds < 1 ||
                capacityPerStream < 1 ||
                cleanupMilliseconds < 1 ||
                executable.IndexOf('\0') >= 0 ||
                executable.IndexOf('"') >= 0
            ) {
                throw new ArgumentException("Git probe runner arguments were invalid.");
            }

            IntPtr job = IntPtr.Zero;
            IntPtr stdinRead = IntPtr.Zero;
            IntPtr stdinWrite = IntPtr.Zero;
            IntPtr stdoutRead = IntPtr.Zero;
            IntPtr stdoutWrite = IntPtr.Zero;
            IntPtr stderrRead = IntPtr.Zero;
            IntPtr stderrWrite = IntPtr.Zero;
            IntPtr attributeList = IntPtr.Zero;
            IntPtr attributeHandles = IntPtr.Zero;
            IntPtr environmentBlock = IntPtr.Zero;
            var processInfo = new PROCESS_INFORMATION();
            bool attributeListInitialized = false;
            bool processCreated = false;
            bool jobAssigned = false;
            Thread stdoutThread = null;
            Thread stderrThread = null;
            bool stdoutThreadStarted = false;
            bool stderrThreadStarted = false;
            var stdout = new Capture(capacityPerStream);
            var stderr = new Capture(capacityPerStream);
            try {
                var attributes = new SECURITY_ATTRIBUTES();
                attributes.nLength = Marshal.SizeOf(typeof(SECURITY_ATTRIBUTES));
                attributes.bInheritHandle = true;
                CreateOwnedPipe(ref stdinRead, ref stdinWrite, ref attributes, "Git probe stdin pipe creation failed.");
                CreateOwnedPipe(ref stdoutRead, ref stdoutWrite, ref attributes, "Git probe stdout pipe creation failed.");
                CreateOwnedPipe(ref stderrRead, ref stderrWrite, ref attributes, "Git probe stderr pipe creation failed.");
                Require(SetHandleInformation(stdinWrite, HANDLE_FLAG_INHERIT, 0), "Git probe stdin inheritance policy failed.");
                Require(SetHandleInformation(stdoutRead, HANDLE_FLAG_INHERIT, 0), "Git probe stdout inheritance policy failed.");
                Require(SetHandleInformation(stderrRead, HANDLE_FLAG_INHERIT, 0), "Git probe stderr inheritance policy failed.");

                UIntPtr attributeSize = UIntPtr.Zero;
                InitializeProcThreadAttributeList(IntPtr.Zero, 1, 0, ref attributeSize);
                if (attributeSize == UIntPtr.Zero || attributeSize.ToUInt64() > Int32.MaxValue) {
                    throw new InvalidOperationException("Git probe attribute list size was invalid.");
                }
                attributeList = Marshal.AllocHGlobal((int)attributeSize.ToUInt64());
                Require(InitializeProcThreadAttributeList(attributeList, 1, 0, ref attributeSize), "Git probe attribute list initialization failed.");
                attributeListInitialized = true;
                attributeHandles = Marshal.AllocHGlobal(IntPtr.Size * 3);
                Marshal.WriteIntPtr(attributeHandles, 0, stdinRead);
                Marshal.WriteIntPtr(attributeHandles, IntPtr.Size, stdoutWrite);
                Marshal.WriteIntPtr(attributeHandles, IntPtr.Size * 2, stderrWrite);
                Require(
                    UpdateProcThreadAttribute(
                        attributeList, 0, new IntPtr(PROC_THREAD_ATTRIBUTE_HANDLE_LIST),
                        attributeHandles, new UIntPtr((uint)(IntPtr.Size * 3)),
                        IntPtr.Zero, IntPtr.Zero),
                    "Git probe inherited handle allowlist failed.");

                var startup = new STARTUPINFOEX();
                startup.StartupInfo.cb = Marshal.SizeOf(typeof(STARTUPINFOEX));
                startup.StartupInfo.dwFlags = STARTF_USESTDHANDLES;
                startup.StartupInfo.hStdInput = stdinRead;
                startup.StartupInfo.hStdOutput = stdoutWrite;
                startup.StartupInfo.hStdError = stderrWrite;
                startup.lpAttributeList = attributeList;
                environmentBlock = BuildEnvironmentBlock(environment);
                job = CreateConfiguredJob();
                var commandLine = new StringBuilder("\"" + executable + "\" --version");
                PROCESS_INFORMATION createdProcessInfo;
                if (!CreateProcessW(
                        executable, commandLine, IntPtr.Zero, IntPtr.Zero, true,
                        CREATE_SUSPENDED | CREATE_UNICODE_ENVIRONMENT |
                        EXTENDED_STARTUPINFO_PRESENT | DETACHED_PROCESS,
                        environmentBlock, workingDirectory, ref startup, out createdProcessInfo)) {
                    int processCreationError = Marshal.GetLastWin32Error();
                    throw new Win32Exception(processCreationError, "Git probe process creation failed.");
                }
                processInfo = createdProcessInfo;
                processCreated = true;
                Close(ref stdinRead);
                Close(ref stdoutWrite);
                Close(ref stderrWrite);
                Close(ref stdinWrite);

                Require(AssignProcessToJobObject(job, processInfo.hProcess), "Git probe job assignment failed.");
                jobAssigned = true;
                IntPtr stdoutDrainPipe = stdoutRead;
                IntPtr stderrDrainPipe = stderrRead;
                stdoutThread = new Thread(delegate() { DrainPipe(stdoutDrainPipe, stdout); });
                stderrThread = new Thread(delegate() { DrainPipe(stderrDrainPipe, stderr); });
                stdoutThread.IsBackground = true;
                stderrThread.IsBackground = true;
                try {
                    stdoutThread.Start();
                    stdoutThreadStarted = true;
                    stdoutRead = IntPtr.Zero;
                    stderrThread.Start();
                    stderrThreadStarted = true;
                    stderrRead = IntPtr.Zero;
                }
                catch {
                    if (!stdoutThreadStarted) stdoutRead = stdoutDrainPipe;
                    if (!stderrThreadStarted) stderrRead = stderrDrainPipe;
                    throw;
                }
                if (ResumeThread(processInfo.hThread) == 0xffffffff) {
                    throw new Win32Exception(Marshal.GetLastWin32Error(), "Git probe process resume failed.");
                }

                Stopwatch mainClock = Stopwatch.StartNew();
                long quiescentSince = -1;
                bool timedOut = false;
                bool truncated = false;
                while (true) {
                    uint rootWait = WaitForSingleObject(processInfo.hProcess, 0);
                    if (rootWait != WAIT_OBJECT_0 && rootWait != WAIT_TIMEOUT) {
                        throw new Win32Exception(Marshal.GetLastWin32Error(), "Git probe process wait failed.");
                    }
                    JOBOBJECT_BASIC_ACCOUNTING_INFORMATION liveAccounting = QueryAccounting(job);
                    if (
                        rootWait == WAIT_OBJECT_0 &&
                        liveAccounting.ActiveProcesses == 0 &&
                        stdoutThread.Join(0) &&
                        stderrThread.Join(0)
                    ) {
                        if (quiescentSince < 0) quiescentSince = mainClock.ElapsedMilliseconds;
                        if (mainClock.ElapsedMilliseconds - quiescentSince >= 25) break;
                    }
                    else {
                        quiescentSince = -1;
                    }
                    if (stdout.Truncated || stderr.Truncated) { truncated = true; break; }
                    if (mainClock.ElapsedMilliseconds >= timeoutMilliseconds) { timedOut = true; break; }
                    Thread.Sleep(10);
                }

                bool forced = timedOut || truncated;
                if (forced) {
                    Require(TerminateJobObject(job, 137), "Git probe process tree termination failed.");
                }
                Stopwatch cleanupClock = Stopwatch.StartNew();
                if (!WaitForQuiescence(job, RemainingMilliseconds(cleanupClock, cleanupMilliseconds))) {
                    throw new InvalidOperationException("Git probe process tree did not quiesce.");
                }
                if (WaitForSingleObject(processInfo.hProcess, (uint)RemainingMilliseconds(cleanupClock, cleanupMilliseconds)) != WAIT_OBJECT_0) {
                    throw new InvalidOperationException("Git probe root process did not terminate.");
                }
                bool stdoutJoined = stdoutThread.Join(RemainingMilliseconds(cleanupClock, cleanupMilliseconds));
                bool stderrJoined = stderrThread.Join(RemainingMilliseconds(cleanupClock, cleanupMilliseconds));
                if (!stdoutJoined || !stderrJoined) {
                    throw new InvalidOperationException("Git probe output drains did not terminate.");
                }
                if (stdout.Error != null || stderr.Error != null) {
                    throw new InvalidOperationException("Git probe output drain failed.");
                }
                truncated = truncated || stdout.Truncated || stderr.Truncated;

                JOBOBJECT_BASIC_ACCOUNTING_INFORMATION accounting = QueryAccounting(job);
                uint exitCode;
                Require(GetExitCodeProcess(processInfo.hProcess, out exitCode), "Git probe exit code read failed.");
                bool exactProcessCount =
                    accounting.TotalProcesses == 1 &&
                    (forced || accounting.TotalTerminatedProcesses == 0) &&
                    accounting.ActiveProcesses == 0;
                if (!exactProcessCount) {
                    throw new InvalidOperationException(
                        "Git probe process count was not exact: total=" +
                        accounting.TotalProcesses + ", active=" +
                        accounting.ActiveProcesses + ", terminated=" +
                        accounting.TotalTerminatedProcesses + ".");
                }

                string standardOutput = String.Empty;
                string standardError = String.Empty;
                if (!truncated) {
                    var strictUtf8 = new UTF8Encoding(false, true);
                    standardOutput = strictUtf8.GetString(stdout.Bytes, 0, stdout.Count);
                    standardError = strictUtf8.GetString(stderr.Bytes, 0, stderr.Count);
                }
                return new GitProbeRunResult {
                    Started = true,
                    TimedOut = timedOut,
                    TerminationComplete = true,
                    OutputTruncated = truncated,
                    JobAssigned = true,
                    ProcessCountExact = true,
                    ExitCode = forced ? -1 : unchecked((int)exitCode),
                    StdOut = standardOutput,
                    StdErr = standardError
                };
            }
            catch {
                bool cleanupComplete = true;
                Stopwatch failureCleanupClock = Stopwatch.StartNew();
                if (processCreated) {
                    if (jobAssigned) {
                        try { TerminateJobObject(job, 137); } catch { }
                    }
                    else {
                        try { TerminateProcess(processInfo.hProcess, 137); } catch { }
                    }
                    if (stdoutThreadStarted) {
                        try { CancelCaptureRead(stdout); } catch { }
                    }
                    if (stderrThreadStarted) {
                        try { CancelCaptureRead(stderr); } catch { }
                    }
                    if (jobAssigned) {
                        try {
                            cleanupComplete = WaitForQuiescence(
                                job,
                                RemainingMilliseconds(failureCleanupClock, cleanupMilliseconds)
                            ) && cleanupComplete;
                        }
                        catch { cleanupComplete = false; }
                    }
                    try {
                        cleanupComplete = (
                            WaitForSingleObject(
                                processInfo.hProcess,
                                (uint)RemainingMilliseconds(failureCleanupClock, cleanupMilliseconds)
                            ) == WAIT_OBJECT_0
                        ) && cleanupComplete;
                    }
                    catch { cleanupComplete = false; }
                }
                if (stdoutThreadStarted) {
                    bool joined = false;
                    try { joined = stdoutThread.Join(RemainingMilliseconds(failureCleanupClock, cleanupMilliseconds)); } catch { }
                    cleanupComplete = joined && cleanupComplete;
                }
                if (stderrThreadStarted) {
                    bool joined = false;
                    try { joined = stderrThread.Join(RemainingMilliseconds(failureCleanupClock, cleanupMilliseconds)); } catch { }
                    cleanupComplete = joined && cleanupComplete;
                }
                if (!cleanupComplete) {
                    throw new InvalidOperationException("Git probe failure cleanup was incomplete.");
                }
                throw;
            }
            finally {
                Close(ref stdinRead);
                Close(ref stdinWrite);
                Close(ref stdoutWrite);
                Close(ref stderrWrite);
                Close(ref stdoutRead);
                Close(ref stderrRead);
                Close(ref processInfo.hThread);
                Close(ref processInfo.hProcess);
                if (environmentBlock != IntPtr.Zero) Marshal.FreeHGlobal(environmentBlock);
                if (attributeList != IntPtr.Zero) {
                    if (attributeListInitialized) DeleteProcThreadAttributeList(attributeList);
                    Marshal.FreeHGlobal(attributeList);
                }
                if (attributeHandles != IntPtr.Zero) Marshal.FreeHGlobal(attributeHandles);
                Close(ref job);
            }
        }
    }
}
'@
}

function Invoke-CddsiGitVersionProbe {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][string]$ExpectedFileIdentityToken,
        [ValidateRange(1000, 30000)][int]$TimeoutMilliseconds = 10000
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    if ($ExpectedFileIdentityToken -notmatch '^[a-f0-9]{64}$') {
        throw 'Git version probe requires an exact expected file identity token.'
    }

    $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Process')
    $programFiles = [System.IO.Path]::GetFullPath(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    ).TrimEnd('\')
    $installRoot = [System.IO.Path]::GetFullPath((Join-Path $programFiles 'Git')).TrimEnd('\')
    $launcherPath = Join-Path $installRoot 'cmd\git.exe'
    $binPath = Join-Path $installRoot 'mingw64\bin'
    $corePath = Join-Path $binPath 'git.exe'
    $httpsPath = Join-Path $installRoot 'mingw64\libexec\git-core\git-remote-https.exe'
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($ExecutablePath), $launcherPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Git version probe requires the exact supported PATH launcher.'
    }

    $lockStreams = New-Object System.Collections.Generic.List[System.IO.FileStream]
    try {
        Initialize-CddsiD027GitProbeRunnerType
        $privateDllItems = @(
            Get-ChildItem -LiteralPath $binPath -Filter '*.dll' -File -Force -ErrorAction Stop
        )
        if ($privateDllItems.Count -lt 5 -or $privateDllItems.Count -gt 256) {
            throw 'Git private DLL lock set was outside the supported bound.'
        }
        $privateDllPathSet = @{}
        foreach ($privateDllItem in $privateDllItems) {
            $privateDllPath = [System.IO.Path]::GetFullPath([string]$privateDllItem.FullName)
            $privateDllParent = [System.IO.Path]::GetDirectoryName($privateDllPath).TrimEnd('\')
            $privateDllName = [System.IO.Path]::GetFileName($privateDllPath)
            if (
                -not [string]::Equals($privateDllParent, $binPath, [StringComparison]::OrdinalIgnoreCase) -or
                $privateDllName -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,126}\.dll$' -or
                $privateDllPathSet.ContainsKey($privateDllName.ToUpperInvariant())
            ) {
                throw 'Git private DLL lock set was invalid.'
            }
            $privateDllPathSet[$privateDllName.ToUpperInvariant()] = $privateDllPath
        }
        $privateDllPaths = [string[]]@($privateDllPathSet.Values)
        [Array]::Sort($privateDllPaths, [StringComparer]::OrdinalIgnoreCase)
        $lockPaths = @($launcherPath, $corePath, $httpsPath) + @($privateDllPaths)
        foreach ($lockPath in $lockPaths) {
            $lockStreams.Add([System.IO.File]::Open(
                $lockPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            ))
        }
        $lockedObservation = Get-CddsiGitForWindowsExecutableObservation -ExecutionContext $Context -ExecutablePath $ExecutablePath
        if (
            $lockedObservation.Status -cne 'SUCCEEDED' -or
            $lockedObservation.Data.IdentityStatus -cne 'Trusted' -or
            $lockedObservation.Data.FileIdentityToken -cne $ExpectedFileIdentityToken
        ) {
            return New-CddsiOperationResult -Operation 'ProbeGitForWindowsVersion' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_EXECUTABLE_CHANGED_BEFORE_PROBE' -MessageSafe 'Git executable identity changed before the isolated version probe.'
        }

        $startInfo = New-CddsiGitVersionProbeStartInfo -ExecutablePath $corePath -SystemRootPath $systemRoot -ProductTempPath $Context.Paths.Temp
        $probeEnvironment = @{}
        foreach ($environmentName in $startInfo.EnvironmentVariables.Keys) {
            $name = [string]$environmentName
            $probeEnvironment[$name] = [string]$startInfo.EnvironmentVariables[$name]
        }
        $run = [Cddsi.D027.GitProbeRunner]::Run(
            $startInfo.FileName,
            $startInfo.WorkingDirectory,
            $probeEnvironment,
            $TimeoutMilliseconds,
            128,
            5000
        )
        if (-not $run.JobAssigned -or -not $run.ProcessCountExact -or -not $run.TerminationComplete) {
            throw 'Git probe containment did not complete.'
        }
        $probeResult = [pscustomobject][ordered]@{
            SchemaVersion = 1
            Started = [bool]$run.Started
            TimedOut = [bool]$run.TimedOut
            TerminationComplete = [bool]$run.TerminationComplete
            OutputTruncated = [bool]$run.OutputTruncated
            ExitCode = if ($run.TimedOut -or $run.OutputTruncated) { $null } else { [int]$run.ExitCode }
            StdOut = if ($run.OutputTruncated) { '' } else { [string]$run.StdOut }
            StdErr = if ($run.OutputTruncated) { '' } else { [string]$run.StdErr }
        }

        $lockedAfterObservation = Get-CddsiGitForWindowsExecutableObservation -ExecutionContext $Context -ExecutablePath $ExecutablePath
        if (
            $lockedAfterObservation.Status -cne 'SUCCEEDED' -or
            $lockedAfterObservation.Data.IdentityStatus -cne 'Trusted' -or
            $lockedAfterObservation.Data.FileIdentityToken -cne $ExpectedFileIdentityToken
        ) {
            return New-CddsiOperationResult -Operation 'ProbeGitForWindowsVersion' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_EXECUTABLE_CHANGED_DURING_PROBE' -MessageSafe 'Git installation identity changed during the isolated version probe.'
        }
    }
    catch {
        return New-CddsiOperationResult -Operation 'ProbeGitForWindowsVersion' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_VERSION_PROBE_FAILED' -MessageSafe 'The isolated Git version probe failed closed.'
    }
    finally {
        foreach ($lockStream in @($lockStreams.ToArray())) {
            if ($null -ne $lockStream) { $lockStream.Dispose() }
        }
    }

    $parsed = ConvertFrom-CddsiGitVersionProbeResult -ProbeResult $probeResult
    if (-not $parsed.Valid) {
        return New-CddsiOperationResult -Operation 'ProbeGitForWindowsVersion' -Status 'FAILED' -Mode Live -ErrorCode $parsed.ReasonCode -MessageSafe 'The isolated Git version probe was rejected.'
    }
    return New-CddsiOperationResult -Operation 'ProbeGitForWindowsVersion' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The isolated Git for Windows version probe succeeded.' -Data $parsed
}

function Get-CddsiGitForWindowsExecutableObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ExecutablePath
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    if (
        [string]::IsNullOrWhiteSpace($ExecutablePath) -or
        -not [System.IO.Path]::IsPathRooted($ExecutablePath) -or
        -not [string]::Equals([System.IO.Path]::GetFileName($ExecutablePath), 'git.exe', [StringComparison]::OrdinalIgnoreCase)
    ) {
        throw 'Git executable observation requires an exact absolute git.exe path.'
    }

    $path = [System.IO.Path]::GetFullPath($ExecutablePath)
    $programFiles = [System.IO.Path]::GetFullPath(
        [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
    ).TrimEnd('\')
    $installRoot = [System.IO.Path]::GetFullPath((Join-Path $programFiles 'Git')).TrimEnd('\')
    $launcherPath = Join-Path $installRoot 'cmd\git.exe'
    $corePath = Join-Path $installRoot 'mingw64\bin\git.exe'
    $httpsPath = Join-Path $installRoot 'mingw64\libexec\git-core\git-remote-https.exe'
    $pathBindingToken = Get-CddsiPathBindingToken -Path $path

    $newUntrustedData = {
        param([string[]]$ReasonCodes)
        return [pscustomobject][ordered]@{
            SchemaVersion = 3
            PathBindingToken = $pathBindingToken
            FileIdentityToken = $null
            InstallRootBindingToken = $null
            CorePathBindingToken = $null
            HttpsPathBindingToken = $null
            DependencyIdentityToken = $null
            DependencyCount = 0
            ArtifactSha256 = $null
            ArtifactSizeBytes = [long]0
            FileVersion = $null
            PeMachine = $null
            AuthenticodeStatus = 'Unknown'
            SignerThumbprint = $null
            SignerSubjectToken = $null
            PublisherToken = $null
            IdentityToken = $null
            IdentityStatus = 'Untrusted'
            ProtectionStatus = 'Unknown'
            RegistryStatus = 'Unknown'
            ComponentCount = 0
            ReasonCodes = @($ReasonCodes)
        }
    }

    if (-not [string]::Equals($path, $launcherPath, [StringComparison]::OrdinalIgnoreCase)) {
        $data = & $newUntrustedData @('GIT_INSTALL_LAYOUT_UNSUPPORTED')
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git executable was not in the supported protected installation layout.' -Data $data
    }

    $binPath = Join-Path $installRoot 'mingw64\bin'
    $baseRequiredPaths = @(
        (Join-Path $installRoot 'cmd'),
        (Join-Path $installRoot 'mingw64'),
        $binPath,
        (Join-Path $installRoot 'mingw64\libexec'),
        (Join-Path $installRoot 'mingw64\libexec\git-core'),
        $launcherPath,
        $corePath,
        $httpsPath
    )
    $baseProtection = Test-CddsiGitProtectedInstallPathSet -ExecutionContext $Context -InstallRoot $installRoot -RequiredPaths $baseRequiredPaths
    if ($baseProtection.Status -cne 'SUCCEEDED' -or $baseProtection.Data.ProtectionStatus -cne 'Protected') {
        $reasons = if ($baseProtection.Status -ceq 'SUCCEEDED') { @($baseProtection.Data.ReasonCodes) } else { @($baseProtection.ErrorCode) }
        $data = & $newUntrustedData $reasons
        $data.ProtectionStatus = 'Untrusted'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git installation path was not protected for reuse.' -Data $data
    }

    try {
        $privateDllItems = @(
            Get-ChildItem -LiteralPath $binPath -Filter '*.dll' -File -Force -ErrorAction Stop
        )
        if ($privateDllItems.Count -lt 5 -or $privateDllItems.Count -gt 256) {
            throw 'Git private DLL count was outside the supported bound.'
        }
        $privateDllPathSet = @{}
        foreach ($privateDllItem in $privateDllItems) {
            $privateDllPath = [System.IO.Path]::GetFullPath([string]$privateDllItem.FullName)
            $privateDllParent = [System.IO.Path]::GetDirectoryName($privateDllPath).TrimEnd('\')
            $privateDllName = [System.IO.Path]::GetFileName($privateDllPath)
            if (
                -not [string]::Equals($privateDllParent, $binPath, [StringComparison]::OrdinalIgnoreCase) -or
                $privateDllName -notmatch '^[A-Za-z0-9][A-Za-z0-9._+-]{0,126}\.dll$' -or
                $privateDllPathSet.ContainsKey($privateDllName.ToUpperInvariant())
            ) {
                throw 'Git private DLL path set was invalid.'
            }
            $privateDllPathSet[$privateDllName.ToUpperInvariant()] = $privateDllPath
        }
        $privateDllPaths = [string[]]@($privateDllPathSet.Values)
        [Array]::Sort($privateDllPaths, [StringComparer]::OrdinalIgnoreCase)
    }
    catch {
        $data = & $newUntrustedData @('GIT_PRIVATE_DLL_SET_INVALID')
        $data.ProtectionStatus = 'Protected'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git private dependency set could not be enumerated safely.' -Data $data
    }

    $requiredPaths = @($baseRequiredPaths) + @($privateDllPaths)
    $protection = Test-CddsiGitProtectedInstallPathSet -ExecutionContext $Context -InstallRoot $installRoot -RequiredPaths $requiredPaths
    if ($protection.Status -cne 'SUCCEEDED' -or $protection.Data.ProtectionStatus -cne 'Protected') {
        $reasons = if ($protection.Status -ceq 'SUCCEEDED') { @($protection.Data.ReasonCodes) } else { @($protection.ErrorCode) }
        $data = & $newUntrustedData $reasons
        $data.ProtectionStatus = 'Untrusted'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'A Git private dependency path was not protected for reuse.' -Data $data
    }

    $privateDlls = Get-CddsiGitForWindowsPrivateDllObservation -ExecutionContext $Context -BinPath $binPath -ExpectedPaths $privateDllPaths
    if ($privateDlls.Status -cne 'SUCCEEDED' -or $privateDlls.Data.IdentityStatus -cne 'Trusted') {
        $reasons = if ($privateDlls.Status -ceq 'SUCCEEDED') { @($privateDlls.Data.ReasonCodes) } else { @($privateDlls.ErrorCode) }
        $data = & $newUntrustedData $reasons
        $data.ProtectionStatus = 'Protected'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The protected Git private dependency set was not trusted.' -Data $data
    }

    $components = @(
        Get-CddsiGitForWindowsSignedComponentObservation -ExecutionContext $Context -ComponentPath $launcherPath -ComponentRole PathLauncher
        Get-CddsiGitForWindowsSignedComponentObservation -ExecutionContext $Context -ComponentPath $corePath -ComponentRole Core
        Get-CddsiGitForWindowsSignedComponentObservation -ExecutionContext $Context -ComponentPath $httpsPath -ComponentRole HttpsTransport
    )
    $componentReasons = New-Object System.Collections.Generic.List[string]
    foreach ($component in $components) {
        if ($component.Status -cne 'SUCCEEDED') {
            $componentReasons.Add($component.ErrorCode)
        }
        elseif ($component.Data.IdentityStatus -cne 'Trusted') {
            foreach ($reason in @($component.Data.ReasonCodes)) { $componentReasons.Add($reason) }
        }
    }
    if ($componentReasons.Count -gt 0) {
        $data = & $newUntrustedData @($componentReasons.ToArray() | Select-Object -Unique)
        $data.ProtectionStatus = 'Protected'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'A required Git installation component was not trusted.' -Data $data
    }

    $launcher = $components[0].Data
    $core = $components[1].Data
    $https = $components[2].Data
    if (
        $launcher.FileVersion -cne $core.FileVersion -or
        $launcher.FileVersion -cne $https.FileVersion -or
        $launcher.SignerThumbprint -cne $core.SignerThumbprint -or
        $launcher.SignerThumbprint -cne $https.SignerThumbprint
    ) {
        $data = & $newUntrustedData @('GIT_INSTALL_COMPONENT_IDENTITY_MISMATCH')
        $data.ProtectionStatus = 'Protected'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Git installation component identities did not agree.' -Data $data
    }

    $receiptVersion = ConvertTo-CddsiGitInstallerReceiptVersion -GitVersion $launcher.FileVersion
    $registry = Get-CddsiGitForWindowsRegistryObservation -ExecutionContext $Context -ExpectedInstallRoot $installRoot -ExpectedReceiptVersion $receiptVersion
    if ($registry.Status -cne 'SUCCEEDED' -or $registry.Data.RegistryStatus -cne 'Trusted') {
        $reasons = if ($registry.Status -ceq 'SUCCEEDED') { @($registry.Data.ReasonCodes) } else { @($registry.ErrorCode) }
        $data = & $newUntrustedData $reasons
        $data.ProtectionStatus = 'Protected'
        $data.RegistryStatus = 'Untrusted'
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git machine installation receipt did not corroborate the protected component bundle.' -Data $data
    }

    $bundleToken = Get-CddsiSupplyChainTextBindingToken -Text (
        '{0}|{1}|{2}|{3}|{4}|{5}' -f
        $protection.Data.InstallRootBindingToken,
        $registry.Data.RegistryIdentityToken,
        $launcher.FileIdentityToken,
        $core.FileIdentityToken,
        $https.FileIdentityToken,
        $privateDlls.Data.DependencyIdentityToken
    )
    $data = [pscustomobject][ordered]@{
        SchemaVersion = 3
        PathBindingToken = $launcher.PathBindingToken
        FileIdentityToken = $bundleToken
        InstallRootBindingToken = $protection.Data.InstallRootBindingToken
        CorePathBindingToken = $core.PathBindingToken
        HttpsPathBindingToken = $https.PathBindingToken
        DependencyIdentityToken = $privateDlls.Data.DependencyIdentityToken
        DependencyCount = [int]$privateDlls.Data.DependencyCount
        ArtifactSha256 = $launcher.ArtifactSha256
        ArtifactSizeBytes = [long]$launcher.ArtifactSizeBytes
        FileVersion = $launcher.FileVersion
        PeMachine = 'x64'
        AuthenticodeStatus = 'Valid'
        SignerThumbprint = $launcher.SignerThumbprint
        SignerSubjectToken = '<SIGNER_SUBJECT:GIT_FOR_WINDOWS_JOHANNES_SCHINDELIN>'
        PublisherToken = '<PUBLISHER:GIT_DEVELOPMENT_COMMUNITY>'
        IdentityToken = '<IDENTITY:GIT_FOR_WINDOWS_X64_PROTECTED_BUNDLE>'
        IdentityStatus = 'Trusted'
        ProtectionStatus = 'Protected'
        RegistryStatus = 'Trusted'
        ComponentCount = 3
        ReasonCodes = @()
    }
    return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The protected Git for Windows installation bundle was observed.' -Data $data
}

function Get-CddsiLiveGitForWindowsObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][string]$MinimumVersion,
        [ValidateRange(1000, 30000)][int]$TimeoutMilliseconds = 10000
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null

    $candidatePaths = New-Object System.Collections.Generic.List[string]
    $shadowPaths = New-Object System.Collections.Generic.List[string]
    $pathInvalid = $false
    $shadowNames = New-Object System.Collections.Generic.List[string]
    $shadowNameSeen = @{}
    $pathExtValue = [Environment]::GetEnvironmentVariable('PATHEXT', 'Process')
    $hasExePathExtension = $false
    if (
        $pathExtValue -isnot [string] -or
        [string]::IsNullOrWhiteSpace($pathExtValue) -or
        $pathExtValue.Length -gt 1024
    ) {
        $pathInvalid = $true
    }
    else {
        $extensions = @($pathExtValue -split ';', -1)
        if ($extensions.Count -gt 64) { $pathInvalid = $true }
        foreach ($extensionEntry in $extensions) {
            $extension = $extensionEntry.Trim().ToLowerInvariant()
            if ($extension -notmatch '^\.[a-z0-9]{1,8}$') {
                $pathInvalid = $true
                break
            }
            if ($extension -ceq '.exe') {
                $hasExePathExtension = $true
                continue
            }
            $shadowName = 'git' + $extension
            if (-not $shadowNameSeen.ContainsKey($shadowName)) {
                $shadowNameSeen[$shadowName] = $true
                $shadowNames.Add($shadowName)
            }
        }
        if (-not $hasExePathExtension) { $pathInvalid = $true }
    }
    if (-not $shadowNameSeen.ContainsKey('git.ps1')) {
        $shadowNameSeen['git.ps1'] = $true
        $shadowNames.Add('git.ps1')
    }
    $pathValue = [Environment]::GetEnvironmentVariable('Path', 'Process')
    if ($null -eq $pathValue) { $pathValue = '' }
    $pathEntries = if ($pathInvalid) { @() } else { @($pathValue -split ';', -1) }
    foreach ($entry in $pathEntries) {
        $directory = $entry.Trim()
        if ($directory.Length -eq 0) { continue }
        $startsQuoted = $directory.StartsWith('"', [StringComparison]::Ordinal)
        $endsQuoted = $directory.EndsWith('"', [StringComparison]::Ordinal)
        if ($startsQuoted -ne $endsQuoted) {
            $pathInvalid = $true
            break
        }
        if ($startsQuoted) {
            if ($directory.Length -lt 2) {
                $pathInvalid = $true
                break
            }
            $directory = $directory.Substring(1, $directory.Length - 2)
        }
        $directory = [Environment]::ExpandEnvironmentVariables($directory)
        if (
            $directory.IndexOfAny([char[]]@('*', '?', [char]0)) -ge 0 -or
            $directory.Contains('%') -or
            $directory -notmatch '^[A-Za-z]:\\' -or
            -not [System.IO.Path]::IsPathRooted($directory)
        ) {
            $pathInvalid = $true
            break
        }
        try {
            $directory = [System.IO.Path]::GetFullPath($directory)
            $driveRoot = [System.IO.Path]::GetPathRoot($directory)
            $drive = New-Object System.IO.DriveInfo($driveRoot)
            if ($drive.DriveType -ne [System.IO.DriveType]::Fixed) {
                throw 'PATH directory is not on a fixed local volume.'
            }
        }
        catch {
            $pathInvalid = $true
            break
        }
        $directoryMissing = $false
        $ancestorPaths = New-Object System.Collections.Generic.List[string]
        $ancestorPaths.Add($driveRoot)
        $relativeDirectory = $directory.Substring($driveRoot.Length)
        $ancestor = $driveRoot
        foreach ($segment in @($relativeDirectory.Split(
            [char[]]@('\'),
            [System.StringSplitOptions]::RemoveEmptyEntries
        ))) {
            $ancestor = [System.IO.Path]::Combine($ancestor, $segment)
            $ancestorPaths.Add($ancestor)
        }
        foreach ($ancestorPath in $ancestorPaths) {
            try {
                $ancestorItem = Get-Item -LiteralPath $ancestorPath -Force -ErrorAction Stop
            }
            catch {
                if ($_.CategoryInfo.Category -eq [Management.Automation.ErrorCategory]::ObjectNotFound) {
                    $directoryMissing = $true
                    break
                }
                $pathInvalid = $true
                break
            }
            if (
                -not $ancestorItem.PSIsContainer -or
                ($ancestorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
            ) {
                $pathInvalid = $true
                break
            }
        }
        if ($pathInvalid) { break }
        if ($directoryMissing) { continue }
        $gitExe = Join-Path $directory 'git.exe'
        try {
            if (Test-Path -LiteralPath $gitExe -PathType Leaf -ErrorAction Stop) {
                $candidatePaths.Add($gitExe)
            }
        }
        catch {
            $pathInvalid = $true
            break
        }
        foreach ($shadowName in $shadowNames) {
            $shadow = Join-Path $directory $shadowName
            try {
                if (Test-Path -LiteralPath $shadow -PathType Leaf -ErrorAction Stop) {
                    $shadowPaths.Add($shadow)
                }
            }
            catch {
                $pathInvalid = $true
                break
            }
        }
        if ($pathInvalid) { break }
    }

    $pathSet = if ($pathInvalid) {
        [pscustomobject][ordered]@{
            SchemaVersion = 1; Status = 'INVALID'; CandidateCount = 0
            CanonicalPaths = @(); ReasonCodes = @('GIT_PATH_INVALID')
        }
    }
    else {
        Resolve-CddsiGitExecutablePathSet -CandidatePaths $candidatePaths.ToArray() -ShadowPaths $shadowPaths.ToArray()
    }
    if ($pathSet.Status -cne 'READY') {
        $data = [pscustomobject][ordered]@{
            SchemaVersion = 1; CandidateCount = $pathSet.CandidateCount; ExecutableToken = $null
            Version = $null; Source = 'Unknown'; IdentityStatus = 'Unknown'; CapabilityState = 'Unknown'
            ReuseEligible = $false; CapabilityStatus = 'BLOCKED'; ReasonCodes = @($pathSet.ReasonCodes)
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Git PATH observation completed and failed closed.' -Data $data
    }

    $executablePath = $pathSet.CanonicalPaths[0]
    $before = Get-CddsiGitForWindowsExecutableObservation -ExecutionContext $Context -ExecutablePath $executablePath
    if ($before.Status -cne 'SUCCEEDED') {
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode $before.ErrorCode -MessageSafe 'Git executable identity observation failed closed.'
    }
    $executableToken = '<GIT_EXECUTABLE:PATH_SHA256:{0}>' -f $before.Data.PathBindingToken.ToUpperInvariant()
    if ($before.Data.IdentityStatus -cne 'Trusted') {
        $data = [pscustomobject][ordered]@{
            SchemaVersion = 1; CandidateCount = 1; ExecutableToken = $executableToken
            Version = $before.Data.FileVersion; Source = 'Unknown'; IdentityStatus = $before.Data.IdentityStatus
            CapabilityState = 'Unknown'; ReuseEligible = $false; CapabilityStatus = 'BLOCKED'
            ReasonCodes = @($before.Data.ReasonCodes)
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Git executable identity was not trusted and was not executed.' -Data $data
    }

    $probe = Invoke-CddsiGitVersionProbe -ExecutionContext $Context -ExecutablePath $executablePath -ExpectedFileIdentityToken $before.Data.FileIdentityToken -TimeoutMilliseconds $TimeoutMilliseconds
    if ($probe.Status -cne 'SUCCEEDED') {
        $data = [pscustomobject][ordered]@{
            SchemaVersion = 1; CandidateCount = 1; ExecutableToken = $executableToken
            Version = $before.Data.FileVersion; Source = 'GitForWindows'; IdentityStatus = 'Trusted'
            CapabilityState = 'Broken'; ReuseEligible = $false; CapabilityStatus = 'BLOCKED'
            ReasonCodes = @($probe.ErrorCode)
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The trusted Git executable did not pass its isolated version probe.' -Data $data
    }

    $after = Get-CddsiGitForWindowsExecutableObservation -ExecutionContext $Context -ExecutablePath $executablePath
    if (
        $after.Status -cne 'SUCCEEDED' -or $after.Data.IdentityStatus -cne 'Trusted' -or
        $after.Data.FileIdentityToken -cne $before.Data.FileIdentityToken -or
        $after.Data.ArtifactSha256 -cne $before.Data.ArtifactSha256 -or
        [long]$after.Data.ArtifactSizeBytes -ne [long]$before.Data.ArtifactSizeBytes
    ) {
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_EXECUTABLE_CHANGED_DURING_CHECK' -MessageSafe 'Git executable identity changed during detection.'
    }
    if ($probe.Data.Version -cne $before.Data.FileVersion) {
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_EXECUTABLE_VERSION_MISMATCH' -MessageSafe 'Git executable file and probe versions did not match.'
    }

    $minimum = $null
    if (-not [string]::IsNullOrWhiteSpace($MinimumVersion)) {
        if (-not [version]::TryParse($MinimumVersion, [ref]$minimum)) {
            throw 'MinimumVersion must be null or a valid version string.'
        }
    }
    $blockedReasons = @()
    $unknownReasons = @()
    if ($null -eq $minimum) {
        $unknownReasons += 'GIT_MINIMUM_VERSION_UNRESOLVED'
    }
    elseif ([version]::Parse($probe.Data.ComparisonVersion) -lt $minimum) {
        $blockedReasons += 'GIT_UPGRADE_REQUIRED'
    }
    if ($blockedReasons.Count -gt 0) {
        $capabilityStatus = 'BLOCKED'
        $reasonCodes = $blockedReasons
    }
    elseif ($unknownReasons.Count -gt 0) {
        $capabilityStatus = 'UNKNOWN'
        $reasonCodes = $unknownReasons
    }
    else {
        $capabilityStatus = 'READY'
        $reasonCodes = @('GIT_REUSE_READY')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion = 1; CandidateCount = 1; ExecutableToken = $executableToken
        Version = $probe.Data.Version; Source = 'GitForWindows'; IdentityStatus = 'Trusted'
        CapabilityState = 'Operational'; ReuseEligible = ($capabilityStatus -ceq 'READY')
        CapabilityStatus = $capabilityStatus; ReasonCodes = @($reasonCodes)
    }
    return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Git for Windows PATH, identity and version observation completed.' -Data $data
}

function Get-CddsiGitForWindowsStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][string]$MinimumVersion
    )

    if ($Context.Mode -ceq 'Live') {
        return Get-CddsiLiveGitForWindowsObservation -ExecutionContext $Context -MinimumVersion $MinimumVersion
    }
    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $minimum = $null
    if (-not [string]::IsNullOrWhiteSpace($MinimumVersion)) {
        try {
            $minimum = [version]::Parse($MinimumVersion)
        }
        catch {
            throw 'MinimumVersion must be null or a valid version string.'
        }
    }

    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        CandidateCount   = 0
        ExecutableToken  = $null
        Version          = $null
        Source           = 'Unknown'
        IdentityStatus   = 'Unknown'
        CapabilityState  = 'Unknown'
        ReuseEligible    = $false
        CapabilityStatus = 'UNKNOWN'
        ReasonCodes      = @('GIT_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Process -Operation Inspect -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_PROVIDER_FAILED' -MessageSafe 'Synthetic Git for Windows provider failed closed.' -Data $unknownData
    }

    $valid = (
        (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'Candidates')) -and
        $observation.SchemaVersion -is [int] -and $observation.SchemaVersion -eq 1 -and
        $null -ne $observation.Candidates
    )
    [object[]]$candidates = @()
    if ($valid) {
        $candidates = @($observation.Candidates)
    }
    if ($valid) {
        foreach ($candidate in $candidates) {
            if (
                -not (Test-CddsiExactPropertySet -InputObject $candidate -Expected @('ExecutableToken', 'Version', 'Source', 'IdentityStatus', 'CapabilityState')) -or
                $candidate.ExecutableToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $candidate.ExecutableToken) -or
                $candidate.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate.Version) -or
                $candidate.Source -isnot [string] -or @('GitForWindows', 'Other', 'Unknown') -cnotcontains $candidate.Source -or
                $candidate.IdentityStatus -isnot [string] -or @('Trusted', 'Untrusted', 'Unknown') -cnotcontains $candidate.IdentityStatus -or
                $candidate.CapabilityState -isnot [string] -or @('Operational', 'Broken', 'Unknown') -cnotcontains $candidate.CapabilityState
            ) {
                $valid = $false
                break
            }
        }
    }
    if (-not $valid) {
        $unknownData.ReasonCodes = @('GIT_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_RESULT_INVALID' -MessageSafe 'Synthetic Git inventory did not match the exact schema.' -Data $unknownData
    }

    if ($candidates.Count -eq 0) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion    = 1
            CandidateCount   = 0
            ExecutableToken  = $null
            Version          = $null
            Source           = 'Unknown'
            IdentityStatus   = 'Unknown'
            CapabilityState  = 'Unknown'
            ReuseEligible    = $false
            CapabilityStatus = 'BLOCKED'
            ReasonCodes      = @('GIT_MISSING')
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git inventory completed.' -Data $data
    }

    if ($candidates.Count -gt 1) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion    = 1
            CandidateCount   = $candidates.Count
            ExecutableToken  = $null
            Version          = $null
            Source           = 'Unknown'
            IdentityStatus   = 'Unknown'
            CapabilityState  = 'Unknown'
            ReuseEligible    = $false
            CapabilityStatus = 'BLOCKED'
            ReasonCodes      = @('GIT_PATH_AMBIGUOUS')
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git inventory found multiple candidates and failed closed.' -Data $data
    }

    $candidate = $candidates[0]
    $versionObservation = ConvertFrom-CddsiGitVersionProbeResult -ProbeResult ([pscustomobject][ordered]@{
        SchemaVersion = 1; Started = $true; TimedOut = $false; TerminationComplete = $true; OutputTruncated = $false
        ExitCode = 0; StdOut = 'git version ' + $candidate.Version; StdErr = ''
    })
    if (-not $versionObservation.Valid) {
        $unknownData.CandidateCount = 1
        $unknownData.ReasonCodes = @('GIT_VERSION_INVALID')
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_VERSION_INVALID' -MessageSafe 'Synthetic Git version output was not parseable.' -Data $unknownData
    }
    $installedVersion = [version]::Parse($versionObservation.ComparisonVersion)

    $blockedReasons = @()
    $unknownReasons = @()
    if ($candidate.Source -ceq 'Other') { $blockedReasons += 'GIT_SOURCE_UNSUPPORTED' }
    if ($candidate.Source -ceq 'Unknown') { $unknownReasons += 'GIT_SOURCE_UNKNOWN' }
    if ($candidate.IdentityStatus -ceq 'Untrusted') { $blockedReasons += 'GIT_IDENTITY_UNTRUSTED' }
    if ($candidate.IdentityStatus -ceq 'Unknown') { $unknownReasons += 'GIT_IDENTITY_UNKNOWN' }
    if ($candidate.CapabilityState -ceq 'Broken') { $blockedReasons += 'GIT_CAPABILITY_BROKEN' }
    if ($candidate.CapabilityState -ceq 'Unknown') { $unknownReasons += 'GIT_CAPABILITY_UNKNOWN' }
    if ($null -eq $minimum) {
        $unknownReasons += 'GIT_MINIMUM_VERSION_UNRESOLVED'
    }
    elseif ($installedVersion -lt $minimum) {
        $blockedReasons += 'GIT_UPGRADE_REQUIRED'
    }

    if ($blockedReasons.Count -gt 0) {
        $capabilityStatus = 'BLOCKED'
        $reasonCodes = @($blockedReasons + $unknownReasons)
    }
    elseif ($unknownReasons.Count -gt 0) {
        $capabilityStatus = 'UNKNOWN'
        $reasonCodes = @($unknownReasons)
    }
    else {
        $capabilityStatus = 'READY'
        $reasonCodes = @('GIT_REUSE_READY')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        CandidateCount   = 1
        ExecutableToken  = $candidate.ExecutableToken
        Version          = $candidate.Version
        Source           = $candidate.Source
        IdentityStatus   = $candidate.IdentityStatus
        CapabilityState  = $candidate.CapabilityState
        ReuseEligible    = ($capabilityStatus -ceq 'READY')
        CapabilityStatus = $capabilityStatus
        ReasonCodes      = @($reasonCodes)
    }
    return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git for Windows inventory completed.' -Data $data
}

function ConvertFrom-CddsiGitHubReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ReleaseDocument,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ReleaseDocument -Expected @('tag_name', 'draft', 'prerelease', 'html_url', 'assets'))) {
        throw 'GitHub release document does not match the normalized exact schema.'
    }
    if (
        $ReleaseDocument.tag_name -isnot [string] -or
        $ReleaseDocument.draft -isnot [bool] -or $ReleaseDocument.draft -or
        $ReleaseDocument.prerelease -isnot [bool] -or $ReleaseDocument.prerelease -or
        $ReleaseDocument.html_url -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $ReleaseDocument.html_url -ExpectedOwner GitForWindows) -or
        $null -eq $ReleaseDocument.assets
    ) {
        throw 'GitHub release identity, draft or prerelease state is invalid.'
    }
    $tagMatch = [regex]::Match($ReleaseDocument.tag_name, '^v(?<version>[0-9]+\.[0-9]+\.[0-9]+)\.windows\.(?<revision>[1-9][0-9]*)$')
    if (-not $tagMatch.Success) { throw 'Git for Windows release tag does not match vX.windows.N.' }
    $releaseVersion = $tagMatch.Groups['version'].Value
    $releaseRevision = $tagMatch.Groups['revision'].Value
    $artifactVersion = '{0}.{1}' -f $releaseVersion, $releaseRevision
    # Git for Windows omits ".1" from installer file names for windows.1
    # releases, but appends later revision numbers (for example,
    # Git-2.55.0.3-64-bit.exe for v2.55.0.windows.3).
    $installerFileVersion = if ($releaseRevision -ceq '1') { $releaseVersion } else { $artifactVersion }
    $expectedTagUri = 'https://github.com/git-for-windows/git/releases/tag/' + $ReleaseDocument.tag_name
    if ($ReleaseDocument.html_url -cne $expectedTagUri) { throw 'GitHub release URL is not bound to the declared tag.' }

    $assetFields = @('name', 'browser_download_url', 'size', 'state', 'content_type', 'digest')
    $assetNamePattern = if ($Architecture -ceq 'x64') {
        '^Git-' + [regex]::Escape($installerFileVersion) + '-64-bit\.exe$'
    }
    else {
        '^Git-' + [regex]::Escape($installerFileVersion) + '-arm64\.exe$'
    }
    $installerContentTypes = @('application/executable', 'application/x-msdownload')
    $selectedAssets = @()
    foreach ($asset in @($ReleaseDocument.assets)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $asset -Expected $assetFields)) {
            throw 'GitHub release asset does not match the normalized exact schema.'
        }
        if (
            $asset.name -isnot [string] -or
            $asset.browser_download_url -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $asset.browser_download_url -ExpectedOwner GitForWindows) -or
            ($asset.size -isnot [int] -and $asset.size -isnot [long]) -or [long]$asset.size -lt 1 -or
            $asset.state -isnot [string] -or $asset.state -cne 'uploaded' -or
            $asset.content_type -isnot [string] -or [string]::IsNullOrWhiteSpace($asset.content_type) -or
            ($null -ne $asset.digest -and $asset.digest -isnot [string])
        ) {
            throw 'GitHub release asset values are invalid.'
        }
        if ($asset.name -match $assetNamePattern) {
            if ($installerContentTypes -cnotcontains $asset.content_type) {
                throw 'GitHub installer asset content type is invalid.'
            }
            if ($asset.digest -isnot [string] -or $asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
                throw 'GitHub installer asset requires an exact SHA-256 digest.'
            }
            $selectedAssets += $asset
        }
    }
    if ($selectedAssets.Count -ne 1) { throw 'GitHub release metadata must contain exactly one installer for the requested architecture.' }
    $selected = $selectedAssets[0]
    $expectedAssetPrefix = 'https://github.com/git-for-windows/git/releases/download/' + $ReleaseDocument.tag_name + '/'
    if ($selected.browser_download_url -cne ($expectedAssetPrefix + $selected.name)) {
        throw 'GitHub asset URL is not exactly bound to the declared tag and asset name.'
    }
    $artifactSha256 = $selected.digest.Substring(7).ToLowerInvariant()

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion              = 1
        DescriptorId               = ('git-for-windows-{0}-windows-{1}-{2}' -f $releaseVersion, $releaseRevision, $Architecture)
        ArtifactType               = 'GitForWindowsInstaller'
        SourcePolicy               = 'git_for_windows_official_only'
        SourceUri                  = $selected.browser_download_url
        SourceUriBindingToken      = Get-CddsiSourceUriBindingToken -SourceUri $selected.browser_download_url
        ReleaseVersion             = $artifactVersion
        Architecture               = $Architecture
        Channel                    = 'Installer'
        FileNameToken              = if ($Architecture -ceq 'x64') { '<ARTIFACT_FILE:GIT_X64_INSTALLER>' } else { '<ARTIFACT_FILE:GIT_ARM64_INSTALLER>' }
        ExpectedArtifactSha256     = $artifactSha256
        ExpectedArtifactSizeBytes  = [long]$selected.size
        ExpectedSignerThumbprint   = $null
        ExpectedSignerSubjectToken = $null
        ExpectedPublisherToken     = $null
        ExpectedIdentityToken      = $null
        RedirectPolicy             = 'same-owner-https-only'
        MaximumBytes               = [long]1073741824
        MetadataStatus             = 'UNRESOLVED'
    }
    $descriptor = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) { $descriptor[$property.Name] = $property.Value }
    $descriptor['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $result = [pscustomobject]$descriptor
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $result -ExpectedArtifactType GitForWindowsInstaller)) {
        throw 'Git for Windows descriptor failed its immutable contract.'
    }
    return $result
}

function Get-CddsiOfficialGitInstallerMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    try {
        $document = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Network -Operation Inspect -ResourceToken '<NETWORK:GIT_FOR_WINDOWS_RELEASES_API>' -Arguments ([ordered]@{ Architecture = $Architecture })
        $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture $Architecture
    }
    catch {
        return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_METADATA_INVALID' -MessageSafe 'Synthetic GitHub release metadata failed closed.'
    }
    return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'GIT_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'GitHub metadata resolved version and digest, but signer and installer identity remain unresolved.' -Data $descriptor
}

function Save-CddsiOfficialGitInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller)) {
        throw 'Git download plan requires an exact official artifact descriptor.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $DestinationPath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'DownloadGitForWindows' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion         = 1
        ArtifactType         = 'GitForWindowsInstaller'
        DestinationPathToken = $pathBindingToken
        MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken
        CacheKey              = $ArtifactDescriptor.MetadataBindingToken
        CachePolicy           = 'unique-by-immutable-descriptor'
        WriteImplemented      = $false
    }
    $errorCode = if ($ArtifactDescriptor.MetadataStatus -ceq 'READY') { 'P4_PLAN_ONLY' } else { 'GIT_ARTIFACT_CONTRACT_UNRESOLVED' }
    return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode $errorCode -MessageSafe 'No network or file write occurred; only an immutable download/cache plan was returned.' -Data $data -PlannedChanges @('<DOWNLOAD:GIT_FOR_WINDOWS_INSTALLER>')
}

function Test-CddsiGitInstallerSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)][AllowNull()]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller -RequireResolved)) {
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'GIT_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'Resolved Git hash and signer identity metadata are required before verification.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $InstallerPath
    try {
        $fileObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'SignatureVerification' })
        $signatureObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Package -Operation Inspect -ResourceToken '<SIGNATURE:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; ArtifactSha256 = [string]$fileObservation.ArtifactSha256 })
        $evidence = New-CddsiSignatureEvidenceVerdict -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller -PathBindingToken $pathBindingToken -SourceObservation $SourceObservation -FileObservation $fileObservation -SignatureObservation $signatureObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc
    }
    catch {
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_SIGNATURE_OBSERVATION_FAILED' -MessageSafe 'Synthetic Git signature observation failed closed.'
    }
    if (-not $evidence.Valid) {
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_SIGNATURE_REJECTED' -MessageSafe 'Git signature or immutable descriptor binding did not match.' -Data $evidence
    }
    return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git signature evidence v2 is fully bound.' -Data $evidence
}

function Install-CddsiGitForWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $InstallerPath -ExpectedArtifactType GitForWindowsInstaller -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) { throw '安装合同要求与目标安装包、source observation、run/profile 及 immutable descriptor 绑定的新鲜 v2 验签证据。' }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
    $pathBindingToken = Get-CddsiPathBindingToken -Path $InstallerPath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'InstallGitForWindows' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $current = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'ExecutionTimeHashReverification' })
    if (
        -not (Test-CddsiExactPropertySet -InputObject $current -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes')) -or
        -not (Test-CddsiSchemaVersionOne -Value $current.SchemaVersion) -or
        $current.FileIdentityToken -isnot [string] -or $current.FileIdentityToken -cne $payload.FileIdentityToken -or
        $current.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $current.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
        ($current.ArtifactSizeBytes -isnot [int] -and $current.ArtifactSizeBytes -isnot [long]) -or [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 Git installer hash/size 复验失败；拒绝安装。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'GitForWindowsInstaller'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'Git installer hash was reverified through the fake provider; installation remains disabled.' -Data $data -PlannedChanges @('<INSTALL:GIT_FOR_WINDOWS>')
}
