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
    if ($Context.EnvironmentTier -cne 'VmAcceptance') {
        throw 'The first Live adapter execution is restricted to the disposable VM acceptance tier.'
    }
    if ($StageManifest.Stage -cne 'VmAcceptance' -or $StageManifest.ArtifactProfile -cne 'VmAcceptance') {
        throw 'The Live adapter requires a VmAcceptance stage manifest.'
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

    throw 'Live provider implementations remain disabled until disposable-VM integration is explicitly completed.'
}
