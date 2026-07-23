[CmdletBinding()]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Throw-CddsiVendoredPesterFailure {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Reason
    )

    throw ("Vendored Pester verification failed: {0}. Restore the tracked .dev/modules/Pester/5.6.1 tree from a trusted repository checkout. This verifier never downloads or repairs dependencies." -f $Reason)
}

function Get-CddsiVendoredCanonicalPath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $volumeRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::Equals($fullPath.TrimEnd('\'), $volumeRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        return $volumeRoot
    }
    return $fullPath.TrimEnd('\')
}

function Assert-CddsiVendoredExactPropertySet {
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$ContractName
    )

    if ($null -eq $InputObject) {
        Throw-CddsiVendoredPesterFailure -Reason ("{0} is missing" -f $ContractName)
    }
    $actualNames = if ($InputObject -is [System.Collections.IDictionary]) {
        @($InputObject.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    }
    else {
        @($InputObject.PSObject.Properties.Name | Sort-Object)
    }
    $expectedNames = @($Expected | Sort-Object)
    if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) {
        Throw-CddsiVendoredPesterFailure -Reason ("{0} property set drifted" -f $ContractName)
    }
}

function Assert-CddsiVendoredRelativePath {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [string]$ContractName
    )

    $normalized = $RelativePath.Replace('\', '/')
    if ([string]::IsNullOrWhiteSpace($normalized) -or [System.IO.Path]::IsPathRooted($normalized)) {
        Throw-CddsiVendoredPesterFailure -Reason ("{0} must be a repository-relative path" -f $ContractName)
    }
    $segments = @($normalized.Split('/'))
    if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) {
        Throw-CddsiVendoredPesterFailure -Reason ("{0} contains an unsafe path segment" -f $ContractName)
    }
    return $normalized
}

function Assert-CddsiVendoredPathWithinRepository {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Leaf', 'Container')]
        [string]$ExpectedType
    )

    $rootFullPath = Get-CddsiVendoredCanonicalPath -Path $RepositoryRoot
    $targetFullPath = Get-CddsiVendoredCanonicalPath -Path $Path
    $insideRepository = $targetFullPath.StartsWith($rootFullPath + '\', [StringComparison]::OrdinalIgnoreCase)
    if (-not $insideRepository) {
        Throw-CddsiVendoredPesterFailure -Reason 'a dependency path escaped the repository'
    }
    if (-not (Test-Path -LiteralPath $targetFullPath)) {
        Throw-CddsiVendoredPesterFailure -Reason 'a required tracked dependency path is missing'
    }

    $targetItem = Get-Item -LiteralPath $targetFullPath -Force -ErrorAction Stop
    if (($ExpectedType -eq 'Leaf' -and $targetItem.PSIsContainer) -or ($ExpectedType -eq 'Container' -and -not $targetItem.PSIsContainer)) {
        Throw-CddsiVendoredPesterFailure -Reason 'a required tracked dependency path has the wrong type'
    }

    $cursor = $targetFullPath
    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
        if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-CddsiVendoredPesterFailure -Reason 'a dependency path contains a reparse point'
        }
        if ([string]::Equals($cursor, $rootFullPath, [StringComparison]::OrdinalIgnoreCase)) {
            return $targetFullPath
        }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = Get-CddsiVendoredCanonicalPath -Path $parent
    }
    Throw-CddsiVendoredPesterFailure -Reason 'repository ancestry validation did not reach the repository root'
}

function Get-CddsiVendoredTreeFiles {
    param(
        [Parameter(Mandatory = $true)]
        [string]$TreeRoot
    )

    $rootFullPath = Get-CddsiVendoredCanonicalPath -Path $TreeRoot
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($rootFullPath)
    $files = New-Object System.Collections.Generic.List[object]
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force -ErrorAction Stop)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                Throw-CddsiVendoredPesterFailure -Reason 'the vendored dependency tree contains a reparse point'
            }
            if ($item.PSIsContainer) {
                $queue.Enqueue($item.FullName)
            }
            else {
                $relativePath = $item.FullName.Substring($rootFullPath.Length).TrimStart('\').Replace('\', '/')
                $files.Add([pscustomobject][ordered]@{
                    RelativePath = $relativePath
                    File         = $item
                })
            }
        }
    }
    return $files.ToArray()
}

