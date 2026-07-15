BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    function Copy-TestCddsiState {
        param([Parameter(Mandatory = $true)]$State)
        $copy = [System.Management.Automation.PSSerializer]::Deserialize(
            [System.Management.Automation.PSSerializer]::Serialize($State, 40)
        )
        $copy.completedSteps = @($copy.completedSteps)
        return $copy
    }

    function New-TestCddsiState {
        return New-CddsiState -RunId '20000000-0000-4000-8000-000000000701' `
            -TimestampUtc '2030-01-01T00:00:00.0000000Z'
    }

    function New-TestCddsiCheckpointState {
        $state = New-TestCddsiState
        return Set-CddsiResumeCheckpoint -State $state -ExpectedStateRevision 1 `
            -CheckpointId 'checkpoint-90000000-0000-4000-8000-000000000701' `
            -Stage VmAcceptance -ArtifactSha256 ('a' * 64) -SidecarSha256 ('b' * 64) `
            -ContentDigest ('c' * 64) -ArtifactProfile VmAcceptance `
            -GrantId '10000000-0000-4000-8000-000000000701' `
            -ClaimId '40000000-0000-4000-8000-000000000701' `
            -WorkflowSessionStateKeySha256 ('d' * 64) `
            -PrepareOperationUseId '60000000-0000-4000-8000-000000000701' `
            -PrepareTerminalState COMPLETED -PrepareTerminalReceiptBindingToken ('e' * 64) `
            -PrepareProviderEvidenceDigest ('f' * 64) `
            -PrepareOccurredAtUtc '2030-01-01T00:01:00.0000000Z' `
            -ResumeAvailableStateKeySha256 ('1' * 64) `
            -ResumeAvailableReceiptBindingToken ('2' * 64) -MutationState CHANGED `
            -UpdatedAtUtc '2030-01-01T00:02:00.0000000Z' `
            -ExpiresAtUtc '2030-01-01T00:50:00.0000000Z' `
            -AuthorizationExpiresAtUtc '2030-01-01T01:00:00.0000000Z'
    }
}

