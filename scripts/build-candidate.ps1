[CmdletBinding()]
param(
    [switch]$ImportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$entryCandidateImportOnly = $PSBoundParameters.ContainsKey('ImportOnly') -and $ImportOnly.IsPresent
$scriptRoot = $PSScriptRoot
$repositoryRoot = Split-Path -Parent $scriptRoot

# This trusted-harness entry point composes existing pure release contracts and
# the release builder's sandboxed file/ZIP helpers. Imports define functions
# only; no candidate is built at load time.
. (Join-Path $repositoryRoot 'lib\bootstrap.ps1')
Import-CddsiLibraries
. (Join-Path $repositoryRoot 'lib\release-facts.ps1')
. (Join-Path $repositoryRoot 'lib\credential-helper-release.ps1')
. (Join-Path $repositoryRoot 'lib\release-artifact.ps1')
. (Join-Path $scriptRoot 'build-release.ps1') -ImportOnly

$script:CddsiCandidateOutputMarkerName = '.cddsi-candidate-output.json'

function Get-CddsiCandidateBytesSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-CddsiCandidateFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Get-CddsiCandidateCanonicalJsonBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Value)

    $json = (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Value) + "`n"
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes($json)
}

function Assert-CddsiCandidateOwnedSandbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Sandbox)

    if (-not (Test-CddsiExactPropertySet -InputObject $Sandbox -Expected @(
        'Root', 'TempBase', 'RunId', 'OwnershipToken', 'MarkerPath', 'Paths', 'CanaryValue',
        'CanaryPaths', 'CanaryFileSha256'
    ))) { throw 'Candidate build requires an exact owner-marked HostSandbox.' }
    if (-not (Test-Path -LiteralPath $Sandbox.Root -PathType Container)) {
        throw 'Candidate HostSandbox is unavailable.'
    }
    Assert-CddsiNoReparsePath -Path $Sandbox.Root -StopRoot $Sandbox.TempBase
    $null = Read-CddsiOwnerMarker -Sandbox $Sandbox
}

function Assert-CddsiCandidatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$MustExist,
        [switch]$MustNotExist,
        [switch]$Container
    )

    $full = Get-CddsiCanonicalPath -Path $Path
    if (-not (Test-CddsiPathWithinRoot -Path $full -Root $Sandbox.Root)) {
        throw 'Candidate path escapes the owner-marked sandbox.'
    }
    Assert-CddsiNoReparsePath -Path $full -StopRoot $Sandbox.Root -PathMayNotExist:(-not (Test-Path -LiteralPath $full))
    if ($MustExist -and -not (Test-Path -LiteralPath $full -PathType $(if ($Container) { 'Container' } else { 'Leaf' }))) {
        throw 'Candidate input path is unavailable.'
    }
    if ($MustNotExist -and (Test-Path -LiteralPath $full)) {
        throw 'Candidate output path must not already exist.'
    }
    return $full
}

function New-CddsiCandidateOutputRoot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$OutputRoot
    )

    $full = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $OutputRoot -MustNotExist
    [void][System.IO.Directory]::CreateDirectory($full)
    Assert-CddsiNoReparsePath -Path $full -StopRoot $Sandbox.Root
    $marker = [pscustomobject][ordered]@{
        SchemaVersion            = 1
        MarkerType               = 'CddsiCandidateOutputOwner'
        RunId                    = $Sandbox.RunId
        OwnershipToken           = $Sandbox.OwnershipToken
        SandboxRootBindingSha256 = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($Sandbox.Root).ToUpperInvariant())
        OutputRootBindingSha256  = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($full).ToUpperInvariant())
    }
    Write-CddsiUtf8CreateNew -Path (Join-Path $full $script:CddsiCandidateOutputMarkerName) `
        -Content ((ConvertTo-CddsiVmCalibrationCanonicalJson -Value $marker) + "`n")
    return $full
}

function Assert-CddsiCandidateOutputOwner {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$OutputRoot
    )

    $full = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $OutputRoot -MustExist -Container
    $markerPath = Join-Path $full $script:CddsiCandidateOutputMarkerName
    Assert-CddsiNoReparsePath -Path $markerPath -StopRoot $Sandbox.Root
    if (-not [System.IO.File]::Exists($markerPath)) { throw 'Candidate output ownership marker is missing.' }
    $marker = [System.IO.File]::ReadAllText($markerPath, (New-Object System.Text.UTF8Encoding($false))) | ConvertFrom-Json
    if (-not (Test-CddsiExactPropertySet -InputObject $marker -Expected @(
        'SchemaVersion', 'MarkerType', 'RunId', 'OwnershipToken', 'SandboxRootBindingSha256', 'OutputRootBindingSha256'
    ))) { throw 'Candidate output ownership marker schema drifted.' }
    if ($marker.SchemaVersion -ne 1 -or $marker.MarkerType -cne 'CddsiCandidateOutputOwner' -or
        $marker.RunId -cne $Sandbox.RunId -or $marker.OwnershipToken -cne $Sandbox.OwnershipToken -or
        $marker.SandboxRootBindingSha256 -cne (Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($Sandbox.Root).ToUpperInvariant())) -or
        $marker.OutputRootBindingSha256 -cne (Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($full).ToUpperInvariant()))) {
        throw 'Candidate output ownership marker is invalid.'
    }
    return $full
}

function Remove-CddsiCandidateOwnedOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$OutputRoot
    )

    $full = Assert-CddsiCandidateOutputOwner -Sandbox $Sandbox -OutputRoot $OutputRoot
    $queue = [System.Collections.Generic.Queue[string]]::new()
    $queue.Enqueue($full)
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @([System.IO.DirectoryInfo]::new($directory).EnumerateFileSystemInfos())) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Candidate cleanup refuses a reparse point.'
            }
            if ($item -is [System.IO.DirectoryInfo]) { $queue.Enqueue($item.FullName) }
        }
    }
    [System.IO.Directory]::Delete($full, $true)
}

function Get-CddsiCandidateSourceContentEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string[]]$RelativePaths
    )

    Assert-CddsiCandidateOwnedSandbox -Sandbox $Sandbox
    $sourceFull = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $SourceRoot -MustExist -Container
    $canonicalPaths = @($RelativePaths | ForEach-Object { ConvertTo-CddsiReleaseRelativePath -Path $_ })
    if ($canonicalPaths.Count -lt 1 -or @($canonicalPaths | Select-Object -Unique).Count -ne $canonicalPaths.Count) {
        throw 'Candidate content paths must be a non-empty unique set.'
    }
    $orderedPaths = [string[]]@($canonicalPaths)
    [Array]::Sort($orderedPaths, [StringComparer]::Ordinal)
    $items = @(Get-CddsiReleasePackageItems -RepositoryRoot $sourceFull -PackageFiles $orderedPaths)
    $hashes = Get-CddsiReleaseContentHashes -Items $items
    $entries = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $items.Count; $index++) {
        $item = $items[$index]
        $entries.Add([pscustomobject][ordered]@{
            Ordinal     = $index
            Path        = $item.RelativePath
            Sha256      = [string]$hashes[$item.RelativePath]
            LengthBytes = [long]([System.IO.FileInfo]::new($item.FullPath).Length)
        })
    }
    return [object[]]$entries.ToArray()
}

