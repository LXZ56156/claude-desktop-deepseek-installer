[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$RepositoryRoot,

    [Parameter(Mandatory = $true)]
    [string]$SandboxRoot,

    [Parameter(Mandatory = $true)]
    [string]$RunId,

    [Parameter(Mandatory = $true)]
    [string]$RepositoryInventoryPath,

    [Parameter(Mandatory = $true)]
    [string]$BoundaryManifestPath,

    [Parameter(Mandatory = $true)]
    [string]$DependencyManifestPath,

    [Parameter(Mandatory = $true)]
    [ValidateSet('PowerShell7', 'WindowsPowerShell')]
    [string]$EngineId,

    [Parameter(Mandatory = $true)]
    [string]$EngineExecutablePath,

    [Parameter(Mandatory = $true)]
    [string]$EngineGrantSha256,

    [switch]$SkipPester,

    [switch]$EvidenceBuilderOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
$script:SandboxRoot = [System.IO.Path]::GetFullPath($SandboxRoot).TrimEnd('\')
$script:Failures = New-Object System.Collections.Generic.List[string]
$script:PesterResult = $null
$script:SandboxBindingSha256 = $null
$script:PesterTreeSha256 = $null
$script:DependencyManifestSha256 = $null
$script:ExecutionBoundaryManifestSha256 = $null
$script:AstSyntaxErrorCount = $null
$script:LiveAdapterFileCount = $null
$script:SecretFindingCount = $null
$script:RepositoryContentChanged = $null
$script:CddsiWorkerMeasurementRuleVersion = 'cddsi-worker-measurement-rules-v2'

function Get-RepositoryFiles {
    $inventoryFullPath = [System.IO.Path]::GetFullPath($RepositoryInventoryPath)
    if (-not $inventoryFullPath.StartsWith($script:SandboxRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Repository inventory must be inside the owned sandbox.'
    }
    if (-not (Test-Path -LiteralPath $inventoryFullPath -PathType Leaf)) {
        throw 'Trusted harness did not provide a repository inventory.'
    }
    $inventoryText = [System.IO.File]::ReadAllText($inventoryFullPath, [System.Text.Encoding]::UTF8)
    $inventory = $inventoryText | ConvertFrom-Json -ErrorAction Stop
    $inventoryNames = @($inventory.PSObject.Properties.Name | Sort-Object)
    $expectedInventoryNames = @('Paths', 'RepositoryRootBindingSha256', 'RunId', 'SchemaVersion')
    if (($inventoryNames -join [Environment]::NewLine) -cne ($expectedInventoryNames -join [Environment]::NewLine)) { throw 'Repository inventory envelope schema drift.' }
    $expectedRepositoryBinding = Get-CddsiWorkerSha256Text -Text ([System.IO.Path]::GetFullPath($script:Root).ToUpperInvariant())
    if ($inventory.SchemaVersion -ne 1 -or $inventory.RunId -cne $RunId -or $inventory.RepositoryRootBindingSha256 -cne $expectedRepositoryBinding) { throw 'Repository inventory envelope binding is invalid.' }
    $paths = @($inventory.Paths)
    $sortedPaths = [string[]]@($paths | ForEach-Object { [string]$_ })
    [Array]::Sort($sortedPaths, [StringComparer]::Ordinal)
    if ((@($paths | ForEach-Object { [string]$_ }) -join [Environment]::NewLine) -cne ($sortedPaths -join [Environment]::NewLine)) { throw 'Repository inventory paths are not ordinal-sorted.' }
    $pathDuplicates = @($paths | Group-Object | Where-Object Count -gt 1)
    if ($pathDuplicates.Count -gt 0) { throw 'Repository inventory paths are not unique.' }
    $files = @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $relative = ([string]$_).Replace('\', '/')
        if ([System.IO.Path]::IsPathRooted($relative) -or @($relative.Split('/') | Where-Object { $_ -eq '..' }).Count -gt 0) {
            throw "Repository inventory contains an unsafe path: $relative"
        }
        $fullPath = Join-Path $script:Root $relative
        $resolvedPath = [System.IO.Path]::GetFullPath($fullPath)
        if (-not $resolvedPath.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw "Repository inventory escapes the source root: $relative"
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Repository file is missing: $relative" }
        $item = Get-Item -LiteralPath $fullPath -Force
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw "Repository inventory references a reparse point: $relative"
        }
        [pscustomobject]@{ File = $item; RelativePath = $relative }
    })
    # The inventory was already validated as ordinal-sorted above. Preserve
    # that exact order; Sort-Object would reapply culture-sensitive ordering
    # and change the manifest hash for paths such as Z.txt and a.txt.
    return @($files)
}

function Get-RepositoryContentManifest {
    return @((Get-RepositoryFiles) | ForEach-Object {
        '{0}|{1}' -f $_.RelativePath, (Get-FileHash -LiteralPath $_.File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

function Invoke-CheckStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        & $Action
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $message = Protect-CheckMessage -Message $_.Exception.Message
        $script:Failures.Add("${Name}: $message")
        Write-Host "[FAIL] $Name - $message" -ForegroundColor Red
    }
}

function Protect-CheckMessage {
    param([AllowNull()][string]$Message)
    if ($null -eq $Message) { return '' }
    $safe = [regex]::Replace($Message, '\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)', '')
    $safe = [regex]::Replace($safe, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $safe = [regex]::Replace($safe, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '')
    $safe = [regex]::Replace($safe, '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]', '')
    $safe = [regex]::Replace($safe, '(?i)sk-[a-z0-9_-]{20,}', '[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])', 'Bearer [REDACTED]')
    $credentialPattern = '(?i)(?<prefix>"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?)(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}'
    $safe = [regex]::Replace($safe, $credentialPattern, '${prefix}[REDACTED]')
    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $privateKeyPattern = '(?is)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----.*?-----END [^-\r\n]*' + $privateKeyLabel + '-----'
    $safe = [regex]::Replace($safe, $privateKeyPattern, '[REDACTED PRIVATE KEY]')
    if ($safe.Length -gt 6000) { return $safe.Substring(0, 6000) }
    return $safe
}

function Test-CddsiJsonIntegerOne {
    param([AllowNull()]$Value)
    return (($Value -is [int] -or $Value -is [long]) -and [long]$Value -eq 1)
}

function Read-CddsiStrictUtf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$DisplayPath
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Count -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) { throw "UTF-16 text is forbidden: $DisplayPath" }
    if (@($bytes | Where-Object { $_ -eq 0 }).Count -gt 0) { throw "NUL byte in text file: $DisplayPath" }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { return $strictUtf8.GetString($bytes) } catch { throw "Invalid UTF-8 text: $DisplayPath" }
}

function Get-CddsiWorkerSha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-CddsiWorkerSequenceSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Values
    )

    return Get-CddsiWorkerSha256Text -Text ($Values -join "`n")
}

function Find-CddsiWorkerStreamSecretFindings {
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$Stream,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (-not $Stream.CanRead) { throw 'Worker secret scan requires a readable stream.' }
    $patterns = @(
        [pscustomobject]@{ Type = 'ApiKey'; Pattern = '(?i)sk-[a-z0-9_-]{20,}' }
        [pscustomobject]@{ Type = 'Bearer'; Pattern = '(?i)Bearer\s+[a-z0-9._~-]{20,}' }
        [pscustomobject]@{ Type = 'CredentialAssignment'; Pattern = '(?i)"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?[a-z0-9._~-]{20,}' }
        [pscustomobject]@{ Type = 'PrivateKeyHeader'; Pattern = '(?is)-----BEGIN [^-\r\n]*PRIVATE KEY-----' }
    )
    $buffer = New-Object byte[] 65536
    $carrySize = 4096
    $carry = ''
    $absoluteRead = [long]0
    $encoding = [System.Text.Encoding]::GetEncoding(28591)
    $findings = New-Object System.Collections.Generic.List[object]
    while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $combinedOffset = $absoluteRead - $carry.Length
        $combined = $carry + $encoding.GetString($buffer, 0, $read)
        $absoluteRead += $read
        $isFinalChunk = $Stream.Position -eq $Stream.Length
        $scanStartLimit = if ($isFinalChunk) { $combined.Length } else { [Math]::Max(0, $combined.Length - $carrySize) }
        foreach ($definition in $patterns) {
            foreach ($match in @([regex]::Matches($combined, $definition.Pattern) | Where-Object { $_.Index -lt $scanStartLimit })) {
                $findings.Add([pscustomobject][ordered]@{
                    Source       = $RelativePath
                    LocationKind = 'ByteOffset'
                    ByteOffset   = [long]($combinedOffset + $match.Index)
                    Type         = [string]$definition.Type
                })
            }
        }
        $carry = if ($isFinalChunk) { '' } else { $combined.Substring($scanStartLimit) }
    }
    return $findings.ToArray()
}

function Find-CddsiWorkerFileSecretFindings {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    try {
        return @(Find-CddsiWorkerStreamSecretFindings -Stream $stream -RelativePath $RelativePath)
    }
    finally {
        $stream.Dispose()
    }
}

function Test-CddsiWorkerExactPropertySet {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$ExpectedNames
    )

    if ($null -eq $InputObject) { return $false }
    $actualNames = @($InputObject.PSObject.Properties.Name | Sort-Object)
    $sortedExpectedNames = @($ExpectedNames | Sort-Object)
    return (($actualNames -join [Environment]::NewLine) -ceq ($sortedExpectedNames -join [Environment]::NewLine))
}

function Assert-CddsiWorkerNonNegativeInteger {
    param(
        [Parameter(Mandatory = $true)]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if (($Value -isnot [int] -and $Value -isnot [long]) -or [long]$Value -lt 0) {
        throw ("Worker evidence field {0} must be a non-negative integer." -f $Name)
    }
}

function Assert-CddsiWorkerSha256Value {
    param(
        [Parameter(Mandatory = $true)][string]$Value,
        [Parameter(Mandatory = $true)][string]$Name
    )

    if ($Value -cnotmatch '^[a-f0-9]{64}$') {
        throw ("Worker evidence field {0} must be a lowercase SHA-256 value." -f $Name)
    }
}

function Get-CddsiWorkerRequiredSuiteSummarySha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SuiteResults
    )

    $lines = @($SuiteResults | ForEach-Object {
        '{0}|{1}|{2}' -f ([string]$_.RelativePath).Replace('\', '/'), [long]$_.TestCount, [string]$_.Result
    })
    return Get-CddsiWorkerSequenceSha256 -Values $lines
}

