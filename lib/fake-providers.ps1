# fake-providers.ps1 - In-memory, default-deny fake providers for local and CI use.
# Provider behavior is data-driven. No scriptblock handler is stored or dispatched.

function New-CddsiFakeProviderSet {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$ExpectedCalls = @(),
        [AllowEmptyCollection()][object[]]$FailureInjections = @()
    )

    $normalizedExpectedCalls = @()
    foreach ($call in @($ExpectedCalls)) {
        if ($null -eq $call) {
            throw 'ExpectedCalls cannot contain null entries.'
        }
        $fieldNames = @(Get-CddsiFakeInputFieldNames -InputObject $call)
        $allowedFieldNames = @('Provider', 'Operation', 'ResourceToken', 'Arguments', 'Result')
        foreach ($fieldName in $fieldNames) {
            if ($allowedFieldNames -cnotcontains $fieldName) {
                throw ("ExpectedCalls contains an unknown field: {0}." -f $fieldName)
            }
        }
        foreach ($requiredName in @('Provider', 'Operation', 'ResourceToken')) {
            if ($fieldNames -cnotcontains $requiredName) {
                throw ("ExpectedCalls is missing field: {0}." -f $requiredName)
            }
        }

        $providerValue = Get-CddsiFakeInputFieldValue -InputObject $call -Name 'Provider'
        $operationValue = Get-CddsiFakeInputFieldValue -InputObject $call -Name 'Operation'
        $resourceTokenValue = Get-CddsiFakeInputFieldValue -InputObject $call -Name 'ResourceToken'
        if ($providerValue -isnot [string] -or
            $operationValue -isnot [string] -or
            $resourceTokenValue -isnot [string]) {
            throw 'ExpectedCalls Provider, Operation and ResourceToken must be strings.'
        }
        $provider = [string]$providerValue
        $operation = [string]$operationValue
        $resourceToken = [string]$resourceTokenValue
        if ($script:CddsiProviderNames -cnotcontains $provider) {
            throw 'ExpectedCalls contains an unsupported provider or incorrect casing.'
        }
        if ($operation -notmatch '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$') {
            throw 'ExpectedCalls contains an invalid operation name.'
        }
        if (-not (Test-CddsiLogicalResourceToken -ResourceToken $resourceToken)) {
            throw 'ExpectedCalls contains a non-logical resource token.'
        }

        $arguments = [ordered]@{}
        if ($fieldNames -ccontains 'Arguments') {
            $inputArguments = Get-CddsiFakeInputFieldValue -InputObject $call -Name 'Arguments'
            if ($null -ne $inputArguments) {
                if ($inputArguments -isnot [System.Collections.Specialized.OrderedDictionary]) {
                    throw 'ExpectedCalls.Arguments must be an OrderedDictionary.'
                }
                foreach ($key in @(Get-CddsiFakeInputFieldNames -InputObject $inputArguments)) {
                    $arguments[$key] = Get-CddsiFakeInputFieldValue -InputObject $inputArguments -Name $key
                }
            }
        }

        $result = $null
        if ($fieldNames -ccontains 'Result') {
            $result = Get-CddsiFakeInputFieldValue -InputObject $call -Name 'Result'
        }
        $normalizedExpectedCalls += [pscustomobject][ordered]@{
            Provider      = $provider
            Operation     = $operation
            ResourceToken = $resourceToken
            Arguments     = $arguments
            Result        = $result
        }
    }

    $normalizedFailureInjections = @()
    $seenFailureSequences = @{}
    foreach ($failure in @($FailureInjections)) {
        if ($null -eq $failure) {
            throw 'FailureInjections cannot contain null entries.'
        }
        $fieldNames = @(Get-CddsiFakeInputFieldNames -InputObject $failure)
        if (-not (Test-CddsiExactNameSet -Actual $fieldNames -Expected @('Sequence', 'ErrorCode', 'MessageSafe'))) {
            throw 'FailureInjections must contain exactly Sequence, ErrorCode and MessageSafe.'
        }
        $sequence = Get-CddsiFakeInputFieldValue -InputObject $failure -Name 'Sequence'
        $errorCodeValue = Get-CddsiFakeInputFieldValue -InputObject $failure -Name 'ErrorCode'
        $messageSafeValue = Get-CddsiFakeInputFieldValue -InputObject $failure -Name 'MessageSafe'
        if ($errorCodeValue -isnot [string] -or $messageSafeValue -isnot [string]) {
            throw 'FailureInjections ErrorCode and MessageSafe must be strings.'
        }
        $errorCode = [string]$errorCodeValue
        $messageSafe = [string]$messageSafeValue
        if (($sequence -isnot [int] -and $sequence -isnot [long]) -or [long]$sequence -lt 1 -or [long]$sequence -gt $normalizedExpectedCalls.Count) {
            throw 'FailureInjections.Sequence must identify an expected call.'
        }
        if ($seenFailureSequences.ContainsKey([string]$sequence)) {
            throw 'FailureInjections.Sequence must be unique.'
        }
        $seenFailureSequences[[string]$sequence] = $true
        if ($errorCode -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,63}$') {
            throw 'FailureInjections.ErrorCode must be a safe identifier.'
        }
        if ([string]::IsNullOrWhiteSpace($messageSafe) -or $messageSafe.Length -gt 256 -or $messageSafe -match '[\r\n]') {
            throw 'FailureInjections.MessageSafe must be a short single-line message.'
        }
        if (@(Find-CddsiPotentialSecrets -Content $messageSafe -Source '<FAKE_FAILURE>').Count -gt 0) {
            throw 'FailureInjections.MessageSafe must not contain credential material.'
        }
        $normalizedFailureInjections += [pscustomobject][ordered]@{
            Sequence    = [int]$sequence
            ErrorCode   = $errorCode
            MessageSafe = $messageSafe
        }
    }

    $providerSet = [ordered]@{
        SchemaVersion = 1
        Kind          = 'Fake'
    }
    foreach ($providerName in $script:CddsiProviderNames) {
        $providerSet[$providerName] = [pscustomobject][ordered]@{
            SchemaVersion = 1
            Name          = $providerName
            Kind          = 'Fake'
            IsLive        = $false
        }
    }
    $providerSet['ExpectedCalls'] = @($normalizedExpectedCalls)
    $providerSet['FailureInjections'] = @($normalizedFailureInjections)
    $providerSet['ScenarioBindingToken'] = ''
    $providerSet['Cursor'] = 0
    $providerSet['MutationSpy'] = [System.Collections.ArrayList]@()
    $result = [pscustomobject]$providerSet
    $result.ScenarioBindingToken = Get-CddsiFakeScenarioBindingToken `
        -ExpectedCalls ([object[]]$result.ExpectedCalls) `
        -FailureInjections ([object[]]$result.FailureInjections)
    Assert-CddsiFakeProviderScenario -ProviderSet $result | Out-Null
    return $result
}

