[CmdletBinding()]
param(
    [switch]$SkipPester
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$script:Root = Split-Path -Parent $PSScriptRoot
$script:Failures = New-Object System.Collections.Generic.List[string]

function Get-RepositoryFiles {
    $paths = @(& git -c core.quotepath=false -C $script:Root ls-files --cached --others --exclude-standard)
    if ($LASTEXITCODE -ne 0) { throw 'git ls-files failed.' }
    $files = @($paths | Where-Object { -not [string]::IsNullOrWhiteSpace($_) } | ForEach-Object {
        $relative = ([string]$_).Replace('\', '/')
        $fullPath = Join-Path $script:Root $relative
        if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) { throw "Repository file is missing: $relative" }
        [pscustomobject]@{ File = Get-Item -LiteralPath $fullPath -Force; RelativePath = $relative }
    })
    return @($files | Sort-Object RelativePath)
}

function Get-RepositoryContentManifest {
    return @((Get-RepositoryFiles) | ForEach-Object {
        '{0}|{1}' -f $_.RelativePath, (Get-FileHash -LiteralPath $_.File.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    })
}

function Invoke-CheckStep {
    param(
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][scriptblock]$Action
    )

    try {
        & $Action
        Write-Host "[PASS] $Name" -ForegroundColor Green
    }
    catch {
        $message = Protect-CheckMessage -Message $_.Exception.Message
        $script:Failures.Add("${Name}: $message")
        Write-Host "[FAIL] $Name - $message" -ForegroundColor Red
    }
}

function Protect-CheckMessage {
    param([AllowNull()][string]$Message)
    if ($null -eq $Message) { return '' }
    $safe = [regex]::Replace($Message, '(?i)(?<![a-z0-9_-])sk-[a-z0-9_-]{20,}(?![a-z0-9_-])', '[REDACTED]')
    $safe = [regex]::Replace($safe, '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])', 'Bearer [REDACTED]')
    $credentialPattern = '(?i)(?<prefix>"?(?:api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?)(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}'
    $safe = [regex]::Replace($safe, $credentialPattern, '${prefix}[REDACTED]')
    $privateKeyLabel = 'PRIVATE' + ' KEY'
    $privateKeyPattern = '(?is)-----BEGIN [^-\r\n]*' + $privateKeyLabel + '-----.*?-----END [^-\r\n]*' + $privateKeyLabel + '-----'
    return [regex]::Replace($safe, $privateKeyPattern, '[REDACTED PRIVATE KEY]')
}

function Test-CddsiJsonIntegerOne {
    param([AllowNull()]$Value)
    return (($Value -is [int] -or $Value -is [long]) -and [long]$Value -eq 1)
}

function Read-CddsiStrictUtf8Text {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$DisplayPath
    )
    $bytes = [System.IO.File]::ReadAllBytes($Path)
    if ($bytes.Count -ge 2 -and (($bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) -or ($bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF))) { throw "UTF-16 text is forbidden: $DisplayPath" }
    if (@($bytes | Where-Object { $_ -eq 0 }).Count -gt 0) { throw "NUL byte in text file: $DisplayPath" }
    $strictUtf8 = New-Object System.Text.UTF8Encoding($false, $true)
    try { return $strictUtf8.GetString($bytes) } catch { throw "Invalid UTF-8 text: $DisplayPath" }
}

$initialInventory = @((Get-RepositoryFiles).RelativePath)
$initialContentManifest = @(Get-RepositoryContentManifest)

Invoke-CheckStep -Name 'Forbidden runtime artifact directories are absent' -Action {
    foreach ($name in @('release', 'artifacts', 'logs', 'backup', 'reports', 'TestResults')) {
        if (Test-Path -LiteralPath (Join-Path $script:Root $name)) { throw "Runtime artifact directory must not exist in the source tree: $name" }
    }
}

