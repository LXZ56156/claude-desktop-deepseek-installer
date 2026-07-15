[CmdletBinding()]
param(
    [switch]$DryRun,
    [string]$OutputDirectory,
    [switch]$SkipQualityGate,
    [switch]$ImportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$entryDryRun = $DryRun.IsPresent
$entryImportOnly = $ImportOnly.IsPresent
$entryOutputDirectorySpecified = $PSBoundParameters.ContainsKey('OutputDirectory')
$entrySkipQualityGate = $SkipQualityGate.IsPresent
$root = Split-Path -Parent $PSScriptRoot
$manifestPath = Join-Path $PSScriptRoot 'release-manifest.psd1'

# Reuse the single P1 owner-marker and cleanup implementation. ImportOnly
# defines trusted-harness helpers without running its quality scenario.
. (Join-Path $PSScriptRoot 'invoke-host-sandbox.ps1') -ImportOnly

$script:CddsiReleaseSecretScanChunkBytes = 64KB
$script:CddsiReleaseSecretScanOverlapBytes = 4KB

function ConvertTo-CddsiReleaseRelativePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path)) {
        throw 'Release manifest paths must not be empty.'
    }
    if ([System.IO.Path]::IsPathRooted($Path) -or $Path.IndexOf([char]0) -ge 0) {
        throw 'Release manifest paths must be relative.'
    }
    if ($Path.Contains('\') -or $Path.StartsWith('/', [StringComparison]::Ordinal) -or
        $Path.EndsWith('/', [StringComparison]::Ordinal) -or $Path.Contains('//')) {
        throw 'Release manifest paths must use canonical forward-slash form.'
    }
    if ($Path.IndexOfAny([char[]]':*?"<>|') -ge 0) {
        throw 'Release manifest paths contain a forbidden Windows path character.'
    }

    $segments = @($Path.Split('/'))
    foreach ($segment in $segments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -ceq '.' -or $segment -ceq '..') {
            throw 'Release manifest paths contain an unsafe path segment.'
        }
        if ($segment.IndexOfAny([System.IO.Path]::GetInvalidFileNameChars()) -ge 0) {
            throw 'Release manifest paths contain an invalid file-name character.'
        }
        if ($segment.EndsWith('.', [StringComparison]::Ordinal) -or
            $segment.EndsWith(' ', [StringComparison]::Ordinal)) {
            throw 'Release manifest paths contain a Windows-normalized alias.'
        }
        $deviceBase = @($segment.Split('.'))[0].TrimEnd([char[]]' .')
        if ($deviceBase -match '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|COM(?:[1-9]|\u00b9|\u00b2|\u00b3)|LPT(?:[1-9]|\u00b9|\u00b2|\u00b3))$') {
            throw 'Release manifest paths contain a reserved Windows device name.'
        }
    }
    return $Path
}

function Assert-CddsiReleaseExactSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    $expectedSorted = @($Expected | Sort-Object)
    $actualSorted = @($Actual | Sort-Object)
    if ($expectedSorted.Count -ne $actualSorted.Count -or
        ($expectedSorted -join "`n") -cne ($actualSorted -join "`n")) {
        throw ("{0} differs from the exact release allow-list." -f $Label)
    }
}

function Add-CddsiReleaseFileLedgerEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Ledger,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [string]$RuleId,

        [Parameter(Mandatory = $true)]
        [string]$ResourceToken,

        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2147483647)]
        [int]$ItemCount
    )

    Add-CddsiHarnessLedgerEntry `
        -Ledger $Ledger `
        -RunId $RunId `
        -Category FileSystem `
        -RuleId $RuleId `
        -ResourceToken $ResourceToken `
        -Outcome Succeeded `
        -Data ([pscustomobject][ordered]@{ ItemCount = $ItemCount })
}

function Assert-CddsiReleaseLedgerSequence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [System.Collections.Generic.List[object]]$Ledger,

        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [object[]]$Expected,

        [Parameter(Mandatory = $true)]
        [string]$OwnershipToken
    )

    if ($Ledger.Count -ne $Expected.Count) {
        throw 'Release simulation harness ledger count differs from the exact contract.'
    }
    for ($index = 0; $index -lt $Expected.Count; $index++) {
        $entry = $Ledger[$index]
        $contract = $Expected[$index]
        Assert-CddsiReleaseExactSet `
            -Expected @('SchemaVersion', 'Sequence', 'RunId', 'Plane', 'Category', 'RuleId', 'ResourceToken', 'Outcome', 'Data') `
            -Actual @($entry.PSObject.Properties.Name) `
            -Label 'Release simulation harness ledger entry schema'
        if ($entry.SchemaVersion -isnot [int] -or $entry.SchemaVersion -ne 1 -or
            $entry.Sequence -isnot [int] -or $entry.Sequence -ne ($index + 1) -or
            $entry.RunId -isnot [string] -or
            $entry.RunId -cne $RunId -or
            $entry.Plane -isnot [string] -or
            $entry.Plane -cne 'TrustedHarness' -or
            $entry.Category -isnot [string] -or
            $entry.Category -cne 'FileSystem' -or
            $entry.RuleId -isnot [string] -or
            $entry.RuleId -cne $contract.RuleId -or
            $entry.ResourceToken -isnot [string] -or
            $entry.ResourceToken -cne $contract.ResourceToken -or
            $entry.Outcome -isnot [string] -or
            $entry.Outcome -cne 'Succeeded') {
            throw 'Release simulation harness ledger sequence or contract drifted.'
        }
        if ($null -eq $contract.Data) {
            if ($null -ne $entry.Data) {
                throw 'Release simulation harness ledger data must be null for this rule.'
            }
        }
        else {
            if ($null -eq $entry.Data -or $entry.Data -isnot [pscustomobject]) {
                throw 'Release simulation harness ledger data type drifted.'
            }
            Assert-CddsiReleaseExactSet `
                -Expected @($contract.Data.PSObject.Properties.Name) `
                -Actual @($entry.Data.PSObject.Properties.Name) `
                -Label 'Release simulation harness ledger data schema'
            foreach ($property in @($contract.Data.PSObject.Properties)) {
                $actualValue = $entry.Data.($property.Name)
                if ($actualValue.GetType() -ne $property.Value.GetType() -or $actualValue -ne $property.Value) {
                    throw 'Release simulation harness ledger data value or type drifted.'
                }
            }
        }
        $dataText = if ($null -eq $entry.Data) { 'null' } else { $entry.Data | ConvertTo-Json -Compress -Depth 5 }
        if ($dataText -match '(?i)(?:[a-z]:\\|\\\\)' -or
            (-not [string]::IsNullOrWhiteSpace($OwnershipToken) -and $dataText.Contains($OwnershipToken))) {
            throw 'Release simulation harness ledger contains an absolute path or ownership token.'
        }
    }
}

function New-CddsiReleaseLedgerContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$PackageFileCount,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$RepositoryItemCountBefore,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 2147483647)]
        [int]$RepositoryItemCountAfter,

        [switch]$IncludeCleanup
    )

    $contract = New-Object System.Collections.Generic.List[object]
    $contract.Add([pscustomobject]@{ RuleId = 'CreateSandbox'; ResourceToken = '<SANDBOX_ROOT>'; Data = $null })
    $contract.Add([pscustomobject]@{ RuleId = 'WriteOwnerMarker'; ResourceToken = '<SANDBOX_ROOT>/.cddsi-owner.json'; Data = $null })
    $contract.Add([pscustomobject]@{ RuleId = 'CreateSyntheticEnvironment'; ResourceToken = '<SANDBOX_ROOT>/synthetic'; Data = [pscustomobject][ordered]@{ CanaryFileCount = 5 } })
    $contract.Add([pscustomobject]@{ RuleId = 'ReleaseRepositorySnapshotBefore'; ResourceToken = '<REPOSITORY_ROOT>/<WORKING_TREE>'; Data = (New-CddsiReleaseItemCountData -Count $RepositoryItemCountBefore) })
    $contract.Add([pscustomobject]@{ RuleId = 'ReleaseManifestRead'; ResourceToken = '<REPOSITORY_ROOT>/<RELEASE_MANIFEST>'; Data = (New-CddsiReleaseItemCountData -Count 1) })
    foreach ($rule in @(
        @{ RuleId = 'ReleaseSourceRead'; ResourceToken = '<REPOSITORY_ROOT>/<PACKAGE_ALLOW_LIST>' }
        @{ RuleId = 'ReleaseSourceSecretScan'; ResourceToken = '<REPOSITORY_ROOT>/<PACKAGE_ALLOW_LIST>' }
        @{ RuleId = 'ReleaseStageCreateCopy'; ResourceToken = '<SANDBOX_ROOT>/<RELEASE_STAGE>' }
        @{ RuleId = 'ReleaseStageRead'; ResourceToken = '<SANDBOX_ROOT>/<RELEASE_STAGE>' }
        @{ RuleId = 'ReleaseZipCreate'; ResourceToken = '<SANDBOX_ROOT>/<RELEASE_ZIP>' }
        @{ RuleId = 'ReleaseZipRead'; ResourceToken = '<SANDBOX_ROOT>/<RELEASE_ZIP>' }
        @{ RuleId = 'ReleaseExtractCreate'; ResourceToken = '<SANDBOX_ROOT>/<RELEASE_EXTRACT>' }
        @{ RuleId = 'ReleaseExtractRead'; ResourceToken = '<SANDBOX_ROOT>/<RELEASE_EXTRACT>' }
        @{ RuleId = 'ReleaseSourceRefingerprint'; ResourceToken = '<REPOSITORY_ROOT>/<PACKAGE_ALLOW_LIST>' }
    )) {
        $contract.Add([pscustomobject]@{ RuleId = $rule.RuleId; ResourceToken = $rule.ResourceToken; Data = (New-CddsiReleaseItemCountData -Count $PackageFileCount) })
    }
    $contract.Add([pscustomobject]@{ RuleId = 'ReleaseRepositorySnapshotAfter'; ResourceToken = '<REPOSITORY_ROOT>/<WORKING_TREE>'; Data = (New-CddsiReleaseItemCountData -Count $RepositoryItemCountAfter) })
    if ($IncludeCleanup) {
        $contract.Add([pscustomobject]@{ RuleId = 'CleanupSandbox'; ResourceToken = '<SANDBOX_ROOT>'; Data = $null })
    }
    return $contract.ToArray()
}

function New-CddsiReleaseItemCountData {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateRange(0, 2147483647)]
        [int]$Count
    )

    return [pscustomobject][ordered]@{ ItemCount = $Count }
}

function Get-CddsiReleaseManifestContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath
    )

    $repositoryFull = Get-CddsiCanonicalPath -Path $RepositoryRoot
    if (-not (Test-Path -LiteralPath $repositoryFull -PathType Container)) {
        throw 'Release repository root is unavailable.'
    }
    Assert-CddsiNoReparsePath -Path $repositoryFull -StopRoot ([System.IO.Path]::GetPathRoot($repositoryFull))

    $manifestFull = Get-CddsiCanonicalPath -Path $ManifestPath
    if (-not (Test-CddsiPathWithinRoot -Path $manifestFull -Root $repositoryFull)) {
        throw 'Release manifest path escapes the repository root.'
    }
    if (-not (Test-Path -LiteralPath $manifestFull -PathType Leaf)) {
        throw 'Release manifest is unavailable.'
    }
    Assert-CddsiNoReparsePath -Path $manifestFull -StopRoot $repositoryFull

    $manifest = Import-PowerShellDataFile -LiteralPath $manifestFull
    Assert-CddsiReleaseExactSet `
        -Expected @('SchemaVersion', 'PackageFiles', 'DevelopmentOnlyFiles') `
        -Actual @($manifest.Keys | ForEach-Object { [string]$_ }) `
        -Label 'Release manifest schema'
    if ($manifest.SchemaVersion -ne 1) {
        throw 'Unsupported release manifest schema.'
    }
    if ($manifest.PackageFiles -isnot [System.Array] -or
        $manifest.DevelopmentOnlyFiles -isnot [System.Array]) {
        throw 'Release manifest file classifications must be arrays.'
    }

    $packageFiles = @($manifest.PackageFiles | ForEach-Object {
        ConvertTo-CddsiReleaseRelativePath -Path ([string]$_)
    })
    $developmentFiles = @($manifest.DevelopmentOnlyFiles | ForEach-Object {
        ConvertTo-CddsiReleaseRelativePath -Path ([string]$_)
    })
    if ($packageFiles.Count -eq 0) {
        throw 'Release package allow-list must not be empty.'
    }

    $classified = @($packageFiles + $developmentFiles)
    $duplicates = @($classified | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) {
        throw 'Release manifest entries must be unique and disjoint.'
    }

    return [pscustomobject][ordered]@{
        RepositoryRoot      = $repositoryFull
        ManifestPath        = $manifestFull
        PackageFiles        = $packageFiles
        DevelopmentOnlyFiles = $developmentFiles
    }
}

function Get-CddsiReleasePackageItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string[]]$PackageFiles
    )

    $items = New-Object System.Collections.Generic.List[object]
    foreach ($relative in $PackageFiles) {
        $canonicalRelative = ConvertTo-CddsiReleaseRelativePath -Path $relative
        $fullPath = Get-CddsiCanonicalPath -Path (Join-Path $RepositoryRoot ($canonicalRelative.Replace('/', '\')))
        if (-not (Test-CddsiPathWithinRoot -Path $fullPath -Root $RepositoryRoot)) {
            throw 'Release package path escapes the repository root.'
        }
        if (-not [System.IO.File]::Exists($fullPath)) {
            throw ("Package allow-list entry is missing: {0}" -f $canonicalRelative)
        }
        Assert-CddsiNoReparsePath -Path $fullPath -StopRoot $RepositoryRoot
        $items.Add([pscustomobject][ordered]@{
            RelativePath = $canonicalRelative
            FullPath     = $fullPath
        })
    }
    return $items.ToArray()
}

function Find-CddsiReleaseSecretFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Staging', 'ZIP', 'Extracted')]
        [string]$Layer
    )

    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $patterns = @(
        [pscustomobject]@{ Type = 'DeepSeekLikeKey'; Regex = '(?i)(?<![a-z0-9_-])sk-[a-z0-9_-]{20,}(?![a-z0-9_-])' }
        [pscustomobject]@{ Type = 'BearerToken'; Regex = '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])' }
        [pscustomobject]@{ Type = 'CredentialAssignment'; Regex = '(?i)"?(api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}' }
        [pscustomobject]@{ Type = 'PrivateKey'; Regex = ('(?i)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----') }
    )
    $findings = New-Object System.Collections.Generic.List[object]
    $lines = @($Content -split "`r?`n", 0)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        foreach ($pattern in $patterns) {
            if ([regex]::IsMatch($lines[$index], $pattern.Regex)) {
                $findings.Add([pscustomobject][ordered]@{
                    Layer        = $Layer
                    RelativePath = $RelativePath
                    Line         = $index + 1
                    Type         = $pattern.Type
                })
            }
        }
    }
    return $findings.ToArray()
}

function Find-CddsiReleaseStreamSecretFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.Stream]$Stream,

        [Parameter(Mandatory = $true)]
        [string]$RelativePath,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Staging', 'ZIP', 'Extracted')]
        [string]$Layer
    )

    if (-not $Stream.CanRead) {
        throw 'Release secret scan stream is not readable.'
    }
    $buffer = New-Object byte[] $script:CddsiReleaseSecretScanChunkBytes
    $carry = New-Object byte[] 0
    $findings = New-Object System.Collections.Generic.List[object]
    $seenTypes = @{}
    $singleByteEncoding = [System.Text.Encoding]::GetEncoding(28591)
    while (($read = $Stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
        $window = New-Object byte[] ($carry.Length + $read)
        if ($carry.Length -gt 0) {
            [Array]::Copy($carry, 0, $window, 0, $carry.Length)
        }
        [Array]::Copy($buffer, 0, $window, $carry.Length, $read)
        $content = $singleByteEncoding.GetString($window)
        foreach ($finding in @(Find-CddsiReleaseSecretFindings -Content $content -RelativePath $RelativePath -Layer $Layer)) {
            if (-not $seenTypes.ContainsKey($finding.Type)) {
                $seenTypes[$finding.Type] = $true
                $findings.Add([pscustomobject][ordered]@{
                    Layer        = $Layer
                    RelativePath = $RelativePath
                    Line         = 0
                    Type         = $finding.Type
                })
            }
        }

        $carryLength = [Math]::Min($script:CddsiReleaseSecretScanOverlapBytes, $window.Length)
        $carry = New-Object byte[] $carryLength
        if ($carryLength -gt 0) {
            [Array]::Copy($window, $window.Length - $carryLength, $carry, 0, $carryLength)
        }
    }
    return $findings.ToArray()
}

