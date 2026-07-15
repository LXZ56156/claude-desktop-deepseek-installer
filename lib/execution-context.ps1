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
        [ValidateSet('Allowed', 'Denied', 'InjectedFailure')]
        [string]$Outcome,

        [string]$ErrorCode = ''
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null

    $safeResourceToken = if (Test-CddsiLogicalResourceToken -ResourceToken $ResourceToken) {
        $ResourceToken
    }
    else {
        '<INVALID_RESOURCE_TOKEN>'
    }

    if (-not [string]::IsNullOrEmpty($ErrorCode) -and $ErrorCode -notmatch '^[A-Za-z][A-Za-z0-9_.-]{0,63}$') {
        throw 'Access-ledger ErrorCode is not a safe identifier.'
    }

    $ledger = $Context.AccessLedger
    $entry = [pscustomobject][ordered]@{
        Sequence        = [int]$ledger.Entries.Count + 1
        Plane           = 'Product'
        Provider        = $Provider
        Operation       = $Operation
        ResourceToken   = $safeResourceToken
        ArgumentCount   = [int]$Arguments.Count
        Allowed         = $Allowed
        Expected        = $Expected
        IsMutation      = $IsMutation
        FailureInjected = $FailureInjected
        Outcome         = $Outcome
        ErrorCode       = $ErrorCode
    }
    [void]$ledger.Entries.Add($entry)
    return $entry
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
        [ValidateSet('HostSandbox', 'CI', 'VmAcceptance', 'UserLive')]
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

    if ($null -eq $AccessLedger) {
        $AccessLedger = New-CddsiAccessLedger -LiveProviderLoaded:($Providers.Kind -ceq 'Live')
    }

    $context = [pscustomobject][ordered]@{
        SchemaVersion   = 1
        RunId           = $RunId
        Mode            = $Mode
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
        'EnvironmentTier',
        'SandboxRoot',
        'Paths',
        'Providers',
        'Policy',
        'AccessLedger'
    )
    if (-not (Test-CddsiExactNameSet -Actual $contextNames -Expected $requiredContextNames)) {
        throw 'ExecutionContext does not match the exact schema.'
    }
    if (($Context.SchemaVersion -isnot [int] -and $Context.SchemaVersion -isnot [long]) -or [long]$Context.SchemaVersion -ne 1) {
        throw 'ExecutionContext.SchemaVersion is unsupported.'
    }

    $parsedRunId = [guid]::Empty
    if ($Context.RunId -isnot [string] -or -not [guid]::TryParse($Context.RunId, [ref]$parsedRunId) -or $parsedRunId -eq [guid]::Empty) {
        throw 'ExecutionContext.RunId must be a non-empty GUID.'
    }

    $allowedModes = @('TestSafe', 'DryRun', 'Live')
    if ($Context.Mode -isnot [string] -or $allowedModes -cnotcontains $Context.Mode) {
        throw 'ExecutionContext.Mode is invalid.'
    }
    if ($PSBoundParameters.ContainsKey('ExpectedMode') -and $Context.Mode -cne $ExpectedMode) {
        throw 'ExecutionContext.Mode does not match ExpectedMode.'
    }

    $allowedTiers = @('HostSandbox', 'CI', 'VmAcceptance', 'UserLive')
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
    if (-not (Test-CddsiExactNameSet -Actual $pathNames -Expected $script:CddsiContextPathNames)) {
        throw 'ExecutionContext.Paths does not match the exact schema.'
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
    if (-not (Test-CddsiExactNameSet -Actual $policyNames -Expected $script:CddsiContextPolicyNames)) {
        throw 'ExecutionContext.Policy does not match the exact schema.'
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
    $providerSetNames = @($Context.Providers.PSObject.Properties.Name)
    $requiredProviderSetNames = @('SchemaVersion', 'Kind') + $script:CddsiProviderNames + @('ExpectedCalls', 'FailureInjections', 'Cursor', 'MutationSpy')
    if (-not (Test-CddsiExactNameSet -Actual $providerSetNames -Expected $requiredProviderSetNames)) {
        throw 'ExecutionContext.Providers does not match the exact provider-set schema.'
    }
    if (($Context.Providers.SchemaVersion -isnot [int] -and $Context.Providers.SchemaVersion -isnot [long]) -or [long]$Context.Providers.SchemaVersion -ne 1) {
        throw 'ExecutionContext.Providers.SchemaVersion is unsupported.'
    }
    if ($Context.Providers.Kind -cne 'Fake') {
        throw 'P1 permits only the Fake provider set.'
    }
    if ($Context.Mode -ceq 'Live' -or $Context.Policy.AllowLiveProvider) {
        throw 'P1 forbids Live execution and live-provider authorization.'
    }
    if ($Context.Providers.Cursor -isnot [int] -or $Context.Providers.Cursor -lt 0 -or $Context.Providers.Cursor -gt @($Context.Providers.ExpectedCalls).Count) {
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
        if (-not (Test-CddsiExactNameSet -Actual $contractNames -Expected @('SchemaVersion', 'Name', 'Kind', 'IsLive'))) {
            throw ("ExecutionContext.Providers.{0} has an invalid contract schema." -f $providerName)
        }
        if (($providerContract.SchemaVersion -isnot [int] -and $providerContract.SchemaVersion -isnot [long]) -or [long]$providerContract.SchemaVersion -ne 1) {
            throw ("ExecutionContext.Providers.{0} has an invalid schema version." -f $providerName)
        }
        if ($providerContract.Name -cne $providerName -or $providerContract.Kind -cne 'Fake' -or $providerContract.IsLive -isnot [bool] -or $providerContract.IsLive) {
            throw ("ExecutionContext.Providers.{0} must be a non-live Fake provider." -f $providerName)
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
    if (-not (Test-CddsiExactNameSet -Actual $ledgerNames -Expected $requiredLedgerNames)) {
        throw 'ExecutionContext.AccessLedger does not match the exact schema.'
    }
    if (($Context.AccessLedger.SchemaVersion -isnot [int] -and $Context.AccessLedger.SchemaVersion -isnot [long]) -or [long]$Context.AccessLedger.SchemaVersion -ne 1 -or $Context.AccessLedger.Plane -cne 'Product') {
        throw 'ExecutionContext.AccessLedger identity is invalid.'
    }
    if ($Context.AccessLedger.Entries -isnot [System.Collections.IList]) {
        throw 'ExecutionContext.AccessLedger.Entries must be an in-memory list.'
    }
    foreach ($counterName in @('UnexpectedEntryCount', 'ForbiddenResourceAccessCount', 'OutsideSandboxWriteCount', 'ProductLiveProcessSpawnCount', 'ProductNetworkRequestCount', 'RealRegistryAccessCount')) {
        $counter = $Context.AccessLedger.$counterName
        if (($counter -isnot [int] -and $counter -isnot [long]) -or [long]$counter -lt 0) {
            throw ("ExecutionContext.AccessLedger.{0} must be a non-negative integer." -f $counterName)
        }
    }
    if ($Context.AccessLedger.LiveProviderLoaded -isnot [bool] -or $Context.AccessLedger.LiveProviderLoaded) {
        throw 'P1 requires LIVE_PROVIDER_LOADED = false.'
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

    if ($providerContract.Kind -cne 'Fake' -or $providerContract.IsLive) {
        throw 'Only non-live Fake providers may execute in P1.'
    }

    return Invoke-CddsiFakeProviderOperation -ExecutionContext $Context -Provider $Provider -Operation $Operation -ResourceToken $ResourceToken -Arguments $Arguments
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
    $remainingExpectedCalls = @($Context.Providers.ExpectedCalls).Count - [int]$Context.Providers.Cursor
    $mutationViolationCount = 0
    if ($Context.Mode -in @('TestSafe', 'DryRun')) {
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