Invoke-CheckStep -Name 'Release manifest classifies every repository file exactly once' -Action {
    $manifestPath = Join-Path $PSScriptRoot 'release-manifest.psd1'
    $manifest = Import-PowerShellDataFile -LiteralPath $manifestPath
    if ($manifest.SchemaVersion -ne 1) { throw 'Unsupported release manifest schema.' }
    $package = @($manifest.PackageFiles)
    $development = @($manifest.DevelopmentOnlyFiles)
    $classified = @($package + $development)
    $duplicates = @($classified | Group-Object | Where-Object Count -gt 1)
    if ($duplicates.Count -gt 0) { throw "Manifest has duplicate entries: $($duplicates.Name -join ', ')" }
    $diff = @(Compare-Object -ReferenceObject $initialInventory -DifferenceObject @($classified | Sort-Object))
    if ($diff.Count -gt 0) {
        $details = @($diff | ForEach-Object { '{0}:{1}' -f $_.SideIndicator, $_.InputObject }) -join ', '
        throw "Manifest inventory mismatch: $details"
    }
    foreach ($entry in $package) {
        if (-not (Test-Path -LiteralPath (Join-Path $script:Root $entry) -PathType Leaf)) { throw "Missing package file: $entry" }
    }
}

Invoke-CheckStep -Name 'PowerShell AST syntax' -Action {
    $powerShellFiles = @(Get-RepositoryFiles | Where-Object { $_.RelativePath -match '\.(ps1|psd1)$' })
    $allErrors = New-Object System.Collections.Generic.List[string]
    foreach ($item in $powerShellFiles) {
        $tokens = $null
        $errors = $null
        [void][System.Management.Automation.Language.Parser]::ParseFile($item.File.FullName, [ref]$tokens, [ref]$errors)
        foreach ($parseError in @($errors)) {
            $allErrors.Add("$($item.RelativePath):$($parseError.Extent.StartLineNumber): $($parseError.Message)")
        }
    }
    if ($allErrors.Count -gt 0) { throw ($allErrors -join ' | ') }
}

