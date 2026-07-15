BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')
    $fixturePath = Join-Path $script:RepoRoot 'tests\Fixtures\anthropic-msix-release-synthetic-v1.json'
    $script:MsixFixture = [System.IO.File]::ReadAllText($fixturePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

    function New-CddsiMsixExpectedCall {
        param([string]$Provider, [string]$ResourceToken, [System.Collections.IDictionary]$Arguments, $Result)
        return [pscustomobject][ordered]@{ Provider = $Provider; Operation = 'Inspect'; ResourceToken = $ResourceToken; Arguments = $Arguments; Result = $Result }
    }

    function New-CddsiMsixSignatureObservation {
        param($Descriptor, [string]$PublisherToken = '')
        if ([string]::IsNullOrEmpty($PublisherToken)) { $PublisherToken = $Descriptor.ExpectedPublisherToken }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            SignerThumbprint = $Descriptor.ExpectedSignerThumbprint
            SignerSubjectToken = $Descriptor.ExpectedSignerSubjectToken
            PublisherToken = $PublisherToken
            IdentityToken = $Descriptor.ExpectedIdentityToken
            Architecture = $Descriptor.Architecture
            ArtifactVersion = $Descriptor.ReleaseVersion
            ObservationId = 'synthetic-msix-observation'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
    }

    function New-CddsiMsixSourceObservation {
        param($Descriptor, [string]$RunId, [string]$ArtifactProfile = 'VmAcceptance')
        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-source-observation-v1'; RunId = $RunId
            ArtifactProfile = $ArtifactProfile
            DescriptorId = $Descriptor.DescriptorId; MetadataBindingToken = $Descriptor.MetadataBindingToken
            RequestUri = $Descriptor.SourceUri; FinalUri = $Descriptor.SourceUri; RedirectUris = @()
            RedirectChainBindingToken = Get-CddsiSupplyChainTextBindingToken -Text $Descriptor.SourceUri
            RedirectCount = 0; ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes; ObservationId = 'synthetic-msix-source'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
        $result = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) { $result[$property.Name] = $property.Value }
        $result['SourceObservationBindingToken'] = Get-CddsiSourceObservationBindingToken -Observation $withoutBinding
        return [pscustomobject]$result
    }
}

