# stage-policy.ps1 - Pure stage, workflow-claim and confirmation contracts.
# This module never discovers an environment, loads an adapter or performs I/O.

$script:CddsiStandardOperationNames = @(
    'LoadLiveProviders',
    'AcquireArtifacts',
    'VerifyArtifacts',
    'EnsureClaudeDesktop',
    'EnsureGit',
    'PrepareCowork',
    'ResumeCowork',
    'PersistCredential',
    'BackupManagedPolicy',
    'WriteManagedPolicy',
    'RestartDesktop',
    'InvokeAcceptance',
    'WriteReport',
    'RemoveAcquiredArtifacts',
    'RestoreClaudeDesktopState',
    'RestoreGitState',
    'RestoreCoworkState',
    'RemoveCredential',
    'RestoreCredentialState',
    'RemoveManagedPolicyBackup',
    'RestoreManagedPolicy',
    'RestoreDesktopLifecycle',
    'RemoveReport'
)
$script:CddsiCalibrationOperationNames = @(
    'InspectEnvironment',
    'AcquireCalibrationArtifacts',
    'VerifyCalibrationArtifacts',
    'CalibrateMsixScope',
    'CalibrateCredentialHelper',
    'CalibrateGit',
    'WriteCalibrationEvidence',
    'CleanupCalibrationResources'
)
$script:CddsiGrantedOperationNames = @(
    @($script:CddsiStandardOperationNames)
    @($script:CddsiCalibrationOperationNames)
)
$script:CddsiOperationAbortReasonCodes = @(
    'PROVIDER_FAILED',
    'WORKFLOW_ABORTED',
    'NOT_RUN_DUE_TO_ABORT',
    'COMPENSATION_FAILED',
    'NOT_REQUIRED',
    'USER_CANCELLED'
)
$script:CddsiWorkflowAbortReasonCodes = @(
    'OPERATION_ABORTED',
    'COMPENSATION_FAILED',
    'USER_CANCELLED',
    'AUTHORIZATION_ABORTED'
)

function Test-CddsiStageManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]$Manifest
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Manifest -Expected @(
        'SchemaVersion', 'ContractVersion', 'Stage', 'ArtifactProfile',
        'ArtifactVersion', 'CommitId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'CreatedAtUtc'
    ))) {
        return $false
    }
    $schemaVersionOne = (
        (Test-CddsiSchemaVersionOne -Value $Manifest.SchemaVersion) -and
        $Manifest.ContractVersion -is [string] -and
        $Manifest.ContractVersion -ceq 'cddsi-stage-manifest-v1'
    )
    $schemaVersionTwo = (
        ($Manifest.SchemaVersion -is [int] -or $Manifest.SchemaVersion -is [long]) -and
        [long]$Manifest.SchemaVersion -eq 2 -and
        $Manifest.ContractVersion -is [string] -and
        $Manifest.ContractVersion -ceq 'cddsi-stage-manifest-v2'
    )
    if (-not $schemaVersionOne -and -not $schemaVersionTwo) { return $false }

    $profiles = if ($schemaVersionOne) {
        @{
            Scaffold      = 'Scaffold'
            Development   = 'Development'
            VmCalibration = 'VmCalibration'
            VmAcceptance  = 'VmAcceptance'
            UserLive      = 'UserLive'
        }
    }
    else {
        @{
            VmDevelopment = 'VmDevelopment'
        }
    }
    if ($Manifest.Stage -isnot [string] -or -not $profiles.ContainsKey($Manifest.Stage)) { return $false }
    if ($Manifest.ArtifactProfile -isnot [string] -or $Manifest.ArtifactProfile -cne $profiles[$Manifest.Stage]) { return $false }
    if ($Manifest.ArtifactVersion -isnot [string] -or
        -not [regex]::IsMatch($Manifest.ArtifactVersion, '^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)(?:-[A-Za-z0-9][A-Za-z0-9.-]*)?$')) {
        return $false
    }
    if ($Manifest.CommitId -isnot [string] -or -not [regex]::IsMatch($Manifest.CommitId, '^(?:[a-f0-9]{40}|[a-f0-9]{64})$')) { return $false }
    if ($Manifest.ArtifactSha256 -isnot [string] -or -not [regex]::IsMatch($Manifest.ArtifactSha256, '^[a-f0-9]{64}$')) { return $false }
    if ($Manifest.SidecarSha256 -isnot [string] -or -not [regex]::IsMatch($Manifest.SidecarSha256, '^[a-f0-9]{64}$')) { return $false }
    if ($Manifest.ContentDigest -isnot [string] -or -not [regex]::IsMatch($Manifest.ContentDigest, '^[a-f0-9]{64}$')) { return $false }
    if (@(@($Manifest.ArtifactSha256, $Manifest.SidecarSha256, $Manifest.ContentDigest) | Select-Object -Unique).Count -ne 3) { return $false }
    if ($Manifest.CreatedAtUtc -isnot [string] -or
        -not [regex]::IsMatch($Manifest.CreatedAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
        -not (Test-CddsiUtcTimestampValue -Value $Manifest.CreatedAtUtc)) {
        return $false
    }
    return $true
}

function Test-CddsiOperationGrant {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]$Grant
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Grant -Expected @(
        'SchemaVersion', 'ContractVersion', 'GrantId', 'ArtifactSha256',
        'SidecarSha256', 'ContentDigest', 'ArtifactProfile', 'RunId', 'IssuedAtUtc',
        'ExpiresAtUtc', 'Nonce', 'AllowedOperations', 'SingleUse', 'ConfirmationBindings'
    ))) {
        return $false
    }
    if (-not (Test-CddsiSchemaVersionOne -Value $Grant.SchemaVersion)) { return $false }
    if ($Grant.ContractVersion -isnot [string] -or $Grant.ContractVersion -cne 'cddsi-operation-grant-v2') { return $false }

    $uuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    foreach ($uuid in @($Grant.GrantId, $Grant.RunId, $Grant.Nonce)) {
        if ($uuid -isnot [string] -or -not [regex]::IsMatch($uuid, $uuidPattern) -or
            $uuid -ceq '00000000-0000-0000-0000-000000000000') {
            return $false
        }
    }
    if (@(@($Grant.GrantId, $Grant.RunId, $Grant.Nonce) | Select-Object -Unique).Count -ne 3) { return $false }

    foreach ($hash in @($Grant.ArtifactSha256, $Grant.SidecarSha256, $Grant.ContentDigest)) {
        if ($hash -isnot [string] -or -not [regex]::IsMatch($hash, '^[a-f0-9]{64}$')) { return $false }
    }
    if (@(@($Grant.ArtifactSha256, $Grant.SidecarSha256, $Grant.ContentDigest) | Select-Object -Unique).Count -ne 3) { return $false }
    if ($Grant.ArtifactProfile -isnot [string] -or @('VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive') -cnotcontains $Grant.ArtifactProfile) { return $false }

    foreach ($timestamp in @($Grant.IssuedAtUtc, $Grant.ExpiresAtUtc)) {
        if ($timestamp -isnot [string] -or
            -not [regex]::IsMatch($timestamp, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
            -not (Test-CddsiUtcTimestampValue -Value $timestamp)) {
            return $false
        }
    }
    $issuedAt = [DateTimeOffset]::Parse($Grant.IssuedAtUtc)
    $expiresAt = [DateTimeOffset]::Parse($Grant.ExpiresAtUtc)
    if ($expiresAt -le $issuedAt) { return $false }
    if ($Grant.SingleUse -isnot [bool] -or -not $Grant.SingleUse) { return $false }
    if ($Grant.AllowedOperations -isnot [System.Array] -or @($Grant.AllowedOperations).Count -eq 0) { return $false }

    $profileOperations = if ($Grant.ArtifactProfile -ceq 'VmCalibration') {
        $script:CddsiCalibrationOperationNames
    }
    else {
        $script:CddsiStandardOperationNames
    }
    $seenOperations = @{}
    foreach ($operation in @($Grant.AllowedOperations)) {
        if ($operation -isnot [string] -or $profileOperations -cnotcontains $operation) { return $false }
        if ($seenOperations.ContainsKey($operation)) { return $false }
        $seenOperations[$operation] = $true
    }

    if ($Grant.ConfirmationBindings -isnot [System.Array] -or
        @($Grant.ConfirmationBindings).Count -ne @($Grant.AllowedOperations).Count) {
        return $false
    }
    $seenBindingOperations = @{}
    $seenPromptDigests = @{}
    $seenConfirmationIds = @{}
    foreach ($binding in @($Grant.ConfirmationBindings)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $binding -Expected @(
            'SchemaVersion', 'ContractVersion', 'ConfirmationId', 'Operation', 'PromptDigest', 'Required'
        ))) {
            return $false
        }
        if (-not (Test-CddsiSchemaVersionOne -Value $binding.SchemaVersion)) { return $false }
        if ($binding.ContractVersion -isnot [string] -or
            $binding.ContractVersion -cne 'cddsi-operation-confirmation-binding-v1') {
            return $false
        }
        if ($binding.ConfirmationId -isnot [string] -or
            -not [regex]::IsMatch($binding.ConfirmationId, $uuidPattern) -or
            $binding.ConfirmationId -ceq '00000000-0000-0000-0000-000000000000' -or
            @($Grant.GrantId, $Grant.RunId, $Grant.Nonce) -ccontains $binding.ConfirmationId -or
            $seenConfirmationIds.ContainsKey($binding.ConfirmationId)) {
            return $false
        }
        $seenConfirmationIds[$binding.ConfirmationId] = $true
        if ($binding.Operation -isnot [string] -or @($Grant.AllowedOperations) -cnotcontains $binding.Operation) { return $false }
        if ($seenBindingOperations.ContainsKey($binding.Operation)) { return $false }
        $seenBindingOperations[$binding.Operation] = $true
        if ($binding.PromptDigest -isnot [string] -or
            -not [regex]::IsMatch($binding.PromptDigest, '^[a-f0-9]{64}$') -or
            $seenPromptDigests.ContainsKey($binding.PromptDigest)) {
            return $false
        }
        $seenPromptDigests[$binding.PromptDigest] = $true
        if ($binding.Required -isnot [bool] -or -not $binding.Required) { return $false }
    }
    foreach ($operation in @($Grant.AllowedOperations)) {
        if (-not $seenBindingOperations.ContainsKey($operation)) { return $false }
    }
    return $true
}

