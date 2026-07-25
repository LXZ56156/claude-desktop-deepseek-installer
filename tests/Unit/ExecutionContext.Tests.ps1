BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\execution-context.ps1')
    . (Join-Path $script:RepoRoot 'lib\fake-providers.ps1')

    function New-ExecutionContextTestPaths {
        param(
            [string]$SandboxRoot = 'C:\Synthetic Temp\cddsi-test-00000000-0000-0000-0000-000000000001'
        )

        return [ordered]@{
            Home         = Join-Path $SandboxRoot 'profile'
            UserProfile  = Join-Path $SandboxRoot 'profile'
            LocalAppData = Join-Path $SandboxRoot 'local-app-data'
            AppData      = Join-Path $SandboxRoot 'app-data'
            ProgramData  = Join-Path $SandboxRoot 'program-data'
            Temp         = Join-Path $SandboxRoot 'temp'
            Download     = Join-Path $SandboxRoot 'download'
            State        = Join-Path $SandboxRoot 'state'
            Backup       = Join-Path $SandboxRoot 'backup'
            Report       = Join-Path $SandboxRoot 'report'
            Credential   = Join-Path $SandboxRoot 'credential'
            ConfigLibrary = Join-Path $SandboxRoot 'config-library'
            GitGlobalConfig = Join-Path $SandboxRoot 'git-global-config'
            XdgConfig    = Join-Path $SandboxRoot 'xdg-config'
            XdgData      = Join-Path $SandboxRoot 'xdg-data'
        }
    }

    function New-ExecutionContextTestPolicy {
        param([bool]$AllowLiveProvider = $false)

        return [ordered]@{
            SchemaVersion            = 1
            AllowLiveProvider        = $AllowLiveProvider
            ForbiddenResourceTokens = @('<CLAUDE_SETTINGS>', '<GIT_GLOBAL_CONFIG>')
            CanaryTokens             = @('<CANARY:CLAUDE_SETTINGS>', '<CANARY:GIT_CONFIG>')
        }
    }

    function New-ExecutionContextFixture {
        param(
            [ValidateSet('TestSafe', 'DryRun', 'Live')]
            [string]$Mode = 'TestSafe',
            [ValidateSet('Scaffold', 'Development', 'VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive')]
            [string]$Stage = 'Scaffold',
            [ValidateSet('HostSandbox', 'CI', 'VmDevelopment', 'VmAcceptance', 'UserLive')]
            [string]$EnvironmentTier = 'HostSandbox',
            [AllowNull()]$Providers = $null,
            [bool]$AllowLiveProvider = $false,
            [string]$SandboxRoot = 'C:\Synthetic Temp\cddsi-test-00000000-0000-0000-0000-000000000001'
        )

        if ($null -eq $Providers) {
            $Providers = New-CddsiFakeProviderSet
        }
        return New-CddsiExecutionContext `
            -RunId '00000000-0000-0000-0000-000000000001' `
            -Mode $Mode `
            -Stage $Stage `
            -EnvironmentTier $EnvironmentTier `
            -SandboxRoot $SandboxRoot `
            -Paths (New-ExecutionContextTestPaths -SandboxRoot $SandboxRoot) `
            -Providers $Providers `
            -Policy (New-ExecutionContextTestPolicy -AllowLiveProvider $AllowLiveProvider)
    }
}

