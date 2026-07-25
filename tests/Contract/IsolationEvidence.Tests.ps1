BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\execution-context.ps1')
    . (Join-Path $script:RepoRoot 'lib\fake-providers.ps1')

    function New-IsolationEvidenceTestContext {
        param(
            [object[]]$ExpectedCalls = @(),

            [ValidateSet('TestSafe', 'DryRun')]
            [string]$Mode = 'TestSafe'
        )

        $root = 'C:\Evidence Tests\cddsi-test-00000000-0000-0000-0000-000000000003'
        $paths = [ordered]@{
            Home         = Join-Path $root 'profile'
            UserProfile  = Join-Path $root 'profile'
            LocalAppData = Join-Path $root 'local-app-data'
            AppData      = Join-Path $root 'app-data'
            ProgramData  = Join-Path $root 'program-data'
            Temp         = Join-Path $root 'temp'
            Download     = Join-Path $root 'download'
            State        = Join-Path $root 'state'
            Backup       = Join-Path $root 'backup'
            Report       = Join-Path $root 'report'
            Credential   = Join-Path $root 'credential'
            ConfigLibrary = Join-Path $root 'config-library'
            GitGlobalConfig = Join-Path $root 'git-global-config'
            XdgConfig    = Join-Path $root 'xdg-config'
            XdgData      = Join-Path $root 'xdg-data'
        }
        $policy = [ordered]@{
            SchemaVersion            = 1
            AllowLiveProvider        = $false
            ForbiddenResourceTokens = @('<CLAUDE_SETTINGS>', '<GIT_GLOBAL_CONFIG>')
            CanaryTokens             = @('<CANARY:CLAUDE_SETTINGS>', '<CANARY:GIT_CONFIG>')
        }
        return New-CddsiExecutionContext `
            -RunId '00000000-0000-0000-0000-000000000003' `
            -Mode $Mode `
            -Stage Scaffold `
            -EnvironmentTier HostSandbox `
            -SandboxRoot $root `
            -Paths $paths `
            -Providers (New-CddsiFakeProviderSet -ExpectedCalls $ExpectedCalls) `
            -Policy $policy
    }

    $script:WorkerGrantSha256 = ('1' * 64) -join ''
    . (Join-Path $script:RepoRoot 'scripts\check-worker.ps1') `
        -RepositoryRoot $script:RepoRoot `
        -SandboxRoot 'C:\Evidence Builder\cddsi-test-00000000-0000-0000-0000-000000000004' `
        -RunId '00000000-0000-0000-0000-000000000004' `
        -RepositoryInventoryPath 'C:\Evidence Builder\inventory.json' `
        -BoundaryManifestPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1') `
        -DependencyManifestPath (Join-Path $script:RepoRoot 'config\dev-dependencies.psd1') `
        -EngineId PowerShell7 `
        -EngineExecutablePath 'C:\Tools\pwsh.exe' `
        -EngineGrantSha256 $script:WorkerGrantSha256 `
        -GitExecutablePath 'C:\Tools\git.exe' `
        -GitGrantSha256 ('2' * 64) `
        -EvidenceBuilderOnly

    function New-WorkerEvidenceBuilderFixture {
        $suiteResults = @(
            [pscustomobject][ordered]@{
                RelativePath = 'tests/Contract/IsolationEvidence.Tests.ps1'
                TestCount = 18
                Result = 'Passed'
            }
        )
        $measurements = [pscustomobject][ordered]@{
            AstSyntaxErrorCount = 0
            LiveAdapterFileCount = 0
            SecretFindingCount = 0
            RepositoryContentChanged = $false
            LiveProviderLoaded = $false
            AccessLedger = [pscustomobject][ordered]@{
                ContextCount = 2
                TestSafeContextCount = 1
                DryRunContextCount = 1
                EntryCount = 2
                ForbiddenResourceAccessCount = 0
                OutsideSandboxWriteCount = 0
                ProductLiveProcessSpawnCount = 0
                ProductNetworkRequestCount = 0
                RealRegistryAccessCount = 0
                UnexpectedLedgerEntryCount = 0
            }
            MutationSpyCounts = [pscustomobject][ordered]@{
                FileSystem = 0
                Environment = 0
                Registry = 0
                Network = 0
                Process = 0
                AppX = 0
                Feature = 0
                Service = 0
                Credential = 0
                Restart = 0
            }
            Pester = [pscustomobject][ordered]@{
                Result = 'Passed'
                PassedCount = 11
                FailedCount = 0
                SkippedCount = 0
                NotRunCount = 0
                InconclusiveCount = 0
            }
            RequiredSuiteResults = $suiteResults
            RequiredSuiteFailureCount = 0
        }
        $sameRepositoryManifestSha256 = ('b' * 64) -join ''
        $provenance = [pscustomobject][ordered]@{
            MeasurementRuleVersion = 'cddsi-worker-measurement-rules-v6'
            RepositoryInventorySha256 = ('a' * 64) -join ''
            InitialRepositoryManifestSha256 = $sameRepositoryManifestSha256
            FinalRepositoryManifestSha256 = $sameRepositoryManifestSha256
            ExecutionBoundaryManifestSha256 = ('c' * 64) -join ''
            DependencyManifestSha256 = ('d' * 64) -join ''
            RequiredSuiteSummarySha256 = Get-CddsiWorkerRequiredSuiteSummarySha256 -SuiteResults $suiteResults
            PesterTreeSha256 = ('f' * 64) -join ''
            EngineGrantSha256 = $script:WorkerGrantSha256
        }
        return @{
            RunId = '00000000-0000-0000-0000-000000000004'
            Engine = 'PowerShell7'
            SandboxBindingSha256 = ('e' * 64) -join ''
            Measurements = $measurements
            Provenance = $provenance
            ExpectedEngineGrantSha256 = $script:WorkerGrantSha256
        }
    }
}

