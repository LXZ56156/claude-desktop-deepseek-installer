BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\common.ps1')
    . (Join-Path $script:RepoRoot 'lib\vm-test-relay.ps1')
    . (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-git-outbox.ps1')
    . (Join-Path $script:RepoRoot 'operator\realtime-relay\realtime-relay-client.ps1')
    $script:ProtectCurrentUserFunctionText =
    ${function:Protect-CddsiRealtimeRelaySecretCurrentUserInternal}.ToString()
    $script:UnprotectCurrentUserFunctionText =
    ${function:Unprotect-CddsiRealtimeRelaySecretCurrentUserInternal}.ToString()
    $script:RealtimeNow = [DateTimeOffset]::ParseExact(
        '2030-01-02T03:04:05Z',
        'yyyy-MM-ddTHH:mm:ssZ',
        [Globalization.CultureInfo]::InvariantCulture
    )

    function Test-CddsiRealtimePowerShell7OnlyCase {
        if ($PSVersionTable.PSVersion.Major -eq 7) {
            return $true
        }
        $PSVersionTable.PSVersion.Major | Should -Be 5
        return $false
    }

    function New-CddsiRealtimeTestTrackedSocket {
        param(
            [switch]$ThrowOnAbort,
            [switch]$ThrowOnDispose
        )

        $socket = [pscustomobject][ordered]@{
            AbortCount = 0
            DisposeCount = 0
            ThrowOnAbort = [bool]$ThrowOnAbort
            ThrowOnDispose = [bool]$ThrowOnDispose
        }
        $socket | Add-Member -MemberType ScriptMethod -Name Abort -Value {
            $this.AbortCount = [int]$this.AbortCount + 1
            if ($this.ThrowOnAbort) {
                throw 'SYNTHETIC_SOCKET_ABORT_FAILURE_WITHOUT_DETAILS'
            }
        }
        $socket | Add-Member -MemberType ScriptMethod -Name Dispose -Value {
            $this.DisposeCount = [int]$this.DisposeCount + 1
            if ($this.ThrowOnDispose) {
                throw 'SYNTHETIC_SOCKET_DISPOSE_FAILURE_WITHOUT_DETAILS'
            }
        }
        return $socket
    }

    function Copy-CddsiRealtimeTestObject {
        param($InputObject)

        if ($null -eq $InputObject) {
            return $null
        }
        return ConvertFrom-Json -InputObject (
            ConvertTo-Json -Compress -Depth 8 -InputObject $InputObject
        )
    }

    function New-CddsiRealtimeTestMessage {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [long]$Sequence = 1,
            [AllowNull()][string]$PreviousSha256 = $null,
            [AllowNull()][string]$MessageId = $null,
            [AllowNull()][string]$CreatedAt = $null,
            [AllowNull()][string]$Expiry = $null
        )

        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        if ([string]::IsNullOrEmpty($MessageId)) {
            $MessageId = '00000000-0000-4000-8000-{0}' -f $Sequence.ToString('x12')
        }
        if ([string]::IsNullOrEmpty($CreatedAt)) {
            $CreatedAt = $script:RealtimeNow.ToString(
                'yyyy-MM-ddTHH:mm:ssZ',
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        if ([string]::IsNullOrEmpty($Expiry)) {
            $Expiry = $script:RealtimeNow.AddMinutes(5).ToString(
                'yyyy-MM-ddTHH:mm:ssZ',
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        $message = [pscustomobject][ordered]@{
            Schema = 'cddsi-relay-notification-v1'
            Lane = $Lane
            MessageId = $MessageId
            Sequence = [long]$Sequence
            PreviousSha256 = if ([string]::IsNullOrEmpty($PreviousSha256)) { $null } else { $PreviousSha256 }
            PayloadSha256 = ('a' * 64)
            RepositoryId = $policy.RepositoryId
            Ref = 'refs/heads/main'
            Commit = ('b' * 40)
            CreatedAt = $CreatedAt
            Expiry = $Expiry
            SenderRole = $policy.SenderRole
        }
        return ConvertTo-CddsiRealtimeRelayCanonicalNotificationInternal -Message $message
    }

    function New-CddsiRealtimeTestWakeEvent {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [long]$Sequence = 1,
            [string]$MessageId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
        )

        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        return [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-wake-event-v1'
            Verb = 'CONTROL_REPO_POINTER_AVAILABLE'
            Lane = $Lane
            MessageId = $MessageId
            Sequence = $Sequence
            RepositoryId = $policy.RepositoryId
            Ref = 'refs/heads/main'
            Commit = 'b' * 40
            PayloadSha256 = 'a' * 64
        }
    }

    function New-CddsiRealtimeTestGitOutboxBinding {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [Parameter(Mandatory = $true)][string]$RunnerSha256
        )

        $senderRole = if ($Lane -ceq 'host-to-vm') { 'HostCoordinator' } else { 'VmTester' }
        return [pscustomobject][ordered]@{
            StateRoot = Join-Path $TestDrive ('git-state-' + $Lane)
            ProductRoot = Join-Path $TestDrive 'product'
            OperatorWorkspaceRoot = Join-Path $TestDrive 'operator'
            GitExecutable = Join-Path $TestDrive 'git.exe'
            GitExecutableSha256 = ('1' * 64)
            RunnerSha256 = $RunnerSha256
            RepositoryUri = 'https://example.invalid/control.git'
            RepositoryIdentity = 'synthetic/' + $Lane
            ProtectionEvidence = [pscustomobject][ordered]@{ ReceiptId = 'synthetic-receipt' }
            ProtectionEvidenceSha256 = ('2' * 64)
            ExpectedRepositoryNumericId = if ($Lane -ceq 'host-to-vm') { [long]1301870499 } else { [long]1301870545 }
            ExpectedRepositoryNodeId = 'R_synthetic'
            ExpectedRepositoryVisibility = 'PUBLIC'
            ExpectedProtectionAuthority = 'SYNTHETIC_AUTHORITY'
            ExpectedProtectionPolicySha256 = ('3' * 64)
            ProtectionTrustRoot = Join-Path $TestDrive 'protection-trust'
            ProtectionAuthorityAssertionPath = Join-Path $TestDrive 'protection-trust\assertion.json'
            ExpectedProtectionAuthorityAssertionSha256 = ('4' * 64)
            ExpectedProtectionAuthorityBindingToken = ('5' * 64)
            CredentialProfileId = 'synthetic-profile'
            SshExecutable = $null
            SshExecutableSha256 = $null
            ExpectedSshExecutableSha256 = $null
            DeployKeyPath = $null
            DeployKeySha256 = $null
            ExpectedDeployKeySha256 = $null
            KnownHostsPath = $null
            KnownHostsSha256 = $null
            ExpectedKnownHostsSha256 = $null
            ExpectedGenesisCommit = ('6' * 40)
            RemoteRef = 'refs/heads/main'
            HostToVmRepositoryIdentity = 'synthetic/host-to-vm'
            VmToHostRepositoryIdentity = 'synthetic/vm-to-host'
            ProductRepositoryIdentity = 'synthetic/product'
            AuthenticatedOutbox = $Lane
            AuthenticatedSenderRoles = @($senderRole)
            MaximumRuntimeSeconds = 30
            MaximumGitCommandSeconds = 20
            MaximumOutputBytes = 65536
            MaximumMessageBodyBytes = 65536
            MaximumAgeSeconds = 600
            MaximumClockSkewSeconds = 90
            ProtectionEvidenceMaximumAgeSeconds = 3600
        }
    }

    function New-CddsiRealtimeTestCodexWakeParameters {
        param(
            [Parameter(Mandatory = $true)]$GitOutboxBinding,
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm'
        )

        $sessionId = if ($Lane -ceq 'host-to-vm') {
            'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        }
        else {
            'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
        }
        $codexExecutable = [IO.Path]::GetFullPath(
            (Join-Path $TestDrive ('codex-bin-' + $Lane + '\codex.exe'))
        )
        [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($codexExecutable))
        [IO.File]::WriteAllBytes($codexExecutable, [byte[]]@(0x4d, 0x5a, 0x01, 0x02))
        $workingRoot = [IO.Path]::GetFullPath($GitOutboxBinding.ProductRoot)
        $codexHome = [IO.Path]::GetFullPath((Join-Path $TestDrive ('codex-home-' + $Lane)))
        $syntheticProfileRoot = [IO.Path]::GetFullPath((Join-Path $TestDrive ('profile-' + $Lane)))
        $syntheticAppDataRoot = [IO.Path]::GetFullPath((Join-Path $TestDrive ('local-app-' + $Lane)))
        foreach ($directory in @(
                $workingRoot, $codexHome, $syntheticProfileRoot, $syntheticAppDataRoot,
                [IO.Path]::GetFullPath($GitOutboxBinding.StateRoot)
            )) {
            [void][IO.Directory]::CreateDirectory($directory)
        }
        $tempRoot = [IO.Path]::GetFullPath((Join-Path $GitOutboxBinding.StateRoot (
                    'codex-wake-' + $sessionId
                )))
        [void][IO.Directory]::CreateDirectory($tempRoot)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        Set-CddsiRealtimeRelayProtectedDirectoryAclInternal `
            -StateRoot $tempRoot -OwnerSid $ownerSid
        $tempRootSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $tempRoot
        $marker = Get-CddsiRealtimeRelayCodexTempOwnerMarkerInternal `
            -CodexSessionId $sessionId -CodexTempRootSha256 $tempRootSha256
        [IO.File]::WriteAllText(
            (Join-Path $tempRoot '.cddsi-codex-temp-owner.json'),
            $marker,
            [Text.UTF8Encoding]::new($false)
        )
        return @{
            CodexExecutable = $codexExecutable
            ExpectedCodexExecutableSha256 = Get-CddsiRealtimeRelayFileSha256Internal `
                -Path $codexExecutable
            CodexSessionId = $sessionId
            CodexWorkingRoot = $workingRoot
            CodexHome = $codexHome
            CodexUserProfile = $syntheticProfileRoot
            CodexLocalAppData = $syntheticAppDataRoot
            CodexTempRoot = $tempRoot
            CodexMaximumRuntimeSeconds = 30
        }
    }

    function New-CddsiRealtimeFakeHarness {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [object[]]$ReceivePlans = @([pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }),
            [bool[]]$AckResults = @($true),
            [AllowNull()]$ExistingState = $null,
            [int]$CommitFailures = 0,
            [bool]$CredentialReady = $true,
            [string]$ProviderKind = 'Fake',
            [string]$ContextMode = 'TestSafe',
            [AllowNull()][string]$AssertionClientId = $null,
            [AllowNull()]$RootResult = $null,
            [switch]$ThrowOnClose,
            [switch]$ThrowOnRelease
        )

        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        if ([string]::IsNullOrEmpty($AssertionClientId)) {
            $AssertionClientId = $policy.ReaderClientId
        }
        if ($null -eq $RootResult) {
            $RootResult = [pscustomobject][ordered]@{
                Valid = $true
                OwnerMarked = $true
                AclProtected = $true
                NoReparse = $true
                Created = $false
            }
        }
        $tracker = [pscustomobject][ordered]@{
            State = Copy-CddsiRealtimeTestObject $ExistingState
            ReceivePlans = @($ReceivePlans)
            ReceiveIndex = 0
            ReceiveAfter = [Collections.ArrayList]::new()
            AckResults = @($AckResults)
            AckIndex = 0
            AckBodies = [Collections.ArrayList]::new()
            CommitFailures = $CommitFailures
            CommitCount = 0
            WakeInvocationCount = 0
            WakeEffectCount = 0
            WakeEvents = [Collections.ArrayList]::new()
            SeenWakeIds = @{}
            DelayValues = [Collections.ArrayList]::new()
            LockReleasedCount = 0
            TransportCloseCount = 0
        }
        $validateRoot = { return $RootResult }.GetNewClosure()
        $acquireLock = { return [pscustomobject]@{ Held = $true } }.GetNewClosure()
        $load = {
            param([string]$RequestedLane)
            if ($RequestedLane -cne $Lane) {
                throw 'SYNTHETIC_LANE_MISMATCH'
            }
            if ($null -eq $tracker.State) {
                return $null
            }
            return ConvertFrom-Json -InputObject (
                ConvertTo-Json -Compress -Depth 8 -InputObject $tracker.State
            )
        }.GetNewClosure()
        $commit = {
            param($State)
            $tracker.CommitCount++
            if ($tracker.CommitFailures -gt 0) {
                $tracker.CommitFailures--
                throw 'REALTIME_STATE_ATOMIC_WRITE_FAILED'
            }
            $tracker.State = ConvertFrom-Json -InputObject (
                ConvertTo-Json -Compress -Depth 8 -InputObject $State
            )
        }.GetNewClosure()
        $release = {
            param($Handle)
            $tracker.LockReleasedCount++
            if ($ThrowOnRelease) {
                throw ('F' * 64)
            }
        }.GetNewClosure()
        $receive = {
            param([string]$RequestedLane, [long]$After, [int]$Maximum)
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
            $accepted = $true
            if ($tracker.AckIndex -lt $tracker.AckResults.Count) {
                $accepted = [bool]$tracker.AckResults[$tracker.AckIndex]
            }
            $tracker.AckIndex++
            return [pscustomobject][ordered]@{ Accepted = $accepted }
        }.GetNewClosure()
        $close = {
            $tracker.TransportCloseCount++
            if ($ThrowOnClose) {
                throw ('E' * 64)
            }
        }.GetNewClosure()
        $wake = {
            param($Event)
            $tracker.WakeInvocationCount++
            [void]$tracker.WakeEvents.Add((ConvertFrom-Json -InputObject (
                        ConvertTo-Json -Compress -Depth 8 -InputObject $Event
                    )))
            if (-not $tracker.SeenWakeIds.ContainsKey($Event.MessageId)) {
                $tracker.SeenWakeIds[$Event.MessageId] = $true
                $tracker.WakeEffectCount++
            }
            return [pscustomobject][ordered]@{
                FixedEntryInvoked = $true
                PreviouslyInvoked = $false
                Consumed = $true
                RepositoryIdentityVerified = $true
                PayloadSha256Verified = $true
                GitInvocationCount = 0L
                OperatorGitTransportCount = 0L
                OperatorLocalStateMutationCount = 0L
                OperatorCodexProcessSpawnCount = 0L
                FixedWakeEffectCount = 0L
            }
        }.GetNewClosure()
        $fixedNow = $script:RealtimeNow
        $context = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-context-v1'
            Mode = $ContextMode
            ProviderKind = $ProviderKind
            Endpoint = '<SYNTHETIC_RELAY_ENDPOINT>'
            ClientId = $AssertionClientId
            Providers = [pscustomobject][ordered]@{
                State = [pscustomobject][ordered]@{
                    BindingToken = ('c' * 64)
                    ValidateRoot = $validateRoot
                    AcquireLock = $acquireLock
                    Load = $load
                    CommitAtomically = $commit
                    ReleaseLock = $release
                }
                Transport = [pscustomobject][ordered]@{
                    Receive = $receive
                    Ack = $ack
                    Close = $close
                }
                Wake = [pscustomobject][ordered]@{
                    AdapterId = 'cddsi-fast-lane-fixed-resume-v1'
                    AdapterSha256 = ('d' * 64)
                    InvokeFixed = $wake
                }
                Clock = [pscustomobject][ordered]@{
                    GetUtcNow = { return $fixedNow }.GetNewClosure()
                    GetJitterMilliseconds = { param([int]$Maximum) return [int]17 }.GetNewClosure()
                    Delay = { param([int]$Milliseconds) [void]$tracker.DelayValues.Add($Milliseconds) }.GetNewClosure()
                }
                Credential = [pscustomobject][ordered]@{
                    StorageKind = 'SYNTHETIC'
                    BindingToken = ('e' * 64)
                    TestReady = { return [bool]$CredentialReady }.GetNewClosure()
                }
            }
        }
        $assertion = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-runtime-assertion-v1'
            Status = 'SYNTHETIC'
            Lane = $Lane
            ClientId = $AssertionClientId
        }
        return [pscustomobject][ordered]@{
            Context = $context
            Assertion = $assertion
            Tracker = $tracker
        }
    }

    function Assert-CddsiRealtimeZeroMetrics {
        param($Result)

        foreach ($property in @(
                'ProductLiveAttemptCount', 'RealRegistryAccessCount', 'ProductNetworkRequestCount',
                'OperatorRelayNetworkRequestCount', 'RealNetworkAccessCount',
                'RealCredentialManagerAccessCount', 'ProductProcessSpawnCount',
                'OperatorGitInvocationCount', 'OperatorGitTransportCount',
                'OperatorLocalStateMutationCount', 'OperatorCodexProcessSpawnCount',
                'FixedWakeEffectCount', 'OutsideOwnedStateWriteCount',
                'UnexpectedLedgerEntryCount', 'MutationSpyCount'
            )) {
            $Result.$property | Should -Be 0
        }
    }

    function New-CddsiRealtimeTestPublishPointer {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [string]$MessageId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc',
            [string]$PayloadSha256 = ('a' * 64),
            [string]$Commit = ('b' * 40)
        )

        return [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-publish-pointer-v1'
            Lane = $Lane
            MessageId = $MessageId
            PayloadSha256 = $PayloadSha256
            Commit = $Commit
        }
    }

    function New-CddsiRealtimeFakePublisherHarness {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [string[]]$ResponseCodes = @('PUBLISHED'),
            [int]$CommitFailures = 0,
            [AllowNull()][string]$ClientId = $null
        )

        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        if ([string]::IsNullOrEmpty($ClientId)) {
            $ClientId = $policy.WriterClientId
        }
        $tracker = [pscustomobject][ordered]@{
            State = New-CddsiRealtimeRelayPublisherStateInternal -Lane $Lane
            Now = $script:RealtimeNow
            StateOperationCount = 0
            CredentialReadyCount = 0
            NetworkCount = 0
            CommitFailures = $CommitFailures
            CommitCount = 0
            ReleaseCount = 0
            MessageIdCount = 0
            ResponseIndex = 0
            ResponseCodes = @($ResponseCodes)
            Bodies = [Collections.ArrayList]::new()
        }
        $validateRoot = {
            $tracker.StateOperationCount++
            return [pscustomobject][ordered]@{
                Valid = $true
                OwnerMarked = $true
                AclProtected = $true
                NoReparse = $true
                Created = $false
            }
        }.GetNewClosure()
        $acquire = {
            param([string]$RequestedLane)
            $tracker.StateOperationCount++
            if ($RequestedLane -cne $Lane) { throw 'SYNTHETIC_LANE_MISMATCH' }
            return [pscustomobject]@{ Held = $true }
        }.GetNewClosure()
        $load = {
            param([string]$RequestedLane)
            $tracker.StateOperationCount++
            if ($RequestedLane -cne $Lane) { throw 'SYNTHETIC_LANE_MISMATCH' }
            return ConvertFrom-Json -InputObject (
                ConvertTo-Json -Compress -Depth 8 -InputObject $tracker.State
            )
        }.GetNewClosure()
        $commit = {
            param($State)
            $tracker.StateOperationCount++
            $tracker.CommitCount++
            if ($tracker.CommitFailures -gt 0) {
                $tracker.CommitFailures--
                throw 'SYNTHETIC_COMMIT_FAILURE_WITHOUT_DETAILS'
            }
            $tracker.State = ConvertFrom-Json -InputObject (
                ConvertTo-Json -Compress -Depth 8 -InputObject $State
            )
        }.GetNewClosure()
        $release = {
            param([string]$RequestedLane, $Handle)
            $tracker.ReleaseCount++
            if ($RequestedLane -cne $Lane) { throw 'SYNTHETIC_LANE_MISMATCH' }
        }.GetNewClosure()
        $publish = {
            param([string]$RequestedLane, [string]$Body)
            $tracker.NetworkCount++
            [void]$tracker.Bodies.Add($Body)
            if ($RequestedLane -cne $Lane) { throw 'SYNTHETIC_LANE_MISMATCH' }
            $code = if ($tracker.ResponseIndex -lt $tracker.ResponseCodes.Count) {
                [string]$tracker.ResponseCodes[$tracker.ResponseIndex]
            }
            else {
                [string]$tracker.ResponseCodes[-1]
            }
            $tracker.ResponseIndex++
            if ($code -ceq 'REJECTED') {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            $algorithm = [Security.Cryptography.SHA256]::Create()
            try {
                $messageSha256 = ([BitConverter]::ToString($algorithm.ComputeHash(
                            [Text.UTF8Encoding]::new($false, $true).GetBytes($Body)
                        ))).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $algorithm.Dispose()
            }
            return [pscustomobject][ordered]@{
                Accepted = $true
                Code = $code
                MessageSha256 = $messageSha256
            }
        }.GetNewClosure()
        $getMessageId = {
            $tracker.MessageIdCount++
            return 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
        }.GetNewClosure()
        $testReady = {
            $tracker.CredentialReadyCount++
            return $true
        }.GetNewClosure()
        $clientAdapterSha256 = 'd' * 64
        $stateBinding = 'e' * 64
        $credentialBinding = 'f' * 64
        $context = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-publisher-context-v1'
            Mode = 'TestSafe'
            ProviderKind = 'Fake'
            Endpoint = '<SYNTHETIC_RELAY_ENDPOINT>'
            ClientId = $ClientId
            ClientAdapterSha256 = $clientAdapterSha256
            Providers = [pscustomobject][ordered]@{
                State = [pscustomobject][ordered]@{
                    BindingToken = $stateBinding
                    ValidateRoot = $validateRoot
                    AcquirePublisherLock = $acquire
                    LoadPublisher = $load
                    CommitPublisher = $commit
                    ReleasePublisherLock = $release
                }
                Transport = [pscustomobject][ordered]@{ Publish = $publish }
                Clock = [pscustomobject][ordered]@{
                    GetUtcNow = { return $tracker.Now }.GetNewClosure()
                    NewMessageId = $getMessageId
                }
                Credential = [pscustomobject][ordered]@{
                    StorageKind = 'SYNTHETIC'
                    BindingToken = $credentialBinding
                    TestReady = $testReady
                }
            }
        }
        $assertion = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-publisher-runtime-assertion-v1'
            Status = 'SYNTHETIC'
            Lane = $Lane
            ClientId = $policy.WriterClientId
            Endpoint = '<SYNTHETIC_RELAY_ENDPOINT>'
            Environment = 'synthetic-v1'
            KeyId = 'synthetic-key-v1'
            CredentialStorageKind = 'SYNTHETIC'
            CredentialBindingToken = $credentialBinding
            StateRootBindingToken = $stateBinding
            ClientAdapterSha256 = $clientAdapterSha256
            IssuedAtUtc = $script:RealtimeNow.AddSeconds(-1).ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
            ExpiresAtUtc = $script:RealtimeNow.AddMinutes(5).ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
        }
        return [pscustomobject][ordered]@{
            Context = $context
            Assertion = $assertion
            Pointer = New-CddsiRealtimeTestPublishPointer -Lane $Lane
            Tracker = $tracker
        }
    }

    function New-CddsiRealtimeCleanupTestContract {
        param(
            [Parameter(Mandatory = $true)]$StateProvider,
            [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
            [ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId =
            'host-coordinator-v1'
        )

        $clientAdapterSha256 = if ($null -ne $StateProvider.PSObject.Properties['ClientAdapterSha256']) {
            [string]$StateProvider.ClientAdapterSha256
        }
        else {
            'd' * 64
        }
        $bindingToken = [string]$StateProvider.BindingToken
        $context = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-context-v1'
            Mode = $Mode
            ProviderKind = if ($Mode -ceq 'Live') { 'Live' } else { 'Fake' }
            Endpoint = if ($Mode -ceq 'Live') {
                'wss://relay.synthetic.workers.dev/'
            }
            else {
                '<SYNTHETIC_RELAY_ENDPOINT>'
            }
            ClientId = $ClientId
            ClientAdapterSha256 = $clientAdapterSha256
            Providers = [pscustomobject][ordered]@{
                State = $StateProvider
                Transport = [pscustomobject][ordered]@{ Kind = 'UNUSED' }
                Wake = [pscustomobject][ordered]@{ Kind = 'UNUSED' }
                Clock = [pscustomobject][ordered]@{ Kind = 'UNUSED' }
                Credential = [pscustomobject][ordered]@{ Kind = 'UNUSED' }
            }
        }
        $issued = if ($Mode -ceq 'Live') {
            [DateTimeOffset]::UtcNow.AddSeconds(-1)
        }
        else {
            $script:RealtimeNow.AddSeconds(-1)
        }
        $assertion = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-cleanup-runtime-assertion-v1'
            Status = if ($Mode -ceq 'Live') { 'AUTHORIZED' } else { 'SYNTHETIC' }
            Action = 'REMOVE_OWNED_RELAY_STATE'
            Mode = $Mode
            ClientId = $ClientId
            StateRootBindingToken = $bindingToken
            ClientAdapterSha256 = $clientAdapterSha256
            IssuedAtUtc = $issued.ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
            ExpiresAtUtc = $issued.AddSeconds(60).ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
        }
        return [pscustomobject][ordered]@{
            Context = $context
            Assertion = $assertion
        }
    }

    function New-CddsiRealtimeTestLiveHarness {
        param(
            [ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane = 'host-to-vm',
            [DateTimeOffset]$IssuedAtUtc = $script:RealtimeNow.AddSeconds(-1),
            [DateTimeOffset]$ExpiresAtUtc = $script:RealtimeNow.AddSeconds(60),
            [AllowNull()][string]$RunId = $null
        )

        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        if ([string]::IsNullOrEmpty($RunId)) {
            $RunId = if ($Lane -ceq 'host-to-vm') {
                '44444444-4444-4444-8444-444444444444'
            }
            else {
                '55555555-5555-4555-8555-555555555555'
            }
        }
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $stateRoot = [IO.Path]::GetFullPath(
            (Join-Path $TestDrive ('cddsi-realtime-relay-' + $RunId))
        )
        $ownershipToken = '7' * 64
        $stateBinding = Get-CddsiRealtimeRelayStateBindingTokenInternal `
            -StateRoot $stateRoot -OwnerSid $ownerSid `
            -OwnershipTokenSha256 $ownershipToken
        $clientAdapterSha256 = Get-CddsiRealtimeRelayClientAdapterSha256Internal
        $stateProvider = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-owned-state-provider-v2'
            ProviderKind = 'OWNED_STATE'
            StateRoot = $stateRoot
            RunId = $RunId
            OwnerSid = $ownerSid
            OwnershipTokenSha256 = $ownershipToken
            BindingToken = $stateBinding
            ClientAdapterSha256 = $clientAdapterSha256
        }
        $environment = 'production-v1'
        $keyId = if ($policy.ReaderClientId -ceq 'vm-tester-v1') {
            'vm-2026-07'
        }
        else {
            'host-2026-07'
        }
        $credentialBlobSha256 = '8' * 64
        $credentialBinding = Get-CddsiRealtimeRelayCredentialBindingTokenInternal `
            -ClientId $policy.ReaderClientId -Environment $environment -KeyId $keyId `
            -StateRootBindingToken $stateBinding `
            -CredentialBlobSha256 $credentialBlobSha256 `
            -ClientAdapterSha256 $clientAdapterSha256
        $credentialProvider = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-credential-provider-v2'
            StorageKind = 'DPAPI_CURRENT_USER'
            ClientId = $policy.ReaderClientId
            Environment = $environment
            KeyId = $keyId
            CredentialFileName = '.relay-credential.dpapi.json'
            StateRoot = $stateRoot
            RunId = $RunId
            OwnerSid = $ownerSid
            OwnershipTokenSha256 = $ownershipToken
            StateRootBindingToken = $stateBinding
            CredentialBlobSha256 = $credentialBlobSha256
            BindingToken = $credentialBinding
            ClientAdapterSha256 = $clientAdapterSha256
        }
        $runnerSha256 = Get-CddsiRealtimeRelayFileSha256Internal `
            -Path (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-git-outbox.ps1')
        $gitBinding = New-CddsiRealtimeTestGitOutboxBinding -Lane $Lane `
            -RunnerSha256 $runnerSha256
        $gitBindingSha256 = Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal `
            -Binding $gitBinding
        $codexParameters = New-CddsiRealtimeTestCodexWakeParameters `
            -GitOutboxBinding $gitBinding -Lane $Lane
        $wakeProvider = New-CddsiRealtimeRelayFixedGitOutboxWakeProvider -Lane $Lane `
            -ClientId $policy.ReaderClientId -GitOutboxBinding $gitBinding `
            -ExpectedBindingSha256 $gitBindingSha256 `
            -ExpectedAdapterSha256 $clientAdapterSha256 `
            -ExpectedGitOutboxRunnerSha256 $runnerSha256 @codexParameters
        $endpoint = [uri]'wss://relay.synthetic.workers.dev/'
        $context = New-CddsiRealtimeRelayLiveProvider -Endpoint $endpoint `
            -ClientId $policy.ReaderClientId -Lane $Lane `
            -CredentialProvider $credentialProvider -FixedWakeProvider $wakeProvider `
            -StateProvider $stateProvider
        $assertion = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-runtime-assertion-v1'
            Status = 'AUTHORIZED'
            Lane = $Lane
            ClientId = $policy.ReaderClientId
            Endpoint = $endpoint.AbsoluteUri
            Environment = $environment
            KeyId = $keyId
            CredentialStorageKind = 'DPAPI_CURRENT_USER'
            CredentialBindingToken = $credentialBinding
            StateRootBindingToken = $stateBinding
            WakeAdapterId = $wakeProvider.AdapterId
            WakeAdapterSha256 = $wakeProvider.AdapterSha256
            WakeBindingSha256 = $wakeProvider.BindingSha256
            GitOutboxRunnerSha256 = $wakeProvider.GitOutboxRunnerSha256
            CodexResumeBindingSha256 = $wakeProvider.CodexResumeBindingSha256
            ClientAdapterSha256 = $clientAdapterSha256
            IssuedAtUtc = $IssuedAtUtc.ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
            ExpiresAtUtc = $ExpiresAtUtc.ToString(
                'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
            )
        }
        return [pscustomobject][ordered]@{
            Context = $context
            Assertion = $assertion
            StateProvider = $stateProvider
            CredentialProvider = $credentialProvider
            WakeProvider = $wakeProvider
        }
    }

    function New-CddsiRealtimeProvisionTestStateDescriptor {
        param(
            [Parameter(Mandatory = $true)][string]$StateRoot,
            [string]$RunId = '66666666-6666-4666-8666-666666666666',
            [AllowNull()][string]$OwnerSid = $null,
            [string]$OwnershipTokenSha256 = ('a' * 64),
            [string]$ClientAdapterSha256 = ('b' * 64)
        )

        if ([string]::IsNullOrEmpty($OwnerSid)) {
            $OwnerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        }
        $fullPath = [IO.Path]::GetFullPath($StateRoot)
        return [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-owned-state-provider-v2'
            ProviderKind = 'OWNED_STATE'
            StateRoot = $fullPath
            RunId = $RunId
            OwnerSid = $OwnerSid
            OwnershipTokenSha256 = $OwnershipTokenSha256
            BindingToken = Get-CddsiRealtimeRelayStateBindingTokenInternal `
                -StateRoot $fullPath -OwnerSid $OwnerSid `
                -OwnershipTokenSha256 $OwnershipTokenSha256
            ClientAdapterSha256 = $ClientAdapterSha256
        }
    }
}

Describe 'realtime relay notification contract' {
    It 'accepts only the canonical immutable pointer schema on both PowerShell engines' {
        $raw = New-CddsiRealtimeTestMessage
        $result = Test-CddsiRealtimeRelayNotificationInternal -RawMessage $raw -NowUtc $script:RealtimeNow

        $result.Valid | Should -BeTrue
        $result.Code | Should -BeExactly 'VALID'
        $result.Message.RepositoryId | Should -BeExactly '1301870499'
        $raw | Should -Not -Match '(?i)command|powershell|prompt|script|logbody|freetext'
    }

    It 'rejects non-string schema fields instead of allowing PowerShell coercion' {
        $raw = New-CddsiRealtimeTestMessage
        $numberRepository = $raw.Replace('"RepositoryId":"1301870499"', '"RepositoryId":1301870499')

        $result = Test-CddsiRealtimeRelayNotificationInternal `
            -RawMessage $numberRepository -NowUtc $script:RealtimeNow
        $result.Valid | Should -BeFalse
        $result.Code | Should -BeExactly 'INVALID_FIELD_TYPE'
    }

    It 'rejects malformed, duplicate-key, oversized, future, and expired inputs' {
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage '{' -NowUtc $script:RealtimeNow).Valid |
            Should -BeFalse
        $duplicate = (New-CddsiRealtimeTestMessage).Replace(
            '"Commit":"' + ('b' * 40) + '","CreatedAt":',
            '"Commit":"' + ('b' * 40) + '","Commit":"' + ('b' * 40) + '","CreatedAt":'
        )
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage $duplicate -NowUtc $script:RealtimeNow).Valid |
            Should -BeFalse
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage ('x' * 4097) -NowUtc $script:RealtimeNow).Code |
            Should -BeExactly 'BODY_TOO_LARGE'

        $future = New-CddsiRealtimeTestMessage `
            -CreatedAt $script:RealtimeNow.AddMinutes(2).ToString('yyyy-MM-ddTHH:mm:ssZ') `
            -Expiry $script:RealtimeNow.AddMinutes(4).ToString('yyyy-MM-ddTHH:mm:ssZ')
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage $future -NowUtc $script:RealtimeNow).Code |
            Should -BeExactly 'CREATED_AT_OUTSIDE_WINDOW'
        $expired = New-CddsiRealtimeTestMessage `
            -CreatedAt $script:RealtimeNow.AddSeconds(-60).ToString('yyyy-MM-ddTHH:mm:ssZ') `
            -Expiry $script:RealtimeNow.AddSeconds(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage $expired -NowUtc $script:RealtimeNow).Code |
            Should -BeExactly 'MESSAGE_EXPIRED'
    }

    It 'uses the JavaScript-safe integer boundary for cross-language sequence values' {
        $maximum = New-CddsiRealtimeTestMessage -Sequence 9007199254740991 `
            -MessageId '00000000-0000-4000-8000-000000000001'
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage $maximum -NowUtc $script:RealtimeNow).Valid |
            Should -BeTrue
        $tooLarge = New-CddsiRealtimeTestMessage -Sequence 9007199254740992 `
            -MessageId '00000000-0000-4000-8000-000000000002'
        (Test-CddsiRealtimeRelayNotificationInternal -RawMessage $tooLarge -NowUtc $script:RealtimeNow).Code |
            Should -BeExactly 'INVALID_SEQUENCE'
    }

    It 'matches the Worker HMAC v2 golden vector on both PowerShell engines' {
        $canonical = New-CddsiRealtimeRelayCanonicalRequestInternal `
            -Environment 'production-v1' -KeyId 'host-2026-07' `
            -ClientId 'host-coordinator-v1' -Method GET `
            -CanonicalTarget '/v1/messages/vm-to-host?after=7' `
            -Timestamp '2030-01-01T00:00:00Z' `
            -Nonce ('A' * 43) `
            -BodySha256 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        $canonical | Should -BeExactly (@(
                'CDDsi-HMAC-SHA256-v2'
                'cddsi-realtime-relay-v1'
                'production-v1'
                'host-2026-07'
                'host-coordinator-v1'
                'GET'
                '/v1/messages/vm-to-host?after=7'
                '2030-01-01T00:00:00Z'
                ('A' * 43)
                'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
            ) -join "`n")
        $secret = [byte[]](0..31)
        try {
            (Get-CddsiRealtimeRelayHmacInternal -SecretBytes $secret -CanonicalRequest $canonical) |
                Should -BeExactly '94ab76773c9f421f487209cd97c164005607a0f103a82804b349b088aed0f942'
        }
        finally {
            [Array]::Clear($secret, 0, $secret.Length)
        }
    }

    It 'hashes an empty GET body and binds v2 scope without clearing resolver source bytes' {
        $secret = [byte[]](1..32)
        $resolver = { return $secret }.GetNewClosure()
        $headers1 = New-CddsiRealtimeRelayAuthHeadersInternal -ClientId 'vm-tester-v1' -Method GET `
            -CanonicalTarget '/v1/watch?after=0&lane=host-to-vm' -Body '' `
            -NowUtc $script:RealtimeNow -SecretResolver $resolver `
            -Environment 'production-v1' -KeyId 'vm-2026-07'
        $headers2 = New-CddsiRealtimeRelayAuthHeadersInternal -ClientId 'vm-tester-v1' -Method GET `
            -CanonicalTarget '/v1/watch?after=0&lane=host-to-vm' -Body '' `
            -NowUtc $script:RealtimeNow -SecretResolver $resolver `
            -Environment 'production-v1' -KeyId 'vm-2026-07'

        $headers1.'x-cddsi-audience' | Should -BeExactly 'cddsi-realtime-relay-v1'
        $headers1.'x-cddsi-environment' | Should -BeExactly 'production-v1'
        $headers1.'x-cddsi-key-id' | Should -BeExactly 'vm-2026-07'
        $headers1.'x-cddsi-body-sha256' | Should -BeExactly `
            'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
        $headers2.'x-cddsi-body-sha256' | Should -BeExactly $headers1.'x-cddsi-body-sha256'
        @($secret | Where-Object { $_ -eq 0 }).Count | Should -Be 0
    }
}

Describe 'realtime relay fake watcher state machine' {
    It 'consumes and ACKs host-to-vm without executing untrusted content' {
        $raw = New-CddsiRealtimeTestMessage -Lane host-to-vm
        $harness = New-CddsiRealtimeFakeHarness -Lane host-to-vm -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) },
            [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
        )

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion -Mode TestSafe

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Changed | Should -BeFalse
        $result.ProcessedCount | Should -Be 1
        $result.AckCount | Should -Be 1
        $harness.Tracker.WakeInvocationCount | Should -Be 1
        $harness.Tracker.WakeEvents[0].Verb | Should -BeExactly 'CONTROL_REPO_POINTER_AVAILABLE'
        (@($harness.Tracker.WakeEvents[0].PSObject.Properties.Name | Sort-Object) -join ',') |
            Should -BeExactly 'Commit,Lane,MessageId,PayloadSha256,Ref,RepositoryId,SchemaVersion,Sequence,Verb'
        $harness.Tracker.LockReleasedCount | Should -Be 1
        $harness.Tracker.TransportCloseCount | Should -Be 1
        Assert-CddsiRealtimeZeroMetrics -Result $result
    }

    It 'enforces the inverse vm-to-host reader identity in DryRun' {
        $raw = New-CddsiRealtimeTestMessage -Lane vm-to-host
        $harness = New-CddsiRealtimeFakeHarness -Lane vm-to-host -ContextMode DryRun -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) },
            [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
        )

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane vm-to-host -RuntimeAssertion $harness.Assertion -Mode DryRun

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $harness.Context.ClientId | Should -BeExactly 'host-coordinator-v1'
        $harness.Tracker.WakeEffectCount | Should -Be 1
        Assert-CddsiRealtimeZeroMetrics -Result $result
    }

    It 'reconnects with exponential backoff and resumes from the last ACK' {
        $raw = New-CddsiRealtimeTestMessage
        $harness = New-CddsiRealtimeFakeHarness -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Disconnected'; Messages = @(); Code = 'SYNTHETIC' },
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) },
            [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
        )

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.ReconnectCount | Should -Be 1
        @($harness.Tracker.DelayValues) | Should -Be @(1017)
        @($harness.Tracker.ReceiveAfter) | Should -Be @(0, 0, 1)
    }

    It 'replays an ACK loss without a second wake effect' {
        $raw = New-CddsiRealtimeTestMessage
        $harness = New-CddsiRealtimeFakeHarness -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) },
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) },
            [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
        ) -AckResults @($false, $true)

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion -MaxMessages 1

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.ProcessedCount | Should -Be 1
        $result.DuplicateCount | Should -Be 1
        $result.AckCount | Should -Be 1
        $harness.Tracker.WakeInvocationCount | Should -Be 1
        @($harness.Tracker.ReceiveAfter) | Should -Be @(0, 0)
        @($harness.Tracker.DelayValues) | Should -Be @(1017)
    }

    It 'permits only an exact state-backed late ACK replay after freshness windows' {
        $cases = @(
            [pscustomobject][ordered]@{
                CreatedAt = $script:RealtimeNow.AddSeconds(-120).ToString('yyyy-MM-ddTHH:mm:ssZ')
                Expiry = $script:RealtimeNow.AddMinutes(5).ToString('yyyy-MM-ddTHH:mm:ssZ')
            },
            [pscustomobject][ordered]@{
                CreatedAt = $script:RealtimeNow.AddMinutes(-10).ToString('yyyy-MM-ddTHH:mm:ssZ')
                Expiry = $script:RealtimeNow.AddSeconds(-1).ToString('yyyy-MM-ddTHH:mm:ssZ')
            }
        )
        foreach ($case in $cases) {
            $raw = New-CddsiRealtimeTestMessage -CreatedAt $case.CreatedAt -Expiry $case.Expiry
            $messageHash = Get-CddsiRealtimeRelayTextSha256Internal -Text $raw
            $state = [pscustomobject][ordered]@{
                SchemaVersion = 'cddsi-realtime-relay-watcher-state-v1'
                Lane = 'host-to-vm'
                LastConsumedSequence = [long]1
                LastAckedSequence = [long]0
                LastMessageSha256 = $messageHash
                ProcessedMessages = @([pscustomobject][ordered]@{
                        MessageId = '00000000-0000-4000-8000-000000000001'
                        Sequence = [long]1
                        MessageSha256 = $messageHash
                        PayloadSha256 = ('a' * 64)
                    })
                Revision = [long]1
            }
            $harness = New-CddsiRealtimeFakeHarness -ExistingState $state -ReceivePlans @(
                [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) }
            )
            $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
                -Lane host-to-vm -RuntimeAssertion $harness.Assertion -MaxMessages 1

            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.ProcessedCount | Should -Be 0
            $result.DuplicateCount | Should -Be 1
            $result.AckCount | Should -Be 1
            $result.LastAckedSequence | Should -Be 1
            $harness.Tracker.WakeInvocationCount | Should -Be 0

            $unseen = New-CddsiRealtimeFakeHarness -ReceivePlans @(
                [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) }
            )
            $blocked = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $unseen.Context `
                -Lane host-to-vm -RuntimeAssertion $unseen.Assertion -MaxMessages 1
            $blocked.Status | Should -BeExactly 'BLOCKED'
            $blocked.Code | Should -BeExactly 'REALTIME_NOTIFICATION_INVALID'
            $unseen.Tracker.WakeInvocationCount | Should -Be 0
        }
    }

    It 'bounds persistent ACK failures instead of livelocking' {
        $raw = New-CddsiRealtimeTestMessage
        $plans = @()
        1..3 | ForEach-Object {
            $plans += [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) }
        }
        $harness = New-CddsiRealtimeFakeHarness -ReceivePlans $plans -AckResults @($false, $false, $false)

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion -MaxReconnectAttempts 3

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_ACK_RETRY_EXHAUSTED'
        $harness.Tracker.WakeEffectCount | Should -Be 1
    }

    It 'does not report success when an unacknowledged state cannot be replayed' {
        $raw = New-CddsiRealtimeTestMessage
        $messageHash = Get-CddsiRealtimeRelayTextSha256Internal -Text $raw
        $state = [pscustomobject][ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-watcher-state-v1'
            Lane = 'host-to-vm'
            LastConsumedSequence = [long]1
            LastAckedSequence = [long]0
            LastMessageSha256 = $messageHash
            ProcessedMessages = @([pscustomobject][ordered]@{
                    MessageId = '00000000-0000-4000-8000-000000000001'
                    Sequence = [long]1
                    MessageSha256 = $messageHash
                    PayloadSha256 = ('a' * 64)
                })
            Revision = [long]1
        }
        foreach ($plan in @(
                [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() },
                [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @() }
            )) {
            $harness = New-CddsiRealtimeFakeHarness -ExistingState $state -ReceivePlans @($plan)
            $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
                -Lane host-to-vm -RuntimeAssertion $harness.Assertion
            $result.Status | Should -BeExactly 'BLOCKED'
            $result.Code | Should -BeExactly 'REALTIME_ACK_PENDING_NOT_REPLAYED'
            $harness.Tracker.WakeInvocationCount | Should -Be 0
        }
    }

    It 'fails closed on a sequence gap, wrong previous hash, and wrong lane' {
        $cases = @(
            (New-CddsiRealtimeTestMessage -Sequence 2)
            (New-CddsiRealtimeTestMessage -PreviousSha256 ('f' * 64))
            (New-CddsiRealtimeTestMessage -Lane vm-to-host)
        )
        foreach ($raw in $cases) {
            $harness = New-CddsiRealtimeFakeHarness -ReceivePlans @(
                [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) }
            )
            $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
                -Lane host-to-vm -RuntimeAssertion $harness.Assertion
            $result.Status | Should -BeExactly 'BLOCKED'
            $harness.Tracker.WakeInvocationCount | Should -Be 0
            Assert-CddsiRealtimeZeroMetrics -Result $result
        }
    }

    It 'rejects the same MessageId at a later otherwise-valid sequence' {
        $first = New-CddsiRealtimeTestMessage -Sequence 1
        $firstHash = Get-CddsiRealtimeRelayTextSha256Internal -Text $first
        $second = New-CddsiRealtimeTestMessage -Sequence 2 -PreviousSha256 $firstHash `
            -MessageId '00000000-0000-4000-8000-000000000001'
        $harness = New-CddsiRealtimeFakeHarness -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($first) },
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($second) }
        )

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_MESSAGE_ID_REPLAY'
        $harness.Tracker.WakeEffectCount | Should -Be 1
    }

    It 'blocks the wrong identity before any transport call' {
        $harness = New-CddsiRealtimeFakeHarness -AssertionClientId 'host-coordinator-v1'

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_SYNTHETIC_ASSERTION_INVALID'
        $harness.Tracker.ReceiveAfter.Count | Should -Be 0
    }

    It 'blocks invalid owner, ACL, reparse, credential, and non-fake contexts before receive' {
        foreach ($root in @(
                [pscustomobject][ordered]@{ Valid = $true; OwnerMarked = $false; AclProtected = $true; NoReparse = $true; Created = $false },
                [pscustomobject][ordered]@{ Valid = $true; OwnerMarked = $true; AclProtected = $false; NoReparse = $true; Created = $false },
                [pscustomobject][ordered]@{ Valid = $true; OwnerMarked = $true; AclProtected = $true; NoReparse = $false; Created = $false }
            )) {
            $harness = New-CddsiRealtimeFakeHarness -RootResult $root
            $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
                -Lane host-to-vm -RuntimeAssertion $harness.Assertion
            $result.Status | Should -BeExactly 'BLOCKED'
            $harness.Tracker.ReceiveAfter.Count | Should -Be 0
        }
        $credentialHarness = New-CddsiRealtimeFakeHarness -CredentialReady $false
        (Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $credentialHarness.Context `
                -Lane host-to-vm -RuntimeAssertion $credentialHarness.Assertion).Code |
            Should -BeExactly 'REALTIME_CREDENTIAL_NOT_READY'
        $liveHarness = New-CddsiRealtimeFakeHarness -ProviderKind Live
        (Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $liveHarness.Context `
                -Lane host-to-vm -RuntimeAssertion $liveHarness.Assertion).Code |
            Should -BeExactly 'REALTIME_NONLIVE_PROVIDER_NOT_FAKE'
    }

    It 'keeps atomic state unchanged on commit failure and recovers idempotently' {
        $raw = New-CddsiRealtimeTestMessage
        $harness = New-CddsiRealtimeFakeHarness -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) }
        ) -CommitFailures 1

        $failed = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion
        $failed.Status | Should -BeExactly 'BLOCKED'
        $failed.Code | Should -BeExactly 'REALTIME_STATE_ATOMIC_WRITE_FAILED'
        $harness.Tracker.State | Should -BeNullOrEmpty
        $harness.Tracker.AckBodies.Count | Should -Be 0

        $harness.Tracker.ReceivePlans = @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) },
            [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
        )
        $harness.Tracker.ReceiveIndex = 0
        $recovered = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion
        $recovered.Status | Should -BeExactly 'SUCCEEDED'
        $harness.Tracker.WakeEffectCount | Should -Be 1
    }

    It 'never discloses provider exception text and still attempts both cleanup paths' {
        $harness = New-CddsiRealtimeFakeHarness -ThrowOnClose -ThrowOnRelease
        $harness.Context.Providers.Transport.Receive = { throw ('A' * 64) }.GetNewClosure()

        $result = Invoke-CddsiRealtimeRelayWatcher -RelayExecutionContext $harness.Context `
            -Lane host-to-vm -RuntimeAssertion $harness.Assertion

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_WATCH_BLOCKED'
        $result.Code | Should -Not -Match '^A{64}$'
        $harness.Tracker.TransportCloseCount | Should -Be 1
        $harness.Tracker.LockReleasedCount | Should -Be 1
    }

    It 'treats repeated healthy WebSocket idle windows as no reconnect budget consumption' {
        $plans = @()
        for ($index = 0; $index -lt 8; $index++) {
            $plans += [pscustomobject][ordered]@{
                Status = 'Connected'
                Messages = @()
                Code = 'REALTIME_WEBSOCKET_IDLE'
            }
        }
        $plans += [pscustomobject][ordered]@{ Status = 'Stopped'; Messages = @() }
        $harness = New-CddsiRealtimeFakeHarness -ReceivePlans $plans
        $result = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $harness.Context -Lane host-to-vm `
            -RuntimeAssertion $harness.Assertion -MaxReconnectAttempts 1

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.ReconnectCount | Should -Be 0
        $harness.Tracker.ReceiveIndex | Should -Be 9
        Assert-CddsiRealtimeZeroMetrics -Result $result
    }
}

Describe 'realtime relay fake publisher state machine' {
    It 'publishes only fixed pointers in the one permitted direction for each writer' {
        foreach ($lane in @('host-to-vm', 'vm-to-host')) {
            $harness = New-CddsiRealtimeFakePublisherHarness -Lane $lane
            $result = Invoke-CddsiRealtimeRelayPublish `
                -RelayExecutionContext $harness.Context -PublishPointer $harness.Pointer `
                -RuntimeAssertion $harness.Assertion

            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.Code | Should -BeExactly 'PUBLISHED'
            $result.Mode | Should -BeExactly 'TestSafe'
            $result.Changed | Should -BeFalse
            $result.Idempotent | Should -BeFalse
            $result.Lane | Should -BeExactly $lane
            $result.Sequence | Should -Be 1
            $harness.Tracker.NetworkCount | Should -Be 1
            $harness.Tracker.MessageIdCount | Should -Be 0
            $harness.Tracker.CommitCount | Should -Be 2
            $harness.Tracker.ReleaseCount | Should -Be 1
            $harness.Tracker.State.PendingPublish | Should -BeNullOrEmpty
            $harness.Tracker.State.LastPublishedSequence | Should -Be 1
            $raw = [string]$harness.Tracker.Bodies[0]
            $validation = Test-CddsiRealtimeRelayNotificationInternal `
                -RawMessage $raw -NowUtc $script:RealtimeNow
            $validation.Valid | Should -BeTrue
            $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $lane
            $validation.Message.RepositoryId | Should -BeExactly $policy.RepositoryId
            $validation.Message.Ref | Should -BeExactly 'refs/heads/main'
            $validation.Message.SenderRole | Should -BeExactly $policy.SenderRole
            $validation.Message.PSObject.Properties.Name | Should -Not -Contain 'Prompt'
            Assert-CddsiRealtimeZeroMetrics -Result $result
        }
    }

    It 'retries the exact pending bytes and MessageId after response loss even past expiry' {
        $harness = New-CddsiRealtimeFakePublisherHarness `
            -ResponseCodes @('REJECTED', 'PUBLISHED_IDEMPOTENT')
        $first = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $harness.Context -PublishPointer $harness.Pointer `
            -RuntimeAssertion $harness.Assertion
        $first.Status | Should -BeExactly 'BLOCKED'
        $first.Code | Should -BeExactly 'REALTIME_PUBLISH_REJECTED'
        $harness.Tracker.State.PendingPublish | Should -Not -BeNullOrEmpty
        $firstBody = [string]$harness.Tracker.Bodies[0]
        $harness.Tracker.Now = $script:RealtimeNow.AddMinutes(10)

        $second = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $harness.Context -PublishPointer $harness.Pointer `
            -RuntimeAssertion $harness.Assertion

        $second.Status | Should -BeExactly 'SUCCEEDED'
        $second.Code | Should -BeExactly 'PUBLISHED_IDEMPOTENT'
        $second.Idempotent | Should -BeTrue
        $harness.Tracker.Bodies.Count | Should -Be 2
        [string]$harness.Tracker.Bodies[1] | Should -BeExactly $firstBody
        $harness.Tracker.MessageIdCount | Should -Be 0
        $harness.Tracker.State.PendingPublish | Should -BeNullOrEmpty
        $harness.Tracker.State.LastPublishedSequence | Should -Be 1
        Assert-CddsiRealtimeZeroMetrics -Result $first
        Assert-CddsiRealtimeZeroMetrics -Result $second
    }

    It 'carries one exact control record through publish, watch, and Git outbox target validation' {
        $controlSequence = 41L
        $controlPayload = [pscustomobject][ordered]@{
            SchemaVersion = '1'
            Status = 'SYNTHETIC_CONTROL_RECORD'
            EvidenceSha256 = '9' * 64
        }
        $controlPayloadSha256 = Get-CddsiVmTestRelayPayloadSha256 `
            -Payload $controlPayload
        $publisher = New-CddsiRealtimeFakePublisherHarness
        $publisher.Pointer.PayloadSha256 = $controlPayloadSha256
        $publishResult = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $publisher.Context -PublishPointer $publisher.Pointer `
            -RuntimeAssertion $publisher.Assertion
        $publishResult.Status | Should -BeExactly 'SUCCEEDED'
        $raw = [string]$publisher.Tracker.Bodies[0]
        $notification = Test-CddsiRealtimeRelayNotificationInternal `
            -RawMessage $raw -NowUtc $script:RealtimeNow
        $notification.Message.MessageId | Should -BeExactly $publisher.Pointer.MessageId

        $watcher = New-CddsiRealtimeFakeHarness -ReceivePlans @(
            [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($raw) }
        )
        $watchResult = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $watcher.Context -Lane host-to-vm `
            -RuntimeAssertion $watcher.Assertion -MaxMessages 1
        $watchResult.Status | Should -BeExactly 'SUCCEEDED'
        $watcher.Tracker.WakeEvents.Count | Should -Be 1
        $wake = $watcher.Tracker.WakeEvents[0]
        $wake.MessageId | Should -BeExactly $publisher.Pointer.MessageId
        $wake.Commit | Should -BeExactly $publisher.Pointer.Commit
        $wake.PayloadSha256 | Should -BeExactly $publisher.Pointer.PayloadSha256
        $wake.RepositoryId | Should -BeExactly '1301870499'
        $wake.Ref | Should -BeExactly 'refs/heads/main'
        $wake.Sequence | Should -Be 1
        $wake.Sequence | Should -Not -Be $controlSequence

        $controlRecord = [pscustomobject][ordered]@{
            Path = 'outbox/000000000041-' + $publisher.Pointer.MessageId + '.json'
            Message = [pscustomobject][ordered]@{
                Envelope = [pscustomobject][ordered]@{
                    MessageId = $publisher.Pointer.MessageId
                    Sequence = $controlSequence
                    PayloadSha256 = $controlPayloadSha256
                }
                Payload = $controlPayload
            }
        }
        $syntheticRepositoryPath = Join-Path $TestDrive 'synthetic-control.git'
        Mock Read-CddsiFastLaneMessageAtCommit {
            param($Context, $RepositoryPath, $Commit)
            if ($RepositoryPath -cne $syntheticRepositoryPath -or
                $Commit -cne $publisher.Pointer.Commit) {
                throw 'SYNTHETIC_TARGET_LOOKUP_BINDING_MISMATCH'
            }
            return $controlRecord
        }
        { Assert-CddsiFastLaneExpectedWakePointer -Pointer $wake -Operation Poll `
                -AuthenticatedOutbox host-to-vm -ExpectedRepositoryNumericId 1301870499 `
                -RemoteRef refs/heads/main } | Should -Not -Throw
        $target = Assert-CddsiFastLaneWakePointerTarget -Context @{
            ProviderKind = 'SYNTHETIC_NO_PROCESS'
        } -RepositoryPath $syntheticRepositoryPath -Pointer $wake
        $target.Path | Should -BeExactly $controlRecord.Path
        $target.Message.Envelope.Sequence | Should -Be $controlSequence
        $target.Message.Envelope.MessageId | Should -BeExactly $wake.MessageId
        $target.Message.Envelope.PayloadSha256 | Should -BeExactly $wake.PayloadSha256
        Should -Invoke Read-CddsiFastLaneMessageAtCommit -Times 1 -Exactly
        $watcher.Tracker.AckBodies.Count | Should -Be 1
        Assert-CddsiRealtimeZeroMetrics -Result $publishResult
        Assert-CddsiRealtimeZeroMetrics -Result $watchResult
    }

    It 'returns local idempotent success after final commit and rejects completed pointer drift' {
        $harness = New-CddsiRealtimeFakePublisherHarness
        $first = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $harness.Context -PublishPointer $harness.Pointer `
            -RuntimeAssertion $harness.Assertion
        $first.Code | Should -BeExactly 'PUBLISHED'
        $harness.Tracker.NetworkCount | Should -Be 1
        $harness.Tracker.CommitCount | Should -Be 2

        $retry = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $harness.Context -PublishPointer $harness.Pointer `
            -RuntimeAssertion $harness.Assertion
        $retry.Status | Should -BeExactly 'SUCCEEDED'
        $retry.Code | Should -BeExactly 'PUBLISHED_IDEMPOTENT'
        $retry.Idempotent | Should -BeTrue
        $retry.Sequence | Should -Be 1
        $retry.MessageSha256 | Should -BeExactly $first.MessageSha256
        $harness.Tracker.NetworkCount | Should -Be 1
        $harness.Tracker.CommitCount | Should -Be 2
        $harness.Tracker.State.PendingPublish | Should -BeNullOrEmpty

        foreach ($driftPointer in @(
                (New-CddsiRealtimeTestPublishPointer -Commit ('c' * 40))
                (New-CddsiRealtimeTestPublishPointer -PayloadSha256 ('d' * 64))
            )) {
            $drift = Invoke-CddsiRealtimeRelayPublish `
                -RelayExecutionContext $harness.Context -PublishPointer $driftPointer `
                -RuntimeAssertion $harness.Assertion
            $drift.Status | Should -BeExactly 'BLOCKED'
            $drift.Code | Should -BeExactly 'REALTIME_PUBLISH_PENDING_CONFLICT'
        }
        $harness.Tracker.NetworkCount | Should -Be 1
        $harness.Tracker.CommitCount | Should -Be 2
        Assert-CddsiRealtimeZeroMetrics -Result $retry
    }

    It 'keeps pending state on rejection and refuses pointer drift without another send' {
        $harness = New-CddsiRealtimeFakePublisherHarness -ResponseCodes @('REJECTED')
        $first = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $harness.Context -PublishPointer $harness.Pointer `
            -RuntimeAssertion $harness.Assertion
        $first.Code | Should -BeExactly 'REALTIME_PUBLISH_REJECTED'
        $drifted = New-CddsiRealtimeTestPublishPointer -Commit ('c' * 40)
        $second = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $harness.Context -PublishPointer $drifted `
            -RuntimeAssertion $harness.Assertion
        $second.Status | Should -BeExactly 'BLOCKED'
        $second.Code | Should -BeExactly 'REALTIME_PUBLISH_PENDING_CONFLICT'
        $harness.Tracker.NetworkCount | Should -Be 1
        $harness.Tracker.State.PendingPublish | Should -Not -BeNullOrEmpty
    }

    It 'fails before credential, state, or transport on wrong identity and malformed pointers' {
        $wrongIdentity = New-CddsiRealtimeFakePublisherHarness `
            -ClientId vm-tester-v1
        $identityResult = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $wrongIdentity.Context `
            -PublishPointer $wrongIdentity.Pointer `
            -RuntimeAssertion $wrongIdentity.Assertion
        $identityResult.Code | Should -BeExactly 'REALTIME_PUBLISH_WRITER_IDENTITY_MISMATCH'
        $wrongIdentity.Tracker.CredentialReadyCount | Should -Be 0
        $wrongIdentity.Tracker.StateOperationCount | Should -Be 0
        $wrongIdentity.Tracker.NetworkCount | Should -Be 0

        $malformed = New-CddsiRealtimeFakePublisherHarness
        $malformed.Pointer | Add-Member -NotePropertyName FreeText `
            -NotePropertyValue 'do not execute this'
        $malformedResult = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $malformed.Context `
            -PublishPointer $malformed.Pointer `
            -RuntimeAssertion $malformed.Assertion
        $malformedResult.Code | Should -BeExactly 'REALTIME_PUBLISH_NOTIFICATION_INVALID'
        $malformed.Tracker.CredentialReadyCount | Should -Be 0
        $malformed.Tracker.StateOperationCount | Should -Be 0
        $malformed.Tracker.NetworkCount | Should -Be 0
    }

    It 'persists pending before transport and preserves it on response drift' {
        $writeFailure = New-CddsiRealtimeFakePublisherHarness -CommitFailures 1
        $failed = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $writeFailure.Context `
            -PublishPointer $writeFailure.Pointer `
            -RuntimeAssertion $writeFailure.Assertion
        $failed.Code | Should -BeExactly 'REALTIME_PUBLISH_STATE_ATOMIC_WRITE_FAILED'
        $writeFailure.Tracker.NetworkCount | Should -Be 0

        $drift = New-CddsiRealtimeFakePublisherHarness
        $drift.Context.Providers.Transport.Publish = {
            param([string]$RequestedLane, [string]$Body)
            $drift.Tracker.NetworkCount++
            [void]$drift.Tracker.Bodies.Add($Body)
            return [pscustomobject][ordered]@{
                Accepted = $true
                Code = 'PUBLISHED'
                MessageSha256 = '0' * 64
            }
        }.GetNewClosure()
        $drifted = Invoke-CddsiRealtimeRelayPublish `
            -RelayExecutionContext $drift.Context -PublishPointer $drift.Pointer `
            -RuntimeAssertion $drift.Assertion
        $drifted.Code | Should -BeExactly 'REALTIME_PUBLISH_RESULT_INVALID'
        $drift.Tracker.State.PendingPublish | Should -Not -BeNullOrEmpty
        $drift.Tracker.CommitCount | Should -Be 1
    }
}

Describe 'realtime relay fixed live provider bindings' {
    It 'constructs data-only fixed wake providers for both inverse reader identities' {
        $adapterSha256 = Get-CddsiRealtimeRelayFileSha256Internal `
            -Path (Join-Path $script:RepoRoot 'operator\realtime-relay\realtime-relay-client.ps1')
        $runnerSha256 = Get-CddsiRealtimeRelayFileSha256Internal `
            -Path (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-git-outbox.ps1')
        foreach ($case in @(
                [pscustomobject]@{ Lane = 'host-to-vm'; ClientId = 'vm-tester-v1' }
                [pscustomobject]@{ Lane = 'vm-to-host'; ClientId = 'host-coordinator-v1' }
            )) {
            $binding = New-CddsiRealtimeTestGitOutboxBinding -Lane $case.Lane `
                -RunnerSha256 $runnerSha256
            $bindingSha256 = Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal -Binding $binding
            $codexParameters = New-CddsiRealtimeTestCodexWakeParameters `
                -GitOutboxBinding $binding -Lane $case.Lane
            $provider = New-CddsiRealtimeRelayFixedGitOutboxWakeProvider -Lane $case.Lane `
                -ClientId $case.ClientId -GitOutboxBinding $binding `
                -ExpectedBindingSha256 $bindingSha256 -ExpectedAdapterSha256 $adapterSha256 `
                -ExpectedGitOutboxRunnerSha256 $runnerSha256 @codexParameters

            (Test-CddsiRealtimeRelayFixedWakeProviderContractInternal -WakeProvider $provider `
                    -Lane $case.Lane -ClientId $case.ClientId -VerifySource) | Should -BeTrue
            @($provider.PSObject.Properties.Value | Where-Object {
                    $_ -is [scriptblock] -or $_ -is [Delegate]
                }).Count | Should -Be 0
            $provider.PSObject.Properties.Name | Should -Not -Contain 'InvokeFixed'
        }
    }

    It 'rejects executable binding data, source drift, lane drift, and post-construction mutation' {
        $adapterPath = Join-Path $script:RepoRoot 'operator\realtime-relay\realtime-relay-client.ps1'
        $runnerPath = Join-Path $script:RepoRoot 'operator\fast-lane\invoke-git-outbox.ps1'
        $adapterSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $adapterPath
        $runnerSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $runnerPath
        $binding = New-CddsiRealtimeTestGitOutboxBinding -RunnerSha256 $runnerSha256
        $bindingSha256 = Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal -Binding $binding
        $codexParameters = New-CddsiRealtimeTestCodexWakeParameters `
            -GitOutboxBinding $binding

        { New-CddsiRealtimeRelayFixedGitOutboxWakeProvider -Lane host-to-vm `
                -ClientId host-coordinator-v1 -GitOutboxBinding $binding `
                -ExpectedBindingSha256 $bindingSha256 -ExpectedAdapterSha256 $adapterSha256 `
                -ExpectedGitOutboxRunnerSha256 $runnerSha256 @codexParameters } |
            Should -Throw -ExpectedMessage 'REALTIME_WAKE_BINDING_INVALID'
        { New-CddsiRealtimeRelayFixedGitOutboxWakeProvider -Lane host-to-vm `
                -ClientId vm-tester-v1 -GitOutboxBinding $binding `
                -ExpectedBindingSha256 $bindingSha256 -ExpectedAdapterSha256 ('f' * 64) `
                -ExpectedGitOutboxRunnerSha256 $runnerSha256 @codexParameters } |
            Should -Throw -ExpectedMessage 'REALTIME_WAKE_SOURCE_HASH_MISMATCH'

        $executable = New-CddsiRealtimeTestGitOutboxBinding -RunnerSha256 $runnerSha256
        $executable.ProtectionEvidence = [pscustomobject][ordered]@{ Run = { throw 'UNTRUSTED' } }
        { New-CddsiRealtimeRelayFixedGitOutboxWakeProvider -Lane host-to-vm `
                -ClientId vm-tester-v1 -GitOutboxBinding $executable `
                -ExpectedBindingSha256 ('0' * 64) -ExpectedAdapterSha256 $adapterSha256 `
                -ExpectedGitOutboxRunnerSha256 $runnerSha256 @codexParameters } |
            Should -Throw -ExpectedMessage 'REALTIME_WAKE_BINDING_EXECUTABLE_FORBIDDEN'

        $provider = New-CddsiRealtimeRelayFixedGitOutboxWakeProvider -Lane host-to-vm `
            -ClientId vm-tester-v1 -GitOutboxBinding $binding `
            -ExpectedBindingSha256 $bindingSha256 -ExpectedAdapterSha256 $adapterSha256 `
            -ExpectedGitOutboxRunnerSha256 $runnerSha256 @codexParameters
        $provider.Binding.MaximumAgeSeconds = 601
        (Test-CddsiRealtimeRelayFixedWakeProviderContractInternal -WakeProvider $provider `
                -Lane host-to-vm -ClientId vm-tester-v1 -VerifySource) | Should -BeFalse
    }

    It 'exposes no caller-supplied live wake scriptblock and rejects invalid DPAPI scope before path access' {
        $liveParameters = (Get-Command New-CddsiRealtimeRelayLiveProvider -CommandType Function).Parameters
        $liveParameters.Keys | Should -Contain 'FixedWakeProvider'
        $liveParameters.Keys | Should -Not -Contain 'WakeAdapter'
        $liveParameters.Keys | Should -Not -Contain 'WakeAdapterSha256'

        { New-CddsiRealtimeRelayDpapiCredentialProvider -StateRoot 'Z:\must-not-be-read' `
                -RunId '00000000-0000-4000-8000-000000000001' -OwnerSid 'S-1-5-21-1' `
                -OwnershipTokenSha256 ('a' * 64) -ClientId vm-tester-v1 `
                -Environment 'INVALID_ENVIRONMENT' -KeyId 'vm-2026-07' } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_AUTH_SCOPE_INVALID'
    }
}

Describe 'realtime relay fixed wake proof and process boundary' {
    BeforeEach {
        $script:WakeNow = $script:RealtimeNow
        $script:WakeReceiptStatus = 'CONSUMED_NOW'
        $script:WakeProofState = New-CddsiRealtimeRelayWakeProofStateInternal `
            -Lane host-to-vm
        $script:WakeCommittedStatuses = [Collections.ArrayList]::new()
        $script:WakeProofCommitFailures = 0
        $script:WakeProcessAdvancesClock = $false
        $script:WakeProcessThrows = $false
        $script:WakeProcessResult = [pscustomobject][ordered]@{
            Started = $true
            Completed = $true
            ExitCode = 0
            TimedOut = $false
            JobAssigned = $true
            ProcessTreeTerminated = $false
            EnvironmentInheritedCount = 0
            OutputDiscarded = $true
        }

        Mock Get-CddsiRealtimeRelayLiveUtcNowInternal { return $script:WakeNow }
        Mock Invoke-CddsiRealtimeRelayOwnedStateOperationInternal {
            param($StateProvider, $Operation, $Lane, $State, $Handle)
            if ($Operation -ceq 'LoadWakeProof') {
                return ConvertFrom-Json -InputObject (
                    ConvertTo-Json -Compress -Depth 8 -InputObject $script:WakeProofState
                )
            }
            if ($Operation -ceq 'CommitWakeProof') {
                if ($script:WakeProofCommitFailures -gt 0) {
                    $script:WakeProofCommitFailures--
                    throw 'SYNTHETIC_WAKE_PROOF_COMMIT_FAILURE'
                }
                $entryStatus = if (@($State.Entries).Count -eq 0) {
                    '<EMPTY>'
                }
                else {
                    [string]$State.Entries[-1].Status
                }
                [void]$script:WakeCommittedStatuses.Add($entryStatus)
                $script:WakeProofState = ConvertFrom-Json -InputObject (
                    ConvertTo-Json -Compress -Depth 8 -InputObject $State
                )
                return
            }
            throw 'UNEXPECTED_WAKE_STATE_OPERATION'
        }
        Mock Invoke-CddsiFastLaneGitOutbox {
            param($ExpectedWakePointer)
            return [pscustomobject][ordered]@{
                WakeReceipt = [pscustomobject][ordered]@{
                    SchemaVersion = 1L
                    ContractVersion = 'cddsi-fast-lane-wake-receipt-v1'
                    Status = $script:WakeReceiptStatus
                    Lane = $ExpectedWakePointer.Lane
                    MessageId = $ExpectedWakePointer.MessageId
                    Sequence = [long]$ExpectedWakePointer.Sequence
                    RepositoryId = $ExpectedWakePointer.RepositoryId
                    Ref = $ExpectedWakePointer.Ref
                    Commit = $ExpectedWakePointer.Commit
                    PayloadSha256 = $ExpectedWakePointer.PayloadSha256
                    RepositoryIdentityVerified = $true
                    PayloadSha256Verified = $true
                    FixedEntryInvoked = $false
                    Consumed = $true
                }
                GitInvocationCount = 1L
                OperatorGitTransportCount = 1L
                LocalStateMutationCount = 1L
                ProductNetworkRequestCount = 0L
            }
        }
        Mock Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal {
            param($WakeProvider, $ClockProvider, $AuthorizationExpiresAtUtc)
            if ($script:WakeProcessThrows) {
                throw 'REALTIME_FIXED_WAKE_REJECTED'
            }
            if ($script:WakeProcessAdvancesClock) {
                $script:WakeNow = $script:RealtimeNow.AddSeconds(61)
            }
            return $script:WakeProcessResult
        }
    }

    AfterEach {
        foreach ($sessionId in @($script:CddsiRealtimeLiveSessions.Keys)) {
            Close-CddsiRealtimeRelayTrustedLiveSessionInternal `
                -TrustedSessionId ([string]$sessionId)
        }
    }

    It 'commits PENDING before one fixed process and commits SUCCEEDED only after exit zero' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $event = New-CddsiRealtimeTestWakeEvent
        $audit = $script:CddsiRealtimeLiveSessions[
            $harness.Context.Providers.Transport.SessionId
        ]

        $result = Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
            -WakeProvider $harness.WakeProvider -WakeEvent $event `
            -StateProvider $harness.StateProvider -AuditSession $audit `
            -ClockProvider $harness.Context.Providers.Clock `
            -RelayContext $harness.Context -RuntimeAssertion $harness.Assertion `
            -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60)

        @($script:WakeCommittedStatuses) | Should -Be @('PENDING', 'SUCCEEDED')
        $script:WakeProofState.Entries[0].Status | Should -BeExactly 'SUCCEEDED'
        $result.FixedEntryInvoked | Should -BeTrue
        $result.PreviouslyInvoked | Should -BeFalse
        $result.OperatorCodexProcessSpawnCount | Should -Be 1
        $result.FixedWakeEffectCount | Should -Be 1
        $audit.OperatorCodexProcessSpawnCount | Should -Be 1
        $audit.FixedWakeEffectCount | Should -Be 1
        $audit.PersistentChangeObserved | Should -BeTrue
        Assert-MockCalled Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal `
            -Times 1 -Exactly
    }

    It 'does not spawn for ALREADY_CONSUMED with SUCCEEDED proof and retries PENDING proof' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $event = New-CddsiRealtimeTestWakeEvent
        $script:WakeReceiptStatus = 'ALREADY_CONSUMED'
        foreach ($proofStatus in @('SUCCEEDED', 'PENDING')) {
            $script:WakeProofState = [pscustomobject][ordered]@{
                SchemaVersion = 'cddsi-realtime-relay-wake-proof-v1'
                Lane = 'host-to-vm'
                Entries = @([pscustomobject][ordered]@{
                        MessageId = $event.MessageId
                        Sequence = [long]$event.Sequence
                        Commit = $event.Commit
                        PayloadSha256 = $event.PayloadSha256
                        Status = $proofStatus
                    })
                Revision = 1L
            }
            $script:WakeCommittedStatuses.Clear()
            $harness = New-CddsiRealtimeTestLiveHarness
            $audit = $script:CddsiRealtimeLiveSessions[
                $harness.Context.Providers.Transport.SessionId
            ]
            $result = Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
                -WakeProvider $harness.WakeProvider -WakeEvent $event `
                -StateProvider $harness.StateProvider -AuditSession $audit `
                -ClockProvider $harness.Context.Providers.Clock `
                -RelayContext $harness.Context -RuntimeAssertion $harness.Assertion `
                -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60)
            if ($proofStatus -ceq 'SUCCEEDED') {
                $result.PreviouslyInvoked | Should -BeTrue
                $result.FixedEntryInvoked | Should -BeFalse
                @($script:WakeCommittedStatuses).Count | Should -Be 0
            }
            else {
                $result.PreviouslyInvoked | Should -BeFalse
                $result.FixedEntryInvoked | Should -BeTrue
                @($script:WakeCommittedStatuses) | Should -Be @('SUCCEEDED')
            }
            Close-CddsiRealtimeRelayTrustedLiveSessionInternal `
                -TrustedSessionId $harness.Context.Providers.Transport.SessionId
        }
        Assert-MockCalled Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal `
            -Times 1 -Exactly
    }

    It 'recovers ALREADY_CONSUMED with missing proof after the first PENDING commit failed' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $event = New-CddsiRealtimeTestWakeEvent
        $audit = $script:CddsiRealtimeLiveSessions[
            $harness.Context.Providers.Transport.SessionId
        ]
        $script:WakeProofCommitFailures = 1

        { Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
                -WakeProvider $harness.WakeProvider -WakeEvent $event `
                -StateProvider $harness.StateProvider -AuditSession $audit `
                -ClockProvider $harness.Context.Providers.Clock `
                -RelayContext $harness.Context -RuntimeAssertion $harness.Assertion `
                -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60) } |
            Should -Throw -ExpectedMessage 'SYNTHETIC_WAKE_PROOF_COMMIT_FAILURE'
        @($script:WakeProofState.Entries).Count | Should -Be 0
        Assert-MockCalled Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal `
            -Times 0 -Exactly

        $script:WakeReceiptStatus = 'ALREADY_CONSUMED'
        $result = Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
            -WakeProvider $harness.WakeProvider -WakeEvent $event `
            -StateProvider $harness.StateProvider -AuditSession $audit `
            -ClockProvider $harness.Context.Providers.Clock `
            -RelayContext $harness.Context -RuntimeAssertion $harness.Assertion `
            -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60)
        @($script:WakeCommittedStatuses) | Should -Be @('PENDING', 'SUCCEEDED')
        $script:WakeProofState.Entries[0].Status | Should -BeExactly 'SUCCEEDED'
        $result.FixedEntryInvoked | Should -BeTrue
        $result.PreviouslyInvoked | Should -BeFalse
        Assert-MockCalled Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal `
            -Times 1 -Exactly
    }

    It 'leaves proof PENDING for process rejection, timeout, nonzero exit, and no job' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        foreach ($case in @('THROW', 'TIMEOUT', 'NONZERO', 'NO_JOB')) {
            $script:WakeProofState = New-CddsiRealtimeRelayWakeProofStateInternal `
                -Lane host-to-vm
            $script:WakeCommittedStatuses.Clear()
            $script:WakeProcessThrows = $case -ceq 'THROW'
            $script:WakeProcessResult = [pscustomobject][ordered]@{
                Started = $true
                Completed = $true
                ExitCode = if ($case -ceq 'NONZERO') { 9 } else { 0 }
                TimedOut = $case -ceq 'TIMEOUT'
                JobAssigned = $case -cne 'NO_JOB'
                ProcessTreeTerminated = $false
                EnvironmentInheritedCount = 0
                OutputDiscarded = $true
            }
            $harness = New-CddsiRealtimeTestLiveHarness
            $event = New-CddsiRealtimeTestWakeEvent
            $audit = $script:CddsiRealtimeLiveSessions[
                $harness.Context.Providers.Transport.SessionId
            ]
            { Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
                    -WakeProvider $harness.WakeProvider -WakeEvent $event `
                    -StateProvider $harness.StateProvider -AuditSession $audit `
                    -ClockProvider $harness.Context.Providers.Clock `
                    -RelayContext $harness.Context -RuntimeAssertion $harness.Assertion `
                    -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60) } |
                Should -Throw -ExpectedMessage 'REALTIME_FIXED_WAKE_REJECTED'
            @($script:WakeCommittedStatuses) | Should -Be @('PENDING')
            $script:WakeProofState.Entries[0].Status | Should -BeExactly 'PENDING'
            $audit.FixedWakeEffectCount | Should -Be 0
            Close-CddsiRealtimeRelayTrustedLiveSessionInternal `
                -TrustedSessionId $harness.Context.Providers.Transport.SessionId
        }

        $watcher = New-CddsiRealtimeFakeHarness -ReceivePlans @(
            [pscustomobject][ordered]@{
                Status = 'Connected'
                Messages = @(New-CddsiRealtimeTestMessage)
            }
        )
        $watcher.Context.Providers.Wake.InvokeFixed = {
            throw 'REALTIME_FIXED_WAKE_REJECTED'
        }
        $watchResult = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $watcher.Context -Lane host-to-vm `
            -RuntimeAssertion $watcher.Assertion -MaxMessages 1
        $watchResult.Code | Should -BeExactly 'REALTIME_FIXED_WAKE_REJECTED'
        $watcher.Tracker.CommitCount | Should -Be 0
        $watcher.Tracker.AckBodies.Count | Should -Be 0
        Assert-CddsiRealtimeZeroMetrics -Result $watchResult
    }

    It 'accepts drained truncated output while binding exact argv and a minimal environment' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        Initialize-CddsiFastLaneBoundedProcessType
        $invocation = New-CddsiRealtimeRelayFixedCodexInvocationInternal `
            -WakeProvider $harness.WakeProvider
        $runnerResult = [pscustomobject][ordered]@{
            JobAssigned = $true
            TimedOut = $false
            ProcessTreeTerminated = $false
            ExitCode = 0
            Truncated = $true
            StandardOutput = 'X' * 5000
            StandardError = 'Y' * 5000
        }
        $result = ConvertTo-CddsiRealtimeRelayFixedCodexResultInternal `
            -RunnerResult $runnerResult

        $result.Completed | Should -BeTrue
        $result.OutputDiscarded | Should -BeTrue
        $result.PSObject.Properties.Name | Should -Not -Contain 'StandardOutput'
        $result.PSObject.Properties.Name | Should -Not -Contain 'StandardError'
        $invocation.Executable | Should -BeExactly `
            $harness.WakeProvider.CodexExecutable
        $invocation.WorkingDirectory | Should -BeExactly `
            $harness.WakeProvider.CodexWorkingRoot
        $invocation.StandardInput | Should -BeExactly ''
        $invocation.MaximumOutputBytes | Should -Be 4096
        $expectedArguments = (@(
                'exec', 'resume', '--json', $harness.WakeProvider.CodexSessionId,
                $script:CddsiRealtimeFixedResumePrompt
            ) | ForEach-Object {
                ConvertTo-CddsiFastLaneGitQuotedArgument -Value ([string]$_)
            }) -join ' '
        $invocation.ArgumentText | Should -BeExactly $expectedArguments
        $invocation.ArgumentText | Should -Not -Match ('a' * 64)
        @($invocation.Environment.Keys | Sort-Object) | Should -Be @(
            'CODEX_HOME', 'HOME', 'LOCALAPPDATA', 'NO_COLOR', 'SystemRoot', 'TEMP',
            'TMP', 'USERPROFILE', 'WINDIR'
        )
        foreach ($forbidden in @(
                'PATH', 'HTTP_PROXY', 'HTTPS_PROXY', 'OPENAI_API_KEY',
                'CLOUDFLARE_API_TOKEN', 'NODE_OPTIONS'
            )) {
            $invocation.Environment.ContainsKey($forbidden) | Should -BeFalse
        }
    }

    It 'keeps PENDING and never commits SUCCEEDED when authorization expires after process exit' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $script:WakeProcessAdvancesClock = $true
        $harness = New-CddsiRealtimeTestLiveHarness
        $event = New-CddsiRealtimeTestWakeEvent
        $audit = $script:CddsiRealtimeLiveSessions[
            $harness.Context.Providers.Transport.SessionId
        ]

        { Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
                -WakeProvider $harness.WakeProvider -WakeEvent $event `
                -StateProvider $harness.StateProvider -AuditSession $audit `
                -ClockProvider $harness.Context.Providers.Clock `
                -RelayContext $harness.Context -RuntimeAssertion $harness.Assertion `
                -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60) } |
            Should -Throw -ExpectedMessage 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        @($script:WakeCommittedStatuses) | Should -Be @('PENDING')
        $script:WakeProofState.Entries[0].Status | Should -BeExactly 'PENDING'
        $audit.FixedWakeEffectCount | Should -Be 1
        $audit.PersistentChangeObserved | Should -BeTrue
    }
}

