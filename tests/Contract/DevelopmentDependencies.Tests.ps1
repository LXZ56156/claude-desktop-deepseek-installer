BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BootstrapPath = Join-Path $script:RepoRoot 'scripts\bootstrap-dev.ps1'
    $script:DependencyManifestPath = Join-Path $script:RepoRoot 'config\dev-dependencies.psd1'
    $script:VendoredPesterRoot = Join-Path $script:RepoRoot '.dev\modules\Pester\5.6.1'
    $script:ProductReleaseGateRelativePath = 'config/product-release-gate.psd1'
    $script:QualitySetPolicyPath = Join-Path $script:RepoRoot 'scripts\quality-set-policy.ps1'
    . $script:BootstrapPath
    . $script:QualitySetPolicyPath
    $script:DependencyLock = Import-PowerShellDataFile -LiteralPath $script:DependencyManifestPath
    $script:ProductReleaseGate = Import-PowerShellDataFile -LiteralPath (
        Join-Path $script:RepoRoot $script:ProductReleaseGateRelativePath
    )
    $script:ReleaseManifest = Import-PowerShellDataFile -LiteralPath (
        Join-Path $script:RepoRoot 'scripts\release-manifest.psd1'
    )
    $script:ExecutionBoundary = Import-PowerShellDataFile -LiteralPath (
        Join-Path $script:RepoRoot 'config\execution-boundaries.psd1'
    )

    function New-CddsiVendoredPesterTestRepository {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Name
        )

        $testRepository = Join-Path $TestDrive $Name
        $targetParent = Join-Path $testRepository '.dev\modules\Pester'
        $licenseParent = Join-Path $testRepository 'third-party'
        [void](New-Item -ItemType Directory -Path $targetParent -Force)
        [void](New-Item -ItemType Directory -Path $licenseParent -Force)
        Copy-Item -LiteralPath $script:VendoredPesterRoot -Destination $targetParent -Recurse
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'third-party\Pester-5.6.1-LICENSE.txt') -Destination $licenseParent
        return $testRepository
    }

    function Copy-CddsiPesterLockForTest {
        $copy = @{}
        foreach ($key in $script:DependencyLock.Pester.Keys) { $copy[$key] = $script:DependencyLock.Pester[$key] }
        return $copy
    }

    function New-CddsiNamedGateSafeFailureJsonFixture {
        param(
            [ValidateRange(0, 1000)]
            [int]$FailedTestCount = 0,

            [ValidateRange(0, 480)]
            [int]$NamePaddingLength = 0
        )

        $failedTests = @(
            if ($FailedTestCount -gt 0) {
                foreach ($index in 1..$FailedTestCount) {
                    [pscustomobject][ordered]@{
                        RelativePath    = 'tests/Contract/Acceptance.Tests.ps1'
                        StartLine       = $index
                        Name            = (
                            'synthetic failure {0:D3} {1}' -f
                            $index,
                            ('x' * $NamePaddingLength)
                        )
                        ErrorRecordCount = 1
                    }
                }
            }
        )
        $hasPesterFailure = $failedTests.Count -gt 0
        $progress = [pscustomobject][ordered]@{
            SchemaVersion                      = 2
            Phase                              = if ($hasPesterFailure) {
                'QualityWorker'
            }
            else {
                'QualityHarness'
            }
            ExpectedWorkerCount                = if ($hasPesterFailure) {
                18
            }
            else {
                0
            }
            CompletedWorkerCount               = if ($hasPesterFailure) {
                1
            }
            else {
                0
            }
            CompletedWorkerIds                 = if ($hasPesterFailure) {
                @('PowerShell7/Static')
            }
            else {
                @()
            }
            CompletedShardCount                = 0
            CompletedTestFileCount             = 0L
            CompletedPassedCount               = 0L
            CurrentEngine                      = if ($hasPesterFailure) {
                'PowerShell7'
            }
            else {
                ''
            }
            CurrentWorkerRole                  = if ($hasPesterFailure) {
                'PesterShard'
            }
            else {
                ''
            }
            CurrentShardId                     = if ($hasPesterFailure) {
                'C01'
            }
            else {
                ''
            }
            CurrentFailedCount                 = [long]$failedTests.Count
            CurrentFailedTests                 = $failedTests
            CurrentFailedTestEvidenceTruncated = $false
            TimedOut                           = $false
        }
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion            = 3
            EvidenceType             = 'CddsiSafeFailureEvidence'
            Scenario                 = 'Quality'
            RunId                    = '95000000-0000-4000-8000-000000000001'
            Status                   = 'FAILED_SAFE'
            PrimaryFailureCode       = 'PESTER_ASSERTION_FAILURE'
            SafeFailureMessage       = 'Synthetic safe failure.'
            CleanupOutcome           = 'SucceededAfterFailure'
            CleanupFailureCode       = 'NONE'
            RepositoryContentChanged = $false
            Progress                 = $progress
            SafeFailureDisclosure    = $true
        }
        return ($evidence | ConvertTo-Json -Depth 100 -Compress)
    }
}

