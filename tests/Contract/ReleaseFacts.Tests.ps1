BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:ReleaseFactsOperations = @(
        'InspectEnvironment',
        'AcquireCalibrationArtifacts',
        'VerifyCalibrationArtifacts',
        'CalibrateMsixScope',
        'CalibrateCredentialHelper',
        'CalibrateGit',
        'WriteCalibrationEvidence',
        'CleanupCalibrationResources'
    )
    $script:ReleaseFactsValidationTimeUtc = '2026-07-14T00:45:00Z'
    $script:ReleaseFactsFreezeTimeUtc = '2026-07-14T00:46:00Z'
    $script:ReleaseFactsReplayTimeUtc = '2026-07-14T00:47:00Z'
    $script:ReleaseFactsConsumptionId = '90000000-0000-4000-8000-000000000001'
    $script:ReleaseFactsFreezeId = '91000000-0000-4000-8000-000000000001'
    $script:ReleaseFactsConsumptionStoreInstanceId = '93000000-0000-4000-8000-000000000001'
    $script:ReleaseFactsConsumptionTransactionId = '93000000-0000-4000-8000-000000000002'
    $script:ReleaseFactsConsumptionProposalNonce = '93000000-0000-4000-8000-000000000003'
    $script:ReleaseFactsFreezeStoreInstanceId = '94000000-0000-4000-8000-000000000001'
    $script:ReleaseFactsFreezeTransactionId = '94000000-0000-4000-8000-000000000002'
    $script:ReleaseFactsFreezeProposalNonce = '94000000-0000-4000-8000-000000000003'

    function New-CddsiReleaseFactsAuthorityFixture {
        param([Parameter(Mandatory = $true)][string]$KeyId)
        $csp = [System.Security.Cryptography.CspParameters]::new()
        $csp.Flags = [System.Security.Cryptography.CspProviderFlags]::CreateEphemeralKey
        $signer = [System.Security.Cryptography.RSACryptoServiceProvider]::new(2048, $csp)
        $signer.PersistKeyInCsp = $false
        $parameters = $signer.ExportParameters($false)
        $publicKey = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-cas-store-authority-public-key-v1'
            Algorithm = 'RSA-SHA256-PKCS1-v1_5'; KeyId = $KeyId
            ModulusBase64 = [Convert]::ToBase64String($parameters.Modulus)
            ExponentBase64 = [Convert]::ToBase64String($parameters.Exponent)
            FingerprintSha256 = $null
        }
        $publicKey.FingerprintSha256 = Get-CddsiCasStoreAuthorityKeyFingerprint -StoreAuthorityPublicKey $publicKey
        return [pscustomobject]@{ Signer = $signer; PublicKey = $publicKey }
    }

    function New-CddsiReleaseFactsCommitReceiptFixture {
        param(
            [Parameter(Mandatory = $true)]$CommitProposal,
            [Parameter(Mandatory = $true)]$Signer,
            [Parameter(Mandatory = $true)][string]$CommitId,
            [Parameter(Mandatory = $true)][string]$CommittedAtUtc
        )
        $receipt = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-cas-commit-receipt-v1'
            Purpose = $CommitProposal.Purpose; Domain = $CommitProposal.Domain
            SignatureAlgorithm = 'RSA-SHA256-PKCS1-v1_5'
            StoreAuthorityKeyId = $CommitProposal.StoreAuthorityKeyId
            StoreAuthorityKeyFingerprintSha256 = $CommitProposal.StoreAuthorityKeyFingerprintSha256
            StoreInstanceId = $CommitProposal.StoreInstanceId; StoreEpoch = $CommitProposal.StoreEpoch
            TransactionId = $CommitProposal.TransactionId; CommitId = $CommitId
            StateKeySha256 = $CommitProposal.StateKeySha256
            OldRevision = $CommitProposal.OldRevision; NewRevision = $CommitProposal.NewRevision
            OldStateBindingToken = $CommitProposal.OldStateBindingToken
            NewStateBindingToken = $CommitProposal.NewStateBindingToken
            ProposalBindingToken = $CommitProposal.ProposalBindingToken; ProposalNonce = $CommitProposal.ProposalNonce
            SessionAnchorToken = $CommitProposal.SessionAnchorToken; SessionBindingToken = $CommitProposal.SessionBindingToken
            EvidenceBindingToken = $CommitProposal.EvidenceBindingToken; ConsumptionId = $CommitProposal.ConsumptionId
            FreezeId = $CommitProposal.FreezeId; FactsBindingToken = $CommitProposal.FactsBindingToken
            CommittedAtUtc = $CommittedAtUtc; ExpiresAtUtc = $CommitProposal.ProposedState.ExpiresAtUtc
            SignatureBase64 = $null; ReceiptBindingToken = $null
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes((Get-CddsiCasCommitReceiptSigningPayload -CommitReceipt $receipt))
        $signature = $Signer.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $receipt.SignatureBase64 = [Convert]::ToBase64String($signature)
        $receipt.ReceiptBindingToken = Get-CddsiCasCommitReceiptBindingToken -CommitReceipt $receipt
        return $receipt
    }

    $script:ReleaseFactsConsumptionAuthority = New-CddsiReleaseFactsAuthorityFixture -KeyId '93000000-0000-4000-8000-000000000005'
    $script:ReleaseFactsFreezeAuthority = New-CddsiReleaseFactsAuthorityFixture -KeyId '94000000-0000-4000-8000-000000000005'

    function Copy-CddsiReleaseFactsFixture {
        param([Parameter(Mandatory = $true)][AllowNull()]$Value)

        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($key in $Value.Keys) { $copy[$key] = Copy-CddsiReleaseFactsFixture -Value $Value[$key] }
            return $copy
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Value) { $items.Add((Copy-CddsiReleaseFactsFixture -Value $item)) }
            Write-Output -NoEnumerate ([object[]]$items.ToArray())
            return
        }
        $properties = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $properties[$property.Name] = Copy-CddsiReleaseFactsFixture -Value $property.Value
        }
        return [pscustomobject]$properties
    }

    function New-CddsiReleaseFactsOsFixture {
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = '2026-07-14T00:04:00Z'; ImageSha256 = ('6' * 64)
            Sku = 'Windows11Pro24H2'; Architecture = 'x64'; Build = 26100; Ubr = 5000
            Language = 'zh-CN'; PatchDate = '2026-07-01'; NestedVirtualization = 'SUPPORTED'; FailureCode = ''
        }
    }

    function New-CddsiReleaseFactsMsixFixture {
        param([Parameter(Mandatory = $true)][ValidateSet('Standard', 'Offline')][string]$Flavor)

        $observedAt = if ($Flavor -ceq 'Standard') { '2026-07-14T00:10:00Z' } else { '2026-07-14T00:20:00Z' }
        $sourceUri = if ($Flavor -ceq 'Offline') {
            'https://claude.ai/api/desktop/win32/x64/offline/latest/redirect'
        }
        else { 'https://claude.ai/api/desktop/win32/x64/latest/redirect' }
        $artifactSha = if ($Flavor -ceq 'Offline') { ('e' * 64) } else { ('f' * 64) }
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = $observedAt; Flavor = $Flavor; SourceUri = $sourceUri
            RedirectUri = ('https://downloads.claude.ai/windows/Claude-{0}-1.2.3.4-x64.msix' -f $Flavor.ToLowerInvariant())
            RedirectCount = 1; Version = '1.2.3.4'; SizeBytes = 104857600; ArtifactSha256 = $artifactSha
            Signer = [pscustomobject][ordered]@{
                AuthenticodeStatus = 'VALID'; ChainTrusted = $true
                Subject = 'CN=Anthropic PBC, O=Anthropic PBC, C=US'; Thumbprint = ('1' * 40); TimestampStatus = 'VALID'
            }
            Certificate = [pscustomobject][ordered]@{
                CertificateSha256 = ('2' * 64); SerialNumber = '0A12'
                NotBeforeUtc = '2026-01-01T00:00:00Z'; NotAfterUtc = '2027-01-01T00:00:00Z'
            }
            ManifestIdentity = [pscustomobject][ordered]@{
                Name = 'Claude'; Publisher = 'CN=Anthropic PBC, O=Anthropic PBC, C=US'; Version = '1.2.3.4'
                ProcessorArchitecture = 'x64'; ResourceId = ''; PackageFamilyName = 'Claude_abcdef'
                PackageFullName = 'Claude_1.2.3.4_x64__abcdef'
            }
            Deployments = [pscustomobject][ordered]@{
                PerUser = [pscustomobject][ordered]@{
                    Result = 'FAIL'; PackageInstalled = $true; CoworkService = 'ABSENT'; ErrorCode = 'COWORK_SERVICE_ABSENT'
                }
                MachineWide = [pscustomobject][ordered]@{
                    Result = 'PASS'; PackageInstalled = $true; CoworkService = 'PRESENT'; ErrorCode = ''
                }
                RecommendedScope = 'MACHINE_WIDE'; RecommendationCode = 'COWORK_SERVICE_REQUIRED'
            }
            FailureCode = ''
        }
    }

    function New-CddsiReleaseFactsGitFixture {
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = '2026-07-14T00:25:00Z'; ReleaseTag = 'v2.53.0.windows.3'
            AssetName = 'Git-2.53.0.3-64-bit.exe'
            SourceUri = 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.3/Git-2.53.0.3-64-bit.exe'
            Version = '2.53.0.windows.3'; SizeBytes = 68157440; ArtifactSha256 = ('3' * 64)
            Signer = [pscustomobject][ordered]@{
                AuthenticodeStatus = 'VALID'; ChainTrusted = $true
                Subject = 'CN=Open Source Developer, O=Git for Windows, C=US'
                Thumbprint = ('4' * 40); CertificateSha256 = ('5' * 64)
            }
            PeIdentity = [pscustomobject][ordered]@{
                OriginalFilename = 'Git-2.53.0.3-64-bit.exe'; ProductName = 'Git for Windows'
                CompanyName = 'The Git Development Community'; FileVersion = '2.53.0.3'; Machine = 'x64'
            }
            FailureCode = ''
        }
    }

    function New-CddsiReleaseFactsBehaviorFixture {
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = '2026-07-14T00:30:00Z'
            Helper = [pscustomobject][ordered]@{
                Result = 'PASS'; Invoked = $true; StdoutSingleToken = $true; StderrSafe = $true
                TimeoutEnforced = $true; TtlObservedSeconds = 3600; SilentRefreshObserved = $true; ErrorCode = ''
            }
            Chooser = [pscustomobject][ordered]@{
                Result = 'PASS'; Hidden = $true; DeveloperModeSkipped = $true; AnthropicLoginSkipped = $true; ErrorCode = ''
            }
            HkcuManagedPolicy = [pscustomobject][ordered]@{
                Result = 'PASS'; Effective = $true; ValueType = 'REG_SZ'; ValueCount = 15
                HelperReferenceUsed = $true; ConfigLibraryWriterUsed = $false; RawValuesCaptured = $false; ErrorCode = ''
            }
            FailureCode = ''
        }
    }

    function New-CddsiReleaseFactsCleanupFixture {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; Status = 'COMPLETE'; ObservedAtUtc = '2026-07-14T00:35:00Z'
            CalibrationArtifactsRemoved = $true; TemporaryCredentialRemoved = $true
            TemporaryPolicyRemoved = $true; DesktopProcessesStopped = $true; FailureCode = ''
        }
    }

    function New-CddsiReleaseFactsSessionFixture {
        param(
            [Parameter(Mandatory = $true)]$OperationEvidenceRecords,
            [ValidateSet(1, 2)][int]$Variant = 1
        )

        $artifactSha = if ($Variant -eq 1) { ('a' * 64) } else { ('9' * 64) }
        $sidecarSha = if ($Variant -eq 1) { ('b' * 64) } else { ('8' * 64) }
        $contentDigest = if ($Variant -eq 1) { ('c' * 64) } else { ('7' * 64) }
        $suffix = if ($Variant -eq 1) { '000000000001' } else { '000000000002' }
        $runId = "22222222-2222-4222-8222-$suffix"
        $grantId = "11111111-1111-4111-8111-$suffix"
        $nonce = "33333333-3333-4333-8333-$suffix"
        $claimId = "44444444-4444-4444-8444-$suffix"
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-stage-manifest-v1'; Stage = 'VmCalibration'
            ArtifactProfile = 'VmCalibration'; ArtifactVersion = '0.10.0-calibration'; CommitId = ('d' * 40)
            ArtifactSha256 = $artifactSha; SidecarSha256 = $sidecarSha; ContentDigest = $contentDigest
            CreatedAtUtc = '2026-07-14T00:00:00Z'
        }
        $bindings = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $script:ReleaseFactsOperations.Count; $index++) {
            $bindings.Add([pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId = ('50000000-0000-4000-8000-{0:d12}' -f (($Variant * 100) + $index + 1))
                Operation = $script:ReleaseFactsOperations[$index]; PromptDigest = (([string]($index + 1)) * 64); Required = $true
            })
        }
        $grant = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-operation-grant-v2'; GrantId = $grantId
            ArtifactSha256 = $artifactSha; SidecarSha256 = $sidecarSha; ContentDigest = $contentDigest
            ArtifactProfile = 'VmCalibration'; RunId = $runId; IssuedAtUtc = '2026-07-14T00:01:00Z'
            ExpiresAtUtc = '2026-07-14T01:00:00Z'; Nonce = $nonce
            AllowedOperations = [string[]]$script:ReleaseFactsOperations; SingleUse = $true
            ConfirmationBindings = [object[]]$bindings.ToArray()
        }
        $authorization = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-authorization-session-v1'; State = 'CLAIMED'
            GrantId = $grantId; Nonce = $nonce; ClaimId = $claimId; RunId = $runId
            ArtifactSha256 = $artifactSha; SidecarSha256 = $sidecarSha; ContentDigest = $contentDigest
            ArtifactProfile = 'VmCalibration'; ClaimedAtUtc = '2026-07-14T00:02:00Z'
            ExpiresAtUtc = '2026-07-14T01:00:00Z'; Revision = 1
        }
        $workflow = New-CddsiWorkflowSessionState -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $authorization
        $availableStates = @($script:ReleaseFactsOperations | ForEach-Object {
            New-CddsiOperationUseState -StageManifest $manifest -OperationGrant $grant `
                -AuthorizationSession $authorization -WorkflowSessionState $workflow -Operation $_
        })
        $anchor = Get-CddsiVmCalibrationSessionAnchorToken -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $authorization -WorkflowSessionState $workflow -OperationUseStates $availableStates
        $claimTimes = @(
            '2026-07-14T00:04:30Z', '2026-07-14T00:25:30Z', '2026-07-14T00:26:30Z', '2026-07-14T00:27:30Z',
            '2026-07-14T00:30:30Z', '2026-07-14T00:31:30Z', '2026-07-14T00:33:30Z', '2026-07-14T00:35:30Z'
        )
        $terminalTimes = @(
            '2026-07-14T00:05:00Z', '2026-07-14T00:26:00Z', '2026-07-14T00:27:00Z', '2026-07-14T00:28:00Z',
            '2026-07-14T00:31:00Z', '2026-07-14T00:32:00Z', '2026-07-14T00:34:00Z', '2026-07-14T00:36:00Z'
        )
        $terminalStates = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $script:ReleaseFactsOperations.Count; $index++) {
            $operation = $script:ReleaseFactsOperations[$index]
            $binding = @($grant.ConfirmationBindings | Where-Object { $_.Operation -ceq $operation })[0]
            $confirmation = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-interactive-confirmation-v2'
                ConfirmationId = $binding.ConfirmationId; GrantId = $grantId; ClaimId = $claimId
                PromptDigest = $binding.PromptDigest; ArtifactSha256 = $artifactSha; SidecarSha256 = $sidecarSha
                ContentDigest = $contentDigest; ArtifactProfile = 'VmCalibration'; RunId = $runId; Nonce = $nonce
                Operation = $operation; Confirmed = $true; ConfirmedAtUtc = $claimTimes[$index]
            }
            $operationUseId = '60000000-0000-4000-8000-{0:d12}' -f (($Variant * 100) + $index + 1)
            $authorizationResult = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
                -AuthorizationSession $authorization -WorkflowSessionState $workflow -OperationUseState $availableStates[$index] `
                -Confirmation $confirmation -Operation $operation -OperationUseId $operationUseId `
                -ExpectedRevision 0 -RunId $runId -NowUtc $claimTimes[$index]
            if (-not $authorizationResult.Data.AuthorizationProposed) { throw 'Synthetic release-facts operation claim failed.' }
            $terminalResult = Resolve-CddsiOperationUseTerminal -StageManifest $manifest -OperationGrant $grant `
                -AuthorizationSession $authorization -WorkflowSessionState $workflow `
                -OperationUseState $authorizationResult.Data.ProposedOperationUseState -Operation $operation `
                -OperationUseId $operationUseId -ExpectedRevision 1 -Outcome COMPLETED `
                -ProviderEvidenceDigest $OperationEvidenceRecords[$index].ProviderEvidenceDigest `
                -OccurredAtUtc $terminalTimes[$index] `
                -IdempotencyKey ('70000000-0000-4000-8000-{0:d12}' -f (($Variant * 100) + $index + 1))
            if (-not $terminalResult.Data.Terminalized) { throw 'Synthetic release-facts terminal receipt failed.' }
            $terminalStates.Add($terminalResult.Data.TerminalOperationUseState)
        }
        $workflowResult = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $authorization -WorkflowSessionState $workflow -OperationUseStates @($terminalStates) `
            -ExpectedRevision $workflow.Revision -Outcome COMPLETED -OccurredAtUtc '2026-07-14T00:40:00Z' `
            -IdempotencyKey ('80000000-0000-4000-8000-{0:d12}' -f $Variant)
        if (-not $workflowResult.Data.Terminalized) {
            throw ('Synthetic release-facts workflow terminal receipt failed: {0}' -f (ConvertTo-CddsiJson -InputObject $workflowResult))
        }
        $session = [pscustomobject][ordered]@{
            SchemaVersion = 2; ContractVersion = 'cddsi-vm-calibration-session-v2'
            StageManifest = $manifest; OperationGrant = $grant; AuthorizationSession = $authorization
            WorkflowSessionState = $workflowResult.Data.TerminalWorkflowSessionState
            OperationUseStates = @($terminalStates); SessionAnchorToken = $anchor; SessionBindingToken = $null
        }
        $session.SessionBindingToken = Get-CddsiVmCalibrationSessionBindingToken -ExpectedSession $session
        return $session
    }

    function New-CddsiReleaseFactsBundleFixture {
        param([ValidateSet(1, 2)][int]$Variant = 1)

        $os = New-CddsiReleaseFactsOsFixture
        $candidates = @((New-CddsiReleaseFactsMsixFixture -Flavor Standard), (New-CddsiReleaseFactsMsixFixture -Flavor Offline))
        $git = New-CddsiReleaseFactsGitFixture
        $behavior = New-CddsiReleaseFactsBehaviorFixture
        $cleanup = New-CddsiReleaseFactsCleanupFixture
        $selection = Resolve-CddsiVmCalibrationSelection -MsixCandidates $candidates
        $readiness = Resolve-CddsiVmCalibrationReadiness -OsImage $os -MsixCandidates $candidates `
            -Selection $selection -Git $git -DesktopBehavior $behavior
        $records = Get-CddsiVmCalibrationOperationEvidenceRecords -ObservationStartedAtUtc '2026-07-14T00:03:00Z' `
            -OsImage $os -MsixCandidates $candidates -Selection $selection -Git $git `
            -DesktopBehavior $behavior -Readiness $readiness -Cleanup $cleanup
        $session = New-CddsiReleaseFactsSessionFixture -OperationEvidenceRecords $records -Variant $Variant
        $evidence = New-CddsiVmCalibrationEvidence -ExpectedSession $session `
            -ExpectedSessionAnchorToken $session.SessionAnchorToken -ValidationTimeUtc $script:ReleaseFactsValidationTimeUtc `
            -ObservationStartedAtUtc '2026-07-14T00:03:00Z' -OsImage $os -MsixCandidates $candidates `
            -Git $git -DesktopBehavior $behavior -Cleanup $cleanup
        $available = New-CddsiVmCalibrationConsumptionState -ExpectedSession $session `
            -ExpectedSessionAnchorToken $session.SessionAnchorToken `
            -StoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -StoreInstanceId $script:ReleaseFactsConsumptionStoreInstanceId -StoreEpoch 1 `
            -ValidationTimeUtc $script:ReleaseFactsValidationTimeUtc
        $commit = Resolve-CddsiVmCalibrationConsumption -Evidence $evidence -ExpectedSession $session `
            -ExpectedSessionAnchorToken $session.SessionAnchorToken -ConsumptionState $available `
            -StoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -ConsumptionId $script:ReleaseFactsConsumptionId `
            -TransactionId $script:ReleaseFactsConsumptionTransactionId `
            -ProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
            -CommittedConsumptionReceipt $null -ExpectedRevision 0 `
            -ValidationTimeUtc $script:ReleaseFactsValidationTimeUtc
        if ($commit.Status -cne 'READY_TO_COMMIT') { throw 'Synthetic P10A consumption did not produce a commit proposal.' }
        $consumed = $commit.ProposedConsumptionState
        $receipt = New-CddsiReleaseFactsCommitReceiptFixture -CommitProposal $commit.CommitProposal `
            -Signer $script:ReleaseFactsConsumptionAuthority.Signer `
            -CommitId '93000000-0000-4000-8000-000000000004' `
            -CommittedAtUtc $script:ReleaseFactsValidationTimeUtc
        $ready = Resolve-CddsiVmCalibrationConsumption -Evidence $evidence -ExpectedSession $session `
            -ExpectedSessionAnchorToken $session.SessionAnchorToken -ConsumptionState $consumed `
            -StoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -ConsumptionId $script:ReleaseFactsConsumptionId `
            -TransactionId $script:ReleaseFactsConsumptionTransactionId `
            -ProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
            -CommittedConsumptionReceipt $receipt -ExpectedRevision 1 `
            -ValidationTimeUtc $script:ReleaseFactsValidationTimeUtc
        if ($ready.Status -cne 'READY_TO_FREEZE') { throw 'Synthetic P10A consumption receipt is not committed.' }
        return [pscustomobject][ordered]@{
            Session = $session; Evidence = $evidence; AvailableConsumptionState = $available
            CommittedConsumptionState = $consumed; CommittedConsumptionReceipt = $receipt
        }
    }

    function New-CddsiReleaseFactsFreezeFixture {
        param([Parameter(Mandatory = $true)]$Bundle)

        return New-CddsiReleaseFactsFreezeState -Evidence $Bundle.Evidence -ExpectedSession $Bundle.Session `
            -ExpectedSessionAnchorToken $Bundle.Session.SessionAnchorToken `
            -CommittedConsumptionState $Bundle.CommittedConsumptionState `
            -CommittedConsumptionReceipt $Bundle.CommittedConsumptionReceipt `
            -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
            -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
            -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
            -FreezeStoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey `
            -FreezeStoreInstanceId $script:ReleaseFactsFreezeStoreInstanceId -FreezeStoreEpoch 1 `
            -ValidationTimeUtc $script:ReleaseFactsFreezeTimeUtc
    }

    function Resolve-CddsiReleaseFactsFixture {
        param(
            [Parameter(Mandatory = $true)]$Bundle,
            [Parameter(Mandatory = $true)]$FreezeState,
            [string]$FreezeId = $script:ReleaseFactsFreezeId,
            [int]$ExpectedRevision = 0,
            [string]$ValidationTimeUtc = $script:ReleaseFactsFreezeTimeUtc,
            [AllowNull()]$CommittedFreezeReceipt = $null,
            $FreezeStoreAuthorityPublicKey = $script:ReleaseFactsFreezeAuthority.PublicKey,
            [string]$FreezeTransactionId = $script:ReleaseFactsFreezeTransactionId,
            [string]$FreezeProposalNonce = $script:ReleaseFactsFreezeProposalNonce
        )

        return Resolve-CddsiFrozenReleaseFacts -Evidence $Bundle.Evidence -ExpectedSession $Bundle.Session `
            -ExpectedSessionAnchorToken $Bundle.Session.SessionAnchorToken `
            -CommittedConsumptionState $Bundle.CommittedConsumptionState `
            -CommittedConsumptionReceipt $Bundle.CommittedConsumptionReceipt `
            -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
            -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
            -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
            -FreezeState $FreezeState -FreezeStoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey `
            -FreezeId $FreezeId -FreezeTransactionId $FreezeTransactionId -FreezeProposalNonce $FreezeProposalNonce `
            -CommittedFreezeReceipt $CommittedFreezeReceipt -ExpectedRevision $ExpectedRevision `
            -ValidationTimeUtc $ValidationTimeUtc
    }
}

