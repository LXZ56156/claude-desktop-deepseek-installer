[CmdletBinding()]
param(
    [string]$PowerShell7Executable,

    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$PowerShell7Sha256,

    [string]$WindowsPowerShellExecutable,

    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$WindowsPowerShellSha256,

    [string]$GitExecutable,

    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$GitSha256,

    [ValidateRange(30, 3600)]
    [int]$ProcessTimeoutSeconds = 900,

    [switch]$PassThru,
    [switch]$ImportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$namedGateEntryPowerShell7Executable = $PowerShell7Executable
$namedGateEntryPowerShell7Sha256 = $PowerShell7Sha256
$namedGateEntryWindowsPowerShellExecutable = $WindowsPowerShellExecutable
$namedGateEntryWindowsPowerShellSha256 = $WindowsPowerShellSha256
$namedGateEntryGitExecutable = $GitExecutable
$namedGateEntryGitSha256 = $GitSha256
$namedGateEntryProcessTimeoutSeconds = $ProcessTimeoutSeconds
$namedGateEntryPassThru = $PassThru.IsPresent
$namedGateEntryImportOnly = $ImportOnly.IsPresent
$script:CddsiNamedGateRepositoryRoot = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot)
).TrimEnd('\')
$script:CddsiProductGateScript = Join-Path $PSScriptRoot 'product-release-gate.ps1'
$script:CddsiHistoricalGateScript = Join-Path $PSScriptRoot 'historical-diagnostics.ps1'

. $script:CddsiProductGateScript -ImportOnly
. $script:CddsiHistoricalGateScript -ImportOnly

function Get-CddsiNamedGateSafeCode {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Value,

        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Z0-9_]+$')]
        [string]$Fallback
    )

    if (
        -not [string]::IsNullOrWhiteSpace($Value) -and
        $Value.Length -le 128 -and
        $Value -cmatch '^[A-Z0-9_]+$'
    ) {
        return $Value
    }
    return $Fallback
}

function New-CddsiNamedGateChildOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('ProductReleaseGate', 'HistoricalDiagnostics')]
        [string]$Gate,

        [Parameter(Mandatory = $true)]
        [bool]$Succeeded,

        [AllowNull()]
        [System.Exception]$Error
    )

    if ($Succeeded) {
        if ($null -ne $Error) {
            throw 'A successful named-gate child must not carry an exception.'
        }
        return [pscustomobject][ordered]@{
            Gate                      = $Gate
            Attempted                 = $true
            Status                    = 'PASSED'
            FailureCode               = 'NONE'
            FailureStage              = 'NONE'
            SafeFailureEvidenceStatus = 'NOT_APPLICABLE'
            SafeFailureEvidenceSha256 = ''
            SafeFailureEvidence       = $null
        }
    }
    if ($null -eq $Error) {
        throw 'A failed named-gate child must carry an exception.'
    }

    $fallbackCode = if ($Gate -ceq 'ProductReleaseGate') {
        'PRODUCT_RELEASE_GATE_FAILED'
    }
    else {
        'HISTORICAL_DIAGNOSTICS_FAILED'
    }
    $rawSafeEvidence = [string]$Error.Data['CddsiSafeFailureEvidenceJson']
    if ([string]::IsNullOrWhiteSpace($rawSafeEvidence)) {
        $rawSafeEvidence = [string]$Error.Data['CddsiFailureEvidenceJson']
    }

    $safeEvidence = $null
    $safeEvidenceStatus = 'UNAVAILABLE'
    if (-not [string]::IsNullOrWhiteSpace($rawSafeEvidence)) {
        $safeEvidence = ConvertFrom-CddsiProductGateSafeFailureEvidenceJson `
            -Json $rawSafeEvidence
        if ($null -eq $safeEvidence) {
            $safeEvidenceStatus = 'REJECTED_UNSAFE'
        }
        else {
            try {
                $null = Assert-CddsiQualityFailureProgress `
                    -Progress $safeEvidence.Progress
                $safeEvidenceStatus = 'BOUND'
            }
            catch {
                $safeEvidence = $null
                $safeEvidenceStatus = 'REJECTED_UNSAFE'
            }
        }
    }
    elseif (
        [string]$Error.Data['CddsiSafeFailureEvidenceStatus'] -ceq
            'REJECTED_UNSAFE'
    ) {
        $safeEvidenceStatus = 'REJECTED_UNSAFE'
    }

    $evidenceCode = if ($null -eq $safeEvidence) {
        ''
    }
    else {
        [string]$safeEvidence.PrimaryFailureCode
    }
    $failureCode = Get-CddsiNamedGateSafeCode `
        -Value ([string]$Error.Data['CddsiFailureCode']) `
        -Fallback (
            Get-CddsiNamedGateSafeCode `
                -Value $evidenceCode `
                -Fallback $fallbackCode
        )
    $failureStage = Get-CddsiNamedGateSafeCode `
        -Value ([string]$Error.Data['CddsiFailureStage']) `
        -Fallback 'EXECUTION'
    $safeEvidenceSha256 = if ($null -eq $safeEvidence) {
        ''
    }
    else {
        Get-CddsiGateCanonicalObjectSha256 -Value $safeEvidence
    }

    return [pscustomobject][ordered]@{
        Gate                      = $Gate
        Attempted                 = $true
        Status                    = 'FAILED_CLOSED'
        FailureCode               = $failureCode
        FailureStage              = $failureStage
        SafeFailureEvidenceStatus = $safeEvidenceStatus
        SafeFailureEvidenceSha256 = $safeEvidenceSha256
        SafeFailureEvidence       = $safeEvidence
    }
}