function New-CddsiWorkerIsolationEvidenceV2 {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('PowerShell7', 'WindowsPowerShell')][string]$Engine,
        [Parameter(Mandatory = $true)][string]$SandboxBindingSha256,
        [Parameter(Mandatory = $true)]$Measurements,
        [Parameter(Mandatory = $true)]$Provenance,
        [Parameter(Mandatory = $true)][string]$ExpectedEngineGrantSha256
    )

    $parsedRunId = [guid]::Empty
    if (-not [guid]::TryParse($RunId, [ref]$parsedRunId)) { throw 'Worker evidence RunId must be a GUID.' }
    Assert-CddsiWorkerSha256Value -Value $SandboxBindingSha256 -Name 'SandboxBindingSha256'
    Assert-CddsiWorkerSha256Value -Value $ExpectedEngineGrantSha256 -Name 'ExpectedEngineGrantSha256'

    $measurementNames = @(
        'AccessLedger', 'AstSyntaxErrorCount', 'LiveAdapterFileCount', 'LiveProviderLoaded',
        'MutationSpyCounts', 'Pester', 'RepositoryContentChanged', 'RequiredSuiteFailureCount',
        'RequiredSuiteResults', 'SecretFindingCount'
    )
    if (-not (Test-CddsiWorkerExactPropertySet -InputObject $Measurements -ExpectedNames $measurementNames)) {
        throw 'Worker Measurements does not match the exact schema.'
    }
    foreach ($booleanName in @('LiveProviderLoaded', 'RepositoryContentChanged')) {
        if ($Measurements.$booleanName -isnot [bool]) { throw "Worker Measurements.$booleanName must be Boolean." }
    }
    foreach ($integerName in @('AstSyntaxErrorCount', 'LiveAdapterFileCount', 'RequiredSuiteFailureCount', 'SecretFindingCount')) {
        Assert-CddsiWorkerNonNegativeInteger -Value $Measurements.$integerName -Name "Measurements.$integerName"
    }

    $ledgerNames = @(
        'ContextCount', 'DryRunContextCount', 'EntryCount', 'ForbiddenResourceAccessCount',
        'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount', 'ProductNetworkRequestCount',
        'RealRegistryAccessCount', 'TestSafeContextCount', 'UnexpectedLedgerEntryCount'
    )
    if (-not (Test-CddsiWorkerExactPropertySet -InputObject $Measurements.AccessLedger -ExpectedNames $ledgerNames)) {
        throw 'Worker Measurements.AccessLedger does not match the exact schema.'
    }
    foreach ($ledgerName in $ledgerNames) {
        Assert-CddsiWorkerNonNegativeInteger -Value $Measurements.AccessLedger.$ledgerName -Name "Measurements.AccessLedger.$ledgerName"
    }
    if (
        [long]$Measurements.AccessLedger.ContextCount -ne (
            [long]$Measurements.AccessLedger.TestSafeContextCount + [long]$Measurements.AccessLedger.DryRunContextCount
        ) -or
        [long]$Measurements.AccessLedger.TestSafeContextCount -lt 1 -or
        [long]$Measurements.AccessLedger.DryRunContextCount -lt 1
    ) {
        throw 'Worker access-ledger evidence must bind at least one TestSafe and one DryRun context.'
    }

    $mutationNames = @('AppX', 'Credential', 'Environment', 'Feature', 'FileSystem', 'Network', 'Process', 'Registry', 'Restart', 'Service')
    if (-not (Test-CddsiWorkerExactPropertySet -InputObject $Measurements.MutationSpyCounts -ExpectedNames $mutationNames)) {
        throw 'Worker Measurements.MutationSpyCounts does not match the exact schema.'
    }
    foreach ($mutationName in $mutationNames) {
        Assert-CddsiWorkerNonNegativeInteger -Value $Measurements.MutationSpyCounts.$mutationName -Name "Measurements.MutationSpyCounts.$mutationName"
    }

    $pesterNames = @('FailedCount', 'InconclusiveCount', 'NotRunCount', 'PassedCount', 'Result', 'SkippedCount')
    if (-not (Test-CddsiWorkerExactPropertySet -InputObject $Measurements.Pester -ExpectedNames $pesterNames)) {
        throw 'Worker Measurements.Pester does not match the exact schema.'
    }
    if ([string]::IsNullOrWhiteSpace([string]$Measurements.Pester.Result)) { throw 'Worker Pester result is missing.' }
    foreach ($pesterName in @('FailedCount', 'InconclusiveCount', 'NotRunCount', 'PassedCount', 'SkippedCount')) {
        Assert-CddsiWorkerNonNegativeInteger -Value $Measurements.Pester.$pesterName -Name "Measurements.Pester.$pesterName"
    }

    $suiteResults = @($Measurements.RequiredSuiteResults)
    if ($suiteResults.Count -eq 0) { throw 'Worker required-suite evidence is empty.' }
    foreach ($suiteResult in $suiteResults) {
        if (-not (Test-CddsiWorkerExactPropertySet -InputObject $suiteResult -ExpectedNames @('RelativePath', 'Result', 'TestCount'))) {
            throw 'Worker required-suite result does not match the exact schema.'
        }
        if ([string]::IsNullOrWhiteSpace([string]$suiteResult.RelativePath) -or [string]::IsNullOrWhiteSpace([string]$suiteResult.Result)) {
            throw 'Worker required-suite result contains an empty binding.'
        }
        Assert-CddsiWorkerNonNegativeInteger -Value $suiteResult.TestCount -Name 'Measurements.RequiredSuiteResults.TestCount'
    }
    $actualSuiteFailureCount = @($suiteResults | Where-Object { [string]$_.Result -cne 'Passed' }).Count
    if ([long]$Measurements.RequiredSuiteFailureCount -ne [long]$actualSuiteFailureCount) {
        throw 'Worker required-suite failure count is not bound to the suite results.'
    }

    $provenanceNames = @(
        'DependencyManifestSha256', 'EngineGrantSha256', 'ExecutionBoundaryManifestSha256',
        'FinalRepositoryManifestSha256', 'InitialRepositoryManifestSha256', 'MeasurementRuleVersion',
        'PesterTreeSha256', 'RepositoryInventorySha256', 'RequiredSuiteSummarySha256'
    )
    if (-not (Test-CddsiWorkerExactPropertySet -InputObject $Provenance -ExpectedNames $provenanceNames)) {
        throw 'Worker Provenance does not match the exact schema.'
    }
    if ([string]$Provenance.MeasurementRuleVersion -cne $script:CddsiWorkerMeasurementRuleVersion) {
        throw 'Worker measurement-rule version drift.'
    }
    foreach ($shaName in @($provenanceNames | Where-Object { $_ -ne 'MeasurementRuleVersion' })) {
        Assert-CddsiWorkerSha256Value -Value ([string]$Provenance.$shaName) -Name "Provenance.$shaName"
    }
    if ([string]$Provenance.EngineGrantSha256 -cne $ExpectedEngineGrantSha256) {
        throw 'Worker engine grant SHA-256 does not match the expected grant.'
    }
    $manifestChanged = [string]$Provenance.InitialRepositoryManifestSha256 -cne [string]$Provenance.FinalRepositoryManifestSha256
    if ([bool]$Measurements.RepositoryContentChanged -ne $manifestChanged) {
        throw 'Worker repository changed measurement is not bound to the repository manifest hashes.'
    }
    $requiredSuiteSummarySha256 = Get-CddsiWorkerRequiredSuiteSummarySha256 -SuiteResults $suiteResults
    if ([string]$Provenance.RequiredSuiteSummarySha256 -cne $requiredSuiteSummarySha256) {
        throw 'Worker required-suite summary SHA-256 binding drift.'
    }

    return [pscustomobject][ordered]@{
        SchemaVersion         = 2
        EvidenceType         = 'CddsiWorkerIsolationEvidence'
        RunId                = $RunId
        Engine               = $Engine
        SandboxBindingSha256 = $SandboxBindingSha256
        Measurements         = $Measurements
        Provenance           = $Provenance
    }
}

function Measure-CddsiWorkerExecutionContexts {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Contexts
    )

    if ($Contexts.Count -eq 0) { throw 'Worker synthetic context evidence is empty.' }
    $evidenceItems = @($Contexts | ForEach-Object { Get-CddsiIsolationEvidence -Context $_ })
    $mutationCounts = [ordered]@{
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
    foreach ($context in $Contexts) {
        foreach ($mutation in @($context.Providers.MutationSpy)) {
            $mutationName = switch -CaseSensitive ([string]$mutation.Provider) {
                'Package' { 'AppX'; break }
                'FileSystem' { 'FileSystem'; break }
                'Environment' { 'Environment'; break }
                'Registry' { 'Registry'; break }
                'Network' { 'Network'; break }
                'Process' {
                    if ([string]$mutation.Operation -ceq 'Restart') { 'Restart' } else { 'Process' }
                    break
                }
                'Feature' { 'Feature'; break }
                'Service' { 'Service'; break }
                'Credential' { 'Credential'; break }
                default { throw 'Worker mutation spy contains an unsupported provider.' }
            }
            $mutationCounts[$mutationName] = [int]$mutationCounts[$mutationName] + 1
        }
    }

    return [pscustomobject][ordered]@{
        LiveProviderLoaded = @($evidenceItems | Where-Object { $_.LIVE_PROVIDER_LOADED }).Count -gt 0
        AccessLedger = [pscustomobject][ordered]@{
            ContextCount                    = $Contexts.Count
            TestSafeContextCount            = @($Contexts | Where-Object { $_.Mode -ceq 'TestSafe' }).Count
            DryRunContextCount               = @($Contexts | Where-Object { $_.Mode -ceq 'DryRun' }).Count
            EntryCount                      = [int](($Contexts | ForEach-Object { @($_.AccessLedger.Entries).Count } | Measure-Object -Sum).Sum)
            ForbiddenResourceAccessCount    = [int](($evidenceItems | ForEach-Object { $_.FORBIDDEN_RESOURCE_ACCESS_COUNT } | Measure-Object -Sum).Sum)
            OutsideSandboxWriteCount        = [int](($evidenceItems | ForEach-Object { $_.OUTSIDE_SANDBOX_WRITE_COUNT } | Measure-Object -Sum).Sum)
            ProductLiveProcessSpawnCount    = [int](($evidenceItems | ForEach-Object { $_.PRODUCT_LIVE_PROCESS_SPAWN_COUNT } | Measure-Object -Sum).Sum)
            ProductNetworkRequestCount      = [int](($evidenceItems | ForEach-Object { $_.PRODUCT_NETWORK_REQUEST_COUNT } | Measure-Object -Sum).Sum)
            RealRegistryAccessCount         = [int](($evidenceItems | ForEach-Object { $_.REAL_REGISTRY_ACCESS_COUNT } | Measure-Object -Sum).Sum)
            UnexpectedLedgerEntryCount      = [int](($evidenceItems | ForEach-Object { $_.UNEXPECTED_LEDGER_ENTRY_COUNT } | Measure-Object -Sum).Sum)
        }
        MutationSpyCounts = [pscustomobject]$mutationCounts
    }
}

