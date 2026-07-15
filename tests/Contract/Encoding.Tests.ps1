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
}