function Get-CddsiVendoredTreeSha256 {
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Files
    )

    $byRelativePath = @{}
    foreach ($entry in @($Files)) {
        if ($byRelativePath.ContainsKey($entry.RelativePath)) {
            Throw-CddsiVendoredPesterFailure -Reason 'the vendored dependency tree contains duplicate relative paths'
        }
        $byRelativePath[$entry.RelativePath] = $entry
    }
    $relativePaths = [string[]]@($byRelativePath.Keys)
    [Array]::Sort($relativePaths, [StringComparer]::Ordinal)
    $treeLines = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in $relativePaths) {
        $entry = $byRelativePath[$relativePath]
        $fileHash = (Get-FileHash -LiteralPath $entry.File.FullName -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
        $treeLines.Add(('{0}|{1}|{2}' -f $relativePath, $fileHash, [long]$entry.File.Length))
    }

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha256.ComputeHash($utf8.GetBytes(($treeLines -join "`n"))))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha256.Dispose()
    }
}

function Assert-CddsiVendoredPesterLock {
    param(
        [Parameter(Mandatory = $true)]
        $DependencyLock
    )

    Assert-CddsiVendoredExactPropertySet -InputObject $DependencyLock -Expected @('SchemaVersion', 'Pester', 'IsolationEvidenceSuites', 'QualityShards') -ContractName 'development dependency lock'
    if (($DependencyLock.SchemaVersion -isnot [int] -and $DependencyLock.SchemaVersion -isnot [long]) -or [long]$DependencyLock.SchemaVersion -ne 1) {
        Throw-CddsiVendoredPesterFailure -Reason 'development dependency schemaVersion must be integer 1'
    }

    $expectedPesterProperties = @(
        'Version', 'ProvenanceStatus', 'RootRelativePath', 'ManifestRelativePath',
        'ExpectedFileCount', 'ExpectedTotalBytes', 'ExpectedManifestSha256', 'ExpectedTreeSha256',
        'LicenseRelativePath', 'ExpectedLicenseBytes', 'ExpectedLicenseSha256',
        'TreeHashFormat', 'OfficialGalleryUrl', 'OfficialProjectUrl', 'OfficialLicenseUrl'
    )
    Assert-CddsiVendoredExactPropertySet -InputObject $DependencyLock.Pester -Expected $expectedPesterProperties -ContractName 'Pester dependency lock'
    $pester = $DependencyLock.Pester
    if ($pester.Version -cne '5.6.1' -or $pester.ProvenanceStatus -cne 'VendoredPinnedTree') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester version or provenance status drifted'
    }
    if ($pester.RootRelativePath -cne '.dev/modules/Pester/5.6.1' -or $pester.ManifestRelativePath -cne 'Pester.psd1') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester repository paths drifted'
    }
    if (($pester.ExpectedFileCount -isnot [int] -and $pester.ExpectedFileCount -isnot [long]) -or [long]$pester.ExpectedFileCount -ne 20) {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester expected file count drifted'
    }
    if (($pester.ExpectedTotalBytes -isnot [int] -and $pester.ExpectedTotalBytes -isnot [long]) -or [long]$pester.ExpectedTotalBytes -ne 1145990) {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester expected byte count drifted'
    }
    if ($pester.ExpectedManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or $pester.ExpectedTreeSha256 -cnotmatch '^[a-f0-9]{64}$') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester SHA-256 values must be lowercase hexadecimal'
    }
    if ($pester.LicenseRelativePath -cne 'third-party/Pester-5.6.1-LICENSE.txt' -or
        ($pester.ExpectedLicenseBytes -isnot [int] -and $pester.ExpectedLicenseBytes -isnot [long]) -or
        [long]$pester.ExpectedLicenseBytes -ne 11357 -or
        $pester.ExpectedLicenseSha256 -cne 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester local license lock drifted'
    }
    if ($pester.ExpectedManifestSha256 -cne '644e3dd029b4f2fdd7b99395446dcd7211d5a1027f51285759c2465e6df671aa' -or
        $pester.ExpectedTreeSha256 -cne 'b4992fea36787bda13b0301e2c459a03910ada99c73fd5b3ed9943470fd84460') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester locked SHA-256 values drifted'
    }
    if ($pester.TreeHashFormat -cne 'ordinal-relative-path|sha256-lower|length joined with LF, UTF-8 without BOM') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester tree hash format drifted'
    }
    if ($pester.OfficialGalleryUrl -cne 'https://www.powershellgallery.com/packages/Pester/5.6.1' -or
        $pester.OfficialProjectUrl -cne 'https://github.com/Pester/Pester' -or
        $pester.OfficialLicenseUrl -cne 'https://www.apache.org/licenses/LICENSE-2.0.html') {
        Throw-CddsiVendoredPesterFailure -Reason 'Pester provenance URLs drifted'
    }
    return $pester
}

