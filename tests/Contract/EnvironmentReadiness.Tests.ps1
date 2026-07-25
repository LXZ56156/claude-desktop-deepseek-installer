BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function New-CddsiContractExpectedCall {
        param([string]$Provider, [string]$ResourceToken, $Result)
        return [pscustomobject][ordered]@{
            Provider = $Provider; Operation = 'Inspect'; ResourceToken = $ResourceToken; Arguments = [ordered]@{}; Result = $Result
        }
    }
}

Describe 'P3 environment and readiness contracts' {
    It 'binds the P3 Desktop and surface evaluators to the frozen P2 contract' {
        $config = New-CddsiClaudeDesktopDesiredConfig
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeTrue
        $calls = @(
            (New-CddsiContractExpectedCall -Provider Environment -ResourceToken '<ENVIRONMENT:WINDOWS>' -Result ([pscustomobject][ordered]@{
                SchemaVersion = 1; Platform = 'Windows'; BuildNumber = 22631; Architecture = 'x64'; IsAdministrator = $true
            })),
            (New-CddsiContractExpectedCall -Provider Package -ResourceToken '<PACKAGE:CLAUDE_DESKTOP>' -Result ([pscustomobject][ordered]@{
                SchemaVersion = 1
                Installations = @([pscustomobject][ordered]@{
                    InstallKind = 'Msix'; Version = $config.MinimumDesktopVersion; Architecture = 'x64'; Scope = 'MachineWide'; DeploymentChannel = 'Standard'
                    IdentityToken = '<PACKAGE_ID:CLAUDE_DESKTOP>'; IdentityStatus = 'Trusted'; Operational = $true
                })
            })),
            (New-CddsiContractExpectedCall -Provider Process -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' -Result ([pscustomobject][ordered]@{
                SchemaVersion = 1
                Candidates = @([pscustomobject][ordered]@{
                    ExecutableToken = '<GIT_EXECUTABLE:PRIMARY>'; Version = '2.45.0.windows.1'; Source = 'GitForWindows'; IdentityStatus = 'Trusted'; CapabilityState = 'Operational'
                })
            })),
            (New-CddsiContractExpectedCall -Provider Feature -ResourceToken '<FEATURE:VIRTUAL_MACHINE_PLATFORM>' -Result ([pscustomobject][ordered]@{ SchemaVersion = 1; State = 'Enabled' })),
            (New-CddsiContractExpectedCall -Provider Environment -ResourceToken '<ENVIRONMENT:HARDWARE_VIRTUALIZATION>' -Result ([pscustomobject][ordered]@{ SchemaVersion = 1; State = 'Enabled' })),
            (New-CddsiContractExpectedCall -Provider Service -ResourceToken '<SERVICE:COWORK>' -Result ([pscustomobject][ordered]@{
                SchemaVersion = 1; IdentityToken = '<SERVICE_ID:COWORK>'; IdentityStatus = 'Trusted'; State = 'Running'
            }))
        )
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls $calls
        $environment = Get-CddsiDesktopEnvironmentSnapshot -ExecutionContext $context -MinimumBuild 19041 -SupportedArchitectures @('x64', 'arm64')
        $desktop = Get-CddsiClaudeDesktopMsixStatus -ExecutionContext $context -MinimumVersion $config.MinimumDesktopVersion -RequiredScope MachineWide -ExpectedArchitecture $environment.Data.Architecture
        $git = Get-CddsiGitForWindowsStatus -ExecutionContext $context -MinimumVersion '2.45.0'
        $vmp = Test-CddsiVirtualMachinePlatform -ExecutionContext $context
        $hardware = Test-CddsiHardwareVirtualization -ExecutionContext $context
        $service = Test-CddsiCoworkServiceStatus -ExecutionContext $context
        $cowork = Get-CddsiCoworkReadiness -EnvironmentStatus $environment -DesktopStatus $desktop -VirtualMachinePlatformStatus $vmp -HardwareVirtualizationStatus $hardware -ServiceStatus $service
        $surfaces = Resolve-CddsiEffectiveSurfaces -RequestedSurfaces $config.RequestedSurfaces -EnvironmentStatus $environment -DesktopStatus $desktop -GitStatus $git -CoworkStatus $cowork

        $desktop.Data.Version | Should -BeExactly $config.MinimumDesktopVersion
        @($surfaces.Data.RequestedSurfaces) -join '|' | Should -BeExactly (@($config.RequestedSurfaces) -join '|')
        $surfaces.Status | Should -BeExactly 'SUCCEEDED'
        $surfaces.Success | Should -BeTrue
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        @($context.AccessLedger.Entries | ForEach-Object Provider) -join '|' | Should -BeExactly 'Environment|Package|Process|Feature|Environment|Service'
        $context.AccessLedger.LiveProviderLoaded | Should -BeFalse
        $context.AccessLedger.ForbiddenResourceAccessCount | Should -Be 0
        $context.AccessLedger.OutsideSandboxWriteCount | Should -Be 0
        $context.AccessLedger.ProductLiveProcessSpawnCount | Should -Be 0
        $context.AccessLedger.ProductNetworkRequestCount | Should -Be 0
        $context.AccessLedger.RealRegistryAccessCount | Should -Be 0
        @($context.Providers.MutationSpy).Count | Should -Be 0
    }

    It 'keeps every P3 result on an exact path-free schema' {
        $operationProperties = @('Operation', 'Status', 'Success', 'Changed', 'Mode', 'ErrorCode', 'MessageSafe', 'Data', 'RestartRequired', 'PlannedChanges', 'Warnings')
        $readyEnvironment = New-CddsiOperationResult -Operation Environment -Status SUCCEEDED -Data ([pscustomobject]@{ CapabilityStatus = 'READY'; IsAdministrator = $true })
        $readyCapability = New-CddsiOperationResult -Operation Capability -Status SUCCEEDED -Data ([pscustomobject]@{ CapabilityStatus = 'READY' })
        $cowork = Get-CddsiCoworkReadiness -EnvironmentStatus $readyEnvironment -DesktopStatus $readyCapability -VirtualMachinePlatformStatus $readyCapability -HardwareVirtualizationStatus $readyCapability -ServiceStatus $readyCapability
        $surfaces = Resolve-CddsiEffectiveSurfaces -RequestedSurfaces @('Chat', 'Code', 'Cowork') -EnvironmentStatus $readyEnvironment -DesktopStatus $readyCapability -GitStatus $readyCapability -CoworkStatus $cowork

        (Test-CddsiExactPropertySet -InputObject $cowork -Expected $operationProperties) | Should -BeTrue
        (Test-CddsiExactPropertySet -InputObject $cowork.Data -Expected @(
            'SchemaVersion', 'CapabilityStatus', 'Ready', 'BlockingReasons', 'EnvironmentStatus', 'DesktopStatus',
            'VirtualMachinePlatformStatus', 'HardwareVirtualizationStatus', 'ServiceStatus', 'AdministratorCapability'
        )) | Should -BeTrue
        (Test-CddsiExactPropertySet -InputObject $surfaces -Expected $operationProperties) | Should -BeTrue
        (Test-CddsiExactPropertySet -InputObject $surfaces.Data -Expected @(
            'SchemaVersion', 'RequestedSurfaces', 'EffectiveSurfaces', 'TargetPreserved', 'TargetSatisfied', 'OverallCapabilityStatus', 'Capabilities'
        )) | Should -BeTrue
        foreach ($capability in @($surfaces.Data.Capabilities)) {
            (Test-CddsiExactPropertySet -InputObject $capability -Expected @('Surface', 'CapabilityStatus', 'ReasonCodes')) | Should -BeTrue
        }
        $serialized = @($cowork, $surfaces) | ConvertTo-Json -Depth 20
        $serialized | Should -Not -Match '(?i)([A-Z]:\\|USERPROFILE|LOCALAPPDATA|\\\.claude|Authorization|api[_-]?key|sk-[A-Za-z0-9])'
    }

    It 'keeps pure readiness evaluators free of ExecutionContext and capability selectors' {
        foreach ($name in @('Get-CddsiCoworkReadiness', 'Resolve-CddsiEffectiveSurfaces')) {
            $parameters = (Get-Command $name -CommandType Function).Parameters.Keys
            $parameters | Should -Not -Contain 'Context'
            $parameters | Should -Not -Contain 'ExecutionContext'
        }
        (Get-Command Resolve-CddsiEffectiveSurfaces).Parameters.Keys | Should -Not -Contain 'DisableSurface'
        { Resolve-CddsiEffectiveSurfaces -RequestedSurfaces @('Chat') -EnvironmentStatus $null -DesktopStatus $null -GitStatus $null -CoworkStatus $null } | Should -Throw
    }

    It 'runs the default Diagnose entry only against its declared synthetic provider sequence' {
        $result = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Diagnose -TestSafe -PassThru
        $result.Operation | Should -BeExactly 'RunDiagnostics'
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.Success | Should -BeFalse
        @($result.Data.Surfaces.Data.RequestedSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        $result.Data.Surfaces.Data.TargetPreserved | Should -BeTrue
        $result.MessageSafe | Should -Match 'synthetic fake provider'
    }
}
