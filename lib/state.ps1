# state.ps1 - Resume-state schema and write contracts.
# Dependencies: common.ps1. No state file is read or written at scaffold stage.

function Get-CddsiStatePath {
    [CmdletBinding()]
    param(
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData')
    )

    if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) {
        throw '无法解析 LOCALAPPDATA。'
    }
    return Join-Path $LocalAppDataPath 'ClaudeDesktopDeepSeekInstaller\state.json'
}

function New-CddsiState {
    [CmdletBinding()]
    param(
        [string]$InstallerVersion = '0.1.0-dev',
        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$ExecutionMode = 'TestSafe',
        [string]$RunId = ([guid]::NewGuid().ToString('D'))
    )

    $now = [DateTime]::UtcNow.ToString('o')
    return [pscustomobject][ordered]@{
        schemaVersion   = 1
        installerVersion = $InstallerVersion
        runId           = $RunId
        executionMode   = $ExecutionMode
        phase           = 'bootstrap'
        status          = 'initialized'
        completedSteps  = @()
        pendingAction   = $null
        restart         = [pscustomobject][ordered]@{
            required    = $false
            reasonCode  = $null
            resumePhase = $null
        }
        desktop         = [pscustomobject][ordered]@{
            installed       = $false
            packageVersion  = $null
            packageIdentity = $null
            signatureStatus = 'not_checked'
        }
        git             = [pscustomobject][ordered]@{
            installed = $false
            version   = $null
            source    = $null
        }
        cowork          = [pscustomobject][ordered]@{
            virtualMachinePlatform = 'not_checked'
            hardwareVirtualization = 'not_checked'
            serviceStatus          = 'not_checked'
            ready                  = $false
        }
        config          = [pscustomobject][ordered]@{
            targetPathToken = '%LOCALAPPDATA%\Claude-3p\configLibrary'
            backupId       = $null
            beforeSha256   = $null
            afterSha256    = $null
        }
        claudeCodeSettings = [pscustomobject][ordered]@{
            policy        = 'do_not_read_or_modify'
            baselineToken = $null
            finalToken    = $null
            unchanged     = $null
        }
        deepseek        = [pscustomobject][ordered]@{
            keyFormatValidated    = $false
            remoteValidationStatus = 'not_run'
            lastErrorClass        = $null
        }
        lastError       = $null
        createdAtUtc    = $now
        updatedAtUtc    = $now
    }
}

function Test-CddsiStateSchema {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $State
    )

    $topLevel = @('schemaVersion', 'installerVersion', 'runId', 'executionMode', 'phase', 'status', 'completedSteps', 'pendingAction', 'restart', 'desktop', 'git', 'cowork', 'config', 'claudeCodeSettings', 'deepseek', 'lastError', 'createdAtUtc', 'updatedAtUtc')
    if (-not (Test-CddsiExactPropertySet -InputObject $State -Expected $topLevel)) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.restart -Expected @('required', 'reasonCode', 'resumePhase'))) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.desktop -Expected @('installed', 'packageVersion', 'packageIdentity', 'signatureStatus'))) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.git -Expected @('installed', 'version', 'source'))) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.cowork -Expected @('virtualMachinePlatform', 'hardwareVirtualization', 'serviceStatus', 'ready'))) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.config -Expected @('targetPathToken', 'backupId', 'beforeSha256', 'afterSha256'))) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.claudeCodeSettings -Expected @('policy', 'baselineToken', 'finalToken', 'unchanged'))) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.deepseek -Expected @('keyFormatValidated', 'remoteValidationStatus', 'lastErrorClass'))) { return $false }
    if ($null -ne $State.lastError -and -not (Test-CddsiExactPropertySet -InputObject $State.lastError -Expected @('code', 'messageSafe'))) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $State.schemaVersion)) { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $State.installerVersion -MaxLength 64)) { return $false }
    if ($State.runId -isnot [string]) { return $false }
    $parsedGuid = [guid]::Empty
    if (-not [guid]::TryParse($State.runId, [ref]$parsedGuid)) { return $false }
    if ($State.executionMode -isnot [string] -or $State.executionMode -notin @('TestSafe', 'DryRun', 'Live')) { return $false }
    if ($State.phase -isnot [string] -or $State.phase -notmatch '^[a-z][a-z0-9_]*$') { return $false }
    if ($State.status -isnot [string] -or $State.status -notmatch '^[a-z][a-z0-9_]*$') { return $false }
    if ($State.completedSteps -isnot [System.Array]) { return $false }
    $seenSteps = @{}
    foreach ($step in @($State.completedSteps)) {
        if (-not (Test-CddsiSafeIdentifierValue -Value $step -MaxLength 64) -or $seenSteps.ContainsKey($step)) { return $false }
        $seenSteps[$step] = $true
    }
    if ($State.restart.required -isnot [bool] -or $State.desktop.installed -isnot [bool] -or $State.git.installed -isnot [bool] -or $State.cowork.ready -isnot [bool] -or $State.deepseek.keyFormatValidated -isnot [bool]) { return $false }
    if ($State.restart.required) {
        if (-not (Test-CddsiSafeIdentifierValue -Value $State.restart.reasonCode -MaxLength 64)) { return $false }
        if (-not (Test-CddsiSafeIdentifierValue -Value $State.restart.resumePhase -MaxLength 64)) { return $false }
        if ($State.pendingAction -cne 'restart') { return $false }
    }
    elseif ($null -ne $State.restart.reasonCode -or $null -ne $State.restart.resumePhase -or $null -ne $State.pendingAction) { return $false }
    if ($State.config.targetPathToken -cne '%LOCALAPPDATA%\Claude-3p\configLibrary') { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $State.config.backupId -AllowNull -MaxLength 128)) { return $false }
    foreach ($hashName in @('beforeSha256', 'afterSha256')) {
        $hashValue = $State.config.$hashName
        if ($null -ne $hashValue -and ($hashValue -isnot [string] -or $hashValue -notmatch '^[a-fA-F0-9]{64}$')) { return $false }
    }
    if ($State.claudeCodeSettings.policy -cne 'do_not_read_or_modify') { return $false }
    foreach ($tokenName in @('baselineToken', 'finalToken')) {
        $tokenValue = $State.claudeCodeSettings.$tokenName
        if ($null -ne $tokenValue -and ($tokenValue -isnot [string] -or $tokenValue -notmatch '^[a-fA-F0-9]{64}$')) { return $false }
    }
    if ($null -ne $State.claudeCodeSettings.unchanged -and $State.claudeCodeSettings.unchanged -isnot [bool]) { return $false }
    foreach ($value in @($State.desktop.packageVersion, $State.desktop.packageIdentity, $State.desktop.signatureStatus, $State.git.version, $State.git.source, $State.cowork.virtualMachinePlatform, $State.cowork.hardwareVirtualization, $State.cowork.serviceStatus, $State.deepseek.remoteValidationStatus, $State.deepseek.lastErrorClass)) {
        if (-not (Test-CddsiSafeIdentifierValue -Value $value -AllowNull -MaxLength 128)) { return $false }
    }
    if ($null -ne $State.lastError) {
        if (-not (Test-CddsiSafeIdentifierValue -Value $State.lastError.code -MaxLength 64)) { return $false }
        if ($State.lastError.messageSafe -isnot [string] -or $State.lastError.messageSafe.Length -gt 512 -or $State.lastError.messageSafe -match '[\r\n\{\}\[\]]') { return $false }
    }
    if (-not (Test-CddsiUtcTimestampValue -Value $State.createdAtUtc)) { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $State.updatedAtUtc)) { return $false }
    try {
        if ([DateTimeOffset]$State.updatedAtUtc -lt [DateTimeOffset]$State.createdAtUtc) { return $false }
    }
    catch { return $false }
    $serialized = ConvertTo-CddsiJson -InputObject $State
    if (@(Find-CddsiPotentialSecrets -Content $serialized -Source '<state>').Count -gt 0) { return $false }
    if ($serialized -match '(?i)"(apiKey|authorization|authToken)"\s*:') { return $false }
    return $true
}