Describe 'realtime relay DPAPI credential provisioning' {
    BeforeEach {
        $script:ProtectedDataProtectCount = 0
        $script:ProtectedDataUnprotectCount = 0
        Mock Protect-CddsiRealtimeRelaySecretCurrentUserInternal {
            param($SecretBytes, $EntropyBytes)
            $script:ProtectedDataProtectCount++
            $protected = [byte[]]::new(64)
            for ($index = 0; $index -lt 32; $index++) {
                $protected[$index] = [byte]($SecretBytes[$index] -bxor 0xA5)
                $protected[$index + 32] = [byte]($EntropyBytes[$index] -bxor 0x5A)
            }
            return $protected
        }
        Mock Unprotect-CddsiRealtimeRelaySecretCurrentUserInternal {
            param($ProtectedBytes, $EntropyBytes)
            $script:ProtectedDataUnprotectCount++
            if ($ProtectedBytes.Length -ne 64) {
                throw 'SYNTHETIC_PROTECTED_DATA_INVALID'
            }
            $secret = [byte[]]::new(32)
            for ($index = 0; $index -lt 32; $index++) {
                if ($ProtectedBytes[$index + 32] -ne
                    [byte]($EntropyBytes[$index] -bxor 0x5A)) {
                    throw 'SYNTHETIC_ENTROPY_BINDING_INVALID'
                }
                $secret[$index] = [byte]($ProtectedBytes[$index] -bxor 0xA5)
            }
            return $secret
        }
    }

    It 'plans TestSafe and DryRun with exact data-only output and zero state or DPAPI touch' {
        $runId = '66666666-6666-4666-8666-666666666666'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $stateProvider = New-CddsiRealtimeProvisionTestStateDescriptor `
            -StateRoot $root -RunId $runId
        $secret = [byte[]](0..31)
        Mock Get-CddsiRealtimeRelayClientAdapterSha256Internal { throw 'SOURCE_READ_FORBIDDEN' }
        Mock Initialize-CddsiRealtimeRelayOwnedStateRootInternal { throw 'STATE_TOUCH_FORBIDDEN' }
        Mock Test-CddsiRealtimeRelayCredentialCandidateInternal { throw 'DPAPI_TOUCH_FORBIDDEN' }

        foreach ($mode in @('TestSafe', 'DryRun')) {
            $result = Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes $secret -Mode $mode -AllowCreate
            (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $result `
                    -Expected $script:CddsiRealtimeCredentialProvisionResultProperties) |
                Should -BeTrue
            $result.SchemaVersion | Should -BeExactly `
                'cddsi-realtime-relay-credential-provision-result-v1'
            $result.Status | Should -BeExactly 'PLANNED'
            $result.Changed | Should -BeFalse
            $result.CredentialBlobSha256 | Should -BeNullOrEmpty
            ($result | ConvertTo-Json -Compress) | Should -Not -Match `
                '(?i)secret|protectedsecret|stateRoot|credentialPath'
        }
        Assert-MockCalled Get-CddsiRealtimeRelayClientAdapterSha256Internal -Times 0
        Assert-MockCalled Initialize-CddsiRealtimeRelayOwnedStateRootInternal -Times 0
        Assert-MockCalled Test-CddsiRealtimeRelayCredentialCandidateInternal -Times 0
        $script:ProtectedDataProtectCount | Should -Be 0
        $script:ProtectedDataUnprotectCount | Should -Be 0
        Test-Path -LiteralPath $root | Should -BeFalse
        $secret | Should -Be ([byte[]](0..31))
        $script:ProtectCurrentUserFunctionText |
            Should -Match '\[Security\.Cryptography\.ProtectedData\]::Protect'
        $script:ProtectCurrentUserFunctionText |
            Should -Match '\[Security\.Cryptography\.DataProtectionScope\]::CurrentUser'
        $script:UnprotectCurrentUserFunctionText |
            Should -Match '\[Security\.Cryptography\.ProtectedData\]::Unprotect'
    }

    It 'parses only a bounded canonical credential blob without invoking DPAPI' {
        $credentialPath = Join-Path $TestDrive 'credential-parse.json'
        $bindingToken = 'd' * 64
        $protectedBase64 = [Convert]::ToBase64String([byte[]](0..63))
        $blob = [pscustomobject][ordered]@{
            ClientId = 'vm-tester-v1'
            Environment = 'production-v1'
            KeyId = 'vm-2026-07'
            ProtectedSecretBase64 = $protectedBase64
            ProtectionScope = 'CurrentUser'
            SchemaVersion = 'cddsi-realtime-relay-dpapi-credential-v1'
            StateRootBindingToken = $bindingToken
        }
        $canonical = ConvertTo-CddsiRealtimeRelayCanonicalCredentialBlobInternal `
            -CredentialBlob $blob
        [IO.File]::WriteAllText(
            $credentialPath,
            $canonical,
            [Text.UTF8Encoding]::new($false)
        )
        $parsed = Read-CddsiRealtimeRelayCredentialBlobInternal `
            -CredentialPath $credentialPath -ClientId vm-tester-v1 `
            -Environment production-v1 -KeyId vm-2026-07 `
            -StateRootBindingToken $bindingToken
        $parsed.CredentialBlobSha256 | Should -Match '^[0-9a-f]{64}$'

        $invalidBlobs = @(
            $canonical.Replace(
                '"ClientId":"vm-tester-v1"',
                '"ClientId":"vm-tester-v1","ClientId":"vm-tester-v1"'
            )
            ($canonical + ' ')
            $canonical.Replace($protectedBase64, 'AA==')
            ('x' * ($script:CddsiRealtimeMaxCredentialBlobBytes + 1))
        )
        foreach ($invalidBlob in $invalidBlobs) {
            [IO.File]::WriteAllText(
                $credentialPath,
                $invalidBlob,
                [Text.UTF8Encoding]::new($false)
            )
            { Read-CddsiRealtimeRelayCredentialBlobInternal `
                    -CredentialPath $credentialPath -ClientId vm-tester-v1 `
                    -Environment production-v1 -KeyId vm-2026-07 `
                    -StateRootBindingToken $bindingToken } |
                Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        $script:ProtectedDataProtectCount | Should -Be 0
        $script:ProtectedDataUnprotectCount | Should -Be 0
    }

    It 'creates a CurrentUser blob through the fixed fake seam and never emits plaintext' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $runId = '77777777-7777-4777-8777-777777777777'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $stateProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root `
            -RunId $runId -OwnerSid $ownerSid -OwnershipTokenSha256 ('c' * 64)
        $canary = 'CDDsiRelaySecretCanary-123456789'
        $secret = [Text.Encoding]::ASCII.GetBytes($canary)
        $original = [byte[]]$secret.Clone()
        try {
            $result = Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes $secret -Mode Live -AcknowledgeCredentialWrite -AllowCreate
            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.Code | Should -BeExactly 'REALTIME_CREDENTIAL_CREATED'
            $result.Changed | Should -BeTrue
            $result.CredentialBlobSha256 | Should -Match '^[0-9a-f]{64}$'
            (Compare-Object $original $secret) | Should -BeNullOrEmpty

            $credentialPath = Join-Path $root '.relay-credential.dpapi.json'
            $raw = [IO.File]::ReadAllText($credentialPath, [Text.UTF8Encoding]::new($false, $true))
            $raw | Should -Not -Match ([regex]::Escape($canary))
            $raw | Should -Not -Match ([regex]::Escape([Convert]::ToBase64String($secret)))
            ($result | ConvertTo-Json -Compress) | Should -Not -Match `
                '(?i)ProtectedSecretBase64|CredentialPath|StateRoot'

            $provider = New-CddsiRealtimeRelayDpapiCredentialProvider -StateRoot $root `
                -RunId $runId -OwnerSid $ownerSid -OwnershipTokenSha256 ('c' * 64) `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07
            $provider.CredentialBlobSha256 | Should -BeExactly $result.CredentialBlobSha256
            $canonical = 'synthetic-canonical-request-without-secret'
            $actualSignature = Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal `
                -CredentialProvider $provider -Operation Sign -CanonicalRequest $canonical
            $expectedSignature = Get-CddsiRealtimeRelayHmacInternal `
                -SecretBytes $secret -CanonicalRequest $canonical
            $actualSignature | Should -BeExactly $expectedSignature
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.next.json') |
                Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.backup.json') |
                Should -BeFalse
        }
        finally {
            [Array]::Clear($secret, 0, $secret.Length)
            [Array]::Clear($original, 0, $original.Length)
        }
    }

    It 'requires CAS for rotation, rejects create over existing, and signs with the rotated key' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $runId = '88888888-8888-4888-8888-888888888888'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $stateProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root `
            -RunId $runId -OwnerSid $ownerSid -OwnershipTokenSha256 ('d' * 64)
        $oldSecret = [byte[]](0..31)
        $newSecret = [byte[]](32..63)
        try {
            $created = Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes $oldSecret -Mode Live -AcknowledgeCredentialWrite -AllowCreate
            $credentialPath = Join-Path $root '.relay-credential.dpapi.json'
            $oldRawSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $credentialPath

            { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                    -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-08 `
                    -SecretBytes $newSecret -Mode Live -AcknowledgeCredentialWrite `
                    -ExpectedCurrentCredentialBlobSha256 ('f' * 64) } |
                Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_ROTATION_CAS_MISMATCH'
            (Get-CddsiRealtimeRelayFileSha256Internal -Path $credentialPath) |
                Should -BeExactly $oldRawSha256
            { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                    -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-08 `
                    -SecretBytes $newSecret -Mode Live -AcknowledgeCredentialWrite -AllowCreate } |
                Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_ALREADY_EXISTS'

            $rotated = Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-08 `
                -SecretBytes $newSecret -Mode Live -AcknowledgeCredentialWrite `
                -ExpectedCurrentCredentialBlobSha256 $created.CredentialBlobSha256
            $rotated.Code | Should -BeExactly 'REALTIME_CREDENTIAL_ROTATED'
            $rotated.CredentialBlobSha256 | Should -Not -BeExactly `
                $created.CredentialBlobSha256
            $provider = New-CddsiRealtimeRelayDpapiCredentialProvider -StateRoot $root `
                -RunId $runId -OwnerSid $ownerSid -OwnershipTokenSha256 ('d' * 64) `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-08
            $canonical = 'rotation-verification-request'
            (Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal `
                    -CredentialProvider $provider -Operation Sign `
                    -CanonicalRequest $canonical) | Should -BeExactly `
                (Get-CddsiRealtimeRelayHmacInternal -SecretBytes $newSecret `
                    -CanonicalRequest $canonical)
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.next.json') |
                Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.backup.json') |
                Should -BeFalse
        }
        finally {
            [Array]::Clear($oldSecret, 0, $oldSecret.Length)
            [Array]::Clear($newSecret, 0, $newSecret.Length)
        }
    }

    It 'blocks stale credential candidates and historical backups before blob read, DPAPI, or network' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $runId = '18181818-1818-4818-8818-181818181818'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $ownershipToken = '5' * 64
        $stateProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root `
            -RunId $runId -OwnerSid $ownerSid `
            -OwnershipTokenSha256 $ownershipToken
        $secret = [byte[]](0..31)
        try {
            [void](Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                    -ClientId vm-tester-v1 -Environment production-v1 `
                    -KeyId vm-2026-07 -SecretBytes $secret -Mode Live `
                    -AcknowledgeCredentialWrite -AllowCreate)
            $provider = New-CddsiRealtimeRelayDpapiCredentialProvider -StateRoot $root `
                -RunId $runId -OwnerSid $ownerSid `
                -OwnershipTokenSha256 $ownershipToken -ClientId vm-tester-v1 `
                -Environment production-v1 -KeyId vm-2026-07
            $clientAdapterSha256 = Get-CddsiRealtimeRelayClientAdapterSha256Internal
            $clock = [pscustomobject][ordered]@{
                SchemaVersion = 'cddsi-realtime-relay-live-clock-provider-v1'
                ProviderKind = 'STATIC_SYSTEM_CLOCK'
                ClientAdapterSha256 = $clientAdapterSha256
            }
            $session = [pscustomobject][ordered]@{
                Socket = $null
                OperatorRelayNetworkRequestCount = 0L
            }
            $unprotectBefore = $script:ProtectedDataUnprotectCount
            Mock Read-CddsiRealtimeRelayCredentialBlobInternal {
                throw 'CURRENT_CREDENTIAL_READ_FORBIDDEN'
            }

            foreach ($leaf in @(
                    '.relay-credential.dpapi.next.json',
                    '.relay-credential.dpapi.backup.json'
                )) {
                $stalePath = Join-Path $root $leaf
                [IO.File]::WriteAllText(
                    $stalePath,
                    '{}',
                    [Text.UTF8Encoding]::new($false)
                )
                { New-CddsiRealtimeRelayDpapiCredentialProvider -StateRoot $root `
                        -RunId $runId -OwnerSid $ownerSid `
                        -OwnershipTokenSha256 $ownershipToken `
                        -ClientId vm-tester-v1 -Environment production-v1 `
                        -KeyId vm-2026-07 } |
                    Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_STALE_ARTIFACT'
                { Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal `
                        -CredentialProvider $provider -Operation Sign `
                        -CanonicalRequest 'must-not-sign' } |
                    Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_UNAVAILABLE'

                $now = [DateTimeOffset]::UtcNow
                $receive = Invoke-CddsiRealtimeRelayWebSocketReceiveInternal `
                    -Session $session -Endpoint ([uri]'wss://relay.synthetic.workers.dev/') `
                    -ClientId vm-tester-v1 -CredentialProvider $provider `
                    -ClockProvider $clock -NowUtc $now -Lane host-to-vm -After 0 `
                    -MaxMessages 1 -AuthorizationExpiresAtUtc $now.AddSeconds(60)
                $receive.Status | Should -BeExactly 'Disconnected'
                $session.OperatorRelayNetworkRequestCount | Should -Be 0
                $script:ProtectedDataUnprotectCount | Should -Be $unprotectBefore
                [IO.File]::Delete($stalePath)
            }
            Assert-MockCalled Read-CddsiRealtimeRelayCredentialBlobInternal -Times 0
        }
        finally {
            [Array]::Clear($secret, 0, $secret.Length)
        }
    }

    It 'preserves the old blob and removes its candidate when roundtrip validation fails' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $runId = '99999999-9999-4999-8999-999999999999'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $stateProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root `
            -RunId $runId -OwnerSid $ownerSid -OwnershipTokenSha256 ('e' * 64)
        $oldSecret = [byte[]](1..32)
        $newSecret = [byte[]](33..64)
        try {
            $created = Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes $oldSecret -Mode Live -AcknowledgeCredentialWrite -AllowCreate
            $credentialPath = Join-Path $root '.relay-credential.dpapi.json'
            $oldRawSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $credentialPath
            Mock Test-CddsiRealtimeRelayCredentialCandidateInternal {
                throw 'SYNTHETIC_CANDIDATE_FAILURE_WITHOUT_SECRET'
            }

            { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                    -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-08 `
                    -SecretBytes $newSecret -Mode Live -AcknowledgeCredentialWrite `
                    -ExpectedCurrentCredentialBlobSha256 $created.CredentialBlobSha256 } |
                Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_PROVISION_FAILED'
            (Get-CddsiRealtimeRelayFileSha256Internal -Path $credentialPath) |
                Should -BeExactly $oldRawSha256
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.next.json') |
                Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.backup.json') |
                Should -BeFalse
        }
        finally {
            [Array]::Clear($oldSecret, 0, $oldSecret.Length)
            [Array]::Clear($newSecret, 0, $newSecret.Length)
        }
    }

    It 'keeps the old blob on atomic replacement failure and redacts the lower exception' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $runId = '12121212-1212-4212-8212-121212121212'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $stateProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root `
            -RunId $runId -OwnerSid $ownerSid -OwnershipTokenSha256 ('6' * 64)
        $oldSecret = [byte[]](2..33)
        $newSecret = [byte[]](34..65)
        try {
            $created = Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes $oldSecret -Mode Live -AcknowledgeCredentialWrite -AllowCreate
            $credentialPath = Join-Path $root '.relay-credential.dpapi.json'
            $oldRawSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $credentialPath
            Mock Move-CddsiRealtimeRelayCredentialCandidateAtomicInternal {
                throw 'LOWER_FAILURE_C:\sensitive\credential-path secret-canary'
            }

            $caught = $null
            try {
                Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                    -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-08 `
                    -SecretBytes $newSecret -Mode Live -AcknowledgeCredentialWrite `
                    -ExpectedCurrentCredentialBlobSha256 $created.CredentialBlobSha256
            }
            catch {
                $caught = $_.Exception.Message
            }
            $caught | Should -BeExactly 'REALTIME_CREDENTIAL_PROVISION_FAILED'
            $caught | Should -Not -Match '(?i)sensitive|secret-canary|credential-path'
            (Get-CddsiRealtimeRelayFileSha256Internal -Path $credentialPath) |
                Should -BeExactly $oldRawSha256
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.next.json') |
                Should -BeFalse
            Test-Path -LiteralPath (Join-Path $root '.relay-credential.dpapi.backup.json') |
                Should -BeFalse
        }
        finally {
            [Array]::Clear($oldSecret, 0, $oldSecret.Length)
            [Array]::Clear($newSecret, 0, $newSecret.Length)
        }
    }

    It 'fails before provisioning on wrong secret types, tombstone, ACL drift, and reparse verdicts' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $wrongRunId = 'aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa'
        $wrongRoot = Join-Path $TestDrive ('cddsi-realtime-relay-' + $wrongRunId)
        $wrongProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $wrongRoot `
            -RunId $wrongRunId -OwnerSid $ownerSid -OwnershipTokenSha256 ('1' * 64)
        { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $wrongProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes ([byte[]](0..30)) -Mode Live `
                -AcknowledgeCredentialWrite -AllowCreate } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_SECRET_INPUT_INVALID'
        { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $wrongProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes 'not-a-byte-array' -Mode Live `
                -AcknowledgeCredentialWrite -AllowCreate } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_SECRET_INPUT_INVALID'
        Test-Path -LiteralPath $wrongRoot | Should -BeFalse

        $tombstoneRunId = 'bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb'
        $tombstoneRoot = Join-Path $TestDrive ('cddsi-realtime-relay-' + $tombstoneRunId)
        $tombstoneProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $tombstoneRoot `
            -RunId $tombstoneRunId -OwnerSid $ownerSid -OwnershipTokenSha256 ('2' * 64)
        (Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $tombstoneProvider -Operation ValidateRoot).Valid | Should -BeTrue
        [IO.File]::WriteAllText(
            (Join-Path $tombstoneRoot '.cleanup-tombstone.json'),
            '{}',
            [Text.UTF8Encoding]::new($false)
        )
        { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $tombstoneProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes ([byte[]](0..31)) -Mode Live `
                -AcknowledgeCredentialWrite -AllowCreate } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_STATE_ROOT_INVALID'

        $aclRunId = 'cccccccc-cccc-4ccc-8ccc-cccccccccccc'
        $aclRoot = Join-Path $TestDrive ('cddsi-realtime-relay-' + $aclRunId)
        $aclProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $aclRoot `
            -RunId $aclRunId -OwnerSid $ownerSid -OwnershipTokenSha256 ('3' * 64)
        (Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $aclProvider -Operation ValidateRoot).Valid | Should -BeTrue
        $directory = [IO.DirectoryInfo]::new($aclRoot)
        $sections = [Security.AccessControl.AccessControlSections]::Owner -bor `
            [Security.AccessControl.AccessControlSections]::Access
        $security = [IO.FileSystemAclExtensions]::GetAccessControl($directory, $sections)
        $security.SetAccessRuleProtection($false, $true)
        [IO.FileSystemAclExtensions]::SetAccessControl($directory, $security)
        { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $aclProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes ([byte[]](0..31)) -Mode Live `
                -AcknowledgeCredentialWrite -AllowCreate } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_STATE_ROOT_INVALID'

        $reparseRunId = 'dddddddd-dddd-4ddd-8ddd-dddddddddddd'
        $reparseRoot = Join-Path $TestDrive ('cddsi-realtime-relay-' + $reparseRunId)
        $reparseProvider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $reparseRoot `
            -RunId $reparseRunId -OwnerSid $ownerSid -OwnershipTokenSha256 ('4' * 64)
        Mock Test-CddsiRealtimeRelayNoReparsePathInternal { return $false } `
            -ParameterFilter {
                [IO.Path]::GetFullPath($Path) -ceq [IO.Path]::GetFullPath($reparseRoot)
            }
        { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $reparseProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes ([byte[]](0..31)) -Mode Live `
                -AcknowledgeCredentialWrite -AllowCreate } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_STATE_ROOT_INVALID'
        Test-Path -LiteralPath $reparseRoot | Should -BeFalse
    }

    It 'fails Live provisioning closed on Windows PowerShell 5.1 before path access' {
        if ($PSVersionTable.PSVersion.Major -eq 7) {
            $PSVersionTable.PSVersion.Major | Should -Be 7
            return
        }
        $runId = 'eeeeeeee-eeee-4eee-8eee-eeeeeeeeeeee'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $stateProvider = New-CddsiRealtimeProvisionTestStateDescriptor `
            -StateRoot $root -RunId $runId
        { Set-CddsiRealtimeRelayDpapiCredential -StateProvider $stateProvider `
                -ClientId vm-tester-v1 -Environment production-v1 -KeyId vm-2026-07 `
                -SecretBytes ([byte[]](0..31)) -Mode Live `
                -AcknowledgeCredentialWrite -AllowCreate } |
            Should -Throw -ExpectedMessage 'REALTIME_CREDENTIAL_REQUIRES_WINDOWS_POWERSHELL7'
        Test-Path -LiteralPath $root | Should -BeFalse
    }
}