function Assert-CddsiNamedGateChildOutcome {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Outcome,

        [Parameter(Mandatory = $true)]
        [ValidateSet('ProductReleaseGate', 'HistoricalDiagnostics')]
        [string]$ExpectedGate
    )

    Assert-CddsiGateExactPropertySet -Value $Outcome -Expected @(
        'Attempted',
        'FailureCode',
        'FailureStage',
        'Gate',
        'SafeFailureEvidence',
        'SafeFailureEvidenceSha256',
        'SafeFailureEvidenceStatus',
        'Status'
    ) -Label "$ExpectedGate failure outcome"
    if (
        [string]$Outcome.Gate -cne $ExpectedGate -or
        $Outcome.Attempted -isnot [bool] -or
        -not [bool]$Outcome.Attempted -or
        [string]$Outcome.Status -notin @('PASSED', 'FAILED_CLOSED')
    ) {
        throw "$ExpectedGate failure outcome identity is invalid."
    }

    if ([string]$Outcome.Status -ceq 'PASSED') {
        if (
            [string]$Outcome.FailureCode -cne 'NONE' -or
            [string]$Outcome.FailureStage -cne 'NONE' -or
            [string]$Outcome.SafeFailureEvidenceStatus -cne 'NOT_APPLICABLE' -or
            -not [string]::IsNullOrEmpty(
                [string]$Outcome.SafeFailureEvidenceSha256
            ) -or
            $null -ne $Outcome.SafeFailureEvidence
        ) {
            throw "$ExpectedGate successful outcome carries failure data."
        }
        return $true
    }

    if (
        [string]$Outcome.FailureCode -notmatch '^[A-Z0-9_]{1,128}$' -or
        [string]$Outcome.FailureStage -notmatch '^[A-Z0-9_]{1,128}$' -or
        [string]$Outcome.SafeFailureEvidenceStatus -notin @(
            'BOUND',
            'REJECTED_UNSAFE',
            'UNAVAILABLE'
        )
    ) {
        throw "$ExpectedGate failed outcome metadata is invalid."
    }
    if ([string]$Outcome.SafeFailureEvidenceStatus -ceq 'BOUND') {
        if (
            $null -eq $Outcome.SafeFailureEvidence -or
            [string]$Outcome.SafeFailureEvidenceSha256 -cnotmatch
                '^[a-f0-9]{64}$'
        ) {
            throw "$ExpectedGate bound failure evidence is missing."
        }
        $validated = ConvertFrom-CddsiProductGateSafeFailureEvidenceJson `
            -Json (
                $Outcome.SafeFailureEvidence |
                    ConvertTo-Json -Depth 100 -Compress
            )
        if ($null -eq $validated) {
            throw "$ExpectedGate bound failure evidence is unsafe."
        }
        $null = Assert-CddsiQualityFailureProgress `
            -Progress $validated.Progress
        if (
            [string]$Outcome.SafeFailureEvidenceSha256 -cne
            (Get-CddsiGateCanonicalObjectSha256 -Value $validated)
        ) {
            throw "$ExpectedGate bound failure evidence hash drift."
        }
    }
    elseif (
        $null -ne $Outcome.SafeFailureEvidence -or
        -not [string]::IsNullOrEmpty(
            [string]$Outcome.SafeFailureEvidenceSha256
        )
    ) {
        throw "$ExpectedGate unbound failure outcome carries evidence."
    }
    return $true
}

function New-CddsiNamedGateFailureEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [bool]$ProductSucceeded,

        [AllowNull()]
        [System.Exception]$ProductError,

        [Parameter(Mandatory = $true)]
        [bool]$HistoricalSucceeded,

        [AllowNull()]
        [System.Exception]$HistoricalError,

        [Parameter(Mandatory = $true)]
        [ValidateSet(
            'CHILD_GATE_FAILURE',
            'NAMED_GATE_VALIDATION_FAILED'
        )]
        [string]$FailureCode
    )

    $productOutcome = New-CddsiNamedGateChildOutcome `
        -Gate ProductReleaseGate `
        -Succeeded $ProductSucceeded `
        -Error $ProductError
    $historicalOutcome = New-CddsiNamedGateChildOutcome `
        -Gate HistoricalDiagnostics `
        -Succeeded $HistoricalSucceeded `
        -Error $HistoricalError
    $childFailureCount = @(
        $productOutcome
        $historicalOutcome
    ).Where({ [string]$_.Status -ceq 'FAILED_CLOSED' }).Count
    if (
        $FailureCode -ceq 'CHILD_GATE_FAILURE' -and
        $childFailureCount -lt 1
    ) {
        throw 'Child-gate failure evidence requires a failed child.'
    }
    if (
        $FailureCode -ceq 'NAMED_GATE_VALIDATION_FAILED' -and
        $childFailureCount -ne 0
    ) {
        throw 'Named-gate validation failure requires successful children.'
    }

    $binding = [pscustomobject][ordered]@{
        SchemaVersion        = 1
        EvidenceType         = 'CddsiNamedReleaseGateFailureEvidence'
        ContractVersion      = 'D-026'
        Status               = 'FAILED_SAFE'
        FailureCode          = $FailureCode
        BothPathsAttempted   = $true
        ChildFailureCount    = $childFailureCount
        ProductPath          = $productOutcome
        HistoricalPath       = $historicalOutcome
        SafeFailureDisclosure = $true
    }
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion        = 1
        EvidenceType         = 'CddsiNamedReleaseGateFailureEvidence'
        ContractVersion      = 'D-026'
        Status               = 'FAILED_SAFE'
        FailureCode          = $FailureCode
        BothPathsAttempted   = $true
        ChildFailureCount    = $childFailureCount
        ProductPath          = $productOutcome
        HistoricalPath       = $historicalOutcome
        SafeFailureDisclosure = $true
        BindingSha256        = Get-CddsiGateCanonicalObjectSha256 `
            -Value $binding
    }
    $null = Assert-CddsiNamedGateFailureEvidence -Evidence $evidence
    return $evidence
}

function Assert-CddsiNamedGateFailureEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence
    )

    Assert-CddsiGateExactPropertySet -Value $Evidence -Expected @(
        'BindingSha256',
        'BothPathsAttempted',
        'ChildFailureCount',
        'ContractVersion',
        'EvidenceType',
        'FailureCode',
        'HistoricalPath',
        'ProductPath',
        'SafeFailureDisclosure',
        'SchemaVersion',
        'Status'
    ) -Label 'Named release-gate failure evidence'
    if (
        -not (Test-CddsiGateInteger -Value $Evidence.SchemaVersion) -or
        [long]$Evidence.SchemaVersion -ne 1 -or
        [string]$Evidence.EvidenceType -cne
            'CddsiNamedReleaseGateFailureEvidence' -or
        [string]$Evidence.ContractVersion -cne 'D-026' -or
        [string]$Evidence.Status -cne 'FAILED_SAFE' -or
        [string]$Evidence.FailureCode -notin @(
            'CHILD_GATE_FAILURE',
            'NAMED_GATE_VALIDATION_FAILED'
        ) -or
        $Evidence.BothPathsAttempted -isnot [bool] -or
        -not [bool]$Evidence.BothPathsAttempted -or
        $Evidence.SafeFailureDisclosure -isnot [bool] -or
        -not [bool]$Evidence.SafeFailureDisclosure -or
        -not (Test-CddsiGateInteger -Value $Evidence.ChildFailureCount)
    ) {
        throw 'Named release-gate failure evidence identity is invalid.'
    }
    $null = Assert-CddsiNamedGateChildOutcome `
        -Outcome $Evidence.ProductPath `
        -ExpectedGate ProductReleaseGate
    $null = Assert-CddsiNamedGateChildOutcome `
        -Outcome $Evidence.HistoricalPath `
        -ExpectedGate HistoricalDiagnostics
    $actualChildFailureCount = @(
        $Evidence.ProductPath
        $Evidence.HistoricalPath
    ).Where({ [string]$_.Status -ceq 'FAILED_CLOSED' }).Count
    if (
        [long]$Evidence.ChildFailureCount -ne $actualChildFailureCount -or
        (
            [string]$Evidence.FailureCode -ceq 'CHILD_GATE_FAILURE' -and
            $actualChildFailureCount -lt 1
        ) -or
        (
            [string]$Evidence.FailureCode -ceq
                'NAMED_GATE_VALIDATION_FAILED' -and
            $actualChildFailureCount -ne 0
        )
    ) {
        throw 'Named release-gate failure count binding drift.'
    }

    $binding = [pscustomobject][ordered]@{
        SchemaVersion        = 1
        EvidenceType         = 'CddsiNamedReleaseGateFailureEvidence'
        ContractVersion      = 'D-026'
        Status               = 'FAILED_SAFE'
        FailureCode          = [string]$Evidence.FailureCode
        BothPathsAttempted   = $true
        ChildFailureCount    = $actualChildFailureCount
        ProductPath          = $Evidence.ProductPath
        HistoricalPath       = $Evidence.HistoricalPath
        SafeFailureDisclosure = $true
    }
    if (
        [string]$Evidence.BindingSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.BindingSha256 -cne
        (Get-CddsiGateCanonicalObjectSha256 -Value $binding)
    ) {
        throw 'Named release-gate failure binding hash drift.'
    }
    return $true
}

function New-CddsiNamedGateFailureException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence
    )

    $null = Assert-CddsiNamedGateFailureEvidence -Evidence $Evidence
    $json = $Evidence | ConvertTo-Json -Depth 100 -Compress
    $exception = [InvalidOperationException]::new(
        'Named release-gate execution failed safely.'
    )
    $exception.Data['CddsiFailureCode'] = 'NAMED_RELEASE_GATE_FAILED'
    $exception.Data['CddsiFailureEvidenceJson'] = $json
    return $exception
}

function Throw-CddsiNamedGateFailure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence
    )

    $exception = New-CddsiNamedGateFailureException -Evidence $Evidence
    [Console]::Error.WriteLine(
        'CDDSI_NAMED_GATE_FAILURE_EVIDENCE_V1=' +
        [string]$exception.Data['CddsiFailureEvidenceJson']
    )
    throw $exception
}

function Assert-CddsiNamedHistoricalDiagnosticEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence,

        [Parameter(Mandatory = $true)]
        $Profile,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Assert-CddsiGateExactPropertySet -Value $Evidence -Expected @(
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
        -not (Test-CddsiGateInteger -Value $Evidence.SchemaVersion) -or
        [long]$Evidence.SchemaVersion -ne 1 -or
        [string]$Evidence.EvidenceType -cne 'CddsiHistoricalDiagnosticEvidence' -or
        [string]$Evidence.ContractVersion -cne 'D-026' -or
        [string]$Evidence.Status -cne 'COMPLETED' -or
        [string]$Evidence.DiagnosticResult -notin @('PASSED', 'FAILED_TESTS') -or
        $Evidence.ReleaseBlocking -isnot [bool] -or
        [bool]$Evidence.ReleaseBlocking -or
        [string]$Evidence.QualitySet -cne 'HistoricalDiagnostic' -or
        [string]$Evidence.EnforcementPhase -cne 'NamedProductReleaseGate' -or
        [string]$Evidence.AssertionFailureDisposition -cne
        'ReportOnlyAfterCompleteTestFailure'
    ) {
        throw 'Historical diagnostic evidence identity is invalid.'
    }
    foreach ($binding in @(
        @{ Name = 'ExpectedFileCount'; Value = 13L },
        @{ Name = 'ExpectedPesterFileCount'; Value = 13L },
        @{ Name = 'ExpectedShardCount'; Value = 9L },
        @{ Name = 'ExpectedWorkerCount'; Value = 20L },
        @{ Name = 'ExpectedProcessCount'; Value = 23L },
        @{ Name = 'ExpectedLedgerEntryCount'; Value = 52L }
    )) {
        if (
            -not (Test-CddsiGateInteger -Value $Evidence.($binding.Name)) -or
            [long]$Evidence.($binding.Name) -ne [long]$binding.Value
        ) {
            throw "Historical diagnostic evidence count drift: $($binding.Name)."
        }
    }
    foreach ($binding in @(
        @{ Name = 'ClassificationManifestSha256'; Value = [string]$Profile.ClassificationManifestSha256 },
        @{ Name = 'DependencyManifestSha256'; Value = [string]$Profile.DependencyManifestSha256 },
        @{ Name = 'QualitySetPolicySha256'; Value = [string]$Profile.CanonicalSha256 }
    )) {
        if ([string]$Evidence.($binding.Name) -cne [string]$binding.Value) {
            throw "Historical diagnostic evidence policy binding drift: $($binding.Name)."
        }
    }

    $summary = Assert-CddsiGateQualityEvidence `
        -Evidence $Evidence.CoreQualityEvidence `
        -QualitySetPolicy $Profile `
        -RepositoryRoot $RepositoryRoot
    if (
        [string]$summary.DiagnosticResult -cne [string]$Evidence.DiagnosticResult -or
        [long]$summary.FailedTestCount -ne [long]$Evidence.FailedTestCount -or
        [long]$summary.RequiredSuiteFailureCount -ne
        [long]$Evidence.RequiredSuiteFailureCount
    ) {
        throw 'Historical diagnostic evidence result binding drift.'
    }
    $coreSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $Evidence.CoreQualityEvidence
    if (
        [string]$Evidence.CoreQualityEvidenceSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.CoreQualityEvidenceSha256 -cne $coreSha256
    ) {
        throw 'Historical diagnostic nested evidence hash drift.'
    }
    $binding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiHistoricalDiagnosticEvidence'
        ContractVersion = 'D-026'
        Status = 'COMPLETED'
        DiagnosticResult = [string]$summary.DiagnosticResult
        ReleaseBlocking = $false
        QualitySet = 'HistoricalDiagnostic'
        EnforcementPhase = 'NamedProductReleaseGate'
        AssertionFailureDisposition = 'ReportOnlyAfterCompleteTestFailure'
        FailedTestCount = [long]$summary.FailedTestCount
        RequiredSuiteFailureCount = [long]$summary.RequiredSuiteFailureCount
        ClassificationManifestSha256 = [string]$Profile.ClassificationManifestSha256
        DependencyManifestSha256 = [string]$Profile.DependencyManifestSha256
        QualitySetPolicySha256 = [string]$Profile.CanonicalSha256
        ExpectedFileCount = 13
        ExpectedPesterFileCount = 13
        ExpectedShardCount = 9
        ExpectedWorkerCount = 20
        ExpectedProcessCount = 23
        ExpectedLedgerEntryCount = 52
        CoreQualityEvidenceSha256 = $coreSha256
    }
    if (
        [string]$Evidence.BindingSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.BindingSha256 -cne
        (Get-CddsiGateCanonicalObjectSha256 -Value $binding)
    ) {
        throw 'Historical diagnostic binding hash drift.'
    }
    return $true
}

