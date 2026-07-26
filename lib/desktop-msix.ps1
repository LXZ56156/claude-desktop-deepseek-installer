# desktop-msix.ps1 - Claude Desktop MSIX lifecycle contracts.
# Signature verification is mandatory and has no bypass parameter.

$script:CddsiD027ClaudeStandardX64SourceUri =
    'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
$script:CddsiD027ClaudeMsixMinimumBytes = [long]64
$script:CddsiD027ClaudeTransportPathPattern =
    '^/releases/win32/x64/[0-9]+\.[0-9]+\.[0-9]+/Claude-[a-f0-9]{40}\.msix$'
$script:CddsiD027ClaudeMsixMaximumBytes = [long](1GB)
$script:CddsiD027ClaudeManifestMaximumBytes = [long](1MB)
$script:CddsiD027ClaudeSignerCertificateMaximumBytes = 12288
$script:CddsiD027ClaudeDownloadBufferBytes = 65536
$script:CddsiD027ClaudeFileShareReadConstructionCapability =
    New-Object System.Object
$script:CddsiD027ClaudeManifestNamespace =
    'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
$script:CddsiD027ClaudeDownloadReceiptFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'ArtifactState',
    'RunId',
    'ArtifactProfile',
    'ArtifactType',
    'DescriptorId',
    'SourceDescriptorBindingToken',
    'RequestUri',
    'RequestUriBindingToken',
    'SanitizedFinalUri',
    'SanitizedRedirectUris',
    'RedirectChainBindingToken',
    'RedirectCount',
    'StagingRootPathBindingToken',
    'DestinationPathBindingToken',
    'FileIdentityToken',
    'ArtifactSha256',
    'ArtifactSizeBytes',
    'ContentBindingToken',
    'ObservedAtUtc',
    'ReceiptBindingToken'
)
$script:CddsiD027ClaudeDownloadTransportFactFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'InitialRequestMethod',
    'InitialRequestUri',
    'InitialStatusCode',
    'RedirectCount',
    'RedirectLocationHeaderCount',
    'RedirectTargetTransportUri',
    'RedirectContentTypeHeaderCount',
    'RedirectContentEncodingCount',
    'RedirectTransferEncodingCount',
    'RedirectContentLengthHeaderCount',
    'RedirectContentLengthBytes',
    'FinalRequestMethod',
    'FinalRequestTransportUri',
    'FinalStatusCode',
    'FinalLocationHeaderCount',
    'FinalContentTypeHeaderCount',
    'FinalContentTypeMediaType',
    'FinalContentTypeParameterCount',
    'FinalContentEncodingCount',
    'FinalTransferEncodingCount',
    'FinalContentLengthHeaderCount',
    'FinalContentLengthBytes'
)
$script:CddsiD027ClaudeDownloadTransportObservationFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'TransportState',
    'ArtifactProfile',
    'ArtifactType',
    'DescriptorId',
    'SourceDescriptorBindingToken',
    'RequestUriBindingToken',
    'RequestMethod',
    'InitialStatusCode',
    'SanitizedFinalUri',
    'SanitizedFinalUriBindingToken',
    'RedirectCount',
    'FinalStatusCode',
    'ContentTypeMediaType',
    'ContentEncodingCount',
    'TransferEncodingCount',
    'DeclaredContentLengthBytes',
    'HeaderObservationBindingToken'
)
$script:CddsiD027ClaudeHeldArtifactObservationFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'ObservationMethod',
    'FinalPathBindingToken',
    'FileSystemName',
    'NumberOfLinks',
    'IsDirectory',
    'IsReparsePoint',
    'VolumeSerialNumberHex',
    'FileIndexHex',
    'FileIdentityToken',
    'ArtifactSha256',
    'ArtifactSizeBytes',
    'ObservedAtUtc'
)
$script:CddsiD027ClaudeManifestIdentityFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'PackageName',
    'Publisher',
    'PublisherTextSha256',
    'PublisherParsedX500RawDataSha256',
    'PackageVersion',
    'Architecture',
    'ResourceId',
    'PackageIdentityBindingToken',
    'ManifestSha256',
    'ManifestLengthBytes',
    'ManifestBindingToken'
)
$script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'EvidenceKind',
    'VerificationMethod',
    'SignerExtractionMethod',
    'StateLifecycle',
    'RunId',
    'ArtifactProfile',
    'ArtifactType',
    'FinalPathBindingToken',
    'DownloadReceiptBindingToken',
    'FileIdentityToken',
    'ArtifactSha256',
    'ArtifactSizeBytes',
    'ContentBindingToken',
    'ManifestBindingToken',
    'PackageIdentityBindingToken',
    'WinVerifyTrustTrusted',
    'WinVerifyTrustStatus',
    'WinVerifyTrustNativeStatusHex',
    'WinVerifyTrustRevocationMode',
    'SignerCertificateDerBase64',
    'SignerCertificateDerSha256',
    'SignerCertificateDerLengthBytes',
    'SignerCertificateThumbprintSha1',
    'SignerSubject',
    'SignerSubjectTextSha256',
    'SignerSubjectNameRawDataSha256',
    'ObservedAtUtc',
    'EvidenceBindingToken'
)
$script:CddsiD027ClaudeMsixSameStateNativeObservationFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'ObservationMethod',
    'VerificationMethod',
    'SignerExtractionMethod',
    'StateLifecycle',
    'FinalPathBindingToken',
    'CallerFileHandleSupplied',
    'FinalPathStableAcrossVerification',
    'FileFactsStableAcrossVerification',
    'ProviderOpenedFile',
    'PrimarySignerCount',
    'SecondarySignatureCount',
    'WinVerifyTrustTrusted',
    'WinVerifyTrustStatus',
    'WinVerifyTrustNativeStatusHex',
    'WinVerifyTrustRevocationMode',
    'StateCloseCompleted',
    'StateCloseNativeStatusHex',
    'StreamPositionRestored',
    'PrimarySignerCertificateDerBytes',
    'PrimarySignerCertificateDerLengthBytes'
)

if (
    $null -eq (Get-Variable `
        -Name CddsiD027ClaudeMsixSameStateSignerNativeType `
        -Scope Script `
        -ErrorAction SilentlyContinue)
) {
    $script:CddsiD027ClaudeMsixSameStateSignerNativeType = $null
}
if (
    $null -eq (Get-Variable `
        -Name CddsiD027ClaudeMsixSameStateSignerNativeAssemblyFullName `
        -Scope Script `
        -ErrorAction SilentlyContinue)
) {
    $script:CddsiD027ClaudeMsixSameStateSignerNativeAssemblyFullName = $null
}

$script:CddsiD027ClaudeMsixSameStateSignerNativeTypeDefinition = @'
using System;
using System.Globalization;
using System.IO;
using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using Microsoft.Win32.SafeHandles;

namespace Cddsi.D027 {
    public static class ClaudeMsixSameStateWinVerifyTrustV1 {
        private const uint WTD_UI_NONE = 2;
        private const uint WTD_REVOKE_NONE = 0;
        private const uint WTD_CHOICE_FILE = 1;
        private const uint WTD_STATEACTION_VERIFY = 1;
        private const uint WTD_STATEACTION_CLOSE = 2;
        private const uint WTD_REVOCATION_CHECK_NONE = 0x10;
        private const uint WTD_CACHE_ONLY_URL_RETRIEVAL = 0x1000;
        private const uint WTD_DISABLE_MD2_MD4 = 0x2000;
        private const uint WTD_UICONTEXT_INSTALL = 1;
        private const uint WSS_GET_SECONDARY_SIG_COUNT = 0x2;
        private const int MinimumCertificateBytes = 256;
        private const int MaximumCertificateBytes = 12288;
        private const long MaximumArtifactBytes = 1073741824;
        private const int Windows11MinimumBuild = 22000;
        private const byte VER_NT_WORKSTATION = 1;
        private const ushort IMAGE_FILE_MACHINE_UNKNOWN = 0;
        private const ushort IMAGE_FILE_MACHINE_AMD64 = 0x8664;
        private const uint FILE_ATTRIBUTE_DIRECTORY = 0x10;
        private const uint FILE_ATTRIBUTE_REPARSE_POINT = 0x400;

        private static readonly Guid GenericVerifyV2 =
            new Guid("00AAC56B-CD44-11d0-8CC2-00C04FC295EE");
        private static readonly IntPtr InvalidWindowHandle = new IntPtr(-1);

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
        private struct RTL_OSVERSIONINFOEXW {
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

        [StructLayout(LayoutKind.Sequential)]
        private struct WINTRUST_FILE_INFO {
            internal uint cbStruct;
            internal IntPtr pcwszFilePath;
            internal IntPtr hFile;
            internal IntPtr pgKnownSubject;
        }

