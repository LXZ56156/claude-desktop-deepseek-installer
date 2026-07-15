# credential-helper-release.ps1 - Pure release, protected-blob and invocation contracts.
# This file never reads a file, invokes a process or calls DPAPI.

function New-CddsiCredentialHelperReleaseContract {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        SchemaVersion                  = 1
        ContractVersion                = 'cddsi-credential-helper-release-v1'
        ImplementationKind             = 'SignedDotNetExe'
        ExecutableFileName              = 'cddsi-credential-helper.exe'
        ProtocolVersion                 = 'cddsi-credential-helper-protocol-v1'
        BuildDescriptorContractVersion  = 'cddsi-credential-helper-build-v1'
        CandidateContractVersion        = 'cddsi-credential-helper-candidate-v1'
        SignatureContractVersion        = 'cddsi-credential-helper-signature-v1'
        AclContractVersion              = 'cddsi-credential-helper-acl-v1'
        ProtectedBlobContractVersion    = 'cddsi-credential-helper-protected-blob-v1'
        InvocationContractVersion       = 'cddsi-credential-helper-invocation-v1'
        TargetFramework                 = 'net8.0-windows'
        SupportedArchitectures          = [string[]]@('Arm64', 'X64')
        SelfContained                   = $true
        SingleFile                      = $true
        Deterministic                   = $true
        DependencyLockRequired          = $true
        SbomFormat                      = 'CycloneDXJson15'
        AuthenticodeRequired            = $true
        TrustedChainRequired            = $true
        DpapiScope                      = 'CurrentUser'
        BlobResourceToken               = '<CREDENTIAL_BLOB:DEEPSEEK>'
        BlobAclPolicy                   = 'CurrentUserOnlyProtectedDacl'
        BlobOwnerPolicy                 = 'ExactCurrentUserSid'
        PlaintextPersistence            = $false
        InvocationKind                  = 'DirectExecutable'
        ArgumentCount                   = 0
        ShellInvocation                 = $false
        StandardInputRead               = $false
        AllowedOutputKinds              = [string[]]@('BareTokenSingleLine', 'ExactJsonV1')
        ExactJsonPropertyName           = 'token'
        StandardErrorPolicy             = 'Empty'
        RequiredExitCode                = 0
        ContextEnvironmentVariableName  = 'CLAUDE_HELPER_CONTEXT'
        AllowedHelperContexts           = [string[]]@(
            'interactive',
            'mid-session-refresh',
            'scheduled-task',
            'setup-test',
            'background'
        )
        DefaultTimeoutSeconds           = 60
        MidSessionRefreshTimeoutSeconds = 20
        PromptPolicy                    = 'Forbidden'
        TtlSeconds                      = 3600
    }
}

