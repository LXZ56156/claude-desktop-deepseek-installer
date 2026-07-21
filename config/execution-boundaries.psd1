@{
    SchemaVersion = 1

    Planes = @{
        ProductCore = @(
            'Start-Here.ps1'
            'lib/bootstrap.ps1'
            'lib/logger.ps1'
            'lib/common.ps1'
            'lib/stage-policy.ps1'
            'lib/vm-calibration.ps1'
            'lib/release-facts.ps1'
            'lib/release-artifact.ps1'
            'lib/execution-context.ps1'
            'lib/fake-providers.ps1'
            'lib/state.ps1'
            'lib/state-store.ps1'
            'lib/desktop-env-check.ps1'
            'lib/desktop-msix.ps1'
            'lib/git-for-windows.ps1'
            'lib/cowork-readiness.ps1'
            'lib/deepseek-api.ps1'
            'lib/credential-helper-release.ps1'
            'lib/desktop-config.ps1'
            'lib/desktop-lifecycle.ps1'
            'lib/desktop-acceptance.ps1'
            'lib/orchestrator.ps1'
            'scripts/elevated-install.ps1'
        )

        Tests = @(
            'tests/Unit/Common.Tests.ps1'
            'tests/Unit/ExecutionContext.Tests.ps1'
            'tests/Unit/FakeProviders.Tests.ps1'
            'tests/Unit/State.Tests.ps1'
            'tests/Unit/StateStore.Tests.ps1'
            'tests/Unit/DeepSeekApi.Tests.ps1'
            'tests/Unit/EnvironmentReadiness.Tests.ps1'
            'tests/Contract/PublicFunctions.Tests.ps1'
            'tests/Contract/SafetyBoundary.Tests.ps1'
            'tests/Contract/Config.Tests.ps1'
            'tests/Contract/DevelopmentDependencies.Tests.ps1'
            'tests/Contract/Encoding.Tests.ps1'
            'tests/Contract/IsolationEvidence.Tests.ps1'
            'tests/Contract/EnvironmentReadiness.Tests.ps1'
            'tests/Contract/StagePolicy.Tests.ps1'
            'tests/Contract/Orchestrator.Tests.ps1'
            'tests/Contract/Acceptance.Tests.ps1'
            'tests/Contract/CoworkResume.Tests.ps1'
            'tests/Contract/VmCalibration.Tests.ps1'
            'tests/Contract/ReleaseFacts.Tests.ps1'
            'tests/Contract/ReleaseArtifact.Tests.ps1'
            'tests/Contract/CredentialHelperRelease.Tests.ps1'
            'tests/Contract/DesktopMsix.Tests.ps1'
            'tests/Contract/GitSupplyChain.Tests.ps1'
            'tests/Contract/LiveAdapters.Tests.ps1'
            'tests/Contract/FastLanePolicy.Tests.ps1'
            'tests/Contract/FastLaneReadiness.Tests.ps1'
            'tests/Contract/OperatorCoordinationBoundary.Tests.ps1'
            'tests/Contract/RealtimeRelay.Tests.ps1'
            'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1'
            'tests/Contract/VmReset.Tests.ps1'
            'tests/Contract/VmResetLiveAdapter.Tests.ps1'
            'tests/Contract/WindowsVmResetProvider.Tests.ps1'
            'tests/Unit/VmTestRelay.Tests.ps1'
            'tests/Support/TestContext.ps1'
            'tests/HostSandbox/HostSandbox.Tests.ps1'
            'tests/HostSandbox/ReleaseSimulation.Tests.ps1'
            'tests/HostSandbox/CandidateBuild.Tests.ps1'
            'tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1'
            'tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1'
            'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
        )

        TrustedHarness = @(
            'scripts/bootstrap-dev.ps1'
            'scripts/build-release.ps1'
            'scripts/build-candidate.ps1'
            'scripts/check.ps1'
            'scripts/check-worker.ps1'
            'scripts/invoke-host-sandbox.ps1'
            'operator/fast-lane/invoke-synthetic-rehearsal.ps1'
        )

        OperatorCoordination = @(
            'lib/vm-test-relay.ps1'
            'lib/vm-reset.ps1'
            'lib/vm-fast-lane-readiness.ps1'
            'operator/fast-lane/build-vm-onboarding.ps1'
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/fast-lane/invoke-vm-reset-live.ps1'
            'operator/fast-lane/providers/windows-vm-reset.ps1'
            'operator/realtime-relay/invoke-vm-smoke.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        PolicyData = @(
            'config/public-functions.psd1'
            'config/execution-boundaries.psd1'
            'config/dev-dependencies.psd1'
            'config/fast-lane-policy.psd1'
            'scripts/release-manifest.psd1'
        )

        DevelopmentDependencies = @(
            '.dev/modules/Pester/5.6.1/Pester.ps1'
            '.dev/modules/Pester/5.6.1/Pester.psd1'
            '.dev/modules/Pester/5.6.1/Pester.psm1'
        )

        LiveAdapters = @(
            'lib/live-adapters.ps1'
        )
    }

    Rules = @{
        DefaultBootstrapLibraryFiles = @(
            'lib/logger.ps1'
            'lib/common.ps1'
            'lib/stage-policy.ps1'
            'lib/vm-calibration.ps1'
            'lib/release-facts.ps1'
            'lib/release-artifact.ps1'
            'lib/state.ps1'
            'lib/execution-context.ps1'
            'lib/fake-providers.ps1'
            'lib/state-store.ps1'
            'lib/desktop-env-check.ps1'
            'lib/desktop-msix.ps1'
            'lib/git-for-windows.ps1'
            'lib/cowork-readiness.ps1'
            'lib/deepseek-api.ps1'
            'lib/credential-helper-release.ps1'
            'lib/desktop-config.ps1'
            'lib/desktop-lifecycle.ps1'
            'lib/desktop-acceptance.ps1'
            'lib/orchestrator.ps1'
        )

        ProductDotSourceAllowList = @{
            'Start-Here.ps1' = @(
                'lib/bootstrap.ps1'
            )
            'lib/bootstrap.ps1' = @(
                'lib/logger.ps1'
                'lib/common.ps1'
                'lib/stage-policy.ps1'
                'lib/vm-calibration.ps1'
                'lib/release-facts.ps1'
                'lib/release-artifact.ps1'
                'lib/state.ps1'
                'lib/execution-context.ps1'
                'lib/fake-providers.ps1'
                'lib/state-store.ps1'
                'lib/desktop-env-check.ps1'
                'lib/desktop-msix.ps1'
                'lib/git-for-windows.ps1'
                'lib/cowork-readiness.ps1'
                'lib/deepseek-api.ps1'
                'lib/credential-helper-release.ps1'
                'lib/desktop-config.ps1'
                'lib/desktop-lifecycle.ps1'
                'lib/desktop-acceptance.ps1'
                'lib/orchestrator.ps1'
            )
            'scripts/elevated-install.ps1' = @(
                'lib/bootstrap.ps1'
            )
        }

        LiveAdapterEntryPoints = @{
            'lib/live-adapters.ps1' = @(
                'Invoke-CddsiLiveAdapterOperation'
            )
        }

        LiveAdapterCommandAllowList = @{
            'lib/live-adapters.ps1' = @()
        }

        LiveAdapterTypePrefixAllowList = @{
            'lib/live-adapters.ps1' = @()
        }

        LiveAdapterRequiredGateCommands = @(
            'Assert-CddsiExecutionContext'
            'Test-CddsiCommittedOperationUseReceipt'
        )

        ProductForbiddenCommands = @(
            'Get-ChildItem'
            'Get-Item'
            'Test-Path'
            'Get-Content'
            'Set-Content'
            'Add-Content'
            'Out-File'
            'New-Item'
            'Remove-Item'
            'Copy-Item'
            'Move-Item'
            'Get-FileHash'
            'Get-ItemProperty'
            'Set-ItemProperty'
            'New-ItemProperty'
            'Remove-ItemProperty'
            'Invoke-WebRequest'
            'Invoke-RestMethod'
            'Start-BitsTransfer'
            'Get-Process'
            'Start-Process'
            'Stop-Process'
            'Get-AppxPackage'
            'Add-AppxPackage'
            'Remove-AppxPackage'
            'Get-WindowsOptionalFeature'
            'Enable-WindowsOptionalFeature'
            'Disable-WindowsOptionalFeature'
            'Get-Service'
            'Start-Service'
            'Stop-Service'
            'Set-Service'
            'Get-ScheduledTask'
            'Register-ScheduledTask'
            'Unregister-ScheduledTask'
            'Get-CimInstance'
            'Get-WmiObject'
            'Restart-Computer'
            'Invoke-Expression'
            'Add-Type'
            'reg'
            'reg.exe'
            'curl'
            'curl.exe'
            'wget'
            'wget.exe'
            'git'
            'git.exe'
            'pwsh'
            'pwsh.exe'
            'powershell'
            'powershell.exe'
            'cmd'
            'cmd.exe'
            'msiexec'
            'msiexec.exe'
            'winget'
            'winget.exe'
            'dism'
            'dism.exe'
            'sc'
            'sc.exe'
            'schtasks'
            'schtasks.exe'
            'net'
            'net.exe'
            'shutdown'
            'shutdown.exe'
            'taskkill'
            'taskkill.exe'
            'rundll32'
            'rundll32.exe'
        )

        ProductCommandAllowList = @{}

        ProductForbiddenVariables = @(
            'HOME'
            'PROFILE'
            'USERPROFILE'
            'LOCALAPPDATA'
            'APPDATA'
            'PROGRAMDATA'
            'HOMEDRIVE'
            'HOMEPATH'
            'env:HOME'
            'env:USERPROFILE'
            'env:LOCALAPPDATA'
            'env:APPDATA'
            'env:PROGRAMDATA'
            'env:HOMEDRIVE'
            'env:HOMEPATH'
            'env:TEMP'
            'env:TMP'
            'env:PATH'
        )

        ProductForbiddenTypePrefixes = @(
            'Environment'
            'System.Environment'
            'System.IO.File'
            'System.IO.Directory'
            'Microsoft.Win32.Registry'
            'System.Diagnostics.Process'
            'System.Net.'
            'System.Security.Cryptography.ProtectedData'
            'Windows.Security.Credentials'
            'wmi'
        )

        TestForbiddenCommands = @(
            'Get-ItemProperty'
            'Set-ItemProperty'
            'New-ItemProperty'
            'Remove-ItemProperty'
            'Invoke-WebRequest'
            'Invoke-RestMethod'
            'Start-BitsTransfer'
            'Save-Module'
            'Install-Module'
            'Get-Process'
            'Start-Process'
            'Stop-Process'
            'Get-AppxPackage'
            'Add-AppxPackage'
            'Remove-AppxPackage'
            'Get-WindowsOptionalFeature'
            'Enable-WindowsOptionalFeature'
            'Disable-WindowsOptionalFeature'
            'Get-Service'
            'Start-Service'
            'Stop-Service'
            'Set-Service'
            'Get-ScheduledTask'
            'Register-ScheduledTask'
            'Unregister-ScheduledTask'
            'Get-CimInstance'
            'Get-WmiObject'
            'Restart-Computer'
            'Invoke-Expression'
            'Add-Type'
            'reg'
            'reg.exe'
            'curl'
            'curl.exe'
            'wget'
            'wget.exe'
            'git'
            'git.exe'
            'pwsh'
            'pwsh.exe'
            'powershell'
            'powershell.exe'
            'cmd'
            'cmd.exe'
            'msiexec'
            'msiexec.exe'
            'winget'
            'winget.exe'
            'dism'
            'dism.exe'
            'sc'
            'sc.exe'
            'schtasks'
            'schtasks.exe'
            'net'
            'net.exe'
            'shutdown'
            'shutdown.exe'
            'taskkill'
            'taskkill.exe'
            'rundll32'
            'rundll32.exe'
        )

        TestForbiddenVariables = @(
            'HOME'
            'PROFILE'
            'USERPROFILE'
            'LOCALAPPDATA'
            'APPDATA'
            'PROGRAMDATA'
            'HOMEDRIVE'
            'HOMEPATH'
            'env:HOME'
            'env:USERPROFILE'
            'env:LOCALAPPDATA'
            'env:APPDATA'
            'env:PROGRAMDATA'
            'env:HOMEDRIVE'
            'env:HOMEPATH'
            'env:TEMP'
            'env:TMP'
            'env:PATH'
        )

        TestForbiddenTypePrefixes = @(
            'Environment'
            'System.Environment'
            'Microsoft.Win32.Registry'
            'System.Diagnostics.Process'
            'System.Net.'
            'System.Security.Cryptography.ProtectedData'
            'Windows.Security.Credentials'
            'wmi'
        )

        TrustedHarnessDynamicInvocationFiles = @(
            'scripts/build-candidate.ps1'
            'scripts/build-release.ps1'
            'scripts/check.ps1'
            'scripts/check-worker.ps1'
            'operator/fast-lane/invoke-synthetic-rehearsal.ps1'
        )

        TrustedHarnessProcessFiles = @(
            'scripts/invoke-host-sandbox.ps1'
        )

        TrustedHarnessNetworkFiles = @()

        TrustedHarnessReflectionFiles = @()

        OperatorCoordinationLibraryFiles = @(
            'lib/vm-test-relay.ps1'
            'lib/vm-reset.ps1'
            'lib/vm-fast-lane-readiness.ps1'
        )

        OperatorRuntimeFiles = @(
            'operator/fast-lane/build-vm-onboarding.ps1'
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/fast-lane/invoke-vm-reset-live.ps1'
            'operator/fast-lane/providers/windows-vm-reset.ps1'
            'operator/realtime-relay/invoke-vm-smoke.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        OperatorRuntimeEntryPoints = @{
            'operator/fast-lane/build-vm-onboarding.ps1' = @(
                'New-CddsiFastLaneVmOnboardingBundle'
                'Test-CddsiFastLaneVmOnboardingBundle'
            )
            'operator/fast-lane/invoke-git-outbox.ps1' = @(
                'Invoke-CddsiFastLaneGitOutbox'
                'Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding'
            )
            'operator/fast-lane/invoke-vm-reset-live.ps1' = @(
                'Invoke-CddsiVmResetLiveAdapter'
            )
            'operator/fast-lane/providers/windows-vm-reset.ps1' = @(
                'Get-CddsiWindowsVmResetProviderOperationContract'
                'Test-CddsiWindowsVmResetTrustPolicy'
                'Test-CddsiWindowsVmResetDeploymentEvidence'
                'Test-CddsiWindowsVmResetLiveAuthorization'
                'Test-CddsiWindowsVmResetProviderAdapterAuthorization'
                'Test-CddsiWindowsVmResetAdapterDeviceSignature'
                'Invoke-CddsiWindowsVmResetAuthorizedRequest'
                'New-CddsiWindowsVmResetProvider'
            )
            'operator/realtime-relay/invoke-vm-smoke.ps1' = @(
                'Invoke-CddsiRelayVmSmoke'
            )
            'operator/realtime-relay/realtime-relay-client.ps1' = @(
                'Invoke-CddsiRealtimeRelayWatcher'
                'Invoke-CddsiRealtimeRelayPublish'
                'Set-CddsiRealtimeRelayDpapiCredential'
                'New-CddsiRealtimeRelayDpapiCredentialProvider'
                'New-CddsiRealtimeRelayFixedGitOutboxWakeProvider'
                'New-CddsiRealtimeRelayOwnedStateProvider'
                'Remove-CddsiRealtimeRelayOwnedState'
                'New-CddsiRealtimeRelayLiveProvider'
                'New-CddsiRealtimeRelayLivePublisher'
            )
        }

        OperatorRuntimeDynamicInvocationFiles = @(
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/fast-lane/invoke-vm-reset-live.ps1'
            'operator/fast-lane/providers/windows-vm-reset.ps1'
            'operator/realtime-relay/invoke-vm-smoke.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        OperatorRuntimeFileSystemFiles = @(
            'operator/fast-lane/build-vm-onboarding.ps1'
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/fast-lane/providers/windows-vm-reset.ps1'
            'operator/realtime-relay/invoke-vm-smoke.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        OperatorRuntimeProcessFiles = @(
            'operator/fast-lane/build-vm-onboarding.ps1'
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/fast-lane/providers/windows-vm-reset.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        OperatorRuntimeNetworkFiles = @(
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/realtime-relay/invoke-vm-smoke.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        OperatorRuntimeCredentialFiles = @(
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        OperatorRuntimeReflectionFiles = @(
            'operator/fast-lane/build-vm-onboarding.ps1'
            'operator/fast-lane/invoke-git-outbox.ps1'
            'operator/fast-lane/providers/windows-vm-reset.ps1'
        )

        OperatorRuntimeVmInspectionFiles = @(
            'operator/fast-lane/providers/windows-vm-reset.ps1'
        )

        OperatorRuntimeVmMutationFiles = @(
            'operator/fast-lane/providers/windows-vm-reset.ps1'
        )
    }
}
