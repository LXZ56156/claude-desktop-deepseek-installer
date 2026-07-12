# cowork-readiness.ps1 - Cowork prerequisites and resume contracts.
# Enabling Windows features or scheduling resume work is outside this stage.

function Get-CddsiCoworkReadiness {
    [CmdletBinding()]
    param()

    $data = [pscustomobject][ordered]@{
        virtualMachinePlatform = 'not_checked'
        hardwareVirtualization = 'not_checked'
        coworkService          = 'not_checked'
        ready                  = $false
        blockingReasons        = @('not_implemented')
    }
    return New-CddsiOperationResult -Operation 'EvaluateCoworkReadiness' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe 'Cowork readiness 尚未读取本机状态。' -Data $data
}

function Get-CddsiCoworkBlockingReasons {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Readiness
    )

    if ($null -eq $Readiness.Data -or $null -eq $Readiness.Data.blockingReasons) {
        return @('invalid_readiness_result')
    }
    return @($Readiness.Data.blockingReasons)
}

function New-CddsiCoworkResumePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReasonCode,
        [string]$ResumePhase = 'verify_cowork'
    )

    return [pscustomobject][ordered]@{
        schemaVersion = 1
        reasonCode    = $ReasonCode
        resumePhase   = $ResumePhase
        automaticRestartAllowed = $false
        schedulerRegistrationImplemented = $false
    }
}

function Test-CddsiCoworkServiceStatus {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectCoworkService' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '未查询 Cowork 服务；服务身份尚待官方合同确认。'
}

function Enable-CddsiVirtualMachinePlatform {
    [CmdletBinding()]
    param(
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges,
        [switch]$AcknowledgeRestart
    )

    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'EnableVirtualMachinePlatform' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'EnableVirtualMachinePlatform' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会启用 Windows 功能，也不会重启。' -RestartRequired $true -PlannedChanges @('VirtualMachinePlatform') -Warnings @('即使未来实现，重启仍需独立确认。')
}