function Test-CddsiGrantClaimState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]$ClaimState
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ClaimState -Expected @(
        'SchemaVersion', 'ContractVersion', 'State', 'GrantId', 'Nonce', 'RunId',
        'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'ArtifactProfile',
        'ClaimId', 'ClaimedAtUtc', 'ExpiresAtUtc', 'Revision'
    ))) {
        return $false
    }
    if (-not (Test-CddsiSchemaVersionOne -Value $ClaimState.SchemaVersion)) { return $false }
    if ($ClaimState.ContractVersion -isnot [string] -or $ClaimState.ContractVersion -cne 'cddsi-grant-claim-state-v1') { return $false }
    if ($ClaimState.State -isnot [string] -or @('AVAILABLE', 'CLAIMED', 'COMPLETED', 'ABORTED', 'EXPIRED') -cnotcontains $ClaimState.State) { return $false }

    $uuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    foreach ($uuid in @($ClaimState.GrantId, $ClaimState.Nonce, $ClaimState.RunId)) {
        if ($uuid -isnot [string] -or -not [regex]::IsMatch($uuid, $uuidPattern) -or
            $uuid -ceq '00000000-0000-0000-0000-000000000000') {
            return $false
        }
    }
    if (@(@($ClaimState.GrantId, $ClaimState.Nonce, $ClaimState.RunId) | Select-Object -Unique).Count -ne 3) { return $false }
    foreach ($hash in @($ClaimState.ArtifactSha256, $ClaimState.SidecarSha256, $ClaimState.ContentDigest)) {
        if ($hash -isnot [string] -or -not [regex]::IsMatch($hash, '^[a-f0-9]{64}$')) { return $false }
    }
    if (@(@($ClaimState.ArtifactSha256, $ClaimState.SidecarSha256, $ClaimState.ContentDigest) | Select-Object -Unique).Count -ne 3) { return $false }
    if ($ClaimState.ArtifactProfile -isnot [string] -or @('VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive') -cnotcontains $ClaimState.ArtifactProfile) { return $false }
    if ($ClaimState.ExpiresAtUtc -isnot [string] -or
        -not [regex]::IsMatch($ClaimState.ExpiresAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
        -not (Test-CddsiUtcTimestampValue -Value $ClaimState.ExpiresAtUtc)) {
        return $false
    }
    if ($ClaimState.Revision -isnot [int] -or $ClaimState.Revision -lt 0) { return $false }

    if ($ClaimState.State -ceq 'AVAILABLE') {
        if ($null -ne $ClaimState.ClaimId -or $null -ne $ClaimState.ClaimedAtUtc -or $ClaimState.Revision -ne 0) { return $false }
    }
    else {
        if ($ClaimState.ClaimId -isnot [string] -or
            -not [regex]::IsMatch($ClaimState.ClaimId, $uuidPattern) -or
            $ClaimState.ClaimId -ceq '00000000-0000-0000-0000-000000000000') {
            return $false
        }
        if (@($ClaimState.GrantId, $ClaimState.Nonce, $ClaimState.RunId) -ccontains $ClaimState.ClaimId) { return $false }
        if ($ClaimState.ClaimedAtUtc -isnot [string] -or
            -not [regex]::IsMatch($ClaimState.ClaimedAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
            -not (Test-CddsiUtcTimestampValue -Value $ClaimState.ClaimedAtUtc) -or
            [DateTimeOffset]::Parse($ClaimState.ClaimedAtUtc) -ge [DateTimeOffset]::Parse($ClaimState.ExpiresAtUtc) -or
            $ClaimState.Revision -lt 1) {
            return $false
        }
    }
    return $true
}

function Test-CddsiAuthorizationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]$AuthorizationSession
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $AuthorizationSession -Expected @(
        'SchemaVersion', 'ContractVersion', 'State', 'GrantId', 'Nonce', 'ClaimId',
        'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'ArtifactProfile',
        'ClaimedAtUtc', 'ExpiresAtUtc', 'Revision'
    ))) {
        return $false
    }
    if (-not (Test-CddsiSchemaVersionOne -Value $AuthorizationSession.SchemaVersion)) { return $false }
    if ($AuthorizationSession.ContractVersion -isnot [string] -or
        $AuthorizationSession.ContractVersion -cne 'cddsi-authorization-session-v1' -or
        $AuthorizationSession.State -isnot [string] -or
        $AuthorizationSession.State -cne 'CLAIMED') {
        return $false
    }

    $uuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    foreach ($uuid in @(
        $AuthorizationSession.GrantId,
        $AuthorizationSession.Nonce,
        $AuthorizationSession.ClaimId,
        $AuthorizationSession.RunId
    )) {
        if ($uuid -isnot [string] -or -not [regex]::IsMatch($uuid, $uuidPattern) -or
            $uuid -ceq '00000000-0000-0000-0000-000000000000') {
            return $false
        }
    }
    if (@(@(
        $AuthorizationSession.GrantId,
        $AuthorizationSession.Nonce,
        $AuthorizationSession.ClaimId,
        $AuthorizationSession.RunId
    ) | Select-Object -Unique).Count -ne 4) {
        return $false
    }
    foreach ($hash in @(
        $AuthorizationSession.ArtifactSha256,
        $AuthorizationSession.SidecarSha256,
        $AuthorizationSession.ContentDigest
    )) {
        if ($hash -isnot [string] -or -not [regex]::IsMatch($hash, '^[a-f0-9]{64}$')) { return $false }
    }
    if (@(@(
        $AuthorizationSession.ArtifactSha256,
        $AuthorizationSession.SidecarSha256,
        $AuthorizationSession.ContentDigest
    ) | Select-Object -Unique).Count -ne 3) { return $false }
    if ($AuthorizationSession.ArtifactProfile -isnot [string] -or
        @('VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive') -cnotcontains $AuthorizationSession.ArtifactProfile) {
        return $false
    }
    foreach ($timestamp in @($AuthorizationSession.ClaimedAtUtc, $AuthorizationSession.ExpiresAtUtc)) {
        if ($timestamp -isnot [string] -or
            -not [regex]::IsMatch($timestamp, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
            -not (Test-CddsiUtcTimestampValue -Value $timestamp)) {
            return $false
        }
    }
    if ([DateTimeOffset]::Parse($AuthorizationSession.ClaimedAtUtc) -ge
        [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc)) {
        return $false
    }
    if ($AuthorizationSession.Revision -isnot [int] -or $AuthorizationSession.Revision -lt 1) { return $false }
    return $true
}

function Resolve-CddsiGrantClaim {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]$OperationGrant,

        [Parameter(Mandatory = $true)]
        [AllowNull()]$ClaimState,

        [Parameter(Mandatory = $true)]
        [string]$ClaimId,

        [Parameter(Mandatory = $true)]
        [int]$ExpectedRevision,

        [Parameter(Mandatory = $true)]
        [string]$NowUtc
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $grantValid = Test-CddsiOperationGrant -Grant $OperationGrant
    $claimStateValid = Test-CddsiGrantClaimState -ClaimState $ClaimState
    if (-not $grantValid) { $reasonCodes.Add('OPERATION_GRANT_INVALID') }
    if (-not $claimStateValid) { $reasonCodes.Add('GRANT_CLAIM_STATE_INVALID') }

    $uuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    $claimIdValid = (
        $ClaimId -is [string] -and
        [regex]::IsMatch($ClaimId, $uuidPattern) -and
        $ClaimId -cne '00000000-0000-0000-0000-000000000000'
    )
    if (-not $claimIdValid) { $reasonCodes.Add('CLAIM_ID_INVALID') }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }
    $nowValid = (
        $NowUtc -is [string] -and
        [regex]::IsMatch($NowUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $NowUtc)
    )
    if (-not $nowValid) { $reasonCodes.Add('CURRENT_TIME_INVALID') }

    if ($grantValid -and $claimIdValid) {
        if (@($OperationGrant.GrantId, $OperationGrant.Nonce, $OperationGrant.RunId) -ccontains $ClaimId -or
            @($OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId }) -ccontains $ClaimId) {
            $reasonCodes.Add('CLAIM_ID_COLLISION')
        }
    }
    if ($grantValid -and $claimStateValid) {
        if ($ClaimState.GrantId -cne $OperationGrant.GrantId -or
            $ClaimState.Nonce -cne $OperationGrant.Nonce -or
            $ClaimState.RunId -cne $OperationGrant.RunId -or
            $ClaimState.ArtifactSha256 -cne $OperationGrant.ArtifactSha256 -or
            $ClaimState.SidecarSha256 -cne $OperationGrant.SidecarSha256 -or
            $ClaimState.ContentDigest -cne $OperationGrant.ContentDigest -or
            $ClaimState.ArtifactProfile -cne $OperationGrant.ArtifactProfile -or
            $ClaimState.ExpiresAtUtc -cne $OperationGrant.ExpiresAtUtc) {
            $reasonCodes.Add('GRANT_CLAIM_BINDING_MISMATCH')
        }
        if ($ClaimState.Revision -ne $ExpectedRevision) {
            $reasonCodes.Add('GRANT_CLAIM_CONCURRENCY_CONFLICT')
        }
        if ($ClaimState.State -ceq 'CLAIMED') {
            $reasonCodes.Add('GRANT_CLAIM_REPLAY')
        }
        elseif (@('COMPLETED', 'ABORTED', 'EXPIRED') -ccontains $ClaimState.State) {
            $reasonCodes.Add('GRANT_CLAIM_TERMINAL')
        }
        elseif ($ClaimState.State -cne 'AVAILABLE') {
            $reasonCodes.Add('GRANT_CLAIM_STATE_NOT_AVAILABLE')
        }
        if ($nowValid) {
            $now = [DateTimeOffset]::Parse($NowUtc)
            if ($now -lt [DateTimeOffset]::Parse($OperationGrant.IssuedAtUtc)) {
                $reasonCodes.Add('GRANT_NOT_YET_VALID')
            }
            if ($now -ge [DateTimeOffset]::Parse($OperationGrant.ExpiresAtUtc)) {
                $reasonCodes.Add('GRANT_CLAIM_EXPIRED')
            }
        }
    }

    $claimed = ($reasonCodes.Count -eq 0)
    $session = $null
    if ($claimed) {
        $session = [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-authorization-session-v1'
            State           = 'CLAIMED'
            GrantId         = $OperationGrant.GrantId
            Nonce           = $OperationGrant.Nonce
            ClaimId         = $ClaimId
            RunId           = $OperationGrant.RunId
            ArtifactSha256  = $OperationGrant.ArtifactSha256
            SidecarSha256   = $OperationGrant.SidecarSha256
            ContentDigest   = $OperationGrant.ContentDigest
            ArtifactProfile = $OperationGrant.ArtifactProfile
            ClaimedAtUtc    = $NowUtc
            ExpiresAtUtc    = $OperationGrant.ExpiresAtUtc
            Revision        = $ExpectedRevision + 1
        }
    }

    $data = [pscustomobject][ordered]@{
        SchemaVersion                   = 1
        ContractVersion                 = 'cddsi-grant-claim-reduction-v1'
        Claimed                         = $claimed
        PreviousState                   = if ($claimStateValid) { $ClaimState.State } else { $null }
        NextState                       = if ($claimed) { 'CLAIMED' } else { $null }
        GrantId                         = if ($grantValid) { $OperationGrant.GrantId } else { $null }
        ClaimId                         = if ($claimIdValid) { $ClaimId } else { $null }
        PreviousRevision                = if ($claimStateValid) { $ClaimState.Revision } else { $null }
        NextRevision                    = if ($claimed) { $ExpectedRevision + 1 } else { $null }
        RequiresAtomicCompareAndSwap    = $claimed
        AuthorizationSession            = $session
        ReasonCodes                     = @($reasonCodes | Select-Object -Unique)
    }
    return New-CddsiOperationResult -Operation 'ClaimOperationGrant' `
        -Status $(if ($claimed) { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }) `
        -ErrorCode $(if ($claimed) { '' } else { 'GRANT_CLAIM_FAILED' }) `
        -MessageSafe $(if ($claimed) { 'The single-use workflow grant claim is ready for atomic compare-and-swap persistence.' } else { 'The workflow grant claim failed closed.' }) `
        -Data $data
}

function ConvertTo-CddsiStagePolicyBindingField {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return '<null>' }
    if ($Value -is [bool]) { $text = if ($Value) { 'true' } else { 'false' } }
    elseif ($Value -is [int] -or $Value -is [long]) {
        $text = $Value.ToString([System.Globalization.CultureInfo]::InvariantCulture)
    }
    elseif ($Value -is [string]) { $text = $Value }
    else { throw 'Stage-policy binding fields must be null, string, bool, int or long.' }
    return ('{0}:{1}' -f $text.Length, $text)
}

function Test-CddsiStageGrantSessionBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession
    )

    if (-not (Test-CddsiStageManifest -Manifest $StageManifest) -or
        -not (Test-CddsiOperationGrant -Grant $OperationGrant) -or
        -not (Test-CddsiAuthorizationSession -AuthorizationSession $AuthorizationSession)) {
        return $false
    }
    if ($StageManifest.Stage -cne $OperationGrant.ArtifactProfile -or
        $StageManifest.ArtifactProfile -cne $OperationGrant.ArtifactProfile -or
        $StageManifest.ArtifactSha256 -cne $OperationGrant.ArtifactSha256 -or
        $StageManifest.SidecarSha256 -cne $OperationGrant.SidecarSha256 -or
        $StageManifest.ContentDigest -cne $OperationGrant.ContentDigest) {
        return $false
    }
    if ($AuthorizationSession.GrantId -cne $OperationGrant.GrantId -or
        $AuthorizationSession.Nonce -cne $OperationGrant.Nonce -or
        $AuthorizationSession.RunId -cne $OperationGrant.RunId -or
        $AuthorizationSession.ArtifactSha256 -cne $OperationGrant.ArtifactSha256 -or
        $AuthorizationSession.SidecarSha256 -cne $OperationGrant.SidecarSha256 -or
        $AuthorizationSession.ContentDigest -cne $OperationGrant.ContentDigest -or
        $AuthorizationSession.ArtifactProfile -cne $OperationGrant.ArtifactProfile -or
        $AuthorizationSession.ExpiresAtUtc -cne $OperationGrant.ExpiresAtUtc) {
        return $false
    }
    return $true
}

