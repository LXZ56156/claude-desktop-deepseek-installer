[CmdletBinding()]
param(
    [ValidateSet('Quality')]
    [string]$Scenario = 'Quality',

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
        $safe = $safe.Substring(0, $headLength) + $marker + $safe.Substring($safe.Length - $tailLength)
    }
    return $safe
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
            $safe = [regex]::Replace($safe, [regex]::Escape($value), [string]$token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
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
        if (-not [string]::IsNullOrWhiteSpace($value) -and $Text.IndexOf($value, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return $false }
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
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokens,
        [AllowNull()][string]$OwnershipToken,
        [AllowNull()][string]$CanaryValue
    )

    $safeMessage = Protect-CddsiHarnessText -Text $PrimaryFailureMessage -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
    $safeDisclosure = Test-CddsiSafeDiagnosticDisclosure -Text $safeMessage -PathTokens $PathTokens -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion            = 1
        EvidenceType             = 'CddsiSafeFailureEvidence'
        Scenario                 = $Scenario
        RunId                    = $RunId
        Status                   = 'FAILED_SAFE'
        PrimaryFailureCode       = $PrimaryFailureCode
        SafeFailureMessage       = $safeMessage
        CleanupOutcome           = $CleanupOutcome
        CleanupFailureCode       = $CleanupFailureCode
        RepositoryContentChanged = $RepositoryContentChanged
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
        'RepositoryContentChanged', 'RunId', 'SafeFailureDisclosure', 'SafeFailureMessage',
        'Scenario', 'SchemaVersion', 'Status'
    )
    $actualNames = @($Evidence.PSObject.Properties.Name | Sort-Object)
    if (($expectedNames -join "`n") -cne ($actualNames -join "`n")) { throw 'Safe failure evidence schema drift.' }
    if ($Evidence.SchemaVersion -isnot [int] -or $Evidence.SchemaVersion -ne 1) { throw 'Safe failure evidence version is invalid.' }
    if ($Evidence.EvidenceType -cne 'CddsiSafeFailureEvidence' -or $Evidence.Status -cne 'FAILED_SAFE') { throw 'Safe failure evidence type is invalid.' }
    if ([string]$Evidence.RunId -notmatch '^[a-f0-9]{8}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{4}-[a-f0-9]{12}$') { throw 'Safe failure evidence run binding is invalid.' }
    if ([string]$Evidence.PrimaryFailureCode -notmatch '^[A-Z0-9_]+$' -or [string]$Evidence.CleanupFailureCode -notmatch '^[A-Z0-9_]+$') { throw 'Safe failure evidence code is invalid.' }
    if ($Evidence.RepositoryContentChanged -isnot [bool] -or $Evidence.SafeFailureDisclosure -isnot [bool] -or -not $Evidence.SafeFailureDisclosure) { throw 'Safe failure disclosure validation failed.' }
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

    foreach ($worker in @(
        [pscustomobject]@{ RuleId = 'QualityWorkerPowerShell7'; Engine = 'PowerShell7'; Grant = $PowerShell7Grant; Leaf = 'worker-powershell7.json' }
        [pscustomobject]@{ RuleId = 'QualityWorkerWindowsPowerShell'; Engine = 'WindowsPowerShell'; Grant = $WindowsPowerShellGrant; Leaf = 'worker-windows-powershell.json' }
    )) {
        $rule = Get-CddsiExpectedProcessRuleExact -ExpectedProcessRules $ExpectedProcessRules -RuleId $worker.RuleId
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category Process -RuleId $worker.RuleId -ResourceToken $worker.Grant.ResourceToken -Outcome Succeeded -Data (New-CddsiExpectedProcessLedgerData -ExpectedProcessRule $rule)))
        $sequence++
        $entries.Add((New-CddsiExpectedHarnessLedgerEntry -Sequence $sequence -RunId $RunId -Category FileSystem -RuleId ReadWorkerEvidence -ResourceToken ('<SANDBOX_ROOT>/evidence/{0}' -f $worker.Leaf) -Outcome Succeeded -Data ([pscustomobject][ordered]@{ Engine = [string]$worker.Engine })))
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
        $startInfo.StandardOutputEncoding = New-Object System.Text.UTF8Encoding($false)
        $startInfo.StandardErrorEncoding = New-Object System.Text.UTF8Encoding($false)
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
            try { $process.Kill() } catch { }
            try { $process.WaitForExit() } catch { }
            try { $stdout = [string]$stdoutTask.Result } catch { }
            try { $stderr = [string]$stderrTask.Result } catch { }
            $outcome = 'TimedOut'
        }
        else {
            $process.WaitForExit()
            $stdout = [string]$stdoutTask.Result
            $stderr = [string]$stderrTask.Result
            $exitCode = $process.ExitCode
            if ($exitCode -eq 0) { $outcome = 'Succeeded' }
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
        $timeoutTail = $stderr + [Environment]::NewLine + $stdout
        if ($timeoutTail.Length -gt 5000) {
            $timeoutTail = $timeoutTail.Substring($timeoutTail.Length - 5000)
        }
        $safeTimeoutTail = Protect-CddsiHarnessText -Text $timeoutTail -PathTokens $PathTokens `
            -OwnershipToken $OwnershipToken -CanaryValue $CanaryValue
        if ([string]::IsNullOrWhiteSpace($safeTimeoutTail)) { $safeTimeoutTail = 'NO_SAFE_OUTPUT' }
        throw ('Trusted process timed out: {0}. Last safe output: {1}' -f `
            $RuleId, $safeTimeoutTail.Trim())
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

