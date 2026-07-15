BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:CandidateBuilderPath = Join-Path $script:RepoRoot 'scripts\build-candidate.ps1'
    . $script:CandidateBuilderPath -ImportOnly

    $script:CandidateVersion = '1.0.0-rc.1'
    $script:CandidateCommit = 'a' * 40
    $script:CandidateValidationTime = '2030-01-01T00:05:00Z'
    $script:CandidateRequestedTime = '2030-01-01T00:03:00Z'
    $script:CandidateObservedTime = '2030-01-01T00:07:00Z'
    $script:CandidateFrozenTime = '2030-01-01T00:08:00Z'
    $script:CandidateHelperId = '81000000-0000-4000-8000-000000000001'
    $script:CandidateBuildId = '81000000-0000-4000-8000-000000000002'
    $script:CandidateRequestId = '81000000-0000-4000-8000-000000000003'
    $script:CandidateObservationId = '81000000-0000-4000-8000-000000000004'
    $script:CandidateFreezeId = '81000000-0000-4000-8000-000000000005'

    function Copy-CddsiCandidateFixtureValue {
        param([Parameter(Mandatory = $true)][AllowNull()]$Value)

        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($key in $Value.Keys) { $copy[$key] = Copy-CddsiCandidateFixtureValue -Value $Value[$key] }
            return $copy
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Value) { $items.Add((Copy-CddsiCandidateFixtureValue -Value $item)) }
            Write-Output -NoEnumerate ([object[]]$items.ToArray())
            return
        }
        $properties = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $properties[$property.Name] = Copy-CddsiCandidateFixtureValue -Value $property.Value
        }
        return [pscustomobject]$properties
    }

    function Write-CddsiCandidateFixtureBytes {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
        )

        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [System.IO.File]::WriteAllBytes($Path, $Bytes)
    }

    function Write-CddsiCandidateFixtureText {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
        )

        Write-CddsiCandidateFixtureBytes -Path $Path `
            -Bytes ((New-Object System.Text.UTF8Encoding($false)).GetBytes($Text))
    }

    function New-CddsiCandidateFrozenFactsFixture {
        $authoritySigner = New-Object System.Security.Cryptography.RSACng 2048
        $authorityParameters = $authoritySigner.ExportParameters($false)
        $authorityPublicKey = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-cas-store-authority-public-key-v1'
            Algorithm = 'RSA-SHA256-PKCS1-v1_5'; KeyId = '82000000-0000-4000-8000-000000000003'
            ModulusBase64 = [Convert]::ToBase64String($authorityParameters.Modulus)
            ExponentBase64 = [Convert]::ToBase64String($authorityParameters.Exponent)
            FingerprintSha256 = $null
        }
        $authorityPublicKey.FingerprintSha256 = Get-CddsiCasStoreAuthorityKeyFingerprint `
            -StoreAuthorityPublicKey $authorityPublicKey
        $source = [pscustomobject][ordered]@{
            SchemaVersion = 1
            SessionAnchorToken = '1' * 64
            SessionBindingToken = '2' * 64
            EvidenceBindingToken = '3' * 64
            ConsumptionStateKeySha256 = '4' * 64
            ConsumptionStateBindingToken = '5' * 64
            ConsumptionCommitReceiptBindingToken = '6' * 64
            ConsumptionId = '82000000-0000-4000-8000-000000000001'
            ConsumptionRevision = 2
            EvidenceCompletedAtUtc = '2030-01-01T00:01:00Z'
        }
        $facts = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-frozen-release-facts-v1'
            Purpose = 'P10B_RELEASE_BUILD_INPUT_ONLY'
            SourceBindings = $source
            OsImage = [pscustomobject][ordered]@{
                Status = 'OBSERVED'; Architecture = 'x64'; Build = 26100; Ubr = 5000
            }
            Msix = [pscustomobject][ordered]@{
                Status = 'OBSERVED'; Flavor = 'Offline'; Scope = 'MACHINE_WIDE'; Version = '1.2.3.4'
            }
            Git = [pscustomobject][ordered]@{
                Status = 'OBSERVED'; Version = '2.53.0.windows.3'
            }
            CredentialHelper = [pscustomobject][ordered]@{
                Result = 'PASS'; TimeoutEnforced = $true; TtlObservedSeconds = 3600
            }
            Chooser = [pscustomobject][ordered]@{
                Result = 'PASS'; Hidden = $true
            }
            HkcuManagedPolicy = [pscustomobject][ordered]@{
                Result = 'PASS'; Effective = $true; ValueType = 'REG_SZ'
            }
            FactsBindingToken = $null
        }
        $facts.FactsBindingToken = Get-CddsiFrozenReleaseFactsBindingToken -Facts $facts
        $available = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-facts-freeze-state-v2'
            Purpose = 'P10B_RELEASE_FACTS_FREEZE_STATE'; StateKeySha256 = $null; State = 'AVAILABLE'
            StoreAuthorityKeyId = $authorityPublicKey.KeyId
            StoreAuthorityKeyFingerprintSha256 = $authorityPublicKey.FingerprintSha256
            StoreInstanceId = '82000000-0000-4000-8000-000000000004'; StoreEpoch = [long]1
            SessionAnchorToken = $source.SessionAnchorToken; SessionBindingToken = $source.SessionBindingToken
            EvidenceBindingToken = $source.EvidenceBindingToken
            ConsumptionStateKeySha256 = $source.ConsumptionStateKeySha256
            ConsumptionStateBindingToken = $source.ConsumptionStateBindingToken
            ConsumptionCommitReceiptBindingToken = $source.ConsumptionCommitReceiptBindingToken
            ConsumptionId = $source.ConsumptionId; FreezeId = $null; FactsBindingToken = $null
            FrozenAtUtc = $null; ExpiresAtUtc = '2030-02-01T00:00:00Z'; Revision = [long]0
            StateBindingToken = $null
        }
        $available.StateKeySha256 = Get-CddsiReleaseFactsFreezeStateKey -FreezeState $available
        $available.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $available
        $freezeState = Copy-CddsiCandidateFixtureValue -Value $available
        $freezeState.State = 'FROZEN'; $freezeState.FreezeId = '82000000-0000-4000-8000-000000000002'
        $freezeState.FactsBindingToken = $facts.FactsBindingToken
        $freezeState.FrozenAtUtc = '2030-01-01T00:02:00Z'; $freezeState.Revision = [long]1
        $freezeState.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $freezeState
        $transactionId = '82000000-0000-4000-8000-000000000005'
        $proposalNonce = '82000000-0000-4000-8000-000000000006'
        $proposal = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-facts-freeze-commit-proposal-v1'
            Purpose = 'P10B_RELEASE_FACTS_FREEZE_COMMIT'; Domain = 'P10B_RELEASE_FACTS_FREEZE'
            StoreAuthorityKeyId = $authorityPublicKey.KeyId
            StoreAuthorityKeyFingerprintSha256 = $authorityPublicKey.FingerprintSha256
            StoreInstanceId = $freezeState.StoreInstanceId; StoreEpoch = $freezeState.StoreEpoch
            TransactionId = $transactionId; StateKeySha256 = $freezeState.StateKeySha256
            OldRevision = [long]0; NewRevision = [long]1; OldStateBindingToken = $available.StateBindingToken
            NewStateBindingToken = $freezeState.StateBindingToken; ProposalNonce = $proposalNonce
            SessionAnchorToken = $source.SessionAnchorToken; SessionBindingToken = $source.SessionBindingToken
            EvidenceBindingToken = $source.EvidenceBindingToken; ConsumptionId = $source.ConsumptionId
            FreezeId = $freezeState.FreezeId; FactsBindingToken = $facts.FactsBindingToken
            ProposedState = $freezeState; ProposalBindingToken = $null
        }
        $proposal.ProposalBindingToken = Get-CddsiReleaseFactsFreezeProposalBindingToken -CommitProposal $proposal
        $commitReceipt = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-cas-commit-receipt-v1'
            Purpose = $proposal.Purpose; Domain = $proposal.Domain
            SignatureAlgorithm = 'RSA-SHA256-PKCS1-v1_5'
            StoreAuthorityKeyId = $proposal.StoreAuthorityKeyId
            StoreAuthorityKeyFingerprintSha256 = $proposal.StoreAuthorityKeyFingerprintSha256
            StoreInstanceId = $proposal.StoreInstanceId; StoreEpoch = $proposal.StoreEpoch
            TransactionId = $proposal.TransactionId; CommitId = '82000000-0000-4000-8000-000000000007'
            StateKeySha256 = $proposal.StateKeySha256; OldRevision = $proposal.OldRevision; NewRevision = $proposal.NewRevision
            OldStateBindingToken = $proposal.OldStateBindingToken; NewStateBindingToken = $proposal.NewStateBindingToken
            ProposalBindingToken = $proposal.ProposalBindingToken; ProposalNonce = $proposal.ProposalNonce
            SessionAnchorToken = $proposal.SessionAnchorToken; SessionBindingToken = $proposal.SessionBindingToken
            EvidenceBindingToken = $proposal.EvidenceBindingToken; ConsumptionId = $proposal.ConsumptionId
            FreezeId = $proposal.FreezeId; FactsBindingToken = $proposal.FactsBindingToken
            CommittedAtUtc = '2030-01-01T00:03:00Z'; ExpiresAtUtc = $freezeState.ExpiresAtUtc
            SignatureBase64 = $null; ReceiptBindingToken = $null
        }
        $receiptBytes = [Text.Encoding]::UTF8.GetBytes((Get-CddsiCasCommitReceiptSigningPayload -CommitReceipt $commitReceipt))
        $receiptSignature = $authoritySigner.SignData($receiptBytes, [Security.Cryptography.HashAlgorithmName]::SHA256,
            [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $commitReceipt.SignatureBase64 = [Convert]::ToBase64String($receiptSignature)
        $commitReceipt.ReceiptBindingToken = Get-CddsiCasCommitReceiptBindingToken -CommitReceipt $commitReceipt
        return [pscustomobject][ordered]@{
            Facts = $facts; FreezeState = $freezeState; CommitReceipt = $commitReceipt
            StoreAuthorityPublicKey = $authorityPublicKey; StoreAuthoritySigner = $authoritySigner
            TransactionId = $transactionId; ProposalNonce = $proposalNonce
        }
    }

    function New-CddsiCandidateHelperEvidenceFixture {
        param(
            [Parameter(Mandatory = $true)][string]$HelperPath,
            [Parameter(Mandatory = $true)][string]$SbomPath
        )

        $descriptor = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-build-v1'
            BuildId = '83000000-0000-4000-8000-000000000001'
            ReleaseVersion = $script:CandidateVersion; CommitId = $script:CandidateCommit
            ImplementationKind = 'SignedDotNetExe'; ProtocolVersion = 'cddsi-credential-helper-protocol-v1'
            ExecutableFileName = 'cddsi-credential-helper.exe'; Architecture = 'X64'
            RuntimeIdentifier = 'win-x64'; TargetFramework = 'net8.0-windows'
            DotNetSdkVersion = '8.0.408'; CompilerVersion = '4.11.0'; RuntimePackVersion = '8.0.15'
            ToolchainDescriptorSha256 = '6' * 64; DependencyLockSha256 = '7' * 64; DependencyCount = 4
            SourceTreeSha256 = '8' * 64; SourceManifestSha256 = '9' * 64; SourceTreeEntryCount = 12
            SbomFormat = 'CycloneDXJson15'; SbomSha256 = Get-CddsiCandidateFileSha256 -Path $SbomPath
            SbomComponentSetSha256 = 'a' * 64; SbomComponentCount = 9
            PeSha256 = Get-CddsiCandidateFileSha256 -Path $HelperPath
            PeSizeBytes = [long]([System.IO.FileInfo]::new($HelperPath).Length)
            ExpectedSignerCertificateSha256 = 'b' * 64; ExpectedSignerSubjectSha256 = 'c' * 64
            Deterministic = $true; SelfContained = $true; SingleFile = $true
            DependencyLockRequired = $true; AuthenticodeRequired = $true
            ProducedAtUtc = '2030-01-01T00:00:00Z'; DescriptorBindingToken = $null
        }
        $descriptor.DescriptorBindingToken = Get-CddsiCredentialHelperBuildDescriptorBindingToken -Descriptor $descriptor
        $signature = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-signature-v1'
            EvidenceId = '83000000-0000-4000-8000-000000000002'; CandidateId = $script:CandidateHelperId
            BuildDescriptorBindingToken = $descriptor.DescriptorBindingToken; PeSha256 = $descriptor.PeSha256
            AuthenticodeStatus = 'Valid'; ChainTrusted = $true
            SignerCertificateSha256 = $descriptor.ExpectedSignerCertificateSha256
            SignerSubjectSha256 = $descriptor.ExpectedSignerSubjectSha256
            TimestampStatus = 'Valid'; TimestampUtc = '2030-01-01T00:01:00Z'
            ObservedAtUtc = '2030-01-01T00:02:00Z'; BindingToken = $null
        }
        $signature.BindingToken = Get-CddsiCredentialHelperSignatureEvidenceBindingToken -Evidence $signature
        return [pscustomobject][ordered]@{ Descriptor = $descriptor; Signature = $signature }
    }

    function New-CddsiCandidateFixture {
        param([Parameter(Mandatory = $true)][string]$TempBase)

        $ledger = [System.Collections.Generic.List[object]]::new()
        $sandbox = New-CddsiOwnedSandbox -TempBase $TempBase -RunId ([guid]::NewGuid().ToString('D')) -Ledger $ledger
        $tracking = [pscustomobject]@{
            Sandbox = $sandbox; Ledger = $ledger; StoreAuthoritySigner = $null
            SidecarSigner = $null; SidecarCertificate = $null
        }
        $script:CandidateFixtureSandboxes.Add($tracking)
        $source = Join-Path $sandbox.Root 'candidate-source'
        [void][System.IO.Directory]::CreateDirectory($source)
        $packageFiles = [string[]]@('Start-Here.ps1', 'config/defaults.json')
        $helperRelative = 'runtime/cddsi-credential-helper.exe'
        $sbomRelative = 'runtime/cddsi-credential-helper.cdx.json'
        Write-CddsiCandidateFixtureText -Path (Join-Path $source 'Start-Here.ps1') -Text "Write-Output 'safe'`r`n"
        Write-CddsiCandidateFixtureText -Path (Join-Path $source 'config\defaults.json') -Text '{"mode":"safe"}'
        $helperBytes = New-Object byte[] 4096
        $helperBytes[0] = 77; $helperBytes[1] = 90
        for ($index = 2; $index -lt $helperBytes.Length; $index++) { $helperBytes[$index] = [byte]($index % 251) }
        $helperPath = Join-Path $source ($helperRelative.Replace('/', '\'))
        $sbomPath = Join-Path $source ($sbomRelative.Replace('/', '\'))
        Write-CddsiCandidateFixtureBytes -Path $helperPath -Bytes $helperBytes
        Write-CddsiCandidateFixtureText -Path $sbomPath -Text '{"bomFormat":"CycloneDX","specVersion":"1.5","components":[{"name":"cddsi-helper"}]}'
        $allPaths = [string[]]@($packageFiles + $helperRelative + $sbomRelative)
        $entries = @(Get-CddsiCandidateSourceContentEntries -Sandbox $sandbox -SourceRoot $source -RelativePaths $allPaths)
        $frozen = New-CddsiCandidateFrozenFactsFixture
        $tracking.StoreAuthoritySigner = $frozen.StoreAuthoritySigner
        $helper = New-CddsiCandidateHelperEvidenceFixture -HelperPath $helperPath -SbomPath $sbomPath
        $sidecarSigner = [System.Security.Cryptography.RSACng]::new(2048)
        $certificateRequest = [System.Security.Cryptography.X509Certificates.CertificateRequest]::new(
            'CN=CDDSI Offline Release Signer', $sidecarSigner,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $certificate = $certificateRequest.CreateSelfSigned(
            [DateTimeOffset]::Parse('2029-12-31T00:00:00Z'),
            [DateTimeOffset]::Parse('2031-01-01T00:00:00Z'))
        $tracking.SidecarSigner = $sidecarSigner; $tracking.SidecarCertificate = $certificate
        $certificateSha256 = Get-CddsiCandidateBytesSha256 -Bytes $certificate.RawData
        $publicKeySha256 = Get-CddsiCandidateBytesSha256 -Bytes $certificate.GetPublicKey()
        $signer = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-signer-identity-v1'; IdentityType = 'X509'
            Subject = $certificate.Subject; CertificateSha256 = $certificateSha256
            KeyId = 'cddsi-offline-release-key-v1'
        }
        $trustPolicy = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-signature-trust-policy-v1'
            SignatureAlgorithm = 'RSA-PSS-SHA256'; ExpectedSubject = $signer.Subject
            ExpectedCertificateSha256 = $certificateSha256; ExpectedPublicKeySha256 = $publicKeySha256
            ExpectedKeyId = $signer.KeyId; SigningRequestId = $script:CandidateRequestId
            SigningNonce = 'a' * 64; MaximumSignatureAgeSeconds = [long]3600
        }
        return [pscustomobject][ordered]@{
            Sandbox = $sandbox; Ledger = $ledger; SourceRoot = $source; PackageFiles = $packageFiles
            HelperRelativePath = $helperRelative; SbomRelativePath = $sbomRelative; ContentEntries = $entries
            FrozenFacts = $frozen.Facts; FreezeState = $frozen.FreezeState
            FreezeCommitReceipt = $frozen.CommitReceipt
            FreezeStoreAuthorityPublicKey = $frozen.StoreAuthorityPublicKey
            FreezeTransactionId = $frozen.TransactionId; FreezeProposalNonce = $frozen.ProposalNonce
            HelperDescriptor = $helper.Descriptor; HelperSignature = $helper.Signature; SignerIdentity = $signer
            SignatureTrustPolicy = $trustPolicy; SidecarSigner = $sidecarSigner; SidecarCertificate = $certificate
        }
    }

    function Invoke-CddsiCandidateFixtureBuild {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [Parameter(Mandatory = $true)][string]$OutputLeaf,
            [ValidateSet('VmAcceptance', 'UserLive')][string]$ArtifactProfile = 'VmAcceptance',
            [AllowNull()]$ContentEntries,
            [AllowNull()][string[]]$PackageFiles,
            [AllowNull()]$HelperDescriptor,
            [AllowNull()]$HelperSignature,
            [ValidateSet('None', 'Cleanup')][string]$FailureInjection = 'None'
        )

        if ($null -eq $ContentEntries) { $ContentEntries = $Fixture.ContentEntries }
        if ($null -eq $PackageFiles) { $PackageFiles = $Fixture.PackageFiles }
        if ($null -eq $HelperDescriptor) { $HelperDescriptor = $Fixture.HelperDescriptor }
        if ($null -eq $HelperSignature) { $HelperSignature = $Fixture.HelperSignature }
        return Invoke-CddsiCandidateBuildPhaseOne -Sandbox $Fixture.Sandbox -SourceRoot $Fixture.SourceRoot `
            -OutputRoot (Join-Path $Fixture.Sandbox.Root $OutputLeaf) -PackageFiles $PackageFiles `
            -HelperRelativePath $Fixture.HelperRelativePath -SbomRelativePath $Fixture.SbomRelativePath `
            -ContentEntries $ContentEntries -FrozenFacts $Fixture.FrozenFacts `
            -CommittedFreezeState $Fixture.FreezeState -FreezeCommitReceipt $Fixture.FreezeCommitReceipt `
            -FreezeStoreAuthorityPublicKey $Fixture.FreezeStoreAuthorityPublicKey `
            -FreezeTransactionId $Fixture.FreezeTransactionId -FreezeProposalNonce $Fixture.FreezeProposalNonce `
            -HelperBuildDescriptor $HelperDescriptor `
            -HelperSignatureEvidence $HelperSignature -HelperCandidateId $script:CandidateHelperId `
            -SidecarSignerIdentity $Fixture.SignerIdentity -SignatureTrustPolicy $Fixture.SignatureTrustPolicy `
            -ArtifactProfile $ArtifactProfile `
            -ArtifactVersion $script:CandidateVersion -CommitId $script:CandidateCommit `
            -BuildId $script:CandidateBuildId -SigningRequestId $script:CandidateRequestId `
            -RequestedAtUtc $script:CandidateRequestedTime -ValidationTimeUtc $script:CandidateValidationTime `
            -DetachedSidecarName ('cddsi-{0}.zip.sidecar.json' -f $ArtifactProfile.ToLowerInvariant()) `
            -ArchiveName ('cddsi-{0}.zip' -f $ArtifactProfile.ToLowerInvariant()) `
            -FailureInjection $FailureInjection
    }

    function New-CddsiCandidateSidecarFixture {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [Parameter(Mandatory = $true)]$BuildResult
        )

        $request = $BuildResult.SigningRequest
        $claimsBytes = [Convert]::FromBase64String($request.ClaimsBytesBase64)
        $signatureBytes = $Fixture.SidecarSigner.SignData(
            $claimsBytes,
            [System.Security.Cryptography.HashAlgorithmName]::SHA256,
            [System.Security.Cryptography.RSASignaturePadding]::Pss)
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 2; ContractVersion = 'cddsi-release-detached-signature-evidence-v2'
            ClaimsBindingToken = $request.ClaimsBindingToken; SignatureAlgorithm = 'RSA-PSS-SHA256'
            SignatureValueBase64 = [Convert]::ToBase64String($signatureBytes)
            SignatureValueSha256 = Get-CddsiCandidateBytesSha256 -Bytes $signatureBytes
            SigningCertificateDerBase64 = [Convert]::ToBase64String($Fixture.SidecarCertificate.RawData)
            SigningCertificateSha256 = $request.SignerIdentity.CertificateSha256
            SignedAtUtc = $request.SignedAtUtc; SigningTimeKind = $request.SigningTimeKind
            EvidenceBindingToken = $null
        }
        $evidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken -SignatureEvidence $evidence
        return New-CddsiReleaseSidecarPayload -Manifest $BuildResult.Manifest `
            -ExpectedSignatureTrustPolicy $Fixture.SignatureTrustPolicy `
            -FinalZipSha256 $BuildResult.FinalZipSha256 `
            -SignerIdentity $request.SignerIdentity -SignatureEvidence $evidence `
            -ValidationTimeUtc $script:CandidateFrozenTime
    }
}

