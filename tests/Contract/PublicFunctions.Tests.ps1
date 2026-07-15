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
            @('Pure', 'ContextBound') -ccontains $contract.Kind | Should -BeTrue
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
            if ($executionContextMandatory) {
                $contract.Kind | Should -BeExactly 'ContextBound'
            }
        }
    }

    It 'keeps logging and provider dispatch explicitly context-bound' {
        foreach ($name in @('Write-CddsiLog', 'Invoke-CddsiProviderOperation', 'Invoke-CddsiFakeProviderOperation')) {
            $contract = $script:PublicContract.ParameterContracts[$name]
            $contract.Kind | Should -BeExactly 'ContextBound'
            @($contract.Mandatory) -ccontains 'Context' | Should -BeTrue
        }
    }
}
