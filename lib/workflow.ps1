# User-facing D-027 practical workflow.

function Invoke-CddsiDryRun {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Diagnose', 'Restore')]
        [string]$Action
    )

    $plans = @{
        Install = @(
            'Check Windows 11 x64 and Windows PowerShell 5.1'
            'Reuse a working unique Git, or install the official latest Git for Windows'
            'Download, verify and install the official latest Claude x64 MSIX'
            'Store the DeepSeek key with DPAPI CurrentUser'
            'Write the minimal HKCU Claude third-party policy'
            'Launch Claude Desktop'
        )
        Diagnose = @(
            'Read Windows, Git, Claude AppX and project-owned configuration status'
            'Never read the stored API key'
        )
        Restore = @(
            'Remove only the policy, helper, encrypted credential and state owned by this project'
        )
    }
    New-CddsiResult -Status 'SUCCEEDED' -Changed $false `
        -Message ('DryRun 完成：{0} 未执行任何网络、进程、注册表、AppX 或文件写入。' -f $Action) `
        -NextStep '从 Release ZIP 双击相应入口执行真实操作。' `
        -Data ([pscustomobject][ordered]@{
            Mode = 'DryRun'
            Plan = @($plans[$Action])
        })
}

function Invoke-CddsiInstallWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,
        [switch]$AcceptChanges,
        [switch]$NonInteractive
    )

    $changed = $false
    $tempDirectory = $null
    try {
        $build = Assert-CddsiSupportedRuntime
        $settings = Get-CddsiSettings -ProjectRoot $ProjectRoot
        $paths = Get-CddsiProductPaths
        Assert-CddsiConfigurationPreflight -ProjectRoot $ProjectRoot -Paths $paths

        Write-Host '即将检查或安装 Git、安装最新版 Claude Desktop、关闭正在运行的 Claude、'
        Write-Host '保存加密 API Key，'
        Write-Host '并写入当前用户 HKCU\SOFTWARE\Policies\Claude。'
        Write-Host '安装器不会读取或修改 Git 全局配置，也不会访问 Claude Code settings.json。'
        if (-not (Read-CddsiConfirmation `
            -Prompt '是否继续' `
            -AcceptChanges:$AcceptChanges `
            -NonInteractive:$NonInteractive)) {
            return New-CddsiResult -Status 'CANCELLED' `
                -ErrorCode 'USER_CANCELLED' -Changed $false `
                -Message '用户取消，未执行安装。' `
                -NextStep '准备好后重新双击开始安装。'
        }

        $tempDirectory = New-CddsiTempDirectory
        $git = Install-CddsiGitIfNeeded -TempDirectory $tempDirectory
        $changed = $changed -or $git.Changed

        $claude = Install-CddsiClaudeDesktop -TempDirectory $tempDirectory
        $changed = $changed -or $claude.Changed

        [void](Stop-CddsiClaudeProcesses)
        $configuration = Set-CddsiClaudeConfiguration `
            -ProjectRoot $ProjectRoot -Settings $settings `
            -NonInteractive:$NonInteractive
        $changed = $changed -or $configuration.Changed

        try {
            Start-Process -FilePath 'claude://claude.ai/new' -ErrorAction Stop |
                Out-Null
        }
        catch {
            Throw-CddsiError -Code 'CLAUDE_LAUNCH_FAILED' `
                -Message '安装和配置已完成，但无法自动打开 Claude Desktop。'
        }

        return New-CddsiResult -Status 'SUCCEEDED' -Changed $changed `
            -Message ('安装完成：Windows build {0}，Git {1}，Claude {2}，DeepSeek HKCU 配置已 readback。' -f `
                $build, $git.Version, $claude.Version) `
            -NextStep '在 Claude 中先验证文本 Chat；Code/Cowork 的具体兼容性由 VM 实测继续补齐。' `
            -Data ([pscustomobject][ordered]@{
                WindowsBuild = $build
                GitVersion   = [string]$git.Version
                ClaudeVersion = [string]$claude.Version
                ConfigurationOwned = $configuration.Owned
                CoworkProvisioning = 'NOT_INCLUDED_IN_PRACTICAL_MVP'
            })
    }
    catch {
        return ConvertFrom-CddsiSafeException -Exception $_.Exception `
            -Changed $changed
    }
    finally {
        if ($null -ne $tempDirectory) {
            try {
                Remove-CddsiTempDirectory -Path $tempDirectory
            }
            catch {
                # Cleanup failure must not hide the primary result. The random
                # owner-scoped directory is reported by neither logs nor state.
            }
        }
    }
}

function Invoke-CddsiDiagnoseWorkflow {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    try {
        $build = Assert-CddsiSupportedRuntime
        $git = Get-CddsiGitStatus
        $claude = Get-CddsiClaudeStatus
        $configuration = Get-CddsiConfigurationStatus -ProjectRoot $ProjectRoot
        $ready = $git.Healthy -and $claude.Installed -and
            $configuration.PolicyMatches -and
            $configuration.HelperPresent -and
            $configuration.CredentialPresent -and
            $configuration.IntegrityMatches
        if ($ready) {
            return New-CddsiResult -Status 'SUCCEEDED' -Changed $false `
                -Message 'Git、Claude Desktop、DPAPI helper 和 HKCU 配置均已就绪。' `
                -NextStep '打开 Claude，验证 DeepSeek 文本对话。' `
                -Data ([pscustomobject][ordered]@{
                    WindowsBuild = $build
                    GitVersion = [string]$git.Version
                    ClaudeVersion = [string]$claude.Version
                    PolicyMatches = $configuration.PolicyMatches
                })
        }
        return New-CddsiResult -Status 'ACTION_REQUIRED' `
            -ErrorCode 'INSTALLATION_INCOMPLETE' -Changed $false `
            -Message '至少一项必要组件或项目配置尚未就绪。' `
            -NextStep '重新双击开始安装；它会复用已成功完成的步骤。' `
            -Data ([pscustomobject][ordered]@{
                WindowsBuild = $build
                GitHealthy = $git.Healthy
                ClaudeInstalled = $claude.Installed
                PolicyMatches = $configuration.PolicyMatches
                HelperPresent = $configuration.HelperPresent
                CredentialPresent = $configuration.CredentialPresent
                IntegrityMatches = $configuration.IntegrityMatches
            })
    }
    catch {
        return ConvertFrom-CddsiSafeException -Exception $_.Exception
    }
}