Describe 'P10B sandboxed two-phase candidate assembly' {
    BeforeEach {
        $script:CandidateFixtureSandboxes = [System.Collections.Generic.List[object]]::new()
    }

    AfterEach {
        foreach ($item in @($script:CandidateFixtureSandboxes)) {
            if (Test-Path -LiteralPath $item.Sandbox.Root -PathType Container) {
                Remove-CddsiOwnedSandbox -Sandbox $item.Sandbox -Ledger $item.Ledger
            }
            if ($null -ne $item.StoreAuthoritySigner) { $item.StoreAuthoritySigner.Dispose() }
            if ($null -ne $item.SidecarCertificate) { $item.SidecarCertificate.Dispose() }
            if ($null -ne $item.SidecarSigner) { $item.SidecarSigner.Dispose() }
        }
    }

    It 'is import-only, has no operational top-level statements, and fails closed without parameters' {
        { & $script:CandidateBuilderPath } | Should -Throw '*fail closed*'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:CandidateBuilderPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $forbidden = @(
            'Start-Process', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Get-AuthenticodeSignature',
            'Get-ItemProperty', 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty',
            'Get-Credential', 'Invoke-Expression', 'dotnet'
        )
        @($commands | Where-Object { $forbidden -ccontains $_.GetCommandName() }).Count | Should -Be 0
        $dynamicInvocations = @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -or
                $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
        })
        $dynamicInvocations.Count | Should -Be 5
        @($dynamicInvocations | Where-Object {
            $_.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Dot
        }).Count | Should -Be 0
        $boundary = Import-PowerShellDataFile -LiteralPath (
            Join-Path $script:RepoRoot 'config\execution-boundaries.psd1'
        )
        @($boundary.Planes.TrustedHarness) | Should -Contain 'scripts/build-candidate.ps1'
        @($boundary.Rules.TrustedHarnessDynamicInvocationFiles) |
            Should -Contain 'scripts/build-candidate.ps1'
        $types = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) |
            ForEach-Object { $_.TypeName.FullName })
        @($types | Where-Object { $_ -match 'ProtectedData|Microsoft\.Win32\.Registry|Diagnostics\.Process' }).Count | Should -Be 0
    }

    It 'builds byte-identical fixed-order ZIPs and freezes one externally signed sidecar' {
        $fixture = New-CddsiCandidateFixture -TempBase $TestDrive
        $first = Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'build-one'
        $second = Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'build-two'
        $first.FinalZipSha256 | Should -BeExactly $second.FinalZipSha256
        [System.IO.File]::ReadAllBytes($first.ZipPath) | Should -Be ([System.IO.File]::ReadAllBytes($second.ZipPath))
        $first.Manifest.ArtifactProfile | Should -BeExactly 'VmAcceptance'
        $first.Manifest.Entries.Path | Should -Contain $fixture.HelperRelativePath
        $first.Manifest.Entries.Path | Should -Contain $fixture.SbomRelativePath
        $first.Plane | Should -BeExactly 'TrustedHarness'
        $first.EnvironmentTier | Should -BeExactly 'HostSandbox'
        $first.Simulation | Should -BeTrue
        $first.Publishable | Should -BeFalse
        $first.PublicationBlockCode | Should -BeExactly 'REAL_STORE_AND_SIGNING_RECEIPTS_REQUIRED'
        $first.SigningRequest.Purpose | Should -BeExactly 'HOST_SANDBOX_SIMULATION_ONLY'
        $first.SigningRequest.Publishable | Should -BeFalse
        (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $first.ExpectedSignatureTrustPolicy) |
            Should -BeExactly (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $fixture.SignatureTrustPolicy)
        (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $first.SigningRequest.ExpectedSignatureTrustPolicy) |
            Should -BeExactly (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $fixture.SignatureTrustPolicy)
        (Test-CddsiReleaseContentManifest -Manifest $first.Manifest `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy) | Should -BeTrue
        $wrongTrustAnchor = Copy-CddsiCandidateFixtureValue -Value $fixture.SignatureTrustPolicy
        $wrongTrustAnchor.SigningNonce = 'b' * 64
        (Test-CddsiReleaseContentManifest -Manifest $first.Manifest `
            -ExpectedSignatureTrustPolicy $wrongTrustAnchor) | Should -BeFalse

        $sidecar = New-CddsiCandidateSidecarFixture -Fixture $fixture -BuildResult $first
        (Test-CddsiReleaseSidecarPayload -Payload $sidecar -Manifest $first.Manifest `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -ValidationTimeUtc $script:CandidateFrozenTime) | Should -BeTrue
        (Test-CddsiReleaseSidecarPayload -Payload $sidecar -Manifest $first.Manifest `
            -ExpectedSignatureTrustPolicy $wrongTrustAnchor `
            -ValidationTimeUtc $script:CandidateFrozenTime) | Should -BeFalse
        $observation = New-CddsiCandidateFinalZipObservation -Sandbox $fixture.Sandbox -BuildResult $first `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -ObservationId $script:CandidateObservationId -ObservedAtUtc $script:CandidateObservedTime
        $observation.Plane | Should -BeExactly 'TrustedHarness'
        $observation.EnvironmentTier | Should -BeExactly 'HostSandbox'
        $observation.Simulation | Should -BeTrue
        $receipt = Complete-CddsiCandidateBuildPhaseTwo -Sandbox $fixture.Sandbox -BuildResult $first `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -FinalZipObservation $observation -SidecarPayload $sidecar `
            -FreezeId $script:CandidateFreezeId -FrozenAtUtc $script:CandidateFrozenTime
        $receipt.State | Should -BeExactly 'SIMULATION_FROZEN'
        $receipt.Plane | Should -BeExactly 'TrustedHarness'
        $receipt.EnvironmentTier | Should -BeExactly 'HostSandbox'
        $receipt.Simulation | Should -BeTrue
        $receipt.Publishable | Should -BeFalse
        $receipt.PublicationBlockCode | Should -BeExactly 'REAL_STORE_AND_SIGNING_RECEIPTS_REQUIRED'
        $receipt.FinalZipSha256 | Should -BeExactly $first.FinalZipSha256
        $receipt.SidecarPayloadBindingToken | Should -BeExactly $sidecar.PayloadBindingToken
        $receipt.ReceiptBindingToken | Should -BeExactly (Get-CddsiCandidateFreezeReceiptBindingToken -Receipt $receipt)

        Initialize-CddsiReleaseCompression
        $stream = [System.IO.File]::OpenRead($first.ZipPath)
        try {
            $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
            try {
                @($archive.Entries.FullName) | Should -Not -Contain $first.Manifest.DetachedSidecarName
                @($archive.Entries | ForEach-Object {
                    $_.LastWriteTime.DateTime.ToString('yyyy-MM-ddTHH:mm:ss')
                } | Select-Object -Unique) `
                    | Should -Be @('1980-01-01T00:00:00')
                $expectedOrder = [string[]]@($archive.Entries.FullName)
                [Array]::Sort($expectedOrder, [StringComparer]::Ordinal)
                @($archive.Entries.FullName) | Should -Be $expectedOrder
            }
            finally { $archive.Dispose() }
        }
        finally { $stream.Dispose() }
    }

    It 'rejects content, package, helper, manifest, profile, ZIP hash and sidecar replay' {
        $fixture = New-CddsiCandidateFixture -TempBase $TestDrive
        $entryDrift = Copy-CddsiCandidateFixtureValue -Value $fixture.ContentEntries
        $entryDrift[0].Sha256 = '0' * 64
        { Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'entry-drift' -ContentEntries $entryDrift } `
            | Should -Throw
        { Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'package-drift' `
            -PackageFiles @($fixture.PackageFiles[0]) } | Should -Throw
        $helperDrift = Copy-CddsiCandidateFixtureValue -Value $fixture.HelperDescriptor
        $helperDrift.PeSha256 = '0' * 64
        $helperDrift.DescriptorBindingToken = Get-CddsiCredentialHelperBuildDescriptorBindingToken -Descriptor $helperDrift
        { Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'helper-drift' `
            -HelperDescriptor $helperDrift } | Should -Throw

        $vm = Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'vm'
        $manifestReplay = Copy-CddsiCandidateFixtureValue -Value $vm
        $manifestReplay.Manifest.ArtifactVersion = '1.0.1'
        (Test-CddsiCandidateBuildResult -BuildResult $manifestReplay `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy) | Should -BeFalse
        $publicationReplay = Copy-CddsiCandidateFixtureValue -Value $vm
        $publicationReplay.Publishable = $true
        $publicationReplay.BuildBindingToken = Get-CddsiCandidateBuildBindingToken -BuildResult $publicationReplay
        (Test-CddsiCandidateBuildResult -BuildResult $publicationReplay `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy) | Should -BeFalse
        $requestReplay = Copy-CddsiCandidateFixtureValue -Value $vm.SigningRequest
        $requestReplay.Purpose = 'RELEASE_SIGNING'
        $requestReplay.RequestBindingToken = Get-CddsiCandidateSigningRequestBindingToken -Request $requestReplay
        (Test-CddsiCandidateSigningRequest -Request $requestReplay -Manifest $vm.Manifest `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy) | Should -BeFalse
        $user = Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'user' -ArtifactProfile UserLive
        $vmSidecar = New-CddsiCandidateSidecarFixture -Fixture $fixture -BuildResult $vm
        $userObservation = New-CddsiCandidateFinalZipObservation -Sandbox $fixture.Sandbox -BuildResult $user `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -ObservationId '81000000-0000-4000-8000-000000000006' -ObservedAtUtc $script:CandidateObservedTime
        { Complete-CddsiCandidateBuildPhaseTwo -Sandbox $fixture.Sandbox -BuildResult $user `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -FinalZipObservation $userObservation -SidecarPayload $vmSidecar `
            -FreezeId '81000000-0000-4000-8000-000000000007' -FrozenAtUtc $script:CandidateFrozenTime } `
            | Should -Throw

        $vmObservation = New-CddsiCandidateFinalZipObservation -Sandbox $fixture.Sandbox -BuildResult $vm `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -ObservationId $script:CandidateObservationId -ObservedAtUtc $script:CandidateObservedTime
        $stream = [System.IO.File]::Open($vm.ZipPath, [System.IO.FileMode]::Append, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        try { $stream.WriteByte(1); $stream.Flush() } finally { $stream.Dispose() }
        { Complete-CddsiCandidateBuildPhaseTwo -Sandbox $fixture.Sandbox -BuildResult $vm `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -FinalZipObservation $vmObservation -SidecarPayload $vmSidecar `
            -FreezeId $script:CandidateFreezeId -FrozenAtUtc $script:CandidateFrozenTime } | Should -Throw

        $sidecarReplay = Copy-CddsiCandidateFixtureValue -Value (
            New-CddsiCandidateSidecarFixture -Fixture $fixture -BuildResult $user)
        $invalidSignatureBytes = New-Object byte[] 256
        $sidecarReplay.SignatureEvidence.SignatureValueBase64 = [Convert]::ToBase64String($invalidSignatureBytes)
        $sidecarReplay.SignatureEvidence.SignatureValueSha256 = Get-CddsiCandidateBytesSha256 -Bytes $invalidSignatureBytes
        $sidecarReplay.SignatureEvidence.EvidenceBindingToken = Get-CddsiReleaseSignatureEvidenceBindingToken `
            -SignatureEvidence $sidecarReplay.SignatureEvidence
        $sidecarReplay.PayloadBindingToken = Get-CddsiReleaseSidecarPayloadBindingToken -Payload $sidecarReplay
        { Complete-CddsiCandidateBuildPhaseTwo -Sandbox $fixture.Sandbox -BuildResult $user `
            -ExpectedSignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -FinalZipObservation $userObservation -SidecarPayload $sidecarReplay `
            -FreezeId '81000000-0000-4000-8000-000000000008' -FrozenAtUtc $script:CandidateFrozenTime } `
            | Should -Throw
    }

    It 'rejects output escape, pre-existing output and reparse ancestry before writing' {
        $fixture = New-CddsiCandidateFixture -TempBase $TestDrive
        { Invoke-CddsiCandidateBuildPhaseOne -Sandbox $fixture.Sandbox -SourceRoot $fixture.SourceRoot `
            -OutputRoot (Join-Path $TestDrive 'outside') -PackageFiles $fixture.PackageFiles `
            -HelperRelativePath $fixture.HelperRelativePath -SbomRelativePath $fixture.SbomRelativePath `
            -ContentEntries $fixture.ContentEntries -FrozenFacts $fixture.FrozenFacts `
            -CommittedFreezeState $fixture.FreezeState -FreezeCommitReceipt $fixture.FreezeCommitReceipt `
            -FreezeStoreAuthorityPublicKey $fixture.FreezeStoreAuthorityPublicKey `
            -FreezeTransactionId $fixture.FreezeTransactionId -FreezeProposalNonce $fixture.FreezeProposalNonce `
            -HelperBuildDescriptor $fixture.HelperDescriptor `
            -HelperSignatureEvidence $fixture.HelperSignature -HelperCandidateId $script:CandidateHelperId `
            -SidecarSignerIdentity $fixture.SignerIdentity -SignatureTrustPolicy $fixture.SignatureTrustPolicy `
            -ArtifactProfile VmAcceptance `
            -ArtifactVersion $script:CandidateVersion -CommitId $script:CandidateCommit `
            -BuildId $script:CandidateBuildId -SigningRequestId $script:CandidateRequestId `
            -RequestedAtUtc $script:CandidateRequestedTime -ValidationTimeUtc $script:CandidateValidationTime } `
            | Should -Throw
        $existing = Join-Path $fixture.Sandbox.Root 'existing'
        [void][System.IO.Directory]::CreateDirectory($existing)
        { Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'existing' } | Should -Throw

        $target = Join-Path $fixture.Sandbox.Root 'junction-target'
        $junction = Join-Path $fixture.Sandbox.Root 'junction-link'
        [void][System.IO.Directory]::CreateDirectory($target)
        $null = New-Item -ItemType Junction -Path $junction -Target $target
        try {
            { Invoke-CddsiCandidateBuildPhaseOne -Sandbox $fixture.Sandbox -SourceRoot $fixture.SourceRoot `
                -OutputRoot (Join-Path $junction 'candidate') -PackageFiles $fixture.PackageFiles `
                -HelperRelativePath $fixture.HelperRelativePath -SbomRelativePath $fixture.SbomRelativePath `
                -ContentEntries $fixture.ContentEntries -FrozenFacts $fixture.FrozenFacts `
                -CommittedFreezeState $fixture.FreezeState -FreezeCommitReceipt $fixture.FreezeCommitReceipt `
                -FreezeStoreAuthorityPublicKey $fixture.FreezeStoreAuthorityPublicKey `
                -FreezeTransactionId $fixture.FreezeTransactionId -FreezeProposalNonce $fixture.FreezeProposalNonce `
                -HelperBuildDescriptor $fixture.HelperDescriptor `
                -HelperSignatureEvidence $fixture.HelperSignature -HelperCandidateId $script:CandidateHelperId `
                -SidecarSignerIdentity $fixture.SignerIdentity -SignatureTrustPolicy $fixture.SignatureTrustPolicy `
                -ArtifactProfile VmAcceptance `
                -ArtifactVersion $script:CandidateVersion -CommitId $script:CandidateCommit `
                -BuildId $script:CandidateBuildId -SigningRequestId $script:CandidateRequestId `
                -RequestedAtUtc $script:CandidateRequestedTime -ValidationTimeUtc $script:CandidateValidationTime } `
                | Should -Throw
        }
        finally { [System.IO.Directory]::Delete($junction) }
    }

    It 'fails secret scanning safely, removes owned output, and reports cleanup failure without faking success' {
        $fixture = New-CddsiCandidateFixture -TempBase $TestDrive
        $secretValue = 'sk-' + ('q' * 32)
        Write-CddsiCandidateFixtureText -Path (Join-Path $fixture.SourceRoot 'config\defaults.json') -Text $secretValue
        $allPaths = [string[]]@($fixture.PackageFiles + $fixture.HelperRelativePath + $fixture.SbomRelativePath)
        $fixture.ContentEntries = @(Get-CddsiCandidateSourceContentEntries -Sandbox $fixture.Sandbox `
            -SourceRoot $fixture.SourceRoot -RelativePaths $allPaths)
        $cleanedOutput = Join-Path $fixture.Sandbox.Root 'secret-cleaned'
        { Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'secret-cleaned' } | Should -Throw
        (Test-Path -LiteralPath $cleanedOutput) | Should -BeFalse

        $failedOutput = Join-Path $fixture.Sandbox.Root 'cleanup-failed'
        $failure = $null
        try {
            $null = Invoke-CddsiCandidateFixtureBuild -Fixture $fixture -OutputLeaf 'cleanup-failed' `
                -FailureInjection Cleanup
        }
        catch { $failure = $_.Exception.Data['CddsiCandidateBuildFailure'] }
        $failure.Status | Should -BeExactly 'FAILED_SAFE'
        $failure.CleanupOutcome | Should -BeExactly 'Failed'
        $failure.CleanupErrorCode | Should -BeExactly 'CANDIDATE_CLEANUP_FAILED'
        (Test-Path -LiteralPath $failedOutput -PathType Container) | Should -BeTrue
        Remove-CddsiCandidateOwnedOutput -Sandbox $fixture.Sandbox -OutputRoot $failedOutput
    }
}