Describe 'vendored Pester development dependency' {
    It 'ships the complete Apache 2.0 license beside the development notice' {
        $noticePath = Join-Path $script:RepoRoot 'THIRD_PARTY_NOTICES.md'
        $licensePath = Join-Path $script:RepoRoot 'third-party\Pester-5.6.1-LICENSE.txt'

        (Test-Path -LiteralPath $noticePath -PathType Leaf) | Should -BeTrue
        (Test-Path -LiteralPath $licensePath -PathType Leaf) | Should -BeTrue
        $notice = [System.IO.File]::ReadAllText($noticePath)
        $license = [System.IO.File]::ReadAllText($licensePath)
        $notice | Should -Match ([regex]::Escape('third-party/Pester-5.6.1-LICENSE.txt'))
        $license | Should -Match 'Apache License'
        $license | Should -Match 'Version 2\.0, January 2004'
        $license | Should -Match 'END OF TERMS AND CONDITIONS'
    }

    It 'locks the exact Pester 5.6.1 tree and official provenance' {
        $pester = $script:DependencyLock.Pester
        @($pester.Keys | Sort-Object) | Should -Be @(
            'ExpectedFileCount', 'ExpectedLicenseBytes', 'ExpectedLicenseSha256', 'ExpectedManifestSha256',
            'ExpectedTotalBytes', 'ExpectedTreeSha256', 'LicenseRelativePath', 'ManifestRelativePath',
            'OfficialGalleryUrl', 'OfficialLicenseUrl', 'OfficialProjectUrl',
            'ProvenanceStatus', 'RootRelativePath', 'TreeHashFormat', 'Version'
        )
        $pester.Version | Should -BeExactly '5.6.1'
        $pester.ProvenanceStatus | Should -BeExactly 'VendoredPinnedTree'
        $pester.ExpectedFileCount | Should -Be 20
        $pester.ExpectedTotalBytes | Should -Be 1145990
        $pester.ExpectedManifestSha256 | Should -BeExactly '644e3dd029b4f2fdd7b99395446dcd7211d5a1027f51285759c2465e6df671aa'
        $pester.ExpectedTreeSha256 | Should -BeExactly 'b4992fea36787bda13b0301e2c459a03910ada99c73fd5b3ed9943470fd84460'
        $pester.LicenseRelativePath | Should -BeExactly 'third-party/Pester-5.6.1-LICENSE.txt'
        $pester.ExpectedLicenseBytes | Should -Be 11357
        $pester.ExpectedLicenseSha256 | Should -BeExactly 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
        $pester.OfficialGalleryUrl | Should -BeExactly 'https://www.powershellgallery.com/packages/Pester/5.6.1'
        $pester.OfficialProjectUrl | Should -BeExactly 'https://github.com/Pester/Pester'
        $pester.OfficialLicenseUrl | Should -BeExactly 'https://www.apache.org/licenses/LICENSE-2.0.html'
    }

    It 'freezes an exact ordinal shard partition over every repository test file' {
        @($script:DependencyLock.Keys | Sort-Object) | Should -Be @(
            'IsolationEvidenceSuites', 'Pester', 'QualityShards', 'SchemaVersion'
        )
        $shards = @($script:DependencyLock.QualityShards)
        @($shards.ShardId) | Should -Be @(
            'C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08',
            'U01', 'U02', 'H01', 'H02', 'H03'
        )
        $listed = New-Object System.Collections.Generic.List[string]
        foreach ($shard in $shards) {
            @($shard.Keys | Sort-Object) | Should -Be @('Paths', 'ShardId')
            [string]$shard.ShardId | Should -Match '^[CHU][0-9]{2}$'
            $paths = [string[]]@($shard.Paths)
            $ordinal = [string[]]$paths.Clone()
            [Array]::Sort($ordinal, [StringComparer]::Ordinal)
            ($paths -join "`n") | Should -BeExactly ($ordinal -join "`n")
            foreach ($path in $paths) {
                $path | Should -Match '^tests/(?:Contract|HostSandbox|Unit)/[^/]+\.Tests\.ps1$'
                [System.IO.Path]::IsPathRooted($path) | Should -BeFalse
                @($path.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count | Should -Be 0
                $listed.Add($path)
            }
        }
        $listedArray = [string[]]$listed.ToArray()
        $listedOrdinal = [string[]]$listedArray.Clone()
        [Array]::Sort($listedOrdinal, [StringComparer]::Ordinal)
        $actual = [string[]]@(
            Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'tests') -Recurse -Filter '*.Tests.ps1' -File |
                ForEach-Object { $_.FullName.Substring($script:RepoRoot.Length + 1).Replace('\', '/') }
        )
        [Array]::Sort($actual, [StringComparer]::Ordinal)
        $listedArray.Count | Should -Be 42
        @($listedArray | Sort-Object -Unique).Count | Should -Be 42
        ($listedOrdinal -join "`n") | Should -BeExactly ($actual -join "`n")
    }

    It 'keeps bootstrap verify-only with no network module installation import or writes' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:BootstrapPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        @($ast.ParamBlock.Parameters).Count | Should -Be 0

        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        foreach ($forbiddenCommand in @(
            'Import-Module', 'Save-Module', 'Install-Module', 'Update-Module',
            'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer',
            'New-Item', 'Remove-Item', 'Copy-Item', 'Move-Item', 'Set-Content', 'Add-Content', 'Out-File',
            'Start-Process', 'Invoke-Expression'
        )) {
            $commands | Should -Not -Contain $forbiddenCommand
        }
        @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand }, $true)).Count | Should -Be 0

        $types = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName })
        @($types | Where-Object { $_ -eq 'System.IO.File' -or $_ -eq 'System.IO.Directory' -or $_ -eq 'System.IO.FileStream' -or $_ -like 'System.Net.*' }).Count | Should -Be 0
    }

    It 'verifies the repository tree without importing Pester' {
        $result = Assert-CddsiVendoredPesterTree -RepositoryRoot $script:RepoRoot -DependencyLock $script:DependencyLock
        $result.PSObject.Properties.Name | Should -Be @(
            'Dependency', 'Version', 'ProvenanceStatus', 'RootRelativePath',
            'FileCount', 'TotalBytes', 'ManifestSha256', 'TreeSha256', 'LicenseSha256'
        )
        $result.FileCount | Should -Be 20
        $result.TotalBytes | Should -Be 1145990
        $result.LicenseSha256 | Should -BeExactly $script:DependencyLock.Pester.ExpectedLicenseSha256
    }

    It 'rejects a changed local Apache license' {
        $testRepository = New-CddsiVendoredPesterTestRepository -Name 'changed-license'
        [System.IO.File]::AppendAllText((Join-Path $testRepository 'third-party\Pester-5.6.1-LICENSE.txt'), 'changed')

        { Assert-CddsiVendoredPesterTree -RepositoryRoot $testRepository -DependencyLock $script:DependencyLock } | Should -Throw
    }

    It 'accepts an exact TestDrive copy and rejects an extra package metadata file' {
        $testRepository = New-CddsiVendoredPesterTestRepository -Name 'exact-tree'
        (Assert-CddsiVendoredPesterTree -RepositoryRoot $testRepository -DependencyLock $script:DependencyLock).TreeSha256 | Should -BeExactly $script:DependencyLock.Pester.ExpectedTreeSha256

        $unexpectedPath = Join-Path $testRepository '.dev\modules\Pester\5.6.1\PSGetModuleInfo.xml'
        Set-Content -LiteralPath $unexpectedPath -Value '<synthetic />' -Encoding UTF8
        { Assert-CddsiVendoredPesterTree -RepositoryRoot $testRepository -DependencyLock $script:DependencyLock } | Should -Throw
    }

    It 'rejects an escaping lock path before reading outside the synthetic repository' {
        $testRepository = New-CddsiVendoredPesterTestRepository -Name 'unsafe-lock'
        $unsafePester = Copy-CddsiPesterLockForTest
        $unsafePester.RootRelativePath = '../outside'
        $unsafeLock = [ordered]@{
            SchemaVersion            = 1
            Pester                  = $unsafePester
            IsolationEvidenceSuites = $script:DependencyLock.IsolationEvidenceSuites
            QualityShards           = $script:DependencyLock.QualityShards
        }

        { Assert-CddsiVendoredPesterTree -RepositoryRoot $testRepository -DependencyLock $unsafeLock } | Should -Throw
    }

    It 'fails safely when the tracked tree is missing and does not disclose its absolute path' {
        $missingRepository = Join-Path $TestDrive 'missing-tree'
        [void](New-Item -ItemType Directory -Path $missingRepository)
        $message = ''
        try {
            $null = Assert-CddsiVendoredPesterTree -RepositoryRoot $missingRepository -DependencyLock $script:DependencyLock
            throw 'Expected missing vendored tree verification to fail.'
        }
        catch {
            $message = $_.Exception.Message
        }
        $message | Should -Match 'Restore the tracked .dev/modules/Pester/5.6.1 tree'
        $message | Should -Not -Match ([regex]::Escape($missingRepository))
    }

    It 'tracks only the locked files as raw bytes and leaves package metadata ignored' {
        $ignoreLines = @(Get-Content -LiteralPath (Join-Path $script:RepoRoot '.gitignore'))
        $trackedPrefix = '!.dev/modules/Pester/5.6.1/'
        $unignoredFiles = @($ignoreLines | Where-Object { $_.StartsWith($trackedPrefix, [StringComparison]::Ordinal) -and -not $_.EndsWith('/', [StringComparison]::Ordinal) } | ForEach-Object { $_.Substring($trackedPrefix.Length) } | Sort-Object)
        $lockedFiles = @(Get-ChildItem -LiteralPath $script:VendoredPesterRoot -File -Recurse | ForEach-Object { $_.FullName.Substring($script:VendoredPesterRoot.Length + 1).Replace('\', '/') } | Sort-Object)
        ($unignoredFiles -join "`n") | Should -BeExactly ($lockedFiles -join "`n")
        $ignoreLines | Should -Contain '.dev/modules/Pester/**/PSGetModuleInfo.xml'

        $attributeLines = @(Get-Content -LiteralPath (Join-Path $script:RepoRoot '.gitattributes'))
        $rawTreeRule = '/.dev/modules/Pester/5.6.1/** -text -diff'
        $rawTreeIndex = [Array]::IndexOf($attributeLines, $rawTreeRule)
        $powerShellRuleIndex = [Array]::IndexOf($attributeLines, '*.ps1 text eol=crlf whitespace=trailing-space,space-before-tab,cr-at-eol')
        $rawTreeIndex | Should -BeGreaterThan $powerShellRuleIndex
    }
}

Describe 'D-026 product release gate classification inventory' {
    It 'activates the exact named product release gate schema' {
        $policy = $script:ProductReleaseGate
        (@($policy.Keys | Sort-Object) -join ',') | Should -BeExactly (
            'ContractVersion,EnforcementPhase,HistoricalDiagnosticFiles,' +
            'ProductReleaseBlockingFiles,SchemaVersion,Scope'
        )
        (($policy.SchemaVersion -is [int]) -or ($policy.SchemaVersion -is [long])) | Should -BeTrue
        [long]$policy.SchemaVersion | Should -Be 1
        [string]$policy.ContractVersion | Should -BeExactly 'D-026'
        [string]$policy.EnforcementPhase | Should -BeExactly 'NamedProductReleaseGate'

        (@($policy.Scope.Keys | Sort-Object) -join ',') | Should -BeExactly (
            'ExpectedPesterTestCount,ExpectedTrackedFileCount,PathComparison,RootRelativePath'
        )
        [string]$policy.Scope.RootRelativePath | Should -BeExactly 'tests'
        [string]$policy.Scope.PathComparison | Should -BeExactly 'Ordinal'
        [long]$policy.Scope.ExpectedTrackedFileCount | Should -Be 47
        [long]$policy.Scope.ExpectedPesterTestCount | Should -Be 42

        $relativePath = $script:ProductReleaseGateRelativePath
        $owners = @(
            $script:ExecutionBoundary.Planes.Keys |
                Where-Object {
                    @($script:ExecutionBoundary.Planes[[string]$_]) -ccontains $relativePath
                }
        )
        $owners.Count | Should -Be 1
        [string]$owners[0] | Should -BeExactly 'PolicyData'
        @(
            $script:ReleaseManifest.PackageFiles |
                Where-Object { [string]$_ -ceq $relativePath }
        ).Count | Should -Be 0
        @(
            $script:ReleaseManifest.DevelopmentOnlyFiles |
                Where-Object { [string]$_ -ceq $relativePath }
        ).Count | Should -Be 1

        $checkText = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'scripts\check.ps1'))
        $hostText = [IO.File]::ReadAllText((Join-Path $script:RepoRoot 'scripts\invoke-host-sandbox.ps1'))
        $checkText.IndexOf('-Scenario Quality', [StringComparison]::Ordinal) |
            Should -BeGreaterOrEqual 0
        $hostText.IndexOf("[ValidateSet('Quality')]", [StringComparison]::Ordinal) |
            Should -BeGreaterOrEqual 0
    }

    It 'partitions the exact release-manifest test inventory with safe ordinal paths' {
        $policy = $script:ProductReleaseGate
        $productEntries = @($policy.ProductReleaseBlockingFiles)
        $historicalEntries = @($policy.HistoricalDiagnosticFiles)
        $productEntries.Count | Should -Be 34
        $historicalEntries.Count | Should -Be 13

        foreach ($entries in @(
            [pscustomobject]@{ Name = 'Product'; Value = $productEntries },
            [pscustomobject]@{ Name = 'Historical'; Value = $historicalEntries }
        )) {
            $paths = [string[]]@(
                $entries.Value | ForEach-Object { [string]$_.RelativePath }
            )
            $ordinalPaths = [string[]]$paths.Clone()
            [Array]::Sort($ordinalPaths, [StringComparer]::Ordinal)
            ($paths -join "`n") | Should -BeExactly ($ordinalPaths -join "`n")
        }

        $allEntries = @($productEntries + $historicalEntries)
        $classifiedPaths = [string[]]@(
            $allEntries | ForEach-Object { [string]$_.RelativePath }
        )
        $ordinalSet = New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::Ordinal
        )
        $caseFoldedSet = New-Object 'System.Collections.Generic.HashSet[string]' (
            [StringComparer]::OrdinalIgnoreCase
        )
        foreach ($entry in $allEntries) {
            ($entry -is [System.Collections.IDictionary]) | Should -BeTrue
            (@($entry.Keys | Sort-Object) -join ',') |
                Should -BeExactly 'FileKind,ReasonCode,RelativePath'

            $relativePath = [string]$entry.RelativePath
            [string]::IsNullOrWhiteSpace($relativePath) | Should -BeFalse
            $relativePath.StartsWith('tests/', [StringComparison]::Ordinal) | Should -BeTrue
            [IO.Path]::IsPathRooted($relativePath) | Should -BeFalse
            $relativePath | Should -Not -Match '[\\:*?"<>|\x00-\x1f]'
            @($relativePath.Split('/') | Where-Object { $_ -in @('', '.', '..') }).Count |
                Should -Be 0
            $ordinalSet.Add($relativePath) | Should -BeTrue
            $caseFoldedSet.Add($relativePath) | Should -BeTrue

            $currentPath = $script:RepoRoot
            foreach ($segment in $relativePath.Split('/')) {
                $currentPath = Join-Path $currentPath $segment
                (Test-Path -LiteralPath $currentPath) | Should -BeTrue
                $item = Get-Item -LiteralPath $currentPath -Force
                (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) |
                    Should -BeFalse
            }
            (Test-Path -LiteralPath $currentPath -PathType Leaf) | Should -BeTrue
        }

        [Array]::Sort($classifiedPaths, [StringComparer]::Ordinal)
        $manifestFiles = [string[]]@(
            @($script:ReleaseManifest.PackageFiles) +
            @($script:ReleaseManifest.DevelopmentOnlyFiles)
        )
        @(
            $script:ReleaseManifest.PackageFiles |
                Where-Object { ([string]$_).StartsWith('tests/', [StringComparison]::Ordinal) }
        ).Count | Should -Be 0
        $canonicalPaths = [string[]]@(
            $manifestFiles |
                Where-Object { ([string]$_).StartsWith('tests/', [StringComparison]::Ordinal) }
        )
        [Array]::Sort($canonicalPaths, [StringComparer]::Ordinal)
        $canonicalPaths.Count | Should -Be 47
        ($classifiedPaths -join "`n") | Should -BeExactly ($canonicalPaths -join "`n")
    }

    It 'uses exact current-product metadata for all product files' {
        $entries = @($script:ProductReleaseGate.ProductReleaseBlockingFiles)
        $reasonByKind = @{
            PesterTest      = 'CurrentProductReleaseTest'
            SyntheticFixture = 'CurrentProductSyntheticFixture'
            SupportScript   = 'CurrentProductSupportScript'
        }
        foreach ($entry in $entries) {
            $kind = [string]$entry.FileKind
            $relativePath = [string]$entry.RelativePath
            ($reasonByKind.ContainsKey($kind)) | Should -BeTrue
            [string]$entry.ReasonCode | Should -BeExactly ([string]$reasonByKind[$kind])
            if ($kind -ceq 'PesterTest') {
                $relativePath.EndsWith('.Tests.ps1', [StringComparison]::Ordinal) |
                    Should -BeTrue
            }
            elseif ($kind -ceq 'SyntheticFixture') {
                $relativePath.StartsWith('tests/Fixtures/', [StringComparison]::Ordinal) |
                    Should -BeTrue
                $relativePath.EndsWith('.json', [StringComparison]::Ordinal) | Should -BeTrue
            }
            else {
                $relativePath | Should -BeExactly 'tests/Support/TestContext.ps1'
            }
        }
        @($entries | Where-Object { $_.FileKind -ceq 'PesterTest' }).Count | Should -Be 29
        @($entries | Where-Object { $_.FileKind -ceq 'SyntheticFixture' }).Count |
            Should -Be 4
        @($entries | Where-Object { $_.FileKind -ceq 'SupportScript' }).Count | Should -Be 1
    }

    It 'freezes the exact retired historical allowlist and rationale' {
        $expectedLines = @(
            'tests/Contract/FastLanePolicy.Tests.ps1|PesterTest|RetiredFastLaneTransport'
            'tests/Contract/FastLaneReadiness.Tests.ps1|PesterTest|RetiredFastLaneTransport'
            'tests/Contract/RealtimeRelay.Tests.ps1|PesterTest|RetiredRealtimeRelayTransport'
            'tests/Contract/RealtimeRelayForegroundControl.Tests.ps1|PesterTest|RetiredRealtimeRelayTransport'
            'tests/Contract/RealtimeRelayForegroundCycle.Tests.ps1|PesterTest|RetiredRealtimeRelayTransport'
            'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1|PesterTest|RetiredRealtimeRelayTransport'
            'tests/Contract/VmReset.Tests.ps1|PesterTest|RetiredVmRelayResetControl'
            'tests/Contract/VmResetLiveAdapter.Tests.ps1|PesterTest|RetiredVmRelayResetControl'
            'tests/Contract/WindowsVmResetProvider.Tests.ps1|PesterTest|RetiredVmRelayResetControl'
            'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1|PesterTest|RetiredFastLaneTransport'
            'tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1|PesterTest|RetiredFastLaneTransport'
            'tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1|PesterTest|RetiredFastLaneTransport'
            'tests/Unit/VmTestRelay.Tests.ps1|PesterTest|RetiredVmRelayResetControl'
        )
        $entries = @($script:ProductReleaseGate.HistoricalDiagnosticFiles)
        $actualLines = @(
            $entries | ForEach-Object {
                '{0}|{1}|{2}' -f $_.RelativePath, $_.FileKind, $_.ReasonCode
            }
        )
        ($actualLines -join "`n") | Should -BeExactly ($expectedLines -join "`n")
        @($entries | Where-Object { $_.ReasonCode -ceq 'RetiredFastLaneTransport' }).Count |
            Should -Be 5
        @(
            $entries |
                Where-Object { $_.ReasonCode -ceq 'RetiredRealtimeRelayTransport' }
        ).Count | Should -Be 4
        @(
            $entries |
                Where-Object { $_.ReasonCode -ceq 'RetiredVmRelayResetControl' }
        ).Count | Should -Be 4
    }

    It 'binds all Pester entries to QualityShards and keeps safety gates in Product' {
        $productEntries = @($script:ProductReleaseGate.ProductReleaseBlockingFiles)
        $historicalEntries = @($script:ProductReleaseGate.HistoricalDiagnosticFiles)
        $productPesterPaths = [string[]]@(
            $productEntries |
                Where-Object { $_.FileKind -ceq 'PesterTest' } |
                ForEach-Object { [string]$_.RelativePath }
        )
        $historicalPesterPaths = [string[]]@(
            $historicalEntries |
                Where-Object { $_.FileKind -ceq 'PesterTest' } |
                ForEach-Object { [string]$_.RelativePath }
        )
        $classifiedPesterPaths = [string[]]@($productPesterPaths + $historicalPesterPaths)
        $shardPaths = [string[]]@(
            $script:DependencyLock.QualityShards |
                ForEach-Object { @($_.Paths) } |
                ForEach-Object { [string]$_ }
        )
        [Array]::Sort($classifiedPesterPaths, [StringComparer]::Ordinal)
        [Array]::Sort($shardPaths, [StringComparer]::Ordinal)
        $productPesterPaths.Count | Should -Be 29
        $historicalPesterPaths.Count | Should -Be 13
        $classifiedPesterPaths.Count | Should -Be 42
        ($classifiedPesterPaths -join "`n") | Should -BeExactly ($shardPaths -join "`n")

        $productPaths = @(
            $productEntries | ForEach-Object { [string]$_.RelativePath }
        )
        foreach ($requiredProductPath in @(
            'tests/Contract/DevelopmentDependencies.Tests.ps1'
            'tests/Contract/IsolationEvidence.Tests.ps1'
            'tests/Contract/OperatorCoordinationBoundary.Tests.ps1'
            'tests/Contract/ReleaseArtifact.Tests.ps1'
            'tests/Contract/ReleaseFacts.Tests.ps1'
            'tests/Contract/VmCalibration.Tests.ps1'
            'tests/HostSandbox/CandidateBuild.Tests.ps1'
            'tests/HostSandbox/HostSandbox.Tests.ps1'
            'tests/HostSandbox/ReleaseSimulation.Tests.ps1'
        )) {
            @($productPaths | Where-Object { $_ -ceq $requiredProductPath }).Count |
                Should -Be 1
        }
    }
}

