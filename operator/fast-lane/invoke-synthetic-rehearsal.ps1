# Pure, bounded P10A-0A Fast Lane rehearsal. Callers must load common.ps1 and
# vm-test-relay.ps1 first. The only writes are canonical files below a new,
# explicitly supplied synthetic sandbox root.

function New-CddsiFastLaneSyntheticPayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MessageType,
        [Parameter(Mandatory = $true)][string]$CycleId,
        [Parameter(Mandatory = $true)][string]$RunId,
        [ValidateSet('PASS', 'FAIL', 'BLOCKED')][string]$OverallStatus = 'PASS'
    )

    if ($MessageType -ceq 'TEST_REQUEST') {
        return [pscustomobject][ordered]@{
            SchemaVersion = '1'; ContractVersion = 'cddsi-vm-test-relay-test-request-v1'
            RequestKind = 'Initial'; PriorCycleId = $null
        }
    }
    if ($MessageType -ceq 'TEST_RESULT') {
        return [pscustomobject][ordered]@{
            SchemaVersion = '1'; ContractVersion = 'cddsi-vm-test-relay-test-result-v1'
            CycleId = $CycleId; RunId = $RunId; Phase = 'Synthetic'; MatrixCell = 'win11-x64-synthetic'
            OverallStatus = $OverallStatus; EvidenceClass = 'Diagnostic'
            AcceptanceReceiptUri = $null; AcceptanceReceiptSha256 = $null
            SecretFindingCount = 0; ForbiddenMutationCount = 0; UnexpectedLedgerEntryCount = 0
            SummaryCode = ('SYNTHETIC_' + $OverallStatus)
        }
    }
    if ($MessageType -ceq 'STOP') {
        return [pscustomobject][ordered]@{
            SchemaVersion = '1'; ContractVersion = 'cddsi-vm-test-relay-stop-v1'
            ReasonCode = 'SYNTHETIC_OPERATOR_STOP'
        }
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = '1'; ContractVersion = 'cddsi-vm-test-relay-control-v1'
        Code = ('SYNTHETIC_' + $MessageType)
    }
}

function New-CddsiFastLaneSyntheticEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$MessageId,
        [Parameter(Mandatory = $true)][string]$CycleId,
        [Parameter(Mandatory = $true)][long]$Sequence,
        [Parameter(Mandatory = $true)][string]$MessageType,
        [Parameter(Mandatory = $true)][string]$SenderRole,
        [Parameter(Mandatory = $true)][string]$Outbox,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][AllowNull()]$PreviousMessageSha256,
        [Parameter(Mandatory = $true)][string]$Nonce,
        [string]$CreatedAtUtc = '2030-01-01T00:04:00.0000000Z',
        [string]$ExpiresAtUtc = '2030-01-01T00:14:00.0000000Z',
        [AllowNull()]$CleanReceiptSha256 = $null,
        [AllowNull()]$EvidenceUri = $null,
        [AllowNull()]$EvidenceSha256 = $null
    )

    $canonicalPayload = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Payload
    $physicalRepository = $(if ($Outbox -ceq 'host-to-vm') {
        $State.HostToVmRepositoryIdentity
    } else {
        $State.VmToHostRepositoryIdentity
    })
    return [pscustomobject][ordered]@{
        SchemaVersion = '1'; ProtocolVersion = 'cddsi-vm-test-relay-v1'; Lane = 'Fast'
        MessageId = $MessageId; CycleId = $CycleId; Sequence = $Sequence
        MessageType = $MessageType; SenderRole = $SenderRole
        HostToVmRepositoryIdentity = $State.HostToVmRepositoryIdentity
        VmToHostRepositoryIdentity = $State.VmToHostRepositoryIdentity
        PhysicalControlRepositoryIdentity = $physicalRepository
        ProductRepositoryIdentity = $State.ProductRepositoryIdentity; Outbox = $Outbox
        CreatedAtUtc = $CreatedAtUtc; ExpiresAtUtc = $ExpiresAtUtc; Nonce = $Nonce
        ExpectedStateBindingToken = $State.StateBindingToken
        PreviousMessageSha256 = $PreviousMessageSha256
        RepositoryCommitSha = ('a' * 40); RepairRef = 'refs/heads/codex/repair/p10a-0a'
        ArtifactProfile = 'VmCalibration'; CandidateId = $null
        ArtifactSha256 = ('b' * 64); SidecarSha256 = ('c' * 64); RunbookSha256 = ('d' * 64)
        VmImageSha256 = ('e' * 64); OsMatrixCell = 'win11-x64-synthetic'; RunId = $RunId
        EnvironmentResetMode = 'GuestReset'; ResetPolicySha256 = ('f' * 64)
        ResetAllowListSha256 = ('1' * 64); OperationGrantSha256 = ('2' * 64)
        SessionAnchorSha256 = ('3' * 64); CleanReceiptSha256 = $CleanReceiptSha256
        SnapshotReceiptSha256 = $null
        PayloadSha256 = Get-CddsiVmTestRelayPayloadSha256 -Payload $Payload
        MessageBodyLength = [Text.Encoding]::UTF8.GetByteCount($canonicalPayload)
        EvidenceUri = $EvidenceUri; EvidenceSha256 = $EvidenceSha256; Status = $Status
        SigningKeyId = $null; SignatureAlgorithm = $null; Signature = $null
    }
}

