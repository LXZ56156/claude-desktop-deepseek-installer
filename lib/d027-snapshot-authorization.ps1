# d027-snapshot-authorization.ps1 - D-027 external clean-snapshot authorization contracts.
# Loading this file defines contracts only and performs no host observation or mutation.

$script:CddsiD027ExternalSnapshotReceiptMaximumBytes = [long](32KB)
$script:CddsiD027CandidateZipMaximumBytes = [long](1GB)
$script:CddsiD027CandidateSbomMaximumBytes = [long](8MB)
$script:CddsiD027CredentialHelperPeMaximumBytes = [long](100MB)
$script:CddsiD027ClaudeSnapshotMsixMaximumBytes = [long](1GB)
$script:CddsiD027ClaudeSnapshotWorkloadBindingDomain =
    'cddsi-d027-claude-machine-wide-snapshot-workload-binding-v1'
$script:CddsiD027ClaudeAcquisitionWorkloadBindingDomain =
    'cddsi-d027-claude-msix-acquisition-workload-binding-v1'
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
$script:CddsiD027ClaudeSnapshotWorkloadFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'WorkloadKind',
    'RunId',
    'Stage',
    'EnvironmentTier',
    'ArtifactProfile',
    'Operation',
    'CandidateCommitSha',
    'CandidateTreeSha',
    'CandidateZipSha256',
    'CandidateZipLengthBytes',
    'CandidateContentManifestBindingToken',
    'CandidateSbomSha256',
    'CandidateSbomLengthBytes',
    'CredentialHelperSourceTreeSha256',
    'CredentialHelperSourceManifestSha256',
    'CredentialHelperPeSha256',
    'CredentialHelperPeLengthBytes',
    'CredentialHelperBuildDescriptorBindingToken',
    'CredentialHelperSignatureEvidenceBindingToken',
    'ClaudeMsixSha256',
    'ClaudeMsixLengthBytes',
    'ClaudeMsixContentBindingToken',
    'ClaudeDownloadReceiptBindingToken',
    'ClaudeHeldFileIdentityToken',
    'ClaudeManifestBindingToken',
    'ClaudePackageIdentityBindingToken',
    'ClaudeSignatureEvidenceBindingToken',
    'WorkloadBindingToken'
)
$script:CddsiD027ClaudeAcquisitionWorkloadFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'WorkloadKind',
    'RunId',
    'Stage',
    'EnvironmentTier',
    'ArtifactProfile',
    'Operation',
    'CandidateCommitSha',
    'CandidateTreeSha',
    'CandidateZipSha256',
    'CandidateZipLengthBytes',
    'CandidateContentManifestBindingToken',
    'CandidateSbomSha256',
    'CandidateSbomLengthBytes',
    'SourceDescriptorBindingToken',
    'SourceUriBindingToken',
    'Architecture',
    'Channel',
    'StagingRootPathBindingToken',
    'DestinationPathBindingToken',
    'WorkloadBindingToken'
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
$script:CddsiD027ClaudeAcquisitionLiveSessionAuthorizationFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'Receipt',
    'ReceiptSha256',
    'ReceiptLengthBytes',
    'WorkloadDescriptor',
    'AuthorizedAtUtc',
    'InitialPlatformObservation'
)
$script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization = $null
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

