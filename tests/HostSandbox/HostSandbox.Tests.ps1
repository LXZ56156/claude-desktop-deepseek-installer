BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:RunnerPath = Join-Path $script:RepoRoot 'scripts\invoke-host-sandbox.ps1'
    $script:WorkerPath = Join-Path $script:RepoRoot 'scripts\check-worker.ps1'
    $script:GateCommonPath = Join-Path $script:RepoRoot 'scripts\release-gate-common.ps1'
    . $script:RunnerPath -ImportOnly
    . $script:GateCommonPath
    . $script:WorkerPath `
        -RepositoryRoot $script:RepoRoot `
        -SandboxRoot (Join-Path ([System.IO.Path]::GetTempPath()) 'cddsi-worker-builder-only') `
        -RunId '00000000-0000-0000-0000-000000000100' `
        -RepositoryInventoryPath (Join-Path $script:RepoRoot 'scripts\release-manifest.psd1') `
        -BoundaryManifestPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1') `
        -DependencyManifestPath (Join-Path $script:RepoRoot 'vendor\dev-dependencies.lock.psd1') `
        -EngineId PowerShell7 `
        -EngineExecutablePath (Join-Path $PSHOME 'powershell.exe') `
        -EngineGrantSha256 ('0' * 64 -join '') `
        -GitExecutablePath 'C:\cddsi-synthetic-tools\git.exe' `
        -GitGrantSha256 ('0' * 64 -join '') `
        -EvidenceBuilderOnly

    function New-HostSandboxTestLedger {
        return New-Object System.Collections.Generic.List[object]
    }

    function New-CddsiHistoricalPesterCompletionFixture {
        $runtimeError = [System.Management.Automation.ErrorRecord]::new(
            [System.InvalidOperationException]::new('synthetic runtime failure'),
            'SyntheticRuntimeFailure',
            [System.Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )
        return [pscustomobject][ordered]@{
            Result                 = 'Failed'
            TotalCount             = [long]2
            PassedCount            = [long]1
            FailedCount            = [long]1
            SkippedCount           = [long]0
            NotRunCount            = [long]0
            InconclusiveCount      = [long]0
            FailedBlocksCount      = [long]0
            FailedContainersCount  = [long]0
            Tests                  = @(
                [pscustomobject][ordered]@{
                    Result      = 'Passed'
                    ErrorRecord = @()
                },
                [pscustomobject][ordered]@{
                    Result      = 'Failed'
                    ErrorRecord = @($runtimeError)
                }
            )
        }
    }

    function New-CddsiGateAggregateWorkerFixture {
        param(
            [Parameter(Mandatory = $true)]
            [ValidateSet('PowerShell7', 'WindowsPowerShell')]
            [string]$Engine,

            [Parameter(Mandatory = $true)]
            $QualitySetPolicy,

            [string]$SandboxBindingSha256 = ('8' * 64 -join ''),

            [string]$FailedShardId = '',

            [AllowNull()]$FailedTest
        )

        $runId = '00000000-0000-0000-0000-000000000120'
        $sameRepositoryManifestSha256 = ('2' * 64 -join '')
        $dependency = Import-PowerShellDataFile -LiteralPath (
            Join-Path $script:RepoRoot 'config\dev-dependencies.psd1')
        $boundary = Import-PowerShellDataFile -LiteralPath (
            Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
        $accessLedger = [pscustomobject][ordered]@{
            ContextCount                  = 2L
            TestSafeContextCount          = 1L
            DryRunContextCount            = 1L
            EntryCount                    = 2L
            ForbiddenResourceAccessCount  = 0L
            OutsideSandboxWriteCount      = 0L
            ProductLiveProcessSpawnCount  = 0L
            ProductNetworkRequestCount    = 0L
            RealRegistryAccessCount       = 0L
            UnexpectedLedgerEntryCount    = 0L
        }
        $mutationSpyCounts = [pscustomobject][ordered]@{
            FileSystem = 0L
            Environment = 0L
            Registry = 0L
            Network = 0L
            Process = 0L
            AppX = 0L
            Feature = 0L
            Service = 0L
            Credential = 0L
            Restart = 0L
        }
        $staticEvidence = [pscustomobject][ordered]@{
            SchemaVersion         = 1L
            EvidenceType         = 'CddsiWorkerStaticEvidence'
            RunId                = $runId
            Engine               = $Engine
            SandboxBindingSha256 = $SandboxBindingSha256
            Measurements         = [pscustomobject][ordered]@{
                AstSyntaxErrorCount      = 0L
                LiveAdapterFileCount     = [long]@($boundary.Planes.LiveAdapters).Count
                SecretFindingCount       = 0L
                RepositoryContentChanged = $false
                LiveProviderLoaded       = $false
                AccessLedger             = $accessLedger
                MutationSpyCounts        = $mutationSpyCounts
            }
            Provenance           = [pscustomobject][ordered]@{
                MeasurementRuleVersion          = 'cddsi-worker-measurement-rules-v6'
                RepositoryInventorySha256       = ('1' * 64 -join '')
                InitialRepositoryManifestSha256 = $sameRepositoryManifestSha256
                FinalRepositoryManifestSha256   = $sameRepositoryManifestSha256
                ExecutionBoundaryManifestSha256 = ('3' * 64 -join '')
                DependencyManifestSha256        = [string]$QualitySetPolicy.DependencyManifestSha256
                PesterTreeSha256                = [string]$dependency.Pester.ExpectedTreeSha256
                EngineGrantSha256               = ('4' * 64 -join '')
                QualityShardPolicySha256        = [string]$QualitySetPolicy.CanonicalSha256
            }
        }
        $shardEvidence = New-Object System.Collections.Generic.List[object]
        foreach ($profileShard in @($QualitySetPolicy.QualityShards)) {
            $isFailedShard = [string]$profileShard.ShardId -ceq $FailedShardId
            if ($isFailedShard -and $null -eq $FailedTest) {
                throw 'Synthetic failed shard requires failed-test evidence.'
            }
            $requiredSuites = @($dependency.IsolationEvidenceSuites | Where-Object {
                @($profileShard.Paths) -ccontains ([string]$_.RelativePath).Replace('\', '/')
            } | ForEach-Object {
                [pscustomobject][ordered]@{
                    RelativePath = ([string]$_.RelativePath).Replace('\', '/')
                    TestCount    = [long]$_.ExpectedTestCount
                    Result       = 'Passed'
                }
            })
            $shardEvidence.Add([pscustomobject][ordered]@{
                SchemaVersion         = 2L
                EvidenceType         = 'CddsiWorkerPesterShardEvidence'
                RunId                = $runId
                Engine               = $Engine
                ShardId              = [string]$profileShard.ShardId
                SandboxBindingSha256 = $SandboxBindingSha256
                ShardPathsSha256     = [string]$profileShard.PathsSha256
                TestFiles            = [string[]]@($profileShard.Paths)
                Pester               = [pscustomobject][ordered]@{
                    Result                      = $(if ($isFailedShard) { 'Failed' } else { 'Passed' })
                    TotalCount                  = 1L
                    PassedCount                 = $(if ($isFailedShard) { 0L } else { 1L })
                    FailedCount                 = $(if ($isFailedShard) { 1L } else { 0L })
                    FailedBlocksCount           = 0L
                    FailedContainersCount       = 0L
                    FailedTests                 = $(if ($isFailedShard) { @($FailedTest) } else { @() })
                    FailedTestEvidenceTruncated = $false
                    SkippedCount                = 0L
                    NotRunCount                 = 0L
                    InconclusiveCount           = 0L
                    DurationMilliseconds        = 1L
                }
                RequiredSuiteResults = $requiredSuites
                Provenance           = [pscustomobject][ordered]@{
                    MeasurementRuleVersion          = 'cddsi-worker-measurement-rules-v6'
                    RepositoryInventorySha256       = ('1' * 64 -join '')
                    InitialRepositoryManifestSha256 = $sameRepositoryManifestSha256
                    FinalRepositoryManifestSha256   = $sameRepositoryManifestSha256
                    DependencyManifestSha256        = [string]$QualitySetPolicy.DependencyManifestSha256
                    PesterTreeSha256                = [string]$dependency.Pester.ExpectedTreeSha256
                    EngineGrantSha256               = ('4' * 64 -join '')
                    QualityShardPolicySha256        = [string]$QualitySetPolicy.CanonicalSha256
                }
            })
        }
        return Merge-CddsiWorkerIsolationEvidence `
            -Engine $Engine `
            -StaticEvidence $staticEvidence `
            -ShardEvidence $shardEvidence.ToArray() `
            -QualityShardPolicy $QualitySetPolicy `
            -DependencyManifestPath (Join-Path $script:RepoRoot 'config\dev-dependencies.psd1')
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
        $gitRenderedPath = 'C:/Source Repo/nested\objects'
        (Test-CddsiSafeDiagnosticDisclosure -Text ('path=' + $gitRenderedPath) `
                -PathTokens $paths) | Should -BeFalse

        $safe = Protect-CddsiHarnessText `
            -Text ('path=C:\Source Repo git=' + $gitRenderedPath +
                ' token=' + $token + ' key=' + $apiKey) `
            -PathTokens $paths `
            -OwnershipToken $token
        $safe | Should -Match '<REPOSITORY_ROOT>'
        $safe | Should -Match '\[OWNERSHIP_TOKEN\]'
        $safe | Should -Match '\[REDACTED\]'
        $safe | Should -Not -Match [regex]::Escape($apiKey)
        $safe | Should -Not -Match [regex]::Escape('C:\Source Repo')
        $safe | Should -Not -Match [regex]::Escape('C:/Source Repo')
        (Test-CddsiSafeDiagnosticDisclosure -Text $safe -PathTokens $paths `
                -OwnershipToken $token) | Should -BeTrue

        $originalCulture = [Threading.Thread]::CurrentThread.CurrentCulture
        try {
            [Threading.Thread]::CurrentThread.CurrentCulture =
                [Globalization.CultureInfo]::GetCultureInfo('tr-TR')
            $culturePaths = [ordered]@{ '<SANDBOX_ROOT>' = 'C:\INSTALL' }
            $cultureSafe = Protect-CddsiHarnessText -Text 'path=c:/install/nested' `
                -PathTokens $culturePaths
            $cultureSafe | Should -BeExactly 'path=<SANDBOX_ROOT>/nested'
            (Test-CddsiSafeDiagnosticDisclosure -Text 'path=c:/install/nested' `
                    -PathTokens $culturePaths) | Should -BeFalse
        }
        finally {
            [Threading.Thread]::CurrentThread.CurrentCulture = $originalCulture
        }
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

    It 'keeps Chinese and non-BMP characters intact at the timeout-tail boundary' {
        $suffix = '质量检查：中文 😀 𠮷'
        $text = ('x' * 5000) + $suffix
        $tail = Get-CddsiUnicodeSafeTail -Text $text -MaximumLength $suffix.Length
        $tail | Should -BeExactly $suffix
        $tail | Should -Not -Match ([string][char]0xFFFD)

        $boundary = ('y' * 12) + [char]0xD83D + [char]0xDE00 + 'z'
        $safeBoundary = Get-CddsiUnicodeSafeTail -Text $boundary -MaximumLength 2
        $safeBoundary | Should -BeExactly 'z'
        @($safeBoundary.ToCharArray() | Where-Object {
            [char]::IsHighSurrogate($_) -or [char]::IsLowSurrogate($_)
        }).Count | Should -Be 0
    }

    It 'bounds redirected-task draining and preserves decoded Unicode' {
        $completedSource = New-Object 'System.Threading.Tasks.TaskCompletionSource[string]'
        $completedSource.SetResult('质量检查 😀 𠮷')
        $completed = Read-CddsiProcessTextTask -Task $completedSource.Task -WaitMilliseconds 100 -FailureText 'FAILED'
        $completed.Succeeded | Should -BeTrue
        $completed.Text | Should -BeExactly '质量检查 😀 𠮷'

        $pendingSource = New-Object 'System.Threading.Tasks.TaskCompletionSource[string]'
        $pending = Read-CddsiProcessTextTask -Task $pendingSource.Task -WaitMilliseconds 1 -FailureText 'OUTPUT_DRAIN_TIMEOUT'
        $pending.Succeeded | Should -BeFalse
        $pending.Text | Should -BeExactly 'OUTPUT_DRAIN_TIMEOUT'
    }

    It 'creates an exact machine-readable safe failure envelope' {
        $token = ('b' * 64 -join '')
        $canary = 'CDDSI_SYNTHETIC_CANARY_00000000000000000000000000000110'
        $paths = [ordered]@{ '<REPOSITORY_ROOT>' = 'C:\Sensitive Repo' }
        $apiKey = 'sk-' + ('r' * 32 -join '')
        $currentFailure = [pscustomobject]@{
            Pester = [pscustomobject]@{
                FailedCount = 1L
                FailedTestEvidenceTruncated = $false
                FailedTests = @(
                    [pscustomobject][ordered]@{
                        RelativePath = 'tests/HostSandbox/HostSandbox.Tests.ps1'
                        StartLine = 279L
                        Name = 'creates an exact machine-readable safe failure envelope'
                        ErrorRecordCount = 1L
                    }
                )
            }
        }
        $progress = New-CddsiQualityFailureProgress `
            -CompletedRoleEvidence @(
                [pscustomobject]@{
                    EvidenceType = 'CddsiWorkerStaticEvidence'
                    Engine       = 'PowerShell7'
                },
                [pscustomobject]@{
                    EvidenceType = 'CddsiWorkerPesterShardEvidence'
                    Engine       = 'PowerShell7'
                    ShardId      = 'C01'
                    TestFiles    = @('tests/Contract/One.Tests.ps1', 'tests/Unit/Two.Tests.ps1')
                    Pester       = [pscustomobject]@{ PassedCount = 17L }
                }
            ) `
            -CompletedWorkerIds @('PowerShell7/Static', 'PowerShell7/C01') `
            -CurrentWorkerDescriptor ([pscustomobject]@{
                Engine = 'PowerShell7'; WorkerRole = 'PesterShard'; ShardId = 'C02'
            }) `
            -CurrentWorkerFailureEvidence $currentFailure `
            -ExpectedWorkerCount 28 `
            -TimedOut $true
        $evidence = New-CddsiSafeFailureEvidence `
            -Scenario Quality `
            -RunId '00000000-0000-0000-0000-000000000110' `
            -PrimaryFailureCode 'PRIMARY_FAILURE' `
            -PrimaryFailureMessage ('primary C:\Sensitive Repo ' + $token + $canary + $apiKey) `
            -CleanupOutcome RefusedUnsafeCleanup `
            -CleanupFailureCode CLEANUP_REFUSED_UNSAFE `
            -RepositoryContentChanged $true `
            -Progress $progress `
            -PathTokens $paths `
            -OwnershipToken $token `
            -CanaryValue $canary

        @($evidence.PSObject.Properties.Name | Sort-Object) | Should -Be @(
            'CleanupFailureCode', 'CleanupOutcome', 'EvidenceType', 'PrimaryFailureCode',
            'Progress', 'RepositoryContentChanged', 'RunId', 'SafeFailureDisclosure', 'SafeFailureMessage',
            'Scenario', 'SchemaVersion', 'Status'
        )
        $evidence.SchemaVersion | Should -Be 3
        $evidence.Status | Should -BeExactly 'FAILED_SAFE'
        $evidence.RepositoryContentChanged | Should -BeTrue
        $evidence.CleanupOutcome | Should -BeExactly 'RefusedUnsafeCleanup'
        $exception = New-CddsiSafeFailureException -Evidence $evidence
        $json = [string]$exception.Data['CddsiFailureEvidenceJson']
        $roundTrip = $json | ConvertFrom-Json
        $roundTrip.PrimaryFailureCode | Should -BeExactly 'PRIMARY_FAILURE'
        $roundTrip.CleanupFailureCode | Should -BeExactly 'CLEANUP_REFUSED_UNSAFE'
        $roundTrip.Progress.Phase | Should -BeExactly 'QualityWorker'
        $roundTrip.Progress.CompletedWorkerCount | Should -Be 2
        $roundTrip.Progress.CompletedShardCount | Should -Be 1
        $roundTrip.Progress.CompletedTestFileCount | Should -Be 2
        $roundTrip.Progress.CompletedPassedCount | Should -Be 17
        $roundTrip.Progress.CurrentShardId | Should -BeExactly 'C02'
        $roundTrip.Progress.CurrentFailedCount | Should -Be 1
        $roundTrip.Progress.CurrentFailedTestEvidenceTruncated | Should -BeFalse
        $roundTrip.Progress.CurrentFailedTests[0].RelativePath |
            Should -BeExactly 'tests/HostSandbox/HostSandbox.Tests.ps1'
        $roundTrip.Progress.CurrentFailedTests[0].StartLine | Should -Be 279
        $roundTrip.Progress.CurrentFailedTests[0].Name |
            Should -BeExactly 'creates an exact machine-readable safe failure envelope'
        $roundTrip.Progress.TimedOut | Should -BeTrue
        (Assert-CddsiSafeFailureEvidence -Evidence $roundTrip -PathTokens $paths -OwnershipToken $token -CanaryValue $canary) |
            Should -BeTrue
        $json | Should -Not -Match [regex]::Escape($apiKey)
        $json | Should -Not -Match [regex]::Escape($token)
        $json | Should -Not -Match [regex]::Escape($canary)
        $json | Should -Not -Match [regex]::Escape('C:\Sensitive Repo')
    }

    It 'accepts only source-bound static failed-test summaries' {
        $failedTest = [pscustomobject][ordered]@{
            RelativePath = 'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
            StartLine = 2800L
            Name = 'stages three distinct mocked keypairs with protected receipts and reuses the exact valid root idempotently'
            ErrorRecordCount = 1L
        }

        (Assert-CddsiSafeFailedTestSummary `
            -FailedTests @($failedTest) `
            -FailedCount 1 `
            -Truncated $false) | Should -BeTrue
        (Assert-CddsiFailedTestSourceBinding `
            -FailedTests @($failedTest) `
            -RepositoryRoot $script:RepoRoot `
            -AllowedRelativePaths @($failedTest.RelativePath)) | Should -BeTrue

        $forged = $failedTest.PSObject.Copy()
        $forged.Name = 'forged runtime text'
        {
            Assert-CddsiFailedTestSourceBinding `
                -FailedTests @($forged) `
                -RepositoryRoot $script:RepoRoot `
                -AllowedRelativePaths @($failedTest.RelativePath)
        } | Should -Throw
    }

    It 'validates persisted failed-test evidence through exact entry 33 at every consumer' {
        $newFailedTest = {
            [pscustomobject][ordered]@{
                RelativePath = 'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
                StartLine = 2800L
                Name = 'stages three distinct mocked keypairs with protected receipts and reuses the exact valid root idempotently'
                ErrorRecordCount = 1L
            }
        }
        $complete = @(1..33 | ForEach-Object { & $newFailedTest })

        {
            Assert-CddsiSafeFailedTestSummary `
                -FailedTests $complete `
                -FailedCount 33L `
                -Truncated $false
        } | Should -Not -Throw
        {
            Assert-CddsiFailedTestSourceBinding `
                -FailedTests $complete `
                -RepositoryRoot $script:RepoRoot `
                -AllowedRelativePaths @($complete[0].RelativePath)
        } | Should -Not -Throw
        {
            Assert-CddsiGateFailedTestSummary `
                -FailedTests $complete `
                -FailedCount 33L `
                -Truncated $false `
                -AllowedRelativePaths @($complete[0].RelativePath) `
                -RepositoryRoot $script:RepoRoot `
                -Label 'synthetic 33-entry shard'
        } | Should -Not -Throw

        {
            Assert-CddsiSafeFailedTestSummary `
                -FailedTests $complete `
                -FailedCount 33L `
                -Truncated $true
        } | Should -Throw
        {
            Assert-CddsiGateFailedTestSummary `
                -FailedTests $complete `
                -FailedCount 33L `
                -Truncated $true `
                -AllowedRelativePaths @($complete[0].RelativePath) `
                -RepositoryRoot $script:RepoRoot `
                -Label 'synthetic 33-entry shard'
        } | Should -Throw

        $missingErrorRecordCount = @(1..33 | ForEach-Object { & $newFailedTest })
        $missingErrorRecordCount[32].PSObject.Properties.Remove('ErrorRecordCount')
        {
            Assert-CddsiSafeFailedTestSummary `
                -FailedTests $missingErrorRecordCount `
                -FailedCount 33L `
                -Truncated $false
        } | Should -Throw

        $zeroErrorRecordCount = @(1..33 | ForEach-Object { & $newFailedTest })
        $zeroErrorRecordCount[32].ErrorRecordCount = 0L
        {
            Assert-CddsiGateFailedTestSummary `
                -FailedTests $zeroErrorRecordCount `
                -FailedCount 33L `
                -Truncated $false `
                -AllowedRelativePaths @($zeroErrorRecordCount[0].RelativePath) `
                -RepositoryRoot $script:RepoRoot `
                -Label 'synthetic 33-entry shard'
        } | Should -Throw

        $forgedSource = @(1..33 | ForEach-Object { & $newFailedTest })
        $forgedSource[32].Name = 'forged entry 33 source binding'
        {
            Assert-CddsiFailedTestSourceBinding `
                -FailedTests $forgedSource `
                -RepositoryRoot $script:RepoRoot `
                -AllowedRelativePaths @($forgedSource[0].RelativePath)
        } | Should -Throw
        {
            Assert-CddsiGateFailedTestSummary `
                -FailedTests $forgedSource `
                -FailedCount 33L `
                -Truncated $false `
                -AllowedRelativePaths @($forgedSource[0].RelativePath) `
                -RepositoryRoot $script:RepoRoot `
                -Label 'synthetic 33-entry shard'
        } | Should -Throw
    }

    It 'rejects timeout progress that is not an exact worker-plan prefix' {
        $invalid = [pscustomobject][ordered]@{
            SchemaVersion                     = 2
            Phase                             = 'QualityWorker'
            ExpectedWorkerCount               = 28
            CompletedWorkerCount              = 1
            CompletedWorkerIds                = @('PowerShell7/X99')
            CompletedShardCount               = 1
            CompletedTestFileCount            = 1L
            CompletedPassedCount              = 1L
            CurrentEngine                     = 'PowerShell7'
            CurrentWorkerRole                 = 'PesterShard'
            CurrentShardId                    = 'C02'
            CurrentFailedCount                = 0L
            CurrentFailedTests                = @()
            CurrentFailedTestEvidenceTruncated = $false
            TimedOut                          = $true
        }
        { Assert-CddsiQualityFailureProgress -Progress $invalid } | Should -Throw

        $invalid.CompletedWorkerIds = @('PowerShell7/Static')
        $invalid.CompletedShardCount = 1
        { Assert-CddsiQualityFailureProgress -Progress $invalid } | Should -Throw

        $invalid.CompletedShardCount = 0
        $invalid.SchemaVersion = '1'
        { Assert-CddsiQualityFailureProgress -Progress $invalid } | Should -Throw
    }

    It 'keeps full safe diagnostics free of split surrogate pairs' {
        $paths = [ordered]@{ '<REPOSITORY_ROOT>' = 'C:\Synthetic Repo' }
        $headBoundary = ('h' * 116) + '😀' + ('m' * 200) + '𠮷' + ('t' * 200)
        $safe = Protect-CddsiHarnessText -Text $headBoundary -PathTokens $paths -MaximumLength 256
        $roundTrip = ([pscustomobject]@{ Text = $safe } | ConvertTo-Json -Compress) | ConvertFrom-Json
        $roundTrip.Text | Should -BeExactly $safe
        $roundTrip.Text | Should -Not -Match ([string][char]0xFFFD)
        for ($index = 0; $index -lt $safe.Length; $index++) {
            if ([char]::IsHighSurrogate($safe[$index])) {
                ($index + 1 -lt $safe.Length -and [char]::IsLowSurrogate($safe[$index + 1])) | Should -BeTrue
            }
            if ([char]::IsLowSurrogate($safe[$index])) {
                ($index -gt 0 -and [char]::IsHighSurrogate($safe[$index - 1])) | Should -BeTrue
            }
        }
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

    It 'accepts a complete historical Failed result with a non-assertion test error record' {
        $result = New-CddsiHistoricalPesterCompletionFixture
        $result.Tests[1].ErrorRecord[0].FullyQualifiedErrorId |
            Should -BeExactly 'SyntheticRuntimeFailure'
        $result.Tests[1].ErrorRecord[0].FullyQualifiedErrorId |
            Should -Not -BeExactly 'PesterAssertionFailed'

        (Test-CddsiHistoricalPesterCompletion -PesterResult $result) | Should -BeTrue
    }

    It 'rejects Passed and every incomplete historical Pester terminal state' {
        $passed = New-CddsiHistoricalPesterCompletionFixture
        $passed.Result = 'Passed'
        $passed.PassedCount = [long]2
        $passed.FailedCount = [long]0
        $passed.Tests[1].Result = 'Passed'
        $passed.Tests[1].ErrorRecord = @()
        (Test-CddsiHistoricalPesterCompletion -PesterResult $passed) | Should -BeFalse

        foreach ($countName in @('SkippedCount', 'NotRunCount', 'InconclusiveCount')) {
            $incomplete = New-CddsiHistoricalPesterCompletionFixture
            $incomplete.$countName = [long]1
            (Test-CddsiHistoricalPesterCompletion -PesterResult $incomplete) |
                Should -BeFalse -Because ($countName + ' must remain zero')
        }

        foreach ($countName in @('FailedBlocksCount', 'FailedContainersCount')) {
            $infrastructureFailure = New-CddsiHistoricalPesterCompletionFixture
            $infrastructureFailure.$countName = [long]1
            (Test-CddsiHistoricalPesterCompletion -PesterResult $infrastructureFailure) |
                Should -BeFalse -Because ($countName + ' is not a completed test-level failure')
        }
    }

    It 'rejects missing failed-test error evidence, count drift, and nonterminal test results' {
        $missingErrorRecord = New-CddsiHistoricalPesterCompletionFixture
        $missingErrorRecord.Tests[1].ErrorRecord = @()
        (Test-CddsiHistoricalPesterCompletion -PesterResult $missingErrorRecord) | Should -BeFalse

        $nullErrorRecord = New-CddsiHistoricalPesterCompletionFixture
        $nullErrorRecord.Tests[1].ErrorRecord = @($null)
        (Test-CddsiHistoricalPesterCompletion -PesterResult $nullErrorRecord) | Should -BeFalse

        $testCountDrift = New-CddsiHistoricalPesterCompletionFixture
        $testCountDrift.TotalCount = [long]3
        (Test-CddsiHistoricalPesterCompletion -PesterResult $testCountDrift) | Should -BeFalse

        $summaryCountDrift = New-CddsiHistoricalPesterCompletionFixture
        $summaryCountDrift.PassedCount = [long]2
        (Test-CddsiHistoricalPesterCompletion -PesterResult $summaryCountDrift) | Should -BeFalse

        $failedCountDrift = New-CddsiHistoricalPesterCompletionFixture
        $failedCountDrift.FailedCount = [long]2
        $failedCountDrift.PassedCount = [long]0
        (Test-CddsiHistoricalPesterCompletion -PesterResult $failedCountDrift) | Should -BeFalse

        $nonterminalTest = New-CddsiHistoricalPesterCompletionFixture
        $nonterminalTest.Tests[0].Result = 'Skipped'
        (Test-CddsiHistoricalPesterCompletion -PesterResult $nonterminalTest) | Should -BeFalse
    }

    It 'defaults QualitySet to AllBlocking and exposes only the three named sets' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:WorkerPath,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0

        $qualitySetParameters = @($ast.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -ceq 'QualitySet'
        })
        $qualitySetParameters.Count | Should -Be 1
        $qualitySet = $qualitySetParameters[0]
        $qualitySet.DefaultValue.SafeGetValue() | Should -BeExactly 'AllBlocking'
        $validateSet = @($qualitySet.Attributes | Where-Object {
            $_.TypeName.Name -ceq 'ValidateSet'
        })
        $validateSet.Count | Should -Be 1
        @($validateSet[0].PositionalArguments | ForEach-Object { $_.SafeGetValue() }) |
            Should -Be @('AllBlocking', 'ProductReleaseBlocking', 'HistoricalDiagnostic')
    }

    It 'keeps FAILED_TESTS evidence truthful and scoped only to HistoricalDiagnostic' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:WorkerPath,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0

        $historicalAssignments = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq '$historicalFailedCompletion'
        }, $true))
        $historicalAssignments.Count | Should -Be 1
        $historicalAssignments[0].Right.Extent.Text |
            Should -Match ([regex]::Escape('$QualitySet') + "\s+-ceq\s+'HistoricalDiagnostic'")
        $historicalAssignments[0].Right.Extent.Text |
            Should -Match 'Test-CddsiHistoricalPesterCompletion'

        $acceptanceAssignments = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq '$accepted'
        }, $true))
        $acceptanceAssignments.Count | Should -Be 1
        $acceptanceAssignments[0].Right.Extent.Text |
            Should -Match ([regex]::Escape('$cleanPester -or $historicalFailedCompletion'))

        $measurementAssignments = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq '$pesterMeasurement'
        }, $true))
        $measurementAssignments.Count | Should -Be 1
        $measurementAssignments[0].Right.Extent.Text |
            Should -Match ('Result\s*=\s*' + [regex]::Escape('[string]$result.Result'))

        $diagnosticBranches = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
                @($node.Clauses | Where-Object {
                    $_.Item1.Extent.Text.Trim() -ceq '$historicalFailedCompletion'
                }).Count -eq 1 -and
                $node.Extent.Text -match 'FAILED_TESTS'
        }, $true))
        $diagnosticBranches.Count | Should -Be 1
        $diagnosticBranches[0].Extent.Text | Should -Match '\[DIAGNOSTIC\]'
    }

    It 'preserves profile-bound shard completion evidence and rejects aggregate tampering' {
        $policy = Get-CddsiQualitySetPolicy `
            -RepositoryRoot $script:RepoRoot `
            -QualitySet ProductReleaseBlocking
        $aggregate = New-CddsiGateAggregateWorkerFixture `
            -Engine PowerShell7 `
            -QualitySetPolicy $policy

        $summary = Assert-CddsiGateWorkerEvidence `
            -WorkerEvidence $aggregate `
            -Engine PowerShell7 `
            -RunId ([string]$aggregate.RunId) `
            -QualitySetPolicy $policy `
            -RepositoryRoot $script:RepoRoot
        $summary.Result | Should -BeExactly 'Passed'
        $summary.TotalCount | Should -Be @($policy.QualityShards).Count
        $aggregate.Provenance.QualityShardPolicySha256 |
            Should -BeExactly $policy.CanonicalSha256
        @($aggregate.Measurements.ShardCompletionEvidence | ForEach-Object ShardId) |
            Should -Be @($policy.QualityShards | ForEach-Object ShardId)
        @($aggregate.Measurements.ShardCompletionEvidence | ForEach-Object ShardPathsSha256) |
            Should -Be @($policy.QualityShards | ForEach-Object PathsSha256)

        foreach ($tamper in @(
            [pscustomobject]@{ Target = 'Shard'; Name = 'PassedCount'; Value = -1L },
            [pscustomobject]@{ Target = 'Shard'; Name = 'TotalCount'; Value = 2L },
            [pscustomobject]@{ Target = 'Shard'; Name = 'FailedBlocksCount'; Value = 1L },
            [pscustomobject]@{ Target = 'Shard'; Name = 'FailedContainersCount'; Value = 1L },
            [pscustomobject]@{ Target = 'Shard'; Name = 'ShardPathsSha256'; Value = ('9' * 64 -join '') },
            [pscustomobject]@{ Target = 'Provenance'; Name = 'QualityShardPolicySha256'; Value = ('9' * 64 -join '') }
        )) {
            $tampered = ($aggregate | ConvertTo-Json -Depth 100) | ConvertFrom-Json
            if ($tamper.Target -ceq 'Shard') {
                $tampered.Measurements.ShardCompletionEvidence[0].($tamper.Name) = $tamper.Value
            }
            else {
                $tampered.Provenance.($tamper.Name) = $tamper.Value
            }
            {
                Assert-CddsiGateWorkerEvidence `
                    -WorkerEvidence $tampered `
                    -Engine PowerShell7 `
                    -RunId ([string]$tampered.RunId) `
                    -QualitySetPolicy $policy `
                    -RepositoryRoot $script:RepoRoot
            } | Should -Throw -Because ($tamper.Target + '.' + $tamper.Name + ' must fail closed')
        }
    }

    It 'keeps only complete historical test-level failure report-only in aggregate evidence' {
        $policy = Get-CddsiQualitySetPolicy `
            -RepositoryRoot $script:RepoRoot `
            -QualitySet HistoricalDiagnostic
        $failedTest = [pscustomobject][ordered]@{
            RelativePath     = 'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
            StartLine        = 2800L
            Name             = 'stages three distinct mocked keypairs with protected receipts and reuses the exact valid root idempotently'
            ErrorRecordCount = 1L
        }
        $aggregate = New-CddsiGateAggregateWorkerFixture `
            -Engine PowerShell7 `
            -QualitySetPolicy $policy `
            -FailedShardId H02 `
            -FailedTest $failedTest

        $summary = Assert-CddsiGateWorkerEvidence `
            -WorkerEvidence $aggregate `
            -Engine PowerShell7 `
            -RunId ([string]$aggregate.RunId) `
            -QualitySetPolicy $policy `
            -RepositoryRoot $script:RepoRoot
        $summary.Result | Should -BeExactly 'Failed'
        $summary.FailedCount | Should -Be 1
        $aggregate.Measurements.Pester.FailedBlocksCount | Should -Be 0
        $aggregate.Measurements.Pester.FailedContainersCount | Should -Be 0

        $infrastructureFailure = ($aggregate | ConvertTo-Json -Depth 100) | ConvertFrom-Json
        $h02 = @($infrastructureFailure.Measurements.ShardCompletionEvidence | Where-Object {
            [string]$_.ShardId -ceq 'H02'
        })[0]
        $h02.FailedBlocksCount = 1L
        {
            Assert-CddsiGateWorkerEvidence `
                -WorkerEvidence $infrastructureFailure `
                -Engine PowerShell7 `
                -RunId ([string]$infrastructureFailure.RunId) `
                -QualitySetPolicy $policy `
                -RepositoryRoot $script:RepoRoot
        } | Should -Throw
    }

    It 'requires source-bound failed-test summaries and one shared engine sandbox binding' {
        $failedTest = [pscustomobject][ordered]@{
            RelativePath    = 'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
            StartLine       = 2800L
            Name            = 'stages three distinct mocked keypairs with protected receipts and reuses the exact valid root idempotently'
            ErrorRecordCount = 1L
        }
        {
            Assert-CddsiGateFailedTestSummary `
                -FailedTests @($failedTest) `
                -FailedCount 1L `
                -Truncated $false `
                -AllowedRelativePaths @($failedTest.RelativePath) `
                -RepositoryRoot $script:RepoRoot `
                -Label 'synthetic shard'
        } | Should -Not -Throw

        foreach ($tamper in @(
            [pscustomobject]@{ Name = 'ErrorRecordCount'; Value = 0L },
            [pscustomobject]@{ Name = 'StartLine'; Value = -1L },
            [pscustomobject]@{ Name = 'Name'; Value = 'forged It name' }
        )) {
            $forged = $failedTest.PSObject.Copy()
            $forged.($tamper.Name) = $tamper.Value
            {
                Assert-CddsiGateFailedTestSummary `
                    -FailedTests @($forged) `
                    -FailedCount 1L `
                    -Truncated $false `
                    -AllowedRelativePaths @($failedTest.RelativePath) `
                    -RepositoryRoot $script:RepoRoot `
                    -Label 'synthetic shard'
            } | Should -Throw
        }

        $sharedBinding = ('8' * 64 -join '')
        {
            Assert-CddsiGateWorkerSandboxBinding -WorkerEvidence @(
                [pscustomobject]@{ SandboxBindingSha256 = $sharedBinding },
                [pscustomobject]@{ SandboxBindingSha256 = $sharedBinding }
            )
        } | Should -Not -Throw
        {
            Assert-CddsiGateWorkerSandboxBinding -WorkerEvidence @(
                [pscustomobject]@{ SandboxBindingSha256 = $sharedBinding },
                [pscustomobject]@{ SandboxBindingSha256 = ('9' * 64 -join '') }
            )
        } | Should -Throw
    }

    It 'fails closed on negative, total-drift, block, and container role evidence' {
        $ledger = New-HostSandboxTestLedger
        $sandbox = New-CddsiOwnedSandbox `
            -TempBase $TestDrive `
            -RunId '00000000-0000-0000-0000-000000000121' `
            -Ledger $ledger
        try {
            $policy = Get-CddsiQualitySetPolicy `
                -RepositoryRoot $script:RepoRoot `
                -QualitySet ProductReleaseBlocking
            $profileShard = @($policy.QualityShards | Where-Object {
                [string]$_.ShardId -ceq 'H01'
            })[0]
            $inventoryPath = Join-Path $sandbox.Paths.State 'role-reader-inventory.json'
            $inventory = [pscustomobject][ordered]@{
                SchemaVersion               = 1L
                RunId                       = [string]$sandbox.RunId
                RepositoryRootBindingSha256 = Get-CddsiSha256Text -Text (
                    [System.IO.Path]::GetFullPath($script:RepoRoot).TrimEnd('\').ToUpperInvariant())
                Paths                       = @('tests/HostSandbox/HostSandbox.Tests.ps1')
            }
            [System.IO.File]::WriteAllText(
                $inventoryPath,
                (($inventory | ConvertTo-Json -Depth 10) + "`n"),
                (New-Object System.Text.UTF8Encoding($false))
            )
            $inventoryMeasurement = Get-CddsiRepositoryInventoryMeasurement `
                -InventoryPath $inventoryPath `
                -RepositoryRoot $script:RepoRoot `
                -Sandbox $sandbox
            $grantSha256 = ('4' * 64 -join '')
            $descriptor = [pscustomobject][ordered]@{
                Engine     = 'PowerShell7'
                WorkerRole = 'PesterShard'
                ShardId    = 'H01'
                Grant      = [pscustomobject]@{ Sha256 = $grantSha256 }
                Leaf       = Get-CddsiWorkerEvidenceLeaf `
                    -Engine PowerShell7 `
                    -Role PesterShard `
                    -SelectedShardId H01
            }
            $dependencyPath = Join-Path $script:RepoRoot 'config\dev-dependencies.psd1'
            $dependency = Import-PowerShellDataFile -LiteralPath $dependencyPath
            $sameRepositoryManifestSha256 = [string]$inventoryMeasurement.ManifestSha256
            $roleEvidence = [pscustomobject][ordered]@{
                SchemaVersion         = 2L
                EvidenceType         = 'CddsiWorkerPesterShardEvidence'
                RunId                = [string]$sandbox.RunId
                Engine               = 'PowerShell7'
                ShardId              = 'H01'
                SandboxBindingSha256 = Get-CddsiSha256Text -Text (
                    [System.IO.Path]::GetFullPath($sandbox.Root).ToUpperInvariant())
                ShardPathsSha256     = [string]$profileShard.PathsSha256
                TestFiles            = [string[]]@($profileShard.Paths)
                Pester               = [pscustomobject][ordered]@{
                    Result                      = 'Passed'
                    TotalCount                  = 1L
                    PassedCount                 = 1L
                    FailedCount                 = 0L
                    FailedBlocksCount           = 0L
                    FailedContainersCount       = 0L
                    FailedTests                 = @()
                    FailedTestEvidenceTruncated = $false
                    SkippedCount                = 0L
                    NotRunCount                 = 0L
                    InconclusiveCount           = 0L
                    DurationMilliseconds        = 1L
                }
                RequiredSuiteResults = @()
                Provenance           = [pscustomobject][ordered]@{
                    MeasurementRuleVersion          = 'cddsi-worker-measurement-rules-v6'
                    RepositoryInventorySha256       = [string]$inventoryMeasurement.InventorySha256
                    InitialRepositoryManifestSha256 = $sameRepositoryManifestSha256
                    FinalRepositoryManifestSha256   = $sameRepositoryManifestSha256
                    DependencyManifestSha256        = (Get-FileHash -LiteralPath $dependencyPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    PesterTreeSha256                = [string]$dependency.Pester.ExpectedTreeSha256
                    EngineGrantSha256               = $grantSha256
                    QualityShardPolicySha256        = [string]$policy.CanonicalSha256
                }
            }
            $evidencePath = Join-Path $sandbox.Paths.Evidence $descriptor.Leaf
            $writeEvidence = {
                param($Value)
                [System.IO.File]::WriteAllText(
                    $evidencePath,
                    (($Value | ConvertTo-Json -Depth 100) + "`n"),
                    (New-Object System.Text.UTF8Encoding($false))
                )
            }
            & $writeEvidence $roleEvidence
            {
                Read-CddsiWorkerRoleEvidence `
                    -Descriptor $descriptor `
                    -Sandbox $sandbox `
                    -RepositoryRoot $script:RepoRoot `
                    -RepositoryInventoryPath $inventoryPath `
                    -BoundaryManifestPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1') `
                    -DependencyManifestPath $dependencyPath `
                    -QualityShardPolicy $policy `
                    -Ledger $ledger `
                    -ReadMode CleanCompletion
            } | Should -Not -Throw

            foreach ($tamper in @(
                [pscustomobject]@{ Name = 'TotalCount'; Value = -1L },
                [pscustomobject]@{ Name = 'TotalCount'; Value = 2L },
                [pscustomobject]@{ Name = 'FailedBlocksCount'; Value = 1L },
                [pscustomobject]@{ Name = 'FailedContainersCount'; Value = 1L }
            )) {
                $forged = ($roleEvidence | ConvertTo-Json -Depth 100) | ConvertFrom-Json
                $forged.Pester.($tamper.Name) = $tamper.Value
                & $writeEvidence $forged
                {
                    Read-CddsiWorkerRoleEvidence `
                        -Descriptor $descriptor `
                        -Sandbox $sandbox `
                        -RepositoryRoot $script:RepoRoot `
                        -RepositoryInventoryPath $inventoryPath `
                        -BoundaryManifestPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1') `
                        -DependencyManifestPath $dependencyPath `
                        -QualityShardPolicy $policy `
                        -Ledger $ledger `
                        -ReadMode CleanCompletion
                } | Should -Throw -Because ($tamper.Name + ' must fail closed')
            }
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
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

    It 'validates only canonical persisted ZIP timestamp representations' {
        $canonicalText = '1980-01-01T00:00:00Z'
        $canonicalUtc = [datetime]::SpecifyKind(
            [datetime]::ParseExact(
                '1980-01-01T00:00:00',
                'yyyy-MM-ddTHH:mm:ss',
                [Globalization.CultureInfo]::InvariantCulture
            ),
            [System.DateTimeKind]::Utc
        )
        $defaultRoundTrip = (
            ('{"ZipEntryTimestampUtc":"' + $canonicalText + '"}') |
                ConvertFrom-Json
        ).ZipEntryTimestampUtc

        (
            Test-CddsiGateCanonicalZipEntryTimestamp -Value $canonicalText
        ) | Should -BeTrue
        (
            Test-CddsiGateCanonicalZipEntryTimestamp -Value $canonicalUtc
        ) | Should -BeTrue
        (
            Test-CddsiGateCanonicalZipEntryTimestamp -Value $defaultRoundTrip
        ) | Should -BeTrue

        foreach ($rejected in @(
            '1980-01-01T00:00:00.0000000Z',
            '1980-01-01T00:00:00+00:00',
            '1980-01-01t00:00:00z',
            ' 1980-01-01T00:00:00Z',
            [datetime]::SpecifyKind(
                $canonicalUtc,
                [System.DateTimeKind]::Local
            ),
            [datetime]::SpecifyKind(
                $canonicalUtc,
                [System.DateTimeKind]::Unspecified
            ),
            $canonicalUtc.AddTicks(1),
            ([datetimeoffset]'1980-01-01T00:00:00Z'),
            624511296000000000L,
            [pscustomobject]@{ Ticks = 624511296000000000L },
            $null
        )) {
            (
                Test-CddsiGateCanonicalZipEntryTimestamp -Value $rejected
            ) | Should -BeFalse
        }

        if ($PSVersionTable.PSVersion.Major -ge 6) {
            $textHash = Get-CddsiGateCanonicalObjectSha256 -Value (
                [pscustomobject][ordered]@{
                    ZipEntryTimestampUtc = $canonicalText
                }
            )
            $roundTripHash = Get-CddsiGateCanonicalObjectSha256 -Value (
                [pscustomobject][ordered]@{
                    ZipEntryTimestampUtc = $defaultRoundTrip
                }
            )
            $roundTripHash | Should -BeExactly $textHash
        }
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
