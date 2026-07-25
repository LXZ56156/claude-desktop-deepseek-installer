# common.ps1 - Pure data, safety-policy and serialization helpers.
# Dependency rule: no domain module may be loaded from this file.

$script:CddsiProjectStage = 'Scaffold'

function Get-CddsiProjectStage {
    [CmdletBinding()]
    param()

    return $script:CddsiProjectStage
}

function New-CddsiOperationResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [ValidateSet('SUCCEEDED', 'PARTIAL', 'RESTART_REQUIRED', 'ACTION_REQUIRED', 'CANCELLED', 'FAILED')]
        [string]$Status,

        [bool]$Changed = $false,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [string]$ErrorCode = '',
        [string]$MessageSafe = '',
        [AllowNull()]$Data = $null,
        [bool]$RestartRequired = $false,
        [string[]]$PlannedChanges = @(),
        [string[]]$Warnings = @(),

        [AllowNull()]
        [System.Collections.IDictionary]$PathTokenValues
    )

    if (@('SUCCEEDED', 'PARTIAL', 'RESTART_REQUIRED', 'ACTION_REQUIRED', 'CANCELLED', 'FAILED') -cnotcontains $Status) {
        throw 'Operation result Status must use the canonical uppercase value.'
    }
    if ($Mode -ne 'Live' -and $Changed) {
        throw 'TestSafe 或 DryRun 结果不得声明 Changed=true。'
    }

    return [pscustomobject][ordered]@{
        Operation       = $Operation
        Status          = $Status
        Success         = ($Status -ceq 'SUCCEEDED')
        Changed         = $Changed
        Mode            = $Mode
        ErrorCode       = $ErrorCode
        MessageSafe     = Protect-CddsiReportText -Text $MessageSafe -PathTokenValues $PathTokenValues
        Data            = $Data
        RestartRequired = $RestartRequired
        PlannedChanges  = @($PlannedChanges | ForEach-Object { Protect-CddsiReportText -Text $_ -PathTokenValues $PathTokenValues })
        Warnings        = @($Warnings | ForEach-Object { Protect-CddsiReportText -Text $_ -PathTokenValues $PathTokenValues })
    }
}

function Get-CddsiOperationExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SUCCEEDED', 'PARTIAL', 'RESTART_REQUIRED', 'ACTION_REQUIRED', 'CANCELLED', 'FAILED')]
        [string]$Status
    )

    if (@('SUCCEEDED', 'PARTIAL', 'RESTART_REQUIRED', 'ACTION_REQUIRED', 'CANCELLED', 'FAILED') -cnotcontains $Status) {
        throw 'CLI exit Status must use the canonical uppercase value.'
    }
    return [int]$(switch ($Status) {
        'SUCCEEDED' { 0; break }
        'FAILED' { 1; break }
        'PARTIAL' { 2; break }
        'RESTART_REQUIRED' { 3; break }
        'ACTION_REQUIRED' { 4; break }
        'CANCELLED' { 5; break }
    })
}

function Format-CddsiOperationCliSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    if ($null -eq $Result) { throw 'CLI summary requires an operation result.' }
    foreach ($name in @('Status', 'ErrorCode', 'Changed', 'MessageSafe')) {
        if ($null -eq $Result.PSObject.Properties[$name]) {
            throw "CLI summary result is missing $name."
        }
    }
    $status = [string]$Result.Status
    $null = Get-CddsiOperationExitCode -Status $status
    if ($Result.Changed -isnot [bool]) { throw 'CLI summary Changed must be Boolean.' }

    $errorCode = [string]$Result.ErrorCode
    if ([string]::IsNullOrWhiteSpace($errorCode)) { $errorCode = 'NONE' }
    if ($errorCode -cnotmatch '^[A-Z0-9_]+$') { throw 'CLI summary ErrorCode is invalid.' }

    $nextStep = [string]$(switch ($status) {
        'SUCCEEDED' { 'No further action is required.'; break }
        'FAILED' { 'Review ErrorCode and safe logs before retrying.'; break }
        'PARTIAL' { 'Complete the remaining action identified by ErrorCode, then retry.'; break }
        'RESTART_REQUIRED' { 'Restart Windows, then run the command again.'; break }
        'ACTION_REQUIRED' { 'Complete the required action identified by ErrorCode, then retry.'; break }
        'CANCELLED' { 'Run the command again when ready.'; break }
    })

    return [string[]]@(
        'Status={0}' -f $status
        'ErrorCode={0}' -f $errorCode
        'Changed={0}' -f ([string]$Result.Changed).ToLowerInvariant()
        'NextStep={0}' -f $nextStep
    )
}

function Resolve-CddsiExecutionMode {
    [CmdletBinding()]
    param(
        [switch]$TestSafe,
        [switch]$DryRun,
        [switch]$Live
    )

    $selected = @($TestSafe.IsPresent, $DryRun.IsPresent, $Live.IsPresent | Where-Object { $_ }).Count
    if ($selected -gt 1) {
        throw 'TestSafe、DryRun 和 Live 只能选择一个。'
    }
    if ($Live) { return 'Live' }
    if ($DryRun) { return 'DryRun' }
    return 'TestSafe'
}

function Test-CddsiRealMutationAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null

    # D-026 now has a package-bound VmDevelopment authorization spine, but this
    # mutation decision remains false until a separately tested Live provider
    # implementation consumes the committed operation-use receipt.
    return $false
}

function Assert-CddsiMutationAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiRealMutationAllowed -ExecutionContext $Context -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges)) {
        throw ("操作 '{0}' 被安全边界阻断。当前阶段={1}，模式={2}。" -f $Operation, $Context.Stage, $Mode)
    }
}

function Get-CddsiConfigLibraryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$LocalAppDataPath
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
        throw '无法解析 LOCALAPPDATA。'
    }
    return Join-Path $LocalAppDataPath 'Claude-3p\configLibrary'
}