function New-CddsiNamedGateRunEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProductEvidence,

        [Parameter(Mandatory = $true)]
        $HistoricalEvidence
    )

    $productSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $ProductEvidence
    $historicalSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $HistoricalEvidence
    $binding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiNamedReleaseGateRunEvidence'
        ContractVersion = 'D-026'
        Status = 'PASSED'
        ProductGateStatus = 'PASSED'
        HistoricalStatus = 'COMPLETED'
        HistoricalDiagnosticResult = [string]$HistoricalEvidence.DiagnosticResult
        HistoricalReleaseBlocking = $false
        ProductGateEvidenceSha256 = $productSha256
        HistoricalDiagnosticEvidenceSha256 = $historicalSha256
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiNamedReleaseGateRunEvidence'
        ContractVersion = 'D-026'
        Status = 'PASSED'
        ProductGateStatus = 'PASSED'
        HistoricalStatus = 'COMPLETED'
        HistoricalDiagnosticResult = [string]$HistoricalEvidence.DiagnosticResult
        HistoricalReleaseBlocking = $false
        ProductGateEvidenceSha256 = $productSha256
        HistoricalDiagnosticEvidenceSha256 = $historicalSha256
        ProductReleaseGateEvidence = $ProductEvidence
        HistoricalDiagnosticEvidence = $HistoricalEvidence
        BindingSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $binding
    }
}