function Assert-CddsiWorkerSandboxBinding {
    $parsedRunId = [guid]::Empty
    if (-not [guid]::TryParse($RunId, [ref]$parsedRunId)) { throw 'Worker RunId must be a GUID.' }
    if ((Split-Path -Leaf $script:SandboxRoot) -notmatch '^cddsi-test-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') {
        throw 'Worker sandbox leaf is invalid.'
    }
    $rootItem = Get-Item -LiteralPath $script:SandboxRoot -Force -ErrorAction Stop
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Worker sandbox root is a reparse point.' }
    $markerPath = Join-Path $script:SandboxRoot '.cddsi-owner.json'
    if (-not (Test-Path -LiteralPath $markerPath -PathType Leaf)) { throw 'Worker sandbox owner marker is missing.' }
    $markerItem = Get-Item -LiteralPath $markerPath -Force
    if (($markerItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Worker sandbox owner marker is a reparse point.' }
    $marker = ([System.IO.File]::ReadAllText($markerPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
    $expectedNames = @('MarkerType', 'OwnershipToken', 'RootBindingSha256', 'RunId', 'SchemaVersion')
    $actualNames = @($marker.PSObject.Properties.Name | Sort-Object)
    if (($expectedNames -join [Environment]::NewLine) -cne ($actualNames -join [Environment]::NewLine)) { throw 'Worker sandbox owner marker schema drift.' }
    if ($marker.SchemaVersion -ne 1 -or $marker.MarkerType -cne 'CddsiHostSandboxOwner' -or $marker.RunId -cne $RunId) { throw 'Worker sandbox owner marker binding is invalid.' }
    if ([string]$marker.OwnershipToken -notmatch '^[a-f0-9]{64}$') { throw 'Worker sandbox owner token shape is invalid.' }
    $binding = Get-CddsiWorkerSha256Text -Text ([System.IO.Path]::GetFullPath($script:SandboxRoot).ToUpperInvariant())
    if ([string]$marker.RootBindingSha256 -cne $binding) { throw 'Worker sandbox root binding is invalid.' }
    return $binding
}

function Get-CddsiRequiredIsolationSuiteResults {
    if ($null -eq $script:PesterResult) { throw 'Pester result is unavailable for isolation evidence.' }
    $dependencyLock = Import-PowerShellDataFile -LiteralPath $DependencyManifestPath
    $suitePolicy = @($dependencyLock.IsolationEvidenceSuites)
    if ($suitePolicy.Count -eq 0) { throw 'Isolation evidence suite policy is empty.' }
    $pesterTests = @($script:PesterResult.Tests)
    if ($pesterTests.Count -eq 0) { throw 'Pester did not return test-level evidence.' }

    $testRoot = [System.IO.Path]::GetFullPath((Join-Path $script:Root 'tests')).TrimEnd('\')
    $pesterTestRecords = @($pesterTests | ForEach-Object {
        $testFile = $null
        if ($null -ne $_.ScriptBlock) { $testFile = [string]$_.ScriptBlock.File }
        if ([string]::IsNullOrWhiteSpace($testFile) -or -not [System.IO.Path]::IsPathRooted($testFile)) {
            throw 'Pester test evidence is missing an absolute ScriptBlock.File binding.'
        }
        $testFileFull = [System.IO.Path]::GetFullPath($testFile)
        if (-not $testFileFull.StartsWith($testRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Pester test evidence escaped the repository test root.'
        }
        [pscustomobject][ordered]@{
            RelativePath = $testFileFull.Substring($script:Root.Length + 1).Replace('\', '/')
            Test         = $_
        }
    })

    $suiteResults = New-Object System.Collections.Generic.List[object]
    foreach ($suite in $suitePolicy) {
        $relativePath = ([string]$suite.RelativePath).Replace('\', '/')
        $expectedCount = [int]$suite.ExpectedTestCount
        if (-not $relativePath.StartsWith('tests/', [StringComparison]::Ordinal) -or $expectedCount -le 0) { throw 'Isolation evidence suite policy is invalid.' }
        $matchingTests = @($pesterTestRecords | Where-Object { $_.RelativePath -ceq $relativePath })
        if ($matchingTests.Count -ne $expectedCount) { throw "Isolation evidence test count drift: $relativePath" }
        if (@($matchingTests | Where-Object { [string]$_.Test.Result -cne 'Passed' }).Count -gt 0) { throw "Isolation evidence suite is not clean: $relativePath" }
        $suiteResults.Add([pscustomobject][ordered]@{
            RelativePath = $relativePath
            TestCount    = $matchingTests.Count
            Result       = 'Passed'
        })
    }
    return $suiteResults.ToArray()
}

function Write-CddsiWorkerIsolationEvidence {
    param([Parameter(Mandatory = $true)]$Evidence)

    $evidenceDirectory = Join-Path $script:SandboxRoot 'evidence'
    if (-not (Test-Path -LiteralPath $evidenceDirectory -PathType Container)) { throw 'Worker evidence directory is missing.' }
    $evidenceItem = Get-Item -LiteralPath $evidenceDirectory -Force
    if (($evidenceItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Worker evidence directory is a reparse point.' }
    $leaf = if ($EngineId -ceq 'PowerShell7') { 'worker-powershell7.json' } else { 'worker-windows-powershell.json' }
    $path = Join-Path $evidenceDirectory $leaf
    if (Test-Path -LiteralPath $path) { throw 'Worker evidence path already exists.' }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stream = New-Object System.IO.FileStream($path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = New-Object System.IO.StreamWriter($stream, $utf8)
        try {
            $writer.Write(($Evidence | ConvertTo-Json -Depth 10) + [Environment]::NewLine)
            $writer.Flush()
            $stream.Flush()
        }
        finally { $writer.Dispose() }
    }
    finally { $stream.Dispose() }
    return $path
}

function Get-CddsiSafeTreeFiles {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $rootFullPath = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $rootFullPath -PathType Container)) {
        throw "Required tree is missing: $rootFullPath"
    }

    $rootItem = Get-Item -LiteralPath $rootFullPath -Force
    if (($rootItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Tree root is a reparse point: $rootFullPath"
    }

    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($rootFullPath)
    $files = New-Object System.Collections.Generic.List[object]
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw "Tree contains a reparse point: $($item.FullName)"
            }
            if ($item.PSIsContainer) {
                $queue.Enqueue($item.FullName)
            }
            else {
                $relative = $item.FullName.Substring($rootFullPath.Length).TrimStart('\').Replace('\', '/')
                $files.Add([pscustomobject]@{ RelativePath = $relative; File = $item })
            }
        }
    }
    return $files.ToArray()
}

function Test-CddsiDevDependencyLock {
    $expectedDependencyPath = Join-Path $script:Root 'config\dev-dependencies.psd1'
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($DependencyManifestPath), [System.IO.Path]::GetFullPath($expectedDependencyPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Dependency manifest path does not match the repository policy file.'
    }
    $script:DependencyManifestSha256 = (Get-FileHash -LiteralPath $expectedDependencyPath -Algorithm SHA256).Hash.ToLowerInvariant()

    $lock = Import-PowerShellDataFile -LiteralPath $expectedDependencyPath
    if ($lock.SchemaVersion -ne 1 -or $null -eq $lock.Pester) { throw 'Unsupported development dependency lock.' }
    $topLevelNames = @($lock.Keys | Sort-Object)
    if (($topLevelNames -join ',') -cne 'IsolationEvidenceSuites,Pester,SchemaVersion') { throw 'Development dependency lock top-level schema drift.' }
    $pesterNames = @($lock.Pester.Keys | Sort-Object)
    $expectedPesterNames = @('ExpectedFileCount', 'ExpectedLicenseBytes', 'ExpectedLicenseSha256', 'ExpectedManifestSha256', 'ExpectedTotalBytes', 'ExpectedTreeSha256', 'LicenseRelativePath', 'ManifestRelativePath', 'OfficialGalleryUrl', 'OfficialLicenseUrl', 'OfficialProjectUrl', 'ProvenanceStatus', 'RootRelativePath', 'TreeHashFormat', 'Version')
    if (($pesterNames -join ',') -cne ($expectedPesterNames -join ',')) { throw 'Pester dependency lock schema drift.' }
    if ($lock.Pester.Version -cne '5.6.1' -or $lock.Pester.ProvenanceStatus -cne 'VendoredPinnedTree') {
        throw 'Pester dependency lock is not an approved vendored pinned tree.'
    }
    if ($lock.Pester.RootRelativePath -cne '.dev/modules/Pester/5.6.1' -or $lock.Pester.ManifestRelativePath -cne 'Pester.psd1') { throw 'Pester dependency path policy drift.' }
    if ($lock.Pester.LicenseRelativePath -cne 'third-party/Pester-5.6.1-LICENSE.txt' -or [long]$lock.Pester.ExpectedLicenseBytes -ne 11357 -or $lock.Pester.ExpectedLicenseSha256 -cne 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4') { throw 'Pester local license lock drift.' }
    if ($lock.Pester.TreeHashFormat -cne 'ordinal-relative-path|sha256-lower|length joined with LF, UTF-8 without BOM') { throw 'Pester tree-hash format drift.' }
    if ($lock.Pester.OfficialGalleryUrl -cne 'https://www.powershellgallery.com/packages/Pester/5.6.1' -or $lock.Pester.OfficialProjectUrl -cne 'https://github.com/Pester/Pester' -or $lock.Pester.OfficialLicenseUrl -cne 'https://www.apache.org/licenses/LICENSE-2.0.html') {
        throw 'Pester provenance metadata drift.'
    }

    $dependencyRoot = [System.IO.Path]::GetFullPath((Join-Path $script:Root $lock.Pester.RootRelativePath)).TrimEnd('\')
    if (-not $dependencyRoot.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Pester dependency root escapes the repository.'
    }

    $files = @(Get-CddsiSafeTreeFiles -RootPath $dependencyRoot)
    if ($files.Count -ne [int]$lock.Pester.ExpectedFileCount) {
        throw "Pester dependency file count drift: expected $($lock.Pester.ExpectedFileCount), actual $($files.Count)."
    }
    $totalBytes = [long](($files | ForEach-Object { $_.File.Length } | Measure-Object -Sum).Sum)
    if ($totalBytes -ne [long]$lock.Pester.ExpectedTotalBytes) {
        throw "Pester dependency byte count drift: expected $($lock.Pester.ExpectedTotalBytes), actual $totalBytes."
    }

    $byRelative = @{}
    foreach ($entry in $files) { $byRelative[$entry.RelativePath] = $entry }
    $relativeNames = [string[]]@($files | ForEach-Object RelativePath)
    [Array]::Sort($relativeNames, [StringComparer]::Ordinal)
    $treeLines = New-Object System.Collections.Generic.List[string]
    foreach ($relativeName in $relativeNames) {
        $entry = $byRelative[$relativeName]
        $fileHash = (Get-FileHash -LiteralPath $entry.File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
        $treeLines.Add(('{0}|{1}|{2}' -f $relativeName, $fileHash, $entry.File.Length))
    }
    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $treeHash = ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes(($treeLines -join "`n"))))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
    if ($treeHash -cne $lock.Pester.ExpectedTreeSha256) { throw 'Pester dependency tree SHA-256 drift.' }
    $script:PesterTreeSha256 = $treeHash

    $manifestPath = Join-Path $dependencyRoot $lock.Pester.ManifestRelativePath
    if (-not (Test-Path -LiteralPath $manifestPath -PathType Leaf)) { throw 'Pinned Pester manifest is missing.' }
    $manifestHash = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($manifestHash -cne $lock.Pester.ExpectedManifestSha256) { throw 'Pinned Pester manifest SHA-256 drift.' }

    $licensePath = [System.IO.Path]::GetFullPath((Join-Path $script:Root $lock.Pester.LicenseRelativePath))
    if (-not $licensePath.StartsWith($script:Root + '\', [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $licensePath -PathType Leaf)) { throw 'Pinned Pester license path is unsafe or missing.' }
    $licenseItem = Get-Item -LiteralPath $licensePath -Force
    if (($licenseItem.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0 -or [long]$licenseItem.Length -ne [long]$lock.Pester.ExpectedLicenseBytes) { throw 'Pinned Pester license metadata drift.' }
    $licenseHash = (Get-FileHash -LiteralPath $licensePath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($licenseHash -cne $lock.Pester.ExpectedLicenseSha256) { throw 'Pinned Pester license SHA-256 drift.' }
    return $manifestPath
}

function Get-CddsiCommandName {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.CommandAst]$CommandAst)
    $name = $CommandAst.GetCommandName()
    if ([string]::IsNullOrWhiteSpace($name)) { return $null }
    return @($name -split '\\')[-1]
}

function Get-CddsiStaticDotSourceTargets {
    param(
        [Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast,
        [Parameter(Mandatory = $true)][string]$RelativePath,
        [AllowEmptyCollection()][string[]]$BootstrapLibraryFiles = @(),
        [switch]$RequireResolved
    )

    $dotCommands = @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
    }, $true))
    if ($RelativePath -ceq 'lib/bootstrap.ps1') {
        if ($dotCommands.Count -ne 1 -or $dotCommands[0].Extent.Text.Trim() -cne '. $path') {
            throw 'lib/bootstrap.ps1 dot-source site drift.'
        }
        return @($BootstrapLibraryFiles)
    }

    $targets = New-Object System.Collections.Generic.List[string]
    foreach ($dotCommand in $dotCommands) {
        $candidateValues = New-Object System.Collections.Generic.List[string]
        foreach ($stringNode in @($dotCommand.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true))) {
            if ([string]$stringNode.Value -match '(?i)\.ps1$') {
                $candidateValues.Add([string]$stringNode.Value)
            }
        }

        if ($candidateValues.Count -eq 0) {
            $targetVariables = @($dotCommand.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
            foreach ($variableName in $targetVariables) {
                $assignments = @($Ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                        $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                        $node.Left.VariablePath.UserPath -ceq $variableName
                }, $true))
                foreach ($assignment in $assignments) {
                    foreach ($stringNode in @($assignment.Right.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                    }, $true))) {
                        if ([string]$stringNode.Value -match '(?i)\.ps1$') {
                            $candidateValues.Add([string]$stringNode.Value)
                        }
                    }
                }
            }
        }

        $resolvedForSite = @($candidateValues | ForEach-Object { $_.Replace('\', '/').TrimStart([char[]]@('.', '/')) } | Sort-Object -Unique)
        if ($RequireResolved -and $resolvedForSite.Count -ne 1) {
            throw ("{0} has an unresolved or ambiguous product dot-source at line {1}." -f $RelativePath, $dotCommand.Extent.StartLineNumber)
        }
        foreach ($resolved in $resolvedForSite) { $targets.Add($resolved) }
    }
    return @($targets | Sort-Object -Unique)
}

function Get-CddsiAstTypeNames {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast)

    return @($Ast.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.TypeExpressionAst] -or
            $node -is [System.Management.Automation.Language.TypeConstraintAst]
    }, $true) | ForEach-Object { $_.TypeName.FullName } | Where-Object { $_ })
}

function Test-CddsiDevelopmentDependencyPath {
    param([Parameter(Mandatory = $true)][string]$RelativePath)

    return $RelativePath.Replace('\', '/').StartsWith('.dev/modules/Pester/5.6.1/', [StringComparison]::Ordinal)
}

function Get-CddsiForbiddenReflectionFindings {
    param([Parameter(Mandatory = $true)][System.Management.Automation.Language.Ast]$Ast)

    $findings = New-Object System.Collections.Generic.List[string]
    foreach ($node in @($Ast.FindAll({ param($candidate) $candidate -is [System.Management.Automation.Language.MemberExpressionAst] }, $true))) {
        $member = $node.Member.Extent.Text.Trim("'`"")
        $expression = $node.Expression.Extent.Text
        $forbidden = $false
        if ($node.Static -and $member -ieq 'GetType') { $forbidden = $true }
        if ($expression -match '(?i)(?:^|\[)(?:System\.)?Activator\]?$' -and $member -match '(?i)^CreateInstance$') { $forbidden = $true }
        if ($expression -match '(?i)Assembly' -and $member -match '(?i)^Load(?:File|From|WithPartialName)?$') { $forbidden = $true }
        if ($member -ieq 'InvokeMember') { $forbidden = $true }
        if ($member -ieq 'Invoke' -and $expression -match '(?i)(MethodInfo|method|constructor|member)') { $forbidden = $true }
        if ($expression -match '(?i)(ScriptBlock|(?:Automation\.)?PowerShell)' -and $member -match '(?i)^(Create|AddScript)$') { $forbidden = $true }
        if ($member -ieq 'AddScript') { $forbidden = $true }
        if ($forbidden) { $findings.Add(('line {0}:{1}' -f $node.Extent.StartLineNumber, $member)) }
    }
    return $findings.ToArray()
}

function Assert-CddsiWorkerEngineGrant {
    $expectedLeaf = if ($EngineId -ceq 'PowerShell7') { 'pwsh.exe' } else { 'powershell.exe' }
    $fullPath = [System.IO.Path]::GetFullPath($EngineExecutablePath)
    if ((Split-Path -Leaf $fullPath) -cne $expectedLeaf) { throw 'Worker engine executable leaf does not match EngineId.' }
    Assert-CddsiWorkerSha256Value -Value $EngineGrantSha256 -Name 'EngineGrantSha256'
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw 'Worker engine grant executable is missing.' }
    $item = Get-Item -LiteralPath $fullPath -Force
    if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { throw 'Worker engine grant executable is a reparse point.' }
    $actualSha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -cne $EngineGrantSha256) { throw 'Worker engine executable SHA-256 does not match its grant.' }
    return $actualSha256
}

function New-CddsiWorkerSyntheticContext {
    param([Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun')][string]$Mode)

    $syntheticRoot = Join-Path $script:SandboxRoot ('synthetic-product\' + $Mode.ToLowerInvariant())
    $paths = [ordered]@{
        Home = Join-Path $syntheticRoot 'home'
        UserProfile = Join-Path $syntheticRoot 'profile'
        LocalAppData = Join-Path $syntheticRoot 'local-app-data'
        AppData = Join-Path $syntheticRoot 'app-data'
        ProgramData = Join-Path $syntheticRoot 'program-data'
        Temp = Join-Path $syntheticRoot 'temp'
        Download = Join-Path $syntheticRoot 'download'
        State = Join-Path $syntheticRoot 'state'
        Backup = Join-Path $syntheticRoot 'backup'
        Report = Join-Path $syntheticRoot 'report'
        Credential = Join-Path $syntheticRoot 'credential'
        ConfigLibrary = Join-Path $syntheticRoot 'config-library'
        GitGlobalConfig = Join-Path $syntheticRoot 'git-global-config'
        XdgConfig = Join-Path $syntheticRoot 'xdg-config'
        XdgData = Join-Path $syntheticRoot 'xdg-data'
    }
    $policy = [ordered]@{
        SchemaVersion = 1
        AllowLiveProvider = $false
        ForbiddenResourceTokens = @('<REAL_CLAUDE_CONFIG>', '<REAL_GIT_CONFIG>', '<REAL_REGISTRY>', '<REAL_PROCESS>', '<REAL_NETWORK>')
        CanaryTokens = @('<CANARY_CLAUDE_SETTINGS>', '<CANARY_GIT_CONFIG>', '<CANARY_CLAUDE_POLICY>', '<CANARY_CREDENTIAL>')
    }
    $expectedCalls = @(
        [pscustomobject][ordered]@{
            Provider = 'Clock'
            Operation = 'UtcNow'
            ResourceToken = '<CLOCK:UTC>'
            Arguments = [ordered]@{}
            Result = '2030-01-01T00:00:00.0000000Z'
        }
    )
    return New-CddsiExecutionContext `
        -RunId $RunId `
        -Mode $Mode `
        -EnvironmentTier HostSandbox `
        -SandboxRoot $syntheticRoot `
        -Paths $paths `
        -Providers (New-CddsiFakeProviderSet -ExpectedCalls $expectedCalls) `
        -Policy $policy `
        -AccessLedger (New-CddsiAccessLedger)
}

function Measure-CddsiWorkerSyntheticIsolationScenarios {
    $contexts = New-Object System.Collections.Generic.List[object]
    foreach ($mode in @('TestSafe', 'DryRun')) {
        $context = New-CddsiWorkerSyntheticContext -Mode $mode
        $null = Invoke-CddsiProviderOperation -Context $context -Provider Clock -Operation UtcNow -ResourceToken '<CLOCK:UTC>' -Arguments ([ordered]@{})
        Assert-CddsiFakeProviderExpectations -Context $context -RequireNoMutations | Out-Null
        $contexts.Add($context)
    }
    return Measure-CddsiWorkerExecutionContexts -Contexts $contexts.ToArray()
}

if ($EvidenceBuilderOnly) { return }

$script:SandboxBindingSha256 = Assert-CddsiWorkerSandboxBinding
$engineGrantSha256Actual = Assert-CddsiWorkerEngineGrant
$initialRepositoryFiles = @(Get-RepositoryFiles)
$initialInventory = @($initialRepositoryFiles.RelativePath)
$initialContentManifest = @(Get-RepositoryContentManifest)
$initialContentManifestSha256 = Get-CddsiWorkerSequenceSha256 -Values $initialContentManifest
$repositoryInventorySha256 = (Get-FileHash -LiteralPath ([System.IO.Path]::GetFullPath($RepositoryInventoryPath)) -Algorithm SHA256).Hash.ToLowerInvariant()

Invoke-CheckStep -Name 'Execution files have one exact capability-plane owner' -Action {
    $expectedBoundaryPath = Join-Path $script:Root 'config\execution-boundaries.psd1'
    if (-not [string]::Equals([System.IO.Path]::GetFullPath($BoundaryManifestPath), [System.IO.Path]::GetFullPath($expectedBoundaryPath), [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Execution boundary path does not match the repository policy file.'
    }
    $script:ExecutionBoundaryManifestSha256 = (Get-FileHash -LiteralPath $expectedBoundaryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $boundary = Import-PowerShellDataFile -LiteralPath $expectedBoundaryPath
    if ($boundary.SchemaVersion -ne 1) { throw 'Unsupported execution-boundary schema.' }
    foreach ($requiredRuleName in @(
        'DefaultBootstrapLibraryFiles',
        'ProductDotSourceAllowList',
        'LiveAdapterEntryPoints',
        'LiveAdapterCommandAllowList',
        'LiveAdapterTypePrefixAllowList',
        'LiveAdapterRequiredGateCommands',
        'ProductForbiddenCommands',
        'ProductCommandAllowList',
        'ProductForbiddenVariables',
        'ProductForbiddenTypePrefixes',
        'TestForbiddenCommands',
        'TestForbiddenVariables',
        'TestForbiddenTypePrefixes',
        'OperatorCoordinationLibraryFiles',
        'TrustedHarnessDynamicInvocationFiles',
        'TrustedHarnessProcessFiles',
        'TrustedHarnessNetworkFiles',
        'TrustedHarnessReflectionFiles'
    )) {
        if (-not $boundary.Rules.ContainsKey($requiredRuleName)) { throw "Execution-boundary policy is missing rule: $requiredRuleName" }
    }
    if ($boundary.Rules.ProductCommandAllowList.Count -ne 0) { throw 'P1 product command exceptions are forbidden.' }
    $planeNames = @(
        'ProductCore', 'Tests', 'TrustedHarness', 'OperatorCoordination',
        'PolicyData', 'DevelopmentDependencies', 'LiveAdapters'
    )
    $classified = New-Object System.Collections.Generic.List[string]
    foreach ($planeName in $planeNames) {
        foreach ($relative in @($boundary.Planes[$planeName])) { $classified.Add(([string]$relative).Replace('\', '/')) }
    }
    $duplicates = @($classified | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw "Execution boundary duplicates: $($duplicates.Name -join ', ')" }
    $actual = @((Get-RepositoryFiles) | Where-Object { $_.RelativePath -match '\.(ps1|psm1|psd1)$' } | ForEach-Object RelativePath | Sort-Object)
    $classificationDiff = @(Compare-Object -ReferenceObject $actual -DifferenceObject @($classified | Sort-Object))
    if ($classificationDiff.Count -gt 0) {
        $details = @($classificationDiff | ForEach-Object { '{0}:{1}' -f $_.SideIndicator, $_.InputObject }) -join ', '
        throw "Execution boundary inventory mismatch: $details"
    }
    $script:LiveAdapterFileCount = @($boundary.Planes.LiveAdapters).Count
    $expectedLiveAdapters = @('lib/live-adapters.ps1')
    $liveAdapterDiff = @(Compare-Object -ReferenceObject $expectedLiveAdapters -DifferenceObject @($boundary.Planes.LiveAdapters))
    if ($liveAdapterDiff.Count -gt 0) { throw 'Live adapter file allow-list drift.' }
    if ((@($boundary.Rules.LiveAdapterRequiredGateCommands) -join "`n") -cne (@('Assert-CddsiExecutionContext', 'Test-CddsiCommittedOperationUseReceipt') -join "`n")) {
        throw 'Live adapter required-gate command policy drift.'
    }
    foreach ($mapRuleName in @('LiveAdapterEntryPoints', 'LiveAdapterCommandAllowList', 'LiveAdapterTypePrefixAllowList')) {
        $ruleKeys = @($boundary.Rules[$mapRuleName].Keys | Sort-Object)
        if (($ruleKeys -join "`n") -cne (@($expectedLiveAdapters | Sort-Object) -join "`n")) {
            throw "Live adapter $mapRuleName keys do not match the exact file allow-list."
        }
    }
    $releasePolicy = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Root 'scripts/release-manifest.psd1')
    foreach ($relative in $expectedLiveAdapters) {
        if (@($releasePolicy.PackageFiles) -cnotcontains $relative -or @($releasePolicy.DevelopmentOnlyFiles) -ccontains $relative) {
            throw "$relative must be packaged from the exact release allow-list."
        }
    }
    $expectedOperatorLibraries = @('lib/vm-test-relay.ps1', 'lib/vm-reset.ps1')
    if ((@($boundary.Planes.OperatorCoordination | Sort-Object) -join "`n") -cne (@($expectedOperatorLibraries | Sort-Object) -join "`n") -or
        (@($boundary.Rules.OperatorCoordinationLibraryFiles | Sort-Object) -join "`n") -cne (@($expectedOperatorLibraries | Sort-Object) -join "`n")) {
        throw 'Operator coordination library allow-list drift.'
    }
    foreach ($relative in $expectedOperatorLibraries) {
        if (@($releasePolicy.PackageFiles) -ccontains $relative -or @($releasePolicy.DevelopmentOnlyFiles) -cnotcontains $relative) {
            throw "$relative must remain DevelopmentOnly and outside the Release package."
        }
    }
    $lockedDependencyScripts = @(
        '.dev/modules/Pester/5.6.1/Pester.ps1'
        '.dev/modules/Pester/5.6.1/Pester.psd1'
        '.dev/modules/Pester/5.6.1/Pester.psm1'
    )
    $dependencyPlaneDiff = @(Compare-Object -ReferenceObject @($lockedDependencyScripts | Sort-Object) -DifferenceObject @($boundary.Planes.DevelopmentDependencies | Sort-Object))
    if ($dependencyPlaneDiff.Count -gt 0) { throw 'Development dependency execution-file allow-list drift.' }

    $forbiddenCommands = @($boundary.Rules.ProductForbiddenCommands)
    $forbiddenVariables = @($boundary.Rules.ProductForbiddenVariables)
    $forbiddenTypePrefixes = @($boundary.Rules.ProductForbiddenTypePrefixes)

    $bootstrapRelative = 'lib/bootstrap.ps1'
    $bootstrapTokens = $null
    $bootstrapErrors = $null
    $bootstrapAst = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $bootstrapRelative), [ref]$bootstrapTokens, [ref]$bootstrapErrors)
    if (@($bootstrapErrors).Count -gt 0) { throw 'lib/bootstrap.ps1 has PowerShell syntax errors.' }
    $loadOrderAssignments = @($bootstrapAst.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
            $node.Left.VariablePath.UserPath -ceq 'script:CddsiLibraryLoadOrder'
    }, $true))
    if ($loadOrderAssignments.Count -ne 1) { throw 'Default bootstrap load-order assignment drift.' }
    $actualBootstrapFiles = @($loadOrderAssignments[0].Right.FindAll({
        param($node)
        $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
    }, $true) | ForEach-Object { 'lib/' + [string]$_.Value })
    $expectedBootstrapFiles = @($boundary.Rules.DefaultBootstrapLibraryFiles)
    if (($actualBootstrapFiles -join "`n") -cne ($expectedBootstrapFiles -join "`n")) {
        throw 'Default bootstrap load graph differs from its exact ordered allow-list.'
    }
    if (@($expectedBootstrapFiles | Where-Object { @($boundary.Planes.ProductCore) -cnotcontains $_ }).Count -gt 0 -or
        @($expectedBootstrapFiles | Where-Object { @($boundary.Planes.LiveAdapters) -ccontains $_ }).Count -gt 0 -or
        @($expectedBootstrapFiles | Where-Object { @($boundary.Planes.OperatorCoordination) -ccontains $_ }).Count -gt 0) {
        throw 'Default bootstrap load graph escapes ProductCore or includes a live/operator module.'
    }

    $actualProductDotSourceGraph = @{}
    foreach ($relative in @($boundary.Planes.ProductCore)) {
        if ($relative -notmatch '\.(ps1|psm1)$') { continue }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $dotCommands = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
        }, $true))
        if ($dotCommands.Count -gt 0) {
            $actualProductDotSourceGraph[$relative] = @(Get-CddsiStaticDotSourceTargets -Ast $ast -RelativePath $relative `
                -BootstrapLibraryFiles $actualBootstrapFiles -RequireResolved)
        }
    }
    $expectedProductDotSourceFiles = @($boundary.Rules.ProductDotSourceAllowList.Keys | Sort-Object)
    $actualProductDotSourceFiles = @($actualProductDotSourceGraph.Keys | Sort-Object)
    if (($actualProductDotSourceFiles -join "`n") -cne ($expectedProductDotSourceFiles -join "`n")) {
        throw 'ProductCore dot-source file allow-list drift.'
    }
    foreach ($relative in $expectedProductDotSourceFiles) {
        $expectedTargets = @($boundary.Rules.ProductDotSourceAllowList[$relative] | Sort-Object)
        $actualTargets = @($actualProductDotSourceGraph[$relative] | Sort-Object)
        if (($actualTargets -join "`n") -cne ($expectedTargets -join "`n")) {
            throw "$relative dot-source targets differ from the exact load-graph allow-list."
        }
        if (@($actualTargets | Where-Object { @($boundary.Planes.LiveAdapters) -ccontains $_ }).Count -gt 0) {
            throw "$relative dot-sources a live adapter."
        }
    }

    foreach ($relative in @(
        $boundary.Planes.ProductCore + $boundary.Planes.Tests +
        $boundary.Planes.TrustedHarness + $boundary.Planes.OperatorCoordination
    )) {
        if ($relative -notmatch '\.(ps1|psm1)$') { continue }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $dotTargets = @(Get-CddsiStaticDotSourceTargets -Ast $ast -RelativePath $relative -BootstrapLibraryFiles $actualBootstrapFiles)
        foreach ($liveRelative in $expectedLiveAdapters) {
            $liveLeaf = @($liveRelative -split '/')[-1]
            if (@($dotTargets | Where-Object { $_ -ceq $liveRelative -or @($_ -split '/')[-1] -ceq $liveLeaf }).Count -gt 0) {
                throw "$relative dot-sources a live adapter."
            }
            $loadCommands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    ($node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot -or
                    $node.GetCommandName() -ieq 'Import-Module')
            }, $true) | Where-Object { $_.Extent.Text.Replace('\', '/').IndexOf($liveLeaf, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
            $usingModuleStatements = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.UsingStatementAst]
            }, $true) | Where-Object { $_.Extent.Text.Replace('\', '/').IndexOf($liveLeaf, [StringComparison]::OrdinalIgnoreCase) -ge 0 })
            if ($loadCommands.Count -gt 0 -or $usingModuleStatements.Count -gt 0) {
                throw "$relative imports or dot-sources a live adapter."
            }
        }
    }

    foreach ($relative in $expectedLiveAdapters) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $topLevelStatements = @($ast.EndBlock.Statements)
        if ($topLevelStatements.Count -eq 0 -or @($topLevelStatements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] }).Count -gt 0) {
            throw "$relative contains directly executable top-level statements."
        }
        $functionNodes = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $actualEntryPoints = @($functionNodes | ForEach-Object Name | Sort-Object)
        $expectedEntryPoints = @($boundary.Rules.LiveAdapterEntryPoints[$relative] | Sort-Object)
        if (($actualEntryPoints -join "`n") -cne ($expectedEntryPoints -join "`n")) {
            throw "$relative entry points differ from the exact allow-list."
        }
        if ($functionNodes.Count -ne 1) { throw "$relative must expose one auditable Live entry point." }
        $entryPoint = $functionNodes[0]
        $requiredParameters = @(
            'Context', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState',
            'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc'
        )
        $parameterNames = @($entryPoint.Body.ParamBlock.Parameters | ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object)
        if (($parameterNames -join "`n") -cne (@($requiredParameters | Sort-Object) -join "`n")) {
            throw "$relative Live entry-point parameter schema drift."
        }
        foreach ($parameter in @($entryPoint.Body.ParamBlock.Parameters)) {
            $isMandatory = $false
            foreach ($attribute in @($parameter.Attributes | Where-Object { $_.TypeName.FullName -ceq 'Parameter' })) {
                foreach ($namedArgument in @($attribute.NamedArguments | Where-Object { $_.ArgumentName -ieq 'Mandatory' })) {
                    if ($null -eq $namedArgument.Argument -or $namedArgument.Argument.Extent.Text -ieq '$true') { $isMandatory = $true }
                }
            }
            if (-not $isMandatory) { throw "$relative parameter $($parameter.Name.VariablePath.UserPath) must be mandatory." }
        }
        $contextParameter = @($entryPoint.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'Context' })[0]
        $contextAliases = @($contextParameter.Attributes | Where-Object { $_.TypeName.FullName -ceq 'Alias' } | ForEach-Object { $_.PositionalArguments[0].Value })
        if ($contextAliases.Count -ne 1 -or $contextAliases[0] -cne 'ExecutionContext') {
            throw "$relative Context must use the exact ExecutionContext alias."
        }

        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $dotOrImportCommands = @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot -or
                $_.GetCommandName() -ieq 'Import-Module'
        })
        $dynamicCommands = @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and
                [string]::IsNullOrWhiteSpace($_.GetCommandName())
        })
        if ($dotOrImportCommands.Count -gt 0 -or $dynamicCommands.Count -gt 0) {
            throw "$relative must not dot-source, import or dynamically invoke code."
        }
        $commandNames = @($commands | ForEach-Object { Get-CddsiCommandName -CommandAst $_ } | Where-Object { $_ })
        foreach ($gateName in @($boundary.Rules.LiveAdapterRequiredGateCommands)) {
            if (@($commandNames | Where-Object { $_ -ceq $gateName }).Count -ne 1) {
                throw "$relative must call required gate $gateName exactly once."
            }
        }
        $assertGate = @($commands | Where-Object { (Get-CddsiCommandName -CommandAst $_) -ceq 'Assert-CddsiExecutionContext' })[0]
        $receiptGate = @($commands | Where-Object { (Get-CddsiCommandName -CommandAst $_) -ceq 'Test-CddsiCommittedOperationUseReceipt' })[0]
        if ($assertGate.Extent.Text -notmatch '(?i)-ExpectedMode\s+Live' -or
            $entryPoint.Extent.Text -notmatch "(?s)EnvironmentTier\s+-cne\s+'VmAcceptance'" -or
            $entryPoint.Extent.Text -notmatch "(?s)Stage\s+-cne\s+'VmAcceptance'" -or
            $entryPoint.Extent.Text -notmatch "(?s)ArtifactProfile\s+-cne\s+'VmAcceptance'") {
            throw "$relative does not statically require the disposable VmAcceptance boundary."
        }
        foreach ($bindingName in @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc')) {
            if ($receiptGate.Extent.Text -notmatch ('(?i)-' + [regex]::Escape($bindingName) + '\s+')) {
                throw "$relative committed operation-use gate omits $bindingName."
            }
        }
        if ($assertGate.Extent.StartOffset -ge $receiptGate.Extent.StartOffset) {
            throw "$relative execution-context gate must precede the operation-use gate."
        }

        $actualLiveCommands = @($commandNames | Where-Object { $forbiddenCommands -ccontains $_ } | Sort-Object -Unique)
        $allowedLiveCommands = @($boundary.Rules.LiveAdapterCommandAllowList[$relative] | Sort-Object)
        if (($actualLiveCommands -join "`n") -cne ($allowedLiveCommands -join "`n")) {
            throw "$relative system-command capability allow-list drift."
        }
        foreach ($hostCommand in @($commands | Where-Object { $forbiddenCommands -ccontains (Get-CddsiCommandName -CommandAst $_) })) {
            if ($hostCommand.Extent.StartOffset -le $receiptGate.Extent.EndOffset) {
                throw "$relative contains a system capability before the committed operation-use gate."
            }
        }
        $types = @(Get-CddsiAstTypeNames -Ast $ast | Sort-Object -Unique)
        $actualLiveTypePrefixes = @($forbiddenTypePrefixes | Where-Object {
            $prefix = $_
            @($types | Where-Object { $_.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        } | Sort-Object)
        $allowedLiveTypePrefixes = @($boundary.Rules.LiveAdapterTypePrefixAllowList[$relative] | Sort-Object)
        if (($actualLiveTypePrefixes -join "`n") -cne ($allowedLiveTypePrefixes -join "`n")) {
            throw "$relative system-type capability allow-list drift."
        }
        $reflectionHits = @(Get-CddsiForbiddenReflectionFindings -Ast $ast)
        if ($reflectionHits.Count -gt 0) { throw "$relative uses forbidden reflection or dynamic code: $($reflectionHits -join ', ')" }
    }

    foreach ($relative in @($boundary.Planes.ProductCore)) {
        if ($relative -notmatch '\.(ps1|psm1)$') { continue }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $allowedCommands = @()
        if ($boundary.Rules.ProductCommandAllowList.ContainsKey($relative)) {
            $allowedCommands = @($boundary.Rules.ProductCommandAllowList[$relative])
        }
        $commandHits = @($commands | ForEach-Object { Get-CddsiCommandName -CommandAst $_ } | Where-Object { $_ -and $forbiddenCommands -contains $_ -and $allowedCommands -notcontains $_ } | Sort-Object -Unique)
        if ($commandHits.Count -gt 0) { throw "$relative bypasses providers with commands: $($commandHits -join ', ')" }
        $dynamicCalls = @($commands | Where-Object { $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and [string]::IsNullOrWhiteSpace($_.GetCommandName()) })
        if ($dynamicCalls.Count -gt 0) { throw "$relative contains a dynamic command invocation." }
        $variableHits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Where-Object { $forbiddenVariables -contains $_ -or $_.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase) } | Sort-Object -Unique)
        if ($variableHits.Count -gt 0) { throw "$relative resolves host variables: $($variableHits -join ', ')" }
        $types = @(Get-CddsiAstTypeNames -Ast $ast)
        $typeHits = @($types | Where-Object {
            $candidate = $_
            @($forbiddenTypePrefixes | Where-Object { $candidate.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        } | Sort-Object -Unique)
        if ($typeHits.Count -gt 0) { throw "$relative references host types: $($typeHits -join ', ')" }
        $reflectionHits = @(Get-CddsiForbiddenReflectionFindings -Ast $ast)
        if ($reflectionHits.Count -gt 0) { throw "$relative uses forbidden reflection or dynamic code: $($reflectionHits -join ', ')" }
    }

    foreach ($relative in @($boundary.Planes.OperatorCoordination)) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $topLevelStatements = @($ast.EndBlock.Statements)
        $invalidTopLevel = @($topLevelStatements | Where-Object {
            $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $_ -isnot [System.Management.Automation.Language.AssignmentStatementAst]
        })
        if ($invalidTopLevel.Count -gt 0) { throw "$relative contains executable operator-coordination top-level statements." }
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $commandHits = @(
            $commands |
                ForEach-Object { Get-CddsiCommandName -CommandAst $_ } |
                Where-Object { $_ -and $forbiddenCommands -contains $_ } |
                Sort-Object -Unique
        )
        if ($commandHits.Count -gt 0) { throw "$relative contains direct host capabilities: $($commandHits -join ', ')" }
        $variableHits = @(
            $ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) |
                ForEach-Object { $_.VariablePath.UserPath } |
                Where-Object { $forbiddenVariables -contains $_ -or $_.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase) } |
                Sort-Object -Unique
        )
        if ($variableHits.Count -gt 0) { throw "$relative resolves host variables: $($variableHits -join ', ')" }
        $types = @(Get-CddsiAstTypeNames -Ast $ast)
        $typeHits = @($types | Where-Object {
            $candidate = $_
            @($forbiddenTypePrefixes | Where-Object { $candidate.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        } | Sort-Object -Unique)
        if ($typeHits.Count -gt 0) { throw "$relative references host types: $($typeHits -join ', ')" }
        $reflectionHits = @(Get-CddsiForbiddenReflectionFindings -Ast $ast)
        if ($reflectionHits.Count -gt 0) { throw "$relative uses forbidden reflection or dynamic code: $($reflectionHits -join ', ')" }
    }

    $testForbiddenCommands = @($boundary.Rules.TestForbiddenCommands)
    $testForbiddenVariables = @($boundary.Rules.TestForbiddenVariables)
    $testForbiddenTypePrefixes = @($boundary.Rules.TestForbiddenTypePrefixes)
    if ($testForbiddenCommands.Count -eq 0 -or $testForbiddenVariables.Count -eq 0 -or $testForbiddenTypePrefixes.Count -eq 0) {
        throw 'Test host-capability policy must not be empty.'
    }
    foreach ($relative in @($boundary.Planes.Tests)) {
        if ($relative -notmatch '\.(ps1|psm1)$') { continue }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $commandHits = @($commands | ForEach-Object { Get-CddsiCommandName -CommandAst $_ } | Where-Object { $_ -and $testForbiddenCommands -contains $_ } | Sort-Object -Unique)
        if ($commandHits.Count -gt 0) { throw "$relative invokes forbidden host capabilities: $($commandHits -join ', ')" }
        $variableHits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Where-Object { $testForbiddenVariables -contains $_ -or $_.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase) } | Sort-Object -Unique)
        if ($variableHits.Count -gt 0) { throw "$relative resolves host variables: $($variableHits -join ', ')" }
        $types = @(Get-CddsiAstTypeNames -Ast $ast)
        $typeHits = @($types | Where-Object {
            $candidate = $_
            @($testForbiddenTypePrefixes | Where-Object { $candidate.StartsWith($_, [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        } | Sort-Object -Unique)
        if ($typeHits.Count -gt 0) { throw "$relative references forbidden host types: $($typeHits -join ', ')" }
        $reflectionHits = @(Get-CddsiForbiddenReflectionFindings -Ast $ast)
        if ($reflectionHits.Count -gt 0) { throw "$relative uses forbidden reflection or dynamic code: $($reflectionHits -join ', ')" }
    }

    $trustedHarnessFiles = @($boundary.Planes.TrustedHarness)
    $capabilityRules = @(
        [pscustomobject]@{ Name = 'DynamicInvocation'; PolicyProperty = 'TrustedHarnessDynamicInvocationFiles' }
        [pscustomobject]@{ Name = 'Process'; PolicyProperty = 'TrustedHarnessProcessFiles' }
        [pscustomobject]@{ Name = 'Network'; PolicyProperty = 'TrustedHarnessNetworkFiles' }
        [pscustomobject]@{ Name = 'Reflection'; PolicyProperty = 'TrustedHarnessReflectionFiles' }
    )
    foreach ($capabilityRule in $capabilityRules) {
        $allowedFiles = @($boundary.Rules[$capabilityRule.PolicyProperty])
        $duplicates = @($allowedFiles | Group-Object | Where-Object Count -gt 1)
        if ($duplicates.Count -gt 0) { throw "Trusted harness $($capabilityRule.Name) allow-list has duplicates: $($duplicates.Name -join ', ')" }
        $outsideHarness = @($allowedFiles | Where-Object { $trustedHarnessFiles -notcontains $_ })
        if ($outsideHarness.Count -gt 0) { throw "Trusted harness $($capabilityRule.Name) allow-list escapes its plane: $($outsideHarness -join ', ')" }
    }

    $actualDynamicFiles = New-Object System.Collections.Generic.List[string]
    $actualProcessFiles = New-Object System.Collections.Generic.List[string]
    $actualNetworkFiles = New-Object System.Collections.Generic.List[string]
    $actualReflectionFiles = New-Object System.Collections.Generic.List[string]
    $harnessProcessCommands = @('Start-Process', 'Start-Job', 'Invoke-Command', 'New-PSSession', 'Enter-PSSession', 'git', 'git.exe', 'pwsh', 'pwsh.exe', 'powershell', 'powershell.exe', 'cmd', 'cmd.exe', 'msiexec', 'msiexec.exe', 'winget', 'winget.exe')
    $harnessNetworkCommands = @('Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'Save-Module', 'Install-Module', 'curl', 'curl.exe', 'wget', 'wget.exe')
    foreach ($relative in $trustedHarnessFiles) {
        if ($relative -notmatch '\.(ps1|psm1)$') { continue }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        if (@($errors).Count -gt 0) { throw "$relative has PowerShell syntax errors." }
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $dynamicInvocations = @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -or
                $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
        })
        if ($dynamicInvocations.Count -gt 0) {
            $actualDynamicFiles.Add($relative)
        }
        $commandNames = @($commands | ForEach-Object { Get-CddsiCommandName -CommandAst $_ } | Where-Object { $_ })
        $types = @(Get-CddsiAstTypeNames -Ast $ast)
        $hasProcessCommand = @($commandNames | Where-Object { $harnessProcessCommands -contains $_ }).Count -gt 0
        $hasProcessType = @($types | Where-Object { $_.StartsWith('System.Diagnostics.Process', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if ($hasProcessCommand -or $hasProcessType) { $actualProcessFiles.Add($relative) }
        $hasNetworkCommand = @($commandNames | Where-Object { $harnessNetworkCommands -contains $_ }).Count -gt 0
        $hasNetworkType = @($types | Where-Object { $_.StartsWith('System.Net.', [StringComparison]::OrdinalIgnoreCase) }).Count -gt 0
        if ($hasNetworkCommand -or $hasNetworkType) { $actualNetworkFiles.Add($relative) }
        if (@(Get-CddsiForbiddenReflectionFindings -Ast $ast).Count -gt 0) { $actualReflectionFiles.Add($relative) }
    }

    $actualByCapability = @{
        TrustedHarnessDynamicInvocationFiles = $actualDynamicFiles.ToArray()
        TrustedHarnessProcessFiles           = $actualProcessFiles.ToArray()
        TrustedHarnessNetworkFiles           = $actualNetworkFiles.ToArray()
        TrustedHarnessReflectionFiles        = $actualReflectionFiles.ToArray()
    }
    foreach ($capabilityRule in $capabilityRules) {
        $expected = @($boundary.Rules[$capabilityRule.PolicyProperty] | Sort-Object)
        $actual = @($actualByCapability[$capabilityRule.PolicyProperty] | Sort-Object)
        $capabilityDiff = @(Compare-Object -ReferenceObject $expected -DifferenceObject $actual)
        if ($capabilityDiff.Count -gt 0) {
            $details = @($capabilityDiff | ForEach-Object { '{0}:{1}' -f $_.SideIndicator, $_.InputObject }) -join ', '
            throw "Trusted harness $($capabilityRule.Name) capability allow-list drift: $details"
        }
    }

    $encodedCommandPattern = '(?i)(?:^|\s)-Encoded' + 'Command(?:\s|$)'
    $executionPolicyBypassPattern = '(?i)-Execution' + 'Policy\s+Bypass'
    foreach ($relative in @(
        $boundary.Planes.ProductCore + $boundary.Planes.Tests +
        $boundary.Planes.TrustedHarness + $boundary.Planes.OperatorCoordination
    )) {
        if ($relative -notmatch '\.(ps1|psm1)$') { continue }
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        $commandText = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.Extent.Text }) -join "`n"
        if ($commandText -match $encodedCommandPattern -or $commandText -match $executionPolicyBypassPattern) {
            throw "$relative contains a prohibited child-shell invocation pattern."
        }
    }
}

Invoke-CheckStep -Name 'Forbidden runtime artifact directories are absent' -Action {
    foreach ($name in @('release', 'artifacts', 'logs', 'backup', 'reports', 'TestResults')) {
        if (Test-Path -LiteralPath (Join-Path $script:Root $name)) { throw "Runtime artifact directory must not exist in the source tree: $name" }
    }
}

Invoke-CheckStep -Name 'Release manifest classifies every repository file exactly once' -Action {
    $manifestPath = Join-Path $PSScriptRoot 'release-manifest.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    if ($manifest.SchemaVersion -ne 1) { throw 'Unsupported release manifest schema.' }
    $package = @($manifest.PackageFiles)
    $development = @($manifest.DevelopmentOnlyFiles)
    $classified = @($package + $development)
    $duplicates = @($classified | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw "Manifest has duplicate entries: $($duplicates.Name -join ', ')" }
    $diff = @(Compare-Object -ReferenceObject $initialInventory -DifferenceObject @($classified | Sort-Object))
    if ($diff.Count -gt 0) {
        $details = @($diff | ForEach-Object { '{0}:{1}' -f $_.SideIndicator, $_.InputObject }) -join ', '
        throw "Manifest inventory mismatch: $details"
    }
    foreach ($entry in $package) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:Root $entry) -PathType Leaf)) { throw "Missing package file: $entry" }
    }
}

Invoke-CheckStep -Name 'Documentation system is complete and discoverable' -Action {
    $manifest = Import-PowerShellDataFile -LiteralPath (Join-Path $PSScriptRoot 'release-manifest.psd1')
    $documentation = @((Get-RepositoryFiles) | Where-Object { $_.RelativePath -match '^docs/.+\.md$' })
    foreach ($item in $documentation) {
        $relative = $item.RelativePath
        $path = Join-Path $script:Root $relative
        if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Required documentation is missing: $relative" }
        if ($relative -eq 'docs/SECURITY.md') {
            if (@($manifest.PackageFiles) -notcontains $relative) { throw "Packaged documentation is not classified correctly: $relative" }
        }
        elseif (@($manifest.DevelopmentOnlyFiles) -notcontains $relative) {
            throw "Development documentation is not classified correctly: $relative"
        }
    }

    $index = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\README.md') -DisplayPath 'docs/README.md'
    foreach ($item in $documentation) {
        $exactReference = '`' + $item.RelativePath + '`'
        if (-not $index.Contains($exactReference)) { throw "Documentation index does not reference the exact project path: $($item.RelativePath)" }
    }

    foreach ($markdown in @((Get-RepositoryFiles) | Where-Object { $_.RelativePath -like '*.md' })) {
        $content = Read-CddsiStrictUtf8Text -Path $markdown.File.FullName -DisplayPath $markdown.RelativePath
        $references = @([regex]::Matches($content, '(?<![A-Za-z0-9_./-])docs/[A-Za-z0-9_-]+\.md') | ForEach-Object { $_.Value } | Sort-Object -Unique)
        foreach ($reference in $references) {
            if (-not (Test-Path -LiteralPath (Join-Path $script:Root $reference) -PathType Leaf)) {
                throw "$($markdown.RelativePath) references missing local documentation: $reference"
            }
        }
        $fenceCount = [regex]::Matches($content, '(?m)^[\t ]*(?:```|~~~)').Count
        if (($fenceCount % 2) -ne 0) { throw "$($markdown.RelativePath) has unbalanced fenced code blocks." }
    }

    $readme = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'README.md') -DisplayPath 'README.md'
    foreach ($reference in @('docs/HANDOFF.md', 'docs/README.md', 'docs/TEST_ISOLATION.md', 'docs/VM_TEST_RELAY.md', 'docs/VM_ACCEPTANCE_PLAN.md')) {
        if (-not $readme.Contains($reference)) { throw "README does not expose required documentation: $reference" }
    }

    $product = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\PRODUCT_SPEC.md') -DisplayPath 'docs/PRODUCT_SPEC.md'
    foreach ($marker in @(
        '不展示 Chat/Code/Cowork 选择页',
        'Git 是产品必备前置',
        '`RequestedSurfaces` 固定为三项',
        '`SUCCEEDED/PARTIAL/RESTART_REQUIRED/ACTION_REQUIRED/CANCELLED/FAILED`'
    )) {
        if (-not $product.Contains($marker)) { throw "Product specification is missing fixed all-surfaces marker: $marker" }
    }
    if ($product.Contains('### 3. 能力选择')) { throw 'Product specification must not expose a capability-selection step.' }

    $decisions = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\DECISIONS.md') -DisplayPath 'docs/DECISIONS.md'
    foreach ($marker in @(
        'D-016：固定完整功能目标',
        'D-017：Git 是产品必备前置',
        'D-018：每个 Release 冻结单一 MSIX 部署范围',
        'D-019：分层状态模型'
    )) {
        if (-not $decisions.Contains($marker)) { throw "Decision log is missing product-flow decision: $marker" }
    }

    $isolation = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\TEST_ISOLATION.md') -DisplayPath 'docs/TEST_ISOLATION.md'
    foreach ($marker in @(
        '%USERPROFILE%\.claude\**',
        '%LOCALAPPDATA%\Claude-3p\**',
        'HKCU\SOFTWARE\Policies\Claude',
        'LIVE_PROVIDER_LOADED = false',
        'FORBIDDEN_RESOURCE_ACCESS_COUNT = 0',
        'PRODUCT_NETWORK_REQUEST_COUNT = 0',
        'P1 Sandbox Foundation'
    )) {
        if (-not $isolation.Contains($marker)) { throw "Test isolation contract is missing marker: $marker" }
    }

    $plan = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\IMPLEMENTATION_PLAN.md') -DisplayPath 'docs/IMPLEMENTATION_PLAN.md'
    foreach ($phase in 0..12) {
        $phaseName = 'P' + $phase
        if (-not $plan.Contains($phaseName)) { throw "Implementation plan is missing phase $phaseName." }
    }
    foreach ($marker in @('Sandbox Foundation', 'Release Candidate', 'VM Codex Live 验收')) {
        if (-not $plan.Contains($marker)) { throw "Implementation plan is missing marker: $marker" }
    }

    $handoff = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\HANDOFF.md') -DisplayPath 'docs/HANDOFF.md'
    foreach ($marker in @('P1 Sandbox Foundation', '不需要重新从零调研', '不在开发机执行 Live')) {
        if (-not $handoff.Contains($marker)) { throw "Handoff is missing marker: $marker" }
    }

    $relay = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\VM_TEST_RELAY.md') -DisplayPath 'docs/VM_TEST_RELAY.md'
    foreach ($marker in @(
        '宿主机 Codex 是唯一代码写入者',
        'VM Codex 只测试、分析和回传',
        '外部 hypervisor supervisor',
        'git fetch',
        'checkout --detach',
        'P10A → 冻结事实 → P10B → P11',
        'TEST_RESULT',
        'FIX_READY',
        '不得把 relay 消息当作 P11 acceptance receipt'
    )) {
        if (-not $relay.Contains($marker)) { throw "VM test relay contract is missing marker: $marker" }
    }

    $contracts = Read-CddsiStrictUtf8Text -Path (Join-Path $script:Root 'docs\EXTERNAL_CONTRACTS.md') -DisplayPath 'docs/EXTERNAL_CONTRACTS.md'
    foreach ($marker in @(
        'https://claude.com/docs/third-party/claude-desktop/configuration',
        'https://api.deepseek.com/anthropic',
        'deepseek-v4-flash',
        'deepseek-v4-pro'
    )) {
        if (-not $contracts.Contains($marker)) { throw "External contract baseline is missing marker: $marker" }
    }
}

Invoke-CheckStep -Name 'Test sources pass the baseline host-access pattern guard' -Action {
    $forbiddenCommands = @(
        'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer', 'curl', 'curl.exe', 'wget', 'iwr', 'irm',
        'Get-AppxPackage', 'Add-AppxPackage', 'Remove-AppxPackage', 'Add-AppxProvisionedPackage',
        'Get-WindowsOptionalFeature', 'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature',
        'Get-Service', 'Start-Service', 'Stop-Service', 'Set-Service',
        'Get-ScheduledTask', 'Register-ScheduledTask', 'Unregister-ScheduledTask',
        'Get-ItemProperty', 'Set-ItemProperty', 'New-ItemProperty', 'Remove-ItemProperty',
        'Get-CimInstance', 'Get-WmiObject', 'Get-Process', 'Start-Process', 'saps', 'Stop-Process', 'Restart-Computer',
        'Test-NetConnection', 'Resolve-DnsName', 'Add-Type',
        'shutdown', 'shutdown.exe', 'reg', 'reg.exe', 'winget', 'winget.exe'
    )
    $forbiddenTypes = @(
        'Environment',
        'System.Environment',
        'Microsoft.Win32.Registry',
        'Microsoft.Win32.RegistryKey',
        'System.Diagnostics.Process',
        'System.Diagnostics.ProcessStartInfo',
        'System.Net.WebClient',
        'System.Net.WebRequest',
        'System.Net.Http.HttpClient',
        'System.Net.Sockets.Socket',
        'System.Net.Sockets.TcpClient'
    )
    $forbiddenVariables = @(
        'HOME', 'PROFILE', 'USERPROFILE', 'LOCALAPPDATA', 'APPDATA', 'PROGRAMDATA', 'HOMEDRIVE', 'HOMEPATH',
        'env:HOME', 'env:USERPROFILE', 'env:LOCALAPPDATA', 'env:APPDATA', 'env:PROGRAMDATA', 'env:HOMEDRIVE', 'env:HOMEPATH'
    )
    $testFiles = @(Get-RepositoryFiles | Where-Object { $_.RelativePath -match '^tests/.+\.(ps1|psm1|psd1)$' })
    foreach ($item in $testFiles) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($item.File.FullName, [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object {
            $commandName = $_.GetCommandName()
            if ($commandName) { @($commandName -split '\\')[-1] }
        } | Where-Object { $_ })
        $commandHits = @($commands | Where-Object { $forbiddenCommands -contains $_ } | Sort-Object -Unique)
        if ($commandHits.Count -gt 0) { throw "$($item.RelativePath) invokes forbidden host commands: $($commandHits -join ', ')" }
        $typeHits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName } | Where-Object { $forbiddenTypes -contains $_ } | Sort-Object -Unique)
        if ($typeHits.Count -gt 0) { throw "$($item.RelativePath) references forbidden host types: $($typeHits -join ', ')" }
        $variableHits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.VariableExpressionAst] }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Where-Object { $forbiddenVariables -contains $_ } | Sort-Object -Unique)
        if ($variableHits.Count -gt 0) { throw "$($item.RelativePath) references forbidden host variables: $($variableHits -join ', ')" }
    }
}

