# state.ps1 - Resume-state schema and pure compare-and-swap reducers.
# Dependencies: common.ps1. Stage receipt verification belongs to cowork-readiness.ps1.

function New-CddsiState {
    [CmdletBinding()]
    param(
        [string]$InstallerVersion = '0.1.0-dev',
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$ExecutionMode = 'TestSafe',
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$TimestampUtc
    )

    if (-not (Test-CddsiCanonicalUuidValue -Value $RunId)) { throw 'RunId 必须是 canonical UUID。' }
    if (-not (Test-CddsiUtcTimestampValue -Value $TimestampUtc)) { throw 'TimestampUtc 必须是调用方注入的 UTC 时间。' }
    if ($InstallerVersion -cnotmatch '^(?=.{1,64}$)(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') { throw 'InstallerVersion 必须是规范 SemVer。' }
    if (@('TestSafe', 'DryRun', 'Live') -cnotcontains $ExecutionMode) { throw 'ExecutionMode 大小写或值无效。' }

    return [pscustomobject][ordered]@{
        schemaVersion = 3
        installerVersion = $InstallerVersion
        runId = $RunId
        executionMode = $ExecutionMode
        revision = 1
        phase = 'bootstrap'
        status = 'initialized'
        completedSteps = @()
        pendingAction = $null
        restart = [pscustomobject][ordered]@{
            required = $false
            reasonCode = $null
            resumePhase = $null
            checkpointId = $null
            ownerRunId = $null
            stage = $null
            artifactSha256 = $null
            sidecarSha256 = $null
            contentDigest = $null
            profile = $null
            grantId = $null
            claimId = $null
            workflowSessionStateKeySha256 = $null
            prepareOperationUseId = $null
            prepareTerminalState = $null
            prepareTerminalReceiptBindingToken = $null
            prepareProviderEvidenceDigest = $null
            prepareOccurredAtUtc = $null
            resumeAvailableStateKeySha256 = $null
            resumeAvailableReceiptBindingToken = $null
            resumeOperationState = $null
            resumeOperationUseId = $null
            resumeClaimedReceiptBindingToken = $null
            resumeClaimedAtUtc = $null
            resumeTerminalReceiptBindingToken = $null
            resumeProviderEvidenceDigest = $null
            resumeOccurredAtUtc = $null
            attemptClaimId = $null
            checkpointRevision = 0
            attemptCount = 0
            mutationState = $null
            createdAtUtc = $null
            updatedAtUtc = $null
            expiresAtUtc = $null
            authorizationExpiresAtUtc = $null
        }
        desktop = [pscustomobject][ordered]@{
            installed = $false
            packageVersion = $null
            packageIdentity = $null
            signatureStatus = 'not_checked'
        }
        git = [pscustomobject][ordered]@{ installed = $false; version = $null; source = $null }
        cowork = [pscustomobject][ordered]@{
            virtualMachinePlatform = 'not_checked'
            hardwareVirtualization = 'not_checked'
            serviceStatus = 'not_checked'
            ready = $false
        }
        config = [pscustomobject][ordered]@{
            targetSource = 'HKCU_MANAGED_POLICY'
            contractVersion = $null
            ownershipStatus = 'not_evaluated'
            backupId = $null
        }
        deepseek = [pscustomobject][ordered]@{
            keyFormatValidated = $false
            remoteValidationStatus = 'not_run'
            lastErrorClass = $null
        }
        lastError = $null
        createdAtUtc = $TimestampUtc
        updatedAtUtc = $TimestampUtc
    }
}

