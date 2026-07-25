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
            -Stage Scaffold `
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

    It 'creates a recomputable tagged binding over complete typed ordered scenario data' {
        $expected = @(
            [pscustomobject][ordered]@{
                Provider = 'Environment'
                Operation = 'Inspect'
                ResourceToken = '<ENVIRONMENT:WINDOWS>'
                Arguments = [ordered]@{
                    Name = 'HOME'; Required = $true; Count = [int]1; Wide = [long]1
                }
                Result = [pscustomobject][ordered]@{
                    Value = 'synthetic'; Items = @([int]1, [long]2)
                }
            }
        )
        $failures = @(
            [pscustomobject][ordered]@{
                Sequence = 1
                ErrorCode = 'synthetic_failure'
                MessageSafe = 'Synthetic failure.'
            }
        )
        $providers = New-CddsiFakeProviderSet -ExpectedCalls $expected `
            -FailureInjections $failures

        $providers.ScenarioBindingToken | Should -Match '^[a-f0-9]{64}$'
        $providers.ScenarioBindingToken | Should -BeExactly (
            Get-CddsiFakeScenarioBindingToken `
                -ExpectedCalls ([object[]]$providers.ExpectedCalls) `
                -FailureInjections ([object[]]$providers.FailureInjections)
        )
        $providers.ScenarioBindingToken |
            Should -BeExactly 'ef8ae1e898de20e218bf288af730dfd662babe5fe9b65b8ba299a8d53507b93b'
        @($providers.PSObject.Properties.Name) | Should -Contain 'ScenarioBindingToken'
        $providers.PSObject.Properties['ScenarioBindingToken'].MemberType |
            Should -Be ([System.Management.Automation.PSMemberTypes]::NoteProperty)
        $providers.PSObject.Properties['ScenarioBindingToken'].IsSettable | Should -BeTrue
    }

    It 'rejects ordinary complete-scenario deletion rewrite type and order tampering everywhere' {
        $expected = @(
            [pscustomobject][ordered]@{
                Provider = 'Environment'; Operation = 'GetVariable'
                ResourceToken = '<ENV:HOME>'
                Arguments = [ordered]@{ Name = 'HOME'; Required = $true }
                Result = [pscustomobject][ordered]@{ State = 'Present'; Count = [int]1 }
            },
            [pscustomobject][ordered]@{
                Provider = 'Clock'; Operation = 'UtcNow'; ResourceToken = '<CLOCK:UTC>'
                Arguments = [ordered]@{}
                Result = '2030-01-01T00:00:00.0000000Z'
            }
        )
        $failures = @(
            [pscustomobject][ordered]@{
                Sequence = 1; ErrorCode = 'synthetic_first'; MessageSafe = 'First synthetic failure.'
            },
            [pscustomobject][ordered]@{
                Sequence = 2; ErrorCode = 'synthetic_second'; MessageSafe = 'Second synthetic failure.'
            }
        )
        $mutations = @(
            {
                param($context)
                $context.Providers.ExpectedCalls = @($context.Providers.ExpectedCalls[0])
                $context.Providers.FailureInjections = @($context.Providers.FailureInjections[0])
            },
            { param($context) $context.Providers.ExpectedCalls[0].Arguments['Name'] = 'OTHER' },
            {
                param($context)
                $context.Providers.ExpectedCalls[0].Arguments = [ordered]@{
                    Required = $true; Name = 'HOME'
                }
            },
            { param($context) $context.Providers.ExpectedCalls[0].Result.State = 'Rewritten' },
            { param($context) $context.Providers.ExpectedCalls[0].Result.Count = [long]1 },
            {
                param($context)
                $context.Providers.ExpectedCalls = @(
                    $context.Providers.ExpectedCalls[1],
                    $context.Providers.ExpectedCalls[0]
                )
            },
            { param($context) $context.Providers.FailureInjections = @() },
            {
                param($context)
                $context.Providers.FailureInjections = @(
                    $context.Providers.FailureInjections[1],
                    $context.Providers.FailureInjections[0]
                )
            },
            { param($context) $context.Providers.FailureInjections[0].MessageSafe = 'Rewritten synthetic failure.' },
            { param($context) $context.Providers.ScenarioBindingToken = ('f' * 64) }
        )

        foreach ($mutation in $mutations) {
            $context = New-FakeProviderTestContext -ExpectedCalls $expected `
                -FailureInjections $failures
            & $mutation $context
            { Assert-CddsiFakeProviderScenario -ProviderSet $context.Providers } |
                Should -Throw '*ScenarioBindingToken*'
            { Assert-CddsiExecutionContext -ExecutionContext $context } |
                Should -Throw '*ScenarioBindingToken*'
            { Assert-CddsiFakeProviderExpectations -ExecutionContext $context } |
                Should -Throw '*ScenarioBindingToken*'
            { Get-CddsiIsolationEvidence -ExecutionContext $context } |
                Should -Throw '*ScenarioBindingToken*'
        }
    }

    It 'rejects secrets cycles executable getters and unsupported custom objects before serialization' {
        $baseCall = [pscustomobject][ordered]@{
            Provider = 'Environment'; Operation = 'Inspect'
            ResourceToken = '<ENVIRONMENT:WINDOWS>'; Arguments = [ordered]@{}
            Result = $null
        }
        $secret = 'sk-' + ('x' * 32 -join '')
        $secretCall = $baseCall.PSObject.Copy()
        $secretCall.Arguments = [ordered]@{ ApiKey = $secret }
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($secretCall)
        } | Should -Throw '*credential material*'

        $cycle = [ordered]@{}
        $cycle['Self'] = $cycle
        $cycleCall = $baseCall.PSObject.Copy()
        $cycleCall.Result = $cycle
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($cycleCall)
        } | Should -Throw '*cyclic*'

        $script:NestedScenarioGetterInvoked = $false
        $unsafeResult = [pscustomobject][ordered]@{ Safe = 'synthetic' }
        $unsafeResult | Add-Member -MemberType ScriptProperty -Name Computed -Value {
            $script:NestedScenarioGetterInvoked = $true
            'must-not-run'
        } -SecondValue {
            param($value)
        }
        $unsafeCall = $baseCall.PSObject.Copy()
        $unsafeCall.Result = $unsafeResult
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeCall)
        } | Should -Throw '*NoteProperty*'
        $script:NestedScenarioGetterInvoked | Should -BeFalse

        $script:TopLevelScenarioGetterInvoked = $false
        $unsafeTopLevelCall = [pscustomobject][ordered]@{
            Provider = 'Environment'; Operation = 'Inspect'
            ResourceToken = '<ENVIRONMENT:WINDOWS>'; Arguments = [ordered]@{}
        }
        $unsafeTopLevelCall | Add-Member -MemberType ScriptProperty -Name Result -Value {
            $script:TopLevelScenarioGetterInvoked = $true
            'must-not-run'
        } -SecondValue {
            param($value)
        }
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeTopLevelCall)
        } | Should -Throw '*settable NoteProperty*'
        $script:TopLevelScenarioGetterInvoked | Should -BeFalse

        $script:TopLevelScenarioMethodInvoked = $false
        $unsafeTopLevelMethodCall = $baseCall.PSObject.Copy()
        $unsafeTopLevelMethodCall | Add-Member -MemberType ScriptMethod -Name GetType -Value {
            $script:TopLevelScenarioMethodInvoked = $true
            [System.Management.Automation.PSCustomObject]
        } -Force
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeTopLevelMethodCall)
        } | Should -Throw '*extended or executable methods*'
        $script:TopLevelScenarioMethodInvoked | Should -BeFalse

        $script:TypedFieldConversionInvoked = $false
        $unsafeTypedField = [pscustomobject][ordered]@{ Value = 'Environment' }
        $unsafeTypedField | Add-Member -MemberType ScriptMethod -Name ToString -Value {
            $script:TypedFieldConversionInvoked = $true
            'Environment'
        } -Force
        $unsafeTypedFieldCall = $baseCall.PSObject.Copy()
        $unsafeTypedFieldCall.Provider = $unsafeTypedField
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeTypedFieldCall)
        } | Should -Throw '*must be strings*'
        $script:TypedFieldConversionInvoked | Should -BeFalse

        $script:DictionaryScenarioGetterInvoked = $false
        $unsafeDictionaryCall = [ordered]@{
            Provider = 'Environment'; Operation = 'Inspect'
            ResourceToken = '<ENVIRONMENT:WINDOWS>'; Arguments = [ordered]@{}
        }
        Add-Member -InputObject $unsafeDictionaryCall -MemberType ScriptProperty -Name Computed -Value {
            $script:DictionaryScenarioGetterInvoked = $true
            'must-not-run'
        }
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeDictionaryCall)
        } | Should -Throw '*extended or executable*'
        $script:DictionaryScenarioGetterInvoked | Should -BeFalse

        $script:ArgumentScenarioGetterInvoked = $false
        $unsafeArguments = [ordered]@{ Name = 'HOME' }
        Add-Member -InputObject $unsafeArguments -MemberType ScriptProperty -Name Computed -Value {
            $script:ArgumentScenarioGetterInvoked = $true
            'must-not-run'
        }
        $unsafeArgumentCall = $baseCall.PSObject.Copy()
        $unsafeArgumentCall.Arguments = $unsafeArguments
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeArgumentCall)
        } | Should -Throw '*extended or executable*'
        $script:ArgumentScenarioGetterInvoked | Should -BeFalse

        $script:ArrayRankGetterInvoked = $false
        $unsafeArray = [object[]]@('synthetic')
        Add-Member -InputObject $unsafeArray -MemberType ScriptProperty -Name Rank -Value {
            $script:ArrayRankGetterInvoked = $true
            1
        } -Force
        $unsafeArrayCall = $baseCall.PSObject.Copy()
        $unsafeArrayCall.Result = [pscustomobject][ordered]@{ Items = $unsafeArray }
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($unsafeArrayCall)
        } | Should -Throw '*extended or executable properties*'
        $script:ArrayRankGetterInvoked | Should -BeFalse

        $customCall = $baseCall.PSObject.Copy()
        $customCall.Result = [System.IO.FileInfo]::new('C:\synthetic\never-read.txt')
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($customCall)
        } | Should -Throw '*unsupported data type*'

        $arrayListCall = $baseCall.PSObject.Copy()
        $arrayListCall.Result = [System.Collections.ArrayList]@('synthetic')
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($arrayListCall)
        } | Should -Throw '*unsupported data type*'
    }

    It 'rejects every non-null container or typed value under a secret-bearing field name' {
        $baseCall = [pscustomobject][ordered]@{
            Provider = 'Environment'; Operation = 'Inspect'
            ResourceToken = '<ENVIRONMENT:WINDOWS>'; Arguments = [ordered]@{}
            Result = $null
        }
        foreach ($case in @(
            [pscustomobject]@{ Value = [char[]]('sk-' + ('x' * 24)) },
            [pscustomobject]@{ Value = [ordered]@{ Value = 'redacted' } },
            [pscustomobject]@{ Value = [pscustomobject][ordered]@{ Value = 'redacted' } },
            [pscustomobject]@{ Value = [int]0 },
            [pscustomobject]@{ Value = 'PLACEHOLDER' },
            [pscustomobject]@{ Value = 'REDACTED' },
            [pscustomobject]@{ Value = '<redacted>' }
        )) {
            $unsafeValue = $case.Value
            $unsafeCall = $baseCall.PSObject.Copy()
            $unsafeCall.Result = [pscustomobject][ordered]@{ ApiKey = $unsafeValue }
            {
                New-CddsiFakeProviderSet -ExpectedCalls @($unsafeCall)
            } | Should -Throw '*secret-bearing fields*'
        }

        $safeCall = $baseCall.PSObject.Copy()
        $safeCall.Result = [pscustomobject][ordered]@{
            ApiKey = $null
            Authorization = 'redacted'
            Password = '<REDACTED>'
        }
        {
            New-CddsiFakeProviderSet -ExpectedCalls @($safeCall)
        } | Should -Not -Throw
    }

    It 'preserves empty singleton and multi-item result arrays as exact array values' {
        foreach ($case in @(
            [pscustomobject]@{ Value = [object[]]@() },
            [pscustomobject]@{ Value = [object[]]@('one') },
            [pscustomobject]@{ Value = [object[]]@('one', 'two') }
        )) {
            $resultValue = $case.Value
            $call = [pscustomobject][ordered]@{
                Provider = 'Environment'; Operation = 'Inspect'
                ResourceToken = '<ENVIRONMENT:WINDOWS>'; Arguments = [ordered]@{}
                Result = $resultValue
            }
            $providers = New-CddsiFakeProviderSet -ExpectedCalls @($call)
            $actual = $providers.ExpectedCalls[0].Result
            $actual.GetType().FullName | Should -BeExactly 'System.Object[]'
            $actual.Count | Should -Be $resultValue.Count
            (Get-CddsiFakeScenarioBindingToken -ExpectedCalls ([object[]]$providers.ExpectedCalls) `
                -FailureInjections ([object[]]$providers.FailureInjections)) |
                Should -BeExactly $providers.ScenarioBindingToken
        }
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
        $context.AccessLedger.Entries[0].PSObject.Properties.Name | Should -Contain 'ProviderEvidenceDigest'
        $context.AccessLedger.Entries[0].ProviderEvidenceDigest | Should -BeNullOrEmpty

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
        $context.AccessLedger.Entries[0].ProviderEvidenceDigest | Should -BeNullOrEmpty
        (Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations) | Should -BeTrue
    }

    It 'binds injected failures to the exact expected call including arguments and mutation state' {
        $expected = @(
            [pscustomobject]@{
                Provider = 'FileSystem'
                Operation = 'WriteFile'
                ResourceToken = '<STATE_ROOT>/state.json'
                Arguments = [ordered]@{ Encoding = 'utf8'; Flush = $true }
                Result = $null
            }
        )
        $failures = @(
            [pscustomobject]@{
                Sequence = 1
                ErrorCode = 'synthetic_write_failure'
                MessageSafe = 'Synthetic write failure.'
            }
        )
        $context = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failures
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem `
                -Operation WriteFile -ResourceToken '<STATE_ROOT>/state.json' `
                -Arguments ([ordered]@{ Flush = $true; Encoding = 'utf8' })
        } | Should -Throw '*synthetic_write_failure*'
        $entry = $context.AccessLedger.Entries[0]
        $entry.ArgumentCount | Should -Be 2
        $entry.IsMutation | Should -BeTrue
        $entry.Outcome | Should -BeExactly 'InjectedFailure'
        $entry.ErrorCode | Should -BeExactly 'synthetic_write_failure'
        $context.Providers.Cursor | Should -Be 1
        (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue
    }

    It 'rejects undeclared or mismatched manual injected-failure ledger additions without pollution' {
        $undeclared = New-FakeProviderTestContext
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $undeclared -Provider FileSystem `
                -Operation WriteFile -ResourceToken '<STATE_ROOT>/state.json' `
                -Arguments ([ordered]@{ Encoding = 'utf8'; Flush = $true }) `
                -Allowed $true -Expected $true -IsMutation $true -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'forged_failure'
        } | Should -Throw
        $undeclared.AccessLedger.Entries.Count | Should -Be 0

        $expected = @(
            [pscustomobject]@{
                Provider = 'Environment'
                Operation = 'GetVariable'
                ResourceToken = '<ENV:HOME>'
                Arguments = [ordered]@{ Name = 'HOME'; Required = $true }
                Result = 'synthetic-home'
            }
        )
        $failure = @(
            [pscustomobject]@{
                Sequence = 1
                ErrorCode = 'synthetic_failure'
                MessageSafe = 'Synthetic failure.'
            }
        )

        $missingInjection = New-FakeProviderTestContext -ExpectedCalls $expected
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $missingInjection -Provider Environment `
                -Operation GetVariable -ResourceToken '<ENV:HOME>' `
                -Arguments ([ordered]@{ Name = 'HOME'; Required = $true }) `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'synthetic_failure'
        } | Should -Throw '*declared failure injection*'
        $missingInjection.AccessLedger.Entries.Count | Should -Be 0

        $wrongArguments = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failure
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $wrongArguments -Provider Environment `
                -Operation GetVariable -ResourceToken '<ENV:HOME>' `
                -Arguments ([ordered]@{ Name = 'OTHER'; Required = $true }) `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'synthetic_failure'
        } | Should -Throw '*arguments do not match*'
        $wrongArguments.AccessLedger.Entries.Count | Should -Be 0

        $wrongArgumentCount = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failure
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $wrongArgumentCount -Provider Environment `
                -Operation GetVariable -ResourceToken '<ENV:HOME>' `
                -Arguments ([ordered]@{ Name = 'HOME'; Required = $true; Extra = $true }) `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'synthetic_failure'
        } | Should -Throw '*exact expected-call tuple*'
        $wrongArgumentCount.AccessLedger.Entries.Count | Should -Be 0

        $wrongMutation = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failure
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $wrongMutation -Provider Environment `
                -Operation GetVariable -ResourceToken '<ENV:HOME>' `
                -Arguments ([ordered]@{ Name = 'HOME'; Required = $true }) `
                -Allowed $true -Expected $true -IsMutation $true -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'synthetic_failure'
        } | Should -Throw '*mutation state*'
        $wrongMutation.AccessLedger.Entries.Count | Should -Be 0

        $wrongError = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failure
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $wrongError -Provider Environment `
                -Operation GetVariable -ResourceToken '<ENV:HOME>' `
                -Arguments ([ordered]@{ Name = 'HOME'; Required = $true }) `
                -Allowed $true -Expected $true -IsMutation $false -FailureInjected $true `
                -Outcome InjectedFailure -ErrorCode 'other_failure'
        } | Should -Throw '*declared failure injection*'
        $wrongError.AccessLedger.Entries.Count | Should -Be 0
    }

    It 'rejects forged historical injected-failure entries and cursor divergence' {
        $expected = @(
            [pscustomobject]@{
                Provider = 'FileSystem'
                Operation = 'WriteFile'
                ResourceToken = '<STATE_ROOT>/state.json'
                Arguments = [ordered]@{ Encoding = 'utf8'; Flush = $true }
                Result = $null
            }
        )
        $failures = @(
            [pscustomobject]@{
                Sequence = 1
                ErrorCode = 'synthetic_write_failure'
                MessageSafe = 'Synthetic write failure.'
            }
        )
        foreach ($mutation in @(
            { param($context) $context.AccessLedger.Entries[0].ArgumentCount = 1 },
            { param($context) $context.AccessLedger.Entries[0].IsMutation = $false },
            { param($context) $context.AccessLedger.Entries[0].ErrorCode = 'other_failure' },
            { param($context) $context.AccessLedger.Entries[0].ResourceToken = '<STATE_ROOT>/other.json' },
            { param($context) $context.Providers.Cursor = 0 }
        )) {
            $context = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failures
            try {
                Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem `
                    -Operation WriteFile -ResourceToken '<STATE_ROOT>/state.json' `
                    -Arguments ([ordered]@{ Encoding = 'utf8'; Flush = $true })
            }
            catch {
                $_.Exception.Message | Should -Match 'synthetic_write_failure'
            }
            & $mutation $context
            { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw
        }
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

    It 'keeps Allowed, InjectedFailure and Denied transitions in one exact auditable sequence' {
        $expected = @(
            [pscustomobject]@{
                Provider = 'FileSystem'
                Operation = 'WriteFile'
                ResourceToken = '<STATE_ROOT>/state.json'
                Result = $null
            },
            [pscustomobject]@{
                Provider = 'Process'
                Operation = 'Start'
                ResourceToken = '<PROCESS:SYNTHETIC>'
                Result = $null
            }
        )
        $failures = @(
            [pscustomobject]@{
                Sequence = 2
                ErrorCode = 'synthetic_start_failure'
                MessageSafe = 'Synthetic process start failure.'
            }
        )
        $context = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failures

        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Clock `
                -Operation UtcNow -ResourceToken '<CLOCK:UTC>'
        } | Should -Throw '*next exact expected call*'
        Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem `
            -Operation WriteFile -ResourceToken '<STATE_ROOT>/state.json' | Out-Null
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Process `
                -Operation Start -ResourceToken '<CANARY:GIT_CONFIG>'
        } | Should -Throw '*forbidden*'
        {
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Process `
                -Operation Start -ResourceToken '<PROCESS:SYNTHETIC>'
        } | Should -Throw '*synthetic_start_failure*'

        $context.Providers.Cursor | Should -Be 2
        @($context.AccessLedger.Entries.Outcome) | Should -Be @(
            'Denied', 'Allowed', 'Denied', 'InjectedFailure'
        )
        @($context.Providers.MutationSpy.Sequence) | Should -Be @(2, 3, 4)
        $context.AccessLedger.UnexpectedEntryCount | Should -Be 2
        $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 2
        (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue
    }

    It 'rejects cleared, extra or rewritten mutation-spy state' {
        $expected = @(
            [pscustomobject]@{
                Provider = 'FileSystem'
                Operation = 'WriteFile'
                ResourceToken = '<STATE_ROOT>/state.json'
                Result = $null
            }
        )
        foreach ($mutation in @(
            { param($context) $context.Providers.MutationSpy.Clear() },
            {
                param($context)
                [void]$context.Providers.MutationSpy.Add([pscustomobject][ordered]@{
                    Sequence = 2
                    Provider = 'FileSystem'
                    Operation = 'WriteFile'
                    ResourceToken = '<STATE_ROOT>/state.json'
                })
            },
            { param($context) $context.Providers.MutationSpy[0].Sequence = 2 },
            { param($context) $context.Providers.MutationSpy[0].Provider = 'Process' },
            { param($context) $context.Providers.MutationSpy[0].Operation = 'DeleteFile' },
            { param($context) $context.Providers.MutationSpy[0].ResourceToken = '<STATE_ROOT>/other.json' }
        )) {
            $context = New-FakeProviderTestContext -ExpectedCalls $expected
            Invoke-CddsiProviderOperation -ExecutionContext $context -Provider FileSystem `
                -Operation WriteFile -ResourceToken '<STATE_ROOT>/state.json' | Out-Null
            & $mutation $context
            { Assert-CddsiExecutionContext -ExecutionContext $context } |
                Should -Throw '*mutation spy*'
        }
    }

    It 'rejects forged denied counters, real-access counters, branches and cursor consumption' {
        foreach ($mutation in @(
            { param($context) $context.AccessLedger.UnexpectedEntryCount = 0 },
            { param($context) $context.AccessLedger.UnexpectedEntryCount = 2 },
            { param($context) $context.AccessLedger.ForbiddenResourceAccessCount = 0 },
            { param($context) $context.AccessLedger.ForbiddenResourceAccessCount = 2 },
            { param($context) $context.AccessLedger.OutsideSandboxWriteCount = 1 },
            { param($context) $context.AccessLedger.ProductLiveProcessSpawnCount = 1 },
            { param($context) $context.AccessLedger.ProductNetworkRequestCount = 1 },
            { param($context) $context.AccessLedger.RealRegistryAccessCount = 1 },
            { param($context) $context.AccessLedger.Entries[0].ErrorCode = 'sequence_mismatch' }
        )) {
            $context = New-FakeProviderTestContext
            {
                Invoke-CddsiProviderOperation -ExecutionContext $context -Provider Environment `
                    -Operation Inspect -ResourceToken '<ENV:OTHER>'
            } | Should -Throw '*default-denied*'
            & $mutation $context
            { Assert-CddsiExecutionContext -ExecutionContext $context } | Should -Throw
        }

        $expected = @(
            [pscustomobject]@{
                Provider = 'Environment'
                Operation = 'GetVariable'
                ResourceToken = '<ENV:HOME>'
                Result = 'synthetic-home'
            }
        )
        $cursorContext = New-FakeProviderTestContext -ExpectedCalls $expected
        {
            Invoke-CddsiProviderOperation -ExecutionContext $cursorContext -Provider Clock `
                -Operation UtcNow -ResourceToken '<CLOCK:UTC>'
        } | Should -Throw '*next exact expected call*'
        $cursorContext.Providers.Cursor = 1
        { Assert-CddsiExecutionContext -ExecutionContext $cursorContext } |
            Should -Throw '*cursor*'
    }

    It 'revalidates the complete mutable Fake scenario before every transition' {
        $expected = @(
            [pscustomobject]@{
                Provider = 'Environment'
                Operation = 'GetVariable'
                ResourceToken = '<ENV:HOME>'
                Arguments = [ordered]@{ Name = 'HOME' }
                Result = 'synthetic-home'
            }
        )
        $failures = @(
            [pscustomobject]@{
                Sequence = 1
                ErrorCode = 'synthetic_failure'
                MessageSafe = 'Synthetic failure.'
            }
        )
        foreach ($mutation in @(
            {
                param($context)
                $replacement = [System.Collections.ArrayList]::new()
                [void]$replacement.Add($context.Providers.ExpectedCalls[0])
                $context.Providers.ExpectedCalls = $replacement
            },
            {
                param($context)
                $context.Providers.ExpectedCalls[0] |
                    Add-Member -NotePropertyName Extra -NotePropertyValue $true
            },
            { param($context) $context.Providers.ExpectedCalls[0].Provider = 'environment' },
            { param($context) $context.Providers.ExpectedCalls[0].Operation = 'bad operation' },
            { param($context) $context.Providers.ExpectedCalls[0].ResourceToken = 'C:\real' },
            {
                param($context)
                $context.Providers.ExpectedCalls[0].Arguments = [pscustomobject]@{ Name = 'HOME' }
            },
            { param($context) $context.Providers.FailureInjections[0].Sequence = 1L },
            {
                param($context)
                $context.Providers.FailureInjections += [pscustomobject][ordered]@{
                    Sequence = 1
                    ErrorCode = 'second_failure'
                    MessageSafe = 'Second synthetic failure.'
                }
            },
            {
                param($context)
                $context.Providers.FailureInjections[0] |
                    Add-Member -NotePropertyName Extra -NotePropertyValue $true
            },
            { param($context) $context.Providers.FailureInjections[0].ErrorCode = 'bad code' },
            { param($context) $context.Providers.FailureInjections[0].MessageSafe = "line one`nline two" }
        )) {
            $context = New-FakeProviderTestContext -ExpectedCalls $expected -FailureInjections $failures
            & $mutation $context
            { Assert-CddsiExecutionContext -ExecutionContext $context } |
                Should -Throw '*Fake provider*'
        }
    }

    It 'rolls back every Fake transition field when post-state validation rejects the candidate' {
        $context = New-FakeProviderTestContext
        $before = $context | ConvertTo-Json -Depth 20 -Compress
        {
            Add-CddsiProductAccessLedgerEntry -ExecutionContext $context -Provider Environment `
                -Operation Inspect -ResourceToken '<ENV:OTHER>' -Allowed $false -Expected $false `
                -IsMutation $false -FailureInjected $false -Outcome Denied `
                -ErrorCode 'sequence_mismatch'
        } | Should -Throw '*fail-closed branch*'
        ($context | ConvertTo-Json -Depth 20 -Compress) | Should -BeExactly $before
        (Assert-CddsiExecutionContext -ExecutionContext $context) | Should -BeTrue
    }
}
