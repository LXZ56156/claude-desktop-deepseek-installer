function Test-CddsiContractParameterMandatory {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.ParameterAst]$ParameterAst
    )

    foreach ($attribute in @($ParameterAst.Attributes)) {
        if ($attribute.TypeName.FullName -cne 'Parameter') {
            continue
        }
        foreach ($namedArgument in @($attribute.NamedArguments)) {
            if ($namedArgument.ArgumentName -ine 'Mandatory') {
                continue
            }
            if ($null -eq $namedArgument.Argument -or $namedArgument.Argument.Extent.Text -ieq '$true') {
                return $true
            }
        }
    }
    return $false
}

function Get-CddsiContractParameterAst {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,

        [Parameter(Mandatory = $true)]
        [string]$Name
    )

    $matches = @(
        $FunctionAst.Body.ParamBlock.Parameters |
            Where-Object { $_.Name.VariablePath.UserPath -ceq $Name }
    )
    if ($matches.Count -eq 0) { return $null }
    return $matches[0]
}

function ConvertTo-CddsiContractSetText {
    [CmdletBinding()]
    param(
        [AllowNull()]
        [object[]]$Value
    )

    return (@($Value | ForEach-Object { [string]$_ } | Sort-Object) -join "`n")
}

BeforeAll {
    function Test-CddsiContractParameterMandatory {
        param([Parameter(Mandatory = $true)][System.Management.Automation.Language.ParameterAst]$ParameterAst)

        foreach ($attribute in @($ParameterAst.Attributes)) {
            if ($attribute.TypeName.FullName -cne 'Parameter') { continue }
            foreach ($namedArgument in @($attribute.NamedArguments)) {
                if ($namedArgument.ArgumentName -ine 'Mandatory') { continue }
                if ($null -eq $namedArgument.Argument -or $namedArgument.Argument.Extent.Text -ieq '$true') { return $true }
            }
        }
        return $false
    }

    function Get-CddsiContractParameterAst {
        param(
            [Parameter(Mandatory = $true)][System.Management.Automation.Language.FunctionDefinitionAst]$FunctionAst,
            [Parameter(Mandatory = $true)][string]$Name
        )

        $matches = @($FunctionAst.Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -ceq $Name })
        if ($matches.Count -eq 0) { return $null }
        return $matches[0]
    }

    function ConvertTo-CddsiContractSetText {
        param([AllowNull()][AllowEmptyCollection()][object[]]$Value)
        return (@($Value | ForEach-Object { [string]$_ } | Sort-Object) -join "`n")
    }

    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:PublicContract = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\public-functions.psd1')
    $script:ExecutionBoundary = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\execution-boundaries.psd1')
    $script:FunctionAstByName = @{}
    $script:FunctionFileByName = @{}
    $script:DuplicateFunctionNames = @()
    $script:ParseErrors = @()
    $script:ActualFunctionsByFile = @{}
    $script:ActualLibraryFiles = @(
        Get-ChildItem -LiteralPath (Join-Path $script:RepoRoot 'lib') -Filter '*.ps1' -File |
            Sort-Object Name |
            ForEach-Object { 'lib/' + $_.Name }
    )

    foreach ($relativePath in $script:ActualLibraryFiles) {
        $tokens = $null
        $errors = $null
        $absolutePath = Join-Path $script:RepoRoot ($relativePath -replace '/', '\')
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($absolutePath, [ref]$tokens, [ref]$errors)
        $script:ParseErrors += @($errors)
        $nodes = @(
            $ast.FindAll(
                { param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] },
                $true
            )
        )
        $script:ActualFunctionsByFile[$relativePath] = @($nodes | ForEach-Object Name)
        foreach ($node in $nodes) {
            if ($script:FunctionAstByName.ContainsKey($node.Name)) {
                $script:DuplicateFunctionNames += $node.Name
                continue
            }
            $script:FunctionAstByName[$node.Name] = $node
            $script:FunctionFileByName[$node.Name] = $relativePath
        }
    }
}

