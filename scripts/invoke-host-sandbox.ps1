[CmdletBinding()]
param(
    [ValidateSet('Quality')]
    [string]$Scenario = 'Quality',

    [ValidateSet('AllBlocking', 'ProductReleaseBlocking', 'HistoricalDiagnostic')]
    [string]$QualitySet = 'AllBlocking',

    [string]$RepositoryRoot,
    [string]$PowerShell7Executable,
    [string]$PowerShell7Sha256,
    [string]$WindowsPowerShellExecutable,
    [string]$WindowsPowerShellSha256,
    [string]$GitExecutable,
    [string]$GitSha256,

    [ValidateRange(30, 3600)]
    [int]$ProcessTimeoutSeconds = 900,

    [switch]$KeepSandboxOnFailure,
    [switch]$PassThru,
    [switch]$ImportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:CddsiOwnerMarkerName = '.cddsi-owner.json'
$qualitySetPolicyValidatorPath = Join-Path $PSScriptRoot 'quality-set-policy.ps1'
if (-not (Test-Path -LiteralPath $qualitySetPolicyValidatorPath -PathType Leaf)) {
    throw 'The pure quality-set policy validator is unavailable.'
}
. $qualitySetPolicyValidatorPath

function Get-CddsiCanonicalPath {
    param([Parameter(Mandatory = $true)][string]$Path)

    $fullPath = [System.IO.Path]::GetFullPath($Path)
    $volumeRoot = [System.IO.Path]::GetPathRoot($fullPath)
    if ([string]::Equals($fullPath.TrimEnd('\'), $volumeRoot.TrimEnd('\'), [StringComparison]::OrdinalIgnoreCase)) {
        return $volumeRoot
    }
    return $fullPath.TrimEnd('\')
}

function Get-CddsiSha256Text {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($utf8.GetBytes($Text)))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-CddsiPathWithinRoot {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root,
        [switch]$AllowRoot
    )

    $pathFull = Get-CddsiCanonicalPath -Path $Path
    $rootFull = Get-CddsiCanonicalPath -Path $Root
    if ([string]::Equals($pathFull, $rootFull, [StringComparison]::OrdinalIgnoreCase)) {
        return $AllowRoot.IsPresent
    }
    $rootPrefix = $rootFull
    if (-not $rootPrefix.EndsWith('\', [StringComparison]::Ordinal)) { $rootPrefix += '\' }
    return $pathFull.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Assert-CddsiNoReparsePath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$StopRoot,
        [switch]$PathMayNotExist
    )

    $stopFull = Get-CddsiCanonicalPath -Path $StopRoot
    $cursor = Get-CddsiCanonicalPath -Path $Path
    if (-not (Test-CddsiPathWithinRoot -Path $cursor -Root $stopFull -AllowRoot)) {
        throw 'Path is outside the approved root.'
    }
    if ($PathMayNotExist -and -not (Test-Path -LiteralPath $cursor)) {
        $cursor = Split-Path -Parent $cursor
    }

    while (-not [string]::IsNullOrWhiteSpace($cursor)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Approved path contains a reparse point.'
            }
        }
        if ([string]::Equals($cursor, $stopFull, [StringComparison]::OrdinalIgnoreCase)) { return }
        $parent = Split-Path -Parent $cursor
        if ([string]::IsNullOrWhiteSpace($parent) -or $parent -eq $cursor) { break }
        $cursor = Get-CddsiCanonicalPath -Path $parent
    }
    throw 'Approved root was not reached while validating path ancestry.'
}

function New-CddsiOwnershipToken {
    $bytes = New-Object byte[] 32
    $rng = New-Object System.Security.Cryptography.RNGCryptoServiceProvider
    try {
        $rng.GetBytes($bytes)
        return ([BitConverter]::ToString($bytes)).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $rng.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Add-CddsiHarnessLedgerEntry {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('FileSystem', 'Process', 'Network')][string]$Category,
        [Parameter(Mandatory = $true)][string]$RuleId,
        [Parameter(Mandatory = $true)][string]$ResourceToken,
        [Parameter(Mandatory = $true)][ValidateSet('Allowed', 'Denied', 'Failed', 'Succeeded', 'TimedOut')][string]$Outcome,
        [AllowNull()]$Data
    )

    $Ledger.Add([pscustomobject][ordered]@{
        SchemaVersion = 1
        Sequence      = $Ledger.Count + 1
        RunId         = $RunId
        Plane         = 'TrustedHarness'
        Category      = $Category
        RuleId        = $RuleId
        ResourceToken = $ResourceToken
        Outcome       = $Outcome
        Data          = $Data
    })
}

function Assert-CddsiExactObjectValue {
    param(
        [AllowNull()]$Expected,
        [AllowNull()]$Actual,
        [Parameter(Mandatory = $true)][string]$Label
    )

    if ($null -eq $Expected -or $null -eq $Actual) {
        if ($null -ne $Expected -or $null -ne $Actual) { throw ("Exact value drift: {0}." -f $Label) }
        return
    }
    if ($Expected -is [pscustomobject]) {
        if ($Actual -isnot [pscustomobject]) { throw ("Exact object type drift: {0}." -f $Label) }
        $expectedNames = [string[]]@($Expected.PSObject.Properties.Name)
        $actualNames = [string[]]@($Actual.PSObject.Properties.Name)
        [Array]::Sort($expectedNames, [StringComparer]::Ordinal)
        [Array]::Sort($actualNames, [StringComparer]::Ordinal)
        if (($expectedNames -join "`n") -cne ($actualNames -join "`n")) { throw ("Exact property set drift: {0}." -f $Label) }
        foreach ($name in $expectedNames) {
            Assert-CddsiExactObjectValue -Expected $Expected.$name -Actual $Actual.$name -Label ("{0}.{1}" -f $Label, $name)
        }
        return
    }
    if ($Expected -is [System.Array]) {
        if ($Actual -isnot [System.Array] -or $Expected.GetType().FullName -cne $Actual.GetType().FullName -or $Expected.Count -ne $Actual.Count) {
            throw ("Exact array drift: {0}." -f $Label)
        }
        for ($index = 0; $index -lt $Expected.Count; $index++) {
            Assert-CddsiExactObjectValue -Expected $Expected[$index] -Actual $Actual[$index] -Label ("{0}[{1}]" -f $Label, $index)
        }
        return
    }
    if ($Expected.GetType().FullName -cne $Actual.GetType().FullName) { throw ("Exact scalar type drift: {0}." -f $Label) }
    if ($Expected -is [string]) {
        if ($Expected -cne $Actual) { throw ("Exact string value drift: {0}." -f $Label) }
        return
    }
    if ($Expected -ne $Actual) { throw ("Exact scalar value drift: {0}." -f $Label) }
}

function New-CddsiExpectedHarnessLedgerEntry {
    param(
        [Parameter(Mandatory = $true)][int]$Sequence,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][ValidateSet('FileSystem', 'Process', 'Network')][string]$Category,
        [Parameter(Mandatory = $true)][string]$RuleId,
        [Parameter(Mandatory = $true)][string]$ResourceToken,
        [Parameter(Mandatory = $true)][string]$Outcome,
        [AllowNull()]$Data
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        Sequence      = $Sequence
        RunId         = $RunId
        Plane         = 'TrustedHarness'
        Category      = $Category
        RuleId        = $RuleId
        ResourceToken = $ResourceToken
        Outcome       = $Outcome
        Data          = $Data
    }
}

function Assert-CddsiHarnessLedgerExact {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ExpectedEntries
    )

    if ($Ledger.Count -ne $ExpectedEntries.Count) { throw 'Trusted harness ledger count drift.' }
    for ($index = 0; $index -lt $ExpectedEntries.Count; $index++) {
        Assert-CddsiExactObjectValue -Expected $ExpectedEntries[$index] -Actual $Ledger[$index] -Label ("HarnessLedger[{0}]" -f $index)
    }
    return $true
}

function Write-CddsiUtf8CreateNew {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
    )

    $utf8 = New-Object System.Text.UTF8Encoding($false)
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
    try {
        $writer = New-Object System.IO.StreamWriter($stream, $utf8)
        try {
            $writer.Write($Content)
            $writer.Flush()
            $stream.Flush()
        }
        finally {
            $writer.Dispose()
        }
    }
    finally {
        $stream.Dispose()
    }
}

function New-CddsiOwnedSandbox {
    param(
        [Parameter(Mandatory = $true)][string]$TempBase,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger
    )

    $parsedRunId = [guid]::Empty
    if (-not [guid]::TryParse($RunId, [ref]$parsedRunId)) { throw 'RunId must be a GUID.' }
    $tempFull = [System.IO.Path]::GetFullPath($TempBase).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $tempFull -PathType Container)) { throw 'OS temporary root is unavailable.' }
    Assert-CddsiNoReparsePath -Path $tempFull -StopRoot ([System.IO.Path]::GetPathRoot($tempFull))

    $leaf = 'cddsi-test-' + [guid]::NewGuid().ToString('D')
    $root = Join-Path $tempFull $leaf
    if (Test-Path -LiteralPath $root) { throw 'Generated sandbox path already exists.' }
    Assert-CddsiNoReparsePath -Path $root -StopRoot $tempFull -PathMayNotExist
    [void][System.IO.Directory]::CreateDirectory($root)
    Assert-CddsiNoReparsePath -Path $root -StopRoot $tempFull
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $RunId -Category FileSystem -RuleId CreateSandbox -ResourceToken '<SANDBOX_ROOT>' -Outcome Succeeded -Data $null

    $token = New-CddsiOwnershipToken
    $markerPath = Join-Path $root $script:CddsiOwnerMarkerName
    $marker = [pscustomobject][ordered]@{
        SchemaVersion = 1
        MarkerType    = 'CddsiHostSandboxOwner'
        RunId         = $RunId
        OwnershipToken = $token
        RootBindingSha256 = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($root).ToUpperInvariant())
    }
    Write-CddsiUtf8CreateNew -Path $markerPath -Content ($marker | ConvertTo-Json -Depth 5)
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $RunId -Category FileSystem -RuleId WriteOwnerMarker -ResourceToken '<SANDBOX_ROOT>/.cddsi-owner.json' -Outcome Succeeded -Data $null

    $paths = [ordered]@{
        Profile          = Join-Path $root 'profile'
        LocalAppData     = Join-Path $root 'profile\AppData\Local'
        RoamingAppData   = Join-Path $root 'profile\AppData\Roaming'
        ProgramData      = Join-Path $root 'program-data'
        Temp             = Join-Path $root 'temp'
        XdgConfig        = Join-Path $root 'xdg-config'
        XdgData          = Join-Path $root 'xdg-data'
        Downloads        = Join-Path $root 'downloads'
        State            = Join-Path $root 'state'
        Backup           = Join-Path $root 'backup'
        Reports          = Join-Path $root 'reports'
        Evidence         = Join-Path $root 'evidence'
        CredentialStore  = Join-Path $root 'credential-store'
    }
    $canaryValue = 'CDDSI_SYNTHETIC_CANARY_' + $RunId.Replace('-', '')
    $canaryFiles = @(
        @{ Path = (Join-Path $paths.Profile '.gitconfig'); Content = "[broken-$canaryValue" }
        @{ Path = (Join-Path $paths.XdgConfig 'git\config'); Content = "[broken-$canaryValue" }
        @{ Path = (Join-Path $paths.Profile '.claude\settings.json'); Content = ('{"canary":"' + $canaryValue + '"}') }
        @{ Path = (Join-Path $paths.LocalAppData 'Claude-3p\configLibrary\canary.json'); Content = ('{"canary":"' + $canaryValue + '"}') }
        @{ Path = (Join-Path $paths.CredentialStore 'canary.txt'); Content = $canaryValue }
    )
    $canaryFileSha256 = [ordered]@{}
    foreach ($canary in $canaryFiles) { $canaryFileSha256[$canary.Path] = Get-CddsiSha256Text -Text $canary.Content }
    $sandbox = [pscustomobject][ordered]@{
        Root         = $root
        TempBase     = $tempFull
        RunId        = $RunId
        OwnershipToken = $token
        MarkerPath   = $markerPath
        Paths        = $paths
        CanaryValue  = $canaryValue
        CanaryPaths  = @($canaryFiles | ForEach-Object Path)
        CanaryFileSha256 = $canaryFileSha256
    }
    try {
        foreach ($path in $paths.Values) {
            if (-not (Test-CddsiPathWithinRoot -Path $path -Root $root)) { throw 'Synthetic path escapes the sandbox.' }
            [void][System.IO.Directory]::CreateDirectory($path)
            Assert-CddsiNoReparsePath -Path $path -StopRoot $root
        }
        foreach ($canary in $canaryFiles) {
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $canary.Path))
            Write-CddsiUtf8CreateNew -Path $canary.Path -Content $canary.Content
        }
        Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $RunId -Category FileSystem -RuleId CreateSyntheticEnvironment -ResourceToken '<SANDBOX_ROOT>/synthetic' -Outcome Succeeded -Data ([pscustomobject]@{ CanaryFileCount = $canaryFiles.Count })
        return $sandbox
    }
    catch {
        $constructionError = $_
        try { Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $Ledger } catch { }
        throw $constructionError
    }
}

function Read-CddsiOwnerMarker {
    param([Parameter(Mandatory = $true)]$Sandbox)

    if (-not (Test-Path -LiteralPath $Sandbox.MarkerPath -PathType Leaf)) { throw 'Sandbox owner marker is missing.' }
    $text = [System.IO.File]::ReadAllText($Sandbox.MarkerPath, [System.Text.Encoding]::UTF8)
    $marker = $text | ConvertFrom-Json -ErrorAction Stop
    $actualNames = @($marker.PSObject.Properties.Name | Sort-Object)
    $expectedNames = @('MarkerType', 'OwnershipToken', 'RootBindingSha256', 'RunId', 'SchemaVersion' | Sort-Object)
    if (($actualNames -join "`n") -cne ($expectedNames -join "`n")) { throw 'Sandbox owner marker schema drift.' }
    if ($marker.SchemaVersion -ne 1 -or $marker.MarkerType -cne 'CddsiHostSandboxOwner') { throw 'Sandbox owner marker is invalid.' }
    if ($marker.RunId -cne $Sandbox.RunId -or $marker.OwnershipToken -cne $Sandbox.OwnershipToken) { throw 'Sandbox ownership does not match this run.' }
    $expectedBinding = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($Sandbox.Root).ToUpperInvariant())
    if ($marker.RootBindingSha256 -cne $expectedBinding) { throw 'Sandbox root binding does not match.' }
    return $marker
}

function Remove-CddsiOwnedSandbox {
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger
    )

    $root = [System.IO.Path]::GetFullPath($Sandbox.Root).TrimEnd('\')
    if (-not (Test-CddsiPathWithinRoot -Path $root -Root $Sandbox.TempBase)) { throw 'Refusing cleanup outside the approved temporary root.' }
    if ((Split-Path -Leaf $root) -notmatch '^cddsi-test-[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') { throw 'Refusing cleanup for an invalid sandbox leaf name.' }
    Assert-CddsiNoReparsePath -Path $root -StopRoot $Sandbox.TempBase
    $null = Read-CddsiOwnerMarker -Sandbox $Sandbox

    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($root)
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Refusing recursive cleanup because the sandbox contains a reparse point.'
            }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName) }
        }
    }

    [System.IO.Directory]::Delete($root, $true)
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $Sandbox.RunId -Category FileSystem -RuleId CleanupSandbox -ResourceToken '<SANDBOX_ROOT>' -Outcome Succeeded -Data $null
}

