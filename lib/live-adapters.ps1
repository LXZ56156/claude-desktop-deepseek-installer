# live-adapters.ps1 - Deliberately isolated Live-provider entry boundary.
# This file is packaged but is never loaded by the default bootstrap, CI or Pester.

function Invoke-CddsiLiveAdapterOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]
        $Context,

        [Parameter(Mandatory = $true)]
        $StageManifest,

        [Parameter(Mandatory = $true)]
        $OperationGrant,

        [Parameter(Mandatory = $true)]
        $AuthorizationSession,

        [Parameter(Mandatory = $true)]
        $WorkflowSessionState,

        [Parameter(Mandatory = $true)]
        $OperationUseState,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$OperationUseId,

        [Parameter(Mandatory = $true)]
        [string]$ValidationTimeUtc,

        [Parameter(Mandatory = $true)]
        [string]$AdapterSha256
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null

    $allowedBindings = @(
        [pscustomobject][ordered]@{
            EnvironmentTier = 'VmDevelopment'
            Stage           = 'VmDevelopment'
            ArtifactProfile = 'VmDevelopment'
        },
        [pscustomobject][ordered]@{
            EnvironmentTier = 'VmAcceptance'
            Stage           = 'VmAcceptance'
            ArtifactProfile = 'VmAcceptance'
        },
        [pscustomobject][ordered]@{
            EnvironmentTier = 'UserLive'
            Stage           = 'UserLive'
            ArtifactProfile = 'UserLive'
        }
    )
    $bindingMatches = @($allowedBindings | Where-Object {
        $_.EnvironmentTier -ceq $Context.EnvironmentTier -and
        $_.Stage -ceq $Context.Stage -and
        $_.Stage -ceq $StageManifest.Stage -and
        $_.ArtifactProfile -ceq $StageManifest.ArtifactProfile
    })
    if ($bindingMatches.Count -ne 1) {
        throw 'The Live adapter requires one exact stage, environment-tier and artifact-profile binding.'
    }
    if ($Context.RunId -cne $OperationGrant.RunId) {
        throw 'The Live adapter requires the execution context and operation grant to use the same run identifier.'
    }
    if ($Context.Providers.Kind -cne 'Unloaded' -or $Context.AccessLedger.LiveProviderLoaded) {
        throw 'The Live adapter load boundary requires an Unloaded provider set.'
    }
    if ($Operation -cne 'LoadLiveProviders') {
        throw 'The Live adapter load boundary requires the dedicated LoadLiveProviders operation.'
    }
    if ($AdapterSha256 -cnotmatch '^[a-f0-9]{64}$') {
        throw 'The Live adapter requires one caller-supplied lowercase SHA-256 identifier.'
    }
    if (-not (Test-CddsiCommittedOperationUseReceipt `
        -StageManifest $StageManifest `
        -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $OperationUseState `
        -Operation $Operation `
        -OperationUseId $OperationUseId `
        -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'The Live adapter requires a committed stage/grant/operation-use receipt.'
    }

    $loadedProviderSet = New-CddsiLiveReadOnlyProviderSet `
        -RunId $Context.RunId `
        -Stage $Context.Stage `
        -EnvironmentTier $Context.EnvironmentTier `
        -ArtifactProfile $StageManifest.ArtifactProfile `
        -AdapterSha256 $AdapterSha256 `
        -LoadOperationUseId $OperationUseId `
        -LoadReceiptBindingToken $OperationUseState.ReceiptBindingToken

    $previousProviderSet = $Context.Providers
    $previousLiveProviderLoaded = $Context.AccessLedger.LiveProviderLoaded
    try {
        $Context.Providers = $loadedProviderSet
        $Context.AccessLedger.LiveProviderLoaded = $true
        Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null
    }
    catch {
        $Context.Providers = $previousProviderSet
        $Context.AccessLedger.LiveProviderLoaded = $previousLiveProviderLoaded
        throw
    }

    $resultData = [pscustomobject][ordered]@{
        SchemaVersion      = 1
        ProviderSetKind    = $loadedProviderSet.Kind
        CapabilitySetDigest = $loadedProviderSet.CapabilitySetDigest
        LiveProviderLoaded = $Context.AccessLedger.LiveProviderLoaded
    }
    return New-CddsiOperationResult -Operation 'LoadLiveProviders' -Status 'SUCCEEDED' `
        -Changed $false -Mode Live -MessageSafe 'The source-unbound Live read-only provider contract was loaded with a caller-supplied adapter identifier.' `
        -Data $resultData
}

function Invoke-CddsiLiveReadOnlyProviderOperation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]
        $Context,

        [Parameter(Mandatory = $true)]
        [string]$Provider,

        [Parameter(Mandatory = $true)]
        [string]$Operation,

        [Parameter(Mandatory = $true)]
        [string]$ResourceToken,

        [Parameter(Mandatory = $true)]
        [System.Collections.IDictionary]$Arguments
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null

    $providerIsExact = $true
    $providerCapabilities = @(switch -CaseSensitive ($Provider) {
        'FileSystem' { $Context.Providers.FileSystem.Capabilities; break }
        'Environment' { $Context.Providers.Environment.Capabilities; break }
        'Registry' { $Context.Providers.Registry.Capabilities; break }
        'Process' { $Context.Providers.Process.Capabilities; break }
        'Network' { $Context.Providers.Network.Capabilities; break }
        'Package' { $Context.Providers.Package.Capabilities; break }
        'Feature' { $Context.Providers.Feature.Capabilities; break }
        'Service' { $Context.Providers.Service.Capabilities; break }
        'Credential' { $Context.Providers.Credential.Capabilities; break }
        'Clock' { $Context.Providers.Clock.Capabilities; break }
        default {
            $providerIsExact = $false
            @()
            break
        }
    })

    if (-not $providerIsExact) {
        # The dispatcher already enforces canonical provider identity.  A
        # direct public call with an unknown or wrong-case provider is a
        # contract violation and cannot be represented truthfully in the
        # canonical ledger schema, so fail before mutating any context state.
        throw 'LIVE_READ_ONLY_CAPABILITY_DENIED'
    }

    $ledgerOperation = if ($Operation -match '^[A-Za-z][A-Za-z0-9_.:-]{0,127}$') {
        $Operation
    }
    else {
        'RejectedCapability'
    }
    $denialCode = $null
    if ($Arguments.Count -ne 0) {
        $denialCode = 'LIVE_READ_ONLY_ARGUMENTS_DENIED'
    }
    else {
        $allCapabilities = @(
            $Context.Providers.FileSystem.Capabilities
            $Context.Providers.Environment.Capabilities
            $Context.Providers.Registry.Capabilities
            $Context.Providers.Process.Capabilities
            $Context.Providers.Network.Capabilities
            $Context.Providers.Package.Capabilities
            $Context.Providers.Feature.Capabilities
            $Context.Providers.Service.Capabilities
            $Context.Providers.Credential.Capabilities
            $Context.Providers.Clock.Capabilities
        )
        $resourceMatches = @($allCapabilities | Where-Object {
            $_.ResourceToken -ceq $ResourceToken
        })
        $capabilityMatches = @($providerCapabilities | Where-Object {
            $_.Operation -ceq $Operation -and
            $_.ResourceToken -ceq $ResourceToken -and
            @($_.ArgumentNames).Count -eq 0
        })
        if ($resourceMatches.Count -eq 0) {
            $denialCode = 'LIVE_READ_ONLY_RESOURCE_DENIED'
        }
        elseif ($capabilityMatches.Count -ne 1) {
            $denialCode = 'LIVE_READ_ONLY_CAPABILITY_DENIED'
        }
    }
    if ($null -ne $denialCode) {
        Add-CddsiProductAccessLedgerEntry `
            -ExecutionContext $Context `
            -Provider $Provider `
            -Operation $ledgerOperation `
            -ResourceToken $ResourceToken `
            -Arguments $Arguments `
            -Allowed $false `
            -Expected $false `
            -IsMutation:($Operation -cne 'Inspect') `
            -FailureInjected $false `
            -Outcome Denied `
            -ErrorCode $denialCode `
            -ProviderEvidenceDigest $null | Out-Null
        throw $denialCode
    }

    $errorCode = 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
    Add-CddsiProductAccessLedgerEntry `
        -ExecutionContext $Context `
        -Provider $Provider `
        -Operation $Operation `
        -ResourceToken $ResourceToken `
        -Arguments $Arguments `
        -Allowed $true `
        -Expected $true `
        -IsMutation $false `
        -FailureInjected $false `
        -Outcome ProviderFailure `
        -ErrorCode $errorCode `
        -ProviderEvidenceDigest $null | Out-Null
    throw $errorCode
}
