BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:SignatureRunId =
        '27000000-0000-4000-8000-000000000327'
    $script:SignatureStagingRoot = $TestDrive
    $script:SignatureDestination =
        Join-Path $script:SignatureStagingRoot 'Claude-signed-x64.msix'
    $script:SignatureArtifactSha256 = 'a' * 64
    $script:SignatureArtifactSizeBytes = [long]123456789
    $script:SignatureVolumeSerialNumberHex = '12AB34CD'
    $script:SignatureFileIndexHex = '0000000000000327'
    $script:SignaturePublisher =
        'CN=CDDsi Synth' + [char]0x00E9 +
            'tic Claude Publisher, O=CDDsi Test Only, C=US'
    $script:SignatureManifestTemplate = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="Claude" Publisher="__PUBLISHER__" Version="1.2.3.4" ProcessorArchitecture="x64" ResourceId="" />
</Package>
'@

    function Get-CddsiD027TestSha256 {
        param([Parameter(Mandatory = $true)][byte[]]$Bytes)

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [BitConverter]::ToString(
                $sha.ComputeHash($Bytes)
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function New-CddsiD027TestManifestIdentity {
        param(
            [string]$Publisher = $script:SignaturePublisher
        )

        $xml = $script:SignatureManifestTemplate.Replace(
            '__PUBLISHER__',
            $Publisher
        )
        return ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
            -ManifestBytes ([System.Text.Encoding]::UTF8.GetBytes($xml))
    }

    $rsa = [System.Security.Cryptography.RSA]::Create(2048)
    $selfSigned = $null
    try {
        $request =
            [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
                $script:SignaturePublisher,
                $rsa,
                [System.Security.Cryptography.HashAlgorithmName]::SHA256,
                [System.Security.Cryptography.RSASignaturePadding]::Pkcs1
            )
        $usages = New-Object System.Security.Cryptography.OidCollection
        [void]$usages.Add(
            (New-Object System.Security.Cryptography.Oid(
                '1.3.6.1.5.5.7.3.3',
                'Code Signing'
            ))
        )
        $request.CertificateExtensions.Add(
            (New-Object `
                System.Security.Cryptography.X509Certificates.X509EnhancedKeyUsageExtension(
                    $usages,
                    $true
                ))
        )
        $selfSigned = $request.CreateSelfSigned(
            [DateTimeOffset]::UtcNow.AddDays(-1),
            [DateTimeOffset]::UtcNow.AddDays(1)
        )
        $script:SignatureCertificateDer = $selfSigned.Export(
            [System.Security.Cryptography.X509Certificates.X509ContentType]::Cert
        )
    }
    finally {
        if ($null -ne $selfSigned) { $selfSigned.Dispose() }
        $rsa.Dispose()
    }
    $script:SignatureCertificate =
        [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
            $script:SignatureCertificateDer,
            [string]$null,
            [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
        )
    $script:SignatureManifestIdentity =
        New-CddsiD027TestManifestIdentity
    $script:SignatureFinalPathBindingToken =
        Get-CddsiPathBindingToken -Path $script:SignatureDestination
    $script:SignatureFileIdentityToken =
        Get-CddsiD027ClaudeFileIdentityToken `
            -FinalPathBindingToken $script:SignatureFinalPathBindingToken `
            -VolumeSerialNumberHex `
                $script:SignatureVolumeSerialNumberHex `
            -FileIndexHex $script:SignatureFileIndexHex `
            -ArtifactSha256 $script:SignatureArtifactSha256 `
            -ArtifactSizeBytes $script:SignatureArtifactSizeBytes

    function New-CddsiD027TestDownloadReceipt {
        return New-CddsiD027ClaudeDownloadReceipt `
            -RunId $script:SignatureRunId `
            -StagingRootPath $script:SignatureStagingRoot `
            -DestinationPath $script:SignatureDestination `
            -FileIdentityToken $script:SignatureFileIdentityToken `
            -SanitizedRedirectUris ([string[]]@(
                'https://downloads.claude.ai/releases/win32/x64/Claude.msix'
            )) `
            -ArtifactSha256 $script:SignatureArtifactSha256 `
            -ArtifactSizeBytes $script:SignatureArtifactSizeBytes `
            -ObservedAtUtc '2030-01-01T00:00:00Z'
    }

    function New-CddsiD027TestHeldArtifactObservation {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-held-artifact-observation-v1'
            ObservationMethod = 'HeldFinalFileHandle'
            FinalPathBindingToken =
                $script:SignatureFinalPathBindingToken
            FileSystemName = 'NTFS'
            NumberOfLinks = [long]1
            IsDirectory = $false
            IsReparsePoint = $false
            VolumeSerialNumberHex =
                $script:SignatureVolumeSerialNumberHex
            FileIndexHex = $script:SignatureFileIndexHex
            FileIdentityToken = $script:SignatureFileIdentityToken
            ArtifactSha256 = $script:SignatureArtifactSha256
            ArtifactSizeBytes = $script:SignatureArtifactSizeBytes
            ObservedAtUtc = '2030-01-01T00:02:00Z'
        }
    }

    $script:SignatureDownloadReceipt =
        New-CddsiD027TestDownloadReceipt
    $script:SignatureHeldObservation =
        New-CddsiD027TestHeldArtifactObservation

    function New-CddsiD027TestMsixSignatureEvidence {
        param(
            $ManifestIdentity = $script:SignatureManifestIdentity,
            $DownloadReceipt = $script:SignatureDownloadReceipt,
            $HeldArtifactObservation = $script:SignatureHeldObservation,
            [string]$ObservedAtUtc = '2030-01-01T00:03:00Z'
        )

        $certificate = $script:SignatureCertificate
        $certificateDer = $script:SignatureCertificateDer
        $values = [ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-msix-signature-evidence-v1'
            EvidenceKind = 'ClaudeDesktopMsixWinVerifyTrust'
            VerificationMethod = 'WinVerifyTrustGenericVerifyV2'
            SignerExtractionMethod =
                'WinVerifyTrustStateDataPrimarySigner'
            StateLifecycle = 'VerifyExtractPrimarySignerClose'
            RunId = $script:SignatureRunId
            ArtifactProfile = 'VmAcceptance'
            ArtifactType = 'ClaudeDesktopMsix'
            FinalPathBindingToken =
                $HeldArtifactObservation.FinalPathBindingToken
            DownloadReceiptBindingToken =
                $DownloadReceipt.ReceiptBindingToken
            FileIdentityToken =
                $HeldArtifactObservation.FileIdentityToken
            ArtifactSha256 =
                $HeldArtifactObservation.ArtifactSha256
            ArtifactSizeBytes =
                [long]$HeldArtifactObservation.ArtifactSizeBytes
            ContentBindingToken =
                Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 `
                        $HeldArtifactObservation.ArtifactSha256 `
                    -ArtifactSizeBytes `
                        ([long]$HeldArtifactObservation.ArtifactSizeBytes)
            ManifestBindingToken =
                $ManifestIdentity.ManifestBindingToken
            PackageIdentityBindingToken =
                $ManifestIdentity.PackageIdentityBindingToken
            WinVerifyTrustTrusted = $true
            WinVerifyTrustStatus = 'Trusted'
            WinVerifyTrustNativeStatusHex = '0x00000000'
            WinVerifyTrustRevocationMode = 'NotChecked'
            SignerCertificateDerBase64 =
                [Convert]::ToBase64String($certificateDer)
            SignerCertificateDerSha256 =
                Get-CddsiD027TestSha256 -Bytes $certificateDer
            SignerCertificateDerLengthBytes =
                [long]$certificateDer.Length
            SignerCertificateThumbprintSha1 =
                ([string]$certificate.Thumbprint).ToLowerInvariant()
            SignerSubject = [string]$certificate.Subject
            SignerSubjectTextSha256 =
                Get-CddsiD027TestSha256 -Bytes (
                    [System.Text.Encoding]::UTF8.GetBytes(
                        [string]$certificate.Subject
                    )
                )
            SignerSubjectNameRawDataSha256 =
                Get-CddsiD027TestSha256 `
                    -Bytes $certificate.SubjectName.RawData
            ObservedAtUtc = $ObservedAtUtc
        }
        $withoutBinding = [pscustomobject]$values
        $values['EvidenceBindingToken'] =
            Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken `
                -Evidence $withoutBinding
        return [pscustomobject]$values
    }

    function Copy-CddsiD027TestSignatureObject {
        param([Parameter(Mandatory = $true)]$Value)
        return $Value | ConvertTo-Json -Depth 20 | ConvertFrom-Json
    }

    function Set-CddsiD027TestSignatureEvidenceBinding {
        param([Parameter(Mandatory = $true)]$Evidence)

        $Evidence.EvidenceBindingToken =
            Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken `
                -Evidence $Evidence
        return $Evidence
    }

    function Test-CddsiD027TestSignatureEvidence {
        param(
            [Parameter(Mandatory = $true)]$Evidence,
            $ManifestIdentity = $script:SignatureManifestIdentity,
            $DownloadReceipt = $script:SignatureDownloadReceipt,
            $HeldArtifactObservation = $script:SignatureHeldObservation,
            [string]$ExpectedRunId = $script:SignatureRunId,
            [string]$ExpectedStagingRootPath =
                $script:SignatureStagingRoot,
            [string]$ExpectedDestinationPath =
                $script:SignatureDestination,
            [string]$ValidationTimeUtc = '2030-01-01T00:04:00Z'
        )

        return Test-CddsiD027ClaudeMsixSignatureEvidenceContract `
            -Evidence $Evidence `
            -ManifestIdentity $ManifestIdentity `
            -DownloadReceipt $DownloadReceipt `
            -HeldArtifactObservation $HeldArtifactObservation `
            -ExpectedRunId $ExpectedRunId `
            -ExpectedStagingRootPath $ExpectedStagingRootPath `
            -ExpectedDestinationPath $ExpectedDestinationPath `
            -ValidationTimeUtc $ValidationTimeUtc
    }
}

AfterAll {
    if ($null -ne $script:SignatureCertificate) {
        $script:SignatureCertificate.Dispose()
    }
}

Describe 'D-027 Claude MSIX signer evidence pure contract' {
    It 'binds one exact held artifact manifest and same-state signer certificate claim' {
        $evidence = New-CddsiD027TestMsixSignatureEvidence

        @($evidence.PSObject.Properties.Name) -join "`n" |
            Should -BeExactly (@(
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
            ) -join "`n")
        $evidence.EvidenceBindingToken |
            Should -BeExactly (
                Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken `
                    -Evidence $evidence
            )
        $evidence.ManifestBindingToken |
            Should -Not -BeExactly $evidence.PackageIdentityBindingToken
        Test-CddsiD027TestSignatureEvidence -Evidence $evidence |
            Should -BeTrue
    }

    It 'binds raw manifest bytes separately from parsed package identity' {
        $manifest = $script:SignatureManifestIdentity
        $manifest.ManifestSha256 | Should -Match '^[a-f0-9]{64}$'
        $manifest.ManifestLengthBytes | Should -BeGreaterThan 31
        $manifest.ManifestBindingToken |
            Should -BeExactly (
                Get-CddsiD027ClaudeManifestBindingToken `
                    -ManifestIdentity $manifest
            )
        $manifest.ManifestBindingToken |
            Should -Not -BeExactly $manifest.PackageIdentityBindingToken

        $otherBytes = [System.Text.Encoding]::UTF8.GetBytes(
            $script:SignatureManifestTemplate.Replace(
                '__PUBLISHER__',
                $script:SignaturePublisher
            ).Replace('</Package>', "  `n</Package>")
        )
        $other = ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
            -ManifestBytes $otherBytes
        $other.PackageIdentityBindingToken |
            Should -BeExactly $manifest.PackageIdentityBindingToken
        $other.ManifestBindingToken |
            Should -Not -BeExactly $manifest.ManifestBindingToken

        foreach ($mutation in @(
            @{ Name = 'PublisherTextSha256'; Value = ('b' * 64) },
            @{
                Name = 'PublisherParsedX500RawDataSha256'
                Value = ('b' * 64)
            },
            @{ Name = 'PackageIdentityBindingToken'; Value = ('b' * 64) },
            @{ Name = 'PackageName'; Value = 'Other' },
            @{ Name = 'Architecture'; Value = 'arm64' },
            @{ Name = 'PackageVersion'; Value = '1.2.3' },
            @{ Name = 'ResourceId'; Value = 'other' },
            @{ Name = 'ManifestSha256'; Value = ('0' * 64) },
            @{ Name = 'ManifestLengthBytes'; Value = [long](1MB) + 1 }
        )) {
            $changed = Copy-CddsiD027TestSignatureObject -Value $manifest
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            {
                Get-CddsiD027ClaudeManifestBindingToken `
                    -ManifestIdentity $changed
            } | Should -Throw -Because $mutation.Name
        }

        $extra = Copy-CddsiD027TestSignatureObject -Value $manifest
        $extra | Add-Member -NotePropertyName Unexpected -NotePropertyValue 'x'
        {
            Get-CddsiD027ClaudeManifestBindingToken `
                -ManifestIdentity $extra
        } | Should -Throw '*exact binding schema*'
    }

    It 'rejects native trust and state-lifecycle claims after rebinding' {
        $mutations = @(
            @{ Name = 'EvidenceKind'; Value = 'GitInstallerWinVerifyTrust' },
            @{ Name = 'VerificationMethod'; Value = 'GetAuthenticodeSignature' },
            @{ Name = 'SignerExtractionMethod'; Value = 'SeparatePathReopen' },
            @{ Name = 'StateLifecycle'; Value = 'VerifyCloseExtract' },
            @{ Name = 'ArtifactProfile'; Value = 'UserLive' },
            @{ Name = 'ArtifactType'; Value = 'GitForWindowsInstaller' },
            @{ Name = 'WinVerifyTrustTrusted'; Value = $false },
            @{ Name = 'WinVerifyTrustStatus'; Value = 'Untrusted' },
            @{ Name = 'WinVerifyTrustNativeStatusHex'; Value = '0x800B0109' },
            @{ Name = 'WinVerifyTrustRevocationMode'; Value = 'Online' }
        )
        foreach ($mutation in $mutations) {
            $changed = Copy-CddsiD027TestSignatureObject `
                -Value (New-CddsiD027TestMsixSignatureEvidence)
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            $changed = Set-CddsiD027TestSignatureEvidenceBinding `
                -Evidence $changed
            Test-CddsiD027TestSignatureEvidence -Evidence $changed |
                Should -BeFalse -Because $mutation.Name
        }
    }

    It 'rejects certificate and ordinal Publisher drift after rebinding' {
        $mutations = @(
            @{ Name = 'SignerCertificateDerBase64'; Value = ('A' * 512) },
            @{ Name = 'SignerCertificateDerSha256'; Value = ('b' * 64) },
            @{
                Name = 'SignerCertificateDerLengthBytes'
                Value = [long]$script:SignatureCertificateDer.Length + 1
            },
            @{
                Name = 'SignerCertificateThumbprintSha1'
                Value = ('b' * 40)
            },
            @{
                Name = 'SignerSubject'
                Value = $script:SignaturePublisher.ToUpperInvariant()
            },
            @{ Name = 'SignerSubjectTextSha256'; Value = ('b' * 64) },
            @{ Name = 'SignerSubjectNameRawDataSha256'; Value = ('b' * 64) }
        )
        foreach ($mutation in $mutations) {
            $changed = Copy-CddsiD027TestSignatureObject `
                -Value (New-CddsiD027TestMsixSignatureEvidence)
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            $changed = Set-CddsiD027TestSignatureEvidenceBinding `
                -Evidence $changed
            Test-CddsiD027TestSignatureEvidence -Evidence $changed |
                Should -BeFalse -Because $mutation.Name
        }

        $canonicalEquivalentPublisher =
            $script:SignaturePublisher.Replace(
                [string][char]0x00E9,
                ('e' + [char]0x0301)
            )
        foreach ($publisher in @(
                $script:SignaturePublisher.ToUpperInvariant(),
                ($script:SignaturePublisher + ' '),
                $canonicalEquivalentPublisher
            )) {
            $manifest = New-CddsiD027TestManifestIdentity `
                -Publisher $publisher
            $evidence = New-CddsiD027TestMsixSignatureEvidence `
                -ManifestIdentity $manifest
            Test-CddsiD027TestSignatureEvidence `
                -Evidence $evidence `
                -ManifestIdentity $manifest |
                Should -BeFalse -Because $publisher
        }
    }

    It 'rejects artifact receipt held-file run and manifest cross-binding drift' {
        $mutations = @(
            @{ Name = 'RunId'; Value = '27000000-0000-4000-8000-000000000328' },
            @{ Name = 'FinalPathBindingToken'; Value = ('b' * 64) },
            @{ Name = 'DownloadReceiptBindingToken'; Value = ('b' * 64) },
            @{ Name = 'FileIdentityToken'; Value = ('b' * 64) },
            @{ Name = 'ArtifactSha256'; Value = ('b' * 64) },
            @{
                Name = 'ArtifactSizeBytes'
                Value = [long]$script:SignatureArtifactSizeBytes + 1
            },
            @{ Name = 'ContentBindingToken'; Value = ('b' * 64) },
            @{ Name = 'ManifestBindingToken'; Value = ('b' * 64) },
            @{ Name = 'PackageIdentityBindingToken'; Value = ('b' * 64) }
        )
        foreach ($mutation in $mutations) {
            $changed = Copy-CddsiD027TestSignatureObject `
                -Value (New-CddsiD027TestMsixSignatureEvidence)
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            $changed = Set-CddsiD027TestSignatureEvidenceBinding `
                -Evidence $changed
            Test-CddsiD027TestSignatureEvidence -Evidence $changed |
                Should -BeFalse -Because $mutation.Name
        }

        $wrongRun = New-CddsiD027TestMsixSignatureEvidence
        Test-CddsiD027TestSignatureEvidence `
            -Evidence $wrongRun `
            -ExpectedRunId '27000000-0000-4000-8000-000000000328' |
            Should -BeFalse
        Test-CddsiD027TestSignatureEvidence `
            -Evidence $wrongRun `
            -ExpectedDestinationPath (
                Join-Path $script:SignatureStagingRoot 'Other.msix'
            ) |
            Should -BeFalse
    }

    It 'rejects schema type binding and time-window drift' {
        $extra = New-CddsiD027TestMsixSignatureEvidence
        $extra | Add-Member -NotePropertyName Unexpected -NotePropertyValue 'x'
        Test-CddsiD027TestSignatureEvidence -Evidence $extra |
            Should -BeFalse

        $missing = Copy-CddsiD027TestSignatureObject `
            -Value (New-CddsiD027TestMsixSignatureEvidence)
        $missing.PSObject.Properties.Remove('StateLifecycle')
        Test-CddsiD027TestSignatureEvidence -Evidence $missing |
            Should -BeFalse

        foreach ($mutation in @(
            @{ Name = 'ArtifactSizeBytes'; Value = '123456789' },
            @{ Name = 'SignerCertificateDerLengthBytes'; Value = '836' },
            @{ Name = 'EvidenceBindingToken'; Value = ('0' * 64) }
        )) {
            $changed = Copy-CddsiD027TestSignatureObject `
                -Value (New-CddsiD027TestMsixSignatureEvidence)
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            if ($mutation.Name -cne 'EvidenceBindingToken') {
                $changed = Set-CddsiD027TestSignatureEvidenceBinding `
                    -Evidence $changed
            }
            Test-CddsiD027TestSignatureEvidence -Evidence $changed |
                Should -BeFalse -Because (
                    '{0}={1}' -f $mutation.Name, $mutation.Value
                )
        }

        foreach ($timeCase in @(
            @{
                Name = 'before held-file observation'
                ObservedAtUtc = '2030-01-01T00:01:59Z'
                ValidationTimeUtc = '2030-01-01T00:04:00Z'
            },
            @{
                Name = 'after held-file five-minute window only'
                ObservedAtUtc = '2030-01-01T00:07:01Z'
                ValidationTimeUtc = '2030-01-01T00:07:00Z'
            },
            @{
                Name = 'over thirty seconds ahead of validation only'
                ObservedAtUtc = '2030-01-01T00:04:31Z'
                ValidationTimeUtc = '2030-01-01T00:04:00Z'
            }
        )) {
            $changed = New-CddsiD027TestMsixSignatureEvidence `
                -ObservedAtUtc $timeCase.ObservedAtUtc
            Test-CddsiD027TestSignatureEvidence `
                -Evidence $changed `
                -ValidationTimeUtc $timeCase.ValidationTimeUtc |
                Should -BeFalse -Because $timeCase.Name
        }
    }

    It 'keeps direct correlation entrypoints free of Live primitives and exports no Claude Live authority' {
        foreach ($name in @(
                'Get-CddsiD027ClaudeManifestBindingToken',
                'Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken',
                'Test-CddsiD027ClaudeMsixSignatureEvidenceContract'
            )) {
            $command = Get-Command $name -CommandType Function
            foreach ($parameter in @(
                    'Context',
                    'ExecutionContext',
                    'Mode',
                    'Bypass',
                    'ExpectedSigner',
                    'ExpectedPublisher',
                    'ExpectedOperation'
                )) {
                $command.Parameters.Keys | Should -Not -Contain $parameter
            }
            $command.Definition | Should -Not -Match (
                '(?i)Add-Type|Get-AuthenticodeSignature|' +
                'Invoke-WebRequest|Invoke-RestMethod|Start-Process|' +
                'Get-Item|New-Item|Remove-Item|Move-Item|Copy-Item|' +
                'Get-Content|Set-Content|Add-Content|Out-File|' +
                'Test-Path|Resolve-Path|Get-ChildItem|' +
                'Get-ItemProperty|Set-ItemProperty|Add-AppxPackage|' +
                'WTHelperProvDataFromStateData|DllImport'
            )
        }
        (Get-Command Test-CddsiD027ClaudeMsixSignatureEvidenceContract).
            Definition | Should -Match (
                'X509KeyStorageFlags\]::EphemeralKeySet'
            )
        Get-Command Enable-CddsiD027ClaudeLiveSessionAuthorization `
            -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Assert-CddsiD027ClaudeLiveContext `
            -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
    }
}