function ConvertTo-CddsiWindowsArgument {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Argument)

    if ($Argument.Length -gt 0 -and $Argument -notmatch '[\s"]') { return $Argument }
    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    $backslashes = 0
    foreach ($character in $Argument.ToCharArray()) {
        if ($character -eq '\') {
            $backslashes++
            continue
        }
        if ($character -eq '"') {
            if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
            [void]$builder.Append('\"')
            $backslashes = 0
            continue
        }
        if ($backslashes -gt 0) {
            [void]$builder.Append(('\' * $backslashes))
            $backslashes = 0
        }
        [void]$builder.Append($character)
    }
    if ($backslashes -gt 0) { [void]$builder.Append(('\' * ($backslashes * 2))) }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function Join-CddsiWindowsArguments {
    param([Parameter(Mandatory = $true)][AllowEmptyCollection()][AllowEmptyString()][string[]]$Arguments)
    return (@($Arguments | ForEach-Object { ConvertTo-CddsiWindowsArgument -Argument $_ }) -join ' ')
}

function ConvertTo-CddsiSafeDiagnosticText {
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(256, 65536)][int]$MaximumLength = 6000,
        [switch]$SkipTruncation
    )

    if ($null -eq $Text) { return '' }
    $safe = [regex]::Replace($Text, '\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)', '')
    $safe = [regex]::Replace($safe, '\x1B\[[0-?]*[ -/]*[@-~]', '')
    $safe = [regex]::Replace($safe, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]', '')
    $safe = [regex]::Replace($safe, '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]', '')
    if (-not $SkipTruncation -and $safe.Length -gt $MaximumLength) {
        $marker = [Environment]::NewLine + '[...TRUNCATED...]' + [Environment]::NewLine
        $headLength = [Math]::Min(1500, [Math]::Floor(($MaximumLength - $marker.Length) / 2))
        $tailLength = $MaximumLength - $marker.Length - $headLength
        $tailStart = $safe.Length - $tailLength
        if (
            $headLength -gt 0 -and $headLength -lt $safe.Length -and
            [char]::IsHighSurrogate($safe[$headLength - 1]) -and
            [char]::IsLowSurrogate($safe[$headLength])
        ) {
            $headLength--
        }
        if (
            $tailStart -gt 0 -and $tailStart -lt $safe.Length -and
            [char]::IsLowSurrogate($safe[$tailStart]) -and
            [char]::IsHighSurrogate($safe[$tailStart - 1])
        ) {
            $tailStart++
        }
        $safe = $safe.Substring(0, $headLength) + $marker + $safe.Substring($tailStart)
    }
    return $safe
}

function Get-CddsiHarnessPathDisclosurePattern {
    param([Parameter(Mandatory = $true)][string]$Path)

    $normalized = $Path.Replace('\', '/')
    $segments = $normalized.Split(
        [char[]]@('/'),
        [System.StringSplitOptions]::None)
    return (@($segments | ForEach-Object {
        [regex]::Escape([string]$_)
    }) -join '[\\/]')
}

function Protect-CddsiHarnessText {
    param(
        [AllowNull()][string]$Text,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokens,
        [AllowNull()][string]$OwnershipToken,
        [AllowNull()][string]$CanaryValue,
        [ValidateRange(256, 65536)][int]$MaximumLength = 6000
    )

    $safe = ConvertTo-CddsiSafeDiagnosticText -Text $Text -SkipTruncation
    $safe = [regex]::Replace($safe, '(?i)sk-[a-z0-9_-]{20,}', '[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])', 'Bearer [REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)(?<prefix>"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?)[a-z0-9._~-]{20,}', '${prefix}[REDACTED]')
    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $safe = [regex]::Replace($safe, '(?is)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----', '[REDACTED PRIVATE KEY HEADER]')
    if (-not [string]::IsNullOrWhiteSpace($OwnershipToken)) { $safe = $safe.Replace($OwnershipToken, '[OWNERSHIP_TOKEN]') }
    if (-not [string]::IsNullOrWhiteSpace($CanaryValue)) { $safe = $safe.Replace($CanaryValue, '[SYNTHETIC_CANARY]') }
    foreach ($token in $PathTokens.Keys) {
        $value = [string]$PathTokens[$token]
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $pathPattern = Get-CddsiHarnessPathDisclosurePattern -Path $value
            $safe = [regex]::Replace(
                $safe,
                $pathPattern,
                [string]$token,
                (
                    [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                    [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
                ))
        }
    }
    return ConvertTo-CddsiSafeDiagnosticText -Text $safe -MaximumLength $MaximumLength
}

function Test-CddsiSafeDiagnosticDisclosure {
    param(
        [Parameter(Mandatory = $true)][string]$Text,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokens,
        [AllowNull()][string]$OwnershipToken,
        [AllowNull()][string]$CanaryValue
    )

    if ([regex]::IsMatch($Text, '[\x00-\x08\x0B\x0C\x0E-\x1F\x7F-\x9F]')) { return $false }
    if ([regex]::IsMatch($Text, '[\u061C\u200E\u200F\u202A-\u202E\u2066-\u2069]')) { return $false }
    if ((Get-CddsiSecretFindingCount -Text $Text -CanaryValue $CanaryValue) -ne 0) { return $false }
    if (-not [string]::IsNullOrWhiteSpace($OwnershipToken) -and $Text.Contains($OwnershipToken)) { return $false }
    foreach ($token in $PathTokens.Keys) {
        $value = [string]$PathTokens[$token]
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $pathPattern = Get-CddsiHarnessPathDisclosurePattern -Path $value
            if ([regex]::IsMatch(
                    $Text,
                    $pathPattern,
                    (
                        [System.Text.RegularExpressions.RegexOptions]::IgnoreCase -bor
                        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
                    ))) {
                return $false
            }
        }
    }
    return $true
}

function Get-CddsiUnicodeSafeTail {
    param(
        [AllowNull()][string]$Text,
        [ValidateRange(1, 100000)][int]$MaximumLength = 5000
    )

    if ([string]::IsNullOrEmpty($Text) -or $Text.Length -le $MaximumLength) {
        return [string]$Text
    }
    $start = $Text.Length - $MaximumLength
    if (
        $start -gt 0 -and
        [char]::IsLowSurrogate($Text[$start]) -and
        [char]::IsHighSurrogate($Text[$start - 1])
    ) {
        $start++
    }
    return $Text.Substring($start)
}

function Assert-CddsiSafeFailedTestSummary {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FailedTests,
        [Parameter(Mandatory = $true)][ValidateRange(0, 100000)][long]$FailedCount,
        [Parameter(Mandatory = $true)][bool]$Truncated
    )

    $entries = @($FailedTests)
    if ($entries.Count -ne $FailedCount -or $Truncated) {
        throw 'Failed-test summary count or truncation binding drift.'
    }
    foreach ($entry in $entries) {
        $names = @($entry.PSObject.Properties.Name | Sort-Object)
        if (($names -join ',') -cne 'ErrorRecordCount,Name,RelativePath,StartLine') {
            throw 'Failed-test summary schema drift.'
        }
        if (
            [string]$entry.RelativePath -notmatch '^tests/(Contract|HostSandbox|Unit)/[A-Za-z0-9._-]+\.Tests\.ps1$' -or
            ($entry.StartLine -isnot [int] -and $entry.StartLine -isnot [long]) -or
            [long]$entry.StartLine -lt 1 -or
            ($entry.ErrorRecordCount -isnot [int] -and $entry.ErrorRecordCount -isnot [long]) -or
            [long]$entry.ErrorRecordCount -lt 1 -or
            [string]::IsNullOrWhiteSpace([string]$entry.Name) -or
            ([string]$entry.Name).Length -gt 512
        ) {
            throw 'Failed-test summary binding is invalid.'
        }
        $safeName = ConvertTo-CddsiSafeDiagnosticText -Text ([string]$entry.Name) -SkipTruncation
        if ($safeName -cne [string]$entry.Name) {
            throw 'Failed-test summary name contains unsafe diagnostic text.'
        }
    }
    return $true
}

function Assert-CddsiFailedTestSourceBinding {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$FailedTests,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string[]]$AllowedRelativePaths
    )

    $root = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    foreach ($failedTest in @($FailedTests)) {
        if ($AllowedRelativePaths -cnotcontains [string]$failedTest.RelativePath) {
            throw 'Pester shard failed-test source escaped the shard policy.'
        }
        $failedTestPath = [System.IO.Path]::GetFullPath(
            (Join-Path $root ([string]$failedTest.RelativePath)))
        if (-not $failedTestPath.StartsWith($root + '\', [StringComparison]::OrdinalIgnoreCase)) {
            throw 'Pester shard failed-test source escaped the repository.'
        }
        $tokens = $null
        $parseErrors = $null
        $sourceAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $failedTestPath, [ref]$tokens, [ref]$parseErrors)
        if (@($parseErrors).Count -ne 0) { throw 'Pester shard failed-test source has syntax errors.' }
        $matchingCommands = @($sourceAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.Extent.StartLineNumber -eq [long]$failedTest.StartLine -and
                $node.GetCommandName() -ceq 'It'
        }, $true))
        if ($matchingCommands.Count -ne 1 -or
            $matchingCommands[0].CommandElements.Count -lt 2 -or
            $matchingCommands[0].CommandElements[1] -isnot
                [System.Management.Automation.Language.StringConstantExpressionAst] -or
            [string]$matchingCommands[0].CommandElements[1].Value -cne [string]$failedTest.Name) {
            throw 'Pester shard failed-test source binding drift.'
        }
    }
    return $true
}

function New-CddsiQualityFailureProgress {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$CompletedRoleEvidence,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$CompletedWorkerIds,
        [AllowNull()]$CurrentWorkerDescriptor,
        [AllowNull()]$CurrentWorkerFailureEvidence,
        [Parameter(Mandatory = $true)][ValidateRange(0, 1000)][int]$ExpectedWorkerCount,
        [Parameter(Mandatory = $true)][bool]$TimedOut
    )

    $completedIds = @($CompletedWorkerIds)
    $derivedIds = @($CompletedRoleEvidence | ForEach-Object {
        if ($_.Engine -notin @('PowerShell7', 'WindowsPowerShell')) {
            throw 'Completed role evidence engine is invalid.'
        }
        if ($_.EvidenceType -ceq 'CddsiWorkerStaticEvidence') {
            '{0}/Static' -f $_.Engine
        }
        elseif (
            $_.EvidenceType -ceq 'CddsiWorkerPesterShardEvidence' -and
            [string]$_.ShardId -match '^(C0[1-8]|U0[1-2]|H0[1-3])$'
        ) {
            '{0}/{1}' -f $_.Engine, $_.ShardId
        }
        else {
            throw 'Completed role evidence type is invalid.'
        }
    })
    if (($derivedIds -join "`n") -cne ($completedIds -join "`n")) {
        throw 'Completed worker identities do not match role evidence.'
    }
    $completedShardEvidence = @($CompletedRoleEvidence | Where-Object {
        $_.EvidenceType -ceq 'CddsiWorkerPesterShardEvidence'
    })
    $currentEngine = ''
    $currentWorkerRole = ''
    $currentShardId = ''
    $phase = 'QualityHarness'
    if ($null -ne $CurrentWorkerDescriptor) {
        $phase = 'QualityWorker'
        $currentEngine = [string]$CurrentWorkerDescriptor.Engine
        $currentWorkerRole = [string]$CurrentWorkerDescriptor.WorkerRole
        $currentShardId = [string]$CurrentWorkerDescriptor.ShardId
    }
    $currentFailedCount = [long]0
    $currentFailedTests = @()
    $currentFailedTestEvidenceTruncated = $false
    if ($null -ne $CurrentWorkerFailureEvidence) {
        $currentFailedCount = [long]$CurrentWorkerFailureEvidence.Pester.FailedCount
        $currentFailedTests = @($CurrentWorkerFailureEvidence.Pester.FailedTests)
        $currentFailedTestEvidenceTruncated =
            [bool]$CurrentWorkerFailureEvidence.Pester.FailedTestEvidenceTruncated
    }

    $progress = [pscustomobject][ordered]@{
        SchemaVersion                     = 2
        Phase                             = $phase
        ExpectedWorkerCount               = $ExpectedWorkerCount
        CompletedWorkerCount              = $completedIds.Count
        CompletedWorkerIds                = $completedIds
        CompletedShardCount               = $completedShardEvidence.Count
        CompletedTestFileCount            = [long](($completedShardEvidence | ForEach-Object {
            @($_.TestFiles).Count
        } | Measure-Object -Sum).Sum)
        CompletedPassedCount              = [long](($completedShardEvidence | ForEach-Object {
            [long]$_.Pester.PassedCount
        } | Measure-Object -Sum).Sum)
        CurrentEngine                     = $currentEngine
        CurrentWorkerRole                 = $currentWorkerRole
        CurrentShardId                    = $currentShardId
        CurrentFailedCount                = $currentFailedCount
        CurrentFailedTests                = $currentFailedTests
        CurrentFailedTestEvidenceTruncated = $currentFailedTestEvidenceTruncated
        TimedOut                          = $TimedOut
    }
    $null = Assert-CddsiQualityFailureProgress -Progress $progress
    return $progress
}

