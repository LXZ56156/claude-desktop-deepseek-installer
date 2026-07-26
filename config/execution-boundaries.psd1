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
            'lib/d027-snapshot-authorization.ps1'
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
            'tests/Unit/D027ClaudeDownloadReceipt.Tests.ps1'
            'tests/Unit/D027ClaudeMsixDownloadWriter.Tests.ps1'
            'tests/Unit/D027ClaudeMsixHeldHandleCorrelation.Tests.ps1'
            'tests/Unit/D027ClaudeMsixManifest.Tests.ps1'
            'tests/Unit/D027ClaudeMsixSameStateSigner.Tests.ps1'
            'tests/Unit/D027ClaudeMsixSignatureEvidence.Tests.ps1'
            'tests/Unit/D027GitWinVerifyTrust.Tests.ps1'
            'tests/Unit/D027SnapshotAuthorization.Tests.ps1'
            'tests/Unit/ExecutionContext.Tests.ps1'
            'tests/Unit/FakeProviders.Tests.ps1'
            'tests/Unit/GitForWindowsObserver.Tests.ps1'
            'tests/Unit/State.Tests.ps1'
            'tests/Unit/StateStore.Tests.ps1'
            'tests/Unit/DeepSeekApi.Tests.ps1'
            'tests/Unit/EnvironmentReadiness.Tests.ps1'
            'tests/Contract/D027ClaudeDesktopInstallerLive.Tests.ps1'
            'tests/Contract/D027GitInstallerLive.Tests.ps1'
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
            'tests/Contract/RealtimeRelayForegroundControl.Tests.ps1'
            'tests/Contract/RealtimeRelayForegroundCycle.Tests.ps1'
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
            'scripts/historical-diagnostics.ps1'
            'scripts/invoke-host-sandbox.ps1'
            'scripts/invoke-release-gates.ps1'
            'scripts/product-release-gate.ps1'
            'scripts/quality-set-policy.ps1'
            'scripts/release-gate-common.ps1'
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
            'operator/realtime-relay/foreground-control.ps1'
            'operator/realtime-relay/invoke-foreground-cycle.ps1'
            'operator/realtime-relay/realtime-relay-client.ps1'
        )

        PolicyData = @(
            'config/d027-snapshot-authority.psd1'
            'config/public-functions.psd1'
            'config/execution-boundaries.psd1'
            'config/dev-dependencies.psd1'
            'config/fast-lane-policy.psd1'
            'config/product-release-gate.psd1'
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
            'lib/d027-snapshot-authorization.ps1'
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
                'lib/d027-snapshot-authorization.ps1'
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
                'Invoke-CddsiLiveReadOnlyProviderOperation'
            )
        }

        LiveAdapterLoadEntryPoint = 'Invoke-CddsiLiveAdapterOperation'

        LiveAdapterProviderEntryPoint = 'Invoke-CddsiLiveReadOnlyProviderOperation'

        LiveAdapterCommandAllowList = @{
            'lib/live-adapters.ps1' = @(
                'Add-CddsiProductAccessLedgerEntry'
                'Assert-CddsiExecutionContext'
                'New-CddsiLiveReadOnlyProviderSet'
                'New-CddsiOperationResult'
                'Out-Null'
                'Test-CddsiCommittedOperationUseReceipt'
                'Where-Object'
            )
        }

        LiveAdapterTypePrefixAllowList = @{
            'lib/live-adapters.ps1' = @(
                'Alias'
                'CmdletBinding'
                'long'
                'ordered'
                'Parameter'
                'pscustomobject'
                'string'
                'System.Collections.IDictionary'
            )
        }

        LiveAdapterDirectPipelineAllowList = @{
            'lib/live-adapters.ps1' = @(
                'Invoke-CddsiLiveAdapterOperation|NamedBlockAst|<SUPPRESSED>|3ae2f4f683ebf4e9bece3eada1c9bec9f4baafbac94d40d8aba86ae76bfb6dbf'
                'Invoke-CddsiLiveAdapterOperation|StatementBlockAst|$allowedBindings|5284a902bfb4ab775b0a317b3d9305a36cb37e4fbbd3cc98103a3d7c5b4b14cc'
                'Invoke-CddsiLiveAdapterOperation|StatementBlockAst|$bindingMatches|f9156254d0ed94e820070206d810809398561a23458b88839ed115ff00b49cbc'
                'Invoke-CddsiLiveAdapterOperation|NamedBlockAst|$bindingMatches|f1b2e05ceeb396c1a7a5f410cde522e8295bba478d0761ee534c493088b1ccba'
                'Invoke-CddsiLiveAdapterOperation|StatementBlockAst|<SUPPRESSED>|3ae2f4f683ebf4e9bece3eada1c9bec9f4baafbac94d40d8aba86ae76bfb6dbf'
                'Invoke-CddsiLiveReadOnlyProviderOperation|NamedBlockAst|<SUPPRESSED>|3ae2f4f683ebf4e9bece3eada1c9bec9f4baafbac94d40d8aba86ae76bfb6dbf'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|3903c8547534f13be8a4b0db161c7474a2031561ee80c6df60e61e4eac123243'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|e6df2462ea89892f28ed62faa35b0e18f2cf1ecf1b51bd643b74a5f23607ab4c'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|cb9ebcf11430eccaf30cb93b716f11d5296451bb7d2d8289b2d36bce8fb26896'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|75b781d07089fae58b97c82e33fc86df5064ed161536bd7d77cd691f9099c64d'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|3966b8445c0607deb35d34cd85c9e86f810962e8a4f729af23a0114f69386c9c'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|e58748e338ee9c96cfd211e2b9abac49a1b166aa2eb86321335ad63276fab88c'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|abc5cda1999018b9843c03ee9a164fa61095cb6dae2ba56e87586a5942d45a29'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|bd5a4cce5a5cfbdf0d9cf022e4a83860de9aebf12154e6e198973d0c9f65b170'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|bc62be9c9021e6d124f0318bb81998f24227a9037d71b6362ab13ebf3c58e9b2'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|94da684c5bdf046c8cf5b0bc7594f8d5f0160e7c936ed17c4277d50750dbe433'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$providerCapabilities|33091f65f3978ae558c600fcbf0ff6320f49fff0f2b39527e0eaa9e9d5ad4ecc'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$ledgerOperation|8618efe8d14b8618865c1a308ef25010618b345bc51841d0e794315890d64166'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$ledgerOperation|a9e37c0b59da99fae1caeb30cb3866d8b0a1cacc276dcbf7bf53a2b9a1f142cf'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|3903c8547534f13be8a4b0db161c7474a2031561ee80c6df60e61e4eac123243'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|e6df2462ea89892f28ed62faa35b0e18f2cf1ecf1b51bd643b74a5f23607ab4c'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|cb9ebcf11430eccaf30cb93b716f11d5296451bb7d2d8289b2d36bce8fb26896'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|75b781d07089fae58b97c82e33fc86df5064ed161536bd7d77cd691f9099c64d'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|3966b8445c0607deb35d34cd85c9e86f810962e8a4f729af23a0114f69386c9c'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|e58748e338ee9c96cfd211e2b9abac49a1b166aa2eb86321335ad63276fab88c'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|abc5cda1999018b9843c03ee9a164fa61095cb6dae2ba56e87586a5942d45a29'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|bd5a4cce5a5cfbdf0d9cf022e4a83860de9aebf12154e6e198973d0c9f65b170'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|bc62be9c9021e6d124f0318bb81998f24227a9037d71b6362ab13ebf3c58e9b2'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$allCapabilities|94da684c5bdf046c8cf5b0bc7594f8d5f0160e7c936ed17c4277d50750dbe433'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$resourceMatches|12a0ab925d41b300af4cb1ae6e324a53c96a9958fb84c1aca98e5282a77d9eea'
                'Invoke-CddsiLiveReadOnlyProviderOperation|NamedBlockAst|$resourceMatches|5443af5a90b4a59666fb4b00fdfe5e63d5039ba9f960e6b607600d8de71404b4'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$capabilityMatches|e6634d66e0e5b82100cd467886e5ab124f702250adc013665540a05f28dca720'
                'Invoke-CddsiLiveReadOnlyProviderOperation|NamedBlockAst|$capabilityMatches|9d039c27dfd4e22eac8e94b5ba7433b64f8615f8621691faf9232d96d5def6f5'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|$capabilityMatches|f599dcee9b4631473a3550a4ff26484c036b9ef7b0cefae79012f20b37200fd1'
                'Invoke-CddsiLiveReadOnlyProviderOperation|StatementBlockAst|<SUPPRESSED>|685c4d5c87f4af6c5f6ed6b954663d010c5a046777f37439081fb9f23948a50a'
                'Invoke-CddsiLiveReadOnlyProviderOperation|NamedBlockAst|<SUPPRESSED>|aedc2d0bf35c88d3fa23e2ab70baeb71e796da21d9e207171da268d29f125613'
            )
        }

        LiveAdapterFunctionSourceDigestAllowList = @{
            'lib/live-adapters.ps1' = @(
                'Invoke-CddsiLiveAdapterOperation|5bfbd5cd2bb6f1f5d926345c753d9e9aa0b9a87d41fc5efd34a9852c87b6080a'
                'Invoke-CddsiLiveReadOnlyProviderOperation|213b3b9b9e8b5d7263179c2599e1cadb3f6332dbc264486e273836db8296adb4'
            )
        }

        LiveAdapterRequiredGateCommands = @(
            'Assert-CddsiExecutionContext'
            'Test-CddsiCommittedOperationUseReceipt'
        )

        LiveAdapterRequiredOperation = 'LoadLiveProviders'

        LiveReadOnlyCapabilities = @(
            @{
                Provider            = 'Environment'
                Operation           = 'Inspect'
                ResourceToken       = '<ENVIRONMENT:WINDOWS>'
                ResultSchemaId       = 'WindowsEnvironmentObservation/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Environment'
                Operation           = 'Inspect'
                ResourceToken       = '<ENVIRONMENT:HARDWARE_VIRTUALIZATION>'
                ResultSchemaId       = 'HardwareVirtualizationObservation/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Environment'
                Operation           = 'Inspect'
                ResourceToken       = '<KNOWN_FOLDERS:CURRENT_USER>'
                ResultSchemaId       = 'CurrentUserKnownFoldersObservation/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Package'
                Operation           = 'Inspect'
                ResourceToken       = '<PACKAGE:CLAUDE_DESKTOP>'
                ResultSchemaId       = 'ClaudeDesktopPackageInventory/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Process'
                Operation           = 'Inspect'
                ResourceToken       = '<PROCESS:GIT_FOR_WINDOWS>'
                ResultSchemaId       = 'GitForWindowsInventory/v2'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Feature'
                Operation           = 'Inspect'
                ResourceToken       = '<FEATURE:VIRTUAL_MACHINE_PLATFORM>'
                ResultSchemaId       = 'VirtualMachinePlatformObservation/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Service'
                Operation           = 'Inspect'
                ResourceToken       = '<SERVICE:COWORK>'
                ResultSchemaId       = 'CoworkServiceObservation/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Registry'
                Operation           = 'Inspect'
                ResourceToken       = '<HKLM_MANAGED_POLICY>'
                ResultSchemaId       = 'ClaudeConfigSourceMetadata/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Registry'
                Operation           = 'Inspect'
                ResourceToken       = '<HKCU_MANAGED_POLICY>'
                ResultSchemaId       = 'ClaudeConfigSourceMetadata/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'FileSystem'
                Operation           = 'Inspect'
                ResourceToken       = '<CONFIG_LIBRARY>'
                ResultSchemaId       = 'ClaudeConfigSourceMetadata/v1'
                ArgumentNames       = @()
            }
            @{
                Provider            = 'Process'
                Operation           = 'Inspect'
                ResourceToken       = '<PROCESS:CLAUDE_DESKTOP>'
                ResultSchemaId       = 'ClaudeDesktopProcessInventory/v1'
                ArgumentNames       = @()
            }
        )

        LiveAdapterForbiddenTextPatterns = @(
            '(?i)\.claude'
            '(?i)settings\.json'
            '(?i)\bUserProfile\b'
            '(?i)\bHomeDirectory\b'
        )

        LiveAdapterForbiddenVariableNames = @(
            'HOME'
            'PROFILE'
            'USERPROFILE'
            'LOCALAPPDATA'
            'APPDATA'
            'PROGRAMDATA'
            'HOMEDRIVE'
            'HOMEPATH'
        )

        LiveAdapterForbidEnvironmentVariables = $true

        LiveAdapterSystemCapabilityCommands = @(
            'Get-Acl'
            'Get-ChildItem'
            'Get-Item'
            'Test-Path'
            'Resolve-Path'
            'Convert-Path'
            'Join-Path'
            'Split-Path'
            'Get-Location'
            'Get-PSDrive'
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
            'Get-ItemPropertyValue'
            'Set-ItemProperty'
            'New-ItemProperty'
            'Remove-ItemProperty'
            'Invoke-WebRequest'
            'Invoke-RestMethod'
            'Start-BitsTransfer'
            'Resolve-DnsName'
            'Test-NetConnection'
            'Get-Process'
            'Start-Process'
            'Stop-Process'
            'Start-Job'
            'Invoke-Command'
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
            'New-Object'
            'gci'
            'gc'
            'dir'
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

        LiveAdapterSystemCapabilityTypePrefixes = @(
            'Environment'
            'System.Environment'
            'System.IO.File'
            'System.IO.Directory'
            'System.IO.Path'
            'Microsoft.Win32.Registry'
            'System.Diagnostics.Process'
            'System.Net.'
            'System.Security.Cryptography.ProtectedData'
            'Windows.Security.Credentials'
            'wmi'
        )

        LiveAdapterSystemCapabilitySites = @{
            'lib/live-adapters.ps1' = @()
        }

        LiveAdapterAllowedBindings = @(
            @{
                EnvironmentTier = 'VmDevelopment'
                Stage           = 'VmDevelopment'
                ArtifactProfile = 'VmDevelopment'
            }
            @{
                EnvironmentTier = 'VmAcceptance'
                Stage           = 'VmAcceptance'
                ArtifactProfile = 'VmAcceptance'
            }
            @{
                EnvironmentTier = 'UserLive'
                Stage           = 'UserLive'
                ArtifactProfile = 'UserLive'
            }
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
            'scripts/historical-diagnostics.ps1'
            'scripts/invoke-host-sandbox.ps1'
            'scripts/invoke-release-gates.ps1'
            'scripts/product-release-gate.ps1'
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
            'operator/realtime-relay/foreground-control.ps1'
            'operator/realtime-relay/invoke-foreground-cycle.ps1'
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
            'operator/realtime-relay/foreground-control.ps1' = @(
                'ConvertFrom-CddsiRealtimeRelayForegroundControlBody'
            )
            'operator/realtime-relay/invoke-foreground-cycle.ps1' = @(
                'Invoke-CddsiRealtimeRelayForegroundCycle'
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
            'operator/realtime-relay/invoke-foreground-cycle.ps1'
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