function Invoke-CddsiRestoreWorkflow {
    [CmdletBinding()]
    param(
        [switch]$AcceptChanges,
        [switch]$NonInteractive
    )

    $restoreStarted = $false
    try {
        [void](Assert-CddsiSupportedRuntime)
        if (-not (Read-CddsiConfirmation `
            -Prompt '是否删除本项目拥有的 Claude HKCU policy、helper 和加密凭据' `
            -AcceptChanges:$AcceptChanges `
            -NonInteractive:$NonInteractive)) {
            return New-CddsiResult -Status 'CANCELLED' `
                -ErrorCode 'USER_CANCELLED' -Changed $false `
                -Message '用户取消，未删除任何配置。' `
                -NextStep '无需操作。'
        }
        $restoreStarted = $true
        $restored = Restore-CddsiClaudeConfiguration
        return New-CddsiResult -Status 'SUCCEEDED' `
            -Changed $restored.Changed `
            -Message '已删除本项目拥有的 HKCU policy、helper、DPAPI 密文和状态。' `
            -NextStep '完全退出并重新打开 Claude Desktop，使配置变化生效。'
    }
    catch {
        return ConvertFrom-CddsiSafeException -Exception $_.Exception `
            -Changed $restoreStarted
    }
}

function Invoke-CddsiAction {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('Install', 'Diagnose', 'Restore')]
        [string]$Action,

        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [switch]$AcceptChanges,
        [switch]$NonInteractive
    )

    switch ($Action) {
        'Install' {
            return Invoke-CddsiInstallWorkflow -ProjectRoot $ProjectRoot `
                -AcceptChanges:$AcceptChanges -NonInteractive:$NonInteractive
        }
        'Diagnose' {
            return Invoke-CddsiDiagnoseWorkflow -ProjectRoot $ProjectRoot
        }
        'Restore' {
            return Invoke-CddsiRestoreWorkflow `
                -AcceptChanges:$AcceptChanges -NonInteractive:$NonInteractive
        }
    }
}
