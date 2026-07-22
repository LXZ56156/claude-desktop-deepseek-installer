BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
    $script:ReleaseManifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'scripts\release-manifest.psd1')
    $script:PublicContract = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\public-functions.psd1')
    $script:OperatorLibraries = @(
        'lib/vm-test-relay.ps1'
        'lib/vm-reset.ps1'
        'lib/vm-fast-lane-readiness.ps1'
    )
    $script:OperatorRuntimes = @(
        'operator/fast-lane/build-vm-onboarding.ps1'
        'operator/fast-lane/invoke-git-outbox.ps1'
        'operator/fast-lane/invoke-vm-reset-live.ps1'
        'operator/fast-lane/providers/windows-vm-reset.ps1'
        'operator/realtime-relay/invoke-vm-smoke.ps1'
        'operator/realtime-relay/foreground-control.ps1'
        'operator/realtime-relay/invoke-foreground-cycle.ps1'
        'operator/realtime-relay/realtime-relay-client.ps1'
    )
    $script:RehearsalRelative = 'operator/fast-lane/invoke-synthetic-rehearsal.ps1'
    $script:RealtimeRelayProposalRelative = 'docs/REALTIME_RELAY_PROPOSAL.md'
    $script:RealtimeRelayReadmeRelative = 'operator/realtime-relay/README.md'
    . (Join-Path $script:RepoRoot 'scripts\check-worker.ps1') `
        -RepositoryRoot $script:RepoRoot `
        -SandboxRoot $script:RepoRoot `
        -RunId '00000000-0000-4000-8000-000000000001' `
        -RepositoryInventoryPath 'unused' `
        -BoundaryManifestPath 'unused' `
        -DependencyManifestPath 'unused' `
        -EngineId PowerShell7 `
        -EngineExecutablePath 'unused' `
        -EngineGrantSha256 ('a' * 64) `
        -GitExecutablePath 'unused\git.exe' `
        -GitGrantSha256 ('b' * 64) `
        -EvidenceBuilderOnly
}

