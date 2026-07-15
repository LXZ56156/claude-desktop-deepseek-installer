BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\common.ps1')
    . (Join-Path $script:RepoRoot 'lib\execution-context.ps1')
    . (Join-Path $script:RepoRoot 'lib\fake-providers.ps1')

    function New-FakeProviderTestContext {
        param(
            [object[]]$ExpectedCalls = @(),
            [object[]]$FailureInjections = @()
        )

        $root = 'C:\P1 Tests\cddsi-test-00000000-0000-0000-0000-000000000002'
        $paths = [ordered]@{
            Home         = Join-Path $root 'profile'
            UserProfile  = Join-Path $root 'profile'
            LocalAppData = Join-Path $root 'local-app-data'
            AppData      = Join-Path $root 'app-data'
            ProgramData  = Join-Path $root 'program-data'
            Temp         = Join-Path $root 'temp'
            Download     = Join-Path $root 'download'
            State        = Join-Path $root 'state'
            Backup       = Join-Path $root 'backup'
            Report       = Join-Path $root 'report'
            Credential   = Join-Path $root 'credential'
            ConfigLibrary = Join-Path $root 'config-library'
            GitGlobalConfig = Join-Path $root 'git-global-config'
            XdgConfig    = Join-Path $root 'xdg-config'
            XdgData      = Join-Path $root 'xdg-data'
        }
        $policy = [ordered]@{
            SchemaVersion            = 1
            AllowLiveProvider        = $false
            ForbiddenResourceTokens = @('<CLAUDE_SETTINGS>', '<GIT_GLOBAL_CONFIG>')
            CanaryTokens             = @('<CANARY:CLAUDE_SETTINGS>', '<CANARY:GIT_CONFIG>')
        }
        return New-CddsiExecutionContext `
            -RunId '00000000-0000-0000-0000-000000000002' `
            -Mode TestSafe `
            -EnvironmentTier HostSandbox `
            -SandboxRoot $root `
            -Paths $paths `
            -Providers (New-CddsiFakeProviderSet -ExpectedCalls $ExpectedCalls -FailureInjections $FailureInjections) `
            -Policy $policy
    }
}

Describe 'P1 fake provider behavior' {
    It 'compares empty collections and argument dictionaries exactly' {
        (Test-CddsiFakeValueEqual -Expected @() -Actual @()) | Should -BeTrue
        (Test-CddsiFakeValueEqual -Expected ([ordered]@{}) -Actual ([ordered]@{})) | Should -BeTrue
        (Test-CddsiExactNameSet -Actual @() -Expected @()) | Should -BeTrue
    }

    It 'default-denies undeclared calls and records only safe product-ledger metadata' {
        $context = New-FakeProviderTestContext
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem -Operation ReadFile -ResourceToken '<STATE_ROOT>/state.json'
        } | Should -Throw '*default-denied*'
        $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 1
        $context.AccessLedger.UnexpectedEntryCount | Should -Be 1
        $context.AccessLedger.Entries.Count | Should -Be 1
        $context.AccessLedger.Entries[0].Allowed | Should -BeFalse
        $context.AccessLedger.Entries[0].ResourceToken | Should -BeExactly '<STATE_ROOT>/state.json'
        $context.AccessLedger.Entries[0].PSObject.Properties.Name | Should -Not -Contain 'Arguments'

        $mutationContext = New-FakeProviderTestContext
        {
            Invoke-CddsiProviderOperation -ExecutionContext $mutationContext -Provider Process -Operation Start -ResourceToken '<PROCESS:CLAUDE_DESKTOP>'
        } | Should -Throw '*default-denied*'
        $mutationContext.Providers.MutationSpy.Count | Should -Be 1
        $mutationContext.AccessLedger.Entries[0].IsMutation | Should -BeTrue
    }

    It 'enforces one exact sequence across different provider categories' {
        $expected = @(
            [pscustomobject]@{ Provider = 'Environment'; Operation = 'GetVariable'; ResourceToken = '<ENV:HOME>'; Result = 'synthetic-home' },
            [pscustomobject]@{ Provider = 'Clock'; Operation = 'UtcNow'; ResourceToken = '<CLOCK:UTC>'; Result = '2030-01-01T00:00:00.0000000Z' }
        )
        $wrongOrder = New-FakeProviderTestContext -ExpectedCalls $expected
        {
            Invoke-CddsiProviderOperation -ExecutionContext $wrongOrder -Provider Clock -Operation UtcNow -ResourceToken '<CLOCK:UTC>'
        } | Should -Throw '*next exact expected call*'
        $wrongOrder.Providers.Cursor | Should -Be 0

        $context = New-FakeProviderTestContext -ExpectedCalls $expected
        (Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Environment -Operation GetVariable -ResourceToken '<ENV:HOME>') | Should -BeExactly 'synthetic-home'
        (Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Clock -Operation UtcNow -ResourceToken '<CLOCK:UTC>') | Should -BeExactly '2030-01-01T00:00:00.0000000Z'
        (Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations) | Should -BeTrue
    }

    It 'compares expected arguments exactly while ignoring dictionary insertion order' {
        $expected = @(
            [pscustomobject]@{
                Provider = 'Environment'
                Operation = 'GetVariable'
                ResourceToken = '<ENV:HOME>'
                Arguments = [ordered]@{ Name = 'HOME'; Required = $true }
                Result = 'synthetic-home'
            }
        )
        $context = New-FakeProviderTestContext -ExpectedCalls $expected
        $actualArguments = [ordered]@{ Required = $true; Name = 'HOME' }
        (Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Environment -Operation GetVariable -ResourceToken '<ENV:HOME>' -Arguments $actualArguments) | Should -BeExactly 'synthetic-home'

        $context = New-FakeProviderTestContext -ExpectedCalls $expected
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Environment -Operation GetVariable -ResourceToken '<ENV:HOME>' -Arguments ([ordered]@{ Name = 'HOME'; Required = $false })
        } | Should -Throw '*next exact expected call*'
    }

    It 'injects a deterministic failure after consuming the declared call' {
        $expected = @(
            [pscustomobject]@{ Provider = 'Network'; Operation = 'Inspect'; ResourceToken = '<NETWORK:FAKE_ENDPOINT>'; Result = $null }
        )
        $failures = @(
            [pscustomobject]@{ Sequence = 1; ErrorCode = 'synthetic_failure'; MessageSafe = 'Synthetic transport failure.' }
        )
        $context = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failures
        $message = ''
        try {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Network -Operation Inspect -ResourceToken '<NETWORK:FAKE_ENDPOINT>'
        }
        catch {
            $message = $_.Exception.Message
        }
        $message | Should -Match 'synthetic_failure'
        $context.Providers.Cursor | Should -Be 1
        $context.AccessLedger.Entries[0].FailureInjected | Should -BeTrue
        $context.AccessLedger.Entries[0].Outcome | Should -BeExactly 'InjectedFailure'
        (Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations) | Should -BeTrue
    }

    It 'rejects credential material in injected failure messages' {
        $expected = @(
            [pscustomobject]@{ Provider = 'Network'; Operation = 'Inspect'; ResourceToken = '<NETWORK:FAKE_ENDPOINT>'; Result = $null }
        )
        $secret = 'sk-' + ('x' * 32 -join '')
        {
            New-CddsiFakeProviderSet -ExpectedCalls $expected -FailureInjections @(
                [pscustomobject]@{ Sequence = 1; ErrorCode = 'synthetic_failure'; MessageSafe = $secret }
            )
        } | Should -Throw '*credential*'
    }

    It 'records every attempted mutation in the mutation spy' {
        $expected = @(
            [pscustomobject]@{ Provider = 'FileSystem'; Operation = 'WriteFile'; ResourceToken = '<STATE_ROOT>/state.json'; Result = $null }
        )
        $context = New-FakeProviderTestContext -ExpectedCalls $expected
        { Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem -Operation WriteFile -ResourceToken '<STATE_ROOT>/state.json' } | Should -Not -Throw
        $context.Providers.MutationSpy.Count | Should -Be 1
        $context.Providers.MutationSpy[0].Operation | Should -BeExactly 'WriteFile'
        { Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations } | Should -Throw '*mutation spy*'
        (Get-CddsiIsolationEvidence -ExecutionContext $context).UNEXPECTED_LEDGER_ENTRY_COUNT | Should -Be 1
    }

    It 'denies synthetic canaries even when a scenario tries to allow them' {
        $expected = @(
            [pscustomobject]@{ Provider = 'FileSystem'; Operation = 'ReadFile'; ResourceToken = '<CANARY:CLAUDE_SETTINGS>'; Result = 'never-returned' }
        )
        $context = New-FakeProviderTestContext -ExpectedCalls $expected
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem -Operation ReadFile -ResourceToken '<CANARY:CLAUDE_SETTINGS>'
        } | Should -Throw '*forbidden*'
        $context.Providers.Cursor | Should -Be 0
        $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 1
    }

    It 'denies descendants of protected logical resource tokens' {
        foreach ($token in @('<CLAUDE_SETTINGS>/nested.json', '<CANARY:GIT_CONFIG>\nested')) {
            $context = New-FakeProviderTestContext
            {
                Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem -Operation ReadFile -ResourceToken $token
            } | Should -Throw '*forbidden*'
            $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 1
            $context.Providers.Cursor | Should -Be 0
        }
    }

    It 'routes all ten provider categories without dynamic handlers' {
        $providers = @('FileSystem', 'Environment', 'Registry', 'Process', 'Network', 'Package', 'Feature', 'Service', 'Credential', 'Clock')
        $expected = @()
        foreach ($provider in $providers) {
            $operation = if ($provider -ceq 'Clock') { 'UtcNow' } else { 'Inspect' }
            $expected += [pscustomobject]@{
                Provider = $provider
                Operation = $operation
                ResourceToken = ("<PROVIDER:{0}>" -f $provider.ToUpperInvariant())
                Result = $provider
            }
        }
        $context = New-FakeProviderTestContext -ExpectedCalls $expected
        foreach ($provider in $providers) {
            $operation = if ($provider -ceq 'Clock') { 'UtcNow' } else { 'Inspect' }
            $token = "<PROVIDER:{0}>" -f $provider.ToUpperInvariant()
            (Invoke-CddsiProviderOperation -ExecutionContext $context -Provider $provider -Operation $operation -ResourceToken $token) | Should -BeExactly $provider
        }
        (Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations) | Should -BeTrue
    }
}