function Assert-CddsiNamedGateRunEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence,

        [Parameter(Mandatory = $true)]
        $ProductProfile,

        [Parameter(Mandatory = $true)]
        $HistoricalProfile,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    Assert-CddsiGateExactPropertySet -Value $Evidence -Expected @(
        'BindingSha256',
        'ContractVersion',
        'EvidenceType',
        'HistoricalDiagnosticEvidence',
        'HistoricalDiagnosticEvidenceSha256',
        'HistoricalDiagnosticResult',
        'HistoricalReleaseBlocking',
        'HistoricalStatus',
        'ProductGateEvidenceSha256',
        'ProductGateStatus',
        'ProductReleaseGateEvidence',
        'SchemaVersion',
        'Status'
    ) -Label 'Named release-gate run evidence'
    if (
        -not (Test-CddsiGateInteger -Value $Evidence.SchemaVersion) -or
        [long]$Evidence.SchemaVersion -ne 1 -or
        [string]$Evidence.EvidenceType -cne 'CddsiNamedReleaseGateRunEvidence' -or
        [string]$Evidence.ContractVersion -cne 'D-026' -or
        [string]$Evidence.Status -cne 'PASSED' -or
        [string]$Evidence.ProductGateStatus -cne 'PASSED' -or
        [string]$Evidence.HistoricalStatus -cne 'COMPLETED' -or
        [string]$Evidence.HistoricalDiagnosticResult -notin @('PASSED', 'FAILED_TESTS') -or
        $Evidence.HistoricalReleaseBlocking -isnot [bool] -or
        [bool]$Evidence.HistoricalReleaseBlocking
    ) {
        throw 'Named release-gate run evidence identity is invalid.'
    }
    $null = Assert-CddsiProductReleaseGateEvidence `
        -Evidence $Evidence.ProductReleaseGateEvidence `
        -Profile $ProductProfile `
        -RepositoryRoot $RepositoryRoot
    $null = Assert-CddsiNamedHistoricalDiagnosticEvidence `
        -Evidence $Evidence.HistoricalDiagnosticEvidence `
        -Profile $HistoricalProfile `
        -RepositoryRoot $RepositoryRoot
    if (
        [string]$Evidence.HistoricalDiagnosticResult -cne
        [string]$Evidence.HistoricalDiagnosticEvidence.DiagnosticResult
    ) {
        throw 'Named release-gate historical result binding drift.'
    }
    $productSha256 = Get-CddsiGateCanonicalObjectSha256 `
        -Value $Evidence.ProductReleaseGateEvidence
    $historicalSha256 = Get-CddsiGateCanonicalObjectSha256 `
        -Value $Evidence.HistoricalDiagnosticEvidence
    if (
        [string]$Evidence.ProductGateEvidenceSha256 -cne $productSha256 -or
        [string]$Evidence.HistoricalDiagnosticEvidenceSha256 -cne $historicalSha256
    ) {
        throw 'Named release-gate nested evidence hash drift.'
    }
    $binding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiNamedReleaseGateRunEvidence'
        ContractVersion = 'D-026'
        Status = 'PASSED'
        ProductGateStatus = 'PASSED'
        HistoricalStatus = 'COMPLETED'
        HistoricalDiagnosticResult = [string]$Evidence.HistoricalDiagnosticResult
        HistoricalReleaseBlocking = $false
        ProductGateEvidenceSha256 = $productSha256
        HistoricalDiagnosticEvidenceSha256 = $historicalSha256
    }
    if (
        [string]$Evidence.BindingSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.BindingSha256 -cne
        (Get-CddsiGateCanonicalObjectSha256 -Value $binding)
    ) {
        throw 'Named release-gate run binding hash drift.'
    }
    return $true
}