function Assert-CddsiCandidateContentEntries {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ExpectedEntries,
        [Parameter(Mandatory = $true)]$ObservedEntries
    )

    $expected = @($ExpectedEntries)
    $observed = @($ObservedEntries)
    if ($expected.Count -lt 1 -or $expected.Count -ne $observed.Count) {
        throw 'Candidate content observation count drifted.'
    }
    for ($index = 0; $index -lt $expected.Count; $index++) {
        foreach ($entry in @($expected[$index], $observed[$index])) {
            if (-not (Test-CddsiExactPropertySet -InputObject $entry -Expected @('Ordinal', 'Path', 'Sha256', 'LengthBytes'))) {
                throw 'Candidate content entry schema drifted.'
            }
        }
        foreach ($name in @('Ordinal', 'Path', 'Sha256', 'LengthBytes')) {
            if ($expected[$index].$name -cne $observed[$index].$name) {
                throw 'Candidate content observation differs from the supplied frozen entry set.'
            }
        }
    }
}

function Assert-CddsiCandidateFrozenFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$FrozenFacts,
        [Parameter(Mandatory = $true)]$CommittedFreezeState,
        [Parameter(Mandatory = $true)]$FreezeCommitReceipt,
        [Parameter(Mandatory = $true)]$FreezeStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$FreezeTransactionId,
        [Parameter(Mandatory = $true)][string]$FreezeProposalNonce,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $FrozenFacts -Expected @(
        'SchemaVersion', 'ContractVersion', 'Purpose', 'SourceBindings', 'OsImage', 'Msix', 'Git',
        'CredentialHelper', 'Chooser', 'HkcuManagedPolicy', 'FactsBindingToken'
    )) -or $FrozenFacts.SchemaVersion -ne 1 -or
        $FrozenFacts.ContractVersion -cne 'cddsi-frozen-release-facts-v1' -or
        $FrozenFacts.Purpose -cne 'P10B_RELEASE_BUILD_INPUT_ONLY' -or
        $FrozenFacts.FactsBindingToken -cne (Get-CddsiFrozenReleaseFactsBindingToken -Facts $FrozenFacts)) {
        throw 'Candidate build requires structurally valid frozen release facts.'
    }
    $factsJson = ConvertTo-CddsiVmCalibrationCanonicalJson -Value $FrozenFacts
    if ($factsJson -match '(?i)NOT_OBSERVED|"(?:Status|Result)"\s*:\s*"(?:FAILED|FAIL)"' -or
        @(Find-CddsiPotentialSecrets -Content $factsJson -Source '<candidate-frozen-facts>').Count -ne 0) {
        throw 'Candidate frozen facts are incomplete or unsafe.'
    }
    $source = $FrozenFacts.SourceBindings
    if (-not (Test-CddsiExactPropertySet -InputObject $source -Expected @(
        'SchemaVersion', 'SessionAnchorToken', 'SessionBindingToken', 'EvidenceBindingToken',
        'ConsumptionStateKeySha256', 'ConsumptionStateBindingToken',
        'ConsumptionCommitReceiptBindingToken', 'ConsumptionId', 'ConsumptionRevision',
        'EvidenceCompletedAtUtc'
    )) -or $source.SchemaVersion -ne 1) {
        throw 'Candidate frozen facts source bindings do not match the committed CAS contract.'
    }
    if (-not (Test-CddsiCommittedReleaseFactsFreezeReceipt -FreezeState $CommittedFreezeState `
        -CommitReceipt $FreezeCommitReceipt -StoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey `
        -ExpectedSessionAnchorToken $source.SessionAnchorToken `
        -ExpectedSessionBindingToken $source.SessionBindingToken `
        -ExpectedEvidenceBindingToken $source.EvidenceBindingToken `
        -ExpectedConsumptionStateKeySha256 $source.ConsumptionStateKeySha256 `
        -ExpectedConsumptionStateBindingToken $source.ConsumptionStateBindingToken `
        -ExpectedConsumptionCommitReceiptBindingToken $source.ConsumptionCommitReceiptBindingToken `
        -ExpectedConsumptionId $source.ConsumptionId `
        -ExpectedFreezeId $CommittedFreezeState.FreezeId `
        -ExpectedFactsBindingToken $FrozenFacts.FactsBindingToken `
        -ExpectedTransactionId $FreezeTransactionId -ExpectedProposalNonce $FreezeProposalNonce `
        -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'Candidate frozen facts do not match a current committed freeze receipt.'
    }
}

function Test-CddsiCandidateSignerIdentity {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$SignerIdentity)

    try {
        return (
            (Test-CddsiExactPropertySet -InputObject $SignerIdentity -Expected @(
                'SchemaVersion', 'ContractVersion', 'IdentityType', 'Subject', 'CertificateSha256', 'KeyId'
            )) -and $SignerIdentity.SchemaVersion -eq 1 -and
            $SignerIdentity.ContractVersion -ceq 'cddsi-release-signer-identity-v1' -and
            $SignerIdentity.IdentityType -ceq 'X509' -and
            $SignerIdentity.Subject -is [string] -and $SignerIdentity.Subject.Length -ge 1 -and
            $SignerIdentity.Subject.Length -le 256 -and $SignerIdentity.Subject -notmatch '[\x00-\x1F\x7F\{\}\[\]]' -and
            $SignerIdentity.Subject -notmatch '(?i)(?:[A-Z]:\\|\\\\|/Users/|/home/)' -and
            @(Find-CddsiPotentialSecrets -Content $SignerIdentity.Subject -Source '<candidate-signer>').Count -eq 0 -and
            (Test-CddsiReleaseSha256Value -Value $SignerIdentity.CertificateSha256) -and
            (Test-CddsiSafeIdentifierValue -Value $SignerIdentity.KeyId -MaxLength 128)
        )
    }
    catch { return $false }
}

function Copy-CddsiCandidateSignatureTrustPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$SignatureTrustPolicy)

    if (-not (Test-CddsiExactPropertySet -InputObject $SignatureTrustPolicy -Expected @(
        'SchemaVersion', 'ContractVersion', 'SignatureAlgorithm', 'ExpectedSubject',
        'ExpectedCertificateSha256', 'ExpectedPublicKeySha256', 'ExpectedKeyId',
        'SigningRequestId', 'SigningNonce', 'MaximumSignatureAgeSeconds'
    ))) {
        throw 'Candidate signature trust policy does not match the exact external-anchor contract.'
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = $SignatureTrustPolicy.SchemaVersion
        ContractVersion = $SignatureTrustPolicy.ContractVersion
        SignatureAlgorithm = $SignatureTrustPolicy.SignatureAlgorithm
        ExpectedSubject = $SignatureTrustPolicy.ExpectedSubject
        ExpectedCertificateSha256 = $SignatureTrustPolicy.ExpectedCertificateSha256
        ExpectedPublicKeySha256 = $SignatureTrustPolicy.ExpectedPublicKeySha256
        ExpectedKeyId = $SignatureTrustPolicy.ExpectedKeyId
        SigningRequestId = $SignatureTrustPolicy.SigningRequestId
        SigningNonce = $SignatureTrustPolicy.SigningNonce
        MaximumSignatureAgeSeconds = $SignatureTrustPolicy.MaximumSignatureAgeSeconds
    }
}

function Get-CddsiCandidateSigningRequestBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Request)

    $values = @(
        'cddsi-candidate-sidecar-signing-request-v1', $Request.SchemaVersion, $Request.ContractVersion,
        $Request.Purpose, $Request.Publishable,
        $Request.RequestId, $Request.ArtifactProfile, $Request.ArtifactVersion, $Request.CommitId,
        $Request.FinalZipSha256, $Request.FinalZipLengthBytes, $Request.ContentDigest,
        $Request.FrozenFactsToken, $Request.ReleaseFactsStateBindingToken,
        $Request.ReleaseFactsCommitReceiptBindingToken, $Request.ReleaseFactsStoreAuthorityFingerprintSha256,
        $Request.ManifestBindingToken, $Request.DetachedSidecarName,
        $Request.ExpectedSignatureTrustPolicy.SchemaVersion,
        $Request.ExpectedSignatureTrustPolicy.ContractVersion,
        $Request.ExpectedSignatureTrustPolicy.SignatureAlgorithm,
        $Request.ExpectedSignatureTrustPolicy.ExpectedSubject,
        $Request.ExpectedSignatureTrustPolicy.ExpectedCertificateSha256,
        $Request.ExpectedSignatureTrustPolicy.ExpectedPublicKeySha256,
        $Request.ExpectedSignatureTrustPolicy.ExpectedKeyId,
        $Request.ExpectedSignatureTrustPolicy.SigningRequestId,
        $Request.ExpectedSignatureTrustPolicy.SigningNonce,
        $Request.ExpectedSignatureTrustPolicy.MaximumSignatureAgeSeconds,
        $Request.ClaimsBindingToken, $Request.ClaimsBytesBase64, $Request.ClaimsLengthBytes,
        $Request.SignedAtUtc, $Request.SigningTimeKind, $Request.SignerIdentity.SchemaVersion,
        $Request.SignerIdentity.ContractVersion, $Request.SignerIdentity.IdentityType,
        $Request.SignerIdentity.Subject, $Request.SignerIdentity.CertificateSha256,
        $Request.SignerIdentity.KeyId, $Request.RequestedAtUtc
    )
    return Get-CddsiSupplyChainTextBindingToken -Text (@($values | ForEach-Object {
        ConvertTo-CddsiStagePolicyBindingField -Value $_
    }) -join "`n")
}

function Test-CddsiCandidateSigningRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Request,
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $Request -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'Publishable', 'RequestId', 'ArtifactProfile', 'ArtifactVersion',
            'CommitId', 'FinalZipSha256', 'FinalZipLengthBytes', 'ContentDigest', 'FrozenFactsToken',
            'ReleaseFactsStateBindingToken', 'ReleaseFactsCommitReceiptBindingToken',
            'ReleaseFactsStoreAuthorityFingerprintSha256',
            'ManifestBindingToken', 'DetachedSidecarName', 'ExpectedSignatureTrustPolicy',
            'SignerIdentity', 'ClaimsBindingToken',
            'ClaimsBytesBase64', 'ClaimsLengthBytes', 'SignedAtUtc', 'SigningTimeKind',
            'RequestedAtUtc', 'RequestBindingToken'
        )) -or -not (Test-CddsiReleaseContentManifest -Manifest $Manifest `
                -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy) -or
            (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Request.ExpectedSignatureTrustPolicy) -cne
                (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $ExpectedSignatureTrustPolicy) -or
            $Request.SchemaVersion -ne 1 -or
            $Request.ContractVersion -cne 'cddsi-candidate-sidecar-signing-request-v1' -or
            $Request.Purpose -cne 'HOST_SANDBOX_SIMULATION_ONLY' -or
            $Request.Publishable -isnot [bool] -or $Request.Publishable -or
            -not (Test-CddsiCanonicalUuidValue -Value $Request.RequestId) -or
            $Request.ArtifactProfile -cne $Manifest.ArtifactProfile -or
            $Request.ArtifactVersion -cne $Manifest.ArtifactVersion -or
            $Request.CommitId -cne $Manifest.CommitId -or
            $Request.ContentDigest -cne $Manifest.ContentDigest -or
            $Request.FrozenFactsToken -cne $Manifest.FrozenFactsToken -or
            -not (Test-CddsiReleaseSha256Value -Value $Request.ReleaseFactsStateBindingToken) -or
            -not (Test-CddsiReleaseSha256Value -Value $Request.ReleaseFactsCommitReceiptBindingToken) -or
            -not (Test-CddsiReleaseSha256Value -Value $Request.ReleaseFactsStoreAuthorityFingerprintSha256) -or
            $Request.ManifestBindingToken -cne $Manifest.ManifestBindingToken -or
            $Request.DetachedSidecarName -cne $Manifest.DetachedSidecarName -or
            $Request.RequestId -cne $Request.ExpectedSignatureTrustPolicy.SigningRequestId -or
            $Request.SignerIdentity.Subject -cne $Request.ExpectedSignatureTrustPolicy.ExpectedSubject -or
            $Request.SignerIdentity.CertificateSha256 -cne $Request.ExpectedSignatureTrustPolicy.ExpectedCertificateSha256 -or
            $Request.SignerIdentity.KeyId -cne $Request.ExpectedSignatureTrustPolicy.ExpectedKeyId -or
            -not (Test-CddsiReleaseSha256Value -Value $Request.FinalZipSha256) -or
            ($Request.FinalZipLengthBytes -isnot [int] -and $Request.FinalZipLengthBytes -isnot [long]) -or
            [long]$Request.FinalZipLengthBytes -lt 1 -or
            -not (Test-CddsiCandidateSignerIdentity -SignerIdentity $Request.SignerIdentity) -or
            $Request.ClaimsBytesBase64 -isnot [string] -or $Request.ClaimsBytesBase64.Length -lt 1 -or
            $Request.ClaimsBytesBase64.Length -gt 32768 -or
            ($Request.ClaimsLengthBytes -isnot [int] -and $Request.ClaimsLengthBytes -isnot [long]) -or
            [long]$Request.ClaimsLengthBytes -lt 1 -or
            -not (Test-CddsiUtcTimestampValue -Value $Request.SignedAtUtc) -or
            $Request.SignedAtUtc -cne $Request.RequestedAtUtc -or
            $Request.SigningTimeKind -cne 'SIGNER_ASSERTED_NO_RFC3161' -or
            -not (Test-CddsiUtcTimestampValue -Value $Request.RequestedAtUtc)) { return $false }
        $draft = [pscustomobject][ordered]@{
            SchemaVersion = 2; ContractVersion = 'cddsi-release-sidecar-payload-v2'
            FinalZipSha256 = $Request.FinalZipSha256; ContentDigest = $Request.ContentDigest
            ArtifactProfile = $Request.ArtifactProfile; ArtifactVersion = $Request.ArtifactVersion
            CommitId = $Request.CommitId; FrozenFactsToken = $Request.FrozenFactsToken
            ManifestBindingToken = $Request.ManifestBindingToken
            SignatureTrustPolicy = $Request.ExpectedSignatureTrustPolicy; SignerIdentity = $Request.SignerIdentity
            SignatureEvidence = [pscustomobject][ordered]@{
                SchemaVersion = 2; ContractVersion = 'cddsi-release-detached-signature-evidence-v2'
                SignatureAlgorithm = 'RSA-PSS-SHA256'; SignedAtUtc = $Request.SignedAtUtc
                SigningTimeKind = $Request.SigningTimeKind
            }
        }
        $claimsBytes = ConvertTo-CddsiReleaseSidecarClaimsBytes -Payload $draft
        return (
            $Request.ClaimsBindingToken -ceq (Get-CddsiReleaseSidecarClaimsBindingToken -Payload $draft) -and
            [long]$Request.ClaimsLengthBytes -eq [long]$claimsBytes.Length -and
            $Request.ClaimsBytesBase64 -ceq [Convert]::ToBase64String($claimsBytes) -and
            $Request.RequestBindingToken -ceq (Get-CddsiCandidateSigningRequestBindingToken -Request $Request)
        )
    }
    catch { return $false }
}

function Get-CddsiCandidateBuildBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$BuildResult)

    $values = @(
        'cddsi-candidate-build-result-v1', $BuildResult.SchemaVersion, $BuildResult.ContractVersion,
        $BuildResult.Plane, $BuildResult.EnvironmentTier, $BuildResult.Simulation,
        $BuildResult.Publishable, $BuildResult.PublicationBlockCode,
        $BuildResult.BuildId, $BuildResult.ArtifactProfile, $BuildResult.ArtifactVersion,
        $BuildResult.CommitId, $BuildResult.FrozenFactsToken, $BuildResult.FreezeStateBindingToken,
        $BuildResult.FreezeCommitReceiptBindingToken, $BuildResult.FreezeStoreAuthorityFingerprintSha256,
        $BuildResult.ExpectedSignatureTrustPolicy.SchemaVersion,
        $BuildResult.ExpectedSignatureTrustPolicy.ContractVersion,
        $BuildResult.ExpectedSignatureTrustPolicy.SignatureAlgorithm,
        $BuildResult.ExpectedSignatureTrustPolicy.ExpectedSubject,
        $BuildResult.ExpectedSignatureTrustPolicy.ExpectedCertificateSha256,
        $BuildResult.ExpectedSignatureTrustPolicy.ExpectedPublicKeySha256,
        $BuildResult.ExpectedSignatureTrustPolicy.ExpectedKeyId,
        $BuildResult.ExpectedSignatureTrustPolicy.SigningRequestId,
        $BuildResult.ExpectedSignatureTrustPolicy.SigningNonce,
        $BuildResult.ExpectedSignatureTrustPolicy.MaximumSignatureAgeSeconds,
        $BuildResult.Manifest.ManifestBindingToken, $BuildResult.FinalZipSha256,
        $BuildResult.FinalZipLengthBytes, $BuildResult.HelperBuildDescriptorBindingToken,
        $BuildResult.HelperSignatureEvidenceBindingToken, $BuildResult.SbomSha256,
        $BuildResult.SigningRequest.RequestBindingToken, $BuildResult.OutputRootBindingSha256
    )
    return Get-CddsiSupplyChainTextBindingToken -Text (@($values | ForEach-Object {
        ConvertTo-CddsiStagePolicyBindingField -Value $_
    }) -join "`n")
}

