# execution-context.ps1 - Pure execution-context, product-ledger and evidence contracts.
# This file performs no filesystem, registry, process, network or clock access.

$script:CddsiProviderNames = @(
    'FileSystem',
    'Environment',
    'Registry',
    'Process',
    'Network',
    'Package',
    'Feature',
    'Service',
    'Credential',
    'Clock'
)

$script:CddsiContextPathNames = @(
    'Home',
    'UserProfile',
    'LocalAppData',
    'AppData',
    'ProgramData',
    'Temp',
    'Download',
    'State',
    'Backup',
    'Report',
    'Credential',
    'ConfigLibrary',
    'GitGlobalConfig',
    'XdgConfig',
    'XdgData'
)

$script:CddsiContextPolicyNames = @(
    'SchemaVersion',
    'AllowLiveProvider',
    'ForbiddenResourceTokens',
    'CanaryTokens'
)

function Get-CddsiLiveReadOnlyCapabilityContracts {
    [CmdletBinding()]
    param()

    return @(
    [pscustomobject][ordered]@{
        Provider = 'Environment'; Operation = 'Inspect'; ResourceToken = '<ENVIRONMENT:WINDOWS>'
        ArgumentNames = @(); ResultSchemaId = 'WindowsEnvironmentObservation/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Environment'; Operation = 'Inspect'; ResourceToken = '<ENVIRONMENT:HARDWARE_VIRTUALIZATION>'
        ArgumentNames = @(); ResultSchemaId = 'HardwareVirtualizationObservation/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Environment'; Operation = 'Inspect'; ResourceToken = '<KNOWN_FOLDERS:CURRENT_USER>'
        ArgumentNames = @(); ResultSchemaId = 'CurrentUserKnownFoldersObservation/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Package'; Operation = 'Inspect'; ResourceToken = '<PACKAGE:CLAUDE_DESKTOP>'
        ArgumentNames = @(); ResultSchemaId = 'ClaudeDesktopPackageInventory/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Process'; Operation = 'Inspect'; ResourceToken = '<PROCESS:GIT_FOR_WINDOWS>'
        ArgumentNames = @(); ResultSchemaId = 'GitForWindowsInventory/v2'
    }
    [pscustomobject][ordered]@{
        Provider = 'Feature'; Operation = 'Inspect'; ResourceToken = '<FEATURE:VIRTUAL_MACHINE_PLATFORM>'
        ArgumentNames = @(); ResultSchemaId = 'VirtualMachinePlatformObservation/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Service'; Operation = 'Inspect'; ResourceToken = '<SERVICE:COWORK>'
        ArgumentNames = @(); ResultSchemaId = 'CoworkServiceObservation/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Registry'; Operation = 'Inspect'; ResourceToken = '<HKLM_MANAGED_POLICY>'
        ArgumentNames = @(); ResultSchemaId = 'ClaudeConfigSourceMetadata/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Registry'; Operation = 'Inspect'; ResourceToken = '<HKCU_MANAGED_POLICY>'
        ArgumentNames = @(); ResultSchemaId = 'ClaudeConfigSourceMetadata/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'FileSystem'; Operation = 'Inspect'; ResourceToken = '<CONFIG_LIBRARY>'
        ArgumentNames = @(); ResultSchemaId = 'ClaudeConfigSourceMetadata/v1'
    }
    [pscustomobject][ordered]@{
        Provider = 'Process'; Operation = 'Inspect'; ResourceToken = '<PROCESS:CLAUDE_DESKTOP>'
        ArgumentNames = @(); ResultSchemaId = 'ClaudeDesktopProcessInventory/v1'
    }
    )
}

function Test-CddsiExactNameSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Actual,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Expected
    )

    if ($Actual.Count -ne $Expected.Count) {
        return $false
    }

    $difference = @(Compare-Object -ReferenceObject @($Expected | Sort-Object) -DifferenceObject @($Actual | Sort-Object) -CaseSensitive)
    return ($difference.Count -eq 0)
}

function Test-CddsiExactNotePropertySet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$Expected
    )

    if ($null -eq $InputObject) {
        return $false
    }
    $properties = @($InputObject.PSObject.Properties)
    if (-not (Test-CddsiExactNameSet -Actual @($properties.Name) -Expected $Expected)) {
        return $false
    }
    foreach ($name in $Expected) {
        $property = $InputObject.PSObject.Properties[$name]
        if ($null -eq $property -or
            $property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
            -not $property.IsGettable -or -not $property.IsSettable) {
            return $false
        }
    }
    return $true
}

function Test-CddsiLogicalResourceToken {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [string]$ResourceToken
    )

    if ([string]::IsNullOrWhiteSpace($ResourceToken)) {
        return $false
    }

    return [regex]::IsMatch($ResourceToken, '^<[A-Z0-9_:-]+>(?:[\\/][A-Za-z0-9_.-]+)*$')
}

function Get-CddsiFakeInputFieldNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject
    )

    foreach ($method in @($InputObject.PSObject.Methods)) {
        if ($method.MemberType -ne [System.Management.Automation.PSMemberTypes]::Method) {
            throw 'Fake provider inputs must not contain extended or executable methods.'
        }
    }
    foreach ($member in @($InputObject.PSObject.Members)) {
        if (@('PropertySet', 'MemberSet', 'Event', 'Dynamic', 'InferredProperty') -ccontains
            [string]$member.MemberType) {
            throw 'Fake provider inputs must not contain extended member sets or events.'
        }
    }
    $safeNamePattern = '^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}$'
    if ($InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        if ($InputObject.GetType() -ne [System.Collections.Specialized.OrderedDictionary]) {
            throw 'Fake provider input dictionaries require the exact OrderedDictionary runtime type.'
        }
        foreach ($property in @($InputObject.PSObject.Properties)) {
            if ($property.MemberType -ne [System.Management.Automation.PSMemberTypes]::Property) {
                throw 'Fake provider input dictionaries must not contain extended or executable properties.'
            }
        }
        $names = @()
        foreach ($key in $InputObject.Keys) {
            if ($key -isnot [string] -or [string]$key -notmatch $safeNamePattern) {
                throw 'Fake provider input dictionary keys must be safe strings.'
            }
            $names += [string]$key
        }
        if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
            throw 'Fake provider input dictionary keys must be unique with exact casing.'
        }
        return $names
    }
    if ($InputObject -isnot [System.Management.Automation.PSCustomObject]) {
        throw 'Fake provider inputs require PSCustomObject or OrderedDictionary data.'
    }

    $properties = @($InputObject.PSObject.Properties)
    foreach ($property in $properties) {
        if ($property.Name -notmatch $safeNamePattern -or
            $property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
            -not $property.IsGettable -or -not $property.IsSettable) {
            throw 'Fake provider input objects require safe, settable NoteProperty members only.'
        }
    }
    $names = @($properties | ForEach-Object { [string]$_.Name })
    if (@($names | Sort-Object -Unique).Count -ne $names.Count) {
        throw 'Fake provider input object property names must be unique with exact casing.'
    }
    return $names
}

function Get-CddsiFakeInputFieldValue {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $InputObject,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $fieldNames = @(Get-CddsiFakeInputFieldNames -InputObject $InputObject)
    if ($fieldNames -cnotcontains $Name) {
        return $null
    }

    if ($InputObject -is [System.Collections.Specialized.OrderedDictionary]) {
        foreach ($key in $InputObject.Keys) {
            if ([string]$key -ceq $Name) {
                $value = $InputObject[$key]
                if ($value -is [System.Collections.IEnumerable] -and
                    $value -isnot [string]) {
                    return ,$value
                }
                return $value
            }
        }
        return $null
    }

    $property = $InputObject.PSObject.Properties[$Name]
    if ($null -eq $property -or
        $property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
        -not $property.IsGettable -or -not $property.IsSettable) {
        return $null
    }
    $value = $property.Value
    if ($value -is [System.Collections.IEnumerable] -and
        $value -isnot [string]) {
        return ,$value
    }
    return $value
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
        if (($Expected -is [System.Collections.Specialized.OrderedDictionary] -and
                $Expected.GetType() -ne [System.Collections.Specialized.OrderedDictionary]) -or
            ($Actual -is [System.Collections.Specialized.OrderedDictionary] -and
                $Actual.GetType() -ne [System.Collections.Specialized.OrderedDictionary])) {
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
            if ($null -eq $actualKey -or
                -not (Test-CddsiFakeValueEqual -Expected $Expected[$expectedKey] -Actual $Actual[$actualKey])) {
                return $false
            }
        }
        return $true
    }

    $expectedIsList = ($Expected -is [System.Array] -or
        $Expected -is [System.Collections.IList]) -and $Expected -isnot [string]
    $actualIsList = ($Actual -is [System.Array] -or
        $Actual -is [System.Collections.IList]) -and $Actual -isnot [string]
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