Describe 'P10B frozen release facts exact contract' {
    BeforeAll {
        $script:Bundle = New-CddsiReleaseFactsBundleFixture
        $script:FreezeState = New-CddsiReleaseFactsFreezeFixture -Bundle $script:Bundle
    }

    It 'requires a committed P10A receipt before constructing the freeze state' {
        {
            New-CddsiReleaseFactsFreezeState -Evidence $script:Bundle.Evidence -ExpectedSession $script:Bundle.Session `
                -ExpectedSessionAnchorToken $script:Bundle.Session.SessionAnchorToken `
                -CommittedConsumptionState $script:Bundle.AvailableConsumptionState `
                -CommittedConsumptionReceipt $script:Bundle.CommittedConsumptionReceipt `
                -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
                -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
                -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
                -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
                -FreezeStoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey `
                -FreezeStoreInstanceId $script:ReleaseFactsFreezeStoreInstanceId -FreezeStoreEpoch 1 `
                -ValidationTimeUtc $script:ReleaseFactsFreezeTimeUtc
        } | Should -Throw
    }

    It 'creates an exact source-bound AVAILABLE state' {
        (Test-CddsiReleaseFactsFreezeState -FreezeState $script:FreezeState) | Should -BeTrue
        $script:FreezeState.State | Should -BeExactly 'AVAILABLE'
        $script:FreezeState.Revision | Should -Be 0
        $script:FreezeState.SessionBindingToken | Should -BeExactly $script:Bundle.Session.SessionBindingToken
        $script:FreezeState.EvidenceBindingToken | Should -BeExactly $script:Bundle.Evidence.EvidenceBindingToken
        $script:FreezeState.ConsumptionStateBindingToken | Should -BeExactly $script:Bundle.CommittedConsumptionState.StateBindingToken
        $script:FreezeState.ConsumptionCommitReceiptBindingToken | Should -BeExactly $script:Bundle.CommittedConsumptionReceipt.ReceiptBindingToken
        $script:FreezeState.StoreAuthorityKeyFingerprintSha256 | Should -BeExactly $script:ReleaseFactsFreezeAuthority.PublicKey.FingerprintSha256
    }

    It 'requires CAS before exposing any frozen facts' {
        $proposal = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $script:FreezeState
        $proposal.Status | Should -BeExactly 'READY_TO_COMMIT'
        $proposal.RequiresAtomicCompareAndSwap | Should -BeTrue
        $proposal.CanUseFrozenFacts | Should -BeFalse
        $proposal.FrozenReleaseFacts | Should -BeNullOrEmpty
        $proposal.ProposedFreezeState.State | Should -BeExactly 'FROZEN'
        $proposal.ProposedFreezeState.Revision | Should -Be 1
        (Test-CddsiReleaseFactsFreezeState -FreezeState $proposal.ProposedFreezeState) | Should -BeTrue
        (Test-CddsiReleaseFactsFreezeCommitProposal -CommitProposal $proposal.CommitProposal) | Should -BeTrue
        $proposal.IntegrityTokensAreAuthorization | Should -BeFalse
    }

    It 'returns exact facts only after committed-state idempotent replay' {
        $proposal = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $script:FreezeState
        $receipt = New-CddsiReleaseFactsCommitReceiptFixture -CommitProposal $proposal.CommitProposal `
            -Signer $script:ReleaseFactsFreezeAuthority.Signer `
            -CommitId '94000000-0000-4000-8000-000000000004' -CommittedAtUtc $script:ReleaseFactsFreezeTimeUtc
        $frozen = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $receipt `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        $frozen.Status | Should -BeExactly 'FROZEN'
        $frozen.CanUseFrozenFacts | Should -BeTrue
        $frozen.IdempotentReplay | Should -BeTrue
        $facts = $frozen.FrozenReleaseFacts
        $facts.Msix.Flavor | Should -BeExactly 'Standard'
        $facts.Msix.Scope | Should -BeExactly 'MACHINE_WIDE'
        $facts.Msix.Deployment.Result | Should -BeExactly 'PASS'
        $facts.Git.Version | Should -BeExactly '2.53.0.windows.3'
        $facts.CredentialHelper.Result | Should -BeExactly 'PASS'
        $facts.Chooser.Hidden | Should -BeTrue
        $facts.HkcuManagedPolicy.ValueType | Should -BeExactly 'REG_SZ'
        $facts.HkcuManagedPolicy.ValueCount | Should -Be 15
        (ConvertTo-CddsiJson -InputObject $facts) | Should -Not -Match '(?i)NOT_OBSERVED|"(?:Status|Result)"\s*:\s*"(?:FAILED|FAIL)"'
        (Test-CddsiFrozenReleaseFacts -Facts $facts -Evidence $script:Bundle.Evidence `
            -ExpectedSession $script:Bundle.Session -ExpectedSessionAnchorToken $script:Bundle.Session.SessionAnchorToken `
            -CommittedConsumptionState $script:Bundle.CommittedConsumptionState `
            -CommittedConsumptionReceipt $script:Bundle.CommittedConsumptionReceipt `
            -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
            -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
            -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
            -CommittedFreezeState $proposal.ProposedFreezeState -CommittedFreezeReceipt $receipt `
            -FreezeStoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey `
            -ExpectedFreezeId $script:ReleaseFactsFreezeId `
            -ExpectedFreezeTransactionId $script:ReleaseFactsFreezeTransactionId `
            -ExpectedFreezeProposalNonce $script:ReleaseFactsFreezeProposalNonce `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc) | Should -BeTrue
    }
}

