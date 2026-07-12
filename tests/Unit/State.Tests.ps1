BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'resume state schema' {
    It 'creates a versioned state without credential fields' {
        $state = New-CddsiState -RunId '00000000-0000-0000-0000-000000000001'
        (Test-CddsiStateSchema -State $state) | Should -BeTrue
        $json = $state | ConvertTo-Json -Depth 30
        $json | Should -Not -Match '(?i)"apiKey"\s*:'
        $json | Should -Not -Match '(?i)"authorization"\s*:'
        $state.schemaVersion | Should -Be 1
    }

    It 'models restart and resume without authorizing automatic restart' {
        $state = New-CddsiState
        $pending = Set-CddsiResumeCheckpoint -State $state -ReasonCode 'vmp_change' -ResumePhase 'verify_cowork'
        $pending.restart.required | Should -BeTrue
        $pending.restart.resumePhase | Should -Be 'verify_cowork'
        $cleared = Clear-CddsiResumeCheckpoint -State $pending
        $cleared.restart.required | Should -BeFalse
        $cleared.pendingAction | Should -BeNullOrEmpty
    }

    It 'does not write a state file in TestSafe' {
        $local = Join-Path $TestDrive 'LocalAppData'
        $path = Join-Path $local 'ClaudeDesktopDeepSeekInstaller\state.json'
        $result = Write-CddsiStateAtomic -State (New-CddsiState) -Path $path -LocalAppDataPath $local -Mode TestSafe
        $result.Status | Should -Be 'planned'
        (Test-Path -LiteralPath $path) | Should -BeFalse
    }

    It 'rejects state containing key material' {
        $state = New-CddsiState
        $state.lastError = [pscustomobject]@{ code = 'synthetic'; messageSafe = ('sk-' + ('D' * 24)) }
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
    }

    It 'rejects arbitrary state read and write targets' {
        $local = Join-Path $TestDrive 'LocalAppData'
        $forbidden = Join-Path $TestDrive '.claude\settings.json'
        { Read-CddsiState -Path $forbidden -LocalAppDataPath $local -Mode TestSafe } | Should -Throw
        { Write-CddsiStateAtomic -State (New-CddsiState) -Path $forbidden -LocalAppDataPath $local -Mode DryRun } | Should -Throw
        (Test-CddsiStateTarget -Path (Join-Path $local 'ClaudeDesktopDeepSeekInstaller\state.json') -LocalAppDataPath $local -Mode TestSafe) | Should -BeTrue
    }

    It 'rejects extra fields that could carry raw config' {
        $state = New-CddsiState
        $state | Add-Member -NotePropertyName rawConfig -NotePropertyValue '{ }'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
    }

    It 'rejects string booleans invalid run ids and malformed timestamps' {
        $state = New-CddsiState
        $state.restart.required = 'false'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
        $state = New-CddsiState
        $state.runId = 'not-a-guid'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
        $state = New-CddsiState
        $state.updatedAtUtc = 'not-a-time'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
        $state = New-CddsiState
        $state.completedSteps = @('download_msix', 'download_msix')
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
        $state = New-CddsiState
        $state.completedSteps = @([pscustomobject]@{ rawConfig = '{ }' })
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
        $state = New-CddsiState
        $state.config.backupId = '{"rawConfig":{}}'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
        $state = New-CddsiState
        $state.updatedAtUtc = '2000-01-01T00:00:00.0000000Z'
        (Test-CddsiStateSchema -State $state) | Should -BeFalse
    }
}