Describe 'operator coordination static isolation boundary' {
    It 'classifies the local realtime relay contract as inactive DevelopmentOnly documentation' {
        @($script:ReleaseManifest.PackageFiles | Where-Object {
                $_ -ceq $script:RealtimeRelayProposalRelative
            }).Count | Should -Be 0
        @($script:ReleaseManifest.DevelopmentOnlyFiles | Where-Object {
                $_ -ceq $script:RealtimeRelayProposalRelative
            }).Count | Should -Be 1

        $proposalPath = Join-Path $script:RepoRoot $script:RealtimeRelayProposalRelative
        Test-Path -LiteralPath $proposalPath -PathType Leaf | Should -BeTrue
        $proposal = [IO.File]::ReadAllText(
            $proposalPath,
            [Text.UTF8Encoding]::new($false, $true)
        )
        foreach ($requiredText in @(
            'LOCAL_GATES_PASSED / EXTERNAL_AUTHORIZED_FREE_ONLY /'
            'WORKERS_PAID_NOT_LISTED / VM_RELAY_READY / PROVISIONED /'
            'CROSS_DEVICE_SMOKE_PASSED / FOREGROUND_RUNNER_LOCAL_TESTED /'
            'HOST_FOREGROUND_CREDENTIAL_READY / VM_FOREGROUND_CREDENTIAL_READY /'
            'VM_DEPLOY_KEY_REGISTERED / CLEAN_ROOM_EPOCH_DEPLOYED /'
            'FOREGROUND_CANARY_PENDING / NOT_PRIMARY / AUTOMATION_PAUSED'
            'invoke-vm-smoke.ps1 -PackagePath'
            'Cloudflare Worker + SQLite-backed Durable Object + WebSocket Hibernation'
            '`host-to-vm`'
            '`vm-to-host`'
            'HMAC 请求认证'
            '`CDDsi-HMAC-SHA256-v2`'
            '`ClientWebSocket`'
            'sibling infra repo'
            'immutable payload pointer'
            'Cloudflare 的公网 URL 不是 sender authority'
            'GitHub control repo'
            '一分钟轮询合同保留，但在 D-024 前台路径中未启用'
            '**Formal Lane**'
            '禁止自动 merge、release、promotion'
        )) {
            $proposal.IndexOf($requiredText, [StringComparison]::Ordinal) |
                Should -BeGreaterOrEqual 0
        }

        @($script:ReleaseManifest.PackageFiles | Where-Object {
                $_ -ceq $script:RealtimeRelayReadmeRelative
            }).Count | Should -Be 0
        @($script:ReleaseManifest.DevelopmentOnlyFiles | Where-Object {
                $_ -ceq $script:RealtimeRelayReadmeRelative
            }).Count | Should -Be 1
        $readmePath = Join-Path $script:RepoRoot $script:RealtimeRelayReadmeRelative
        Test-Path -LiteralPath $readmePath -PathType Leaf | Should -BeTrue
        $readme = [IO.File]::ReadAllText(
            $readmePath,
            [Text.UTF8Encoding]::new($false, $true)
        )
        foreach ($requiredText in @(
            'PROVISIONED / CROSS_DEVICE_SMOKE_PASSED /'
            'FOREGROUND_RUNNER_LOCAL_TESTED / HOST_FOREGROUND_CREDENTIAL_READY /'
            'VM_FOREGROUND_CREDENTIAL_READY / VM_DEPLOY_KEY_REGISTERED /'
            'CLEAN_ROOM_EPOCH_DEPLOYED / FOREGROUND_CANARY_PENDING / NOT_PRIMARY /'
            'AUTOMATION_PAUSED'
            '`invoke-foreground-cycle.ps1`'
            '`foreground-control.ps1`'
            'CDDsi_FOREGROUND_CONTROL_V1'
            '`ConvertFrom-CddsiRealtimeRelayForegroundControlBody`'
            '`invoke-vm-smoke.ps1 -PackagePath`'
            'New-CddsiRealtimeRelayLivePublisher'
            'Invoke-CddsiRealtimeRelayPublish'
            '`PendingPublish`'
            'PUBLISHED_IDEMPOTENT'
            '`exec resume --json <fixed-session-uuid> <fixed-source-prompt>`'
            '`REALTIME_WEBSOCKET_IDLE`'
            '`REMOVE_OWNED_RELAY_STATE`'
            'new environment epoch'
            'automation stays `PAUSED`'
        )) {
            $readme.IndexOf($requiredText, [StringComparison]::Ordinal) |
                Should -BeGreaterOrEqual 0
        }
    }

    It 'formats heterogeneous Pester error records without hiding the failed test' {
        $exception = [InvalidOperationException]::new('synthetic worker failure')
        $record = [Management.Automation.ErrorRecord]::new(
            $exception,
            'CDDsiSyntheticFailure',
            [Management.Automation.ErrorCategory]::InvalidOperation,
            $null
        )
        (Get-CddsiWorkerErrorRecordMessage -ErrorRecord $record) |
            Should -BeExactly 'synthetic worker failure'
        (Get-CddsiWorkerErrorRecordMessage -ErrorRecord ([pscustomobject]@{ Detail = 'shape-only' })) |
            Should -Match 'shape-only'
        (Get-CddsiWorkerErrorRecordMessage -ErrorRecord $null) |
            Should -BeExactly 'NO_ERROR_RECORD'
    }

    It 'owns exactly the DevelopmentOnly libraries outside product bootstrap and Release' {
        (@($script:Boundary.Planes.OperatorCoordination | Sort-Object) -join "`n") |
            Should -BeExactly (@($script:OperatorLibraries + $script:OperatorRuntimes | Sort-Object) -join "`n")
        (@($script:Boundary.Rules.OperatorCoordinationLibraryFiles | Sort-Object) -join "`n") |
            Should -BeExactly (@($script:OperatorLibraries | Sort-Object) -join "`n")

        foreach ($relative in $script:OperatorLibraries) {
            @($script:Boundary.Planes.ProductCore) | Should -Not -Contain $relative
            @($script:Boundary.Planes.LiveAdapters) | Should -Not -Contain $relative
            @($script:Boundary.Rules.DefaultBootstrapLibraryFiles) | Should -Not -Contain $relative
            @($script:ReleaseManifest.PackageFiles) | Should -Not -Contain $relative
            @($script:ReleaseManifest.DevelopmentOnlyFiles) | Should -Contain $relative
            $script:PublicContract.Files.ContainsKey($relative) | Should -BeTrue
        }
    }

    It 'owns exact DevelopmentOnly operator runtimes with narrow capability declarations' {
        (@($script:Boundary.Rules.OperatorRuntimeFiles | Sort-Object) -join "`n") |
            Should -BeExactly (@($script:OperatorRuntimes | Sort-Object) -join "`n")
        (@($script:Boundary.Rules.OperatorRuntimeEntryPoints.Keys | Sort-Object) -join "`n") |
            Should -BeExactly (@($script:OperatorRuntimes | Sort-Object) -join "`n")
        @($script:Boundary.Rules.OperatorRuntimeEntryPoints['operator/fast-lane/invoke-git-outbox.ps1']) |
            Should -BeExactly @(
                'Invoke-CddsiFastLaneGitOutbox'
                'Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding'
            )
        @($script:Boundary.Rules.OperatorRuntimeEntryPoints['operator/realtime-relay/realtime-relay-client.ps1']) |
            Should -BeExactly @(
                'Invoke-CddsiRealtimeRelayWatcher'
                'Invoke-CddsiRealtimeRelayPublish'
                'Set-CddsiRealtimeRelayDpapiCredential'
                'New-CddsiRealtimeRelayDpapiCredentialProvider'
                'New-CddsiRealtimeRelayFixedGitOutboxWakeProvider'
                'New-CddsiRealtimeRelayOwnedStateProvider'
                'Remove-CddsiRealtimeRelayOwnedState'
                'New-CddsiRealtimeRelayLiveProvider'
                'New-CddsiRealtimeRelayLivePublisher'
            )
        @($script:Boundary.Rules.OperatorRuntimeEntryPoints['operator/realtime-relay/invoke-vm-smoke.ps1']) |
            Should -BeExactly @('Invoke-CddsiRelayVmSmoke')
        @($script:Boundary.Rules.OperatorRuntimeEntryPoints['operator/realtime-relay/foreground-control.ps1']) |
            Should -BeExactly @('ConvertFrom-CddsiRealtimeRelayForegroundControlBody')
        @($script:Boundary.Rules.OperatorRuntimeEntryPoints['operator/realtime-relay/invoke-foreground-cycle.ps1']) |
            Should -BeExactly @('Invoke-CddsiRealtimeRelayForegroundCycle')
        @($script:Boundary.Rules.OperatorRuntimeNetworkFiles) |
            Should -BeExactly @(
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/realtime-relay/invoke-vm-smoke.ps1'
                'operator/realtime-relay/realtime-relay-client.ps1'
            )
        @($script:Boundary.Rules.OperatorRuntimeCredentialFiles) |
            Should -BeExactly @('operator/realtime-relay/realtime-relay-client.ps1')
        @($script:Boundary.Rules.OperatorRuntimeFileSystemFiles) |
            Should -BeExactly @(
                'operator/fast-lane/build-vm-onboarding.ps1'
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/fast-lane/providers/windows-vm-reset.ps1'
                'operator/realtime-relay/invoke-vm-smoke.ps1'
                'operator/realtime-relay/realtime-relay-client.ps1'
            )
        @($script:Boundary.Rules.OperatorRuntimeProcessFiles) |
            Should -BeExactly @(
                'operator/fast-lane/build-vm-onboarding.ps1'
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/fast-lane/providers/windows-vm-reset.ps1'
                'operator/realtime-relay/realtime-relay-client.ps1'
            )
        @($script:Boundary.Rules.OperatorRuntimeReflectionFiles) |
            Should -BeExactly @(
                'operator/fast-lane/build-vm-onboarding.ps1'
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/fast-lane/providers/windows-vm-reset.ps1'
            )
        @($script:Boundary.Rules.OperatorRuntimeDynamicInvocationFiles) |
            Should -BeExactly @(
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/fast-lane/invoke-vm-reset-live.ps1'
                'operator/fast-lane/providers/windows-vm-reset.ps1'
                'operator/realtime-relay/invoke-vm-smoke.ps1'
                'operator/realtime-relay/invoke-foreground-cycle.ps1'
                'operator/realtime-relay/realtime-relay-client.ps1'
            )
        @($script:Boundary.Rules.OperatorRuntimeVmInspectionFiles) |
            Should -BeExactly @('operator/fast-lane/providers/windows-vm-reset.ps1')
        @($script:Boundary.Rules.OperatorRuntimeVmMutationFiles) |
            Should -BeExactly @('operator/fast-lane/providers/windows-vm-reset.ps1')

        foreach ($relative in $script:OperatorRuntimes) {
            @($script:Boundary.Planes.ProductCore) | Should -Not -Contain $relative
            @($script:Boundary.Planes.LiveAdapters) | Should -Not -Contain $relative
            @($script:Boundary.Planes.TrustedHarness) | Should -Not -Contain $relative
            @($script:ReleaseManifest.PackageFiles) | Should -Not -Contain $relative
            @($script:ReleaseManifest.DevelopmentOnlyFiles) | Should -Contain $relative

            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot $relative),
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $commands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))
            @($commands | ForEach-Object { $_.GetCommandName() } | Where-Object {
                @('Invoke-Expression', 'Register-ScheduledTask', 'Unregister-ScheduledTask',
                    'Restart-Computer', 'cmd', 'cmd.exe') -ccontains $_
            }).Count | Should -Be 0
        }
    }

    It 'derives an actual capability set exactly equal to every operator runtime allow-list' {
        $actualByCapability = [ordered]@{
            DynamicInvocation = @()
            FileSystem        = @()
            Process           = @()
            Network           = @()
            Credential        = @()
            Reflection        = @()
            VmInspection      = @()
            VmMutation        = @()
        }
        foreach ($relative in $script:OperatorRuntimes) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot $relative),
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $observation = Get-CddsiOperatorRuntimeCapabilityObservation `
                -Ast $ast -SourceText $ast.Extent.Text
            foreach ($capabilityName in @($actualByCapability.Keys)) {
                if ($observation.$capabilityName) {
                    $actualByCapability[$capabilityName] =
                        @($actualByCapability[$capabilityName]) + @($relative)
                }
            }
        }

        {
            Assert-CddsiOperatorRuntimeCapabilityAllowLists `
                -RuntimeFiles $script:OperatorRuntimes `
                -Rules $script:Boundary.Rules `
                -ActualByCapability $actualByCapability
        } | Should -Not -Throw
    }

    It 'detects <Capability> from the synthetic <Primitive> primitive' -TestCases @(
        @{ Capability = 'DynamicInvocation'; Primitive = 'dynamic invocation'; Source = 'function Invoke-Synthetic { param($Target) & $Target }' }
        @{ Capability = 'FileSystem'; Primitive = 'file read'; Source = "function Invoke-Synthetic { [IO.File]::ReadAllText('x') }" }
        @{ Capability = 'Process'; Primitive = 'process start'; Source = "function Invoke-Synthetic { [System.Diagnostics.Process]::Start('x') }" }
        @{ Capability = 'Network'; Primitive = 'web request'; Source = 'function Invoke-Synthetic { Invoke-WebRequest https://example.invalid }' }
        @{ Capability = 'Network'; Primitive = 'Net alias type'; Source = 'function Invoke-Synthetic { [Net.Http.HttpClient]::new() }' }
        @{ Capability = 'Credential'; Primitive = 'DPAPI CurrentUser'; Source = 'function Invoke-Synthetic { [Security.Cryptography.ProtectedData]::Protect($a, $b, [Security.Cryptography.DataProtectionScope]::CurrentUser) }' }
        @{ Capability = 'Reflection'; Primitive = 'Add-Type'; Source = "function Invoke-Synthetic { Add-Type -TypeDefinition 'class X {}' }" }
        @{ Capability = 'VmInspection'; Primitive = 'CIM inspection'; Source = 'function Invoke-Synthetic { Get-CimInstance Win32_ComputerSystem }' }
        @{ Capability = 'VmInspection'; Primitive = 'AppX inspection'; Source = 'function Invoke-Synthetic { Get-AppxPackage }' }
        @{ Capability = 'VmInspection'; Primitive = 'registry inspection'; Source = "function Invoke-Synthetic { [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey('x') }" }
        @{ Capability = 'VmInspection'; Primitive = 'credential inspection'; Source = "function Invoke-Synthetic { Add-Type -TypeDefinition 'CredRead' }" }
        @{ Capability = 'VmMutation'; Primitive = 'AppX mutation'; Source = 'function Invoke-Synthetic { Remove-AppxPackage -Package synthetic }' }
        @{ Capability = 'VmMutation'; Primitive = 'registry mutation'; Source = "function Invoke-Synthetic { `$key.DeleteValue('x') }" }
        @{ Capability = 'VmMutation'; Primitive = 'credential mutation'; Source = "function Invoke-Synthetic { Add-Type -TypeDefinition 'CredDelete' }" }
        @{ Capability = 'VmMutation'; Primitive = 'owned reset file mutation'; Source = "function Invoke-CddsiWindowsVmResetResourceMutationInternal { [IO.File]::Delete('x') }" }
    ) {
        param($Capability, $Primitive, $Source)

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $Source,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $observation = Get-CddsiOperatorRuntimeCapabilityObservation `
            -Ast $ast -SourceText $Source
        $observation.$Capability | Should -BeTrue
    }

    It 'infers the builder Git helper process and reflection capabilities without network overreach' {
        $source = 'function Invoke-Synthetic { Invoke-CddsiFastLaneOnboardingSourceGit }'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseInput(
            $source,
            [ref]$tokens,
            [ref]$errors
        )
        $observation = Get-CddsiOperatorRuntimeCapabilityObservation -Ast $ast -SourceText $source
        $observation.Process | Should -BeTrue
        $observation.Reflection | Should -BeTrue
        $observation.Network | Should -BeFalse
    }

    It 'fails closed for both an undeclared capability and an over-declared capability' {
        $runtimeFiles = @('synthetic-runtime.ps1')
        $rules = [ordered]@{
            OperatorRuntimeDynamicInvocationFiles = @()
            OperatorRuntimeFileSystemFiles        = @()
            OperatorRuntimeProcessFiles           = @()
            OperatorRuntimeNetworkFiles           = @()
            OperatorRuntimeCredentialFiles        = @()
            OperatorRuntimeReflectionFiles        = @()
            OperatorRuntimeVmInspectionFiles      = @()
            OperatorRuntimeVmMutationFiles        = @()
        }
        $actual = [ordered]@{
            DynamicInvocation = @()
            FileSystem        = @('synthetic-runtime.ps1')
            Process           = @()
            Network           = @()
            Credential        = @()
            Reflection        = @()
            VmInspection      = @()
            VmMutation        = @()
        }
        {
            Assert-CddsiOperatorRuntimeCapabilityAllowLists `
                -RuntimeFiles $runtimeFiles -Rules $rules -ActualByCapability $actual
        } | Should -Throw '*OperatorRuntimeFileSystemFiles actual capability set drifted*'

        $actual.FileSystem = @()
        $rules.OperatorRuntimeFileSystemFiles = @('synthetic-runtime.ps1')
        {
            Assert-CddsiOperatorRuntimeCapabilityAllowLists `
                -RuntimeFiles $runtimeFiles -Rules $rules -ActualByCapability $actual
        } | Should -Throw '*OperatorRuntimeFileSystemFiles actual capability set drifted*'
    }

    It 'rejects credential capability in every operator runtime except the exact relay client' {
        $runtimeFiles = @(
            'operator/realtime-relay/realtime-relay-client.ps1'
            'synthetic-other-runtime.ps1'
        )
        $rules = [ordered]@{
            OperatorRuntimeDynamicInvocationFiles = @()
            OperatorRuntimeFileSystemFiles        = @()
            OperatorRuntimeProcessFiles           = @()
            OperatorRuntimeNetworkFiles           = @()
            OperatorRuntimeCredentialFiles        = @('operator/realtime-relay/realtime-relay-client.ps1')
            OperatorRuntimeReflectionFiles        = @()
            OperatorRuntimeVmInspectionFiles      = @()
            OperatorRuntimeVmMutationFiles        = @()
        }
        $actual = [ordered]@{
            DynamicInvocation = @()
            FileSystem        = @()
            Process           = @()
            Network           = @()
            Credential        = @('operator/realtime-relay/realtime-relay-client.ps1', 'synthetic-other-runtime.ps1')
            Reflection        = @()
            VmInspection      = @()
            VmMutation        = @()
        }

        {
            Assert-CddsiOperatorRuntimeCapabilityAllowLists `
                -RuntimeFiles $runtimeFiles -Rules $rules -ActualByCapability $actual
        } | Should -Throw '*OperatorRuntimeCredentialFiles actual capability set drifted*'
    }

    It 'keeps operator libraries declaration-only and free of direct host capabilities' {
        $forbiddenCommands = @($script:Boundary.Rules.ProductForbiddenCommands)
        $forbiddenVariables = @($script:Boundary.Rules.ProductForbiddenVariables)
        $forbiddenTypePrefixes = @($script:Boundary.Rules.ProductForbiddenTypePrefixes)

        foreach ($relative in $script:OperatorLibraries) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot $relative),
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            @($ast.EndBlock.Statements | Where-Object {
                $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $_ -isnot [System.Management.Automation.Language.AssignmentStatementAst]
            }).Count | Should -Be 0

            $commands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))
            @($commands | ForEach-Object { $_.GetCommandName() } | Where-Object {
                $_ -and $forbiddenCommands -ccontains $_
            } | Sort-Object -Unique).Count | Should -Be 0

            @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Where-Object {
                $forbiddenVariables -ccontains $_ -or $_.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase)
            } | Sort-Object -Unique).Count | Should -Be 0

            $typeNames = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.TypeExpressionAst] -or
                    $node -is [System.Management.Automation.Language.TypeConstraintAst]
            }, $true) | ForEach-Object { $_.TypeName.FullName } | Sort-Object -Unique)
            @($typeNames | Where-Object {
                $candidate = $_
                @($forbiddenTypePrefixes | Where-Object {
                    $candidate.StartsWith($_, [StringComparison]::OrdinalIgnoreCase)
                }).Count -gt 0
            }).Count | Should -Be 0
        }
    }

    It 'keeps the filesystem-writing rehearsal in the trusted harness with no Live mode' {
        @($script:Boundary.Planes.TrustedHarness) | Should -Contain $script:RehearsalRelative
        @($script:Boundary.Planes.OperatorCoordination) | Should -Not -Contain $script:RehearsalRelative
        @($script:Boundary.Rules.TrustedHarnessDynamicInvocationFiles) | Should -Contain $script:RehearsalRelative
        @($script:Boundary.Rules.TrustedHarnessProcessFiles) | Should -Not -Contain $script:RehearsalRelative
        @($script:Boundary.Rules.TrustedHarnessNetworkFiles) | Should -Not -Contain $script:RehearsalRelative
        @($script:ReleaseManifest.PackageFiles) | Should -Not -Contain $script:RehearsalRelative
        @($script:ReleaseManifest.DevelopmentOnlyFiles) | Should -Contain $script:RehearsalRelative

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:RepoRoot $script:RehearsalRelative),
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $entry = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Invoke-CddsiFastLaneSyntheticRehearsal'
        }, $true))
        $entry.Count | Should -Be 1
        $mode = @($entry[0].Body.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -ceq 'Mode'
        })
        $mode.Count | Should -Be 1
        $validateSet = @($mode[0].Attributes | Where-Object { $_.TypeName.FullName -ceq 'ValidateSet' })
        $validateSet.Count | Should -Be 1
        (@($validateSet[0].PositionalArguments | ForEach-Object { $_.Value }) -join "`n") |
            Should -BeExactly (@('TestSafe', 'DryRun') -join "`n")
    }
}