Invoke-CheckStep -Name 'JSON parsing and defaults contract' -Action {
    $jsonFiles = @(Get-RepositoryFiles | Where-Object { $_.RelativePath -like '*.json' })
    foreach ($item in $jsonFiles) {
        $text = [System.IO.File]::ReadAllText($item.File.FullName, [System.Text.Encoding]::UTF8)
        try { $null = $text | ConvertFrom-Json -ErrorAction Stop } catch { throw "Invalid JSON: $($item.RelativePath)" }
    }
    $configPath = Join-Path $script:Root 'config\deepseek-desktop.defaults.json'
    $config = ([System.IO.File]::ReadAllText($configPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json)
    if (-not (Test-CddsiJsonIntegerOne -Value $config.schemaVersion)) { throw 'Defaults schemaVersion must be integer 1.' }
    if ($config.projectStage -cne 'scaffold' -or $config.execution.defaultMode -cne 'TestSafe') { throw 'Defaults must stay scaffold/TestSafe.' }
    foreach ($entry in @(
        @($config.execution.liveEnabled, $false, 'execution.liveEnabled'),
        @($config.execution.requireExplicitLiveAcknowledgement, $true, 'execution.requireExplicitLiveAcknowledgement'),
        @($config.execution.automaticRestartAllowed, $false, 'execution.automaticRestartAllowed'),
        @($config.desktop.modelDiscovery, $false, 'desktop.modelDiscovery'),
        @($config.desktop.capabilities.chat, $true, 'desktop.capabilities.chat'),
        @($config.desktop.capabilities.code, $true, 'desktop.capabilities.code'),
        @($config.desktop.capabilities.cowork, $true, 'desktop.capabilities.cowork'),
        @($config.deepseek.persistCredentialInState, $false, 'deepseek.persistCredentialInState'),
        @($config.deepseek.validationRequestEnabled, $false, 'deepseek.validationRequestEnabled'),
        @($config.claudeDesktopMsix.requireAuthenticodeSignature, $true, 'claudeDesktopMsix.requireAuthenticodeSignature'),
        @($config.claudeDesktopMsix.requireTrustedChain, $true, 'claudeDesktopMsix.requireTrustedChain'),
        @($config.gitForWindows.silentInstallEnabled, $false, 'gitForWindows.silentInstallEnabled'),
        @($config.gitForWindows.modifyGlobalGitConfig, $false, 'gitForWindows.modifyGlobalGitConfig'),
        @($config.cowork.checkVirtualMachinePlatform, $true, 'cowork.checkVirtualMachinePlatform'),
        @($config.cowork.checkHardwareVirtualization, $true, 'cowork.checkHardwareVirtualization'),
        @($config.cowork.checkService, $true, 'cowork.checkService'),
        @($config.cowork.enableWindowsFeature, $false, 'cowork.enableWindowsFeature'),
        @($config.cowork.restartEnabled, $false, 'cowork.restartEnabled')
    )) {
        if ($entry[0] -isnot [bool] -or $entry[0] -ne $entry[1]) { throw "Unsafe or mistyped default: $($entry[2])" }
    }
    if ($config.desktop.configLibraryPath -cne '%LOCALAPPDATA%\Claude-3p\configLibrary') { throw 'Unexpected configLibrary path.' }
    if ($config.desktop.claudeCodeSettingsPolicy -cne 'do_not_read_or_modify') { throw 'Claude Code settings policy drift.' }
    $defaultModels = @($config.desktop.models)
    if ($defaultModels.Count -ne 2 -or $defaultModels[0] -isnot [string] -or $defaultModels[1] -isnot [string] -or $defaultModels[0] -cne 'deepseek-chat' -or $defaultModels[1] -cne 'deepseek-reasoner') { throw 'Fixed model list drift.' }
    if ($config.deepseek.baseUrl -cne 'https://api.deepseek.com' -or $config.deepseek.credentialInput -cne 'secure_runtime_handle') { throw 'DeepSeek provider defaults drift.' }
    if ($config.claudeDesktopMsix.sourcePolicy -cne 'anthropic_official_only' -or $null -ne $config.claudeDesktopMsix.downloadUri -or $null -ne $config.claudeDesktopMsix.expectedPublisher -or $null -ne $config.claudeDesktopMsix.packageIdentity) { throw 'MSIX official-source scaffold defaults drift.' }
    if ($config.gitForWindows.sourcePolicy -cne 'git_for_windows_official_only' -or $null -ne $config.gitForWindows.downloadUri -or $null -ne $config.gitForWindows.expectedPublisher) { throw 'Git official-source scaffold defaults drift.' }
}

Invoke-CheckStep -Name 'Encoding and line-ending baseline' -Action {
    foreach ($item in @(Get-RepositoryFiles | Where-Object { $_.RelativePath -like '*.cmd' })) {
        $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
        if (@($bytes | Where-Object { $_ -gt 127 }).Count -gt 0) { throw "CMD is not ASCII: $($item.RelativePath)" }
        if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "CMD has UTF-8 BOM: $($item.RelativePath)" }
        $text = [System.Text.Encoding]::ASCII.GetString($bytes)
        if ($text -match '(?i)\bchcp\b') { throw "CMD must not change code page: $($item.RelativePath)" }
        if ($text -match '(?<!\r)\n') { throw "CMD must use CRLF: $($item.RelativePath)" }
        if (-not $text.EndsWith("`r`n") -or $text.Substring(0, $text.Length - 2).EndsWith("`r`n")) { throw "CMD must have exactly one final newline: $($item.RelativePath)" }
        if ([regex]::IsMatch($text, '(?m)[ \t]+(?=\r?$)')) { throw "CMD has trailing whitespace: $($item.RelativePath)" }
    }
    foreach ($item in @(Get-RepositoryFiles | Where-Object { $_.RelativePath -match '\.(ps1|psd1)$' })) {
        $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
        if ($bytes.Count -lt 3 -or $bytes[0] -ne 0xEF -or $bytes[1] -ne 0xBB -or $bytes[2] -ne 0xBF) { throw "PowerShell file must be UTF-8 BOM for Windows PowerShell 5.1: $($item.RelativePath)" }
        $text = [System.Text.Encoding]::UTF8.GetString($bytes, 3, $bytes.Count - 3)
        if ($text -match '(?<!\r)\n') { throw "PowerShell file must use CRLF: $($item.RelativePath)" }
        if (-not $text.EndsWith("`r`n") -or $text.Substring(0, $text.Length - 2).EndsWith("`r`n")) { throw "PowerShell file must have exactly one final newline: $($item.RelativePath)" }
        if ([regex]::IsMatch($text, '(?m)[ \t]+(?=\r?$)')) { throw "PowerShell file has trailing whitespace: $($item.RelativePath)" }
    }
    $binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.msix', '.exe', '.dll', '.pdb', '.pdf')
    foreach ($item in @(Get-RepositoryFiles | Where-Object { $_.RelativePath -notmatch '\.(ps1|psd1|cmd)$' -and $binaryExtensions -notcontains $_.File.Extension.ToLowerInvariant() })) {
        $bytes = [System.IO.File]::ReadAllBytes($item.File.FullName)
        if ($bytes.Count -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) { throw "Non-PowerShell text must not have UTF-8 BOM: $($item.RelativePath)" }
        $text = Read-CddsiStrictUtf8Text -Path $item.File.FullName -DisplayPath $item.RelativePath
        if ($text.Contains("`r")) { throw "Text file must use LF: $($item.RelativePath)" }
        if (-not $text.EndsWith("`n") -or $text.Substring(0, $text.Length - 1).EndsWith("`n")) { throw "Text file must have exactly one final newline: $($item.RelativePath)" }
        if ([regex]::IsMatch($text, '(?m)[ \t]+$')) { throw "Text file has trailing whitespace: $($item.RelativePath)" }
    }
}

