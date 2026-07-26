# Shared result, validation and temporary-directory helpers.

$script:CddsiOwnerId = 'claude-desktop-deepseek-installer'
$script:CddsiStateSchemaVersion = 1
$script:CddsiPolicyPath = 'HKCU:\SOFTWARE\Policies\Claude'
$script:CddsiMachinePolicyPath = 'HKLM:\SOFTWARE\Policies\Claude'
$script:CddsiOwnershipPath = 'HKCU:\SOFTWARE\ClaudeDeepSeekInstaller'
$script:CddsiCredentialEntropy = [System.Text.Encoding]::UTF8.GetBytes(
    'claude-desktop-deepseek-installer:deepseek:v1'
)

function New-CddsiResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateSet('SUCCEEDED', 'PARTIAL', 'ACTION_REQUIRED', 'CANCELLED', 'FAILED')]
        [string]$Status,

        [string]$ErrorCode = '',
        [string]$Message = '',
        [string]$NextStep = '',
        [bool]$Changed = $false,
        [AllowNull()]$Data = $null
    )

    [pscustomobject][ordered]@{
        Status    = $Status
        ErrorCode = $ErrorCode
        Changed   = $Changed
        Message   = $Message
        NextStep  = $NextStep
        Data      = $Data
    }
}

function Get-CddsiExitCode {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Status
    )

    switch ($Status) {
        'SUCCEEDED' { return 0 }
        'ACTION_REQUIRED' { return 2 }
        'PARTIAL' { return 2 }
        'CANCELLED' { return 3 }
        default { return 1 }
    }
}

function Write-CddsiResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Result
    )

    Write-Host ('Status={0}' -f $Result.Status)
    Write-Host ('ErrorCode={0}' -f $Result.ErrorCode)
    Write-Host ('Changed={0}' -f $Result.Changed.ToString().ToLowerInvariant())
    Write-Host ('Message={0}' -f $Result.Message)
    Write-Host ('NextStep={0}' -f $Result.NextStep)
}

function Throw-CddsiError {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidatePattern('^[A-Z0-9_]{3,80}$')]
        [string]$Code,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    throw [System.InvalidOperationException]::new(('{0}|{1}' -f $Code, $Message))
}

function ConvertFrom-CddsiSafeException {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Exception]$Exception,

        [bool]$Changed = $false
    )

    $code = 'UNEXPECTED_FAILURE'
    $message = '操作未完成。详细异常已隐藏，以避免泄露本机信息。'
    if ($Exception.Message -match '^(?<Code>[A-Z0-9_]{3,80})\|(?<Safe>[^\r\n]{1,500})$') {
        $code = $Matches.Code
        $message = $Matches.Safe
    }

    $status = switch -Regex ($code) {
        '^USER_CANCELLED$' { 'CANCELLED'; break }
        '(_CONFLICT|_REQUIRED|_UNAVAILABLE|_NOT_FOUND)$' { 'ACTION_REQUIRED'; break }
        default { if ($Changed) { 'PARTIAL' } else { 'FAILED' } }
    }

    New-CddsiResult -Status $status -ErrorCode $code -Changed $Changed `
        -Message $message -NextStep '按提示处理后重新双击安装入口。'
}

function Get-CddsiSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $path = Join-Path $ProjectRoot 'config\deepseek-desktop.defaults.json'
    if (-not (Test-Path -LiteralPath $path -PathType Leaf)) {
        Throw-CddsiError -Code 'PRODUCT_CONFIG_NOT_FOUND' -Message '产品配置文件缺失。'
    }

    try {
        $settings = Get-Content -LiteralPath $path -Raw -Encoding UTF8 | ConvertFrom-Json
    }
    catch {
        Throw-CddsiError -Code 'PRODUCT_CONFIG_INVALID' -Message '产品配置文件无法解析。'
    }

    $models = @($settings.models)
    if ($settings.schemaVersion -ne 3 -or
        $settings.provider.kind -cne 'gateway' -or
        $settings.provider.baseUrl -cne 'https://api.deepseek.com/anthropic' -or
        $settings.provider.authScheme -cne 'x-api-key' -or
        $models.Count -ne 2 -or
        $models[0].name -cne 'deepseek-v4-pro' -or
        $models[1].name -cne 'deepseek-v4-flash') {
        Throw-CddsiError -Code 'PRODUCT_CONFIG_INVALID' -Message '产品配置不符合 D-027 practical 合同。'
    }
    return $settings
}

function Assert-CddsiSupportedRuntime {
    [CmdletBinding()]
    param()

    if ($PSVersionTable.PSEdition -cne 'Desktop' -or
        $PSVersionTable.PSVersion.Major -ne 5 -or
        -not [Environment]::Is64BitProcess -or
        -not [Environment]::Is64BitOperatingSystem) {
        Throw-CddsiError -Code 'RUNTIME_UNSUPPORTED' `
            -Message '只支持 64 位 Windows PowerShell 5.1。'
    }

    $build = 0
    try {
        $windows = Get-ItemProperty -LiteralPath `
            'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' `
            -Name CurrentBuildNumber, InstallationType `
            -ErrorAction Stop
        $build = [int]$windows.CurrentBuildNumber
    }
    catch {
        Throw-CddsiError -Code 'WINDOWS_VERSION_UNAVAILABLE' `
            -Message '无法确认 Windows 版本。'
    }
    if ($build -lt 22000 -or
        $windows.InstallationType -cne 'Client' -or
        $env:PROCESSOR_ARCHITECTURE -cne 'AMD64' -or
        $env:PROCESSOR_ARCHITEW6432 -ceq 'ARM64') {
        Throw-CddsiError -Code 'WINDOWS_VERSION_UNSUPPORTED' `
            -Message '当前首版只支持 Windows 11 x64。'
    }
    return $build
}

function Get-CddsiProductPaths {
    [CmdletBinding()]
    param()

    if ([string]::IsNullOrWhiteSpace($env:LOCALAPPDATA)) {
        Throw-CddsiError -Code 'LOCAL_APPDATA_UNAVAILABLE' `
            -Message '无法定位当前用户的 LocalAppData。'
    }
    $root = Join-Path $env:LOCALAPPDATA 'ClaudeDeepSeekInstaller'
    [pscustomobject][ordered]@{
        Root           = $root
        Credential     = Join-Path $root 'credential.bin'
        Helper         = Join-Path $root 'DeepSeekCredentialHelper.exe'
        State          = Join-Path $root 'state.json'
        OwnershipMarker = Join-Path $root '.cddsi-owner'
    }
}