function Assert-CddsiReleaseNoSecretFindings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$Findings,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Staging', 'ZIP', 'Extracted')]
        [string]$Layer
    )

    if ($Findings.Count -gt 0) {
        $safe = @($Findings | ForEach-Object {
            '{0}:{1}:{2}' -f $_.RelativePath, $_.Line, $_.Type
        }) -join ', '
        throw ("Release {0} secret scan failed: {1}" -f $Layer, $safe)
    }
}

function Invoke-CddsiReleaseFileSecretScan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Source', 'Staging', 'Extracted')]
        [string]$Layer
    )

    $findings = New-Object System.Collections.Generic.List[object]
    foreach ($item in $Items) {
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($item.FullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            foreach ($finding in @(Find-CddsiReleaseStreamSecretFindings -Stream $stream -RelativePath $item.RelativePath -Layer $Layer)) {
                $findings.Add($finding)
            }
        }
        finally {
            if ($null -ne $stream) { $stream.Dispose() }
        }
    }
    Assert-CddsiReleaseNoSecretFindings -Findings $findings.ToArray() -Layer $Layer
    return 0
}

function Get-CddsiReleaseContentHashes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items
    )

    $fingerprint = [ordered]@{}
    foreach ($item in $Items) {
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $stream = $null
        try {
            $stream = [System.IO.File]::Open($item.FullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            $fingerprint[$item.RelativePath] = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
        }
        finally {
            if ($null -ne $stream) { $stream.Dispose() }
            $sha.Dispose()
        }
    }
    return ,$fingerprint
}

function Assert-CddsiReleaseContentHashesEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Expected,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Actual,

        [Parameter(Mandatory = $true)]
        [string]$Label
    )

    Assert-CddsiReleaseExactSet `
        -Expected @($Expected.Keys | ForEach-Object { [string]$_ }) `
        -Actual @($Actual.Keys | ForEach-Object { [string]$_ }) `
        -Label ($Label + ' hash keys')
    foreach ($relative in $Expected.Keys) {
        if ([string]$Expected[$relative] -cne [string]$Actual[$relative]) {
            throw ("{0} content hash differs for: {1}" -f $Label, $relative)
        }
    }
}

function Get-CddsiReleaseRepositorySnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot
    )

    $rootFull = Get-CddsiCanonicalPath -Path $RepositoryRoot
    if (-not (Test-Path -LiteralPath $rootFull -PathType Container)) {
        throw 'Release repository snapshot root is unavailable.'
    }
    Assert-CddsiNoReparsePath -Path $rootFull -StopRoot ([System.IO.Path]::GetPathRoot($rootFull))

    $rawEntries = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($rootFull)
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            $canonical = Get-CddsiCanonicalPath -Path $item.FullName
            if (-not (Test-CddsiPathWithinRoot -Path $canonical -Root $rootFull)) {
                throw 'Release repository snapshot enumeration escaped its root.'
            }
            $relative = $canonical.Substring($rootFull.TrimEnd('\').Length).TrimStart([char[]]'\/').Replace('\', '/')
            if ($relative -ieq '.git' -or $relative.StartsWith('.git/', [StringComparison]::OrdinalIgnoreCase)) {
                continue
            }
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Release repository snapshot contains a reparse point.'
            }
            $canonicalRelative = ConvertTo-CddsiReleaseRelativePath -Path $relative
            if ($item.PSIsContainer) {
                $rawEntries.Add([pscustomobject][ordered]@{
                    Key   = 'D:' + $canonicalRelative
                    Value = 'Directory'
                    Kind  = 'Directory'
                })
                $queue.Enqueue($canonical)
                continue
            }

            $sha = [System.Security.Cryptography.SHA256]::Create()
            $stream = $null
            try {
                $stream = [System.IO.File]::Open($canonical, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
            }
            finally {
                if ($null -ne $stream) { $stream.Dispose() }
                $sha.Dispose()
            }
            $rawEntries.Add([pscustomobject][ordered]@{
                Key   = 'F:' + $canonicalRelative
                Value = $hash
                Kind  = 'File'
            })
        }
    }

    $entries = [ordered]@{}
    foreach ($entry in @($rawEntries | Sort-Object Key)) {
        $entries[$entry.Key] = $entry.Value
    }
    return [pscustomobject][ordered]@{
        Entries        = $entries
        FileCount      = @($rawEntries | Where-Object Kind -eq 'File').Count
        DirectoryCount = @($rawEntries | Where-Object Kind -eq 'Directory').Count
        ItemCount      = $rawEntries.Count
    }
}

function Test-CddsiReleaseRepositorySnapshotsEqual {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Before,
        [Parameter(Mandatory = $true)]$After
    )

    $beforeKeys = @($Before.Entries.Keys | ForEach-Object { [string]$_ })
    $afterKeys = @($After.Entries.Keys | ForEach-Object { [string]$_ })
    $beforeSorted = @($beforeKeys | Sort-Object)
    $afterSorted = @($afterKeys | Sort-Object)
    if ($beforeSorted.Count -ne $afterSorted.Count -or
        ($beforeSorted -join "`n") -cne ($afterSorted -join "`n")) {
        return $false
    }
    foreach ($key in $beforeSorted) {
        if ([string]$Before.Entries[$key] -cne [string]$After.Entries[$key]) {
            return $false
        }
    }
    return $true
}

function Protect-CddsiReleaseFailureText {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$TempRoot,
        [AllowNull()][string]$OwnershipToken
    )

    if ($null -eq $Text) { return '' }
    $safe = [regex]::Replace($Text, '\x1b\][^\x07\x1b]*(?:\x07|\x1b\\)', '')
    $safe = [regex]::Replace($safe, '\x1b\[[0-?]*[ -/]*[@-~]', '')
    $safe = [regex]::Replace($safe, '[\x00-\x1f\x7f-\x9f]', '')
    $safe = [regex]::Replace($safe, '[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]', '')
    $pathTokens = [ordered]@{
        '<REPOSITORY_ROOT>' = $RepositoryRoot
        '<TEMP_ROOT>'       = $TempRoot
    }
    $safe = Protect-CddsiHarnessText -Text $safe -PathTokens $pathTokens -OwnershipToken $OwnershipToken
    if ($safe.Length -gt 2000) { $safe = $safe.Substring(0, 2000) }
    return $safe
}

function New-CddsiReleaseFailureEnvelope {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PrimaryError,
        [Parameter(Mandatory = $true)][ValidateSet('NotStarted', 'Succeeded', 'Failed')][string]$CleanupOutcome,
        [AllowNull()][string]$CleanupError,
        [AllowNull()]$RepositoryContentChanged,
        [Parameter(Mandatory = $true)][ValidateSet('Compared', 'NotAvailable')][string]$RepositoryComparisonOutcome,
        [Parameter(Mandatory = $true)][ValidateRange(0, 2147483647)][int]$HarnessLedgerCount
    )

    return [pscustomobject][ordered]@{
        SchemaVersion               = 1
        Operation                   = 'ReleaseSimulation'
        Status                      = 'FAILED'
        PrimaryError                = $PrimaryError
        CleanupOutcome              = $CleanupOutcome
        CleanupError                = $CleanupError
        RepositoryContentChanged    = $RepositoryContentChanged
        RepositoryComparisonOutcome = $RepositoryComparisonOutcome
        HarnessLedgerCount          = $HarnessLedgerCount
    }
}

function Copy-CddsiReleasePackageItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [object[]]$Items,

        [Parameter(Mandatory = $true)]
        [string]$StagingRoot,

        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot
    )

    if (-not (Test-CddsiPathWithinRoot -Path $StagingRoot -Root $SandboxRoot)) {
        throw 'Release staging root escapes the owned sandbox.'
    }
    if (Test-Path -LiteralPath $StagingRoot) {
        throw 'Release staging root must not already exist.'
    }
    [void][System.IO.Directory]::CreateDirectory($StagingRoot)
    Assert-CddsiNoReparsePath -Path $StagingRoot -StopRoot $SandboxRoot

    foreach ($item in $Items) {
        $destination = Get-CddsiCanonicalPath -Path (Join-Path $StagingRoot ($item.RelativePath.Replace('/', '\')))
        if (-not (Test-CddsiPathWithinRoot -Path $destination -Root $StagingRoot)) {
            throw 'Release staging destination escapes the staging root.'
        }
        $parent = Split-Path -Parent $destination
        [void][System.IO.Directory]::CreateDirectory($parent)
        Assert-CddsiNoReparsePath -Path $parent -StopRoot $SandboxRoot

        $sourceStream = [System.IO.File]::Open($item.FullPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $destinationStream = $null
        try {
            $destinationStream = [System.IO.File]::Open($destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
            $sourceStream.CopyTo($destinationStream)
            $destinationStream.Flush()
        }
        finally {
            if ($null -ne $destinationStream) { $destinationStream.Dispose() }
            $sourceStream.Dispose()
        }
    }
}

function Get-CddsiReleaseTreeItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TreeRoot,

        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot
    )

    if (-not (Test-CddsiPathWithinRoot -Path $TreeRoot -Root $SandboxRoot) -or
        -not (Test-Path -LiteralPath $TreeRoot -PathType Container)) {
        throw 'Release simulation tree is unavailable or outside the sandbox.'
    }
    Assert-CddsiNoReparsePath -Path $TreeRoot -StopRoot $SandboxRoot

    $items = New-Object System.Collections.Generic.List[object]
    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue((Get-CddsiCanonicalPath -Path $TreeRoot))
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Release simulation tree contains a reparse point.'
            }
            $canonical = Get-CddsiCanonicalPath -Path $item.FullName
            if (-not (Test-CddsiPathWithinRoot -Path $canonical -Root $TreeRoot)) {
                throw 'Release simulation tree enumeration escaped its root.'
            }
            if ($item.PSIsContainer) {
                $queue.Enqueue($canonical)
                continue
            }
            $relative = $canonical.Substring($TreeRoot.TrimEnd('\').Length).TrimStart([char[]]'\/').Replace('\', '/')
            $items.Add([pscustomobject][ordered]@{
                RelativePath = ConvertTo-CddsiReleaseRelativePath -Path $relative
                FullPath     = $canonical
            })
        }
    }
    return $items.ToArray()
}

function Initialize-CddsiReleaseCompression {
    [CmdletBinding()]
    param()

    if ($null -eq ('System.IO.Compression.ZipArchive' -as [type])) {
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    }
    if ($null -eq ('System.IO.Compression.ZipArchive' -as [type])) {
        throw 'ZIP support is unavailable.'
    }
}

function Write-CddsiReleaseZipUInt16 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.BinaryWriter]$Writer,

        [Parameter(Mandatory = $true)]
        [long]$Value,

        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    if ($Value -lt 0 -or $Value -gt [uint16]::MaxValue) {
        throw ("Release ZIP32 {0} exceeds the unsigned 16-bit boundary." -f $FieldName)
    }
    $bytes = New-Object byte[] 2
    $bytes[0] = [byte]($Value -band 0xFF)
    $bytes[1] = [byte](($Value -shr 8) -band 0xFF)
    [void]$Writer.Write([byte[]]$bytes)
}

function Write-CddsiReleaseZipUInt32 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.IO.BinaryWriter]$Writer,

        [Parameter(Mandatory = $true)]
        [long]$Value,

        [Parameter(Mandatory = $true)]
        [string]$FieldName
    )

    if ($Value -lt 0 -or [uint64]$Value -gt [uint64][uint32]::MaxValue) {
        throw ("Release ZIP32 {0} exceeds the unsigned 32-bit boundary." -f $FieldName)
    }
    $bytes = New-Object byte[] 4
    $bytes[0] = [byte]($Value -band 0xFF)
    $bytes[1] = [byte](($Value -shr 8) -band 0xFF)
    $bytes[2] = [byte](($Value -shr 16) -band 0xFF)
    $bytes[3] = [byte](($Value -shr 24) -band 0xFF)
    [void]$Writer.Write([byte[]]$bytes)
}

function New-CddsiReleaseSimulationZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$StagingRoot,

        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string[]]$PackageFiles,

        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot
    )

    Initialize-CddsiReleaseCompression
    if (-not (Test-CddsiPathWithinRoot -Path $StagingRoot -Root $SandboxRoot) -or
        -not (Test-CddsiPathWithinRoot -Path $ZipPath -Root $SandboxRoot)) {
        throw 'Release ZIP inputs escape the owned sandbox.'
    }
    if (Test-Path -LiteralPath $ZipPath) {
        throw 'Release simulation ZIP must not already exist.'
    }

    $zipParent = Split-Path -Parent $ZipPath
    [void][System.IO.Directory]::CreateDirectory($zipParent)
    Assert-CddsiNoReparsePath -Path $zipParent -StopRoot $SandboxRoot

    $packageFileCount = @($PackageFiles).Count
    if ($packageFileCount -eq 0 -or $packageFileCount -gt 65534) {
        throw 'Release ZIP32 entry count must be between 1 and 65534; 65535 is reserved as a ZIP64 sentinel.'
    }
    $orderedPackageFiles = [string[]]@($PackageFiles | ForEach-Object {
        ConvertTo-CddsiReleaseRelativePath -Path ([string]$_)
    })
    if ($orderedPackageFiles.Count -ne $packageFileCount) {
        throw 'Release ZIP32 canonical entry count drifted.'
    }
    $entryNames = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    foreach ($relative in $orderedPackageFiles) {
        if (-not $entryNames.Add($relative)) {
            throw 'Release ZIP32 entry names must be ordinal-unique.'
        }
    }
    [Array]::Sort($orderedPackageFiles, [StringComparer]::Ordinal)

    $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
    $uint32Maximum = [uint64][uint32]::MaxValue
    $zip32FieldMaximum = $uint32Maximum - [uint64]1
    $crc32Polynomial = [uint64][Convert]::ToUInt32('EDB88320', 16)
    $crc32Table = New-Object 'System.UInt32[]' 256
    for ($tableIndex = 0; $tableIndex -lt $crc32Table.Length; $tableIndex++) {
        [uint64]$tableValue = [uint64]$tableIndex
        for ($bitIndex = 0; $bitIndex -lt 8; $bitIndex++) {
            if (($tableValue -band [uint64]1) -ne 0) {
                $tableValue = (($tableValue -shr 1) -bxor $crc32Polynomial) -band $uint32Maximum
            }
            else {
                $tableValue = ($tableValue -shr 1) -band $uint32Maximum
            }
        }
        $crc32Table[$tableIndex] = [uint32]$tableValue
    }

    $localHeaderSignature = [long][Convert]::ToUInt32('04034B50', 16)
    $centralHeaderSignature = [long][Convert]::ToUInt32('02014B50', 16)
    $endOfCentralDirectorySignature = [long][Convert]::ToUInt32('06054B50', 16)
    $versionNeeded = 20
    $utf8Flag = 0x0800
    $storeMethod = 0
    $fixedDosTime = 0
    $fixedDosDate = 0x0021
    $buffer = New-Object byte[] 65536
    $centralRecords = [System.Collections.Generic.List[object]]::new()

    $zipStream = $null
    $writer = $null
    $creationError = $null
    try {
        $zipStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $writer = [System.IO.BinaryWriter]::new($zipStream, $utf8, $true)
        foreach ($canonicalRelative in $orderedPackageFiles) {
            $sourcePath = Get-CddsiCanonicalPath -Path (Join-Path $StagingRoot ($canonicalRelative.Replace('/', '\')))
            if (-not (Test-CddsiPathWithinRoot -Path $sourcePath -Root $StagingRoot) -or
                -not [System.IO.File]::Exists($sourcePath)) {
                throw 'Release ZIP source is missing or outside staging.'
            }
            Assert-CddsiNoReparsePath -Path $sourcePath -StopRoot $SandboxRoot
            $nameBytes = [byte[]]$utf8.GetBytes($canonicalRelative)
            if ($nameBytes.Length -eq 0 -or $nameBytes.Length -gt [uint16]::MaxValue) {
                throw 'Release ZIP32 UTF-8 entry name length is invalid.'
            }

            $sourceStream = $null
            try {
                $sourceStream = [System.IO.File]::Open($sourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
                $contentLength = [long]$sourceStream.Length
                if ($contentLength -lt 0 -or [uint64]$contentLength -gt $zip32FieldMaximum) {
                    throw 'Release ZIP32 entry content reaches the ZIP64 size sentinel.'
                }
                $localHeaderOffset = [long]$zipStream.Position
                $projectedDataEnd = [uint64]$localHeaderOffset + [uint64]30 +
                    [uint64]$nameBytes.Length + [uint64]$contentLength
                if ($localHeaderOffset -lt 0 -or $projectedDataEnd -gt $zip32FieldMaximum) {
                    throw 'Release ZIP32 local data offset reaches the ZIP64 offset sentinel.'
                }

                Write-CddsiReleaseZipUInt32 -Writer $writer -Value $localHeaderSignature -FieldName LocalHeaderSignature
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value $versionNeeded -FieldName VersionNeeded
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value $utf8Flag -FieldName GeneralPurposeFlag
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value $storeMethod -FieldName CompressionMethod
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value $fixedDosTime -FieldName LastWriteTime
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value $fixedDosDate -FieldName LastWriteDate
                Write-CddsiReleaseZipUInt32 -Writer $writer -Value 0 -FieldName Crc32Placeholder
                Write-CddsiReleaseZipUInt32 -Writer $writer -Value $contentLength -FieldName CompressedSize
                Write-CddsiReleaseZipUInt32 -Writer $writer -Value $contentLength -FieldName UncompressedSize
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value $nameBytes.Length -FieldName FileNameLength
                Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName ExtraFieldLength
                [void]$writer.Write([byte[]]$nameBytes)

                [uint64]$crc32 = $uint32Maximum
                [long]$writtenLength = 0
                while (($readCount = $sourceStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                    for ($byteIndex = 0; $byteIndex -lt $readCount; $byteIndex++) {
                        $crcIndex = [int](($crc32 -bxor [uint64]$buffer[$byteIndex]) -band [uint64]0xFF)
                        $crc32 = (($crc32 -shr 8) -bxor [uint64]$crc32Table[$crcIndex]) -band $uint32Maximum
                    }
                    [void]$writer.Write([byte[]]$buffer, [int]0, [int]$readCount)
                    $writtenLength += [long]$readCount
                }
                if ($writtenLength -ne $contentLength) {
                    throw 'Release ZIP32 source length changed while the entry was written.'
                }
                $crc32 = ($crc32 -bxor $uint32Maximum) -band $uint32Maximum
                $entryEndOffset = [long]$zipStream.Position
                $writer.Flush()
                $zipStream.Position = $localHeaderOffset + 14
                Write-CddsiReleaseZipUInt32 -Writer $writer -Value ([long]$crc32) -FieldName Crc32
                $writer.Flush()
                $zipStream.Position = $entryEndOffset

                [void]$centralRecords.Add([pscustomobject][ordered]@{
                    NameBytes         = $nameBytes
                    Crc32             = [uint32]$crc32
                    ContentLength     = $contentLength
                    LocalHeaderOffset = $localHeaderOffset
                })
            }
            finally {
                if ($null -ne $sourceStream) { $sourceStream.Dispose() }
            }
        }

        $centralDirectoryOffset = [long]$zipStream.Position
        if ($centralDirectoryOffset -lt 0 -or [uint64]$centralDirectoryOffset -gt $zip32FieldMaximum) {
            throw 'Release ZIP32 central-directory offset reaches the ZIP64 offset sentinel.'
        }
        [uint64]$predictedCentralDirectorySize = 0
        foreach ($record in $centralRecords) {
            $predictedCentralDirectorySize += [uint64]46 + [uint64]$record.NameBytes.Length
        }
        if ($predictedCentralDirectorySize -gt $zip32FieldMaximum -or
            ([uint64]$centralDirectoryOffset + $predictedCentralDirectorySize + [uint64]22) -gt $zip32FieldMaximum) {
            throw 'Release ZIP32 predicted central directory reaches a ZIP64 sentinel boundary.'
        }
        foreach ($record in $centralRecords) {
            Write-CddsiReleaseZipUInt32 -Writer $writer -Value $centralHeaderSignature -FieldName CentralHeaderSignature
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $versionNeeded -FieldName VersionMadeBy
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $versionNeeded -FieldName CentralVersionNeeded
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $utf8Flag -FieldName CentralGeneralPurposeFlag
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $storeMethod -FieldName CentralCompressionMethod
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $fixedDosTime -FieldName CentralLastWriteTime
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $fixedDosDate -FieldName CentralLastWriteDate
            Write-CddsiReleaseZipUInt32 -Writer $writer -Value ([long]$record.Crc32) -FieldName CentralCrc32
            Write-CddsiReleaseZipUInt32 -Writer $writer -Value $record.ContentLength -FieldName CentralCompressedSize
            Write-CddsiReleaseZipUInt32 -Writer $writer -Value $record.ContentLength -FieldName CentralUncompressedSize
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value $record.NameBytes.Length -FieldName CentralFileNameLength
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName CentralExtraFieldLength
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName FileCommentLength
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName DiskNumberStart
            Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName InternalFileAttributes
            Write-CddsiReleaseZipUInt32 -Writer $writer -Value 0 -FieldName ExternalFileAttributes
            Write-CddsiReleaseZipUInt32 -Writer $writer -Value $record.LocalHeaderOffset -FieldName RelativeLocalHeaderOffset
            [void]$writer.Write([byte[]]$record.NameBytes)
        }

        $centralDirectorySize = [long]$zipStream.Position - $centralDirectoryOffset
        $projectedArchiveLength = [uint64]$zipStream.Position + [uint64]22
        if ($centralDirectorySize -lt 0 -or
            [uint64]$centralDirectorySize -ne $predictedCentralDirectorySize -or
            [uint64]$centralDirectorySize -gt $zip32FieldMaximum -or
            $projectedArchiveLength -gt $zip32FieldMaximum) {
            throw 'Release ZIP32 central directory reaches a ZIP64 sentinel boundary.'
        }
        Write-CddsiReleaseZipUInt32 -Writer $writer -Value $endOfCentralDirectorySignature -FieldName EndOfCentralDirectorySignature
        Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName NumberOfThisDisk
        Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName CentralDirectoryDisk
        Write-CddsiReleaseZipUInt16 -Writer $writer -Value $centralRecords.Count -FieldName EntryCountOnDisk
        Write-CddsiReleaseZipUInt16 -Writer $writer -Value $centralRecords.Count -FieldName TotalEntryCount
        Write-CddsiReleaseZipUInt32 -Writer $writer -Value $centralDirectorySize -FieldName CentralDirectorySize
        Write-CddsiReleaseZipUInt32 -Writer $writer -Value $centralDirectoryOffset -FieldName CentralDirectoryOffset
        Write-CddsiReleaseZipUInt16 -Writer $writer -Value 0 -FieldName ArchiveCommentLength
        $writer.Flush()
        $zipStream.Flush()
    }
    catch {
        $creationError = $_
    }
    finally {
        if ($null -ne $writer) {
            try { $writer.Dispose() }
            catch { if ($null -eq $creationError) { $creationError = $_ } }
        }
        if ($null -ne $zipStream) {
            try { $zipStream.Dispose() }
            catch { if ($null -eq $creationError) { $creationError = $_ } }
        }
    }
    if ($null -ne $creationError) {
        try {
            if ([System.IO.File]::Exists($ZipPath)) { [System.IO.File]::Delete($ZipPath) }
        }
        catch {
            throw [InvalidOperationException]::new(
                'Release ZIP32 creation failed and partial-file cleanup also failed.',
                $_.Exception
            )
        }
        throw $creationError
    }
}

function Get-CddsiReleaseZipEntrySha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Entry
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $entryStream = $null
    try {
        $entryStream = $Entry.Open()
        return ([BitConverter]::ToString($sha.ComputeHash($entryStream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $entryStream) { $entryStream.Dispose() }
        $sha.Dispose()
    }
}

function Test-CddsiReleaseZipLayer {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string[]]$PackageFiles,

        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot
    )

    Initialize-CddsiReleaseCompression
    if (-not (Test-CddsiPathWithinRoot -Path $ZipPath -Root $SandboxRoot) -or
        -not [System.IO.File]::Exists($ZipPath)) {
        throw 'Release ZIP is unavailable or outside the owned sandbox.'
    }
    Assert-CddsiNoReparsePath -Path $ZipPath -StopRoot $SandboxRoot

    $zipStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $archive = $null
    $entryNames = New-Object System.Collections.Generic.List[string]
    $findings = New-Object System.Collections.Generic.List[object]
    $contentHashes = [ordered]@{}
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        foreach ($entry in @($archive.Entries)) {
            if ([string]::IsNullOrEmpty($entry.Name)) {
                throw 'Release ZIP contains a directory entry not present in the file allow-list.'
            }
            $relative = ConvertTo-CddsiReleaseRelativePath -Path $entry.FullName
            if ($contentHashes.Contains($relative)) {
                throw 'Release ZIP contains a duplicate or case-alias entry.'
            }
            $entryNames.Add($relative)
            $contentHashes[$relative] = Get-CddsiReleaseZipEntrySha256 -Entry $entry
            $entryStream = $null
            try {
                $entryStream = $entry.Open()
                foreach ($finding in @(Find-CddsiReleaseStreamSecretFindings -Stream $entryStream -RelativePath $relative -Layer ZIP)) {
                    $findings.Add($finding)
                }
            }
            finally {
                if ($null -ne $entryStream) { $entryStream.Dispose() }
            }
        }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $zipStream.Dispose()
    }

    Assert-CddsiReleaseNoSecretFindings -Findings $findings.ToArray() -Layer ZIP
    Assert-CddsiReleaseExactSet -Expected $PackageFiles -Actual $entryNames.ToArray() -Label 'ZIP entries'
    return [pscustomobject][ordered]@{
        EntryCount     = $entryNames.Count
        SecretFindings = 0
        InventoryExact = $true
        ContentHashes  = $contentHashes
    }
}

function Expand-CddsiReleaseSimulationZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ZipPath,

        [Parameter(Mandatory = $true)]
        [string]$ExtractionRoot,

        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot
    )

    Initialize-CddsiReleaseCompression
    if (-not (Test-CddsiPathWithinRoot -Path $ZipPath -Root $SandboxRoot) -or
        -not [System.IO.File]::Exists($ZipPath)) {
        throw 'Release extraction ZIP is unavailable or outside the owned sandbox.'
    }
    if (-not (Test-CddsiPathWithinRoot -Path $ExtractionRoot -Root $SandboxRoot)) {
        throw 'Release extraction root escapes the owned sandbox.'
    }
    if (Test-Path -LiteralPath $ExtractionRoot) {
        throw 'Release extraction root must not already exist.'
    }
    Assert-CddsiNoReparsePath -Path $ZipPath -StopRoot $SandboxRoot
    [void][System.IO.Directory]::CreateDirectory($ExtractionRoot)
    Assert-CddsiNoReparsePath -Path $ExtractionRoot -StopRoot $SandboxRoot

    $zipStream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $archive = $null
    $seen = @{}
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($zipStream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        foreach ($entry in @($archive.Entries)) {
            if ([string]::IsNullOrEmpty($entry.Name)) {
                throw 'Release extraction refuses ZIP directory entries.'
            }
            $relative = ConvertTo-CddsiReleaseRelativePath -Path $entry.FullName
            if ($seen.ContainsKey($relative)) {
                throw 'Release extraction refuses duplicate or case-alias ZIP entries.'
            }
            $seen[$relative] = $true

            $destination = Get-CddsiCanonicalPath -Path (Join-Path $ExtractionRoot ($relative.Replace('/', '\')))
            if (-not (Test-CddsiPathWithinRoot -Path $destination -Root $ExtractionRoot)) {
                throw 'Release extraction destination escapes the extraction root.'
            }
            $parent = Split-Path -Parent $destination
            [void][System.IO.Directory]::CreateDirectory($parent)
            Assert-CddsiNoReparsePath -Path $parent -StopRoot $SandboxRoot

            $entryStream = $null
            $destinationStream = $null
            try {
                $entryStream = $entry.Open()
                $destinationStream = [System.IO.File]::Open($destination, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
                $entryStream.CopyTo($destinationStream)
                $destinationStream.Flush()
            }
            finally {
                if ($null -ne $destinationStream) { $destinationStream.Dispose() }
                if ($null -ne $entryStream) { $entryStream.Dispose() }
            }
            Assert-CddsiNoReparsePath -Path $destination -StopRoot $SandboxRoot
        }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $zipStream.Dispose()
    }
}

function Invoke-CddsiReleaseSimulation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RepositoryRoot,

        [Parameter(Mandatory = $true)]
        [string]$ManifestPath,

        [Parameter(Mandatory = $true)]
        [string]$TempBase
    )

    $repositoryFull = $RepositoryRoot
    $tempFull = $TempBase
    $preflightError = $null
    try {
        $repositoryFull = Get-CddsiCanonicalPath -Path $RepositoryRoot
        if (-not (Test-Path -LiteralPath $repositoryFull -PathType Container)) {
            throw 'Release repository root is unavailable.'
        }
        Assert-CddsiNoReparsePath -Path $repositoryFull -StopRoot ([System.IO.Path]::GetPathRoot($repositoryFull))
        $tempFull = Get-CddsiCanonicalPath -Path $TempBase
        if (-not (Test-Path -LiteralPath $tempFull -PathType Container)) {
            throw 'Release simulation temporary root is unavailable.'
        }
        Assert-CddsiNoReparsePath -Path $tempFull -StopRoot ([System.IO.Path]::GetPathRoot($tempFull))
        if (Test-CddsiPathWithinRoot -Path $tempFull -Root $repositoryFull -AllowRoot) {
            throw 'Release simulation temporary root must not be inside the source tree.'
        }
    }
    catch {
        $preflightError = $_
    }
    if ($null -ne $preflightError) {
        $safePreflightError = Protect-CddsiReleaseFailureText `
            -Text ([string]$preflightError.Exception.Message) `
            -RepositoryRoot $repositoryFull `
            -TempRoot $tempFull `
            -OwnershipToken $null
        $preflightEnvelope = New-CddsiReleaseFailureEnvelope `
            -PrimaryError $safePreflightError `
            -CleanupOutcome NotStarted `
            -CleanupError $null `
            -RepositoryContentChanged $null `
            -RepositoryComparisonOutcome NotAvailable `
            -HarnessLedgerCount 0
        $preflightException = New-Object System.InvalidOperationException('Release simulation failed; inspect CddsiReleaseFailure evidence.')
        $preflightException.Data['CddsiReleaseFailure'] = $preflightEnvelope
        throw $preflightException
    }

    $ledger = New-Object System.Collections.Generic.List[object]
    $sandbox = $null
    $runId = [guid]::NewGuid().ToString('D')
    $primaryError = $null
    $cleanupError = $null
    $cleanupOutcome = 'NotStarted'
    $repositorySnapshotBefore = $null
    $repositorySnapshotAfter = $null
    $repositoryComparisonOutcome = 'NotAvailable'
    $repositoryContentChanged = $null
    $sourcePackageChanged = $false
    $contract = $null
    $sourceItems = @()
    $sourceSecretFindings = 0
    $stagingSecretFindings = 0
    $zipEvidence = $null
    $extractedSecretFindings = 0
    $extractedItems = @()
    try {
        $sandbox = New-CddsiOwnedSandbox -TempBase $tempFull -RunId $runId -Ledger $ledger
        $simulationRoot = Join-Path $sandbox.Root '发布 仿真 &!()'
        $stagingRoot = Join-Path $simulationRoot 'staging'
        $zipPath = Join-Path $simulationRoot 'release-simulation.zip'
        $extractionRoot = Join-Path $simulationRoot 'extracted 内容 &!()'
        foreach ($path in @($simulationRoot, $stagingRoot, $zipPath, $extractionRoot)) {
            if (-not (Test-CddsiPathWithinRoot -Path $path -Root $sandbox.Root)) {
                throw 'Release simulation output escapes the owned sandbox.'
            }
        }

        $repositorySnapshotBefore = Get-CddsiReleaseRepositorySnapshot -RepositoryRoot $repositoryFull
        Add-CddsiReleaseFileLedgerEntry `
            -Ledger $ledger `
            -RunId $runId `
            -RuleId ReleaseRepositorySnapshotBefore `
            -ResourceToken '<REPOSITORY_ROOT>/<WORKING_TREE>' `
            -ItemCount $repositorySnapshotBefore.ItemCount

        $contract = Get-CddsiReleaseManifestContract -RepositoryRoot $repositoryFull -ManifestPath $ManifestPath
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseManifestRead -ResourceToken '<REPOSITORY_ROOT>/<RELEASE_MANIFEST>' -ItemCount 1

        $sourceItems = @(Get-CddsiReleasePackageItems -RepositoryRoot $contract.RepositoryRoot -PackageFiles $contract.PackageFiles)
        Assert-CddsiReleaseExactSet `
            -Expected $contract.PackageFiles `
            -Actual @($sourceItems | ForEach-Object RelativePath) `
            -Label 'Source package files'
        $sourceHashes = Get-CddsiReleaseContentHashes -Items $sourceItems
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseSourceRead -ResourceToken '<REPOSITORY_ROOT>/<PACKAGE_ALLOW_LIST>' -ItemCount $sourceItems.Count

        $sourceSecretFindings = Invoke-CddsiReleaseFileSecretScan -Items $sourceItems -Layer Source
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseSourceSecretScan -ResourceToken '<REPOSITORY_ROOT>/<PACKAGE_ALLOW_LIST>' -ItemCount $sourceItems.Count

        Copy-CddsiReleasePackageItems -Items $sourceItems -StagingRoot $stagingRoot -SandboxRoot $sandbox.Root
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseStageCreateCopy -ResourceToken '<SANDBOX_ROOT>/<RELEASE_STAGE>' -ItemCount $sourceItems.Count

        $stagedItems = @(Get-CddsiReleaseTreeItems -TreeRoot $stagingRoot -SandboxRoot $sandbox.Root)
        Assert-CddsiReleaseExactSet `
            -Expected $contract.PackageFiles `
            -Actual @($stagedItems | ForEach-Object RelativePath) `
            -Label 'Staging inventory'
        $stagingSecretFindings = Invoke-CddsiReleaseFileSecretScan -Items $stagedItems -Layer Staging
        $stagingHashes = Get-CddsiReleaseContentHashes -Items $stagedItems
        Assert-CddsiReleaseContentHashesEqual -Expected $sourceHashes -Actual $stagingHashes -Label 'Source-to-staging'
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseStageRead -ResourceToken '<SANDBOX_ROOT>/<RELEASE_STAGE>' -ItemCount $stagedItems.Count

        New-CddsiReleaseSimulationZip `
            -StagingRoot $stagingRoot `
            -ZipPath $zipPath `
            -PackageFiles $contract.PackageFiles `
            -SandboxRoot $sandbox.Root
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseZipCreate -ResourceToken '<SANDBOX_ROOT>/<RELEASE_ZIP>' -ItemCount $contract.PackageFiles.Count

        $zipEvidence = Test-CddsiReleaseZipLayer `
            -ZipPath $zipPath `
            -PackageFiles $contract.PackageFiles `
            -SandboxRoot $sandbox.Root
        Assert-CddsiReleaseContentHashesEqual -Expected $sourceHashes -Actual $zipEvidence.ContentHashes -Label 'Source-to-ZIP'
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseZipRead -ResourceToken '<SANDBOX_ROOT>/<RELEASE_ZIP>' -ItemCount $zipEvidence.EntryCount

        Expand-CddsiReleaseSimulationZip -ZipPath $zipPath -ExtractionRoot $extractionRoot -SandboxRoot $sandbox.Root
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseExtractCreate -ResourceToken '<SANDBOX_ROOT>/<RELEASE_EXTRACT>' -ItemCount $zipEvidence.EntryCount

        $extractedItems = @(Get-CddsiReleaseTreeItems -TreeRoot $extractionRoot -SandboxRoot $sandbox.Root)
        Assert-CddsiReleaseExactSet `
            -Expected $contract.PackageFiles `
            -Actual @($extractedItems | ForEach-Object RelativePath) `
            -Label 'Extracted inventory'
        $extractedSecretFindings = Invoke-CddsiReleaseFileSecretScan -Items $extractedItems -Layer Extracted
        $extractedHashes = Get-CddsiReleaseContentHashes -Items $extractedItems
        Assert-CddsiReleaseContentHashesEqual -Expected $sourceHashes -Actual $extractedHashes -Label 'Source-to-extracted'
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseExtractRead -ResourceToken '<SANDBOX_ROOT>/<RELEASE_EXTRACT>' -ItemCount $extractedItems.Count

        $afterSourceHashes = Get-CddsiReleaseContentHashes -Items $sourceItems
        try {
            Assert-CddsiReleaseContentHashesEqual -Expected $sourceHashes -Actual $afterSourceHashes -Label 'Source re-fingerprint'
        }
        catch {
            $sourcePackageChanged = $true
            throw
        }
        Add-CddsiReleaseFileLedgerEntry -Ledger $ledger -RunId $runId -RuleId ReleaseSourceRefingerprint -ResourceToken '<REPOSITORY_ROOT>/<PACKAGE_ALLOW_LIST>' -ItemCount $sourceItems.Count

        $repositorySnapshotAfter = Get-CddsiReleaseRepositorySnapshot -RepositoryRoot $repositoryFull
        Add-CddsiReleaseFileLedgerEntry `
            -Ledger $ledger `
            -RunId $runId `
            -RuleId ReleaseRepositorySnapshotAfter `
            -ResourceToken '<REPOSITORY_ROOT>/<WORKING_TREE>' `
            -ItemCount $repositorySnapshotAfter.ItemCount
        $repositoryContentChanged = -not (Test-CddsiReleaseRepositorySnapshotsEqual `
            -Before $repositorySnapshotBefore `
            -After $repositorySnapshotAfter)
        $repositoryComparisonOutcome = 'Compared'

        $preCleanupLedgerContract = @(New-CddsiReleaseLedgerContract `
            -PackageFileCount $contract.PackageFiles.Count `
            -RepositoryItemCountBefore $repositorySnapshotBefore.ItemCount `
            -RepositoryItemCountAfter $repositorySnapshotAfter.ItemCount)
        Assert-CddsiReleaseLedgerSequence `
            -Ledger $ledger `
            -RunId $runId `
            -Expected $preCleanupLedgerContract `
            -OwnershipToken $sandbox.OwnershipToken
        if ($repositoryContentChanged) {
            throw 'Release simulation detected working-tree content or directory drift.'
        }
    }
    catch {
        $primaryError = $_
    }
    finally {
        if ($null -ne $sandbox -and (Test-Path -LiteralPath $sandbox.Root -PathType Container)) {
            try {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
                $cleanupOutcome = 'Succeeded'
            }
            catch {
                $cleanupError = $_
                $cleanupOutcome = 'Failed'
            }
        }
        elseif ($null -ne $sandbox) {
            $cleanupOutcome = 'Succeeded'
        }

        if ($null -ne $repositorySnapshotBefore -and $null -eq $repositorySnapshotAfter) {
            try {
                $repositorySnapshotAfter = Get-CddsiReleaseRepositorySnapshot -RepositoryRoot $repositoryFull
                $repositoryContentChanged = -not (Test-CddsiReleaseRepositorySnapshotsEqual `
                    -Before $repositorySnapshotBefore `
                    -After $repositorySnapshotAfter)
                $repositoryComparisonOutcome = 'Compared'
            }
            catch {
                if ($null -eq $primaryError) { $primaryError = $_ }
            }
        }
    }

    if ($null -eq $primaryError -and $cleanupOutcome -eq 'Succeeded') {
        try {
            $finalLedgerContract = @(New-CddsiReleaseLedgerContract `
                -PackageFileCount $contract.PackageFiles.Count `
                -RepositoryItemCountBefore $repositorySnapshotBefore.ItemCount `
                -RepositoryItemCountAfter $repositorySnapshotAfter.ItemCount `
                -IncludeCleanup)
            Assert-CddsiReleaseLedgerSequence `
                -Ledger $ledger `
                -RunId $runId `
                -Expected $finalLedgerContract `
                -OwnershipToken $sandbox.OwnershipToken
        }
        catch {
            $primaryError = $_
        }
    }
    if ($null -ne $primaryError -or $cleanupOutcome -eq 'Failed') {
        $primaryText = if ($null -ne $primaryError) {
            [string]$primaryError.Exception.Message
        }
        else {
            'Owned release sandbox cleanup failed.'
        }
        $safePrimary = Protect-CddsiReleaseFailureText `
            -Text $primaryText `
            -RepositoryRoot $repositoryFull `
            -TempRoot $tempFull `
            -OwnershipToken $(if ($null -eq $sandbox) { $null } else { $sandbox.OwnershipToken })
        $safeCleanup = if ($null -eq $cleanupError) {
            $null
        }
        else {
            Protect-CddsiReleaseFailureText `
                -Text ([string]$cleanupError.Exception.Message) `
                -RepositoryRoot $repositoryFull `
                -TempRoot $tempFull `
                -OwnershipToken $(if ($null -eq $sandbox) { $null } else { $sandbox.OwnershipToken })
        }
        $envelope = New-CddsiReleaseFailureEnvelope `
            -PrimaryError $safePrimary `
            -CleanupOutcome $cleanupOutcome `
            -CleanupError $safeCleanup `
            -RepositoryContentChanged $repositoryContentChanged `
            -RepositoryComparisonOutcome $repositoryComparisonOutcome `
            -HarnessLedgerCount $ledger.Count
        $exception = New-Object System.InvalidOperationException('Release simulation failed; inspect CddsiReleaseFailure evidence.')
        $exception.Data['CddsiReleaseFailure'] = $envelope
        throw $exception
    }

    $finalExpected = @(New-CddsiReleaseLedgerContract `
        -PackageFileCount $contract.PackageFiles.Count `
        -RepositoryItemCountBefore $repositorySnapshotBefore.ItemCount `
        -RepositoryItemCountAfter $repositorySnapshotAfter.ItemCount `
        -IncludeCleanup)
    $trustedHarnessProcessCount = @($ledger | Where-Object Category -eq 'Process').Count
    $trustedHarnessNetworkCount = @($ledger | Where-Object Category -eq 'Network').Count
    $trustedHarnessFileSystemCount = @($ledger | Where-Object Category -eq 'FileSystem').Count
    $unexpectedLedgerEntryCount = [Math]::Abs($ledger.Count - $finalExpected.Count) +
        @($ledger | Where-Object { $_.Category -ne 'FileSystem' -or $_.Outcome -ne 'Succeeded' }).Count
    $secretFindings = [int]$sourceSecretFindings + [int]$stagingSecretFindings +
        [int]$zipEvidence.SecretFindings + [int]$extractedSecretFindings
    return [pscustomobject][ordered]@{
        SchemaVersion              = 1
        Operation                  = 'ReleaseSimulation'
        Mode                       = 'DryRun'
        Status                     = 'SUCCEEDED'
        Changed                    = [bool]($sourcePackageChanged -or $repositoryContentChanged)
        PackageFileCount           = $contract.PackageFiles.Count
        SourceSecretFindings       = $sourceSecretFindings
        StagingSecretFindings      = $stagingSecretFindings
        ZipSecretFindings          = $zipEvidence.SecretFindings
        ZipEntryCount              = $zipEvidence.EntryCount
        ZipInventoryExact          = $zipEvidence.InventoryExact
        ZipDeterministic           = $true
        ZipEntryOrder              = 'Ordinal'
        ZipEntryTimestampUtc       = '1980-01-01T00:00:00Z'
        ZipCompression             = 'Store'
        ExtractSecretFindings      = $extractedSecretFindings
        ExtractFileCount           = $extractedItems.Count
        ExtractInventoryExact      = ($extractedItems.Count -eq $contract.PackageFiles.Count)
        ContentHashesExact         = -not $sourcePackageChanged
        SpecialPathValidated       = $true
        RepositoryFileCount        = $repositorySnapshotBefore.FileCount
        RepositoryDirectoryCount   = $repositorySnapshotBefore.DirectoryCount
        TrustedHarnessProcessCount = $trustedHarnessProcessCount
        TrustedHarnessNetworkCount = $trustedHarnessNetworkCount
        TrustedHarnessFileSystemCount = $trustedHarnessFileSystemCount
        HarnessLedgerExact         = ($unexpectedLedgerEntryCount -eq 0)
        SourcePackageChanged       = $sourcePackageChanged
        LIVE_PROVIDER_LOADED                  = (@($ledger | Where-Object { $_.RuleId -match 'LiveProvider' }).Count -gt 0)
        FORBIDDEN_RESOURCE_ACCESS_COUNT       = @($ledger | Where-Object Outcome -eq 'Denied').Count
        OUTSIDE_SANDBOX_WRITE_COUNT           = @($ledger | Where-Object RuleId -eq 'OutsideSandboxWrite').Count
        PRODUCT_LIVE_PROCESS_SPAWN_COUNT      = @($ledger | Where-Object { $_.Category -eq 'Process' -and $_.RuleId -match 'Product' }).Count
        PRODUCT_NETWORK_REQUEST_COUNT         = @($ledger | Where-Object { $_.Category -eq 'Network' -and $_.RuleId -match 'Product' }).Count
        REAL_REGISTRY_ACCESS_COUNT            = @($ledger | Where-Object RuleId -eq 'RealRegistryAccess').Count
        UNAPPROVED_HARNESS_PROCESS_COUNT      = @($ledger | Where-Object { $_.Category -eq 'Process' -and $_.Outcome -ne 'Succeeded' }).Count
        UNAPPROVED_HARNESS_NETWORK_COUNT      = @($ledger | Where-Object { $_.Category -eq 'Network' -and $_.Outcome -ne 'Succeeded' }).Count
        SECRET_FINDINGS                       = $secretFindings
        UNEXPECTED_LEDGER_ENTRY_COUNT         = $unexpectedLedgerEntryCount
        REPOSITORY_CONTENT_CHANGED            = [bool]$repositoryContentChanged
        CleanupOutcome             = $cleanupOutcome
    }
}

if ($entryImportOnly) {
    return
}
if (-not $entryDryRun) {
    throw 'P1 release publication is fail closed. Only -DryRun Release Simulation is available.'
}
if ($entryOutputDirectorySpecified -or $entrySkipQualityGate) {
    throw 'P1 -DryRun owns all temporary output and does not accept OutputDirectory or SkipQualityGate.'
}

$simulation = Invoke-CddsiReleaseSimulation `
    -RepositoryRoot $root `
    -ManifestPath $manifestPath `
    -TempBase ([System.IO.Path]::GetTempPath())
Write-Host ("[release] DryRun Release Simulation passed for {0} package files; sandbox cleanup succeeded." -f $simulation.PackageFileCount) -ForegroundColor Green
return $simulation
