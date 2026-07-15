# release-facts.ps1 - Pure P10A consumption to P10B frozen-facts contracts.
# This module never inspects the host, persists state or performs release work.
# Binding tokens are integrity identifiers, not authorization. A FROZEN state
# is usable only with a matching, RSA-SHA256 verified store commit receipt.

function Get-CddsiReleaseFactsFreezeStateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$FreezeState)

    $payload = [pscustomobject][ordered]@{
        ContractVersion                = 'cddsi-release-facts-freeze-state-key-v2'
        Purpose                        = $FreezeState.Purpose
        StoreAuthorityKeyId            = $FreezeState.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $FreezeState.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId                = $FreezeState.StoreInstanceId
        StoreEpoch                     = $FreezeState.StoreEpoch
        SessionAnchorToken             = $FreezeState.SessionAnchorToken
        SessionBindingToken            = $FreezeState.SessionBindingToken
        EvidenceBindingToken           = $FreezeState.EvidenceBindingToken
        ConsumptionStateKeySha256      = $FreezeState.ConsumptionStateKeySha256
        ConsumptionStateBindingToken   = $FreezeState.ConsumptionStateBindingToken
        ConsumptionCommitReceiptBindingToken = $FreezeState.ConsumptionCommitReceiptBindingToken
        ConsumptionId                  = $FreezeState.ConsumptionId
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Get-CddsiReleaseFactsFreezeStateBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$FreezeState)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion                      = $FreezeState.SchemaVersion
        ContractVersion                    = $FreezeState.ContractVersion
        Purpose                            = $FreezeState.Purpose
        StateKeySha256                     = $FreezeState.StateKeySha256
        State                              = $FreezeState.State
        StoreAuthorityKeyId                = $FreezeState.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $FreezeState.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId                    = $FreezeState.StoreInstanceId
        StoreEpoch                         = $FreezeState.StoreEpoch
        SessionAnchorToken                 = $FreezeState.SessionAnchorToken
        SessionBindingToken                = $FreezeState.SessionBindingToken
        EvidenceBindingToken               = $FreezeState.EvidenceBindingToken
        ConsumptionStateKeySha256          = $FreezeState.ConsumptionStateKeySha256
        ConsumptionStateBindingToken       = $FreezeState.ConsumptionStateBindingToken
        ConsumptionCommitReceiptBindingToken = $FreezeState.ConsumptionCommitReceiptBindingToken
        ConsumptionId                      = $FreezeState.ConsumptionId
        FreezeId                           = $FreezeState.FreezeId
        FactsBindingToken                  = $FreezeState.FactsBindingToken
        FrozenAtUtc                        = $FreezeState.FrozenAtUtc
        ExpiresAtUtc                       = $FreezeState.ExpiresAtUtc
        Revision                           = $FreezeState.Revision
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiReleaseFactsFreezeState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$FreezeState)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $FreezeState -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'StateKeySha256', 'State',
            'StoreAuthorityKeyId', 'StoreAuthorityKeyFingerprintSha256',
            'StoreInstanceId', 'StoreEpoch',
            'SessionAnchorToken', 'SessionBindingToken', 'EvidenceBindingToken',
            'ConsumptionStateKeySha256', 'ConsumptionStateBindingToken',
            'ConsumptionCommitReceiptBindingToken',
            'ConsumptionId', 'FreezeId', 'FactsBindingToken', 'FrozenAtUtc',
            'ExpiresAtUtc', 'Revision', 'StateBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $FreezeState.SchemaVersion) -or
            $FreezeState.ContractVersion -cne 'cddsi-release-facts-freeze-state-v2' -or
            $FreezeState.Purpose -cne 'P10B_RELEASE_FACTS_FREEZE_STATE' -or
            $FreezeState.State -cnotin @('AVAILABLE', 'FROZEN')) { return $false }
        foreach ($name in @(
            'StateKeySha256', 'StoreAuthorityKeyFingerprintSha256',
            'SessionAnchorToken', 'SessionBindingToken',
            'EvidenceBindingToken', 'ConsumptionStateKeySha256',
            'ConsumptionStateBindingToken', 'ConsumptionCommitReceiptBindingToken',
            'StateBindingToken'
        )) {
            if ($FreezeState.$name -isnot [string] -or $FreezeState.$name -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (-not (Test-CddsiCanonicalUuidValue -Value $FreezeState.StoreAuthorityKeyId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $FreezeState.StoreInstanceId) -or
            ($FreezeState.StoreEpoch -isnot [int] -and $FreezeState.StoreEpoch -isnot [long]) -or
            [long]$FreezeState.StoreEpoch -lt 1 -or
            -not (Test-CddsiCanonicalUuidValue -Value $FreezeState.ConsumptionId) -or
            -not (Test-CddsiVmCalibrationTimestampValue -Value $FreezeState.ExpiresAtUtc)) { return $false }
        if ($FreezeState.Revision -isnot [int] -and $FreezeState.Revision -isnot [long]) { return $false }
        if ($FreezeState.State -ceq 'AVAILABLE') {
            if ($null -ne $FreezeState.FreezeId -or $null -ne $FreezeState.FactsBindingToken -or
                $null -ne $FreezeState.FrozenAtUtc -or [long]$FreezeState.Revision -ne 0) { return $false }
        }
        else {
            if (-not (Test-CddsiCanonicalUuidValue -Value $FreezeState.FreezeId) -or
                $FreezeState.FactsBindingToken -isnot [string] -or $FreezeState.FactsBindingToken -notmatch '^[a-f0-9]{64}$' -or
                -not (Test-CddsiVmCalibrationTimestampValue -Value $FreezeState.FrozenAtUtc) -or
                [long]$FreezeState.Revision -ne 1 -or
                [DateTimeOffset]::Parse($FreezeState.FrozenAtUtc) -ge [DateTimeOffset]::Parse($FreezeState.ExpiresAtUtc)) { return $false }
        }
        return (
            $FreezeState.StateKeySha256 -ceq (Get-CddsiReleaseFactsFreezeStateKey -FreezeState $FreezeState) -and
            $FreezeState.StateBindingToken -ceq (Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $FreezeState)
        )
    }
    catch { return $false }
}

function Get-CddsiReleaseFactsFreezeProposalBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$CommitProposal)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion = $CommitProposal.SchemaVersion; ContractVersion = $CommitProposal.ContractVersion
        Purpose = $CommitProposal.Purpose; Domain = $CommitProposal.Domain
        StoreAuthorityKeyId = $CommitProposal.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $CommitProposal.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId = $CommitProposal.StoreInstanceId; StoreEpoch = $CommitProposal.StoreEpoch
        TransactionId = $CommitProposal.TransactionId; StateKeySha256 = $CommitProposal.StateKeySha256
        OldRevision = $CommitProposal.OldRevision; NewRevision = $CommitProposal.NewRevision
        OldStateBindingToken = $CommitProposal.OldStateBindingToken
        NewStateBindingToken = $CommitProposal.NewStateBindingToken; ProposalNonce = $CommitProposal.ProposalNonce
        SessionAnchorToken = $CommitProposal.SessionAnchorToken; SessionBindingToken = $CommitProposal.SessionBindingToken
        EvidenceBindingToken = $CommitProposal.EvidenceBindingToken; ConsumptionId = $CommitProposal.ConsumptionId
        FreezeId = $CommitProposal.FreezeId; FactsBindingToken = $CommitProposal.FactsBindingToken
        ProposedState = $CommitProposal.ProposedState
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiReleaseFactsFreezeCommitProposal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$CommitProposal)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $CommitProposal -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'Domain', 'StoreAuthorityKeyId',
            'StoreAuthorityKeyFingerprintSha256', 'StoreInstanceId', 'StoreEpoch',
            'TransactionId', 'StateKeySha256', 'OldRevision', 'NewRevision',
            'OldStateBindingToken', 'NewStateBindingToken', 'ProposalNonce',
            'SessionAnchorToken', 'SessionBindingToken', 'EvidenceBindingToken',
            'ConsumptionId', 'FreezeId', 'FactsBindingToken', 'ProposedState',
            'ProposalBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $CommitProposal.SchemaVersion) -or
            $CommitProposal.ContractVersion -cne 'cddsi-release-facts-freeze-commit-proposal-v1' -or
            $CommitProposal.Purpose -cne 'P10B_RELEASE_FACTS_FREEZE_COMMIT' -or
            $CommitProposal.Domain -cne 'P10B_RELEASE_FACTS_FREEZE' -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.StoreAuthorityKeyId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.StoreInstanceId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.TransactionId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.ProposalNonce) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.ConsumptionId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.FreezeId) -or
            $CommitProposal.FactsBindingToken -isnot [string] -or $CommitProposal.FactsBindingToken -notmatch '^[a-f0-9]{64}$' -or
            ($CommitProposal.StoreEpoch -isnot [int] -and $CommitProposal.StoreEpoch -isnot [long]) -or
            ($CommitProposal.OldRevision -isnot [int] -and $CommitProposal.OldRevision -isnot [long]) -or
            ($CommitProposal.NewRevision -isnot [int] -and $CommitProposal.NewRevision -isnot [long]) -or
            [long]$CommitProposal.StoreEpoch -lt 1 -or [long]$CommitProposal.OldRevision -ne 0 -or [long]$CommitProposal.NewRevision -ne 1) { return $false }
        foreach ($name in @(
            'StoreAuthorityKeyFingerprintSha256', 'StateKeySha256', 'OldStateBindingToken',
            'NewStateBindingToken', 'SessionAnchorToken', 'SessionBindingToken',
            'EvidenceBindingToken', 'ProposalBindingToken'
        )) {
            if ($CommitProposal.$name -isnot [string] -or $CommitProposal.$name -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (-not (Test-CddsiReleaseFactsFreezeState -FreezeState $CommitProposal.ProposedState) -or
            $CommitProposal.ProposedState.State -cne 'FROZEN' -or
            $CommitProposal.ProposedState.StateKeySha256 -cne $CommitProposal.StateKeySha256 -or
            $CommitProposal.ProposedState.StateBindingToken -cne $CommitProposal.NewStateBindingToken -or
            $CommitProposal.ProposedState.FreezeId -cne $CommitProposal.FreezeId -or
            $CommitProposal.ProposedState.FactsBindingToken -cne $CommitProposal.FactsBindingToken -or
            $CommitProposal.ProposedState.StoreAuthorityKeyId -cne $CommitProposal.StoreAuthorityKeyId -or
            $CommitProposal.ProposedState.StoreAuthorityKeyFingerprintSha256 -cne $CommitProposal.StoreAuthorityKeyFingerprintSha256 -or
            $CommitProposal.ProposedState.StoreInstanceId -cne $CommitProposal.StoreInstanceId -or
            [long]$CommitProposal.ProposedState.StoreEpoch -ne [long]$CommitProposal.StoreEpoch -or
            $CommitProposal.ProposedState.SessionAnchorToken -cne $CommitProposal.SessionAnchorToken -or
            $CommitProposal.ProposedState.SessionBindingToken -cne $CommitProposal.SessionBindingToken -or
            $CommitProposal.ProposedState.EvidenceBindingToken -cne $CommitProposal.EvidenceBindingToken -or
            $CommitProposal.ProposedState.ConsumptionId -cne $CommitProposal.ConsumptionId -or
            $CommitProposal.ProposalBindingToken -cne (Get-CddsiReleaseFactsFreezeProposalBindingToken -CommitProposal $CommitProposal)) { return $false }
        return $true
    }
    catch { return $false }
}