Invoke-CheckStep -Name 'PowerShell AST syntax' -Action {
    $powerShellFiles = @(Get-RepositoryFiles | Where-Object { -not (Test-CddsiDevelopmentDependencyPath -RelativePath $_.RelativePath) -and $_.RelativePath -match '\.(ps1|psd1)$' })
    $allErrors = New-Object System.Collections.Generic.List[string]
    foreach ($item in $powerShellFiles) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($item.File.FullName, [ref]$tokens, [ref]$errors)
        foreach ($parseError in @($errors)) {
            $allErrors.Add("$($item.RelativePath):$($parseError.Extent.StartLineNumber): $($parseError.Message)")
        }
    }
    $script:AstSyntaxErrorCount = $allErrors.Count
    if ($allErrors.Count -gt 0) { throw ($allErrors -join ' | ') }
}

Invoke-CheckStep -Name 'JSON parsing and defaults contract' -Action {
    $jsonFiles = @(Get-RepositoryFiles | Where-Object { $_.RelativePath -like '*.json' })
    foreach ($item in $jsonFiles) {
        $text = [System.IO.File]::ReadAllText($item.File.FullName, [System.Text.Encoding]::UTF8)
        try { $null = $text | ConvertFrom-Json -ErrorAction Stop } catch { throw "Invalid JSON: $($item.RelativePath)" }
    }
    $configPath = Join-Path $script:Root 'config\deepseek-desktop.defaults.json'
    $config = ([System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
    if (($config.schemaVersion -isnot [int] -and $config.schemaVersion -isnot [long]) -or [long]$config.schemaVersion -ne 2) { throw 'Defaults schemaVersion must be integer 2.' }
    if ($config.projectStage -cne 'scaffold' -or $config.execution.defaultMode -cne 'TestSafe') { throw 'Defaults must stay scaffold/TestSafe.' }
    foreach ($entry in @(
        @($config.execution.liveEnabled, $false, 'execution.liveEnabled'),
        @($config.execution.requireExplicitLiveAcknowledgement, $true, 'execution.requireExplicitLiveAcknowledgement'),
        @($config.execution.automaticRestartAllowed, $false, 'execution.automaticRestartAllowed'),
        @($config.desktop3p.configLibraryWriterEnabled, $false, 'desktop3p.configLibraryWriterEnabled'),
        @($config.desktop3p.modelPolicy.discoveryEnabled, $false, 'desktop3p.modelPolicy.discoveryEnabled'),
        @($config.desktop3p.surfacePolicy.chatEnabled, $true, 'desktop3p.surfacePolicy.chatEnabled'),
        @($config.desktop3p.surfacePolicy.codeEnabled, $true, 'desktop3p.surfacePolicy.codeEnabled'),
        @($config.desktop3p.surfacePolicy.coworkEnabled, $true, 'desktop3p.surfacePolicy.coworkEnabled'),
        @($config.desktop3p.surfacePolicy.autoModeEnabled, $false, 'desktop3p.surfacePolicy.autoModeEnabled'),
        @($config.desktop3p.deploymentChooserPolicy.disabled, $true, 'desktop3p.deploymentChooserPolicy.disabled'),
        @($config.desktop3p.credentialReference.silentRefreshEnabled, $true, 'desktop3p.credentialReference.silentRefreshEnabled'),
        @($config.desktop3p.credentialReference.persistInConfig, $false, 'desktop3p.credentialReference.persistInConfig'),
        @($config.desktop3p.validationRequestEnabled, $false, 'desktop3p.validationRequestEnabled'),
        @($config.claudeDesktopMsix.requireAuthenticodeSignature, $true, 'claudeDesktopMsix.requireAuthenticodeSignature'),
        @($config.claudeDesktopMsix.requireTrustedChain, $true, 'claudeDesktopMsix.requireTrustedChain'),
        @($config.claudeDesktopMsix.requireExecutionTimeHashReverification, $true, 'claudeDesktopMsix.requireExecutionTimeHashReverification'),
        @($config.gitForWindows.requireAuthenticodeSignature, $true, 'gitForWindows.requireAuthenticodeSignature'),
        @($config.gitForWindows.requireTrustedChain, $true, 'gitForWindows.requireTrustedChain'),
        @($config.gitForWindows.requireExecutionTimeHashReverification, $true, 'gitForWindows.requireExecutionTimeHashReverification'),
        @($config.gitForWindows.silentInstallEnabled, $false, 'gitForWindows.silentInstallEnabled'),
        @($config.gitForWindows.modifyGlobalGitConfig, $false, 'gitForWindows.modifyGlobalGitConfig'),
        @($config.cowork.checkVirtualMachinePlatform, $true, 'cowork.checkVirtualMachinePlatform'),
        @($config.cowork.checkHardwareVirtualization, $true, 'cowork.checkHardwareVirtualization'),
        @($config.cowork.checkService, $true, 'cowork.checkService'),
        @($config.cowork.enableWindowsFeature, $false, 'cowork.enableWindowsFeature'),
        @($config.cowork.restartEnabled, $false, 'cowork.restartEnabled')
    )) {
        if ($entry[0] -isnot [bool] -or $entry[0] -ne $entry[1]) { throw "Unsafe or mistyped default: $($entry[2])" }
    }
    if ($config.desktop3p.contractVersion -cne 'claude-desktop-3p-managed-policy-v1' -or $config.desktop3p.minimumDesktopVersion -cne '1.20186.0' -or $config.desktop3p.windowsPolicyNoMergeSince -cne '1.19367.0') { throw 'Desktop 3P contract version drift.' }
    if ($config.desktop3p.targetSource -cne 'HKCU_MANAGED_POLICY' -or $config.desktop3p.registryKey -cne 'HKCU\SOFTWARE\Policies\Claude' -or $config.desktop3p.existingSourcePolicy -cne 'conflict-stop') { throw 'Desktop 3P target ownership drift.' }
    if ($config.desktop3p.claudeCodeSettingsPolicy -cne 'do_not_read_or_modify') { throw 'Claude Code settings policy drift.' }
    if ((@($config.desktop3p.sourcePrecedence) -join '|') -cne 'HKLM_MANAGED_POLICY|HKCU_MANAGED_POLICY|CONFIG_LIBRARY') { throw 'Desktop 3P source precedence drift.' }
    if ($config.desktop3p.provider.kind -cne 'gateway' -or $config.desktop3p.provider.baseUrl -cne 'https://api.deepseek.com/anthropic' -or $config.desktop3p.provider.authScheme -cne 'x-api-key') { throw 'DeepSeek gateway defaults drift.' }
    $defaultModels = @($config.desktop3p.modelPolicy.models)
    if ($defaultModels.Count -ne 2 -or $defaultModels[0].name -cne 'deepseek-v4-pro' -or $defaultModels[1].name -cne 'deepseek-v4-flash' -or $defaultModels[0].supports1m -isnot [bool] -or -not $defaultModels[0].supports1m -or $defaultModels[1].supports1m -isnot [bool] -or -not $defaultModels[1].supports1m) { throw 'Fixed V4 model list drift.' }
    if ((@($config.desktop3p.requestedSurfaces) -join '|') -cne 'Chat|Code|Cowork') { throw 'RequestedSurfaces drift.' }
    if ($config.desktop3p.credentialReference.kind -cne 'helper-script' -or $config.desktop3p.credentialReference.helperBinding -cne '<CREDENTIAL_HELPER_PATH>' -or [long]$config.desktop3p.credentialReference.ttlSeconds -ne 3600 -or [long]$config.desktop3p.credentialReference.timeoutSeconds -ne 60) { throw 'Credential helper defaults drift.' }
    if ($config.claudeDesktopMsix.sourcePolicy -cne 'anthropic_official_only' -or $null -ne $config.claudeDesktopMsix.metadataUri -or $null -ne $config.claudeDesktopMsix.downloadUri -or $null -ne $config.claudeDesktopMsix.expectedArtifactSha256 -or $null -ne $config.claudeDesktopMsix.expectedArtifactSizeBytes -or $null -ne $config.claudeDesktopMsix.expectedSignerThumbprint -or $null -ne $config.claudeDesktopMsix.expectedSignerSubjectToken -or $null -ne $config.claudeDesktopMsix.expectedPublisher -or $null -ne $config.claudeDesktopMsix.packageIdentity -or $config.claudeDesktopMsix.requireAuthenticodeSignature -isnot [bool] -or -not $config.claudeDesktopMsix.requireAuthenticodeSignature -or $config.claudeDesktopMsix.requireTrustedChain -isnot [bool] -or -not $config.claudeDesktopMsix.requireTrustedChain -or $config.claudeDesktopMsix.requireExecutionTimeHashReverification -isnot [bool] -or -not $config.claudeDesktopMsix.requireExecutionTimeHashReverification -or $config.claudeDesktopMsix.redirectPolicy -cne 'same-owner-https-only' -or [long]$config.claudeDesktopMsix.maximumBytes -ne 4294967296) { throw 'MSIX official-source scaffold defaults drift.' }
    if ($config.gitForWindows.sourcePolicy -cne 'git_for_windows_official_only' -or $config.gitForWindows.metadataApiUri -cne 'https://api.github.com/repos/git-for-windows/git/releases/latest' -or $null -ne $config.gitForWindows.downloadUri -or $null -ne $config.gitForWindows.expectedArtifactSha256 -or $null -ne $config.gitForWindows.expectedArtifactSizeBytes -or $null -ne $config.gitForWindows.expectedSignerThumbprint -or $null -ne $config.gitForWindows.expectedSignerSubjectToken -or $null -ne $config.gitForWindows.expectedPublisher -or $null -ne $config.gitForWindows.installerIdentity -or $config.gitForWindows.requireAuthenticodeSignature -isnot [bool] -or -not $config.gitForWindows.requireAuthenticodeSignature -or $config.gitForWindows.requireTrustedChain -isnot [bool] -or -not $config.gitForWindows.requireTrustedChain -or $config.gitForWindows.requireExecutionTimeHashReverification -isnot [bool] -or -not $config.gitForWindows.requireExecutionTimeHashReverification -or $config.gitForWindows.redirectPolicy -cne 'same-owner-https-only' -or [long]$config.gitForWindows.maximumBytes -ne 1073741824 -or $config.gitForWindows.silentInstallEnabled -isnot [bool] -or $config.gitForWindows.silentInstallEnabled -or $config.gitForWindows.modifyGlobalGitConfig -isnot [bool] -or $config.gitForWindows.modifyGlobalGitConfig) { throw 'Git official-source scaffold defaults drift.' }
}

Invoke-CheckStep -Name 'Encoding and line-ending baseline' -Action {
    foreach ($item in @(Get-RepositoryFiles | Where-Object { -not (Test-CddsiDevelopmentDependencyPath -RelativePath $_.RelativePath) -and $_.RelativePath -like '*.cmd' })) {
        $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
        if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw "CMD is not ASCII: $($item.RelativePath)" }
        if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "CMD has UTF-8 BOM: $($item.RelativePath)" }
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($text -match '(?i)\bchcp\b') { throw "CMD must not change code page: $($item.RelativePath)" }
        if ($text -match '(?i)-ExecutionPolicy\s+Bypass') { throw "CMD must not bypass PowerShell execution policy: $($item.RelativePath)" }
        if ($text -match '(?i)(?:^|\s)-EncodedCommand(?:\s|$)') { throw "CMD must not use encoded PowerShell commands: $($item.RelativePath)" }
        if ($text -match '\r(?!\n)' -or $text -match '(?<!\r)\n') { throw "CMD must use exact CRLF: $($item.RelativePath)" }
        if (-not $text.EndsWith("`r`n") -or $text.Substring(0, $text.Length - 2).EndsWith("`r`n")) { throw "CMD must have exactly one final newline: $($item.RelativePath)" }
        if ([regex]::IsMatch($text, '(?m)[ \t]+(?=\r?$)')) { throw "CMD has trailing whitespace: $($item.RelativePath)" }
    }
    foreach ($item in @(Get-RepositoryFiles | Where-Object { -not (Test-CddsiDevelopmentDependencyPath -RelativePath $_.RelativePath) -and $_.RelativePath -match '\.(ps1|psd1)$' })) {
        $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
        if ($bytes.Count -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { throw "PowerShell file must be UTF-8 BOM for Windows PowerShell 5.1: $($item.RelativePath)" }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Count - 3)
        if ($text -match '\r(?!\n)' -or $text -match '(?<!\r)\n') { throw "PowerShell file must use exact CRLF: $($item.RelativePath)" }
        if (-not $text.EndsWith("`r`n") -or $text.Substring(0, $text.Length - 2).EndsWith("`r`n")) { throw "PowerShell file must have exactly one final newline: $($item.RelativePath)" }
        if ([regex]::IsMatch($text, '(?m)[ \t]+(?=\r?$)')) { throw "PowerShell file has trailing whitespace: $($item.RelativePath)" }
    }
    $binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.msix', '.exe', '.dll', '.pdb', '.pdf')
    foreach ($item in @(Get-RepositoryFiles | Where-Object { -not (Test-CddsiDevelopmentDependencyPath -RelativePath $_.RelativePath) -and $_.RelativePath -notmatch '\.(ps1|psd1|cmd)$' -and $binaryExtensions -notcontains $_.File.Extension.ToLowerInvariant() })) {
        $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
        if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "Non-PowerShell text must not have UTF-8 BOM: $($item.RelativePath)" }
        $text = Read-CddsiStrictUtf8Text -Path $item.File.FullName -DisplayPath $item.RelativePath
        if ($text.Contains("`r")) { throw "Text file must use LF: $($item.RelativePath)" }
        if (-not $text.EndsWith("`n") -or $text.Substring(0, $text.Length - 1).EndsWith("`n")) { throw "Text file must have exactly one final newline: $($item.RelativePath)" }
        if ([regex]::IsMatch($text, '(?m)[ \t]+$')) { throw "Text file has trailing whitespace: $($item.RelativePath)" }
    }
}

