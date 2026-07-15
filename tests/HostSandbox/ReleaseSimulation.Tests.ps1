BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:BuilderPath = Join-Path $script:RepoRoot 'scripts\build-release.ps1'
    . $script:BuilderPath -ImportOnly

    function Write-CddsiReleaseFixtureText {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
        )

        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [System.IO.File]::WriteAllText($Path, $Content, (New-Object System.Text.UTF8Encoding($false)))
    }

    function Write-CddsiReleaseFixtureBytes {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
        )

        [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
        [System.IO.File]::WriteAllBytes($Path, $Bytes)
    }

    function Write-CddsiReleaseFixtureManifest {
        param(
            [Parameter(Mandatory = $true)][string]$Path,
            [Parameter(Mandatory = $true)][string[]]$PackageFiles,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$DevelopmentOnlyFiles
        )

        $lines = New-Object System.Collections.Generic.List[string]
        $lines.Add('@{')
        $lines.Add('    SchemaVersion = 1')
        $lines.Add('    PackageFiles = @(')
        foreach ($entry in $PackageFiles) {
            $lines.Add("        '$($entry.Replace("'", "''"))'")
        }
        $lines.Add('    )')
        $lines.Add('    DevelopmentOnlyFiles = @(')
        foreach ($entry in $DevelopmentOnlyFiles) {
            $lines.Add("        '$($entry.Replace("'", "''"))'")
        }
        $lines.Add('    )')
        $lines.Add('}')
        Write-CddsiReleaseFixtureText -Path $Path -Content (($lines -join "`r`n") + "`r`n")
    }

    function New-CddsiReleaseFixtureRepository {
        param([Parameter(Mandatory = $true)][string]$Root)

        [void][System.IO.Directory]::CreateDirectory($Root)
        $manifestPath = Join-Path $Root 'scripts\release-manifest.psd1'
        Write-CddsiReleaseFixtureText -Path (Join-Path $Root 'README.md') -Content "safe release text`r`n"
        Write-CddsiReleaseFixtureText -Path (Join-Path $Root 'config\defaults.json') -Content '{"mode":"safe"}'
        $developmentCanary = 'sk-' + ('d' * 32 -join '')
        Write-CddsiReleaseFixtureText -Path (Join-Path $Root 'dev-only.txt') -Content $developmentCanary
        Write-CddsiReleaseFixtureManifest `
            -Path $manifestPath `
            -PackageFiles @('README.md', 'config/defaults.json') `
            -DevelopmentOnlyFiles @('dev-only.txt', 'scripts/release-manifest.psd1')
        return [pscustomobject]@{
            Root         = $Root
            ManifestPath = $manifestPath
            PackageFiles = @('README.md', 'config/defaults.json')
        }
    }

    function Get-CddsiReleaseFixtureFingerprint {
        param([Parameter(Mandatory = $true)][string]$Root)

        $rootFull = [System.IO.Path]::GetFullPath($Root).TrimEnd('\')
        $entries = New-Object System.Collections.Generic.List[string]
        foreach ($path in @([System.IO.Directory]::EnumerateFiles($rootFull, '*', [System.IO.SearchOption]::AllDirectories))) {
            $relative = [System.IO.Path]::GetFullPath($path).Substring($rootFull.Length).TrimStart([char[]]'\/').Replace('\', '/')
            $sha = [System.Security.Cryptography.SHA256]::Create()
            $stream = [System.IO.File]::Open($path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
            try {
                $hash = ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
            }
            finally {
                $stream.Dispose()
                $sha.Dispose()
            }
            $entries.Add($relative + '=' + $hash)
        }
        return @($entries | Sort-Object)
    }

    function Get-CddsiReleaseFixtureSandboxRoots {
        param([Parameter(Mandatory = $true)][string]$TempBase)

        return @(
            [System.IO.Directory]::EnumerateDirectories($TempBase, 'cddsi-test-*', [System.IO.SearchOption]::TopDirectoryOnly) |
                ForEach-Object { [System.IO.Path]::GetFullPath($_) } |
                Sort-Object
        )
    }

    function Add-CddsiReleaseFixtureZipEntry {
        param(
            [Parameter(Mandatory = $true)][string]$ZipPath,
            [Parameter(Mandatory = $true)][string]$EntryName,
            [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content
        )

        Initialize-CddsiReleaseCompression
        $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $archive = $null
        try {
            $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
            $entry = $archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $bytes = [System.Text.Encoding]::UTF8.GetBytes($Content)
                $entryStream.Write($bytes, 0, $bytes.Length)
            }
            finally {
                $entryStream.Dispose()
            }
        }
        finally {
            if ($null -ne $archive) { $archive.Dispose() }
            $stream.Dispose()
        }
    }

    function Set-CddsiReleaseFixtureZipEntryBytes {
        param(
            [Parameter(Mandatory = $true)][string]$ZipPath,
            [Parameter(Mandatory = $true)][string]$EntryName,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
        )

        Initialize-CddsiReleaseCompression
        $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::ReadWrite, [System.IO.FileShare]::None)
        $archive = $null
        try {
            $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Update, $false)
            $existing = $archive.GetEntry($EntryName)
            if ($null -eq $existing) { throw 'Fixture ZIP entry is missing.' }
            $existing.Delete()
            $entry = $archive.CreateEntry($EntryName, [System.IO.Compression.CompressionLevel]::Optimal)
            $entryStream = $entry.Open()
            try {
                $entryStream.Write($Bytes, 0, $Bytes.Length)
            }
            finally {
                $entryStream.Dispose()
            }
        }
        finally {
            if ($null -ne $archive) { $archive.Dispose() }
            $stream.Dispose()
        }
    }

    function New-CddsiReleaseFixtureCrossChunkSecretBytes {
        param([Parameter(Mandatory = $true)][string]$Secret)

        $secretBytes = [System.Text.Encoding]::ASCII.GetBytes($Secret)
        $secretOffset = $script:CddsiReleaseSecretScanChunkBytes - 3
        $bytes = New-Object byte[] ($secretOffset + $secretBytes.Length + 8)
        $bytes[0] = 0x89
        $bytes[1] = 0x50
        $bytes[2] = 0x4E
        $bytes[3] = 0x47
        [Array]::Copy($secretBytes, 0, $bytes, $secretOffset, $secretBytes.Length)
        return ,$bytes
    }

    function New-CddsiReleaseFixtureLedger {
        param(
            [Parameter(Mandatory = $true)][string]$RunId,
            [Parameter(Mandatory = $true)][object[]]$Contract
        )

        $ledger = New-Object System.Collections.Generic.List[object]
        foreach ($entry in $Contract) {
            $data = if ($null -eq $entry.Data) {
                $null
            }
            else {
                $copy = [ordered]@{}
                foreach ($property in @($entry.Data.PSObject.Properties)) {
                    $copy[$property.Name] = $property.Value
                }
                [pscustomobject]$copy
            }
            Add-CddsiHarnessLedgerEntry `
                -Ledger $ledger `
                -RunId $RunId `
                -Category FileSystem `
                -RuleId $entry.RuleId `
                -ResourceToken $entry.ResourceToken `
                -Outcome Succeeded `
                -Data $data
        }
        return ,$ledger
    }
}

