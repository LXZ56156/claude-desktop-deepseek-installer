BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'D-027 Claude Desktop official source contract' {
    It 'creates one unresolved Standard x64 descriptor without invented artifact facts' {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor

        (Test-CddsiExactPropertySet -InputObject $descriptor -Expected @(
                'SchemaVersion',
                'DescriptorId',
                'ArtifactType',
                'SourcePolicy',
                'SourceUri',
                'SourceUriBindingToken',
                'ReleaseVersion',
                'Architecture',
                'Channel',
                'FileNameToken',
                'ExpectedArtifactSha256',
                'ExpectedArtifactSizeBytes',
                'ExpectedSignerThumbprint',
                'ExpectedSignerSubjectToken',
                'ExpectedPublisherToken',
                'ExpectedIdentityToken',
                'RedirectPolicy',
                'MaximumBytes',
                'MetadataStatus',
                'MetadataBindingToken'
            )) | Should -BeTrue
        $descriptor.DescriptorId |
            Should -BeExactly 'claude-desktop-standard-x64-latest'
        $descriptor.SourceUri |
            Should -BeExactly 'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
        $descriptor.Architecture | Should -BeExactly 'x64'
        $descriptor.Channel | Should -BeExactly 'Standard'
        $descriptor.ReleaseVersion | Should -BeNullOrEmpty
        $descriptor.ExpectedArtifactSha256 | Should -BeNullOrEmpty
        $descriptor.ExpectedArtifactSizeBytes | Should -BeNullOrEmpty
        $descriptor.ExpectedSignerThumbprint | Should -BeNullOrEmpty
        $descriptor.ExpectedSignerSubjectToken | Should -BeNullOrEmpty
        $descriptor.ExpectedPublisherToken | Should -BeNullOrEmpty
        $descriptor.ExpectedIdentityToken | Should -BeNullOrEmpty
        $descriptor.MetadataStatus | Should -BeExactly 'UNRESOLVED'
        $descriptor.MaximumBytes | Should -Be ([long](1GB))
        $descriptor.MetadataBindingToken | Should -Match '^[a-f0-9]{64}$'
        Test-CddsiArtifactDescriptor `
            -Descriptor $descriptor `
            -ExpectedArtifactType ClaudeDesktopMsix |
            Should -BeTrue
        Test-CddsiArtifactDescriptor `
            -Descriptor $descriptor `
            -ExpectedArtifactType ClaudeDesktopMsix `
            -RequireResolved |
            Should -BeFalse
    }

    It 'recognizes documented endpoint shapes while the D-027 descriptor fixes x64 Standard' {
        Test-CddsiOfficialArtifactUri `
            -SourceUri 'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect' `
            -ExpectedOwner Anthropic |
            Should -BeTrue

        Test-CddsiOfficialArtifactUri `
            -SourceUri 'https://claude.ai/api/desktop/win32/x64/latest/redirect' `
            -ExpectedOwner Anthropic |
            Should -BeFalse
        Test-CddsiOfficialArtifactUri `
            -SourceUri 'https://claude.ai/api/desktop/win32/x64/offline/latest/redirect' `
            -ExpectedOwner Anthropic |
            Should -BeTrue
        Test-CddsiOfficialArtifactUri `
            -SourceUri 'https://claude.ai/api/desktop/win32/arm64/msix/latest/redirect' `
            -ExpectedOwner Anthropic |
            Should -BeTrue
        foreach ($uri in @(
                'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect?token=secret',
                'https://claude.ai:444/api/desktop/win32/x64/msix/latest/redirect',
                'http://claude.ai/api/desktop/win32/x64/msix/latest/redirect',
                'https://example.invalid/api/desktop/win32/x64/msix/latest/redirect'
            )) {
            Test-CddsiOfficialArtifactUri -SourceUri $uri -ExpectedOwner Anthropic |
                Should -BeFalse
        }
    }

    It 'keeps D-027 source selection free of caller architecture, channel or URI inputs' {
        $parameters =
            (Get-Command New-CddsiD027ClaudeDesktopSourceDescriptor).Parameters.Keys
        foreach ($name in @(
                'Architecture',
                'Channel',
                'SourceUri',
                'DownloadUri',
                'Offline',
                'Arm64',
                'Bypass'
            )) {
            $parameters | Should -Not -Contain $name
        }
    }
}