function Assert-CddsiQualityFailureProgress {
    param([Parameter(Mandatory = $true)]$Progress)

    $expectedNames = @(
        'CompletedPassedCount', 'CompletedShardCount', 'CompletedTestFileCount',
        'CompletedWorkerCount', 'CompletedWorkerIds', 'CurrentEngine', 'CurrentFailedCount',
        'CurrentFailedTestEvidenceTruncated', 'CurrentFailedTests', 'CurrentShardId',
        'CurrentWorkerRole', 'ExpectedWorkerCount', 'Phase', 'SchemaVersion', 'TimedOut'
    )
    $actualNames = @($Progress.PSObject.Properties.Name | Sort-Object)
    if (($expectedNames -join "`n") -cne ($actualNames -join "`n")) {
        throw 'Quality failure progress schema drift.'
    }
    if (($Progress.SchemaVersion -isnot [int] -and $Progress.SchemaVersion -isnot [long]) -or
        [long]$Progress.SchemaVersion -ne 2) {
        throw 'Quality failure progress version is invalid.'
    }
    if ([string]$Progress.Phase -notin @('QualityHarness', 'QualityWorker')) {
        throw 'Quality failure progress phase is invalid.'
    }
    foreach ($countName in @('ExpectedWorkerCount', 'CompletedWorkerCount', 'CompletedShardCount')) {
        if (($Progress.$countName -isnot [int] -and $Progress.$countName -isnot [long]) -or
            [long]$Progress.$countName -lt 0) {
            throw 'Quality failure progress integer count is invalid.'
        }
    }
    foreach ($countName in @('CompletedTestFileCount', 'CompletedPassedCount')) {
        if (($Progress.$countName -isnot [int] -and $Progress.$countName -isnot [long]) -or
            [long]$Progress.$countName -lt 0) {
            throw 'Quality failure progress long count is invalid.'
        }
    }
    if (($Progress.CurrentFailedCount -isnot [int] -and $Progress.CurrentFailedCount -isnot [long]) -or
        [long]$Progress.CurrentFailedCount -lt 0 -or
        $Progress.CurrentFailedTestEvidenceTruncated -isnot [bool]) {
        throw 'Quality failure progress failed-test summary is invalid.'
    }
    $null = Assert-CddsiSafeFailedTestSummary `
        -FailedTests @($Progress.CurrentFailedTests) `
        -FailedCount ([long]$Progress.CurrentFailedCount) `
        -Truncated ([bool]$Progress.CurrentFailedTestEvidenceTruncated)
    $shardIds = @()
    switch ([int]$Progress.ExpectedWorkerCount) {
        0 {
            $shardIds = @()
            break
        }
        18 {
            $shardIds = @('C01', 'C02', 'C03', 'C04', 'C05', 'U01', 'U02', 'H01')
            break
        }
        20 {
            $shardIds = @('C04', 'C05', 'C06', 'C07', 'C08', 'U02', 'H01', 'H02', 'H03')
            break
        }
        28 {
            $shardIds = @('C01', 'C02', 'C03', 'C04', 'C05', 'C06', 'C07', 'C08', 'U01', 'U02', 'H01', 'H02', 'H03')
            break
        }
        default {
            throw 'Quality failure progress expected worker count is invalid.'
        }
    }
    $completedIds = @($Progress.CompletedWorkerIds)
    if ([long]$Progress.CompletedWorkerCount -ne $completedIds.Count -or
        [long]$Progress.CompletedWorkerCount -gt [long]$Progress.ExpectedWorkerCount) {
        throw 'Quality failure progress worker count is invalid.'
    }
    $expectedWorkerIds = if ([int]$Progress.ExpectedWorkerCount -eq 0) {
        @()
    }
    else {
        @(
            foreach ($engine in @('PowerShell7', 'WindowsPowerShell')) {
                '{0}/Static' -f $engine
                foreach ($shardId in $shardIds) { '{0}/{1}' -f $engine, $shardId }
            }
        )
    }
    $expectedCompletedPrefix = @()
    if ($completedIds.Count -gt 0) {
        $expectedCompletedPrefix = @($expectedWorkerIds[0..($completedIds.Count - 1)])
    }
    if (($completedIds -join "`n") -cne ($expectedCompletedPrefix -join "`n")) {
        throw 'Quality failure progress completed workers are not an exact plan prefix.'
    }
    $completedShardCount = @($completedIds | Where-Object { $_ -notmatch '/Static$' }).Count
    if ([int]$Progress.CompletedShardCount -ne $completedShardCount) {
        throw 'Quality failure progress shard count is invalid.'
    }
    if ($Progress.TimedOut -isnot [bool]) {
        throw 'Quality failure progress timeout flag is invalid.'
    }
    if ($Progress.Phase -ceq 'QualityWorker') {
        if ([string]$Progress.CurrentEngine -notin @('PowerShell7', 'WindowsPowerShell') -or
            [string]$Progress.CurrentWorkerRole -notin @('Static', 'PesterShard')) {
            throw 'Quality failure progress current worker is invalid.'
        }
        if ($Progress.CurrentWorkerRole -ceq 'Static' -and
            -not [string]::IsNullOrEmpty([string]$Progress.CurrentShardId)) {
            throw 'Quality failure progress static shard identity is invalid.'
        }
        if ($Progress.CurrentWorkerRole -ceq 'PesterShard' -and
            [string]$Progress.CurrentShardId -notmatch '^(C0[1-8]|U0[1-2]|H0[1-3])$') {
            throw 'Quality failure progress shard identity is invalid.'
        }
        $currentWorkerId = if ($Progress.CurrentWorkerRole -ceq 'Static') {
            '{0}/Static' -f $Progress.CurrentEngine
        }
        else {
            '{0}/{1}' -f $Progress.CurrentEngine, $Progress.CurrentShardId
        }
        if (
            [int]$Progress.ExpectedWorkerCount -eq 0 -or
            $completedIds.Count -ge $expectedWorkerIds.Count -or
            $currentWorkerId -cne $expectedWorkerIds[$completedIds.Count]
        ) {
            throw 'Quality failure progress current worker is not the next plan item.'
        }
        if ([string]$Progress.CurrentWorkerRole -cne 'PesterShard' -and
            [long]$Progress.CurrentFailedCount -ne 0) {
            throw 'Only a Pester shard may expose a failed-test summary.'
        }
    }
    elseif (
        -not [string]::IsNullOrEmpty([string]$Progress.CurrentEngine) -or
        -not [string]::IsNullOrEmpty([string]$Progress.CurrentWorkerRole) -or
        -not [string]::IsNullOrEmpty([string]$Progress.CurrentShardId) -or
        [long]$Progress.CurrentFailedCount -ne 0
    ) {
        throw 'Quality failure progress harness identity is invalid.'
    }
    return $true
}

function New-CddsiSafeFailureEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$Scenario,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$PrimaryFailureCode,
        [AllowNull()][string]$PrimaryFailureMessage,
        [Parameter(Mandatory = $true)][string]$CleanupOutcome,
        [Parameter(Mandatory = $true)][string]$CleanupFailureCode,
        [Parameter(Mandatory = $true)][bool]$RepositoryContentChanged,
        [Parameter(Mandatory = $true)]$Progress,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokens,
        [AllowNull()][string]$OwnershipToken,
        [AllowNull()][string]$CanaryValue
    )

    $safeMessage = Protect-CddsiHarnessText -Text $PrimaryFailureMessage -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
    $safeDisclosure = Test-CddsiSafeDiagnosticDisclosure -Text $safeMessage -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
    $null = Assert-CddsiQualityFailureProgress -Progress $Progress
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion            = 3
        EvidenceType             = 'CddsiSafeFailureEvidence'
        Scenario                 = $Scenario
        RunId                    = $RunId
        Status                   = 'FAILED_SAFE'
        PrimaryFailureCode       = $PrimaryFailureCode
        SafeFailureMessage       = $safeMessage
        CleanupOutcome           = $CleanupOutcome
        CleanupFailureCode       = $CleanupFailureCode
        RepositoryContentChanged = $RepositoryContentChanged
        Progress                 = $Progress
        SafeFailureDisclosure    = $safeDisclosure
    }
    $null = Assert-CddsiSafeFailureEvidence -Evidence $evidence -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
    return $evidence
}

function Assert-CddsiSafeFailureEvidence {
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokens,
        [AllowNull()][string]$OwnershipToken,
        [AllowNull()][string]$CanaryValue
    )

    $expectedNames = @(
        'CleanupFailureCode', 'CleanupOutcome', 'EvidenceType', 'PrimaryFailureCode',
        'Progress', 'RepositoryContentChanged', 'RunId', 'SafeFailureDisclosure', 'SafeFailureMessage',
        'Scenario', 'SchemaVersion', 'Status'
    )
    $actualNames = @($Evidence.PSObject.Properties.Name | Sort-Object)
    if (($expectedNames -join "`n") -cne ($actualNames -join "`n")) { throw 'Safe failure evidence schema drift.' }
    if (($Evidence.SchemaVersion -isnot [int] -and $Evidence.SchemaVersion -isnot [long]) -or
        [long]$Evidence.SchemaVersion -ne 3) { throw 'Safe failure evidence version is invalid.' }
    if ($Evidence.EvidenceType -cne 'CddsiSafeFailureEvidence' -or $Evidence.Status -cne 'FAILED_SAFE') { throw 'Safe failure evidence type is invalid.' }
    if ([string]$Evidence.RunId -notmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') { throw 'Safe failure evidence run binding is invalid.' }
    if ([string]$Evidence.PrimaryFailureCode -notmatch '^[A-Z0-9_]+$' -or [string]$Evidence.CleanupFailureCode -notmatch '^[A-Z0-9_]+$') { throw 'Safe failure evidence code is invalid.' }
    if ($Evidence.RepositoryContentChanged -isnot [bool] -or $Evidence.SafeFailureDisclosure -isnot [bool] -or -not $Evidence.SafeFailureDisclosure) { throw 'Safe failure disclosure validation failed.' }
    $null = Assert-CddsiQualityFailureProgress -Progress $Evidence.Progress
    if (-not (Test-CddsiSafeDiagnosticDisclosure -Text ([string]$Evidence.SafeFailureMessage) -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue)) { throw 'Safe failure evidence contains unsafe diagnostic text.' }
    return $true
}

function New-CddsiSafeFailureException {
    param([Parameter(Mandatory = $true)]$Evidence)

    $message = 'Isolated {0} scenario failed safely: {1}' -f $Evidence.Scenario, $Evidence.SafeFailureMessage
    $exception = New-Object System.InvalidOperationException($message)
    $exception.Data['CddsiFailureEvidenceJson'] = ($Evidence | ConvertTo-Json -Depth 6 -Compress)
    return $exception
}

function Assert-CddsiTrustedToolGrant {
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('PowerShell7', 'WindowsPowerShell', 'Git')]
        [string]$ToolId,

        [Parameter(Mandatory = $true)][string]$ExecutablePath,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedLeaf,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger
    )

    if (-not [System.IO.Path]::IsPathRooted($ExecutablePath)) {
        throw ('{0} grant must use an absolute executable path.' -f $ToolId)
    }
    if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw ('{0} grant must include an exact SHA-256.' -f $ToolId)
    }

    $fullPath = [System.IO.Path]::GetFullPath($ExecutablePath)
    if ((Split-Path -Leaf $fullPath) -cne $ExpectedLeaf) {
        throw ('{0} grant has an unexpected executable name.' -f $ToolId)
    }
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw ('{0} granted executable is unavailable.' -f $ToolId)
    }
    Assert-CddsiNoReparsePath -Path $fullPath -StopRoot ([System.IO.Path]::GetPathRoot($fullPath))
    $actualSha256 = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    if ($actualSha256 -cne $ExpectedSha256.ToLowerInvariant()) {
        throw ('{0} executable SHA-256 does not match its grant.' -f $ToolId)
    }

    $resourceToken = '<TOOL_{0}>' -f $ToolId.ToUpperInvariant()
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $RunId -Category FileSystem -RuleId ValidateToolGrant -ResourceToken $resourceToken -Outcome Succeeded -Data ([pscustomobject][ordered]@{
        ToolId = $ToolId
        Sha256 = $actualSha256
    })
    return [pscustomobject][ordered]@{
        ToolId        = $ToolId
        Path          = $fullPath
        Sha256        = $actualSha256
        ResourceToken = $resourceToken
    }
}

function Get-CddsiWindowsSystemContext {
    param([Parameter(Mandatory = $true)]$WindowsPowerShellGrant)

    $suffix = '\System32\WindowsPowerShell\v1.0\powershell.exe'
    $fullPath = [System.IO.Path]::GetFullPath($WindowsPowerShellGrant.Path)
    if (-not $fullPath.EndsWith($suffix, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'Windows PowerShell grant must identify the System32 Windows PowerShell 5.1 executable.'
    }
    $systemRoot = $fullPath.Substring(0, $fullPath.Length - $suffix.Length)
    if ([string]::IsNullOrWhiteSpace($systemRoot) -or -not (Test-Path -LiteralPath $systemRoot -PathType Container)) {
        throw 'Windows PowerShell grant does not bind a valid Windows root.'
    }
    Assert-CddsiNoReparsePath -Path $systemRoot -StopRoot ([System.IO.Path]::GetPathRoot($systemRoot))
    return [pscustomobject][ordered]@{
        SystemRoot = $systemRoot
        System32   = Join-Path $systemRoot 'System32'
        ComSpec    = Join-Path $systemRoot 'System32\cmd.exe'
    }
}

function New-CddsiMinimalEnvironment {
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]$WindowsContext,
        [Parameter(Mandatory = $true)][string]$PowerShellHome
    )

    $profile = [System.IO.Path]::GetFullPath($Sandbox.Paths.Profile)
    $homeDrive = [System.IO.Path]::GetPathRoot($profile).TrimEnd('\')
    $homePath = $profile.Substring($homeDrive.Length)
    $systemDrive = [System.IO.Path]::GetPathRoot([string]$WindowsContext.SystemRoot).TrimEnd('\')
    $modulePaths = @(
        Join-Path $RepositoryRoot '.dev\modules'
        Join-Path ([System.IO.Path]::GetFullPath($PowerShellHome)) 'Modules'
    )

    return [ordered]@{
        USERPROFILE                 = $profile
        HOME                        = $profile
        HOMEDRIVE                   = $homeDrive
        HOMEPATH                    = $homePath
        LOCALAPPDATA                = [string]$Sandbox.Paths.LocalAppData
        APPDATA                     = [string]$Sandbox.Paths.RoamingAppData
        PROGRAMDATA                 = [string]$Sandbox.Paths.ProgramData
        TEMP                        = [string]$Sandbox.Paths.Temp
        TMP                         = [string]$Sandbox.Paths.Temp
        XDG_CONFIG_HOME             = [string]$Sandbox.Paths.XdgConfig
        XDG_DATA_HOME               = [string]$Sandbox.Paths.XdgData
        SystemRoot                  = [string]$WindowsContext.SystemRoot
        WINDIR                      = [string]$WindowsContext.SystemRoot
        SystemDrive                 = $systemDrive
        ComSpec                     = [string]$WindowsContext.ComSpec
        PATH                        = [string]$WindowsContext.System32
        PATHEXT                     = '.COM;.EXE;.BAT;.CMD'
        PSModulePath                = ($modulePaths -join [System.IO.Path]::PathSeparator)
        GIT_CONFIG_NOSYSTEM         = '1'
        GIT_CONFIG_SYSTEM           = 'NUL'
        GIT_CONFIG_GLOBAL           = 'NUL'
        GIT_OPTIONAL_LOCKS          = '0'
        GIT_TERMINAL_PROMPT         = '0'
        GCM_INTERACTIVE             = 'Never'
        POWERSHELL_TELEMETRY_OPTOUT = '1'
        POWERSHELL_UPDATECHECK       = 'Off'
        DOTNET_CLI_TELEMETRY_OPTOUT = '1'
        CI                          = '1'
    }
}

function Get-CddsiStableMapHash {
    param([Parameter(Mandatory = $true)][System.Collections.IDictionary]$Map)

    $names = [string[]]@($Map.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    $lines = New-Object System.Collections.Generic.List[string]
    foreach ($name in $names) {
        $lines.Add(('{0}={1}' -f $name, [string]$Map[$name]))
    }
    return Get-CddsiSha256Text -Text ($lines -join [Environment]::NewLine)
}

function New-CddsiExpectedProcessRule {
    param(
        [Parameter(Mandatory = $true)][int]$Sequence,
        [Parameter(Mandatory = $true)][string]$RuleId,
        [Parameter(Mandatory = $true)]$ToolGrant,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Environment,
        [Parameter(Mandatory = $true)][string]$WorkingDirectoryToken
    )

    return [pscustomobject][ordered]@{
        Sequence              = $Sequence
        RuleId                = $RuleId
        ToolId                = $ToolGrant.ToolId
        ToolSha256            = $ToolGrant.Sha256
        ArgumentsSha256       = Get-CddsiSha256Text -Text ($Arguments -join ([char]0))
        EnvironmentSha256     = Get-CddsiStableMapHash -Map $Environment
        WorkingDirectoryToken = $WorkingDirectoryToken
        Count                 = 1
    }
}

function Get-CddsiRepositorySnapshot {
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $root = [System.IO.Path]::GetFullPath($RootPath).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { throw 'Repository root is unavailable.' }
    Assert-CddsiNoReparsePath -Path $root -StopRoot ([System.IO.Path]::GetPathRoot($root))

    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($root)
    $manifest = New-Object System.Collections.Generic.List[string]
    $fileCount = 0
    $directoryCount = 0
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if ([string]::Equals($directory, $root, [StringComparison]::OrdinalIgnoreCase) -and [string]::Equals($item.Name, '.git', [StringComparison]::OrdinalIgnoreCase)) { continue }
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'Repository snapshot refused a reparse point.'
            }
            $relative = $item.FullName.Substring($root.Length).TrimStart('\').Replace('\', '/')
            if ($item.PSIsContainer) {
                $manifest.Add(('D|{0}' -f $relative))
                $directoryCount++
                $queue.Enqueue($item.FullName)
                continue
            }
            $manifest.Add(('F|{0}|{1}|{2}' -f $relative, (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant(), [long]$item.Length))
            $fileCount++
        }
    }

    $manifestArray = [string[]]$manifest.ToArray()
    [Array]::Sort($manifestArray, [StringComparer]::Ordinal)
    return [pscustomobject][ordered]@{
        SchemaVersion  = 1
        Scope          = 'WorkingTreeExcludingDotGit'
        FileCount      = [int]$fileCount
        DirectoryCount = [int]$directoryCount
        Hash           = Get-CddsiSha256Text -Text ($manifestArray -join "`n")
        Manifest       = $manifestArray
    }
}

function Get-CddsiExpectedProcessRuleExact {
    param(
        [Parameter(Mandatory = $true)][object[]]$ExpectedProcessRules,
        [Parameter(Mandatory = $true)][string]$RuleId
    )

    $matches = @($ExpectedProcessRules | Where-Object { $_.RuleId -ceq $RuleId })
    if ($matches.Count -ne 1) { throw 'Expected process rule inventory drift.' }
    return $matches[0]
}

function New-CddsiExpectedProcessLedgerData {
    param([Parameter(Mandatory = $true)]$ExpectedProcessRule)

    return [pscustomobject][ordered]@{
        ToolId             = [string]$ExpectedProcessRule.ToolId
        ToolSha256         = [string]$ExpectedProcessRule.ToolSha256
        ArgumentsSha256    = [string]$ExpectedProcessRule.ArgumentsSha256
        EnvironmentSha256  = [string]$ExpectedProcessRule.EnvironmentSha256
        WorkingDirectory   = '<SANDBOX_ROOT>'
        ExitCode           = [int]0
        SecretFindingCount = [int]0
    }
}

function New-CddsiExpectedQualityHarnessLedger {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)]$PowerShell7Grant,
        [Parameter(Mandatory = $true)]$WindowsPowerShellGrant,
        [Parameter(Mandatory = $true)]$GitGrant,
        [Parameter(Mandatory = $true)][object[]]$ExpectedProcessRules,
        [Parameter(Mandatory = $true)][object[]]$WorkerInvocationPlan,
        [Parameter(Mandatory = $true)][int]$CanaryFileCount,
        [Parameter(Mandatory = $true)][int]$InventoryFileCount,
        [Parameter(Mandatory = $true)]$ArtifactScanEvidence,
        [switch]$IncludeCleanup
    )

    $entries = New-Object System.Collections.Generic.List[object]
    $sequence = 0
    foreach ($grant in @($PowerShell7Grant, $WindowsPowerShellGrant, $GitGrant)) {
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId ValidateToolGrant -ResourceToken $grant.ResourceToken -Outcome Succeeded -Data ([pscustomobject][ordered]@{ ToolId = [string]$grant.ToolId; Sha256 = [string]$grant.Sha256 })))
    }
    foreach ($entry in @(
        [pscustomobject]@{ RuleId = 'CreateSandbox'; ResourceToken = '<SANDBOX_ROOT>'; Data = $null }
        [pscustomobject]@{ RuleId = 'WriteOwnerMarker'; ResourceToken = '<SANDBOX_ROOT>/.cddsi-owner.json'; Data = $null }
        [pscustomobject]@{ RuleId = 'CreateSyntheticEnvironment'; ResourceToken = '<SANDBOX_ROOT>/synthetic'; Data = [pscustomobject][ordered]@{ CanaryFileCount = [int]$CanaryFileCount } }
    )) {
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId $entry.RuleId -ResourceToken $entry.ResourceToken -Outcome Succeeded -Data $entry.Data))
    }

    $gitInventoryRule = Get-CddsiExpectedProcessRuleExact -ExpectedProcessRules $ExpectedProcessRules -RuleId 'GitInventory'
    $sequence++
    $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category Process -RuleId GitInventory -ResourceToken $GitGrant.ResourceToken -Outcome Succeeded -Data (New-CddsiExpectedProcessLedgerData -ExpectedProcessRule $gitInventoryRule)))
    $sequence++
    $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId WriteRepositoryInventory -ResourceToken '<SANDBOX_ROOT>/state/repository-inventory.json' -Outcome Succeeded -Data ([pscustomobject][ordered]@{ FileCount = [int]$InventoryFileCount })))

    foreach ($worker in $WorkerInvocationPlan) {
        $rule = Get-CddsiExpectedProcessRuleExact -ExpectedProcessRules $ExpectedProcessRules -RuleId $worker.RuleId
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category Process -RuleId $worker.RuleId -ResourceToken $worker.Grant.ResourceToken -Outcome Succeeded -Data (New-CddsiExpectedProcessLedgerData -ExpectedProcessRule $rule)))
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId ReadWorkerEvidence -ResourceToken ('<SANDBOX_ROOT>/evidence/{0}' -f $worker.Leaf) -Outcome Succeeded -Data ([pscustomobject][ordered]@{
            Engine     = [string]$worker.Engine
            WorkerRole = [string]$worker.WorkerRole
            ShardId    = [string]$worker.ShardId
        })))
    }

    foreach ($ruleId in @('GitDiffCheck', 'GitCachedDiffCheck')) {
        $rule = Get-CddsiExpectedProcessRuleExact -ExpectedProcessRules $ExpectedProcessRules -RuleId $ruleId
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category Process -RuleId $ruleId -ResourceToken $GitGrant.ResourceToken -Outcome Succeeded -Data (New-CddsiExpectedProcessLedgerData -ExpectedProcessRule $rule)))
    }
    $sequence++
    $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId ScanSandboxArtifacts -ResourceToken '<SANDBOX_ROOT>' -Outcome Succeeded -Data ([pscustomobject][ordered]@{
        FileCount    = [int]$ArtifactScanEvidence.FileCount
        FindingCount = [int]$ArtifactScanEvidence.FindingCount
    })))
    if ($IncludeCleanup) {
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId CleanupSandbox -ResourceToken '<SANDBOX_ROOT>' -Outcome Succeeded -Data $null))
    }
    return $entries.ToArray()
}

function Get-CddsiSecretFindingCount {
    param(
        [AllowNull()][string]$Text,
        [AllowNull()][string]$CanaryValue,
        [int]$StartIndexExclusive = -1
    )

    if ([string]::IsNullOrEmpty($Text)) { return 0 }
    $indexLimit = if ($StartIndexExclusive -lt 0 -or $StartIndexExclusive -gt $Text.Length) {
        $Text.Length
    }
    else {
        $StartIndexExclusive
    }
    $patterns = @(
        '(?i)sk-[a-z0-9_-]{20,}'
        '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])'
        '(?i)"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?[a-z0-9._~-]{20,}'
    )
    $count = 0
    foreach ($pattern in $patterns) {
        $count += @([regex]::Matches($Text, $pattern) | Where-Object { $_.Index -lt $indexLimit }).Count
    }
    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $count += @([regex]::Matches($Text, '(?is)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----') | Where-Object { $_.Index -lt $indexLimit }).Count
    if (-not [string]::IsNullOrWhiteSpace($CanaryValue)) {
        $count += @([regex]::Matches($Text, [regex]::Escape($CanaryValue)) | Where-Object { $_.Index -lt $indexLimit }).Count
    }
    return $count
}