function Get-CddsiFakeScenarioBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$ExpectedCalls,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$FailureInjections
    )

    # PSSerializer is used only after an explicit pure-data walk.  This avoids
    # invoking ScriptProperty/CodeProperty getters while still binding CLR
    # scalar types and collection/property order identically on PS 7 and 5.1.
    $payload = [pscustomobject][ordered]@{
        ContractTag       = 'CDDsi/FakeScenario/v1'
        ExpectedCalls     = [object[]]$ExpectedCalls
        FailureInjections = [object[]]$FailureInjections
    }
    $pending = [System.Collections.ArrayList]@()
    [void]$pending.Add([pscustomobject][ordered]@{
        Value     = $payload
        Depth     = 0
        Name      = 'Scenario'
        Ancestors = [System.Collections.ArrayList]@()
    })
    $nodeCount = 0
    $totalStringCharacters = 0L
    $safeNamePattern = '^[A-Za-z0-9_][A-Za-z0-9_.:-]{0,127}$'
    $sensitiveNamePattern = '^(?i:api[ _-]?key|auth[ _-]?token|authorization|password|secret)$'
    $secretPatterns = @(
        '(?i)(?<![a-z0-9_-])sk-[a-z0-9_-]{20,}(?![a-z0-9_-])',
        '(?i)(?<![a-z0-9._~-])Bearer\s+[a-z0-9._~-]{20,}(?![a-z0-9._~-])',
        '(?i)"?(api[ _-]?key|auth[ _-]?token|authorization)"?\s*[:=]\s*["'']?(?!<|null\b|placeholder\b|redacted\b)[a-z0-9._~-]{20,}',
        ('(?i)-----BEGIN [^-\r\n]*' + ('PRIVATE' + ' KEY') + '-----')
    )

    while ($pending.Count -gt 0) {
        $pendingIndex = $pending.Count - 1
        $item = $pending[$pendingIndex]
        $pending.RemoveAt($pendingIndex)
        $value = $item.Value
        $depth = [int]$item.Depth
        $valueName = [string]$item.Name

        if ($depth -gt 32) {
            throw 'Fake provider scenario data exceeds the maximum depth of 32.'
        }
        $nodeCount++
        if ($nodeCount -gt 4096) {
            throw 'Fake provider scenario data exceeds the maximum node count of 4096.'
        }
        if ($null -eq $value) {
            continue
        }
        foreach ($method in @($value.PSObject.Methods)) {
            if ($method.MemberType -ne [System.Management.Automation.PSMemberTypes]::Method) {
                throw 'Fake provider scenario data must not contain extended or executable methods.'
            }
        }
        foreach ($member in @($value.PSObject.Members)) {
            if (@('PropertySet', 'MemberSet', 'Event', 'Dynamic', 'InferredProperty') -ccontains
                [string]$member.MemberType) {
                throw 'Fake provider scenario data must not contain extended member sets or events.'
            }
        }
        if ($valueName -match $sensitiveNamePattern) {
            if ($value -isnot [string]) {
                throw 'Fake provider scenario data must not contain secret-bearing fields.'
            }
            $sensitiveStringValue = [string]$value
            if (@('placeholder', 'redacted', '<REDACTED>') -cnotcontains $sensitiveStringValue) {
                foreach ($secretPattern in $secretPatterns) {
                    if ([regex]::IsMatch($sensitiveStringValue, $secretPattern)) {
                        throw 'Fake provider scenario data must not contain credential material.'
                    }
                }
                throw 'Fake provider scenario data must not contain secret-bearing fields.'
            }
        }

        $isSafeScalar = (
            $value -is [string] -or $value -is [char] -or
            $value -is [bool] -or
            $value -is [byte] -or $value -is [sbyte] -or
            $value -is [int16] -or $value -is [uint16] -or
            $value -is [int32] -or $value -is [uint32] -or
            $value -is [int64] -or $value -is [uint64] -or
            $value -is [single] -or $value -is [double]
        )
        $isArray = $value -is [System.Array]
        $isOrderedDictionary = $value -is [System.Collections.Specialized.OrderedDictionary]
        $isCustomObject = $value -is [System.Management.Automation.PSCustomObject]
        if ($isOrderedDictionary -and
            $value.GetType() -ne [System.Collections.Specialized.OrderedDictionary]) {
            throw 'Fake provider scenario dictionaries require the exact OrderedDictionary runtime type.'
        }
        $isContainer = $isArray -or $isOrderedDictionary -or $isCustomObject
        $nextAncestors = $item.Ancestors

        if ($isContainer) {
            $nextAncestors = [System.Collections.ArrayList]@()
            foreach ($ancestor in @($item.Ancestors)) {
                if ([object]::ReferenceEquals($ancestor, $value)) {
                    throw 'Fake provider scenario data must not contain cyclic object references.'
                }
                [void]$nextAncestors.Add([object]$ancestor)
            }
            [void]$nextAncestors.Add([object]$value)
        }

        if ($isSafeScalar) {
            foreach ($property in @($value.PSObject.Properties)) {
                if ($property.MemberType -ne [System.Management.Automation.PSMemberTypes]::Property) {
                    throw 'Fake provider scalar values must not contain extended or executable properties.'
                }
            }
            if ($value -is [string]) {
                $stringValue = [string]$value
                $totalStringCharacters += $stringValue.Length
                if ($totalStringCharacters -gt 4194304L) {
                    throw 'Fake provider scenario string data exceeds the four-megacharacter limit.'
                }
                foreach ($secretPattern in $secretPatterns) {
                    if ([regex]::IsMatch($stringValue, $secretPattern)) {
                        throw 'Fake provider scenario data must not contain credential material.'
                    }
                }
            }
            continue
        }

        if ($isArray) {
            foreach ($property in @($value.PSObject.Properties)) {
                $isPs51BuiltInCountAlias = (
                    $property.Name -ceq 'Count' -and
                    $property.MemberType -eq [System.Management.Automation.PSMemberTypes]::AliasProperty -and
                    $property.ReferencedMemberName -ceq 'Length'
                )
                if ($property.MemberType -ne [System.Management.Automation.PSMemberTypes]::Property -and
                    -not $isPs51BuiltInCountAlias) {
                    throw 'Fake provider scenario arrays must not contain extended or executable properties.'
                }
            }
            if ($value.Rank -ne 1) {
                throw 'Fake provider scenario arrays must be one-dimensional.'
            }
            for ($index = $value.Length - 1; $index -ge 0; $index--) {
                [void]$pending.Add([pscustomobject][ordered]@{
                    Value     = $value.GetValue($index)
                    Depth     = $depth + 1
                    Name      = ([string]$index)
                    Ancestors = $nextAncestors
                })
            }
            continue
        }

        if ($isOrderedDictionary) {
            foreach ($property in @($value.PSObject.Properties)) {
                if ($property.MemberType -ne [System.Management.Automation.PSMemberTypes]::Property) {
                    throw 'Fake provider scenario dictionaries must not contain extended or executable properties.'
                }
            }
            $dictionaryKeys = @($value.Keys)
            for ($index = $dictionaryKeys.Count - 1; $index -ge 0; $index--) {
                $key = $dictionaryKeys[$index]
                if ($key -isnot [string] -or $key -notmatch $safeNamePattern) {
                    throw 'Fake provider scenario dictionary keys must be safe strings.'
                }
                [void]$pending.Add([pscustomobject][ordered]@{
                    Value     = $value[$key]
                    Depth     = $depth + 1
                    Name      = [string]$key
                    Ancestors = $nextAncestors
                })
            }
            continue
        }

        if ($isCustomObject) {
            $properties = @($value.PSObject.Properties)
            foreach ($property in $properties) {
                if ($property.Name -notmatch $safeNamePattern -or
                    $property.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
                    -not $property.IsGettable -or -not $property.IsSettable) {
                    throw 'Fake provider scenario objects require safe, settable NoteProperty members only.'
                }
            }
            for ($index = $properties.Count - 1; $index -ge 0; $index--) {
                $property = $properties[$index]
                [void]$pending.Add([pscustomobject][ordered]@{
                    Value     = $property.Value
                    Depth     = $depth + 1
                    Name      = [string]$property.Name
                    Ancestors = $nextAncestors
                })
            }
            continue
        }

        throw 'Fake provider scenario contains an unsupported data type.'
    }

    $serialized = [System.Management.Automation.PSSerializer]::Serialize($payload, 64)
    foreach ($secretPattern in $secretPatterns) {
        if ([regex]::IsMatch($serialized, $secretPattern)) {
            throw 'Fake provider scenario serialization must not contain credential material.'
        }
    }

    # This is an unkeyed structural-integrity checksum, not a MAC or proof of
    # origin.  It detects ordinary in-memory deletion/rewrite but not an
    # attacker who is already authorized to rewrite both state and checksum.
    $bindingBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        "CDDsi/FakeScenarioBinding/v1`n" + $serialized
    )
    $hasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        return [System.BitConverter]::ToString(
            $hasher.ComputeHash($bindingBytes)
        ).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hasher.Dispose()
    }
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

function Test-CddsiFakeResourceTokenAllowed {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,

        [AllowNull()]
        [string]$ResourceToken
    )

    if ($ResourceToken -ceq '<INVALID_RESOURCE_TOKEN>' -or
        -not (Test-CddsiLogicalResourceToken -ResourceToken $ResourceToken)) {
        return $false
    }

    foreach ($policyCollectionName in @('ForbiddenResourceTokens', 'CanaryTokens')) {
        foreach ($blockedToken in @($Policy.$policyCollectionName)) {
            if (
                $ResourceToken -ceq $blockedToken -or
                $ResourceToken.StartsWith(
                    ([string]$blockedToken + '/'),
                    [System.StringComparison]::Ordinal
                ) -or
                $ResourceToken.StartsWith(
                    ([string]$blockedToken + '\'),
                    [System.StringComparison]::Ordinal
                )
            ) {
                return $false
            }
        }
    }
    return $true
}

function Assert-CddsiFakeProviderScenario {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProviderSet
    )

    $requiredProviderSetNames = @('SchemaVersion', 'Kind') + $script:CddsiProviderNames +
        @('ExpectedCalls', 'FailureInjections', 'ScenarioBindingToken', 'Cursor', 'MutationSpy')
    if ($null -eq $ProviderSet -or
        -not (Test-CddsiExactNotePropertySet -InputObject $ProviderSet `
            -Expected $requiredProviderSetNames) -or
        $ProviderSet.Kind -cne 'Fake') {
        throw 'Fake provider scenario requires the exact Fake provider-set kind.'
    }
    if ($ProviderSet.ExpectedCalls -isnot [System.Array] -or
        $ProviderSet.FailureInjections -isnot [System.Array]) {
        throw 'Fake provider scenario collections must be arrays.'
    }

    foreach ($call in @($ProviderSet.ExpectedCalls)) {
        if ($null -eq $call -or
            -not (Test-CddsiExactNotePropertySet -InputObject $call `
                -Expected @('Provider', 'Operation', 'ResourceToken', 'Arguments', 'Result'))) {
            throw 'Fake provider ExpectedCalls entry does not match the exact normalized schema.'
        }
        if ($call.Provider -isnot [string] -or
            $script:CddsiProviderNames -cnotcontains $call.Provider) {
            throw 'Fake provider ExpectedCalls entry has an invalid provider.'
        }
        if ($call.Operation -isnot [string] -or
            $call.Operation -notmatch '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$') {
            throw 'Fake provider ExpectedCalls entry has an invalid operation.'
        }
        if ($call.ResourceToken -isnot [string] -or
            -not (Test-CddsiLogicalResourceToken -ResourceToken $call.ResourceToken)) {
            throw 'Fake provider ExpectedCalls entry has a non-logical resource token.'
        }
        if ($call.Arguments -isnot [System.Collections.IDictionary]) {
            throw 'Fake provider ExpectedCalls entry Arguments must be an IDictionary.'
        }
        foreach ($argumentKey in $call.Arguments.Keys) {
            if ($argumentKey -isnot [string] -or [string]::IsNullOrEmpty($argumentKey)) {
                throw 'Fake provider ExpectedCalls argument names must be non-empty strings.'
            }
        }
    }

    $seenFailureSequences = @{}
    foreach ($failure in @($ProviderSet.FailureInjections)) {
        if ($null -eq $failure -or
            -not (Test-CddsiExactNotePropertySet -InputObject $failure `
                -Expected @('Sequence', 'ErrorCode', 'MessageSafe'))) {
            throw 'Fake provider FailureInjections entry does not match the exact normalized schema.'
        }
        if ($failure.Sequence -isnot [int] -or $failure.Sequence -lt 1 -or
            $failure.Sequence -gt @($ProviderSet.ExpectedCalls).Count) {
            throw 'Fake provider FailureInjections sequence must identify an expected call.'
        }
        if ($seenFailureSequences.ContainsKey([string]$failure.Sequence)) {
            throw 'Fake provider FailureInjections sequence must be unique.'
        }
        $seenFailureSequences[[string]$failure.Sequence] = $true
        if ($failure.ErrorCode -isnot [string] -or
            $failure.ErrorCode -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,63}$') {
            throw 'Fake provider FailureInjections ErrorCode must be a safe identifier.'
        }
        if ($failure.MessageSafe -isnot [string] -or
            [string]::IsNullOrWhiteSpace($failure.MessageSafe) -or
            $failure.MessageSafe.Length -gt 256 -or $failure.MessageSafe -match '[\r\n]') {
            throw 'Fake provider FailureInjections MessageSafe must be a short single-line string.'
        }
        if (@(Find-CddsiPotentialSecrets -Content $failure.MessageSafe `
            -Source '<FAKE_FAILURE>').Count -gt 0) {
            throw 'Fake provider FailureInjections MessageSafe must not contain credential material.'
        }
    }

    if ($ProviderSet.ScenarioBindingToken -isnot [string] -or
        $ProviderSet.ScenarioBindingToken -cnotmatch '^[a-f0-9]{64}$') {
        throw 'Fake provider ScenarioBindingToken must be a lowercase SHA-256 value.'
    }
    $recomputedScenarioBindingToken = Get-CddsiFakeScenarioBindingToken `
        -ExpectedCalls ([object[]]$ProviderSet.ExpectedCalls) `
        -FailureInjections ([object[]]$ProviderSet.FailureInjections)
    if ($ProviderSet.ScenarioBindingToken -cne $recomputedScenarioBindingToken) {
        throw 'Fake provider ScenarioBindingToken does not match the complete normalized scenario.'
    }

    return $true
}