Describe 'P1 isolation evidence contract' {
    It 'accepts the exact AllBlocking classification independently of shard sequence order' {
        $dependency = Import-PowerShellDataFile -LiteralPath (
            Join-Path $script:RepoRoot 'config\dev-dependencies.psd1'
        )
        $repositoryFiles = @(
            $dependency.QualityShards |
                ForEach-Object { @($_.Paths) } |
                ForEach-Object {
                    [pscustomobject]@{ RelativePath = [string]$_ }
                }
        )

        $policy = Get-CddsiWorkerQualityShardPolicy `
            -RepositoryFiles $repositoryFiles `
            -SelectedShardId ''

        $policy.Profile.QualitySet | Should -BeExactly 'AllBlocking'
        @($policy.Profile.SelectedPesterPaths).Count | Should -Be 42
        @($policy.Shards).Count | Should -Be 13
    }

    It 'returns the original exact evidence field set with clean zero values' {
        $context = New-IsolationEvidenceTestContext
        $evidence = Get-CddsiIsolationEvidence -ExecutionContext $context
        @($evidence.PSObject.Properties.Name) | Should -Be @(
            'LIVE_PROVIDER_LOADED',
            'FORBIDDEN_RESOURCE_ACCESS_COUNT',
            'OUTSIDE_SANDBOX_WRITE_COUNT',
            'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
            'PRODUCT_NETWORK_REQUEST_COUNT',
            'REAL_REGISTRY_ACCESS_COUNT',
            'UNAPPROVED_HARNESS_PROCESS_COUNT',
            'UNAPPROVED_HARNESS_NETWORK_COUNT',
            'SECRET_FINDINGS',
            'UNEXPECTED_LEDGER_ENTRY_COUNT',
            'REPOSITORY_CONTENT_CHANGED'
        )
        $evidence.LIVE_PROVIDER_LOADED | Should -BeFalse
        $evidence.REPOSITORY_CONTENT_CHANGED | Should -BeFalse
        $evidence.UNEXPECTED_LEDGER_ENTRY_COUNT | Should -Be 0
        (Assert-CddsiIsolationEvidence -Evidence $evidence) | Should -BeTrue
    }

    It 'fails evidence when a forbidden product access was attempted' {
        $context = New-IsolationEvidenceTestContext
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Registry -Operation ReadValue -ResourceToken '<CLAUDE_SETTINGS>'
        } | Should -Throw
        $evidence = Get-CddsiIsolationEvidence -ExecutionContext $context
        $evidence.FORBIDDEN_RESOURCE_ACCESS_COUNT | Should -Be 1
        $evidence.UNEXPECTED_LEDGER_ENTRY_COUNT | Should -Be 1
        { Assert-CddsiIsolationEvidence -Evidence $evidence } | Should -Throw
    }

    It 'counts unconsumed exact expectations as unexpected evidence' {
        $expected = @(
            [pscustomobject]@{ Provider = 'Clock'; Operation = 'UtcNow'; ResourceToken = '<CLOCK:UTC>'; Result = '2030-01-01T00:00:00.0000000Z' }
        )
        $context = New-IsolationEvidenceTestContext -ExpectedCalls $expected
        $evidence = Get-CddsiIsolationEvidence -ExecutionContext $context
        $evidence.UNEXPECTED_LEDGER_ENTRY_COUNT | Should -Be 1
        { Assert-CddsiIsolationEvidence -Evidence $evidence } | Should -Throw
    }

    It 'preserves separate harness secret and repository evidence inputs' {
        $context = New-IsolationEvidenceTestContext
        $evidence = Get-CddsiIsolationEvidence `
            -ExecutionContext $context `
            -UnapprovedHarnessProcessCount 1 `
            -UnapprovedHarnessNetworkCount 2 `
            -SecretFindings 3 `
            -RepositoryContentChanged $true
        $evidence.UNAPPROVED_HARNESS_PROCESS_COUNT | Should -Be 1
        $evidence.UNAPPROVED_HARNESS_NETWORK_COUNT | Should -Be 2
        $evidence.SECRET_FINDINGS | Should -Be 3
        $evidence.REPOSITORY_CONTENT_CHANGED | Should -BeTrue
        { Assert-CddsiIsolationEvidence -Evidence $evidence } | Should -Throw
    }

    It 'rejects evidence with missing or extra fields' {
        $evidence = Get-CddsiIsolationEvidence -ExecutionContext (New-IsolationEvidenceTestContext)
        $evidence | Add-Member -NotePropertyName Extra -NotePropertyValue 0
        { Assert-CddsiIsolationEvidence -Evidence $evidence } | Should -Throw
    }

    It 'requires exact worker Measurements and Provenance fields with no missing defaults' {
        $missingFixture = New-WorkerEvidenceBuilderFixture
        $missingFixture.Measurements.PSObject.Properties.Remove('AstSyntaxErrorCount')
        { New-CddsiWorkerIsolationEvidenceV2 @missingFixture } | Should -Throw

        $extraFixture = New-WorkerEvidenceBuilderFixture
        $extraFixture.Provenance | Add-Member -NotePropertyName Extra -NotePropertyValue 0
        { New-CddsiWorkerIsolationEvidenceV2 @extraFixture } | Should -Throw
    }

    It 'propagates non-zero worker measurements without replacing them with clean constants' {
        $fixture = New-WorkerEvidenceBuilderFixture
        $fixture.Measurements.AstSyntaxErrorCount = 4
        $fixture.Measurements.LiveAdapterFileCount = 2
        $fixture.Measurements.SecretFindingCount = 3
        $fixture.Measurements.LiveProviderLoaded = $true
        $fixture.Measurements.AccessLedger.ForbiddenResourceAccessCount = 5
        $fixture.Measurements.AccessLedger.UnexpectedLedgerEntryCount = 6
        $fixture.Measurements.MutationSpyCounts.FileSystem = 7
        $fixture.Measurements.Pester.Result = 'Failed'
        $fixture.Measurements.Pester.FailedCount = 8
        $fixture.Measurements.RequiredSuiteResults[0].Result = 'Failed'
        $fixture.Measurements.RequiredSuiteFailureCount = 1
        $fixture.Provenance.RequiredSuiteSummarySha256 = Get-CddsiWorkerRequiredSuiteSummarySha256 -SuiteResults $fixture.Measurements.RequiredSuiteResults
        $fixture.Provenance.FinalRepositoryManifestSha256 = ('9' * 64) -join ''
        $fixture.Measurements.RepositoryContentChanged = $true

        $evidence = New-CddsiWorkerIsolationEvidenceV2 @fixture
        $evidence.Measurements.AstSyntaxErrorCount | Should -Be 4
        $evidence.Measurements.LiveAdapterFileCount | Should -Be 2
        $evidence.Measurements.SecretFindingCount | Should -Be 3
        $evidence.Measurements.LiveProviderLoaded | Should -BeTrue
        $evidence.Measurements.AccessLedger.ForbiddenResourceAccessCount | Should -Be 5
        $evidence.Measurements.AccessLedger.UnexpectedLedgerEntryCount | Should -Be 6
        $evidence.Measurements.MutationSpyCounts.FileSystem | Should -Be 7
        $evidence.Measurements.Pester.FailedCount | Should -Be 8
        $evidence.Measurements.RequiredSuiteFailureCount | Should -Be 1
        $evidence.Measurements.RepositoryContentChanged | Should -BeTrue
    }

    It 'rejects repository and required-suite hash binding drift' {
        $repositoryFixture = New-WorkerEvidenceBuilderFixture
        $repositoryFixture.Provenance.FinalRepositoryManifestSha256 = ('9' * 64) -join ''
        { New-CddsiWorkerIsolationEvidenceV2 @repositoryFixture } | Should -Throw

        $suiteFixture = New-WorkerEvidenceBuilderFixture
        $suiteFixture.Provenance.RequiredSuiteSummarySha256 = ('9' * 64) -join ''
        { New-CddsiWorkerIsolationEvidenceV2 @suiteFixture } | Should -Throw
    }

    It 'rejects an engine SHA that does not match the trusted grant' {
        $fixture = New-WorkerEvidenceBuilderFixture
        $fixture.ExpectedEngineGrantSha256 = ('2' * 64) -join ''
        { New-CddsiWorkerIsolationEvidenceV2 @fixture } | Should -Throw
    }

    It 'binds failed Pester tests to static repository source names and lines' {
        $relativePath = 'tests/Contract/IsolationEvidence.Tests.ps1'
        $fullPath = Join-Path $script:RepoRoot $relativePath
        $script:InitialRepositoryHashByPath[$relativePath] =
            (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $fullPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $testName = 'binds failed Pester tests to static repository source names and lines'
        $sourceCommands = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'It' -and
                $node.CommandElements.Count -ge 2 -and
                $node.CommandElements[1] -is
                    [Management.Automation.Language.StringConstantExpressionAst] -and
                [string]$node.CommandElements[1].Value -ceq $testName
        }, $true))
        $sourceCommands.Count | Should -Be 1
        $fakeResult = [pscustomobject]@{
            FailedCount = 1L
            Tests = @(
                [pscustomobject]@{
                    Result = 'Failed'
                    Name = $testName
                    ErrorRecord = @([pscustomobject]@{
                        FullyQualifiedErrorId = 'SyntheticFailure'
                    })
                    ScriptBlock = [pscustomobject]@{
                        File = $fullPath
                        StartPosition = [pscustomobject]@{
                            StartLine = [long]$sourceCommands[0].Extent.StartLineNumber
                        }
                    }
                }
            )
        }

        $failedTests = @(Get-CddsiWorkerFailedTestEvidence `
            -PesterResult $fakeResult `
            -AllowedRelativePaths @($relativePath))

        $failedTests.Count | Should -Be 1
        $failedTests[0].RelativePath | Should -BeExactly $relativePath
        $failedTests[0].StartLine | Should -Be $sourceCommands[0].Extent.StartLineNumber
        $failedTests[0].Name | Should -BeExactly $testName
        $failedTests[0].ErrorRecordCount | Should -Be 1
    }

    It 'validates every failed test through exact entry 33 without truncation' {
        $relativePath = 'tests/Contract/IsolationEvidence.Tests.ps1'
        $fullPath = Join-Path $script:RepoRoot $relativePath
        $script:InitialRepositoryHashByPath[$relativePath] =
            (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $fullPath, [ref]$tokens, [ref]$parseErrors)
        @($parseErrors).Count | Should -Be 0
        $testName = 'validates every failed test through exact entry 33 without truncation'
        $sourceCommands = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'It' -and
                $node.CommandElements.Count -ge 2 -and
                $node.CommandElements[1] -is
                    [Management.Automation.Language.StringConstantExpressionAst] -and
                [string]$node.CommandElements[1].Value -ceq $testName
        }, $true))
        $sourceCommands.Count | Should -Be 1

        $newFailedTest = {
            [pscustomobject]@{
                Result = 'Failed'
                Name = $testName
                ErrorRecord = @([pscustomobject]@{
                    FullyQualifiedErrorId = 'SyntheticFailure'
                })
                ScriptBlock = [pscustomobject]@{
                    File = $fullPath
                    StartPosition = [pscustomobject]@{
                        StartLine = [long]$sourceCommands[0].Extent.StartLineNumber
                    }
                }
            }
        }
        $completeTests = @(1..33 | ForEach-Object { & $newFailedTest })
        $completeResult = [pscustomobject]@{
            FailedCount = 33L
            Tests = $completeTests
        }
        $completeEvidence = @(Get-CddsiWorkerFailedTestEvidence `
            -PesterResult $completeResult `
            -AllowedRelativePaths @($relativePath))
        $completeEvidence.Count | Should -Be 33
        $completeEvidence[32].ErrorRecordCount | Should -Be 1

        $missingTests = @(1..33 | ForEach-Object { & $newFailedTest })
        $missingTests[32].PSObject.Properties.Remove('ErrorRecord')
        {
            Get-CddsiWorkerFailedTestEvidence `
                -PesterResult ([pscustomobject]@{
                    FailedCount = 33L
                    Tests = $missingTests
                }) `
                -AllowedRelativePaths @($relativePath)
        } | Should -Throw

        $nullTests = @(1..33 | ForEach-Object { & $newFailedTest })
        $nullTests[32].ErrorRecord = @($null)
        {
            Get-CddsiWorkerFailedTestEvidence `
                -PesterResult ([pscustomobject]@{
                    FailedCount = 33L
                    Tests = $nullTests
                }) `
                -AllowedRelativePaths @($relativePath)
        } | Should -Throw
    }

    It 'creates full schema version 2 shard failure evidence' {
        $testFiles = @('tests/HostSandbox/FastLaneGitOutbox.Tests.ps1')
        $failedTests = @(
            [pscustomobject][ordered]@{
                RelativePath = $testFiles[0]
                StartLine = 2800L
                Name = 'stages three distinct mocked keypairs with protected receipts and reuses the exact valid root idempotently'
                ErrorRecordCount = 1L
            }
        )
        $pester = [pscustomobject][ordered]@{
            Result = 'Failed'
            TotalCount = 23L
            PassedCount = 22L
            FailedCount = 1L
            FailedBlocksCount = 0L
            FailedContainersCount = 0L
            FailedTests = $failedTests
            FailedTestEvidenceTruncated = $false
            SkippedCount = 0L
            NotRunCount = 0L
            InconclusiveCount = 0L
            DurationMilliseconds = 1000L
        }
        $provenance = [pscustomobject][ordered]@{
            MeasurementRuleVersion = 'cddsi-worker-measurement-rules-v6'
            RepositoryInventorySha256 = ('a' * 64) -join ''
            InitialRepositoryManifestSha256 = ('b' * 64) -join ''
            FinalRepositoryManifestSha256 = ('b' * 64) -join ''
            DependencyManifestSha256 = ('c' * 64) -join ''
            PesterTreeSha256 = ('d' * 64) -join ''
            EngineGrantSha256 = $script:WorkerGrantSha256
            QualityShardPolicySha256 = ('e' * 64) -join ''
        }

        $evidence = New-CddsiWorkerPesterShardEvidenceV2 `
            -RunId '00000000-0000-0000-0000-000000000004' `
            -Engine PowerShell7 `
            -ShardId H02 `
            -SandboxBindingSha256 (('f' * 64) -join '') `
            -ShardPathsSha256 (Get-CddsiWorkerQualityShardPathsSha256 -Values $testFiles) `
            -TestFiles $testFiles `
            -Pester $pester `
            -Provenance $provenance `
            -ExpectedEngineGrantSha256 $script:WorkerGrantSha256

        $evidence.SchemaVersion | Should -Be 2
        $evidence.Pester.FailedCount | Should -Be 1
        $evidence.Pester.FailedTests[0].StartLine | Should -Be 2800
        $evidence.Pester.FailedTests[0].ErrorRecordCount | Should -Be 1
        $evidence.Pester.FailedTestEvidenceTruncated | Should -BeFalse

        $fullPester = $pester.PSObject.Copy()
        $fullPester.TotalCount = 55L
        $fullPester.FailedCount = 33L
        $fullPester.FailedTests = @(1..33 | ForEach-Object {
            $failedTests[0].PSObject.Copy()
        })
        $fullEvidence = New-CddsiWorkerPesterShardEvidenceV2 `
            -RunId '00000000-0000-0000-0000-000000000004' `
            -Engine PowerShell7 `
            -ShardId H02 `
            -SandboxBindingSha256 (('f' * 64) -join '') `
            -ShardPathsSha256 (Get-CddsiWorkerQualityShardPathsSha256 -Values $testFiles) `
            -TestFiles $testFiles `
            -Pester $fullPester `
            -Provenance $provenance `
            -ExpectedEngineGrantSha256 $script:WorkerGrantSha256
        @($fullEvidence.Pester.FailedTests).Count | Should -Be 33
        $fullEvidence.Pester.FailedTestEvidenceTruncated | Should -BeFalse

        $forbiddenTruncation = $fullPester.PSObject.Copy()
        $forbiddenTruncation.FailedTestEvidenceTruncated = $true
        {
            New-CddsiWorkerPesterShardEvidenceV2 `
                -RunId '00000000-0000-0000-0000-000000000004' `
                -Engine PowerShell7 `
                -ShardId H02 `
                -SandboxBindingSha256 (('f' * 64) -join '') `
                -ShardPathsSha256 (Get-CddsiWorkerQualityShardPathsSha256 -Values $testFiles) `
                -TestFiles $testFiles `
                -Pester $forbiddenTruncation `
                -Provenance $provenance `
                -ExpectedEngineGrantSha256 $script:WorkerGrantSha256
        } | Should -Throw

        {
            New-CddsiWorkerPesterShardEvidenceV2 `
                -RunId '00000000-0000-0000-0000-000000000004' `
                -Engine PowerShell7 `
                -ShardId H02 `
                -SandboxBindingSha256 (('f' * 64) -join '') `
                -ShardPathsSha256 (Get-CddsiWorkerSequenceSha256 -Values $testFiles) `
                -TestFiles $testFiles `
                -Pester $pester `
                -Provenance $provenance `
                -ExpectedEngineGrantSha256 $script:WorkerGrantSha256
        } | Should -Throw

        $negativeCount = $pester.PSObject.Copy()
        $negativeCount.TotalCount = -1L
        {
            New-CddsiWorkerPesterShardEvidenceV2 `
                -RunId '00000000-0000-0000-0000-000000000004' `
                -Engine PowerShell7 `
                -ShardId H02 `
                -SandboxBindingSha256 (('f' * 64) -join '') `
                -ShardPathsSha256 (Get-CddsiWorkerQualityShardPathsSha256 -Values $testFiles) `
                -TestFiles $testFiles `
                -Pester $negativeCount `
                -Provenance $provenance `
                -ExpectedEngineGrantSha256 $script:WorkerGrantSha256
        } | Should -Throw

        $totalDrift = $pester.PSObject.Copy()
        $totalDrift.TotalCount = 24L
        {
            New-CddsiWorkerPesterShardEvidenceV2 `
                -RunId '00000000-0000-0000-0000-000000000004' `
                -Engine PowerShell7 `
                -ShardId H02 `
                -SandboxBindingSha256 (('f' * 64) -join '') `
                -ShardPathsSha256 (Get-CddsiWorkerQualityShardPathsSha256 -Values $testFiles) `
                -TestFiles $testFiles `
                -Pester $totalDrift `
                -Provenance $provenance `
                -ExpectedEngineGrantSha256 $script:WorkerGrantSha256
        } | Should -Throw

        $missingErrorCount = $pester.PSObject.Copy()
        $missingFailedTest = $failedTests[0].PSObject.Copy()
        $missingFailedTest.PSObject.Properties.Remove('ErrorRecordCount')
        $missingErrorCount.FailedTests = @($missingFailedTest)
        {
            New-CddsiWorkerPesterShardEvidenceV2 `
                -RunId '00000000-0000-0000-0000-000000000004' `
                -Engine PowerShell7 `
                -ShardId H02 `
                -SandboxBindingSha256 (('f' * 64) -join '') `
                -ShardPathsSha256 (Get-CddsiWorkerQualityShardPathsSha256 -Values $testFiles) `
                -TestFiles $testFiles `
                -Pester $missingErrorCount `
                -Provenance $provenance `
                -ExpectedEngineGrantSha256 $script:WorkerGrantSha256
        } | Should -Throw
    }

    It 'aggregates actual TestSafe and DryRun ledger and mutation-spy records' {
        $testSafeCall = [pscustomobject]@{
            Provider = 'FileSystem'
            Operation = 'WriteFile'
            ResourceToken = '<SANDBOX_ROOT>/state'
            Arguments = [ordered]@{ Content = 'safe' }
            Result = $null
        }
        $dryRunCall = [pscustomobject]@{
            Provider = 'Registry'
            Operation = 'WriteValue'
            ResourceToken = '<SANDBOX_REGISTRY>/policy'
            Arguments = [ordered]@{ Value = 'safe' }
            Result = $null
        }
        $testSafeContext = New-IsolationEvidenceTestContext -Mode TestSafe -ExpectedCalls @($testSafeCall)
        $dryRunContext = New-IsolationEvidenceTestContext -Mode DryRun -ExpectedCalls @($dryRunCall)
        $null = Invoke-CddsiProviderOperation -Context $testSafeContext -Provider FileSystem -Operation WriteFile -ResourceToken '<SANDBOX_ROOT>/state' -Arguments ([ordered]@{ Content = 'safe' })
        $null = Invoke-CddsiProviderOperation -Context $dryRunContext -Provider Registry -Operation WriteValue -ResourceToken '<SANDBOX_REGISTRY>/policy' -Arguments ([ordered]@{ Value = 'safe' })
        {
            Invoke-CddsiProviderOperation -Context $dryRunContext -Provider Network -Operation Request -ResourceToken '<SANDBOX_NETWORK>/probe'
        } | Should -Throw

        $actual = Measure-CddsiWorkerExecutionContexts -Contexts @($testSafeContext, $dryRunContext)
        $actual.AccessLedger.ContextCount | Should -Be 2
        $actual.AccessLedger.TestSafeContextCount | Should -Be 1
        $actual.AccessLedger.DryRunContextCount | Should -Be 1
        $actual.AccessLedger.EntryCount | Should -Be 3
        $actual.AccessLedger.ForbiddenResourceAccessCount | Should -Be 1
        $actual.AccessLedger.UnexpectedLedgerEntryCount | Should -Be 3
        $actual.MutationSpyCounts.FileSystem | Should -Be 1
        $actual.MutationSpyCounts.Registry | Should -Be 1
    }

    It 'accepts arbitrary clean binary content in the worker stream scanner' {
        $bytes = [byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0x81, 0x7F)
        $stream = New-Object System.IO.MemoryStream(,$bytes)
        try {
            @(Find-CddsiWorkerStreamSecretFindings -Stream $stream -RelativePath 'assets/clean.png').Count | Should -Be 0
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'preserves the trusted ordinal repository inventory order for manifest hashing' {
        $originalRoot = $script:Root
        $originalSandboxRoot = $script:SandboxRoot
        $syntheticRoot = Join-Path $TestDrive 'ordinal-inventory'
        [System.IO.Directory]::CreateDirectory($syntheticRoot) | Out-Null
        [System.IO.File]::WriteAllText((Join-Path $syntheticRoot 'Z.txt'), 'upper', [System.Text.UTF8Encoding]::new($false))
        [System.IO.File]::WriteAllText((Join-Path $syntheticRoot 'a.txt'), 'lower', [System.Text.UTF8Encoding]::new($false))
        $inventoryPath = Join-Path $syntheticRoot 'inventory.json'
        $inventory = [pscustomobject][ordered]@{
            SchemaVersion               = 1
            RunId                       = '00000000-0000-0000-0000-000000000004'
            RepositoryRootBindingSha256 = Get-CddsiWorkerSha256Text -Text ([System.IO.Path]::GetFullPath($syntheticRoot).ToUpperInvariant())
            Paths                       = @('Z.txt', 'a.txt')
        }
        [System.IO.File]::WriteAllText($inventoryPath, (($inventory | ConvertTo-Json -Depth 4) + "`n"), [System.Text.UTF8Encoding]::new($false))

        try {
            $script:Root = [System.IO.Path]::GetFullPath($syntheticRoot).TrimEnd('\')
            $script:SandboxRoot = $script:Root
            $RepositoryInventoryPath = $inventoryPath
            @((Get-RepositoryFiles).RelativePath) | Should -Be @('Z.txt', 'a.txt')
        }
        finally {
            $script:Root = $originalRoot
            $script:SandboxRoot = $originalSandboxRoot
        }
    }

    It 'detects a synthetic key that crosses the worker scan chunk boundary' {
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
        $stream = New-Object System.IO.MemoryStream(,$payload)
        try {
            $findings = @(Find-CddsiWorkerStreamSecretFindings -Stream $stream -RelativePath 'assets/pseudo.png')
            $findings.Count | Should -Be 1
            $findings[0].Type | Should -BeExactly 'ApiKey'
            $findings[0].ByteOffset | Should -Be 65534
            ($findings | ConvertTo-Json -Depth 4) | Should -Not -Match [regex]::Escape($syntheticKey)
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'sanitizes terminal controls and bidi text before worker failure disclosure' {
        $syntheticKey = 'sk-' + ('q' * 32 -join '')
        $message = ([char]27) + '[31ms' + ([char]8) + $syntheticKey.Substring(1) + ([char]0x202E) + ([char]27) + '[0m'
        $safe = Protect-CheckMessage -Message $message
        $safe | Should -Match '\[REDACTED\]'
        $safe | Should -Not -Match [regex]::Escape($syntheticKey)
        $safe | Should -Not -Match '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F\u202A-\u202E]'
    }

    It 'separates Pester shards from static validation and monolithic test discovery' {
        $workerText = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot 'scripts\check-worker.ps1'))
        $shardBranch = $workerText.IndexOf("if (`$WorkerRole -ceq 'PesterShard') {", [StringComparison]::Ordinal)
        $staticStep = $workerText.IndexOf("Invoke-CheckStep -Name 'Execution files", [StringComparison]::Ordinal)
        $staticEvidence = $workerText.IndexOf('$staticEvidence = New-CddsiWorkerStaticEvidenceV1', [StringComparison]::Ordinal)
        $shardEvidence = $workerText.IndexOf('$shardEvidence = New-CddsiWorkerPesterShardEvidenceV2', [StringComparison]::Ordinal)

        $shardBranch | Should -BeGreaterOrEqual 0
        $shardEvidence | Should -BeGreaterThan $shardBranch
        $staticStep | Should -BeGreaterThan $shardEvidence
        $staticEvidence | Should -BeGreaterThan $staticStep
        $workerText | Should -Not -Match [regex]::Escape("Invoke-Pester -Path (Join-Path `$script:Root 'tests')")
        $workerText | Should -Match 'Invoke-Pester -Path \$selectedFullPaths'
    }

    It 'keeps the P1 core free from direct host I/O and dynamic scriptblock dispatch' {
        $files = @(
            Join-Path $script:RepoRoot 'lib\execution-context.ps1'
            Join-Path $script:RepoRoot 'lib\fake-providers.ps1'
        )
        $forbiddenCommands = @(
            'Test-Path', 'Get-Item', 'Get-ChildItem', 'Get-FileHash', 'Get-Date',
            'New-Item', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Set-Content', 'Add-Content', 'Out-File',
            'Start-Process', 'Stop-Process', 'Invoke-WebRequest', 'Invoke-RestMethod',
            'Get-ItemProperty', 'Set-ItemProperty', 'Get-AppxPackage', 'Add-AppxPackage',
            'Get-WindowsOptionalFeature', 'Enable-WindowsOptionalFeature', 'Get-Service', 'Start-Service',
            'Invoke-Expression', 'Add-Type'
        )
        $forbiddenTypes = @(
            'Environment', 'System.Environment', 'System.IO.File', 'System.IO.Directory',
            'Microsoft.Win32.Registry', 'Microsoft.Win32.RegistryKey',
            'System.Diagnostics.Process', 'System.Diagnostics.ProcessStartInfo',
            'System.Net.WebClient', 'System.Net.WebRequest', 'System.Net.Http.HttpClient'
        )
        foreach ($file in $files) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile($file, [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
            $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
            @($commands | Where-Object { $forbiddenCommands -ccontains $_ }).Count | Should -Be 0
            $types = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName })
            @($types | Where-Object { $forbiddenTypes -ccontains $_ }).Count | Should -Be 0
            $content = Get-Content -Raw -LiteralPath $file
            $content | Should -Not -Match '(?i)\.Invoke\s*\('
            $content | Should -Not -Match '(?m)&\s*\$'
            $content | Should -Not -Match '(?i)\[guid\]::NewGuid|\[DateTime\]::UtcNow'
        }
    }
}
