# release-artifact.ps1 - Pure P10B release-candidate artifact contracts.
# This module never reads files, creates archives, invokes a signer or opens a
# certificate store. It validates immutable bindings and detached signatures
# using only caller-supplied bytes and in-memory X509/RSA primitives.

function Test-CddsiReleaseSha256Value {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    return ($Value -is [string] -and $Value -match '^[a-f0-9]{64}$')
}

function Test-CddsiReleaseVersionValue {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($Value -isnot [string] -or $Value.Length -lt 5 -or $Value.Length -gt 128) { return $false }
    return [regex]::IsMatch(
        $Value,
        '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$'
    )
}

function Test-CddsiReleaseCommitIdValue {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    return ($Value -is [string] -and $Value -match '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')
}

function Test-CddsiReleaseTimestampValue {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    return (
        $Value -is [string] -and
        [regex]::IsMatch($Value, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $Value)
    )
}

function Test-CddsiReleaseEntryPath {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($Value -isnot [string] -or $Value.Length -lt 1 -or $Value.Length -gt 260) { return $false }
    if ($Value -match '[\\:*?"<>|\x00-\x1F\x7F]' -or $Value.StartsWith('/') -or $Value.EndsWith('/') -or $Value.Contains('//')) { return $false }
    $reservedNames = @(
        'CON', 'PRN', 'AUX', 'NUL',
        'COM1', 'COM2', 'COM3', 'COM4', 'COM5', 'COM6', 'COM7', 'COM8', 'COM9',
        'LPT1', 'LPT2', 'LPT3', 'LPT4', 'LPT5', 'LPT6', 'LPT7', 'LPT8', 'LPT9',
        "COM$([char]0x00B9)", "COM$([char]0x00B2)", "COM$([char]0x00B3)",
        "LPT$([char]0x00B9)", "LPT$([char]0x00B2)", "LPT$([char]0x00B3)"
    )
    foreach ($segment in @($Value -split '/')) {
        if ($segment.Length -eq 0 -or $segment -ceq '.' -or $segment -ceq '..' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) { return $false }
        $baseName = @($segment -split '\.', 2)[0].ToUpperInvariant()
        if ($reservedNames -ccontains $baseName) { return $false }
    }
    return $true
}

function Get-CddsiReleaseContentDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Manifest)

    $values = @(
        'cddsi-release-content-digest-v2',
        $Manifest.Stage,
        $Manifest.ArtifactProfile,
        $Manifest.ArtifactVersion,
        $Manifest.CommitId,
        $Manifest.FrozenFactsToken,
        $Manifest.ManifestPath,
        $Manifest.DetachedSidecarName,
        $Manifest.SignatureTrustPolicy.SchemaVersion,
        $Manifest.SignatureTrustPolicy.ContractVersion,
        $Manifest.SignatureTrustPolicy.SignatureAlgorithm,
        $Manifest.SignatureTrustPolicy.ExpectedSubject,
        $Manifest.SignatureTrustPolicy.ExpectedCertificateSha256,
        $Manifest.SignatureTrustPolicy.ExpectedPublicKeySha256,
        $Manifest.SignatureTrustPolicy.ExpectedKeyId,
        $Manifest.SignatureTrustPolicy.SigningRequestId,
        $Manifest.SignatureTrustPolicy.SigningNonce,
        $Manifest.SignatureTrustPolicy.MaximumSignatureAgeSeconds,
        $Manifest.EntryCount
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    foreach ($entry in @($Manifest.Entries)) {
        foreach ($value in @($entry.Ordinal, $entry.Path, $entry.Sha256, $entry.LengthBytes)) {
            $lines += ConvertTo-CddsiStagePolicyBindingField -Value $value
        }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Get-CddsiReleaseContentManifestBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Manifest)

    $values = @(
        'cddsi-release-content-manifest-binding-v2',
        $Manifest.SchemaVersion,
        $Manifest.ContractVersion,
        $Manifest.Stage,
        $Manifest.ArtifactProfile,
        $Manifest.ArtifactVersion,
        $Manifest.CommitId,
        $Manifest.FrozenFactsToken,
        $Manifest.ManifestPath,
        $Manifest.DetachedSidecarName,
        $Manifest.SignatureTrustPolicy.SchemaVersion,
        $Manifest.SignatureTrustPolicy.ContractVersion,
        $Manifest.SignatureTrustPolicy.SignatureAlgorithm,
        $Manifest.SignatureTrustPolicy.ExpectedSubject,
        $Manifest.SignatureTrustPolicy.ExpectedCertificateSha256,
        $Manifest.SignatureTrustPolicy.ExpectedPublicKeySha256,
        $Manifest.SignatureTrustPolicy.ExpectedKeyId,
        $Manifest.SignatureTrustPolicy.SigningRequestId,
        $Manifest.SignatureTrustPolicy.SigningNonce,
        $Manifest.SignatureTrustPolicy.MaximumSignatureAgeSeconds,
        $Manifest.EntryCount,
        $Manifest.ContentDigest
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    foreach ($entry in @($Manifest.Entries)) {
        foreach ($value in @($entry.Ordinal, $entry.Path, $entry.Sha256, $entry.LengthBytes)) {
            $lines += ConvertTo-CddsiStagePolicyBindingField -Value $value
        }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function New-CddsiReleaseContentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('VmAcceptance', 'UserLive')][string]$Stage,
        [Parameter(Mandatory = $true)][ValidateSet('VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ArtifactVersion,
        [Parameter(Mandatory = $true)][string]$CommitId,
        [Parameter(Mandatory = $true)][string]$FrozenFactsToken,
        [Parameter(Mandatory = $true)][string]$ManifestPath,
        [Parameter(Mandatory = $true)][string]$DetachedSidecarName,
        [Parameter(Mandatory = $true)]$SignatureTrustPolicy,
        [Parameter(Mandatory = $true)]$Entries
    )

    $entryCopies = @()
    foreach ($entry in @($Entries)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $entry -Expected @('Ordinal', 'Path', 'Sha256', 'LengthBytes'))) {
            throw 'Release content entry does not match the exact v1 schema.'
        }
        $entryCopies += [pscustomobject][ordered]@{
            Ordinal     = $entry.Ordinal
            Path        = $entry.Path
            Sha256      = $entry.Sha256
            LengthBytes = $entry.LengthBytes
        }
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $SignatureTrustPolicy -Expected @(
        'SchemaVersion', 'ContractVersion', 'SignatureAlgorithm', 'ExpectedSubject',
        'ExpectedCertificateSha256', 'ExpectedPublicKeySha256', 'ExpectedKeyId',
        'SigningRequestId', 'SigningNonce', 'MaximumSignatureAgeSeconds'
    ))) {
        throw 'Release signature trust policy does not match the exact v1 schema.'
    }
    $trustPolicyCopy = [pscustomobject][ordered]@{
        SchemaVersion               = $SignatureTrustPolicy.SchemaVersion
        ContractVersion             = $SignatureTrustPolicy.ContractVersion
        SignatureAlgorithm          = $SignatureTrustPolicy.SignatureAlgorithm
        ExpectedSubject             = $SignatureTrustPolicy.ExpectedSubject
        ExpectedCertificateSha256   = $SignatureTrustPolicy.ExpectedCertificateSha256
        ExpectedPublicKeySha256     = $SignatureTrustPolicy.ExpectedPublicKeySha256
        ExpectedKeyId               = $SignatureTrustPolicy.ExpectedKeyId
        SigningRequestId            = $SignatureTrustPolicy.SigningRequestId
        SigningNonce                = $SignatureTrustPolicy.SigningNonce
        MaximumSignatureAgeSeconds  = $SignatureTrustPolicy.MaximumSignatureAgeSeconds
    }
    $manifest = [pscustomobject][ordered]@{
        SchemaVersion       = 2
        ContractVersion     = 'cddsi-release-content-manifest-v2'
        Stage               = $Stage
        ArtifactProfile     = $ArtifactProfile
        ArtifactVersion     = $ArtifactVersion
        CommitId            = $CommitId
        FrozenFactsToken    = $FrozenFactsToken
        ManifestPath        = $ManifestPath
        DetachedSidecarName = $DetachedSidecarName
        SignatureTrustPolicy = $trustPolicyCopy
        EntryCount          = $entryCopies.Count
        Entries             = [object[]]$entryCopies
        ContentDigest       = $null
        ManifestBindingToken = $null
    }
    $manifest.ContentDigest = Get-CddsiReleaseContentDigest -Manifest $manifest
    $manifest.ManifestBindingToken = Get-CddsiReleaseContentManifestBindingToken -Manifest $manifest
    if (-not (Test-CddsiReleaseContentManifest -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $SignatureTrustPolicy)) {
        throw 'Release content manifest construction failed closed.'
    }
    return $manifest
}