function Test-CddsiStateSchema {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$State)

    try {
        $topLevel = @(
            'schemaVersion', 'installerVersion', 'runId', 'executionMode', 'revision', 'phase',
            'status', 'completedSteps', 'pendingAction', 'restart', 'desktop', 'git', 'cowork',
            'config', 'deepseek', 'lastError', 'createdAtUtc', 'updatedAtUtc'
        )
        $restartFields = @(
            'required', 'reasonCode', 'resumePhase', 'checkpointId', 'ownerRunId', 'stage',
            'artifactSha256', 'sidecarSha256', 'contentDigest', 'profile', 'grantId', 'claimId',
            'workflowSessionStateKeySha256', 'prepareOperationUseId', 'prepareTerminalState',
            'prepareTerminalReceiptBindingToken', 'prepareProviderEvidenceDigest', 'prepareOccurredAtUtc',
            'resumeAvailableStateKeySha256', 'resumeAvailableReceiptBindingToken', 'resumeOperationState',
            'resumeOperationUseId', 'resumeClaimedReceiptBindingToken', 'resumeClaimedAtUtc',
            'resumeTerminalReceiptBindingToken', 'resumeProviderEvidenceDigest', 'resumeOccurredAtUtc',
            'attemptClaimId', 'checkpointRevision', 'attemptCount', 'mutationState', 'createdAtUtc',
            'updatedAtUtc', 'expiresAtUtc', 'authorizationExpiresAtUtc'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $State -Expected $topLevel) -or
            -not (Test-CddsiExactPropertySet -InputObject $State.restart -Expected $restartFields) -or
            -not (Test-CddsiExactPropertySet -InputObject $State.desktop -Expected @('installed', 'packageVersion', 'packageIdentity', 'signatureStatus')) -or
            -not (Test-CddsiExactPropertySet -InputObject $State.git -Expected @('installed', 'version', 'source')) -or
            -not (Test-CddsiExactPropertySet -InputObject $State.cowork -Expected @('virtualMachinePlatform', 'hardwareVirtualization', 'serviceStatus', 'ready')) -or
            -not (Test-CddsiExactPropertySet -InputObject $State.config -Expected @('targetSource', 'contractVersion', 'ownershipStatus', 'backupId')) -or
            -not (Test-CddsiExactPropertySet -InputObject $State.deepseek -Expected @('keyFormatValidated', 'remoteValidationStatus', 'lastErrorClass'))) { return $false }
        if ($null -ne $State.lastError -and -not (Test-CddsiExactPropertySet -InputObject $State.lastError -Expected @('code', 'messageSafe'))) { return $false }
        if (($State.schemaVersion -isnot [int] -and $State.schemaVersion -isnot [long]) -or [long]$State.schemaVersion -ne 3 -or
            ($State.revision -isnot [int] -and $State.revision -isnot [long]) -or [long]$State.revision -lt 1) { return $false }
        if ($State.installerVersion -isnot [string] -or $State.installerVersion -cnotmatch '^(?=.{1,64}$)(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)\.(?:0|[1-9]\d*)(?:-(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*)(?:\.(?:0|[1-9]\d*|[0-9A-Za-z-]*[A-Za-z-][0-9A-Za-z-]*))*)?(?:\+[0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*)?$') { return $false }
        if (-not (Test-CddsiCanonicalUuidValue -Value $State.runId) -or
            $State.executionMode -isnot [string] -or @('TestSafe', 'DryRun', 'Live') -cnotcontains $State.executionMode) { return $false }
        if ($State.phase -isnot [string] -or @('bootstrap', 'diagnose', 'preflight', 'install', 'configure', 'restart_pending', 'resume', 'verify', 'repair', 'uninstall', 'cleanup', 'complete', 'failed', 'cancelled') -cnotcontains $State.phase) { return $false }
        if ($State.status -isnot [string] -or @('initialized', 'in_progress', 'action_required', 'restart_required', 'partial', 'succeeded', 'failed', 'cancelled') -cnotcontains $State.status) { return $false }
        if ($State.completedSteps -isnot [System.Array]) { return $false }
        $allowedSteps = @('preflight', 'fixed_target', 'acquire_artifacts', 'verify_artifacts', 'ensure_desktop', 'ensure_git', 'prepare_cowork', 'persist_credential', 'backup_policy', 'write_policy', 'restart_desktop', 'acceptance', 'report')
        $seenSteps = @{}
        foreach ($step in @($State.completedSteps)) {
            if ($step -isnot [string] -or $allowedSteps -cnotcontains $step -or $seenSteps.ContainsKey($step)) { return $false }
            $seenSteps[$step] = $true
        }
        if ($State.restart.required -isnot [bool] -or $State.desktop.installed -isnot [bool] -or
            $State.git.installed -isnot [bool] -or $State.cowork.ready -isnot [bool] -or
            $State.deepseek.keyFormatValidated -isnot [bool]) { return $false }

        if ($State.restart.required) {
            $r = $State.restart
            if ($r.reasonCode -cne 'vmp_change' -or $r.resumePhase -cne 'verify_cowork' -or
                $State.pendingAction -cne 'restart') { return $false }
            if ($r.checkpointId -isnot [string] -or $r.checkpointId -notmatch '^checkpoint-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { return $false }
            $checkpointUuid = $r.checkpointId.Substring('checkpoint-'.Length)
            foreach ($uuid in @($r.ownerRunId, $r.grantId, $r.claimId, $r.prepareOperationUseId, $checkpointUuid)) {
                if (-not (Test-CddsiCanonicalUuidValue -Value $uuid)) { return $false }
            }
            if ($r.ownerRunId -cne $State.runId -or $r.stage -isnot [string] -or
                @('VmAcceptance', 'UserLive') -cnotcontains $r.stage -or $r.profile -cne $r.stage) { return $false }
            foreach ($hash in @(
                $r.artifactSha256, $r.sidecarSha256, $r.contentDigest, $r.workflowSessionStateKeySha256,
                $r.prepareTerminalReceiptBindingToken, $r.prepareProviderEvidenceDigest,
                $r.resumeAvailableStateKeySha256, $r.resumeAvailableReceiptBindingToken
            )) { if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false } }
            if (@(@($r.artifactSha256, $r.sidecarSha256, $r.contentDigest) | Select-Object -Unique).Count -ne 3 -or
                $r.prepareTerminalState -cnotin @('COMPLETED', 'ABORTED') -or
                $r.mutationState -cnotin @('CHANGED', 'UNKNOWN')) { return $false }
            if (($r.checkpointRevision -isnot [int] -and $r.checkpointRevision -isnot [long]) -or
                [long]$r.checkpointRevision -lt 1 -or [long]$r.checkpointRevision -gt 3 -or
                ($r.attemptCount -isnot [int] -and $r.attemptCount -isnot [long]) -or
                [long]$r.attemptCount -lt 0 -or [long]$r.attemptCount -gt 1) { return $false }
            foreach ($time in @($r.prepareOccurredAtUtc, $r.createdAtUtc, $r.updatedAtUtc, $r.expiresAtUtc, $r.authorizationExpiresAtUtc)) {
                if (-not (Test-CddsiUtcTimestampValue -Value $time)) { return $false }
            }
            $created = [DateTimeOffset]::Parse($r.createdAtUtc)
            $updated = [DateTimeOffset]::Parse($r.updatedAtUtc)
            $expires = [DateTimeOffset]::Parse($r.expiresAtUtc)
            $authorizationExpires = [DateTimeOffset]::Parse($r.authorizationExpiresAtUtc)
            if ([DateTimeOffset]::Parse($r.prepareOccurredAtUtc) -gt $created -or $created -gt $updated -or
                $updated -ge $expires -or $expires -gt $authorizationExpires -or
                $State.updatedAtUtc -cne $r.updatedAtUtc) { return $false }

            switch -CaseSensitive ($r.resumeOperationState) {
                'AVAILABLE' {
                    if ([long]$r.checkpointRevision -ne 1 -or [long]$r.attemptCount -ne 0 -or
                        $null -ne $r.resumeOperationUseId -or $null -ne $r.resumeClaimedReceiptBindingToken -or
                        $null -ne $r.resumeClaimedAtUtc -or $null -ne $r.resumeTerminalReceiptBindingToken -or
                        $null -ne $r.resumeProviderEvidenceDigest -or $null -ne $r.resumeOccurredAtUtc -or
                        $null -ne $r.attemptClaimId) { return $false }
                    break
                }
                'CLAIMED' {
                    if ([long]$r.checkpointRevision -ne 2 -or [long]$r.attemptCount -ne 1 -or
                        -not (Test-CddsiCanonicalUuidValue -Value $r.resumeOperationUseId) -or
                        -not (Test-CddsiCanonicalUuidValue -Value $r.attemptClaimId) -or
                        $r.resumeClaimedReceiptBindingToken -isnot [string] -or $r.resumeClaimedReceiptBindingToken -notmatch '^[a-f0-9]{64}$' -or
                        -not (Test-CddsiUtcTimestampValue -Value $r.resumeClaimedAtUtc) -or
                        $null -ne $r.resumeTerminalReceiptBindingToken -or $null -ne $r.resumeProviderEvidenceDigest -or
                        $null -ne $r.resumeOccurredAtUtc) { return $false }
                    break
                }
                { $_ -in @('COMPLETED', 'ABORTED') } {
                    if ([long]$r.checkpointRevision -ne 3 -or [long]$r.attemptCount -ne 1 -or
                        -not (Test-CddsiCanonicalUuidValue -Value $r.resumeOperationUseId) -or
                        -not (Test-CddsiCanonicalUuidValue -Value $r.attemptClaimId) -or
                        $r.resumeClaimedReceiptBindingToken -isnot [string] -or $r.resumeClaimedReceiptBindingToken -notmatch '^[a-f0-9]{64}$' -or
                        $r.resumeTerminalReceiptBindingToken -isnot [string] -or $r.resumeTerminalReceiptBindingToken -notmatch '^[a-f0-9]{64}$' -or
                        $r.resumeProviderEvidenceDigest -isnot [string] -or $r.resumeProviderEvidenceDigest -notmatch '^[a-f0-9]{64}$' -or
                        -not (Test-CddsiUtcTimestampValue -Value $r.resumeClaimedAtUtc) -or
                        -not (Test-CddsiUtcTimestampValue -Value $r.resumeOccurredAtUtc)) { return $false }
                    break
                }
                default { return $false }
            }
            if ($r.resumeOperationState -cne 'AVAILABLE') {
                $identifiers = @($State.runId, $checkpointUuid, $r.grantId, $r.claimId, $r.prepareOperationUseId, $r.resumeOperationUseId, $r.attemptClaimId)
                if (@(@($identifiers) | Select-Object -Unique).Count -ne $identifiers.Count) { return $false }
                $claimed = [DateTimeOffset]::Parse($r.resumeClaimedAtUtc)
                if ($claimed -lt $created -or $claimed -gt $updated -or $claimed -ge $expires) { return $false }
                if ($r.resumeOperationState -in @('COMPLETED', 'ABORTED')) {
                    $occurred = [DateTimeOffset]::Parse($r.resumeOccurredAtUtc)
                    if ($occurred -lt $claimed -or $occurred -gt $updated -or $occurred -ge $expires) { return $false }
                }
            }
        }
        else {
            if ($null -ne $State.pendingAction) { return $false }
            foreach ($name in $restartFields) {
                if ($name -ceq 'required') { continue }
                if ($name -ceq 'checkpointRevision' -or $name -ceq 'attemptCount') {
                    if (($State.restart.$name -isnot [int] -and $State.restart.$name -isnot [long]) -or [long]$State.restart.$name -ne 0) { return $false }
                }
                elseif ($null -ne $State.restart.$name) { return $false }
            }
        }

        if (-not $State.desktop.installed) {
            if ($null -ne $State.desktop.packageVersion -or $null -ne $State.desktop.packageIdentity -or $State.desktop.signatureStatus -cne 'not_checked') { return $false }
        }
        else {
            if ($State.desktop.packageVersion -isnot [string] -or $State.desktop.packageVersion -cnotmatch '^(?=.{1,64}$)\d+\.\d+\.\d+(?:\.\d+)?$' -or
                $State.desktop.packageIdentity -isnot [string] -or
                ($State.desktop.packageIdentity -cne '<PACKAGE_IDENTITY:UNKNOWN>' -and $State.desktop.packageIdentity -cnotmatch '^<PACKAGE_IDENTITY_SHA256:[a-f0-9]{64}>$') -or
                @('not_checked', 'valid', 'invalid', 'unknown') -cnotcontains $State.desktop.signatureStatus) { return $false }
        }
        if (-not $State.git.installed) {
            if ($null -ne $State.git.version -or $null -ne $State.git.source) { return $false }
        }
        elseif ($State.git.version -isnot [string] -or $State.git.version -cnotmatch '^(?=.{1,64}$)\d+\.\d+\.\d+(?:\.\d+)?$' -or
            $State.git.source -isnot [string] -or @('existing', 'official_installer', 'unknown') -cnotcontains $State.git.source) { return $false }
        if ($State.cowork.virtualMachinePlatform -isnot [string] -or @('not_checked', 'enabled', 'disabled', 'pending_restart', 'unknown') -cnotcontains $State.cowork.virtualMachinePlatform -or
            $State.cowork.hardwareVirtualization -isnot [string] -or @('not_checked', 'enabled', 'disabled', 'unknown') -cnotcontains $State.cowork.hardwareVirtualization -or
            $State.cowork.serviceStatus -isnot [string] -or @('not_checked', 'ready', 'blocked', 'missing', 'unknown') -cnotcontains $State.cowork.serviceStatus) { return $false }
        if ($State.cowork.ready -and ($State.cowork.virtualMachinePlatform -cne 'enabled' -or $State.cowork.hardwareVirtualization -cne 'enabled' -or $State.cowork.serviceStatus -cne 'ready')) { return $false }
        if ($State.config.targetSource -cne 'HKCU_MANAGED_POLICY' -or
            ($null -ne $State.config.contractVersion -and $State.config.contractVersion -cne 'claude-desktop-3p-managed-policy-v1') -or
            $State.config.ownershipStatus -isnot [string] -or @('not_evaluated', 'available', 'project', 'external', 'conflict', 'unknown') -cnotcontains $State.config.ownershipStatus) { return $false }
        if ($null -ne $State.config.backupId -and ($State.config.backupId -isnot [string] -or $State.config.backupId -notmatch '^backup-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$')) { return $false }
        if ($State.deepseek.remoteValidationStatus -isnot [string] -or @('not_run', 'succeeded', 'failed', 'action_required', 'unknown') -cnotcontains $State.deepseek.remoteValidationStatus -or
            ($null -ne $State.deepseek.lastErrorClass -and @('InvalidInput', 'Unauthorized', 'Billing', 'Forbidden', 'NotFound', 'Validation', 'RateLimited', 'Timeout', 'Dns', 'Tls', 'Proxy', 'Cancelled', 'Transport', 'ServerError', 'Unknown') -cnotcontains $State.deepseek.lastErrorClass)) { return $false }
        if ($null -ne $State.lastError) {
            $messages = [ordered]@{
                operation_failed = 'error.operation_failed'; action_required = 'error.action_required'; cancelled = 'error.cancelled'
                checkpoint_schema_invalid = 'error.checkpoint_schema_invalid'; checkpoint_run_mismatch = 'error.checkpoint_run_mismatch'
                checkpoint_id_mismatch = 'error.checkpoint_id_mismatch'; checkpoint_artifact_mismatch = 'error.checkpoint_artifact_mismatch'
                checkpoint_attempt_mismatch = 'error.checkpoint_attempt_mismatch'; checkpoint_time_invalid = 'error.checkpoint_time_invalid'
                checkpoint_expired = 'error.checkpoint_expired'; checkpoint_attempts_exhausted = 'error.checkpoint_attempts_exhausted'
                config_conflict = 'error.config_conflict'; credential_invalid = 'error.credential_invalid'
                artifact_invalid = 'error.artifact_invalid'; acceptance_failed = 'error.acceptance_failed'
            }
            if ($State.lastError.code -isnot [string] -or @($messages.Keys) -cnotcontains $State.lastError.code -or
                $State.lastError.messageSafe -cne $messages[$State.lastError.code]) { return $false }
        }
        if (-not (Test-CddsiUtcTimestampValue -Value $State.createdAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $State.updatedAtUtc) -or
            [DateTimeOffset]::Parse($State.updatedAtUtc) -lt [DateTimeOffset]::Parse($State.createdAtUtc)) { return $false }
        $serialized = ConvertTo-CddsiJson -InputObject $State -Depth 40
        if (@(Find-CddsiPotentialSecrets -Content $serialized -Source '<state>').Count -gt 0 -or
            $serialized -match '(?i)"(apiKey|authorization|authToken)"\s*:') { return $false }
        return $true
    }
    catch { return $false }
}