function Test-CddsiLiveReadOnlyCapabilityTuple {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProviderSet,

        [Parameter(Mandatory = $true)]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$ResourceToken,

        [Parameter(Mandatory = $true)]
        $ArgumentCount
    )

    if ($null -eq $ProviderSet) {
        return $false
    }
    $kindProperty = $ProviderSet.PSObject.Properties['Kind']
    $providerProperty = $ProviderSet.PSObject.Properties[$Provider]
    if ($null -eq $kindProperty -or
        $kindProperty.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
        -not $kindProperty.IsGettable -or -not $kindProperty.IsSettable -or
        $kindProperty.Value -cne 'LiveReadOnly' -or
        $null -eq $providerProperty -or
        $providerProperty.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
        -not $providerProperty.IsGettable -or -not $providerProperty.IsSettable -or
        $script:CddsiProviderNames -cnotcontains $Provider -or
        ($ArgumentCount -isnot [int] -and $ArgumentCount -isnot [long]) -or
        [long]$ArgumentCount -ne 0) {
        return $false
    }

    $providerContract = $providerProperty.Value
    if ($null -eq $providerContract -or
        -not (Test-CddsiExactNotePropertySet -InputObject $providerContract -Expected @(
            'SchemaVersion', 'Name', 'Kind', 'IsLive', 'Access', 'Capabilities'
        )) -or
        $providerContract.Name -cne $Provider -or
        $providerContract.Kind -cne 'LiveReadOnly' -or -not $providerContract.IsLive) {
        return $false
    }

    foreach ($capability in @($providerContract.Capabilities)) {
        if ((Test-CddsiExactNotePropertySet -InputObject $capability -Expected @(
            'SchemaVersion', 'Operation', 'ResourceToken', 'ArgumentNames', 'ResultSchemaId'
        )) -and
            $capability.Operation -is [string] -and $capability.Operation -ceq $Operation -and
            $capability.ResourceToken -is [string] -and
            $capability.ResourceToken -ceq $ResourceToken -and
            @($capability.ArgumentNames).Count -eq 0) {
            return $true
        }
    }
    return $false
}

function Assert-CddsiProductAccessLedgerEntryValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $ProviderSet,

        [Parameter(Mandatory = $true)]
        $Provider,

        [Parameter(Mandatory = $true)]
        $Operation,

        [Parameter(Mandatory = $true)]
        $ResourceToken,

        [Parameter(Mandatory = $true)]
        $ArgumentCount,

        [Parameter(Mandatory = $true)]
        $Allowed,

        [Parameter(Mandatory = $true)]
        $Expected,

        [Parameter(Mandatory = $true)]
        $IsMutation,

        [Parameter(Mandatory = $true)]
        $FailureInjected,

        [Parameter(Mandatory = $true)]
        $Outcome,

        [Parameter(Mandatory = $true)]
        $ErrorCode,

        [AllowNull()]
        $ProviderEvidenceDigest,

        [AllowNull()]
        $InvocationBindingToken,

        [AllowNull()]
        $ExpectedCallSequence = $null,

        [AllowNull()]
        $Arguments
    )

    if ($null -eq $ProviderSet) {
        throw 'Access-ledger ProviderSet is mandatory.'
    }
    $providerSetKindProperty = $ProviderSet.PSObject.Properties['Kind']
    if ($null -eq $providerSetKindProperty -or
        $providerSetKindProperty.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
        -not $providerSetKindProperty.IsGettable -or -not $providerSetKindProperty.IsSettable -or
        $providerSetKindProperty.Value -isnot [string]) {
        throw 'Access-ledger ProviderSet.Kind must be a settable NoteProperty.'
    }
    $providerSetKind = [string]$providerSetKindProperty.Value
    if ($providerSetKind -ceq 'Unloaded') {
        throw 'The Unloaded provider set must never contain a product access-ledger entry.'
    }
    if (@('Fake', 'LiveReadOnly') -cnotcontains $providerSetKind) {
        throw 'Access-ledger ProviderSet.Kind is unsupported.'
    }

    if ($Provider -isnot [string] -or $script:CddsiProviderNames -cnotcontains $Provider) {
        throw 'Access-ledger Provider must be an exact case-sensitive provider name.'
    }
    if ($Operation -isnot [string] -or
        $Operation -notmatch '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$') {
        throw 'Access-ledger Operation is not a safe identifier.'
    }
    if ($ResourceToken -isnot [string] -or
        -not (Test-CddsiLogicalResourceToken -ResourceToken $ResourceToken)) {
        throw 'Access-ledger ResourceToken must be a logical token.'
    }
    if (($ArgumentCount -isnot [int] -and $ArgumentCount -isnot [long]) -or
        [long]$ArgumentCount -lt 0) {
        throw 'Access-ledger ArgumentCount must be a non-negative integer.'
    }
    if ($Allowed -isnot [bool] -or $Expected -isnot [bool] -or
        $IsMutation -isnot [bool] -or $FailureInjected -isnot [bool]) {
        throw 'Access-ledger Boolean fields must be Boolean.'
    }
    if ($Outcome -isnot [string] -or
        @('Allowed', 'Denied', 'InjectedFailure', 'ProviderFailure') -cnotcontains $Outcome) {
        throw 'Access-ledger Outcome is invalid.'
    }
    if ($ErrorCode -isnot [string] -or
        (-not [string]::IsNullOrEmpty($ErrorCode) -and
            $ErrorCode -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,63}$')) {
        throw 'Access-ledger ErrorCode is not a safe identifier.'
    }
    if ($null -ne $ProviderEvidenceDigest -and
        ($ProviderEvidenceDigest -isnot [string] -or
            $ProviderEvidenceDigest -cnotmatch '^[a-f0-9]{64}$')) {
        throw 'Access-ledger ProviderEvidenceDigest must be null or a lowercase SHA-256 value.'
    }
    if ($providerSetKind -ceq 'Fake') {
        if ($InvocationBindingToken -isnot [string] -or
            $InvocationBindingToken -cnotmatch '^[a-f0-9]{64}$') {
            throw 'Access-ledger Fake InvocationBindingToken must be a lowercase SHA-256 value.'
        }
    }
    elseif ($null -ne $InvocationBindingToken) {
        throw 'Access-ledger LiveReadOnly InvocationBindingToken must remain null.'
    }

    if ($providerSetKind -ceq 'Fake' -and
        $IsMutation -ne (Test-CddsiFakeMutationOperation -Provider $Provider -Operation $Operation)) {
        throw 'Access-ledger Fake mutation state does not match the exact provider operation.'
    }

    $expectedCall = $null
    $expectedInvocationBindingToken = $null
    if ($providerSetKind -ceq 'Fake' -and $null -ne $ExpectedCallSequence) {
        if (($ExpectedCallSequence -isnot [int] -and $ExpectedCallSequence -isnot [long]) -or
            [long]$ExpectedCallSequence -lt 1 -or
            [long]$ExpectedCallSequence -gt @($ProviderSet.ExpectedCalls).Count) {
            throw 'Access-ledger Fake entry must bind to an exact expected-call sequence.'
        }

        $expectedCall = @($ProviderSet.ExpectedCalls)[[int]$ExpectedCallSequence - 1]
        if ($null -eq $expectedCall -or
            -not (Test-CddsiExactNotePropertySet -InputObject $expectedCall `
                -Expected @('Provider', 'Operation', 'ResourceToken', 'Arguments', 'Result')) -or
            $expectedCall.Arguments -isnot [System.Collections.IDictionary]) {
            throw 'Access-ledger Fake expected-call binding is invalid.'
        }
        $expectedInvocationBindingToken = Get-CddsiFakeScenarioBindingToken `
            -ExpectedCalls ([object[]]@(
                [pscustomobject][ordered]@{
                    Provider      = $expectedCall.Provider
                    Operation     = $expectedCall.Operation
                    ResourceToken = $expectedCall.ResourceToken
                    Arguments     = $expectedCall.Arguments
                }
            )) `
            -FailureInjections ([object[]]@())
    }

    if ($providerSetKind -ceq 'Fake' -and
        ($Outcome -ceq 'Allowed' -or $Outcome -ceq 'InjectedFailure')) {
        if ($null -eq $expectedCall) {
            throw 'Access-ledger Fake outcome must bind to an exact expected-call sequence.'
        }
        if ($null -eq $expectedCall -or
            -not (Test-CddsiExactNotePropertySet -InputObject $expectedCall `
                -Expected @('Provider', 'Operation', 'ResourceToken', 'Arguments', 'Result')) -or
            $expectedCall.Arguments -isnot [System.Collections.IDictionary] -or
            $expectedCall.Provider -isnot [string] -or $expectedCall.Provider -cne $Provider -or
            $expectedCall.Operation -isnot [string] -or $expectedCall.Operation -cne $Operation -or
            $expectedCall.ResourceToken -isnot [string] -or
            $expectedCall.ResourceToken -cne $ResourceToken -or
            [long]$ArgumentCount -ne [long]$expectedCall.Arguments.Count) {
            throw 'Access-ledger Fake outcome does not match the exact expected-call tuple.'
        }
        if ($InvocationBindingToken -cne $expectedInvocationBindingToken) {
            throw 'Access-ledger Fake outcome does not match its exact invocation binding.'
        }

        if ($PSBoundParameters.ContainsKey('Arguments')) {
            if ($Arguments -isnot [System.Collections.IDictionary] -or
                -not (Test-CddsiFakeValueEqual -Expected $expectedCall.Arguments -Actual $Arguments)) {
                throw 'Access-ledger Fake arguments do not match the exact expected call.'
            }
        }

        $matchingFailureInjections = @(
            @($ProviderSet.FailureInjections) |
                Where-Object {
                    $null -ne $_ -and
                    $_.Sequence -is [int] -and
                    $_.Sequence -eq [int]$ExpectedCallSequence
                }
        )
        if ($Outcome -ceq 'InjectedFailure') {
            if ($matchingFailureInjections.Count -ne 1 -or
                -not (Test-CddsiExactNotePropertySet `
                    -InputObject $matchingFailureInjections[0] `
                    -Expected @('Sequence', 'ErrorCode', 'MessageSafe')) -or
                $matchingFailureInjections[0].ErrorCode -isnot [string] -or
                $matchingFailureInjections[0].ErrorCode -cne $ErrorCode) {
                throw 'Access-ledger InjectedFailure does not match the declared failure injection.'
            }
        }
        elseif ($matchingFailureInjections.Count -ne 0) {
            throw 'Access-ledger Allowed outcome conflicts with a declared failure injection.'
        }
    }

    switch -CaseSensitive ($Outcome) {
        'Allowed' {
            if (-not $Allowed -or -not $Expected -or $FailureInjected -or
                -not [string]::IsNullOrEmpty($ErrorCode)) {
                throw 'Access-ledger Allowed outcome fields are inconsistent.'
            }
            if ($providerSetKind -ceq 'LiveReadOnly') {
                throw 'Access-ledger LiveReadOnly Allowed is forbidden until an implemented result-evidence binding exists.'
            }
            elseif ($null -ne $ProviderEvidenceDigest) {
                throw 'Access-ledger Allowed evidence does not match the provider-set kind.'
            }
            break
        }
        'Denied' {
            if ($Allowed -or $Expected -or $FailureInjected -or
                [string]::IsNullOrEmpty($ErrorCode) -or $null -ne $ProviderEvidenceDigest) {
                throw 'Access-ledger Denied outcome fields are inconsistent.'
            }
            if ($providerSetKind -ceq 'Fake' -and $ErrorCode -ceq 'sequence_mismatch') {
                if ($null -eq $expectedInvocationBindingToken -or
                    $InvocationBindingToken -ceq $expectedInvocationBindingToken) {
                    throw 'Access-ledger Fake sequence_mismatch must retain a distinct invocation binding.'
                }
            }
            elseif ($providerSetKind -ceq 'LiveReadOnly') {
                $expectedIsMutation = $Operation -cne 'Inspect'
                if ($IsMutation -ne $expectedIsMutation) {
                    throw 'Access-ledger LiveReadOnly Denied mutation state does not match the exact operation.'
                }

                $expectedDenialErrorCode = $null
                if ([long]$ArgumentCount -ne 0) {
                    $expectedDenialErrorCode = 'LIVE_READ_ONLY_ARGUMENTS_DENIED'
                }
                else {
                    $resourceCapabilityCount = 0
                    foreach ($providerName in $script:CddsiProviderNames) {
                        $providerContractProperty = $ProviderSet.PSObject.Properties[$providerName]
                        if ($null -eq $providerContractProperty -or
                            $providerContractProperty.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
                            -not $providerContractProperty.IsGettable -or
                            -not $providerContractProperty.IsSettable) {
                            throw 'Access-ledger LiveReadOnly provider contract must be a settable NoteProperty.'
                        }
                        $liveProviderContract = $providerContractProperty.Value
                        if (-not (Test-CddsiExactNotePropertySet -InputObject $liveProviderContract -Expected @(
                            'SchemaVersion', 'Name', 'Kind', 'IsLive', 'Access', 'Capabilities'
                        ))) {
                            throw 'Access-ledger LiveReadOnly provider contract has executable or invalid properties.'
                        }
                        foreach ($capability in @($liveProviderContract.Capabilities)) {
                            if (-not (Test-CddsiExactNotePropertySet -InputObject $capability -Expected @(
                                'SchemaVersion', 'Operation', 'ResourceToken',
                                'ArgumentNames', 'ResultSchemaId'
                            ))) {
                                throw 'Access-ledger LiveReadOnly capability has executable or invalid properties.'
                            }
                            if ($capability.ResourceToken -is [string] -and
                                $capability.ResourceToken -ceq $ResourceToken) {
                                $resourceCapabilityCount++
                            }
                        }
                    }
                    if ($resourceCapabilityCount -eq 0) {
                        $expectedDenialErrorCode = 'LIVE_READ_ONLY_RESOURCE_DENIED'
                    }
                    elseif (-not (Test-CddsiLiveReadOnlyCapabilityTuple -ProviderSet $ProviderSet `
                        -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken `
                        -ArgumentCount $ArgumentCount)) {
                        $expectedDenialErrorCode = 'LIVE_READ_ONLY_CAPABILITY_DENIED'
                    }
                }
                if ($null -eq $expectedDenialErrorCode -or
                    $ErrorCode -cne $expectedDenialErrorCode) {
                    throw 'Access-ledger LiveReadOnly Denied error does not match its exact fail-closed branch.'
                }
            }
            break
        }
        'InjectedFailure' {
            if (-not $Allowed -or -not $Expected -or -not $FailureInjected -or
                [string]::IsNullOrEmpty($ErrorCode) -or $null -ne $ProviderEvidenceDigest -or
                $providerSetKind -cne 'Fake') {
                throw 'Access-ledger InjectedFailure outcome fields are inconsistent.'
            }
            break
        }
        'ProviderFailure' {
            if (-not $Allowed -or -not $Expected -or $IsMutation -or $FailureInjected -or
                [long]$ArgumentCount -ne 0 -or
                $ErrorCode -cne 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED' -or
                $null -ne $ProviderEvidenceDigest -or $providerSetKind -cne 'LiveReadOnly' -or
                -not (Test-CddsiLiveReadOnlyCapabilityTuple -ProviderSet $ProviderSet `
                    -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken `
                    -ArgumentCount $ArgumentCount)) {
                throw 'Access-ledger ProviderFailure outcome fields or exact LiveReadOnly capability tuple are inconsistent.'
            }
            break
        }
    }

    return $true
}

