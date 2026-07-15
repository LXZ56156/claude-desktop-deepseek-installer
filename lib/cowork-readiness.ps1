# cowork-readiness.ps1 - Synthetic Cowork capability observations and pure evaluators.
# Enabling Windows features or scheduling resume work is outside this stage.

function Test-CddsiCoworkServiceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        IdentityToken    = $null
        IdentityStatus   = 'Unknown'
        State            = 'Unknown'
        CapabilityStatus = 'UNKNOWN'
        ReasonCodes      = @('COWORK_SERVICE_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Service -Operation Inspect -ResourceToken '<SERVICE:COWORK>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectCoworkService' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'COWORK_SERVICE_PROVIDER_FAILED' -MessageSafe 'Synthetic Cowork service provider failed closed.' -Data $unknownData
    }

    if (
        -not (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'IdentityToken', 'IdentityStatus', 'State')) -or
        $observation.SchemaVersion -isnot [int] -or $observation.SchemaVersion -ne 1 -or
        $observation.IdentityToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $observation.IdentityToken) -or
        $observation.IdentityStatus -isnot [string] -or @('Trusted', 'Untrusted', 'Unknown') -cnotcontains $observation.IdentityStatus -or
        $observation.State -isnot [string] -or @('Running', 'Stopped', 'Missing', 'Unknown') -cnotcontains $observation.State
    ) {
        $unknownData.ReasonCodes = @('COWORK_SERVICE_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectCoworkService' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'COWORK_SERVICE_RESULT_INVALID' -MessageSafe 'Synthetic Cowork service result did not match the exact schema.' -Data $unknownData
    }

    $blockedReasons = @()
    $unknownReasons = @()
    if ($observation.State -in @('Stopped', 'Missing')) { $blockedReasons += ('COWORK_SERVICE_{0}' -f $observation.State.ToUpperInvariant()) }
    if ($observation.State -ceq 'Unknown') { $unknownReasons += 'COWORK_SERVICE_STATE_UNKNOWN' }
    if ($observation.IdentityStatus -ceq 'Untrusted') { $blockedReasons += 'COWORK_SERVICE_IDENTITY_UNTRUSTED' }
    if ($observation.IdentityStatus -ceq 'Unknown') { $unknownReasons += 'COWORK_SERVICE_IDENTITY_UNKNOWN' }
    if ($blockedReasons.Count -gt 0) {
        $capabilityStatus = 'BLOCKED'
        $reasonCodes = @($blockedReasons + $unknownReasons)
    }
    elseif ($unknownReasons.Count -gt 0) {
        $capabilityStatus = 'UNKNOWN'
        $reasonCodes = @($unknownReasons)
    }
    else {
        $capabilityStatus = 'READY'
        $reasonCodes = @('COWORK_SERVICE_READY')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        IdentityToken    = $observation.IdentityToken
        IdentityStatus   = $observation.IdentityStatus
        State            = $observation.State
        CapabilityStatus = $capabilityStatus
        ReasonCodes      = @($reasonCodes)
    }
    return New-CddsiOperationResult -Operation 'DetectCoworkService' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Cowork service observation completed.' -Data $data
}

function Get-CddsiCoworkReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$EnvironmentStatus,
        [Parameter(Mandatory = $true)]$DesktopStatus,
        [Parameter(Mandatory = $true)]$VirtualMachinePlatformStatus,
        [Parameter(Mandatory = $true)]$HardwareVirtualizationStatus,
        [Parameter(Mandatory = $true)]$ServiceStatus,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe'
    )

    $inputs = @(
        [pscustomobject]@{ Name = 'ENVIRONMENT'; Result = $EnvironmentStatus },
        [pscustomobject]@{ Name = 'DESKTOP'; Result = $DesktopStatus },
        [pscustomobject]@{ Name = 'VMP'; Result = $VirtualMachinePlatformStatus },
        [pscustomobject]@{ Name = 'HARDWARE_VIRTUALIZATION'; Result = $HardwareVirtualizationStatus },
        [pscustomobject]@{ Name = 'COWORK_SERVICE'; Result = $ServiceStatus }
    )
    $valid = $true
    foreach ($input in $inputs) {
        if (
            $null -eq $input.Result -or $null -eq $input.Result.Data -or
            $input.Result.Status -cne 'SUCCEEDED' -or
            $input.Result.Data.CapabilityStatus -isnot [string] -or
            @('READY', 'BLOCKED', 'PENDING_RESTART', 'UNKNOWN') -cnotcontains $input.Result.Data.CapabilityStatus
        ) {
            $valid = $false
            break
        }
    }
    if (
        $valid -and
        ($EnvironmentStatus.Data.IsAdministrator -isnot [bool])
    ) {
        $valid = $false
    }

    if (-not $valid) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion                 = 1
            CapabilityStatus              = 'UNKNOWN'
            Ready                         = $false
            BlockingReasons               = @('READINESS_INPUT_INVALID')
            EnvironmentStatus              = 'UNKNOWN'
            DesktopStatus                  = 'UNKNOWN'
            VirtualMachinePlatformStatus   = 'UNKNOWN'
            HardwareVirtualizationStatus   = 'UNKNOWN'
            ServiceStatus                  = 'UNKNOWN'
            AdministratorCapability        = 'UNKNOWN'
        }
        return New-CddsiOperationResult -Operation 'EvaluateCoworkReadiness' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'READINESS_INPUT_INVALID' -MessageSafe 'Cowork readiness inputs were incomplete or failed.' -Data $data
    }

    $reasons = @()
    foreach ($input in $inputs) {
        $status = $input.Result.Data.CapabilityStatus
        if ($status -ceq 'BLOCKED') { $reasons += ('{0}_BLOCKED' -f $input.Name) }
        if ($status -ceq 'UNKNOWN') { $reasons += ('{0}_UNKNOWN' -f $input.Name) }
        if ($status -ceq 'PENDING_RESTART') { $reasons += ('{0}_RESTART_REQUIRED' -f $input.Name) }
    }
    if (-not $EnvironmentStatus.Data.IsAdministrator) { $reasons += 'ADMINISTRATOR_REQUIRED' }

    $componentStatuses = @($inputs | ForEach-Object { $_.Result.Data.CapabilityStatus })
    if ($componentStatuses -ccontains 'BLOCKED' -or -not $EnvironmentStatus.Data.IsAdministrator) {
        $capabilityStatus = 'BLOCKED'
    }
    elseif ($componentStatuses -ccontains 'UNKNOWN') {
        $capabilityStatus = 'UNKNOWN'
    }
    elseif ($componentStatuses -ccontains 'PENDING_RESTART') {
        $capabilityStatus = 'PENDING_RESTART'
    }
    else {
        $capabilityStatus = 'READY'
        $reasons = @('COWORK_READY')
    }

    $data = [pscustomobject][ordered]@{
        SchemaVersion                 = 1
        CapabilityStatus              = $capabilityStatus
        Ready                         = ($capabilityStatus -ceq 'READY')
        BlockingReasons               = @($reasons)
        EnvironmentStatus              = $EnvironmentStatus.Data.CapabilityStatus
        DesktopStatus                  = $DesktopStatus.Data.CapabilityStatus
        VirtualMachinePlatformStatus   = $VirtualMachinePlatformStatus.Data.CapabilityStatus
        HardwareVirtualizationStatus   = $HardwareVirtualizationStatus.Data.CapabilityStatus
        ServiceStatus                  = $ServiceStatus.Data.CapabilityStatus
        AdministratorCapability        = if ($EnvironmentStatus.Data.IsAdministrator) { 'AVAILABLE' } else { 'UNAVAILABLE' }
    }
    $operationStatus = switch -CaseSensitive ($capabilityStatus) {
        'READY' { 'SUCCEEDED'; break }
        'PENDING_RESTART' { 'RESTART_REQUIRED'; break }
        default { 'ACTION_REQUIRED'; break }
    }
    $errorCode = if ($capabilityStatus -ceq 'READY') { '' } else { [string]$reasons[0] }
    return New-CddsiOperationResult -Operation 'EvaluateCoworkReadiness' -Status $operationStatus -Mode $Mode -ErrorCode $errorCode -MessageSafe 'Cowork readiness was derived only from structured synthetic observations.' -Data $data -RestartRequired:($capabilityStatus -ceq 'PENDING_RESTART')
}

