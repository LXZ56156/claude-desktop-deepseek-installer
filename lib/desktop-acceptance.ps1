# desktop-acceptance.ps1 - Acceptance-plan and redacted-report contracts.

function Get-CddsiAcceptancePlan {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Id = 'desktop_msix'; Description = 'Claude Desktop 已安装且 MSIX 签名有效'; Implemented = $false },
        [pscustomobject]@{ Id = 'git_ready'; Description = 'Git for Windows 可用'; Implemented = $false },
        [pscustomobject]@{ Id = 'cowork_ready'; Description = 'Cowork 前置条件与服务就绪'; Implemented = $false },
        [pscustomobject]@{ Id = 'config_atomic'; Description = 'configLibrary 原子写入、备份与恢复合同成立'; Implemented = $false },
        [pscustomobject]@{ Id = 'chat'; Description = 'Chat 验收'; Implemented = $false },
        [pscustomobject]@{ Id = 'code'; Description = 'Code 验收'; Implemented = $false },
        [pscustomobject]@{ Id = 'cowork'; Description = 'Cowork 验收'; Implemented = $false },
        [pscustomobject]@{ Id = 'claude_code_settings_unchanged'; Description = 'Claude Code settings 完整性证明（策略待确认）'; Implemented = $false },
        [pscustomobject]@{ Id = 'api_key_leak_free'; Description = '日志、报告、状态与发布包无 API Key'; Implemented = $false }
    )
}

function Get-CddsiClaudeCodeSettingsIntegrityContract {
    [CmdletBinding()]
    param()

    # Deliberately does not resolve or read ~/.claude/settings.json. The user
    # must later decide whether a hash-only provider is compatible with the
    # stronger no-read policy.
    return [pscustomobject][ordered]@{
        policy                 = 'do_not_read_or_modify'
        hashOnlyProviderAllowed = $null
        contentParsingAllowed  = $false
        contentLoggingAllowed  = $false
        implementationStatus   = 'decision_required'
    }
}

function Get-CddsiClaudeCodeSettingsFingerprint {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'GetClaudeCodeSettingsFingerprint' -Status 'decision_required' -Mode 'TestSafe' -MessageSafe '未定位或读取 settings.json；哈希只读例外尚待用户确认。' -Data (Get-CddsiClaudeCodeSettingsIntegrityContract)
}

function Test-CddsiClaudeCodeSettingsUnchanged {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$BeforeToken,
        [AllowNull()][string]$AfterToken
    )

    if ([string]::IsNullOrWhiteSpace($BeforeToken) -or [string]::IsNullOrWhiteSpace($AfterToken)) {
        return New-CddsiOperationResult -Operation 'VerifyClaudeCodeSettingsUnchanged' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '未读取 Claude Code 配置；完整性 provider 尚待决策。'
    }
    return New-CddsiOperationResult -Operation 'VerifyClaudeCodeSettingsUnchanged' -Status 'evaluated_mock_tokens' -Success ($BeforeToken -eq $AfterToken) -Mode 'TestSafe' -MessageSafe '仅比较调用方提供的不透明 token。' -Data ([pscustomobject]@{ Unchanged = ($BeforeToken -eq $AfterToken) })
}

function Test-CddsiApiKeyLeak {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [string]$Source = '<memory>'
    )

    $findings = @(Find-CddsiPotentialSecrets -Content $Content -Source $Source)
    return [pscustomobject][ordered]@{
        Passed   = ($findings.Count -eq 0)
        Findings = $findings
    }
}

function Test-CddsiChatAcceptance {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'AcceptChat' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '未启动 Claude Desktop 或发送请求。'
}

function Test-CddsiCodeAcceptance {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'AcceptCode' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '未启动 Claude Desktop 或执行 Code 工作流。'
}

function Test-CddsiCoworkAcceptance {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'AcceptCowork' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '未启动 Claude Desktop 或执行 Cowork 工作流。'
}

function Get-CddsiRepairPlan {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Id = 'repair_msix'; Action = '重新检测并验签 Claude Desktop MSIX'; Implemented = $false },
        [pscustomobject]@{ Id = 'repair_git'; Action = '重新检测 Git for Windows'; Implemented = $false },
        [pscustomobject]@{ Id = 'repair_cowork'; Action = '重新评估 Cowork 前置条件'; Implemented = $false },
        [pscustomobject]@{ Id = 'repair_config'; Action = '从受保护备份恢复或重新应用 configLibrary'; Implemented = $false }
    )
}

function Invoke-CddsiDesktopRepair {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'DesktopRepair' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'DesktopRepair' -Status 'not_implemented' -Mode $Mode -MessageSafe '修复编排仅返回计划；未读取或修改本机。' -Data (Get-CddsiRepairPlan)
}

function Invoke-CddsiDesktopAcceptance {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -Operation 'DesktopAcceptance' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    return New-CddsiOperationResult -Operation 'DesktopAcceptance' -Status 'not_implemented' -Mode $Mode -MessageSafe '不会访问 Claude Desktop、DeepSeek 或用户配置。' -Data (Get-CddsiAcceptancePlan)
}

function New-CddsiAcceptanceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Results
    )

    $safe = Protect-CddsiReportText -Text (ConvertTo-CddsiJson -InputObject $Results)
    if (@(Find-CddsiPotentialSecrets -Content $safe -Source '<acceptance-report>').Count -gt 0) {
        throw '验收报告在脱敏后仍包含疑似凭据，已拒绝生成。'
    }
    return [pscustomobject][ordered]@{
        language = 'zh-CN'
        redacted = $true
        content  = "Claude Desktop 验收报告（已脱敏）`n$safe"
        persisted = $false
    }
}