if ($namedGateEntryImportOnly) {
    return
}

$requiredValues = [ordered]@{
    PowerShell7Executable = $namedGateEntryPowerShell7Executable
    PowerShell7Sha256 = $namedGateEntryPowerShell7Sha256
    WindowsPowerShellExecutable = $namedGateEntryWindowsPowerShellExecutable
    WindowsPowerShellSha256 = $namedGateEntryWindowsPowerShellSha256
    GitExecutable = $namedGateEntryGitExecutable
    GitSha256 = $namedGateEntryGitSha256
}
foreach ($requiredName in $requiredValues.Keys) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValues[$requiredName])) {
        throw "Named release gates require an explicit $requiredName grant."
    }
}

$productSucceeded = $false
$historicalSucceeded = $false
$productError = $null
$historicalError = $null
$productEvidence = $null
$historicalEvidence = $null

try {
    [object[]]$productResults = @(
        & $script:CddsiProductGateScript `
            -PowerShell7Executable $namedGateEntryPowerShell7Executable `
            -PowerShell7Sha256 $namedGateEntryPowerShell7Sha256 `
            -WindowsPowerShellExecutable $namedGateEntryWindowsPowerShellExecutable `
            -WindowsPowerShellSha256 $namedGateEntryWindowsPowerShellSha256 `
            -GitExecutable $namedGateEntryGitExecutable `
            -GitSha256 $namedGateEntryGitSha256 `
            -ProcessTimeoutSeconds $namedGateEntryProcessTimeoutSeconds `
            -PassThru
    )
    if ($productResults.Count -ne 1) {
        throw 'ProductReleaseGate evidence cardinality is invalid.'
    }
    $productEvidence = $productResults[0]
    $productSucceeded = $true
}
catch {
    $productError = $_.Exception
}