function New-CddsiAccessLedger {
    [CmdletBinding()]
    param(
        [switch]$LiveProviderLoaded
    )

    return [pscustomobject][ordered]@{
        SchemaVersion                    = 1
        Plane                            = 'Product'
        Entries                          = [System.Collections.ArrayList]@()
        UnexpectedEntryCount             = 0
        ForbiddenResourceAccessCount     = 0
        OutsideSandboxWriteCount         = 0
        ProductLiveProcessSpawnCount     = 0
        ProductNetworkRequestCount       = 0
        RealRegistryAccessCount          = 0
        LiveProviderLoaded               = $LiveProviderLoaded.IsPresent
    }
}

function Add-CddsiProductAccessLedgerEntry {
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

        [System.Collections.IDictionary]$Arguments = ([ordered]@{}),

        [Parameter(Mandatory = $true)]
        [bool]$Allowed,

        [Parameter(Mandatory = $true)]
        [bool]$Expected,

        [Parameter(Mandatory = $true)]
        [bool]$IsMutation,

        [Parameter(Mandatory = $true)]
        [bool]$FailureInjected,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Allowed', 'Denied', 'InjectedFailure', 'ProviderFailure')]
        [string]$Outcome,

        [string]$ErrorCode = '',

        [AllowNull()]
        $ProviderEvidenceDigest = $null
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null

    if ($script:CddsiProviderNames -cnotcontains $Provider) {
        throw 'Access-ledger Provider must be an exact case-sensitive provider name.'
    }

    $safeResourceToken = if (Test-CddsiLogicalResourceToken -ResourceToken $ResourceToken) {
        $ResourceToken
    }
    else {
        '<INVALID_RESOURCE_TOKEN>'
    }

    $argumentCount = if ($null -eq $Arguments) { 0 } else { [int]$Arguments.Count }
    $isFakeTransition = $Context.Providers.Kind -ceq 'Fake'
    $expectedCallSequence = if ($isFakeTransition -and
        ($Outcome -ceq 'Allowed' -or $Outcome -ceq 'InjectedFailure' -or
            ($Outcome -ceq 'Denied' -and $ErrorCode -ceq 'sequence_mismatch')) -and
        [int]$Context.Providers.Cursor -lt @($Context.Providers.ExpectedCalls).Count) {
        [int]$Context.Providers.Cursor + 1
    }
    else {
        $null
    }
    $invocationBindingToken = $null
    if ($isFakeTransition) {
        # Validate the actual call as secret-free pure data before any
        # comparison or ledger mutation.  The ledger retains only this digest,
        # never the Arguments payload.
        $invocationBindingToken = Get-CddsiFakeScenarioBindingToken `
            -ExpectedCalls ([object[]]@(
                [pscustomobject][ordered]@{
                    Provider      = $Provider
                    Operation     = $Operation
                    ResourceToken = $safeResourceToken
                    Arguments     = $Arguments
                }
            )) `
            -FailureInjections ([object[]]@())
        if ($Outcome -ceq 'Allowed' -or $Outcome -ceq 'InjectedFailure') {
            $expectedInvocation = @($Context.Providers.ExpectedCalls)[[int]$expectedCallSequence - 1]
            $invocationBindingToken = Get-CddsiFakeScenarioBindingToken `
                -ExpectedCalls ([object[]]@(
                    [pscustomobject][ordered]@{
                        Provider      = $expectedInvocation.Provider
                        Operation     = $expectedInvocation.Operation
                        ResourceToken = $expectedInvocation.ResourceToken
                        Arguments     = $expectedInvocation.Arguments
                    }
                )) `
                -FailureInjections ([object[]]@())
        }
    }
    Assert-CddsiProductAccessLedgerEntryValues -ProviderSet $Context.Providers `
        -Provider $Provider -Operation $Operation -ResourceToken $safeResourceToken `
        -ArgumentCount $argumentCount -Allowed $Allowed -Expected $Expected `
        -IsMutation $IsMutation -FailureInjected $FailureInjected -Outcome $Outcome `
        -ErrorCode $ErrorCode -ProviderEvidenceDigest $ProviderEvidenceDigest `
        -InvocationBindingToken $invocationBindingToken `
        -ExpectedCallSequence $expectedCallSequence -Arguments $Arguments | Out-Null

    $ledger = $Context.AccessLedger
    $entry = [pscustomobject][ordered]@{
        Sequence        = [int]$ledger.Entries.Count + 1
        Plane           = 'Product'
        Provider        = $Provider
        Operation       = $Operation
        ResourceToken   = $safeResourceToken
        ArgumentCount   = $argumentCount
        Allowed         = $Allowed
        Expected        = $Expected
        IsMutation      = $IsMutation
        FailureInjected = $FailureInjected
        Outcome         = $Outcome
        ErrorCode       = $ErrorCode
        ProviderEvidenceDigest = $ProviderEvidenceDigest
        InvocationBindingToken  = $invocationBindingToken
    }

    $ledgerCountBefore = [int]$ledger.Entries.Count
    $mutationSpyCountBefore = if ($isFakeTransition) {
        [int]$Context.Providers.MutationSpy.Count
    }
    else {
        0
    }
    $cursorBefore = if ($isFakeTransition) {
        [int]$Context.Providers.Cursor
    }
    else {
        0
    }
    $unexpectedCountBefore = $ledger.UnexpectedEntryCount
    $forbiddenCountBefore = $ledger.ForbiddenResourceAccessCount
    try {
        [void]$ledger.Entries.Add($entry)
        if ($isFakeTransition) {
            if ($Outcome -ceq 'Allowed' -or $Outcome -ceq 'InjectedFailure') {
                $Context.Providers.Cursor = $cursorBefore + 1
            }
            if ($IsMutation) {
                [void]$Context.Providers.MutationSpy.Add([pscustomobject][ordered]@{
                    Sequence      = $entry.Sequence
                    Provider      = $entry.Provider
                    Operation     = $entry.Operation
                    ResourceToken = $entry.ResourceToken
                })
            }
        }
        if ($Outcome -ceq 'Denied' -and
            ($isFakeTransition -or $Context.Providers.Kind -ceq 'LiveReadOnly')) {
            $ledger.UnexpectedEntryCount = $unexpectedCountBefore + 1
            $ledger.ForbiddenResourceAccessCount = $forbiddenCountBefore + 1
        }
        Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
        return $entry
    }
    catch {
        while ($ledger.Entries.Count -gt $ledgerCountBefore) {
            $ledger.Entries.RemoveAt($ledger.Entries.Count - 1)
        }
        if ($isFakeTransition) {
            while ($Context.Providers.MutationSpy.Count -gt $mutationSpyCountBefore) {
                $Context.Providers.MutationSpy.RemoveAt($Context.Providers.MutationSpy.Count - 1)
            }
            $Context.Providers.Cursor = $cursorBefore
        }
        $ledger.UnexpectedEntryCount = $unexpectedCountBefore
        $ledger.ForbiddenResourceAccessCount = $forbiddenCountBefore
        throw
    }
}

