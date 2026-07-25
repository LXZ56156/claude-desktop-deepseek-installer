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
$entryPowerShell7Executable = $PowerShell7Executable
$entryPowerShell7Sha256 = $PowerShell7Sha256
$entryWindowsPowerShellExecutable = $WindowsPowerShellExecutable
$entryWindowsPowerShellSha256 = $WindowsPowerShellSha256
$entryGitExecutable = $GitExecutable
$entryGitSha256 = $GitSha256
$entryProcessTimeoutSeconds = $ProcessTimeoutSeconds
$entryPassThru = $PassThru.IsPresent
$entryImportOnly = $ImportOnly.IsPresent
$script:CddsiProductGateRepositoryRoot = [System.IO.Path]::GetFullPath(
    (Split-Path -Parent $PSScriptRoot)
).TrimEnd('\')

function Test-CddsiProductGateSafeFailureText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return $true
    }
    $repositoryForwardPath = (
        $script:CddsiProductGateRepositoryRoot.Replace('\', '/')
    )
    if (
        (
            -not [string]::IsNullOrEmpty($Text) -and
            [IO.Path]::IsPathRooted($Text)
        ) -or
        $Text.IndexOf(
            $script:CddsiProductGateRepositoryRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0 -or
        $Text.IndexOf(
            $repositoryForwardPath,
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0 -or
        $Text -match '(?i)(?<![a-z0-9+.-])[a-z]:[\\/]' -or
        $Text -match '(?<!:)//(?=[^/])' -or
        $Text -match '\\\\' -or
        $Text -cmatch '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]' -or
        $Text -cmatch '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]' -or
        $Text -match (
            '(?i)(?:sk-[a-z0-9_-]{20,}|' +
            'bearer\s+[a-z0-9._~-]{20,})'
        ) -or
        $Text -match (
            '(?i)"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?' +
            '\s*[:=]\s*["'']?(?!<|null\b|placeholder\b|redacted\b)' +
            '[a-z0-9._~-]{20,}'
        ) -or
        $Text -match '(?is)-----BEGIN [^-\r\n]*PRIVATE KEY-----'
    ) {
        return $false
    }
    return $true
}

function Test-CddsiProductGateSafeFailureValue {
    [CmdletBinding()]
    param(
        [AllowNull()]
        $Value
    )

    if ($null -eq $Value) {
        return $true
    }
    if ($Value -is [string]) {
        return Test-CddsiProductGateSafeFailureText -Text $Value
    }
    if ($Value -is [Collections.IDictionary]) {
        foreach ($key in $Value.Keys) {
            if (
                -not (Test-CddsiProductGateSafeFailureText -Text ([string]$key)) -or
                -not (Test-CddsiProductGateSafeFailureValue -Value $Value[$key])
            ) {
                return $false
            }
        }
        return $true
    }
    if ($Value -is [pscustomobject]) {
        foreach ($property in $Value.PSObject.Properties) {
            if (
                -not (Test-CddsiProductGateSafeFailureText -Text $property.Name) -or
                -not (
                    Test-CddsiProductGateSafeFailureValue `
                        -Value $property.Value
                )
            ) {
                return $false
            }
        }
        return $true
    }
    if ($Value -is [Collections.IEnumerable]) {
        foreach ($item in $Value) {
            if (-not (Test-CddsiProductGateSafeFailureValue -Value $item)) {
                return $false
            }
        }
    }
    return $true
}

function ConvertFrom-CddsiProductGateSafeFailureEvidenceJson {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Json
    )

    if ([string]::IsNullOrWhiteSpace($Json)) {
        return $null
    }

    try {
        $evidence = $Json | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        return $null
    }
    $expectedNames = @(
        'CleanupFailureCode',
        'CleanupOutcome',
        'EvidenceType',
        'PrimaryFailureCode',
        'Progress',
        'RepositoryContentChanged',
        'RunId',
        'SafeFailureDisclosure',
        'SafeFailureMessage',
        'Scenario',
        'SchemaVersion',
        'Status'
    )
    $actualNames = @($evidence.PSObject.Properties.Name | Sort-Object)
    if (
        ($actualNames -join "`n") -cne ($expectedNames -join "`n") -or
        ($evidence.SchemaVersion -isnot [int] -and
            $evidence.SchemaVersion -isnot [long]) -or
        [long]$evidence.SchemaVersion -ne 3 -or
        [string]$evidence.EvidenceType -cne 'CddsiSafeFailureEvidence' -or
        [string]$evidence.Status -cne 'FAILED_SAFE' -or
        [string]$evidence.RunId -notmatch
            '^[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$' -or
        [string]$evidence.PrimaryFailureCode -notmatch '^[A-Z0-9_]+$' -or
        [string]$evidence.CleanupFailureCode -notmatch '^[A-Z0-9_]+$' -or
        $evidence.RepositoryContentChanged -isnot [bool] -or
        $evidence.SafeFailureDisclosure -isnot [bool] -or
        -not [bool]$evidence.SafeFailureDisclosure -or
        $null -eq $evidence.Progress -or
        ([string]$evidence.SafeFailureMessage).Length -gt 6000
    ) {
        return $null
    }
    if (-not (Test-CddsiProductGateSafeFailureValue -Value $evidence)) {
        return $null
    }

    $normalizedJson = $evidence | ConvertTo-Json -Depth 100 -Compress
    if (
        $normalizedJson.IndexOf(
            $script:CddsiProductGateRepositoryRoot,
            [StringComparison]::OrdinalIgnoreCase
        ) -ge 0 -or
        $normalizedJson -cmatch '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F]' -or
        $normalizedJson -match (
            '(?i)(?:(?<![a-z0-9+.-])[a-z]:(?:\\\\|/)|' +
            '\\\\\\\\|(?<!:)//(?=[^/]))'
        ) -or
        $normalizedJson -match (
            '(?i)(?:sk-[a-z0-9_-]{20,}|' +
            'bearer\s+[a-z0-9._~-]{20,})'
        ) -or
        $normalizedJson -match (
            '(?i)"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?' +
            '\s*[:=]\s*["'']?(?!<|null\b|placeholder\b|redacted\b)' +
            '[a-z0-9._~-]{20,}'
        ) -or
        $normalizedJson -match
            '(?is)-----BEGIN [^-\r\n]*PRIVATE KEY-----'
    ) {
        return $null
    }
    return $evidence
}

function New-CddsiProductGateFailureException {
    [CmdletBinding()]
    param(
        [ValidateSet('IMPORT', 'EXECUTION')]
        [string]$FailureStage = 'EXECUTION',

        [AllowNull()]
        [System.Exception]$Cause
    )

    $exception = [InvalidOperationException]::new(
        'ProductReleaseGate failed safely.'
    )
    $exception.Data['CddsiFailureCode'] = 'PRODUCT_RELEASE_GATE_FAILED'
    $exception.Data['CddsiFailureStage'] = $FailureStage
    if ($null -ne $Cause) {
        $safeEvidenceJson = [string]$Cause.Data['CddsiFailureEvidenceJson']
        $safeEvidence = ConvertFrom-CddsiProductGateSafeFailureEvidenceJson `
            -Json $safeEvidenceJson
        if ($null -ne $safeEvidence) {
            $exception.Data['CddsiSafeFailureEvidenceStatus'] = 'BOUND'
            $exception.Data['CddsiSafeFailureEvidenceJson'] = (
                $safeEvidence | ConvertTo-Json -Depth 100 -Compress
            )
        }
        elseif (-not [string]::IsNullOrWhiteSpace($safeEvidenceJson)) {
            $exception.Data['CddsiSafeFailureEvidenceStatus'] = (
                'REJECTED_UNSAFE'
            )
        }
    }
    return $exception
}

try {
    . (Join-Path $PSScriptRoot 'release-gate-common.ps1')
    . (Join-Path $PSScriptRoot 'quality-set-policy.ps1')
    . (Join-Path $PSScriptRoot 'invoke-host-sandbox.ps1') -ImportOnly
}
catch {
    throw (New-CddsiProductGateFailureException -FailureStage IMPORT -Cause $_.Exception)
}

function Assert-CddsiProductGateProfile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Profile,

        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $classification = Import-PowerShellDataFile -LiteralPath (
        Join-Path $RepositoryRoot 'config\product-release-gate.psd1'
    )
    if (
        [string]$classification.ContractVersion -cne 'D-026' -or
        [string]$classification.EnforcementPhase -cne 'NamedProductReleaseGate' -or
        [string]$Profile.ContractVersion -cne 'D-026' -or
        [string]$Profile.QualitySet -cne 'ProductReleaseBlocking' -or
        [string]$Profile.AssertionFailureDisposition -cne 'Blocking' -or
        [long]$Profile.FileCount -ne 29 -or
        [long]$Profile.PesterFileCount -ne 29 -or
        [long]$Profile.ShardCount -ne 8 -or
        [long]$Profile.WorkerCount -ne 18 -or
        [long]$Profile.ProcessCount -ne 21 -or
        [long]$Profile.LedgerEntryCount -ne 48 -or
        [string]$Profile.ClassificationManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Profile.DependencyManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Profile.CanonicalSha256 -cnotmatch '^[a-f0-9]{64}$'
    ) {
        throw 'The D-026 product release profile is not active and exact.'
    }
}

function New-CddsiProductReleaseGateEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Profile,

        [Parameter(Mandatory = $true)]
        $BeforeQuality,

        [Parameter(Mandatory = $true)]
        $AfterQuality,

        [Parameter(Mandatory = $true)]
        $AfterRelease,

        [Parameter(Mandatory = $true)]
        $ProductQualityEvidence,

        [Parameter(Mandatory = $true)]
        $ReleaseDryRunEvidence
    )

    $qualitySha256 = Get-CddsiGateCanonicalObjectSha256 -Value $ProductQualityEvidence
    $releaseSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $ReleaseDryRunEvidence
    $repositoryBinding = [pscustomobject][ordered]@{
        Scope = 'WorkingTreeExcludingDotGit'
        BeforeQualitySha256 = [string]$BeforeQuality.Hash
        AfterQualitySha256 = [string]$AfterQuality.Hash
        AfterReleaseSha256 = [string]$AfterRelease.Hash
        FileCount = [long]$BeforeQuality.FileCount
        DirectoryCount = [long]$BeforeQuality.DirectoryCount
    }
    $repositoryBindingSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $repositoryBinding
    $binding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiProductReleaseGateEvidence'
        ContractVersion = 'D-026'
        EnforcementPhase = 'NamedProductReleaseGate'
        Status = 'PASSED'
        ReleaseBlocking = $true
        QualitySet = 'ProductReleaseBlocking'
        ClassificationManifestSha256 = [string]$Profile.ClassificationManifestSha256
        DependencyManifestSha256 = [string]$Profile.DependencyManifestSha256
        QualitySetPolicySha256 = [string]$Profile.CanonicalSha256
        ExpectedFileCount = [long]$Profile.FileCount
        ExpectedPesterFileCount = [long]$Profile.PesterFileCount
        ExpectedShardCount = [long]$Profile.ShardCount
        ExpectedWorkerCount = [long]$Profile.WorkerCount
        ExpectedProcessCount = [long]$Profile.ProcessCount
        ExpectedLedgerEntryCount = [long]$Profile.LedgerEntryCount
        RepositoryBindingSha256 = $repositoryBindingSha256
        ProductQualityEvidenceSha256 = $qualitySha256
        ReleaseDryRunEvidenceSha256 = $releaseSha256
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiProductReleaseGateEvidence'
        ContractVersion = 'D-026'
        EnforcementPhase = 'NamedProductReleaseGate'
        Status = 'PASSED'
        ReleaseBlocking = $true
        QualitySet = 'ProductReleaseBlocking'
        ClassificationManifestSha256 = [string]$Profile.ClassificationManifestSha256
        DependencyManifestSha256 = [string]$Profile.DependencyManifestSha256
        QualitySetPolicySha256 = [string]$Profile.CanonicalSha256
        ExpectedFileCount = [long]$Profile.FileCount
        ExpectedPesterFileCount = [long]$Profile.PesterFileCount
        ExpectedShardCount = [long]$Profile.ShardCount
        ExpectedWorkerCount = [long]$Profile.WorkerCount
        ExpectedProcessCount = [long]$Profile.ProcessCount
        ExpectedLedgerEntryCount = [long]$Profile.LedgerEntryCount
        RepositorySnapshotBeforeQuality = $BeforeQuality
        RepositorySnapshotAfterQuality = $AfterQuality
        RepositorySnapshotAfterRelease = $AfterRelease
        RepositoryBindingSha256 = $repositoryBindingSha256
        ProductQualityEvidenceSha256 = $qualitySha256
        ReleaseDryRunEvidenceSha256 = $releaseSha256
        ProductQualityEvidence = $ProductQualityEvidence
        ReleaseDryRunEvidence = $ReleaseDryRunEvidence
        GateBindingSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $binding
    }
}

function Assert-CddsiProductReleaseGateEvidence {
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
        'ClassificationManifestSha256',
        'ContractVersion',
        'DependencyManifestSha256',
        'EnforcementPhase',
        'EvidenceType',
        'ExpectedFileCount',
        'ExpectedLedgerEntryCount',
        'ExpectedPesterFileCount',
        'ExpectedProcessCount',
        'ExpectedShardCount',
        'ExpectedWorkerCount',
        'GateBindingSha256',
        'ProductQualityEvidence',
        'ProductQualityEvidenceSha256',
        'QualitySet',
        'QualitySetPolicySha256',
        'ReleaseBlocking',
        'ReleaseDryRunEvidence',
        'ReleaseDryRunEvidenceSha256',
        'RepositoryBindingSha256',
        'RepositorySnapshotAfterQuality',
        'RepositorySnapshotAfterRelease',
        'RepositorySnapshotBeforeQuality',
        'SchemaVersion',
        'Status'
    ) -Label 'Product release gate evidence'
    if (
        -not (Test-CddsiGateInteger -Value $Evidence.SchemaVersion) -or
        [long]$Evidence.SchemaVersion -ne 1 -or
        [string]$Evidence.EvidenceType -cne 'CddsiProductReleaseGateEvidence' -or
        [string]$Evidence.ContractVersion -cne 'D-026' -or
        [string]$Evidence.EnforcementPhase -cne 'NamedProductReleaseGate' -or
        [string]$Evidence.Status -cne 'PASSED' -or
        $Evidence.ReleaseBlocking -isnot [bool] -or
        -not [bool]$Evidence.ReleaseBlocking -or
        [string]$Evidence.QualitySet -cne 'ProductReleaseBlocking'
    ) {
        throw 'Product release gate evidence identity is invalid.'
    }
    foreach ($binding in @(
        @{ Name = 'ExpectedFileCount'; Value = [long]$Profile.FileCount },
        @{ Name = 'ExpectedPesterFileCount'; Value = [long]$Profile.PesterFileCount },
        @{ Name = 'ExpectedShardCount'; Value = [long]$Profile.ShardCount },
        @{ Name = 'ExpectedWorkerCount'; Value = [long]$Profile.WorkerCount },
        @{ Name = 'ExpectedProcessCount'; Value = [long]$Profile.ProcessCount },
        @{ Name = 'ExpectedLedgerEntryCount'; Value = [long]$Profile.LedgerEntryCount }
    )) {
        if (
            -not (Test-CddsiGateInteger -Value $Evidence.($binding.Name)) -or
            [long]$Evidence.($binding.Name) -ne [long]$binding.Value
        ) {
            throw "Product release gate count binding drift: $($binding.Name)."
        }
    }
    foreach ($binding in @(
        @{ Name = 'ClassificationManifestSha256'; Value = [string]$Profile.ClassificationManifestSha256 },
        @{ Name = 'DependencyManifestSha256'; Value = [string]$Profile.DependencyManifestSha256 },
        @{ Name = 'QualitySetPolicySha256'; Value = [string]$Profile.CanonicalSha256 }
    )) {
        if ([string]$Evidence.($binding.Name) -cne [string]$binding.Value) {
            throw "Product release gate policy binding drift: $($binding.Name)."
        }
    }

    $before = $Evidence.RepositorySnapshotBeforeQuality
    $afterQuality = $Evidence.RepositorySnapshotAfterQuality
    $afterRelease = $Evidence.RepositorySnapshotAfterRelease
    foreach ($snapshotEntry in @(
        @{ Value = $before; Label = 'Product gate snapshot before quality' },
        @{ Value = $afterQuality; Label = 'Product gate snapshot after quality' },
        @{ Value = $afterRelease; Label = 'Product gate snapshot after release' }
    )) {
        Assert-CddsiGateExactPropertySet -Value $snapshotEntry.Value -Expected @(
            'DirectoryCount',
            'FileCount',
            'Hash',
            'SchemaVersion',
            'Scope'
        ) -Label $snapshotEntry.Label
        if (
            -not (Test-CddsiGateInteger -Value $snapshotEntry.Value.SchemaVersion) -or
            [long]$snapshotEntry.Value.SchemaVersion -ne 1 -or
            [string]$snapshotEntry.Value.Scope -cne 'WorkingTreeExcludingDotGit' -or
            [string]$snapshotEntry.Value.Hash -cnotmatch '^[a-f0-9]{64}$' -or
            -not (Test-CddsiGateInteger -Value $snapshotEntry.Value.FileCount) -or
            [long]$snapshotEntry.Value.FileCount -le 0 -or
            -not (Test-CddsiGateInteger -Value $snapshotEntry.Value.DirectoryCount) -or
            [long]$snapshotEntry.Value.DirectoryCount -le 0
        ) {
            throw "$($snapshotEntry.Label) is invalid."
        }
    }
    Assert-CddsiGateRepositorySnapshotsEqual -Expected $before -Actual $afterQuality `
        -Label 'Product quality execution'
    Assert-CddsiGateRepositorySnapshotsEqual -Expected $before -Actual $afterRelease `
        -Label 'Product release execution'

    $qualitySummary = Assert-CddsiGateQualityEvidence `
        -Evidence $Evidence.ProductQualityEvidence `
        -QualitySetPolicy $Profile `
        -RepositoryRoot $RepositoryRoot
    if ([string]$qualitySummary.DiagnosticResult -cne 'PASSED') {
        throw 'Product quality evidence did not pass.'
    }
    $null = Assert-CddsiGateReleaseEvidence `
        -Evidence $Evidence.ReleaseDryRunEvidence `
        -RepositoryRoot $RepositoryRoot `
        -RepositorySnapshot $afterQuality

    $qualitySha256 = Get-CddsiGateCanonicalObjectSha256 -Value $Evidence.ProductQualityEvidence
    $releaseSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $Evidence.ReleaseDryRunEvidence
    if (
        [string]$Evidence.ProductQualityEvidenceSha256 -cne $qualitySha256 -or
        [string]$Evidence.ReleaseDryRunEvidenceSha256 -cne $releaseSha256
    ) {
        throw 'Product release gate nested evidence hash drift.'
    }
    $repositoryBinding = [pscustomobject][ordered]@{
        Scope = 'WorkingTreeExcludingDotGit'
        BeforeQualitySha256 = [string]$before.Hash
        AfterQualitySha256 = [string]$afterQuality.Hash
        AfterReleaseSha256 = [string]$afterRelease.Hash
        FileCount = [long]$before.FileCount
        DirectoryCount = [long]$before.DirectoryCount
    }
    $repositoryBindingSha256 = Get-CddsiGateCanonicalObjectSha256 -Value $repositoryBinding
    if ([string]$Evidence.RepositoryBindingSha256 -cne $repositoryBindingSha256) {
        throw 'Product release gate repository binding hash drift.'
    }
    $binding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        EvidenceType = 'CddsiProductReleaseGateEvidence'
        ContractVersion = 'D-026'
        EnforcementPhase = 'NamedProductReleaseGate'
        Status = 'PASSED'
        ReleaseBlocking = $true
        QualitySet = 'ProductReleaseBlocking'
        ClassificationManifestSha256 = [string]$Profile.ClassificationManifestSha256
        DependencyManifestSha256 = [string]$Profile.DependencyManifestSha256
        QualitySetPolicySha256 = [string]$Profile.CanonicalSha256
        ExpectedFileCount = [long]$Profile.FileCount
        ExpectedPesterFileCount = [long]$Profile.PesterFileCount
        ExpectedShardCount = [long]$Profile.ShardCount
        ExpectedWorkerCount = [long]$Profile.WorkerCount
        ExpectedProcessCount = [long]$Profile.ProcessCount
        ExpectedLedgerEntryCount = [long]$Profile.LedgerEntryCount
        RepositoryBindingSha256 = $repositoryBindingSha256
        ProductQualityEvidenceSha256 = $qualitySha256
        ReleaseDryRunEvidenceSha256 = $releaseSha256
    }
    if (
        [string]$Evidence.GateBindingSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        [string]$Evidence.GateBindingSha256 -cne (Get-CddsiGateCanonicalObjectSha256 -Value $binding)
    ) {
        throw 'Product release gate binding hash drift.'
    }
    return $true
}

