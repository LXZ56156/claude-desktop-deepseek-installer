BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'common safety helpers' {
    It 'defaults to TestSafe and rejects conflicting modes' {
        (Resolve-CddsiExecutionMode) | Should -Be 'TestSafe'
        (Resolve-CddsiExecutionMode -DryRun) | Should -Be 'DryRun'
        { Resolve-CddsiExecutionMode -TestSafe -Live } | Should -Throw
    }

    It 'keeps all real mutation disabled during scaffold stage' {
        (Test-CddsiRealMutationAllowed -Mode Live -AcknowledgeRealChanges) | Should -BeFalse
        { Assert-CddsiMutationAllowed -Operation 'probe' -Mode Live -AcknowledgeRealChanges } | Should -Throw
    }

    It 'returns a stable structured result' {
        $result = New-CddsiOperationResult -Operation 'probe' -Status 'planned' -Success $true -Mode DryRun
        $result.PSObject.Properties.Name | Should -Contain 'RestartRequired'
        $result.PSObject.Properties.Name | Should -Contain 'PlannedChanges'
        $result.Changed | Should -BeFalse
    }

    It 'redacts complete key material without retaining a suffix' {
        $key = 'sk-' + ('A' * 32)
        $safe = Protect-CddsiSecret -Text ("credential=$key")
        $safe | Should -Not -Match ([regex]::Escape($key))
        $safe | Should -Match '\[REDACTED\]'
        $safe | Should -Not -Match 'AAAA'
    }

    It 'finds a synthetic key but never returns the raw match' {
        $key = 'sk-' + ('B' * 31) + '-'
        $findings = @(Find-CddsiPotentialSecrets -Content ("line`n$key") -Source 'memory')
        $findings.Count | Should -Be 1
        $findings[0].Line | Should -Be 2
        ($findings | ConvertTo-Json -Depth 5) | Should -Not -Match ([regex]::Escape($key))
    }

    It 'detects and fully redacts JSON credentials authorization and private keys' {
        $token = 'T' * 32
        $privateLabel = 'PRIVATE' + ' KEY'
        $content = "{`"apiKey`":`"$token`"}`nauthorization=$token`n-----BEGIN $privateLabel-----`n$token`n-----END $privateLabel-----"
        $findings = @(Find-CddsiPotentialSecrets -Content $content -Source 'synthetic')
        @($findings.Type) | Should -Contain 'CredentialAssignment'
        @($findings.Type) | Should -Contain 'PrivateKey'
        ($findings | ConvertTo-Json -Depth 5) | Should -Not -Match $token
        (Protect-CddsiSecret -Text $content) | Should -Not -Match $token
        (Protect-CddsiLogMessage -Message $content) | Should -Not -Match $token
    }

    It 'validates without silently trimming API key input' {
        $key = 'sk-' + ('C' * 24)
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey $key) | Should -BeTrue
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey (" $key")) | Should -BeFalse
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey ($key + "`n")) | Should -BeFalse
    }

    It 'rejects forged or incomplete signature evidence' {
        $path = Join-Path $TestDrive 'Claude.msix'
        (Test-CddsiSignatureEvidence -Evidence ([pscustomobject]@{ Valid = $true }) -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix) | Should -BeFalse
        $evidence = [pscustomobject]@{
            SchemaVersion = 1
            ArtifactType = 'ClaudeDesktopMsix'
            PathBindingToken = Get-CddsiPathBindingToken -Path $path
            ArtifactSha256 = ('a' * 64)
            Valid = $true
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            PublisherMatch = $true
            IdentityMatch = $true
            SourcePolicy = 'anthropic_official_only'
        }
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix) | Should -BeTrue
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath (Join-Path $TestDrive 'Other.msix') -ExpectedArtifactType ClaudeDesktopMsix) | Should -BeFalse
        $evidence.Valid = 'true'
        $evidence.SchemaVersion = '1'
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix) | Should -BeFalse
    }

    It 'detects same-path artifact replacement by SHA-256' {
        $path = Join-Path $TestDrive 'artifact.bin'
        [System.IO.File]::WriteAllText($path, 'first')
        $hash = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        (Test-CddsiArtifactHashBinding -Path $path -ExpectedSha256 $hash) | Should -BeTrue
        [System.IO.File]::WriteAllText($path, 'replaced')
        (Test-CddsiArtifactHashBinding -Path $path -ExpectedSha256 $hash) | Should -BeFalse
    }

    It 'requires an explicit temporary artifact root for file logging' {
        { Initialize-CddsiLogger -EnableFileLogging -Mode TestSafe } | Should -Throw
        { Initialize-CddsiLogger -EnableFileLogging -Mode DryRun -ArtifactRoot (Join-Path $script:RepoRoot 'logs') } | Should -Throw
        { Initialize-CddsiLogger -EnableFileLogging -Mode Live -ArtifactRoot (Join-Path $TestDrive 'live-log') } | Should -Throw
        $artifactRoot = Join-Path $TestDrive ('cddsi-' + [guid]::NewGuid().ToString('N'))
        $logPath = Initialize-CddsiLogger -EnableFileLogging -Mode TestSafe -ArtifactRoot $artifactRoot -ScriptName 'unit'
        $token = 'L' * 32
        Write-CddsiLog -Level INFO -Message ("authorization=$token")
        [System.IO.File]::ReadAllText($logPath) | Should -Not -Match $token
        Initialize-CddsiLogger -Mode TestSafe | Should -BeNullOrEmpty
    }

    It 'creates an in-memory Chinese acceptance report with path user and credential redaction' {
        $token = 'sk-' + ('R' * 24)
        $userPath = Join-Path ([Environment]::GetFolderPath('UserProfile')) 'secret.txt'
        $result = [pscustomobject]@{ status = '通过'; path = $userPath; user = [Environment]::UserName; authorization = $token }
        $report = New-CddsiAcceptanceReport -Results $result
        $report.language | Should -Be 'zh-CN'
        $report.redacted | Should -BeTrue
        $report.persisted | Should -BeFalse
        $report.content | Should -Match '验收报告'
        $report.content | Should -Not -Match ([regex]::Escape($token))
        $report.content | Should -Not -Match ([regex]::Escape([Environment]::UserName))
        $report.content | Should -Not -Match ([regex]::Escape([Environment]::GetFolderPath('UserProfile')))
    }
}