function Protect-CddsiSecret {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Text
    )

    if ($null -eq $Text) {
        return ''
    }

    $safe = $Text
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9_-])sk-[a-z0-9_-]{20,}(?![a-z0-9_-])', '[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])', 'Bearer [REDACTED]')
    $credentialPattern = '(?i)(?<prefix>"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?)(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}'
    $safe = [regex]::Replace($safe, $credentialPattern, '${prefix}[REDACTED]')
    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $privateKeyPattern = '(?is)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----.*?-----END [^-\r\n]*' + $privateKeyLabel + '-----'
    $safe = [regex]::Replace($safe, $privateKeyPattern, '[REDACTED PRIVATE KEY]')
    return $safe
}

function Protect-CddsiReportText {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$Text,

        [AllowNull()]
        [System.Collections.IDictionary]$PathTokenValues
    )

    $safe = Protect-CddsiSecret -Text $Text
    $pathTokens = [ordered]@{}
    if ($null -ne $PathTokenValues) {
        $requiredTokens = @('%LOCALAPPDATA%', '%USERPROFILE%', '%USERNAME%', '%TEMP%')
        $actualTokens = @($PathTokenValues.Keys | ForEach-Object { [string]$_ })
        if (@(Compare-Object -ReferenceObject @($requiredTokens | Sort-Object) -DifferenceObject @($actualTokens | Sort-Object)).Count -gt 0) {
            throw 'PathTokenValues must contain exactly the supported synthetic token keys.'
        }
        $pathTokens = $PathTokenValues
    }
    foreach ($token in $pathTokens.Keys) {
        $value = $pathTokens[$token]
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $escapedValue = $value.Replace('\', '\\')
            $safe = [regex]::Replace($safe, [regex]::Escape($escapedValue), $token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            $safe = [regex]::Replace($safe, [regex]::Escape($value), $token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    return $safe
}

function Find-CddsiPotentialSecrets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,

        [string]$Source = '<memory>'
    )

    $findings = New-Object System.Collections.Generic.List[object]
    $patterns = @(
        [pscustomobject]@{ Type = 'DeepSeekLikeKey'; Regex = '(?i)(?<![a-z0-9_-])sk-[a-z0-9_-]{20,}(?![a-z0-9_-])' },
        [pscustomobject]@{ Type = 'BearerToken'; Regex = '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])' },
        [pscustomobject]@{ Type = 'CredentialAssignment'; Regex = '(?i)"?(api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}' },
        [pscustomobject]@{ Type = 'PrivateKey'; Regex = ('(?i)-----BEGIN [^-\r\n]*' + ('PRIVATE' + ' KEY') + '-----') }
    )
    $lines = @($Content -split "`r?`n", 0)
    for ($index = 0; $index -lt $lines.Count; $index++) {
        foreach ($pattern in $patterns) {
            if ([regex]::IsMatch($lines[$index], $pattern.Regex)) {
                $findings.Add([pscustomobject][ordered]@{
                    Source   = $Source
                    Line     = $index + 1
                    Type     = $pattern.Type
                    Redacted = '[REDACTED]'
                })
            }
        }
    }
    return @($findings | ForEach-Object { $_ })
}

function Test-CddsiDeepSeekApiKeyFormat {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$ApiKey
    )

    if ([string]::IsNullOrEmpty($ApiKey)) { return $false }
    if ($ApiKey.Length -lt 20 -or $ApiKey.Length -gt 512) { return $false }
    if ($ApiKey -match '[\s\x00-\x1F\x7F]') { return $false }
    return [regex]::IsMatch($ApiKey, '^[\x21-\x7E]+$')
}

function Get-CddsiSupplyChainTextBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Text
    )

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($Text)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Get-CddsiSourceUriBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceUri
    )

    $uri = $null
    if (
        $SourceUri.Length -gt 2048 -or
        -not [Uri]::TryCreate($SourceUri, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or
        -not $uri.IsDefaultPort -or
        $SourceUri -cne $uri.AbsoluteUri -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)
    ) {
        throw 'Source URI binding requires an absolute HTTPS URI without credentials, query or fragment.'
    }
    return Get-CddsiSupplyChainTextBindingToken -Text $uri.AbsoluteUri
}

function Test-CddsiOfficialArtifactUri {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourceUri,
        [Parameter(Mandatory = $true)][ValidateSet('Anthropic', 'GitForWindows')][string]$ExpectedOwner
    )

    $uri = $null
    if (
        $SourceUri.Length -gt 2048 -or
        -not [Uri]::TryCreate($SourceUri, [UriKind]::Absolute, [ref]$uri) -or
        $uri.Scheme -cne 'https' -or
        -not $uri.IsDefaultPort -or
        $SourceUri -cne $uri.AbsoluteUri -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment)
    ) {
        return $false
    }
    $hostName = $uri.DnsSafeHost.ToLowerInvariant()
    $path = $uri.AbsolutePath
    if (
        $path.Contains('\') -or $path.Contains('//') -or $path.Contains('%') -or
        $path -match '(?i)%(?:2e|2f|5c|25)' -or
        @($path.Split('/') | Where-Object { $_ -in @('.', '..') }).Count -gt 0
    ) {
        return $false
    }
    if ($ExpectedOwner -ceq 'Anthropic') {
        if ($hostName -in @('downloads.claude.com', 'downloads.claude.ai')) {
            return [regex]::IsMatch($path, '^/[^?]+\.msix$')
        }
        return (
            $hostName -ceq 'claude.ai' -and
            [regex]::IsMatch($path, '^/api/desktop/win32/(?:x64|arm64)/(?:offline/)?latest/redirect$')
        )
    }
    if ($hostName -ceq 'api.github.com') {
        return $path -in @('/repos/git-for-windows/git/releases/latest', '/repos/git-for-windows/git/releases')
    }
    if ($hostName -ceq 'github.com') {
        return [regex]::IsMatch($path, '^/git-for-windows/git/releases/(?:download/[^/]+/[^/]+|tag/[^/]+)$')
    }
    return $false
}