Invoke-CheckStep -Name 'Public function contracts and side-effect-free module load' -Action {
    $bootstrap = Join-Path $script:Root 'lib\bootstrap.ps1'
    . $bootstrap
    Import-CddsiLibraries
    $publicContract = Import-PowerShellDataFile -LiteralPath (Join-Path $script:Root 'config\public-functions.psd1')
    if ($publicContract.SchemaVersion -ne 1) { throw 'Unsupported public function contract schema.' }
    $requiredFunctions = @($publicContract.Files.GetEnumerator() | ForEach-Object { @($_.Value) })
    foreach ($name in $requiredFunctions) {
        if ($null -eq (Get-Command -Name $name -CommandType Function -ErrorAction SilentlyContinue)) { throw "Missing public function: $name" }
    }
    $functionAstByName = @{}
    foreach ($entry in $publicContract.Files.GetEnumerator()) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $entry.Key), [ref]$tokens, [ref]$errors)
        $functionNodes = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        foreach ($functionNode in $functionNodes) { $functionAstByName[$functionNode.Name] = $functionNode }
        $actualFunctions = @($functionNodes | ForEach-Object Name | Sort-Object)
        $functionDiff = @(Compare-Object -ReferenceObject @($entry.Value | Sort-Object) -DifferenceObject $actualFunctions)
        if ($functionDiff.Count -gt 0) { throw "Public function file contract drift: $($entry.Key)" }
    }
    foreach ($entry in $publicContract.ParameterContracts.GetEnumerator()) {
        $command = Get-Command -Name $entry.Key -CommandType Function -ErrorAction Stop
        foreach ($parameterName in @($entry.Value.Mandatory)) {
            if (-not $command.Parameters.ContainsKey($parameterName)) { throw "$($entry.Key) is missing parameter $parameterName" }
            $mandatory = @($command.Parameters[$parameterName].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count -gt 0
            if (-not $mandatory) { throw "$($entry.Key).$parameterName must be mandatory." }
        }
        if ($entry.Value.ContainsKey('Mode') -and $entry.Value.Mode) {
            if (-not $command.Parameters.ContainsKey('Mode')) { throw "$($entry.Key) is missing Mode." }
            $validateSet = @($command.Parameters.Mode.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object ValidValues)
            if ((@($validateSet | Sort-Object) -join ',') -ne 'DryRun,Live,TestSafe') { throw "$($entry.Key).Mode ValidateSet drift." }
            $modeAst = @($functionAstByName[$entry.Key].Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Mode' })[0]
            if ($null -eq $modeAst.DefaultValue -or $modeAst.DefaultValue.Extent.Text.Trim("'`"") -cne 'TestSafe') { throw "$($entry.Key).Mode must default to TestSafe." }
        }
        foreach ($switchName in @('AcknowledgeRealChanges', 'AcknowledgeRestart')) {
            if ($entry.Value.ContainsKey($switchName) -and $entry.Value[$switchName] -and -not $command.Parameters.ContainsKey($switchName)) {
                throw "$($entry.Key) is missing $switchName."
            }
        }
    }

    $windowsPowerShell = Get-Command powershell.exe -ErrorAction SilentlyContinue
    if ($null -eq $windowsPowerShell) { throw 'Windows PowerShell 5.1 executable not found.' }
    $quotedBootstrap = $bootstrap.Replace("'", "''")
    $childCommand = "`$ErrorActionPreference='Stop'; . '$quotedBootstrap'; Import-CddsiLibraries; if ((Get-CddsiProjectStage) -ne 'Scaffold') { throw 'stage' }; Write-Output 'MODULE_LOAD_OK'"
    $encoded = [Convert]::ToBase64String([System.Text.Encoding]::Unicode.GetBytes($childCommand))
    $childOutput = @(& $windowsPowerShell.Source -NoProfile -NonInteractive -ExecutionPolicy Bypass -EncodedCommand $encoded 2>&1)
    if ($LASTEXITCODE -ne 0 -or ($childOutput -join "`n") -notmatch 'MODULE_LOAD_OK') {
        throw "Windows PowerShell module load failed: $($childOutput -join ' ')"
    }
}

Invoke-CheckStep -Name 'Scaffold modules contain no real system-operation commands' -Action {
    $scaffoldFiles = @(
        'lib/desktop-env-check.ps1', 'lib/desktop-msix.ps1', 'lib/git-for-windows.ps1',
        'lib/cowork-readiness.ps1', 'lib/deepseek-api.ps1', 'lib/desktop-config.ps1',
        'lib/desktop-lifecycle.ps1', 'lib/desktop-acceptance.ps1', 'scripts/elevated-install.ps1'
    )
    $forbiddenCommands = @(
        'Invoke-WebRequest', 'Invoke-RestMethod', 'Add-AppxPackage', 'Remove-AppxPackage',
        'Enable-WindowsOptionalFeature', 'Disable-WindowsOptionalFeature', 'Restart-Computer',
        'Start-Process', 'Stop-Process', 'Register-ScheduledTask', 'Unregister-ScheduledTask',
        'Set-ItemProperty', 'Set-Content', 'Add-Content', 'Out-File', 'Copy-Item', 'Move-Item', 'Remove-Item',
        'Start-BitsTransfer', 'bitsadmin', 'bitsadmin.exe', 'Invoke-Expression', 'iex', 'iwr', 'irm', 'saps', 'New-Object', 'curl', 'curl.exe',
        'wget', 'winget', 'winget.exe', 'dism', 'dism.exe', 'msiexec', 'msiexec.exe', 'wusa', 'wusa.exe',
        'schtasks', 'schtasks.exe', 'shutdown', 'shutdown.exe', 'taskkill', 'taskkill.exe',
        'cmd', 'cmd.exe', 'powershell', 'powershell.exe', 'pwsh', 'pwsh.exe', 'reg', 'reg.exe',
        'rundll32', 'rundll32.exe', 'sc.exe', 'net.exe', 'Start-Service', 'Stop-Service', 'Set-Service'
    )
    $forbiddenTypes = @('System.Diagnostics.Process', 'System.Net.WebClient', 'System.Net.WebRequest', 'System.Net.Http.HttpClient', 'Microsoft.Win32.Registry', 'System.IO.File', 'System.IO.Directory')
    foreach ($relative in $scaffoldFiles) {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:Root $relative), [ref]$tokens, [ref]$errors)
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ })
        $hits = @($commands | Where-Object { $forbiddenCommands -contains $_ } | Sort-Object -Unique)
        if ($hits.Count -gt 0) { throw "$relative contains forbidden scaffold commands: $($hits -join ', ')" }
        $dynamicInvocations = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] -and $node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and [string]::IsNullOrWhiteSpace($node.GetCommandName()) }, $true))
        if ($dynamicInvocations.Count -gt 0) { throw "$relative contains a dynamic command invocation." }
        $typeHits = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName } | Where-Object { $forbiddenTypes -contains $_ } | Sort-Object -Unique)
        if ($typeHits.Count -gt 0) { throw "$relative contains forbidden scaffold .NET types: $($typeHits -join ', ')" }
    }
}

