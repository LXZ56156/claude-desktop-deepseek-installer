BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BootstrapPath = Join-Path $script:RepoRoot 'scripts\bootstrap-dev.ps1'
    $script:DependencyManifestPath = Join-Path $script:RepoRoot 'config\dev-dependencies.psd1'
    $script:VendoredPesterRoot = Join-Path $script:RepoRoot '.dev\modules\Pester\5.6.1'
    . $script:BootstrapPath
    $script:DependencyLock = Import-PowerShellDataFile -LiteralPath $script:DependencyManifestPath

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

    It 'uses one exact PowerShell shell per run step and orders bootstrap quality and release gates' {
        $workflowRoot = Join-Path $script:RepoRoot '.github\workflows'
        foreach ($name in @('ci.yml', 'release-dry-run.yml')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $workflowRoot $name))
            $runLines = @([regex]::Matches($text, '(?m)^[ ]+run:[ ]*(?:\||\S.*)$'))
            $shellLines = @([regex]::Matches($text, '(?m)^[ ]+shell:[ ]*.*$'))
            $exactShellLines = @([regex]::Matches($text, '(?m)^[ ]+shell: pwsh -NoLogo -NoProfile -NonInteractive -File \{0\}$'))
            $runLines.Count | Should -Be 4
            $shellLines.Count | Should -Be $runLines.Count
            $exactShellLines.Count | Should -Be $shellLines.Count

            @([regex]::Matches($text, '(?m)^[ ]+run: \./scripts/bootstrap-dev\.ps1[ ]*$')).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^[ ]+\$evidence = \./scripts/check\.ps1 `[ ]*$')).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^[ ]+-PassThru[ ]*$')).Count | Should -Be 1
            @([regex]::Matches($text, '(?m)^[ ]+\$(?:result|releaseEvidence) = \./scripts/build-release\.ps1 -DryRun[ ]*$')).Count | Should -Be 1

            $bootstrapIndex = $text.IndexOf('run: ./scripts/bootstrap-dev.ps1', [StringComparison]::Ordinal)
            $qualityIndex = $text.IndexOf('$evidence = ./scripts/check.ps1', [StringComparison]::Ordinal)
            $releaseIndex = $text.IndexOf('./scripts/build-release.ps1 -DryRun', [StringComparison]::Ordinal)
            $bootstrapIndex | Should -BeGreaterOrEqual 0
            $qualityIndex | Should -BeGreaterThan $bootstrapIndex
            $releaseIndex | Should -BeGreaterThan $qualityIndex
        }
    }

    It 'requires complete dual-engine quality isolation evidence before release simulation' {
        $qualityZeroMetrics = @(
            'FORBIDDEN_RESOURCE_ACCESS_COUNT', 'OUTSIDE_SANDBOX_WRITE_COUNT',
            'PRODUCT_LIVE_PROCESS_SPAWN_COUNT', 'PRODUCT_NETWORK_REQUEST_COUNT',
            'REAL_REGISTRY_ACCESS_COUNT', 'UNAPPROVED_HARNESS_PROCESS_COUNT',
            'UNAPPROVED_HARNESS_NETWORK_COUNT', 'SECRET_FINDINGS',
            'UNEXPECTED_LEDGER_ENTRY_COUNT'
        )
        $qualityFalseFlags = @('LIVE_PROVIDER_LOADED', 'REPOSITORY_CONTENT_CHANGED')
        $expectedQualityPropertySet = 'CLEANUP_OUTCOME,FORBIDDEN_RESOURCE_ACCESS_COUNT,HARNESS_LEDGER,HARNESS_LEDGER_EXACT,LIVE_PROVIDER_LOADED,MUTATION_SPY_COUNTS,OUTSIDE_SANDBOX_WRITE_COUNT,PRODUCT_LIVE_PROCESS_SPAWN_COUNT,PRODUCT_NETWORK_REQUEST_COUNT,REAL_REGISTRY_ACCESS_COUNT,REPOSITORY_AFTER_DIRECTORY_COUNT,REPOSITORY_AFTER_FILE_COUNT,REPOSITORY_AFTER_SHA256,REPOSITORY_BEFORE_DIRECTORY_COUNT,REPOSITORY_BEFORE_FILE_COUNT,REPOSITORY_BEFORE_SHA256,REPOSITORY_CONTENT_CHANGED,REPOSITORY_SNAPSHOT_SCOPE,RunId,SAFE_FAILURE_DISCLOSURE,Scenario,SchemaVersion,SECRET_FINDINGS,TRUSTED_HARNESS_PROCESS_COUNT,TRUSTED_PROCESS_ACTUAL_COUNT,TRUSTED_PROCESS_EXPECTED_COUNT,TRUSTED_PROCESS_SEQUENCE,UNAPPROVED_HARNESS_NETWORK_COUNT,UNAPPROVED_HARNESS_PROCESS_COUNT,UNEXPECTED_LEDGER_ENTRY_COUNT,WORKER_EVIDENCE'
        $expectedMutationSpySet = 'AppX,Credential,Environment,Feature,FileSystem,Network,Process,Registry,Restart,Service'
        $expectedWorkerEngineSet = 'PowerShell7,WindowsPowerShell'
        $expectedTrustedProcessSequence = 'GitInventory,QualityWorkerPowerShell7,QualityWorkerWindowsPowerShell,GitDiffCheck,GitCachedDiffCheck'
        $expectedHarnessLedgerSequence = 'ValidateToolGrant,ValidateToolGrant,ValidateToolGrant,CreateSandbox,WriteOwnerMarker,CreateSyntheticEnvironment,GitInventory,WriteRepositoryInventory,QualityWorkerPowerShell7,ReadWorkerEvidence,QualityWorkerWindowsPowerShell,ReadWorkerEvidence,GitDiffCheck,GitCachedDiffCheck,ScanSandboxArtifacts,CleanupSandbox'

        foreach ($name in @('ci.yml', 'release-dry-run.yml')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot ".github\workflows\$name"))
            foreach ($propertyName in $qualityZeroMetrics + $qualityFalseFlags) {
                $text | Should -Match ("(?<![A-Za-z0-9_]){0}(?![A-Za-z0-9_])" -f [regex]::Escape($propertyName))
            }
            $text | Should -Match '\$qualityZeroMetrics'
            $text | Should -Match '(?s)foreach\s*\(\$metric\s+in\s+\$qualityZeroMetrics\).*?\[long\]\$evidence\.\$metric\s+-ne\s+0.*?throw'
            $text | Should -Match '\$qualityFalseFlags'
            $text | Should -Match '(?s)foreach\s*\(\$flag\s+in\s+\$qualityFalseFlags\).*?\[bool\]\$evidence\.\$flag.*?throw'

            foreach ($requiredToken in @(
                'SchemaVersion', 'Scenario', 'Quality', 'SAFE_FAILURE_DISCLOSURE', 'HARNESS_LEDGER_EXACT',
                'MUTATION_SPY_COUNTS', 'WORKER_EVIDENCE', 'TRUSTED_PROCESS_SEQUENCE',
                'TRUSTED_PROCESS_EXPECTED_COUNT', 'TRUSTED_PROCESS_ACTUAL_COUNT',
                'TRUSTED_HARNESS_PROCESS_COUNT', 'HARNESS_LEDGER', 'CLEANUP_OUTCOME',
                $expectedQualityPropertySet, $expectedMutationSpySet, $expectedWorkerEngineSet,
                $expectedTrustedProcessSequence, $expectedHarnessLedgerSequence
            )) {
                $text | Should -Match ([regex]::Escape($requiredToken))
            }
            $text | Should -Match '(?s)\$evidence\.PSObject\.Properties\.Name.*?Sort-Object.*?-join.*?-cne'
            $text | Should -Match '(?s)MUTATION_SPY_COUNTS.*?PSObject\.Properties.*?-join.*?-cne'
            $text | Should -Match '(?s)MUTATION_SPY_COUNTS.*?PSObject\.Properties.*?Value\s+-ne\s+0.*?throw'
            $text | Should -Match '(?s)WORKER_EVIDENCE.*?Engine.*?-join.*?-cne'
            $text | Should -Match '(?s)TRUSTED_PROCESS_SEQUENCE.*?RuleId.*?-join.*?-cne'
            $text | Should -Match '(?s)HARNESS_LEDGER.*?RuleId.*?-join.*?-cne'
            $text | Should -Match '(?s)TRUSTED_PROCESS_EXPECTED_COUNT.*?-ne.*?TRUSTED_PROCESS_ACTUAL_COUNT'
            $text | Should -Match '(?s)TRUSTED_PROCESS_ACTUAL_COUNT.*?-ne.*?TRUSTED_HARNESS_PROCESS_COUNT'
            $text | Should -Match '(?s)SchemaVersion.*?-ne\s+2'
            $text | Should -Match "(?s)Scenario.*?-cne\s+'Quality'"
            $text | Should -Match '(?s)SAFE_FAILURE_DISCLOSURE.*?-ne\s+\$true'
            $text | Should -Match "(?s)CLEANUP_OUTCOME.*?-cne\s+'Succeeded'"
        }
    }

    It 'requires complete four-layer release simulation evidence and exact cleanup' {
        $releaseZeroMetrics = @(
            'SourceSecretFindings', 'StagingSecretFindings', 'ZipSecretFindings', 'ExtractSecretFindings',
            'TrustedHarnessProcessCount', 'TrustedHarnessNetworkCount',
            'FORBIDDEN_RESOURCE_ACCESS_COUNT', 'OUTSIDE_SANDBOX_WRITE_COUNT',
            'PRODUCT_LIVE_PROCESS_SPAWN_COUNT', 'PRODUCT_NETWORK_REQUEST_COUNT',
            'REAL_REGISTRY_ACCESS_COUNT', 'UNAPPROVED_HARNESS_PROCESS_COUNT',
            'UNAPPROVED_HARNESS_NETWORK_COUNT', 'SECRET_FINDINGS',
            'UNEXPECTED_LEDGER_ENTRY_COUNT'
        )
        $releaseTrueFlags = @(
            'ZipInventoryExact', 'ExtractInventoryExact', 'ContentHashesExact',
            'SpecialPathValidated', 'HarnessLedgerExact'
        )
        $releaseFalseFlags = @(
            'Changed', 'SourcePackageChanged', 'LIVE_PROVIDER_LOADED',
            'REPOSITORY_CONTENT_CHANGED'
        )
        $expectedReleasePropertySet = 'Changed,CleanupOutcome,ContentHashesExact,ExtractFileCount,ExtractInventoryExact,ExtractSecretFindings,FORBIDDEN_RESOURCE_ACCESS_COUNT,HarnessLedgerExact,LIVE_PROVIDER_LOADED,Mode,Operation,OUTSIDE_SANDBOX_WRITE_COUNT,PackageFileCount,PRODUCT_LIVE_PROCESS_SPAWN_COUNT,PRODUCT_NETWORK_REQUEST_COUNT,REAL_REGISTRY_ACCESS_COUNT,REPOSITORY_CONTENT_CHANGED,RepositoryDirectoryCount,RepositoryFileCount,SchemaVersion,SECRET_FINDINGS,SourcePackageChanged,SourceSecretFindings,SpecialPathValidated,StagingSecretFindings,Status,TrustedHarnessFileSystemCount,TrustedHarnessNetworkCount,TrustedHarnessProcessCount,UNAPPROVED_HARNESS_NETWORK_COUNT,UNAPPROVED_HARNESS_PROCESS_COUNT,UNEXPECTED_LEDGER_ENTRY_COUNT,ZipCompression,ZipDeterministic,ZipEntryCount,ZipEntryOrder,ZipEntryTimestampUtc,ZipInventoryExact,ZipSecretFindings'

        foreach ($name in @('ci.yml', 'release-dry-run.yml')) {
            $text = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot ".github\workflows\$name"))
            foreach ($propertyName in $releaseZeroMetrics + $releaseTrueFlags + $releaseFalseFlags) {
                $text | Should -Match ("(?<![A-Za-z0-9_]){0}(?![A-Za-z0-9_])" -f [regex]::Escape($propertyName))
            }
            $text | Should -Match '\$releaseZeroMetrics'
            $text | Should -Match '(?s)foreach\s*\(\$metric\s+in\s+\$releaseZeroMetrics\).*?\[long\]\$(?:result|releaseEvidence)\.\$metric\s+-ne\s+0.*?throw'
            $text | Should -Match '\$releaseTrueFlags'
            $text | Should -Match '(?s)foreach\s*\(\$flag\s+in\s+\$releaseTrueFlags\).*?\[bool\]\$(?:result|releaseEvidence)\.\$flag.*?-ne\s+\$true.*?throw'
            $text | Should -Match '\$releaseFalseFlags'
            $text | Should -Match '(?s)foreach\s*\(\$flag\s+in\s+\$releaseFalseFlags\).*?\[bool\]\$(?:result|releaseEvidence)\.\$flag.*?throw'

            foreach ($requiredToken in @(
                'SchemaVersion', 'ReleaseSimulation', 'DryRun', 'SUCCEEDED',
                'PackageFileCount', 'ZipEntryCount', 'ExtractFileCount',
                'TrustedHarnessFileSystemCount', 'CleanupOutcome',
                $expectedReleasePropertySet
            )) {
                $text | Should -Match ([regex]::Escape($requiredToken))
            }
            $text | Should -Match '(?s)\$(?:result|releaseEvidence)\.PSObject\.Properties\.Name.*?Sort-Object.*?-join.*?-cne'
            $text | Should -Match '(?s)SchemaVersion.*?-ne\s+1'
            $text | Should -Match "(?s)Operation.*?-cne\s+'ReleaseSimulation'"
            $text | Should -Match "(?s)Mode.*?-cne\s+'DryRun'"
            $text | Should -Match "(?s)Status.*?-cne\s+'SUCCEEDED'"
            $text | Should -Match '(?s)PackageFileCount.*?-le\s+0'
            $text | Should -Match '(?s)ZipEntryCount.*?-ne.*?PackageFileCount'
            $text | Should -Match '(?s)ExtractFileCount.*?-ne.*?PackageFileCount'
            $text | Should -Match '(?s)TrustedHarnessFileSystemCount.*?-ne\s+16'
            $text | Should -Match "(?s)CleanupOutcome.*?-cne\s+'Succeeded'"
        }
    }
}