function Test-CddsiCandidateBuildResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$BuildResult,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy
    )

    try {
        return (
            (Test-CddsiExactPropertySet -InputObject $BuildResult -Expected @(
                'SchemaVersion', 'ContractVersion', 'Plane', 'EnvironmentTier', 'Simulation',
                'Publishable', 'PublicationBlockCode', 'BuildId', 'ArtifactProfile', 'ArtifactVersion',
                'CommitId', 'FrozenFactsToken', 'FreezeStateBindingToken',
                'FreezeCommitReceiptBindingToken', 'FreezeStoreAuthorityFingerprintSha256',
                'ExpectedSignatureTrustPolicy', 'Manifest', 'ZipPath',
                'FinalZipSha256', 'FinalZipLengthBytes', 'HelperBuildDescriptorBindingToken',
                'HelperSignatureEvidenceBindingToken', 'SbomSha256', 'SigningRequest',
                'OutputRoot', 'OutputRootBindingSha256', 'BuildBindingToken'
            )) -and $BuildResult.SchemaVersion -eq 1 -and
            $BuildResult.ContractVersion -ceq 'cddsi-candidate-build-result-v1' -and
            $BuildResult.Plane -ceq 'TrustedHarness' -and
            $BuildResult.EnvironmentTier -ceq 'HostSandbox' -and
            $BuildResult.Simulation -is [bool] -and $BuildResult.Simulation -and
            $BuildResult.Publishable -is [bool] -and -not $BuildResult.Publishable -and
            $BuildResult.PublicationBlockCode -ceq 'REAL_STORE_AND_SIGNING_RECEIPTS_REQUIRED' -and
            (Test-CddsiCanonicalUuidValue -Value $BuildResult.BuildId) -and
            (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $BuildResult.ExpectedSignatureTrustPolicy) -ceq
                (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $ExpectedSignatureTrustPolicy) -and
            (Test-CddsiReleaseContentManifest -Manifest $BuildResult.Manifest `
                -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy) -and
            $BuildResult.ArtifactProfile -ceq $BuildResult.Manifest.ArtifactProfile -and
            $BuildResult.ArtifactVersion -ceq $BuildResult.Manifest.ArtifactVersion -and
            $BuildResult.CommitId -ceq $BuildResult.Manifest.CommitId -and
            $BuildResult.FrozenFactsToken -ceq $BuildResult.Manifest.FrozenFactsToken -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.FreezeStateBindingToken) -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.FreezeCommitReceiptBindingToken) -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.FreezeStoreAuthorityFingerprintSha256) -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.FinalZipSha256) -and
            [long]$BuildResult.FinalZipLengthBytes -gt 0 -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.HelperBuildDescriptorBindingToken) -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.HelperSignatureEvidenceBindingToken) -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.SbomSha256) -and
            (Test-CddsiCandidateSigningRequest -Request $BuildResult.SigningRequest -Manifest $BuildResult.Manifest `
                -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy) -and
            $BuildResult.SigningRequest.FinalZipSha256 -ceq $BuildResult.FinalZipSha256 -and
            $BuildResult.SigningRequest.FinalZipLengthBytes -eq $BuildResult.FinalZipLengthBytes -and
            $BuildResult.SigningRequest.ReleaseFactsStateBindingToken -ceq $BuildResult.FreezeStateBindingToken -and
            $BuildResult.SigningRequest.ReleaseFactsCommitReceiptBindingToken -ceq $BuildResult.FreezeCommitReceiptBindingToken -and
            $BuildResult.SigningRequest.ReleaseFactsStoreAuthorityFingerprintSha256 -ceq $BuildResult.FreezeStoreAuthorityFingerprintSha256 -and
            (Test-CddsiReleaseSha256Value -Value $BuildResult.OutputRootBindingSha256) -and
            $BuildResult.BuildBindingToken -ceq (Get-CddsiCandidateBuildBindingToken -BuildResult $BuildResult)
        )
    }
    catch { return $false }
}