Invoke-CheckStep -Name 'Public function contracts and side-effect-free module load' -Action {
    $bootstrap = Join-Path $script:Root 'lib\bootstrap.ps1'
    . $bootstrap
    Import-CddsiLibraries
    $publicContract = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Root 'config\public-functions.psd1')
    $executionBoundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Root 'config\execution-boundaries.psd1')
    if ($publicContract.SchemaVersion -ne 2) { throw 'Unsupported public function contract schema.' }
    $requiredFunctions = @($publicContract.Files.GetEnumerator() | ForEach-Object { @($_.Value) })
    $defaultBootstrapContractFiles = @('lib/bootstrap.ps1') + @($executionBoundary.Rules.DefaultBootstrapLibraryFiles)
    $bootstrapRequiredFunctions = @(
        $publicContract.Files.GetEnumerator() |
            Where-Object { $defaultBootstrapContractFiles -ccontains [string]$_.Key } |
            ForEach-Object { @($_.Value) }
    )
    $contractFunctions = @($publicContract.ParameterContracts.Keys)
    $contractFunctionDiff = @(Compare-Object -ReferenceObject @($requiredFunctions | Sort-Object) -DifferenceObject @($contractFunctions | Sort-Object))
    if ($contractFunctionDiff.Count -gt 0) { throw 'Public function and parameter contract inventories differ.' }
    foreach ($name in $bootstrapRequiredFunctions) {
        if ($null -eq (Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue)) { throw "Missing public function: $name" }
    }
    $functionAstByName = @{}
    foreach ($entry in $publicContract.Files.GetEnumerator()) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $entry.Key), [ref]$tokens, [ref]$errors)
        $functionNodes = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        foreach ($functionNode in $functionNodes) {
            $functionAstByName[$functionNode.Name] = $functionNode
        }
        $actualFunctions = @($functionNodes | ForEach-Object Name | Sort-Object)
        $functionDiff = @(Compare-Object -ReferenceObject @($entry.Value | Sort-Object) -DifferenceObject $actualFunctions)
        if ($functionDiff.Count -gt 0) { throw "Public function file contract drift: $($entry.Key)" }
    }
    foreach ($entry in $publicContract.ParameterContracts.GetEnumerator()) {
        $contractNames = @($entry.Value.Keys | Sort-Object)
        if (($contractNames -join ',') -cne 'Kind,Mandatory,Mode') { throw "$($entry.Key) parameter contract schema drift." }
        if (@('Pure', 'ContextBound') -notcontains [string]$entry.Value.Kind) { throw "$($entry.Key) has an invalid function kind." }
        if ($entry.Value.Mode -isnot [bool]) { throw "$($entry.Key) Mode contract must be boolean." }
        if ($entry.Value.Mandatory -isnot [System.Collections.IEnumerable] -or $entry.Value.Mandatory -is [string]) { throw "$($entry.Key) Mandatory contract must be an array." }
        if (-not $functionAstByName.ContainsKey([string]$entry.Key)) { throw "$($entry.Key) function AST is missing." }
        $functionAst = $functionAstByName[[string]$entry.Key]
        $parameters = @($functionAst.Body.ParamBlock.Parameters)
        $actualMandatory = @($parameters | Where-Object {
            $parameter = $_
            @($parameter.Attributes | Where-Object { $_.TypeName.FullName -ceq 'Parameter' } | ForEach-Object {
                @($_.NamedArguments | Where-Object {
                    $_.ArgumentName -ieq 'Mandatory' -and
                        ($null -eq $_.Argument -or $_.Argument.Extent.Text -ieq '$true')
                })
            }).Count -gt 0
        } | ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object)
        if (($actualMandatory -join "`n") -cne (@($entry.Value.Mandatory | Sort-Object) -join "`n")) {
            throw "$($entry.Key) mandatory parameter contract drift."
        }
        if ($entry.Value.Kind -ceq 'ContextBound' -and @($entry.Value.Mandatory) -notcontains 'Context') {
            throw "$($entry.Key) context-bound contract must require Context."
        }
        $contextParameter = @($parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'Context' })
        if ($entry.Value.Kind -ceq 'ContextBound') {
            if ($contextParameter.Count -ne 1) { throw "$($entry.Key) context-bound contract must expose Context." }
            $contextAliases = @($contextParameter[0].Attributes | Where-Object { $_.TypeName.FullName -ceq 'Alias' } | ForEach-Object { $_.PositionalArguments[0].Value })
            if ($contextAliases.Count -ne 1 -or $contextAliases[0] -cne 'ExecutionContext') {
                throw "$($entry.Key).Context must expose the exact ExecutionContext alias."
            }
        }
        if ($entry.Value.Kind -ceq 'Pure' -and $contextParameter.Count -gt 0) {
            throw "$($entry.Key) pure contract must not expose Context."
        }
        $modeParameter = @($parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq 'Mode' })
        if ([bool]$entry.Value.Mode -ne ($modeParameter.Count -eq 1)) { throw "$($entry.Key) Mode presence contract drift." }
        if ($entry.Value.Mode) {
            $validateSet = @($modeParameter[0].Attributes | Where-Object { $_.TypeName.FullName -ceq 'ValidateSet' } | ForEach-Object {
                $_.PositionalArguments | ForEach-Object { $_.Extent.Text.Trim("'`"") }
            })
            if ((@($validateSet | Sort-Object) -join ',') -ne 'DryRun,Live,TestSafe') { throw "$($entry.Key).Mode ValidateSet drift." }
            if ($null -eq $modeParameter[0].DefaultValue -or $modeParameter[0].DefaultValue.Extent.Text.Trim("'`"") -cne 'TestSafe') { throw "$($entry.Key).Mode must default to TestSafe." }
        }
    }

}

Invoke-CheckStep -Name 'Scaffold modules contain no real system-operation commands' -Action {
    $scaffoldFiles = @(
        'lib/desktop-env-check.ps1', 'lib/desktop-msix.ps1', 'lib/git-for-windows.ps1',
        'lib/cowork-readiness.ps1', 'lib/deepseek-api.ps1', 'lib/desktop-config.ps1',
        'lib/desktop-lifecycle.ps1', 'lib/desktop-acceptance.ps1', 'scripts/elevated-install.ps1'
    )
    $forbiddenCommands = @(
        'Invoke-WebRequest', 'Invoke-RestMethod', 'Add-AppxPackage', 'Remove-AppxPackage',
        'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature', 'Restart-Computer',
        'Start-Process', 'Stop-Process', 'Register-ScheduledTask', 'Unregister-ScheduledTask',
        'Set-ItemProperty', 'Set-Content', 'Add-Content', 'Out-File', 'Copy-Item', 'Move-Item', 'Remove-Item',
        'Start-BitsTransfer', 'bitsadmin', 'bitsadmin.exe', 'Invoke-Expression', 'iex', 'iwr', 'irm', 'saps', 'New-Object', 'curl', 'curl.exe',
        'wget', 'winget', 'winget.exe', 'dism', 'dism.exe', 'msiexec', 'msiexec.exe', 'wusa', 'wusa.exe',
        'schtasks', 'schtasks.exe', 'shutdown', 'shutdown.exe', 'taskkill', 'taskkill.exe',
        'cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe', 'reg', 'reg.exe',
        'rundll32', 'rundll32.exe', 'sc.exe', 'net.exe', 'Start-Service', 'Stop-Service', 'Set-Service'
    )
    $forbiddenTypes = @('System.Diagnostics.Process', 'System.Net.WebClient', 'System.Net.WebRequest', 'System.Net.Http.HttpClient', 'Microsoft.Win32.Registry', 'System.IO.File', 'System.IO.Directory')
    foreach ($relative in $scaffoldFiles) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $hits = @($commands | Where-Object { $forbiddenCommands -contains $_ } | Sort-Object -Unique)
        if ($hits.Count -gt 0) { throw "$relative contains forbidden scaffold commands: $($hits -join ', ')" }
        $dynamicInvocations = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and [string]::IsNullOrWhiteSpace($node.GetCommandName()) }, $true))
        if ($dynamicInvocations.Count -gt 0) { throw "$relative contains a dynamic command invocation." }
        $typeHits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName } | Where-Object { $forbiddenTypes -contains $_ } | Sort-Object -Unique)
        if ($typeHits.Count -gt 0) { throw "$relative contains forbidden scaffold .NET types: $($typeHits -join ', ')" }
    }
}