        [StructLayout(LayoutKind.Sequential)]
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
            internal IntPtr pSignatureSettings;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct WINTRUST_SIGNATURE_SETTINGS {
            internal uint cbStruct;
            internal uint dwIndex;
            internal uint dwFlags;
            internal uint cSecondarySigs;
            internal uint dwVerifiedSigIndex;
            internal IntPtr pCryptoPolicy;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct BY_HANDLE_FILE_INFORMATION {
            internal uint FileAttributes;
            internal FILETIME_NATIVE CreationTime;
            internal FILETIME_NATIVE LastAccessTime;
            internal FILETIME_NATIVE LastWriteTime;
            internal uint VolumeSerialNumber;
            internal uint FileSizeHigh;
            internal uint FileSizeLow;
            internal uint NumberOfLinks;
            internal uint FileIndexHigh;
            internal uint FileIndexLow;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CRYPT_PROVIDER_DATA_SIGNERS_PREFIX {
            internal uint cbStruct;
            internal IntPtr pWintrustData;
            internal int fOpenedFile;
            internal IntPtr hWndParent;
            internal IntPtr pgActionID;
            internal IntPtr hProv;
            internal uint dwError;
            internal uint dwRegSecuritySettings;
            internal uint dwRegPolicySettings;
            internal IntPtr psPfns;
            internal uint cdwTrustStepErrors;
            internal IntPtr padwTrustStepErrors;
            internal uint chStores;
            internal IntPtr pahStores;
            internal uint dwEncoding;
            internal IntPtr hMsg;
            internal uint csSigners;
            internal IntPtr pasSigners;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct FILETIME_NATIVE {
            internal uint dwLowDateTime;
            internal uint dwHighDateTime;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CRYPT_PROVIDER_SGNR_HEAD {
            internal uint cbStruct;
            internal FILETIME_NATIVE sftVerifyAsOf;
            internal uint csCertChain;
            internal IntPtr pasCertChain;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CRYPT_PROVIDER_CERT_HEAD {
            internal uint cbStruct;
            internal IntPtr pCert;
        }

        [StructLayout(LayoutKind.Sequential)]
        private struct CERT_CONTEXT {
            internal uint dwCertEncodingType;
            internal IntPtr pbCertEncoded;
            internal uint cbCertEncoded;
            internal IntPtr pCertInfo;
            internal IntPtr hCertStore;
        }

        public sealed class AbiSizes {
            public int OsVersionInfoEx;
            public int WinTrustFileInfo;
            public int WinTrustData;
            public int WinTrustSignatureSettings;
            public int ByHandleFileInformation;
            public int ProviderDataSignersPrefix;
            public int ProviderSignersOffset;
            public int ProviderSignerHead;
            public int ProviderCertHead;
            public int CertContext;
        }

        public sealed class Observation {
            public bool Trusted;
            public string Status;
            public string NativeStatusHex;
            public bool CallerFileHandleSupplied;
            public bool FinalPathStableAcrossVerification;
            public bool FileFactsStableAcrossVerification;
            public Nullable<bool> ProviderOpenedFile;
            public Nullable<uint> PrimarySignerCount;
            public Nullable<uint> SecondarySignatureCount;
            public bool StateCloseCompleted;
            public string StateCloseNativeStatusHex;
            public bool StreamPositionRestored;
            public string FinalPathBindingToken;
            public byte[] PrimarySignerCertificateDerBytes;
            public Nullable<uint> PrimarySignerCertificateDerLengthBytes;
        }

        public sealed class HeldFileIdentityObservation {
            public bool Eligible;
            public string Status;
            public string FinalPathBindingToken;
            public string FileSystemName;
            public uint NumberOfLinks;
            public bool IsDirectory;
            public bool IsReparsePoint;
            public string VolumeSerialNumberHex;
            public string FileIndexHex;
            public long ArtifactSizeBytes;
            public string FileFactsBindingToken;
        }

        [DllImport("ntdll.dll", CharSet = CharSet.Unicode, ExactSpelling = true)]
        private static extern int RtlGetVersion(
            ref RTL_OSVERSIONINFOEXW versionInformation);

        [DllImport("kernel32.dll", ExactSpelling = true)]
        private static extern IntPtr GetCurrentProcess();

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool IsWow64Process2(
            IntPtr processHandle,
            out ushort processMachine,
            out ushort nativeMachine);

        [DllImport(
            "kernel32.dll",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true)]
        private static extern uint GetFinalPathNameByHandleW(
            IntPtr fileHandle,
            StringBuilder path,
            uint capacity,
            uint flags);

        [DllImport(
            "kernel32.dll",
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetFileInformationByHandle(
            IntPtr fileHandle,
            out BY_HANDLE_FILE_INFORMATION information);

        [DllImport(
            "kernel32.dll",
            CharSet = CharSet.Unicode,
            ExactSpelling = true,
            SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GetVolumeInformationByHandleW(
            IntPtr fileHandle,
            StringBuilder volumeNameBuffer,
            uint volumeNameSize,
            out uint volumeSerialNumber,
            out uint maximumComponentLength,
            out uint fileSystemFlags,
            StringBuilder fileSystemNameBuffer,
            uint fileSystemNameSize);

        [DllImport(
            "wintrust.dll",
            EntryPoint = "WinVerifyTrustEx",
            ExactSpelling = true)]
        private static extern int WinVerifyTrustEx(
            IntPtr windowHandle,
            ref Guid actionId,
            ref WINTRUST_DATA trustData);

        [DllImport(
            "wintrust.dll",
            EntryPoint = "WTHelperProvDataFromStateData",
            ExactSpelling = true)]
        private static extern IntPtr WTHelperProvDataFromStateData(
            IntPtr stateData);

        [DllImport(
            "wintrust.dll",
            EntryPoint = "WTHelperGetProvSignerFromChain",
            ExactSpelling = true)]
        private static extern IntPtr WTHelperGetProvSignerFromChain(
            IntPtr providerData,
            uint signerIndex,
            [MarshalAs(UnmanagedType.Bool)] bool counterSigner,
            uint counterSignerIndex);

        [DllImport(
            "wintrust.dll",
            EntryPoint = "WTHelperGetProvCertFromChain",
            ExactSpelling = true)]
        private static extern IntPtr WTHelperGetProvCertFromChain(
            IntPtr providerSigner,
            uint certificateIndex);

        public static AbiSizes GetAbiSizes() {
            AbiSizes result = new AbiSizes();
            result.OsVersionInfoEx =
                Marshal.SizeOf(typeof(RTL_OSVERSIONINFOEXW));
            result.WinTrustFileInfo =
                Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
            result.WinTrustData =
                Marshal.SizeOf(typeof(WINTRUST_DATA));
            result.WinTrustSignatureSettings =
                Marshal.SizeOf(typeof(WINTRUST_SIGNATURE_SETTINGS));
            result.ByHandleFileInformation =
                Marshal.SizeOf(typeof(BY_HANDLE_FILE_INFORMATION));
            result.ProviderDataSignersPrefix =
                Marshal.SizeOf(typeof(CRYPT_PROVIDER_DATA_SIGNERS_PREFIX));
            result.ProviderSignersOffset =
                Marshal.OffsetOf(
                    typeof(CRYPT_PROVIDER_DATA_SIGNERS_PREFIX),
                    "csSigners").ToInt32();
            result.ProviderSignerHead =
                Marshal.SizeOf(typeof(CRYPT_PROVIDER_SGNR_HEAD));
            result.ProviderCertHead =
                Marshal.SizeOf(typeof(CRYPT_PROVIDER_CERT_HEAD));
            result.CertContext =
                Marshal.SizeOf(typeof(CERT_CONTEXT));
            return result;
        }

        public static HeldFileIdentityObservation ObserveHeldFileIdentity(
            FileStream stream) {
            HeldFileIdentityObservation result =
                NewHeldFileIdentityObservation("InvalidInput");
            if (!IsWindows11X64()) {
                result.Status = "UnsupportedRuntime";
                return result;
            }
            if (stream == null) {
                return result;
            }
            try {
                if (!stream.CanRead || !stream.CanSeek || stream.CanWrite) {
                    return result;
                }
            }
            catch (ObjectDisposedException) {
                return result;
            }

            SafeFileHandle safeHandle = null;
            bool handleAddRef = false;
            try {
                safeHandle = stream.SafeFileHandle;
                if (safeHandle == null ||
                    safeHandle.IsInvalid ||
                    safeHandle.IsClosed) {
                    return result;
                }
                safeHandle.DangerousAddRef(ref handleAddRef);
                IntPtr rawHandle = safeHandle.DangerousGetHandle();
                if (rawHandle == IntPtr.Zero ||
                    rawHandle == new IntPtr(-1)) {
                    return result;
                }

                BY_HANDLE_FILE_INFORMATION facts =
                    GetHeldFileFacts(rawHandle);
                string finalPath =
                    NormalizeFinalPath(GetFinalPath(rawHandle));
                string fileSystemName;
                uint volumeSerialNumber;
                GetHeldVolumeInformation(
                    rawHandle,
                    out fileSystemName,
                    out volumeSerialNumber);
                if (volumeSerialNumber != facts.VolumeSerialNumber) {
                    result.Status = "VolumeIdentityMismatch";
                    return result;
                }

                long artifactSizeBytes =
                    ((long)facts.FileSizeHigh << 32) |
                    facts.FileSizeLow;
                bool isDirectory =
                    (facts.FileAttributes &
                        FILE_ATTRIBUTE_DIRECTORY) != 0;
                bool isReparsePoint =
                    (facts.FileAttributes &
                        FILE_ATTRIBUTE_REPARSE_POINT) != 0;
                string finalPathBindingToken =
                    GetPathBindingToken(finalPath);

                result.FinalPathBindingToken =
                    finalPathBindingToken;
                result.FileSystemName = fileSystemName;
                result.NumberOfLinks = facts.NumberOfLinks;
                result.IsDirectory = isDirectory;
                result.IsReparsePoint = isReparsePoint;
                result.VolumeSerialNumberHex =
                    facts.VolumeSerialNumber.ToString(
                        "X8",
                        CultureInfo.InvariantCulture);
                result.FileIndexHex =
                    facts.FileIndexHigh.ToString(
                        "X8",
                        CultureInfo.InvariantCulture) +
                    facts.FileIndexLow.ToString(
                        "X8",
                        CultureInfo.InvariantCulture);
                result.ArtifactSizeBytes = artifactSizeBytes;
                result.FileFactsBindingToken =
                    GetFileFactsBindingToken(
                        facts,
                        fileSystemName,
                        finalPathBindingToken);
                result.Eligible = (
                    IsEligibleHeldFile(facts) &&
                    String.Equals(
                        fileSystemName,
                        "NTFS",
                        StringComparison.Ordinal) &&
                    String.Equals(
                        Path.GetExtension(finalPath),
                        ".msix",
                        StringComparison.OrdinalIgnoreCase)
                );
                result.Status = result.Eligible
                    ? "Eligible"
                    : "HeldFileIneligible";
            }
            catch {
                result = NewHeldFileIdentityObservation(
                    "HeldFileUnavailable");
            }
            finally {
                if (handleAddRef && safeHandle != null) {
                    safeHandle.DangerousRelease();
                }
            }
            return result;
        }

        public static Observation Observe(FileStream stream) {
            Observation result = NewObservation("InvalidInput");
            if (!IsWindows11X64()) {
                result.Status = "UnsupportedRuntime";
                return result;
            }
            if (stream == null) {
                return result;
            }
            try {
                if (!stream.CanRead || !stream.CanSeek || stream.CanWrite) {
                    return result;
                }
            }
            catch (ObjectDisposedException) {
                return result;
            }

            SafeFileHandle safeHandle = null;
            bool handleAddRef = false;
            bool verifyReturned = false;
            bool originalPositionCaptured = false;
            bool beforeFileFactsCaptured = false;
            long originalPosition = 0;
            IntPtr pathPointer = IntPtr.Zero;
            IntPtr fileInfoPointer = IntPtr.Zero;
            IntPtr signatureSettingsPointer = IntPtr.Zero;
            BY_HANDLE_FILE_INFORMATION beforeFileFacts =
                new BY_HANDLE_FILE_INFORMATION();
            WINTRUST_DATA trustData = new WINTRUST_DATA();
            Guid actionId = GenericVerifyV2;

            try {
                safeHandle = stream.SafeFileHandle;
                if (safeHandle == null ||
                    safeHandle.IsInvalid ||
                    safeHandle.IsClosed) {
                    return result;
                }
                safeHandle.DangerousAddRef(ref handleAddRef);
                IntPtr rawHandle = safeHandle.DangerousGetHandle();
                if (rawHandle == IntPtr.Zero ||
                    rawHandle == new IntPtr(-1)) {
                    return result;
                }

                originalPosition = stream.Position;
                originalPositionCaptured = true;
                stream.Position = 0;

                beforeFileFacts = GetHeldFileFacts(rawHandle);
                beforeFileFactsCaptured = true;
                if (!IsEligibleHeldFile(beforeFileFacts)) {
                    result.Status = "HeldFileIneligible";
                    return result;
                }

                string finalPath = GetFinalPath(rawHandle);
                string normalizedFinalPath = NormalizeFinalPath(finalPath);
                if (!String.Equals(
                    Path.GetExtension(normalizedFinalPath),
                    ".msix",
                    StringComparison.OrdinalIgnoreCase)) {
                    return result;
                }
                result.FinalPathBindingToken =
                    GetPathBindingToken(normalizedFinalPath);

                pathPointer = Marshal.StringToCoTaskMemUni(finalPath);
                WINTRUST_FILE_INFO fileInfo = new WINTRUST_FILE_INFO();
                fileInfo.cbStruct =
                    (uint)Marshal.SizeOf(typeof(WINTRUST_FILE_INFO));
                fileInfo.pcwszFilePath = pathPointer;
                fileInfo.hFile = rawHandle;
                fileInfo.pgKnownSubject = IntPtr.Zero;
                fileInfoPointer =
                    Marshal.AllocHGlobal(
                        Marshal.SizeOf(typeof(WINTRUST_FILE_INFO)));
                Marshal.StructureToPtr(fileInfo, fileInfoPointer, false);

                WINTRUST_SIGNATURE_SETTINGS signatureSettings =
                    new WINTRUST_SIGNATURE_SETTINGS();
                signatureSettings.cbStruct =
                    (uint)Marshal.SizeOf(
                        typeof(WINTRUST_SIGNATURE_SETTINGS));
                signatureSettings.dwIndex = 0;
                signatureSettings.dwFlags =
                    WSS_GET_SECONDARY_SIG_COUNT;
                signatureSettings.cSecondarySigs =
                    UInt32.MaxValue;
                signatureSettings.dwVerifiedSigIndex =
                    UInt32.MaxValue;
                signatureSettings.pCryptoPolicy = IntPtr.Zero;
                signatureSettingsPointer =
                    Marshal.AllocHGlobal(
                        Marshal.SizeOf(
                            typeof(WINTRUST_SIGNATURE_SETTINGS)));
                Marshal.StructureToPtr(
                    signatureSettings,
                    signatureSettingsPointer,
                    false);

                trustData.cbStruct =
                    (uint)Marshal.SizeOf(typeof(WINTRUST_DATA));
                trustData.pPolicyCallbackData = IntPtr.Zero;
                trustData.pSIPClientData = IntPtr.Zero;
                trustData.dwUIChoice = WTD_UI_NONE;
                trustData.fdwRevocationChecks = WTD_REVOKE_NONE;
                trustData.dwUnionChoice = WTD_CHOICE_FILE;
                trustData.pFile = fileInfoPointer;
                trustData.dwStateAction = WTD_STATEACTION_VERIFY;
                trustData.hWVTStateData = IntPtr.Zero;
                trustData.pwszURLReference = IntPtr.Zero;
                trustData.dwProvFlags =
                    WTD_REVOCATION_CHECK_NONE |
                    WTD_CACHE_ONLY_URL_RETRIEVAL |
                    WTD_DISABLE_MD2_MD4;
                trustData.dwUIContext = WTD_UICONTEXT_INSTALL;
                trustData.pSignatureSettings =
                    signatureSettingsPointer;

                result.CallerFileHandleSupplied = true;
                int nativeStatus = WinVerifyTrustEx(
                    InvalidWindowHandle,
                    ref actionId,
                    ref trustData);
                verifyReturned = true;
                result.NativeStatusHex = ToNativeStatusHex(nativeStatus);
                if (nativeStatus != 0) {
                    result.Status = MapUntrustedStatus(nativeStatus);
                }
                else if (signatureSettingsPointer == IntPtr.Zero) {
                    result.Status = "SignatureSettingsUnavailable";
                }
                else {
                    signatureSettings =
                        (WINTRUST_SIGNATURE_SETTINGS)
                            Marshal.PtrToStructure(
                                signatureSettingsPointer,
                                typeof(WINTRUST_SIGNATURE_SETTINGS));
                    if (
                        signatureSettings.cbStruct !=
                            Marshal.SizeOf(
                                typeof(
                                    WINTRUST_SIGNATURE_SETTINGS)) ||
                        signatureSettings.dwIndex != 0 ||
                        signatureSettings.dwFlags !=
                            WSS_GET_SECONDARY_SIG_COUNT
                    ) {
                        result.Status =
                            "SignatureSettingsInvalid";
                    }
                    else if (
                        signatureSettings.cSecondarySigs ==
                            UInt32.MaxValue ||
                        signatureSettings.dwVerifiedSigIndex ==
                            UInt32.MaxValue
                    ) {
                        result.Status =
                            "SignatureSettingsUnobserved";
                    }
                    else if (
                        signatureSettings.cSecondarySigs != 0 ||
                        signatureSettings.dwVerifiedSigIndex != 0
                    ) {
                        result.SecondarySignatureCount =
                            signatureSettings.cSecondarySigs;
                        result.Status =
                            "AmbiguousEmbeddedSignatures";
                    }
                    else {
                        result.SecondarySignatureCount = 0;
                        if (
                            trustData.hWVTStateData == IntPtr.Zero
                        ) {
                            result.Status = "StateUnavailable";
                        }
                        else {
                            ExtractProviderPrimarySigner(
                                trustData.hWVTStateData,
                                result);
                        }
                    }
                }
            }
            catch (DllNotFoundException) {
                result.Status = "NativeUnavailable";
            }
            catch (EntryPointNotFoundException) {
                result.Status = "NativeUnavailable";
            }
            catch (BadImageFormatException) {
                result.Status = "NativeUnavailable";
            }
            catch (ObjectDisposedException) {
                result.Status = "InvalidInput";
            }
            catch (ArgumentException) {
                result.Status = verifyReturned
                    ? "ExtractionFailed"
                    : "ObservationFailed";
            }
            catch (IOException) {
                result.Status = verifyReturned
                    ? "ExtractionFailed"
                    : "ObservationFailed";
            }
            catch {
                result.Status = verifyReturned
                    ? "ExtractionFailed"
                    : "ObservationFailed";
            }
            finally {
                if (verifyReturned) {
                    try {
                        trustData.dwStateAction = WTD_STATEACTION_CLOSE;
                        int closeStatus = WinVerifyTrustEx(
                            InvalidWindowHandle,
                            ref actionId,
                            ref trustData);
                        result.StateCloseNativeStatusHex =
                            ToNativeStatusHex(closeStatus);
                        result.StateCloseCompleted = closeStatus == 0;
                        if (closeStatus != 0) {
                            result.Status = "StateCloseFailed";
                        }
                    }
                    catch {
                        result.StateCloseCompleted = false;
                        result.StateCloseNativeStatusHex = null;
                        result.Status = "StateCloseFailed";
                    }
                }

                if (verifyReturned && beforeFileFactsCaptured) {
                    try {
                        BY_HANDLE_FILE_INFORMATION afterFileFacts =
                            GetHeldFileFacts(
                                safeHandle.DangerousGetHandle());
                        result.FileFactsStableAcrossVerification =
                            SameHeldFileFacts(
                                beforeFileFacts,
                                afterFileFacts);
                        if (
                            !result.FileFactsStableAcrossVerification
                        ) {
                            result.Status = "FileFactsChanged";
                        }
                    }
                    catch {
                        result.FileFactsStableAcrossVerification =
                            false;
                        result.Status = "FileFactsUnavailable";
                    }
                }
                if (verifyReturned) {
                    try {
                        string afterFinalPath =
                            NormalizeFinalPath(
                                GetFinalPath(
                                    safeHandle.DangerousGetHandle()));
                        string afterFinalPathBindingToken =
                            GetPathBindingToken(afterFinalPath);
                        result.FinalPathStableAcrossVerification =
                            String.Equals(
                                result.FinalPathBindingToken,
                                afterFinalPathBindingToken,
                                StringComparison.Ordinal);
                        if (
                            !result.FinalPathStableAcrossVerification
                        ) {
                            result.Status = "FinalPathChanged";
                        }
                    }
                    catch {
                        result.FinalPathStableAcrossVerification =
                            false;
                        result.Status = "FinalPathUnavailable";
                    }
                }

                bool nativeCleanupFailed = false;
                try {
                    if (fileInfoPointer != IntPtr.Zero) {
                        Marshal.DestroyStructure(
                            fileInfoPointer,
                            typeof(WINTRUST_FILE_INFO));
                        Marshal.FreeHGlobal(fileInfoPointer);
                        fileInfoPointer = IntPtr.Zero;
                    }
                }
                catch {
                    nativeCleanupFailed = true;
                }
                try {
                    if (pathPointer != IntPtr.Zero) {
                        Marshal.FreeCoTaskMem(pathPointer);
                        pathPointer = IntPtr.Zero;
                    }
                }
                catch {
                    nativeCleanupFailed = true;
                }
                try {
                    if (signatureSettingsPointer != IntPtr.Zero) {
                        Marshal.DestroyStructure(
                            signatureSettingsPointer,
                            typeof(WINTRUST_SIGNATURE_SETTINGS));
                        Marshal.FreeHGlobal(
                            signatureSettingsPointer);
                        signatureSettingsPointer = IntPtr.Zero;
                    }
                }
                catch {
                    nativeCleanupFailed = true;
                }
                if (nativeCleanupFailed) {
                    result.Status = "NativeCleanupFailed";
                }

                if (originalPositionCaptured) {
                    try {
                        stream.Position = originalPosition;
                        result.StreamPositionRestored =
                            stream.Position == originalPosition;
                    }
                    catch {
                        result.StreamPositionRestored = false;
                    }
                    if (!result.StreamPositionRestored) {
                        result.Status = "StreamPositionRestoreFailed";
                    }
                }

                if (handleAddRef) {
                    try {
                        if (
                            safeHandle == null ||
                            safeHandle.IsInvalid ||
                            safeHandle.IsClosed
                        ) {
                            result.Status =
                                "CallerHandleInvalidated";
                        }
                        safeHandle.DangerousRelease();
                    }
                    catch {
                        result.Status = "NativeCleanupFailed";
                    }
                }
            }

            if (
                !result.StateCloseCompleted ||
                !result.StreamPositionRestored ||
                !result.CallerFileHandleSupplied ||
                !result.FinalPathStableAcrossVerification ||
                !result.FileFactsStableAcrossVerification ||
                result.ProviderOpenedFile != false ||
                result.PrimarySignerCount != 1 ||
                result.SecondarySignatureCount != 0 ||
                !String.Equals(
                    result.Status,
                    "Trusted",
                    StringComparison.Ordinal)
            ) {
                result.Trusted = false;
                result.PrimarySignerCertificateDerBytes = null;
                result.PrimarySignerCertificateDerLengthBytes = null;
            }
            return result;
        }

        private static void ExtractProviderPrimarySigner(
            IntPtr stateData,
            Observation result) {
            IntPtr providerPointer =
                WTHelperProvDataFromStateData(stateData);
            if (providerPointer == IntPtr.Zero) {
                result.Status = "ProviderDataUnavailable";
                return;
            }
            CRYPT_PROVIDER_DATA_SIGNERS_PREFIX provider =
                (CRYPT_PROVIDER_DATA_SIGNERS_PREFIX)
                    Marshal.PtrToStructure(
                        providerPointer,
                        typeof(
                            CRYPT_PROVIDER_DATA_SIGNERS_PREFIX));
            int providerPrefixSize =
                Marshal.SizeOf(
                    typeof(
                        CRYPT_PROVIDER_DATA_SIGNERS_PREFIX));
            if (provider.cbStruct < providerPrefixSize) {
                result.Status = "ProviderDataInvalid";
                return;
            }
            result.ProviderOpenedFile =
                provider.fOpenedFile != 0;
            result.PrimarySignerCount =
                provider.csSigners;
            if (provider.fOpenedFile != 0) {
                result.Status = "ProviderOpenedFile";
                return;
            }
            if (
                provider.csSigners != 1 ||
                provider.pasSigners == IntPtr.Zero
            ) {
                result.Status = "AmbiguousPrimarySigners";
                return;
            }
            ExtractPrimarySignerCertificate(
                providerPointer,
                provider.pasSigners,
                result);
        }

        private static void ExtractPrimarySignerCertificate(
            IntPtr providerPointer,
            IntPtr expectedPrimarySignerPointer,
            Observation result) {
            IntPtr signerPointer =
                WTHelperGetProvSignerFromChain(
                    providerPointer,
                    0,
                    false,
                    0);
            if (
                signerPointer == IntPtr.Zero ||
                signerPointer != expectedPrimarySignerPointer
            ) {
                result.Status = "PrimarySignerUnavailable";
                return;
            }
            CRYPT_PROVIDER_SGNR_HEAD signer =
                (CRYPT_PROVIDER_SGNR_HEAD)
                    Marshal.PtrToStructure(
                        signerPointer,
                        typeof(CRYPT_PROVIDER_SGNR_HEAD));
            if (
                signer.cbStruct <
                    Marshal.SizeOf(typeof(CRYPT_PROVIDER_SGNR_HEAD)) ||
                signer.csCertChain < 1 ||
                signer.pasCertChain == IntPtr.Zero
            ) {
                result.Status = "PrimarySignerInvalid";
                return;
            }

            IntPtr providerCertificatePointer =
                WTHelperGetProvCertFromChain(signerPointer, 0);
            if (
                providerCertificatePointer == IntPtr.Zero ||
                providerCertificatePointer != signer.pasCertChain
            ) {
                result.Status = "SignerCertificateUnavailable";
                return;
            }
            CRYPT_PROVIDER_CERT_HEAD providerCertificate =
                (CRYPT_PROVIDER_CERT_HEAD)
                    Marshal.PtrToStructure(
                        providerCertificatePointer,
                        typeof(CRYPT_PROVIDER_CERT_HEAD));
            if (
                providerCertificate.cbStruct <
                    Marshal.SizeOf(typeof(CRYPT_PROVIDER_CERT_HEAD)) ||
                providerCertificate.pCert == IntPtr.Zero
            ) {
                result.Status = "SignerCertificateInvalid";
                return;
            }

            CERT_CONTEXT certificate =
                (CERT_CONTEXT)
                    Marshal.PtrToStructure(
                        providerCertificate.pCert,
                        typeof(CERT_CONTEXT));
            if (
                certificate.pbCertEncoded == IntPtr.Zero ||
                certificate.cbCertEncoded < MinimumCertificateBytes ||
                certificate.cbCertEncoded > MaximumCertificateBytes
            ) {
                result.Status = "SignerCertificateDerInvalid";
                return;
            }
            byte[] certificateDer =
                new byte[(int)certificate.cbCertEncoded];
            Marshal.Copy(
                certificate.pbCertEncoded,
                certificateDer,
                0,
                certificateDer.Length);
            result.PrimarySignerCertificateDerBytes = certificateDer;
            result.PrimarySignerCertificateDerLengthBytes =
                certificate.cbCertEncoded;
            result.Trusted = true;
            result.Status = "Trusted";
        }

        private static Observation NewObservation(string status) {
            Observation result = new Observation();
            result.Trusted = false;
            result.Status = status;
            result.NativeStatusHex = null;
            result.CallerFileHandleSupplied = false;
            result.FinalPathStableAcrossVerification = false;
            result.FileFactsStableAcrossVerification = false;
            result.ProviderOpenedFile = null;
            result.PrimarySignerCount = null;
            result.SecondarySignatureCount = null;
            result.StateCloseCompleted = false;
            result.StateCloseNativeStatusHex = null;
            result.StreamPositionRestored = false;
            result.FinalPathBindingToken = null;
            result.PrimarySignerCertificateDerBytes = null;
            result.PrimarySignerCertificateDerLengthBytes = null;
            return result;
        }

        private static HeldFileIdentityObservation
            NewHeldFileIdentityObservation(string status) {
            HeldFileIdentityObservation result =
                new HeldFileIdentityObservation();
            result.Eligible = false;
            result.Status = status;
            result.FinalPathBindingToken = null;
            result.FileSystemName = null;
            result.NumberOfLinks = 0;
            result.IsDirectory = false;
            result.IsReparsePoint = false;
            result.VolumeSerialNumberHex = null;
            result.FileIndexHex = null;
            result.ArtifactSizeBytes = 0;
            result.FileFactsBindingToken = null;
            return result;
        }

        private static bool IsWindows11X64() {
            if (
                !Environment.Is64BitOperatingSystem ||
                !Environment.Is64BitProcess
            ) {
                return false;
            }
            RTL_OSVERSIONINFOEXW version =
                new RTL_OSVERSIONINFOEXW();
            version.dwOSVersionInfoSize =
                (uint)Marshal.SizeOf(
                    typeof(RTL_OSVERSIONINFOEXW));
            if (RtlGetVersion(ref version) != 0) {
                return false;
            }
            if (
                version.dwMajorVersion != 10 ||
                version.dwBuildNumber < Windows11MinimumBuild ||
                version.wProductType != VER_NT_WORKSTATION
            ) {
                return false;
            }
            ushort processMachine;
            ushort nativeMachine;
            if (!IsWow64Process2(
                GetCurrentProcess(),
                out processMachine,
                out nativeMachine)) {
                return false;
            }
            return (
                processMachine == IMAGE_FILE_MACHINE_UNKNOWN &&
                nativeMachine == IMAGE_FILE_MACHINE_AMD64
            );
        }

        private static BY_HANDLE_FILE_INFORMATION GetHeldFileFacts(
            IntPtr rawHandle) {
            BY_HANDLE_FILE_INFORMATION information;
            if (!GetFileInformationByHandle(
                rawHandle,
                out information)) {
                throw new IOException(
                    "The held file facts were unavailable.");
            }
            return information;
        }

        private static void GetHeldVolumeInformation(
            IntPtr rawHandle,
            out string fileSystemName,
            out uint volumeSerialNumber) {
            StringBuilder volumeNameBuffer = new StringBuilder(261);
            StringBuilder fileSystemNameBuffer = new StringBuilder(32);
            uint maximumComponentLength;
            uint fileSystemFlags;
            if (!GetVolumeInformationByHandleW(
                rawHandle,
                volumeNameBuffer,
                (uint)volumeNameBuffer.Capacity,
                out volumeSerialNumber,
                out maximumComponentLength,
                out fileSystemFlags,
                fileSystemNameBuffer,
                (uint)fileSystemNameBuffer.Capacity)) {
                throw new IOException(
                    "The held volume information was unavailable.");
            }
            fileSystemName = fileSystemNameBuffer.ToString();
            if (String.IsNullOrEmpty(fileSystemName)) {
                throw new IOException(
                    "The held volume file system was unavailable.");
            }
        }

        private static bool IsEligibleHeldFile(
            BY_HANDLE_FILE_INFORMATION information) {
            long size =
                ((long)information.FileSizeHigh << 32) |
                information.FileSizeLow;
            return (
                (information.FileAttributes &
                    FILE_ATTRIBUTE_DIRECTORY) == 0 &&
                (information.FileAttributes &
                    FILE_ATTRIBUTE_REPARSE_POINT) == 0 &&
                information.NumberOfLinks == 1 &&
                size > 0 &&
                size <= MaximumArtifactBytes
            );
        }

        private static bool SameHeldFileFacts(
            BY_HANDLE_FILE_INFORMATION before,
            BY_HANDLE_FILE_INFORMATION after) {
            return (
                before.FileAttributes == after.FileAttributes &&
                before.CreationTime.dwLowDateTime ==
                    after.CreationTime.dwLowDateTime &&
                before.CreationTime.dwHighDateTime ==
                    after.CreationTime.dwHighDateTime &&
                before.LastWriteTime.dwLowDateTime ==
                    after.LastWriteTime.dwLowDateTime &&
                before.LastWriteTime.dwHighDateTime ==
                    after.LastWriteTime.dwHighDateTime &&
                before.VolumeSerialNumber ==
                    after.VolumeSerialNumber &&
                before.FileSizeHigh == after.FileSizeHigh &&
                before.FileSizeLow == after.FileSizeLow &&
                before.NumberOfLinks == after.NumberOfLinks &&
                before.FileIndexHigh == after.FileIndexHigh &&
                before.FileIndexLow == after.FileIndexLow
            );
        }

        private static string GetFileFactsBindingToken(
            BY_HANDLE_FILE_INFORMATION facts,
            string fileSystemName,
            string finalPathBindingToken) {
            long artifactSizeBytes =
                ((long)facts.FileSizeHigh << 32) |
                facts.FileSizeLow;
            string canonical = String.Join(
                "\n",
                new string[] {
                    "cddsi-d027-claude-held-file-facts-v1",
                    "FinalPathBindingToken=" +
                        finalPathBindingToken,
                    "FileSystemName=" + fileSystemName,
                    "FileAttributesHex=" +
                        facts.FileAttributes.ToString(
                            "X8",
                            CultureInfo.InvariantCulture),
                    "CreationTimeHighHex=" +
                        facts.CreationTime.dwHighDateTime.ToString(
                            "X8",
                            CultureInfo.InvariantCulture),
                    "CreationTimeLowHex=" +
                        facts.CreationTime.dwLowDateTime.ToString(
                            "X8",
                            CultureInfo.InvariantCulture),
                    "LastWriteTimeHighHex=" +
                        facts.LastWriteTime.dwHighDateTime.ToString(
                            "X8",
                            CultureInfo.InvariantCulture),
                    "LastWriteTimeLowHex=" +
                        facts.LastWriteTime.dwLowDateTime.ToString(
                            "X8",
                            CultureInfo.InvariantCulture),
                    "VolumeSerialNumberHex=" +
                        facts.VolumeSerialNumber.ToString(
                            "X8",
                            CultureInfo.InvariantCulture),
                    "ArtifactSizeBytes=" +
                        artifactSizeBytes.ToString(
                            CultureInfo.InvariantCulture),
                    "NumberOfLinks=" +
                        facts.NumberOfLinks.ToString(
                            CultureInfo.InvariantCulture),
                    "FileIndexHex=" +
                        facts.FileIndexHigh.ToString(
                            "X8",
                            CultureInfo.InvariantCulture) +
                        facts.FileIndexLow.ToString(
                            "X8",
                            CultureInfo.InvariantCulture)
                });
            using (SHA256 sha = SHA256.Create()) {
                return BitConverter.ToString(
                    sha.ComputeHash(
                        Encoding.UTF8.GetBytes(canonical)))
                    .Replace("-", String.Empty)
                    .ToLowerInvariant();
            }
        }

        private static string GetFinalPath(IntPtr rawHandle) {
            const uint capacity = 32768;
            StringBuilder path = new StringBuilder((int)capacity);
            uint length = GetFinalPathNameByHandleW(
                rawHandle,
                path,
                capacity,
                0);
            if (length == 0 || length >= capacity) {
                throw new IOException(
                    "The held file final path was unavailable.");
            }
            return path.ToString();
        }

        private static string NormalizeFinalPath(string finalPath) {
            string normalized = finalPath;
            if (normalized.StartsWith(
                @"\\?\UNC\",
                StringComparison.OrdinalIgnoreCase)) {
                normalized = @"\\" + normalized.Substring(8);
            }
            else if (normalized.StartsWith(
                @"\\?\",
                StringComparison.OrdinalIgnoreCase)) {
                normalized = normalized.Substring(4);
            }
            return Path.GetFullPath(normalized);
        }

        private static string GetPathBindingToken(string finalPath) {
            string canonical =
                Path.GetFullPath(finalPath)
                    .TrimEnd(new char[] { '\\', '/' })
                    .ToUpperInvariant();
            using (SHA256 sha = SHA256.Create()) {
                byte[] bytes = Encoding.UTF8.GetBytes(canonical);
                return BitConverter.ToString(
                    sha.ComputeHash(bytes))
                    .Replace("-", String.Empty)
                    .ToLowerInvariant();
            }
        }

        private static string ToNativeStatusHex(int status) {
            return "0x" +
                unchecked((uint)status).ToString(
                    "X8",
                    CultureInfo.InvariantCulture);
        }

        private static string MapUntrustedStatus(int status) {
            uint value = unchecked((uint)status);
            if (value == 0x800B0100) {
                return "NoSignature";
            }
            if (
                value == 0x800B0001 ||
                value == 0x800B0002 ||
                value == 0x800B0003
            ) {
                return "UnsupportedSubject";
            }
            if (
                value == 0x800B0004 ||
                value == 0x800B0101 ||
                value == 0x800B0109 ||
                value == 0x800B010A ||
                value == 0x800B0111
            ) {
                return "Untrusted";
            }
            return "PolicyRejected";
        }
    }
}
'@

$script:CddsiD027ClaudeMsixSameStateSignerNativeTypeResolver =
    [System.Func[object]]{
        $nativeTypeFullName =
            'Cddsi.D027.ClaudeMsixSameStateWinVerifyTrustV1'
        try {
            if (
                $null -eq
                    $script:CddsiD027ClaudeMsixSameStateSignerNativeType
            ) {
                $preexistingTypes = @(
                    foreach (
                        $assembly in
                            [AppDomain]::CurrentDomain.GetAssemblies()
                    ) {
                        $candidate = $assembly.GetType(
                            $nativeTypeFullName,
                            $false,
                            $false
                        )
                        if ($null -ne $candidate) {
                            $candidate
                        }
                    }
                )
                if ($preexistingTypes.Count -ne 0) {
                    return $null
                }
                $compiledTypes = @(
                    Add-Type `
                        -TypeDefinition `
                            $script:CddsiD027ClaudeMsixSameStateSignerNativeTypeDefinition `
                        -Language CSharp `
                        -PassThru `
                        -ErrorAction Stop
                )
                $matchingTypes = @(
                    $compiledTypes |
                        Where-Object {
                            $_.FullName -ceq $nativeTypeFullName
                        }
                )
                if ($matchingTypes.Count -ne 1) {
                    return $null
                }
                $script:CddsiD027ClaudeMsixSameStateSignerNativeType =
                    $matchingTypes[0]
                $script:CddsiD027ClaudeMsixSameStateSignerNativeAssemblyFullName =
                    $matchingTypes[0].Assembly.FullName
            }

            $nativeType =
                $script:CddsiD027ClaudeMsixSameStateSignerNativeType
            $loadedMatches = @(
                foreach (
                    $assembly in
                        [AppDomain]::CurrentDomain.GetAssemblies()
                ) {
                    $candidate = $assembly.GetType(
                        $nativeTypeFullName,
                        $false,
                        $false
                    )
                    if ($null -ne $candidate) {
                        $candidate
                    }
                }
            )
            if (
                $null -eq $nativeType -or
                $nativeType.FullName -cne $nativeTypeFullName -or
                $nativeType.Assembly.FullName -cne
                    $script:CddsiD027ClaudeMsixSameStateSignerNativeAssemblyFullName -or
                $loadedMatches.Count -ne 1 -or
                -not [object]::ReferenceEquals(
                    $loadedMatches[0],
                    $nativeType
                )
            ) {
                return $null
            }
            return $nativeType
        }
        catch {
            return $null
        }
    }

$script:CddsiD027ClaudeMsixHeldFileIdentityObserver =
    [System.Func[System.IO.FileStream, object]]{
        param([AllowNull()][System.IO.FileStream]$Stream)

        $result = [ordered]@{
            SchemaVersion          = 1
            ContractVersion       =
                'cddsi-d027-claude-msix-held-file-native-observation-v1'
            ObservationMethod     =
                'CallerHeldFileStreamNativeIdentity'
            Eligible              = $false
            Status                = 'InvalidInput'
            FinalPathBindingToken = $null
            FileSystemName        = $null
            NumberOfLinks         = $null
            IsDirectory           = $null
            IsReparsePoint        = $null
            VolumeSerialNumberHex = $null
            FileIndexHex          = $null
            ArtifactSizeBytes     = $null
            FileFactsBindingToken = $null
        }
        if ($null -eq $Stream) {
            return [pscustomobject]$result
        }
        if (
            $PSVersionTable.PSVersion.Major -ne 5 -or
            $PSVersionTable.PSVersion.Minor -ne 1 -or
            -not [Environment]::Is64BitOperatingSystem -or
            -not [Environment]::Is64BitProcess
        ) {
            $result.Status = 'UnsupportedRuntime'
            return [pscustomobject]$result
        }

        try {
            $nativeType =
                $script:CddsiD027ClaudeMsixSameStateSignerNativeTypeResolver.
                    Invoke()
            if ($null -eq $nativeType) {
                $result.Status = 'NativeTypeUnavailable'
                return [pscustomobject]$result
            }
            $observeMethod = $nativeType.GetMethod(
                'ObserveHeldFileIdentity',
                [Reflection.BindingFlags]'Public,Static'
            )
            if ($null -eq $observeMethod) {
                $result.Status = 'NativeTypeUnavailable'
                return [pscustomobject]$result
            }
            $native = $observeMethod.Invoke(
                $null,
                [object[]]@($Stream)
            )
            if ($null -eq $native) {
                $result.Status = 'InvalidNativeObservation'
                return [pscustomobject]$result
            }

            $result.Eligible = [bool]$native.Eligible
            $result.Status = [string]$native.Status
            $result.FinalPathBindingToken =
                [string]$native.FinalPathBindingToken
            $result.FileSystemName =
                [string]$native.FileSystemName
            $result.NumberOfLinks =
                [long]$native.NumberOfLinks
            $result.IsDirectory =
                [bool]$native.IsDirectory
            $result.IsReparsePoint =
                [bool]$native.IsReparsePoint
            $result.VolumeSerialNumberHex =
                [string]$native.VolumeSerialNumberHex
            $result.FileIndexHex =
                [string]$native.FileIndexHex
            $result.ArtifactSizeBytes =
                [long]$native.ArtifactSizeBytes
            $result.FileFactsBindingToken =
                [string]$native.FileFactsBindingToken

            $eligibleShape = (
                $result.Eligible -and
                $result.Status -ceq 'Eligible' -and
                $result.FinalPathBindingToken -cmatch
                    '^[a-f0-9]{64}$' -and
                $result.FinalPathBindingToken -cnotmatch
                    '^0{64}$' -and
                $result.FileSystemName -ceq 'NTFS' -and
                $result.NumberOfLinks -eq 1 -and
                -not $result.IsDirectory -and
                -not $result.IsReparsePoint -and
                $result.VolumeSerialNumberHex -cmatch
                    '^[0-9A-F]{8}$' -and
                $result.VolumeSerialNumberHex -cne
                    '00000000' -and
                $result.FileIndexHex -cmatch
                    '^[0-9A-F]{16}$' -and
                $result.FileIndexHex -cne
                    '0000000000000000' -and
                $result.ArtifactSizeBytes -is [long] -and
                $result.ArtifactSizeBytes -ge 1 -and
                $result.ArtifactSizeBytes -le
                    $script:CddsiD027ClaudeMsixMaximumBytes -and
                $result.FileFactsBindingToken -cmatch
                    '^[a-f0-9]{64}$' -and
                $result.FileFactsBindingToken -cnotmatch
                    '^0{64}$'
            )
            if (-not $eligibleShape) {
                $result.Eligible = $false
                if ($result.Status -ceq 'Eligible') {
                    $result.Status = 'InvalidNativeObservation'
                }
            }
        }
        catch {
            $result.Eligible = $false
            $result.Status = 'NativeUnavailable'
        }
        if (-not $result.Eligible) {
            $result.FinalPathBindingToken = $null
            $result.FileSystemName = $null
            $result.NumberOfLinks = $null
            $result.IsDirectory = $null
            $result.IsReparsePoint = $null
            $result.VolumeSerialNumberHex = $null
            $result.FileIndexHex = $null
            $result.ArtifactSizeBytes = $null
            $result.FileFactsBindingToken = $null
        }
        return [pscustomobject]$result
    }

$script:CddsiD027ClaudeMsixSameStateSignerObserver =
    [System.Func[System.IO.FileStream, object]]{
        param([AllowNull()][System.IO.FileStream]$Stream)

        $result = [ordered]@{
            SchemaVersion                          = 1
            ContractVersion                       =
                'cddsi-d027-claude-msix-same-state-native-observation-v1'
            ObservationMethod                     =
                'CallerHeldFileStreamNativeObservation'
            VerificationMethod                    =
                'WinVerifyTrustExGenericVerifyV2'
            SignerExtractionMethod                =
                'WTHelperPrimarySignerCertificateFromSameState'
            StateLifecycle                        =
                'VerifyExtractCopyCloseRequired'
            FinalPathBindingToken                 = $null
            CallerFileHandleSupplied              = $false
            FinalPathStableAcrossVerification     = $false
            FileFactsStableAcrossVerification     = $false
            ProviderOpenedFile                    = $null
            PrimarySignerCount                    = $null
            SecondarySignatureCount               = $null
            WinVerifyTrustTrusted                 = $false
            WinVerifyTrustStatus                  = 'InvalidInput'
            WinVerifyTrustNativeStatusHex         = $null
            WinVerifyTrustRevocationMode          = 'NotChecked'
            StateCloseCompleted                   = $false
            StateCloseNativeStatusHex             = $null
            StreamPositionRestored                = $false
            PrimarySignerCertificateDerBytes      = $null
            PrimarySignerCertificateDerLengthBytes = $null
        }
        if ($null -eq $Stream) {
            return [pscustomobject]$result
        }
        if (
            $PSVersionTable.PSVersion.Major -ne 5 -or
            $PSVersionTable.PSVersion.Minor -ne 1 -or
            -not [Environment]::Is64BitOperatingSystem -or
            -not [Environment]::Is64BitProcess
        ) {
            $result.WinVerifyTrustStatus = 'UnsupportedRuntime'
            return [pscustomobject]$result
        }

        try {
            $nativeType =
                $script:CddsiD027ClaudeMsixSameStateSignerNativeTypeResolver.
                    Invoke()
            if ($null -eq $nativeType) {
                $result.WinVerifyTrustStatus =
                    'NativeTypeUnavailable'
                return [pscustomobject]$result
            }

            $observeMethod = $nativeType.GetMethod(
                'Observe',
                [Reflection.BindingFlags]'Public,Static'
            )
            if ($null -eq $observeMethod) {
                $result.WinVerifyTrustStatus =
                    'NativeTypeUnavailable'
                return [pscustomobject]$result
            }
            $native = $observeMethod.Invoke(
                $null,
                [object[]]@($Stream)
            )
            if ($null -eq $native) {
                $result.WinVerifyTrustStatus =
                    'InvalidNativeObservation'
                return [pscustomobject]$result
            }

            $result.FinalPathBindingToken =
                [string]$native.FinalPathBindingToken
            $result.CallerFileHandleSupplied =
                [bool]$native.CallerFileHandleSupplied
            $result.FinalPathStableAcrossVerification =
                [bool]$native.FinalPathStableAcrossVerification
            $result.FileFactsStableAcrossVerification =
                [bool]$native.FileFactsStableAcrossVerification
            if ($null -ne $native.ProviderOpenedFile) {
                $result.ProviderOpenedFile =
                    [bool]$native.ProviderOpenedFile
            }
            if ($null -ne $native.PrimarySignerCount) {
                $result.PrimarySignerCount =
                    [long]$native.PrimarySignerCount
            }
            if ($null -ne $native.SecondarySignatureCount) {
                $result.SecondarySignatureCount =
                    [long]$native.SecondarySignatureCount
            }
            $result.WinVerifyTrustTrusted =
                [bool]$native.Trusted
            $result.WinVerifyTrustStatus =
                [string]$native.Status
            $result.WinVerifyTrustNativeStatusHex =
                [string]$native.NativeStatusHex
            $result.StateCloseCompleted =
                [bool]$native.StateCloseCompleted
            $result.StateCloseNativeStatusHex =
                [string]$native.StateCloseNativeStatusHex
            $result.StreamPositionRestored =
                [bool]$native.StreamPositionRestored

            if ($null -ne $native.PrimarySignerCertificateDerBytes) {
                $result.PrimarySignerCertificateDerBytes =
                    [byte[]]$native.PrimarySignerCertificateDerBytes.Clone()
            }
            if (
                $null -ne
                    $native.PrimarySignerCertificateDerLengthBytes
            ) {
                $result.PrimarySignerCertificateDerLengthBytes =
                    [long]$native.PrimarySignerCertificateDerLengthBytes
            }

            $trustedShape = (
                $result.WinVerifyTrustTrusted -and
                $result.WinVerifyTrustStatus -ceq 'Trusted' -and
                $result.WinVerifyTrustNativeStatusHex -ceq
                    '0x00000000' -and
                $result.CallerFileHandleSupplied -and
                $result.FinalPathStableAcrossVerification -and
                $result.FileFactsStableAcrossVerification -and
                $result.ProviderOpenedFile -is [bool] -and
                -not $result.ProviderOpenedFile -and
                $result.PrimarySignerCount -is [long] -and
                $result.PrimarySignerCount -eq 1 -and
                $result.SecondarySignatureCount -is [long] -and
                $result.SecondarySignatureCount -eq 0 -and
                $result.StateCloseCompleted -and
                $result.StateCloseNativeStatusHex -ceq
                    '0x00000000' -and
                $result.StreamPositionRestored -and
                $result.FinalPathBindingToken -cmatch
                    '^[a-f0-9]{64}$' -and
                $result.FinalPathBindingToken -cnotmatch
                    '^0{64}$' -and
                $result.PrimarySignerCertificateDerBytes -is
                    [byte[]] -and
                $result.PrimarySignerCertificateDerBytes.Length -ge
                    256 -and
                $result.PrimarySignerCertificateDerBytes.Length -le
                    $script:CddsiD027ClaudeSignerCertificateMaximumBytes -and
                $result.PrimarySignerCertificateDerLengthBytes -is
                    [long] -and
                $result.PrimarySignerCertificateDerLengthBytes -eq
                    $result.PrimarySignerCertificateDerBytes.Length
            )
            if (-not $trustedShape) {
                $result.WinVerifyTrustTrusted = $false
                $result.PrimarySignerCertificateDerBytes = $null
                $result.PrimarySignerCertificateDerLengthBytes = $null
                if ($result.WinVerifyTrustStatus -ceq 'Trusted') {
                    $result.WinVerifyTrustStatus =
                        'InvalidNativeObservation'
                }
            }
        }
        catch {
            $result.WinVerifyTrustTrusted = $false
            $result.WinVerifyTrustStatus = 'NativeUnavailable'
            $result.PrimarySignerCertificateDerBytes = $null
            $result.PrimarySignerCertificateDerLengthBytes = $null
        }
        return [pscustomobject]$result
    }

$script:CddsiD027ClaudeMsixHeldHandleCorrelationCore =
    [System.Func[System.IO.FileStream, string, object, object]]{
        param(
            [AllowNull()][System.IO.FileStream]$Stream,
            [AllowNull()][string]$ExpectedDestinationPath,
            [AllowNull()]$FileShareReadCapability
        )

        $result = [ordered]@{
            SchemaVersion                        = 1
            ContractVersion                     =
                'cddsi-d027-claude-msix-held-handle-correlation-v1'
            ObservationMethod                   =
                'CallerHeldReadOnlyFileStreamCorrelation'
            Status                              = 'FAILED'
            ErrorCode                           = 'INVALID_INPUT'
            ExpectedDestinationMatched          = $false
            PreVerificationHashCompleted        = $false
            ManifestReadCompleted               = $false
            SameStateVerificationCompleted      = $false
            PostVerificationHashCompleted       = $false
            PreAndPostContentHashMatched         = $false
            PreAndPostFileFactsMatched           = $false
            StreamPositionRestored              = $false
            WinVerifyTrustStatus                = $null
            StateCloseCompleted                 = $false
            FinalPathBindingToken               = $null
            ArtifactSha256                      = $null
            ArtifactSizeBytes                   = $null
            HeldFileIdentityObservation         = $null
            ManifestIdentity                    = $null
            SameStateSignerObservation          = $null
        }
        $initialPosition = [long]0
        $initialPositionCaptured = $false
        $preHasher = $null
        $postHasher = $null
        try {
            if (
                $null -eq $Stream -or
                $ExpectedDestinationPath -isnot [string] -or
                $ExpectedDestinationPath.Length -lt 8 -or
                $ExpectedDestinationPath.Length -gt 32767 -or
                $ExpectedDestinationPath.IndexOf([char]0) -ge 0 -or
                $ExpectedDestinationPath.Contains('/') -or
                $ExpectedDestinationPath -cnotmatch
                    '^[A-Za-z]:\\' -or
                [IO.Path]::GetFullPath($ExpectedDestinationPath) -cne
                    $ExpectedDestinationPath -or
                [IO.Path]::GetExtension($ExpectedDestinationPath) -cne
                    '.msix' -or
                -not $Stream.CanRead -or
                -not $Stream.CanSeek -or
                $Stream.CanWrite
            ) {
                throw 'Invalid held-handle correlation input.'
            }
            $initialPosition = [long]$Stream.Position
            $initialPositionCaptured = $true
            if (
                $initialPosition -lt 0 -or
                $initialPosition -gt $Stream.Length -or
                $Stream.Length -lt 1 -or
                $Stream.Length -gt
                    $script:CddsiD027ClaudeMsixMaximumBytes
            ) {
                throw 'Invalid held-handle correlation stream bounds.'
            }
            $result.ErrorCode = 'HELD_HANDLE_CORRELATION_FAILED'

            $beforeIdentity =
                $script:CddsiD027ClaudeMsixHeldFileIdentityObserver.
                    Invoke($Stream)
            if (
                $null -eq $beforeIdentity -or
                -not $beforeIdentity.Eligible
            ) {
                $result.ErrorCode =
                    'HELD_FILE_IDENTITY_UNAVAILABLE'
                throw 'Held file identity was unavailable.'
            }
            $expectedPathBindingToken =
                Get-CddsiPathBindingToken `
                    -Path $ExpectedDestinationPath
            if (
                $beforeIdentity.FinalPathBindingToken -cne
                    $expectedPathBindingToken
            ) {
                $result.ErrorCode =
                    'DESTINATION_BINDING_MISMATCH'
                throw 'Held file destination binding did not match.'
            }
            $result.ExpectedDestinationMatched = $true

            $preHasher =
                [System.Security.Cryptography.SHA256]::Create()
            $Stream.Position = 0
            $preHash = [BitConverter]::ToString(
                $preHasher.ComputeHash($Stream)
            ).Replace('-', '').ToLowerInvariant()
            $preLength = [long]$Stream.Length
            $Stream.Position = $initialPosition
            if (
                $preHash -cnotmatch '^[a-f0-9]{64}$' -or
                $preHash -cmatch '^0{64}$' -or
                $preLength -ne
                    [long]$beforeIdentity.ArtifactSizeBytes
            ) {
                $result.ErrorCode = 'PRE_VERIFICATION_HASH_INVALID'
                throw 'Pre-verification hash was invalid.'
            }
            $result.PreVerificationHashCompleted = $true

            try {
                $manifestIdentity =
                    Read-CddsiD027ClaudeMsixManifest `
                        -PackageStream $Stream
            }
            catch {
                $result.ErrorCode = 'MSIX_MANIFEST_INVALID'
                throw 'MSIX manifest was invalid.'
            }
            if ([long]$Stream.Position -ne $initialPosition) {
                $result.ErrorCode =
                    'STREAM_POSITION_NOT_RESTORED'
                throw 'Manifest reader did not restore stream position.'
            }
            $result.ManifestReadCompleted = $true

            $signerObservation =
                $script:CddsiD027ClaudeMsixSameStateSignerObserver.
                    Invoke($Stream)
            if ($null -eq $signerObservation) {
                $result.ErrorCode =
                    'MSIX_SIGNATURE_OBSERVATION_INVALID'
                throw 'MSIX signature observation was invalid.'
            }
            $allowedWinVerifyTrustStatuses = @(
                'InvalidInput',
                'UnsupportedRuntime',
                'HeldFileIneligible',
                'SignatureSettingsUnavailable',
                'NoSignature',
                'UnsupportedSubject',
                'Untrusted',
                'PolicyRejected',
                'StateUnavailable',
                'StateCloseFailed',
                'FileFactsChanged',
                'FileFactsUnavailable',
                'FinalPathChanged',
                'FinalPathUnavailable',
                'NativeCleanupFailed',
                'StreamPositionRestoreFailed',
                'ProviderDataUnavailable',
                'ProviderDataInvalid',
                'ProviderOpenedFile',
                'AmbiguousPrimarySigners',
                'PrimarySignerUnavailable',
                'PrimarySignerInvalid',
                'SignerCertificateUnavailable',
                'SignerCertificateInvalid',
                'SignerCertificateDerInvalid',
                'Trusted',
                'NativeTypeUnavailable',
                'InvalidNativeObservation',
                'NativeUnavailable'
            )
            $result.WinVerifyTrustStatus = if (
                $signerObservation.WinVerifyTrustStatus -is [string] -and
                $allowedWinVerifyTrustStatuses -ccontains
                    $signerObservation.WinVerifyTrustStatus
            ) {
                [string]$signerObservation.WinVerifyTrustStatus
            }
            else {
                'InvalidObservation'
            }
            $result.StateCloseCompleted =
                [bool]$signerObservation.StateCloseCompleted
            $result.SameStateVerificationCompleted = (
                $signerObservation.WinVerifyTrustNativeStatusHex -is
                    [string] -and
                $signerObservation.StateCloseCompleted -and
                $signerObservation.StreamPositionRestored
            )
            if ([long]$Stream.Position -ne $initialPosition) {
                $result.ErrorCode =
                    'STREAM_POSITION_NOT_RESTORED'
                throw 'Signature observer did not restore stream position.'
            }

            $postHasher =
                [System.Security.Cryptography.SHA256]::Create()
            $Stream.Position = 0
            $postHash = [BitConverter]::ToString(
                $postHasher.ComputeHash($Stream)
            ).Replace('-', '').ToLowerInvariant()
            $postLength = [long]$Stream.Length
            $Stream.Position = $initialPosition
            if (
                $postHash -cnotmatch '^[a-f0-9]{64}$' -or
                $postHash -cmatch '^0{64}$'
            ) {
                $result.ErrorCode =
                    'POST_VERIFICATION_HASH_INVALID'
                throw 'Post-verification hash was invalid.'
            }
            $result.PostVerificationHashCompleted = $true
            $result.PreAndPostContentHashMatched = (
                $postHash -ceq $preHash -and
                $postLength -eq $preLength
            )

            $afterIdentity =
                $script:CddsiD027ClaudeMsixHeldFileIdentityObserver.
                    Invoke($Stream)
            if (
                $null -eq $afterIdentity -or
                -not $afterIdentity.Eligible
            ) {
                $result.ErrorCode =
                    'HELD_FILE_IDENTITY_UNAVAILABLE'
                throw 'Held file readback identity was unavailable.'
            }
            $result.PreAndPostFileFactsMatched = (
                $afterIdentity.FinalPathBindingToken -ceq
                    $beforeIdentity.FinalPathBindingToken -and
                $afterIdentity.FileFactsBindingToken -ceq
                    $beforeIdentity.FileFactsBindingToken -and
                $afterIdentity.FileSystemName -ceq
                    $beforeIdentity.FileSystemName -and
                [long]$afterIdentity.NumberOfLinks -eq
                    [long]$beforeIdentity.NumberOfLinks -and
                [bool]$afterIdentity.IsDirectory -eq
                    [bool]$beforeIdentity.IsDirectory -and
                [bool]$afterIdentity.IsReparsePoint -eq
                    [bool]$beforeIdentity.IsReparsePoint -and
                $afterIdentity.VolumeSerialNumberHex -ceq
                    $beforeIdentity.VolumeSerialNumberHex -and
                $afterIdentity.FileIndexHex -ceq
                    $beforeIdentity.FileIndexHex -and
                [long]$afterIdentity.ArtifactSizeBytes -eq
                    [long]$beforeIdentity.ArtifactSizeBytes -and
                [long]$afterIdentity.ArtifactSizeBytes -eq
                    $postLength
            )
            if (-not $result.PreAndPostContentHashMatched) {
                $result.ErrorCode =
                    'HELD_FILE_CONTENT_CHANGED'
                throw 'Held file content changed.'
            }
            if (-not $result.PreAndPostFileFactsMatched) {
                $result.ErrorCode =
                    'HELD_FILE_IDENTITY_CHANGED'
                throw 'Held file identity changed.'
            }
            if (-not $result.SameStateVerificationCompleted) {
                $result.ErrorCode =
                    'MSIX_SIGNATURE_OBSERVATION_INCOMPLETE'
                throw 'MSIX signature observation was incomplete.'
            }
            if (-not $signerObservation.WinVerifyTrustTrusted) {
                $result.ErrorCode = 'MSIX_SIGNATURE_NOT_TRUSTED'
                throw 'MSIX signature was not trusted.'
            }
            $trustedSignerShape = (
                (Test-CddsiExactPropertySet `
                    -InputObject $signerObservation `
                    -Expected `
                        $script:CddsiD027ClaudeMsixSameStateNativeObservationFieldNames) -and
                (Test-CddsiSchemaVersionOne `
                    -Value $signerObservation.SchemaVersion) -and
                $signerObservation.ContractVersion -is [string] -and
                $signerObservation.ContractVersion -ceq
                    'cddsi-d027-claude-msix-same-state-native-observation-v1' -and
                $signerObservation.ObservationMethod -is [string] -and
                $signerObservation.ObservationMethod -ceq
                    'CallerHeldFileStreamNativeObservation' -and
                $signerObservation.VerificationMethod -is [string] -and
                $signerObservation.VerificationMethod -ceq
                    'WinVerifyTrustExGenericVerifyV2' -and
                $signerObservation.SignerExtractionMethod -is [string] -and
                $signerObservation.SignerExtractionMethod -ceq
                    'WTHelperPrimarySignerCertificateFromSameState' -and
                $signerObservation.StateLifecycle -is [string] -and
                $signerObservation.StateLifecycle -ceq
                    'VerifyExtractCopyCloseRequired' -and
                $signerObservation.FinalPathBindingToken -is [string] -and
                $signerObservation.FinalPathBindingToken -ceq
                    $beforeIdentity.FinalPathBindingToken -and
                $signerObservation.CallerFileHandleSupplied -is [bool] -and
                $signerObservation.CallerFileHandleSupplied -and
                $signerObservation.FinalPathStableAcrossVerification -is
                    [bool] -and
                $signerObservation.FinalPathStableAcrossVerification -and
                $signerObservation.FileFactsStableAcrossVerification -is
                    [bool] -and
                $signerObservation.FileFactsStableAcrossVerification -and
                $signerObservation.ProviderOpenedFile -is [bool] -and
                -not $signerObservation.ProviderOpenedFile -and
                $signerObservation.PrimarySignerCount -is [long] -and
                $signerObservation.PrimarySignerCount -eq 1 -and
                $signerObservation.SecondarySignatureCount -is [long] -and
                $signerObservation.SecondarySignatureCount -eq 0 -and
                $signerObservation.WinVerifyTrustStatus -is [string] -and
                $signerObservation.WinVerifyTrustStatus -ceq 'Trusted' -and
                $signerObservation.WinVerifyTrustNativeStatusHex -is
                    [string] -and
                $signerObservation.WinVerifyTrustNativeStatusHex -ceq
                    '0x00000000' -and
                $signerObservation.WinVerifyTrustRevocationMode -is
                    [string] -and
                $signerObservation.WinVerifyTrustRevocationMode -ceq
                    'NotChecked' -and
                $signerObservation.StateCloseCompleted -is [bool] -and
                $signerObservation.StateCloseCompleted -and
                $signerObservation.StateCloseNativeStatusHex -is
                    [string] -and
                $signerObservation.StateCloseNativeStatusHex -ceq
                    '0x00000000' -and
                $signerObservation.StreamPositionRestored -is [bool] -and
                $signerObservation.StreamPositionRestored -and
                $signerObservation.PrimarySignerCertificateDerBytes -is
                    [byte[]] -and
                $signerObservation.PrimarySignerCertificateDerBytes.Length -ge
                    256 -and
                $signerObservation.PrimarySignerCertificateDerBytes.Length -le
                    $script:CddsiD027ClaudeSignerCertificateMaximumBytes -and
                $signerObservation.PrimarySignerCertificateDerLengthBytes -is
                    [long] -and
                $signerObservation.PrimarySignerCertificateDerLengthBytes -eq
                    $signerObservation.PrimarySignerCertificateDerBytes.Length
            )
            if (-not $trustedSignerShape) {
                $result.ErrorCode =
                    'MSIX_SIGNATURE_OBSERVATION_INVALID'
                throw 'MSIX trusted signature observation was invalid.'
            }
            if (
                -not [object]::ReferenceEquals(
                    $FileShareReadCapability,
                    $script:CddsiD027ClaudeFileShareReadConstructionCapability
                )
            ) {
                $result.ErrorCode =
                    'CALLER_FILE_SHARE_POLICY_UNPROVEN'
                throw 'Caller file share policy was not proven.'
            }

            $result.ErrorCode = 'CORRELATION_MATERIAL_INVALID'
            $observedAtUtc = [DateTimeOffset]::UtcNow.ToString(
                'yyyy-MM-ddTHH:mm:ssZ',
                [Globalization.CultureInfo]::InvariantCulture
            )
            $fileIdentityToken =
                Get-CddsiD027ClaudeFileIdentityToken `
                    -FinalPathBindingToken `
                        $beforeIdentity.FinalPathBindingToken `
                    -VolumeSerialNumberHex `
                        $beforeIdentity.VolumeSerialNumberHex `
                    -FileIndexHex $beforeIdentity.FileIndexHex `
                    -ArtifactSha256 $preHash `
                    -ArtifactSizeBytes $preLength
            $heldObservation = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion =
                    'cddsi-d027-claude-held-artifact-observation-v1'
                ObservationMethod = 'HeldFinalFileHandle'
                FinalPathBindingToken =
                    $beforeIdentity.FinalPathBindingToken
                FileSystemName = $beforeIdentity.FileSystemName
                NumberOfLinks = [long]$beforeIdentity.NumberOfLinks
                IsDirectory = [bool]$beforeIdentity.IsDirectory
                IsReparsePoint = [bool]$beforeIdentity.IsReparsePoint
                VolumeSerialNumberHex =
                    $beforeIdentity.VolumeSerialNumberHex
                FileIndexHex = $beforeIdentity.FileIndexHex
                FileIdentityToken = $fileIdentityToken
                ArtifactSha256 = $preHash
                ArtifactSizeBytes = $preLength
                ObservedAtUtc = $observedAtUtc
            }
            $result.Status = 'CORRELATED'
            $result.ErrorCode = ''
            $result.FinalPathBindingToken =
                $beforeIdentity.FinalPathBindingToken
            $result.ArtifactSha256 = $preHash
            $result.ArtifactSizeBytes = $preLength
            $result.HeldFileIdentityObservation = $heldObservation
            $result.ManifestIdentity = $manifestIdentity
            $result.SameStateSignerObservation = $signerObservation
        }
        catch {
            # Raw exception data is intentionally discarded from this
            # path-free private observation.
        }
        finally {
            $correlationCleanupFailed = $false
            if ($null -ne $postHasher) {
                try {
                    $postHasher.Dispose()
                }
                catch {
                    $correlationCleanupFailed = $true
                }
            }
            if ($null -ne $preHasher) {
                try {
                    $preHasher.Dispose()
                }
                catch {
                    $correlationCleanupFailed = $true
                }
            }
            if ($initialPositionCaptured) {
                try {
                    $Stream.Position = $initialPosition
                    $result.StreamPositionRestored = (
                        [long]$Stream.Position -eq $initialPosition
                    )
                }
                catch {
                    $result.StreamPositionRestored = $false
                }
            }
            if ($correlationCleanupFailed) {
                $result.Status = 'FAILED'
                $result.ErrorCode =
                    'CORRELATION_HASH_CLEANUP_FAILED'
                $result.FinalPathBindingToken = $null
                $result.ArtifactSha256 = $null
                $result.ArtifactSizeBytes = $null
                $result.HeldFileIdentityObservation = $null
                $result.ManifestIdentity = $null
                $result.SameStateSignerObservation = $null
            }
            if (
                $initialPositionCaptured -and
                -not $result.StreamPositionRestored
            ) {
                $result.Status = 'FAILED'
                $result.ErrorCode =
                    'STREAM_POSITION_NOT_RESTORED'
                $result.FinalPathBindingToken = $null
                $result.ArtifactSha256 = $null
                $result.ArtifactSizeBytes = $null
                $result.HeldFileIdentityObservation = $null
                $result.ManifestIdentity = $null
                $result.SameStateSignerObservation = $null
            }
        }
        return [pscustomobject]$result
    }

$script:CddsiD027ClaudeMsixHeldHandleCorrelator =
    [System.Func[System.IO.FileStream, string, object]]{
        param(
            [AllowNull()][System.IO.FileStream]$Stream,
            [AllowNull()][string]$ExpectedDestinationPath
        )

        return $script:CddsiD027ClaudeMsixHeldHandleCorrelationCore.
            Invoke(
                $Stream,
                $ExpectedDestinationPath,
                $null
            )
    }

$script:CddsiD027ClaudeMsixFileShareReadConstructionSiteCorrelator =
    [System.Func[string, object]]{
        param(
            [AllowNull()][string]$ExpectedDestinationPath
        )

        $stream = $null
        $outcome = $null
        $streamCloseFailed = $false
        try {
            if (
                $ExpectedDestinationPath -isnot [string] -or
                $ExpectedDestinationPath.Length -lt 8 -or
                $ExpectedDestinationPath.Length -gt 32767 -or
                $ExpectedDestinationPath.IndexOf([char]0) -ge 0 -or
                $ExpectedDestinationPath.Contains('/') -or
                $ExpectedDestinationPath -cnotmatch '^[A-Za-z]:\\' -or
                [IO.Path]::GetFullPath($ExpectedDestinationPath) -cne
                    $ExpectedDestinationPath -or
                [IO.Path]::GetExtension($ExpectedDestinationPath) -cne
                    '.msix'
            ) {
                throw 'Invalid construction-site final file path.'
            }
            $stream = [System.IO.FileStream]::new(
                $ExpectedDestinationPath,
                [System.IO.FileMode]::Open,
                [System.IO.FileAccess]::Read,
                [System.IO.FileShare]::Read,
                $script:CddsiD027ClaudeDownloadBufferBytes,
                [System.IO.FileOptions]::SequentialScan
            )
            $outcome =
                $script:CddsiD027ClaudeMsixHeldHandleCorrelationCore.
                    Invoke(
                        $stream,
                        $ExpectedDestinationPath,
                        $script:CddsiD027ClaudeFileShareReadConstructionCapability
                    )
        }
        catch {
            $outcome =
                $script:CddsiD027ClaudeMsixHeldHandleCorrelationCore.
                    Invoke(
                        $null,
                        $ExpectedDestinationPath,
                        $null
                    )
            $outcome.ErrorCode =
                'CONSTRUCTION_SITE_HELD_FILE_OPEN_FAILED'
        }
        finally {
            if ($null -ne $stream) {
                try {
                    $stream.Dispose()
                }
                catch {
                    $streamCloseFailed = $true
                }
            }
            if ($streamCloseFailed) {
                if ($null -eq $outcome) {
                    $outcome =
                        $script:CddsiD027ClaudeMsixHeldHandleCorrelationCore.
                            Invoke(
                                $null,
                                $ExpectedDestinationPath,
                                $null
                            )
                }
                $outcome.Status = 'FAILED'
                $outcome.ErrorCode =
                    'CONSTRUCTION_SITE_HELD_FILE_CLOSE_FAILED'
                $outcome.FinalPathBindingToken = $null
                $outcome.ArtifactSha256 = $null
                $outcome.ArtifactSizeBytes = $null
                $outcome.HeldFileIdentityObservation = $null
                $outcome.ManifestIdentity = $null
                $outcome.SameStateSignerObservation = $null
            }
        }
        return $outcome
    }

$script:CddsiD027ClaudeDownloadPartialPathValidator =
    [System.Func[string, string, bool]]{
        param(
            [AllowNull()][string]$StagingRootPath,
            [AllowNull()][string]$PartialPath
        )

        try {
            if (
                $StagingRootPath -isnot [string] -or
                $PartialPath -isnot [string] -or
                $StagingRootPath.Length -lt 4 -or
                $StagingRootPath.Length -gt 240 -or
                $PartialPath.Length -lt 24 -or
                $PartialPath.Length -gt 240 -or
                $StagingRootPath.IndexOf([char]0) -ge 0 -or
                $PartialPath.IndexOf([char]0) -ge 0 -or
                $StagingRootPath.Contains('/') -or
                $PartialPath.Contains('/') -or
                $StagingRootPath -cnotmatch '^[A-Za-z]:\\' -or
                $PartialPath -cnotmatch '^[A-Za-z]:\\'
            ) {
                return $false
            }
            $rootFull = [IO.Path]::GetFullPath($StagingRootPath)
            $partialFull = [IO.Path]::GetFullPath($PartialPath)
            if (
                $rootFull -cne $StagingRootPath -or
                $partialFull -cne $PartialPath -or
                [string]::Equals(
                    $rootFull,
                    [IO.Path]::GetPathRoot($rootFull),
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                $rootFull.EndsWith(
                    '\',
                    [StringComparison]::Ordinal
                ) -or
                -not [string]::Equals(
                    [IO.Path]::GetDirectoryName($partialFull),
                    $rootFull,
                    [StringComparison]::OrdinalIgnoreCase
                ) -or
                [IO.Path]::GetFileName($partialFull) -cnotmatch
                    '^claude-[a-f0-9]{16}\.partial$'
            ) {
                return $false
            }
            return $true
        }
        catch {
            return $false
        }
    }

$script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter =
    [System.Func[
        System.IO.Stream,
        string,
        string,
        long,
        System.Threading.CancellationToken,
        object
    ]]{
        param(
            [AllowNull()][System.IO.Stream]$SourceStream,
            [AllowNull()][string]$StagingRootPath,
            [AllowNull()][string]$PartialPath,
            [long]$DeclaredLengthBytes,
            [System.Threading.CancellationToken]$CancellationToken
        )

        $result = [ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-download-body-write-v1'
            Status = 'FAILED'
            ErrorCode = 'INVALID_INPUT'
            PartialCreated = $false
            DurableFlushCompleted = $false
            PartialPathBindingToken = $null
            ArtifactSha256 = $null
            ArtifactSizeBytes = $null
        }
        $partialStream = $null
        $sha = $null
        try {
            if (
                $null -eq $SourceStream -or
                -not $SourceStream.CanRead -or
                -not $script:CddsiD027ClaudeDownloadPartialPathValidator.
                    Invoke($StagingRootPath, $PartialPath) -or
                $DeclaredLengthBytes -lt 64 -or
                $DeclaredLengthBytes -gt
                    $script:CddsiD027ClaudeMsixMaximumBytes
            ) {
                return [pscustomobject]$result
            }
            $result.PartialPathBindingToken =
                Get-CddsiPathBindingToken -Path $PartialPath
            if (
                [System.IO.File]::Exists($PartialPath) -or
                [System.IO.Directory]::Exists($PartialPath)
            ) {
                $result.ErrorCode = 'DOWNLOAD_PARTIAL_EXISTS'
                return [pscustomobject]$result
            }

            $result.ErrorCode = 'DOWNLOAD_PARTIAL_CREATE_FAILED'
            $partialStream = [System.IO.FileStream]::new(
                $PartialPath,
                [System.IO.FileMode]::CreateNew,
                [System.IO.FileAccess]::Write,
                [System.IO.FileShare]::None,
                $script:CddsiD027ClaudeDownloadBufferBytes,
                [System.IO.FileOptions]::WriteThrough
            )
            $result.PartialCreated = $true
            $result.ErrorCode =
                'DOWNLOAD_BODY_HASH_INITIALIZATION_FAILED'
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $buffer =
                New-Object byte[] $script:CddsiD027ClaudeDownloadBufferBytes
            [long]$total = 0
            while ($true) {
                $result.ErrorCode = 'DOWNLOAD_BODY_CANCELLED'
                $CancellationToken.ThrowIfCancellationRequested()
                $result.ErrorCode = 'DOWNLOAD_BODY_READ_FAILED'
                $read = $SourceStream.ReadAsync(
                    $buffer,
                    0,
                    $buffer.Length,
                    $CancellationToken
                ).GetAwaiter().GetResult()
                if ($read -le 0) {
                    break
                }
                if (
                    $total + [long]$read -gt
                        $DeclaredLengthBytes
                ) {
                    $result.ErrorCode =
                        'DOWNLOAD_BODY_EXCEEDED_DECLARED_LENGTH'
                    throw 'Download body exceeded its declared length.'
                }
                $result.ErrorCode = 'DOWNLOAD_BODY_WRITE_FAILED'
                $partialStream.Write($buffer, 0, $read)
                $result.ErrorCode = 'DOWNLOAD_BODY_HASH_UPDATE_FAILED'
                [void]$sha.TransformBlock(
                    $buffer,
                    0,
                    $read,
                    $buffer,
                    0
                )
                $total += [long]$read
            }
            if ($total -ne $DeclaredLengthBytes) {
                $result.ErrorCode = 'DOWNLOAD_BODY_TRUNCATED'
                throw 'Download body was truncated.'
            }
            $result.ErrorCode = 'DOWNLOAD_BODY_HASH_FAILED'
            [void]$sha.TransformFinalBlock(
                (New-Object byte[] 0),
                0,
                0
            )
            $artifactSha256 = [BitConverter]::ToString(
                $sha.Hash
            ).Replace('-', '').ToLowerInvariant()
            if (
                $artifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
                $artifactSha256 -cmatch '^0{64}$'
            ) {
                throw 'Download body hash was invalid.'
            }
            $result.ErrorCode = 'DOWNLOAD_BODY_DURABLE_FLUSH_FAILED'
            $partialStream.Flush($true)
            $result.DurableFlushCompleted = $true
            $result.ArtifactSha256 = $artifactSha256
            $result.ArtifactSizeBytes = $total
            $result.Status = 'COMPLETED'
            $result.ErrorCode = ''
        }
        catch {
            # Raw exception data and local paths are intentionally discarded.
        }
        finally {
            $cleanupFailed = $false
            if ($null -ne $sha) {
                try {
                    $sha.Dispose()
                }
                catch {
                    $cleanupFailed = $true
                }
            }
            if ($null -ne $partialStream) {
                try {
                    $partialStream.Dispose()
                }
                catch {
                    $cleanupFailed = $true
                }
            }
            if ($cleanupFailed) {
                $result.Status = 'FAILED'
                $result.ErrorCode =
                    'DOWNLOAD_BODY_CLEANUP_FAILED'
                $result.DurableFlushCompleted = $false
                $result.ArtifactSha256 = $null
                $result.ArtifactSizeBytes = $null
            }
        }
        return [pscustomobject]$result
    }

function New-CddsiD027ClaudeDesktopSourceDescriptor {
    [CmdletBinding()]
    param()

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion              = 1
        DescriptorId               = 'claude-desktop-standard-x64-latest'
        ArtifactType               = 'ClaudeDesktopMsix'
        SourcePolicy               = 'anthropic_official_only'
        SourceUri                  = $script:CddsiD027ClaudeStandardX64SourceUri
        SourceUriBindingToken      = Get-CddsiSourceUriBindingToken `
            -SourceUri $script:CddsiD027ClaudeStandardX64SourceUri
        ReleaseVersion             = $null
        Architecture               = 'x64'
        Channel                    = 'Standard'
        FileNameToken              = '<ARTIFACT_FILE:CLAUDE_X64_STANDARD_MSIX>'
        ExpectedArtifactSha256     = $null
        ExpectedArtifactSizeBytes  = $null
        ExpectedSignerThumbprint   = $null
        ExpectedSignerSubjectToken = $null
        ExpectedPublisherToken     = $null
        ExpectedIdentityToken      = $null
        RedirectPolicy             = 'same-owner-https-only'
        MaximumBytes               = $script:CddsiD027ClaudeMsixMaximumBytes
        MetadataStatus             = 'UNRESOLVED'
    }
    $values = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $values[$property.Name] = $property.Value
    }
    $values['MetadataBindingToken'] =
        Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $descriptor = [pscustomobject]$values
    if (-not (Test-CddsiArtifactDescriptor `
        -Descriptor $descriptor `
        -ExpectedArtifactType ClaudeDesktopMsix)) {
        throw 'D-027 Claude Desktop source descriptor failed its exact unresolved contract.'
    }
    return $descriptor
}

function Test-CddsiD027ClaudeDesktopSourceDescriptor {
    [CmdletBinding()]
    param(
        [AllowNull()]$Descriptor
    )

    try {
        $expected = New-CddsiD027ClaudeDesktopSourceDescriptor
        $expectedNames = @(
            $expected.PSObject.Properties |
                ForEach-Object { [string]$_.Name }
        )
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Descriptor `
                -Expected $expectedNames)
        ) {
            return $false
        }
        foreach ($name in $expectedNames) {
            $expectedValue = $expected.$name
            $actualValue = $Descriptor.$name
            if ($null -eq $expectedValue) {
                if ($null -ne $actualValue) {
                    return $false
                }
                continue
            }
            if (
                $null -eq $actualValue -or
                $actualValue.GetType() -ne $expectedValue.GetType()
            ) {
                return $false
            }
            if ($expectedValue -is [string]) {
                if ($actualValue -cne $expectedValue) {
                    return $false
                }
            }
            elseif ($actualValue -ne $expectedValue) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-CddsiD027ClaudeSanitizedDownloadUri {
    [CmdletBinding()]
    param(
        [AllowNull()]$SourceUri
    )

    $uri = $null
    if (
        $SourceUri -isnot [string] -or
        $SourceUri.Length -lt 16 -or
        $SourceUri.Length -gt 2048 -or
        -not [Uri]::TryCreate(
            $SourceUri,
            [UriKind]::Absolute,
            [ref]$uri
        ) -or
        $uri.Scheme -cne 'https' -or
        -not $uri.IsDefaultPort -or
        $SourceUri -cne $uri.AbsoluteUri -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment) -or
        $uri.DnsSafeHost.ToLowerInvariant() -cne 'downloads.claude.ai'
    ) {
        return $false
    }
    $path = $uri.AbsolutePath
    $contradictorySegmentPattern =
        '(?i)(?:^|[._~-])(?:arm64|aarch64|x86|ia32|offline)(?:[._~-]|$)'
    if (
        $path.Length -lt 7 -or
        $path.Length -gt 1024 -or
        $path.Contains('\') -or
        $path.Contains('//') -or
        $path.Contains('%') -or
        @(
            $path.Split('/') |
                Where-Object { $_ -in @('.', '..') }
        ).Count -gt 0 -or
        @(
            $path.Split('/') |
                Where-Object {
                    $_ -match $contradictorySegmentPattern
                }
        ).Count -gt 0
    ) {
        return $false
    }
    return [regex]::IsMatch(
        $path,
        '^/[A-Za-z0-9._~/-]+\.msix$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
}

function ConvertTo-CddsiD027ClaudeSanitizedTransportUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TransportUri
    )

    try {
        $uri = $null
        if (
            $TransportUri.Length -lt 16 -or
            $TransportUri.Length -gt 12288 -or
            [regex]::IsMatch(
                $TransportUri,
                '[\p{Cc}\p{Z}]',
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            ) -or
            $TransportUri.Contains('\') -or
            -not [Uri]::TryCreate(
                $TransportUri,
                [UriKind]::Absolute,
                [ref]$uri
            ) -or
            $uri.Scheme -cne 'https' -or
            -not $uri.IsDefaultPort -or
            -not [string]::IsNullOrEmpty($uri.UserInfo) -or
            -not [string]::IsNullOrEmpty($uri.Fragment) -or
            $uri.DnsSafeHost.ToLowerInvariant() -cne
                'downloads.claude.ai'
        ) {
            throw 'invalid'
        }
        $sanitized = $uri.GetLeftPart([UriPartial]::Path)
        $queryIndex = $TransportUri.IndexOf(
            '?',
            [StringComparison]::Ordinal
        )
        $rawProjection = if ($queryIndex -ge 0) {
            $TransportUri.Substring(0, $queryIndex)
        }
        else {
            $TransportUri
        }
        if (
            $rawProjection -cne $sanitized -or
            -not [regex]::IsMatch(
                $uri.AbsolutePath,
                $script:CddsiD027ClaudeTransportPathPattern,
                [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
            ) -or
            -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                -SourceUri $sanitized)
        ) {
            throw 'invalid'
        }
        return $sanitized
    }
    catch {
        throw 'Claude transport URI was not an allowed official download target.'
    }
}

function Get-CddsiD027ClaudeTransportHeaderBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Observation
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeDownloadTransportObservationFieldNames |
            Where-Object { $_ -cne 'HeaderObservationBindingToken' }
    )
    $validNames = (
        (Test-CddsiExactPropertySet `
            -InputObject $Observation `
            -Expected $withoutBinding) -or
        (Test-CddsiExactPropertySet `
            -InputObject $Observation `
            -Expected `
                $script:CddsiD027ClaudeDownloadTransportObservationFieldNames)
    )
    if (-not $validNames) {
        throw 'Claude transport header observation did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    $canonical.Add(
        'cddsi-d027-claude-transport-header-observation-binding-v1'
    )
    foreach ($name in $withoutBinding) {
        $value = $Observation.$name
        if ($value -is [string]) {
            $type = 's'
            $text = $value
        }
        elseif ($value -is [bool]) {
            $type = 'b'
            $text = if ($value) { 'true' } else { 'false' }
        }
        elseif ($value -is [int] -or $value -is [long]) {
            $type = 'i'
            $text = [Convert]::ToString(
                [long]$value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        else {
            throw 'Claude transport header observation contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}:{2}={3}:{4}' -f
                $type.Length,
                $type,
                $name.Length,
                $name,
                $text.Length) +
            ':' + $text
        )
    }
    return Get-CddsiSupplyChainTextBindingToken `
        -Text ($canonical -join "`n")
}

function Test-CddsiD027ClaudeTransportHeaderObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor
    )

    try {
        if (
            $null -eq $Observation -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $Observation `
                -Expected `
                    $script:CddsiD027ClaudeDownloadTransportObservationFieldNames) -or
            -not (Test-CddsiD027ClaudeDesktopSourceDescriptor `
                -Descriptor $ArtifactDescriptor) -or
            -not (Test-CddsiSchemaVersionOne `
                -Value $Observation.SchemaVersion) -or
            $Observation.ContractVersion -isnot [string] -or
            $Observation.ContractVersion -cne
                'cddsi-d027-claude-transport-header-observation-v1' -or
            $Observation.TransportState -isnot [string] -or
            $Observation.TransportState -cne
                'HEADERS_ACCEPTED_BODY_UNVERIFIED' -or
            $Observation.ArtifactProfile -isnot [string] -or
            $Observation.ArtifactProfile -cne 'VmAcceptance' -or
            $Observation.ArtifactType -isnot [string] -or
            $Observation.ArtifactType -cne 'ClaudeDesktopMsix' -or
            $Observation.DescriptorId -isnot [string] -or
            $Observation.DescriptorId -cne
                $ArtifactDescriptor.DescriptorId -or
            $Observation.SourceDescriptorBindingToken -isnot [string] -or
            $Observation.SourceDescriptorBindingToken -cne
                $ArtifactDescriptor.MetadataBindingToken -or
            $Observation.RequestUriBindingToken -isnot [string] -or
            $Observation.RequestUriBindingToken -cne
                $ArtifactDescriptor.SourceUriBindingToken -or
            $Observation.RequestMethod -isnot [string] -or
            $Observation.RequestMethod -cne 'GET' -or
            $Observation.ContentTypeMediaType -isnot [string] -or
            $Observation.ContentTypeMediaType -cne
                'application/octet-stream' -or
            $Observation.SanitizedFinalUri -isnot [string] -or
            (ConvertTo-CddsiD027ClaudeSanitizedTransportUri `
                -TransportUri $Observation.SanitizedFinalUri) -cne
                    $Observation.SanitizedFinalUri -or
            $Observation.SanitizedFinalUriBindingToken -isnot [string] -or
            $Observation.SanitizedFinalUriBindingToken -cne
                (Get-CddsiSourceUriBindingToken `
                    -SourceUri $Observation.SanitizedFinalUri) -or
            (($Observation.InitialStatusCode -isnot [int]) -and
                ($Observation.InitialStatusCode -isnot [long])) -or
            [long]$Observation.InitialStatusCode -ne 307 -or
            (($Observation.RedirectCount -isnot [int]) -and
                ($Observation.RedirectCount -isnot [long])) -or
            [long]$Observation.RedirectCount -ne 1 -or
            (($Observation.FinalStatusCode -isnot [int]) -and
                ($Observation.FinalStatusCode -isnot [long])) -or
            [long]$Observation.FinalStatusCode -ne 200 -or
            (($Observation.ContentEncodingCount -isnot [int]) -and
                ($Observation.ContentEncodingCount -isnot [long])) -or
            [long]$Observation.ContentEncodingCount -ne 0 -or
            (($Observation.TransferEncodingCount -isnot [int]) -and
                ($Observation.TransferEncodingCount -isnot [long])) -or
            [long]$Observation.TransferEncodingCount -ne 0 -or
            (($Observation.DeclaredContentLengthBytes -isnot [int]) -and
                ($Observation.DeclaredContentLengthBytes -isnot [long])) -or
            [long]$Observation.DeclaredContentLengthBytes -lt
                $script:CddsiD027ClaudeMsixMinimumBytes -or
            [long]$Observation.DeclaredContentLengthBytes -gt
                [long]$ArtifactDescriptor.MaximumBytes -or
            $Observation.HeaderObservationBindingToken -isnot [string] -or
            $Observation.HeaderObservationBindingToken -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Observation.HeaderObservationBindingToken -cmatch
                '^0{64}$' -or
            $Observation.HeaderObservationBindingToken -cne
                (Get-CddsiD027ClaudeTransportHeaderBindingToken `
                    -Observation $Observation)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function New-CddsiD027ClaudeTransportHeaderObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$HeaderFacts
    )

    try {
        if (
            -not (Test-CddsiD027ClaudeDesktopSourceDescriptor `
                -Descriptor $ArtifactDescriptor) -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $HeaderFacts `
                -Expected `
                    $script:CddsiD027ClaudeDownloadTransportFactFieldNames) -or
            -not (Test-CddsiSchemaVersionOne `
                -Value $HeaderFacts.SchemaVersion) -or
            $HeaderFacts.ContractVersion -isnot [string] -or
            $HeaderFacts.ContractVersion -cne
                'cddsi-d027-claude-transport-header-facts-v1'
        ) {
            throw 'invalid'
        }
        foreach ($name in @(
            'InitialStatusCode',
            'RedirectCount',
            'RedirectLocationHeaderCount',
            'RedirectContentTypeHeaderCount',
            'RedirectContentEncodingCount',
            'RedirectTransferEncodingCount',
            'RedirectContentLengthHeaderCount',
            'RedirectContentLengthBytes',
            'FinalStatusCode',
            'FinalLocationHeaderCount',
            'FinalContentTypeHeaderCount',
            'FinalContentTypeParameterCount',
            'FinalContentEncodingCount',
            'FinalTransferEncodingCount',
            'FinalContentLengthHeaderCount',
            'FinalContentLengthBytes'
        )) {
            $value = $HeaderFacts.$name
            if ($value -isnot [int] -and $value -isnot [long]) {
                throw 'invalid'
            }
        }
        if (
            $HeaderFacts.InitialRequestMethod -isnot [string] -or
            $HeaderFacts.InitialRequestMethod -cne 'GET' -or
            $HeaderFacts.InitialRequestUri -isnot [string] -or
            $HeaderFacts.InitialRequestUri -cne
                $ArtifactDescriptor.SourceUri -or
            [long]$HeaderFacts.InitialStatusCode -ne 307 -or
            [long]$HeaderFacts.RedirectCount -ne 1 -or
            [long]$HeaderFacts.RedirectLocationHeaderCount -ne 1 -or
            $HeaderFacts.RedirectTargetTransportUri -isnot [string] -or
            $HeaderFacts.FinalRequestMethod -isnot [string] -or
            $HeaderFacts.FinalRequestMethod -cne 'GET' -or
            $HeaderFacts.FinalRequestTransportUri -isnot [string] -or
            -not [string]::Equals(
                $HeaderFacts.RedirectTargetTransportUri,
                $HeaderFacts.FinalRequestTransportUri,
                [StringComparison]::Ordinal
            ) -or
            [long]$HeaderFacts.RedirectContentTypeHeaderCount -ne 0 -or
            [long]$HeaderFacts.RedirectContentEncodingCount -ne 0 -or
            [long]$HeaderFacts.RedirectTransferEncodingCount -ne 0 -or
            -not (
                (
                    [long]$HeaderFacts.RedirectContentLengthHeaderCount -eq
                        0 -and
                    [long]$HeaderFacts.RedirectContentLengthBytes -eq -1
                ) -or
                (
                    [long]$HeaderFacts.RedirectContentLengthHeaderCount -eq
                        1 -and
                    [long]$HeaderFacts.RedirectContentLengthBytes -eq 0
                )
            ) -or
            [long]$HeaderFacts.FinalStatusCode -ne 200 -or
            [long]$HeaderFacts.FinalLocationHeaderCount -ne 0 -or
            [long]$HeaderFacts.FinalContentTypeHeaderCount -ne 1 -or
            $HeaderFacts.FinalContentTypeMediaType -isnot [string] -or
            $HeaderFacts.FinalContentTypeMediaType -cne
                'application/octet-stream' -or
            [long]$HeaderFacts.FinalContentTypeParameterCount -ne 0 -or
            [long]$HeaderFacts.FinalContentEncodingCount -ne 0 -or
            [long]$HeaderFacts.FinalTransferEncodingCount -ne 0 -or
            [long]$HeaderFacts.FinalContentLengthHeaderCount -ne 1 -or
            [long]$HeaderFacts.FinalContentLengthBytes -lt
                $script:CddsiD027ClaudeMsixMinimumBytes -or
            [long]$HeaderFacts.FinalContentLengthBytes -gt
                [long]$ArtifactDescriptor.MaximumBytes
        ) {
            throw 'invalid'
        }

        $sanitizedRedirect =
            ConvertTo-CddsiD027ClaudeSanitizedTransportUri `
                -TransportUri $HeaderFacts.RedirectTargetTransportUri
        $sanitizedFinal =
            ConvertTo-CddsiD027ClaudeSanitizedTransportUri `
                -TransportUri $HeaderFacts.FinalRequestTransportUri
        if ($sanitizedRedirect -cne $sanitizedFinal) {
            throw 'invalid'
        }

        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-transport-header-observation-v1'
            TransportState = 'HEADERS_ACCEPTED_BODY_UNVERIFIED'
            ArtifactProfile = 'VmAcceptance'
            ArtifactType = 'ClaudeDesktopMsix'
            DescriptorId = $ArtifactDescriptor.DescriptorId
            SourceDescriptorBindingToken =
                $ArtifactDescriptor.MetadataBindingToken
            RequestUriBindingToken =
                $ArtifactDescriptor.SourceUriBindingToken
            RequestMethod = 'GET'
            InitialStatusCode = [long]307
            SanitizedFinalUri = $sanitizedFinal
            SanitizedFinalUriBindingToken =
                Get-CddsiSourceUriBindingToken `
                    -SourceUri $sanitizedFinal
            RedirectCount = [long]1
            FinalStatusCode = [long]200
            ContentTypeMediaType = 'application/octet-stream'
            ContentEncodingCount = [long]0
            TransferEncodingCount = [long]0
            DeclaredContentLengthBytes =
                [long]$HeaderFacts.FinalContentLengthBytes
        }
        $values = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) {
            $values[$property.Name] = $property.Value
        }
        $values['HeaderObservationBindingToken'] =
            Get-CddsiD027ClaudeTransportHeaderBindingToken `
                -Observation $withoutBinding
        $result = [pscustomobject]$values
        if (-not (Test-CddsiD027ClaudeTransportHeaderObservation `
            -Observation $result `
            -ArtifactDescriptor $ArtifactDescriptor)) {
            throw 'invalid'
        }
        return $result
    }
    catch {
        throw 'Claude transport header facts were not accepted.'
    }
}

function Test-CddsiD027ClaudeDownloadDestinationPath {
    [CmdletBinding()]
    param(
        [AllowNull()]$StagingRootPath,
        [AllowNull()]$DestinationPath
    )

    try {
        if (
            $StagingRootPath -isnot [string] -or
            $DestinationPath -isnot [string] -or
            $StagingRootPath.Length -lt 4 -or
            $StagingRootPath.Length -gt 32767 -or
            $DestinationPath.Length -lt 8 -or
            $DestinationPath.Length -gt 32767 -or
            $StagingRootPath.IndexOf([char]0) -ge 0 -or
            $DestinationPath.IndexOf([char]0) -ge 0 -or
            $StagingRootPath.Contains('/') -or
            $DestinationPath.Contains('/') -or
            $StagingRootPath -cnotmatch '^[A-Za-z]:\\' -or
            $DestinationPath -cnotmatch '^[A-Za-z]:\\'
        ) {
            return $false
        }

        $rootFull = [IO.Path]::GetFullPath($StagingRootPath)
        $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
        $rootPath = [IO.Path]::GetPathRoot($rootFull)
        $destinationRoot = [IO.Path]::GetPathRoot($destinationFull)
        if (
            $rootFull -cne $StagingRootPath -or
            $destinationFull -cne $DestinationPath -or
            $rootPath -cnotmatch '^[A-Za-z]:\\$' -or
            $destinationRoot -cnotmatch '^[A-Za-z]:\\$' -or
            -not [string]::Equals(
                $rootPath,
                $destinationRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            [string]::Equals(
                $rootFull,
                $rootPath,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            $rootFull.EndsWith('\', [StringComparison]::Ordinal) -or
            $rootFull.Substring(2).Contains(':') -or
            $destinationFull.Substring(2).Contains(':') -or
            -not [string]::Equals(
                [IO.Path]::GetDirectoryName($destinationFull),
                $rootFull,
                [StringComparison]::OrdinalIgnoreCase
            )
        ) {
            return $false
        }

        foreach ($segment in @($rootFull.Substring(3).Split('\'))) {
            $deviceBase = @($segment.Split('.'))[0].
                TrimEnd([char[]]' .')
            if (
                [string]::IsNullOrWhiteSpace($segment) -or
                $segment.IndexOfAny(
                    [IO.Path]::GetInvalidFileNameChars()
                ) -ge 0 -or
                $segment.EndsWith(
                    '.',
                    [StringComparison]::Ordinal
                ) -or
                $segment.EndsWith(
                    ' ',
                    [StringComparison]::Ordinal
                ) -or
                $deviceBase -match
                    '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|' +
                    'COM(?:[1-9]|\u00b9|\u00b2|\u00b3)|' +
                    'LPT(?:[1-9]|\u00b9|\u00b2|\u00b3))$'
            ) {
                return $false
            }
        }

        $leafName = [IO.Path]::GetFileName($destinationFull)
        $leafDeviceBase = @($leafName.Split('.'))[0].
            TrimEnd([char[]]' .')
        return (
            $leafName -cmatch '^[A-Za-z0-9._~-]+\.msix$' -and
            $leafDeviceBase -notmatch
                '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|' +
                'COM(?:[1-9]|\u00b9|\u00b2|\u00b3)|' +
                'LPT(?:[1-9]|\u00b9|\u00b2|\u00b3))$' -and
            $leafName -cnotmatch
                '(?i)(?:^|[._~-])(?:arm64|aarch64|x86|ia32|offline)(?:[._~-]|$)'
        )
    }
    catch {
        return $false
    }
}

function Get-CddsiD027ClaudeDownloadReceiptBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeDownloadReceiptFieldNames |
            Where-Object { $_ -cne 'ReceiptBindingToken' }
    )
    $validNames = (
        (Test-CddsiExactPropertySet `
            -InputObject $Receipt `
            -Expected $withoutBinding) -or
        (Test-CddsiExactPropertySet `
            -InputObject $Receipt `
            -Expected $script:CddsiD027ClaudeDownloadReceiptFieldNames)
    )
    if (-not $validNames) {
        throw 'Claude download receipt did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    foreach ($name in $withoutBinding) {
        if ($name -ceq 'SanitizedRedirectUris') {
            $redirects = @($Receipt.SanitizedRedirectUris)
            $canonical.Add(
                ('{0}:{1}={2}' -f $name.Length, $name, $redirects.Count)
            )
            for ($index = 0; $index -lt $redirects.Count; $index++) {
                if ($redirects[$index] -isnot [string]) {
                    throw 'Claude download receipt redirect value was invalid.'
                }
                $text = [string]$redirects[$index]
                $canonical.Add(
                    (
                        'Redirect[{0}]={1}:{2}' -f
                            $index,
                            $text.Length,
                            $text
                    )
                )
            }
            continue
        }
        $value = $Receipt.$name
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
            throw 'Claude download receipt contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text)
        )
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Get-CddsiD027ClaudeFileIdentityToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FinalPathBindingToken,
        [Parameter(Mandatory = $true)][string]$VolumeSerialNumberHex,
        [Parameter(Mandatory = $true)][string]$FileIndexHex,
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ArtifactSizeBytes
    )

    if (
        $FinalPathBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
        $FinalPathBindingToken -cmatch '^0{64}$' -or
        $VolumeSerialNumberHex -cnotmatch '^[0-9A-F]{8}$' -or
        $VolumeSerialNumberHex -ceq '00000000' -or
        $FileIndexHex -cnotmatch '^[0-9A-F]{16}$' -or
        $FileIndexHex -ceq '0000000000000000' -or
        $ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactSha256 -cmatch '^0{64}$' -or
        $ArtifactSizeBytes -lt 1 -or
        $ArtifactSizeBytes -gt $script:CddsiD027ClaudeMsixMaximumBytes
    ) {
        throw 'Claude held-file identity fields were invalid.'
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-d027-claude-held-file-identity-v1'
        ('FinalPathBindingToken={0}' -f $FinalPathBindingToken)
        ('VolumeSerialNumberHex={0}' -f $VolumeSerialNumberHex)
        ('FileIndexHex={0}' -f $FileIndexHex)
        'FileSystemName=NTFS'
        'NumberOfLinks=1'
        'IsDirectory=false'
        'IsReparsePoint=false'
        ('ArtifactSha256={0}' -f $ArtifactSha256)
        (
            'ArtifactSizeBytes={0}' -f
                [Convert]::ToString(
                    $ArtifactSizeBytes,
                    [Globalization.CultureInfo]::InvariantCulture
                )
        )
    ) -join "`n")
}

function Get-CddsiD027ClaudeContentBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ArtifactSizeBytes
    )

    if (
        $ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactSha256 -cmatch '^0{64}$' -or
        $ArtifactSizeBytes -lt 1 -or
        $ArtifactSizeBytes -gt $script:CddsiD027ClaudeMsixMaximumBytes
    ) {
        throw 'Claude content binding fields were invalid.'
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-d027-claude-content-v1'
        'ArtifactType=ClaudeDesktopMsix'
        ('ArtifactSha256={0}' -f $ArtifactSha256)
        (
            'ArtifactSizeBytes={0}' -f
                [Convert]::ToString(
                    $ArtifactSizeBytes,
                    [Globalization.CultureInfo]::InvariantCulture
                )
        )
    ) -join "`n")
}

function New-CddsiD027ClaudeDownloadReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$StagingRootPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$FileIdentityToken,
        [Parameter(Mandatory = $true)][string[]]$SanitizedRedirectUris,
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ArtifactSizeBytes,
        [Parameter(Mandatory = $true)][string]$ObservedAtUtc
    )

    $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
    if (
        -not (Test-CddsiCanonicalUuidValue -Value $RunId) -or
        -not (Test-CddsiD027ClaudeDownloadDestinationPath `
            -StagingRootPath $StagingRootPath `
            -DestinationPath $DestinationPath) -or
        $FileIdentityToken -cnotmatch '^[a-f0-9]{64}$' -or
        $FileIdentityToken -cmatch '^0{64}$' -or
        $ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactSha256 -cmatch '^0{64}$' -or
        $ArtifactSizeBytes -lt 1 -or
        $ArtifactSizeBytes -gt [long]$descriptor.MaximumBytes -or
        $ObservedAtUtc -notmatch
            '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
        -not (Test-CddsiUtcTimestampValue -Value $ObservedAtUtc) -or
        $null -eq $SanitizedRedirectUris -or
        $SanitizedRedirectUris.Count -lt 1 -or
        $SanitizedRedirectUris.Count -gt 5
    ) {
        throw 'Claude download receipt inputs were invalid.'
    }
    foreach ($redirectUri in $SanitizedRedirectUris) {
        if (
            -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                -SourceUri $redirectUri)
        ) {
            throw 'Claude download receipt contained an invalid sanitized redirect.'
        }
    }
    if (
        @($SanitizedRedirectUris | Sort-Object -Unique).Count -ne
            $SanitizedRedirectUris.Count
    ) {
        throw 'Claude download receipt redirect chain contained a loop.'
    }

    $requestUriBindingToken =
        Get-CddsiSourceUriBindingToken -SourceUri $descriptor.SourceUri
    $redirectCanonical = New-Object System.Collections.Generic.List[string]
    $redirectCanonical.Add('cddsi-d027-claude-redirect-chain-v1')
    $redirectCanonical.Add(('RequestUri={0}' -f $descriptor.SourceUri))
    for ($index = 0; $index -lt $SanitizedRedirectUris.Count; $index++) {
        $redirectCanonical.Add(
            ('Redirect[{0}]={1}' -f $index, $SanitizedRedirectUris[$index])
        )
    }
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-d027-claude-download-receipt-v1'
        ArtifactState = 'DOWNLOADED_UNVERIFIED'
        RunId = $RunId
        ArtifactProfile = 'VmAcceptance'
        ArtifactType = 'ClaudeDesktopMsix'
        DescriptorId = $descriptor.DescriptorId
        SourceDescriptorBindingToken = $descriptor.MetadataBindingToken
        RequestUri = $descriptor.SourceUri
        RequestUriBindingToken = $requestUriBindingToken
        SanitizedFinalUri =
            $SanitizedRedirectUris[$SanitizedRedirectUris.Count - 1]
        SanitizedRedirectUris = [string[]]@($SanitizedRedirectUris)
        RedirectChainBindingToken =
            Get-CddsiSupplyChainTextBindingToken `
                -Text ($redirectCanonical -join "`n")
        RedirectCount = [long]$SanitizedRedirectUris.Count
        StagingRootPathBindingToken =
            Get-CddsiPathBindingToken -Path $StagingRootPath
        DestinationPathBindingToken =
            Get-CddsiPathBindingToken -Path $DestinationPath
        FileIdentityToken = $FileIdentityToken
        ArtifactSha256 = $ArtifactSha256
        ArtifactSizeBytes = [long]$ArtifactSizeBytes
        ContentBindingToken =
            Get-CddsiD027ClaudeContentBindingToken `
                -ArtifactSha256 $ArtifactSha256 `
                -ArtifactSizeBytes $ArtifactSizeBytes
        ObservedAtUtc = $ObservedAtUtc
    }
    $values = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $values[$property.Name] = $property.Value
    }
    $values['ReceiptBindingToken'] =
        Get-CddsiD027ClaudeDownloadReceiptBindingToken `
            -Receipt $withoutBinding
    return [pscustomobject]$values
}

function Test-CddsiD027ClaudeDownloadReceipt {
    [CmdletBinding()]
    param(
        [AllowNull()]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedStagingRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ExpectedFileIdentityToken,
        [Parameter(Mandatory = $true)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedArtifactSizeBytes,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Receipt `
                -Expected $script:CddsiD027ClaudeDownloadReceiptFieldNames) -or
            -not (Test-CddsiSchemaVersionOne -Value $Receipt.SchemaVersion) -or
            $Receipt.ContractVersion -isnot [string] -or
            $Receipt.ContractVersion -cne
                'cddsi-d027-claude-download-receipt-v1' -or
            $Receipt.ArtifactState -isnot [string] -or
            $Receipt.ArtifactState -cne 'DOWNLOADED_UNVERIFIED' -or
            -not (Test-CddsiCanonicalUuidValue -Value $ExpectedRunId) -or
            $Receipt.RunId -isnot [string] -or
            $Receipt.RunId -cne $ExpectedRunId -or
            $Receipt.ArtifactProfile -isnot [string] -or
            $Receipt.ArtifactProfile -cne 'VmAcceptance' -or
            $Receipt.ArtifactType -isnot [string] -or
            $Receipt.ArtifactType -cne 'ClaudeDesktopMsix' -or
            $Receipt.DescriptorId -isnot [string] -or
            $Receipt.DescriptorId -cne $descriptor.DescriptorId -or
            $Receipt.SourceDescriptorBindingToken -isnot [string] -or
            $Receipt.SourceDescriptorBindingToken -cne
                $descriptor.MetadataBindingToken -or
            $Receipt.RequestUri -isnot [string] -or
            $Receipt.RequestUri -cne $descriptor.SourceUri -or
            $Receipt.RequestUriBindingToken -isnot [string] -or
            $Receipt.RequestUriBindingToken -cne
                $descriptor.SourceUriBindingToken -or
            $Receipt.SanitizedRedirectUris -isnot [System.Array] -or
            -not (Test-CddsiD027ClaudeDownloadDestinationPath `
                -StagingRootPath $ExpectedStagingRootPath `
                -DestinationPath $ExpectedDestinationPath) -or
            $ExpectedFileIdentityToken -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedFileIdentityToken -cmatch '^0{64}$' -or
            $Receipt.FileIdentityToken -isnot [string] -or
            $Receipt.FileIdentityToken -cne $ExpectedFileIdentityToken -or
            $ExpectedArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedArtifactSha256 -cmatch '^0{64}$' -or
            $Receipt.ArtifactSha256 -isnot [string] -or
            $Receipt.ArtifactSha256 -cne $ExpectedArtifactSha256 -or
            $ExpectedArtifactSizeBytes -lt 1 -or
            $ExpectedArtifactSizeBytes -gt [long]$descriptor.MaximumBytes -or
            (($Receipt.ArtifactSizeBytes -isnot [int]) -and
                ($Receipt.ArtifactSizeBytes -isnot [long])) -or
            [long]$Receipt.ArtifactSizeBytes -ne
                $ExpectedArtifactSizeBytes -or
            $Receipt.ContentBindingToken -isnot [string] -or
            $Receipt.ContentBindingToken -cne
                (Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $ExpectedArtifactSha256 `
                    -ArtifactSizeBytes $ExpectedArtifactSizeBytes) -or
            (($Receipt.RedirectCount -isnot [int]) -and
                ($Receipt.RedirectCount -isnot [long])) -or
            [long]$Receipt.RedirectCount -lt 1 -or
            [long]$Receipt.RedirectCount -gt 5 -or
            $Receipt.SanitizedFinalUri -isnot [string] -or
            -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                -SourceUri $Receipt.SanitizedFinalUri)
        ) {
            return $false
        }

        $redirects = @($Receipt.SanitizedRedirectUris)
        if (
            $redirects.Count -ne [long]$Receipt.RedirectCount -or
            $Receipt.SanitizedFinalUri -cne
                $redirects[$redirects.Count - 1]
        ) {
            return $false
        }
        foreach ($redirectUri in $redirects) {
            if (
                $redirectUri -isnot [string] -or
                -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                    -SourceUri $redirectUri)
            ) {
                return $false
            }
        }
        if (@($redirects | Sort-Object -Unique).Count -ne $redirects.Count) {
            return $false
        }
        $redirectCanonical = New-Object System.Collections.Generic.List[string]
        $redirectCanonical.Add('cddsi-d027-claude-redirect-chain-v1')
        $redirectCanonical.Add(('RequestUri={0}' -f $descriptor.SourceUri))
        for ($index = 0; $index -lt $redirects.Count; $index++) {
            $redirectCanonical.Add(
                ('Redirect[{0}]={1}' -f $index, $redirects[$index])
            )
        }
        if (
            $Receipt.RedirectChainBindingToken -isnot [string] -or
            $Receipt.RedirectChainBindingToken -cne
                (Get-CddsiSupplyChainTextBindingToken `
                    -Text ($redirectCanonical -join "`n")) -or
            $Receipt.StagingRootPathBindingToken -isnot [string] -or
            $Receipt.StagingRootPathBindingToken -cne
                (Get-CddsiPathBindingToken `
                    -Path $ExpectedStagingRootPath) -or
            $Receipt.DestinationPathBindingToken -isnot [string] -or
            $Receipt.DestinationPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath) -or
            $Receipt.ReceiptBindingToken -isnot [string] -or
            $Receipt.ReceiptBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.ReceiptBindingToken -cne
                (Get-CddsiD027ClaudeDownloadReceiptBindingToken `
                    -Receipt $Receipt)
        ) {
            return $false
        }

