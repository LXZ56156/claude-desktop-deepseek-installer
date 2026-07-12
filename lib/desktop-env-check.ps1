# desktop-env-check.ps1 - Read-only environment detection contracts.
# TODO: implement with injected providers; never enable Windows features here.

function Get-CddsiClaudeDesktopStatus {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectClaudeDesktop' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe 'Claude Desktop MSIX 检测尚未实现。'
}

function Test-CddsiVirtualMachinePlatform {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectVirtualMachinePlatform' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe 'VirtualMachinePlatform 只读检测尚未实现。'
}

function Test-CddsiHardwareVirtualization {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectHardwareVirtualization' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '硬件虚拟化只读检测尚未实现。'
}

function Get-CddsiDesktopEnvironmentSnapshot {
    [CmdletBinding()]
    param()

    $data = [pscustomobject][ordered]@{
        claudeDesktop            = 'not_checked'
        windowsVersion           = 'not_checked'
        virtualMachinePlatform   = 'not_checked'
        hardwareVirtualization   = 'not_checked'
        coworkService            = 'not_checked'
        requiresRestart          = $false
    }
    return New-CddsiOperationResult -Operation 'EnvironmentSnapshot' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '环境快照接口已定义，未访问本机状态。' -Data $data
}