function New-CddsiPrivateDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $created = $false
    if (Test-Path -LiteralPath $Path) {
        $item = Get-Item -LiteralPath $Path -Force -ErrorAction Stop
        if (-not $item.PSIsContainer -or
            ($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-CddsiError -Code 'PRODUCT_DIRECTORY_UNSAFE' `
                -Message '产品私有目录不是普通目录，拒绝继续。'
        }
    }
    else {
        New-Item -ItemType Directory -Path $Path -ErrorAction Stop | Out-Null
        $created = $true
    }

    if (-not $created) {
        return
    }
    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleSpecific($rule)
    }
    $inheritance = [System.Security.AccessControl.InheritanceFlags]'ContainerInherit, ObjectInherit'
    $propagation = [System.Security.AccessControl.PropagationFlags]::None
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    foreach ($sid in @(
        $identity,
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')),
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544'))
    )) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            $propagation,
            $allow
        )
        [void]$acl.AddAccessRule($rule)
    }
    [System.IO.Directory]::SetAccessControl($Path, $acl)
}

function Set-CddsiPrivateFileAcl {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $identity = [System.Security.Principal.WindowsIdentity]::GetCurrent().User
    $acl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $acl.SetAccessRuleProtection($true, $false)
    foreach ($rule in @($acl.Access)) {
        [void]$acl.RemoveAccessRuleSpecific($rule)
    }
    $allow = [System.Security.AccessControl.AccessControlType]::Allow
    foreach ($sid in @(
        $identity,
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-18')),
        (New-Object System.Security.Principal.SecurityIdentifier('S-1-5-32-544'))
    )) {
        $rule = New-Object System.Security.AccessControl.FileSystemAccessRule(
            $sid,
            [System.Security.AccessControl.FileSystemRights]::FullControl,
            $allow
        )
        [void]$acl.AddAccessRule($rule)
    }
    [System.IO.File]::SetAccessControl($Path, $acl)
}

function New-CddsiTempDirectory {
    [CmdletBinding()]
    param()

    $root = [System.IO.Path]::GetTempPath()
    $leaf = 'cddsi-{0}' -f ([guid]::NewGuid().ToString('N'))
    $path = Join-Path $root $leaf
    New-Item -ItemType Directory -Path $path -ErrorAction Stop | Out-Null
    return $path
}

function Remove-CddsiTempDirectory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    $full = [System.IO.Path]::GetFullPath($Path)
    $temp = [System.IO.Path]::GetFullPath([System.IO.Path]::GetTempPath())
    $leaf = Split-Path -Leaf $full
    if (-not $full.StartsWith($temp, [StringComparison]::OrdinalIgnoreCase) -or
        $leaf -notmatch '^cddsi-[a-f0-9]{32}$') {
        Throw-CddsiError -Code 'TEMP_CLEANUP_REFUSED' `
            -Message '临时目录不属于本次运行，拒绝清理。'
    }
    if (Test-Path -LiteralPath $full) {
        Remove-Item -LiteralPath $full -Recurse -Force -ErrorAction Stop
    }
}

function Get-CddsiFileSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    (Get-FileHash -LiteralPath $Path -Algorithm SHA256 -ErrorAction Stop).Hash.ToLowerInvariant()
}

function Read-CddsiConfirmation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Prompt,
        [switch]$AcceptChanges,
        [switch]$NonInteractive
    )

    if ($AcceptChanges) {
        return $true
    }
    if ($NonInteractive) {
        return $false
    }
    $answer = Read-Host ('{0} [y/N]' -f $Prompt)
    return $answer -match '^(?i:y|yes)$'
}
