# orchestrator.ps1 - Pure plan, execution trace and compensation reducers.
# This module never dispatches a provider and never performs host I/O.

function Get-CddsiInstallPlanStepDefinitions {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject][ordered]@{ Sequence = 1;  Id = 'preflight';           Operation = 'InspectReadiness';      RequiresGrant = $false; Mutation = $false; CompensationOperation = $null },
        [pscustomobject][ordered]@{ Sequence = 2;  Id = 'fixed_target';        Operation = 'ResolveFixedTarget';    RequiresGrant = $false; Mutation = $false; CompensationOperation = $null },
        [pscustomobject][ordered]@{ Sequence = 3;  Id = 'load_live_providers'; Operation = 'LoadLiveProviders';     RequiresGrant = $true;  Mutation = $false; CompensationOperation = $null },
        [pscustomobject][ordered]@{ Sequence = 4;  Id = 'acquire_artifacts';   Operation = 'AcquireArtifacts';      RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RemoveAcquiredArtifacts' },
        [pscustomobject][ordered]@{ Sequence = 5;  Id = 'verify_artifacts';    Operation = 'VerifyArtifacts';       RequiresGrant = $true;  Mutation = $false; CompensationOperation = $null },
        [pscustomobject][ordered]@{ Sequence = 6;  Id = 'ensure_desktop';      Operation = 'EnsureClaudeDesktop';   RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RestoreClaudeDesktopState' },
        [pscustomobject][ordered]@{ Sequence = 7;  Id = 'ensure_git';          Operation = 'EnsureGit';             RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RestoreGitState' },
        [pscustomobject][ordered]@{ Sequence = 8;  Id = 'prepare_cowork';      Operation = 'PrepareCowork';         RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RestoreCoworkState' },
        [pscustomobject][ordered]@{ Sequence = 9;  Id = 'persist_credential';  Operation = 'PersistCredential';     RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RestoreCredentialState' },
        [pscustomobject][ordered]@{ Sequence = 10; Id = 'backup_policy';       Operation = 'BackupManagedPolicy';   RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RemoveManagedPolicyBackup' },
        [pscustomobject][ordered]@{ Sequence = 11; Id = 'write_policy';        Operation = 'WriteManagedPolicy';    RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RestoreManagedPolicy' },
        [pscustomobject][ordered]@{ Sequence = 12; Id = 'restart_desktop';     Operation = 'RestartDesktop';        RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RestoreDesktopLifecycle' },
        [pscustomobject][ordered]@{ Sequence = 13; Id = 'acceptance';          Operation = 'InvokeAcceptance';      RequiresGrant = $true;  Mutation = $false; CompensationOperation = $null },
        [pscustomobject][ordered]@{ Sequence = 14; Id = 'report';              Operation = 'WriteReport';           RequiresGrant = $true;  Mutation = $true;  CompensationOperation = 'RemoveReport' }
    )
}

function Get-CddsiInstallPlanGrantedOperations {
    [CmdletBinding()]
    param()

    $steps = @(Get-CddsiInstallPlanStepDefinitions)
    $forward = @($steps | Where-Object RequiresGrant | ForEach-Object { $_.Operation })
    $compensation = @($steps | Sort-Object Sequence -Descending | Where-Object {
        $_.RequiresGrant -and $null -ne $_.CompensationOperation
    } | ForEach-Object { $_.CompensationOperation })
    return @($forward + $compensation)
}

function Get-CddsiInstallPlanBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Plan)

    $values = @(
        'cddsi-install-plan-binding-v3', $Plan.SchemaVersion, $Plan.ContractVersion,
        $Plan.RunId, $Plan.Stage, $Plan.ArtifactProfile, $Plan.ArtifactSha256,
        $Plan.SidecarSha256, $Plan.ContentDigest, $Plan.GrantId, $Plan.ClaimId,
        $Plan.AuthorizationSessionRevision, $Plan.WorkflowSessionStateKeySha256,
        $Plan.WorkflowSessionRevision, $Plan.WorkflowSessionReceiptBindingToken,
        $Plan.InstallScope, (@($Plan.RequestedSurfaces) -join '|')
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    foreach ($step in @($Plan.Steps)) {
        foreach ($value in @(
            $step.SchemaVersion, $step.Sequence, $step.Id, $step.Operation,
            $step.RequiresGrant, $step.Mutation, $step.CompensationOperation,
            $step.OperationUseStateKeySha256, $step.CompensationUseStateKeySha256
        )) {
            $lines += ConvertTo-CddsiStagePolicyBindingField -Value $value
        }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $Plan -Expected @(
            'SchemaVersion', 'ContractVersion', 'PlanId', 'RunId', 'Stage',
            'ArtifactProfile', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest',
            'GrantId', 'ClaimId', 'AuthorizationSessionRevision',
            'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision',
            'WorkflowSessionReceiptBindingToken', 'InstallScope', 'RequestedSurfaces', 'Steps'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $Plan.SchemaVersion) -or
            $Plan.ContractVersion -cne 'cddsi-install-plan-v3' -or
            $Plan.PlanId -isnot [string] -or $Plan.PlanId -notmatch '^[a-f0-9]{64}$' -or
            $Plan.InstallScope -cnotin @('PerUser', 'MachineWide') -or
            $Plan.RequestedSurfaces -isnot [System.Array] -or
            (@($Plan.RequestedSurfaces) -join '|') -cne 'Chat|Code|Cowork') { return $false }
        if (-not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
            -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
            -WorkflowSessionState $WorkflowSessionState) -or
            $WorkflowSessionState.State -cne 'CLAIMED' -or
            @('VmDevelopment', 'VmAcceptance', 'UserLive') -cnotcontains $StageManifest.Stage) { return $false }
        if ($Plan.RunId -cne $OperationGrant.RunId -or $Plan.Stage -cne $StageManifest.Stage -or
            $Plan.ArtifactProfile -cne $OperationGrant.ArtifactProfile -or
            $Plan.ArtifactSha256 -cne $OperationGrant.ArtifactSha256 -or
            $Plan.SidecarSha256 -cne $OperationGrant.SidecarSha256 -or
            $Plan.ContentDigest -cne $OperationGrant.ContentDigest -or
            $Plan.GrantId -cne $OperationGrant.GrantId -or
            $Plan.ClaimId -cne $AuthorizationSession.ClaimId -or
            $Plan.AuthorizationSessionRevision -ne $AuthorizationSession.Revision -or
            $Plan.WorkflowSessionStateKeySha256 -cne $WorkflowSessionState.StateKeySha256 -or
            $Plan.WorkflowSessionRevision -ne $WorkflowSessionState.Revision -or
            $Plan.WorkflowSessionReceiptBindingToken -cne $WorkflowSessionState.ReceiptBindingToken) { return $false }

        $expectedOperations = @(Get-CddsiInstallPlanGrantedOperations)
        if ((@($OperationGrant.AllowedOperations) -join '|') -cne ($expectedOperations -join '|')) { return $false }
        $definitions = @(Get-CddsiInstallPlanStepDefinitions)
        if ($Plan.Steps -isnot [System.Array] -or @($Plan.Steps).Count -ne $definitions.Count) { return $false }
        for ($index = 0; $index -lt $definitions.Count; $index++) {
            $step = @($Plan.Steps)[$index]
            $definition = $definitions[$index]
            if (-not (Test-CddsiExactPropertySet -InputObject $step -Expected @(
                'SchemaVersion', 'Sequence', 'Id', 'Operation', 'RequiresGrant', 'Mutation',
                'CompensationOperation', 'OperationUseStateKeySha256', 'CompensationUseStateKeySha256'
            )) -or -not (Test-CddsiSchemaVersionOne -Value $step.SchemaVersion) -or
                $step.Sequence -ne $definition.Sequence -or $step.Id -cne $definition.Id -or
                $step.Operation -cne $definition.Operation -or
                $step.RequiresGrant -ne $definition.RequiresGrant -or
                $step.Mutation -ne $definition.Mutation -or
                $step.CompensationOperation -cne $definition.CompensationOperation) { return $false }
            if ($step.RequiresGrant) {
                $expectedUse = New-CddsiOperationUseState -StageManifest $StageManifest `
                    -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                    -WorkflowSessionState $WorkflowSessionState -Operation $step.Operation
                if ($step.OperationUseStateKeySha256 -cne $expectedUse.StateKeySha256) { return $false }
            }
            elseif ($null -ne $step.OperationUseStateKeySha256) { return $false }
            if ($null -ne $step.CompensationOperation) {
                $expectedCompensation = New-CddsiOperationUseState -StageManifest $StageManifest `
                    -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                    -WorkflowSessionState $WorkflowSessionState -Operation $step.CompensationOperation
                if ($step.CompensationUseStateKeySha256 -cne $expectedCompensation.StateKeySha256) { return $false }
            }
            elseif ($null -ne $step.CompensationUseStateKeySha256) { return $false }
        }
        return ($Plan.PlanId -ceq (Get-CddsiInstallPlanBindingToken -Plan $Plan))
    }
    catch { return $false }
}

function New-CddsiInstallPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)][ValidateSet('PerUser', 'MachineWide', 'Unresolved')][string]$InstallScope,
        [Parameter(Mandatory = $true)][string]$RunId
    )

    if ($InstallScope -ceq 'Unresolved') {
        return New-CddsiOperationResult -Operation 'CreateInstallPlan' -Status 'ACTION_REQUIRED' `
            -ErrorCode 'MSIX_SCOPE_UNRESOLVED' -MessageSafe 'The unique MSIX scope is unresolved; no install plan was created.'
    }
    if (-not (Test-CddsiCanonicalUuidValue -Value $RunId) -or
        -not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
            -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
            -WorkflowSessionState $WorkflowSessionState) -or
        $WorkflowSessionState.State -cne 'CLAIMED' -or
        @('VmDevelopment', 'VmAcceptance', 'UserLive') -cnotcontains $StageManifest.Stage -or
        $OperationGrant.RunId -cne $RunId -or
        (@($OperationGrant.AllowedOperations) -join '|') -cne (@(Get-CddsiInstallPlanGrantedOperations) -join '|')) {
        return New-CddsiOperationResult -Operation 'CreateInstallPlan' -Status 'ACTION_REQUIRED' `
            -ErrorCode 'INSTALL_PLAN_BINDING_INVALID' -MessageSafe 'Install plan bindings failed closed.'
    }

    $steps = @()
    foreach ($definition in @(Get-CddsiInstallPlanStepDefinitions)) {
        $forwardKey = $null
        $compensationKey = $null
        if ($definition.RequiresGrant) {
            $forwardKey = (New-CddsiOperationUseState -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $WorkflowSessionState -Operation $definition.Operation).StateKeySha256
        }
        if ($null -ne $definition.CompensationOperation) {
            $compensationKey = (New-CddsiOperationUseState -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $WorkflowSessionState -Operation $definition.CompensationOperation).StateKeySha256
        }
        $steps += [pscustomobject][ordered]@{
            SchemaVersion = 1; Sequence = $definition.Sequence; Id = $definition.Id
            Operation = $definition.Operation; RequiresGrant = $definition.RequiresGrant
            Mutation = $definition.Mutation; CompensationOperation = $definition.CompensationOperation
            OperationUseStateKeySha256 = $forwardKey; CompensationUseStateKeySha256 = $compensationKey
        }
    }
    $plan = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-install-plan-v3'; PlanId = $null
        RunId = $RunId; Stage = $StageManifest.Stage; ArtifactProfile = $OperationGrant.ArtifactProfile
        ArtifactSha256 = $OperationGrant.ArtifactSha256; SidecarSha256 = $OperationGrant.SidecarSha256
        ContentDigest = $OperationGrant.ContentDigest; GrantId = $OperationGrant.GrantId
        ClaimId = $AuthorizationSession.ClaimId; AuthorizationSessionRevision = $AuthorizationSession.Revision
        WorkflowSessionStateKeySha256 = $WorkflowSessionState.StateKeySha256
        WorkflowSessionRevision = $WorkflowSessionState.Revision
        WorkflowSessionReceiptBindingToken = $WorkflowSessionState.ReceiptBindingToken
        InstallScope = $InstallScope; RequestedSurfaces = @('Chat', 'Code', 'Cowork'); Steps = @($steps)
    }
    $plan.PlanId = Get-CddsiInstallPlanBindingToken -Plan $plan
    if (-not (Test-CddsiInstallPlan -Plan $plan -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState)) {
        return New-CddsiOperationResult -Operation 'CreateInstallPlan' -Status 'ACTION_REQUIRED' `
            -ErrorCode 'INSTALL_PLAN_CONSTRUCTION_INVALID' -MessageSafe 'Install plan construction failed closed.'
    }
    return New-CddsiOperationResult -Operation 'CreateInstallPlan' -Status 'SUCCEEDED' `
        -MessageSafe 'The bound install plan was created without executing a provider.' -Data $plan
}

function Get-CddsiTraceEventEvidenceDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Event
    )

    $receiptToken = if ($null -eq $Event.OperationUseReceipt) { $null } else { $Event.OperationUseReceipt.ReceiptBindingToken }
    $values = @(
        'cddsi-orchestrator-event-evidence-v2', $Plan.PlanId, $Event.Sequence,
        $Event.StepId, $Event.Outcome, $Event.MutationState, $Event.OccurredAtUtc,
        $Event.ErrorCode, $receiptToken
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiOrchestratorSafeErrorCode {
    [CmdletBinding()]
    param([AllowNull()]$ErrorCode)

    if (-not (Test-CddsiSafeIdentifierValue -Value $ErrorCode -AllowNull -MaxLength 128)) {
        return $false
    }
    if ($null -eq $ErrorCode) { return $true }
    return (@(Find-CddsiPotentialSecrets -Content $ErrorCode -Source '<orchestrator-error-code>').Count -eq 0)
}

function Get-CddsiCompensationPlanBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$CompensationPlan)

    $values = @(
        'cddsi-compensation-plan-binding-v2', $CompensationPlan.SchemaVersion,
        $CompensationPlan.ContractVersion, $CompensationPlan.PlanId, $CompensationPlan.RunId,
        $CompensationPlan.GrantId, $CompensationPlan.ClaimId,
        $CompensationPlan.PrimaryFailureStepId, $CompensationPlan.PrimaryFailureOperationUseId,
        $CompensationPlan.PrimaryFailureReceiptBindingToken,
        $CompensationPlan.PrimaryFailureProviderEvidenceDigest,
        $CompensationPlan.PrimaryFailureOccurredAtUtc, $CompensationPlan.Status
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    foreach ($item in @($CompensationPlan.Compensations)) {
        foreach ($value in @(
            $item.SchemaVersion, $item.Sequence, $item.SourceStepId, $item.SourceOperation,
            $item.SourceOperationUseId, $item.SourceReceiptBindingToken,
            $item.Operation, $item.OperationUseStateKeySha256
        )) { $lines += ConvertTo-CddsiStagePolicyBindingField -Value $value }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiCompensationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CompensationPlan,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState
    )

    try {
        if (-not (Test-CddsiInstallPlan -Plan $Plan -StageManifest $StageManifest `
            -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
            -WorkflowSessionState $WorkflowSessionState) -or
            -not (Test-CddsiExactPropertySet -InputObject $CompensationPlan -Expected @(
                'SchemaVersion', 'ContractVersion', 'CompensationPlanId', 'PlanId', 'RunId',
                'GrantId', 'ClaimId', 'PrimaryFailureReceipt', 'PrimaryFailureStepId', 'PrimaryFailureOperationUseId',
                'PrimaryFailureReceiptBindingToken', 'PrimaryFailureProviderEvidenceDigest',
                'PrimaryFailureOccurredAtUtc', 'Status', 'Compensations'
            ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $CompensationPlan.SchemaVersion) -or
            $CompensationPlan.ContractVersion -cne 'cddsi-compensation-plan-v2' -or
            $CompensationPlan.CompensationPlanId -notmatch '^[a-f0-9]{64}$' -or
            $CompensationPlan.PlanId -cne $Plan.PlanId -or $CompensationPlan.RunId -cne $Plan.RunId -or
            $CompensationPlan.GrantId -cne $Plan.GrantId -or $CompensationPlan.ClaimId -cne $Plan.ClaimId -or
            $CompensationPlan.Status -cnotin @('NONE', 'REQUIRED') -or
            $CompensationPlan.Compensations -isnot [System.Array]) { return $false }
        $primaryValues = @(
            $CompensationPlan.PrimaryFailureReceipt,
            $CompensationPlan.PrimaryFailureStepId,
            $CompensationPlan.PrimaryFailureOperationUseId,
            $CompensationPlan.PrimaryFailureReceiptBindingToken,
            $CompensationPlan.PrimaryFailureProviderEvidenceDigest,
            $CompensationPlan.PrimaryFailureOccurredAtUtc
        )
        $hasPrimaryFailure = @($primaryValues | Where-Object { $null -ne $_ }).Count -gt 0
        if ($hasPrimaryFailure -and @($primaryValues | Where-Object { $null -eq $_ }).Count -gt 0) { return $false }
        $compensationCount = @($CompensationPlan.Compensations).Count
        if (($CompensationPlan.Status -ceq 'NONE' -and $compensationCount -ne 0) -or
            ($CompensationPlan.Status -ceq 'REQUIRED' -and $compensationCount -lt 1) -or
            (-not $hasPrimaryFailure -and $CompensationPlan.Status -cne 'NONE')) { return $false }
        if ($hasPrimaryFailure) {
            foreach ($hash in @($CompensationPlan.PrimaryFailureReceiptBindingToken, $CompensationPlan.PrimaryFailureProviderEvidenceDigest)) {
                if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
            }
            if (-not (Test-CddsiCanonicalUuidValue -Value $CompensationPlan.PrimaryFailureOperationUseId) -or
                $CompensationPlan.PrimaryFailureOccurredAtUtc -isnot [string] -or
                -not (Test-CddsiUtcTimestampValue -Value $CompensationPlan.PrimaryFailureOccurredAtUtc)) { return $false }
            $definitions = @(Get-CddsiInstallPlanStepDefinitions)
            $primaryStep = @($definitions | Where-Object { $_.Id -ceq $CompensationPlan.PrimaryFailureStepId })
            if ($primaryStep.Count -ne 1 -or -not $primaryStep[0].RequiresGrant -or
                -not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest `
                    -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                    -WorkflowSessionState $WorkflowSessionState `
                    -OperationUseState $CompensationPlan.PrimaryFailureReceipt `
                    -Operation $primaryStep[0].Operation `
                    -OperationUseId $CompensationPlan.PrimaryFailureOperationUseId `
                    -Outcome 'ABORTED' `
                    -ExpectedProviderEvidenceDigest $CompensationPlan.PrimaryFailureProviderEvidenceDigest) -or
                $CompensationPlan.PrimaryFailureReceipt.ReceiptBindingToken -cne $CompensationPlan.PrimaryFailureReceiptBindingToken -or
                $CompensationPlan.PrimaryFailureReceipt.OccurredAtUtc -cne $CompensationPlan.PrimaryFailureOccurredAtUtc) { return $false }
            $previousSourceSequence = [int]::MaxValue
            $seenSourceUseIds = @{}
            $seenSourceReceiptTokens = @{}
            for ($index = 0; $index -lt $compensationCount; $index++) {
                $item = @($CompensationPlan.Compensations)[$index]
                if (-not (Test-CddsiExactPropertySet -InputObject $item -Expected @(
                    'SchemaVersion', 'Sequence', 'SourceStepId', 'SourceOperation',
                    'SourceOperationUseId', 'SourceReceiptBindingToken', 'SourceOperationUseReceipt', 'Operation',
                    'OperationUseStateKeySha256'
                )) -or -not (Test-CddsiSchemaVersionOne -Value $item.SchemaVersion) -or
                    $item.Sequence -ne ($index + 1) -or
                    -not (Test-CddsiCanonicalUuidValue -Value $item.SourceOperationUseId) -or
                    $item.SourceReceiptBindingToken -notmatch '^[a-f0-9]{64}$' -or
                    $item.OperationUseStateKeySha256 -notmatch '^[a-f0-9]{64}$') { return $false }
                $source = @($definitions | Where-Object { $_.Id -ceq $item.SourceStepId })
                if ($source.Count -ne 1 -or -not $source[0].Mutation -or
                    $source[0].Operation -cne $item.SourceOperation -or
                    $source[0].CompensationOperation -cne $item.Operation -or
                    $source[0].Sequence -gt $primaryStep[0].Sequence -or
                    $source[0].Sequence -ge $previousSourceSequence -or
                    $seenSourceUseIds.ContainsKey($item.SourceOperationUseId) -or
                    $seenSourceReceiptTokens.ContainsKey($item.SourceReceiptBindingToken) -or
                    [DateTimeOffset]::Parse($item.SourceOperationUseReceipt.OccurredAtUtc) -gt
                        [DateTimeOffset]::Parse($CompensationPlan.PrimaryFailureOccurredAtUtc)) { return $false }
                $expectedSourceOutcome = if ($item.SourceStepId -ceq $CompensationPlan.PrimaryFailureStepId) {
                    'ABORTED'
                }
                else { 'COMPLETED' }
                if ($item.SourceOperationUseReceipt.State -cne $expectedSourceOutcome -or
                    -not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest `
                        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                        -WorkflowSessionState $WorkflowSessionState `
                        -OperationUseState $item.SourceOperationUseReceipt `
                        -Operation $item.SourceOperation `
                        -OperationUseId $item.SourceOperationUseId `
                        -Outcome $expectedSourceOutcome `
                        -ExpectedProviderEvidenceDigest $item.SourceOperationUseReceipt.ProviderEvidenceDigest) -or
                    $item.SourceOperationUseReceipt.ReceiptBindingToken -cne $item.SourceReceiptBindingToken -or
                    ($item.SourceStepId -ceq $CompensationPlan.PrimaryFailureStepId -and
                        ($item.SourceOperationUseId -cne $CompensationPlan.PrimaryFailureOperationUseId -or
                         $item.SourceReceiptBindingToken -cne $CompensationPlan.PrimaryFailureReceiptBindingToken))) { return $false }
                $planStep = @($Plan.Steps | Where-Object { $_.Id -ceq $item.SourceStepId })[0]
                if ($item.OperationUseStateKeySha256 -cne $planStep.CompensationUseStateKeySha256) { return $false }
                $seenSourceUseIds[$item.SourceOperationUseId] = $true
                $seenSourceReceiptTokens[$item.SourceReceiptBindingToken] = $true
                $previousSourceSequence = $source[0].Sequence
            }
        }
        return ($CompensationPlan.CompensationPlanId -ceq (Get-CddsiCompensationPlanBindingToken -CompensationPlan $CompensationPlan))
    }
    catch { return $false }
}

function New-CddsiCompensationPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [AllowNull()]$PrimaryFailureReceipt,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$AffectedOperationUseReceipts
    )

    if (-not (Test-CddsiInstallPlan -Plan $Plan -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState)) { throw 'Install plan is invalid.' }
    $affected = @($AffectedOperationUseReceipts)
    if ($null -eq $PrimaryFailureReceipt) {
        if ($affected.Count -ne 0) { throw 'Affected receipts require a primary failure receipt.' }
        $empty = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-compensation-plan-v2'; CompensationPlanId = $null
            PlanId = $Plan.PlanId; RunId = $Plan.RunId; GrantId = $Plan.GrantId; ClaimId = $Plan.ClaimId
            PrimaryFailureReceipt = $null; PrimaryFailureStepId = $null; PrimaryFailureOperationUseId = $null
            PrimaryFailureReceiptBindingToken = $null; PrimaryFailureProviderEvidenceDigest = $null
            PrimaryFailureOccurredAtUtc = $null; Status = 'NONE'; Compensations = @()
        }
        $empty.CompensationPlanId = Get-CddsiCompensationPlanBindingToken -CompensationPlan $empty
        return $empty
    }
    if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $PrimaryFailureReceipt) -or
        $PrimaryFailureReceipt.State -cne 'ABORTED' -or
        -not $PrimaryFailureReceipt.ProviderInvocationOccurred) { throw 'Primary failure receipt is invalid.' }
    $definitions = @(Get-CddsiInstallPlanStepDefinitions)
    $primaryStep = @($definitions | Where-Object { $_.Operation -ceq $PrimaryFailureReceipt.Operation })
    if ($primaryStep.Count -ne 1) { throw 'Primary failure receipt is not a forward plan operation.' }

    $receiptByStep = @{}
    foreach ($receipt in $affected) {
        if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
            -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
            -OperationUseState $receipt) -or $receipt.State -cnotin @('COMPLETED', 'ABORTED') -or
            -not $receipt.ProviderInvocationOccurred) { throw 'Affected operation receipt is invalid.' }
        $step = @($definitions | Where-Object { $_.Operation -ceq $receipt.Operation })
        if ($step.Count -ne 1 -or -not $step[0].Mutation -or $null -eq $step[0].CompensationOperation -or
            $receiptByStep.ContainsKey($step[0].Id)) { throw 'Affected receipt cannot be mapped uniquely.' }
        $receiptByStep[$step[0].Id] = $receipt
    }
    $items = @()
    foreach ($definition in @($definitions | Sort-Object Sequence -Descending)) {
        if (-not $receiptByStep.ContainsKey($definition.Id)) { continue }
        $receipt = $receiptByStep[$definition.Id]
        $planStep = @($Plan.Steps | Where-Object { $_.Id -ceq $definition.Id })[0]
        $items += [pscustomobject][ordered]@{
            SchemaVersion = 1; Sequence = $items.Count + 1; SourceStepId = $definition.Id
            SourceOperation = $definition.Operation; SourceOperationUseId = $receipt.OperationUseId
            SourceReceiptBindingToken = $receipt.ReceiptBindingToken
            SourceOperationUseReceipt = $receipt
            Operation = $definition.CompensationOperation
            OperationUseStateKeySha256 = $planStep.CompensationUseStateKeySha256
        }
    }
    $compensationPlan = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-compensation-plan-v2'; CompensationPlanId = $null
        PlanId = $Plan.PlanId; RunId = $Plan.RunId; GrantId = $Plan.GrantId; ClaimId = $Plan.ClaimId
        PrimaryFailureReceipt = $PrimaryFailureReceipt
        PrimaryFailureStepId = $primaryStep[0].Id
        PrimaryFailureOperationUseId = $PrimaryFailureReceipt.OperationUseId
        PrimaryFailureReceiptBindingToken = $PrimaryFailureReceipt.ReceiptBindingToken
        PrimaryFailureProviderEvidenceDigest = $PrimaryFailureReceipt.ProviderEvidenceDigest
        PrimaryFailureOccurredAtUtc = $PrimaryFailureReceipt.OccurredAtUtc
        Status = if ($items.Count -eq 0) { 'NONE' } else { 'REQUIRED' }
        Compensations = @($items)
    }
    $compensationPlan.CompensationPlanId = Get-CddsiCompensationPlanBindingToken -CompensationPlan $compensationPlan
    if (-not (Test-CddsiCompensationPlan -CompensationPlan $compensationPlan -Plan $Plan `
        -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState)) {
        throw 'Compensation plan construction failed closed.'
    }
    return $compensationPlan
}

function Resolve-CddsiOrchestratorTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Events
    )

    if (-not (Test-CddsiInstallPlan -Plan $Plan -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState)) { throw 'Install plan is invalid.' }
    $steps = @($Plan.Steps)
    $completed = [System.Collections.Generic.List[string]]::new()
    $affectedReceipts = [System.Collections.Generic.List[object]]::new()
    $affectedIds = [System.Collections.Generic.List[string]]::new()
    $usedStateKeys = @{}; $usedUseIds = @{}; $usedIdempotencyKeys = @{}
    $nextStep = 0; $activeStep = $null; $activeReceipt = $null
    $state = 'NOT_STARTED'; $terminal = $false; $errorCode = $null
    $primaryFailureReceipt = $null; $lastTime = $null; $lastOccurredAtUtc = $null

    for ($eventIndex = 0; $eventIndex -lt @($Events).Count; $eventIndex++) {
        $event = @($Events)[$eventIndex]
        if (-not (Test-CddsiExactPropertySet -InputObject $event -Expected @(
            'SchemaVersion', 'ContractVersion', 'Sequence', 'PlanId', 'StepId', 'Outcome',
            'MutationState', 'OccurredAtUtc', 'ProviderEvidenceDigest', 'OperationUseReceipt', 'ErrorCode'
        )) -or -not (Test-CddsiSchemaVersionOne -Value $event.SchemaVersion) -or
            $event.ContractVersion -cne 'cddsi-orchestrator-trace-event-v2' -or
            $event.Sequence -ne ($eventIndex + 1) -or $event.PlanId -cne $Plan.PlanId -or
            $event.Outcome -cnotin @('STARTED', 'SUCCEEDED', 'FAILED', 'CANCELLED') -or
            $event.MutationState -cnotin @('NONE', 'CHANGED', 'UNCHANGED', 'UNKNOWN') -or
            $event.ProviderEvidenceDigest -notmatch '^[a-f0-9]{64}$' -or
            -not (Test-CddsiOrchestratorSafeErrorCode -ErrorCode $event.ErrorCode) -or
            $event.OccurredAtUtc -isnot [string] -or -not (Test-CddsiUtcTimestampValue -Value $event.OccurredAtUtc)) {
            throw 'Orchestrator trace event schema is invalid.'
        }
        if ($terminal) { throw 'No event may follow a terminal trace outcome.' }
        $occurred = [DateTimeOffset]::Parse($event.OccurredAtUtc)
        if ($occurred -lt [DateTimeOffset]::Parse($AuthorizationSession.ClaimedAtUtc) -or
            $occurred -ge [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc) -or
            ($null -ne $lastTime -and $occurred -le $lastTime)) { throw 'Trace event time is invalid.' }
        $lastTime = $occurred
        $lastOccurredAtUtc = $event.OccurredAtUtc
        if ($nextStep -ge $steps.Count -or $event.StepId -cne $steps[$nextStep].Id) { throw 'Trace step order is invalid.' }
        $step = $steps[$nextStep]
        if ($event.Outcome -ceq 'STARTED') {
            if ($null -ne $activeStep -or $event.MutationState -cne 'NONE' -or $null -ne $event.ErrorCode) {
                throw 'STARTED transition is invalid.'
            }
            if ($step.RequiresGrant) {
                $receipt = $event.OperationUseReceipt
                if (-not (Test-CddsiCommittedOperationUseReceipt -StageManifest $StageManifest `
                    -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                    -WorkflowSessionState $WorkflowSessionState -OperationUseState $receipt `
                    -Operation $step.Operation -OperationUseId $receipt.OperationUseId `
                    -ValidationTimeUtc $event.OccurredAtUtc) -or
                    $receipt.StateKeySha256 -cne $step.OperationUseStateKeySha256 -or
                    $receipt.ClaimedAtUtc -cne $event.OccurredAtUtc -or
                    $usedStateKeys.ContainsKey($receipt.StateKeySha256) -or
                    $usedUseIds.ContainsKey($receipt.OperationUseId) -or
                    $usedIdempotencyKeys.ContainsKey($receipt.OperationUseId) -or
                    $event.ProviderEvidenceDigest -cne (Get-CddsiTraceEventEvidenceDigest -Plan $Plan -Event $event)) {
                    throw 'Authorized STARTED receipt is invalid or replayed.'
                }
                $usedStateKeys[$receipt.StateKeySha256] = $true
                $usedUseIds[$receipt.OperationUseId] = $true
                $activeReceipt = $receipt
            }
            else {
                if ($null -ne $event.OperationUseReceipt -or
                    $event.ProviderEvidenceDigest -cne (Get-CddsiTraceEventEvidenceDigest -Plan $Plan -Event $event)) {
                    throw 'Non-authorized STARTED evidence is invalid.'
                }
                $activeReceipt = $null
            }
            $activeStep = $step.Id; $state = 'RUNNING'; continue
        }

        if ($activeStep -cne $step.Id) { throw 'Terminal event has no matching STARTED event.' }
        if ($event.Outcome -ceq 'SUCCEEDED' -and $null -ne $event.ErrorCode) { throw 'Successful event cannot carry an error code.' }
        if ($event.Outcome -cne 'SUCCEEDED' -and $null -eq $event.ErrorCode) { throw 'Failed event requires a safe error code.' }
        if (-not $step.Mutation -and $event.MutationState -cne 'NONE') { throw 'Non-mutation step cannot report mutation.' }
        if ($step.Mutation -and $event.Outcome -ceq 'SUCCEEDED' -and $event.MutationState -cnotin @('CHANGED', 'UNCHANGED')) {
            throw 'Successful mutation step has invalid mutation state.'
        }
        if ($step.Mutation -and $event.Outcome -cne 'SUCCEEDED' -and $event.MutationState -cnotin @('CHANGED', 'UNCHANGED', 'UNKNOWN')) {
            throw 'Failed mutation step has invalid mutation state.'
        }
        $terminalReceipt = $null
        if ($step.RequiresGrant) {
            $terminalReceipt = $event.OperationUseReceipt
            $expectedOutcome = if ($event.Outcome -ceq 'SUCCEEDED') { 'COMPLETED' } else { 'ABORTED' }
            if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $WorkflowSessionState -OperationUseState $terminalReceipt `
                -Operation $step.Operation -OperationUseId $activeReceipt.OperationUseId `
                -Outcome $expectedOutcome -ExpectedProviderEvidenceDigest $event.ProviderEvidenceDigest) -or
                $terminalReceipt.StateKeySha256 -cne $activeReceipt.StateKeySha256 -or
                $terminalReceipt.ConfirmationId -cne $activeReceipt.ConfirmationId -or
                $terminalReceipt.ConfirmedAtUtc -cne $activeReceipt.ConfirmedAtUtc -or
                $terminalReceipt.ClaimedAtUtc -cne $activeReceipt.ClaimedAtUtc -or
                $terminalReceipt.Revision -ne ($activeReceipt.Revision + 1) -or
                $terminalReceipt.OccurredAtUtc -cne $event.OccurredAtUtc -or
                -not $terminalReceipt.ProviderInvocationOccurred -or
                $usedIdempotencyKeys.ContainsKey($terminalReceipt.IdempotencyKey) -or
                $usedUseIds.ContainsKey($terminalReceipt.IdempotencyKey) -or
                ($event.Outcome -ceq 'CANCELLED' -and $terminalReceipt.TerminalReasonCode -cne 'USER_CANCELLED') -or
                ($event.Outcome -ceq 'FAILED' -and $terminalReceipt.TerminalReasonCode -cnotin @('PROVIDER_FAILED', 'WORKFLOW_ABORTED'))) {
                throw 'Authorized terminal receipt is invalid or replayed.'
            }
            $usedIdempotencyKeys[$terminalReceipt.IdempotencyKey] = $true
        }
        else {
            if ($null -ne $event.OperationUseReceipt -or
                $event.ProviderEvidenceDigest -cne (Get-CddsiTraceEventEvidenceDigest -Plan $Plan -Event $event)) {
                throw 'Non-authorized terminal evidence is invalid.'
            }
        }
        if ($step.Mutation -and $null -ne $terminalReceipt -and
            $terminalReceipt.ProviderInvocationOccurred -and $event.MutationState -cin @('CHANGED', 'UNKNOWN')) {
            $affectedIds.Add($step.Id); $affectedReceipts.Add($terminalReceipt)
        }
        if ($event.Outcome -ceq 'SUCCEEDED') {
            $completed.Add($step.Id); $activeStep = $null; $activeReceipt = $null; $nextStep++
            $state = if ($nextStep -eq $steps.Count) { 'SUCCEEDED' } else { 'RUNNING' }
            continue
        }
        $state = $event.Outcome; $errorCode = $event.ErrorCode; $terminal = $true
        $primaryFailureReceipt = $terminalReceipt; $activeStep = $null; $activeReceipt = $null
    }
    $compensationPlan = if ($terminal -and $null -ne $primaryFailureReceipt) {
        New-CddsiCompensationPlan -Plan $Plan -StageManifest $StageManifest `
            -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
            -WorkflowSessionState $WorkflowSessionState -PrimaryFailureReceipt $primaryFailureReceipt `
            -AffectedOperationUseReceipts @($affectedReceipts)
    }
    else {
        New-CddsiCompensationPlan -Plan $Plan -StageManifest $StageManifest `
            -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
            -WorkflowSessionState $WorkflowSessionState -PrimaryFailureReceipt $null `
            -AffectedOperationUseReceipts @()
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-orchestrator-trace-v2'
        PlanId = $Plan.PlanId; RunId = $Plan.RunId; State = $state
        CurrentStepId = if ($state -ceq 'RUNNING') { if ($null -ne $activeStep) { $activeStep } elseif ($nextStep -lt $steps.Count) { $steps[$nextStep].Id } else { $null } } else { $null }
        CompletedStepIds = @($completed); AffectedStepIds = @($affectedIds)
        ErrorCode = $errorCode; PrimaryFailureReceipt = $primaryFailureReceipt
        CompensationPlan = $compensationPlan; EventsProcessed = @($Events).Count
        LastOccurredAtUtc = $lastOccurredAtUtc
    }
}

function Get-CddsiCompensationEventEvidenceDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CompensationPlan,
        [Parameter(Mandatory = $true)]$Event
    )

    $receiptToken = if ($null -eq $Event.OperationUseReceipt) { $null } else { $Event.OperationUseReceipt.ReceiptBindingToken }
    $values = @(
        'cddsi-compensation-event-evidence-v2', $CompensationPlan.PlanId,
        $CompensationPlan.CompensationPlanId, $Event.Sequence, $Event.SourceStepId,
        $Event.Operation, $Event.Outcome, $Event.OccurredAtUtc, $Event.ErrorCode, $receiptToken
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Resolve-CddsiCompensationTrace {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$CompensationPlan,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$Events
    )

    if (-not (Test-CddsiCompensationPlan -CompensationPlan $CompensationPlan -Plan $Plan `
        -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState)) {
        throw 'Compensation plan is invalid.'
    }
    if ($CompensationPlan.Status -ceq 'NONE') {
        if (@($Events).Count -ne 0) { throw 'A NONE compensation plan cannot accept events.' }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-compensation-trace-v2'
            PlanId = $Plan.PlanId; CompensationPlanId = $CompensationPlan.CompensationPlanId
            Status = 'FULL'; CurrentSourceStepId = $null; RestoredSourceStepIds = @()
            ErrorCode = $null; EventsProcessed = 0
        }
    }
    $items = @($CompensationPlan.Compensations)
    $restored = [System.Collections.Generic.List[string]]::new()
    $usedStateKeys = @{}; $usedUseIds = @{}; $usedIdempotencyKeys = @{}
    $sourceUseIds = @($items | ForEach-Object { $_.SourceOperationUseId })
    $sourceIdempotencyKeys = @($items | ForEach-Object { $_.SourceOperationUseReceipt.IdempotencyKey })
    $next = 0; $activeItem = $null; $activeReceipt = $null; $failed = $false
    $errorCode = $null; $lastTime = [DateTimeOffset]::Parse($CompensationPlan.PrimaryFailureOccurredAtUtc)
    for ($index = 0; $index -lt @($Events).Count; $index++) {
        $event = @($Events)[$index]
        if (-not (Test-CddsiExactPropertySet -InputObject $event -Expected @(
            'SchemaVersion', 'ContractVersion', 'Sequence', 'PlanId', 'CompensationPlanId',
            'SourceStepId', 'Operation', 'Outcome', 'OccurredAtUtc', 'ProviderEvidenceDigest',
            'OperationUseReceipt', 'ErrorCode'
        )) -or -not (Test-CddsiSchemaVersionOne -Value $event.SchemaVersion) -or
            $event.ContractVersion -cne 'cddsi-compensation-trace-event-v2' -or
            $event.Sequence -ne ($index + 1) -or $event.PlanId -cne $Plan.PlanId -or
            $event.CompensationPlanId -cne $CompensationPlan.CompensationPlanId -or
            $event.Outcome -cnotin @('STARTED', 'SUCCEEDED', 'FAILED') -or
            $event.ProviderEvidenceDigest -notmatch '^[a-f0-9]{64}$' -or
            -not (Test-CddsiOrchestratorSafeErrorCode -ErrorCode $event.ErrorCode) -or
            -not (Test-CddsiUtcTimestampValue -Value $event.OccurredAtUtc)) { throw 'Compensation event schema is invalid.' }
        if ($failed -or $next -ge $items.Count) { throw 'Compensation event follows a terminal state.' }
        $occurred = [DateTimeOffset]::Parse($event.OccurredAtUtc)
        if ($occurred -le $lastTime -or $occurred -ge [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc)) {
            throw 'Compensation event time is invalid.'
        }
        $lastTime = $occurred
        $item = $items[$next]
        if ($event.SourceStepId -cne $item.SourceStepId -or $event.Operation -cne $item.Operation) {
            throw 'Compensation order is invalid.'
        }
        if ($event.Outcome -ceq 'STARTED') {
            if ($null -ne $activeItem -or $null -ne $event.ErrorCode -or
                -not (Test-CddsiCommittedOperationUseReceipt -StageManifest $StageManifest `
                    -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                    -WorkflowSessionState $WorkflowSessionState -OperationUseState $event.OperationUseReceipt `
                    -Operation $item.Operation -OperationUseId $event.OperationUseReceipt.OperationUseId `
                    -ValidationTimeUtc $event.OccurredAtUtc) -or
                $event.OperationUseReceipt.StateKeySha256 -cne $item.OperationUseStateKeySha256 -or
                $event.OperationUseReceipt.ClaimedAtUtc -cne $event.OccurredAtUtc -or
                $sourceUseIds -ccontains $event.OperationUseReceipt.OperationUseId -or
                $sourceIdempotencyKeys -ccontains $event.OperationUseReceipt.OperationUseId -or
                $CompensationPlan.PrimaryFailureOperationUseId -ceq $event.OperationUseReceipt.OperationUseId -or
                $usedStateKeys.ContainsKey($event.OperationUseReceipt.StateKeySha256) -or
                $usedUseIds.ContainsKey($event.OperationUseReceipt.OperationUseId) -or
                $usedIdempotencyKeys.ContainsKey($event.OperationUseReceipt.OperationUseId) -or
                $event.ProviderEvidenceDigest -cne (Get-CddsiCompensationEventEvidenceDigest -CompensationPlan $CompensationPlan -Event $event)) {
                throw 'Compensation STARTED receipt is invalid, early or replayed.'
            }
            $usedStateKeys[$event.OperationUseReceipt.StateKeySha256] = $true
            $usedUseIds[$event.OperationUseReceipt.OperationUseId] = $true
            $activeItem = $item; $activeReceipt = $event.OperationUseReceipt; continue
        }
        if ($null -eq $activeItem -or
            ($event.Outcome -ceq 'SUCCEEDED' -and $null -ne $event.ErrorCode) -or
            ($event.Outcome -ceq 'FAILED' -and $null -eq $event.ErrorCode)) {
            throw 'Compensation terminal transition is invalid.'
        }
        $expectedOutcome = if ($event.Outcome -ceq 'SUCCEEDED') { 'COMPLETED' } else { 'ABORTED' }
        $receipt = $event.OperationUseReceipt
        if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest `
            -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
            -WorkflowSessionState $WorkflowSessionState -OperationUseState $receipt `
            -Operation $item.Operation -OperationUseId $activeReceipt.OperationUseId `
            -Outcome $expectedOutcome -ExpectedProviderEvidenceDigest $event.ProviderEvidenceDigest) -or
            $receipt.StateKeySha256 -cne $activeReceipt.StateKeySha256 -or
            $receipt.ConfirmationId -cne $activeReceipt.ConfirmationId -or
            $receipt.ConfirmedAtUtc -cne $activeReceipt.ConfirmedAtUtc -or
            $receipt.ClaimedAtUtc -cne $activeReceipt.ClaimedAtUtc -or
            $receipt.Revision -ne ($activeReceipt.Revision + 1) -or
            $receipt.OccurredAtUtc -cne $event.OccurredAtUtc -or
            -not $receipt.ProviderInvocationOccurred -or
            $usedIdempotencyKeys.ContainsKey($receipt.IdempotencyKey) -or
            $usedUseIds.ContainsKey($receipt.IdempotencyKey) -or
            $sourceUseIds -ccontains $receipt.IdempotencyKey -or
            $sourceIdempotencyKeys -ccontains $receipt.IdempotencyKey -or
            ($event.Outcome -ceq 'FAILED' -and $receipt.TerminalReasonCode -cne 'COMPENSATION_FAILED')) {
            throw 'Compensation terminal receipt is invalid or replayed.'
        }
        $usedIdempotencyKeys[$receipt.IdempotencyKey] = $true
        if ($event.Outcome -ceq 'FAILED') { $failed = $true; $errorCode = $event.ErrorCode; $activeItem = $null; $activeReceipt = $null; continue }
        $restored.Add($item.SourceStepId); $next++; $activeItem = $null; $activeReceipt = $null
    }
    $status = if ($failed) { 'FAILED' } elseif ($next -eq $items.Count) { 'FULL' } else { 'REQUIRED_NOT_PROVEN' }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-compensation-trace-v2'
        PlanId = $Plan.PlanId; CompensationPlanId = $CompensationPlan.CompensationPlanId
        Status = $status
        CurrentSourceStepId = if ($status -ceq 'REQUIRED_NOT_PROVEN') { if ($null -ne $activeItem) { $activeItem.SourceStepId } else { $items[$next].SourceStepId } } else { $null }
        RestoredSourceStepIds = @($restored); ErrorCode = $errorCode; EventsProcessed = @($Events).Count
    }
}
