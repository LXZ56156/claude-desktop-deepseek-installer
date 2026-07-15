# state-store.ps1 - Provider-backed state persistence boundary.
# All host access is routed through the injected ExecutionContext provider set.

function Get-CddsiStatePath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $statePath = $Context.Paths.State
    if ($statePath -isnot [string] -or [string]::IsNullOrWhiteSpace($statePath)) {
        throw 'ExecutionContext.Paths.State 必须是显式的非空路径。'
    }
    return $statePath
}

function Test-CddsiStateTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $expected = Get-CddsiStatePath -ExecutionContext $Context
    try {
        $expectedFullPath = [System.IO.Path]::GetFullPath($expected).TrimEnd('\')
        $actualFullPath = [System.IO.Path]::GetFullPath($Path).TrimEnd('\')
        return [string]::Equals($expectedFullPath, $actualFullPath, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Read-CddsiState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe'
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    Get-CddsiStatePath -ExecutionContext $Context | Out-Null

    $content = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider 'FileSystem' -Operation 'ReadText' -ResourceToken '<STATE>' -Arguments ([ordered]@{
        Encoding = 'UTF8'
    })
    if ($content -isnot [string]) {
        throw 'FileSystem.ReadText 必须返回 JSON 字符串。'
    }

    $state = ConvertFrom-CddsiJson -Content $content -Source '<STATE>'
    if (-not (Test-CddsiStateSchema -State $state)) {
        throw '状态文件不符合 schema 或包含疑似凭据。'
    }
    if ($state.executionMode -cne $Mode -or $state.runId -cne $Context.RunId) {
        throw '状态文件的 executionMode 或 runId 与当前 ExecutionContext 不匹配。'
    }

    return New-CddsiOperationResult -Operation 'ReadState' -Status 'SUCCEEDED' -Mode $Mode -MessageSafe '状态已通过 fake FileSystem provider 读取并验证。' -Data $state
}

function Write-CddsiStateAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [Parameter(Mandatory = $true)]
        $State,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    Get-CddsiStatePath -ExecutionContext $Context | Out-Null
    if (-not (Test-CddsiStateSchema -State $State)) {
        throw '状态对象不符合 schema 或包含疑似凭据。'
    }
    if ($State.executionMode -cne $Mode -or $State.runId -cne $Context.RunId) {
        throw '状态对象的 executionMode 或 runId 与当前 ExecutionContext 不匹配。'
    }

    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'WriteStateAtomic' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }

    return New-CddsiOperationResult -Operation 'WriteStateAtomic' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe 'P1 不调用状态 mutation provider；仅返回原子写入计划。' -PlannedChanges @('<STATE>')
}
