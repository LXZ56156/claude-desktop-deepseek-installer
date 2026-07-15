BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\stage-policy.ps1')

    function New-CddsiSyntheticStageManifest {
        param(
            [ValidateSet('Scaffold', 'Development', 'VmCalibration', 'VmAcceptance', 'UserLive')]
            [string]$Stage = 'VmAcceptance',
            [string]$ArtifactProfile = ''
        )

        if ([string]::IsNullOrEmpty($ArtifactProfile)) { $ArtifactProfile = $Stage }
        return [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-stage-manifest-v1'
            Stage           = $Stage
            ArtifactProfile = $ArtifactProfile
            ArtifactVersion = '1.2.3-rc.1'
            CommitId        = ('a' * 40)
            ArtifactSha256  = ('b' * 64)
            SidecarSha256   = ('d' * 64)
            ContentDigest   = ('c' * 64)
            CreatedAtUtc    = '2030-01-01T00:00:00Z'
        }
    }

    function New-CddsiSyntheticOperationGrant {
        param(
            [string[]]$AllowedOperations = @('EnsureGit'),
            [string]$ArtifactProfile = 'VmAcceptance',
            [string]$RunId = '20000000-0000-4000-8000-000000000801'
        )

        $bindings = @()
        for ($index = 0; $index -lt $AllowedOperations.Count; $index++) {
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion   = 1
                ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId  = '50000000-0000-4000-8000-{0}' -f (($index + 1).ToString('000000000000'))
                Operation       = $AllowedOperations[$index]
                PromptDigest    = (($index + 1).ToString('x')).PadLeft(64, '0')
                Required        = $true
            }
        }
        return [pscustomobject][ordered]@{
            SchemaVersion       = 1
            ContractVersion     = 'cddsi-operation-grant-v2'
            GrantId             = '10000000-0000-4000-8000-000000000801'
            ArtifactSha256      = ('b' * 64)
            SidecarSha256       = ('d' * 64)
            ContentDigest       = ('c' * 64)
            ArtifactProfile     = $ArtifactProfile
            RunId               = $RunId
            IssuedAtUtc         = '2030-01-01T00:00:00Z'
            ExpiresAtUtc        = '2030-01-01T01:00:00Z'
            Nonce               = '30000000-0000-4000-8000-000000000801'
            AllowedOperations   = @($AllowedOperations)
            SingleUse           = $true
            ConfirmationBindings = @($bindings)
        }
    }

    function New-CddsiSyntheticClaimState {
        param(
            [AllowNull()]$Grant = (New-CddsiSyntheticOperationGrant),
            [ValidateSet('AVAILABLE', 'CLAIMED', 'COMPLETED', 'ABORTED', 'EXPIRED')]
            [string]$State = 'AVAILABLE',
            [string]$ClaimId = '40000000-0000-4000-8000-000000000801',
            [int]$Revision = -1
        )

        if ($Revision -lt 0) { $Revision = if ($State -ceq 'AVAILABLE') { 0 } else { 1 } }
        return [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-grant-claim-state-v1'
            State           = $State
            GrantId         = $Grant.GrantId
            Nonce           = $Grant.Nonce
            RunId           = $Grant.RunId
            ArtifactSha256  = $Grant.ArtifactSha256
            SidecarSha256   = $Grant.SidecarSha256
            ContentDigest   = $Grant.ContentDigest
            ArtifactProfile = $Grant.ArtifactProfile
            ClaimId         = if ($State -ceq 'AVAILABLE') { $null } else { $ClaimId }
            ClaimedAtUtc    = if ($State -ceq 'AVAILABLE') { $null } else { '2030-01-01T00:02:00Z' }
            ExpiresAtUtc    = $Grant.ExpiresAtUtc
            Revision        = $Revision
        }
    }

    function New-CddsiSyntheticAuthorizationSession {
        param(
            [AllowNull()]$Grant = (New-CddsiSyntheticOperationGrant),
            [string]$ClaimId = '40000000-0000-4000-8000-000000000801'
        )

        return [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-authorization-session-v1'
            State           = 'CLAIMED'
            GrantId         = $Grant.GrantId
            Nonce           = $Grant.Nonce
            ClaimId         = $ClaimId
            RunId           = $Grant.RunId
            ArtifactSha256  = $Grant.ArtifactSha256
            SidecarSha256   = $Grant.SidecarSha256
            ContentDigest   = $Grant.ContentDigest
            ArtifactProfile = $Grant.ArtifactProfile
            ClaimedAtUtc    = '2030-01-01T00:02:00Z'
            ExpiresAtUtc    = $Grant.ExpiresAtUtc
            Revision        = 1
        }
    }

    function New-CddsiSyntheticInteractiveConfirmation {
        param(
            [AllowNull()]$Grant = (New-CddsiSyntheticOperationGrant),
            [AllowNull()]$Session = (New-CddsiSyntheticAuthorizationSession -Grant $Grant),
            [string]$Operation = 'EnsureGit'
        )

        $binding = @($Grant.ConfirmationBindings | Where-Object { $_.Operation -ceq $Operation })[0]
        return [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-interactive-confirmation-v2'
            ConfirmationId  = $binding.ConfirmationId
            GrantId         = $Grant.GrantId
            ClaimId         = $Session.ClaimId
            PromptDigest    = $binding.PromptDigest
            ArtifactSha256  = $Grant.ArtifactSha256
            SidecarSha256   = $Grant.SidecarSha256
            ContentDigest   = $Grant.ContentDigest
            ArtifactProfile = $Grant.ArtifactProfile
            RunId           = $Grant.RunId
            Nonce           = $Grant.Nonce
            Operation       = $Operation
            Confirmed       = $true
            ConfirmedAtUtc  = '2030-01-01T00:05:00Z'
        }
    }

    function New-CddsiSyntheticWorkflowState {
        param(
            [AllowNull()]$Manifest = (New-CddsiSyntheticStageManifest),
            [AllowNull()]$Grant = (New-CddsiSyntheticOperationGrant),
            [AllowNull()]$Session = (New-CddsiSyntheticAuthorizationSession -Grant $Grant)
        )
        return New-CddsiWorkflowSessionState -StageManifest $Manifest -OperationGrant $Grant -AuthorizationSession $Session
    }

    function Get-CddsiSyntheticOperationUseId {
        param([AllowNull()]$Grant, [Parameter(Mandatory = $true)][string]$Operation)
        $index = [array]::IndexOf([object[]]@($Grant.AllowedOperations), $Operation)
        if ($index -lt 0) { throw 'Operation is not present in the synthetic grant.' }
        return ('60000000-0000-4000-8000-{0:d12}' -f ($index + 1))
    }

    function Get-CddsiSyntheticOperationIdempotencyKey {
        param([AllowNull()]$Grant, [Parameter(Mandatory = $true)][string]$Operation)
        $index = [array]::IndexOf([object[]]@($Grant.AllowedOperations), $Operation)
        if ($index -lt 0) { throw 'Operation is not present in the synthetic grant.' }
        return ('70000000-0000-4000-8000-{0:d12}' -f ($index + 1))
    }

    function New-CddsiSyntheticAvailableOperationUse {
        param(
            [AllowNull()]$Manifest,
            [AllowNull()]$Grant,
            [AllowNull()]$Session,
            [AllowNull()]$Workflow,
            [Parameter(Mandatory = $true)][string]$Operation
        )
        return New-CddsiOperationUseState -StageManifest $Manifest -OperationGrant $Grant `
            -AuthorizationSession $Session -WorkflowSessionState $Workflow -Operation $Operation
    }

    function New-CddsiSyntheticClaimedOperationUse {
        param(
            [AllowNull()]$Manifest,
            [AllowNull()]$Grant,
            [AllowNull()]$Session,
            [AllowNull()]$Workflow,
            [Parameter(Mandatory = $true)][string]$Operation
        )
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $Manifest -Grant $Grant `
            -Session $Session -Workflow $Workflow -Operation $Operation
        $operationUseId = Get-CddsiSyntheticOperationUseId -Grant $Grant -Operation $Operation
        $confirmation = New-CddsiSyntheticInteractiveConfirmation -Grant $Grant -Session $Session -Operation $Operation
        $proposal = Resolve-CddsiOperationAuthorization -StageManifest $Manifest -OperationGrant $Grant `
            -AuthorizationSession $Session -WorkflowSessionState $Workflow -OperationUseState $available `
            -Confirmation $confirmation -Operation $Operation -OperationUseId $operationUseId `
            -ExpectedRevision 0 -RunId $Grant.RunId -NowUtc '2030-01-01T00:10:00Z'
        if (-not $proposal.Data.AuthorizationProposed) { throw 'Synthetic operation-use claim failed.' }
        return $proposal.Data.ProposedOperationUseState
    }

    function New-CddsiSyntheticTerminalOperationUse {
        param(
            [AllowNull()]$Manifest,
            [AllowNull()]$Grant,
            [AllowNull()]$Session,
            [AllowNull()]$Workflow,
            [Parameter(Mandatory = $true)][string]$Operation,
            [ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome = 'COMPLETED',
            [string]$TerminalReasonCode = ''
        )
        $claimed = New-CddsiSyntheticClaimedOperationUse -Manifest $Manifest -Grant $Grant `
            -Session $Session -Workflow $Workflow -Operation $Operation
        if ($Outcome -ceq 'ABORTED' -and [string]::IsNullOrEmpty($TerminalReasonCode)) {
            $TerminalReasonCode = 'PROVIDER_FAILED'
        }
        $terminal = Resolve-CddsiOperationUseTerminal -StageManifest $Manifest -OperationGrant $Grant `
            -AuthorizationSession $Session -WorkflowSessionState $Workflow -OperationUseState $claimed `
            -Operation $Operation -OperationUseId $claimed.OperationUseId -ExpectedRevision $claimed.Revision `
            -Outcome $Outcome -ProviderEvidenceDigest ('8' * 64) -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey (Get-CddsiSyntheticOperationIdempotencyKey -Grant $Grant -Operation $Operation) `
            -TerminalReasonCode $TerminalReasonCode
        if (-not $terminal.Data.Terminalized) { throw 'Synthetic operation-use terminal reduction failed.' }
        return $terminal.Data.TerminalOperationUseState
    }

    function New-CddsiSyntheticUnexecutedAbort {
        param(
            [AllowNull()]$Manifest,
            [AllowNull()]$Grant,
            [AllowNull()]$Session,
            [AllowNull()]$Workflow,
            [Parameter(Mandatory = $true)][string]$Operation,
            [ValidateSet('NOT_RUN_DUE_TO_ABORT', 'NOT_REQUIRED')][string]$ReasonCode
        )
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $Manifest -Grant $Grant `
            -Session $Session -Workflow $Workflow -Operation $Operation
        $result = Resolve-CddsiUnexecutedOperationUseAbort -StageManifest $Manifest -OperationGrant $Grant `
            -AuthorizationSession $Session -WorkflowSessionState $Workflow -OperationUseState $available `
            -Operation $Operation -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $Grant -Operation $Operation) `
            -ExpectedRevision 0 -ReasonCode $ReasonCode -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey (Get-CddsiSyntheticOperationIdempotencyKey -Grant $Grant -Operation $Operation)
        if (-not $result.Data.Terminalized) { throw 'Synthetic unexecuted-operation abort failed.' }
        return $result.Data.TerminalOperationUseState
    }
}