function Get-CddsiFileSecretFindingCount {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [AllowNull()][string]$CanaryValue,
        [AllowNull()][string]$OwnershipToken
    )

    $bufferSize = 65536
    $carrySize = 4096
    $buffer = New-Object byte[] $bufferSize
    $singleByteEncoding = [System.Text.Encoding]::GetEncoding(28591)
    $stream = New-Object System.IO.FileStream($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $carry = ''
    $findingCount = 0
    try {
        while (($read = $stream.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $combined = $carry + $singleByteEncoding.GetString($buffer, 0, $read)
            $isFinalChunk = $stream.Position -eq $stream.Length
            $scanStartLimit = if ($isFinalChunk) { $combined.Length } else { [Math]::Max(0, $combined.Length - $carrySize) }
            $findingCount += Get-CddsiSecretFindingCount -Text $combined -CanaryValue $CanaryValue -StartIndexExclusive $scanStartLimit
            if (-not [string]::IsNullOrWhiteSpace($OwnershipToken)) {
                $findingCount += @([regex]::Matches($combined, [regex]::Escape($OwnershipToken)) | Where-Object { $_.Index -lt $scanStartLimit }).Count
            }
            $carry = if ($isFinalChunk) { '' } else { $combined.Substring($scanStartLimit) }
        }
    }
    finally {
        $stream.Dispose()
    }
    return $findingCount
}

function Test-CddsiSandboxTextArtifactPath {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Sandbox
    )

    if ([string]::Equals($Path, $Sandbox.MarkerPath, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    foreach ($root in @($Sandbox.Paths.Evidence, $Sandbox.Paths.State, $Sandbox.Paths.Reports)) {
        if (Test-CddsiPathWithinRoot -Path $Path -Root $root) { return $true }
    }
    return $false
}

function Read-CddsiProcessTextTask {
    param(
        [Parameter(Mandatory = $true)]$Task,
        [Parameter(Mandatory = $true)][ValidateRange(1, 10000)][int]$WaitMilliseconds,
        [Parameter(Mandatory = $true)][string]$FailureText
    )

    try {
        if (-not $Task.Wait($WaitMilliseconds)) {
            return [pscustomobject][ordered]@{
                Succeeded = $false
                Text      = $FailureText
            }
        }
        return [pscustomobject][ordered]@{
            Succeeded = $true
            Text      = [string]$Task.Result
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            Succeeded = $false
            Text      = $FailureText
        }
    }
}

function Invoke-CddsiTrustedProcess {
    param(
        [Parameter(Mandatory = $true)][string]$RuleId,
        [Parameter(Mandatory = $true)]$ToolGrant,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$Arguments,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Environment,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][ValidateRange(1, 3600)][int]$TimeoutSeconds,
        [Parameter(Mandatory = $true)][object[]]$ExpectedProcessRules,
        [Parameter(Mandatory = $true)][ref]$ProcessOrdinal,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokens,
        [AllowNull()][string]$OwnershipToken,
        [AllowNull()][string]$CanaryValue
    )

    $argumentHash = Get-CddsiSha256Text -Text ($Arguments -join ([char]0))
    $environmentHash = Get-CddsiStableMapHash -Map $Environment
    $ordinal = [int]$ProcessOrdinal.Value
    $mismatchFields = New-Object System.Collections.Generic.List[string]
    $expectedRule = $null
    $ruleSchemaValid = $false
    if ($ordinal -ge $ExpectedProcessRules.Count) {
        $mismatchFields.Add('Sequence')
    }
    else {
        $expectedRule = $ExpectedProcessRules[$ordinal]
        $expectedNames = @('ArgumentsSha256', 'Count', 'EnvironmentSha256', 'RuleId', 'Sequence', 'ToolId', 'ToolSha256', 'WorkingDirectoryToken')
        $actualNames = @($expectedRule.PSObject.Properties.Name | Sort-Object)
        if (($expectedNames -join [Environment]::NewLine) -cne ($actualNames -join [Environment]::NewLine)) {
            $mismatchFields.Add('RuleSchema')
        }
        else {
            $ruleSchemaValid = $true
        }
    }

    $workingDirectoryToken = $null
    if ([string]::Equals((Get-CddsiCanonicalPath -Path $WorkingDirectory), (Get-CddsiCanonicalPath -Path $PathTokens['<SANDBOX_ROOT>']), [StringComparison]::OrdinalIgnoreCase)) {
        $workingDirectoryToken = '<SANDBOX_ROOT>'
    }
    else {
        $mismatchFields.Add('WorkingDirectoryToken')
    }
    try {
        Assert-CddsiNoReparsePath -Path $ToolGrant.Path -StopRoot ([System.IO.Path]::GetPathRoot($ToolGrant.Path))
        $actualToolSha256 = (Get-FileHash -LiteralPath $ToolGrant.Path -Algorithm SHA256).Hash.ToLowerInvariant()
    }
    catch {
        $actualToolSha256 = $null
        $mismatchFields.Add('ToolRevalidation')
    }

    if ($null -ne $expectedRule -and $ruleSchemaValid) {
        if ([int]$expectedRule.Sequence -ne $ordinal + 1) { $mismatchFields.Add('Sequence') }
        if ([int]$expectedRule.Count -ne 1) { $mismatchFields.Add('Count') }
        if ([string]$expectedRule.RuleId -cne $RuleId) { $mismatchFields.Add('RuleId') }
        if ([string]$expectedRule.ToolId -cne [string]$ToolGrant.ToolId) { $mismatchFields.Add('ToolId') }
        if ([string]$expectedRule.ToolSha256 -cne [string]$ToolGrant.Sha256 -or [string]$expectedRule.ToolSha256 -cne [string]$actualToolSha256) { $mismatchFields.Add('ToolSha256') }
        if ([string]$expectedRule.ArgumentsSha256 -cne $argumentHash) { $mismatchFields.Add('ArgumentsSha256') }
        if ([string]$expectedRule.EnvironmentSha256 -cne $environmentHash) { $mismatchFields.Add('EnvironmentSha256') }
        if ([string]$expectedRule.WorkingDirectoryToken -cne $workingDirectoryToken) { $mismatchFields.Add('WorkingDirectoryToken') }
    }
    if ($mismatchFields.Count -gt 0) {
        Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $RunId -Category Process -RuleId $RuleId -ResourceToken $ToolGrant.ResourceToken -Outcome Denied -Data ([pscustomobject][ordered]@{
            ExpectedSequence = $ordinal + 1
            MismatchFields   = @($mismatchFields | Sort-Object -Unique)
        })
        throw 'Trusted process invocation does not match the exact scenario grant.'
    }

    Assert-CddsiNoReparsePath -Path $WorkingDirectory -StopRoot $PathTokens['<SANDBOX_ROOT>']
    $ProcessOrdinal.Value = $ordinal + 1
    [System.Diagnostics.ProcessStartInfo]$startInfo = New-Object System.Diagnostics.ProcessStartInfo
    $startInfo.FileName = $ToolGrant.Path
    $startInfo.Arguments = Join-CddsiWindowsArguments -Arguments $Arguments
    $startInfo.WorkingDirectory = $WorkingDirectory
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardInput = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    if ($startInfo.PSObject.Properties.Name -contains 'StandardOutputEncoding') {
        $redirectedUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
        $startInfo.StandardOutputEncoding = $redirectedUtf8
        $startInfo.StandardErrorEncoding = $redirectedUtf8
    }
    $startInfo.EnvironmentVariables.Clear()
    foreach ($name in $Environment.Keys) {
        $startInfo.EnvironmentVariables[[string]$name] = [string]$Environment[$name]
    }

    [System.Diagnostics.Process]$process = New-Object System.Diagnostics.Process
    $process.StartInfo = $startInfo
    $stdout = ''
    $stderr = ''
    $exitCode = $null
    $outcome = 'Failed'
    try {
        if (-not $process.Start()) { throw 'Trusted process did not start.' }
        $process.StandardInput.Close()
        $stdoutTask = $process.StandardOutput.ReadToEndAsync()
        $stderrTask = $process.StandardError.ReadToEndAsync()
        if (-not $process.WaitForExit($TimeoutSeconds * 1000)) {
            $terminationComplete = $false
            try {
                if ($PSVersionTable.PSVersion.Major -ge 7) {
                    $process.Kill($true)
                }
                else {
                    $process.Kill()
                }
            }
            catch {
                try { $process.Kill() } catch { }
            }
            try { $terminationComplete = $process.WaitForExit(5000) } catch { $terminationComplete = $false }
            if ($terminationComplete) {
                $stdoutRead = Read-CddsiProcessTextTask -Task $stdoutTask -WaitMilliseconds 2000 -FailureText 'OUTPUT_DRAIN_TIMEOUT'
                $stderrRead = Read-CddsiProcessTextTask -Task $stderrTask -WaitMilliseconds 2000 -FailureText 'OUTPUT_DRAIN_TIMEOUT'
                $stdout = $stdoutRead.Text
                $stderr = $stderrRead.Text
            }
            else {
                $stdout = ''
                $stderr = 'PROCESS_TERMINATION_INCOMPLETE'
            }
            $outcome = 'TimedOut'
        }
        else {
            $process.WaitForExit()
            $exitCode = $process.ExitCode
            $stdoutRead = Read-CddsiProcessTextTask -Task $stdoutTask -WaitMilliseconds 5000 -FailureText 'OUTPUT_ENCODING_INVALID'
            $stderrRead = Read-CddsiProcessTextTask -Task $stderrTask -WaitMilliseconds 5000 -FailureText 'OUTPUT_ENCODING_INVALID'
            if (-not $stdoutRead.Succeeded -or -not $stderrRead.Succeeded) {
                $stdout = ''
                $stderr = 'OUTPUT_ENCODING_INVALID'
                $outcome = 'Failed'
            }
            else {
                $stdout = $stdoutRead.Text
                $stderr = $stderrRead.Text
                if ($exitCode -eq 0) { $outcome = 'Succeeded' }
            }
        }
    }
    catch {
        $stderr = [string]$_.Exception.Message
        $outcome = 'Failed'
    }
    finally {
        $process.Dispose()
    }

    $secretFindingCount = (Get-CddsiSecretFindingCount -Text $stdout -CanaryValue $CanaryValue) + (Get-CddsiSecretFindingCount -Text $stderr -CanaryValue $CanaryValue)
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $RunId -Category Process -RuleId $RuleId -ResourceToken $ToolGrant.ResourceToken -Outcome $outcome -Data ([pscustomobject][ordered]@{
        ToolId             = $ToolGrant.ToolId
        ToolSha256         = $ToolGrant.Sha256
        ArgumentsSha256    = $argumentHash
        EnvironmentSha256  = $environmentHash
        WorkingDirectory   = '<SANDBOX_ROOT>'
        ExitCode           = $exitCode
        SecretFindingCount = $secretFindingCount
    })

    if ($secretFindingCount -gt 0) { throw 'Trusted process output contained a secret or synthetic canary.' }
    if ($outcome -eq 'TimedOut') {
        $timeoutTail = Get-CddsiUnicodeSafeTail -Text ($stderr + [Environment]::NewLine + $stdout) -MaximumLength 5000
        $safeTimeoutTail = Protect-CddsiHarnessText -Text $timeoutTail -PathTokens $PathTokens `
            -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
        if ([string]::IsNullOrWhiteSpace($safeTimeoutTail)) { $safeTimeoutTail = 'NO_SAFE_OUTPUT' }
        $timeoutException = New-Object System.TimeoutException(
            ('Trusted process timed out: {0}. Last safe output: {1}' -f `
                $RuleId, $safeTimeoutTail.Trim())
        )
        $timeoutException.Data['CddsiProcessFailureCode'] = 'PROCESS_TIMEOUT'
        $timeoutException.Data['CddsiProcessRuleId'] = $RuleId
        $timeoutException.Data['CddsiProcessTerminationComplete'] = $terminationComplete
        throw $timeoutException
    }
    if ($outcome -ne 'Succeeded') {
        $safeOutput = Protect-CddsiHarnessText -Text ($stderr + [Environment]::NewLine + $stdout) -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
        throw ('Trusted process failed: {0}. {1}' -f $RuleId, $safeOutput.Trim())
    }
    return [pscustomobject][ordered]@{
        RuleId   = $RuleId
        ExitCode = $exitCode
        StdOut   = $stdout
        StdErr   = $stderr
    }
}

function Write-CddsiRepositoryInventory {
    param(
        [Parameter(Mandatory = $true)][string]$GitOutput,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger
    )

    $repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $rawPaths = @($GitOutput.Split([char]0) | Where-Object { -not [string]::IsNullOrEmpty($_) })
    $safePaths = New-Object System.Collections.Generic.List[string]
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::OrdinalIgnoreCase)
    foreach ($rawPath in $rawPaths) {
        $relative = ([string]$rawPath).Replace('\', '/')
        if ([System.IO.Path]::IsPathRooted($relative) -or $relative.IndexOf([char]0) -ge 0) {
            throw 'Git inventory returned an unsafe rooted path.'
        }
        $segments = @($relative.Split('/'))
        if ($segments.Count -eq 0 -or @($segments | Where-Object { $_ -eq '..' -or $_ -eq '.' -or $_ -eq '' }).Count -gt 0) {
            throw 'Git inventory returned an unsafe relative path.'
        }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRootFull $relative))
        if (-not (Test-CddsiPathWithinRoot -Path $fullPath -Root $repositoryRootFull)) {
            throw 'Git inventory escaped the repository root.'
        }
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
            throw 'Git inventory referenced a missing repository file.'
        }
        Assert-CddsiNoReparsePath -Path $fullPath -StopRoot $repositoryRootFull
        if (-not $seen.Add($relative)) { throw 'Git inventory contained a duplicate path.' }
        $safePaths.Add($relative)
    }
    $paths = $safePaths.ToArray()
    [Array]::Sort($paths, [StringComparer]::Ordinal)

    $inventoryPath = Join-Path $Sandbox.Paths.State 'repository-inventory.json'
    $inventory = [pscustomobject][ordered]@{
        SchemaVersion                 = 1
        RunId                         = $Sandbox.RunId
        RepositoryRootBindingSha256   = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($repositoryRootFull).ToUpperInvariant())
        Paths                         = @($paths)
    }
    Write-CddsiUtf8CreateNew -Path $inventoryPath -Content (($inventory | ConvertTo-Json -Depth 4) + [Environment]::NewLine)
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $Sandbox.RunId -Category FileSystem -RuleId WriteRepositoryInventory -ResourceToken '<SANDBOX_ROOT>/state/repository-inventory.json' -Outcome Succeeded -Data ([pscustomobject]@{ FileCount = $paths.Count })
    return [pscustomobject][ordered]@{
        Path      = $inventoryPath
        FileCount = [int]$paths.Count
        Sha256    = (Get-FileHash -LiteralPath $inventoryPath -Algorithm SHA256).Hash.ToLowerInvariant()
    }
}

