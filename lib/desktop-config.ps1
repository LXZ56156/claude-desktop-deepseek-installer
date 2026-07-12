# desktop-config.ps1 - configLibrary desired-state, backup and restore contracts.
# The real Claude Desktop configLibrary schema must be verified before Live work.

function Get-CddsiClaudeDesktopConfigLibraryPath {
    [CmdletBinding()]
    param(
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData')
    )

    return Get-CddsiConfigLibraryPath -LocalAppDataPath $LocalAppDataPath
}

function Test-CddsiConfigLibraryTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe'
    )

    try {
        $effectiveLocalAppData = if ($Mode -eq 'Live') { [Environment]::GetFolderPath('LocalApplicationData') } else { $LocalAppDataPath }
        if ([string]::IsNullOrWhiteSpace($effectiveLocalAppData)) { return $false }
        $localRoot = [System.IO.Path]::GetFullPath($effectiveLocalAppData).TrimEnd('\')
        $expected = [System.IO.Path]::GetFullPath((Get-CddsiClaudeDesktopConfigLibraryPath -LocalAppDataPath $localRoot)).TrimEnd('\')
        $actual = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
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

function Read-CddsiClaudeDesktopConfigLibrary {
    [CmdletBinding()]
    param(
        [string]$TargetPath = (Get-CddsiClaudeDesktopConfigLibraryPath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiConfigLibraryTarget -TargetPath $TargetPath -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) { throw '拒绝读取：目标不是受信任的 configLibrary 路径。' }
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'ReadConfigLibrary' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'ReadConfigLibrary' -Status 'not_implemented' -Mode $Mode -MessageSafe '脚手架阶段不读取 configLibrary。'
}

function New-CddsiClaudeDesktopDesiredConfig {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        schemaStatus  = 'draft_requires_desktop_contract_verification'
        provider      = 'DeepSeek'
        modelDiscovery = [pscustomobject]@{ enabled = $false }
        models        = @('deepseek-chat', 'deepseek-reasoner')
        capabilities  = [pscustomobject][ordered]@{
            chat   = $true
            code   = $true
            cowork = $true
        }
        credential = [pscustomobject][ordered]@{
            source = 'runtime_secure_handle'
            value  = $null
            persistInState = $false
        }
    }
}

function Test-CddsiClaudeDesktopConfigContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Config -Expected @('schemaVersion', 'schemaStatus', 'provider', 'modelDiscovery', 'models', 'capabilities', 'credential'))) { return $false }
    if ($Config.schemaVersion -isnot [int] -or $Config.schemaVersion -ne 1 -or $Config.schemaStatus -cne 'draft_requires_desktop_contract_verification' -or $Config.provider -cne 'DeepSeek') { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $Config.modelDiscovery -Expected @('enabled'))) { return $false }
    if ($Config.modelDiscovery.enabled -isnot [bool] -or $Config.modelDiscovery.enabled) { return $false }
    $models = @($Config.models)
    if ($models.Count -ne 2 -or $models[0] -isnot [string] -or $models[1] -isnot [string]) { return $false }
    if ($models[0] -cne 'deepseek-chat' -or $models[1] -cne 'deepseek-reasoner') { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $Config.capabilities -Expected @('chat', 'code', 'cowork'))) { return $false }
    foreach ($name in @('chat', 'code', 'cowork')) {
        if ($Config.capabilities.$name -isnot [bool] -or -not $Config.capabilities.$name) { return $false }
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $Config.credential -Expected @('source', 'value', 'persistInState'))) { return $false }
    if ($Config.credential.source -cne 'runtime_secure_handle' -or $null -ne $Config.credential.value) { return $false }
    if ($Config.credential.persistInState -isnot [bool] -or $Config.credential.persistInState) { return $false }
    $serialized = ConvertTo-CddsiJson -InputObject $Config
    return (@(Find-CddsiPotentialSecrets -Content $serialized -Source '<desired-config>').Count -eq 0)
}

function Compare-CddsiClaudeDesktopConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Current,
        [Parameter(Mandatory = $true)]$Desired
    )

    return New-CddsiOperationResult -Operation 'CompareConfigLibrary' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '配置差异算法尚未实现。' -Data ([pscustomobject]@{ CurrentProvided = ($null -ne $Current); DesiredValid = (Test-CddsiClaudeDesktopConfigContract -Config $Desired) })
}

function New-CddsiConfigRestorableBackup {
    [CmdletBinding()]
    param(
        [string]$TargetPath = (Get-CddsiClaudeDesktopConfigLibraryPath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiConfigLibraryTarget -TargetPath $TargetPath -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) { throw '拒绝备份：目标不是受信任的 configLibrary 路径。' }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'BackupConfigLibrary' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'BackupConfigLibrary' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会读取或备份配置；未来恢复包必须使用 DPAPI 或等效保护。' -PlannedChanges @($TargetPath)
}

function New-CddsiConfigRedactedSnapshot {
    [CmdletBinding()]
    param(
        [string]$TargetPath = (Get-CddsiClaudeDesktopConfigLibraryPath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiConfigLibraryTarget -TargetPath $TargetPath -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) { throw '拒绝生成快照：目标不是受信任的 configLibrary 路径。' }
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'CreateRedactedConfigSnapshot' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'CreateRedactedConfigSnapshot' -Status 'not_implemented' -Mode $Mode -MessageSafe '不会读取配置；脱敏诊断快照合同已定义。'
}

function Write-CddsiClaudeDesktopConfigAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$DesiredConfig,
        [string]$TargetPath = (Get-CddsiClaudeDesktopConfigLibraryPath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiConfigLibraryTarget -TargetPath $TargetPath -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) {
        throw '拒绝写入：目标不是 %LOCALAPPDATA%\Claude-3p\configLibrary。'
    }
    if (-not (Test-CddsiClaudeDesktopConfigContract -Config $DesiredConfig)) {
        throw 'DesiredConfig 不符合固定模型、关闭 discovery 与功能开关合同。'
    }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'WriteConfigLibraryAtomic' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'WriteConfigLibraryAtomic' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会写入 Claude Desktop 配置。未来流程：同目录临时文件、重读校验、flush、原子替换。' -PlannedChanges @($TargetPath)
}

function Restore-CddsiClaudeDesktopConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$BackupId,
        [string]$TargetPath = (Get-CddsiClaudeDesktopConfigLibraryPath),
        [string]$LocalAppDataPath = [Environment]::GetFolderPath('LocalApplicationData'),
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiConfigLibraryTarget -TargetPath $TargetPath -LocalAppDataPath $LocalAppDataPath -Mode $Mode)) {
        throw '拒绝恢复：目标不是 configLibrary。'
    }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'RestoreConfigLibrary' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'RestoreConfigLibrary' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会读取备份或恢复配置。' -Data ([pscustomobject]@{ BackupId = $BackupId }) -PlannedChanges @($TargetPath)
}
