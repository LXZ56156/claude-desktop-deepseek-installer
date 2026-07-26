@{
    SchemaVersion = 2

    Files = @{
        'lib/bootstrap.ps1' = @(
            'Get-CddsiProjectRoot'
            'Import-CddsiLibraries'
            'Initialize-CddsiScript'
        )
        'lib/common.ps1' = @(
            'Get-CddsiProjectStage'
            'New-CddsiOperationResult'
            'Get-CddsiOperationExitCode'
            'Format-CddsiOperationCliSummary'
            'Resolve-CddsiExecutionMode'
            'Test-CddsiRealMutationAllowed'
            'Assert-CddsiMutationAllowed'
            'Get-CddsiConfigLibraryPath'
            'Protect-CddsiSecret'
            'Protect-CddsiReportText'
            'Find-CddsiPotentialSecrets'
            'Test-CddsiDeepSeekApiKeyFormat'
            'Get-CddsiSupplyChainTextBindingToken'
            'Get-CddsiSourceUriBindingToken'
            'Test-CddsiOfficialArtifactUri'
            'Test-CddsiOfficialArtifactRedirectUri'
            'Get-CddsiSourceObservationBindingToken'
            'Test-CddsiSourceObservation'
            'Get-CddsiArtifactDescriptorBindingToken'
            'Test-CddsiArtifactDescriptor'
            'Get-CddsiSignatureEvidenceBindingToken'
            'New-CddsiSignatureEvidenceVerdict'
            'Test-CddsiSignatureEvidence'
            'Test-CddsiSchemaVersionOne'
            'Test-CddsiUtcTimestampValue'
            'Test-CddsiSafeIdentifierValue'
            'Test-CddsiCanonicalUuidValue'
            'Get-CddsiPathBindingToken'
            'Test-CddsiArtifactHashBinding'
            'ConvertFrom-CddsiJson'
            'ConvertTo-CddsiJson'
            'Test-CddsiExactPropertySet'
            'Get-CddsiSignatureEvidencePayload'
        )
        'lib/cowork-readiness.ps1' = @(
            'Test-CddsiCoworkServiceStatus'
            'Get-CddsiCoworkReadiness'
            'Resolve-CddsiEffectiveSurfaces'
            'Get-CddsiCoworkBlockingReasons'
            'Resolve-CddsiCoworkFeatureChangeTranscript'
            'New-CddsiCoworkCheckpointPlan'
            'Test-CddsiResumeCheckpointEligibility'
            'Resolve-CddsiCoworkResume'
            'Enable-CddsiVirtualMachinePlatform'
        )
        'lib/deepseek-api.ps1' = @(
            'New-CddsiCredentialHelperContract'
            'Test-CddsiCredentialCaptureMetadata'
            'Test-CddsiCredentialAuthorizationBinding'
            'Resolve-CddsiCredentialAuthorizationBinding'
            'Test-CddsiCredentialProtectionEvidence'
            'ConvertFrom-CddsiCredentialHelperOutput'
            'Read-CddsiDeepSeekApiKeySecure'
            'Protect-CddsiDeepSeekCredential'
            'Get-CddsiCredentialLifecycleProviderEvidenceSha256'
            'Get-CddsiCredentialLifecycleProviderAggregateSha256'
            'New-CddsiCredentialLifecyclePlan'
            'Test-CddsiCredentialLifecycleEvent'
            'Resolve-CddsiCredentialLifecycleTranscript'
            'ConvertTo-CddsiDeepSeekApiErrorClass'
            'Invoke-CddsiDeepSeekApiValidation'
        )
        'lib/desktop-acceptance.ps1' = @(
            'Get-CddsiAcceptancePlan'
            'Get-CddsiClaudeCodeSettingsIntegrityContract'
            'Get-CddsiClaudeCodeSettingsFingerprint'
            'Test-CddsiClaudeCodeSettingsUnchanged'
            'Test-CddsiApiKeyLeak'
            'Test-CddsiExternalE2eEvidence'
            'Resolve-CddsiCompensationStatus'
            'Resolve-CddsiAcceptanceStatus'
            'New-CddsiAcceptanceEvidence'
            'Test-CddsiAcceptanceEvidence'
            'Test-CddsiChatAcceptance'
            'Test-CddsiCodeAcceptance'
            'Test-CddsiCoworkAcceptance'
            'Get-CddsiRepairPlan'
            'Invoke-CddsiDesktopRepair'
            'Invoke-CddsiDesktopAcceptance'
            'New-CddsiAcceptanceReport'
        )
        'lib/desktop-config.ps1' = @(
            'Get-CddsiClaudeDesktopConfigLibraryPath'
            'Test-CddsiConfigLibraryTarget'
            'Read-CddsiClaudeDesktopConfigLibrary'
            'New-CddsiClaudeDesktopDesiredConfig'
            'Test-CddsiClaudeDesktopConfigContract'
            'ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet'
            'Compare-CddsiClaudeDesktopConfig'
            'Test-CddsiConfigOperationAuthorizationBundle'
            'Get-CddsiConfigBackupEvidenceBindingToken'
            'Test-CddsiConfigBackupEvidence'
            'Test-CddsiManagedPolicyValueSet'
            'New-CddsiConfigBackupPlan'
            'New-CddsiConfigTransactionPlan'
            'Resolve-CddsiConfigTransactionTranscript'
            'New-CddsiConfigRestorableBackup'
            'New-CddsiConfigRedactedSnapshot'
            'Write-CddsiClaudeDesktopConfigAtomic'
            'Restore-CddsiClaudeDesktopConfig'
        )
        'lib/desktop-env-check.ps1' = @(
            'Get-CddsiDesktopEnvironmentSnapshot'
            'Test-CddsiVirtualMachinePlatform'
            'Test-CddsiHardwareVirtualization'
        )
        'lib/desktop-lifecycle.ps1' = @(
            'Get-CddsiClaudeDesktopProcessState'
            'Stop-CddsiClaudeDesktop'
            'Start-CddsiClaudeDesktop'
            'Restart-CddsiClaudeDesktop'
        )
        'lib/desktop-msix.ps1' = @(
            'New-CddsiD027ClaudeDesktopSourceDescriptor'
            'Test-CddsiD027ClaudeDesktopSourceDescriptor'
            'Test-CddsiD027ClaudeSanitizedDownloadUri'
            'Test-CddsiD027ClaudeDownloadDestinationPath'
            'Get-CddsiD027ClaudeDownloadReceiptBindingToken'
            'Get-CddsiD027ClaudeFileIdentityToken'
            'Get-CddsiD027ClaudeContentBindingToken'
            'New-CddsiD027ClaudeDownloadReceipt'
            'Test-CddsiD027ClaudeDownloadReceipt'
            'Test-CddsiD027ClaudeDownloadedArtifactObservation'
            'Get-CddsiD027ClaudeManifestBindingToken'
            'Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken'
            'Test-CddsiD027ClaudeMsixSignatureEvidenceContract'
            'ConvertFrom-CddsiD027ClaudeAppxManifestBytes'
            'Read-CddsiD027ClaudeMsixManifest'
            'Get-CddsiClaudeDesktopMsixStatus'
            'ConvertFrom-CddsiAnthropicMsixReleaseMetadata'
            'Get-CddsiOfficialMsixMetadata'
            'Save-CddsiOfficialClaudeDesktopMsix'
            'Test-CddsiClaudeDesktopMsixSignature'
            'Install-CddsiClaudeDesktopMsix'
            'Update-CddsiClaudeDesktopMsix'
        )
        'lib/execution-context.ps1' = @(
            'Get-CddsiLiveReadOnlyCapabilityContracts'
            'Test-CddsiExactNameSet'
            'Test-CddsiExactNotePropertySet'
            'Test-CddsiLogicalResourceToken'
            'Get-CddsiFakeInputFieldNames'
            'Get-CddsiFakeInputFieldValue'
            'Test-CddsiFakeValueEqual'
            'Get-CddsiFakeScenarioBindingToken'
            'Test-CddsiFakeMutationOperation'
            'Test-CddsiFakeResourceTokenAllowed'
            'Assert-CddsiFakeProviderScenario'
            'Test-CddsiLiveReadOnlyCapabilityTuple'
            'Assert-CddsiProductAccessLedgerEntryValues'
            'New-CddsiUnloadedProviderSet'
            'New-CddsiLiveReadOnlyProviderSet'
            'New-CddsiAccessLedger'
            'Add-CddsiProductAccessLedgerEntry'
            'New-CddsiExecutionContext'
            'Assert-CddsiExecutionContext'
            'Get-CddsiExecutionPathTokenValues'
            'Invoke-CddsiProviderOperation'
            'Get-CddsiIsolationEvidence'
            'Assert-CddsiIsolationEvidence'
        )
        'lib/fake-providers.ps1' = @(
            'New-CddsiFakeProviderSet'
            'Invoke-CddsiFakeProviderOperation'
            'Assert-CddsiFakeProviderExpectations'
        )
        'lib/d027-snapshot-authorization.ps1' = @(
            'Test-CddsiD027Windows11X64Platform'
            'Get-CddsiD027SnapshotPlatformObservation'
            'Get-CddsiD027GitSnapshotWorkloadBindingToken'
            'Get-CddsiD027ClaudeSnapshotWorkloadBindingToken'
            'Test-CddsiD027ClaudeSnapshotWorkloadDescriptor'
            'Test-CddsiD027CanonicalBase64'
            'Get-CddsiD027SnapshotAuthorityKeySha256'
            'Get-CddsiD027SnapshotAuthorityPolicy'
            'Get-CddsiD027ExternalSnapshotReceiptBindingToken'
            'Test-CddsiD027ExternalSnapshotReceipt'
            'Test-CddsiD027ClaudeExternalSnapshotReceipt'
            'Get-CddsiD027SnapshotReceiptHeldFileObservation'
            'Read-CddsiD027ExternalSnapshotReceipt'
            'Enable-CddsiD027GitLiveSessionAuthorization'
            'Clear-CddsiD027GitLiveSessionAuthorization'
            'Assert-CddsiD027GitLiveBootstrapContext'
            'Assert-CddsiD027GitLiveContext'
        )
        'lib/git-for-windows.ps1' = @(
            'Get-CddsiD027GitWinVerifyTrustResult'
            'ConvertFrom-CddsiGitVersionProbeResult'
            'ConvertTo-CddsiGitInstallerReceiptVersion'
            'ConvertFrom-CddsiGitPeHeader'
            'Test-CddsiCurrentProcessElevated'
            'Get-CddsiGitForWindowsRegistryObservation'
            'Test-CddsiGitProtectedInstallPathSet'
            'Get-CddsiGitForWindowsPrivateDllObservation'
            'Get-CddsiGitForWindowsSignedComponentObservation'
            'Resolve-CddsiGitExecutablePathSet'
            'New-CddsiGitVersionProbeStartInfo'
            'Initialize-CddsiD027GitProbeRunnerType'
            'Invoke-CddsiGitVersionProbe'
            'Get-CddsiGitForWindowsExecutableObservation'
            'Get-CddsiLiveGitForWindowsObservation'
            'Get-CddsiGitForWindowsStatus'
            'ConvertTo-CddsiD027NormalizedGitHubReleaseDocument'
            'Get-CddsiD027GitDownloadReceiptBindingToken'
            'New-CddsiD027GitDownloadReceipt'
            'Test-CddsiD027GitDownloadReceipt'
            'Resolve-CddsiD027GitInstallerDescriptor'
            'Get-CddsiD027GitInstallerProcessPolicy'
            'Assert-CddsiD027GitDirectorySecurity'
            'Test-CddsiD027GitPostInstallReadbackEligible'
            'ConvertTo-CddsiD027GitInstallerExitResult'
            'ConvertFrom-CddsiGitHubReleaseMetadata'
            'Get-CddsiOfficialGitInstallerMetadata'
            'Save-CddsiOfficialGitInstaller'
            'Get-CddsiD027GitInstallerObservation'
            'Test-CddsiGitInstallerSignature'
            'Get-CddsiD027GitPersistentPathObservation'
            'Install-CddsiGitForWindows'
        )
        'lib/live-adapters.ps1' = @(
            'Invoke-CddsiLiveAdapterOperation'
            'Invoke-CddsiLiveReadOnlyProviderOperation'
        )
        'lib/logger.ps1' = @(
            'Initialize-CddsiConsoleEncoding'
            'Protect-CddsiLogMessage'
            'Initialize-CddsiLogger'
            'Write-CddsiLog'
            'Get-CddsiLogPath'
        )
        'lib/orchestrator.ps1' = @(
            'Get-CddsiInstallPlanStepDefinitions'
            'Get-CddsiInstallPlanGrantedOperations'
            'Get-CddsiInstallPlanBindingToken'
            'Test-CddsiInstallPlan'
            'New-CddsiInstallPlan'
            'Get-CddsiTraceEventEvidenceDigest'
            'Test-CddsiOrchestratorSafeErrorCode'
            'Get-CddsiCompensationPlanBindingToken'
            'Test-CddsiCompensationPlan'
            'New-CddsiCompensationPlan'
            'Resolve-CddsiOrchestratorTrace'
            'Get-CddsiCompensationEventEvidenceDigest'
            'Resolve-CddsiCompensationTrace'
        )
        'lib/stage-policy.ps1' = @(
            'Test-CddsiStageManifest'
            'Test-CddsiOperationGrant'
            'Test-CddsiGrantClaimState'
            'Test-CddsiAuthorizationSession'
            'Resolve-CddsiGrantClaim'
            'ConvertTo-CddsiStagePolicyBindingField'
            'Test-CddsiStageGrantSessionBinding'
            'Get-CddsiWorkflowOperationSetDigest'
            'Test-CddsiGrantCompensationOperation'
            'Get-CddsiWorkflowSessionStateKey'
            'Get-CddsiWorkflowSessionBindingToken'
            'Test-CddsiWorkflowSessionState'
            'Test-CddsiWorkflowSessionBinding'
            'New-CddsiWorkflowSessionState'
            'Get-CddsiOperationUseStateKey'
            'Get-CddsiOperationUseBindingToken'
            'Test-CddsiOperationUseState'
            'Test-CddsiOperationUseBinding'
            'New-CddsiOperationUseState'
            'Resolve-CddsiOperationAuthorizationBinding'
            'Resolve-CddsiOperationAuthorization'
            'Test-CddsiCommittedOperationUseReceipt'
            'Test-CddsiTerminalOperationUseReceipt'
            'Resolve-CddsiOperationUseTerminal'
            'Resolve-CddsiUnexecutedOperationUseAbort'
            'Get-CddsiTerminalOperationSetDigest'
            'Resolve-CddsiWorkflowSessionTerminal'
        )
        'lib/state-store.ps1' = @(
            'Get-CddsiStatePath'
            'Test-CddsiStateTarget'
            'Read-CddsiState'
            'Write-CddsiStateAtomic'
        )
        'lib/state.ps1' = @(
            'New-CddsiState'
            'Test-CddsiStateSchema'
            'Set-CddsiResumeCheckpoint'
            'Claim-CddsiResumeCheckpointAttempt'
            'Complete-CddsiResumeCheckpointAttempt'
            'Clear-CddsiResumeCheckpoint'
            'ConvertTo-CddsiStateV3'
        )
        'lib/vm-calibration.ps1' = @(
            'ConvertTo-CddsiVmCalibrationCanonicalValue'
            'ConvertTo-CddsiVmCalibrationCanonicalJsonString'
            'ConvertTo-CddsiVmCalibrationCanonicalJson'
            'Get-CddsiVmCalibrationCanonicalBindingToken'
            'Test-CddsiVmCalibrationSha256Value'
            'Test-CddsiVmCalibrationSafeText'
            'Test-CddsiVmCalibrationHttpsUri'
            'Test-CddsiVmCalibrationTimestampValue'
            'Get-CddsiVmCalibrationOperationSetDigest'
            'Get-CddsiVmCalibrationSessionAnchorToken'
            'Get-CddsiVmCalibrationSessionBindingToken'
            'Test-CddsiVmCalibrationSession'
            'New-CddsiVmCalibrationSessionReference'
            'Resolve-CddsiVmCalibrationSelection'
            'Resolve-CddsiVmCalibrationReadiness'
            'Test-CddsiVmCalibrationCleanupEvidence'
            'Get-CddsiVmCalibrationOperationEvidenceRecords'
            'New-CddsiVmCalibrationOperationReceiptReferences'
            'Get-CddsiVmCalibrationEvidenceBindingToken'
            'New-CddsiVmCalibrationEvidence'
            'Test-CddsiVmCalibrationEvidence'
            'Get-CddsiCasStoreAuthorityKeyFingerprint'
            'Test-CddsiCasStoreAuthorityPublicKey'
            'Get-CddsiCasCommitReceiptSigningPayload'
            'Get-CddsiCasCommitReceiptBindingToken'
            'Test-CddsiCasCommitReceiptSignature'
            'Get-CddsiVmCalibrationConsumptionStateKey'
            'Get-CddsiVmCalibrationConsumptionBindingToken'
            'Test-CddsiVmCalibrationConsumptionState'
            'New-CddsiVmCalibrationConsumptionState'
            'Get-CddsiVmCalibrationConsumptionProposalBindingToken'
            'Test-CddsiVmCalibrationConsumptionCommitProposal'
            'Test-CddsiCommittedVmCalibrationConsumptionReceipt'
            'Resolve-CddsiVmCalibrationConsumption'
        )
        'lib/release-facts.ps1' = @(
            'Get-CddsiReleaseFactsFreezeStateKey'
            'Get-CddsiReleaseFactsFreezeStateBindingToken'
            'Test-CddsiReleaseFactsFreezeState'
            'Get-CddsiReleaseFactsFreezeProposalBindingToken'
            'Test-CddsiReleaseFactsFreezeCommitProposal'
            'Test-CddsiCommittedReleaseFactsFreezeReceipt'
            'New-CddsiReleaseFactsFreezeState'
            'Get-CddsiFrozenReleaseFactsBindingToken'
            'Resolve-CddsiFrozenReleaseFacts'
            'Test-CddsiFrozenReleaseFacts'
        )
        'lib/release-artifact.ps1' = @(
            'Test-CddsiReleaseSha256Value'
            'Test-CddsiReleaseVersionValue'
            'Test-CddsiReleaseCommitIdValue'
            'Test-CddsiReleaseTimestampValue'
            'Test-CddsiReleaseEntryPath'
            'Get-CddsiReleaseContentDigest'
            'Get-CddsiReleaseContentManifestBindingToken'
            'New-CddsiReleaseContentManifest'
            'Test-CddsiReleaseContentManifest'
            'Test-CddsiReleaseArchiveObservation'
            'Get-CddsiReleaseSidecarClaimsBindingToken'
            'ConvertTo-CddsiReleaseSidecarClaimsBytes'
            'Get-CddsiReleaseSignatureEvidenceBindingToken'
            'Get-CddsiReleaseSidecarPayloadBindingToken'
            'New-CddsiReleaseSidecarPayload'
            'Test-CddsiReleaseSidecarPayload'
            'Get-CddsiReleaseCandidateSetBindingToken'
            'New-CddsiReleaseCandidateSet'
            'Test-CddsiReleaseCandidateSet'
            'Get-CddsiReleasePromotionReceiptBindingToken'
            'New-CddsiReleasePromotionReceipt'
            'Test-CddsiReleasePromotionReceipt'
        )
        'lib/credential-helper-release.ps1' = @(
            'New-CddsiCredentialHelperReleaseContract'
            'Get-CddsiCredentialHelperBuildDescriptorBindingToken'
            'Test-CddsiCredentialHelperBuildDescriptor'
            'Get-CddsiCredentialHelperSignatureEvidenceBindingToken'
            'Test-CddsiCredentialHelperSignatureEvidence'
            'Get-CddsiCredentialHelperAclEvidenceBindingToken'
            'Test-CddsiCredentialHelperAclEvidence'
            'Get-CddsiCredentialHelperInvocationContractBindingToken'
            'Get-CddsiCredentialHelperCandidateEvidenceBindingToken'
            'Test-CddsiCredentialHelperCandidateEvidence'
            'Get-CddsiCredentialHelperProtectedBlobEvidenceBindingToken'
            'Test-CddsiCredentialHelperProtectedBlobEvidence'
            'Test-CddsiCredentialHelperInvocationOutput'
            'Get-CddsiCredentialHelperInvocationEvidenceBindingToken'
            'Test-CddsiCredentialHelperInvocationEvidence'
        )
        'lib/vm-test-relay.ps1' = @(
            'ConvertTo-CddsiVmTestRelayCanonicalJson'
            'Get-CddsiVmTestRelayPayloadSha256'
            'Get-CddsiVmTestRelayMessageSha256'
            'Get-CddsiVmTestRelayStateBindingToken'
            'Test-CddsiVmTestRelayEnvelope'
            'New-CddsiVmTestRelayState'
            'Test-CddsiVmTestRelayState'
            'Resolve-CddsiVmTestRelayTransition'
        )
        'lib/vm-reset.ps1' = @(
            'Get-CddsiVmResetBindingToken'
            'Test-CddsiVmResetAllowListEntry'
            'Test-CddsiVmResetOwnershipReceipt'
            'Test-CddsiVmResetPolicy'
            'Get-CddsiVmResetBaselineDigest'
            'Test-CddsiVmResetBaseline'
            'New-CddsiVmResetPlan'
            'Test-CddsiVmResetPlan'
            'Test-CddsiVmResetActionReceipt'
            'Resolve-CddsiVmResetDisposition'
            'New-CddsiVmCleanReadyReceipt'
            'Test-CddsiVmCleanReadyReceipt'
            'Invoke-CddsiVmGuestReset'
        )
        'lib/vm-fast-lane-readiness.ps1' = @(
            'Get-CddsiFastLaneDeploymentObservationBindingToken'
            'Test-CddsiFastLaneRepositoryObservation'
            'Test-CddsiFastLaneCredentialObservation'
            'Test-CddsiFastLaneAutomationObservation'
            'Test-CddsiFastLaneDeploymentObservation'
            'Resolve-CddsiFastLaneReadiness'
        )
    }

    ParameterContracts = @{
        'Get-CddsiProjectRoot' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Import-CddsiLibraries' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Initialize-CddsiScript' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Get-CddsiProjectStage' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'New-CddsiOperationResult' = @{ Kind = 'Pure'; Mandatory = @('Operation', 'Status'); Mode = $true }
        'Get-CddsiOperationExitCode' = @{ Kind = 'Pure'; Mandatory = @('Status'); Mode = $false }
        'Format-CddsiOperationCliSummary' = @{ Kind = 'Pure'; Mandatory = @('Result'); Mode = $false }
        'Resolve-CddsiExecutionMode' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiRealMutationAllowed' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Assert-CddsiMutationAllowed' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Operation'); Mode = $true }
        'Get-CddsiConfigLibraryPath' = @{ Kind = 'Pure'; Mandatory = @('LocalAppDataPath'); Mode = $false }
        'Protect-CddsiSecret' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Protect-CddsiReportText' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Find-CddsiPotentialSecrets' = @{ Kind = 'Pure'; Mandatory = @('Content'); Mode = $false }
        'Test-CddsiDeepSeekApiKeyFormat' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiSupplyChainTextBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Text'); Mode = $false }
        'Get-CddsiSourceUriBindingToken' = @{ Kind = 'Pure'; Mandatory = @('SourceUri'); Mode = $false }
        'Test-CddsiOfficialArtifactUri' = @{ Kind = 'Pure'; Mandatory = @('SourceUri', 'ExpectedOwner'); Mode = $false }
        'Test-CddsiOfficialArtifactRedirectUri' = @{ Kind = 'Pure'; Mandatory = @('SourceUri', 'ExpectedOwner'); Mode = $false }
        'Get-CddsiSourceObservationBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Observation'); Mode = $false }
        'Test-CddsiSourceObservation' = @{ Kind = 'Pure'; Mandatory = @('Observation', 'Descriptor', 'ExpectedArtifactType', 'ExpectedRunId', 'ExpectedProfile', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiArtifactDescriptorBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Descriptor'); Mode = $false }
        'Test-CddsiArtifactDescriptor' = @{ Kind = 'Pure'; Mandatory = @('ExpectedArtifactType'); Mode = $false }
        'Get-CddsiSignatureEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'New-CddsiSignatureEvidenceVerdict' = @{ Kind = 'Pure'; Mandatory = @('Descriptor', 'ExpectedArtifactType', 'PathBindingToken', 'SourceObservation', 'FileObservation', 'SignatureObservation', 'ExpectedRunId', 'ExpectedProfile', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiSignatureEvidence' = @{ Kind = 'Pure'; Mandatory = @('ExpectedPath', 'ExpectedArtifactType', 'Descriptor', 'SourceObservation', 'ExpectedRunId', 'ExpectedProfile', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiSchemaVersionOne' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiUtcTimestampValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiSafeIdentifierValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiCanonicalUuidValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiPathBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Path'); Mode = $false }
        'Test-CddsiArtifactHashBinding' = @{ Kind = 'Pure'; Mandatory = @('ActualSha256', 'ExpectedSha256'); Mode = $false }
        'ConvertFrom-CddsiJson' = @{ Kind = 'Pure'; Mandatory = @('Content'); Mode = $false }
        'ConvertTo-CddsiJson' = @{ Kind = 'Pure'; Mandatory = @('InputObject'); Mode = $false }
        'Test-CddsiExactPropertySet' = @{ Kind = 'Pure'; Mandatory = @('Expected'); Mode = $false }
        'Get-CddsiSignatureEvidencePayload' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiCoworkServiceStatus' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiCoworkReadiness' = @{ Kind = 'Pure'; Mandatory = @('EnvironmentStatus', 'DesktopStatus', 'VirtualMachinePlatformStatus', 'HardwareVirtualizationStatus', 'ServiceStatus'); Mode = $true }
        'Resolve-CddsiEffectiveSurfaces' = @{ Kind = 'Pure'; Mandatory = @('RequestedSurfaces', 'EnvironmentStatus', 'DesktopStatus', 'GitStatus', 'CoworkStatus'); Mode = $true }
        'Get-CddsiCoworkBlockingReasons' = @{ Kind = 'Pure'; Mandatory = @('Readiness'); Mode = $false }
        'Resolve-CddsiCoworkFeatureChangeTranscript' = @{ Kind = 'Pure'; Mandatory = @('Transcript', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'PrepareInitialOperationUseState', 'PrepareTerminalOperationUseState', 'NowUtc'); Mode = $false }
        'New-CddsiCoworkCheckpointPlan' = @{ Kind = 'Pure'; Mandatory = @('State', 'PrepareTranscript', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'PrepareClaimedOperationUseState', 'PrepareTerminalOperationUseState', 'ResumeAvailableOperationUseState', 'ExpectedStateRevision', 'CheckpointId', 'UpdatedAtUtc', 'ExpiresAtUtc'); Mode = $false }
        'Test-CddsiResumeCheckpointEligibility' = @{ Kind = 'Pure'; Mandatory = @('State', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'PrepareTerminalOperationUseState', 'ResumeOperationUseState', 'NowUtc'); Mode = $false }
        'Resolve-CddsiCoworkResume' = @{ Kind = 'Pure'; Mandatory = @('State', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'PrepareTerminalOperationUseState', 'ResumeClaimedOperationUseState', 'ResumeTerminalOperationUseState', 'NowUtc', 'UpdatedAtUtc', 'FeatureState', 'CleanupOutcome'); Mode = $false }
        'Enable-CddsiVirtualMachinePlatform' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'New-CddsiCredentialHelperContract' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiCredentialCaptureMetadata' = @{ Kind = 'Pure'; Mandatory = @('Metadata', 'ExpectedRunId'); Mode = $false }
        'Test-CddsiCredentialAuthorizationBinding' = @{ Kind = 'Pure'; Mandatory = @('Binding'); Mode = $false }
        'Resolve-CddsiCredentialAuthorizationBinding' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'Confirmation', 'CommittedOperationUseReceipt', 'ExpectedOperation', 'ExpectedRunId', 'OccurredAtUtc', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiCredentialProtectionEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedAuthorizationBinding', 'ExpectedHandleToken', 'ExpectedCaptureNonce', 'ExpectedOperationNonce', 'ExpectedHelperArtifactSha256', 'ExpectedCreatedAtUtc'); Mode = $false }
        'ConvertFrom-CddsiCredentialHelperOutput' = @{ Kind = 'Pure'; Mandatory = @('StandardOutput', 'ExitCode', 'InvocationStatus', 'ElapsedMilliseconds', 'ExpectedHelperArtifactSha256', 'ObservedHelperArtifactSha256'); Mode = $false }
        'Read-CddsiDeepSeekApiKeySecure' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Protect-CddsiDeepSeekCredential' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'HandleToken', 'CaptureNonce', 'OperationNonce', 'HelperArtifactSha256', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'Confirmation', 'CommittedOperationUseReceipt', 'CreatedAtUtc', 'ValidationTimeUtc'); Mode = $true }
        'Get-CddsiCredentialLifecycleProviderEvidenceSha256' = @{ Kind = 'Pure'; Mandatory = @('PlanId', 'TransactionId', 'Sequence', 'Name', 'Outcome', 'MutationState', 'AuthorizationSlot', 'Operation', 'OperationUseId', 'OperationUseRevision', 'OperationUseTerminalState', 'OccurredAtUtc', 'AuthorizationBindingToken'); Mode = $false }
        'Get-CddsiCredentialLifecycleProviderAggregateSha256' = @{ Kind = 'Pure'; Mandatory = @('PlanId', 'TransactionId', 'AuthorizationSlot', 'Operation', 'OperationUseId', 'OperationUseRevision', 'OperationUseTerminalState', 'Events'); Mode = $false }
        'New-CddsiCredentialLifecyclePlan' = @{ Kind = 'Pure'; Mandatory = @('Action', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'PrimaryConfirmation', 'PrimaryCommittedOperationUseReceipt', 'ExpectedRunId', 'CreatedAtUtc', 'ValidationTimeUtc', 'CredentialBlobToken', 'HelperArtifactSha256'); Mode = $false }
        'Test-CddsiCredentialLifecycleEvent' = @{ Kind = 'Pure'; Mandatory = @('Event', 'ExpectedSequence', 'ExpectedStep', 'ExpectedOperationUseId', 'ExpectedAuthorizationBindingToken', 'ExpectedTerminalReceipt', 'PlanId', 'TransactionId', 'MinimumOccurredAtUtc', 'ValidationTimeUtc'); Mode = $false }
        'Resolve-CddsiCredentialLifecycleTranscript' = @{ Kind = 'Pure'; Mandatory = @('Plan', 'Transcript', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'PrimaryConfirmation', 'PrimaryCommittedOperationUseReceipt', 'PrimaryTerminalOperationUseReceipt', 'ExpectedRunId', 'ExpectedCreatedAtUtc', 'ValidationTimeUtc', 'ExpectedCredentialBlobToken', 'ExpectedHelperArtifactSha256'); Mode = $false }
        'ConvertTo-CddsiDeepSeekApiErrorClass' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Invoke-CddsiDeepSeekApiValidation' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Get-CddsiAcceptancePlan' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiClaudeCodeSettingsIntegrityContract' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiClaudeCodeSettingsFingerprint' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Test-CddsiClaudeCodeSettingsUnchanged' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiApiKeyLeak' = @{ Kind = 'Pure'; Mandatory = @('Content'); Mode = $false }
        'Test-CddsiExternalE2eEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedArtifactSha256', 'ExpectedEnvironmentImageSha256', 'ExpectedProfile', 'ExpectedScenarioId', 'ExpectedRunId', 'ExpectedNowUtc', 'MaxEvidenceAgeSeconds', 'ExpectedSurfaceEvidenceTokens', 'PreviouslyConsumedEvidenceTokens'); Mode = $false }
        'Resolve-CddsiCompensationStatus' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Resolve-CddsiAcceptanceStatus' = @{ Kind = 'Pure'; Mandatory = @('Capabilities', 'UiEvidence', 'Compensation'); Mode = $false }
        'New-CddsiAcceptanceEvidence' = @{ Kind = 'Pure'; Mandatory = @('ExpectedCapabilities', 'ExpectedArtifactSha256', 'ExpectedEnvironmentImageSha256', 'ExpectedProfile', 'ExpectedScenarioId', 'ExpectedRunId', 'ExpectedNowUtc', 'MaxEvidenceAgeSeconds', 'ExpectedSurfaceEvidenceTokens', 'PreviouslyConsumedEvidenceTokens'); Mode = $false }
        'Test-CddsiAcceptanceEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedCapabilities', 'ExpectedArtifactSha256', 'ExpectedEnvironmentImageSha256', 'ExpectedProfile', 'ExpectedScenarioId', 'ExpectedRunId', 'ExpectedNowUtc', 'MaxEvidenceAgeSeconds', 'ExpectedSurfaceEvidenceTokens', 'PreviouslyConsumedEvidenceTokens'); Mode = $false }
        'Test-CddsiChatAcceptance' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Test-CddsiCodeAcceptance' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Test-CddsiCoworkAcceptance' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiRepairPlan' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Invoke-CddsiDesktopRepair' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Invoke-CddsiDesktopAcceptance' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'New-CddsiAcceptanceReport' = @{ Kind = 'Pure'; Mandatory = @('Results', 'PathTokenValues'); Mode = $false }
        'Get-CddsiClaudeDesktopConfigLibraryPath' = @{ Kind = 'Pure'; Mandatory = @('LocalAppDataPath'); Mode = $false }
        'Test-CddsiConfigLibraryTarget' = @{ Kind = 'Pure'; Mandatory = @('TargetPath', 'LocalAppDataPath'); Mode = $false }
        'Read-CddsiClaudeDesktopConfigLibrary' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'New-CddsiClaudeDesktopDesiredConfig' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiClaudeDesktopConfigContract' = @{ Kind = 'Pure'; Mandatory = @('Config'); Mode = $false }
        'ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet' = @{ Kind = 'Pure'; Mandatory = @('Config', 'CredentialHelperPath'); Mode = $false }
        'Compare-CddsiClaudeDesktopConfig' = @{ Kind = 'Pure'; Mandatory = @('Current', 'Desired'); Mode = $false }
        'Test-CddsiConfigOperationAuthorizationBundle' = @{ Kind = 'Pure'; Mandatory = @('AuthorizationBundle', 'Operation', 'OperationUseId', 'ExpectedState'); Mode = $false }
        'Get-CddsiConfigBackupEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiConfigBackupEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'BackupAuthorization'); Mode = $false }
        'Test-CddsiManagedPolicyValueSet' = @{ Kind = 'Pure'; Mandatory = @('ValueSet'); Mode = $false }
        'New-CddsiConfigBackupPlan' = @{ Kind = 'Pure'; Mandatory = @('SourceDecision', 'BackupAuthorization', 'BackupId', 'OperationNonce', 'ValidationTimeUtc'); Mode = $false }
        'New-CddsiConfigTransactionPlan' = @{ Kind = 'Pure'; Mandatory = @('SourceDecision', 'ValueSet', 'BackupEvidence', 'BackupAuthorization', 'WriteAuthorization', 'ValidationTimeUtc'); Mode = $false }
        'Resolve-CddsiConfigTransactionTranscript' = @{ Kind = 'Pure'; Mandatory = @('Transcript', 'ExpectedPlan', 'SourceDecision', 'ValueSet', 'BackupEvidence', 'BackupAuthorization', 'WriteAuthorization', 'WriteTerminalAuthorization'); Mode = $false }
        'New-CddsiConfigRestorableBackup' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'New-CddsiConfigRedactedSnapshot' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Write-CddsiClaudeDesktopConfigAtomic' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'DesiredConfig'); Mode = $true }
        'Restore-CddsiClaudeDesktopConfig' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'BackupId'); Mode = $true }
        'Get-CddsiDesktopEnvironmentSnapshot' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'MinimumBuild', 'SupportedArchitectures'); Mode = $false }
        'Test-CddsiVirtualMachinePlatform' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Test-CddsiHardwareVirtualization' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiClaudeDesktopProcessState' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Stop-CddsiClaudeDesktop' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Start-CddsiClaudeDesktop' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Restart-CddsiClaudeDesktop' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'New-CddsiD027ClaudeDesktopSourceDescriptor' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiD027ClaudeDesktopSourceDescriptor' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiD027ClaudeSanitizedDownloadUri' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiD027ClaudeDownloadDestinationPath' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiD027ClaudeDownloadReceiptBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Receipt'); Mode = $false }
        'Get-CddsiD027ClaudeFileIdentityToken' = @{ Kind = 'Pure'; Mandatory = @('FinalPathBindingToken', 'VolumeSerialNumberHex', 'FileIndexHex', 'ArtifactSha256', 'ArtifactSizeBytes'); Mode = $false }
        'Get-CddsiD027ClaudeContentBindingToken' = @{ Kind = 'Pure'; Mandatory = @('ArtifactSha256', 'ArtifactSizeBytes'); Mode = $false }
        'New-CddsiD027ClaudeDownloadReceipt' = @{ Kind = 'Pure'; Mandatory = @('RunId', 'StagingRootPath', 'DestinationPath', 'FileIdentityToken', 'SanitizedRedirectUris', 'ArtifactSha256', 'ArtifactSizeBytes', 'ObservedAtUtc'); Mode = $false }
        'Test-CddsiD027ClaudeDownloadReceipt' = @{ Kind = 'Pure'; Mandatory = @('ExpectedRunId', 'ExpectedStagingRootPath', 'ExpectedDestinationPath', 'ExpectedFileIdentityToken', 'ExpectedArtifactSha256', 'ExpectedArtifactSizeBytes', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiD027ClaudeDownloadedArtifactObservation' = @{ Kind = 'Pure'; Mandatory = @('ExpectedRunId', 'ExpectedStagingRootPath', 'ExpectedDestinationPath', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiD027ClaudeManifestBindingToken' = @{ Kind = 'Pure'; Mandatory = @('ManifestIdentity'); Mode = $false }
        'Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiD027ClaudeMsixSignatureEvidenceContract' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ManifestIdentity', 'DownloadReceipt', 'HeldArtifactObservation', 'ExpectedRunId', 'ExpectedStagingRootPath', 'ExpectedDestinationPath', 'ValidationTimeUtc'); Mode = $false }
        'ConvertFrom-CddsiD027ClaudeAppxManifestBytes' = @{ Kind = 'Pure'; Mandatory = @('ManifestBytes'); Mode = $false }
        'Read-CddsiD027ClaudeMsixManifest' = @{ Kind = 'Pure'; Mandatory = @('PackageStream'); Mode = $false }
        'Get-CddsiClaudeDesktopMsixStatus' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'MinimumVersion', 'RequiredScope', 'ExpectedArchitecture'); Mode = $false }
        'ConvertFrom-CddsiAnthropicMsixReleaseMetadata' = @{ Kind = 'Pure'; Mandatory = @('ReleaseDocument', 'Architecture', 'Channel'); Mode = $false }
        'Get-CddsiOfficialMsixMetadata' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Architecture', 'Channel'); Mode = $false }
        'Save-CddsiOfficialClaudeDesktopMsix' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'DestinationPath', 'ArtifactDescriptor'); Mode = $true }
        'Test-CddsiClaudeDesktopMsixSignature' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'PackagePath', 'ArtifactDescriptor', 'SourceObservation', 'ArtifactProfile', 'ValidationTimeUtc'); Mode = $false }
        'Install-CddsiClaudeDesktopMsix' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'PackagePath', 'SignatureEvidence', 'ArtifactDescriptor', 'SourceObservation', 'ArtifactProfile', 'ValidationTimeUtc'); Mode = $true }
        'Update-CddsiClaudeDesktopMsix' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'PackagePath', 'SignatureEvidence', 'ArtifactDescriptor', 'SourceObservation', 'ArtifactProfile', 'ValidationTimeUtc'); Mode = $true }
        'Get-CddsiLiveReadOnlyCapabilityContracts' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiExactNameSet' = @{ Kind = 'Pure'; Mandatory = @('Actual', 'Expected'); Mode = $false }
        'Test-CddsiExactNotePropertySet' = @{ Kind = 'Pure'; Mandatory = @('InputObject', 'Expected'); Mode = $false }
        'Test-CddsiLogicalResourceToken' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiLiveReadOnlyCapabilityTuple' = @{ Kind = 'Pure'; Mandatory = @('ProviderSet', 'Provider', 'Operation', 'ResourceToken', 'ArgumentCount'); Mode = $false }
        'Assert-CddsiProductAccessLedgerEntryValues' = @{ Kind = 'Pure'; Mandatory = @('ProviderSet', 'Provider', 'Operation', 'ResourceToken', 'ArgumentCount', 'Allowed', 'Expected', 'IsMutation', 'FailureInjected', 'Outcome', 'ErrorCode'); Mode = $false }
        'New-CddsiAccessLedger' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Add-CddsiProductAccessLedgerEntry' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Provider', 'Operation', 'ResourceToken', 'Allowed', 'Expected', 'IsMutation', 'FailureInjected', 'Outcome'); Mode = $false }
        'New-CddsiUnloadedProviderSet' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'New-CddsiLiveReadOnlyProviderSet' = @{ Kind = 'Pure'; Mandatory = @('RunId', 'Stage', 'EnvironmentTier', 'ArtifactProfile', 'AdapterSha256', 'LoadOperationUseId', 'LoadReceiptBindingToken'); Mode = $false }
        'New-CddsiExecutionContext' = @{ Kind = 'Pure'; Mandatory = @('RunId', 'Mode', 'Stage', 'EnvironmentTier', 'SandboxRoot', 'Paths', 'Providers', 'Policy'); Mode = $true }
        'Assert-CddsiExecutionContext' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiExecutionPathTokenValues' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Invoke-CddsiProviderOperation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Provider', 'Operation', 'ResourceToken'); Mode = $false }
        'Get-CddsiIsolationEvidence' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Assert-CddsiIsolationEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Get-CddsiFakeInputFieldNames' = @{ Kind = 'Pure'; Mandatory = @('InputObject'); Mode = $false }
        'Get-CddsiFakeInputFieldValue' = @{ Kind = 'Pure'; Mandatory = @('InputObject', 'Name'); Mode = $false }
        'Test-CddsiFakeValueEqual' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiFakeScenarioBindingToken' = @{ Kind = 'Pure'; Mandatory = @('ExpectedCalls', 'FailureInjections'); Mode = $false }
        'Test-CddsiFakeMutationOperation' = @{ Kind = 'Pure'; Mandatory = @('Provider', 'Operation'); Mode = $false }
        'Test-CddsiFakeResourceTokenAllowed' = @{ Kind = 'Pure'; Mandatory = @('Policy'); Mode = $false }
        'Assert-CddsiFakeProviderScenario' = @{ Kind = 'Pure'; Mandatory = @('ProviderSet'); Mode = $false }
        'New-CddsiFakeProviderSet' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Invoke-CddsiFakeProviderOperation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Provider', 'Operation', 'ResourceToken'); Mode = $false }
        'Assert-CddsiFakeProviderExpectations' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Test-CddsiD027Windows11X64Platform' = @{ Kind = 'ProcessScoped'; Mandatory = @(); Mode = $false }
        'Get-CddsiD027SnapshotPlatformObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiD027GitSnapshotWorkloadBindingToken' = @{ Kind = 'Pure'; Mandatory = @('RunId', 'ExecutionArtifactSha256'); Mode = $false }
        'Get-CddsiD027ClaudeSnapshotWorkloadBindingToken' = @{ Kind = 'Pure'; Mandatory = @('WorkloadDescriptor'); Mode = $false }
        'Test-CddsiD027ClaudeSnapshotWorkloadDescriptor' = @{ Kind = 'Pure'; Mandatory = @('WorkloadDescriptor'); Mode = $false }
        'Test-CddsiD027CanonicalBase64' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiD027SnapshotAuthorityKeySha256' = @{ Kind = 'Pure'; Mandatory = @('RsaModulusBase64', 'RsaExponentBase64'); Mode = $false }
        'Get-CddsiD027SnapshotAuthorityPolicy' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiD027ExternalSnapshotReceiptBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Receipt'); Mode = $false }
        'Test-CddsiD027ExternalSnapshotReceipt' = @{ Kind = 'Pure'; Mandatory = @('Receipt', 'ExpectedRunId', 'ExpectedExecutionArtifactSha256', 'PlatformObservation', 'ValidationTimeUtc', 'AuthorityPolicy'); Mode = $false }
        'Test-CddsiD027ClaudeExternalSnapshotReceipt' = @{ Kind = 'Pure'; Mandatory = @('Receipt', 'WorkloadDescriptor', 'ExpectedRunId', 'PlatformObservation', 'ValidationTimeUtc', 'AuthorityPolicy'); Mode = $false }
        'Get-CddsiD027SnapshotReceiptHeldFileObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Stream'); Mode = $false }
        'Read-CddsiD027ExternalSnapshotReceipt' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ReceiptPath', 'ExpectedReceiptSha256'); Mode = $false }
        'Enable-CddsiD027GitLiveSessionAuthorization' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ReceiptPath', 'ExpectedReceiptSha256', 'ExpectedExecutionArtifactSha256'); Mode = $false }
        'Clear-CddsiD027GitLiveSessionAuthorization' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Get-CddsiD027GitWinVerifyTrustResult' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'FilePath'); Mode = $false }
        'Assert-CddsiD027GitLiveBootstrapContext' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Assert-CddsiD027GitLiveContext' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'ConvertFrom-CddsiGitVersionProbeResult' = @{ Kind = 'Pure'; Mandatory = @('ProbeResult'); Mode = $false }
        'ConvertTo-CddsiGitInstallerReceiptVersion' = @{ Kind = 'Pure'; Mandatory = @('GitVersion'); Mode = $false }
        'ConvertFrom-CddsiGitPeHeader' = @{ Kind = 'Pure'; Mandatory = @('HeaderBytes', 'ImageLength'); Mode = $false }
        'Test-CddsiCurrentProcessElevated' = @{ Kind = 'ProcessScoped'; Mandatory = @(); Mode = $false }
        'Get-CddsiGitForWindowsRegistryObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ExpectedInstallRoot', 'ExpectedReceiptVersion'); Mode = $false }
        'Test-CddsiGitProtectedInstallPathSet' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'InstallRoot', 'RequiredPaths'); Mode = $false }
        'Get-CddsiGitForWindowsPrivateDllObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'BinPath', 'ExpectedPaths'); Mode = $false }
        'Get-CddsiGitForWindowsSignedComponentObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ComponentPath', 'ComponentRole'); Mode = $false }
        'Resolve-CddsiGitExecutablePathSet' = @{ Kind = 'Pure'; Mandatory = @('CandidatePaths', 'ShadowPaths'); Mode = $false }
        'New-CddsiGitVersionProbeStartInfo' = @{ Kind = 'Pure'; Mandatory = @('ExecutablePath', 'SystemRootPath', 'ProductTempPath'); Mode = $false }
        'Initialize-CddsiD027GitProbeRunnerType' = @{ Kind = 'ProcessScoped'; Mandatory = @(); Mode = $false }
        'Invoke-CddsiGitVersionProbe' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ExecutablePath', 'ExpectedFileIdentityToken'); Mode = $false }
        'Get-CddsiGitForWindowsExecutableObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ExecutablePath'); Mode = $false }
        'Get-CddsiLiveGitForWindowsObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'MinimumVersion'); Mode = $false }
        'Get-CddsiGitForWindowsStatus' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'MinimumVersion'); Mode = $false }
        'ConvertTo-CddsiD027NormalizedGitHubReleaseDocument' = @{ Kind = 'Pure'; Mandatory = @('ReleaseDocument'); Mode = $false }
        'Get-CddsiD027GitDownloadReceiptBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Receipt'); Mode = $false }
        'New-CddsiD027GitDownloadReceipt' = @{ Kind = 'Pure'; Mandatory = @('ArtifactDescriptor', 'DestinationPath', 'FileIdentityToken', 'SourceObservation', 'ExpectedRunId', 'ArtifactProfile', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiD027GitDownloadReceipt' = @{ Kind = 'Pure'; Mandatory = @('ArtifactDescriptor', 'ExpectedDestinationPath', 'ExpectedFileIdentityToken', 'ExpectedRunId', 'ExpectedProfile', 'ValidationTimeUtc'); Mode = $false }
        'Resolve-CddsiD027GitInstallerDescriptor' = @{ Kind = 'Pure'; Mandatory = @('ArtifactDescriptor', 'InstallerObservation'); Mode = $false }
        'Get-CddsiD027GitInstallerProcessPolicy' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Assert-CddsiD027GitDirectorySecurity' = @{ Kind = 'ProcessScoped'; Mandatory = @('Path', 'Purpose'); Mode = $false }
        'Test-CddsiD027GitPostInstallReadbackEligible' = @{ Kind = 'Pure'; Mandatory = @('Started', 'InstallerStillRunning', 'CompletionObservationFailed'); Mode = $false }
        'ConvertTo-CddsiD027GitInstallerExitResult' = @{ Kind = 'Pure'; Mandatory = @('Started', 'UacCancelled', 'ReadbackTrusted', 'ChangedObserved', 'RestartObserved'); Mode = $false }
        'ConvertFrom-CddsiGitHubReleaseMetadata' = @{ Kind = 'Pure'; Mandatory = @('ReleaseDocument', 'Architecture'); Mode = $false }
        'Get-CddsiOfficialGitInstallerMetadata' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Architecture'); Mode = $false }
        'Save-CddsiOfficialGitInstaller' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'DestinationPath', 'ArtifactDescriptor'); Mode = $true }
        'Get-CddsiD027GitInstallerObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'InstallerPath', 'ArtifactDescriptor'); Mode = $false }
        'Test-CddsiGitInstallerSignature' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'InstallerPath', 'ArtifactDescriptor', 'SourceObservation', 'ArtifactProfile', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiD027GitPersistentPathObservation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'ExpectedArtifactVersion'); Mode = $false }
        'Install-CddsiGitForWindows' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'InstallerPath', 'SignatureEvidence', 'ArtifactDescriptor', 'SourceObservation', 'ArtifactProfile', 'ValidationTimeUtc'); Mode = $true }
        'Invoke-CddsiLiveAdapterOperation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc', 'AdapterSha256'); Mode = $false }
        'Invoke-CddsiLiveReadOnlyProviderOperation' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Provider', 'Operation', 'ResourceToken', 'Arguments'); Mode = $false }
        'Initialize-CddsiConsoleEncoding' = @{ Kind = 'ProcessScoped'; Mandatory = @(); Mode = $false }
        'Protect-CddsiLogMessage' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Initialize-CddsiLogger' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Write-CddsiLog' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Message'); Mode = $false }
        'Get-CddsiLogPath' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiInstallPlanStepDefinitions' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiInstallPlanGrantedOperations' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiInstallPlanBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Plan'); Mode = $false }
        'Test-CddsiInstallPlan' = @{ Kind = 'Pure'; Mandatory = @('Plan', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState'); Mode = $false }
        'New-CddsiInstallPlan' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'InstallScope', 'RunId'); Mode = $false }
        'Get-CddsiTraceEventEvidenceDigest' = @{ Kind = 'Pure'; Mandatory = @('Plan', 'Event'); Mode = $false }
        'Test-CddsiOrchestratorSafeErrorCode' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiCompensationPlanBindingToken' = @{ Kind = 'Pure'; Mandatory = @('CompensationPlan'); Mode = $false }
        'Test-CddsiCompensationPlan' = @{ Kind = 'Pure'; Mandatory = @('CompensationPlan', 'Plan', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState'); Mode = $false }
        'New-CddsiCompensationPlan' = @{ Kind = 'Pure'; Mandatory = @('Plan', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'AffectedOperationUseReceipts'); Mode = $false }
        'Resolve-CddsiOrchestratorTrace' = @{ Kind = 'Pure'; Mandatory = @('Plan', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'Events'); Mode = $false }
        'Get-CddsiCompensationEventEvidenceDigest' = @{ Kind = 'Pure'; Mandatory = @('CompensationPlan', 'Event'); Mode = $false }
        'Resolve-CddsiCompensationTrace' = @{ Kind = 'Pure'; Mandatory = @('CompensationPlan', 'Plan', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'Events'); Mode = $false }
        'Test-CddsiStageManifest' = @{ Kind = 'Pure'; Mandatory = @('Manifest'); Mode = $false }
        'Test-CddsiOperationGrant' = @{ Kind = 'Pure'; Mandatory = @('Grant'); Mode = $false }
        'Test-CddsiGrantClaimState' = @{ Kind = 'Pure'; Mandatory = @('ClaimState'); Mode = $false }
        'Test-CddsiAuthorizationSession' = @{ Kind = 'Pure'; Mandatory = @('AuthorizationSession'); Mode = $false }
        'Resolve-CddsiGrantClaim' = @{ Kind = 'Pure'; Mandatory = @('OperationGrant', 'ClaimState', 'ClaimId', 'ExpectedRevision', 'NowUtc'); Mode = $false }
        'ConvertTo-CddsiStagePolicyBindingField' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiStageGrantSessionBinding' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession'); Mode = $false }
        'Get-CddsiWorkflowOperationSetDigest' = @{ Kind = 'Pure'; Mandatory = @('OperationGrant'); Mode = $false }
        'Test-CddsiGrantCompensationOperation' = @{ Kind = 'Pure'; Mandatory = @('OperationGrant', 'Operation'); Mode = $false }
        'Get-CddsiWorkflowSessionStateKey' = @{ Kind = 'Pure'; Mandatory = @('WorkflowSessionState'); Mode = $false }
        'Get-CddsiWorkflowSessionBindingToken' = @{ Kind = 'Pure'; Mandatory = @('WorkflowSessionState'); Mode = $false }
        'Test-CddsiWorkflowSessionState' = @{ Kind = 'Pure'; Mandatory = @('WorkflowSessionState'); Mode = $false }
        'Test-CddsiWorkflowSessionBinding' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState'); Mode = $false }
        'New-CddsiWorkflowSessionState' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession'); Mode = $false }
        'Get-CddsiOperationUseStateKey' = @{ Kind = 'Pure'; Mandatory = @('OperationUseState'); Mode = $false }
        'Get-CddsiOperationUseBindingToken' = @{ Kind = 'Pure'; Mandatory = @('OperationUseState'); Mode = $false }
        'Test-CddsiOperationUseState' = @{ Kind = 'Pure'; Mandatory = @('OperationUseState'); Mode = $false }
        'Test-CddsiOperationUseBinding' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState'); Mode = $false }
        'New-CddsiOperationUseState' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'Operation'); Mode = $false }
        'Resolve-CddsiOperationAuthorizationBinding' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'Confirmation', 'Operation', 'RunId', 'NowUtc'); Mode = $false }
        'Resolve-CddsiOperationAuthorization' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Confirmation', 'Operation', 'OperationUseId', 'ExpectedRevision', 'RunId', 'NowUtc'); Mode = $false }
        'Test-CddsiCommittedOperationUseReceipt' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiTerminalOperationUseReceipt' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'Outcome', 'ExpectedProviderEvidenceDigest'); Mode = $false }
        'Resolve-CddsiOperationUseTerminal' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ExpectedRevision', 'Outcome', 'ProviderEvidenceDigest', 'OccurredAtUtc', 'IdempotencyKey'); Mode = $false }
        'Resolve-CddsiUnexecutedOperationUseAbort' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ExpectedRevision', 'ReasonCode', 'OccurredAtUtc', 'IdempotencyKey'); Mode = $false }
        'Get-CddsiTerminalOperationSetDigest' = @{ Kind = 'Pure'; Mandatory = @('OperationGrant', 'OperationUseStates'); Mode = $false }
        'Resolve-CddsiWorkflowSessionTerminal' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseStates', 'ExpectedRevision', 'Outcome', 'OccurredAtUtc', 'IdempotencyKey'); Mode = $false }
        'Get-CddsiStatePath' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $false }
        'Test-CddsiStateTarget' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Path'); Mode = $false }
        'Read-CddsiState' = @{ Kind = 'ContextBound'; Mandatory = @('Context'); Mode = $true }
        'Write-CddsiStateAtomic' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'State'); Mode = $true }
        'New-CddsiState' = @{ Kind = 'Pure'; Mandatory = @('RunId', 'TimestampUtc'); Mode = $false }
        'Test-CddsiStateSchema' = @{ Kind = 'Pure'; Mandatory = @('State'); Mode = $false }
        'Set-CddsiResumeCheckpoint' = @{ Kind = 'Pure'; Mandatory = @('State', 'ExpectedStateRevision', 'CheckpointId', 'Stage', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'ArtifactProfile', 'GrantId', 'ClaimId', 'WorkflowSessionStateKeySha256', 'PrepareOperationUseId', 'PrepareTerminalState', 'PrepareTerminalReceiptBindingToken', 'PrepareProviderEvidenceDigest', 'PrepareOccurredAtUtc', 'ResumeAvailableStateKeySha256', 'ResumeAvailableReceiptBindingToken', 'MutationState', 'UpdatedAtUtc', 'ExpiresAtUtc', 'AuthorizationExpiresAtUtc'); Mode = $false }
        'Claim-CddsiResumeCheckpointAttempt' = @{ Kind = 'Pure'; Mandatory = @('State', 'ExpectedCheckpointId', 'ExpectedStateRevision', 'ExpectedCheckpointRevision', 'AttemptClaimId', 'ResumeOperationUseId', 'ResumeClaimedReceiptBindingToken', 'ResumeClaimedAtUtc', 'UpdatedAtUtc'); Mode = $false }
        'Complete-CddsiResumeCheckpointAttempt' = @{ Kind = 'Pure'; Mandatory = @('State', 'ExpectedCheckpointId', 'ExpectedStateRevision', 'ExpectedCheckpointRevision', 'TerminalState', 'TerminalReceiptBindingToken', 'ProviderEvidenceDigest', 'OccurredAtUtc', 'UpdatedAtUtc'); Mode = $false }
        'Clear-CddsiResumeCheckpoint' = @{ Kind = 'Pure'; Mandatory = @('State', 'ExpectedCheckpointId', 'ExpectedStateRevision', 'ExpectedCheckpointRevision', 'UpdatedAtUtc'); Mode = $false }
        'ConvertTo-CddsiStateV3' = @{ Kind = 'Pure'; Mandatory = @('StateV2', 'MigratedAtUtc'); Mode = $false }
        'ConvertTo-CddsiVmCalibrationCanonicalValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'ConvertTo-CddsiVmCalibrationCanonicalJsonString' = @{ Kind = 'Pure'; Mandatory = @('Value'); Mode = $false }
        'ConvertTo-CddsiVmCalibrationCanonicalJson' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiVmCalibrationCanonicalBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Value'); Mode = $false }
        'Test-CddsiVmCalibrationSha256Value' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiVmCalibrationSafeText' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiVmCalibrationHttpsUri' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiVmCalibrationTimestampValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiVmCalibrationOperationSetDigest' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiVmCalibrationSessionAnchorToken' = @{ Kind = 'Pure'; Mandatory = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseStates'); Mode = $false }
        'Get-CddsiVmCalibrationSessionBindingToken' = @{ Kind = 'Pure'; Mandatory = @('ExpectedSession'); Mode = $false }
        'Test-CddsiVmCalibrationSession' = @{ Kind = 'Pure'; Mandatory = @('ExpectedSession', 'ExpectedSessionAnchorToken', 'ValidationTimeUtc'); Mode = $false }
        'New-CddsiVmCalibrationSessionReference' = @{ Kind = 'Pure'; Mandatory = @('ExpectedSession', 'ExpectedSessionAnchorToken', 'ValidationTimeUtc'); Mode = $false }
        'Resolve-CddsiVmCalibrationSelection' = @{ Kind = 'Pure'; Mandatory = @('MsixCandidates'); Mode = $false }
        'Resolve-CddsiVmCalibrationReadiness' = @{ Kind = 'Pure'; Mandatory = @('OsImage', 'MsixCandidates', 'Selection', 'Git', 'DesktopBehavior'); Mode = $false }
        'Test-CddsiVmCalibrationCleanupEvidence' = @{ Kind = 'Pure'; Mandatory = @('Cleanup'); Mode = $false }
        'Get-CddsiVmCalibrationOperationEvidenceRecords' = @{ Kind = 'Pure'; Mandatory = @('ObservationStartedAtUtc', 'OsImage', 'MsixCandidates', 'Selection', 'Git', 'DesktopBehavior', 'Readiness', 'Cleanup'); Mode = $false }
        'New-CddsiVmCalibrationOperationReceiptReferences' = @{ Kind = 'Pure'; Mandatory = @('ExpectedSession', 'OperationEvidenceRecords'); Mode = $false }
        'Get-CddsiVmCalibrationEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'New-CddsiVmCalibrationEvidence' = @{ Kind = 'Pure'; Mandatory = @('ExpectedSession', 'ExpectedSessionAnchorToken', 'ValidationTimeUtc', 'ObservationStartedAtUtc', 'OsImage', 'MsixCandidates', 'Git', 'DesktopBehavior', 'Cleanup'); Mode = $false }
        'Test-CddsiVmCalibrationEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedSession', 'ExpectedSessionAnchorToken', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiCasStoreAuthorityKeyFingerprint' = @{ Kind = 'Pure'; Mandatory = @('StoreAuthorityPublicKey'); Mode = $false }
        'Test-CddsiCasStoreAuthorityPublicKey' = @{ Kind = 'Pure'; Mandatory = @('StoreAuthorityPublicKey'); Mode = $false }
        'Get-CddsiCasCommitReceiptSigningPayload' = @{ Kind = 'Pure'; Mandatory = @('CommitReceipt'); Mode = $false }
        'Get-CddsiCasCommitReceiptBindingToken' = @{ Kind = 'Pure'; Mandatory = @('CommitReceipt'); Mode = $false }
        'Test-CddsiCasCommitReceiptSignature' = @{ Kind = 'Pure'; Mandatory = @('CommitReceipt', 'StoreAuthorityPublicKey'); Mode = $false }
        'Get-CddsiVmCalibrationConsumptionStateKey' = @{ Kind = 'Pure'; Mandatory = @('ConsumptionState'); Mode = $false }
        'Get-CddsiVmCalibrationConsumptionBindingToken' = @{ Kind = 'Pure'; Mandatory = @('ConsumptionState'); Mode = $false }
        'Test-CddsiVmCalibrationConsumptionState' = @{ Kind = 'Pure'; Mandatory = @('ConsumptionState'); Mode = $false }
        'New-CddsiVmCalibrationConsumptionState' = @{ Kind = 'Pure'; Mandatory = @('ExpectedSession', 'ExpectedSessionAnchorToken', 'StoreAuthorityPublicKey', 'StoreInstanceId', 'StoreEpoch', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiVmCalibrationConsumptionProposalBindingToken' = @{ Kind = 'Pure'; Mandatory = @('CommitProposal'); Mode = $false }
        'Test-CddsiVmCalibrationConsumptionCommitProposal' = @{ Kind = 'Pure'; Mandatory = @('CommitProposal'); Mode = $false }
        'Test-CddsiCommittedVmCalibrationConsumptionReceipt' = @{ Kind = 'Pure'; Mandatory = @('ConsumptionState', 'CommitReceipt', 'StoreAuthorityPublicKey', 'ExpectedSessionAnchorToken', 'ExpectedSessionBindingToken', 'ExpectedEvidenceBindingToken', 'ExpectedConsumptionId', 'ExpectedTransactionId', 'ExpectedProposalNonce', 'ValidationTimeUtc'); Mode = $false }
        'Resolve-CddsiVmCalibrationConsumption' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedSession', 'ExpectedSessionAnchorToken', 'ConsumptionState', 'StoreAuthorityPublicKey', 'ConsumptionId', 'TransactionId', 'ProposalNonce', 'CommittedConsumptionReceipt', 'ExpectedRevision', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiReleaseFactsFreezeStateKey' = @{ Kind = 'Pure'; Mandatory = @('FreezeState'); Mode = $false }
        'Get-CddsiReleaseFactsFreezeStateBindingToken' = @{ Kind = 'Pure'; Mandatory = @('FreezeState'); Mode = $false }
        'Test-CddsiReleaseFactsFreezeState' = @{ Kind = 'Pure'; Mandatory = @('FreezeState'); Mode = $false }
        'Get-CddsiReleaseFactsFreezeProposalBindingToken' = @{ Kind = 'Pure'; Mandatory = @('CommitProposal'); Mode = $false }
        'Test-CddsiReleaseFactsFreezeCommitProposal' = @{ Kind = 'Pure'; Mandatory = @('CommitProposal'); Mode = $false }
        'Test-CddsiCommittedReleaseFactsFreezeReceipt' = @{ Kind = 'Pure'; Mandatory = @('FreezeState', 'CommitReceipt', 'StoreAuthorityPublicKey', 'ExpectedSessionAnchorToken', 'ExpectedSessionBindingToken', 'ExpectedEvidenceBindingToken', 'ExpectedConsumptionStateKeySha256', 'ExpectedConsumptionStateBindingToken', 'ExpectedConsumptionCommitReceiptBindingToken', 'ExpectedConsumptionId', 'ExpectedFreezeId', 'ExpectedFactsBindingToken', 'ExpectedTransactionId', 'ExpectedProposalNonce', 'ValidationTimeUtc'); Mode = $false }
        'New-CddsiReleaseFactsFreezeState' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedSession', 'ExpectedSessionAnchorToken', 'CommittedConsumptionState', 'CommittedConsumptionReceipt', 'ConsumptionStoreAuthorityPublicKey', 'ExpectedConsumptionId', 'ExpectedConsumptionTransactionId', 'ExpectedConsumptionProposalNonce', 'FreezeStoreAuthorityPublicKey', 'FreezeStoreInstanceId', 'FreezeStoreEpoch', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiFrozenReleaseFactsBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Facts'); Mode = $false }
        'Resolve-CddsiFrozenReleaseFacts' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedSession', 'ExpectedSessionAnchorToken', 'CommittedConsumptionState', 'CommittedConsumptionReceipt', 'ConsumptionStoreAuthorityPublicKey', 'ExpectedConsumptionId', 'ExpectedConsumptionTransactionId', 'ExpectedConsumptionProposalNonce', 'FreezeState', 'FreezeStoreAuthorityPublicKey', 'FreezeId', 'FreezeTransactionId', 'FreezeProposalNonce', 'CommittedFreezeReceipt', 'ExpectedRevision', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiFrozenReleaseFacts' = @{ Kind = 'Pure'; Mandatory = @('Facts', 'Evidence', 'ExpectedSession', 'ExpectedSessionAnchorToken', 'CommittedConsumptionState', 'CommittedConsumptionReceipt', 'ConsumptionStoreAuthorityPublicKey', 'ExpectedConsumptionId', 'ExpectedConsumptionTransactionId', 'ExpectedConsumptionProposalNonce', 'CommittedFreezeState', 'CommittedFreezeReceipt', 'FreezeStoreAuthorityPublicKey', 'ExpectedFreezeId', 'ExpectedFreezeTransactionId', 'ExpectedFreezeProposalNonce', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiReleaseSha256Value' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiReleaseVersionValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiReleaseCommitIdValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiReleaseTimestampValue' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Test-CddsiReleaseEntryPath' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiReleaseContentDigest' = @{ Kind = 'Pure'; Mandatory = @('Manifest'); Mode = $false }
        'Get-CddsiReleaseContentManifestBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Manifest'); Mode = $false }
        'New-CddsiReleaseContentManifest' = @{ Kind = 'Pure'; Mandatory = @('Stage', 'ArtifactProfile', 'ArtifactVersion', 'CommitId', 'FrozenFactsToken', 'ManifestPath', 'DetachedSidecarName', 'SignatureTrustPolicy', 'Entries'); Mode = $false }
        'Test-CddsiReleaseContentManifest' = @{ Kind = 'Pure'; Mandatory = @('Manifest', 'ExpectedSignatureTrustPolicy'); Mode = $false }
        'Test-CddsiReleaseArchiveObservation' = @{ Kind = 'Pure'; Mandatory = @('Manifest', 'ExpectedSignatureTrustPolicy', 'ArchiveEntryPaths', 'ObservedContentEntries', 'ObservedManifestEntry'); Mode = $false }
        'Get-CddsiReleaseSidecarClaimsBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Payload'); Mode = $false }
        'ConvertTo-CddsiReleaseSidecarClaimsBytes' = @{ Kind = 'Pure'; Mandatory = @('Payload'); Mode = $false }
        'Get-CddsiReleaseSignatureEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('SignatureEvidence'); Mode = $false }
        'Get-CddsiReleaseSidecarPayloadBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Payload'); Mode = $false }
        'New-CddsiReleaseSidecarPayload' = @{ Kind = 'Pure'; Mandatory = @('Manifest', 'ExpectedSignatureTrustPolicy', 'FinalZipSha256', 'SignerIdentity', 'SignatureEvidence', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiReleaseSidecarPayload' = @{ Kind = 'Pure'; Mandatory = @('Payload', 'Manifest', 'ExpectedSignatureTrustPolicy', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiReleaseCandidateSetBindingToken' = @{ Kind = 'Pure'; Mandatory = @('CandidateSet'); Mode = $false }
        'New-CddsiReleaseCandidateSet' = @{ Kind = 'Pure'; Mandatory = @('CandidateManifests', 'CandidateSidecarPayloads', 'ExpectedSignatureTrustPolicies', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiReleaseCandidateSet' = @{ Kind = 'Pure'; Mandatory = @('CandidateSet', 'CandidateManifests', 'CandidateSidecarPayloads', 'ExpectedSignatureTrustPolicies', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiReleasePromotionReceiptBindingToken' = @{ Kind = 'Pure'; Mandatory = @('PromotionReceipt'); Mode = $false }
        'New-CddsiReleasePromotionReceipt' = @{ Kind = 'Pure'; Mandatory = @('CandidateSet', 'CandidateManifests', 'CandidateSidecarPayloads', 'AcceptanceEvidenceToken', 'PromotionId', 'PromotedAtUtc'); Mode = $false }
        'Test-CddsiReleasePromotionReceipt' = @{ Kind = 'Pure'; Mandatory = @('PromotionReceipt', 'CandidateSet', 'CandidateManifests', 'CandidateSidecarPayloads'); Mode = $false }
        'New-CddsiCredentialHelperReleaseContract' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiCredentialHelperBuildDescriptorBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Descriptor'); Mode = $false }
        'Test-CddsiCredentialHelperBuildDescriptor' = @{ Kind = 'Pure'; Mandatory = @('Descriptor', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiCredentialHelperSignatureEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiCredentialHelperSignatureEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedBuildDescriptor', 'ExpectedCandidateId', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiCredentialHelperAclEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiCredentialHelperAclEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedBuildDescriptorBindingToken', 'ExpectedCandidateId', 'ExpectedInstalledExecutablePathToken', 'ExpectedCurrentUserSidToken', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiCredentialHelperInvocationContractBindingToken' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiCredentialHelperCandidateEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiCredentialHelperCandidateEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedBuildDescriptor', 'ExpectedCandidateId', 'ExpectedEvidenceRunId', 'ExpectedChallengeNonce', 'ExpectedInstallRootPath', 'ExpectedInstalledExecutablePath', 'ExpectedCurrentUserSidToken', 'ValidationTimeUtc'); Mode = $false }
        'Get-CddsiCredentialHelperProtectedBlobEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiCredentialHelperProtectedBlobEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedCandidateEvidence', 'ExpectedOperationNonce', 'ExpectedCurrentUserSidToken', 'ValidationTimeUtc'); Mode = $false }
        'Test-CddsiCredentialHelperInvocationOutput' = @{ Kind = 'Pure'; Mandatory = @('OutputKind', 'StandardOutput', 'StandardError', 'HelperContext', 'PromptObserved', 'ArgumentCount', 'ShellInvocation', 'StandardInputRead', 'ExitCode', 'InvocationStatus', 'ElapsedMilliseconds', 'TimeoutSeconds', 'TtlSeconds', 'ExpectedHelperPeSha256', 'ObservedHelperPeSha256', 'ExpectedInstalledExecutablePathToken', 'ObservedInstalledExecutablePathToken'); Mode = $false }
        'Get-CddsiCredentialHelperInvocationEvidenceBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Evidence'); Mode = $false }
        'Test-CddsiCredentialHelperInvocationEvidence' = @{ Kind = 'Pure'; Mandatory = @('Evidence', 'ExpectedCandidateEvidence', 'ExpectedInvocationId', 'ExpectedInvocationChallenge', 'ValidationTimeUtc'); Mode = $false }
        'ConvertTo-CddsiVmTestRelayCanonicalJson' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Get-CddsiVmTestRelayPayloadSha256' = @{ Kind = 'Pure'; Mandatory = @('Payload'); Mode = $false }
        'Get-CddsiVmTestRelayMessageSha256' = @{ Kind = 'Pure'; Mandatory = @('Envelope', 'Payload'); Mode = $false }
        'Get-CddsiVmTestRelayStateBindingToken' = @{ Kind = 'Pure'; Mandatory = @('State'); Mode = $false }
        'Test-CddsiVmTestRelayEnvelope' = @{ Kind = 'Pure'; Mandatory = @('ValidationTimeUtc', 'ExpectedHostToVmRepositoryIdentity', 'ExpectedVmToHostRepositoryIdentity', 'ExpectedProductRepositoryIdentity', 'AuthenticatedSenderRole', 'AuthenticatedOutbox'); Mode = $false }
        'New-CddsiVmTestRelayState' = @{ Kind = 'Pure'; Mandatory = @('HostToVmRepositoryIdentity', 'VmToHostRepositoryIdentity', 'ProductRepositoryIdentity'); Mode = $false }
        'Test-CddsiVmTestRelayState' = @{ Kind = 'Pure'; Mandatory = @(); Mode = $false }
        'Resolve-CddsiVmTestRelayTransition' = @{ Kind = 'Pure'; Mandatory = @('State', 'Envelope', 'Payload', 'ValidationTimeUtc', 'AuthenticatedSenderRole', 'AuthenticatedOutbox'); Mode = $false }
        'Get-CddsiVmResetBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Value'); Mode = $false }
        'Test-CddsiVmResetAllowListEntry' = @{ Kind = 'Pure'; Mandatory = @('Entry'); Mode = $false }
        'Test-CddsiVmResetOwnershipReceipt' = @{ Kind = 'Pure'; Mandatory = @('Receipt', 'AllowListEntry'); Mode = $false }
        'Test-CddsiVmResetPolicy' = @{ Kind = 'Pure'; Mandatory = @('Policy'); Mode = $false }
        'Get-CddsiVmResetBaselineDigest' = @{ Kind = 'Pure'; Mandatory = @('Baseline'); Mode = $false }
        'Test-CddsiVmResetBaseline' = @{ Kind = 'Pure'; Mandatory = @('Baseline', 'Policy'); Mode = $false }
        'New-CddsiVmResetPlan' = @{ Kind = 'Pure'; Mandatory = @('Policy', 'OwnershipReceipts', 'CycleId'); Mode = $false }
        'Test-CddsiVmResetPlan' = @{ Kind = 'Pure'; Mandatory = @('Plan', 'Policy', 'OwnershipReceipts'); Mode = $false }
        'Test-CddsiVmResetActionReceipt' = @{ Kind = 'Pure'; Mandatory = @('Receipt', 'Plan'); Mode = $false }
        'Resolve-CddsiVmResetDisposition' = @{ Kind = 'Pure'; Mandatory = @('Policy', 'Plan', 'OwnershipReceipts', 'ActionReceipts', 'BaselineBefore', 'BaselineAfter', 'FinalState'); Mode = $false }
        'New-CddsiVmCleanReadyReceipt' = @{ Kind = 'Pure'; Mandatory = @('Policy', 'Plan', 'OwnershipReceipts', 'ActionReceipts', 'BaselineBefore', 'BaselineAfter', 'FinalState', 'StartedAtUtc', 'CompletedAtUtc', 'ControlIdentity', 'AuthenticationDigest', 'ExecutionMode'); Mode = $false }
        'Test-CddsiVmCleanReadyReceipt' = @{ Kind = 'Pure'; Mandatory = @('Receipt', 'Policy', 'Plan', 'OwnershipReceipts', 'ActionReceipts', 'BaselineBefore', 'BaselineAfter', 'FinalState'); Mode = $false }
        'Invoke-CddsiVmGuestReset' = @{ Kind = 'ContextBound'; Mandatory = @('Context', 'Policy', 'OwnershipReceipts', 'CycleId', 'StartedAtUtc', 'CompletedAtUtc', 'ControlIdentity', 'AuthenticationDigest'); Mode = $true }
        'Test-CddsiFastLaneRepositoryObservation' = @{ Kind = 'Pure'; Mandatory = @('Observation', 'Expected'); Mode = $false }
        'Test-CddsiFastLaneCredentialObservation' = @{ Kind = 'Pure'; Mandatory = @('Observation', 'Role'); Mode = $false }
        'Test-CddsiFastLaneAutomationObservation' = @{ Kind = 'Pure'; Mandatory = @('Observation', 'Role', 'ExpectedAutomationId', 'ExpectedIntervalMinutes'); Mode = $false }
        'Test-CddsiFastLaneDeploymentObservation' = @{ Kind = 'Pure'; Mandatory = @('Observation', 'Policy'); Mode = $false }
        'Get-CddsiFastLaneDeploymentObservationBindingToken' = @{ Kind = 'Pure'; Mandatory = @('Observation'); Mode = $false }
        'Resolve-CddsiFastLaneReadiness' = @{ Kind = 'Pure'; Mandatory = @('Observation', 'Policy', 'ValidationTimeUtc', 'ExpectedPolicySha256'); Mode = $false }
    }
}