Describe 'P1 execution context contract' {
    It 'creates and validates the exact top-level schema' {
        $context = New-ExecutionContextFixture
        @($context.PSObject.Properties.Name) | Should -Be @(
            'SchemaVersion',
            'RunId',
            'Mode',
            'Stage',
            'EnvironmentTier',
            'SandboxRoot',
            'Paths',
            'Providers',
            'Policy',
            'AccessLedger'
        )
        $context.SchemaVersion | Should -Be 2
        $context.Stage | Should -BeExactly 'Scaffold'
        @($context.Paths.PSObject.Properties.Name) | Should -Be @(
            'Home', 'UserProfile', 'LocalAppData', 'AppData', 'ProgramData',
            'Temp', 'Download', 'State', 'Backup', 'Report', 'Credential',
            'ConfigLibrary', 'GitGlobalConfig', 'XdgConfig', 'XdgData'
        )
        (Assert-CddsiExecutionContext -ExecutionContext $context -ExpectedMode TestSafe) | Should -BeTrue
    }

    It 'defines exactly ten non-live fake providers' {
        $context = New-ExecutionContextFixture
        $names = @('FileSystem', 'Environment', 'Registry', 'Process', 'Network', 'Package', 'Feature', 'Service', 'Credential', 'Clock')
        foreach ($name in $names) {
            $context.Providers.$name.Name | Should -BeExactly $name
            $context.Providers.$name.Kind | Should -BeExactly 'Fake'
            $context.Providers.$name.IsLive | Should -BeFalse
        }
        $names.Count | Should -Be 10
    }

    It 'defines an exact non-executable unloaded provider set' {
        $providers = New-CddsiUnloadedProviderSet
        $providers.Kind | Should -BeExactly 'Unloaded'
        @($providers.ExpectedCalls).Count | Should -Be 0
        @($providers.FailureInjections).Count | Should -Be 0
        $providers.Cursor | Should -Be 0
        @($providers.MutationSpy).Count | Should -Be 0
        foreach ($name in @('FileSystem', 'Environment', 'Registry', 'Process', 'Network', 'Package', 'Feature', 'Service', 'Credential', 'Clock')) {
            $providers.$name.Name | Should -BeExactly $name
            $providers.$name.Kind | Should -BeExactly 'Unloaded'
            $providers.$name.IsLive | Should -BeFalse
        }
    }

    It 'creates an exact in-memory product AccessLedger' {
        $ledger = New-CddsiAccessLedger
        @($ledger.PSObject.Properties.Name) | Should -Be @(
            'SchemaVersion',
            'Plane',
            'Entries',
            'UnexpectedEntryCount',
            'ForbiddenResourceAccessCount',
            'OutsideSandboxWriteCount',
            'ProductLiveProcessSpawnCount',
            'ProductNetworkRequestCount',
            'RealRegistryAccessCount',
            'LiveProviderLoaded'
        )
        $ledger.Plane | Should -BeExactly 'Product'
        $ledger.Entries.Count | Should -Be 0
        $ledger.LiveProviderLoaded | Should -BeFalse
    }

    It 'returns only synthetic report path-token values' {
        $context = New-ExecutionContextFixture
        $tokens = Get-CddsiExecutionPathTokenValues -ExecutionContext $context
        @($tokens.Keys) | Should -Be @('%LOCALAPPDATA%', '%USERPROFILE%', '%USERNAME%', '%TEMP%')
        $tokens['%LOCALAPPDATA%'] | Should -BeExactly $context.Paths.LocalAppData
        $tokens['%USERPROFILE%'] | Should -BeExactly $context.Paths.UserProfile
        $tokens['%USERNAME%'] | Should -BeExactly 'SyntheticUser'
        $tokens['%TEMP%'] | Should -BeExactly $context.Paths.Temp
    }

    It 'rejects extra context fields and missing provider fields' {
        $context = New-ExecutionContextFixture
        $context | Add-Member -NotePropertyName Unexpected -NotePropertyValue $true
        { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw

        $context = New-ExecutionContextFixture
        $context.Providers.PSObject.Properties.Remove('Service')
        { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw
    }

    It 'requires a canonical lowercase context run identifier' {
        $context = New-ExecutionContextFixture
        $context.RunId = 'ABCDEFAB-0000-4000-8000-000000000001'
        { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw
    }

    It 'rejects mode mismatch and allows only unloaded exact-pair Live contexts' {
        $context = New-ExecutionContextFixture -Mode DryRun
        { Assert-CddsiExecutionContext -ExecutionContext $context -ExpectedMode TestSafe } | Should -Throw

        foreach ($binding in @(
            @{ Stage = 'VmDevelopment'; EnvironmentTier = 'VmDevelopment' },
            @{ Stage = 'VmAcceptance'; EnvironmentTier = 'VmAcceptance' },
            @{ Stage = 'UserLive'; EnvironmentTier = 'UserLive' }
        )) {
            $liveContext = New-ExecutionContextFixture -Mode Live -Stage $binding.Stage `
                -EnvironmentTier $binding.EnvironmentTier -Providers (New-CddsiUnloadedProviderSet) `
                -AllowLiveProvider $true
            (Assert-CddsiExecutionContext -ExecutionContext $liveContext -ExpectedMode Live) | Should -BeTrue
            $liveContext.AccessLedger.LiveProviderLoaded | Should -BeFalse
            {
                Invoke-CddsiProviderOperation -ExecutionContext $liveContext -Provider Environment `
                    -Operation Inspect -ResourceToken '<ENVIRONMENT>'
            } | Should -Throw '*LIVE_PROVIDER_NOT_LOADED*'
        }

        { New-ExecutionContextFixture -Mode Live } | Should -Throw
        foreach ($forbiddenTier in @('HostSandbox', 'CI')) {
            {
                New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier $forbiddenTier `
                    -Providers (New-CddsiUnloadedProviderSet) -AllowLiveProvider $true
            } | Should -Throw
        }
        {
            New-ExecutionContextFixture -Mode Live -Stage VmAcceptance -EnvironmentTier VmDevelopment `
                -Providers (New-CddsiUnloadedProviderSet) -AllowLiveProvider $true
        } | Should -Throw
        {
            New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier VmDevelopment `
                -Providers (New-CddsiFakeProviderSet) -AllowLiveProvider $true
        } | Should -Throw
        {
            New-ExecutionContextFixture -Mode TestSafe -Stage VmDevelopment -EnvironmentTier VmDevelopment `
                -Providers (New-CddsiUnloadedProviderSet) -AllowLiveProvider $true
        } | Should -Throw
    }

    It 'rejects paths outside SandboxRoot' {
        $root = 'C:\Synthetic Temp\cddsi-test-00000000-0000-0000-0000-000000000001'
        $paths = New-ExecutionContextTestPaths -SandboxRoot $root
        $paths.Report = 'C:\Outside\report'
        {
            New-CddsiExecutionContext `
                -RunId '00000000-0000-0000-0000-000000000001' `
                -Mode TestSafe `
                -Stage Scaffold `
                -EnvironmentTier HostSandbox `
                -SandboxRoot $root `
                -Paths $paths `
                -Providers (New-CddsiFakeProviderSet) `
                -Policy (New-ExecutionContextTestPolicy)
        } | Should -Throw
    }

    It 'rejects non-logical policy tokens' {
        $policy = New-ExecutionContextTestPolicy
        $policy.CanaryTokens = @('C:\Users\real-user\.claude\settings.json')
        {
            New-CddsiExecutionContext `
                -RunId '00000000-0000-0000-0000-000000000001' `
                -Mode TestSafe `
                -Stage Scaffold `
                -EnvironmentTier HostSandbox `
                -SandboxRoot 'C:\Synthetic Temp\cddsi-test-00000000-0000-0000-0000-000000000001' `
                -Paths (New-ExecutionContextTestPaths) `
                -Providers (New-CddsiFakeProviderSet) `
                -Policy $policy
        } | Should -Throw
    }

    It 'requires non-empty, globally unique protected token collections' {
        $root = 'C:\Synthetic Temp\cddsi-test-00000000-0000-0000-0000-000000000001'
        foreach ($policy in @(
            [ordered]@{ SchemaVersion = 1; AllowLiveProvider = $false; ForbiddenResourceTokens = @(); CanaryTokens = @('<CANARY:GIT_CONFIG>') },
            [ordered]@{ SchemaVersion = 1; AllowLiveProvider = $false; ForbiddenResourceTokens = @('<DUPLICATE>'); CanaryTokens = @('<DUPLICATE>') }
        )) {
            {
                New-CddsiExecutionContext `
                    -RunId '00000000-0000-0000-0000-000000000001' `
                    -Mode TestSafe `
                    -Stage Scaffold `
                    -EnvironmentTier HostSandbox `
                    -SandboxRoot $root `
                    -Paths (New-ExecutionContextTestPaths -SandboxRoot $root) `
                    -Providers (New-CddsiFakeProviderSet) `
                    -Policy $policy
            } | Should -Throw
        }
    }
}