function Get-CddsiWorkflowOperationSetDigest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$OperationGrant)

    if (-not (Test-CddsiOperationGrant -Grant $OperationGrant)) { throw 'OperationGrant is invalid.' }
    $lines = @('cddsi-workflow-operation-set-v1')
    foreach ($operation in @($OperationGrant.AllowedOperations)) {
        $binding = @($OperationGrant.ConfirmationBindings | Where-Object { $_.Operation -ceq $operation })
        if ($binding.Count -ne 1) { throw 'OperationGrant confirmation binding is not unique.' }
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $operation
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $binding[0].ConfirmationId
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $binding[0].PromptDigest
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $binding[0].Required
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiGrantCompensationOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if (-not (Test-CddsiOperationGrant -Grant $OperationGrant) -or
        @($OperationGrant.AllowedOperations) -cnotcontains $Operation) { return $false }
    $operations = @($OperationGrant.AllowedOperations)
    switch ($Operation) {
        'RemoveAcquiredArtifacts' { return ($operations -ccontains 'AcquireArtifacts') }
        'RestoreClaudeDesktopState' { return ($operations -ccontains 'EnsureClaudeDesktop') }
        'RestoreGitState' { return ($operations -ccontains 'EnsureGit') }
        'RestoreCoworkState' { return ($operations -ccontains 'PrepareCowork' -or $operations -ccontains 'ResumeCowork') }
        'RemoveCredential' { return ($operations -ccontains 'PersistCredential') }
        'RestoreCredentialState' { return ($operations -ccontains 'PersistCredential' -or $operations -ccontains 'RemoveCredential') }
        'RestoreManagedPolicy' { return ($operations -ccontains 'WriteManagedPolicy') }
        'RestoreDesktopLifecycle' { return ($operations -ccontains 'RestartDesktop') }
        'RemoveReport' { return ($operations -ccontains 'WriteReport') }
        default { return $false }
    }
}

function Get-CddsiWorkflowSessionStateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$WorkflowSessionState)

    $values = @(
        'cddsi-workflow-session-state-key-v1',
        $WorkflowSessionState.Stage,
        $WorkflowSessionState.ArtifactProfile,
        $WorkflowSessionState.RunId,
        $WorkflowSessionState.ArtifactSha256,
        $WorkflowSessionState.SidecarSha256,
        $WorkflowSessionState.ContentDigest,
        $WorkflowSessionState.GrantId,
        $WorkflowSessionState.Nonce,
        $WorkflowSessionState.ClaimId,
        $WorkflowSessionState.AuthorizationSessionRevision,
        $WorkflowSessionState.ClaimedAtUtc,
        $WorkflowSessionState.ExpiresAtUtc,
        $WorkflowSessionState.OperationSetDigestSha256,
        $WorkflowSessionState.OperationCount
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Get-CddsiWorkflowSessionBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$WorkflowSessionState)

    $values = @(
        'cddsi-workflow-session-state-binding-v1',
        $WorkflowSessionState.SchemaVersion,
        $WorkflowSessionState.ContractVersion,
        $WorkflowSessionState.StateKeySha256,
        $WorkflowSessionState.State,
        $WorkflowSessionState.Stage,
        $WorkflowSessionState.ArtifactProfile,
        $WorkflowSessionState.RunId,
        $WorkflowSessionState.ArtifactSha256,
        $WorkflowSessionState.SidecarSha256,
        $WorkflowSessionState.ContentDigest,
        $WorkflowSessionState.GrantId,
        $WorkflowSessionState.Nonce,
        $WorkflowSessionState.ClaimId,
        $WorkflowSessionState.AuthorizationSessionRevision,
        $WorkflowSessionState.ClaimedAtUtc,
        $WorkflowSessionState.ExpiresAtUtc,
        $WorkflowSessionState.OperationSetDigestSha256,
        $WorkflowSessionState.OperationCount,
        $WorkflowSessionState.TerminalOperationSetDigestSha256,
        $WorkflowSessionState.OccurredAtUtc,
        $WorkflowSessionState.TerminalReasonCode,
        $WorkflowSessionState.IdempotencyKey,
        $WorkflowSessionState.Revision
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiWorkflowSessionState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$WorkflowSessionState)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $WorkflowSessionState -Expected @(
            'SchemaVersion', 'ContractVersion', 'StateKeySha256', 'State', 'Stage',
            'ArtifactProfile', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest',
            'GrantId', 'Nonce', 'ClaimId', 'AuthorizationSessionRevision', 'ClaimedAtUtc',
            'ExpiresAtUtc', 'OperationSetDigestSha256', 'OperationCount',
            'TerminalOperationSetDigestSha256', 'OccurredAtUtc', 'TerminalReasonCode',
            'IdempotencyKey', 'Revision', 'ReceiptBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $WorkflowSessionState.SchemaVersion) -or
            $WorkflowSessionState.ContractVersion -cne 'cddsi-workflow-session-state-v1' -or
            $WorkflowSessionState.State -cnotin @('CLAIMED', 'COMPLETED', 'ABORTED')) { return $false }
        if ($WorkflowSessionState.Stage -cnotin @('VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive') -or
            $WorkflowSessionState.ArtifactProfile -cne $WorkflowSessionState.Stage) { return $false }
        foreach ($uuid in @($WorkflowSessionState.RunId, $WorkflowSessionState.GrantId, $WorkflowSessionState.Nonce, $WorkflowSessionState.ClaimId)) {
            if (-not (Test-CddsiCanonicalUuidValue -Value $uuid)) { return $false }
        }
        if (@(@($WorkflowSessionState.RunId, $WorkflowSessionState.GrantId, $WorkflowSessionState.Nonce, $WorkflowSessionState.ClaimId) | Select-Object -Unique).Count -ne 4) { return $false }
        foreach ($hash in @(
            $WorkflowSessionState.StateKeySha256,
            $WorkflowSessionState.ArtifactSha256,
            $WorkflowSessionState.SidecarSha256,
            $WorkflowSessionState.ContentDigest,
            $WorkflowSessionState.OperationSetDigestSha256,
            $WorkflowSessionState.ReceiptBindingToken
        )) {
            if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (@(@($WorkflowSessionState.ArtifactSha256, $WorkflowSessionState.SidecarSha256, $WorkflowSessionState.ContentDigest) | Select-Object -Unique).Count -ne 3) { return $false }
        if ($WorkflowSessionState.AuthorizationSessionRevision -isnot [int] -or $WorkflowSessionState.AuthorizationSessionRevision -lt 1 -or
            $WorkflowSessionState.OperationCount -isnot [int] -or $WorkflowSessionState.OperationCount -lt 1 -or
            $WorkflowSessionState.Revision -isnot [int] -or $WorkflowSessionState.Revision -lt $WorkflowSessionState.AuthorizationSessionRevision) { return $false }
        foreach ($timestamp in @($WorkflowSessionState.ClaimedAtUtc, $WorkflowSessionState.ExpiresAtUtc)) {
            if ($timestamp -isnot [string] -or
                -not [regex]::IsMatch($timestamp, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
                -not (Test-CddsiUtcTimestampValue -Value $timestamp)) { return $false }
        }
        if ([DateTimeOffset]::Parse($WorkflowSessionState.ClaimedAtUtc) -ge [DateTimeOffset]::Parse($WorkflowSessionState.ExpiresAtUtc)) { return $false }
        if ($WorkflowSessionState.State -ceq 'CLAIMED') {
            if ($null -ne $WorkflowSessionState.TerminalOperationSetDigestSha256 -or
                $null -ne $WorkflowSessionState.OccurredAtUtc -or
                $null -ne $WorkflowSessionState.TerminalReasonCode -or
                $null -ne $WorkflowSessionState.IdempotencyKey -or
                $WorkflowSessionState.Revision -ne $WorkflowSessionState.AuthorizationSessionRevision) { return $false }
        }
        else {
            if ($WorkflowSessionState.TerminalOperationSetDigestSha256 -isnot [string] -or
                $WorkflowSessionState.TerminalOperationSetDigestSha256 -notmatch '^[a-f0-9]{64}$' -or
                -not (Test-CddsiCanonicalUuidValue -Value $WorkflowSessionState.IdempotencyKey) -or
                $WorkflowSessionState.OccurredAtUtc -isnot [string] -or
                -not [regex]::IsMatch($WorkflowSessionState.OccurredAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
                -not (Test-CddsiUtcTimestampValue -Value $WorkflowSessionState.OccurredAtUtc) -or
                [DateTimeOffset]::Parse($WorkflowSessionState.OccurredAtUtc) -lt [DateTimeOffset]::Parse($WorkflowSessionState.ClaimedAtUtc) -or
                [DateTimeOffset]::Parse($WorkflowSessionState.OccurredAtUtc) -ge [DateTimeOffset]::Parse($WorkflowSessionState.ExpiresAtUtc) -or
                $WorkflowSessionState.Revision -ne ($WorkflowSessionState.AuthorizationSessionRevision + 1)) { return $false }
            if ($WorkflowSessionState.State -ceq 'COMPLETED') {
                if ($WorkflowSessionState.TerminalReasonCode -cne '') { return $false }
            }
            elseif ($WorkflowSessionState.TerminalReasonCode -isnot [string] -or
                $script:CddsiWorkflowAbortReasonCodes -cnotcontains $WorkflowSessionState.TerminalReasonCode) { return $false }
        }
        if ($WorkflowSessionState.StateKeySha256 -cne (Get-CddsiWorkflowSessionStateKey -WorkflowSessionState $WorkflowSessionState) -or
            $WorkflowSessionState.ReceiptBindingToken -cne (Get-CddsiWorkflowSessionBindingToken -WorkflowSessionState $WorkflowSessionState)) { return $false }
        return $true
    }
    catch { return $false }
}

function Test-CddsiWorkflowSessionBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState
    )

    if (-not (Test-CddsiStageGrantSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession) -or
        -not (Test-CddsiWorkflowSessionState -WorkflowSessionState $WorkflowSessionState)) { return $false }
    return (
        $WorkflowSessionState.Stage -ceq $StageManifest.Stage -and
        $WorkflowSessionState.ArtifactProfile -ceq $OperationGrant.ArtifactProfile -and
        $WorkflowSessionState.RunId -ceq $OperationGrant.RunId -and
        $WorkflowSessionState.ArtifactSha256 -ceq $OperationGrant.ArtifactSha256 -and
        $WorkflowSessionState.SidecarSha256 -ceq $OperationGrant.SidecarSha256 -and
        $WorkflowSessionState.ContentDigest -ceq $OperationGrant.ContentDigest -and
        $WorkflowSessionState.GrantId -ceq $OperationGrant.GrantId -and
        $WorkflowSessionState.Nonce -ceq $OperationGrant.Nonce -and
        $WorkflowSessionState.ClaimId -ceq $AuthorizationSession.ClaimId -and
        $WorkflowSessionState.AuthorizationSessionRevision -eq $AuthorizationSession.Revision -and
        $WorkflowSessionState.ClaimedAtUtc -ceq $AuthorizationSession.ClaimedAtUtc -and
        $WorkflowSessionState.ExpiresAtUtc -ceq $AuthorizationSession.ExpiresAtUtc -and
        $WorkflowSessionState.OperationSetDigestSha256 -ceq (Get-CddsiWorkflowOperationSetDigest -OperationGrant $OperationGrant) -and
        $WorkflowSessionState.OperationCount -eq @($OperationGrant.AllowedOperations).Count
    )
}

function New-CddsiWorkflowSessionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession
    )

    if (-not (Test-CddsiStageGrantSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession)) {
        throw 'Stage manifest, operation grant and authorization session are not bound.'
    }
    $state = [pscustomobject][ordered]@{
        SchemaVersion                   = 1
        ContractVersion                 = 'cddsi-workflow-session-state-v1'
        StateKeySha256                  = $null
        State                           = 'CLAIMED'
        Stage                           = $StageManifest.Stage
        ArtifactProfile                 = $OperationGrant.ArtifactProfile
        RunId                           = $OperationGrant.RunId
        ArtifactSha256                  = $OperationGrant.ArtifactSha256
        SidecarSha256                   = $OperationGrant.SidecarSha256
        ContentDigest                   = $OperationGrant.ContentDigest
        GrantId                         = $OperationGrant.GrantId
        Nonce                           = $OperationGrant.Nonce
        ClaimId                         = $AuthorizationSession.ClaimId
        AuthorizationSessionRevision    = $AuthorizationSession.Revision
        ClaimedAtUtc                    = $AuthorizationSession.ClaimedAtUtc
        ExpiresAtUtc                    = $AuthorizationSession.ExpiresAtUtc
        OperationSetDigestSha256        = Get-CddsiWorkflowOperationSetDigest -OperationGrant $OperationGrant
        OperationCount                  = @($OperationGrant.AllowedOperations).Count
        TerminalOperationSetDigestSha256 = $null
        OccurredAtUtc                   = $null
        TerminalReasonCode              = $null
        IdempotencyKey                  = $null
        Revision                        = $AuthorizationSession.Revision
        ReceiptBindingToken             = $null
    }
    $state.StateKeySha256 = Get-CddsiWorkflowSessionStateKey -WorkflowSessionState $state
    $state.ReceiptBindingToken = Get-CddsiWorkflowSessionBindingToken -WorkflowSessionState $state
    if (-not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $state)) {
        throw 'Workflow session state construction failed closed.'
    }
    return $state
}

