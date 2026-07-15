BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function Copy-TestCoworkObject {
        param([Parameter(Mandatory = $true)]$InputObject)
        return [System.Management.Automation.PSSerializer]::Deserialize(
            [System.Management.Automation.PSSerializer]::Serialize($InputObject, 50)
        )
    }

    function New-TestCoworkStageContext {
        param([int]$IdentityBase = 701)

        $operations = @('PrepareCowork', 'ResumeCowork')
        $bindings = @()
        for ($index = 0; $index -lt $operations.Count; $index++) {
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId = '50000000-0000-4000-8000-{0}' -f (($IdentityBase + $index).ToString('000000000000'))
                Operation = $operations[$index]; PromptDigest = ([string]($index + 1) * 64); Required = $true
            }
        }
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-stage-manifest-v1'; Stage = 'VmAcceptance'
            ArtifactProfile = 'VmAcceptance'; ArtifactVersion = '1.2.3'; CommitId = ('a' * 40)
            ArtifactSha256 = ('b' * 64); SidecarSha256 = ('d' * 64); ContentDigest = ('c' * 64)
            CreatedAtUtc = '2030-01-01T00:00:00Z'
        }
        $grant = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-operation-grant-v2'
            GrantId = '10000000-0000-4000-8000-{0}' -f $IdentityBase.ToString('000000000000')
            ArtifactSha256 = $manifest.ArtifactSha256; SidecarSha256 = $manifest.SidecarSha256
            ContentDigest = $manifest.ContentDigest; ArtifactProfile = $manifest.ArtifactProfile
            RunId = '20000000-0000-4000-8000-{0}' -f $IdentityBase.ToString('000000000000')
            IssuedAtUtc = '2030-01-01T00:00:00Z'; ExpiresAtUtc = '2030-01-01T01:00:00Z'
            Nonce = '30000000-0000-4000-8000-{0}' -f $IdentityBase.ToString('000000000000')
            AllowedOperations = @($operations); SingleUse = $true; ConfirmationBindings = @($bindings)
        }
        $session = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-authorization-session-v1'; State = 'CLAIMED'
            GrantId = $grant.GrantId; Nonce = $grant.Nonce
            ClaimId = '40000000-0000-4000-8000-{0}' -f $IdentityBase.ToString('000000000000')
            RunId = $grant.RunId; ArtifactSha256 = $grant.ArtifactSha256; SidecarSha256 = $grant.SidecarSha256
            ContentDigest = $grant.ContentDigest; ArtifactProfile = $grant.ArtifactProfile
            ClaimedAtUtc = '2030-01-01T00:01:00Z'; ExpiresAtUtc = $grant.ExpiresAtUtc; Revision = 1
        }
        $workflow = New-CddsiWorkflowSessionState -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $session
        $prepareAvailable = New-CddsiOperationUseState -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -Operation PrepareCowork
        $resumeAvailable = New-CddsiOperationUseState -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -Operation ResumeCowork
        return [pscustomobject][ordered]@{
            StageManifest = $manifest; OperationGrant = $grant; AuthorizationSession = $session
            WorkflowSessionState = $workflow; PrepareAvailable = $prepareAvailable; ResumeAvailable = $resumeAvailable
        }
    }

    function Claim-TestCoworkOperation {
        param(
            [Parameter(Mandatory = $true)]$StageContext,
            [Parameter(Mandatory = $true)][string]$Operation,
            [Parameter(Mandatory = $true)][string]$OperationUseId,
            [Parameter(Mandatory = $true)][string]$ClaimedAtUtc
        )
        $available = if ($Operation -ceq 'PrepareCowork') { $StageContext.PrepareAvailable } else { $StageContext.ResumeAvailable }
        $binding = @($StageContext.OperationGrant.ConfirmationBindings | Where-Object Operation -CEQ $Operation)[0]
        $confirmation = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-interactive-confirmation-v2'
            ConfirmationId = $binding.ConfirmationId; GrantId = $StageContext.OperationGrant.GrantId
            ClaimId = $StageContext.AuthorizationSession.ClaimId; PromptDigest = $binding.PromptDigest
            ArtifactSha256 = $StageContext.OperationGrant.ArtifactSha256
            SidecarSha256 = $StageContext.OperationGrant.SidecarSha256
            ContentDigest = $StageContext.OperationGrant.ContentDigest
            ArtifactProfile = $StageContext.OperationGrant.ArtifactProfile; RunId = $StageContext.OperationGrant.RunId
            Nonce = $StageContext.OperationGrant.Nonce; Operation = $Operation; Confirmed = $true
            ConfirmedAtUtc = ([DateTimeOffset]::Parse($ClaimedAtUtc).AddSeconds(-10)).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $result = Resolve-CddsiOperationAuthorization -StageManifest $StageContext.StageManifest `
            -OperationGrant $StageContext.OperationGrant -AuthorizationSession $StageContext.AuthorizationSession `
            -WorkflowSessionState $StageContext.WorkflowSessionState -OperationUseState $available `
            -Confirmation $confirmation -Operation $Operation -OperationUseId $OperationUseId -ExpectedRevision 0 `
            -RunId $StageContext.OperationGrant.RunId -NowUtc $ClaimedAtUtc
        if (-not $result.Data.AuthorizationProposed) { throw 'synthetic Cowork claim failed' }
        return $result.Data.ProposedOperationUseState
    }

    function Complete-TestCoworkOperation {
        param(
            [Parameter(Mandatory = $true)]$StageContext,
            [Parameter(Mandatory = $true)]$ClaimedState,
            [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome,
            [Parameter(Mandatory = $true)][string]$ProviderEvidenceDigest,
            [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
            [Parameter(Mandatory = $true)][string]$IdempotencyKey,
            [string]$TerminalReasonCode = ''
        )
        if ($Outcome -ceq 'ABORTED' -and [string]::IsNullOrEmpty($TerminalReasonCode)) { $TerminalReasonCode = 'PROVIDER_FAILED' }
        $result = Resolve-CddsiOperationUseTerminal -StageManifest $StageContext.StageManifest `
            -OperationGrant $StageContext.OperationGrant -AuthorizationSession $StageContext.AuthorizationSession `
            -WorkflowSessionState $StageContext.WorkflowSessionState -OperationUseState $ClaimedState `
            -Operation $ClaimedState.Operation -OperationUseId $ClaimedState.OperationUseId -ExpectedRevision 1 `
            -Outcome $Outcome -ProviderEvidenceDigest $ProviderEvidenceDigest -OccurredAtUtc $OccurredAtUtc `
            -IdempotencyKey $IdempotencyKey -TerminalReasonCode $TerminalReasonCode
        if (-not $result.Data.Terminalized) { throw 'synthetic Cowork terminalization failed' }
        return $result.Data.TerminalOperationUseState
    }

    function New-TestCoworkPrepareEvent {
        param(
            [Parameter(Mandatory = $true)]$ClaimedState,
            [Parameter(Mandatory = $true)][int]$Sequence,
            [Parameter(Mandatory = $true)][string]$Name,
            [Parameter(Mandatory = $true)][string]$Outcome,
            [Parameter(Mandatory = $true)][string]$MutationState,
            [Parameter(Mandatory = $true)][string]$ReadbackStatus,
            [Parameter(Mandatory = $true)][bool]$RestartRequired,
            [Parameter(Mandatory = $true)][string]$OccurredAtUtc
        )
        $event = [pscustomobject][ordered]@{
            Sequence = $Sequence; Name = $Name; Outcome = $Outcome; MutationState = $MutationState
            ReadbackStatus = $ReadbackStatus; RestartRequired = $RestartRequired; OccurredAtUtc = $OccurredAtUtc
            OperationUseId = $ClaimedState.OperationUseId; ProviderEvidenceSha256 = $null
        }
        $event.ProviderEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-cowork-prepare-event-v3', $ClaimedState.RunId, $ClaimedState.ArtifactSha256,
            $ClaimedState.SidecarSha256, $ClaimedState.ContentDigest, $ClaimedState.ArtifactProfile,
            $ClaimedState.GrantId, $ClaimedState.ClaimId, $ClaimedState.WorkflowSessionStateKeySha256,
            $ClaimedState.OperationUseId, [string]$Sequence, $Name, $Outcome, $MutationState,
            $ReadbackStatus, ([string]$RestartRequired).ToLowerInvariant(), $OccurredAtUtc
        ) -join '|')
        return $event
    }

    function New-TestCoworkCheckpointFixture {
        $stage = New-TestCoworkStageContext
        $prepareClaim = Claim-TestCoworkOperation -StageContext $stage -Operation PrepareCowork `
            -OperationUseId '60000000-0000-4000-8000-000000000701' -ClaimedAtUtc '2030-01-01T00:02:00Z'
        $events = @(
            (New-TestCoworkPrepareEvent -ClaimedState $prepareClaim -Sequence 1 -Name 'feature_enable_no_restart' `
                -Outcome SUCCEEDED -MutationState CHANGED -ReadbackStatus NO_RESTART_REQUESTED `
                -RestartRequired:$false -OccurredAtUtc '2030-01-01T00:03:00Z'),
            (New-TestCoworkPrepareEvent -ClaimedState $prepareClaim -Sequence 2 -Name 'feature_readback' `
                -Outcome SUCCEEDED -MutationState NONE -ReadbackStatus ENABLED_PENDING_RESTART `
                -RestartRequired:$true -OccurredAtUtc '2030-01-01T00:04:00Z')
        )
        $transcript = [pscustomobject][ordered]@{
            SchemaVersion = 3; ContractVersion = 'cddsi-cowork-prepare-transcript-v3'
            UserDecision = 'Continue'; Events = @($events)
        }
        $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text ((@($events | ForEach-Object ProviderEvidenceSha256)) -join '|')
        $prepareTerminal = Complete-TestCoworkOperation -StageContext $stage -ClaimedState $prepareClaim `
            -Outcome COMPLETED -ProviderEvidenceDigest $providerDigest -OccurredAtUtc '2030-01-01T00:04:00Z' `
            -IdempotencyKey '70000000-0000-4000-8000-000000000701'
        $state = New-CddsiState -RunId $stage.OperationGrant.RunId -TimestampUtc '2030-01-01T00:00:00Z'
        $plan = New-CddsiCoworkCheckpointPlan -State $state -PrepareTranscript $transcript `
            -StageManifest $stage.StageManifest -OperationGrant $stage.OperationGrant `
            -AuthorizationSession $stage.AuthorizationSession -WorkflowSessionState $stage.WorkflowSessionState `
            -PrepareClaimedOperationUseState $prepareClaim -PrepareTerminalOperationUseState $prepareTerminal `
            -ResumeAvailableOperationUseState $stage.ResumeAvailable -ExpectedStateRevision 1 `
            -CheckpointId 'checkpoint-90000000-0000-4000-8000-000000000701' `
            -UpdatedAtUtc '2030-01-01T00:05:00Z' -ExpiresAtUtc '2030-01-01T00:55:00Z'
        return [pscustomobject][ordered]@{
            Stage = $stage; PrepareClaim = $prepareClaim; PrepareTerminal = $prepareTerminal
            Transcript = $transcript; Plan = $plan; State = $plan.CheckpointState
        }
    }

    function New-TestCoworkResumeClaim {
        param([Parameter(Mandatory = $true)]$Fixture)
        $resumeClaim = Claim-TestCoworkOperation -StageContext $Fixture.Stage -Operation ResumeCowork `
            -OperationUseId '60000000-0000-4000-8000-000000000702' -ClaimedAtUtc '2030-01-01T00:07:00Z'
        $claimedState = Claim-CddsiResumeCheckpointAttempt -State $Fixture.State `
            -ExpectedCheckpointId $Fixture.State.restart.checkpointId -ExpectedStateRevision $Fixture.State.revision `
            -ExpectedCheckpointRevision $Fixture.State.restart.checkpointRevision `
            -AttemptClaimId '80000000-0000-4000-8000-000000000701' `
            -ResumeOperationUseId $resumeClaim.OperationUseId `
            -ResumeClaimedReceiptBindingToken $resumeClaim.ReceiptBindingToken `
            -ResumeClaimedAtUtc $resumeClaim.ClaimedAtUtc -UpdatedAtUtc $resumeClaim.ClaimedAtUtc
        return [pscustomobject][ordered]@{ OperationUseState = $resumeClaim; State = $claimedState }
    }

    function New-TestCoworkResumeTerminal {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [Parameter(Mandatory = $true)]$ResumeClaim,
            [ValidateSet('Enabled', 'Disabled', 'PendingRestart', 'Unknown')][string]$FeatureState = 'Enabled',
            [ValidateSet('SUCCEEDED', 'FAILED', 'NOT_ATTEMPTED')][string]$CleanupOutcome = 'SUCCEEDED'
        )
        $digest = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-cowork-resume-provider-v3', $ResumeClaim.State.restart.checkpointId,
            [string]$ResumeClaim.State.revision, [string]$ResumeClaim.State.restart.checkpointRevision,
            $ResumeClaim.State.restart.attemptClaimId, $ResumeClaim.State.restart.resumeOperationUseId,
            $FeatureState, $CleanupOutcome, '2030-01-01T00:09:00Z'
        ) -join '|')
        $outcome = if ($FeatureState -ceq 'Enabled' -and $CleanupOutcome -ceq 'SUCCEEDED') { 'COMPLETED' } else { 'ABORTED' }
        $reason = if ($outcome -ceq 'COMPLETED') { '' } elseif ($CleanupOutcome -ceq 'FAILED') { 'PROVIDER_FAILED' } else { 'WORKFLOW_ABORTED' }
        return Complete-TestCoworkOperation -StageContext $Fixture.Stage `
            -ClaimedState $ResumeClaim.OperationUseState -Outcome $outcome -ProviderEvidenceDigest $digest `
            -OccurredAtUtc '2030-01-01T00:09:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000702' `
            -TerminalReasonCode $reason
    }
}

Describe 'Cowork checkpoint and resume receipts' {
    It 'leaves no checkpoint when the user refuses before mutation' {
        $stage = New-TestCoworkStageContext
        $transcript = [pscustomobject][ordered]@{
            SchemaVersion = 3; ContractVersion = 'cddsi-cowork-prepare-transcript-v3'
            UserDecision = 'Cancel'; Events = @()
        }
        $result = Resolve-CddsiCoworkFeatureChangeTranscript -Transcript $transcript `
            -StageManifest $stage.StageManifest -OperationGrant $stage.OperationGrant `
            -AuthorizationSession $stage.AuthorizationSession -WorkflowSessionState $stage.WorkflowSessionState `
            -PrepareInitialOperationUseState $stage.PrepareAvailable -PrepareTerminalOperationUseState $null `
            -NowUtc '2030-01-01T00:02:00Z'
        $result.Status | Should -Be 'CANCELLED'
        $result.Data.CheckpointDisposition | Should -Be 'ABSENT'
        $result.Data.CheckpointRetentionRequired | Should -BeFalse
    }

    It 'binds a pending restart checkpoint to stage session receipts and bounded expiry' {
        $fixture = New-TestCoworkCheckpointFixture
        $fixture.State.restart.required | Should -BeTrue
        $fixture.State.restart.resumeOperationState | Should -Be 'AVAILABLE'
        $fixture.State.restart.prepareTerminalReceiptBindingToken | Should -Be $fixture.PrepareTerminal.ReceiptBindingToken
        $fixture.State.restart.resumeAvailableReceiptBindingToken | Should -Be $fixture.Stage.ResumeAvailable.ReceiptBindingToken
        ([DateTimeOffset]::Parse($fixture.State.restart.expiresAtUtc) -le [DateTimeOffset]::Parse($fixture.Stage.AuthorizationSession.ExpiresAtUtc)) | Should -BeTrue
        $fixture.Plan.AutomaticRestartAllowed | Should -BeFalse

        $eligibility = Test-CddsiResumeCheckpointEligibility -State $fixture.State `
            -StageManifest $fixture.Stage.StageManifest -OperationGrant $fixture.Stage.OperationGrant `
            -AuthorizationSession $fixture.Stage.AuthorizationSession -WorkflowSessionState $fixture.Stage.WorkflowSessionState `
            -PrepareTerminalOperationUseState $fixture.PrepareTerminal `
            -ResumeOperationUseState $fixture.Stage.ResumeAvailable -NowUtc '2030-01-01T00:06:00Z'
        $eligibility.Status | Should -Be 'READY'
        (Get-Command Resolve-CddsiCoworkResume).Parameters.ContainsKey('CheckpointEligibility') | Should -BeFalse
    }

    It 'rejects corrupt early expired and cross-session resume attempts' {
        $fixture = New-TestCoworkCheckpointFixture
        $arguments = @{
            State = $fixture.State; StageManifest = $fixture.Stage.StageManifest
            OperationGrant = $fixture.Stage.OperationGrant; AuthorizationSession = $fixture.Stage.AuthorizationSession
            WorkflowSessionState = $fixture.Stage.WorkflowSessionState
            PrepareTerminalOperationUseState = $fixture.PrepareTerminal
            ResumeOperationUseState = $fixture.Stage.ResumeAvailable
        }
        (Test-CddsiResumeCheckpointEligibility @arguments -NowUtc '2030-01-01T00:04:00Z').Status | Should -Be 'EARLY'
        (Test-CddsiResumeCheckpointEligibility @arguments -NowUtc '2030-01-01T00:55:00Z').Status | Should -Be 'EXPIRED'
        $corrupt = Copy-TestCoworkObject $fixture.State
        $corrupt.completedSteps = @($corrupt.completedSteps); $corrupt.restart.attemptCount = '0'
        $bad = $arguments.Clone(); $bad.State = $corrupt
        (Test-CddsiResumeCheckpointEligibility @bad -NowUtc '2030-01-01T00:06:00Z').Status | Should -Be 'CORRUPT'
        $foreign = New-TestCoworkStageContext -IdentityBase 801
        $cross = $arguments.Clone(); $cross.StageManifest = $foreign.StageManifest; $cross.OperationGrant = $foreign.OperationGrant
        $cross.AuthorizationSession = $foreign.AuthorizationSession; $cross.WorkflowSessionState = $foreign.WorkflowSessionState
        $cross.ResumeOperationUseState = $foreign.ResumeAvailable
        (Test-CddsiResumeCheckpointEligibility @cross -NowUtc '2030-01-01T00:06:00Z').Status | Should -Be 'CONTEXT_MISMATCH'
    }

    It 'clears only after an independently claimed and terminal ResumeCowork receipt' {
        $fixture = New-TestCoworkCheckpointFixture
        $resume = New-TestCoworkResumeClaim -Fixture $fixture
        $terminal = New-TestCoworkResumeTerminal -Fixture $fixture -ResumeClaim $resume
        $result = Resolve-CddsiCoworkResume -State $resume.State -StageManifest $fixture.Stage.StageManifest `
            -OperationGrant $fixture.Stage.OperationGrant -AuthorizationSession $fixture.Stage.AuthorizationSession `
            -WorkflowSessionState $fixture.Stage.WorkflowSessionState `
            -PrepareTerminalOperationUseState $fixture.PrepareTerminal `
            -ResumeClaimedOperationUseState $resume.OperationUseState -ResumeTerminalOperationUseState $terminal `
            -NowUtc '2030-01-01T00:09:00Z' -UpdatedAtUtc '2030-01-01T00:09:00Z' `
            -FeatureState Enabled -CleanupOutcome SUCCEEDED
        $result.Status | Should -Be 'SUCCEEDED'
        $result.Data.CheckpointCleared | Should -BeTrue
        $result.Data.CleanupStatus | Should -Be 'COMPLETED_PROVEN'
        $result.Data.ProposedState.restart.required | Should -BeFalse
    }

    It 'retains an honest terminal checkpoint on cleanup failure and rejects replay' {
        $fixture = New-TestCoworkCheckpointFixture
        $resume = New-TestCoworkResumeClaim -Fixture $fixture
        $terminal = New-TestCoworkResumeTerminal -Fixture $fixture -ResumeClaim $resume -FeatureState Enabled -CleanupOutcome FAILED
        $common = @{
            StageManifest = $fixture.Stage.StageManifest; OperationGrant = $fixture.Stage.OperationGrant
            AuthorizationSession = $fixture.Stage.AuthorizationSession; WorkflowSessionState = $fixture.Stage.WorkflowSessionState
            PrepareTerminalOperationUseState = $fixture.PrepareTerminal
            ResumeClaimedOperationUseState = $resume.OperationUseState; ResumeTerminalOperationUseState = $terminal
            NowUtc = '2030-01-01T00:09:00Z'; UpdatedAtUtc = '2030-01-01T00:09:00Z'
            FeatureState = 'Enabled'; CleanupOutcome = 'FAILED'
        }
        $result = Resolve-CddsiCoworkResume -State $resume.State @common
        $result.Status | Should -Be 'FAILED'
        $result.Data.CheckpointCleared | Should -BeFalse
        $result.Data.ProposedState.restart.resumeOperationState | Should -Be 'ABORTED'
        $replay = Resolve-CddsiCoworkResume -State $result.Data.ProposedState @common
        $replay.Status | Should -Be 'FAILED'
        $replay.ErrorCode | Should -Be 'CHECKPOINT_TERMINAL_REPLAY'
    }

    It 'keeps TestSafe and DryRun mutation and real-access counters at zero' {
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $context = New-CddsiTestExecutionContext -Mode $mode -SandboxRoot $TestDrive
            $result = Enable-CddsiVirtualMachinePlatform -Context $context -Mode $mode
            $result.Changed | Should -BeFalse
            @($context.Providers.MutationSpy).Count | Should -Be 0
            Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $context) | Should -BeTrue
        }
    }
}
