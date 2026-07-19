BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\stage-policy.ps1')
    . (Join-Path $script:RepoRoot 'lib\orchestrator.ps1')

    function Copy-CddsiSyntheticObject {
        param(
            [Parameter(Mandatory = $true)]
            [AllowNull()]
            $InputObject,
            [AllowNull()]
            [System.Collections.ArrayList]$SourceReferences = $null,
            [AllowNull()]
            [System.Collections.ArrayList]$CopiedReferences = $null
        )

        if ($null -eq $InputObject) { return $null }
        if ($InputObject -is [string] -or $InputObject.GetType().IsValueType) {
            return $InputObject
        }
        if ($null -eq $SourceReferences) {
            $SourceReferences = [System.Collections.ArrayList]::new()
            $CopiedReferences = [System.Collections.ArrayList]::new()
        }
        for ($index = 0; $index -lt $SourceReferences.Count; $index++) {
            if ([object]::ReferenceEquals($SourceReferences[$index], $InputObject)) {
                return ,$CopiedReferences[$index]
            }
        }

        if ($InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
            $copy = [ordered]@{}
            [void]$SourceReferences.Add($InputObject)
            [void]$CopiedReferences.Add($copy)
            foreach ($key in $InputObject.Keys) {
                $copy.Add($key, (Copy-CddsiSyntheticObject -InputObject $InputObject[$key] `
                    -SourceReferences $SourceReferences -CopiedReferences $CopiedReferences))
            }
            return ,$copy
        }
        if ($InputObject -is [hashtable]) {
            $copy = @{}
            [void]$SourceReferences.Add($InputObject)
            [void]$CopiedReferences.Add($copy)
            foreach ($key in $InputObject.Keys) {
                $copy[$key] = Copy-CddsiSyntheticObject -InputObject $InputObject[$key] `
                    -SourceReferences $SourceReferences -CopiedReferences $CopiedReferences
            }
            return ,$copy
        }
        if ($InputObject.GetType().IsArray) {
            $copy = [object[]]::new($InputObject.Count)
            [void]$SourceReferences.Add($InputObject)
            [void]$CopiedReferences.Add($copy)
            for ($index = 0; $index -lt $InputObject.Count; $index++) {
                $copy[$index] = Copy-CddsiSyntheticObject -InputObject $InputObject[$index] `
                    -SourceReferences $SourceReferences -CopiedReferences $CopiedReferences
            }
            return ,$copy
        }
        if ($InputObject -is [System.Collections.IList]) {
            $copy = [System.Collections.ArrayList]::new()
            [void]$SourceReferences.Add($InputObject)
            [void]$CopiedReferences.Add($copy)
            foreach ($item in $InputObject) {
                [void]$copy.Add((Copy-CddsiSyntheticObject -InputObject $item `
                    -SourceReferences $SourceReferences -CopiedReferences $CopiedReferences))
            }
            return ,$copy
        }

        $copy = [pscustomobject][ordered]@{}
        [void]$SourceReferences.Add($InputObject)
        [void]$CopiedReferences.Add($copy)
        foreach ($property in @($InputObject.PSObject.Properties | Where-Object {
            $_.MemberType -in @('NoteProperty', 'Property')
        })) {
            $value = Copy-CddsiSyntheticObject -InputObject $property.Value `
                -SourceReferences $SourceReferences -CopiedReferences $CopiedReferences
            $copy.PSObject.Properties.Add(
                [System.Management.Automation.PSNoteProperty]::new($property.Name, $value)
            )
        }
        return ,$copy
    }

    function Get-CddsiSyntheticUtc {
        param([Parameter(Mandatory = $true)][int]$Minute)
        return ([DateTimeOffset]::Parse('2030-01-01T00:00:00Z').AddMinutes($Minute)).ToString('yyyy-MM-ddTHH:mm:ssZ')
    }

    function New-CddsiSyntheticOrchestratorContext {
        param(
            [ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')]
            [string]$Stage = 'VmAcceptance',
            [string]$RunId = '20000000-0000-4000-8000-000000000901'
        )

        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-stage-manifest-v1'
            Stage = $Stage; ArtifactProfile = $Stage; ArtifactVersion = '1.2.3-rc.1'
            CommitId = ('a' * 40); ArtifactSha256 = ('b' * 64); SidecarSha256 = ('d' * 64)
            ContentDigest = ('c' * 64); CreatedAtUtc = '2030-01-01T00:00:00Z'
        }
        $operations = @(Get-CddsiInstallPlanGrantedOperations)
        $bindings = @()
        for ($index = 0; $index -lt $operations.Count; $index++) {
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId = '50000000-0000-4000-8000-{0:d12}' -f ($index + 1)
                Operation = $operations[$index]
                PromptDigest = (($index + 1).ToString('x')).PadLeft(64, '0')
                Required = $true
            }
        }
        $grant = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-operation-grant-v2'
            GrantId = '10000000-0000-4000-8000-000000000901'
            ArtifactSha256 = $manifest.ArtifactSha256; SidecarSha256 = $manifest.SidecarSha256
            ContentDigest = $manifest.ContentDigest; ArtifactProfile = $Stage; RunId = $RunId
            IssuedAtUtc = '2030-01-01T00:00:00Z'; ExpiresAtUtc = '2030-01-01T01:00:00Z'
            Nonce = '30000000-0000-4000-8000-000000000901'
            AllowedOperations = @($operations); SingleUse = $true; ConfirmationBindings = @($bindings)
        }
        $session = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-authorization-session-v1'; State = 'CLAIMED'
            GrantId = $grant.GrantId; Nonce = $grant.Nonce
            ClaimId = '40000000-0000-4000-8000-000000000901'; RunId = $RunId
            ArtifactSha256 = $grant.ArtifactSha256; SidecarSha256 = $grant.SidecarSha256
            ContentDigest = $grant.ContentDigest; ArtifactProfile = $Stage
            ClaimedAtUtc = '2030-01-01T00:02:00Z'; ExpiresAtUtc = $grant.ExpiresAtUtc; Revision = 1
        }
        $workflow = New-CddsiWorkflowSessionState -StageManifest $manifest `
            -OperationGrant $grant -AuthorizationSession $session
        $planResult = New-CddsiInstallPlan -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow `
            -InstallScope PerUser -RunId $RunId
        return [pscustomobject][ordered]@{
            Manifest = $manifest; Grant = $grant; Session = $session; Workflow = $workflow
            PlanResult = $planResult; Plan = $planResult.Data
        }
    }

    function Get-CddsiSyntheticOperationIndex {
        param($Context, [Parameter(Mandatory = $true)][string]$Operation)
        $index = [array]::IndexOf([object[]]@($Context.Grant.AllowedOperations), $Operation)
        if ($index -lt 0) { throw 'Synthetic operation is absent from the grant.' }
        return $index
    }

    function Get-CddsiSyntheticOperationUseId {
        param($Context, [Parameter(Mandatory = $true)][string]$Operation)
        return '60000000-0000-4000-8000-{0:d12}' -f ((Get-CddsiSyntheticOperationIndex -Context $Context -Operation $Operation) + 1)
    }

    function Get-CddsiSyntheticIdempotencyKey {
        param($Context, [Parameter(Mandatory = $true)][string]$Operation)
        return '70000000-0000-4000-8000-{0:d12}' -f ((Get-CddsiSyntheticOperationIndex -Context $Context -Operation $Operation) + 1)
    }

    function Get-CddsiSyntheticProviderDigest {
        param($Context, [Parameter(Mandatory = $true)][string]$Operation)
        return (((Get-CddsiSyntheticOperationIndex -Context $Context -Operation $Operation) + 33).ToString('x')).PadLeft(64, '8')
    }

    function New-CddsiSyntheticConfirmation {
        param($Context, [Parameter(Mandatory = $true)][string]$Operation)
        $binding = @($Context.Grant.ConfirmationBindings | Where-Object Operation -CEQ $Operation)[0]
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-interactive-confirmation-v2'
            ConfirmationId = $binding.ConfirmationId; GrantId = $Context.Grant.GrantId
            ClaimId = $Context.Session.ClaimId; PromptDigest = $binding.PromptDigest
            ArtifactSha256 = $Context.Grant.ArtifactSha256; SidecarSha256 = $Context.Grant.SidecarSha256
            ContentDigest = $Context.Grant.ContentDigest; ArtifactProfile = $Context.Grant.ArtifactProfile
            RunId = $Context.Grant.RunId; Nonce = $Context.Grant.Nonce; Operation = $Operation
            Confirmed = $true; ConfirmedAtUtc = '2030-01-01T00:03:00Z'
        }
    }

    function New-CddsiSyntheticClaimedReceipt {
        param(
            $Context,
            [Parameter(Mandatory = $true)][string]$Operation,
            [Parameter(Mandatory = $true)][string]$ClaimedAtUtc
        )
        $available = New-CddsiOperationUseState -StageManifest $Context.Manifest `
            -OperationGrant $Context.Grant -AuthorizationSession $Context.Session `
            -WorkflowSessionState $Context.Workflow -Operation $Operation
        $proposal = Resolve-CddsiOperationAuthorization -StageManifest $Context.Manifest `
            -OperationGrant $Context.Grant -AuthorizationSession $Context.Session `
            -WorkflowSessionState $Context.Workflow -OperationUseState $available `
            -Confirmation (New-CddsiSyntheticConfirmation -Context $Context -Operation $Operation) `
            -Operation $Operation -OperationUseId (Get-CddsiSyntheticOperationUseId -Context $Context -Operation $Operation) `
            -ExpectedRevision 0 -RunId $Context.Grant.RunId -NowUtc $ClaimedAtUtc
        if (-not $proposal.Data.AuthorizationProposed) { throw 'Synthetic operation claim failed.' }
        return $proposal.Data.ProposedOperationUseState
    }

    function Complete-CddsiSyntheticReceipt {
        param(
            $Context,
            [Parameter(Mandatory = $true)]$ClaimedReceipt,
            [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
            [ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome = 'COMPLETED',
            [string]$TerminalReasonCode = ''
        )
        if ($Outcome -ceq 'ABORTED' -and [string]::IsNullOrEmpty($TerminalReasonCode)) {
            $TerminalReasonCode = 'PROVIDER_FAILED'
        }
        $result = Resolve-CddsiOperationUseTerminal -StageManifest $Context.Manifest `
            -OperationGrant $Context.Grant -AuthorizationSession $Context.Session `
            -WorkflowSessionState $Context.Workflow -OperationUseState $ClaimedReceipt `
            -Operation $ClaimedReceipt.Operation -OperationUseId $ClaimedReceipt.OperationUseId `
            -ExpectedRevision $ClaimedReceipt.Revision -Outcome $Outcome `
            -ProviderEvidenceDigest (Get-CddsiSyntheticProviderDigest -Context $Context -Operation $ClaimedReceipt.Operation) `
            -OccurredAtUtc $OccurredAtUtc `
            -IdempotencyKey (Get-CddsiSyntheticIdempotencyKey -Context $Context -Operation $ClaimedReceipt.Operation) `
            -TerminalReasonCode $TerminalReasonCode
        if (-not $result.Data.Terminalized) { throw 'Synthetic operation terminal reduction failed.' }
        return $result.Data.TerminalOperationUseState
    }

    function New-CddsiSyntheticTraceEvent {
        param(
            $Context, [int]$Sequence, [string]$StepId,
            [ValidateSet('STARTED', 'SUCCEEDED', 'FAILED', 'CANCELLED')][string]$Outcome,
            [ValidateSet('NONE', 'CHANGED', 'UNCHANGED', 'UNKNOWN')][string]$MutationState,
            [string]$OccurredAtUtc, [AllowNull()]$Receipt = $null,
            [AllowNull()]$ErrorCode = $null
        )
        $event = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-orchestrator-trace-event-v2'
            Sequence = $Sequence; PlanId = $Context.Plan.PlanId; StepId = $StepId
            Outcome = $Outcome; MutationState = $MutationState; OccurredAtUtc = $OccurredAtUtc
            ProviderEvidenceDigest = $null; OperationUseReceipt = $Receipt; ErrorCode = $ErrorCode
        }
        $event.ProviderEvidenceDigest = if ($null -ne $Receipt -and $Outcome -cne 'STARTED') {
            $Receipt.ProviderEvidenceDigest
        }
        else { Get-CddsiTraceEventEvidenceDigest -Plan $Context.Plan -Event $event }
        return $event
    }

    function New-CddsiSyntheticTraceEvents {
        param($Context, [AllowNull()][string]$FailureStepId = $null)
        $events = [System.Collections.Generic.List[object]]::new()
        $sequence = 0; $minute = 2
        foreach ($step in @($Context.Plan.Steps)) {
            $minute++; $startTime = Get-CddsiSyntheticUtc -Minute $minute
            $claimed = if ($step.RequiresGrant) {
                New-CddsiSyntheticClaimedReceipt -Context $Context -Operation $step.Operation -ClaimedAtUtc $startTime
            }
            else { $null }
            $sequence++
            $events.Add((New-CddsiSyntheticTraceEvent -Context $Context -Sequence $sequence `
                -StepId $step.Id -Outcome STARTED -MutationState NONE -OccurredAtUtc $startTime -Receipt $claimed))
            $minute++; $terminalTime = Get-CddsiSyntheticUtc -Minute $minute
            $failed = $step.Id -ceq $FailureStepId
            $terminalReceipt = if ($step.RequiresGrant) {
                Complete-CddsiSyntheticReceipt -Context $Context -ClaimedReceipt $claimed `
                    -OccurredAtUtc $terminalTime -Outcome $(if ($failed) { 'ABORTED' } else { 'COMPLETED' })
            }
            else { $null }
            $sequence++
            $events.Add((New-CddsiSyntheticTraceEvent -Context $Context -Sequence $sequence `
                -StepId $step.Id -Outcome $(if ($failed) { 'FAILED' } else { 'SUCCEEDED' }) `
                -MutationState $(if ($failed -and $step.Mutation) { 'UNKNOWN' } elseif ($step.Mutation) { 'CHANGED' } else { 'NONE' }) `
                -OccurredAtUtc $terminalTime -Receipt $terminalReceipt `
                -ErrorCode $(if ($failed) { 'SYNTHETIC_PROVIDER_FAILED' } else { $null })))
            if ($failed) { break }
        }
        return @($events | ForEach-Object { $_ })
    }

    function New-CddsiSyntheticCompensationEvent {
        param(
            $Context, $CompensationPlan, [int]$Sequence, $Item,
            [ValidateSet('STARTED', 'SUCCEEDED', 'FAILED')][string]$Outcome,
            [string]$OccurredAtUtc, $Receipt, [AllowNull()]$ErrorCode = $null
        )
        $event = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-compensation-trace-event-v2'
            Sequence = $Sequence; PlanId = $Context.Plan.PlanId
            CompensationPlanId = $CompensationPlan.CompensationPlanId
            SourceStepId = $Item.SourceStepId; Operation = $Item.Operation; Outcome = $Outcome
            OccurredAtUtc = $OccurredAtUtc; ProviderEvidenceDigest = $null
            OperationUseReceipt = $Receipt; ErrorCode = $ErrorCode
        }
        $event.ProviderEvidenceDigest = if ($Outcome -ceq 'STARTED') {
            Get-CddsiCompensationEventEvidenceDigest -CompensationPlan $CompensationPlan -Event $event
        }
        else { $Receipt.ProviderEvidenceDigest }
        return $event
    }

    function New-CddsiSyntheticCompensationEvents {
        param(
            $Context, $CompensationPlan,
            [AllowNull()][string]$FailureSourceStepId = $null,
            [int]$StartMinute = 19
        )
        $events = [System.Collections.Generic.List[object]]::new()
        $sequence = 0; $minute = $StartMinute
        foreach ($item in @($CompensationPlan.Compensations)) {
            $minute++; $startTime = Get-CddsiSyntheticUtc -Minute $minute
            $claimed = New-CddsiSyntheticClaimedReceipt -Context $Context `
                -Operation $item.Operation -ClaimedAtUtc $startTime
            $sequence++
            $events.Add((New-CddsiSyntheticCompensationEvent -Context $Context `
                -CompensationPlan $CompensationPlan -Sequence $sequence -Item $item `
                -Outcome STARTED -OccurredAtUtc $startTime -Receipt $claimed))
            $minute++; $terminalTime = Get-CddsiSyntheticUtc -Minute $minute
            $failed = $item.SourceStepId -ceq $FailureSourceStepId
            $terminal = Complete-CddsiSyntheticReceipt -Context $Context -ClaimedReceipt $claimed `
                -OccurredAtUtc $terminalTime -Outcome $(if ($failed) { 'ABORTED' } else { 'COMPLETED' }) `
                -TerminalReasonCode $(if ($failed) { 'COMPENSATION_FAILED' } else { '' })
            $sequence++
            $events.Add((New-CddsiSyntheticCompensationEvent -Context $Context `
                -CompensationPlan $CompensationPlan -Sequence $sequence -Item $item `
                -Outcome $(if ($failed) { 'FAILED' } else { 'SUCCEEDED' }) `
                -OccurredAtUtc $terminalTime -Receipt $terminal `
                -ErrorCode $(if ($failed) { 'SYNTHETIC_COMPENSATION_FAILED' } else { $null })))
            if ($failed) { break }
        }
        return @($events | ForEach-Object { $_ })
    }

    $script:CanonicalOrchestratorContext = New-CddsiSyntheticOrchestratorContext
    $script:CanonicalSuccessfulTraceEvents = New-CddsiSyntheticTraceEvents `
        -Context $script:CanonicalOrchestratorContext
    $script:CanonicalEnsureGitFailureTraceEvents = New-CddsiSyntheticTraceEvents `
        -Context $script:CanonicalOrchestratorContext -FailureStepId ensure_git
}

Describe 'bound install plan v2' {
    It 'binds the exact executable stage contexts and fixed forward plus compensation operations' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $context.PlanResult.Status | Should -BeExactly 'SUCCEEDED'
        $context.PlanResult.Changed | Should -BeFalse
        (Test-CddsiInstallPlan -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow) | Should -BeTrue
        $context.Plan.ContractVersion | Should -BeExactly 'cddsi-install-plan-v2'
        $context.Plan.PlanId | Should -Match '^[a-f0-9]{64}$'
        $context.Plan.PlanId | Should -BeExactly (Get-CddsiInstallPlanBindingToken -Plan $context.Plan)
        @($context.Plan.Steps).Count | Should -Be 13
        @($context.Plan.Steps | Where-Object RequiresGrant).Count | Should -Be 11
        @($context.Grant.AllowedOperations).Count | Should -Be 20
        @($context.Grant.AllowedOperations) -join '|' | Should -BeExactly (@(Get-CddsiInstallPlanGrantedOperations) -join '|')
        @($context.Plan.RequestedSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
    }

    It 'fails closed outside VmAcceptance or UserLive and without exact grant coverage' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $calibrationManifest = Copy-CddsiSyntheticObject -InputObject $context.Manifest
        $calibrationManifest.Stage = 'VmCalibration'
        $calibrationManifest.ArtifactProfile = 'VmCalibration'
        (New-CddsiInstallPlan -StageManifest $calibrationManifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -InstallScope PerUser -RunId $context.Grant.RunId).Status | Should -BeExactly 'ACTION_REQUIRED'

        $grant = Copy-CddsiSyntheticObject -InputObject $context.Grant
        $grant.AllowedOperations = @($grant.AllowedOperations | Select-Object -SkipLast 1)
        $grant.ConfirmationBindings = @($grant.ConfirmationBindings | Select-Object -SkipLast 1)
        (New-CddsiInstallPlan -StageManifest $context.Manifest -OperationGrant $grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -InstallScope PerUser -RunId $grant.RunId).Status | Should -BeExactly 'ACTION_REQUIRED'
    }

    It 'rejects locally rehashed run session step and operation-use drift' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        foreach ($mutation in @('Run', 'Step', 'UseKey')) {
            $tampered = Copy-CddsiSyntheticObject -InputObject $context.Plan
            if ($mutation -ceq 'Run') { $tampered.RunId = '20000000-0000-4000-8000-000000000999' }
            elseif ($mutation -ceq 'Step') { $tampered.Steps[5].Operation = 'EnsureClaudeDesktop' }
            else { $tampered.Steps[2].OperationUseStateKeySha256 = ('9' * 64) }
            $tampered.PlanId = Get-CddsiInstallPlanBindingToken -Plan $tampered
            (Test-CddsiInstallPlan -Plan $tampered -StageManifest $context.Manifest `
                -OperationGrant $context.Grant -AuthorizationSession $context.Session `
                -WorkflowSessionState $context.Workflow) | Should -BeFalse
        }
        $other = New-CddsiSyntheticOrchestratorContext -RunId '20000000-0000-4000-8000-000000000902'
        (Test-CddsiInstallPlan -Plan $context.Plan -StageManifest $other.Manifest `
            -OperationGrant $other.Grant -AuthorizationSession $other.Session `
            -WorkflowSessionState $other.Workflow) | Should -BeFalse
    }
}

Describe 'receipt-bound orchestrator trace v2' {
    It 'accepts only committed CLAIMED starts and matching terminal receipts' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $events = Copy-CddsiSyntheticObject -InputObject $script:CanonicalSuccessfulTraceEvents
        $trace = Resolve-CddsiOrchestratorTrace -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -Events $events
        $trace.State | Should -BeExactly 'SUCCEEDED'
        @($trace.CompletedStepIds).Count | Should -Be 13
        @($trace.AffectedStepIds).Count | Should -Be 9
        $trace.CompensationPlan.Status | Should -BeExactly 'NONE'
        $trace.EventsProcessed | Should -Be 26
    }

    It 'stops at the primary failure and derives affected steps only from invoked mutation receipts' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $events = Copy-CddsiSyntheticObject -InputObject $script:CanonicalEnsureGitFailureTraceEvents
        $trace = Resolve-CddsiOrchestratorTrace -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $events
        $trace.State | Should -BeExactly 'FAILED'
        @($trace.CompletedStepIds) -join '|' | Should -BeExactly 'preflight|fixed_target|acquire_artifacts|verify_artifacts|ensure_desktop'
        @($trace.AffectedStepIds) -join '|' | Should -BeExactly 'acquire_artifacts|ensure_desktop|ensure_git'
        @($trace.CompletedStepIds) -contains 'prepare_cowork' | Should -BeFalse
        $trace.PrimaryFailureReceipt.ProviderInvocationOccurred | Should -BeTrue
        $trace.CompensationPlan.Status | Should -BeExactly 'REQUIRED'
        @($trace.CompensationPlan.Compensations.Operation) -join '|' | Should -BeExactly 'RestoreGitState|RestoreClaudeDesktopState|RemoveAcquiredArtifacts'
    }

    It 'rejects cross-step receipt replay wrong time forged evidence and secret-bearing errors' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $events = Copy-CddsiSyntheticObject -InputObject $script:CanonicalSuccessfulTraceEvents

        $crossStep = Copy-CddsiSyntheticObject -InputObject $events
        $crossStep[6].OperationUseReceipt = $crossStep[4].OperationUseReceipt
        $crossStep[6].ProviderEvidenceDigest = Get-CddsiTraceEventEvidenceDigest -Plan $context.Plan -Event $crossStep[6]
        { Resolve-CddsiOrchestratorTrace -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events $crossStep } | Should -Throw

        $replay = Copy-CddsiSyntheticObject -InputObject $events
        $replay[8].OperationUseReceipt = $replay[4].OperationUseReceipt
        $replay[8].ProviderEvidenceDigest = Get-CddsiTraceEventEvidenceDigest -Plan $context.Plan -Event $replay[8]
        { Resolve-CddsiOrchestratorTrace -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events $replay } | Should -Throw

        $wrongTime = Copy-CddsiSyntheticObject -InputObject $events
        $wrongTime[5].OccurredAtUtc = $wrongTime[4].OccurredAtUtc
        { Resolve-CddsiOrchestratorTrace -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events $wrongTime } | Should -Throw

        $forged = Copy-CddsiSyntheticObject -InputObject $events
        $forged[5].ProviderEvidenceDigest = ('9' * 64)
        { Resolve-CddsiOrchestratorTrace -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events $forged } | Should -Throw

        $alternateClaim = New-CddsiSyntheticClaimedReceipt -Context $context `
            -Operation AcquireArtifacts -ClaimedAtUtc '2030-01-01T00:07:30Z'
        $alternateTerminal = Complete-CddsiSyntheticReceipt -Context $context `
            -ClaimedReceipt $alternateClaim -OccurredAtUtc '2030-01-01T00:08:00Z'
        $brokenLineage = Copy-CddsiSyntheticObject -InputObject $events
        $brokenLineage[5].OperationUseReceipt = $alternateTerminal
        $brokenLineage[5].ProviderEvidenceDigest = $alternateTerminal.ProviderEvidenceDigest
        { Resolve-CddsiOrchestratorTrace -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events $brokenLineage } | Should -Throw

        $secretEvents = @(
            (New-CddsiSyntheticTraceEvent -Context $context -Sequence 1 -StepId preflight `
                -Outcome STARTED -MutationState NONE -OccurredAtUtc (Get-CddsiSyntheticUtc -Minute 3)),
            (New-CddsiSyntheticTraceEvent -Context $context -Sequence 2 -StepId preflight `
                -Outcome FAILED -MutationState NONE -OccurredAtUtc (Get-CddsiSyntheticUtc -Minute 4) `
                -ErrorCode ('s' + 'k-' + ('x' * 30)))
        )
        { Resolve-CddsiOrchestratorTrace -Plan $context.Plan -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events $secretEvents } | Should -Throw
    }

    It 'rejects an attacker-rehashed plan before processing any event' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $tampered = Copy-CddsiSyntheticObject -InputObject $context.Plan
        $tampered.Steps[2].Operation = 'EnsureGit'
        $tampered.PlanId = Get-CddsiInstallPlanBindingToken -Plan $tampered
        { Resolve-CddsiOrchestratorTrace -Plan $tampered -StageManifest $context.Manifest `
            -OperationGrant $context.Grant -AuthorizationSession $context.Session `
            -WorkflowSessionState $context.Workflow -Events @() } | Should -Throw
    }
}

