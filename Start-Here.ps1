[CmdletBinding()]
param(
    [ValidateSet('Install', 'Diagnose', 'Repair', 'Restore')]
    [string]$Action = 'Install',

    [switch]$TestSafe,
    [switch]$DryRun,
    [switch]$Live,
    [switch]$NonInteractive,
    [switch]$PassThru,

    [AllowNull()]
    [Alias('ExecutionContext')]$Context
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
trap {
    if ($PassThru) { throw $_ }
    Write-Host 'Status=FAILED'
    Write-Host 'ErrorCode=UNHANDLED_SAFE_FAILURE'
    Write-Host 'Changed=false'
    Write-Host 'NextStep=Review safe logs before retrying.'
    exit 1
}

$bootstrapPath = Join-Path $PSScriptRoot 'lib\bootstrap.ps1'
. $bootstrapPath
$mode = Resolve-CddsiExecutionMode -TestSafe:$TestSafe -DryRun:$DryRun -Live:$Live
if ($mode -eq 'Live') {
    throw 'Live 模式在开发前脚手架阶段被强制禁用；没有真实安装功能可执行。'
}

if ($null -eq $Context) {
    $syntheticRoot = 'C:\cddsi-synthetic'
    $expectedCalls = @()
    if ($Action -ceq 'Diagnose') {
        $expectedCalls = @(
            [pscustomobject][ordered]@{
                Provider      = 'Environment'
                Operation     = 'Inspect'
                ResourceToken = '<ENVIRONMENT:WINDOWS>'
                Arguments     = [ordered]@{}
                Result        = [pscustomobject][ordered]@{
                    SchemaVersion   = 1
                    Platform        = 'Windows'
                    BuildNumber     = 19041
                    Architecture    = 'x64'
                    IsAdministrator = $false
                }
            }
            [pscustomobject][ordered]@{
                Provider      = 'Package'
                Operation     = 'Inspect'
                ResourceToken = '<PACKAGE:CLAUDE_DESKTOP>'
                Arguments     = [ordered]@{}
                Result        = [pscustomobject][ordered]@{ SchemaVersion = 1; Installations = @() }
            }
            [pscustomobject][ordered]@{
                Provider      = 'Process'
                Operation     = 'Inspect'
                ResourceToken = '<PROCESS:GIT_FOR_WINDOWS>'
                Arguments     = [ordered]@{}
                Result        = [pscustomobject][ordered]@{ SchemaVersion = 1; Candidates = @() }
            }
            [pscustomobject][ordered]@{
                Provider      = 'Feature'
                Operation     = 'Inspect'
                ResourceToken = '<FEATURE:VIRTUAL_MACHINE_PLATFORM>'
                Arguments     = [ordered]@{}
                Result        = [pscustomobject][ordered]@{ SchemaVersion = 1; State = 'Unknown' }
            }
            [pscustomobject][ordered]@{
                Provider      = 'Environment'
                Operation     = 'Inspect'
                ResourceToken = '<ENVIRONMENT:HARDWARE_VIRTUALIZATION>'
                Arguments     = [ordered]@{}
                Result        = [pscustomobject][ordered]@{ SchemaVersion = 1; State = 'Unknown' }
            }
            [pscustomobject][ordered]@{
                Provider      = 'Service'
                Operation     = 'Inspect'
                ResourceToken = '<SERVICE:COWORK>'
                Arguments     = [ordered]@{}
                Result        = [pscustomobject][ordered]@{
                    SchemaVersion  = 1
                    IdentityToken  = '<SERVICE_ID:COWORK>'
                    IdentityStatus = 'Unknown'
                    State          = 'Unknown'
                }
            }
        )
    }
    $paths = [ordered]@{
        Home            = Join-Path $syntheticRoot 'home'
        UserProfile     = Join-Path $syntheticRoot 'profile'
        LocalAppData    = Join-Path $syntheticRoot 'profile\AppData\Local'
        AppData         = Join-Path $syntheticRoot 'profile\AppData\Roaming'
        ProgramData     = Join-Path $syntheticRoot 'program-data'
        Temp            = Join-Path $syntheticRoot 'temp'
        Download        = Join-Path $syntheticRoot 'download'
        State           = Join-Path $syntheticRoot 'state\state.json'
        Backup          = Join-Path $syntheticRoot 'backup'
        Report          = Join-Path $syntheticRoot 'report'
        Credential      = Join-Path $syntheticRoot 'credential'
        ConfigLibrary   = Join-Path $syntheticRoot 'profile\AppData\Local\Claude-3p\configLibrary'
        GitGlobalConfig = Join-Path $syntheticRoot 'profile\.gitconfig'
        XdgConfig       = Join-Path $syntheticRoot 'xdg-config'
        XdgData         = Join-Path $syntheticRoot 'xdg-data'
    }
    $policy = [ordered]@{
        SchemaVersion            = 1
        AllowLiveProvider        = $false
        ForbiddenResourceTokens = @('<REAL_CLAUDE_CONFIG>', '<REAL_GIT_CONFIG>', '<REAL_REGISTRY>', '<REAL_PROCESS>', '<REAL_NETWORK>')
        CanaryTokens             = @('<CANARY_CLAUDE_CODE_SETTINGS>', '<CANARY_GIT_CONFIG>', '<CANARY_CLAUDE_POLICY>', '<CANARY_CREDENTIAL>')
    }
    $Context = New-CddsiExecutionContext -RunId '00000000-0000-0000-0000-000000000001' -Mode $mode -EnvironmentTier HostSandbox -SandboxRoot $syntheticRoot -Paths $paths -Providers (New-CddsiFakeProviderSet -ExpectedCalls $expectedCalls) -Policy $policy -AccessLedger (New-CddsiAccessLedger)
}

Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $mode | Out-Null
$pathTokenValues = Get-CddsiExecutionPathTokenValues -ExecutionContext $Context
Initialize-CddsiScript -ExecutionContext $Context -ScriptName ('start-{0}' -f $Action.ToLowerInvariant()) -Mode $mode -PathTokenValues $pathTokenValues | Out-Null

Write-CddsiLog -ExecutionContext $Context -Level INFO -Message ("动作={0}，模式={1}，阶段={2}" -f $Action, $mode, (Get-CddsiProjectStage)) -PathTokenValues $pathTokenValues

switch ($Action) {
    'Install' {
        $result = New-CddsiOperationResult -Operation 'StartInstall' -Status 'ACTION_REQUIRED' -Mode $mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '安装模块边界已加载；MSIX、Git、Windows 功能、API、配置和进程操作均未执行。' -PlannedChanges @(
            'Detect and verify official Claude Desktop MSIX',
            'Detect Git for Windows',
            'Evaluate Cowork readiness',
            'Obtain a DeepSeek credential securely',
            'Prepare HKCU managed-policy desired state'
        )
    }
    'Diagnose' {
        $desiredConfig = New-CddsiClaudeDesktopDesiredConfig
        if (-not (Test-CddsiClaudeDesktopConfigContract -Config $desiredConfig)) {
            throw '固定 Claude Desktop 3P 配置合同无效。'
        }
        $environment = Get-CddsiDesktopEnvironmentSnapshot -ExecutionContext $Context -MinimumBuild 19041 -SupportedArchitectures @('x64', 'arm64')
        $expectedArchitecture = if ($environment.Status -ceq 'SUCCEEDED') { $environment.Data.Architecture } else { 'Unknown' }
        $desktop = Get-CddsiClaudeDesktopMsixStatus -ExecutionContext $Context -MinimumVersion $desiredConfig.MinimumDesktopVersion -RequiredScope Unresolved -ExpectedArchitecture $expectedArchitecture
        $git = Get-CddsiGitForWindowsStatus -ExecutionContext $Context -MinimumVersion $null
        $vmp = Test-CddsiVirtualMachinePlatform -ExecutionContext $Context
        $hardware = Test-CddsiHardwareVirtualization -ExecutionContext $Context
        $service = Test-CddsiCoworkServiceStatus -ExecutionContext $Context
        $cowork = Get-CddsiCoworkReadiness -EnvironmentStatus $environment -DesktopStatus $desktop -VirtualMachinePlatformStatus $vmp -HardwareVirtualizationStatus $hardware -ServiceStatus $service -Mode $mode
        $surfaces = Resolve-CddsiEffectiveSurfaces -RequestedSurfaces $desiredConfig.RequestedSurfaces -EnvironmentStatus $environment -DesktopStatus $desktop -GitStatus $git -CoworkStatus $cowork -Mode $mode
        $result = New-CddsiOperationResult -Operation 'RunDiagnostics' -Status $surfaces.Status -Mode $mode -ErrorCode $surfaces.ErrorCode -MessageSafe '诊断仅消费 synthetic fake provider；未读取宿主机 Claude、Git、AppX、Windows 功能或服务。' -Data ([pscustomobject][ordered]@{
            Environment       = $environment
            Desktop           = $desktop
            Git               = $git
            Virtualization    = $hardware
            VirtualMachinePlatform = $vmp
            CoworkService     = $service
            Cowork            = $cowork
            Surfaces          = $surfaces
            AcceptancePlan    = Get-CddsiAcceptancePlan
        }) -RestartRequired:$surfaces.RestartRequired
    }
    'Restore' {
        $result = New-CddsiOperationResult -Operation 'RestoreConfig' -Status 'ACTION_REQUIRED' -Mode $mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '恢复合同已加载；未读取备份、未写入 managed policy。'
    }
    'Repair' {
        $repair = Invoke-CddsiDesktopRepair -ExecutionContext $Context -Mode $mode
        $result = New-CddsiOperationResult -Operation 'RepairDesktop' -Status 'ACTION_REQUIRED' -Mode $mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '修复合同已加载；未执行安装、系统修改、API、配置或进程操作。' -Data $repair.Data
    }
}

Write-CddsiLog -ExecutionContext $Context -Level INFO -Message $result.MessageSafe -PathTokenValues $pathTokenValues
if ($PassThru) {
    return $result
}

foreach ($line in @(Format-CddsiOperationCliSummary -Result $result)) {
    Write-Host $line
}
exit (Get-CddsiOperationExitCode -Status $result.Status)
