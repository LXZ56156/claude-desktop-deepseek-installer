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
}