Describe 'public function contracts' {
    It 'uses the complete schema version 2 inventory for every library file and function' {
        $script:PublicContract.SchemaVersion | Should -Be 2
        (ConvertTo-CddsiContractSetText -Value @($script:PublicContract.Keys)) |
            Should -BeExactly (ConvertTo-CddsiContractSetText -Value @('SchemaVersion', 'Files', 'ParameterContracts'))
        (ConvertTo-CddsiContractSetText -Value @($script:PublicContract.Files.Keys)) |
            Should -BeExactly (ConvertTo-CddsiContractSetText -Value $script:ActualLibraryFiles)
        @($script:ParseErrors).Count | Should -Be 0
        @($script:DuplicateFunctionNames).Count | Should -Be 0

        foreach ($relativePath in $script:ActualLibraryFiles) {
            $script:PublicContract.Files.ContainsKey($relativePath) | Should -BeTrue
            (ConvertTo-CddsiContractSetText -Value @($script:PublicContract.Files[$relativePath])) |
                Should -BeExactly (ConvertTo-CddsiContractSetText -Value @($script:ActualFunctionsByFile[$relativePath]))
        }

        $declaredNames = @(
            $script:PublicContract.Files.GetEnumerator() |
                ForEach-Object { @($_.Value) }
        )
        @($declaredNames).Count | Should -Be @($declaredNames | Sort-Object -Unique).Count
        (ConvertTo-CddsiContractSetText -Value @($script:PublicContract.ParameterContracts.Keys)) |
            Should -BeExactly (ConvertTo-CddsiContractSetText -Value $declaredNames)
    }

    It 'matches every mandatory parameter and records an explicit function kind and Mode contract' {
        foreach ($entry in $script:PublicContract.ParameterContracts.GetEnumerator()) {
            $name = [string]$entry.Key
            $contract = $entry.Value
            $script:FunctionAstByName.ContainsKey($name) | Should -BeTrue
            (ConvertTo-CddsiContractSetText -Value @($contract.Keys)) |
                Should -BeExactly (ConvertTo-CddsiContractSetText -Value @('Kind', 'Mandatory', 'Mode'))
            @('Pure', 'ContextBound', 'ProcessScoped') -ccontains $contract.Kind | Should -BeTrue
            $contract.Mandatory -is [System.Array] | Should -BeTrue
            $contract.Mode -is [bool] | Should -BeTrue

            $functionAst = $script:FunctionAstByName[$name]
            $parameters = @($functionAst.Body.ParamBlock.Parameters)
            $actualMandatory = @(
                $parameters |
                    Where-Object { Test-CddsiContractParameterMandatory -ParameterAst $_ } |
                    ForEach-Object { $_.Name.VariablePath.UserPath }
            )
            (ConvertTo-CddsiContractSetText -Value $actualMandatory) |
                Should -BeExactly (ConvertTo-CddsiContractSetText -Value @($contract.Mandatory))
            @($contract.Mandatory).Count | Should -Be @($contract.Mandatory | Sort-Object -Unique).Count

            $modeAst = Get-CddsiContractParameterAst -FunctionAst $functionAst -Name 'Mode'
            $hasMode = $null -ne $modeAst
            $contract.Mode | Should -Be $hasMode
            if ($hasMode) {
                $validateSetAttributes = @(
                    $modeAst.Attributes |
                        Where-Object { $_.TypeName.FullName -ceq 'ValidateSet' }
                )
                @($validateSetAttributes).Count | Should -Be 1
                $validValues = @(
                    $validateSetAttributes[0].PositionalArguments |
                        ForEach-Object {
                            if ($_ -is [System.Management.Automation.Language.StringConstantExpressionAst]) {
                                $_.Value
                            }
                            else {
                                $_.Extent.Text.Trim("'`"")
                            }
                        }
                )
                (ConvertTo-CddsiContractSetText -Value $validValues) |
                    Should -BeExactly (ConvertTo-CddsiContractSetText -Value @('TestSafe', 'DryRun', 'Live'))
                $defaultText = if ($null -eq $modeAst.DefaultValue) {
                    ''
                }
                else {
                    $modeAst.DefaultValue.Extent.Text.Trim("'`"")
                }
                $defaultText | Should -BeExactly 'TestSafe'
            }

            $executionContextAst = Get-CddsiContractParameterAst -FunctionAst $functionAst -Name 'Context'
            $executionContextMandatory = (
                $null -ne $executionContextAst -and
                (Test-CddsiContractParameterMandatory -ParameterAst $executionContextAst)
            )
            $executionContextAlias = $false
            if ($null -ne $executionContextAst) {
                $aliasAttributes = @(
                    $executionContextAst.Attributes |
                        Where-Object { $_.TypeName.FullName -ceq 'Alias' }
                )
                if ($aliasAttributes.Count -eq 1 -and $aliasAttributes[0].PositionalArguments.Count -eq 1) {
                    $executionContextAlias = $aliasAttributes[0].PositionalArguments[0].Value -ceq 'ExecutionContext'
                }
            }
            if ($contract.Kind -ceq 'ContextBound') {
                $executionContextMandatory | Should -BeTrue
                $executionContextAlias | Should -BeTrue
            }
            if ($contract.Kind -ceq 'ProcessScoped') {
                @(
                    'Initialize-CddsiConsoleEncoding',
                    'Test-CddsiD027Windows11X64Platform',
                    'Test-CddsiCurrentProcessElevated',
                    'Initialize-CddsiD027GitProbeRunnerType'
                ) | Should -Contain $name
                $executionContextMandatory | Should -BeFalse
            }
            if ($executionContextMandatory) {
                $contract.Kind | Should -BeExactly 'ContextBound'
            }
        }
    }

    It 'binds Stage explicitly and keeps provider construction separate from context-bound dispatch' {
        foreach ($name in @(
            'Write-CddsiLog',
            'Invoke-CddsiProviderOperation',
            'Invoke-CddsiFakeProviderOperation',
            'Invoke-CddsiLiveAdapterOperation',
            'Invoke-CddsiLiveReadOnlyProviderOperation'
        )) {
            $contract = $script:PublicContract.ParameterContracts[$name]
            $contract.Kind | Should -BeExactly 'ContextBound'
            @($contract.Mandatory) -ccontains 'Context' | Should -BeTrue
        }
        $contextContract = $script:PublicContract.ParameterContracts['New-CddsiExecutionContext']
        $contextContract.Kind | Should -BeExactly 'Pure'
        @($contextContract.Mandatory) | Should -Contain 'Stage'
        @($contextContract.Mandatory | Where-Object { $_ -ceq 'Stage' }).Count | Should -Be 1

        $unloadedContract = $script:PublicContract.ParameterContracts['New-CddsiUnloadedProviderSet']
        $unloadedContract.Kind | Should -BeExactly 'Pure'
        @($unloadedContract.Mandatory).Count | Should -Be 0
        $unloadedContract.Mode | Should -BeFalse
        @($script:PublicContract.Files['lib/execution-context.ps1'] | Where-Object {
            $_ -ceq 'New-CddsiUnloadedProviderSet'
        }).Count | Should -Be 1

        $liveReadOnlyContract = $script:PublicContract.ParameterContracts['New-CddsiLiveReadOnlyProviderSet']
        $liveReadOnlyContract.Kind | Should -BeExactly 'Pure'
        @($liveReadOnlyContract.Mandatory) -join '|' | Should -BeExactly (
            'RunId|Stage|EnvironmentTier|ArtifactProfile|AdapterSha256|' +
            'LoadOperationUseId|LoadReceiptBindingToken'
        )
        $liveReadOnlyContract.Mode | Should -BeFalse
        @($script:PublicContract.Files['lib/execution-context.ps1'] | Where-Object {
            $_ -ceq 'New-CddsiLiveReadOnlyProviderSet'
        }).Count | Should -Be 1
        $capabilityContract = $script:PublicContract.ParameterContracts[
            'Get-CddsiLiveReadOnlyCapabilityContracts'
        ]
        $capabilityContract.Kind | Should -BeExactly 'Pure'
        @($capabilityContract.Mandatory).Count | Should -Be 0
        $capabilityContract.Mode | Should -BeFalse
        @($script:PublicContract.Files['lib/execution-context.ps1'] | Where-Object {
            $_ -ceq 'Get-CddsiLiveReadOnlyCapabilityContracts'
        }).Count | Should -Be 1

        $tupleContract = $script:PublicContract.ParameterContracts['Test-CddsiLiveReadOnlyCapabilityTuple']
        $tupleContract.Kind | Should -BeExactly 'Pure'
        @($tupleContract.Mandatory) -join '|' |
            Should -BeExactly 'ProviderSet|Provider|Operation|ResourceToken|ArgumentCount'
        $tupleContract.Mode | Should -BeFalse

        $ledgerValueContract = $script:PublicContract.ParameterContracts['Assert-CddsiProductAccessLedgerEntryValues']
        $ledgerValueContract.Kind | Should -BeExactly 'Pure'
        @($ledgerValueContract.Mandatory) -join '|' | Should -BeExactly (
            'ProviderSet|Provider|Operation|ResourceToken|ArgumentCount|Allowed|Expected|' +
            'IsMutation|FailureInjected|Outcome|ErrorCode'
        )
        $ledgerValueContract.Mode | Should -BeFalse

        $scenarioContract = $script:PublicContract.ParameterContracts['Assert-CddsiFakeProviderScenario']
        $scenarioContract.Kind | Should -BeExactly 'Pure'
        @($scenarioContract.Mandatory) | Should -Be @('ProviderSet')
        $scenarioContract.Mode | Should -BeFalse

        $scenarioBindingContract = $script:PublicContract.ParameterContracts['Get-CddsiFakeScenarioBindingToken']
        $scenarioBindingContract.Kind | Should -BeExactly 'Pure'
        @($scenarioBindingContract.Mandatory) |
            Should -Be @('ExpectedCalls', 'FailureInjections')
        $scenarioBindingContract.Mode | Should -BeFalse

        $notePropertyContract = $script:PublicContract.ParameterContracts['Test-CddsiExactNotePropertySet']
        $notePropertyContract.Kind | Should -BeExactly 'Pure'
        @($notePropertyContract.Mandatory) | Should -Be @('InputObject', 'Expected')
        $notePropertyContract.Mode | Should -BeFalse

        $resourceContract = $script:PublicContract.ParameterContracts['Test-CddsiFakeResourceTokenAllowed']
        $resourceContract.Kind | Should -BeExactly 'Pure'
        @($resourceContract.Mandatory) | Should -Be @('Policy')
        $resourceContract.Mode | Should -BeFalse

        foreach ($movedHelper in @(
            'Test-CddsiExactNotePropertySet',
            'Get-CddsiFakeInputFieldNames',
            'Get-CddsiFakeInputFieldValue',
            'Test-CddsiFakeValueEqual',
            'Get-CddsiFakeScenarioBindingToken',
            'Test-CddsiFakeMutationOperation',
            'Test-CddsiFakeResourceTokenAllowed',
            'Assert-CddsiFakeProviderScenario'
        )) {
            @($script:PublicContract.Files['lib/execution-context.ps1'] | Where-Object {
                $_ -ceq $movedHelper
            }).Count | Should -Be 1
            @($script:PublicContract.Files['lib/fake-providers.ps1'] | Where-Object {
                $_ -ceq $movedHelper
            }).Count | Should -Be 0
        }

        $script:PublicContract.ParameterContracts['Initialize-CddsiConsoleEncoding'].Kind |
            Should -BeExactly 'ProcessScoped'
    }

    It 'passes Stage explicitly at every classified execution-context construction call site' {
        $classifiedPowerShellFiles = @(
            $script:ExecutionBoundary.Planes.Keys |
                ForEach-Object { @($script:ExecutionBoundary.Planes[$_]) } |
                Where-Object { $_ -match '\.ps1$' } |
                Sort-Object -Unique
        )
        $callSiteCount = 0
        foreach ($relativePath in $classifiedPowerShellFiles) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile(
                (Join-Path $script:RepoRoot $relativePath),
                [ref]$tokens,
                [ref]$errors
            )
            @($errors).Count | Should -Be 0
            $calls = @($ast.FindAll({
                param($node)
                $node -is [System.Management.Automation.Language.CommandAst] -and
                    $node.GetCommandName() -ceq 'New-CddsiExecutionContext'
            }, $true))
            foreach ($call in $calls) {
                $callSiteCount++
                @($call.CommandElements | Where-Object {
                    $_ -is [System.Management.Automation.Language.CommandParameterAst] -and
                    $_.ParameterName -ceq 'Stage'
                }).Count | Should -Be 1
            }
        }
        $callSiteCount | Should -BeGreaterThan 0
    }
}
