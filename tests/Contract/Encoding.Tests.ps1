BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
}

Describe 'entrypoint encoding contracts' {
    It 'keeps every cmd file ASCII and BOM-free' {
        $cmdFiles = @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.cmd' -File)
        $cmdFiles.Count | Should -BeGreaterThan 0
        foreach ($file in $cmdFiles) {
            $bytes = [System.IO.File]::ReadAllBytes($file.FullName)
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
            (($bytes.Count -ge 3) -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        }
    }

    It 'does not change the console code page from cmd wrappers' {
        $content = @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.cmd' -File | ForEach-Object { [System.IO.File]::ReadAllText($_.FullName) }) -join "`n"
        $content | Should -Not -Match '(?i)\bchcp\b'
        $content | Should -Not -Match '(?i)-ExecutionPolicy\s+Bypass'
        $content | Should -Not -Match '(?i)-EncodedCommand'
    }

    It 'freezes all six cmd wrappers to synchronous exit-code forwarding' {
        $cmdFiles = @(Get-ChildItem -LiteralPath $script:RepoRoot -Filter '*.cmd' -File)
        $cmdNames = [string[]]@($cmdFiles.Name)
        [Array]::Sort($cmdNames, [StringComparer]::Ordinal)
        $cmdNames | Should -Be @(
            'Restore-Config.cmd', 'Run-Diagnostics.cmd', 'Start-Install.cmd',
            '一键诊断.cmd', '开始安装.cmd', '恢复配置.cmd'
        )
        foreach ($leaf in @('Restore-Config.cmd', 'Run-Diagnostics.cmd', 'Start-Install.cmd')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $leaf))
            $text | Should -Match '(?m)^set "RC=%errorlevel%"\r?$'
            $text | Should -Match '(?m)^endlocal & exit /b %RC%\r?$'
            $text | Should -Not -Match '(?im)^\s*start(?:\s|$)'
        }
        $aliases = [ordered]@{
            '一键诊断.cmd' = 'Run-Diagnostics.cmd'
            '恢复配置.cmd' = 'Restore-Config.cmd'
            '开始安装.cmd' = 'Start-Install.cmd'
        }
        foreach ($entry in $aliases.GetEnumerator()) {
            $text = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $entry.Key))
            $text | Should -Match ('(?m)^call "%~dp0' + [regex]::Escape($entry.Value) + '" %\*\r?$')
            $text | Should -Match '(?m)^exit /b %errorlevel%\r?$'
        }

        $entryText = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'Start-Here.ps1'))
        $entryText | Should -Match "Write-Host 'Status=FAILED'"
        $entryText | Should -Match "Write-Host 'ErrorCode=UNHANDLED_SAFE_FAILURE'"
        $entryText | Should -Match 'exit \(Get-CddsiOperationExitCode -Status \$result\.Status\)'
    }

    It 'establishes one UTF-8 producer contract before quality-worker output' {
        $loggerPath = Join-Path $script:RepoRoot 'lib\logger.ps1'
        $workerPath = Join-Path $script:RepoRoot 'scripts\check-worker.ps1'
        $runnerPath = Join-Path $script:RepoRoot 'scripts\invoke-host-sandbox.ps1'
        $loggerText = [System.IO.File]::ReadAllText($loggerPath)
        $workerText = [System.IO.File]::ReadAllText($workerPath)
        $runnerText = [System.IO.File]::ReadAllText($runnerPath)
        $checkText = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'scripts\check.ps1'))

        @([regex]::Matches(
            ($loggerText + $workerText + $runnerText),
            '\[Console\]::OutputEncoding\s*='
        )).Count | Should -Be 1
        $loggerText | Should -Match '\$global:OutputEncoding\s*='
        $loggerText | Should -Not -Match '(?i)\bchcp\b'
        $workerReturn = $workerText.IndexOf('if ($EvidenceBuilderOnly) { return }', [StringComparison]::Ordinal)
        $workerEncoding = $workerText.IndexOf('Initialize-CddsiConsoleEncoding | Out-Null', [StringComparison]::Ordinal)
        $workerFirstStep = $workerText.IndexOf("Invoke-CheckStep -Name 'Execution files", [StringComparison]::Ordinal)
        $workerEncoding | Should -BeGreaterThan $workerReturn
        $workerFirstStep | Should -BeGreaterThan $workerEncoding
        $runnerText | Should -Match 'UTF8Encoding\(\$false,\s*\$true\)'
        $workerText | Should -Match 'CDDSI_UTF8_ROUNDTRIP=质量检查 😀 𠮷'
        $runnerText | Should -Match 'CDDSI_UTF8_ROUNDTRIP=质量检查 😀 𠮷'
        $runnerText | Should -Match '\$workerProcessResult\.StdOut\.Contains\(\$utf8RoundTripMarker\)'
        $runnerText | Should -Match '\$workerProcessResult\.StdErr\.Contains\(\$utf8RoundTripMarker\)'
        $checkText | Should -Match 'Initialize-CddsiConsoleEncoding \| Out-Null'
        $checkText | Should -Match 'CDDSI_SAFE_FAILURE_EVIDENCE_V2='
    }
}
