BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    $script:Manifest = Import-PowerShellDataFile -LiteralPath (
        Join-Path $script:ProjectRoot 'scripts\release-manifest.psd1'
    )
}

Describe 'small release inventory' {
    It 'classifies every present tracked or untracked source file exactly once' {
        $package = @($script:Manifest.PackageFiles)
        $development = @($script:Manifest.DevelopmentOnlyFiles)
        @($package | Where-Object { $_ -in $development }).Count | Should -Be 0
        $listed = @($package + $development | Sort-Object -Unique)
        $actual = @(
            git -C $script:ProjectRoot -c core.quotePath=false ls-files `
                --cached --others --exclude-standard |
                ForEach-Object { $_.Replace('\', '/') } |
                Where-Object {
                    Test-Path -LiteralPath (Join-Path $script:ProjectRoot $_)
                } |
                Sort-Object -Unique
        )
        $LASTEXITCODE | Should -Be 0
        ($actual -join "`n") | Should -BeExactly ($listed -join "`n")
    }

    It 'packages only the 22 practical runtime and user files' {
        @($script:Manifest.PackageFiles).Count | Should -Be 22
        foreach ($required in @(
            'Start-Install.cmd'
            'Start-Here.ps1'
            'lib/installer.ps1'
            'lib/configuration.ps1'
            'helper/CddsiCredentialHelper.cs'
            'config/deepseek-desktop.defaults.json'
        )) {
            $script:Manifest.PackageFiles | Should -Contain $required
        }
        ($script:Manifest.PackageFiles -join "`n") |
            Should -Not -Match '(?m)^(tests|scripts|docs|operator|\.dev)/'
    }

    It 'has removed every retired runtime, relay and snapshot authorization path' {
        foreach ($relative in @(
            'lib/d027-snapshot-authorization.ps1'
            'lib/vm-test-relay.ps1'
            'lib/fake-providers.ps1'
            'scripts/product-release-gate.ps1'
            'config/d027-snapshot-authority.psd1'
        )) {
            Test-Path -LiteralPath (Join-Path $script:ProjectRoot $relative) |
                Should -BeFalse
        }
        @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'operator') `
            -File -Recurse -ErrorAction SilentlyContinue).Count | Should -Be 0
    }

    It 'keeps the runtime below 2500 PowerShell lines' {
        $runtime = @(
            'Start-Here.ps1'
            'lib/bootstrap.ps1'
            'lib/common.ps1'
            'lib/installer.ps1'
            'lib/configuration.ps1'
            'lib/workflow.ps1'
        )
        $lines = 0
        foreach ($relative in $runtime) {
            $lines += @([IO.File]::ReadAllLines(
                (Join-Path $script:ProjectRoot $relative)
            )).Count
        }
        $lines | Should -BeLessThan 2500
    }

    It 'uses exactly two focused Pester files' {
        $tests = @(Get-ChildItem -LiteralPath (Join-Path $script:ProjectRoot 'tests') `
            -Filter '*.Tests.ps1' -File -Recurse)
        $tests.Count | Should -Be 2
    }
}

