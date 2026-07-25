function Get-CddsiQualitySetPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [ValidateSet('AllBlocking', 'ProductReleaseBlocking', 'HistoricalDiagnostic')]
        [string]$QualitySet
    )

    Set-StrictMode -Version Latest
    $ErrorActionPreference = 'Stop'

    function Get-OrdinalSortedStrings {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]]$Value
        )

        [string[]]$copy = @($Value)
        [Array]::Sort($copy, [StringComparer]::Ordinal)
        return $copy
    }

    function Assert-ExactKeys {
        param(
            [Parameter(Mandatory = $true)]
            [object]$Value,

            [Parameter(Mandatory = $true)]
            [string[]]$Expected,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        if (-not ($Value -is [Collections.IDictionary])) {
            throw "$Label must be a dictionary."
        }

        [string[]]$actualNames = @($Value.Keys | ForEach-Object { [string]$_ })
        $actualNames = @(Get-OrdinalSortedStrings -Value $actualNames)
        [string[]]$expectedNames = @(Get-OrdinalSortedStrings -Value $Expected)
        if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) {
            throw "$Label has an unexpected schema."
        }
    }

    function Assert-ExactStringSequence {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]]$Actual,

            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]]$Expected,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        if ($Actual.Count -ne $Expected.Count) {
            throw "$Label has an unexpected count."
        }

        for ($index = 0; $index -lt $Expected.Count; $index++) {
            if ($Actual[$index] -cne $Expected[$index]) {
                throw "$Label has an unexpected value or order."
            }
        }
    }

    function Get-Utf8Sha256 {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyString()]
            [string]$Text
        )

        $encoding = New-Object System.Text.UTF8Encoding($false)
        $bytes = $encoding.GetBytes($Text)
        $sha256 = [Security.Cryptography.SHA256]::Create()
        try {
            return ([BitConverter]::ToString($sha256.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha256.Dispose()
        }
    }

    function Get-SequenceSha256 {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [string[]]$Value
        )

        if ($Value.Count -eq 0) {
            return Get-Utf8Sha256 -Text ''
        }

        return Get-Utf8Sha256 -Text (($Value -join "`n") + "`n")
    }

    function Assert-SafeRelativePath {
        param(
            [Parameter(Mandatory = $true)]
            [string]$RelativePath,

            [Parameter(Mandatory = $true)]
            [string]$RootFullPath,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        if (
            [string]::IsNullOrWhiteSpace($RelativePath) -or
            $RelativePath.Length -gt 260 -or
            $RelativePath -match '[\x00-\x1f\x7f]' -or
            $RelativePath.Contains('\') -or
            $RelativePath.Contains(':') -or
            $RelativePath.StartsWith('/') -or
            $RelativePath.EndsWith('/') -or
            $RelativePath.Contains('//')
        ) {
            throw "$Label is not a safe repository-relative path."
        }

        [string[]]$segments = @($RelativePath.Split('/'))
        if ($segments.Count -lt 2) {
            throw "$Label must be rooted below the tests directory."
        }
        foreach ($segment in $segments) {
            if (
                [string]::IsNullOrWhiteSpace($segment) -or
                $segment -ceq '.' -or
                $segment -ceq '..'
            ) {
                throw "$Label contains an unsafe path segment."
            }
        }
        if ($segments[0] -cne 'tests') {
            throw "$Label must be rooted below the tests directory."
        }

        $combined = [IO.Path]::GetFullPath((Join-Path $RootFullPath ($RelativePath.Replace('/', '\'))))
        $rootPrefix = $RootFullPath.TrimEnd('\') + '\'
        if (-not $combined.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Label resolves outside the repository root."
        }

        $roundTrip = $combined.Substring($rootPrefix.Length).Replace('\', '/')
        if ($roundTrip -cne $RelativePath) {
            throw "$Label is not in canonical relative-path form."
        }

        return $combined
    }

    function Assert-NoReparsePath {
        param(
            [Parameter(Mandatory = $true)]
            [string]$FullPath,

            [Parameter(Mandatory = $true)]
            [string]$RootFullPath,

            [Parameter(Mandatory = $true)]
            [string]$Label
        )

        $rootItem = Get-Item -LiteralPath $RootFullPath -Force -ErrorAction Stop
        if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'Repository root must not be a reparse point.'
        }

        $rootPrefix = $RootFullPath.TrimEnd('\') + '\'
        if (-not $FullPath.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Label resolves outside the repository root."
        }

        $relative = $FullPath.Substring($rootPrefix.Length)
        $cursor = $RootFullPath
        foreach ($segment in @($relative.Split('\'))) {
            $cursor = Join-Path $cursor $segment
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "$Label traverses a reparse point."
            }
        }
    }

    function Get-TestTreeFilePaths {
        param(
            [Parameter(Mandatory = $true)]
            [string]$TestsRoot,

            [Parameter(Mandatory = $true)]
            [string]$RootFullPath
        )

        $result = New-Object 'System.Collections.Generic.List[string]'
        $pending = New-Object 'System.Collections.Generic.Stack[string]'
        $pending.Push($TestsRoot)

        while ($pending.Count -gt 0) {
            $directoryPath = $pending.Pop()
            $directory = Get-Item -LiteralPath $directoryPath -Force -ErrorAction Stop
            if (($directory.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'The tests tree contains a directory reparse point.'
            }

            foreach ($item in @(Get-ChildItem -LiteralPath $directoryPath -Force -ErrorAction Stop)) {
                if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'The tests tree contains a reparse point.'
                }
                if ($item.PSIsContainer) {
                    $pending.Push($item.FullName)
                    continue
                }

                $rootPrefix = $RootFullPath.TrimEnd('\') + '\'
                if (-not $item.FullName.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)) {
                    throw 'A tests-tree item resolves outside the repository root.'
                }
                $result.Add($item.FullName.Substring($rootPrefix.Length).Replace('\', '/'))
            }
        }

        return @(Get-OrdinalSortedStrings -Value @($result))
    }

    function Get-FileSha256Lower {
        param(
            [Parameter(Mandatory = $true)]
            [string]$Path
        )

        return ([string](Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash).ToLowerInvariant()
    }

    $rootFullPath = [IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $rootFullPath -PathType Container)) {
        throw 'RepositoryRoot must name an existing directory.'
    }
    $rootItem = Get-Item -LiteralPath $rootFullPath -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw 'RepositoryRoot must not be a reparse point.'
    }

    $classificationPath = Join-Path $rootFullPath 'config\product-release-gate.psd1'
    $dependencyPath = Join-Path $rootFullPath 'config\dev-dependencies.psd1'
    foreach ($manifest in @(
            @{ Path = $classificationPath; Label = 'Classification manifest' }
            @{ Path = $dependencyPath; Label = 'Dependency manifest' }
        )) {
        if (-not (Test-Path -LiteralPath $manifest.Path -PathType Leaf)) {
            throw ($manifest.Label + ' is missing.')
        }
        Assert-NoReparsePath -FullPath $manifest.Path -RootFullPath $rootFullPath -Label $manifest.Label
    }

    $classificationManifestSha256 = Get-FileSha256Lower -Path $classificationPath
    $dependencyManifestSha256 = Get-FileSha256Lower -Path $dependencyPath
    $classification = Import-PowerShellDataFile -LiteralPath $classificationPath -ErrorAction Stop
    $dependencies = Import-PowerShellDataFile -LiteralPath $dependencyPath -ErrorAction Stop

    Assert-ExactKeys -Value $classification -Expected @(
        'ContractVersion'
        'EnforcementPhase'
        'HistoricalDiagnosticFiles'
        'ProductReleaseBlockingFiles'
        'SchemaVersion'
        'Scope'
    ) -Label 'Classification manifest'
    if (
        -not ($classification.SchemaVersion -is [int]) -or
        $classification.SchemaVersion -ne 1 -or
        $classification.ContractVersion -cne 'D-026' -or
        $classification.EnforcementPhase -cne 'NamedProductReleaseGate'
    ) {
        throw 'Classification manifest identity is not the active D-026 named-gate contract.'
    }

    Assert-ExactKeys -Value $classification.Scope -Expected @(
        'ExpectedPesterTestCount'
        'ExpectedTrackedFileCount'
        'PathComparison'
        'RootRelativePath'
    ) -Label 'Classification scope'
    if (
        $classification.Scope.RootRelativePath -cne 'tests' -or
        $classification.Scope.PathComparison -cne 'Ordinal' -or
        -not ($classification.Scope.ExpectedTrackedFileCount -is [int]) -or
        $classification.Scope.ExpectedTrackedFileCount -ne 47 -or
        -not ($classification.Scope.ExpectedPesterTestCount -is [int]) -or
        $classification.Scope.ExpectedPesterTestCount -ne 42
    ) {
        throw 'Classification scope is not the expected 47-file/42-test contract.'
    }

    Assert-ExactKeys -Value $dependencies -Expected @(
        'IsolationEvidenceSuites'
        'Pester'
        'QualityShards'
        'SchemaVersion'
    ) -Label 'Dependency manifest'
    if (-not ($dependencies.SchemaVersion -is [int]) -or $dependencies.SchemaVersion -ne 1) {
        throw 'Dependency manifest schema version is not supported.'
    }

    Assert-ExactKeys -Value $dependencies.Pester -Expected @(
        'ExpectedFileCount'
        'ExpectedLicenseBytes'
        'ExpectedLicenseSha256'
        'ExpectedManifestSha256'
        'ExpectedTotalBytes'
        'ExpectedTreeSha256'
        'LicenseRelativePath'
        'ManifestRelativePath'
        'OfficialGalleryUrl'
        'OfficialLicenseUrl'
        'OfficialProjectUrl'
        'ProvenanceStatus'
        'RootRelativePath'
        'TreeHashFormat'
        'Version'
    ) -Label 'Dependency manifest Pester lock'
    foreach ($name in @(
            'ExpectedFileCount'
            'ExpectedLicenseBytes'
            'ExpectedTotalBytes'
        )) {
        if (-not ($dependencies.Pester[$name] -is [int]) -or [int]$dependencies.Pester[$name] -le 0) {
            throw 'Dependency manifest Pester lock has an invalid integer field.'
        }
    }
    foreach ($name in @(
            'ExpectedLicenseSha256'
            'ExpectedManifestSha256'
            'ExpectedTreeSha256'
        )) {
        if ([string]$dependencies.Pester[$name] -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Dependency manifest Pester lock has an invalid SHA-256 field.'
        }
    }
    foreach ($name in @(
            'LicenseRelativePath'
            'ManifestRelativePath'
            'OfficialGalleryUrl'
            'OfficialLicenseUrl'
            'OfficialProjectUrl'
            'ProvenanceStatus'
            'RootRelativePath'
            'TreeHashFormat'
            'Version'
        )) {
        if (-not ($dependencies.Pester[$name] -is [string]) -or [string]::IsNullOrWhiteSpace([string]$dependencies.Pester[$name])) {
            throw 'Dependency manifest Pester lock has an invalid string field.'
        }
    }

    $isolationSuites = @($dependencies.IsolationEvidenceSuites)
    if ($isolationSuites.Count -ne 3) {
        throw 'Dependency manifest must contain exactly three isolation evidence suites.'
    }
    $isolationPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($suite in $isolationSuites) {
        Assert-ExactKeys -Value $suite -Expected @('ExpectedTestCount', 'RelativePath') -Label 'Isolation evidence suite'
        $null = Assert-SafeRelativePath -RelativePath ([string]$suite.RelativePath) -RootFullPath $rootFullPath -Label 'Isolation evidence suite path'
        if (-not ($suite.ExpectedTestCount -is [int]) -or [int]$suite.ExpectedTestCount -le 0) {
            throw 'Isolation evidence suite test count is invalid.'
        }
        if (-not $isolationPathSet.Add([string]$suite.RelativePath)) {
            throw 'Isolation evidence suite paths must be unique.'
        }
    }

    $productEntries = @($classification.ProductReleaseBlockingFiles)
    $historicalEntries = @($classification.HistoricalDiagnosticFiles)
    if ($productEntries.Count -ne 34 -or $historicalEntries.Count -ne 13) {
        throw 'Classification manifest must contain exactly 34 product files and 13 historical files.'
    }

    $allClassificationPaths = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $productPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $historicalPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $classificationKindByPath = New-Object 'System.Collections.Generic.Dictionary[string,string]' ([StringComparer]::Ordinal)
    $productPesterPaths = New-Object 'System.Collections.Generic.List[string]'
    $historicalPesterPaths = New-Object 'System.Collections.Generic.List[string]'
    $productFixtureCount = 0
    $productSupportCount = 0

    foreach ($setDefinition in @(
            @{ Name = 'Product'; Entries = $productEntries; PathSet = $productPathSet }
            @{ Name = 'Historical'; Entries = $historicalEntries; PathSet = $historicalPathSet }
        )) {
        [string[]]$encounteredPaths = @($setDefinition.Entries | ForEach-Object { [string]$_.RelativePath })
        [string[]]$sortedEncounteredPaths = @(Get-OrdinalSortedStrings -Value $encounteredPaths)
        Assert-ExactStringSequence -Actual $encounteredPaths -Expected $sortedEncounteredPaths -Label ($setDefinition.Name + ' classification order')

        foreach ($entry in @($setDefinition.Entries)) {
            Assert-ExactKeys -Value $entry -Expected @('FileKind', 'ReasonCode', 'RelativePath') -Label ($setDefinition.Name + ' classification entry')
            $relativePath = [string]$entry.RelativePath
            $fullPath = Assert-SafeRelativePath -RelativePath $relativePath -RootFullPath $rootFullPath -Label ($setDefinition.Name + ' classification path')
            if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
                throw ($setDefinition.Name + ' classification path is missing.')
            }
            Assert-NoReparsePath -FullPath $fullPath -RootFullPath $rootFullPath -Label ($setDefinition.Name + ' classification path')

            if (-not $setDefinition.PathSet.Add($relativePath) -or -not $allClassificationPaths.Add($relativePath)) {
                throw 'Classification paths must be unique and disjoint.'
            }
            $classificationKindByPath[$relativePath] = [string]$entry.FileKind

            if ($setDefinition.Name -ceq 'Historical') {
                if (
                    [string]$entry.FileKind -cne 'PesterTest' -or
                    $relativePath -cnotmatch '\.Tests\.ps1$'
                ) {
                    throw 'Historical diagnostics may contain only Pester test files.'
                }
                $historicalPesterPaths.Add($relativePath)
                continue
            }

            switch -CaseSensitive ([string]$entry.FileKind) {
                'PesterTest' {
                    if (
                        [string]$entry.ReasonCode -cne 'CurrentProductReleaseTest' -or
                        $relativePath -cnotmatch '\.Tests\.ps1$'
                    ) {
                        throw 'Product Pester classification metadata is invalid.'
                    }
                    $productPesterPaths.Add($relativePath)
                }
                'SyntheticFixture' {
                    if ([string]$entry.ReasonCode -cne 'CurrentProductSyntheticFixture') {
                        throw 'Product fixture classification metadata is invalid.'
                    }
                    $productFixtureCount++
                }
                'SupportScript' {
                    if ([string]$entry.ReasonCode -cne 'CurrentProductSupportScript') {
                        throw 'Product support classification metadata is invalid.'
                    }
                    $productSupportCount++
                }
                default {
                    throw 'Product classification contains an unsupported file kind.'
                }
            }
        }
    }

    if (
        $productPesterPaths.Count -ne 29 -or
        $historicalPesterPaths.Count -ne 13 -or
        $productFixtureCount -ne 4 -or
        $productSupportCount -ne 1
    ) {
        throw 'Classification kind counts are not the expected 29/13/4/1 contract.'
    }

    [string[]]$expectedHistoricalPaths = @(
        'tests/Contract/FastLanePolicy.Tests.ps1'
        'tests/Contract/FastLaneReadiness.Tests.ps1'
        'tests/Contract/RealtimeRelay.Tests.ps1'
        'tests/Contract/RealtimeRelayForegroundControl.Tests.ps1'
        'tests/Contract/RealtimeRelayForegroundCycle.Tests.ps1'
        'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1'
        'tests/Contract/VmReset.Tests.ps1'
        'tests/Contract/VmResetLiveAdapter.Tests.ps1'
        'tests/Contract/WindowsVmResetProvider.Tests.ps1'
        'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1'
        'tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1'
        'tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1'
        'tests/Unit/VmTestRelay.Tests.ps1'
    )
    Assert-ExactStringSequence -Actual @($historicalPesterPaths) -Expected $expectedHistoricalPaths -Label 'Historical diagnostic allowlist'

    $expectedHistoricalReasonByPath = @{
        'tests/Contract/FastLanePolicy.Tests.ps1' = 'RetiredFastLaneTransport'
        'tests/Contract/FastLaneReadiness.Tests.ps1' = 'RetiredFastLaneTransport'
        'tests/Contract/RealtimeRelay.Tests.ps1' = 'RetiredRealtimeRelayTransport'
        'tests/Contract/RealtimeRelayForegroundControl.Tests.ps1' = 'RetiredRealtimeRelayTransport'
        'tests/Contract/RealtimeRelayForegroundCycle.Tests.ps1' = 'RetiredRealtimeRelayTransport'
        'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1' = 'RetiredRealtimeRelayTransport'
        'tests/Contract/VmReset.Tests.ps1' = 'RetiredVmRelayResetControl'
        'tests/Contract/VmResetLiveAdapter.Tests.ps1' = 'RetiredVmRelayResetControl'
        'tests/Contract/WindowsVmResetProvider.Tests.ps1' = 'RetiredVmRelayResetControl'
        'tests/HostSandbox/FastLaneGitOutbox.Tests.ps1' = 'RetiredFastLaneTransport'
        'tests/HostSandbox/FastLaneOnboardingBundle.Tests.ps1' = 'RetiredFastLaneTransport'
        'tests/HostSandbox/FastLaneSyntheticRehearsal.Tests.ps1' = 'RetiredFastLaneTransport'
        'tests/Unit/VmTestRelay.Tests.ps1' = 'RetiredVmRelayResetControl'
    }
    foreach ($entry in $historicalEntries) {
        $path = [string]$entry.RelativePath
        if (
            -not $expectedHistoricalReasonByPath.ContainsKey($path) -or
            [string]$entry.ReasonCode -cne [string]$expectedHistoricalReasonByPath[$path]
        ) {
            throw 'Historical diagnostic metadata differs from the exact retired-operator allowlist.'
        }
    }

    [string[]]$protectedProductPaths = @(
        'tests/Contract/Acceptance.Tests.ps1'
        'tests/Contract/Config.Tests.ps1'
        'tests/Contract/CredentialHelperRelease.Tests.ps1'
        'tests/Contract/DesktopMsix.Tests.ps1'
        'tests/Contract/Encoding.Tests.ps1'
        'tests/Contract/GitSupplyChain.Tests.ps1'
        'tests/Contract/IsolationEvidence.Tests.ps1'
        'tests/Contract/LiveAdapters.Tests.ps1'
        'tests/Contract/OperatorCoordinationBoundary.Tests.ps1'
        'tests/Contract/Orchestrator.Tests.ps1'
        'tests/Contract/PublicFunctions.Tests.ps1'
        'tests/Contract/ReleaseArtifact.Tests.ps1'
        'tests/Contract/ReleaseFacts.Tests.ps1'
        'tests/Contract/SafetyBoundary.Tests.ps1'
        'tests/Contract/StagePolicy.Tests.ps1'
        'tests/Contract/VmCalibration.Tests.ps1'
        'tests/HostSandbox/CandidateBuild.Tests.ps1'
        'tests/HostSandbox/HostSandbox.Tests.ps1'
        'tests/HostSandbox/ReleaseSimulation.Tests.ps1'
    )
    foreach ($protectedPath in $protectedProductPaths) {
        if (-not $productPathSet.Contains($protectedPath) -or $historicalPathSet.Contains($protectedPath)) {
            throw 'A protected current-product test was moved outside the product release gate.'
        }
    }

    $testsRoot = Join-Path $rootFullPath 'tests'
    if (-not (Test-Path -LiteralPath $testsRoot -PathType Container)) {
        throw 'The classified tests root is missing.'
    }
    Assert-NoReparsePath -FullPath $testsRoot -RootFullPath $rootFullPath -Label 'Tests root'
    [string[]]$actualTestTreePaths = @(Get-TestTreeFilePaths -TestsRoot $testsRoot -RootFullPath $rootFullPath)
    [string[]]$classifiedPaths = @(Get-OrdinalSortedStrings -Value @($allClassificationPaths))
    Assert-ExactStringSequence -Actual $actualTestTreePaths -Expected $classifiedPaths -Label 'Classified tests-tree closure'
    if ($classifiedPaths.Count -ne 47) {
        throw 'Classified tests-tree closure must contain exactly 47 files.'
    }

    $shards = @($dependencies.QualityShards)
    [string[]]$expectedShardIds = @(
        'C01'
        'C02'
        'C03'
        'C04'
        'C05'
        'C06'
        'C07'
        'C08'
        'U01'
        'U02'
        'H01'
        'H02'
        'H03'
    )
    if ($shards.Count -ne $expectedShardIds.Count) {
        throw 'Dependency manifest must contain exactly 13 quality shards.'
    }

    $manifestPesterPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $manifestPesterPaths = New-Object 'System.Collections.Generic.List[string]'
    for ($shardIndex = 0; $shardIndex -lt $shards.Count; $shardIndex++) {
        $shard = $shards[$shardIndex]
        Assert-ExactKeys -Value $shard -Expected @('Paths', 'ShardId') -Label 'Quality shard'
        if ([string]$shard.ShardId -cne $expectedShardIds[$shardIndex]) {
            throw 'Quality shard identifiers or order differ from the exact manifest contract.'
        }
        [string[]]$shardPaths = @($shard.Paths | ForEach-Object { [string]$_ })
        if ($shardPaths.Count -eq 0) {
            throw 'Dependency manifest quality shards must not be empty.'
        }
        foreach ($shardPath in $shardPaths) {
            $null = Assert-SafeRelativePath -RelativePath $shardPath -RootFullPath $rootFullPath -Label 'Quality shard path'
            if (
                $shardPath -cnotmatch '\.Tests\.ps1$' -or
                -not $classificationKindByPath.ContainsKey($shardPath) -or
                [string]$classificationKindByPath[$shardPath] -cne 'PesterTest'
            ) {
                throw 'Quality shard path is not a classified Pester test.'
            }
            if (-not $manifestPesterPathSet.Add($shardPath)) {
                throw 'Quality shard Pester paths must be globally unique.'
            }
            $manifestPesterPaths.Add($shardPath)
        }
    }

    [string[]]$classifiedPesterPaths = @(
        Get-OrdinalSortedStrings -Value @(
            @($productPesterPaths) + @($historicalPesterPaths)
        )
    )
    [string[]]$sortedManifestPesterPaths = @(Get-OrdinalSortedStrings -Value @($manifestPesterPaths))
    Assert-ExactStringSequence -Actual $sortedManifestPesterPaths -Expected $classifiedPesterPaths -Label 'Quality-shard/classification Pester closure'
    if ($manifestPesterPaths.Count -ne 42) {
        throw 'Quality-shard Pester closure must contain exactly 42 files.'
    }
    foreach ($suitePath in $isolationPathSet) {
        if (-not $manifestPesterPathSet.Contains($suitePath)) {
            throw 'An isolation evidence suite is missing from the quality-shard closure.'
        }
    }

    $selectedSet = switch -CaseSensitive ($QualitySet) {
        'AllBlocking' {
            $manifestPesterPathSet
            break
        }
        'ProductReleaseBlocking' {
            $productPathSet
            break
        }
        'HistoricalDiagnostic' {
            $historicalPathSet
            break
        }
        default {
            throw 'Unsupported quality set.'
        }
    }

    $selectedFilePaths = New-Object 'System.Collections.Generic.List[string]'
    $selectedShards = New-Object 'System.Collections.Generic.List[object]'
    foreach ($shard in $shards) {
        $selectedShardPaths = New-Object 'System.Collections.Generic.List[string]'
        foreach ($path in @($shard.Paths)) {
            $relativePath = [string]$path
            if ($selectedSet.Contains($relativePath)) {
                $selectedShardPaths.Add($relativePath)
                $selectedFilePaths.Add($relativePath)
            }
        }
        if ($selectedShardPaths.Count -eq 0) {
            continue
        }

        [string[]]$selectedShardPathArray = @($selectedShardPaths)
        $selectedShards.Add([pscustomobject][ordered]@{
            ShardId = [string]$shard.ShardId
            Paths = $selectedShardPathArray
            PathsSha256 = Get-SequenceSha256 -Value $selectedShardPathArray
        })
    }

    [string[]]$selectedFilePathArray = @($selectedFilePaths)
    [string[]]$selectedPesterPathArray = @($selectedFilePaths)
    $expectedCounts = switch -CaseSensitive ($QualitySet) {
        'AllBlocking' {
            @{ FileCount = 42; ShardCount = 13; WorkerCount = 28; ProcessCount = 31; LedgerEntryCount = 68 }
            break
        }
        'ProductReleaseBlocking' {
            @{ FileCount = 29; ShardCount = 8; WorkerCount = 18; ProcessCount = 21; LedgerEntryCount = 48 }
            break
        }
        'HistoricalDiagnostic' {
            @{ FileCount = 13; ShardCount = 9; WorkerCount = 20; ProcessCount = 23; LedgerEntryCount = 52 }
            break
        }
        default {
            throw 'Unsupported quality set.'
        }
    }

    $computedWorkerCount = 2 * (1 + $selectedShards.Count)
    $computedProcessCount = $computedWorkerCount + 3
    $computedLedgerEntryCount = (2 * $computedProcessCount) + 6
    if (
        $selectedFilePathArray.Count -ne [int]$expectedCounts.FileCount -or
        $selectedPesterPathArray.Count -ne [int]$expectedCounts.FileCount -or
        $selectedShards.Count -ne [int]$expectedCounts.ShardCount -or
        $computedWorkerCount -ne [int]$expectedCounts.WorkerCount -or
        $computedProcessCount -ne [int]$expectedCounts.ProcessCount -or
        $computedLedgerEntryCount -ne [int]$expectedCounts.LedgerEntryCount
    ) {
        throw 'Selected quality-set topology differs from the exact D-026 execution profile.'
    }

    $selectedFilePathsSha256 = Get-SequenceSha256 -Value $selectedFilePathArray
    $selectedPesterPathsSha256 = Get-SequenceSha256 -Value $selectedPesterPathArray
    $shardPolicyLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($shard in $selectedShards) {
        $shardPolicyLines.Add('ShardId=' + [string]$shard.ShardId)
        $shardPolicyLines.Add('PathsSha256=' + [string]$shard.PathsSha256)
        foreach ($path in @($shard.Paths)) {
            $shardPolicyLines.Add('Path=' + [string]$path)
        }
    }
    $selectedShardPolicySha256 = Get-SequenceSha256 -Value @($shardPolicyLines)

    $assertionFailureDisposition = if ($QualitySet -ceq 'HistoricalDiagnostic') {
        'ReportOnlyAfterCompleteTestFailure'
    }
    else {
        'Blocking'
    }

    $canonicalLines = New-Object 'System.Collections.Generic.List[string]'
    foreach ($line in @(
            'SchemaVersion=1'
            'ContractVersion=D-026'
            ('QualitySet=' + $QualitySet)
            ('AssertionFailureDisposition=' + $assertionFailureDisposition)
            ('ClassificationManifestSha256=' + $classificationManifestSha256)
            ('DependencyManifestSha256=' + $dependencyManifestSha256)
            ('SelectedFilePathsSha256=' + $selectedFilePathsSha256)
            ('SelectedPesterPathsSha256=' + $selectedPesterPathsSha256)
            ('SelectedShardPolicySha256=' + $selectedShardPolicySha256)
            ('FileCount=' + [string]$selectedFilePathArray.Count)
            ('PesterFileCount=' + [string]$selectedPesterPathArray.Count)
            ('ShardCount=' + [string]$selectedShards.Count)
            ('WorkerCount=' + [string]$computedWorkerCount)
            ('ProcessCount=' + [string]$computedProcessCount)
            ('LedgerEntryCount=' + [string]$computedLedgerEntryCount)
        )) {
        $canonicalLines.Add($line)
    }
    foreach ($path in $selectedFilePathArray) {
        $canonicalLines.Add('SelectedFilePath=' + $path)
    }
    foreach ($path in $selectedPesterPathArray) {
        $canonicalLines.Add('SelectedPesterPath=' + $path)
    }
    foreach ($line in $shardPolicyLines) {
        $canonicalLines.Add('QualityShard.' + $line)
    }
    $canonicalSha256 = Get-SequenceSha256 -Value @($canonicalLines)

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'D-026'
        QualitySet = $QualitySet
        AssertionFailureDisposition = $assertionFailureDisposition
        ClassificationManifestSha256 = $classificationManifestSha256
        DependencyManifestSha256 = $dependencyManifestSha256
        CanonicalSha256 = $canonicalSha256
        SelectedFilePathsSha256 = $selectedFilePathsSha256
        SelectedPesterPathsSha256 = $selectedPesterPathsSha256
        SelectedShardPolicySha256 = $selectedShardPolicySha256
        SelectedFilePaths = $selectedFilePathArray
        SelectedPesterPaths = $selectedPesterPathArray
        QualityShards = $selectedShards.ToArray()
        FileCount = $selectedFilePathArray.Count
        PesterFileCount = $selectedPesterPathArray.Count
        ShardCount = $selectedShards.Count
        WorkerCount = $computedWorkerCount
        ProcessCount = $computedProcessCount
        LedgerEntryCount = $computedLedgerEntryCount
    }
}
