BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\execution-context.ps1')
    . (Join-Path $script:RepoRoot 'lib\state-store.ps1')
}

Describe 'provider-backed state store' {
    BeforeEach {
        $script:StateStoreContext = [pscustomobject]@{
            Mode  = 'TestSafe'
            RunId = '20000000-0000-4000-8000-000000000001'
            Paths = [pscustomobject]@{
                State = (Join-Path $TestDrive 'state\state.json')
            }
        }
        Mock Assert-CddsiExecutionContext { return $true }
        Mock Invoke-CddsiProviderOperation { throw 'unexpected provider call' }
        Mock Assert-CddsiMutationAllowed { throw 'P1 blocks Live mutation' }
    }

    It 'uses only the context-owned state target' {
        (Get-CddsiStatePath -ExecutionContext $script:StateStoreContext) | Should -Be $script:StateStoreContext.Paths.State
        (Test-CddsiStateTarget -ExecutionContext $script:StateStoreContext -Path $script:StateStoreContext.Paths.State) | Should -BeTrue
        (Test-CddsiStateTarget -ExecutionContext $script:StateStoreContext -Path (Join-Path $TestDrive 'other.json')) | Should -BeFalse
    }

    It 'reads state only through the declared fake FileSystem operation' {
        $state = New-CddsiState -RunId '20000000-0000-4000-8000-000000000001' -TimestampUtc '2030-01-01T00:00:00.0000000Z'
        $json = ConvertTo-CddsiJson -InputObject $state
        Mock Invoke-CddsiProviderOperation { return $json }

        $result = Read-CddsiState -ExecutionContext $script:StateStoreContext -Mode TestSafe

        $result.Status | Should -Be 'SUCCEEDED'
        $result.Success | Should -BeTrue
        $result.Changed | Should -BeFalse
        $result.Data.runId | Should -Be $state.runId
        Should -Invoke Invoke-CddsiProviderOperation -Times 1 -Exactly -ParameterFilter {
            $Provider -ceq 'FileSystem' -and
            $Operation -ceq 'ReadText' -and
            $ResourceToken -ceq '<STATE>' -and
            $Arguments.Encoding -ceq 'UTF8'
        }
    }

    It 'returns a non-success plan without invoking a mutation provider' {
        $state = New-CddsiState -RunId '20000000-0000-4000-8000-000000000001' -TimestampUtc '2030-01-01T00:00:00.0000000Z'

        $result = Write-CddsiStateAtomic -ExecutionContext $script:StateStoreContext -State $state -Mode TestSafe

        $result.Status | Should -Be 'ACTION_REQUIRED'
        $result.ErrorCode | Should -Be 'SCAFFOLD_ONLY'
        $result.Success | Should -BeFalse
        $result.Changed | Should -BeFalse
        $result.PlannedChanges | Should -Contain '<STATE>'
        Should -Invoke Invoke-CddsiProviderOperation -Times 0 -Exactly
    }

    It 'fails closed before every Live state mutation' {
        $context = [pscustomobject]@{
            Mode  = 'Live'
            RunId = '20000000-0000-4000-8000-000000000001'
            Paths = $script:StateStoreContext.Paths
        }
        $state = New-CddsiState -RunId '20000000-0000-4000-8000-000000000001' -TimestampUtc '2030-01-01T00:00:00.0000000Z' -ExecutionMode Live

        { Write-CddsiStateAtomic -ExecutionContext $context -State $state -Mode Live -AcknowledgeRealChanges } | Should -Throw
        Should -Invoke Invoke-CddsiProviderOperation -Times 0 -Exactly
    }

    It 'rejects stale run ownership and execution-mode drift' {
        $state = New-CddsiState -RunId '20000000-0000-4000-8000-000000000009' -TimestampUtc '2030-01-01T00:00:00.0000000Z'
        Mock Invoke-CddsiProviderOperation { return (ConvertTo-CddsiJson -InputObject $state) }
        { Read-CddsiState -ExecutionContext $script:StateStoreContext -Mode TestSafe } | Should -Throw '*runId*'

        $state = New-CddsiState -RunId $script:StateStoreContext.RunId -TimestampUtc '2030-01-01T00:00:00.0000000Z' -ExecutionMode DryRun
        { Write-CddsiStateAtomic -ExecutionContext $script:StateStoreContext -State $state -Mode TestSafe } | Should -Throw '*executionMode*'
    }

    It 'requires ExecutionContext on every public store operation' {
        { Get-CddsiStatePath } | Should -Throw
        { Test-CddsiStateTarget -Path 'state.json' } | Should -Throw
        { Read-CddsiState } | Should -Throw
        { Write-CddsiStateAtomic -State ([pscustomobject]@{}) } | Should -Throw
    }
}
