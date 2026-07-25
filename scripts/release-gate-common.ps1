Set-StrictMode -Version Latest

function Get-CddsiGateSha256Text {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $encoding = New-Object System.Text.UTF8Encoding($false)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($encoding.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Get-CddsiGateCanonicalObjectSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    $json = ConvertTo-Json -InputObject $Value -Depth 100 -Compress
    return Get-CddsiGateSha256Text -Text ($json + "`n")
}

function Test-CddsiGateInteger {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    return ($Value -is [int] -or $Value -is [long])
}

function Assert-CddsiGateExactPropertySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if ($null -eq $Value) {
        throw "$Label is missing."
    }
    [string[]]$actualNames = @($Value.PSObject.Properties.Name | ForEach-Object { [string]$_ })
    [string[]]$expectedNames = @($Expected)
    [Array]::Sort($actualNames, [StringComparer]::Ordinal)
    [Array]::Sort($expectedNames, [StringComparer]::Ordinal)
    if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) {
        throw "$Label schema drift."
    }
}

function Get-CddsiGateExpectedProcessSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QualitySetPolicy
    )

    $sequence = New-Object System.Collections.Generic.List[string]
    $sequence.Add('GitInventory')
    foreach ($engine in @('PowerShell7', 'WindowsPowerShell')) {
        $sequence.Add('QualityStatic' + $engine)
        foreach ($shard in @($QualitySetPolicy.QualityShards)) {
            $sequence.Add(('QualityShard{0}{1}' -f $engine, [string]$shard.ShardId))
        }
    }
    $sequence.Add('GitDiffCheck')
    $sequence.Add('GitCachedDiffCheck')
    return $sequence.ToArray()
}

function Get-CddsiGateExpectedHarnessLedgerSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QualitySetPolicy
    )

    $sequence = New-Object System.Collections.Generic.List[string]
    foreach ($ruleId in @(
        'ValidateToolGrant',
        'ValidateToolGrant',
        'ValidateToolGrant',
        'CreateSandbox',
        'WriteOwnerMarker',
        'CreateSyntheticEnvironment',
        'GitInventory',
        'WriteRepositoryInventory'
    )) {
        $sequence.Add($ruleId)
    }
    foreach ($processRuleId in @(Get-CddsiGateExpectedProcessSequence -QualitySetPolicy $QualitySetPolicy)) {
        if ($processRuleId -in @('GitInventory', 'GitDiffCheck', 'GitCachedDiffCheck')) {
            continue
        }
        $sequence.Add($processRuleId)
        $sequence.Add('ReadWorkerEvidence')
    }
    $sequence.Add('GitDiffCheck')
    $sequence.Add('GitCachedDiffCheck')
    $sequence.Add('ScanSandboxArtifacts')
    $sequence.Add('CleanupSandbox')
    return $sequence.ToArray()
}

function Assert-CddsiGateExactStringSequence {
    [CmdletBinding()]
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
        throw "$Label count drift."
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        if ($Actual[$index] -cne $Expected[$index]) {
            throw "$Label value or order drift."
        }
    }
}

function Assert-CddsiGateNonNegativeInteger {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    if (-not (Test-CddsiGateInteger -Value $Value) -or [long]$Value -lt 0) {
        throw "$Label must be a non-negative integer."
    }
}

function Assert-CddsiGateFailedTestSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$FailedTests,

        [Parameter(Mandatory = $true)]
        [long]$FailedCount,

        [Parameter(Mandatory = $true)]
        [bool]$Truncated,

        [Parameter(Mandatory = $true)]
        [string[]]$AllowedRelativePaths,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Assert-CddsiGateNonNegativeInteger -Value $FailedCount -Label "$Label failed count"
    $entries = @($FailedTests)
    if (
        $entries.Count -ne $FailedCount -or
        $Truncated
    ) {
        throw "$Label failed-test summary count or truncation binding drift."
    }

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    foreach ($entry in $entries) {
        Assert-CddsiGateExactPropertySet -Value $entry -Expected @(
            'ErrorRecordCount',
            'Name',
            'RelativePath',
            'StartLine'
        ) -Label "$Label failed-test summary"
        Assert-CddsiGateNonNegativeInteger -Value $entry.StartLine `
            -Label "$Label failed-test source line"
        Assert-CddsiGateNonNegativeInteger -Value $entry.ErrorRecordCount `
            -Label "$Label failed-test error-record count"
        if (
            [long]$entry.StartLine -lt 1 -or
            [long]$entry.ErrorRecordCount -lt 1 -or
            [string]::IsNullOrWhiteSpace([string]$entry.Name) -or
            ([string]$entry.Name).Length -gt 512 -or
            $AllowedRelativePaths -cnotcontains [string]$entry.RelativePath
        ) {
            throw "$Label failed-test source binding is invalid."
        }

        $fullPath = [System.IO.Path]::GetFullPath(
            (Join-Path $root ([string]$entry.RelativePath)))
        if (-not $fullPath.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "$Label failed-test source escaped the repository."
        }
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $fullPath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        if (@($parseErrors).Count -ne 0) {
            throw "$Label failed-test source has syntax errors."
        }
        $matchingCommands = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.Extent.StartLineNumber -eq [long]$entry.StartLine -and
                $node.GetCommandName() -ceq 'It'
        }, $true))
        if (
            $matchingCommands.Count -ne 1 -or
            $matchingCommands[0].CommandElements.Count -lt 2 -or
            $matchingCommands[0].CommandElements[1] -isnot
                [System.Management.Automation.Language.StringConstantExpressionAst] -or
            [string]$matchingCommands[0].CommandElements[1].Value -cne [string]$entry.Name
        ) {
            throw "$Label failed-test static It binding drift."
        }
    }
}

function Assert-CddsiGateWorkerSandboxBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$WorkerEvidence
    )

    $workers = @($WorkerEvidence)
    if ($workers.Count -ne 2) {
        throw 'Quality aggregate worker count drift.'
    }
    foreach ($worker in $workers) {
        if ([string]$worker.SandboxBindingSha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Quality aggregate worker sandbox binding is invalid.'
        }
    }
    if (
        [string]$workers[0].SandboxBindingSha256 -cne
        [string]$workers[1].SandboxBindingSha256
    ) {
        throw 'Quality aggregate worker sandbox binding drift.'
    }
    return $true
}

function Assert-CddsiGateWorkerEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $WorkerEvidence,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PowerShell7', 'WindowsPowerShell')]
        [string]$Engine,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        $QualitySetPolicy,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Assert-CddsiGateExactPropertySet -Value $WorkerEvidence -Expected @(
        'Engine',
        'EvidenceType',
        'Measurements',
        'Provenance',
        'RunId',
        'SandboxBindingSha256',
        'SchemaVersion'
    ) -Label "$Engine aggregate worker evidence"
    if (
        -not (Test-CddsiGateInteger -Value $WorkerEvidence.SchemaVersion) -or
        [long]$WorkerEvidence.SchemaVersion -ne 2 -or
        [string]$WorkerEvidence.EvidenceType -cne 'CddsiWorkerIsolationEvidence' -or
        [string]$WorkerEvidence.Engine -cne $Engine -or
        [string]$WorkerEvidence.RunId -cne $RunId -or
        [string]$WorkerEvidence.SandboxBindingSha256 -cnotmatch '^[a-f0-9]{64}$'
    ) {
        throw "$Engine aggregate worker identity is invalid."
    }

    Assert-CddsiGateExactPropertySet -Value $WorkerEvidence.Measurements -Expected @(
        'AccessLedger',
        'AstSyntaxErrorCount',
        'LiveAdapterFileCount',
        'LiveProviderLoaded',
        'MutationSpyCounts',
        'Pester',
        'RepositoryContentChanged',
        'RequiredSuiteFailureCount',
        'RequiredSuiteResults',
        'SecretFindingCount',
        'ShardCompletionEvidence'
    ) -Label "$Engine aggregate worker measurements"
    foreach ($zeroName in @('AstSyntaxErrorCount', 'SecretFindingCount')) {
        if (
            -not (Test-CddsiGateInteger -Value $WorkerEvidence.Measurements.$zeroName) -or
            [long]$WorkerEvidence.Measurements.$zeroName -ne 0
        ) {
            throw "$Engine aggregate worker measurement is not integer zero: $zeroName."
        }
    }
    $boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $RepositoryRoot 'config\execution-boundaries.psd1')
    if (
        -not (Test-CddsiGateInteger -Value $WorkerEvidence.Measurements.LiveAdapterFileCount) -or
        [long]$WorkerEvidence.Measurements.LiveAdapterFileCount -ne @($boundary.Planes.LiveAdapters).Count -or
        $WorkerEvidence.Measurements.LiveProviderLoaded -isnot [bool] -or
        [bool]$WorkerEvidence.Measurements.LiveProviderLoaded -or
        $WorkerEvidence.Measurements.RepositoryContentChanged -isnot [bool] -or
        [bool]$WorkerEvidence.Measurements.RepositoryContentChanged
    ) {
        throw "$Engine aggregate worker static measurements are unsafe."
    }

    $access = $WorkerEvidence.Measurements.AccessLedger
    Assert-CddsiGateExactPropertySet -Value $access -Expected @(
        'ContextCount',
        'DryRunContextCount',
        'EntryCount',
        'ForbiddenResourceAccessCount',
        'OutsideSandboxWriteCount',
        'ProductLiveProcessSpawnCount',
        'ProductNetworkRequestCount',
        'RealRegistryAccessCount',
        'TestSafeContextCount',
        'UnexpectedLedgerEntryCount'
    ) -Label "$Engine aggregate access ledger"
    foreach ($binding in @(
        @{ Name = 'ContextCount'; Value = 2L },
        @{ Name = 'TestSafeContextCount'; Value = 1L },
        @{ Name = 'DryRunContextCount'; Value = 1L },
        @{ Name = 'EntryCount'; Value = 2L }
    )) {
        if (
            -not (Test-CddsiGateInteger -Value $access.($binding.Name)) -or
            [long]$access.($binding.Name) -ne [long]$binding.Value
        ) {
            throw "$Engine aggregate access-ledger scenario binding drift."
        }
    }
    foreach ($zeroName in @(
        'ForbiddenResourceAccessCount',
        'OutsideSandboxWriteCount',
        'ProductLiveProcessSpawnCount',
        'ProductNetworkRequestCount',
        'RealRegistryAccessCount',
        'UnexpectedLedgerEntryCount'
    )) {
        if (
            -not (Test-CddsiGateInteger -Value $access.$zeroName) -or
            [long]$access.$zeroName -ne 0
        ) {
            throw "$Engine aggregate access-ledger measurement is not integer zero: $zeroName."
        }
    }

    $mutationNames = @(
        'AppX',
        'Credential',
        'Environment',
        'Feature',
        'FileSystem',
        'Network',
        'Process',
        'Registry',
        'Restart',
        'Service'
    )
    Assert-CddsiGateExactPropertySet -Value $WorkerEvidence.Measurements.MutationSpyCounts `
        -Expected $mutationNames `
        -Label "$Engine aggregate mutation spy"
    foreach ($mutationName in $mutationNames) {
        $value = $WorkerEvidence.Measurements.MutationSpyCounts.$mutationName
        if (-not (Test-CddsiGateInteger -Value $value) -or [long]$value -ne 0) {
            throw "$Engine aggregate mutation-spy measurement is not integer zero: $mutationName."
        }
    }

    $pester = $WorkerEvidence.Measurements.Pester
    Assert-CddsiGateExactPropertySet -Value $pester -Expected @(
        'FailedBlocksCount',
        'FailedContainersCount',
        'FailedCount',
        'InconclusiveCount',
        'NotRunCount',
        'PassedCount',
        'Result',
        'SkippedCount',
        'TotalCount'
    ) -Label "$Engine aggregate Pester result"
    foreach ($countName in @(
        'FailedBlocksCount', 'FailedContainersCount', 'FailedCount', 'InconclusiveCount',
        'NotRunCount', 'PassedCount', 'SkippedCount', 'TotalCount'
    )) {
        Assert-CddsiGateNonNegativeInteger -Value $pester.$countName `
            -Label "$Engine aggregate Pester count $countName"
    }
    if (
        [long]$pester.TotalCount -le 0 -or
        [long]$pester.TotalCount -ne (
            [long]$pester.PassedCount +
            [long]$pester.FailedCount +
            [long]$pester.SkippedCount +
            [long]$pester.NotRunCount +
            [long]$pester.InconclusiveCount
        ) -or
        [long]$pester.SkippedCount -ne 0 -or
        [long]$pester.NotRunCount -ne 0 -or
        [long]$pester.InconclusiveCount -ne 0 -or
        [long]$pester.FailedBlocksCount -ne 0 -or
        [long]$pester.FailedContainersCount -ne 0
    ) {
        throw "$Engine aggregate Pester completion is incomplete."
    }
    $isHistorical = [string]$QualitySetPolicy.QualitySet -ceq 'HistoricalDiagnostic'
    if ($isHistorical) {
        if ([string]$pester.Result -ceq 'Passed') {
            if ([long]$pester.PassedCount -le 0 -or [long]$pester.FailedCount -ne 0) {
                throw "$Engine historical Pester passed completion is inconsistent."
            }
        }
        elseif ([string]$pester.Result -ceq 'Failed') {
            if ([long]$pester.FailedCount -le 0) {
                throw "$Engine historical Pester failed completion is inconsistent."
            }
        }
        else {
            throw "$Engine historical Pester result is invalid."
        }
    }
    elseif (
        [string]$pester.Result -cne 'Passed' -or
        [long]$pester.PassedCount -le 0 -or
        [long]$pester.FailedCount -ne 0
    ) {
        throw "$Engine product Pester result is not clean."
    }

    $profileShards = @($QualitySetPolicy.QualityShards)
    $shardCompletions = @($WorkerEvidence.Measurements.ShardCompletionEvidence)
    if ($shardCompletions.Count -ne $profileShards.Count) {
        throw "$Engine shard-completion evidence count drift."
    }
    $shardSums = [ordered]@{
        TotalCount            = 0L
        PassedCount           = 0L
        FailedCount           = 0L
        SkippedCount          = 0L
        NotRunCount           = 0L
        InconclusiveCount     = 0L
        FailedBlocksCount     = 0L
        FailedContainersCount = 0L
    }
    for ($shardIndex = 0; $shardIndex -lt $profileShards.Count; $shardIndex++) {
        $profileShard = $profileShards[$shardIndex]
        $completion = $shardCompletions[$shardIndex]
        Assert-CddsiGateExactPropertySet -Value $completion -Expected @(
            'DurationMilliseconds',
            'FailedBlocksCount',
            'FailedContainersCount',
            'FailedCount',
            'FailedTestEvidenceTruncated',
            'FailedTests',
            'InconclusiveCount',
            'NotRunCount',
            'PassedCount',
            'Result',
            'ShardId',
            'ShardPathsSha256',
            'SkippedCount',
            'TestFiles',
            'TotalCount'
        ) -Label "$Engine shard-completion evidence"
        if (
            [string]$completion.ShardId -cne [string]$profileShard.ShardId -or
            [string]$completion.ShardPathsSha256 -cne [string]$profileShard.PathsSha256
        ) {
            throw "$Engine shard-completion profile binding drift."
        }
        [string[]]$actualFiles = @($completion.TestFiles | ForEach-Object { [string]$_ })
        [string[]]$expectedFiles = @($profileShard.Paths | ForEach-Object { [string]$_ })
        Assert-CddsiGateExactStringSequence -Actual $actualFiles -Expected $expectedFiles `
            -Label "$Engine shard-completion file sequence"
        $expectedPathsSha256 = Get-CddsiGateSha256Text -Text (
            $(if ($expectedFiles.Count -eq 0) { '' } else { ($expectedFiles -join "`n") + "`n" })
        )
        if ([string]$completion.ShardPathsSha256 -cne $expectedPathsSha256) {
            throw "$Engine shard-completion path hash drift."
        }
        foreach ($countName in @(
            'DurationMilliseconds', 'FailedBlocksCount', 'FailedContainersCount', 'FailedCount',
            'InconclusiveCount', 'NotRunCount', 'PassedCount', 'SkippedCount', 'TotalCount'
        )) {
            Assert-CddsiGateNonNegativeInteger -Value $completion.$countName `
                -Label "$Engine $($completion.ShardId) $countName"
        }
        if (
            [long]$completion.TotalCount -le 0 -or
            [long]$completion.TotalCount -ne (
                [long]$completion.PassedCount +
                [long]$completion.FailedCount +
                [long]$completion.SkippedCount +
                [long]$completion.NotRunCount +
                [long]$completion.InconclusiveCount
            ) -or
            [long]$completion.SkippedCount -ne 0 -or
            [long]$completion.NotRunCount -ne 0 -or
            [long]$completion.InconclusiveCount -ne 0 -or
            [long]$completion.FailedBlocksCount -ne 0 -or
            [long]$completion.FailedContainersCount -ne 0
        ) {
            throw "$Engine shard completion is incomplete or contains infrastructure failure."
        }
        if ([string]$completion.Result -ceq 'Passed') {
            if ([long]$completion.PassedCount -le 0 -or [long]$completion.FailedCount -ne 0) {
                throw "$Engine passed shard completion is inconsistent."
            }
        }
        elseif ([string]$completion.Result -ceq 'Failed') {
            if (-not $isHistorical -or [long]$completion.FailedCount -le 0) {
                throw "$Engine failed shard completion is release-blocking."
            }
        }
        else {
            throw "$Engine shard completion result is invalid."
        }
        if ($completion.FailedTestEvidenceTruncated -isnot [bool]) {
            throw "$Engine shard failed-test truncation flag is invalid."
        }
        Assert-CddsiGateFailedTestSummary `
            -FailedTests @($completion.FailedTests) `
            -FailedCount ([long]$completion.FailedCount) `
            -Truncated ([bool]$completion.FailedTestEvidenceTruncated) `
            -AllowedRelativePaths $expectedFiles `
            -RepositoryRoot $RepositoryRoot `
            -Label "$Engine $($completion.ShardId)"
        foreach ($sumName in @($shardSums.Keys)) {
            $shardSums[$sumName] = [long]$shardSums[$sumName] + [long]$completion.$sumName
        }
    }
    foreach ($sumName in $shardSums.Keys) {
        if ([long]$pester.$sumName -ne [long]$shardSums[$sumName]) {
            throw "$Engine aggregate-to-shard Pester count drift: $sumName."
        }
    }

    $dependency = Import-PowerShellDataFile -LiteralPath (Join-Path $RepositoryRoot 'config\dev-dependencies.psd1')
    $selectedPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($path in @($QualitySetPolicy.SelectedPesterPaths)) {
        $null = $selectedPathSet.Add([string]$path)
    }
    $expectedSuites = @($dependency.IsolationEvidenceSuites | Where-Object {
        $selectedPathSet.Contains(([string]$_.RelativePath).Replace('\', '/'))
    })
    $actualSuites = @($WorkerEvidence.Measurements.RequiredSuiteResults)
    if ($actualSuites.Count -ne $expectedSuites.Count) {
        throw "$Engine required-suite evidence count drift."
    }
    $suiteFailureCount = 0L
    for ($suiteIndex = 0; $suiteIndex -lt $expectedSuites.Count; $suiteIndex++) {
        $expectedSuite = $expectedSuites[$suiteIndex]
        $actualSuite = $actualSuites[$suiteIndex]
        Assert-CddsiGateExactPropertySet -Value $actualSuite -Expected @(
            'RelativePath',
            'Result',
            'TestCount'
        ) -Label "$Engine required-suite evidence"
        if (
            [string]$actualSuite.RelativePath -cne ([string]$expectedSuite.RelativePath).Replace('\', '/') -or
            -not (Test-CddsiGateInteger -Value $actualSuite.TestCount) -or
            [long]$actualSuite.TestCount -ne [long]$expectedSuite.ExpectedTestCount -or
            [string]$actualSuite.Result -notin @('Passed', 'Failed') -or
            (-not $isHistorical -and [string]$actualSuite.Result -cne 'Passed')
        ) {
            throw "$Engine required-suite evidence binding drift."
        }
        if ([string]$actualSuite.Result -ceq 'Failed') {
            $suiteFailureCount++
        }
    }
    if (
        -not (Test-CddsiGateInteger -Value $WorkerEvidence.Measurements.RequiredSuiteFailureCount) -or
        [long]$WorkerEvidence.Measurements.RequiredSuiteFailureCount -ne $suiteFailureCount
    ) {
        throw "$Engine required-suite failure count drift."
    }

    Assert-CddsiGateExactPropertySet -Value $WorkerEvidence.Provenance -Expected @(
        'DependencyManifestSha256',
        'EngineGrantSha256',
        'ExecutionBoundaryManifestSha256',
        'FinalRepositoryManifestSha256',
        'InitialRepositoryManifestSha256',
        'MeasurementRuleVersion',
        'PesterTreeSha256',
        'QualityShardPolicySha256',
        'RepositoryInventorySha256',
        'RequiredSuiteSummarySha256'
    ) -Label "$Engine aggregate provenance"
    if ([string]$WorkerEvidence.Provenance.MeasurementRuleVersion -cne 'cddsi-worker-measurement-rules-v6') {
        throw "$Engine aggregate provenance rule version drift."
    }
    foreach ($property in $WorkerEvidence.Provenance.PSObject.Properties) {
        if (
            $property.Name -cne 'MeasurementRuleVersion' -and
            [string]$property.Value -cnotmatch '^[a-f0-9]{64}$'
        ) {
            throw "$Engine aggregate provenance hash is invalid: $($property.Name)."
        }
    }
    if (
        [string]$WorkerEvidence.Provenance.InitialRepositoryManifestSha256 -cne
        [string]$WorkerEvidence.Provenance.FinalRepositoryManifestSha256 -or
        [string]$WorkerEvidence.Provenance.DependencyManifestSha256 -cne
        [string]$QualitySetPolicy.DependencyManifestSha256 -or
        [string]$WorkerEvidence.Provenance.QualityShardPolicySha256 -cne
        [string]$QualitySetPolicy.CanonicalSha256
    ) {
        throw "$Engine aggregate repository or dependency binding drift."
    }

    return [pscustomobject][ordered]@{
        Result = [string]$pester.Result
        TotalCount = [long]$pester.TotalCount
        PassedCount = [long]$pester.PassedCount
        FailedCount = [long]$pester.FailedCount
        RequiredSuiteFailureCount = [long]$suiteFailureCount
    }
}

function Assert-CddsiGateQualityEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence,

        [Parameter(Mandatory = $true)]
        $QualitySetPolicy,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Assert-CddsiGateExactPropertySet -Value $Evidence -Expected @(
        'CLEANUP_OUTCOME',
        'FORBIDDEN_RESOURCE_ACCESS_COUNT',
        'HARNESS_LEDGER',
        'HARNESS_LEDGER_EXACT',
        'LIVE_PROVIDER_LOADED',
        'MUTATION_SPY_COUNTS',
        'OUTSIDE_SANDBOX_WRITE_COUNT',
        'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
        'PRODUCT_NETWORK_REQUEST_COUNT',
        'REAL_REGISTRY_ACCESS_COUNT',
        'REPOSITORY_AFTER_DIRECTORY_COUNT',
        'REPOSITORY_AFTER_FILE_COUNT',
        'REPOSITORY_AFTER_SHA256',
        'REPOSITORY_BEFORE_DIRECTORY_COUNT',
        'REPOSITORY_BEFORE_FILE_COUNT',
        'REPOSITORY_BEFORE_SHA256',
        'REPOSITORY_CONTENT_CHANGED',
        'REPOSITORY_SNAPSHOT_SCOPE',
        'RunId',
        'SAFE_FAILURE_DISCLOSURE',
        'Scenario',
        'SchemaVersion',
        'SECRET_FINDINGS',
        'TRUSTED_HARNESS_PROCESS_COUNT',
        'TRUSTED_PROCESS_ACTUAL_COUNT',
        'TRUSTED_PROCESS_EXPECTED_COUNT',
        'TRUSTED_PROCESS_SEQUENCE',
        'UNAPPROVED_HARNESS_NETWORK_COUNT',
        'UNAPPROVED_HARNESS_PROCESS_COUNT',
        'UNEXPECTED_LEDGER_ENTRY_COUNT',
        'WORKER_EVIDENCE'
    ) -Label 'Quality evidence'
    $parsedRunId = [guid]::Empty
    if (
        -not (Test-CddsiGateInteger -Value $Evidence.SchemaVersion) -or
        [long]$Evidence.SchemaVersion -ne 2 -or
        [string]$Evidence.Scenario -cne 'Quality' -or
        [string]$Evidence.CLEANUP_OUTCOME -cne 'Succeeded' -or
        -not [guid]::TryParse([string]$Evidence.RunId, [ref]$parsedRunId)
    ) {
        throw 'Quality evidence identity is invalid.'
    }
    foreach ($zeroName in @(
        'FORBIDDEN_RESOURCE_ACCESS_COUNT',
        'OUTSIDE_SANDBOX_WRITE_COUNT',
        'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
        'PRODUCT_NETWORK_REQUEST_COUNT',
        'REAL_REGISTRY_ACCESS_COUNT',
        'UNAPPROVED_HARNESS_PROCESS_COUNT',
        'UNAPPROVED_HARNESS_NETWORK_COUNT',
        'SECRET_FINDINGS',
        'UNEXPECTED_LEDGER_ENTRY_COUNT'
    )) {
        if (-not (Test-CddsiGateInteger -Value $Evidence.$zeroName) -or [long]$Evidence.$zeroName -ne 0) {
            throw "Quality evidence metric is not integer zero: $zeroName."
        }
    }
    foreach ($falseName in @('LIVE_PROVIDER_LOADED', 'REPOSITORY_CONTENT_CHANGED')) {
        if ($Evidence.$falseName -isnot [bool] -or [bool]$Evidence.$falseName) {
            throw "Quality evidence flag is not false: $falseName."
        }
    }
    foreach ($trueName in @('SAFE_FAILURE_DISCLOSURE', 'HARNESS_LEDGER_EXACT')) {
        if ($Evidence.$trueName -isnot [bool] -or -not [bool]$Evidence.$trueName) {
            throw "Quality evidence flag is not true: $trueName."
        }
    }

    if (
        [string]$Evidence.REPOSITORY_SNAPSHOT_SCOPE -cne 'WorkingTreeExcludingDotGit' -or
        [string]$Evidence.REPOSITORY_BEFORE_SHA256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.REPOSITORY_AFTER_SHA256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.REPOSITORY_BEFORE_SHA256 -cne [string]$Evidence.REPOSITORY_AFTER_SHA256
    ) {
        throw 'Quality repository snapshot hash binding drift.'
    }
    foreach ($countName in @(
        'REPOSITORY_BEFORE_FILE_COUNT',
        'REPOSITORY_AFTER_FILE_COUNT',
        'REPOSITORY_BEFORE_DIRECTORY_COUNT',
        'REPOSITORY_AFTER_DIRECTORY_COUNT'
    )) {
        if (-not (Test-CddsiGateInteger -Value $Evidence.$countName) -or [long]$Evidence.$countName -le 0) {
            throw "Quality repository snapshot count is invalid: $countName."
        }
    }
    if (
        [long]$Evidence.REPOSITORY_BEFORE_FILE_COUNT -ne [long]$Evidence.REPOSITORY_AFTER_FILE_COUNT -or
        [long]$Evidence.REPOSITORY_BEFORE_DIRECTORY_COUNT -ne [long]$Evidence.REPOSITORY_AFTER_DIRECTORY_COUNT
    ) {
        throw 'Quality repository snapshot count binding drift.'
    }

    $mutationNames = @(
        'AppX',
        'Credential',
        'Environment',
        'Feature',
        'FileSystem',
        'Network',
        'Process',
        'Registry',
        'Restart',
        'Service'
    )
    Assert-CddsiGateExactPropertySet -Value $Evidence.MUTATION_SPY_COUNTS `
        -Expected $mutationNames `
        -Label 'Quality mutation-spy evidence'
    foreach ($mutationName in $mutationNames) {
        $value = $Evidence.MUTATION_SPY_COUNTS.$mutationName
        if (-not (Test-CddsiGateInteger -Value $value) -or [long]$value -ne 0) {
            throw "Quality mutation-spy evidence is not integer zero: $mutationName."
        }
    }

    [string[]]$expectedProcessSequence = @(Get-CddsiGateExpectedProcessSequence -QualitySetPolicy $QualitySetPolicy)
    [string[]]$actualProcessSequence = @($Evidence.TRUSTED_PROCESS_SEQUENCE | ForEach-Object { [string]$_.RuleId })
    Assert-CddsiGateExactStringSequence -Actual $actualProcessSequence -Expected $expectedProcessSequence `
        -Label 'Quality trusted-process sequence'
    foreach ($countName in @(
        'TRUSTED_PROCESS_EXPECTED_COUNT',
        'TRUSTED_PROCESS_ACTUAL_COUNT',
        'TRUSTED_HARNESS_PROCESS_COUNT'
    )) {
        if (
            -not (Test-CddsiGateInteger -Value $Evidence.$countName) -or
            [long]$Evidence.$countName -ne [long]$QualitySetPolicy.ProcessCount
        ) {
            throw "Quality trusted-process count drift: $countName."
        }
    }

    [string[]]$expectedLedgerSequence = @(Get-CddsiGateExpectedHarnessLedgerSequence -QualitySetPolicy $QualitySetPolicy)
    [string[]]$actualLedgerSequence = @($Evidence.HARNESS_LEDGER | ForEach-Object { [string]$_.RuleId })
    Assert-CddsiGateExactStringSequence -Actual $actualLedgerSequence -Expected $expectedLedgerSequence `
        -Label 'Quality harness-ledger sequence'
    if (
        $actualLedgerSequence.Count -ne [int]$QualitySetPolicy.LedgerEntryCount -or
        $expectedLedgerSequence.Count -ne [int]$QualitySetPolicy.LedgerEntryCount
    ) {
        throw 'Quality harness-ledger count drift.'
    }

    $workers = @($Evidence.WORKER_EVIDENCE)
    $null = Assert-CddsiGateWorkerSandboxBinding -WorkerEvidence $workers
    $workerSummaries = New-Object System.Collections.Generic.List[object]
    foreach ($engine in @('PowerShell7', 'WindowsPowerShell')) {
        $matches = @($workers | Where-Object { [string]$_.Engine -ceq $engine })
        if ($matches.Count -ne 1) {
            throw 'Quality aggregate worker engine set drift.'
        }
        $workerSummaries.Add((Assert-CddsiGateWorkerEvidence `
            -WorkerEvidence $matches[0] `
            -Engine $engine `
            -RunId ([string]$Evidence.RunId) `
            -QualitySetPolicy $QualitySetPolicy `
            -RepositoryRoot $RepositoryRoot))
    }
    $failedTests = [long](($workerSummaries | ForEach-Object { [long]$_.FailedCount } | Measure-Object -Sum).Sum)
    $failedSuites = [long](($workerSummaries | ForEach-Object { [long]$_.RequiredSuiteFailureCount } | Measure-Object -Sum).Sum)
    $diagnosticResult = if (($failedTests + $failedSuites) -gt 0) { 'FAILED_TESTS' } else { 'PASSED' }
    if (
        [string]$QualitySetPolicy.QualitySet -ne 'HistoricalDiagnostic' -and
        $diagnosticResult -cne 'PASSED'
    ) {
        throw 'Blocking quality evidence contains a failed test.'
    }
    return [pscustomobject][ordered]@{
        DiagnosticResult = $diagnosticResult
        FailedTestCount = $failedTests
        RequiredSuiteFailureCount = $failedSuites
        WorkerSummaries = $workerSummaries.ToArray()
    }
}