function Get-CddsiRepositoryInventoryMeasurement {
    param(
        [Parameter(Mandatory = $true)][string]$InventoryPath,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]$Sandbox
    )

    $inventoryFullPath = [System.IO.Path]::GetFullPath($InventoryPath)
    if (-not (Test-CddsiPathWithinRoot -Path $inventoryFullPath -Root $Sandbox.Root)) { throw 'Repository inventory measurement path escaped the sandbox.' }
    Assert-CddsiNoReparsePath -Path $inventoryFullPath -StopRoot $Sandbox.Root
    $bytes = [System.IO.File]::ReadAllBytes($inventoryFullPath)
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $text = $strictUtf8.GetString($bytes) } catch { throw 'Repository inventory measurement is not strict UTF-8.' }
    $inventory = $text | ConvertFrom-Json -ErrorAction Stop
    $inventoryNames = @($inventory.PSObject.Properties.Name | Sort-Object)
    if (($inventoryNames -join ',') -cne 'Paths,RepositoryRootBindingSha256,RunId,SchemaVersion') { throw 'Repository inventory measurement schema drift.' }
    if ($inventory.SchemaVersion -ne 1 -or $inventory.RunId -cne $Sandbox.RunId) { throw 'Repository inventory measurement run binding drift.' }
    $repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    $expectedRootBinding = Get-CddsiSha256Text -Text ($repositoryRootFull.ToUpperInvariant())
    if ($inventory.RepositoryRootBindingSha256 -cne $expectedRootBinding) { throw 'Repository inventory measurement root binding drift.' }
    $paths = [string[]]@($inventory.Paths | ForEach-Object { [string]$_ })
    $sortedPaths = [string[]]$paths.Clone()
    [Array]::Sort($sortedPaths, [StringComparer]::Ordinal)
    if (($paths -join "`n") -cne ($sortedPaths -join "`n")) { throw 'Repository inventory measurement is not ordinal sorted.' }
    $seen = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    $manifest = New-Object System.Collections.Generic.List[string]
    foreach ($relativePath in $paths) {
        if ([string]::IsNullOrWhiteSpace($relativePath) -or [System.IO.Path]::IsPathRooted($relativePath) -or -not $seen.Add($relativePath)) { throw 'Repository inventory measurement contains an unsafe or duplicate path.' }
        $segments = @($relativePath.Replace('\', '/').Split('/'))
        if (@($segments | Where-Object { $_ -eq '' -or $_ -eq '.' -or $_ -eq '..' }).Count -gt 0) { throw 'Repository inventory measurement contains an unsafe path segment.' }
        $fullPath = [System.IO.Path]::GetFullPath((Join-Path $repositoryRootFull $relativePath))
        if (-not (Test-CddsiPathWithinRoot -Path $fullPath -Root $repositoryRootFull) -or -not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw 'Repository inventory measurement path is unavailable.' }
        Assert-CddsiNoReparsePath -Path $fullPath -StopRoot $repositoryRootFull
        $manifest.Add(('{0}|{1}' -f $relativePath.Replace('\', '/'), (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()))
    }
    return [pscustomobject][ordered]@{
        InventorySha256 = (Get-FileHash -LiteralPath $inventoryFullPath -Algorithm SHA256).Hash.ToLowerInvariant()
        ManifestSha256  = Get-CddsiSha256Text -Text ($manifest.ToArray() -join "`n")
        FileCount       = [int]$paths.Count
    }
}

function Get-CddsiWorkerEvidenceLeaf {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('PowerShell7', 'WindowsPowerShell')][string]$Engine,
        [Parameter(Mandatory = $true)][ValidateSet('Static', 'PesterShard')][string]$WorkerRole,
        [AllowEmptyString()][string]$ShardId = ''
    )

    $engineToken = if ($Engine -ceq 'PowerShell7') { 'powershell7' } else { 'windows-powershell' }
    if ($WorkerRole -ceq 'Static') {
        if (-not [string]::IsNullOrEmpty($ShardId)) { throw 'Static worker leaf cannot bind a shard id.' }
        return "worker-$engineToken-static.json"
    }
    if ($ShardId -cnotmatch '^[CHU][0-9]{2}$') { throw 'Pester shard leaf requires a valid shard id.' }
    return ('worker-{0}-shard-{1}.json' -f $engineToken, $ShardId.ToLowerInvariant())
}

function New-CddsiQualityWorkerInvocationPlan {
    param(
        [Parameter(Mandatory = $true)][string[]]$WorkerCommonArguments,
        [Parameter(Mandatory = $true)]$QualityShardPolicy,
        [Parameter(Mandatory = $true)]$PowerShell7Grant,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PowerShell7Environment,
        [Parameter(Mandatory = $true)]$WindowsPowerShellGrant,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$WindowsPowerShellEnvironment,
        [Parameter(Mandatory = $true)][int]$FirstSequence
    )

    $plan = New-Object System.Collections.Generic.List[object]
    $sequence = $FirstSequence
    foreach ($engineSpec in @(
        [pscustomobject]@{ Engine = 'PowerShell7'; RuleToken = 'PowerShell7'; Grant = $PowerShell7Grant; Environment = $PowerShell7Environment }
        [pscustomobject]@{ Engine = 'WindowsPowerShell'; RuleToken = 'WindowsPowerShell'; Grant = $WindowsPowerShellGrant; Environment = $WindowsPowerShellEnvironment }
    )) {
        $engineArguments = $WorkerCommonArguments + @(
            '-EngineId', $engineSpec.Engine,
            '-EngineExecutablePath', $engineSpec.Grant.Path,
            '-EngineGrantSha256', $engineSpec.Grant.Sha256
        )
        $plan.Add([pscustomobject][ordered]@{
            Sequence    = $sequence
            RuleId      = 'QualityStatic' + $engineSpec.RuleToken
            Engine      = $engineSpec.Engine
            WorkerRole  = 'Static'
            ShardId     = ''
            Grant       = $engineSpec.Grant
            Environment = $engineSpec.Environment
            Arguments   = $engineArguments + @('-WorkerRole', 'Static')
            Leaf        = Get-CddsiWorkerEvidenceLeaf -Engine $engineSpec.Engine -WorkerRole Static
        })
        $sequence++
        foreach ($shard in $QualityShardPolicy.QualityShards) {
            $plan.Add([pscustomobject][ordered]@{
                Sequence    = $sequence
                RuleId      = 'QualityShard' + $engineSpec.RuleToken + $shard.ShardId
                Engine      = $engineSpec.Engine
                WorkerRole  = 'PesterShard'
                ShardId     = $shard.ShardId
                Grant       = $engineSpec.Grant
                Environment = $engineSpec.Environment
                Arguments   = $engineArguments + @('-WorkerRole', 'PesterShard', '-ShardId', $shard.ShardId)
                Leaf        = Get-CddsiWorkerEvidenceLeaf -Engine $engineSpec.Engine -WorkerRole PesterShard -ShardId $shard.ShardId
            })
            $sequence++
        }
    }
    return $plan.ToArray()
}

function Get-CddsiRequiredSuiteSummarySha256 {
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$SuiteResults
    )

    $lines = @($SuiteResults | ForEach-Object {
        '{0}|{1}|{2}' -f ([string]$_.RelativePath).Replace('\', '/'), [long]$_.TestCount, [string]$_.Result
    })
    return Get-CddsiSha256Text -Text ($lines -join "`n")
}

function Get-CddsiWorkerProvenanceBindingDrift {
    param(
        [Parameter(Mandatory = $true)]$Actual,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Expected
    )

    $names = [string[]]@($Expected.Keys | ForEach-Object { [string]$_ })
    [Array]::Sort($names, [StringComparer]::Ordinal)
    return @($names | Where-Object { [string]$Actual.$_ -cne [string]$Expected[$_] })
}

function Read-CddsiWorkerIsolationEvidence {
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][ValidateSet('PowerShell7', 'WindowsPowerShell')][string]$Engine,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)]$EngineGrant,
        [Parameter(Mandatory = $true)][string]$RepositoryInventoryPath,
        [Parameter(Mandatory = $true)][string]$BoundaryManifestPath,
        [Parameter(Mandatory = $true)][string]$DependencyManifestPath,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger
    )

    $leaf = if ($Engine -ceq 'PowerShell7') { 'worker-powershell7.json' } else { 'worker-windows-powershell.json' }
    $path = Join-Path $Sandbox.Paths.Evidence $leaf
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Required worker isolation evidence is missing.' }
    Assert-CddsiNoReparsePath -Path $path -StopRoot $Sandbox.Root
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw 'Worker isolation evidence must be UTF-8 without BOM.' }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $text = $strictUtf8.GetString($bytes) } catch { throw 'Worker isolation evidence is not strict UTF-8.' }
    if ((Get-CddsiSecretFindingCount -Text $text -CanaryValue $Sandbox.CanaryValue) -gt 0 -or $text.Contains($Sandbox.OwnershipToken)) {
        throw 'Worker isolation evidence contains a secret, canary, or ownership token.'
    }
    $evidence = $text | ConvertFrom-Json -ErrorAction Stop
    $expectedNames = @('Engine', 'EvidenceType', 'Measurements', 'Provenance', 'RunId', 'SandboxBindingSha256', 'SchemaVersion')
    $actualNames = @($evidence.PSObject.Properties.Name | Sort-Object)
    if (($expectedNames -join [Environment]::NewLine) -cne ($actualNames -join [Environment]::NewLine)) { throw 'Worker isolation evidence schema drift.' }
    $expectedBinding = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($Sandbox.Root).ToUpperInvariant())
    if ($evidence.SchemaVersion -ne 2 -or $evidence.EvidenceType -cne 'CddsiWorkerIsolationEvidence' -or $evidence.RunId -cne $Sandbox.RunId -or $evidence.Engine -cne $Engine -or $evidence.SandboxBindingSha256 -cne $expectedBinding) {
        throw 'Worker isolation evidence binding is invalid.'
    }

    $measurementNames = @(
        'AccessLedger', 'AstSyntaxErrorCount', 'LiveAdapterFileCount', 'LiveProviderLoaded',
        'MutationSpyCounts', 'Pester', 'RepositoryContentChanged', 'RequiredSuiteFailureCount',
        'RequiredSuiteResults', 'SecretFindingCount'
    ) | Sort-Object
    $actualMeasurementNames = @($evidence.Measurements.PSObject.Properties.Name | Sort-Object)
    if (($measurementNames -join "`n") -cne ($actualMeasurementNames -join "`n")) { throw 'Worker measurement schema drift.' }
    foreach ($booleanName in @('LiveProviderLoaded', 'RepositoryContentChanged')) {
        if ($evidence.Measurements.$booleanName -isnot [bool] -or [bool]$evidence.Measurements.$booleanName) { throw "Worker measurement is not false: $booleanName" }
    }
    foreach ($zeroName in @('AstSyntaxErrorCount', 'RequiredSuiteFailureCount', 'SecretFindingCount')) {
        $value = $evidence.Measurements.$zeroName
        if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -ne 0) { throw "Worker measurement is not integer zero: $zeroName" }
    }
    $boundaryPolicy = Import-PowerShellDataFile -LiteralPath $BoundaryManifestPath
    $expectedLiveAdapterFileCount = @($boundaryPolicy.Planes.LiveAdapters).Count
    $actualLiveAdapterFileCount = $evidence.Measurements.LiveAdapterFileCount
    if (
        ($actualLiveAdapterFileCount -isnot [int] -and $actualLiveAdapterFileCount -isnot [long]) -or
        [long]$actualLiveAdapterFileCount -ne [long]$expectedLiveAdapterFileCount
    ) {
        throw 'Worker live-adapter inventory count does not match the bound execution policy.'
    }
    $accessNames = @(
        'ContextCount', 'DryRunContextCount', 'EntryCount', 'ForbiddenResourceAccessCount',
        'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount', 'ProductNetworkRequestCount',
        'RealRegistryAccessCount', 'TestSafeContextCount', 'UnexpectedLedgerEntryCount'
    ) | Sort-Object
    $actualAccessNames = @($evidence.Measurements.AccessLedger.PSObject.Properties.Name | Sort-Object)
    if (($accessNames -join "`n") -cne ($actualAccessNames -join "`n")) { throw 'Worker access-ledger measurement schema drift.' }
    foreach ($name in $accessNames) {
        $value = $evidence.Measurements.AccessLedger.$name
        if ($value -isnot [int] -and $value -isnot [long]) { throw "Worker access-ledger measurement is not an integer: $name" }
    }
    if ([long]$evidence.Measurements.AccessLedger.ContextCount -ne 2 -or [long]$evidence.Measurements.AccessLedger.TestSafeContextCount -ne 1 -or [long]$evidence.Measurements.AccessLedger.DryRunContextCount -ne 1 -or [long]$evidence.Measurements.AccessLedger.EntryCount -ne 2) { throw 'Worker access-ledger scenario count drift.' }
    foreach ($zeroName in @('ForbiddenResourceAccessCount', 'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount', 'ProductNetworkRequestCount', 'RealRegistryAccessCount', 'UnexpectedLedgerEntryCount')) {
        if ([long]$evidence.Measurements.AccessLedger.$zeroName -ne 0) { throw "Worker access-ledger measurement is not zero: $zeroName" }
    }

    $mutationNames = @('AppX', 'Credential', 'Environment', 'Feature', 'FileSystem', 'Network', 'Process', 'Registry', 'Restart', 'Service')
    $actualMutationNames = @($evidence.Measurements.MutationSpyCounts.PSObject.Properties.Name | Sort-Object)
    if (($mutationNames -join [Environment]::NewLine) -cne ($actualMutationNames -join [Environment]::NewLine)) { throw 'Worker mutation-spy evidence schema drift.' }
    foreach ($mutationName in $mutationNames) {
        $value = $evidence.Measurements.MutationSpyCounts.$mutationName
        if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -ne 0) { throw "Worker mutation spy is not integer zero: $mutationName" }
    }

    $pesterNames = @('FailedCount', 'InconclusiveCount', 'NotRunCount', 'PassedCount', 'Result', 'SkippedCount')
    $actualPesterNames = @($evidence.Measurements.Pester.PSObject.Properties.Name | Sort-Object)
    if (($pesterNames -join "`n") -cne ($actualPesterNames -join "`n")) { throw 'Worker Pester measurement schema drift.' }
    if ($evidence.Measurements.Pester.Result -cne 'Passed' -or [long]$evidence.Measurements.Pester.PassedCount -le 0) { throw 'Worker Pester measurement is not clean.' }
    foreach ($zeroName in @('FailedCount', 'InconclusiveCount', 'NotRunCount', 'SkippedCount')) {
        if ([long]$evidence.Measurements.Pester.$zeroName -ne 0) { throw "Worker Pester measurement is not zero: $zeroName" }
    }

    $lock = Import-PowerShellDataFile -LiteralPath $DependencyManifestPath
    $suitePolicy = @($lock.IsolationEvidenceSuites)
    $suiteEvidence = @($evidence.Measurements.RequiredSuiteResults)
    if ($suiteEvidence.Count -ne $suitePolicy.Count) { throw 'Worker required-suite evidence count drift.' }
    foreach ($suite in $suitePolicy) {
        $relativePath = ([string]$suite.RelativePath).Replace('\', '/')
        $matches = @($suiteEvidence | Where-Object { $_.RelativePath -ceq $relativePath })
        if ($matches.Count -ne 1) { throw 'Worker required-suite evidence inventory drift.' }
        $suiteResult = $matches[0]
        $suiteNames = @($suiteResult.PSObject.Properties.Name | Sort-Object)
        if (($suiteNames -join ',') -cne 'RelativePath,Result,TestCount') { throw 'Worker required-suite evidence schema drift.' }
        if ($suiteResult.Result -cne 'Passed' -or [int]$suiteResult.TestCount -ne [int]$suite.ExpectedTestCount) { throw 'Worker required-suite evidence is not clean.' }
    }

    $provenanceNames = @(
        'DependencyManifestSha256', 'EngineGrantSha256', 'ExecutionBoundaryManifestSha256',
        'FinalRepositoryManifestSha256', 'InitialRepositoryManifestSha256', 'MeasurementRuleVersion',
        'PesterTreeSha256', 'RepositoryInventorySha256', 'RequiredSuiteSummarySha256'
    ) | Sort-Object
    $actualProvenanceNames = @($evidence.Provenance.PSObject.Properties.Name | Sort-Object)
    if (($provenanceNames -join "`n") -cne ($actualProvenanceNames -join "`n")) { throw 'Worker provenance schema drift.' }
    foreach ($shaName in @($provenanceNames | Where-Object { $_ -ne 'MeasurementRuleVersion' })) {
        if ([string]$evidence.Provenance.$shaName -notmatch '^[a-f0-9]{64}$') { throw "Worker provenance SHA-256 is invalid: $shaName" }
    }
    $inventoryMeasurement = Get-CddsiRepositoryInventoryMeasurement -InventoryPath $RepositoryInventoryPath -RepositoryRoot $RepositoryRoot -Sandbox $Sandbox
    $expectedProvenance = [ordered]@{
        MeasurementRuleVersion          = 'cddsi-worker-measurement-rules-v2'
        RepositoryInventorySha256       = $inventoryMeasurement.InventorySha256
        InitialRepositoryManifestSha256 = $inventoryMeasurement.ManifestSha256
        FinalRepositoryManifestSha256   = $inventoryMeasurement.ManifestSha256
        ExecutionBoundaryManifestSha256 = (Get-FileHash -LiteralPath $BoundaryManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        DependencyManifestSha256        = (Get-FileHash -LiteralPath $DependencyManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        RequiredSuiteSummarySha256      = Get-CddsiRequiredSuiteSummarySha256 -SuiteResults $suiteEvidence
        PesterTreeSha256                = [string]$lock.Pester.ExpectedTreeSha256
        EngineGrantSha256               = [string]$EngineGrant.Sha256
    }
    $provenanceDrift = @(Get-CddsiWorkerProvenanceBindingDrift -Actual $evidence.Provenance -Expected $expectedProvenance)
    if ($provenanceDrift.Count -gt 0) {
        throw ('Worker provenance binding drift: {0}.' -f ($provenanceDrift -join ', '))
    }
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $Sandbox.RunId -Category FileSystem -RuleId ReadWorkerEvidence -ResourceToken ('<SANDBOX_ROOT>/evidence/{0}' -f $leaf) -Outcome Succeeded -Data ([pscustomobject]@{ Engine = $Engine })
    return $evidence
}

function Read-CddsiWorkerRoleEvidence {
    param(
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$RepositoryRoot,
        [Parameter(Mandatory = $true)][string]$RepositoryInventoryPath,
        [Parameter(Mandatory = $true)][string]$BoundaryManifestPath,
        [Parameter(Mandatory = $true)][string]$DependencyManifestPath,
        [Parameter(Mandatory = $true)]$QualityShardPolicy,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger,
        [ValidateSet('CleanCompletion', 'HistoricalCompletion', 'FailureProgressOnly')]
        [string]$ReadMode = 'CleanCompletion'
    )

    $path = Join-Path $Sandbox.Paths.Evidence $Descriptor.Leaf
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) { throw 'Required worker role evidence is missing.' }
    Assert-CddsiNoReparsePath -Path $path -StopRoot $Sandbox.Root
    $bytes = [System.IO.File]::ReadAllBytes($path)
    if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        throw 'Worker role evidence must be UTF-8 without BOM.'
    }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { $text = $strictUtf8.GetString($bytes) } catch { throw 'Worker role evidence is not strict UTF-8.' }
    if ((Get-CddsiSecretFindingCount -Text $text -CanaryValue $Sandbox.CanaryValue) -gt 0 -or $text.Contains($Sandbox.OwnershipToken)) {
        throw 'Worker role evidence contains a secret, canary, or ownership token.'
    }
    $evidence = $text | ConvertFrom-Json -ErrorAction Stop
    $expectedBinding = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($Sandbox.Root).ToUpperInvariant())
    $expectedSchemaVersion = if ($Descriptor.WorkerRole -ceq 'Static') { 1L } else { 2L }
    if (
        ($evidence.SchemaVersion -isnot [int] -and $evidence.SchemaVersion -isnot [long]) -or
        [long]$evidence.SchemaVersion -ne $expectedSchemaVersion -or
        $evidence.RunId -cne $Sandbox.RunId -or
        $evidence.Engine -cne $Descriptor.Engine -or
        $evidence.SandboxBindingSha256 -cne $expectedBinding
    ) {
        throw 'Worker role evidence binding is invalid.'
    }
    if ($Descriptor.WorkerRole -ceq 'Static' -and $ReadMode -cne 'CleanCompletion') {
        throw 'Static worker evidence supports only clean-completion reads.'
    }
    if (
        $ReadMode -ceq 'HistoricalCompletion' -and
        [string]$QualityShardPolicy.QualitySet -cne 'HistoricalDiagnostic'
    ) {
        throw 'Historical-completion evidence requires the historical diagnostic quality set.'
    }

    $inventoryMeasurement = Get-CddsiRepositoryInventoryMeasurement `
        -InventoryPath $RepositoryInventoryPath `
        -RepositoryRoot $RepositoryRoot `
        -Sandbox $Sandbox
    $lock = Import-PowerShellDataFile -LiteralPath $DependencyManifestPath
    $expectedCommonProvenance = [ordered]@{
        MeasurementRuleVersion          = 'cddsi-worker-measurement-rules-v6'
        RepositoryInventorySha256       = $inventoryMeasurement.InventorySha256
        InitialRepositoryManifestSha256 = $inventoryMeasurement.ManifestSha256
        FinalRepositoryManifestSha256   = $inventoryMeasurement.ManifestSha256
        DependencyManifestSha256        = (Get-FileHash -LiteralPath $DependencyManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        PesterTreeSha256                = [string]$lock.Pester.ExpectedTreeSha256
        EngineGrantSha256               = [string]$Descriptor.Grant.Sha256
        QualityShardPolicySha256        = [string]$QualityShardPolicy.CanonicalSha256
    }

    if ($Descriptor.WorkerRole -ceq 'Static') {
        $expectedNames = @('Engine', 'EvidenceType', 'Measurements', 'Provenance', 'RunId', 'SandboxBindingSha256', 'SchemaVersion')
        if ((@($evidence.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($expectedNames -join "`n") -or
            $evidence.EvidenceType -cne 'CddsiWorkerStaticEvidence') {
            throw 'Static worker evidence schema drift.'
        }
        $measurementNames = @(
            'AccessLedger', 'AstSyntaxErrorCount', 'LiveAdapterFileCount', 'LiveProviderLoaded',
            'MutationSpyCounts', 'RepositoryContentChanged', 'SecretFindingCount'
        ) | Sort-Object
        if ((@($evidence.Measurements.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($measurementNames -join "`n")) {
            throw 'Static worker measurement schema drift.'
        }
        if ($evidence.Measurements.LiveProviderLoaded -isnot [bool] -or $evidence.Measurements.LiveProviderLoaded -or
            $evidence.Measurements.RepositoryContentChanged -isnot [bool] -or $evidence.Measurements.RepositoryContentChanged) {
            throw 'Static worker Boolean evidence is not clean.'
        }
        foreach ($name in @('AstSyntaxErrorCount', 'SecretFindingCount')) {
            $value = $evidence.Measurements.$name
            if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -ne 0) {
                throw "Static worker measurement is not integer zero: $name"
            }
        }
        $boundary = Import-PowerShellDataFile -LiteralPath $BoundaryManifestPath
        $liveAdapterFileCount = $evidence.Measurements.LiveAdapterFileCount
        if (($liveAdapterFileCount -isnot [int] -and $liveAdapterFileCount -isnot [long]) -or
            [long]$liveAdapterFileCount -ne @($boundary.Planes.LiveAdapters).Count) {
            throw 'Static worker live-adapter count drift.'
        }
        $accessNames = @(
            'ContextCount', 'DryRunContextCount', 'EntryCount', 'ForbiddenResourceAccessCount',
            'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount', 'ProductNetworkRequestCount',
            'RealRegistryAccessCount', 'TestSafeContextCount', 'UnexpectedLedgerEntryCount'
        ) | Sort-Object
        if ((@($evidence.Measurements.AccessLedger.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($accessNames -join "`n")) {
            throw 'Static worker access-ledger schema drift.'
        }
        if (
            ($evidence.Measurements.AccessLedger.ContextCount -isnot [int] -and $evidence.Measurements.AccessLedger.ContextCount -isnot [long]) -or
            ($evidence.Measurements.AccessLedger.TestSafeContextCount -isnot [int] -and $evidence.Measurements.AccessLedger.TestSafeContextCount -isnot [long]) -or
            ($evidence.Measurements.AccessLedger.DryRunContextCount -isnot [int] -and $evidence.Measurements.AccessLedger.DryRunContextCount -isnot [long]) -or
            ($evidence.Measurements.AccessLedger.EntryCount -isnot [int] -and $evidence.Measurements.AccessLedger.EntryCount -isnot [long]) -or
            [long]$evidence.Measurements.AccessLedger.ContextCount -ne 2 -or
            [long]$evidence.Measurements.AccessLedger.TestSafeContextCount -ne 1 -or
            [long]$evidence.Measurements.AccessLedger.DryRunContextCount -ne 1 -or
            [long]$evidence.Measurements.AccessLedger.EntryCount -ne 2
        ) {
            throw 'Static worker access-ledger scenario count drift.'
        }
        foreach ($name in @(
            'ForbiddenResourceAccessCount', 'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount',
            'ProductNetworkRequestCount', 'RealRegistryAccessCount', 'UnexpectedLedgerEntryCount'
        )) {
            $value = $evidence.Measurements.AccessLedger.$name
            if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -ne 0) {
                throw "Static worker access evidence is not integer zero: $name"
            }
        }
        $mutationNames = @('AppX', 'Credential', 'Environment', 'Feature', 'FileSystem', 'Network', 'Process', 'Registry', 'Restart', 'Service')
        if ((@($evidence.Measurements.MutationSpyCounts.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($mutationNames -join "`n")) {
            throw 'Static worker mutation schema drift.'
        }
        foreach ($name in $mutationNames) {
            $value = $evidence.Measurements.MutationSpyCounts.$name
            if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -ne 0) {
                throw "Static worker mutation count is not integer zero: $name"
            }
        }
        $expectedCommonProvenance['ExecutionBoundaryManifestSha256'] =
            (Get-FileHash -LiteralPath $BoundaryManifestPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $expectedProvenanceNames = @($expectedCommonProvenance.Keys | Sort-Object)
        if ((@($evidence.Provenance.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($expectedProvenanceNames -join "`n")) {
            throw 'Static worker provenance schema drift.'
        }
        if (@(Get-CddsiWorkerProvenanceBindingDrift -Actual $evidence.Provenance -Expected $expectedCommonProvenance).Count -gt 0) {
            throw 'Static worker provenance binding drift.'
        }
    }
    else {
        $expectedNames = @(
            'Engine', 'EvidenceType', 'Pester', 'Provenance', 'RequiredSuiteResults', 'RunId',
            'SandboxBindingSha256', 'SchemaVersion', 'ShardId', 'ShardPathsSha256', 'TestFiles'
        )
        if ((@($evidence.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($expectedNames -join "`n") -or
            $evidence.EvidenceType -cne 'CddsiWorkerPesterShardEvidence' -or
            $evidence.ShardId -cne $Descriptor.ShardId) {
            throw 'Pester shard evidence schema or shard binding drift.'
        }
        $policyMatches = @($QualityShardPolicy.QualityShards | Where-Object { $_.ShardId -ceq $Descriptor.ShardId })
        if ($policyMatches.Count -ne 1) { throw 'Pester shard is absent from the policy.' }
        $policyShard = $policyMatches[0]
        if (
            $evidence.ShardPathsSha256 -cne $policyShard.PathsSha256 -or
            (@($evidence.TestFiles) -join "`n") -cne (@($policyShard.Paths) -join "`n")
        ) {
            throw 'Pester shard file-list binding drift.'
        }
        $pesterNames = @(
            'DurationMilliseconds', 'FailedBlocksCount', 'FailedContainersCount', 'FailedCount',
            'FailedTestEvidenceTruncated', 'FailedTests', 'InconclusiveCount', 'NotRunCount',
            'PassedCount', 'Result', 'SkippedCount', 'TotalCount'
        )
        if ((@($evidence.Pester.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($pesterNames -join "`n")) {
            throw 'Pester shard result schema drift.'
        }
        foreach ($name in @(
            'DurationMilliseconds', 'FailedBlocksCount', 'FailedContainersCount', 'FailedCount',
            'InconclusiveCount', 'NotRunCount', 'PassedCount', 'SkippedCount', 'TotalCount'
        )) {
            $value = $evidence.Pester.$name
            if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -lt 0) {
                throw "Pester shard result is not a non-negative integer: $name"
            }
        }
        if (
            [long]$evidence.Pester.TotalCount -ne (
                [long]$evidence.Pester.PassedCount +
                [long]$evidence.Pester.FailedCount +
                [long]$evidence.Pester.SkippedCount +
                [long]$evidence.Pester.NotRunCount +
                [long]$evidence.Pester.InconclusiveCount
            )
        ) {
            throw 'Pester shard total count binding drift.'
        }
        if ($evidence.Pester.FailedTestEvidenceTruncated -isnot [bool]) {
            throw 'Pester shard failed-test truncation flag is invalid.'
        }
        $null = Assert-CddsiSafeFailedTestSummary `
            -FailedTests @($evidence.Pester.FailedTests) `
            -FailedCount ([long]$evidence.Pester.FailedCount) `
            -Truncated ([bool]$evidence.Pester.FailedTestEvidenceTruncated)
        $null = Assert-CddsiFailedTestSourceBinding `
            -FailedTests @($evidence.Pester.FailedTests) `
            -RepositoryRoot $RepositoryRoot `
            -AllowedRelativePaths @($policyShard.Paths)
        if ($ReadMode -ceq 'FailureProgressOnly') {
            if ($evidence.Pester.Result -cne 'Failed' -or
                [long]$evidence.Pester.FailedCount -lt 1 -or
                [long]$evidence.Pester.DurationMilliseconds -lt 0) {
                throw 'Pester shard failure evidence is not a failed result.'
            }
        }
        elseif ($ReadMode -ceq 'HistoricalCompletion') {
            if (
                [long]$evidence.Pester.TotalCount -le 0 -or
                [long]$evidence.Pester.DurationMilliseconds -lt 0 -or
                [long]$evidence.Pester.SkippedCount -ne 0 -or
                [long]$evidence.Pester.NotRunCount -ne 0 -or
                [long]$evidence.Pester.InconclusiveCount -ne 0 -or
                [long]$evidence.Pester.FailedBlocksCount -ne 0 -or
                [long]$evidence.Pester.FailedContainersCount -ne 0 -or
                [long]$evidence.Pester.TotalCount -ne (
                    [long]$evidence.Pester.PassedCount + [long]$evidence.Pester.FailedCount
                )
            ) {
                throw 'Historical Pester shard completion contains an incomplete test result.'
            }
            if ($evidence.Pester.Result -ceq 'Passed') {
                if (
                    [long]$evidence.Pester.PassedCount -le 0 -or
                    [long]$evidence.Pester.FailedCount -ne 0
                ) {
                    throw 'Historical Pester shard passed completion is inconsistent.'
                }
            }
            elseif ($evidence.Pester.Result -ceq 'Failed') {
                if ([long]$evidence.Pester.FailedCount -lt 1) {
                    throw 'Historical Pester shard failed completion has no failed tests.'
                }
            }
            else {
                throw 'Historical Pester shard completion result is invalid.'
            }
        }
        else {
            if ($evidence.Pester.Result -cne 'Passed' -or
                [long]$evidence.Pester.TotalCount -le 0 -or
                [long]$evidence.Pester.TotalCount -ne [long]$evidence.Pester.PassedCount -or
                [long]$evidence.Pester.PassedCount -le 0 -or
                [long]$evidence.Pester.DurationMilliseconds -lt 0) {
                throw 'Pester shard result is not clean.'
            }
            foreach ($name in @(
                'FailedBlocksCount', 'FailedContainersCount', 'FailedCount',
                'InconclusiveCount', 'NotRunCount', 'SkippedCount'
            )) {
                if ([long]$evidence.Pester.$name -ne 0) { throw "Pester shard result is not zero: $name" }
            }
        }
        foreach ($suiteResult in @($evidence.RequiredSuiteResults)) {
            if ((@($suiteResult.PSObject.Properties.Name | Sort-Object) -join ',') -cne 'RelativePath,Result,TestCount') {
                throw 'Pester shard required-suite schema drift.'
            }
            if ($suiteResult.TestCount -isnot [int] -and $suiteResult.TestCount -isnot [long]) {
                throw 'Pester shard required-suite count is not an integer.'
            }
            $suitePolicy = @($lock.IsolationEvidenceSuites | Where-Object {
                ([string]$_.RelativePath).Replace('\', '/') -ceq [string]$suiteResult.RelativePath
            })
            if ($suitePolicy.Count -ne 1 -or
                @($policyShard.Paths) -cnotcontains [string]$suiteResult.RelativePath -or
                [string]$suiteResult.Result -notin @('Passed', 'Failed') -or
                ($ReadMode -ceq 'CleanCompletion' -and [string]$suiteResult.Result -cne 'Passed') -or
                [long]$suiteResult.TestCount -ne [long]$suitePolicy[0].ExpectedTestCount) {
                throw 'Pester shard required-suite binding drift.'
            }
        }
        $expectedProvenanceNames = @($expectedCommonProvenance.Keys | Sort-Object)
        if ((@($evidence.Provenance.PSObject.Properties.Name | Sort-Object) -join "`n") -cne ($expectedProvenanceNames -join "`n")) {
            throw 'Pester shard provenance schema drift.'
        }
        if (@(Get-CddsiWorkerProvenanceBindingDrift -Actual $evidence.Provenance -Expected $expectedCommonProvenance).Count -gt 0) {
            throw 'Pester shard provenance binding drift.'
        }
    }

    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $Sandbox.RunId -Category FileSystem `
        -RuleId ReadWorkerEvidence -ResourceToken ('<SANDBOX_ROOT>/evidence/{0}' -f $Descriptor.Leaf) `
        -Outcome Succeeded -Data ([pscustomobject][ordered]@{
            Engine     = [string]$Descriptor.Engine
            WorkerRole = [string]$Descriptor.WorkerRole
            ShardId    = [string]$Descriptor.ShardId
        })
    return $evidence
}

function Merge-CddsiWorkerIsolationEvidence {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('PowerShell7', 'WindowsPowerShell')][string]$Engine,
        [Parameter(Mandatory = $true)]$StaticEvidence,
        [Parameter(Mandatory = $true)][object[]]$ShardEvidence,
        [Parameter(Mandatory = $true)]$QualityShardPolicy,
        [Parameter(Mandatory = $true)][string]$DependencyManifestPath
    )

    if ($StaticEvidence.Engine -cne $Engine -or $StaticEvidence.EvidenceType -cne 'CddsiWorkerStaticEvidence') {
        throw 'Static evidence does not match the aggregate engine.'
    }
    $isHistoricalDiagnostic = [string]$QualityShardPolicy.QualitySet -ceq 'HistoricalDiagnostic'
    if (
        [string]$QualityShardPolicy.QualitySet -notin @(
            'AllBlocking',
            'ProductReleaseBlocking',
            'HistoricalDiagnostic'
        )
    ) {
        throw 'Pester shard aggregate quality-set binding is invalid.'
    }
    $expectedShardIds = @($QualityShardPolicy.QualityShards | ForEach-Object { [string]$_.ShardId })
    $actualShardIds = @($ShardEvidence | ForEach-Object { [string]$_.ShardId })
    if (
        $ShardEvidence.Count -ne $expectedShardIds.Count -or
        ($actualShardIds -join "`n") -cne ($expectedShardIds -join "`n") -or
        @($ShardEvidence | Where-Object { $_.Engine -cne $Engine }).Count -gt 0
    ) {
        throw 'Pester shard aggregate inventory is incomplete.'
    }
    if (
        @($ShardEvidence | Where-Object {
            [string]$_.RunId -cne [string]$StaticEvidence.RunId -or
            [string]$_.SandboxBindingSha256 -cne [string]$StaticEvidence.SandboxBindingSha256
        }).Count -gt 0
    ) {
        throw 'Pester shard aggregate run or sandbox binding drift.'
    }
    for ($shardIndex = 0; $shardIndex -lt $QualityShardPolicy.QualityShards.Count; $shardIndex++) {
        $policyShard = $QualityShardPolicy.QualityShards[$shardIndex]
        $actualShard = $ShardEvidence[$shardIndex]
        if (
            [string]$actualShard.ShardPathsSha256 -cne [string]$policyShard.PathsSha256 -or
            (@($actualShard.TestFiles) -join "`n") -cne (@($policyShard.Paths) -join "`n") -or
            [string]$actualShard.Provenance.QualityShardPolicySha256 -cne
                [string]$QualityShardPolicy.CanonicalSha256
        ) {
            throw 'Pester shard aggregate policy binding drift.'
        }
    }
    $lock = Import-PowerShellDataFile -LiteralPath $DependencyManifestPath
    $allSuiteResults = @($ShardEvidence | ForEach-Object { @($_.RequiredSuiteResults) })
    $selectedPesterPathSet = New-Object 'System.Collections.Generic.HashSet[string]' ([StringComparer]::Ordinal)
    foreach ($selectedPesterPath in @($QualityShardPolicy.SelectedPesterPaths)) {
        if (-not $selectedPesterPathSet.Add([string]$selectedPesterPath)) {
            throw 'Selected Pester path inventory contains a duplicate.'
        }
    }
    $selectedSuitePolicy = @($lock.IsolationEvidenceSuites | Where-Object {
        $selectedPesterPathSet.Contains(([string]$_.RelativePath).Replace('\', '/'))
    })
    $orderedSuiteResults = New-Object System.Collections.Generic.List[object]
    foreach ($suite in $selectedSuitePolicy) {
        $relativePath = ([string]$suite.RelativePath).Replace('\', '/')
        $matches = @($allSuiteResults | Where-Object { $_.RelativePath -ceq $relativePath })
        if (
            $matches.Count -ne 1 -or
            [string]$matches[0].Result -notin @('Passed', 'Failed') -or
            (-not $isHistoricalDiagnostic -and [string]$matches[0].Result -cne 'Passed') -or
            [long]$matches[0].TestCount -ne [long]$suite.ExpectedTestCount
        ) {
            throw 'Required isolation suite aggregate is incomplete.'
        }
        $orderedSuiteResults.Add($matches[0])
    }
    if ($allSuiteResults.Count -ne $orderedSuiteResults.Count) {
        throw 'Required isolation suite aggregate contains an extra result.'
    }

    $shardCompletionEvidence = New-Object System.Collections.Generic.List[object]
    foreach ($shard in @($ShardEvidence)) {
        $shardCompletionEvidence.Add([pscustomobject][ordered]@{
            ShardId                    = [string]$shard.ShardId
            ShardPathsSha256           = [string]$shard.ShardPathsSha256
            TestFiles                  = [string[]]@($shard.TestFiles)
            Result                     = [string]$shard.Pester.Result
            TotalCount                 = [long]$shard.Pester.TotalCount
            PassedCount                = [long]$shard.Pester.PassedCount
            FailedCount                = [long]$shard.Pester.FailedCount
            SkippedCount               = [long]$shard.Pester.SkippedCount
            NotRunCount                = [long]$shard.Pester.NotRunCount
            InconclusiveCount          = [long]$shard.Pester.InconclusiveCount
            FailedBlocksCount          = [long]$shard.Pester.FailedBlocksCount
            FailedContainersCount      = [long]$shard.Pester.FailedContainersCount
            DurationMilliseconds       = [long]$shard.Pester.DurationMilliseconds
            FailedTests                = @($shard.Pester.FailedTests)
            FailedTestEvidenceTruncated = [bool]$shard.Pester.FailedTestEvidenceTruncated
        })
    }
    $passedCount = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.PassedCount } | Measure-Object -Sum).Sum)
    $failedCount = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.FailedCount } | Measure-Object -Sum).Sum)
    $pester = [pscustomobject][ordered]@{
        Result                = $(if ($failedCount -gt 0) { 'Failed' } else { 'Passed' })
        TotalCount            = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.TotalCount } | Measure-Object -Sum).Sum)
        PassedCount           = $passedCount
        FailedCount           = $failedCount
        SkippedCount          = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.SkippedCount } | Measure-Object -Sum).Sum)
        NotRunCount           = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.NotRunCount } | Measure-Object -Sum).Sum)
        InconclusiveCount     = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.InconclusiveCount } | Measure-Object -Sum).Sum)
        FailedBlocksCount     = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.FailedBlocksCount } | Measure-Object -Sum).Sum)
        FailedContainersCount = [long](($ShardEvidence | ForEach-Object { [long]$_.Pester.FailedContainersCount } | Measure-Object -Sum).Sum)
    }
    if (
        $pester.TotalCount -le 0 -or
        $pester.TotalCount -ne ($pester.PassedCount + $pester.FailedCount) -or
        $pester.SkippedCount -ne 0 -or
        $pester.NotRunCount -ne 0 -or
        $pester.InconclusiveCount -ne 0 -or
        $pester.FailedBlocksCount -ne 0 -or
        $pester.FailedContainersCount -ne 0 -or
        (-not $isHistoricalDiagnostic -and (
            $pester.Result -cne 'Passed' -or
            $pester.PassedCount -le 0 -or
            $pester.FailedCount -ne 0
        ))
    ) {
        throw 'Pester aggregate is not clean.'
    }
    $suiteResults = $orderedSuiteResults.ToArray()
    $requiredSuiteFailureCount = [long]@($suiteResults | Where-Object {
        [string]$_.Result -ceq 'Failed'
    }).Count
    $measurements = [pscustomobject][ordered]@{
        AstSyntaxErrorCount       = [long]$StaticEvidence.Measurements.AstSyntaxErrorCount
        LiveAdapterFileCount      = [long]$StaticEvidence.Measurements.LiveAdapterFileCount
        SecretFindingCount        = [long]$StaticEvidence.Measurements.SecretFindingCount
        RepositoryContentChanged  = [bool]$StaticEvidence.Measurements.RepositoryContentChanged
        LiveProviderLoaded        = [bool]$StaticEvidence.Measurements.LiveProviderLoaded
        AccessLedger              = $StaticEvidence.Measurements.AccessLedger
        MutationSpyCounts         = $StaticEvidence.Measurements.MutationSpyCounts
        Pester                    = $pester
        ShardCompletionEvidence   = $shardCompletionEvidence.ToArray()
        RequiredSuiteResults      = @($suiteResults)
        RequiredSuiteFailureCount = $requiredSuiteFailureCount
    }
    $provenance = [pscustomobject][ordered]@{
        MeasurementRuleVersion          = 'cddsi-worker-measurement-rules-v6'
        RepositoryInventorySha256       = [string]$StaticEvidence.Provenance.RepositoryInventorySha256
        InitialRepositoryManifestSha256 = [string]$StaticEvidence.Provenance.InitialRepositoryManifestSha256
        FinalRepositoryManifestSha256   = [string]$StaticEvidence.Provenance.FinalRepositoryManifestSha256
        ExecutionBoundaryManifestSha256 = [string]$StaticEvidence.Provenance.ExecutionBoundaryManifestSha256
        DependencyManifestSha256        = [string]$StaticEvidence.Provenance.DependencyManifestSha256
        RequiredSuiteSummarySha256      = Get-CddsiRequiredSuiteSummarySha256 -SuiteResults $suiteResults
        PesterTreeSha256                = [string]$StaticEvidence.Provenance.PesterTreeSha256
        EngineGrantSha256               = [string]$StaticEvidence.Provenance.EngineGrantSha256
        QualityShardPolicySha256        = [string]$QualityShardPolicy.CanonicalSha256
    }
    return [pscustomobject][ordered]@{
        SchemaVersion         = 2
        EvidenceType         = 'CddsiWorkerIsolationEvidence'
        RunId                = [string]$StaticEvidence.RunId
        Engine               = $Engine
        SandboxBindingSha256 = [string]$StaticEvidence.SandboxBindingSha256
        Measurements         = $measurements
        Provenance           = $provenance
    }
}

