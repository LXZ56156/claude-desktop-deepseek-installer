BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')
    $fixturePath = Join-Path $script:RepoRoot 'tests\Fixtures\git-for-windows-release-api-synthetic-v1.json'
    $script:GitFixture = [System.IO.File]::ReadAllText($fixturePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

    function New-CddsiGitSupplyExpectedCall {
        param([string]$Provider, [string]$ResourceToken, [System.Collections.IDictionary]$Arguments, $Result)
        return [pscustomobject][ordered]@{ Provider = $Provider; Operation = 'Inspect'; ResourceToken = $ResourceToken; Arguments = $Arguments; Result = $Result }
    }

    function Resolve-CddsiSyntheticGitDescriptor {
        param($Descriptor)
        $Descriptor.ExpectedSignerThumbprint = ('2' * 40)
        $Descriptor.ExpectedSignerSubjectToken = '<SIGNER_SUBJECT:GIT_FOR_WINDOWS_SYNTHETIC>'
        $Descriptor.ExpectedPublisherToken = '<PUBLISHER:GIT_FOR_WINDOWS_SYNTHETIC>'
        $Descriptor.ExpectedIdentityToken = '<IDENTITY:GIT_FOR_WINDOWS_INSTALLER_SYNTHETIC>'
        $Descriptor.MetadataStatus = 'READY'
        $Descriptor.MetadataBindingToken = Get-CddsiArtifactDescriptorBindingToken -Descriptor $Descriptor
        return $Descriptor
    }

    function New-CddsiGitSupplySignatureObservation {
        param($Descriptor, [string]$SignerThumbprint = '')
        if ([string]::IsNullOrEmpty($SignerThumbprint)) { $SignerThumbprint = $Descriptor.ExpectedSignerThumbprint }
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            SignerThumbprint = $SignerThumbprint
            SignerSubjectToken = $Descriptor.ExpectedSignerSubjectToken
            PublisherToken = $Descriptor.ExpectedPublisherToken
            IdentityToken = $Descriptor.ExpectedIdentityToken
            Architecture = $Descriptor.Architecture
            ArtifactVersion = $Descriptor.ReleaseVersion
            ObservationId = 'synthetic-git-observation'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
    }

    function New-CddsiGitSupplySourceObservation {
        param($Descriptor, [string]$RunId, [string]$ArtifactProfile = 'VmAcceptance')
        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-source-observation-v1'; RunId = $RunId
            ArtifactProfile = $ArtifactProfile
            DescriptorId = $Descriptor.DescriptorId; MetadataBindingToken = $Descriptor.MetadataBindingToken
            RequestUri = $Descriptor.SourceUri; FinalUri = $Descriptor.SourceUri; RedirectUris = @()
            RedirectChainBindingToken = Get-CddsiSupplyChainTextBindingToken -Text $Descriptor.SourceUri
            RedirectCount = 0; ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes; ObservationId = 'synthetic-git-source'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
        $result = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) { $result[$property.Name] = $property.Value }
        $result['SourceObservationBindingToken'] = Get-CddsiSourceObservationBindingToken -Observation $withoutBinding
        return [pscustomobject]$result
    }
}