function Get-CddsiRequiredSuiteSummarySha256 {
    param([Parameter(Mandatory = $true)][object[]]$SuiteResults)

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
        '-GitExecutablePath'
        $gitGrant.Path
        '-GitGrantSha256'
        $gitGrant.Sha256
    )
    $powerShell7WorkerArguments = $workerCommonArguments + @(
        '-EngineId', 'PowerShell7',
        '-EngineExecutablePath', $powerShell7Grant.Path,
        '-EngineGrantSha256', $powerShell7Grant.Sha256
    )
    $windowsPowerShellWorkerArguments = $workerCommonArguments + @(
        '-EngineId', 'WindowsPowerShell',
        '-EngineExecutablePath', $windowsPowerShellGrant.Path,
        '-EngineGrantSha256', $windowsPowerShellGrant.Sha256
    )
    $diffArguments = $gitBaseArguments + @('-c', 'diff.external=', 'diff', '--no-ext-diff', '--check')
    $cachedDiffArguments = $gitBaseArguments + @('-c', 'diff.external=', 'diff', '--cached', '--no-ext-diff', '--check')

    $expectedProcessRules = @(
        New-CddsiExpectedProcessRule -Sequence 1 -RuleId 'GitInventory' -ToolGrant $gitGrant -Arguments $inventoryArguments -Environment $gitEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'
        New-CddsiExpectedProcessRule -Sequence 2 -RuleId 'QualityWorkerPowerShell7' -ToolGrant $powerShell7Grant -Arguments $powerShell7WorkerArguments -Environment $powerShell7Environment -WorkingDirectoryToken '<SANDBOX_ROOT>'
        New-CddsiExpectedProcessRule -Sequence 3 -RuleId 'QualityWorkerWindowsPowerShell' -ToolGrant $windowsPowerShellGrant -Arguments $windowsPowerShellWorkerArguments -Environment $windowsPowerShellEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'
        New-CddsiExpectedProcessRule -Sequence 4 -RuleId 'GitDiffCheck' -ToolGrant $gitGrant -Arguments $diffArguments -Environment $gitEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'
        New-CddsiExpectedProcessRule -Sequence 5 -RuleId 'GitCachedDiffCheck' -ToolGrant $gitGrant -Arguments $cachedDiffArguments -Environment $gitEnvironment -WorkingDirectoryToken '<SANDBOX_ROOT>'
    )

    $inventoryResult = Invoke-CddsiTrustedProcess -RuleId 'GitInventory' -ToolGrant $gitGrant -Arguments $inventoryArguments -Environment $gitEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $inventoryEvidence = Write-CddsiRepositoryInventory -GitOutput $inventoryResult.StdOut -RepositoryRoot $repositoryRootFull -Sandbox $sandbox -Ledger $ledger
    if (-not [string]::Equals($inventoryEvidence.Path, $inventoryPath, [StringComparison]::OrdinalIgnoreCase)) { throw 'Repository inventory path drift.' }
    $null = Invoke-CddsiTrustedProcess -RuleId 'QualityWorkerPowerShell7' -ToolGrant $powerShell7Grant -Arguments $powerShell7WorkerArguments -Environment $powerShell7Environment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $powerShell7Evidence = Read-CddsiWorkerIsolationEvidence -Sandbox $sandbox -Engine 'PowerShell7' -RepositoryRoot $repositoryRootFull -EngineGrant $powerShell7Grant -RepositoryInventoryPath $inventoryPath -BoundaryManifestPath $boundaryManifestPath -DependencyManifestPath $dependencyManifestPath -Ledger $ledger
    $null = Invoke-CddsiTrustedProcess -RuleId 'QualityWorkerWindowsPowerShell' -ToolGrant $windowsPowerShellGrant -Arguments $windowsPowerShellWorkerArguments -Environment $windowsPowerShellEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $windowsPowerShellEvidence = Read-CddsiWorkerIsolationEvidence -Sandbox $sandbox -Engine 'WindowsPowerShell' -RepositoryRoot $repositoryRootFull -EngineGrant $windowsPowerShellGrant -RepositoryInventoryPath $inventoryPath -BoundaryManifestPath $boundaryManifestPath -DependencyManifestPath $dependencyManifestPath -Ledger $ledger
    $workerEvidence = @($powerShell7Evidence, $windowsPowerShellEvidence)
    $null = Invoke-CddsiTrustedProcess -RuleId 'GitDiffCheck' -ToolGrant $gitGrant -Arguments $diffArguments -Environment $gitEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue
    $null = Invoke-CddsiTrustedProcess -RuleId 'GitCachedDiffCheck' -ToolGrant $gitGrant -Arguments $cachedDiffArguments -Environment $gitEnvironment -WorkingDirectory $sandbox.Root -TimeoutSeconds $ProcessTimeoutSeconds -ExpectedProcessRules $expectedProcessRules -ProcessOrdinal ([ref]$processOrdinal) -Ledger $ledger -RunId $runId -PathTokens $pathTokens -OwnershipToken $sandbox.OwnershipToken -CanaryValue $sandbox.CanaryValue

    if ($processOrdinal -ne $expectedProcessRules.Count) { throw 'Trusted process sequence did not complete exactly.' }
    $artifactScanEvidence = Test-CddsiSandboxArtifacts -Sandbox $sandbox -Ledger $ledger
    $afterSnapshot = Get-CddsiRepositorySnapshot -RootPath $repositoryRootFull
    $repositoryContentChanged = $beforeSnapshot.Hash -cne $afterSnapshot.Hash
    if ($repositoryContentChanged) { throw 'Quality checks changed repository content.' }

    $expectedPreCleanupLedger = New-CddsiExpectedQualityHarnessLedger -RunId $runId -PowerShell7Grant $powerShell7Grant -WindowsPowerShellGrant $windowsPowerShellGrant -GitGrant $gitGrant -ExpectedProcessRules $expectedProcessRules -CanaryFileCount $sandbox.CanaryPaths.Count -InventoryFileCount $inventoryEvidence.FileCount -ArtifactScanEvidence $artifactScanEvidence
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
    $expectedFinalLedger = New-CddsiExpectedQualityHarnessLedger -RunId $runId -PowerShell7Grant $powerShell7Grant -WindowsPowerShellGrant $windowsPowerShellGrant -GitGrant $gitGrant -ExpectedProcessRules $expectedProcessRules -CanaryFileCount $sandbox.CanaryPaths.Count -InventoryFileCount $inventoryEvidence.FileCount -ArtifactScanEvidence $artifactScanEvidence -IncludeCleanup
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
        $failureEvidence = New-CddsiSafeFailureEvidence -Scenario Quality -RunId $runId -PrimaryFailureCode 'QUALITY_SCENARIO_FAILED' -PrimaryFailureMessage $primaryError.Exception.Message -CleanupOutcome $cleanupOutcome -CleanupFailureCode $cleanupFailureCode -RepositoryContentChanged $repositoryChangedAfterFailure -PathTokens $pathTokens -OwnershipToken $ownershipToken -CanaryValue $canaryValue
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