function Assert-CddsiVendoredPesterTree {
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        $DependencyLock
    )

    $pester = Assert-CddsiVendoredPesterLock -DependencyLock $DependencyLock
    $rootRelativePath = Assert-CddsiVendoredRelativePath -RelativePath $pester.RootRelativePath -ContractName 'Pester.RootRelativePath'
    $manifestRelativePath = Assert-CddsiVendoredRelativePath -RelativePath $pester.ManifestRelativePath -ContractName 'Pester.ManifestRelativePath'
    $repositoryFullPath = Get-CddsiVendoredCanonicalPath -Path $RepositoryRoot
    $dependencyRoot = Get-CddsiVendoredCanonicalPath -Path (Join-Path $repositoryFullPath $rootRelativePath)
    $null = Assert-CddsiVendoredPathWithinRepository -RepositoryRoot $repositoryFullPath -Path $dependencyRoot -ExpectedType Container

    $files = @(Get-CddsiVendoredTreeFiles -TreeRoot $dependencyRoot)
    if ($files.Count -ne [int]$pester.ExpectedFileCount) {
        Throw-CddsiVendoredPesterFailure -Reason 'the vendored Pester file count does not match the lock'
    }
    $totalBytes = [long]0
    foreach ($entry in $files) { $totalBytes += [long]$entry.File.Length }
    if ($totalBytes -ne [long]$pester.ExpectedTotalBytes) {
        Throw-CddsiVendoredPesterFailure -Reason 'the vendored Pester byte count does not match the lock'
    }

    try {
        $treeSha256 = Get-CddsiVendoredTreeSha256 -Files $files
    }
    catch {
        Throw-CddsiVendoredPesterFailure -Reason 'the vendored Pester tree could not be hashed safely'
    }
    if ($treeSha256 -cne $pester.ExpectedTreeSha256) {
        Throw-CddsiVendoredPesterFailure -Reason 'the vendored Pester tree SHA-256 does not match the lock'
    }

    $manifestPath = Get-CddsiVendoredCanonicalPath -Path (Join-Path $dependencyRoot $manifestRelativePath)
    $null = Assert-CddsiVendoredPathWithinRepository -RepositoryRoot $repositoryFullPath -Path $manifestPath -ExpectedType Leaf
    try {
        $manifestSha256 = (Get-FileHash -LiteralPath $manifestPath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    }
    catch {
        Throw-CddsiVendoredPesterFailure -Reason 'the vendored Pester manifest could not be hashed safely'
    }
    if ($manifestSha256 -cne $pester.ExpectedManifestSha256) {
        Throw-CddsiVendoredPesterFailure -Reason 'the vendored Pester manifest SHA-256 does not match the lock'
    }

    $licenseRelativePath = Assert-CddsiVendoredRelativePath -RelativePath $pester.LicenseRelativePath -ContractName 'Pester.LicenseRelativePath'
    $licensePath = Get-CddsiVendoredCanonicalPath -Path (Join-Path $repositoryFullPath $licenseRelativePath)
    $null = Assert-CddsiVendoredPathWithinRepository -RepositoryRoot $repositoryFullPath -Path $licensePath -ExpectedType Leaf
    $licenseItem = Get-Item -LiteralPath $licensePath -Force -ErrorAction Stop
    if ([long]$licenseItem.Length -ne [long]$pester.ExpectedLicenseBytes) {
        Throw-CddsiVendoredPesterFailure -Reason 'the Pester license byte count does not match the lock'
    }
    $licenseSha256 = (Get-FileHash -LiteralPath $licensePath -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
    if ($licenseSha256 -cne $pester.ExpectedLicenseSha256) {
        Throw-CddsiVendoredPesterFailure -Reason 'the Pester license SHA-256 does not match the lock'
    }

    return [pscustomobject][ordered]@{
        Dependency       = 'Pester'
        Version          = $pester.Version
        ProvenanceStatus = $pester.ProvenanceStatus
        RootRelativePath = $rootRelativePath
        FileCount        = $files.Count
        TotalBytes       = $totalBytes
        ManifestSha256   = $manifestSha256
        TreeSha256       = $treeSha256
        LicenseSha256    = $licenseSha256
    }
}

$repositoryRoot = Get-CddsiVendoredCanonicalPath -Path (Split-Path -Parent $PSScriptRoot)
$dependencyManifestPath = Join-Path $repositoryRoot 'config\dev-dependencies.psd1'
$null = Assert-CddsiVendoredPathWithinRepository -RepositoryRoot $repositoryRoot -Path $dependencyManifestPath -ExpectedType Leaf
$dependencyLock = Import-PowerShellDataFile -LiteralPath $dependencyManifestPath -ErrorAction Stop
$verification = Assert-CddsiVendoredPesterTree -RepositoryRoot $repositoryRoot -DependencyLock $dependencyLock
Write-Host ("[bootstrap-dev] Verified vendored Pester {0}: {1} files, {2} bytes, tree SHA-256 {3}." -f $verification.Version, $verification.FileCount, $verification.TotalBytes, $verification.TreeSha256)
