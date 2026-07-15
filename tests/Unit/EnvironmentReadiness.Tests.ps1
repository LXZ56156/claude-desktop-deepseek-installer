BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function New-CddsiTestExpectedCall {
        param(
            [string]$Provider,
            [string]$ResourceToken,
            $Result
        )

        return [pscustomobject][ordered]@{
            Provider      = $Provider
            Operation     = 'Inspect'
            ResourceToken = $ResourceToken
            Arguments     = [ordered]@{}
            Result        = $Result
        }
    }

    function New-CddsiTestMsixInstallation {
        param(
            [string]$InstallKind = 'Msix',
            [string]$Version = '1.20186.0',
            [string]$Architecture = 'x64',
            [string]$Scope = 'MachineWide',
            [string]$DeploymentChannel = 'Standard',
            [string]$IdentityStatus = 'Trusted',
            [bool]$Operational = $true,
            [string]$IdentityToken = '<PACKAGE_ID:CLAUDE_DESKTOP>'
        )

        return [pscustomobject][ordered]@{
            InstallKind       = $InstallKind
            Version           = $Version
            Architecture      = $Architecture
            Scope             = $Scope
            DeploymentChannel = $DeploymentChannel
            IdentityToken     = $IdentityToken
            IdentityStatus    = $IdentityStatus
            Operational       = $Operational
        }
    }

    function New-CddsiTestGitCandidate {
        param(
            [string]$Version = '2.45.0',
            [string]$Source = 'GitForWindows',
            [string]$IdentityStatus = 'Trusted',
            [string]$CapabilityState = 'Operational',
            [string]$ExecutableToken = '<GIT_EXECUTABLE:PRIMARY>'
        )

        return [pscustomobject][ordered]@{
            ExecutableToken = $ExecutableToken
            Version         = $Version
            Source          = $Source
            IdentityStatus  = $IdentityStatus
            CapabilityState = $CapabilityState
        }
    }

    function New-CddsiTestCapabilityResult {
        param(
            [string]$CapabilityStatus = 'READY',
            [string]$Operation = 'SyntheticCapability'
        )

        return New-CddsiOperationResult -Operation $Operation -Status 'SUCCEEDED' -Data ([pscustomobject][ordered]@{
            CapabilityStatus = $CapabilityStatus
        })
    }

    function New-CddsiTestEnvironmentResult {
        param(
            [string]$CapabilityStatus = 'READY',
            [bool]$IsAdministrator = $true
        )

        return New-CddsiOperationResult -Operation 'SyntheticEnvironment' -Status 'SUCCEEDED' -Data ([pscustomobject][ordered]@{
            CapabilityStatus = $CapabilityStatus
            IsAdministrator  = $IsAdministrator
        })
    }
}

