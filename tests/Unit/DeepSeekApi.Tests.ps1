BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function New-CddsiCredentialStageManifest {
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-stage-manifest-v1'
            Stage = 'VmAcceptance'; ArtifactProfile = 'VmAcceptance'; ArtifactVersion = '1.2.3'
            CommitId = ('a' * 40); ArtifactSha256 = ('b' * 64); SidecarSha256 = ('d' * 64)
            ContentDigest = ('c' * 64); CreatedAtUtc = '2030-01-01T00:00:00Z'
        }
    }

    function New-CddsiCredentialAuthorizationBundle {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('PersistCredential', 'RemoveCredential', 'RestoreCredentialState')][string]$Operation,
            [Parameter(Mandatory = $true)][int]$Index,
            [string]$RunId = '20000000-0000-4000-8000-000000000801',
            [string]$PromptDigest = '',
            [string]$IssuedAtUtc = '2030-01-01T00:00:00Z',
            [string]$SessionClaimedAtUtc = '2030-01-01T00:02:00Z',
            [string]$ConfirmedAtUtc = '2030-01-01T00:05:00Z',
            [string]$OperationClaimedAtUtc = '2030-01-01T00:10:00Z'
        )
        if ([string]::IsNullOrEmpty($PromptDigest)) { $PromptDigest = ([string]$Index).PadLeft(64, '0') }
        $manifest = New-CddsiCredentialStageManifest
        $suffix = $Index.ToString('000000000000')
        $grant = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-operation-grant-v2'
            GrantId = "10000000-0000-4000-8000-$suffix"; ArtifactSha256 = $manifest.ArtifactSha256
            SidecarSha256 = $manifest.SidecarSha256; ContentDigest = $manifest.ContentDigest
            ArtifactProfile = $manifest.ArtifactProfile; RunId = $RunId; IssuedAtUtc = $IssuedAtUtc
            ExpiresAtUtc = '2030-01-01T01:00:00Z'; Nonce = "30000000-0000-4000-8000-$suffix"
            AllowedOperations = @($Operation); SingleUse = $true
            ConfirmationBindings = @([pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId = "50000000-0000-4000-8000-$suffix"; Operation = $Operation
                PromptDigest = $PromptDigest; Required = $true
            })
        }
        $session = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-authorization-session-v1'; State = 'CLAIMED'
            GrantId = $grant.GrantId; Nonce = $grant.Nonce; ClaimId = "40000000-0000-4000-8000-$suffix"
            RunId = $RunId; ArtifactSha256 = $grant.ArtifactSha256; SidecarSha256 = $grant.SidecarSha256
            ContentDigest = $grant.ContentDigest; ArtifactProfile = $grant.ArtifactProfile
            ClaimedAtUtc = $SessionClaimedAtUtc; ExpiresAtUtc = $grant.ExpiresAtUtc; Revision = 1
        }
        $workflow = New-CddsiWorkflowSessionState -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $session
        $confirmation = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-interactive-confirmation-v2'
            ConfirmationId = $grant.ConfirmationBindings[0].ConfirmationId; GrantId = $grant.GrantId
            ClaimId = $session.ClaimId; PromptDigest = $PromptDigest; ArtifactSha256 = $grant.ArtifactSha256
            SidecarSha256 = $grant.SidecarSha256; ContentDigest = $grant.ContentDigest
            ArtifactProfile = $grant.ArtifactProfile; RunId = $RunId; Nonce = $grant.Nonce
            Operation = $Operation; Confirmed = $true; ConfirmedAtUtc = $ConfirmedAtUtc
        }
        $available = New-CddsiOperationUseState -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -Operation $Operation
        $proposal = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $available `
            -Confirmation $confirmation -Operation $Operation `
            -OperationUseId "60000000-0000-4000-8000-$suffix" -ExpectedRevision 0 `
            -RunId $RunId -NowUtc $OperationClaimedAtUtc
        if (-not $proposal.Data.AuthorizationProposed) { throw 'Synthetic credential authorization claim failed.' }
        return [pscustomobject][ordered]@{
            Index = $Index; Manifest = $manifest; Grant = $grant; Session = $session
            Workflow = $workflow; Confirmation = $confirmation
            ClaimedReceipt = $proposal.Data.ProposedOperationUseState
        }
    }

    function New-CddsiCredentialPlanFixture {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('Install', 'Rotate', 'Revoke', 'Cleanup')][string]$Action,
            [int]$Index = 801,
            [string]$CredentialBlobToken = '<DPAPI_BLOB:00000000-0000-0000-0000-000000000601>'
        )
        $operation = if ($Action -in @('Install', 'Rotate')) { 'PersistCredential' } else { 'RemoveCredential' }
        $bundle = New-CddsiCredentialAuthorizationBundle -Operation $operation -Index $Index
        $previous = if ($Action -ceq 'Rotate') { '<DPAPI_BLOB:00000000-0000-0000-0000-000000000600>' } else { $null }
        $plan = New-CddsiCredentialLifecyclePlan -Action $Action -StageManifest $bundle.Manifest `
            -OperationGrant $bundle.Grant -AuthorizationSession $bundle.Session `
            -WorkflowSessionState $bundle.Workflow -PrimaryConfirmation $bundle.Confirmation `
            -PrimaryCommittedOperationUseReceipt $bundle.ClaimedReceipt `
            -ExpectedRunId $bundle.Grant.RunId -CreatedAtUtc '2030-01-01T00:11:00Z' `
            -ValidationTimeUtc '2030-01-01T00:12:00Z' -CredentialBlobToken $CredentialBlobToken `
            -PreviousBlobToken $previous -HelperArtifactSha256 ('e' * 64)
        return [pscustomobject][ordered]@{ Bundle = $bundle; Plan = $plan }
    }

    function New-CddsiCredentialLifecycleEvent {
        param(
            [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)]$Step,
            [Parameter(Mandatory = $true)][long]$Sequence,
            [Parameter(Mandatory = $true)][string]$OperationUseId,
            [Parameter(Mandatory = $true)][string]$AuthorizationBindingToken,
            [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$TerminalState,
            [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
            [ValidateSet('SUCCEEDED', 'FAILED')][string]$Outcome = 'SUCCEEDED',
            [ValidateSet('NONE', 'UNCHANGED', 'CHANGED', 'UNKNOWN')][string]$MutationState = 'NONE'
        )
        $digest = Get-CddsiCredentialLifecycleProviderEvidenceSha256 -PlanId $Plan.PlanId `
            -TransactionId $Plan.TransactionId -Sequence $Sequence -Name $Step.Name `
            -Outcome $Outcome -MutationState $MutationState -AuthorizationSlot $Step.AuthorizationSlot `
            -Operation $Step.Operation -OperationUseId $OperationUseId -OperationUseRevision 2 `
            -OperationUseTerminalState $TerminalState -OccurredAtUtc $OccurredAtUtc `
            -AuthorizationBindingToken $AuthorizationBindingToken
        return [pscustomobject][ordered]@{
            Sequence = $Sequence; Name = $Step.Name; Outcome = $Outcome; MutationState = $MutationState
            AuthorizationSlot = $Step.AuthorizationSlot; Operation = $Step.Operation
            OperationUseId = $OperationUseId; OperationUseRevision = 2
            OperationUseTerminalState = $TerminalState; OccurredAtUtc = $OccurredAtUtc
            ProviderEvidenceSha256 = $digest
        }
    }

    function New-CddsiCredentialTerminalReceipt {
        param(
            [Parameter(Mandatory = $true)]$Bundle,
            [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)][ValidateSet('PRIMARY', 'COMPENSATION')][string]$AuthorizationSlot,
            [Parameter(Mandatory = $true)][object[]]$Events,
            [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome,
            [string]$TerminalReasonCode = ''
        )
        $aggregate = Get-CddsiCredentialLifecycleProviderAggregateSha256 -PlanId $Plan.PlanId `
            -TransactionId $Plan.TransactionId -AuthorizationSlot $AuthorizationSlot `
            -Operation $Bundle.ClaimedReceipt.Operation -OperationUseId $Bundle.ClaimedReceipt.OperationUseId `
            -OperationUseRevision 2 -OperationUseTerminalState $Outcome -Events $Events
        $suffix = $Bundle.Index.ToString('000000000000')
        $result = Resolve-CddsiOperationUseTerminal -StageManifest $Bundle.Manifest `
            -OperationGrant $Bundle.Grant -AuthorizationSession $Bundle.Session `
            -WorkflowSessionState $Bundle.Workflow -OperationUseState $Bundle.ClaimedReceipt `
            -Operation $Bundle.ClaimedReceipt.Operation -OperationUseId $Bundle.ClaimedReceipt.OperationUseId `
            -ExpectedRevision 1 -Outcome $Outcome -ProviderEvidenceDigest $aggregate `
            -OccurredAtUtc $Events[-1].OccurredAtUtc `
            -IdempotencyKey "70000000-0000-4000-8000-$suffix" -TerminalReasonCode $TerminalReasonCode
        if (-not $result.Data.Terminalized) { throw 'Synthetic credential terminal receipt failed.' }
        return [pscustomobject][ordered]@{ Receipt = $result.Data.TerminalOperationUseState; Aggregate = $aggregate }
    }

    function Get-CddsiCredentialCompensationPromptDigest {
        param([Parameter(Mandatory = $true)]$Plan, [Parameter(Mandatory = $true)]$PrimaryTerminal, [Parameter(Mandatory = $true)][string]$PrimaryAggregate)
        return Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-credential-compensation-confirmation-v2', $Plan.PlanId, $Plan.TransactionId,
            $PrimaryTerminal.ReceiptBindingToken, $PrimaryAggregate, $PrimaryTerminal.OccurredAtUtc,
            $Plan.Action, $Plan.CompensationSpec.Operation
        ) -join "`n")
    }

    function Get-CddsiCredentialCompensationBindingToken {
        param(
            [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)]$PrimaryTerminal,
            [Parameter(Mandatory = $true)][string]$PrimaryAggregate,
            [Parameter(Mandatory = $true)][string]$PromptDigest,
            [Parameter(Mandatory = $true)]$CompensationAuthorization
        )
        return Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-credential-compensation-authorization-v2', $Plan.PlanId, $Plan.TransactionId,
            $Plan.Action, $Plan.CompensationSpec.Operation, $PrimaryTerminal.ReceiptBindingToken,
            $PrimaryAggregate, $PrimaryTerminal.OccurredAtUtc, $PromptDigest,
            $CompensationAuthorization.BindingToken
        ) -join "`n")
    }

    function New-CddsiCompensatedCredentialFailureFixture {
        param(
            [Parameter(Mandatory = $true)][ValidateSet('Install', 'Rotate', 'Revoke', 'Cleanup')][string]$Action,
            [int]$PrimaryIndex = 801,
            [int]$CompensationIndex = 901,
            [string]$CompensationIssuedAtUtc = '2030-01-01T00:31:00Z',
            [string]$PromptDigestOverride = ''
        )
        $fixture = New-CddsiCredentialPlanFixture -Action $Action -Index $PrimaryIndex
        $plan = $fixture.Plan; $primary = $fixture.Bundle
        $primaryEvents = @()
        $failureStep = $null
        foreach ($step in @($plan.Steps)) {
            $time = ([DateTimeOffset]'2030-01-01T00:29:00Z').AddSeconds([int]$step.Sequence).ToString('yyyy-MM-ddTHH:mm:ssZ')
            if ($step.Mutation) {
                $failureStep = $step
                $primaryEvents += New-CddsiCredentialLifecycleEvent -Plan $plan -Step $step `
                    -Sequence $step.Sequence -OperationUseId $primary.ClaimedReceipt.OperationUseId `
                    -AuthorizationBindingToken $plan.PrimaryAuthorization.BindingToken -TerminalState ABORTED `
                    -OccurredAtUtc $time -Outcome FAILED -MutationState UNKNOWN
                break
            }
            $primaryEvents += New-CddsiCredentialLifecycleEvent -Plan $plan -Step $step `
                -Sequence $step.Sequence -OperationUseId $primary.ClaimedReceipt.OperationUseId `
                -AuthorizationBindingToken $plan.PrimaryAuthorization.BindingToken -TerminalState ABORTED `
                -OccurredAtUtc $time -Outcome SUCCEEDED -MutationState NONE
        }
        $primaryTerminalData = New-CddsiCredentialTerminalReceipt -Bundle $primary -Plan $plan `
            -AuthorizationSlot PRIMARY -Events $primaryEvents -Outcome ABORTED -TerminalReasonCode PROVIDER_FAILED
        $promptDigest = Get-CddsiCredentialCompensationPromptDigest -Plan $plan `
            -PrimaryTerminal $primaryTerminalData.Receipt -PrimaryAggregate $primaryTerminalData.Aggregate
        if (-not [string]::IsNullOrEmpty($PromptDigestOverride)) { $promptDigest = $PromptDigestOverride }
        $compensation = New-CddsiCredentialAuthorizationBundle -Operation $plan.CompensationSpec.Operation `
            -Index $CompensationIndex -RunId $plan.RunId -PromptDigest $promptDigest `
            -IssuedAtUtc $CompensationIssuedAtUtc -SessionClaimedAtUtc '2030-01-01T00:32:00Z' `
            -ConfirmedAtUtc '2030-01-01T00:33:00Z' -OperationClaimedAtUtc '2030-01-01T00:34:00Z'
        $compensationBinding = Resolve-CddsiCredentialAuthorizationBinding `
            -StageManifest $compensation.Manifest -OperationGrant $compensation.Grant `
            -AuthorizationSession $compensation.Session -WorkflowSessionState $compensation.Workflow `
            -Confirmation $compensation.Confirmation -CommittedOperationUseReceipt $compensation.ClaimedReceipt `
            -ExpectedOperation $plan.CompensationSpec.Operation -ExpectedRunId $plan.RunId `
            -OccurredAtUtc '2030-01-01T00:36:00Z' -ValidationTimeUtc '2030-01-01T00:45:00Z'
        $compensationBindingToken = Get-CddsiCredentialCompensationBindingToken -Plan $plan `
            -PrimaryTerminal $primaryTerminalData.Receipt -PrimaryAggregate $primaryTerminalData.Aggregate `
            -PromptDigest $promptDigest -CompensationAuthorization $compensationBinding
        $compensationEvents = @()
        foreach ($step in @($plan.CompensationSpec.Steps)) {
            $sequence = $primaryEvents.Count + [int]$step.Sequence
            $time = ([DateTimeOffset]'2030-01-01T00:35:00Z').AddSeconds([int]$step.Sequence).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $mutation = if ($step.Mutation) { 'CHANGED' } else { 'NONE' }
            $compensationEvents += New-CddsiCredentialLifecycleEvent -Plan $plan -Step $step `
                -Sequence $sequence -OperationUseId $compensation.ClaimedReceipt.OperationUseId `
                -AuthorizationBindingToken $compensationBindingToken -TerminalState COMPLETED `
                -OccurredAtUtc $time -Outcome SUCCEEDED -MutationState $mutation
        }
        $compensationTerminalData = New-CddsiCredentialTerminalReceipt -Bundle $compensation -Plan $plan `
            -AuthorizationSlot COMPENSATION -Events $compensationEvents -Outcome COMPLETED
        $transcript = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-lifecycle-transcript-v2'
            PlanId = $plan.PlanId; TransactionId = $plan.TransactionId; Action = $plan.Action; RunId = $plan.RunId
            PrimaryOperationUseId = $primary.ClaimedReceipt.OperationUseId
            PrimaryTerminalReceiptBindingToken = $primaryTerminalData.Receipt.ReceiptBindingToken
            CompensationAuthorizationBindingToken = $compensationBindingToken
            CompensationOperationUseId = $compensation.ClaimedReceipt.OperationUseId
            CompensationTerminalReceiptBindingToken = $compensationTerminalData.Receipt.ReceiptBindingToken
            Events = @($primaryEvents + $compensationEvents)
        }
        $arguments = @{
            Plan = $plan; Transcript = $transcript; StageManifest = $primary.Manifest
            OperationGrant = $primary.Grant; AuthorizationSession = $primary.Session
            WorkflowSessionState = $primary.Workflow; PrimaryConfirmation = $primary.Confirmation
            PrimaryCommittedOperationUseReceipt = $primary.ClaimedReceipt
            PrimaryTerminalOperationUseReceipt = $primaryTerminalData.Receipt
            ExpectedRunId = $plan.RunId; ExpectedCreatedAtUtc = $plan.CreatedAtUtc
            ValidationTimeUtc = '2030-01-01T00:45:00Z'; ExpectedCredentialBlobToken = $plan.CredentialBlobToken
            ExpectedPreviousBlobToken = $plan.PreviousBlobToken; ExpectedHelperArtifactSha256 = $plan.HelperArtifactSha256
            CompensationStageManifest = $compensation.Manifest; CompensationOperationGrant = $compensation.Grant
            CompensationAuthorizationSession = $compensation.Session
            CompensationWorkflowSessionState = $compensation.Workflow
            CompensationConfirmation = $compensation.Confirmation
            CompensationCommittedOperationUseReceipt = $compensation.ClaimedReceipt
            CompensationTerminalOperationUseReceipt = $compensationTerminalData.Receipt
        }
        return [pscustomobject][ordered]@{
            Plan = $plan; Primary = $primary; PrimaryEvents = $primaryEvents
            PrimaryTerminal = $primaryTerminalData; Compensation = $compensation
            CompensationEvents = $compensationEvents; CompensationTerminal = $compensationTerminalData
            Transcript = $transcript; Arguments = $arguments; FailureStep = $failureStep
        }
    }
}