function Get-CddsiOperationUseStateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$OperationUseState)

    $values = @(
        'cddsi-operation-use-state-key-v1',
        $OperationUseState.Stage,
        $OperationUseState.ArtifactProfile,
        $OperationUseState.RunId,
        $OperationUseState.ArtifactSha256,
        $OperationUseState.SidecarSha256,
        $OperationUseState.ContentDigest,
        $OperationUseState.GrantId,
        $OperationUseState.Nonce,
        $OperationUseState.ClaimId,
        $OperationUseState.AuthorizationSessionRevision,
        $OperationUseState.WorkflowSessionStateKeySha256,
        $OperationUseState.WorkflowSessionRevision,
        $OperationUseState.ConfirmationId,
        $OperationUseState.ConfirmationPromptDigest,
        $OperationUseState.Operation,
        $OperationUseState.ExpiresAtUtc
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Get-CddsiOperationUseBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$OperationUseState)

    $values = @(
        'cddsi-operation-use-state-binding-v1',
        $OperationUseState.SchemaVersion,
        $OperationUseState.ContractVersion,
        $OperationUseState.StateKeySha256,
        $OperationUseState.State,
        $OperationUseState.Stage,
        $OperationUseState.ArtifactProfile,
        $OperationUseState.RunId,
        $OperationUseState.ArtifactSha256,
        $OperationUseState.SidecarSha256,
        $OperationUseState.ContentDigest,
        $OperationUseState.GrantId,
        $OperationUseState.Nonce,
        $OperationUseState.ClaimId,
        $OperationUseState.AuthorizationSessionRevision,
        $OperationUseState.WorkflowSessionStateKeySha256,
        $OperationUseState.WorkflowSessionRevision,
        $OperationUseState.ConfirmationId,
        $OperationUseState.ConfirmationPromptDigest,
        $OperationUseState.ConfirmedAtUtc,
        $OperationUseState.ConfirmationConsumed,
        $OperationUseState.Operation,
        $OperationUseState.OperationUseId,
        $OperationUseState.ClaimedAtUtc,
        $OperationUseState.ExpiresAtUtc,
        $OperationUseState.ProviderIdempotencyRequired,
        $OperationUseState.ProviderInvocationOccurred,
        $OperationUseState.ProviderEvidenceDigest,
        $OperationUseState.OccurredAtUtc,
        $OperationUseState.TerminalReasonCode,
        $OperationUseState.IdempotencyKey,
        $OperationUseState.Revision
    )
    $lines = @($values | ForEach-Object { ConvertTo-CddsiStagePolicyBindingField -Value $_ })
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Test-CddsiOperationUseState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$OperationUseState)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $OperationUseState -Expected @(
            'SchemaVersion', 'ContractVersion', 'StateKeySha256', 'State', 'Stage',
            'ArtifactProfile', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest',
            'GrantId', 'Nonce', 'ClaimId', 'AuthorizationSessionRevision',
            'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision', 'ConfirmationId',
            'ConfirmationPromptDigest', 'ConfirmedAtUtc', 'ConfirmationConsumed',
            'Operation', 'OperationUseId',
            'ClaimedAtUtc', 'ExpiresAtUtc',
            'ProviderIdempotencyRequired', 'ProviderInvocationOccurred',
            'ProviderEvidenceDigest', 'OccurredAtUtc',
            'TerminalReasonCode', 'IdempotencyKey', 'Revision', 'ReceiptBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $OperationUseState.SchemaVersion) -or
            $OperationUseState.ContractVersion -cne 'cddsi-operation-use-state-v1' -or
            $OperationUseState.State -cnotin @('AVAILABLE', 'CLAIMED', 'COMPLETED', 'ABORTED')) { return $false }
        if ($OperationUseState.Stage -cnotin @('VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive') -or
            $OperationUseState.ArtifactProfile -cne $OperationUseState.Stage -or
            $script:CddsiGrantedOperationNames -cnotcontains $OperationUseState.Operation) { return $false }
        foreach ($uuid in @($OperationUseState.RunId, $OperationUseState.GrantId, $OperationUseState.Nonce, $OperationUseState.ClaimId, $OperationUseState.ConfirmationId)) {
            if (-not (Test-CddsiCanonicalUuidValue -Value $uuid)) { return $false }
        }
        if (@(@($OperationUseState.RunId, $OperationUseState.GrantId, $OperationUseState.Nonce, $OperationUseState.ClaimId, $OperationUseState.ConfirmationId) | Select-Object -Unique).Count -ne 5) { return $false }
        foreach ($hash in @(
            $OperationUseState.StateKeySha256,
            $OperationUseState.ArtifactSha256,
            $OperationUseState.SidecarSha256,
            $OperationUseState.ContentDigest,
            $OperationUseState.WorkflowSessionStateKeySha256,
            $OperationUseState.ConfirmationPromptDigest,
            $OperationUseState.ReceiptBindingToken
        )) {
            if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (@(@($OperationUseState.ArtifactSha256, $OperationUseState.SidecarSha256, $OperationUseState.ContentDigest) | Select-Object -Unique).Count -ne 3) { return $false }
        if ($OperationUseState.AuthorizationSessionRevision -isnot [int] -or $OperationUseState.AuthorizationSessionRevision -lt 1 -or
            $OperationUseState.WorkflowSessionRevision -isnot [int] -or $OperationUseState.WorkflowSessionRevision -lt 1 -or
            $OperationUseState.Revision -isnot [int] -or $OperationUseState.Revision -lt 0 -or
            $OperationUseState.ProviderIdempotencyRequired -isnot [bool] -or -not $OperationUseState.ProviderIdempotencyRequired -or
            $OperationUseState.ConfirmationConsumed -isnot [bool] -or
            $OperationUseState.ProviderInvocationOccurred -isnot [bool]) { return $false }
        if ($OperationUseState.ExpiresAtUtc -isnot [string] -or
            -not [regex]::IsMatch($OperationUseState.ExpiresAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
            -not (Test-CddsiUtcTimestampValue -Value $OperationUseState.ExpiresAtUtc)) { return $false }
        if ($OperationUseState.State -ceq 'AVAILABLE') {
            if ($null -ne $OperationUseState.OperationUseId -or $null -ne $OperationUseState.ConfirmedAtUtc -or
                $OperationUseState.ConfirmationConsumed -or $null -ne $OperationUseState.ClaimedAtUtc -or
                $OperationUseState.ProviderInvocationOccurred -or $null -ne $OperationUseState.ProviderEvidenceDigest -or
                $null -ne $OperationUseState.OccurredAtUtc -or $null -ne $OperationUseState.TerminalReasonCode -or
                $null -ne $OperationUseState.IdempotencyKey -or $OperationUseState.Revision -ne 0) { return $false }
        }
        else {
            if (-not (Test-CddsiCanonicalUuidValue -Value $OperationUseState.OperationUseId) -or
                @($OperationUseState.RunId, $OperationUseState.GrantId, $OperationUseState.Nonce, $OperationUseState.ClaimId, $OperationUseState.ConfirmationId) -ccontains $OperationUseState.OperationUseId) { return $false }
            $unexecutedAbort = (
                $OperationUseState.State -ceq 'ABORTED' -and
                $OperationUseState.TerminalReasonCode -cin @('NOT_RUN_DUE_TO_ABORT', 'NOT_REQUIRED')
            )
            if ($unexecutedAbort) {
                if ($null -ne $OperationUseState.ConfirmedAtUtc -or $OperationUseState.ConfirmationConsumed -or
                    $null -ne $OperationUseState.ClaimedAtUtc -or $OperationUseState.ProviderInvocationOccurred -or
                    $null -ne $OperationUseState.ProviderEvidenceDigest -or $OperationUseState.Revision -ne 1) { return $false }
            }
            else {
                if (-not $OperationUseState.ConfirmationConsumed -or
                    $OperationUseState.ClaimedAtUtc -isnot [string] -or
                    -not [regex]::IsMatch($OperationUseState.ClaimedAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
                    -not (Test-CddsiUtcTimestampValue -Value $OperationUseState.ClaimedAtUtc) -or
                    [DateTimeOffset]::Parse($OperationUseState.ClaimedAtUtc) -ge [DateTimeOffset]::Parse($OperationUseState.ExpiresAtUtc) -or
                    $OperationUseState.ConfirmedAtUtc -isnot [string] -or
                    -not [regex]::IsMatch($OperationUseState.ConfirmedAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
                    -not (Test-CddsiUtcTimestampValue -Value $OperationUseState.ConfirmedAtUtc) -or
                    [DateTimeOffset]::Parse($OperationUseState.ConfirmedAtUtc) -gt [DateTimeOffset]::Parse($OperationUseState.ClaimedAtUtc)) { return $false }
                if ($OperationUseState.State -ceq 'CLAIMED') {
                    if ($OperationUseState.ProviderInvocationOccurred -or
                        $null -ne $OperationUseState.ProviderEvidenceDigest -or $null -ne $OperationUseState.OccurredAtUtc -or
                        $null -ne $OperationUseState.TerminalReasonCode -or $null -ne $OperationUseState.IdempotencyKey -or
                        $OperationUseState.Revision -ne 1) { return $false }
                }
                else {
                    if (-not $OperationUseState.ProviderInvocationOccurred -or
                        $OperationUseState.ProviderEvidenceDigest -isnot [string] -or
                        $OperationUseState.ProviderEvidenceDigest -notmatch '^[a-f0-9]{64}$' -or
                        $OperationUseState.Revision -ne 2) { return $false }
                    if ($OperationUseState.State -ceq 'COMPLETED') {
                        if ($OperationUseState.TerminalReasonCode -cne '') { return $false }
                    }
                    elseif ($OperationUseState.TerminalReasonCode -isnot [string] -or
                        $OperationUseState.TerminalReasonCode -cin @('NOT_RUN_DUE_TO_ABORT', 'NOT_REQUIRED') -or
                        $script:CddsiOperationAbortReasonCodes -cnotcontains $OperationUseState.TerminalReasonCode) { return $false }
                }
            }
            if ($OperationUseState.State -in @('COMPLETED', 'ABORTED')) {
                if (-not (Test-CddsiCanonicalUuidValue -Value $OperationUseState.IdempotencyKey) -or
                    @($OperationUseState.RunId, $OperationUseState.GrantId, $OperationUseState.Nonce, $OperationUseState.ClaimId, $OperationUseState.ConfirmationId, $OperationUseState.OperationUseId) -ccontains $OperationUseState.IdempotencyKey -or
                    $OperationUseState.OccurredAtUtc -isnot [string] -or
                    -not [regex]::IsMatch($OperationUseState.OccurredAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
                    -not (Test-CddsiUtcTimestampValue -Value $OperationUseState.OccurredAtUtc) -or
                    [DateTimeOffset]::Parse($OperationUseState.OccurredAtUtc) -ge [DateTimeOffset]::Parse($OperationUseState.ExpiresAtUtc)) { return $false }
                if (-not $unexecutedAbort -and
                    [DateTimeOffset]::Parse($OperationUseState.OccurredAtUtc) -lt [DateTimeOffset]::Parse($OperationUseState.ClaimedAtUtc)) { return $false }
            }
        }
        if ($OperationUseState.StateKeySha256 -cne (Get-CddsiOperationUseStateKey -OperationUseState $OperationUseState) -or
            $OperationUseState.ReceiptBindingToken -cne (Get-CddsiOperationUseBindingToken -OperationUseState $OperationUseState)) { return $false }
        return $true
    }
    catch { return $false }
}

function Test-CddsiOperationUseBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseState
    )

    if (-not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState) -or
        -not (Test-CddsiOperationUseState -OperationUseState $OperationUseState)) { return $false }
    $binding = @($OperationGrant.ConfirmationBindings | Where-Object { $_.Operation -ceq $OperationUseState.Operation })
    if ($binding.Count -ne 1) { return $false }
    return (
        $OperationUseState.Stage -ceq $StageManifest.Stage -and
        $OperationUseState.ArtifactProfile -ceq $OperationGrant.ArtifactProfile -and
        $OperationUseState.RunId -ceq $OperationGrant.RunId -and
        $OperationUseState.ArtifactSha256 -ceq $OperationGrant.ArtifactSha256 -and
        $OperationUseState.SidecarSha256 -ceq $OperationGrant.SidecarSha256 -and
        $OperationUseState.ContentDigest -ceq $OperationGrant.ContentDigest -and
        $OperationUseState.GrantId -ceq $OperationGrant.GrantId -and
        $OperationUseState.Nonce -ceq $OperationGrant.Nonce -and
        $OperationUseState.ClaimId -ceq $AuthorizationSession.ClaimId -and
        $OperationUseState.AuthorizationSessionRevision -eq $AuthorizationSession.Revision -and
        $OperationUseState.WorkflowSessionStateKeySha256 -ceq $WorkflowSessionState.StateKeySha256 -and
        $OperationUseState.WorkflowSessionRevision -eq $AuthorizationSession.Revision -and
        $OperationUseState.ConfirmationId -ceq $binding[0].ConfirmationId -and
        $OperationUseState.ConfirmationPromptDigest -ceq $binding[0].PromptDigest -and
        ($null -eq $OperationUseState.ConfirmedAtUtc -or
            [DateTimeOffset]::Parse($OperationUseState.ConfirmedAtUtc) -ge [DateTimeOffset]::Parse($AuthorizationSession.ClaimedAtUtc)) -and
        $OperationUseState.ExpiresAtUtc -ceq $AuthorizationSession.ExpiresAtUtc
    )
}