function Get-CddsiSourceObservationBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Observation
    )

    $fields = @(
        'SchemaVersion', 'ContractVersion', 'RunId', 'ArtifactProfile', 'DescriptorId',
        'MetadataBindingToken', 'RequestUri', 'FinalUri', 'RedirectUris',
        'RedirectChainBindingToken', 'RedirectCount', 'ArtifactSha256',
        'ArtifactSizeBytes', 'ObservationId', 'ObservedAtUtc'
    )
    $validNames = (
        (Test-CddsiExactPropertySet -InputObject $Observation -Expected $fields) -or
        (Test-CddsiExactPropertySet -InputObject $Observation -Expected @($fields + 'SourceObservationBindingToken'))
    )
    if (-not $validNames) { throw 'Source observation does not match the binding schema.' }

    $parts = @()
    foreach ($name in $fields) {
        $value = $Observation.$name
        if ($name -ceq 'RedirectUris') {
            $text = (@($value) -join "`n")
        }
        elseif ($value -is [DateTime]) {
            $text = $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($value -is [DateTimeOffset]) {
            $text = $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            $text = [Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture)
        }
        $parts += ('{0}={1}' -f $name, $text)
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($parts -join "`n")
}

function Test-CddsiSourceObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Observation,
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)][ValidateSet('ClaudeDesktopMsix', 'GitForWindowsInstaller')][string]$ExpectedArtifactType,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 900
    )

    if (-not (Test-CddsiArtifactDescriptor -Descriptor $Descriptor -ExpectedArtifactType $ExpectedArtifactType -RequireResolved)) { return $false }
    $required = @(
        'SchemaVersion', 'ContractVersion', 'RunId', 'ArtifactProfile', 'DescriptorId',
        'MetadataBindingToken', 'RequestUri', 'FinalUri', 'RedirectUris',
        'RedirectChainBindingToken', 'RedirectCount', 'ArtifactSha256',
        'ArtifactSizeBytes', 'ObservationId', 'ObservedAtUtc', 'SourceObservationBindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Observation -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Observation.SchemaVersion) -or $Observation.ContractVersion -cne 'cddsi-source-observation-v1') { return $false }
    if (-not (Test-CddsiCanonicalUuidValue -Value $ExpectedRunId) -or $Observation.RunId -cne $ExpectedRunId) { return $false }
    if ($Observation.ArtifactProfile -isnot [string] -or $Observation.ArtifactProfile -cne $ExpectedProfile) { return $false }
    if ($Observation.DescriptorId -cne $Descriptor.DescriptorId -or $Observation.MetadataBindingToken -cne $Descriptor.MetadataBindingToken) { return $false }
    if ($Observation.RequestUri -cne $Descriptor.SourceUri) { return $false }
    $owner = if ($ExpectedArtifactType -ceq 'ClaudeDesktopMsix') { 'Anthropic' } else { 'GitForWindows' }
    $redirectUris = @($Observation.RedirectUris)
    if ($Observation.RedirectUris -isnot [System.Array] -or ($Observation.RedirectCount -isnot [int] -and $Observation.RedirectCount -isnot [long]) -or [long]$Observation.RedirectCount -ne $redirectUris.Count -or $redirectUris.Count -gt 10) { return $false }
    $seenUris = @{}
    foreach ($uri in @($Observation.RequestUri) + $redirectUris) {
        if ($uri -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $uri -ExpectedOwner $owner) -or $seenUris.ContainsKey($uri)) { return $false }
        $seenUris[$uri] = $true
    }
    $expectedFinalUri = if ($redirectUris.Count -eq 0) { $Observation.RequestUri } else { $redirectUris[-1] }
    if ($Observation.FinalUri -cne $expectedFinalUri) { return $false }
    $expectedChainBinding = Get-CddsiSupplyChainTextBindingToken -Text ((@($Observation.RequestUri) + $redirectUris) -join "`n")
    if ($Observation.RedirectChainBindingToken -isnot [string] -or $Observation.RedirectChainBindingToken -cne $expectedChainBinding) { return $false }
    if ($Observation.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $Observation.ArtifactSha256 -ExpectedSha256 $Descriptor.ExpectedArtifactSha256)) { return $false }
    if (($Observation.ArtifactSizeBytes -isnot [int] -and $Observation.ArtifactSizeBytes -isnot [long]) -or [long]$Observation.ArtifactSizeBytes -ne [long]$Descriptor.ExpectedArtifactSizeBytes) { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $Observation.ObservationId -MaxLength 128)) { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $Observation.ObservedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)) { return $false }
    $observedAt = [DateTimeOffset]::Parse($Observation.ObservedAtUtc)
    $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if ($observedAt -gt $validationTime -or ($validationTime - $observedAt).TotalSeconds -gt $MaximumAgeSeconds) { return $false }
    if ($Observation.SourceObservationBindingToken -isnot [string] -or $Observation.SourceObservationBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Observation.SourceObservationBindingToken -ceq (Get-CddsiSourceObservationBindingToken -Observation $Observation))
    }
    catch {
        return $false
    }
}

function Get-CddsiArtifactDescriptorBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Descriptor
    )

    $fields = @(
        'SchemaVersion', 'DescriptorId', 'ArtifactType', 'SourcePolicy', 'SourceUri',
        'SourceUriBindingToken', 'ReleaseVersion', 'Architecture', 'Channel', 'FileNameToken',
        'ExpectedArtifactSha256', 'ExpectedArtifactSizeBytes', 'ExpectedSignerThumbprint',
        'ExpectedSignerSubjectToken', 'ExpectedPublisherToken', 'ExpectedIdentityToken',
        'RedirectPolicy', 'MaximumBytes', 'MetadataStatus'
    )
    $validNames = (
        (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected $fields) -or
        (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected @($fields + 'MetadataBindingToken'))
    )
    if (-not $validNames) { throw 'Artifact descriptor does not match the binding schema.' }

    $parts = @()
    foreach ($name in $fields) {
        $value = $Descriptor.$name
        $text = if ($null -eq $value) {
            '<NULL>'
        }
        elseif ($value -is [bool]) {
            if ($value) { 'true' } else { 'false' }
        }
        else {
            [Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture)
        }
        $parts += ('{0}={1}' -f $name, $text)
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($parts -join "`n")
}

function Test-CddsiArtifactDescriptor {
    [CmdletBinding()]
    param(
        [AllowNull()]$Descriptor,
        [Parameter(Mandatory = $true)][ValidateSet('ClaudeDesktopMsix', 'GitForWindowsInstaller')][string]$ExpectedArtifactType,
        [switch]$RequireResolved
    )

    $required = @(
        'SchemaVersion', 'DescriptorId', 'ArtifactType', 'SourcePolicy', 'SourceUri',
        'SourceUriBindingToken', 'ReleaseVersion', 'Architecture', 'Channel', 'FileNameToken',
        'ExpectedArtifactSha256', 'ExpectedArtifactSizeBytes', 'ExpectedSignerThumbprint',
        'ExpectedSignerSubjectToken', 'ExpectedPublisherToken', 'ExpectedIdentityToken',
        'RedirectPolicy', 'MaximumBytes', 'MetadataStatus', 'MetadataBindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Descriptor.SchemaVersion)) { return $false }
    if ($Descriptor.ArtifactType -isnot [string] -or $Descriptor.ArtifactType -cne $ExpectedArtifactType) { return $false }
    $expectedSourcePolicy = if ($ExpectedArtifactType -ceq 'ClaudeDesktopMsix') { 'anthropic_official_only' } else { 'git_for_windows_official_only' }
    $expectedOwner = if ($ExpectedArtifactType -ceq 'ClaudeDesktopMsix') { 'Anthropic' } else { 'GitForWindows' }
    if ($Descriptor.SourcePolicy -isnot [string] -or $Descriptor.SourcePolicy -cne $expectedSourcePolicy) { return $false }
    if ($Descriptor.SourceUri -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $Descriptor.SourceUri -ExpectedOwner $expectedOwner)) { return $false }
    try {
        $expectedSourceBinding = Get-CddsiSourceUriBindingToken -SourceUri $Descriptor.SourceUri
    }
    catch {
        return $false
    }
    if ($Descriptor.SourceUriBindingToken -isnot [string] -or $Descriptor.SourceUriBindingToken -cne $expectedSourceBinding) { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $Descriptor.DescriptorId -MaxLength 128)) { return $false }
    $parsedVersion = $null
    if ($Descriptor.ReleaseVersion -isnot [string] -or -not [version]::TryParse($Descriptor.ReleaseVersion, [ref]$parsedVersion)) { return $false }
    if ($Descriptor.Architecture -isnot [string] -or @('x64', 'arm64') -cnotcontains $Descriptor.Architecture) { return $false }
    if ($Descriptor.Channel -isnot [string] -or @('Standard', 'Offline', 'Installer') -cnotcontains $Descriptor.Channel) { return $false }
    if (
        ($ExpectedArtifactType -ceq 'ClaudeDesktopMsix' -and @('Standard', 'Offline') -cnotcontains $Descriptor.Channel) -or
        ($ExpectedArtifactType -ceq 'GitForWindowsInstaller' -and $Descriptor.Channel -cne 'Installer')
    ) { return $false }
    if ($Descriptor.FileNameToken -isnot [string] -or -not [regex]::IsMatch($Descriptor.FileNameToken, '^<[A-Z0-9_:-]+>(?:[\\/][A-Za-z0-9_.-]+)*$')) { return $false }
    if ($null -ne $Descriptor.ExpectedArtifactSha256 -and ($Descriptor.ExpectedArtifactSha256 -isnot [string] -or $Descriptor.ExpectedArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$')) { return $false }
    if ($null -ne $Descriptor.ExpectedArtifactSizeBytes -and (($Descriptor.ExpectedArtifactSizeBytes -isnot [int] -and $Descriptor.ExpectedArtifactSizeBytes -isnot [long]) -or [long]$Descriptor.ExpectedArtifactSizeBytes -lt 1)) { return $false }
    if ($null -ne $Descriptor.ExpectedSignerThumbprint -and ($Descriptor.ExpectedSignerThumbprint -isnot [string] -or $Descriptor.ExpectedSignerThumbprint -notmatch '^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$')) { return $false }
    foreach ($name in @('ExpectedSignerSubjectToken', 'ExpectedPublisherToken', 'ExpectedIdentityToken')) {
        if ($null -ne $Descriptor.$name -and ($Descriptor.$name -isnot [string] -or -not [regex]::IsMatch($Descriptor.$name, '^<[A-Z0-9_:-]+>(?:[\\/][A-Za-z0-9_.-]+)*$'))) { return $false }
    }
    if ($Descriptor.RedirectPolicy -isnot [string] -or $Descriptor.RedirectPolicy -cne 'same-owner-https-only') { return $false }
    if (($Descriptor.MaximumBytes -isnot [int] -and $Descriptor.MaximumBytes -isnot [long]) -or [long]$Descriptor.MaximumBytes -lt 1) { return $false }
    if ($null -ne $Descriptor.ExpectedArtifactSizeBytes -and [long]$Descriptor.ExpectedArtifactSizeBytes -gt [long]$Descriptor.MaximumBytes) { return $false }
    if ($Descriptor.MetadataStatus -isnot [string] -or @('READY', 'UNRESOLVED') -cnotcontains $Descriptor.MetadataStatus) { return $false }
    $resolved = (
        $null -ne $Descriptor.ExpectedArtifactSha256 -and $null -ne $Descriptor.ExpectedArtifactSizeBytes -and
        $null -ne $Descriptor.ExpectedSignerThumbprint -and $null -ne $Descriptor.ExpectedSignerSubjectToken -and
        $null -ne $Descriptor.ExpectedPublisherToken -and $null -ne $Descriptor.ExpectedIdentityToken
    )
    if (($Descriptor.MetadataStatus -ceq 'READY') -ne $resolved) { return $false }
    if ($RequireResolved -and -not $resolved) { return $false }
    if ($Descriptor.MetadataBindingToken -isnot [string] -or $Descriptor.MetadataBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($Descriptor.MetadataBindingToken -ceq (Get-CddsiArtifactDescriptorBindingToken -Descriptor $Descriptor))
    }
    catch {
        return $false
    }
}

function Get-CddsiSignatureEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $fields = @(
        'SchemaVersion', 'EvidenceKind', 'ObservationStatus', 'Verdict', 'ArtifactType',
        'VerificationStage', 'RunId', 'ArtifactProfile', 'PathBindingToken', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes',
        'Architecture', 'ArtifactVersion', 'SourcePolicy', 'SourceDescriptorId',
        'SourceUriBindingToken', 'MetadataBindingToken', 'SourceObservationId',
        'SourceObservationBindingToken', 'SignerThumbprint',
        'SignerSubjectToken', 'PublisherToken', 'IdentityToken', 'AuthenticodeStatus',
        'ChainTrusted', 'HashMatch', 'SizeMatch', 'SignerMatch', 'PublisherMatch',
        'IdentityMatch', 'ArchitectureMatch', 'VersionMatch', 'SourceMatch',
        'ObservationId', 'ObservedAtUtc', 'Valid'
    )
    $validNames = (
        (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $fields) -or
        (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @($fields + 'EvidenceBindingToken'))
    )
    if (-not $validNames) { throw 'Signature evidence does not match the binding schema.' }
    $parts = @()
    foreach ($name in $fields) {
        $value = $Evidence.$name
        $text = if ($null -eq $value) {
            '<NULL>'
        }
        elseif ($value -is [bool]) {
            if ($value) { 'true' } else { 'false' }
        }
        elseif ($value -is [DateTime]) {
            $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($value -is [DateTimeOffset]) {
            $value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
        }
        else {
            [Convert]::ToString($value, [Globalization.CultureInfo]::InvariantCulture)
        }
        $parts += ('{0}={1}' -f $name, $text)
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($parts -join "`n")
}

function New-CddsiSignatureEvidenceVerdict {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)][ValidateSet('ClaudeDesktopMsix', 'GitForWindowsInstaller')][string]$ExpectedArtifactType,
        [Parameter(Mandatory = $true)][string]$PathBindingToken,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)]$FileObservation,
        [Parameter(Mandatory = $true)]$SignatureObservation,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 900
    )

    if (-not (Test-CddsiArtifactDescriptor -Descriptor $Descriptor -ExpectedArtifactType $ExpectedArtifactType -RequireResolved)) {
        throw 'A resolved artifact descriptor is required to produce a signature verdict.'
    }
    if ($PathBindingToken -notmatch '^[a-f0-9]{64}$') { throw 'PathBindingToken is invalid.' }
    if (-not (Test-CddsiSourceObservation -Observation $SourceObservation -Descriptor $Descriptor -ExpectedArtifactType $ExpectedArtifactType -ExpectedRunId $ExpectedRunId -ExpectedProfile $ExpectedProfile -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) {
        throw 'Source observation is invalid, stale or not bound to the descriptor and run.'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $FileObservation -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes'))) {
        throw 'File observation does not match the exact schema.'
    }
    if (
        -not (Test-CddsiSchemaVersionOne -Value $FileObservation.SchemaVersion) -or
        $FileObservation.FileIdentityToken -isnot [string] -or $FileObservation.FileIdentityToken -notmatch '^[a-f0-9]{64}$' -or
        $FileObservation.ArtifactSha256 -isnot [string] -or $FileObservation.ArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        ($FileObservation.ArtifactSizeBytes -isnot [int] -and $FileObservation.ArtifactSizeBytes -isnot [long]) -or
        [long]$FileObservation.ArtifactSizeBytes -lt 1
    ) {
        throw 'File observation values are invalid.'
    }
    $signatureFields = @(
        'SchemaVersion', 'ArtifactSha256', 'AuthenticodeStatus', 'ChainTrusted',
        'SignerThumbprint', 'SignerSubjectToken', 'PublisherToken', 'IdentityToken',
        'Architecture', 'ArtifactVersion', 'ObservationId', 'ObservedAtUtc'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $SignatureObservation -Expected $signatureFields)) {
        throw 'Signature observation does not match the exact schema.'
    }
    if (
        -not (Test-CddsiSchemaVersionOne -Value $SignatureObservation.SchemaVersion) -or
        $SignatureObservation.ArtifactSha256 -isnot [string] -or $SignatureObservation.ArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$' -or
        $SignatureObservation.AuthenticodeStatus -isnot [string] -or @('Valid', 'Invalid', 'Unknown') -cnotcontains $SignatureObservation.AuthenticodeStatus -or
        $SignatureObservation.ChainTrusted -isnot [bool] -or
        $SignatureObservation.SignerThumbprint -isnot [string] -or $SignatureObservation.SignerThumbprint -notmatch '^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$' -or
        $SignatureObservation.SignerSubjectToken -isnot [string] -or -not [regex]::IsMatch($SignatureObservation.SignerSubjectToken, '^<[A-Z0-9_:-]+>(?:[\\/][A-Za-z0-9_.-]+)*$') -or
        $SignatureObservation.PublisherToken -isnot [string] -or -not [regex]::IsMatch($SignatureObservation.PublisherToken, '^<[A-Z0-9_:-]+>(?:[\\/][A-Za-z0-9_.-]+)*$') -or
        $SignatureObservation.IdentityToken -isnot [string] -or -not [regex]::IsMatch($SignatureObservation.IdentityToken, '^<[A-Z0-9_:-]+>(?:[\\/][A-Za-z0-9_.-]+)*$') -or
        $SignatureObservation.Architecture -isnot [string] -or @('x64', 'arm64') -cnotcontains $SignatureObservation.Architecture -or
        $SignatureObservation.ArtifactVersion -isnot [string] -or
        -not (Test-CddsiSafeIdentifierValue -Value $SignatureObservation.ObservationId -MaxLength 128) -or
        -not (Test-CddsiUtcTimestampValue -Value $SignatureObservation.ObservedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)
    ) {
        throw 'Signature observation values are invalid.'
    }
    $signatureObservedAt = [DateTimeOffset]::Parse($SignatureObservation.ObservedAtUtc)
    $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if ($signatureObservedAt -lt [DateTimeOffset]::Parse($SourceObservation.ObservedAtUtc) -or $signatureObservedAt -gt $validationTime -or ($validationTime - $signatureObservedAt).TotalSeconds -gt $MaximumAgeSeconds) {
        throw 'Signature observation is from the future or is stale.'
    }

    $hashMatch = (
        (Test-CddsiArtifactHashBinding -ActualSha256 $FileObservation.ArtifactSha256 -ExpectedSha256 $Descriptor.ExpectedArtifactSha256) -and
        (Test-CddsiArtifactHashBinding -ActualSha256 $SignatureObservation.ArtifactSha256 -ExpectedSha256 $FileObservation.ArtifactSha256)
    )
    $sizeMatch = ([long]$FileObservation.ArtifactSizeBytes -eq [long]$Descriptor.ExpectedArtifactSizeBytes)
    $signerMatch = [string]::Equals($SignatureObservation.SignerThumbprint, $Descriptor.ExpectedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase) -and $SignatureObservation.SignerSubjectToken -ceq $Descriptor.ExpectedSignerSubjectToken
    $publisherMatch = ($SignatureObservation.PublisherToken -ceq $Descriptor.ExpectedPublisherToken)
    $identityMatch = ($SignatureObservation.IdentityToken -ceq $Descriptor.ExpectedIdentityToken)
    $architectureMatch = ($SignatureObservation.Architecture -ceq $Descriptor.Architecture)
    $versionMatch = ($SignatureObservation.ArtifactVersion -ceq $Descriptor.ReleaseVersion)
    $sourceMatch = (
        $SourceObservation.RunId -ceq $ExpectedRunId -and
        $SourceObservation.ArtifactProfile -ceq $ExpectedProfile -and
        $SourceObservation.DescriptorId -ceq $Descriptor.DescriptorId -and
        $SourceObservation.MetadataBindingToken -ceq $Descriptor.MetadataBindingToken -and
        $SourceObservation.RequestUri -ceq $Descriptor.SourceUri -and
        (Test-CddsiArtifactHashBinding -ActualSha256 $SourceObservation.ArtifactSha256 -ExpectedSha256 $FileObservation.ArtifactSha256) -and
        [long]$SourceObservation.ArtifactSizeBytes -eq [long]$FileObservation.ArtifactSizeBytes
    )
    $valid = (
        $SignatureObservation.AuthenticodeStatus -ceq 'Valid' -and $SignatureObservation.ChainTrusted -and
        $hashMatch -and $sizeMatch -and $signerMatch -and $publisherMatch -and $identityMatch -and
        $architectureMatch -and $versionMatch -and $sourceMatch
    )
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion         = 2
        EvidenceKind          = 'ArtifactSignatureVerdict'
        ObservationStatus     = 'COMPLETE'
        Verdict               = if ($valid) { 'TRUSTED' } else { 'REJECTED' }
        ArtifactType          = $ExpectedArtifactType
        VerificationStage     = 'PreInstall'
        RunId                 = $ExpectedRunId
        ArtifactProfile       = $ExpectedProfile
        PathBindingToken      = $PathBindingToken
        FileIdentityToken     = $FileObservation.FileIdentityToken
        ArtifactSha256        = $FileObservation.ArtifactSha256.ToLowerInvariant()
        ArtifactSizeBytes     = [long]$FileObservation.ArtifactSizeBytes
        Architecture          = $SignatureObservation.Architecture
        ArtifactVersion       = $SignatureObservation.ArtifactVersion
        SourcePolicy          = $Descriptor.SourcePolicy
        SourceDescriptorId    = $Descriptor.DescriptorId
        SourceUriBindingToken = $Descriptor.SourceUriBindingToken
        MetadataBindingToken  = $Descriptor.MetadataBindingToken
        SourceObservationId   = $SourceObservation.ObservationId
        SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken
        SignerThumbprint      = $SignatureObservation.SignerThumbprint.ToLowerInvariant()
        SignerSubjectToken    = $SignatureObservation.SignerSubjectToken
        PublisherToken        = $SignatureObservation.PublisherToken
        IdentityToken         = $SignatureObservation.IdentityToken
        AuthenticodeStatus    = $SignatureObservation.AuthenticodeStatus
        ChainTrusted          = [bool]$SignatureObservation.ChainTrusted
        HashMatch             = $hashMatch
        SizeMatch             = $sizeMatch
        SignerMatch           = $signerMatch
        PublisherMatch        = $publisherMatch
        IdentityMatch         = $identityMatch
        ArchitectureMatch     = $architectureMatch
        VersionMatch          = $versionMatch
        SourceMatch           = $sourceMatch
        ObservationId         = $SignatureObservation.ObservationId
        ObservedAtUtc         = $SignatureObservation.ObservedAtUtc
        Valid                 = $valid
    }
    $binding = Get-CddsiSignatureEvidenceBindingToken -Evidence $withoutBinding
    $evidence = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) { $evidence[$property.Name] = $property.Value }
    $evidence['EvidenceBindingToken'] = $binding
    return [pscustomobject]$evidence
}