Describe 'P3 synthetic Windows environment inventory' {
    It 'accepts each officially modeled architecture at the minimum build' -TestCases @(
        @{ Architecture = 'x64' },
        @{ Architecture = 'arm64' }
    ) {
        param($Architecture)
        $call = New-CddsiTestExpectedCall -Provider Environment -ResourceToken '<ENVIRONMENT:WINDOWS>' -Result ([pscustomobject][ordered]@{
            SchemaVersion = 1; Platform = 'Windows'; BuildNumber = 19041; Architecture = $Architecture; IsAdministrator = $false
        })
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiDesktopEnvironmentSnapshot -ExecutionContext $context -MinimumBuild 19041 -SupportedArchitectures @('x64', 'arm64')
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.CapabilityStatus | Should -BeExactly 'READY'
        $result.Data.Architecture | Should -BeExactly $Architecture
        $result.Data.AdministratorCapability | Should -BeExactly 'UNAVAILABLE'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'blocks unsupported builds and architectures without failing the observation' -TestCases @(
        @{ Build = 19040; Architecture = 'x64'; Reason = 'WINDOWS_BUILD_UNSUPPORTED' },
        @{ Build = 22631; Architecture = 'Other'; Reason = 'ARCHITECTURE_UNSUPPORTED' }
    ) {
        param($Build, $Architecture, $Reason)
        $call = New-CddsiTestExpectedCall -Provider Environment -ResourceToken '<ENVIRONMENT:WINDOWS>' -Result ([pscustomobject][ordered]@{
            SchemaVersion = 1; Platform = 'Windows'; BuildNumber = $Build; Architecture = $Architecture; IsAdministrator = $true
        })
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiDesktopEnvironmentSnapshot -ExecutionContext $context -MinimumBuild 19041 -SupportedArchitectures @('x64', 'arm64')
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.CapabilityStatus | Should -BeExactly 'BLOCKED'
        @($result.Data.ReasonCodes) | Should -Contain $Reason
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'fails closed for an injected provider error and consumes only the declared call' {
        $call = New-CddsiTestExpectedCall -Provider Environment -ResourceToken '<ENVIRONMENT:WINDOWS>' -Result $null
        $failure = [pscustomobject]@{ Sequence = 1; ErrorCode = 'synthetic_timeout'; MessageSafe = 'Synthetic timeout.' }
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call) -FailureInjections @($failure)
        $result = Get-CddsiDesktopEnvironmentSnapshot -ExecutionContext $context -MinimumBuild 19041 -SupportedArchitectures @('x64', 'arm64')
        $result.Status | Should -BeExactly 'FAILED'
        $result.Data.CapabilityStatus | Should -BeExactly 'UNKNOWN'
        $result.MessageSafe | Should -Not -Match 'Synthetic timeout'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'fails closed when no provider call was declared' {
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $result = Get-CddsiDesktopEnvironmentSnapshot -ExecutionContext $context -MinimumBuild 19041 -SupportedArchitectures @('x64', 'arm64')
        $result.Status | Should -BeExactly 'FAILED'
        $result.ErrorCode | Should -BeExactly 'ENVIRONMENT_PROVIDER_FAILED'
        $context.AccessLedger.UnexpectedEntryCount | Should -Be 1
        @($context.Providers.MutationSpy).Count | Should -Be 0
    }
}

Describe 'P3 synthetic Claude Desktop inventory' {
    It 'covers missing, legacy, old, current, opposite-scope and conflict states' {
        $cases = @(
            [pscustomobject]@{ Items = @(); Scope = 'MachineWide'; Status = 'BLOCKED'; Type = 'None'; Reason = 'DESKTOP_MISSING' },
            [pscustomobject]@{ Items = @(New-CddsiTestMsixInstallation -InstallKind LegacyExe -Scope PerUser); Scope = 'MachineWide'; Status = 'BLOCKED'; Type = 'LegacyExe'; Reason = 'LEGACY_DESKTOP_UNSUPPORTED' },
            [pscustomobject]@{ Items = @(New-CddsiTestMsixInstallation -Version '1.20000.0'); Scope = 'MachineWide'; Status = 'BLOCKED'; Type = 'Msix'; Reason = 'DESKTOP_UPGRADE_REQUIRED' },
            [pscustomobject]@{ Items = @(New-CddsiTestMsixInstallation); Scope = 'MachineWide'; Status = 'READY'; Type = 'Msix'; Reason = 'DESKTOP_MSIX_READY' },
            [pscustomobject]@{ Items = @(New-CddsiTestMsixInstallation -Scope PerUser); Scope = 'MachineWide'; Status = 'BLOCKED'; Type = 'Msix'; Reason = 'MSIX_SCOPE_MISMATCH' },
            [pscustomobject]@{ Items = @((New-CddsiTestMsixInstallation -InstallKind LegacyExe -Scope PerUser), (New-CddsiTestMsixInstallation)); Scope = 'MachineWide'; Status = 'BLOCKED'; Type = 'Conflict'; Reason = 'LEGACY_MSIX_CONFLICT' },
            [pscustomobject]@{ Items = @((New-CddsiTestMsixInstallation -Scope PerUser), (New-CddsiTestMsixInstallation)); Scope = 'MachineWide'; Status = 'BLOCKED'; Type = 'Conflict'; Reason = 'MSIX_DOUBLE_INSTALL_RISK' }
        )
        foreach ($case in $cases) {
            $call = New-CddsiTestExpectedCall -Provider Package -ResourceToken '<PACKAGE:CLAUDE_DESKTOP>' -Result ([pscustomobject][ordered]@{
                SchemaVersion = 1; Installations = @($case.Items)
            })
            $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
            $result = Get-CddsiClaudeDesktopMsixStatus -ExecutionContext $context -MinimumVersion '1.20186.0' -RequiredScope $case.Scope -ExpectedArchitecture x64
            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.Data.CapabilityStatus | Should -BeExactly $case.Status
            $result.Data.InstallType | Should -BeExactly $case.Type
            @($result.Data.ReasonCodes) | Should -Contain $case.Reason
            Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        }
    }

    It 'keeps an otherwise valid MSIX unknown until P10 freezes the scope' {
        $call = New-CddsiTestExpectedCall -Provider Package -ResourceToken '<PACKAGE:CLAUDE_DESKTOP>' -Result ([pscustomobject][ordered]@{
            SchemaVersion = 1; Installations = @(New-CddsiTestMsixInstallation)
        })
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiClaudeDesktopMsixStatus -ExecutionContext $context -MinimumVersion '1.20186.0' -RequiredScope Unresolved -ExpectedArchitecture x64
        $result.Data.CapabilityStatus | Should -BeExactly 'UNKNOWN'
        @($result.Data.ReasonCodes) | Should -Contain 'MSIX_SCOPE_DECISION_REQUIRED'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'rejects malformed provider output without echoing it' {
        $call = New-CddsiTestExpectedCall -Provider Package -ResourceToken '<PACKAGE:CLAUDE_DESKTOP>' -Result ([pscustomobject]@{
            SchemaVersion = 1; Installations = @([pscustomobject]@{ Path = 'C:\unsafe\Claude.exe' })
        })
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiClaudeDesktopMsixStatus -ExecutionContext $context -MinimumVersion '1.20186.0' -RequiredScope MachineWide -ExpectedArchitecture x64
        $result.Status | Should -BeExactly 'FAILED'
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match 'unsafe|Claude\.exe'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }
}

Describe 'P3 synthetic Git for Windows inventory' {
    It 'covers reusable, missing, old, broken, foreign and ambiguous candidates' {
        $cases = @(
            [pscustomobject]@{ Candidates = @(New-CddsiTestGitCandidate); Status = 'READY'; Reason = 'GIT_REUSE_READY' },
            [pscustomobject]@{ Candidates = @(); Status = 'BLOCKED'; Reason = 'GIT_MISSING' },
            [pscustomobject]@{ Candidates = @(New-CddsiTestGitCandidate -Version '2.44.0'); Status = 'BLOCKED'; Reason = 'GIT_UPGRADE_REQUIRED' },
            [pscustomobject]@{ Candidates = @(New-CddsiTestGitCandidate -CapabilityState Broken); Status = 'BLOCKED'; Reason = 'GIT_CAPABILITY_BROKEN' },
            [pscustomobject]@{ Candidates = @(New-CddsiTestGitCandidate -Source Other); Status = 'BLOCKED'; Reason = 'GIT_SOURCE_UNSUPPORTED' },
            [pscustomobject]@{ Candidates = @((New-CddsiTestGitCandidate), (New-CddsiTestGitCandidate -ExecutableToken '<GIT_EXECUTABLE:SECONDARY>')); Status = 'BLOCKED'; Reason = 'GIT_PATH_AMBIGUOUS' }
        )
        foreach ($case in $cases) {
            $call = New-CddsiTestExpectedCall -Provider Process -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' -Result ([pscustomobject][ordered]@{
                SchemaVersion = 1; Candidates = @($case.Candidates)
            })
            $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
            $result = Get-CddsiGitForWindowsStatus -ExecutionContext $context -MinimumVersion '2.45.0'
            $result.Data.CapabilityStatus | Should -BeExactly $case.Status
            @($result.Data.ReasonCodes) | Should -Contain $case.Reason
            $result.Data.ReuseEligible | Should -Be ($case.Status -ceq 'READY')
            Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        }
    }

    It 'fails closed on abnormal version output' {
        $call = New-CddsiTestExpectedCall -Provider Process -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' -Result ([pscustomobject][ordered]@{
            SchemaVersion = 1; Candidates = @(New-CddsiTestGitCandidate -Version 'not-a-version')
        })
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiGitForWindowsStatus -ExecutionContext $context -MinimumVersion '2.45.0'
        $result.Status | Should -BeExactly 'FAILED'
        $result.Data.CapabilityStatus | Should -BeExactly 'UNKNOWN'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'does not claim reuse while the minimum version decision is unresolved' {
        $call = New-CddsiTestExpectedCall -Provider Process -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' -Result ([pscustomobject][ordered]@{
            SchemaVersion = 1; Candidates = @(New-CddsiTestGitCandidate)
        })
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiGitForWindowsStatus -ExecutionContext $context -MinimumVersion $null
        $result.Data.CapabilityStatus | Should -BeExactly 'UNKNOWN'
        $result.Data.ReuseEligible | Should -BeFalse
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_MINIMUM_VERSION_UNRESOLVED'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }
}