Describe 'D-026 fail-closed quality-set policy profiles' {
    It 'derives three exact stable and distinct execution profiles from the classified inventory' {
        $expectedPropertyNames = @(
            'SchemaVersion'
            'ContractVersion'
            'QualitySet'
            'AssertionFailureDisposition'
            'ClassificationManifestSha256'
            'DependencyManifestSha256'
            'CanonicalSha256'
            'SelectedFilePathsSha256'
            'SelectedPesterPathsSha256'
            'SelectedShardPolicySha256'
            'SelectedFilePaths'
            'SelectedPesterPaths'
            'QualityShards'
            'FileCount'
            'PesterFileCount'
            'ShardCount'
            'WorkerCount'
            'ProcessCount'
            'LedgerEntryCount'
        )
        $expectations = @(
            [pscustomobject]@{
                QualitySet = 'AllBlocking'
                Disposition = 'Blocking'
                FileCount = 42
                ShardIds = @(
                    'C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08',
                    'U01', 'U02', 'H01', 'H02', 'H03'
                )
                WorkerCount = 28
                ProcessCount = 31
                LedgerEntryCount = 68
            }
            [pscustomobject]@{
                QualitySet = 'ProductReleaseBlocking'
                Disposition = 'Blocking'
                FileCount = 29
                ShardIds = @('C01', 'C02', 'C03', 'C04', 'C05', 'U01', 'U02', 'H01')
                WorkerCount = 18
                ProcessCount = 21
                LedgerEntryCount = 48
            }
            [pscustomobject]@{
                QualitySet = 'HistoricalDiagnostic'
                Disposition = 'ReportOnlyAfterCompleteTestFailure'
                FileCount = 13
                ShardIds = @(
                    'C04', 'C05', 'C06', 'C07', 'C08', 'U02', 'H01', 'H02', 'H03'
                )
                WorkerCount = 20
                ProcessCount = 23
                LedgerEntryCount = 52
            }
        )

        $classificationSha256 = (
            Get-FileHash -LiteralPath (
                Join-Path $script:RepoRoot $script:ProductReleaseGateRelativePath
            ) -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $dependencySha256 = (
            Get-FileHash -LiteralPath $script:DependencyManifestPath -Algorithm SHA256
        ).Hash.ToLowerInvariant()
        $profiles = @{}

        foreach ($expectation in $expectations) {
            $qualityProfile = Get-CddsiQualitySetPolicy `
                -RepositoryRoot $script:RepoRoot `
                -QualitySet $expectation.QualitySet
            $repeat = Get-CddsiQualitySetPolicy `
                -RepositoryRoot $script:RepoRoot `
                -QualitySet $expectation.QualitySet
            $profiles[$expectation.QualitySet] = $qualityProfile

            ($qualityProfile.PSObject.Properties.Name -join "`n") |
                Should -BeExactly ($expectedPropertyNames -join "`n")
            [long]$qualityProfile.SchemaVersion | Should -Be 1
            [string]$qualityProfile.ContractVersion | Should -BeExactly 'D-026'
            [string]$qualityProfile.QualitySet | Should -BeExactly $expectation.QualitySet
            [string]$qualityProfile.AssertionFailureDisposition |
                Should -BeExactly $expectation.Disposition
            [long]$qualityProfile.FileCount | Should -Be $expectation.FileCount
            [long]$qualityProfile.PesterFileCount | Should -Be $expectation.FileCount
            [long]$qualityProfile.ShardCount | Should -Be $expectation.ShardIds.Count
            [long]$qualityProfile.WorkerCount | Should -Be $expectation.WorkerCount
            [long]$qualityProfile.ProcessCount | Should -Be $expectation.ProcessCount
            [long]$qualityProfile.LedgerEntryCount | Should -Be $expectation.LedgerEntryCount
            [string]$qualityProfile.ClassificationManifestSha256 |
                Should -BeExactly $classificationSha256
            [string]$qualityProfile.DependencyManifestSha256 |
                Should -BeExactly $dependencySha256

            foreach ($hashName in @(
                'ClassificationManifestSha256'
                'DependencyManifestSha256'
                'CanonicalSha256'
                'SelectedFilePathsSha256'
                'SelectedPesterPathsSha256'
                'SelectedShardPolicySha256'
            )) {
                [string]$qualityProfile.$hashName | Should -Match '^[a-f0-9]{64}$'
                [string]$repeat.$hashName |
                    Should -BeExactly ([string]$qualityProfile.$hashName)
            }

            $actualShardIds = [string[]]@(
                $qualityProfile.QualityShards |
                    ForEach-Object { [string]$_.ShardId }
            )
            ($actualShardIds -join "`n") |
                Should -BeExactly (@($expectation.ShardIds) -join "`n")
            foreach ($shard in @($qualityProfile.QualityShards)) {
                ($shard.PSObject.Properties.Name -join ',') |
                    Should -BeExactly 'ShardId,Paths,PathsSha256'
                [string]$shard.ShardId | Should -Match '^[CHU][0-9]{2}$'
                @($shard.Paths).Count | Should -BeGreaterThan 0
                [string]$shard.PathsSha256 | Should -Match '^[a-f0-9]{64}$'
            }

            $flattenedPaths = [string[]]@(
                $qualityProfile.QualityShards |
                    ForEach-Object { @($_.Paths) } |
                    ForEach-Object { [string]$_ }
            )
            ([string[]]@($qualityProfile.SelectedFilePaths) -join "`n") |
                Should -BeExactly ($flattenedPaths -join "`n")
            ([string[]]@($qualityProfile.SelectedPesterPaths) -join "`n") |
                Should -BeExactly ($flattenedPaths -join "`n")
            @($flattenedPaths | Sort-Object -Unique).Count |
                Should -Be $expectation.FileCount

            $classificationEntries = switch -CaseSensitive ($expectation.QualitySet) {
                'AllBlocking' {
                    @(
                        @($script:ProductReleaseGate.ProductReleaseBlockingFiles) +
                        @($script:ProductReleaseGate.HistoricalDiagnosticFiles)
                    )
                    break
                }
                'ProductReleaseBlocking' {
                    @($script:ProductReleaseGate.ProductReleaseBlockingFiles)
                    break
                }
                'HistoricalDiagnostic' {
                    @($script:ProductReleaseGate.HistoricalDiagnosticFiles)
                    break
                }
            }
            $expectedPaths = [string[]]@(
                $classificationEntries |
                    Where-Object { [string]$_.FileKind -ceq 'PesterTest' } |
                    ForEach-Object { [string]$_.RelativePath }
            )
            $actualPaths = [string[]]$flattenedPaths.Clone()
            [Array]::Sort($expectedPaths, [StringComparer]::Ordinal)
            [Array]::Sort($actualPaths, [StringComparer]::Ordinal)
            ($actualPaths -join "`n") | Should -BeExactly ($expectedPaths -join "`n")
        }

        @($profiles.Values | ForEach-Object { $_.CanonicalSha256 } | Sort-Object -Unique).Count |
            Should -Be 3
        @(
            $profiles.Values |
                ForEach-Object { $_.SelectedFilePathsSha256 } |
                Sort-Object -Unique
        ).Count | Should -Be 3
        @(
            $profiles.Values |
                ForEach-Object { $_.SelectedShardPolicySha256 } |
                Sort-Object -Unique
        ).Count | Should -Be 3

        $productPaths = [string[]]@(
            $profiles.ProductReleaseBlocking.SelectedPesterPaths
        )
        $historicalPaths = [string[]]@(
            $profiles.HistoricalDiagnostic.SelectedPesterPaths
        )
        @($productPaths | Where-Object { $historicalPaths -ccontains $_ }).Count |
            Should -Be 0
        $combinedPaths = [string[]]@($productPaths + $historicalPaths)
        $allPaths = [string[]]@($profiles.AllBlocking.SelectedPesterPaths)
        [Array]::Sort($combinedPaths, [StringComparer]::Ordinal)
        [Array]::Sort($allPaths, [StringComparer]::Ordinal)
        ($combinedPaths -join "`n") | Should -BeExactly ($allPaths -join "`n")
    }

    It 'fails closed when an owner-scoped classification manifest copy is tampered' {
        $copyRoot = Join-Path $TestDrive 'tampered-quality-set-policy'
        $copyConfig = Join-Path $copyRoot 'config'
        [void](New-Item -ItemType Directory -Path $copyConfig -Force)
        Copy-Item -LiteralPath (Join-Path $script:RepoRoot 'tests') `
            -Destination $copyRoot -Recurse
        Copy-Item -LiteralPath (
            Join-Path $script:RepoRoot $script:ProductReleaseGateRelativePath
        ) -Destination $copyConfig
        Copy-Item -LiteralPath $script:DependencyManifestPath -Destination $copyConfig

        $tamperedManifestPath = Join-Path $copyConfig 'product-release-gate.psd1'
        $manifestText = [IO.File]::ReadAllText($tamperedManifestPath)
        $originalToken = 'ExpectedTrackedFileCount = 47'
        $manifestText.IndexOf($originalToken, [StringComparison]::Ordinal) |
            Should -BeGreaterOrEqual 0
        $manifestText.IndexOf(
            $originalToken,
            $manifestText.IndexOf($originalToken, [StringComparison]::Ordinal) + 1,
            [StringComparison]::Ordinal
        ) | Should -Be -1
        $tamperedText = $manifestText.Replace(
            $originalToken,
            'ExpectedTrackedFileCount = 48'
        )
        [IO.File]::WriteAllText(
            $tamperedManifestPath,
            $tamperedText,
            (New-Object Text.UTF8Encoding($false))
        )

        {
            Get-CddsiQualitySetPolicy `
                -RepositoryRoot $copyRoot `
                -QualitySet ProductReleaseBlocking
        } | Should -Throw
    }
}

Describe 'D-026 named release-gate static boundaries' {
    It 'classifies every named gate harness file exactly once and freezes dynamic invocation owners' {
        $gateFiles = @(
            'scripts/release-gate-common.ps1'
            'scripts/product-release-gate.ps1'
            'scripts/historical-diagnostics.ps1'
            'scripts/invoke-release-gates.ps1'
        )
        $dynamicGateFiles = @(
            'scripts/product-release-gate.ps1'
            'scripts/historical-diagnostics.ps1'
            'scripts/invoke-host-sandbox.ps1'
            'scripts/invoke-release-gates.ps1'
        )

        foreach ($relativePath in $gateFiles) {
            (Test-Path -LiteralPath (Join-Path $script:RepoRoot $relativePath) -PathType Leaf) |
                Should -BeTrue
            $boundaryOwners = @(
                $script:ExecutionBoundary.Planes.Keys |
                    Where-Object {
                        @($script:ExecutionBoundary.Planes[[string]$_]) -ccontains $relativePath
                    }
            )
            $boundaryOwners.Count | Should -Be 1
            [string]$boundaryOwners[0] | Should -BeExactly 'TrustedHarness'
            @(
                $script:ReleaseManifest.PackageFiles |
                    Where-Object { [string]$_ -ceq $relativePath }
            ).Count | Should -Be 0
            @(
                $script:ReleaseManifest.DevelopmentOnlyFiles |
                    Where-Object { [string]$_ -ceq $relativePath }
            ).Count | Should -Be 1
        }

        $dynamicOwners = @(
            $script:ExecutionBoundary.Rules.TrustedHarnessDynamicInvocationFiles
        )
        foreach ($relativePath in $dynamicGateFiles) {
            @($dynamicOwners | Where-Object { [string]$_ -ceq $relativePath }).Count |
                Should -Be 1
        }
        @(
            $dynamicOwners |
                Where-Object {
                    [string]$_ -ceq 'scripts/release-gate-common.ps1'
                }
        ).Count | Should -Be 0
    }

    It 'copies every entry parameter exactly once before dot-sourced libraries can overwrite it' {
        $entryScripts = @(
            'scripts/product-release-gate.ps1'
            'scripts/historical-diagnostics.ps1'
            'scripts/invoke-release-gates.ps1'
        )
        $expectedParameters = @(
            'PowerShell7Executable'
            'PowerShell7Sha256'
            'WindowsPowerShellExecutable'
            'WindowsPowerShellSha256'
            'GitExecutable'
            'GitSha256'
            'ProcessTimeoutSeconds'
            'PassThru'
            'ImportOnly'
        )

        foreach ($relativePath in $entryScripts) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot $relativePath),
                [ref]$tokens,
                [ref]$parseErrors
            )
            @($parseErrors).Count | Should -Be 0
            $parameterNames = @(
                $ast.ParamBlock.Parameters |
                    ForEach-Object { [string]$_.Name.VariablePath.UserPath }
            )
            ($parameterNames -join "`n") |
                Should -BeExactly ($expectedParameters -join "`n")

            $dotSourceStatements = @(
                $ast.FindAll(
                    {
                        param($node)
                        $node -is [System.Management.Automation.Language.CommandAst] -and
                        $node.InvocationOperator -eq
                        [System.Management.Automation.Language.TokenKind]::Dot
                    },
                    $true
                )
            )
            $dotSourceStatements.Count | Should -BeGreaterThan 0
            $firstDotSourceOffset = (
                $dotSourceStatements |
                    Sort-Object { $_.Extent.StartOffset } |
                    Select-Object -First 1
            ).Extent.StartOffset
            $preImportAssignments = @(
                $ast.EndBlock.Statements |
                    Where-Object {
                        $_ -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $_.Extent.EndOffset -le $firstDotSourceOffset
                    }
            )
            $copyNames = New-Object 'System.Collections.Generic.HashSet[string]' (
                [StringComparer]::Ordinal
            )
            foreach ($parameterName in $expectedParameters) {
                $copies = @(
                    $preImportAssignments |
                        Where-Object {
                            $sourceNames = @(
                                $_.Right.FindAll(
                                    {
                                        param($node)
                                        $node -is [System.Management.Automation.Language.VariableExpressionAst]
                                    },
                                    $true
                                ) |
                                    ForEach-Object {
                                        [string]$_.VariablePath.UserPath
                                    }
                            )
                            $sourceNames.Count -eq 1 -and
                            $sourceNames[0] -ceq $parameterName
                        }
                )
                $copies.Count | Should -Be 1
                ($copies[0].Left -is [System.Management.Automation.Language.VariableExpressionAst]) |
                    Should -BeTrue
                $copyName = [string]$copies[0].Left.VariablePath.UserPath
                $copyName | Should -Not -BeExactly $parameterName
                $copyNames.Add($copyName) | Should -BeTrue
            }
            $copyNames.Count | Should -Be $expectedParameters.Count
        }
    }

    It 'binds the product gate to one repository root three snapshots and Release DryRun' {
        $path = Join-Path $script:RepoRoot 'scripts\product-release-gate.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path,
            [ref]$tokens,
            [ref]$parseErrors
        )
        @($parseErrors).Count | Should -Be 0
        @(
            $ast.ParamBlock.Parameters |
                Where-Object {
                    [string]$_.Name.VariablePath.UserPath -ceq 'RepositoryRoot'
                }
        ).Count | Should -Be 0

        $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n")
        @([regex]::Matches(
            $text,
            '(?m)^\$script:CddsiProductGateRepositoryRoot = \[System\.IO\.Path\]::GetFullPath\($'
        )).Count | Should -Be 1
        @([regex]::Matches(
            $text,
            '(?m)^\s+\-RootPath \$script:CddsiProductGateRepositoryRoot$'
        )).Count | Should -Be 3
        @([regex]::Matches(
            $text,
            '(?m)^\s+\-QualitySet ProductReleaseBlocking$'
        )).Count | Should -BeGreaterOrEqual 1
        @([regex]::Matches(
            $text,
            '(?m)^\s*\$releaseDryRunEvidence = & \(Join-Path \$PSScriptRoot ''build-release\.ps1''\) -DryRun$'
        )).Count | Should -Be 1
        @([regex]::Matches(
            $text,
            '(?m)^\s+RepositorySnapshot(?:BeforeQuality|AfterQuality|AfterRelease) = '
        )).Count | Should -Be 3
        @([regex]::Matches(
            $text,
            '(?m)^\s*Assert-CddsiGateRepositorySnapshotsEqual `$\n\s+\-Expected \$beforeQuality `$'
        )).Count | Should -Be 2
        foreach ($snapshotName in @(
            'beforeQuality'
            'afterQuality'
            'afterRelease'
        )) {
            $text | Should -Match (
                '(?m)^\s*\${0} = Assert-CddsiGateRepositorySnapshot ' -f
                $snapshotName
            )
        }
    }

    It 'keeps ImportOnly grant-free and wraps product failures in one stable safe code' {
        $path = Join-Path $script:RepoRoot 'scripts\product-release-gate.ps1'
        $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n")
        @([regex]::Matches(
            $text,
            '(?m)^function New-CddsiProductGateFailureException \{$'
        )).Count | Should -Be 1
        @([regex]::Matches(
            $text,
            [regex]::Escape("'PRODUCT_RELEASE_GATE_FAILED'")
        )).Count | Should -Be 1
        $catchBlocks = @([regex]::Matches(
            $text,
            '(?ms)^catch \{\n(?<Body>.*?)^\}$'
        ))
        $catchBlocks.Count | Should -Be 2
        $catchBlocks[0].Groups['Body'].Value.Trim() | Should -BeExactly (
            'throw (New-CddsiProductGateFailureException ' +
            '-FailureStage IMPORT -Cause $_.Exception)'
        )
        $catchBlocks[1].Groups['Body'].Value.Trim() | Should -BeExactly (
            'throw (New-CddsiProductGateFailureException ' +
            '-FailureStage EXECUTION -Cause $_.Exception)'
        )

        [object[]]$results = @(
            & {
                . $path -ImportOnly
                New-CddsiProductGateFailureException
            }
        )
        $results.Count | Should -Be 1
        $exception = $results[0]
        ($exception -is [InvalidOperationException]) | Should -BeTrue
        $exception.Message | Should -BeExactly 'ProductReleaseGate failed safely.'
        [string]$exception.Data['CddsiFailureCode'] |
            Should -BeExactly 'PRODUCT_RELEASE_GATE_FAILED'
        [string]$exception.Data['CddsiFailureStage'] |
            Should -BeExactly 'EXECUTION'
        @($exception.Data.Keys).Count | Should -Be 2

        $safeCause = [InvalidOperationException]::new('synthetic safe cause')
        $safeCause.Data['CddsiFailureEvidenceJson'] = (
            New-CddsiNamedGateSafeFailureJsonFixture
        )
        $safeException = & {
            . $path -ImportOnly
            New-CddsiProductGateFailureException `
                -FailureStage EXECUTION `
                -Cause $safeCause
        }
        [string]$safeException.Data['CddsiSafeFailureEvidenceJson'] |
            Should -BeExactly ([string]$safeCause.Data['CddsiFailureEvidenceJson'])
        [string]$safeException.Data['CddsiSafeFailureEvidenceStatus'] |
            Should -BeExactly 'BOUND'

        $unsafeCause = [InvalidOperationException]::new('synthetic unsafe cause')
        $unsafeEvidence = (
            New-CddsiNamedGateSafeFailureJsonFixture |
                ConvertFrom-Json
        )
        $unsafeEvidence.SafeFailureMessage = 'C:\private\path'
        $unsafeCause.Data['CddsiFailureEvidenceJson'] = (
            $unsafeEvidence | ConvertTo-Json -Depth 100 -Compress
        )
        $unsafeException = & {
            . $path -ImportOnly
            New-CddsiProductGateFailureException `
                -FailureStage EXECUTION `
                -Cause $unsafeCause
        }
        $unsafeException.Data.Contains('CddsiSafeFailureEvidenceJson') |
            Should -BeFalse
        [string]$unsafeException.Data['CddsiSafeFailureEvidenceStatus'] |
            Should -BeExactly 'REJECTED_UNSAFE'

        $safeJson = New-CddsiNamedGateSafeFailureJsonFixture
        $escapedPathJson = $safeJson.Replace(
            'Synthetic safe failure.',
            'C:\u005cprivate\u005cpath'
        )
        $escapedSecretJson = $safeJson.Replace(
            'Synthetic safe failure.',
            ('s\u006b-' + ('z' * 24))
        )
        $forwardDrivePathJson = $safeJson.Replace(
            'Synthetic safe failure.',
            'C:/private/path'
        )
        $forwardUncPathJson = $safeJson.Replace(
            'Synthetic safe failure.',
            '//server/share/private'
        )
        $rootedForwardPathJson = $safeJson.Replace(
            'Synthetic safe failure.',
            '/Users/private/path'
        )
        $rootedBackslashPathJson = $safeJson.Replace(
            'Synthetic safe failure.',
            '\\Users\\private\\path'
        )
        foreach ($escapedJson in @(
                $escapedPathJson
                $escapedSecretJson
                $forwardDrivePathJson
                $forwardUncPathJson
                $rootedForwardPathJson
                $rootedBackslashPathJson
            )) {
            $escapedCause = [InvalidOperationException]::new(
                'synthetic escaped unsafe cause'
            )
            $escapedCause.Data['CddsiFailureEvidenceJson'] = $escapedJson
            $escapedException = & {
                . $path -ImportOnly
                New-CddsiProductGateFailureException `
                    -FailureStage EXECUTION `
                    -Cause $escapedCause
            }
            $escapedException.Data.Contains(
                'CddsiSafeFailureEvidenceJson'
            ) | Should -BeFalse
            [string]$escapedException.Data[
                'CddsiSafeFailureEvidenceStatus'
            ] | Should -BeExactly 'REJECTED_UNSAFE'
        }

        $safeUrlCause = [InvalidOperationException]::new(
            'synthetic safe URL cause'
        )
        $safeUrlCause.Data['CddsiFailureEvidenceJson'] = $safeJson.Replace(
            'Synthetic safe failure.',
            'https://example.invalid/safe-diagnostic'
        )
        $safeUrlException = & {
            . $path -ImportOnly
            New-CddsiProductGateFailureException `
                -FailureStage EXECUTION `
                -Cause $safeUrlCause
        }
        [string]$safeUrlException.Data['CddsiSafeFailureEvidenceStatus'] |
            Should -BeExactly 'BOUND'
    }

    It 'binds historical diagnostics to the fixed repository root and exact historical set' {
        $path = Join-Path $script:RepoRoot 'scripts\historical-diagnostics.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $path,
            [ref]$tokens,
            [ref]$parseErrors
        )
        @($parseErrors).Count | Should -Be 0
        @(
            $ast.ParamBlock.Parameters |
                Where-Object {
                    [string]$_.Name.VariablePath.UserPath -ceq 'RepositoryRoot'
                }
        ).Count | Should -Be 0

        $text = [IO.File]::ReadAllText($path).Replace("`r`n", "`n")
        @([regex]::Matches(
            $text,
            '(?m)^\$script:CddsiHistoricalRepositoryRoot = \[System\.IO\.Path\]::GetFullPath\($'
        )).Count | Should -Be 1
        @([regex]::Matches(
            $text,
            '(?m)^\s+\-RepositoryRoot \$script:CddsiHistoricalRepositoryRoot `$'
        )).Count | Should -BeGreaterOrEqual 1
        @([regex]::Matches(
            $text,
            '(?m)^\s+\-QualitySet HistoricalDiagnostic$'
        )).Count | Should -BeGreaterOrEqual 1
        $text | Should -Match (
            "(?m)^\s*if \(\`$EnforcementPhase -cne 'NamedProductReleaseGate'\) \{$"
        )
        $text | Should -Match "(?m)^\s+'ReportOnlyAfterCompleteTestFailure'$"
    }

    It 'binds historical engine summaries to total passed and failed test counts' {
        $path = Join-Path $script:RepoRoot 'scripts\historical-diagnostics.ps1'
        $validSummary = [pscustomobject][ordered]@{
            DiagnosticResult = 'FAILED_TESTS'
            FailedTestCount = 2L
            RequiredSuiteFailureCount = 0L
            WorkerSummaries = @(
                [pscustomobject][ordered]@{
                    Result = 'Failed'
                    TotalCount = 5L
                    PassedCount = 4L
                    FailedCount = 1L
                    RequiredSuiteFailureCount = 0L
                }
                [pscustomobject][ordered]@{
                    Result = 'Failed'
                    TotalCount = 7L
                    PassedCount = 6L
                    FailedCount = 1L
                    RequiredSuiteFailureCount = 0L
                }
            )
        }

        {
            & {
                . $path -ImportOnly
                Assert-CddsiHistoricalValidationSummary `
                    -ValidationSummary $validSummary
            }
        } | Should -Not -Throw

        $missingTotal = (
            $validSummary |
                ConvertTo-Json -Depth 10 |
                ConvertFrom-Json
        )
        $missingTotal.WorkerSummaries[1].PSObject.Properties.Remove('TotalCount')
        {
            & {
                . $path -ImportOnly
                Assert-CddsiHistoricalValidationSummary `
                    -ValidationSummary $missingTotal
            }
        } | Should -Throw

        $driftedTotal = (
            $validSummary |
                ConvertTo-Json -Depth 10 |
                ConvertFrom-Json
        )
        $driftedTotal.WorkerSummaries[1].TotalCount = 8L
        {
            & {
                . $path -ImportOnly
                Assert-CddsiHistoricalValidationSummary `
                    -ValidationSummary $driftedTotal
            }
        } | Should -Throw
    }

    It 'preserves complete safe child failures through entry 33 and beyond the former capacity boundary' {
        $path = Join-Path $script:RepoRoot 'scripts\invoke-release-gates.ps1'
        $largeJson = New-CddsiNamedGateSafeFailureJsonFixture `
            -FailedTestCount 371 `
            -NamePaddingLength 470
        $largeJson.Length | Should -BeGreaterThan 131072

        $productCause = [InvalidOperationException]::new(
            'synthetic product raw message must not escape'
        )
        $productCause.Data['CddsiFailureEvidenceJson'] = $largeJson
        $historicalError = [InvalidOperationException]::new(
            'synthetic historical raw message must not escape'
        )
        $historicalError.Data['CddsiFailureEvidenceJson'] = (
            New-CddsiNamedGateSafeFailureJsonFixture -FailedTestCount 33
        )

        $results = @(
            & {
                . $path -ImportOnly
                $productError = New-CddsiProductGateFailureException `
                    -FailureStage EXECUTION `
                    -Cause $productCause
                $evidence = New-CddsiNamedGateFailureEvidence `
                    -ProductSucceeded $false `
                    -ProductError $productError `
                    -HistoricalSucceeded $false `
                    -HistoricalError $historicalError `
                    -FailureCode CHILD_GATE_FAILURE
                $null = Assert-CddsiNamedGateFailureEvidence -Evidence $evidence
                $exception = New-CddsiNamedGateFailureException `
                    -Evidence $evidence
                [pscustomobject]@{
                    Evidence = $evidence
                    Exception = $exception
                }
            }
        )
        $results.Count | Should -Be 1
        $evidence = $results[0].Evidence
        $exception = $results[0].Exception
        $evidence.ChildFailureCount | Should -Be 2
        $evidence.ProductPath.SafeFailureEvidenceStatus |
            Should -BeExactly 'BOUND'
        $evidence.HistoricalPath.SafeFailureEvidenceStatus |
            Should -BeExactly 'BOUND'
        @(
            $evidence.ProductPath.SafeFailureEvidence.Progress.CurrentFailedTests
        ).Count | Should -Be 371
        $evidence.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTestEvidenceTruncated | Should -BeFalse
        $evidence.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[32].Name |
            Should -Match '^synthetic failure 033 '
        $evidence.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[370].Name |
            Should -Match '^synthetic failure 371 '
        $evidence.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[370].ErrorRecordCount | Should -Be 1
        @(
            $evidence.HistoricalPath.SafeFailureEvidence.Progress.
                CurrentFailedTests
        ).Count | Should -Be 33
        $evidence.HistoricalPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[32].Name |
            Should -Match '^synthetic failure 033 '
        $evidence.HistoricalPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[32].ErrorRecordCount | Should -Be 1
        [string]$exception.Data['CddsiFailureCode'] |
            Should -BeExactly 'NAMED_RELEASE_GATE_FAILED'
        $combinedJson = [string]$exception.Data['CddsiFailureEvidenceJson']
        $combinedJson.Length | Should -BeGreaterThan 131072
        $combinedJson | Should -Not -Match 'product raw message'
        $combinedJson | Should -Not -Match 'historical raw message'
        $roundTrip = $combinedJson | ConvertFrom-Json
        @(
            $roundTrip.ProductPath.SafeFailureEvidence.Progress.
                CurrentFailedTests
        ).Count | Should -Be 371
        $roundTrip.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[32].ErrorRecordCount | Should -Be 1
        $roundTrip.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[370].Name |
            Should -Match '^synthetic failure 371 '
        $roundTrip.ProductPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[370].ErrorRecordCount | Should -Be 1
        @(
            $roundTrip.HistoricalPath.SafeFailureEvidence.Progress.
                CurrentFailedTests
        ).Count | Should -Be 33
        $roundTrip.HistoricalPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[32].Name |
            Should -Match '^synthetic failure 033 '
        $roundTrip.HistoricalPath.SafeFailureEvidence.Progress.
            CurrentFailedTests[32].ErrorRecordCount | Should -Be 1

        $forged = (
            New-CddsiNamedGateSafeFailureJsonFixture -FailedTestCount 33 |
                ConvertFrom-Json
        )
        $forged.Progress.CurrentFailedTests[32].ErrorRecordCount = 0
        $forgedCause = [InvalidOperationException]::new(
            'synthetic forged cause'
        )
        $forgedCause.Data['CddsiFailureEvidenceJson'] = (
            $forged | ConvertTo-Json -Depth 100 -Compress
        )
        $forgedOutcome = & {
            . $path -ImportOnly
            $forgedProductError = New-CddsiProductGateFailureException `
                -FailureStage EXECUTION `
                -Cause $forgedCause
            New-CddsiNamedGateChildOutcome `
                -Gate ProductReleaseGate `
                -Succeeded $false `
                -Error $forgedProductError
        }
        $forgedOutcome.SafeFailureEvidenceStatus |
            Should -BeExactly 'REJECTED_UNSAFE'
        $forgedOutcome.SafeFailureEvidence | Should -BeNullOrEmpty
        $forgedOutcome.SafeFailureEvidenceSha256 | Should -BeNullOrEmpty

        $validationFailure = & {
            . $path -ImportOnly
            New-CddsiNamedGateFailureEvidence `
                -ProductSucceeded $true `
                -ProductError $null `
                -HistoricalSucceeded $true `
                -HistoricalError $null `
                -FailureCode NAMED_GATE_VALIDATION_FAILED
        }
        $validationFailure.ChildFailureCount | Should -Be 0
        $validationFailure.ProductPath.Status | Should -BeExactly 'PASSED'
        $validationFailure.HistoricalPath.Status | Should -BeExactly 'PASSED'
        {
            & {
                . $path -ImportOnly
                Assert-CddsiNamedGateFailureEvidence `
                    -Evidence $validationFailure
            }
        } | Should -Not -Throw
    }

    It 'attempts product first historical second and emits a bound safe failure after both paths' {
        $path = Join-Path $script:RepoRoot 'scripts\invoke-release-gates.ps1'
        $text = [IO.File]::ReadAllText($path)
        $mainOffset = $text.IndexOf(
            '$productSucceeded = $false',
            [StringComparison]::Ordinal
        )
        $mainOffset | Should -BeGreaterOrEqual 0
        $mainText = $text.Substring($mainOffset)

        $productTryOffset = $mainText.IndexOf(
            '& $script:CddsiProductGateScript',
            [StringComparison]::Ordinal
        )
        $productCatchOffset = $mainText.IndexOf(
            '$productError = $_.Exception',
            [StringComparison]::Ordinal
        )
        $historicalTryOffset = $mainText.IndexOf(
            '& $script:CddsiHistoricalGateScript',
            [StringComparison]::Ordinal
        )
        $historicalCatchOffset = $mainText.IndexOf(
            '$historicalError = $_.Exception',
            [StringComparison]::Ordinal
        )
        $hardFailureOffset = $mainText.IndexOf(
            'if (-not $productSucceeded -or -not $historicalSucceeded)',
            [StringComparison]::Ordinal
        )
        $hardThrowOffset = $mainText.IndexOf(
            'Throw-CddsiNamedGateFailure -Evidence $failureEvidence',
            [StringComparison]::Ordinal
        )
        $productTryOffset | Should -BeGreaterOrEqual 0
        $productCatchOffset | Should -BeGreaterThan $productTryOffset
        $historicalTryOffset | Should -BeGreaterThan $productCatchOffset
        $historicalCatchOffset | Should -BeGreaterThan $historicalTryOffset
        $hardFailureOffset | Should -BeGreaterThan $historicalCatchOffset
        $hardThrowOffset | Should -BeGreaterThan $hardFailureOffset
        $mainText.Substring(
            $productCatchOffset,
            $historicalTryOffset - $productCatchOffset
        ) | Should -Not -Match '(?m)^\s*throw\b'
    }
}