function Test-CddsiSignatureEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()]$Evidence,
        [Parameter(Mandatory = $true)][string]$ExpectedPath,
        [Parameter(Mandatory = $true)][ValidateSet('ClaudeDesktopMsix', 'GitForWindowsInstaller')][string]$ExpectedArtifactType,
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 900
    )

    if (-not (Test-CddsiArtifactDescriptor -Descriptor $Descriptor -ExpectedArtifactType $ExpectedArtifactType -RequireResolved)) { return $false }
    if (-not (Test-CddsiSourceObservation -Observation $SourceObservation -Descriptor $Descriptor -ExpectedArtifactType $ExpectedArtifactType -ExpectedRunId $ExpectedRunId -ExpectedProfile $ExpectedProfile -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) { return $false }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $Evidence

    $required = @(
        'SchemaVersion', 'EvidenceKind', 'ObservationStatus', 'Verdict', 'ArtifactType',
        'VerificationStage', 'RunId', 'ArtifactProfile', 'PathBindingToken', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes',
        'Architecture', 'ArtifactVersion', 'SourcePolicy', 'SourceDescriptorId',
        'SourceUriBindingToken', 'MetadataBindingToken', 'SourceObservationId',
        'SourceObservationBindingToken', 'SignerThumbprint',
        'SignerSubjectToken', 'PublisherToken', 'IdentityToken', 'AuthenticodeStatus',
        'ChainTrusted', 'HashMatch', 'SizeMatch', 'SignerMatch', 'PublisherMatch',
        'IdentityMatch', 'ArchitectureMatch', 'VersionMatch', 'SourceMatch',
        'ObservationId', 'ObservedAtUtc', 'Valid', 'EvidenceBindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $payload -Expected $required)) { return $false }
    if (($payload.SchemaVersion -isnot [int] -and $payload.SchemaVersion -isnot [long]) -or [long]$payload.SchemaVersion -ne 2) { return $false }
    if ($payload.EvidenceKind -isnot [string] -or $payload.EvidenceKind -cne 'ArtifactSignatureVerdict') { return $false }
    if ($payload.ObservationStatus -isnot [string] -or $payload.ObservationStatus -cne 'COMPLETE') { return $false }
    if ($payload.Verdict -isnot [string] -or $payload.Verdict -cne 'TRUSTED') { return $false }
    if ($payload.ArtifactType -isnot [string] -or $payload.ArtifactType -cne $ExpectedArtifactType) { return $false }
    if ($payload.VerificationStage -isnot [string] -or $payload.VerificationStage -cne 'PreInstall') { return $false }
    if ($payload.RunId -isnot [string] -or $payload.RunId -cne $ExpectedRunId) { return $false }
    if ($payload.ArtifactProfile -isnot [string] -or $payload.ArtifactProfile -cne $ExpectedProfile) { return $false }
    try {
        $expectedPathBindingToken = Get-CddsiPathBindingToken -Path $ExpectedPath
    }
    catch {
        return $false
    }
    if ($payload.PathBindingToken -isnot [string] -or $payload.PathBindingToken -cne $expectedPathBindingToken) { return $false }
    if ($payload.FileIdentityToken -isnot [string] -or $payload.FileIdentityToken -notmatch '^[a-f0-9]{64}$') { return $false }
    if ($payload.ArtifactSha256 -isnot [string] -or $payload.ArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    if (-not (Test-CddsiArtifactHashBinding -ActualSha256 $payload.ArtifactSha256 -ExpectedSha256 $Descriptor.ExpectedArtifactSha256)) { return $false }
    if (($payload.ArtifactSizeBytes -isnot [int] -and $payload.ArtifactSizeBytes -isnot [long]) -or [long]$payload.ArtifactSizeBytes -ne [long]$Descriptor.ExpectedArtifactSizeBytes) { return $false }
    if ($payload.Architecture -isnot [string] -or $payload.Architecture -cne $Descriptor.Architecture) { return $false }
    if ($payload.ArtifactVersion -isnot [string] -or $payload.ArtifactVersion -cne $Descriptor.ReleaseVersion) { return $false }
    if ($payload.SourcePolicy -isnot [string] -or $payload.SourcePolicy -cne $Descriptor.SourcePolicy) { return $false }
    if ($payload.SourceDescriptorId -isnot [string] -or $payload.SourceDescriptorId -cne $Descriptor.DescriptorId) { return $false }
    if ($payload.SourceUriBindingToken -isnot [string] -or $payload.SourceUriBindingToken -cne $Descriptor.SourceUriBindingToken) { return $false }
    if ($payload.MetadataBindingToken -isnot [string] -or $payload.MetadataBindingToken -cne $Descriptor.MetadataBindingToken) { return $false }
    if ($payload.SourceObservationId -isnot [string] -or $payload.SourceObservationId -cne $SourceObservation.ObservationId) { return $false }
    if ($payload.SourceObservationBindingToken -isnot [string] -or $payload.SourceObservationBindingToken -cne $SourceObservation.SourceObservationBindingToken) { return $false }
    if ($payload.SignerThumbprint -isnot [string] -or -not [string]::Equals($payload.SignerThumbprint, $Descriptor.ExpectedSignerThumbprint, [StringComparison]::OrdinalIgnoreCase)) { return $false }
    if ($payload.SignerSubjectToken -isnot [string] -or $payload.SignerSubjectToken -cne $Descriptor.ExpectedSignerSubjectToken) { return $false }
    if ($payload.PublisherToken -isnot [string] -or $payload.PublisherToken -cne $Descriptor.ExpectedPublisherToken) { return $false }
    if ($payload.IdentityToken -isnot [string] -or $payload.IdentityToken -cne $Descriptor.ExpectedIdentityToken) { return $false }
    foreach ($name in @('Valid', 'ChainTrusted', 'HashMatch', 'SizeMatch', 'SignerMatch', 'PublisherMatch', 'IdentityMatch', 'ArchitectureMatch', 'VersionMatch', 'SourceMatch')) {
        if ($payload.$name -isnot [bool] -or -not $payload.$name) { return $false }
    }
    if ($payload.AuthenticodeStatus -isnot [string] -or $payload.AuthenticodeStatus -cne 'Valid') { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $payload.ObservationId -MaxLength 128)) { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $payload.ObservedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)) { return $false }
    $observedAt = [DateTimeOffset]::Parse($payload.ObservedAtUtc)
    $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if ($observedAt -lt [DateTimeOffset]::Parse($SourceObservation.ObservedAtUtc) -or $observedAt -gt $validationTime -or ($validationTime - $observedAt).TotalSeconds -gt $MaximumAgeSeconds) { return $false }
    if ($payload.EvidenceBindingToken -isnot [string] -or $payload.EvidenceBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    try {
        return ($payload.EvidenceBindingToken -ceq (Get-CddsiSignatureEvidenceBindingToken -Evidence $payload))
    }
    catch {
        return $false
    }
}

function Test-CddsiSchemaVersionOne {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value
    )

    return (($Value -is [int] -or $Value -is [long]) -and [long]$Value -eq 1)
}

