@{
    SchemaVersion  = 1
    ProtocolVersion = 'cddsi-vm-test-relay-v1'
    Lane            = 'Fast'

    ProductRemote = @{
        RepositoryToken         = 'github.com/LXZ56156/claude-desktop-deepseek-installer'
        PrivateRequired          = $true
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
            Ref             = 'refs/heads/main'
            LogicalOutbox   = 'host-to-vm'
            WriterRole      = 'HostCoordinator'
            ReaderRole      = 'VmTester'
        }
        VmToHost = @{
            RepositoryToken = 'github.com/LXZ56156/cddsi-vm-to-host'
            Ref             = 'refs/heads/main'
            LogicalOutbox   = 'vm-to-host'
            WriterRole      = 'VmTester'
            ReaderRole      = 'HostCoordinator'
        }
        ForcePushAllowed      = $false
        HistoryRewriteAllowed = $false
        DeletePublishedMessage = $false
        SingleActiveCycle      = $true
        CompareAndSwapRequired = $true
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
            Role         = 'HostCoordinator'
            ReadOutbox   = 'vm-to-host'
            WriteOutbox  = 'host-to-vm'
            MayEditCode  = $true
            MayMerge     = $false
            MayRelease   = $false
            MayRunLive   = $false
        }
        Vm = @{
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