Invoke-CheckStep -Name 'Repository API Key leak scan' -Action {
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($item in @(Get-RepositoryFiles | Where-Object { -not (Test-CddsiDevelopmentDependencyPath -RelativePath $_.RelativePath) })) {
        foreach ($finding in @(Find-CddsiWorkerFileSecretFindings -Path $item.File.FullName -RelativePath $item.RelativePath)) { $findings.Add($finding) }
    }
    $script:SecretFindingCount = $findings.Count
    if ($findings.Count -gt 0) {
        $safeDetails = @($findings | ForEach-Object { '{0}:{1}:{2}' -f $_.Source, $_.ByteOffset, $_.Type }) -join ', '
        throw "Potential secrets found: $safeDetails"
    }
}

if (-not $SkipPester) {
    Invoke-CheckStep -Name 'Pester Unit and Contract suites' -Action {
        $pesterManifest = Test-CddsiDevDependencyLock
        Remove-Module Pester -Force -ErrorAction SilentlyContinue
        Import-Module $pesterManifest -Force -ErrorAction Stop
        $result = Invoke-Pester -Path (Join-Path $script:Root 'tests') -Output Detailed -PassThru
        $script:PesterResult = $result
        if ([string]$result.Result -ne 'Passed' -or $result.FailedCount -gt 0 -or $result.SkippedCount -gt 0 -or $result.NotRunCount -gt 0 -or $result.InconclusiveCount -gt 0) {
            $failedDetails = @(
                $result.Tests |
                    Where-Object { [string]$_.Result -ceq 'Failed' } |
                    ForEach-Object {
                        $message = ''
                        if ($null -ne $_.ErrorRecord) { $message = [string]$_.ErrorRecord.Exception.Message }
                        if ($message.Length -gt 300) { $message = $message.Substring(0, 300) }
                        '{0} [{1}:{2}] {3}' -f $_.ExpandedName, $_.ScriptBlock.File, $_.ScriptBlock.StartPosition.StartLine, $message
                    }
            )
            throw ("Pester result is not clean: Result={0}, Failed={1}, Skipped={2}, NotRun={3}, Inconclusive={4}. FailedTests={5}" -f $result.Result, $result.FailedCount, $result.SkippedCount, $result.NotRunCount, $result.InconclusiveCount, ($failedDetails -join ' | '))
        }
    }
}