Describe 'stage manifest contract' {
    It 'accepts only the exact lifecycle stage and artifact-profile mapping' {
        foreach ($stage in @('Scaffold', 'Development', 'VmCalibration', 'VmAcceptance', 'UserLive')) {
            (Test-CddsiStageManifest -Manifest (New-CddsiSyntheticStageManifest -Stage $stage)) | Should -BeTrue
        }

        $manifest = New-CddsiSyntheticStageManifest -Stage VmAcceptance -ArtifactProfile UserLive
        (Test-CddsiStageManifest -Manifest $manifest) | Should -BeFalse
    }

    It 'fails closed on schema version hash timestamp and property drift' {
        $manifest = New-CddsiSyntheticStageManifest
        Add-Member -InputObject $manifest -NotePropertyName RawConfig -NotePropertyValue '{}'
        (Test-CddsiStageManifest -Manifest $manifest) | Should -BeFalse
        (Test-CddsiStageManifest -Manifest ([pscustomobject]@{ SchemaVersion = 1 })) | Should -BeFalse

        $manifest = New-CddsiSyntheticStageManifest
        $manifest.SchemaVersion = 2
        (Test-CddsiStageManifest -Manifest $manifest) | Should -BeFalse
        $manifest = New-CddsiSyntheticStageManifest
        $manifest.ArtifactSha256 = ('B' * 64)
        (Test-CddsiStageManifest -Manifest $manifest) | Should -BeFalse
        $manifest = New-CddsiSyntheticStageManifest
        $manifest.SidecarSha256 = $manifest.ArtifactSha256
        (Test-CddsiStageManifest -Manifest $manifest) | Should -BeFalse
        $manifest = New-CddsiSyntheticStageManifest
        $manifest.CreatedAtUtc = '2030-01-01T08:00:00+08:00'
        (Test-CddsiStageManifest -Manifest $manifest) | Should -BeFalse
    }
}