function Test-CddsiReleaseContentManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Manifest,
        [Parameter(Mandatory = $true)][AllowNull()]$ExpectedSignatureTrustPolicy
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $Manifest -Expected @(
            'SchemaVersion', 'ContractVersion', 'Stage', 'ArtifactProfile', 'ArtifactVersion',
            'CommitId', 'FrozenFactsToken', 'ManifestPath', 'DetachedSidecarName', 'EntryCount',
            'SignatureTrustPolicy', 'Entries', 'ContentDigest', 'ManifestBindingToken'
        ))) { return $false }
        if ($Manifest.SchemaVersion -ne 2 -or
            $Manifest.ContractVersion -cne 'cddsi-release-content-manifest-v2' -or
            $Manifest.Stage -isnot [string] -or $Manifest.Stage -cnotin @('VmAcceptance', 'UserLive') -or
            $Manifest.ArtifactProfile -isnot [string] -or $Manifest.ArtifactProfile -cne $Manifest.Stage -or
            -not (Test-CddsiReleaseVersionValue -Value $Manifest.ArtifactVersion) -or
            -not (Test-CddsiReleaseCommitIdValue -Value $Manifest.CommitId) -or
            -not (Test-CddsiReleaseSha256Value -Value $Manifest.FrozenFactsToken) -or
            -not (Test-CddsiReleaseEntryPath -Value $Manifest.ManifestPath) -or
            -not (Test-CddsiReleaseEntryPath -Value $Manifest.DetachedSidecarName) -or
            $Manifest.DetachedSidecarName.Contains('/')) { return $false }
        if ([string]::Equals($Manifest.ManifestPath, $Manifest.DetachedSidecarName, [StringComparison]::OrdinalIgnoreCase)) { return $false }

        $trustPolicy = $Manifest.SignatureTrustPolicy
        if ((ConvertTo-CddsiVmCalibrationCanonicalJson -Value $trustPolicy) -cne
            (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $ExpectedSignatureTrustPolicy)) { return $false }
        if (-not (Test-CddsiExactPropertySet -InputObject $trustPolicy -Expected @(
            'SchemaVersion', 'ContractVersion', 'SignatureAlgorithm', 'ExpectedSubject',
            'ExpectedCertificateSha256', 'ExpectedPublicKeySha256', 'ExpectedKeyId',
            'SigningRequestId', 'SigningNonce', 'MaximumSignatureAgeSeconds'
        )) -or -not (Test-CddsiSchemaVersionOne -Value $trustPolicy.SchemaVersion) -or
            $trustPolicy.ContractVersion -cne 'cddsi-release-signature-trust-policy-v1' -or
            $trustPolicy.SignatureAlgorithm -cne 'RSA-PSS-SHA256' -or
            $trustPolicy.ExpectedSubject -isnot [string] -or $trustPolicy.ExpectedSubject.Length -lt 1 -or
            $trustPolicy.ExpectedSubject.Length -gt 256 -or
            $trustPolicy.ExpectedSubject -match '[\x00-\x1F\x7F\{\}\[\]]' -or
            $trustPolicy.ExpectedSubject -match '(?i)(?:[A-Z]:\\|\\\\|/Users/|/home/)' -or
            @(Find-CddsiPotentialSecrets -Content $trustPolicy.ExpectedSubject -Source '<release-trusted-signer-subject>').Count -ne 0 -or
            -not (Test-CddsiReleaseSha256Value -Value $trustPolicy.ExpectedCertificateSha256) -or
            -not (Test-CddsiReleaseSha256Value -Value $trustPolicy.ExpectedPublicKeySha256) -or
            -not (Test-CddsiSafeIdentifierValue -Value $trustPolicy.ExpectedKeyId -MaxLength 128) -or
            -not (Test-CddsiCanonicalUuidValue -Value $trustPolicy.SigningRequestId) -or
            $trustPolicy.SigningNonce -isnot [string] -or $trustPolicy.SigningNonce -notmatch '^[a-f0-9]{64}$' -or
            ($trustPolicy.MaximumSignatureAgeSeconds -isnot [int] -and
                $trustPolicy.MaximumSignatureAgeSeconds -isnot [long]) -or
            [long]$trustPolicy.MaximumSignatureAgeSeconds -lt 1 -or
            [long]$trustPolicy.MaximumSignatureAgeSeconds -gt 86400 -or
            $trustPolicy.ExpectedCertificateSha256 -ceq $trustPolicy.ExpectedPublicKeySha256 -or
            $trustPolicy.SigningNonce -ceq $trustPolicy.ExpectedCertificateSha256 -or
            $trustPolicy.SigningNonce -ceq $trustPolicy.ExpectedPublicKeySha256) { return $false }

        $entries = @($Manifest.Entries)
        if (($Manifest.EntryCount -isnot [int] -and $Manifest.EntryCount -isnot [long]) -or
            [long]$Manifest.EntryCount -lt 1 -or [long]$Manifest.EntryCount -ne $entries.Count) { return $false }
        $ordinalPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
        $caseFoldedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $previousPath = $null
        for ($index = 0; $index -lt $entries.Count; $index++) {
            $entry = $entries[$index]
            if (-not (Test-CddsiExactPropertySet -InputObject $entry -Expected @('Ordinal', 'Path', 'Sha256', 'LengthBytes'))) { return $false }
            if (($entry.Ordinal -isnot [int] -and $entry.Ordinal -isnot [long]) -or [long]$entry.Ordinal -ne $index -or
                -not (Test-CddsiReleaseEntryPath -Value $entry.Path) -or
                -not (Test-CddsiReleaseSha256Value -Value $entry.Sha256) -or
                ($entry.LengthBytes -isnot [int] -and $entry.LengthBytes -isnot [long]) -or [long]$entry.LengthBytes -lt 0) { return $false }
            if ([string]::Equals($entry.Path, $Manifest.ManifestPath, [StringComparison]::OrdinalIgnoreCase) -or
                [string]::Equals($entry.Path, $Manifest.DetachedSidecarName, [StringComparison]::OrdinalIgnoreCase)) { return $false }
            if (-not $ordinalPaths.Add($entry.Path) -or -not $caseFoldedPaths.Add($entry.Path)) { return $false }
            if ($null -ne $previousPath -and [StringComparer]::Ordinal.Compare($previousPath, $entry.Path) -ge 0) { return $false }
            $previousPath = $entry.Path
        }
        if (-not (Test-CddsiReleaseSha256Value -Value $Manifest.ContentDigest) -or
            $Manifest.ContentDigest -cne (Get-CddsiReleaseContentDigest -Manifest $Manifest) -or
            -not (Test-CddsiReleaseSha256Value -Value $Manifest.ManifestBindingToken) -or
            $Manifest.ManifestBindingToken -cne (Get-CddsiReleaseContentManifestBindingToken -Manifest $Manifest)) { return $false }
        return $true
    }
    catch { return $false }
}

function Test-CddsiReleaseArchiveObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy,
        [Parameter(Mandatory = $true)]$ArchiveEntryPaths,
        [Parameter(Mandatory = $true)]$ObservedContentEntries,
        [Parameter(Mandatory = $true)]$ObservedManifestEntry
    )

    try {
        if (-not (Test-CddsiReleaseContentManifest -Manifest $Manifest `
                -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy)) { return $false }
        $archivePaths = @($ArchiveEntryPaths)
        $observed = @($ObservedContentEntries)
        if (-not (Test-CddsiExactPropertySet -InputObject $ObservedManifestEntry -Expected @(
            'Path', 'Sha256', 'LengthBytes'
        )) -or $ObservedManifestEntry.Path -cne $Manifest.ManifestPath -or
            -not (Test-CddsiReleaseSha256Value -Value $ObservedManifestEntry.Sha256) -or
            ($ObservedManifestEntry.LengthBytes -isnot [int] -and
                $ObservedManifestEntry.LengthBytes -isnot [long]) -or
            [long]$ObservedManifestEntry.LengthBytes -lt 1) { return $false }

        $canonicalJson = (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Manifest) + "`n"
        $manifestBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($canonicalJson)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $manifestSha256 = ([BitConverter]::ToString($sha.ComputeHash($manifestBytes))).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
        if ($ObservedManifestEntry.Sha256 -cne $manifestSha256 -or
            [long]$ObservedManifestEntry.LengthBytes -ne [long]$manifestBytes.Length) { return $false }

        $expectedPaths = [string[]]@(@($Manifest.ManifestPath) + @($Manifest.Entries | ForEach-Object { $_.Path }))
        [Array]::Sort($expectedPaths, [StringComparer]::Ordinal)
        if ($archivePaths.Count -ne $expectedPaths.Count -or $observed.Count -ne $Manifest.EntryCount) { return $false }
        $caseFoldedPaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        for ($index = 0; $index -lt $expectedPaths.Count; $index++) {
            if ($archivePaths[$index] -isnot [string] -or $archivePaths[$index] -cne $expectedPaths[$index] -or
                -not $caseFoldedPaths.Add($archivePaths[$index]) -or
                [string]::Equals($archivePaths[$index], $Manifest.DetachedSidecarName, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        }
        for ($index = 0; $index -lt $observed.Count; $index++) {
            $item = $observed[$index]
            $expected = $Manifest.Entries[$index]
            if (-not (Test-CddsiExactPropertySet -InputObject $item -Expected @('Ordinal', 'Path', 'Sha256', 'LengthBytes'))) { return $false }
            foreach ($name in @('Ordinal', 'Path', 'Sha256', 'LengthBytes')) {
                if ($item.$name -cne $expected.$name) { return $false }
            }
        }
        return $true
    }
    catch { return $false }
}

function ConvertTo-CddsiReleaseSidecarClaimsBytes {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Payload)

    $trustPolicy = $Payload.SignatureTrustPolicy
    $evidence = $Payload.SignatureEvidence
    $values = @(
        'cddsi-release-sidecar-rsa-pss-sha256-claims-v2',
        $Payload.SchemaVersion,
        $Payload.ContractVersion,
        $Payload.FinalZipSha256,
        $Payload.ContentDigest,
        $Payload.ArtifactProfile,
        $Payload.ArtifactVersion,
        $Payload.CommitId,
        $Payload.FrozenFactsToken,
        $Payload.ManifestBindingToken,
        $trustPolicy.SchemaVersion,
        $trustPolicy.ContractVersion,
        $trustPolicy.SignatureAlgorithm,
        $trustPolicy.ExpectedSubject,
        $trustPolicy.ExpectedCertificateSha256,
        $trustPolicy.ExpectedPublicKeySha256,
        $trustPolicy.ExpectedKeyId,
        $trustPolicy.SigningRequestId,
        $trustPolicy.SigningNonce,
        $trustPolicy.MaximumSignatureAgeSeconds,
        $Payload.SignerIdentity.SchemaVersion,
        $Payload.SignerIdentity.ContractVersion,
        $Payload.SignerIdentity.IdentityType,
        $Payload.SignerIdentity.Subject,
        $Payload.SignerIdentity.CertificateSha256,
        $Payload.SignerIdentity.KeyId,
        $evidence.SchemaVersion,
        $evidence.ContractVersion,
        $evidence.SignatureAlgorithm,
        $evidence.SignedAtUtc,
        $evidence.SigningTimeKind
    )
    $canonicalText = (@($values | ForEach-Object {
        ConvertTo-CddsiStagePolicyBindingField -Value $_
    }) -join "`n")
    return (New-Object System.Text.UTF8Encoding($false)).GetBytes($canonicalText)
}

function Get-CddsiReleaseSidecarClaimsBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Payload)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = ConvertTo-CddsiReleaseSidecarClaimsBytes -Payload $Payload
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally { $sha.Dispose() }
}

function Get-CddsiReleaseSignatureEvidenceBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$SignatureEvidence)

    $values = @(
        'cddsi-release-detached-signature-evidence-binding-v2',
        $SignatureEvidence.SchemaVersion,
        $SignatureEvidence.ContractVersion,
        $SignatureEvidence.ClaimsBindingToken,
        $SignatureEvidence.SignatureAlgorithm,
        $SignatureEvidence.SignatureValueBase64,
        $SignatureEvidence.SignatureValueSha256,
        $SignatureEvidence.SigningCertificateDerBase64,
        $SignatureEvidence.SigningCertificateSha256,
        $SignatureEvidence.SignedAtUtc,
        $SignatureEvidence.SigningTimeKind
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Get-CddsiReleaseSidecarPayloadBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Payload)

    $values = @(
        'cddsi-release-sidecar-payload-binding-v2',
        $Payload.SchemaVersion,
        $Payload.ContractVersion,
        $Payload.FinalZipSha256,
        $Payload.ContentDigest,
        $Payload.ArtifactProfile,
        $Payload.ArtifactVersion,
        $Payload.CommitId,
        $Payload.FrozenFactsToken,
        $Payload.ManifestBindingToken,
        $Payload.ClaimsBindingToken,
        $Payload.SignatureTrustPolicy.SchemaVersion,
        $Payload.SignatureTrustPolicy.ContractVersion,
        $Payload.SignatureTrustPolicy.SignatureAlgorithm,
        $Payload.SignatureTrustPolicy.ExpectedSubject,
        $Payload.SignatureTrustPolicy.ExpectedCertificateSha256,
        $Payload.SignatureTrustPolicy.ExpectedPublicKeySha256,
        $Payload.SignatureTrustPolicy.ExpectedKeyId,
        $Payload.SignatureTrustPolicy.SigningRequestId,
        $Payload.SignatureTrustPolicy.SigningNonce,
        $Payload.SignatureTrustPolicy.MaximumSignatureAgeSeconds,
        $Payload.SignerIdentity.SchemaVersion,
        $Payload.SignerIdentity.ContractVersion,
        $Payload.SignerIdentity.IdentityType,
        $Payload.SignerIdentity.Subject,
        $Payload.SignerIdentity.CertificateSha256,
        $Payload.SignerIdentity.KeyId,
        $Payload.SignatureEvidence.EvidenceBindingToken
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function New-CddsiReleaseSidecarPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy,
        [Parameter(Mandatory = $true)][string]$FinalZipSha256,
        [Parameter(Mandatory = $true)]$SignerIdentity,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $identityCopy = [pscustomobject][ordered]@{
        SchemaVersion     = $SignerIdentity.SchemaVersion
        ContractVersion   = $SignerIdentity.ContractVersion
        IdentityType      = $SignerIdentity.IdentityType
        Subject           = $SignerIdentity.Subject
        CertificateSha256 = $SignerIdentity.CertificateSha256
        KeyId             = $SignerIdentity.KeyId
    }
    $trustPolicy = $Manifest.SignatureTrustPolicy
    $trustPolicyCopy = [pscustomobject][ordered]@{
        SchemaVersion              = $trustPolicy.SchemaVersion
        ContractVersion            = $trustPolicy.ContractVersion
        SignatureAlgorithm         = $trustPolicy.SignatureAlgorithm
        ExpectedSubject            = $trustPolicy.ExpectedSubject
        ExpectedCertificateSha256  = $trustPolicy.ExpectedCertificateSha256
        ExpectedPublicKeySha256    = $trustPolicy.ExpectedPublicKeySha256
        ExpectedKeyId              = $trustPolicy.ExpectedKeyId
        SigningRequestId           = $trustPolicy.SigningRequestId
        SigningNonce               = $trustPolicy.SigningNonce
        MaximumSignatureAgeSeconds = $trustPolicy.MaximumSignatureAgeSeconds
    }
    $evidenceCopy = [pscustomobject][ordered]@{
        SchemaVersion                 = $SignatureEvidence.SchemaVersion
        ContractVersion               = $SignatureEvidence.ContractVersion
        ClaimsBindingToken            = $SignatureEvidence.ClaimsBindingToken
        SignatureAlgorithm            = $SignatureEvidence.SignatureAlgorithm
        SignatureValueBase64          = $SignatureEvidence.SignatureValueBase64
        SignatureValueSha256          = $SignatureEvidence.SignatureValueSha256
        SigningCertificateDerBase64   = $SignatureEvidence.SigningCertificateDerBase64
        SigningCertificateSha256      = $SignatureEvidence.SigningCertificateSha256
        SignedAtUtc                   = $SignatureEvidence.SignedAtUtc
        SigningTimeKind               = $SignatureEvidence.SigningTimeKind
        EvidenceBindingToken          = $SignatureEvidence.EvidenceBindingToken
    }
    $payload = [pscustomobject][ordered]@{
        SchemaVersion        = 2
        ContractVersion      = 'cddsi-release-sidecar-payload-v2'
        FinalZipSha256       = $FinalZipSha256
        ContentDigest        = $Manifest.ContentDigest
        ArtifactProfile      = $Manifest.ArtifactProfile
        ArtifactVersion      = $Manifest.ArtifactVersion
        CommitId             = $Manifest.CommitId
        FrozenFactsToken     = $Manifest.FrozenFactsToken
        ManifestBindingToken = $Manifest.ManifestBindingToken
        SignatureTrustPolicy = $trustPolicyCopy
        SignerIdentity       = $identityCopy
        ClaimsBindingToken   = $SignatureEvidence.ClaimsBindingToken
        SignatureEvidence    = $evidenceCopy
        PayloadBindingToken  = $null
    }
    $payload.PayloadBindingToken = Get-CddsiReleaseSidecarPayloadBindingToken -Payload $payload
    if (-not (Test-CddsiReleaseSidecarPayload -Payload $payload -Manifest $Manifest `
            -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'Detached release sidecar construction failed closed.'
    }
    return $payload
}

function Test-CddsiReleaseSidecarPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Payload,
        [Parameter(Mandatory = $true)]$Manifest,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicy,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $certificate = $null
    $rsa = $null
    try {
        if (-not (Test-CddsiReleaseContentManifest -Manifest $Manifest `
                -ExpectedSignatureTrustPolicy $ExpectedSignatureTrustPolicy) -or
            -not (Test-CddsiReleaseTimestampValue -Value $ValidationTimeUtc) -or
            -not (Test-CddsiExactPropertySet -InputObject $Payload -Expected @(
                'SchemaVersion', 'ContractVersion', 'FinalZipSha256', 'ContentDigest', 'ArtifactProfile',
                'ArtifactVersion', 'CommitId', 'FrozenFactsToken', 'ManifestBindingToken',
                'SignatureTrustPolicy', 'SignerIdentity', 'ClaimsBindingToken', 'SignatureEvidence',
                'PayloadBindingToken'
            ))) { return $false }
        if ($Payload.SchemaVersion -ne 2 -or
            $Payload.ContractVersion -cne 'cddsi-release-sidecar-payload-v2' -or
            -not (Test-CddsiReleaseSha256Value -Value $Payload.FinalZipSha256) -or
            $Payload.ContentDigest -cne $Manifest.ContentDigest -or
            $Payload.ArtifactProfile -cne $Manifest.ArtifactProfile -or
            $Payload.ArtifactVersion -cne $Manifest.ArtifactVersion -or
            $Payload.CommitId -cne $Manifest.CommitId -or
            $Payload.FrozenFactsToken -cne $Manifest.FrozenFactsToken -or
            $Payload.ManifestBindingToken -cne $Manifest.ManifestBindingToken -or
            (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Payload.SignatureTrustPolicy) -cne
                (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Manifest.SignatureTrustPolicy)) { return $false }

        $trustPolicy = $Manifest.SignatureTrustPolicy
        $identity = $Payload.SignerIdentity
        if (-not (Test-CddsiExactPropertySet -InputObject $identity -Expected @(
            'SchemaVersion', 'ContractVersion', 'IdentityType', 'Subject', 'CertificateSha256', 'KeyId'
        )) -or -not (Test-CddsiSchemaVersionOne -Value $identity.SchemaVersion) -or
            $identity.ContractVersion -cne 'cddsi-release-signer-identity-v1' -or
            $identity.IdentityType -cne 'X509' -or
            $identity.Subject -cne $trustPolicy.ExpectedSubject -or
            $identity.CertificateSha256 -cne $trustPolicy.ExpectedCertificateSha256 -or
            $identity.KeyId -cne $trustPolicy.ExpectedKeyId) { return $false }

        $evidence = $Payload.SignatureEvidence
        if (-not (Test-CddsiExactPropertySet -InputObject $evidence -Expected @(
            'SchemaVersion', 'ContractVersion', 'ClaimsBindingToken', 'SignatureAlgorithm',
            'SignatureValueBase64', 'SignatureValueSha256', 'SigningCertificateDerBase64',
            'SigningCertificateSha256', 'SignedAtUtc', 'SigningTimeKind', 'EvidenceBindingToken'
        )) -or $evidence.SchemaVersion -ne 2 -or
            $evidence.ContractVersion -cne 'cddsi-release-detached-signature-evidence-v2' -or
            $evidence.ClaimsBindingToken -cne $Payload.ClaimsBindingToken -or
            $evidence.SignatureAlgorithm -cne 'RSA-PSS-SHA256' -or
            $evidence.SignatureAlgorithm -cne $trustPolicy.SignatureAlgorithm -or
            $evidence.SignatureValueBase64 -isnot [string] -or
            $evidence.SignatureValueBase64.Length -lt 1 -or $evidence.SignatureValueBase64.Length -gt 16384 -or
            $evidence.SigningCertificateDerBase64 -isnot [string] -or
            $evidence.SigningCertificateDerBase64.Length -lt 1 -or
            $evidence.SigningCertificateDerBase64.Length -gt 32768 -or
            -not (Test-CddsiReleaseSha256Value -Value $evidence.SignatureValueSha256) -or
            $evidence.SigningCertificateSha256 -cne $trustPolicy.ExpectedCertificateSha256 -or
            -not (Test-CddsiReleaseTimestampValue -Value $evidence.SignedAtUtc) -or
            $evidence.SigningTimeKind -cne 'SIGNER_ASSERTED_NO_RFC3161' -or
            -not (Test-CddsiReleaseSha256Value -Value $evidence.EvidenceBindingToken) -or
            $evidence.EvidenceBindingToken -cne (Get-CddsiReleaseSignatureEvidenceBindingToken -SignatureEvidence $evidence)) { return $false }

        $signatureBytes = [Convert]::FromBase64String($evidence.SignatureValueBase64)
        $certificateBytes = [Convert]::FromBase64String($evidence.SigningCertificateDerBase64)
        if ($signatureBytes.Length -lt 256 -or $signatureBytes.Length -gt 1024 -or
            $certificateBytes.Length -lt 256 -or $certificateBytes.Length -gt 16384 -or
            [Convert]::ToBase64String($signatureBytes) -cne $evidence.SignatureValueBase64 -or
            [Convert]::ToBase64String($certificateBytes) -cne $evidence.SigningCertificateDerBase64) { return $false }

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $signatureSha256 = ([BitConverter]::ToString($sha.ComputeHash($signatureBytes))).Replace('-', '').ToLowerInvariant()
            $certificateSha256 = ([BitConverter]::ToString($sha.ComputeHash($certificateBytes))).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
        if ($signatureSha256 -cne $evidence.SignatureValueSha256 -or
            $certificateSha256 -cne $evidence.SigningCertificateSha256 -or
            $certificateSha256 -cne $identity.CertificateSha256) { return $false }

        $certificate = [System.Security.Cryptography.X509Certificates.X509Certificate2]::new($certificateBytes)
        if ([Convert]::ToBase64String($certificate.RawData) -cne $evidence.SigningCertificateDerBase64 -or
            $certificate.Subject -cne $trustPolicy.ExpectedSubject) { return $false }
        $publicKeyBytes = $certificate.GetPublicKey()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $publicKeySha256 = ([BitConverter]::ToString($sha.ComputeHash($publicKeyBytes))).Replace('-', '').ToLowerInvariant()
        }
        finally { $sha.Dispose() }
        if ($publicKeySha256 -cne $trustPolicy.ExpectedPublicKeySha256) { return $false }

        $rsa = [System.Security.Cryptography.X509Certificates.RSACertificateExtensions]::GetRSAPublicKey($certificate)
        if ($null -eq $rsa -or $rsa.KeySize -lt 2048 -or $rsa.KeySize -gt 8192 -or
            $signatureBytes.Length -ne [int]($rsa.KeySize / 8)) { return $false }

        $signedAt = [DateTimeOffset]::Parse($evidence.SignedAtUtc, [Globalization.CultureInfo]::InvariantCulture)
        $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc, [Globalization.CultureInfo]::InvariantCulture)
        $certificateNotBefore = [DateTimeOffset]$certificate.NotBefore.ToUniversalTime()
        $certificateNotAfter = [DateTimeOffset]$certificate.NotAfter.ToUniversalTime()
        if ($signedAt -gt $validationTime -or
            ($validationTime - $signedAt).TotalSeconds -gt [long]$trustPolicy.MaximumSignatureAgeSeconds -or
            $signedAt -lt $certificateNotBefore -or $signedAt -gt $certificateNotAfter -or
            $validationTime -lt $certificateNotBefore -or $validationTime -gt $certificateNotAfter) { return $false }

        if (-not (Test-CddsiReleaseSha256Value -Value $Payload.ClaimsBindingToken) -or
            $Payload.ClaimsBindingToken -cne (Get-CddsiReleaseSidecarClaimsBindingToken -Payload $Payload) -or
            -not (Test-CddsiReleaseSha256Value -Value $Payload.PayloadBindingToken) -or
            $Payload.PayloadBindingToken -cne (Get-CddsiReleaseSidecarPayloadBindingToken -Payload $Payload)) { return $false }
        $claimsBytes = ConvertTo-CddsiReleaseSidecarClaimsBytes -Payload $Payload
        if (-not $rsa.VerifyData(
            $claimsBytes,
            $signatureBytes,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pss
        )) { return $false }

        $domainTokens = @(
            $Payload.FinalZipSha256, $Payload.ContentDigest, $Payload.FrozenFactsToken,
            $Payload.ManifestBindingToken, $Payload.ClaimsBindingToken,
            $evidence.SignatureValueSha256, $evidence.EvidenceBindingToken,
            $Payload.PayloadBindingToken
        )
        return (@($domainTokens | Select-Object -Unique).Count -eq $domainTokens.Count)
    }
    catch { return $false }
    finally {
        if ($null -ne $rsa) { $rsa.Dispose() }
        if ($null -ne $certificate) { $certificate.Dispose() }
    }
}

function Get-CddsiReleaseCandidateSetBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$CandidateSet)

    $values = @(
        'cddsi-release-candidate-set-binding-v1',
        $CandidateSet.SchemaVersion,
        $CandidateSet.ContractVersion,
        $CandidateSet.ArtifactVersion,
        $CandidateSet.CommitId,
        $CandidateSet.FrozenFactsToken,
        $CandidateSet.CandidateCount
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    foreach ($candidate in @($CandidateSet.Candidates)) {
        foreach ($value in @(
            $candidate.Ordinal, $candidate.ArtifactProfile, $candidate.FinalZipSha256,
            $candidate.ContentDigest, $candidate.ManifestBindingToken,
            $candidate.SidecarPayloadBindingToken
        )) { $lines += ConvertTo-CddsiStagePolicyBindingField -Value $value }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function New-CddsiReleaseCandidateSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CandidateManifests,
        [Parameter(Mandatory = $true)]$CandidateSidecarPayloads,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicies,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $manifests = @($CandidateManifests)
    $sidecars = @($CandidateSidecarPayloads)
    if ($manifests.Count -ne 2 -or $sidecars.Count -ne 2) { throw 'Release candidate set requires exactly two candidates.' }
    $candidates = @()
    for ($index = 0; $index -lt 2; $index++) {
        $candidates += [pscustomobject][ordered]@{
            Ordinal                   = $index
            ArtifactProfile           = $sidecars[$index].ArtifactProfile
            FinalZipSha256            = $sidecars[$index].FinalZipSha256
            ContentDigest             = $sidecars[$index].ContentDigest
            ManifestBindingToken      = $sidecars[$index].ManifestBindingToken
            SidecarPayloadBindingToken = $sidecars[$index].PayloadBindingToken
        }
    }
    $candidateSet = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        ContractVersion  = 'cddsi-release-candidate-set-v1'
        ArtifactVersion  = $manifests[0].ArtifactVersion
        CommitId         = $manifests[0].CommitId
        FrozenFactsToken = $manifests[0].FrozenFactsToken
        CandidateCount   = 2
        Candidates       = [object[]]$candidates
        SetBindingToken  = $null
    }
    $candidateSet.SetBindingToken = Get-CddsiReleaseCandidateSetBindingToken -CandidateSet $candidateSet
    if (-not (Test-CddsiReleaseCandidateSet -CandidateSet $candidateSet -CandidateManifests $manifests `
        -CandidateSidecarPayloads $sidecars -ExpectedSignatureTrustPolicies $ExpectedSignatureTrustPolicies `
        -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'Release candidate set construction failed closed.'
    }
    return $candidateSet
}

function Test-CddsiReleaseCandidateSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$CandidateSet,
        [Parameter(Mandatory = $true)]$CandidateManifests,
        [Parameter(Mandatory = $true)]$CandidateSidecarPayloads,
        [Parameter(Mandatory = $true)]$ExpectedSignatureTrustPolicies,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $CandidateSet -Expected @(
            'SchemaVersion', 'ContractVersion', 'ArtifactVersion', 'CommitId', 'FrozenFactsToken',
            'CandidateCount', 'Candidates', 'SetBindingToken'
        )) -or -not (Test-CddsiSchemaVersionOne -Value $CandidateSet.SchemaVersion) -or
            $CandidateSet.ContractVersion -cne 'cddsi-release-candidate-set-v1' -or
            -not (Test-CddsiReleaseVersionValue -Value $CandidateSet.ArtifactVersion) -or
            -not (Test-CddsiReleaseCommitIdValue -Value $CandidateSet.CommitId) -or
            -not (Test-CddsiReleaseSha256Value -Value $CandidateSet.FrozenFactsToken) -or
            ($CandidateSet.CandidateCount -isnot [int] -and $CandidateSet.CandidateCount -isnot [long]) -or
            [long]$CandidateSet.CandidateCount -ne 2) { return $false }
        $manifests = @($CandidateManifests)
        $sidecars = @($CandidateSidecarPayloads)
        $trustPolicies = @($ExpectedSignatureTrustPolicies)
        $candidates = @($CandidateSet.Candidates)
        if ($manifests.Count -ne 2 -or $sidecars.Count -ne 2 -or $trustPolicies.Count -ne 2 -or
            $candidates.Count -ne 2) { return $false }
        $expectedProfiles = @('VmAcceptance', 'UserLive')
        for ($index = 0; $index -lt 2; $index++) {
            $manifest = $manifests[$index]
            $sidecar = $sidecars[$index]
            $candidate = $candidates[$index]
            if (-not (Test-CddsiReleaseContentManifest -Manifest $manifest `
                    -ExpectedSignatureTrustPolicy $trustPolicies[$index]) -or
                -not (Test-CddsiReleaseSidecarPayload -Payload $sidecar -Manifest $manifest `
                    -ExpectedSignatureTrustPolicy $trustPolicies[$index] `
                    -ValidationTimeUtc $ValidationTimeUtc) -or
                $manifest.ArtifactProfile -cne $expectedProfiles[$index] -or
                $sidecar.ArtifactProfile -cne $expectedProfiles[$index] -or
                -not (Test-CddsiExactPropertySet -InputObject $candidate -Expected @(
                    'Ordinal', 'ArtifactProfile', 'FinalZipSha256', 'ContentDigest',
                    'ManifestBindingToken', 'SidecarPayloadBindingToken'
                )) -or ($candidate.Ordinal -isnot [int] -and $candidate.Ordinal -isnot [long]) -or [long]$candidate.Ordinal -ne $index -or
                $candidate.ArtifactProfile -cne $expectedProfiles[$index] -or
                $candidate.FinalZipSha256 -cne $sidecar.FinalZipSha256 -or
                $candidate.ContentDigest -cne $manifest.ContentDigest -or
                $candidate.ManifestBindingToken -cne $manifest.ManifestBindingToken -or
                $candidate.SidecarPayloadBindingToken -cne $sidecar.PayloadBindingToken -or
                $manifest.ArtifactVersion -cne $CandidateSet.ArtifactVersion -or
                $manifest.CommitId -cne $CandidateSet.CommitId -or
                $manifest.FrozenFactsToken -cne $CandidateSet.FrozenFactsToken) { return $false }
        }
        foreach ($name in @('FinalZipSha256', 'ContentDigest', 'ManifestBindingToken', 'SidecarPayloadBindingToken')) {
            if ($candidates[0].$name -ceq $candidates[1].$name) { return $false }
        }
        if (-not (Test-CddsiReleaseSha256Value -Value $CandidateSet.SetBindingToken) -or
            $CandidateSet.SetBindingToken -cne (Get-CddsiReleaseCandidateSetBindingToken -CandidateSet $CandidateSet)) { return $false }
        return $true
    }
    catch { return $false }
}

function Get-CddsiReleasePromotionReceiptBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$PromotionReceipt)

    $values = @(
        'cddsi-release-promotion-receipt-binding-v1',
        $PromotionReceipt.SchemaVersion,
        $PromotionReceipt.ContractVersion,
        $PromotionReceipt.State,
        $PromotionReceipt.PromotionId,
        $PromotionReceipt.CandidateSetBindingToken,
        $PromotionReceipt.SourceProfile,
        $PromotionReceipt.TargetProfile,
        $PromotionReceipt.SourceZipSha256,
        $PromotionReceipt.TargetZipSha256,
        $PromotionReceipt.SourceSidecarPayloadBindingToken,
        $PromotionReceipt.TargetSidecarPayloadBindingToken,
        $PromotionReceipt.ArtifactVersion,
        $PromotionReceipt.CommitId,
        $PromotionReceipt.FrozenFactsToken,
        $PromotionReceipt.AcceptanceEvidenceToken,
        $PromotionReceipt.PromotedAtUtc
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function New-CddsiReleasePromotionReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CandidateSet,
        [Parameter(Mandatory = $true)]$CandidateManifests,
        [Parameter(Mandatory = $true)]$CandidateSidecarPayloads,
        [Parameter(Mandatory = $true)][string]$AcceptanceEvidenceToken,
        [Parameter(Mandatory = $true)][string]$PromotionId,
        [Parameter(Mandatory = $true)][string]$PromotedAtUtc
    )

    throw 'P11_ACCEPTANCE_RECEIPT_REQUIRED: promotion is unavailable until the exact P11 acceptance receipt contract exists.'
}

function Test-CddsiReleasePromotionReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$PromotionReceipt,
        [Parameter(Mandatory = $true)]$CandidateSet,
        [Parameter(Mandatory = $true)]$CandidateManifests,
        [Parameter(Mandatory = $true)]$CandidateSidecarPayloads
    )

    return $false
}