function Get-CddsiCredentialHelperBuildDescriptorBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Descriptor
    )

    $lines = @(
        'contract=' + [string]$Descriptor.ContractVersion
        'buildId=' + [string]$Descriptor.BuildId
        'releaseVersion=' + [string]$Descriptor.ReleaseVersion
        'commitId=' + [string]$Descriptor.CommitId
        'implementation=' + [string]$Descriptor.ImplementationKind
        'protocol=' + [string]$Descriptor.ProtocolVersion
        'fileName=' + [string]$Descriptor.ExecutableFileName
        'architecture=' + [string]$Descriptor.Architecture
        'runtimeIdentifier=' + [string]$Descriptor.RuntimeIdentifier
        'targetFramework=' + [string]$Descriptor.TargetFramework
        'dotNetSdkVersion=' + [string]$Descriptor.DotNetSdkVersion
        'compilerVersion=' + [string]$Descriptor.CompilerVersion
        'runtimePackVersion=' + [string]$Descriptor.RuntimePackVersion
        'toolchain=' + [string]$Descriptor.ToolchainDescriptorSha256
        'dependencyLock=' + [string]$Descriptor.DependencyLockSha256
        'dependencyCount=' + [string]$Descriptor.DependencyCount
        'sourceTree=' + [string]$Descriptor.SourceTreeSha256
        'sourceManifest=' + [string]$Descriptor.SourceManifestSha256
        'sourceTreeEntryCount=' + [string]$Descriptor.SourceTreeEntryCount
        'sbomFormat=' + [string]$Descriptor.SbomFormat
        'sbom=' + [string]$Descriptor.SbomSha256
        'sbomComponentSet=' + [string]$Descriptor.SbomComponentSetSha256
        'sbomComponentCount=' + [string]$Descriptor.SbomComponentCount
        'pe=' + [string]$Descriptor.PeSha256
        'peSize=' + [string]$Descriptor.PeSizeBytes
        'signerCertificate=' + [string]$Descriptor.ExpectedSignerCertificateSha256
        'signerSubject=' + [string]$Descriptor.ExpectedSignerSubjectSha256
        'deterministic=' + ([string]$Descriptor.Deterministic).ToLowerInvariant()
        'selfContained=' + ([string]$Descriptor.SelfContained).ToLowerInvariant()
        'singleFile=' + ([string]$Descriptor.SingleFile).ToLowerInvariant()
        'dependencyLockRequired=' + ([string]$Descriptor.DependencyLockRequired).ToLowerInvariant()
        'authenticodeRequired=' + ([string]$Descriptor.AuthenticodeRequired).ToLowerInvariant()
        'producedAt=' + [string]$Descriptor.ProducedAtUtc
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCredentialHelperBuildDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'BuildId', 'ReleaseVersion', 'CommitId',
        'ImplementationKind', 'ProtocolVersion', 'ExecutableFileName', 'Architecture',
        'RuntimeIdentifier', 'TargetFramework', 'DotNetSdkVersion', 'CompilerVersion',
        'RuntimePackVersion', 'ToolchainDescriptorSha256', 'DependencyLockSha256',
        'DependencyCount', 'SourceTreeSha256', 'SourceManifestSha256',
        'SourceTreeEntryCount', 'SbomFormat', 'SbomSha256', 'SbomComponentSetSha256',
        'SbomComponentCount', 'PeSha256', 'PeSizeBytes', 'ExpectedSignerCertificateSha256',
        'ExpectedSignerSubjectSha256', 'Deterministic', 'SelfContained', 'SingleFile',
        'DependencyLockRequired', 'AuthenticodeRequired', 'ProducedAtUtc',
        'DescriptorBindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Descriptor.SchemaVersion) -or
        $Descriptor.ContractVersion -cne 'cddsi-credential-helper-build-v1' -or
        $Descriptor.ImplementationKind -cne 'SignedDotNetExe' -or
        $Descriptor.ProtocolVersion -cne 'cddsi-credential-helper-protocol-v1' -or
        $Descriptor.ExecutableFileName -cne 'cddsi-credential-helper.exe' -or
        $Descriptor.TargetFramework -cne 'net8.0-windows' -or
        $Descriptor.SbomFormat -cne 'CycloneDXJson15') { return $false }
    if (-not (Test-CddsiCanonicalUuidValue -Value $Descriptor.BuildId) -or
        $Descriptor.ReleaseVersion -isnot [string] -or
        $Descriptor.ReleaseVersion -notmatch '^(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:-[a-z0-9]+(?:[.-][a-z0-9]+)*)?$' -or
        $Descriptor.CommitId -isnot [string] -or $Descriptor.CommitId -notmatch '^[a-f0-9]{40}$') { return $false }
    $expectedRuntimeIdentifier = switch ($Descriptor.Architecture) {
        'X64' { 'win-x64' }
        'Arm64' { 'win-arm64' }
        default { return $false }
    }
    if ($Descriptor.RuntimeIdentifier -cne $expectedRuntimeIdentifier) { return $false }
    foreach ($version in @($Descriptor.DotNetSdkVersion, $Descriptor.CompilerVersion, $Descriptor.RuntimePackVersion)) {
        if (-not (Test-CddsiSafeIdentifierValue -Value $version -MaxLength 64)) { return $false }
    }
    $hashes = @(
        $Descriptor.ToolchainDescriptorSha256, $Descriptor.DependencyLockSha256,
        $Descriptor.SourceTreeSha256, $Descriptor.SourceManifestSha256,
        $Descriptor.SbomSha256, $Descriptor.SbomComponentSetSha256,
        $Descriptor.PeSha256, $Descriptor.ExpectedSignerCertificateSha256,
        $Descriptor.ExpectedSignerSubjectSha256
    )
    foreach ($hash in $hashes) {
        if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    if (@($hashes | Select-Object -Unique).Count -ne $hashes.Count) { return $false }
    foreach ($countName in @('DependencyCount', 'SourceTreeEntryCount', 'SbomComponentCount')) {
        $count = $Descriptor.$countName
        if (($count -isnot [int] -and $count -isnot [long]) -or [long]$count -lt 0) { return $false }
    }
    if ([long]$Descriptor.SourceTreeEntryCount -lt 1 -or [long]$Descriptor.SbomComponentCount -lt 1) { return $false }
    if (($Descriptor.PeSizeBytes -isnot [int] -and $Descriptor.PeSizeBytes -isnot [long]) -or
        [long]$Descriptor.PeSizeBytes -lt 1 -or [long]$Descriptor.PeSizeBytes -gt 104857600) { return $false }
    foreach ($name in @('Deterministic', 'SelfContained', 'SingleFile', 'DependencyLockRequired', 'AuthenticodeRequired')) {
        if ($Descriptor.$name -isnot [bool] -or -not $Descriptor.$name) { return $false }
    }
    if (-not (Test-CddsiUtcTimestampValue -Value $Descriptor.ProducedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc) -or
        [DateTimeOffset]::Parse($Descriptor.ProducedAtUtc) -gt [DateTimeOffset]::Parse($ValidationTimeUtc)) { return $false }
    if ($Descriptor.DescriptorBindingToken -isnot [string] -or $Descriptor.DescriptorBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Descriptor.DescriptorBindingToken -ceq (Get-CddsiCredentialHelperBuildDescriptorBindingToken -Descriptor $Descriptor))
    }
    catch {
        return $false
    }
}

function Get-CddsiCredentialHelperSignatureEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $lines = @(
        'contract=' + [string]$Evidence.ContractVersion
        'evidenceId=' + [string]$Evidence.EvidenceId
        'candidateId=' + [string]$Evidence.CandidateId
        'build=' + [string]$Evidence.BuildDescriptorBindingToken
        'pe=' + [string]$Evidence.PeSha256
        'status=' + [string]$Evidence.AuthenticodeStatus
        'chainTrusted=' + ([string]$Evidence.ChainTrusted).ToLowerInvariant()
        'certificate=' + [string]$Evidence.SignerCertificateSha256
        'subject=' + [string]$Evidence.SignerSubjectSha256
        'timestampStatus=' + [string]$Evidence.TimestampStatus
        'timestamp=' + [string]$Evidence.TimestampUtc
        'observedAt=' + [string]$Evidence.ObservedAtUtc
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCredentialHelperSignatureEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedBuildDescriptor,
        [Parameter(Mandatory = $true)][string]$ExpectedCandidateId,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumObservationAgeSeconds = 600
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'EvidenceId', 'CandidateId',
        'BuildDescriptorBindingToken', 'PeSha256', 'AuthenticodeStatus',
        'ChainTrusted', 'SignerCertificateSha256', 'SignerSubjectSha256',
        'TimestampStatus', 'TimestampUtc', 'ObservedAtUtc', 'BindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required) -or
        -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-credential-helper-signature-v1' -or
        -not (Test-CddsiCanonicalUuidValue -Value $ExpectedCandidateId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.EvidenceId) -or
        $Evidence.CandidateId -cne $ExpectedCandidateId -or
        $Evidence.EvidenceId -ceq $ExpectedCandidateId) { return $false }
    if ($Evidence.BuildDescriptorBindingToken -cne $ExpectedBuildDescriptor.DescriptorBindingToken -or
        $Evidence.PeSha256 -cne $ExpectedBuildDescriptor.PeSha256 -or
        $Evidence.SignerCertificateSha256 -cne $ExpectedBuildDescriptor.ExpectedSignerCertificateSha256 -or
        $Evidence.SignerSubjectSha256 -cne $ExpectedBuildDescriptor.ExpectedSignerSubjectSha256 -or
        $Evidence.AuthenticodeStatus -cne 'Valid' -or
        $Evidence.ChainTrusted -isnot [bool] -or -not $Evidence.ChainTrusted -or
        $Evidence.TimestampStatus -cne 'Valid') { return $false }
    foreach ($time in @($ExpectedBuildDescriptor.ProducedAtUtc, $Evidence.TimestampUtc, $Evidence.ObservedAtUtc, $ValidationTimeUtc)) {
        if (-not (Test-CddsiUtcTimestampValue -Value $time)) { return $false }
    }
    $produced = [DateTimeOffset]::Parse($ExpectedBuildDescriptor.ProducedAtUtc)
    $timestamp = [DateTimeOffset]::Parse($Evidence.TimestampUtc)
    $observed = [DateTimeOffset]::Parse($Evidence.ObservedAtUtc)
    $validation = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if ($timestamp -lt $produced -or $observed -lt $timestamp -or $observed -gt $validation -or
        ($validation - $observed).TotalSeconds -gt $MaximumObservationAgeSeconds) { return $false }
    if ($Evidence.BindingToken -isnot [string] -or $Evidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Evidence.BindingToken -ceq (Get-CddsiCredentialHelperSignatureEvidenceBindingToken -Evidence $Evidence))
    }
    catch {
        return $false
    }
}

function Get-CddsiCredentialHelperAclEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $lines = @(
        'contract=' + [string]$Evidence.ContractVersion
        'evidenceId=' + [string]$Evidence.EvidenceId
        'candidateId=' + [string]$Evidence.CandidateId
        'build=' + [string]$Evidence.BuildDescriptorBindingToken
        'path=' + [string]$Evidence.InstalledExecutablePathToken
        'owner=' + [string]$Evidence.OwnerSidToken
        'expectedOwner=' + [string]$Evidence.ExpectedOwnerSidToken
        'acl=' + [string]$Evidence.AclDescriptorSha256
        'policy=' + [string]$Evidence.AclPolicy
        'daclProtected=' + ([string]$Evidence.DaclProtected).ToLowerInvariant()
        'ownerMatch=' + ([string]$Evidence.OwnerMatch).ToLowerInvariant()
        'currentUserReadExecute=' + ([string]$Evidence.CurrentUserReadExecute).ToLowerInvariant()
        'currentUserWrite=' + ([string]$Evidence.CurrentUserWrite).ToLowerInvariant()
        'administratorsWrite=' + ([string]$Evidence.AdministratorsWrite).ToLowerInvariant()
        'systemWrite=' + ([string]$Evidence.SystemWrite).ToLowerInvariant()
        'unexpectedWriteAceCount=' + [string]$Evidence.UnexpectedWriteAceCount
        'observedAt=' + [string]$Evidence.ObservedAtUtc
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCredentialHelperAclEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][string]$ExpectedBuildDescriptorBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedCandidateId,
        [Parameter(Mandatory = $true)][string]$ExpectedInstalledExecutablePathToken,
        [Parameter(Mandatory = $true)][string]$ExpectedCurrentUserSidToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumObservationAgeSeconds = 600
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'EvidenceId', 'CandidateId',
        'BuildDescriptorBindingToken', 'InstalledExecutablePathToken', 'OwnerSidToken',
        'ExpectedOwnerSidToken', 'AclDescriptorSha256', 'AclPolicy', 'DaclProtected',
        'OwnerMatch', 'CurrentUserReadExecute', 'CurrentUserWrite', 'AdministratorsWrite',
        'SystemWrite', 'UnexpectedWriteAceCount', 'ObservedAtUtc', 'BindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required) -or
        -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-credential-helper-acl-v1') { return $false }
    foreach ($id in @($ExpectedCandidateId, $Evidence.EvidenceId)) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $id)) { return $false }
    }
    if ($Evidence.CandidateId -cne $ExpectedCandidateId -or $Evidence.EvidenceId -ceq $ExpectedCandidateId -or
        $ExpectedBuildDescriptorBindingToken -notmatch '^[a-f0-9]{64}$' -or
        $Evidence.BuildDescriptorBindingToken -cne $ExpectedBuildDescriptorBindingToken -or
        $ExpectedInstalledExecutablePathToken -notmatch '^[a-f0-9]{64}$' -or
        $Evidence.InstalledExecutablePathToken -cne $ExpectedInstalledExecutablePathToken) { return $false }
    foreach ($token in @($ExpectedCurrentUserSidToken, $Evidence.OwnerSidToken, $Evidence.ExpectedOwnerSidToken, $Evidence.AclDescriptorSha256)) {
        if ($token -isnot [string] -or $token -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    if ($Evidence.OwnerSidToken -cne $ExpectedCurrentUserSidToken -or
        $Evidence.ExpectedOwnerSidToken -cne $ExpectedCurrentUserSidToken -or
        $Evidence.AclPolicy -cne 'CurrentUserReadExecuteOnlyProtectedDacl') { return $false }
    $expectedBooleans = [ordered]@{
        DaclProtected          = $true
        OwnerMatch             = $true
        CurrentUserReadExecute = $true
        CurrentUserWrite       = $false
        AdministratorsWrite    = $true
        SystemWrite            = $true
    }
    foreach ($name in $expectedBooleans.Keys) {
        if ($Evidence.$name -isnot [bool] -or $Evidence.$name -ne $expectedBooleans[$name]) { return $false }
    }
    if (($Evidence.UnexpectedWriteAceCount -isnot [int] -and $Evidence.UnexpectedWriteAceCount -isnot [long]) -or
        [long]$Evidence.UnexpectedWriteAceCount -ne 0 -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.ObservedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc) -or
        [DateTimeOffset]::Parse($Evidence.ObservedAtUtc) -gt [DateTimeOffset]::Parse($ValidationTimeUtc) -or
        ([DateTimeOffset]::Parse($ValidationTimeUtc) - [DateTimeOffset]::Parse($Evidence.ObservedAtUtc)).TotalSeconds -gt
            $MaximumObservationAgeSeconds) { return $false }
    if ($Evidence.BindingToken -isnot [string] -or $Evidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Evidence.BindingToken -ceq (Get-CddsiCredentialHelperAclEvidenceBindingToken -Evidence $Evidence))
    }
    catch {
        return $false
    }
}