Describe 'P3 synthetic Cowork readiness' {
    It 'maps the complete synthetic admin, VMP, hardware and service state product' {
        foreach ($administrator in @($false, $true)) {
            foreach ($vmpStatus in @('READY', 'BLOCKED', 'PENDING_RESTART', 'UNKNOWN')) {
                foreach ($hardwareStatus in @('READY', 'BLOCKED', 'UNKNOWN')) {
                    foreach ($serviceStatus in @('READY', 'BLOCKED', 'UNKNOWN')) {
                        $result = Get-CddsiCoworkReadiness `
                            -EnvironmentStatus (New-CddsiTestEnvironmentResult -IsAdministrator $administrator) `
                            -DesktopStatus (New-CddsiTestCapabilityResult) `
                            -VirtualMachinePlatformStatus (New-CddsiTestCapabilityResult -CapabilityStatus $vmpStatus) `
                            -HardwareVirtualizationStatus (New-CddsiTestCapabilityResult -CapabilityStatus $hardwareStatus) `
                            -ServiceStatus (New-CddsiTestCapabilityResult -CapabilityStatus $serviceStatus)

                        $statuses = @($vmpStatus, $hardwareStatus, $serviceStatus)
                        $expected = if (-not $administrator -or $statuses -ccontains 'BLOCKED') {
                            'BLOCKED'
                        }
                        elseif ($statuses -ccontains 'UNKNOWN') {
                            'UNKNOWN'
                        }
                        elseif ($statuses -ccontains 'PENDING_RESTART') {
                            'PENDING_RESTART'
                        }
                        else {
                            'READY'
                        }
                        $result.Data.CapabilityStatus | Should -BeExactly $expected
                        $result.Success | Should -Be ($expected -ceq 'READY')
                    }
                }
            }
        }
    }

    It 'observes VMP, hardware and service only through exact fake calls' {
        $calls = @(
            (New-CddsiTestExpectedCall -Provider Feature -ResourceToken '<FEATURE:VIRTUAL_MACHINE_PLATFORM>' -Result ([pscustomobject]@{ SchemaVersion = 1; State = 'PendingRestart' })),
            (New-CddsiTestExpectedCall -Provider Environment -ResourceToken '<ENVIRONMENT:HARDWARE_VIRTUALIZATION>' -Result ([pscustomobject]@{ SchemaVersion = 1; State = 'Enabled' })),
            (New-CddsiTestExpectedCall -Provider Service -ResourceToken '<SERVICE:COWORK>' -Result ([pscustomobject]@{ SchemaVersion = 1; IdentityToken = '<SERVICE_ID:COWORK>'; IdentityStatus = 'Trusted'; State = 'Running' }))
        )
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls $calls
        $vmp = Test-CddsiVirtualMachinePlatform -ExecutionContext $context
        $hardware = Test-CddsiHardwareVirtualization -ExecutionContext $context
        $service = Test-CddsiCoworkServiceStatus -ExecutionContext $context
        $vmp.Data.CapabilityStatus | Should -BeExactly 'PENDING_RESTART'
        $hardware.Data.CapabilityStatus | Should -BeExactly 'READY'
        $service.Data.CapabilityStatus | Should -BeExactly 'READY'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }
}

Describe 'P3 fixed target surface derivation' {
    It 'reports success only when all three requested surfaces are ready' {
        $environment = New-CddsiTestEnvironmentResult
        $ready = New-CddsiTestCapabilityResult
        $cowork = New-CddsiOperationResult -Operation 'Cowork' -Status 'SUCCEEDED' -Data ([pscustomobject]@{ CapabilityStatus = 'READY' })
        $result = Resolve-CddsiEffectiveSurfaces -RequestedSurfaces @('Chat', 'Code', 'Cowork') -EnvironmentStatus $environment -DesktopStatus $ready -GitStatus $ready -CoworkStatus $cowork
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Success | Should -BeTrue
        @($result.Data.EffectiveSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        $result.Data.TargetSatisfied | Should -BeTrue
    }

    It 'preserves the fixed target and does not misreport a Git blocker as Chat-only success' {
        $environment = New-CddsiTestEnvironmentResult
        $ready = New-CddsiTestCapabilityResult
        $blockedGit = New-CddsiTestCapabilityResult -CapabilityStatus BLOCKED
        $cowork = New-CddsiOperationResult -Operation 'Cowork' -Status 'SUCCEEDED' -Data ([pscustomobject]@{ CapabilityStatus = 'READY' })
        $result = Resolve-CddsiEffectiveSurfaces -RequestedSurfaces @('Chat', 'Code', 'Cowork') -EnvironmentStatus $environment -DesktopStatus $ready -GitStatus $blockedGit -CoworkStatus $cowork
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.Success | Should -BeFalse
        @($result.Data.RequestedSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        @($result.Data.EffectiveSurfaces) -join '|' | Should -BeExactly 'Chat|Cowork'
        $result.Data.TargetPreserved | Should -BeTrue
        $result.Data.TargetSatisfied | Should -BeFalse
    }
}