function Assert-CddsiGateRepositorySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Snapshot,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Assert-CddsiGateExactPropertySet -Value $Snapshot -Expected @(
        'DirectoryCount',
        'FileCount',
        'Hash',
        'Manifest',
        'SchemaVersion',
        'Scope'
    ) -Label $Label
    if (
        -not (Test-CddsiGateInteger -Value $Snapshot.SchemaVersion) -or
        [long]$Snapshot.SchemaVersion -ne 1 -or
        [string]$Snapshot.Scope -cne 'WorkingTreeExcludingDotGit' -or
        [string]$Snapshot.Hash -cnotmatch '^[a-f0-9]{64}$' -or
        -not (Test-CddsiGateInteger -Value $Snapshot.FileCount) -or
        [long]$Snapshot.FileCount -le 0 -or
        -not (Test-CddsiGateInteger -Value $Snapshot.DirectoryCount) -or
        [long]$Snapshot.DirectoryCount -le 0
    ) {
        throw "$Label identity is invalid."
    }
    $manifest = @($Snapshot.Manifest)
    if ($manifest.Count -ne ([long]$Snapshot.FileCount + [long]$Snapshot.DirectoryCount)) {
        throw "$Label manifest count drift."
    }
    [string[]]$manifestStrings = @($manifest | ForEach-Object { [string]$_ })
    [string[]]$ordinal = @($manifestStrings)
    [Array]::Sort($ordinal, [StringComparer]::Ordinal)
    if (($manifestStrings -join "`n") -cne ($ordinal -join "`n")) {
        throw "$Label manifest is not ordinal-sorted."
    }
    if ((Get-CddsiGateSha256Text -Text ($manifestStrings -join "`n")) -cne [string]$Snapshot.Hash) {
        throw "$Label manifest hash drift."
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        Scope = 'WorkingTreeExcludingDotGit'
        Hash = [string]$Snapshot.Hash
        FileCount = [long]$Snapshot.FileCount
        DirectoryCount = [long]$Snapshot.DirectoryCount
    }
}