function Test-CddsiCommittedReleaseFactsFreezeReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$FreezeState,
        [Parameter(Mandatory = $true)]$CommitReceipt,
        [Parameter(Mandatory = $true)]$StoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedEvidenceBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionStateKeySha256,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionStateBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionCommitReceiptBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory = $true)][string]$ExpectedFreezeId,
        [Parameter(Mandatory = $true)][string]$ExpectedFactsBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedProposalNonce,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        if (-not (Test-CddsiReleaseFactsFreezeState -FreezeState $FreezeState) -or
            $FreezeState.State -cne 'FROZEN' -or
            $FreezeState.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
            $FreezeState.SessionBindingToken -cne $ExpectedSessionBindingToken -or
            $FreezeState.EvidenceBindingToken -cne $ExpectedEvidenceBindingToken -or
            $FreezeState.ConsumptionStateKeySha256 -cne $ExpectedConsumptionStateKeySha256 -or
            $FreezeState.ConsumptionStateBindingToken -cne $ExpectedConsumptionStateBindingToken -or
            $FreezeState.ConsumptionCommitReceiptBindingToken -cne $ExpectedConsumptionCommitReceiptBindingToken -or
            $FreezeState.ConsumptionId -cne $ExpectedConsumptionId -or
            $FreezeState.FreezeId -cne $ExpectedFreezeId -or
            $FreezeState.FactsBindingToken -cne $ExpectedFactsBindingToken -or
            -not (Test-CddsiCasCommitReceiptSignature -CommitReceipt $CommitReceipt -StoreAuthorityPublicKey $StoreAuthorityPublicKey) -or
            -not (Test-CddsiVmCalibrationTimestampValue -Value $ValidationTimeUtc)) { return $false }
        $availableState = [pscustomobject][ordered]@{
            SchemaVersion = $FreezeState.SchemaVersion; ContractVersion = $FreezeState.ContractVersion
            Purpose = $FreezeState.Purpose; StateKeySha256 = $FreezeState.StateKeySha256; State = 'AVAILABLE'
            StoreAuthorityKeyId = $FreezeState.StoreAuthorityKeyId
            StoreAuthorityKeyFingerprintSha256 = $FreezeState.StoreAuthorityKeyFingerprintSha256
            StoreInstanceId = $FreezeState.StoreInstanceId; StoreEpoch = $FreezeState.StoreEpoch
            SessionAnchorToken = $FreezeState.SessionAnchorToken; SessionBindingToken = $FreezeState.SessionBindingToken
            EvidenceBindingToken = $FreezeState.EvidenceBindingToken
            ConsumptionStateKeySha256 = $FreezeState.ConsumptionStateKeySha256
            ConsumptionStateBindingToken = $FreezeState.ConsumptionStateBindingToken
            ConsumptionCommitReceiptBindingToken = $FreezeState.ConsumptionCommitReceiptBindingToken
            ConsumptionId = $FreezeState.ConsumptionId; FreezeId = $null; FactsBindingToken = $null
            FrozenAtUtc = $null; ExpiresAtUtc = $FreezeState.ExpiresAtUtc; Revision = 0; StateBindingToken = $null
        }
        $availableState.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $availableState
        $proposal = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-release-facts-freeze-commit-proposal-v1'
            Purpose = 'P10B_RELEASE_FACTS_FREEZE_COMMIT'; Domain = 'P10B_RELEASE_FACTS_FREEZE'
            StoreAuthorityKeyId = $FreezeState.StoreAuthorityKeyId
            StoreAuthorityKeyFingerprintSha256 = $FreezeState.StoreAuthorityKeyFingerprintSha256
            StoreInstanceId = $FreezeState.StoreInstanceId; StoreEpoch = $FreezeState.StoreEpoch
            TransactionId = $ExpectedTransactionId; StateKeySha256 = $FreezeState.StateKeySha256
            OldRevision = 0; NewRevision = 1; OldStateBindingToken = $availableState.StateBindingToken
            NewStateBindingToken = $FreezeState.StateBindingToken; ProposalNonce = $ExpectedProposalNonce
            SessionAnchorToken = $ExpectedSessionAnchorToken; SessionBindingToken = $ExpectedSessionBindingToken
            EvidenceBindingToken = $ExpectedEvidenceBindingToken; ConsumptionId = $ExpectedConsumptionId
            FreezeId = $ExpectedFreezeId; FactsBindingToken = $ExpectedFactsBindingToken
            ProposedState = $FreezeState; ProposalBindingToken = $null
        }
        $proposal.ProposalBindingToken = Get-CddsiReleaseFactsFreezeProposalBindingToken -CommitProposal $proposal
        if (-not (Test-CddsiReleaseFactsFreezeCommitProposal -CommitProposal $proposal) -or
            $CommitReceipt.Purpose -cne $proposal.Purpose -or $CommitReceipt.Domain -cne $proposal.Domain -or
            $CommitReceipt.StoreInstanceId -cne $proposal.StoreInstanceId -or [long]$CommitReceipt.StoreEpoch -ne [long]$proposal.StoreEpoch -or
            $CommitReceipt.TransactionId -cne $ExpectedTransactionId -or $CommitReceipt.StateKeySha256 -cne $proposal.StateKeySha256 -or
            [long]$CommitReceipt.OldRevision -ne 0 -or [long]$CommitReceipt.NewRevision -ne 1 -or
            $CommitReceipt.OldStateBindingToken -cne $proposal.OldStateBindingToken -or
            $CommitReceipt.NewStateBindingToken -cne $proposal.NewStateBindingToken -or
            $CommitReceipt.ProposalBindingToken -cne $proposal.ProposalBindingToken -or
            $CommitReceipt.ProposalNonce -cne $ExpectedProposalNonce -or
            $CommitReceipt.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
            $CommitReceipt.SessionBindingToken -cne $ExpectedSessionBindingToken -or
            $CommitReceipt.EvidenceBindingToken -cne $ExpectedEvidenceBindingToken -or
            $CommitReceipt.ConsumptionId -cne $ExpectedConsumptionId -or $CommitReceipt.FreezeId -cne $ExpectedFreezeId -or
            $CommitReceipt.FactsBindingToken -cne $ExpectedFactsBindingToken -or
            $CommitReceipt.ExpiresAtUtc -cne $FreezeState.ExpiresAtUtc -or
            [DateTimeOffset]::Parse($CommitReceipt.CommittedAtUtc) -lt [DateTimeOffset]::Parse($FreezeState.FrozenAtUtc)) { return $false }
        $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
        return ($validationTime -ge [DateTimeOffset]::Parse($CommitReceipt.CommittedAtUtc) -and
            $validationTime -lt [DateTimeOffset]::Parse($FreezeState.ExpiresAtUtc))
    }
    catch { return $false }
}