function Write-CddsiFastLaneSyntheticCanonicalFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Root,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [Parameter(Mandatory = $true)]$Value
    )

    $path = [IO.Path]::Combine($Root, $RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar))
    $parent = [IO.Path]::GetDirectoryName($path)
    [void][IO.Directory]::CreateDirectory($parent)
    if ([IO.File]::Exists($path)) { throw "Synthetic append-only path already exists: $RelativePath" }
    $canonical = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Value
    [IO.File]::WriteAllBytes($path, (New-Object Text.UTF8Encoding($false)).GetBytes($canonical + "`n"))
    return [pscustomobject][ordered]@{
        RelativePath = $RelativePath
        Sha256 = Get-CddsiSupplyChainTextBindingToken -Text $canonical
        ByteLength = [Text.Encoding]::UTF8.GetByteCount($canonical + "`n")
    }
}

function Invoke-CddsiFastLaneSyntheticRehearsal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$SandboxRoot
    )

    $required = @(
        'ConvertTo-CddsiVmTestRelayCanonicalJson', 'Get-CddsiVmTestRelayPayloadSha256',
        'Get-CddsiVmTestRelayMessageSha256', 'New-CddsiVmTestRelayState',
        'Resolve-CddsiVmTestRelayTransition', 'Get-CddsiSupplyChainTextBindingToken'
    )
    foreach ($commandName in $required) {
        if ($null -eq (Get-Command -Name $commandName -CommandType Function -ErrorAction SilentlyContinue)) {
            throw "Required pure relay function is not loaded: $commandName"
        }
    }

    $fullRoot = [IO.Path]::GetFullPath($SandboxRoot)
    $leaf = [IO.Path]::GetFileName($fullRoot.TrimEnd([IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar))
    if ($leaf -notmatch '^cddsi-fastlane-synthetic-[a-f0-9]{8}-[a-f0-9]{4}-4[a-f0-9]{3}-[89ab][a-f0-9]{3}-[a-f0-9]{12}$') {
        throw 'Synthetic rehearsal root must use the cddsi-fastlane-synthetic-<UUID> ownership form.'
    }
    $rootParent = [IO.Path]::GetDirectoryName($fullRoot)
    if (-not [IO.Directory]::Exists($rootParent) -or [IO.Directory]::Exists($fullRoot) -or [IO.File]::Exists($fullRoot)) {
        throw 'Synthetic rehearsal root must be a new child of an existing caller-owned directory.'
    }
    [void][IO.Directory]::CreateDirectory($fullRoot)

    $outboxRecords = [System.Collections.ArrayList]::new()
    $caseRecords = [System.Collections.ArrayList]::new()
    $validationTime = '2030-01-01T00:05:00.0000000Z'
    $hostRepository = 'synthetic/cddsi-host-to-vm'
    $vmRepository = 'synthetic/cddsi-vm-to-host'
    $productRepository = 'synthetic/cddsi-product'
    $cleanReceipt = '4' * 64
    $diagnosticHash = '5' * 64

    $marker = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-synthetic-owner-v1'
        Owner = 'CDDsiFastLaneRehearsal'; SyntheticOnly = $true
    }
    [void](Write-CddsiFastLaneSyntheticCanonicalFile -Root $fullRoot -RelativePath '.cddsi-owner.json' -Value $marker)

    function Invoke-SyntheticDelivery {
        param($State, $Envelope, $Payload, [string]$FileName, [string]$PhysicalOutbox,
            [string]$AuthenticatedRole, [string]$AuthenticatedOutbox)
        $bundle = [pscustomobject][ordered]@{ Envelope = $Envelope; Payload = $Payload }
        $file = Write-CddsiFastLaneSyntheticCanonicalFile -Root $fullRoot `
            -RelativePath ($PhysicalOutbox + '/' + $FileName) -Value $bundle
        [void]$outboxRecords.Add($file)
        return Resolve-CddsiVmTestRelayTransition -State $State -Envelope $Envelope -Payload $Payload `
            -ValidationTimeUtc $validationTime -AuthenticatedSenderRole $AuthenticatedRole `
            -AuthenticatedOutbox $AuthenticatedOutbox
    }

    function New-SyntheticState {
        return New-CddsiVmTestRelayState -HostToVmRepositoryIdentity $hostRepository `
            -VmToHostRepositoryIdentity $vmRepository -ProductRepositoryIdentity $productRepository
    }

    $passState = New-SyntheticState
    $passCycle = '91000000-0000-4000-8000-000000000001'
    $passRun = '94000000-0000-4000-8000-000000000001'
    $passSteps = @(
        @('TEST_REQUEST', 'HostCoordinator', 'host-to-vm', 'TEST_REQUESTED'),
        @('VM_ACK', 'VmTester', 'vm-to-host', 'VM_ACKED'),
        @('CLEAN_READY', 'VmTester', 'vm-to-host', 'CLEAN_READY'),
        @('TEST_STARTED', 'VmTester', 'vm-to-host', 'TEST_RUNNING'),
        @('TEST_RESULT', 'VmTester', 'vm-to-host', 'TEST_PASSED'),
        @('HOST_ACK', 'HostCoordinator', 'host-to-vm', 'HOST_ACKED')
    )
    $passAccepted = $true
    for ($index = 0; $index -lt $passSteps.Count; $index++) {
        $sequence = $index + 1
        $step = $passSteps[$index]
        $payload = New-CddsiFastLaneSyntheticPayload -MessageType $step[0] -CycleId $passCycle -RunId $passRun
        $needsClean = $sequence -ge 3
        $hasEvidence = $sequence -ge 5
        $envelope = New-CddsiFastLaneSyntheticEnvelope -State $passState -Payload $payload `
            -MessageId ('92000000-0000-4000-8000-{0:d12}' -f $sequence) -CycleId $passCycle `
            -Sequence $sequence -MessageType $step[0] -SenderRole $step[1] -Outbox $step[2] `
            -Status $step[3] -RunId $passRun -PreviousMessageSha256 $passState.ActiveMessageSha256 `
            -Nonce ('93000000-0000-4000-8000-{0:d12}' -f $sequence) `
            -CleanReceiptSha256 $(if ($needsClean) { $cleanReceipt } else { $null }) `
            -EvidenceUri $(if ($hasEvidence) { 'diagnostic/pass/report.json' } else { $null }) `
            -EvidenceSha256 $(if ($hasEvidence) { $diagnosticHash } else { $null })
        $transition = Invoke-SyntheticDelivery $passState $envelope $payload `
            ('{0:d3}-pass-{1}.json' -f $sequence, $step[0].ToLowerInvariant()) $step[2] $step[1] $step[2]
        $passAccepted = $passAccepted -and $transition.Accepted -and $transition.Advanced
        $passState = $transition.State
    }
    $passObserved = $passAccepted -and $passState.ActiveStatus -ceq 'IDLE' -and `
        $passState.CompletedCycleIds -ccontains $passCycle
    [void]$caseRecords.Add([pscustomobject][ordered]@{
        Name = 'pass_chain'; ExpectedDisposition = 'ACCEPT'; ObservedDisposition = $(if ($passObserved) { 'ACCEPT' } else { 'REJECT' })
        ErrorCode = ''; Passed = $passObserved
    })

    function Add-NegativeInitialCase {
        param([string]$Name, [string]$CycleId, [string]$MessageId, [string]$Nonce,
            [string]$ExpectedError, [scriptblock]$Mutate, [string]$PhysicalOutbox = 'host-to-vm',
            [string]$AuthenticatedOutbox = 'host-to-vm')
        $state = New-SyntheticState
        $runId = $CycleId.Replace('91000000', '94000000')
        $payload = New-CddsiFastLaneSyntheticPayload -MessageType TEST_REQUEST -CycleId $CycleId -RunId $runId
        $envelope = New-CddsiFastLaneSyntheticEnvelope -State $state -Payload $payload -MessageId $MessageId `
            -CycleId $CycleId -Sequence 1 -MessageType TEST_REQUEST -SenderRole HostCoordinator `
            -Outbox host-to-vm -Status TEST_REQUESTED -RunId $runId -PreviousMessageSha256 $null -Nonce $Nonce
        & $Mutate $envelope $payload
        $transition = Invoke-SyntheticDelivery $state $envelope $payload ($Name + '.json') `
            $PhysicalOutbox HostCoordinator $AuthenticatedOutbox
        $passed = -not $transition.Accepted -and $transition.ErrorCode -ceq $ExpectedError
        [void]$caseRecords.Add([pscustomobject][ordered]@{
            Name = $Name; ExpectedDisposition = 'REJECT'; ObservedDisposition = $(if ($transition.Accepted) { 'ACCEPT' } else { 'REJECT' })
            ErrorCode = $transition.ErrorCode; Passed = $passed
        })
        return [pscustomobject][ordered]@{ State = $state; Envelope = $envelope; Payload = $payload; Transition = $transition }
    }

    $duplicateState = New-SyntheticState
    $duplicateCycle = '91000000-0000-4000-8000-000000000002'
    $duplicateRun = '94000000-0000-4000-8000-000000000002'
    $duplicatePayload = New-CddsiFastLaneSyntheticPayload TEST_REQUEST $duplicateCycle $duplicateRun
    $duplicateEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $duplicateState -Payload $duplicatePayload `
        -MessageId '92000000-0000-4000-8000-000000000010' -CycleId $duplicateCycle -Sequence 1 `
        -MessageType TEST_REQUEST -SenderRole HostCoordinator -Outbox host-to-vm -Status TEST_REQUESTED `
        -RunId $duplicateRun -PreviousMessageSha256 $null -Nonce '93000000-0000-4000-8000-000000000010'
    $duplicateFirst = Invoke-SyntheticDelivery $duplicateState $duplicateEnvelope $duplicatePayload `
        '010-duplicate-first.json' host-to-vm HostCoordinator host-to-vm
    $duplicateSecond = Invoke-SyntheticDelivery $duplicateFirst.State $duplicateEnvelope $duplicatePayload `
        '011-duplicate-replay.json' host-to-vm HostCoordinator host-to-vm
    $duplicatePassed = $duplicateFirst.Accepted -and -not $duplicateSecond.Accepted -and `
        $duplicateSecond.ErrorCode -ceq 'MESSAGE_REPLAY'
    [void]$caseRecords.Add([pscustomobject][ordered]@{
        Name = 'duplicate_message'; ExpectedDisposition = 'REJECT'; ObservedDisposition = $(if ($duplicateSecond.Accepted) { 'ACCEPT' } else { 'REJECT' })
        ErrorCode = $duplicateSecond.ErrorCode; Passed = $duplicatePassed
    })

    [void](Add-NegativeInitialCase stale_message '91000000-0000-4000-8000-000000000003' `
        '92000000-0000-4000-8000-000000000020' '93000000-0000-4000-8000-000000000020' `
        RELAY_ENVELOPE_INVALID { param($envelope, $payload) $envelope.CreatedAtUtc = '2029-12-31T23:40:00.0000000Z'; $envelope.ExpiresAtUtc = '2029-12-31T23:50:00.0000000Z' })
    [void](Add-NegativeInitialCase tampered_payload '91000000-0000-4000-8000-000000000004' `
        '92000000-0000-4000-8000-000000000021' '93000000-0000-4000-8000-000000000021' `
        RELAY_ENVELOPE_INVALID { param($envelope, $payload) $payload.ContractVersion = 'cddsi-vm-test-relay-tampered-v1' })
    [void](Add-NegativeInitialCase wrong_direction '91000000-0000-4000-8000-000000000005' `
        '92000000-0000-4000-8000-000000000022' '93000000-0000-4000-8000-000000000022' `
        RELAY_ENVELOPE_INVALID { param($envelope, $payload) } vm-to-host vm-to-host)

    $stopState = New-SyntheticState
    $stopCycle = '91000000-0000-4000-8000-000000000006'
    $stopRun = '94000000-0000-4000-8000-000000000006'
    $requestPayload = New-CddsiFastLaneSyntheticPayload TEST_REQUEST $stopCycle $stopRun
    $requestEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $stopState -Payload $requestPayload `
        -MessageId '92000000-0000-4000-8000-000000000030' -CycleId $stopCycle -Sequence 1 `
        -MessageType TEST_REQUEST -SenderRole HostCoordinator -Outbox host-to-vm -Status TEST_REQUESTED `
        -RunId $stopRun -PreviousMessageSha256 $null -Nonce '93000000-0000-4000-8000-000000000030'
    $requestTransition = Invoke-SyntheticDelivery $stopState $requestEnvelope $requestPayload `
        '030-stop-request.json' host-to-vm HostCoordinator host-to-vm
    $stopPayload = New-CddsiFastLaneSyntheticPayload STOP $stopCycle $stopRun
    $stopEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $requestTransition.State -Payload $stopPayload `
        -MessageId '92000000-0000-4000-8000-000000000031' -CycleId $stopCycle -Sequence 2 `
        -MessageType STOP -SenderRole HostCoordinator -Outbox host-to-vm -Status STOPPED -RunId $stopRun `
        -PreviousMessageSha256 $requestTransition.MessageSha256 -Nonce '93000000-0000-4000-8000-000000000031'
    $stopTransition = Invoke-SyntheticDelivery $requestTransition.State $stopEnvelope $stopPayload `
        '031-stop.json' host-to-vm HostCoordinator host-to-vm
    $stopPassed = $stopTransition.Accepted -and $stopTransition.State.StoppedCycleIds -ccontains $stopCycle
    [void]$caseRecords.Add([pscustomobject][ordered]@{
        Name = 'stop_closes_cycle'; ExpectedDisposition = 'ACCEPT'; ObservedDisposition = $(if ($stopTransition.Accepted) { 'ACCEPT' } else { 'REJECT' })
        ErrorCode = $stopTransition.ErrorCode; Passed = $stopPassed
    })
    $continuePayload = New-CddsiFastLaneSyntheticPayload VM_ACK $stopCycle $stopRun
    $continueEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $stopTransition.State -Payload $continuePayload `
        -MessageId '92000000-0000-4000-8000-000000000032' -CycleId $stopCycle -Sequence 3 `
        -MessageType VM_ACK -SenderRole VmTester -Outbox vm-to-host -Status VM_ACKED -RunId $stopRun `
        -PreviousMessageSha256 $stopTransition.MessageSha256 -Nonce '93000000-0000-4000-8000-000000000032'
    $continueTransition = Invoke-SyntheticDelivery $stopTransition.State $continueEnvelope $continuePayload `
        '032-post-stop-continuation.json' vm-to-host VmTester vm-to-host
    $continuePassed = -not $continueTransition.Accepted -and $continueTransition.ErrorCode -ceq 'CYCLE_CLOSED'
    [void]$caseRecords.Add([pscustomobject][ordered]@{
        Name = 'post_stop_continuation'; ExpectedDisposition = 'REJECT'; ObservedDisposition = $(if ($continueTransition.Accepted) { 'ACCEPT' } else { 'REJECT' })
        ErrorCode = $continueTransition.ErrorCode; Passed = $continuePassed
    })

    $passedCount = @($caseRecords | Where-Object { $_.Passed }).Count
    $hostFiles = @($outboxRecords | Where-Object { $_.RelativePath -like 'host-to-vm/*' })
    $vmFiles = @($outboxRecords | Where-Object { $_.RelativePath -like 'vm-to-host/*' })
    $evidenceBody = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-synthetic-rehearsal-evidence-v1'
        ProtocolVersion = 'cddsi-vm-test-relay-v1'; Lane = 'Fast'; Mode = $Mode
        EvidenceClass = 'Diagnostic'; SyntheticOnly = $true; ProductChanged = $false
        ProductLiveOperationCount = 0; NetworkAccessCount = 0; GitInvocationCount = 0
        RealSystemProbeCount = 0; SecretFindingCount = 0
        Outboxes = @(
            [pscustomobject][ordered]@{ Name = 'host-to-vm'; WriterRole = 'HostCoordinator'; RepositoryIdentity = $hostRepository; MessageCount = $hostFiles.Count; Files = @($hostFiles) },
            [pscustomobject][ordered]@{ Name = 'vm-to-host'; WriterRole = 'VmTester'; RepositoryIdentity = $vmRepository; MessageCount = $vmFiles.Count; Files = @($vmFiles) }
        )
        Cases = @($caseRecords)
        Summary = [pscustomobject][ordered]@{
            ExpectationCount = $caseRecords.Count; ExpectationPassedCount = $passedCount
            ExpectationFailedCount = $caseRecords.Count - $passedCount
            OverallStatus = $(if ($passedCount -eq $caseRecords.Count) { 'PASS' } else { 'FAIL' })
        }
        EvidenceRelativePath = 'evidence/rehearsal.json'
    }
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion = $evidenceBody.SchemaVersion; ContractVersion = $evidenceBody.ContractVersion
        ProtocolVersion = $evidenceBody.ProtocolVersion; Lane = $evidenceBody.Lane; Mode = $evidenceBody.Mode
        EvidenceClass = $evidenceBody.EvidenceClass; SyntheticOnly = $evidenceBody.SyntheticOnly
        ProductChanged = $evidenceBody.ProductChanged; ProductLiveOperationCount = $evidenceBody.ProductLiveOperationCount
        NetworkAccessCount = $evidenceBody.NetworkAccessCount; GitInvocationCount = $evidenceBody.GitInvocationCount
        RealSystemProbeCount = $evidenceBody.RealSystemProbeCount; SecretFindingCount = $evidenceBody.SecretFindingCount
        Outboxes = $evidenceBody.Outboxes; Cases = $evidenceBody.Cases; Summary = $evidenceBody.Summary
        EvidenceRelativePath = $evidenceBody.EvidenceRelativePath
        EvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $evidenceBody)
    }
    [void](Write-CddsiFastLaneSyntheticCanonicalFile -Root $fullRoot `
        -RelativePath $evidence.EvidenceRelativePath -Value $evidence)
    return $evidence
}
