@{
    SchemaVersion  = 2
    ProtocolVersion = 'cddsi-vm-test-relay-v1'
    Lane            = 'Fast'

    ProductRemote = @{
        RepositoryToken         = 'github.com/LXZ56156/claude-desktop-deepseek-installer'
        RepositoryId            = 1301870422
        RepositoryNodeId        = 'R_kgDOTZj3Vg'
        VisibilityRequired       = 'PUBLIC'
        HostWriteRefPattern      = 'refs/heads/codex/repair/*'
        VmReadOnly               = $true
        VmDisallowedCapabilities = @(
            'CreateBranch'
            'CreateTag'
            'CreateRelease'
            'CreateIssue'
            'CreatePullRequest'
            'Push'
            'WorkflowDispatch'
        )
    }

    ControlPlane = @{
        Topology = 'DirectionalRepositoryPair'
        HostToVm = @{
            RepositoryToken = 'github.com/LXZ56156/cddsi-host-to-vm'
            RepositoryId    = 1301870499
            RepositoryNodeId = 'R_kgDOTZj3ow'
            VisibilityRequired = 'PUBLIC'
            Ref             = 'refs/heads/main'
            GenesisCommitSha = '179cb95df432392e6ecd901c9008c01e4b41003e'
            LogicalOutbox   = 'host-to-vm'
            WriterRole      = 'HostCoordinator'
            ReaderRole      = 'VmTester'
        }
        VmToHost = @{
            RepositoryToken = 'github.com/LXZ56156/cddsi-vm-to-host'
            RepositoryId    = 1301870545
            RepositoryNodeId = 'R_kgDOTZj30Q'
            VisibilityRequired = 'PUBLIC'
            Ref             = 'refs/heads/main'
            GenesisCommitSha = 'd88fe54d624bb5699751522e80e1cc4cd367ec33'
            LogicalOutbox   = 'vm-to-host'
            WriterRole      = 'VmTester'
            ReaderRole      = 'HostCoordinator'
        }
        ForcePushAllowed      = $false
        HistoryRewriteAllowed = $false
        DeletePublishedMessage = $false
        SingleActiveCycle      = $true
        CompareAndSwapRequired = $true
        PinnedGenesisRequired   = $true
        ServerProtectedHistoryRequired = $true
        RepositoryVisibilityRequired   = 'PUBLIC'
    }

    TransportRuntime = @{
        ContractVersion         = 'cddsi-fast-lane-git-outbox-v1'
        MessagePathPattern      = '^outbox/[0-9]{12}-[a-f0-9-]{36}\.json$'
        StateFileName           = 'relay-state.json'
        LockFileName            = 'relay-state.lock'
        MaximumMessagesPerPoll  = 32
        MaximumRuntimeSeconds   = 45
        MaximumOutputBytes      = 65536
        MaximumRetryCount       = 0
        FastForwardOnly         = $true
        ForcePushAllowed        = $false
        DeleteRefAllowed        = $false
        ExecutePayloadText      = $false
    }

    SshTrust = @{
        GitHubHost                    = 'github.com'
        OpenSshToolId                 = 'OpenSSH'
        OpenSshVmPath                 = '%PROGRAMFILES%\Git\usr\bin\ssh.exe'
        KnownHostsSourcePath          = 'operator/fast-lane/trust/github-known-hosts'
        KnownHostsSha256              = 'c73ac5d045cd2a359d2202b79b551fb22a638463d5ddbe5ed59b1b3998869c88'
        StrictHostKeyCheckingRequired = $true
    }

    Envelope = @{
        SignatureMustBeNull = $true
        MaximumBodyBytes    = 65536
        MaximumClockSkewSec = 120
        MaximumAgeSec       = 900
        RequiredBindings    = @(
            'RepositoryIdentity'
            'RepairRef'
            'MatrixCell'
            'RunId'
            'ResetPolicySha256'
            'ResetAllowListSha256'
            'Nonce'
            'ExpectedPreviousState'
        )
    }

    Automation = @{
        IntervalMinutes = 1
        Host = @{
            AutomationId = 'cddsi-fast-lane-hostcoordinator-minute-poll'
            InitialStatus = 'PAUSED'
            Role         = 'HostCoordinator'
            ReadOutbox   = 'vm-to-host'
            WriteOutbox  = 'host-to-vm'
            MayEditCode  = $true
            MayMerge     = $false
            MayRelease   = $false
            MayRunLive   = $false
        }
        Vm = @{
            AutomationId = 'cddsi-fast-lane-vmtester-minute-poll'
            InitialStatus = 'PAUSED'
            MustBeCreatedOnVmDevice = $true
            Role         = 'VmTester'
            ReadOutbox   = 'host-to-vm'
            WriteOutbox  = 'vm-to-host'
            MayEditCode  = $false
            MayPushCode  = $false
            MayBuildCandidate = $false
            MayChangeRunbook  = $false
        }
    }

    GuestReset = @{
        EnvironmentResetMode = 'GuestReset'
        ReceiptStatus        = 'CLEAN_READY'
        AllowedResourceKinds = @(
            'OwnedTestPackage'
            'OwnedHkcuValue'
            'OwnedCredential'
            'OwnedCheckpoint'
            'OwnerMarkedDirectory'
        )
        MandatoryEscalationReasons = @(
            'BaselineDrift'
            'CleanupFailure'
            'MissingOwnershipReceipt'
            'UnknownMutation'
            'VmpStateUnknown'
            'RebootStateUnknown'
            'UninstallStateUnknown'
            'CompensationStateUnknown'
        )
        ForbiddenBroadActions = @(
            'GitClean'
            'ProfileCleanup'
            'GlobalGitConfigRewrite'
            'GlobalPowerShellConfigRewrite'
            'ScheduledTaskEnumerationCleanup'
            'BroadTempCleanup'
        )
    }

    ProhibitedTransitions = @(
        'FastPassToFormalPass'
        'RelayAckToAcceptanceReceipt'
        'AutomaticMerge'
        'AutomaticP12Promotion'
        'AutomaticRelease'
        'SourcePullAsCandidateRetest'
    )
}
