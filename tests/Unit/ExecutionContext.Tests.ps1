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
        $initialProviders = if ($Providers.Kind -ceq 'LiveReadOnly') {
            New-CddsiUnloadedProviderSet
        }
        else {
            $Providers
        }
        $context = New-CddsiExecutionContext `
            -RunId '00000000-0000-0000-0000-000000000001' `
            -Mode $Mode `
            -Stage $Stage `
            -EnvironmentTier $EnvironmentTier `
            -SandboxRoot $SandboxRoot `
            -Paths (New-ExecutionContextTestPaths -SandboxRoot $SandboxRoot) `
            -Providers $initialProviders `
            -Policy (New-ExecutionContextTestPolicy -AllowLiveProvider $AllowLiveProvider)
        if ($Providers.Kind -ceq 'LiveReadOnly') {
            $context.Providers = $Providers
            $context.AccessLedger.LiveProviderLoaded = $true
            Assert-CddsiExecutionContext -ExecutionContext $context -ExpectedMode Live | Out-Null
        }
        return $context
    }

    function New-LiveReadOnlyProviderSetFixture {
        param(
            [ValidateSet('VmDevelopment', 'VmAcceptance', 'UserLive')]
            [string]$Stage = 'VmDevelopment'
        )

        return New-CddsiLiveReadOnlyProviderSet `
            -RunId '00000000-0000-0000-0000-000000000001' `
            -Stage $Stage `
            -EnvironmentTier $Stage `
            -ArtifactProfile $Stage `
            -AdapterSha256 ('a' * 64) `
            -LoadOperationUseId '00000000-0000-4000-8000-000000000011' `
            -LoadReceiptBindingToken ('b' * 64)
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

    It 'never permits an Unloaded provider set to acquire any ledger entry' {
        $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
            -EnvironmentTier VmDevelopment -Providers (New-CddsiUnloadedProviderSet) `
            -AllowLiveProvider $true
        $before = $context | ConvertTo-Json -Depth 20 -Compress
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                -Allowed $false -Expected $false -IsMutation $false `
                -FailureInjected $false -Outcome Denied `
                -ErrorCode 'LIVE_READ_ONLY_RESOURCE_DENIED'
        } | Should -Throw '*must never contain*'
        ($context | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly $before

        [void]$context.AccessLedger.Entries.Add([pscustomobject][ordered]@{
            Sequence = 1; Plane = 'Product'; Provider = 'Environment'; Operation = 'Inspect'
            ResourceToken = '<ENVIRONMENT:WINDOWS>'; ArgumentCount = 0
            Allowed = $false; Expected = $false; IsMutation = $false; FailureInjected = $false
            Outcome = 'Denied'; ErrorCode = 'LIVE_READ_ONLY_RESOURCE_DENIED'
            ProviderEvidenceDigest = $null; InvocationBindingToken = $null
        })
        { Assert-CddsiExecutionContext -ExecutionContext $context } |
            Should -Throw '*must never contain*'
    }

    It 'defines the exact bound LiveReadOnly provider schema and eleven capabilities' {
        $providers = New-LiveReadOnlyProviderSetFixture
        @($providers.PSObject.Properties.Name) | Should -Be @(
            'SchemaVersion', 'Kind', 'RunId', 'Stage', 'EnvironmentTier', 'ArtifactProfile',
            'AdapterSha256', 'LoadOperationUseId', 'LoadReceiptBindingToken', 'CapabilitySetDigest',
            'FileSystem', 'Environment', 'Registry', 'Process', 'Network', 'Package', 'Feature',
            'Service', 'Credential', 'Clock'
        )
        $providers.SchemaVersion | Should -Be 2
        $providers.Kind | Should -BeExactly 'LiveReadOnly'
        $providers.CapabilitySetDigest |
            Should -BeExactly '26c9e8d095c7570df019d1758d277d6bc6b6161d88695f2b96f3350dcc4e942e'
        @($providers.PSObject.Properties.Name) | Should -Not -Contain 'ExpectedCalls'
        @($providers.PSObject.Properties.Name) | Should -Not -Contain 'Capabilities'

        [string[]]$actualCapabilityLines = @()
        foreach ($providerName in @(
            'FileSystem', 'Environment', 'Registry', 'Process', 'Network',
            'Package', 'Feature', 'Service', 'Credential', 'Clock'
        )) {
            $provider = $providers.$providerName
            @($provider.PSObject.Properties.Name) | Should -Be @(
                'SchemaVersion', 'Name', 'Kind', 'IsLive', 'Access', 'Capabilities'
            )
            $provider.SchemaVersion | Should -Be 2
            $provider.Kind | Should -BeExactly 'LiveReadOnly'
            $provider.IsLive | Should -BeTrue
            $provider.Access | Should -BeExactly 'ReadOnly'
            foreach ($capability in @($provider.Capabilities)) {
                @($capability.PSObject.Properties.Name) | Should -Be @(
                    'SchemaVersion', 'Operation', 'ResourceToken', 'ArgumentNames', 'ResultSchemaId'
                )
                $capability.SchemaVersion | Should -Be 1
                $capability.ArgumentNames -is [System.Array] | Should -BeTrue
                @($capability.ArgumentNames).Count | Should -Be 0
                $actualCapabilityLines += '{0}|{1}|{2}|{3}|{4}' -f $providerName,
                    $capability.Operation, $capability.ResourceToken,
                    (@($capability.ArgumentNames) -join ','), $capability.ResultSchemaId
            }
        }
        $actualCapabilityLines.Count | Should -Be 11
        [string[]]$expectedCapabilityLines = @(
            'Environment|Inspect|<ENVIRONMENT:WINDOWS>||WindowsEnvironmentObservation/v1',
            'Environment|Inspect|<ENVIRONMENT:HARDWARE_VIRTUALIZATION>||HardwareVirtualizationObservation/v1',
            'Environment|Inspect|<KNOWN_FOLDERS:CURRENT_USER>||CurrentUserKnownFoldersObservation/v1',
            'Package|Inspect|<PACKAGE:CLAUDE_DESKTOP>||ClaudeDesktopPackageInventory/v1',
            'Process|Inspect|<PROCESS:GIT_FOR_WINDOWS>||GitForWindowsInventory/v2',
            'Feature|Inspect|<FEATURE:VIRTUAL_MACHINE_PLATFORM>||VirtualMachinePlatformObservation/v1',
            'Service|Inspect|<SERVICE:COWORK>||CoworkServiceObservation/v1',
            'Registry|Inspect|<HKLM_MANAGED_POLICY>||ClaudeConfigSourceMetadata/v1',
            'Registry|Inspect|<HKCU_MANAGED_POLICY>||ClaudeConfigSourceMetadata/v1',
            'FileSystem|Inspect|<CONFIG_LIBRARY>||ClaudeConfigSourceMetadata/v1',
            'Process|Inspect|<PROCESS:CLAUDE_DESKTOP>||ClaudeDesktopProcessInventory/v1'
        )
        [System.Array]::Sort($actualCapabilityLines, [System.StringComparer]::Ordinal)
        [System.Array]::Sort($expectedCapabilityLines, [System.StringComparer]::Ordinal)
        $actualCapabilityLines | Should -Be $expectedCapabilityLines

        $utf8 = [System.Text.UTF8Encoding]::new($false)
        $sha256 = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actualDigest = [System.BitConverter]::ToString(
                $sha256.ComputeHash($utf8.GetBytes(($actualCapabilityLines -join "`n")))
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha256.Dispose()
        }
        $actualDigest | Should -BeExactly $providers.CapabilitySetDigest
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

    It 'accepts transactionally loaded LiveReadOnly contexts and binds ledger state exactly' {
        foreach ($stage in @('VmDevelopment', 'VmAcceptance', 'UserLive')) {
            $context = New-ExecutionContextFixture -Mode Live -Stage $stage -EnvironmentTier $stage `
                -Providers (New-LiveReadOnlyProviderSetFixture -Stage $stage) -AllowLiveProvider $true
            (Assert-CddsiExecutionContext -ExecutionContext $context -ExpectedMode Live) | Should -BeTrue
            $context.AccessLedger.LiveProviderLoaded | Should -BeTrue
            (Get-CddsiIsolationEvidence -ExecutionContext $context).LIVE_PROVIDER_LOADED | Should -BeTrue
        }
    }

    It 'requires every freshly constructed Live context to start Unloaded' {
        $providers = New-LiveReadOnlyProviderSetFixture
        {
            New-CddsiExecutionContext `
                -RunId '00000000-0000-0000-0000-000000000001' `
                -Mode Live `
                -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment `
                -SandboxRoot 'C:\Synthetic Temp\cddsi-test-00000000-0000-0000-0000-000000000001' `
                -Paths (New-ExecutionContextTestPaths) `
                -Providers $providers `
                -Policy (New-ExecutionContextTestPolicy -AllowLiveProvider $true)
        } | Should -Throw '*must start with the Unloaded provider set*'
    }

    It 'rejects tampered LiveReadOnly bindings and capabilities' {
        foreach ($mutation in @(
            { param($providerSet) $providerSet.Kind = 'livereadonly' },
            { param($providerSet) $providerSet.RunId = '00000000-0000-4000-8000-000000000099' },
            { param($providerSet) $providerSet.AdapterSha256 = 'A' * 64 },
            { param($providerSet) $providerSet.CapabilitySetDigest = 'c' * 64 },
            { param($providerSet) $providerSet.Environment.Capabilities[0].ResourceToken = '<ENVIRONMENT:OTHER>' },
            { param($providerSet) $providerSet.Process.Capabilities[0].ResultSchemaId = 'GitForWindowsInventory/v1' },
            { param($providerSet) $providerSet.Network.Capabilities = @([pscustomobject]@{
                SchemaVersion = 1; Operation = 'Inspect'; ResourceToken = '<NETWORK:OTHER>'
                ArgumentNames = @(); ResultSchemaId = 'NetworkObservation/v1'
            }) }
        )) {
            $providers = New-LiveReadOnlyProviderSetFixture
            & $mutation $providers
            {
                New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier VmDevelopment `
                    -Providers $providers -AllowLiveProvider $true
            } | Should -Throw
        }
    }

    It 'ignores mutable legacy capability state and binds actual capabilities to the fixed digest' {
        $script:CddsiLiveReadOnlyCapabilities = @(
            [pscustomobject][ordered]@{
                Provider = 'Network'; Operation = 'Inspect'; ResourceToken = '<NETWORK:FORGED>'
                ArgumentNames = @(); ResultSchemaId = 'ForgedObservation/v1'
            }
        )
        try {
            $providers = New-LiveReadOnlyProviderSetFixture
            $providers.CapabilitySetDigest |
                Should -BeExactly '26c9e8d095c7570df019d1758d277d6bc6b6161d88695f2b96f3350dcc4e942e'
            @($providers.Network.Capabilities).Count | Should -Be 0

            $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment -Providers $providers `
                -AllowLiveProvider $true
            $context.Providers.Environment.Capabilities[0].ResourceToken = '<NETWORK:FORGED>'
            { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw
        }
        finally {
            Remove-Variable -Name CddsiLiveReadOnlyCapabilities -Scope Script -ErrorAction SilentlyContinue
        }
    }

    It 'fails loaded-provider dispatch closed without invoking an ambient same-named function' {
        $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier VmDevelopment `
            -Providers (New-LiveReadOnlyProviderSetFixture) -AllowLiveProvider $true
        $before = $context | ConvertTo-Json -Depth 20 -Compress
        $script:AmbientLiveAdapterInvoked = $false
        function Invoke-CddsiLiveReadOnlyProviderOperation {
            param([Alias('ExecutionContext')]$Context, $Provider, $Operation, $ResourceToken, $Arguments)
            $script:AmbientLiveAdapterInvoked = $true
            throw 'AMBIENT_ADAPTER_MUST_NOT_RUN'
        }
        try {
            {
                Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Environment `
                    -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>'
            } | Should -Throw '*LIVE_READ_ONLY_ADAPTER_SOURCE_UNBOUND*'
        }
        finally {
            Remove-Item -LiteralPath 'Function:\Invoke-CddsiLiveReadOnlyProviderOperation' -ErrorAction SilentlyContinue
        }

        $script:AmbientLiveAdapterInvoked | Should -BeFalse
        ($context | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly $before
        $context.AccessLedger.Entries.Count | Should -Be 0
        $context.AccessLedger.UnexpectedEntryCount | Should -Be 0
        $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 0
        (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue
    }

    It 'enforces exact access-ledger outcome and evidence combinations' {
        $fakeContext = New-ExecutionContextFixture
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $fakeContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $false -FailureInjected $false -Outcome Allowed -ProviderEvidenceDigest ('a' * 64)
        } | Should -Throw
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $fakeContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $false -FailureInjected $false -Outcome ProviderFailure -ErrorCode 'provider_failed'
        } | Should -Throw '*ProviderFailure*'

        $liveContext = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier VmDevelopment `
            -Providers (New-LiveReadOnlyProviderSetFixture) -AllowLiveProvider $true
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $liveContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $false -FailureInjected $false -Outcome Allowed
        } | Should -Throw '*Allowed is forbidden*'
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $liveContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $true -FailureInjected $false -Outcome Allowed -ProviderEvidenceDigest ('a' * 64)
        } | Should -Throw
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $liveContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $false -FailureInjected $false -Outcome ProviderFailure `
                -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED' `
                -ProviderEvidenceDigest ('a' * 64)
        } | Should -Throw '*ProviderFailure*'
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $liveContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $false -FailureInjected $false -Outcome ProviderFailure `
                -ErrorCode 'provider_failed'
        } | Should -Throw '*ProviderFailure*'

        $failureEntry = Add-CddsiProductAccessLedgerEntry -ExecutionContext $liveContext -Provider Environment `
            -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
            -IsMutation $false -FailureInjected $false -Outcome ProviderFailure `
            -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        $failureEntry.ProviderEvidenceDigest | Should -BeNullOrEmpty
        $failureEntry.ErrorCode | Should -BeExactly 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        (Assert-CddsiExecutionContext -ExecutionContext $liveContext) | Should -BeTrue

        $successContext = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier VmDevelopment `
            -Providers (New-LiveReadOnlyProviderSetFixture) -AllowLiveProvider $true
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $successContext -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Allowed $true -Expected $true `
                -IsMutation $false -FailureInjected $false -Outcome Allowed `
                -ProviderEvidenceDigest ('d' * 64)
        } | Should -Throw '*Allowed is forbidden*'
        $successContext.AccessLedger.Entries.Count | Should -Be 0
        (Assert-CddsiExecutionContext -ExecutionContext $successContext) | Should -BeTrue
    }

    It 'binds every LiveReadOnly denial to its exact branch mutation state and counters' {
        $cases = @(
            [pscustomobject][ordered]@{
                Provider = 'Environment'; Operation = 'Inspect'
                ResourceToken = '<ENVIRONMENT:WINDOWS>'
                Arguments = [ordered]@{ Unexpected = $true }
                IsMutation = $false; ErrorCode = 'LIVE_READ_ONLY_ARGUMENTS_DENIED'
            },
            [pscustomobject][ordered]@{
                Provider = 'Environment'; Operation = 'Inspect'
                ResourceToken = '<ENVIRONMENT:UNKNOWN>'; Arguments = [ordered]@{}
                IsMutation = $false; ErrorCode = 'LIVE_READ_ONLY_RESOURCE_DENIED'
            },
            [pscustomobject][ordered]@{
                Provider = 'Environment'; Operation = 'Inspect'
                ResourceToken = '<PROCESS:GIT_FOR_WINDOWS>'; Arguments = [ordered]@{}
                IsMutation = $false; ErrorCode = 'LIVE_READ_ONLY_CAPABILITY_DENIED'
            },
            [pscustomobject][ordered]@{
                Provider = 'Process'; Operation = 'Start'
                ResourceToken = '<PROCESS:GIT_FOR_WINDOWS>'; Arguments = [ordered]@{}
                IsMutation = $true; ErrorCode = 'LIVE_READ_ONLY_CAPABILITY_DENIED'
            }
        )

        foreach ($case in $cases) {
            $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment -Providers (New-LiveReadOnlyProviderSetFixture) `
                -AllowLiveProvider $true
            $entry = Add-CddsiProductAccessLedgerEntry -ExecutionContext $context `
                -Provider $case.Provider -Operation $case.Operation `
                -ResourceToken $case.ResourceToken -Arguments $case.Arguments `
                -Allowed $false -Expected $false -IsMutation $case.IsMutation `
                -FailureInjected $false -Outcome Denied -ErrorCode $case.ErrorCode
            $entry.ErrorCode | Should -BeExactly $case.ErrorCode
            $entry.IsMutation | Should -Be $case.IsMutation
            $context.AccessLedger.UnexpectedEntryCount | Should -Be 1
            $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 1
            (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue

            $wrongCodeContext = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment -Providers (New-LiveReadOnlyProviderSetFixture) `
                -AllowLiveProvider $true
            $wrongCode = if ($case.ErrorCode -ceq 'LIVE_READ_ONLY_RESOURCE_DENIED') {
                'LIVE_READ_ONLY_CAPABILITY_DENIED'
            }
            else {
                'LIVE_READ_ONLY_RESOURCE_DENIED'
            }
            {
                Add-CddsiProductAccessLedgerEntry -ExecutionContext $wrongCodeContext `
                    -Provider $case.Provider -Operation $case.Operation `
                    -ResourceToken $case.ResourceToken -Arguments $case.Arguments `
                    -Allowed $false -Expected $false -IsMutation $case.IsMutation `
                    -FailureInjected $false -Outcome Denied -ErrorCode $wrongCode
            } | Should -Throw '*exact fail-closed branch*'
            $wrongCodeContext.AccessLedger.Entries.Count | Should -Be 0

            $wrongMutationContext = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment -Providers (New-LiveReadOnlyProviderSetFixture) `
                -AllowLiveProvider $true
            {
                Add-CddsiProductAccessLedgerEntry -ExecutionContext $wrongMutationContext `
                    -Provider $case.Provider -Operation $case.Operation `
                    -ResourceToken $case.ResourceToken -Arguments $case.Arguments `
                    -Allowed $false -Expected $false -IsMutation:(-not $case.IsMutation) `
                    -FailureInjected $false -Outcome Denied -ErrorCode $case.ErrorCode
            } | Should -Throw '*mutation state*'
            $wrongMutationContext.AccessLedger.Entries.Count | Should -Be 0
        }

        foreach ($counterMutation in @(
            { param($ledger) $ledger.UnexpectedEntryCount = 0 },
            { param($ledger) $ledger.UnexpectedEntryCount = 2 },
            { param($ledger) $ledger.ForbiddenResourceAccessCount = 0 },
            { param($ledger) $ledger.ForbiddenResourceAccessCount = 2 }
        )) {
            $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment -Providers (New-LiveReadOnlyProviderSetFixture) `
                -AllowLiveProvider $true
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:UNKNOWN>' `
                -Allowed $false -Expected $false -IsMutation $false -FailureInjected $false `
                -Outcome Denied -ErrorCode 'LIVE_READ_ONLY_RESOURCE_DENIED' | Out-Null
            & $counterMutation $context.AccessLedger
            { Assert-CddsiExecutionContext -ExecutionContext $context } |
                Should -Throw '*denied counters*'
        }
    }

    It 'rejects non-canonical provider names before appending an access-ledger entry' {
        $context = New-ExecutionContextFixture
        foreach ($provider in @('environment', 'ENVIRONMENT', 'Unknown')) {
            {
                Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider $provider `
                    -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                    -Allowed $false -Expected $false -IsMutation $false `
                    -FailureInjected $false -Outcome Denied -ErrorCode 'provider_denied'
            } | Should -Throw '*exact case-sensitive provider name*'
            $context.AccessLedger.Entries.Count | Should -Be 0
        }
        (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue
    }

    It 'requires every LiveReadOnly provider failure to match its exact zero-argument partition tuple' {
        $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment -EnvironmentTier VmDevelopment `
            -Providers (New-LiveReadOnlyProviderSetFixture) -AllowLiveProvider $true

        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Process `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $false `
                -Outcome ProviderFailure -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        } | Should -Throw '*exact LiveReadOnly capability tuple*'
        $context.AccessLedger.Entries.Count | Should -Be 0

        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $false `
                -Outcome ProviderFailure -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        } | Should -Throw '*exact LiveReadOnly capability tuple*'
        $context.AccessLedger.Entries.Count | Should -Be 0

        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                -Arguments ([ordered]@{ Unexpected = $true }) `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $false `
                -Outcome ProviderFailure -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        } | Should -Throw '*ProviderFailure*'
        $context.AccessLedger.Entries.Count | Should -Be 0

        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $false `
                -Outcome ProviderFailure -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        } | Should -Throw '*exact LiveReadOnly capability tuple*'
        $context.AccessLedger.Entries.Count | Should -Be 0

        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'injected_failure'
        } | Should -Throw '*InjectedFailure*'
        $context.AccessLedger.Entries.Count | Should -Be 0
        (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue
    }

    It 'rejects forged LiveReadOnly ledger entries with the same rules used before append' {
        $forgedAllowedContext = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
            -EnvironmentTier VmDevelopment -Providers (New-LiveReadOnlyProviderSetFixture) `
            -AllowLiveProvider $true
        [void]$forgedAllowedContext.AccessLedger.Entries.Add([pscustomobject][ordered]@{
            Sequence = 1; Plane = 'Product'; Provider = 'Environment'; Operation = 'Inspect'
            ResourceToken = '<ENVIRONMENT:WINDOWS>'; ArgumentCount = 0
            Allowed = $true; Expected = $true; IsMutation = $false; FailureInjected = $false
            Outcome = 'Allowed'; ErrorCode = ''; ProviderEvidenceDigest = ('d' * 64)
            InvocationBindingToken = $null
        })
        { Assert-CddsiExecutionContext -ExecutionContext $forgedAllowedContext } |
            Should -Throw '*Allowed is forbidden*'

        foreach ($mutation in @(
            { param($entry) $entry.ArgumentCount = 1 },
            { param($entry) $entry.ResourceToken = '<PROCESS:GIT_FOR_WINDOWS>' },
            { param($entry) $entry.IsMutation = $true },
            { param($entry) $entry.ProviderEvidenceDigest = 'e' * 64 },
            { param($entry) $entry.ErrorCode = 'provider_failed' }
        )) {
            $context = New-ExecutionContextFixture -Mode Live -Stage VmDevelopment `
                -EnvironmentTier VmDevelopment -Providers (New-LiveReadOnlyProviderSetFixture) `
                -AllowLiveProvider $true
            $entry = Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $false `
                -Outcome ProviderFailure -ErrorCode 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
            & $mutation $entry
            { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw
        }
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

    It 'rejects settable ScriptProperty substitutions before invoking their getters' {
        $context = New-ExecutionContextFixture
        $script:ContextGetterInvoked = $false
        $script:ContextSetterInvoked = $false
        $context.PSObject.Properties.Remove('Mode')
        $context | Add-Member -MemberType ScriptProperty -Name Mode -Value {
            $script:ContextGetterInvoked = $true
            'TestSafe'
        } -SecondValue {
            param($value)
            $script:ContextSetterInvoked = $true
        }
        $context.Mode = 'DryRun'
        $script:ContextSetterInvoked | Should -BeTrue
        { Assert-CddsiExecutionContext -ExecutionContext $context } |
            Should -Throw '*NoteProperty*'
        $script:ContextGetterInvoked | Should -BeFalse

        $context = New-ExecutionContextFixture
        $script:LedgerGetterInvoked = $false
        $script:LedgerSetterInvoked = $false
        $context.AccessLedger.PSObject.Properties.Remove('UnexpectedEntryCount')
        $context.AccessLedger | Add-Member -MemberType ScriptProperty `
            -Name UnexpectedEntryCount -Value {
                $script:LedgerGetterInvoked = $true
                0
            } -SecondValue {
                param($value)
                $script:LedgerSetterInvoked = $true
            }
        $context.AccessLedger.UnexpectedEntryCount = 1
        $script:LedgerSetterInvoked | Should -BeTrue
        { Assert-CddsiExecutionContext -ExecutionContext $context } |
            Should -Throw '*NoteProperty*'
        $script:LedgerGetterInvoked | Should -BeFalse

        $context = New-ExecutionContextFixture
        $script:ProviderGetterInvoked = $false
        $script:ProviderSetterInvoked = $false
        $context.Providers.PSObject.Properties.Remove('ExpectedCalls')
        $context.Providers | Add-Member -MemberType ScriptProperty -Name ExpectedCalls -Value {
            $script:ProviderGetterInvoked = $true
            @()
        } -SecondValue {
            param($value)
            $script:ProviderSetterInvoked = $true
        }
        $context.Providers.ExpectedCalls = @()
        $script:ProviderSetterInvoked | Should -BeTrue
        { Assert-CddsiExecutionContext -ExecutionContext $context } |
            Should -Throw '*NoteProperty*'
        $script:ProviderGetterInvoked | Should -BeFalse
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
