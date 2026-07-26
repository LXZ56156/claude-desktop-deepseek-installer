BeforeAll {
    $script:RepoRoot =
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:DesktopMsixPath =
        Join-Path $script:RepoRoot 'lib\desktop-msix.ps1'
    $script:DesktopMsixSource =
        [System.IO.File]::ReadAllText($script:DesktopMsixPath)
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

    $script:ExpectedHeldIdentityProperties = @(
        'SchemaVersion',
        'ContractVersion',
        'ObservationMethod',
        'Eligible',
        'Status',
        'FinalPathBindingToken',
        'FileSystemName',
        'NumberOfLinks',
        'IsDirectory',
        'IsReparsePoint',
        'VolumeSerialNumberHex',
        'FileIndexHex',
        'ArtifactSizeBytes',
        'FileFactsBindingToken'
    )
    $script:ExpectedCorrelationProperties = @(
        'SchemaVersion',
        'ContractVersion',
        'ObservationMethod',
        'Status',
        'ErrorCode',
        'ExpectedDestinationMatched',
        'PreVerificationHashCompleted',
        'ManifestReadCompleted',
        'SameStateVerificationCompleted',
        'PostVerificationHashCompleted',
        'PreAndPostContentHashMatched',
        'PreAndPostFileFactsMatched',
        'StreamPositionRestored',
        'WinVerifyTrustStatus',
        'StateCloseCompleted',
        'FinalPathBindingToken',
        'ArtifactSha256',
        'ArtifactSizeBytes',
        'HeldFileIdentityObservation',
        'ManifestIdentity',
        'SameStateSignerObservation'
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop

    function New-CddsiD027UnsignedMsixFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Path
        )

        $manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="Claude" Publisher="CN=CDDsi Unsigned Fixture, O=CDDsi Test Only, C=US" Version="1.2.3.4" ProcessorArchitecture="x64" ResourceId="" />
</Package>
'@
        $entries = [ordered]@{
            'AppxManifest.xml' =
                [System.Text.Encoding]::UTF8.GetBytes($manifest)
            'AppxSignature.p7x' =
                [byte[]](0..63 | ForEach-Object { [byte]$_ })
            'AppxBlockMap.xml' =
                [System.Text.Encoding]::UTF8.GetBytes(
                    '<BlockMap xmlns="http://schemas.microsoft.com/appx/2010/blockmap" />'
                )
            '[Content_Types].xml' =
                [System.Text.Encoding]::UTF8.GetBytes(
                    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types" />'
                )
        }

        $fileStream = [System.IO.FileStream]::new(
            $Path,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::None
        )
        $archive = $null
        try {
            $archive = [System.IO.Compression.ZipArchive]::new(
                $fileStream,
                [System.IO.Compression.ZipArchiveMode]::Create,
                $true
            )
            foreach ($name in $entries.Keys) {
                $entry = $archive.CreateEntry(
                    $name,
                    [System.IO.Compression.CompressionLevel]::Optimal
                )
                $entryStream = $null
                try {
                    $entryStream = $entry.Open()
                    $bytes = [byte[]]$entries[$name]
                    $entryStream.Write($bytes, 0, $bytes.Length)
                }
                finally {
                    if ($null -ne $entryStream) {
                        $entryStream.Dispose()
                    }
                }
            }
        }
        finally {
            if ($null -ne $archive) {
                $archive.Dispose()
            }
            $fileStream.Dispose()
        }
    }

    function Assert-CddsiD027CorrelationHasNoRawPath {
        param(
            [Parameter(Mandatory = $true)]$Result,
            [Parameter(Mandatory = $true)][string]$Path
        )

        foreach (
            $text in @(
                $Result.PSObject.Properties |
                    Where-Object { $_.Value -is [string] } |
                    ForEach-Object { [string]$_.Value }
            )
        ) {
            $text.IndexOf(
                $Path,
                [StringComparison]::OrdinalIgnoreCase
            ) | Should -Be -1
        }
        ($Result | ConvertTo-Json -Depth 20 -Compress) |
            Should -Not -Match '(?i)Exception|Stack|TargetSite'
    }
}

