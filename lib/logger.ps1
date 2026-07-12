# logger.ps1 - Console-safe, secret-safe logging primitives.
# Dependency rule: this file has no project-library dependencies.

$script:CddsiLogFilePath = $null
$script:CddsiFileLoggingEnabled = $false

function Initialize-CddsiConsoleEncoding {
    [CmdletBinding()]
    param()

    # Windows PowerShell 5.1 with the legacy console handles Chinese more
    # reliably when the host keeps its native code page. PowerShell 7 can use
    # UTF-8 without changing machine or user settings.
    if ($PSVersionTable.PSEdition -eq 'Core') {
        try {
            $utf8 = New-Object System.Text.UTF8Encoding($false)
            [Console]::OutputEncoding = $utf8
            $global:OutputEncoding = $utf8
        }
        catch {
            # Some redirected hosts do not expose a writable console encoding.
        }
    }
}

function Protect-CddsiLogMessage {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$Message
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
    $pathTokens = [ordered]@{
        '%LOCALAPPDATA%' = [Environment]::GetFolderPath('LocalApplicationData')
        '%USERPROFILE%'  = [Environment]::GetFolderPath('UserProfile')
        '%USERNAME%'     = [Environment]::UserName
        '%TEMP%'         = [System.IO.Path]::GetTempPath().TrimEnd('\')
    }
    foreach ($token in $pathTokens.Keys) {
        $value = $pathTokens[$token]
        if (-not [string]::IsNullOrWhiteSpace($value)) {
            $safe = [regex]::Replace($safe, [regex]::Escape($value), $token, [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
        }
    }
    return $safe
}

function Initialize-CddsiLogger {
    [CmdletBinding()]
    param(
        [string]$ScriptName = 'cddsi',
        [string]$ArtifactRoot,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$EnableFileLogging
    )

    Initialize-CddsiConsoleEncoding
    $script:CddsiFileLoggingEnabled = $false
    $script:CddsiLogFilePath = $null

    if (-not $EnableFileLogging) {
        return $null
    }

    if ($Mode -eq 'Live') {
        throw '脚手架阶段禁止 Live 文件日志。'
    }

    if ([string]::IsNullOrWhiteSpace($ArtifactRoot)) {
        throw '启用文件日志时必须显式提供唯一 ArtifactRoot。'
    }
    $tempRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath()).TrimEnd('\')
    $artifactFullPath = [System.IO.Path]::GetFullPath($ArtifactRoot).TrimEnd('\')
    if ([string]::Equals($artifactFullPath, $tempRoot, [StringComparison]::OrdinalIgnoreCase) -or -not $artifactFullPath.StartsWith($tempRoot + '\', [StringComparison]::OrdinalIgnoreCase)) {
        throw 'TestSafe/DryRun 文件日志只能写入显式的 OS 临时目录。'
    }
    if ((Split-Path -Leaf $artifactFullPath) -notmatch '^cddsi-[a-fA-F0-9]{32}$') {
        throw 'ArtifactRoot 必须使用 cddsi-<32位GUID> 唯一目录名。'
    }
    if (Test-Path -LiteralPath $artifactFullPath) {
        throw 'ArtifactRoot 必须是本次运行尚不存在的唯一目录。'
    }
    $cursor = Split-Path -Parent $artifactFullPath
    while ($cursor.StartsWith($tempRoot, [StringComparison]::OrdinalIgnoreCase)) {
        if (Test-Path -LiteralPath $cursor) {
            $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
            if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'ArtifactRoot 的现有祖先包含重解析点。'
            }
        }
        if ([string]::Equals($cursor, $tempRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
        $parent = Split-Path -Parent $cursor
        if ($parent -eq $cursor) { break }
        $cursor = $parent
    }

    $logDirectory = Join-Path $artifactFullPath 'logs'
    if (-not (Test-Path -LiteralPath $logDirectory -PathType Container)) {
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
    }

    $safeName = [regex]::Replace($ScriptName, '[^A-Za-z0-9._-]', '_')
    $stamp = Get-Date -Format 'yyyyMMdd-HHmmss-fff'
    $script:CddsiLogFilePath = Join-Path $logDirectory ("{0}-{1}.log" -f $safeName, $stamp)
    $script:CddsiFileLoggingEnabled = $true
    return $script:CddsiLogFilePath
}

function Write-CddsiLog {
    [CmdletBinding()]
    param(
        [ValidateSet('DEBUG', 'INFO', 'WARN', 'ERROR', 'SUCCESS')]
        [string]$Level = 'INFO',

        [Parameter(Mandatory = $true)]
        [AllowEmptyString()]
        [string]$Message
    )

    $safeMessage = Protect-CddsiLogMessage -Message $Message
    $line = '[{0}] [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $safeMessage
    Write-Host $line

    if ($script:CddsiFileLoggingEnabled -and -not [string]::IsNullOrWhiteSpace($script:CddsiLogFilePath)) {
        $utf8NoBom = New-Object System.Text.UTF8Encoding($false)
        [System.IO.File]::AppendAllText($script:CddsiLogFilePath, $line + [Environment]::NewLine, $utf8NoBom)
    }
}

function Get-CddsiLogPath {
    [CmdletBinding()]
    param()

    return $script:CddsiLogFilePath
}
