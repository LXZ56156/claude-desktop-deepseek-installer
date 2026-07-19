BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:CalibrationOperations = @(
        'InspectEnvironment',
        'AcquireCalibrationArtifacts',
        'VerifyCalibrationArtifacts',
        'CalibrateMsixScope',
        'CalibrateCredentialHelper',
        'CalibrateGit',
        'WriteCalibrationEvidence',
        'CleanupCalibrationResources'
    )
    $script:ObservationStartedAtUtc = '2026-07-14T00:03:00Z'
    $script:CompletedAtUtc = '2026-07-14T00:40:00Z'
    $script:ValidationTimeUtc = '2026-07-14T00:45:00Z'
    $script:ConsumptionStoreInstanceId = '92000000-0000-4000-8000-000000000001'
    $script:ConsumptionTransactionId = '92000000-0000-4000-8000-000000000002'
    $script:ConsumptionProposalNonce = '92000000-0000-4000-8000-000000000003'

    function New-CddsiCasAuthorityFixture {
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

    function New-CddsiCasCommitReceiptFixture {
        param(
            [Parameter(Mandatory = $true)]$CommitProposal,
            [Parameter(Mandatory = $true)]$Signer,
            [string]$CommitId = '92000000-0000-4000-8000-000000000004',
            [string]$CommittedAtUtc = '2026-07-14T00:45:00Z'
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
            ProposalBindingToken = $CommitProposal.ProposalBindingToken
            ProposalNonce = $CommitProposal.ProposalNonce
            SessionAnchorToken = $CommitProposal.SessionAnchorToken
            SessionBindingToken = $CommitProposal.SessionBindingToken
            EvidenceBindingToken = $CommitProposal.EvidenceBindingToken
            ConsumptionId = $CommitProposal.ConsumptionId; FreezeId = $CommitProposal.FreezeId
            FactsBindingToken = $CommitProposal.FactsBindingToken
            CommittedAtUtc = $CommittedAtUtc; ExpiresAtUtc = $CommitProposal.ProposedState.ExpiresAtUtc
            SignatureBase64 = $null; ReceiptBindingToken = $null
        }
        $bytes = [Text.Encoding]::UTF8.GetBytes((Get-CddsiCasCommitReceiptSigningPayload -CommitReceipt $receipt))
        $signature = $Signer.SignData($bytes, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        $receipt.SignatureBase64 = [Convert]::ToBase64String($signature)
        $receipt.ReceiptBindingToken = Get-CddsiCasCommitReceiptBindingToken -CommitReceipt $receipt
        return $receipt
    }

    $script:ConsumptionAuthority = New-CddsiCasAuthorityFixture -KeyId '92000000-0000-4000-8000-000000000005'

    function Copy-CddsiVmCalibrationFixture {
        param([Parameter(Mandatory = $true)][AllowNull()]$Value)
        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) {
            return $Value
        }
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($key in $Value.Keys) {
                $copy[$key] = Copy-CddsiVmCalibrationFixture -Value $Value[$key]
            }
            return $copy
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = [System.Collections.Generic.List[object]]::new()
            foreach ($item in $Value) {
                $items.Add((Copy-CddsiVmCalibrationFixture -Value $item))
            }
            Write-Output -NoEnumerate ([object[]]$items.ToArray())
            return
        }
        $properties = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $properties[$property.Name] = Copy-CddsiVmCalibrationFixture -Value $property.Value
        }
        return [pscustomobject]$properties
    }

    function Test-CddsiVmCalibrationMandatoryParameterFixture {
        param(
            [Parameter(Mandatory = $true)][string]$CommandName,
            [Parameter(Mandatory = $true)][string]$ParameterName
        )
        $parameter = (Get-Command $CommandName).Parameters[$ParameterName]
        return @($parameter.Attributes | Where-Object {
            $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory
        }).Count -gt 0
    }

    function New-CddsiVmCalibrationStageManifestFixture {
        return [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-stage-manifest-v1'
            Stage           = 'VmCalibration'
            ArtifactProfile = 'VmCalibration'
            ArtifactVersion = '0.10.0-calibration'
            CommitId        = ('d' * 40)
            ArtifactSha256  = ('a' * 64)
            SidecarSha256   = ('b' * 64)
            ContentDigest   = ('c' * 64)
            CreatedAtUtc    = '2026-07-14T00:00:00Z'
        }
    }

    function New-CddsiVmCalibrationGrantFixture {
        $bindings = @()
        $digits = @('1', '2', '3', '4', '5', '6', '7', '8')
        for ($index = 0; $index -lt $script:CalibrationOperations.Count; $index++) {
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion   = 1
                ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId  = ('50000000-0000-4000-8000-{0:d12}' -f ($index + 1))
                Operation       = $script:CalibrationOperations[$index]
                PromptDigest    = ($digits[$index] * 64)
                Required        = $true
            }
        }
        return [pscustomobject][ordered]@{
            SchemaVersion       = 1
            ContractVersion     = 'cddsi-operation-grant-v2'
            GrantId             = '11111111-1111-4111-8111-111111111111'
            ArtifactSha256      = ('a' * 64)
            SidecarSha256       = ('b' * 64)
            ContentDigest       = ('c' * 64)
            ArtifactProfile     = 'VmCalibration'
            RunId               = '22222222-2222-4222-8222-222222222222'
            IssuedAtUtc         = '2026-07-14T00:01:00Z'
            ExpiresAtUtc        = '2026-07-14T01:00:00Z'
            Nonce               = '33333333-3333-4333-8333-333333333333'
            AllowedOperations   = [string[]]$script:CalibrationOperations
            SingleUse           = $true
            ConfirmationBindings = [object[]]$bindings
        }
    }

    function New-CddsiVmCalibrationAuthorizationSessionFixture {
        return [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-authorization-session-v1'
            State           = 'CLAIMED'
            GrantId         = '11111111-1111-4111-8111-111111111111'
            Nonce           = '33333333-3333-4333-8333-333333333333'
            ClaimId         = '44444444-4444-4444-8444-444444444444'
            RunId           = '22222222-2222-4222-8222-222222222222'
            ArtifactSha256  = ('a' * 64)
            SidecarSha256   = ('b' * 64)
            ContentDigest   = ('c' * 64)
            ArtifactProfile = 'VmCalibration'
            ClaimedAtUtc    = '2026-07-14T00:02:00Z'
            ExpiresAtUtc    = '2026-07-14T01:00:00Z'
            Revision        = 1
        }
    }

    function New-CddsiVmCalibrationSessionFixture {
        param([Parameter(Mandatory = $true)]$OperationEvidenceRecords)

        $manifest = New-CddsiVmCalibrationStageManifestFixture
        $grant = New-CddsiVmCalibrationGrantFixture
        $authorizationSession = New-CddsiVmCalibrationAuthorizationSessionFixture
        $workflow = New-CddsiWorkflowSessionState -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $authorizationSession
        $availableStates = @($script:CalibrationOperations | ForEach-Object {
            New-CddsiOperationUseState -StageManifest $manifest -OperationGrant $grant `
                -AuthorizationSession $authorizationSession -WorkflowSessionState $workflow -Operation $_
        })
        $anchor = Get-CddsiVmCalibrationSessionAnchorToken -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $authorizationSession -WorkflowSessionState $workflow -OperationUseStates $availableStates
        $claimTimes = @(
            '2026-07-14T00:04:30Z', '2026-07-14T00:25:30Z',
            '2026-07-14T00:26:30Z', '2026-07-14T00:27:30Z',
            '2026-07-14T00:30:30Z', '2026-07-14T00:31:30Z',
            '2026-07-14T00:33:30Z', '2026-07-14T00:35:30Z'
        )
        $terminalTimes = @(
            '2026-07-14T00:05:00Z', '2026-07-14T00:26:00Z',
            '2026-07-14T00:27:00Z', '2026-07-14T00:28:00Z',
            '2026-07-14T00:31:00Z', '2026-07-14T00:32:00Z',
            '2026-07-14T00:34:00Z', '2026-07-14T00:36:00Z'
        )
        $terminalStates = [System.Collections.Generic.List[object]]::new()
        for ($index = 0; $index -lt $script:CalibrationOperations.Count; $index++) {
            $operation = $script:CalibrationOperations[$index]
            $binding = @($grant.ConfirmationBindings | Where-Object { $_.Operation -ceq $operation })[0]
            $confirmation = [pscustomobject][ordered]@{
                SchemaVersion   = 1
                ContractVersion = 'cddsi-interactive-confirmation-v2'
                ConfirmationId  = $binding.ConfirmationId
                GrantId         = $grant.GrantId
                ClaimId         = $authorizationSession.ClaimId
                PromptDigest    = $binding.PromptDigest
                ArtifactSha256  = $grant.ArtifactSha256
                SidecarSha256   = $grant.SidecarSha256
                ContentDigest   = $grant.ContentDigest
                ArtifactProfile = $grant.ArtifactProfile
                RunId           = $grant.RunId
                Nonce           = $grant.Nonce
                Operation       = $operation
                Confirmed       = $true
                ConfirmedAtUtc  = $claimTimes[$index]
            }
            $operationUseId = '60000000-0000-4000-8000-{0:d12}' -f ($index + 1)
            $authorizationResult = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
                -AuthorizationSession $authorizationSession -WorkflowSessionState $workflow -OperationUseState $availableStates[$index] `
                -Confirmation $confirmation -Operation $operation -OperationUseId $operationUseId `
                -ExpectedRevision 0 -RunId $grant.RunId -NowUtc $claimTimes[$index]
            if (-not $authorizationResult.Data.AuthorizationProposed) { throw 'Synthetic calibration operation claim failed.' }
            $claimed = $authorizationResult.Data.ProposedOperationUseState
            $terminalResult = Resolve-CddsiOperationUseTerminal -StageManifest $manifest -OperationGrant $grant `
                -AuthorizationSession $authorizationSession -WorkflowSessionState $workflow -OperationUseState $claimed `
                -Operation $operation -OperationUseId $operationUseId -ExpectedRevision $claimed.Revision `
                -Outcome COMPLETED -ProviderEvidenceDigest $OperationEvidenceRecords[$index].ProviderEvidenceDigest `
                -OccurredAtUtc $terminalTimes[$index] -IdempotencyKey ('70000000-0000-4000-8000-{0:d12}' -f ($index + 1))
            if (-not $terminalResult.Data.Terminalized) { throw 'Synthetic calibration operation terminal reduction failed.' }
            $terminalStates.Add($terminalResult.Data.TerminalOperationUseState)
        }
        $workflowResult = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $authorizationSession -WorkflowSessionState $workflow -OperationUseStates @($terminalStates) `
            -ExpectedRevision $workflow.Revision -Outcome COMPLETED -OccurredAtUtc $script:CompletedAtUtc `
            -IdempotencyKey '80000000-0000-4000-8000-000000000001'
        if (-not $workflowResult.Data.Terminalized) { throw 'Synthetic calibration workflow terminal reduction failed.' }
        $session = [pscustomobject][ordered]@{
            SchemaVersion        = 2
            ContractVersion      = 'cddsi-vm-calibration-session-v2'
            StageManifest        = $manifest
            OperationGrant       = $grant
            AuthorizationSession = $authorizationSession
            WorkflowSessionState = $workflowResult.Data.TerminalWorkflowSessionState
            OperationUseStates   = @($terminalStates)
            SessionAnchorToken   = $anchor
            SessionBindingToken  = $null
        }
        $session.SessionBindingToken = Get-CddsiVmCalibrationSessionBindingToken -ExpectedSession $session
        return $session
    }

    function New-CddsiVmCalibrationOsFixture {
        param([string]$Status = 'OBSERVED')
        if ($Status -ceq 'OBSERVED') {
            return [pscustomobject][ordered]@{
                Status = 'OBSERVED'; ObservedAtUtc = '2026-07-14T00:04:00Z'; ImageSha256 = ('6' * 64)
                Sku = 'Windows11Pro24H2'; Architecture = 'x64'; Build = 26100; Ubr = 5000
                Language = 'zh-CN'; PatchDate = '2026-07-01'; NestedVirtualization = 'SUPPORTED'; FailureCode = ''
            }
        }
        return [pscustomobject][ordered]@{
            Status = $Status; ObservedAtUtc = '2026-07-14T00:04:00Z'; ImageSha256 = 'NOT_OBSERVED'
            Sku = 'NOT_OBSERVED'; Architecture = 'NOT_OBSERVED'; Build = 'NOT_OBSERVED'; Ubr = 'NOT_OBSERVED'
            Language = 'NOT_OBSERVED'; PatchDate = 'NOT_OBSERVED'; NestedVirtualization = 'NOT_OBSERVED'
            FailureCode = if ($Status -ceq 'FAILED') { 'OS_CALIBRATION_TOOL_FAILED' } else { 'NOT_OBSERVED' }
        }
    }

    function New-CddsiVmCalibrationMsixFixture {
        param([Parameter(Mandatory = $true)][string]$Flavor, [string]$Status = 'OBSERVED')
        $observedAt = if ($Flavor -ceq 'Standard') { '2026-07-14T00:10:00Z' } else { '2026-07-14T00:20:00Z' }
        if ($Status -cne 'OBSERVED') {
            $perUser = [pscustomobject][ordered]@{ Result = 'NOT_OBSERVED'; PackageInstalled = 'NOT_OBSERVED'; CoworkService = 'NOT_OBSERVED'; ErrorCode = 'NOT_OBSERVED' }
            $machineWide = Copy-CddsiVmCalibrationFixture -Value $perUser
            return [pscustomobject][ordered]@{
                Status = $Status; ObservedAtUtc = $observedAt; Flavor = $Flavor; SourceUri = 'NOT_OBSERVED'; RedirectUri = 'NOT_OBSERVED'
                RedirectCount = 'NOT_OBSERVED'; Version = 'NOT_OBSERVED'; SizeBytes = 'NOT_OBSERVED'; ArtifactSha256 = 'NOT_OBSERVED'
                Signer = [pscustomobject][ordered]@{ AuthenticodeStatus = 'NOT_OBSERVED'; ChainTrusted = 'NOT_OBSERVED'; Subject = 'NOT_OBSERVED'; Thumbprint = 'NOT_OBSERVED'; TimestampStatus = 'NOT_OBSERVED' }
                Certificate = [pscustomobject][ordered]@{ CertificateSha256 = 'NOT_OBSERVED'; SerialNumber = 'NOT_OBSERVED'; NotBeforeUtc = 'NOT_OBSERVED'; NotAfterUtc = 'NOT_OBSERVED' }
                ManifestIdentity = [pscustomobject][ordered]@{ Name = 'NOT_OBSERVED'; Publisher = 'NOT_OBSERVED'; Version = 'NOT_OBSERVED'; ProcessorArchitecture = 'NOT_OBSERVED'; ResourceId = 'NOT_OBSERVED'; PackageFamilyName = 'NOT_OBSERVED'; PackageFullName = 'NOT_OBSERVED' }
                Deployments = [pscustomobject][ordered]@{ PerUser = $perUser; MachineWide = $machineWide; RecommendedScope = 'NOT_OBSERVED'; RecommendationCode = 'NOT_OBSERVED' }
                FailureCode = if ($Status -ceq 'FAILED') { 'MSIX_CALIBRATION_TOOL_FAILED' } else { 'NOT_OBSERVED' }
            }
        }
        $sourceUri = if ($Flavor -ceq 'Offline') { 'https://claude.ai/api/desktop/win32/x64/offline/latest/redirect' } else { 'https://claude.ai/api/desktop/win32/x64/latest/redirect' }
        $artifactSha = if ($Flavor -ceq 'Offline') { ('e' * 64) } else { ('f' * 64) }
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = $observedAt; Flavor = $Flavor; SourceUri = $sourceUri
            RedirectUri = ('https://downloads.claude.ai/windows/Claude-{0}-1.2.3.4-x64.msix' -f $Flavor.ToLowerInvariant())
            RedirectCount = 1; Version = '1.2.3.4'; SizeBytes = 104857600; ArtifactSha256 = $artifactSha
            Signer = [pscustomobject][ordered]@{ AuthenticodeStatus = 'VALID'; ChainTrusted = $true; Subject = 'CN=Anthropic PBC, O=Anthropic PBC, C=US'; Thumbprint = ('1' * 40); TimestampStatus = 'VALID' }
            Certificate = [pscustomobject][ordered]@{ CertificateSha256 = ('2' * 64); SerialNumber = '0A12'; NotBeforeUtc = '2026-01-01T00:00:00Z'; NotAfterUtc = '2027-01-01T00:00:00Z' }
            ManifestIdentity = [pscustomobject][ordered]@{ Name = 'Claude'; Publisher = 'CN=Anthropic PBC, O=Anthropic PBC, C=US'; Version = '1.2.3.4'; ProcessorArchitecture = 'x64'; ResourceId = ''; PackageFamilyName = 'Claude_abcdef'; PackageFullName = 'Claude_1.2.3.4_x64__abcdef' }
            Deployments = [pscustomobject][ordered]@{
                PerUser = [pscustomobject][ordered]@{ Result = 'FAIL'; PackageInstalled = $true; CoworkService = 'ABSENT'; ErrorCode = 'COWORK_SERVICE_ABSENT' }
                MachineWide = [pscustomobject][ordered]@{ Result = 'PASS'; PackageInstalled = $true; CoworkService = 'PRESENT'; ErrorCode = '' }
                RecommendedScope = 'MACHINE_WIDE'; RecommendationCode = 'COWORK_SERVICE_REQUIRED'
            }
            FailureCode = ''
        }
    }

    function New-CddsiVmCalibrationGitFixture {
        param([string]$Status = 'OBSERVED')
        if ($Status -cne 'OBSERVED') {
            return [pscustomobject][ordered]@{
                Status = $Status; ObservedAtUtc = '2026-07-14T00:25:00Z'; ReleaseTag = 'NOT_OBSERVED'; AssetName = 'NOT_OBSERVED'; SourceUri = 'NOT_OBSERVED'
                Version = 'NOT_OBSERVED'; SizeBytes = 'NOT_OBSERVED'; ArtifactSha256 = 'NOT_OBSERVED'
                Signer = [pscustomobject][ordered]@{ AuthenticodeStatus = 'NOT_OBSERVED'; ChainTrusted = 'NOT_OBSERVED'; Subject = 'NOT_OBSERVED'; Thumbprint = 'NOT_OBSERVED'; CertificateSha256 = 'NOT_OBSERVED' }
                PeIdentity = [pscustomobject][ordered]@{ OriginalFilename = 'NOT_OBSERVED'; ProductName = 'NOT_OBSERVED'; CompanyName = 'NOT_OBSERVED'; FileVersion = 'NOT_OBSERVED'; Machine = 'NOT_OBSERVED' }
                FailureCode = if ($Status -ceq 'FAILED') { 'GIT_CALIBRATION_TOOL_FAILED' } else { 'NOT_OBSERVED' }
            }
        }
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = '2026-07-14T00:25:00Z'; ReleaseTag = 'v2.53.0.windows.3'; AssetName = 'Git-2.53.0.3-64-bit.exe'
            SourceUri = 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.3/Git-2.53.0.3-64-bit.exe'
            Version = '2.53.0.windows.3'; SizeBytes = 68157440; ArtifactSha256 = ('3' * 64)
            Signer = [pscustomobject][ordered]@{ AuthenticodeStatus = 'VALID'; ChainTrusted = $true; Subject = 'CN=Open Source Developer, O=Git for Windows, C=US'; Thumbprint = ('4' * 40); CertificateSha256 = ('5' * 64) }
            PeIdentity = [pscustomobject][ordered]@{ OriginalFilename = 'Git-2.53.0.3-64-bit.exe'; ProductName = 'Git for Windows'; CompanyName = 'The Git Development Community'; FileVersion = '2.53.0.3'; Machine = 'x64' }
            FailureCode = ''
        }
    }

    function New-CddsiVmCalibrationBehaviorFixture {
        param([string]$Status = 'OBSERVED')
        if ($Status -cne 'OBSERVED') {
            return [pscustomobject][ordered]@{
                Status = $Status; ObservedAtUtc = '2026-07-14T00:30:00Z'
                Helper = [pscustomobject][ordered]@{ Result = 'NOT_OBSERVED'; Invoked = 'NOT_OBSERVED'; StdoutSingleToken = 'NOT_OBSERVED'; StderrSafe = 'NOT_OBSERVED'; TimeoutEnforced = 'NOT_OBSERVED'; TtlObservedSeconds = 'NOT_OBSERVED'; SilentRefreshObserved = 'NOT_OBSERVED'; ErrorCode = 'NOT_OBSERVED' }
                Chooser = [pscustomobject][ordered]@{ Result = 'NOT_OBSERVED'; Hidden = 'NOT_OBSERVED'; DeveloperModeSkipped = 'NOT_OBSERVED'; AnthropicLoginSkipped = 'NOT_OBSERVED'; ErrorCode = 'NOT_OBSERVED' }
                HkcuManagedPolicy = [pscustomobject][ordered]@{ Result = 'NOT_OBSERVED'; Effective = 'NOT_OBSERVED'; ValueType = 'NOT_OBSERVED'; ValueCount = 'NOT_OBSERVED'; HelperReferenceUsed = 'NOT_OBSERVED'; ConfigLibraryWriterUsed = 'NOT_OBSERVED'; RawValuesCaptured = 'NOT_OBSERVED'; ErrorCode = 'NOT_OBSERVED' }
                FailureCode = if ($Status -ceq 'FAILED') { 'DESKTOP_BEHAVIOR_CALIBRATION_FAILED' } else { 'NOT_OBSERVED' }
            }
        }
        return [pscustomobject][ordered]@{
            Status = 'OBSERVED'; ObservedAtUtc = '2026-07-14T00:30:00Z'
            Helper = [pscustomobject][ordered]@{ Result = 'PASS'; Invoked = $true; StdoutSingleToken = $true; StderrSafe = $true; TimeoutEnforced = $true; TtlObservedSeconds = 3600; SilentRefreshObserved = $true; ErrorCode = '' }
            Chooser = [pscustomobject][ordered]@{ Result = 'PASS'; Hidden = $true; DeveloperModeSkipped = $true; AnthropicLoginSkipped = $true; ErrorCode = '' }
            HkcuManagedPolicy = [pscustomobject][ordered]@{ Result = 'PASS'; Effective = $true; ValueType = 'REG_SZ'; ValueCount = 15; HelperReferenceUsed = $true; ConfigLibraryWriterUsed = $false; RawValuesCaptured = $false; ErrorCode = '' }
            FailureCode = ''
        }
    }

    function New-CddsiVmCalibrationCleanupFixture {
        return [pscustomobject][ordered]@{
            SchemaVersion               = 1
            Status                      = 'COMPLETE'
            ObservedAtUtc               = '2026-07-14T00:35:00Z'
            CalibrationArtifactsRemoved = $true
            TemporaryCredentialRemoved  = $true
            TemporaryPolicyRemoved      = $true
            DesktopProcessesStopped     = $true
            FailureCode                 = ''
        }
    }

    function New-CddsiVmCalibrationBundleFixture {
        param(
            $Session,
            [string]$SessionAnchorToken = '',
            $OsImage,
            $MsixCandidates,
            $Git,
            $DesktopBehavior,
            $Cleanup,
            [string]$ObservationStartedAtUtc = $script:ObservationStartedAtUtc
        )
        if ($null -eq $OsImage) { $OsImage = New-CddsiVmCalibrationOsFixture }
        if ($null -eq $MsixCandidates) { $MsixCandidates = @((New-CddsiVmCalibrationMsixFixture -Flavor Standard), (New-CddsiVmCalibrationMsixFixture -Flavor Offline)) }
        if ($null -eq $Git) { $Git = New-CddsiVmCalibrationGitFixture }
        if ($null -eq $DesktopBehavior) { $DesktopBehavior = New-CddsiVmCalibrationBehaviorFixture }
        if ($null -eq $Cleanup) { $Cleanup = New-CddsiVmCalibrationCleanupFixture }

        $selection = Resolve-CddsiVmCalibrationSelection -MsixCandidates $MsixCandidates
        $readiness = Resolve-CddsiVmCalibrationReadiness -OsImage $OsImage -MsixCandidates $MsixCandidates -Selection $selection -Git $Git -DesktopBehavior $DesktopBehavior
        $records = Get-CddsiVmCalibrationOperationEvidenceRecords -ObservationStartedAtUtc $ObservationStartedAtUtc -OsImage $OsImage -MsixCandidates $MsixCandidates -Selection $selection -Git $Git -DesktopBehavior $DesktopBehavior -Readiness $readiness -Cleanup $Cleanup
        if ($null -eq $Session) { $Session = New-CddsiVmCalibrationSessionFixture -OperationEvidenceRecords $records }
        if ([string]::IsNullOrEmpty($SessionAnchorToken)) { $SessionAnchorToken = $Session.SessionAnchorToken }
        $evidence = New-CddsiVmCalibrationEvidence -ExpectedSession $Session -ExpectedSessionAnchorToken $SessionAnchorToken `
            -ValidationTimeUtc $script:ValidationTimeUtc -ObservationStartedAtUtc $ObservationStartedAtUtc `
            -OsImage $OsImage -MsixCandidates $MsixCandidates -Git $Git -DesktopBehavior $DesktopBehavior -Cleanup $Cleanup
        return [pscustomobject]@{ Session = $Session; SessionAnchorToken = $SessionAnchorToken; Evidence = $evidence }
    }

    function Update-CddsiVmCalibrationInternalFields {
        param([Parameter(Mandatory = $true)]$Evidence)
        $Evidence.Selection = Resolve-CddsiVmCalibrationSelection -MsixCandidates $Evidence.MsixCandidates
        $Evidence.Readiness = Resolve-CddsiVmCalibrationReadiness -OsImage $Evidence.OsImage -MsixCandidates $Evidence.MsixCandidates -Selection $Evidence.Selection -Git $Evidence.Git -DesktopBehavior $Evidence.DesktopBehavior
        $Evidence.EvidenceBindingToken = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $Evidence
    }

    function Test-CddsiVmCalibrationSessionFixture {
        param($Session, [string]$AnchorToken)
        return Test-CddsiVmCalibrationSession -ExpectedSession $Session -ExpectedSessionAnchorToken $AnchorToken -ValidationTimeUtc $script:ValidationTimeUtc
    }

    function Test-CddsiVmCalibrationEvidenceFixture {
        param($Evidence, $Session, [string]$AnchorToken)
        return Test-CddsiVmCalibrationEvidence -Evidence $Evidence -ExpectedSession $Session -ExpectedSessionAnchorToken $AnchorToken -ValidationTimeUtc $script:ValidationTimeUtc
    }

    function New-CddsiVmCalibrationConsumptionStateFixture {
        param($Session, [string]$AnchorToken)
        return New-CddsiVmCalibrationConsumptionState -ExpectedSession $Session -ExpectedSessionAnchorToken $AnchorToken `
            -StoreAuthorityPublicKey $script:ConsumptionAuthority.PublicKey `
            -StoreInstanceId $script:ConsumptionStoreInstanceId -StoreEpoch 1 -ValidationTimeUtc $script:ValidationTimeUtc
    }

    function Resolve-CddsiVmCalibrationConsumptionFixture {
        param(
            $Evidence,
            $Session,
            [string]$AnchorToken,
            $ConsumptionState,
            [string]$ConsumptionId = '90000000-0000-4000-8000-000000000001',
            [int]$ExpectedRevision = 0,
            [AllowNull()]$CommittedReceipt = $null,
            $StoreAuthorityPublicKey = $script:ConsumptionAuthority.PublicKey,
            [string]$TransactionId = $script:ConsumptionTransactionId,
            [string]$ProposalNonce = $script:ConsumptionProposalNonce,
            [string]$ValidationTimeUtc = $script:ValidationTimeUtc
        )
        return Resolve-CddsiVmCalibrationConsumption -Evidence $Evidence -ExpectedSession $Session `
            -ExpectedSessionAnchorToken $AnchorToken -ConsumptionState $ConsumptionState `
            -StoreAuthorityPublicKey $StoreAuthorityPublicKey -ConsumptionId $ConsumptionId `
            -TransactionId $TransactionId -ProposalNonce $ProposalNonce `
            -CommittedConsumptionReceipt $CommittedReceipt -ExpectedRevision $ExpectedRevision `
            -ValidationTimeUtc $ValidationTimeUtc
    }

    $script:DefaultVmCalibrationBundleFixture = New-CddsiVmCalibrationBundleFixture
}

Describe 'P10A external-session-bound calibration contract' {
    It 'uses one fixed canonical JSON and SHA-256 golden vector across PowerShell engines' {
        $escape = 'quote' + [char]34 + [char]92 + 'line' + [char]10
        $value = [pscustomobject][ordered]@{
            Z = 2
            a = '汉字'
            Escape = $escape
            Empty = @()
            Map = [ordered]@{ beta = $true; Alpha = $null }
        }

        (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $value) | Should -BeExactly '{"Empty":[],"Escape":"quote\"\\line\n","Map":{"Alpha":null,"beta":true},"Z":2,"a":"汉字"}'
        (Get-CddsiVmCalibrationCanonicalBindingToken -Value $value) | Should -BeExactly '3fe020c6513646a2ae03a474c7060362a2626cd26d4bb1e36e81fd86c93a8dc1'
    }

    It 'validates two ordered candidates but exposes freeze only from consumption' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        (Test-CddsiVmCalibrationSessionFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeTrue
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $bundle.Evidence -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeTrue
        @($bundle.Evidence.MsixCandidates).Count | Should -Be 2
        $bundle.Evidence.MsixCandidates[0].Flavor | Should -BeExactly 'Standard'
        $bundle.Evidence.MsixCandidates[1].Flavor | Should -BeExactly 'Offline'
        $bundle.Evidence.Readiness.Status | Should -BeExactly 'COMPLETE'
        $bundle.Evidence.Readiness.PSObject.Properties.Name | Should -Not -Contain 'CanFreezeP10B'
        $bundle.Evidence.Readiness.ComprehensiveAcceptance | Should -BeFalse

        $state = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        $proposal = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $state
        $proposal.Status | Should -BeExactly 'READY_TO_COMMIT'
        $proposal.CanFreezeP10B | Should -BeFalse
        $proposal.RequiresAtomicCompareAndSwap | Should -BeTrue
        (Test-CddsiVmCalibrationConsumptionCommitProposal -CommitProposal $proposal.CommitProposal) | Should -BeTrue
        $proposal.IntegrityTokensAreAuthorization | Should -BeFalse

        $receipt = New-CddsiCasCommitReceiptFixture -CommitProposal $proposal.CommitProposal -Signer $script:ConsumptionAuthority.Signer
        $consumption = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1
        $consumption.Status | Should -BeExactly 'READY_TO_FREEZE'
        $consumption.CanFreezeP10B | Should -BeTrue
        $consumption.SelectedFlavor | Should -BeExactly 'Standard'
        $consumption.SelectedScope | Should -BeExactly 'MACHINE_WIDE'
        $consumption.ComprehensiveAcceptance | Should -BeFalse
    }

    It 'requires an external anchor and one committed consumption CAS receipt' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        (Test-CddsiVmCalibrationSessionFixture -Session $bundle.Session -AnchorToken ('0' * 64)) | Should -BeFalse
        (Test-CddsiVmCalibrationSession -ExpectedSession $bundle.Session -ExpectedSessionAnchorToken $bundle.SessionAnchorToken `
            -ValidationTimeUtc '2026-07-15T01:00:01Z' -MaximumAgeSeconds 86400) | Should -BeFalse

        $state = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        $proposal = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $state
        $proposal.Status | Should -BeExactly 'READY_TO_COMMIT'
        $proposal.CanFreezeP10B | Should -BeFalse
        $receipt = New-CddsiCasCommitReceiptFixture -CommitProposal $proposal.CommitProposal -Signer $script:ConsumptionAuthority.Signer
        (Test-CddsiCommittedVmCalibrationConsumptionReceipt -ConsumptionState $proposal.ProposedConsumptionState `
            -CommitReceipt $receipt -StoreAuthorityPublicKey $script:ConsumptionAuthority.PublicKey `
            -ExpectedSessionAnchorToken $bundle.SessionAnchorToken -ExpectedSessionBindingToken $bundle.Session.SessionBindingToken `
            -ExpectedEvidenceBindingToken $bundle.Evidence.EvidenceBindingToken -ExpectedConsumptionId '90000000-0000-4000-8000-000000000001' `
            -ExpectedTransactionId $script:ConsumptionTransactionId -ExpectedProposalNonce $script:ConsumptionProposalNonce `
            -ValidationTimeUtc $script:ValidationTimeUtc) | Should -BeTrue

        $ready = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1
        $ready.IdempotentReplay | Should -BeTrue
        $ready.CanFreezeP10B | Should -BeTrue
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -ConsumptionId '90000000-0000-4000-8000-000000000002' -CommittedReceipt $receipt `
            -ExpectedRevision 1).CanFreezeP10B | Should -BeFalse

        $receiptReplay = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $receiptReplay.OperationReceipts[1] = $receiptReplay.OperationReceipts[0]
        $receiptReplay.EvidenceBindingToken = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $receiptReplay
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $receiptReplay -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
    }

    It 'never treats a raw proposal state or a recomputed SHA token as a committed receipt' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $available = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        $proposal = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $available
        $rawReplay = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState -ExpectedRevision 1
        $rawReplay.Status | Should -BeExactly 'BLOCKED'
        $rawReplay.CanFreezeP10B | Should -BeFalse
        $rawReplay.ReasonCodes | Should -Contain 'CONSUMPTION_SIGNED_RECEIPT_REQUIRED'

        $forged = Copy-CddsiVmCalibrationFixture -Value $proposal.ProposedConsumptionState
        $forged.ConsumedAtUtc = '2026-07-14T00:44:59Z'
        $forged.StateBindingToken = Get-CddsiVmCalibrationConsumptionBindingToken -ConsumptionState $forged
        (Test-CddsiVmCalibrationConsumptionState -ConsumptionState $forged) | Should -BeTrue
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $forged -ExpectedRevision 1).CanFreezeP10B | Should -BeFalse
    }

    It 'requires the pinned RSA authority and rejects forged, stale, replayed and expired commit receipts' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $available = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        $proposal = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $available
        $receipt = New-CddsiCasCommitReceiptFixture -CommitProposal $proposal.CommitProposal -Signer $script:ConsumptionAuthority.Signer

        $forged = Copy-CddsiVmCalibrationFixture -Value $receipt
        $forged.CommitId = '92000000-0000-4000-8000-000000000099'
        $forged.ReceiptBindingToken = Get-CddsiCasCommitReceiptBindingToken -CommitReceipt $forged
        (Test-CddsiCasCommitReceiptSignature -CommitReceipt $forged `
            -StoreAuthorityPublicKey $script:ConsumptionAuthority.PublicKey) | Should -BeFalse

        $otherAuthority = New-CddsiCasAuthorityFixture -KeyId '92000000-0000-4000-8000-000000000006'
        try {
            (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
                -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
                -CommittedReceipt $receipt -ExpectedRevision 1 `
                -StoreAuthorityPublicKey $otherAuthority.PublicKey).CanFreezeP10B | Should -BeFalse
        }
        finally { $otherAuthority.Signer.Dispose() }

        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 0).CanFreezeP10B | Should -BeFalse
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1 `
            -TransactionId '92000000-0000-4000-8000-000000000007').CanFreezeP10B | Should -BeFalse
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1 `
            -ProposalNonce '92000000-0000-4000-8000-000000000008').CanFreezeP10B | Should -BeFalse
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1 `
            -ValidationTimeUtc '2026-07-14T01:00:00Z').CanFreezeP10B | Should -BeFalse

        $otherBundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $otherBundle.Session.OperationUseStates[0].ProviderEvidenceDigest = ('0' * 64)
        $otherBundle.Session.OperationUseStates[0].ReceiptBindingToken = Get-CddsiOperationUseBindingToken -OperationUseState $otherBundle.Session.OperationUseStates[0]
        $otherBundle.Session.WorkflowSessionState.TerminalOperationSetDigestSha256 = Get-CddsiTerminalOperationSetDigest -OperationGrant $otherBundle.Session.OperationGrant -OperationUseStates $otherBundle.Session.OperationUseStates
        $otherBundle.Session.WorkflowSessionState.ReceiptBindingToken = Get-CddsiWorkflowSessionBindingToken -WorkflowSessionState $otherBundle.Session.WorkflowSessionState
        $otherBundle.Session.SessionBindingToken = Get-CddsiVmCalibrationSessionBindingToken -ExpectedSession $otherBundle.Session
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $otherBundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1).CanFreezeP10B | Should -BeFalse
    }

    It 'requires ExpectedSession and consumes the stage-policy v2 contracts without a private grant schema' {
        (Test-CddsiVmCalibrationMandatoryParameterFixture -CommandName Test-CddsiVmCalibrationEvidence `
            -ParameterName ExpectedSession) | Should -BeTrue
        (Test-CddsiVmCalibrationMandatoryParameterFixture -CommandName Test-CddsiVmCalibrationEvidence `
            -ParameterName ExpectedSessionAnchorToken) | Should -BeTrue
        (Test-CddsiVmCalibrationMandatoryParameterFixture -CommandName Resolve-CddsiVmCalibrationConsumption `
            -ParameterName ConsumptionState) | Should -BeTrue
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $bundle.Evidence.SessionBinding.PSObject.Properties.Name | Should -Not -Contain 'Grant'
        $bundle.Evidence.SessionBinding.GrantId | Should -BeExactly $bundle.Session.OperationGrant.GrantId
        $bundle.Evidence.SessionBinding.ClaimId | Should -BeExactly $bundle.Session.AuthorizationSession.ClaimId
        $bundle.Evidence.SessionBinding.SidecarSha256 | Should -BeExactly $bundle.Session.StageManifest.SidecarSha256
    }

    It 'rejects forged grant session and operation-set bindings' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $mutations = @(
            { param($session) $session.StageManifest.SidecarSha256 = ('0' * 64) },
            { param($session) $session.OperationGrant.ArtifactSha256 = ('0' * 64) },
            { param($session) $session.AuthorizationSession.ClaimId = $session.OperationGrant.GrantId },
            { param($session) $temporary = $session.OperationGrant.AllowedOperations[0]; $session.OperationGrant.AllowedOperations[0] = $session.OperationGrant.AllowedOperations[1]; $session.OperationGrant.AllowedOperations[1] = $temporary },
            { param($session) $session.WorkflowSessionState.TerminalOperationSetDigestSha256 = ('0' * 64) },
            { param($session) $session.WorkflowSessionState.State = 'CLAIMED' },
            { param($session) $session.OperationUseStates[0].State = 'CLAIMED' },
            { param($session) $session.SessionAnchorToken = ('0' * 64) }
        )
        $state = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        foreach ($mutation in $mutations) {
            $session = Copy-CddsiVmCalibrationFixture -Value $bundle.Session
            & $mutation $session
            (Test-CddsiVmCalibrationSessionFixture -Session $session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
            (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $session -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $state).CanFreezeP10B | Should -BeFalse
        }
    }

    It 'rejects expired completion and every observation outside the claimed session window' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $expired = Copy-CddsiVmCalibrationFixture -Value $bundle.Session
        $expired.WorkflowSessionState.OccurredAtUtc = $expired.AuthorizationSession.ExpiresAtUtc
        (Test-CddsiVmCalibrationSessionFixture -Session $expired -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse

        $early = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $early.OsImage.ObservedAtUtc = '2026-07-14T00:01:30Z'
        Update-CddsiVmCalibrationInternalFields -Evidence $early
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $early -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse

        $late = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $late.DesktopBehavior.ObservedAtUtc = '2026-07-14T01:00:00Z'
        Update-CddsiVmCalibrationInternalFields -Evidence $late
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $late -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
    }

    It 'blocks a missing candidate and a valid but explicitly unobserved flavor' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $oneOnly = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $oneOnly.MsixCandidates = [object[]]@($oneOnly.MsixCandidates[0])
        Update-CddsiVmCalibrationInternalFields -Evidence $oneOnly
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $oneOnly -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
        $state = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $oneOnly -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $state).CanFreezeP10B | Should -BeFalse

        $candidates = @(
            (New-CddsiVmCalibrationMsixFixture -Flavor Standard),
            (New-CddsiVmCalibrationMsixFixture -Flavor Offline -Status NOT_OBSERVED)
        )
        $incomplete = New-CddsiVmCalibrationBundleFixture -MsixCandidates $candidates
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $incomplete.Evidence -Session $incomplete.Session -AnchorToken $incomplete.SessionAnchorToken) | Should -BeTrue
        $incomplete.Evidence.Readiness.Status | Should -BeExactly 'INCOMPLETE'
        $incompleteState = New-CddsiVmCalibrationConsumptionStateFixture -Session $incomplete.Session -AnchorToken $incomplete.SessionAnchorToken
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $incomplete.Evidence -Session $incomplete.Session -AnchorToken $incomplete.SessionAnchorToken -ConsumptionState $incompleteState).CanFreezeP10B | Should -BeFalse
    }

    It 'derives selection from both candidates and can select Offline only from explicit Standard failure facts' {
        $standard = New-CddsiVmCalibrationMsixFixture -Flavor Standard
        $standard.Deployments.MachineWide = [pscustomobject][ordered]@{ Result = 'FAIL'; PackageInstalled = $true; CoworkService = 'ABSENT'; ErrorCode = 'COWORK_SERVICE_ABSENT' }
        $standard.Deployments.RecommendedScope = 'NONE'
        $standard.Deployments.RecommendationCode = 'NO_VIABLE_STANDARD_SCOPE'
        $bundle = New-CddsiVmCalibrationBundleFixture -MsixCandidates @($standard, (New-CddsiVmCalibrationMsixFixture -Flavor Offline))
        $bundle.Evidence.Readiness.Status | Should -BeExactly 'COMPLETE'
        $bundle.Evidence.Selection.Flavor | Should -BeExactly 'Offline'
        $bundle.Evidence.Selection.ReasonCode | Should -BeExactly 'OFFLINE_CANDIDATE_REQUIRED'
        $state = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        $proposal = Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $state
        $receipt = New-CddsiCasCommitReceiptFixture -CommitProposal $proposal.CommitProposal -Signer $script:ConsumptionAuthority.Signer
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $bundle.Evidence -Session $bundle.Session `
            -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $proposal.ProposedConsumptionState `
            -CommittedReceipt $receipt -ExpectedRevision 1).CanFreezeP10B | Should -BeTrue

        $swapped = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $swapped.MsixCandidates = [object[]]@($swapped.MsixCandidates[1], $swapped.MsixCandidates[0])
        Update-CddsiVmCalibrationInternalFields -Evidence $swapped
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $swapped -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
    }

    It 'rejects unofficial or query-bearing MSIX and Git source URIs and overlong redirects' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $attacks = @(
            { param($evidence) $evidence.MsixCandidates[0].SourceUri = 'https://example.com/Claude.msix' },
            { param($evidence) $evidence.MsixCandidates[0].RedirectUri = 'https://example.com/Claude.msix' },
            { param($evidence) $evidence.MsixCandidates[1].SourceUri += '?token=synthetic' },
            { param($evidence) $evidence.Git.SourceUri = 'https://example.com/Git.exe' },
            { param($evidence) $evidence.Git.SourceUri += '?asset=1' },
            { param($evidence) $evidence.MsixCandidates[0].RedirectUri = 'https://downloads.claude.ai/' + ('a' * 2048) }
        )
        foreach ($attack in $attacks) {
            $evidence = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
            & $attack $evidence
            Update-CddsiVmCalibrationInternalFields -Evidence $evidence
            (Test-CddsiVmCalibrationEvidenceFixture -Evidence $evidence -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
        }
    }

    It 'rejects relabelled duplicate MSIX candidates and Git asset route drift' {
        $duplicate = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $duplicate.Evidence.MsixCandidates[1].SourceUri = $duplicate.Evidence.MsixCandidates[0].SourceUri
        $duplicate.Evidence.MsixCandidates[1].RedirectUri = $duplicate.Evidence.MsixCandidates[0].RedirectUri
        $duplicate.Evidence.MsixCandidates[1].ArtifactSha256 = $duplicate.Evidence.MsixCandidates[0].ArtifactSha256
        Update-CddsiVmCalibrationInternalFields -Evidence $duplicate.Evidence
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $duplicate.Evidence -Session $duplicate.Session -AnchorToken $duplicate.SessionAnchorToken) | Should -BeFalse

        $wrongFlavorRoute = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $wrongFlavorRoute.Evidence.MsixCandidates[1].SourceUri = 'https://claude.ai/api/desktop/win32/x64/latest/redirect'
        Update-CddsiVmCalibrationInternalFields -Evidence $wrongFlavorRoute.Evidence
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $wrongFlavorRoute.Evidence -Session $wrongFlavorRoute.Session -AnchorToken $wrongFlavorRoute.SessionAnchorToken) | Should -BeFalse

        $gitRouteDrift = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $gitRouteDrift.Evidence.Git.AssetName = 'Git-2.53.0.3-arm64.exe'
        Update-CddsiVmCalibrationInternalFields -Evidence $gitRouteDrift.Evidence
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $gitRouteDrift.Evidence -Session $gitRouteDrift.Session -AnchorToken $gitRouteDrift.SessionAnchorToken) | Should -BeFalse
    }

    It 'rejects observation drift even after every evidence-internal derived field is recomputed' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $forged = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $forged.MsixCandidates[0].SizeBytes = 104857601
        Update-CddsiVmCalibrationInternalFields -Evidence $forged
        $forged.EvidenceBindingToken | Should -BeExactly (Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $forged)
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $forged -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
        $state = New-CddsiVmCalibrationConsumptionStateFixture -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken
        (Resolve-CddsiVmCalibrationConsumptionFixture -Evidence $forged -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken -ConsumptionState $state).CanFreezeP10B | Should -BeFalse
    }

    It 'rejects whole-evidence binding drift and evidence-session mismatch' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $bindingDrift = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $bindingDrift.EvidenceBindingToken = ('0' * 64)
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $bindingDrift -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse

        $referenceDrift = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $referenceDrift.SessionBinding.ClaimId = '60000000-0000-4000-8000-000000000001'
        $referenceDrift.EvidenceBindingToken = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $referenceDrift
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $referenceDrift -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse

        $otherSession = Copy-CddsiVmCalibrationFixture -Value $bundle.Session
        $otherSession.OperationUseStates[0].ProviderEvidenceDigest = ('0' * 64)
        $otherSession.OperationUseStates[0].ReceiptBindingToken = Get-CddsiOperationUseBindingToken -OperationUseState $otherSession.OperationUseStates[0]
        $otherSession.WorkflowSessionState.TerminalOperationSetDigestSha256 = Get-CddsiTerminalOperationSetDigest -OperationGrant $otherSession.OperationGrant -OperationUseStates $otherSession.OperationUseStates
        $otherSession.WorkflowSessionState.ReceiptBindingToken = Get-CddsiWorkflowSessionBindingToken -WorkflowSessionState $otherSession.WorkflowSessionState
        $otherSession.SessionBindingToken = Get-CddsiVmCalibrationSessionBindingToken -ExpectedSession $otherSession
        (Test-CddsiVmCalibrationSessionFixture -Session $otherSession -AnchorToken $bundle.SessionAnchorToken) | Should -BeTrue
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $bundle.Evidence -Session $otherSession -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse
    }

    It 'keeps COMPLETE distinct from comprehensive acceptance and rejects injected sensitive fields' {
        $bundle = Copy-CddsiVmCalibrationFixture -Value $script:DefaultVmCalibrationBundleFixture
        $raw = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $raw.DesktopBehavior.HkcuManagedPolicy | Add-Member -NotePropertyName RegistryValues -NotePropertyValue @{}
        $raw.EvidenceBindingToken = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $raw
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $raw -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse

        $secret = Copy-CddsiVmCalibrationFixture -Value $bundle.Evidence
        $secret.MsixCandidates[0].Signer.Subject = 'authorization=' + ('T' * 32)
        $secret.EvidenceBindingToken = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $secret
        (Test-CddsiVmCalibrationEvidenceFixture -Evidence $secret -Session $bundle.Session -AnchorToken $bundle.SessionAnchorToken) | Should -BeFalse

        (ConvertTo-CddsiJson -InputObject $bundle.Evidence) | Should -Not -Match 'CanFreezeP10B'
        $bundle.Evidence.Readiness.ComprehensiveAcceptance | Should -BeFalse
    }
}

AfterAll {
    if ($null -ne $script:ConsumptionAuthority -and $null -ne $script:ConsumptionAuthority.Signer) {
        $script:ConsumptionAuthority.Signer.Dispose()
    }
}