function Set-CddsiResumeCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][long]$ExpectedStateRevision,
        [Parameter(Mandatory = $true)][string]$CheckpointId,
        [Parameter(Mandatory = $true)][string]$Stage,
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][string]$SidecarSha256,
        [Parameter(Mandatory = $true)][string]$ContentDigest,
        [Parameter(Mandatory = $true)][ValidateSet('VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$GrantId,
        [Parameter(Mandatory = $true)][string]$ClaimId,
        [Parameter(Mandatory = $true)][string]$WorkflowSessionStateKeySha256,
        [Parameter(Mandatory = $true)][string]$PrepareOperationUseId,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$PrepareTerminalState,
        [Parameter(Mandatory = $true)][string]$PrepareTerminalReceiptBindingToken,
        [Parameter(Mandatory = $true)][string]$PrepareProviderEvidenceDigest,
        [Parameter(Mandatory = $true)][string]$PrepareOccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$ResumeAvailableStateKeySha256,
        [Parameter(Mandatory = $true)][string]$ResumeAvailableReceiptBindingToken,
        [Parameter(Mandatory = $true)][ValidateSet('CHANGED', 'UNKNOWN')][string]$MutationState,
        [Parameter(Mandatory = $true)][string]$UpdatedAtUtc,
        [Parameter(Mandatory = $true)][string]$ExpiresAtUtc,
        [Parameter(Mandatory = $true)][string]$AuthorizationExpiresAtUtc
    )

    if (-not (Test-CddsiStateSchema -State $State)) { throw '输入状态不符合 schema v3。' }
    if ([long]$State.revision -ne $ExpectedStateRevision) { throw 'State compare-and-swap revision 不匹配。' }
    if ($State.restart.required) { throw '不得覆盖活动 checkpoint。' }
    if ($CheckpointId -notmatch '^checkpoint-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { throw 'CheckpointId 必须是 checkpoint-canonical UUID。' }
    if ($Stage -cne $ArtifactProfile) { throw 'Stage/Profile binding 无效。' }
    foreach ($uuid in @($GrantId, $ClaimId, $PrepareOperationUseId)) { if (-not (Test-CddsiCanonicalUuidValue -Value $uuid)) { throw 'Checkpoint UUID binding 无效。' } }
    foreach ($hash in @($ArtifactSha256, $SidecarSha256, $ContentDigest, $WorkflowSessionStateKeySha256, $PrepareTerminalReceiptBindingToken, $PrepareProviderEvidenceDigest, $ResumeAvailableStateKeySha256, $ResumeAvailableReceiptBindingToken)) {
        if ($hash -notmatch '^[a-f0-9]{64}$') { throw 'Checkpoint hash binding 无效。' }
    }
    foreach ($time in @($PrepareOccurredAtUtc, $UpdatedAtUtc, $ExpiresAtUtc, $AuthorizationExpiresAtUtc)) { if (-not (Test-CddsiUtcTimestampValue -Value $time)) { throw 'Checkpoint time 无效。' } }
    $updated = [DateTimeOffset]::Parse($UpdatedAtUtc)
    if ($updated -lt [DateTimeOffset]::Parse($State.updatedAtUtc) -or $updated -lt [DateTimeOffset]::Parse($PrepareOccurredAtUtc) -or
        [DateTimeOffset]::Parse($ExpiresAtUtc) -le $updated -or [DateTimeOffset]::Parse($ExpiresAtUtc) -gt [DateTimeOffset]::Parse($AuthorizationExpiresAtUtc)) { throw 'Checkpoint time window 无效。' }

    $copy = [System.Management.Automation.PSSerializer]::Deserialize(
        [System.Management.Automation.PSSerializer]::Serialize($State, 40)
    )
    $copy.completedSteps = @($copy.completedSteps)
    $copy.revision = [long]$State.revision + 1
    $copy.pendingAction = 'restart'
    $copy.updatedAtUtc = $UpdatedAtUtc
    $values = [ordered]@{
        required = $true; reasonCode = 'vmp_change'; resumePhase = 'verify_cowork'; checkpointId = $CheckpointId
        ownerRunId = $State.runId; stage = $Stage; artifactSha256 = $ArtifactSha256; sidecarSha256 = $SidecarSha256
        contentDigest = $ContentDigest; profile = $ArtifactProfile; grantId = $GrantId; claimId = $ClaimId
        workflowSessionStateKeySha256 = $WorkflowSessionStateKeySha256; prepareOperationUseId = $PrepareOperationUseId
        prepareTerminalState = $PrepareTerminalState; prepareTerminalReceiptBindingToken = $PrepareTerminalReceiptBindingToken
        prepareProviderEvidenceDigest = $PrepareProviderEvidenceDigest; prepareOccurredAtUtc = $PrepareOccurredAtUtc
        resumeAvailableStateKeySha256 = $ResumeAvailableStateKeySha256; resumeAvailableReceiptBindingToken = $ResumeAvailableReceiptBindingToken
        resumeOperationState = 'AVAILABLE'; resumeOperationUseId = $null; resumeClaimedReceiptBindingToken = $null
        resumeClaimedAtUtc = $null; resumeTerminalReceiptBindingToken = $null; resumeProviderEvidenceDigest = $null
        resumeOccurredAtUtc = $null; attemptClaimId = $null; checkpointRevision = 1; attemptCount = 0
        mutationState = $MutationState; createdAtUtc = $UpdatedAtUtc; updatedAtUtc = $UpdatedAtUtc
        expiresAtUtc = $ExpiresAtUtc; authorizationExpiresAtUtc = $AuthorizationExpiresAtUtc
    }
    foreach ($name in $values.Keys) { $copy.restart.$name = $values[$name] }
    if (-not (Test-CddsiStateSchema -State $copy)) { throw 'Checkpoint 状态生成失败。' }
    return $copy
}

function Claim-CddsiResumeCheckpointAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ExpectedCheckpointId,
        [Parameter(Mandatory = $true)][long]$ExpectedStateRevision,
        [Parameter(Mandatory = $true)][long]$ExpectedCheckpointRevision,
        [Parameter(Mandatory = $true)][string]$AttemptClaimId,
        [Parameter(Mandatory = $true)][string]$ResumeOperationUseId,
        [Parameter(Mandatory = $true)][string]$ResumeClaimedReceiptBindingToken,
        [Parameter(Mandatory = $true)][string]$ResumeClaimedAtUtc,
        [Parameter(Mandatory = $true)][string]$UpdatedAtUtc
    )

    if (-not (Test-CddsiStateSchema -State $State) -or -not $State.restart.required) { throw '不存在有效 checkpoint。' }
    if ($State.restart.checkpointId -cne $ExpectedCheckpointId -or [long]$State.revision -ne $ExpectedStateRevision -or
        [long]$State.restart.checkpointRevision -ne $ExpectedCheckpointRevision) { throw 'Checkpoint compare-and-swap binding 不匹配。' }
    if ($State.restart.resumeOperationState -cne 'AVAILABLE' -or [long]$State.restart.attemptCount -ne 0) { throw 'Checkpoint 已 claim 或 terminal，禁止重复 attempt。' }
    foreach ($uuid in @($AttemptClaimId, $ResumeOperationUseId)) { if (-not (Test-CddsiCanonicalUuidValue -Value $uuid)) { throw 'Resume attempt UUID 无效。' } }
    $ids = @($State.runId, $State.restart.checkpointId.Substring('checkpoint-'.Length), $State.restart.grantId, $State.restart.claimId, $State.restart.prepareOperationUseId, $AttemptClaimId, $ResumeOperationUseId)
    if (@(@($ids) | Select-Object -Unique).Count -ne $ids.Count) { throw 'Resume attempt UUID 不得碰撞。' }
    if ($ResumeClaimedReceiptBindingToken -notmatch '^[a-f0-9]{64}$' -or -not (Test-CddsiUtcTimestampValue -Value $ResumeClaimedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $UpdatedAtUtc)) { throw 'Resume claimed receipt 无效。' }
    $claimed = [DateTimeOffset]::Parse($ResumeClaimedAtUtc)
    $updated = [DateTimeOffset]::Parse($UpdatedAtUtc)
    if ($claimed -lt [DateTimeOffset]::Parse($State.restart.createdAtUtc) -or $updated -lt $claimed -or
        $updated -le [DateTimeOffset]::Parse($State.updatedAtUtc) -or $updated -ge [DateTimeOffset]::Parse($State.restart.expiresAtUtc)) { throw 'Resume claim time window 无效。' }

    $copy = [System.Management.Automation.PSSerializer]::Deserialize(
        [System.Management.Automation.PSSerializer]::Serialize($State, 40)
    )
    $copy.completedSteps = @($copy.completedSteps)
    $copy.revision = [long]$State.revision + 1
    $copy.updatedAtUtc = $UpdatedAtUtc
    $copy.restart.resumeOperationState = 'CLAIMED'
    $copy.restart.resumeOperationUseId = $ResumeOperationUseId
    $copy.restart.resumeClaimedReceiptBindingToken = $ResumeClaimedReceiptBindingToken
    $copy.restart.resumeClaimedAtUtc = $ResumeClaimedAtUtc
    $copy.restart.attemptClaimId = $AttemptClaimId
    $copy.restart.attemptCount = 1
    $copy.restart.checkpointRevision = [long]$State.restart.checkpointRevision + 1
    $copy.restart.updatedAtUtc = $UpdatedAtUtc
    if (-not (Test-CddsiStateSchema -State $copy)) { throw 'Resume claim 状态生成失败。' }
    return $copy
}