Describe 'operation grant contract' {
    It 'requires one independent confirmation binding for every allowed operation' {
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeTrue
        @($grant.ConfirmationBindings | Select-Object -ExpandProperty ConfirmationId | Select-Object -Unique).Count | Should -Be 2
        @($grant.ConfirmationBindings | Select-Object -ExpandProperty PromptDigest | Select-Object -Unique).Count | Should -Be 2

        $grant.ConfirmationBindings[1].PromptDigest = $grant.ConfirmationBindings[0].PromptDigest
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $grant.ConfirmationBindings[1].ConfirmationId = $grant.ConfirmationBindings[0].ConfirmationId
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $grant.ConfirmationBindings = @($grant.ConfirmationBindings[0])
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
    }

    It 'confines VmCalibration to exactly the dedicated eight-operation universe' {
        $calibrationOperations = @(
            'InspectEnvironment',
            'AcquireCalibrationArtifacts',
            'VerifyCalibrationArtifacts',
            'CalibrateMsixScope',
            'CalibrateCredentialHelper',
            'CalibrateGit',
            'WriteCalibrationEvidence',
            'CleanupCalibrationResources'
        )
        (Test-CddsiOperationGrant -Grant (New-CddsiSyntheticOperationGrant `
            -ArtifactProfile VmCalibration -AllowedOperations $calibrationOperations)) | Should -BeTrue
        (Test-CddsiOperationGrant -Grant (New-CddsiSyntheticOperationGrant `
            -ArtifactProfile VmCalibration -AllowedOperations @('EnsureGit'))) | Should -BeFalse
        (Test-CddsiOperationGrant -Grant (New-CddsiSyntheticOperationGrant `
            -ArtifactProfile VmAcceptance -AllowedOperations @('CalibrateGit'))) | Should -BeFalse
        (Test-CddsiOperationGrant -Grant (New-CddsiSyntheticOperationGrant `
            -ArtifactProfile VmCalibration -AllowedOperations @('CalibrateMsixScope', 'CalibrateUnknown'))) | Should -BeFalse
    }

    It 'rejects arbitrary identifier payloads schema drift and invalid lifetime or reuse flags' {
        $grant = New-CddsiSyntheticOperationGrant
        Add-Member -InputObject $grant -NotePropertyName ApiKey -NotePropertyValue '<forbidden>'
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        (Test-CddsiOperationGrant -Grant ([pscustomobject]@{ SchemaVersion = 1 })) | Should -BeFalse

        foreach ($property in @('GrantId', 'Nonce', 'RunId')) {
            $grant = New-CddsiSyntheticOperationGrant
            $grant.$property = 'attacker-controlled-payload'
            (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        }
        $grant = New-CddsiSyntheticOperationGrant
        $grant.GrantId = '1a000000-0000-4000-8000-000000000801'.ToUpperInvariant()
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        $grant = New-CddsiSyntheticOperationGrant
        $grant.Nonce = $grant.GrantId
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        $grant = New-CddsiSyntheticOperationGrant
        $grant.ExpiresAtUtc = $grant.IssuedAtUtc
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        $grant = New-CddsiSyntheticOperationGrant
        $grant.SingleUse = $false
        (Test-CddsiOperationGrant -Grant $grant) | Should -BeFalse
        (Test-CddsiOperationGrant -Grant (New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'EnsureGit'))) | Should -BeFalse
    }
}

