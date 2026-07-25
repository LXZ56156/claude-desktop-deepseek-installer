[CmdletBinding()]
param(
    [string]$PowerShell7Executable,
    [string]$PowerShell7Sha256,
    [string]$WindowsPowerShellExecutable,
    [string]$WindowsPowerShellSha256,
    [string]$GitExecutable,
    [string]$GitSha256,

    [ValidateRange(30, 3600)]
    [int]$ProcessTimeoutSeconds = 900,

    [switch]$PassThru,
    [switch]$ImportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$historicalEntryPowerShell7Executable = $PowerShell7Executable
$historicalEntryPowerShell7Sha256 = $PowerShell7Sha256
$historicalEntryWindowsPowerShellExecutable = $WindowsPowerShellExecutable
$historicalEntryWindowsPowerShellSha256 = $WindowsPowerShellSha256
$historicalEntryGitExecutable = $GitExecutable
$historicalEntryGitSha256 = $GitSha256
$historicalEntryProcessTimeoutSeconds = $ProcessTimeoutSeconds
$historicalEntryPassThru = $PassThru.IsPresent
$historicalEntryImportOnly = $ImportOnly.IsPresent

$script:CddsiHistoricalRepositoryRoot = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot)
).TrimEnd('\')
$script:CddsiHistoricalPolicyPath = Join-Path $PSScriptRoot 'quality-set-policy.ps1'
$script:CddsiHistoricalGateCommonPath = Join-Path $PSScriptRoot 'release-gate-common.ps1'
$script:CddsiHistoricalHostHarnessPath = Join-Path $PSScriptRoot 'invoke-host-sandbox.ps1'
$script:CddsiHistoricalClassificationPath = Join-Path `
    $script:CddsiHistoricalRepositoryRoot `
    'config\product-release-gate.psd1'

foreach ($requiredScript in @(
        $script:CddsiHistoricalPolicyPath
        $script:CddsiHistoricalGateCommonPath
        $script:CddsiHistoricalHostHarnessPath
    )) {
    if (-not (Test-Path -LiteralPath $requiredScript -PathType Leaf)) {
        throw 'A required historical-diagnostic harness component is unavailable.'
    }
}

. $script:CddsiHistoricalPolicyPath
. $script:CddsiHistoricalGateCommonPath

function Assert-CddsiHistoricalToolGrantInput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$ExecutablePath,

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Sha256,

        [Parameter(Mandatory = $true)]
        [ValidateSet('PowerShell7', 'WindowsPowerShell', 'Git')]
        [string]$ToolId
    )

    if (
        [string]::IsNullOrWhiteSpace($ExecutablePath) -or
        -not [System.IO.Path]::IsPathRooted($ExecutablePath)
    ) {
        throw "$ToolId requires an absolute executable grant."
    }
    if ($Sha256 -cnotmatch '^[a-fA-F0-9]{64}$') {
        throw "$ToolId requires an exact SHA-256 grant."
    }
}

