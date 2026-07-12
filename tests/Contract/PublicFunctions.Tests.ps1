BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    $script:PublicContract = Import-PowerShellDataFile -LiteralPath (Join-Path $script:RepoRoot 'config\public-functions.psd1')
}

Describe 'public function contracts' {
    It 'loads every required public function without executing a workflow' {
        $required = @($script:PublicContract.Files.GetEnumerator() | ForEach-Object { @($_.Value) })
        foreach ($name in $required) {
            Get-Command -Name $name -CommandType Function -ErrorAction Stop | Should -Not -BeNullOrEmpty
        }
    }

    It 'matches each library file exactly and enforces mandatory and Mode parameters' {
        $functionAstByName = @{}
        foreach ($entry in $script:PublicContract.Files.GetEnumerator()) {
            $tokens = $null
            $errors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot $entry.Key), [ref]$tokens, [ref]$errors)
            @($errors).Count | Should -Be 0
            $nodes = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.FunctionDefinitionAst] }, $true))
            foreach ($node in $nodes) { $functionAstByName[$node.Name] = $node }
            $actual = @($nodes | ForEach-Object Name | Sort-Object)
            @(Compare-Object -ReferenceObject @($entry.Value | Sort-Object) -DifferenceObject $actual).Count | Should -Be 0
        }
        foreach ($entry in $script:PublicContract.ParameterContracts.GetEnumerator()) {
            $command = Get-Command -Name $entry.Key -CommandType Function -ErrorAction Stop
            foreach ($parameterName in @($entry.Value.Mandatory)) {
                $command.Parameters.ContainsKey($parameterName) | Should -BeTrue
                @($command.Parameters[$parameterName].Attributes | Where-Object { $_ -is [System.Management.Automation.ParameterAttribute] -and $_.Mandatory }).Count | Should -BeGreaterThan 0
            }
            if ($entry.Value.ContainsKey('Mode') -and $entry.Value.Mode) {
                $command.Parameters.ContainsKey('Mode') | Should -BeTrue
                $validValues = @($command.Parameters.Mode.Attributes | Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] } | ForEach-Object ValidValues)
                (@($validValues | Sort-Object) -join ',') | Should -Be 'DryRun,Live,TestSafe'
                $modeAst = @($functionAstByName[$entry.Key].Body.ParamBlock.Parameters | Where-Object { $_.Name.VariablePath.UserPath -eq 'Mode' })[0]
                $modeAst.DefaultValue.Extent.Text.Trim("'`"") | Should -BeExactly 'TestSafe'
            }
            foreach ($switchName in @('AcknowledgeRealChanges', 'AcknowledgeRestart')) {
                if ($entry.Value.ContainsKey($switchName) -and $entry.Value[$switchName]) {
                    $command.Parameters.ContainsKey($switchName) | Should -BeTrue
                }
            }
        }
    }
}