function Test-CddsiStateTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe'
    )

    try {
        $effectiveLocalAppData = if ($Mode -eq 'Live') { [Environment]::GetFolderPath('LocalApplicationData') } else { $LocalAppDataPath }
        if ([string]::IsNullOrWhiteSpace($effectiveLocalAppData)) { return $false }
        $localRoot = [System.IO.Path]::GetFullPath($effectiveLocalAppData).TrimEnd('\')
        $expected = [System.IO.Path]::GetFullPath((Get-CddsiStatePath -LocalAppDataPath $localRoot)).TrimEnd('\')
        $actual = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        if (-not [string]::Equals($expected, $actual, [StringComparison]::OrdinalIgnoreCase)) { return $false }

        $cursor = $actual
        while (-not [string]::IsNullOrWhiteSpace($cursor) -and $cursor.StartsWith($localRoot, [StringComparison]::OrdinalIgnoreCase)) {
            if (Test-Path -LiteralPath $cursor) {
                $item = Get-Item -LiteralPath $cursor -Force -ErrorAction Stop
                if (($item.Attributes -band [System.IO.FileAttributes]::ReparsePoint) -ne 0) { return $false }
            }
            if ([string]::Equals($cursor, $localRoot, [StringComparison]::OrdinalIgnoreCase)) { break }
            $parent = Split-Path -Parent $cursor
            if ($parent -eq $cursor) { break }
            $cursor = $parent
        }
        return $true
    }
    catch {
        return $false
    }
}

function Read-CddsiState {
    [CmdletBinding()]
    param(
        [string]$Path = (Get-CddsiStatePath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiStateTarget -Path $Path -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) { throw '拒绝读取：目标不是受信任的状态文件路径。' }
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'ReadState' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'ReadState' -Status 'not_implemented' -Mode $Mode -MessageSafe '脚手架阶段不读取状态文件。'
}

function Write-CddsiStateAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [string]$Path = (Get-CddsiStatePath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiStateSchema -State $State)) {
        throw '状态对象不符合 schema 或包含疑似凭据。'
    }
    if (-not (Test-CddsiStateTarget -Path $Path -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) { throw '拒绝写入：目标不是受信任的状态文件路径。' }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'WriteStateAtomic' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'WriteStateAtomic' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '状态原子写入尚未实现。' -PlannedChanges @($Path)
}

function Set-CddsiResumeCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [Parameter(Mandatory = $true)][string]$ResumePhase
    )

    if (-not (Test-CddsiStateSchema -State $State)) { throw '输入状态不符合 schema。' }
    $copy = $State | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.restart.required = $true
    $copy.restart.reasonCode = $ReasonCode
    $copy.restart.resumePhase = $ResumePhase
    $copy.pendingAction = 'restart'
    $copy.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    if (-not (Test-CddsiStateSchema -State $copy)) { throw '续跑状态生成失败。' }
    return $copy
}

function Clear-CddsiResumeCheckpoint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State
    )

    if (-not (Test-CddsiStateSchema -State $State)) { throw '输入状态不符合 schema。' }
    $copy = $State | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    $copy.restart.required = $false
    $copy.restart.reasonCode = $null
    $copy.restart.resumePhase = $null
    $copy.pendingAction = $null
    $copy.updatedAtUtc = [DateTime]::UtcNow.ToString('o')
    if (-not (Test-CddsiStateSchema -State $copy)) { throw '续跑状态清理失败。' }
    return $copy
}