function New-CddsiUnloadedProviderSet {
    [CmdletBinding()]
    param()

    $providerSet = [ordered]@{
        SchemaVersion = 1
        Kind          = 'Unloaded'
    }
    foreach ($providerName in $script:CddsiProviderNames) {
        $providerSet[$providerName] = [pscustomobject][ordered]@{
            SchemaVersion = 1
            Name          = $providerName
            Kind          = 'Unloaded'
            IsLive        = $false
        }
    }
    $providerSet['ExpectedCalls'] = @()
    $providerSet['FailureInjections'] = @()
    $providerSet['Cursor'] = 0
    $providerSet['MutationSpy'] = [System.Collections.ArrayList]@()
    return [pscustomobject]$providerSet
}

function New-CddsiLiveReadOnlyProviderSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('VmDevelopment', 'VmAcceptance', 'UserLive')]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [ValidateSet('VmDevelopment', 'VmAcceptance', 'UserLive')]
        [string]$EnvironmentTier,

        [Parameter(Mandatory = $true)]
        [ValidateSet('VmDevelopment', 'VmAcceptance', 'UserLive')]
        [string]$ArtifactProfile,

        [Parameter(Mandatory = $true)]
        [string]$AdapterSha256,

        [Parameter(Mandatory = $true)]
        [string]$LoadOperationUseId,

        [Parameter(Mandatory = $true)]
        [string]$LoadReceiptBindingToken
    )

    $parsedRunId = [guid]::Empty
    if (-not [guid]::TryParse($RunId, [ref]$parsedRunId) -or $parsedRunId -eq [guid]::Empty -or
        $RunId -cne $parsedRunId.ToString('D')) {
        throw 'LiveReadOnly provider RunId must be a canonical lowercase GUID.'
    }
    $parsedOperationUseId = [guid]::Empty
    if (-not [guid]::TryParse($LoadOperationUseId, [ref]$parsedOperationUseId) -or
        $parsedOperationUseId -eq [guid]::Empty -or
        $LoadOperationUseId -cne $parsedOperationUseId.ToString('D') -or
        $LoadOperationUseId -ceq $RunId) {
        throw 'LiveReadOnly provider LoadOperationUseId must be a canonical lowercase GUID.'
    }
    if ($Stage -cne $EnvironmentTier -or $Stage -cne $ArtifactProfile) {
        throw 'LiveReadOnly provider stage, environment tier and artifact profile must match exactly.'
    }
    if ($AdapterSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'LiveReadOnly provider AdapterSha256 must be a lowercase SHA-256 value.'
    }
    if ($LoadReceiptBindingToken -cnotmatch '^[a-f0-9]{64}$') {
        throw 'LiveReadOnly provider load receipt binding token must be a lowercase SHA-256 value.'
    }

    $capabilities = @(
        Get-CddsiLiveReadOnlyCapabilityContracts |
            ForEach-Object {
                [pscustomobject][ordered]@{
                    Provider            = $_.Provider
                    Operation           = $_.Operation
                    ResourceToken       = $_.ResourceToken
                    ArgumentNames       = @($_.ArgumentNames)
                    ResultSchemaId       = $_.ResultSchemaId
                }
            }
    )
    [string[]]$capabilityLines = @(
        $capabilities |
            ForEach-Object {
                '{0}|{1}|{2}|{3}|{4}' -f $_.Provider, $_.Operation, $_.ResourceToken,
                    (@($_.ArgumentNames) -join ','), $_.ResultSchemaId
            }
    )
    [System.Array]::Sort($capabilityLines, [System.StringComparer]::Ordinal)
    $capabilityBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
        ($capabilityLines -join "`n")
    )
    $capabilityHasher = [System.Security.Cryptography.SHA256]::Create()
    try {
        $capabilitySetDigest = [System.BitConverter]::ToString(
            $capabilityHasher.ComputeHash($capabilityBytes)
        ).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $capabilityHasher.Dispose()
    }
    if ($capabilitySetDigest -cne
        '26c9e8d095c7570df019d1758d277d6bc6b6161d88695f2b96f3350dcc4e942e') {
        throw 'LiveReadOnly canonical capability source does not match the fixed digest.'
    }
    $providerSet = [ordered]@{
        SchemaVersion                    = 2
        Kind                             = 'LiveReadOnly'
        RunId                            = $RunId
        Stage                            = $Stage
        EnvironmentTier                  = $EnvironmentTier
        ArtifactProfile                  = $ArtifactProfile
        AdapterSha256                    = $AdapterSha256
        LoadOperationUseId               = $LoadOperationUseId
        LoadReceiptBindingToken          = $LoadReceiptBindingToken
        CapabilitySetDigest              = $capabilitySetDigest
    }
    foreach ($providerName in $script:CddsiProviderNames) {
        $providerCapabilities = @(
            $capabilities |
                Where-Object { $_.Provider -ceq $providerName } |
                ForEach-Object {
                    [pscustomobject][ordered]@{
                        SchemaVersion       = 1
                        Operation           = $_.Operation
                        ResourceToken       = $_.ResourceToken
                        ArgumentNames       = @($_.ArgumentNames)
                        ResultSchemaId       = $_.ResultSchemaId
                    }
                }
        )
        $providerSet[$providerName] = [pscustomobject][ordered]@{
            SchemaVersion = 2
            Name          = $providerName
            Kind          = 'LiveReadOnly'
            IsLive        = $true
            Access        = 'ReadOnly'
            Capabilities  = $providerCapabilities
        }
    }
    return [pscustomobject]$providerSet
}

function New-CddsiExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$RunId,

        [Parameter(Mandatory = $true)]
        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [Parameter(Mandatory = $true)]
        [ValidateSet('Scaffold', 'Development', 'VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive')]
        [string]$Stage,

        [Parameter(Mandatory = $true)]
        [ValidateSet('HostSandbox', 'CI', 'VmDevelopment', 'VmAcceptance', 'UserLive')]
        [string]$EnvironmentTier,

        [Parameter(Mandatory = $true)]
        [string]$SandboxRoot,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Paths,

        [Parameter(Mandatory = $true)]
        $Providers,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Policy,

        [AllowNull()]
        $AccessLedger
    )

    $actualPathNames = @($Paths.Keys | ForEach-Object { [string]$_ })
    if (-not (Test-CddsiExactNameSet -Actual $actualPathNames -Expected $script:CddsiContextPathNames)) {
        throw 'ExecutionContext.Paths must match the exact synthetic path schema.'
    }

    $actualPolicyNames = @($Policy.Keys | ForEach-Object { [string]$_ })
    if (-not (Test-CddsiExactNameSet -Actual $actualPolicyNames -Expected $script:CddsiContextPolicyNames)) {
        throw 'ExecutionContext.Policy must match the exact policy schema.'
    }

    $pathObject = [ordered]@{}
    foreach ($name in $script:CddsiContextPathNames) {
        $pathObject[$name] = [string]$Paths[$name]
    }

    $policyObject = [ordered]@{
        SchemaVersion            = $Policy['SchemaVersion']
        AllowLiveProvider        = $Policy['AllowLiveProvider']
        ForbiddenResourceTokens = @($Policy['ForbiddenResourceTokens'])
        CanaryTokens             = @($Policy['CanaryTokens'])
    }

    $initialProviderKindProperty = $Providers.PSObject.Properties['Kind']
    if ($null -eq $initialProviderKindProperty -or
        $initialProviderKindProperty.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
        -not $initialProviderKindProperty.IsGettable -or
        -not $initialProviderKindProperty.IsSettable -or
        $initialProviderKindProperty.Value -isnot [string]) {
        throw 'ExecutionContext provider construction requires Kind to be a settable NoteProperty.'
    }
    if ($initialProviderKindProperty.Value -ceq 'LiveReadOnly') {
        throw 'A fresh Live execution context must start with the Unloaded provider set.'
    }
    if ($null -eq $AccessLedger) {
        $AccessLedger = New-CddsiAccessLedger
    }

    $context = [pscustomobject][ordered]@{
        SchemaVersion   = 2
        RunId           = $RunId
        Mode            = $Mode
        Stage           = $Stage
        EnvironmentTier = $EnvironmentTier
        SandboxRoot     = $SandboxRoot
        Paths           = [pscustomobject]$pathObject
        Providers       = $Providers
        Policy          = [pscustomobject]$policyObject
        AccessLedger    = $AccessLedger
    }

    Assert-CddsiExecutionContext -ExecutionContext $context -ExpectedMode $Mode | Out-Null
    return $context
}