function Test-CddsiUtcTimestampValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value
    )

    if ($Value -is [DateTime]) { return ($Value.Kind -eq [DateTimeKind]::Utc) }
    if ($Value -is [DateTimeOffset]) { return ($Value.Offset -eq [TimeSpan]::Zero) }
    if (
        $Value -isnot [string] -or
        [string]::IsNullOrWhiteSpace($Value) -or
        -not [regex]::IsMatch($Value, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$')
    ) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    [string[]]$formats = @("yyyy-MM-dd'T'HH:mm:ss'Z'", "yyyy-MM-dd'T'HH:mm:ss.FFFFFFF'Z'")
    $styles = [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal
    return (
        [DateTimeOffset]::TryParseExact($Value, $formats, [Globalization.CultureInfo]::InvariantCulture, $styles, [ref]$parsed) -and
        $parsed.Offset -eq [TimeSpan]::Zero
    )
}

function Test-CddsiSafeIdentifierValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [switch]$AllowNull,
        [ValidateRange(1, 256)][int]$MaxLength = 128
    )

    if ($null -eq $Value) { return $AllowNull.IsPresent }
    if ($Value -isnot [string] -or $Value.Length -lt 1 -or $Value.Length -gt $MaxLength) { return $false }
    return [regex]::IsMatch($Value, '^[A-Za-z0-9][A-Za-z0-9._-]*$')
}