try {
    [object[]]$historicalResults = @(
        & $script:CddsiHistoricalGateScript `
            -PowerShell7Executable $namedGateEntryPowerShell7Executable `
            -PowerShell7Sha256 $namedGateEntryPowerShell7Sha256 `
            -WindowsPowerShellExecutable $namedGateEntryWindowsPowerShellExecutable `
            -WindowsPowerShellSha256 $namedGateEntryWindowsPowerShellSha256 `
            -GitExecutable $namedGateEntryGitExecutable `
            -GitSha256 $namedGateEntryGitSha256 `
            -ProcessTimeoutSeconds $namedGateEntryProcessTimeoutSeconds `
            -PassThru
    )
    if ($historicalResults.Count -ne 1) {
        throw 'Historical diagnostic evidence cardinality is invalid.'
    }
    $historicalEvidence = $historicalResults[0]
    $historicalSucceeded = $true
    Write-Host (
        'Historical diagnostics: COMPLETED/{0} (release-blocking=false).' -f
        [string]$historicalEvidence.DiagnosticResult
    )
}
catch {
    $historicalError = $_.Exception
}

if (-not $productSucceeded -or -not $historicalSucceeded) {
    $failureEvidence = New-CddsiNamedGateFailureEvidence `
        -ProductSucceeded $productSucceeded `
        -ProductError $productError `
        -HistoricalSucceeded $historicalSucceeded `
        -HistoricalError $historicalError `
        -FailureCode CHILD_GATE_FAILURE
    Throw-CddsiNamedGateFailure -Evidence $failureEvidence
}

try {
    $productProfile = Get-CddsiQualitySetPolicy `
        -RepositoryRoot $script:CddsiNamedGateRepositoryRoot `
        -QualitySet ProductReleaseBlocking
    $historicalProfile = Get-CddsiQualitySetPolicy `
        -RepositoryRoot $script:CddsiNamedGateRepositoryRoot `
        -QualitySet HistoricalDiagnostic
    $runEvidence = New-CddsiNamedGateRunEvidence `
        -ProductEvidence $productEvidence `
        -HistoricalEvidence $historicalEvidence
    $null = Assert-CddsiNamedGateRunEvidence `
        -Evidence $runEvidence `
        -ProductProfile $productProfile `
        -HistoricalProfile $historicalProfile `
        -RepositoryRoot $script:CddsiNamedGateRepositoryRoot
}
catch {
    $failureEvidence = New-CddsiNamedGateFailureEvidence `
        -ProductSucceeded $true `
        -ProductError $null `
        -HistoricalSucceeded $true `
        -HistoricalError $null `
        -FailureCode NAMED_GATE_VALIDATION_FAILED
    Throw-CddsiNamedGateFailure -Evidence $failureEvidence
}

if ($namedGateEntryPassThru) {
    return $runEvidence
}
Write-Host 'Named D-026 release gates passed; historical diagnostics were reported separately.' -ForegroundColor Green