Invoke-CheckStep -Name 'Repository API Key leak scan' -Action {
    if ($null -eq (Get-Command Find-CddsiPotentialSecrets -ErrorAction SilentlyContinue)) {
        . (Join-Path $script:Root 'lib\logger.ps1')
        . (Join-Path $script:Root 'lib\common.ps1')
    }
    $findings = New-Object System.Collections.Generic.List[object]
    $binaryExtensions = @('.png', '.jpg', '.jpeg', '.gif', '.ico', '.zip', '.msix', '.exe', '.dll', '.pdb', '.pdf')
    foreach ($item in @(Get-RepositoryFiles)) {
        if ($binaryExtensions -notcontains $item.File.Extension.ToLowerInvariant()) {
            $content = Read-CddsiStrictUtf8Text -Path $item.File.FullName -DisplayPath $item.RelativePath
            foreach ($finding in @(Find-CddsiPotentialSecrets -Content $content -Source $item.RelativePath)) { $findings.Add($finding) }
        }
    }
    if ($findings.Count -gt 0) {
        $safeDetails = @($findings | ForEach-Object { '{0}:{1}:{2}' -f $_.Source, $_.Line, $_.Type }) -join ', '
        throw "Potential secrets found: $safeDetails"
    }
}

if (-not $SkipPester) {
    Invoke-CheckStep -Name 'Pester Unit and Contract suites' -Action {
        $pesterManifest = Join-Path $script:Root '.dev\modules\Pester\5.6.1\Pester.psd1'
        if (-not (Test-Path -LiteralPath $pesterManifest -PathType Leaf)) {
            throw 'Repository-local Pester 5.6.1 is missing. Run scripts/bootstrap-dev.ps1 first.'
        }
        Remove-Module Pester -Force -ErrorAction SilentlyContinue
        Import-Module $pesterManifest -Force -ErrorAction Stop
        $result = Invoke-Pester -Path (Join-Path $script:Root 'tests') -Output Detailed -PassThru
        if ([string]$result.Result -ne 'Passed' -or $result.FailedCount -gt 0 -or $result.SkippedCount -gt 0 -or $result.NotRunCount -gt 0 -or $result.InconclusiveCount -gt 0) {
            throw ("Pester result is not clean: Result={0}, Failed={1}, Skipped={2}, NotRun={3}, Inconclusive={4}." -f $result.Result, $result.FailedCount, $result.SkippedCount, $result.NotRunCount, $result.InconclusiveCount)
        }
    }
}