Describe 'realtime relay live static dispatch security' {
    It 'suppresses WebSocket connect task completion output before returning a transport descriptor' {
        $receiveSource =
        ${function:Invoke-CddsiRealtimeRelayWebSocketReceiveInternal}.ToString()
        [regex]::Matches(
            $receiveSource,
            '(?ms)\[void\]\s*\$socket\.ConnectAsync\(.*?\)\.GetAwaiter\(\)\.GetResult\(\)'
        ).Count | Should -Be 1
    }

    BeforeEach {
        $script:LiveClockNow = $script:RealtimeNow
        $script:LiveCredentialValidateCount = 0
        $script:LiveCredentialSignCount = 0
        $script:LiveStateCommitCount = 0
        $script:LiveWakeCount = 0
        $script:LiveAckCount = 0
        $script:LiveLoadedState = $null
        $script:LiveReceiveRaw = $null
        $script:LiveReceiveStatus = 'Connected'
        $script:LiveReceiveAdvancesClock = $false
        $script:LiveReceiveMutatesTransport = $false
        $script:LiveWakeAdvancesClock = $false
        $script:LiveAckAccepted = $true
        $script:LiveAckAuthorizationExpiry = $null

        Mock Get-CddsiRealtimeRelayLiveUtcNowInternal {
            return $script:LiveClockNow
        }
        Mock Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal {
            param($CredentialProvider, $Operation, $CanonicalRequest)
            if ($Operation -ceq 'Sign') {
                $script:LiveCredentialSignCount++
                return '9' * 64
            }
            $script:LiveCredentialValidateCount++
            return $true
        }
        Mock Invoke-CddsiRealtimeRelayOwnedStateOperationInternal {
            param($StateProvider, $Operation, $Lane, $State, $Handle)
            if ($Operation -ceq 'ValidateRoot') {
                return [pscustomobject][ordered]@{
                    Valid = $true
                    OwnerMarked = $true
                    AclProtected = $true
                    NoReparse = $true
                    Created = $false
                }
            }
            if ($Operation -ceq 'AcquireLock') {
                return [pscustomobject]@{ Held = $true }
            }
            if ($Operation -ceq 'AcquireLifecycleLock') {
                return [IO.MemoryStream]::new()
            }
            if ($Operation -ceq 'Load') {
                return Copy-CddsiRealtimeTestObject $script:LiveLoadedState
            }
            if ($Operation -ceq 'CommitAtomically') {
                $script:LiveStateCommitCount++
                $script:LiveLoadedState = Copy-CddsiRealtimeTestObject $State
            }
        }
        Mock Invoke-CddsiRealtimeRelayLiveTransportReceiveInternal {
            param(
                $TransportProvider, $CredentialProvider, $ClockProvider, $Lane, $After,
                $MaxMessages, $AuthorizationExpiresAtUtc
            )
            $session = $script:CddsiRealtimeLiveSessions[$TransportProvider.SessionId]
            $session.OperatorRelayNetworkRequestCount =
            [long]$session.OperatorRelayNetworkRequestCount + 1
            if ($script:LiveReceiveAdvancesClock) {
                $script:LiveClockNow = $script:RealtimeNow.AddSeconds(61)
            }
            if ($script:LiveReceiveMutatesTransport) {
                $TransportProvider.ClientAdapterSha256 = '0' * 64
            }
            if ($script:LiveReceiveStatus -ceq 'Disconnected') {
                return [pscustomobject][ordered]@{
                    Status = 'Disconnected'
                    Messages = @()
                    Code = 'SYNTHETIC_DISCONNECTED'
                }
            }
            return [pscustomobject][ordered]@{
                Status = 'Connected'
                Messages = @($script:LiveReceiveRaw)
            }
        }
        Mock Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal {
            param(
                $WakeProvider, $WakeEvent, $StateProvider, $AuditSession,
                $ClockProvider, $RelayContext, $RuntimeAssertion,
                $AuthorizationExpiresAtUtc
            )
            $script:LiveWakeCount++
            if ($script:LiveWakeAdvancesClock) {
                $script:LiveClockNow = $script:RealtimeNow.AddSeconds(61)
            }
            return [pscustomobject][ordered]@{
                FixedEntryInvoked = $true
                PreviouslyInvoked = $false
                Consumed = $true
                RepositoryIdentityVerified = $true
                PayloadSha256Verified = $true
                GitInvocationCount = 0L
                OperatorGitTransportCount = 0L
                OperatorLocalStateMutationCount = 0L
                OperatorCodexProcessSpawnCount = 0L
                FixedWakeEffectCount = 0L
            }
        }
        Mock Invoke-CddsiRealtimeRelayLiveTransportAckInternal {
            param(
                $TransportProvider, $CredentialProvider, $ClockProvider, $Body,
                $AuthorizationExpiresAtUtc
            )
            $script:LiveAckCount++
            $script:LiveAckAuthorizationExpiry = $AuthorizationExpiresAtUtc
            $session = $script:CddsiRealtimeLiveSessions[$TransportProvider.SessionId]
            $session.OperatorRelayNetworkRequestCount =
            [long]$session.OperatorRelayNetworkRequestCount + 1
            return [pscustomobject][ordered]@{ Accepted = [bool]$script:LiveAckAccepted }
        }
    }

    It 'uses exact data-only Live descriptors and blocks forged executable mutation' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        (Get-Command Invoke-CddsiRealtimeRelayWatcher -CommandType Function).Parameters.Keys |
            Should -Not -Contain 'TrustedLiveSessionId'
        $harness = New-CddsiRealtimeTestLiveHarness
        $sessionId = $harness.Context.Providers.Transport.SessionId
        try {
            { Copy-CddsiRealtimeRelayPlainDataInternal -Value $harness.Context } |
                Should -Not -Throw
            (Test-CddsiRealtimeRelayStateProviderContractInternal `
                    -StateProvider $harness.StateProvider -VerifySource) | Should -BeTrue
            (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
                    -CredentialProvider $harness.CredentialProvider `
                    -ClientId vm-tester-v1 `
                    -StateRootBindingToken $harness.StateProvider.BindingToken -VerifySource) |
                Should -BeTrue
            (Test-CddsiRealtimeRelayLiveTransportProviderContractInternal `
                    -TransportProvider $harness.Context.Providers.Transport `
                    -VerifySource -VerifySession) | Should -BeTrue
            (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
                    -ClockProvider $harness.Context.Providers.Clock -VerifySource) |
                Should -BeTrue
            @($harness.Context.Providers.PSObject.Properties.Value | ForEach-Object {
                    $_.PSObject.Properties.Value
                } | Where-Object { $_ -is [scriptblock] -or $_ -is [Delegate] }).Count |
                Should -Be 0

            $harness.Context.Providers.Transport | Add-Member -NotePropertyName Receive `
                -NotePropertyValue { throw 'UNTRUSTED_LIVE_CODE' }
            $result = Invoke-CddsiRealtimeRelayWatcher `
                -RelayExecutionContext $harness.Context -Lane host-to-vm `
                -RuntimeAssertion $harness.Assertion -Mode Live
            $result.Status | Should -BeExactly 'BLOCKED'
            $result.Code | Should -BeExactly 'REALTIME_RUNTIME_ASSERTION_INVALID'
            $script:LiveCredentialValidateCount | Should -Be 0
            $script:LiveWakeCount | Should -Be 0
            $script:LiveAckCount | Should -Be 0
            $result.OperatorRelayNetworkRequestCount | Should -Be 0
        }
        finally {
            [void]$script:CddsiRealtimeLiveSessions.Remove($sessionId)
        }
    }

    It 'does not use a caller-forged session id for trusted cleanup' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $victim = New-CddsiRealtimeTestLiveHarness
        $forged = New-CddsiRealtimeTestLiveHarness
        $victimSessionId = $victim.Context.Providers.Transport.SessionId
        $forgedSessionId = $forged.Context.Providers.Transport.SessionId
        $victimSocket = New-CddsiRealtimeTestTrackedSocket
        $script:CddsiRealtimeLiveSessions[$victimSessionId].Socket = $victimSocket
        try {
            $forged.Context.Providers.Transport.SessionId = $victimSessionId
            $result = Invoke-CddsiRealtimeRelayWatcher `
                -RelayExecutionContext $forged.Context -Lane host-to-vm `
                -RuntimeAssertion $forged.Assertion -Mode Live
            $result.Status | Should -BeExactly 'BLOCKED'
            $result.Code | Should -BeExactly 'REALTIME_RUNTIME_BINDING_MISMATCH'
            $script:CddsiRealtimeLiveSessions.ContainsKey($victimSessionId) |
                Should -BeTrue
            $script:CddsiRealtimeLiveSessions.ContainsKey($forgedSessionId) |
                Should -BeFalse
            $victimSocket.AbortCount | Should -Be 0
            $victimSocket.DisposeCount | Should -Be 0
        }
        finally {
            [void]$script:CddsiRealtimeLiveSessions.Remove($victimSessionId)
            [void]$script:CddsiRealtimeLiveSessions.Remove($forgedSessionId)
        }
    }

    It 'requires an exact bounded runtime assertion before any provider operation' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        foreach ($case in @('EXTRA_PROPERTY', 'OVERLONG')) {
            $harness = if ($case -ceq 'OVERLONG') {
                New-CddsiRealtimeTestLiveHarness `
                    -IssuedAtUtc $script:RealtimeNow `
                    -ExpiresAtUtc $script:RealtimeNow.AddSeconds(601)
            }
            else {
                New-CddsiRealtimeTestLiveHarness
            }
            $sessionId = $harness.Context.Providers.Transport.SessionId
            try {
                if ($case -ceq 'EXTRA_PROPERTY') {
                    $harness.Assertion | Add-Member -NotePropertyName FreeText `
                        -NotePropertyValue 'forbidden'
                }
                $result = Invoke-CddsiRealtimeRelayWatcher `
                    -RelayExecutionContext $harness.Context -Lane host-to-vm `
                    -RuntimeAssertion $harness.Assertion -Mode Live
                $result.Status | Should -BeExactly 'BLOCKED'
                $result.Code | Should -BeExactly 'REALTIME_RUNTIME_ASSERTION_INVALID'
                $result.OperatorRelayNetworkRequestCount | Should -Be 0
            }
            finally {
                [void]$script:CddsiRealtimeLiveSessions.Remove($sessionId)
            }
        }
        $script:LiveCredentialValidateCount | Should -Be 0
        $script:LiveStateCommitCount | Should -Be 0
        $script:LiveWakeCount | Should -Be 0
        $script:LiveAckCount | Should -Be 0
    }

    It 'rechecks expiry after receive before wake and records relay attempts only' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $sessionId = $harness.Context.Providers.Transport.SessionId
        $socket = New-CddsiRealtimeTestTrackedSocket
        $script:CddsiRealtimeLiveSessions[$sessionId].Socket = $socket
        $script:LiveReceiveRaw = New-CddsiRealtimeTestMessage
        $script:LiveReceiveAdvancesClock = $true

        $result = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $harness.Context -Lane host-to-vm `
            -RuntimeAssertion $harness.Assertion -Mode Live -MaxMessages 1

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        $script:LiveWakeCount | Should -Be 0
        $script:LiveStateCommitCount | Should -Be 0
        $script:LiveCredentialSignCount | Should -Be 0
        $script:LiveAckCount | Should -Be 0
        $script:CddsiRealtimeLiveSessions.ContainsKey($sessionId) | Should -BeFalse
        $socket.AbortCount | Should -Be 1
        $socket.DisposeCount | Should -Be 1
        $result.ProductNetworkRequestCount | Should -Be 0
        $result.RealNetworkAccessCount | Should -Be 0
        $result.OperatorRelayNetworkRequestCount | Should -Be 1
    }

    It 'rechecks expiry after fixed wake before state commit and ACK' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $sessionId = $harness.Context.Providers.Transport.SessionId
        $socket = New-CddsiRealtimeTestTrackedSocket
        $script:CddsiRealtimeLiveSessions[$sessionId].Socket = $socket
        $script:LiveReceiveRaw = New-CddsiRealtimeTestMessage
        $script:LiveWakeAdvancesClock = $true

        $result = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $harness.Context -Lane host-to-vm `
            -RuntimeAssertion $harness.Assertion -Mode Live -MaxMessages 1

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        $script:LiveWakeCount | Should -Be 1
        $script:LiveStateCommitCount | Should -Be 0
        $script:LiveCredentialSignCount | Should -Be 0
        $script:LiveAckCount | Should -Be 0
        $script:CddsiRealtimeLiveSessions.ContainsKey($sessionId) | Should -BeFalse
        $socket.AbortCount | Should -Be 1
        $socket.DisposeCount | Should -Be 1
    }

    It 'rechecks expiry for an already-consumed replay before ACK signing or sending' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $raw = New-CddsiRealtimeTestMessage
        $validation = Test-CddsiRealtimeRelayNotificationInternal `
            -RawMessage $raw -NowUtc $script:RealtimeNow
        $state = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        $state.LastConsumedSequence = 1
        $state.LastMessageSha256 = $validation.MessageSha256
        $state.ProcessedMessages = @([pscustomobject][ordered]@{
                MessageId = $validation.Message.MessageId
                Sequence = 1L
                MessageSha256 = $validation.MessageSha256
                PayloadSha256 = $validation.Message.PayloadSha256
            })
        $state.Revision = 1L
        $script:LiveLoadedState = $state
        $script:LiveReceiveRaw = $raw
        $script:LiveReceiveAdvancesClock = $true
        $harness = New-CddsiRealtimeTestLiveHarness

        $result = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $harness.Context -Lane host-to-vm `
            -RuntimeAssertion $harness.Assertion -Mode Live -MaxMessages 1

        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        $result.DuplicateCount | Should -Be 1
        $script:LiveWakeCount | Should -Be 0
        $script:LiveStateCommitCount | Should -Be 0
        $script:LiveCredentialSignCount | Should -Be 0
        $script:LiveAckCount | Should -Be 0
    }

    It 'passes assertion expiry to ACK and returns successful operator-only attempt counts' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $sessionId = $harness.Context.Providers.Transport.SessionId
        $socket = New-CddsiRealtimeTestTrackedSocket
        $script:CddsiRealtimeLiveSessions[$sessionId].Socket = $socket
        $script:LiveReceiveRaw = New-CddsiRealtimeTestMessage

        $result = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $harness.Context -Lane host-to-vm `
            -RuntimeAssertion $harness.Assertion -Mode Live -MaxMessages 1

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Changed | Should -BeTrue
        $result.ProductNetworkRequestCount | Should -Be 0
        $result.RealNetworkAccessCount | Should -Be 0
        $result.OperatorRelayNetworkRequestCount | Should -Be 2
        $script:LiveAckAuthorizationExpiry | Should -Be `
            $script:RealtimeNow.AddSeconds(60)
        $script:CddsiRealtimeLiveSessions.ContainsKey($sessionId) | Should -BeFalse
        $socket.AbortCount | Should -Be 1
        $socket.DisposeCount | Should -Be 1
    }

    It 'preserves a trusted attempt count after post-attempt transport descriptor drift' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $sessionId = $harness.Context.Providers.Transport.SessionId
        $socket = New-CddsiRealtimeTestTrackedSocket -ThrowOnAbort -ThrowOnDispose
        $script:CddsiRealtimeLiveSessions[$sessionId].Socket = $socket
        $script:LiveReceiveStatus = 'Disconnected'
        $script:LiveReceiveMutatesTransport = $true
        $result = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $harness.Context -Lane host-to-vm `
            -RuntimeAssertion $harness.Assertion -Mode Live `
            -MaxMessages 1 -MaxReconnectAttempts 2
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'REALTIME_RUNTIME_BINDING_MISMATCH'
        $result.OperatorRelayNetworkRequestCount | Should -Be 1
        $result.ProductNetworkRequestCount | Should -Be 0
        $script:CddsiRealtimeLiveSessions.ContainsKey($sessionId) | Should -BeFalse
        $socket.AbortCount | Should -Be 1
        $socket.DisposeCount | Should -Be 1
    }

    It 'counts failed receive and ACK attempts before returning fixed failure codes' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $receiveHarness = New-CddsiRealtimeTestLiveHarness
        $receiveSessionId = $receiveHarness.Context.Providers.Transport.SessionId
        $receiveSocket = New-CddsiRealtimeTestTrackedSocket
        $script:CddsiRealtimeLiveSessions[$receiveSessionId].Socket = $receiveSocket
        $script:LiveReceiveStatus = 'Disconnected'
        $receiveResult = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $receiveHarness.Context -Lane host-to-vm `
            -RuntimeAssertion $receiveHarness.Assertion -Mode Live `
            -MaxMessages 1 -MaxReconnectAttempts 1
        $receiveResult.Code | Should -BeExactly 'REALTIME_RECONNECT_EXHAUSTED'
        $receiveResult.OperatorRelayNetworkRequestCount | Should -Be 1
        $script:CddsiRealtimeLiveSessions.ContainsKey($receiveSessionId) |
            Should -BeFalse
        $receiveSocket.DisposeCount | Should -Be 1

        $script:LiveReceiveStatus = 'Connected'
        $script:LiveReceiveRaw = New-CddsiRealtimeTestMessage
        $script:LiveAckAccepted = $false
        $ackHarness = New-CddsiRealtimeTestLiveHarness
        $ackSessionId = $ackHarness.Context.Providers.Transport.SessionId
        $ackSocket = New-CddsiRealtimeTestTrackedSocket
        $script:CddsiRealtimeLiveSessions[$ackSessionId].Socket = $ackSocket
        $ackResult = Invoke-CddsiRealtimeRelayWatcher `
            -RelayExecutionContext $ackHarness.Context -Lane host-to-vm `
            -RuntimeAssertion $ackHarness.Assertion -Mode Live `
            -MaxMessages 1 -MaxReconnectAttempts 1
        $ackResult.Code | Should -BeExactly 'REALTIME_ACK_RETRY_EXHAUSTED'
        $ackResult.OperatorRelayNetworkRequestCount | Should -Be 2
        $ackResult.ProductNetworkRequestCount | Should -Be 0
        $script:CddsiRealtimeLiveSessions.ContainsKey($ackSessionId) | Should -BeFalse
        $ackSocket.DisposeCount | Should -Be 1
    }

    It 'fails an expired ACK before signing and never increments a network attempt' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $harness = New-CddsiRealtimeTestLiveHarness
        $session = [pscustomobject][ordered]@{
            Socket = $null
            OperatorRelayNetworkRequestCount = 0L
        }
        $script:LiveClockNow = $script:RealtimeNow.AddSeconds(61)

        { Invoke-CddsiRealtimeRelayAckInternal -Session $session `
                -Endpoint ([uri]$harness.Context.Endpoint) `
                -ClientId $harness.Context.ClientId `
                -CredentialProvider $harness.CredentialProvider `
                -ClockProvider $harness.Context.Providers.Clock `
                -NowUtc $script:RealtimeNow -Body '{}' `
                -AuthorizationExpiresAtUtc $script:RealtimeNow.AddSeconds(60) } |
            Should -Throw -ExpectedMessage 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        $script:LiveCredentialSignCount | Should -Be 0
        $session.OperatorRelayNetworkRequestCount | Should -Be 0
        [void]$script:CddsiRealtimeLiveSessions.Remove(
            $harness.Context.Providers.Transport.SessionId
        )
    }
}