function Test-CddsiCanonicalUuidValue {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value
    )

    return (
        $Value -is [string] -and
        [regex]::IsMatch($Value, '^[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') -and
        $Value -cne '00000000-0000-0000-0000-000000000000'
    )
}

function Get-CddsiPathBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ([string]::IsNullOrWhiteSpace($Path) -or -not [System.IO.Path]::IsPathRooted($Path)) {
        throw 'Path binding requires an explicit absolute path.'
    }
    $canonical = [System.IO.Path]::GetFullPath($Path).TrimEnd([char[]]@('\', '/')).ToUpperInvariant()
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $bytes = [System.Text.Encoding]::UTF8.GetBytes($canonical)
        return ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function Test-CddsiArtifactHashBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ActualSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if ($ActualSha256 -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    return [string]::Equals($ActualSha256, $ExpectedSha256, [StringComparison]::OrdinalIgnoreCase)
}

function ConvertFrom-CddsiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Content,

        [string]$Source = '<memory>'
    )

    try {
        return $Content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "JSON 内容无效: $Source。$($_.Exception.Message)"
    }
}

function ConvertTo-CddsiJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,
        [ValidateRange(2, 100)]
        [int]$Depth = 20
    )

    return $InputObject | ConvertTo-Json -Depth $Depth
}