function Assert-CddsiGateRepositorySnapshotsEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Expected,

        [Parameter(Mandatory = $true)]
        $Actual,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    foreach ($name in @('SchemaVersion', 'Scope', 'Hash', 'FileCount', 'DirectoryCount')) {
        if ([string]$Expected.$name -cne [string]$Actual.$name) {
            throw "$Label repository snapshot drift."
        }
    }
}

function Test-CddsiGateCanonicalZipEntryTimestamp {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($Value -is [string]) {
        return $Value -ceq '1980-01-01T00:00:00Z'
    }
    if ($Value -is [datetime]) {
        return (
            $Value.Kind -eq [System.DateTimeKind]::Utc -and
            [long]$Value.Ticks -eq 624511296000000000L
        )
    }
    return $false
}

function Assert-CddsiGateReleaseEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        $RepositorySnapshot
    )

    Assert-CddsiGateExactPropertySet -Value $Evidence -Expected @(
        'Changed',
        'CleanupOutcome',
        'ContentHashesExact',
        'ExtractFileCount',
        'ExtractInventoryExact',
        'ExtractSecretFindings',
        'FORBIDDEN_RESOURCE_ACCESS_COUNT',
        'HarnessLedgerExact',
        'LIVE_PROVIDER_LOADED',
        'Mode',
        'Operation',
        'OUTSIDE_SANDBOX_WRITE_COUNT',
        'PackageFileCount',
        'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
        'PRODUCT_NETWORK_REQUEST_COUNT',
        'REAL_REGISTRY_ACCESS_COUNT',
        'REPOSITORY_CONTENT_CHANGED',
        'RepositoryDirectoryCount',
        'RepositoryFileCount',
        'SchemaVersion',
        'SECRET_FINDINGS',
        'SourcePackageChanged',
        'SourceSecretFindings',
        'SpecialPathValidated',
        'StagingSecretFindings',
        'Status',
        'TrustedHarnessFileSystemCount',
        'TrustedHarnessNetworkCount',
        'TrustedHarnessProcessCount',
        'UNAPPROVED_HARNESS_NETWORK_COUNT',
        'UNAPPROVED_HARNESS_PROCESS_COUNT',
        'UNEXPECTED_LEDGER_ENTRY_COUNT',
        'ZipCompression',
        'ZipDeterministic',
        'ZipEntryCount',
        'ZipEntryOrder',
        'ZipEntryTimestampUtc',
        'ZipInventoryExact',
        'ZipSecretFindings'
    ) -Label 'Release DryRun evidence'
    if (
        -not (Test-CddsiGateInteger -Value $Evidence.SchemaVersion) -or
        [long]$Evidence.SchemaVersion -ne 1 -or
        [string]$Evidence.Operation -cne 'ReleaseSimulation' -or
        [string]$Evidence.Mode -cne 'DryRun' -or
        [string]$Evidence.Status -cne 'SUCCEEDED' -or
        [string]$Evidence.CleanupOutcome -cne 'Succeeded' -or
        [string]$Evidence.ZipEntryOrder -cne 'Ordinal' -or
        -not (
            Test-CddsiGateCanonicalZipEntryTimestamp `
                -Value $Evidence.ZipEntryTimestampUtc
        ) -or
        [string]$Evidence.ZipCompression -cne 'Store'
    ) {
        throw 'Release DryRun evidence identity is invalid.'
    }
    foreach ($zeroName in @(
        'SourceSecretFindings',
        'StagingSecretFindings',
        'ZipSecretFindings',
        'ExtractSecretFindings',
        'TrustedHarnessProcessCount',
        'TrustedHarnessNetworkCount',
        'FORBIDDEN_RESOURCE_ACCESS_COUNT',
        'OUTSIDE_SANDBOX_WRITE_COUNT',
        'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
        'PRODUCT_NETWORK_REQUEST_COUNT',
        'REAL_REGISTRY_ACCESS_COUNT',
        'UNAPPROVED_HARNESS_PROCESS_COUNT',
        'UNAPPROVED_HARNESS_NETWORK_COUNT',
        'SECRET_FINDINGS',
        'UNEXPECTED_LEDGER_ENTRY_COUNT'
    )) {
        if (-not (Test-CddsiGateInteger -Value $Evidence.$zeroName) -or [long]$Evidence.$zeroName -ne 0) {
            throw "Release DryRun metric is not integer zero: $zeroName."
        }
    }
    foreach ($trueName in @(
        'ZipInventoryExact',
        'ZipDeterministic',
        'ExtractInventoryExact',
        'ContentHashesExact',
        'SpecialPathValidated',
        'HarnessLedgerExact'
    )) {
        if ($Evidence.$trueName -isnot [bool] -or -not [bool]$Evidence.$trueName) {
            throw "Release DryRun flag is not true: $trueName."
        }
    }
    foreach ($falseName in @(
        'Changed',
        'SourcePackageChanged',
        'LIVE_PROVIDER_LOADED',
        'REPOSITORY_CONTENT_CHANGED'
    )) {
        if ($Evidence.$falseName -isnot [bool] -or [bool]$Evidence.$falseName) {
            throw "Release DryRun flag is not false: $falseName."
        }
    }
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $RepositoryRoot 'scripts\release-manifest.psd1')
    $expectedPackageCount = @($manifest.PackageFiles).Count
    foreach ($countName in @('PackageFileCount', 'ZipEntryCount', 'ExtractFileCount')) {
        if (
            -not (Test-CddsiGateInteger -Value $Evidence.$countName) -or
            [long]$Evidence.$countName -ne [long]$expectedPackageCount
        ) {
            throw "Release DryRun package count drift: $countName."
        }
    }
    if (
        -not (Test-CddsiGateInteger -Value $Evidence.RepositoryFileCount) -or
        [long]$Evidence.RepositoryFileCount -ne [long]$RepositorySnapshot.FileCount -or
        -not (Test-CddsiGateInteger -Value $Evidence.RepositoryDirectoryCount) -or
        [long]$Evidence.RepositoryDirectoryCount -ne [long]$RepositorySnapshot.DirectoryCount -or
        -not (Test-CddsiGateInteger -Value $Evidence.TrustedHarnessFileSystemCount) -or
        [long]$Evidence.TrustedHarnessFileSystemCount -ne 16
    ) {
        throw 'Release DryRun repository or harness count drift.'
    }
    return $true
}
