[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -cne 'Desktop' -or
    $PSVersionTable.PSVersion.Major -ne 5 -or
    -not [Environment]::Is64BitProcess) {
    throw 'Run scripts/check.ps1 with 64-bit Windows PowerShell 5.1.'
}

$projectRoot = Split-Path -Parent $PSScriptRoot
[void](& (Join-Path $PSScriptRoot 'bootstrap-dev.ps1') -PassThru)
$manifest = Import-PowerShellDataFile -LiteralPath (
    Join-Path $PSScriptRoot 'release-manifest.psd1'
)

$parseTargets = @(
    @($manifest.PackageFiles) + @(
        'scripts/bootstrap-dev.ps1'
        'scripts/build-release.ps1'
        'scripts/check.ps1'
    ) | Where-Object { [IO.Path]::GetExtension($_) -in @('.ps1', '.psd1') }
)
foreach ($relative in $parseTargets) {
    $tokens = $null
    $errors = $null
    [void][Management.Automation.Language.Parser]::ParseFile(
        (Join-Path $projectRoot $relative),
        [ref]$tokens,
        [ref]$errors
    )
    if ($errors.Count -ne 0) {
        throw ('PowerShell 5.1 parse failed for {0}: {1}' -f
            $relative,
            ($errors.Message -join '; '))
    }
}

$configuration = [PesterConfiguration]::Default
$configuration.Run.Path = @(Join-Path $projectRoot 'tests')
$configuration.Run.PassThru = $true
$configuration.Output.Verbosity = 'Detailed'
$configuration.TestResult.Enabled = $false
$result = Invoke-Pester -Configuration $configuration
if ($result.FailedCount -ne 0 -or
    $result.SkippedCount -ne 0 -or
    $result.NotRunCount -ne 0 -or
    $result.InconclusiveCount -ne 0) {
    throw ('Pester gate failed: failed={0}, skipped={1}, notRun={2}, inconclusive={3}' -f
        $result.FailedCount,
        $result.SkippedCount,
        $result.NotRunCount,
        $result.InconclusiveCount)
}

$release = & (Join-Path $PSScriptRoot 'build-release.ps1') -DryRun
if ($release.Status -cne 'SUCCEEDED') {
    throw 'Release DryRun failed.'
}

$diffOutput = @(git -C $projectRoot diff --check 2>&1)
if ($LASTEXITCODE -ne 0) {
    throw ("git diff --check failed:`n{0}" -f ($diffOutput -join "`n"))
}

[pscustomobject]@{
    Status           = 'SUCCEEDED'
    PesterPassed     = $result.PassedCount
    ParsedFiles      = $parseTargets.Count
    PackageFileCount = $release.PackageFileCount
}
