BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\release-artifact.ps1')

    $script:ReleaseValidationTime = '2030-01-01T00:20:00Z'

    function Copy-CddsiReleaseArtifactFixture {
        param([Parameter(Mandatory = $true)][AllowNull()]$Value)

        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($key in $Value.Keys) { $copy[$key] = Copy-CddsiReleaseArtifactFixture -Value $Value[$key] }
            return $copy
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Value) { $items.Add((Copy-CddsiReleaseArtifactFixture -Value $item)) }
            Write-Output -NoEnumerate ([object[]]$items.ToArray())
            return
        }
        $properties = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $properties[$property.Name] = Copy-CddsiReleaseArtifactFixture -Value $property.Value
        }
        return [pscustomobject]$properties
    }

    function Get-CddsiReleaseFixtureSha256 {
        param([Parameter(Mandatory = $true)][byte[]]$Bytes)

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
        finally { $sha.Dispose() }
    }

    function New-CddsiSyntheticReleaseSigner {
        param(
            [Parameter(Mandatory = $true)][string]$Subject,
            [Parameter(Mandatory = $true)][string]$KeyId,
            [Parameter(Mandatory = $true)][string]$SigningRequestId,
            [Parameter(Mandatory = $true)][string]$SigningNonce
        )

        $rsa = [System.Security.Cryptography.RSACng]::new(2048)
        $request = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            $Subject,
            $rsa,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
        )
        $certificate = $request.CreateSelfSigned(
            [DateTimeOffset]::Parse('2029-01-01T00:00:00Z'),
            [DateTimeOffset]::Parse('2031-01-01T00:00:00Z')
        )
        $certificateBytes = $certificate.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert
        )
        $certificateSha256 = Get-CddsiReleaseFixtureSha256 -Bytes $certificateBytes
        $publicKeySha256 = Get-CddsiReleaseFixtureSha256 -Bytes ($certificate.GetPublicKey())
        $identity = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            ContractVersion   = 'cddsi-release-signer-identity-v1'
            IdentityType      = 'X509'
            Subject           = $certificate.Subject
            CertificateSha256 = $certificateSha256
            KeyId             = $KeyId
        }
        $trustPolicy = [pscustomobject][ordered]@{
            SchemaVersion              = 1
            ContractVersion            = 'cddsi-release-signature-trust-policy-v1'
            SignatureAlgorithm         = 'RSA-PSS-SHA256'
            ExpectedSubject            = $certificate.Subject
            ExpectedCertificateSha256  = $certificateSha256
            ExpectedPublicKeySha256    = $publicKeySha256
            ExpectedKeyId              = $KeyId
            SigningRequestId           = $SigningRequestId
            SigningNonce               = $SigningNonce
            MaximumSignatureAgeSeconds = 3600
        }
        return [pscustomobject][ordered]@{
            Rsa                  = $rsa
            Certificate          = $certificate
            CertificateBytes     = $certificateBytes
            CertificateDerBase64 = [Convert]::ToBase64String($certificateBytes)
            Identity             = $identity
            TrustPolicy          = $trustPolicy
        }
    }

    $script:VmSigner = New-CddsiSyntheticReleaseSigner `
        -Subject 'CN=CDDSI VM Candidate Signer' -KeyId 'vm-candidate-key-v2' `
        -SigningRequestId '61000000-0000-4000-8000-000000000001' -SigningNonce ('1' * 64)
    $script:UserSigner = New-CddsiSyntheticReleaseSigner `
        -Subject 'CN=CDDSI User Candidate Signer' -KeyId 'user-candidate-key-v2' `
        -SigningRequestId '62000000-0000-4000-8000-000000000001' -SigningNonce ('2' * 64)

    function New-CddsiReleaseContentEntriesFixture {
        return [object[]]@(
            [pscustomobject][ordered]@{ Ordinal = 0; Path = 'Start-Here.ps1'; Sha256 = ('a' * 64); LengthBytes = 101L },
            [pscustomobject][ordered]@{ Ordinal = 1; Path = 'lib/bootstrap.ps1'; Sha256 = ('b' * 64); LengthBytes = 202L }
        )
    }

    function New-CddsiReleaseManifestFixture {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('VmAcceptance', 'UserLive')][string]$ArtifactProfile,
            [string]$ArtifactVersion = '1.2.3-rc.1',
            [string]$CommitId = ('9' * 40),
            [string]$FrozenFactsToken = ('c' * 64),
            [AllowNull()]$Signer
        )

        if ($null -eq $Signer) {
            $Signer = if ($ArtifactProfile -ceq 'VmAcceptance') { $script:VmSigner } else { $script:UserSigner }
        }
        $sidecarName = if ($ArtifactProfile -ceq 'VmAcceptance') {
            'cddsi-vm-acceptance.zip.sidecar.json'
        }
        else { 'cddsi-user-live.zip.sidecar.json' }
        return New-CddsiReleaseContentManifest -Stage $ArtifactProfile -ArtifactProfile $ArtifactProfile `
            -ArtifactVersion $ArtifactVersion -CommitId $CommitId -FrozenFactsToken $FrozenFactsToken `
            -ManifestPath 'release/content-manifest.json' -DetachedSidecarName $sidecarName `
            -SignatureTrustPolicy $Signer.TrustPolicy -Entries (New-CddsiReleaseContentEntriesFixture)
    }

    function New-CddsiReleaseManifestObservationFixture {
        param([Parameter(Mandatory = $true)]$Manifest)

        $bytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes(
            (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Manifest) + "`n"
        )
        return [pscustomobject][ordered]@{
            Path        = $Manifest.ManifestPath
            Sha256      = Get-CddsiReleaseFixtureSha256 -Bytes $bytes
            LengthBytes = [long]$bytes.Length
        }
    }

    function New-CddsiReleaseSidecarFixture {
        param(
            [Parameter(Mandatory = $true)]$Manifest,
            [string]$SignedAtUtc,
            [string]$ValidationTimeUtc = $script:ReleaseValidationTime,
            [AllowNull()]$SigningSigner,
            [AllowNull()]$PayloadSigner
        )

        $signer = $PayloadSigner
        if ($null -eq $signer) {
            $signer = if ($Manifest.ArtifactProfile -ceq 'VmAcceptance') { $script:VmSigner } else { $script:UserSigner }
        }
        if ($null -eq $SigningSigner) { $SigningSigner = $signer }
        if ([string]::IsNullOrEmpty($SignedAtUtc)) {
            $SignedAtUtc = if ($Manifest.ArtifactProfile -ceq 'VmAcceptance') {
                '2030-01-01T00:10:00Z'
            }
            else { '2030-01-01T00:11:00Z' }
        }
        $finalZipSha256 = if ($Manifest.ArtifactProfile -ceq 'VmAcceptance') { 'd' * 64 } else { 'e' * 64 }
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion               = 2
            ContractVersion             = 'cddsi-release-detached-signature-evidence-v2'
            ClaimsBindingToken          = $null
            SignatureAlgorithm          = 'RSA-PSS-SHA256'
            SignatureValueBase64        = $null
            SignatureValueSha256        = $null
            SigningCertificateDerBase64 = $signer.CertificateDerBase64
            SigningCertificateSha256    = $signer.Identity.CertificateSha256
            SignedAtUtc                 = $SignedAtUtc
            SigningTimeKind             = 'SIGNER_ASSERTED_NO_RFC3161'
            EvidenceBindingToken        = $null
        }
        $draft = [pscustomobject][ordered]@{
            SchemaVersion        = 2
            ContractVersion      = 'cddsi-release-sidecar-payload-v2'
            FinalZipSha256       = $finalZipSha256
            ContentDigest        = $Manifest.ContentDigest
            ArtifactProfile      = $Manifest.ArtifactProfile
            ArtifactVersion      = $Manifest.ArtifactVersion
            CommitId             = $Manifest.CommitId
            FrozenFactsToken     = $Manifest.FrozenFactsToken
            ManifestBindingToken = $Manifest.ManifestBindingToken
            SignatureTrustPolicy = $Manifest.SignatureTrustPolicy
            SignerIdentity       = $signer.Identity
            ClaimsBindingToken   = $null
            SignatureEvidence    = $evidence
            PayloadBindingToken  = $null
        }
        $evidence.ClaimsBindingToken = Get-CddsiReleaseSidecarClaimsBindingToken -Payload $draft
        $draft.ClaimsBindingToken = $evidence.ClaimsBindingToken
        $signatureBytes = $SigningSigner.Rsa.SignData(
            (ConvertTo-CddsiReleaseSidecarClaimsBytes -Payload $draft),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pss
        )
        $evidence.SignatureValueBase64 = [Convert]::ToBase64String($signatureBytes)
        $evidence.SignatureValueSha256 = Get-CddsiReleaseFixtureSha256 -Bytes $signatureBytes
        $evidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken -SignatureEvidence $evidence
        return New-CddsiReleaseSidecarPayload -Manifest $Manifest `
            -ExpectedSignatureTrustPolicy $signer.TrustPolicy -FinalZipSha256 $finalZipSha256 `
            -SignerIdentity $signer.Identity -SignatureEvidence $evidence -ValidationTimeUtc $ValidationTimeUtc
    }

    function New-CddsiReleaseCandidateFixture {
        param(
            [string]$ArtifactVersion = '1.2.3-rc.1',
            [string]$CommitId = ('9' * 40),
            [string]$FrozenFactsToken = ('c' * 64)
        )

        $vmManifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance `
            -ArtifactVersion $ArtifactVersion -CommitId $CommitId -FrozenFactsToken $FrozenFactsToken
        $userManifest = New-CddsiReleaseManifestFixture -ArtifactProfile UserLive `
            -ArtifactVersion $ArtifactVersion -CommitId $CommitId -FrozenFactsToken $FrozenFactsToken
        $manifests = [object[]]@($vmManifest, $userManifest)
        $sidecars = [object[]]@(
            (New-CddsiReleaseSidecarFixture -Manifest $vmManifest),
            (New-CddsiReleaseSidecarFixture -Manifest $userManifest)
        )
        $trustPolicies = [object[]]@($script:VmSigner.TrustPolicy, $script:UserSigner.TrustPolicy)
        $set = New-CddsiReleaseCandidateSet -CandidateManifests $manifests `
            -CandidateSidecarPayloads $sidecars -ExpectedSignatureTrustPolicies $trustPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime
        return [pscustomobject][ordered]@{
            Manifests = $manifests; Sidecars = $sidecars; TrustPolicies = $trustPolicies; Set = $set
        }
    }
}

AfterAll {
    foreach ($signer in @($script:VmSigner, $script:UserSigner)) {
        if ($null -ne $signer.Certificate) { $signer.Certificate.Dispose() }
        if ($null -ne $signer.Rsa) { $signer.Rsa.Dispose() }
    }
}

Describe 'P10B embedded release content manifest contract' {
    It 'binds the exact content set and an external signer pin while retaining an acyclic topology' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        (Test-CddsiReleaseContentManifest -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy) | Should -BeTrue
        $manifest.SignatureTrustPolicy.ExpectedCertificateSha256 | Should -BeExactly $script:VmSigner.Identity.CertificateSha256
        $manifest.SignatureTrustPolicy.ExpectedPublicKeySha256 | Should -Match '^[a-f0-9]{64}$'
        $manifest.SignatureTrustPolicy.SigningRequestId | Should -BeExactly '61000000-0000-4000-8000-000000000001'
        $manifest.SignatureTrustPolicy.SigningNonce | Should -BeExactly ('1' * 64)
        @($manifest.Entries | Where-Object { $_.Path -ceq $manifest.ManifestPath }).Count | Should -Be 0
        @($manifest.Entries | Where-Object { $_.Path -ceq $manifest.DetachedSidecarName }).Count | Should -Be 0

        $copy = Copy-CddsiReleaseArtifactFixture -Value $manifest
        (Get-CddsiReleaseContentDigest -Manifest $copy) | Should -BeExactly $manifest.ContentDigest
        (Get-CddsiReleaseContentManifestBindingToken -Manifest $copy) | Should -BeExactly $manifest.ManifestBindingToken
    }

    It 'binds the manifest bytes in the archive in addition to content entry hashes' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        $paths = [string[]]@(@($manifest.ManifestPath) + @($manifest.Entries.Path))
        [Array]::Sort($paths, [StringComparer]::Ordinal)
        $manifestObservation = New-CddsiReleaseManifestObservationFixture -Manifest $manifest
        (Test-CddsiReleaseArchiveObservation -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy -ArchiveEntryPaths $paths `
            -ObservedContentEntries $manifest.Entries -ObservedManifestEntry $manifestObservation) | Should -BeTrue

        $swappedPaths = @($paths)
        $swap = $swappedPaths[0]
        $swappedPaths[0] = $swappedPaths[-1]
        $swappedPaths[-1] = $swap
        (Test-CddsiReleaseArchiveObservation -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy -ArchiveEntryPaths $swappedPaths `
            -ObservedContentEntries $manifest.Entries -ObservedManifestEntry $manifestObservation) | Should -BeFalse
        (Test-CddsiReleaseArchiveObservation -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ArchiveEntryPaths @($paths + 'unexpected.txt') `
            -ObservedContentEntries $manifest.Entries -ObservedManifestEntry $manifestObservation) | Should -BeFalse

        foreach ($property in @('Sha256', 'LengthBytes')) {
            $drift = Copy-CddsiReleaseArtifactFixture -Value $manifestObservation
            $drift.$property = if ($property -ceq 'Sha256') { 'f' * 64 } else { [long]$drift.LengthBytes + 1L }
            (Test-CddsiReleaseArchiveObservation -Manifest $manifest `
                -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy -ArchiveEntryPaths $paths `
                -ObservedContentEntries $manifest.Entries -ObservedManifestEntry $drift) | Should -BeFalse
        }
        $hashDrift = Copy-CddsiReleaseArtifactFixture -Value $manifest.Entries
        $hashDrift[1].Sha256 = 'f' * 64
        (Test-CddsiReleaseArchiveObservation -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy -ArchiveEntryPaths $paths `
            -ObservedContentEntries $hashDrift -ObservedManifestEntry $manifestObservation) | Should -BeFalse
    }

    It 'rejects Windows-unsafe and reserved archive entry names' {
        foreach ($path in @(
            'bad*.txt', 'bad?.txt', 'bad".txt', 'bad<.txt', 'bad>.txt', 'bad|.txt',
            'bad:name.txt', 'bad\name.txt', 'folder/.', 'folder/..', 'folder/trailing.',
            'folder/trailing ', 'COM1.txt', 'LPT9', 'COM¹.txt', 'COM²', 'COM³.log',
            'LPT¹.txt', 'LPT²', 'LPT³.log'
        )) { (Test-CddsiReleaseEntryPath -Value $path) | Should -BeFalse }
        (Test-CddsiReleaseEntryPath -Value 'safe/中文.txt') | Should -BeTrue
    }

    It 'rejects signer trust, self-reference, sidecar inclusion, swaps and case collisions after rebinding' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        $attacks = @()
        foreach ($mutation in @(
            @{ Kind = 'EntryPath'; Index = 0; Value = $manifest.ManifestPath },
            @{ Kind = 'EntryPath'; Index = 0; Value = $manifest.DetachedSidecarName },
            @{ Kind = 'EntryPath'; Index = 1; Value = 'start-here.ps1' },
            @{ Kind = 'Trust'; Name = 'ExpectedCertificateSha256'; Value = ('8' * 64) },
            @{ Kind = 'Trust'; Name = 'ExpectedPublicKeySha256'; Value = ('7' * 64) },
            @{ Kind = 'Trust'; Name = 'SignatureAlgorithm'; Value = 'ECDSA-P256-SHA256' }
        )) {
            $attack = Copy-CddsiReleaseArtifactFixture -Value $manifest
            if ($mutation.Kind -ceq 'EntryPath') { $attack.Entries[$mutation.Index].Path = $mutation.Value }
            else { $attack.SignatureTrustPolicy.($mutation.Name) = $mutation.Value }
            $attack.ContentDigest = Get-CddsiReleaseContentDigest -Manifest $attack
            $attack.ManifestBindingToken = Get-CddsiReleaseContentManifestBindingToken -Manifest $attack
            $attacks += ,$attack
        }
        foreach ($attack in $attacks) {
            (Test-CddsiReleaseContentManifest -Manifest $attack `
                -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy) | Should -BeFalse
        }
    }
}