function Invoke-CddsiCandidateBuildPhaseOne {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$OutputRoot,
        [Parameter(Mandatory = $true)][string[]]$PackageFiles,
        [Parameter(Mandatory = $true)][string]$HelperRelativePath,
        [Parameter(Mandatory = $true)][string]$SbomRelativePath,
        [Parameter(Mandatory = $true)]$ContentEntries,
        [Parameter(Mandatory = $true)]$FrozenFacts,
        [Parameter(Mandatory = $true)]$CommittedFreezeState,
        [Parameter(Mandatory = $true)]$FreezeCommitReceipt,
        [Parameter(Mandatory = $true)]$FreezeStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$FreezeTransactionId,
        [Parameter(Mandatory = $true)][string]$FreezeProposalNonce,
        [Parameter(Mandatory = $true)]$HelperBuildDescriptor,
        [Parameter(Mandatory = $true)]$HelperSignatureEvidence,
        [Parameter(Mandatory = $true)][string]$HelperCandidateId,
        [Parameter(Mandatory = $true)]$SidecarSignerIdentity,
        [Parameter(Mandatory = $true)]$SignatureTrustPolicy,
        [Parameter(Mandatory = $true)][ValidateSet('VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ArtifactVersion,
        [Parameter(Mandatory = $true)][string]$CommitId,
        [Parameter(Mandatory = $true)][string]$BuildId,
        [Parameter(Mandatory = $true)][string]$SigningRequestId,
        [Parameter(Mandatory = $true)][string]$RequestedAtUtc,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [string]$ManifestPath = 'release/content-manifest.json',
        [string]$DetachedSidecarName = 'cddsi-candidate.zip.sidecar.json',
        [string]$ArchiveName = 'cddsi-candidate.zip',
        [ValidateSet('None', 'Cleanup')][string]$FailureInjection = 'None'
    )

    Assert-CddsiCandidateOwnedSandbox -Sandbox $Sandbox
    $sourceFull = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $SourceRoot -MustExist -Container
    $outputFull = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $OutputRoot -MustNotExist
    if ((Test-CddsiPathWithinRoot -Path $outputFull -Root $sourceFull -AllowRoot) -or
        (Test-CddsiPathWithinRoot -Path $sourceFull -Root $outputFull -AllowRoot)) {
        throw 'Candidate source and output roots must be disjoint.'
    }
    foreach ($id in @($BuildId, $SigningRequestId, $HelperCandidateId)) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $id)) { throw 'Candidate identifiers must be canonical UUIDs.' }
    }
    if (@(@($BuildId, $SigningRequestId, $HelperCandidateId) | Select-Object -Unique).Count -ne 3) {
        throw 'Candidate identifiers must be domain-separated.'
    }
    if (-not (Test-CddsiUtcTimestampValue -Value $RequestedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc) -or
        [DateTimeOffset]::Parse($RequestedAtUtc) -gt [DateTimeOffset]::Parse($ValidationTimeUtc)) {
        throw 'Candidate request time is invalid.'
    }
    Assert-CddsiCandidateFrozenFacts -FrozenFacts $FrozenFacts -CommittedFreezeState $CommittedFreezeState `
        -FreezeCommitReceipt $FreezeCommitReceipt -FreezeStoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey `
        -FreezeTransactionId $FreezeTransactionId -FreezeProposalNonce $FreezeProposalNonce `
        -ValidationTimeUtc $ValidationTimeUtc
    if (-not (Test-CddsiCredentialHelperBuildDescriptor -Descriptor $HelperBuildDescriptor -ValidationTimeUtc $ValidationTimeUtc) -or
        $HelperBuildDescriptor.ReleaseVersion -cne $ArtifactVersion -or
        $HelperBuildDescriptor.CommitId -cne $CommitId -or
        -not (Test-CddsiCredentialHelperSignatureEvidence -Evidence $HelperSignatureEvidence `
            -ExpectedBuildDescriptor $HelperBuildDescriptor -ExpectedCandidateId $HelperCandidateId `
            -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'Candidate helper build or signature evidence is invalid.'
    }
    $expectedArchitecture = if ($FrozenFacts.OsImage.Architecture -ceq 'x64') { 'X64' } `
        elseif ($FrozenFacts.OsImage.Architecture -ceq 'arm64') { 'Arm64' } else { $null }
    if ($null -eq $expectedArchitecture -or $HelperBuildDescriptor.Architecture -cne $expectedArchitecture) {
        throw 'Candidate helper architecture does not match frozen VM facts.'
    }
    if (-not (Test-CddsiCandidateSignerIdentity -SignerIdentity $SidecarSignerIdentity)) {
        throw 'Candidate sidecar signer identity is invalid.'
    }
    $trustedPolicy = Copy-CddsiCandidateSignatureTrustPolicy -SignatureTrustPolicy $SignatureTrustPolicy
    if ($trustedPolicy.SigningRequestId -cne $SigningRequestId -or
        $trustedPolicy.ExpectedSubject -cne $SidecarSignerIdentity.Subject -or
        $trustedPolicy.ExpectedCertificateSha256 -cne $SidecarSignerIdentity.CertificateSha256 -or
        $trustedPolicy.ExpectedKeyId -cne $SidecarSignerIdentity.KeyId) {
        throw 'Candidate signature trust policy is not bound to the requested signer and request id.'
    }
    foreach ($name in @($ArchiveName, $DetachedSidecarName)) {
        $null = ConvertTo-CddsiReleaseRelativePath -Path $name
        if ($name.Contains('/')) { throw 'Candidate archive and detached sidecar names must be leaf names.' }
    }
    $manifestRelative = ConvertTo-CddsiReleaseRelativePath -Path $ManifestPath
    $helperRelative = ConvertTo-CddsiReleaseRelativePath -Path $HelperRelativePath
    $sbomRelative = ConvertTo-CddsiReleaseRelativePath -Path $SbomRelativePath
    $staticFiles = @($PackageFiles | ForEach-Object { ConvertTo-CddsiReleaseRelativePath -Path $_ })
    if ($staticFiles.Count -lt 1 -or @($staticFiles + $helperRelative + $sbomRelative | Select-Object -Unique).Count -ne ($staticFiles.Count + 2)) {
        throw 'Candidate static, helper and SBOM paths must be unique and disjoint.'
    }
    $allContentPaths = [string[]]@($staticFiles + $helperRelative + $sbomRelative)
    [Array]::Sort($allContentPaths, [StringComparer]::Ordinal)
    foreach ($reserved in @($manifestRelative, $DetachedSidecarName, $ArchiveName, $script:CddsiCandidateOutputMarkerName)) {
        if (@($allContentPaths | Where-Object { [string]::Equals($_, $reserved, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0) {
            throw 'Candidate content collides with a reserved output path.'
        }
    }

    $observedEntries = @(Get-CddsiCandidateSourceContentEntries -Sandbox $Sandbox -SourceRoot $sourceFull -RelativePaths $allContentPaths)
    Assert-CddsiCandidateContentEntries -ExpectedEntries $ContentEntries -ObservedEntries $observedEntries
    $helperEntry = @($observedEntries | Where-Object Path -CEQ $helperRelative)
    $sbomEntry = @($observedEntries | Where-Object Path -CEQ $sbomRelative)
    if ($helperEntry.Count -ne 1 -or $sbomEntry.Count -ne 1 -or
        $helperEntry[0].Sha256 -cne $HelperBuildDescriptor.PeSha256 -or
        [long]$helperEntry[0].LengthBytes -ne [long]$HelperBuildDescriptor.PeSizeBytes -or
        $sbomEntry[0].Sha256 -cne $HelperBuildDescriptor.SbomSha256 -or
        [long]$sbomEntry[0].LengthBytes -lt 1) {
        throw 'Candidate helper or SBOM file observation differs from its pure evidence.'
    }

    $createdOutput = $false
    try {
        $outputFull = New-CddsiCandidateOutputRoot -Sandbox $Sandbox -OutputRoot $outputFull
        $createdOutput = $true
        $sourceItems = @(Get-CddsiReleasePackageItems -RepositoryRoot $sourceFull -PackageFiles $allContentPaths)
        $null = Invoke-CddsiReleaseFileSecretScan -Items $sourceItems -Layer Source

        $stagingRoot = Join-Path $outputFull 'staging'
        Copy-CddsiReleasePackageItems -Items $sourceItems -StagingRoot $stagingRoot -SandboxRoot $Sandbox.Root
        $manifest = New-CddsiReleaseContentManifest -Stage $ArtifactProfile -ArtifactProfile $ArtifactProfile `
            -ArtifactVersion $ArtifactVersion -CommitId $CommitId -FrozenFactsToken $FrozenFacts.FactsBindingToken `
            -ManifestPath $manifestRelative -DetachedSidecarName $DetachedSidecarName `
            -SignatureTrustPolicy $trustedPolicy -Entries $observedEntries
        $manifestBytes = Get-CddsiCandidateCanonicalJsonBytes -Value $manifest
        $manifestFull = Get-CddsiCanonicalPath -Path (Join-Path $stagingRoot ($manifestRelative.Replace('/', '\')))
        if (-not (Test-CddsiPathWithinRoot -Path $manifestFull -Root $stagingRoot)) {
            throw 'Candidate embedded manifest escapes staging.'
        }
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $manifestFull))
        Assert-CddsiNoReparsePath -Path (Split-Path -Parent $manifestFull) -StopRoot $Sandbox.Root
        $manifestStream = [System.IO.File]::Open($manifestFull, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $manifestStream.Write($manifestBytes, 0, $manifestBytes.Length); $manifestStream.Flush() }
        finally { $manifestStream.Dispose() }

        $zipFiles = [string[]]@($allContentPaths + $manifestRelative)
        $stagedItems = @(Get-CddsiReleaseTreeItems -TreeRoot $stagingRoot -SandboxRoot $Sandbox.Root)
        Assert-CddsiReleaseExactSet -Expected $zipFiles -Actual @($stagedItems.RelativePath) -Label 'Candidate staging inventory'
        $null = Invoke-CddsiReleaseFileSecretScan -Items $stagedItems -Layer Staging
        $zipPath = Join-Path $outputFull $ArchiveName
        New-CddsiReleaseSimulationZip -StagingRoot $stagingRoot -ZipPath $zipPath `
            -PackageFiles $zipFiles -SandboxRoot $Sandbox.Root
        $zipEvidence = Test-CddsiReleaseZipLayer -ZipPath $zipPath -PackageFiles $zipFiles -SandboxRoot $Sandbox.Root
        $expectedHashes = [ordered]@{}
        foreach ($entry in $observedEntries) { $expectedHashes[$entry.Path] = $entry.Sha256 }
        $expectedHashes[$manifestRelative] = Get-CddsiCandidateBytesSha256 -Bytes $manifestBytes
        Assert-CddsiReleaseContentHashesEqual -Expected $expectedHashes -Actual $zipEvidence.ContentHashes -Label 'Candidate ZIP'
        [System.IO.Directory]::Delete($stagingRoot, $true)

        $zipSha256 = Get-CddsiCandidateFileSha256 -Path $zipPath
        $zipLength = [long]([System.IO.FileInfo]::new($zipPath).Length)
        $claimsDraft = [pscustomobject][ordered]@{
            SchemaVersion = 2; ContractVersion = 'cddsi-release-sidecar-payload-v2'
            FinalZipSha256 = $zipSha256; ContentDigest = $manifest.ContentDigest
            ArtifactProfile = $manifest.ArtifactProfile; ArtifactVersion = $manifest.ArtifactVersion
            CommitId = $manifest.CommitId; FrozenFactsToken = $manifest.FrozenFactsToken
            ManifestBindingToken = $manifest.ManifestBindingToken
            SignatureTrustPolicy = $trustedPolicy; SignerIdentity = $SidecarSignerIdentity
            SignatureEvidence = [pscustomobject][ordered]@{
                SchemaVersion = 2; ContractVersion = 'cddsi-release-detached-signature-evidence-v2'
                SignatureAlgorithm = 'RSA-PSS-SHA256'; SignedAtUtc = $RequestedAtUtc
                SigningTimeKind = 'SIGNER_ASSERTED_NO_RFC3161'
            }
        }
        $claimsBytes = ConvertTo-CddsiReleaseSidecarClaimsBytes -Payload $claimsDraft
        $request = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-candidate-sidecar-signing-request-v1'
            Purpose = 'HOST_SANDBOX_SIMULATION_ONLY'; Publishable = $false
            RequestId = $SigningRequestId; ArtifactProfile = $ArtifactProfile; ArtifactVersion = $ArtifactVersion
            CommitId = $CommitId; FinalZipSha256 = $zipSha256; FinalZipLengthBytes = $zipLength
            ContentDigest = $manifest.ContentDigest; FrozenFactsToken = $manifest.FrozenFactsToken
            ReleaseFactsStateBindingToken = $CommittedFreezeState.StateBindingToken
            ReleaseFactsCommitReceiptBindingToken = $FreezeCommitReceipt.ReceiptBindingToken
            ReleaseFactsStoreAuthorityFingerprintSha256 = $FreezeStoreAuthorityPublicKey.FingerprintSha256
            ManifestBindingToken = $manifest.ManifestBindingToken; DetachedSidecarName = $DetachedSidecarName
            ExpectedSignatureTrustPolicy = Copy-CddsiCandidateSignatureTrustPolicy -SignatureTrustPolicy $trustedPolicy
            SignerIdentity = $SidecarSignerIdentity
            ClaimsBindingToken = Get-CddsiReleaseSidecarClaimsBindingToken -Payload $claimsDraft
            ClaimsBytesBase64 = [Convert]::ToBase64String($claimsBytes); ClaimsLengthBytes = [long]$claimsBytes.Length
            SignedAtUtc = $RequestedAtUtc; SigningTimeKind = 'SIGNER_ASSERTED_NO_RFC3161'
            RequestedAtUtc = $RequestedAtUtc; RequestBindingToken = $null
        }
        $request.RequestBindingToken = Get-CddsiCandidateSigningRequestBindingToken -Request $request
        if (-not (Test-CddsiCandidateSigningRequest -Request $request -Manifest $manifest `
                -ExpectedSignatureTrustPolicy $trustedPolicy)) {
            throw 'Candidate signing request construction failed closed.'
        }
        $result = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-candidate-build-result-v1'; BuildId = $BuildId
            Plane = 'TrustedHarness'; EnvironmentTier = 'HostSandbox'; Simulation = $true
            Publishable = $false; PublicationBlockCode = 'REAL_STORE_AND_SIGNING_RECEIPTS_REQUIRED'
            ArtifactProfile = $ArtifactProfile; ArtifactVersion = $ArtifactVersion; CommitId = $CommitId
            FrozenFactsToken = $FrozenFacts.FactsBindingToken
            FreezeStateBindingToken = $CommittedFreezeState.StateBindingToken
            FreezeCommitReceiptBindingToken = $FreezeCommitReceipt.ReceiptBindingToken
            FreezeStoreAuthorityFingerprintSha256 = $FreezeStoreAuthorityPublicKey.FingerprintSha256
            ExpectedSignatureTrustPolicy = Copy-CddsiCandidateSignatureTrustPolicy -SignatureTrustPolicy $trustedPolicy
            Manifest = $manifest; ZipPath = $zipPath; FinalZipSha256 = $zipSha256
            FinalZipLengthBytes = $zipLength
            HelperBuildDescriptorBindingToken = $HelperBuildDescriptor.DescriptorBindingToken
            HelperSignatureEvidenceBindingToken = $HelperSignatureEvidence.BindingToken
            SbomSha256 = $HelperBuildDescriptor.SbomSha256; SigningRequest = $request
            OutputRoot = $outputFull
            OutputRootBindingSha256 = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($outputFull).ToUpperInvariant())
            BuildBindingToken = $null
        }
        $result.BuildBindingToken = Get-CddsiCandidateBuildBindingToken -BuildResult $result
        if (-not (Test-CddsiCandidateBuildResult -BuildResult $result `
                -ExpectedSignatureTrustPolicy $trustedPolicy)) {
            throw 'Candidate build result construction failed closed.'
        }
        return $result
    }
    catch {
        $cleanupOutcome = 'NotStarted'
        if ($createdOutput -and (Test-Path -LiteralPath $outputFull -PathType Container)) {
            try {
                if ($FailureInjection -ceq 'Cleanup') { throw 'Synthetic candidate cleanup failure.' }
                Remove-CddsiCandidateOwnedOutput -Sandbox $Sandbox -OutputRoot $outputFull
                $cleanupOutcome = 'Succeeded'
            }
            catch { $cleanupOutcome = 'Failed' }
        }
        $failure = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-candidate-build-failure-v1'
            Plane = 'TrustedHarness'; EnvironmentTier = 'HostSandbox'; Simulation = $true; Publishable = $false
            Status = 'FAILED_SAFE'; PrimaryErrorCode = 'CANDIDATE_BUILD_FAILED'
            CleanupOutcome = $cleanupOutcome
            CleanupErrorCode = if ($cleanupOutcome -ceq 'Failed') { 'CANDIDATE_CLEANUP_FAILED' } else { '' }
        }
        $exception = [InvalidOperationException]::new('Candidate build failed safely; inspect CddsiCandidateBuildFailure evidence.')
        $exception.Data['CddsiCandidateBuildFailure'] = $failure
        throw $exception
    }
}

function Get-CddsiCandidateFinalZipObservationBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Observation)

    $lines = @(@(
        'cddsi-candidate-final-zip-observation-v1', $Observation.SchemaVersion,
        $Observation.ContractVersion, $Observation.Plane, $Observation.EnvironmentTier,
        $Observation.Simulation, $Observation.ObservationId, $Observation.ArtifactProfile,
        $Observation.FinalZipSha256, $Observation.FinalZipLengthBytes,
        $Observation.ManifestBindingToken, $Observation.ObservedAtUtc
    ) | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function New-CddsiCandidateFinalZipObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)]$BuildResult,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy,
        [Parameter(Mandatory = $true)][string]$ObservationId,
        [Parameter(Mandatory = $true)][string]$ObservedAtUtc
    )

    Assert-CddsiCandidateOwnedSandbox -Sandbox $Sandbox
    if (-not (Test-CddsiCandidateBuildResult -BuildResult $BuildResult `
            -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy) -or
        -not (Test-CddsiCanonicalUuidValue -Value $ObservationId) -or
        -not (Test-CddsiUtcTimestampValue -Value $ObservedAtUtc)) {
        throw 'Final ZIP observation inputs are invalid.'
    }
    $outputFull = Assert-CddsiCandidateOutputOwner -Sandbox $Sandbox -OutputRoot $BuildResult.OutputRoot
    $zipFull = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $BuildResult.ZipPath -MustExist
    if (-not (Test-CddsiPathWithinRoot -Path $zipFull -Root $outputFull)) {
        throw 'Final ZIP observation path escapes candidate output.'
    }
    $observation = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-candidate-final-zip-observation-v1'
        Plane = 'TrustedHarness'; EnvironmentTier = 'HostSandbox'; Simulation = $true
        ObservationId = $ObservationId; ArtifactProfile = $BuildResult.ArtifactProfile
        FinalZipSha256 = Get-CddsiCandidateFileSha256 -Path $zipFull
        FinalZipLengthBytes = [long]([System.IO.FileInfo]::new($zipFull).Length)
        ManifestBindingToken = $BuildResult.Manifest.ManifestBindingToken
        ObservedAtUtc = $ObservedAtUtc; ObservationBindingToken = $null
    }
    $observation.ObservationBindingToken = Get-CddsiCandidateFinalZipObservationBindingToken -Observation $observation
    return $observation
}

function Get-CddsiCandidateFreezeReceiptBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Receipt)

    $lines = @(@(
        'cddsi-candidate-freeze-receipt-v1', $Receipt.SchemaVersion, $Receipt.ContractVersion,
        $Receipt.State, $Receipt.Plane, $Receipt.EnvironmentTier, $Receipt.Simulation,
        $Receipt.Publishable, $Receipt.PublicationBlockCode,
        $Receipt.FreezeId, $Receipt.BuildId, $Receipt.SigningRequestBindingToken,
        $Receipt.FinalZipObservationBindingToken, $Receipt.ArtifactProfile, $Receipt.ArtifactVersion,
        $Receipt.CommitId, $Receipt.FrozenFactsToken, $Receipt.ManifestBindingToken,
        $Receipt.FreezeStateBindingToken, $Receipt.FreezeCommitReceiptBindingToken,
        $Receipt.FreezeStoreAuthorityFingerprintSha256,
        $Receipt.ContentDigest, $Receipt.FinalZipSha256, $Receipt.FinalZipLengthBytes,
        $Receipt.SidecarPayloadBindingToken, $Receipt.SidecarSha256, $Receipt.SidecarLengthBytes,
        $Receipt.HelperBuildDescriptorBindingToken, $Receipt.HelperSignatureEvidenceBindingToken,
        $Receipt.FrozenAtUtc
    ) | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Complete-CddsiCandidateBuildPhaseTwo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)]$BuildResult,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy,
        [Parameter(Mandatory = $true)]$FinalZipObservation,
        [Parameter(Mandatory = $true)]$SidecarPayload,
        [Parameter(Mandatory = $true)][string]$FreezeId,
        [Parameter(Mandatory = $true)][string]$FrozenAtUtc
    )

    Assert-CddsiCandidateOwnedSandbox -Sandbox $Sandbox
    if (-not (Test-CddsiCandidateBuildResult -BuildResult $BuildResult `
            -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy) -or
        -not (Test-CddsiCanonicalUuidValue -Value $FreezeId) -or
        -not (Test-CddsiUtcTimestampValue -Value $FrozenAtUtc)) {
        throw 'Candidate freeze inputs are invalid.'
    }
    $outputFull = Assert-CddsiCandidateOutputOwner -Sandbox $Sandbox -OutputRoot $BuildResult.OutputRoot
    $zipFull = Assert-CddsiCandidatePath -Sandbox $Sandbox -Path $BuildResult.ZipPath -MustExist
    if (-not (Test-CddsiPathWithinRoot -Path $zipFull -Root $outputFull)) {
        throw 'Candidate final ZIP escapes the owned output root.'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $FinalZipObservation -Expected @(
        'SchemaVersion', 'ContractVersion', 'Plane', 'EnvironmentTier', 'Simulation',
        'ObservationId', 'ArtifactProfile', 'FinalZipSha256',
        'FinalZipLengthBytes', 'ManifestBindingToken', 'ObservedAtUtc', 'ObservationBindingToken'
    )) -or $FinalZipObservation.SchemaVersion -ne 1 -or
        $FinalZipObservation.ContractVersion -cne 'cddsi-candidate-final-zip-observation-v1' -or
        $FinalZipObservation.Plane -cne 'TrustedHarness' -or
        $FinalZipObservation.EnvironmentTier -cne 'HostSandbox' -or
        $FinalZipObservation.Simulation -isnot [bool] -or -not $FinalZipObservation.Simulation -or
        -not (Test-CddsiCanonicalUuidValue -Value $FinalZipObservation.ObservationId) -or
        $FinalZipObservation.ArtifactProfile -cne $BuildResult.ArtifactProfile -or
        $FinalZipObservation.ManifestBindingToken -cne $BuildResult.Manifest.ManifestBindingToken -or
        -not (Test-CddsiUtcTimestampValue -Value $FinalZipObservation.ObservedAtUtc) -or
        $FinalZipObservation.ObservationBindingToken -cne (Get-CddsiCandidateFinalZipObservationBindingToken -Observation $FinalZipObservation)) {
        throw 'Candidate final ZIP observation contract is invalid.'
    }
    $currentZipSha = Get-CddsiCandidateFileSha256 -Path $zipFull
    $currentZipLength = [long]([System.IO.FileInfo]::new($zipFull).Length)
    if ($currentZipSha -cne $BuildResult.FinalZipSha256 -or
        $currentZipSha -cne $FinalZipObservation.FinalZipSha256 -or
        $currentZipLength -ne [long]$BuildResult.FinalZipLengthBytes -or
        $currentZipLength -ne [long]$FinalZipObservation.FinalZipLengthBytes) {
        throw 'Candidate final ZIP changed after phase one or observation.'
    }
    $zipFiles = [string[]]@(@($BuildResult.Manifest.Entries.Path) + $BuildResult.Manifest.ManifestPath)
    $zipEvidence = Test-CddsiReleaseZipLayer -ZipPath $zipFull -PackageFiles $zipFiles -SandboxRoot $Sandbox.Root
    $manifestBytes = Get-CddsiCandidateCanonicalJsonBytes -Value $BuildResult.Manifest
    $expectedHashes = [ordered]@{}
    foreach ($entry in @($BuildResult.Manifest.Entries)) { $expectedHashes[$entry.Path] = $entry.Sha256 }
    $expectedHashes[$BuildResult.Manifest.ManifestPath] = Get-CddsiCandidateBytesSha256 -Bytes $manifestBytes
    Assert-CddsiReleaseContentHashesEqual -Expected $expectedHashes -Actual $zipEvidence.ContentHashes -Label 'Final candidate ZIP'

    if (-not (Test-CddsiReleaseSidecarPayload -Payload $SidecarPayload -Manifest $BuildResult.Manifest `
            -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy `
            -ValidationTimeUtc $FrozenAtUtc) -or
        $SidecarPayload.FinalZipSha256 -cne $currentZipSha -or
        $SidecarPayload.ClaimsBindingToken -cne $BuildResult.SigningRequest.ClaimsBindingToken -or
        (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $SidecarPayload.SignerIdentity) -cne
            (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $BuildResult.SigningRequest.SignerIdentity)) {
        throw 'Candidate detached sidecar does not satisfy the signed request.'
    }
    $requested = [DateTimeOffset]::Parse($BuildResult.SigningRequest.RequestedAtUtc)
    $signed = [DateTimeOffset]::Parse($SidecarPayload.SignatureEvidence.SignedAtUtc)
    $observed = [DateTimeOffset]::Parse($FinalZipObservation.ObservedAtUtc)
    $frozen = [DateTimeOffset]::Parse($FrozenAtUtc)
    if ($signed -lt $requested -or $observed -lt $signed -or $frozen -lt $observed) {
        throw 'Candidate signing, observation and freeze times are out of order.'
    }

    $sidecarPath = Get-CddsiCanonicalPath -Path (Join-Path $outputFull $BuildResult.Manifest.DetachedSidecarName)
    if (-not (Test-CddsiPathWithinRoot -Path $sidecarPath -Root $outputFull) -or
        (Test-Path -LiteralPath $sidecarPath)) {
        throw 'Candidate detached sidecar output is unsafe or already exists.'
    }
    Assert-CddsiNoReparsePath -Path $sidecarPath -StopRoot $Sandbox.Root -PathMayNotExist
    $sidecarBytes = Get-CddsiCandidateCanonicalJsonBytes -Value $SidecarPayload
    $sidecarStream = [System.IO.File]::Open($sidecarPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try { $sidecarStream.Write($sidecarBytes, 0, $sidecarBytes.Length); $sidecarStream.Flush() }
    finally { $sidecarStream.Dispose() }
    try {
        $sidecarItem = [pscustomobject][ordered]@{ RelativePath = $BuildResult.Manifest.DetachedSidecarName; FullPath = $sidecarPath }
        $null = Invoke-CddsiReleaseFileSecretScan -Items @($sidecarItem) -Layer Staging
        $sidecarSha = Get-CddsiCandidateFileSha256 -Path $sidecarPath
        $receipt = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-candidate-freeze-receipt-v1'; State = 'SIMULATION_FROZEN'
            Plane = 'TrustedHarness'; EnvironmentTier = 'HostSandbox'; Simulation = $true
            Publishable = $false; PublicationBlockCode = 'REAL_STORE_AND_SIGNING_RECEIPTS_REQUIRED'
            FreezeId = $FreezeId; BuildId = $BuildResult.BuildId
            SigningRequestBindingToken = $BuildResult.SigningRequest.RequestBindingToken
            FinalZipObservationBindingToken = $FinalZipObservation.ObservationBindingToken
            ArtifactProfile = $BuildResult.ArtifactProfile; ArtifactVersion = $BuildResult.ArtifactVersion
            CommitId = $BuildResult.CommitId; FrozenFactsToken = $BuildResult.FrozenFactsToken
            ManifestBindingToken = $BuildResult.Manifest.ManifestBindingToken
            FreezeStateBindingToken = $BuildResult.FreezeStateBindingToken
            FreezeCommitReceiptBindingToken = $BuildResult.FreezeCommitReceiptBindingToken
            FreezeStoreAuthorityFingerprintSha256 = $BuildResult.FreezeStoreAuthorityFingerprintSha256
            ContentDigest = $BuildResult.Manifest.ContentDigest; FinalZipSha256 = $currentZipSha
            FinalZipLengthBytes = $currentZipLength; SidecarPayloadBindingToken = $SidecarPayload.PayloadBindingToken
            SidecarSha256 = $sidecarSha; SidecarLengthBytes = [long]$sidecarBytes.Length
            HelperBuildDescriptorBindingToken = $BuildResult.HelperBuildDescriptorBindingToken
            HelperSignatureEvidenceBindingToken = $BuildResult.HelperSignatureEvidenceBindingToken
            FrozenAtUtc = $FrozenAtUtc; ReceiptBindingToken = $null
        }
        $receipt.ReceiptBindingToken = Get-CddsiCandidateFreezeReceiptBindingToken -Receipt $receipt
        return $receipt
    }
    catch {
        if ([System.IO.File]::Exists($sidecarPath)) { [System.IO.File]::Delete($sidecarPath) }
        throw
    }
}

if ($entryCandidateImportOnly) { return }
throw 'P10B candidate assembly is fail closed. Dot-source with -ImportOnly and invoke an explicit sandbox-bound phase.'
