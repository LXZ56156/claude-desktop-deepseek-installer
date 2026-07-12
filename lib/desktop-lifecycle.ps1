# desktop-lifecycle.ps1 - Claude Desktop process lifecycle contracts.
# No process is queried, stopped or started at scaffold stage.

function Get-CddsiClaudeDesktopProcessState {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectClaudeDesktopProcess' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '未查询 Claude 进程。'
}

function Stop-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'StopClaudeDesktop' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'StopClaudeDesktop' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会关闭 Claude Desktop 进程。'
}

function Start-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'StartClaudeDesktop' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'StartClaudeDesktop' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会启动 Claude Desktop 进程。'
}

function Restart-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'RestartClaudeDesktop' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'RestartClaudeDesktop' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会重启 Claude Desktop 进程。'
}