Describe 'P10B detached RSA-PSS signed sidecar contract' {
    It 'verifies exact canonical claims bytes against the pinned in-memory X509 RSA public key' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        $sidecar = New-CddsiReleaseSidecarFixture -Manifest $manifest
        (Test-CddsiReleaseSidecarPayload -Payload $sidecar -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeTrue
        $sidecar.SignatureEvidence.SignatureAlgorithm | Should -BeExactly 'RSA-PSS-SHA256'
        $sidecar.SignatureEvidence.SigningTimeKind | Should -BeExactly 'SIGNER_ASSERTED_NO_RFC3161'
        @($sidecar.SignatureEvidence.PSObject.Properties.Name) | Should -Not -Contain 'VerificationStatus'
        $sidecar.SignatureEvidence.SignatureValueBase64 | Should -Not -BeNullOrEmpty
        $sidecar.SignatureEvidence.SigningCertificateDerBase64 | Should -Not -BeNullOrEmpty
        @(Find-CddsiPotentialSecrets -Content (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $sidecar) `
            -Source '<synthetic-release-sidecar>').Count | Should -Be 0
    }

    It 'rejects forged self-reported validity, ECDSA, empty signatures and wrong claims' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        $sidecar = New-CddsiReleaseSidecarFixture -Manifest $manifest

        $legacy = Copy-CddsiReleaseArtifactFixture -Value $sidecar
        $legacy.SignatureEvidence = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-detached-signature-evidence-v1'
            ClaimsBindingToken = $sidecar.ClaimsBindingToken; SignatureAlgorithm = 'RSA-PSS-SHA256'
            SignatureValueSha256 = $sidecar.SignatureEvidence.SignatureValueSha256
            SigningCertificateSha256 = $sidecar.SignerIdentity.CertificateSha256
            VerificationStatus = 'VALID'; VerificationEvidenceToken = ('f' * 64)
            SignedAtUtc = '2030-01-01T00:10:00Z'; EvidenceBindingToken = ('6' * 64)
        }
        (Test-CddsiReleaseSidecarPayload -Payload $legacy -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse

        foreach ($kind in @('ECDSA', 'Empty', 'Claims')) {
            $attack = Copy-CddsiReleaseArtifactFixture -Value $sidecar
            switch ($kind) {
                'ECDSA' { $attack.SignatureEvidence.SignatureAlgorithm = 'ECDSA-P256-SHA256' }
                'Empty' { $attack.SignatureEvidence.SignatureValueBase64 = '' }
                'Claims' { $attack.SignatureEvidence.ClaimsBindingToken = ('f' * 64) }
            }
            $attack.SignatureEvidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken `
                -SignatureEvidence $attack.SignatureEvidence
            $attack.PayloadBindingToken = Get-CddsiReleaseSidecarPayloadBindingToken -Payload $attack
            (Test-CddsiReleaseSidecarPayload -Payload $attack -Manifest $manifest `
                -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
                -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
        }
    }

    It 'rejects a changed key, changed certificate and signed-claims tampering' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        $sidecar = New-CddsiReleaseSidecarFixture -Manifest $manifest

        $wrongKey = Copy-CddsiReleaseArtifactFixture -Value $sidecar
        $wrongSignature = $script:UserSigner.Rsa.SignData(
            (ConvertTo-CddsiReleaseSidecarClaimsBytes -Payload $wrongKey),
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pss
        )
        $wrongKey.SignatureEvidence.SignatureValueBase64 = [Convert]::ToBase64String($wrongSignature)
        $wrongKey.SignatureEvidence.SignatureValueSha256 = Get-CddsiReleaseFixtureSha256 -Bytes $wrongSignature
        $wrongKey.SignatureEvidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken `
            -SignatureEvidence $wrongKey.SignatureEvidence
        $wrongKey.PayloadBindingToken = Get-CddsiReleaseSidecarPayloadBindingToken -Payload $wrongKey
        (Test-CddsiReleaseSidecarPayload -Payload $wrongKey -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse

        $wrongCertificate = Copy-CddsiReleaseArtifactFixture -Value $sidecar
        $wrongCertificate.SignatureEvidence.SigningCertificateDerBase64 = $script:UserSigner.CertificateDerBase64
        $wrongCertificate.SignatureEvidence.SigningCertificateSha256 = $script:UserSigner.Identity.CertificateSha256
        $wrongCertificate.SignatureEvidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken `
            -SignatureEvidence $wrongCertificate.SignatureEvidence
        $wrongCertificate.PayloadBindingToken = Get-CddsiReleaseSidecarPayloadBindingToken -Payload $wrongCertificate
        (Test-CddsiReleaseSidecarPayload -Payload $wrongCertificate -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse

        $tamperedClaims = Copy-CddsiReleaseArtifactFixture -Value $sidecar
        $tamperedClaims.FinalZipSha256 = 'e' * 64
        $tamperedClaims.ClaimsBindingToken = Get-CddsiReleaseSidecarClaimsBindingToken -Payload $tamperedClaims
        $tamperedClaims.SignatureEvidence.ClaimsBindingToken = $tamperedClaims.ClaimsBindingToken
        $tamperedClaims.SignatureEvidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken `
            -SignatureEvidence $tamperedClaims.SignatureEvidence
        $tamperedClaims.PayloadBindingToken = Get-CddsiReleaseSidecarPayloadBindingToken -Payload $tamperedClaims
        (Test-CddsiReleaseSidecarPayload -Payload $tamperedClaims -Manifest $manifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
    }

    It 'rejects a complete manifest policy, certificate and signature substitution against the external trust anchor' {
        $attackerManifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance `
            -Signer $script:UserSigner
        $attackerSidecar = New-CddsiReleaseSidecarFixture -Manifest $attackerManifest `
            -PayloadSigner $script:UserSigner -SigningSigner $script:UserSigner

        (Test-CddsiReleaseContentManifest -Manifest $attackerManifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy) | Should -BeFalse
        (Test-CddsiReleaseSidecarPayload -Payload $attackerSidecar -Manifest $attackerManifest `
            -ExpectedSignatureTrustPolicy $script:VmSigner.TrustPolicy `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
    }

    It 'rejects future, stale and certificate-expired signer-asserted times' {
        $manifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance
        { New-CddsiReleaseSidecarFixture -Manifest $manifest -SignedAtUtc '2030-01-01T00:21:00Z' } |
            Should -Throw '*failed closed*'
        { New-CddsiReleaseSidecarFixture -Manifest $manifest -SignedAtUtc '2030-01-01T00:10:00Z' `
            -ValidationTimeUtc '2030-01-01T01:10:01Z' } | Should -Throw '*failed closed*'
        { New-CddsiReleaseSidecarFixture -Manifest $manifest -SignedAtUtc '2031-01-01T00:00:01Z' `
            -ValidationTimeUtc '2031-01-01T00:00:01Z' } | Should -Throw '*failed closed*'
    }
}

Describe 'P10B dual-candidate set and P11 promotion boundary' {
    It 'requires exactly one ordered and cryptographically valid candidate per frozen profile' {
        $fixture = New-CddsiReleaseCandidateFixture
        (Test-CddsiReleaseCandidateSet -CandidateSet $fixture.Set -CandidateManifests $fixture.Manifests `
            -CandidateSidecarPayloads $fixture.Sidecars -ExpectedSignatureTrustPolicies $fixture.TrustPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeTrue
        @($fixture.Set.Candidates.ArtifactProfile) | Should -Be @('VmAcceptance', 'UserLive')

        (Test-CddsiReleaseCandidateSet -CandidateSet $fixture.Set -CandidateManifests @($fixture.Manifests[0]) `
            -CandidateSidecarPayloads @($fixture.Sidecars[0]) `
            -ExpectedSignatureTrustPolicies @($fixture.TrustPolicies[0]) `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
        (Test-CddsiReleaseCandidateSet -CandidateSet $fixture.Set `
            -CandidateManifests @($fixture.Manifests[1], $fixture.Manifests[0]) `
            -CandidateSidecarPayloads @($fixture.Sidecars[1], $fixture.Sidecars[0]) `
            -ExpectedSignatureTrustPolicies $fixture.TrustPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
    }

    It 'rejects candidate swaps, ZIP replay and cross-version substitution' {
        $fixture = New-CddsiReleaseCandidateFixture
        $entrySwap = Copy-CddsiReleaseArtifactFixture -Value $fixture.Set
        $first = $entrySwap.Candidates[0]
        $entrySwap.Candidates[0] = $entrySwap.Candidates[1]
        $entrySwap.Candidates[1] = $first
        $entrySwap.SetBindingToken = Get-CddsiReleaseCandidateSetBindingToken -CandidateSet $entrySwap
        (Test-CddsiReleaseCandidateSet -CandidateSet $entrySwap -CandidateManifests $fixture.Manifests `
            -CandidateSidecarPayloads $fixture.Sidecars -ExpectedSignatureTrustPolicies $fixture.TrustPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse

        $zipReplay = Copy-CddsiReleaseArtifactFixture -Value $fixture.Set
        $zipReplay.Candidates[1].FinalZipSha256 = $zipReplay.Candidates[0].FinalZipSha256
        $zipReplay.SetBindingToken = Get-CddsiReleaseCandidateSetBindingToken -CandidateSet $zipReplay
        (Test-CddsiReleaseCandidateSet -CandidateSet $zipReplay -CandidateManifests $fixture.Manifests `
            -CandidateSidecarPayloads $fixture.Sidecars -ExpectedSignatureTrustPolicies $fixture.TrustPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse

        $otherVersion = New-CddsiReleaseCandidateFixture -ArtifactVersion '1.2.4'
        (Test-CddsiReleaseCandidateSet -CandidateSet $fixture.Set -CandidateManifests $otherVersion.Manifests `
            -CandidateSidecarPayloads $otherVersion.Sidecars `
            -ExpectedSignatureTrustPolicies $otherVersion.TrustPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
    }

    It 'rejects a self-consistent candidate set signed under an attacker-controlled replacement policy' {
        $attackerVmManifest = New-CddsiReleaseManifestFixture -ArtifactProfile VmAcceptance `
            -Signer $script:UserSigner
        $userManifest = New-CddsiReleaseManifestFixture -ArtifactProfile UserLive
        $manifests = [object[]]@($attackerVmManifest, $userManifest)
        $sidecars = [object[]]@(
            (New-CddsiReleaseSidecarFixture -Manifest $attackerVmManifest `
                -PayloadSigner $script:UserSigner -SigningSigner $script:UserSigner),
            (New-CddsiReleaseSidecarFixture -Manifest $userManifest)
        )
        $attackerPolicies = [object[]]@($script:UserSigner.TrustPolicy, $script:UserSigner.TrustPolicy)
        $attackerSet = New-CddsiReleaseCandidateSet -CandidateManifests $manifests `
            -CandidateSidecarPayloads $sidecars -ExpectedSignatureTrustPolicies $attackerPolicies `
            -ValidationTimeUtc $script:ReleaseValidationTime

        (Test-CddsiReleaseCandidateSet -CandidateSet $attackerSet -CandidateManifests $manifests `
            -CandidateSidecarPayloads $sidecars `
            -ExpectedSignatureTrustPolicies @($script:VmSigner.TrustPolicy, $script:UserSigner.TrustPolicy) `
            -ValidationTimeUtc $script:ReleaseValidationTime) | Should -BeFalse
    }

    It 'cannot construct or accept PROMOTED state before the P11 acceptance receipt exists' {
        $fixture = New-CddsiReleaseCandidateFixture
        { New-CddsiReleasePromotionReceipt -CandidateSet $fixture.Set `
            -CandidateManifests $fixture.Manifests -CandidateSidecarPayloads $fixture.Sidecars `
            -AcceptanceEvidenceToken ('7' * 64) -PromotionId '70000000-0000-4000-8000-000000000001' `
            -PromotedAtUtc '2030-01-01T01:00:00Z' } | Should -Throw '*P11_ACCEPTANCE_RECEIPT_REQUIRED*'

        $forged = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-promotion-receipt-v1'; State = 'PROMOTED'
        }
        (Test-CddsiReleasePromotionReceipt -PromotionReceipt $forged -CandidateSet $fixture.Set `
            -CandidateManifests $fixture.Manifests -CandidateSidecarPayloads $fixture.Sidecars) | Should -BeFalse
    }
}
