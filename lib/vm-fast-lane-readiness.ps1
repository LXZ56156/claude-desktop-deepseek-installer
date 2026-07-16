# vm-fast-lane-readiness.ps1 - Pure deployment-readiness contracts for P10A-0A.
#
# This DevelopmentOnly operator-coordination library performs no I/O. It keeps
# host implementation readiness, external protection readiness, VM integration
# readiness, and Formal P10A authorization as four distinct facts.

function Get-CddsiFastLaneDeploymentObservationBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation
    )

    if ($null -eq (Get-Command -Name ConvertTo-CddsiVmTestRelayCanonicalJson -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'Fast Lane canonical relay contract is not loaded.'
    }
    $payload = [ordered]@{}
    foreach ($property in $Observation.PSObject.Properties) {
        if ($property.Name -cne 'ObservationBindingToken') {
            $payload[$property.Name] = $property.Value
        }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $payload)
}

function Test-CddsiFastLaneRepositoryObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation,
        [Parameter(Mandatory = $true)][AllowNull()]$Expected
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Observation -Expected @(
        'RepositoryToken', 'RepositoryId', 'RepositoryNodeId', 'Visibility',
        'Ref', 'GenesisCommitSha', 'IdentityVerified', 'ProtectedHistory',
        'ForcePushDenied', 'RefDeletionDenied', 'HistoryRewriteDenied'
    ))) { return $false }

    if ($Observation.RepositoryToken -isnot [string] -or
        $Observation.RepositoryToken -cne $Expected.RepositoryToken -or
        ($Observation.RepositoryId -isnot [int] -and $Observation.RepositoryId -isnot [long]) -or
        [long]$Observation.RepositoryId -ne [long]$Expected.RepositoryId -or
        $Observation.RepositoryNodeId -isnot [string] -or
        $Observation.RepositoryNodeId -cne $Expected.RepositoryNodeId -or
        $Observation.Visibility -isnot [string] -or
        @('PUBLIC', 'PRIVATE') -cnotcontains $Observation.Visibility -or
        $Observation.Ref -isnot [string] -or
        $Observation.Ref -cne $Expected.Ref -or
        $Observation.GenesisCommitSha -isnot [string] -or
        $Observation.GenesisCommitSha -notmatch '^[a-f0-9]{40}$' -or
        $Observation.GenesisCommitSha -cne $Expected.GenesisCommitSha) { return $false }

    foreach ($name in @(
        'IdentityVerified', 'ProtectedHistory', 'ForcePushDenied',
        'RefDeletionDenied', 'HistoryRewriteDenied'
    )) {
        if ($Observation.$name -isnot [bool]) { return $false }
    }
    return $true
}

function Test-CddsiFastLaneCredentialObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation,
        [Parameter(Mandatory = $true)][ValidateSet('HostCoordinator', 'VmTester')][string]$Role
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Observation -Expected @(
        'Role', 'Present', 'StoredOutsideRepository', 'RepositoryScopeExact',
        'RefScopeExact', 'ProductReadOnly', 'WrongDirectionWriteDenied',
        'BroadAdminCapabilityAbsent', 'NegativeTestsPassed', 'EvidenceSha256'
    ))) { return $false }
    if ($Observation.Role -cne $Role) { return $false }
    foreach ($name in @(
        'Present', 'StoredOutsideRepository', 'RepositoryScopeExact',
        'RefScopeExact', 'ProductReadOnly', 'WrongDirectionWriteDenied',
        'BroadAdminCapabilityAbsent', 'NegativeTestsPassed'
    )) {
        if ($Observation.$name -isnot [bool]) { return $false }
    }
    if ($Observation.EvidenceSha256 -isnot [string] -or
        $Observation.EvidenceSha256 -notmatch '^[a-f0-9]{64}$') { return $false }
    return $true
}

function Test-CddsiFastLaneAutomationObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation,
        [Parameter(Mandatory = $true)][ValidateSet('HostCoordinator', 'VmTester')][string]$Role,
        [Parameter(Mandatory = $true)][string]$ExpectedAutomationId,
        [Parameter(Mandatory = $true)][int]$ExpectedIntervalMinutes
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Observation -Expected @(
        'Role', 'AutomationId', 'Registered', 'CreatedOnCorrectDevice', 'Status',
        'IntervalMinutes', 'RuntimeHashBound', 'PromptHashBound',
        'LeastPrivilegeIdentityBound', 'EvidenceSha256'
    ))) { return $false }
    if ($Observation.Role -cne $Role -or
        $Observation.AutomationId -isnot [string] -or
        $Observation.AutomationId -cne $ExpectedAutomationId -or
        $Observation.Status -isnot [string] -or
        @('MISSING', 'PAUSED', 'ACTIVE') -cnotcontains $Observation.Status -or
        ($Observation.IntervalMinutes -isnot [int] -and $Observation.IntervalMinutes -isnot [long]) -or
        [long]$Observation.IntervalMinutes -ne $ExpectedIntervalMinutes -or
        $Observation.EvidenceSha256 -isnot [string] -or
        $Observation.EvidenceSha256 -notmatch '^[a-f0-9]{64}$') { return $false }
    foreach ($name in @(
        'Registered', 'CreatedOnCorrectDevice', 'RuntimeHashBound',
        'PromptHashBound', 'LeastPrivilegeIdentityBound'
    )) {
        if ($Observation.$name -isnot [bool]) { return $false }
    }
    return $true
}