Describe 'GitHub Actions workflow supply-chain and evidence contracts' {
    It 'keeps an exact workflow inventory with canonical UTF-8 LF formatting' {
        $workflowRoot = Join-Path $script:RepoRoot '.github\workflows'
        $expectedNames = @('ci.yml', 'release-dry-run.yml')
        $actualNames = @(Get-ChildItem -LiteralPath $workflowRoot -File | ForEach-Object Name | Sort-Object)
        ($actualNames -join "`n") | Should -BeExactly ($expectedNames -join "`n")

        $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        foreach ($name in $expectedNames) {
            $path = Join-Path $workflowRoot $name
            $bytes = [System.IO.File]::ReadAllBytes($path)
            $bytes.Count | Should -BeGreaterThan 0
            ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
            { $strictUtf8.GetString($bytes) } | Should -Not -Throw
            $text = $strictUtf8.GetString($bytes)
            $text.Contains("`r") | Should -BeFalse
            $text.EndsWith("`n", [StringComparison]::Ordinal) | Should -BeTrue
            $text.EndsWith("`n`n", [StringComparison]::Ordinal) | Should -BeFalse
            $text.Substring(0, $text.Length - 1) | Should -Not -Match '(?m)[ \t]+$'
        }
    }

    It 'pins every action and keeps exact triggers jobs and minimum read-only permissions' {
        $workflowRoot = Join-Path $script:RepoRoot '.github\workflows'
        $contracts = [ordered]@{
            'ci.yml' = [ordered]@{
                Header = "name: CI`n`non:`n  push:`n    branches: [main]`n  pull_request:"
                Job    = 'quality'
            }
            'release-dry-run.yml' = [ordered]@{
                Header = "name: Release dry run`n`non:`n  workflow_dispatch:`n  pull_request:"
                Job    = 'release-contract'
            }
        }
        $approvedCheckoutSha = '11bd71901bbe5b1630ceea73d27597364c9af683'

        foreach ($name in $contracts.Keys) {
            $text = [System.IO.File]::ReadAllText((Join-Path $workflowRoot $name))
            $text.StartsWith($contracts[$name].Header + "`n`npermissions:`n  contents: read`n`njobs:`n", [StringComparison]::Ordinal) | Should -BeTrue
            @([regex]::Matches($text, '(?m)^permissions:$')).Count | Should -Be 1
            $jobMatches = @([regex]::Matches($text, '(?m)^  (?<name>[a-z0-9-]+):\n    (?:runs-on|uses):'))
            $jobMatches.Count | Should -Be 1
            $jobMatches[0].Groups['name'].Value | Should -BeExactly $contracts[$name].Job
            @([regex]::Matches($text, '(?m)^    runs-on: windows-latest$')).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^    timeout-minutes: 240$')).Count | Should -Be 1
            $text | Should -Not -Match '(?mi)^[ ]*[a-z0-9-]+:[ ]*write[ ]*$'
            $text | Should -Not -Match '(?mi)^[ ]*(pull_request_target|schedule):[ ]*$'
            $text | Should -Not -Match '(?im)(-Mode\s+[''"]?Live\b|\bMode\s*[:=]\s*[''"]?Live\b|^[ ]+Live:[ ]*$)'
            $text | Should -Not -Match '(?i)\b(SkipQualityGate|OutputDirectory)\b'

            $allUses = @([regex]::Matches($text, '(?m)^[ ]*uses:[ ]*\S+.*$'))
            $pinnedUses = @([regex]::Matches($text, '(?m)^[ ]*uses:[ ]*[^@\s]+@[a-f0-9]{40}(?:[ ]+#.*)?$'))
            $allUses.Count | Should -BeGreaterThan 0
            $pinnedUses.Count | Should -Be $allUses.Count
            @([regex]::Matches($text, "(?m)^[ ]*uses:[ ]*actions/checkout@$approvedCheckoutSha(?:[ ]+#.*)?$")).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^[ ]*persist-credentials:[ ]*false[ ]*$')).Count | Should -Be 1
            $text | Should -Match ("(?m)^[ ]+- name: [^`n]+`n[ ]+uses: actions/checkout@{0}(?:[ ]+#.*)?`n[ ]+with:`n[ ]+persist-credentials: false(?:`n|$)" -f $approvedCheckoutSha)
        }
    }

    It 'uses exactly three PowerShell run steps and only the named gate entry point' {
        $workflowRoot = Join-Path $script:RepoRoot '.github\workflows'
        foreach ($name in @('ci.yml', 'release-dry-run.yml')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $workflowRoot $name))
            $runLines = @([regex]::Matches($text, '(?m)^[ ]+run:[ ]*(?:\||\S.*)$'))
            $shellLines = @([regex]::Matches($text, '(?m)^[ ]+shell:[ ]*.*$'))
            $exactShellLines = @([regex]::Matches($text, '(?m)^[ ]+shell: pwsh -NoLogo -NoProfile -NonInteractive -File \{0\}$'))
            $runLines.Count | Should -Be 3
            $shellLines.Count | Should -Be $runLines.Count
            $exactShellLines.Count | Should -Be $shellLines.Count

            @([regex]::Matches($text, '(?m)^[ ]+run: \./scripts/bootstrap-dev\.ps1[ ]*$')).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^[ ]+\$result = \./scripts/invoke-release-gates\.ps1 `[ ]*$')).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^[ ]+-PassThru[ ]*$')).Count | Should -Be 1
            @([regex]::Matches(
                $text,
                '(?m)^[ ]+-ProcessTimeoutSeconds 900 `[ ]*$'
            )).Count | Should -Be 1
            foreach ($stepName in @(
                'Bind trusted runner tool grants'
                'Verify vendored Pester lock'
                'Run named product gate and independent historical diagnostics'
            )) {
                @([regex]::Matches(
                    $text,
                    '(?m)^[ ]+- name: {0}$' -f [regex]::Escape($stepName)
                )).Count | Should -Be 1
            }

            $bootstrapIndex = $text.IndexOf('run: ./scripts/bootstrap-dev.ps1', [StringComparison]::Ordinal)
            $gateIndex = $text.IndexOf('$result = ./scripts/invoke-release-gates.ps1', [StringComparison]::Ordinal)
            $bootstrapIndex | Should -BeGreaterOrEqual 0
            $gateIndex | Should -BeGreaterThan $bootstrapIndex
            foreach ($forbiddenEntry in @(
                './scripts/check.ps1'
                './scripts/build-release.ps1'
                './scripts/invoke-host-sandbox.ps1'
            )) {
                $text.IndexOf($forbiddenEntry, [StringComparison]::Ordinal) |
                    Should -Be -1
            }
        }
    }

    It 'validates exact outer named gate evidence and terminal status' {
        $expectedOuterPropertySet = (
            'BindingSha256,ContractVersion,EvidenceType,HistoricalDiagnosticEvidence,' +
            'HistoricalDiagnosticEvidenceSha256,HistoricalDiagnosticResult,' +
            'HistoricalReleaseBlocking,HistoricalStatus,ProductGateEvidenceSha256,' +
            'ProductGateStatus,ProductReleaseGateEvidence,SchemaVersion,Status'
        )

        foreach ($name in @('ci.yml', 'release-dry-run.yml')) {
            $text = [IO.File]::ReadAllText((
                Join-Path $script:RepoRoot ".github\workflows\$name"
            ))
            foreach ($requiredToken in @(
                $expectedOuterPropertySet
                'CddsiNamedReleaseGateRunEvidence'
                'D-026'
                'BindingSha256'
                'ProductGateEvidenceSha256'
                'HistoricalDiagnosticEvidenceSha256'
                'ProductReleaseGateEvidence'
                'HistoricalDiagnosticEvidence'
            )) {
                $text | Should -Match ([regex]::Escape($requiredToken))
            }
            $text | Should -Match "(?m)^\s+\`$result\.Status -cne 'PASSED' -or$"
            $text | Should -Match (
                "(?m)^\s+\`$result\.ProductGateStatus -cne 'PASSED' -or$"
            )
            $text | Should -Match (
                "(?m)^\s+\`$result\.HistoricalStatus -cne 'COMPLETED' -or$"
            )
            $text | Should -Match (
                "(?m)^\s+\`$result\.HistoricalDiagnosticResult -notin " +
                "@\('PASSED', 'FAILED_TESTS'\) -or$"
            )
            $text | Should -Match (
                '(?s)\$result\.HistoricalReleaseBlocking -isnot \[bool\].*?' +
                '\$result\.HistoricalReleaseBlocking\)'
            )
        }
    }

    It 'validates exact product historical topology and nested Release DryRun evidence' {

        foreach ($name in @('ci.yml', 'release-dry-run.yml')) {
            $text = [IO.File]::ReadAllText((
                Join-Path $script:RepoRoot ".github\workflows\$name"
            ))
            foreach ($binding in @(
                @{ Prefix = 'product'; Name = 'ExpectedPesterFileCount'; Value = 29 },
                @{ Prefix = 'product'; Name = 'ExpectedWorkerCount'; Value = 18 },
                @{ Prefix = 'product'; Name = 'ExpectedProcessCount'; Value = 21 },
                @{ Prefix = 'product'; Name = 'ExpectedLedgerEntryCount'; Value = 48 },
                @{ Prefix = 'historical'; Name = 'ExpectedPesterFileCount'; Value = 13 },
                @{ Prefix = 'historical'; Name = 'ExpectedWorkerCount'; Value = 20 },
                @{ Prefix = 'historical'; Name = 'ExpectedProcessCount'; Value = 23 },
                @{ Prefix = 'historical'; Name = 'ExpectedLedgerEntryCount'; Value = 52 }
            )) {
                $text | Should -Match (
                    '(?m)^\s+\${0}\.{1} -ne {2}(?: -or)?$' -f
                    $binding.Prefix,
                    $binding.Name,
                    $binding.Value
                )
            }

            foreach ($requiredLine in @(
                "`$product.EnforcementPhase -cne 'NamedProductReleaseGate' -or"
                "`$product.QualitySet -cne 'ProductReleaseBlocking' -or"
                "`$historical.QualitySet -cne 'HistoricalDiagnostic' -or"
                "`$product.ReleaseDryRunEvidence.Status -cne 'SUCCEEDED' -or"
                "`$product.ReleaseDryRunEvidence.Operation -cne 'ReleaseSimulation' -or"
            )) {
                $text | Should -Match (
                    '(?m)^\s+{0}$' -f [regex]::Escape($requiredLine)
                )
            }
            $text | Should -Match (
                "(?m)^\s+if \(\`$product\.Status -cne 'PASSED' -or$"
            )
            $text | Should -Match (
                "(?m)^\s+\`$product\.ReleaseDryRunEvidence\.Mode -cne " +
                "'DryRun'\) \{$"
            )
            $text | Should -Match (
                "(?m)^\s+if \(\`$historical\.Status -cne 'COMPLETED' -or$"
            )
            $text | Should -Match (
                '(?m)^\s+\$historical\.DiagnosticResult -cne ' +
                '\$result\.HistoricalDiagnosticResult -or$'
            )
            $text | Should -Match (
                '(?s)\$historical\.ReleaseBlocking -isnot \[bool\].*?' +
                '\$historical\.ReleaseBlocking'
            )
        }
    }
}
