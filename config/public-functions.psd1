@{
    SchemaVersion = 1

    Files = @{
        'lib/bootstrap.ps1' = @(
            'Get-CddsiProjectRoot', 'Import-CddsiLibraries', 'Initialize-CddsiScript'
        )
        'lib/logger.ps1' = @(
            'Initialize-CddsiConsoleEncoding', 'Protect-CddsiLogMessage', 'Initialize-CddsiLogger',
            'Write-CddsiLog', 'Get-CddsiLogPath'
        )
        'lib/common.ps1' = @(
            'Get-CddsiProjectStage', 'New-CddsiOperationResult', 'Resolve-CddsiExecutionMode',
            'Test-CddsiRealMutationAllowed', 'Assert-CddsiMutationAllowed', 'Get-CddsiConfigLibraryPath',
            'Protect-CddsiSecret', 'Protect-CddsiReportText', 'Find-CddsiPotentialSecrets',
            'Test-CddsiDeepSeekApiKeyFormat', 'Test-CddsiSignatureEvidence', 'Test-CddsiSchemaVersionOne',
            'Test-CddsiUtcTimestampValue', 'Get-CddsiPathBindingToken', 'Test-CddsiArtifactHashBinding',
            'Test-CddsiSafeIdentifierValue', 'Read-CddsiJsonFile', 'ConvertTo-CddsiJson', 'Test-CddsiExactPropertySet',
            'Get-CddsiSignatureEvidencePayload'
        )
        'lib/state.ps1' = @(
            'Get-CddsiStatePath', 'New-CddsiState', 'Test-CddsiStateSchema', 'Test-CddsiStateTarget',
            'Read-CddsiState', 'Write-CddsiStateAtomic', 'Set-CddsiResumeCheckpoint',
            'Clear-CddsiResumeCheckpoint'
        )
        'lib/desktop-env-check.ps1' = @(
            'Get-CddsiClaudeDesktopStatus', 'Test-CddsiVirtualMachinePlatform',
            'Test-CddsiHardwareVirtualization', 'Get-CddsiDesktopEnvironmentSnapshot'
        )
        'lib/desktop-msix.ps1' = @(
            'Get-CddsiClaudeDesktopMsixStatus', 'Get-CddsiOfficialMsixMetadata',
            'Save-CddsiOfficialClaudeDesktopMsix', 'Test-CddsiClaudeDesktopMsixSignature',
            'Install-CddsiClaudeDesktopMsix', 'Update-CddsiClaudeDesktopMsix'
        )
        'lib/git-for-windows.ps1' = @(
            'Get-CddsiGitForWindowsStatus', 'Get-CddsiOfficialGitInstallerMetadata',
            'Test-CddsiGitInstallerSignature', 'Save-CddsiOfficialGitInstaller',
            'Install-CddsiGitForWindows'
        )
        'lib/cowork-readiness.ps1' = @(
            'Get-CddsiCoworkReadiness', 'Get-CddsiCoworkBlockingReasons', 'New-CddsiCoworkResumePlan',
            'Test-CddsiCoworkServiceStatus', 'Enable-CddsiVirtualMachinePlatform'
        )
        'lib/deepseek-api.ps1' = @(
            'Read-CddsiDeepSeekApiKeySecure', 'ConvertTo-CddsiDeepSeekApiErrorClass',
            'Invoke-CddsiDeepSeekApiValidation'
        )
        'lib/desktop-config.ps1' = @(
            'Get-CddsiClaudeDesktopConfigLibraryPath', 'Test-CddsiConfigLibraryTarget',
            'Read-CddsiClaudeDesktopConfigLibrary', 'New-CddsiClaudeDesktopDesiredConfig',
            'Test-CddsiClaudeDesktopConfigContract', 'Compare-CddsiClaudeDesktopConfig',
            'New-CddsiConfigRestorableBackup', 'New-CddsiConfigRedactedSnapshot',
            'Write-CddsiClaudeDesktopConfigAtomic', 'Restore-CddsiClaudeDesktopConfig'
        )
        'lib/desktop-lifecycle.ps1' = @(
            'Get-CddsiClaudeDesktopProcessState', 'Stop-CddsiClaudeDesktop',
            'Start-CddsiClaudeDesktop', 'Restart-CddsiClaudeDesktop'
        )
        'lib/desktop-acceptance.ps1' = @(
            'Get-CddsiAcceptancePlan', 'Get-CddsiClaudeCodeSettingsIntegrityContract',
            'Get-CddsiClaudeCodeSettingsFingerprint', 'Test-CddsiClaudeCodeSettingsUnchanged',
            'Test-CddsiApiKeyLeak', 'Test-CddsiChatAcceptance', 'Test-CddsiCodeAcceptance',
            'Test-CddsiCoworkAcceptance', 'Get-CddsiRepairPlan', 'Invoke-CddsiDesktopRepair',
            'Invoke-CddsiDesktopAcceptance', 'New-CddsiAcceptanceReport'
        )
    }

    ParameterContracts = @{
        'Initialize-CddsiLogger' = @{ Mandatory = @(); Mode = $true }
        'Initialize-CddsiScript' = @{ Mandatory = @(); Mode = $true }
        'Read-CddsiState' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Write-CddsiStateAtomic' = @{ Mandatory = @('State'); Mode = $true; AcknowledgeRealChanges = $true }
        'Set-CddsiResumeCheckpoint' = @{ Mandatory = @('State', 'ReasonCode', 'ResumePhase') }
        'Save-CddsiOfficialClaudeDesktopMsix' = @{ Mandatory = @('DestinationPath'); Mode = $true; AcknowledgeRealChanges = $true }
        'Test-CddsiClaudeDesktopMsixSignature' = @{ Mandatory = @('PackagePath') }
        'Install-CddsiClaudeDesktopMsix' = @{ Mandatory = @('PackagePath', 'SignatureEvidence'); Mode = $true; AcknowledgeRealChanges = $true }
        'Update-CddsiClaudeDesktopMsix' = @{ Mandatory = @('PackagePath', 'SignatureEvidence'); Mode = $true; AcknowledgeRealChanges = $true }
        'Save-CddsiOfficialGitInstaller' = @{ Mandatory = @('DestinationPath'); Mode = $true; AcknowledgeRealChanges = $true }
        'Test-CddsiGitInstallerSignature' = @{ Mandatory = @('InstallerPath') }
        'Install-CddsiGitForWindows' = @{ Mandatory = @('InstallerPath', 'SignatureEvidence'); Mode = $true; AcknowledgeRealChanges = $true }
        'Enable-CddsiVirtualMachinePlatform' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true; AcknowledgeRestart = $true }
        'Invoke-CddsiDeepSeekApiValidation' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Read-CddsiClaudeDesktopConfigLibrary' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'New-CddsiConfigRestorableBackup' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'New-CddsiConfigRedactedSnapshot' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Write-CddsiClaudeDesktopConfigAtomic' = @{ Mandatory = @('DesiredConfig'); Mode = $true; AcknowledgeRealChanges = $true }
        'Restore-CddsiClaudeDesktopConfig' = @{ Mandatory = @('BackupId'); Mode = $true; AcknowledgeRealChanges = $true }
        'Stop-CddsiClaudeDesktop' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Start-CddsiClaudeDesktop' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Restart-CddsiClaudeDesktop' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Invoke-CddsiDesktopRepair' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
        'Invoke-CddsiDesktopAcceptance' = @{ Mandatory = @(); Mode = $true; AcknowledgeRealChanges = $true }
    }
}
