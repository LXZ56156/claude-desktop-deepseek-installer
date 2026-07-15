BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
    $script:ReleaseManifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'scripts\release-manifest.psd1')
    $script:PublicContract = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\public-functions.psd1')
    $script:OperatorLibraries = @('lib/vm-test-relay.ps1', 'lib/vm-reset.ps1')
    $script:RehearsalRelative = 'operator/fast-lane/invoke-synthetic-rehearsal.ps1'
}

Describe 'operator coordination static isolation boundary' {
    It 'owns exactly the two DevelopmentOnly libraries outside product bootstrap and Release' {
        (@($script:Boundary.Planes.OperatorCoordination | Sort-Object) -join "`n") |
            Should -BeExactly (@($script:OperatorLibraries | Sort-Object) -join "`n")
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
