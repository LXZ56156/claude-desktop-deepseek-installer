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

    function Get-CddsiLiveAdapterTestSha256 {
        param([Parameter(Mandatory = $true)][string]$Text)

        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes($Text)
        $algorithm = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [System.BitConverter]::ToString(
                $algorithm.ComputeHash($bytes)
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $algorithm.Dispose()
        }
    }

    function Get-CddsiLiveAdapterFunctionSourceDigestContracts {
        param([Parameter(Mandatory = $true)]$Ast)

        return @(
            $Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) |
                ForEach-Object {
                    $normalizedSource = $_.Extent.Text.Replace("`r`n", "`n").Replace("`r", "`n")
                    '{0}|{1}' -f $_.Name, (Get-CddsiLiveAdapterTestSha256 -Text $normalizedSource)
                } |
                Sort-Object
        )
    }
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

        foreach ($ruleName in @(
            'LiveAdapterEntryPoints',
            'LiveAdapterCommandAllowList',
            'LiveAdapterTypePrefixAllowList',
            'LiveAdapterDirectPipelineAllowList',
            'LiveAdapterFunctionSourceDigestAllowList',
            'LiveAdapterSystemCapabilitySites'
        )) {
            @($script:Boundary.Rules[$ruleName].Keys).Count | Should -Be 1
            @($script:Boundary.Rules[$ruleName].Keys)[0] | Should -BeExactly $script:LiveRelative
        }
        $script:Boundary.Rules.LiveAdapterLoadEntryPoint | Should -BeExactly 'Invoke-CddsiLiveAdapterOperation'
        $script:Boundary.Rules.LiveAdapterProviderEntryPoint | Should -BeExactly 'Invoke-CddsiLiveReadOnlyProviderOperation'
        (@($script:Boundary.Rules.LiveAdapterEntryPoints[$script:LiveRelative] | Sort-Object) -join "`n") |
            Should -BeExactly ((@(
                'Invoke-CddsiLiveAdapterOperation'
                'Invoke-CddsiLiveReadOnlyProviderOperation'
            ) | Sort-Object) -join "`n")
        $script:Boundary.Rules.LiveAdapterRequiredOperation | Should -BeExactly 'LoadLiveProviders'
        $bindingTexts = @(
            $script:Boundary.Rules.LiveAdapterAllowedBindings |
                ForEach-Object {
                    (@($_.Keys | ForEach-Object { [string]$_ } | Sort-Object) -join "`n") |
                        Should -BeExactly ((@('ArtifactProfile', 'EnvironmentTier', 'Stage') | Sort-Object) -join "`n")
                    '{0}|{1}|{2}' -f $_.EnvironmentTier, $_.Stage, $_.ArtifactProfile
                } |
                Sort-Object
        )
        ($bindingTexts -join "`n") | Should -BeExactly ((@(
            'UserLive|UserLive|UserLive'
            'VmAcceptance|VmAcceptance|VmAcceptance'
            'VmDevelopment|VmDevelopment|VmDevelopment'
        ) | Sort-Object) -join "`n")
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

        $configuredFunctionDigests = @(
            $script:Boundary.Rules.LiveAdapterFunctionSourceDigestAllowList[$script:LiveRelative] |
                ForEach-Object { [string]$_ }
        )
        $configuredFunctionDigests.Count | Should -Be 2
        @($configuredFunctionDigests | Sort-Object -Unique).Count | Should -Be 2
        @($configuredFunctionDigests | Where-Object {
            $_ -cnotmatch '^[A-Za-z][A-Za-z0-9-]*\|[a-f0-9]{64}$'
        }).Count | Should -Be 0
        (Get-CddsiLiveAdapterTestSha256 -Text ($configuredFunctionDigests -join "`n")) |
            Should -BeExactly '3d565a3d288c564ad0459b346a059c68c5b90df2994552741c4b939370a8cc3c'
        $actualFunctionDigests = @(Get-CddsiLiveAdapterFunctionSourceDigestContracts -Ast $script:LiveAst)
        ($actualFunctionDigests -join "`n") |
            Should -BeExactly ((@($configuredFunctionDigests | Sort-Object)) -join "`n")
    }

    It 'binds the package hash and committed LoadLiveProviders receipt before installing a loaded read-only context' {
        $functions = @($script:LiveAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $functions.Count | Should -Be 2
        (@($functions.Name | Sort-Object) -join "`n") | Should -BeExactly ((@(
            'Invoke-CddsiLiveAdapterOperation'
            'Invoke-CddsiLiveReadOnlyProviderOperation'
        ) | Sort-Object) -join "`n")
        $loadFunction = @($functions | Where-Object Name -CEQ 'Invoke-CddsiLiveAdapterOperation')[0]
        $requiredParameters = @(
            'Context', 'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState',
            'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc', 'AdapterSha256'
        )
        $parameters = @($loadFunction.Body.ParamBlock.Parameters)
        (@($parameters | ForEach-Object { $_.Name.VariablePath.UserPath } | Sort-Object) -join "`n") |
            Should -BeExactly (@($requiredParameters | Sort-Object) -join "`n")
        foreach ($parameter in $parameters) {
            @(
                $parameter.Attributes |
                    Where-Object { $_.TypeName.FullName -ceq 'Parameter' } |
                    ForEach-Object { $_.NamedArguments } |
                    Where-Object { $_.ArgumentName -ieq 'Mandatory' }
            ).Count | Should -Be 1
        }

        $commands = @($loadFunction.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        $assertGates = @($commands | Where-Object { $_.GetCommandName() -ceq 'Assert-CddsiExecutionContext' } | Sort-Object { $_.Extent.StartOffset })
        $receiptGates = @($commands | Where-Object { $_.GetCommandName() -ceq 'Test-CddsiCommittedOperationUseReceipt' })
        $assertGates.Count | Should -Be 2
        $receiptGates.Count | Should -Be 1
        $assertGates[0].Extent.Text | Should -Match '(?i)-ExpectedMode\s+Live'
        $assertGates[1].Extent.Text | Should -Match '(?i)-ExpectedMode\s+Live'
        $assertGates[0].Extent.StartOffset | Should -BeLessThan $receiptGates[0].Extent.StartOffset
        foreach ($bindingName in @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState', 'Operation', 'OperationUseId', 'ValidationTimeUtc')) {
            $receiptGates[0].Extent.Text | Should -Match ('(?i)-' + [regex]::Escape($bindingName) + '\s+')
        }

        $bindingHashtableNodes = @($loadFunction.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.HashtableAst]) { return $false }
            $keys = @($node.KeyValuePairs | ForEach-Object {
                if ($_.Item1 -is [System.Management.Automation.Language.StringConstantExpressionAst]) { [string]$_.Item1.Value }
            } | Sort-Object)
            return (($keys -join "`n") -ceq ((@('ArtifactProfile', 'EnvironmentTier', 'Stage') | Sort-Object) -join "`n"))
        }, $true))
        $sourceBindingTexts = @()
        foreach ($bindingNode in $bindingHashtableNodes) {
            $bindingValues = @{}
            foreach ($pair in @($bindingNode.KeyValuePairs)) {
                $valueNodes = @($pair.Item2.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.StringConstantExpressionAst]
                }, $true))
                $valueNodes.Count | Should -Be 1
                $bindingValues[[string]$pair.Item1.Value] = [string]$valueNodes[0].Value
            }
            $sourceBindingTexts += '{0}|{1}|{2}' -f $bindingValues.EnvironmentTier, $bindingValues.Stage, $bindingValues.ArtifactProfile
        }
        (@($sourceBindingTexts | Sort-Object) -join "`n") | Should -BeExactly ((@(
            'UserLive|UserLive|UserLive'
            'VmAcceptance|VmAcceptance|VmAcceptance'
            'VmDevelopment|VmDevelopment|VmDevelopment'
        ) | Sort-Object) -join "`n")
        foreach ($requiredComparison in @(
            '$Context.EnvironmentTier', '$Context.Stage', '$StageManifest.Stage',
            '$StageManifest.ArtifactProfile', '$Context.RunId', '$OperationGrant.RunId'
        )) {
            $beforeReceipt = @($loadFunction.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.BinaryExpressionAst] -and
                    $node.Extent.Text -cmatch [regex]::Escape($requiredComparison)
            }, $true) | Where-Object { $_.Extent.StartOffset -lt $receiptGates[0].Extent.StartOffset })
            $beforeReceipt.Count | Should -BeGreaterThan 0
        }
        $loadFunction.Extent.Text | Should -Match '\$Operation\s+-cne\s+[''"]LoadLiveProviders[''"]'
        $loadFunction.Extent.Text | Should -Match '\$AdapterSha256\s+-cnotmatch\s+[''"]\^\[a-f0-9\]\{64\}\$[''"]'

        $constructors = @($commands | Where-Object { $_.GetCommandName() -ceq 'New-CddsiLiveReadOnlyProviderSet' })
        $constructors.Count | Should -Be 1
        $constructors[0].Extent.StartOffset | Should -BeGreaterThan $receiptGates[0].Extent.EndOffset
        foreach ($parameterName in @(
            'RunId', 'Stage', 'EnvironmentTier', 'ArtifactProfile', 'AdapterSha256',
            'LoadOperationUseId', 'LoadReceiptBindingToken'
        )) {
            $constructors[0].Extent.Text | Should -Match ('(?i)-' + [regex]::Escape($parameterName) + '\s+')
        }
        $constructors[0].Extent.Text | Should -Match '-AdapterSha256\s+\$AdapterSha256'
        $constructors[0].Extent.Text | Should -Match '-LoadReceiptBindingToken\s+\$OperationUseState\.ReceiptBindingToken'
        $rollbackTryStatements = @($loadFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.TryStatementAst]
        }, $true))
        $rollbackTryStatements.Count | Should -Be 1
        $rollbackTry = $rollbackTryStatements[0]
        $rollbackTry.Finally | Should -BeNullOrEmpty
        $installStatements = @($rollbackTry.Body.Statements)
        $installStatements.Count | Should -Be 3
        $installStatements[0].Extent.Text |
            Should -BeExactly '$Context.Providers = $loadedProviderSet'
        $installStatements[1].Extent.Text |
            Should -BeExactly '$Context.AccessLedger.LiveProviderLoaded = $true'
        $installStatements[2].Extent.Text | Should -BeExactly (
            'Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null'
        )
        $preInstallCaptures = @($loadFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Extent.Text -in @(
                    '$previousProviderSet = $Context.Providers',
                    '$previousLiveProviderLoaded = $Context.AccessLedger.LiveProviderLoaded'
                )
        }, $true))
        $preInstallCaptures.Count | Should -Be 2
        foreach ($capture in $preInstallCaptures) {
            $capture.Extent.EndOffset | Should -BeLessThan $rollbackTry.Extent.StartOffset
        }
        @($rollbackTry.CatchClauses).Count | Should -Be 1
        $rollbackTry.CatchClauses[0].IsCatchAll | Should -BeTrue
        @($rollbackTry.CatchClauses[0].CatchTypes).Count | Should -Be 0
        $restoreStatements = @($rollbackTry.CatchClauses[0].Body.Statements)
        $restoreStatements.Count | Should -Be 3
        $restoreStatements[0].Extent.Text |
            Should -BeExactly '$Context.Providers = $previousProviderSet'
        $restoreStatements[1].Extent.Text |
            Should -BeExactly '$Context.AccessLedger.LiveProviderLoaded = $previousLiveProviderLoaded'
        $restoreStatements[2] |
            Should -BeOfType ([System.Management.Automation.Language.ThrowStatementAst])
        $restoreStatements[2].Pipeline | Should -BeNullOrEmpty
        $assertGates[1].Extent.StartOffset | Should -BeGreaterThan $constructors[0].Extent.EndOffset

        $successResults = @($commands | Where-Object {
            $_.GetCommandName() -ceq 'New-CddsiOperationResult' -and
                $_.Extent.Text -match '(?i)-Operation\s+[''"]LoadLiveProviders[''"]' -and
                $_.Extent.Text -match '(?i)-Status\s+[''"]?SUCCEEDED[''"]?' -and
                $_.Extent.Text -match '(?i)-Changed\s+\$false' -and
                $_.Extent.Text -match '(?i)-Mode\s+Live(?:\s|$)'
        })
        $successResults.Count | Should -Be 1
        $successResults[0].Extent.StartOffset | Should -BeGreaterThan $rollbackTry.Extent.EndOffset
        $loadFunction.Extent.Text | Should -Match '\.CapabilitySetDigest'
        $loadFunction.Extent.Text | Should -Not -Match 'LIVE_PROVIDER_LOAD_NOT_IMPLEMENTED'
    }

    It 'freezes eleven empty-argument capabilities and ledgers denied or unavailable dispatch without system access' {
        $expectedCapabilities = @(
            'Environment|Inspect|<ENVIRONMENT:WINDOWS>||WindowsEnvironmentObservation/v1'
            'Environment|Inspect|<ENVIRONMENT:HARDWARE_VIRTUALIZATION>||HardwareVirtualizationObservation/v1'
            'Environment|Inspect|<KNOWN_FOLDERS:CURRENT_USER>||CurrentUserKnownFoldersObservation/v1'
            'Package|Inspect|<PACKAGE:CLAUDE_DESKTOP>||ClaudeDesktopPackageInventory/v1'
            'Process|Inspect|<PROCESS:GIT_FOR_WINDOWS>||GitForWindowsInventory/v2'
            'Feature|Inspect|<FEATURE:VIRTUAL_MACHINE_PLATFORM>||VirtualMachinePlatformObservation/v1'
            'Service|Inspect|<SERVICE:COWORK>||CoworkServiceObservation/v1'
            'Registry|Inspect|<HKLM_MANAGED_POLICY>||ClaudeConfigSourceMetadata/v1'
            'Registry|Inspect|<HKCU_MANAGED_POLICY>||ClaudeConfigSourceMetadata/v1'
            'FileSystem|Inspect|<CONFIG_LIBRARY>||ClaudeConfigSourceMetadata/v1'
            'Process|Inspect|<PROCESS:CLAUDE_DESKTOP>||ClaudeDesktopProcessInventory/v1'
        )
        $actualCapabilities = @($script:Boundary.Rules.LiveReadOnlyCapabilities | ForEach-Object {
            (@($_.Keys | ForEach-Object { [string]$_ } | Sort-Object) -join "`n") |
                Should -BeExactly ((@('ArgumentNames', 'Operation', 'Provider', 'ResourceToken', 'ResultSchemaId') | Sort-Object) -join "`n")
            @($_.ArgumentNames).Count | Should -Be 0
            '{0}|{1}|{2}|{3}|{4}' -f $_.Provider, $_.Operation, $_.ResourceToken, (@($_.ArgumentNames) -join ','), $_.ResultSchemaId
        })
        ($actualCapabilities -join "`n") | Should -BeExactly ($expectedCapabilities -join "`n")

        $functions = @($script:LiveAst.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
        $providerFunction = @($functions | Where-Object Name -CEQ 'Invoke-CddsiLiveReadOnlyProviderOperation')[0]
        $parameters = @($providerFunction.Body.ParamBlock.Parameters)
        (@($parameters.Name.VariablePath.UserPath | Sort-Object) -join "`n") |
            Should -BeExactly ((@('Arguments', 'Context', 'Operation', 'Provider', 'ResourceToken') | Sort-Object) -join "`n")
        foreach ($parameter in $parameters) {
            @(
                $parameter.Attributes |
                    Where-Object { $_.TypeName.FullName -ceq 'Parameter' } |
                    ForEach-Object { $_.NamedArguments } |
                    Where-Object { $_.ArgumentName -ieq 'Mandatory' }
            ).Count | Should -Be 1
        }
        $commands = @($providerFunction.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        @($commands | Where-Object { $_.GetCommandName() -ceq 'Assert-CddsiExecutionContext' }).Count | Should -Be 1
        $deniedLedger = @($commands | Where-Object {
            $_.GetCommandName() -ceq 'Add-CddsiProductAccessLedgerEntry' -and $_.Extent.Text -match '(?i)-Outcome\s+Denied'
        })
        $providerFailureLedger = @($commands | Where-Object {
            $_.GetCommandName() -ceq 'Add-CddsiProductAccessLedgerEntry' -and $_.Extent.Text -match '(?i)-Outcome\s+ProviderFailure'
        })
        $deniedLedger.Count | Should -Be 1
        $providerFailureLedger.Count | Should -Be 1
        $deniedLedger[0].Extent.Text | Should -Match '(?i)-Allowed\s+\$false'
        $deniedLedger[0].Extent.Text | Should -Match '(?i)-Expected\s+\$false'
        $deniedLedger[0].Extent.Text | Should -Match '(?i)-Provider\s+\$Provider'
        $deniedLedger[0].Extent.Text | Should -Match '(?i)-Operation\s+\$ledgerOperation'
        $deniedLedger[0].Extent.Text | Should -Match '(?i)-ProviderEvidenceDigest\s+\$null'
        $providerFailureLedger[0].Extent.Text | Should -Match '(?i)-Allowed\s+\$true'
        $providerFailureLedger[0].Extent.Text | Should -Match '(?i)-Expected\s+\$true'
        $providerFailureLedger[0].Extent.Text | Should -Match '(?i)-Outcome\s+ProviderFailure'
        $providerFailureLedger[0].Extent.Text | Should -Match '(?i)-ProviderEvidenceDigest\s+\$null'
        foreach ($code in @(
            'LIVE_READ_ONLY_ARGUMENTS_DENIED', 'LIVE_READ_ONLY_RESOURCE_DENIED',
            'LIVE_READ_ONLY_CAPABILITY_DENIED', 'LIVE_READ_ONLY_PROVIDER_NOT_IMPLEMENTED'
        )) {
            $providerFunction.Extent.Text | Should -Match ([regex]::Escape($code))
        }
        foreach ($counterName in @('ForbiddenResourceAccessCount', 'UnexpectedEntryCount')) {
            $providerFunction.Extent.Text | Should -Match ('\$Context\.AccessLedger\.' + $counterName + '\s*=')
        }
        foreach ($providerName in @(
            'FileSystem', 'Environment', 'Registry', 'Process', 'Network',
            'Package', 'Feature', 'Service', 'Credential', 'Clock'
        )) {
            $providerFunction.Extent.Text | Should -Match ('\$Context\.Providers\.' + $providerName + '\.Capabilities')
        }
        $providerFunction.Extent.Text | Should -Not -Match '\$_\.Provider'

        $providerText = $providerFunction.Extent.Text
        $providerSwitches = @($providerFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.SwitchStatementAst] -and
                $node.Extent.Text -cmatch '^switch\s+-CaseSensitive\s+\(\$Provider\)'
        }, $true))
        $providerSwitches.Count | Should -Be 1
        $providerSwitches[0].Extent.StartOffset | Should -BeLessThan $deniedLedger[0].Extent.StartOffset
        $providerText | Should -Match '\$providerIsExact\s*=\s*\$true'
        $providerText | Should -Match 'default\s*\{\s*\$providerIsExact\s*=\s*\$false'
        $providerText | Should -Match (
            '\$ledgerOperation\s*=\s*if(?s:.*?)else\s*\{\s*' +
            '[''"]RejectedCapability[''"]'
        )
        $providerGateBranches = @($providerFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.IfStatementAst] -and
                $node.Extent.Text -cmatch '^if\s*\(-not\s+\$providerIsExact\)'
        }, $true))
        $providerGateBranches.Count | Should -Be 1
        $providerGate = $providerGateBranches[0]
        $providerGate.Extent.Text |
            Should -Match 'throw\s+[''"]LIVE_READ_ONLY_CAPABILITY_DENIED[''"]'
        $providerGate.Extent.StartOffset | Should -BeGreaterThan $providerSwitches[0].Extent.EndOffset
        $providerGate.Extent.EndOffset | Should -BeLessThan $deniedLedger[0].Extent.StartOffset
        @($providerGate.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.GetCommandName() -ceq 'Add-CddsiProductAccessLedgerEntry'
        }, $true)).Count | Should -Be 0
        @($providerGate.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -cmatch '^\$Context\.'
        }, $true)).Count | Should -Be 0
        $contextAsserts = @($commands | Where-Object {
            $_.GetCommandName() -ceq 'Assert-CddsiExecutionContext'
        })
        $contextAsserts.Count | Should -Be 1
        $contextAsserts[0].Extent.EndOffset | Should -BeLessThan $providerSwitches[0].Extent.StartOffset
        $allCapabilityAssignments = @($providerFunction.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq '$allCapabilities'
        }, $true))
        $allCapabilityAssignments.Count | Should -Be 1
        $allCapabilityAssignments[0].Extent.StartOffset |
            Should -BeGreaterThan $providerSwitches[0].Extent.EndOffset

        $liveText = [System.IO.File]::ReadAllText($script:LivePath)
        foreach ($pattern in @($script:Boundary.Rules.LiveAdapterForbiddenTextPatterns)) {
            $liveText | Should -Not -Match $pattern
        }
        $variables = @($script:LiveAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
        @($variables | Where-Object {
            @($script:Boundary.Rules.LiveAdapterForbiddenVariableNames) -ccontains $_ -or
                $_.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase)
        }).Count | Should -Be 0
        $systemCommands = @($commands | Where-Object {
            $name = $_.GetCommandName()
            $name -and @($script:Boundary.Rules.LiveAdapterSystemCapabilityCommands) -ccontains $name
        })
        $systemCommands.Count | Should -Be 0
        @($script:Boundary.Rules.LiveAdapterSystemCapabilitySites[$script:LiveRelative]).Count | Should -Be 0
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
