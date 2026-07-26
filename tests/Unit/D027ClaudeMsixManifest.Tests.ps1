BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    Add-Type -AssemblyName System.IO.Compression
    Add-Type -AssemblyName System.IO.Compression.FileSystem

    # Parser-only synthetic identity. This is not an observed or trusted Anthropic
    # publisher; the later signer/publisher gate must freeze real package facts.
    $script:ValidClaudeManifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="Claude" Publisher="CN=CDDsi Synthetic Fixture, O=CDDsi Test Only, C=US" Version="1.2.3.4" ProcessorArchitecture="x64" ResourceId="" />
  <Properties>
    <DisplayName>Claude</DisplayName>
  </Properties>
</Package>
'@

    function ConvertTo-CddsiD027TestManifestBytes {
        param([Parameter(Mandatory = $true)][string]$Xml)
        return [System.Text.Encoding]::UTF8.GetBytes($Xml)
    }

    function Get-CddsiD027TestManifestSha256 {
        param([Parameter(Mandatory = $true)][byte[]]$Bytes)

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            return [BitConverter]::ToString(
                $sha.ComputeHash($Bytes)
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
    }

    function New-CddsiD027TestMsixStream {
        param(
            [Parameter(Mandatory = $true)][object[]]$Entries
        )

        $stream = New-Object System.IO.MemoryStream
        $archive = [System.IO.Compression.ZipArchive]::new(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Update,
            $true
        )
        try {
            foreach ($definition in $Entries) {
                $entry = $archive.CreateEntry(
                    [string]$definition.Name,
                    [System.IO.Compression.CompressionLevel]::Optimal
                )
                $entryStream = $entry.Open()
                try {
                    [byte[]]$bytes = if ($definition.Content -is [byte[]]) {
                        $definition.Content
                    }
                    else {
                        [System.Text.Encoding]::UTF8.GetBytes(
                            [string]$definition.Content
                        )
                    }
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally {
                    $entryStream.Dispose()
                }
            }
        }
        finally {
            $archive.Dispose()
        }
        $stream.Position = 0
        return ,$stream
    }

    function Add-CddsiD027TestCriticalMsixEntries {
        param(
            [Parameter(Mandatory = $true)]
            [AllowEmptyCollection()]
            [object[]]$ManifestEntries
        )

        return @(
            $ManifestEntries
            [pscustomobject]@{
                Name = 'AppxSignature.p7x'
                Content = 'synthetic signature placeholder'
            }
            [pscustomobject]@{
                Name = 'AppxBlockMap.xml'
                Content = '<BlockMap />'
            }
            [pscustomobject]@{
                Name = '[Content_Types].xml'
                Content = '<Types />'
            }
        )
    }
}

Describe 'D-027 Claude Desktop bounded MSIX manifest parser' {
    It 'extracts one exact Claude x64 package identity from bounded XML bytes' {
        $manifestBytes = ConvertTo-CddsiD027TestManifestBytes `
            -Xml $script:ValidClaudeManifest
        $expectedManifestSha256 =
            Get-CddsiD027TestManifestSha256 -Bytes $manifestBytes
        $result = ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
            -ManifestBytes $manifestBytes

        (Test-CddsiExactPropertySet -InputObject $result -Expected @(
                'SchemaVersion',
                'ContractVersion',
                'PackageName',
                'Publisher',
                'PublisherTextSha256',
                'PublisherParsedX500RawDataSha256',
                'PackageVersion',
                'Architecture',
                'ResourceId',
                'PackageIdentityBindingToken',
                'ManifestSha256',
                'ManifestLengthBytes',
                'ManifestBindingToken'
            )) | Should -BeTrue
        $result.SchemaVersion | Should -Be 1
        $result.ContractVersion |
            Should -BeExactly 'cddsi-d027-claude-appx-manifest-v1'
        $result.PackageName | Should -BeExactly 'Claude'
        $result.Publisher |
            Should -BeExactly 'CN=CDDsi Synthetic Fixture, O=CDDsi Test Only, C=US'
        $result.PublisherTextSha256 | Should -Match '^[a-f0-9]{64}$'
        $result.PublisherParsedX500RawDataSha256 |
            Should -Match '^[a-f0-9]{64}$'
        $result.PackageVersion | Should -BeExactly '1.2.3.4'
        $result.Architecture | Should -BeExactly 'x64'
        $result.ResourceId | Should -BeExactly ''
        $result.PackageIdentityBindingToken | Should -Match '^[a-f0-9]{64}$'
        $result.ManifestSha256 |
            Should -BeExactly $expectedManifestSha256
        $result.ManifestLengthBytes | Should -Be $manifestBytes.Length
        $result.ManifestBindingToken |
            Should -BeExactly (
                Get-CddsiD027ClaudeManifestBindingToken `
                    -ManifestIdentity $result
            )
        (Get-Command ConvertFrom-CddsiD027ClaudeAppxManifestBytes).
            Definition | Should -Match (
                '\$manifestSnapshot\s*=\s*' +
                '\[byte\[\]\]\$ManifestBytes\.Clone\(\)'
            )
    }

    It 'reads only one exact root AppxManifest.xml and restores the caller stream position' {
        $entries = Add-CddsiD027TestCriticalMsixEntries -ManifestEntries @(
            [pscustomobject]@{
                Name = 'AppxManifest.xml'
                Content = $script:ValidClaudeManifest
            }
        )
        $entries += [pscustomobject]@{
            Name = 'Assets/placeholder.txt'
            Content = 'not executable'
        }
        $stream = New-CddsiD027TestMsixStream -Entries $entries
        try {
            $stream.Position = 5
            $result = Read-CddsiD027ClaudeMsixManifest -PackageStream $stream
            $result.PackageName | Should -BeExactly 'Claude'
            $result.PackageVersion | Should -BeExactly '1.2.3.4'
            $stream.Position | Should -Be 5
        }
        finally {
            $stream.Dispose()
        }

        $pastEnd = New-CddsiD027TestMsixStream -Entries $entries
        try {
            $pastEnd.Position = $pastEnd.Length + 7
            $originalPosition = $pastEnd.Position
            {
                Read-CddsiD027ClaudeMsixManifest -PackageStream $pastEnd
            } | Should -Throw
            $pastEnd.Position | Should -Be $originalPosition
        }
        finally {
            $pastEnd.Dispose()
        }

        $invalidEntries = Add-CddsiD027TestCriticalMsixEntries `
            -ManifestEntries @(
                [pscustomobject]@{
                    Name = 'AppxManifest.xml'
                    Content = $script:ValidClaudeManifest.Replace(
                        'Name="Claude"',
                        'Name="Other"'
                    )
                }
            )
        $invalid = New-CddsiD027TestMsixStream -Entries $invalidEntries
        try {
            $invalid.Position = 5
            {
                Read-CddsiD027ClaudeMsixManifest -PackageStream $invalid
            } | Should -Throw
            $invalid.Position | Should -Be 5
        }
        finally {
            $invalid.Dispose()
        }
    }

    It 'rejects every package identity, publisher, version and XML ambiguity mutation' {
        $mutations = @(
            $script:ValidClaudeManifest.Replace('Name="Claude"', 'Name="Other"'),
            $script:ValidClaudeManifest.Replace(
                'ProcessorArchitecture="x64"',
                'ProcessorArchitecture="arm64"'
            ),
            $script:ValidClaudeManifest.Replace('Version="1.2.3.4"', 'Version="1.2.3"'),
            $script:ValidClaudeManifest.Replace(
                'Version="1.2.3.4"',
                'Version="1.2.3.65536"'
            ),
            $script:ValidClaudeManifest.Replace(
                'Publisher="CN=CDDsi Synthetic Fixture, O=CDDsi Test Only, C=US"',
                'Publisher="not a distinguished name"'
            ),
            $script:ValidClaudeManifest.Replace('ResourceId=""', 'ResourceId="../bad"'),
            $script:ValidClaudeManifest.Replace(
                'ResourceId=""',
                'ResourceId="" Unexpected="value"'
            ),
            $script:ValidClaudeManifest.Replace(
                '  <Properties>',
                '  <Identity Name="Claude" Publisher="CN=CDDsi Synthetic Fixture, O=CDDsi Test Only, C=US" Version="1.2.3.4" ProcessorArchitecture="x64" />' +
                    "`n  <Properties>"
            ),
            $script:ValidClaudeManifest.Replace(
                'http://schemas.microsoft.com/appx/manifest/foundation/windows10',
                'https://example.invalid/wrong'
            ),
            (
                '<!DOCTYPE Package [<!ENTITY x "bad">]>' +
                $script:ValidClaudeManifest.Replace(
                    '<?xml version="1.0" encoding="utf-8"?>',
                    ''
                )
            )
        )

        foreach ($xml in $mutations) {
            {
                ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
                    -ManifestBytes (
                        ConvertTo-CddsiD027TestManifestBytes -Xml $xml
                    )
            } | Should -Throw
        }
    }

    It 'rejects missing, nested, wrong-case and duplicate critical ZIP entries' {
        $entrySets = @(
            [pscustomobject]@{
                Entries = @(
                [pscustomobject]@{
                    Name = 'Assets/placeholder.txt'
                    Content = 'missing'
                }
                )
            },
            [pscustomobject]@{
                Entries = @(
                [pscustomobject]@{
                    Name = 'Nested/AppxManifest.xml'
                    Content = $script:ValidClaudeManifest
                }
                )
            },
            [pscustomobject]@{
                Entries = @(
                [pscustomobject]@{
                    Name = 'appxmanifest.xml'
                    Content = $script:ValidClaudeManifest
                }
                )
            },
            [pscustomobject]@{
                Entries = @(
                [pscustomobject]@{
                    Name = 'AppxManifest.xml'
                    Content = $script:ValidClaudeManifest
                },
                [pscustomobject]@{
                    Name = 'AppxManifest.xml'
                    Content = $script:ValidClaudeManifest
                }
                )
            }
        )

        foreach ($case in $entrySets) {
            $entries = Add-CddsiD027TestCriticalMsixEntries `
                -ManifestEntries $case.Entries
            $stream = New-CddsiD027TestMsixStream -Entries $entries
            try {
                {
                    Read-CddsiD027ClaudeMsixManifest -PackageStream $stream
                } | Should -Throw
            }
            finally {
                $stream.Dispose()
            }
        }

        $validEntries = Add-CddsiD027TestCriticalMsixEntries `
            -ManifestEntries @(
                [pscustomobject]@{
                    Name = 'AppxManifest.xml'
                    Content = $script:ValidClaudeManifest
                }
            )
        foreach ($requiredName in @(
                'AppxSignature.p7x',
                'AppxBlockMap.xml',
                '[Content_Types].xml'
            )) {
            foreach ($mutation in @('Missing', 'WrongCase', 'Duplicate')) {
                $mutatedEntries = @(
                    foreach ($definition in $validEntries) {
                        if (
                            $definition.Name -ceq $requiredName -and
                            $mutation -ceq 'Missing'
                        ) {
                            continue
                        }
                        if (
                            $definition.Name -ceq $requiredName -and
                            $mutation -ceq 'WrongCase'
                        ) {
                            [pscustomobject]@{
                                Name = $requiredName.ToLowerInvariant()
                                Content = $definition.Content
                            }
                            continue
                        }
                        $definition
                    }
                    if ($mutation -ceq 'Duplicate') {
                        $duplicate = @(
                            $validEntries |
                                Where-Object Name -CEQ $requiredName
                        )[0]
                        [pscustomobject]@{
                            Name = $duplicate.Name
                            Content = $duplicate.Content
                        }
                    }
                )
                $stream = New-CddsiD027TestMsixStream -Entries $mutatedEntries
                try {
                    {
                        Read-CddsiD027ClaudeMsixManifest -PackageStream $stream
                    } | Should -Throw
                }
                finally {
                    $stream.Dispose()
                }
            }
        }
    }

    It 'rejects empty, oversized and non-ZIP package content without reading the host' {
        {
            ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
                -ManifestBytes (New-Object byte[] ((1MB) + 1))
        } | Should -Throw

        foreach ($bytes in @(
                (New-Object byte[] 0),
                [System.Text.Encoding]::UTF8.GetBytes('not a zip package')
            )) {
            $stream = New-Object System.IO.MemoryStream(,$bytes)
            try {
                {
                    Read-CddsiD027ClaudeMsixManifest -PackageStream $stream
                } | Should -Throw
            }
            finally {
                $stream.Dispose()
            }
        }
    }
}