function Test-CddsiSandboxArtifacts {
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger
    )

    $queue = New-Object System.Collections.Generic.Queue[string]
    $queue.Enqueue($Sandbox.Root)
    $findingCount = 0
    $fileCount = 0
    foreach ($expectedCanaryPath in $Sandbox.CanaryFileSha256.Keys) {
        if (-not (Test-Path -LiteralPath $expectedCanaryPath -PathType Leaf)) { $findingCount++ }
    }
    while ($queue.Count -gt 0) {
        $directory = $queue.Dequeue()
        foreach ($item in @(Get-ChildItem -LiteralPath $directory -Force)) {
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { $findingCount++; continue }
            if ($item.PSIsContainer) { $queue.Enqueue($item.FullName); continue }
            $fileCount++
            if ($Sandbox.CanaryFileSha256.Contains($item.FullName)) {
                $actualHash = (Get-FileHash -LiteralPath $item.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
                if ($actualHash -cne [string]$Sandbox.CanaryFileSha256[$item.FullName]) { $findingCount++ }
                continue
            }
            $ownershipToken = if ([string]::Equals($item.FullName, $Sandbox.MarkerPath, [StringComparison]::OrdinalIgnoreCase)) { $null } else { $Sandbox.OwnershipToken }
            $findingCount += Get-CddsiFileSecretFindingCount -Path $item.FullName -CanaryValue $Sandbox.CanaryValue -OwnershipToken $ownershipToken
            if (Test-CddsiSandboxTextArtifactPath -Path $item.FullName -Sandbox $Sandbox) {
                $bytes = [System.IO.File]::ReadAllBytes($item.FullName)
                $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
                try { $text = $strictUtf8.GetString($bytes) } catch { $findingCount++; continue }
                if ($text.IndexOf([char]0) -ge 0) { $findingCount++ }
            }
        }
    }
    $outcome = if ($findingCount -eq 0) { 'Succeeded' } else { 'Failed' }
    Add-CddsiHarnessLedgerEntry -Ledger $Ledger -RunId $Sandbox.RunId -Category FileSystem -RuleId ScanSandboxArtifacts -ResourceToken '<SANDBOX_ROOT>' -Outcome $outcome -Data ([pscustomobject][ordered]@{ FileCount = $fileCount; FindingCount = $findingCount })
    if ($findingCount -ne 0) { throw 'Sandbox artifact secret, canary, ownership, encoding, or reparse scan failed.' }
    return [pscustomobject][ordered]@{
        FileCount    = [int]$fileCount
        FindingCount = [int]$findingCount
    }
}

