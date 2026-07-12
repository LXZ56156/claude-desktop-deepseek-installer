[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$OutputDirectory,
    [switch]$SkipQualityGate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'release-manifest.psd1'

function Get-ReleaseSourceFiles {
    $paths = @(& git -c core.quotepath=false -C $root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    return @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $relative = ([string]$_).Replace('\', '/')
        $fullPath = Join-Path $root $relative
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Repository file is missing: $relative" }
        [pscustomobject]@{ File = Get-Item -LiteralPath $fullPath -Force; RelativePath = $relative }
    } | Sort-Object RelativePath)
}

function Test-ReleaseTextFile {
    param([Parameter(Mandatory = $true)]$Item)
    $binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.msix', '.exe', '.dll', '.pdb', '.pdf')
    return ($binaryExtensions -notcontains $Item.File.Extension.ToLowerInvariant())
}

function Read-ReleaseTextStrict {
    param([Parameter(Mandatory = $true)]$Item)
    $bytes = [System.IO.File]::ReadAllBytes($Item.File.FullName)
    if ($bytes.Count -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) { throw "UTF-16 text is forbidden: $($Item.RelativePath)" }
    if (@($bytes | Where-Object { $_ -eq 0 }).Count -gt 0) { throw "NUL byte in text file: $($Item.RelativePath)" }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { return $strictUtf8.GetString($bytes) } catch { throw "Invalid UTF-8 text: $($Item.RelativePath)" }
}

function Invoke-ReleaseSecretScan {
    param([Parameter(Mandatory = $true)][object[]]$Items)
    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($item in @($Items)) {
        if (Test-ReleaseTextFile -Item $item) {
            $content = Read-ReleaseTextStrict -Item $item
            foreach ($finding in @(Find-CddsiPotentialSecrets -Content $content -Source $item.RelativePath)) {
                $findings.Add($finding)
            }
        }
    }
    if ($findings.Count -gt 0) {
        $safe = @($findings | ForEach-Object { '{0}:{1}:{2}' -f $_.Source, $_.Line, $_.Type }) -join ', '
        throw "Release secret scan failed: $safe"
    }
}

if (-not $SkipQualityGate) {
    & (Join-Path $PSScriptRoot 'check.ps1') -SkipPester
}

. (Join-Path $root 'lib\logger.ps1')
. (Join-Path $root 'lib\common.ps1')

$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
if ($manifest.SchemaVersion -ne 1) { throw 'Unsupported release manifest schema.' }
$packageFiles = @($manifest.PackageFiles)
$developmentFiles = @($manifest.DevelopmentOnlyFiles)
$classified = @($packageFiles + $developmentFiles)
$duplicates = @($classified | Group-Object | Where-Object Count -gt 1)
if ($duplicates.Count -gt 0) { throw "Duplicate release manifest entries: $($duplicates.Name -join ', ')" }

$sourceItems = @(Get-ReleaseSourceFiles)
$sourcePaths = @($sourceItems.RelativePath)
$inventoryDiff = @(Compare-Object -ReferenceObject @($sourcePaths | Sort-Object) -DifferenceObject @($classified | Sort-Object))
if ($inventoryDiff.Count -gt 0) {
    $details = @($inventoryDiff | ForEach-Object { '{0}:{1}' -f $_.SideIndicator, $_.InputObject }) -join ', '
    throw "Release manifest does not classify the repository exactly: $details"
}

$version = [System.IO.File]::ReadAllText((Join-Path $root 'VERSION'), [System.Text.Encoding]::UTF8).Trim()
if ($version -notmatch '^\d+\.\d+\.\d+(?:-[0-9A-Za-z.-]+)?$') { throw "VERSION is not valid SemVer: $version" }

foreach ($relative in $packageFiles) {
    $path = Join-Path $root $relative
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw "Package allow-list entry is missing: $relative" }
}

Write-Host '[release] Scanning every classified source text file for credentials...'
Invoke-ReleaseSecretScan -Items $sourceItems