Describe 'D-027 Claude MSIX held-handle correlation primitive' {
    It 'keeps the identity observer and correlator private and unconsumed' {
        $script:CddsiD027ClaudeMsixHeldFileIdentityObserver.GetType().
            FullName |
            Should -BeExactly (
                'System.Func`2[[System.IO.FileStream, mscorlib, ' +
                'Version=4.0.0.0, Culture=neutral, ' +
                'PublicKeyToken=b77a5c561934e089],' +
                '[System.Object, mscorlib, Version=4.0.0.0, ' +
                'Culture=neutral, PublicKeyToken=b77a5c561934e089]]'
            )
        $script:CddsiD027ClaudeMsixHeldHandleCorrelator.GetType().
            FullName |
            Should -BeExactly (
                'System.Func`3[[System.IO.FileStream, mscorlib, ' +
                'Version=4.0.0.0, Culture=neutral, ' +
                'PublicKeyToken=b77a5c561934e089],' +
                '[System.String, mscorlib, Version=4.0.0.0, ' +
                'Culture=neutral, PublicKeyToken=b77a5c561934e089],' +
                '[System.Object, mscorlib, Version=4.0.0.0, ' +
                'Culture=neutral, PublicKeyToken=b77a5c561934e089]]'
            )
        @(
            $script:DesktopMsixAst.FindAll(
                {
                    param($node)
                    $node -is
                        [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -cmatch
                        'HeldFileIdentity|HeldHandleCorrelat'
                },
                $true
            )
        ).Count | Should -Be 0
        @(
            Get-Command `
                '*CddsiD027ClaudeMsixHeld*' `
                -CommandType Function `
                -ErrorAction SilentlyContinue
        ).Count | Should -Be 0
        $script:DesktopMsixSource |
            Should -Not -Match (
                'Enable-CddsiD027ClaudeLiveSessionAuthorization|' +
                'Assert-CddsiD027ClaudeLiveContext'
            )
    }

    It 'returns one exact path-free fail-closed schema for null input' {
        $result =
            $script:CddsiD027ClaudeMsixHeldHandleCorrelator.Invoke(
                $null,
                'C:\CDDsi\staging\Claude.msix'
            )

        (@($result.PSObject.Properties.Name) -join ',') |
            Should -BeExactly (
                $script:ExpectedCorrelationProperties -join ','
            )
        $result.SchemaVersion | Should -Be 1
        $result.ContractVersion |
            Should -BeExactly (
                'cddsi-d027-claude-msix-' +
                'held-handle-correlation-v1'
            )
        $result.ObservationMethod |
            Should -BeExactly (
                'CallerHeldReadOnlyFileStreamCorrelation'
            )
        $result.Status | Should -BeExactly 'FAILED'
        $result.ErrorCode | Should -BeExactly 'INVALID_INPUT'
        $result.StreamPositionRestored | Should -BeFalse
        $result.FinalPathBindingToken | Should -BeNullOrEmpty
        $result.ArtifactSha256 | Should -BeNullOrEmpty
        $result.ArtifactSizeBytes | Should -BeNullOrEmpty
        $result.HeldFileIdentityObservation |
            Should -BeNullOrEmpty
        $result.ManifestIdentity | Should -BeNullOrEmpty
        $result.SameStateSignerObservation |
            Should -BeNullOrEmpty
        Assert-CddsiD027CorrelationHasNoRawPath `
            -Result $result `
            -Path 'C:\CDDsi\staging\Claude.msix'
    }

    It 'derives exact NTFS and file identity facts from the caller handle' {
        $path = Join-Path $TestDrive 'held-identity.msix'
        New-CddsiD027UnsignedMsixFixture -Path $path
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Position = 7
            $result =
                $script:CddsiD027ClaudeMsixHeldFileIdentityObserver.
                    Invoke($stream)

            (@($result.PSObject.Properties.Name) -join ',') |
                Should -BeExactly (
                    $script:ExpectedHeldIdentityProperties -join ','
                )
            $result.Eligible | Should -BeTrue
            $result.Status | Should -BeExactly 'Eligible'
            $result.FinalPathBindingToken |
                Should -BeExactly (
                    Get-CddsiPathBindingToken -Path $path
                )
            $result.FileSystemName | Should -BeExactly 'NTFS'
            $result.NumberOfLinks | Should -Be 1
            $result.IsDirectory | Should -BeFalse
            $result.IsReparsePoint | Should -BeFalse
            $result.VolumeSerialNumberHex |
                Should -Match '^[0-9A-F]{8}$'
            $result.FileIndexHex |
                Should -Match '^[0-9A-F]{16}$'
            $result.ArtifactSizeBytes |
                Should -Be $stream.Length
            $result.FileFactsBindingToken |
                Should -Match '^[a-f0-9]{64}$'
            $stream.Position | Should -Be 7
            $stream.SafeFileHandle.IsClosed | Should -BeFalse
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'runs the complete unsigned negative correlation without leaking claims' {
        $path = Join-Path $TestDrive 'unsigned-correlation.msix'
        New-CddsiD027UnsignedMsixFixture -Path $path
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Position = 11
            $competingWrite = $null
            $competingWriteOpened = $false
            try {
                $competingWrite = [System.IO.FileStream]::new(
                    $path,
                    [System.IO.FileMode]::Open,
                    [System.IO.FileAccess]::Write,
                    [System.IO.FileShare]::ReadWrite
                )
                $competingWriteOpened = $true
            }
            catch {
                $competingWriteOpened = $false
            }
            finally {
                if ($null -ne $competingWrite) {
                    $competingWrite.Dispose()
                }
            }
            $competingWriteOpened | Should -BeFalse

            $result =
                $script:CddsiD027ClaudeMsixHeldHandleCorrelator.
                    Invoke($stream, $path)

            $result.Status | Should -BeExactly 'FAILED'
            $result.ErrorCode |
                Should -BeExactly 'MSIX_SIGNATURE_NOT_TRUSTED'
            $result.ExpectedDestinationMatched | Should -BeTrue
            $result.PreVerificationHashCompleted | Should -BeTrue
            $result.ManifestReadCompleted | Should -BeTrue
            $result.SameStateVerificationCompleted |
                Should -BeTrue
            $result.PostVerificationHashCompleted | Should -BeTrue
            $result.PreAndPostContentHashMatched |
                Should -BeTrue
            $result.PreAndPostFileFactsMatched |
                Should -BeTrue
            $result.StreamPositionRestored | Should -BeTrue
            $result.WinVerifyTrustStatus |
                Should -BeIn @(
                    'NoSignature',
                    'UnsupportedSubject',
                    'Untrusted',
                    'PolicyRejected'
                )
            $result.StateCloseCompleted | Should -BeTrue
            $result.FinalPathBindingToken | Should -BeNullOrEmpty
            $result.ArtifactSha256 | Should -BeNullOrEmpty
            $result.ArtifactSizeBytes | Should -BeNullOrEmpty
            $result.HeldFileIdentityObservation |
                Should -BeNullOrEmpty
            $result.ManifestIdentity | Should -BeNullOrEmpty
            $result.SameStateSignerObservation |
                Should -BeNullOrEmpty
            $stream.Position | Should -Be 11
            $stream.CanRead | Should -BeTrue
            $stream.SafeFileHandle.IsClosed | Should -BeFalse
            Assert-CddsiD027CorrelationHasNoRawPath `
                -Result $result `
                -Path $path

            $originalObserver =
                $script:CddsiD027ClaudeMsixSameStateSignerObserver
            $script:CddsiD027ForgedStatus = $path
            try {
                $script:CddsiD027ClaudeMsixSameStateSignerObserver =
                    [System.Func[System.IO.FileStream, object]]{
                        param([System.IO.FileStream]$IgnoredStream)
                        return [pscustomobject][ordered]@{
                            WinVerifyTrustStatus =
                                $script:CddsiD027ForgedStatus
                            StateCloseCompleted = $true
                            WinVerifyTrustNativeStatusHex =
                                '0x00000000'
                            StreamPositionRestored = $true
                            WinVerifyTrustTrusted = $false
                        }
                    }
                $stream.Position = 11
                $forgedResult =
                    $script:CddsiD027ClaudeMsixHeldHandleCorrelator.
                        Invoke($stream, $path)

                $forgedResult.ErrorCode |
                    Should -BeExactly 'MSIX_SIGNATURE_NOT_TRUSTED'
                $forgedResult.WinVerifyTrustStatus |
                    Should -BeExactly 'InvalidObservation'
                $forgedResult.SameStateSignerObservation |
                    Should -BeNullOrEmpty
                $forgedResult.StreamPositionRestored |
                    Should -BeTrue
                $stream.Position | Should -Be 11
                Assert-CddsiD027CorrelationHasNoRawPath `
                    -Result $forgedResult `
                    -Path $path
            }
            finally {
                $script:CddsiD027ClaudeMsixSameStateSignerObserver =
                    $originalObserver
                Remove-Variable `
                    -Name CddsiD027ForgedStatus `
                    -Scope Script `
                    -ErrorAction SilentlyContinue
            }
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'rejects a mismatched destination before hashing or manifest reads' {
        $path = Join-Path $TestDrive 'destination-binding.msix'
        $otherPath = Join-Path $TestDrive 'other.msix'
        New-CddsiD027UnsignedMsixFixture -Path $path
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Position = 5
            $result =
                $script:CddsiD027ClaudeMsixHeldHandleCorrelator.
                    Invoke($stream, $otherPath)

            $result.ErrorCode |
                Should -BeExactly 'DESTINATION_BINDING_MISMATCH'
            $result.ExpectedDestinationMatched | Should -BeFalse
            $result.PreVerificationHashCompleted | Should -BeFalse
            $result.ManifestReadCompleted | Should -BeFalse
            $result.PostVerificationHashCompleted | Should -BeFalse
            $result.StreamPositionRestored | Should -BeTrue
            $result.HeldFileIdentityObservation |
                Should -BeNullOrEmpty
            $stream.Position | Should -Be 5
            $stream.SafeFileHandle.IsClosed | Should -BeFalse
            Assert-CddsiD027CorrelationHasNoRawPath `
                -Result $result `
                -Path $path
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'rejects writable and disposed streams without disposing caller resources' {
        $path = Join-Path $TestDrive 'invalid-stream.msix'
        New-CddsiD027UnsignedMsixFixture -Path $path
        $writable = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::ReadWrite,
            [System.IO.FileShare]::Read
        )
        try {
            $writable.Position = 3
            $writableResult =
                $script:CddsiD027ClaudeMsixHeldHandleCorrelator.
                    Invoke($writable, $path)
            $writableResult.ErrorCode |
                Should -BeExactly 'INVALID_INPUT'
            $writableResult.StreamPositionRestored |
                Should -BeFalse
            $writable.Position | Should -Be 3
            $writable.SafeFileHandle.IsClosed | Should -BeFalse
        }
        finally {
            $writable.Dispose()
        }

        $disposed = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $disposed.Dispose()
        $disposedResult =
            $script:CddsiD027ClaudeMsixHeldHandleCorrelator.
                Invoke($disposed, $path)
        $disposedResult.Status | Should -BeExactly 'FAILED'
        $disposedResult.ErrorCode |
            Should -BeExactly 'INVALID_INPUT'
        $disposedResult.FinalPathBindingToken |
            Should -BeNullOrEmpty
    }

    It 'fails a malformed package after pre-hash and restores the stream' {
        $path = Join-Path $TestDrive 'malformed.msix'
        [System.IO.File]::WriteAllBytes(
            $path,
            [byte[]](0..127 | ForEach-Object { [byte]$_ })
        )
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Position = 9
            $result =
                $script:CddsiD027ClaudeMsixHeldHandleCorrelator.
                    Invoke($stream, $path)

            $result.ErrorCode |
                Should -BeExactly 'MSIX_MANIFEST_INVALID'
            $result.PreVerificationHashCompleted | Should -BeTrue
            $result.ManifestReadCompleted | Should -BeFalse
            $result.SameStateVerificationCompleted |
                Should -BeFalse
            $result.PostVerificationHashCompleted |
                Should -BeFalse
            $result.StreamPositionRestored | Should -BeTrue
            $result.ManifestIdentity | Should -BeNullOrEmpty
            $stream.Position | Should -Be 9
            $stream.SafeFileHandle.IsClosed | Should -BeFalse
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'fixes one same-stream order and forbids path reopen or authority calls' {
        $assignments = @(
            $script:DesktopMsixAst.FindAll(
                {
                    param($node)
                    $node -is
                        [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $node.Left.Extent.Text -ceq
                        '$script:CddsiD027ClaudeMsixHeldHandleCorrelator'
                },
                $true
            )
        )
        $assignments.Count | Should -Be 1
        $extent = $assignments[0].Right.Extent.Text
        $beforeIndex = $extent.IndexOf(
            '$beforeIdentity =',
            [StringComparison]::Ordinal
        )
        $preHashIndex = $extent.IndexOf(
            '$preHash =',
            [StringComparison]::Ordinal
        )
        $manifestIndex = $extent.IndexOf(
            'Read-CddsiD027ClaudeMsixManifest',
            [StringComparison]::Ordinal
        )
        $signerIndex = $extent.IndexOf(
            '$signerObservation =',
            [StringComparison]::Ordinal
        )
        $postHashIndex = $extent.IndexOf(
            '$postHash =',
            [StringComparison]::Ordinal
        )
        $afterIndex = $extent.IndexOf(
            '$afterIdentity =',
            [StringComparison]::Ordinal
        )
        $beforeIndex | Should -BeGreaterThan -1
        $preHashIndex | Should -BeGreaterThan $beforeIndex
        $manifestIndex | Should -BeGreaterThan $preHashIndex
        $signerIndex | Should -BeGreaterThan $manifestIndex
        $postHashIndex | Should -BeGreaterThan $signerIndex
        $afterIndex | Should -BeGreaterThan $postHashIndex
        $extent |
            Should -Not -Match (
                'File\s*::\s*(?:Open|OpenRead)|' +
                'FileStream\s*::\s*new|' +
                'Get-(?:Item|FileHash|AuthenticodeSignature)|' +
                'Resolve-Path|Test-Path|' +
                'Invoke-WebRequest|HttpClient|Start-Process|' +
                'Registry|Install-Cddsi|Enable-Cddsi.*Session'
            )
        $extent |
            Should -Not -Match (
                'New-CddsiD027ClaudeDownloadReceipt|' +
                'Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken|' +
                'Test-CddsiD027ClaudeMsixSignatureEvidenceContract'
            )
        $extent |
            Should -Match 'CALLER_FILE_SHARE_POLICY_UNPROVEN'
        $extent |
            Should -Match 'Test-CddsiExactPropertySet'
        foreach (
            $trustedInvariant in @(
                'CallerFileHandleSupplied',
                'FinalPathStableAcrossVerification',
                'FileFactsStableAcrossVerification',
                'ProviderOpenedFile',
                'PrimarySignerCount',
                'SecondarySignatureCount',
                'WinVerifyTrustNativeStatusHex',
                'StateCloseNativeStatusHex',
                'PrimarySignerCertificateDerBytes'
            )
        ) {
            $extent | Should -Match $trustedInvariant
        }
        $extent |
            Should -Not -Match (
                '\$result\.Status\s*=\s*' +
                "'(?:CORRELATED|SUCCEEDED|OBSERVATIONS_MATCHED)'"
            )
        $script:DesktopMsixSource |
            Should -Match 'GetVolumeInformationByHandleW'
        $script:DesktopMsixSource |
            Should -Match (
                'volumeSerialNumber\s*!=\s*' +
                'facts\.VolumeSerialNumber'
            )
        $script:DesktopMsixSource |
            Should -Match 'FileFactsBindingToken'
    }
}
