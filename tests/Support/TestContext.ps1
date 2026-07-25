# TestContext.ps1 - Synthetic P1 context construction for Unit/Contract tests.
# This helper performs no filesystem, environment, clock, process or network access.

function New-CddsiTestExecutionContext {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun')]
        [string]$Mode = 'TestSafe',

        [string]$SandboxRoot = 'C:\cddsi-synthetic-tests',

        [object[]]$ExpectedCalls = @(),
        [object[]]$FailureInjections = @(),

        [string]$RunId = '00000000-0000-0000-0000-000000000101'
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
        AllowLiveProvider        = $false
        ForbiddenResourceTokens = @('<REAL_CLAUDE_CONFIG>', '<REAL_GIT_CONFIG>', '<REAL_REGISTRY>', '<REAL_PROCESS>', '<REAL_NETWORK>')
        CanaryTokens             = @('<CANARY_CLAUDE_CODE_SETTINGS>', '<CANARY_GIT_CONFIG>', '<CANARY_CLAUDE_POLICY>', '<CANARY_CREDENTIAL>')
    }
    $providers = New-CddsiFakeProviderSet -ExpectedCalls $ExpectedCalls -FailureInjections $FailureInjections
    return New-CddsiExecutionContext -RunId $RunId -Mode $Mode -Stage Scaffold -EnvironmentTier HostSandbox -SandboxRoot $SandboxRoot -Paths $paths -Providers $providers -Policy $policy -AccessLedger (New-CddsiAccessLedger)
}
