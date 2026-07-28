[CmdletBinding()]
param(
    [ValidateSet('Install', 'Diagnose', 'Restore')]
    [string]$Action = 'Install',

    [switch]$Live,
    [switch]$DryRun,
    [switch]$AcceptChanges,
    [switch]$NonInteractive,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$bootstrapPath = Join-Path $PSScriptRoot 'lib\bootstrap.ps1'
. $bootstrapPath
Import-CddsiLibraries

if ($Live -and $DryRun) {
    $result = New-CddsiResult -Status 'FAILED' -ErrorCode 'MODE_CONFLICT' `
        -Message 'Live 和 DryRun 不能同时使用。' `
        -NextStep '只选择一种运行模式。'
}
elseif (-not $Live) {
    $result = Invoke-CddsiDryRun -Action $Action
}
else {
    $result = Invoke-CddsiAction -Action $Action `
        -ProjectRoot $PSScriptRoot `
        -AcceptChanges:$AcceptChanges `
        -NonInteractive:$NonInteractive
}

if ($PassThru) {
    return $result
}

Write-CddsiResult -Result $result
exit (Get-CddsiExitCode -Status $result.Status)