function Assert-CddsiExecutionContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$ExpectedMode
    )

    if ($null -eq $Context) {
        throw 'ExecutionContext is mandatory.'
    }

    $contextNames = @($Context.PSObject.Properties.Name)
    $requiredContextNames = @(
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
    if (-not (Test-CddsiExactNotePropertySet -InputObject $Context -Expected $requiredContextNames)) {
        throw 'ExecutionContext does not match the exact settable NoteProperty schema.'
    }
    if (($Context.SchemaVersion -isnot [int] -and $Context.SchemaVersion -isnot [long]) -or [long]$Context.SchemaVersion -ne 2) {
        throw 'ExecutionContext.SchemaVersion is unsupported.'
    }

    $parsedRunId = [guid]::Empty
    if ($Context.RunId -isnot [string] -or -not [guid]::TryParse($Context.RunId, [ref]$parsedRunId) -or $parsedRunId -eq [guid]::Empty) {
        throw 'ExecutionContext.RunId must be a non-empty GUID.'
    }
    if ($Context.RunId -cne $parsedRunId.ToString('D')) {
        throw 'ExecutionContext.RunId must be a canonical lowercase GUID.'
    }

    $allowedModes = @('TestSafe', 'DryRun', 'Live')
    if ($Context.Mode -isnot [string] -or $allowedModes -cnotcontains $Context.Mode) {
        throw 'ExecutionContext.Mode is invalid.'
    }
    if ($PSBoundParameters.ContainsKey('ExpectedMode') -and $Context.Mode -cne $ExpectedMode) {
        throw 'ExecutionContext.Mode does not match ExpectedMode.'
    }

    $allowedStages = @('Scaffold', 'Development', 'VmDevelopment', 'VmCalibration', 'VmAcceptance', 'UserLive')
    if ($Context.Stage -isnot [string] -or $allowedStages -cnotcontains $Context.Stage) {
        throw 'ExecutionContext.Stage is invalid.'
    }

    $allowedTiers = @('HostSandbox', 'CI', 'VmDevelopment', 'VmAcceptance', 'UserLive')
    if ($Context.EnvironmentTier -isnot [string] -or $allowedTiers -cnotcontains $Context.EnvironmentTier) {
        throw 'ExecutionContext.EnvironmentTier is invalid.'
    }

    if ($Context.SandboxRoot -isnot [string] -or [string]::IsNullOrWhiteSpace($Context.SandboxRoot) -or -not [System.IO.Path]::IsPathRooted($Context.SandboxRoot)) {
        throw 'ExecutionContext.SandboxRoot must be an explicit absolute path.'
    }
    $sandboxRoot = [System.IO.Path]::GetFullPath($Context.SandboxRoot).TrimEnd([char[]]@('\', '/'))
    if ([string]::IsNullOrWhiteSpace($sandboxRoot)) {
        throw 'ExecutionContext.SandboxRoot is invalid.'
    }

    if ($null -eq $Context.Paths) {
        throw 'ExecutionContext.Paths is mandatory.'
    }
    $pathNames = @($Context.Paths.PSObject.Properties.Name)
    if (-not (Test-CddsiExactNotePropertySet -InputObject $Context.Paths `
        -Expected $script:CddsiContextPathNames)) {
        throw 'ExecutionContext.Paths does not match the exact settable NoteProperty schema.'
    }
    foreach ($name in $script:CddsiContextPathNames) {
        $path = $Context.Paths.$name
        if ($path -isnot [string] -or [string]::IsNullOrWhiteSpace($path) -or -not [System.IO.Path]::IsPathRooted($path)) {
            throw ("ExecutionContext.Paths.{0} must be an absolute path." -f $name)
        }
        $fullPath = [System.IO.Path]::GetFullPath($path).TrimEnd([char[]]@('\', '/'))
        $requiredPrefix = $sandboxRoot + [System.IO.Path]::DirectorySeparatorChar
        if (-not $fullPath.StartsWith($requiredPrefix, [StringComparison]::OrdinalIgnoreCase)) {
            throw ("ExecutionContext.Paths.{0} must be inside SandboxRoot." -f $name)
        }
    }

    if ($null -eq $Context.Policy) {
        throw 'ExecutionContext.Policy is mandatory.'
    }
    $policyNames = @($Context.Policy.PSObject.Properties.Name)
    if (-not (Test-CddsiExactNotePropertySet -InputObject $Context.Policy `
        -Expected $script:CddsiContextPolicyNames)) {
        throw 'ExecutionContext.Policy does not match the exact settable NoteProperty schema.'
    }
    if (($Context.Policy.SchemaVersion -isnot [int] -and $Context.Policy.SchemaVersion -isnot [long]) -or [long]$Context.Policy.SchemaVersion -ne 1) {
        throw 'ExecutionContext.Policy.SchemaVersion is unsupported.'
    }
    if ($Context.Policy.AllowLiveProvider -isnot [bool]) {
        throw 'ExecutionContext.Policy.AllowLiveProvider must be Boolean.'
    }
    $allPolicyTokens = @()
    foreach ($tokenCollectionName in @('ForbiddenResourceTokens', 'CanaryTokens')) {
        $tokens = @($Context.Policy.$tokenCollectionName)
        if ($tokens.Count -eq 0) {
            throw ("ExecutionContext.Policy.{0} must not be empty." -f $tokenCollectionName)
        }
        foreach ($token in $tokens) {
            if (-not (Test-CddsiLogicalResourceToken -ResourceToken $token)) {
                throw ("ExecutionContext.Policy.{0} contains a non-logical token." -f $tokenCollectionName)
            }
            $allPolicyTokens += [string]$token
        }
    }
    if (@($allPolicyTokens | Sort-Object -Unique -CaseSensitive).Count -ne $allPolicyTokens.Count) {
        throw 'ExecutionContext.Policy resource tokens must be unique across all policy collections.'
    }

    if ($null -eq $Context.Providers) {
        throw 'ExecutionContext.Providers is mandatory.'
    }
    $providerSetKindProperty = $Context.Providers.PSObject.Properties['Kind']
    if ($null -eq $providerSetKindProperty -or
        $providerSetKindProperty.MemberType -ne [System.Management.Automation.PSMemberTypes]::NoteProperty -or
        -not $providerSetKindProperty.IsGettable -or -not $providerSetKindProperty.IsSettable -or
        $providerSetKindProperty.Value -isnot [string]) {
        throw 'ExecutionContext.Providers.Kind must be a settable NoteProperty.'
    }
    $providerSetKind = [string]$providerSetKindProperty.Value
    $providerSetNames = @($Context.Providers.PSObject.Properties.Name)
    if ($providerSetKind -ceq 'Fake' -or $providerSetKind -ceq 'Unloaded') {
        $providerStateNames = @('ExpectedCalls', 'FailureInjections')
        if ($providerSetKind -ceq 'Fake') {
            $providerStateNames += 'ScenarioBindingToken'
        }
        $providerStateNames += @('Cursor', 'MutationSpy')
        $requiredProviderSetNames = @('SchemaVersion', 'Kind') + $script:CddsiProviderNames +
            $providerStateNames
        if (-not (Test-CddsiExactNotePropertySet -InputObject $Context.Providers `
            -Expected $requiredProviderSetNames)) {
            throw 'ExecutionContext.Providers does not match the exact settable NoteProperty non-live provider-set schema.'
        }
        if (($Context.Providers.SchemaVersion -isnot [int] -and $Context.Providers.SchemaVersion -isnot [long]) -or
            [long]$Context.Providers.SchemaVersion -ne 1) {
            throw 'ExecutionContext.Providers.SchemaVersion is unsupported.'
        }
        if ($Context.Providers.Cursor -isnot [int] -or $Context.Providers.Cursor -lt 0 -or
            $Context.Providers.Cursor -gt @($Context.Providers.ExpectedCalls).Count) {
            throw 'ExecutionContext.Providers.Cursor is invalid.'
        }
        if ($Context.Providers.MutationSpy -isnot [System.Collections.IList]) {
            throw 'ExecutionContext.Providers.MutationSpy must be an in-memory list.'
        }
        foreach ($providerName in $script:CddsiProviderNames) {
            $providerContract = $Context.Providers.$providerName
            if ($null -eq $providerContract) {
                throw ("ExecutionContext.Providers.{0} is mandatory." -f $providerName)
            }
            $contractNames = @($providerContract.PSObject.Properties.Name)
            if (-not (Test-CddsiExactNotePropertySet -InputObject $providerContract `
                -Expected @('SchemaVersion', 'Name', 'Kind', 'IsLive'))) {
                throw ("ExecutionContext.Providers.{0} has an invalid settable NoteProperty non-live contract schema." -f $providerName)
            }
            if (($providerContract.SchemaVersion -isnot [int] -and $providerContract.SchemaVersion -isnot [long]) -or
                [long]$providerContract.SchemaVersion -ne 1) {
                throw ("ExecutionContext.Providers.{0} has an invalid schema version." -f $providerName)
            }
            if ($providerContract.Name -cne $providerName -or $providerContract.Kind -cne $providerSetKind -or
                $providerContract.IsLive -isnot [bool] -or $providerContract.IsLive) {
                throw ("ExecutionContext.Providers.{0} must match the non-live provider-set kind." -f $providerName)
            }
        }
        if ($providerSetKind -ceq 'Fake') {
            Assert-CddsiFakeProviderScenario -ProviderSet $Context.Providers | Out-Null
        }
    }
    elseif ($providerSetKind -ceq 'LiveReadOnly') {
        $requiredProviderSetNames = @(
            'SchemaVersion', 'Kind', 'RunId', 'Stage', 'EnvironmentTier', 'ArtifactProfile',
            'AdapterSha256', 'LoadOperationUseId', 'LoadReceiptBindingToken', 'CapabilitySetDigest'
        ) + $script:CddsiProviderNames
        if (-not (Test-CddsiExactNotePropertySet -InputObject $Context.Providers `
            -Expected $requiredProviderSetNames)) {
            throw 'ExecutionContext.Providers does not match the exact settable NoteProperty LiveReadOnly provider-set schema.'
        }
        if (($Context.Providers.SchemaVersion -isnot [int] -and $Context.Providers.SchemaVersion -isnot [long]) -or
            [long]$Context.Providers.SchemaVersion -ne 2) {
            throw 'ExecutionContext LiveReadOnly provider schema version is unsupported.'
        }
        $parsedLoadOperationUseId = [guid]::Empty
        if ($Context.Providers.RunId -isnot [string] -or $Context.Providers.RunId -cne $Context.RunId -or
            $Context.Providers.Stage -isnot [string] -or $Context.Providers.Stage -cne $Context.Stage -or
            $Context.Providers.EnvironmentTier -isnot [string] -or
            $Context.Providers.EnvironmentTier -cne $Context.EnvironmentTier -or
            $Context.Providers.ArtifactProfile -isnot [string] -or
            $Context.Providers.ArtifactProfile -cne $Context.Stage) {
            throw 'ExecutionContext LiveReadOnly provider binding does not match the context.'
        }
        $canonicalCapabilities = @(Get-CddsiLiveReadOnlyCapabilityContracts)
        [string[]]$canonicalCapabilityLines = @(
            $canonicalCapabilities |
                ForEach-Object {
                    '{0}|{1}|{2}|{3}|{4}' -f $_.Provider, $_.Operation, $_.ResourceToken,
                        (@($_.ArgumentNames) -join ','), $_.ResultSchemaId
                }
        )
        [System.Array]::Sort($canonicalCapabilityLines, [System.StringComparer]::Ordinal)
        $canonicalCapabilityBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
            ($canonicalCapabilityLines -join "`n")
        )
        $canonicalCapabilityHasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $canonicalCapabilityDigest = [System.BitConverter]::ToString(
                $canonicalCapabilityHasher.ComputeHash($canonicalCapabilityBytes)
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $canonicalCapabilityHasher.Dispose()
        }
        if ($canonicalCapabilityDigest -cne
            '26c9e8d095c7570df019d1758d277d6bc6b6161d88695f2b96f3350dcc4e942e') {
            throw 'ExecutionContext LiveReadOnly canonical capability source does not match the fixed digest.'
        }

        if ($Context.Providers.AdapterSha256 -isnot [string] -or
            $Context.Providers.AdapterSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Context.Providers.LoadReceiptBindingToken -isnot [string] -or
            $Context.Providers.LoadReceiptBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Context.Providers.CapabilitySetDigest -isnot [string] -or
            $Context.Providers.CapabilitySetDigest -cne $canonicalCapabilityDigest -or
            $Context.Providers.LoadOperationUseId -isnot [string] -or
            -not [guid]::TryParse($Context.Providers.LoadOperationUseId, [ref]$parsedLoadOperationUseId) -or
            $parsedLoadOperationUseId -eq [guid]::Empty -or
            $Context.Providers.LoadOperationUseId -cne $parsedLoadOperationUseId.ToString('D')) {
            throw 'ExecutionContext LiveReadOnly provider evidence binding is invalid.'
        }

        $capabilityCount = 0
        [string[]]$actualCapabilityLines = @()
        foreach ($providerName in $script:CddsiProviderNames) {
            $providerContract = $Context.Providers.$providerName
            if ($null -eq $providerContract) {
                throw ("ExecutionContext.Providers.{0} is mandatory." -f $providerName)
            }
            $contractNames = @($providerContract.PSObject.Properties.Name)
            if (-not (Test-CddsiExactNotePropertySet -InputObject $providerContract -Expected @(
                'SchemaVersion', 'Name', 'Kind', 'IsLive', 'Access', 'Capabilities'
            ))) {
                throw ("ExecutionContext.Providers.{0} has an invalid settable NoteProperty LiveReadOnly contract schema." -f $providerName)
            }
            if (($providerContract.SchemaVersion -isnot [int] -and $providerContract.SchemaVersion -isnot [long]) -or
                [long]$providerContract.SchemaVersion -ne 2 -or
                $providerContract.Name -isnot [string] -or $providerContract.Name -cne $providerName -or
                $providerContract.Kind -isnot [string] -or $providerContract.Kind -cne 'LiveReadOnly' -or
                $providerContract.IsLive -isnot [bool] -or -not $providerContract.IsLive -or
                $providerContract.Access -isnot [string] -or $providerContract.Access -cne 'ReadOnly' -or
                $providerContract.Capabilities -isnot [System.Array]) {
                throw ("ExecutionContext.Providers.{0} has an invalid LiveReadOnly identity." -f $providerName)
            }

            $expectedCapabilities = @(
                $canonicalCapabilities |
                    Where-Object { $_.Provider -ceq $providerName }
            )
            $actualCapabilities = @($providerContract.Capabilities)
            if ($actualCapabilities.Count -ne $expectedCapabilities.Count) {
                throw ("ExecutionContext.Providers.{0} has an invalid capability count." -f $providerName)
            }
            for ($capabilityIndex = 0; $capabilityIndex -lt $expectedCapabilities.Count; $capabilityIndex++) {
                $actualCapability = $actualCapabilities[$capabilityIndex]
                $expectedCapability = $expectedCapabilities[$capabilityIndex]
                if ($null -eq $actualCapability -or -not (Test-CddsiExactNotePropertySet `
                    -InputObject $actualCapability `
                    -Expected @('SchemaVersion', 'Operation', 'ResourceToken', 'ArgumentNames', 'ResultSchemaId')) -or
                    ($actualCapability.SchemaVersion -isnot [int] -and
                        $actualCapability.SchemaVersion -isnot [long]) -or
                    [long]$actualCapability.SchemaVersion -ne 1 -or
                    $actualCapability.Operation -isnot [string] -or
                    $actualCapability.Operation -cne $expectedCapability.Operation -or
                    $actualCapability.ResourceToken -isnot [string] -or
                    $actualCapability.ResourceToken -cne $expectedCapability.ResourceToken -or
                    $actualCapability.ResultSchemaId -isnot [string] -or
                    $actualCapability.ResultSchemaId -cne $expectedCapability.ResultSchemaId -or
                    $actualCapability.ArgumentNames -isnot [System.Array] -or
                    -not (Test-CddsiExactNameSet -Actual @($actualCapability.ArgumentNames) `
                        -Expected @($expectedCapability.ArgumentNames))) {
                    throw ("ExecutionContext.Providers.{0} has an invalid capability contract." -f $providerName)
                }
                $actualCapabilityLines += '{0}|{1}|{2}|{3}|{4}' -f $providerName,
                    $actualCapability.Operation, $actualCapability.ResourceToken,
                    (@($actualCapability.ArgumentNames) -join ','),
                    $actualCapability.ResultSchemaId
                $capabilityCount++
            }
        }
        if ($capabilityCount -ne 11) {
            throw 'ExecutionContext LiveReadOnly provider capability set must contain exactly eleven contracts.'
        }
        [System.Array]::Sort($actualCapabilityLines, [System.StringComparer]::Ordinal)
        $actualCapabilityBytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
            ($actualCapabilityLines -join "`n")
        )
        $actualCapabilityHasher = [System.Security.Cryptography.SHA256]::Create()
        try {
            $actualCapabilityDigest = [System.BitConverter]::ToString(
                $actualCapabilityHasher.ComputeHash($actualCapabilityBytes)
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $actualCapabilityHasher.Dispose()
        }
        if ($actualCapabilityDigest -cne $canonicalCapabilityDigest -or
            $actualCapabilityDigest -cne $Context.Providers.CapabilitySetDigest) {
            throw 'ExecutionContext LiveReadOnly actual capability set does not match the fixed digest.'
        }
    }
    else {
        throw 'ExecutionContext.Providers.Kind is unsupported.'
    }

    if ($Context.Mode -in @('TestSafe', 'DryRun')) {
        if ($providerSetKind -cne 'Fake' -or $Context.Policy.AllowLiveProvider) {
            throw 'TestSafe and DryRun require the non-live Fake provider set and deny live-provider authorization.'
        }
    }
    else {
        $liveStageTiers = @{
            VmDevelopment = 'VmDevelopment'
            VmAcceptance  = 'VmAcceptance'
            UserLive      = 'UserLive'
        }
        if (-not $liveStageTiers.ContainsKey($Context.Stage) -or
            $Context.EnvironmentTier -cne $liveStageTiers[$Context.Stage]) {
            throw 'Live requires an exact authorized stage and environment-tier pair.'
        }
        if (-not $Context.Policy.AllowLiveProvider -or
            -not ($providerSetKind -ceq 'Unloaded' -or
                $providerSetKind -ceq 'LiveReadOnly')) {
            throw 'Live context requires explicit provider-load permission and an authorized provider state.'
        }
        if ($providerSetKind -ceq 'Unloaded' -and
            (@($Context.Providers.ExpectedCalls).Count -ne 0 -or
                @($Context.Providers.FailureInjections).Count -ne 0 -or
                $Context.Providers.Cursor -ne 0 -or
                @($Context.Providers.MutationSpy).Count -ne 0)) {
            throw 'The Unloaded provider set must not contain executable fake-provider state.'
        }
    }

    if ($null -eq $Context.AccessLedger) {
        throw 'ExecutionContext.AccessLedger is mandatory.'
    }
    $ledgerNames = @($Context.AccessLedger.PSObject.Properties.Name)
    $requiredLedgerNames = @(
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
    if (-not (Test-CddsiExactNotePropertySet -InputObject $Context.AccessLedger `
        -Expected $requiredLedgerNames)) {
        throw 'ExecutionContext.AccessLedger does not match the exact settable NoteProperty schema.'
    }
    if (($Context.AccessLedger.SchemaVersion -isnot [int] -and $Context.AccessLedger.SchemaVersion -isnot [long]) -or [long]$Context.AccessLedger.SchemaVersion -ne 1 -or $Context.AccessLedger.Plane -cne 'Product') {
        throw 'ExecutionContext.AccessLedger identity is invalid.'
    }
    if ($Context.AccessLedger.Entries -isnot [System.Collections.IList]) {
        throw 'ExecutionContext.AccessLedger.Entries must be an in-memory list.'
    }
    if ($providerSetKind -ceq 'Unloaded' -and $Context.AccessLedger.Entries.Count -ne 0) {
        throw 'The Unloaded provider set must never contain a product access-ledger entry.'
    }
    foreach ($counterName in @('UnexpectedEntryCount', 'ForbiddenResourceAccessCount', 'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount', 'ProductNetworkRequestCount', 'RealRegistryAccessCount')) {
        $counter = $Context.AccessLedger.$counterName
        if (($counter -isnot [int] -and $counter -isnot [long]) -or [long]$counter -lt 0) {
            throw ("ExecutionContext.AccessLedger.{0} must be a non-negative integer." -f $counterName)
        }
    }
    $ledgerEntryNames = @(
        'Sequence', 'Plane', 'Provider', 'Operation', 'ResourceToken', 'ArgumentCount',
        'Allowed', 'Expected', 'IsMutation', 'FailureInjected', 'Outcome', 'ErrorCode',
        'ProviderEvidenceDigest', 'InvocationBindingToken'
    )
    $fakeConsumedExpectedCallCount = 0
    $fakeDeniedEntryCount = 0
    $liveDeniedEntryCount = 0
    $fakeMutationLedgerEntries = [System.Collections.ArrayList]@()
    for ($entryIndex = 0; $entryIndex -lt $Context.AccessLedger.Entries.Count; $entryIndex++) {
        $entry = $Context.AccessLedger.Entries[$entryIndex]
        if ($null -eq $entry -or -not (Test-CddsiExactNotePropertySet `
            -InputObject $entry -Expected $ledgerEntryNames)) {
            throw 'ExecutionContext.AccessLedger contains an invalid settable NoteProperty entry schema.'
        }
        if (($entry.Sequence -isnot [int] -and $entry.Sequence -isnot [long]) -or
            [long]$entry.Sequence -ne ($entryIndex + 1) -or
            $entry.Plane -isnot [string] -or $entry.Plane -cne 'Product') {
            throw 'ExecutionContext.AccessLedger contains an invalid entry value.'
        }
        $entryExpectedCallSequence = $null
        if ($providerSetKind -ceq 'Fake' -and
            ($entry.Outcome -ceq 'Allowed' -or $entry.Outcome -ceq 'InjectedFailure')) {
            $fakeConsumedExpectedCallCount++
            $entryExpectedCallSequence = $fakeConsumedExpectedCallCount
        }
        elseif ($providerSetKind -ceq 'Fake' -and
            $entry.Outcome -ceq 'Denied' -and
            $entry.ErrorCode -ceq 'sequence_mismatch') {
            $entryExpectedCallSequence = $fakeConsumedExpectedCallCount + 1
        }
        Assert-CddsiProductAccessLedgerEntryValues -ProviderSet $Context.Providers `
            -Provider $entry.Provider -Operation $entry.Operation `
            -ResourceToken $entry.ResourceToken -ArgumentCount $entry.ArgumentCount `
            -Allowed $entry.Allowed -Expected $entry.Expected -IsMutation $entry.IsMutation `
            -FailureInjected $entry.FailureInjected -Outcome $entry.Outcome `
            -ErrorCode $entry.ErrorCode `
            -ProviderEvidenceDigest $entry.ProviderEvidenceDigest `
            -InvocationBindingToken $entry.InvocationBindingToken `
            -ExpectedCallSequence $entryExpectedCallSequence | Out-Null

        if ($providerSetKind -ceq 'Fake') {
            if ($entry.Outcome -ceq 'Denied') {
                $fakeDeniedEntryCount++
                $expectedDeniedErrorCode = if (-not (Test-CddsiFakeResourceTokenAllowed `
                    -Policy $Context.Policy -ResourceToken $entry.ResourceToken)) {
                    'forbidden_resource'
                }
                elseif ($fakeConsumedExpectedCallCount -ge @($Context.Providers.ExpectedCalls).Count) {
                    'default_deny'
                }
                else {
                    'sequence_mismatch'
                }
                if ($entry.ErrorCode -cne $expectedDeniedErrorCode) {
                    throw 'ExecutionContext Fake denied entry does not match its exact fail-closed branch.'
                }
            }
            if ($entry.IsMutation) {
                [void]$fakeMutationLedgerEntries.Add($entry)
            }
        }
        elseif ($providerSetKind -ceq 'LiveReadOnly' -and $entry.Outcome -ceq 'Denied') {
            $liveDeniedEntryCount++
        }
    }
    if ($providerSetKind -ceq 'Fake') {
        if ([int]$Context.Providers.Cursor -ne $fakeConsumedExpectedCallCount) {
            throw 'ExecutionContext Fake provider cursor does not match the auditable ledger call sequence.'
        }
        if ([long]$Context.AccessLedger.UnexpectedEntryCount -ne $fakeDeniedEntryCount -or
            [long]$Context.AccessLedger.ForbiddenResourceAccessCount -ne $fakeDeniedEntryCount) {
            throw 'ExecutionContext Fake denied counters do not match the exact denied ledger count.'
        }
        foreach ($realCounterName in @(
            'OutsideSandboxWriteCount',
            'ProductLiveProcessSpawnCount',
            'ProductNetworkRequestCount',
            'RealRegistryAccessCount'
        )) {
            if ([long]$Context.AccessLedger.$realCounterName -ne 0) {
                throw ("ExecutionContext Fake provider requires {0} to remain zero." -f $realCounterName)
            }
        }
        if ($Context.Providers.MutationSpy.Count -ne $fakeMutationLedgerEntries.Count) {
            throw 'ExecutionContext Fake mutation spy count does not match the mutation ledger.'
        }
        for ($mutationIndex = 0; $mutationIndex -lt $fakeMutationLedgerEntries.Count; $mutationIndex++) {
            $spyEntry = $Context.Providers.MutationSpy[$mutationIndex]
            $ledgerMutationEntry = $fakeMutationLedgerEntries[$mutationIndex]
            if ($null -eq $spyEntry -or
                -not (Test-CddsiExactNotePropertySet -InputObject $spyEntry `
                    -Expected @('Sequence', 'Provider', 'Operation', 'ResourceToken')) -or
                ($spyEntry.Sequence -isnot [int] -and $spyEntry.Sequence -isnot [long]) -or
                [long]$spyEntry.Sequence -ne [long]$ledgerMutationEntry.Sequence -or
                $spyEntry.Provider -isnot [string] -or
                $spyEntry.Provider -cne $ledgerMutationEntry.Provider -or
                $spyEntry.Operation -isnot [string] -or
                $spyEntry.Operation -cne $ledgerMutationEntry.Operation -or
                $spyEntry.ResourceToken -isnot [string] -or
                $spyEntry.ResourceToken -cne $ledgerMutationEntry.ResourceToken) {
                throw 'ExecutionContext Fake mutation spy does not exactly match the mutation ledger.'
            }
        }
    }
    elseif ($providerSetKind -ceq 'LiveReadOnly') {
        if ([long]$Context.AccessLedger.UnexpectedEntryCount -ne $liveDeniedEntryCount -or
            [long]$Context.AccessLedger.ForbiddenResourceAccessCount -ne $liveDeniedEntryCount) {
            throw 'ExecutionContext LiveReadOnly denied counters do not match the exact denied ledger count.'
        }
    }
    elseif ($providerSetKind -ceq 'Unloaded') {
        if ([long]$Context.AccessLedger.UnexpectedEntryCount -ne 0 -or
            [long]$Context.AccessLedger.ForbiddenResourceAccessCount -ne 0) {
            throw 'ExecutionContext Unloaded provider counters must remain zero.'
        }
    }
    $expectedLiveProviderLoaded = $providerSetKind -ceq 'LiveReadOnly'
    if ($Context.AccessLedger.LiveProviderLoaded -isnot [bool] -or
        $Context.AccessLedger.LiveProviderLoaded -ne $expectedLiveProviderLoaded) {
        throw 'ExecutionContext.AccessLedger.LiveProviderLoaded does not match the provider-set state.'
    }

    return $true
}

function Get-CddsiExecutionPathTokenValues {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    return [ordered]@{
        '%LOCALAPPDATA%' = $Context.Paths.LocalAppData
        '%USERPROFILE%'  = $Context.Paths.UserProfile
        '%USERNAME%'     = 'SyntheticUser'
        '%TEMP%'         = $Context.Paths.Temp
    }
}

function Invoke-CddsiProviderOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [Parameter(Mandatory = $true)]
        [ValidateSet('FileSystem', 'Environment', 'Registry', 'Process', 'Network', 'Package', 'Feature', 'Service', 'Credential', 'Clock')]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$ResourceToken,

        [System.Collections.IDictionary]$Arguments = ([ordered]@{})
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null

    if ($script:CddsiProviderNames -cnotcontains $Provider) {
        throw 'Provider name casing or value is invalid.'
    }
    if ($Operation -notmatch '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$') {
        throw 'Provider operation name is invalid.'
    }

    $providerContract = switch -CaseSensitive ($Provider) {
        'FileSystem' { $Context.Providers.FileSystem; break }
        'Environment' { $Context.Providers.Environment; break }
        'Registry' { $Context.Providers.Registry; break }
        'Process' { $Context.Providers.Process; break }
        'Network' { $Context.Providers.Network; break }
        'Package' { $Context.Providers.Package; break }
        'Feature' { $Context.Providers.Feature; break }
        'Service' { $Context.Providers.Service; break }
        'Credential' { $Context.Providers.Credential; break }
        'Clock' { $Context.Providers.Clock; break }
        default { throw 'Provider is not supported.' }
    }

    if ($providerContract.Kind -ceq 'Unloaded' -and -not $providerContract.IsLive) {
        throw 'LIVE_PROVIDER_NOT_LOADED'
    }
    if ($providerContract.Kind -ceq 'Fake' -and -not $providerContract.IsLive) {
        return Invoke-CddsiFakeProviderOperation -ExecutionContext $Context -Provider $Provider `
            -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments
    }
    if ($providerContract.Kind -ceq 'LiveReadOnly' -and $providerContract.IsLive) {
        # No trusted source/definition binding exists for an ambient adapter
        # function yet.  Never dispatch by name until that provenance contract
        # is implemented and independently reviewed.
        throw 'LIVE_READ_ONLY_ADAPTER_SOURCE_UNBOUND'
    }
    throw 'Provider dispatcher rejected an invalid provider contract.'
}

function Get-CddsiIsolationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [ValidateRange(0, 2147483647)]
        [int]$UnapprovedHarnessProcessCount = 0,

        [ValidateRange(0, 2147483647)]
        [int]$UnapprovedHarnessNetworkCount = 0,

        [ValidateRange(0, 2147483647)]
        [int]$SecretFindings = 0,

        [bool]$RepositoryContentChanged = $false
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null

    $ledger = $Context.AccessLedger
    $remainingExpectedCalls = 0
    $mutationViolationCount = 0
    if ($Context.Providers.Kind -ceq 'Fake') {
        $remainingExpectedCalls = @($Context.Providers.ExpectedCalls).Count - [int]$Context.Providers.Cursor
    }
    if ($Context.Mode -in @('TestSafe', 'DryRun') -and $Context.Providers.Kind -ceq 'Fake') {
        $mutationViolationCount = @($Context.Providers.MutationSpy).Count
    }

    return [pscustomobject][ordered]@{
        LIVE_PROVIDER_LOADED                  = [bool]$ledger.LiveProviderLoaded
        FORBIDDEN_RESOURCE_ACCESS_COUNT       = [int]$ledger.ForbiddenResourceAccessCount
        OUTSIDE_SANDBOX_WRITE_COUNT           = [int]$ledger.OutsideSandboxWriteCount
        PRODUCT_LIVE_PROCESS_SPAWN_COUNT      = [int]$ledger.ProductLiveProcessSpawnCount
        PRODUCT_NETWORK_REQUEST_COUNT         = [int]$ledger.ProductNetworkRequestCount
        REAL_REGISTRY_ACCESS_COUNT            = [int]$ledger.RealRegistryAccessCount
        UNAPPROVED_HARNESS_PROCESS_COUNT      = $UnapprovedHarnessProcessCount
        UNAPPROVED_HARNESS_NETWORK_COUNT      = $UnapprovedHarnessNetworkCount
        SECRET_FINDINGS                       = $SecretFindings
        UNEXPECTED_LEDGER_ENTRY_COUNT         = [int]$ledger.UnexpectedEntryCount + [int]$remainingExpectedCalls + [int]$mutationViolationCount
        REPOSITORY_CONTENT_CHANGED            = $RepositoryContentChanged
    }
}

function Assert-CddsiIsolationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Evidence
    )

    if ($null -eq $Evidence) {
        throw 'Isolation evidence is mandatory.'
    }

    $requiredNames = @(
        'LIVE_PROVIDER_LOADED',
        'FORBIDDEN_RESOURCE_ACCESS_COUNT',
        'OUTSIDE_SANDBOX_WRITE_COUNT',
        'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
        'PRODUCT_NETWORK_REQUEST_COUNT',
        'REAL_REGISTRY_ACCESS_COUNT',
        'UNAPPROVED_HARNESS_PROCESS_COUNT',
        'UNAPPROVED_HARNESS_NETWORK_COUNT',
        'SECRET_FINDINGS',
        'UNEXPECTED_LEDGER_ENTRY_COUNT',
        'REPOSITORY_CONTENT_CHANGED'
    )
    $actualNames = @($Evidence.PSObject.Properties.Name)
    if (-not (Test-CddsiExactNameSet -Actual $actualNames -Expected $requiredNames)) {
        throw 'Isolation evidence does not match the exact schema.'
    }
    if ($Evidence.LIVE_PROVIDER_LOADED -isnot [bool] -or $Evidence.REPOSITORY_CONTENT_CHANGED -isnot [bool]) {
        throw 'Isolation evidence Boolean fields have invalid types.'
    }
    if ($Evidence.LIVE_PROVIDER_LOADED -or $Evidence.REPOSITORY_CONTENT_CHANGED) {
        throw 'Isolation evidence contains a forbidden true value.'
    }
    foreach ($counterName in @(
        'FORBIDDEN_RESOURCE_ACCESS_COUNT',
        'OUTSIDE_SANDBOX_WRITE_COUNT',
        'PRODUCT_LIVE_PROCESS_SPAWN_COUNT',
        'PRODUCT_NETWORK_REQUEST_COUNT',
        'REAL_REGISTRY_ACCESS_COUNT',
        'UNAPPROVED_HARNESS_PROCESS_COUNT',
        'UNAPPROVED_HARNESS_NETWORK_COUNT',
        'SECRET_FINDINGS',
        'UNEXPECTED_LEDGER_ENTRY_COUNT'
    )) {
        $value = $Evidence.$counterName
        if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -ne 0) {
            throw ("Isolation evidence field {0} must be the integer zero." -f $counterName)
        }
    }

    return $true
}
