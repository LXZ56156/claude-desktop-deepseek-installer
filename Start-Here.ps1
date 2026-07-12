[CmdletBinding()]
param(
    [ValidateSet('Install', 'Diagnose', 'Repair', 'Restore')]
    [string]$Action = 'Install',

    [switch]$TestSafe,
    [switch]$DryRun,
    [switch]$Live,
    [switch]$NonInteractive,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path $PSScriptRoot 'lib\bootstrap.ps1'
. $bootstrapPath
$mode = Resolve-CddsiExecutionMode -TestSafe:$TestSafe -DryRun:$DryRun -Live:$Live
Initialize-CddsiScript -ScriptName ('start-{0}' -f $Action.ToLowerInvariant()) -Mode $mode | Out-Null
if ($mode -eq 'Live') {
    throw 'Live 模式在开发前脚手架阶段被强制禁用；没有真实安装功能可执行。'
}

Write-CddsiLog -Level INFO -Message ("动作={0}，模式={1}，阶段={2}" -f $Action, $mode, (Get-CddsiProjectStage))

switch ($Action) {
    'Install' {
        $result = New-CddsiOperationResult -Operation 'StartInstall' -Status 'scaffold_only' -Success $true -Mode $mode -MessageSafe '安装模块边界已加载；MSIX、Git、Windows 功能、API、配置和进程操作均未执行。' -PlannedChanges @(
            'Detect and verify official Claude Desktop MSIX',
            'Detect Git for Windows',
            'Evaluate Cowork readiness',
            'Obtain a DeepSeek credential securely',
            'Prepare configLibrary desired state'
        )
    }
    'Diagnose' {
        $result = New-CddsiOperationResult -Operation 'RunDiagnostics' -Status 'scaffold_only' -Success $true -Mode $mode -MessageSafe '诊断合同已加载，但未读取本机 Claude、Windows 功能、Git 或用户配置。' -Data ([pscustomobject][ordered]@{
            environment = Get-CddsiDesktopEnvironmentSnapshot
            cowork      = Get-CddsiCoworkReadiness
            acceptance  = Get-CddsiAcceptancePlan
        })
    }
    'Restore' {
        $result = New-CddsiOperationResult -Operation 'RestoreConfig' -Status 'scaffold_only' -Success $true -Mode $mode -MessageSafe '恢复合同已加载；未读取备份、未写入 configLibrary。'
    }
    'Repair' {
        $repair = Invoke-CddsiDesktopRepair -Mode $mode
        $result = New-CddsiOperationResult -Operation 'RepairDesktop' -Status 'scaffold_only' -Success $true -Mode $mode -MessageSafe '修复合同已加载；未执行安装、系统修改、API、配置或进程操作。' -Data $repair.Data
    }
}

Write-CddsiLog -Level SUCCESS -Message $result.MessageSafe
if ($PassThru) {
    return $result
}
