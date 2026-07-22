BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'operator\realtime-relay\realtime-relay-client.ps1')
    . (Join-Path $script:RepoRoot 'operator\realtime-relay\invoke-foreground-cycle.ps1')
    $script:ForegroundNow = [DateTimeOffset]::ParseExact(
        '2030-01-02T03:04:05Z',
        'yyyy-MM-ddTHH:mm:ssZ',
        [Globalization.CultureInfo]::InvariantCulture
    )

    function Copy-CddsiForegroundObject {
        param($Value)
        if ($null -eq $Value) { return $null }
        return ConvertFrom-Json -InputObject (ConvertTo-Json -InputObject $Value -Compress -Depth 8)
    }

    function New-CddsiForegroundPointer {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
            [string]$MessageId = '11111111-1111-4111-8111-111111111111'
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-publish-pointer-v1'
            Lane = $Lane; MessageId = $MessageId
            PayloadSha256 = 'a' * 64; Commit = 'b' * 40
        }
    }

    function New-CddsiForegroundMessage {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
            [long]$Sequence = 1,
            [AllowNull()][string]$PreviousSha256 = $null,
            [string]$MessageId = '11111111-1111-4111-8111-111111111111'
        )
        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        $message = [pscustomobject][ordered]@{
            Schema = 'cddsi-relay-notification-v1'; Lane = $Lane; MessageId = $MessageId
            Sequence = $Sequence
            PreviousSha256 = if ([string]::IsNullOrEmpty($PreviousSha256)) {
                $null
            }
            else { $PreviousSha256 }
            PayloadSha256 = 'a' * 64; RepositoryId = $policy.RepositoryId
            Ref = 'refs/heads/main'; Commit = 'b' * 40
            CreatedAt = $script:ForegroundNow.ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
            Expiry = $script:ForegroundNow.AddMinutes(5).ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
            SenderRole = $policy.SenderRole
        }
        return ConvertTo-CddsiRealtimeRelayCanonicalNotificationInternal -Message $message
    }

    function New-CddsiForegroundHarness {
        param(
            [ValidateSet('HostCoordinator', 'VmTester')][string]$Role,
            [object[]]$ReceivePlans = @(
                [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
            ),
            [object[]]$AckPlans = @(
                [pscustomobject][ordered]@{ Accepted = $true }
            )
        )
        $policy = Get-CddsiRealtimeRelayForegroundPolicyInternal -Role $Role
        $tracker = [pscustomobject][ordered]@{
            Now = $script:ForegroundNow
            ReceivePlans = @($ReceivePlans); ReceiveIndex = 0
            AckPlans = @($AckPlans); AckIndex = 0
            ReceiveLanes = [Collections.ArrayList]::new()
            ReceiveAfter = [Collections.ArrayList]::new()
            AckBodies = [Collections.ArrayList]::new()
            DelayCount = 0; CloseCount = 0; ReleaseCount = 0
            WakeCount = 0; PayloadExecutionCount = 0
            State = $null
            PublisherState = New-CddsiRealtimeRelayPublisherStateInternal -Lane $policy.WriteLane
            PublishBodies = [Collections.ArrayList]::new()
        }
        $validateRoot = {
            return [pscustomobject][ordered]@{
                Valid = $true; OwnerMarked = $true; AclProtected = $true
                NoReparse = $true; Created = $false
            }
        }.GetNewClosure()
        $acquire = { return [pscustomobject]@{ Held = $true } }.GetNewClosure()
        $load = {
            param([string]$Lane)
            if ($Lane -cne $policy.ReadLane) { throw 'SYNTHETIC_WRONG_READ_LANE' }
            if ($null -eq $tracker.State) { return $null }
            return ConvertFrom-Json -InputObject (
                ConvertTo-Json -InputObject $tracker.State -Compress -Depth 8
            )
        }.GetNewClosure()
        $commit = {
            param($State)
            $tracker.State = ConvertFrom-Json -InputObject (
                ConvertTo-Json -InputObject $State -Compress -Depth 8
            )
        }.GetNewClosure()
        $release = { param($Handle) $tracker.ReleaseCount++ }.GetNewClosure()
        $loadPublisher = {
            param([string]$Lane)
            if ($Lane -cne $policy.WriteLane) { throw 'SYNTHETIC_WRONG_WRITE_LANE' }
            return ConvertFrom-Json -InputObject (
                ConvertTo-Json -InputObject $tracker.PublisherState -Compress -Depth 8
            )
        }.GetNewClosure()
        $commitPublisher = {
            param($State)
            $tracker.PublisherState = ConvertFrom-Json -InputObject (
                ConvertTo-Json -InputObject $State -Compress -Depth 8
            )
        }.GetNewClosure()
        $releasePublisher = { param([string]$Lane, $Handle) }.GetNewClosure()
        $receive = {
            param([string]$Lane, [long]$After, [int]$Maximum, [DateTimeOffset]$Deadline)
            [void]$tracker.ReceiveLanes.Add($Lane)
            [void]$tracker.ReceiveAfter.Add($After)
            if ($tracker.ReceiveIndex -ge $tracker.ReceivePlans.Count) {
                return [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
            }
            $result = $tracker.ReceivePlans[$tracker.ReceiveIndex]
            $tracker.ReceiveIndex++
            return $result
        }.GetNewClosure()
        $ack = {
            param([string]$Body)
            [void]$tracker.AckBodies.Add($Body)
            if ($tracker.AckIndex -ge $tracker.AckPlans.Count) {
                return [pscustomobject][ordered]@{ Accepted = $true }
            }
            $result = $tracker.AckPlans[$tracker.AckIndex]
            $tracker.AckIndex++
            if ($result -is [string]) { throw $result }
            return $result
        }.GetNewClosure()
        $publish = {
            param([string]$Lane, [string]$Body)
            [void]$tracker.PublishBodies.Add($Body)
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try {
                $sha = ([BitConverter]::ToString($algorithm.ComputeHash(
                            [Text.UTF8Encoding]::new($false, $true).GetBytes($Body)
                        ))).Replace('-', '').ToLowerInvariant()
            }
            finally { $algorithm.Dispose() }
            return [pscustomobject][ordered]@{
                Accepted = $true; Code = 'PUBLISHED'; MessageSha256 = $sha
            }
        }.GetNewClosure()
        $context = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-publisher-context-v1'
            Mode = 'TestSafe'; ProviderKind = 'Fake'
            Endpoint = '<SYNTHETIC_RELAY_ENDPOINT>'; ClientId = $policy.ClientId
            ClientAdapterSha256 = 'd' * 64
            Providers = [pscustomobject][ordered]@{
                State = [pscustomobject][ordered]@{
                    BindingToken = 'e' * 64; ValidateRoot = $validateRoot
                    AcquireLock = $acquire; Load = $load; CommitAtomically = $commit
                    ReleaseLock = $release; AcquirePublisherLock = { param($Lane) return [pscustomobject]@{ Held = $true } }
                    LoadPublisher = $loadPublisher; CommitPublisher = $commitPublisher
                    ReleasePublisherLock = $releasePublisher
                }
                Transport = [pscustomobject][ordered]@{
                    Receive = $receive; Ack = $ack; Publish = $publish
                    Close = { $tracker.CloseCount++ }.GetNewClosure()
                }
                Clock = [pscustomobject][ordered]@{
                    GetUtcNow = { return $tracker.Now }.GetNewClosure()
                    GetJitterMilliseconds = { param([int]$Maximum) return 0 }
                    Delay = {
                        param([int]$Milliseconds)
                        $tracker.DelayCount++
                        $tracker.Now = $tracker.Now.AddMilliseconds($Milliseconds)
                    }.GetNewClosure()
                    NewMessageId = { return '11111111-1111-4111-8111-111111111111' }
                }
                Credential = [pscustomobject][ordered]@{
                    StorageKind = 'SYNTHETIC'; BindingToken = 'f' * 64
                    TestReady = { return $true }
                }
            }
        }
        $assertion = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-publisher-runtime-assertion-v1'
            Status = 'SYNTHETIC'; Lane = $policy.WriteLane; ClientId = $policy.ClientId
            Endpoint = '<SYNTHETIC_RELAY_ENDPOINT>'; Environment = 'synthetic-v1'
            KeyId = 'synthetic-key-v1'; CredentialStorageKind = 'SYNTHETIC'
            CredentialBindingToken = 'f' * 64; StateRootBindingToken = 'e' * 64
            ClientAdapterSha256 = 'd' * 64
            IssuedAtUtc = '2030-01-02T03:04:04Z'; ExpiresAtUtc = '2030-01-02T03:09:05Z'
        }
        return [pscustomobject]@{
            Context = $context; Assertion = $assertion; Policy = $policy; Tracker = $tracker
        }
    }

    function Assert-CddsiForegroundNoExecution {
        param($Result, $Tracker)
        $Result.OperatorCodexProcessSpawnCount | Should -Be 0
        $Result.FixedWakeEffectCount | Should -Be 0
        $Result.PayloadExecutionCount | Should -Be 0
        $Tracker.WakeCount | Should -Be 0
        $Tracker.PayloadExecutionCount | Should -Be 0
    }
}