function Complete-CddsiResumeCheckpointAttempt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ExpectedCheckpointId,
        [Parameter(Mandatory = $true)][long]$ExpectedStateRevision,
        [Parameter(Mandatory = $true)][long]$ExpectedCheckpointRevision,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$TerminalState,
        [Parameter(Mandatory = $true)][string]$TerminalReceiptBindingToken,
        [Parameter(Mandatory = $true)][string]$ProviderEvidenceDigest,
        [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$UpdatedAtUtc
    )

    if (-not (Test-CddsiStateSchema -State $State) -or $State.restart.resumeOperationState -cne 'CLAIMED') { throw 'Checkpoint 不处于 CLAIMED。' }
    if ($State.restart.checkpointId -cne $ExpectedCheckpointId -or [long]$State.revision -ne $ExpectedStateRevision -or
        [long]$State.restart.checkpointRevision -ne $ExpectedCheckpointRevision) { throw 'Resume terminal compare-and-swap binding 不匹配。' }
    foreach ($hash in @($TerminalReceiptBindingToken, $ProviderEvidenceDigest)) { if ($hash -notmatch '^[a-f0-9]{64}$') { throw 'Resume terminal receipt 无效。' } }
    if (-not (Test-CddsiUtcTimestampValue -Value $OccurredAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $UpdatedAtUtc)) { throw 'Resume terminal time 无效。' }
    $occurred = [DateTimeOffset]::Parse($OccurredAtUtc)
    $updated = [DateTimeOffset]::Parse($UpdatedAtUtc)
    if ($occurred -lt [DateTimeOffset]::Parse($State.restart.resumeClaimedAtUtc) -or $updated -lt $occurred -or
        $updated -le [DateTimeOffset]::Parse($State.updatedAtUtc) -or $updated -ge [DateTimeOffset]::Parse($State.restart.expiresAtUtc)) { throw 'Resume terminal time window 无效。' }

    $copy = [System.Management.Automation.PSSerializer]::Deserialize(
        [System.Management.Automation.PSSerializer]::Serialize($State, 40)
    )
    $copy.completedSteps = @($copy.completedSteps)
    $copy.revision = [long]$State.revision + 1
    $copy.updatedAtUtc = $UpdatedAtUtc
    $copy.restart.resumeOperationState = $TerminalState
    $copy.restart.resumeTerminalReceiptBindingToken = $TerminalReceiptBindingToken
    $copy.restart.resumeProviderEvidenceDigest = $ProviderEvidenceDigest
    $copy.restart.resumeOccurredAtUtc = $OccurredAtUtc
    $copy.restart.checkpointRevision = [long]$State.restart.checkpointRevision + 1
    $copy.restart.updatedAtUtc = $UpdatedAtUtc
    if (-not (Test-CddsiStateSchema -State $copy)) { throw 'Resume terminal 状态生成失败。' }
    return $copy
}

