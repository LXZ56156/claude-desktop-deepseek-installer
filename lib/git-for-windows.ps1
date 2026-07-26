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
$script:CddsiD027GitLatestReleaseApiUri = 'https://api.github.com/repos/git-for-windows/git/releases/latest'
$script:CddsiD027GitMetadataMaximumBytes = [long](8MB)
$script:CddsiD027GitMetadataTimeoutSeconds = 60
$script:CddsiD027GitDownloadTimeoutSeconds = 1800
$script:CddsiD027GitDownloadMaximumRedirects = 5
$script:CddsiD027GitInstallerSignerSubjectToken = '<SIGNER_SUBJECT:GIT_FOR_WINDOWS_JOHANNES_SCHINDELIN>'
$script:CddsiD027GitInstallerPublisherToken = '<PUBLISHER:GIT_DEVELOPMENT_COMMUNITY>'
$script:CddsiD027GitInstallerIdentityToken = '<IDENTITY:GIT_FOR_WINDOWS_X64_INSTALLER>'
$script:CddsiD027ExternalSnapshotReceiptMaximumBytes = [long](32KB)
$script:CddsiD027SnapshotAuthorityPolicyFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'Configured',
    'AuthorityId',
    'SignatureAlgorithm',
    'AuthorityKeySha256',
    'RsaModulusBase64',
    'RsaExponentBase64'
)
$script:CddsiD027ExternalSnapshotReceiptFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'AuthorityId',
    'AuthorityKeySha256',
    'SignatureAlgorithm',
    'AuthoritySignatureBase64',
    'ExternalSource',
    'RestoreState',
    'VmDisposition',
    'RunId',
    'Stage',
    'EnvironmentTier',
    'ArtifactProfile',
    'Operation',
    'ExecutionArtifactSha256',
    'SnapshotIdentitySha256',
    'VmIdentitySha256',
    'RestorerIdentitySha256',
    'WindowsMajorVersion',
    'WindowsBuildNumber',
    'WindowsProductType',
    'WindowsProductInfoCode',
    'NativeArchitecture',
    'ProcessArchitecture',
    'PowerShellVersion',
    'RestoreCompletedAtUtc',
    'IssuedAtUtc',
    'ExpiresAtUtc',
    'WorkloadBindingToken',
    'ReceiptBindingToken'
)
$script:CddsiD027GitLiveSessionAuthorizationFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'Receipt',
    'ReceiptSha256',
    'ReceiptLengthBytes',
    'ExpectedExecutionArtifactSha256',
    'AuthorizedAtUtc',
    'InitialPlatformObservation'
)
$script:CddsiD027GitLiveSessionAuthorization = $null
$script:CddsiD027SnapshotReceiptSignatureDomain =
    'cddsi-d027-external-clean-snapshot-receipt-signature-v1'

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

function Get-CddsiD027SnapshotPlatformObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiD027GitLiveBootstrapContext -ExecutionContext $Context | Out-Null
    try {
        if ($null -eq ('Cddsi.D027.SnapshotPlatformBindingV1' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

namespace Cddsi.D027 {
    public sealed class SnapshotPlatformObservationV1 {
        public uint WindowsMajorVersion;
        public uint WindowsBuildNumber;
        public byte WindowsProductType;
        public uint WindowsProductInfoCode;
        public ushort NativeMachine;
        public bool Is64BitProcess;
        public string VmUuid;
    }

    public static class SnapshotPlatformBindingV1 {
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

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetProductInfo(
            uint majorVersion,
            uint minorVersion,
            uint servicePackMajor,
            uint servicePackMinor,
            out uint productType);

        [DllImport("ntdll.dll", CharSet = CharSet.Unicode)]
        private static extern int RtlGetVersion(ref RTL_OSVERSIONINFOEX version);

        [DllImport("kernel32.dll", SetLastError = true)]
        private static extern uint GetSystemFirmwareTable(
            uint firmwareTableProviderSignature,
            uint firmwareTableId,
            IntPtr firmwareTableBuffer,
            uint bufferSize);

        private static string ObserveVmUuid() {
            const uint RSMB = 0x52534D42;
            uint required = GetSystemFirmwareTable(RSMB, 0, IntPtr.Zero, 0);
            if (required < 32 || required > 16 * 1024 * 1024) {
                throw new InvalidOperationException(
                    "Raw SMBIOS table length was invalid.");
            }
            IntPtr buffer = Marshal.AllocHGlobal((int)required);
            try {
                uint written = GetSystemFirmwareTable(RSMB, 0, buffer, required);
                if (written != required) {
                    throw new InvalidOperationException(
                        "Raw SMBIOS table observation was incomplete.");
                }
                byte[] raw = new byte[(int)required];
                Marshal.Copy(buffer, raw, 0, (int)required);
                if (raw.Length < 8) {
                    throw new InvalidOperationException(
                        "Raw SMBIOS header was incomplete.");
                }
                byte major = raw[1];
                byte minor = raw[2];
                if (major < 2 || (major == 2 && minor < 6)) {
                    throw new InvalidOperationException(
                        "SMBIOS UUID byte order was unsupported.");
                }
                uint tableLength = BitConverter.ToUInt32(raw, 4);
                if (tableLength == 0 || tableLength > raw.Length - 8) {
                    throw new InvalidOperationException(
                        "Raw SMBIOS payload length was invalid.");
                }
                int offset = 8;
                int end = checked(8 + (int)tableLength);
                while (offset + 4 <= end) {
                    byte type = raw[offset];
                    int formattedLength = raw[offset + 1];
                    if (formattedLength < 4 || offset + formattedLength > end) {
                        throw new InvalidOperationException(
                            "SMBIOS structure length was invalid.");
                    }
                    if (type == 1) {
                        if (formattedLength < 24) {
                            throw new InvalidOperationException(
                                "SMBIOS system UUID field was absent.");
                        }
                        byte[] uuid = new byte[16];
                        Buffer.BlockCopy(raw, offset + 8, uuid, 0, 16);
                        bool allZero = true;
                        bool allOnes = true;
                        for (int index = 0; index < uuid.Length; index++) {
                            if (uuid[index] != 0) allZero = false;
                            if (uuid[index] != 0xFF) allOnes = false;
                        }
                        if (allZero || allOnes) {
                            throw new InvalidOperationException(
                                "SMBIOS system UUID was a placeholder.");
                        }
                        return new Guid(uuid).ToString("D").ToLowerInvariant();
                    }
                    int next = offset + formattedLength;
                    while (next + 1 < end &&
                        !(raw[next] == 0 && raw[next + 1] == 0)) {
                        next++;
                    }
                    if (next + 1 >= end) {
                        throw new InvalidOperationException(
                            "SMBIOS string-set terminator was absent.");
                    }
                    offset = next + 2;
                    if (type == 127) break;
                }
                throw new InvalidOperationException(
                    "SMBIOS system-information structure was absent.");
            }
            finally {
                Marshal.FreeHGlobal(buffer);
            }
        }

        public static SnapshotPlatformObservationV1 Observe() {
            ushort processMachine;
            ushort nativeMachine;
            if (!IsWow64Process2(GetCurrentProcess(), out processMachine, out nativeMachine)) {
                throw new InvalidOperationException("Native architecture observation failed.");
            }

            RTL_OSVERSIONINFOEX version = new RTL_OSVERSIONINFOEX();
            version.dwOSVersionInfoSize =
                (uint)Marshal.SizeOf(typeof(RTL_OSVERSIONINFOEX));
            if (RtlGetVersion(ref version) != 0) {
                throw new InvalidOperationException("Native Windows version observation failed.");
            }

            uint productInfoCode;
            if (!GetProductInfo(
                version.dwMajorVersion,
                version.dwMinorVersion,
                version.wServicePackMajor,
                version.wServicePackMinor,
                out productInfoCode)) {
                throw new InvalidOperationException("Windows edition observation failed.");
            }

            SnapshotPlatformObservationV1 result =
                new SnapshotPlatformObservationV1();
            result.WindowsMajorVersion = version.dwMajorVersion;
            result.WindowsBuildNumber = version.dwBuildNumber;
            result.WindowsProductType = version.wProductType;
            result.WindowsProductInfoCode = productInfoCode;
            result.NativeMachine = nativeMachine;
            result.Is64BitProcess = IntPtr.Size == 8;
            result.VmUuid = ObserveVmUuid();
            return result;
        }

        public static bool IsSupported(SnapshotPlatformObservationV1 value) {
            return
                value != null &&
                value.WindowsMajorVersion == 10 &&
                value.WindowsBuildNumber >= 22000 &&
                value.WindowsProductType == VER_NT_WORKSTATION &&
                value.WindowsProductInfoCode > 0 &&
                value.NativeMachine == IMAGE_FILE_MACHINE_AMD64 &&
                value.Is64BitProcess &&
                !String.IsNullOrEmpty(value.VmUuid);
        }
    }
}
'@ -ErrorAction Stop
        }

        $native = [Cddsi.D027.SnapshotPlatformBindingV1]::Observe()
        if (
            -not [Cddsi.D027.SnapshotPlatformBindingV1]::IsSupported($native) -or
            $PSVersionTable.PSVersion.Major -ne 5 -or
            $PSVersionTable.PSVersion.Minor -ne 1
        ) {
            throw 'The D-027 snapshot platform observation was outside the supported product matrix.'
        }
        $vmIdentitySha256 = Get-CddsiSupplyChainTextBindingToken -Text (
            'cddsi-d027-vm-identity-smbios-uuid-v1' + "`n" +
            'SmbiosUuid=' + [string]$native.VmUuid
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-snapshot-platform-observation-v2'
            WindowsMajorVersion = [long]$native.WindowsMajorVersion
            WindowsBuildNumber = [long]$native.WindowsBuildNumber
            WindowsProductType = 'Workstation'
            WindowsProductInfoCode = [long]$native.WindowsProductInfoCode
            NativeArchitecture = 'x64'
            ProcessArchitecture = 'x64'
            PowerShellVersion = '5.1'
            VmIdentitySha256 = $vmIdentitySha256
        }
    }
    catch {
        throw 'D-027 snapshot platform observation could not prove Windows 11 x64 Workstation and 64-bit Windows PowerShell 5.1.'
    }
}

function Get-CddsiD027GitSnapshotWorkloadBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$ExecutionArtifactSha256
    )

    $parsedRunId = [guid]::Empty
    if (
        -not [guid]::TryParse($RunId, [ref]$parsedRunId) -or
        $parsedRunId -eq [guid]::Empty -or
        $RunId -cne $parsedRunId.ToString('D') -or
        $ExecutionArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ExecutionArtifactSha256 -cmatch '^0{64}$'
    ) {
        throw 'D-027 Git snapshot workload binding inputs were invalid.'
    }
    $values = [ordered]@{
        ContractVersion = 'cddsi-d027-git-snapshot-workload-v1'
        RunId = $RunId
        Stage = 'VmAcceptance'
        EnvironmentTier = 'VmAcceptance'
        ArtifactProfile = 'VmAcceptance'
        Operation = 'InstallGitForWindows'
        ExecutionArtifactSha256 = $ExecutionArtifactSha256
    }
    $canonical = New-Object System.Collections.Generic.List[string]
    foreach ($name in $values.Keys) {
        $text = [string]$values[$name]
        $canonical.Add(('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text))
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Test-CddsiD027CanonicalBase64 {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [int]$MinimumBytes = 1,
        [int]$MaximumBytes = 8192
    )

    if (
        $Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Value) -or
        $Value.Length -gt 16384 -or
        $Value -notmatch '^[A-Za-z0-9+/]+={0,2}$'
    ) {
        return $false
    }
    try {
        $bytes = [Convert]::FromBase64String($Value)
        return (
            $bytes.Length -ge $MinimumBytes -and
            $bytes.Length -le $MaximumBytes -and
            [Convert]::ToBase64String($bytes) -ceq $Value
        )
    }
    catch {
        return $false
    }
}

function Get-CddsiD027SnapshotAuthorityKeySha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RsaModulusBase64,
        [Parameter(Mandatory = $true)][string]$RsaExponentBase64
    )

    if (
        -not (Test-CddsiD027CanonicalBase64 -Value $RsaModulusBase64 -MinimumBytes 256 -MaximumBytes 512) -or
        -not (Test-CddsiD027CanonicalBase64 -Value $RsaExponentBase64 -MinimumBytes 1 -MaximumBytes 8)
    ) {
        throw 'D-027 snapshot authority public key was not canonical RSA-2048-or-stronger material.'
    }
    $canonical = @(
        'cddsi-d027-snapshot-authority-public-key-v1'
        ('RsaModulusBase64={0}' -f $RsaModulusBase64)
        ('RsaExponentBase64={0}' -f $RsaExponentBase64)
    ) -join "`n"
    return Get-CddsiSupplyChainTextBindingToken -Text $canonical
}

function Get-CddsiD027SnapshotAuthorityPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    try {
        $policyPath = [System.IO.Path]::GetFullPath(
            (Join-Path $PSScriptRoot '..\config\d027-snapshot-authority.psd1')
        )
        $policyData = Import-PowerShellDataFile -LiteralPath $policyPath -ErrorAction Stop
        if (
            $policyData -isnot [System.Collections.IDictionary] -or
            @($policyData.Keys).Count -ne
                $script:CddsiD027SnapshotAuthorityPolicyFieldNames.Count -or
            ((@($policyData.Keys | Sort-Object) -join "`n") -cne
                (@($script:CddsiD027SnapshotAuthorityPolicyFieldNames | Sort-Object) -join "`n"))
        ) {
            throw 'Policy property set was invalid.'
        }
        $policy = [pscustomobject][ordered]@{
            SchemaVersion = $policyData.SchemaVersion
            ContractVersion = $policyData.ContractVersion
            Configured = $policyData.Configured
            AuthorityId = $policyData.AuthorityId
            SignatureAlgorithm = $policyData.SignatureAlgorithm
            AuthorityKeySha256 = $policyData.AuthorityKeySha256
            RsaModulusBase64 = $policyData.RsaModulusBase64
            RsaExponentBase64 = $policyData.RsaExponentBase64
        }
        if (
            -not (Test-CddsiSchemaVersionOne -Value $policy.SchemaVersion) -or
            $policy.ContractVersion -isnot [string] -or
            $policy.ContractVersion -cne 'cddsi-d027-snapshot-authority-policy-v1' -or
            $policy.Configured -isnot [bool] -or
            $policy.AuthorityId -isnot [string] -or
            $policy.SignatureAlgorithm -isnot [string] -or
            $policy.SignatureAlgorithm -cne 'RSA-SHA256-PKCS1-v1_5' -or
            $policy.AuthorityKeySha256 -isnot [string] -or
            $policy.RsaModulusBase64 -isnot [string] -or
            $policy.RsaExponentBase64 -isnot [string]
        ) {
            throw 'Policy schema was invalid.'
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = $policy.ContractVersion
            Configured = [bool]$policy.Configured
            AuthorityId = [string]$policy.AuthorityId
            SignatureAlgorithm = [string]$policy.SignatureAlgorithm
            AuthorityKeySha256 = [string]$policy.AuthorityKeySha256
            RsaModulusBase64 = [string]$policy.RsaModulusBase64
            RsaExponentBase64 = [string]$policy.RsaExponentBase64
        }
    }
    catch {
        throw 'The tracked D-027 external snapshot authority policy was unavailable or invalid.'
    }
}