function New-CddsiQualityEvidence {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][System.Collections.Generic.List[object]]$Ledger,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ExpectedHarnessLedger,
        [Parameter(Mandatory = $true)][object[]]$ExpectedProcessRules,
        [Parameter(Mandatory = $true)][object[]]$WorkerEvidence,
        [Parameter(Mandatory = $true)]$BeforeSnapshot,
        [Parameter(Mandatory = $true)]$AfterSnapshot,
        [Parameter(Mandatory = $true)][string]$CleanupOutcome,
        [Parameter(Mandatory = $true)][bool]$SafeFailureDisclosure
    )

    $null = Assert-CddsiHarnessLedgerExact -Ledger $Ledger -ExpectedEntries $ExpectedHarnessLedger
    if (-not $SafeFailureDisclosure) { throw 'Quality evidence requires a successful safe-disclosure measurement.' }
    foreach ($snapshot in @($BeforeSnapshot, $AfterSnapshot)) {
        $snapshotNames = @($snapshot.PSObject.Properties.Name | Sort-Object)
        if (($snapshotNames -join ',') -cne 'DirectoryCount,FileCount,Hash,Manifest,SchemaVersion,Scope') { throw 'Repository snapshot schema drift.' }
        if ($snapshot.SchemaVersion -ne 1 -or $snapshot.Scope -cne 'WorkingTreeExcludingDotGit' -or [string]$snapshot.Hash -notmatch '^[a-f0-9]{64}$') { throw 'Repository snapshot binding is invalid.' }
    }
    $processEntries = @($Ledger | Where-Object { $_.Category -eq 'Process' })
    $networkEntries = @($Ledger | Where-Object { $_.Category -eq 'Network' })
    $expectedRuleIds = @($ExpectedProcessRules | ForEach-Object RuleId)
    $successfulProcessEntries = @($processEntries | Where-Object Outcome -eq 'Succeeded')
    $unapprovedHarnessProcessCount = @($processEntries | Where-Object { $_.Outcome -eq 'Denied' -or $expectedRuleIds -notcontains $_.RuleId }).Count
    $unapprovedHarnessNetworkCount = $networkEntries.Count
    $harnessSecretFindings = [int](($processEntries | ForEach-Object {
        if ($null -ne $_.Data -and $_.Data.PSObject.Properties.Name -contains 'SecretFindingCount') { [int]$_.Data.SecretFindingCount }
    } | Measure-Object -Sum).Sum)
    $artifactScanEntries = @($Ledger | Where-Object { $_.Category -eq 'FileSystem' -and $_.RuleId -eq 'ScanSandboxArtifacts' })
    if ($artifactScanEntries.Count -ne 1) { throw 'Sandbox artifact scan ledger evidence is incomplete.' }
    $sandboxArtifactFindingCount = [int]$artifactScanEntries[0].Data.FindingCount
    $unexpectedHarnessLedgerCount = 0
    $workerEngineSet = (@($WorkerEvidence | ForEach-Object Engine | Sort-Object) -join ',')
    if ($WorkerEvidence.Count -ne 2 -or $workerEngineSet -cne 'PowerShell7,WindowsPowerShell') { throw 'Worker evidence engine set is incomplete.' }

    $liveProviderLoaded = @($WorkerEvidence | Where-Object { $_.Measurements.LiveProviderLoaded }).Count -gt 0
    $repositoryChangedByWorker = @($WorkerEvidence | Where-Object { $_.Measurements.RepositoryContentChanged }).Count -gt 0
    $forbiddenResourceAccessCount = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.AccessLedger.ForbiddenResourceAccessCount } | Measure-Object -Sum).Sum)
    $outsideSandboxWriteCount = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.AccessLedger.OutsideSandboxWriteCount } | Measure-Object -Sum).Sum)
    $productLiveProcessCount = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.AccessLedger.ProductLiveProcessSpawnCount } | Measure-Object -Sum).Sum)
    $productNetworkCount = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.AccessLedger.ProductNetworkRequestCount } | Measure-Object -Sum).Sum)
    $realRegistryAccessCount = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.AccessLedger.RealRegistryAccessCount } | Measure-Object -Sum).Sum)
    $workerSecretFindings = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.SecretFindingCount } | Measure-Object -Sum).Sum)
    $workerUnexpectedLedgerCount = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.AccessLedger.UnexpectedLedgerEntryCount } | Measure-Object -Sum).Sum)
    $mutationCounts = [ordered]@{}
    foreach ($mutationName in @('FileSystem', 'Environment', 'Registry', 'Network', 'Process', 'AppX', 'Feature', 'Service', 'Credential', 'Restart')) {
        $mutationCounts[$mutationName] = [int](($WorkerEvidence | ForEach-Object { [int]$_.Measurements.MutationSpyCounts.$mutationName } | Measure-Object -Sum).Sum)
    }
    $secretFindings = $harnessSecretFindings + $workerSecretFindings + $sandboxArtifactFindingCount
    $unexpectedLedgerEntryCount = $unexpectedHarnessLedgerCount + $workerUnexpectedLedgerCount
    $expectedProcessCount = [int](($ExpectedProcessRules | ForEach-Object { [int]$_.Count } | Measure-Object -Sum).Sum)
    $repositoryContentChanged = $BeforeSnapshot.Hash -cne $AfterSnapshot.Hash
    return [pscustomobject][ordered]@{
        SchemaVersion                   = 2
        Scenario                        = 'Quality'
        RunId                           = $RunId
        LIVE_PROVIDER_LOADED            = $liveProviderLoaded
        FORBIDDEN_RESOURCE_ACCESS_COUNT = $forbiddenResourceAccessCount
        OUTSIDE_SANDBOX_WRITE_COUNT     = $outsideSandboxWriteCount
        PRODUCT_LIVE_PROCESS_SPAWN_COUNT = $productLiveProcessCount
        PRODUCT_NETWORK_REQUEST_COUNT   = $productNetworkCount
        REAL_REGISTRY_ACCESS_COUNT      = $realRegistryAccessCount
        UNAPPROVED_HARNESS_PROCESS_COUNT = $unapprovedHarnessProcessCount
        UNAPPROVED_HARNESS_NETWORK_COUNT = $unapprovedHarnessNetworkCount
        SECRET_FINDINGS                 = $secretFindings
        UNEXPECTED_LEDGER_ENTRY_COUNT   = $unexpectedLedgerEntryCount
        REPOSITORY_CONTENT_CHANGED      = ($repositoryContentChanged -or $repositoryChangedByWorker)
        REPOSITORY_SNAPSHOT_SCOPE       = 'WorkingTreeExcludingDotGit'
        REPOSITORY_BEFORE_SHA256        = [string]$BeforeSnapshot.Hash
        REPOSITORY_AFTER_SHA256         = [string]$AfterSnapshot.Hash
        REPOSITORY_BEFORE_FILE_COUNT    = [int]$BeforeSnapshot.FileCount
        REPOSITORY_AFTER_FILE_COUNT     = [int]$AfterSnapshot.FileCount
        REPOSITORY_BEFORE_DIRECTORY_COUNT = [int]$BeforeSnapshot.DirectoryCount
        REPOSITORY_AFTER_DIRECTORY_COUNT = [int]$AfterSnapshot.DirectoryCount
        TRUSTED_PROCESS_EXPECTED_COUNT  = $expectedProcessCount
        TRUSTED_PROCESS_ACTUAL_COUNT    = $successfulProcessEntries.Count
        TRUSTED_HARNESS_PROCESS_COUNT   = $successfulProcessEntries.Count
        TRUSTED_PROCESS_SEQUENCE        = @($ExpectedProcessRules)
        WORKER_EVIDENCE                  = @($WorkerEvidence)
        MUTATION_SPY_COUNTS             = [pscustomobject]$mutationCounts
        CLEANUP_OUTCOME                 = $CleanupOutcome
        SAFE_FAILURE_DISCLOSURE         = $SafeFailureDisclosure
        HARNESS_LEDGER_EXACT            = $true
        HARNESS_LEDGER                  = $Ledger.ToArray()
    }
}

if ($ImportOnly) { return }

$requiredValues = [ordered]@{
    RepositoryRoot              = $RepositoryRoot
    PowerShell7Executable       = $PowerShell7Executable
    PowerShell7Sha256           = $PowerShell7Sha256
    WindowsPowerShellExecutable = $WindowsPowerShellExecutable
    WindowsPowerShellSha256     = $WindowsPowerShellSha256
    GitExecutable               = $GitExecutable
    GitSha256                   = $GitSha256
}
foreach ($requiredName in $requiredValues.Keys) {
    if ([string]::IsNullOrWhiteSpace([string]$requiredValues[$requiredName])) {
        throw ('HostSandbox requires an explicit {0} grant.' -f $requiredName)
    }
}

$runId = [guid]::NewGuid().ToString('D')
$ledger = New-Object System.Collections.Generic.List[object]
$sandbox = $null
$pathTokens = [ordered]@{}
$processOrdinal = 0
$expectedProcessRules = @()
$evidence = $null
$repositoryRootFull = $null
$beforeSnapshot = $null
$afterSnapshot = $null
$artifactScanEvidence = $null
$inventoryEvidence = $null
$workerInvocationPlan = @()
$workerRoleEvidence = New-Object System.Collections.Generic.List[object]
$completedWorkerIds = New-Object System.Collections.Generic.List[string]
$currentWorkerDescriptor = $null
$currentWorkerFailureEvidence = $null