function Resolve-CddsiEffectiveSurfaces {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RequestedSurfaces,
        [Parameter(Mandatory = $true)]$EnvironmentStatus,
        [Parameter(Mandatory = $true)]$DesktopStatus,
        [Parameter(Mandatory = $true)]$GitStatus,
        [Parameter(Mandatory = $true)]$CoworkStatus,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe'
    )

    $requested = @($RequestedSurfaces)
    if (($requested -join '|') -cne 'Chat|Code|Cowork') {
        throw 'RequestedSurfaces must remain exactly Chat, Code and Cowork.'
    }

    $inputs = @($EnvironmentStatus, $DesktopStatus, $GitStatus, $CoworkStatus)
    $valid = $true
    foreach ($input in $inputs) {
        if (
            $null -eq $input -or $null -eq $input.Data -or
            $input.Data.CapabilityStatus -isnot [string] -or
            @('READY', 'BLOCKED', 'PENDING_RESTART', 'UNKNOWN') -cnotcontains $input.Data.CapabilityStatus
        ) {
            $valid = $false
            break
        }
    }
    if (-not $valid) {
        $capabilities = @(
            [pscustomobject][ordered]@{ Surface = 'Chat'; CapabilityStatus = 'UNKNOWN'; ReasonCodes = @('SURFACE_INPUT_INVALID') },
            [pscustomobject][ordered]@{ Surface = 'Code'; CapabilityStatus = 'UNKNOWN'; ReasonCodes = @('SURFACE_INPUT_INVALID') },
            [pscustomobject][ordered]@{ Surface = 'Cowork'; CapabilityStatus = 'UNKNOWN'; ReasonCodes = @('SURFACE_INPUT_INVALID') }
        )
        $data = [pscustomobject][ordered]@{
            SchemaVersion          = 1
            RequestedSurfaces      = @($requested)
            EffectiveSurfaces      = @()
            TargetPreserved        = $true
            TargetSatisfied        = $false
            OverallCapabilityStatus = 'UNKNOWN'
            Capabilities           = @($capabilities)
        }
        return New-CddsiOperationResult -Operation 'ResolveEffectiveSurfaces' -Status 'FAILED' -Mode $Mode -ErrorCode 'SURFACE_INPUT_INVALID' -MessageSafe 'Surface readiness inputs were incomplete.' -Data $data
    }

    $chatInputs = @($EnvironmentStatus.Data.CapabilityStatus, $DesktopStatus.Data.CapabilityStatus)
    if ($chatInputs -ccontains 'BLOCKED') { $chatStatus = 'BLOCKED' }
    elseif ($chatInputs -ccontains 'UNKNOWN') { $chatStatus = 'UNKNOWN' }
    elseif ($chatInputs -ccontains 'PENDING_RESTART') { $chatStatus = 'PENDING_RESTART' }
    else { $chatStatus = 'READY' }

    $codeInputs = @($chatStatus, $GitStatus.Data.CapabilityStatus)
    if ($codeInputs -ccontains 'BLOCKED') { $codeStatus = 'BLOCKED' }
    elseif ($codeInputs -ccontains 'UNKNOWN') { $codeStatus = 'UNKNOWN' }
    elseif ($codeInputs -ccontains 'PENDING_RESTART') { $codeStatus = 'PENDING_RESTART' }
    else { $codeStatus = 'READY' }

    $coworkInputs = @($chatStatus, $CoworkStatus.Data.CapabilityStatus)
    if ($coworkInputs -ccontains 'BLOCKED') { $coworkSurfaceStatus = 'BLOCKED' }
    elseif ($coworkInputs -ccontains 'UNKNOWN') { $coworkSurfaceStatus = 'UNKNOWN' }
    elseif ($coworkInputs -ccontains 'PENDING_RESTART') { $coworkSurfaceStatus = 'PENDING_RESTART' }
    else { $coworkSurfaceStatus = 'READY' }

    $chatReasons = if ($chatStatus -ceq 'READY') { @('CHAT_READY') } else { @('ENVIRONMENT_OR_DESKTOP_NOT_READY') }
    $codeReasons = if ($codeStatus -ceq 'READY') { @('CODE_READY') } else { @('CHAT_OR_GIT_NOT_READY') }
    $coworkReasons = if ($coworkSurfaceStatus -ceq 'READY') { @('COWORK_READY') } else { @('CHAT_OR_COWORK_NOT_READY') }
    $capabilities = @(
        [pscustomobject][ordered]@{ Surface = 'Chat'; CapabilityStatus = $chatStatus; ReasonCodes = @($chatReasons) },
        [pscustomobject][ordered]@{ Surface = 'Code'; CapabilityStatus = $codeStatus; ReasonCodes = @($codeReasons) },
        [pscustomobject][ordered]@{ Surface = 'Cowork'; CapabilityStatus = $coworkSurfaceStatus; ReasonCodes = @($coworkReasons) }
    )
    $effective = @($capabilities | Where-Object CapabilityStatus -CEQ 'READY' | ForEach-Object { $_.Surface })
    $targetSatisfied = ($effective.Count -eq $requested.Count)
    $surfaceStatuses = @($capabilities | ForEach-Object { $_.CapabilityStatus })
    if ($targetSatisfied) {
        $overallCapabilityStatus = 'READY'
    }
    elseif ($surfaceStatuses -ccontains 'BLOCKED') {
        $overallCapabilityStatus = 'BLOCKED'
    }
    elseif ($surfaceStatuses -ccontains 'UNKNOWN') {
        $overallCapabilityStatus = 'UNKNOWN'
    }
    else {
        $overallCapabilityStatus = 'PENDING_RESTART'
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion           = 1
        RequestedSurfaces       = @($requested)
        EffectiveSurfaces       = @($effective)
        TargetPreserved         = $true
        TargetSatisfied         = $targetSatisfied
        OverallCapabilityStatus = $overallCapabilityStatus
        Capabilities            = @($capabilities)
    }
    $operationStatus = if ($targetSatisfied) {
        'SUCCEEDED'
    }
    elseif ($overallCapabilityStatus -ceq 'PENDING_RESTART') {
        'RESTART_REQUIRED'
    }
    else {
        'ACTION_REQUIRED'
    }
    $errorCode = if ($targetSatisfied) { '' } else { 'SURFACE_REQUIREMENTS_NOT_MET' }
    return New-CddsiOperationResult -Operation 'ResolveEffectiveSurfaces' -Status $operationStatus -Mode $Mode -ErrorCode $errorCode -MessageSafe 'Effective surfaces were derived without changing the fixed requested target.' -Data $data -RestartRequired:($operationStatus -ceq 'RESTART_REQUIRED')
}