function Clear-CddsiResumeCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ExpectedCheckpointId,
        [Parameter(Mandatory = $true)][long]$ExpectedStateRevision,
        [Parameter(Mandatory = $true)][long]$ExpectedCheckpointRevision,
        [Parameter(Mandatory = $true)][string]$UpdatedAtUtc
    )

    if (-not (Test-CddsiStateSchema -State $State) -or $State.restart.resumeOperationState -cne 'COMPLETED') { throw '只有已证明 COMPLETED 的 ResumeCowork receipt 才允许清理 checkpoint。' }
    if ($State.restart.checkpointId -cne $ExpectedCheckpointId -or [long]$State.revision -ne $ExpectedStateRevision -or
        [long]$State.restart.checkpointRevision -ne $ExpectedCheckpointRevision) { throw 'Checkpoint cleanup compare-and-swap binding 不匹配。' }
    if (-not (Test-CddsiUtcTimestampValue -Value $UpdatedAtUtc) -or
        [DateTimeOffset]::Parse($UpdatedAtUtc) -lt [DateTimeOffset]::Parse($State.restart.resumeOccurredAtUtc) -or
        [DateTimeOffset]::Parse($UpdatedAtUtc) -lt [DateTimeOffset]::Parse($State.updatedAtUtc)) { throw 'Checkpoint cleanup time 无效。' }
    $copy = [System.Management.Automation.PSSerializer]::Deserialize(
        [System.Management.Automation.PSSerializer]::Serialize($State, 40)
    )
    $copy.completedSteps = @($copy.completedSteps)
    $copy.revision = [long]$State.revision + 1
    $copy.pendingAction = $null
    $copy.updatedAtUtc = $UpdatedAtUtc
    $blank = New-CddsiState -InstallerVersion $copy.installerVersion -ExecutionMode $copy.executionMode -RunId $copy.runId -TimestampUtc $copy.createdAtUtc
    $copy.restart = $blank.restart
    if (-not (Test-CddsiStateSchema -State $copy)) { throw 'Checkpoint cleanup 状态生成失败。' }
    return $copy
}