Describe 'P1 DryRun Release Simulation' {
    It 'imports only the sandbox helper and contains no Git, network, product-entry, or Live publication path' {
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($script:BuilderPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $commands = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true))
        $commandNames = @($commands | ForEach-Object { $_.GetCommandName() } | Where-Object { $_ } | Sort-Object -Unique)
        foreach ($forbidden in @(
            'git', 'git.exe', 'Invoke-WebRequest', 'Invoke-RestMethod', 'Start-BitsTransfer',
            'Start-Process', 'Start-Here.ps1', 'Initialize-CddsiScript'
        )) {
            $commandNames | Should -Not -Contain $forbidden
        }
        $dynamicInvocations = @($commands | Where-Object {
            $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Ampersand -or
                $_.InvocationOperator -eq [System.Management.Automation.Language.TokenKind]::Dot
        })
        $dynamicInvocations.Count | Should -Be 1
        $dynamicInvocations[0].Extent.Text | Should -Match 'invoke-host-sandbox\.ps1'
        $dynamicInvocations[0].Extent.Text | Should -Match '-ImportOnly'

        $variables = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.VariableExpressionAst]
        }, $true) | ForEach-Object { $_.VariablePath.UserPath })
        @($variables | Where-Object { $_ -match '^env:' }).Count | Should -Be 0
        $content = [System.IO.File]::ReadAllText($script:BuilderPath)
        $content | Should -Match 'if \(\$entryImportOnly\)'
        $content | Should -Match 'if \(-not \$entryDryRun\)'
        $content | Should -Match 'P1 release publication is fail closed'
        $content | Should -Match ([regex]::Escape("'发布 仿真 &!()'"))
        $content | Should -Match 'function Write-CddsiReleaseZipUInt16'
        $content | Should -Match 'function Write-CddsiReleaseZipUInt32'
        $content | Should -Match 'EDB88320'
        $content | Should -Match '04034B50'
        $content | Should -Match '02014B50'
        $content | Should -Match '06054B50'
        $content | Should -Match '65535 is reserved as a ZIP64 sentinel'
        $content | Should -Not -Match 'CompressionLevel\]::NoCompression'
    }

    It 'copies only PackageFiles, leaves the source unchanged, and cleans every sandbox artifact' {
        $fixture = New-CddsiReleaseFixtureRepository -Root (Join-Path $TestDrive 'source-success')
        $beforeFingerprint = @(Get-CddsiReleaseFixtureFingerprint -Root $fixture.Root)
        $beforeSandboxes = @(Get-CddsiReleaseFixtureSandboxRoots -TempBase $TestDrive)

        $result = Invoke-CddsiReleaseSimulation `
            -RepositoryRoot $fixture.Root `
            -ManifestPath $fixture.ManifestPath `
            -TempBase $TestDrive

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Mode | Should -BeExactly 'DryRun'
        $result.Changed | Should -BeFalse
        $result.PackageFileCount | Should -Be 2
        $result.SourceSecretFindings | Should -Be 0
        $result.StagingSecretFindings | Should -Be 0
        $result.ZipSecretFindings | Should -Be 0
        $result.ZipEntryCount | Should -Be 2
        $result.ZipInventoryExact | Should -BeTrue
        $result.ZipDeterministic | Should -BeTrue
        $result.ZipEntryOrder | Should -BeExactly 'Ordinal'
        $result.ZipEntryTimestampUtc | Should -BeExactly '1980-01-01T00:00:00Z'
        $result.ZipCompression | Should -BeExactly 'Store'
        $result.ExtractSecretFindings | Should -Be 0
        $result.ExtractFileCount | Should -Be 2
        $result.ExtractInventoryExact | Should -BeTrue
        $result.ContentHashesExact | Should -BeTrue
        $result.SpecialPathValidated | Should -BeTrue
        $result.TrustedHarnessProcessCount | Should -Be 0
        $result.TrustedHarnessNetworkCount | Should -Be 0
        $result.RepositoryFileCount | Should -BeGreaterThan 0
        $result.RepositoryDirectoryCount | Should -BeGreaterThan 0
        $result.TrustedHarnessFileSystemCount | Should -Be 16
        $result.HarnessLedgerExact | Should -BeTrue
        $result.SourcePackageChanged | Should -BeFalse
        $result.LIVE_PROVIDER_LOADED | Should -BeFalse
        $result.FORBIDDEN_RESOURCE_ACCESS_COUNT | Should -Be 0
        $result.OUTSIDE_SANDBOX_WRITE_COUNT | Should -Be 0
        $result.PRODUCT_LIVE_PROCESS_SPAWN_COUNT | Should -Be 0
        $result.PRODUCT_NETWORK_REQUEST_COUNT | Should -Be 0
        $result.REAL_REGISTRY_ACCESS_COUNT | Should -Be 0
        $result.UNAPPROVED_HARNESS_PROCESS_COUNT | Should -Be 0
        $result.UNAPPROVED_HARNESS_NETWORK_COUNT | Should -Be 0
        $result.SECRET_FINDINGS | Should -Be 0
        $result.UNEXPECTED_LEDGER_ENTRY_COUNT | Should -Be 0
        $result.REPOSITORY_CONTENT_CHANGED | Should -BeFalse
        $result.CleanupOutcome | Should -BeExactly 'Succeeded'
        (@(Get-CddsiReleaseFixtureFingerprint -Root $fixture.Root) -join "`n") |
            Should -BeExactly ($beforeFingerprint -join "`n")
        (@(Get-CddsiReleaseFixtureSandboxRoots -TempBase $TestDrive) -join "`n") |
            Should -BeExactly ($beforeSandboxes -join "`n")
        (Test-Path -LiteralPath (Join-Path $fixture.Root 'release-simulation.zip')) | Should -BeFalse
    }

    It 'creates byte-identical ZIPs with ordinal entries and fixed metadata' {
        $stagingRoot = Join-Path $TestDrive 'deterministic-staging'
        Write-CddsiReleaseFixtureText -Path (Join-Path $stagingRoot 'zeta.txt') -Content 'zeta'
        Write-CddsiReleaseFixtureText -Path (Join-Path $stagingRoot 'alpha.txt') -Content 'alpha'
        Write-CddsiReleaseFixtureText -Path (Join-Path $stagingRoot '目录\中文.txt') -Content 'safe'
        Write-CddsiReleaseFixtureText -Path (Join-Path $stagingRoot 'empty.txt') -Content ''
        Write-CddsiReleaseFixtureBytes -Path (Join-Path $stagingRoot 'nested\binary.bin') `
            -Bytes ([byte[]]@(0x00, 0x01, 0x02, 0x7F, 0x80, 0xFF))
        $packageFiles = @('zeta.txt', 'nested/binary.bin', '目录/中文.txt', 'empty.txt', 'alpha.txt')
        $zipOne = Join-Path $TestDrive 'candidate-one.zip'
        $zipTwo = Join-Path $TestDrive 'candidate-two.zip'

        New-CddsiReleaseSimulationZip -StagingRoot $stagingRoot -ZipPath $zipOne `
            -PackageFiles $packageFiles -SandboxRoot $TestDrive
        New-CddsiReleaseSimulationZip -StagingRoot $stagingRoot -ZipPath $zipTwo `
            -PackageFiles $packageFiles -SandboxRoot $TestDrive

        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $streamOne = [System.IO.File]::OpenRead($zipOne)
            try { $hashOne = ([BitConverter]::ToString($sha.ComputeHash($streamOne))).Replace('-', '').ToLowerInvariant() }
            finally { $streamOne.Dispose() }
            $sha.Initialize()
            $streamTwo = [System.IO.File]::OpenRead($zipTwo)
            try { $hashTwo = ([BitConverter]::ToString($sha.ComputeHash($streamTwo))).Replace('-', '').ToLowerInvariant() }
            finally { $streamTwo.Dispose() }
        }
        finally {
            $sha.Dispose()
        }
        $hashTwo | Should -BeExactly $hashOne

        $rawStream = [System.IO.File]::OpenRead($zipOne)
        $rawReader = $null
        try {
            $rawReader = [System.IO.BinaryReader]::new(
                $rawStream,
                [System.Text.UTF8Encoding]::new($false, $true),
                $false
            )
            $expectedNames = @('alpha.txt', 'empty.txt', 'nested/binary.bin', 'zeta.txt', '目录/中文.txt')
            for ($entryIndex = 0; $entryIndex -lt $expectedNames.Count; $entryIndex++) {
                $rawReader.ReadUInt32() | Should -Be ([Convert]::ToUInt32('04034B50', 16))
                $rawReader.ReadUInt16() | Should -Be 20
                $rawReader.ReadUInt16() | Should -Be 0x0800
                $rawReader.ReadUInt16() | Should -Be 0
                $rawReader.ReadUInt16() | Should -Be 0
                $rawReader.ReadUInt16() | Should -Be 0x0021
                $entryCrc32 = $rawReader.ReadUInt32()
                $compressedSize = $rawReader.ReadUInt32()
                $uncompressedSize = $rawReader.ReadUInt32()
                $nameLength = $rawReader.ReadUInt16()
                $extraLength = $rawReader.ReadUInt16()
                $entryName = [System.Text.Encoding]::UTF8.GetString($rawReader.ReadBytes($nameLength))
                $entryName | Should -BeExactly $expectedNames[$entryIndex]
                $extraLength | Should -Be 0
                $compressedSize | Should -Be $uncompressedSize
                if ($entryName -ceq 'alpha.txt') {
                    $entryCrc32 | Should -Be ([Convert]::ToUInt32('D0E0396A', 16))
                }
                elseif ($entryName -ceq 'empty.txt') {
                    $entryCrc32 | Should -Be 0
                }
                $rawReader.ReadBytes([int]$compressedSize).Count | Should -Be ([int]$compressedSize)
            }
            $rawReader.ReadUInt32() | Should -Be ([Convert]::ToUInt32('02014B50', 16))
            [void]$rawReader.BaseStream.Seek(-22, [System.IO.SeekOrigin]::End)
            $rawReader.ReadUInt32() | Should -Be ([Convert]::ToUInt32('06054B50', 16))
            $rawReader.ReadUInt16() | Should -Be 0
            $rawReader.ReadUInt16() | Should -Be 0
            $rawReader.ReadUInt16() | Should -Be 5
            $rawReader.ReadUInt16() | Should -Be 5
            $centralDirectorySize = $rawReader.ReadUInt32()
            $centralDirectoryOffset = $rawReader.ReadUInt32()
            $rawReader.ReadUInt16() | Should -Be 0
            $centralDirectorySize | Should -BeGreaterThan 0
            $centralDirectoryOffset | Should -BeGreaterThan 0
            ([long]$centralDirectoryOffset + [long]$centralDirectorySize + 22) |
                Should -Be $rawReader.BaseStream.Length
        }
        finally {
            if ($null -ne $rawReader) { $rawReader.Dispose() }
            else { $rawStream.Dispose() }
        }

        Initialize-CddsiReleaseCompression
        $stream = [System.IO.File]::OpenRead($zipOne)
        $archive = $null
        try {
            $archive = [System.IO.Compression.ZipArchive]::new(
                $stream,
                [System.IO.Compression.ZipArchiveMode]::Read,
                $false
            )
            $entries = [System.Collections.Generic.List[object]]::new()
            foreach ($archiveEntry in $archive.Entries) {
                [void]$entries.Add($archiveEntry)
            }
            $entries.Count | Should -Be 5
            (@($entries | ForEach-Object FullName) -join "`n") |
                Should -BeExactly (@('alpha.txt', 'empty.txt', 'nested/binary.bin', 'zeta.txt', '目录/中文.txt') -join "`n")
            foreach ($entry in $entries) {
                # ZIP stores a DOS wall-clock value without an offset. Interpret that
                # deterministic field as UTC instead of applying the host time zone.
                $canonicalTimestampUtc = [DateTimeOffset]::new(
                    $entry.LastWriteTime.Year,
                    $entry.LastWriteTime.Month,
                    $entry.LastWriteTime.Day,
                    $entry.LastWriteTime.Hour,
                    $entry.LastWriteTime.Minute,
                    $entry.LastWriteTime.Second,
                    [TimeSpan]::Zero
                )
                $canonicalTimestampUtc.ToString('yyyy-MM-ddTHH:mm:ssZ') |
                    Should -BeExactly '1980-01-01T00:00:00Z'
                $entry.CompressedLength | Should -Be $entry.Length
                $entry.ExternalAttributes | Should -Be 0
            }
        }
        finally {
            if ($null -ne $archive) { $archive.Dispose() }
            $stream.Dispose()
        }

        $partialZip = Join-Path $TestDrive 'candidate-partial.zip'
        {
            New-CddsiReleaseSimulationZip -StagingRoot $stagingRoot -ZipPath $partialZip `
                -PackageFiles @('alpha.txt', 'zz-missing.txt') -SandboxRoot $TestDrive
        } | Should -Throw
        Test-Path -LiteralPath $partialZip | Should -BeFalse

        $tooManyEntries = [System.Array]::CreateInstance([string], 65535)
        $tooManyZip = Join-Path $TestDrive 'candidate-zip64-sentinel.zip'
        {
            New-CddsiReleaseSimulationZip -StagingRoot $stagingRoot -ZipPath $tooManyZip `
                -PackageFiles $tooManyEntries -SandboxRoot $TestDrive
        } | Should -Throw
        Test-Path -LiteralPath $tooManyZip | Should -BeFalse
    }

    It 'rejects manifest and temporary-root path escapes before touching an outside file' {
        $fixture = New-CddsiReleaseFixtureRepository -Root (Join-Path $TestDrive 'source-escape')
        $outsidePath = Join-Path $TestDrive 'outside.txt'
        Write-CddsiReleaseFixtureText -Path $outsidePath -Content 'outside-canary'
        Write-CddsiReleaseFixtureManifest `
            -Path $fixture.ManifestPath `
            -PackageFiles @('../outside.txt') `
            -DevelopmentOnlyFiles @('scripts/release-manifest.psd1')

        {
            Invoke-CddsiReleaseSimulation `
                -RepositoryRoot $fixture.Root `
                -ManifestPath $fixture.ManifestPath `
                -TempBase $TestDrive
        } | Should -Throw
        [System.IO.File]::ReadAllText($outsidePath) | Should -BeExactly 'outside-canary'

        Write-CddsiReleaseFixtureManifest `
            -Path $fixture.ManifestPath `
            -PackageFiles $fixture.PackageFiles `
            -DevelopmentOnlyFiles @('dev-only.txt', 'scripts/release-manifest.psd1')
        {
            Invoke-CddsiReleaseSimulation `
                -RepositoryRoot $fixture.Root `
                -ManifestPath $fixture.ManifestPath `
                -TempBase $fixture.Root
        } | Should -Throw
        @(Get-CddsiReleaseFixtureSandboxRoots -TempBase $fixture.Root).Count | Should -Be 0
    }

    It 'fails closed on release manifest schema, overlap, and missing-file drift' {
        $fixture = New-CddsiReleaseFixtureRepository -Root (Join-Path $TestDrive 'source-manifest-drift')
        $invalidSchema = @"
@{
    SchemaVersion = 1
    PackageFiles = @('README.md')
    DevelopmentOnlyFiles = @('scripts/release-manifest.psd1')
    Unexpected = @()
}
"@
        Write-CddsiReleaseFixtureText -Path $fixture.ManifestPath -Content $invalidSchema
        {
            Invoke-CddsiReleaseSimulation -RepositoryRoot $fixture.Root -ManifestPath $fixture.ManifestPath -TempBase $TestDrive
        } | Should -Throw

        Write-CddsiReleaseFixtureManifest `
            -Path $fixture.ManifestPath `
            -PackageFiles @('README.md') `
            -DevelopmentOnlyFiles @('README.md', 'scripts/release-manifest.psd1')
        {
            Invoke-CddsiReleaseSimulation -RepositoryRoot $fixture.Root -ManifestPath $fixture.ManifestPath -TempBase $TestDrive
        } | Should -Throw

        Write-CddsiReleaseFixtureManifest `
            -Path $fixture.ManifestPath `
            -PackageFiles @('missing.txt') `
            -DevelopmentOnlyFiles @('scripts/release-manifest.psd1')
        {
            Invoke-CddsiReleaseSimulation -RepositoryRoot $fixture.Root -ManifestPath $fixture.ManifestPath -TempBase $TestDrive
        } | Should -Throw
        @(Get-CddsiReleaseFixtureSandboxRoots -TempBase $TestDrive).Count | Should -Be 0
    }

    It 'rejects secrets independently at source, staging, and ZIP layers without disclosing the value' {
        $fixture = New-CddsiReleaseFixtureRepository -Root (Join-Path $TestDrive 'source-secret')
        $secret = 'sk-' + ('s' * 32 -join '')
        Write-CddsiReleaseFixtureText -Path (Join-Path $fixture.Root 'README.md') -Content $secret
        $sourceError = $null
        try {
            Invoke-CddsiReleaseSimulation -RepositoryRoot $fixture.Root -ManifestPath $fixture.ManifestPath -TempBase $TestDrive
        }
        catch {
            $sourceError = $_
        }
        $sourceError | Should -Not -BeNullOrEmpty
        $sourceError.Exception.Message | Should -BeExactly 'Release simulation failed; inspect CddsiReleaseFailure evidence.'
        $sourceEnvelope = $sourceError.Exception.Data['CddsiReleaseFailure']
        $sourceEnvelope.PrimaryError | Should -Match 'Source secret scan failed'
        $sourceError.Exception.Message | Should -Not -Match [regex]::Escape($secret)
        $sourceEnvelope.PrimaryError | Should -Not -Match [regex]::Escape($secret)
        @(Get-CddsiReleaseFixtureSandboxRoots -TempBase $TestDrive).Count | Should -Be 0

        $ledger = New-Object System.Collections.Generic.List[object]
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId ([guid]::NewGuid().ToString('D')) -Ledger $ledger
        try {
            $stagingRoot = Join-Path $sandbox.Root 'secret-layers\staging'
            $secretPath = Join-Path $stagingRoot 'secret.txt'
            Write-CddsiReleaseFixtureText -Path $secretPath -Content $secret
            $item = [pscustomobject]@{ RelativePath = 'secret.txt'; FullPath = $secretPath }
            $stagingError = $null
            try {
                Invoke-CddsiReleaseFileSecretScan -Items @($item) -Layer Staging
            }
            catch {
                $stagingError = $_
            }
            $stagingError | Should -Not -BeNullOrEmpty
            $stagingError.Exception.Message | Should -Match 'Staging secret scan failed'
            $stagingError.Exception.Message | Should -Not -Match [regex]::Escape($secret)

            $zipPath = Join-Path $sandbox.Root 'secret-layers\secret.zip'
            New-CddsiReleaseSimulationZip `
                -StagingRoot $stagingRoot `
                -ZipPath $zipPath `
                -PackageFiles @('secret.txt') `
                -SandboxRoot $sandbox.Root
            $zipError = $null
            try {
                Test-CddsiReleaseZipLayer -ZipPath $zipPath -PackageFiles @('secret.txt') -SandboxRoot $sandbox.Root
            }
            catch {
                $zipError = $_
            }
            $zipError | Should -Not -BeNullOrEmpty
            $zipError.Exception.Message | Should -Match 'ZIP secret scan failed'
            $zipError.Exception.Message | Should -Not -Match [regex]::Escape($secret)
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
        (Test-Path -LiteralPath $sandbox.Root) | Should -BeFalse
    }

    It 'rejects zip-slip, absolute, duplicate, and Windows-alias entries during validation and extraction' {
        $ledger = New-Object System.Collections.Generic.List[object]
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId ([guid]::NewGuid().ToString('D')) -Ledger $ledger
        try {
            $stagingRoot = Join-Path $sandbox.Root 'zip-attacks\staging'
            Write-CddsiReleaseFixtureText -Path (Join-Path $stagingRoot 'safe.txt') -Content 'safe'
            $cases = @(
                [pscustomobject]@{ Name = 'zip-slip'; EntryName = '../escape.txt' }
                [pscustomobject]@{ Name = 'absolute'; EntryName = '/absolute.txt' }
                [pscustomobject]@{ Name = 'duplicate'; EntryName = 'safe.txt' }
                [pscustomobject]@{ Name = 'windows-alias'; EntryName = 'safe.txt.' }
            )
            for ($index = 0; $index -lt $cases.Count; $index++) {
                $case = $cases[$index]
                $zipPath = Join-Path $sandbox.Root ("zip-attacks\attack-{0}.zip" -f $index)
                New-CddsiReleaseSimulationZip `
                    -StagingRoot $stagingRoot `
                    -ZipPath $zipPath `
                    -PackageFiles @('safe.txt') `
                    -SandboxRoot $sandbox.Root
                Add-CddsiReleaseFixtureZipEntry -ZipPath $zipPath -EntryName $case.EntryName -Content 'attack-canary'

                {
                    Test-CddsiReleaseZipLayer -ZipPath $zipPath -PackageFiles @('safe.txt') -SandboxRoot $sandbox.Root
                } | Should -Throw

                $extractionRoot = Join-Path $sandbox.Root ("zip-attacks\extract-{0}" -f $index)
                {
                    Expand-CddsiReleaseSimulationZip -ZipPath $zipPath -ExtractionRoot $extractionRoot -SandboxRoot $sandbox.Root
                } | Should -Throw
            }
            (Test-Path -LiteralPath (Join-Path $sandbox.Root 'zip-attacks\escape.txt')) | Should -BeFalse
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
        (Test-Path -LiteralPath $sandbox.Root) | Should -BeFalse
    }

    It 'detects binary content drift even when ZIP and extracted entry names remain exact' {
        $ledger = New-Object System.Collections.Generic.List[object]
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId ([guid]::NewGuid().ToString('D')) -Ledger $ledger
        try {
            $stagingRoot = Join-Path $sandbox.Root 'binary-drift\staging'
            $binaryPath = Join-Path $stagingRoot 'asset.png'
            Write-CddsiReleaseFixtureBytes -Path $binaryPath -Bytes ([byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x01, 0x02, 0x03))
            $stagedItem = [pscustomobject]@{ RelativePath = 'asset.png'; FullPath = $binaryPath }
            $expectedHashes = Get-CddsiReleaseContentHashes -Items @($stagedItem)

            $zipPath = Join-Path $sandbox.Root 'binary-drift\release.zip'
            New-CddsiReleaseSimulationZip `
                -StagingRoot $stagingRoot `
                -ZipPath $zipPath `
                -PackageFiles @('asset.png') `
                -SandboxRoot $sandbox.Root
            Set-CddsiReleaseFixtureZipEntryBytes -ZipPath $zipPath -EntryName 'asset.png' -Bytes ([byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x09, 0x09, 0x09))

            $zipEvidence = Test-CddsiReleaseZipLayer -ZipPath $zipPath -PackageFiles @('asset.png') -SandboxRoot $sandbox.Root
            $zipEvidence.InventoryExact | Should -BeTrue
            {
                Assert-CddsiReleaseContentHashesEqual -Expected $expectedHashes -Actual $zipEvidence.ContentHashes -Label 'Binary ZIP drift'
            } | Should -Throw

            $extractionRoot = Join-Path $sandbox.Root 'binary-drift\extracted'
            Expand-CddsiReleaseSimulationZip -ZipPath $zipPath -ExtractionRoot $extractionRoot -SandboxRoot $sandbox.Root
            $extractedItems = @(Get-CddsiReleaseTreeItems -TreeRoot $extractionRoot -SandboxRoot $sandbox.Root)
            @($extractedItems).Count | Should -Be 1
            $extractedHashes = Get-CddsiReleaseContentHashes -Items $extractedItems
            {
                Assert-CddsiReleaseContentHashesEqual -Expected $expectedHashes -Actual $extractedHashes -Label 'Binary extracted drift'
            } | Should -Throw
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
        (Test-Path -LiteralPath $sandbox.Root) | Should -BeFalse
    }

    It 'rejects ZIP inventory drift and removes only the owner-validated sandbox' {
        $ledger = New-Object System.Collections.Generic.List[object]
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId ([guid]::NewGuid().ToString('D')) -Ledger $ledger
        $sibling = Join-Path $TestDrive 'zip-drift-sibling'
        Write-CddsiReleaseFixtureText -Path (Join-Path $sibling 'keep.txt') -Content 'keep'
        try {
            $stagingRoot = Join-Path $sandbox.Root 'zip-drift\staging'
            Write-CddsiReleaseFixtureText -Path (Join-Path $stagingRoot 'safe.txt') -Content 'safe'
            $zipPath = Join-Path $sandbox.Root 'zip-drift\release.zip'
            New-CddsiReleaseSimulationZip `
                -StagingRoot $stagingRoot `
                -ZipPath $zipPath `
                -PackageFiles @('safe.txt') `
                -SandboxRoot $sandbox.Root
            Add-CddsiReleaseFixtureZipEntry -ZipPath $zipPath -EntryName 'unexpected.txt' -Content 'unexpected'

            {
                Test-CddsiReleaseZipLayer -ZipPath $zipPath -PackageFiles @('safe.txt') -SandboxRoot $sandbox.Root
            } | Should -Throw
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }

        (Test-Path -LiteralPath $sandbox.Root) | Should -BeFalse
        [System.IO.File]::ReadAllText((Join-Path $sibling 'keep.txt')) | Should -BeExactly 'keep'
        @($ledger | Where-Object RuleId -eq 'CleanupSandbox').Count | Should -Be 1
    }

    It 'rejects every Windows device alias including multi-extension, spaced, console, and superscript forms' {
        foreach ($unsafe in @(
            'CONIN$', 'CONOUT$.txt', 'CON.foo.bar', 'CON .txt',
            ('COM' + [char]0x00B9 + '.log'), ('COM' + [char]0x00B2), ('COM' + [char]0x00B3 + '.bin'),
            ('LPT' + [char]0x00B9 + '.log'), ('LPT' + [char]0x00B2), ('LPT' + [char]0x00B3 + '.bin')
        )) {
            { ConvertTo-CddsiReleaseRelativePath -Path $unsafe } | Should -Throw
        }
        ConvertTo-CddsiReleaseRelativePath -Path 'console.txt' | Should -BeExactly 'console.txt'
        ConvertTo-CddsiReleaseRelativePath -Path 'COM10.txt' | Should -BeExactly 'COM10.txt'
    }

    It 'streams every binary layer with overlap and rejects a cross-chunk secret without disclosing it' {
        $ledger = New-Object System.Collections.Generic.List[object]
        $sandbox = New-CddsiOwnedSandbox -TempBase $TestDrive -RunId ([guid]::NewGuid().ToString('D')) -Ledger $ledger
        $secret = 'sk-' + ('x' * 40 -join '')
        try {
            $stagingRoot = Join-Path $sandbox.Root 'binary-secret\staging'
            $safePath = Join-Path $stagingRoot 'safe.png'
            $secretPath = Join-Path $stagingRoot 'secret.png'
            Write-CddsiReleaseFixtureBytes -Path $safePath -Bytes ([byte[]]@(0x89, 0x50, 0x4E, 0x47, 0x00, 0xFF, 0x01))
            Write-CddsiReleaseFixtureBytes -Path $secretPath -Bytes (New-CddsiReleaseFixtureCrossChunkSecretBytes -Secret $secret)
            $safeItem = [pscustomobject]@{ RelativePath = 'safe.png'; FullPath = $safePath }
            $secretItem = [pscustomobject]@{ RelativePath = 'secret.png'; FullPath = $secretPath }

            foreach ($layer in @('Source', 'Staging', 'Extracted')) {
                (Invoke-CddsiReleaseFileSecretScan -Items @($safeItem) -Layer $layer) | Should -Be 0
                $layerError = $null
                try {
                    $null = Invoke-CddsiReleaseFileSecretScan -Items @($secretItem) -Layer $layer
                }
                catch {
                    $layerError = $_
                }
                $layerError | Should -Not -BeNullOrEmpty
                $layerError.Exception.Message | Should -Match ($layer + ' secret scan failed')
                $layerError.Exception.Message | Should -Not -Match ([regex]::Escape($secret))
            }

            $safeZip = Join-Path $sandbox.Root 'binary-secret\safe.zip'
            New-CddsiReleaseSimulationZip `
                -StagingRoot $stagingRoot `
                -ZipPath $safeZip `
                -PackageFiles @('safe.png') `
                -SandboxRoot $sandbox.Root
            $safeZipEvidence = Test-CddsiReleaseZipLayer `
                -ZipPath $safeZip `
                -PackageFiles @('safe.png') `
                -SandboxRoot $sandbox.Root
            $safeZipEvidence.SecretFindings | Should -Be 0

            $secretZip = Join-Path $sandbox.Root 'binary-secret\secret.zip'
            New-CddsiReleaseSimulationZip `
                -StagingRoot $stagingRoot `
                -ZipPath $secretZip `
                -PackageFiles @('secret.png') `
                -SandboxRoot $sandbox.Root
            $zipError = $null
            try {
                $null = Test-CddsiReleaseZipLayer `
                    -ZipPath $secretZip `
                    -PackageFiles @('secret.png') `
                    -SandboxRoot $sandbox.Root
            }
            catch {
                $zipError = $_
            }
            $zipError | Should -Not -BeNullOrEmpty
            $zipError.Exception.Message | Should -Match 'ZIP secret scan failed'
            $zipError.Exception.Message | Should -Not -Match ([regex]::Escape($secret))
        }
        finally {
            if (Test-Path -LiteralPath $sandbox.Root) {
                Remove-CddsiOwnedSandbox -Sandbox $sandbox -Ledger $ledger
            }
        }
        (Test-Path -LiteralPath $sandbox.Root) | Should -BeFalse
    }

    It 'requires exact ledger outer and data schemas and rejects extra success entries and false counts' {
        $runId = [guid]::NewGuid().ToString('D')
        $contract = @(New-CddsiReleaseLedgerContract `
            -PackageFileCount 2 `
            -RepositoryItemCountBefore 4 `
            -RepositoryItemCountAfter 4 `
            -IncludeCleanup)
        $valid = New-CddsiReleaseFixtureLedger -RunId $runId -Contract $contract
        { Assert-CddsiReleaseLedgerSequence -Ledger $valid -RunId $runId -Expected $contract -OwnershipToken 'owner-token' } |
            Should -Not -Throw

        $extra = New-CddsiReleaseFixtureLedger -RunId $runId -Contract $contract
        Add-CddsiHarnessLedgerEntry `
            -Ledger $extra `
            -RunId $runId `
            -Category FileSystem `
            -RuleId ExtraSuccess `
            -ResourceToken '<SANDBOX_ROOT>/extra' `
            -Outcome Succeeded `
            -Data $null
        { Assert-CddsiReleaseLedgerSequence -Ledger $extra -RunId $runId -Expected $contract -OwnershipToken 'owner-token' } |
            Should -Throw

        $falseCount = New-CddsiReleaseFixtureLedger -RunId $runId -Contract $contract
        $falseCount[4].Data.ItemCount = 999
        { Assert-CddsiReleaseLedgerSequence -Ledger $falseCount -RunId $runId -Expected $contract -OwnershipToken 'owner-token' } |
            Should -Throw

        $falseType = New-CddsiReleaseFixtureLedger -RunId $runId -Contract $contract
        $falseType[4].Data = [pscustomobject][ordered]@{ ItemCount = '1' }
        { Assert-CddsiReleaseLedgerSequence -Ledger $falseType -RunId $runId -Expected $contract -OwnershipToken 'owner-token' } |
            Should -Throw

        $extraField = New-CddsiReleaseFixtureLedger -RunId $runId -Contract $contract
        $extraField[0] | Add-Member -NotePropertyName Unexpected -NotePropertyValue 'success'
        { Assert-CddsiReleaseLedgerSequence -Ledger $extraField -RunId $runId -Expected $contract -OwnershipToken 'owner-token' } |
            Should -Throw
    }

    It 'snapshots every file and directory outside dot-git and detects unclassified drift' {
        $fixture = New-CddsiReleaseFixtureRepository -Root (Join-Path $TestDrive 'source-snapshot')
        Write-CddsiReleaseFixtureText -Path (Join-Path $fixture.Root '.git\objects\ignored') -Content 'ignored'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'empty-before'))
        $before = Get-CddsiReleaseRepositorySnapshot -RepositoryRoot $fixture.Root
        @($before.Entries.Keys | Where-Object { $_ -match '^(?:D|F):\.git(?:/|$)' }).Count | Should -Be 0
        $before.DirectoryCount | Should -BeGreaterThan 0

        Write-CddsiReleaseFixtureText -Path (Join-Path $fixture.Root 'dev-only.txt') -Content 'changed outside PackageFiles'
        [void][System.IO.Directory]::CreateDirectory((Join-Path $fixture.Root 'empty-after'))
        $after = Get-CddsiReleaseRepositorySnapshot -RepositoryRoot $fixture.Root
        (Test-CddsiReleaseRepositorySnapshotsEqual -Before $before -After $after) | Should -BeFalse
    }

    It 'returns a structured sanitized failure envelope with cleanup and measured repository evidence' {
        $fixture = New-CddsiReleaseFixtureRepository -Root (Join-Path $TestDrive 'source-failure-envelope')
        $invalidSchema = "@{ SchemaVersion = 1; PackageFiles = @('README.md'); DevelopmentOnlyFiles = @('scripts/release-manifest.psd1'); Extra = 1 }"
        Write-CddsiReleaseFixtureText -Path $fixture.ManifestPath -Content $invalidSchema
        $failure = $null
        try {
            $null = Invoke-CddsiReleaseSimulation `
                -RepositoryRoot $fixture.Root `
                -ManifestPath $fixture.ManifestPath `
                -TempBase $TestDrive
        }
        catch {
            $failure = $_
        }
        $failure | Should -Not -BeNullOrEmpty
        $failure.Exception.Message | Should -BeExactly 'Release simulation failed; inspect CddsiReleaseFailure evidence.'
        $envelope = $failure.Exception.Data['CddsiReleaseFailure']
        $envelope | Should -Not -BeNullOrEmpty
        $actualEnvelopeNames = @($envelope.PSObject.Properties.Name | Sort-Object) -join "`n"
        $expectedEnvelopeNames = @(
            'CleanupError', 'CleanupOutcome', 'HarnessLedgerCount', 'Operation', 'PrimaryError',
            'RepositoryComparisonOutcome', 'RepositoryContentChanged', 'SchemaVersion', 'Status'
        ) | Sort-Object
        $actualEnvelopeNames | Should -BeExactly ($expectedEnvelopeNames -join "`n")
        $envelope.PrimaryError | Should -Match 'schema'
        $envelope.CleanupOutcome | Should -BeExactly 'Succeeded'
        $envelope.CleanupError | Should -BeNullOrEmpty
        $envelope.RepositoryComparisonOutcome | Should -BeExactly 'Compared'
        $envelope.RepositoryContentChanged | Should -BeFalse
        $envelope.HarnessLedgerCount | Should -BeGreaterThan 0
        @(Get-CddsiReleaseFixtureSandboxRoots -TempBase $TestDrive).Count | Should -Be 0

        $secret = 'sk-' + ('z' * 32 -join '')
        $escape = [char]0x1B
        $unsafe = $escape + '[31m' + [char]0x00 + [char]0x0085 + [char]0x202E +
            $secret + ' ' + $fixture.Root + ' ' + $escape + '[0m'
        $safe = Protect-CddsiReleaseFailureText `
            -Text $unsafe `
            -RepositoryRoot $fixture.Root `
            -TempRoot $TestDrive `
            -OwnershipToken 'owner-token'
        $safe | Should -Not -Match '[\x00-\x1f\x7f-\x9f]'
        $safe | Should -Not -Match '[\u061c\u200e\u200f\u202a-\u202e\u2066-\u2069]'
        $safe | Should -Not -Match ([regex]::Escape($secret))
        $safe | Should -Not -Match ([regex]::Escape($fixture.Root))
        [System.IO.File]::ReadAllText($script:BuilderPath) | Should -Not -Match 'SAFE_FAILURE_DISCLOSURE'
    }
}
