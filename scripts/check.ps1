[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$PowerShell7Executable,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$PowerShell7Sha256,

    [Parameter(Mandatory = $true)]
    [string]$WindowsPowerShellExecutable,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$WindowsPowerShellSha256,

    [Parameter(Mandatory = $true)]
    [string]$GitExecutable,

    [Parameter(Mandatory = $true)]
    [ValidatePattern('^[a-fA-F0-9]{64}$')]
    [string]$GitSha256,

    [ValidateRange(30, 3600)]
    [int]$ProcessTimeoutSeconds = 900,

    [switch]$KeepSandboxOnFailure,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

. (Join-Path (Split-Path -Parent $PSScriptRoot) 'lib\logger.ps1')
Initialize-CddsiConsoleEncoding | Out-Null

$runner = Join-Path $PSScriptRoot 'invoke-host-sandbox.ps1'
try {
    $result = & $runner `
        -Scenario Quality `
        -RepositoryRoot (Split-Path -Parent $PSScriptRoot) `
        -PowerShell7Executable $PowerShell7Executable `
        -PowerShell7Sha256 $PowerShell7Sha256 `
        -WindowsPowerShellExecutable $WindowsPowerShellExecutable `
        -WindowsPowerShellSha256 $WindowsPowerShellSha256 `
        -GitExecutable $GitExecutable `
        -GitSha256 $GitSha256 `
        -ProcessTimeoutSeconds $ProcessTimeoutSeconds `
        -KeepSandboxOnFailure:$KeepSandboxOnFailure `
        -PassThru
}
catch {
    $primaryError = $_
    $failureJson = [string]$primaryError.Exception.Data['CddsiFailureEvidenceJson']
    if (-not [string]::IsNullOrWhiteSpace($failureJson) -and $failureJson.Length -le 200000) {
        try {
            $failureEvidence = $failureJson | ConvertFrom-Json -ErrorAction Stop
            if (
                $failureEvidence.SchemaVersion -eq 2 -and
                $failureEvidence.EvidenceType -ceq 'CddsiSafeFailureEvidence' -and
                $failureEvidence.Status -ceq 'FAILED_SAFE'
            ) {
                [Console]::Error.WriteLine('CDDSI_SAFE_FAILURE_EVIDENCE_V2=' + $failureJson)
            }
        }
        catch {
            # Never emit an unvalidated failure payload.
        }
    }
    throw $primaryError
}

if ($PassThru) {
    return $result
}

Write-Host 'All isolated quality checks passed.' -ForegroundColor Green