function Get-CddsiD027ClaudeAcquisitionWorkloadBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$WorkloadDescriptor
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeAcquisitionWorkloadFieldNames |
            Where-Object { $_ -cne 'WorkloadBindingToken' }
    )
    $validNames = (
        (Test-CddsiExactPropertySet `
            -InputObject $WorkloadDescriptor `
            -Expected $withoutBinding) -or
        (Test-CddsiExactPropertySet `
            -InputObject $WorkloadDescriptor `
            -Expected $script:CddsiD027ClaudeAcquisitionWorkloadFieldNames)
    )
    if (-not $validNames) {
        throw 'D-027 Claude acquisition workload did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    $canonical.Add($script:CddsiD027ClaudeAcquisitionWorkloadBindingDomain)
    foreach ($name in $withoutBinding) {
        $value = $WorkloadDescriptor.$name
        $text = if ($value -is [string]) {
            $value
        }
        elseif ($value -is [int] -or $value -is [long]) {
            [Convert]::ToString(
                [long]$value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        else {
            throw 'D-027 Claude acquisition workload contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text)
        )
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function New-CddsiD027ClaudeAcquisitionWorkloadDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$CandidateCommitSha,
        [Parameter(Mandatory = $true)][string]$CandidateTreeSha,
        [Parameter(Mandatory = $true)][string]$CandidateZipSha256,
        [Parameter(Mandatory = $true)][long]$CandidateZipLengthBytes,
        [Parameter(Mandatory = $true)]
        [string]$CandidateContentManifestBindingToken,
        [Parameter(Mandatory = $true)][string]$CandidateSbomSha256,
        [Parameter(Mandatory = $true)][long]$CandidateSbomLengthBytes,
        [Parameter(Mandatory = $true)][string]$StagingRootPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    $sourceDescriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
    if (
        $StagingRootPath.Length -gt 240 -or
        $DestinationPath.Length -gt 240 -or
        -not (Test-CddsiD027ClaudeDesktopSourceDescriptor `
            -Descriptor $sourceDescriptor) -or
        -not (Test-CddsiD027ClaudeDownloadDestinationPath `
            -StagingRootPath $StagingRootPath `
            -DestinationPath $DestinationPath)
    ) {
        throw 'D-027 Claude acquisition source or destination was invalid.'
    }

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion =
            'cddsi-d027-claude-msix-acquisition-workload-v1'
        WorkloadKind = 'ClaudeDesktopMsixAcquisition'
        RunId = $RunId
        Stage = 'VmAcceptance'
        EnvironmentTier = 'VmAcceptance'
        ArtifactProfile = 'VmAcceptance'
        Operation = 'AcquireClaudeDesktopMsix'
        CandidateCommitSha = $CandidateCommitSha
        CandidateTreeSha = $CandidateTreeSha
        CandidateZipSha256 = $CandidateZipSha256
        CandidateZipLengthBytes = [long]$CandidateZipLengthBytes
        CandidateContentManifestBindingToken =
            $CandidateContentManifestBindingToken
        CandidateSbomSha256 = $CandidateSbomSha256
        CandidateSbomLengthBytes = [long]$CandidateSbomLengthBytes
        SourceDescriptorBindingToken = $sourceDescriptor.MetadataBindingToken
        SourceUriBindingToken = $sourceDescriptor.SourceUriBindingToken
        Architecture = 'x64'
        Channel = 'Standard'
        StagingRootPathBindingToken =
            Get-CddsiPathBindingToken -Path $StagingRootPath
        DestinationPathBindingToken =
            Get-CddsiPathBindingToken -Path $DestinationPath
    }
    $values = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $values[$property.Name] = $property.Value
    }
    $values['WorkloadBindingToken'] =
        Get-CddsiD027ClaudeAcquisitionWorkloadBindingToken `
            -WorkloadDescriptor $withoutBinding
    $descriptor = [pscustomobject]$values
    if (-not (Test-CddsiD027ClaudeAcquisitionWorkloadDescriptor `
        -WorkloadDescriptor $descriptor)) {
        throw 'D-027 Claude acquisition workload failed its exact contract.'
    }
    return $descriptor
}

function Test-CddsiD027ClaudeAcquisitionWorkloadDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$WorkloadDescriptor
    )

    try {
        if (
            $null -eq $WorkloadDescriptor -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $WorkloadDescriptor `
                -Expected $script:CddsiD027ClaudeAcquisitionWorkloadFieldNames)
        ) {
            return $false
        }

        $runId = [guid]::Empty
        if (
            -not (Test-CddsiSchemaVersionOne `
                -Value $WorkloadDescriptor.SchemaVersion) -or
            $WorkloadDescriptor.ContractVersion -isnot [string] -or
            $WorkloadDescriptor.ContractVersion -cne
                'cddsi-d027-claude-msix-acquisition-workload-v1' -or
            $WorkloadDescriptor.WorkloadKind -isnot [string] -or
            $WorkloadDescriptor.WorkloadKind -cne
                'ClaudeDesktopMsixAcquisition' -or
            $WorkloadDescriptor.RunId -isnot [string] -or
            -not [guid]::TryParse(
                $WorkloadDescriptor.RunId,
                [ref]$runId
            ) -or
            $runId -eq [guid]::Empty -or
            $WorkloadDescriptor.RunId -cne $runId.ToString('D') -or
            $WorkloadDescriptor.Stage -isnot [string] -or
            $WorkloadDescriptor.Stage -cne 'VmAcceptance' -or
            $WorkloadDescriptor.EnvironmentTier -isnot [string] -or
            $WorkloadDescriptor.EnvironmentTier -cne 'VmAcceptance' -or
            $WorkloadDescriptor.ArtifactProfile -isnot [string] -or
            $WorkloadDescriptor.ArtifactProfile -cne 'VmAcceptance' -or
            $WorkloadDescriptor.Operation -isnot [string] -or
            $WorkloadDescriptor.Operation -cne 'AcquireClaudeDesktopMsix' -or
            $WorkloadDescriptor.Architecture -isnot [string] -or
            $WorkloadDescriptor.Architecture -cne 'x64' -or
            $WorkloadDescriptor.Channel -isnot [string] -or
            $WorkloadDescriptor.Channel -cne 'Standard'
        ) {
            return $false
        }

        foreach ($name in @('CandidateCommitSha', 'CandidateTreeSha')) {
            $value = $WorkloadDescriptor.$name
            if (
                $value -isnot [string] -or
                $value -cnotmatch '^[a-f0-9]{40}$' -or
                $value -cmatch '^0{40}$'
            ) {
                return $false
            }
        }
        foreach ($name in @(
            'CandidateZipSha256',
            'CandidateContentManifestBindingToken',
            'CandidateSbomSha256',
            'SourceDescriptorBindingToken',
            'SourceUriBindingToken',
            'StagingRootPathBindingToken',
            'DestinationPathBindingToken',
            'WorkloadBindingToken'
        )) {
            $value = $WorkloadDescriptor.$name
            if (
                $value -isnot [string] -or
                $value -cnotmatch '^[a-f0-9]{64}$' -or
                $value -cmatch '^0{64}$'
            ) {
                return $false
            }
        }
        if (
            (($WorkloadDescriptor.CandidateZipLengthBytes -isnot [int]) -and
                ($WorkloadDescriptor.CandidateZipLengthBytes -isnot [long])) -or
            [long]$WorkloadDescriptor.CandidateZipLengthBytes -lt 1 -or
            [long]$WorkloadDescriptor.CandidateZipLengthBytes -gt
                $script:CddsiD027CandidateZipMaximumBytes -or
            (($WorkloadDescriptor.CandidateSbomLengthBytes -isnot [int]) -and
                ($WorkloadDescriptor.CandidateSbomLengthBytes -isnot [long])) -or
            [long]$WorkloadDescriptor.CandidateSbomLengthBytes -lt 1 -or
            [long]$WorkloadDescriptor.CandidateSbomLengthBytes -gt
                $script:CddsiD027CandidateSbomMaximumBytes -or
            $WorkloadDescriptor.StagingRootPathBindingToken -ceq
                $WorkloadDescriptor.DestinationPathBindingToken
        ) {
            return $false
        }

        $sourceDescriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        if (
            -not (Test-CddsiD027ClaudeDesktopSourceDescriptor `
                -Descriptor $sourceDescriptor) -or
            $WorkloadDescriptor.SourceDescriptorBindingToken -cne
                $sourceDescriptor.MetadataBindingToken -or
            $WorkloadDescriptor.SourceUriBindingToken -cne
                $sourceDescriptor.SourceUriBindingToken -or
            $WorkloadDescriptor.WorkloadBindingToken -cne
                (Get-CddsiD027ClaudeAcquisitionWorkloadBindingToken `
                    -WorkloadDescriptor $WorkloadDescriptor)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-CddsiD027ClaudeSnapshotWorkloadBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$WorkloadDescriptor
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeSnapshotWorkloadFieldNames |
            Where-Object { $_ -cne 'WorkloadBindingToken' }
    )
    $validNames = (
        (Test-CddsiExactPropertySet `
            -InputObject $WorkloadDescriptor `
            -Expected $withoutBinding) -or
        (Test-CddsiExactPropertySet `
            -InputObject $WorkloadDescriptor `
            -Expected $script:CddsiD027ClaudeSnapshotWorkloadFieldNames)
    )
    if (-not $validNames) {
        throw 'D-027 Claude snapshot workload did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    $canonical.Add($script:CddsiD027ClaudeSnapshotWorkloadBindingDomain)
    foreach ($name in $withoutBinding) {
        $value = $WorkloadDescriptor.$name
        $text = if ($value -is [string]) {
            $value
        }
        elseif ($value -is [int] -or $value -is [long]) {
            [Convert]::ToString(
                [long]$value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        else {
            throw 'D-027 Claude snapshot workload contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text)
        )
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Test-CddsiD027ClaudeSnapshotWorkloadDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$WorkloadDescriptor
    )

    try {
        if (
            $null -eq $WorkloadDescriptor -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $WorkloadDescriptor `
                -Expected $script:CddsiD027ClaudeSnapshotWorkloadFieldNames)
        ) {
            return $false
        }

        $runId = [guid]::Empty
        if (
            -not (Test-CddsiSchemaVersionOne -Value $WorkloadDescriptor.SchemaVersion) -or
            $WorkloadDescriptor.ContractVersion -isnot [string] -or
            $WorkloadDescriptor.ContractVersion -cne
                'cddsi-d027-claude-machine-wide-snapshot-workload-v1' -or
            $WorkloadDescriptor.WorkloadKind -isnot [string] -or
            $WorkloadDescriptor.WorkloadKind -cne 'ClaudeDesktopMachineWide' -or
            $WorkloadDescriptor.RunId -isnot [string] -or
            -not [guid]::TryParse($WorkloadDescriptor.RunId, [ref]$runId) -or
            $runId -eq [guid]::Empty -or
            $WorkloadDescriptor.RunId -cne $runId.ToString('D') -or
            $WorkloadDescriptor.Stage -isnot [string] -or
            $WorkloadDescriptor.Stage -cne 'VmAcceptance' -or
            $WorkloadDescriptor.EnvironmentTier -isnot [string] -or
            $WorkloadDescriptor.EnvironmentTier -cne 'VmAcceptance' -or
            $WorkloadDescriptor.ArtifactProfile -isnot [string] -or
            $WorkloadDescriptor.ArtifactProfile -cne 'VmAcceptance' -or
            $WorkloadDescriptor.Operation -isnot [string] -or
            $WorkloadDescriptor.Operation -cne 'ProvisionClaudeDesktopMachineWide'
        ) {
            return $false
        }

        foreach ($name in @('CandidateCommitSha', 'CandidateTreeSha')) {
            $value = $WorkloadDescriptor.$name
            if (
                $value -isnot [string] -or
                $value -cnotmatch '^[a-f0-9]{40}$' -or
                $value -cmatch '^0{40}$'
            ) {
                return $false
            }
        }
        foreach ($name in @(
            'CandidateZipSha256',
            'CandidateContentManifestBindingToken',
            'CandidateSbomSha256',
            'CredentialHelperSourceTreeSha256',
            'CredentialHelperSourceManifestSha256',
            'CredentialHelperPeSha256',
            'CredentialHelperBuildDescriptorBindingToken',
            'CredentialHelperSignatureEvidenceBindingToken',
            'ClaudeMsixSha256',
            'ClaudeMsixContentBindingToken',
            'ClaudeDownloadReceiptBindingToken',
            'ClaudeHeldFileIdentityToken',
            'ClaudeManifestBindingToken',
            'ClaudePackageIdentityBindingToken',
            'ClaudeSignatureEvidenceBindingToken',
            'WorkloadBindingToken'
        )) {
            $value = $WorkloadDescriptor.$name
            if (
                $value -isnot [string] -or
                $value -cnotmatch '^[a-f0-9]{64}$' -or
                $value -cmatch '^0{64}$'
            ) {
                return $false
            }
        }

        $lengthBounds = [ordered]@{
            CandidateZipLengthBytes = $script:CddsiD027CandidateZipMaximumBytes
            CandidateSbomLengthBytes = $script:CddsiD027CandidateSbomMaximumBytes
            CredentialHelperPeLengthBytes =
                $script:CddsiD027CredentialHelperPeMaximumBytes
            ClaudeMsixLengthBytes =
                $script:CddsiD027ClaudeSnapshotMsixMaximumBytes
        }
        foreach ($name in $lengthBounds.Keys) {
            $value = $WorkloadDescriptor.$name
            if (
                (($value -isnot [int]) -and ($value -isnot [long])) -or
                [long]$value -lt 1 -or
                [long]$value -gt [long]$lengthBounds[$name]
            ) {
                return $false
            }
        }

        $expectedContentBindingToken = Get-CddsiD027ClaudeContentBindingToken `
            -ArtifactSha256 $WorkloadDescriptor.ClaudeMsixSha256 `
            -ArtifactSizeBytes ([long]$WorkloadDescriptor.ClaudeMsixLengthBytes)
        if (
            $WorkloadDescriptor.ClaudeMsixContentBindingToken -cne
                $expectedContentBindingToken -or
            $WorkloadDescriptor.WorkloadBindingToken -cne
                (Get-CddsiD027ClaudeSnapshotWorkloadBindingToken `
                    -WorkloadDescriptor $WorkloadDescriptor)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
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

$script:CddsiD027ExternalSnapshotReceiptCommonProof =
    [Func[object, string, string, object, string, object, bool]]{
    param(
        $Receipt,
        $ExpectedRunId,
        $ExpectedExecutionArtifactSha256,
        $PlatformObservation,
        $ValidationTimeUtc,
        $AuthorityPolicy
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
            $Receipt.Operation -cnotin @(
                'InstallGitForWindows',
                'AcquireClaudeDesktopMsix',
                'ProvisionClaudeDesktopMachineWide'
            )
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

    try {
        $expectedWorkloadBindingToken =
            Get-CddsiD027GitSnapshotWorkloadBindingToken `
                -RunId $ExpectedRunId `
                -ExecutionArtifactSha256 $ExpectedExecutionArtifactSha256
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Receipt `
                -Expected $script:CddsiD027ExternalSnapshotReceiptFieldNames) -or
            $Receipt.Operation -isnot [string] -or
            $Receipt.Operation -cne 'InstallGitForWindows' -or
            $Receipt.WorkloadBindingToken -isnot [string] -or
            $Receipt.WorkloadBindingToken -cne $expectedWorkloadBindingToken
        ) {
            return $false
        }
        return $script:CddsiD027ExternalSnapshotReceiptCommonProof.Invoke(
            $Receipt,
            $ExpectedRunId,
            $ExpectedExecutionArtifactSha256,
            $PlatformObservation,
            $ValidationTimeUtc,
            $AuthorityPolicy
        )
    }
    catch {
        return $false
    }
}

function Test-CddsiD027ClaudeAcquisitionExternalSnapshotReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)]$WorkloadDescriptor,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)]$PlatformObservation,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)]$AuthorityPolicy
    )

    try {
        if (-not (Test-CddsiD027ClaudeAcquisitionWorkloadDescriptor `
            -WorkloadDescriptor $WorkloadDescriptor)) {
            return $false
        }
        $parsedExpectedRunId = [guid]::Empty
        if (
            -not [guid]::TryParse($ExpectedRunId, [ref]$parsedExpectedRunId) -or
            $parsedExpectedRunId -eq [guid]::Empty -or
            $ExpectedRunId -cne $parsedExpectedRunId.ToString('D') -or
            $WorkloadDescriptor.RunId -cne $ExpectedRunId -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $Receipt `
                -Expected $script:CddsiD027ExternalSnapshotReceiptFieldNames) -or
            $Receipt.Operation -isnot [string] -or
            $Receipt.Operation -cne 'AcquireClaudeDesktopMsix' -or
            $Receipt.WorkloadBindingToken -isnot [string] -or
            $Receipt.WorkloadBindingToken -cne
                $WorkloadDescriptor.WorkloadBindingToken
        ) {
            return $false
        }
        return $script:CddsiD027ExternalSnapshotReceiptCommonProof.Invoke(
            $Receipt,
            $ExpectedRunId,
            $WorkloadDescriptor.CandidateZipSha256,
            $PlatformObservation,
            $ValidationTimeUtc,
            $AuthorityPolicy
        )
    }
    catch {
        return $false
    }
}

