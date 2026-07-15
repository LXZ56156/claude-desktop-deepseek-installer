# fake-providers.ps1 - In-memory, default-deny fake providers for local and CI use.
# Provider behavior is data-driven. No scriptblock handler is stored or dispatched.

function Get-CddsiFakeInputFieldNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        return @($InputObject.Keys | ForEach-Object { [string]$_ })
    }
    return @($InputObject.PSObject.Properties.Name)
}

function Get-CddsiFakeInputFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    if ($InputObject -is [System.Collections.IDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ceq $Name) {
                return $InputObject[$key]
            }
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property) {
        return $null
    }
    return $property.Value
}

function Test-CddsiFakeValueEqual {
    [CmdletBinding()]
    param(
        [AllowNull()][AllowEmptyCollection()]$Expected,
        [AllowNull()][AllowEmptyCollection()]$Actual
    )

    if ($null -eq $Expected -or $null -eq $Actual) {
        return ($null -eq $Expected -and $null -eq $Actual)
    }

    $expectedIsDictionary = $Expected -is [System.Collections.IDictionary]
    $actualIsDictionary = $Actual -is [System.Collections.IDictionary]
    if ($expectedIsDictionary -or $actualIsDictionary) {
        if (-not ($expectedIsDictionary -and $actualIsDictionary)) {
            return $false
        }
        $expectedKeys = @($Expected.Keys | ForEach-Object { [string]$_ })
        $actualKeys = @($Actual.Keys | ForEach-Object { [string]$_ })
        if (-not (Test-CddsiExactNameSet -Actual $actualKeys -Expected $expectedKeys)) {
            return $false
        }
        foreach ($expectedKey in $Expected.Keys) {
            $actualKey = $null
            foreach ($candidateKey in $Actual.Keys) {
                if ([string]$candidateKey -ceq [string]$expectedKey) {
                    $actualKey = $candidateKey
                    break
                }
            }
            if ($null -eq $actualKey -or -not (Test-CddsiFakeValueEqual -Expected $Expected[$expectedKey] -Actual $Actual[$actualKey])) {
                return $false
            }
        }
        return $true
    }

    $expectedIsList = ($Expected -is [System.Array] -or $Expected -is [System.Collections.IList]) -and $Expected -isnot [string]
    $actualIsList = ($Actual -is [System.Array] -or $Actual -is [System.Collections.IList]) -and $Actual -isnot [string]
    if ($expectedIsList -or $actualIsList) {
        if (-not ($expectedIsList -and $actualIsList)) {
            return $false
        }
        $expectedItems = @($Expected)
        $actualItems = @($Actual)
        if ($expectedItems.Count -ne $actualItems.Count) {
            return $false
        }
        for ($index = 0; $index -lt $expectedItems.Count; $index++) {
            if (-not (Test-CddsiFakeValueEqual -Expected $expectedItems[$index] -Actual $actualItems[$index])) {
                return $false
            }
        }
        return $true
    }

    if ($Expected.GetType().FullName -cne $Actual.GetType().FullName) {
        return $false
    }
    if ($Expected -is [string]) {
        return ([string]$Expected -ceq [string]$Actual)
    }
    return [object]::Equals($Expected, $Actual)
}

