# desktop-env-check.ps1 - Synthetic Windows and virtualization observations.
# All observations are supplied by the mandatory ExecutionContext provider set.

function Get-CddsiDesktopEnvironmentSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][ValidateRange(1, 2147483647)][int]$MinimumBuild,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$SupportedArchitectures
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $architectures = @($SupportedArchitectures)
    if (
        $architectures.Count -eq 0 -or
        @($architectures | Sort-Object -Unique -CaseSensitive).Count -ne $architectures.Count -or
        @($architectures | Where-Object { @('x64', 'arm64') -cnotcontains $_ }).Count -ne 0
    ) {
        throw 'SupportedArchitectures must be a unique non-empty subset of x64 and arm64.'
    }

    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion           = 1
        Platform                = 'Unknown'
        BuildNumber             = $null
        Architecture            = 'Unknown'
        IsAdministrator         = $false
        AdministratorCapability = 'UNKNOWN'
        CapabilityStatus        = 'UNKNOWN'
        ReasonCodes             = @('ENVIRONMENT_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Environment -Operation Inspect -ResourceToken '<ENVIRONMENT:WINDOWS>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectWindowsEnvironment' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'ENVIRONMENT_PROVIDER_FAILED' -MessageSafe 'Synthetic Windows environment provider failed closed.' -Data $unknownData
    }

    $valid = (
        (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'Platform', 'BuildNumber', 'Architecture', 'IsAdministrator')) -and
        $observation.SchemaVersion -is [int] -and $observation.SchemaVersion -eq 1 -and
        $observation.Platform -is [string] -and @('Windows', 'Other') -ccontains $observation.Platform -and
        ($observation.BuildNumber -is [int] -or $observation.BuildNumber -is [long]) -and [long]$observation.BuildNumber -ge 0 -and
        $observation.Architecture -is [string] -and @('x64', 'arm64', 'Other') -ccontains $observation.Architecture -and
        $observation.IsAdministrator -is [bool]
    )
    if (-not $valid) {
        $unknownData.ReasonCodes = @('ENVIRONMENT_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectWindowsEnvironment' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'ENVIRONMENT_RESULT_INVALID' -MessageSafe 'Synthetic Windows environment result did not match the exact schema.' -Data $unknownData
    }

    $reasons = @()
    if ($observation.Platform -cne 'Windows') { $reasons += 'WINDOWS_REQUIRED' }
    if ([long]$observation.BuildNumber -lt $MinimumBuild) { $reasons += 'WINDOWS_BUILD_UNSUPPORTED' }
    if ($architectures -cnotcontains $observation.Architecture) { $reasons += 'ARCHITECTURE_UNSUPPORTED' }
    $capabilityStatus = if ($reasons.Count -eq 0) { 'READY' } else { 'BLOCKED' }
    if ($reasons.Count -eq 0) { $reasons = @('WINDOWS_ENVIRONMENT_READY') }

    $data = [pscustomobject][ordered]@{
        SchemaVersion           = 1
        Platform                = $observation.Platform
        BuildNumber             = [long]$observation.BuildNumber
        Architecture            = $observation.Architecture
        IsAdministrator         = [bool]$observation.IsAdministrator
        AdministratorCapability = if ($observation.IsAdministrator) { 'AVAILABLE' } else { 'UNAVAILABLE' }
        CapabilityStatus        = $capabilityStatus
        ReasonCodes             = @($reasons)
    }
    return New-CddsiOperationResult -Operation 'DetectWindowsEnvironment' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Windows environment observation completed.' -Data $data
}

function Test-CddsiVirtualMachinePlatform {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        State            = 'Unknown'
        CapabilityStatus = 'UNKNOWN'
        ReasonCodes      = @('VMP_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Feature -Operation Inspect -ResourceToken '<FEATURE:VIRTUAL_MACHINE_PLATFORM>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectVirtualMachinePlatform' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'VMP_PROVIDER_FAILED' -MessageSafe 'Synthetic VirtualMachinePlatform provider failed closed.' -Data $unknownData
    }

    if (
        -not (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'State')) -or
        $observation.SchemaVersion -isnot [int] -or $observation.SchemaVersion -ne 1 -or
        $observation.State -isnot [string] -or @('Enabled', 'Disabled', 'PendingRestart', 'Unknown') -cnotcontains $observation.State
    ) {
        $unknownData.ReasonCodes = @('VMP_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectVirtualMachinePlatform' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'VMP_RESULT_INVALID' -MessageSafe 'Synthetic VirtualMachinePlatform result did not match the exact schema.' -Data $unknownData
    }

    $capabilityStatus = switch -CaseSensitive ($observation.State) {
        'Enabled' { 'READY'; break }
        'Disabled' { 'BLOCKED'; break }
        'PendingRestart' { 'PENDING_RESTART'; break }
        default { 'UNKNOWN'; break }
    }
    $reasonCode = switch -CaseSensitive ($observation.State) {
        'Enabled' { 'VMP_READY'; break }
        'Disabled' { 'VMP_DISABLED'; break }
        'PendingRestart' { 'VMP_RESTART_REQUIRED'; break }
        default { 'VMP_STATE_UNKNOWN'; break }
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        State            = $observation.State
        CapabilityStatus = $capabilityStatus
        ReasonCodes      = @($reasonCode)
    }
    return New-CddsiOperationResult -Operation 'DetectVirtualMachinePlatform' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic VirtualMachinePlatform observation completed.' -Data $data
}

function Test-CddsiHardwareVirtualization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        State            = 'Unknown'
        CapabilityStatus = 'UNKNOWN'
        ReasonCodes      = @('HARDWARE_VIRTUALIZATION_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Environment -Operation Inspect -ResourceToken '<ENVIRONMENT:HARDWARE_VIRTUALIZATION>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectHardwareVirtualization' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'HARDWARE_VIRTUALIZATION_PROVIDER_FAILED' -MessageSafe 'Synthetic hardware virtualization provider failed closed.' -Data $unknownData
    }

    if (
        -not (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'State')) -or
        $observation.SchemaVersion -isnot [int] -or $observation.SchemaVersion -ne 1 -or
        $observation.State -isnot [string] -or @('Enabled', 'Disabled', 'Unknown') -cnotcontains $observation.State
    ) {
        $unknownData.ReasonCodes = @('HARDWARE_VIRTUALIZATION_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectHardwareVirtualization' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'HARDWARE_VIRTUALIZATION_RESULT_INVALID' -MessageSafe 'Synthetic hardware virtualization result did not match the exact schema.' -Data $unknownData
    }

    $capabilityStatus = switch -CaseSensitive ($observation.State) {
        'Enabled' { 'READY'; break }
        'Disabled' { 'BLOCKED'; break }
        default { 'UNKNOWN'; break }
    }
    $reasonCode = switch -CaseSensitive ($observation.State) {
        'Enabled' { 'HARDWARE_VIRTUALIZATION_READY'; break }
        'Disabled' { 'HARDWARE_VIRTUALIZATION_DISABLED'; break }
        default { 'HARDWARE_VIRTUALIZATION_STATE_UNKNOWN'; break }
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        State            = $observation.State
        CapabilityStatus = $capabilityStatus
        ReasonCodes      = @($reasonCode)
    }
    return New-CddsiOperationResult -Operation 'DetectHardwareVirtualization' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic hardware virtualization observation completed.' -Data $data
}