Describe 'realtime relay foreground cycle' {
    It 'strictly derives the WebSocket endpoint from an HTTPS receipt endpoint' {
        $derived = ConvertTo-CddsiRealtimeRelayForegroundWebSocketEndpointInternal `
            -Endpoint ([uri]'https://relay.account.workers.dev/')

        $derived.AbsoluteUri | Should -BeExactly 'wss://relay.account.workers.dev/'
        { ConvertTo-CddsiRealtimeRelayForegroundWebSocketEndpointInternal `
                -Endpoint ([uri]'https://relay.account.workers.dev/?unexpected=1') } |
            Should -Throw '*FOREGROUND_ENDPOINT_INVALID*'
        { ConvertTo-CddsiRealtimeRelayForegroundWebSocketEndpointInternal `
                -Endpoint ([uri]'http://relay.account.workers.dev/') } |
            Should -Throw '*FOREGROUND_ENDPOINT_INVALID*'
    }

    It 'reports fixed opposite directions without needing Codex Automation' {
        $hostResult = Invoke-CddsiRealtimeRelayForegroundCycle -Action Status -Role HostCoordinator
        $vm = Invoke-CddsiRealtimeRelayForegroundCycle -Action Status -Role VmTester

        $hostResult.Status | Should -BeExactly 'READY'
        $hostResult.ReadLane | Should -BeExactly 'vm-to-host'
        $hostResult.WriteLane | Should -BeExactly 'host-to-vm'
        $vm.ReadLane | Should -BeExactly 'host-to-vm'
        $vm.WriteLane | Should -BeExactly 'vm-to-host'
        Assert-CddsiForegroundNoExecution -Result $hostResult -Tracker ([pscustomobject]@{
                WakeCount = 0; PayloadExecutionCount = 0
            })
    }

    It 'receives, validates, persists, and ACKs one exact pointer without wake or payload execution' {
        foreach ($role in @('HostCoordinator', 'VmTester')) {
            $policy = Get-CddsiRealtimeRelayForegroundPolicyInternal -Role $role
            $pointer = New-CddsiForegroundPointer -Lane $policy.ReadLane
            $message = New-CddsiForegroundMessage -Lane $policy.ReadLane
            (Test-CddsiRealtimeRelayNotificationInternal `
                    -RawMessage $message -NowUtc $script:ForegroundNow).Code |
                Should -BeExactly 'VALID'
            $harness = New-CddsiForegroundHarness -Role $role -ReceivePlans @(
                [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($message) }
            )

            $result = Invoke-CddsiRealtimeRelayForegroundCycle `
                -Action WaitPointer -Role $role -Pointer $pointer `
                -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

            $result.Code | Should -BeExactly 'FOREGROUND_POINTER_RECEIVED'
            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.AckCount | Should -Be 1
            $harness.Tracker.ReceiveLanes[0] | Should -BeExactly $policy.ReadLane
            $harness.Tracker.AckBodies.Count | Should -Be 1
            $harness.Tracker.State.LastAckedSequence | Should -Be 1
            Assert-CddsiForegroundNoExecution -Result $result -Tracker $harness.Tracker
        }
    }

    It 'waits for and returns the next valid role-lane pointer without knowing its id first' {
        $message = New-CddsiForegroundMessage -Lane host-to-vm `
            -MessageId '22222222-2222-4222-8222-222222222222'
        (Test-CddsiRealtimeRelayNotificationInternal `
                -RawMessage $message -NowUtc $script:ForegroundNow).Code |
            Should -BeExactly 'VALID'
        $harness = New-CddsiForegroundHarness -Role VmTester -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($message) }
        )

        $result = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role VmTester -Pointer $null `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $result.Code | Should -BeExactly 'FOREGROUND_POINTER_RECEIVED'
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.MessageId | Should -BeExactly '22222222-2222-4222-8222-222222222222'
        $result.PayloadSha256 | Should -BeExactly ('a' * 64)
        $result.Commit | Should -BeExactly ('b' * 40)
        $result.ReadLane | Should -BeExactly 'host-to-vm'
        Assert-CddsiForegroundNoExecution -Result $result -Tracker $harness.Tracker
    }

    It 'reconnects from the requested baseline and accepts only the exact next pointer' {
        $pointer = New-CddsiForegroundPointer -Lane host-to-vm
        $message = New-CddsiForegroundMessage -Lane host-to-vm -Sequence 5 `
            -PreviousSha256 ('9' * 64)
        $harness = New-CddsiForegroundHarness -Role VmTester -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Disconnected'; Messages = @(); Code = 'TEST_DROP' },
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($message) }
        )

        $result = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role VmTester -Pointer $pointer -AfterSequence 4 `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $result.Code | Should -BeExactly 'FOREGROUND_POINTER_RECEIVED'
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Sequence | Should -Be 5
        $result.ReconnectCount | Should -Be 1
        @($harness.Tracker.ReceiveAfter) | Should -Be @(4, 4)
        $harness.Tracker.State.LastAckedSequence | Should -Be 5
        Assert-CddsiForegroundNoExecution -Result $result -Tracker $harness.Tracker
    }

    It 're-ACKs an exact atomically stored delivery after ACK loss even when it has expired' {
        $pointer = New-CddsiForegroundPointer -Lane host-to-vm
        $message = New-CddsiForegroundMessage -Lane host-to-vm
        $harness = New-CddsiForegroundHarness -Role VmTester -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($message) },
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($message) }
        ) -AckPlans @(
            'SYNTHETIC_ACK_RESPONSE_LOST',
            [pscustomobject][ordered]@{ Accepted = $true }
        )

        $first = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role VmTester -Pointer $pointer `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $first.Status | Should -BeExactly 'BLOCKED'
        $harness.Tracker.State.LastConsumedSequence | Should -Be 1
        $harness.Tracker.State.LastAckedSequence | Should -Be 0
        $harness.Tracker.AckBodies.Count | Should -Be 1

        $harness.Tracker.Now = $script:ForegroundNow.AddMinutes(5).AddSeconds(1)
        $second = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role VmTester -Pointer $pointer `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $second.Status | Should -BeExactly 'SUCCEEDED'
        $second.Code | Should -BeExactly 'FOREGROUND_POINTER_DUPLICATE'
        $second.Idempotent | Should -BeTrue
        $second.AckCount | Should -Be 1
        $harness.Tracker.State.LastAckedSequence | Should -Be 1
        $harness.Tracker.AckBodies.Count | Should -Be 2
        Assert-CddsiForegroundNoExecution -Result $second -Tracker $harness.Tracker
    }

    It 'fails closed when a consumed MessageId is replayed at another sequence' {
        $pointer = New-CddsiForegroundPointer -Lane host-to-vm
        $firstMessage = New-CddsiForegroundMessage -Lane host-to-vm
        $firstMessageSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $firstMessage
        $replayedMessage = New-CddsiForegroundMessage -Lane host-to-vm -Sequence 2 `
            -PreviousSha256 $firstMessageSha256
        $harness = New-CddsiForegroundHarness -Role VmTester -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($firstMessage) },
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($replayedMessage) }
        )

        $first = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role VmTester -Pointer $pointer `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion
        $second = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role VmTester -Pointer $pointer `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $first.Status | Should -BeExactly 'SUCCEEDED'
        $second.Status | Should -BeExactly 'BLOCKED'
        $second.Code | Should -BeExactly 'FOREGROUND_MESSAGE_ID_REPLAY'
        $harness.Tracker.State.LastConsumedSequence | Should -Be 1
        $harness.Tracker.State.LastAckedSequence | Should -Be 1
        $harness.Tracker.AckBodies.Count | Should -Be 1
        Assert-CddsiForegroundNoExecution -Result $second -Tracker $harness.Tracker
    }

    It 'fails the wrong role lane before any fake transport or state call' {
        $harness = New-CddsiForegroundHarness -Role HostCoordinator
        $wrong = New-CddsiForegroundPointer -Lane host-to-vm

        $result = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action WaitPointer -Role HostCoordinator -Pointer $wrong `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'FOREGROUND_WRONG_DIRECTION'
        $harness.Tracker.ReceiveLanes.Count | Should -Be 0
        Assert-CddsiForegroundNoExecution -Result $result -Tracker $harness.Tracker
    }

    It 'publishes only the role write lane through the existing publisher state machine' {
        $pointer = New-CddsiForegroundPointer -Lane host-to-vm
        $harness = New-CddsiForegroundHarness -Role HostCoordinator

        $result = Invoke-CddsiRealtimeRelayForegroundCycle `
            -Action PublishPointer -Role HostCoordinator -Pointer $pointer `
            -RelayExecutionContext $harness.Context -RuntimeAssertion $harness.Assertion

        $result.RelayCode | Should -BeExactly 'PUBLISHED'
        $result.Code | Should -BeExactly 'FOREGROUND_POINTER_PUBLISHED'
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.RelayCode | Should -BeExactly 'PUBLISHED'
        $harness.Tracker.PublishBodies.Count | Should -Be 1
        $validation = Test-CddsiRealtimeRelayNotificationInternal `
            -RawMessage ([string]$harness.Tracker.PublishBodies[0]) -NowUtc $script:ForegroundNow
        $validation.Valid | Should -BeTrue
        $validation.Message.Lane | Should -BeExactly 'host-to-vm'
        Assert-CddsiForegroundNoExecution -Result $result -Tracker $harness.Tracker
    }

    It 'contains no command execution or fixed wake path in the foreground runner' {
        $source = Get-Content -LiteralPath (
            Join-Path $script:RepoRoot 'operator\realtime-relay\invoke-foreground-cycle.ps1'
        ) -Raw
        $source | Should -Not -Match '(?i)Invoke-Expression|Start-Process'
        $source | Should -Not -Match 'Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal'
        $source | Should -Not -Match '\.Providers\.Wake'
    }

    It 'returns a nonzero CLI exit code for a blocked result without exposing details' {
        $engineName = if ($PSVersionTable.PSEdition -ceq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
        $engine = Join-Path $PSHOME $engineName
        $runner = Join-Path $script:RepoRoot `
            'operator\realtime-relay\invoke-foreground-cycle.ps1'
        $output = & $engine -NoLogo -NoProfile -File $runner `
            -Action PublishPointer -Role HostCoordinator -Mode TestSafe 2>$null
        $exitCode = $LASTEXITCODE
        $result = ConvertFrom-Json -InputObject ($output -join '')

        $exitCode | Should -Be 1
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'FOREGROUND_POINTER_INVALID'
        ($output -join '') | Should -Not -Match '(?i)secret|authorization|exception|stack'
    }

    It 'returns one fixed non-secret JSON result for Live CLI setup failures' {
        $engineName = if ($PSVersionTable.PSEdition -ceq 'Core') { 'pwsh.exe' } else { 'powershell.exe' }
        $engine = Join-Path $PSHOME $engineName
        $runner = Join-Path $script:RepoRoot `
            'operator\realtime-relay\invoke-foreground-cycle.ps1'
        $common = @('-NoLogo', '-NoProfile', '-File', $runner, '-Action', 'Status',
            '-Role', 'HostCoordinator', '-Mode', 'Live', '-AcknowledgeOperatorPlaneLive')
        $cases = @(
            @(),
            @('-Endpoint', 'http://relay.account.workers.dev/', '-StateRoot', $TestDrive,
                '-RunId', '11111111-1111-4111-8111-111111111111',
                '-OwnerSid', 'S-1-5-21-1', '-OwnershipTokenSha256', ('a' * 64),
                '-Environment', 'production-v1', '-KeyId', 'host-2026-07'),
            @('-Endpoint', 'https://relay.account.workers.dev/', '-StateRoot', $TestDrive,
                '-RunId', '11111111-1111-4111-8111-111111111111',
                '-OwnerSid', ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value),
                '-OwnershipTokenSha256', ('a' * 64), '-Environment', 'INVALID!',
                '-KeyId', 'host-2026-07')
        )

        foreach ($case in $cases) {
            $stderrPath = Join-Path $TestDrive ('foreground-cli-{0}.stderr' -f [guid]::NewGuid())
            $arguments = @($common) + @($case)
            $output = & $engine @arguments 2> $stderrPath
            $exitCode = $LASTEXITCODE
            $stderr = if (Test-Path -LiteralPath $stderrPath) {
                Get-Content -LiteralPath $stderrPath -Raw
            }
            else { '' }
            $json = $output -join ''
            $result = ConvertFrom-Json -InputObject $json

            $exitCode | Should -Be 1
            $result.Status | Should -BeExactly 'BLOCKED'
            $result.Code | Should -BeExactly 'FOREGROUND_BLOCKED'
            @($output).Count | Should -Be 1
            $stderr | Should -BeNullOrEmpty
            $json | Should -Not -Match '(?i)secret|authorization|exception|stack|REALTIME_'
        }
    }
}
