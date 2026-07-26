BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:ClaudeDownloadRunId =
        '27000000-0000-4000-8000-000000000227'
    $script:ClaudeDownloadStagingRoot = $TestDrive
    $script:ClaudeDownloadDestination =
        Join-Path `
            $script:ClaudeDownloadStagingRoot `
            'Claude-x64-content-addressed.msix'
    $script:ClaudeDownloadSha256 = 'a' * 64
    $script:ClaudeDownloadSize = [long]123456789
    $script:ClaudeDownloadObservedAtUtc = '2030-01-01T00:00:00Z'
    $script:ClaudeDownloadRedirects = [string[]]@(
        'https://downloads.claude.ai/releases/win32/x64/redirect.msix',
        'https://downloads.claude.ai/releases/win32/x64/1.2.3/Claude-1.2.3.msix'
    )
    $script:ClaudeDownloadPathBindingToken =
        Get-CddsiPathBindingToken -Path $script:ClaudeDownloadDestination
    $script:ClaudeDownloadVolumeSerialNumberHex = '12AB34CD'
    $script:ClaudeDownloadFileIndexHex = '0000000000000042'
    $script:ClaudeDownloadFileIdentityToken =
        Get-CddsiD027ClaudeFileIdentityToken `
            -FinalPathBindingToken `
                $script:ClaudeDownloadPathBindingToken `
            -VolumeSerialNumberHex `
                $script:ClaudeDownloadVolumeSerialNumberHex `
            -FileIndexHex $script:ClaudeDownloadFileIndexHex `
            -ArtifactSha256 $script:ClaudeDownloadSha256 `
            -ArtifactSizeBytes $script:ClaudeDownloadSize

    function New-CddsiD027ClaudeDownloadReceiptFixture {
        param(
            [string]$RunId = $script:ClaudeDownloadRunId,
            [string]$StagingRootPath =
                $script:ClaudeDownloadStagingRoot,
            [string]$DestinationPath =
                $script:ClaudeDownloadDestination,
            [string]$FileIdentityToken =
                $script:ClaudeDownloadFileIdentityToken,
            [string[]]$RedirectUris =
                $script:ClaudeDownloadRedirects,
            [string]$ArtifactSha256 =
                $script:ClaudeDownloadSha256,
            [long]$ArtifactSizeBytes =
                $script:ClaudeDownloadSize,
            [string]$ObservedAtUtc =
                $script:ClaudeDownloadObservedAtUtc
        )

        return New-CddsiD027ClaudeDownloadReceipt `
            -RunId $RunId `
            -StagingRootPath $StagingRootPath `
            -DestinationPath $DestinationPath `
            -FileIdentityToken $FileIdentityToken `
            -SanitizedRedirectUris $RedirectUris `
            -ArtifactSha256 $ArtifactSha256 `
            -ArtifactSizeBytes $ArtifactSizeBytes `
            -ObservedAtUtc $ObservedAtUtc
    }

    function New-CddsiD027ClaudeHeldObservationFixture {
        param(
            [string]$DestinationPath =
                $script:ClaudeDownloadDestination,
            [string]$ObservationMethod = 'HeldFinalFileHandle',
            [string]$FileSystemName = 'NTFS',
            [long]$NumberOfLinks = 1,
            [bool]$IsDirectory = $false,
            [bool]$IsReparsePoint = $false,
            [string]$VolumeSerialNumberHex =
                $script:ClaudeDownloadVolumeSerialNumberHex,
            [string]$FileIndexHex =
                $script:ClaudeDownloadFileIndexHex,
            [string]$ArtifactSha256 =
                $script:ClaudeDownloadSha256,
            [long]$ArtifactSizeBytes =
                $script:ClaudeDownloadSize,
            [string]$ObservedAtUtc = '2030-01-01T00:04:00Z'
        )

        $pathBindingToken =
            Get-CddsiPathBindingToken -Path $DestinationPath
        $fileIdentityToken =
            Get-CddsiD027ClaudeFileIdentityToken `
                -FinalPathBindingToken $pathBindingToken `
                -VolumeSerialNumberHex $VolumeSerialNumberHex `
                -FileIndexHex $FileIndexHex `
                -ArtifactSha256 $ArtifactSha256 `
                -ArtifactSizeBytes $ArtifactSizeBytes
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-held-artifact-observation-v1'
            ObservationMethod = $ObservationMethod
            FinalPathBindingToken = $pathBindingToken
            FileSystemName = $FileSystemName
            NumberOfLinks = [long]$NumberOfLinks
            IsDirectory = $IsDirectory
            IsReparsePoint = $IsReparsePoint
            VolumeSerialNumberHex = $VolumeSerialNumberHex
            FileIndexHex = $FileIndexHex
            FileIdentityToken = $fileIdentityToken
            ArtifactSha256 = $ArtifactSha256
            ArtifactSizeBytes = [long]$ArtifactSizeBytes
            ObservedAtUtc = $ObservedAtUtc
        }
    }

    function New-CddsiD027ClaudeTransportHeaderFactsFixture {
        param(
            [string]$TransportUri =
                (
                    'https://downloads.claude.ai/releases/win32/x64/' +
                    '1.2.3/Claude-' +
                    '0123456789abcdef0123456789abcdef01234567.msix?v=1'
                ),
            [long]$ContentLengthBytes = [long]258383876
        )

        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-transport-header-facts-v1'
            InitialRequestMethod = 'GET'
            InitialRequestUri =
                'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
            InitialStatusCode = [long]307
            RedirectCount = [long]1
            RedirectLocationHeaderCount = [long]1
            RedirectTargetTransportUri = $TransportUri
            RedirectContentTypeHeaderCount = [long]0
            RedirectContentEncodingCount = [long]0
            RedirectTransferEncodingCount = [long]0
            RedirectContentLengthHeaderCount = [long]1
            RedirectContentLengthBytes = [long]0
            FinalRequestMethod = 'GET'
            FinalRequestTransportUri = $TransportUri
            FinalStatusCode = [long]200
            FinalLocationHeaderCount = [long]0
            FinalContentTypeHeaderCount = [long]1
            FinalContentTypeMediaType = 'application/octet-stream'
            FinalContentTypeParameterCount = [long]0
            FinalContentEncodingCount = [long]0
            FinalTransferEncodingCount = [long]0
            FinalContentLengthHeaderCount = [long]1
            FinalContentLengthBytes = $ContentLengthBytes
        }
    }
}

