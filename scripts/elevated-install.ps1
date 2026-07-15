[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [Alias('ExecutionContext')]$Context,

    [Parameter(Mandatory = $true)]
    [ValidateSet('ClaudeDesktopMsix', 'GitForWindows', 'VirtualMachinePlatform')]
    [string]$Operation,

    [ValidateSet('TestSafe', 'DryRun', 'Live')]
    [string]$Mode = 'TestSafe',

    [switch]$AcknowledgeRealChanges,
    [switch]$AcknowledgeRestart,
    [switch]$PassThru
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
. (Join-Path $root 'lib\bootstrap.ps1')
Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
Initialize-CddsiScript -ExecutionContext $Context -ScriptName 'elevated-install' -Mode $Mode | Out-Null

if ($Mode -eq 'Live') {
    throw 'elevated-install.ps1 的 Live 执行尚未实现，且脚手架阶段禁止提权或系统修改。'
}

$result = New-CddsiOperationResult -Operation ("Elevated:{0}" -f $Operation) -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '未请求管理员权限，未执行安装、Windows 功能更改或重启。'
if ($PassThru) { return $result }
Write-CddsiLog -ExecutionContext $Context -Level INFO -Message $result.MessageSafe -PathTokenValues (Get-CddsiExecutionPathTokenValues -ExecutionContext $Context)