Describe 'P4 Git for Windows supply-chain contract' {
    It 'parses current-shaped official metadata and ignores unrelated release asset MIME types' {
        foreach ($architecture in @('x64', 'arm64')) {
            $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $script:GitFixture -Architecture $architecture
            $descriptor.ReleaseVersion | Should -BeExactly '2.55.0.3'
            $descriptor.DescriptorId | Should -Match '^git-for-windows-2\.55\.0-windows-3-'
            $descriptor.Architecture | Should -BeExactly $architecture
            $descriptor.ExpectedArtifactSha256 | Should -Match '^[a-f0-9]{64}$'
            $descriptor.MetadataStatus | Should -BeExactly 'UNRESOLVED'
            $descriptor.ExpectedSignerThumbprint | Should -BeNullOrEmpty
            $descriptor.ExpectedPublisherToken | Should -BeNullOrEmpty
            $descriptor.ExpectedIdentityToken | Should -BeNullOrEmpty
            (Test-CddsiArtifactDescriptor -Descriptor $descriptor -ExpectedArtifactType GitForWindowsInstaller) | Should -BeTrue
            (Test-CddsiArtifactDescriptor -Descriptor $descriptor -ExpectedArtifactType GitForWindowsInstaller -RequireResolved) | Should -BeFalse
        }
    }

    It 'binds windows.1 tags to the official filename without a .1 suffix' {
        $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.tag_name = 'v2.54.0.windows.1'
        $document.html_url = 'https://github.com/git-for-windows/git/releases/tag/v2.54.0.windows.1'
        $document.assets = @($document.assets[0])
        $document.assets[0].name = 'Git-2.54.0-64-bit.exe'
        $document.assets[0].browser_download_url = 'https://github.com/git-for-windows/git/releases/download/v2.54.0.windows.1/Git-2.54.0-64-bit.exe'

        $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64
        $descriptor.ReleaseVersion | Should -BeExactly '2.54.0.1'
        $descriptor.SourceUri | Should -BeExactly $document.assets[0].browser_download_url
    }

    It 'rejects draft prerelease wrong-repository tag duplicate installer and wrong revision filename' {
        foreach ($property in @('draft', 'prerelease')) {
            $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            $document.$property = $true
            { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw
        }
        $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.html_url = 'https://github.com/other/repository/releases/tag/v2.55.0.windows.3'
        { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw
        $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.assets += $document.assets[0]
        { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw
        $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.tag_name = '2.55.0'
        { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw

        $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.assets[0].browser_download_url = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/Git-2.55.0.3-arm64.exe'
        { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw

        $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
        $document.assets[0].name = 'Git-2.55.0-64-bit.exe'
        $document.assets[0].browser_download_url = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/Git-2.55.0-64-bit.exe'
        { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw
    }

    It 'rejects a selected installer with a missing digest or non-executable MIME type' {
        foreach ($mutation in @('MissingDigest', 'WrongMime')) {
            $document = $script:GitFixture | ConvertTo-Json -Depth 10 | ConvertFrom-Json
            if ($mutation -ceq 'MissingDigest') { $document.assets[0].digest = $null }
            else { $document.assets[0].content_type = 'text/plain' }
            { ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture x64 } | Should -Throw
        }
    }

    It 'consumes the GitHub latest document only through a declared fake Network observation' {
        $call = New-CddsiGitSupplyExpectedCall -Provider Network -ResourceToken '<NETWORK:GIT_FOR_WINDOWS_RELEASES_API>' -Arguments ([ordered]@{ Architecture = 'x64' }) -Result $script:GitFixture
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -ExpectedCalls @($call)
        $result = Get-CddsiOfficialGitInstallerMetadata -ExecutionContext $context -Architecture x64
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.ErrorCode | Should -BeExactly 'GIT_ARTIFACT_CONTRACT_UNRESOLVED'
        $result.Data.SourceUri | Should -Match '^https://github\.com/git-for-windows/git/releases/download/'
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        $context.AccessLedger.ProductNetworkRequestCount | Should -Be 0
    }

    It 'keeps download and verification fail-closed while signer identity is unresolved' {
        $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $script:GitFixture -Architecture x64
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $path = Join-Path $TestDrive 'Git.exe'
        $download = Save-CddsiOfficialGitInstaller -ExecutionContext $context -DestinationPath $path -ArtifactDescriptor $descriptor -Mode TestSafe
        $download.Status | Should -BeExactly 'ACTION_REQUIRED'
        $download.ErrorCode | Should -BeExactly 'GIT_ARTIFACT_CONTRACT_UNRESOLVED'
        $verification = Test-CddsiGitInstallerSignature -ExecutionContext $context -InstallerPath $path -ArtifactDescriptor $descriptor -SourceObservation $null -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z'
        $verification.Status | Should -BeExactly 'ACTION_REQUIRED'
        @($context.AccessLedger.Entries).Count | Should -Be 0
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
    }

    It 'supports a synthetic resolved contract and execution-time rehash without installing' {
        foreach ($modeCase in @(
            [pscustomobject]@{ Mode = 'TestSafe'; RunId = '20000000-0000-4000-8000-000000000421' },
            [pscustomobject]@{ Mode = 'DryRun'; RunId = '20000000-0000-4000-8000-000000000422' }
        )) {
            $descriptor = Resolve-CddsiSyntheticGitDescriptor -Descriptor (ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $script:GitFixture -Architecture x64)
            $path = Join-Path $TestDrive ('Git-{0}.exe' -f $modeCase.Mode)
            $pathToken = Get-CddsiPathBindingToken -Path $path
            $fileObservation = [pscustomobject]@{ SchemaVersion = 1; FileIdentityToken = ('f' * 64); ArtifactSha256 = $descriptor.ExpectedArtifactSha256; ArtifactSizeBytes = $descriptor.ExpectedArtifactSizeBytes }
            $sourceObservation = New-CddsiGitSupplySourceObservation -Descriptor $descriptor -RunId $modeCase.RunId
            $calls = @(
                (New-CddsiGitSupplyExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'SignatureVerification' }) -Result $fileObservation),
                (New-CddsiGitSupplyExpectedCall -Provider Package -ResourceToken '<SIGNATURE:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; ArtifactSha256 = $descriptor.ExpectedArtifactSha256 }) -Result (New-CddsiGitSupplySignatureObservation -Descriptor $descriptor)),
                (New-CddsiGitSupplyExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'ExecutionTimeHashReverification' }) -Result $fileObservation)
            )
            $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -Mode $modeCase.Mode -RunId $modeCase.RunId -ExpectedCalls $calls
            $verification = Test-CddsiGitInstallerSignature -ExecutionContext $context -InstallerPath $path -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z'
            $verification.Status | Should -BeExactly 'SUCCEEDED'
            $verification.Data.SchemaVersion | Should -Be 2
            $plan = Install-CddsiGitForWindows -ExecutionContext $context -InstallerPath $path -SignatureEvidence $verification -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z' -Mode $modeCase.Mode
            $plan.Status | Should -BeExactly 'ACTION_REQUIRED'
            $plan.Changed | Should -BeFalse
            $plan.Data.ExecutionHashReverified | Should -BeTrue
            Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
            Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $context) | Should -BeTrue
        }
    }

    It 'rejects signer mismatch and never exposes a bypass parameter' {
        $descriptor = Resolve-CddsiSyntheticGitDescriptor -Descriptor (ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $script:GitFixture -Architecture x64)
        $path = Join-Path $TestDrive 'Git.exe'
        $pathToken = Get-CddsiPathBindingToken -Path $path
        $fileObservation = [pscustomobject]@{ SchemaVersion = 1; FileIdentityToken = ('f' * 64); ArtifactSha256 = $descriptor.ExpectedArtifactSha256; ArtifactSizeBytes = $descriptor.ExpectedArtifactSizeBytes }
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -RunId '20000000-0000-4000-8000-000000000423'
        $sourceObservation = New-CddsiGitSupplySourceObservation -Descriptor $descriptor -RunId $context.RunId
        $calls = @(
            (New-CddsiGitSupplyExpectedCall -Provider FileSystem -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; Purpose = 'SignatureVerification' }) -Result $fileObservation),
            (New-CddsiGitSupplyExpectedCall -Provider Package -ResourceToken '<SIGNATURE:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathToken; ArtifactSha256 = $descriptor.ExpectedArtifactSha256 }) -Result (New-CddsiGitSupplySignatureObservation -Descriptor $descriptor -SignerThumbprint ('3' * 40)))
        )
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -RunId $context.RunId -ExpectedCalls $calls
        $verification = Test-CddsiGitInstallerSignature -ExecutionContext $context -InstallerPath $path -ArtifactDescriptor $descriptor -SourceObservation $sourceObservation -ArtifactProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z'
        $verification.Status | Should -BeExactly 'FAILED'
        $verification.Data.Valid | Should -BeFalse
        (Test-CddsiSignatureEvidence -Evidence $verification.Data -ExpectedPath $path -ExpectedArtifactType GitForWindowsInstaller -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $context.RunId -ExpectedProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z') | Should -BeFalse
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        foreach ($name in @('Test-CddsiGitInstallerSignature', 'Install-CddsiGitForWindows')) {
            foreach ($forbidden in @('SkipSignatureCheck', 'IgnoreSignature', 'Bypass', 'NoVerify')) { (Get-Command $name).Parameters.Keys | Should -Not -Contain $forbidden }
        }
    }
}
