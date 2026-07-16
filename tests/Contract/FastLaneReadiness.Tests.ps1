BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\common.ps1')
    . (Join-Path $script:RepoRoot 'lib\vm-test-relay.ps1')
    . (Join-Path $script:RepoRoot 'lib\vm-fast-lane-readiness.ps1')
    $script:Policy = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\fast-lane-policy.psd1')
    $script:PolicySha256 = 'e' * 64
    $script:ValidationTimeUtc = '2030-01-01T00:05:00Z'

    function New-CddsiRepositoryObservationFixture {
        param($Expected, [string]$Ref, [string]$GenesisCommitSha, [bool]$Protected = $true)
        [pscustomobject][ordered]@{
            RepositoryToken = $Expected.RepositoryToken
            RepositoryId = [long]$Expected.RepositoryId
            RepositoryNodeId = $Expected.RepositoryNodeId
            Private = $true
            Ref = $Ref
            GenesisCommitSha = $GenesisCommitSha
            IdentityVerified = $true
            ProtectedHistory = $Protected
            ForcePushDenied = $Protected
            RefDeletionDenied = $Protected
            HistoryRewriteDenied = $Protected
        }
    }

    function New-CddsiCredentialObservationFixture {
        param([string]$Role, [bool]$Ready, [bool]$ProductReadOnly)
        [pscustomobject][ordered]@{
            Role = $Role
            Present = $Ready
            StoredOutsideRepository = $Ready
            RepositoryScopeExact = $Ready
            RefScopeExact = $Ready
            ProductReadOnly = $ProductReadOnly
            WrongDirectionWriteDenied = $Ready
            BroadAdminCapabilityAbsent = $Ready
            NegativeTestsPassed = $Ready
            EvidenceSha256 = 'a' * 64
        }
    }

    function New-CddsiAutomationObservationFixture {
        param([string]$Role, [string]$AutomationId, [string]$Status, [bool]$Ready)
        [pscustomobject][ordered]@{
            Role = $Role
            AutomationId = $AutomationId
            Registered = $Ready
            CreatedOnCorrectDevice = $Ready
            Status = $Status
            IntervalMinutes = 1
            RuntimeHashBound = $Ready
            PromptHashBound = $Ready
            LeastPrivilegeIdentityBound = $Ready
            EvidenceSha256 = 'b' * 64
        }
    }

    function New-CddsiComponentObservationFixture {
        param([bool]$Ready, [bool]$DiagnosticOnly = $true)
        [pscustomobject][ordered]@{
            Available = $Ready
            Validated = $Ready
            DiagnosticOnly = $DiagnosticOnly
            EvidenceSha256 = 'c' * 64
        }
    }

    function New-CddsiFastLaneDeploymentObservationFixture {
        param(
            [bool]$Protected = $true,
            [bool]$HostCredentialReady = $true,
            [bool]$HostAutomationReady = $true,
            [bool]$VmReady = $false,
            [bool]$FormalReady = $false
        )
        $commit = 'd' * 40
        $repairRef = 'refs/heads/codex/repair/p10a-0a-fast-lane'
        $observation = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-fast-lane-deployment-observation-v1'
            CapturedAtUtc = '2030-01-01T00:00:00Z'
            ValidUntilUtc = '2030-01-01T00:10:00Z'
            PolicySha256 = $script:PolicySha256
            ProductCommitSha = $commit
            RepairRef = $repairRef
            ProductRepository = New-CddsiRepositoryObservationFixture -Expected $script:Policy.ProductRemote `
                -Ref $repairRef -GenesisCommitSha $commit -Protected $Protected
            HostToVmRepository = New-CddsiRepositoryObservationFixture -Expected $script:Policy.ControlPlane.HostToVm `
                -Ref $script:Policy.ControlPlane.HostToVm.Ref `
                -GenesisCommitSha $script:Policy.ControlPlane.HostToVm.GenesisCommitSha -Protected $Protected
            VmToHostRepository = New-CddsiRepositoryObservationFixture -Expected $script:Policy.ControlPlane.VmToHost `
                -Ref $script:Policy.ControlPlane.VmToHost.Ref `
                -GenesisCommitSha $script:Policy.ControlPlane.VmToHost.GenesisCommitSha -Protected $Protected
            HostRuntime = New-CddsiComponentObservationFixture -Ready $true
            OnboardingBundle = New-CddsiComponentObservationFixture -Ready $true
            HostCredential = New-CddsiCredentialObservationFixture -Role HostCoordinator `
                -Ready $HostCredentialReady -ProductReadOnly $false
            HostAutomation = New-CddsiAutomationObservationFixture -Role HostCoordinator `
                -AutomationId $script:Policy.Automation.Host.AutomationId `
                -Status $(if ($HostAutomationReady) { 'PAUSED' } else { 'MISSING' }) -Ready $HostAutomationReady
            VmCredential = New-CddsiCredentialObservationFixture -Role VmTester -Ready $VmReady -ProductReadOnly $true
            VmAutomation = New-CddsiAutomationObservationFixture -Role VmTester `
                -AutomationId $script:Policy.Automation.Vm.AutomationId `
                -Status $(if ($VmReady) { 'ACTIVE' } else { 'MISSING' }) -Ready $VmReady
            VmReset = New-CddsiComponentObservationFixture -Ready $VmReady
            UnattendedLoop = New-CddsiComponentObservationFixture -Ready $VmReady
            FormalLane = New-CddsiComponentObservationFixture -Ready $FormalReady -DiagnosticOnly (-not $FormalReady)
            ObservationBindingToken = ''
        }
        $observation.ObservationBindingToken = Get-CddsiFastLaneDeploymentObservationBindingToken -Observation $observation
        return $observation
    }
}

