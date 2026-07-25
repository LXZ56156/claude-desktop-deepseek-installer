BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function New-CddsiSafetyArtifactDescriptor {
        param([string]$ArtifactType)
        $msix = $ArtifactType -ceq 'ClaudeDesktopMsix'
        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1; DescriptorId = if ($msix) { 'safety-msix' } else { 'safety-git' }; ArtifactType = $ArtifactType
            SourcePolicy = if ($msix) { 'anthropic_official_only' } else { 'git_for_windows_official_only' }
            SourceUri = if ($msix) { 'https://downloads.claude.com/synthetic-fixtures/safety.msix' } else { 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.3/Git-2.53.0-64-bit.exe' }
            SourceUriBindingToken = $null; ReleaseVersion = if ($msix) { '1.20186.0' } else { '2.53.0' }; Architecture = 'x64'; Channel = if ($msix) { 'Standard' } else { 'Installer' }
            FileNameToken = if ($msix) { '<ARTIFACT_FILE:SAFETY_MSIX>' } else { '<ARTIFACT_FILE:SAFETY_GIT>' }
            ExpectedArtifactSha256 = ('a' * 64); ExpectedArtifactSizeBytes = [long]1000; ExpectedSignerThumbprint = ('1' * 40)
            ExpectedSignerSubjectToken = '<SIGNER_SUBJECT:SAFETY>'; ExpectedPublisherToken = '<PUBLISHER:SAFETY>'; ExpectedIdentityToken = '<IDENTITY:SAFETY>'
            RedirectPolicy = 'same-owner-https-only'; MaximumBytes = [long]2000; MetadataStatus = 'READY'
        }
        $withoutBinding.SourceUriBindingToken = Get-CddsiSourceUriBindingToken -SourceUri $withoutBinding.SourceUri
        $descriptor = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) { $descriptor[$property.Name] = $property.Value }
        $descriptor['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
        return [pscustomobject]$descriptor
    }

    function New-CddsiSafetySourceObservation {
        param($Descriptor, [string]$RunId, [string]$ArtifactProfile = 'VmAcceptance')
        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-source-observation-v1'
            RunId = $RunId
            ArtifactProfile = $ArtifactProfile
            DescriptorId = $Descriptor.DescriptorId
            MetadataBindingToken = $Descriptor.MetadataBindingToken
            RequestUri = $Descriptor.SourceUri
            FinalUri = $Descriptor.SourceUri
            RedirectUris = @()
            RedirectChainBindingToken = Get-CddsiSupplyChainTextBindingToken -Text $Descriptor.SourceUri
            RedirectCount = 0
            ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes
            ObservationId = 'synthetic-safety-source'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
        $result = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) { $result[$property.Name] = $property.Value }
        $result['SourceObservationBindingToken'] = Get-CddsiSourceObservationBindingToken -Observation $withoutBinding
        return [pscustomobject]$result
    }

    function Get-CddsiSafetyDirectPipelineContracts {
        param($Ast)

        $contracts = @(
            $functions = @($Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true))
            foreach ($entryPoint in $functions) {
                $directPipelines = @($entryPoint.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.PipelineAst] -and
                        ($node.Parent -is [System.Management.Automation.Language.NamedBlockAst] -or
                        $node.Parent -is [System.Management.Automation.Language.StatementBlockAst])
                }, $true))
                foreach ($pipeline in $directPipelines) {
                    $captureTarget = $null
                    $ancestor = $pipeline.Parent
                    while ($null -ne $ancestor -and $ancestor -ne $entryPoint) {
                        if ($ancestor -is [System.Management.Automation.Language.AssignmentStatementAst]) {
                            $captureTarget = $ancestor.Left.Extent.Text
                            break
                        }
                        $ancestor = $ancestor.Parent
                    }
                    if ($null -eq $captureTarget) {
                        $pipelineElements = @($pipeline.PipelineElements)
                        $lastPipelineElement = if ($pipelineElements.Count -gt 0) {
                            $pipelineElements[-1]
                        }
                        else {
                            $null
                        }
                        if ($lastPipelineElement -is [System.Management.Automation.Language.CommandAst] -and
                            $lastPipelineElement.GetCommandName() -ceq 'Out-Null') {
                            $captureTarget = '<SUPPRESSED>'
                        }
                        else {
                            $captureTarget = '<UNBOUND>'
                        }
                    }
                    $normalizedExtent = $pipeline.Extent.Text.Replace("`r`n", "`n").Replace("`r", "`n")
                    '{0}|{1}|{2}|{3}' -f
                        $entryPoint.Name,
                        $pipeline.Parent.GetType().Name,
                        $captureTarget,
                        (Get-CddsiSupplyChainTextBindingToken -Text $normalizedExtent)
                }
            }
        )
        return @($contracts | Sort-Object)
    }

    function Get-CddsiSafetyFunctionSourceDigestContracts {
        param($Ast)

        return @(
            $Ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
            }, $true) |
                ForEach-Object {
                    $normalizedSource = $_.Extent.Text.Replace("`r`n", "`n").Replace("`r", "`n")
                    '{0}|{1}' -f $_.Name, (
                        Get-CddsiSupplyChainTextBindingToken -Text $normalizedSource
                    )
                } |
                Sort-Object
        )
    }

    function Add-CddsiSafetyFalseWrapper {
        param(
            [string]$Source,
            [string]$StartAnchor
        )

        $newLine = if ($Source.Contains("`r`n")) { "`r`n" } else { "`n" }
        $start = $Source.IndexOf($StartAnchor, [StringComparison]::Ordinal)
        if ($start -lt 0) {
            throw "Synthetic wrapper start anchor was not found: $StartAnchor"
        }
        $closingText = $newLine + '    }'
        $closingStart = $Source.IndexOf($closingText, $start, [StringComparison]::Ordinal)
        if ($closingStart -lt 0) {
            throw "Synthetic wrapper closing statement was not found: $StartAnchor"
        }
        $end = $closingStart + $closingText.Length
        $originalBlock = $Source.Substring($start, $end - $start)
        return $Source.Substring(0, $start) +
            '    if ($false) {' + $newLine +
            $originalBlock + $newLine +
            '    }' +
            $Source.Substring($end)
    }
}

