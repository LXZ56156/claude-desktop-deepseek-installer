[CmdletBinding()]
param(
    [ValidateSet('Status', 'WaitPointer', 'PublishPointer')][string]$Action = 'Status',
    [ValidateSet('HostCoordinator', 'VmTester')][string]$Role = 'HostCoordinator',
    [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
    [AllowNull()][string]$MessageId = $null,
    [AllowNull()][string]$PayloadSha256 = $null,
    [AllowNull()][string]$Commit = $null,
    [ValidateRange(0, 9007199254740991L)][long]$AfterSequence = 0,
    [ValidateRange(1, 600)][int]$MaxWaitSeconds = 120,
    [ValidateRange(1, 32)][int]$MaxReconnectAttempts = 5,
    [AllowNull()][uri]$Endpoint = $null,
    [AllowNull()][string]$StateRoot = $null,
    [AllowNull()][string]$RunId = $null,
    [AllowNull()][string]$OwnerSid = $null,
    [AllowNull()][string]$OwnershipTokenSha256 = $null,
    [AllowNull()][string]$Environment = $null,
    [AllowNull()][string]$KeyId = $null,
    [switch]$AcknowledgeOperatorPlaneLive
)

Set-StrictMode -Version Latest

if ($null -eq (Get-Command -Name Invoke-CddsiRealtimeRelayPublish -ErrorAction SilentlyContinue)) {
    . (Join-Path $PSScriptRoot 'realtime-relay-client.ps1')
}

$script:CddsiRealtimeForegroundResultSchema = 'cddsi-realtime-relay-foreground-result-v1'
$script:CddsiRealtimeForegroundCodes = @(
    'FOREGROUND_STATUS_READY', 'FOREGROUND_PLANNED', 'FOREGROUND_POINTER_RECEIVED',
    'FOREGROUND_POINTER_DUPLICATE', 'FOREGROUND_POINTER_PUBLISHED',
    'FOREGROUND_POINTER_INVALID', 'FOREGROUND_WRONG_DIRECTION',
    'FOREGROUND_CONTEXT_REQUIRED', 'FOREGROUND_CONTEXT_INVALID',
    'FOREGROUND_CONFIRMATION_REQUIRED', 'FOREGROUND_PROVIDER_MISSING',
    'FOREGROUND_STATE_ROOT_INVALID', 'FOREGROUND_LOCK_FAILED',
    'FOREGROUND_STATE_INVALID', 'FOREGROUND_STATE_COMMIT_FAILED',
    'FOREGROUND_TRANSPORT_INVALID', 'FOREGROUND_RECONNECT_EXHAUSTED',
    'FOREGROUND_NOTIFICATION_INVALID', 'FOREGROUND_POINTER_MISMATCH',
    'FOREGROUND_MESSAGE_ID_REPLAY',
    'FOREGROUND_SEQUENCE_GAP', 'FOREGROUND_PREVIOUS_HASH_MISMATCH',
    'FOREGROUND_ACK_INVALID', 'FOREGROUND_ACK_REJECTED',
    'FOREGROUND_WAIT_TIMEOUT', 'FOREGROUND_BLOCKED'
)

function Get-CddsiRealtimeRelayForegroundPolicyInternal {
    param([Parameter(Mandatory = $true)][ValidateSet('HostCoordinator', 'VmTester')][string]$Role)

    if ($Role -ceq 'HostCoordinator') {
        return [pscustomobject][ordered]@{
            ClientId = 'host-coordinator-v1'; ReadLane = 'vm-to-host'; WriteLane = 'host-to-vm'
        }
    }
    return [pscustomobject][ordered]@{
        ClientId = 'vm-tester-v1'; ReadLane = 'host-to-vm'; WriteLane = 'vm-to-host'
    }
}

function ConvertTo-CddsiRealtimeRelayForegroundWebSocketEndpointInternal {
    param([Parameter(Mandatory = $true)][uri]$Endpoint)

    if (-not $Endpoint.IsAbsoluteUri -or $Endpoint.UserInfo.Length -ne 0 -or
        $Endpoint.Query.Length -ne 0 -or $Endpoint.Fragment.Length -ne 0 -or
        $Endpoint.AbsolutePath -cne '/' -or -not $Endpoint.IsDefaultPort -or
        $Endpoint.Port -ne 443 -or
        $Endpoint.Host -cnotmatch '^[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev$') {
        throw 'FOREGROUND_ENDPOINT_INVALID'
    }
    if ($Endpoint.Scheme -ceq 'wss') { return $Endpoint }
    if ($Endpoint.Scheme -cne 'https') { throw 'FOREGROUND_ENDPOINT_INVALID' }
    return [uri]('wss://{0}/' -f $Endpoint.Host)
}

function Test-CddsiRealtimeRelayForegroundPointerInternal {
    param([Parameter(Mandatory = $true)]$Pointer)

    return $null -ne $Pointer -and
        (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $Pointer `
            -Expected $script:CddsiRealtimePublishPointerProperties) -and
        $Pointer.SchemaVersion -ceq $script:CddsiRealtimePublishPointerSchema -and
        @('host-to-vm', 'vm-to-host') -ccontains $Pointer.Lane -and
        $Pointer.MessageId -is [string] -and $Pointer.MessageId -cmatch
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -and
        $Pointer.PayloadSha256 -is [string] -and
        $Pointer.PayloadSha256 -cmatch '^[0-9a-f]{64}$' -and
        $Pointer.Commit -is [string] -and $Pointer.Commit -cmatch '^[0-9a-f]{40}$'
}

function New-CddsiRealtimeRelayForegroundResultInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowNull()][string]$RelayCode,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][bool]$Changed,
        [Parameter(Mandatory = $true)]$Policy,
        [AllowNull()]$Pointer,
        [AllowNull()]$Sequence,
        [Parameter(Mandatory = $true)][bool]$Idempotent,
        [Parameter(Mandatory = $true)][long]$AckCount,
        [Parameter(Mandatory = $true)][long]$ReconnectCount,
        [Parameter(Mandatory = $true)][long]$NetworkCount,
        [Parameter(Mandatory = $true)][long]$StateMutationCount
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeForegroundResultSchema
        Action = $Action; Role = $Role; Status = $Status; Code = $Code; RelayCode = $RelayCode
        Mode = $Mode; Changed = $Changed
        ReadLane = $Policy.ReadLane; WriteLane = $Policy.WriteLane
        MessageId = if ($null -eq $Pointer) { $null } else { $Pointer.MessageId }
        Sequence = $Sequence
        PayloadSha256 = if ($null -eq $Pointer) { $null } else { $Pointer.PayloadSha256 }
        Commit = if ($null -eq $Pointer) { $null } else { $Pointer.Commit }
        Idempotent = $Idempotent; AckCount = $AckCount; ReconnectCount = $ReconnectCount
        ProductLiveAttemptCount = 0L; RealRegistryAccessCount = 0L; ProductNetworkRequestCount = 0L
        OperatorRelayNetworkRequestCount = $NetworkCount
        OperatorGitInvocationCount = 0L; OperatorGitTransportCount = 0L
        OperatorLocalStateMutationCount = $StateMutationCount
        OperatorCodexProcessSpawnCount = 0L; FixedWakeEffectCount = 0L
        PayloadExecutionCount = 0L; RealNetworkAccessCount = 0L
        RealCredentialManagerAccessCount = 0L; ProductProcessSpawnCount = 0L
        OutsideOwnedStateWriteCount = 0L; UnexpectedLedgerEntryCount = 0L; MutationSpyCount = 0L
    }
}

function Get-CddsiRealtimeRelayForegroundNowInternal {
    param($Context, [string]$Mode)

    if ($Mode -ceq 'Live') {
        return Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $Context.Providers.Clock
    }
    if ($Context.Providers.Clock.GetUtcNow -isnot [scriptblock]) {
        throw 'FOREGROUND_PROVIDER_MISSING'
    }
    $value = & $Context.Providers.Clock.GetUtcNow
    if ($value -isnot [DateTimeOffset]) { throw 'FOREGROUND_PROVIDER_MISSING' }
    return $value
}

function Invoke-CddsiRealtimeRelayForegroundStateInternal {
    param($Context, [string]$Mode, [string]$Operation, [AllowNull()][string]$Lane = $null,
        [AllowNull()]$State = $null, [AllowNull()]$Handle = $null)

    if ($Mode -ceq 'Live') {
        return Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $Context.Providers.State -Operation $Operation `
            -Lane $Lane -State $State -Handle $Handle
    }
    $provider = $Context.Providers.State
    if ($null -eq $provider.PSObject.Properties[$Operation] -or
        $provider.$Operation -isnot [scriptblock]) { throw 'FOREGROUND_PROVIDER_MISSING' }
    switch ($Operation) {
        'Load' { return & $provider.Load $Lane }
        'CommitAtomically' { return & $provider.CommitAtomically $State }
        'ReleaseLock' { return & $provider.ReleaseLock $Handle }
        default { return & $provider.$Operation }
    }
}

function Assert-CddsiRealtimeRelayForegroundContextInternal {
    param($Context, $RuntimeAssertion, $Policy, [string]$Mode)

    if ($null -eq $Context -or $null -eq $Context.PSObject -or
        $null -eq $Context.PSObject.Properties['ClientId'] -or
        $Context.ClientId -cne $Policy.ClientId) { throw 'FOREGROUND_CONTEXT_INVALID' }
    try {
        Assert-CddsiRealtimeRelayPublisherContextInternal -RelayContext $Context `
            -Mode $Mode -Lane $Policy.WriteLane -RuntimeAssertion $RuntimeAssertion
    }
    catch { throw 'FOREGROUND_CONTEXT_INVALID' }
}

function Invoke-CddsiRealtimeRelayForegroundWaitInternal {
    param(
        $Context, $RuntimeAssertion, $Pointer, $Policy,
        [string]$Role, [string]$Mode, [long]$AfterSequence,
        [int]$MaxWaitSeconds, [int]$MaxReconnectAttempts
    )

    $lockHandle = $null
    $lifecycleLockHandle = $null
    $sessionId = $null
    $ackCount = 0L
    $reconnectCount = 0L
    $networkCount = 0L
    $mutationCount = 0L
    try {
        Assert-CddsiRealtimeRelayForegroundContextInternal `
            -Context $Context -RuntimeAssertion $RuntimeAssertion -Policy $Policy -Mode $Mode
        $providers = $Context.Providers
        $authorizationExpires = if ($Mode -ceq 'Live') {
            $sessionId = Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
                -RelayContext $Context
            Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                -RelayContext $Context -Lane $Policy.WriteLane -RuntimeAssertion $RuntimeAssertion
        }
        else { [DateTimeOffset]::MaxValue }
        $deadline = (Get-CddsiRealtimeRelayForegroundNowInternal `
                -Context $Context -Mode $Mode).AddSeconds($MaxWaitSeconds)
        if ($authorizationExpires -lt $deadline) { $deadline = $authorizationExpires }

        $root = Invoke-CddsiRealtimeRelayForegroundStateInternal `
            -Context $Context -Mode $Mode -Operation ValidateRoot
        if ($null -eq $root -or
            -not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $root `
                -Expected @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created')) -or
            $root.Valid -isnot [bool] -or $root.OwnerMarked -isnot [bool] -or
            $root.AclProtected -isnot [bool] -or $root.NoReparse -isnot [bool] -or
            $root.Created -isnot [bool] -or -not $root.Valid -or
            -not $root.OwnerMarked -or -not $root.AclProtected -or -not $root.NoReparse) {
            throw 'FOREGROUND_STATE_ROOT_INVALID'
        }
        if ($Mode -ceq 'Live') {
            $lifecycleLockHandle = Invoke-CddsiRealtimeRelayForegroundStateInternal `
                -Context $Context -Mode $Mode -Operation AcquireLifecycleLock
        }
        $lockHandle = Invoke-CddsiRealtimeRelayForegroundStateInternal `
            -Context $Context -Mode $Mode -Operation AcquireLock
        if ($null -ne $lifecycleLockHandle) {
            $lifecycleLockHandle.Dispose()
            $lifecycleLockHandle = $null
        }
        if ($null -eq $lockHandle) { throw 'FOREGROUND_LOCK_FAILED' }
        $state = Invoke-CddsiRealtimeRelayForegroundStateInternal `
            -Context $Context -Mode $Mode -Operation Load -Lane $Policy.ReadLane
        if ($null -eq $state) {
            $state = New-CddsiRealtimeRelayInitialStateInternal -Lane $Policy.ReadLane
        }
        if (-not (Test-CddsiRealtimeRelayStateInternal -State $state -Lane $Policy.ReadLane)) {
            throw 'FOREGROUND_STATE_INVALID'
        }
        $effectiveAfter = if ([long]$state.LastAckedSequence -eq 0 -and $AfterSequence -gt 0) {
            $AfterSequence
        }
        else { [long]$state.LastAckedSequence }
        $disconnectFailures = 0

        while ((Get-CddsiRealtimeRelayForegroundNowInternal -Context $Context -Mode $Mode) -lt $deadline) {
            $receive = if ($Mode -ceq 'Live') {
                try {
                    Invoke-CddsiRealtimeRelayLiveTransportReceiveInternal `
                        -TransportProvider $providers.Transport `
                        -CredentialProvider $providers.Credential `
                        -ClockProvider $providers.Clock -Lane $Policy.ReadLane `
                        -After $effectiveAfter -MaxMessages 1 `
                        -AuthorizationExpiresAtUtc $deadline
                }
                finally {
                    $networkCount = Get-CddsiRealtimeRelayOperatorNetworkRequestCountBySessionIdInternal `
                        -SessionId $sessionId
                }
            }
            else {
                if ($providers.Transport.Receive -isnot [scriptblock]) {
                    throw 'FOREGROUND_PROVIDER_MISSING'
                }
                & $providers.Transport.Receive $Policy.ReadLane $effectiveAfter 1 $deadline
            }
            if ($null -eq $receive -or
                (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $receive `
                        -Expected @('Status', 'Messages')) -and
                    -not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $receive `
                        -Expected @('Status', 'Messages', 'Code'))) -or
                $receive.Status -isnot [string] -or $receive.Messages -isnot [Array] -or
                @('Connected', 'Disconnected', 'Stopped') -cnotcontains $receive.Status) {
                throw 'FOREGROUND_TRANSPORT_INVALID'
            }
            if ($receive.Status -ceq 'Disconnected') {
                $disconnectFailures++
                $reconnectCount++
                if ($disconnectFailures -ge $MaxReconnectAttempts) {
                    throw 'FOREGROUND_RECONNECT_EXHAUSTED'
                }
                $delay = [int][Math]::Min(30000, [Math]::Pow(2, $disconnectFailures - 1) * 1000)
                if ($Mode -ceq 'Live') {
                    $jitter = Get-CddsiRealtimeRelayLiveJitterMillisecondsInternal `
                        -ClockProvider $providers.Clock -Maximum 250
                    Invoke-CddsiRealtimeRelayLiveDelayInternal `
                        -ClockProvider $providers.Clock -Milliseconds ($delay + $jitter)
                }
                else {
                    if ($providers.Clock.GetJitterMilliseconds -isnot [scriptblock] -or
                        $providers.Clock.Delay -isnot [scriptblock]) {
                        throw 'FOREGROUND_PROVIDER_MISSING'
                    }
                    $jitter = & $providers.Clock.GetJitterMilliseconds 250
                    if ($jitter -isnot [int] -or $jitter -lt 0 -or $jitter -gt 250) {
                        throw 'FOREGROUND_PROVIDER_MISSING'
                    }
                    & $providers.Clock.Delay ($delay + $jitter)
                }
                continue
            }
            if ($receive.Status -ceq 'Stopped') { break }
            $disconnectFailures = 0
            if (@($receive.Messages).Count -eq 0) {
                if ($null -ne $receive.PSObject.Properties['Code'] -and
                    $receive.Code -ceq 'REALTIME_WEBSOCKET_IDLE') { continue }
                break
            }
            if (@($receive.Messages).Count -ne 1 -or $receive.Messages[0] -isnot [string]) {
                throw 'FOREGROUND_TRANSPORT_INVALID'
            }
            $now = Get-CddsiRealtimeRelayForegroundNowInternal -Context $Context -Mode $Mode
            $validation = Test-CddsiRealtimeRelayNotificationInternal `
                -RawMessage ([string]$receive.Messages[0]) -NowUtc $now
            if (-not $validation.Valid -and @(
                    'CREATED_AT_OUTSIDE_WINDOW', 'MESSAGE_EXPIRED'
                ) -ccontains $validation.Code) {
                $storedReplay = Test-CddsiRealtimeRelayNotificationInternal `
                    -RawMessage ([string]$receive.Messages[0]) -NowUtc $now `
                    -ValidationMode StoredConsumedReplay
                if ($storedReplay.Valid) {
                    $storedMatches = @($state.ProcessedMessages | Where-Object {
                            [long]$_.Sequence -eq [long]$storedReplay.Message.Sequence -and
                            $_.MessageId -ceq $storedReplay.Message.MessageId -and
                            $_.MessageSha256 -ceq $storedReplay.MessageSha256 -and
                            $_.PayloadSha256 -ceq $storedReplay.Message.PayloadSha256
                        })
                    if ($storedMatches.Count -eq 1) {
                        $validation = $storedReplay
                    }
                }
            }
            if (-not $validation.Valid) { throw 'FOREGROUND_NOTIFICATION_INVALID' }
            $message = $validation.Message
            if ($message.Lane -cne $Policy.ReadLane) {
                throw 'FOREGROUND_WRONG_DIRECTION'
            }
            if ($null -ne $Pointer -and (
                    $message.MessageId -cne $Pointer.MessageId -or
                    $message.PayloadSha256 -cne $Pointer.PayloadSha256 -or
                    $message.Commit -cne $Pointer.Commit
                )) {
                throw 'FOREGROUND_POINTER_MISMATCH'
            }
            $observedPointer = [pscustomobject][ordered]@{
                SchemaVersion = $script:CddsiRealtimePublishPointerSchema
                Lane = $message.Lane
                MessageId = $message.MessageId
                PayloadSha256 = $message.PayloadSha256
                Commit = $message.Commit
            }
            $matches = @($state.ProcessedMessages | Where-Object {
                    [long]$_.Sequence -eq [long]$message.Sequence
                })
            $messageIdMatches = @($state.ProcessedMessages | Where-Object {
                    $_.MessageId -ceq $message.MessageId
                })
            if ($messageIdMatches.Count -gt 1 -or
                ($messageIdMatches.Count -eq 1 -and
                    [long]$messageIdMatches[0].Sequence -ne [long]$message.Sequence)) {
                throw 'FOREGROUND_MESSAGE_ID_REPLAY'
            }
            $idempotent = $false
            if ($matches.Count -eq 1) {
                if ($matches[0].MessageId -cne $message.MessageId -or
                    $matches[0].MessageSha256 -cne $validation.MessageSha256 -or
                    $matches[0].PayloadSha256 -cne $message.PayloadSha256) {
                    throw 'FOREGROUND_STATE_INVALID'
                }
                $idempotent = $true
            }
            elseif ($matches.Count -ne 0) { throw 'FOREGROUND_STATE_INVALID' }
            else {
                $expectedSequence = if ([long]$state.LastConsumedSequence -eq 0 -and
                    $AfterSequence -gt 0) { $AfterSequence + 1 }
                else { [long]$state.LastConsumedSequence + 1 }
                if ([long]$message.Sequence -ne $expectedSequence) {
                    throw 'FOREGROUND_SEQUENCE_GAP'
                }
                if ([long]$state.LastConsumedSequence -gt 0 -and
                    $message.PreviousSha256 -cne $state.LastMessageSha256) {
                    throw 'FOREGROUND_PREVIOUS_HASH_MISMATCH'
                }
                if ([long]$state.LastConsumedSequence -eq 0 -and $AfterSequence -eq 0 -and
                    $null -ne $message.PreviousSha256) {
                    throw 'FOREGROUND_PREVIOUS_HASH_MISMATCH'
                }
                $state.ProcessedMessages = @($state.ProcessedMessages) + @(
                    [pscustomobject][ordered]@{
                        MessageId = $message.MessageId; Sequence = [long]$message.Sequence
                        MessageSha256 = $validation.MessageSha256
                        PayloadSha256 = $message.PayloadSha256
                    }
                )
                if (@($state.ProcessedMessages).Count -gt 256) {
                    $state.ProcessedMessages = @($state.ProcessedMessages | Select-Object -Last 256)
                }
                $state.LastConsumedSequence = [long]$message.Sequence
                $state.LastMessageSha256 = $validation.MessageSha256
                $state.Revision = [long]$state.Revision + 1
                try {
                    [void](Invoke-CddsiRealtimeRelayForegroundStateInternal `
                            -Context $Context -Mode $Mode -Operation CommitAtomically -State $state)
                    if ($Mode -ceq 'Live') { $mutationCount++ }
                }
                catch { throw 'FOREGROUND_STATE_COMMIT_FAILED' }
            }
            $ack = [pscustomobject][ordered]@{
                Schema = $script:CddsiRealtimeAckSchema; Lane = $message.Lane
                MessageId = $message.MessageId; Sequence = [long]$message.Sequence
                PayloadSha256 = $message.PayloadSha256; AckStatus = 'CONSUMED'
                AckedAt = $now.ToString(
                    'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
                )
                SenderRole = $Role
            }
            $ackBody = ConvertTo-CddsiRealtimeRelayCanonicalAckInternal -Ack $ack
            $ackResult = if ($Mode -ceq 'Live') {
                try {
                    Invoke-CddsiRealtimeRelayLiveTransportAckInternal `
                        -TransportProvider $providers.Transport `
                        -CredentialProvider $providers.Credential `
                        -ClockProvider $providers.Clock -Body $ackBody `
                        -AuthorizationExpiresAtUtc $deadline
                }
                finally {
                    $networkCount = Get-CddsiRealtimeRelayOperatorNetworkRequestCountBySessionIdInternal `
                        -SessionId $sessionId
                }
            }
            else {
                if ($providers.Transport.Ack -isnot [scriptblock]) {
                    throw 'FOREGROUND_PROVIDER_MISSING'
                }
                & $providers.Transport.Ack $ackBody
            }
            if ($null -eq $ackResult -or
                -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                    -InputObject $ackResult -Expected @('Accepted')) -or
                $ackResult.Accepted -isnot [bool]) { throw 'FOREGROUND_ACK_INVALID' }
            if (-not $ackResult.Accepted) { throw 'FOREGROUND_ACK_REJECTED' }
            $ackCount++
            if ([long]$state.LastAckedSequence -lt [long]$message.Sequence) {
                $state.LastAckedSequence = [long]$message.Sequence
                $state.Revision = [long]$state.Revision + 1
                try {
                    [void](Invoke-CddsiRealtimeRelayForegroundStateInternal `
                            -Context $Context -Mode $Mode -Operation CommitAtomically -State $state)
                    if ($Mode -ceq 'Live') { $mutationCount++ }
                }
                catch { throw 'FOREGROUND_STATE_COMMIT_FAILED' }
            }
            return New-CddsiRealtimeRelayForegroundResultInternal `
                -Action WaitPointer -Role $Role -Status SUCCEEDED `
                -Code $(if ($idempotent) { 'FOREGROUND_POINTER_DUPLICATE' } `
                    else { 'FOREGROUND_POINTER_RECEIVED' }) `
                -RelayCode $null -Mode $Mode -Changed ($Mode -ceq 'Live') `
                -Policy $Policy -Pointer $observedPointer -Sequence ([long]$message.Sequence) `
                -Idempotent $idempotent -AckCount $ackCount -ReconnectCount $reconnectCount `
                -NetworkCount $networkCount -StateMutationCount $mutationCount
        }
        throw 'FOREGROUND_WAIT_TIMEOUT'
    }
    catch {
        $code = [string]$_.Exception.Message
        if (@('REALTIME_PUBLISH_ASSERTION_EXPIRED', 'REALTIME_RUNTIME_ASSERTION_EXPIRED') `
            -ccontains $code) { $code = 'FOREGROUND_WAIT_TIMEOUT' }
        elseif ($script:CddsiRealtimeForegroundCodes -cnotcontains $code) {
            $code = 'FOREGROUND_BLOCKED'
        }
        return New-CddsiRealtimeRelayForegroundResultInternal `
            -Action WaitPointer -Role $Role -Status BLOCKED -Code $code -RelayCode $null `
            -Mode $Mode -Changed ($Mode -ceq 'Live' -and $mutationCount -gt 0) `
            -Policy $Policy -Pointer $Pointer -Sequence $null -Idempotent $false `
            -AckCount $ackCount -ReconnectCount $reconnectCount `
            -NetworkCount $networkCount -StateMutationCount $mutationCount
    }
    finally {
        try {
            if ($Mode -ceq 'Live' -and -not [string]::IsNullOrEmpty($sessionId)) {
                Close-CddsiRealtimeRelayTrustedLiveSessionInternal -TrustedSessionId $sessionId
            }
            elseif ($null -ne $Context.Providers.Transport.PSObject.Properties['Close'] -and
                $Context.Providers.Transport.Close -is [scriptblock]) {
                & $Context.Providers.Transport.Close
            }
        }
        catch { }
        try { if ($null -ne $lifecycleLockHandle) { $lifecycleLockHandle.Dispose() } } catch { }
        try {
            if ($null -ne $lockHandle) {
                if ($Mode -ceq 'Live') { $lockHandle.Dispose() }
                else {
                    [void](Invoke-CddsiRealtimeRelayForegroundStateInternal `
                            -Context $Context -Mode $Mode -Operation ReleaseLock -Handle $lockHandle)
                }
            }
        }
        catch { }
    }
}