function Get-CddsiD027ExternalSnapshotReceiptBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt
    )

    if (
        $null -eq $Receipt -or
        -not (Test-CddsiExactPropertySet -InputObject $Receipt -Expected $script:CddsiD027ExternalSnapshotReceiptFieldNames)
    ) {
        throw 'D-027 external snapshot receipt did not match the exact schema.'
    }
    $canonical = New-Object System.Collections.Generic.List[string]
    foreach ($name in @($script:CddsiD027ExternalSnapshotReceiptFieldNames | Where-Object {
        $_ -cne 'AuthoritySignatureBase64' -and $_ -cne 'ReceiptBindingToken'
    })) {
        $value = $Receipt.$name
        $text = if ($value -is [string]) {
            $value
        }
        elseif ($value -is [int] -or $value -is [long]) {
            [Convert]::ToString([long]$value, [Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            throw 'D-027 external snapshot receipt contained an unsupported field type.'
        }
        $canonical.Add(('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text))
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Test-CddsiD027ExternalSnapshotReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedExecutionArtifactSha256,
        [Parameter(Mandatory = $true)]$PlatformObservation,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)]$AuthorityPolicy
    )

    $rsa = $null
    $sha = $null
    try {
        $platformFields = @(
            'SchemaVersion',
            'ContractVersion',
            'WindowsMajorVersion',
            'WindowsBuildNumber',
            'WindowsProductType',
            'WindowsProductInfoCode',
            'NativeArchitecture',
            'ProcessArchitecture',
            'PowerShellVersion',
            'VmIdentitySha256'
        )
        if (
            $null -eq $Receipt -or
            $null -eq $AuthorityPolicy -or
            $null -eq $PlatformObservation -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $Receipt `
                -Expected $script:CddsiD027ExternalSnapshotReceiptFieldNames) -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $AuthorityPolicy `
                -Expected $script:CddsiD027SnapshotAuthorityPolicyFieldNames) -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $PlatformObservation `
                -Expected $platformFields)
        ) {
            return $false
        }

        if (
            -not (Test-CddsiSchemaVersionOne -Value $AuthorityPolicy.SchemaVersion) -or
            $AuthorityPolicy.ContractVersion -isnot [string] -or
            $AuthorityPolicy.ContractVersion -cne 'cddsi-d027-snapshot-authority-policy-v1' -or
            $AuthorityPolicy.Configured -isnot [bool] -or
            -not $AuthorityPolicy.Configured -or
            $AuthorityPolicy.AuthorityId -isnot [string] -or
            $AuthorityPolicy.AuthorityId -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._-]{2,63}$' -or
            $AuthorityPolicy.SignatureAlgorithm -isnot [string] -or
            $AuthorityPolicy.SignatureAlgorithm -cne 'RSA-SHA256-PKCS1-v1_5' -or
            $AuthorityPolicy.AuthorityKeySha256 -isnot [string] -or
            $AuthorityPolicy.AuthorityKeySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $AuthorityPolicy.AuthorityKeySha256 -cmatch '^0{64}$' -or
            -not (Test-CddsiD027CanonicalBase64 `
                -Value $AuthorityPolicy.RsaModulusBase64 `
                -MinimumBytes 256 `
                -MaximumBytes 512) -or
            -not (Test-CddsiD027CanonicalBase64 `
                -Value $AuthorityPolicy.RsaExponentBase64 `
                -MinimumBytes 1 `
                -MaximumBytes 8)
        ) {
            return $false
        }
        $calculatedAuthorityKeySha256 = Get-CddsiD027SnapshotAuthorityKeySha256 `
            -RsaModulusBase64 $AuthorityPolicy.RsaModulusBase64 `
            -RsaExponentBase64 $AuthorityPolicy.RsaExponentBase64
        if ($AuthorityPolicy.AuthorityKeySha256 -cne $calculatedAuthorityKeySha256) {
            return $false
        }

        $runId = [guid]::Empty
        if (
            -not (Test-CddsiSchemaVersionOne -Value $Receipt.SchemaVersion) -or
            $Receipt.ContractVersion -isnot [string] -or
            $Receipt.ContractVersion -cne 'cddsi-d027-external-clean-snapshot-receipt-v2' -or
            $Receipt.AuthorityId -isnot [string] -or
            $Receipt.AuthorityId -cne $AuthorityPolicy.AuthorityId -or
            $Receipt.AuthorityKeySha256 -isnot [string] -or
            $Receipt.AuthorityKeySha256 -cne $AuthorityPolicy.AuthorityKeySha256 -or
            $Receipt.SignatureAlgorithm -isnot [string] -or
            $Receipt.SignatureAlgorithm -cne $AuthorityPolicy.SignatureAlgorithm -or
            $Receipt.ExternalSource -isnot [string] -or
            $Receipt.ExternalSource -cne 'VmExternalHypervisor' -or
            $Receipt.RestoreState -isnot [string] -or
            $Receipt.RestoreState -cne 'CleanSnapshotRestored' -or
            $Receipt.VmDisposition -isnot [string] -or
            $Receipt.VmDisposition -cne 'Disposable' -or
            $Receipt.RunId -isnot [string] -or
            -not [guid]::TryParse($Receipt.RunId, [ref]$runId) -or
            $runId -eq [guid]::Empty -or
            $Receipt.RunId -cne $runId.ToString('D') -or
            $Receipt.RunId -cne $ExpectedRunId -or
            $Receipt.Stage -isnot [string] -or
            $Receipt.Stage -cne 'VmAcceptance' -or
            $Receipt.EnvironmentTier -isnot [string] -or
            $Receipt.EnvironmentTier -cne 'VmAcceptance' -or
            $Receipt.ArtifactProfile -isnot [string] -or
            $Receipt.ArtifactProfile -cne 'VmAcceptance' -or
            $Receipt.Operation -isnot [string] -or
            $Receipt.Operation -cne 'InstallGitForWindows'
        ) {
            return $false
        }

        if (
            -not (Test-CddsiSchemaVersionOne -Value $PlatformObservation.SchemaVersion) -or
            $PlatformObservation.ContractVersion -isnot [string] -or
            $PlatformObservation.ContractVersion -cne 'cddsi-d027-snapshot-platform-observation-v2' -or
            $ExpectedExecutionArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedExecutionArtifactSha256 -cmatch '^0{64}$' -or
            $Receipt.ExecutionArtifactSha256 -isnot [string] -or
            $Receipt.ExecutionArtifactSha256 -cne $ExpectedExecutionArtifactSha256 -or
            $Receipt.SnapshotIdentitySha256 -isnot [string] -or
            $Receipt.SnapshotIdentitySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.SnapshotIdentitySha256 -cmatch '^0{64}$' -or
            $Receipt.VmIdentitySha256 -isnot [string] -or
            $Receipt.VmIdentitySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.VmIdentitySha256 -cmatch '^0{64}$' -or
            $Receipt.RestorerIdentitySha256 -isnot [string] -or
            $Receipt.RestorerIdentitySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.RestorerIdentitySha256 -cmatch '^0{64}$' -or
            (($Receipt.WindowsMajorVersion -isnot [int]) -and
                ($Receipt.WindowsMajorVersion -isnot [long])) -or
            [long]$Receipt.WindowsMajorVersion -ne 10 -or
            (($Receipt.WindowsBuildNumber -isnot [int]) -and
                ($Receipt.WindowsBuildNumber -isnot [long])) -or
            [long]$Receipt.WindowsBuildNumber -lt 22000 -or
            $Receipt.WindowsProductType -isnot [string] -or
            $Receipt.WindowsProductType -cne 'Workstation' -or
            (($Receipt.WindowsProductInfoCode -isnot [int]) -and
                ($Receipt.WindowsProductInfoCode -isnot [long])) -or
            [long]$Receipt.WindowsProductInfoCode -le 0 -or
            $Receipt.NativeArchitecture -isnot [string] -or
            $Receipt.NativeArchitecture -cne 'x64' -or
            $Receipt.ProcessArchitecture -isnot [string] -or
            $Receipt.ProcessArchitecture -cne 'x64' -or
            $Receipt.PowerShellVersion -isnot [string] -or
            $Receipt.PowerShellVersion -cne '5.1' -or
            $PlatformObservation.VmIdentitySha256 -isnot [string] -or
            $PlatformObservation.VmIdentitySha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $PlatformObservation.VmIdentitySha256 -cmatch '^0{64}$' -or
            $Receipt.VmIdentitySha256 -cne $PlatformObservation.VmIdentitySha256 -or
            (($PlatformObservation.WindowsMajorVersion -isnot [int]) -and
                ($PlatformObservation.WindowsMajorVersion -isnot [long])) -or
            [long]$Receipt.WindowsMajorVersion -ne [long]$PlatformObservation.WindowsMajorVersion -or
            (($PlatformObservation.WindowsBuildNumber -isnot [int]) -and
                ($PlatformObservation.WindowsBuildNumber -isnot [long])) -or
            [long]$Receipt.WindowsBuildNumber -ne [long]$PlatformObservation.WindowsBuildNumber -or
            $PlatformObservation.WindowsProductType -isnot [string] -or
            $Receipt.WindowsProductType -cne $PlatformObservation.WindowsProductType -or
            (($PlatformObservation.WindowsProductInfoCode -isnot [int]) -and
                ($PlatformObservation.WindowsProductInfoCode -isnot [long])) -or
            [long]$Receipt.WindowsProductInfoCode -ne [long]$PlatformObservation.WindowsProductInfoCode -or
            $PlatformObservation.NativeArchitecture -isnot [string] -or
            $Receipt.NativeArchitecture -cne $PlatformObservation.NativeArchitecture -or
            $PlatformObservation.ProcessArchitecture -isnot [string] -or
            $Receipt.ProcessArchitecture -cne $PlatformObservation.ProcessArchitecture -or
            $PlatformObservation.PowerShellVersion -isnot [string] -or
            $Receipt.PowerShellVersion -cne $PlatformObservation.PowerShellVersion -or
            $Receipt.WorkloadBindingToken -isnot [string] -or
            $Receipt.WorkloadBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.WorkloadBindingToken -cmatch '^0{64}$' -or
            $Receipt.ReceiptBindingToken -isnot [string] -or
            $Receipt.ReceiptBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.ReceiptBindingToken -cmatch '^0{64}$' -or
            -not (Test-CddsiD027CanonicalBase64 `
                -Value $Receipt.AuthoritySignatureBase64 `
                -MinimumBytes 256 `
                -MaximumBytes 512)
        ) {
            return $false
        }

        foreach ($timestamp in @(
            $Receipt.RestoreCompletedAtUtc,
            $Receipt.IssuedAtUtc,
            $Receipt.ExpiresAtUtc,
            $ValidationTimeUtc
        )) {
            if (
                $timestamp -isnot [string] -or
                $timestamp -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
                -not (Test-CddsiUtcTimestampValue -Value $timestamp)
            ) {
                return $false
            }
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $restoreTime = [DateTimeOffset]::ParseExact(
            $Receipt.RestoreCompletedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $issuedTime = [DateTimeOffset]::ParseExact(
            $Receipt.IssuedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $expiresTime = [DateTimeOffset]::ParseExact(
            $Receipt.ExpiresAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $validationTime = [DateTimeOffset]::ParseExact(
            $ValidationTimeUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        if (
            $restoreTime -gt $issuedTime.AddSeconds(30) -or
            $issuedTime -gt $validationTime.AddSeconds(30) -or
            $expiresTime -le $issuedTime -or
            ($issuedTime - $restoreTime).TotalMinutes -gt 10 -or
            ($expiresTime - $issuedTime).TotalMinutes -gt 90 -or
            $validationTime -gt $expiresTime -or
            ($validationTime - $restoreTime).TotalMinutes -gt 90
        ) {
            return $false
        }

        $expectedWorkloadBindingToken = Get-CddsiD027GitSnapshotWorkloadBindingToken `
            -RunId $ExpectedRunId `
            -ExecutionArtifactSha256 $ExpectedExecutionArtifactSha256
        if ($Receipt.WorkloadBindingToken -cne $expectedWorkloadBindingToken) {
            return $false
        }
        $calculatedReceiptBindingToken =
            Get-CddsiD027ExternalSnapshotReceiptBindingToken -Receipt $Receipt
        if ($Receipt.ReceiptBindingToken -cne $calculatedReceiptBindingToken) {
            return $false
        }

        $modulus = [Convert]::FromBase64String($AuthorityPolicy.RsaModulusBase64)
        $exponent = [Convert]::FromBase64String($AuthorityPolicy.RsaExponentBase64)
        $signature = [Convert]::FromBase64String($Receipt.AuthoritySignatureBase64)
        if ($signature.Length -ne $modulus.Length) {
            return $false
        }
        $parameters = New-Object System.Security.Cryptography.RSAParameters
        $parameters.Modulus = $modulus
        $parameters.Exponent = $exponent
        $rsa = [System.Security.Cryptography.RSA]::Create()
        $rsa.ImportParameters($parameters)
        $signatureText = '{0}{1}{2}' -f
            $script:CddsiD027SnapshotReceiptSignatureDomain,
            "`n",
            $Receipt.ReceiptBindingToken
        $signatureBytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes(
            $signatureText
        )
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $signatureHash = $sha.ComputeHash($signatureBytes)
        return $rsa.VerifyHash(
            $signatureHash,
            $signature,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $rsa) { $rsa.Dispose() }
    }
}

function Get-CddsiD027SnapshotReceiptHeldFileObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][System.IO.FileStream]$Stream
    )

    if ($null -eq ('Cddsi.D027.SnapshotReceiptFileV1' -as [type])) {
        Add-Type -TypeDefinition @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Cddsi.D027 {
    public sealed class SnapshotReceiptFileObservationV1 {
        public string FinalPath;
        public uint NumberOfLinks;
        public string FileSystemName;
    }

    public static class SnapshotReceiptFileV1 {
        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME {
            internal uint Low;
            internal uint High;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION {
            internal uint FileAttributes;
            internal FILETIME CreationTime;
            internal FILETIME LastAccessTime;
            internal FILETIME LastWriteTime;
            internal uint VolumeSerialNumber;
            internal uint FileSizeHigh;
            internal uint FileSizeLow;
            internal uint NumberOfLinks;
            internal uint FileIndexHigh;
            internal uint FileIndexLow;
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            SafeFileHandle handle,
            StringBuilder path,
            uint capacity,
            uint flags);

        [DllImport("kernel32.dll", SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandle(
            SafeFileHandle handle,
            out BY_HANDLE_FILE_INFORMATION information);

        [DllImport("kernel32.dll", CharSet = CharSet.Unicode, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetVolumeInformationByHandleW(
            SafeFileHandle handle,
            StringBuilder volumeName,
            uint volumeNameCapacity,
            out uint volumeSerialNumber,
            out uint maximumComponentLength,
            out uint fileSystemFlags,
            StringBuilder fileSystemName,
            uint fileSystemNameCapacity);

        public static SnapshotReceiptFileObservationV1 Observe(
            SafeFileHandle handle) {
            if (handle == null || handle.IsInvalid || handle.IsClosed) {
                throw new InvalidOperationException("Receipt handle was invalid.");
            }
            uint capacity = 32768;
            StringBuilder path = new StringBuilder((int)capacity);
            uint length = GetFinalPathNameByHandleW(handle, path, capacity, 0);
            if (length == 0 || length >= capacity) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            BY_HANDLE_FILE_INFORMATION information;
            if (!GetFileInformationByHandle(handle, out information)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            StringBuilder volumeName = new StringBuilder(261);
            StringBuilder fileSystemName = new StringBuilder(261);
            uint volumeSerialNumber;
            uint maximumComponentLength;
            uint fileSystemFlags;
            if (!GetVolumeInformationByHandleW(
                handle,
                volumeName,
                (uint)volumeName.Capacity,
                out volumeSerialNumber,
                out maximumComponentLength,
                out fileSystemFlags,
                fileSystemName,
                (uint)fileSystemName.Capacity)) {
                throw new Win32Exception(Marshal.GetLastWin32Error());
            }
            SnapshotReceiptFileObservationV1 result =
                new SnapshotReceiptFileObservationV1();
            result.FinalPath = path.ToString();
            result.NumberOfLinks = information.NumberOfLinks;
            result.FileSystemName = fileSystemName.ToString();
            return result;
        }
    }
}
'@ -ErrorAction Stop
    }
    $native = [Cddsi.D027.SnapshotReceiptFileV1]::Observe($Stream.SafeFileHandle)
    $finalPath = [string]$native.FinalPath
    if ($finalPath.StartsWith('\\?\UNC\', [StringComparison]::OrdinalIgnoreCase)) {
        $finalPath = '\\' + $finalPath.Substring(8)
    }
    elseif ($finalPath.StartsWith('\\?\', [StringComparison]::OrdinalIgnoreCase)) {
        $finalPath = $finalPath.Substring(4)
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        FinalPath = [System.IO.Path]::GetFullPath($finalPath)
        NumberOfLinks = [long]$native.NumberOfLinks
        FileSystemName = [string]$native.FileSystemName
    }
}

function Read-CddsiD027ExternalSnapshotReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ExpectedReceiptSha256
    )

    Assert-CddsiD027GitLiveBootstrapContext -ExecutionContext $Context | Out-Null
    $stream = $null
    $hasher = $null
    try {
        if (
            $ExpectedReceiptSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedReceiptSha256 -cmatch '^0{64}$' -or
            [string]::IsNullOrWhiteSpace($ReceiptPath) -or
            $ReceiptPath.IndexOfAny([char[]]@('*', '?', [char]0)) -ge 0 -or
            -not [System.IO.Path]::IsPathRooted($ReceiptPath) -or
            ($ReceiptPath.Length -gt 2 -and $ReceiptPath.Substring(2).Contains(':'))
        ) {
            throw 'Receipt input was invalid.'
        }
        $fullPath = [System.IO.Path]::GetFullPath($ReceiptPath)
        $tempPath = [System.IO.Path]::GetFullPath([string]$Context.Paths.Temp).TrimEnd('\')
        if (
            -not [string]::Equals(
                [System.IO.Path]::GetDirectoryName($fullPath),
                $tempPath,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not [string]::Equals(
                [System.IO.Path]::GetExtension($fullPath),
                '.json',
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            [System.IO.Path]::GetFileName($fullPath) -cnotmatch
                '^d027-external-snapshot-receipt(?:-[a-f0-9]{64})?\.json$'
        ) {
            throw 'Receipt target was outside the product temp root.'
        }
        $stream = New-Object System.IO.FileStream(
            $fullPath,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::None,
            4096,
            [System.IO.FileOptions]::SequentialScan
        )
        $heldFile = Get-CddsiD027SnapshotReceiptHeldFileObservation `
            -ExecutionContext $Context `
            -Stream $stream
        $attributes = [System.IO.File]::GetAttributes($fullPath)
        if (
            -not [string]::Equals(
                $heldFile.FinalPath,
                $fullPath,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            $heldFile.NumberOfLinks -ne 1 -or
            $heldFile.FileSystemName -cne 'NTFS' -or
            ($attributes -band [System.IO.FileAttributes]::Directory) -ne 0 -or
            ($attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
        ) {
            throw 'Receipt target identity was unsupported.'
        }
        if (
            $stream.Length -le 0 -or
            $stream.Length -gt $script:CddsiD027ExternalSnapshotReceiptMaximumBytes
        ) {
            throw 'Receipt length was invalid.'
        }
        $bytes = New-Object byte[] ([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) {
                throw 'Receipt read was truncated.'
            }
            $offset += $read
        }
        if (
            $bytes.Length -ge 3 -and
            $bytes[0] -eq 0xEF -and
            $bytes[1] -eq 0xBB -and
            $bytes[2] -eq 0xBF
        ) {
            throw 'Receipt encoding was not canonical.'
        }
        $hasher = [System.Security.Cryptography.SHA256]::Create()
        $actualSha256 = [BitConverter]::ToString(
            $hasher.ComputeHash($bytes)
        ).Replace('-', '').ToLowerInvariant()
        if ($actualSha256 -cne $ExpectedReceiptSha256) {
            throw 'Receipt bytes did not match the independently supplied hash.'
        }
        $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $content = $utf8.GetString($bytes)
        $receipt = $content | ConvertFrom-Json -ErrorAction Stop
        if ($null -eq $receipt -or $receipt -is [System.Array]) {
            throw 'Receipt JSON root was invalid.'
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-external-snapshot-receipt-read-v1'
            Receipt = $receipt
            ReceiptSha256 = $actualSha256
            ReceiptLengthBytes = [long]$bytes.Length
        }
    }
    catch {
        throw 'D-027 external snapshot receipt could not be read and validated from the exact product-temp file.'
    }
    finally {
        if ($null -ne $hasher) { $hasher.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Enable-CddsiD027GitLiveSessionAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ExpectedReceiptSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedExecutionArtifactSha256
    )

    $script:CddsiD027GitLiveSessionAuthorization = $null
    try {
        Assert-CddsiD027GitLiveBootstrapContext -ExecutionContext $Context | Out-Null
        if (
            $Context.Stage -isnot [string] -or $Context.Stage -cne 'VmAcceptance' -or
            $Context.EnvironmentTier -isnot [string] -or
            $Context.EnvironmentTier -cne 'VmAcceptance' -or
            $ExpectedExecutionArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedExecutionArtifactSha256 -cmatch '^0{64}$'
        ) {
            throw 'The D-027 snapshot authorization bootstrap context was invalid.'
        }
        $readResult = Read-CddsiD027ExternalSnapshotReceipt `
            -ExecutionContext $Context `
            -ReceiptPath $ReceiptPath `
            -ExpectedReceiptSha256 $ExpectedReceiptSha256
        $platformObservation = Get-CddsiD027SnapshotPlatformObservation -ExecutionContext $Context
        $validationTimeUtc = [DateTimeOffset]::UtcNow.ToString(
            'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture
        )
        $authorityPolicy =
            Get-CddsiD027SnapshotAuthorityPolicy -ExecutionContext $Context
        if (-not (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $readResult.Receipt `
            -ExpectedRunId $Context.RunId `
            -ExpectedExecutionArtifactSha256 $ExpectedExecutionArtifactSha256 `
            -PlatformObservation $platformObservation `
            -ValidationTimeUtc $validationTimeUtc `
            -AuthorityPolicy $authorityPolicy)) {
            throw 'The D-027 snapshot receipt did not authorize this exact workload.'
        }

        $receipt = $readResult.Receipt
        $authorization = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-git-live-signed-authorization-v2'
            Receipt = $receipt
            ReceiptSha256 = $readResult.ReceiptSha256
            ReceiptLengthBytes = [long]$readResult.ReceiptLengthBytes
            ExpectedExecutionArtifactSha256 = $ExpectedExecutionArtifactSha256
            AuthorizedAtUtc = $validationTimeUtc
            InitialPlatformObservation = $platformObservation
        }
        $script:CddsiD027GitLiveSessionAuthorization = $authorization
        $safeData = [pscustomobject][ordered]@{
            SchemaVersion = 1
            AuthorizationStatus = 'Active'
            AuthorityId = $receipt.AuthorityId
            AuthorityKeySha256 = $receipt.AuthorityKeySha256
            SignatureAlgorithm = $receipt.SignatureAlgorithm
            RunId = $receipt.RunId
            Stage = $receipt.Stage
            ArtifactProfile = $receipt.ArtifactProfile
            Operation = $receipt.Operation
            ReceiptSha256 = $authorization.ReceiptSha256
            ReceiptBindingToken = $receipt.ReceiptBindingToken
            WorkloadBindingToken = $receipt.WorkloadBindingToken
            ExpiresAtUtc = $receipt.ExpiresAtUtc
        }
        return New-CddsiOperationResult `
            -Operation 'EnableD027GitLiveSessionAuthorization' `
            -Status 'SUCCEEDED' `
            -Mode Live `
            -MessageSafe 'An exact externally signed clean-snapshot receipt was verified against the pinned D-027 VM-operator public key for this Git VmAcceptance workload.' `
            -Data $safeData
    }
    catch {
        $script:CddsiD027GitLiveSessionAuthorization = $null
        return New-CddsiOperationResult `
            -Operation 'EnableD027GitLiveSessionAuthorization' `
            -Status 'ACTION_REQUIRED' `
            -Mode Live `
            -ErrorCode 'D027_EXTERNAL_SNAPSHOT_AUTHORIZATION_INVALID' `
            -MessageSafe 'A fresh exact VM-external clean-snapshot receipt signed by the configured pinned authority is required before any D-027 Git Live operation.'
    }
}

function Clear-CddsiD027GitLiveSessionAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiD027GitLiveBootstrapContext -ExecutionContext $Context | Out-Null
    $script:CddsiD027GitLiveSessionAuthorization = $null
    return New-CddsiOperationResult `
        -Operation 'ClearD027GitLiveSessionAuthorization' `
        -Status 'SUCCEEDED' `
        -Mode Live `
        -MessageSafe 'The process-scoped D-027 Git Live authorization was cleared.'
}

function Get-CddsiD027GitWinVerifyTrustResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$FilePath
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null

    $newResult = {
        param(
            [Parameter(Mandatory = $true)][bool]$Trusted,
            [Parameter(Mandatory = $true)][string]$Status,
            [AllowNull()][string]$NativeStatusHex
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            Trusted = $Trusted
            Status = $Status
            NativeStatusHex = $NativeStatusHex
            RevocationMode = 'NotChecked'
        }
    }

    try {
        if (
            [string]::IsNullOrWhiteSpace($FilePath) -or
            $FilePath.IndexOfAny([char[]]@('*', '?', [char]0)) -ge 0 -or
            -not [System.IO.Path]::IsPathRooted($FilePath)
        ) {
            return & $newResult $false 'InvalidInput' $null
        }
        $path = [System.IO.Path]::GetFullPath($FilePath)
        if (
            -not [string]::Equals(
                [System.IO.Path]::GetExtension($path),
                '.exe',
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not [System.IO.File]::Exists($path)
        ) {
            return & $newResult $false 'FileUnavailable' $null
        }

        if ($null -eq ('Cddsi.D027.WinVerifyTrustPolicy' -as [type])) {
            Add-Type -TypeDefinition @'
using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;

namespace Cddsi.D027 {
    public sealed class WinVerifyTrustPolicyResult {
        public bool Trusted;
        public string Status;
        public string NativeStatusHex;
        public string RevocationMode;
    }

    public static class WinVerifyTrustPolicy {
        private const uint WTD_UI_NONE = 2;
        private const uint WTD_REVOKE_NONE = 0;
        private const uint WTD_CHOICE_FILE = 1;
        private const uint WTD_STATEACTION_VERIFY = 1;
        private const uint WTD_STATEACTION_CLOSE = 2;
        private const uint WTD_CACHE_ONLY_URL_RETRIEVAL = 0x00001000;

        private static readonly Guid WinTrustActionGenericVerifyV2 =
            new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
        private static readonly IntPtr InvalidWindowHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WINTRUST_FILE_INFO {
            internal uint cbStruct;
            [MarshalAs(UnmanagedType.LPWStr)]
            internal string pcwszFilePath;
            internal IntPtr hFile;
            internal IntPtr pgKnownSubject;
        }

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct WINTRUST_DATA {
            internal uint cbStruct;
            internal IntPtr pPolicyCallbackData;
            internal IntPtr pSIPClientData;
            internal uint dwUIChoice;
            internal uint fdwRevocationChecks;
            internal uint dwUnionChoice;
            internal IntPtr pFile;
            internal uint dwStateAction;
            internal IntPtr hWVTStateData;
            internal IntPtr pwszURLReference;
            internal uint dwProvFlags;
            internal uint dwUIContext;
        }

        [DllImport("wintrust.dll", ExactSpelling = true, CharSet = CharSet.Unicode)]
        private static extern int WinVerifyTrust(
            IntPtr hwnd,
            [In] ref Guid actionId,
            ref WINTRUST_DATA trustData);

        private static string GetStatus(int nativeStatus) {
            uint value = unchecked((uint)nativeStatus);
            switch (value) {
                case 0x00000000U: return "Trusted";
                case 0x800B0100U: return "NoSignature";
                case 0x800B0003U: return "UnsupportedSubject";
                case 0x800B0001U: return "ProviderUnavailable";
                case 0x800B0111U: return "ExplicitDistrust";
                case 0x800B0004U: return "Untrusted";
                case 0x80096010U: return "BadDigest";
                case 0x800B010CU: return "Revoked";
                case 0x800B0109U: return "UntrustedRoot";
                case 0x800B010AU: return "ChainInvalid";
                case 0x800B0101U: return "Expired";
                case 0x80092013U: return "RevocationOffline";
                case 0x80092012U: return "RevocationUnavailable";
                case 0x80096005U: return "TimestampInvalid";
                default: return "PolicyRejected";
            }
        }

        public static WinVerifyTrustPolicyResult VerifyFile(string filePath) {
            IntPtr fileInfoPointer = IntPtr.Zero;
            bool fileInfoMarshaled = false;
            bool verifyAttempted = false;
            int nativeStatus = unchecked((int)0x800B0004U);
            Guid actionId = WinTrustActionGenericVerifyV2;
            WINTRUST_DATA trustData = new WINTRUST_DATA();

            using (FileStream file = new FileStream(
                filePath,
                FileMode.Open,
                FileAccess.Read,
                FileShare.Read)) {
                WINTRUST_FILE_INFO fileInfo = new WINTRUST_FILE_INFO();
                fileInfo.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
                fileInfo.pcwszFilePath = filePath;
                fileInfo.hFile = file.SafeFileHandle.DangerousGetHandle();
                fileInfo.pgKnownSubject = IntPtr.Zero;

                try {
                    fileInfoPointer = Marshal.AllocHGlobal(
                        Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
                    Marshal.StructureToPtr(fileInfo, fileInfoPointer, false);
                    fileInfoMarshaled = true;

                    trustData.cbStruct = (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
                    trustData.pPolicyCallbackData = IntPtr.Zero;
                    trustData.pSIPClientData = IntPtr.Zero;
                    trustData.dwUIChoice = WTD_UI_NONE;
                    trustData.fdwRevocationChecks = WTD_REVOKE_NONE;
                    trustData.dwUnionChoice = WTD_CHOICE_FILE;
                    trustData.pFile = fileInfoPointer;
                    trustData.dwStateAction = WTD_STATEACTION_VERIFY;
                    trustData.hWVTStateData = IntPtr.Zero;
                    trustData.pwszURLReference = IntPtr.Zero;
                    trustData.dwProvFlags = WTD_CACHE_ONLY_URL_RETRIEVAL;
                    trustData.dwUIContext = 0;

                    verifyAttempted = true;
                    nativeStatus = WinVerifyTrust(
                        InvalidWindowHandle,
                        ref actionId,
                        ref trustData);
                }
                finally {
                    if (verifyAttempted) {
                        try {
                            trustData.dwStateAction = WTD_STATEACTION_CLOSE;
                            WinVerifyTrust(
                                InvalidWindowHandle,
                                ref actionId,
                                ref trustData);
                        }
                        catch {
                        }
                    }
                    if (fileInfoMarshaled) {
                        Marshal.DestroyStructure(
                            fileInfoPointer,
                            typeof(WINTRUST_FILE_INFO));
                    }
                    if (fileInfoPointer != IntPtr.Zero) {
                        Marshal.FreeHGlobal(fileInfoPointer);
                    }
                }
            }

            WinVerifyTrustPolicyResult result = new WinVerifyTrustPolicyResult();
            result.Trusted = nativeStatus == 0;
            result.Status = GetStatus(nativeStatus);
            result.NativeStatusHex = "0x" +
                unchecked((uint)nativeStatus).ToString("X8", CultureInfo.InvariantCulture);
            result.RevocationMode = "NotChecked";
            return result;
        }
    }
}
'@ -ErrorAction Stop
        }

        $nativeResult = [Cddsi.D027.WinVerifyTrustPolicy]::VerifyFile($path)
        if (
            $null -eq $nativeResult -or
            $nativeResult.Trusted -isnot [bool] -or
            [string]::IsNullOrWhiteSpace([string]$nativeResult.Status) -or
            [string]$nativeResult.NativeStatusHex -notmatch '^0x[0-9A-F]{8}$' -or
            [string]$nativeResult.RevocationMode -cne 'NotChecked'
        ) {
            return & $newResult $false 'VerificationUnavailable' $null
        }
        return & $newResult ([bool]$nativeResult.Trusted) ([string]$nativeResult.Status) ([string]$nativeResult.NativeStatusHex)
    }
    catch {
        return & $newResult $false 'VerificationUnavailable' $null
    }
}

function Assert-CddsiD027GitLiveBootstrapContext {
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
                $tempDrive.DriveFormat -cne 'NTFS' -or
                -not [System.IO.Directory]::Exists($tempPath)
            ) {
                throw 'Product temp was not an existing fixed NTFS directory.'
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
    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null
    return $true
}

function Assert-CddsiD027GitLiveContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiD027GitLiveBootstrapContext -ExecutionContext $Context | Out-Null
    $authorization = $script:CddsiD027GitLiveSessionAuthorization
    try {
        if (
            $null -eq $authorization -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $authorization `
                -Expected $script:CddsiD027GitLiveSessionAuthorizationFieldNames) -or
            -not (Test-CddsiSchemaVersionOne -Value $authorization.SchemaVersion) -or
            $authorization.ContractVersion -isnot [string] -or
            $authorization.ContractVersion -cne 'cddsi-d027-git-live-signed-authorization-v2' -or
            $null -eq $authorization.Receipt -or
            $Context.RunId -isnot [string] -or
            $Context.Stage -isnot [string] -or
            $Context.Stage -cne 'VmAcceptance' -or
            $Context.EnvironmentTier -isnot [string] -or
            $Context.EnvironmentTier -cne 'VmAcceptance' -or
            $authorization.ReceiptSha256 -isnot [string] -or
            $authorization.ReceiptSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $authorization.ReceiptSha256 -cmatch '^0{64}$' -or
            (($authorization.ReceiptLengthBytes -isnot [int]) -and
                ($authorization.ReceiptLengthBytes -isnot [long])) -or
            [long]$authorization.ReceiptLengthBytes -le 0 -or
            [long]$authorization.ReceiptLengthBytes -gt
                $script:CddsiD027ExternalSnapshotReceiptMaximumBytes -or
            $authorization.ExpectedExecutionArtifactSha256 -isnot [string] -or
            $authorization.ExpectedExecutionArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $authorization.ExpectedExecutionArtifactSha256 -cmatch '^0{64}$' -or
            $authorization.AuthorizedAtUtc -isnot [string] -or
            $authorization.AuthorizedAtUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
            -not (Test-CddsiUtcTimestampValue -Value $authorization.AuthorizedAtUtc) -or
            $null -eq $authorization.InitialPlatformObservation
        ) {
            throw 'Authorization state was invalid.'
        }
        if (
            $Context.Providers.Kind -ceq 'LiveReadOnly' -and
            (
                $Context.Providers.RunId -cne $Context.RunId -or
                $Context.Providers.Stage -cne 'VmAcceptance' -or
                $Context.Providers.EnvironmentTier -cne 'VmAcceptance' -or
                $Context.Providers.ArtifactProfile -cne 'VmAcceptance'
            )
        ) {
            throw 'Loaded provider profile was not bound to the authorization.'
        }
        $authorityPolicy =
            Get-CddsiD027SnapshotAuthorityPolicy -ExecutionContext $Context
        $platformObservation =
            Get-CddsiD027SnapshotPlatformObservation -ExecutionContext $Context
        $validationTimeUtc = [DateTimeOffset]::UtcNow.ToString(
            'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture
        )
        if (-not (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $authorization.Receipt `
            -ExpectedRunId $Context.RunId `
            -ExpectedExecutionArtifactSha256 $authorization.ExpectedExecutionArtifactSha256 `
            -PlatformObservation $platformObservation `
            -ValidationTimeUtc $validationTimeUtc `
            -AuthorityPolicy $authorityPolicy)) {
            throw 'Signed authorization receipt was invalid, stale or no longer platform-bound.'
        }
    }
    catch {
        $script:CddsiD027GitLiveSessionAuthorization = $null
        throw 'D-027 Git Live requires a fresh process-scoped authorization from an exact VM-external clean-snapshot receipt signed by the pinned authority and bound to this VmAcceptance run and workload.'
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
        $winTrustResult = Get-CddsiD027GitWinVerifyTrustResult `
            -ExecutionContext $Context `
            -FilePath $path
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
    $signatureType = [string]$signature.SignatureType
    $signerSubject = if ($null -eq $signature.SignerCertificate) { '' } else { [string]$signature.SignerCertificate.Subject }
    $signerThumbprint = if ($null -eq $signature.SignerCertificate) { '' } else { ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant() }
    $reasonCodes = New-Object System.Collections.Generic.List[string]
    if ($peMachine -cne 'x64') { $reasonCodes.Add('GIT_COMPONENT_ARCHITECTURE_UNSUPPORTED') }
    if (
        $authenticodeStatus -cne 'Valid' -or
        $signatureType -cne 'Authenticode' -or
        $null -eq $signature.TimeStamperCertificate
    ) {
        $reasonCodes.Add('GIT_COMPONENT_AUTHENTICODE_INVALID')
    }
    if (-not $winTrustResult.Trusted) { $reasonCodes.Add('GIT_COMPONENT_CHAIN_UNTRUSTED') }
    if (
        -not [regex]::IsMatch(
            $signerSubject,
            $script:CddsiGitExecutableSignerSubjectPattern,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        ) -or
        $signerThumbprint -notmatch '^[a-f0-9]{40}$'
    ) {
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
        SignatureType = $signatureType
        ChainTrusted = [bool]$winTrustResult.Trusted
        ChainRevocationMode = $winTrustResult.RevocationMode
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

function ConvertTo-CddsiD027NormalizedGitHubReleaseDocument {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ReleaseDocument
    )

    if ($null -eq $ReleaseDocument) {
        throw 'GitHub release response was empty.'
    }
    foreach ($name in @('tag_name', 'draft', 'prerelease', 'immutable', 'html_url', 'assets')) {
        if ($null -eq $ReleaseDocument.PSObject.Properties[$name]) {
            throw 'GitHub release response omitted a required field.'
        }
    }
    if (
        $ReleaseDocument.tag_name -isnot [string] -or
        $ReleaseDocument.draft -isnot [bool] -or
        $ReleaseDocument.prerelease -isnot [bool] -or
        $ReleaseDocument.immutable -isnot [bool] -or -not $ReleaseDocument.immutable -or
        $ReleaseDocument.html_url -isnot [string] -or
        $null -eq $ReleaseDocument.assets
    ) {
        throw 'GitHub release response field types were invalid.'
    }

    $assets = @($ReleaseDocument.assets)
    if ($assets.Count -lt 1 -or $assets.Count -gt 256) {
        throw 'GitHub release response asset count was outside the allowed range.'
    }
    $normalizedAssets = New-Object System.Collections.Generic.List[object]
    foreach ($asset in $assets) {
        foreach ($name in @('name', 'browser_download_url', 'size', 'state', 'content_type', 'digest')) {
            if ($null -eq $asset -or $null -eq $asset.PSObject.Properties[$name]) {
                throw 'GitHub release asset omitted a required field.'
            }
        }
        if (
            $asset.name -isnot [string] -or
            $asset.browser_download_url -isnot [string] -or
            (($asset.size -isnot [int]) -and ($asset.size -isnot [long])) -or
            $asset.state -isnot [string] -or
            $asset.content_type -isnot [string] -or
            ($null -ne $asset.digest -and $asset.digest -isnot [string])
        ) {
            throw 'GitHub release asset field types were invalid.'
        }
        $normalizedAssets.Add([pscustomobject][ordered]@{
            name                 = [string]$asset.name
            browser_download_url = [string]$asset.browser_download_url
            size                 = [long]$asset.size
            state                = [string]$asset.state
            content_type         = [string]$asset.content_type
            digest               = if ($null -eq $asset.digest) { $null } else { [string]$asset.digest }
        })
    }

    return [pscustomobject][ordered]@{
        tag_name  = [string]$ReleaseDocument.tag_name
        draft      = [bool]$ReleaseDocument.draft
        prerelease = [bool]$ReleaseDocument.prerelease
        immutable  = [bool]$ReleaseDocument.immutable
        html_url   = [string]$ReleaseDocument.html_url
        assets     = $normalizedAssets.ToArray()
    }
}

function Get-CddsiD027GitDownloadReceiptBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt
    )

    $fields = @(
        'SchemaVersion', 'ContractVersion', 'RunId', 'ArtifactProfile', 'ArtifactType',
        'DescriptorId', 'MetadataBindingToken', 'DestinationPathBindingToken',
        'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes', 'SourceObservation'
    )
    $validNames = (
        (Test-CddsiExactPropertySet -InputObject $Receipt -Expected $fields) -or
        (Test-CddsiExactPropertySet -InputObject $Receipt -Expected @($fields + 'ReceiptBindingToken'))
    )
    if (-not $validNames) {
        throw 'Git download receipt does not match the binding schema.'
    }
    if ($null -eq $Receipt.SourceObservation) {
        throw 'Git download receipt source observation was missing.'
    }
    $sourceBinding = [string]$Receipt.SourceObservation.SourceObservationBindingToken
    $parts = @(
        'SchemaVersion={0}' -f [Convert]::ToString($Receipt.SchemaVersion, [Globalization.CultureInfo]::InvariantCulture)
        'ContractVersion={0}' -f [string]$Receipt.ContractVersion
        'RunId={0}' -f [string]$Receipt.RunId
        'ArtifactProfile={0}' -f [string]$Receipt.ArtifactProfile
        'ArtifactType={0}' -f [string]$Receipt.ArtifactType
        'DescriptorId={0}' -f [string]$Receipt.DescriptorId
        'MetadataBindingToken={0}' -f [string]$Receipt.MetadataBindingToken
        'DestinationPathBindingToken={0}' -f [string]$Receipt.DestinationPathBindingToken
        'FileIdentityToken={0}' -f [string]$Receipt.FileIdentityToken
        'ArtifactSha256={0}' -f [string]$Receipt.ArtifactSha256
        'ArtifactSizeBytes={0}' -f [Convert]::ToString($Receipt.ArtifactSizeBytes, [Globalization.CultureInfo]::InvariantCulture)
        'SourceObservationBindingToken={0}' -f $sourceBinding
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($parts -join "`n")
}

function New-CddsiD027GitDownloadReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$FileIdentityToken,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller)) {
        throw 'Git download receipt requires an exact artifact descriptor.'
    }
    if ($FileIdentityToken -notmatch '^[a-f0-9]{64}$') {
        throw 'Git download receipt file identity token was invalid.'
    }
    if (-not (Test-CddsiSourceObservation -Observation $SourceObservation -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller -ExpectedRunId $ExpectedRunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'Git download receipt source observation was invalid.'
    }
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion                = 1
        ContractVersion              = 'cddsi-d027-git-download-receipt-v1'
        RunId                       = $ExpectedRunId
        ArtifactProfile             = $ArtifactProfile
        ArtifactType                = 'GitForWindowsInstaller'
        DescriptorId                = $ArtifactDescriptor.DescriptorId
        MetadataBindingToken        = $ArtifactDescriptor.MetadataBindingToken
        DestinationPathBindingToken = Get-CddsiPathBindingToken -Path $DestinationPath
        FileIdentityToken            = $FileIdentityToken
        ArtifactSha256               = $ArtifactDescriptor.ExpectedArtifactSha256.ToLowerInvariant()
        ArtifactSizeBytes            = [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes
        SourceObservation            = $SourceObservation
    }
    $result = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    $result['ReceiptBindingToken'] = Get-CddsiD027GitDownloadReceiptBindingToken -Receipt $withoutBinding
    return [pscustomobject]$result
}

function Test-CddsiD027GitDownloadReceipt {
    [CmdletBinding()]
    param(
        [AllowNull()]$Receipt,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ExpectedFileIdentityToken,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'RunId', 'ArtifactProfile', 'ArtifactType',
        'DescriptorId', 'MetadataBindingToken', 'DestinationPathBindingToken',
        'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes', 'SourceObservation',
        'ReceiptBindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Receipt -Expected $required)) { return $false }
    if (
        -not (Test-CddsiSchemaVersionOne -Value $Receipt.SchemaVersion) -or
        $Receipt.ContractVersion -isnot [string] -or
        $Receipt.ContractVersion -cne 'cddsi-d027-git-download-receipt-v1' -or
        -not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller) -or
        $Receipt.RunId -isnot [string] -or $Receipt.RunId -cne $ExpectedRunId -or
        $Receipt.ArtifactProfile -isnot [string] -or $Receipt.ArtifactProfile -cne $ExpectedProfile -or
        $Receipt.ArtifactType -isnot [string] -or $Receipt.ArtifactType -cne 'GitForWindowsInstaller' -or
        $Receipt.DescriptorId -isnot [string] -or $Receipt.DescriptorId -cne $ArtifactDescriptor.DescriptorId -or
        $Receipt.MetadataBindingToken -isnot [string] -or $Receipt.MetadataBindingToken -cne $ArtifactDescriptor.MetadataBindingToken -or
        $Receipt.FileIdentityToken -isnot [string] -or $Receipt.FileIdentityToken -cne $ExpectedFileIdentityToken -or
        $Receipt.ArtifactSha256 -isnot [string] -or
        -not (Test-CddsiArtifactHashBinding -ActualSha256 $Receipt.ArtifactSha256 -ExpectedSha256 $ArtifactDescriptor.ExpectedArtifactSha256) -or
        (($Receipt.ArtifactSizeBytes -isnot [int]) -and
            ($Receipt.ArtifactSizeBytes -isnot [long])) -or
        [long]$Receipt.ArtifactSizeBytes -ne [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes
    ) { return $false }
    try {
        if ($Receipt.DestinationPathBindingToken -cne (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath)) { return $false }
        if (-not (Test-CddsiSourceObservation -Observation $Receipt.SourceObservation -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller -ExpectedRunId $ExpectedRunId -ExpectedProfile $ExpectedProfile -ValidationTimeUtc $ValidationTimeUtc)) { return $false }
        if ($Receipt.ReceiptBindingToken -isnot [string] -or $Receipt.ReceiptBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
        return ($Receipt.ReceiptBindingToken -ceq (Get-CddsiD027GitDownloadReceiptBindingToken -Receipt $Receipt))
    }
    catch {
        return $false
    }
}

function Resolve-CddsiD027GitInstallerDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$InstallerObservation
    )

    if (
        -not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller) -or
        $ArtifactDescriptor.MetadataStatus -cne 'UNRESOLVED' -or
        $ArtifactDescriptor.Architecture -cne 'x64'
    ) {
        throw 'Git installer descriptor resolution requires an unresolved x64 descriptor.'
    }
    $requiredObservation = @(
        'SchemaVersion', 'ContractVersion', 'DescriptorId', 'MetadataBindingToken',
        'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes', 'AuthenticodeStatus', 'SignatureType',
        'ChainTrusted', 'ChainRevocationMode', 'TimestampStatus', 'TimestampChainStatus',
        'SignerThumbprint', 'SignerSubjectToken', 'PublisherToken', 'IdentityToken', 'BootstrapPeMachine',
        'DeclaredPayloadArchitecture', 'ArchitectureBindingSource', 'ArtifactVersion',
        'ObservationId', 'ObservedAtUtc'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $InstallerObservation -Expected $requiredObservation)) {
        throw 'Git installer observation does not match the exact schema.'
    }
    if (
        -not (Test-CddsiSchemaVersionOne -Value $InstallerObservation.SchemaVersion) -or
        $InstallerObservation.ContractVersion -isnot [string] -or
        $InstallerObservation.ContractVersion -cne 'cddsi-d027-git-installer-observation-v1' -or
        $InstallerObservation.DescriptorId -isnot [string] -or
        $InstallerObservation.DescriptorId -cne $ArtifactDescriptor.DescriptorId -or
        $InstallerObservation.MetadataBindingToken -isnot [string] -or
        $InstallerObservation.MetadataBindingToken -cne $ArtifactDescriptor.MetadataBindingToken -or
        $InstallerObservation.FileIdentityToken -isnot [string] -or $InstallerObservation.FileIdentityToken -notmatch '^[a-f0-9]{64}$' -or
        $InstallerObservation.ArtifactSha256 -isnot [string] -or
        -not (Test-CddsiArtifactHashBinding -ActualSha256 $InstallerObservation.ArtifactSha256 -ExpectedSha256 $ArtifactDescriptor.ExpectedArtifactSha256) -or
        (($InstallerObservation.ArtifactSizeBytes -isnot [int]) -and
            ($InstallerObservation.ArtifactSizeBytes -isnot [long])) -or
        [long]$InstallerObservation.ArtifactSizeBytes -ne [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -or
        $InstallerObservation.AuthenticodeStatus -isnot [string] -or $InstallerObservation.AuthenticodeStatus -cne 'Valid' -or
        $InstallerObservation.SignatureType -isnot [string] -or $InstallerObservation.SignatureType -cne 'Authenticode' -or
        $InstallerObservation.ChainTrusted -isnot [bool] -or -not $InstallerObservation.ChainTrusted -or
        $InstallerObservation.ChainRevocationMode -isnot [string] -or
        $InstallerObservation.ChainRevocationMode -cne 'NotChecked' -or
        $InstallerObservation.TimestampStatus -isnot [string] -or $InstallerObservation.TimestampStatus -cne 'Present' -or
        $InstallerObservation.TimestampChainStatus -isnot [string] -or
        $InstallerObservation.TimestampChainStatus -cne 'NotIndependentlyEvaluated' -or
        $InstallerObservation.SignerThumbprint -isnot [string] -or $InstallerObservation.SignerThumbprint -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$' -or
        $InstallerObservation.SignerSubjectToken -isnot [string] -or $InstallerObservation.SignerSubjectToken -cne $script:CddsiD027GitInstallerSignerSubjectToken -or
        $InstallerObservation.PublisherToken -isnot [string] -or $InstallerObservation.PublisherToken -cne $script:CddsiD027GitInstallerPublisherToken -or
        $InstallerObservation.IdentityToken -isnot [string] -or $InstallerObservation.IdentityToken -cne $script:CddsiD027GitInstallerIdentityToken -or
        $InstallerObservation.BootstrapPeMachine -isnot [string] -or $InstallerObservation.BootstrapPeMachine -cne 'x86' -or
        $InstallerObservation.DeclaredPayloadArchitecture -isnot [string] -or
        $InstallerObservation.DeclaredPayloadArchitecture -cne 'x64' -or
        $InstallerObservation.ArchitectureBindingSource -isnot [string] -or
        $InstallerObservation.ArchitectureBindingSource -cne 'OfficialMetadataDigestAndFileName' -or
        $InstallerObservation.ArtifactVersion -isnot [string] -or $InstallerObservation.ArtifactVersion -cne $ArtifactDescriptor.ReleaseVersion -or
        -not (Test-CddsiSafeIdentifierValue -Value $InstallerObservation.ObservationId -MaxLength 128) -or
        -not (Test-CddsiUtcTimestampValue -Value $InstallerObservation.ObservedAtUtc)
    ) {
        throw 'Git installer signer, publisher, identity, bootstrap or payload observation was rejected.'
    }

    $resolvedValues = [ordered]@{}
    foreach ($property in $ArtifactDescriptor.PSObject.Properties) {
        if ($property.Name -cne 'MetadataBindingToken') {
            $resolvedValues[$property.Name] = $property.Value
        }
    }
    $resolvedValues['ExpectedSignerThumbprint'] = $InstallerObservation.SignerThumbprint.ToLowerInvariant()
    $resolvedValues['ExpectedSignerSubjectToken'] = $script:CddsiD027GitInstallerSignerSubjectToken
    $resolvedValues['ExpectedPublisherToken'] = $script:CddsiD027GitInstallerPublisherToken
    $resolvedValues['ExpectedIdentityToken'] = $script:CddsiD027GitInstallerIdentityToken
    $resolvedValues['MetadataStatus'] = 'READY'
    $withoutBinding = [pscustomobject]$resolvedValues
    $resolvedValues['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $resolved = [pscustomobject]$resolvedValues
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $resolved -ExpectedArtifactType GitForWindowsInstaller -RequireResolved)) {
        throw 'Resolved Git installer descriptor failed its immutable contract.'
    }
    return $resolved
}

function Get-CddsiD027GitInstallerProcessPolicy {
    [CmdletBinding()]
    param()

    $arguments = [string[]]@(
        '/VERYSILENT'
        '/NORESTART'
        '/NOCANCEL'
        '/SP-'
        '/SUPPRESSMSGBOXES'
        '/NOCLOSEAPPLICATIONS'
        '/NORESTARTAPPLICATIONS'
        '/RESTARTEXITCODE=8'
        '/o:PathOption=Cmd'
        '/o:EditorOption=VIM'
        '/COMPONENTS=gitlfs'
    )
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion   = 1
        UseShellExecute = $true
        Verb            = 'runas'
        CreateNoWindow  = $false
        WindowStyle     = 'Normal'
        WorkingDirectoryPolicy = 'WindowsSystemDirectory64'
        ArgumentList    = $arguments
        TimeoutSeconds  = 1800
    }
    $bindingText = @(
        'SchemaVersion=1'
        'UseShellExecute=true'
        'Verb=runas'
        'CreateNoWindow=false'
        'WindowStyle=Normal'
        'WorkingDirectoryPolicy=WindowsSystemDirectory64'
        'TimeoutSeconds=1800'
        'Arguments={0}' -f ($arguments -join "`n")
    ) -join "`n"
    $result = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $result[$property.Name] = $property.Value
    }
    $result['PolicyBindingToken'] = Get-CddsiSupplyChainTextBindingToken -Text $bindingText
    return [pscustomobject]$result
}

function Assert-CddsiD027GitDirectorySecurity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateSet('ProductTemp', 'ProtectedSystem')]
        [string]$Purpose
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathRooted($Path)) {
        throw 'Git directory security validation requires an absolute path.'
    }
    $fullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
    if ([string]::IsNullOrWhiteSpace($fullPath) -or $fullPath.Length -gt 240) {
        throw 'Git directory security validation rejected the canonical path.'
    }
    $item = Get-Item -LiteralPath $fullPath -Force -ErrorAction Stop
    if (
        -not $item.PSIsContainer -or
        ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0
    ) {
        throw 'Git directory security validation rejected the directory identity.'
    }
    $cursor = $fullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $cursorItem = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($cursorItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Git directory security validation rejected a reparse-point ancestor.'
        }
        $parent = [System.IO.Directory]::GetParent($cursor)
        if ($null -eq $parent) { break }
        $cursor = $parent.FullName
    }
    $drive = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($fullPath))
    if (
        $drive.DriveType -ne [System.IO.DriveType]::Fixed -or
        $drive.DriveFormat -cne 'NTFS'
    ) {
        throw 'Git directory security validation requires fixed NTFS.'
    }

    $allowedWriterSids = @($script:CddsiGitProtectedWriterSids)
    if ($Purpose -ceq 'ProductTemp') {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        try {
            $allowedWriterSids += [string]$identity.User.Value
        }
        finally {
            $identity.Dispose()
        }
    }
    $acl = Get-Acl -LiteralPath $fullPath -ErrorAction Stop
    $ownerSid = ([Security.Principal.NTAccount]$acl.Owner).Translate(
        [Security.Principal.SecurityIdentifier]
    ).Value
    if ($allowedWriterSids -cnotcontains $ownerSid) {
        throw 'Git directory security validation rejected the owner.'
    }
    $sddl = $acl.GetSecurityDescriptorSddlForm(
        [Security.AccessControl.AccessControlSections]::Access
    )
    if ($sddl -notmatch '^D:' -or $sddl -match 'NO_ACCESS_CONTROL') {
        throw 'Git directory security validation rejected a null or invalid DACL.'
    }
    foreach ($rule in @($acl.GetAccessRules(
        $true,
        $true,
        [Security.Principal.SecurityIdentifier]
    ))) {
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
        if ($allowedWriterSids -cnotcontains $sid -and -not $creatorOwnerInheritOnly) {
            throw 'Git directory security validation found an untrusted writer.'
        }
    }
    return $fullPath
}