Describe 'P4 Anthropic MSIX supply-chain contract' {
    It 'parses exactly one immutable x64 or arm64 Standard or Offline descriptor' {
        foreach ($architecture in @('x64', 'arm64')) {
            foreach ($channel in @('Standard', 'Offline')) {
                $descriptor = ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $script:MsixFixture -Architecture $architecture -Channel $channel
                $descriptor.ArtifactType | Should -BeExactly 'ClaudeDesktopMsix'
                $descriptor.Architecture | Should -BeExactly $architecture
                $descriptor.Channel | Should -BeExactly $channel
                $descriptor.MetadataStatus | Should -BeExactly 'READY'
                (Test-CddsiArtifactDescriptor -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -RequireResolved) | Should -BeTrue
            }
        }
    }

    It 'rejects non-official hosts duplicate assets and incomplete exact schemas' {
        $document = $script:MsixFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.Assets[0].DownloadUri = 'https://example.invalid/Claude.msix'
        { ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $document -Architecture x64 -Channel Standard } | Should -Throw

        $document = $script:MsixFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.Assets += $document.Assets[0]
        { ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $document -Architecture x64 -Channel Standard } | Should -Throw

        $document = $script:MsixFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        Add-Member -InputObject $document.Assets[0] -NotePropertyName Bypass -NotePropertyValue $true
        { ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $document -Architecture x64 -Channel Standard } | Should -Throw
    }

    It 'resolves metadata only through one declared fake Network observation' {
        $call = New-CddsiMsixExpectedCall -Provider Network -ResourceToken '<NETWORK:ANTHROPIC_MSIX_METADATA>' -Arguments ([ordered]@{ Architecture = 'x64'; Channel = 'Standard' }) -Result $script:MsixFixture
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiOfficialMsixMetadata -ExecutionContext $context -Architecture x64 -Channel Standard
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.MetadataStatus | Should -BeExactly 'READY'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        $context.AccessLedger.ProductNetworkRequestCount | Should -Be 0
    }

    It 'returns a cache-bound plan without network or filesystem mutation' {
        $descriptor = ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $script:MsixFixture -Architecture x64 -Channel Standard
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $result = Save-CddsiOfficialClaudeDesktopMsix -ExecutionContext $context -DestinationPath (Join-Path $TestDrive 'Claude.msix') -ArtifactDescriptor $descriptor -Mode TestSafe
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.Changed | Should -BeFalse
        $result.Data.CacheKey | Should -BeExactly $descriptor.MetadataBindingToken
        $result.Data.WriteImplemented | Should -BeFalse
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'creates v2 evidence before a plan and rehashes at execution time' {
        foreach ($modeCase in @(
            [pscustomobject]@{ Mode = 'TestSafe'; RunId = '20000000-0000-4000-8000-000000000411' },
            [pscustomobject]@{ Mode = 'DryRun'; RunId = '20000000-0000-4000-8000-000000000412' }
        )) {
            $descriptor = ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $script:MsixFixture -Architecture x64 -Channel Standard
            $path = Join-Path $TestDrive ('Claude-{0}.msix' -f $modeCase.Mode)
            $pathToken = Get-CddsiPathBindingToken -Path $path
            $fileObservation = [pscustomobject]@{ SchemaVersion = 1; FileIdentityToken = ('f' * 64); ArtifactSha256 = $descriptor.ExpectedArtifactSha256; ArtifactSizeBytes = $descriptor.ExpectedArtifactSizeBytes }
            $sourceObservation = New-CddsiMsixSourceObservation -Descriptor $descriptor -RunId $modeCase.RunId
            $calls = @(
                (New-CddsiMsixExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'SignatureVerification' }) -Result $fileObservation),
                (New-CddsiMsixExpectedCall -Provider Package -ResourceToken '<SIGNATURE:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; ArtifactSha256 = $descriptor.ExpectedArtifactSha256 }) -Result (New-CddsiMsixSignatureObservation -Descriptor $descriptor)),
                (New-CddsiMsixExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'ExecutionTimeHashReverification' }) -Result $fileObservation)
            )
            $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -Mode $modeCase.Mode -RunId $modeCase.RunId -ExpectedCalls $calls
            $verification = Test-CddsiClaudeDesktopMsixSignature -ExecutionContext $context -PackagePath $path -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z'
            $verification.Status | Should -BeExactly 'SUCCEEDED'
            $verification.Data.SchemaVersion | Should -Be 2
            (Test-CddsiSignatureEvidence -Evidence $verification -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $context.RunId -ExpectedProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z') | Should -BeTrue
            $plan = Install-CddsiClaudeDesktopMsix -ExecutionContext $context -PackagePath $path -SignatureEvidence $verification -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode $modeCase.Mode
            $plan.Changed | Should -BeFalse
            $plan.Data.ExecutionHashReverified | Should -BeTrue
            @($context.AccessLedger.Entries | ForEach-Object { '{0}:{1}' -f $_.Provider, $_.ResourceToken }) -join '|' | Should -BeExactly 'FileSystem:<ARTIFACT:CLAUDE_DESKTOP_MSIX>|Package:<SIGNATURE:CLAUDE_DESKTOP_MSIX>|FileSystem:<ARTIFACT:CLAUDE_DESKTOP_MSIX>'
            Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
            Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $context) | Should -BeTrue
        }
    }

    It 'rejects a same-path swap during execution-time hash reverification' {
        $descriptor = ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $script:MsixFixture -Architecture x64 -Channel Standard
        $path = Join-Path $TestDrive 'Claude.msix'
        $pathToken = Get-CddsiPathBindingToken -Path $path
        $fileObservation = [pscustomobject]@{ SchemaVersion = 1; FileIdentityToken = ('f' * 64); ArtifactSha256 = $descriptor.ExpectedArtifactSha256; ArtifactSizeBytes = $descriptor.ExpectedArtifactSizeBytes }
        $swappedObservation = [pscustomobject]@{ SchemaVersion = 1; FileIdentityToken = ('e' * 64); ArtifactSha256 = ('9' * 64); ArtifactSizeBytes = $descriptor.ExpectedArtifactSizeBytes }
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -RunId '20000000-0000-4000-8000-000000000413'
        $sourceObservation = New-CddsiMsixSourceObservation -Descriptor $descriptor -RunId $context.RunId
        $calls = @(
            (New-CddsiMsixExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'SignatureVerification' }) -Result $fileObservation),
            (New-CddsiMsixExpectedCall -Provider Package -ResourceToken '<SIGNATURE:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; ArtifactSha256 = $descriptor.ExpectedArtifactSha256 }) -Result (New-CddsiMsixSignatureObservation -Descriptor $descriptor)),
            (New-CddsiMsixExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'ExecutionTimeHashReverification' }) -Result $swappedObservation)
        )
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -RunId $context.RunId -ExpectedCalls $calls
        $verification = Test-CddsiClaudeDesktopMsixSignature -ExecutionContext $context -PackagePath $path -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z'
        { Install-CddsiClaudeDesktopMsix -ExecutionContext $context -PackagePath $path -SignatureEvidence $verification -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode TestSafe } | Should -Throw
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'exposes no signature or installation bypass parameters' {
        foreach ($name in @('Test-CddsiClaudeDesktopMsixSignature', 'Install-CddsiClaudeDesktopMsix', 'Update-CddsiClaudeDesktopMsix')) {
            $parameters = (Get-Command $name).Parameters.Keys
            foreach ($forbidden in @('SkipSignatureCheck', 'IgnoreSignature', 'Bypass', 'NoVerify')) { $parameters | Should -Not -Contain $forbidden }
        }
    }
}