Describe 'realtime relay owned state persistence' {
    It 'uses an owner-marked protected root, atomic state, and tombstoned cleanup' {
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $liveHarness = $null
        if ($PSVersionTable.PSVersion.Major -eq 7) {
            $liveHarness = New-CddsiRealtimeTestLiveHarness `
                -RunId '11111111-1111-4111-8111-111111111111'
            $provider = $liveHarness.StateProvider
            $root = $provider.StateRoot
        }
        else {
            $runId = '11111111-1111-4111-8111-111111111111'
            $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
            $provider = New-CddsiRealtimeRelayOwnedStateProvider `
                -StateRoot $root -RunId $runId -OwnerSid $ownerSid `
                -OwnershipTokenSha256 ('a' * 64)
        }
        (Test-CddsiRealtimeRelayStateProviderContractInternal `
                -StateProvider $provider -VerifySource) | Should -BeTrue
        @($provider.PSObject.Properties.Value | Where-Object {
                $_ -is [scriptblock] -or $_ -is [Delegate]
            }).Count | Should -Be 0

        $validated = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation ValidateRoot
        $validated.Valid | Should -BeTrue
        $validated.OwnerMarked | Should -BeTrue
        $validated.AclProtected | Should -BeTrue
        $validated.NoReparse | Should -BeTrue

        $lock = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation AcquireLock
        { Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation AcquireLock } | Should -Throw
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation ReleaseLock -Handle $lock

        $state = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation CommitAtomically -State $state
        $loaded = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation Load -Lane host-to-vm
        (Test-CddsiRealtimeRelayStateInternal -State $loaded -Lane host-to-vm) | Should -BeTrue

        if ($PSVersionTable.PSVersion.Major -eq 7) {
            $cleanupContract = New-CddsiRealtimeCleanupTestContract `
                -StateProvider $provider -Mode Live `
                -ClientId $liveHarness.Context.ClientId
            (Test-CddsiRealtimeRelayRootsDisjointInternal `
                    -FirstRoot $provider.StateRoot `
                    -SecondRoot $liveHarness.WakeProvider.Binding.StateRoot) |
                Should -BeTrue
            Test-Path -LiteralPath $liveHarness.WakeProvider.CodexTempRoot |
                Should -BeTrue
            $cleanup = Remove-CddsiRealtimeRelayOwnedState `
                -RelayExecutionContext $liveHarness.Context `
                -StateProvider $provider -RuntimeAssertion $cleanupContract.Assertion `
                -Mode Live -AcknowledgeOwnedStateCleanup
        }
        else {
            { Remove-CddsiRealtimeRelayOwnedState `
                    -RelayExecutionContext (
                    New-CddsiRealtimeCleanupTestContract `
                        -StateProvider $provider -Mode Live
                ).Context -StateProvider $provider -RuntimeAssertion (
                    New-CddsiRealtimeCleanupTestContract `
                        -StateProvider $provider -Mode Live
                ).Assertion -Mode Live -AcknowledgeOwnedStateCleanup } |
                Should -Throw -ExpectedMessage 'REALTIME_CLEANUP_CONTEXT_INVALID'
            $cleanup = Remove-CddsiRealtimeRelayOwnedStateRootInternal `
                -StateRoot $provider.StateRoot -RunId $provider.RunId `
                -OwnerSid $provider.OwnerSid `
                -OwnershipTokenSha256 $provider.OwnershipTokenSha256
        }
        $cleanup.SensitiveStateRemoved | Should -BeTrue
        $cleanup.RootTombstoned | Should -BeTrue
        $cleanup.RootRemoved | Should -BeFalse
        Test-Path -LiteralPath (Join-Path $root 'watcher-state.json') | Should -BeFalse
        (Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot).Valid | Should -BeFalse
    }

    It 'does not create a missing root during cleanup' {
        if ($PSVersionTable.PSVersion.Major -eq 7) {
            $liveHarness = New-CddsiRealtimeTestLiveHarness `
                -RunId '22222222-2222-4222-8222-222222222222'
            $provider = $liveHarness.StateProvider
            $root = $provider.StateRoot
            $cleanupContract = New-CddsiRealtimeCleanupTestContract `
                -StateProvider $provider -Mode Live `
                -ClientId $liveHarness.Context.ClientId
            { Remove-CddsiRealtimeRelayOwnedState `
                    -RelayExecutionContext $liveHarness.Context `
                    -StateProvider $provider -RuntimeAssertion $cleanupContract.Assertion `
                    -Mode Live -AcknowledgeOwnedStateCleanup } |
                Should -Throw '*REALTIME_STATE_CLEANUP_ROOT_INVALID*'
        }
        else {
            $runId = '22222222-2222-4222-8222-222222222222'
            $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
            $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        }
        Test-Path -LiteralPath $root | Should -BeFalse
    }

    It 'plans cleanup without touching a path or provider in TestSafe and DryRun' {
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $stateProvider = [pscustomobject][ordered]@{
                BindingToken = 'f' * 64
                ForbiddenPath = 'Z:\must-not-be-read'
            }
            $contract = New-CddsiRealtimeCleanupTestContract `
                -StateProvider $stateProvider -Mode $mode
            $result = Remove-CddsiRealtimeRelayOwnedState `
                -RelayExecutionContext $contract.Context -StateProvider $stateProvider `
                -RuntimeAssertion $contract.Assertion -Mode $mode
            $result.SchemaVersion | Should -BeExactly `
                'cddsi-realtime-relay-cleanup-result-v1'
            $result.Status | Should -BeExactly 'PLANNED'
            $result.Changed | Should -BeFalse
            $result.SensitiveStateRemoved | Should -BeFalse
            Assert-CddsiRealtimeZeroMetrics -Result $result
        }
    }

    It 'rejects a fabricated Live context and requires the exact registered state object' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $liveHarness = New-CddsiRealtimeTestLiveHarness `
            -RunId '36363636-3636-4636-8636-363636363636'
        $provider = $liveHarness.StateProvider
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot)
        $forgedContext = Copy-CddsiRealtimeTestObject $liveHarness.Context
        $contract = New-CddsiRealtimeCleanupTestContract -StateProvider $provider `
            -Mode Live -ClientId $liveHarness.Context.ClientId
        $sessionId = $liveHarness.Context.Providers.Transport.SessionId
        [object]::ReferenceEquals($liveHarness.Context, $forgedContext) |
            Should -BeFalse
        @($script:CddsiRealtimeLiveSessions.Keys).Count | Should -Be 1
        [object]::ReferenceEquals(
            $script:CddsiRealtimeLiveSessions[$sessionId].ContextReference.PSObject,
            $forgedContext.PSObject
        ) | Should -BeFalse
        (Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
                -RelayContext $liveHarness.Context) | Should -BeExactly $sessionId
        (Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
                -RelayContext $forgedContext) | Should -BeNullOrEmpty

        { Remove-CddsiRealtimeRelayOwnedState `
                -RelayExecutionContext $forgedContext -StateProvider $provider `
                -RuntimeAssertion $contract.Assertion -Mode Live `
                -AcknowledgeOwnedStateCleanup } |
            Should -Throw -ExpectedMessage 'REALTIME_CLEANUP_CONTEXT_INVALID'
        Test-Path -LiteralPath (Join-Path $provider.StateRoot '.cleanup-tombstone.json') |
            Should -BeFalse
        $script:CddsiRealtimeLiveSessions.ContainsKey($sessionId) | Should -BeTrue
        Close-CddsiRealtimeRelayTrustedLiveSessionInternal -TrustedSessionId $sessionId
    }

    It 'uses a short lifecycle gate without starving publisher behind an idle watcher' {
        $runId = '35353535-3535-4535-8535-353535353535'
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $provider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root -RunId $runId `
            -OwnerSid $ownerSid -OwnershipTokenSha256 ('d' * 64)
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot)
        $watcherLock = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation AcquireLock
        $lifecycleLock = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation AcquireLifecycleLock
        $publisherLock = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation AcquirePublisherLock -Lane host-to-vm
        $publisherLock | Should -Not -BeNullOrEmpty
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation ReleasePublisherLock -Lane host-to-vm `
            -Handle $publisherLock
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation ReleaseLifecycleLock -Handle $lifecycleLock

        { Remove-CddsiRealtimeRelayOwnedStateRootInternal `
                -StateRoot $provider.StateRoot -RunId $provider.RunId `
                -OwnerSid $provider.OwnerSid `
                -OwnershipTokenSha256 $provider.OwnershipTokenSha256 } | Should -Throw
        Test-Path -LiteralPath (Join-Path $root '.cleanup-tombstone.json') |
            Should -BeFalse
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation ReleaseLock -Handle $watcherLock

        $publisherLock = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation AcquirePublisherLock -Lane host-to-vm
        { Remove-CddsiRealtimeRelayOwnedStateRootInternal `
                -StateRoot $provider.StateRoot -RunId $provider.RunId `
                -OwnerSid $provider.OwnerSid `
                -OwnershipTokenSha256 $provider.OwnershipTokenSha256 } | Should -Throw
        Test-Path -LiteralPath (Join-Path $root '.cleanup-tombstone.json') |
            Should -BeFalse
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation ReleasePublisherLock -Lane host-to-vm `
            -Handle $publisherLock

        $cleanup = Remove-CddsiRealtimeRelayOwnedStateRootInternal `
            -StateRoot $provider.StateRoot -RunId $provider.RunId `
            -OwnerSid $provider.OwnerSid `
            -OwnershipTokenSha256 $provider.OwnershipTokenSha256
        $cleanup.RootTombstoned | Should -BeTrue
    }

    It 'rejects reparse lifecycle and watcher lock leaves before any cleanup mutation' {
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $cases = @(
            [pscustomobject]@{
                RunId = '45454545-4545-4545-8545-454545454545'
                Leaf = '.lifecycle.lock'
                OtherLeaf = '.watcher.lock'
                Token = 'e' * 64
            },
            [pscustomobject]@{
                RunId = '46464646-4646-4646-8646-464646464646'
                Leaf = '.watcher.lock'
                OtherLeaf = '.lifecycle.lock'
                Token = 'f' * 64
            }
        )
        foreach ($case in $cases) {
            $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $case.RunId)
            $provider = New-CddsiRealtimeRelayOwnedStateProvider `
                -StateRoot $root -RunId $case.RunId -OwnerSid $ownerSid `
                -OwnershipTokenSha256 $case.Token
            [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $provider -Operation ValidateRoot)
            $externalTarget = Join-Path $TestDrive ('external-lock-target-' + $case.RunId)
            [void][IO.Directory]::CreateDirectory($externalTarget)
            $sentinelPath = Join-Path $externalTarget 'sentinel.txt'
            [IO.File]::WriteAllText(
                $sentinelPath, 'external-sentinel', [Text.UTF8Encoding]::new($false)
            )
            $lockReparsePath = Join-Path $root $case.Leaf
            try {
                New-Item -ItemType Junction -Path $lockReparsePath `
                    -Target $externalTarget -ErrorAction Stop | Out-Null
                (Test-CddsiRealtimeRelayStateFilePathSafeInternal `
                        -Path $lockReparsePath) | Should -BeFalse

                { Remove-CddsiRealtimeRelayOwnedStateRootInternal `
                        -StateRoot $provider.StateRoot -RunId $provider.RunId `
                        -OwnerSid $provider.OwnerSid `
                        -OwnershipTokenSha256 $provider.OwnershipTokenSha256 } |
                    Should -Throw -ExpectedMessage 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'

                [IO.File]::ReadAllText($sentinelPath) |
                    Should -BeExactly 'external-sentinel'
                Test-Path -LiteralPath (Join-Path $root '.cleanup-tombstone.json') |
                    Should -BeFalse
                Test-Path -LiteralPath (Join-Path $root $case.OtherLeaf) |
                    Should -BeFalse
                @([IO.Directory]::EnumerateFileSystemEntries($root)).Count |
                    Should -Be 2
            }
            finally {
                if ([IO.Directory]::Exists($lockReparsePath)) {
                    [IO.Directory]::Delete($lockReparsePath, $false)
                }
            }
        }
    }

    It 'refuses Live cleanup when publisher chain state has not been explicitly retired' {
        if (-not (Test-CddsiRealtimePowerShell7OnlyCase)) { return }
        $liveHarness = New-CddsiRealtimeTestLiveHarness `
            -RunId '34343434-3434-4434-8434-343434343434'
        $provider = $liveHarness.StateProvider
        $root = $provider.StateRoot
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot)
        $publisherState = New-CddsiRealtimeRelayPublisherStateInternal -Lane host-to-vm
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation CommitPublisher -State $publisherState
        $contract = New-CddsiRealtimeCleanupTestContract -StateProvider $provider `
            -Mode Live -ClientId $liveHarness.Context.ClientId

        { Remove-CddsiRealtimeRelayOwnedState `
                -RelayExecutionContext $liveHarness.Context -StateProvider $provider `
                -RuntimeAssertion $contract.Assertion -Mode Live `
                -AcknowledgeOwnedStateCleanup } |
            Should -Throw -ExpectedMessage 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'
        Test-Path -LiteralPath (Join-Path $root 'publisher-state-host-to-vm.json') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $root '.cleanup-tombstone.json') |
            Should -BeFalse
    }

    It 'promotes a sole valid next state and discards next when committed state exists' {
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $promoteRunId = '13131313-1313-4313-8313-131313131313'
        $promoteRoot = Join-Path $TestDrive ('cddsi-realtime-relay-' + $promoteRunId)
        $promoteProvider = New-CddsiRealtimeRelayOwnedStateProvider `
            -StateRoot $promoteRoot -RunId $promoteRunId -OwnerSid $ownerSid `
            -OwnershipTokenSha256 ('7' * 64)
        (Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $promoteProvider -Operation ValidateRoot).Valid | Should -BeTrue
        $candidate = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        $candidate.Revision = 3L
        $candidateRaw = ConvertTo-Json -Compress -Depth 6 -InputObject $candidate
        [IO.File]::WriteAllText(
            (Join-Path $promoteRoot 'watcher-state.next.json'),
            $candidateRaw,
            [Text.UTF8Encoding]::new($false)
        )
        $promoted = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $promoteProvider -Operation Load -Lane host-to-vm
        $promoted.Revision | Should -Be 3
        Test-Path -LiteralPath (Join-Path $promoteRoot 'watcher-state.json') |
            Should -BeTrue
        Test-Path -LiteralPath (Join-Path $promoteRoot 'watcher-state.next.json') |
            Should -BeFalse

        $discardRunId = '14141414-1414-4414-8414-141414141414'
        $discardRoot = Join-Path $TestDrive ('cddsi-realtime-relay-' + $discardRunId)
        $discardProvider = New-CddsiRealtimeRelayOwnedStateProvider `
            -StateRoot $discardRoot -RunId $discardRunId -OwnerSid $ownerSid `
            -OwnershipTokenSha256 ('8' * 64)
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $discardProvider -Operation ValidateRoot)
        $committed = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        $committed.Revision = 4L
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $discardProvider -Operation CommitAtomically -State $committed
        $statePath = Join-Path $discardRoot 'watcher-state.json'
        $committedSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $statePath
        $superseded = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        $superseded.Revision = 5L
        [IO.File]::WriteAllText(
            (Join-Path $discardRoot 'watcher-state.next.json'),
            (ConvertTo-Json -Compress -Depth 6 -InputObject $superseded),
            [Text.UTF8Encoding]::new($false)
        )
        $loaded = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $discardProvider -Operation Load -Lane host-to-vm
        $loaded.Revision | Should -Be 4
        (Get-CddsiRealtimeRelayFileSha256Internal -Path $statePath) |
            Should -BeExactly $committedSha256
        Test-Path -LiteralPath (Join-Path $discardRoot 'watcher-state.next.json') |
            Should -BeFalse
    }

    It 'fails closed on a partial sole next state without promoting it' {
        $runId = '15151515-1515-4515-8515-151515151515'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $provider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root -RunId $runId `
            -OwnerSid $ownerSid -OwnershipTokenSha256 ('9' * 64)
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot)
        $nextPath = Join-Path $root 'watcher-state.next.json'
        [IO.File]::WriteAllText(
            $nextPath,
            '{"SchemaVersion":',
            [Text.UTF8Encoding]::new($false)
        )
        { Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation Load -Lane host-to-vm } |
            Should -Throw -ExpectedMessage 'REALTIME_STATE_JSON_INVALID'
        Test-Path -LiteralPath (Join-Path $root 'watcher-state.json') |
            Should -BeFalse
        Test-Path -LiteralPath $nextPath | Should -BeTrue
    }

    It 'preserves committed state across one atomic replace failure and retries idempotently' {
        $runId = '16161616-1616-4616-8616-161616161616'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $provider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root -RunId $runId `
            -OwnerSid $ownerSid -OwnershipTokenSha256 ('a' * 64)
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot)
        $oldState = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        $oldState.Revision = 6L
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation CommitAtomically -State $oldState
        $statePath = Join-Path $root 'watcher-state.json'
        $oldSha256 = Get-CddsiRealtimeRelayFileSha256Internal -Path $statePath
        $newState = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        $newState.Revision = 7L
        $script:StateAtomicMoveCount = 0
        Mock Move-CddsiRealtimeRelayStateCandidateAtomicInternal {
            param($NextPath, $StatePath, $BackupPath, $ReplaceExisting)
            $script:StateAtomicMoveCount++
            if ($script:StateAtomicMoveCount -eq 1) {
                throw 'SYNTHETIC_ATOMIC_REPLACE_FAILURE'
            }
            if ($ReplaceExisting) {
                [IO.File]::Replace($NextPath, $StatePath, $BackupPath, $true)
                if ([IO.File]::Exists($BackupPath)) {
                    [IO.File]::Delete($BackupPath)
                }
            }
            else {
                [IO.File]::Move($NextPath, $StatePath)
            }
        }
        { Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation CommitAtomically -State $newState } |
            Should -Throw -ExpectedMessage 'SYNTHETIC_ATOMIC_REPLACE_FAILURE'
        (Get-CddsiRealtimeRelayFileSha256Internal -Path $statePath) |
            Should -BeExactly $oldSha256
        Test-Path -LiteralPath (Join-Path $root 'watcher-state.next.json') |
            Should -BeTrue
        $recovered = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation Load -Lane host-to-vm
        $recovered.Revision | Should -Be 6
        Test-Path -LiteralPath (Join-Path $root 'watcher-state.next.json') |
            Should -BeFalse
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $provider -Operation CommitAtomically -State $newState
        (Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation Load -Lane host-to-vm).Revision |
            Should -Be 7
    }

    It 'rejects unsafe state and next file reparse verdicts before reading or writing' {
        $runId = '17171717-1717-4717-8717-171717171717'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)
        $ownerSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $provider = New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root -RunId $runId `
            -OwnerSid $ownerSid -OwnershipTokenSha256 ('b' * 64)
        [void](Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $provider -Operation ValidateRoot)
        $state = New-CddsiRealtimeRelayInitialStateInternal -Lane host-to-vm
        foreach ($leaf in @('watcher-state.next.json', 'watcher-state.json')) {
            $script:UnsafeStatePath = [IO.Path]::GetFullPath((Join-Path $root $leaf))
            Mock Test-CddsiRealtimeRelayStateFilePathSafeInternal { return $false } `
                -ParameterFilter { [IO.Path]::GetFullPath($Path) -ceq $script:UnsafeStatePath }
            { Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $provider -Operation Load -Lane host-to-vm } |
                Should -Throw -ExpectedMessage 'REALTIME_STATE_FILE_REPARSE'
            { Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $provider -Operation CommitAtomically -State $state } |
                Should -Throw -ExpectedMessage 'REALTIME_STATE_FILE_REPARSE'
        }
    }

    It 'rejects a non-current-user ACL identity before touching a path' {
        $runId = '33333333-3333-4333-8333-333333333333'
        $root = Join-Path $TestDrive ('cddsi-realtime-relay-' + $runId)

        {
            New-CddsiRealtimeRelayOwnedStateProvider -StateRoot $root -RunId $runId `
                -OwnerSid 'S-1-5-18' -OwnershipTokenSha256 ('c' * 64)
        } | Should -Throw '*REALTIME_STATE_OWNER_NOT_CURRENT_USER*'
        Test-Path -LiteralPath $root | Should -BeFalse
    }
}