function Assert-CddsiHistoricalProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QualitySetPolicy,

        [Parameter(Mandatory = $true)]
        [string]$EnforcementPhase
    )

    Assert-CddsiGateExactPropertySet -Value $QualitySetPolicy -Expected @(
        'AssertionFailureDisposition',
        'CanonicalSha256',
        'ClassificationManifestSha256',
        'ContractVersion',
        'DependencyManifestSha256',
        'FileCount',
        'LedgerEntryCount',
        'PesterFileCount',
        'ProcessCount',
        'QualitySet',
        'QualityShards',
        'SchemaVersion',
        'SelectedFilePaths',
        'SelectedFilePathsSha256',
        'SelectedPesterPaths',
        'SelectedPesterPathsSha256',
        'SelectedShardPolicySha256',
        'ShardCount',
        'WorkerCount'
    ) -Label 'Historical diagnostic quality-set policy'

    if (
        -not (Test-CddsiGateInteger -Value $QualitySetPolicy.SchemaVersion) -or
        [long]$QualitySetPolicy.SchemaVersion -ne 1 -or
        [string]$QualitySetPolicy.ContractVersion -cne 'D-026' -or
        [string]$QualitySetPolicy.QualitySet -cne 'HistoricalDiagnostic' -or
        [string]$QualitySetPolicy.AssertionFailureDisposition -cne
        'ReportOnlyAfterCompleteTestFailure'
    ) {
        throw 'Historical diagnostic policy identity is invalid.'
    }

    foreach ($hashName in @(
            'CanonicalSha256'
            'ClassificationManifestSha256'
            'DependencyManifestSha256'
            'SelectedFilePathsSha256'
            'SelectedPesterPathsSha256'
            'SelectedShardPolicySha256'
        )) {
        if ([string]$QualitySetPolicy.$hashName -cnotmatch '^[a-f0-9]{64}$') {
            throw "Historical diagnostic policy hash is invalid: $hashName."
        }
    }

    foreach ($binding in @(
            @{ Name = 'FileCount'; Value = 13L }
            @{ Name = 'PesterFileCount'; Value = 13L }
            @{ Name = 'ShardCount'; Value = 9L }
            @{ Name = 'WorkerCount'; Value = 20L }
            @{ Name = 'ProcessCount'; Value = 23L }
            @{ Name = 'LedgerEntryCount'; Value = 52L }
        )) {
        if (
            -not (Test-CddsiGateInteger -Value $QualitySetPolicy.($binding.Name)) -or
            [long]$QualitySetPolicy.($binding.Name) -ne [long]$binding.Value
        ) {
            throw "Historical diagnostic topology drift: $($binding.Name)."
        }
    }

    if (
        @($QualitySetPolicy.SelectedFilePaths).Count -ne 13 -or
        @($QualitySetPolicy.SelectedPesterPaths).Count -ne 13 -or
        @($QualitySetPolicy.QualityShards).Count -ne 9
    ) {
        throw 'Historical diagnostic selected-set topology is incomplete.'
    }

    if ($EnforcementPhase -cne 'NamedProductReleaseGate') {
        throw 'Historical diagnostic classification enforcement phase is invalid.'
    }
}

function Assert-CddsiHistoricalValidationSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ValidationSummary
    )

    Assert-CddsiGateExactPropertySet -Value $ValidationSummary -Expected @(
        'DiagnosticResult',
        'FailedTestCount',
        'RequiredSuiteFailureCount',
        'WorkerSummaries'
    ) -Label 'Historical diagnostic validation summary'
    if ([string]$ValidationSummary.DiagnosticResult -notin @('PASSED', 'FAILED_TESTS')) {
        throw 'Historical diagnostic result is invalid.'
    }
    foreach ($countName in @('FailedTestCount', 'RequiredSuiteFailureCount')) {
        if (
            -not (Test-CddsiGateInteger -Value $ValidationSummary.$countName) -or
            [long]$ValidationSummary.$countName -lt 0
        ) {
            throw "Historical diagnostic failure count is invalid: $countName."
        }
    }

    $workers = @($ValidationSummary.WorkerSummaries)
    if ($workers.Count -ne 2) {
        throw 'Historical diagnostic engine-summary count drift.'
    }
    for ($workerIndex = 0; $workerIndex -lt $workers.Count; $workerIndex++) {
        $worker = $workers[$workerIndex]
        Assert-CddsiGateExactPropertySet -Value $worker -Expected @(
            'FailedCount',
            'PassedCount',
            'RequiredSuiteFailureCount',
            'Result',
            'TotalCount'
        ) -Label 'Historical diagnostic engine summary'
        if ([string]$worker.Result -notin @('Passed', 'Failed')) {
            throw 'Historical diagnostic engine result is invalid.'
        }
        foreach ($countName in @(
                'FailedCount'
                'PassedCount'
                'RequiredSuiteFailureCount'
                'TotalCount'
            )) {
            if (
                -not (Test-CddsiGateInteger -Value $worker.$countName) -or
                [long]$worker.$countName -lt 0
            ) {
                throw "Historical diagnostic engine count is invalid: $countName."
            }
        }
        if (
            ([string]$worker.Result -ceq 'Passed' -and [long]$worker.FailedCount -ne 0) -or
            ([string]$worker.Result -ceq 'Failed' -and [long]$worker.FailedCount -le 0) -or
            [long]$worker.TotalCount -ne
            ([long]$worker.PassedCount + [long]$worker.FailedCount)
        ) {
            throw 'Historical diagnostic engine result/count binding drift.'
        }
    }

    $computedFailedTestCount = [long](
        ($workers | ForEach-Object { [long]$_.FailedCount } | Measure-Object -Sum).Sum
    )
    $computedRequiredSuiteFailureCount = [long](
        ($workers | ForEach-Object {
                [long]$_.RequiredSuiteFailureCount
            } | Measure-Object -Sum).Sum
    )
    $expectedResult = if (
        ($computedFailedTestCount + $computedRequiredSuiteFailureCount) -gt 0
    ) {
        'FAILED_TESTS'
    }
    else {
        'PASSED'
    }
    if (
        [long]$ValidationSummary.FailedTestCount -ne $computedFailedTestCount -or
        [long]$ValidationSummary.RequiredSuiteFailureCount -ne
        $computedRequiredSuiteFailureCount -or
        [string]$ValidationSummary.DiagnosticResult -cne $expectedResult
    ) {
        throw 'Historical diagnostic aggregate failure binding drift.'
    }
}

