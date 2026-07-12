BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'desktop config contract' {
    It 'pins models, disables discovery and enables Chat Code Cowork' {
        $config = New-CddsiClaudeDesktopDesiredConfig
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeTrue
        $config.modelDiscovery.enabled | Should -BeFalse
        @($config.models) | Should -Be @('deepseek-chat', 'deepseek-reasoner')
        $config.capabilities.chat | Should -BeTrue
        $config.capabilities.code | Should -BeTrue
        $config.capabilities.cowork | Should -BeTrue
        $config.credential.value | Should -BeNullOrEmpty
    }

    It 'rejects model overrides and malformed credential contracts' {
        { New-CddsiClaudeDesktopDesiredConfig -Models @('other-model') } | Should -Throw
        $config = New-CddsiClaudeDesktopDesiredConfig
        $config.models = @('other-model')
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeFalse
        $config = New-CddsiClaudeDesktopDesiredConfig
        $config.credential.value = 'not-a-secret-looking-value'
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeFalse
        $config = New-CddsiClaudeDesktopDesiredConfig
        $config.modelDiscovery.enabled = 'false'
        $config.capabilities.chat = 'true'
        $config.credential.persistInState = 'false'
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeFalse
        $config = New-CddsiClaudeDesktopDesiredConfig
        $config.models = "deepseek-chat`ndeepseek-reasoner"
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeFalse
        (Test-CddsiClaudeDesktopConfigContract -Config ([pscustomobject]@{ provider = 'DeepSeek' })) | Should -BeFalse
    }

    It 'allows only the exact configLibrary directory' {
        $local = Join-Path $TestDrive 'LocalAppData'
        $expected = Join-Path $local 'Claude-3p\configLibrary'
        (Test-CddsiConfigLibraryTarget -TargetPath $expected -LocalAppDataPath $local) | Should -BeTrue
        (Test-CddsiConfigLibraryTarget -TargetPath (Join-Path $TestDrive '.claude\settings.json') -LocalAppDataPath $local) | Should -BeFalse
        (Test-CddsiConfigLibraryTarget -TargetPath $expected -LocalAppDataPath $local -Mode Live) | Should -BeFalse
    }

    It 'plans an atomic write but creates no files' {
        $local = Join-Path $TestDrive 'LocalAppData'
        $target = Join-Path $local 'Claude-3p\configLibrary'
        $result = Write-CddsiClaudeDesktopConfigAtomic -DesiredConfig (New-CddsiClaudeDesktopDesiredConfig) -TargetPath $target -LocalAppDataPath $local -Mode TestSafe
        $result.Status | Should -Be 'planned'
        (Test-Path -LiteralPath $target) | Should -BeFalse
    }

    It 'rejects non-configLibrary targets for read backup snapshot write and restore contracts' {
        $local = Join-Path $TestDrive 'LocalAppData'
        $forbidden = Join-Path $TestDrive '.claude\settings.json'
        { Read-CddsiClaudeDesktopConfigLibrary -TargetPath $forbidden -LocalAppDataPath $local } | Should -Throw
        { New-CddsiConfigRestorableBackup -TargetPath $forbidden -LocalAppDataPath $local -Mode TestSafe } | Should -Throw
        { New-CddsiConfigRedactedSnapshot -TargetPath $forbidden -LocalAppDataPath $local -Mode TestSafe } | Should -Throw
        { Write-CddsiClaudeDesktopConfigAtomic -DesiredConfig (New-CddsiClaudeDesktopDesiredConfig) -TargetPath $forbidden -LocalAppDataPath $local -Mode TestSafe } | Should -Throw
        { Restore-CddsiClaudeDesktopConfig -BackupId 'fixture' -TargetPath $forbidden -LocalAppDataPath $local -Mode TestSafe } | Should -Throw
    }

    It 'does not resolve or read Claude Code settings in its integrity contract' {
        $contract = Get-CddsiClaudeCodeSettingsIntegrityContract
        $contract.policy | Should -Be 'do_not_read_or_modify'
        $contract.contentParsingAllowed | Should -BeFalse
        $contract.hashOnlyProviderAllowed | Should -BeNullOrEmpty
    }
}