Invoke-CheckStep -Name 'Checks did not create repository artifacts' -Action {
    $finalInventory = @((Get-RepositoryFiles).RelativePath)
    $diff = @(Compare-Object -ReferenceObject $initialInventory -DifferenceObject $finalInventory)
    if ($diff.Count -gt 0) { throw "Repository inventory changed during checks: $($diff.InputObject -join ', ')" }
    $finalContentManifest = @(Get-RepositoryContentManifest)
    $script:FinalRepositoryManifestSha256 = Get-CddsiWorkerSequenceSha256 -Values $finalContentManifest
    $script:RepositoryContentChanged = $initialContentManifestSha256 -cne $script:FinalRepositoryManifestSha256
    if ($script:RepositoryContentChanged) { throw 'Repository file content changed during checks.' }
}

if ($script:Failures.Count -gt 0) {
    Write-Host "`nQuality checks failed:" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    throw "$($script:Failures.Count) quality check(s) failed."
}

if ($SkipPester) { throw 'Worker isolation evidence requires the pinned Pester suites.' }

# Pester executes test files in transient scopes. Reload only the two pure P1
# libraries required for the post-test synthetic measurement into the worker
# script scope so evidence generation cannot depend on leaked test functions.
. (Join-Path $script:Root 'lib\execution-context.ps1')
. (Join-Path $script:Root 'lib\fake-providers.ps1')