function Test-CddsiExactPropertySet {
    [CmdletBinding()]
    param(
        [AllowNull()]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Expected
    )

    if ($null -eq $InputObject) { return $false }
    $actualNames = @($InputObject.PSObject.Properties.Name | Sort-Object)
    $expectedNames = @($Expected | Sort-Object)
    if ($actualNames.Count -ne $expectedNames.Count) { return $false }
    return (($actualNames -join "`n") -ceq ($expectedNames -join "`n"))
}

function Get-CddsiSignatureEvidencePayload {
    [CmdletBinding()]
    param(
        [AllowNull()]$Evidence
    )

    if ($null -eq $Evidence) { return $null }
    $properties = @($Evidence.PSObject.Properties.Name)
    if ($properties -contains 'Data') {
        $operationResultProperties = @(
            'Operation', 'Status', 'Success', 'Changed', 'Mode', 'ErrorCode',
            'MessageSafe', 'Data', 'RestartRequired', 'PlannedChanges', 'Warnings'
        )
        if (
            -not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $operationResultProperties) -or
            $Evidence.Status -cne 'SUCCEEDED' -or
            $Evidence.Success -isnot [bool] -or -not $Evidence.Success -or
            $Evidence.Changed -isnot [bool] -or $Evidence.Changed -or
            $null -eq $Evidence.Data
        ) {
            return $null
        }
        return $Evidence.Data
    }
    return $Evidence
}