Describe 'state schema v3 and Cowork checkpoint state machine' {
    It 'creates a strict secret-free v3 state with canonical identifiers' {
        $state = New-TestCddsiState
        (Test-CddsiStateSchema -State $state) | Should -BeTrue
        $state.schemaVersion | Should -Be 3
        $state.revision | Should -Be 1
        ($state | ConvertTo-Json -Depth 40) | Should -Not -Match '(?i)api.?key|authorization.?header|raw.?config|configLibrary'
        { New-CddsiState -RunId ('2a000000-0000-4000-8000-000000000701'.ToUpperInvariant()) -TimestampUtc '2030-01-01T00:00:00Z' } | Should -Throw

        $state.config.backupId = 'backup-70000000-0000-4000-8000-000000000701'
        (Test-CddsiStateSchema -State $state) | Should -BeTrue
        $state.config.backupId = 'backup-70000000000040008000000000000701'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
    }

    It 'uses CAS revisions across available claimed completed and cleared states' {
        $pending = New-TestCddsiCheckpointState
        $pending.revision | Should -Be 2
        $pending.restart.checkpointRevision | Should -Be 1
        $pending.restart.resumeOperationState | Should -Be 'AVAILABLE'

        $claimed = Claim-CddsiResumeCheckpointAttempt -State $pending `
            -ExpectedCheckpointId $pending.restart.checkpointId -ExpectedStateRevision 2 `
            -ExpectedCheckpointRevision 1 -AttemptClaimId '80000000-0000-4000-8000-000000000701' `
            -ResumeOperationUseId '60000000-0000-4000-8000-000000000702' `
            -ResumeClaimedReceiptBindingToken ('3' * 64) `
            -ResumeClaimedAtUtc '2030-01-01T00:03:00.0000000Z' `
            -UpdatedAtUtc '2030-01-01T00:03:00.0000000Z'
        $claimed.revision | Should -Be 3
        $claimed.restart.checkpointRevision | Should -Be 2
        $claimed.restart.attemptCount | Should -Be 1
        (Test-CddsiStateSchema -State $claimed) | Should -BeTrue

        $terminal = Complete-CddsiResumeCheckpointAttempt -State $claimed `
            -ExpectedCheckpointId $claimed.restart.checkpointId -ExpectedStateRevision 3 `
            -ExpectedCheckpointRevision 2 -TerminalState COMPLETED `
            -TerminalReceiptBindingToken ('4' * 64) -ProviderEvidenceDigest ('5' * 64) `
            -OccurredAtUtc '2030-01-01T00:04:00.0000000Z' `
            -UpdatedAtUtc '2030-01-01T00:04:00.0000000Z'
        $terminal.restart.resumeOperationState | Should -Be 'COMPLETED'
        $terminal.restart.checkpointRevision | Should -Be 3

        $cleared = Clear-CddsiResumeCheckpoint -State $terminal `
            -ExpectedCheckpointId $terminal.restart.checkpointId -ExpectedStateRevision 4 `
            -ExpectedCheckpointRevision 3 -UpdatedAtUtc '2030-01-01T00:04:00.0000000Z'
        $cleared.revision | Should -Be 5
        $cleared.restart.required | Should -BeFalse
        (Test-CddsiStateSchema -State $cleared) | Should -BeTrue
    }

    It 'rejects stale CAS duplicate attempts identifier collision and time rollback' {
        $pending = New-TestCddsiCheckpointState
        $base = @{
            State = $pending; ExpectedCheckpointId = $pending.restart.checkpointId
            ExpectedStateRevision = 2; ExpectedCheckpointRevision = 1
            AttemptClaimId = '80000000-0000-4000-8000-000000000701'
            ResumeOperationUseId = '60000000-0000-4000-8000-000000000702'
            ResumeClaimedReceiptBindingToken = ('3' * 64)
            ResumeClaimedAtUtc = '2030-01-01T00:03:00.0000000Z'; UpdatedAtUtc = '2030-01-01T00:03:00.0000000Z'
        }
        $stale = $base.Clone(); $stale.ExpectedStateRevision = 1
        { Claim-CddsiResumeCheckpointAttempt @stale } | Should -Throw
        $collision = $base.Clone(); $collision.AttemptClaimId = $pending.restart.claimId
        { Claim-CddsiResumeCheckpointAttempt @collision } | Should -Throw
        $rollback = $base.Clone(); $rollback.UpdatedAtUtc = '2030-01-01T00:01:59.0000000Z'
        { Claim-CddsiResumeCheckpointAttempt @rollback } | Should -Throw
        $claimed = Claim-CddsiResumeCheckpointAttempt @base
        $replay = $base.Clone(); $replay.State = $claimed; $replay.ExpectedStateRevision = 3; $replay.ExpectedCheckpointRevision = 2
        { Claim-CddsiResumeCheckpointAttempt @replay } | Should -Throw
    }

    It 'never clears an aborted or merely claimed checkpoint' {
        $pending = New-TestCddsiCheckpointState
        { Clear-CddsiResumeCheckpoint -State $pending -ExpectedCheckpointId $pending.restart.checkpointId `
            -ExpectedStateRevision 2 -ExpectedCheckpointRevision 1 -UpdatedAtUtc '2030-01-01T00:03:00.0000000Z' } | Should -Throw
        $claimed = Claim-CddsiResumeCheckpointAttempt -State $pending `
            -ExpectedCheckpointId $pending.restart.checkpointId -ExpectedStateRevision 2 -ExpectedCheckpointRevision 1 `
            -AttemptClaimId '80000000-0000-4000-8000-000000000701' `
            -ResumeOperationUseId '60000000-0000-4000-8000-000000000702' `
            -ResumeClaimedReceiptBindingToken ('3' * 64) -ResumeClaimedAtUtc '2030-01-01T00:03:00.0000000Z' `
            -UpdatedAtUtc '2030-01-01T00:03:00.0000000Z'
        $aborted = Complete-CddsiResumeCheckpointAttempt -State $claimed `
            -ExpectedCheckpointId $claimed.restart.checkpointId -ExpectedStateRevision 3 -ExpectedCheckpointRevision 2 `
            -TerminalState ABORTED -TerminalReceiptBindingToken ('4' * 64) -ProviderEvidenceDigest ('5' * 64) `
            -OccurredAtUtc '2030-01-01T00:04:00.0000000Z' -UpdatedAtUtc '2030-01-01T00:04:00.0000000Z'
        { Clear-CddsiResumeCheckpoint -State $aborted -ExpectedCheckpointId $aborted.restart.checkpointId `
            -ExpectedStateRevision 4 -ExpectedCheckpointRevision 3 -UpdatedAtUtc '2030-01-01T00:04:00.0000000Z' } | Should -Throw
    }

    It 'rejects corrupt fields and expiry beyond authorization' {
        $pending = New-TestCddsiCheckpointState
        $corrupt = Copy-TestCddsiState $pending
        $corrupt.restart | Add-Member -NotePropertyName rawConfig -NotePropertyValue '{}'
        (Test-CddsiStateSchema -State $corrupt) | Should -BeFalse
        $corrupt = Copy-TestCddsiState $pending
        $corrupt.restart.attemptCount = '0'
        (Test-CddsiStateSchema -State $corrupt) | Should -BeFalse
        { Set-CddsiResumeCheckpoint -State (New-TestCddsiState) -ExpectedStateRevision 1 `
            -CheckpointId 'checkpoint-90000000-0000-4000-8000-000000000702' -Stage VmAcceptance `
            -ArtifactSha256 ('a' * 64) -SidecarSha256 ('b' * 64) -ContentDigest ('c' * 64) `
            -ArtifactProfile VmAcceptance -GrantId '10000000-0000-4000-8000-000000000701' `
            -ClaimId '40000000-0000-4000-8000-000000000701' -WorkflowSessionStateKeySha256 ('d' * 64) `
            -PrepareOperationUseId '60000000-0000-4000-8000-000000000701' -PrepareTerminalState COMPLETED `
            -PrepareTerminalReceiptBindingToken ('e' * 64) -PrepareProviderEvidenceDigest ('f' * 64) `
            -PrepareOccurredAtUtc '2030-01-01T00:01:00Z' -ResumeAvailableStateKeySha256 ('1' * 64) `
            -ResumeAvailableReceiptBindingToken ('2' * 64) -MutationState CHANGED `
            -UpdatedAtUtc '2030-01-01T00:02:00Z' -ExpiresAtUtc '2030-01-01T01:01:00Z' `
            -AuthorizationExpiresAtUtc '2030-01-01T01:00:00Z' } | Should -Throw
    }

    It 'strictly migrates only an inactive exact v2 state' {
        $state = New-TestCddsiState
        $v2 = Copy-TestCddsiState $state
        $v2.PSObject.Properties.Remove('revision')
        $v2.schemaVersion = 2
        $v2.restart = [pscustomobject][ordered]@{
            required = $false; reasonCode = $null; resumePhase = $null; checkpointId = $null
            ownerRunId = $null; artifactSha256 = $null; profile = $null; createdAtUtc = $null
            expiresAtUtc = $null; attemptCount = 0
        }
        $migrated = ConvertTo-CddsiStateV3 -StateV2 $v2 -MigratedAtUtc '2030-01-01T00:01:00.0000000Z'
        $migrated.schemaVersion | Should -Be 3
        (Test-CddsiStateSchema -State $migrated) | Should -BeTrue

        $pending = Copy-TestCddsiState $v2
        $pending.restart.required = $true; $pending.pendingAction = 'restart'
        { ConvertTo-CddsiStateV3 -StateV2 $pending -MigratedAtUtc '2030-01-01T00:01:00.0000000Z' } | Should -Throw
        $extra = Copy-TestCddsiState $v2
        $extra | Add-Member -NotePropertyName rawConfig -NotePropertyValue '{}'
        { ConvertTo-CddsiStateV3 -StateV2 $extra -MigratedAtUtc '2030-01-01T00:01:00.0000000Z' } | Should -Throw
        $v2.config.backupId = 'backup-legacy'
        { ConvertTo-CddsiStateV3 -StateV2 $v2 -MigratedAtUtc '2030-01-01T00:01:00.0000000Z' } | Should -Throw
    }
}