function Get-CddsiCredentialHelperInvocationContractBindingToken {
    [CmdletBinding()]
    param()

    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'contract=cddsi-credential-helper-invocation-v1'
        'protocol=cddsi-credential-helper-protocol-v1'
        'kind=DirectExecutable'
        'argumentCount=0'
        'shellInvocation=false'
        'standardInputRead=false'
        'outputs=BareTokenSingleLine,ExactJsonV1'
        'jsonProperty=token'
        'standardError=Empty'
        'exitCode=0'
        'contextEnvironmentVariable=CLAUDE_HELPER_CONTEXT'
        'helperContexts=interactive,mid-session-refresh,scheduled-task,setup-test,background'
        'defaultTimeoutSeconds=60'
        'midSessionRefreshTimeoutSeconds=20'
        'promptPolicy=Forbidden'
        'ttlSeconds=3600'
        'outputPersistence=false'
        'outputDigestPersistence=false'
    ) -join "`n")
}

function Get-CddsiCredentialHelperCandidateEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $lines = @(
        'contract=' + [string]$Evidence.ContractVersion
        'candidateId=' + [string]$Evidence.CandidateId
        'runId=' + [string]$Evidence.EvidenceRunId
        'challenge=' + [string]$Evidence.ChallengeNonce
        'build=' + [string]$Evidence.BuildDescriptorBindingToken
        'binaryPresent=' + ([string]$Evidence.BinaryPresent).ToLowerInvariant()
        'observedPe=' + [string]$Evidence.ObservedPeSha256
        'observedPeSize=' + [string]$Evidence.ObservedPeSizeBytes
        'installRoot=' + [string]$Evidence.InstallRootPathToken
        'path=' + [string]$Evidence.InstalledExecutablePathToken
        'finalResolvedPath=' + [string]$Evidence.FinalResolvedPathToken
        'pathCanonical=' + ([string]$Evidence.PathCanonical).ToLowerInvariant()
        'reparsePointCount=' + [string]$Evidence.ReparsePointCount
        'signature=' + [string]$Evidence.SignatureEvidence.BindingToken
        'acl=' + [string]$Evidence.AclEvidence.BindingToken
        'invocationContract=' + [string]$Evidence.InvocationContractBindingToken
        'protocol=' + [string]$Evidence.ProtocolVersion
        'observedAt=' + [string]$Evidence.ObservedAtUtc
        'eligible=' + ([string]$Evidence.Eligible).ToLowerInvariant()
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCredentialHelperCandidateEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedBuildDescriptor,
        [Parameter(Mandatory = $true)][string]$ExpectedCandidateId,
        [Parameter(Mandatory = $true)][string]$ExpectedEvidenceRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedChallengeNonce,
        [Parameter(Mandatory = $true)][string]$ExpectedInstallRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedInstalledExecutablePath,
        [Parameter(Mandatory = $true)][string]$ExpectedCurrentUserSidToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 3600
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'CandidateId', 'EvidenceRunId',
        'ChallengeNonce', 'BuildDescriptorBindingToken', 'BinaryPresent',
        'ObservedPeSha256', 'ObservedPeSizeBytes', 'InstallRootPathToken',
        'InstalledExecutablePathToken', 'FinalResolvedPathToken', 'PathCanonical',
        'ReparsePointCount',
        'SignatureEvidence', 'AclEvidence', 'InvocationContractBindingToken',
        'ProtocolVersion', 'ObservedAtUtc', 'Eligible', 'BindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required) -or
        -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-credential-helper-candidate-v1' -or
        -not (Test-CddsiCredentialHelperBuildDescriptor -Descriptor $ExpectedBuildDescriptor -ValidationTimeUtc $ValidationTimeUtc)) { return $false }
    foreach ($id in @($ExpectedCandidateId, $ExpectedEvidenceRunId, $ExpectedChallengeNonce)) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $id)) { return $false }
    }
    if (@(@($ExpectedCandidateId, $ExpectedEvidenceRunId, $ExpectedChallengeNonce) | Select-Object -Unique).Count -ne 3 -or
        $Evidence.CandidateId -cne $ExpectedCandidateId -or
        $Evidence.EvidenceRunId -cne $ExpectedEvidenceRunId -or
        $Evidence.ChallengeNonce -cne $ExpectedChallengeNonce -or
        $Evidence.BuildDescriptorBindingToken -cne $ExpectedBuildDescriptor.DescriptorBindingToken) { return $false }
    if ($ExpectedInstallRootPath -isnot [string] -or $ExpectedInstalledExecutablePath -isnot [string] -or
        $ExpectedInstallRootPath -notmatch '^[A-Za-z]:\\[^\\/:*?"<>|\r\n]+(?:\\[^\\/:*?"<>|\r\n]+)*$' -or
        $ExpectedInstalledExecutablePath -cne ($ExpectedInstallRootPath + '\cddsi-credential-helper.exe')) { return $false }
    try {
        if (-not [string]::Equals([System.IO.Path]::GetFullPath($ExpectedInstallRootPath),
                $ExpectedInstallRootPath, [StringComparison]::Ordinal) -or
            -not [string]::Equals([System.IO.Path]::GetFullPath($ExpectedInstalledExecutablePath),
                $ExpectedInstalledExecutablePath, [StringComparison]::Ordinal)) { return $false }
        foreach ($segment in @($ExpectedInstallRootPath.Substring(3).Split('\\'))) {
            if ([string]::IsNullOrEmpty($segment) -or $segment -ceq '.' -or $segment -ceq '..' -or
                $segment.EndsWith('.') -or $segment.EndsWith(' ') -or
                $segment -match '^(?i:(?:CON|PRN|AUX|NUL|COM[1-9¹²³]|LPT[1-9¹²³]))(?:\..*)?$') { return $false }
        }
        $expectedRootToken = Get-CddsiPathBindingToken -Path $ExpectedInstallRootPath
        $expectedPathToken = Get-CddsiPathBindingToken -Path $ExpectedInstalledExecutablePath
    }
    catch {
        return $false
    }
    if ($Evidence.BinaryPresent -isnot [bool] -or -not $Evidence.BinaryPresent -or
        $Evidence.ObservedPeSha256 -cne $ExpectedBuildDescriptor.PeSha256 -or
        ($Evidence.ObservedPeSizeBytes -isnot [int] -and $Evidence.ObservedPeSizeBytes -isnot [long]) -or
        [long]$Evidence.ObservedPeSizeBytes -ne [long]$ExpectedBuildDescriptor.PeSizeBytes -or
        $Evidence.InstallRootPathToken -cne $expectedRootToken -or
        $Evidence.InstalledExecutablePathToken -cne $expectedPathToken -or
        $Evidence.FinalResolvedPathToken -cne $expectedPathToken -or
        $Evidence.PathCanonical -isnot [bool] -or -not $Evidence.PathCanonical -or
        ($Evidence.ReparsePointCount -isnot [int] -and $Evidence.ReparsePointCount -isnot [long]) -or
        [long]$Evidence.ReparsePointCount -ne 0 -or
        $Evidence.ProtocolVersion -cne $ExpectedBuildDescriptor.ProtocolVersion -or
        $Evidence.InvocationContractBindingToken -cne (Get-CddsiCredentialHelperInvocationContractBindingToken)) { return $false }
    if (-not (Test-CddsiCredentialHelperSignatureEvidence -Evidence $Evidence.SignatureEvidence `
            -ExpectedBuildDescriptor $ExpectedBuildDescriptor -ExpectedCandidateId $ExpectedCandidateId `
            -ValidationTimeUtc $ValidationTimeUtc)) { return $false }
    if (-not (Test-CddsiCredentialHelperAclEvidence -Evidence $Evidence.AclEvidence `
            -ExpectedBuildDescriptorBindingToken $ExpectedBuildDescriptor.DescriptorBindingToken `
            -ExpectedCandidateId $ExpectedCandidateId -ExpectedInstalledExecutablePathToken $expectedPathToken `
            -ExpectedCurrentUserSidToken $ExpectedCurrentUserSidToken -ValidationTimeUtc $ValidationTimeUtc)) { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $Evidence.ObservedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)) { return $false }
    $observed = [DateTimeOffset]::Parse($Evidence.ObservedAtUtc)
    $validation = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if ($observed -gt $validation -or ($validation - $observed).TotalSeconds -gt $MaximumAgeSeconds) { return $false }
    if ($Evidence.Eligible -isnot [bool] -or -not $Evidence.Eligible -or
        $Evidence.BindingToken -isnot [string] -or $Evidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Evidence.BindingToken -ceq (Get-CddsiCredentialHelperCandidateEvidenceBindingToken -Evidence $Evidence))
    }
    catch {
        return $false
    }
}

function Get-CddsiCredentialHelperProtectedBlobEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $lines = @(
        'contract=' + [string]$Evidence.ContractVersion
        'evidenceId=' + [string]$Evidence.EvidenceId
        'candidateId=' + [string]$Evidence.CandidateId
        'candidate=' + [string]$Evidence.CandidateEvidenceBindingToken
        'operationNonce=' + [string]$Evidence.OperationNonce
        'protocol=' + [string]$Evidence.ProtocolVersion
        'path=' + [string]$Evidence.InstalledExecutablePathToken
        'pe=' + [string]$Evidence.HelperPeSha256
        'resource=' + [string]$Evidence.BlobResourceToken
        'blobHandle=' + [string]$Evidence.BlobHandleToken
        'encryptedBlob=' + [string]$Evidence.EncryptedBlobSha256
        'encryptedBlobSize=' + [string]$Evidence.EncryptedBlobSizeBytes
        'scope=' + [string]$Evidence.DpapiScope
        'currentUser=' + [string]$Evidence.CurrentUserSidToken
        'expectedCurrentUser=' + [string]$Evidence.ExpectedCurrentUserSidToken
        'owner=' + [string]$Evidence.OwnerSidToken
        'entropy=' + [string]$Evidence.EntropyContextSha256
        'acl=' + [string]$Evidence.AclDescriptorSha256
        'aclPolicy=' + [string]$Evidence.AclPolicy
        'daclProtected=' + ([string]$Evidence.DaclProtected).ToLowerInvariant()
        'ownerMatch=' + ([string]$Evidence.OwnerMatch).ToLowerInvariant()
        'unexpectedWriteAceCount=' + [string]$Evidence.UnexpectedWriteAceCount
        'plaintextPersisted=' + ([string]$Evidence.PlaintextPersisted).ToLowerInvariant()
        'readback=' + [string]$Evidence.ReadbackStatus
        'createdAt=' + [string]$Evidence.CreatedAtUtc
        'valid=' + ([string]$Evidence.Valid).ToLowerInvariant()
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCredentialHelperProtectedBlobEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedCandidateEvidence,
        [Parameter(Mandatory = $true)][string]$ExpectedOperationNonce,
        [Parameter(Mandatory = $true)][string]$ExpectedCurrentUserSidToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 3600
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'EvidenceId', 'CandidateId',
        'CandidateEvidenceBindingToken', 'OperationNonce', 'ProtocolVersion',
        'InstalledExecutablePathToken', 'HelperPeSha256', 'BlobResourceToken',
        'BlobHandleToken', 'EncryptedBlobSha256', 'EncryptedBlobSizeBytes',
        'DpapiScope', 'CurrentUserSidToken', 'ExpectedCurrentUserSidToken',
        'OwnerSidToken', 'EntropyContextSha256', 'AclDescriptorSha256', 'AclPolicy',
        'DaclProtected', 'OwnerMatch', 'UnexpectedWriteAceCount', 'PlaintextPersisted',
        'ReadbackStatus', 'CreatedAtUtc', 'Valid', 'BindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required) -or
        -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-credential-helper-protected-blob-v1' -or
        $null -eq $ExpectedCandidateEvidence -or
        $ExpectedCandidateEvidence.Eligible -isnot [bool] -or -not $ExpectedCandidateEvidence.Eligible -or
        $ExpectedCandidateEvidence.BindingToken -isnot [string] -or
        $ExpectedCandidateEvidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    foreach ($id in @($Evidence.EvidenceId, $ExpectedOperationNonce)) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $id)) { return $false }
    }
    if ($Evidence.EvidenceId -ceq $ExpectedOperationNonce -or
        $Evidence.CandidateId -cne $ExpectedCandidateEvidence.CandidateId -or
        $Evidence.CandidateEvidenceBindingToken -cne $ExpectedCandidateEvidence.BindingToken -or
        $Evidence.OperationNonce -cne $ExpectedOperationNonce -or
        $Evidence.ProtocolVersion -cne $ExpectedCandidateEvidence.ProtocolVersion -or
        $Evidence.InstalledExecutablePathToken -cne $ExpectedCandidateEvidence.InstalledExecutablePathToken -or
        $Evidence.HelperPeSha256 -cne $ExpectedCandidateEvidence.ObservedPeSha256) { return $false }
    if ($Evidence.BlobResourceToken -cne '<CREDENTIAL_BLOB:DEEPSEEK>' -or
        $Evidence.BlobHandleToken -isnot [string] -or
        $Evidence.BlobHandleToken -notmatch '^<DPAPI_BLOB:[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}>$') { return $false }
    foreach ($hash in @($Evidence.EncryptedBlobSha256, $Evidence.CurrentUserSidToken,
            $Evidence.ExpectedCurrentUserSidToken, $Evidence.OwnerSidToken,
            $Evidence.EntropyContextSha256, $Evidence.AclDescriptorSha256)) {
        if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    $expectedEntropy = Get-CddsiSupplyChainTextBindingToken -Text (@(
        $ExpectedCandidateEvidence.BindingToken,
        $ExpectedCandidateEvidence.ProtocolVersion,
        $ExpectedCandidateEvidence.InstalledExecutablePathToken,
        $ExpectedCandidateEvidence.ObservedPeSha256,
        $ExpectedCurrentUserSidToken,
        '<CREDENTIAL_BLOB:DEEPSEEK>'
    ) -join "`n")
    if ($ExpectedCurrentUserSidToken -notmatch '^[a-f0-9]{64}$' -or
        $Evidence.CurrentUserSidToken -cne $ExpectedCurrentUserSidToken -or
        $Evidence.ExpectedCurrentUserSidToken -cne $ExpectedCurrentUserSidToken -or
        $Evidence.OwnerSidToken -cne $ExpectedCurrentUserSidToken -or
        $Evidence.EntropyContextSha256 -cne $expectedEntropy -or
        $Evidence.DpapiScope -cne 'CurrentUser' -or
        $Evidence.AclPolicy -cne 'CurrentUserOnlyProtectedDacl') { return $false }
    if (($Evidence.EncryptedBlobSizeBytes -isnot [int] -and $Evidence.EncryptedBlobSizeBytes -isnot [long]) -or
        [long]$Evidence.EncryptedBlobSizeBytes -lt 1 -or [long]$Evidence.EncryptedBlobSizeBytes -gt 1048576 -or
        $Evidence.DaclProtected -isnot [bool] -or -not $Evidence.DaclProtected -or
        $Evidence.OwnerMatch -isnot [bool] -or -not $Evidence.OwnerMatch -or
        ($Evidence.UnexpectedWriteAceCount -isnot [int] -and $Evidence.UnexpectedWriteAceCount -isnot [long]) -or
        [long]$Evidence.UnexpectedWriteAceCount -ne 0 -or
        $Evidence.PlaintextPersisted -isnot [bool] -or $Evidence.PlaintextPersisted -or
        $Evidence.ReadbackStatus -cne 'VerifiedEncryptedBlob' -or
        $Evidence.Valid -isnot [bool] -or -not $Evidence.Valid) { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $Evidence.CreatedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)) { return $false }
    $created = [DateTimeOffset]::Parse($Evidence.CreatedAtUtc)
    $validation = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if ($created -gt $validation -or ($validation - $created).TotalSeconds -gt $MaximumAgeSeconds) { return $false }
    if ($Evidence.BindingToken -isnot [string] -or $Evidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Evidence.BindingToken -ceq (Get-CddsiCredentialHelperProtectedBlobEvidenceBindingToken -Evidence $Evidence))
    }
    catch {
        return $false
    }
}

function Test-CddsiCredentialHelperInvocationOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('BareTokenSingleLine', 'ExactJsonV1')][string]$OutputKind,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardOutput,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardError,
        [Parameter(Mandatory = $true)][ValidateSet('interactive', 'mid-session-refresh', 'scheduled-task', 'setup-test', 'background')][string]$HelperContext,
        [Parameter(Mandatory = $true)][bool]$PromptObserved,
        [Parameter(Mandatory = $true)][int]$ArgumentCount,
        [Parameter(Mandatory = $true)][bool]$ShellInvocation,
        [Parameter(Mandatory = $true)][bool]$StandardInputRead,
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][ValidateSet('Completed', 'TimedOut', 'Cancelled', 'Failed')][string]$InvocationStatus,
        [Parameter(Mandatory = $true)][long]$ElapsedMilliseconds,
        [Parameter(Mandatory = $true)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][int]$TtlSeconds,
        [Parameter(Mandatory = $true)][string]$ExpectedHelperPeSha256,
        [Parameter(Mandatory = $true)][string]$ObservedHelperPeSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedInstalledExecutablePathToken,
        [Parameter(Mandatory = $true)][string]$ObservedInstalledExecutablePathToken
    )

    $expectedTimeoutSeconds = if ($HelperContext -ceq 'mid-session-refresh') { 20 } else { 60 }
    if ($ArgumentCount -ne 0 -or $ShellInvocation -or $StandardInputRead -or $PromptObserved -or
        $ExitCode -ne 0 -or $InvocationStatus -cne 'Completed' -or
        $TimeoutSeconds -ne $expectedTimeoutSeconds -or $TtlSeconds -ne 3600 -or
        $ElapsedMilliseconds -lt 0 -or $ElapsedMilliseconds -gt ([long]$expectedTimeoutSeconds * 1000L) -or
        -not [string]::IsNullOrEmpty($StandardError)) { return $false }
    foreach ($hash in @($ExpectedHelperPeSha256, $ObservedHelperPeSha256,
            $ExpectedInstalledExecutablePathToken, $ObservedInstalledExecutablePathToken)) {
        if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    if ($ObservedHelperPeSha256 -cne $ExpectedHelperPeSha256 -or
        $ObservedInstalledExecutablePathToken -cne $ExpectedInstalledExecutablePathToken) { return $false }
    if ($OutputKind -ceq 'BareTokenSingleLine') {
        if ($StandardOutput -match '[\r\n]' -or $StandardOutput.StartsWith('{')) { return $false }
        return (Test-CddsiDeepSeekApiKeyFormat -ApiKey $StandardOutput)
    }
    if ($StandardOutput -notmatch '^\{"token":"(?<TokenValue>[^"\\\r\n]+)"\}$') { return $false }
    return (Test-CddsiDeepSeekApiKeyFormat -ApiKey $Matches.TokenValue)
}

function Get-CddsiCredentialHelperInvocationEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $lines = @(
        'contract=' + [string]$Evidence.ContractVersion
        'invocationId=' + [string]$Evidence.InvocationId
        'candidateId=' + [string]$Evidence.CandidateId
        'candidate=' + [string]$Evidence.CandidateEvidenceBindingToken
        'challenge=' + [string]$Evidence.InvocationChallenge
        'protocol=' + [string]$Evidence.ProtocolVersion
        'kind=' + [string]$Evidence.InvocationKind
        'helperContext=' + [string]$Evidence.HelperContext
        'promptObserved=' + ([string]$Evidence.PromptObserved).ToLowerInvariant()
        'argumentCount=' + [string]$Evidence.ArgumentCount
        'shellInvocation=' + ([string]$Evidence.ShellInvocation).ToLowerInvariant()
        'standardInputRead=' + ([string]$Evidence.StandardInputRead).ToLowerInvariant()
        'outputKind=' + [string]$Evidence.OutputKind
        'outputValidated=' + ([string]$Evidence.OutputValidated).ToLowerInvariant()
        'tokenLength=' + [string]$Evidence.TokenLength
        'outputPersisted=' + ([string]$Evidence.OutputPersisted).ToLowerInvariant()
        'outputDigestPersisted=' + ([string]$Evidence.OutputDigestPersisted).ToLowerInvariant()
        'standardErrorEmpty=' + ([string]$Evidence.StandardErrorEmpty).ToLowerInvariant()
        'exitCode=' + [string]$Evidence.ExitCode
        'status=' + [string]$Evidence.InvocationStatus
        'elapsed=' + [string]$Evidence.ElapsedMilliseconds
        'timeout=' + [string]$Evidence.TimeoutSeconds
        'ttl=' + [string]$Evidence.TtlSeconds
        'pe=' + [string]$Evidence.ObservedPeSha256
        'path=' + [string]$Evidence.InstalledExecutablePathToken
        'startedAt=' + [string]$Evidence.StartedAtUtc
        'completedAt=' + [string]$Evidence.CompletedAtUtc
        'valid=' + ([string]$Evidence.Valid).ToLowerInvariant()
    )
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCredentialHelperInvocationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedCandidateEvidence,
        [Parameter(Mandatory = $true)][string]$ExpectedInvocationId,
        [Parameter(Mandatory = $true)][string]$ExpectedInvocationChallenge,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 3600)][int]$MaximumAgeSeconds = 300
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'InvocationId', 'CandidateId',
        'CandidateEvidenceBindingToken', 'InvocationChallenge', 'ProtocolVersion',
        'InvocationKind', 'HelperContext', 'PromptObserved', 'ArgumentCount',
        'ShellInvocation', 'StandardInputRead',
        'OutputKind', 'OutputValidated', 'TokenLength', 'OutputPersisted',
        'OutputDigestPersisted', 'StandardErrorEmpty', 'ExitCode', 'InvocationStatus',
        'ElapsedMilliseconds', 'TimeoutSeconds', 'TtlSeconds', 'ObservedPeSha256',
        'InstalledExecutablePathToken', 'StartedAtUtc', 'CompletedAtUtc', 'Valid',
        'BindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required) -or
        -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-credential-helper-invocation-v1' -or
        $null -eq $ExpectedCandidateEvidence -or
        $ExpectedCandidateEvidence.Eligible -isnot [bool] -or -not $ExpectedCandidateEvidence.Eligible -or
        $ExpectedCandidateEvidence.BindingToken -isnot [string] -or
        $ExpectedCandidateEvidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    foreach ($id in @($ExpectedInvocationId, $ExpectedInvocationChallenge)) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $id)) { return $false }
    }
    if ($ExpectedInvocationId -ceq $ExpectedInvocationChallenge -or
        $Evidence.InvocationId -cne $ExpectedInvocationId -or
        $Evidence.InvocationChallenge -cne $ExpectedInvocationChallenge -or
        $Evidence.CandidateId -cne $ExpectedCandidateEvidence.CandidateId -or
        $Evidence.CandidateEvidenceBindingToken -cne $ExpectedCandidateEvidence.BindingToken -or
        $Evidence.ProtocolVersion -cne $ExpectedCandidateEvidence.ProtocolVersion -or
        $Evidence.ObservedPeSha256 -cne $ExpectedCandidateEvidence.ObservedPeSha256 -or
        $Evidence.InstalledExecutablePathToken -cne $ExpectedCandidateEvidence.InstalledExecutablePathToken) { return $false }
    $allowedContexts = @('interactive', 'mid-session-refresh', 'scheduled-task', 'setup-test', 'background')
    if ($Evidence.InvocationKind -cne 'DirectExecutable' -or $Evidence.HelperContext -isnot [string] -or
        $allowedContexts -cnotcontains $Evidence.HelperContext -or
        $Evidence.PromptObserved -isnot [bool] -or $Evidence.PromptObserved -or
        $Evidence.ArgumentCount -ne 0 -or
        $Evidence.ShellInvocation -isnot [bool] -or $Evidence.ShellInvocation -or
        $Evidence.StandardInputRead -isnot [bool] -or $Evidence.StandardInputRead -or
        $Evidence.OutputKind -cnotin @('BareTokenSingleLine', 'ExactJsonV1') -or
        $Evidence.OutputValidated -isnot [bool] -or -not $Evidence.OutputValidated -or
        ($Evidence.TokenLength -isnot [int] -and $Evidence.TokenLength -isnot [long]) -or
        [long]$Evidence.TokenLength -lt 20 -or [long]$Evidence.TokenLength -gt 512 -or
        $Evidence.OutputPersisted -isnot [bool] -or $Evidence.OutputPersisted -or
        $Evidence.OutputDigestPersisted -isnot [bool] -or $Evidence.OutputDigestPersisted -or
        $Evidence.StandardErrorEmpty -isnot [bool] -or -not $Evidence.StandardErrorEmpty) { return $false }
    $expectedTimeoutSeconds = if ($Evidence.HelperContext -ceq 'mid-session-refresh') { 20 } else { 60 }
    if ($Evidence.ExitCode -ne 0 -or $Evidence.InvocationStatus -cne 'Completed' -or
        ($Evidence.ElapsedMilliseconds -isnot [int] -and $Evidence.ElapsedMilliseconds -isnot [long]) -or
        [long]$Evidence.ElapsedMilliseconds -lt 0 -or
        [long]$Evidence.ElapsedMilliseconds -gt ([long]$expectedTimeoutSeconds * 1000L) -or
        $Evidence.TimeoutSeconds -ne $expectedTimeoutSeconds -or $Evidence.TtlSeconds -ne 3600 -or
        $Evidence.Valid -isnot [bool] -or -not $Evidence.Valid) { return $false }
    foreach ($time in @($Evidence.StartedAtUtc, $Evidence.CompletedAtUtc, $ValidationTimeUtc)) {
        if (-not (Test-CddsiUtcTimestampValue -Value $time)) { return $false }
    }
    $started = [DateTimeOffset]::Parse($Evidence.StartedAtUtc)
    $completed = [DateTimeOffset]::Parse($Evidence.CompletedAtUtc)
    $validation = [DateTimeOffset]::Parse($ValidationTimeUtc)
    $wallMilliseconds = ($completed - $started).TotalMilliseconds
    if ($completed -lt $started -or $wallMilliseconds -gt ([long]$expectedTimeoutSeconds * 1000L) -or
        [Math]::Abs($wallMilliseconds - [long]$Evidence.ElapsedMilliseconds) -gt 1000 -or
        $completed -gt $validation -or ($validation - $completed).TotalSeconds -gt $MaximumAgeSeconds) { return $false }
    if ($Evidence.BindingToken -isnot [string] -or $Evidence.BindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Evidence.BindingToken -ceq (Get-CddsiCredentialHelperInvocationEvidenceBindingToken -Evidence $Evidence))
    }
    catch {
        return $false
    }
}