function Test-CddsiFastLaneDeploymentObservation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation,
        [Parameter(Mandatory = $true)][AllowNull()]$Policy
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Observation -Expected @(
        'SchemaVersion', 'ContractVersion', 'CapturedAtUtc', 'ValidUntilUtc',
        'PolicySha256', 'ProductCommitSha',
        'RepairRef', 'ProductRepository', 'HostToVmRepository',
        'VmToHostRepository', 'HostRuntime', 'OnboardingBundle',
        'HostCredential', 'HostAutomation', 'VmCredential', 'VmAutomation',
        'VmReset', 'UnattendedLoop', 'FormalLane', 'ObservationBindingToken'
    ))) { return $false }
    if (($Observation.SchemaVersion -isnot [int] -and $Observation.SchemaVersion -isnot [long]) -or
        [long]$Observation.SchemaVersion -ne 2 -or
        $Observation.ContractVersion -cne 'cddsi-fast-lane-deployment-observation-v2' -or
        -not (Test-CddsiUtcTimestampValue -Value $Observation.CapturedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Observation.ValidUntilUtc) -or
        $Observation.PolicySha256 -isnot [string] -or
        $Observation.PolicySha256 -notmatch '^[a-f0-9]{64}$' -or
        $Observation.ProductCommitSha -isnot [string] -or
        $Observation.ProductCommitSha -notmatch '^[a-f0-9]{40}$' -or
        $Observation.RepairRef -isnot [string] -or
        $Observation.RepairRef -notmatch '^refs/heads/codex/repair/[a-z0-9][a-z0-9._/-]{0,119}$' -or
        $Observation.RepairRef.Contains('..') -or
        $Observation.RepairRef.Contains('//') -or
        $Observation.RepairRef.EndsWith('.lock', [StringComparison]::Ordinal) -or
        $Observation.ObservationBindingToken -isnot [string] -or
        $Observation.ObservationBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }
    $captured = [DateTimeOffset]::Parse($Observation.CapturedAtUtc)
    $validUntil = [DateTimeOffset]::Parse($Observation.ValidUntilUtc)
    if ($validUntil -le $captured -or ($validUntil - $captured).TotalSeconds -gt 900) { return $false }

    $productExpected = @{
        RepositoryToken = $Policy.ProductRemote.RepositoryToken
        RepositoryId = $Policy.ProductRemote.RepositoryId
        RepositoryNodeId = $Policy.ProductRemote.RepositoryNodeId
        Ref = $Observation.RepairRef
        GenesisCommitSha = $Observation.ProductCommitSha
    }
    if (-not (Test-CddsiFastLaneRepositoryObservation -Observation $Observation.ProductRepository -Expected $productExpected) -or
        -not (Test-CddsiFastLaneRepositoryObservation -Observation $Observation.HostToVmRepository -Expected $Policy.ControlPlane.HostToVm) -or
        -not (Test-CddsiFastLaneRepositoryObservation -Observation $Observation.VmToHostRepository -Expected $Policy.ControlPlane.VmToHost)) { return $false }

    if (-not (Test-CddsiFastLaneCredentialObservation -Observation $Observation.HostCredential -Role HostCoordinator) -or
        -not (Test-CddsiFastLaneCredentialObservation -Observation $Observation.VmCredential -Role VmTester) -or
        -not (Test-CddsiFastLaneAutomationObservation -Observation $Observation.HostAutomation -Role HostCoordinator `
            -ExpectedAutomationId $Policy.Automation.Host.AutomationId -ExpectedIntervalMinutes $Policy.Automation.IntervalMinutes) -or
        -not (Test-CddsiFastLaneAutomationObservation -Observation $Observation.VmAutomation -Role VmTester `
            -ExpectedAutomationId $Policy.Automation.Vm.AutomationId -ExpectedIntervalMinutes $Policy.Automation.IntervalMinutes)) { return $false }

    foreach ($componentName in @('HostRuntime', 'OnboardingBundle', 'VmReset', 'UnattendedLoop', 'FormalLane')) {
        $component = $Observation.$componentName
        if (-not (Test-CddsiExactPropertySet -InputObject $component -Expected @(
            'Available', 'Validated', 'DiagnosticOnly', 'EvidenceSha256'
        )) -or
            $component.Available -isnot [bool] -or
            $component.Validated -isnot [bool] -or
            $component.DiagnosticOnly -isnot [bool] -or
            $component.EvidenceSha256 -isnot [string] -or
            $component.EvidenceSha256 -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    return ($Observation.ObservationBindingToken -ceq
        (Get-CddsiFastLaneDeploymentObservationBindingToken -Observation $Observation))
}

function Resolve-CddsiFastLaneReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Observation,
        [Parameter(Mandatory = $true)][AllowNull()]$Policy,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][string]$ExpectedPolicySha256
    )

    if (-not (Test-CddsiFastLaneDeploymentObservation -Observation $Observation -Policy $Policy)) {
        throw 'Fast Lane deployment observation is invalid.'
    }
    if (-not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc) -or
        $ExpectedPolicySha256 -notmatch '^[a-f0-9]{64}$' -or
        $Observation.PolicySha256 -cne $ExpectedPolicySha256) {
        throw 'Fast Lane validation time or policy binding is invalid.'
    }
    $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
    $capturedTime = [DateTimeOffset]::Parse($Observation.CapturedAtUtc)
    $validUntilTime = [DateTimeOffset]::Parse($Observation.ValidUntilUtc)
    if ($validationTime -lt $capturedTime.AddSeconds(-120) -or $validationTime -gt $validUntilTime) {
        throw 'Fast Lane deployment observation is stale or not yet valid.'
    }

    $reasons = @()
    $hostImplementationReady = $Observation.HostRuntime.Available -and
        $Observation.HostRuntime.Validated -and
        $Observation.HostRuntime.DiagnosticOnly -and
        $Observation.OnboardingBundle.Available -and
        $Observation.OnboardingBundle.Validated -and
        $Observation.OnboardingBundle.DiagnosticOnly
    if (-not $hostImplementationReady) { $reasons += 'HOST_IMPLEMENTATION_INCOMPLETE' }

    $repositories = @(
        $Observation.ProductRepository,
        $Observation.HostToVmRepository,
        $Observation.VmToHostRepository
    )
    $repositoryVisibilityReady = @($repositories | Where-Object {
        $_.Visibility -cne 'PUBLIC'
    }).Count -eq 0
    if (-not $repositoryVisibilityReady) { $reasons += 'REPOSITORY_VISIBILITY_MISMATCH' }

    $repositoryProtectionReady = @($repositories | Where-Object {
        -not $_.IdentityVerified -or -not $_.ProtectedHistory -or
        -not $_.ForcePushDenied -or -not $_.RefDeletionDenied -or
        -not $_.HistoryRewriteDenied
    }).Count -eq 0
    if (-not $repositoryProtectionReady) { $reasons += 'PROTECTED_HISTORY_UNAVAILABLE' }

    $hostCredentialReady = $Observation.HostCredential.Present -and
        $Observation.HostCredential.StoredOutsideRepository -and
        $Observation.HostCredential.RepositoryScopeExact -and
        $Observation.HostCredential.RefScopeExact -and
        -not $Observation.HostCredential.ProductReadOnly -and
        $Observation.HostCredential.WrongDirectionWriteDenied -and
        $Observation.HostCredential.BroadAdminCapabilityAbsent -and
        $Observation.HostCredential.NegativeTestsPassed
    if (-not $hostCredentialReady) { $reasons += 'HOST_CREDENTIAL_NOT_VERIFIED' }

    $hostAutomationBound = $Observation.HostAutomation.Registered -and
        $Observation.HostAutomation.CreatedOnCorrectDevice -and
        $Observation.HostAutomation.RuntimeHashBound -and
        $Observation.HostAutomation.PromptHashBound -and
        $Observation.HostAutomation.LeastPrivilegeIdentityBound
    $hostAutomationSafelyStaged = $hostAutomationBound -and
        $Observation.HostAutomation.Status -ceq 'PAUSED'
    if (-not $hostAutomationSafelyStaged) { $reasons += 'HOST_AUTOMATION_NOT_SAFELY_STAGED' }

    # Device-local key generation, bundle verification, and negative-permission
    # setup may begin while remote protection and credentials are still being
    # provisioned. No control-repository polling or product test is authorized
    # by this narrower bootstrap gate.
    $canStartVmBootstrap = $hostImplementationReady -and $hostAutomationSafelyStaged

    $canStartVmIntegration = $hostImplementationReady -and
        $repositoryVisibilityReady -and $repositoryProtectionReady -and $hostCredentialReady -and
        $hostAutomationSafelyStaged

    $vmCredentialReady = $Observation.VmCredential.Present -and
        $Observation.VmCredential.StoredOutsideRepository -and
        $Observation.VmCredential.RepositoryScopeExact -and
        $Observation.VmCredential.RefScopeExact -and
        $Observation.VmCredential.ProductReadOnly -and
        $Observation.VmCredential.WrongDirectionWriteDenied -and
        $Observation.VmCredential.BroadAdminCapabilityAbsent -and
        $Observation.VmCredential.NegativeTestsPassed
    if (-not $vmCredentialReady) { $reasons += 'VM_CREDENTIAL_NOT_VERIFIED' }

    $vmAutomationBound = $Observation.VmAutomation.Registered -and
        $Observation.VmAutomation.CreatedOnCorrectDevice -and
        $Observation.VmAutomation.RuntimeHashBound -and
        $Observation.VmAutomation.PromptHashBound -and
        $Observation.VmAutomation.LeastPrivilegeIdentityBound -and
        @('PAUSED', 'ACTIVE') -ccontains $Observation.VmAutomation.Status
    $vmAutomationSafelyStaged = $vmAutomationBound -and
        $Observation.VmAutomation.Status -ceq 'PAUSED'
    if (-not $vmAutomationBound) {
        $reasons += 'VM_AUTOMATION_NOT_SAFELY_BOUND'
    }
    elseif (-not $vmAutomationSafelyStaged) {
        $reasons += 'VM_AUTOMATION_NOT_SAFELY_STAGED'
    }

    $vmResetReady = $Observation.VmReset.Available -and
        $Observation.VmReset.Validated -and $Observation.VmReset.DiagnosticOnly
    if (-not $vmResetReady) { $reasons += 'VM_RESET_NOT_VERIFIED' }

    $unattendedReady = $Observation.UnattendedLoop.Available -and
        $Observation.UnattendedLoop.Validated -and
        $Observation.UnattendedLoop.DiagnosticOnly
    if (-not $unattendedReady) { $reasons += 'UNATTENDED_LOOP_NOT_VERIFIED' }

    $p10a0aComplete = $hostImplementationReady -and $repositoryVisibilityReady -and $repositoryProtectionReady -and
        $hostCredentialReady -and $hostAutomationSafelyStaged -and $vmCredentialReady -and
        $vmAutomationSafelyStaged -and $vmResetReady -and $unattendedReady
    # Fast Lane observations are diagnostic and cannot authenticate the
    # snapshot, signature, or CAS authorities required by Formal P10A. This v1
    # resolver therefore has no input capable of authorizing the next lane.
    $formalLaneReady = $false
    $reasons += 'FORMAL_LANE_UNAVAILABLE'

    return [pscustomobject][ordered]@{
        SchemaVersion              = 2
        ContractVersion            = 'cddsi-fast-lane-readiness-v2'
        HostImplementationReady    = [bool]$hostImplementationReady
        RepositoryVisibilityReady  = [bool]$repositoryVisibilityReady
        RepositoryProtectionReady  = [bool]$repositoryProtectionReady
        HostCredentialReady        = [bool]$hostCredentialReady
        HostAutomationReady        = [bool]$hostAutomationBound
        HostAutomationSafelyStaged = [bool]$hostAutomationSafelyStaged
        CanStartVmBootstrap        = [bool]$canStartVmBootstrap
        CanStartVmIntegration      = [bool]$canStartVmIntegration
        VmCredentialReady          = [bool]$vmCredentialReady
        VmAutomationReady          = [bool]$vmAutomationBound
        VmAutomationSafelyStaged   = [bool]$vmAutomationSafelyStaged
        VmResetReady               = [bool]$vmResetReady
        UnattendedLoopReady         = [bool]$unattendedReady
        P10A0AComplete              = [bool]$p10a0aComplete
        FormalLaneReady             = [bool]$formalLaneReady
        CanStartFormalP10A          = $false
        ReasonCodes                 = @($reasons | Sort-Object -Unique -CaseSensitive)
    }
}
