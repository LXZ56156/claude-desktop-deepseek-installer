BeforeAll {
    $script:RepoRoot =
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:DesktopMsixPath =
        Join-Path $script:RepoRoot 'lib\desktop-msix.ps1'
    $tokens = $null
    $errors = $null
    $script:DesktopMsixAst =
        [System.Management.Automation.Language.Parser]::ParseFile(
            $script:DesktopMsixPath,
            [ref]$tokens,
            [ref]$errors
        )
    if (@($errors).Count -ne 0) {
        throw 'desktop-msix.ps1 did not parse for the focused test.'
    }
    $script:ExpectedWriterProperties = @(
        'SchemaVersion',
        'ContractVersion',
        'Status',
        'ErrorCode',
        'PartialCreated',
        'DurableFlushCompleted',
        'PartialPathBindingToken',
        'ArtifactSha256',
        'ArtifactSizeBytes'
    )

    function Get-CddsiD027DownloadWriterTestSha256 {
        param(
            [Parameter(Mandatory = $true)][byte[]]$Bytes
        )

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

    function New-CddsiD027DownloadWriterTestBytes {
        param(
            [Parameter(Mandatory = $true)][int]$Length
        )

        $bytes = New-Object byte[] $Length
        for ($index = 0; $index -lt $bytes.Length; $index++) {
            $bytes[$index] = [byte]($index % 251)
        }
        return $bytes
    }
}

Describe 'D-027 Claude bounded download body writer' {
    It 'keeps the writer and partial-path validator private exact delegates' {
        $script:CddsiD027ClaudeDownloadPartialPathValidator.GetType().
            Name |
            Should -BeExactly 'Func`3'
        $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.GetType().
            Name |
            Should -BeExactly 'Func`6'
        @(
            Get-Command `
                '*CddsiD027Claude*Download*Writer*' `
                -CommandType Function `
                -ErrorAction SilentlyContinue
        ).Count | Should -Be 0
    }

    It 'writes, hashes and durably flushes one exact declared body' {
        $bytes =
            New-CddsiD027DownloadWriterTestBytes -Length 131073
        $source = [System.IO.MemoryStream]::new($bytes, $false)
        $partialPath =
            Join-Path $TestDrive 'claude-0123456789abcdef.partial'
        try {
            $result =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $source,
                        $TestDrive,
                        $partialPath,
                        [long]$bytes.Length,
                        [System.Threading.CancellationToken]::None
                    )

            (@($result.PSObject.Properties.Name) -join ',') |
                Should -BeExactly (
                    $script:ExpectedWriterProperties -join ','
                )
            $result.SchemaVersion | Should -Be 1
            $result.ContractVersion |
                Should -BeExactly (
                    'cddsi-d027-claude-download-body-write-v1'
                )
            $result.Status | Should -BeExactly 'COMPLETED'
            $result.ErrorCode | Should -BeExactly ''
            $result.PartialCreated | Should -BeTrue
            $result.DurableFlushCompleted | Should -BeTrue
            $result.PartialPathBindingToken |
                Should -BeExactly (
                    Get-CddsiPathBindingToken -Path $partialPath
                )
            $result.ArtifactSha256 |
                Should -BeExactly (
                    Get-CddsiD027DownloadWriterTestSha256 -Bytes $bytes
                )
            $result.ArtifactSizeBytes | Should -Be $bytes.Length
            $writtenBytes =
                [System.IO.File]::ReadAllBytes($partialPath)
            $writtenBytes.Length | Should -Be $bytes.Length
            Get-CddsiD027DownloadWriterTestSha256 -Bytes $writtenBytes |
                Should -BeExactly $result.ArtifactSha256
            $source.CanRead | Should -BeTrue
            $source.Position | Should -Be $source.Length
        }
        finally {
            $source.Dispose()
        }
    }

    It 'fails closed on truncation and preserves the caller stream contract' {
        $bytes = New-CddsiD027DownloadWriterTestBytes -Length 64
        $source = [System.IO.MemoryStream]::new($bytes, $false)
        $partialPath =
            Join-Path $TestDrive 'claude-1111111111111111.partial'
        try {
            $result =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $source,
                        $TestDrive,
                        $partialPath,
                        [long]65,
                        [System.Threading.CancellationToken]::None
                    )

            $result.Status | Should -BeExactly 'FAILED'
            $result.ErrorCode |
                Should -BeExactly 'DOWNLOAD_BODY_TRUNCATED'
            $result.PartialCreated | Should -BeTrue
            $result.DurableFlushCompleted | Should -BeFalse
            $result.ArtifactSha256 | Should -BeNullOrEmpty
            $result.ArtifactSizeBytes | Should -BeNullOrEmpty
            [System.IO.FileInfo]::new($partialPath).Length |
                Should -Be 64
            $source.CanRead | Should -BeTrue
        }
        finally {
            $source.Dispose()
        }
    }

    It 'rejects bytes beyond the declared length before writing that block' {
        $bytes = New-CddsiD027DownloadWriterTestBytes -Length 65
        $source = [System.IO.MemoryStream]::new($bytes, $false)
        $partialPath =
            Join-Path $TestDrive 'claude-2222222222222222.partial'
        try {
            $result =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $source,
                        $TestDrive,
                        $partialPath,
                        [long]64,
                        [System.Threading.CancellationToken]::None
                    )

            $result.ErrorCode |
                Should -BeExactly (
                    'DOWNLOAD_BODY_EXCEEDED_DECLARED_LENGTH'
                )
            $result.PartialCreated | Should -BeTrue
            [System.IO.FileInfo]::new($partialPath).Length |
                Should -Be 0
        }
        finally {
            $source.Dispose()
        }
    }

    It 'honors cancellation without disposing the caller stream' {
        $bytes = New-CddsiD027DownloadWriterTestBytes -Length 64
        $source = [System.IO.MemoryStream]::new($bytes, $false)
        $cancellation =
            New-Object System.Threading.CancellationTokenSource
        $partialPath =
            Join-Path $TestDrive 'claude-3333333333333333.partial'
        try {
            $cancellation.Cancel()
            $result =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $source,
                        $TestDrive,
                        $partialPath,
                        [long]64,
                        $cancellation.Token
                    )

            $result.Status | Should -BeExactly 'FAILED'
            $result.ErrorCode |
                Should -BeExactly 'DOWNLOAD_BODY_CANCELLED'
            $result.PartialCreated | Should -BeTrue
            $result.DurableFlushCompleted | Should -BeFalse
            $source.CanRead | Should -BeTrue
        }
        finally {
            $cancellation.Dispose()
            $source.Dispose()
        }
    }

    It 'rejects invalid or preexisting partial destinations without overwrite' {
        $existingPath =
            Join-Path $TestDrive 'claude-4444444444444444.partial'
        $sentinel = [byte[]](1, 2, 3, 4)
        [System.IO.File]::WriteAllBytes($existingPath, $sentinel)
        $source = [System.IO.MemoryStream]::new(
            (New-CddsiD027DownloadWriterTestBytes -Length 64),
            $false
        )
        try {
            $existing =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $source,
                        $TestDrive,
                        $existingPath,
                        [long]64,
                        [System.Threading.CancellationToken]::None
                    )
            $existing.ErrorCode |
                Should -BeExactly 'DOWNLOAD_PARTIAL_EXISTS'
            $existing.PartialCreated | Should -BeFalse
            [System.IO.File]::ReadAllBytes($existingPath) |
                Should -Be $sentinel

            $badPath = Join-Path $TestDrive 'Claude.partial'
            $invalid =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $source,
                        $TestDrive,
                        $badPath,
                        [long]64,
                        [System.Threading.CancellationToken]::None
                    )
            $invalid.ErrorCode | Should -BeExactly 'INVALID_INPUT'
            $invalid.PartialCreated | Should -BeFalse
            $invalid.PartialPathBindingToken |
                Should -BeNullOrEmpty
            [System.IO.File]::Exists($badPath) | Should -BeFalse

            $nestedRoot = Join-Path $TestDrive 'nested'
            [void][System.IO.Directory]::CreateDirectory($nestedRoot)
            foreach ($unsafePath in @(
                    (Join-Path `
                        ($TestDrive + '-sibling') `
                        'claude-5555555555555555.partial'),
                    (Join-Path `
                        $nestedRoot `
                        'claude-6666666666666666.partial'),
                    (Join-Path `
                        $TestDrive `
                        'nested\..\claude-7777777777777777.partial'),
                    (Join-Path `
                        $TestDrive `
                        'claude-8888888888888888.partial:stream')
                )) {
                $unsafe =
                    $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                        Invoke(
                            $source,
                            $TestDrive,
                            $unsafePath,
                            [long]64,
                            [System.Threading.CancellationToken]::None
                        )
                $unsafe.ErrorCode | Should -BeExactly 'INVALID_INPUT'
                $unsafe.PartialCreated | Should -BeFalse
                [System.IO.File]::Exists($unsafePath) |
                    Should -BeFalse
            }

            foreach ($boundCase in @(
                    @{
                        Path =
                            Join-Path `
                                $TestDrive `
                                'claude-9999999999999999.partial'
                        Length = [long]63
                    },
                    @{
                        Path =
                            Join-Path `
                                $TestDrive `
                                'claude-aaaaaaaaaaaaaaaa.partial'
                        Length = [long](1GB) + 1
                    }
                )) {
                $bound =
                    $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                        Invoke(
                            $source,
                            $TestDrive,
                            $boundCase.Path,
                            $boundCase.Length,
                            [System.Threading.CancellationToken]::None
                        )
                $bound.ErrorCode | Should -BeExactly 'INVALID_INPUT'
                $bound.PartialCreated | Should -BeFalse
                [System.IO.File]::Exists($boundCase.Path) |
                    Should -BeFalse
            }

            $disposed =
                [System.IO.MemoryStream]::new(
                    (New-CddsiD027DownloadWriterTestBytes -Length 64),
                    $false
                )
            $disposed.Dispose()
            $disposedPath =
                Join-Path $TestDrive 'claude-bbbbbbbbbbbbbbbb.partial'
            $disposedResult =
                $script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter.
                    Invoke(
                        $disposed,
                        $TestDrive,
                        $disposedPath,
                        [long]64,
                        [System.Threading.CancellationToken]::None
                    )
            $disposedResult.ErrorCode |
                Should -BeExactly 'INVALID_INPUT'
            $disposedResult.PartialCreated | Should -BeFalse
            [System.IO.File]::Exists($disposedPath) |
                Should -BeFalse
        }
        finally {
            $source.Dispose()
        }
    }

    It 'fixes CreateNew, no-share, bounded hashing and durable-flush semantics' {
        $assignments = @(
            $script:DesktopMsixAst.FindAll(
                {
                    param($node)
                    $node -is
                        [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.Extent.Text -ceq
                        '$script:CddsiD027ClaudeMsixBoundedDownloadBodyWriter'
                },
                $true
            )
        )
        $assignments.Count | Should -Be 1
        $extent = $assignments[0].Right.Extent.Text
        foreach ($required in @(
                'FileMode]::CreateNew',
                'FileAccess]::Write',
                'FileShare]::None',
                'FileOptions]::WriteThrough',
                'ReadAsync',
                'TransformBlock',
                'TransformFinalBlock',
                'Flush($true)',
                'DOWNLOAD_BODY_EXCEEDED_DECLARED_LENGTH',
                'DOWNLOAD_BODY_TRUNCATED'
            )) {
            $extent | Should -Match ([regex]::Escape($required))
        }
        $extent |
            Should -Not -Match (
                'HttpClient|Invoke-WebRequest|Invoke-RestMethod|' +
                'File\s*::\s*Move|Remove-(?:Item|File)|' +
                'Get-(?:FileHash|AuthenticodeSignature)|' +
                'Add-Appx|Start-Process|Registry'
            )
    }
}