function Invoke-CddsiFakeProviderOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [Parameter(Mandatory = $true)]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$ResourceToken,

        [System.Collections.IDictionary]$Arguments = ([ordered]@{})
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if ($script:CddsiProviderNames -cnotcontains $Provider) {
        throw 'Fake provider name is invalid.'
    }
    if ($Operation -notmatch '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$') {
        throw 'Fake provider operation name is invalid.'
    }

    $providerSet = $Context.Providers
    $isMutation = Test-CddsiFakeMutationOperation -Provider $Provider -Operation $Operation
    $resourceTokenAllowed = Test-CddsiFakeResourceTokenAllowed `
        -Policy $Context.Policy -ResourceToken $ResourceToken
    if (-not $resourceTokenAllowed) {
        Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $false -Expected $false -IsMutation $isMutation -FailureInjected $false -Outcome Denied -ErrorCode 'forbidden_resource' | Out-Null
        throw 'Fake provider denied a forbidden or non-logical resource token.'
    }

    $cursor = [int]$providerSet.Cursor
    $expectedCalls = @($providerSet.ExpectedCalls)
    if ($cursor -ge $expectedCalls.Count) {
        Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $false -Expected $false -IsMutation $isMutation -FailureInjected $false -Outcome Denied -ErrorCode 'default_deny' | Out-Null
        throw 'Fake provider default-denied an undeclared call.'
    }

    $expected = $expectedCalls[$cursor]
    $matches = (
        $expected.Provider -ceq $Provider -and
        $expected.Operation -ceq $Operation -and
        $expected.ResourceToken -ceq $ResourceToken -and
        (Test-CddsiFakeValueEqual -Expected $expected.Arguments -Actual $Arguments)
    )
    if (-not $matches) {
        Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $false -Expected $false -IsMutation $isMutation -FailureInjected $false -Outcome Denied -ErrorCode 'sequence_mismatch' | Out-Null
        throw 'Fake provider call did not match the next exact expected call.'
    }

    $sequence = $cursor + 1

    $failureInjection = $null
    foreach ($candidateFailure in @($providerSet.FailureInjections)) {
        if ([int]$candidateFailure.Sequence -eq $sequence) {
            $failureInjection = $candidateFailure
            break
        }
    }
    if ($null -ne $failureInjection) {
        Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $true -Expected $true -IsMutation $isMutation -FailureInjected $true -Outcome InjectedFailure -ErrorCode $failureInjection.ErrorCode | Out-Null
        throw ("FAKE_PROVIDER_FAILURE[{0}]: {1}" -f $failureInjection.ErrorCode, $failureInjection.MessageSafe)
    }

    Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $true -Expected $true -IsMutation $isMutation -FailureInjected $false -Outcome Allowed | Out-Null
    return $expected.Result
}

function Assert-CddsiFakeProviderExpectations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [switch]$RequireNoMutations
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $providerSet = $Context.Providers
    $remaining = @($providerSet.ExpectedCalls).Count - [int]$providerSet.Cursor
    if ($remaining -ne 0) {
        throw ("Fake provider has {0} unconsumed expected call(s)." -f $remaining)
    }
    if ([int]$Context.AccessLedger.UnexpectedEntryCount -ne 0) {
        throw 'Fake provider recorded unexpected ledger entries.'
    }
    if ($RequireNoMutations -and @($providerSet.MutationSpy).Count -ne 0) {
        throw 'Fake provider mutation spy is not zero.'
    }
    return $true
}