function Test-CddsiFakeMutationOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Operation
    )

    $mutationOperations = switch -CaseSensitive ($Provider) {
        'FileSystem' { @('CreateDirectory', 'WriteFile', 'AppendFile', 'ReplaceFile', 'DeleteFile', 'CopyFile', 'MoveFile', 'SetAcl', 'FlushFile'); break }
        'Environment' { @('SetVariable', 'RemoveVariable'); break }
        'Registry' { @('WriteValue', 'DeleteValue', 'CreateKey', 'DeleteKey'); break }
        'Process' { @('Start', 'Stop', 'Terminate'); break }
        'Network' { @(); break }
        'Package' { @('Install', 'Update', 'Remove'); break }
        'Feature' { @('Enable', 'Disable'); break }
        'Service' { @('Start', 'Stop', 'SetStartupType'); break }
        'Credential' { @('Store', 'Delete'); break }
        'Clock' { @(); break }
        default { @(); break }
    }
    return ($mutationOperations -ccontains $Operation)
}

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

        $provider = [string](Get-CddsiFakeInputFieldValue -InputObject $call -Name 'Provider')
        $operation = [string](Get-CddsiFakeInputFieldValue -InputObject $call -Name 'Operation')
        $resourceToken = [string](Get-CddsiFakeInputFieldValue -InputObject $call -Name 'ResourceToken')
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
                if ($inputArguments -isnot [System.Collections.IDictionary]) {
                    throw 'ExpectedCalls.Arguments must be an IDictionary.'
                }
                foreach ($key in $inputArguments.Keys) {
                    $arguments[[string]$key] = $inputArguments[$key]
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
        $errorCode = [string](Get-CddsiFakeInputFieldValue -InputObject $failure -Name 'ErrorCode')
        $messageSafe = [string](Get-CddsiFakeInputFieldValue -InputObject $failure -Name 'MessageSafe')
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
    $providerSet['Cursor'] = 0
    $providerSet['MutationSpy'] = [System.Collections.ArrayList]@()
    return [pscustomobject]$providerSet
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
    if ($isMutation) {
        $safeMutationToken = if (Test-CddsiLogicalResourceToken -ResourceToken $ResourceToken) {
            $ResourceToken
        }
        else {
            '<INVALID_RESOURCE_TOKEN>'
        }
        [void]$providerSet.MutationSpy.Add([pscustomobject][ordered]@{
            Sequence      = [int]$Context.AccessLedger.Entries.Count + 1
            Provider      = $Provider
            Operation     = $Operation
            ResourceToken = $safeMutationToken
        })
    }

    $resourceTokenAllowed = Test-CddsiLogicalResourceToken -ResourceToken $ResourceToken
    if ($resourceTokenAllowed) {
        foreach ($forbiddenToken in @($Context.Policy.ForbiddenResourceTokens)) {
            if (
                $ResourceToken -ceq $forbiddenToken -or
                $ResourceToken.StartsWith(([string]$forbiddenToken + '/'), [System.StringComparison]::Ordinal) -or
                $ResourceToken.StartsWith(([string]$forbiddenToken + '\'), [System.StringComparison]::Ordinal)
            ) {
                $resourceTokenAllowed = $false
                break
            }
        }
    }
    if ($resourceTokenAllowed) {
        foreach ($canaryToken in @($Context.Policy.CanaryTokens)) {
            if (
                $ResourceToken -ceq $canaryToken -or
                $ResourceToken.StartsWith(([string]$canaryToken + '/'), [System.StringComparison]::Ordinal) -or
                $ResourceToken.StartsWith(([string]$canaryToken + '\'), [System.StringComparison]::Ordinal)
            ) {
                $resourceTokenAllowed = $false
                break
            }
        }
    }
    if (-not $resourceTokenAllowed) {
        $Context.AccessLedger.ForbiddenResourceAccessCount = [int]$Context.AccessLedger.ForbiddenResourceAccessCount + 1
        $Context.AccessLedger.UnexpectedEntryCount = [int]$Context.AccessLedger.UnexpectedEntryCount + 1
        Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $false -Expected $false -IsMutation $isMutation -FailureInjected $false -Outcome Denied -ErrorCode 'forbidden_resource' | Out-Null
        throw 'Fake provider denied a forbidden or non-logical resource token.'
    }

    $cursor = [int]$providerSet.Cursor
    $expectedCalls = @($providerSet.ExpectedCalls)
    if ($cursor -ge $expectedCalls.Count) {
        $Context.AccessLedger.ForbiddenResourceAccessCount = [int]$Context.AccessLedger.ForbiddenResourceAccessCount + 1
        $Context.AccessLedger.UnexpectedEntryCount = [int]$Context.AccessLedger.UnexpectedEntryCount + 1
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
        $Context.AccessLedger.ForbiddenResourceAccessCount = [int]$Context.AccessLedger.ForbiddenResourceAccessCount + 1
        $Context.AccessLedger.UnexpectedEntryCount = [int]$Context.AccessLedger.UnexpectedEntryCount + 1
        Add-CddsiProductAccessLedgerEntry -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments -Allowed $false -Expected $false -IsMutation $isMutation -FailureInjected $false -Outcome Denied -ErrorCode 'sequence_mismatch' | Out-Null
        throw 'Fake provider call did not match the next exact expected call.'
    }

    $sequence = $cursor + 1
    $providerSet.Cursor = $sequence

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