Describe 'P10B frozen release facts attack resistance' {
    BeforeAll {
        $script:Bundle = New-CddsiReleaseFactsBundleFixture
        $script:FreezeState = New-CddsiReleaseFactsFreezeFixture -Bundle $script:Bundle
        $script:Proposal = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $script:FreezeState
        $script:CommittedFreezeReceipt = New-CddsiReleaseFactsCommitReceiptFixture -CommitProposal $script:Proposal.CommitProposal `
            -Signer $script:ReleaseFactsFreezeAuthority.Signer `
            -CommitId '94000000-0000-4000-8000-000000000004' -CommittedAtUtc $script:ReleaseFactsFreezeTimeUtc
    }

    It 'rejects a stale CAS revision' {
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $script:FreezeState -ExpectedRevision 1
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'FREEZE_CONCURRENCY_CONFLICT'

        $committedResult = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 0 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        $committedResult.CanUseFrozenFacts | Should -BeFalse
        $committedResult.ReasonCodes | Should -Contain 'FREEZE_CONCURRENCY_CONFLICT'
    }

    It 'never treats the raw freeze proposal state as a committed receipt' {
        $raw = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        $raw.Status | Should -BeExactly 'BLOCKED'
        $raw.CanUseFrozenFacts | Should -BeFalse
        $raw.ReasonCodes | Should -Contain 'FREEZE_SIGNED_RECEIPT_REQUIRED'
    }

    It 'rejects forged signatures, wrong authorities and proposal replay fields' {
        $forged = Copy-CddsiReleaseFactsFixture -Value $script:CommittedFreezeReceipt
        $forged.CommitId = '94000000-0000-4000-8000-000000000099'
        $forged.ReceiptBindingToken = Get-CddsiCasCommitReceiptBindingToken -CommitReceipt $forged
        (Test-CddsiCasCommitReceiptSignature -CommitReceipt $forged `
            -StoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey) | Should -BeFalse
        (Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $forged -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc).CanUseFrozenFacts | Should -BeFalse

        $otherAuthority = New-CddsiReleaseFactsAuthorityFixture -KeyId '94000000-0000-4000-8000-000000000006'
        try {
            (Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
                -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
                -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
                -FreezeStoreAuthorityPublicKey $otherAuthority.PublicKey `
                -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc).CanUseFrozenFacts | Should -BeFalse
        }
        finally { $otherAuthority.Signer.Dispose() }

        (Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -FreezeTransactionId '94000000-0000-4000-8000-000000000007' `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc).CanUseFrozenFacts | Should -BeFalse
        (Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -FreezeProposalNonce '94000000-0000-4000-8000-000000000008' `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc).CanUseFrozenFacts | Should -BeFalse
    }

    It 'rejects a different FreezeId replay against committed state' {
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState `
            -FreezeId '91000000-0000-4000-8000-000000000002' -ExpectedRevision 1 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'CALIBRATION_EVIDENCE_FREEZE_REPLAY'
    }

    It 'rejects a FreezeId colliding with the P10A consumption id' {
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $script:FreezeState `
            -FreezeId $script:ReleaseFactsConsumptionId
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'FREEZE_ID_COLLISION'
    }

    It 'rejects evidence tampering even after the attacker recomputes its top-level token' {
        $tampered = Copy-CddsiReleaseFactsFixture -Value $script:Bundle.Evidence
        $tampered.Git.Version = '9.9.9.windows.9'
        $tampered.EvidenceBindingToken = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $tampered
        $bundle = [pscustomobject]@{
            Session = $script:Bundle.Session; Evidence = $tampered
            CommittedConsumptionState = $script:Bundle.CommittedConsumptionState
            CommittedConsumptionReceipt = $script:Bundle.CommittedConsumptionReceipt
        }
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $bundle -FreezeState $script:FreezeState
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'EVIDENCE_SESSION_INVALID'
    }

    It 'rejects cross-session use of evidence, consumption and freeze receipts' {
        $other = New-CddsiReleaseFactsBundleFixture -Variant 2
        $bundle = [pscustomobject]@{
            Session = $other.Session; Evidence = $script:Bundle.Evidence
            CommittedConsumptionState = $script:Bundle.CommittedConsumptionState
            CommittedConsumptionReceipt = $script:Bundle.CommittedConsumptionReceipt
        }
        $result = Resolve-CddsiFrozenReleaseFacts -Evidence $bundle.Evidence -ExpectedSession $bundle.Session `
            -ExpectedSessionAnchorToken $bundle.Session.SessionAnchorToken `
            -CommittedConsumptionState $bundle.CommittedConsumptionState `
            -CommittedConsumptionReceipt $bundle.CommittedConsumptionReceipt `
            -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
            -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
            -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
            -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
            -FreezeState $script:FreezeState -FreezeStoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey `
            -FreezeId $script:ReleaseFactsFreezeId -FreezeTransactionId $script:ReleaseFactsFreezeTransactionId `
            -FreezeProposalNonce $script:ReleaseFactsFreezeProposalNonce -CommittedFreezeReceipt $null -ExpectedRevision 0 `
            -ValidationTimeUtc $script:ReleaseFactsFreezeTimeUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'EVIDENCE_SESSION_INVALID'
    }

    It 'rejects an expired session and both committed receipts' {
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -ValidationTimeUtc '2026-07-15T00:40:01Z'
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'EVIDENCE_SESSION_INVALID'
        $result.ReasonCodes | Should -Contain 'CONSUMPTION_RECEIPT_INVALID'
    }

    It 'rejects a committed freeze receipt whose facts token was replaced' {
        $tamperedState = Copy-CddsiReleaseFactsFixture -Value $script:Proposal.ProposedFreezeState
        $tamperedState.FactsBindingToken = ('0' * 64)
        $tamperedState.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $tamperedState
        (Test-CddsiReleaseFactsFreezeState -FreezeState $tamperedState) | Should -BeTrue
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $tamperedState `
            -ExpectedRevision 1 -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'FREEZE_COMMIT_RECEIPT_INVALID'
    }

    It 'rejects MSIX flavor and scope reinterpretation even with a recomputed token' {
        $frozen = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        foreach ($mutation in @('FLAVOR', 'SCOPE')) {
            $facts = Copy-CddsiReleaseFactsFixture -Value $frozen.FrozenReleaseFacts
            if ($mutation -ceq 'FLAVOR') { $facts.Msix.Flavor = 'Offline' }
            else { $facts.Msix.Scope = 'PER_USER' }
            $facts.FactsBindingToken = Get-CddsiFrozenReleaseFactsBindingToken -Facts $facts
            (Test-CddsiFrozenReleaseFacts -Facts $facts -Evidence $script:Bundle.Evidence `
                -ExpectedSession $script:Bundle.Session -ExpectedSessionAnchorToken $script:Bundle.Session.SessionAnchorToken `
                -CommittedConsumptionState $script:Bundle.CommittedConsumptionState `
                -CommittedConsumptionReceipt $script:Bundle.CommittedConsumptionReceipt `
                -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
                -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
                -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
                -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
                -CommittedFreezeState $script:Proposal.ProposedFreezeState `
                -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
                -FreezeStoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey `
                -ExpectedFreezeId $script:ReleaseFactsFreezeId `
                -ExpectedFreezeTransactionId $script:ReleaseFactsFreezeTransactionId `
                -ExpectedFreezeProposalNonce $script:ReleaseFactsFreezeProposalNonce `
                -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc) | Should -BeFalse
        }
    }

    It 'rejects Git, helper and status reinterpretation with recomputed tokens' {
        $frozen = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle `
            -FreezeState $script:Proposal.ProposedFreezeState -ExpectedRevision 1 `
            -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
            -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc
        foreach ($mutation in @('GIT', 'HELPER', 'FAILED')) {
            $facts = Copy-CddsiReleaseFactsFixture -Value $frozen.FrozenReleaseFacts
            if ($mutation -ceq 'GIT') { $facts.Git.Version = '9.9.9.windows.9' }
            elseif ($mutation -ceq 'HELPER') { $facts.CredentialHelper.Result = 'NOT_OBSERVED' }
            else { $facts.Git.Status = 'FAILED' }
            $facts.FactsBindingToken = Get-CddsiFrozenReleaseFactsBindingToken -Facts $facts
            (Test-CddsiFrozenReleaseFacts -Facts $facts -Evidence $script:Bundle.Evidence `
                -ExpectedSession $script:Bundle.Session -ExpectedSessionAnchorToken $script:Bundle.Session.SessionAnchorToken `
                -CommittedConsumptionState $script:Bundle.CommittedConsumptionState `
                -CommittedConsumptionReceipt $script:Bundle.CommittedConsumptionReceipt `
                -ConsumptionStoreAuthorityPublicKey $script:ReleaseFactsConsumptionAuthority.PublicKey `
                -ExpectedConsumptionId $script:ReleaseFactsConsumptionId `
                -ExpectedConsumptionTransactionId $script:ReleaseFactsConsumptionTransactionId `
                -ExpectedConsumptionProposalNonce $script:ReleaseFactsConsumptionProposalNonce `
                -CommittedFreezeState $script:Proposal.ProposedFreezeState `
                -CommittedFreezeReceipt $script:CommittedFreezeReceipt `
                -FreezeStoreAuthorityPublicKey $script:ReleaseFactsFreezeAuthority.PublicKey `
                -ExpectedFreezeId $script:ReleaseFactsFreezeId `
                -ExpectedFreezeTransactionId $script:ReleaseFactsFreezeTransactionId `
                -ExpectedFreezeProposalNonce $script:ReleaseFactsFreezeProposalNonce `
                -ValidationTimeUtc $script:ReleaseFactsReplayTimeUtc) | Should -BeFalse
        }
    }

    It 'rejects a forged revision even if the attacker recomputes the receipt token' {
        $tampered = Copy-CddsiReleaseFactsFixture -Value $script:FreezeState
        $tampered.Revision = 1
        $tampered.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $tampered
        (Test-CddsiReleaseFactsFreezeState -FreezeState $tampered) | Should -BeFalse
        $result = Resolve-CddsiReleaseFactsFixture -Bundle $script:Bundle -FreezeState $tampered -ExpectedRevision 1
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'FREEZE_STATE_INVALID'
    }
}

AfterAll {
    foreach ($authority in @($script:ReleaseFactsConsumptionAuthority, $script:ReleaseFactsFreezeAuthority)) {
        if ($null -ne $authority -and $null -ne $authority.Signer) { $authority.Signer.Dispose() }
    }
}