function New-CddsiReleaseFactsFreezeState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)]$CommittedConsumptionState,
        [Parameter(Mandatory = $true)]$CommittedConsumptionReceipt,
        [Parameter(Mandatory = $true)]$ConsumptionStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionTransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionProposalNonce,
        [Parameter(Mandatory = $true)]$FreezeStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$FreezeStoreInstanceId,
        [Parameter(Mandatory = $true)][long]$FreezeStoreEpoch,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    if (-not (Test-CddsiVmCalibrationEvidence -Evidence $Evidence -ExpectedSession $ExpectedSession `
        -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc `
        -MaximumAgeSeconds $MaximumAgeSeconds)) {
        throw 'A valid, fresh and externally anchored P10A evidence document is required.'
    }
    if (-not (Test-CddsiCommittedVmCalibrationConsumptionReceipt -ConsumptionState $CommittedConsumptionState `
        -CommitReceipt $CommittedConsumptionReceipt -StoreAuthorityPublicKey $ConsumptionStoreAuthorityPublicKey `
        -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ExpectedSessionBindingToken $ExpectedSession.SessionBindingToken `
        -ExpectedEvidenceBindingToken $Evidence.EvidenceBindingToken -ExpectedConsumptionId $ExpectedConsumptionId `
        -ExpectedTransactionId $ExpectedConsumptionTransactionId -ExpectedProposalNonce $ExpectedConsumptionProposalNonce `
        -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'A committed P10A consumption receipt bound to the same evidence and session is required.'
    }
    if (-not (Test-CddsiCasStoreAuthorityPublicKey -StoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey) -or
        -not (Test-CddsiCanonicalUuidValue -Value $FreezeStoreInstanceId) -or $FreezeStoreEpoch -lt 1) {
        throw 'A valid and explicitly pinned release-facts CAS store authority is required.'
    }
    $selectedCandidates = @($Evidence.MsixCandidates | Where-Object {
        $_.Flavor -ceq $Evidence.Selection.Flavor -and $_.ArtifactSha256 -ceq $Evidence.Selection.SelectedArtifactSha256
    })
    $selectedDeployment = if ($Evidence.Selection.Scope -ceq 'PER_USER') {
        if ($selectedCandidates.Count -eq 1) { $selectedCandidates[0].Deployments.PerUser } else { $null }
    }
    elseif ($Evidence.Selection.Scope -ceq 'MACHINE_WIDE') {
        if ($selectedCandidates.Count -eq 1) { $selectedCandidates[0].Deployments.MachineWide } else { $null }
    }
    else { $null }
    if ($Evidence.Readiness.Status -cne 'COMPLETE' -or $Evidence.Selection.Status -cne 'SELECTED' -or
        @($Evidence.MsixCandidates | Where-Object { $_.Status -ceq 'OBSERVED' }).Count -ne 2 -or
        $selectedCandidates.Count -ne 1 -or $null -eq $selectedDeployment -or $selectedDeployment.Result -cne 'PASS' -or
        $Evidence.Git.Status -cne 'OBSERVED' -or $Evidence.Git.Signer.AuthenticodeStatus -cne 'VALID' -or
        -not [bool]$Evidence.Git.Signer.ChainTrusted -or $Evidence.DesktopBehavior.Status -cne 'OBSERVED' -or
        $Evidence.DesktopBehavior.Helper.Result -cne 'PASS' -or $Evidence.DesktopBehavior.Chooser.Result -cne 'PASS' -or
        $Evidence.DesktopBehavior.HkcuManagedPolicy.Result -cne 'PASS' -or $Evidence.Cleanup.Status -cne 'COMPLETE') {
        throw 'P10B release facts require complete, observed and successful P10A calibration facts.'
    }

    $state = [pscustomobject][ordered]@{
        SchemaVersion                  = 1
        ContractVersion                = 'cddsi-release-facts-freeze-state-v2'
        Purpose                        = 'P10B_RELEASE_FACTS_FREEZE_STATE'
        StateKeySha256                 = $null
        State                          = 'AVAILABLE'
        StoreAuthorityKeyId            = $FreezeStoreAuthorityPublicKey.KeyId
        StoreAuthorityKeyFingerprintSha256 = $FreezeStoreAuthorityPublicKey.FingerprintSha256
        StoreInstanceId                = $FreezeStoreInstanceId
        StoreEpoch                     = $FreezeStoreEpoch
        SessionAnchorToken             = $ExpectedSessionAnchorToken
        SessionBindingToken            = $ExpectedSession.SessionBindingToken
        EvidenceBindingToken           = $Evidence.EvidenceBindingToken
        ConsumptionStateKeySha256      = $CommittedConsumptionState.StateKeySha256
        ConsumptionStateBindingToken   = $CommittedConsumptionState.StateBindingToken
        ConsumptionCommitReceiptBindingToken = $CommittedConsumptionReceipt.ReceiptBindingToken
        ConsumptionId                  = $ExpectedConsumptionId
        FreezeId                       = $null
        FactsBindingToken              = $null
        FrozenAtUtc                    = $null
        ExpiresAtUtc                   = $CommittedConsumptionReceipt.ExpiresAtUtc
        Revision                       = 0
        StateBindingToken              = $null
    }
    $state.StateKeySha256 = Get-CddsiReleaseFactsFreezeStateKey -FreezeState $state
    $state.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $state
    if (-not (Test-CddsiReleaseFactsFreezeState -FreezeState $state)) {
        throw 'Release-facts freeze state construction failed closed.'
    }
    return $state
}

function Get-CddsiFrozenReleaseFactsBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Facts)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion     = $Facts.SchemaVersion
        ContractVersion   = $Facts.ContractVersion
        Purpose           = $Facts.Purpose
        SourceBindings    = $Facts.SourceBindings
        OsImage           = $Facts.OsImage
        Msix              = $Facts.Msix
        Git               = $Facts.Git
        CredentialHelper  = $Facts.CredentialHelper
        Chooser           = $Facts.Chooser
        HkcuManagedPolicy = $Facts.HkcuManagedPolicy
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Resolve-CddsiFrozenReleaseFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)]$CommittedConsumptionState,
        [Parameter(Mandatory = $true)]$CommittedConsumptionReceipt,
        [Parameter(Mandatory = $true)]$ConsumptionStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionTransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionProposalNonce,
        [Parameter(Mandatory = $true)]$FreezeState,
        [Parameter(Mandatory = $true)]$FreezeStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$FreezeId,
        [Parameter(Mandatory = $true)][string]$FreezeTransactionId,
        [Parameter(Mandatory = $true)][string]$FreezeProposalNonce,
        [Parameter(Mandatory = $true)][AllowNull()]$CommittedFreezeReceipt,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $evidenceValid = Test-CddsiVmCalibrationEvidence -Evidence $Evidence -ExpectedSession $ExpectedSession `
        -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc `
        -MaximumAgeSeconds $MaximumAgeSeconds
    if (-not $evidenceValid) { $reasonCodes.Add('EVIDENCE_SESSION_INVALID') }
    $consumptionValid = $false
    if ($evidenceValid) {
        $consumptionValid = Test-CddsiCommittedVmCalibrationConsumptionReceipt -ConsumptionState $CommittedConsumptionState `
            -CommitReceipt $CommittedConsumptionReceipt -StoreAuthorityPublicKey $ConsumptionStoreAuthorityPublicKey `
            -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ExpectedSessionBindingToken $ExpectedSession.SessionBindingToken `
            -ExpectedEvidenceBindingToken $Evidence.EvidenceBindingToken -ExpectedConsumptionId $ExpectedConsumptionId `
            -ExpectedTransactionId $ExpectedConsumptionTransactionId -ExpectedProposalNonce $ExpectedConsumptionProposalNonce `
            -ValidationTimeUtc $ValidationTimeUtc
    }
    if (-not $consumptionValid) { $reasonCodes.Add('CONSUMPTION_RECEIPT_INVALID') }
    $stateValid = Test-CddsiReleaseFactsFreezeState -FreezeState $FreezeState
    if (-not $stateValid) { $reasonCodes.Add('FREEZE_STATE_INVALID') }
    elseif ($FreezeState.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
        $FreezeState.SessionBindingToken -cne $ExpectedSession.SessionBindingToken -or
        $FreezeState.EvidenceBindingToken -cne $Evidence.EvidenceBindingToken -or
        $FreezeState.ConsumptionStateKeySha256 -cne $CommittedConsumptionState.StateKeySha256 -or
        $FreezeState.ConsumptionStateBindingToken -cne $CommittedConsumptionState.StateBindingToken -or
        $FreezeState.ConsumptionCommitReceiptBindingToken -cne $CommittedConsumptionReceipt.ReceiptBindingToken -or
        $FreezeState.ConsumptionId -cne $ExpectedConsumptionId) {
        $reasonCodes.Add('FREEZE_SOURCE_BINDING_MISMATCH')
    }
    elseif (-not (Test-CddsiCasStoreAuthorityPublicKey -StoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey) -or
        $FreezeState.StoreAuthorityKeyId -cne $FreezeStoreAuthorityPublicKey.KeyId -or
        $FreezeState.StoreAuthorityKeyFingerprintSha256 -cne $FreezeStoreAuthorityPublicKey.FingerprintSha256) {
        $reasonCodes.Add('FREEZE_STORE_AUTHORITY_MISMATCH')
    }
    if (-not (Test-CddsiCanonicalUuidValue -Value $FreezeId)) { $reasonCodes.Add('FREEZE_ID_INVALID') }
    elseif (@(
        $ExpectedConsumptionId,
        $ExpectedSession.OperationGrant.RunId,
        $ExpectedSession.OperationGrant.GrantId,
        $ExpectedSession.OperationGrant.Nonce,
        $ExpectedSession.AuthorizationSession.ClaimId,
        @($ExpectedSession.OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId }),
        @($ExpectedSession.OperationUseStates | ForEach-Object { $_.OperationUseId; $_.IdempotencyKey })
    ) -ccontains $FreezeId) { $reasonCodes.Add('FREEZE_ID_COLLISION') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $FreezeTransactionId) -or
        @($ExpectedConsumptionId, $FreezeId) -ccontains $FreezeTransactionId) { $reasonCodes.Add('FREEZE_TRANSACTION_ID_INVALID') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $FreezeProposalNonce) -or
        @($ExpectedConsumptionId, $FreezeId, $FreezeTransactionId) -ccontains $FreezeProposalNonce) { $reasonCodes.Add('FREEZE_PROPOSAL_NONCE_INVALID') }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }

    $selectedCandidates = @()
    $selectedCandidate = $null
    $selectedDeployment = $null
    if ($evidenceValid) {
        $selectedCandidates = @($Evidence.MsixCandidates | Where-Object {
            $_.Flavor -ceq $Evidence.Selection.Flavor -and $_.ArtifactSha256 -ceq $Evidence.Selection.SelectedArtifactSha256
        })
        if ($selectedCandidates.Count -eq 1) {
            $selectedCandidate = $selectedCandidates[0]
            if ($Evidence.Selection.Scope -ceq 'PER_USER') { $selectedDeployment = $selectedCandidate.Deployments.PerUser }
            elseif ($Evidence.Selection.Scope -ceq 'MACHINE_WIDE') { $selectedDeployment = $selectedCandidate.Deployments.MachineWide }
        }
        if ($Evidence.Readiness.Status -cne 'COMPLETE' -or $Evidence.Selection.Status -cne 'SELECTED' -or
            @($Evidence.MsixCandidates | Where-Object { $_.Status -ceq 'OBSERVED' }).Count -ne 2 -or
            $selectedCandidates.Count -ne 1 -or $null -eq $selectedDeployment -or $selectedDeployment.Result -cne 'PASS' -or
            $Evidence.Git.Status -cne 'OBSERVED' -or $Evidence.Git.Signer.AuthenticodeStatus -cne 'VALID' -or
            -not [bool]$Evidence.Git.Signer.ChainTrusted -or $Evidence.DesktopBehavior.Status -cne 'OBSERVED' -or
            $Evidence.DesktopBehavior.Helper.Result -cne 'PASS' -or $Evidence.DesktopBehavior.Chooser.Result -cne 'PASS' -or
            $Evidence.DesktopBehavior.HkcuManagedPolicy.Result -cne 'PASS' -or $Evidence.Cleanup.Status -cne 'COMPLETE') {
            $reasonCodes.Add('CALIBRATION_FACTS_NOT_FREEZABLE')
        }
    }

    $facts = $null
    if ($reasonCodes.Count -eq 0) {
        $facts = [pscustomobject][ordered]@{
            SchemaVersion   = 1
            ContractVersion = 'cddsi-frozen-release-facts-v1'
            Purpose         = 'P10B_RELEASE_BUILD_INPUT_ONLY'
            SourceBindings  = [pscustomobject][ordered]@{
                SchemaVersion                  = 1
                SessionAnchorToken             = $ExpectedSessionAnchorToken
                SessionBindingToken            = $ExpectedSession.SessionBindingToken
                EvidenceBindingToken           = $Evidence.EvidenceBindingToken
                ConsumptionStateKeySha256      = $CommittedConsumptionState.StateKeySha256
                ConsumptionStateBindingToken   = $CommittedConsumptionState.StateBindingToken
                ConsumptionCommitReceiptBindingToken = $CommittedConsumptionReceipt.ReceiptBindingToken
                ConsumptionId                  = $ExpectedConsumptionId
                ConsumptionRevision            = $CommittedConsumptionState.Revision
                EvidenceCompletedAtUtc          = $Evidence.CompletedAtUtc
            }
            OsImage = [pscustomobject][ordered]@{
                Status               = $Evidence.OsImage.Status
                ObservedAtUtc        = $Evidence.OsImage.ObservedAtUtc
                ImageSha256          = $Evidence.OsImage.ImageSha256
                Sku                  = $Evidence.OsImage.Sku
                Architecture         = $Evidence.OsImage.Architecture
                Build                = $Evidence.OsImage.Build
                Ubr                  = $Evidence.OsImage.Ubr
                Language             = $Evidence.OsImage.Language
                PatchDate            = $Evidence.OsImage.PatchDate
                NestedVirtualization = $Evidence.OsImage.NestedVirtualization
            }
            Msix = [pscustomobject][ordered]@{
                Status                   = $selectedCandidate.Status
                ObservedAtUtc            = $selectedCandidate.ObservedAtUtc
                Flavor                  = $Evidence.Selection.Flavor
                Scope                   = $Evidence.Selection.Scope
                SourceUri               = $selectedCandidate.SourceUri
                RedirectUri             = $selectedCandidate.RedirectUri
                RedirectCount           = $selectedCandidate.RedirectCount
                Version                 = $selectedCandidate.Version
                SizeBytes               = $selectedCandidate.SizeBytes
                ArtifactSha256          = $selectedCandidate.ArtifactSha256
                Signer                  = $selectedCandidate.Signer
                Certificate             = $selectedCandidate.Certificate
                ManifestIdentity        = $selectedCandidate.ManifestIdentity
                Deployment              = $selectedDeployment
                RecommendationCode      = $selectedCandidate.Deployments.RecommendationCode
                SelectionReasonCode     = $Evidence.Selection.ReasonCode
                CandidateSetDigestSha256 = $Evidence.Selection.CandidateSetDigestSha256
            }
            Git = [pscustomobject][ordered]@{
                Status         = $Evidence.Git.Status
                ObservedAtUtc  = $Evidence.Git.ObservedAtUtc
                ReleaseTag     = $Evidence.Git.ReleaseTag
                AssetName      = $Evidence.Git.AssetName
                SourceUri      = $Evidence.Git.SourceUri
                Version        = $Evidence.Git.Version
                SizeBytes      = $Evidence.Git.SizeBytes
                ArtifactSha256 = $Evidence.Git.ArtifactSha256
                Signer         = $Evidence.Git.Signer
                PeIdentity     = $Evidence.Git.PeIdentity
            }
            CredentialHelper = [pscustomobject][ordered]@{
                Result                = $Evidence.DesktopBehavior.Helper.Result
                Invoked               = $Evidence.DesktopBehavior.Helper.Invoked
                StdoutSingleToken     = $Evidence.DesktopBehavior.Helper.StdoutSingleToken
                StderrSafe            = $Evidence.DesktopBehavior.Helper.StderrSafe
                TimeoutEnforced       = $Evidence.DesktopBehavior.Helper.TimeoutEnforced
                TtlObservedSeconds    = $Evidence.DesktopBehavior.Helper.TtlObservedSeconds
                SilentRefreshObserved = $Evidence.DesktopBehavior.Helper.SilentRefreshObserved
            }
            Chooser = [pscustomobject][ordered]@{
                Result                 = $Evidence.DesktopBehavior.Chooser.Result
                Hidden                 = $Evidence.DesktopBehavior.Chooser.Hidden
                DeveloperModeSkipped   = $Evidence.DesktopBehavior.Chooser.DeveloperModeSkipped
                AnthropicLoginSkipped  = $Evidence.DesktopBehavior.Chooser.AnthropicLoginSkipped
            }
            HkcuManagedPolicy = [pscustomobject][ordered]@{
                Result                  = $Evidence.DesktopBehavior.HkcuManagedPolicy.Result
                Effective               = $Evidence.DesktopBehavior.HkcuManagedPolicy.Effective
                ValueType               = $Evidence.DesktopBehavior.HkcuManagedPolicy.ValueType
                ValueCount              = $Evidence.DesktopBehavior.HkcuManagedPolicy.ValueCount
                HelperReferenceUsed     = $Evidence.DesktopBehavior.HkcuManagedPolicy.HelperReferenceUsed
                ConfigLibraryWriterUsed = $Evidence.DesktopBehavior.HkcuManagedPolicy.ConfigLibraryWriterUsed
                RawValuesCaptured       = $Evidence.DesktopBehavior.HkcuManagedPolicy.RawValuesCaptured
            }
            FactsBindingToken = $null
        }
        $facts.FactsBindingToken = Get-CddsiFrozenReleaseFactsBindingToken -Facts $facts
        $factsJson = ConvertTo-CddsiJson -InputObject $facts
        if ($factsJson -match '(?i)NOT_OBSERVED|"(?:Status|Result)"\s*:\s*"(?:FAILED|FAIL)"' -or
            @(Find-CddsiPotentialSecrets -Content $factsJson -Source '<frozen-release-facts>').Count -gt 0) {
            $reasonCodes.Add('FROZEN_FACTS_UNSAFE')
            $facts = $null
        }
    }

    $proposedState = $null
    $commitProposal = $null
    $idempotentReplay = $false
    $requiresCas = $false
    $canUse = $false
    if ($reasonCodes.Count -eq 0 -and $stateValid -and $null -ne $facts) {
        if ($FreezeState.State -ceq 'FROZEN') {
            if ($FreezeState.FreezeId -ceq $FreezeId -and $FreezeState.FactsBindingToken -ceq $facts.FactsBindingToken -and
                [long]$FreezeState.Revision -eq [long]$ExpectedRevision -and $null -ne $CommittedFreezeReceipt -and
                (Test-CddsiCommittedReleaseFactsFreezeReceipt -FreezeState $FreezeState `
                    -CommitReceipt $CommittedFreezeReceipt -StoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey `
                    -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ExpectedSessionBindingToken $ExpectedSession.SessionBindingToken `
                    -ExpectedEvidenceBindingToken $Evidence.EvidenceBindingToken `
                    -ExpectedConsumptionStateKeySha256 $CommittedConsumptionState.StateKeySha256 `
                    -ExpectedConsumptionStateBindingToken $CommittedConsumptionState.StateBindingToken `
                    -ExpectedConsumptionCommitReceiptBindingToken $CommittedConsumptionReceipt.ReceiptBindingToken `
                    -ExpectedConsumptionId $ExpectedConsumptionId -ExpectedFreezeId $FreezeId `
                    -ExpectedFactsBindingToken $facts.FactsBindingToken -ExpectedTransactionId $FreezeTransactionId `
                    -ExpectedProposalNonce $FreezeProposalNonce -ValidationTimeUtc $ValidationTimeUtc)) {
                $proposedState = $FreezeState
                $idempotentReplay = $true
                $canUse = $true
            }
            elseif ($null -eq $CommittedFreezeReceipt) { $reasonCodes.Add('FREEZE_SIGNED_RECEIPT_REQUIRED') }
            elseif ([long]$FreezeState.Revision -ne [long]$ExpectedRevision) { $reasonCodes.Add('FREEZE_CONCURRENCY_CONFLICT') }
            elseif ($FreezeState.FreezeId -ceq $FreezeId) { $reasonCodes.Add('FREEZE_COMMIT_RECEIPT_INVALID') }
            else { $reasonCodes.Add('CALIBRATION_EVIDENCE_FREEZE_REPLAY') }
        }
        elseif ($ExpectedRevision -ne [long]$FreezeState.Revision) {
            $reasonCodes.Add('FREEZE_CONCURRENCY_CONFLICT')
        }
        elseif ([DateTimeOffset]::Parse($ValidationTimeUtc) -ge [DateTimeOffset]::Parse($FreezeState.ExpiresAtUtc)) {
            $reasonCodes.Add('FREEZE_STATE_EXPIRED')
        }
        else {
            if ($null -ne $CommittedFreezeReceipt) { $reasonCodes.Add('FREEZE_CURRENT_STATE_NOT_COMMITTED') }
            $proposedState = [pscustomobject][ordered]@{
                SchemaVersion = $FreezeState.SchemaVersion; ContractVersion = $FreezeState.ContractVersion
                Purpose = $FreezeState.Purpose; StateKeySha256 = $FreezeState.StateKeySha256; State = 'FROZEN'
                StoreAuthorityKeyId = $FreezeState.StoreAuthorityKeyId
                StoreAuthorityKeyFingerprintSha256 = $FreezeState.StoreAuthorityKeyFingerprintSha256
                StoreInstanceId = $FreezeState.StoreInstanceId; StoreEpoch = $FreezeState.StoreEpoch
                SessionAnchorToken = $FreezeState.SessionAnchorToken; SessionBindingToken = $FreezeState.SessionBindingToken
                EvidenceBindingToken = $FreezeState.EvidenceBindingToken
                ConsumptionStateKeySha256 = $FreezeState.ConsumptionStateKeySha256
                ConsumptionStateBindingToken = $FreezeState.ConsumptionStateBindingToken
                ConsumptionCommitReceiptBindingToken = $FreezeState.ConsumptionCommitReceiptBindingToken
                ConsumptionId = $FreezeState.ConsumptionId; FreezeId = $FreezeId
                FactsBindingToken = $facts.FactsBindingToken; FrozenAtUtc = $ValidationTimeUtc
                ExpiresAtUtc = $FreezeState.ExpiresAtUtc; Revision = [long]$FreezeState.Revision + 1
                StateBindingToken = $null
            }
            $proposedState.StateBindingToken = Get-CddsiReleaseFactsFreezeStateBindingToken -FreezeState $proposedState
            if (-not (Test-CddsiReleaseFactsFreezeState -FreezeState $proposedState)) {
                $reasonCodes.Add('FREEZE_PROPOSAL_INVALID')
                $proposedState = $null
            }
            elseif ($reasonCodes.Count -eq 0) {
                $commitProposal = [pscustomobject][ordered]@{
                    SchemaVersion = 1; ContractVersion = 'cddsi-release-facts-freeze-commit-proposal-v1'
                    Purpose = 'P10B_RELEASE_FACTS_FREEZE_COMMIT'; Domain = 'P10B_RELEASE_FACTS_FREEZE'
                    StoreAuthorityKeyId = $FreezeState.StoreAuthorityKeyId
                    StoreAuthorityKeyFingerprintSha256 = $FreezeState.StoreAuthorityKeyFingerprintSha256
                    StoreInstanceId = $FreezeState.StoreInstanceId; StoreEpoch = $FreezeState.StoreEpoch
                    TransactionId = $FreezeTransactionId; StateKeySha256 = $FreezeState.StateKeySha256
                    OldRevision = $FreezeState.Revision; NewRevision = $proposedState.Revision
                    OldStateBindingToken = $FreezeState.StateBindingToken
                    NewStateBindingToken = $proposedState.StateBindingToken; ProposalNonce = $FreezeProposalNonce
                    SessionAnchorToken = $ExpectedSessionAnchorToken; SessionBindingToken = $ExpectedSession.SessionBindingToken
                    EvidenceBindingToken = $Evidence.EvidenceBindingToken; ConsumptionId = $ExpectedConsumptionId
                    FreezeId = $FreezeId; FactsBindingToken = $facts.FactsBindingToken
                    ProposedState = $proposedState; ProposalBindingToken = $null
                }
                $commitProposal.ProposalBindingToken = Get-CddsiReleaseFactsFreezeProposalBindingToken -CommitProposal $commitProposal
                if (-not (Test-CddsiReleaseFactsFreezeCommitProposal -CommitProposal $commitProposal)) {
                    $reasonCodes.Add('FREEZE_COMMIT_PROPOSAL_INVALID')
                    $commitProposal = $null; $proposedState = $null
                }
                else { $requiresCas = $true }
            }
        }
    }

    $readyToCommit = ($null -ne $proposedState -and $requiresCas -and $reasonCodes.Count -eq 0)
    $frozen = ($canUse -and $idempotentReplay -and $reasonCodes.Count -eq 0)
    return [pscustomobject][ordered]@{
        SchemaVersion               = 1
        ContractVersion             = 'cddsi-release-facts-freeze-resolution-v1'
        Status                      = if ($frozen) { 'FROZEN' } elseif ($readyToCommit) { 'READY_TO_COMMIT' } else { 'BLOCKED' }
        CanUseFrozenFacts           = $frozen
        RequiresAtomicCompareAndSwap = $readyToCommit
        IdempotentReplay            = $idempotentReplay
        StateKeySha256              = if ($stateValid) { $FreezeState.StateKeySha256 } else { $null }
        PreviousRevision            = if ($stateValid) { $FreezeState.Revision } else { $null }
        NextRevision                = if ($null -ne $proposedState) { $proposedState.Revision } else { $null }
        ProposedFreezeState         = $proposedState
        CommitProposal              = $commitProposal
        CommittedReceiptVerified    = $frozen
        IntegrityTokensAreAuthorization = $false
        FactsBindingToken           = if ($null -ne $facts) { $facts.FactsBindingToken } else { $null }
        FrozenReleaseFacts          = if ($frozen) { $facts } else { $null }
        ReasonCodes                 = if ($frozen) { @('P10B_RELEASE_FACTS_FROZEN') } elseif ($readyToCommit) { @('FREEZE_COMMIT_REQUIRED') } else { @($reasonCodes | Select-Object -Unique) }
    }
}

function Test-CddsiFrozenReleaseFacts {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Facts,
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)]$CommittedConsumptionState,
        [Parameter(Mandatory = $true)]$CommittedConsumptionReceipt,
        [Parameter(Mandatory = $true)]$ConsumptionStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionTransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionProposalNonce,
        [Parameter(Mandatory = $true)]$CommittedFreezeState,
        [Parameter(Mandatory = $true)]$CommittedFreezeReceipt,
        [Parameter(Mandatory = $true)]$FreezeStoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ExpectedFreezeId,
        [Parameter(Mandatory = $true)][string]$ExpectedFreezeTransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedFreezeProposalNonce,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $Facts -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'SourceBindings',
            'OsImage', 'Msix', 'Git', 'CredentialHelper', 'Chooser',
            'HkcuManagedPolicy', 'FactsBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $Facts.SchemaVersion) -or
            $Facts.ContractVersion -cne 'cddsi-frozen-release-facts-v1' -or
            $Facts.Purpose -cne 'P10B_RELEASE_BUILD_INPUT_ONLY' -or
            $Facts.FactsBindingToken -isnot [string] -or $Facts.FactsBindingToken -notmatch '^[a-f0-9]{64}$' -or
            $Facts.FactsBindingToken -cne (Get-CddsiFrozenReleaseFactsBindingToken -Facts $Facts)) { return $false }
        $resolution = Resolve-CddsiFrozenReleaseFacts -Evidence $Evidence -ExpectedSession $ExpectedSession `
            -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -CommittedConsumptionState $CommittedConsumptionState `
            -CommittedConsumptionReceipt $CommittedConsumptionReceipt -ConsumptionStoreAuthorityPublicKey $ConsumptionStoreAuthorityPublicKey `
            -ExpectedConsumptionId $ExpectedConsumptionId -ExpectedConsumptionTransactionId $ExpectedConsumptionTransactionId `
            -ExpectedConsumptionProposalNonce $ExpectedConsumptionProposalNonce -FreezeState $CommittedFreezeState `
            -FreezeStoreAuthorityPublicKey $FreezeStoreAuthorityPublicKey -FreezeId $ExpectedFreezeId `
            -FreezeTransactionId $ExpectedFreezeTransactionId -FreezeProposalNonce $ExpectedFreezeProposalNonce `
            -CommittedFreezeReceipt $CommittedFreezeReceipt -ExpectedRevision $CommittedFreezeState.Revision `
            -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds
        if ($resolution.Status -cne 'FROZEN' -or -not $resolution.CanUseFrozenFacts -or $null -eq $resolution.FrozenReleaseFacts) { return $false }
        if ((Get-CddsiVmCalibrationCanonicalBindingToken -Value $Facts) -cne
            (Get-CddsiVmCalibrationCanonicalBindingToken -Value $resolution.FrozenReleaseFacts)) { return $false }
        $serialized = ConvertTo-CddsiJson -InputObject $Facts
        return ($serialized -notmatch '(?i)NOT_OBSERVED|"(?:Status|Result)"\s*:\s*"(?:FAILED|FAIL)"' -and
            @(Find-CddsiPotentialSecrets -Content $serialized -Source '<frozen-release-facts>').Count -eq 0)
    }
    catch { return $false }
}