if ($entryImportOnly) {
    return
}

$requiredValues = [ordered]@{
    PowerShell7Executable = $entryPowerShell7Executable
    PowerShell7Sha256 = $entryPowerShell7Sha256
    WindowsPowerShellExecutable = $entryWindowsPowerShellExecutable
    WindowsPowerShellSha256 = $entryWindowsPowerShellSha256
    GitExecutable = $entryGitExecutable
    GitSha256 = $entryGitSha256
}
foreach ($requiredName in $requiredValues.Keys) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValues[$requiredName])) {
        throw "ProductReleaseGate requires an explicit $requiredName grant."
    }
}

try {
    $profile = Get-CddsiQualitySetPolicy `
        -RepositoryRoot $script:CddsiProductGateRepositoryRoot `
        -QualitySet ProductReleaseBlocking
    Assert-CddsiProductGateProfile `
        -Profile $profile `
        -RepositoryRoot $script:CddsiProductGateRepositoryRoot

    $beforeQualitySnapshot = Get-CddsiRepositorySnapshot `
        -RootPath $script:CddsiProductGateRepositoryRoot
    $beforeQuality = Assert-CddsiGateRepositorySnapshot `
        -Snapshot $beforeQualitySnapshot `
        -Label 'Product gate snapshot before quality'

    $productQualityEvidence = & (Join-Path $PSScriptRoot 'invoke-host-sandbox.ps1') `
        -Scenario Quality `
        -QualitySet ProductReleaseBlocking `
        -RepositoryRoot $script:CddsiProductGateRepositoryRoot `
        -PowerShell7Executable $entryPowerShell7Executable `
        -PowerShell7Sha256 $entryPowerShell7Sha256 `
        -WindowsPowerShellExecutable $entryWindowsPowerShellExecutable `
        -WindowsPowerShellSha256 $entryWindowsPowerShellSha256 `
        -GitExecutable $entryGitExecutable `
        -GitSha256 $entryGitSha256 `
        -ProcessTimeoutSeconds $entryProcessTimeoutSeconds `
        -PassThru
    $qualitySummary = Assert-CddsiGateQualityEvidence `
        -Evidence $productQualityEvidence `
        -QualitySetPolicy $profile `
        -RepositoryRoot $script:CddsiProductGateRepositoryRoot
    if ([string]$qualitySummary.DiagnosticResult -cne 'PASSED') {
        throw 'Product release-blocking tests did not pass.'
    }

    $afterQualitySnapshot = Get-CddsiRepositorySnapshot `
        -RootPath $script:CddsiProductGateRepositoryRoot
    $afterQuality = Assert-CddsiGateRepositorySnapshot `
        -Snapshot $afterQualitySnapshot `
        -Label 'Product gate snapshot after quality'
    Assert-CddsiGateRepositorySnapshotsEqual `
        -Expected $beforeQuality `
        -Actual $afterQuality `
        -Label 'Product quality execution'
    if (
        [string]$productQualityEvidence.REPOSITORY_BEFORE_SHA256 -cne [string]$beforeQuality.Hash -or
        [string]$productQualityEvidence.REPOSITORY_AFTER_SHA256 -cne [string]$afterQuality.Hash -or
        [long]$productQualityEvidence.REPOSITORY_BEFORE_FILE_COUNT -ne [long]$beforeQuality.FileCount -or
        [long]$productQualityEvidence.REPOSITORY_AFTER_FILE_COUNT -ne [long]$afterQuality.FileCount -or
        [long]$productQualityEvidence.REPOSITORY_BEFORE_DIRECTORY_COUNT -ne [long]$beforeQuality.DirectoryCount -or
        [long]$productQualityEvidence.REPOSITORY_AFTER_DIRECTORY_COUNT -ne [long]$afterQuality.DirectoryCount
    ) {
        throw 'Product quality evidence is not bound to the outer repository snapshots.'
    }

    $releaseDryRunEvidence = & (Join-Path $PSScriptRoot 'build-release.ps1') -DryRun
    $null = Assert-CddsiGateReleaseEvidence `
        -Evidence $releaseDryRunEvidence `
        -RepositoryRoot $script:CddsiProductGateRepositoryRoot `
        -RepositorySnapshot $afterQuality

    $afterReleaseSnapshot = Get-CddsiRepositorySnapshot `
        -RootPath $script:CddsiProductGateRepositoryRoot
    $afterRelease = Assert-CddsiGateRepositorySnapshot `
        -Snapshot $afterReleaseSnapshot `
        -Label 'Product gate snapshot after release'
    Assert-CddsiGateRepositorySnapshotsEqual `
        -Expected $beforeQuality `
        -Actual $afterRelease `
        -Label 'Product release execution'
    if (
        [long]$releaseDryRunEvidence.RepositoryFileCount -ne [long]$afterQuality.FileCount -or
        [long]$releaseDryRunEvidence.RepositoryDirectoryCount -ne [long]$afterQuality.DirectoryCount
    ) {
        throw 'Release DryRun evidence is not bound to the outer repository snapshot.'
    }

    $gateEvidence = New-CddsiProductReleaseGateEvidence `
        -Profile $profile `
        -BeforeQuality $beforeQuality `
        -AfterQuality $afterQuality `
        -AfterRelease $afterRelease `
        -ProductQualityEvidence $productQualityEvidence `
        -ReleaseDryRunEvidence $releaseDryRunEvidence
    $null = Assert-CddsiProductReleaseGateEvidence `
        -Evidence $gateEvidence `
        -Profile $profile `
        -RepositoryRoot $script:CddsiProductGateRepositoryRoot

    if ($entryPassThru) {
        return $gateEvidence
    }
    Write-Host 'ProductReleaseGate passed with exact D-026 product tests and Release DryRun evidence.' -ForegroundColor Green
}
catch {
    throw (New-CddsiProductGateFailureException -FailureStage EXECUTION -Cause $_.Exception)
}