function Test-CddsiD027GitPostInstallReadbackEligible {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Started,
        [Parameter(Mandatory = $true)][bool]$InstallerStillRunning,
        [Parameter(Mandatory = $true)][bool]$CompletionObservationFailed,
        [AllowNull()][Nullable[int]]$ExitCode
    )

    return (
        $Started -and
        -not $InstallerStillRunning -and
        -not $CompletionObservationFailed -and
        $null -ne $ExitCode -and
        [int]$ExitCode -eq 0
    )
}

function ConvertTo-CddsiD027GitInstallerExitResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Started,
        [Parameter(Mandatory = $true)][bool]$UacCancelled,
        [AllowNull()][Nullable[int]]$ExitCode,
        [Parameter(Mandatory = $true)][bool]$ReadbackTrusted,
        [Parameter(Mandatory = $true)][bool]$ChangedObserved,
        [Parameter(Mandatory = $true)][bool]$RestartObserved,
        [bool]$CompletionObservationFailed = $false,
        [bool]$InstallerStillRunning = $false,
        [bool]$PostInstallAuthorizationInvalid = $false,
        [bool]$ReadbackObservationFailed = $false
    )

    if ($UacCancelled -and $Started) {
        throw 'A started installer cannot also be classified as a UAC cancellation.'
    }
    $status = 'FAILED'
    $errorCode = 'GIT_INSTALL_START_FAILED'
    $restartRequired = $false
    if ($UacCancelled) {
        $status = 'CANCELLED'
        $errorCode = 'GIT_INSTALL_UAC_CANCELLED'
    }
    elseif (-not $Started) {
        $status = 'FAILED'
        $errorCode = 'GIT_INSTALL_START_FAILED'
    }
    elseif ($InstallerStillRunning) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALLER_STILL_RUNNING'
    }
    elseif ($PostInstallAuthorizationInvalid) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALL_POST_AUTHORIZATION_INVALID'
    }
    elseif ($RestartObserved -or ($null -ne $ExitCode -and [int]$ExitCode -eq 8)) {
        $status = 'RESTART_REQUIRED'
        $errorCode = 'GIT_INSTALL_RESTART_REQUIRED'
        $restartRequired = $true
    }
    elseif ($CompletionObservationFailed) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALL_COMPLETION_UNKNOWN'
    }
    elseif ($ReadbackObservationFailed) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALL_READBACK_FAILED'
    }
    elseif ($null -eq $ExitCode) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALL_TIMEOUT'
    }
    elseif ([int]$ExitCode -eq 0 -and $ReadbackTrusted) {
        $status = 'SUCCEEDED'
        $errorCode = ''
    }
    elseif ([int]$ExitCode -eq 0) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALL_READBACK_FAILED'
    }
    elseif ($ChangedObserved) {
        $status = 'PARTIAL'
        $errorCode = 'GIT_INSTALL_NONZERO_PARTIAL'
    }
    else {
        $status = 'FAILED'
        $errorCode = 'GIT_INSTALL_NONZERO'
    }
    return [pscustomobject][ordered]@{
        SchemaVersion   = 1
        Status          = $status
        ErrorCode       = $errorCode
        Changed         = [bool]$ChangedObserved
        RestartRequired = $restartRequired
    }
}

