BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:RunnerPath = Join-Path $script:RepoRoot 'scripts\invoke-host-sandbox.ps1'
    . $script:RunnerPath -ImportOnly

    function New-HostSandboxTestLedger {
        return New-Object System.Collections.Generic.List[object]
    }
}

Describe 'P1 trusted HostSandbox harness' {
    It 'uses an owner-marked unique root and synthetic-only paths' {
        $ledger = New-HostSandboxTestLedger
        $runId = '00000000-0000-0000-0000-000000000101'
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId $runId -Ledger $ledger
        try {
            (Split-Path -Leaf $sandbox.Root) | Should -Match '^cddsi-test-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$'
            $sandbox.Root | Should -Match ('^' + [regex]::Escape([System.IO.Path]::GetFullPath($TestDrive).TrimEnd('\')) + '\\')
            $marker = Read-CddsiOwnerMarker -Sandbox $sandbox
            @($marker.PSObject.Properties.Name | Sort-Object) | Should -Be @(
                'MarkerType', 'OwnershipToken', 'RootBindingSha256', 'RunId', 'SchemaVersion'
            )
            $marker.RunId | Should -BeExactly $runId
            foreach ($path in $sandbox.Paths.Values) {
                (Test-CddsiPathWithinRoot -Path $path -Root $sandbox.Root) | Should -BeTrue
            }
            $sandbox.CanaryPaths.Count | Should -Be 5
            @($ledger | Where-Object Plane -eq 'TrustedHarness').Count | Should -Be $ledger.Count
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
    }

    It 'refuses cleanup when the in-memory ownership token is wrong' {
        $ledger = New-HostSandboxTestLedger
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId '00000000-0000-0000-0000-000000000102' -Ledger $ledger
        $actualToken = $sandbox.OwnershipToken
        try {
            $sandbox.OwnershipToken = ('0' * 64 -join '')
            { Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger } | Should -Throw
            (Test-Path -LiteralPath $sandbox.Root -PathType Container) | Should -BeTrue
        }
        finally {
            $sandbox.OwnershipToken = $actualToken
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
    }

    It 'deletes only the exact owned sandbox and preserves a sibling' {
        $ledger = New-HostSandboxTestLedger
        $sibling = Join-Path $TestDrive 'unowned-sibling'
        [void][System.IO.Directory]::CreateDirectory($sibling)
        [System.IO.File]::WriteAllText((Join-Path $sibling 'keep.txt'), 'keep')
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId '00000000-0000-0000-0000-000000000103' -Ledger $ledger

        Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger

        (Test-Path -LiteralPath $sandbox.Root) | Should -BeFalse
        (Test-Path -LiteralPath (Join-Path $sibling 'keep.txt') -PathType Leaf) | Should -BeTrue
        @($ledger | Where-Object RuleId -eq 'CleanupSandbox').Count | Should -Be 1
    }

    It 'builds an allow-list environment with isolated Git and profile state' {
        $ledger = New-HostSandboxTestLedger
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId '00000000-0000-0000-0000-000000000104' -Ledger $ledger
        try {
            $windowsRoot = Join-Path $TestDrive 'synthetic-windows'
            $context = [pscustomobject]@{
                SystemRoot = $windowsRoot
                System32   = Join-Path $windowsRoot 'System32'
                ComSpec    = Join-Path $windowsRoot 'System32\cmd.exe'
            }
            $powerShellHome = Join-Path $windowsRoot 'System32\WindowsPowerShell\v1.0'
            $environment = New-CddsiMinimalEnvironment -Sandbox $sandbox -RepositoryRoot $script:RepoRoot -WindowsContext $context -PowerShellHome $powerShellHome

            $environment.USERPROFILE | Should -BeExactly $sandbox.Paths.Profile
            $environment.HOME | Should -BeExactly $sandbox.Paths.Profile
            $environment.TEMP | Should -BeExactly $sandbox.Paths.Temp
            $environment.GIT_CONFIG_NOSYSTEM | Should -BeExactly '1'
            $environment.GIT_CONFIG_SYSTEM | Should -BeExactly 'NUL'
            $environment.GIT_CONFIG_GLOBAL | Should -BeExactly 'NUL'
            $environment.GIT_TERMINAL_PROMPT | Should -BeExactly '0'
            $environment.POWERSHELL_UPDATECHECK | Should -BeExactly 'Off'
            $environment.Contains('DEEPSEEK_API_KEY') | Should -BeFalse
            $environment.Contains('HTTP_PROXY') | Should -BeFalse
            $environment.Contains('CLAUDE_CONFIG_DIR') | Should -BeFalse
        }
        finally {
            Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
        }
    }

    It 'quotes Windows arguments without shell interpretation' {
        (ConvertTo-CddsiWindowsArgument -Argument 'plain') | Should -BeExactly 'plain'
        (ConvertTo-CddsiWindowsArgument -Argument '') | Should -BeExactly '""'
        (ConvertTo-CddsiWindowsArgument -Argument 'two words') | Should -BeExactly '"two words"'
        (Join-CddsiWindowsArguments -Arguments @('one', 'two words', '')) | Should -BeExactly 'one "two words" ""'
    }

    It 'fails closed before probing a relative tool grant' {
        $ledger = New-HostSandboxTestLedger
        {
            Assert-CddsiTrustedToolGrant `
                -ToolId Git `
                -ExecutablePath 'git.exe' `
                -ExpectedSha256 ('0' * 64 -join '') `
                -ExpectedLeaf 'git.exe' `
                -RunId '00000000-0000-0000-0000-000000000105' `
                -Ledger $ledger
        } | Should -Throw
        $ledger.Count | Should -Be 0
    }

    It 'denies a process-rule hash mismatch before starting the granted file' {
        $ledger = New-HostSandboxTestLedger
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId '00000000-0000-0000-0000-000000000106' -Ledger $ledger
        try {
            $toolPath = Join-Path $sandbox.Root 'fake-tool.exe'
            [System.IO.File]::WriteAllText($toolPath, 'not-an-executable')
            $toolHash = (Get-FileHash -LiteralPath $toolPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $toolGrant = [pscustomobject]@{ ToolId = 'Git'; Path = $toolPath; Sha256 = $toolHash; ResourceToken = '<TOOL_GIT>' }
            $environment = [ordered]@{ TEST_ONLY = '1' }
            $expectedRules = @(
                New-CddsiExpectedProcessRule -Sequence 1 -RuleId 'MismatchBeforeStart' -ToolGrant $toolGrant -Arguments @('expected') -Environment $environment -WorkingDirectoryToken '<SANDBOX_ROOT>'
            )
            $ordinal = 0
            $pathTokens = [ordered]@{ '<SANDBOX_ROOT>' = $sandbox.Root }
            {
                Invoke-CddsiTrustedProcess -RuleId 'MismatchBeforeStart' -ToolGrant $toolGrant -Arguments @('actual') -Environment $environment -WorkingDirectory $sandbox.Root -TimeoutSeconds 30 -ExpectedProcessRules $expectedRules -ProcessOrdinal ([ref]$ordinal) -Ledger $ledger -RunId $sandbox.RunId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
            } | Should -Throw
            $ordinal | Should -Be 0
            $processEntries = @($ledger | Where-Object Category -eq 'Process')
            $processEntries.Count | Should -Be 1
            $processEntries[0].Outcome | Should -BeExactly 'Denied'
            $processEntries[0].Data.MismatchFields | Should -Contain 'ArgumentsSha256'
        }
        finally {
            Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
        }
    }

    It 'fails the persistent artifact scan when a canary is copied' {
        $ledger = New-HostSandboxTestLedger
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId '00000000-0000-0000-0000-000000000107' -Ledger $ledger
        try {
            [System.IO.File]::WriteAllText((Join-Path $sandbox.Paths.Reports 'leak.txt'), $sandbox.CanaryValue)
            { Test-CddsiSandboxArtifacts -Sandbox $sandbox -Ledger $ledger } | Should -Throw
            $scanEntries = @($ledger | Where-Object RuleId -eq 'ScanSandboxArtifacts')
            $scanEntries.Count | Should -Be 1
            $scanEntries[0].Outcome | Should -BeExactly 'Failed'
            $scanEntries[0].Data.FindingCount | Should -BeGreaterThan 0
        }
        finally {
            Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
        }
    }

    It 'scans binary artifacts across chunk boundaries without requiring UTF-8' {
        $ledger = New-HostSandboxTestLedger
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId '00000000-0000-0000-0000-000000000108' -Ledger $ledger
        try {
            $binaryPath = Join-Path $sandbox.Paths.Profile 'AppData\Local\Microsoft\PowerShell\ModuleAnalysisCache-Test'
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $binaryPath))
            [System.IO.File]::WriteAllBytes($binaryPath, [byte[]]@(0xFF, 0x00, 0x81, 0x7F))
            $cleanEvidence = Test-CddsiSandboxArtifacts -Sandbox $sandbox -Ledger $ledger
            $cleanEvidence.FindingCount | Should -Be 0
            $cleanEvidence.FileCount | Should -BeGreaterThan 0

            $pseudoPng = Join-Path $sandbox.Paths.Profile 'AppData\Local\Microsoft\PowerShell\pseudo-secret.png'
            $prefix = New-Object byte[] 65534
            $prefix[0] = 0x89
            $prefix[1] = 0x50
            $prefix[2] = 0x4E
            $prefix[3] = 0x47
            $syntheticKey = 'sk-' + ('x' * 32 -join '')
            $secretBytes = [System.Text.Encoding]::ASCII.GetBytes($syntheticKey)
            $payload = New-Object byte[] ($prefix.Length + $secretBytes.Length)
            [Array]::Copy($prefix, 0, $payload, 0, $prefix.Length)
            [Array]::Copy($secretBytes, 0, $payload, $prefix.Length, $secretBytes.Length)
            [System.IO.File]::WriteAllBytes($pseudoPng, $payload)

            $failure = { Test-CddsiSandboxArtifacts -Sandbox $sandbox -Ledger $ledger } | Should -Throw -PassThru
            $failure.Exception.Message | Should -Not -Match [regex]::Escape($syntheticKey)
            @($ledger | Where-Object { $_.RuleId -eq 'ScanSandboxArtifacts' -and $_.Outcome -eq 'Failed' }).Count | Should -Be 1
        }
        finally {
            Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
        }
    }

    It 'redacts API material, ownership tokens, and host paths' {
        $token = ('a' * 64 -join '')
        $paths = [ordered]@{ '<REPOSITORY_ROOT>' = 'C:\Source Repo' }
        $apiKey = 'sk-' + ('z' * 32 -join '')
        $safe = Protect-CddsiHarnessText -Text ('path=C:\Source Repo token=' + $token + ' key=' + $apiKey) -PathTokens $paths -OwnershipToken $token
        $safe | Should -Match '<REPOSITORY_ROOT>'
        $safe | Should -Match '\[OWNERSHIP_TOKEN\]'
        $safe | Should -Match '\[REDACTED\]'
        $safe | Should -Not -Match [regex]::Escape($apiKey)
    }

    It 'removes ANSI, control, and bidirectional characters before redaction' {
        $token = ('a' * 64 -join '')
        $canary = 'CDDSI_SYNTHETIC_CANARY_00000000000000000000000000000109'
        $paths = [ordered]@{ '<REPOSITORY_ROOT>' = 'C:\Source Repo' }
        $apiKey = 'sk-' + ('q' * 32 -join '')
        $raw = ([char]27) + '[31mC:\Source' + ([char]0) + ' Repo' + ([char]27) + '[0m' + ([char]0x202E) + $token + $canary + 's' + ([char]8) + $apiKey.Substring(1)

        $safe = Protect-CddsiHarnessText -Text $raw -PathTokens $paths -OwnershipToken $token -CanaryValue $canary

        (Test-CddsiSafeDiagnosticDisclosure -Text $safe -PathTokens $paths -OwnershipToken $token -CanaryValue $canary) | Should -BeTrue
        $safe | Should -Match '<REPOSITORY_ROOT>'
        $safe | Should -Match '\[OWNERSHIP_TOKEN\]'
        $safe | Should -Match '\[SYNTHETIC_CANARY\]'
        $safe | Should -Match '\[REDACTED\]'
        $safe | Should -Not -Match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u202A-\u202E]'
    }

    It 'creates an exact machine-readable safe failure envelope' {
        $token = ('b' * 64 -join '')
        $canary = 'CDDSI_SYNTHETIC_CANARY_00000000000000000000000000000110'
        $paths = [ordered]@{ '<REPOSITORY_ROOT>' = 'C:\Sensitive Repo' }
        $apiKey = 'sk-' + ('r' * 32 -join '')
        $evidence = New-CddsiSafeFailureEvidence `
            -Scenario Quality `
            -RunId '00000000-0000-0000-0000-000000000110' `
            -PrimaryFailureCode 'PRIMARY_FAILURE' `
            -PrimaryFailureMessage ('primary C:\Sensitive Repo ' + $token + $canary + $apiKey) `
            -CleanupOutcome RefusedUnsafeCleanup `
            -CleanupFailureCode CLEANUP_REFUSED_UNSAFE `
            -RepositoryContentChanged $true `
            -PathTokens $paths `
            -OwnershipToken $token `
            -CanaryValue $canary

        @($evidence.PSObject.Properties.Name | Sort-Object) | Should -Be @(
            'CleanupFailureCode', 'CleanupOutcome', 'EvidenceType', 'PrimaryFailureCode',
            'RepositoryContentChanged', 'RunId', 'SafeFailureDisclosure', 'SafeFailureMessage',
            'Scenario', 'SchemaVersion', 'Status'
        )
        $evidence.Status | Should -BeExactly 'FAILED_SAFE'
        $evidence.RepositoryContentChanged | Should -BeTrue
        $evidence.CleanupOutcome | Should -BeExactly 'RefusedUnsafeCleanup'
        $exception = New-CddsiSafeFailureException -Evidence $evidence
        $json = [string]$exception.Data['CddsiFailureEvidenceJson']
        $roundTrip = $json | ConvertFrom-Json
        $roundTrip.PrimaryFailureCode | Should -BeExactly 'PRIMARY_FAILURE'
        $roundTrip.CleanupFailureCode | Should -BeExactly 'CLEANUP_REFUSED_UNSAFE'
        $json | Should -Not -Match [regex]::Escape($apiKey)
        $json | Should -Not -Match [regex]::Escape($token)
        $json | Should -Not -Match [regex]::Escape($canary)
        $json | Should -Not -Match [regex]::Escape('C:\Sensitive Repo')
    }

    It 'reports only deterministic field names for worker provenance drift' {
        $secret = 'sk-' + ('s' * 32 -join '')
        $actual = [pscustomobject][ordered]@{
            EngineGrantSha256 = $secret
            PesterTreeSha256  = 'same'
        }
        $expected = [ordered]@{
            PesterTreeSha256  = 'same'
            EngineGrantSha256 = 'expected'
        }

        $drift = @(Get-CddsiWorkerProvenanceBindingDrift -Actual $actual -Expected $expected)
        $drift | Should -Be @('EngineGrantSha256')
        ($drift -join ', ') | Should -Not -Match [regex]::Escape($secret)
    }

    It 'rejects any extra successful harness ledger entry and Data drift' {
        $runId = '00000000-0000-0000-0000-000000000111'
        $ledger = New-HostSandboxTestLedger
        Add-CddsiHarnessLedgerEntry -Ledger $ledger -RunId $runId -Category FileSystem -RuleId ExactEntry -ResourceToken '<SANDBOX_ROOT>' -Outcome Succeeded -Data ([pscustomobject][ordered]@{ Count = [int]1 })
        $expected = @(
            New-CddsiExpectedHarnessLedgerEntry -Sequence 1 -RunId $runId -Category FileSystem -RuleId ExactEntry -ResourceToken '<SANDBOX_ROOT>' -Outcome Succeeded -Data ([pscustomobject][ordered]@{ Count = [int]1 })
        )
        (Assert-CddsiHarnessLedgerExact -Ledger $ledger -ExpectedEntries $expected) | Should -BeTrue

        Add-CddsiHarnessLedgerEntry -Ledger $ledger -RunId $runId -Category FileSystem -RuleId ExtraSuccess -ResourceToken '<SANDBOX_ROOT>/extra' -Outcome Succeeded -Data $null
        { Assert-CddsiHarnessLedgerExact -Ledger $ledger -ExpectedEntries $expected } | Should -Throw

        $ledger.RemoveAt(1)
        $ledger[0].Data = [pscustomobject][ordered]@{ Count = [int]2 }
        { Assert-CddsiHarnessLedgerExact -Ledger $ledger -ExpectedEntries $expected } | Should -Throw
        $ledger[0].Data = [pscustomobject][ordered]@{ Count = [int]1; Extra = [int]0 }
        { Assert-CddsiHarnessLedgerExact -Ledger $ledger -ExpectedEntries $expected } | Should -Throw
        $ledger[0].Data = [pscustomobject][ordered]@{ Count = [int]1 }
        $ledger[0] | Add-Member -NotePropertyName ExtraOuterField -NotePropertyValue 'unexpected'
        { Assert-CddsiHarnessLedgerExact -Ledger $ledger -ExpectedEntries $expected } | Should -Throw
        $ledger[0].PSObject.Properties.Remove('ExtraOuterField')
        $ledger[0].Sequence = [long]1
        { Assert-CddsiHarnessLedgerExact -Ledger $ledger -ExpectedEntries $expected } | Should -Throw
    }

    It 'detects file, development-only, and empty-directory repository drift' {
        $root = Join-Path $TestDrive 'snapshot-repository'
        [void][System.IO.Directory]::CreateDirectory($root)
        [System.IO.File]::WriteAllText((Join-Path $root 'package.txt'), 'one')
        $before = Get-CddsiRepositorySnapshot -RootPath $root

        $developmentDirectory = Join-Path $root 'tests\empty'
        [void][System.IO.Directory]::CreateDirectory($developmentDirectory)
        $withEmptyDirectory = Get-CddsiRepositorySnapshot -RootPath $root
        $withEmptyDirectory.Hash | Should -Not -BeExactly $before.Hash
        $withEmptyDirectory.DirectoryCount | Should -BeGreaterThan $before.DirectoryCount

        [System.IO.File]::WriteAllText((Join-Path $root 'tests\development-only.txt'), 'two')
        $withDevelopmentFile = Get-CddsiRepositorySnapshot -RootPath $root
        $withDevelopmentFile.Hash | Should -Not -BeExactly $withEmptyDirectory.Hash
        $withDevelopmentFile.FileCount | Should -BeGreaterThan $withEmptyDirectory.FileCount
        $withDevelopmentFile.Scope | Should -BeExactly 'WorkingTreeExcludingDotGit'
    }

    It 'contains ProcessStartInfo orchestration and no policy-bypass switches' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:RunnerPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $types = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.TypeExpressionAst] -or
                $node -is [System.Management.Automation.Language.TypeConstraintAst]
        }, $true) | ForEach-Object { $_.TypeName.FullName })
        $types | Should -Contain 'System.Diagnostics.ProcessStartInfo'
        $content = [System.IO.File]::ReadAllText($script:RunnerPath)
        $encodedPattern = '(?i)-Encoded' + 'Command'
        $policyPattern = '(?i)-Execution' + 'Policy\s+Bypass'
        $content | Should -Not -Match $encodedPattern
        $content | Should -Not -Match $policyPattern
    }
}
