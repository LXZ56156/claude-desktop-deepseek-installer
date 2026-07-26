BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:WinTrustFunctionSource = (
        Get-Command Get-CddsiD027GitWinVerifyTrustResult -CommandType Function -ErrorAction Stop
    ).Definition
    $script:GitLibrarySource = [System.IO.File]::ReadAllText(
        (Join-Path $script:RepoRoot 'lib\git-for-windows.ps1')
    )
}

Describe 'D-027 Git WinVerifyTrust policy' {
    BeforeEach {
        $script:WinTrustContext = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = $TestDrive }
        }
        Mock Assert-CddsiD027GitLiveContext { return $true }
    }

    It 'fixes the native policy to no UI, no revocation network and closed state' {
        $script:WinTrustFunctionSource | Should -Match 'WTD_UI_NONE'
        $script:WinTrustFunctionSource | Should -Match 'WTD_REVOKE_NONE'
        $script:WinTrustFunctionSource | Should -Match 'WTD_CACHE_ONLY_URL_RETRIEVAL'
        $script:WinTrustFunctionSource | Should -Match 'WTD_STATEACTION_VERIFY'
        $script:WinTrustFunctionSource | Should -Match 'WTD_STATEACTION_CLOSE'
        $script:WinTrustFunctionSource | Should -Match 'InvalidWindowHandle'
        $script:WinTrustFunctionSource | Should -Match 'FileShare\.Read'
        $script:WinTrustFunctionSource | Should -Not -Match 'Process\.Start|Start-Process|UseShellExecute'
    }

    It 'fails closed with an exact path-free result for invalid input' {
        $result = Get-CddsiD027GitWinVerifyTrustResult `
            -ExecutionContext $script:WinTrustContext `
            -FilePath '.\relative.exe'

        (@($result.PSObject.Properties.Name) -join ',') |
            Should -BeExactly 'SchemaVersion,Trusted,Status,NativeStatusHex,RevocationMode'
        $result.SchemaVersion | Should -Be 1
        $result.Trusted | Should -BeFalse
        $result.Status | Should -BeExactly 'InvalidInput'
        $result.NativeStatusHex | Should -BeNullOrEmpty
        $result.RevocationMode | Should -BeExactly 'NotChecked'
        ($result | ConvertTo-Json -Compress) | Should -Not -Match 'relative\.exe'
    }

    It 'rejects an unsigned local executable without executing it or exposing its path' {
        $unsignedPath = Join-Path $TestDrive 'unsigned-policy-probe.exe'
        [System.IO.File]::WriteAllBytes(
            $unsignedPath,
            [byte[]]@(0x4d, 0x5a, 0x00, 0x00, 0x00, 0x00)
        )

        $result = Get-CddsiD027GitWinVerifyTrustResult `
            -ExecutionContext $script:WinTrustContext `
            -FilePath $unsignedPath

        $result.Trusted | Should -BeFalse
        $result.Status | Should -BeIn @(
            'NoSignature',
            'UnsupportedSubject',
            'Untrusted',
            'PolicyRejected'
        )
        $result.NativeStatusHex | Should -Match '^0x[0-9A-F]{8}$'
        $result.RevocationMode | Should -BeExactly 'NotChecked'
        ($result | ConvertTo-Json -Compress) |
            Should -Not -Match ([regex]::Escape($unsignedPath))
    }

    It 'binds both Git observations to embedded Authenticode and WinVerifyTrust' {
        ([regex]::Matches(
            $script:GitLibrarySource,
            'Get-CddsiD027GitWinVerifyTrustResult[\s\S]{0,160}-ExecutionContext \$Context[\s\S]{0,160}-FilePath \$path'
        )).Count | Should -BeGreaterOrEqual 2
        ([regex]::Matches(
            $script:GitLibrarySource,
            '\$signatureType -cne ''Authenticode'''
        )).Count | Should -BeGreaterOrEqual 2
        $script:GitLibrarySource |
            Should -Match 'TimestampStatus = ''Present'''
        $script:GitLibrarySource |
            Should -Match 'TimestampChainStatus = ''NotIndependentlyEvaluated'''
        $script:GitLibrarySource |
            Should -Not -Match 'TimestampChainTrusted = \$true'
    }
}
