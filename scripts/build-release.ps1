[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$OutputDirectory
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$projectRoot = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'release-manifest.psd1'
$manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
$package = @($manifest.PackageFiles | ForEach-Object { $_.Replace('\', '/') })
$development = @($manifest.DevelopmentOnlyFiles | ForEach-Object { $_.Replace('\', '/') })

if ($manifest.SchemaVersion -ne 3 -or
    $package.Count -eq 0 -or
    @($package | Sort-Object -Unique).Count -ne $package.Count -or
    @($development | Sort-Object -Unique).Count -ne $development.Count -or
    @($package | Where-Object { $_ -in $development }).Count -ne 0) {
    throw 'Release manifest classification is invalid.'
}

$listed = @($package + $development | Sort-Object -Unique)
$sourceFiles = @(
    git -C $projectRoot -c core.quotePath=false ls-files --cached --others --exclude-standard |
        ForEach-Object { $_.Replace('\', '/') } |
        Where-Object { Test-Path -LiteralPath (Join-Path $projectRoot $_) } |
        Sort-Object -Unique
)
if ($LASTEXITCODE -ne 0) {
    throw 'Unable to enumerate the source tree with Git.'
}
$missingClassification = @($sourceFiles | Where-Object { $_ -notin $listed })
$staleClassification = @($listed | Where-Object { $_ -notin $sourceFiles })
if ($missingClassification.Count -ne 0 -or $staleClassification.Count -ne 0) {
    throw ('Release classification mismatch. Unclassified=[{0}] Stale=[{1}]' -f
        ($missingClassification -join ', '),
        ($staleClassification -join ', '))
}

$textExtensions = @('.ps1', '.psd1', '.cmd', '.md', '.json', '.yml', '.yaml', '.txt', '.cs')
$secretPatterns = @(
    '(?i)\bsk-[A-Za-z0-9_-]{20,}\b'
    '(?i)\bapi[_-]?key\s*[:=]\s*["''][A-Za-z0-9_-]{8,}["'']'
    '(?i)\bauthorization\s*[:=]\s*["'']?bearer\s+[A-Za-z0-9._-]{16,}'
)
foreach ($relative in $sourceFiles) {
    $full = Join-Path $projectRoot $relative
    $item = Get-Item -LiteralPath $full -Force
    if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
        throw "Reparse points are not allowed in the classified source tree: $relative"
    }
    if ($textExtensions -contains $item.Extension.ToLowerInvariant()) {
        $content = [IO.File]::ReadAllText($full)
        foreach ($pattern in $secretPatterns) {
            if ($content -match $pattern) {
                throw "Potential secret found in classified source: $relative"
            }
        }
    }
}

foreach ($relative in $package) {
    if (-not (Test-Path -LiteralPath (Join-Path $projectRoot $relative) -PathType Leaf)) {
        throw "Package file is missing: $relative"
    }
}

$validation = [pscustomobject]@{
    Status               = 'SUCCEEDED'
    DryRun               = [bool]$DryRun
    PackageFileCount     = $package.Count
    DevelopmentFileCount = $development.Count
    ClassifiedFileCount  = $listed.Count
}
if ($DryRun) {
    $validation
    return
}

if ([string]::IsNullOrWhiteSpace($OutputDirectory)) {
    $OutputDirectory = Join-Path $projectRoot 'release'
}
$version = ([IO.File]::ReadAllText((Join-Path $projectRoot 'VERSION'))).Trim()
if ($version -notmatch '^[0-9]+\.[0-9]+\.[0-9]+(?:-[a-z0-9.-]+)?$') {
    throw 'VERSION is not a safe release identifier.'
}
$archiveName = '{0}-{1}.zip' -f $manifest.ProductName, $version
$archivePath = Join-Path $OutputDirectory $archiveName
$hashPath = '{0}.sha256' -f $archivePath
if ((Test-Path -LiteralPath $archivePath) -or (Test-Path -LiteralPath $hashPath)) {
    throw 'Release output already exists; move it aside before rebuilding.'
}

$staging = Join-Path ([IO.Path]::GetTempPath()) (
    'cddsi-release-{0}' -f ([guid]::NewGuid().ToString('N'))
)
$staging = [IO.Path]::GetFullPath($staging)
$tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath())
if (-not $staging.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
    (Split-Path -Leaf $staging) -notmatch '^cddsi-release-[a-f0-9]{32}$') {
    throw 'Unsafe release staging path.'
}

New-Item -ItemType Directory -Path $staging -ErrorAction Stop | Out-Null
try {
    [IO.File]::WriteAllText(
        (Join-Path $staging '.cddsi-release-owner'),
        'claude-desktop-deepseek-installer',
        (New-Object Text.UTF8Encoding($false))
    )
    foreach ($relative in $package) {
        $source = Join-Path $projectRoot $relative
        $destination = Join-Path $staging $relative
        $parent = Split-Path -Parent $destination
        if (-not (Test-Path -LiteralPath $parent -PathType Container)) {
            New-Item -ItemType Directory -Path $parent -Force -ErrorAction Stop |
                Out-Null
        }
        Copy-Item -LiteralPath $source -Destination $destination -ErrorAction Stop
    }
    Remove-Item -LiteralPath (Join-Path $staging '.cddsi-release-owner') -Force

    $stagedFiles = @(Get-ChildItem -LiteralPath $staging -File -Recurse |
        ForEach-Object {
            $_.FullName.Substring($staging.Length + 1).Replace('\', '/')
        } | Sort-Object)
    if (($stagedFiles -join "`n") -cne (($package | Sort-Object) -join "`n")) {
        throw 'Staging inventory does not exactly match PackageFiles.'
    }

    New-Item -ItemType Directory -Path $OutputDirectory -Force -ErrorAction Stop |
        Out-Null
    Compress-Archive -Path (Join-Path $staging '*') -DestinationPath $archivePath `
        -CompressionLevel Optimal -ErrorAction Stop

    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $zip = [IO.Compression.ZipFile]::OpenRead($archivePath)
    try {
        $zipFiles = @($zip.Entries |
            Where-Object { -not $_.FullName.EndsWith('/') } |
            ForEach-Object { $_.FullName.Replace('\', '/') } |
            Sort-Object)
    }
    finally {
        $zip.Dispose()
    }
    if (($zipFiles -join "`n") -cne (($package | Sort-Object) -join "`n")) {
        throw 'ZIP inventory does not exactly match PackageFiles.'
    }

    $hash = (Get-FileHash -LiteralPath $archivePath -Algorithm SHA256).Hash.ToLowerInvariant()
    [IO.File]::WriteAllText(
        $hashPath,
        ('{0}  {1}{2}' -f $hash, $archiveName, "`n"),
        (New-Object Text.UTF8Encoding($false))
    )
    [pscustomobject]@{
        Status           = 'SUCCEEDED'
        DryRun           = $false
        ArchivePath      = $archivePath
        ArchiveSha256    = $hash
        PackageFileCount = $package.Count
    }
}
finally {
    if ((Test-Path -LiteralPath $staging -PathType Container) -and
        $staging.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase) -and
        (Split-Path -Leaf $staging) -match '^cddsi-release-[a-f0-9]{32}$') {
        Remove-Item -LiteralPath $staging -Recurse -Force -ErrorAction Stop
    }
}
