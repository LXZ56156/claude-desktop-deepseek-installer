BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:Boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
    $script:ReleaseManifest = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'scripts\release-manifest.psd1')
    $script:LiveRelative = 'lib/live-adapters.ps1'
    $script:LivePath = Join-Path $script:RepoRoot $script:LiveRelative
    $script:LiveTokens = $null
    $script:LiveErrors = $null
    $script:LiveAst = [System.Management.Automation.Language.Parser]::ParseFile(
        $script:LivePath,
        [ref]$script:LiveTokens,
        [ref]$script:LiveErrors
    )
}

Describe 'Live adapter static isolation boundary' {
    It 'uses one exact packaged allow-list outside every locally executable plane' {
        @($script:Boundary.Planes.LiveAdapters).Count | Should -Be 1
        $script:Boundary.Planes.LiveAdapters[0] | Should -BeExactly $script:LiveRelative
        @($script:Boundary.Planes.ProductCore) | Should -Not -Contain $script:LiveRelative
        @($script:Boundary.Planes.Tests) | Should -Not -Contain $script:LiveRelative
        @($script:Boundary.Planes.TrustedHarness) | Should -Not -Contain $script:LiveRelative
        @($script:Boundary.Planes.OperatorCoordination) | Should -Not -Contain $script:LiveRelative
        @($script:ReleaseManifest.PackageFiles) | Should -Contain $script:LiveRelative
        @($script:ReleaseManifest.DevelopmentOnlyFiles) | Should -Not -Contain $script:LiveRelative
        @($script:ReleaseManifest.DevelopmentOnlyFiles) | Should -Contain 'tests/Contract/LiveAdapters.Tests.ps1'

        foreach ($ruleName in @('LiveAdapterEntryPoints', 'LiveAdapterCommandAllowList', 'LiveAdapterTypePrefixAllowList')) {
            @($script:Boundary.Rules[$ruleName].Keys).Count | Should -Be 1
            @($script:Boundary.Rules[$ruleName].Keys)[0] | Should -BeExactly $script:LiveRelative
        }
    }

    It 'contains declarations only and cannot dot-source import or dynamically invoke code' {
        @($script:LiveErrors).Count | Should -Be 0
        $topLevelStatements = @($script:LiveAst.EndBlock.Statements)
        $topLevelStatements.Count | Should -BeGreaterThan 0
        @($topLevelStatements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] }).Count | Should -Be 0

        $commands = @($script:LiveAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot -or
                $_.GetCommandName() -ieq 'Import-Module'
        }).Count | Should -Be 0
        @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -and
                [string]::IsNullOrWhiteSpace($_.GetCommandName())
        }).Count | Should -Be 0
        @($script:LiveAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.UsingStatementAst] }, $true)).Count | Should -Be 0
    }

    It 'requires the VM acceptance context and committed operation-use gate before any provider capability' {
        $functions = @($script:LiveAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $functions.Count | Should -Be 1
        $functions[0].Name | Should -BeExactly 'Invoke-CddsiLiveAdapterOperation'

        $requiredParameters = @(
            'Context', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState',
            'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc'
        )
        $parameters = @($functions[0].Body.ParamBlock.Parameters)
        (@($parameters | ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object) -join "`n") |
            Should -BeExactly (@($requiredParameters | Sort-Object) -join "`n")
        foreach ($parameter in $parameters) {
            $mandatoryArguments = @(
                $parameter.Attributes |
                    Where-Object { $_.TypeName.FullName -ceq 'Parameter' } |
                    ForEach-Object { $_.NamedArguments } |
                    Where-Object { $_.ArgumentName -ieq 'Mandatory' }
            )
            @($mandatoryArguments).Count | Should -Be 1
            $mandatoryArguments[0].Argument.Extent.Text | Should -BeExactly '$true'
        }

        $commands = @($script:LiveAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $assertGate = @($commands | Where-Object { $_.GetCommandName() -ceq 'Assert-CddsiExecutionContext' })
        $receiptGate = @($commands | Where-Object { $_.GetCommandName() -ceq 'Test-CddsiCommittedOperationUseReceipt' })
        $assertGate.Count | Should -Be 1
        $receiptGate.Count | Should -Be 1
        $assertGate[0].Extent.Text | Should -Match '(?i)-ExpectedMode\s+Live'
        $assertGate[0].Extent.StartOffset | Should -BeLessThan $receiptGate[0].Extent.StartOffset
        $functions[0].Extent.Text | Should -Match "(?s)EnvironmentTier\s+-cne\s+'VmAcceptance'"
        $functions[0].Extent.Text | Should -Match "(?s)Stage\s+-cne\s+'VmAcceptance'"
        $functions[0].Extent.Text | Should -Match "(?s)ArtifactProfile\s+-cne\s+'VmAcceptance'"
        foreach ($bindingName in @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc')) {
            $receiptGate[0].Extent.Text | Should -Match ('(?i)-' + [regex]::Escape($bindingName) + '\s+')
        }

        $forbiddenCommands = @($script:Boundary.Rules.ProductForbiddenCommands)
        $actualSystemCommands = @(
            $commands |
                ForEach-Object { $_.GetCommandName() } |
                Where-Object { $_ -and $forbiddenCommands -ccontains $_ } |
                Sort-Object -Unique
        )
        (@($actualSystemCommands) -join "`n") |
            Should -BeExactly (@($script:Boundary.Rules.LiveAdapterCommandAllowList[$script:LiveRelative] | Sort-Object) -join "`n")
    }

    It 'keeps the exact default bootstrap graph disjoint from Live adapters' {
        $tokens = $null
        $errors = $null
        $bootstrapAst = [System.Management.Automation.Language.Parser]::ParseFile(
            (Join-Path $script:RepoRoot 'lib\bootstrap.ps1'),
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $assignments = @($bootstrapAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left.VariablePath.UserPath -ceq 'script:CddsiLibraryLoadOrder'
        }, $true))
        $assignments.Count | Should -Be 1
        $actualLoadOrder = @($assignments[0].Right.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
        }, $true) | ForEach-Object { 'lib/' + [string]$_.Value })
        ($actualLoadOrder -join "`n") | Should -BeExactly (@($script:Boundary.Rules.DefaultBootstrapLibraryFiles) -join "`n")
        @($actualLoadOrder) | Should -Not -Contain $script:LiveRelative
        foreach ($relative in $actualLoadOrder) {
            @($script:Boundary.Planes.ProductCore) | Should -Contain $relative
        }
    }

    It 'prevents ProductCore tests and trusted harness code from loading the Live adapter' {
        $liveLeaf = @($script:LiveRelative -split '/')[-1]
        foreach ($relative in @(
            $script:Boundary.Planes.ProductCore + $script:Boundary.Planes.Tests +
            $script:Boundary.Planes.TrustedHarness + $script:Boundary.Planes.OperatorCoordination
        )) {
            if ($relative -notmatch '\.(ps1|psm1)$') { continue }
            $fileParseTokens = $null
            $fileParseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $relative), [ref]$fileParseTokens, [ref]$fileParseErrors)
            if (@($fileParseErrors).Count -gt 0) {
                @($script:Boundary.Planes.ProductCore) | Should -Contain $relative
                @($script:Boundary.Rules.ProductDotSourceAllowList.Keys) | Should -Not -Contain $relative
                (Get-Content -LiteralPath (Join-Path $script:RepoRoot $relative) -Raw).Replace('\', '/') |
                    Should -Not -Match ([regex]::Escape($liveLeaf))
                continue
            }
            $loadCommands = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    ($node.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot -or
                    $node.GetCommandName() -ieq 'Import-Module')
            }, $true))
            foreach ($loadCommand in $loadCommands) {
                $loadCommand.Extent.Text.Replace('\', '/') | Should -Not -Match ([regex]::Escape($liveLeaf))
                $variableNames = @($loadCommand.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.VariableExpressionAst]
                }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
                foreach ($variableName in $variableNames) {
                    $assignments = @($ast.FindAll({
                        param($node)
                        $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                            $node.Left -is [System.Management.Automation.Language.VariableExpressionAst] -and
                            $node.Left.VariablePath.UserPath -ceq $variableName
                    }, $true))
                    foreach ($assignment in $assignments) {
                        $assignment.Right.Extent.Text.Replace('\', '/') | Should -Not -Match ([regex]::Escape($liveLeaf))
                    }
                }
            }
            $usingStatements = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.UsingStatementAst] }, $true))
            foreach ($usingStatement in $usingStatements) {
                $usingStatement.Extent.Text.Replace('\', '/') | Should -Not -Match ([regex]::Escape($liveLeaf))
            }
        }
    }
}