function ConvertFrom-CddsiGitHubReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ReleaseDocument,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ReleaseDocument -Expected @('tag_name', 'draft', 'prerelease', 'immutable', 'html_url', 'assets'))) {
        throw 'GitHub release document does not match the normalized exact schema.'
    }
    if (
        $ReleaseDocument.tag_name -isnot [string] -or
        $ReleaseDocument.draft -isnot [bool] -or $ReleaseDocument.draft -or
        $ReleaseDocument.prerelease -isnot [bool] -or $ReleaseDocument.prerelease -or
        $ReleaseDocument.immutable -isnot [bool] -or -not $ReleaseDocument.immutable -or
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
            (($asset.size -isnot [int]) -and ($asset.size -isnot [long])) -or
            [long]$asset.size -lt 1 -or
            $asset.state -isnot [string] -or $asset.state -cne 'uploaded' -or
            $asset.content_type -isnot [string] -or [string]::IsNullOrWhiteSpace($asset.content_type) -or
            ($null -ne $asset.digest -and $asset.digest -isnot [string])
        ) {
            throw 'GitHub release asset values are invalid.'
        }
        if ([regex]::IsMatch(
            $asset.name,
            $assetNamePattern,
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )) {
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

    if ($Context.Mode -ceq 'Live') {
        Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
        if ($Architecture -cne 'x64') {
            return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_ARCHITECTURE_UNSUPPORTED' -MessageSafe 'D-027 supports only the x64 Git for Windows installer.'
        }

        $handler = $null
        $client = $null
        $request = $null
        $response = $null
        $responseStream = $null
        $memory = $null
        $metadataCancellation = $null
        try {
            Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.AllowAutoRedirect = $false
            $handler.UseCookies = $false
            $handler.UseDefaultCredentials = $false
            $handler.PreAuthenticate = $false
            $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::None
            $handler.CheckCertificateRevocationList = $true
            $handler.SslProtocols = [System.Security.Authentication.SslProtocols]::Tls12
            $client = New-Object System.Net.Http.HttpClient($handler, $false)
            $client.Timeout = [TimeSpan]::FromSeconds($script:CddsiD027GitMetadataTimeoutSeconds)
            $metadataCancellation = New-Object System.Threading.CancellationTokenSource
            $metadataCancellation.CancelAfter(
                [TimeSpan]::FromSeconds($script:CddsiD027GitMetadataTimeoutSeconds)
            )
            $request = New-Object System.Net.Http.HttpRequestMessage(
                [System.Net.Http.HttpMethod]::Get,
                $script:CddsiD027GitLatestReleaseApiUri
            )
            [void]$request.Headers.UserAgent.ParseAdd('CDDsi-D027/1.0')
            [void]$request.Headers.Accept.ParseAdd('application/vnd.github+json')
            [void]$request.Headers.TryAddWithoutValidation('X-GitHub-Api-Version', '2022-11-28')
            $response = $client.SendAsync(
                $request,
                [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                $metadataCancellation.Token
            ).GetAwaiter().GetResult()
            if ([int]$response.StatusCode -ne 200) {
                throw 'GitHub metadata response status was not 200.'
            }
            if ($null -ne $response.Headers.Location) {
                throw 'GitHub metadata endpoint redirected unexpectedly.'
            }
            $mediaType = if ($null -eq $response.Content.Headers.ContentType) {
                ''
            }
            else {
                [string]$response.Content.Headers.ContentType.MediaType
            }
            if ($mediaType -notin @('application/json', 'application/vnd.github+json')) {
                throw 'GitHub metadata response content type was invalid.'
            }
            if (@($response.Content.Headers.ContentEncoding).Count -ne 0) {
                throw 'GitHub metadata response content encoding was not allowed.'
            }
            $declaredLength = $response.Content.Headers.ContentLength
            if (
                $null -ne $declaredLength -and
                ([long]$declaredLength -lt 1 -or [long]$declaredLength -gt $script:CddsiD027GitMetadataMaximumBytes)
            ) {
                throw 'GitHub metadata response length was invalid.'
            }

            $responseStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
            $memory = New-Object System.IO.MemoryStream
            $buffer = New-Object byte[] 65536
            [long]$total = 0
            while ($true) {
                $read = $responseStream.ReadAsync(
                    $buffer,
                    0,
                    $buffer.Length,
                    $metadataCancellation.Token
                ).GetAwaiter().GetResult()
                if ($read -le 0) { break }
                $total += [long]$read
                if ($total -gt $script:CddsiD027GitMetadataMaximumBytes) {
                    throw 'GitHub metadata response exceeded the byte limit.'
                }
                $memory.Write($buffer, 0, $read)
            }
            if ($total -lt 1 -or ($null -ne $declaredLength -and $total -ne [long]$declaredLength)) {
                throw 'GitHub metadata response was empty or truncated.'
            }
            $utf8 = New-Object System.Text.UTF8Encoding($false, $true)
            $json = $utf8.GetString($memory.ToArray())
            $rawDocument = $json | ConvertFrom-Json -ErrorAction Stop
            $normalized = ConvertTo-CddsiD027NormalizedGitHubReleaseDocument -ReleaseDocument $rawDocument
            $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $normalized -Architecture x64
        }
        catch {
            return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_METADATA_REQUEST_FAILED' -MessageSafe 'The official Git for Windows release metadata could not be resolved safely.'
        }
        finally {
            if ($null -ne $memory) { $memory.Dispose() }
            if ($null -ne $responseStream) { $responseStream.Dispose() }
            if ($null -ne $response) { $response.Dispose() }
            if ($null -ne $request) { $request.Dispose() }
            if ($null -ne $metadataCancellation) { $metadataCancellation.Dispose() }
            if ($null -ne $client) { $client.Dispose() }
            if ($null -ne $handler) { $handler.Dispose() }
        }
        return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Official Git for Windows x64 version, artifact identity, length and SHA-256 metadata were resolved.' -Data $descriptor
    }

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
        [switch]$AcknowledgeRealChanges,
        [AllowNull()][string]$ArtifactProfile = $null
    )

    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller)) {
        throw 'Git download plan requires an exact official artifact descriptor.'
    }
    if ($Mode -eq 'Live') {
        Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
        if (-not $AcknowledgeRealChanges) {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'ACTION_REQUIRED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_CONFIRMATION_REQUIRED' -MessageSafe 'Explicit confirmation is required before downloading the Git installer.'
        }
        if (
            $ArtifactDescriptor.Architecture -cne 'x64' -or
            $ArtifactDescriptor.MetadataStatus -cne 'UNRESOLVED' -or
            $ArtifactDescriptor.ExpectedArtifactSha256 -isnot [string] -or
            $ArtifactDescriptor.ExpectedArtifactSha256 -notmatch '^[a-f0-9]{64}$' -or
            (($ArtifactDescriptor.ExpectedArtifactSizeBytes -isnot [int]) -and
                ($ArtifactDescriptor.ExpectedArtifactSizeBytes -isnot [long])) -or
            [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -lt 1 -or
            [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -gt [long]$ArtifactDescriptor.MaximumBytes
        ) {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_DESCRIPTOR_INVALID' -MessageSafe 'The Git installer download descriptor was not an unresolved official x64 artifact.'
        }
        if ([string]::IsNullOrWhiteSpace($ArtifactProfile)) {
            $ArtifactProfile = if ($Context.Stage -in @('VmCalibration', 'VmAcceptance', 'UserLive')) {
                [string]$Context.Stage
            }
            else {
                $null
            }
        }
        if ($ArtifactProfile -notin @('VmCalibration', 'VmAcceptance', 'UserLive')) {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'ACTION_REQUIRED' -Mode Live -ErrorCode 'GIT_ARTIFACT_PROFILE_REQUIRED' -MessageSafe 'A supported artifact profile is required for the Git download receipt.'
        }
        if (-not (Test-CddsiCanonicalUuidValue -Value $Context.RunId)) {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_RUN_ID_INVALID' -MessageSafe 'The Git download requires a canonical nonzero run identifier.'
        }

        $tempRoot = $null
        $destination = $null
        $expectedFileName = $null
        try {
            $tempRoot = [System.IO.Path]::GetFullPath([string]$Context.Paths.Temp).TrimEnd('\')
            $destination = [System.IO.Path]::GetFullPath($DestinationPath)
            $sourceUri = New-Object Uri($ArtifactDescriptor.SourceUri, [UriKind]::Absolute)
            $expectedFileName = [Uri]::UnescapeDataString(
                [System.IO.Path]::GetFileName($sourceUri.AbsolutePath)
            )
            if (
                $destination.Length -gt 240 -or
                -not [string]::Equals(
                    [System.IO.Path]::GetDirectoryName($destination).TrimEnd('\'),
                    $tempRoot,
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                -not [string]::Equals(
                    [System.IO.Path]::GetFileName($destination),
                    $expectedFileName,
                    [StringComparison]::Ordinal
                ) -or
                $expectedFileName -notmatch '^Git-[0-9]+\.[0-9]+\.[0-9]+(?:\.[1-9][0-9]*)?-64-bit\.exe$' -or
                [System.IO.File]::Exists($destination) -or
                [System.IO.Directory]::Exists($destination)
            ) {
                throw 'Git download destination was outside the exact product temp file contract.'
            }
            Assert-CddsiD027GitDirectorySecurity -Path $tempRoot -Purpose ProductTemp |
                Out-Null
        }
        catch {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_DESTINATION_UNSAFE' -MessageSafe 'The Git installer destination was not a new owner-protected file in the exact product temp directory.'
        }

        $partialPath = Join-Path $tempRoot (
            'g-{0}-{1}.tmp' -f
            $Context.RunId.Replace('-', '').Substring(0, 8),
            $ArtifactDescriptor.MetadataBindingToken.Substring(0, 8)
        )
        if ($partialPath.Length -gt 240) {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_DESTINATION_UNSAFE' -MessageSafe 'The Git installer partial path exceeded the supported Windows path bound.'
        }
        if ([System.IO.File]::Exists($partialPath) -or [System.IO.Directory]::Exists($partialPath)) {
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'ACTION_REQUIRED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_PARTIAL_EXISTS' -MessageSafe 'A prior product-owned Git download partial requires explicit recovery before retrying.'
        }

        $handler = $null
        $client = $null
        $downloadCancellation = $null
        $partialStream = $null
        $sha = $null
        $currentUri = $ArtifactDescriptor.SourceUri
        $safeRedirectUris = New-Object System.Collections.Generic.List[string]
        $transportUris = New-Object System.Collections.Generic.List[string]
        $seenTransportUris = @{}
        $transportUris.Add($currentUri)
        $seenTransportUris[$currentUri] = $true
        $finalSafeUri = $currentUri
        $committed = $false
        $partialCreated = $false
        try {
            Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
            $handler = New-Object System.Net.Http.HttpClientHandler
            $handler.AllowAutoRedirect = $false
            $handler.UseCookies = $false
            $handler.UseDefaultCredentials = $false
            $handler.PreAuthenticate = $false
            $handler.AutomaticDecompression = [System.Net.DecompressionMethods]::None
            $handler.CheckCertificateRevocationList = $true
            $handler.SslProtocols = [System.Security.Authentication.SslProtocols]::Tls12
            $client = New-Object System.Net.Http.HttpClient($handler, $false)
            $client.Timeout = [TimeSpan]::FromSeconds($script:CddsiD027GitDownloadTimeoutSeconds)
            $downloadCancellation = New-Object System.Threading.CancellationTokenSource
            $downloadCancellation.CancelAfter(
                [TimeSpan]::FromSeconds($script:CddsiD027GitDownloadTimeoutSeconds)
            )

            $finalResponse = $null
            for ($redirectCount = 0; $redirectCount -le $script:CddsiD027GitDownloadMaximumRedirects; $redirectCount++) {
                $request = $null
                $response = $null
                try {
                    $request = New-Object System.Net.Http.HttpRequestMessage(
                        [System.Net.Http.HttpMethod]::Get,
                        $currentUri
                    )
                    [void]$request.Headers.UserAgent.ParseAdd('CDDsi-D027/1.0')
                    [void]$request.Headers.Accept.ParseAdd('application/octet-stream')
                    $response = $client.SendAsync(
                        $request,
                        [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead,
                        $downloadCancellation.Token
                    ).GetAwaiter().GetResult()
                    $statusCode = [int]$response.StatusCode
                    if ($statusCode -in @(301, 302, 303, 307, 308)) {
                        if ($redirectCount -ge $script:CddsiD027GitDownloadMaximumRedirects) {
                            throw 'Git installer redirect limit was exceeded.'
                        }
                        $location = $response.Headers.Location
                        if ($null -eq $location) {
                            throw 'Git installer redirect omitted Location.'
                        }
                        $baseUri = New-Object Uri($currentUri, [UriKind]::Absolute)
                        $nextUriObject = if ($location.IsAbsoluteUri) {
                            $location
                        }
                        else {
                            New-Object Uri($baseUri, $location)
                        }
                        $nextUri = $nextUriObject.AbsoluteUri
                        if (
                            $nextUri.Length -gt 12288 -or
                            $nextUriObject.Scheme -cne 'https' -or
                            -not $nextUriObject.IsDefaultPort -or
                            -not [string]::IsNullOrEmpty($nextUriObject.UserInfo) -or
                            -not [string]::IsNullOrEmpty($nextUriObject.Fragment) -or
                            $nextUriObject.DnsSafeHost.ToLowerInvariant() -cne 'release-assets.githubusercontent.com' -or
                            -not [regex]::IsMatch(
                                $nextUriObject.AbsolutePath,
                                '^/github-production-release-asset/[1-9][0-9]*/[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
                                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
                            ) -or
                            $seenTransportUris.ContainsKey($nextUri)
                        ) {
                            throw 'Git installer redirect target was not an allowed GitHub release asset URI.'
                        }
                        $safeUri = $nextUriObject.GetLeftPart([UriPartial]::Path)
                        if (-not (Test-CddsiOfficialArtifactRedirectUri -SourceUri $safeUri -ExpectedOwner GitForWindows)) {
                            throw 'Git installer redirect receipt URI was invalid.'
                        }
                        $seenTransportUris[$nextUri] = $true
                        $transportUris.Add($nextUri)
                        $safeRedirectUris.Add($safeUri)
                        $currentUri = $nextUri
                        $finalSafeUri = $safeUri
                        continue
                    }
                    if ($statusCode -ne 200) {
                        throw 'Git installer response status was not 200.'
                    }
                    $finalResponse = $response
                    $response = $null
                    break
                }
                finally {
                    if ($null -ne $response) { $response.Dispose() }
                    if ($null -ne $request) { $request.Dispose() }
                }
            }
            if ($null -eq $finalResponse) {
                throw 'Git installer response did not reach a final artifact.'
            }
            try {
                $contentLength = $finalResponse.Content.Headers.ContentLength
                $contentType = if ($null -eq $finalResponse.Content.Headers.ContentType) {
                    ''
                }
                else {
                    [string]$finalResponse.Content.Headers.ContentType.MediaType
                }
                if (
                    $null -eq $contentLength -or
                    [long]$contentLength -ne [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -or
                    [long]$contentLength -gt [long]$ArtifactDescriptor.MaximumBytes -or
                    $contentType -notin @('application/octet-stream', 'application/executable', 'application/x-msdownload') -or
                    @($finalResponse.Content.Headers.ContentEncoding).Count -ne 0
                ) {
                    throw 'Git installer response length, MIME type or encoding was invalid.'
                }
                $networkStream = $null
                try {
                    $networkStream = $finalResponse.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
                    $partialStream = New-Object System.IO.FileStream(
                        $partialPath,
                        [System.IO.FileMode]::CreateNew,
                        [System.IO.FileAccess]::Write,
                        [System.IO.FileShare]::None,
                        65536,
                        [System.IO.FileOptions]::WriteThrough
                    )
                    $partialCreated = $true
                    $sha = [System.Security.Cryptography.SHA256]::Create()
                    $buffer = New-Object byte[] 65536
                    [long]$total = 0
                    while ($true) {
                        $read = $networkStream.ReadAsync(
                            $buffer,
                            0,
                            $buffer.Length,
                            $downloadCancellation.Token
                        ).GetAwaiter().GetResult()
                        if ($read -le 0) { break }
                        if (($total + [long]$read) -gt [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes) {
                            throw 'Git installer response exceeded the expected length.'
                        }
                        $partialStream.Write($buffer, 0, $read)
                        [void]$sha.TransformBlock($buffer, 0, $read, $buffer, 0)
                        $total += [long]$read
                    }
                    [void]$sha.TransformFinalBlock((New-Object byte[] 0), 0, 0)
                    $downloadHash = ([BitConverter]::ToString($sha.Hash)).Replace('-', '').ToLowerInvariant()
                    if (
                        $total -ne [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -or
                        -not (Test-CddsiArtifactHashBinding -ActualSha256 $downloadHash -ExpectedSha256 $ArtifactDescriptor.ExpectedArtifactSha256)
                    ) {
                        throw 'Git installer response was truncated or its SHA-256 did not match.'
                    }
                    $partialStream.Flush($true)
                }
                finally {
                    if ($null -ne $sha) {
                        $sha.Dispose()
                        $sha = $null
                    }
                    if ($null -ne $partialStream) {
                        $partialStream.Dispose()
                        $partialStream = $null
                    }
                    if ($null -ne $networkStream) { $networkStream.Dispose() }
                }
            }
            finally {
                $finalResponse.Dispose()
            }

            $readbackHash = (Get-FileHash -LiteralPath $partialPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
            $readbackItem = Get-Item -LiteralPath $partialPath -Force -ErrorAction Stop
            if (
                $readbackItem.PSIsContainer -or
                ($readbackItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
                [long]$readbackItem.Length -ne [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -or
                -not (Test-CddsiArtifactHashBinding -ActualSha256 $readbackHash -ExpectedSha256 $ArtifactDescriptor.ExpectedArtifactSha256)
            ) {
                throw 'Git installer committed-file readback failed.'
            }
            [System.IO.File]::Move($partialPath, $destination)
            $committed = $true

            $pathBindingToken = Get-CddsiPathBindingToken -Path $destination
            $fileIdentityToken = Get-CddsiSupplyChainTextBindingToken -Text (
                '{0}|{1}|{2}' -f
                $pathBindingToken,
                $readbackHash,
                [long]$readbackItem.Length
            )
            $observedAt = [DateTimeOffset]::UtcNow.ToString(
                'yyyy-MM-ddTHH:mm:ssZ',
                [Globalization.CultureInfo]::InvariantCulture
            )
            $redirectArray = $safeRedirectUris.ToArray()
            $sourceWithoutBinding = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-source-observation-v1'
                RunId = $Context.RunId
                ArtifactProfile = $ArtifactProfile
                DescriptorId = $ArtifactDescriptor.DescriptorId
                MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken
                RequestUri = $ArtifactDescriptor.SourceUri
                FinalUri = $finalSafeUri
                RedirectUris = $redirectArray
                RedirectChainBindingToken = Get-CddsiSupplyChainTextBindingToken -Text (
                    (@($ArtifactDescriptor.SourceUri) + @($redirectArray)) -join "`n"
                )
                RedirectCount = $redirectArray.Count
                ArtifactSha256 = $readbackHash
                ArtifactSizeBytes = [long]$readbackItem.Length
                ObservationId = 'git-download-' + $Context.RunId
                ObservedAtUtc = $observedAt
            }
            $sourceValues = [ordered]@{}
            foreach ($property in $sourceWithoutBinding.PSObject.Properties) {
                $sourceValues[$property.Name] = $property.Value
            }
            $sourceValues['SourceObservationBindingToken'] = Get-CddsiSourceObservationBindingToken -Observation $sourceWithoutBinding
            $sourceObservation = [pscustomobject]$sourceValues
            $receipt = New-CddsiD027GitDownloadReceipt -ArtifactDescriptor $ArtifactDescriptor -DestinationPath $destination -FileIdentityToken $fileIdentityToken -SourceObservation $sourceObservation -ExpectedRunId $Context.RunId -ArtifactProfile $ArtifactProfile -ValidationTimeUtc $observedAt
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'SUCCEEDED' -Changed $true -Mode Live -MessageSafe 'The official Git for Windows installer was downloaded, length-checked, hashed, read back and committed to product temp.' -Data $receipt
        }
        catch {
            if ($partialCreated -or $committed) {
                $recoveryPath = if ($committed) { $destination } else { $partialPath }
                $recovery = [pscustomobject][ordered]@{
                    SchemaVersion = 1
                    ArtifactType = 'GitForWindowsInstaller'
                    RecoveryPathBindingToken = Get-CddsiPathBindingToken -Path $recoveryPath
                    PartialCreated = $partialCreated
                    DestinationCommitted = $committed
                }
                return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'PARTIAL' -Changed $true -Mode Live -ErrorCode 'GIT_DOWNLOAD_RECOVERY_REQUIRED' -MessageSafe 'The Git download was not accepted; a run-owned temp path may remain and requires identity-checked recovery.' -Data $recovery
            }
            return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_FAILED' -MessageSafe 'The official Git for Windows installer download failed closed and no artifact was accepted.'
        }
        finally {
            if ($null -ne $sha) { $sha.Dispose() }
            if ($null -ne $partialStream) { $partialStream.Dispose() }
            if ($null -ne $downloadCancellation) { $downloadCancellation.Dispose() }
            if ($null -ne $client) { $client.Dispose() }
            if ($null -ne $handler) { $handler.Dispose() }
        }
    }

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    $pathBindingToken = Get-CddsiPathBindingToken -Path $DestinationPath
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

function Get-CddsiD027GitInstallerObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    if (
        -not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller) -or
        $ArtifactDescriptor.Architecture -cne 'x64'
    ) {
        return New-CddsiOperationResult -Operation 'ObserveGitInstaller' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALLER_DESCRIPTOR_INVALID' -MessageSafe 'The Git installer observation requires an exact official x64 descriptor.'
    }

    $stream = $null
    $sha = $null
    try {
        $path = [System.IO.Path]::GetFullPath($InstallerPath)
        $tempRoot = [System.IO.Path]::GetFullPath([string]$Context.Paths.Temp).TrimEnd('\')
        $sourceUri = New-Object Uri($ArtifactDescriptor.SourceUri, [UriKind]::Absolute)
        $expectedFileName = [Uri]::UnescapeDataString(
            [System.IO.Path]::GetFileName($sourceUri.AbsolutePath)
        )
        if (
            -not [string]::Equals(
                [System.IO.Path]::GetDirectoryName($path).TrimEnd('\'),
                $tempRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            -not [string]::Equals(
                [System.IO.Path]::GetFileName($path),
                $expectedFileName,
                [StringComparison]::Ordinal
            )
        ) {
            throw 'Git installer path escaped the exact product temp artifact.'
        }
        $stream = [System.IO.File]::Open(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $item = Get-Item -LiteralPath $path -Force -ErrorAction Stop
        if (
            $item.PSIsContainer -or
            ($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or
            [long]$item.Length -ne [long]$ArtifactDescriptor.ExpectedArtifactSizeBytes -or
            [long]$stream.Length -ne [long]$item.Length
        ) {
            throw 'Git installer type or length was invalid.'
        }

        $headerLength = [int][Math]::Min([long]4096, [long]$stream.Length)
        $header = New-Object byte[] $headerLength
        $headerOffset = 0
        while ($headerOffset -lt $headerLength) {
            $read = $stream.Read($header, $headerOffset, $headerLength - $headerOffset)
            if ($read -le 0) { break }
            $headerOffset += $read
        }
        if ($headerOffset -ne $headerLength) {
            throw 'Git installer PE header was truncated.'
        }
        $bootstrapPeMachine = ConvertFrom-CddsiGitPeHeader -HeaderBytes $header -ImageLength ([long]$stream.Length)
        $stream.Position = 0
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $hashBytes = $sha.ComputeHash($stream)
        $artifactSha256 = ([BitConverter]::ToString($hashBytes)).Replace('-', '').ToLowerInvariant()
        if (-not (Test-CddsiArtifactHashBinding -ActualSha256 $artifactSha256 -ExpectedSha256 $ArtifactDescriptor.ExpectedArtifactSha256)) {
            throw 'Git installer SHA-256 did not match official metadata.'
        }

        $signature = Get-AuthenticodeSignature -LiteralPath $path -ErrorAction Stop
        $winTrustResult = Get-CddsiD027GitWinVerifyTrustResult `
            -ExecutionContext $Context `
            -FilePath $path
        $versionInfo = $item.VersionInfo
        $authenticodeStatus = [string]$signature.Status
        $signatureType = [string]$signature.SignatureType
        $signerSubject = if ($null -eq $signature.SignerCertificate) {
            ''
        }
        else {
            [string]$signature.SignerCertificate.Subject
        }
        $signerThumbprint = if ($null -eq $signature.SignerCertificate) {
            ''
        }
        else {
            ([string]$signature.SignerCertificate.Thumbprint).ToLowerInvariant()
        }
        $timestampPresent = ($null -ne $signature.TimeStamperCertificate)
        $fileDescription = if ($null -eq $versionInfo.FileDescription) { '' } else { $versionInfo.FileDescription.Trim() }
        $productName = if ($null -eq $versionInfo.ProductName) { '' } else { $versionInfo.ProductName.Trim() }
        $companyName = if ($null -eq $versionInfo.CompanyName) { '' } else { $versionInfo.CompanyName.Trim() }
        $fileVersion = if ($null -eq $versionInfo.FileVersion) { '' } else { $versionInfo.FileVersion.Trim() }
        $productVersion = if ($null -eq $versionInfo.ProductVersion) { '' } else { $versionInfo.ProductVersion.Trim() }
        if (
            $authenticodeStatus -cne 'Valid' -or
            $signatureType -cne 'Authenticode' -or
            -not $winTrustResult.Trusted -or
            -not $timestampPresent -or
            -not [regex]::IsMatch(
                $signerSubject,
                $script:CddsiGitExecutableSignerSubjectPattern,
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            ) -or
            $signerThumbprint -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$'
        ) {
            return New-CddsiOperationResult -Operation 'ObserveGitInstaller' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALLER_SIGNATURE_INVALID' -MessageSafe 'The Git installer Authenticode signature, trusted signer or timestamp was invalid.'
        }
        if (
            $bootstrapPeMachine -cne 'x86' -or
            $fileDescription -cne 'Git Setup' -or
            $productName -cne 'Git' -or
            $companyName -cne 'The Git Development Community' -or
            $fileVersion -cne $ArtifactDescriptor.ReleaseVersion -or
            $productVersion -cne $ArtifactDescriptor.ReleaseVersion
        ) {
            return New-CddsiOperationResult -Operation 'ObserveGitInstaller' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALLER_IDENTITY_INVALID' -MessageSafe 'The Git installer bootstrap, publisher, product or version identity was invalid.'
        }
        $pathBindingToken = Get-CddsiPathBindingToken -Path $path
        $fileIdentityToken = Get-CddsiSupplyChainTextBindingToken -Text (
            '{0}|{1}|{2}' -f
            $pathBindingToken,
            $artifactSha256,
            [long]$item.Length
        )
        $observedAt = [DateTimeOffset]::UtcNow.ToString(
            'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture
        )
        $observation = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-git-installer-observation-v1'
            DescriptorId = $ArtifactDescriptor.DescriptorId
            MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken
            FileIdentityToken = $fileIdentityToken
            ArtifactSha256 = $artifactSha256
            ArtifactSizeBytes = [long]$item.Length
            AuthenticodeStatus = 'Valid'
            SignatureType = 'Authenticode'
            ChainTrusted = [bool]$winTrustResult.Trusted
            ChainRevocationMode = $winTrustResult.RevocationMode
            TimestampStatus = 'Present'
            TimestampChainStatus = 'NotIndependentlyEvaluated'
            SignerThumbprint = $signerThumbprint
            SignerSubjectToken = $script:CddsiD027GitInstallerSignerSubjectToken
            PublisherToken = $script:CddsiD027GitInstallerPublisherToken
            IdentityToken = $script:CddsiD027GitInstallerIdentityToken
            BootstrapPeMachine = 'x86'
            DeclaredPayloadArchitecture = 'x64'
            ArchitectureBindingSource = 'OfficialMetadataDigestAndFileName'
            ArtifactVersion = $ArtifactDescriptor.ReleaseVersion
            ObservationId = 'git-installer-' + $Context.RunId
            ObservedAtUtc = $observedAt
        }
        return New-CddsiOperationResult -Operation 'ObserveGitInstaller' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git installer hash, embedded Authenticode signer, publisher, x86 bootstrap and metadata-bound x64 target were verified.' -Data $observation
    }
    catch {
        return New-CddsiOperationResult -Operation 'ObserveGitInstaller' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALLER_OBSERVATION_FAILED' -MessageSafe 'The Git installer could not be observed safely.'
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
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

    if ($Context.Mode -ceq 'Live') {
        Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
        if (
            -not (Test-CddsiCanonicalUuidValue -Value $Context.RunId) -or
            -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)
        ) {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_SIGNATURE_CONTEXT_INVALID' -MessageSafe 'The Git signature verification context or validation time was invalid.'
        }
        $callerValidation = [DateTimeOffset]::Parse($ValidationTimeUtc)
        $clockNow = [DateTimeOffset]::UtcNow
        if ([Math]::Abs(($clockNow - $callerValidation).TotalSeconds) -gt 300) {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_SIGNATURE_CLOCK_INVALID' -MessageSafe 'The Git signature validation time was not close to the current trusted clock.'
        }
        if (
            -not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller) -or
            $ArtifactDescriptor.MetadataStatus -cne 'UNRESOLVED' -or
            $ArtifactDescriptor.Architecture -cne 'x64'
        ) {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_ARTIFACT_CONTRACT_INVALID' -MessageSafe 'Live Git verification requires the unresolved official x64 metadata descriptor.'
        }

        $receipt = $SourceObservation
        if (
            $null -ne $receipt -and
            $null -ne $receipt.PSObject.Properties['Data'] -and
            $receipt.Status -ceq 'SUCCEEDED'
        ) {
            $receipt = $receipt.Data
        }
        $installerObservationResult = Get-CddsiD027GitInstallerObservation -ExecutionContext $Context -InstallerPath $InstallerPath -ArtifactDescriptor $ArtifactDescriptor
        if ($installerObservationResult.Status -cne 'SUCCEEDED') {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode $installerObservationResult.ErrorCode -MessageSafe 'The Git installer signature or identity observation failed closed.'
        }
        $installerObservation = $installerObservationResult.Data
        $validationNow = [DateTimeOffset]::UtcNow.ToString(
            'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture
        )
        if (-not (Test-CddsiD027GitDownloadReceipt -Receipt $receipt -ArtifactDescriptor $ArtifactDescriptor -ExpectedDestinationPath $InstallerPath -ExpectedFileIdentityToken $installerObservation.FileIdentityToken -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $validationNow)) {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_DOWNLOAD_RECEIPT_INVALID' -MessageSafe 'The Git download receipt was stale, tampered or not bound to the installer bytes.'
        }
        try {
            $resolvedDescriptor = Resolve-CddsiD027GitInstallerDescriptor -ArtifactDescriptor $ArtifactDescriptor -InstallerObservation $installerObservation
            $originalSource = $receipt.SourceObservation
            $resolvedSourceWithoutBinding = [pscustomobject][ordered]@{
                SchemaVersion = $originalSource.SchemaVersion
                ContractVersion = $originalSource.ContractVersion
                RunId = $originalSource.RunId
                ArtifactProfile = $originalSource.ArtifactProfile
                DescriptorId = $originalSource.DescriptorId
                MetadataBindingToken = $resolvedDescriptor.MetadataBindingToken
                RequestUri = $originalSource.RequestUri
                FinalUri = $originalSource.FinalUri
                RedirectUris = @($originalSource.RedirectUris)
                RedirectChainBindingToken = $originalSource.RedirectChainBindingToken
                RedirectCount = $originalSource.RedirectCount
                ArtifactSha256 = $originalSource.ArtifactSha256
                ArtifactSizeBytes = $originalSource.ArtifactSizeBytes
                ObservationId = $originalSource.ObservationId
                ObservedAtUtc = $originalSource.ObservedAtUtc
            }
            $resolvedSourceValues = [ordered]@{}
            foreach ($property in $resolvedSourceWithoutBinding.PSObject.Properties) {
                $resolvedSourceValues[$property.Name] = $property.Value
            }
            $resolvedSourceValues['SourceObservationBindingToken'] = Get-CddsiSourceObservationBindingToken -Observation $resolvedSourceWithoutBinding
            $resolvedSource = [pscustomobject]$resolvedSourceValues
            $fileObservation = [pscustomobject][ordered]@{
                SchemaVersion = 1
                FileIdentityToken = $installerObservation.FileIdentityToken
                ArtifactSha256 = $installerObservation.ArtifactSha256
                ArtifactSizeBytes = [long]$installerObservation.ArtifactSizeBytes
            }
            $signatureObservation = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ArtifactSha256 = $installerObservation.ArtifactSha256
                AuthenticodeStatus = $installerObservation.AuthenticodeStatus
                ChainTrusted = [bool]$installerObservation.ChainTrusted
                SignerThumbprint = $installerObservation.SignerThumbprint
                SignerSubjectToken = $installerObservation.SignerSubjectToken
                PublisherToken = $installerObservation.PublisherToken
                IdentityToken = $installerObservation.IdentityToken
                Architecture = $installerObservation.DeclaredPayloadArchitecture
                ArtifactVersion = $installerObservation.ArtifactVersion
                ObservationId = $installerObservation.ObservationId
                ObservedAtUtc = $installerObservation.ObservedAtUtc
            }
            $evidence = New-CddsiSignatureEvidenceVerdict -Descriptor $resolvedDescriptor -ExpectedArtifactType GitForWindowsInstaller -PathBindingToken (Get-CddsiPathBindingToken -Path $InstallerPath) -SourceObservation $resolvedSource -FileObservation $fileObservation -SignatureObservation $signatureObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $validationNow
        }
        catch {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_SIGNATURE_REJECTED' -MessageSafe 'The Git installer signer, publisher, identity or immutable binding was rejected.'
        }
        if (-not $evidence.Valid) {
            return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_SIGNATURE_REJECTED' -MessageSafe 'The Git installer signature evidence did not match the official artifact contract.'
        }
        $bundle = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-git-verification-bundle-v1'
            ResolvedDescriptor = $resolvedDescriptor
            ResolvedSourceObservation = $resolvedSource
            SignatureEvidence = $evidence
            SignatureType = $installerObservation.SignatureType
            ChainRevocationMode = $installerObservation.ChainRevocationMode
            ValidationTimeUtc = $validationNow
            DownloadReceiptBindingToken = $receipt.ReceiptBindingToken
        }
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'The Git installer embedded signature, publisher, identity, x86 bootstrap and metadata-bound x64 target contract were verified.' -Data $bundle
    }

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

function Get-CddsiD027GitPersistentPathObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ExpectedArtifactVersion
    )

    Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
    $parsedVersion = $null
    if (
        -not (Test-CddsiCanonicalUuidValue -Value $Context.RunId) -or
        -not [version]::TryParse($ExpectedArtifactVersion, [ref]$parsedVersion) -or
        $parsedVersion.Revision -lt 1
    ) {
        throw 'Persistent Git PATH readback requires an exact four-component artifact version.'
    }
    $expectedGitVersion = '{0}.{1}.{2}.windows.{3}' -f (
        $parsedVersion.Major,
        $parsedVersion.Minor,
        $parsedVersion.Build,
        $parsedVersion.Revision
    )

    $machineBase = $null
    $machineKey = $null
    $userKey = $null
    $priorProcessPath = [Environment]::GetEnvironmentVariable('Path', 'Process')
    try {
        $machineBase = [Microsoft.Win32.RegistryKey]::OpenBaseKey(
            [Microsoft.Win32.RegistryHive]::LocalMachine,
            [Microsoft.Win32.RegistryView]::Registry64
        )
        $machineKey = $machineBase.OpenSubKey(
            'SYSTEM\CurrentControlSet\Control\Session Manager\Environment',
            $false
        )
        $userKey = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('Environment', $false)
        if ($null -eq $machineKey) {
            throw 'Machine environment registry key was missing.'
        }
        $readPathValue = {
            param(
                [AllowNull()]$RegistryKey,
                [bool]$Required
            )

            if ($null -eq $RegistryKey) {
                if ($Required) { throw 'Required PATH registry key was missing.' }
                return [pscustomobject][ordered]@{ Kind = 'Missing'; Value = '' }
            }
            $pathNames = @(
                $RegistryKey.GetValueNames() |
                    Where-Object { [string]::Equals($_, 'Path', [StringComparison]::OrdinalIgnoreCase) }
            )
            if ($pathNames.Count -eq 0) {
                if ($Required) { throw 'Required PATH registry value was missing.' }
                return [pscustomobject][ordered]@{ Kind = 'Missing'; Value = '' }
            }
            if ($pathNames.Count -ne 1) {
                throw 'PATH registry value identity was ambiguous.'
            }
            $valueName = [string]$pathNames[0]
            $kind = $RegistryKey.GetValueKind($valueName)
            if ($kind -notin @(
                [Microsoft.Win32.RegistryValueKind]::String,
                [Microsoft.Win32.RegistryValueKind]::ExpandString
            )) {
                throw 'PATH registry kind was invalid.'
            }
            $value = $RegistryKey.GetValue(
                $valueName,
                $null,
                [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
            )
            if ($value -isnot [string] -or $value.Length -gt 32767 -or $value.Contains([char]0)) {
                throw 'PATH registry value was invalid.'
            }
            return [pscustomobject][ordered]@{
                Kind = [string]$kind
                Value = $value
            }
        }

        $machineBefore = & $readPathValue $machineKey $true
        $userBefore = & $readPathValue $userKey $false
        $machinePath = $machineBefore.Value
        $userPath = $userBefore.Value
        $effectivePath = if ([string]::IsNullOrEmpty($userPath)) {
            $machinePath
        }
        elseif ([string]::IsNullOrEmpty($machinePath)) {
            $userPath
        }
        else {
            $machinePath.TrimEnd(';') + ';' + $userPath.TrimStart(';')
        }
        [Environment]::SetEnvironmentVariable('Path', $effectivePath, 'Process')
        $gitObservation = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $Context -MinimumVersion $ExpectedArtifactVersion
        $machineAfter = & $readPathValue $machineKey $true
        $userAfter = & $readPathValue $userKey $false
        $pathStable = (
            $machineAfter.Kind -ceq $machineBefore.Kind -and
            [string]::Equals($machineAfter.Value, $machineBefore.Value, [StringComparison]::Ordinal) -and
            $userAfter.Kind -ceq $userBefore.Kind -and
            [string]::Equals($userAfter.Value, $userBefore.Value, [StringComparison]::Ordinal)
        )
        $trusted = (
            $pathStable -and
            $gitObservation.Status -ceq 'SUCCEEDED' -and
            $gitObservation.Data.CapabilityStatus -ceq 'READY' -and
            $gitObservation.Data.ReuseEligible -eq $true -and
            $gitObservation.Data.Version -ceq $expectedGitVersion -and
            $gitObservation.Data.Source -ceq 'GitForWindows' -and
            $gitObservation.Data.IdentityStatus -ceq 'Trusted' -and
            $gitObservation.Data.CapabilityState -ceq 'Operational'
        )
        $pathReceiptToken = Get-CddsiSupplyChainTextBindingToken -Text (
            @(
                'RunId={0}' -f $Context.RunId
                'MachineKind={0}' -f $machineBefore.Kind
                'MachinePathSha256={0}' -f (Get-CddsiSupplyChainTextBindingToken -Text $machineBefore.Value)
                'UserKind={0}' -f $userBefore.Kind
                'UserPathSha256={0}' -f (Get-CddsiSupplyChainTextBindingToken -Text $userBefore.Value)
                'ExpectedGitVersion={0}' -f $expectedGitVersion
                'ObservedExecutableToken={0}' -f (
                    if ($null -eq $gitObservation.Data) { '' } else { $gitObservation.Data.ExecutableToken }
                )
                'ObservedGitVersion={0}' -f (
                    if ($null -eq $gitObservation.Data) { '' } else { $gitObservation.Data.Version }
                )
                'CapabilityStatus={0}' -f (
                    if ($null -eq $gitObservation.Data) { 'UNKNOWN' } else { $gitObservation.Data.CapabilityStatus }
                )
                'PathStable={0}' -f $pathStable.ToString().ToLowerInvariant()
            ) -join "`n"
        )
        return New-CddsiOperationResult -Operation 'ObserveGitPersistentPath' -Status 'SUCCEEDED' -Mode Live -MessageSafe 'Machine and user PATH were read back and evaluated through the protected Git observer.' -Data ([pscustomobject][ordered]@{
            SchemaVersion = 1
            PathReadbackStatus = if ($trusted) { 'Trusted' } else { 'Untrusted' }
            PathReceiptBindingToken = $pathReceiptToken
            ExpectedGitVersion = $expectedGitVersion
            ObservedGitVersion = if ($null -eq $gitObservation.Data) { $null } else { $gitObservation.Data.Version }
            ObservedExecutableToken = if ($null -eq $gitObservation.Data) { $null } else { $gitObservation.Data.ExecutableToken }
            CapabilityStatus = if ($null -eq $gitObservation.Data) { 'UNKNOWN' } else { $gitObservation.Data.CapabilityStatus }
            ReasonCodes = if ($trusted) {
                @()
            }
            elseif (-not $pathStable) {
                @('GIT_PERSISTENT_PATH_CHANGED_DURING_READBACK')
            }
            elseif ($null -eq $gitObservation.Data) {
                @('GIT_PATH_READBACK_FAILED')
            }
            else {
                @($gitObservation.Data.ReasonCodes)
            }
        })
    }
    catch {
        return New-CddsiOperationResult -Operation 'ObserveGitPersistentPath' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_PATH_READBACK_FAILED' -MessageSafe 'The persistent machine and user PATH could not be read back safely.'
    }
    finally {
        [Environment]::SetEnvironmentVariable('Path', $priorProcessPath, 'Process')
        if ($null -ne $userKey) { $userKey.Dispose() }
        if ($null -ne $machineKey) { $machineKey.Dispose() }
        if ($null -ne $machineBase) { $machineBase.Dispose() }
    }
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
        [switch]$AcknowledgeRealChanges,
        [AllowNull()][string]$ExternalSnapshotAuthorizationBindingToken = $null
    )

    if ($Mode -eq 'Live') {
        Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
        $snapshotAuthorization = $script:CddsiD027GitLiveSessionAuthorization
        $snapshotReceipt = $snapshotAuthorization.Receipt
        if (-not $AcknowledgeRealChanges) {
            return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'ACTION_REQUIRED' -Mode Live -ErrorCode 'GIT_INSTALL_CONFIRMATION_REQUIRED' -MessageSafe 'Explicit Git install, UAC and machine PATH confirmation is required.'
        }
        if (
            $ExternalSnapshotAuthorizationBindingToken -isnot [string] -or
            $ExternalSnapshotAuthorizationBindingToken -cne $snapshotReceipt.ReceiptBindingToken -or
            $ArtifactProfile -cne 'VmAcceptance'
        ) {
            return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'ACTION_REQUIRED' -Mode Live -ErrorCode 'GIT_INSTALL_SNAPSHOT_AUTHORIZATION_REQUIRED' -MessageSafe 'The active exact VM-external snapshot authorization must be explicitly bound to this Git VmAcceptance installation.'
        }
        if (Test-CddsiCurrentProcessElevated) {
            return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'ACTION_REQUIRED' -Mode Live -ErrorCode 'GIT_INSTALL_PARENT_ELEVATED_UNSUPPORTED' -MessageSafe 'Run the product from a non-elevated PowerShell session and approve only the installer UAC prompt.'
        }

        $unresolvedDescriptor = $ArtifactDescriptor
        $providedReceipt = $SourceObservation
        $verificationBundle = $null
        if (
            $null -ne $SignatureEvidence -and
            $null -ne $SignatureEvidence.PSObject.Properties['Data'] -and
            $SignatureEvidence.Status -ceq 'SUCCEEDED' -and
            $null -ne $SignatureEvidence.Data -and
            $SignatureEvidence.Data.ContractVersion -ceq 'cddsi-d027-git-verification-bundle-v1'
        ) {
            $verificationBundle = $SignatureEvidence.Data
        }
        elseif (
            $null -ne $SignatureEvidence -and
            $SignatureEvidence.ContractVersion -ceq 'cddsi-d027-git-verification-bundle-v1'
        ) {
            $verificationBundle = $SignatureEvidence
        }
        if (
            $null -ne $providedReceipt -and
            $null -ne $providedReceipt.PSObject.Properties['Data'] -and
            $providedReceipt.Status -ceq 'SUCCEEDED'
        ) {
            $providedReceipt = $providedReceipt.Data
        }

        $bundleValid = $false
        $downloadReceiptBindingToken = $null
        try {
            $bundleFields = @(
                'SchemaVersion', 'ContractVersion', 'ResolvedDescriptor',
                'ResolvedSourceObservation', 'SignatureEvidence', 'SignatureType', 'ChainRevocationMode',
                'ValidationTimeUtc', 'DownloadReceiptBindingToken'
            )
            if (
                -not (Test-CddsiExactPropertySet -InputObject $verificationBundle -Expected $bundleFields) -or
                -not (Test-CddsiSchemaVersionOne -Value $verificationBundle.SchemaVersion) -or
                $verificationBundle.ContractVersion -isnot [string] -or
                $verificationBundle.ContractVersion -cne 'cddsi-d027-git-verification-bundle-v1' -or
                $verificationBundle.SignatureType -isnot [string] -or
                $verificationBundle.SignatureType -cne 'Authenticode' -or
                $verificationBundle.ChainRevocationMode -isnot [string] -or
                $verificationBundle.ChainRevocationMode -cne 'NotChecked' -or
                $verificationBundle.DownloadReceiptBindingToken -isnot [string] -or
                $verificationBundle.DownloadReceiptBindingToken -notmatch '^[a-f0-9]{64}$' -or
                -not (Test-CddsiUtcTimestampValue -Value $verificationBundle.ValidationTimeUtc) -or
                -not (Test-CddsiArtifactDescriptor -Descriptor $unresolvedDescriptor -ExpectedArtifactType GitForWindowsInstaller) -or
                $unresolvedDescriptor.MetadataStatus -cne 'UNRESOLVED' -or
                $unresolvedDescriptor.Architecture -cne 'x64' -or
                -not (Test-CddsiArtifactDescriptor -Descriptor $verificationBundle.ResolvedDescriptor -ExpectedArtifactType GitForWindowsInstaller -RequireResolved) -or
                $verificationBundle.ResolvedDescriptor.Architecture -cne 'x64'
            ) {
                throw 'Git verification bundle schema or descriptor state was invalid.'
            }
            foreach ($name in @(
                'DescriptorId', 'ArtifactType', 'SourcePolicy', 'SourceUri',
                'SourceUriBindingToken', 'ReleaseVersion', 'Architecture', 'Channel',
                'FileNameToken', 'ExpectedArtifactSha256', 'ExpectedArtifactSizeBytes',
                'RedirectPolicy', 'MaximumBytes'
            )) {
                if ($unresolvedDescriptor.$name -cne $verificationBundle.ResolvedDescriptor.$name) {
                    throw 'Git verification bundle changed immutable release metadata.'
                }
            }
            $bundlePayload = Get-CddsiSignatureEvidencePayload -Evidence $verificationBundle.SignatureEvidence
            $receiptValidationTime = [DateTimeOffset]::UtcNow.ToString(
                'yyyy-MM-ddTHH:mm:ssZ',
                [Globalization.CultureInfo]::InvariantCulture
            )
            if (
                -not (Test-CddsiD027GitDownloadReceipt -Receipt $providedReceipt -ArtifactDescriptor $unresolvedDescriptor -ExpectedDestinationPath $InstallerPath -ExpectedFileIdentityToken $bundlePayload.FileIdentityToken -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $receiptValidationTime) -or
                $providedReceipt.ReceiptBindingToken -cne $verificationBundle.DownloadReceiptBindingToken
            ) {
                throw 'Git download receipt did not match the verification bundle.'
            }

            $ArtifactDescriptor = $verificationBundle.ResolvedDescriptor
            $SourceObservation = $verificationBundle.ResolvedSourceObservation
            $SignatureEvidence = $verificationBundle.SignatureEvidence
            $ValidationTimeUtc = $verificationBundle.ValidationTimeUtc
            $downloadReceiptBindingToken = $providedReceipt.ReceiptBindingToken
            $bundleValid = (
                Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $InstallerPath -ExpectedArtifactType GitForWindowsInstaller -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc
            )
        }
        catch {
            $bundleValid = $false
        }
        if (-not $bundleValid) {
            return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALL_EVIDENCE_INVALID' -MessageSafe 'Fresh Git download, source and signature evidence is required before installation.'
        }
        $validationTimestamp = [DateTimeOffset]::Parse($ValidationTimeUtc)
        $currentTimestamp = [DateTimeOffset]::UtcNow
        if (
            $validationTimestamp -gt $currentTimestamp.AddSeconds(30) -or
            ($currentTimestamp - $validationTimestamp).TotalSeconds -gt 900
        ) {
            return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALL_EVIDENCE_STALE' -MessageSafe 'Git installer evidence was stale or from the future.'
        }

        $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
        $pathBindingToken = Get-CddsiPathBindingToken -Path $InstallerPath
        $policy = Get-CddsiD027GitInstallerProcessPolicy
        $lockStream = $null
        $process = $null
        $started = $false
        $uacCancelled = $false
        $exitCode = $null
        $timedOut = $false
        $installerStillRunning = $false
        $completionObservationFailed = $false
        $postInstallAuthorizationValid = $false
        $readbackObservationFailed = $false
        $preExecutionObservation = $null
        $startSnapshotEvidence = $null
        $workingDirectory = $null
        try {
            $lockStream = [System.IO.File]::Open(
                [System.IO.Path]::GetFullPath($InstallerPath),
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read
            )
            $preExecutionResult = Get-CddsiD027GitInstallerObservation -ExecutionContext $Context -InstallerPath $InstallerPath -ArtifactDescriptor $ArtifactDescriptor
            if ($preExecutionResult.Status -cne 'SUCCEEDED') {
                throw 'Git installer execution-time observation failed.'
            }
            $preExecutionObservation = $preExecutionResult.Data
            if (
                $preExecutionObservation.FileIdentityToken -cne $payload.FileIdentityToken -or
                -not (Test-CddsiArtifactHashBinding -ActualSha256 $preExecutionObservation.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
                [long]$preExecutionObservation.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes -or
                $preExecutionObservation.SignerThumbprint -cne $payload.SignerThumbprint -or
                $preExecutionObservation.SignerSubjectToken -cne $payload.SignerSubjectToken -or
                $preExecutionObservation.PublisherToken -cne $payload.PublisherToken -or
                $preExecutionObservation.IdentityToken -cne $payload.IdentityToken -or
                $preExecutionObservation.SignatureType -cne $verificationBundle.SignatureType -or
                -not $preExecutionObservation.ChainTrusted -or
                $preExecutionObservation.ChainRevocationMode -cne $verificationBundle.ChainRevocationMode -or
                $preExecutionObservation.BootstrapPeMachine -cne 'x86' -or
                $preExecutionObservation.DeclaredPayloadArchitecture -cne 'x64' -or
                $preExecutionObservation.ArchitectureBindingSource -cne 'OfficialMetadataDigestAndFileName' -or
                $preExecutionObservation.ArtifactVersion -cne $ArtifactDescriptor.ReleaseVersion
            ) {
                throw 'Git installer changed after signature verification.'
            }
            Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
            $snapshotAuthorization = $script:CddsiD027GitLiveSessionAuthorization
            if (
                $ExternalSnapshotAuthorizationBindingToken -cne
                    $snapshotAuthorization.Receipt.ReceiptBindingToken
            ) {
                throw 'Git snapshot authorization changed before process start.'
            }
            Assert-CddsiD027GitDirectorySecurity `
                -Path ([string]$Context.Paths.Temp) `
                -Purpose ProductTemp |
                Out-Null
            $workingDirectory = Assert-CddsiD027GitDirectorySecurity `
                -Path ([Environment]::SystemDirectory) `
                -Purpose ProtectedSystem
            $startSnapshotEvidence = [pscustomobject][ordered]@{
                ReceiptSha256 = $snapshotAuthorization.ReceiptSha256
                ReceiptBindingToken = $snapshotAuthorization.Receipt.ReceiptBindingToken
                AuthorityId = $snapshotAuthorization.Receipt.AuthorityId
                AuthorityKeySha256 = $snapshotAuthorization.Receipt.AuthorityKeySha256
                ExecutionArtifactSha256 =
                    $snapshotAuthorization.Receipt.ExecutionArtifactSha256
                SnapshotIdentitySha256 =
                    $snapshotAuthorization.Receipt.SnapshotIdentitySha256
                WorkloadBindingToken =
                    $snapshotAuthorization.Receipt.WorkloadBindingToken
            }
            try {
                $process = Start-Process -FilePath ([System.IO.Path]::GetFullPath($InstallerPath)) -ArgumentList $policy.ArgumentList -Verb $policy.Verb -WorkingDirectory $workingDirectory -WindowStyle $policy.WindowStyle -PassThru -ErrorAction Stop
                $started = $true
            }
            catch {
                $exception = $_.Exception
                while ($null -ne $exception -and $exception -isnot [ComponentModel.Win32Exception]) {
                    $exception = $exception.InnerException
                }
                if ($null -ne $exception -and $exception.NativeErrorCode -eq 1223) {
                    $uacCancelled = $true
                }
                else {
                    throw 'Git installer process could not be started.'
                }
            }
            if ($started) {
                if ($process.WaitForExit([int]($policy.TimeoutSeconds * 1000))) {
                    $exitCode = [int]$process.ExitCode
                }
                else {
                    $timedOut = $true
                    $installerStillRunning = $true
                }
            }
        }
        catch {
            if (-not $started -and -not $uacCancelled) {
                return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'FAILED' -Mode Live -ErrorCode 'GIT_INSTALL_PREEXECUTION_FAILED' -MessageSafe 'The Git installer changed, failed final verification or could not be started.'
            }
            if ($started) {
                $completionObservationFailed = $true
            }
        }
        finally {
            if ($null -ne $process) { $process.Dispose() }
            if ($null -ne $lockStream) { $lockStream.Dispose() }
        }

        $pathReadback = $null
        if (Test-CddsiD027GitPostInstallReadbackEligible `
                -Started $started `
                -InstallerStillRunning $installerStillRunning `
                -CompletionObservationFailed $completionObservationFailed `
                -ExitCode $exitCode) {
            try {
                Assert-CddsiD027GitLiveContext -ExecutionContext $Context | Out-Null
                $postInstallAuthorization = $script:CddsiD027GitLiveSessionAuthorization
                if (
                    $ExternalSnapshotAuthorizationBindingToken -cne
                        $postInstallAuthorization.Receipt.ReceiptBindingToken -or
                    $startSnapshotEvidence.ReceiptBindingToken -cne
                        $postInstallAuthorization.Receipt.ReceiptBindingToken -or
                    $startSnapshotEvidence.AuthorityKeySha256 -cne
                        $postInstallAuthorization.Receipt.AuthorityKeySha256
                ) {
                    throw 'Git snapshot authorization changed after installer completion.'
                }
                $postInstallAuthorizationValid = $true
            }
            catch {
                $postInstallAuthorizationValid = $false
            }
            if ($postInstallAuthorizationValid) {
                try {
                    $pathReadback = Get-CddsiD027GitPersistentPathObservation `
                        -ExecutionContext $Context `
                        -ExpectedArtifactVersion $ArtifactDescriptor.ReleaseVersion
                    if (
                        $null -eq $pathReadback -or
                        $pathReadback.Status -cne 'SUCCEEDED'
                    ) {
                        $readbackObservationFailed = $true
                    }
                }
                catch {
                    $pathReadback = $null
                    $readbackObservationFailed = $true
                }
            }
        }
        $readbackTrusted = (
            $null -ne $pathReadback -and
            $pathReadback.Status -ceq 'SUCCEEDED' -and
            $pathReadback.Data.PathReadbackStatus -ceq 'Trusted'
        )
        $disposition = ConvertTo-CddsiD027GitInstallerExitResult `
            -Started $started `
            -UacCancelled $uacCancelled `
            -ExitCode $exitCode `
            -ReadbackTrusted $readbackTrusted `
            -ChangedObserved $started `
            -RestartObserved ($null -ne $exitCode -and [int]$exitCode -eq 8) `
            -CompletionObservationFailed $completionObservationFailed `
            -InstallerStillRunning $installerStillRunning `
            -PostInstallAuthorizationInvalid (
                $started -and
                -not $installerStillRunning -and
                -not $completionObservationFailed -and
                $null -ne $exitCode -and
                [int]$exitCode -eq 0 -and
                -not $postInstallAuthorizationValid
            ) `
            -ReadbackObservationFailed $readbackObservationFailed
        $data = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-git-install-receipt-v1'
            ArtifactType = 'GitForWindowsInstaller'
            DescriptorId = $ArtifactDescriptor.DescriptorId
            MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken
            DownloadReceiptBindingToken = $downloadReceiptBindingToken
            SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken
            SignatureEvidenceBindingToken = $payload.EvidenceBindingToken
            InstallerPathBindingToken = $pathBindingToken
            FileIdentityToken = if ($null -eq $preExecutionObservation) { $payload.FileIdentityToken } else { $preExecutionObservation.FileIdentityToken }
            ArtifactSha256 = $payload.ArtifactSha256
            ArtifactSizeBytes = [long]$payload.ArtifactSizeBytes
            BootstrapPeMachine = 'x86'
            DeclaredPayloadArchitecture = 'x64'
            ArchitectureBindingSource = 'OfficialMetadataDigestAndFileName'
            SignatureType = $verificationBundle.SignatureType
            ChainRevocationMode = $verificationBundle.ChainRevocationMode
            ProcessPolicyBindingToken = $policy.PolicyBindingToken
            ExternalSnapshotReceiptSha256 = $startSnapshotEvidence.ReceiptSha256
            ExternalSnapshotAuthorizationBindingToken =
                $startSnapshotEvidence.ReceiptBindingToken
            SnapshotAuthorityId = $startSnapshotEvidence.AuthorityId
            SnapshotAuthorityKeySha256 = $startSnapshotEvidence.AuthorityKeySha256
            ExecutionArtifactSha256 = $startSnapshotEvidence.ExecutionArtifactSha256
            SnapshotIdentitySha256 = $startSnapshotEvidence.SnapshotIdentitySha256
            SnapshotWorkloadBindingToken = $startSnapshotEvidence.WorkloadBindingToken
            ProcessStarted = $started
            UacCancelled = $uacCancelled
            InstallerExitCode = $exitCode
            TimedOut = $timedOut
            InstallerStillRunning = $installerStillRunning
            CompletionObservationFailed = $completionObservationFailed
            PostInstallAuthorizationValid = $postInstallAuthorizationValid
            ReadbackObservationFailed = $readbackObservationFailed
            PersistentPathReadbackStatus = if (
                $null -eq $pathReadback -or
                $null -eq $pathReadback.Data -or
                $pathReadback.Data.PathReadbackStatus -isnot [string]
            ) {
                'NotObserved'
            }
            else {
                $pathReadback.Data.PathReadbackStatus
            }
            PersistentPathReceiptBindingToken = if ($null -eq $pathReadback -or $null -eq $pathReadback.Data) { $null } else { $pathReadback.Data.PathReceiptBindingToken }
            ExecutionHashReverified = ($null -ne $preExecutionObservation)
            AuthenticodeReverified = ($null -ne $preExecutionObservation)
            LiveInstallImplemented = $true
        }
        $message = switch ($disposition.Status) {
            'SUCCEEDED' { 'Git for Windows was installed and the persistent PATH, protected x64 bundle, version and registry receipt were read back.'; break }
            'CANCELLED' { 'The Git installer UAC prompt was cancelled; installation did not start.'; break }
            'RESTART_REQUIRED' { 'The Git installer requires a manual Windows restart; no automatic restart was attempted.'; break }
            'PARTIAL' {
                if ($installerStillRunning) {
                    'The elevated Git installer was still running at the bounded timeout; no completion or persistent PATH readback was claimed.'
                }
                else {
                    'The Git installer started but did not reach a signed-authorized trusted terminal readback; restore the external snapshot or complete the indicated recovery.'
                }
                break
            }
            default { 'The Git installer did not start or did not complete successfully.'; break }
        }
        return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status $disposition.Status -Changed $disposition.Changed -Mode Live -ErrorCode $disposition.ErrorCode -MessageSafe $message -Data $data -RestartRequired $disposition.RestartRequired
    }

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
        (($current.ArtifactSizeBytes -isnot [int]) -and
            ($current.ArtifactSizeBytes -isnot [long])) -or
        [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 Git installer hash/size 复验失败；拒绝安装。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'GitForWindowsInstaller'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'Git installer hash was reverified through the fake provider; installation remains disabled.' -Data $data -PlannedChanges @('<INSTALL:GIT_FOR_WINDOWS>')
}
