[CmdletBinding()]
param(
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$lock = Import-PowerShellDataFile -LiteralPath (
    Join-Path $projectRoot 'config\dev-dependencies.psd1'
)
$pesterRoot = Join-Path $projectRoot $lock.Pester.RootRelativePath
$manifest = Join-Path $pesterRoot $lock.Pester.ManifestRelativePath
$license = Join-Path $projectRoot $lock.Pester.LicenseRelativePath

foreach ($path in @($pesterRoot, $manifest, $license)) {
    if (-not (Test-Path -LiteralPath $path)) {
        throw "Locked development dependency is missing: $path"
    }
}

$files = @(Get-ChildItem -LiteralPath $pesterRoot -File -Recurse)
$totalBytes = [long](($files | Measure-Object -Property Length -Sum).Sum)
if ($files.Count -ne $lock.Pester.ExpectedFileCount -or
    $totalBytes -ne $lock.Pester.ExpectedTotalBytes) {
    throw 'Vendored Pester tree count or byte length does not match the lock.'
}

$manifestHash = (Get-FileHash -LiteralPath $manifest -Algorithm SHA256).Hash.ToLowerInvariant()
$licenseHash = (Get-FileHash -LiteralPath $license -Algorithm SHA256).Hash.ToLowerInvariant()
if ($manifestHash -cne $lock.Pester.ExpectedManifestSha256 -or
    (Get-Item -LiteralPath $license).Length -ne $lock.Pester.ExpectedLicenseBytes -or
    $licenseHash -cne $lock.Pester.ExpectedLicenseSha256) {
    throw 'Vendored Pester manifest or license does not match the lock.'
}

$byRelativePath = @{}
foreach ($file in $files) {
    $relative = $file.FullName.Substring($pesterRoot.Length + 1).Replace('\', '/')
    if ($byRelativePath.ContainsKey($relative)) {
        throw 'Vendored Pester tree contains duplicate relative paths.'
    }
    $byRelativePath[$relative] = $file
}
$relativePaths = [string[]]@($byRelativePath.Keys)
[Array]::Sort($relativePaths, [StringComparer]::Ordinal)
$records = foreach ($relative in $relativePaths) {
    $file = $byRelativePath[$relative]
    $hash = (Get-FileHash -LiteralPath $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    '{0}|{1}|{2}' -f $relative, $hash, $file.Length
}
$bytes = (New-Object Text.UTF8Encoding($false)).GetBytes(($records -join "`n"))
$sha = [Security.Cryptography.SHA256]::Create()
try {
    $treeHash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
}
finally {
    $sha.Dispose()
}
if ($treeHash -cne $lock.Pester.ExpectedTreeSha256) {
    throw 'Vendored Pester tree hash does not match the lock.'
}

Import-Module -Name $manifest -Global -Force -ErrorAction Stop
$loaded = Get-Module Pester | Sort-Object Version -Descending | Select-Object -First 1
if ($null -eq $loaded -or $loaded.Version.ToString() -cne $lock.Pester.Version) {
    throw 'The locked Pester version was not loaded.'
}

$result = [pscustomobject]@{
    PesterVersion = $loaded.Version.ToString()
    FileCount     = $files.Count
    TotalBytes    = $totalBytes
    TreeSha256    = $treeHash
}
if ($PassThru) {
    return $result
}
$result | Format-List
