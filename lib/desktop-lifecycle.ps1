# desktop-lifecycle.ps1 - Claude Desktop process lifecycle contracts.
# No process is queried, stopped or started at scaffold stage.

function Get-CddsiClaudeDesktopProcessState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    return New-CddsiOperationResult -Operation 'DetectClaudeDesktopProcess' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'NOT_IMPLEMENTED' -MessageSafe '未查询 Claude 进程。'
}

function Stop-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'StopClaudeDesktop' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'StopClaudeDesktop' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '不会关闭 Claude Desktop 进程。'
}

function Start-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'StartClaudeDesktop' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'StartClaudeDesktop' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '不会启动 Claude Desktop 进程。'
}

function Restart-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'RestartClaudeDesktop' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'RestartClaudeDesktop' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '不会重启 Claude Desktop 进程。'
}