Describe 'P10A-0A deployment readiness contracts' {
    It 'separates completed host implementation from unavailable protected history and credentials' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture -Protected $false `
            -HostCredentialReady $false -HostAutomationReady $true
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.HostImplementationReady | Should -BeTrue
        $result.CanStartVmBootstrap | Should -BeTrue
        $result.RepositoryProtectionReady | Should -BeFalse
        $result.HostCredentialReady | Should -BeFalse
        $result.CanStartVmIntegration | Should -BeFalse
        $result.P10A0AComplete | Should -BeFalse
        $result.CanStartFormalP10A | Should -BeFalse
        @($result.ReasonCodes) | Should -Contain 'PROTECTED_HISTORY_UNAVAILABLE'
        @($result.ReasonCodes) | Should -Contain 'HOST_CREDENTIAL_NOT_VERIFIED'
    }

    It 'allows VM integration to start only after the host runtime, protection, credential, and paused automation are staged' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.CanStartVmIntegration | Should -BeTrue
        $result.CanStartVmBootstrap | Should -BeTrue
        $result.P10A0AComplete | Should -BeFalse
        $result.ReasonCodes | Should -Contain 'VM_CREDENTIAL_NOT_VERIFIED'
        $result.ReasonCodes | Should -Contain 'VM_AUTOMATION_NOT_SAFELY_BOUND'
    }

    It 'can complete Fast Lane without promoting diagnostic evidence to Formal P10A' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture -VmReady $true
        $observation.VmAutomation.Status = 'PAUSED'
        $observation.ObservationBindingToken = Get-CddsiFastLaneDeploymentObservationBindingToken -Observation $observation
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.P10A0AComplete | Should -BeTrue
        $result.FormalLaneReady | Should -BeFalse
        $result.CanStartFormalP10A | Should -BeFalse
        $result.ReasonCodes | Should -Contain 'FORMAL_LANE_UNAVAILABLE'
    }

    It 'rejects a self-reported Formal flag because Fast Lane cannot authenticate Formal authorities' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture -VmReady $true -FormalReady $true
        $observation.VmAutomation.Status = 'PAUSED'
        $observation.ObservationBindingToken = Get-CddsiFastLaneDeploymentObservationBindingToken -Observation $observation
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.P10A0AComplete | Should -BeTrue
        $result.FormalLaneReady | Should -BeFalse
        $result.CanStartFormalP10A | Should -BeFalse
        $result.ReasonCodes | Should -Contain 'FORMAL_LANE_UNAVAILABLE'
    }

    It 'rejects repository identity substitution before readiness evaluation' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture
        $observation.HostToVmRepository.RepositoryId = 1
        { Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256 } |
            Should -Throw '*observation is invalid*'
    }

    It 'rejects an active host automation as the pre-VM staged state' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture
        $observation.HostAutomation.Status = 'ACTIVE'
        $observation.ObservationBindingToken = Get-CddsiFastLaneDeploymentObservationBindingToken -Observation $observation
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.HostAutomationReady | Should -BeTrue
        $result.HostAutomationSafelyStaged | Should -BeFalse
        $result.CanStartVmBootstrap | Should -BeFalse
        $result.CanStartVmIntegration | Should -BeFalse
        $result.ReasonCodes | Should -Contain 'HOST_AUTOMATION_NOT_SAFELY_STAGED'
    }

    It 'rejects stale, mixed-policy, and post-binding tampered observations' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture
        { Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc '2030-01-01T00:20:00Z' -ExpectedPolicySha256 $script:PolicySha256 } |
            Should -Throw '*stale*'
        { Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 ('f' * 64) } |
            Should -Throw '*policy binding*'
        $observation.HostRuntime.Validated = $false
        { Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256 } |
            Should -Throw '*observation is invalid*'
    }

    It 'represents a completed unattended smoke after both device tasks return to paused' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture -VmReady $true
        $observation.HostAutomation.Status = 'PAUSED'
        $observation.VmAutomation.Status = 'PAUSED'
        $observation.ObservationBindingToken = Get-CddsiFastLaneDeploymentObservationBindingToken -Observation $observation
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.P10A0AComplete | Should -BeTrue
        $result.HostAutomationSafelyStaged | Should -BeTrue
        $result.VmAutomationReady | Should -BeTrue
        $result.VmAutomationSafelyStaged | Should -BeTrue
    }

    It 'does not declare P10A-0A complete while the VM minute task is still active' {
        $observation = New-CddsiFastLaneDeploymentObservationFixture -VmReady $true
        $result = Resolve-CddsiFastLaneReadiness -Observation $observation -Policy $script:Policy `
            -ValidationTimeUtc $script:ValidationTimeUtc -ExpectedPolicySha256 $script:PolicySha256
        $result.VmAutomationReady | Should -BeTrue
        $result.VmAutomationSafelyStaged | Should -BeFalse
        $result.P10A0AComplete | Should -BeFalse
        $result.ReasonCodes | Should -Contain 'VM_AUTOMATION_NOT_SAFELY_STAGED'
    }
}