function New-CddsiOperationUseState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)][string]$Operation
    )

    if (-not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState) -or
        $WorkflowSessionState.State -cne 'CLAIMED') { throw 'Workflow session is not a bound CLAIMED session.' }
    $binding = @($OperationGrant.ConfirmationBindings | Where-Object { $_.Operation -ceq $Operation })
    if ($binding.Count -ne 1) { throw 'Operation does not have exactly one confirmation binding.' }
    $state = [pscustomobject][ordered]@{
        SchemaVersion                  = 1
        ContractVersion                = 'cddsi-operation-use-state-v1'
        StateKeySha256                 = $null
        State                          = 'AVAILABLE'
        Stage                          = $StageManifest.Stage
        ArtifactProfile                = $OperationGrant.ArtifactProfile
        RunId                          = $OperationGrant.RunId
        ArtifactSha256                 = $OperationGrant.ArtifactSha256
        SidecarSha256                  = $OperationGrant.SidecarSha256
        ContentDigest                  = $OperationGrant.ContentDigest
        GrantId                        = $OperationGrant.GrantId
        Nonce                          = $OperationGrant.Nonce
        ClaimId                        = $AuthorizationSession.ClaimId
        AuthorizationSessionRevision   = $AuthorizationSession.Revision
        WorkflowSessionStateKeySha256  = $WorkflowSessionState.StateKeySha256
        WorkflowSessionRevision        = $WorkflowSessionState.Revision
        ConfirmationId                 = $binding[0].ConfirmationId
        ConfirmationPromptDigest       = $binding[0].PromptDigest
        ConfirmedAtUtc                 = $null
        ConfirmationConsumed           = $false
        Operation                      = $Operation
        OperationUseId                 = $null
        ClaimedAtUtc                   = $null
        ExpiresAtUtc                   = $AuthorizationSession.ExpiresAtUtc
        ProviderIdempotencyRequired    = $true
        ProviderInvocationOccurred     = $false
        ProviderEvidenceDigest         = $null
        OccurredAtUtc                  = $null
        TerminalReasonCode             = $null
        IdempotencyKey                 = $null
        Revision                       = 0
        ReceiptBindingToken            = $null
    }
    $state.StateKeySha256 = Get-CddsiOperationUseStateKey -OperationUseState $state
    $state.ReceiptBindingToken = Get-CddsiOperationUseBindingToken -OperationUseState $state
    if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState -OperationUseState $state)) {
        throw 'Operation-use state construction failed closed.'
    }
    return $state
}

function Resolve-CddsiOperationAuthorizationBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]$StageManifest,

        [Parameter(Mandatory = $true)]
        [AllowNull()]$OperationGrant,

        [Parameter(Mandatory = $true)]
        [AllowNull()]$AuthorizationSession,

        [Parameter(Mandatory = $true)]
        [AllowNull()]$Confirmation,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [string]$NowUtc
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $manifestValid = Test-CddsiStageManifest -Manifest $StageManifest
    $grantValid = Test-CddsiOperationGrant -Grant $OperationGrant
    $sessionValid = Test-CddsiAuthorizationSession -AuthorizationSession $AuthorizationSession
    if (-not $manifestValid) { $reasonCodes.Add('STAGE_MANIFEST_INVALID') }
    if (-not $grantValid) { $reasonCodes.Add('OPERATION_GRANT_INVALID') }
    if (-not $sessionValid) { $reasonCodes.Add('AUTHORIZATION_SESSION_INVALID') }

    $uuidPattern = '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$'
    $runIdValid = (
        $RunId -is [string] -and
        [regex]::IsMatch($RunId, $uuidPattern) -and
        $RunId -cne '00000000-0000-0000-0000-000000000000'
    )
    if (-not $runIdValid) { $reasonCodes.Add('RUN_ID_INVALID') }
    $nowValid = (
        $NowUtc -is [string] -and
        [regex]::IsMatch($NowUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $NowUtc)
    )
    if (-not $nowValid) { $reasonCodes.Add('CURRENT_TIME_INVALID') }
    if ($Operation -isnot [string] -or $script:CddsiGrantedOperationNames -cnotcontains $Operation) {
        $reasonCodes.Add('OPERATION_UNKNOWN')
    }

    if ($manifestValid -and $grantValid) {
        if ($StageManifest.Stage -cne $OperationGrant.ArtifactProfile -or
            $StageManifest.ArtifactProfile -cne $OperationGrant.ArtifactProfile) {
            $reasonCodes.Add('PROFILE_BINDING_MISMATCH')
        }
        if ($StageManifest.ArtifactSha256 -cne $OperationGrant.ArtifactSha256) {
            $reasonCodes.Add('ARTIFACT_HASH_MISMATCH')
        }
        if ($StageManifest.SidecarSha256 -cne $OperationGrant.SidecarSha256) {
            $reasonCodes.Add('SIDECAR_HASH_MISMATCH')
        }
        if ($StageManifest.ContentDigest -cne $OperationGrant.ContentDigest) {
            $reasonCodes.Add('CONTENT_DIGEST_MISMATCH')
        }
        if ($runIdValid -and $OperationGrant.RunId -cne $RunId) {
            $reasonCodes.Add('RUN_ID_MISMATCH')
        }
        if ($script:CddsiGrantedOperationNames -ccontains $Operation -and
            @($OperationGrant.AllowedOperations) -cnotcontains $Operation) {
            $reasonCodes.Add('OPERATION_NOT_ALLOWED')
        }
    }

    if ($grantValid -and $sessionValid) {
        if ($AuthorizationSession.GrantId -cne $OperationGrant.GrantId -or
            $AuthorizationSession.Nonce -cne $OperationGrant.Nonce -or
            $AuthorizationSession.RunId -cne $OperationGrant.RunId -or
            $AuthorizationSession.ArtifactSha256 -cne $OperationGrant.ArtifactSha256 -or
            $AuthorizationSession.SidecarSha256 -cne $OperationGrant.SidecarSha256 -or
            $AuthorizationSession.ContentDigest -cne $OperationGrant.ContentDigest -or
            $AuthorizationSession.ArtifactProfile -cne $OperationGrant.ArtifactProfile -or
            $AuthorizationSession.ExpiresAtUtc -cne $OperationGrant.ExpiresAtUtc) {
            $reasonCodes.Add('AUTHORIZATION_SESSION_BINDING_MISMATCH')
        }
        if ($nowValid) {
            $now = [DateTimeOffset]::Parse($NowUtc)
            $claimedAt = [DateTimeOffset]::Parse($AuthorizationSession.ClaimedAtUtc)
            $issuedAt = [DateTimeOffset]::Parse($OperationGrant.IssuedAtUtc)
            $expiresAt = [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc)
            if ($claimedAt -lt $issuedAt -or $claimedAt -gt $now) {
                $reasonCodes.Add('AUTHORIZATION_SESSION_TIME_INVALID')
            }
            if ($now -ge $expiresAt) {
                $reasonCodes.Add('AUTHORIZATION_SESSION_EXPIRED')
            }
        }
    }

    $confirmationValid = Test-CddsiExactPropertySet -InputObject $Confirmation -Expected @(
        'SchemaVersion', 'ContractVersion', 'ConfirmationId', 'GrantId', 'ClaimId',
        'PromptDigest', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest',
        'ArtifactProfile', 'RunId', 'Nonce', 'Operation', 'Confirmed', 'ConfirmedAtUtc'
    )
    if ($confirmationValid) {
        $confirmationValid = (
            (Test-CddsiSchemaVersionOne -Value $Confirmation.SchemaVersion) -and
            $Confirmation.ContractVersion -is [string] -and
            $Confirmation.ContractVersion -ceq 'cddsi-interactive-confirmation-v2' -and
            $Confirmation.ConfirmationId -is [string] -and
            [regex]::IsMatch($Confirmation.ConfirmationId, $uuidPattern) -and
            $Confirmation.ConfirmationId -cne '00000000-0000-0000-0000-000000000000' -and
            $Confirmation.GrantId -is [string] -and
            [regex]::IsMatch($Confirmation.GrantId, $uuidPattern) -and
            $Confirmation.ClaimId -is [string] -and
            [regex]::IsMatch($Confirmation.ClaimId, $uuidPattern) -and
            $Confirmation.PromptDigest -is [string] -and
            [regex]::IsMatch($Confirmation.PromptDigest, '^[a-f0-9]{64}$') -and
            $Confirmation.ArtifactSha256 -is [string] -and
            [regex]::IsMatch($Confirmation.ArtifactSha256, '^[a-f0-9]{64}$') -and
            $Confirmation.SidecarSha256 -is [string] -and
            [regex]::IsMatch($Confirmation.SidecarSha256, '^[a-f0-9]{64}$') -and
            $Confirmation.ContentDigest -is [string] -and
            [regex]::IsMatch($Confirmation.ContentDigest, '^[a-f0-9]{64}$') -and
            $Confirmation.ArtifactProfile -is [string] -and
            @('VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive') -ccontains $Confirmation.ArtifactProfile -and
            $Confirmation.RunId -is [string] -and
            [regex]::IsMatch($Confirmation.RunId, $uuidPattern) -and
            $Confirmation.Nonce -is [string] -and
            [regex]::IsMatch($Confirmation.Nonce, $uuidPattern) -and
            $Confirmation.Operation -is [string] -and
            $script:CddsiGrantedOperationNames -ccontains $Confirmation.Operation -and
            $Confirmation.Confirmed -is [bool] -and
            $Confirmation.Confirmed -and
            $Confirmation.ConfirmedAtUtc -is [string] -and
            [regex]::IsMatch($Confirmation.ConfirmedAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
            (Test-CddsiUtcTimestampValue -Value $Confirmation.ConfirmedAtUtc)
        )
    }
    if (-not $confirmationValid) {
        $reasonCodes.Add('CONFIRMATION_INVALID')
    }
    elseif ($grantValid -and $sessionValid) {
        $operationBinding = @($OperationGrant.ConfirmationBindings | Where-Object { $_.Operation -ceq $Operation })
        if ($operationBinding.Count -ne 1 -or
            $Confirmation.ConfirmationId -cne $operationBinding[0].ConfirmationId -or
            $Confirmation.GrantId -cne $OperationGrant.GrantId -or
            $Confirmation.ClaimId -cne $AuthorizationSession.ClaimId -or
            $Confirmation.PromptDigest -cne $operationBinding[0].PromptDigest -or
            $Confirmation.ArtifactSha256 -cne $OperationGrant.ArtifactSha256 -or
            $Confirmation.SidecarSha256 -cne $OperationGrant.SidecarSha256 -or
            $Confirmation.ContentDigest -cne $OperationGrant.ContentDigest -or
            $Confirmation.ArtifactProfile -cne $OperationGrant.ArtifactProfile -or
            $Confirmation.RunId -cne $OperationGrant.RunId -or
            $Confirmation.Nonce -cne $OperationGrant.Nonce -or
            $Confirmation.Operation -cne $Operation) {
            $reasonCodes.Add('CONFIRMATION_BINDING_MISMATCH')
        }
        if ($confirmationValid -and @(@(
            $Confirmation.ConfirmationId,
            $Confirmation.GrantId,
            $Confirmation.ClaimId,
            $Confirmation.RunId,
            $Confirmation.Nonce
        ) | Select-Object -Unique).Count -ne 5) {
            $reasonCodes.Add('CONFIRMATION_IDENTIFIER_COLLISION')
        }
        if ($nowValid) {
            $confirmedAt = [DateTimeOffset]::Parse($Confirmation.ConfirmedAtUtc)
            $claimedAt = [DateTimeOffset]::Parse($AuthorizationSession.ClaimedAtUtc)
            $expiresAt = [DateTimeOffset]::Parse($AuthorizationSession.ExpiresAtUtc)
            $now = [DateTimeOffset]::Parse($NowUtc)
            if ($confirmedAt -lt $claimedAt -or $confirmedAt -gt $now -or $confirmedAt -ge $expiresAt) {
                $reasonCodes.Add('CONFIRMATION_TIME_INVALID')
            }
        }
    }

    $bindingValid = ($reasonCodes.Count -eq 0)
    $data = [pscustomobject][ordered]@{
        SchemaVersion   = 1
        ContractVersion = 'cddsi-operation-authorization-binding-v1'
        BindingValid    = $bindingValid
        Stage           = if ($manifestValid) { $StageManifest.Stage } else { $null }
        ArtifactProfile = if ($manifestValid) { $StageManifest.ArtifactProfile } else { $null }
        RunId           = if ($runIdValid) { $RunId } else { $null }
        Operation       = if ($script:CddsiGrantedOperationNames -ccontains $Operation) { $Operation } else { $null }
        GrantId         = if ($grantValid) { $OperationGrant.GrantId } else { $null }
        ClaimId         = if ($sessionValid) { $AuthorizationSession.ClaimId } else { $null }
        ArtifactSha256  = if ($manifestValid) { $StageManifest.ArtifactSha256 } else { $null }
        SidecarSha256   = if ($manifestValid) { $StageManifest.SidecarSha256 } else { $null }
        ConfirmationId = if ($confirmationValid) { $Confirmation.ConfirmationId } else { $null }
        ReasonCodes     = @($reasonCodes | Select-Object -Unique)
    }
    return New-CddsiOperationResult -Operation 'ValidateStageOperationBinding' `
        -Status $(if ($bindingValid) { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }) `
        -ErrorCode $(if ($bindingValid) { '' } else { 'OPERATION_BINDING_INVALID' }) `
        -MessageSafe $(if ($bindingValid) { 'The operation-specific confirmation binding is valid.' } else { 'The operation-specific confirmation binding failed closed.' }) `
        -Data $data
}

