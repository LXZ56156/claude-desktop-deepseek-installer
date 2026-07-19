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
    )
    $script:RehearsalRelative = 'operator/fast-lane/invoke-synthetic-rehearsal.ps1'
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
        @($script:Boundary.Rules.OperatorRuntimeNetworkFiles) |
            Should -BeExactly @('operator/fast-lane/invoke-git-outbox.ps1')
        @($script:Boundary.Rules.OperatorRuntimeFileSystemFiles) |
            Should -BeExactly @(
                'operator/fast-lane/build-vm-onboarding.ps1'
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/fast-lane/providers/windows-vm-reset.ps1'
            )
        @($script:Boundary.Rules.OperatorRuntimeProcessFiles) |
            Should -BeExactly @(
                'operator/fast-lane/build-vm-onboarding.ps1'
                'operator/fast-lane/invoke-git-outbox.ps1'
                'operator/fast-lane/providers/windows-vm-reset.ps1'
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
            OperatorRuntimeReflectionFiles        = @()
            OperatorRuntimeVmInspectionFiles      = @()
            OperatorRuntimeVmMutationFiles        = @()
        }
        $actual = [ordered]@{
            DynamicInvocation = @()
            FileSystem        = @('synthetic-runtime.ps1')
            Process           = @()
            Network           = @()
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