function ConvertTo-CddsiStateV3 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StateV2,
        [Parameter(Mandatory = $true)][string]$MigratedAtUtc
    )

    if (-not (Test-CddsiUtcTimestampValue -Value $MigratedAtUtc)) { throw 'MigratedAtUtc 无效。' }
    $expectedTop = @('schemaVersion', 'installerVersion', 'runId', 'executionMode', 'phase', 'status', 'completedSteps', 'pendingAction', 'restart', 'desktop', 'git', 'cowork', 'config', 'deepseek', 'lastError', 'createdAtUtc', 'updatedAtUtc')
    if (-not (Test-CddsiExactPropertySet -InputObject $StateV2 -Expected $expectedTop) -or
        ($StateV2.schemaVersion -isnot [int] -and $StateV2.schemaVersion -isnot [long]) -or [long]$StateV2.schemaVersion -ne 2 -or
        -not (Test-CddsiExactPropertySet -InputObject $StateV2.restart -Expected @('required', 'reasonCode', 'resumePhase', 'checkpointId', 'ownerRunId', 'artifactSha256', 'profile', 'createdAtUtc', 'expiresAtUtc', 'attemptCount'))) { throw '只接受精确 schema v2 状态。' }
    if ($StateV2.restart.required -or $null -ne $StateV2.pendingAction) { throw 'v2 pending checkpoint 缺少供应链与 receipt binding，禁止迁移。' }
    foreach ($name in @('reasonCode', 'resumePhase', 'checkpointId', 'ownerRunId', 'artifactSha256', 'profile', 'createdAtUtc', 'expiresAtUtc')) { if ($null -ne $StateV2.restart.$name) { throw 'v2 inactive restart 必须为空。' } }
    if (($StateV2.restart.attemptCount -isnot [int] -and $StateV2.restart.attemptCount -isnot [long]) -or [long]$StateV2.restart.attemptCount -ne 0) { throw 'v2 inactive attemptCount 无效。' }
    if (-not (Test-CddsiCanonicalUuidValue -Value $StateV2.runId) -or -not (Test-CddsiUtcTimestampValue -Value $StateV2.createdAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $StateV2.updatedAtUtc) -or
        [DateTimeOffset]::Parse($StateV2.updatedAtUtc) -lt [DateTimeOffset]::Parse($StateV2.createdAtUtc) -or
        [DateTimeOffset]::Parse($MigratedAtUtc) -lt [DateTimeOffset]::Parse($StateV2.updatedAtUtc)) { throw 'v2 migration time/run binding 无效。' }
    if ($null -ne $StateV2.config.backupId) { throw 'legacy backupId 不是 backup-canonical UUID，禁止有损迁移。' }

    $migrated = New-CddsiState -InstallerVersion $StateV2.installerVersion -ExecutionMode $StateV2.executionMode -RunId $StateV2.runId -TimestampUtc $StateV2.createdAtUtc
    $migrated.phase = $StateV2.phase
    $migrated.status = $StateV2.status
    $migrated.completedSteps = @($StateV2.completedSteps)
    $migrated.desktop = $StateV2.desktop
    $migrated.git = $StateV2.git
    $migrated.cowork = $StateV2.cowork
    $migrated.config = $StateV2.config
    $migrated.deepseek = $StateV2.deepseek
    $migrated.lastError = $StateV2.lastError
    $migrated.updatedAtUtc = $MigratedAtUtc
    if (-not (Test-CddsiStateSchema -State $migrated)) { throw '迁移后的 v3 状态无效。' }
    return $migrated
}
