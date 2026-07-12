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
        [string]$Status,

        [bool]$Success = $false,
        [bool]$Changed = $false,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [string]$ErrorCode = '',
        [string]$MessageSafe = '',
        [AllowNull()]$Data = $null,
        [bool]$RestartRequired = $false,
        [string[]]$PlannedChanges = @(),
        [string[]]$Warnings = @()
    )

    return [pscustomobject][ordered]@{
        Operation       = $Operation
        Status          = $Status
        Success         = $Success
        Changed         = $Changed
        Mode            = $Mode
        ErrorCode       = $ErrorCode
        MessageSafe     = Protect-CddsiReportText -Text $MessageSafe
        Data            = $Data
        RestartRequired = $RestartRequired
        PlannedChanges  = @($PlannedChanges | ForEach-Object { Protect-CddsiReportText -Text $_ })
        Warnings        = @($Warnings | ForEach-Object { Protect-CddsiReportText -Text $_ })
    }
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
        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    return ($Mode -eq 'Live' -and $AcknowledgeRealChanges.IsPresent -and (Get-CddsiProjectStage) -eq 'Implemented')
}

function Assert-CddsiMutationAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiRealMutationAllowed -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges)) {
        throw ("操作 '{0}' 被安全边界阻断。当前阶段={1}，模式={2}。" -f $Operation, (Get-CddsiProjectStage), $Mode)
    }
}

function Get-CddsiConfigLibraryPath {
    [CmdletBinding()]
    param(
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData')
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
        [AllowNull()][string]$Text
    )

    $safe = Protect-CddsiSecret -Text $Text
    $pathTokens = [ordered]@{
        '%LOCALAPPDATA%' = [Environment]::GetFolderPath('LocalApplicationData')
        '%USERPROFILE%'  = [Environment]::GetFolderPath('UserProfile')
        '%USERNAME%'     = [Environment]::UserName
        '%TEMP%'         = [System.IO.Path]::GetTempPath().TrimEnd('\')
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
    if ($ApiKey -match '[\s\x00-\x1F\x7F]') { return $false }
    return [regex]::IsMatch($ApiKey, '^sk-[A-Za-z0-9_-]{20,}$')
}

function Test-CddsiSignatureEvidence {
    [CmdletBinding()]
    param(
        [AllowNull()]$Evidence,
        [Parameter(Mandatory = $true)][string]$ExpectedPath,
        [Parameter(Mandatory = $true)]
        [ValidateSet('ClaudeDesktopMsix', 'GitForWindowsInstaller')]
        [string]$ExpectedArtifactType
    )

    if ($null -eq $Evidence) { return $false }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $Evidence

    $names = @($payload.PSObject.Properties.Name)
    $required = @('SchemaVersion', 'ArtifactType', 'PathBindingToken', 'ArtifactSha256', 'Valid', 'AuthenticodeStatus', 'ChainTrusted', 'PublisherMatch', 'IdentityMatch', 'SourcePolicy')
    foreach ($name in $required) {
        if ($names -notcontains $name) { return $false }
    }
    if (-not (Test-CddsiSchemaVersionOne -Value $payload.SchemaVersion)) { return $false }
    if ($payload.ArtifactType -isnot [string] -or $payload.ArtifactType -cne $ExpectedArtifactType) { return $false }
    if ($payload.PathBindingToken -isnot [string] -or $payload.PathBindingToken -cne (Get-CddsiPathBindingToken -Path $ExpectedPath)) { return $false }
    if ($payload.ArtifactSha256 -isnot [string] -or $payload.ArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    foreach ($name in @('Valid', 'ChainTrusted', 'PublisherMatch', 'IdentityMatch')) {
        if ($payload.$name -isnot [bool] -or -not $payload.$name) { return $false }
    }
    if ($payload.AuthenticodeStatus -isnot [string] -or $payload.AuthenticodeStatus -cne 'Valid') { return $false }
    $expectedSource = if ($ExpectedArtifactType -eq 'ClaudeDesktopMsix') { 'anthropic_official_only' } else { 'git_for_windows_official_only' }
    return ($payload.SourcePolicy -is [string] -and $payload.SourcePolicy -ceq $expectedSource)
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
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value)) { return $false }
    $parsed = [DateTimeOffset]::MinValue
    return ([DateTimeOffset]::TryParse($Value, [ref]$parsed) -and $parsed.Offset -eq [TimeSpan]::Zero)
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

function Get-CddsiPathBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $canonical = [System.IO.Path]::GetFullPath($Path).TrimEnd('\').ToUpperInvariant()
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
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$ExpectedSha256
    )

    if ($ExpectedSha256 -notmatch '^[a-fA-F0-9]{64}$') { return $false }
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $false }
    $actual = (Get-FileHash -LiteralPath $Path -Algorithm SHA256).Hash
    return [string]::Equals($actual, $ExpectedSha256, [StringComparison]::OrdinalIgnoreCase)
}

function Read-CddsiJsonFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON 文件不存在: $Path"
    }
    $content = [System.IO.File]::ReadAllText($Path, [System.Text.Encoding]::UTF8)
    try {
        return $content | ConvertFrom-Json -ErrorAction Stop
    }
    catch {
        throw "JSON 文件无效: $Path。$($_.Exception.Message)"
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
    if ($properties -contains 'Data' -and $null -ne $Evidence.Data) { return $Evidence.Data }
    return $Evidence
}