Describe 'single-use workflow claim reducer' {
    It 'reduces AVAILABLE to a package-bound CLAIMED authorization session' {
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $result = Resolve-CddsiGrantClaim -OperationGrant $grant `
            -ClaimState (New-CddsiSyntheticClaimState -Grant $grant) `
            -ClaimId '40000000-0000-4000-8000-000000000801' -ExpectedRevision 0 `
            -NowUtc '2030-01-01T00:02:00Z'

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Success | Should -BeTrue
        $result.Changed | Should -BeFalse
        $result.Data.Claimed | Should -BeTrue
        $result.Data.PreviousState | Should -BeExactly 'AVAILABLE'
        $result.Data.NextState | Should -BeExactly 'CLAIMED'
        $result.Data.RequiresAtomicCompareAndSwap | Should -BeTrue
        $result.Data.PreviousRevision | Should -Be 0
        $result.Data.NextRevision | Should -Be 1
        (Test-CddsiAuthorizationSession -AuthorizationSession $result.Data.AuthorizationSession) | Should -BeTrue
        $result.Data.AuthorizationSession.GrantId | Should -BeExactly $grant.GrantId
        $result.Data.AuthorizationSession.RunId | Should -BeExactly $grant.RunId
        $result.Data.AuthorizationSession.ArtifactSha256 | Should -BeExactly $grant.ArtifactSha256
        $result.Data.AuthorizationSession.ArtifactProfile | Should -BeExactly $grant.ArtifactProfile
        $result.Data.AuthorizationSession.ClaimId | Should -BeExactly '40000000-0000-4000-8000-000000000801'
        $result.Data.AuthorizationSession.ExpiresAtUtc | Should -BeExactly $grant.ExpiresAtUtc
    }

    It 'fails closed on replay concurrent stale revision terminal state and expiry' {
        $grant = New-CddsiSyntheticOperationGrant
        $cases = @(
            [pscustomobject]@{ State = (New-CddsiSyntheticClaimState -Grant $grant -State CLAIMED); Revision = 1; Now = '2030-01-01T00:10:00Z'; Code = 'GRANT_CLAIM_REPLAY' },
            [pscustomobject]@{ State = (New-CddsiSyntheticClaimState -Grant $grant); Revision = 1; Now = '2030-01-01T00:10:00Z'; Code = 'GRANT_CLAIM_CONCURRENCY_CONFLICT' },
            [pscustomobject]@{ State = (New-CddsiSyntheticClaimState -Grant $grant -State COMPLETED); Revision = 1; Now = '2030-01-01T00:10:00Z'; Code = 'GRANT_CLAIM_TERMINAL' },
            [pscustomobject]@{ State = (New-CddsiSyntheticClaimState -Grant $grant -State ABORTED); Revision = 1; Now = '2030-01-01T00:10:00Z'; Code = 'GRANT_CLAIM_TERMINAL' },
            [pscustomobject]@{ State = (New-CddsiSyntheticClaimState -Grant $grant -State EXPIRED); Revision = 1; Now = '2030-01-01T00:10:00Z'; Code = 'GRANT_CLAIM_TERMINAL' },
            [pscustomobject]@{ State = (New-CddsiSyntheticClaimState -Grant $grant); Revision = 0; Now = '2030-01-01T01:00:00Z'; Code = 'GRANT_CLAIM_EXPIRED' }
        )
        foreach ($case in $cases) {
            $result = Resolve-CddsiGrantClaim -OperationGrant $grant -ClaimState $case.State `
                -ClaimId '40000000-0000-4000-8000-000000000801' `
                -ExpectedRevision $case.Revision -NowUtc $case.Now
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            $result.Data.Claimed | Should -BeFalse
            $result.Data.RequiresAtomicCompareAndSwap | Should -BeFalse
            $result.Data.AuthorizationSession | Should -BeNullOrEmpty
            @($result.Data.ReasonCodes) | Should -Contain $case.Code
        }
    }

    It 'rejects forged claim bindings arbitrary claim identifiers and identifier collisions' {
        $grant = New-CddsiSyntheticOperationGrant
        foreach ($property in @('GrantId', 'Nonce', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'ArtifactProfile', 'ExpiresAtUtc')) {
            $state = New-CddsiSyntheticClaimState -Grant $grant
            switch ($property) {
                'GrantId' { $state.GrantId = '10000000-0000-4000-8000-000000000802' }
                'Nonce' { $state.Nonce = '30000000-0000-4000-8000-000000000802' }
                'RunId' { $state.RunId = '20000000-0000-4000-8000-000000000802' }
                'ArtifactSha256' { $state.ArtifactSha256 = ('e' * 64) }
                'SidecarSha256' { $state.SidecarSha256 = ('e' * 64) }
                'ContentDigest' { $state.ContentDigest = ('e' * 64) }
                'ArtifactProfile' { $state.ArtifactProfile = 'UserLive' }
                'ExpiresAtUtc' { $state.ExpiresAtUtc = '2030-01-01T00:59:00Z' }
            }
            $result = Resolve-CddsiGrantClaim -OperationGrant $grant -ClaimState $state `
                -ClaimId '40000000-0000-4000-8000-000000000801' -ExpectedRevision 0 `
                -NowUtc '2030-01-01T00:10:00Z'
            @($result.Data.ReasonCodes) | Should -Contain 'GRANT_CLAIM_BINDING_MISMATCH'
        }

        foreach ($claimId in @(
            'claim-attacker-payload',
            $grant.GrantId,
            $grant.Nonce,
            $grant.RunId,
            $grant.ConfirmationBindings[0].ConfirmationId
        )) {
            $result = Resolve-CddsiGrantClaim -OperationGrant $grant `
                -ClaimState (New-CddsiSyntheticClaimState -Grant $grant) `
                -ClaimId $claimId -ExpectedRevision 0 -NowUtc '2030-01-01T00:10:00Z'
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            @($result.Data.ReasonCodes) | Should -Contain $(if ($claimId -ceq 'claim-attacker-payload') { 'CLAIM_ID_INVALID' } else { 'CLAIM_ID_COLLISION' })
        }
    }

    It 'requires exact claim and session schemas' {
        $grant = New-CddsiSyntheticOperationGrant
        $state = New-CddsiSyntheticClaimState -Grant $grant
        Add-Member -InputObject $state -NotePropertyName RawStoreValue -NotePropertyValue '{}'
        (Test-CddsiGrantClaimState -ClaimState $state) | Should -BeFalse
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        Add-Member -InputObject $session -NotePropertyName Consumed -NotePropertyValue $false
        (Test-CddsiAuthorizationSession -AuthorizationSession $session) | Should -BeFalse
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $session.State = 'AVAILABLE'
        (Test-CddsiAuthorizationSession -AuthorizationSession $session) | Should -BeFalse
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $session.ClaimId = 'claim-attacker-payload'
        (Test-CddsiAuthorizationSession -AuthorizationSession $session) | Should -BeFalse
        $state = New-CddsiSyntheticClaimState -Grant $grant -State CLAIMED
        $state.ClaimId = $state.GrantId
        (Test-CddsiGrantClaimState -ClaimState $state) | Should -BeFalse
    }
}

Describe 'claimed workflow operation authorization' {
    It 'proposes distinct CAS claims for different granted operations without making either executable' {
        $runId = '20000000-0000-4000-8000-000000000801'
        $grant = New-CddsiSyntheticOperationGrant -RunId $runId -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $manifest = New-CddsiSyntheticStageManifest
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $confirmationIds = @()
        foreach ($operation in @('EnsureGit', 'RestoreGitState')) {
            $confirmation = New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session -Operation $operation
            $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
                -Session $session -Workflow $workflow -Operation $operation
            $operationUseId = Get-CddsiSyntheticOperationUseId -Grant $grant -Operation $operation
            $confirmationIds += $confirmation.ConfirmationId
            $result = Resolve-CddsiOperationAuthorization `
                -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $session `
                -WorkflowSessionState $workflow -OperationUseState $available `
                -Confirmation $confirmation -Operation $operation -OperationUseId $operationUseId `
                -ExpectedRevision 0 -RunId $runId `
                -NowUtc '2030-01-01T00:10:00Z'
            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.Data.AuthorizationProposed | Should -BeTrue
            $result.Data.Authorized | Should -BeFalse
            $result.Data.Executable | Should -BeFalse
            $result.Data.Committed | Should -BeFalse
            $result.Data.RequiresAtomicCompareAndSwap | Should -BeTrue
            $result.Data.ProviderExecutionAllowedBeforeCommit | Should -BeFalse
            $result.Data.ProposedOperationUseState.OperationUseId | Should -BeExactly $operationUseId
            $result.Data.ProposedOperationUseState.ConfirmationId | Should -BeExactly $confirmation.ConfirmationId
            @($result.Data.ReasonCodes).Count | Should -Be 0
        }
        @($confirmationIds | Select-Object -Unique).Count | Should -Be 2
    }

    It 'prevents one operation confirmation from masquerading as another' {
        $runId = '20000000-0000-4000-8000-000000000801'
        $grant = New-CddsiSyntheticOperationGrant -RunId $runId -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $manifest = New-CddsiSyntheticStageManifest
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation RestoreGitState
        $operationUseId = Get-CddsiSyntheticOperationUseId -Grant $grant -Operation RestoreGitState
        $confirmation = New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session -Operation EnsureGit

        $result = Resolve-CddsiOperationAuthorization -StageManifest $manifest `
            -OperationGrant $grant -AuthorizationSession $session -WorkflowSessionState $workflow `
            -OperationUseState $available -Confirmation $confirmation -Operation RestoreGitState `
            -OperationUseId $operationUseId -ExpectedRevision 0 -RunId $runId -NowUtc '2030-01-01T00:10:00Z'
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        @($result.Data.ReasonCodes) | Should -Contain 'CONFIRMATION_BINDING_MISMATCH'

        $confirmation.Operation = 'RestoreGitState'
        $result = Resolve-CddsiOperationAuthorization -StageManifest $manifest `
            -OperationGrant $grant -AuthorizationSession $session -WorkflowSessionState $workflow `
            -OperationUseState $available -Confirmation $confirmation -Operation RestoreGitState `
            -OperationUseId $operationUseId -ExpectedRevision 0 -RunId $runId -NowUtc '2030-01-01T00:10:00Z'
        @($result.Data.ReasonCodes) | Should -Contain 'CONFIRMATION_BINDING_MISMATCH'

        $restoreBinding = @($grant.ConfirmationBindings | Where-Object Operation -CEQ 'RestoreGitState')[0]
        $confirmation.PromptDigest = $restoreBinding.PromptDigest
        $result = Resolve-CddsiOperationAuthorization -StageManifest $manifest `
            -OperationGrant $grant -AuthorizationSession $session -WorkflowSessionState $workflow `
            -OperationUseState $available -Confirmation $confirmation -Operation RestoreGitState `
            -OperationUseId $operationUseId -ExpectedRevision 0 -RunId $runId -NowUtc '2030-01-01T00:10:00Z'
        @($result.Data.ReasonCodes) | Should -Contain 'CONFIRMATION_BINDING_MISMATCH'
    }

    It 'binds every confirmation to the claimed session and rejects cross-claim replay' {
        $runId = '20000000-0000-4000-8000-000000000801'
        $grant = New-CddsiSyntheticOperationGrant -RunId $runId
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $manifest = New-CddsiSyntheticStageManifest
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $operationUseId = Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit
        $confirmation = New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session
        $confirmation.ClaimId = '40000000-0000-4000-8000-000000000802'

        $result = Resolve-CddsiOperationAuthorization -StageManifest $manifest `
            -OperationGrant $grant -AuthorizationSession $session -WorkflowSessionState $workflow `
            -OperationUseState $available -Confirmation $confirmation -Operation EnsureGit `
            -OperationUseId $operationUseId -ExpectedRevision 0 -RunId $runId -NowUtc '2030-01-01T00:10:00Z'
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        @($result.Data.ReasonCodes) | Should -Contain 'CONFIRMATION_BINDING_MISMATCH'
    }

    It 'fails closed on invalid session package run operation confirmation and time bindings' {
        $runId = '20000000-0000-4000-8000-000000000801'
        $cases = @(
            [pscustomobject]@{ Code = 'AUTHORIZATION_SESSION_INVALID'; Mutate = { param($manifest, $grant, $session, $confirmation) $session.State = 'COMPLETED' } },
            [pscustomobject]@{ Code = 'AUTHORIZATION_SESSION_BINDING_MISMATCH'; Mutate = { param($manifest, $grant, $session, $confirmation) $session.ArtifactSha256 = ('e' * 64) } },
            [pscustomobject]@{ Code = 'ARTIFACT_HASH_MISMATCH'; Mutate = { param($manifest, $grant, $session, $confirmation) $manifest.ArtifactSha256 = ('e' * 64) } },
            [pscustomobject]@{ Code = 'SIDECAR_HASH_MISMATCH'; Mutate = { param($manifest, $grant, $session, $confirmation) $manifest.SidecarSha256 = ('e' * 64) } },
            [pscustomobject]@{ Code = 'RUN_ID_MISMATCH'; Mutate = { param($manifest, $grant, $session, $confirmation) $grant.RunId = '20000000-0000-4000-8000-000000000802' } },
            [pscustomobject]@{ Code = 'CONFIRMATION_INVALID'; Mutate = { param($manifest, $grant, $session, $confirmation) $confirmation.Confirmed = $false } },
            [pscustomobject]@{ Code = 'CONFIRMATION_TIME_INVALID'; Mutate = { param($manifest, $grant, $session, $confirmation) $confirmation.ConfirmedAtUtc = '2030-01-01T00:01:00Z' } },
            [pscustomobject]@{ Code = 'AUTHORIZATION_SESSION_EXPIRED'; Now = '2030-01-01T01:00:00Z'; Mutate = { param($manifest, $grant, $session, $confirmation) } }
        )
        foreach ($case in $cases) {
            $manifest = New-CddsiSyntheticStageManifest
            $grant = New-CddsiSyntheticOperationGrant -RunId $runId
            $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
            $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
            $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
                -Session $session -Workflow $workflow -Operation EnsureGit
            $operationUseId = Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit
            $confirmation = New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session
            & $case.Mutate $manifest $grant $session $confirmation
            $now = if ($case.PSObject.Properties.Name -contains 'Now') { $case.Now } else { '2030-01-01T00:10:00Z' }
            $result = Resolve-CddsiOperationAuthorization -StageManifest $manifest `
                -OperationGrant $grant -AuthorizationSession $session -WorkflowSessionState $workflow `
                -OperationUseState $available -Confirmation $confirmation -Operation EnsureGit `
                -OperationUseId $operationUseId -ExpectedRevision 0 -RunId $runId -NowUtc $now
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            @($result.Data.ReasonCodes) | Should -Contain $case.Code
        }
    }

    It 'cannot authorize Scaffold Development or cross-profile calibration operations' {
        foreach ($stage in @('Scaffold', 'Development')) {
            $grant = New-CddsiSyntheticOperationGrant
            $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
            $boundManifest = New-CddsiSyntheticStageManifest
            $workflow = New-CddsiSyntheticWorkflowState -Manifest $boundManifest -Grant $grant -Session $session
            $available = New-CddsiSyntheticAvailableOperationUse -Manifest $boundManifest -Grant $grant `
                -Session $session -Workflow $workflow -Operation EnsureGit
            $result = Resolve-CddsiOperationAuthorization -StageManifest (New-CddsiSyntheticStageManifest -Stage $stage) `
                -OperationGrant $grant -AuthorizationSession $session -WorkflowSessionState $workflow `
                -OperationUseState $available `
                -Confirmation (New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session) `
                -Operation EnsureGit -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit) `
                -ExpectedRevision 0 -RunId $grant.RunId -NowUtc '2030-01-01T00:10:00Z'
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            @($result.Data.ReasonCodes) | Should -Contain 'PROFILE_BINDING_MISMATCH'
        }
    }

    It 'exposes only pure policy parameters and no system-I/O path' {
        foreach ($name in @(
            'Test-CddsiStageManifest',
            'Test-CddsiOperationGrant',
            'Test-CddsiGrantClaimState',
            'Test-CddsiAuthorizationSession',
            'Resolve-CddsiGrantClaim',
            'Test-CddsiStageGrantSessionBinding',
            'Get-CddsiWorkflowOperationSetDigest',
            'Test-CddsiGrantCompensationOperation',
            'New-CddsiWorkflowSessionState',
            'Test-CddsiWorkflowSessionState',
            'Test-CddsiWorkflowSessionBinding',
            'New-CddsiOperationUseState',
            'Test-CddsiOperationUseState',
            'Test-CddsiOperationUseBinding',
            'Resolve-CddsiOperationAuthorizationBinding',
            'Resolve-CddsiOperationAuthorization',
            'Test-CddsiCommittedOperationUseReceipt',
            'Test-CddsiTerminalOperationUseReceipt',
            'Resolve-CddsiOperationUseTerminal',
            'Resolve-CddsiUnexecutedOperationUseAbort',
            'Resolve-CddsiWorkflowSessionTerminal'
        )) {
            (Get-Command $name).Parameters.Keys -contains 'Mode' | Should -BeFalse
            (Get-Command $name).Parameters.Keys -contains 'ExecutionContext' | Should -BeFalse
            (Get-Command $name).Parameters.Keys -contains 'Context' | Should -BeFalse
        }

        $path = Join-Path $script:RepoRoot 'lib\stage-policy.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $source = [System.IO.File]::ReadAllText($path)
        $source | Should -Not -Match '(?i)\$env:'
        $source | Should -Not -Match '(?i)\[Environment\]::'
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) |
            ForEach-Object { $_.GetCommandName() })
        foreach ($forbidden in @(
            'Get-Item', 'Test-Path', 'Get-ChildItem', 'Get-Content', 'Set-Content',
            'Invoke-WebRequest', 'Start-Process', 'Get-Process', 'Stop-Process',
            'Get-AppxPackage', 'Add-AppxPackage', 'Get-ItemProperty', 'Set-ItemProperty',
            'Enable-WindowsOptionalFeature', 'Get-Credential', 'New-Object'
        )) {
            $commands -ccontains $forbidden | Should -BeFalse
        }
    }
}

Describe 'operation-use and workflow terminal CAS contracts' {
    It 'creates independent slots for ResumeCowork and credential compensation' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @(
            'PersistCredential', 'RestoreCredentialState', 'ResumeCowork'
        )
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $states = @()
        foreach ($operation in @($grant.AllowedOperations)) {
            $state = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
                -Session $session -Workflow $workflow -Operation $operation
            (Test-CddsiOperationUseState -OperationUseState $state) | Should -BeTrue
            $state.Operation | Should -BeExactly $operation
            $states += $state
        }
        @($states | Select-Object -ExpandProperty StateKeySha256 | Select-Object -Unique).Count | Should -Be 3
        @($states | Select-Object -ExpandProperty ConfirmationId | Select-Object -Unique).Count | Should -Be 3
    }

    It 'rejects the same confirmation twice stale revision and cross-operation state reuse' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $confirmation = New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session -Operation EnsureGit
        $operationUseId = Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit
        $proposal = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $available `
            -Confirmation $confirmation -Operation EnsureGit -OperationUseId $operationUseId `
            -ExpectedRevision 0 -RunId $grant.RunId -NowUtc '2030-01-01T00:10:00Z'
        $claimed = $proposal.Data.ProposedOperationUseState

        $replay = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $claimed `
            -Confirmation $confirmation -Operation EnsureGit -OperationUseId $operationUseId `
            -ExpectedRevision 1 -RunId $grant.RunId -NowUtc '2030-01-01T00:11:00Z'
        $replay.Data.AuthorizationProposed | Should -BeFalse
        @($replay.Data.ReasonCodes) | Should -Contain 'OPERATION_USE_REPLAY'

        $stale = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $available `
            -Confirmation $confirmation -Operation EnsureGit -OperationUseId $operationUseId `
            -ExpectedRevision 1 -RunId $grant.RunId -NowUtc '2030-01-01T00:11:00Z'
        @($stale.Data.ReasonCodes) | Should -Contain 'OPERATION_USE_CONCURRENCY_CONFLICT'

        $crossOperation = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $available `
            -Confirmation (New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session -Operation RestoreGitState) `
            -Operation RestoreGitState -OperationUseId $operationUseId -ExpectedRevision 0 `
            -RunId $grant.RunId -NowUtc '2030-01-01T00:11:00Z'
        @($crossOperation.Data.ReasonCodes) | Should -Contain 'OPERATION_USE_BINDING_MISMATCH'
    }

    It 'requires the CAS-committed CLAIMED receipt before provider execution' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $claimed = New-CddsiSyntheticClaimedOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit

        (Test-CddsiCommittedOperationUseReceipt -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $available `
            -Operation EnsureGit -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit) `
            -ValidationTimeUtc '2030-01-01T00:11:00Z') | Should -BeFalse
        (Test-CddsiCommittedOperationUseReceipt -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $claimed `
            -Operation EnsureGit -OperationUseId $claimed.OperationUseId `
            -ValidationTimeUtc '2030-01-01T00:11:00Z') | Should -BeTrue
        $claimed.ProviderIdempotencyRequired | Should -BeTrue
        $claimed.IdempotencyKey | Should -BeNullOrEmpty
    }

    It 'terminalizes once returns the identical receipt idempotently and rejects conflicts' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $claimed = New-CddsiSyntheticClaimedOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $key = Get-CddsiSyntheticOperationIdempotencyKey -Grant $grant -Operation EnsureGit
        $arguments = @{
            StageManifest = $manifest; OperationGrant = $grant; AuthorizationSession = $session
            WorkflowSessionState = $workflow; OperationUseState = $claimed; Operation = 'EnsureGit'
            OperationUseId = $claimed.OperationUseId; ExpectedRevision = 1; Outcome = 'COMPLETED'
            ProviderEvidenceDigest = ('8' * 64); OccurredAtUtc = '2030-01-01T00:20:00Z'
            IdempotencyKey = $key; TerminalReasonCode = ''
        }
        $first = Resolve-CddsiOperationUseTerminal @arguments
        $first.Data.Terminalized | Should -BeTrue
        $first.Data.RequiresAtomicCompareAndSwap | Should -BeTrue
        $terminal = $first.Data.TerminalOperationUseState
        (Test-CddsiTerminalOperationUseReceipt -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $terminal `
            -Operation EnsureGit -OperationUseId $claimed.OperationUseId -Outcome COMPLETED `
            -ExpectedProviderEvidenceDigest ('8' * 64)) | Should -BeTrue

        $arguments.OperationUseState = $terminal
        $same = Resolve-CddsiOperationUseTerminal @arguments
        $same.Status | Should -BeExactly 'SUCCEEDED'
        $same.Data.IdempotentReplay | Should -BeTrue
        $same.Data.RequiresAtomicCompareAndSwap | Should -BeFalse
        $same.Data.TerminalOperationUseState.ReceiptBindingToken | Should -BeExactly $terminal.ReceiptBindingToken

        $arguments.ProviderEvidenceDigest = ('9' * 64)
        $conflict = Resolve-CddsiOperationUseTerminal @arguments
        $conflict.Status | Should -BeExactly 'ACTION_REQUIRED'
        @($conflict.Data.ReasonCodes) | Should -Contain 'OPERATION_USE_IDEMPOTENCY_CONFLICT'
        $arguments.ProviderEvidenceDigest = ('8' * 64)
        $arguments.IdempotencyKey = '70000000-0000-4000-8000-000000000099'
        $otherKey = Resolve-CddsiOperationUseTerminal @arguments
        @($otherKey.Data.ReasonCodes) | Should -Contain 'OPERATION_USE_TERMINAL_REPLAY'
    }

    It 'rejects stale terminalization and tampered provider evidence receipts' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $claimed = New-CddsiSyntheticClaimedOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $stale = Resolve-CddsiOperationUseTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $claimed `
            -Operation EnsureGit -OperationUseId $claimed.OperationUseId -ExpectedRevision 0 `
            -Outcome COMPLETED -ProviderEvidenceDigest ('8' * 64) -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey (Get-CddsiSyntheticOperationIdempotencyKey -Grant $grant -Operation EnsureGit)
        @($stale.Data.ReasonCodes) | Should -Contain 'OPERATION_USE_CONCURRENCY_CONFLICT'

        $terminal = New-CddsiSyntheticTerminalOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $terminal.ProviderEvidenceDigest = ('9' * 64)
        (Test-CddsiTerminalOperationUseReceipt -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $terminal `
            -Operation EnsureGit -OperationUseId $terminal.OperationUseId -Outcome COMPLETED `
            -ExpectedProviderEvidenceDigest ('9' * 64)) | Should -BeFalse
    }

    It 'requires every operation terminal and prevents authorization after workflow completion' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $states = @(
            (New-CddsiSyntheticTerminalOperationUse -Manifest $manifest -Grant $grant -Session $session -Workflow $workflow -Operation EnsureGit),
            (New-CddsiSyntheticUnexecutedAbort -Manifest $manifest -Grant $grant -Session $session -Workflow $workflow -Operation RestoreGitState -ReasonCode NOT_REQUIRED)
        )
        $workflowKey = '80000000-0000-4000-8000-000000000001'
        $result = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseStates $states `
            -ExpectedRevision $workflow.Revision -Outcome COMPLETED -OccurredAtUtc '2030-01-01T00:30:00Z' `
            -IdempotencyKey $workflowKey
        $result.Data.Terminalized | Should -BeTrue
        $terminalWorkflow = $result.Data.TerminalWorkflowSessionState
        (Test-CddsiWorkflowSessionState -WorkflowSessionState $terminalWorkflow) | Should -BeTrue

        $same = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $terminalWorkflow -OperationUseStates $states `
            -ExpectedRevision $workflow.Revision -Outcome COMPLETED -OccurredAtUtc '2030-01-01T00:30:00Z' `
            -IdempotencyKey $workflowKey
        $same.Data.IdempotentReplay | Should -BeTrue
        $same.Data.TerminalWorkflowSessionState.ReceiptBindingToken | Should -BeExactly $terminalWorkflow.ReceiptBindingToken

        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $blocked = Resolve-CddsiOperationAuthorization -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $terminalWorkflow -OperationUseState $available `
            -Confirmation (New-CddsiSyntheticInteractiveConfirmation -Grant $grant -Session $session -Operation EnsureGit) `
            -Operation EnsureGit -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit) `
            -ExpectedRevision 0 -RunId $grant.RunId -NowUtc '2030-01-01T00:31:00Z'
        @($blocked.Data.ReasonCodes) | Should -Contain 'WORKFLOW_SESSION_TERMINAL'

        $missing = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseStates @($states[0]) `
            -ExpectedRevision $workflow.Revision -Outcome COMPLETED -OccurredAtUtc '2030-01-01T00:30:00Z' `
            -IdempotencyKey '80000000-0000-4000-8000-000000000002'
        @($missing.Data.ReasonCodes) | Should -Contain 'TERMINAL_OPERATION_SET_INCOMPLETE'
    }

    It 'requires explicit aborted-operation semantics for an aborted workflow' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        $completed = New-CddsiSyntheticTerminalOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $aborted = New-CddsiSyntheticTerminalOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation RestoreGitState -Outcome ABORTED `
            -TerminalReasonCode COMPENSATION_FAILED
        $result = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseStates @($completed, $aborted) `
            -ExpectedRevision $workflow.Revision -Outcome ABORTED -OccurredAtUtc '2030-01-01T00:30:00Z' `
            -IdempotencyKey '80000000-0000-4000-8000-000000000003' `
            -TerminalReasonCode COMPENSATION_FAILED
        $result.Data.Terminalized | Should -BeTrue
        $result.Data.TerminalWorkflowSessionState.State | Should -BeExactly 'ABORTED'

        $invalidCompletion = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseStates @($completed, $aborted) `
            -ExpectedRevision $workflow.Revision -Outcome COMPLETED -OccurredAtUtc '2030-01-01T00:30:00Z' `
            -IdempotencyKey '80000000-0000-4000-8000-000000000004'
        @($invalidCompletion.Data.ReasonCodes) | Should -Contain 'WORKFLOW_COMPLETION_REQUIRES_COMPLETED_OR_UNUSED_COMPENSATION'
    }

    It 'closes never-started operations without confirmation or provider evidence and only skips fixed compensation' {
        $manifest = New-CddsiSyntheticStageManifest
        $grant = New-CddsiSyntheticOperationGrant -AllowedOperations @('EnsureGit', 'RestoreGitState')
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session

        $forwardAvailable = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit
        $invalidSkip = Resolve-CddsiUnexecutedOperationUseAbort -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $forwardAvailable `
            -Operation EnsureGit -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $grant -Operation EnsureGit) `
            -ExpectedRevision 0 -ReasonCode NOT_REQUIRED -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey (Get-CddsiSyntheticOperationIdempotencyKey -Grant $grant -Operation EnsureGit)
        @($invalidSkip.Data.ReasonCodes) | Should -Contain 'NOT_REQUIRED_OPERATION_NOT_COMPENSATION'

        $forwardAbort = New-CddsiSyntheticUnexecutedAbort -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation EnsureGit -ReasonCode NOT_RUN_DUE_TO_ABORT
        $compensationAbort = New-CddsiSyntheticUnexecutedAbort -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation RestoreGitState -ReasonCode NOT_RUN_DUE_TO_ABORT
        foreach ($state in @($forwardAbort, $compensationAbort)) {
            $state.State | Should -BeExactly 'ABORTED'
            $state.ConfirmationConsumed | Should -BeFalse
            $state.ProviderInvocationOccurred | Should -BeFalse
            $state.ProviderEvidenceDigest | Should -BeNullOrEmpty
            $state.ConfirmedAtUtc | Should -BeNullOrEmpty
            $state.ClaimedAtUtc | Should -BeNullOrEmpty
        }
        $workflowAbort = Resolve-CddsiWorkflowSessionTerminal -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow `
            -OperationUseStates @($forwardAbort, $compensationAbort) -ExpectedRevision $workflow.Revision `
            -Outcome ABORTED -OccurredAtUtc '2030-01-01T00:30:00Z' `
            -IdempotencyKey '80000000-0000-4000-8000-000000000005' -TerminalReasonCode USER_CANCELLED
        $workflowAbort.Data.Terminalized | Should -BeTrue

        $same = Resolve-CddsiUnexecutedOperationUseAbort -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow `
            -OperationUseState $compensationAbort -Operation RestoreGitState `
            -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $grant -Operation RestoreGitState) `
            -ExpectedRevision 0 -ReasonCode NOT_RUN_DUE_TO_ABORT -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey (Get-CddsiSyntheticOperationIdempotencyKey -Grant $grant -Operation RestoreGitState)
        $same.Data.IdempotentReplay | Should -BeTrue
        $same.Data.TerminalOperationUseState.ReceiptBindingToken | Should -BeExactly $compensationAbort.ReceiptBindingToken
    }

    It 'does not classify any P10A calibration operation as optional compensation' {
        $operations = @(
            'InspectEnvironment', 'AcquireCalibrationArtifacts', 'VerifyCalibrationArtifacts',
            'CalibrateMsixScope', 'CalibrateCredentialHelper', 'CalibrateGit',
            'WriteCalibrationEvidence', 'CleanupCalibrationResources'
        )
        $manifest = New-CddsiSyntheticStageManifest -Stage VmCalibration
        $grant = New-CddsiSyntheticOperationGrant -ArtifactProfile VmCalibration -AllowedOperations $operations
        $session = New-CddsiSyntheticAuthorizationSession -Grant $grant
        $workflow = New-CddsiSyntheticWorkflowState -Manifest $manifest -Grant $grant -Session $session
        foreach ($operation in $operations) {
            (Test-CddsiGrantCompensationOperation -OperationGrant $grant -Operation $operation) | Should -BeFalse
        }
        $available = New-CddsiSyntheticAvailableOperationUse -Manifest $manifest -Grant $grant `
            -Session $session -Workflow $workflow -Operation CleanupCalibrationResources
        $result = Resolve-CddsiUnexecutedOperationUseAbort -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $workflow -OperationUseState $available `
            -Operation CleanupCalibrationResources `
            -OperationUseId (Get-CddsiSyntheticOperationUseId -Grant $grant -Operation CleanupCalibrationResources) `
            -ExpectedRevision 0 -ReasonCode NOT_REQUIRED -OccurredAtUtc '2030-01-01T00:20:00Z' `
            -IdempotencyKey (Get-CddsiSyntheticOperationIdempotencyKey -Grant $grant -Operation CleanupCalibrationResources)
        @($result.Data.ReasonCodes) | Should -Contain 'NOT_REQUIRED_OPERATION_NOT_COMPENSATION'
    }
}
