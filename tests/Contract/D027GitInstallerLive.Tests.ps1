BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:D027GitRunId = '27000000-0000-4000-8000-000000000027'
    $script:D027GitValidationTimeUtc = '2030-01-01T00:00:30Z'
    $script:D027GitArtifactSha256 = 'af12577d0fdff74243a5988197aa49b957d5044edc17004f6ddf0768996f1dca'
    $script:D027GitArtifactSizeBytes = [long]65388144
    $script:D027GitFileIdentityToken = ('f' * 64)

    function New-CddsiD027RawGitHubReleaseDocument {
        param(
            [string]$AssetName = 'Git-2.55.0.3-64-bit.exe',
            [string]$AssetUri = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/Git-2.55.0.3-64-bit.exe'
        )

        return [pscustomobject][ordered]@{
            url = 'https://api.github.com/repos/git-for-windows/git/releases/270000027'
            assets_url = 'https://api.github.com/repos/git-for-windows/git/releases/270000027/assets'
            id = [long]270000027
            author = [pscustomobject]@{ login = 'git-for-windows-bot' }
            tag_name = 'v2.55.0.windows.3'
            target_commitish = 'main'
            name = 'Git for Windows 2.55.0(3)'
            draft = $false
            prerelease = $false
            immutable = $true
            html_url = 'https://github.com/git-for-windows/git/releases/tag/v2.55.0.windows.3'
            published_at = '2030-01-01T00:00:00Z'
            assets = @(
                [pscustomobject][ordered]@{
                    url = 'https://api.github.com/repos/git-for-windows/git/releases/assets/270000028'
                    id = [long]270000028
                    node_id = 'RA_kwDOA'
                    name = $AssetName
                    label = ''
                    uploader = [pscustomobject]@{ login = 'git-for-windows-bot' }
                    content_type = 'application/executable'
                    state = 'uploaded'
                    size = $script:D027GitArtifactSizeBytes
                    digest = 'sha256:' + $script:D027GitArtifactSha256
                    download_count = 1
                    created_at = '2030-01-01T00:00:00Z'
                    updated_at = '2030-01-01T00:00:01Z'
                    browser_download_url = $AssetUri
                },
                [pscustomobject][ordered]@{
                    url = 'https://api.github.com/repos/git-for-windows/git/releases/assets/270000029'
                    id = [long]270000029
                    node_id = 'RA_kwDOB'
                    name = 'MinGit-2.55.0.3-64-bit.zip'
                    label = ''
                    uploader = [pscustomobject]@{ login = 'git-for-windows-bot' }
                    content_type = 'application/zip'
                    state = 'uploaded'
                    size = [long]123456
                    digest = 'sha256:' + ('b' * 64)
                    download_count = 1
                    created_at = '2030-01-01T00:00:00Z'
                    updated_at = '2030-01-01T00:00:01Z'
                    browser_download_url = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/MinGit-2.55.0.3-64-bit.zip'
                }
            )
            tarball_url = 'https://api.github.com/repos/git-for-windows/git/tarball/v2.55.0.windows.3'
            zipball_url = 'https://api.github.com/repos/git-for-windows/git/zipball/v2.55.0.windows.3'
            body = 'Untrusted release notes are deliberately discarded by normalization.'
        }
    }

    function New-CddsiD027UnresolvedGitDescriptor {
        $normalized = ConvertTo-CddsiD027NormalizedGitHubReleaseDocument `
            -ReleaseDocument (New-CddsiD027RawGitHubReleaseDocument)
        return ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $normalized -Architecture x64
    }

    function New-CddsiD027UnresolvedSourceObservation {
        param($Descriptor)

        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-source-observation-v1'
            RunId = $script:D027GitRunId
            ArtifactProfile = 'VmAcceptance'
            DescriptorId = $Descriptor.DescriptorId
            MetadataBindingToken = $Descriptor.MetadataBindingToken
            RequestUri = $Descriptor.SourceUri
            FinalUri = $Descriptor.SourceUri
            RedirectUris = @()
            RedirectChainBindingToken = Get-CddsiSupplyChainTextBindingToken -Text $Descriptor.SourceUri
            RedirectCount = 0
            ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes
            ObservationId = 'd027-git-download-source'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
        $result = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) {
            $result[$property.Name] = $property.Value
        }
        $result['SourceObservationBindingToken'] =
            Get-CddsiSourceObservationBindingToken -Observation $withoutBinding
        return [pscustomobject]$result
    }

    function New-CddsiD027GitInstallerObservation {
        param($Descriptor)

        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-git-installer-observation-v1'
            DescriptorId = $Descriptor.DescriptorId
            MetadataBindingToken = $Descriptor.MetadataBindingToken
            ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes
            FileIdentityToken = $script:D027GitFileIdentityToken
            BootstrapPeMachine = 'x86'
            DeclaredPayloadArchitecture = 'x64'
            ArchitectureBindingSource = 'OfficialMetadataDigestAndFileName'
            AuthenticodeStatus = 'Valid'
            SignatureType = 'Authenticode'
            ChainTrusted = $true
            ChainRevocationMode = 'NotChecked'
            TimestampStatus = 'Present'
            TimestampChainStatus = 'NotIndependentlyEvaluated'
            SignerThumbprint = ('a' * 40)
            SignerSubjectToken = '<SIGNER_SUBJECT:GIT_FOR_WINDOWS_JOHANNES_SCHINDELIN>'
            PublisherToken = '<PUBLISHER:GIT_DEVELOPMENT_COMMUNITY>'
            IdentityToken = '<IDENTITY:GIT_FOR_WINDOWS_X64_INSTALLER>'
            ArtifactVersion = $Descriptor.ReleaseVersion
            ObservationId = 'd027-git-installer-identity'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
    }

    function Copy-CddsiD027TestObject {
        param($InputObject)
        return $InputObject | ConvertTo-Json -Depth 20 -Compress | ConvertFrom-Json
    }
}

Describe 'D-027 Git for Windows live static and pure contracts' {
    Context 'official GitHub metadata normalization and x64 scope' {
        It 'normalizes the raw GitHub response to the exact parser schema' {
            $raw = New-CddsiD027RawGitHubReleaseDocument
            $normalized = ConvertTo-CddsiD027NormalizedGitHubReleaseDocument -ReleaseDocument $raw

            (Test-CddsiExactPropertySet -InputObject $normalized `
                    -Expected @('tag_name', 'draft', 'prerelease', 'immutable', 'html_url', 'assets')) |
                Should -BeTrue
            $normalized.immutable | Should -BeTrue
            @($normalized.assets).Count | Should -Be 2
            foreach ($asset in @($normalized.assets)) {
                (Test-CddsiExactPropertySet -InputObject $asset `
                        -Expected @('name', 'browser_download_url', 'size', 'state', 'content_type', 'digest')) |
                    Should -BeTrue
            }
            $normalized.PSObject.Properties.Name | Should -Not -Contain 'body'
            $normalized.assets[0].PSObject.Properties.Name | Should -Not -Contain 'uploader'

            $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata `
                -ReleaseDocument $normalized `
                -Architecture x64
            $descriptor.Architecture | Should -BeExactly 'x64'
            $descriptor.ExpectedArtifactSha256 | Should -BeExactly $script:D027GitArtifactSha256
            $descriptor.ExpectedArtifactSizeBytes | Should -Be $script:D027GitArtifactSizeBytes
            $descriptor.MetadataStatus | Should -BeExactly 'UNRESOLVED'
        }

        It 'requires GitHub to report the release as strictly immutable' {
            foreach ($value in @($false, 'true', 1)) {
                $raw = New-CddsiD027RawGitHubReleaseDocument
                $raw.immutable = $value
                {
                    ConvertTo-CddsiD027NormalizedGitHubReleaseDocument `
                        -ReleaseDocument $raw
                } | Should -Throw
            }

            $missing = New-CddsiD027RawGitHubReleaseDocument
            $missing.PSObject.Properties.Remove('immutable')
            {
                ConvertTo-CddsiD027NormalizedGitHubReleaseDocument `
                    -ReleaseDocument $missing
            } | Should -Throw

            $normalized = ConvertTo-CddsiD027NormalizedGitHubReleaseDocument `
                -ReleaseDocument (New-CddsiD027RawGitHubReleaseDocument)
            $normalized.immutable = $false
            {
                ConvertFrom-CddsiGitHubReleaseMetadata `
                    -ReleaseDocument $normalized `
                    -Architecture x64
            } | Should -Throw
        }

        It 'selects the official installer name case-sensitively' {
            $raw = New-CddsiD027RawGitHubReleaseDocument `
                -AssetName 'git-2.55.0.3-64-bit.exe' `
                -AssetUri 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/git-2.55.0.3-64-bit.exe'
            $normalized = ConvertTo-CddsiD027NormalizedGitHubReleaseDocument -ReleaseDocument $raw

            {
                ConvertFrom-CddsiGitHubReleaseMetadata `
                    -ReleaseDocument $normalized `
                    -Architecture x64
            } | Should -Throw
        }

        It 'rejects non-x64 only in the static Live branch while retaining legacy non-Live parsing' {
            $command = Get-Command Get-CddsiOfficialGitInstallerMetadata
            $parameter = $command.Parameters['Architecture']
            $validateSet = @(
                $parameter.Attributes |
                    Where-Object { $_ -is [System.Management.Automation.ValidateSetAttribute] }
            )
            $validateSet.Count | Should -Be 1
            (@($validateSet[0].ValidValues | Sort-Object) -join "`n") |
                Should -BeExactly (@('arm64', 'x64') -join "`n")
            $command.Definition |
                Should -Match '\$Architecture\s+-cne\s+''x64'''
            $command.Definition |
                Should -Match 'GIT_ARCHITECTURE_UNSUPPORTED'
            $command.Definition |
                Should -Match 'ConvertFrom-CddsiGitHubReleaseMetadata.+-Architecture\s+x64'
        }

        It 'accepts only the sanitized GitHub release CDN path as a Git redirect receipt URI' {
            Test-CddsiOfficialArtifactRedirectUri `
                -SourceUri 'https://release-assets.githubusercontent.com/github-production-release-asset/23216272/11111111-1111-4111-8111-111111111111' `
                -ExpectedOwner GitForWindows |
                Should -BeTrue

            foreach ($uri in @(
                    'https://github.com/git-for-windows/git/releases/tag/v2.55.0.windows.3',
                    'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/Git-2.55.0.3-64-bit.exe',
                    'https://api.github.com/repos/git-for-windows/git/releases/latest',
                    'https://release-assets.githubusercontent.com/github-production-release-asset/23216272/11111111-1111-4111-8111-111111111111?token=secret',
                    'https://example.invalid/github-production-release-asset/23216272/11111111-1111-4111-8111-111111111111'
                )) {
                Test-CddsiOfficialArtifactRedirectUri `
                    -SourceUri $uri `
                    -ExpectedOwner GitForWindows |
                    Should -BeFalse
            }
        }
    }

    Context 'download receipt binding before signer resolution' {
        It 'binds an unresolved descriptor, destination, file, bytes and nested source observation' {
            $descriptor = New-CddsiD027UnresolvedGitDescriptor
            (Test-CddsiArtifactDescriptor -Descriptor $descriptor `
                    -ExpectedArtifactType GitForWindowsInstaller) |
                Should -BeTrue
            (Test-CddsiArtifactDescriptor -Descriptor $descriptor `
                    -ExpectedArtifactType GitForWindowsInstaller `
                    -RequireResolved) |
                Should -BeFalse

            $source = New-CddsiD027UnresolvedSourceObservation -Descriptor $descriptor
            $destination = Join-Path $TestDrive 'Git-2.55.0.3-64-bit.exe'
            $receipt = New-CddsiD027GitDownloadReceipt `
                -ArtifactDescriptor $descriptor `
                -DestinationPath $destination `
                -FileIdentityToken $script:D027GitFileIdentityToken `
                -SourceObservation $source `
                -ExpectedRunId $script:D027GitRunId `
                -ArtifactProfile VmAcceptance `
                -ValidationTimeUtc $script:D027GitValidationTimeUtc

            (Test-CddsiExactPropertySet -InputObject $receipt -Expected @(
                    'SchemaVersion',
                    'ContractVersion',
                    'RunId',
                    'ArtifactProfile',
                    'ArtifactType',
                    'DescriptorId',
                    'MetadataBindingToken',
                    'DestinationPathBindingToken',
                    'FileIdentityToken',
                    'ArtifactSha256',
                    'ArtifactSizeBytes',
                    'SourceObservation',
                    'ReceiptBindingToken'
                )) | Should -BeTrue
            $receipt.SchemaVersion | Should -Be 1
            $receipt.ContractVersion | Should -BeExactly 'cddsi-d027-git-download-receipt-v1'
            $receipt.RunId | Should -BeExactly $script:D027GitRunId
            $receipt.ArtifactProfile | Should -BeExactly 'VmAcceptance'
            $receipt.ArtifactType | Should -BeExactly 'GitForWindowsInstaller'
            $receipt.DescriptorId | Should -BeExactly $descriptor.DescriptorId
            $receipt.MetadataBindingToken | Should -BeExactly $descriptor.MetadataBindingToken
            $receipt.DestinationPathBindingToken |
                Should -BeExactly (Get-CddsiPathBindingToken -Path $destination)
            $receipt.FileIdentityToken | Should -BeExactly $script:D027GitFileIdentityToken
            $receipt.ArtifactSha256 | Should -BeExactly $descriptor.ExpectedArtifactSha256
            $receipt.ArtifactSizeBytes | Should -Be $descriptor.ExpectedArtifactSizeBytes
            $receipt.SourceObservation.SourceObservationBindingToken |
                Should -BeExactly $source.SourceObservationBindingToken
            $receipt.ReceiptBindingToken | Should -Match '^[a-f0-9]{64}$'

            Test-CddsiD027GitDownloadReceipt `
                -Receipt $receipt `
                -ArtifactDescriptor $descriptor `
                -ExpectedDestinationPath $destination `
                -ExpectedFileIdentityToken $script:D027GitFileIdentityToken `
                -ExpectedRunId $script:D027GitRunId `
                -ExpectedProfile VmAcceptance `
                -ValidationTimeUtc $script:D027GitValidationTimeUtc |
                Should -BeTrue
        }

        It 'rejects receipt, nested source, expected binding and extra-field tampering' {
            $descriptor = New-CddsiD027UnresolvedGitDescriptor
            $source = New-CddsiD027UnresolvedSourceObservation -Descriptor $descriptor
            $destination = Join-Path $TestDrive 'Git-2.55.0.3-64-bit.exe'
            $receipt = New-CddsiD027GitDownloadReceipt `
                -ArtifactDescriptor $descriptor `
                -DestinationPath $destination `
                -FileIdentityToken $script:D027GitFileIdentityToken `
                -SourceObservation $source `
                -ExpectedRunId $script:D027GitRunId `
                -ArtifactProfile VmAcceptance `
                -ValidationTimeUtc $script:D027GitValidationTimeUtc

            $tamperCases = @(
                [pscustomobject]@{
                    Name = 'run id'
                    Mutate = { param($value) $value.RunId = '27000000-0000-4000-8000-000000000028' }
                },
                [pscustomobject]@{
                    Name = 'artifact profile'
                    Mutate = { param($value) $value.ArtifactProfile = 'UserLive' }
                },
                [pscustomobject]@{
                    Name = 'descriptor'
                    Mutate = { param($value) $value.DescriptorId = 'git-for-windows-tampered' }
                },
                [pscustomobject]@{
                    Name = 'metadata binding'
                    Mutate = { param($value) $value.MetadataBindingToken = ('0' * 64) }
                },
                [pscustomobject]@{
                    Name = 'destination'
                    Mutate = { param($value) $value.DestinationPathBindingToken = ('1' * 64) }
                },
                [pscustomobject]@{
                    Name = 'file identity'
                    Mutate = { param($value) $value.FileIdentityToken = ('2' * 64) }
                },
                [pscustomobject]@{
                    Name = 'artifact hash'
                    Mutate = { param($value) $value.ArtifactSha256 = ('3' * 64) }
                },
                [pscustomobject]@{
                    Name = 'artifact size'
                    Mutate = { param($value) $value.ArtifactSizeBytes = [long]1 }
                },
                [pscustomobject]@{
                    Name = 'nested source hash'
                    Mutate = { param($value) $value.SourceObservation.ArtifactSha256 = ('4' * 64) }
                },
                [pscustomobject]@{
                    Name = 'nested source binding'
                    Mutate = {
                        param($value)
                        $value.SourceObservation.SourceObservationBindingToken = ('5' * 64)
                    }
                },
                [pscustomobject]@{
                    Name = 'extra field'
                    Mutate = { param($value) $value | Add-Member -NotePropertyName Unexpected -NotePropertyValue $true }
                }
            )

            foreach ($case in $tamperCases) {
                $copy = Copy-CddsiD027TestObject -InputObject $receipt
                & $case.Mutate $copy
                Test-CddsiD027GitDownloadReceipt `
                    -Receipt $copy `
                    -ArtifactDescriptor $descriptor `
                    -ExpectedDestinationPath $destination `
                    -ExpectedFileIdentityToken $script:D027GitFileIdentityToken `
                    -ExpectedRunId $script:D027GitRunId `
                    -ExpectedProfile VmAcceptance `
                    -ValidationTimeUtc $script:D027GitValidationTimeUtc |
                    Should -BeFalse -Because ('the {0} is immutable' -f $case.Name)
            }

            Test-CddsiD027GitDownloadReceipt `
                -Receipt $receipt `
                -ArtifactDescriptor $descriptor `
                -ExpectedDestinationPath (Join-Path $TestDrive 'different.exe') `
                -ExpectedFileIdentityToken $script:D027GitFileIdentityToken `
                -ExpectedRunId $script:D027GitRunId `
                -ExpectedProfile VmAcceptance `
                -ValidationTimeUtc $script:D027GitValidationTimeUtc |
                Should -BeFalse

            Test-CddsiD027GitDownloadReceipt `
                -Receipt $receipt `
                -ArtifactDescriptor $descriptor `
                -ExpectedDestinationPath $destination `
                -ExpectedFileIdentityToken ('6' * 64) `
                -ExpectedRunId $script:D027GitRunId `
                -ExpectedProfile VmAcceptance `
                -ValidationTimeUtc $script:D027GitValidationTimeUtc |
                Should -BeFalse
        }
    }

    Context 'strict x86 bootstrap and x64 payload identity resolution' {
        It 'resolves a new descriptor only from the exact trusted Git installer observation' {
            $descriptor = New-CddsiD027UnresolvedGitDescriptor
            $observation = New-CddsiD027GitInstallerObservation -Descriptor $descriptor
            $resolved = Resolve-CddsiD027GitInstallerDescriptor `
                -ArtifactDescriptor $descriptor `
                -InstallerObservation $observation

            [object]::ReferenceEquals($resolved, $descriptor) | Should -BeFalse
            $descriptor.MetadataStatus | Should -BeExactly 'UNRESOLVED'
            $descriptor.ExpectedSignerThumbprint | Should -BeNullOrEmpty
            $resolved.MetadataStatus | Should -BeExactly 'READY'
            $resolved.Architecture | Should -BeExactly 'x64'
            $resolved.ExpectedArtifactSha256 | Should -BeExactly $script:D027GitArtifactSha256
            $resolved.ExpectedSignerThumbprint | Should -BeExactly $observation.SignerThumbprint
            $resolved.ExpectedSignerSubjectToken |
                Should -BeExactly '<SIGNER_SUBJECT:GIT_FOR_WINDOWS_JOHANNES_SCHINDELIN>'
            $resolved.ExpectedPublisherToken |
                Should -BeExactly '<PUBLISHER:GIT_DEVELOPMENT_COMMUNITY>'
            $resolved.ExpectedIdentityToken |
                Should -BeExactly '<IDENTITY:GIT_FOR_WINDOWS_X64_INSTALLER>'
            $resolved.MetadataBindingToken | Should -Not -BeExactly $descriptor.MetadataBindingToken
            (Test-CddsiArtifactDescriptor -Descriptor $resolved `
                    -ExpectedArtifactType GitForWindowsInstaller `
                    -RequireResolved) |
                Should -BeTrue
        }

        It 'rejects every architecture, signature, trust, timestamp and identity mismatch' {
            $descriptor = New-CddsiD027UnresolvedGitDescriptor
            $valid = New-CddsiD027GitInstallerObservation -Descriptor $descriptor
            $invalidCases = @(
                [pscustomobject]@{
                    Name = 'contract version'
                    Mutate = { param($value) $value.ContractVersion = 'cddsi-d027-git-installer-observation-v2' }
                },
                [pscustomobject]@{
                    Name = 'descriptor id'
                    Mutate = { param($value) $value.DescriptorId = 'git-for-windows-tampered' }
                },
                [pscustomobject]@{
                    Name = 'descriptor binding'
                    Mutate = { param($value) $value.MetadataBindingToken = ('0' * 64) }
                },
                [pscustomobject]@{
                    Name = 'artifact hash'
                    Mutate = { param($value) $value.ArtifactSha256 = ('1' * 64) }
                },
                [pscustomobject]@{
                    Name = 'artifact size'
                    Mutate = { param($value) $value.ArtifactSizeBytes = [long]1 }
                },
                [pscustomobject]@{
                    Name = 'outer bootstrap machine'
                    Mutate = { param($value) $value.BootstrapPeMachine = 'x64' }
                },
                [pscustomobject]@{
                    Name = 'payload architecture'
                    Mutate = { param($value) $value.DeclaredPayloadArchitecture = 'arm64' }
                },
                [pscustomobject]@{
                    Name = 'architecture binding source'
                    Mutate = { param($value) $value.ArchitectureBindingSource = 'PeHeader' }
                },
                [pscustomobject]@{
                    Name = 'Authenticode status'
                    Mutate = { param($value) $value.AuthenticodeStatus = 'NotSigned' }
                },
                [pscustomobject]@{
                    Name = 'signature type'
                    Mutate = { param($value) $value.SignatureType = 'Catalog' }
                },
                [pscustomobject]@{
                    Name = 'signer chain'
                    Mutate = { param($value) $value.ChainTrusted = $false }
                },
                [pscustomobject]@{
                    Name = 'chain revocation mode'
                    Mutate = { param($value) $value.ChainRevocationMode = 'Online' }
                },
                [pscustomobject]@{
                    Name = 'timestamp status'
                    Mutate = { param($value) $value.TimestampStatus = 'Missing' }
                },
                [pscustomobject]@{
                    Name = 'timestamp chain'
                    Mutate = { param($value) $value.TimestampChainStatus = 'Trusted' }
                },
                [pscustomobject]@{
                    Name = 'signer thumbprint'
                    Mutate = { param($value) $value.SignerThumbprint = ('z' * 40) }
                },
                [pscustomobject]@{
                    Name = 'signer subject'
                    Mutate = {
                        param($value)
                        $value.SignerSubjectToken = '<SIGNER_SUBJECT:OTHER>'
                    }
                },
                [pscustomobject]@{
                    Name = 'publisher'
                    Mutate = { param($value) $value.PublisherToken = '<PUBLISHER:OTHER>' }
                },
                [pscustomobject]@{
                    Name = 'installer identity'
                    Mutate = { param($value) $value.IdentityToken = '<IDENTITY:OTHER>' }
                },
                [pscustomobject]@{
                    Name = 'installer version'
                    Mutate = { param($value) $value.ArtifactVersion = '2.55.0.2' }
                },
                [pscustomobject]@{
                    Name = 'observation id'
                    Mutate = { param($value) $value.ObservationId = '../unsafe' }
                },
                [pscustomobject]@{
                    Name = 'observation timestamp'
                    Mutate = { param($value) $value.ObservedAtUtc = 'not-a-timestamp' }
                },
                [pscustomobject]@{
                    Name = 'extra field'
                    Mutate = { param($value) $value | Add-Member -NotePropertyName Unexpected -NotePropertyValue $true }
                }
            )

            foreach ($case in $invalidCases) {
                $copy = Copy-CddsiD027TestObject -InputObject $valid
                & $case.Mutate $copy
                {
                    Resolve-CddsiD027GitInstallerDescriptor `
                        -ArtifactDescriptor $descriptor `
                        -InstallerObservation $copy
                } | Should -Throw -Because ('the {0} is fail-closed' -f $case.Name)
            }

            $arm64 = Copy-CddsiD027TestObject -InputObject $descriptor
            $arm64.Architecture = 'arm64'
            $arm64.FileNameToken = '<ARTIFACT_FILE:GIT_ARM64_INSTALLER>'
            $arm64.MetadataBindingToken = Get-CddsiArtifactDescriptorBindingToken -Descriptor $arm64
            $armObservation = New-CddsiD027GitInstallerObservation -Descriptor $arm64
            {
                Resolve-CddsiD027GitInstallerDescriptor `
                    -ArtifactDescriptor $arm64 `
                    -InstallerObservation $armObservation
            } | Should -Throw
        }
    }

    Context 'fixed elevated installer process policy' {
        It 'returns only the reviewed RunAs policy and exact safe installer switches' {
            $policy = Get-CddsiD027GitInstallerProcessPolicy
            $expectedArguments = @(
                '/VERYSILENT',
                '/NORESTART',
                '/NOCANCEL',
                '/SP-',
                '/SUPPRESSMSGBOXES',
                '/NOCLOSEAPPLICATIONS',
                '/NORESTARTAPPLICATIONS',
                '/RESTARTEXITCODE=8',
                '/o:PathOption=Cmd',
                '/o:EditorOption=VIM',
                '/COMPONENTS=gitlfs'
            )

            (Test-CddsiExactPropertySet -InputObject $policy -Expected @(
                    'SchemaVersion',
                    'UseShellExecute',
                    'Verb',
                    'CreateNoWindow',
                    'WindowStyle',
                    'WorkingDirectoryPolicy',
                    'ArgumentList',
                    'TimeoutSeconds',
                    'PolicyBindingToken'
                )) | Should -BeTrue
            $policy.SchemaVersion | Should -Be 1
            $policy.UseShellExecute | Should -BeTrue
            $policy.Verb | Should -BeExactly 'runas'
            $policy.CreateNoWindow | Should -BeFalse
            $policy.WindowStyle | Should -BeExactly 'Normal'
            $policy.WorkingDirectoryPolicy | Should -BeExactly 'WindowsSystemDirectory64'
            $policy.TimeoutSeconds | Should -Be 1800
            $policy.PolicyBindingToken | Should -Match '^[a-f0-9]{64}$'
            @($policy.ArgumentList).Count | Should -Be 11
            (@($policy.ArgumentList) -join "`n") |
                Should -BeExactly ($expectedArguments -join "`n")
        }

        It 'does not expose caller arguments, shell selection or verification bypasses' {
            foreach ($name in @(
                    'Save-CddsiOfficialGitInstaller',
                    'Test-CddsiGitInstallerSignature',
                    'Install-CddsiGitForWindows',
                    'Get-CddsiD027GitInstallerProcessPolicy'
                )) {
                $parameters = (Get-Command $name).Parameters.Keys
                foreach ($forbidden in @(
                        'ArgumentList',
                        'Arguments',
                        'Command',
                        'Shell',
                        'Verb',
                        'SkipSignatureCheck',
                        'IgnoreSignature',
                        'NoVerify',
                        'Bypass'
                    )) {
                    $parameters | Should -Not -Contain $forbidden
                }
            }
        }

        It 'revalidates the product temp ACL and launches from a protected system directory' {
            $validator = (Get-Command Assert-CddsiD027GitDirectorySecurity).Definition
            $download = (Get-Command Save-CddsiOfficialGitInstaller).Definition
            $install = (Get-Command Install-CddsiGitForWindows).Definition

            $validator | Should -Match 'NO_ACCESS_CONTROL'
            $validator | Should -Match 'CddsiGitDangerousAccessMask'
            $validator | Should -Match 'ReparsePoint'
            $validator | Should -Match 'DriveType.+Fixed'
            $validator | Should -Match 'DriveFormat.+NTFS'
            $download | Should -Match 'Assert-CddsiD027GitDirectorySecurity.+ProductTemp'
            $install | Should -Match 'Assert-CddsiD027GitDirectorySecurity[\s\S]+ProductTemp'
            $install | Should -Match '\[Environment\]::SystemDirectory'
            $install | Should -Match 'Assert-CddsiD027GitDirectorySecurity[\s\S]+ProtectedSystem'
            $install | Should -Match 'Start-Process[\s\S]+-WorkingDirectory\s+\$workingDirectory'
            $install | Should -Not -Match '-WorkingDirectory.+Context\.Paths\.Temp'
        }
    }

    Context 'safe UAC and installer exit mapping' {
        It 'maps UAC cancellation without reporting a change or success' {
            $result = ConvertTo-CddsiD027GitInstallerExitResult `
                -Started:$false `
                -UacCancelled:$true `
                -ExitCode $null `
                -ReadbackTrusted:$false `
                -ChangedObserved:$false `
                -RestartObserved:$false

            (Test-CddsiExactPropertySet -InputObject $result -Expected @(
                    'SchemaVersion',
                    'Status',
                    'ErrorCode',
                    'Changed',
                    'RestartRequired'
                )) | Should -BeTrue
            $result.Status | Should -BeExactly 'CANCELLED'
            $result.ErrorCode | Should -BeExactly 'GIT_INSTALL_UAC_CANCELLED'
            $result.Changed | Should -BeFalse
            $result.RestartRequired | Should -BeFalse
        }

        It 'maps success only when exit zero and readback are both trusted' {
            $result = ConvertTo-CddsiD027GitInstallerExitResult `
                -Started:$true `
                -UacCancelled:$false `
                -ExitCode 0 `
                -ReadbackTrusted:$true `
                -ChangedObserved:$true `
                -RestartObserved:$false

            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.ErrorCode | Should -BeNullOrEmpty
            $result.Changed | Should -BeTrue
            $result.RestartRequired | Should -BeFalse
        }

        It 'maps start, readback, restart and nonzero failures without false success' {
            $cases = @(
                [pscustomobject]@{
                    Started = $false
                    UacCancelled = $false
                    ExitCode = $null
                    ReadbackTrusted = $false
                    ChangedObserved = $false
                    RestartObserved = $false
                    Status = 'FAILED'
                    ErrorCode = 'GIT_INSTALL_START_FAILED'
                    Changed = $false
                    RestartRequired = $false
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = $null
                    ReadbackTrusted = $false
                    ChangedObserved = $false
                    RestartObserved = $false
                    Status = 'PARTIAL'
                    ErrorCode = 'GIT_INSTALL_TIMEOUT'
                    Changed = $false
                    RestartRequired = $false
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = 0
                    ReadbackTrusted = $false
                    ChangedObserved = $true
                    RestartObserved = $false
                    Status = 'PARTIAL'
                    ErrorCode = 'GIT_INSTALL_READBACK_FAILED'
                    Changed = $true
                    RestartRequired = $false
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = 0
                    ReadbackTrusted = $false
                    ChangedObserved = $false
                    RestartObserved = $false
                    Status = 'PARTIAL'
                    ErrorCode = 'GIT_INSTALL_READBACK_FAILED'
                    Changed = $false
                    RestartRequired = $false
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = 8
                    ReadbackTrusted = $false
                    ChangedObserved = $true
                    RestartObserved = $false
                    Status = 'RESTART_REQUIRED'
                    ErrorCode = 'GIT_INSTALL_RESTART_REQUIRED'
                    Changed = $true
                    RestartRequired = $true
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = 0
                    ReadbackTrusted = $true
                    ChangedObserved = $true
                    RestartObserved = $true
                    Status = 'RESTART_REQUIRED'
                    ErrorCode = 'GIT_INSTALL_RESTART_REQUIRED'
                    Changed = $true
                    RestartRequired = $true
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = 2
                    ReadbackTrusted = $false
                    ChangedObserved = $false
                    RestartObserved = $false
                    Status = 'FAILED'
                    ErrorCode = 'GIT_INSTALL_NONZERO'
                    Changed = $false
                    RestartRequired = $false
                },
                [pscustomobject]@{
                    Started = $true
                    UacCancelled = $false
                    ExitCode = 5
                    ReadbackTrusted = $false
                    ChangedObserved = $true
                    RestartObserved = $false
                    Status = 'PARTIAL'
                    ErrorCode = 'GIT_INSTALL_NONZERO_PARTIAL'
                    Changed = $true
                    RestartRequired = $false
                }
            )

            foreach ($case in $cases) {
                $result = ConvertTo-CddsiD027GitInstallerExitResult `
                    -Started:$case.Started `
                    -UacCancelled:$case.UacCancelled `
                    -ExitCode $case.ExitCode `
                    -ReadbackTrusted:$case.ReadbackTrusted `
                    -ChangedObserved:$case.ChangedObserved `
                    -RestartObserved:$case.RestartObserved
                $result.Status | Should -BeExactly $case.Status
                $result.ErrorCode | Should -BeExactly $case.ErrorCode
                $result.Changed | Should -Be $case.Changed
                $result.RestartRequired | Should -Be $case.RestartRequired
                $result.Status | Should -Not -BeExactly 'SUCCEEDED'
            }
        }

        It 'allows PATH readback only after a known zero exit' {
            Test-CddsiD027GitPostInstallReadbackEligible `
                -Started:$true `
                -InstallerStillRunning:$false `
                -CompletionObservationFailed:$false `
                -ExitCode 0 |
                Should -BeTrue

            foreach ($case in @(
                    [pscustomobject]@{
                        Started = $false
                        StillRunning = $false
                        CompletionFailed = $false
                        ExitCode = 0
                    },
                    [pscustomobject]@{
                        Started = $true
                        StillRunning = $true
                        CompletionFailed = $false
                        ExitCode = $null
                    },
                    [pscustomobject]@{
                        Started = $true
                        StillRunning = $false
                        CompletionFailed = $true
                        ExitCode = $null
                    },
                    [pscustomobject]@{
                        Started = $true
                        StillRunning = $false
                        CompletionFailed = $false
                        ExitCode = 8
                    },
                    [pscustomobject]@{
                        Started = $true
                        StillRunning = $false
                        CompletionFailed = $false
                        ExitCode = 5
                    }
                )) {
                Test-CddsiD027GitPostInstallReadbackEligible `
                    -Started:$case.Started `
                    -InstallerStillRunning:$case.StillRunning `
                    -CompletionObservationFailed:$case.CompletionFailed `
                    -ExitCode $case.ExitCode |
                    Should -BeFalse
            }

            (Get-Command Install-CddsiGitForWindows).Definition |
                Should -Match 'if\s*\(Test-CddsiD027GitPostInstallReadbackEligible'
        }

        It 'preserves restart, completion and readback failure precedence' {
            $restart = ConvertTo-CddsiD027GitInstallerExitResult `
                -Started:$true `
                -UacCancelled:$false `
                -ExitCode 8 `
                -ReadbackTrusted:$false `
                -ChangedObserved:$true `
                -RestartObserved:$true `
                -CompletionObservationFailed:$true `
                -ReadbackObservationFailed:$true
            $restart.Status | Should -BeExactly 'RESTART_REQUIRED'
            $restart.ErrorCode | Should -BeExactly 'GIT_INSTALL_RESTART_REQUIRED'

            $completion = ConvertTo-CddsiD027GitInstallerExitResult `
                -Started:$true `
                -UacCancelled:$false `
                -ExitCode $null `
                -ReadbackTrusted:$false `
                -ChangedObserved:$true `
                -RestartObserved:$false `
                -CompletionObservationFailed:$true `
                -ReadbackObservationFailed:$true
            $completion.Status | Should -BeExactly 'PARTIAL'
            $completion.ErrorCode | Should -BeExactly 'GIT_INSTALL_COMPLETION_UNKNOWN'

            $readback = ConvertTo-CddsiD027GitInstallerExitResult `
                -Started:$true `
                -UacCancelled:$false `
                -ExitCode 0 `
                -ReadbackTrusted:$false `
                -ChangedObserved:$true `
                -RestartObserved:$false `
                -ReadbackObservationFailed:$true
            $readback.Status | Should -BeExactly 'PARTIAL'
            $readback.ErrorCode | Should -BeExactly 'GIT_INSTALL_READBACK_FAILED'
        }

        It 'rejects contradictory UAC state instead of guessing' {
            {
                ConvertTo-CddsiD027GitInstallerExitResult `
                    -Started:$true `
                    -UacCancelled:$true `
                    -ExitCode 0 `
                    -ReadbackTrusted:$true `
                    -ChangedObserved:$false `
                    -RestartObserved:$false
            } | Should -Throw
        }
    }
}
