# TestContext.ps1 - Synthetic P1 context construction for Unit/Contract tests.
# This helper performs no filesystem, environment, clock, process or network access.

function New-CddsiTestExecutionContext {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [ValidateSet('Scaffold', 'Development', 'VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive')]
        [string]$Stage = 'Scaffold',

        [ValidateSet('HostSandbox', 'CI', 'VmDevelopment', 'VmAcceptance', 'UserLive')]
        [string]$EnvironmentTier = 'HostSandbox',

        [string]$SandboxRoot = 'C:\cddsi-synthetic-tests',

        [object[]]$ExpectedCalls = @(),
        [object[]]$FailureInjections = @(),

        [string]$RunId = '00000000-0000-0000-0000-000000000101',

        [AllowNull()]
        $Providers = $null,

        [bool]$AllowLiveProvider = $false
    )

    $paths = [ordered]@{
        Home            = Join-Path $SandboxRoot 'home'
        UserProfile     = Join-Path $SandboxRoot 'profile'
        LocalAppData    = Join-Path $SandboxRoot 'profile\AppData\Local'
        AppData         = Join-Path $SandboxRoot 'profile\AppData\Roaming'
        ProgramData     = Join-Path $SandboxRoot 'program-data'
        Temp            = Join-Path $SandboxRoot 'temp'
        Download        = Join-Path $SandboxRoot 'download'
        State           = Join-Path $SandboxRoot 'state\state.json'
        Backup          = Join-Path $SandboxRoot 'backup'
        Report          = Join-Path $SandboxRoot 'report'
        Credential      = Join-Path $SandboxRoot 'credential'
        ConfigLibrary   = Join-Path $SandboxRoot 'profile\AppData\Local\Claude-3p\configLibrary'
        GitGlobalConfig = Join-Path $SandboxRoot 'profile\.gitconfig'
        XdgConfig       = Join-Path $SandboxRoot 'xdg-config'
        XdgData         = Join-Path $SandboxRoot 'xdg-data'
    }
    $policy = [ordered]@{
        SchemaVersion            = 1
        AllowLiveProvider        = $AllowLiveProvider
        ForbiddenResourceTokens = @('<REAL_CLAUDE_CONFIG>', '<REAL_GIT_CONFIG>', '<REAL_REGISTRY>', '<REAL_PROCESS>', '<REAL_NETWORK>')
        CanaryTokens             = @('<CANARY_CLAUDE_CODE_SETTINGS>', '<CANARY_GIT_CONFIG>', '<CANARY_CLAUDE_POLICY>', '<CANARY_CREDENTIAL>')
    }
    if ($null -eq $Providers) {
        $Providers = New-CddsiFakeProviderSet -ExpectedCalls $ExpectedCalls -FailureInjections $FailureInjections
    }
    return New-CddsiExecutionContext -RunId $RunId -Mode $Mode -Stage $Stage `
        -EnvironmentTier $EnvironmentTier -SandboxRoot $SandboxRoot -Paths $paths `
        -Providers $Providers -Policy $policy
}
