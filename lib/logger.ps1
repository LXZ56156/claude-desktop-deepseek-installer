# logger.ps1 - Console-safe, secret-safe logging primitives.
# Dependency rule: this file has no project-library dependencies.

$script:CddsiLogFilePath = $null
$script:CddsiFileLoggingEnabled = $false
$script:CddsiLogPathTokenValues = $null

function Initialize-CddsiConsoleEncoding {
    [CmdletBinding()]
    param()

    # P1 does not mutate host console or global encoding. Entrypoint-specific
    # encoding policy can be added later through an explicitly reviewed sink.
    return $false
}

function Protect-CddsiLogMessage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Message,

        [AllowNull()]
        [System.Collections.IDictionary]$PathTokenValues
    )

    if ($null -eq $Message) {
        return ''
    }

    $safe = $Message
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9_-])sk-[a-z0-9_-]{20,}(?![a-z0-9_-])', '[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])', 'Bearer [REDACTED]')
    $credentialPattern = '(?i)(?<prefix>"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?)(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}'
    $safe = [regex]::Replace($safe, $credentialPattern, '${prefix}[REDACTED]')
    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $privateKeyPattern = '(?is)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----.*?-----END [^-\r\n]*' + $privateKeyLabel + '-----'
    $safe = [regex]::Replace($safe, $privateKeyPattern, '[REDACTED PRIVATE KEY]')
    if ($null -ne $PathTokenValues) {
        $requiredTokens = @('%LOCALAPPDATA%', '%USERPROFILE%', '%USERNAME%', '%TEMP%')
        $actualTokens = @($PathTokenValues.Keys | ForEach-Object { [string]$_ })
        if (@(Compare-Object -ReferenceObject @($requiredTokens | Sort-Object) -DifferenceObject @($actualTokens | Sort-Object)).Count -gt 0) {
            throw 'PathTokenValues must contain exactly the supported synthetic token keys.'
        }
        foreach ($token in $PathTokenValues.Keys) {
            $value = $PathTokenValues[$token]
            if (-not [string]::IsNullOrWhiteSpace($value)) {
                $escapedValue = $value.Replace('\', '\\')
                $safe = [regex]::Replace($safe, [regex]::Escape($escapedValue), $token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
                $safe = [regex]::Replace($safe, [regex]::Escape($value), $token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
            }
        }
    }
    return $safe
}

function Initialize-CddsiLogger {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [string]$ScriptName = 'cddsi',
        [string]$ArtifactRoot,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$EnableFileLogging,

        [AllowNull()]
        [System.Collections.IDictionary]$PathTokenValues
    )

    if ($null -eq $Context -or $null -eq $Context.PSObject.Properties['Mode']) {
        throw 'ExecutionContext.Mode is mandatory for logger initialization.'
    }
    if ($Context.Mode -cne $Mode) {
        throw 'Logger Mode must match ExecutionContext.Mode.'
    }

    $script:CddsiFileLoggingEnabled = $false
    $script:CddsiLogFilePath = $null
    $script:CddsiLogPathTokenValues = $PathTokenValues

    if ($EnableFileLogging) {
        throw 'P1 不提供文件日志 sink；后续实现必须通过 ExecutionContext 和 FileSystem provider。'
    }

    return $null
}

function Write-CddsiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message,

        [AllowNull()]
        [string]$TimestampUtc,

        [AllowNull()]
        [System.Collections.IDictionary]$PathTokenValues
    )

    if ($null -eq $Context -or $null -eq $Context.PSObject.Properties['Mode']) {
        throw 'ExecutionContext is mandatory for every log sink call.'
    }
    $effectivePathTokens = if ($null -ne $PathTokenValues) { $PathTokenValues } else { $script:CddsiLogPathTokenValues }
    if ($null -eq $effectivePathTokens) {
        throw 'PathTokenValues must be initialized before writing to any log sink.'
    }
    $rawLine = if ([string]::IsNullOrWhiteSpace($TimestampUtc)) {
        '[{0}] {1}' -f $Level, $Message
    }
    else {
        '[{0}] [{1}] {2}' -f $TimestampUtc, $Level, $Message
    }
    $safeLine = Protect-CddsiLogMessage -Message $rawLine -PathTokenValues $effectivePathTokens

    # Console is the only P1 sink. Redaction is complete before the sink call.
    Write-Host $safeLine
}

function Get-CddsiLogPath {
    [CmdletBinding()]
    param()

    return $script:CddsiLogFilePath
}
