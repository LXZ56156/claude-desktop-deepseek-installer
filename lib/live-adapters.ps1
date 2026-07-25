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
        [string]$ValidationTimeUtc
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

    return New-CddsiOperationResult -Operation 'LoadLiveProviders' -Status 'ACTION_REQUIRED' `
        -Mode Live -ErrorCode 'LIVE_PROVIDER_LOAD_NOT_IMPLEMENTED' `
        -MessageSafe 'Live provider authorization is valid, but the provider implementation is not present in this development batch.'
}