Describe 'receipt-bound compensation reducer v2' {
    It 'requires strict reverse proof and reports FULL only after all independent receipts complete' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $trace = Resolve-CddsiOrchestratorTrace -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -Events (Copy-CddsiSyntheticObject -InputObject $script:CanonicalEnsureGitFailureTraceEvents)
        $compensation = $trace.CompensationPlan
        (Test-CddsiCompensationPlan -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow) | Should -BeTrue
        @($compensation.Compensations.SourceStepId) -join '|' | Should -BeExactly 'ensure_git|ensure_desktop|acquire_artifacts'

        $notProven = Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events @()
        $notProven.Status | Should -BeExactly 'REQUIRED_NOT_PROVEN'

        $events = New-CddsiSyntheticCompensationEvents -Context $context -CompensationPlan $compensation
        $full = Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $events
        $full.Status | Should -BeExactly 'FULL'
        @($full.RestoredSourceStepIds) -join '|' | Should -BeExactly 'ensure_git|ensure_desktop|acquire_artifacts'
        foreach ($index in 0, 2, 4) {
            $events[$index].OperationUseReceipt.OperationUseId | Should -Not -BeExactly $compensation.Compensations[$index / 2].SourceOperationUseId
        }
    }

    It 'reports FAILED on a proved compensation failure and never calls it FULL' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $trace = Resolve-CddsiOrchestratorTrace -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -Events (Copy-CddsiSyntheticObject -InputObject $script:CanonicalEnsureGitFailureTraceEvents)
        $events = New-CddsiSyntheticCompensationEvents -Context $context `
            -CompensationPlan $trace.CompensationPlan -FailureSourceStepId ensure_git
        $result = Resolve-CddsiCompensationTrace -CompensationPlan $trace.CompensationPlan -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $events
        $result.Status | Should -BeExactly 'FAILED'
        $result.ErrorCode | Should -BeExactly 'SYNTHETIC_COMPENSATION_FAILED'
    }

    It 'rejects out-of-order missing-proof early replay and forged compensation evidence' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $trace = Resolve-CddsiOrchestratorTrace -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -Events (Copy-CddsiSyntheticObject -InputObject $script:CanonicalEnsureGitFailureTraceEvents)
        $compensation = $trace.CompensationPlan
        $events = New-CddsiSyntheticCompensationEvents -Context $context -CompensationPlan $compensation

        $partial = Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events @($events[0], $events[1])
        $partial.Status | Should -BeExactly 'REQUIRED_NOT_PROVEN'
        $partial.CurrentSourceStepId | Should -BeExactly 'ensure_desktop'

        $outOfOrder = Copy-CddsiSyntheticObject -InputObject $events
        $outOfOrder[0].SourceStepId = $outOfOrder[2].SourceStepId
        $outOfOrder[0].Operation = $outOfOrder[2].Operation
        $outOfOrder[0].OperationUseReceipt = $outOfOrder[2].OperationUseReceipt
        $outOfOrder[0].ProviderEvidenceDigest = Get-CddsiCompensationEventEvidenceDigest `
            -CompensationPlan $compensation -Event $outOfOrder[0]
        { Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $outOfOrder } | Should -Throw

        $early = New-CddsiSyntheticCompensationEvents -Context $context `
            -CompensationPlan $compensation -StartMinute 13
        { Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $early } | Should -Throw

        $replay = Copy-CddsiSyntheticObject -InputObject $events
        $replay[2].OperationUseReceipt = $replay[0].OperationUseReceipt
        $replay[2].ProviderEvidenceDigest = Get-CddsiCompensationEventEvidenceDigest `
            -CompensationPlan $compensation -Event $replay[2]
        { Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $replay } | Should -Throw

        $forged = Copy-CddsiSyntheticObject -InputObject $events
        $forged[1].ProviderEvidenceDigest = ('9' * 64)
        { Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow -Events $forged } | Should -Throw

        $alternateClaim = New-CddsiSyntheticClaimedReceipt -Context $context `
            -Operation $compensation.Compensations[0].Operation -ClaimedAtUtc '2030-01-01T00:20:30Z'
        $alternateTerminal = Complete-CddsiSyntheticReceipt -Context $context `
            -ClaimedReceipt $alternateClaim -OccurredAtUtc '2030-01-01T00:21:00Z'
        $brokenLineage = Copy-CddsiSyntheticObject -InputObject $events
        $brokenLineage[1].OperationUseReceipt = $alternateTerminal
        $brokenLineage[1].ProviderEvidenceDigest = $alternateTerminal.ProviderEvidenceDigest
        { Resolve-CddsiCompensationTrace -CompensationPlan $compensation -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -Events $brokenLineage } | Should -Throw
    }

    It 'rejects rehashed primary failure and PlanId drift in a compensation plan' {
        $context = Copy-CddsiSyntheticObject -InputObject $script:CanonicalOrchestratorContext
        $trace = Resolve-CddsiOrchestratorTrace -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow `
            -Events (Copy-CddsiSyntheticObject -InputObject $script:CanonicalEnsureGitFailureTraceEvents)

        $primary = Copy-CddsiSyntheticObject -InputObject $trace.CompensationPlan
        $primary.PrimaryFailureReceiptBindingToken = ('9' * 64)
        $primary.CompensationPlanId = Get-CddsiCompensationPlanBindingToken -CompensationPlan $primary
        (Test-CddsiCompensationPlan -CompensationPlan $primary -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow) | Should -BeFalse

        $planDrift = Copy-CddsiSyntheticObject -InputObject $trace.CompensationPlan
        $planDrift.PlanId = ('9' * 64)
        $planDrift.CompensationPlanId = Get-CddsiCompensationPlanBindingToken -CompensationPlan $planDrift
        (Test-CddsiCompensationPlan -CompensationPlan $planDrift -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow) | Should -BeFalse

        $unrunClaim = New-CddsiSyntheticClaimedReceipt -Context $context `
            -Operation WriteManagedPolicy -ClaimedAtUtc '2030-01-01T00:12:30Z'
        $unrunReceipt = Complete-CddsiSyntheticReceipt -Context $context `
            -ClaimedReceipt $unrunClaim -OccurredAtUtc '2030-01-01T00:13:00Z'
        $unrun = Copy-CddsiSyntheticObject -InputObject $trace.CompensationPlan
        $unrun.Compensations[0].SourceStepId = 'write_policy'
        $unrun.Compensations[0].SourceOperation = 'WriteManagedPolicy'
        $unrun.Compensations[0].SourceOperationUseId = $unrunReceipt.OperationUseId
        $unrun.Compensations[0].SourceReceiptBindingToken = $unrunReceipt.ReceiptBindingToken
        $unrun.Compensations[0].SourceOperationUseReceipt = $unrunReceipt
        $unrun.Compensations[0].Operation = 'RestoreManagedPolicy'
        $unrun.Compensations[0].OperationUseStateKeySha256 = @(
            $context.Plan.Steps | Where-Object Id -CEQ 'write_policy'
        )[0].CompensationUseStateKeySha256
        $unrun.CompensationPlanId = Get-CddsiCompensationPlanBindingToken -CompensationPlan $unrun
        (Test-CddsiCompensationPlan -CompensationPlan $unrun -Plan $context.Plan `
            -StageManifest $context.Manifest -OperationGrant $context.Grant `
            -AuthorizationSession $context.Session -WorkflowSessionState $context.Workflow) | Should -BeFalse
    }
}

Describe 'orchestrator isolation' {
    It 'contains no provider dispatch host I/O or private receipt validator' {
        foreach ($name in @(
            'New-CddsiInstallPlan', 'Test-CddsiInstallPlan', 'Resolve-CddsiOrchestratorTrace',
            'New-CddsiCompensationPlan', 'Test-CddsiCompensationPlan', 'Resolve-CddsiCompensationTrace'
        )) {
            (Get-Command $name).Parameters.Keys -contains 'Mode' | Should -BeFalse
            (Get-Command $name).Parameters.Keys -contains 'ExecutionContext' | Should -BeFalse
        }
        $path = Join-Path $script:RepoRoot 'lib\orchestrator.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $source = [System.IO.File]::ReadAllText($path)
        $source | Should -Not -Match '(?i)\$env:|\[Environment\]::'
        $source | Should -Not -Match 'function\s+Test-Cddsi(?:Private|Local).*Receipt'
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() })
        foreach ($forbidden in @(
            'Get-Item', 'Test-Path', 'Get-ChildItem', 'Get-Content', 'Set-Content',
            'Invoke-WebRequest', 'Start-Process', 'Get-Process', 'Stop-Process',
            'Get-AppxPackage', 'Add-AppxPackage', 'Get-ItemProperty', 'Set-ItemProperty',
            'Enable-WindowsOptionalFeature', 'Get-Credential', 'New-Object'
        )) { $commands -ccontains $forbidden | Should -BeFalse }
    }
}