function Assert-CddsiHistoricalSafeObject {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value,

        [Parameter(Mandatory = $true)]
        [string[]]$ForbiddenAbsolutePaths
    )

    $pending = New-Object System.Collections.Stack
    $pending.Push($Value)
    while ($pending.Count -gt 0) {
        $current = $pending.Pop()
        if ($null -eq $current) {
            continue
        }
        if ($current -is [string]) {
            $text = [string]$current
            if (
                [System.IO.Path]::IsPathRooted($text) -or
                $text -match '(?i)(?:sk-[a-z0-9_-]{16,}|authorization\s*[:=]|bearer\s+[a-z0-9._~+/=-]{8,})'
            ) {
                throw 'Historical diagnostic evidence contains unsafe disclosure.'
            }
            foreach ($forbiddenPath in $ForbiddenAbsolutePaths) {
                if (
                    -not [string]::IsNullOrWhiteSpace($forbiddenPath) -and
                    $text.IndexOf($forbiddenPath, [StringComparison]::OrdinalIgnoreCase) -ge 0
                ) {
                    throw 'Historical diagnostic evidence contains unsafe disclosure.'
                }
            }
            continue
        }
        if (
            $current -is [bool] -or
            $current -is [byte] -or
            $current -is [sbyte] -or
            $current -is [int16] -or
            $current -is [uint16] -or
            $current -is [int32] -or
            $current -is [uint32] -or
            $current -is [int64] -or
            $current -is [uint64] -or
            $current -is [single] -or
            $current -is [double] -or
            $current -is [decimal] -or
            $current -is [guid] -or
            $current -is [datetime]
        ) {
            continue
        }
        if ($current -is [System.Collections.IDictionary]) {
            foreach ($key in @($current.Keys)) {
                $pending.Push($current[$key])
            }
            continue
        }
        if ($current -is [System.Collections.IEnumerable]) {
            foreach ($item in @($current)) {
                $pending.Push($item)
            }
            continue
        }
        foreach ($property in @($current.PSObject.Properties)) {
            if ($property.IsGettable) {
                $pending.Push($property.Value)
            }
        }
    }
}

function New-CddsiHistoricalDiagnosticEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $QualitySetPolicy,

        [Parameter(Mandatory = $true)]
        [string]$EnforcementPhase,

        [Parameter(Mandatory = $true)]
        $ValidationSummary,

        [Parameter(Mandatory = $true)]
        $CoreQualityEvidence,

        [Parameter(Mandatory = $true)]
        [string[]]$ForbiddenAbsolutePaths
    )

    Assert-CddsiHistoricalProfile `
        -QualitySetPolicy $QualitySetPolicy `
        -EnforcementPhase $EnforcementPhase
    Assert-CddsiHistoricalValidationSummary -ValidationSummary $ValidationSummary
    Assert-CddsiHistoricalSafeObject `
        -Value $CoreQualityEvidence `
        -ForbiddenAbsolutePaths $ForbiddenAbsolutePaths

    $coreQualityEvidenceSha256 = Get-CddsiGateCanonicalObjectSha256 `
        -Value $CoreQualityEvidence
    $binding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiHistoricalDiagnosticEvidence'
        ContractVersion = 'D-026'
        Status = 'COMPLETED'
        DiagnosticResult = [string]$ValidationSummary.DiagnosticResult
        ReleaseBlocking = $false
        QualitySet = 'HistoricalDiagnostic'
        EnforcementPhase = $EnforcementPhase
        AssertionFailureDisposition = 'ReportOnlyAfterCompleteTestFailure'
        FailedTestCount = [long]$ValidationSummary.FailedTestCount
        RequiredSuiteFailureCount = [long]$ValidationSummary.RequiredSuiteFailureCount
        ClassificationManifestSha256 =
            [string]$QualitySetPolicy.ClassificationManifestSha256
        DependencyManifestSha256 = [string]$QualitySetPolicy.DependencyManifestSha256
        QualitySetPolicySha256 = [string]$QualitySetPolicy.CanonicalSha256
        ExpectedFileCount = 13
        ExpectedPesterFileCount = 13
        ExpectedShardCount = 9
        ExpectedWorkerCount = 20
        ExpectedProcessCount = 23
        ExpectedLedgerEntryCount = 52
        CoreQualityEvidenceSha256 = $coreQualityEvidenceSha256
    }
    $bindingSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $binding

    $evidence = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiHistoricalDiagnosticEvidence'
        ContractVersion = 'D-026'
        Status = 'COMPLETED'
        DiagnosticResult = [string]$ValidationSummary.DiagnosticResult
        ReleaseBlocking = $false
        QualitySet = 'HistoricalDiagnostic'
        EnforcementPhase = $EnforcementPhase
        AssertionFailureDisposition = 'ReportOnlyAfterCompleteTestFailure'
        FailedTestCount = [long]$ValidationSummary.FailedTestCount
        RequiredSuiteFailureCount = [long]$ValidationSummary.RequiredSuiteFailureCount
        ClassificationManifestSha256 =
            [string]$QualitySetPolicy.ClassificationManifestSha256
        DependencyManifestSha256 = [string]$QualitySetPolicy.DependencyManifestSha256
        QualitySetPolicySha256 = [string]$QualitySetPolicy.CanonicalSha256
        ExpectedFileCount = 13
        ExpectedPesterFileCount = 13
        ExpectedShardCount = 9
        ExpectedWorkerCount = 20
        ExpectedProcessCount = 23
        ExpectedLedgerEntryCount = 52
        CoreQualityEvidenceSha256 = $coreQualityEvidenceSha256
        CoreQualityEvidence = $CoreQualityEvidence
        BindingSha256 = $bindingSha256
    }

    Assert-CddsiGateExactPropertySet -Value $evidence -Expected @(
        'AssertionFailureDisposition',
        'BindingSha256',
        'ClassificationManifestSha256',
        'ContractVersion',
        'CoreQualityEvidence',
        'CoreQualityEvidenceSha256',
        'DependencyManifestSha256',
        'DiagnosticResult',
        'EnforcementPhase',
        'EvidenceType',
        'ExpectedFileCount',
        'ExpectedLedgerEntryCount',
        'ExpectedPesterFileCount',
        'ExpectedProcessCount',
        'ExpectedShardCount',
        'ExpectedWorkerCount',
        'FailedTestCount',
        'QualitySet',
        'QualitySetPolicySha256',
        'ReleaseBlocking',
        'RequiredSuiteFailureCount',
        'SchemaVersion',
        'Status'
    ) -Label 'Historical diagnostic evidence'
    if (
        [string]$evidence.CoreQualityEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$evidence.BindingSha256 -cnotmatch '^[a-f0-9]{64}$'
    ) {
        throw 'Historical diagnostic evidence binding is invalid.'
    }
    Assert-CddsiHistoricalSafeObject `
        -Value $evidence `
        -ForbiddenAbsolutePaths $ForbiddenAbsolutePaths
    return $evidence
}

function Invoke-CddsiHistoricalDiagnostics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$PowerShell7Executable,

        [Parameter(Mandatory = $true)]
        [string]$PowerShell7Sha256,

        [Parameter(Mandatory = $true)]
        [string]$WindowsPowerShellExecutable,

        [Parameter(Mandatory = $true)]
        [string]$WindowsPowerShellSha256,

        [Parameter(Mandatory = $true)]
        [string]$GitExecutable,

        [Parameter(Mandatory = $true)]
        [string]$GitSha256,

        [Parameter(Mandatory = $true)]
        [ValidateRange(30, 3600)]
        [int]$ProcessTimeoutSeconds
    )

    Assert-CddsiHistoricalToolGrantInput `
        -ExecutablePath $PowerShell7Executable `
        -Sha256 $PowerShell7Sha256 `
        -ToolId PowerShell7
    Assert-CddsiHistoricalToolGrantInput `
        -ExecutablePath $WindowsPowerShellExecutable `
        -Sha256 $WindowsPowerShellSha256 `
        -ToolId WindowsPowerShell
    Assert-CddsiHistoricalToolGrantInput `
        -ExecutablePath $GitExecutable `
        -Sha256 $GitSha256 `
        -ToolId Git

    if (-not (Test-Path -LiteralPath $script:CddsiHistoricalClassificationPath -PathType Leaf)) {
        throw 'The historical-diagnostic classification manifest is unavailable.'
    }
    $classification = Import-PowerShellDataFile `
        -LiteralPath $script:CddsiHistoricalClassificationPath
    $enforcementPhase = [string]$classification.EnforcementPhase

    $qualitySetPolicy = Get-CddsiQualitySetPolicy `
        -RepositoryRoot $script:CddsiHistoricalRepositoryRoot `
        -QualitySet HistoricalDiagnostic
    Assert-CddsiHistoricalProfile `
        -QualitySetPolicy $qualitySetPolicy `
        -EnforcementPhase $enforcementPhase

    [object[]]$hostResults = @(
        & $script:CddsiHistoricalHostHarnessPath `
            -Scenario Quality `
            -QualitySet HistoricalDiagnostic `
            -RepositoryRoot $script:CddsiHistoricalRepositoryRoot `
            -PowerShell7Executable $PowerShell7Executable `
            -PowerShell7Sha256 $PowerShell7Sha256 `
            -WindowsPowerShellExecutable $WindowsPowerShellExecutable `
            -WindowsPowerShellSha256 $WindowsPowerShellSha256 `
            -GitExecutable $GitExecutable `
            -GitSha256 $GitSha256 `
            -ProcessTimeoutSeconds $ProcessTimeoutSeconds `
            -PassThru
    )
    if ($hostResults.Count -ne 1) {
        throw 'Historical diagnostic host evidence cardinality is invalid.'
    }
    $coreQualityEvidence = $hostResults[0]
    $validationSummary = Assert-CddsiGateQualityEvidence `
        -Evidence $coreQualityEvidence `
        -QualitySetPolicy $qualitySetPolicy `
        -RepositoryRoot $script:CddsiHistoricalRepositoryRoot
    Assert-CddsiHistoricalValidationSummary -ValidationSummary $validationSummary

    return New-CddsiHistoricalDiagnosticEvidence `
        -QualitySetPolicy $qualitySetPolicy `
        -EnforcementPhase $enforcementPhase `
        -ValidationSummary $validationSummary `
        -CoreQualityEvidence $coreQualityEvidence `
        -ForbiddenAbsolutePaths @(
            $script:CddsiHistoricalRepositoryRoot
            $PowerShell7Executable
            $WindowsPowerShellExecutable
            $GitExecutable
        )
}