try {
    $repositoryRootFull = [System.IO.Path]::GetFullPath($RepositoryRoot).TrimEnd('\')
    if (-not (Test-Path -LiteralPath $repositoryRootFull -PathType Container)) { throw 'Repository root is unavailable.' }
    Assert-CddsiNoReparsePath -Path $repositoryRootFull -StopRoot ([System.IO.Path]::GetPathRoot($repositoryRootFull))

    $powerShell7Grant = Assert-CddsiTrustedToolGrant -ToolId PowerShell7 -ExecutablePath $PowerShell7Executable -ExpectedSha256 $PowerShell7Sha256 -ExpectedLeaf 'pwsh.exe' -RunId $runId -Ledger $ledger
    $windowsPowerShellGrant = Assert-CddsiTrustedToolGrant -ToolId WindowsPowerShell -ExecutablePath $WindowsPowerShellExecutable -ExpectedSha256 $WindowsPowerShellSha256 -ExpectedLeaf 'powershell.exe' -RunId $runId -Ledger $ledger
    $gitGrant = Assert-CddsiTrustedToolGrant -ToolId Git -ExecutablePath $GitExecutable -ExpectedSha256 $GitSha256 -ExpectedLeaf 'git.exe' -RunId $runId -Ledger $ledger
    $windowsContext = Get-CddsiWindowsSystemContext -WindowsPowerShellGrant $windowsPowerShellGrant

    $pathTokens['<REPOSITORY_ROOT>'] = $repositoryRootFull
    $pathTokens[$powerShell7Grant.ResourceToken] = $powerShell7Grant.Path
    $pathTokens[$windowsPowerShellGrant.ResourceToken] = $windowsPowerShellGrant.Path
    $pathTokens[$gitGrant.ResourceToken] = $gitGrant.Path

    $beforeSnapshot = Get-CddsiRepositorySnapshot -RootPath $repositoryRootFull
    $tempBase = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $sandbox = New-CddsiOwnedSandbox -TempBase $tempBase -RunId $runId -Ledger $ledger
    $pathTokens['<SANDBOX_ROOT>'] = $sandbox.Root
    $powerShell7Environment = New-CddsiMinimalEnvironment -Sandbox $sandbox -RepositoryRoot $repositoryRootFull -WindowsContext $windowsContext -PowerShellHome (Split-Path -Parent $powerShell7Grant.Path)
    $windowsPowerShellEnvironment = New-CddsiMinimalEnvironment -Sandbox $sandbox -RepositoryRoot $repositoryRootFull -WindowsContext $windowsContext -PowerShellHome (Split-Path -Parent $windowsPowerShellGrant.Path)
    $gitEnvironment = $windowsPowerShellEnvironment

    $gitBaseArguments = @('-c', 'core.quotepath=false', '-c', 'core.hooksPath=NUL', '-c', 'core.attributesFile=NUL', '-C', $repositoryRootFull)
    $inventoryArguments = $gitBaseArguments + @('ls-files', '-z', '--cached', '--others', '--exclude-standard')
    $inventoryPath = Join-Path $sandbox.Paths.State 'repository-inventory.json'
    $workerPath = Join-Path $repositoryRootFull 'scripts\check-worker.ps1'
    $boundaryManifestPath = Join-Path $repositoryRootFull 'config\execution-boundaries.psd1'
    $dependencyManifestPath = Join-Path $repositoryRootFull 'config\dev-dependencies.psd1'
    $qualitySetPolicy = Get-CddsiQualitySetPolicy `
        -RepositoryRoot $repositoryRootFull `
        -QualitySet $QualitySet
    $workerCommonArguments = @(
        '-NoLogo'
        '-NoProfile'
        '-NonInteractive'
        '-File'
        $workerPath
        '-RepositoryRoot'
        $repositoryRootFull
        '-SandboxRoot'
        $sandbox.Root
        '-RunId'
        $runId
        '-RepositoryInventoryPath'
        $inventoryPath
        '-BoundaryManifestPath'
        $boundaryManifestPath
        '-DependencyManifestPath'
        $dependencyManifestPath
        '-QualitySet'
        $qualitySetPolicy.QualitySet
        '-GitExecutablePath'
        $gitGrant.Path
        '-GitGrantSha256'
        $gitGrant.Sha256
    )
    $workerInvocationPlan = @(New-CddsiQualityWorkerInvocationPlan `
        -WorkerCommonArguments $workerCommonArguments `
        -QualityShardPolicy $qualitySetPolicy `
        -PowerShell7Grant $powerShell7Grant `
        -PowerShell7Environment $powerShell7Environment `
        -WindowsPowerShellGrant $windowsPowerShellGrant `
        -WindowsPowerShellEnvironment $windowsPowerShellEnvironment `
        -FirstSequence 2)
    if ($workerInvocationPlan.Count -ne [int]$qualitySetPolicy.WorkerCount) {
        throw 'Quality-set worker invocation count drift.'
    }
    $diffArguments = $gitBaseArguments + @('-c', 'diff.external=', 'diff', '--no-ext-diff', '--check')
    $cachedDiffArguments = $gitBaseArguments + @('-c', 'diff.external=', 'diff', '--cached', '--no-ext-diff', '--check')

    $processRules = New-Object System.Collections.Generic.List[object]
    $processRules.Add((New-CddsiExpectedProcessRule -Sequence 1 -RuleId 'GitInventory' -ToolGrant $gitGrant -Arguments $inventoryArguments -Environment $gitEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'))
    foreach ($descriptor in $workerInvocationPlan) {
        $processRules.Add((New-CddsiExpectedProcessRule `
            -Sequence $descriptor.Sequence `
            -RuleId $descriptor.RuleId `
            -ToolGrant $descriptor.Grant `
            -Arguments $descriptor.Arguments `
            -Environment $descriptor.Environment `
            -WorkingDirectoryToken '<SANDBOX_ROOT>'))
    }
    $diffSequence = $workerInvocationPlan.Count + 2
    $processRules.Add((New-CddsiExpectedProcessRule -Sequence $diffSequence -RuleId 'GitDiffCheck' -ToolGrant $gitGrant -Arguments $diffArguments -Environment $gitEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'))
    $processRules.Add((New-CddsiExpectedProcessRule -Sequence ($diffSequence + 1) -RuleId 'GitCachedDiffCheck' -ToolGrant $gitGrant -Arguments $cachedDiffArguments -Environment $gitEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'))
    $expectedProcessRules = $processRules.ToArray()
    if ($expectedProcessRules.Count -ne [int]$qualitySetPolicy.ProcessCount) {
        throw 'Quality-set trusted process count drift.'
    }

    $inventoryResult = Invoke-CddsiTrustedProcess -RuleId 'GitInventory' -ToolGrant $gitGrant -Arguments $inventoryArguments -Environment $gitEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $inventoryEvidence = Write-CddsiRepositoryInventory -GitOutput $inventoryResult.StdOut -RepositoryRoot $repositoryRootFull -Sandbox $sandbox -Ledger $ledger
    if (-not [string]::Equals($inventoryEvidence.Path, $inventoryPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Repository inventory path drift.' }
    foreach ($descriptor in $workerInvocationPlan) {
        $currentWorkerDescriptor = $descriptor
        $currentWorkerFailureEvidence = $null
        try {
            $workerProcessResult = Invoke-CddsiTrustedProcess `
                -RuleId $descriptor.RuleId `
                -ToolGrant $descriptor.Grant `
                -Arguments $descriptor.Arguments `
                -Environment $descriptor.Environment `
                -WorkingDirectory $sandbox.Root `
                -TimeoutSeconds $ProcessTimeoutSeconds `
                -ExpectedProcessRules $expectedProcessRules `
                -ProcessOrdinal ([ref]$processOrdinal) `
                -Ledger $ledger `
                -RunId $runId `
                -PathTokens $pathTokens `
                -OwnershipToken $sandbox.OwnershipToken `
                -CanaryValue $sandbox.CanaryValue
        }
        catch {
            $workerProcessError = $_
            $workerTimedOut = (
                [string]$workerProcessError.Exception.Data['CddsiProcessFailureCode'] -ceq
                'PROCESS_TIMEOUT'
            )
            if ($descriptor.WorkerRole -ceq 'PesterShard' -and -not $workerTimedOut) {
                try {
                    $currentWorkerFailureEvidence = Read-CddsiWorkerRoleEvidence `
                        -Descriptor $descriptor `
                        -Sandbox $sandbox `
                        -RepositoryRoot $repositoryRootFull `
                        -RepositoryInventoryPath $inventoryPath `
                        -BoundaryManifestPath $boundaryManifestPath `
                        -DependencyManifestPath $dependencyManifestPath `
                        -QualityShardPolicy $qualitySetPolicy `
                        -Ledger $ledger `
                        -ReadMode FailureProgressOnly
                }
                catch {
                    $currentWorkerFailureEvidence = $null
                }
            }
            throw $workerProcessError
        }
        $utf8RoundTripMarker = 'CDDSI_UTF8_ROUNDTRIP=质量检查 😀 𠮷'
        if (
            -not $workerProcessResult.StdOut.Contains($utf8RoundTripMarker) -or
            -not $workerProcessResult.StdErr.Contains($utf8RoundTripMarker) -or
            $workerProcessResult.StdOut.Contains([string][char]0xFFFD) -or
            $workerProcessResult.StdErr.Contains([string][char]0xFFFD)
        ) {
            throw 'Worker UTF-8 round-trip evidence is invalid.'
        }
        $completionReadMode = if (
            $descriptor.WorkerRole -ceq 'PesterShard' -and
            [string]$qualitySetPolicy.QualitySet -ceq 'HistoricalDiagnostic'
        ) {
            'HistoricalCompletion'
        }
        else {
            'CleanCompletion'
        }
        $roleEvidence = Read-CddsiWorkerRoleEvidence `
            -Descriptor $descriptor `
            -Sandbox $sandbox `
            -RepositoryRoot $repositoryRootFull `
            -RepositoryInventoryPath $inventoryPath `
            -BoundaryManifestPath $boundaryManifestPath `
            -DependencyManifestPath $dependencyManifestPath `
            -QualityShardPolicy $qualitySetPolicy `
            -Ledger $ledger `
            -ReadMode $completionReadMode
        $workerRoleEvidence.Add($roleEvidence)
        $workerId = '{0}/{1}' -f $descriptor.Engine, $(if ($descriptor.WorkerRole -ceq 'Static') { 'Static' } else { $descriptor.ShardId })
        $completedWorkerIds.Add($workerId)
        $currentWorkerDescriptor = $null
    }
    $powerShell7Static = @($workerRoleEvidence | Where-Object { $_.Engine -ceq 'PowerShell7' -and $_.EvidenceType -ceq 'CddsiWorkerStaticEvidence' })
    $windowsPowerShellStatic = @($workerRoleEvidence | Where-Object { $_.Engine -ceq 'WindowsPowerShell' -and $_.EvidenceType -ceq 'CddsiWorkerStaticEvidence' })
    if ($powerShell7Static.Count -ne 1 -or $windowsPowerShellStatic.Count -ne 1) { throw 'Static worker evidence set is incomplete.' }
    $powerShell7Shards = @($workerRoleEvidence | Where-Object { $_.Engine -ceq 'PowerShell7' -and $_.EvidenceType -ceq 'CddsiWorkerPesterShardEvidence' })
    $windowsPowerShellShards = @($workerRoleEvidence | Where-Object { $_.Engine -ceq 'WindowsPowerShell' -and $_.EvidenceType -ceq 'CddsiWorkerPesterShardEvidence' })
    $powerShell7Evidence = Merge-CddsiWorkerIsolationEvidence -Engine PowerShell7 -StaticEvidence $powerShell7Static[0] -ShardEvidence $powerShell7Shards -QualityShardPolicy $qualitySetPolicy -DependencyManifestPath $dependencyManifestPath
    $windowsPowerShellEvidence = Merge-CddsiWorkerIsolationEvidence -Engine WindowsPowerShell -StaticEvidence $windowsPowerShellStatic[0] -ShardEvidence $windowsPowerShellShards -QualityShardPolicy $qualitySetPolicy -DependencyManifestPath $dependencyManifestPath
    $workerEvidence = @($powerShell7Evidence, $windowsPowerShellEvidence)
    $null = Invoke-CddsiTrustedProcess -RuleId 'GitDiffCheck' -ToolGrant $gitGrant -Arguments $diffArguments -Environment $gitEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $null = Invoke-CddsiTrustedProcess -RuleId 'GitCachedDiffCheck' -ToolGrant $gitGrant -Arguments $cachedDiffArguments -Environment $gitEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue

    if ($processOrdinal -ne $expectedProcessRules.Count) { throw 'Trusted process sequence did not complete exactly.' }
    $artifactScanEvidence = Test-CddsiSandboxArtifacts -Sandbox $sandbox -Ledger $ledger
    $afterSnapshot = Get-CddsiRepositorySnapshot -RootPath $repositoryRootFull
    $repositoryContentChanged = $beforeSnapshot.Hash -cne $afterSnapshot.Hash
    if ($repositoryContentChanged) { throw 'Quality checks changed repository content.' }

    $expectedPreCleanupLedger = New-CddsiExpectedQualityHarnessLedger -RunId $runId -PowerShell7Grant $powerShell7Grant -WindowsPowerShellGrant $windowsPowerShellGrant -GitGrant $gitGrant -ExpectedProcessRules $expectedProcessRules -WorkerInvocationPlan $workerInvocationPlan -CanaryFileCount $sandbox.CanaryPaths.Count -InventoryFileCount $inventoryEvidence.FileCount -ArtifactScanEvidence $artifactScanEvidence
    if ($expectedPreCleanupLedger.Count -ne ([int]$qualitySetPolicy.LedgerEntryCount - 1)) {
        throw 'Quality-set pre-cleanup ledger count drift.'
    }
    $probeSecret = 'sk-' + ('z' * 32 -join '')
    $probeText = ([char]27) + '[31m' + $repositoryRootFull + ([char]27) + '[0m' + ([char]0) + ([char]0x202E) + $sandbox.OwnershipToken + $sandbox.CanaryValue + $probeSecret
    $safeProbe = Protect-CddsiHarnessText -Text $probeText -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $safeFailureDisclosure = Test-CddsiSafeDiagnosticDisclosure -Text $safeProbe -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    if (-not $safeFailureDisclosure) { throw 'Safe diagnostic disclosure self-check failed.' }

    $preCleanupEvidence = New-CddsiQualityEvidence -RunId $runId -Ledger $ledger -ExpectedHarnessLedger $expectedPreCleanupLedger -ExpectedProcessRules $expectedProcessRules -WorkerEvidence $workerEvidence -BeforeSnapshot $beforeSnapshot -AfterSnapshot $afterSnapshot -CleanupOutcome 'Pending' -SafeFailureDisclosure $safeFailureDisclosure
    foreach ($zeroName in @('FORBIDDEN_RESOURCE_ACCESS_COUNT', 'OUTSIDE_SANDBOX_WRITE_COUNT', 'PRODUCT_LIVE_PROCESS_SPAWN_COUNT', 'PRODUCT_NETWORK_REQUEST_COUNT', 'REAL_REGISTRY_ACCESS_COUNT', 'UNAPPROVED_HARNESS_PROCESS_COUNT', 'UNAPPROVED_HARNESS_NETWORK_COUNT', 'SECRET_FINDINGS', 'UNEXPECTED_LEDGER_ENTRY_COUNT')) {
        if ([long]$preCleanupEvidence.$zeroName -ne 0) { throw "Aggregated isolation evidence is not zero: $zeroName" }
    }
    if ($preCleanupEvidence.LIVE_PROVIDER_LOADED -or $preCleanupEvidence.REPOSITORY_CONTENT_CHANGED) { throw 'Aggregated isolation boolean evidence is unsafe.' }
    if ($preCleanupEvidence.TRUSTED_PROCESS_EXPECTED_COUNT -ne $preCleanupEvidence.TRUSTED_PROCESS_ACTUAL_COUNT) { throw 'Trusted process count evidence drift.' }
    foreach ($mutationProperty in $preCleanupEvidence.MUTATION_SPY_COUNTS.PSObject.Properties) {
        if ([long]$mutationProperty.Value -ne 0) { throw "Aggregated mutation spy is not zero: $($mutationProperty.Name)" }
    }

    Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
    $finalSnapshot = Get-CddsiRepositorySnapshot -RootPath $repositoryRootFull
    $expectedFinalLedger = New-CddsiExpectedQualityHarnessLedger -RunId $runId -PowerShell7Grant $powerShell7Grant -WindowsPowerShellGrant $windowsPowerShellGrant -GitGrant $gitGrant -ExpectedProcessRules $expectedProcessRules -WorkerInvocationPlan $workerInvocationPlan -CanaryFileCount $sandbox.CanaryPaths.Count -InventoryFileCount $inventoryEvidence.FileCount -ArtifactScanEvidence $artifactScanEvidence -IncludeCleanup
    if ($expectedFinalLedger.Count -ne [int]$qualitySetPolicy.LedgerEntryCount) {
        throw 'Quality-set final ledger count drift.'
    }
    $evidence = New-CddsiQualityEvidence -RunId $runId -Ledger $ledger -ExpectedHarnessLedger $expectedFinalLedger -ExpectedProcessRules $expectedProcessRules -WorkerEvidence $workerEvidence -BeforeSnapshot $beforeSnapshot -AfterSnapshot $finalSnapshot -CleanupOutcome 'Succeeded' -SafeFailureDisclosure $safeFailureDisclosure
}
catch {
    $primaryError = $_
    $ownershipToken = $null
    $canaryValue = $null
    if ($null -ne $sandbox) {
        $ownershipToken = $sandbox.OwnershipToken
        $canaryValue = $sandbox.CanaryValue
    }
    $cleanupOutcome = 'NotCreated'
    $cleanupFailureCode = 'NONE'
    if ($null -ne $sandbox -and (Test-Path -LiteralPath $sandbox.Root -PathType Container)) {
        if ($KeepSandboxOnFailure) {
            $cleanupOutcome = 'PreservedByExplicitRequest'
        }
        else {
            try {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
                $cleanupOutcome = 'SucceededAfterFailure'
            }
            catch {
                $cleanupOutcome = 'RefusedUnsafeCleanup'
                $cleanupFailureCode = 'CLEANUP_REFUSED_UNSAFE'
            }
        }
    }
    $repositoryChangedAfterFailure = $true
    if ($null -ne $beforeSnapshot -and -not [string]::IsNullOrWhiteSpace($repositoryRootFull)) {
        try {
            $failureSnapshot = Get-CddsiRepositorySnapshot -RootPath $repositoryRootFull
            $repositoryChangedAfterFailure = $beforeSnapshot.Hash -cne $failureSnapshot.Hash
        }
        catch {
            $repositoryChangedAfterFailure = $true
        }
    }
    $failureException = $null
    try {
        $timedOut = (
            [string]$primaryError.Exception.Data['CddsiProcessFailureCode'] -ceq
            'PROCESS_TIMEOUT'
        )
        $primaryFailureCode = 'QUALITY_SCENARIO_FAILED'
        if ($timedOut) {
            $primaryFailureCode = if ($null -ne $currentWorkerDescriptor) {
                'QUALITY_WORKER_TIMEOUT'
            }
            else {
                'QUALITY_PROCESS_TIMEOUT'
            }
        }
        $failureProgress = New-CddsiQualityFailureProgress `
            -CompletedRoleEvidence $workerRoleEvidence.ToArray() `
            -CompletedWorkerIds $completedWorkerIds.ToArray() `
            -CurrentWorkerDescriptor $currentWorkerDescriptor `
            -CurrentWorkerFailureEvidence $currentWorkerFailureEvidence `
            -ExpectedWorkerCount $workerInvocationPlan.Count `
            -TimedOut $timedOut
        $failureEvidence = New-CddsiSafeFailureEvidence -Scenario Quality -RunId $runId -PrimaryFailureCode $primaryFailureCode -PrimaryFailureMessage $primaryError.Exception.Message -CleanupOutcome $cleanupOutcome -CleanupFailureCode $cleanupFailureCode -RepositoryContentChanged $repositoryChangedAfterFailure -Progress $failureProgress -PathTokens $pathTokens -OwnershipToken $ownershipToken -CanaryValue $canaryValue
        $failureException = New-CddsiSafeFailureException -Evidence $failureEvidence
    }
    catch {
        $failureException = New-Object System.InvalidOperationException('Isolated quality scenario failed without safe machine-readable evidence.')
    }
    $evidence = $null
    throw $failureException
}

if ($PassThru) { return $evidence }
Write-Host 'Isolated quality scenario passed with an owner-validated sandbox.' -ForegroundColor Green