Invoke-CheckStep -Name 'git diff whitespace check' -Action {
    & git -C $script:Root diff --check
    if ($LASTEXITCODE -ne 0) { throw 'git diff --check failed.' }
    & git -C $script:Root diff --cached --check
    if ($LASTEXITCODE -ne 0) { throw 'git diff --cached --check failed.' }
}

Invoke-CheckStep -Name 'Checks did not create repository artifacts' -Action {
    $finalInventory = @((Get-RepositoryFiles).RelativePath)
    $diff = @(Compare-Object -ReferenceObject $initialInventory -DifferenceObject $finalInventory)
    if ($diff.Count -gt 0) { throw "Repository inventory changed during checks: $($diff.InputObject -join ', ')" }
    $finalContentManifest = @(Get-RepositoryContentManifest)
    $contentDiff = @(Compare-Object -ReferenceObject $initialContentManifest -DifferenceObject $finalContentManifest)
    if ($contentDiff.Count -gt 0) { throw 'Repository file content changed during checks.' }
}

if ($script:Failures.Count -gt 0) {
    Write-Host "`nQuality checks failed:" -ForegroundColor Red
    foreach ($failure in $script:Failures) { Write-Host "  - $failure" -ForegroundColor Red }
    throw "$($script:Failures.Count) quality check(s) failed."
}

Write-Host "`nAll quality checks passed." -ForegroundColor Green