function Resolve-CddsiOperationAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseState,
        [Parameter(Mandatory = $true)]$Confirmation,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$NowUtc
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $bindingResult = Resolve-CddsiOperationAuthorizationBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -Confirmation $Confirmation -Operation $Operation -RunId $RunId -NowUtc $NowUtc
    if (-not $bindingResult.Data.BindingValid) {
        foreach ($code in @($bindingResult.Data.ReasonCodes)) { $reasonCodes.Add([string]$code) }
    }

    $workflowValid = Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState
    if (-not $workflowValid) { $reasonCodes.Add('WORKFLOW_SESSION_INVALID') }
    elseif ($WorkflowSessionState.State -cne 'CLAIMED') { $reasonCodes.Add('WORKFLOW_SESSION_TERMINAL') }

    $useStateValid = Test-CddsiOperationUseBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState -OperationUseState $OperationUseState
    if (-not $useStateValid) { $reasonCodes.Add('OPERATION_USE_STATE_INVALID') }
    elseif ($OperationUseState.Operation -cne $Operation) { $reasonCodes.Add('OPERATION_USE_BINDING_MISMATCH') }

    $operationUseIdValid = Test-CddsiCanonicalUuidValue -Value $OperationUseId
    if (-not $operationUseIdValid) { $reasonCodes.Add('OPERATION_USE_ID_INVALID') }
    elseif ((Test-CddsiOperationGrant -Grant $OperationGrant) -and
        @(
            $OperationGrant.RunId,
            $OperationGrant.GrantId,
            $OperationGrant.Nonce,
            $AuthorizationSession.ClaimId,
            @($OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId })
        ) -ccontains $OperationUseId) {
        $reasonCodes.Add('OPERATION_USE_ID_COLLISION')
    }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }
    elseif ($useStateValid -and $OperationUseState.Revision -ne $ExpectedRevision) {
        $reasonCodes.Add('OPERATION_USE_CONCURRENCY_CONFLICT')
    }
    if ($useStateValid) {
        if ($OperationUseState.State -ceq 'CLAIMED') { $reasonCodes.Add('OPERATION_USE_REPLAY') }
        elseif ($OperationUseState.State -in @('COMPLETED', 'ABORTED')) { $reasonCodes.Add('OPERATION_USE_TERMINAL') }
        elseif ($OperationUseState.State -cne 'AVAILABLE') { $reasonCodes.Add('OPERATION_USE_NOT_AVAILABLE') }
    }

    $proposalCreated = ($reasonCodes.Count -eq 0)
    $proposedState = $null
    if ($proposalCreated) {
        $proposedState = [pscustomobject][ordered]@{
            SchemaVersion                  = $OperationUseState.SchemaVersion
            ContractVersion                = $OperationUseState.ContractVersion
            StateKeySha256                 = $OperationUseState.StateKeySha256
            State                          = 'CLAIMED'
            Stage                          = $OperationUseState.Stage
            ArtifactProfile                = $OperationUseState.ArtifactProfile
            RunId                          = $OperationUseState.RunId
            ArtifactSha256                 = $OperationUseState.ArtifactSha256
            SidecarSha256                  = $OperationUseState.SidecarSha256
            ContentDigest                  = $OperationUseState.ContentDigest
            GrantId                        = $OperationUseState.GrantId
            Nonce                          = $OperationUseState.Nonce
            ClaimId                        = $OperationUseState.ClaimId
            AuthorizationSessionRevision   = $OperationUseState.AuthorizationSessionRevision
            WorkflowSessionStateKeySha256  = $OperationUseState.WorkflowSessionStateKeySha256
            WorkflowSessionRevision        = $OperationUseState.WorkflowSessionRevision
            ConfirmationId                 = $OperationUseState.ConfirmationId
            ConfirmationPromptDigest       = $OperationUseState.ConfirmationPromptDigest
            ConfirmedAtUtc                 = $Confirmation.ConfirmedAtUtc
            ConfirmationConsumed           = $true
            Operation                      = $OperationUseState.Operation
            OperationUseId                 = $OperationUseId
            ClaimedAtUtc                   = $NowUtc
            ExpiresAtUtc                   = $OperationUseState.ExpiresAtUtc
            ProviderIdempotencyRequired    = $true
            ProviderInvocationOccurred     = $false
            ProviderEvidenceDigest         = $null
            OccurredAtUtc                  = $null
            TerminalReasonCode             = $null
            IdempotencyKey                 = $null
            Revision                       = $ExpectedRevision + 1
            ReceiptBindingToken            = $null
        }
        $proposedState.ReceiptBindingToken = Get-CddsiOperationUseBindingToken -OperationUseState $proposedState
        if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
            -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
            -OperationUseState $proposedState)) {
            $reasonCodes.Add('OPERATION_USE_PROPOSAL_INVALID')
            $proposalCreated = $false
            $proposedState = $null
        }
    }

    $data = [pscustomobject][ordered]@{
        SchemaVersion                   = 1
        ContractVersion                 = 'cddsi-operation-authorization-proposal-v1'
        AuthorizationProposed           = $proposalCreated
        Authorized                      = $false
        Executable                      = $false
        Committed                       = $false
        RequiresAtomicCompareAndSwap    = $proposalCreated
        ProviderExecutionAllowedBeforeCommit = $false
        ProviderIdempotencyKey          = if ($proposalCreated) { $OperationUseId } else { $null }
        StateKeySha256                  = if ($useStateValid) { $OperationUseState.StateKeySha256 } else { $null }
        PreviousRevision                = if ($useStateValid) { $OperationUseState.Revision } else { $null }
        NextRevision                    = if ($proposalCreated) { $proposedState.Revision } else { $null }
        ProposedOperationUseState       = $proposedState
        ReasonCodes                     = @($reasonCodes | Select-Object -Unique)
    }
    return New-CddsiOperationResult -Operation 'ProposeStageOperationAuthorization' `
        -Status $(if ($proposalCreated) { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }) `
        -ErrorCode $(if ($proposalCreated) { '' } else { 'OPERATION_AUTHORIZATION_PROPOSAL_FAILED' }) `
        -MessageSafe $(if ($proposalCreated) { 'The operation-use claim is a CAS proposal and is not executable until the exact state is committed.' } else { 'The operation-use claim proposal failed closed.' }) `
        -Data $data
}

function Test-CddsiCommittedOperationUseReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseState,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
            -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
            -OperationUseState $OperationUseState)) { return $false }
        if ($WorkflowSessionState.State -cne 'CLAIMED' -or
            $WorkflowSessionState.Revision -ne $OperationUseState.WorkflowSessionRevision -or
            $OperationUseState.State -cne 'CLAIMED' -or
            $OperationUseState.Operation -cne $Operation -or
            $OperationUseState.OperationUseId -cne $OperationUseId -or
            $OperationUseState.Revision -ne 1 -or
            -not $OperationUseState.ProviderIdempotencyRequired -or
            -not $OperationUseState.ConfirmationConsumed -or
            $OperationUseState.ProviderInvocationOccurred) { return $false }
        if (-not (Test-CddsiCanonicalUuidValue -Value $OperationUseId) -or
            $ValidationTimeUtc -isnot [string] -or
            -not [regex]::IsMatch($ValidationTimeUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -or
            -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)) { return $false }
        $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
        return ($validationTime -ge [DateTimeOffset]::Parse($OperationUseState.ClaimedAtUtc) -and
            $validationTime -lt [DateTimeOffset]::Parse($OperationUseState.ExpiresAtUtc))
    }
    catch { return $false }
}

function Test-CddsiTerminalOperationUseReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseState,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome,
        [Parameter(Mandatory = $true)][string]$ExpectedProviderEvidenceDigest
    )

    if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $OperationUseState)) { return $false }
    return (
        $OperationUseState.State -ceq $Outcome -and
        $OperationUseState.ConfirmationConsumed -and
        $OperationUseState.ProviderInvocationOccurred -and
        $OperationUseState.Operation -ceq $Operation -and
        $OperationUseState.OperationUseId -ceq $OperationUseId -and
        $OperationUseState.ProviderEvidenceDigest -ceq $ExpectedProviderEvidenceDigest -and
        $ExpectedProviderEvidenceDigest -match '^[a-f0-9]{64}$'
    )
}