        foreach ($timestamp in @(
                $Receipt.ObservedAtUtc,
                $ValidationTimeUtc
            )) {
            if (
                $timestamp -isnot [string] -or
                $timestamp -notmatch
                    '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
                -not (Test-CddsiUtcTimestampValue -Value $timestamp)
            ) {
                return $false
            }
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $observedTime = [DateTimeOffset]::ParseExact(
            $Receipt.ObservedAtUtc,
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
            $observedTime -gt $validationTime.AddSeconds(30) -or
            $validationTime -gt $observedTime.AddMinutes(90)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-CddsiD027ClaudeDownloadedArtifactObservation {
    [CmdletBinding()]
    param(
        [AllowNull()]$Observation,
        [AllowNull()]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedStagingRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    # This function validates a pure evidence schema. Only the later Live
    # producer can prove HeldFinalFileHandle by constructing the observation
    # internally while retaining that same handle through downstream use.
    try {
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Observation `
                -Expected `
                    $script:CddsiD027ClaudeHeldArtifactObservationFieldNames) -or
            -not (Test-CddsiSchemaVersionOne `
                -Value $Observation.SchemaVersion) -or
            $Observation.ContractVersion -isnot [string] -or
            $Observation.ContractVersion -cne
                'cddsi-d027-claude-held-artifact-observation-v1' -or
            $Observation.ObservationMethod -isnot [string] -or
            $Observation.ObservationMethod -cne 'HeldFinalFileHandle' -or
            $Observation.FinalPathBindingToken -isnot [string] -or
            $Observation.FinalPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath) -or
            $Observation.FileSystemName -isnot [string] -or
            $Observation.FileSystemName -cne 'NTFS' -or
            (($Observation.NumberOfLinks -isnot [int]) -and
                ($Observation.NumberOfLinks -isnot [long])) -or
            [long]$Observation.NumberOfLinks -ne 1 -or
            $Observation.IsDirectory -isnot [bool] -or
            $Observation.IsDirectory -or
            $Observation.IsReparsePoint -isnot [bool] -or
            $Observation.IsReparsePoint -or
            $Observation.VolumeSerialNumberHex -isnot [string] -or
            $Observation.FileIndexHex -isnot [string] -or
            $Observation.FileIdentityToken -isnot [string] -or
            $Observation.FileIdentityToken -cne
                (Get-CddsiD027ClaudeFileIdentityToken `
                    -FinalPathBindingToken `
                        $Observation.FinalPathBindingToken `
                    -VolumeSerialNumberHex `
                        $Observation.VolumeSerialNumberHex `
                    -FileIndexHex $Observation.FileIndexHex `
                    -ArtifactSha256 $Observation.ArtifactSha256 `
                    -ArtifactSizeBytes `
                        ([long]$Observation.ArtifactSizeBytes)) -or
            $Observation.ArtifactSha256 -isnot [string] -or
            $Observation.ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Observation.ArtifactSha256 -cmatch '^0{64}$' -or
            (($Observation.ArtifactSizeBytes -isnot [int]) -and
                ($Observation.ArtifactSizeBytes -isnot [long])) -or
            $Observation.ObservedAtUtc -isnot [string] -or
            $Observation.ObservedAtUtc -notmatch
                '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
            -not (Test-CddsiUtcTimestampValue `
                -Value $Observation.ObservedAtUtc)
        ) {
            return $false
        }
        if (-not (Test-CddsiD027ClaudeDownloadReceipt `
            -Receipt $Receipt `
            -ExpectedRunId $ExpectedRunId `
            -ExpectedStagingRootPath $ExpectedStagingRootPath `
            -ExpectedDestinationPath $ExpectedDestinationPath `
            -ExpectedFileIdentityToken $Observation.FileIdentityToken `
            -ExpectedArtifactSha256 $Observation.ArtifactSha256 `
            -ExpectedArtifactSizeBytes `
                ([long]$Observation.ArtifactSizeBytes) `
            -ValidationTimeUtc $ValidationTimeUtc)) {
            return $false
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $observationTime = [DateTimeOffset]::ParseExact(
            $Observation.ObservedAtUtc,
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
        $receiptTime = [DateTimeOffset]::ParseExact(
            $Receipt.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        return (
            $observationTime -ge $receiptTime -and
            $observationTime -le $validationTime.AddSeconds(30) -and
            $validationTime -le $observationTime.AddMinutes(5)
        )
    }
    catch {
        return $false
    }
}

function Get-CddsiD027ClaudeManifestBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManifestIdentity
    )

    $sha = $null
    try {
        $withoutBinding = @(
            $script:CddsiD027ClaudeManifestIdentityFieldNames |
                Where-Object { $_ -cne 'ManifestBindingToken' }
        )
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $ManifestIdentity `
                -Expected $withoutBinding) -and
            -not (Test-CddsiExactPropertySet `
                -InputObject $ManifestIdentity `
                -Expected $script:CddsiD027ClaudeManifestIdentityFieldNames)
        ) {
            throw 'Claude manifest identity did not match the exact binding schema.'
        }
        if (
            -not (Test-CddsiSchemaVersionOne `
                -Value $ManifestIdentity.SchemaVersion) -or
            $ManifestIdentity.ContractVersion -isnot [string] -or
            $ManifestIdentity.ContractVersion -cne
                'cddsi-d027-claude-appx-manifest-v1' -or
            $ManifestIdentity.PackageName -isnot [string] -or
            $ManifestIdentity.PackageName -cne 'Claude' -or
            $ManifestIdentity.Publisher -isnot [string] -or
            $ManifestIdentity.Publisher.Length -lt 3 -or
            $ManifestIdentity.Publisher.Length -gt 8192 -or
            $ManifestIdentity.Publisher -match '[\x00-\x1f]' -or
            $ManifestIdentity.PublisherTextSha256 -isnot [string] -or
            $ManifestIdentity.PublisherTextSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $ManifestIdentity.PublisherTextSha256 -cmatch '^0{64}$' -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -isnot
                [string] -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -cmatch
                '^0{64}$' -or
            $ManifestIdentity.PackageVersion -isnot [string] -or
            $ManifestIdentity.Architecture -isnot [string] -or
            $ManifestIdentity.Architecture -cne 'x64' -or
            $ManifestIdentity.ResourceId -isnot [string] -or
            $ManifestIdentity.ResourceId -cne '' -or
            $ManifestIdentity.PackageIdentityBindingToken -isnot [string] -or
            $ManifestIdentity.PackageIdentityBindingToken -cnotmatch
                '^[a-f0-9]{64}$' -or
            $ManifestIdentity.PackageIdentityBindingToken -cmatch '^0{64}$' -or
            $ManifestIdentity.ManifestSha256 -isnot [string] -or
            $ManifestIdentity.ManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ManifestIdentity.ManifestSha256 -cmatch '^0{64}$' -or
            (($ManifestIdentity.ManifestLengthBytes -isnot [int]) -and
                ($ManifestIdentity.ManifestLengthBytes -isnot [long])) -or
            [long]$ManifestIdentity.ManifestLengthBytes -lt 32 -or
            [long]$ManifestIdentity.ManifestLengthBytes -gt
                $script:CddsiD027ClaudeManifestMaximumBytes
        ) {
            throw 'Claude manifest identity values were invalid.'
        }

        $versionMatch = [regex]::Match(
            $ManifestIdentity.PackageVersion,
            '^(?<a>0|[1-9][0-9]{0,4})\.(?<b>0|[1-9][0-9]{0,4})\.(?<c>0|[1-9][0-9]{0,4})\.(?<d>0|[1-9][0-9]{0,4})$',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (-not $versionMatch.Success) {
            throw 'Claude manifest package version was invalid.'
        }
        foreach ($groupName in @('a', 'b', 'c', 'd')) {
            if ([int]::Parse(
                $versionMatch.Groups[$groupName].Value,
                [Globalization.CultureInfo]::InvariantCulture
            ) -gt 65535) {
                throw 'Claude manifest package version exceeded its bound.'
            }
        }

        $distinguishedName =
            New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName(
                $ManifestIdentity.Publisher
            )
        if (
            $null -eq $distinguishedName.RawData -or
            $distinguishedName.RawData.Length -lt 3
        ) {
            throw 'Claude manifest publisher distinguished name was invalid.'
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $publisherTextSha256 = [BitConverter]::ToString(
            $sha.ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $ManifestIdentity.Publisher
                )
            )
        ).Replace('-', '').ToLowerInvariant()
        $publisherParsedX500RawDataSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($distinguishedName.RawData)
        ).Replace('-', '').ToLowerInvariant()
        $packageIdentityBindingToken =
            Get-CddsiSupplyChainTextBindingToken -Text (@(
                'ContractVersion=cddsi-d027-claude-package-identity-v1'
                'Name=Claude'
                ('PublisherTextSha256={0}' -f $publisherTextSha256)
                (
                    'PublisherParsedX500RawDataSha256={0}' -f
                        $publisherParsedX500RawDataSha256
                )
                ('Version={0}' -f $ManifestIdentity.PackageVersion)
                'ProcessorArchitecture=x64'
                'ResourceId='
            ) -join "`n")
        if (
            $ManifestIdentity.PublisherTextSha256 -cne
                $publisherTextSha256 -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -cne
                $publisherParsedX500RawDataSha256 -or
            $ManifestIdentity.PackageIdentityBindingToken -cne
                $packageIdentityBindingToken
        ) {
            throw 'Claude manifest publisher or package identity binding drifted.'
        }

        return Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-d027-claude-manifest-binding-v1'
            ('ManifestSha256={0}' -f $ManifestIdentity.ManifestSha256)
            (
                'ManifestLengthBytes={0}' -f
                    [Convert]::ToString(
                        [long]$ManifestIdentity.ManifestLengthBytes,
                        [Globalization.CultureInfo]::InvariantCulture
                    )
            )
            (
                'PackageIdentityBindingToken={0}' -f
                    $ManifestIdentity.PackageIdentityBindingToken
            )
        ) -join "`n")
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
}

function Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames |
            Where-Object { $_ -cne 'EvidenceBindingToken' }
    )
    if (
        -not (Test-CddsiExactPropertySet `
            -InputObject $Evidence `
            -Expected $withoutBinding) -and
        -not (Test-CddsiExactPropertySet `
            -InputObject $Evidence `
            -Expected $script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames)
    ) {
        throw 'Claude MSIX signature evidence did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    $canonical.Add(
        'cddsi-d027-claude-msix-signature-evidence-binding-v1'
    )
    foreach ($name in $withoutBinding) {
        $value = $Evidence.$name
        $text = if ($value -is [string]) {
            $value
        }
        elseif ($value -is [bool]) {
            $value.ToString().ToLowerInvariant()
        }
        elseif ($value -is [int] -or $value -is [long]) {
            [Convert]::ToString(
                [long]$value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        else {
            throw 'Claude MSIX signature evidence contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text)
        )
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Test-CddsiD027ClaudeMsixSignatureEvidenceContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Evidence,
        [Parameter(Mandatory = $true)][AllowNull()]$ManifestIdentity,
        [Parameter(Mandatory = $true)][AllowNull()]$DownloadReceipt,
        [Parameter(Mandatory = $true)][AllowNull()]$HeldArtifactObservation,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedStagingRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $certificate = $null
    $sha = $null
    try {
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Evidence `
                -Expected `
                    $script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames) -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $ManifestIdentity `
                -Expected $script:CddsiD027ClaudeManifestIdentityFieldNames) -or
            -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
            $Evidence.ContractVersion -isnot [string] -or
            $Evidence.ContractVersion -cne
                'cddsi-d027-claude-msix-signature-evidence-v1' -or
            $Evidence.EvidenceKind -isnot [string] -or
            $Evidence.EvidenceKind -cne 'ClaudeDesktopMsixWinVerifyTrust' -or
            $Evidence.VerificationMethod -isnot [string] -or
            $Evidence.VerificationMethod -cne
                'WinVerifyTrustGenericVerifyV2' -or
            $Evidence.SignerExtractionMethod -isnot [string] -or
            $Evidence.SignerExtractionMethod -cne
                'WinVerifyTrustStateDataPrimarySigner' -or
            $Evidence.StateLifecycle -isnot [string] -or
            $Evidence.StateLifecycle -cne
                'VerifyExtractPrimarySignerClose' -or
            $Evidence.ArtifactProfile -isnot [string] -or
            $Evidence.ArtifactProfile -cne 'VmAcceptance' -or
            $Evidence.ArtifactType -isnot [string] -or
            $Evidence.ArtifactType -cne 'ClaudeDesktopMsix' -or
            $Evidence.WinVerifyTrustTrusted -isnot [bool] -or
            -not $Evidence.WinVerifyTrustTrusted -or
            $Evidence.WinVerifyTrustStatus -isnot [string] -or
            $Evidence.WinVerifyTrustStatus -cne 'Trusted' -or
            $Evidence.WinVerifyTrustNativeStatusHex -isnot [string] -or
            $Evidence.WinVerifyTrustNativeStatusHex -cne '0x00000000' -or
            $Evidence.WinVerifyTrustRevocationMode -isnot [string] -or
            $Evidence.WinVerifyTrustRevocationMode -cne 'NotChecked'
        ) {
            return $false
        }

        $runId = [guid]::Empty
        if (
            $Evidence.RunId -isnot [string] -or
            -not [guid]::TryParse($Evidence.RunId, [ref]$runId) -or
            $runId -eq [guid]::Empty -or
            $Evidence.RunId -cne $runId.ToString('D') -or
            $Evidence.RunId -cne $ExpectedRunId -or
            $Evidence.FinalPathBindingToken -isnot [string] -or
            $Evidence.FinalPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath) -or
            $Evidence.DownloadReceiptBindingToken -isnot [string] -or
            $Evidence.DownloadReceiptBindingToken -cne
                $DownloadReceipt.ReceiptBindingToken -or
            $Evidence.FileIdentityToken -isnot [string] -or
            $Evidence.FileIdentityToken -cne
                $HeldArtifactObservation.FileIdentityToken -or
            $Evidence.ArtifactSha256 -isnot [string] -or
            $Evidence.ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Evidence.ArtifactSha256 -cmatch '^0{64}$' -or
            $Evidence.ArtifactSha256 -cne
                $HeldArtifactObservation.ArtifactSha256 -or
            (($Evidence.ArtifactSizeBytes -isnot [int]) -and
                ($Evidence.ArtifactSizeBytes -isnot [long])) -or
            [long]$Evidence.ArtifactSizeBytes -lt 1 -or
            [long]$Evidence.ArtifactSizeBytes -gt
                $script:CddsiD027ClaudeMsixMaximumBytes -or
            [long]$Evidence.ArtifactSizeBytes -ne
                [long]$HeldArtifactObservation.ArtifactSizeBytes -or
            $Evidence.ContentBindingToken -isnot [string] -or
            $Evidence.ContentBindingToken -cne
                (Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $Evidence.ArtifactSha256 `
                    -ArtifactSizeBytes ([long]$Evidence.ArtifactSizeBytes))
        ) {
            return $false
        }
        if (-not (Test-CddsiD027ClaudeDownloadedArtifactObservation `
            -Observation $HeldArtifactObservation `
            -Receipt $DownloadReceipt `
            -ExpectedRunId $ExpectedRunId `
            -ExpectedStagingRootPath $ExpectedStagingRootPath `
            -ExpectedDestinationPath $ExpectedDestinationPath `
            -ValidationTimeUtc $ValidationTimeUtc)) {
            return $false
        }

        $manifestBindingToken =
            Get-CddsiD027ClaudeManifestBindingToken `
                -ManifestIdentity $ManifestIdentity
        if (
            $ManifestIdentity.ManifestBindingToken -isnot [string] -or
            $ManifestIdentity.ManifestBindingToken -cne
                $manifestBindingToken -or
            $Evidence.ManifestBindingToken -isnot [string] -or
            $Evidence.ManifestBindingToken -cne $manifestBindingToken -or
            $Evidence.PackageIdentityBindingToken -isnot [string] -or
            $Evidence.PackageIdentityBindingToken -cne
                $ManifestIdentity.PackageIdentityBindingToken
        ) {
            return $false
        }

        if (
            $Evidence.SignerCertificateDerBase64 -isnot [string] -or
            -not (Test-CddsiD027CanonicalBase64 `
                -Value $Evidence.SignerCertificateDerBase64 `
                -MinimumBytes 256 `
                -MaximumBytes $script:CddsiD027ClaudeSignerCertificateMaximumBytes) -or
            $Evidence.SignerCertificateDerSha256 -isnot [string] -or
            $Evidence.SignerCertificateDerSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Evidence.SignerCertificateDerSha256 -cmatch '^0{64}$' -or
            (($Evidence.SignerCertificateDerLengthBytes -isnot [int]) -and
                ($Evidence.SignerCertificateDerLengthBytes -isnot [long])) -or
            $Evidence.SignerCertificateThumbprintSha1 -isnot [string] -or
            $Evidence.SignerCertificateThumbprintSha1 -cnotmatch
                '^[a-f0-9]{40}$' -or
            $Evidence.SignerCertificateThumbprintSha1 -cmatch '^0{40}$' -or
            $Evidence.SignerSubject -isnot [string] -or
            $Evidence.SignerSubject.Length -lt 3 -or
            $Evidence.SignerSubject.Length -gt 8192 -or
            $Evidence.SignerSubject -match '[\x00-\x1f]' -or
            $Evidence.SignerSubjectTextSha256 -isnot [string] -or
            $Evidence.SignerSubjectTextSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Evidence.SignerSubjectTextSha256 -cmatch '^0{64}$' -or
            $Evidence.SignerSubjectNameRawDataSha256 -isnot [string] -or
            $Evidence.SignerSubjectNameRawDataSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Evidence.SignerSubjectNameRawDataSha256 -cmatch '^0{64}$'
        ) {
            return $false
        }
        $certificateBytes = [Convert]::FromBase64String(
            $Evidence.SignerCertificateDerBase64
        )
        if (
            [long]$Evidence.SignerCertificateDerLengthBytes -ne
                [long]$certificateBytes.Length -or
            $certificateBytes.Length -lt 256 -or
            $certificateBytes.Length -gt
                $script:CddsiD027ClaudeSignerCertificateMaximumBytes
        ) {
            return $false
        }
        $certificate =
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $certificateBytes,
                [string]$null,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
            )
        if (
            $certificate.HasPrivateKey -or
            [Convert]::ToBase64String($certificate.RawData) -cne
                $Evidence.SignerCertificateDerBase64 -or
            -not [string]::Equals(
                $certificate.Subject,
                $Evidence.SignerSubject,
                [StringComparison]::Ordinal
            ) -or
            -not [string]::Equals(
                $Evidence.SignerSubject,
                $ManifestIdentity.Publisher,
                [StringComparison]::Ordinal
            )
        ) {
            return $false
        }

        $sha = [System.Security.Cryptography.SHA256]::Create()
        $certificateSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($certificate.RawData)
        ).Replace('-', '').ToLowerInvariant()
        $subjectTextSha256 = [BitConverter]::ToString(
            $sha.ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $certificate.Subject
                )
            )
        ).Replace('-', '').ToLowerInvariant()
        $subjectNameRawDataSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($certificate.SubjectName.RawData)
        ).Replace('-', '').ToLowerInvariant()
        if (
            $Evidence.SignerCertificateDerSha256 -cne
                $certificateSha256 -or
            $Evidence.SignerCertificateThumbprintSha1 -cne
                ([string]$certificate.Thumbprint).ToLowerInvariant() -or
            $Evidence.SignerSubjectTextSha256 -cne
                $subjectTextSha256 -or
            $Evidence.SignerSubjectNameRawDataSha256 -cne
                $subjectNameRawDataSha256
        ) {
            return $false
        }

        foreach ($timestamp in @(
                $Evidence.ObservedAtUtc,
                $ValidationTimeUtc
            )) {
            if (
                $timestamp -isnot [string] -or
                $timestamp -notmatch
                    '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
                -not (Test-CddsiUtcTimestampValue -Value $timestamp)
            ) {
                return $false
            }
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $evidenceTime = [DateTimeOffset]::ParseExact(
            $Evidence.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $heldTime = [DateTimeOffset]::ParseExact(
            $HeldArtifactObservation.ObservedAtUtc,
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
            $evidenceTime -lt $heldTime -or
            $evidenceTime -gt $heldTime.AddMinutes(5) -or
            $evidenceTime -gt $validationTime.AddSeconds(30) -or
            $validationTime -gt $evidenceTime.AddMinutes(5) -or
            $Evidence.EvidenceBindingToken -isnot [string] -or
            $Evidence.EvidenceBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Evidence.EvidenceBindingToken -cmatch '^0{64}$' -or
            $Evidence.EvidenceBindingToken -cne
                (Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken `
                    -Evidence $Evidence)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $certificate) { $certificate.Dispose() }
    }
}

function ConvertFrom-CddsiD027ClaudeAppxManifestBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$ManifestBytes
    )

    $memory = $null
    $reader = $null
    $sha = $null
    try {
        if (
            $null -eq $ManifestBytes -or
            $ManifestBytes.Length -lt 32 -or
            $ManifestBytes.Length -gt $script:CddsiD027ClaudeManifestMaximumBytes
        ) {
            throw 'Manifest bytes were outside the allowed bound.'
        }
        $manifestSnapshot = [byte[]]$ManifestBytes.Clone()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $manifestSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($manifestSnapshot)
        ).Replace('-', '').ToLowerInvariant()
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument =
            $script:CddsiD027ClaudeManifestMaximumBytes
        $settings.MaxCharactersFromEntities = 0
        $settings.IgnoreComments = $false
        $settings.IgnoreProcessingInstructions = $false
        $settings.IgnoreWhitespace = $false

        $memory = New-Object System.IO.MemoryStream(
            $manifestSnapshot,
            0,
            $manifestSnapshot.Length,
            $false,
            $true
        )
        $reader = [System.Xml.XmlReader]::Create($memory, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $true
        $document.XmlResolver = $null
        $document.Load($reader)
        if ($null -ne $document.DocumentType) {
            throw 'Manifest document type declarations are prohibited.'
        }
        $root = $document.DocumentElement
        if (
            $null -eq $root -or
            $root.LocalName -cne 'Package' -or
            $root.NamespaceURI -cne $script:CddsiD027ClaudeManifestNamespace
        ) {
            throw 'Manifest package root identity was invalid.'
        }

        $identityCandidates = @(
            $root.ChildNodes |
                Where-Object {
                    $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                    $_.LocalName -ceq 'Identity'
                }
        )
        if (
            $identityCandidates.Count -ne 1 -or
            $identityCandidates[0].NamespaceURI -cne
                $script:CddsiD027ClaudeManifestNamespace
        ) {
            throw 'Manifest requires one exact foundation Identity element.'
        }
        $identity = $identityCandidates[0]
        if ($identity.HasChildNodes) {
            throw 'Manifest Identity must not contain child nodes.'
        }
        $attributeNames = New-Object System.Collections.Generic.List[string]
        foreach ($attribute in @($identity.Attributes)) {
            if (
                $attribute.NamespaceURI -ceq
                    'http://www.w3.org/2000/xmlns/' -or
                $attribute.Prefix -ceq 'xmlns'
            ) {
                continue
            }
            if (-not [string]::IsNullOrEmpty($attribute.NamespaceURI)) {
                throw 'Manifest Identity attributes must be unqualified.'
            }
            $attributeNames.Add([string]$attribute.LocalName)
        }
        $requiredAttributes = @(
            'Name',
            'ProcessorArchitecture',
            'Publisher',
            'Version'
        )
        $allowedWithResourceId = @($requiredAttributes + 'ResourceId')
        $actualAttributeText =
            @($attributeNames.ToArray() | Sort-Object -CaseSensitive) -join "`n"
        $requiredAttributeText =
            @($requiredAttributes | Sort-Object -CaseSensitive) -join "`n"
        $resourceAttributeText =
            @($allowedWithResourceId | Sort-Object -CaseSensitive) -join "`n"
        if (
            $actualAttributeText -cne $requiredAttributeText -and
            $actualAttributeText -cne $resourceAttributeText
        ) {
            throw 'Manifest Identity attribute set was invalid.'
        }

        $packageName = [string]$identity.GetAttribute('Name')
        $publisher = [string]$identity.GetAttribute('Publisher')
        $packageVersion = [string]$identity.GetAttribute('Version')
        $architecture = [string]$identity.GetAttribute('ProcessorArchitecture')
        $resourceId = if ($attributeNames -ccontains 'ResourceId') {
            [string]$identity.GetAttribute('ResourceId')
        }
        else {
            ''
        }
        $versionMatch = [regex]::Match(
            $packageVersion,
            '^(?<a>0|[1-9][0-9]{0,4})\.(?<b>0|[1-9][0-9]{0,4})\.(?<c>0|[1-9][0-9]{0,4})\.(?<d>0|[1-9][0-9]{0,4})$',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (
            $packageName -cne 'Claude' -or
            $architecture -cne 'x64' -or
            -not $versionMatch.Success -or
            $publisher.Length -lt 3 -or
            $publisher.Length -gt 8192 -or
            $publisher -match '[\x00-\x1f]' -or
            $resourceId -cne ''
        ) {
            throw 'Claude package name, publisher, version, architecture or resource identity was invalid.'
        }
        foreach ($groupName in @('a', 'b', 'c', 'd')) {
            if ([int]::Parse(
                $versionMatch.Groups[$groupName].Value,
                [Globalization.CultureInfo]::InvariantCulture
            ) -gt 65535) {
                throw 'Claude package version component exceeded the MSIX bound.'
            }
        }

        $distinguishedName =
            New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName(
                $publisher
            )
        if (
            $null -eq $distinguishedName.RawData -or
            $distinguishedName.RawData.Length -lt 3
        ) {
            throw 'Claude package publisher distinguished name was invalid.'
        }
        $publisherTextSha256 = [BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($publisher))
        ).Replace('-', '').ToLowerInvariant()
        $publisherParsedX500RawDataSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($distinguishedName.RawData)
        ).Replace('-', '').ToLowerInvariant()
        $identityBindingToken = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'ContractVersion=cddsi-d027-claude-package-identity-v1'
            'Name=Claude'
            ('PublisherTextSha256={0}' -f $publisherTextSha256)
            (
                'PublisherParsedX500RawDataSha256={0}' -f
                    $publisherParsedX500RawDataSha256
            )
            ('Version={0}' -f $packageVersion)
            'ProcessorArchitecture=x64'
            ('ResourceId={0}' -f $resourceId)
        ) -join "`n")

        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-claude-appx-manifest-v1'
            PackageName = $packageName
            Publisher = $publisher
            PublisherTextSha256 = $publisherTextSha256
            PublisherParsedX500RawDataSha256 =
                $publisherParsedX500RawDataSha256
            PackageVersion = $packageVersion
            Architecture = $architecture
            ResourceId = $resourceId
            PackageIdentityBindingToken = $identityBindingToken
            ManifestSha256 = $manifestSha256
            ManifestLengthBytes = [long]$manifestSnapshot.Length
        }
        $values = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) {
            $values[$property.Name] = $property.Value
        }
        $values['ManifestBindingToken'] =
            Get-CddsiD027ClaudeManifestBindingToken `
                -ManifestIdentity $withoutBinding
        return [pscustomobject]$values
    }
    catch {
        throw 'Claude Desktop AppxManifest.xml did not match the bounded D-027 x64 identity contract.'
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $memory) { $memory.Dispose() }
    }
}

function Read-CddsiD027ClaudeMsixManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$PackageStream
    )

    $archive = $null
    $entryStream = $null
    $initialPosition = [long]0
    $restorePosition = $false
    try {
        if (
            $null -eq $PackageStream -or
            -not $PackageStream.CanRead -or
            -not $PackageStream.CanSeek
        ) {
            throw 'MSIX package stream must be readable and seekable.'
        }
        $initialPosition = [long]$PackageStream.Position
        if (
            $PackageStream.Length -lt 64 -or
            $PackageStream.Length -gt $script:CddsiD027ClaudeMsixMaximumBytes -or
            $initialPosition -lt 0 -or
            $initialPosition -gt $PackageStream.Length
        ) {
            throw 'MSIX package stream length or caller position was outside the standard x64 bound.'
        }
        $PackageStream.Position = 0
        $restorePosition = $true
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $archive = [System.IO.Compression.ZipArchive]::new(
            $PackageStream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $true
        )
        $entries = @($archive.Entries)
        if ($entries.Count -lt 1 -or $entries.Count -gt 4096) {
            throw 'MSIX ZIP entry count was outside the allowed range.'
        }
        $requiredRootEntries = @(
            'AppxManifest.xml',
            'AppxSignature.p7x',
            'AppxBlockMap.xml',
            '[Content_Types].xml'
        )
        $criticalEntries = @{}
        foreach ($requiredName in $requiredRootEntries) {
            $candidates = @(
                $entries |
                    Where-Object {
                        [string]::Equals(
                            $_.FullName,
                            $requiredName,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    }
            )
            if (
                $candidates.Count -ne 1 -or
                $candidates[0].FullName -cne $requiredName
            ) {
                throw 'MSIX requires one exact copy of every critical root entry.'
            }
            $criticalEntries[$requiredName] = $candidates[0]
        }
        $manifestEntry = $criticalEntries['AppxManifest.xml']
        if (
            $manifestEntry.Length -lt 32 -or
            $manifestEntry.Length -gt $script:CddsiD027ClaudeManifestMaximumBytes -or
            $manifestEntry.CompressedLength -lt 1 -or
            (
                $manifestEntry.Length -gt 65536 -and
                $manifestEntry.CompressedLength -lt
                    [Math]::Floor($manifestEntry.Length / 1000)
            )
        ) {
            throw 'MSIX manifest entry length or compression ratio was invalid.'
        }
        $manifestBytes = New-Object byte[] ([int]$manifestEntry.Length)
        $entryStream = $manifestEntry.Open()
        $offset = 0
        while ($offset -lt $manifestBytes.Length) {
            $read = $entryStream.Read(
                $manifestBytes,
                $offset,
                $manifestBytes.Length - $offset
            )
            if ($read -le 0) {
                throw 'MSIX manifest entry read was truncated.'
            }
            $offset += $read
        }
        if ($entryStream.ReadByte() -ne -1) {
            throw 'MSIX manifest entry exceeded its declared length.'
        }
        return ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
            -ManifestBytes $manifestBytes
    }
    catch {
        throw 'Claude Desktop MSIX manifest could not be read from one bounded root ZIP entry.'
    }
    finally {
        if ($null -ne $entryStream) { $entryStream.Dispose() }
        if ($null -ne $archive) { $archive.Dispose() }
        if (
            $restorePosition -and
            $null -ne $PackageStream -and
            $PackageStream.CanSeek
        ) {
            $PackageStream.Position = $initialPosition
        }
    }
}

function Get-CddsiClaudeDesktopMsixStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$MinimumVersion,
        [Parameter(Mandatory = $true)][ValidateSet('PerUser', 'MachineWide', 'Unresolved')][string]$RequiredScope,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64', 'Unknown')][string]$ExpectedArchitecture
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    try {
        $minimum = [version]::Parse($MinimumVersion)
    }
    catch {
        throw 'MinimumVersion must be a valid version string.'
    }

    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion     = 1
        InstallType       = 'Unknown'
        InventoryCount    = 0
        Version           = $null
        Architecture      = 'Unknown'
        Scope             = 'Unknown'
        DeploymentChannel = 'Unknown'
        IdentityToken     = $null
        IdentityStatus    = 'Unknown'
        CapabilityStatus  = 'UNKNOWN'
        ReasonCodes       = @('DESKTOP_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Package -Operation Inspect -ResourceToken '<PACKAGE:CLAUDE_DESKTOP>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'DESKTOP_PROVIDER_FAILED' -MessageSafe 'Synthetic Claude Desktop package provider failed closed.' -Data $unknownData
    }

    $valid = (
        (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'Installations')) -and
        $observation.SchemaVersion -is [int] -and $observation.SchemaVersion -eq 1 -and
        $null -ne $observation.Installations
    )
    [object[]]$installations = @()
    if ($valid) {
        $installations = @($observation.Installations)
    }
    if ($valid) {
        foreach ($installation in $installations) {
            if (
                -not (Test-CddsiExactPropertySet -InputObject $installation -Expected @('InstallKind', 'Version', 'Architecture', 'Scope', 'DeploymentChannel', 'IdentityToken', 'IdentityStatus', 'Operational')) -or
                $installation.InstallKind -isnot [string] -or @('LegacyExe', 'Msix') -cnotcontains $installation.InstallKind -or
                $installation.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($installation.Version) -or
                $installation.Architecture -isnot [string] -or @('x64', 'arm64', 'Unknown') -cnotcontains $installation.Architecture -or
                $installation.Scope -isnot [string] -or @('PerUser', 'MachineWide', 'Unknown') -cnotcontains $installation.Scope -or
                $installation.DeploymentChannel -isnot [string] -or @('Standard', 'Offline', 'Unknown') -cnotcontains $installation.DeploymentChannel -or
                $installation.IdentityToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $installation.IdentityToken) -or
                $installation.IdentityStatus -isnot [string] -or @('Trusted', 'Untrusted', 'Unknown') -cnotcontains $installation.IdentityStatus -or
                $installation.Operational -isnot [bool]
            ) {
                $valid = $false
                break
            }
        }
    }
    if (-not $valid) {
        $unknownData.ReasonCodes = @('DESKTOP_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'DESKTOP_RESULT_INVALID' -MessageSafe 'Synthetic Claude Desktop inventory did not match the exact schema.' -Data $unknownData
    }

    if ($installations.Count -eq 0) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            InstallType       = 'None'
            InventoryCount    = 0
            Version           = $null
            Architecture      = 'Unknown'
            Scope             = 'Unknown'
            DeploymentChannel = 'Unknown'
            IdentityToken     = $null
            IdentityStatus    = 'Unknown'
            CapabilityStatus  = 'BLOCKED'
            ReasonCodes       = @('DESKTOP_MISSING')
        }
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop inventory completed.' -Data $data
    }

    if ($installations.Count -gt 1) {
        $kinds = @($installations | ForEach-Object { $_.InstallKind } | Sort-Object -Unique -CaseSensitive)
        $scopes = @($installations | Where-Object InstallKind -CEQ 'Msix' | ForEach-Object { $_.Scope } | Sort-Object -Unique -CaseSensitive)
        $msixCount = @($installations | Where-Object InstallKind -CEQ 'Msix').Count
        $reasons = @('DESKTOP_INSTALL_CONFLICT')
        if ($kinds.Count -gt 1) { $reasons += 'LEGACY_MSIX_CONFLICT' }
        if ($msixCount -gt 1) { $reasons += 'MSIX_DOUBLE_INSTALL_RISK' }
        if ($scopes.Count -gt 1) { $reasons += 'MSIX_SCOPE_CONFLICT' }
        $data = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            InstallType       = 'Conflict'
            InventoryCount    = $installations.Count
            Version           = $null
            Architecture      = 'Unknown'
            Scope             = 'Conflict'
            DeploymentChannel = 'Unknown'
            IdentityToken     = $null
            IdentityStatus    = 'Unknown'
            CapabilityStatus  = 'BLOCKED'
            ReasonCodes       = @($reasons)
        }
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop inventory found a conflict and failed closed.' -Data $data
    }

    $installation = $installations[0]
    if ($installation.InstallKind -ceq 'LegacyExe') {
        $data = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            InstallType       = 'LegacyExe'
            InventoryCount    = 1
            Version           = $installation.Version
            Architecture      = $installation.Architecture
            Scope             = $installation.Scope
            DeploymentChannel = $installation.DeploymentChannel
            IdentityToken     = $installation.IdentityToken
            IdentityStatus    = $installation.IdentityStatus
            CapabilityStatus  = 'BLOCKED'
            ReasonCodes       = @('LEGACY_DESKTOP_UNSUPPORTED')
        }
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop inventory found an unsupported legacy installation.' -Data $data
    }

    try {
        $installedVersion = [version]::Parse($installation.Version)
    }
    catch {
        $unknownData.InventoryCount = 1
        $unknownData.ReasonCodes = @('DESKTOP_VERSION_INVALID')
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'DESKTOP_VERSION_INVALID' -MessageSafe 'Synthetic Claude Desktop version was not parseable.' -Data $unknownData
    }

    $blockedReasons = @()
    $unknownReasons = @()
    if ($installedVersion -lt $minimum) { $blockedReasons += 'DESKTOP_UPGRADE_REQUIRED' }
    if (-not $installation.Operational) { $blockedReasons += 'DESKTOP_INSTALLATION_BROKEN' }
    if ($installation.IdentityStatus -ceq 'Untrusted') { $blockedReasons += 'DESKTOP_IDENTITY_UNTRUSTED' }
    if ($installation.IdentityStatus -ceq 'Unknown') { $unknownReasons += 'DESKTOP_IDENTITY_UNKNOWN' }
    if ($ExpectedArchitecture -ceq 'Unknown') {
        $unknownReasons += 'TARGET_ARCHITECTURE_UNKNOWN'
    }
    elseif ($installation.Architecture -ceq 'Unknown') {
        $unknownReasons += 'DESKTOP_ARCHITECTURE_UNKNOWN'
    }
    elseif ($installation.Architecture -cne $ExpectedArchitecture) {
        $blockedReasons += 'DESKTOP_ARCHITECTURE_MISMATCH'
    }
    if ($RequiredScope -ceq 'Unresolved') {
        $unknownReasons += 'MSIX_SCOPE_DECISION_REQUIRED'
    }
    elseif ($installation.Scope -ceq 'Unknown') {
        $unknownReasons += 'MSIX_SCOPE_UNKNOWN'
    }
    elseif ($installation.Scope -cne $RequiredScope) {
        $blockedReasons += 'MSIX_SCOPE_MISMATCH'
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
        $reasonCodes = @('DESKTOP_MSIX_READY')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion     = 1
        InstallType       = 'Msix'
        InventoryCount    = 1
        Version           = $installation.Version
        Architecture      = $installation.Architecture
        Scope             = $installation.Scope
        DeploymentChannel = $installation.DeploymentChannel
        IdentityToken     = $installation.IdentityToken
        IdentityStatus    = $installation.IdentityStatus
        CapabilityStatus  = $capabilityStatus
        ReasonCodes       = @($reasonCodes)
    }
    return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop MSIX inventory completed.' -Data $data
}

function ConvertFrom-CddsiAnthropicMsixReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ReleaseDocument,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
        [Parameter(Mandatory = $true)][ValidateSet('Standard', 'Offline')][string]$Channel
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ReleaseDocument -Expected @('SchemaVersion', 'SourcePolicy', 'DescriptorId', 'ReleaseVersion', 'Assets'))) {
        throw 'Anthropic MSIX release document does not match the exact schema.'
    }
    $parsedVersion = $null
    if (
        -not (Test-CddsiSchemaVersionOne -Value $ReleaseDocument.SchemaVersion) -or
        $ReleaseDocument.SourcePolicy -isnot [string] -or $ReleaseDocument.SourcePolicy -cne 'anthropic_official_only' -or
        -not (Test-CddsiSafeIdentifierValue -Value $ReleaseDocument.DescriptorId -MaxLength 128) -or
        $ReleaseDocument.ReleaseVersion -isnot [string] -or -not [version]::TryParse($ReleaseDocument.ReleaseVersion, [ref]$parsedVersion) -or
        $null -eq $ReleaseDocument.Assets
    ) {
        throw 'Anthropic MSIX release document values are invalid.'
    }

    $assetFields = @(
        'Architecture', 'Channel', 'DownloadUri', 'FileNameToken', 'ArtifactSha256',
        'SizeBytes', 'SignerThumbprint', 'SignerSubjectToken', 'PublisherToken', 'PackageIdentityToken'
    )
    $selectedAssets = @()
    foreach ($asset in @($ReleaseDocument.Assets)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $asset -Expected $assetFields)) {
            throw 'Anthropic MSIX asset does not match the exact schema.'
        }
        if (
            $asset.Architecture -isnot [string] -or @('x64', 'arm64') -cnotcontains $asset.Architecture -or
            $asset.Channel -isnot [string] -or @('Standard', 'Offline') -cnotcontains $asset.Channel -or
            $asset.DownloadUri -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $asset.DownloadUri -ExpectedOwner Anthropic) -or
            $asset.FileNameToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $asset.FileNameToken) -or
            ($asset.SizeBytes -isnot [int] -and $asset.SizeBytes -isnot [long]) -or [long]$asset.SizeBytes -lt 1
        ) {
            throw 'Anthropic MSIX asset values are invalid.'
        }
        if ($null -ne $asset.ArtifactSha256 -and ($asset.ArtifactSha256 -isnot [string] -or $asset.ArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$')) { throw 'Anthropic MSIX asset SHA-256 is invalid.' }
        if ($null -ne $asset.SignerThumbprint -and ($asset.SignerThumbprint -isnot [string] -or $asset.SignerThumbprint -notmatch '^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$')) { throw 'Anthropic MSIX signer thumbprint is invalid.' }
        foreach ($name in @('SignerSubjectToken', 'PublisherToken', 'PackageIdentityToken')) {
            if ($null -ne $asset.$name -and ($asset.$name -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $asset.$name))) {
                throw ('Anthropic MSIX {0} is invalid.' -f $name)
            }
        }
        if ($asset.Architecture -ceq $Architecture -and $asset.Channel -ceq $Channel) { $selectedAssets += $asset }
    }
    if ($selectedAssets.Count -ne 1) { throw 'Anthropic MSIX metadata must contain exactly one requested asset.' }

    $selected = $selectedAssets[0]
    $resolved = (
        $null -ne $selected.ArtifactSha256 -and $null -ne $selected.SignerThumbprint -and
        $null -ne $selected.SignerSubjectToken -and $null -ne $selected.PublisherToken -and
        $null -ne $selected.PackageIdentityToken
    )
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion              = 1
        DescriptorId               = $ReleaseDocument.DescriptorId
        ArtifactType               = 'ClaudeDesktopMsix'
        SourcePolicy               = 'anthropic_official_only'
        SourceUri                  = $selected.DownloadUri
        SourceUriBindingToken      = Get-CddsiSourceUriBindingToken -SourceUri $selected.DownloadUri
        ReleaseVersion             = $ReleaseDocument.ReleaseVersion
        Architecture               = $selected.Architecture
        Channel                    = $selected.Channel
        FileNameToken              = $selected.FileNameToken
        ExpectedArtifactSha256     = if ($null -eq $selected.ArtifactSha256) { $null } else { $selected.ArtifactSha256.ToLowerInvariant() }
        ExpectedArtifactSizeBytes  = [long]$selected.SizeBytes
        ExpectedSignerThumbprint   = if ($null -eq $selected.SignerThumbprint) { $null } else { $selected.SignerThumbprint.ToLowerInvariant() }
        ExpectedSignerSubjectToken = $selected.SignerSubjectToken
        ExpectedPublisherToken     = $selected.PublisherToken
        ExpectedIdentityToken      = $selected.PackageIdentityToken
        RedirectPolicy             = 'same-owner-https-only'
        MaximumBytes               = if ($Channel -ceq 'Offline') { [long]4294967296 } else { [long]1073741824 }
        MetadataStatus             = if ($resolved) { 'READY' } else { 'UNRESOLVED' }
    }
    $descriptor = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) { $descriptor[$property.Name] = $property.Value }
    $descriptor['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $result = [pscustomobject]$descriptor
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $result -ExpectedArtifactType ClaudeDesktopMsix)) {
        throw 'Anthropic MSIX descriptor failed its immutable contract.'
    }
    return $result
}

function Get-CddsiOfficialMsixMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
        [Parameter(Mandatory = $true)][ValidateSet('Standard', 'Offline')][string]$Channel
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    try {
        $document = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Network -Operation Inspect -ResourceToken '<NETWORK:ANTHROPIC_MSIX_METADATA>' -Arguments ([ordered]@{ Architecture = $Architecture; Channel = $Channel })
        $descriptor = ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $document -Architecture $Architecture -Channel $Channel
    }
    catch {
        return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'MSIX_METADATA_INVALID' -MessageSafe 'Synthetic Anthropic MSIX metadata failed closed.'
    }
    if ($descriptor.MetadataStatus -ceq 'READY') {
        return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Anthropic MSIX metadata resolved to an immutable descriptor.' -Data $descriptor
    }
    return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'MSIX_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'MSIX signer, identity or hash remains unresolved and installation is blocked.' -Data $descriptor
}

function Save-CddsiOfficialClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType ClaudeDesktopMsix)) {
        throw 'MSIX download plan requires an exact official artifact descriptor.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $DestinationPath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'DownloadClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ArtifactType = 'ClaudeDesktopMsix'
        DestinationPathBindingToken = $pathBindingToken
        SourceDescriptorBindingToken =
            $ArtifactDescriptor.MetadataBindingToken
        RequestUriBindingToken =
            $ArtifactDescriptor.SourceUriBindingToken
        ArtifactIdentityStatus = 'UNRESOLVED_UNTIL_BODY_HASHED'
        CacheIdentityStatus = 'UNAVAILABLE_UNTIL_BODY_HASHED'
        TransportImplementationStatus = 'NOT_CONNECTED'
        WriteImplemented = $false
    }
    $errorCode = if ($ArtifactDescriptor.MetadataStatus -ceq 'READY') { 'P4_PLAN_ONLY' } else { 'MSIX_ARTIFACT_CONTRACT_UNRESOLVED' }
    return New-CddsiOperationResult -Operation 'DownloadClaudeDesktopMsix' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode $errorCode -MessageSafe 'No network or file write occurred; no artifact or cache identity exists until the response body is hashed.' -Data $data -PlannedChanges @('<DOWNLOAD:CLAUDE_DESKTOP_MSIX>')
}

function Test-CddsiClaudeDesktopMsixSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)][AllowNull()]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType ClaudeDesktopMsix -RequireResolved)) {
        return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'MSIX_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'Resolved MSIX hash and identity metadata are required before verification.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $PackagePath
    try {
        $fileObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'SignatureVerification' })
        $signatureObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Package -Operation Inspect -ResourceToken '<SIGNATURE:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; ArtifactSha256 = [string]$fileObservation.ArtifactSha256 })
        $evidence = New-CddsiSignatureEvidenceVerdict -Descriptor $ArtifactDescriptor -ExpectedArtifactType ClaudeDesktopMsix -PathBindingToken $pathBindingToken -SourceObservation $SourceObservation -FileObservation $fileObservation -SignatureObservation $signatureObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc
    }
    catch {
        return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'MSIX_SIGNATURE_OBSERVATION_FAILED' -MessageSafe 'Synthetic MSIX signature observation failed closed.'
    }
    if (-not $evidence.Valid) {
        return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'MSIX_SIGNATURE_REJECTED' -MessageSafe 'MSIX signature or immutable descriptor binding did not match.' -Data $evidence
    }
    return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic MSIX signature evidence v2 is fully bound.' -Data $evidence
}

function Install-CddsiClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $PackagePath -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) { throw '安装合同要求与目标包、source observation、run/profile 及 immutable descriptor 绑定的新鲜 v2 验签证据。' }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
    $pathBindingToken = Get-CddsiPathBindingToken -Path $PackagePath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'InstallClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $current = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'ExecutionTimeHashReverification' })
    if (
        -not (Test-CddsiExactPropertySet -InputObject $current -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes')) -or
        -not (Test-CddsiSchemaVersionOne -Value $current.SchemaVersion) -or
        $current.FileIdentityToken -isnot [string] -or $current.FileIdentityToken -cne $payload.FileIdentityToken -or
        $current.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $current.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
        ($current.ArtifactSizeBytes -isnot [int] -and $current.ArtifactSizeBytes -isnot [long]) -or [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 MSIX hash/size 复验失败；拒绝安装。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'ClaudeDesktopMsix'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'InstallClaudeDesktopMsix' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'MSIX hash was reverified through the fake provider; installation remains disabled.' -Data $data -PlannedChanges @('<INSTALL:CLAUDE_DESKTOP_MSIX>')
}

function Update-CddsiClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $PackagePath -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) { throw '升级合同要求与目标包、source observation、run/profile 及 immutable descriptor 绑定的新鲜 v2 验签证据。' }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
    $pathBindingToken = Get-CddsiPathBindingToken -Path $PackagePath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'UpdateClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $current = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'ExecutionTimeHashReverification' })
    if (
        -not (Test-CddsiExactPropertySet -InputObject $current -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes')) -or
        -not (Test-CddsiSchemaVersionOne -Value $current.SchemaVersion) -or
        $current.FileIdentityToken -isnot [string] -or $current.FileIdentityToken -cne $payload.FileIdentityToken -or
        $current.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $current.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
        ($current.ArtifactSizeBytes -isnot [int] -and $current.ArtifactSizeBytes -isnot [long]) -or [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 MSIX hash/size 复验失败；拒绝升级。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'ClaudeDesktopMsix'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'UpdateClaudeDesktopMsix' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'MSIX hash was reverified through the fake provider; update remains disabled.' -Data $data -PlannedChanges @('<UPDATE:CLAUDE_DESKTOP_MSIX>')
}