function Test-CddsiD027ClaudeExternalSnapshotReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt,
        [Parameter(Mandatory = $true)]$WorkloadDescriptor,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)]$PlatformObservation,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)]$AuthorityPolicy
    )

    try {
        if (-not (Test-CddsiD027ClaudeSnapshotWorkloadDescriptor `
            -WorkloadDescriptor $WorkloadDescriptor)) {
            return $false
        }
        $parsedExpectedRunId = [guid]::Empty
        if (
            -not [guid]::TryParse($ExpectedRunId, [ref]$parsedExpectedRunId) -or
            $parsedExpectedRunId -eq [guid]::Empty -or
            $ExpectedRunId -cne $parsedExpectedRunId.ToString('D') -or
            $WorkloadDescriptor.RunId -cne $ExpectedRunId -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $Receipt `
                -Expected $script:CddsiD027ExternalSnapshotReceiptFieldNames) -or
            $Receipt.Operation -isnot [string] -or
            $Receipt.Operation -cne 'ProvisionClaudeDesktopMachineWide' -or
            $Receipt.WorkloadBindingToken -isnot [string] -or
            $Receipt.WorkloadBindingToken -cne
                $WorkloadDescriptor.WorkloadBindingToken
        ) {
            return $false
        }
        return $script:CddsiD027ExternalSnapshotReceiptCommonProof.Invoke(
            $Receipt,
            $ExpectedRunId,
            $WorkloadDescriptor.CandidateZipSha256,
            $PlatformObservation,
            $ValidationTimeUtc,
            $AuthorityPolicy
        )
    }
    catch {
        return $false
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

function Enable-CddsiD027ClaudeAcquisitionLiveSessionAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$ReceiptPath,
        [Parameter(Mandatory = $true)][string]$ExpectedReceiptSha256,
        [Parameter(Mandatory = $true)]$WorkloadDescriptor
    )

    $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization = $null
    try {
        Assert-CddsiD027VmAcceptanceLiveBootstrapContext `
            -ExecutionContext $Context | Out-Null
        $contextTempPath =
            [System.IO.Path]::GetFullPath($Context.Paths.Temp).
                TrimEnd('\')
        if (
            -not (Test-CddsiD027ClaudeAcquisitionWorkloadDescriptor `
                -WorkloadDescriptor $WorkloadDescriptor) -or
            $Context.Stage -isnot [string] -or
            $Context.Stage -cne 'VmAcceptance' -or
            $Context.EnvironmentTier -isnot [string] -or
            $Context.EnvironmentTier -cne 'VmAcceptance' -or
            $Context.RunId -isnot [string] -or
            $WorkloadDescriptor.RunId -cne $Context.RunId -or
            $contextTempPath.Length -gt 240 -or
            $WorkloadDescriptor.StagingRootPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $contextTempPath)
        ) {
            throw 'The D-027 Claude acquisition bootstrap context was invalid.'
        }
        $readResult = Read-CddsiD027ExternalSnapshotReceipt `
            -ExecutionContext $Context `
            -ReceiptPath $ReceiptPath `
            -ExpectedReceiptSha256 $ExpectedReceiptSha256
        $platformObservation =
            Get-CddsiD027SnapshotPlatformObservation -ExecutionContext $Context
        $validationTimeUtc = [DateTimeOffset]::UtcNow.ToString(
            'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture
        )
        $authorityPolicy =
            Get-CddsiD027SnapshotAuthorityPolicy -ExecutionContext $Context
        if (-not (Test-CddsiD027ClaudeAcquisitionExternalSnapshotReceipt `
            -Receipt $readResult.Receipt `
            -WorkloadDescriptor $WorkloadDescriptor `
            -ExpectedRunId $Context.RunId `
            -PlatformObservation $platformObservation `
            -ValidationTimeUtc $validationTimeUtc `
            -AuthorityPolicy $authorityPolicy)) {
            throw 'The D-027 snapshot receipt did not authorize this exact Claude acquisition workload.'
        }

        $receipt = $readResult.Receipt
        $workloadValues = [ordered]@{}
        foreach ($name in $script:CddsiD027ClaudeAcquisitionWorkloadFieldNames) {
            $workloadValues[$name] = $WorkloadDescriptor.$name
        }
        $workloadSnapshot = [pscustomobject]$workloadValues
        $authorization = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-acquisition-live-signed-authorization-v1'
            Receipt = $receipt
            ReceiptSha256 = $readResult.ReceiptSha256
            ReceiptLengthBytes = [long]$readResult.ReceiptLengthBytes
            WorkloadDescriptor = $workloadSnapshot
            AuthorizedAtUtc = $validationTimeUtc
            InitialPlatformObservation = $platformObservation
        }
        $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization =
            $authorization
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
            SourceDescriptorBindingToken =
                $workloadSnapshot.SourceDescriptorBindingToken
            StagingRootPathBindingToken =
                $workloadSnapshot.StagingRootPathBindingToken
            DestinationPathBindingToken =
                $workloadSnapshot.DestinationPathBindingToken
            ExpiresAtUtc = $receipt.ExpiresAtUtc
        }
        return New-CddsiOperationResult `
            -Operation 'EnableD027ClaudeAcquisitionLiveSessionAuthorization' `
            -Status 'SUCCEEDED' `
            -Mode Live `
            -MessageSafe 'An exact externally signed clean-snapshot receipt authorized only this candidate-bound Claude MSIX acquisition target.' `
            -Data $safeData
    }
    catch {
        $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization = $null
        return New-CddsiOperationResult `
            -Operation 'EnableD027ClaudeAcquisitionLiveSessionAuthorization' `
            -Status 'ACTION_REQUIRED' `
            -Mode Live `
            -ErrorCode 'D027_CLAUDE_ACQUISITION_SNAPSHOT_AUTHORIZATION_INVALID' `
            -MessageSafe 'A fresh exact VM-external clean-snapshot receipt signed by the configured pinned authority is required for this candidate-bound Claude MSIX acquisition target.'
    }
}

function Clear-CddsiD027ClaudeAcquisitionLiveSessionAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization = $null
    try {
        Assert-CddsiD027VmAcceptanceLiveBootstrapContext `
            -ExecutionContext $Context | Out-Null
    }
    catch {
        return New-CddsiOperationResult `
            -Operation 'ClearD027ClaudeAcquisitionLiveSessionAuthorization' `
            -Status 'ACTION_REQUIRED' `
            -Mode Live `
            -ErrorCode 'D027_CLAUDE_ACQUISITION_CONTEXT_INVALID' `
            -MessageSafe 'The process-scoped D-027 Claude acquisition authorization was cleared, but the current VmAcceptance context was invalid.'
    }
    return New-CddsiOperationResult `
        -Operation 'ClearD027ClaudeAcquisitionLiveSessionAuthorization' `
        -Status 'SUCCEEDED' `
        -Mode Live `
        -MessageSafe 'The process-scoped D-027 Claude acquisition authorization was cleared.'
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

function Assert-CddsiD027VmAcceptanceLiveBootstrapContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    try {
        return Assert-CddsiD027GitLiveBootstrapContext `
            -ExecutionContext $Context
    }
    catch {
        throw 'D-027 VmAcceptance Live context requires Windows 11 x64, 64-bit Windows PowerShell 5.1, Live mode and an explicit local product temp path.'
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

function Assert-CddsiD027ClaudeAcquisitionLiveContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)]$WorkloadDescriptor,
        [Parameter(Mandatory = $true)][string]$StagingRootPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath
    )

    try {
        Assert-CddsiD027VmAcceptanceLiveBootstrapContext `
            -ExecutionContext $Context | Out-Null
        $authorization =
            $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization
        $contextTempPath = $null
        if (
            $null -ne $Context.Paths -and
            $Context.Paths.Temp -is [string] -and
            -not [string]::IsNullOrWhiteSpace($Context.Paths.Temp)
        ) {
            $contextTempPath =
                [System.IO.Path]::GetFullPath($Context.Paths.Temp).
                    TrimEnd('\')
        }
        if (
            $null -eq $authorization -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $authorization `
                -Expected `
                    $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorizationFieldNames) -or
            -not (Test-CddsiSchemaVersionOne `
                -Value $authorization.SchemaVersion) -or
            $authorization.ContractVersion -isnot [string] -or
            $authorization.ContractVersion -cne
                'cddsi-d027-claude-acquisition-live-signed-authorization-v1' -or
            $null -eq $authorization.Receipt -or
            -not (Test-CddsiD027ClaudeAcquisitionWorkloadDescriptor `
                -WorkloadDescriptor $authorization.WorkloadDescriptor) -or
            -not (Test-CddsiD027ClaudeAcquisitionWorkloadDescriptor `
                -WorkloadDescriptor $WorkloadDescriptor) -or
            -not (Test-CddsiD027ClaudeDownloadDestinationPath `
                -StagingRootPath $StagingRootPath `
                -DestinationPath $DestinationPath) -or
            $StagingRootPath.Length -gt 240 -or
            $DestinationPath.Length -gt 240 -or
            $contextTempPath -isnot [string] -or
            -not [string]::Equals(
                $contextTempPath,
                $StagingRootPath,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            $WorkloadDescriptor.StagingRootPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $StagingRootPath) -or
            $WorkloadDescriptor.DestinationPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $DestinationPath) -or
            $authorization.WorkloadDescriptor.WorkloadBindingToken -cne
                $WorkloadDescriptor.WorkloadBindingToken -or
            $Context.RunId -isnot [string] -or
            $Context.RunId -cne $WorkloadDescriptor.RunId -or
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
            $authorization.AuthorizedAtUtc -isnot [string] -or
            $authorization.AuthorizedAtUtc -notmatch
                '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
            -not (Test-CddsiUtcTimestampValue `
                -Value $authorization.AuthorizedAtUtc) -or
            $null -eq $authorization.InitialPlatformObservation
        ) {
            throw 'Claude acquisition authorization state was invalid.'
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
        if (-not (
            Test-CddsiD027ClaudeAcquisitionExternalSnapshotReceipt `
                -Receipt $authorization.Receipt `
                -WorkloadDescriptor $authorization.WorkloadDescriptor `
                -ExpectedRunId $Context.RunId `
                -PlatformObservation $platformObservation `
                -ValidationTimeUtc $validationTimeUtc `
                -AuthorityPolicy $authorityPolicy
        )) {
            throw 'Signed authorization receipt was invalid, stale or no longer platform-bound.'
        }
    }
    catch {
        $script:CddsiD027ClaudeAcquisitionLiveSessionAuthorization = $null
        throw 'D-027 Claude acquisition Live requires a fresh process-scoped authorization from an exact VM-external clean-snapshot receipt signed by the pinned authority and bound only to this candidate, official source and staging target.'
    }
    return $true
}