function Get-CddsiCoworkBlockingReasons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Readiness
    )

    if ($null -eq $Readiness.Data -or $null -eq $Readiness.Data.BlockingReasons) {
        return @('READINESS_RESULT_INVALID')
    }
    return @($Readiness.Data.BlockingReasons)
}

function Resolve-CddsiCoworkFeatureChangeTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Transcript,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$PrepareInitialOperationUseState,
        [Parameter(Mandatory = $true)][AllowNull()]$PrepareTerminalOperationUseState,
        [Parameter(Mandatory = $true)][string]$NowUtc
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Transcript -Expected @('SchemaVersion', 'ContractVersion', 'UserDecision', 'Events')) -or
        ($Transcript.SchemaVersion -isnot [int] -and $Transcript.SchemaVersion -isnot [long]) -or [long]$Transcript.SchemaVersion -ne 3 -or
        $Transcript.ContractVersion -cne 'cddsi-cowork-prepare-transcript-v3' -or
        $Transcript.UserDecision -isnot [string] -or @('Continue', 'Cancel') -cnotcontains $Transcript.UserDecision -or
        -not (Test-CddsiUtcTimestampValue -Value $NowUtc)) { throw 'Cowork prepare transcript contract 无效。' }
    if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $PrepareInitialOperationUseState) -or
        $PrepareInitialOperationUseState.Operation -cne 'PrepareCowork' -or
        $PrepareInitialOperationUseState.ArtifactProfile -cnotin @('VmAcceptance', 'UserLive')) { throw 'PrepareCowork initial operation-use binding 无效。' }

    $events = @($Transcript.Events)
    if ($Transcript.UserDecision -ceq 'Cancel') {
        if ($PrepareInitialOperationUseState.State -cne 'AVAILABLE' -or $null -ne $PrepareTerminalOperationUseState -or $events.Count -ne 0) { throw '用户拒绝不得伪造 PrepareCowork invocation。' }
        return New-CddsiOperationResult -Operation 'ResolveCoworkFeatureChange' -Status 'CANCELLED' -Mode 'TestSafe' `
            -ErrorCode 'USER_CANCELLED' -MessageSafe '用户拒绝 Cowork feature 变更；未发生 mutation，也未创建 checkpoint。' `
            -Data ([pscustomobject][ordered]@{
                FeatureMutationState = 'UNCHANGED'; FeatureReadbackStatus = 'NOT_APPLICABLE'
                CheckpointRetentionRequired = $false; CheckpointDisposition = 'ABSENT'
                PrepareTerminalReceiptBindingToken = $null; ProviderEvidenceDigest = $null
                AutomaticRestartRequested = $false
            })
    }

    if ($PrepareInitialOperationUseState.State -cne 'CLAIMED' -or
        -not (Test-CddsiCommittedOperationUseReceipt -StageManifest $StageManifest -OperationGrant $OperationGrant `
            -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
            -OperationUseState $PrepareInitialOperationUseState -Operation 'PrepareCowork' `
            -OperationUseId $PrepareInitialOperationUseState.OperationUseId -ValidationTimeUtc $NowUtc)) { throw 'PrepareCowork committed receipt 无效。' }
    if ($events.Count -lt 1 -or $events.Count -gt 2) { throw 'Cowork prepare event count 无效。' }

    $expectedNames = @('feature_enable_no_restart', 'feature_readback')
    $previousTime = [DateTimeOffset]::Parse($PrepareInitialOperationUseState.ClaimedAtUtc)
    $expiresAt = [DateTimeOffset]::Parse($PrepareInitialOperationUseState.ExpiresAtUtc)
    $now = [DateTimeOffset]::Parse($NowUtc)
    $failureIndex = -1
    $mutationState = 'UNCHANGED'
    for ($index = 0; $index -lt $events.Count; $index++) {
        $event = $events[$index]
        if (-not (Test-CddsiExactPropertySet -InputObject $event -Expected @(
            'Sequence', 'Name', 'Outcome', 'MutationState', 'ReadbackStatus', 'RestartRequired',
            'OccurredAtUtc', 'OperationUseId', 'ProviderEvidenceSha256'
        ))) { throw 'Cowork prepare event schema 无效。' }
        if (($event.Sequence -isnot [int] -and $event.Sequence -isnot [long]) -or [long]$event.Sequence -ne ($index + 1) -or
            $event.Name -cne $expectedNames[$index] -or $event.Outcome -cnotin @('SUCCEEDED', 'FAILED') -or
            $event.MutationState -cnotin @('NONE', 'UNCHANGED', 'CHANGED', 'UNKNOWN') -or
            $event.ReadbackStatus -isnot [string] -or $event.RestartRequired -isnot [bool] -or
            $event.OperationUseId -cne $PrepareInitialOperationUseState.OperationUseId -or
            -not (Test-CddsiUtcTimestampValue -Value $event.OccurredAtUtc)) { throw 'Cowork prepare event type/binding 无效。' }
        $occurred = [DateTimeOffset]::Parse($event.OccurredAtUtc)
        if ($occurred -lt $previousTime -or $occurred -gt $now -or $occurred -ge $expiresAt) { throw 'Cowork prepare event time window 无效。' }
        $previousTime = $occurred
        $semanticsValid = if ($index -eq 0) {
            -not $event.RestartRequired -and (
                ($event.Outcome -ceq 'SUCCEEDED' -and $event.MutationState -cin @('UNCHANGED', 'CHANGED') -and $event.ReadbackStatus -ceq 'NO_RESTART_REQUESTED') -or
                ($event.Outcome -ceq 'FAILED' -and $event.MutationState -cin @('UNCHANGED', 'CHANGED', 'UNKNOWN') -and $event.ReadbackStatus -ceq 'UNKNOWN')
            )
        }
        else {
            $event.MutationState -ceq 'NONE' -and (
                ($event.Outcome -ceq 'SUCCEEDED' -and $event.ReadbackStatus -ceq 'ENABLED' -and -not $event.RestartRequired) -or
                ($event.Outcome -ceq 'SUCCEEDED' -and $event.ReadbackStatus -ceq 'ENABLED_PENDING_RESTART' -and $event.RestartRequired) -or
                ($event.Outcome -ceq 'FAILED' -and $event.ReadbackStatus -ceq 'UNKNOWN' -and -not $event.RestartRequired)
            )
        }
        if (-not $semanticsValid) { throw 'Cowork prepare event semantics 无效。' }
        $expectedEvidence = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-cowork-prepare-event-v3', $PrepareInitialOperationUseState.RunId,
            $PrepareInitialOperationUseState.ArtifactSha256, $PrepareInitialOperationUseState.SidecarSha256,
            $PrepareInitialOperationUseState.ContentDigest, $PrepareInitialOperationUseState.ArtifactProfile,
            $PrepareInitialOperationUseState.GrantId, $PrepareInitialOperationUseState.ClaimId,
            $PrepareInitialOperationUseState.WorkflowSessionStateKeySha256,
            $PrepareInitialOperationUseState.OperationUseId, [string]($index + 1), $event.Name,
            $event.Outcome, $event.MutationState, $event.ReadbackStatus,
            ([string]$event.RestartRequired).ToLowerInvariant(), $event.OccurredAtUtc
        ) -join '|')
        if ($event.ProviderEvidenceSha256 -cne $expectedEvidence) { throw 'Cowork prepare provider evidence 无法重算。' }
        if ($index -eq 0) { $mutationState = $event.MutationState }
        if ($event.Outcome -ceq 'FAILED') {
            $failureIndex = $index
            if ($events.Count -ne ($index + 1)) { throw 'Cowork prepare failure 后不得继续。' }
            break
        }
    }
    if ($failureIndex -lt 0 -and $events.Count -ne 2) { throw 'Cowork prepare transcript 没有终态 readback。' }
    $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text ((@($events | ForEach-Object ProviderEvidenceSha256)) -join '|')
    $terminalOutcome = if ($failureIndex -lt 0) { 'COMPLETED' } else { 'ABORTED' }
    if ($null -eq $PrepareTerminalOperationUseState -or
        -not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest -OperationGrant $OperationGrant `
            -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
            -OperationUseState $PrepareTerminalOperationUseState -Operation 'PrepareCowork' `
            -OperationUseId $PrepareInitialOperationUseState.OperationUseId -Outcome $terminalOutcome `
            -ExpectedProviderEvidenceDigest $providerDigest)) { throw 'PrepareCowork terminal receipt 无效。' }
    foreach ($name in @(
        'StateKeySha256', 'Stage', 'ArtifactProfile', 'RunId', 'ArtifactSha256', 'SidecarSha256',
        'ContentDigest', 'GrantId', 'Nonce', 'ClaimId', 'AuthorizationSessionRevision',
        'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision', 'ConfirmationId',
        'ConfirmationPromptDigest', 'ConfirmedAtUtc', 'ConfirmationConsumed', 'Operation',
        'OperationUseId', 'ClaimedAtUtc', 'ExpiresAtUtc', 'ProviderIdempotencyRequired'
    )) { if ($PrepareTerminalOperationUseState.$name -cne $PrepareInitialOperationUseState.$name) { throw 'PrepareCowork terminal receipt claim binding 漂移。' } }
    if ($PrepareTerminalOperationUseState.Revision -ne ($PrepareInitialOperationUseState.Revision + 1) -or
        $PrepareTerminalOperationUseState.OccurredAtUtc -cne $events[$events.Count - 1].OccurredAtUtc) { throw 'PrepareCowork terminal revision/time 无效。' }
    $expectedPrepareReason = if ($terminalOutcome -ceq 'COMPLETED') { '' } else { 'PROVIDER_FAILED' }
    if ($PrepareTerminalOperationUseState.TerminalReasonCode -cne $expectedPrepareReason) { throw 'PrepareCowork terminal reason 无效。' }

    $finalReadback = if ($events.Count -eq 2) { $events[1].ReadbackStatus } else { 'UNKNOWN' }
    $restartRequired = ($events.Count -eq 2 -and $events[1].Outcome -ceq 'SUCCEEDED' -and $events[1].RestartRequired)
    $retentionRequired = ($mutationState -cin @('CHANGED', 'UNKNOWN')) -and ($restartRequired -or $failureIndex -ge 0)
    $status = if ($failureIndex -ge 0) { 'FAILED' } elseif ($restartRequired) { 'RESTART_REQUIRED' } else { 'SUCCEEDED' }
    $errorCode = if ($failureIndex -ge 0) { 'COWORK_PREPARE_FAILED' } elseif ($restartRequired) { 'MANUAL_RESTART_REQUIRED' } else { '' }
    return New-CddsiOperationResult -Operation 'ResolveCoworkFeatureChange' -Status $status -Mode 'TestSafe' `
        -ErrorCode $errorCode -MessageSafe 'Cowork feature 结果已由 committed PrepareCowork receipt 重建。' `
        -RestartRequired:$restartRequired -Data ([pscustomobject][ordered]@{
            FeatureMutationState = $mutationState; FeatureReadbackStatus = $finalReadback
            CheckpointRetentionRequired = $retentionRequired
            CheckpointDisposition = $(if ($retentionRequired) { 'CREATE_REQUIRED' } else { 'ABSENT' })
            PrepareTerminalReceiptBindingToken = $PrepareTerminalOperationUseState.ReceiptBindingToken
            ProviderEvidenceDigest = $providerDigest; AutomaticRestartRequested = $false
        })
}

function New-CddsiCoworkCheckpointPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$PrepareTranscript,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$PrepareClaimedOperationUseState,
        [Parameter(Mandatory = $true)]$PrepareTerminalOperationUseState,
        [Parameter(Mandatory = $true)]$ResumeAvailableOperationUseState,
        [Parameter(Mandatory = $true)][long]$ExpectedStateRevision,
        [Parameter(Mandatory = $true)][string]$CheckpointId,
        [Parameter(Mandatory = $true)][string]$UpdatedAtUtc,
        [Parameter(Mandatory = $true)][string]$ExpiresAtUtc
    )

    $prepareResult = Resolve-CddsiCoworkFeatureChangeTranscript -Transcript $PrepareTranscript `
        -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState -PrepareInitialOperationUseState $PrepareClaimedOperationUseState `
        -PrepareTerminalOperationUseState $PrepareTerminalOperationUseState -NowUtc $UpdatedAtUtc
    if (-not $prepareResult.Data.CheckpointRetentionRequired -or $prepareResult.Data.CheckpointDisposition -cne 'CREATE_REQUIRED') { throw '只有已证明 mutation 的 PrepareCowork 结果才能创建 checkpoint。' }
    if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $ResumeAvailableOperationUseState) -or
        $ResumeAvailableOperationUseState.State -cne 'AVAILABLE' -or
        $ResumeAvailableOperationUseState.Operation -cne 'ResumeCowork') { throw 'ResumeCowork AVAILABLE receipt 无效。' }
    foreach ($name in @('Stage', 'ArtifactProfile', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'GrantId', 'Nonce', 'ClaimId', 'AuthorizationSessionRevision', 'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision', 'ExpiresAtUtc')) {
        if ($PrepareTerminalOperationUseState.$name -cne $ResumeAvailableOperationUseState.$name) { throw 'Prepare/Resume session binding 不一致。' }
    }
    $authorizationExpiry = @(
        [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc),
        [DateTimeOffset]::Parse($WorkflowSessionState.ExpiresAtUtc),
        [DateTimeOffset]::Parse($PrepareTerminalOperationUseState.ExpiresAtUtc),
        [DateTimeOffset]::Parse($ResumeAvailableOperationUseState.ExpiresAtUtc)
    ) | Sort-Object | Select-Object -First 1
    if (-not (Test-CddsiUtcTimestampValue -Value $ExpiresAtUtc) -or [DateTimeOffset]::Parse($ExpiresAtUtc) -gt $authorizationExpiry) { throw 'Checkpoint expiry 超出 authorization/session expiry。' }
    $checkpointState = Set-CddsiResumeCheckpoint -State $State -ExpectedStateRevision $ExpectedStateRevision `
        -CheckpointId $CheckpointId -Stage $ResumeAvailableOperationUseState.Stage `
        -ArtifactSha256 $ResumeAvailableOperationUseState.ArtifactSha256 `
        -SidecarSha256 $ResumeAvailableOperationUseState.SidecarSha256 `
        -ContentDigest $ResumeAvailableOperationUseState.ContentDigest -ArtifactProfile $ResumeAvailableOperationUseState.ArtifactProfile `
        -GrantId $ResumeAvailableOperationUseState.GrantId -ClaimId $ResumeAvailableOperationUseState.ClaimId `
        -WorkflowSessionStateKeySha256 $ResumeAvailableOperationUseState.WorkflowSessionStateKeySha256 `
        -PrepareOperationUseId $PrepareTerminalOperationUseState.OperationUseId `
        -PrepareTerminalState $PrepareTerminalOperationUseState.State `
        -PrepareTerminalReceiptBindingToken $PrepareTerminalOperationUseState.ReceiptBindingToken `
        -PrepareProviderEvidenceDigest $PrepareTerminalOperationUseState.ProviderEvidenceDigest `
        -PrepareOccurredAtUtc $PrepareTerminalOperationUseState.OccurredAtUtc `
        -ResumeAvailableStateKeySha256 $ResumeAvailableOperationUseState.StateKeySha256 `
        -ResumeAvailableReceiptBindingToken $ResumeAvailableOperationUseState.ReceiptBindingToken `
        -MutationState $prepareResult.Data.FeatureMutationState -UpdatedAtUtc $UpdatedAtUtc -ExpiresAtUtc $ExpiresAtUtc `
        -AuthorizationExpiresAtUtc $authorizationExpiry.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ')
    $checkpointDigest = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiJson -InputObject $checkpointState -Depth 40)
    return [pscustomobject][ordered]@{
        SchemaVersion = 3; ContractVersion = 'cddsi-cowork-checkpoint-plan-v3'
        PlanId = Get-CddsiSupplyChainTextBindingToken -Text (@('cddsi-cowork-checkpoint-plan-v3', $checkpointDigest, $PrepareTerminalOperationUseState.ReceiptBindingToken, $ResumeAvailableOperationUseState.ReceiptBindingToken) -join '|')
        CheckpointId = $CheckpointId; RunId = $checkpointState.runId
        StateRevisionBefore = $ExpectedStateRevision; StateRevisionAfter = $checkpointState.revision
        CheckpointRevision = $checkpointState.restart.checkpointRevision
        PrepareTerminalReceiptBindingToken = $PrepareTerminalOperationUseState.ReceiptBindingToken
        ResumeAvailableReceiptBindingToken = $ResumeAvailableOperationUseState.ReceiptBindingToken
        CheckpointStateSha256 = $checkpointDigest; CheckpointState = $checkpointState
        RequiredOrder = @('prepare_terminal_verified', 'checkpoint_write', 'checkpoint_readback', 'manual_restart_confirmation')
        AutomaticRestartAllowed = $false; RunOnceAllowed = $false; ScheduledTaskAllowed = $false
    }
}