Describe 'scaffold safety boundary' {
    It 'keeps MSIX, Git, Windows feature and process actions planned only' {
        $testSafeContext = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $dryRunContext = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -Mode DryRun -RunId '00000000-0000-0000-0000-000000000102'
        $msixDescriptor = New-CddsiSafetyArtifactDescriptor -ArtifactType ClaudeDesktopMsix
        $gitDescriptor = New-CddsiSafetyArtifactDescriptor -ArtifactType GitForWindowsInstaller
        (Save-CddsiOfficialClaudeDesktopMsix -ExecutionContext $testSafeContext -DestinationPath (Join-Path $TestDrive 'Claude.msix') -ArtifactDescriptor $msixDescriptor -Mode TestSafe).Changed | Should -BeFalse
        (Save-CddsiOfficialGitInstaller -ExecutionContext $dryRunContext -DestinationPath (Join-Path $TestDrive 'git.exe') -ArtifactDescriptor $gitDescriptor -Mode DryRun).Changed | Should -BeFalse
        (Enable-CddsiVirtualMachinePlatform -ExecutionContext $testSafeContext -Mode TestSafe).Changed | Should -BeFalse
        (Stop-CddsiClaudeDesktop -ExecutionContext $dryRunContext -Mode DryRun).Changed | Should -BeFalse
        (Start-CddsiClaudeDesktop -ExecutionContext $testSafeContext -Mode TestSafe).Changed | Should -BeFalse
        Assert-CddsiFakeProviderExpectations -ExecutionContext $testSafeContext -RequireNoMutations | Should -BeTrue
        Assert-CddsiFakeProviderExpectations -ExecutionContext $dryRunContext -RequireNoMutations | Should -BeTrue
        Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $testSafeContext) | Should -BeTrue
        Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $dryRunContext) | Should -BeTrue
    }

    It 'rejects every attempted Live action even with acknowledgement' {
        $context = New-CddsiTestExecutionContext
        $descriptor = New-CddsiSafetyArtifactDescriptor -ArtifactType ClaudeDesktopMsix
        { Save-CddsiOfficialClaudeDesktopMsix -ExecutionContext $context -DestinationPath 'C:\synthetic\unused.msix' -ArtifactDescriptor $descriptor -Mode Live -AcknowledgeRealChanges } | Should -Throw
        { Enable-CddsiVirtualMachinePlatform -ExecutionContext $context -Mode Live -AcknowledgeRealChanges -AcknowledgeRestart } | Should -Throw
        { Stop-CddsiClaudeDesktop -ExecutionContext $context -Mode Live -AcknowledgeRealChanges } | Should -Throw
        { Invoke-CddsiDeepSeekApiValidation -ExecutionContext $context -Mode Live -AcknowledgeRealChanges } | Should -Throw
    }

    It 'rejects incomplete and legacy v1 evidence before any installation plan' {
        $testSafeContext = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $dryRunContext = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -Mode DryRun -RunId '00000000-0000-0000-0000-000000000103'
        $msixDescriptor = New-CddsiSafetyArtifactDescriptor -ArtifactType ClaudeDesktopMsix
        $gitDescriptor = New-CddsiSafetyArtifactDescriptor -ArtifactType GitForWindowsInstaller
        $testSafeMsixSource = New-CddsiSafetySourceObservation -Descriptor $msixDescriptor -RunId $testSafeContext.RunId
        $dryRunMsixSource = New-CddsiSafetySourceObservation -Descriptor $msixDescriptor -RunId $dryRunContext.RunId
        $testSafeGitSource = New-CddsiSafetySourceObservation -Descriptor $gitDescriptor -RunId $testSafeContext.RunId
        { Install-CddsiClaudeDesktopMsix -ExecutionContext $testSafeContext -PackagePath (Join-Path $TestDrive 'unused.msix') -SignatureEvidence ([pscustomobject]@{ Valid = $false }) -ArtifactDescriptor $msixDescriptor -SourceObservation $testSafeMsixSource -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode TestSafe } | Should -Throw
        { Update-CddsiClaudeDesktopMsix -ExecutionContext $dryRunContext -PackagePath (Join-Path $TestDrive 'unused.msix') -SignatureEvidence ([pscustomobject]@{ Valid = $false }) -ArtifactDescriptor $msixDescriptor -SourceObservation $dryRunMsixSource -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode DryRun } | Should -Throw
        { Install-CddsiGitForWindows -ExecutionContext $testSafeContext -InstallerPath (Join-Path $TestDrive 'unused.exe') -SignatureEvidence ([pscustomobject]@{ Valid = $false }) -ArtifactDescriptor $gitDescriptor -SourceObservation $testSafeGitSource -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode TestSafe } | Should -Throw
        $msixPath = Join-Path $TestDrive 'approved.msix'
        $legacyV1 = [pscustomobject]@{
            SchemaVersion = 1
            ArtifactType = 'ClaudeDesktopMsix'
            PathBindingToken = Get-CddsiPathBindingToken -Path $msixPath
            ArtifactSha256 = ('c' * 64)
            Valid = $true
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            PublisherMatch = $true
            IdentityMatch = $true
            SourcePolicy = 'anthropic_official_only'
        }
        { Install-CddsiClaudeDesktopMsix -ExecutionContext $testSafeContext -PackagePath $msixPath -SignatureEvidence $legacyV1 -ArtifactDescriptor $msixDescriptor -SourceObservation $testSafeMsixSource -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode TestSafe } | Should -Throw
        @($testSafeContext.AccessLedger.Entries).Count | Should -Be 0
        @($dryRunContext.AccessLedger.Entries).Count | Should -Be 0
    }

    It 'runs each root entrypoint in scaffold TestSafe without touching TestDrive' {
        $before = @(Get-ChildItem -LiteralPath $TestDrive -Force -Recurse).Count
        $testSafeContext = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $dryRunContext = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -Mode DryRun -RunId '00000000-0000-0000-0000-000000000104'
        $install = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Install -TestSafe -NonInteractive -PassThru -ExecutionContext $testSafeContext
        $diagnose = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Diagnose -DryRun -NonInteractive -PassThru
        $restore = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Restore -TestSafe -NonInteractive -PassThru -ExecutionContext $testSafeContext
        $repair = & (Join-Path $script:RepoRoot 'Start-Here.ps1') -Action Repair -DryRun -NonInteractive -PassThru -ExecutionContext $dryRunContext
        $install.Status | Should -Be 'ACTION_REQUIRED'
        $diagnose.Status | Should -Be 'ACTION_REQUIRED'
        $restore.Status | Should -Be 'ACTION_REQUIRED'
        $repair.Status | Should -Be 'ACTION_REQUIRED'
        @(Get-ChildItem -LiteralPath $TestDrive -Force -Recurse).Count | Should -Be $before
        Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $testSafeContext) | Should -BeTrue
        Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $dryRunContext) | Should -BeTrue
    }

    It 'keeps repair orchestration plan-only and blocks Live repair' {
        $context = New-CddsiTestExecutionContext
        $result = Invoke-CddsiDesktopRepair -ExecutionContext $context -Mode TestSafe
        $result.Status | Should -Be 'ACTION_REQUIRED'
        @($result.Data).Count | Should -BeGreaterThan 0
        { Invoke-CddsiDesktopRepair -ExecutionContext $context -Mode Live -AcknowledgeRealChanges } | Should -Throw
    }

    It 'keeps the future elevated boundary mandatory and fail-closed' {
        $scriptPath = Join-Path $script:RepoRoot 'scripts\elevated-install.ps1'
        $command = Get-Command -Name $scriptPath -ErrorAction Stop
        @($command.Parameters.Operation.Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -BeGreaterThan 0
        $context = New-CddsiTestExecutionContext
        $safe = & $scriptPath -ExecutionContext $context -Operation ClaudeDesktopMsix -Mode TestSafe -PassThru
        $safe.Status | Should -Be 'ACTION_REQUIRED'
        foreach ($operation in @('ClaudeDesktopMsix', 'GitForWindows', 'VirtualMachinePlatform')) {
            { & $scriptPath -ExecutionContext $context -Operation $operation -Mode Live -AcknowledgeRealChanges -AcknowledgeRestart -PassThru } | Should -Throw
        }
    }

    It 'keeps the Live read-only adapter inside exact safe command and type allow-lists' {
        $boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
        $relative = 'lib/live-adapters.ps1'
        $path = Join-Path $script:RepoRoot $relative
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $ast.ScriptRequirements | Should -BeNullOrEmpty
        @($ast.UsingStatements).Count | Should -Be 0
        $ast.ParamBlock | Should -BeNullOrEmpty
        $ast.DynamicParamBlock | Should -BeNullOrEmpty
        $ast.BeginBlock | Should -BeNullOrEmpty
        $ast.ProcessBlock | Should -BeNullOrEmpty
        $cleanBlockProperty = $ast.PSObject.Properties['CleanBlock']
        if ($null -ne $cleanBlockProperty) {
            $cleanBlockProperty.Value | Should -BeNullOrEmpty
        }
        $functions = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true))
        $functions.Count | Should -Be 2
        $functionDigestPolicySequence = @(
            $boundary.Rules.LiveAdapterFunctionSourceDigestAllowList[$relative] |
                ForEach-Object { [string]$_ }
        )
        $functionDigestPolicySequence.Count | Should -Be 2
        @($functionDigestPolicySequence | Sort-Object -Unique).Count | Should -Be 2
        (Get-CddsiSupplyChainTextBindingToken -Text ($functionDigestPolicySequence -join "`n")) |
            Should -BeExactly '3d565a3d288c564ad0459b346a059c68c5b90df2994552741c4b939370a8cc3c'
        $actualFunctionDigests = @(Get-CddsiSafetyFunctionSourceDigestContracts -Ast $ast)
        ($actualFunctionDigests -join "`n") |
            Should -BeExactly ((@($functionDigestPolicySequence | Sort-Object)) -join "`n")
        $loader = @($functions | Where-Object {
            $_.Name -ceq 'Invoke-CddsiLiveAdapterOperation'
        })[0]
        $providerHandler = @($functions | Where-Object {
            $_.Name -ceq 'Invoke-CddsiLiveReadOnlyProviderOperation'
        })[0]
        foreach ($entryPoint in @($loader, $providerHandler)) {
            $entryPoint.IsFilter | Should -BeFalse
            $entryPoint.IsWorkflow | Should -BeFalse
            $entryPoint.Body.ParamBlock | Should -Not -BeNullOrEmpty
            $entryPoint.Body.DynamicParamBlock | Should -BeNullOrEmpty
            $entryPoint.Body.BeginBlock | Should -BeNullOrEmpty
            $entryPoint.Body.ProcessBlock | Should -BeNullOrEmpty
            $bodyCleanBlockProperty = $entryPoint.Body.PSObject.Properties['CleanBlock']
            if ($null -ne $bodyCleanBlockProperty) {
                $bodyCleanBlockProperty.Value | Should -BeNullOrEmpty
            }
            $entryPoint.Body.EndBlock | Should -Not -BeNullOrEmpty
            @($entryPoint.Body.ParamBlock.Parameters | Where-Object {
                $null -ne $_.DefaultValue
            }).Count | Should -Be 0
            $entryPointStatements = @($entryPoint.Body.EndBlock.Statements)
            $entryPointStatements.Count | Should -BeGreaterThan 0
            $entryPointStatements[0] | Should -BeOfType ([System.Management.Automation.Language.PipelineAst])
            $entryPointStatements[0].Extent.Text | Should -BeExactly (
                'Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null'
            )
        }

        $text = [System.IO.File]::ReadAllText($path)
        foreach ($pattern in @($boundary.Rules.LiveAdapterForbiddenTextPatterns)) {
            $text | Should -Not -Match $pattern
        }
        $variables = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.VariablePath.UserPath } | Sort-Object -Unique)
        @($variables | Where-Object {
            $_.IndexOf(':', [StringComparison]::Ordinal) -ge 0 -or
                @($boundary.Rules.LiveAdapterForbiddenVariableNames) -ccontains $_ -or
                $_.StartsWith('env:', [StringComparison]::OrdinalIgnoreCase)
        }).Count | Should -Be 0

        $commands = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true))
        @($commands | Where-Object {
            [string]::IsNullOrWhiteSpace($_.GetCommandName()) -or
                $_.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown
        }).Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node.GetType().Name -in @(
                'TrapStatementAst',
                'ExitStatementAst',
                'DataStatementAst',
                'TypeDefinitionAst'
            )
        }, $true)).Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.UnaryExpressionAst] -and
                $node.TokenKind.ToString() -in @(
                    'PlusPlus',
                    'PostfixPlusPlus',
                    'MinusMinus',
                    'PostfixMinusMinus'
                )
        }, $true)).Count | Should -Be 0
        $pipelines = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.PipelineAst]
        }, $true))
        @($pipelines | Where-Object {
            $backgroundProperty = $_.PSObject.Properties['Background']
            if ($null -ne $backgroundProperty) {
                return [bool]$backgroundProperty.Value
            }
            return $_.Extent.Text -match '(?s)&\s*$'
        }).Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node.GetType().Name -ceq 'PipelineChainAst'
        }, $true)).Count | Should -Be 0
        $directPipelinePolicySequence = @(
            $boundary.Rules.LiveAdapterDirectPipelineAllowList[$relative] |
                ForEach-Object { [string]$_ }
        )
        $directPipelinePolicySequence.Count | Should -Be 36
        @($directPipelinePolicySequence | Sort-Object -Unique).Count | Should -Be 36
        (Get-CddsiSupplyChainTextBindingToken -Text ($directPipelinePolicySequence -join "`n")) |
            Should -BeExactly '09689c00a12074a7a4332e6bae331fe1ba9252fa7ea74e073dd56777955a15b6'
        $configuredDirectPipelineContracts = @($directPipelinePolicySequence | Sort-Object)
        $actualDirectPipelineContracts = @(Get-CddsiSafetyDirectPipelineContracts -Ast $ast)
        ($actualDirectPipelineContracts -join "`n") |
            Should -BeExactly ($configuredDirectPipelineContracts -join "`n")
        @($actualDirectPipelineContracts | Where-Object {
            $_ -cmatch '\|<UNBOUND>\|'
        }).Count | Should -Be 0
        @($actualDirectPipelineContracts | Where-Object {
            $_ -cmatch '\|\$providerCapabilities\|'
        }).Count | Should -Be 11
        @($actualDirectPipelineContracts | Where-Object {
            $_ -cmatch '\|\$ledgerOperation\|'
        }).Count | Should -Be 2
        @($actualDirectPipelineContracts | Where-Object {
            $_ -cmatch '\|\$allCapabilities\|'
        }).Count | Should -Be 10
        @($actualDirectPipelineContracts | Where-Object {
            $_ -cmatch '\|\$resourceMatches\|'
        }).Count | Should -Be 2
        @($actualDirectPipelineContracts | Where-Object {
            $_ -cmatch '\|\$capabilityMatches\|'
        }).Count | Should -Be 3
        $expectedSafeCommands = @(
            'Add-CddsiProductAccessLedgerEntry'
            'Assert-CddsiExecutionContext'
            'New-CddsiLiveReadOnlyProviderSet'
            'New-CddsiOperationResult'
            'Out-Null'
            'Test-CddsiCommittedOperationUseReceipt'
            'Where-Object'
        )
        $configuredSafeCommands = @($boundary.Rules.LiveAdapterCommandAllowList[$relative] | Sort-Object)
        ($configuredSafeCommands -join "`n") | Should -BeExactly (@($expectedSafeCommands | Sort-Object) -join "`n")
        $actualCommands = @($commands | ForEach-Object { $_.GetCommandName() } | Sort-Object -Unique)
        ($actualCommands -join "`n") | Should -BeExactly ($configuredSafeCommands -join "`n")
        @($commands | Where-Object {
            $name = $_.GetCommandName()
            $name -and @($boundary.Rules.LiveAdapterSystemCapabilityCommands) -ccontains $name
        }).Count | Should -Be 0
        $types = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.TypeExpressionAst] -or
                $node -is [System.Management.Automation.Language.TypeConstraintAst]
        }, $true) | ForEach-Object { $_.TypeName.FullName })
        $attributeTypes = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AttributeAst]
        }, $true) | ForEach-Object { $_.TypeName.FullName })
        $expectedSafeTypes = @(
            'Alias'
            'CmdletBinding'
            'long'
            'ordered'
            'Parameter'
            'pscustomobject'
            'string'
            'System.Collections.IDictionary'
        )
        $configuredSafeTypes = @($boundary.Rules.LiveAdapterTypePrefixAllowList[$relative] | Sort-Object)
        ($configuredSafeTypes -join "`n") | Should -BeExactly (@($expectedSafeTypes | Sort-Object) -join "`n")
        $actualTypes = @(($types + $attributeTypes) | Sort-Object -Unique)
        ($actualTypes -join "`n") | Should -BeExactly ($configuredSafeTypes -join "`n")
        @($types | Where-Object {
            $candidate = $_
            @($boundary.Rules.LiveAdapterSystemCapabilityTypePrefixes | Where-Object {
                $candidate.StartsWith([string]$_, [StringComparison]::OrdinalIgnoreCase)
            }).Count -gt 0
        }).Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst]
        }, $true)).Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.RedirectionAst]
        }, $true)).Count | Should -Be 0
        $memberAssignments = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -is [System.Management.Automation.Language.MemberExpressionAst]
        }, $true))
        $memberAssignmentContracts = @($memberAssignments | ForEach-Object {
            '{0}|{1}|{2}' -f
                $_.Operator.ToString(),
                $_.Left.Extent.Text,
                $_.Right.Extent.Text
        } | Sort-Object)
        $expectedMemberAssignmentContracts = @(
            'Equals|$Context.Providers|$loadedProviderSet'
            'Equals|$Context.AccessLedger.LiveProviderLoaded|$true'
            'Equals|$Context.Providers|$previousProviderSet'
            'Equals|$Context.AccessLedger.LiveProviderLoaded|$previousLiveProviderLoaded'
            'Equals|$Context.AccessLedger.ForbiddenResourceAccessCount|[long]$Context.AccessLedger.ForbiddenResourceAccessCount + 1L'
            'Equals|$Context.AccessLedger.UnexpectedEntryCount|[long]$Context.AccessLedger.UnexpectedEntryCount + 1L'
        ) | Sort-Object
        ($memberAssignmentContracts -join "`n") |
            Should -BeExactly ($expectedMemberAssignmentContracts -join "`n")
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left -isnot [System.Management.Automation.Language.MemberExpressionAst]
        }, $true)).Count | Should -Be 0

        $tryStatements = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.TryStatementAst]
        }, $true))
        $tryStatements.Count | Should -Be 1
        $rollbackTry = $tryStatements[0]
        $rollbackTry.Finally | Should -BeNullOrEmpty
        $rollbackTryStatements = @($rollbackTry.Body.Statements)
        $rollbackTryStatements.Count | Should -Be 3
        $rollbackTryStatements[0] |
            Should -BeOfType ([System.Management.Automation.Language.AssignmentStatementAst])
        $rollbackTryStatements[0].Extent.Text |
            Should -BeExactly '$Context.Providers = $loadedProviderSet'
        $rollbackTryStatements[1] |
            Should -BeOfType ([System.Management.Automation.Language.AssignmentStatementAst])
        $rollbackTryStatements[1].Extent.Text |
            Should -BeExactly '$Context.AccessLedger.LiveProviderLoaded = $true'
        $rollbackTryStatements[2] |
            Should -BeOfType ([System.Management.Automation.Language.PipelineAst])
        $rollbackTryStatements[2].Extent.Text | Should -BeExactly (
            'Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode Live | Out-Null'
        )
        $preInstallCaptures = @($loader.FindAll({
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
        $catchStatements = @($rollbackTry.CatchClauses[0].Body.Statements)
        $catchStatements.Count | Should -Be 3
        $catchStatements[0].Extent.Text | Should -BeExactly '$Context.Providers = $previousProviderSet'
        $catchStatements[1].Extent.Text |
            Should -BeExactly '$Context.AccessLedger.LiveProviderLoaded = $previousLiveProviderLoaded'
        $catchStatements[2] | Should -BeOfType ([System.Management.Automation.Language.ThrowStatementAst])
        $catchStatements[2].Pipeline | Should -BeNullOrEmpty

        $allReturns = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ReturnStatementAst]
        }, $true))
        $allReturns.Count | Should -Be 1
        @($providerHandler.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.ReturnStatementAst]
        }, $true)).Count | Should -Be 0
        $loaderStatements = @($loader.Body.EndBlock.Statements)
        $loaderStatements[-1].Extent.StartOffset | Should -Be $allReturns[0].Extent.StartOffset
        $allReturns[0].Parent.Extent.StartOffset | Should -Be $loader.Body.EndBlock.Extent.StartOffset
        @($allReturns[0].Pipeline.PipelineElements).Count | Should -Be 1
        $allReturns[0].Pipeline.PipelineElements[0] |
            Should -BeOfType ([System.Management.Automation.Language.CommandAst])
        $allReturns[0].Pipeline.PipelineElements[0].GetCommandName() |
            Should -BeExactly 'New-CddsiOperationResult'
        @($boundary.Rules.LiveAdapterSystemCapabilitySites[$relative]).Count | Should -Be 0
    }

    It 'rejects a bare implicit-output expression inserted before the unique Live loader success result' {
        $boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
        $relative = 'lib/live-adapters.ps1'
        $source = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $relative))
        $successAnchor = "    return New-CddsiOperationResult -Operation 'LoadLiveProviders'"
        $mutantSource = $source.Replace(
            $successAnchor,
            "    'UNBOUND_OUTPUT_SENTINEL'`r`n$successAnchor"
        )
        $mutantSource | Should -Not -BeExactly $source
        $mutantTokens = $null
        $mutantErrors = $null
        $mutantAst = [System.Management.Automation.Language.Parser]::ParseInput(
            $mutantSource,
            [ref]$mutantTokens,
            [ref]$mutantErrors
        )
        @($mutantErrors).Count | Should -Be 0

        $configuredContracts = @(
            $boundary.Rules.LiveAdapterDirectPipelineAllowList[$relative] |
                ForEach-Object { [string]$_ } |
                Sort-Object
        )
        $mutantContracts = @(Get-CddsiSafetyDirectPipelineContracts -Ast $mutantAst)
        $mutantContracts.Count | Should -Be ($configuredContracts.Count + 1)
        @($mutantContracts | Where-Object {
            $_ -cmatch '^Invoke-CddsiLiveAdapterOperation\|NamedBlockAst\|<UNBOUND>\|[a-f0-9]{64}$'
        }).Count | Should -Be 1
        ($mutantContracts -join "`n") |
            Should -Not -BeExactly ($configuredContracts -join "`n")
    }

    It 'rejects unreachable wrappers around committed receipt and binding failure gates' {
        $boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
        $relative = 'lib/live-adapters.ps1'
        $source = [System.IO.File]::ReadAllText((Join-Path $script:RepoRoot $relative))
        $configuredPipelines = @(
            $boundary.Rules.LiveAdapterDirectPipelineAllowList[$relative] |
                ForEach-Object { [string]$_ } |
                Sort-Object
        )
        $configuredFunctionDigests = @(
            $boundary.Rules.LiveAdapterFunctionSourceDigestAllowList[$relative] |
                ForEach-Object { [string]$_ } |
                Sort-Object
        )

        foreach ($mutation in @(
            @{
                Name = 'binding-failure'
                StartAnchor = '    if ($bindingMatches.Count -ne 1) {'
            },
            @{
                Name = 'committed-receipt'
                StartAnchor = '    if (-not (Test-CddsiCommittedOperationUseReceipt `'
            }
        )) {
            $mutantSource = Add-CddsiSafetyFalseWrapper -Source $source `
                -StartAnchor $mutation.StartAnchor
            $mutantSource | Should -Not -BeExactly $source -Because $mutation.Name
            $mutantTokens = $null
            $mutantErrors = $null
            $mutantAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $mutantSource,
                [ref]$mutantTokens,
                [ref]$mutantErrors
            )
            @($mutantErrors).Count | Should -Be 0 -Because $mutation.Name

            # The previous direct-pipeline contract alone cannot see an If
            # condition or prove that the unchanged critical branch is
            # reachable.  The complete normalized function digest must.
            $mutantPipelines = @(Get-CddsiSafetyDirectPipelineContracts -Ast $mutantAst)
            ($mutantPipelines -join "`n") |
                Should -BeExactly ($configuredPipelines -join "`n") -Because $mutation.Name
            $mutantFunctionDigests = @(
                Get-CddsiSafetyFunctionSourceDigestContracts -Ast $mutantAst
            )
            ($mutantFunctionDigests -join "`n") |
                Should -Not -BeExactly ($configuredFunctionDigests -join "`n") -Because $mutation.Name
        }
    }

    It 'rejects filesystem registry process network remoting COM and alias bypass syntax' {
        $boundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
        $relative = 'lib/live-adapters.ps1'
        $safeCommands = @($boundary.Rules.LiveAdapterCommandAllowList[$relative])
        $safeTypes = @($boundary.Rules.LiveAdapterTypePrefixAllowList[$relative])
        $commandBypasses = @(
            'Get-Acl -LiteralPath C:\synthetic'
            'Get-ItemPropertyValue -LiteralPath HKCU:\Synthetic -Name Value'
            'Resolve-DnsName synthetic.invalid'
            'Test-NetConnection synthetic.invalid'
            'Start-Job { 1 }'
            'Invoke-Command -ScriptBlock { 1 }'
            'New-Object -ComObject WScript.Shell'
            'gci C:\synthetic'
            'gc C:\synthetic\value.txt'
            'dir C:\synthetic'
            'Microsoft.PowerShell.Management\Get-ChildItem C:\synthetic'
        )
        foreach ($source in $commandBypasses) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $candidateCommands = @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst]
            }, $true))
            @($candidateCommands).Count | Should -BeGreaterThan 0
            @($candidateCommands | Where-Object {
                $name = $_.GetCommandName()
                [string]::IsNullOrWhiteSpace($name) -or $safeCommands -cnotcontains $name
            }).Count | Should -BeGreaterThan 0
        }

        $typeBypasses = @(
            '[System.IO.File]::ReadAllText(''C:\synthetic\value.txt'')'
            '[Microsoft.Win32.Registry]::CurrentUser'
            '[System.Diagnostics.Process]::Start(''synthetic.exe'')'
            '[System.Net.WebClient]::new()'
        )
        foreach ($source in $typeBypasses) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $candidateTypes = @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.TypeExpressionAst] -or
                    $node -is [System.Management.Automation.Language.TypeConstraintAst]
            }, $true) | ForEach-Object { $_.TypeName.FullName })
            @($candidateTypes | Where-Object { $safeTypes -cnotcontains $_ }).Count |
                Should -BeGreaterThan 0
        }

        foreach ($source in @(
            'Where-Object { $true } > C:\synthetic\out.txt'
            '$true 2> C:\synthetic\error.txt'
        )) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.RedirectionAst]
            }, $true)).Count | Should -BeGreaterThan 0
        }

        foreach ($source in @(
            "#requires -Modules Microsoft.PowerShell.Management`nfunction Invoke-Synthetic { }"
            "#requires -RunAsAdministrator`nfunction Invoke-Synthetic { }"
        )) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $candidateAst.ScriptRequirements | Should -Not -BeNullOrEmpty
        }

        $tokens = $null
        $errors = $null
        $usingAst = [System.Management.Automation.Language.Parser]::ParseInput(
            "using module Microsoft.PowerShell.Management`nfunction Invoke-Synthetic { }",
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        @($usingAst.UsingStatements).Count | Should -BeGreaterThan 0

        foreach ($source in @(
            '${alias:Where-Object} = ''Get-ChildItem'''
            '${function:Assert-CddsiExecutionContext} = { $true }'
            '$global:LiveAdapterBypass = $true'
        )) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $candidateVariables = @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.VariableExpressionAst]
            }, $true) | ForEach-Object { $_.VariablePath.UserPath })
            @($candidateVariables | Where-Object {
                $_.IndexOf(':', [StringComparison]::Ordinal) -ge 0
            }).Count | Should -BeGreaterThan 0
        }

        $controlFlowBypasses = @(
            @{ Source = 'trap { continue }'; TypeName = 'TrapStatementAst' }
            @{ Source = 'exit 1'; TypeName = 'ExitStatementAst' }
            @{ Source = 'data Synthetic { ConvertFrom-StringData ''a=b'' }'; TypeName = 'DataStatementAst' }
            @{ Source = 'class Synthetic { }'; TypeName = 'TypeDefinitionAst' }
            @{ Source = 'function Invoke-Synthetic { return 1 }'; TypeName = 'ReturnStatementAst' }
        )
        foreach ($candidate in $controlFlowBypasses) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                [string]$candidate.Source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            @($candidateAst.FindAll({
                param($node)
                $node.GetType().Name -ceq [string]$candidate.TypeName
            }, $true)).Count | Should -BeGreaterThan 0
        }

        foreach ($source in @('$value++', '++$value', '$value--', '--$value')) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.UnaryExpressionAst] -and
                    $node.TokenKind.ToString() -in @(
                        'PlusPlus',
                        'PostfixPlusPlus',
                        'MinusMinus',
                        'PostfixMinusMinus'
                    )
            }, $true)).Count | Should -BeGreaterThan 0
        }

        $tokens = $null
        $errors = $null
        $backgroundAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'Where-Object { $true } &',
            [ref]$tokens,
            [ref]$errors
        )
        $backgroundPipelines = @($backgroundAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.PipelineAst]
        }, $true) | Where-Object {
            $backgroundProperty = $_.PSObject.Properties['Background']
            if ($null -ne $backgroundProperty) {
                return [bool]$backgroundProperty.Value
            }
            return $_.Extent.Text -match '(?s)&\s*$'
        })
        (@($errors).Count + $backgroundPipelines.Count) | Should -BeGreaterThan 0

        $tokens = $null
        $errors = $null
        $chainAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'Where-Object { $true } && Where-Object { $true }',
            [ref]$tokens,
            [ref]$errors
        )
        $pipelineChains = @($chainAst.FindAll({
            param($node)
            $node.GetType().Name -ceq 'PipelineChainAst'
        }, $true))
        if (@($errors).Count -eq 0) {
            $pipelineChains.Count | Should -BeGreaterThan 0
        }
        else {
            @($errors).Count | Should -BeGreaterThan 0
        }

        foreach ($source in @(
            '& Where-Object { $true }'
            '. Where-Object { $true }'
        )) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.InvocationOperator -ne [System.Management.Automation.Language.TokenKind]::Unknown
            }, $true)).Count | Should -BeGreaterThan 0
        }

        foreach ($source in @(
            '$Context.Stage = ''UserLive'''
            '$StageManifest.Stage = ''UserLive'''
            '$OperationGrant.RunId = ''00000000-0000-0000-0000-000000000000'''
            '$Host.PrivateData = $null'
            '$Context.Providers += $loadedProviderSet'
        )) {
            $tokens = $null
            $errors = $null
            $candidateAst = [System.Management.Automation.Language.Parser]::ParseInput(
                $source,
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $candidateAssignments = @($candidateAst.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left -is [System.Management.Automation.Language.MemberExpressionAst]
            }, $true))
            $candidateAssignments.Count | Should -BeGreaterThan 0
            @($candidateAssignments | Where-Object {
                $_.Operator.ToString() -cne 'Equals' -or
                    $_.Left.Extent.Text -notin @(
                        '$Context.Providers',
                        '$Context.AccessLedger.LiveProviderLoaded',
                        '$Context.AccessLedger.ForbiddenResourceAccessCount',
                        '$Context.AccessLedger.UnexpectedEntryCount'
                )
            }).Count | Should -BeGreaterThan 0
        }

        $tokens = $null
        $errors = $null
        $indexedAssignmentAst = [System.Management.Automation.Language.Parser]::ParseInput(
            '$Context[''Providers''] = $loadedProviderSet',
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        @($indexedAssignmentAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left -isnot [System.Management.Automation.Language.VariableExpressionAst] -and
                $node.Left -isnot [System.Management.Automation.Language.MemberExpressionAst]
        }, $true)).Count | Should -BeGreaterThan 0

        $tokens = $null
        $errors = $null
        $filterAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'filter Invoke-Synthetic { $_ }',
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $filterFunction = $filterAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
        $filterFunction.IsFilter | Should -BeTrue

        $tokens = $null
        $errors = $null
        $workflowAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'workflow Invoke-Synthetic { 1 }',
            [ref]$tokens,
            [ref]$errors
        )
        $workflowFunction = $workflowAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
        $workflowFunction.IsWorkflow | Should -BeTrue

        $tokens = $null
        $errors = $null
        $defaultAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Invoke-Synthetic { param($Value = 1) $Value }',
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $defaultFunction = $defaultAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
        @($defaultFunction.Body.ParamBlock.Parameters | Where-Object {
            $null -ne $_.DefaultValue
        }).Count | Should -BeGreaterThan 0

        $tokens = $null
        $errors = $null
        $auxAst = [System.Management.Automation.Language.Parser]::ParseInput(
            'function Invoke-Synthetic { begin { 1 } process { 2 } end { 3 } }',
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $auxFunction = $auxAst.Find({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
        }, $true)
        $auxFunction.Body.BeginBlock | Should -Not -BeNullOrEmpty
        $auxFunction.Body.ProcessBlock | Should -Not -BeNullOrEmpty
    }
}