if ($historicalEntryImportOnly) {
    return
}

$topLevelGrants = [ordered]@{
    PowerShell7Executable = $historicalEntryPowerShell7Executable
    PowerShell7Sha256 = $historicalEntryPowerShell7Sha256
    WindowsPowerShellExecutable = $historicalEntryWindowsPowerShellExecutable
    WindowsPowerShellSha256 = $historicalEntryWindowsPowerShellSha256
    GitExecutable = $historicalEntryGitExecutable
    GitSha256 = $historicalEntryGitSha256
}
foreach ($grantName in $topLevelGrants.Keys) {
    if ([string]::IsNullOrWhiteSpace([string]$topLevelGrants[$grantName])) {
        throw "Historical diagnostics require an explicit $grantName grant."
    }
}

$historicalEvidence = Invoke-CddsiHistoricalDiagnostics `
    -PowerShell7Executable $historicalEntryPowerShell7Executable `
    -PowerShell7Sha256 $historicalEntryPowerShell7Sha256 `
    -WindowsPowerShellExecutable $historicalEntryWindowsPowerShellExecutable `
    -WindowsPowerShellSha256 $historicalEntryWindowsPowerShellSha256 `
    -GitExecutable $historicalEntryGitExecutable `
    -GitSha256 $historicalEntryGitSha256 `
    -ProcessTimeoutSeconds $historicalEntryProcessTimeoutSeconds

if ($historicalEntryPassThru) {
    return $historicalEvidence
}
Write-Host (
    'Historical diagnostics completed with result {0}; release blocking remains false.' -f
    [string]$historicalEvidence.DiagnosticResult
)