$suiteResults = @(Get-CddsiRequiredIsolationSuiteResults)
$syntheticMeasurements = Measure-CddsiWorkerSyntheticIsolationScenarios
$requiredSuiteFailureCount = @($suiteResults | Where-Object { [string]$_.Result -cne 'Passed' }).Count
$measurements = [pscustomobject][ordered]@{
    AstSyntaxErrorCount      = $script:AstSyntaxErrorCount
    LiveAdapterFileCount     = $script:LiveAdapterFileCount
    SecretFindingCount       = $script:SecretFindingCount
    RepositoryContentChanged = $script:RepositoryContentChanged
    LiveProviderLoaded       = $syntheticMeasurements.LiveProviderLoaded
    AccessLedger             = $syntheticMeasurements.AccessLedger
    MutationSpyCounts        = $syntheticMeasurements.MutationSpyCounts
    Pester                   = [pscustomobject][ordered]@{
        Result            = $script:PesterResult.Result
        PassedCount       = $script:PesterResult.PassedCount
        FailedCount       = $script:PesterResult.FailedCount
        SkippedCount      = $script:PesterResult.SkippedCount
        NotRunCount       = $script:PesterResult.NotRunCount
        InconclusiveCount = $script:PesterResult.InconclusiveCount
    }
    RequiredSuiteResults      = @($suiteResults)
    RequiredSuiteFailureCount = $requiredSuiteFailureCount
}
$provenance = [pscustomobject][ordered]@{
    MeasurementRuleVersion          = $script:CddsiWorkerMeasurementRuleVersion
    RepositoryInventorySha256       = $repositoryInventorySha256
    InitialRepositoryManifestSha256 = $initialContentManifestSha256
    FinalRepositoryManifestSha256   = $script:FinalRepositoryManifestSha256
    ExecutionBoundaryManifestSha256 = $script:ExecutionBoundaryManifestSha256
    DependencyManifestSha256        = $script:DependencyManifestSha256
    RequiredSuiteSummarySha256      = Get-CddsiWorkerRequiredSuiteSummarySha256 -SuiteResults $suiteResults
    PesterTreeSha256                = $script:PesterTreeSha256
    EngineGrantSha256               = $engineGrantSha256Actual
}
$workerEvidence = New-CddsiWorkerIsolationEvidenceV2 `
    -RunId $RunId `
    -Engine $EngineId `
    -SandboxBindingSha256 $script:SandboxBindingSha256 `
    -Measurements $measurements `
    -Provenance $provenance `
    -ExpectedEngineGrantSha256 $EngineGrantSha256
$workerEvidencePath = Write-CddsiWorkerIsolationEvidence -Evidence $workerEvidence
Write-Host ("[PASS] Worker isolation evidence - {0}" -f (Split-Path -Leaf $workerEvidencePath)) -ForegroundColor Green

Write-Host "`nAll quality checks passed." -ForegroundColor Green