Write-Host ("[release] Exact package allow-list: {0} files; development-only: {1} files." -f $packageFiles.Count, $developmentFiles.Count)
if ($DryRun) {
    Write-Host '[release] DryRun passed. No staging directory, ZIP, checksum, upload or publication was created.' -ForegroundColor Green
    return
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $root 'release'
}
$outputFullPath = [System.IO.Path]::GetFullPath($OutputDirectory).TrimEnd('\')
$rootFullPath = [System.IO.Path]::GetFullPath($root).TrimEnd('\')
if ([string]::Equals($outputFullPath, $rootFullPath, [StringComparison]::OrdinalIgnoreCase)) {
    throw 'OutputDirectory cannot be the repository root.'
}

$packageName = "claude-desktop-deepseek-installer-$version"
$zipPath = Join-Path $outputFullPath ($packageName + '.zip')
$checksumPath = $zipPath + '.sha256'
if (Test-Path -LiteralPath $zipPath) { throw "Refusing to overwrite existing ZIP: $zipPath" }
if (Test-Path -LiteralPath $checksumPath) { throw "Refusing to overwrite existing checksum: $checksumPath" }

$tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
$ownedRoot = Join-Path $tempBase ("cddsi-release-{0}" -f [guid]::NewGuid().ToString('N'))
$staging = Join-Path $ownedRoot $packageName
$ownedPrefix = $tempBase + '\cddsi-release-'
if (-not ([System.IO.Path]::GetFullPath($ownedRoot).StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase))) {
    throw 'Internal staging ownership check failed.'
}

try {
    [void][System.IO.Directory]::CreateDirectory($staging)
    foreach ($relative in $packageFiles) {
        $source = Join-Path $root $relative
        $destination = Join-Path $staging ($relative.Replace('/', '\'))
        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $destination))
        [System.IO.File]::Copy($source, $destination, $false)
    }

    $stagedItems = @(Get-ChildItem -LiteralPath $staging -File -Recurse | ForEach-Object {
        [pscustomobject]@{
            File = $_
            RelativePath = $_.FullName.Substring($staging.Length).TrimStart([char[]]'\/').Replace('\', '/')
        }
    } | Sort-Object RelativePath)
    $stageDiff = @(Compare-Object -ReferenceObject @($packageFiles | Sort-Object) -DifferenceObject @($stagedItems.RelativePath | Sort-Object))
    if ($stageDiff.Count -gt 0) { throw 'Staging inventory differs from the exact package allow-list.' }
    Invoke-ReleaseSecretScan -Items $stagedItems

    [void][System.IO.Directory]::CreateDirectory($outputFullPath)
    Compress-Archive -LiteralPath $staging -DestinationPath $zipPath -CompressionLevel Optimal -ErrorAction Stop

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    $archive = [System.IO.Compression.ZipFile]::OpenRead($zipPath)
    try {
        $prefix = $packageName + '/'
        $zipFiles = @($archive.Entries | Where-Object { -not [string]::IsNullOrEmpty($_.Name) } | ForEach-Object {
            $name = $_.FullName.Replace('\', '/')
            if (-not $name.StartsWith($prefix, [StringComparison]::Ordinal)) { throw "Unexpected ZIP root: $name" }
            $name.Substring($prefix.Length)
        } | Sort-Object)
    }
    finally {
        $archive.Dispose()
    }
    $zipDiff = @(Compare-Object -ReferenceObject @($packageFiles | Sort-Object) -DifferenceObject $zipFiles)
    if ($zipDiff.Count -gt 0) { throw 'ZIP entries differ from the exact package allow-list.' }

    $hash = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
    [System.IO.File]::WriteAllText($checksumPath, ("{0}  {1}" -f $hash, (Split-Path -Leaf $zipPath)) + [Environment]::NewLine, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "[release] Created: $zipPath" -ForegroundColor Green
    Write-Host "[release] SHA256: $hash" -ForegroundColor Green
}
catch {
    foreach ($target in @($zipPath, $checksumPath)) {
        if (Test-Path -LiteralPath $target -PathType Leaf) {
            [System.IO.File]::Delete($target)
        }
    }
    throw
}
finally {
    if (Test-Path -LiteralPath $ownedRoot -PathType Container) {
        $resolvedOwned = [System.IO.Path]::GetFullPath($ownedRoot)
        if ($resolvedOwned.StartsWith($ownedPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            [System.IO.Directory]::Delete($resolvedOwned, $true)
        }
    }
}