function Invoke-CddsiRealtimeRelayForegroundCycle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Status', 'WaitPointer', 'PublishPointer')][string]$Action,
        [Parameter(Mandatory = $true)]
        [ValidateSet('HostCoordinator', 'VmTester')][string]$Role,
        [AllowNull()]$Pointer = $null,
        [AllowNull()]$RelayExecutionContext = $null,
        [AllowNull()]$RuntimeAssertion = $null,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [ValidateRange(0, 9007199254740991L)][long]$AfterSequence = 0,
        [ValidateRange(1, 600)][int]$MaxWaitSeconds = 120,
        [ValidateRange(1, 32)][int]$MaxReconnectAttempts = 5,
        [switch]$AcknowledgeOperatorPlaneLive
    )

    $policy = Get-CddsiRealtimeRelayForegroundPolicyInternal -Role $Role
    try {
        if ($Action -ceq 'PublishPointer' -or $null -ne $Pointer) {
            if (-not (Test-CddsiRealtimeRelayForegroundPointerInternal -Pointer $Pointer)) {
                throw 'FOREGROUND_POINTER_INVALID'
            }
            $lane = if ($Action -ceq 'WaitPointer') { $policy.ReadLane } else { $policy.WriteLane }
            if ($Pointer.Lane -cne $lane) { throw 'FOREGROUND_WRONG_DIRECTION' }
        }
        if ($Mode -ceq 'Live' -and -not $AcknowledgeOperatorPlaneLive) {
            throw 'FOREGROUND_CONFIRMATION_REQUIRED'
        }
        if ($null -eq $RelayExecutionContext -or $null -eq $RuntimeAssertion) {
            if ($Mode -ceq 'Live') { throw 'FOREGROUND_CONTEXT_REQUIRED' }
            return New-CddsiRealtimeRelayForegroundResultInternal `
                -Action $Action -Role $Role `
                -Status $(if ($Action -ceq 'Status') { 'READY' } else { 'PLANNED' }) `
                -Code $(if ($Action -ceq 'Status') { 'FOREGROUND_STATUS_READY' } `
                    else { 'FOREGROUND_PLANNED' }) `
                -RelayCode $null -Mode $Mode -Changed $false -Policy $policy `
                -Pointer $Pointer -Sequence $null -Idempotent $false -AckCount 0 `
                -ReconnectCount 0 -NetworkCount 0 -StateMutationCount 0
        }
        Assert-CddsiRealtimeRelayForegroundContextInternal `
            -Context $RelayExecutionContext -RuntimeAssertion $RuntimeAssertion `
            -Policy $policy -Mode $Mode
        if ($Action -ceq 'Status') {
            return New-CddsiRealtimeRelayForegroundResultInternal `
                -Action $Action -Role $Role -Status READY -Code FOREGROUND_STATUS_READY `
                -RelayCode $null -Mode $Mode -Changed $false -Policy $policy `
                -Pointer $null -Sequence $null -Idempotent $false -AckCount 0 `
                -ReconnectCount 0 -NetworkCount 0 -StateMutationCount 0
        }
        if ($Action -ceq 'WaitPointer') {
            return Invoke-CddsiRealtimeRelayForegroundWaitInternal `
                -Context $RelayExecutionContext -RuntimeAssertion $RuntimeAssertion `
                -Pointer $Pointer -Policy $policy -Role $Role -Mode $Mode `
                -AfterSequence $AfterSequence -MaxWaitSeconds $MaxWaitSeconds `
                -MaxReconnectAttempts $MaxReconnectAttempts
        }
        $published = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $RelayExecutionContext -PublishPointer $Pointer `
            -RuntimeAssertion $RuntimeAssertion -Mode $Mode `
            -AcknowledgeOperatorPlaneLive:$AcknowledgeOperatorPlaneLive
        return New-CddsiRealtimeRelayForegroundResultInternal `
            -Action PublishPointer -Role $Role -Status $published.Status `
            -Code $(if ($published.Status -ceq 'SUCCEEDED') { 'FOREGROUND_POINTER_PUBLISHED' } `
                else { 'FOREGROUND_BLOCKED' }) `
            -RelayCode $published.Code -Mode $Mode -Changed ([bool]$published.Changed) `
            -Policy $policy -Pointer $Pointer -Sequence $published.Sequence `
            -Idempotent ([bool]$published.Idempotent) -AckCount 0 -ReconnectCount 0 `
            -NetworkCount ([long]$published.OperatorRelayNetworkRequestCount) `
            -StateMutationCount ([long]$published.OperatorLocalStateMutationCount)
    }
    catch {
        $code = [string]$_.Exception.Message
        if ($script:CddsiRealtimeForegroundCodes -cnotcontains $code) { $code = 'FOREGROUND_BLOCKED' }
        return New-CddsiRealtimeRelayForegroundResultInternal `
            -Action $Action -Role $Role -Status BLOCKED -Code $code -RelayCode $null `
            -Mode $Mode -Changed $false -Policy $policy -Pointer $Pointer -Sequence $null `
            -Idempotent $false -AckCount 0 -ReconnectCount 0 -NetworkCount 0 `
            -StateMutationCount 0
    }
}

function New-CddsiRealtimeRelayForegroundLiveAssertionInternal {
    param($Context, [string]$Lane, [int]$LifetimeSeconds)

    $now = Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $Context.Providers.Clock
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimePublisherAssertionSchema
        Status = 'AUTHORIZED'; Lane = $Lane; ClientId = $Context.ClientId
        Endpoint = $Context.Endpoint; Environment = $Context.Providers.Credential.Environment
        KeyId = $Context.Providers.Credential.KeyId
        CredentialStorageKind = $Context.Providers.Credential.StorageKind
        CredentialBindingToken = $Context.Providers.Credential.BindingToken
        StateRootBindingToken = $Context.Providers.State.BindingToken
        ClientAdapterSha256 = $Context.ClientAdapterSha256
        IssuedAtUtc = $now.ToString(
            'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
        )
        ExpiresAtUtc = $now.AddSeconds($LifetimeSeconds).ToString(
            'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
        )
    }
}

if ($MyInvocation.InvocationName -cne '.') {
    $policy = Get-CddsiRealtimeRelayForegroundPolicyInternal -Role $Role
    $pointer = $null
    $foregroundResult = $null
    try {
        $pointer = if ($Action -ceq 'Status' -or
            ($Action -ceq 'WaitPointer' -and [string]::IsNullOrEmpty($MessageId) -and
                [string]::IsNullOrEmpty($PayloadSha256) -and [string]::IsNullOrEmpty($Commit))) { $null }
        else {
            [pscustomobject][ordered]@{
                SchemaVersion = $script:CddsiRealtimePublishPointerSchema
                Lane = if ($Action -ceq 'WaitPointer') { $policy.ReadLane } else { $policy.WriteLane }
                MessageId = $MessageId; PayloadSha256 = $PayloadSha256; Commit = $Commit
            }
        }
        $context = $null
        $assertion = $null
        if ($Mode -ceq 'Live') {
            if ($null -eq $Endpoint -or [string]::IsNullOrEmpty($StateRoot) -or
                [string]::IsNullOrEmpty($RunId) -or [string]::IsNullOrEmpty($OwnerSid) -or
                [string]::IsNullOrEmpty($OwnershipTokenSha256) -or
                [string]::IsNullOrEmpty($Environment) -or [string]::IsNullOrEmpty($KeyId)) {
                throw 'FOREGROUND_LIVE_ARGUMENTS_REQUIRED'
            }
            $webSocketEndpoint = ConvertTo-CddsiRealtimeRelayForegroundWebSocketEndpointInternal `
                -Endpoint $Endpoint
            $stateProvider = New-CddsiRealtimeRelayOwnedStateProvider `
                -StateRoot $StateRoot -RunId $RunId -OwnerSid $OwnerSid `
                -OwnershipTokenSha256 $OwnershipTokenSha256
            $credentialProvider = New-CddsiRealtimeRelayDpapiCredentialProvider `
                -StateRoot $StateRoot -RunId $RunId -OwnerSid $OwnerSid `
                -OwnershipTokenSha256 $OwnershipTokenSha256 -ClientId $policy.ClientId `
                -Environment $Environment -KeyId $KeyId
            $context = New-CddsiRealtimeRelayLivePublisher -Endpoint $webSocketEndpoint `
                -ClientId $policy.ClientId -Lane $policy.WriteLane `
                -CredentialProvider $credentialProvider -StateProvider $stateProvider
            $lifetime = if ($Action -ceq 'WaitPointer') { $MaxWaitSeconds } else { 120 }
            $assertion = New-CddsiRealtimeRelayForegroundLiveAssertionInternal `
                -Context $context -Lane $policy.WriteLane -LifetimeSeconds $lifetime
        }
        $foregroundResult = Invoke-CddsiRealtimeRelayForegroundCycle -Action $Action -Role $Role `
            -Pointer $pointer -RelayExecutionContext $context -RuntimeAssertion $assertion `
            -Mode $Mode -AfterSequence $AfterSequence -MaxWaitSeconds $MaxWaitSeconds `
            -MaxReconnectAttempts $MaxReconnectAttempts `
            -AcknowledgeOperatorPlaneLive:$AcknowledgeOperatorPlaneLive
    }
    catch {
        $foregroundResult = New-CddsiRealtimeRelayForegroundResultInternal `
            -Action $Action -Role $Role -Status BLOCKED -Code FOREGROUND_BLOCKED `
            -RelayCode $null -Mode $Mode -Changed $false -Policy $policy `
            -Pointer $pointer -Sequence $null -Idempotent $false -AckCount 0 `
            -ReconnectCount 0 -NetworkCount 0 -StateMutationCount 0
    }
    $foregroundResult | ConvertTo-Json -Compress -Depth 6
    if ($foregroundResult.Status -ceq 'BLOCKED') { exit 1 }
}