Describe 'D-027 Claude exact unresolved source descriptor' {
    It 'matches only the one x64 Standard latest descriptor property for property' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        Test-CddsiD027ClaudeDesktopSourceDescriptor -Descriptor $descriptor |
            Should -BeTrue

        $mutations = @(
            @{ Name = 'Architecture'; Value = 'arm64' },
            @{ Name = 'Channel'; Value = 'Offline' },
            @{
                Name = 'SourceUri'
                Value =
                    'https://claude.ai/api/desktop/win32/x64/offline/latest/redirect'
            },
            @{ Name = 'ReleaseVersion'; Value = '1.2.3.4' },
            @{ Name = 'ExpectedArtifactSha256'; Value = ('b' * 64) },
            @{ Name = 'MetadataStatus'; Value = 'READY' },
            @{ Name = 'MaximumBytes'; Value = [int](1GB) }
        )
        foreach ($mutation in $mutations) {
            $changed = $descriptor.PSObject.Copy()
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            Test-CddsiD027ClaudeDesktopSourceDescriptor `
                -Descriptor $changed |
                Should -BeFalse -Because $mutation.Name
        }
    }

    It 'accepts only sanitized downloads.claude.ai MSIX path projections' {
        foreach ($uri in @(
                'https://downloads.claude.ai/Claude.msix',
                'https://downloads.claude.ai/releases/win32/x64/1.2.3/Claude-1.2.3.msix'
            )) {
            Test-CddsiD027ClaudeSanitizedDownloadUri -SourceUri $uri |
                Should -BeTrue -Because $uri
        }

        foreach ($uri in @(
                'https://downloads.claude.com/Claude.msix',
                'https://sub.downloads.claude.ai/Claude.msix',
                'https://downloads.claude.ai:444/Claude.msix',
                'http://downloads.claude.ai/Claude.msix',
                'https://downloads.claude.ai/Claude.exe',
                'https://downloads.claude.ai/Claude.MSIX',
                'https://downloads.claude.ai/releases/win32/arm64/Claude.msix',
                'https://downloads.claude.ai/releases/win32/aarch64/Claude.msix',
                'https://downloads.claude.ai/releases/win32/x86/Claude.msix',
                'https://downloads.claude.ai/releases/win32/x64/offline/Claude.msix',
                'https://downloads.claude.ai/releases/Claude-arm64.msix',
                'https://downloads.claude.ai/releases/Claude-offline.msix',
                'https://downloads.claude.ai/a//Claude.msix',
                'https://downloads.claude.ai/a/%43laude.msix',
                'https://downloads.claude.ai/Claude.msix?signature=synthetic',
                'https://downloads.claude.ai/Claude.msix#fragment'
            )) {
            Test-CddsiD027ClaudeSanitizedDownloadUri -SourceUri $uri |
                Should -BeFalse -Because $uri
        }
    }

    It 'accepts only one canonical local MSIX direct child of the bound staging root' {
        Test-CddsiD027ClaudeDownloadDestinationPath `
            -StagingRootPath $script:ClaudeDownloadStagingRoot `
            -DestinationPath $script:ClaudeDownloadDestination |
            Should -BeTrue

        $driveRoot = [IO.Path]::GetPathRoot(
            $script:ClaudeDownloadStagingRoot
        )
        $siblingRoot =
            $script:ClaudeDownloadStagingRoot + '-sibling'
        foreach ($case in @(
                @{
                    Root = $driveRoot
                    Path = Join-Path $driveRoot 'Claude.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path $siblingRoot 'Claude.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'nested\Claude.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'nested\..\Claude.msix'
                },
                @{
                    Root = '\\server\share\staging'
                    Path = '\\server\share\staging\Claude.msix'
                },
                @{
                    Root = '\\?\C:\staging'
                    Path = '\\?\C:\staging\Claude.msix'
                },
                @{
                    Root = 'C:\CON'
                    Path = 'C:\CON\Claude.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'Claude.exe'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'Claude.msix:stream'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'CON.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'NUL.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'COM1.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'LPT9.msix'
                },
                @{
                    Root = $script:ClaudeDownloadStagingRoot
                    Path = Join-Path `
                        $script:ClaudeDownloadStagingRoot `
                        'Claude-arm64.msix'
                }
            )) {
            Test-CddsiD027ClaudeDownloadDestinationPath `
                -StagingRootPath $case.Root `
                -DestinationPath $case.Path |
                Should -BeFalse -Because $case.Path
        }
    }
}

Describe 'D-027 Claude pure redirect and final-header observation' {
    It 'accepts one exact 307 to 200 GET trace and emits only a safe projection' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        $observation =
            New-CddsiD027ClaudeTransportHeaderObservation `
                -ArtifactDescriptor $descriptor `
                -HeaderFacts (
                    New-CddsiD027ClaudeTransportHeaderFactsFixture
                )

        (Test-CddsiExactPropertySet -InputObject $observation -Expected @(
                'SchemaVersion',
                'ContractVersion',
                'TransportState',
                'ArtifactProfile',
                'ArtifactType',
                'DescriptorId',
                'SourceDescriptorBindingToken',
                'RequestUriBindingToken',
                'RequestMethod',
                'InitialStatusCode',
                'SanitizedFinalUri',
                'SanitizedFinalUriBindingToken',
                'RedirectCount',
                'FinalStatusCode',
                'ContentTypeMediaType',
                'ContentEncodingCount',
                'TransferEncodingCount',
                'DeclaredContentLengthBytes',
                'HeaderObservationBindingToken'
            )) | Should -BeTrue
        $observation.TransportState |
            Should -BeExactly 'HEADERS_ACCEPTED_BODY_UNVERIFIED'
        $observation.ArtifactProfile | Should -BeExactly 'VmAcceptance'
        $observation.RequestMethod | Should -BeExactly 'GET'
        $observation.InitialStatusCode | Should -Be ([long]307)
        $observation.RedirectCount | Should -Be ([long]1)
        $observation.FinalStatusCode | Should -Be ([long]200)
        $observation.ContentTypeMediaType |
            Should -BeExactly 'application/octet-stream'
        $observation.DeclaredContentLengthBytes |
            Should -Be ([long]258383876)
        $observation.SanitizedFinalUri |
            Should -BeExactly (
                'https://downloads.claude.ai/releases/win32/x64/' +
                '1.2.3/Claude-' +
                '0123456789abcdef0123456789abcdef01234567.msix'
            )
        $observation.HeaderObservationBindingToken |
            Should -Match '^[a-f0-9]{64}$'
        Test-CddsiD027ClaudeTransportHeaderObservation `
            -Observation $observation `
            -ArtifactDescriptor $descriptor |
            Should -BeTrue
    }

    It 'never persists or binds an opaque transport query' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        $one = New-CddsiD027ClaudeTransportHeaderObservation `
            -ArtifactDescriptor $descriptor `
            -HeaderFacts (
                New-CddsiD027ClaudeTransportHeaderFactsFixture `
                    -TransportUri (
                        'https://downloads.claude.ai/releases/win32/x64/' +
                        '1.2.3/Claude-' +
                        '0123456789abcdef0123456789abcdef01234567.msix?v=1'
                    )
            )
        $two = New-CddsiD027ClaudeTransportHeaderObservation `
            -ArtifactDescriptor $descriptor `
            -HeaderFacts (
                New-CddsiD027ClaudeTransportHeaderFactsFixture `
                    -TransportUri (
                        'https://downloads.claude.ai/releases/win32/x64/' +
                        '1.2.3/Claude-' +
                        '0123456789abcdef0123456789abcdef01234567.msix?v=2'
                    )
            )

        ($one | ConvertTo-Json -Depth 4 -Compress) |
            Should -BeExactly ($two | ConvertTo-Json -Depth 4 -Compress)
        @($one.PSObject.Properties.Name) | Should -Not -Contain 'TransportUri'
        @($one.PSObject.Properties.Name) | Should -Not -Contain 'Query'
        ($one | ConvertTo-Json -Depth 4 -Compress) |
            Should -Not -Match '\?'
    }

    It 'rejects nonofficial ambiguous or contradictory transport targets' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        foreach ($uri in @(
                'https://downloads.claude.com/Claude.msix',
                'https://sub.downloads.claude.ai/Claude.msix',
                'https://downloads.claude.ai:444/Claude.msix',
                'https://downloads.claude.ai:443/releases/win32/x64/1.2.3/Claude-0123456789abcdef0123456789abcdef01234567.msix',
                'http://downloads.claude.ai/Claude.msix',
                'https://user@downloads.claude.ai/Claude.msix',
                'https://downloads.claude.ai/Claude.msix#fragment',
                '/relative/Claude.msix',
                'https://downloads.claude.ai/Claude.msix',
                'https://downloads.claude.ai/a/%43laude.msix',
                'https://downloads.claude.ai/releases/win32/x64/./1.2.3/Claude-0123456789abcdef0123456789abcdef01234567.msix',
                'https://downloads.claude.ai/releases/win32/x64/a/../1.2.3/Claude-0123456789abcdef0123456789abcdef01234567.msix',
                'https://downloads.claude.ai/releases/win32/x64/a/%2e%2e/1.2.3/Claude-0123456789abcdef0123456789abcdef01234567.msix',
                'https://downloads.claude.ai/releases/linux/x64/1.2.3/Claude.msix',
                'https://downloads.claude.ai/releases/win32/arm-64/1.2.3/Claude.msix',
                'https://downloads.claude.ai/releases/arm64/Claude.msix',
                'https://downloads.claude.ai/releases/offline/Claude.msix',
                'https://downloads.claude.ai/releases/win32/x64/1.2.3/Claude-arm-64.msix',
                'https://downloads.claude.ai/releases/win32/x64/beta/Claude-0123456789abcdef0123456789abcdef01234567.msix',
                'https://downloads.claude.ai/releases/win32/x64/1.2.3/Claude-arm32.msix',
                'https://downloads.claude.ai/releases/win32/x64/1.2.3/Claude-i386.msix',
                'https://downloads.claude.ai/releases/win32/x64/1.2.3/Claude-offlinebuild.msix',
                (
                    'https://downloads.claude.ai/releases/win32/x64/' +
                    '1.2.3/Claude-' +
                    '0123456789abcdef0123456789abcdef01234567.msix?x=' +
                    [char]1
                ),
                (
                    'https://downloads.claude.ai/releases/win32/x64/' +
                    '1.2.3/Claude-' +
                    '0123456789abcdef0123456789abcdef01234567.msix?x=' +
                    [char]9
                ),
                (
                    'https://downloads.claude.ai/releases/win32/x64/' +
                    '1.2.3/Claude-' +
                    '0123456789abcdef0123456789abcdef01234567.msix?x=' +
                    [char]0x85
                )
            )) {
            {
                New-CddsiD027ClaudeTransportHeaderObservation `
                    -ArtifactDescriptor $descriptor `
                    -HeaderFacts (
                        New-CddsiD027ClaudeTransportHeaderFactsFixture `
                            -TransportUri $uri
                    )
            } | Should -Throw '*header facts*' -Because $uri
        }
    }

    It 'rejects every redirect final-header and length policy drift' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        $mutations = @(
            @{ Name = 'InitialRequestMethod'; Value = 'HEAD' },
            @{
                Name = 'InitialRequestUri'
                Value =
                    'https://claude.ai/api/desktop/win32/x64/msix/latest'
            },
            @{ Name = 'InitialStatusCode'; Value = [long]302 },
            @{ Name = 'RedirectCount'; Value = [long]2 },
            @{ Name = 'RedirectLocationHeaderCount'; Value = [long]0 },
            @{ Name = 'RedirectLocationHeaderCount'; Value = [long]2 },
            @{ Name = 'RedirectContentTypeHeaderCount'; Value = [long]1 },
            @{ Name = 'RedirectContentEncodingCount'; Value = [long]1 },
            @{ Name = 'RedirectTransferEncodingCount'; Value = [long]1 },
            @{ Name = 'RedirectContentLengthHeaderCount'; Value = [long]0 },
            @{ Name = 'RedirectContentLengthBytes'; Value = [long]1 },
            @{ Name = 'FinalRequestMethod'; Value = 'HEAD' },
            @{
                Name = 'FinalRequestTransportUri'
                Value = 'https://downloads.claude.ai/other/Claude.msix'
            },
            @{ Name = 'FinalStatusCode'; Value = [long]206 },
            @{ Name = 'FinalLocationHeaderCount'; Value = [long]1 },
            @{ Name = 'FinalContentTypeHeaderCount'; Value = [long]0 },
            @{ Name = 'FinalContentTypeHeaderCount'; Value = [long]2 },
            @{ Name = 'FinalContentTypeMediaType'; Value = 'application/msix' },
            @{ Name = 'FinalContentTypeParameterCount'; Value = [long]1 },
            @{ Name = 'FinalContentEncodingCount'; Value = [long]1 },
            @{ Name = 'FinalTransferEncodingCount'; Value = [long]1 },
            @{ Name = 'FinalContentLengthHeaderCount'; Value = [long]0 },
            @{ Name = 'FinalContentLengthHeaderCount'; Value = [long]2 },
            @{ Name = 'FinalContentLengthBytes'; Value = [long]63 },
            @{ Name = 'FinalContentLengthBytes'; Value = [long](1GB + 1) },
            @{ Name = 'FinalStatusCode'; Value = '200' }
        )
        foreach ($mutation in $mutations) {
            $facts = New-CddsiD027ClaudeTransportHeaderFactsFixture
            $facts.PSObject.Properties[$mutation.Name].Value = $mutation.Value
            {
                New-CddsiD027ClaudeTransportHeaderObservation `
                    -ArtifactDescriptor $descriptor `
                    -HeaderFacts $facts
            } | Should -Throw '*header facts*' -Because $mutation.Name
        }

        $missingRedirectLength =
            New-CddsiD027ClaudeTransportHeaderFactsFixture
        $missingRedirectLength.RedirectContentLengthHeaderCount = [long]0
        $missingRedirectLength.RedirectContentLengthBytes = [long]-1
        {
            New-CddsiD027ClaudeTransportHeaderObservation `
                -ArtifactDescriptor $descriptor `
                -HeaderFacts $missingRedirectLength
        } | Should -Not -Throw
    }

    It 'rejects exact-schema type and semantic tampering after rebinding' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        $observation =
            New-CddsiD027ClaudeTransportHeaderObservation `
                -ArtifactDescriptor $descriptor `
                -HeaderFacts (
                    New-CddsiD027ClaudeTransportHeaderFactsFixture
                )
        foreach ($mutation in @(
                @{ Name = 'FinalStatusCode'; Value = [long]201 },
                @{ Name = 'InitialStatusCode'; Value = '307' },
                @{ Name = 'ContentEncodingCount'; Value = [long]1 },
                @{
                    Name = 'SourceDescriptorBindingToken'
                    Value = 'a' * 64
                },
                @{
                    Name = 'RequestUriBindingToken'
                    Value = 'b' * 64
                },
                @{
                    Name = 'ContractVersion'
                    Value = 'cddsi-d027-claude-transport-header-observation-v2'
                },
                @{ Name = 'TransferEncodingCount'; Value = [long]1 },
                @{ Name = 'DeclaredContentLengthBytes'; Value = [long]63 }
            )) {
            $changed = $observation.PSObject.Copy()
            $changed.PSObject.Properties[$mutation.Name].Value =
                $mutation.Value
            $changed.HeaderObservationBindingToken =
                Get-CddsiD027ClaudeTransportHeaderBindingToken `
                    -Observation $changed
            Test-CddsiD027ClaudeTransportHeaderObservation `
                -Observation $changed `
                -ArtifactDescriptor $descriptor |
                Should -BeFalse -Because $mutation.Name
        }

        $extra = $observation.PSObject.Copy()
        Add-Member -InputObject $extra -NotePropertyName RawTransportUri `
            -NotePropertyValue 'not-retained'
        Test-CddsiD027ClaudeTransportHeaderObservation `
            -Observation $extra `
            -ArtifactDescriptor $descriptor |
            Should -BeFalse
        {
            Get-CddsiD027ClaudeTransportHeaderBindingToken `
                -Observation $extra
        } | Should -Throw '*exact binding schema*'
    }

    It 'keeps transport policy pure and the public Save plan cache-neutral' {
        foreach ($name in @(
                'ConvertTo-CddsiD027ClaudeSanitizedTransportUri',
                'Get-CddsiD027ClaudeTransportHeaderBindingToken',
                'New-CddsiD027ClaudeTransportHeaderObservation',
                'Test-CddsiD027ClaudeTransportHeaderObservation'
            )) {
            $definition = (Get-Command $name -CommandType Function).Definition
            $definition | Should -Not -Match (
                '(?i)Invoke-WebRequest|Invoke-RestMethod|HttpClient|' +
                'Start-Process|Get-AuthenticodeSignature|' +
                'Get-Item|New-Item|Remove-Item|Move-Item|Copy-Item|' +
                'Get-Content|Set-Content|Add-Content|Out-File|' +
                'Test-Path|Resolve-Path|Get-ChildItem|' +
                'Get-ItemProperty|Set-ItemProperty|Add-Appx|' +
                '\[System\.IO\.File\]'
            )
        }
        $saveDefinition =
            (Get-Command Save-CddsiOfficialClaudeDesktopMsix).
                Definition
        $saveDefinition | Should -Not -Match 'CacheKey'
        $saveDefinition | Should -Not -Match 'unique-by-immutable-descriptor'
        $saveDefinition | Should -Not -Match (
            'New-CddsiD027ClaudeTransportHeaderObservation'
        )
        $saveDefinition | Should -Not -Match (
            'Assert-CddsiD027ClaudeAcquisitionLiveContext'
        )
    }
}

Describe 'D-027 Claude content-addressed download receipt' {
    It 'creates a bound DOWNLOADED_UNVERIFIED receipt without a cache-key claim' {
        $receipt = New-CddsiD027ClaudeDownloadReceiptFixture

        (Test-CddsiExactPropertySet -InputObject $receipt -Expected @(
                'SchemaVersion',
                'ContractVersion',
                'ArtifactState',
                'RunId',
                'ArtifactProfile',
                'ArtifactType',
                'DescriptorId',
                'SourceDescriptorBindingToken',
                'RequestUri',
                'RequestUriBindingToken',
                'SanitizedFinalUri',
                'SanitizedRedirectUris',
                'RedirectChainBindingToken',
                'RedirectCount',
                'StagingRootPathBindingToken',
                'DestinationPathBindingToken',
                'FileIdentityToken',
                'ArtifactSha256',
                'ArtifactSizeBytes',
                'ContentBindingToken',
                'ObservedAtUtc',
                'ReceiptBindingToken'
            )) | Should -BeTrue
        $receipt.ArtifactState |
            Should -BeExactly 'DOWNLOADED_UNVERIFIED'
        $receipt.ArtifactProfile | Should -BeExactly 'VmAcceptance'
        $receipt.ArtifactType | Should -BeExactly 'ClaudeDesktopMsix'
        $receipt.RequestUri |
            Should -BeExactly (
                'https://claude.ai/api/desktop/win32/x64/' +
                'msix/latest/redirect'
            )
        $receipt.RedirectCount | Should -Be 2
        $receipt.StagingRootPathBindingToken |
            Should -BeExactly (
                Get-CddsiPathBindingToken `
                    -Path $script:ClaudeDownloadStagingRoot
            )
        $receipt.SanitizedFinalUri |
            Should -BeExactly $script:ClaudeDownloadRedirects[-1]
        $receipt.ArtifactSha256 |
            Should -BeExactly $script:ClaudeDownloadSha256
        $receipt.ArtifactSizeBytes |
            Should -Be $script:ClaudeDownloadSize
        $receipt.ContentBindingToken |
            Should -BeExactly (
                Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $script:ClaudeDownloadSha256 `
                    -ArtifactSizeBytes $script:ClaudeDownloadSize
            )
        $receipt.PSObject.Properties.Name | Should -Not -Contain 'CacheKey'
        $receipt.PSObject.Properties.Name |
            Should -Not -Contain 'ReleaseVersion'
        $receipt.ReceiptBindingToken | Should -Match '^[a-f0-9]{64}$'

        Test-CddsiD027ClaudeDownloadReceipt `
            -Receipt $receipt `
            -ExpectedRunId $script:ClaudeDownloadRunId `
            -ExpectedStagingRootPath `
                $script:ClaudeDownloadStagingRoot `
            -ExpectedDestinationPath $script:ClaudeDownloadDestination `
            -ExpectedFileIdentityToken `
                $script:ClaudeDownloadFileIdentityToken `
            -ExpectedArtifactSha256 $script:ClaudeDownloadSha256 `
            -ExpectedArtifactSizeBytes $script:ClaudeDownloadSize `
            -ValidationTimeUtc '2030-01-01T00:05:00Z' |
            Should -BeTrue
    }

    It 'rejects semantic tampering even when the binding token is recomputed' {
        $mutations = @(
            @{
                Name = 'ArtifactState'
                Apply = {
                    param($Value)
                    $Value.ArtifactState = 'SUCCEEDED'
                }
            },
            @{
                Name = 'ArtifactProfile'
                Apply = {
                    param($Value)
                    $Value.ArtifactProfile = 'UserLive'
                }
            },
            @{
                Name = 'ArtifactType'
                Apply = {
                    param($Value)
                    $Value.ArtifactType = 'UnknownMsix'
                }
            },
            @{
                Name = 'SourceDescriptorBindingToken'
                Apply = {
                    param($Value)
                    $Value.SourceDescriptorBindingToken = 'b' * 64
                }
            },
            @{
                Name = 'RequestUri'
                Apply = {
                    param($Value)
                    $Value.RequestUri =
                        'https://claude.ai/api/desktop/win32/x64/' +
                        'offline/latest/redirect'
                }
            },
            @{
                Name = 'SanitizedFinalUri'
                Apply = {
                    param($Value)
                    $Value.SanitizedFinalUri =
                        'https://downloads.claude.ai/Other.msix'
                }
            },
            @{
                Name = 'SanitizedRedirectUris'
                Apply = {
                    param($Value)
                    $Value.SanitizedRedirectUris = [string[]]@(
                        'https://example.invalid/Claude.msix'
                    )
                }
            },
            @{
                Name = 'RedirectCount'
                Apply = { param($Value) $Value.RedirectCount = [long]1 }
            },
            @{
                Name = 'FileIdentityToken'
                Apply = {
                    param($Value)
                    $Value.FileIdentityToken = 'b' * 64
                }
            },
            @{
                Name = 'StagingRootPathBindingToken'
                Apply = {
                    param($Value)
                    $Value.StagingRootPathBindingToken = 'b' * 64
                }
            },
            @{
                Name = 'ArtifactSha256'
                Apply = {
                    param($Value)
                    $Value.ArtifactSha256 = 'b' * 64
                }
            },
            @{
                Name = 'ArtifactSizeBytes'
                Apply = {
                    param($Value)
                    $Value.ArtifactSizeBytes =
                        [long]$Value.ArtifactSizeBytes + 1
                }
            },
            @{
                Name = 'ContentBindingToken'
                Apply = {
                    param($Value)
                    $Value.ContentBindingToken = 'b' * 64
                }
            },
            @{
                Name = 'ObservedAtUtc'
                Apply = {
                    param($Value)
                    $Value.ObservedAtUtc = '2030-01-01T00:06:00Z'
                }
            }
        )

        foreach ($mutation in $mutations) {
            $changed = New-CddsiD027ClaudeDownloadReceiptFixture
            & $mutation.Apply $changed
            $changed.ReceiptBindingToken =
                Get-CddsiD027ClaudeDownloadReceiptBindingToken `
                    -Receipt $changed
            Test-CddsiD027ClaudeDownloadReceipt `
                -Receipt $changed `
                -ExpectedRunId $script:ClaudeDownloadRunId `
                -ExpectedStagingRootPath `
                    $script:ClaudeDownloadStagingRoot `
                -ExpectedDestinationPath `
                    $script:ClaudeDownloadDestination `
                -ExpectedFileIdentityToken `
                    $script:ClaudeDownloadFileIdentityToken `
                -ExpectedArtifactSha256 `
                    $script:ClaudeDownloadSha256 `
                -ExpectedArtifactSizeBytes `
                    $script:ClaudeDownloadSize `
                -ValidationTimeUtc '2030-01-01T00:05:00Z' |
                Should -BeFalse -Because $mutation.Name
        }

        $expired = New-CddsiD027ClaudeDownloadReceiptFixture
        Test-CddsiD027ClaudeDownloadReceipt `
            -Receipt $expired `
            -ExpectedRunId $script:ClaudeDownloadRunId `
            -ExpectedStagingRootPath `
                $script:ClaudeDownloadStagingRoot `
            -ExpectedDestinationPath $script:ClaudeDownloadDestination `
            -ExpectedFileIdentityToken `
                $script:ClaudeDownloadFileIdentityToken `
            -ExpectedArtifactSha256 $script:ClaudeDownloadSha256 `
            -ExpectedArtifactSizeBytes $script:ClaudeDownloadSize `
            -ValidationTimeUtc '2030-01-01T01:30:01Z' |
            Should -BeFalse
    }

    It 'rejects unsafe receipt construction before returning evidence' {
        {
            New-CddsiD027ClaudeDownloadReceiptFixture `
                -ArtifactSha256 ('0' * 64)
        } | Should -Throw
        {
            New-CddsiD027ClaudeDownloadReceiptFixture `
                -ArtifactSizeBytes 0
        } | Should -Throw
        {
            New-CddsiD027ClaudeDownloadReceiptFixture `
                -RedirectUris ([string[]]@())
        } | Should -Throw
        {
            New-CddsiD027ClaudeDownloadReceiptFixture `
                -RedirectUris @(
                    'https://downloads.claude.ai/Claude.msix?token=synthetic'
                )
        } | Should -Throw
        {
            New-CddsiD027ClaudeDownloadReceiptFixture `
                -RedirectUris ([string[]]@(
                    'https://downloads.claude.ai/Claude.msix',
                    'https://downloads.claude.ai/Claude.msix'
                ))
        } | Should -Throw
        {
            New-CddsiD027ClaudeDownloadReceiptFixture `
                -StagingRootPath (
                    $script:ClaudeDownloadStagingRoot + '-sibling'
                )
        } | Should -Throw
    }
}

Describe 'D-027 Claude held artifact TOCTOU contract' {
    It 'matches one NTFS physical identity and current content to the receipt' {
        $observation = New-CddsiD027ClaudeHeldObservationFixture
        $receipt = New-CddsiD027ClaudeDownloadReceiptFixture `
            -FileIdentityToken $observation.FileIdentityToken

        Test-CddsiD027ClaudeDownloadedArtifactObservation `
            -Observation $observation `
            -Receipt $receipt `
            -ExpectedRunId $script:ClaudeDownloadRunId `
            -ExpectedStagingRootPath `
                $script:ClaudeDownloadStagingRoot `
            -ExpectedDestinationPath $script:ClaudeDownloadDestination `
            -ValidationTimeUtc '2030-01-01T00:05:00Z' |
            Should -BeTrue
    }

    It 'rejects path, filesystem, link, physical identity and content drift' {
        $receipt = New-CddsiD027ClaudeDownloadReceiptFixture
        $mutations = @(
            @{
                Name = 'ObservationMethod'
                Apply = {
                    param($Value)
                    $Value.ObservationMethod = 'ClosedPathReopen'
                }
            },
            @{
                Name = 'FinalPathBindingToken'
                Apply = {
                    param($Value)
                    $Value.FinalPathBindingToken = 'b' * 64
                }
            },
            @{
                Name = 'FileSystemName'
                Apply = {
                    param($Value)
                    $Value.FileSystemName = 'ReFS'
                }
            },
            @{
                Name = 'NumberOfLinks'
                Apply = {
                    param($Value)
                    $Value.NumberOfLinks = [long]2
                }
            },
            @{
                Name = 'IsDirectory'
                Apply = {
                    param($Value)
                    $Value.IsDirectory = $true
                }
            },
            @{
                Name = 'IsReparsePoint'
                Apply = {
                    param($Value)
                    $Value.IsReparsePoint = $true
                }
            },
            @{
                Name = 'VolumeSerialNumberHex'
                Apply = {
                    param($Value)
                    $Value.VolumeSerialNumberHex = '56EF78AB'
                }
            },
            @{
                Name = 'FileIndexHex'
                Apply = {
                    param($Value)
                    $Value.FileIndexHex = '0000000000000043'
                }
            },
            @{
                Name = 'FileIdentityToken'
                Apply = {
                    param($Value)
                    $Value.FileIdentityToken = 'b' * 64
                }
            },
            @{
                Name = 'ArtifactSha256'
                Apply = {
                    param($Value)
                    $Value.ArtifactSha256 = 'b' * 64
                }
            },
            @{
                Name = 'ArtifactSizeBytes'
                Apply = {
                    param($Value)
                    $Value.ArtifactSizeBytes =
                        [long]$Value.ArtifactSizeBytes + 1
                }
            },
            @{
                Name = 'ObservedAtUtcStale'
                Apply = {
                    param($Value)
                    $Value.ObservedAtUtc = '2029-12-31T23:59:59Z'
                }
            },
            @{
                Name = 'ObservedAtUtcFuture'
                Apply = {
                    param($Value)
                    $Value.ObservedAtUtc = '2030-01-01T00:05:31Z'
                }
            }
        )

        foreach ($mutation in $mutations) {
            $changed = New-CddsiD027ClaudeHeldObservationFixture
            & $mutation.Apply $changed
            Test-CddsiD027ClaudeDownloadedArtifactObservation `
                -Observation $changed `
                -Receipt $receipt `
                -ExpectedRunId $script:ClaudeDownloadRunId `
                -ExpectedStagingRootPath `
                    $script:ClaudeDownloadStagingRoot `
                -ExpectedDestinationPath `
                    $script:ClaudeDownloadDestination `
                -ValidationTimeUtc '2030-01-01T00:05:00Z' |
                Should -BeFalse -Because $mutation.Name
        }
    }

    It 'rejects a held observation that predates the download receipt' {
        $receipt = New-CddsiD027ClaudeDownloadReceiptFixture `
            -ObservedAtUtc '2030-01-01T00:04:00Z'
        $observation = New-CddsiD027ClaudeHeldObservationFixture `
            -ObservedAtUtc '2030-01-01T00:00:00Z'

        Test-CddsiD027ClaudeDownloadedArtifactObservation `
            -Observation $observation `
            -Receipt $receipt `
            -ExpectedRunId $script:ClaudeDownloadRunId `
            -ExpectedStagingRootPath `
                $script:ClaudeDownloadStagingRoot `
            -ExpectedDestinationPath `
                $script:ClaudeDownloadDestination `
            -ValidationTimeUtc '2030-01-01T00:05:00Z' |
            Should -BeFalse
    }

    It 'keeps the pure contract free of network, file, process and registry access' {
        $functionNames = @(
            'New-CddsiD027ClaudeDesktopSourceDescriptor',
            'Test-CddsiD027ClaudeDesktopSourceDescriptor',
            'Test-CddsiD027ClaudeSanitizedDownloadUri',
            'ConvertTo-CddsiD027ClaudeSanitizedTransportUri',
            'Get-CddsiD027ClaudeTransportHeaderBindingToken',
            'New-CddsiD027ClaudeTransportHeaderObservation',
            'Test-CddsiD027ClaudeTransportHeaderObservation',
            'Test-CddsiD027ClaudeDownloadDestinationPath',
            'Get-CddsiD027ClaudeDownloadReceiptBindingToken',
            'Get-CddsiD027ClaudeFileIdentityToken',
            'Get-CddsiD027ClaudeContentBindingToken',
            'New-CddsiD027ClaudeDownloadReceipt',
            'Test-CddsiD027ClaudeDownloadReceipt',
            'Test-CddsiD027ClaudeDownloadedArtifactObservation'
        )
        foreach ($name in $functionNames) {
            $definition = (Get-Command $name -CommandType Function).Definition
            $definition | Should -Not -Match (
                '(?i)Invoke-WebRequest|Invoke-RestMethod|HttpClient|' +
                'Start-Process|Get-AuthenticodeSignature|' +
                'Get-Item|New-Item|Remove-Item|Move-Item|Copy-Item|' +
                'Get-Content|Set-Content|Add-Content|Out-File|' +
                'Test-Path|Resolve-Path|Get-ChildItem|' +
                'Get-ItemProperty|Set-ItemProperty|Add-Appx|' +
                '\[System\.IO\.File\]'
            )
        }

        $parameters =
            (Get-Command New-CddsiD027ClaudeDownloadReceipt).Parameters.Keys
        foreach ($name in @(
                'ArtifactProfile',
                'Descriptor',
                'SourceUri',
                'Status',
                'ArtifactState',
                'CacheKey',
                'Bypass'
            )) {
            $parameters | Should -Not -Contain $name
        }
    }
}
