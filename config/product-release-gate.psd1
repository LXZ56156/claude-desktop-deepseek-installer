@{
    SchemaVersion = 1
    ContractVersion = 'D-026'
    EnforcementPhase = 'NamedProductReleaseGate'

    Scope = @{
        RootRelativePath = 'tests'
        PathComparison = 'Ordinal'
        ExpectedTrackedFileCount = 47
        ExpectedPesterTestCount = 42
    }

    ProductReleaseBlockingFiles = @(
        @{ RelativePath = 'tests/Contract/Acceptance.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/Config.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/CoworkResume.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/CredentialHelperRelease.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/DesktopMsix.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/DevelopmentDependencies.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/Encoding.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/EnvironmentReadiness.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/GitSupplyChain.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/IsolationEvidence.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/LiveAdapters.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/OperatorCoordinationBoundary.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/Orchestrator.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/PublicFunctions.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/ReleaseArtifact.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/ReleaseFacts.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/SafetyBoundary.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/StagePolicy.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Contract/VmCalibration.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Fixtures/anthropic-msix-release-synthetic-v1.json'; FileKind = 'SyntheticFixture'; ReasonCode = 'CurrentProductSyntheticFixture' }
        @{ RelativePath = 'tests/Fixtures/claude-desktop-3p-contract-v1.json'; FileKind = 'SyntheticFixture'; ReasonCode = 'CurrentProductSyntheticFixture' }
        @{ RelativePath = 'tests/Fixtures/git-for-windows-release-api-synthetic-v1.json'; FileKind = 'SyntheticFixture'; ReasonCode = 'CurrentProductSyntheticFixture' }
        @{ RelativePath = 'tests/Fixtures/safe-config.json'; FileKind = 'SyntheticFixture'; ReasonCode = 'CurrentProductSyntheticFixture' }
        @{ RelativePath = 'tests/HostSandbox/CandidateBuild.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/HostSandbox/HostSandbox.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/HostSandbox/ReleaseSimulation.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Support/TestContext.ps1'; FileKind = 'SupportScript'; ReasonCode = 'CurrentProductSupportScript' }
        @{ RelativePath = 'tests/Unit/Common.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Unit/DeepSeekApi.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Unit/EnvironmentReadiness.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Unit/ExecutionContext.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Unit/FakeProviders.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Unit/State.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
        @{ RelativePath = 'tests/Unit/StateStore.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'CurrentProductReleaseTest' }
    )

    HistoricalDiagnosticFiles = @(
        @{ RelativePath = 'tests/Contract/FastLanePolicy.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredFastLaneTransport' }
        @{ RelativePath = 'tests/Contract/FastLaneReadiness.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredFastLaneTransport' }
        @{ RelativePath = 'tests/Contract/RealtimeRelay.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredRealtimeRelayTransport' }
        @{ RelativePath = 'tests/Contract/RealtimeRelayForegroundControl.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredRealtimeRelayTransport' }
        @{ RelativePath = 'tests/Contract/RealtimeRelayForegroundCycle.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredRealtimeRelayTransport' }
        @{ RelativePath = 'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredRealtimeRelayTransport' }
        @{ RelativePath = 'tests/Contract/VmReset.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredVmRelayResetControl' }
        @{ RelativePath = 'tests/Contract/VmResetLiveAdapter.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredVmRelayResetControl' }
        @{ RelativePath = 'tests/Contract/WindowsVmResetProvider.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredVmRelayResetControl' }
        @{ RelativePath = 'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredFastLaneTransport' }
        @{ RelativePath = 'tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredFastLaneTransport' }
        @{ RelativePath = 'tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredFastLaneTransport' }
        @{ RelativePath = 'tests/Unit/VmTestRelay.Tests.ps1'; FileKind = 'PesterTest'; ReasonCode = 'RetiredVmRelayResetControl' }
    )
}
