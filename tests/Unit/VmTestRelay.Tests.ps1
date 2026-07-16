BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\common.ps1')
    . (Join-Path $script:RepoRoot 'lib\vm-test-relay.ps1')
    $script:FastLanePolicy = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\fast-lane-policy.psd1')

    $script:HostToVmRepositoryIdentity = 'synthetic/cddsi-host-to-vm'
    $script:VmToHostRepositoryIdentity = 'synthetic/cddsi-vm-to-host'
    $script:ProductRepositoryIdentity = 'synthetic/cddsi-product'
    $script:ValidationTimeUtc = '2030-01-01T00:01:00Z'
    $script:DefaultRunId = '30000000-0000-4000-8000-000000000001'

    function New-CddsiRelayStateFixture {
        return New-CddsiVmTestRelayState `
            -HostToVmRepositoryIdentity $script:HostToVmRepositoryIdentity `
            -VmToHostRepositoryIdentity $script:VmToHostRepositoryIdentity `
            -ProductRepositoryIdentity $script:ProductRepositoryIdentity
    }

    function New-CddsiRelayRequestPayloadFixture {
        param(
            [ValidateSet('Initial', 'Retest')][string]$RequestKind = 'Initial',
            [AllowNull()]$PriorCycleId = $null
        )
        return [pscustomobject][ordered]@{
            SchemaVersion   = '1'
            ContractVersion = 'cddsi-vm-test-relay-test-request-v1'
            RequestKind     = $RequestKind
            PriorCycleId    = $PriorCycleId
        }
    }

    function New-CddsiRelayControlPayloadFixture {
        param([string]$Code = 'SYNTHETIC_OK')
        return [pscustomobject][ordered]@{
            SchemaVersion   = '1'
            ContractVersion = 'cddsi-vm-test-relay-control-v1'
            Code            = $Code
        }
    }

    function New-CddsiRelaySnapshotReadyPayloadFixture {
        param([string]$ExternalReceiptAuthorityBindingToken = ('6' * 64))
        return [pscustomobject][ordered]@{
            SchemaVersion                        = '1'
            ContractVersion                      = 'cddsi-vm-test-relay-snapshot-ready-v1'
            Code                                 = 'EXTERNAL_SNAPSHOT_VERIFIED'
            ExternalReceiptAuthority             = 'HypervisorSupervisor'
            ExternalReceiptAuthorityBindingToken = $ExternalReceiptAuthorityBindingToken
        }
    }

    function New-CddsiRelayResultPayloadFixture {
        param(
            [Parameter(Mandatory = $true)][string]$CycleId,
            [ValidateSet('PASS', 'FAIL', 'BLOCKED')][string]$Outcome = 'PASS',
            [string]$RunId = $script:DefaultRunId,
            [string]$EvidenceClass = 'Diagnostic',
            [AllowNull()]$AcceptanceReceiptUri = $null,
            [AllowNull()]$AcceptanceReceiptSha256 = $null
        )
        return [pscustomobject][ordered]@{
            SchemaVersion              = '1'
            ContractVersion            = 'cddsi-vm-test-relay-test-result-v1'
            CycleId                    = $CycleId
            RunId                      = $RunId
            Phase                      = 'Synthetic'
            MatrixCell                 = 'win11-x64-synthetic'
            OverallStatus              = $Outcome
            EvidenceClass              = $EvidenceClass
            AcceptanceReceiptUri       = $AcceptanceReceiptUri
            AcceptanceReceiptSha256    = $AcceptanceReceiptSha256
            SecretFindingCount         = 0
            ForbiddenMutationCount     = 0
            UnexpectedLedgerEntryCount = 0
            SummaryCode                = ('SYNTHETIC_' + $Outcome)
        }
    }

    function New-CddsiRelayFixPayloadFixture {
        param([Parameter(Mandatory = $true)][string]$RepairSourceCycleId)
        return [pscustomobject][ordered]@{
            SchemaVersion      = '1'
            ContractVersion    = 'cddsi-vm-test-relay-fix-ready-v1'
            RepairSourceCycleId = $RepairSourceCycleId
            ChangeClass        = 'CalibrationPackage'
            CandidateRebuilt   = $true
        }
    }

    function New-CddsiRelayStopPayloadFixture {
        return [pscustomobject][ordered]@{
            SchemaVersion   = '1'
            ContractVersion = 'cddsi-vm-test-relay-stop-v1'
            ReasonCode      = 'HUMAN_STOP'
        }
    }

    function New-CddsiRelayEnvelopeFixture {
        param(
            [Parameter(Mandatory = $true)]$State,
            [Parameter(Mandatory = $true)]$Payload,
            [Parameter(Mandatory = $true)][string]$MessageType,
            [Parameter(Mandatory = $true)][string]$Status,
            [AllowNull()]$CycleId = $null,
            [AllowNull()]$MessageId = $null,
            [long]$Sequence = 0,
            [AllowNull()]$PreviousMessageSha256 = '__AUTO__',
            [AllowNull()]$ExpectedStateBindingToken = $null,
            [AllowNull()]$SenderRole = $null,
            [AllowNull()]$Outbox = $null,
            [AllowNull()]$PhysicalControlRepositoryIdentity = $null,
            [ValidateSet('Fast', 'Formal')][string]$Lane = 'Fast',
            [string]$CreatedAtUtc = '2030-01-01T00:00:00Z',
            [string]$ExpiresAtUtc = '2030-01-01T00:10:00Z',
            [AllowNull()][hashtable]$BindingOverrides = $null,
            [AllowNull()]$CleanReceiptSha256 = '__AUTO__',
            [AllowNull()]$SnapshotReceiptSha256 = '__AUTO__',
            [AllowNull()]$EvidenceUri = '__AUTO__',
            [AllowNull()]$EvidenceSha256 = '__AUTO__',
            [AllowNull()]$SigningKeyId = $null,
            [AllowNull()]$SignatureAlgorithm = $null,
            [AllowNull()]$Signature = $null
        )

        if ($null -eq $CycleId) {
            $CycleId = if ($null -ne $State.ActiveCycleId) { $State.ActiveCycleId } else { [guid]::NewGuid().ToString('D').ToLowerInvariant() }
        }
        if ($null -eq $MessageId) { $MessageId = [guid]::NewGuid().ToString('D').ToLowerInvariant() }
        if ($Sequence -eq 0) {
            $Sequence = if ($State.ActiveCycleId -ceq $CycleId) { [long]$State.ActiveSequence + 1 } else { 1 }
        }
        if ($PreviousMessageSha256 -ceq '__AUTO__') {
            $PreviousMessageSha256 = if ($Sequence -eq 1) { $null } else { $State.ActiveMessageSha256 }
        }

        $defaultRole = @{
            TEST_REQUEST = 'HostCoordinator'; VM_ACK = 'VmTester'; SNAPSHOT_READY = 'HostCoordinator'
            CLEAN_READY = 'VmTester'; TEST_STARTED = 'VmTester'; TEST_RESULT = 'VmTester'
            HOST_ACK = 'HostCoordinator'; FIX_READY = 'HostCoordinator'; STOP = 'HostCoordinator'
        }[$MessageType]
        if ($null -eq $SenderRole) { $SenderRole = if ($null -ne $defaultRole) { $defaultRole } else { 'HostCoordinator' } }
        if ($null -eq $Outbox) { $Outbox = if ($SenderRole -ceq 'VmTester') { 'vm-to-host' } else { 'host-to-vm' } }
        if ($null -eq $PhysicalControlRepositoryIdentity) {
            $PhysicalControlRepositoryIdentity = if ($Outbox -ceq 'host-to-vm') {
                $script:HostToVmRepositoryIdentity
            }
            else { $script:VmToHostRepositoryIdentity }
        }
        if ($null -eq $ExpectedStateBindingToken) { $ExpectedStateBindingToken = $State.StateBindingToken }

        $selectBinding = {
            param([string]$Name, $Default)
            if ($null -ne $BindingOverrides -and $BindingOverrides.ContainsKey($Name)) { return $BindingOverrides[$Name] }
            if ($null -ne $State.ActiveBinding) { return $State.ActiveBinding.$Name }
            return $Default
        }
        $environmentResetMode = & $selectBinding 'EnvironmentResetMode' 'GuestReset'
        if ($CleanReceiptSha256 -ceq '__AUTO__') {
            if (@('CLEAN_READY', 'TEST_STARTED', 'TEST_RESULT', 'HOST_ACK') -ccontains $MessageType) {
                $CleanReceiptSha256 = if ($null -ne $State.ActiveCleanReceiptSha256) { $State.ActiveCleanReceiptSha256 } else { 'e' * 64 }
            }
            else { $CleanReceiptSha256 = $null }
        }
        if ($SnapshotReceiptSha256 -ceq '__AUTO__') {
            if ($environmentResetMode -ceq 'SnapshotRestore' -and @('SNAPSHOT_READY', 'CLEAN_READY', 'TEST_STARTED', 'TEST_RESULT', 'HOST_ACK') -ccontains $MessageType) {
                $SnapshotReceiptSha256 = if ($null -ne $State.ActiveSnapshotReceiptSha256) { $State.ActiveSnapshotReceiptSha256 } else { 'f' * 64 }
            }
            else { $SnapshotReceiptSha256 = $null }
        }
        if ($EvidenceUri -ceq '__AUTO__') {
            $EvidenceUri = if ($MessageType -ceq 'TEST_RESULT') { 'diagnostic/synthetic-bundle' } elseif ($MessageType -ceq 'HOST_ACK') { $State.ActiveEvidenceUri } else { $null }
        }
        if ($EvidenceSha256 -ceq '__AUTO__') {
            $EvidenceSha256 = if ($MessageType -ceq 'TEST_RESULT') { '9' * 64 } elseif ($MessageType -ceq 'HOST_ACK') { $State.ActiveEvidenceSha256 } else { $null }
        }

        $canonicalPayload = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Payload
        return [pscustomobject][ordered]@{
            SchemaVersion                     = '1'
            ProtocolVersion                   = 'cddsi-vm-test-relay-v1'
            Lane                              = $Lane
            MessageId                         = $MessageId
            CycleId                           = $CycleId
            Sequence                          = [long]$Sequence
            MessageType                       = $MessageType
            SenderRole                        = $SenderRole
            HostToVmRepositoryIdentity        = $script:HostToVmRepositoryIdentity
            VmToHostRepositoryIdentity        = $script:VmToHostRepositoryIdentity
            PhysicalControlRepositoryIdentity = $PhysicalControlRepositoryIdentity
            ProductRepositoryIdentity         = $script:ProductRepositoryIdentity
            Outbox                            = $Outbox
            CreatedAtUtc                       = $CreatedAtUtc
            ExpiresAtUtc                       = $ExpiresAtUtc
            Nonce                              = [guid]::NewGuid().ToString('D').ToLowerInvariant()
            ExpectedStateBindingToken          = $ExpectedStateBindingToken
            PreviousMessageSha256              = $PreviousMessageSha256
            RepositoryCommitSha                = & $selectBinding 'RepositoryCommitSha' ('a' * 40)
            RepairRef                          = & $selectBinding 'RepairRef' 'refs/heads/codex/repair/p10a-0a'
            ArtifactProfile                    = & $selectBinding 'ArtifactProfile' 'VmCalibration'
            CandidateId                        = & $selectBinding 'CandidateId' $null
            ArtifactSha256                     = & $selectBinding 'ArtifactSha256' ('b' * 64)
            SidecarSha256                      = & $selectBinding 'SidecarSha256' ('c' * 64)
            RunbookSha256                      = & $selectBinding 'RunbookSha256' ('d' * 64)
            VmImageSha256                      = & $selectBinding 'VmImageSha256' ('1' * 64)
            OsMatrixCell                       = & $selectBinding 'OsMatrixCell' 'win11-x64-synthetic'
            RunId                              = & $selectBinding 'RunId' $script:DefaultRunId
            EnvironmentResetMode               = $environmentResetMode
            ResetPolicySha256                  = & $selectBinding 'ResetPolicySha256' ('2' * 64)
            ResetAllowListSha256               = & $selectBinding 'ResetAllowListSha256' ('3' * 64)
            OperationGrantSha256               = & $selectBinding 'OperationGrantSha256' ('4' * 64)
            SessionAnchorSha256                = & $selectBinding 'SessionAnchorSha256' ('5' * 64)
            CleanReceiptSha256                 = $CleanReceiptSha256
            SnapshotReceiptSha256              = $SnapshotReceiptSha256
            PayloadSha256                      = Get-CddsiVmTestRelayPayloadSha256 -Payload $Payload
            MessageBodyLength                  = [Text.Encoding]::UTF8.GetByteCount($canonicalPayload)
            EvidenceUri                        = $EvidenceUri
            EvidenceSha256                     = $EvidenceSha256
            Status                             = $Status
            SigningKeyId                       = $SigningKeyId
            SignatureAlgorithm                 = $SignatureAlgorithm
            Signature                          = $Signature
        }
    }

    function Invoke-CddsiRelayMessageFixture {
        param(
            [Parameter(Mandatory = $true)]$State,
            [Parameter(Mandatory = $true)]$Envelope,
            [Parameter(Mandatory = $true)]$Payload,
            [AllowNull()]$AuthenticatedSenderRole = $null,
            [AllowNull()]$AuthenticatedOutbox = $null,
            [AllowNull()]$ExternallyVerifiedSnapshotReceiptSha256 = $null,
            [AllowNull()]$ExternallyVerifiedSnapshotAuthorityBindingToken = $null
        )
        if ($null -eq $AuthenticatedSenderRole) { $AuthenticatedSenderRole = $Envelope.SenderRole }
        if ($null -eq $AuthenticatedOutbox) { $AuthenticatedOutbox = $Envelope.Outbox }
        return Resolve-CddsiVmTestRelayTransition -State $State -Envelope $Envelope -Payload $Payload `
            -ValidationTimeUtc $script:ValidationTimeUtc `
            -AuthenticatedSenderRole $AuthenticatedSenderRole -AuthenticatedOutbox $AuthenticatedOutbox `
            -ExternallyVerifiedSnapshotReceiptSha256 $ExternallyVerifiedSnapshotReceiptSha256 `
            -ExternallyVerifiedSnapshotAuthorityBindingToken $ExternallyVerifiedSnapshotAuthorityBindingToken
    }

    function Complete-CddsiRelayOutcomeFixture {
        param(
            [ValidateSet('PASS', 'FAIL', 'BLOCKED')][string]$Outcome,
            [Parameter(Mandatory = $true)][string]$CycleId
        )
        $state = New-CddsiRelayStateFixture
        $steps = @(
            @{ Type = 'TEST_REQUEST'; Status = 'TEST_REQUESTED'; Payload = New-CddsiRelayRequestPayloadFixture },
            @{ Type = 'VM_ACK'; Status = 'VM_ACKED'; Payload = New-CddsiRelayControlPayloadFixture 'REQUEST_ACKED' },
            @{ Type = 'CLEAN_READY'; Status = 'CLEAN_READY'; Payload = New-CddsiRelayControlPayloadFixture 'GUEST_RESET_CLEAN' },
            @{ Type = 'TEST_STARTED'; Status = 'TEST_RUNNING'; Payload = New-CddsiRelayControlPayloadFixture 'RUNBOOK_STARTED' },
            @{ Type = 'TEST_RESULT'; Status = ('TEST_' + $(if ($Outcome -ceq 'PASS') { 'PASSED' } elseif ($Outcome -ceq 'FAIL') { 'FAILED' } else { 'BLOCKED' })); Payload = New-CddsiRelayResultPayloadFixture -CycleId $CycleId -Outcome $Outcome },
            @{ Type = 'HOST_ACK'; Status = 'HOST_ACKED'; Payload = New-CddsiRelayControlPayloadFixture 'RESULT_ACKED' }
        )
        foreach ($step in $steps) {
            $envelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $step.Payload -MessageType $step.Type -Status $step.Status -CycleId $CycleId
            $transition = Invoke-CddsiRelayMessageFixture -State $state -Envelope $envelope -Payload $step.Payload
            if (-not $transition.Accepted) { throw ('Synthetic setup failed: {0} {1}' -f $step.Type, $transition.ErrorCode) }
            $state = $transition.State
        }
        return $state
    }
}

Describe 'Fast Lane VM test relay pure contracts' {
    It 'accepts the frozen GitHub repository identities and rejects domain lookalikes' {
        $state = New-CddsiVmTestRelayState `
            -HostToVmRepositoryIdentity $script:FastLanePolicy.ControlPlane.HostToVm.RepositoryToken `
            -VmToHostRepositoryIdentity $script:FastLanePolicy.ControlPlane.VmToHost.RepositoryToken `
            -ProductRepositoryIdentity $script:FastLanePolicy.ProductRemote.RepositoryToken

        (Test-CddsiVmTestRelayState -State $state) | Should -BeTrue
        {
            New-CddsiVmTestRelayState `
                -HostToVmRepositoryIdentity 'github.com.evil/LXZ56156/cddsi-host-to-vm' `
                -VmToHostRepositoryIdentity $script:FastLanePolicy.ControlPlane.VmToHost.RepositoryToken `
                -ProductRepositoryIdentity $script:FastLanePolicy.ProductRemote.RepositoryToken
        } | Should -Throw
    }

    It 'canonicalizes property order and hashes the complete envelope plus payload' {
        $left = [pscustomobject][ordered]@{ Z = "line`nvalue"; A = 7 }
        $right = [pscustomobject][ordered]@{ A = 7; Z = "line`nvalue" }
        (ConvertTo-CddsiVmTestRelayCanonicalJson $left) | Should -BeExactly (ConvertTo-CddsiVmTestRelayCanonicalJson $right)
        (Get-CddsiVmTestRelayPayloadSha256 $left) | Should -BeExactly (Get-CddsiVmTestRelayPayloadSha256 $right)

        $state = New-CddsiRelayStateFixture
        $payload = New-CddsiRelayRequestPayloadFixture
        $envelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $payload -MessageType TEST_REQUEST -Status TEST_REQUESTED
        (Get-CddsiVmTestRelayMessageSha256 $envelope $payload) | Should -Match '^[a-f0-9]{64}$'
    }

    It 'accepts PASS, closes the cycle, and never turns the diagnostic result into acceptance' {
        $cycleId = '40000000-0000-4000-8000-000000000001'
        $state = Complete-CddsiRelayOutcomeFixture -Outcome PASS -CycleId $cycleId
        $state.ActiveStatus | Should -BeExactly 'IDLE'
        $state.CompletedCycleIds | Should -Contain $cycleId
        $state.PendingRepair | Should -BeFalse
        (Test-CddsiVmTestRelayState $state) | Should -BeTrue
    }

    It 'accepts <Outcome>, requires FIX_READY on a new cycle, then accepts RETEST_REQUESTED' -TestCases @(
        @{ Outcome = 'FAIL'; OldCycle = '40000000-0000-4000-8000-000000000002'; NewCycle = '40000000-0000-4000-8000-000000000003' }
        @{ Outcome = 'BLOCKED'; OldCycle = '40000000-0000-4000-8000-000000000004'; NewCycle = '40000000-0000-4000-8000-000000000005' }
    ) {
        param($Outcome, $OldCycle, $NewCycle)
        $state = Complete-CddsiRelayOutcomeFixture -Outcome $Outcome -CycleId $OldCycle
        $state.PendingRepair | Should -BeTrue

        $fixPayload = New-CddsiRelayFixPayloadFixture -RepairSourceCycleId $OldCycle
        $newBinding = @{
            RepositoryCommitSha = '6' * 40; ArtifactSha256 = '7' * 64
            SidecarSha256 = '8' * 64; RunbookSha256 = 'a' * 64
            RunId = '30000000-0000-4000-8000-000000000002'
        }
        $fixEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $fixPayload -MessageType FIX_READY `
            -Status CANDIDATE_REBUILT -CycleId $NewCycle -BindingOverrides $newBinding
        $fix = Invoke-CddsiRelayMessageFixture -State $state -Envelope $fixEnvelope -Payload $fixPayload
        $fix.Accepted | Should -BeTrue

        $requestPayload = New-CddsiRelayRequestPayloadFixture -RequestKind Retest -PriorCycleId $OldCycle
        $requestEnvelope = New-CddsiRelayEnvelopeFixture -State $fix.State -Payload $requestPayload `
            -MessageType TEST_REQUEST -Status RETEST_REQUESTED -CycleId $NewCycle
        $retest = Invoke-CddsiRelayMessageFixture -State $fix.State -Envelope $requestEnvelope -Payload $requestPayload
        $retest.Accepted | Should -BeTrue
        $retest.State.ActiveStatus | Should -BeExactly 'RETEST_REQUESTED'
    }

    It 'rejects replay, stale CAS, out-of-order sequence, and wrong previous hash without advancing' {
        $state = New-CddsiRelayStateFixture
        $payload = New-CddsiRelayRequestPayloadFixture
        $envelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $payload -MessageType TEST_REQUEST -Status TEST_REQUESTED
        $first = Invoke-CddsiRelayMessageFixture -State $state -Envelope $envelope -Payload $payload
        $first.Accepted | Should -BeTrue

        (Invoke-CddsiRelayMessageFixture -State $first.State -Envelope $envelope -Payload $payload).ErrorCode | Should -BeExactly 'MESSAGE_REPLAY'

        $ackPayload = New-CddsiRelayControlPayloadFixture 'REQUEST_ACKED'
        $outOfOrder = New-CddsiRelayEnvelopeFixture -State $first.State -Payload $ackPayload -MessageType VM_ACK -Status VM_ACKED `
            -Sequence 3 -PreviousMessageSha256 $first.State.ActiveMessageSha256
        (Invoke-CddsiRelayMessageFixture -State $first.State -Envelope $outOfOrder -Payload $ackPayload).ErrorCode | Should -BeExactly 'SEQUENCE_MISMATCH'

        $wrongPrevious = New-CddsiRelayEnvelopeFixture -State $first.State -Payload $ackPayload -MessageType VM_ACK -Status VM_ACKED `
            -Sequence 2 -PreviousMessageSha256 ('f' * 64)
        (Invoke-CddsiRelayMessageFixture -State $first.State -Envelope $wrongPrevious -Payload $ackPayload).ErrorCode | Should -BeExactly 'PREVIOUS_MESSAGE_MISMATCH'
    }

    It 'rejects payload tampering and expired messages' {
        $state = New-CddsiRelayStateFixture
        $payload = New-CddsiRelayRequestPayloadFixture
        $envelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $payload -MessageType TEST_REQUEST -Status TEST_REQUESTED
        $payload.RequestKind = 'Retest'
        (Test-CddsiVmTestRelayEnvelope -Envelope $envelope -Payload $payload -ValidationTimeUtc $script:ValidationTimeUtc `
            -ExpectedHostToVmRepositoryIdentity $script:HostToVmRepositoryIdentity `
            -ExpectedVmToHostRepositoryIdentity $script:VmToHostRepositoryIdentity `
            -ExpectedProductRepositoryIdentity $script:ProductRepositoryIdentity `
            -AuthenticatedSenderRole HostCoordinator -AuthenticatedOutbox host-to-vm) | Should -BeFalse

        $freshPayload = New-CddsiRelayRequestPayloadFixture
        $expired = New-CddsiRelayEnvelopeFixture -State $state -Payload $freshPayload -MessageType TEST_REQUEST -Status TEST_REQUESTED `
            -CreatedAtUtc '2029-12-31T23:40:00Z' -ExpiresAtUtc '2029-12-31T23:50:00Z'
        (Invoke-CddsiRelayMessageFixture -State $state -Envelope $expired -Payload $freshPayload).Accepted | Should -BeFalse
    }

    It 'rejects a concurrent cycle and physical repository direction mismatch' {
        $state = New-CddsiRelayStateFixture
        $payload = New-CddsiRelayRequestPayloadFixture
        $firstEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $payload -MessageType TEST_REQUEST -Status TEST_REQUESTED `
            -CycleId '40000000-0000-4000-8000-000000000006'
        $first = Invoke-CddsiRelayMessageFixture -State $state -Envelope $firstEnvelope -Payload $payload

        $otherPayload = New-CddsiRelayRequestPayloadFixture
        $otherEnvelope = New-CddsiRelayEnvelopeFixture -State $first.State -Payload $otherPayload -MessageType TEST_REQUEST -Status TEST_REQUESTED `
            -CycleId '40000000-0000-4000-8000-000000000007'
        (Invoke-CddsiRelayMessageFixture -State $first.State -Envelope $otherEnvelope -Payload $otherPayload).ErrorCode | Should -BeExactly 'ACTIVE_CYCLE_CONFLICT'

        $ackPayload = New-CddsiRelayControlPayloadFixture 'REQUEST_ACKED'
        $wrongRepo = New-CddsiRelayEnvelopeFixture -State $first.State -Payload $ackPayload -MessageType VM_ACK -Status VM_ACKED `
            -PhysicalControlRepositoryIdentity $script:HostToVmRepositoryIdentity
        (Invoke-CddsiRelayMessageFixture -State $first.State -Envelope $wrongRepo -Payload $ackPayload).Accepted | Should -BeFalse
    }

    It 'rejects a wrong role and an unknown message type' {
        $state = New-CddsiRelayStateFixture
        $payload = New-CddsiRelayRequestPayloadFixture
        $wrongRole = New-CddsiRelayEnvelopeFixture -State $state -Payload $payload -MessageType TEST_REQUEST -Status TEST_REQUESTED `
            -SenderRole VmTester -Outbox vm-to-host -PhysicalControlRepositoryIdentity $script:VmToHostRepositoryIdentity
        (Invoke-CddsiRelayMessageFixture -State $state -Envelope $wrongRole -Payload $payload).Accepted | Should -BeFalse

        $control = New-CddsiRelayControlPayloadFixture
        $unknown = New-CddsiRelayEnvelopeFixture -State $state -Payload $control -MessageType UNKNOWN -Status UNKNOWN
        (Invoke-CddsiRelayMessageFixture -State $state -Envelope $unknown -Payload $control).Accepted | Should -BeFalse
    }

    It 'reaches CLEAN_READY through a HostCoordinator-forwarded independently verified snapshot receipt' {
        $cycleId = '40000000-0000-4000-8000-000000000010'
        $state = New-CddsiRelayStateFixture
        $snapshotBinding = @{ EnvironmentResetMode = 'SnapshotRestore' }

        $requestPayload = New-CddsiRelayRequestPayloadFixture
        $requestEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $requestPayload `
            -MessageType TEST_REQUEST -Status TEST_REQUESTED -CycleId $cycleId -BindingOverrides $snapshotBinding
        $request = Invoke-CddsiRelayMessageFixture -State $state -Envelope $requestEnvelope -Payload $requestPayload
        $request.Accepted | Should -BeTrue

        $ackPayload = New-CddsiRelayControlPayloadFixture 'REQUEST_ACKED'
        $ackEnvelope = New-CddsiRelayEnvelopeFixture -State $request.State -Payload $ackPayload `
            -MessageType VM_ACK -Status VM_ACKED -CycleId $cycleId
        $ack = Invoke-CddsiRelayMessageFixture -State $request.State -Envelope $ackEnvelope -Payload $ackPayload
        $ack.Accepted | Should -BeTrue

        $snapshotReceiptSha256 = 'f' * 64
        $authorityBindingToken = '6' * 64
        $snapshotPayload = New-CddsiRelaySnapshotReadyPayloadFixture `
            -ExternalReceiptAuthorityBindingToken $authorityBindingToken
        $snapshotEnvelope = New-CddsiRelayEnvelopeFixture -State $ack.State -Payload $snapshotPayload `
            -MessageType SNAPSHOT_READY -Status ENVIRONMENT_PREPARING -CycleId $cycleId `
            -SnapshotReceiptSha256 $snapshotReceiptSha256

        $withoutExternalProof = Invoke-CddsiRelayMessageFixture -State $ack.State `
            -Envelope $snapshotEnvelope -Payload $snapshotPayload
        $withoutExternalProof.Accepted | Should -BeFalse
        $withoutExternalProof.ErrorCode | Should -BeExactly 'RELAY_ENVELOPE_INVALID'

        $wrongReceipt = Invoke-CddsiRelayMessageFixture -State $ack.State -Envelope $snapshotEnvelope `
            -Payload $snapshotPayload -ExternallyVerifiedSnapshotReceiptSha256 ('a' * 64) `
            -ExternallyVerifiedSnapshotAuthorityBindingToken $authorityBindingToken
        $wrongReceipt.Accepted | Should -BeFalse
        $wrongReceipt.ErrorCode | Should -BeExactly 'RELAY_ENVELOPE_INVALID'

        $snapshot = Invoke-CddsiRelayMessageFixture -State $ack.State -Envelope $snapshotEnvelope `
            -Payload $snapshotPayload -ExternallyVerifiedSnapshotReceiptSha256 $snapshotReceiptSha256 `
            -ExternallyVerifiedSnapshotAuthorityBindingToken $authorityBindingToken
        $snapshot.Accepted | Should -BeTrue
        $snapshot.State.ActiveStatus | Should -BeExactly 'ENVIRONMENT_PREPARING'
        $snapshot.State.ActiveSnapshotReceiptSha256 | Should -BeExactly $snapshotReceiptSha256

        $cleanPayload = New-CddsiRelayControlPayloadFixture 'SNAPSHOT_RESTORE_CLEAN'
        $cleanEnvelope = New-CddsiRelayEnvelopeFixture -State $snapshot.State -Payload $cleanPayload `
            -MessageType CLEAN_READY -Status CLEAN_READY -CycleId $cycleId
        $clean = Invoke-CddsiRelayMessageFixture -State $snapshot.State -Envelope $cleanEnvelope -Payload $cleanPayload
        $clean.Accepted | Should -BeTrue
        $clean.State.ActiveStatus | Should -BeExactly 'CLEAN_READY'
    }

    It 'rejects Human and HypervisorSupervisor self-report sender roles on the dual Git transport' {
        $state = New-CddsiRelayStateFixture
        $stopPayload = New-CddsiRelayStopPayloadFixture
        foreach ($selfReportedRole in @('Human', 'HypervisorSupervisor')) {
            $stopEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $stopPayload `
                -MessageType STOP -Status STOPPED -SenderRole $selfReportedRole -Outbox host-to-vm `
                -PhysicalControlRepositoryIdentity $script:HostToVmRepositoryIdentity
            $result = Invoke-CddsiRelayMessageFixture -State $state -Envelope $stopEnvelope -Payload $stopPayload `
                -AuthenticatedSenderRole HostCoordinator -AuthenticatedOutbox host-to-vm
            $result.Accepted | Should -BeFalse
            $result.ErrorCode | Should -BeExactly 'RELAY_ENVELOPE_INVALID'
        }
    }

    It 'allows HostCoordinator to forward STOP, closes the old cycle, and requires a new CycleId' {
        $state = New-CddsiRelayStateFixture
        $cycleId = '40000000-0000-4000-8000-000000000008'
        $requestPayload = New-CddsiRelayRequestPayloadFixture
        $requestEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $requestPayload -MessageType TEST_REQUEST -Status TEST_REQUESTED -CycleId $cycleId
        $request = Invoke-CddsiRelayMessageFixture -State $state -Envelope $requestEnvelope -Payload $requestPayload

        $stopPayload = New-CddsiRelayStopPayloadFixture
        $stopEnvelope = New-CddsiRelayEnvelopeFixture -State $request.State -Payload $stopPayload -MessageType STOP -Status STOPPED -CycleId $cycleId
        $stopEnvelope.SenderRole | Should -BeExactly 'HostCoordinator'
        $stop = Invoke-CddsiRelayMessageFixture -State $request.State -Envelope $stopEnvelope -Payload $stopPayload
        $stop.Accepted | Should -BeTrue
        $stop.State.StoppedCycleIds | Should -Contain $cycleId

        $oldPayload = New-CddsiRelayRequestPayloadFixture
        $oldEnvelope = New-CddsiRelayEnvelopeFixture -State $stop.State -Payload $oldPayload -MessageType TEST_REQUEST -Status TEST_REQUESTED -CycleId $cycleId
        (Invoke-CddsiRelayMessageFixture -State $stop.State -Envelope $oldEnvelope -Payload $oldPayload).ErrorCode | Should -BeExactly 'CYCLE_CLOSED'
    }

    It 'fails Formal Lane closed even when signature-shaped fields are supplied' {
        $state = New-CddsiRelayStateFixture
        $payload = New-CddsiRelayRequestPayloadFixture
        $formal = New-CddsiRelayEnvelopeFixture -State $state -Payload $payload -MessageType TEST_REQUEST -Status TEST_REQUESTED `
            -Lane Formal -SigningKeyId formal-key -SignatureAlgorithm RSA-SHA256 -Signature synthetic-signature
        $result = Invoke-CddsiRelayMessageFixture -State $state -Envelope $formal -Payload $payload
        $result.Accepted | Should -BeFalse
        $result.ErrorCode | Should -BeExactly 'FORMAL_LANE_UNAVAILABLE'
    }

    It 'rejects a Fast TEST_RESULT that claims Formal evidence or an acceptance receipt' {
        $cycleId = '40000000-0000-4000-8000-000000000009'
        $state = New-CddsiRelayStateFixture
        foreach ($step in @(
            @{ Type = 'TEST_REQUEST'; Status = 'TEST_REQUESTED'; Payload = New-CddsiRelayRequestPayloadFixture },
            @{ Type = 'VM_ACK'; Status = 'VM_ACKED'; Payload = New-CddsiRelayControlPayloadFixture 'REQUEST_ACKED' },
            @{ Type = 'CLEAN_READY'; Status = 'CLEAN_READY'; Payload = New-CddsiRelayControlPayloadFixture 'GUEST_RESET_CLEAN' },
            @{ Type = 'TEST_STARTED'; Status = 'TEST_RUNNING'; Payload = New-CddsiRelayControlPayloadFixture 'RUNBOOK_STARTED' }
        )) {
            $envelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $step.Payload -MessageType $step.Type -Status $step.Status -CycleId $cycleId
            $state = (Invoke-CddsiRelayMessageFixture -State $state -Envelope $envelope -Payload $step.Payload).State
        }

        $formalPayload = New-CddsiRelayResultPayloadFixture -CycleId $cycleId -EvidenceClass Formal
        $formalEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $formalPayload -MessageType TEST_RESULT -Status TEST_PASSED -CycleId $cycleId
        (Invoke-CddsiRelayMessageFixture -State $state -Envelope $formalEnvelope -Payload $formalPayload).Accepted | Should -BeFalse

        $receiptPayload = New-CddsiRelayResultPayloadFixture -CycleId $cycleId `
            -AcceptanceReceiptUri 'formal/object' -AcceptanceReceiptSha256 ('a' * 64)
        $receiptEnvelope = New-CddsiRelayEnvelopeFixture -State $state -Payload $receiptPayload -MessageType TEST_RESULT -Status TEST_PASSED -CycleId $cycleId
        (Invoke-CddsiRelayMessageFixture -State $state -Envelope $receiptEnvelope -Payload $receiptPayload).Accepted | Should -BeFalse
    }
}