function Resolve-CddsiOperationUseTerminal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseState,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome,
        [Parameter(Mandatory = $true)][string]$ProviderEvidenceDigest,
        [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [string]$TerminalReasonCode = ''
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $workflowValid = Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState
    if (-not $workflowValid) { $reasonCodes.Add('WORKFLOW_SESSION_INVALID') }
    $useStateValid = Test-CddsiOperationUseBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState -OperationUseState $OperationUseState
    if (-not $useStateValid) { $reasonCodes.Add('OPERATION_USE_STATE_INVALID') }
    elseif ($OperationUseState.Operation -cne $Operation -or $OperationUseState.OperationUseId -cne $OperationUseId) {
        $reasonCodes.Add('OPERATION_USE_BINDING_MISMATCH')
    }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $OperationUseId)) { $reasonCodes.Add('OPERATION_USE_ID_INVALID') }
    if ($ProviderEvidenceDigest -isnot [string] -or $ProviderEvidenceDigest -notmatch '^[a-f0-9]{64}$') {
        $reasonCodes.Add('PROVIDER_EVIDENCE_DIGEST_INVALID')
    }
    $idempotencyKeyValid = Test-CddsiCanonicalUuidValue -Value $IdempotencyKey
    if (-not $idempotencyKeyValid) { $reasonCodes.Add('IDEMPOTENCY_KEY_INVALID') }
    elseif (@(
        $OperationGrant.RunId,
        $OperationGrant.GrantId,
        $OperationGrant.Nonce,
        $AuthorizationSession.ClaimId,
        $OperationUseId,
        @($OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId })
    ) -ccontains $IdempotencyKey) { $reasonCodes.Add('IDEMPOTENCY_KEY_COLLISION') }
    $occurredAtValid = (
        $OccurredAtUtc -is [string] -and
        [regex]::IsMatch($OccurredAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $OccurredAtUtc)
    )
    if (-not $occurredAtValid) { $reasonCodes.Add('OCCURRED_AT_INVALID') }
    if ($Outcome -ceq 'COMPLETED') {
        if ($TerminalReasonCode -cne '') { $reasonCodes.Add('TERMINAL_REASON_INVALID') }
    }
    elseif ($script:CddsiOperationAbortReasonCodes -cnotcontains $TerminalReasonCode) {
        $reasonCodes.Add('TERMINAL_REASON_INVALID')
    }

    $terminalState = $null
    $idempotentReplay = $false
    $requiresCas = $false
    if ($reasonCodes.Count -eq 0 -and $useStateValid) {
        if ($OperationUseState.State -in @('COMPLETED', 'ABORTED')) {
            $sameReceipt = (
                $OperationUseState.State -ceq $Outcome -and
                $OperationUseState.Operation -ceq $Operation -and
                $OperationUseState.OperationUseId -ceq $OperationUseId -and
                $OperationUseState.ProviderEvidenceDigest -ceq $ProviderEvidenceDigest -and
                $OperationUseState.OccurredAtUtc -ceq $OccurredAtUtc -and
                $OperationUseState.IdempotencyKey -ceq $IdempotencyKey -and
                $OperationUseState.TerminalReasonCode -ceq $TerminalReasonCode
            )
            if ($sameReceipt -and @($OperationUseState.Revision, ($OperationUseState.Revision - 1)) -contains $ExpectedRevision) {
                $terminalState = $OperationUseState
                $idempotentReplay = $true
            }
            elseif ($OperationUseState.IdempotencyKey -ceq $IdempotencyKey) {
                $reasonCodes.Add('OPERATION_USE_IDEMPOTENCY_CONFLICT')
            }
            else { $reasonCodes.Add('OPERATION_USE_TERMINAL_REPLAY') }
        }
        elseif ($OperationUseState.State -cne 'CLAIMED') {
            $reasonCodes.Add('OPERATION_USE_NOT_CLAIMED')
        }
        elseif ($ExpectedRevision -ne $OperationUseState.Revision) {
            $reasonCodes.Add('OPERATION_USE_CONCURRENCY_CONFLICT')
        }
        elseif ($WorkflowSessionState.State -cne 'CLAIMED') {
            $reasonCodes.Add('WORKFLOW_SESSION_TERMINAL')
        }
        elseif (-not $occurredAtValid -or
            [DateTimeOffset]::Parse($OccurredAtUtc) -lt [DateTimeOffset]::Parse($OperationUseState.ClaimedAtUtc) -or
            [DateTimeOffset]::Parse($OccurredAtUtc) -ge [DateTimeOffset]::Parse($OperationUseState.ExpiresAtUtc)) {
            $reasonCodes.Add('OPERATION_USE_TIME_INVALID')
        }
        else {
            $terminalState = [pscustomobject][ordered]@{
                SchemaVersion                  = $OperationUseState.SchemaVersion
                ContractVersion                = $OperationUseState.ContractVersion
                StateKeySha256                 = $OperationUseState.StateKeySha256
                State                          = $Outcome
                Stage                          = $OperationUseState.Stage
                ArtifactProfile                = $OperationUseState.ArtifactProfile
                RunId                          = $OperationUseState.RunId
                ArtifactSha256                 = $OperationUseState.ArtifactSha256
                SidecarSha256                  = $OperationUseState.SidecarSha256
                ContentDigest                  = $OperationUseState.ContentDigest
                GrantId                        = $OperationUseState.GrantId
                Nonce                          = $OperationUseState.Nonce
                ClaimId                        = $OperationUseState.ClaimId
                AuthorizationSessionRevision   = $OperationUseState.AuthorizationSessionRevision
                WorkflowSessionStateKeySha256  = $OperationUseState.WorkflowSessionStateKeySha256
                WorkflowSessionRevision        = $OperationUseState.WorkflowSessionRevision
                ConfirmationId                 = $OperationUseState.ConfirmationId
                ConfirmationPromptDigest       = $OperationUseState.ConfirmationPromptDigest
                ConfirmedAtUtc                 = $OperationUseState.ConfirmedAtUtc
                ConfirmationConsumed           = $true
                Operation                      = $OperationUseState.Operation
                OperationUseId                 = $OperationUseState.OperationUseId
                ClaimedAtUtc                   = $OperationUseState.ClaimedAtUtc
                ExpiresAtUtc                   = $OperationUseState.ExpiresAtUtc
                ProviderIdempotencyRequired    = $true
                ProviderInvocationOccurred     = $true
                ProviderEvidenceDigest         = $ProviderEvidenceDigest
                OccurredAtUtc                  = $OccurredAtUtc
                TerminalReasonCode             = $TerminalReasonCode
                IdempotencyKey                 = $IdempotencyKey
                Revision                       = $OperationUseState.Revision + 1
                ReceiptBindingToken            = $null
            }
            $terminalState.ReceiptBindingToken = Get-CddsiOperationUseBindingToken -OperationUseState $terminalState
            if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $WorkflowSessionState -OperationUseState $terminalState `
                -Operation $Operation -OperationUseId $OperationUseId -Outcome $Outcome `
                -ExpectedProviderEvidenceDigest $ProviderEvidenceDigest)) {
                $reasonCodes.Add('OPERATION_USE_TERMINAL_PROPOSAL_INVALID')
                $terminalState = $null
            }
            else { $requiresCas = $true }
        }
    }

    $succeeded = ($null -ne $terminalState -and $reasonCodes.Count -eq 0)
    $data = [pscustomobject][ordered]@{
        SchemaVersion                = 1
        ContractVersion              = 'cddsi-operation-use-terminal-reduction-v1'
        Terminalized                 = ($succeeded -and -not $idempotentReplay)
        IdempotentReplay             = $idempotentReplay
        RequiresAtomicCompareAndSwap = $requiresCas
        StateKeySha256               = if ($useStateValid) { $OperationUseState.StateKeySha256 } else { $null }
        PreviousRevision             = if ($useStateValid) { $OperationUseState.Revision } else { $null }
        NextRevision                 = if ($succeeded) { $terminalState.Revision } else { $null }
        TerminalOperationUseState    = if ($succeeded) { $terminalState } else { $null }
        ReasonCodes                  = @($reasonCodes | Select-Object -Unique)
    }
    return New-CddsiOperationResult -Operation 'ReduceOperationUseTerminal' `
        -Status $(if ($succeeded) { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }) `
        -ErrorCode $(if ($succeeded) { '' } else { 'OPERATION_USE_TERMINAL_FAILED' }) `
        -MessageSafe $(if ($idempotentReplay) { 'The exact terminal operation receipt was returned idempotently.' } elseif ($succeeded) { 'The terminal operation-use state is ready for atomic compare-and-swap persistence.' } else { 'The terminal operation-use reduction failed closed.' }) `
        -Data $data
}

function Resolve-CddsiUnexecutedOperationUseAbort {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseState,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][ValidateSet('NOT_RUN_DUE_TO_ABORT', 'NOT_REQUIRED')][string]$ReasonCode,
        [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $workflowValid = Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState
    if (-not $workflowValid) { $reasonCodes.Add('WORKFLOW_SESSION_INVALID') }
    $useStateValid = Test-CddsiOperationUseBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState -OperationUseState $OperationUseState
    if (-not $useStateValid) { $reasonCodes.Add('OPERATION_USE_STATE_INVALID') }
    elseif ($OperationUseState.Operation -cne $Operation) { $reasonCodes.Add('OPERATION_USE_BINDING_MISMATCH') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $OperationUseId)) { $reasonCodes.Add('OPERATION_USE_ID_INVALID') }
    elseif (@(
        $OperationGrant.RunId,
        $OperationGrant.GrantId,
        $OperationGrant.Nonce,
        $AuthorizationSession.ClaimId,
        @($OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId })
    ) -ccontains $OperationUseId) { $reasonCodes.Add('OPERATION_USE_ID_COLLISION') }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $IdempotencyKey)) { $reasonCodes.Add('IDEMPOTENCY_KEY_INVALID') }
    elseif (@(
        $OperationGrant.RunId,
        $OperationGrant.GrantId,
        $OperationGrant.Nonce,
        $AuthorizationSession.ClaimId,
        $OperationUseId,
        @($OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId })
    ) -ccontains $IdempotencyKey) { $reasonCodes.Add('IDEMPOTENCY_KEY_COLLISION') }
    $occurredAtValid = (
        $OccurredAtUtc -is [string] -and
        [regex]::IsMatch($OccurredAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $OccurredAtUtc)
    )
    if (-not $occurredAtValid) { $reasonCodes.Add('OCCURRED_AT_INVALID') }
    if ($ReasonCode -ceq 'NOT_REQUIRED' -and
        -not (Test-CddsiGrantCompensationOperation -OperationGrant $OperationGrant -Operation $Operation)) {
        $reasonCodes.Add('NOT_REQUIRED_OPERATION_NOT_COMPENSATION')
    }

    $terminalState = $null
    $idempotentReplay = $false
    $requiresCas = $false
    if ($reasonCodes.Count -eq 0 -and $useStateValid) {
        $isUnexecutedAbort = (
            $OperationUseState.State -ceq 'ABORTED' -and
            -not $OperationUseState.ConfirmationConsumed -and
            -not $OperationUseState.ProviderInvocationOccurred
        )
        if ($isUnexecutedAbort) {
            $sameReceipt = (
                $OperationUseState.Operation -ceq $Operation -and
                $OperationUseState.OperationUseId -ceq $OperationUseId -and
                $OperationUseState.OccurredAtUtc -ceq $OccurredAtUtc -and
                $OperationUseState.IdempotencyKey -ceq $IdempotencyKey -and
                $OperationUseState.TerminalReasonCode -ceq $ReasonCode
            )
            if ($sameReceipt -and @($OperationUseState.Revision, ($OperationUseState.Revision - 1)) -contains $ExpectedRevision) {
                $terminalState = $OperationUseState
                $idempotentReplay = $true
            }
            elseif ($OperationUseState.IdempotencyKey -ceq $IdempotencyKey) {
                $reasonCodes.Add('OPERATION_USE_IDEMPOTENCY_CONFLICT')
            }
            else { $reasonCodes.Add('OPERATION_USE_TERMINAL_REPLAY') }
        }
        elseif ($OperationUseState.State -cne 'AVAILABLE') {
            $reasonCodes.Add('OPERATION_USE_NOT_AVAILABLE')
        }
        elseif ($ExpectedRevision -ne $OperationUseState.Revision) {
            $reasonCodes.Add('OPERATION_USE_CONCURRENCY_CONFLICT')
        }
        elseif ($WorkflowSessionState.State -cne 'CLAIMED') {
            $reasonCodes.Add('WORKFLOW_SESSION_TERMINAL')
        }
        elseif (-not $occurredAtValid -or
            [DateTimeOffset]::Parse($OccurredAtUtc) -lt [DateTimeOffset]::Parse($WorkflowSessionState.ClaimedAtUtc) -or
            [DateTimeOffset]::Parse($OccurredAtUtc) -ge [DateTimeOffset]::Parse($OperationUseState.ExpiresAtUtc)) {
            $reasonCodes.Add('OPERATION_USE_TIME_INVALID')
        }
        else {
            $terminalState = [pscustomobject][ordered]@{
                SchemaVersion                  = $OperationUseState.SchemaVersion
                ContractVersion                = $OperationUseState.ContractVersion
                StateKeySha256                 = $OperationUseState.StateKeySha256
                State                          = 'ABORTED'
                Stage                          = $OperationUseState.Stage
                ArtifactProfile                = $OperationUseState.ArtifactProfile
                RunId                          = $OperationUseState.RunId
                ArtifactSha256                 = $OperationUseState.ArtifactSha256
                SidecarSha256                  = $OperationUseState.SidecarSha256
                ContentDigest                  = $OperationUseState.ContentDigest
                GrantId                        = $OperationUseState.GrantId
                Nonce                          = $OperationUseState.Nonce
                ClaimId                        = $OperationUseState.ClaimId
                AuthorizationSessionRevision   = $OperationUseState.AuthorizationSessionRevision
                WorkflowSessionStateKeySha256  = $OperationUseState.WorkflowSessionStateKeySha256
                WorkflowSessionRevision        = $OperationUseState.WorkflowSessionRevision
                ConfirmationId                 = $OperationUseState.ConfirmationId
                ConfirmationPromptDigest       = $OperationUseState.ConfirmationPromptDigest
                ConfirmedAtUtc                 = $null
                ConfirmationConsumed           = $false
                Operation                      = $OperationUseState.Operation
                OperationUseId                 = $OperationUseId
                ClaimedAtUtc                   = $null
                ExpiresAtUtc                   = $OperationUseState.ExpiresAtUtc
                ProviderIdempotencyRequired    = $true
                ProviderInvocationOccurred     = $false
                ProviderEvidenceDigest         = $null
                OccurredAtUtc                  = $OccurredAtUtc
                TerminalReasonCode             = $ReasonCode
                IdempotencyKey                 = $IdempotencyKey
                Revision                       = $OperationUseState.Revision + 1
                ReceiptBindingToken            = $null
            }
            $terminalState.ReceiptBindingToken = Get-CddsiOperationUseBindingToken -OperationUseState $terminalState
            if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $WorkflowSessionState -OperationUseState $terminalState)) {
                $reasonCodes.Add('UNEXECUTED_OPERATION_ABORT_PROPOSAL_INVALID')
                $terminalState = $null
            }
            else { $requiresCas = $true }
        }
    }

    $succeeded = ($null -ne $terminalState -and $reasonCodes.Count -eq 0)
    $data = [pscustomobject][ordered]@{
        SchemaVersion                = 1
        ContractVersion              = 'cddsi-unexecuted-operation-abort-reduction-v1'
        Terminalized                 = ($succeeded -and -not $idempotentReplay)
        IdempotentReplay             = $idempotentReplay
        Unexecuted                   = $succeeded
        ConfirmationConsumed         = $false
        ProviderInvocationOccurred   = $false
        RequiresAtomicCompareAndSwap = $requiresCas
        StateKeySha256               = if ($useStateValid) { $OperationUseState.StateKeySha256 } else { $null }
        PreviousRevision             = if ($useStateValid) { $OperationUseState.Revision } else { $null }
        NextRevision                 = if ($succeeded) { $terminalState.Revision } else { $null }
        TerminalOperationUseState    = if ($succeeded) { $terminalState } else { $null }
        ReasonCodes                  = @($reasonCodes | Select-Object -Unique)
    }
    return New-CddsiOperationResult -Operation 'ReduceUnexecutedOperationAbort' `
        -Status $(if ($succeeded) { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }) `
        -ErrorCode $(if ($succeeded) { '' } else { 'UNEXECUTED_OPERATION_ABORT_FAILED' }) `
        -MessageSafe $(if ($idempotentReplay) { 'The exact unexecuted-operation receipt was returned idempotently.' } elseif ($succeeded) { 'The unexecuted-operation abort is ready for atomic compare-and-swap persistence.' } else { 'The unexecuted-operation abort failed closed.' }) `
        -Data $data
}

function Get-CddsiTerminalOperationSetDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$OperationUseStates
    )

    if (-not (Test-CddsiOperationGrant -Grant $OperationGrant)) { throw 'OperationGrant is invalid.' }
    $states = @($OperationUseStates)
    if ($states.Count -ne @($OperationGrant.AllowedOperations).Count) { throw 'Terminal operation state count does not match the grant.' }
    $lines = @('cddsi-terminal-operation-set-v1')
    for ($index = 0; $index -lt $states.Count; $index++) {
        if (-not (Test-CddsiOperationUseState -OperationUseState $states[$index]) -or
            $states[$index].State -cnotin @('COMPLETED', 'ABORTED') -or
            $states[$index].Operation -cne $OperationGrant.AllowedOperations[$index]) {
            throw 'Terminal operation state order or contract is invalid.'
        }
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $states[$index].Operation
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $states[$index].OperationUseId
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $states[$index].State
        $lines += ConvertTo-CddsiStagePolicyBindingField -Value $states[$index].ReceiptBindingToken
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($lines -join "`n")
}

function Resolve-CddsiWorkflowSessionTerminal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseStates,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome,
        [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$IdempotencyKey,
        [string]$TerminalReasonCode = ''
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $workflowValid = Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState
    if (-not $workflowValid) { $reasonCodes.Add('WORKFLOW_SESSION_INVALID') }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }
    $occurredAtValid = (
        $OccurredAtUtc -is [string] -and
        [regex]::IsMatch($OccurredAtUtc, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $OccurredAtUtc)
    )
    if (-not $occurredAtValid) { $reasonCodes.Add('OCCURRED_AT_INVALID') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $IdempotencyKey)) { $reasonCodes.Add('IDEMPOTENCY_KEY_INVALID') }
    elseif (@(
        $OperationGrant.RunId,
        $OperationGrant.GrantId,
        $OperationGrant.Nonce,
        $AuthorizationSession.ClaimId,
        @($OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId }),
        @($OperationUseStates | ForEach-Object { $_.OperationUseId; $_.IdempotencyKey })
    ) -ccontains $IdempotencyKey) { $reasonCodes.Add('IDEMPOTENCY_KEY_COLLISION') }
    if ($Outcome -ceq 'COMPLETED') {
        if ($TerminalReasonCode -cne '') { $reasonCodes.Add('TERMINAL_REASON_INVALID') }
    }
    elseif ($script:CddsiWorkflowAbortReasonCodes -cnotcontains $TerminalReasonCode) {
        $reasonCodes.Add('TERMINAL_REASON_INVALID')
    }

    $states = @($OperationUseStates)
    $operationsValid = $true
    $seenStateKeys = @{}
    $seenUseIds = @{}
    $seenIdempotencyKeys = @{}
    if ($states.Count -ne @($OperationGrant.AllowedOperations).Count) {
        $reasonCodes.Add('TERMINAL_OPERATION_SET_INCOMPLETE')
        $operationsValid = $false
    }
    else {
        for ($index = 0; $index -lt $states.Count; $index++) {
            $state = $states[$index]
            $expectedOperation = $OperationGrant.AllowedOperations[$index]
            if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $WorkflowSessionState -OperationUseState $state) -or
                $state.Operation -cne $expectedOperation -or
                $state.State -cnotin @('COMPLETED', 'ABORTED')) {
                $reasonCodes.Add('TERMINAL_OPERATION_SET_INVALID')
                $operationsValid = $false
                continue
            }
            if ($seenStateKeys.ContainsKey($state.StateKeySha256) -or
                $seenUseIds.ContainsKey($state.OperationUseId) -or
                $seenIdempotencyKeys.ContainsKey($state.IdempotencyKey)) {
                $reasonCodes.Add('TERMINAL_OPERATION_SET_REPLAY')
                $operationsValid = $false
            }
            $seenStateKeys[$state.StateKeySha256] = $true
            $seenUseIds[$state.OperationUseId] = $true
            $seenIdempotencyKeys[$state.IdempotencyKey] = $true
            if ($occurredAtValid -and [DateTimeOffset]::Parse($state.OccurredAtUtc) -gt [DateTimeOffset]::Parse($OccurredAtUtc)) {
                $reasonCodes.Add('TERMINAL_OPERATION_TIME_INVALID')
                $operationsValid = $false
            }
        }
    }
    if ($operationsValid) {
        if ($Outcome -ceq 'COMPLETED') {
            foreach ($state in $states) {
                $optionalCompensationNotRequired = (
                    $state.State -ceq 'ABORTED' -and
                    -not $state.ConfirmationConsumed -and
                    -not $state.ProviderInvocationOccurred -and
                    $state.TerminalReasonCode -ceq 'NOT_REQUIRED' -and
                    (Test-CddsiGrantCompensationOperation -OperationGrant $OperationGrant -Operation $state.Operation)
                )
                if ($state.State -cne 'COMPLETED' -and -not $optionalCompensationNotRequired) {
                    $reasonCodes.Add('WORKFLOW_COMPLETION_REQUIRES_COMPLETED_OR_UNUSED_COMPENSATION')
                    $operationsValid = $false
                    break
                }
            }
        }
        elseif (@($states | Where-Object {
            $_.State -ceq 'ABORTED' -and $_.TerminalReasonCode -cne 'NOT_REQUIRED'
        }).Count -eq 0) {
            $reasonCodes.Add('WORKFLOW_ABORT_REQUIRES_ABORTED_OPERATION')
            $operationsValid = $false
        }
    }

    $terminalSetDigest = $null
    if ($operationsValid) {
        try { $terminalSetDigest = Get-CddsiTerminalOperationSetDigest -OperationGrant $OperationGrant -OperationUseStates $states }
        catch {
            $reasonCodes.Add('TERMINAL_OPERATION_SET_INVALID')
            $operationsValid = $false
        }
    }

    $terminalState = $null
    $idempotentReplay = $false
    $requiresCas = $false
    if ($reasonCodes.Count -eq 0 -and $workflowValid -and $operationsValid) {
        if ($WorkflowSessionState.State -in @('COMPLETED', 'ABORTED')) {
            $sameReceipt = (
                $WorkflowSessionState.State -ceq $Outcome -and
                $WorkflowSessionState.TerminalOperationSetDigestSha256 -ceq $terminalSetDigest -and
                $WorkflowSessionState.OccurredAtUtc -ceq $OccurredAtUtc -and
                $WorkflowSessionState.IdempotencyKey -ceq $IdempotencyKey -and
                $WorkflowSessionState.TerminalReasonCode -ceq $TerminalReasonCode
            )
            if ($sameReceipt -and @($WorkflowSessionState.Revision, ($WorkflowSessionState.Revision - 1)) -contains $ExpectedRevision) {
                $terminalState = $WorkflowSessionState
                $idempotentReplay = $true
            }
            elseif ($WorkflowSessionState.IdempotencyKey -ceq $IdempotencyKey) {
                $reasonCodes.Add('WORKFLOW_SESSION_IDEMPOTENCY_CONFLICT')
            }
            else { $reasonCodes.Add('WORKFLOW_SESSION_TERMINAL_REPLAY') }
        }
        elseif ($WorkflowSessionState.State -cne 'CLAIMED') {
            $reasonCodes.Add('WORKFLOW_SESSION_NOT_CLAIMED')
        }
        elseif ($ExpectedRevision -ne $WorkflowSessionState.Revision) {
            $reasonCodes.Add('WORKFLOW_SESSION_CONCURRENCY_CONFLICT')
        }
        elseif (-not $occurredAtValid -or
            [DateTimeOffset]::Parse($OccurredAtUtc) -lt [DateTimeOffset]::Parse($WorkflowSessionState.ClaimedAtUtc) -or
            [DateTimeOffset]::Parse($OccurredAtUtc) -ge [DateTimeOffset]::Parse($WorkflowSessionState.ExpiresAtUtc)) {
            $reasonCodes.Add('WORKFLOW_SESSION_TIME_INVALID')
        }
        else {
            $terminalState = [pscustomobject][ordered]@{
                SchemaVersion                    = $WorkflowSessionState.SchemaVersion
                ContractVersion                  = $WorkflowSessionState.ContractVersion
                StateKeySha256                   = $WorkflowSessionState.StateKeySha256
                State                            = $Outcome
                Stage                            = $WorkflowSessionState.Stage
                ArtifactProfile                  = $WorkflowSessionState.ArtifactProfile
                RunId                            = $WorkflowSessionState.RunId
                ArtifactSha256                   = $WorkflowSessionState.ArtifactSha256
                SidecarSha256                    = $WorkflowSessionState.SidecarSha256
                ContentDigest                    = $WorkflowSessionState.ContentDigest
                GrantId                          = $WorkflowSessionState.GrantId
                Nonce                            = $WorkflowSessionState.Nonce
                ClaimId                          = $WorkflowSessionState.ClaimId
                AuthorizationSessionRevision     = $WorkflowSessionState.AuthorizationSessionRevision
                ClaimedAtUtc                     = $WorkflowSessionState.ClaimedAtUtc
                ExpiresAtUtc                     = $WorkflowSessionState.ExpiresAtUtc
                OperationSetDigestSha256         = $WorkflowSessionState.OperationSetDigestSha256
                OperationCount                   = $WorkflowSessionState.OperationCount
                TerminalOperationSetDigestSha256 = $terminalSetDigest
                OccurredAtUtc                    = $OccurredAtUtc
                TerminalReasonCode               = $TerminalReasonCode
                IdempotencyKey                   = $IdempotencyKey
                Revision                         = $WorkflowSessionState.Revision + 1
                ReceiptBindingToken              = $null
            }
            $terminalState.ReceiptBindingToken = Get-CddsiWorkflowSessionBindingToken -WorkflowSessionState $terminalState
            if (-not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest `
                -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
                -WorkflowSessionState $terminalState)) {
                $reasonCodes.Add('WORKFLOW_SESSION_TERMINAL_PROPOSAL_INVALID')
                $terminalState = $null
            }
            else { $requiresCas = $true }
        }
    }

    $succeeded = ($null -ne $terminalState -and $reasonCodes.Count -eq 0)
    $data = [pscustomobject][ordered]@{
        SchemaVersion                = 1
        ContractVersion              = 'cddsi-workflow-session-terminal-reduction-v1'
        Terminalized                 = ($succeeded -and -not $idempotentReplay)
        IdempotentReplay             = $idempotentReplay
        RequiresAtomicCompareAndSwap = $requiresCas
        StateKeySha256               = if ($workflowValid) { $WorkflowSessionState.StateKeySha256 } else { $null }
        PreviousRevision             = if ($workflowValid) { $WorkflowSessionState.Revision } else { $null }
        NextRevision                 = if ($succeeded) { $terminalState.Revision } else { $null }
        TerminalWorkflowSessionState = if ($succeeded) { $terminalState } else { $null }
        ReasonCodes                  = @($reasonCodes | Select-Object -Unique)
    }
    return New-CddsiOperationResult -Operation 'ReduceWorkflowSessionTerminal' `
        -Status $(if ($succeeded) { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }) `
        -ErrorCode $(if ($succeeded) { '' } else { 'WORKFLOW_SESSION_TERMINAL_FAILED' }) `
        -MessageSafe $(if ($idempotentReplay) { 'The exact terminal workflow receipt was returned idempotently.' } elseif ($succeeded) { 'The terminal workflow state is ready for atomic compare-and-swap persistence.' } else { 'The workflow terminal reduction failed closed.' }) `
        -Data $data
}