Describe 'encoding and launchers' {
    It 'keeps every cmd ASCII-only with CRLF and a final newline' {
        $commands = @($script:Manifest.PackageFiles | Where-Object {
            [IO.Path]::GetExtension($_) -ceq '.cmd'
        })
        foreach ($relative in $commands) {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $script:ProjectRoot $relative))
            @($bytes | Where-Object { $_ -gt 127 }).Count | Should -Be 0
            $text = [Text.Encoding]::ASCII.GetString($bytes)
            $text.EndsWith("`r`n") | Should -BeTrue
            ($text -replace "`r`n", '') | Should -Not -Match "`n"
        }
    }

    It 'routes English launchers to Live and Chinese launchers to those wrappers' {
        [IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'Start-Install.cmd')) |
            Should -Match '-Action Install -Live'
        [IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'Run-Diagnostics.cmd')) |
            Should -Match '-Action Diagnose -Live'
        [IO.File]::ReadAllText((Join-Path $script:ProjectRoot 'Restore-Config.cmd')) |
            Should -Match '-Action Restore -Live'
        [IO.File]::ReadAllText((Join-Path $script:ProjectRoot '开始安装.cmd')) |
            Should -Match 'Start-Install\.cmd'
        [IO.File]::ReadAllText((Join-Path $script:ProjectRoot '一键诊断.cmd')) |
            Should -Match 'Run-Diagnostics\.cmd'
        [IO.File]::ReadAllText((Join-Path $script:ProjectRoot '恢复配置.cmd')) |
            Should -Match 'Restore-Config\.cmd'
    }

    It 'keeps authored PowerShell files UTF-8 BOM plus CRLF' {
        $files = @(
            'Start-Here.ps1'
            'lib/bootstrap.ps1'
            'lib/common.ps1'
            'lib/installer.ps1'
            'lib/configuration.ps1'
            'lib/workflow.ps1'
            'scripts/bootstrap-dev.ps1'
            'scripts/build-release.ps1'
            'scripts/check.ps1'
            'scripts/release-manifest.psd1'
            'config/dev-dependencies.psd1'
            'config/public-functions.psd1'
            'tests/Practical.Tests.ps1'
            'tests/Release.Tests.ps1'
        )
        foreach ($relative in $files) {
            $bytes = [IO.File]::ReadAllBytes((Join-Path $script:ProjectRoot $relative))
            $bytes[0] | Should -Be 0xEF
            $bytes[1] | Should -Be 0xBB
            $bytes[2] | Should -Be 0xBF
            $text = [Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Length - 3)
            $text.EndsWith("`r`n") | Should -BeTrue
            ($text -replace "`r`n", '') | Should -Not -Match "`n"
            $text | Should -Not -Match '(?m)[ \t]+$'
        }
    }
}

Describe 'focused quality gate' {
    It 'validates the release without writing an archive' {
        $result = & (Join-Path $script:ProjectRoot 'scripts\build-release.ps1') -DryRun
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.DryRun | Should -BeTrue
        $result.PackageFileCount | Should -Be 22
    }

    It 'builds a real ZIP with the exact inventory and matching SHA-256' {
        $output = Join-Path $TestDrive 'release output'
        $result = & (Join-Path $script:ProjectRoot 'scripts\build-release.ps1') `
            -OutputDirectory $output
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.DryRun | Should -BeFalse
        $result.PackageFileCount | Should -Be 22
        Test-Path -LiteralPath $result.ArchivePath -PathType Leaf |
            Should -BeTrue

        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $zip = [IO.Compression.ZipFile]::OpenRead($result.ArchivePath)
        try {
            $actual = @($zip.Entries |
                Where-Object { -not $_.FullName.EndsWith('/') } |
                ForEach-Object { $_.FullName.Replace('\', '/') } |
                Sort-Object)
        }
        finally {
            $zip.Dispose()
        }
        $expected = @($script:Manifest.PackageFiles |
            ForEach-Object { $_.Replace('\', '/') } |
            Sort-Object)
        ($actual -join "`n") | Should -BeExactly ($expected -join "`n")
        foreach ($launcher in @('开始安装.cmd', '一键诊断.cmd', '恢复配置.cmd')) {
            $actual | Should -Contain $launcher
        }

        $actualHash = (Get-FileHash -LiteralPath $result.ArchivePath `
            -Algorithm SHA256).Hash.ToLowerInvariant()
        $actualHash | Should -BeExactly $result.ArchiveSha256
        $hashPath = '{0}.sha256' -f $result.ArchivePath
        Test-Path -LiteralPath $hashPath -PathType Leaf | Should -BeTrue
        $expectedHashFile = '{0}  {1}{2}' -f
            $actualHash,
            (Split-Path -Leaf $result.ArchivePath),
            "`n"
        [IO.File]::ReadAllText($hashPath) |
            Should -BeExactly $expectedHashFile
    }

    It 'contains no test skip or retired gate invocation' {
        $check = [IO.File]::ReadAllText(
            (Join-Path $script:ProjectRoot 'scripts\check.ps1')
        )
        $check | Should -Not -Match 'worker|shard|historical|ProductReleaseGate|PS7'
        $check | Should -Match 'Invoke-Pester'
        $check | Should -Match 'build-release\.ps1'
        $check | Should -Match 'git -C \$projectRoot diff --check'
    }
}