Describe 'DeepSeek API contracts' {
    It 'classifies stable HTTP and transport error families' {
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 400).Class | Should -Be 'InvalidInput'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 401).Class | Should -Be 'Unauthorized'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 429).Retryable | Should -BeTrue
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 503).Class | Should -Be 'ServerError'
        (ConvertTo-CddsiDeepSeekApiErrorClass -ExceptionKind Timeout).Class | Should -BeExactly 'Timeout'
    }

    It 'keeps secure input and API validation mutation-free in TestSafe' {
        $context = New-CddsiTestExecutionContext
        (Read-CddsiDeepSeekApiKeySecure -ExecutionContext $context -NonInteractive).Status | Should -Be 'ACTION_REQUIRED'
        (Invoke-CddsiDeepSeekApiValidation -ExecutionContext $context -Mode TestSafe).Data.RequestSent | Should -BeFalse
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'parses only one-line bare helper output into a SecureString' {
        $token = 'v4_' + ('A' * 29); $hash = ('d' * 64)
        $parsed = ConvertFrom-CddsiCredentialHelperOutput -StandardOutput $token -ExitCode 0 `
            -InvocationStatus Completed -ElapsedMilliseconds 50 `
            -ExpectedHelperArtifactSha256 $hash -ObservedHelperArtifactSha256 $hash
        $parsed.SecureValue | Should -BeOfType ([Security.SecureString])
        (ConvertTo-CddsiJson -InputObject $parsed) | Should -Not -Match ([regex]::Escape($token))
        { ConvertFrom-CddsiCredentialHelperOutput -StandardOutput ($token + "`n") -ExitCode 0 `
            -InvocationStatus Completed -ElapsedMilliseconds 50 `
            -ExpectedHelperArtifactSha256 $hash -ObservedHelperArtifactSha256 $hash } | Should -Throw
    }

    It 'binds fake protection provider arguments and evidence to a committed PersistCredential use' {
        $bundle = New-CddsiCredentialAuthorizationBundle -Operation PersistCredential -Index 811
        $createdAt = '2030-01-01T00:11:00Z'; $validation = '2030-01-01T00:12:00Z'
        $credentialBinding = Resolve-CddsiCredentialAuthorizationBinding -StageManifest $bundle.Manifest `
            -OperationGrant $bundle.Grant -AuthorizationSession $bundle.Session `
            -WorkflowSessionState $bundle.Workflow -Confirmation $bundle.Confirmation `
            -CommittedOperationUseReceipt $bundle.ClaimedReceipt -ExpectedOperation PersistCredential `
            -ExpectedRunId $bundle.Grant.RunId -OccurredAtUtc $createdAt -ValidationTimeUtc $validation
        $handle = '<CREDENTIAL_HANDLE:00000000-0000-0000-0000-000000000501>'
        $captureNonce = 'nonce-00000000-0000-0000-0000-000000000501'
        $operationNonce = 'nonce-00000000-0000-0000-0000-000000000502'
        $helperHash = ('e' * 64); $blob = '<DPAPI_BLOB:00000000-0000-0000-0000-000000000502>'
        $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f
            $credentialBinding.BindingToken, $handle, $captureNonce, $operationNonce, $helperHash,
            $blob, 'VERIFIED', $createdAt, $credentialBinding.OperationUseId)
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-v1'; Authorization = $credentialBinding
            CredentialResource = '<CREDENTIAL:DEEPSEEK>'; SourceHandleToken = $handle
            CaptureNonce = $captureNonce; OperationNonce = $operationNonce; HelperArtifactSha256 = $helperHash
            BlobToken = $blob; BlobResourceToken = '<CREDENTIAL_BLOB:DEEPSEEK>'; DpapiScope = 'CurrentUser'
            AclPolicy = 'CurrentUserOnly'; OwnerBound = $true; PlaintextPersisted = $false
            ReadbackStatus = 'VERIFIED'; CreatedAtUtc = $createdAt; ProviderIdempotencyRequired = $true
            ProviderIdempotencyKey = $credentialBinding.OperationUseId; ProviderEvidenceSha256 = $providerDigest; Valid = $true
        }
        $arguments = [ordered]@{
            ContractVersion = 'cddsi-credential-protection-provider-v1'
            AuthorizationBindingToken = $credentialBinding.BindingToken; Stage = $credentialBinding.Stage
            ArtifactProfile = $credentialBinding.ArtifactProfile; RunId = $credentialBinding.RunId
            ArtifactSha256 = $credentialBinding.ArtifactSha256; SidecarSha256 = $credentialBinding.SidecarSha256
            ContentDigest = $credentialBinding.ContentDigest; GrantId = $credentialBinding.GrantId
            ClaimId = $credentialBinding.ClaimId; ConfirmationId = $credentialBinding.ConfirmationId
            Operation = $credentialBinding.Operation; OperationUseId = $credentialBinding.OperationUseId
            OperationUseStateKeySha256 = $credentialBinding.OperationUseStateKeySha256
            OperationUseRevision = $credentialBinding.OperationUseRevision
            OperationUseReceiptBindingToken = $credentialBinding.ReceiptBindingToken
            ProviderIdempotencyRequired = $true; ProviderIdempotencyKey = $credentialBinding.OperationUseId
            HandleToken = $handle; CaptureNonce = $captureNonce; OperationNonce = $operationNonce
            HelperArtifactSha256 = $helperHash; CreatedAtUtc = $createdAt; Persist = $false
        }
        $context = New-CddsiTestExecutionContext -RunId $bundle.Grant.RunId -ExpectedCalls @(
            [ordered]@{ Provider = 'Credential'; Operation = 'ProtectCurrentUser'; ResourceToken = '<CREDENTIAL:DEEPSEEK>'; Arguments = $arguments; Result = $evidence }
        )
        $result = Protect-CddsiDeepSeekCredential -ExecutionContext $context -HandleToken $handle `
            -CaptureNonce $captureNonce -OperationNonce $operationNonce -HelperArtifactSha256 $helperHash `
            -StageManifest $bundle.Manifest -OperationGrant $bundle.Grant -AuthorizationSession $bundle.Session `
            -WorkflowSessionState $bundle.Workflow -Confirmation $bundle.Confirmation `
            -CommittedOperationUseReceipt $bundle.ClaimedReceipt -CreatedAtUtc $createdAt `
            -ValidationTimeUtc $validation -Mode TestSafe
        $result.Status | Should -Be 'SUCCEEDED'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'keeps credential protection mutation-free in DryRun' {
        $bundle = New-CddsiCredentialAuthorizationBundle -Operation PersistCredential -Index 812
        $context = New-CddsiTestExecutionContext -RunId $bundle.Grant.RunId -Mode DryRun
        $result = Protect-CddsiDeepSeekCredential -ExecutionContext $context `
            -HandleToken '<CREDENTIAL_HANDLE:00000000-0000-0000-0000-000000000501>' `
            -CaptureNonce 'nonce-00000000-0000-0000-0000-000000000501' `
            -OperationNonce 'nonce-00000000-0000-0000-0000-000000000502' `
            -HelperArtifactSha256 ('e' * 64) -StageManifest $bundle.Manifest `
            -OperationGrant $bundle.Grant -AuthorizationSession $bundle.Session `
            -WorkflowSessionState $bundle.Workflow -Confirmation $bundle.Confirmation `
            -CommittedOperationUseReceipt $bundle.ClaimedReceipt `
            -CreatedAtUtc '2030-01-01T00:11:00Z' -ValidationTimeUtc '2030-01-01T00:12:00Z' -Mode DryRun
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'rejects arbitrary grant ids authorization swaps replay expiration and future time' {
        $fixture = New-CddsiCredentialPlanFixture -Action Install -Index 821
        $bundle = $fixture.Bundle
        $common = @{
            Action = 'Install'; StageManifest = $bundle.Manifest; OperationGrant = $bundle.Grant
            AuthorizationSession = $bundle.Session; WorkflowSessionState = $bundle.Workflow
            PrimaryConfirmation = $bundle.Confirmation; PrimaryCommittedOperationUseReceipt = $bundle.ClaimedReceipt
            ExpectedRunId = $bundle.Grant.RunId; CreatedAtUtc = '2030-01-01T00:11:00Z'
            ValidationTimeUtc = '2030-01-01T00:12:00Z'
            CredentialBlobToken = '<DPAPI_BLOB:00000000-0000-0000-0000-000000000621>'
            HelperArtifactSha256 = ('e' * 64)
        }
        $badGrant = $bundle.Grant | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $badGrant.GrantId = '90000000-0000-4000-8000-000000000999'
        $case = $common.Clone(); $case.OperationGrant = $badGrant
        { New-CddsiCredentialLifecyclePlan @case } | Should -Throw
        $other = New-CddsiCredentialAuthorizationBundle -Operation PersistCredential -Index 822
        $case = $common.Clone(); $case.PrimaryConfirmation = $other.Confirmation
        { New-CddsiCredentialLifecyclePlan @case } | Should -Throw
        $terminal = Resolve-CddsiOperationUseTerminal -StageManifest $bundle.Manifest -OperationGrant $bundle.Grant `
            -AuthorizationSession $bundle.Session -WorkflowSessionState $bundle.Workflow `
            -OperationUseState $bundle.ClaimedReceipt -Operation PersistCredential `
            -OperationUseId $bundle.ClaimedReceipt.OperationUseId -ExpectedRevision 1 -Outcome ABORTED `
            -ProviderEvidenceDigest ('8' * 64) -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey '70000000-0000-4000-8000-000000000821' -TerminalReasonCode PROVIDER_FAILED
        $case = $common.Clone(); $case.PrimaryCommittedOperationUseReceipt = $terminal.Data.TerminalOperationUseState
        { New-CddsiCredentialLifecyclePlan @case } | Should -Throw
        $case = $common.Clone(); $case.ValidationTimeUtc = '2030-01-01T01:00:00Z'
        { New-CddsiCredentialLifecyclePlan @case } | Should -Throw
        $case = $common.Clone(); $case.CreatedAtUtc = '2030-01-01T00:13:00Z'
        { New-CddsiCredentialLifecyclePlan @case } | Should -Throw
    }

    It 'maps every action to strict primary and delayed action-specific compensation operations' {
        $expected = @{ Install = @('PersistCredential', 'RemoveCredential'); Rotate = @('PersistCredential', 'RestoreCredentialState'); Revoke = @('RemoveCredential', 'RestoreCredentialState'); Cleanup = @('RemoveCredential', 'RestoreCredentialState') }
        $index = 830
        foreach ($action in @('Install', 'Rotate', 'Revoke', 'Cleanup')) {
            $index++
            $plan = (New-CddsiCredentialPlanFixture -Action $action -Index $index).Plan
            $plan.PrimaryAuthorization.Operation | Should -BeExactly $expected[$action][0]
            $plan.CompensationSpec.Operation | Should -BeExactly $expected[$action][1]
            $plan.CompensationSpec.AuthorizationIssuance | Should -BeExactly 'AFTER_PRIMARY_FAILURE'
            $plan.PlanId | Should -Match '^[a-f0-9]{64}$'
            $plan.TransactionId | Should -Match '^[a-f0-9]{64}$'
        }
    }

    It 'rejects a validly rehashed plan when trusted resource inputs do not match' {
        $fixture = New-CddsiCredentialPlanFixture -Action Install -Index 841
        $rehashed = New-CddsiCredentialLifecyclePlan -Action Install -StageManifest $fixture.Bundle.Manifest `
            -OperationGrant $fixture.Bundle.Grant -AuthorizationSession $fixture.Bundle.Session `
            -WorkflowSessionState $fixture.Bundle.Workflow -PrimaryConfirmation $fixture.Bundle.Confirmation `
            -PrimaryCommittedOperationUseReceipt $fixture.Bundle.ClaimedReceipt -ExpectedRunId $fixture.Plan.RunId `
            -CreatedAtUtc $fixture.Plan.CreatedAtUtc -ValidationTimeUtc '2030-01-01T00:12:00Z' `
            -CredentialBlobToken '<DPAPI_BLOB:00000000-0000-0000-0000-000000000699>' `
            -HelperArtifactSha256 $fixture.Plan.HelperArtifactSha256
        { Resolve-CddsiCredentialLifecycleTranscript -Plan $rehashed -Transcript ([pscustomobject]@{}) `
            -StageManifest $fixture.Bundle.Manifest -OperationGrant $fixture.Bundle.Grant `
            -AuthorizationSession $fixture.Bundle.Session -WorkflowSessionState $fixture.Bundle.Workflow `
            -PrimaryConfirmation $fixture.Bundle.Confirmation `
            -PrimaryCommittedOperationUseReceipt $fixture.Bundle.ClaimedReceipt `
            -PrimaryTerminalOperationUseReceipt $fixture.Bundle.ClaimedReceipt `
            -ExpectedRunId $fixture.Plan.RunId -ExpectedCreatedAtUtc $fixture.Plan.CreatedAtUtc `
            -ValidationTimeUtc '2030-01-01T00:45:00Z' `
            -ExpectedCredentialBlobToken $fixture.Plan.CredentialBlobToken `
            -ExpectedHelperArtifactSha256 $fixture.Plan.HelperArtifactSha256 } | Should -Throw
    }

    It 'completes the primary journal without pre-claiming or inventing compensation' {
        $fixture = New-CddsiCredentialPlanFixture -Action Install -Index 842
        $events = @()
        foreach ($step in @($fixture.Plan.Steps)) {
            $time = ([DateTimeOffset]'2030-01-01T00:19:00Z').AddSeconds([int]$step.Sequence).ToString('yyyy-MM-ddTHH:mm:ssZ')
            $mutation = if ($step.Mutation) { 'CHANGED' } else { 'NONE' }
            $events += New-CddsiCredentialLifecycleEvent -Plan $fixture.Plan -Step $step `
                -Sequence $step.Sequence -OperationUseId $fixture.Bundle.ClaimedReceipt.OperationUseId `
                -AuthorizationBindingToken $fixture.Plan.PrimaryAuthorization.BindingToken `
                -TerminalState COMPLETED -OccurredAtUtc $time -Outcome SUCCEEDED -MutationState $mutation
        }
        $terminal = New-CddsiCredentialTerminalReceipt -Bundle $fixture.Bundle -Plan $fixture.Plan `
            -AuthorizationSlot PRIMARY -Events $events -Outcome COMPLETED
        $transcript = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-lifecycle-transcript-v2'
            PlanId = $fixture.Plan.PlanId; TransactionId = $fixture.Plan.TransactionId
            Action = $fixture.Plan.Action; RunId = $fixture.Plan.RunId
            PrimaryOperationUseId = $fixture.Bundle.ClaimedReceipt.OperationUseId
            PrimaryTerminalReceiptBindingToken = $terminal.Receipt.ReceiptBindingToken
            CompensationAuthorizationBindingToken = $null; CompensationOperationUseId = $null
            CompensationTerminalReceiptBindingToken = $null; Events = $events
        }
        $result = Resolve-CddsiCredentialLifecycleTranscript -Plan $fixture.Plan -Transcript $transcript `
            -StageManifest $fixture.Bundle.Manifest -OperationGrant $fixture.Bundle.Grant `
            -AuthorizationSession $fixture.Bundle.Session -WorkflowSessionState $fixture.Bundle.Workflow `
            -PrimaryConfirmation $fixture.Bundle.Confirmation `
            -PrimaryCommittedOperationUseReceipt $fixture.Bundle.ClaimedReceipt `
            -PrimaryTerminalOperationUseReceipt $terminal.Receipt -ExpectedRunId $fixture.Plan.RunId `
            -ExpectedCreatedAtUtc $fixture.Plan.CreatedAtUtc -ValidationTimeUtc '2030-01-01T00:45:00Z' `
            -ExpectedCredentialBlobToken $fixture.Plan.CredentialBlobToken `
            -ExpectedHelperArtifactSha256 $fixture.Plan.HelperArtifactSha256
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.CompensationStatus | Should -BeExactly 'NOT_REQUIRED'
    }

    It 'requires delayed compensation after an uncertain mutation and proves every action-specific journal' {
        $index = 850
        foreach ($action in @('Install', 'Rotate', 'Revoke', 'Cleanup')) {
            $index++
            $fixture = New-CddsiCompensatedCredentialFailureFixture -Action $action `
                -PrimaryIndex $index -CompensationIndex ($index + 100)
            $withoutCompensation = $fixture.Transcript | ConvertTo-Json -Depth 40 | ConvertFrom-Json
            $withoutCompensation.CompensationAuthorizationBindingToken = $null
            $withoutCompensation.CompensationOperationUseId = $null
            $withoutCompensation.CompensationTerminalReceiptBindingToken = $null
            $withoutCompensation.Events = @($fixture.PrimaryEvents)
            $arguments = $fixture.Arguments.Clone(); $arguments.Transcript = $withoutCompensation
            foreach ($name in @('CompensationStageManifest', 'CompensationOperationGrant', 'CompensationAuthorizationSession', 'CompensationWorkflowSessionState', 'CompensationConfirmation', 'CompensationCommittedOperationUseReceipt', 'CompensationTerminalOperationUseReceipt')) { $arguments.Remove($name) }
            (Resolve-CddsiCredentialLifecycleTranscript @arguments).Data.CompensationStatus | Should -BeExactly 'REQUIRED_NOT_PROVEN'
            $fullArguments = $fixture.Arguments
            $result = Resolve-CddsiCredentialLifecycleTranscript @fullArguments
            $result.Status | Should -BeExactly 'FAILED'
            $result.Data.CompensationStatus | Should -BeExactly 'FULL'
            $fixture.CompensationEvents[0].Name | Should -BeExactly $fixture.Plan.CompensationSpec.Steps[0].Name
        }
    }

    It 'rejects event-use swap early compensation cross-transaction prompt and provider evidence replay' {
        $fixture = New-CddsiCompensatedCredentialFailureFixture -Action Rotate -PrimaryIndex 871 -CompensationIndex 971
        $swapped = $fixture.Transcript | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $swapped.Events[-1].OperationUseId = $fixture.Primary.ClaimedReceipt.OperationUseId
        $arguments = $fixture.Arguments.Clone(); $arguments.Transcript = $swapped
        { Resolve-CddsiCredentialLifecycleTranscript @arguments } | Should -Throw

        $early = New-CddsiCompensatedCredentialFailureFixture -Action Rotate -PrimaryIndex 872 `
            -CompensationIndex 972 -CompensationIssuedAtUtc '2030-01-01T00:01:00Z'
        $earlyArguments = $early.Arguments
        { Resolve-CddsiCredentialLifecycleTranscript @earlyArguments } | Should -Throw

        $cross = New-CddsiCompensatedCredentialFailureFixture -Action Rotate -PrimaryIndex 873 `
            -CompensationIndex 973 -PromptDigestOverride ('f' * 64)
        $crossArguments = $cross.Arguments
        { Resolve-CddsiCredentialLifecycleTranscript @crossArguments } | Should -Throw

        $replay = $fixture.Transcript | ConvertTo-Json -Depth 40 | ConvertFrom-Json
        $replay.Events[-1].ProviderEvidenceSha256 = $replay.Events[-2].ProviderEvidenceSha256
        $arguments = $fixture.Arguments.Clone(); $arguments.Transcript = $replay
        { Resolve-CddsiCredentialLifecycleTranscript @arguments } | Should -Throw

        $install = New-CddsiCompensatedCredentialFailureFixture -Action Install -PrimaryIndex 874 -CompensationIndex 974
        $wrongBundle = New-CddsiCredentialAuthorizationBundle -Operation RestoreCredentialState -Index 975 `
            -RunId $install.Plan.RunId -PromptDigest $install.Compensation.Grant.ConfirmationBindings[0].PromptDigest `
            -IssuedAtUtc '2030-01-01T00:31:00Z' -SessionClaimedAtUtc '2030-01-01T00:32:00Z' `
            -ConfirmedAtUtc '2030-01-01T00:33:00Z' -OperationClaimedAtUtc '2030-01-01T00:34:00Z'
        $wrongArguments = $install.Arguments.Clone()
        $wrongArguments.CompensationStageManifest = $wrongBundle.Manifest
        $wrongArguments.CompensationOperationGrant = $wrongBundle.Grant
        $wrongArguments.CompensationAuthorizationSession = $wrongBundle.Session
        $wrongArguments.CompensationWorkflowSessionState = $wrongBundle.Workflow
        $wrongArguments.CompensationConfirmation = $wrongBundle.Confirmation
        $wrongArguments.CompensationCommittedOperationUseReceipt = $wrongBundle.ClaimedReceipt
        { Resolve-CddsiCredentialLifecycleTranscript @wrongArguments } | Should -Throw
    }
}
