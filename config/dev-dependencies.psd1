@{
    SchemaVersion = 1

    Pester = @{
        Version                = '5.6.1'
        ProvenanceStatus       = 'VendoredPinnedTree'
        RootRelativePath       = '.dev/modules/Pester/5.6.1'
        ManifestRelativePath   = 'Pester.psd1'
        ExpectedFileCount      = 20
        ExpectedTotalBytes     = 1145990
        ExpectedManifestSha256 = '644e3dd029b4f2fdd7b99395446dcd7211d5a1027f51285759c2465e6df671aa'
        ExpectedTreeSha256     = 'b4992fea36787bda13b0301e2c459a03910ada99c73fd5b3ed9943470fd84460'
        LicenseRelativePath    = 'third-party/Pester-5.6.1-LICENSE.txt'
        ExpectedLicenseBytes   = 11357
        ExpectedLicenseSha256  = 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
        TreeHashFormat         = 'ordinal-relative-path|sha256-lower|length joined with LF, UTF-8 without BOM'
        OfficialGalleryUrl     = 'https://www.powershellgallery.com/packages/Pester/5.6.1'
        OfficialProjectUrl     = 'https://github.com/Pester/Pester'
        OfficialLicenseUrl     = 'https://www.apache.org/licenses/LICENSE-2.0.html'
    }

    IsolationEvidenceSuites = @(
        @{
            RelativePath      = 'tests/Contract/IsolationEvidence.Tests.ps1'
            ExpectedTestCount = 18
        }
        @{
            RelativePath      = 'tests/Unit/FakeProviders.Tests.ps1'
            ExpectedTestCount = 10
        }
        @{
            RelativePath      = 'tests/Contract/SafetyBoundary.Tests.ps1'
            ExpectedTestCount = 6
        }
    )

    QualityShards = @(
        @{
            ShardId = 'C01'
            Paths = @(
                'tests/Contract/Acceptance.Tests.ps1'
                'tests/Contract/Config.Tests.ps1'
                'tests/Contract/CoworkResume.Tests.ps1'
                'tests/Contract/DesktopMsix.Tests.ps1'
                'tests/Contract/EnvironmentReadiness.Tests.ps1'
            )
        }
        @{
            ShardId = 'C02'
            Paths = @(
                'tests/Contract/CredentialHelperRelease.Tests.ps1'
                'tests/Contract/GitSupplyChain.Tests.ps1'
                'tests/Contract/ReleaseArtifact.Tests.ps1'
                'tests/Contract/ReleaseFacts.Tests.ps1'
            )
        }
        @{
            ShardId = 'C03'
            Paths = @(
                'tests/Contract/DevelopmentDependencies.Tests.ps1'
                'tests/Contract/Encoding.Tests.ps1'
                'tests/Contract/IsolationEvidence.Tests.ps1'
                'tests/Contract/LiveAdapters.Tests.ps1'
                'tests/Contract/PublicFunctions.Tests.ps1'
                'tests/Contract/SafetyBoundary.Tests.ps1'
            )
        }
        @{
            ShardId = 'C04'
            Paths = @(
                'tests/Contract/FastLanePolicy.Tests.ps1'
                'tests/Contract/FastLaneReadiness.Tests.ps1'
                'tests/Contract/OperatorCoordinationBoundary.Tests.ps1'
                'tests/Contract/Orchestrator.Tests.ps1'
                'tests/Contract/StagePolicy.Tests.ps1'
            )
        }
        @{
            ShardId = 'C05'
            Paths = @(
                'tests/Contract/VmCalibration.Tests.ps1'
                'tests/Contract/VmReset.Tests.ps1'
            )
        }
        @{
            ShardId = 'C06'
            Paths = @(
                'tests/Contract/VmResetLiveAdapter.Tests.ps1'
                'tests/Contract/WindowsVmResetProvider.Tests.ps1'
            )
        }
        @{
            ShardId = 'C07'
            Paths = @(
                'tests/Contract/RealtimeRelay.Tests.ps1'
            )
        }
        @{
            ShardId = 'C08'
            Paths = @(
                'tests/Contract/RealtimeRelayForegroundControl.Tests.ps1'
                'tests/Contract/RealtimeRelayForegroundCycle.Tests.ps1'
                'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1'
            )
        }
        @{
            ShardId = 'U01'
            Paths = @(
                'tests/Unit/Common.Tests.ps1'
                'tests/Unit/ExecutionContext.Tests.ps1'
                'tests/Unit/FakeProviders.Tests.ps1'
                'tests/Unit/State.Tests.ps1'
                'tests/Unit/StateStore.Tests.ps1'
            )
        }
        @{
            ShardId = 'U02'
            Paths = @(
                'tests/Unit/DeepSeekApi.Tests.ps1'
                'tests/Unit/EnvironmentReadiness.Tests.ps1'
                'tests/Unit/VmTestRelay.Tests.ps1'
            )
        }
        @{
            ShardId = 'H01'
            Paths = @(
                'tests/HostSandbox/CandidateBuild.Tests.ps1'
                'tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1'
                'tests/HostSandbox/HostSandbox.Tests.ps1'
                'tests/HostSandbox/ReleaseSimulation.Tests.ps1'
            )
        }
        @{
            ShardId = 'H02'
            Paths = @(
                'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
            )
        }
        @{
            ShardId = 'H03'
            Paths = @(
                'tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1'
            )
        }
    )
}
