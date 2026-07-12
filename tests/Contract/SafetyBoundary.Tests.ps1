BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'scaffold safety boundary' {
    It 'keeps MSIX, Git, Windows feature and process actions planned only' {
        (Save-CddsiOfficialClaudeDesktopMsix -DestinationPath (Join-Path $TestDrive 'Claude.msix') -Mode TestSafe).Changed | Should -BeFalse
        $gitPath = Join-Path $TestDrive 'git.exe'
        $gitEvidence = [pscustomobject]@{
            SchemaVersion = 1
            ArtifactType = 'GitForWindowsInstaller'
            PathBindingToken = Get-CddsiPathBindingToken -Path $gitPath
            ArtifactSha256 = ('b' * 64)
            Valid = $true
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            PublisherMatch = $true
            IdentityMatch = $true
            SourcePolicy = 'git_for_windows_official_only'
        }
        (Install-CddsiGitForWindows -InstallerPath $gitPath -SignatureEvidence $gitEvidence -Mode DryRun).Changed | Should -BeFalse
        (Enable-CddsiVirtualMachinePlatform -Mode TestSafe).Changed | Should -BeFalse
        (Stop-CddsiClaudeDesktop -Mode DryRun).Changed | Should -BeFalse
        (Start-CddsiClaudeDesktop -Mode TestSafe).Changed | Should -BeFalse
    }

    It 'rejects every attempted Live action even with acknowledgement' {
        { Save-CddsiOfficialClaudeDesktopMsix -DestinationPath 'unused.msix' -Mode Live -AcknowledgeRealChanges } | Should -Throw
        { Enable-CddsiVirtualMachinePlatform -Mode Live -AcknowledgeRealChanges -AcknowledgeRestart } | Should -Throw
        { Stop-CddsiClaudeDesktop -Mode Live -AcknowledgeRealChanges } | Should -Throw
        { Invoke-CddsiDeepSeekApiValidation -Mode Live -AcknowledgeRealChanges } | Should -Throw
    }

    It 'requires positive signature evidence before MSIX or Git installation plans' {
        { Install-CddsiClaudeDesktopMsix -PackagePath 'unused.msix' -SignatureEvidence ([pscustomobject]@{ Valid = $false }) -Mode TestSafe } | Should -Throw
        { Update-CddsiClaudeDesktopMsix -PackagePath 'unused.msix' -SignatureEvidence ([pscustomobject]@{ Valid = $false }) -Mode DryRun } | Should -Throw
        { Install-CddsiGitForWindows -InstallerPath 'unused.exe' -SignatureEvidence ([pscustomobject]@{ Valid = $false }) -Mode TestSafe } | Should -Throw
        $msixPath = Join-Path $TestDrive 'approved.msix'
        $approved = [pscustomobject]@{
            SchemaVersion = 1
            ArtifactType = 'ClaudeDesktopMsix'
            PathBindingToken = Get-CddsiPathBindingToken -Path $msixPath
            ArtifactSha256 = ('c' * 64)
            Valid = $true
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            PublisherMatch = $true
            IdentityMatch = $true
            SourcePolicy = 'anthropic_official_only'
        }
        (Install-CddsiClaudeDesktopMsix -PackagePath $msixPath -SignatureEvidence $approved -Mode TestSafe).Changed | Should -BeFalse
        { Install-CddsiClaudeDesktopMsix -PackagePath (Join-Path $TestDrive 'different.msix') -SignatureEvidence $approved -Mode TestSafe } | Should -Throw
    }

    It 'runs each root entrypoint in scaffold TestSafe without touching TestDrive' {
        $before = @(Get-ChildItem -LiteralPath $TestDrive -Force -Recurse).Count
        $install = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Install -TestSafe -NonInteractive -PassThru
        $diagnose = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Diagnose -DryRun -NonInteractive -PassThru
        $restore = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Restore -TestSafe -NonInteractive -PassThru
        $repair = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Repair -DryRun -NonInteractive -PassThru
        $install.Status | Should -Be 'scaffold_only'
        $diagnose.Status | Should -Be 'scaffold_only'
        $restore.Status | Should -Be 'scaffold_only'
        $repair.Status | Should -Be 'scaffold_only'
        @(Get-ChildItem -LiteralPath $TestDrive -Force -Recurse).Count | Should -Be $before
    }

    It 'keeps repair orchestration plan-only and blocks Live repair' {
        $result = Invoke-CddsiDesktopRepair -Mode TestSafe
        $result.Status | Should -Be 'not_implemented'
        @($result.Data).Count | Should -BeGreaterThan 0
        { Invoke-CddsiDesktopRepair -Mode Live -AcknowledgeRealChanges } | Should -Throw
    }

    It 'keeps the future elevated boundary mandatory and fail-closed' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\elevated-install.ps1'
        $command = Get-Command -Name $scriptPath -ErrorAction Stop
        @($command.Parameters.Operation.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -BeGreaterThan 0
        $safe = & $scriptPath -Operation ClaudeDesktopMsix -Mode TestSafe -PassThru
        $safe.Status | Should -Be 'planned'
        foreach ($operation in @('ClaudeDesktopMsix', 'GitForWindows', 'VirtualMachinePlatform')) {
            { & $scriptPath -Operation $operation -Mode Live -AcknowledgeRealChanges -AcknowledgeRestart -PassThru } | Should -Throw
        }
    }
}