function Test-CddsiResumeCheckpointEligibility {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$PrepareTerminalOperationUseState,
        [Parameter(Mandatory = $true)]$ResumeOperationUseState,
        [Parameter(Mandatory = $true)][string]$NowUtc
    )

    if (-not (Test-CddsiUtcTimestampValue -Value $NowUtc)) { throw 'NowUtc 无效。' }
    $checkpointId = if ($null -ne $State.restart) { $State.restart.checkpointId } else { $null }
    $stateRevision = if ($null -ne $State.revision) { $State.revision } else { $null }
    $checkpointRevision = if ($null -ne $State.restart) { $State.restart.checkpointRevision } else { $null }
    $attemptClaimId = if ($null -ne $State.restart) { $State.restart.attemptClaimId } else { $null }
    $eligible = $false
    $eligibilityStatus = 'CORRUPT'
    $reasonCode = 'CHECKPOINT_SCHEMA_INVALID'

    :eligibility do {
        if (-not (Test-CddsiStateSchema -State $State)) { break eligibility }
        if (-not $State.restart.required) {
            $eligibilityStatus = 'ABSENT'; $reasonCode = 'CHECKPOINT_NOT_PRESENT'
            break eligibility
        }
        $r = $State.restart
        $contextFields = @('Stage', 'ArtifactProfile', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'GrantId', 'ClaimId', 'WorkflowSessionStateKeySha256')
        $stateNames = @('stage', 'profile', 'ownerRunId', 'artifactSha256', 'sidecarSha256', 'contentDigest', 'grantId', 'claimId', 'workflowSessionStateKeySha256')
        for ($index = 0; $index -lt $contextFields.Count; $index++) {
            if ($ResumeOperationUseState.($contextFields[$index]) -cne $r.($stateNames[$index])) {
                $eligibilityStatus = 'CONTEXT_MISMATCH'; $reasonCode = 'CHECKPOINT_CONTEXT_MISMATCH'
                break eligibility
            }
        }
        if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest -OperationGrant $OperationGrant `
            -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
            -OperationUseState $PrepareTerminalOperationUseState -Operation 'PrepareCowork' `
            -OperationUseId $r.prepareOperationUseId -Outcome $r.prepareTerminalState `
            -ExpectedProviderEvidenceDigest $r.prepareProviderEvidenceDigest) -or
            $PrepareTerminalOperationUseState.ReceiptBindingToken -cne $r.prepareTerminalReceiptBindingToken) {
            $eligibilityStatus = 'RECEIPT_INVALID'; $reasonCode = 'PREPARE_RECEIPT_INVALID'
            break eligibility
        }
        $now = [DateTimeOffset]::Parse($NowUtc)
        if ($now -lt [DateTimeOffset]::Parse($r.updatedAtUtc)) {
            $eligibilityStatus = 'EARLY'; $reasonCode = 'CHECKPOINT_TIME_INVALID'
            break eligibility
        }
        if ($now -ge [DateTimeOffset]::Parse($r.expiresAtUtc)) {
            $eligibilityStatus = 'EXPIRED'; $reasonCode = 'CHECKPOINT_EXPIRED'
            break eligibility
        }
        $actualAuthorizationExpiry = @(
            [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc),
            [DateTimeOffset]::Parse($WorkflowSessionState.ExpiresAtUtc),
            [DateTimeOffset]::Parse($PrepareTerminalOperationUseState.ExpiresAtUtc),
            [DateTimeOffset]::Parse($ResumeOperationUseState.ExpiresAtUtc)
        ) | Sort-Object | Select-Object -First 1
        if ([DateTimeOffset]::Parse($r.expiresAtUtc) -gt $actualAuthorizationExpiry -or
            [DateTimeOffset]::Parse($r.authorizationExpiresAtUtc) -ne $actualAuthorizationExpiry) {
            $eligibilityStatus = 'CONTEXT_MISMATCH'; $reasonCode = 'CHECKPOINT_EXPIRY_BINDING_INVALID'
            break eligibility
        }
        if ($r.resumeOperationState -ceq 'AVAILABLE') {
            if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
                -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
                -OperationUseState $ResumeOperationUseState) -or $ResumeOperationUseState.State -cne 'AVAILABLE' -or
                $ResumeOperationUseState.Operation -cne 'ResumeCowork' -or
                $ResumeOperationUseState.StateKeySha256 -cne $r.resumeAvailableStateKeySha256 -or
                $ResumeOperationUseState.ReceiptBindingToken -cne $r.resumeAvailableReceiptBindingToken) {
                $eligibilityStatus = 'RECEIPT_INVALID'; $reasonCode = 'RESUME_AVAILABLE_RECEIPT_INVALID'
                break eligibility
            }
            $eligible = $true; $eligibilityStatus = 'READY'; $reasonCode = 'CHECKPOINT_READY'
            break eligibility
        }
        if ($r.resumeOperationState -ceq 'CLAIMED') {
            if (-not (Test-CddsiCommittedOperationUseReceipt -StageManifest $StageManifest -OperationGrant $OperationGrant `
                -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
                -OperationUseState $ResumeOperationUseState -Operation 'ResumeCowork' `
                -OperationUseId $r.resumeOperationUseId -ValidationTimeUtc $NowUtc) -or
                $ResumeOperationUseState.StateKeySha256 -cne $r.resumeAvailableStateKeySha256 -or
                $ResumeOperationUseState.ReceiptBindingToken -cne $r.resumeClaimedReceiptBindingToken) {
                $eligibilityStatus = 'RECEIPT_INVALID'; $reasonCode = 'RESUME_CLAIMED_RECEIPT_INVALID'
                break eligibility
            }
            $eligible = $true; $eligibilityStatus = 'CLAIMED_READY'; $reasonCode = 'CHECKPOINT_CLAIMED_READY'
            break eligibility
        }
        $eligibilityStatus = 'REPLAY'; $reasonCode = 'CHECKPOINT_TERMINAL_REPLAY'
    } while ($false)

    $binding = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-cowork-checkpoint-eligibility-v2', $eligible, $eligibilityStatus, $reasonCode,
        $checkpointId, $stateRevision, $checkpointRevision, $attemptClaimId, $NowUtc
    ) -join '|')
    return [pscustomobject][ordered]@{
        SchemaVersion = 2; ContractVersion = 'cddsi-cowork-checkpoint-eligibility-v2'
        Eligible = $eligible; Status = $eligibilityStatus; ReasonCode = $reasonCode; CheckpointId = $checkpointId
        StateRevision = $stateRevision; CheckpointRevision = $checkpointRevision
        AttemptClaimId = $attemptClaimId; EvaluatedAtUtc = $NowUtc; BindingSha256 = $binding
    }
}

function Resolve-CddsiCoworkResume {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$PrepareTerminalOperationUseState,
        [Parameter(Mandatory = $true)]$ResumeClaimedOperationUseState,
        [Parameter(Mandatory = $true)]$ResumeTerminalOperationUseState,
        [Parameter(Mandatory = $true)][string]$NowUtc,
        [Parameter(Mandatory = $true)][string]$UpdatedAtUtc,
        [Parameter(Mandatory = $true)][ValidateSet('Enabled', 'Disabled', 'PendingRestart', 'Unknown')][string]$FeatureState,
        [Parameter(Mandatory = $true)][ValidateSet('SUCCEEDED', 'FAILED', 'NOT_ATTEMPTED')][string]$CleanupOutcome
    )

    $eligibility = Test-CddsiResumeCheckpointEligibility -State $State -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -PrepareTerminalOperationUseState $PrepareTerminalOperationUseState `
        -ResumeOperationUseState $ResumeClaimedOperationUseState -NowUtc $NowUtc
    if (-not $eligibility.Eligible -or $eligibility.Status -cne 'CLAIMED_READY') {
        return New-CddsiOperationResult -Operation 'ResolveCoworkResume' -Status 'FAILED' -Mode 'TestSafe' `
            -ErrorCode $eligibility.ReasonCode -MessageSafe 'Checkpoint eligibility 无法从原始 state/stage receipt 重建。'
    }
    if (($FeatureState -ceq 'Enabled' -and $CleanupOutcome -ceq 'NOT_ATTEMPTED') -or
        ($FeatureState -cne 'Enabled' -and $CleanupOutcome -cne 'NOT_ATTEMPTED')) { throw 'Feature/Cleanup outcome mapping 无效。' }
    $terminalOutcome = if ($FeatureState -ceq 'Enabled' -and $CleanupOutcome -ceq 'SUCCEEDED') { 'COMPLETED' } else { 'ABORTED' }
    $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-cowork-resume-provider-v3', $State.restart.checkpointId, [string]$State.revision,
        [string]$State.restart.checkpointRevision, $State.restart.attemptClaimId,
        $State.restart.resumeOperationUseId, $FeatureState, $CleanupOutcome,
        $ResumeTerminalOperationUseState.OccurredAtUtc
    ) -join '|')
    if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $ResumeTerminalOperationUseState -Operation 'ResumeCowork' `
        -OperationUseId $State.restart.resumeOperationUseId -Outcome $terminalOutcome `
        -ExpectedProviderEvidenceDigest $providerDigest)) { throw 'ResumeCowork terminal cleanup receipt 无效。' }
    foreach ($name in @(
        'StateKeySha256', 'Stage', 'ArtifactProfile', 'RunId', 'ArtifactSha256', 'SidecarSha256',
        'ContentDigest', 'GrantId', 'Nonce', 'ClaimId', 'AuthorizationSessionRevision',
        'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision', 'ConfirmationId',
        'ConfirmationPromptDigest', 'ConfirmedAtUtc', 'ConfirmationConsumed', 'Operation',
        'OperationUseId', 'ClaimedAtUtc', 'ExpiresAtUtc', 'ProviderIdempotencyRequired'
    )) { if ($ResumeTerminalOperationUseState.$name -cne $ResumeClaimedOperationUseState.$name) { throw 'ResumeCowork terminal receipt claim binding 漂移。' } }
    if ($ResumeTerminalOperationUseState.Revision -ne ($ResumeClaimedOperationUseState.Revision + 1) -or
        -not (Test-CddsiUtcTimestampValue -Value $UpdatedAtUtc) -or
        [DateTimeOffset]::Parse($ResumeTerminalOperationUseState.OccurredAtUtc) -gt [DateTimeOffset]::Parse($NowUtc) -or
        [DateTimeOffset]::Parse($UpdatedAtUtc) -lt [DateTimeOffset]::Parse($ResumeTerminalOperationUseState.OccurredAtUtc)) { throw 'ResumeCowork terminal revision/time 无效。' }
    $expectedResumeReason = if ($terminalOutcome -ceq 'COMPLETED') { '' } elseif ($CleanupOutcome -ceq 'FAILED') { 'PROVIDER_FAILED' } else { 'WORKFLOW_ABORTED' }
    if ($ResumeTerminalOperationUseState.TerminalReasonCode -cne $expectedResumeReason) { throw 'ResumeCowork terminal reason 无效。' }
    $terminalState = Complete-CddsiResumeCheckpointAttempt -State $State `
        -ExpectedCheckpointId $State.restart.checkpointId -ExpectedStateRevision $State.revision `
        -ExpectedCheckpointRevision $State.restart.checkpointRevision -TerminalState $terminalOutcome `
        -TerminalReceiptBindingToken $ResumeTerminalOperationUseState.ReceiptBindingToken `
        -ProviderEvidenceDigest $providerDigest -OccurredAtUtc $ResumeTerminalOperationUseState.OccurredAtUtc `
        -UpdatedAtUtc $UpdatedAtUtc
    if ($terminalOutcome -ceq 'COMPLETED') {
        $cleared = Clear-CddsiResumeCheckpoint -State $terminalState -ExpectedCheckpointId $State.restart.checkpointId `
            -ExpectedStateRevision $terminalState.revision -ExpectedCheckpointRevision $terminalState.restart.checkpointRevision `
            -UpdatedAtUtc $UpdatedAtUtc
        return New-CddsiOperationResult -Operation 'ResolveCoworkResume' -Status 'SUCCEEDED' -Mode 'TestSafe' `
            -MessageSafe 'ResumeCowork terminal receipt 已证明 checkpoint cleanup 完成。' `
            -Data ([pscustomobject][ordered]@{
                CheckpointCleared = $true; CleanupStatus = 'COMPLETED_PROVEN'; ReevaluateCowork = $true
                TerminalReceiptBindingToken = $ResumeTerminalOperationUseState.ReceiptBindingToken
                ProposedState = $cleared
            })
    }
    $status = if ($CleanupOutcome -ceq 'FAILED' -or $FeatureState -ceq 'Unknown') { 'FAILED' } elseif ($FeatureState -ceq 'PendingRestart') { 'RESTART_REQUIRED' } else { 'ACTION_REQUIRED' }
    return New-CddsiOperationResult -Operation 'ResolveCoworkResume' -Status $status -Mode 'TestSafe' `
        -ErrorCode $(if ($CleanupOutcome -ceq 'FAILED') { 'CHECKPOINT_CLEANUP_FAILED' } else { 'COWORK_NOT_READY' }) `
        -MessageSafe 'ResumeCowork terminal receipt 未证明 cleanup 成功；checkpoint 诚实保留。' `
        -RestartRequired:($FeatureState -ceq 'PendingRestart') -Data ([pscustomobject][ordered]@{
            CheckpointCleared = $false
            CleanupStatus = $(if ($CleanupOutcome -ceq 'FAILED') { 'FAILED_PROVEN' } else { 'NOT_ATTEMPTED' })
            ReevaluateCowork = $false; TerminalReceiptBindingToken = $ResumeTerminalOperationUseState.ReceiptBindingToken
            ProposedState = $terminalState
        })
}

function Enable-CddsiVirtualMachinePlatform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges,
        [switch]$AcknowledgeRestart
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'EnableVirtualMachinePlatform' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'EnableVirtualMachinePlatform' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '不会启用 Windows 功能，也不会重启。' -PlannedChanges @('VirtualMachinePlatform') -Warnings @('即使未来实现，重启仍需独立确认。')
}
