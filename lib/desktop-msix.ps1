# desktop-msix.ps1 - Claude Desktop MSIX lifecycle contracts.
# Signature verification is mandatory and has no bypass parameter.

$script:CddsiD027ClaudeStandardX64SourceUri =
    'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
$script:CddsiD027ClaudeMsixMaximumBytes = [long](1GB)
$script:CddsiD027ClaudeManifestMaximumBytes = [long](1MB)
$script:CddsiD027ClaudeSignerCertificateMaximumBytes = 12288
$script:CddsiD027ClaudeManifestNamespace =
    'http://schemas.microsoft.com/appx/manifest/foundation/windows10'
$script:CddsiD027ClaudeDownloadReceiptFieldNames = @(
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
)
$script:CddsiD027ClaudeHeldArtifactObservationFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'ObservationMethod',
    'FinalPathBindingToken',
    'FileSystemName',
    'NumberOfLinks',
    'IsDirectory',
    'IsReparsePoint',
    'VolumeSerialNumberHex',
    'FileIndexHex',
    'FileIdentityToken',
    'ArtifactSha256',
    'ArtifactSizeBytes',
    'ObservedAtUtc'
)
$script:CddsiD027ClaudeManifestIdentityFieldNames = @(
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
)
$script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames = @(
    'SchemaVersion',
    'ContractVersion',
    'EvidenceKind',
    'VerificationMethod',
    'SignerExtractionMethod',
    'StateLifecycle',
    'RunId',
    'ArtifactProfile',
    'ArtifactType',
    'FinalPathBindingToken',
    'DownloadReceiptBindingToken',
    'FileIdentityToken',
    'ArtifactSha256',
    'ArtifactSizeBytes',
    'ContentBindingToken',
    'ManifestBindingToken',
    'PackageIdentityBindingToken',
    'WinVerifyTrustTrusted',
    'WinVerifyTrustStatus',
    'WinVerifyTrustNativeStatusHex',
    'WinVerifyTrustRevocationMode',
    'SignerCertificateDerBase64',
    'SignerCertificateDerSha256',
    'SignerCertificateDerLengthBytes',
    'SignerCertificateThumbprintSha1',
    'SignerSubject',
    'SignerSubjectTextSha256',
    'SignerSubjectNameRawDataSha256',
    'ObservedAtUtc',
    'EvidenceBindingToken'
)

function New-CddsiD027ClaudeDesktopSourceDescriptor {
    [CmdletBinding()]
    param()

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion              = 1
        DescriptorId               = 'claude-desktop-standard-x64-latest'
        ArtifactType               = 'ClaudeDesktopMsix'
        SourcePolicy               = 'anthropic_official_only'
        SourceUri                  = $script:CddsiD027ClaudeStandardX64SourceUri
        SourceUriBindingToken      = Get-CddsiSourceUriBindingToken `
            -SourceUri $script:CddsiD027ClaudeStandardX64SourceUri
        ReleaseVersion             = $null
        Architecture               = 'x64'
        Channel                    = 'Standard'
        FileNameToken              = '<ARTIFACT_FILE:CLAUDE_X64_STANDARD_MSIX>'
        ExpectedArtifactSha256     = $null
        ExpectedArtifactSizeBytes  = $null
        ExpectedSignerThumbprint   = $null
        ExpectedSignerSubjectToken = $null
        ExpectedPublisherToken     = $null
        ExpectedIdentityToken      = $null
        RedirectPolicy             = 'same-owner-https-only'
        MaximumBytes               = $script:CddsiD027ClaudeMsixMaximumBytes
        MetadataStatus             = 'UNRESOLVED'
    }
    $values = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $values[$property.Name] = $property.Value
    }
    $values['MetadataBindingToken'] =
        Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $descriptor = [pscustomobject]$values
    if (-not (Test-CddsiArtifactDescriptor `
        -Descriptor $descriptor `
        -ExpectedArtifactType ClaudeDesktopMsix)) {
        throw 'D-027 Claude Desktop source descriptor failed its exact unresolved contract.'
    }
    return $descriptor
}

function Test-CddsiD027ClaudeDesktopSourceDescriptor {
    [CmdletBinding()]
    param(
        [AllowNull()]$Descriptor
    )

    try {
        $expected = New-CddsiD027ClaudeDesktopSourceDescriptor
        $expectedNames = @(
            $expected.PSObject.Properties |
                ForEach-Object { [string]$_.Name }
        )
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Descriptor `
                -Expected $expectedNames)
        ) {
            return $false
        }
        foreach ($name in $expectedNames) {
            $expectedValue = $expected.$name
            $actualValue = $Descriptor.$name
            if ($null -eq $expectedValue) {
                if ($null -ne $actualValue) {
                    return $false
                }
                continue
            }
            if (
                $null -eq $actualValue -or
                $actualValue.GetType() -ne $expectedValue.GetType()
            ) {
                return $false
            }
            if ($expectedValue -is [string]) {
                if ($actualValue -cne $expectedValue) {
                    return $false
                }
            }
            elseif ($actualValue -ne $expectedValue) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-CddsiD027ClaudeSanitizedDownloadUri {
    [CmdletBinding()]
    param(
        [AllowNull()]$SourceUri
    )

    $uri = $null
    if (
        $SourceUri -isnot [string] -or
        $SourceUri.Length -lt 16 -or
        $SourceUri.Length -gt 2048 -or
        -not [Uri]::TryCreate(
            $SourceUri,
            [UriKind]::Absolute,
            [ref]$uri
        ) -or
        $uri.Scheme -cne 'https' -or
        -not $uri.IsDefaultPort -or
        $SourceUri -cne $uri.AbsoluteUri -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        -not [string]::IsNullOrEmpty($uri.Query) -or
        -not [string]::IsNullOrEmpty($uri.Fragment) -or
        $uri.DnsSafeHost.ToLowerInvariant() -cne 'downloads.claude.ai'
    ) {
        return $false
    }
    $path = $uri.AbsolutePath
    $contradictorySegmentPattern =
        '(?i)(?:^|[._~-])(?:arm64|aarch64|x86|ia32|offline)(?:[._~-]|$)'
    if (
        $path.Length -lt 7 -or
        $path.Length -gt 1024 -or
        $path.Contains('\') -or
        $path.Contains('//') -or
        $path.Contains('%') -or
        @(
            $path.Split('/') |
                Where-Object { $_ -in @('.', '..') }
        ).Count -gt 0 -or
        @(
            $path.Split('/') |
                Where-Object {
                    $_ -match $contradictorySegmentPattern
                }
        ).Count -gt 0
    ) {
        return $false
    }
    return [regex]::IsMatch(
        $path,
        '^/[A-Za-z0-9._~/-]+\.msix$',
        [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
}

function Test-CddsiD027ClaudeDownloadDestinationPath {
    [CmdletBinding()]
    param(
        [AllowNull()]$StagingRootPath,
        [AllowNull()]$DestinationPath
    )

    try {
        if (
            $StagingRootPath -isnot [string] -or
            $DestinationPath -isnot [string] -or
            $StagingRootPath.Length -lt 4 -or
            $StagingRootPath.Length -gt 32767 -or
            $DestinationPath.Length -lt 8 -or
            $DestinationPath.Length -gt 32767 -or
            $StagingRootPath.IndexOf([char]0) -ge 0 -or
            $DestinationPath.IndexOf([char]0) -ge 0 -or
            $StagingRootPath.Contains('/') -or
            $DestinationPath.Contains('/') -or
            $StagingRootPath -cnotmatch '^[A-Za-z]:\\' -or
            $DestinationPath -cnotmatch '^[A-Za-z]:\\'
        ) {
            return $false
        }

        $rootFull = [IO.Path]::GetFullPath($StagingRootPath)
        $destinationFull = [IO.Path]::GetFullPath($DestinationPath)
        $rootPath = [IO.Path]::GetPathRoot($rootFull)
        $destinationRoot = [IO.Path]::GetPathRoot($destinationFull)
        if (
            $rootFull -cne $StagingRootPath -or
            $destinationFull -cne $DestinationPath -or
            $rootPath -cnotmatch '^[A-Za-z]:\\$' -or
            $destinationRoot -cnotmatch '^[A-Za-z]:\\$' -or
            -not [string]::Equals(
                $rootPath,
                $destinationRoot,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            [string]::Equals(
                $rootFull,
                $rootPath,
                [StringComparison]::OrdinalIgnoreCase
            ) -or
            $rootFull.EndsWith('\', [StringComparison]::Ordinal) -or
            $rootFull.Substring(2).Contains(':') -or
            $destinationFull.Substring(2).Contains(':') -or
            -not [string]::Equals(
                [IO.Path]::GetDirectoryName($destinationFull),
                $rootFull,
                [StringComparison]::OrdinalIgnoreCase
            )
        ) {
            return $false
        }

        foreach ($segment in @($rootFull.Substring(3).Split('\'))) {
            $deviceBase = @($segment.Split('.'))[0].
                TrimEnd([char[]]' .')
            if (
                [string]::IsNullOrWhiteSpace($segment) -or
                $segment.IndexOfAny(
                    [IO.Path]::GetInvalidFileNameChars()
                ) -ge 0 -or
                $segment.EndsWith(
                    '.',
                    [StringComparison]::Ordinal
                ) -or
                $segment.EndsWith(
                    ' ',
                    [StringComparison]::Ordinal
                ) -or
                $deviceBase -match
                    '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|' +
                    'COM(?:[1-9]|\u00b9|\u00b2|\u00b3)|' +
                    'LPT(?:[1-9]|\u00b9|\u00b2|\u00b3))$'
            ) {
                return $false
            }
        }

        $leafName = [IO.Path]::GetFileName($destinationFull)
        $leafDeviceBase = @($leafName.Split('.'))[0].
            TrimEnd([char[]]' .')
        return (
            $leafName -cmatch '^[A-Za-z0-9._~-]+\.msix$' -and
            $leafDeviceBase -notmatch
                '^(?i:CON|PRN|AUX|NUL|CONIN\$|CONOUT\$|' +
                'COM(?:[1-9]|\u00b9|\u00b2|\u00b3)|' +
                'LPT(?:[1-9]|\u00b9|\u00b2|\u00b3))$' -and
            $leafName -cnotmatch
                '(?i)(?:^|[._~-])(?:arm64|aarch64|x86|ia32|offline)(?:[._~-]|$)'
        )
    }
    catch {
        return $false
    }
}

function Get-CddsiD027ClaudeDownloadReceiptBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Receipt
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeDownloadReceiptFieldNames |
            Where-Object { $_ -cne 'ReceiptBindingToken' }
    )
    $validNames = (
        (Test-CddsiExactPropertySet `
            -InputObject $Receipt `
            -Expected $withoutBinding) -or
        (Test-CddsiExactPropertySet `
            -InputObject $Receipt `
            -Expected $script:CddsiD027ClaudeDownloadReceiptFieldNames)
    )
    if (-not $validNames) {
        throw 'Claude download receipt did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    foreach ($name in $withoutBinding) {
        if ($name -ceq 'SanitizedRedirectUris') {
            $redirects = @($Receipt.SanitizedRedirectUris)
            $canonical.Add(
                ('{0}:{1}={2}' -f $name.Length, $name, $redirects.Count)
            )
            for ($index = 0; $index -lt $redirects.Count; $index++) {
                if ($redirects[$index] -isnot [string]) {
                    throw 'Claude download receipt redirect value was invalid.'
                }
                $text = [string]$redirects[$index]
                $canonical.Add(
                    (
                        'Redirect[{0}]={1}:{2}' -f
                            $index,
                            $text.Length,
                            $text
                    )
                )
            }
            continue
        }
        $value = $Receipt.$name
        $text = if ($value -is [string]) {
            $value
        }
        elseif ($value -is [int] -or $value -is [long]) {
            [Convert]::ToString(
                [long]$value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        else {
            throw 'Claude download receipt contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text)
        )
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Get-CddsiD027ClaudeFileIdentityToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$FinalPathBindingToken,
        [Parameter(Mandatory = $true)][string]$VolumeSerialNumberHex,
        [Parameter(Mandatory = $true)][string]$FileIndexHex,
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ArtifactSizeBytes
    )

    if (
        $FinalPathBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
        $FinalPathBindingToken -cmatch '^0{64}$' -or
        $VolumeSerialNumberHex -cnotmatch '^[0-9A-F]{8}$' -or
        $VolumeSerialNumberHex -ceq '00000000' -or
        $FileIndexHex -cnotmatch '^[0-9A-F]{16}$' -or
        $FileIndexHex -ceq '0000000000000000' -or
        $ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactSha256 -cmatch '^0{64}$' -or
        $ArtifactSizeBytes -lt 1 -or
        $ArtifactSizeBytes -gt $script:CddsiD027ClaudeMsixMaximumBytes
    ) {
        throw 'Claude held-file identity fields were invalid.'
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-d027-claude-held-file-identity-v1'
        ('FinalPathBindingToken={0}' -f $FinalPathBindingToken)
        ('VolumeSerialNumberHex={0}' -f $VolumeSerialNumberHex)
        ('FileIndexHex={0}' -f $FileIndexHex)
        'FileSystemName=NTFS'
        'NumberOfLinks=1'
        'IsDirectory=false'
        'IsReparsePoint=false'
        ('ArtifactSha256={0}' -f $ArtifactSha256)
        (
            'ArtifactSizeBytes={0}' -f
                [Convert]::ToString(
                    $ArtifactSizeBytes,
                    [Globalization.CultureInfo]::InvariantCulture
                )
        )
    ) -join "`n")
}

function Get-CddsiD027ClaudeContentBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ArtifactSizeBytes
    )

    if (
        $ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactSha256 -cmatch '^0{64}$' -or
        $ArtifactSizeBytes -lt 1 -or
        $ArtifactSizeBytes -gt $script:CddsiD027ClaudeMsixMaximumBytes
    ) {
        throw 'Claude content binding fields were invalid.'
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-d027-claude-content-v1'
        'ArtifactType=ClaudeDesktopMsix'
        ('ArtifactSha256={0}' -f $ArtifactSha256)
        (
            'ArtifactSizeBytes={0}' -f
                [Convert]::ToString(
                    $ArtifactSizeBytes,
                    [Globalization.CultureInfo]::InvariantCulture
                )
        )
    ) -join "`n")
}

function New-CddsiD027ClaudeDownloadReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$StagingRootPath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$FileIdentityToken,
        [Parameter(Mandatory = $true)][string[]]$SanitizedRedirectUris,
        [Parameter(Mandatory = $true)][string]$ArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ArtifactSizeBytes,
        [Parameter(Mandatory = $true)][string]$ObservedAtUtc
    )

    $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
    if (
        -not (Test-CddsiCanonicalUuidValue -Value $RunId) -or
        -not (Test-CddsiD027ClaudeDownloadDestinationPath `
            -StagingRootPath $StagingRootPath `
            -DestinationPath $DestinationPath) -or
        $FileIdentityToken -cnotmatch '^[a-f0-9]{64}$' -or
        $FileIdentityToken -cmatch '^0{64}$' -or
        $ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $ArtifactSha256 -cmatch '^0{64}$' -or
        $ArtifactSizeBytes -lt 1 -or
        $ArtifactSizeBytes -gt [long]$descriptor.MaximumBytes -or
        $ObservedAtUtc -notmatch
            '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
        -not (Test-CddsiUtcTimestampValue -Value $ObservedAtUtc) -or
        $null -eq $SanitizedRedirectUris -or
        $SanitizedRedirectUris.Count -lt 1 -or
        $SanitizedRedirectUris.Count -gt 5
    ) {
        throw 'Claude download receipt inputs were invalid.'
    }
    foreach ($redirectUri in $SanitizedRedirectUris) {
        if (
            -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                -SourceUri $redirectUri)
        ) {
            throw 'Claude download receipt contained an invalid sanitized redirect.'
        }
    }
    if (
        @($SanitizedRedirectUris | Sort-Object -Unique).Count -ne
            $SanitizedRedirectUris.Count
    ) {
        throw 'Claude download receipt redirect chain contained a loop.'
    }

    $requestUriBindingToken =
        Get-CddsiSourceUriBindingToken -SourceUri $descriptor.SourceUri
    $redirectCanonical = New-Object System.Collections.Generic.List[string]
    $redirectCanonical.Add('cddsi-d027-claude-redirect-chain-v1')
    $redirectCanonical.Add(('RequestUri={0}' -f $descriptor.SourceUri))
    for ($index = 0; $index -lt $SanitizedRedirectUris.Count; $index++) {
        $redirectCanonical.Add(
            ('Redirect[{0}]={1}' -f $index, $SanitizedRedirectUris[$index])
        )
    }
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-d027-claude-download-receipt-v1'
        ArtifactState = 'DOWNLOADED_UNVERIFIED'
        RunId = $RunId
        ArtifactProfile = 'VmAcceptance'
        ArtifactType = 'ClaudeDesktopMsix'
        DescriptorId = $descriptor.DescriptorId
        SourceDescriptorBindingToken = $descriptor.MetadataBindingToken
        RequestUri = $descriptor.SourceUri
        RequestUriBindingToken = $requestUriBindingToken
        SanitizedFinalUri =
            $SanitizedRedirectUris[$SanitizedRedirectUris.Count - 1]
        SanitizedRedirectUris = [string[]]@($SanitizedRedirectUris)
        RedirectChainBindingToken =
            Get-CddsiSupplyChainTextBindingToken `
                -Text ($redirectCanonical -join "`n")
        RedirectCount = [long]$SanitizedRedirectUris.Count
        StagingRootPathBindingToken =
            Get-CddsiPathBindingToken -Path $StagingRootPath
        DestinationPathBindingToken =
            Get-CddsiPathBindingToken -Path $DestinationPath
        FileIdentityToken = $FileIdentityToken
        ArtifactSha256 = $ArtifactSha256
        ArtifactSizeBytes = [long]$ArtifactSizeBytes
        ContentBindingToken =
            Get-CddsiD027ClaudeContentBindingToken `
                -ArtifactSha256 $ArtifactSha256 `
                -ArtifactSizeBytes $ArtifactSizeBytes
        ObservedAtUtc = $ObservedAtUtc
    }
    $values = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) {
        $values[$property.Name] = $property.Value
    }
    $values['ReceiptBindingToken'] =
        Get-CddsiD027ClaudeDownloadReceiptBindingToken `
            -Receipt $withoutBinding
    return [pscustomobject]$values
}

function Test-CddsiD027ClaudeDownloadReceipt {
    [CmdletBinding()]
    param(
        [AllowNull()]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedStagingRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ExpectedFileIdentityToken,
        [Parameter(Mandatory = $true)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory = $true)][long]$ExpectedArtifactSizeBytes,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        $descriptor = New-CddsiD027ClaudeDesktopSourceDescriptor
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Receipt `
                -Expected $script:CddsiD027ClaudeDownloadReceiptFieldNames) -or
            -not (Test-CddsiSchemaVersionOne -Value $Receipt.SchemaVersion) -or
            $Receipt.ContractVersion -isnot [string] -or
            $Receipt.ContractVersion -cne
                'cddsi-d027-claude-download-receipt-v1' -or
            $Receipt.ArtifactState -isnot [string] -or
            $Receipt.ArtifactState -cne 'DOWNLOADED_UNVERIFIED' -or
            -not (Test-CddsiCanonicalUuidValue -Value $ExpectedRunId) -or
            $Receipt.RunId -isnot [string] -or
            $Receipt.RunId -cne $ExpectedRunId -or
            $Receipt.ArtifactProfile -isnot [string] -or
            $Receipt.ArtifactProfile -cne 'VmAcceptance' -or
            $Receipt.ArtifactType -isnot [string] -or
            $Receipt.ArtifactType -cne 'ClaudeDesktopMsix' -or
            $Receipt.DescriptorId -isnot [string] -or
            $Receipt.DescriptorId -cne $descriptor.DescriptorId -or
            $Receipt.SourceDescriptorBindingToken -isnot [string] -or
            $Receipt.SourceDescriptorBindingToken -cne
                $descriptor.MetadataBindingToken -or
            $Receipt.RequestUri -isnot [string] -or
            $Receipt.RequestUri -cne $descriptor.SourceUri -or
            $Receipt.RequestUriBindingToken -isnot [string] -or
            $Receipt.RequestUriBindingToken -cne
                $descriptor.SourceUriBindingToken -or
            $Receipt.SanitizedRedirectUris -isnot [System.Array] -or
            -not (Test-CddsiD027ClaudeDownloadDestinationPath `
                -StagingRootPath $ExpectedStagingRootPath `
                -DestinationPath $ExpectedDestinationPath) -or
            $ExpectedFileIdentityToken -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedFileIdentityToken -cmatch '^0{64}$' -or
            $Receipt.FileIdentityToken -isnot [string] -or
            $Receipt.FileIdentityToken -cne $ExpectedFileIdentityToken -or
            $ExpectedArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ExpectedArtifactSha256 -cmatch '^0{64}$' -or
            $Receipt.ArtifactSha256 -isnot [string] -or
            $Receipt.ArtifactSha256 -cne $ExpectedArtifactSha256 -or
            $ExpectedArtifactSizeBytes -lt 1 -or
            $ExpectedArtifactSizeBytes -gt [long]$descriptor.MaximumBytes -or
            (($Receipt.ArtifactSizeBytes -isnot [int]) -and
                ($Receipt.ArtifactSizeBytes -isnot [long])) -or
            [long]$Receipt.ArtifactSizeBytes -ne
                $ExpectedArtifactSizeBytes -or
            $Receipt.ContentBindingToken -isnot [string] -or
            $Receipt.ContentBindingToken -cne
                (Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $ExpectedArtifactSha256 `
                    -ArtifactSizeBytes $ExpectedArtifactSizeBytes) -or
            (($Receipt.RedirectCount -isnot [int]) -and
                ($Receipt.RedirectCount -isnot [long])) -or
            [long]$Receipt.RedirectCount -lt 1 -or
            [long]$Receipt.RedirectCount -gt 5 -or
            $Receipt.SanitizedFinalUri -isnot [string] -or
            -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                -SourceUri $Receipt.SanitizedFinalUri)
        ) {
            return $false
        }

        $redirects = @($Receipt.SanitizedRedirectUris)
        if (
            $redirects.Count -ne [long]$Receipt.RedirectCount -or
            $Receipt.SanitizedFinalUri -cne
                $redirects[$redirects.Count - 1]
        ) {
            return $false
        }
        foreach ($redirectUri in $redirects) {
            if (
                $redirectUri -isnot [string] -or
                -not (Test-CddsiD027ClaudeSanitizedDownloadUri `
                    -SourceUri $redirectUri)
            ) {
                return $false
            }
        }
        if (@($redirects | Sort-Object -Unique).Count -ne $redirects.Count) {
            return $false
        }
        $redirectCanonical = New-Object System.Collections.Generic.List[string]
        $redirectCanonical.Add('cddsi-d027-claude-redirect-chain-v1')
        $redirectCanonical.Add(('RequestUri={0}' -f $descriptor.SourceUri))
        for ($index = 0; $index -lt $redirects.Count; $index++) {
            $redirectCanonical.Add(
                ('Redirect[{0}]={1}' -f $index, $redirects[$index])
            )
        }
        if (
            $Receipt.RedirectChainBindingToken -isnot [string] -or
            $Receipt.RedirectChainBindingToken -cne
                (Get-CddsiSupplyChainTextBindingToken `
                    -Text ($redirectCanonical -join "`n")) -or
            $Receipt.StagingRootPathBindingToken -isnot [string] -or
            $Receipt.StagingRootPathBindingToken -cne
                (Get-CddsiPathBindingToken `
                    -Path $ExpectedStagingRootPath) -or
            $Receipt.DestinationPathBindingToken -isnot [string] -or
            $Receipt.DestinationPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath) -or
            $Receipt.ReceiptBindingToken -isnot [string] -or
            $Receipt.ReceiptBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Receipt.ReceiptBindingToken -cne
                (Get-CddsiD027ClaudeDownloadReceiptBindingToken `
                    -Receipt $Receipt)
        ) {
            return $false
        }

        foreach ($timestamp in @(
                $Receipt.ObservedAtUtc,
                $ValidationTimeUtc
            )) {
            if (
                $timestamp -isnot [string] -or
                $timestamp -notmatch
                    '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
                -not (Test-CddsiUtcTimestampValue -Value $timestamp)
            ) {
                return $false
            }
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $observedTime = [DateTimeOffset]::ParseExact(
            $Receipt.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $validationTime = [DateTimeOffset]::ParseExact(
            $ValidationTimeUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        if (
            $observedTime -gt $validationTime.AddSeconds(30) -or
            $validationTime -gt $observedTime.AddMinutes(90)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-CddsiD027ClaudeDownloadedArtifactObservation {
    [CmdletBinding()]
    param(
        [AllowNull()]$Observation,
        [AllowNull()]$Receipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedStagingRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    # This function validates a pure evidence schema. Only the later Live
    # producer can prove HeldFinalFileHandle by constructing the observation
    # internally while retaining that same handle through downstream use.
    try {
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Observation `
                -Expected `
                    $script:CddsiD027ClaudeHeldArtifactObservationFieldNames) -or
            -not (Test-CddsiSchemaVersionOne `
                -Value $Observation.SchemaVersion) -or
            $Observation.ContractVersion -isnot [string] -or
            $Observation.ContractVersion -cne
                'cddsi-d027-claude-held-artifact-observation-v1' -or
            $Observation.ObservationMethod -isnot [string] -or
            $Observation.ObservationMethod -cne 'HeldFinalFileHandle' -or
            $Observation.FinalPathBindingToken -isnot [string] -or
            $Observation.FinalPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath) -or
            $Observation.FileSystemName -isnot [string] -or
            $Observation.FileSystemName -cne 'NTFS' -or
            (($Observation.NumberOfLinks -isnot [int]) -and
                ($Observation.NumberOfLinks -isnot [long])) -or
            [long]$Observation.NumberOfLinks -ne 1 -or
            $Observation.IsDirectory -isnot [bool] -or
            $Observation.IsDirectory -or
            $Observation.IsReparsePoint -isnot [bool] -or
            $Observation.IsReparsePoint -or
            $Observation.VolumeSerialNumberHex -isnot [string] -or
            $Observation.FileIndexHex -isnot [string] -or
            $Observation.FileIdentityToken -isnot [string] -or
            $Observation.FileIdentityToken -cne
                (Get-CddsiD027ClaudeFileIdentityToken `
                    -FinalPathBindingToken `
                        $Observation.FinalPathBindingToken `
                    -VolumeSerialNumberHex `
                        $Observation.VolumeSerialNumberHex `
                    -FileIndexHex $Observation.FileIndexHex `
                    -ArtifactSha256 $Observation.ArtifactSha256 `
                    -ArtifactSizeBytes `
                        ([long]$Observation.ArtifactSizeBytes)) -or
            $Observation.ArtifactSha256 -isnot [string] -or
            $Observation.ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Observation.ArtifactSha256 -cmatch '^0{64}$' -or
            (($Observation.ArtifactSizeBytes -isnot [int]) -and
                ($Observation.ArtifactSizeBytes -isnot [long])) -or
            $Observation.ObservedAtUtc -isnot [string] -or
            $Observation.ObservedAtUtc -notmatch
                '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
            -not (Test-CddsiUtcTimestampValue `
                -Value $Observation.ObservedAtUtc)
        ) {
            return $false
        }
        if (-not (Test-CddsiD027ClaudeDownloadReceipt `
            -Receipt $Receipt `
            -ExpectedRunId $ExpectedRunId `
            -ExpectedStagingRootPath $ExpectedStagingRootPath `
            -ExpectedDestinationPath $ExpectedDestinationPath `
            -ExpectedFileIdentityToken $Observation.FileIdentityToken `
            -ExpectedArtifactSha256 $Observation.ArtifactSha256 `
            -ExpectedArtifactSizeBytes `
                ([long]$Observation.ArtifactSizeBytes) `
            -ValidationTimeUtc $ValidationTimeUtc)) {
            return $false
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $observationTime = [DateTimeOffset]::ParseExact(
            $Observation.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $validationTime = [DateTimeOffset]::ParseExact(
            $ValidationTimeUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $receiptTime = [DateTimeOffset]::ParseExact(
            $Receipt.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        return (
            $observationTime -ge $receiptTime -and
            $observationTime -le $validationTime.AddSeconds(30) -and
            $validationTime -le $observationTime.AddMinutes(5)
        )
    }
    catch {
        return $false
    }
}

function Get-CddsiD027ClaudeManifestBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ManifestIdentity
    )

    $sha = $null
    try {
        $withoutBinding = @(
            $script:CddsiD027ClaudeManifestIdentityFieldNames |
                Where-Object { $_ -cne 'ManifestBindingToken' }
        )
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $ManifestIdentity `
                -Expected $withoutBinding) -and
            -not (Test-CddsiExactPropertySet `
                -InputObject $ManifestIdentity `
                -Expected $script:CddsiD027ClaudeManifestIdentityFieldNames)
        ) {
            throw 'Claude manifest identity did not match the exact binding schema.'
        }
        if (
            -not (Test-CddsiSchemaVersionOne `
                -Value $ManifestIdentity.SchemaVersion) -or
            $ManifestIdentity.ContractVersion -isnot [string] -or
            $ManifestIdentity.ContractVersion -cne
                'cddsi-d027-claude-appx-manifest-v1' -or
            $ManifestIdentity.PackageName -isnot [string] -or
            $ManifestIdentity.PackageName -cne 'Claude' -or
            $ManifestIdentity.Publisher -isnot [string] -or
            $ManifestIdentity.Publisher.Length -lt 3 -or
            $ManifestIdentity.Publisher.Length -gt 8192 -or
            $ManifestIdentity.Publisher -match '[\x00-\x1f]' -or
            $ManifestIdentity.PublisherTextSha256 -isnot [string] -or
            $ManifestIdentity.PublisherTextSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $ManifestIdentity.PublisherTextSha256 -cmatch '^0{64}$' -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -isnot
                [string] -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -cmatch
                '^0{64}$' -or
            $ManifestIdentity.PackageVersion -isnot [string] -or
            $ManifestIdentity.Architecture -isnot [string] -or
            $ManifestIdentity.Architecture -cne 'x64' -or
            $ManifestIdentity.ResourceId -isnot [string] -or
            $ManifestIdentity.ResourceId -cne '' -or
            $ManifestIdentity.PackageIdentityBindingToken -isnot [string] -or
            $ManifestIdentity.PackageIdentityBindingToken -cnotmatch
                '^[a-f0-9]{64}$' -or
            $ManifestIdentity.PackageIdentityBindingToken -cmatch '^0{64}$' -or
            $ManifestIdentity.ManifestSha256 -isnot [string] -or
            $ManifestIdentity.ManifestSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $ManifestIdentity.ManifestSha256 -cmatch '^0{64}$' -or
            (($ManifestIdentity.ManifestLengthBytes -isnot [int]) -and
                ($ManifestIdentity.ManifestLengthBytes -isnot [long])) -or
            [long]$ManifestIdentity.ManifestLengthBytes -lt 32 -or
            [long]$ManifestIdentity.ManifestLengthBytes -gt
                $script:CddsiD027ClaudeManifestMaximumBytes
        ) {
            throw 'Claude manifest identity values were invalid.'
        }

        $versionMatch = [regex]::Match(
            $ManifestIdentity.PackageVersion,
            '^(?<a>0|[1-9][0-9]{0,4})\.(?<b>0|[1-9][0-9]{0,4})\.(?<c>0|[1-9][0-9]{0,4})\.(?<d>0|[1-9][0-9]{0,4})$',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (-not $versionMatch.Success) {
            throw 'Claude manifest package version was invalid.'
        }
        foreach ($groupName in @('a', 'b', 'c', 'd')) {
            if ([int]::Parse(
                $versionMatch.Groups[$groupName].Value,
                [Globalization.CultureInfo]::InvariantCulture
            ) -gt 65535) {
                throw 'Claude manifest package version exceeded its bound.'
            }
        }

        $distinguishedName =
            New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName(
                $ManifestIdentity.Publisher
            )
        if (
            $null -eq $distinguishedName.RawData -or
            $distinguishedName.RawData.Length -lt 3
        ) {
            throw 'Claude manifest publisher distinguished name was invalid.'
        }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $publisherTextSha256 = [BitConverter]::ToString(
            $sha.ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $ManifestIdentity.Publisher
                )
            )
        ).Replace('-', '').ToLowerInvariant()
        $publisherParsedX500RawDataSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($distinguishedName.RawData)
        ).Replace('-', '').ToLowerInvariant()
        $packageIdentityBindingToken =
            Get-CddsiSupplyChainTextBindingToken -Text (@(
                'ContractVersion=cddsi-d027-claude-package-identity-v1'
                'Name=Claude'
                ('PublisherTextSha256={0}' -f $publisherTextSha256)
                (
                    'PublisherParsedX500RawDataSha256={0}' -f
                        $publisherParsedX500RawDataSha256
                )
                ('Version={0}' -f $ManifestIdentity.PackageVersion)
                'ProcessorArchitecture=x64'
                'ResourceId='
            ) -join "`n")
        if (
            $ManifestIdentity.PublisherTextSha256 -cne
                $publisherTextSha256 -or
            $ManifestIdentity.PublisherParsedX500RawDataSha256 -cne
                $publisherParsedX500RawDataSha256 -or
            $ManifestIdentity.PackageIdentityBindingToken -cne
                $packageIdentityBindingToken
        ) {
            throw 'Claude manifest publisher or package identity binding drifted.'
        }

        return Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-d027-claude-manifest-binding-v1'
            ('ManifestSha256={0}' -f $ManifestIdentity.ManifestSha256)
            (
                'ManifestLengthBytes={0}' -f
                    [Convert]::ToString(
                        [long]$ManifestIdentity.ManifestLengthBytes,
                        [Globalization.CultureInfo]::InvariantCulture
                    )
            )
            (
                'PackageIdentityBindingToken={0}' -f
                    $ManifestIdentity.PackageIdentityBindingToken
            )
        ) -join "`n")
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
    }
}

function Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $withoutBinding = @(
        $script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames |
            Where-Object { $_ -cne 'EvidenceBindingToken' }
    )
    if (
        -not (Test-CddsiExactPropertySet `
            -InputObject $Evidence `
            -Expected $withoutBinding) -and
        -not (Test-CddsiExactPropertySet `
            -InputObject $Evidence `
            -Expected $script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames)
    ) {
        throw 'Claude MSIX signature evidence did not match the exact binding schema.'
    }

    $canonical = New-Object System.Collections.Generic.List[string]
    $canonical.Add(
        'cddsi-d027-claude-msix-signature-evidence-binding-v1'
    )
    foreach ($name in $withoutBinding) {
        $value = $Evidence.$name
        $text = if ($value -is [string]) {
            $value
        }
        elseif ($value -is [bool]) {
            $value.ToString().ToLowerInvariant()
        }
        elseif ($value -is [int] -or $value -is [long]) {
            [Convert]::ToString(
                [long]$value,
                [Globalization.CultureInfo]::InvariantCulture
            )
        }
        else {
            throw 'Claude MSIX signature evidence contained an unsupported field type.'
        }
        $canonical.Add(
            ('{0}:{1}={2}:{3}' -f $name.Length, $name, $text.Length, $text)
        )
    }
    return Get-CddsiSupplyChainTextBindingToken -Text ($canonical -join "`n")
}

function Test-CddsiD027ClaudeMsixSignatureEvidenceContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Evidence,
        [Parameter(Mandatory = $true)][AllowNull()]$ManifestIdentity,
        [Parameter(Mandatory = $true)][AllowNull()]$DownloadReceipt,
        [Parameter(Mandatory = $true)][AllowNull()]$HeldArtifactObservation,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedStagingRootPath,
        [Parameter(Mandatory = $true)][string]$ExpectedDestinationPath,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $certificate = $null
    $sha = $null
    try {
        if (
            -not (Test-CddsiExactPropertySet `
                -InputObject $Evidence `
                -Expected `
                    $script:CddsiD027ClaudeMsixSignatureEvidenceFieldNames) -or
            -not (Test-CddsiExactPropertySet `
                -InputObject $ManifestIdentity `
                -Expected $script:CddsiD027ClaudeManifestIdentityFieldNames) -or
            -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
            $Evidence.ContractVersion -isnot [string] -or
            $Evidence.ContractVersion -cne
                'cddsi-d027-claude-msix-signature-evidence-v1' -or
            $Evidence.EvidenceKind -isnot [string] -or
            $Evidence.EvidenceKind -cne 'ClaudeDesktopMsixWinVerifyTrust' -or
            $Evidence.VerificationMethod -isnot [string] -or
            $Evidence.VerificationMethod -cne
                'WinVerifyTrustGenericVerifyV2' -or
            $Evidence.SignerExtractionMethod -isnot [string] -or
            $Evidence.SignerExtractionMethod -cne
                'WinVerifyTrustStateDataPrimarySigner' -or
            $Evidence.StateLifecycle -isnot [string] -or
            $Evidence.StateLifecycle -cne
                'VerifyExtractPrimarySignerClose' -or
            $Evidence.ArtifactProfile -isnot [string] -or
            $Evidence.ArtifactProfile -cne 'VmAcceptance' -or
            $Evidence.ArtifactType -isnot [string] -or
            $Evidence.ArtifactType -cne 'ClaudeDesktopMsix' -or
            $Evidence.WinVerifyTrustTrusted -isnot [bool] -or
            -not $Evidence.WinVerifyTrustTrusted -or
            $Evidence.WinVerifyTrustStatus -isnot [string] -or
            $Evidence.WinVerifyTrustStatus -cne 'Trusted' -or
            $Evidence.WinVerifyTrustNativeStatusHex -isnot [string] -or
            $Evidence.WinVerifyTrustNativeStatusHex -cne '0x00000000' -or
            $Evidence.WinVerifyTrustRevocationMode -isnot [string] -or
            $Evidence.WinVerifyTrustRevocationMode -cne 'NotChecked'
        ) {
            return $false
        }

        $runId = [guid]::Empty
        if (
            $Evidence.RunId -isnot [string] -or
            -not [guid]::TryParse($Evidence.RunId, [ref]$runId) -or
            $runId -eq [guid]::Empty -or
            $Evidence.RunId -cne $runId.ToString('D') -or
            $Evidence.RunId -cne $ExpectedRunId -or
            $Evidence.FinalPathBindingToken -isnot [string] -or
            $Evidence.FinalPathBindingToken -cne
                (Get-CddsiPathBindingToken -Path $ExpectedDestinationPath) -or
            $Evidence.DownloadReceiptBindingToken -isnot [string] -or
            $Evidence.DownloadReceiptBindingToken -cne
                $DownloadReceipt.ReceiptBindingToken -or
            $Evidence.FileIdentityToken -isnot [string] -or
            $Evidence.FileIdentityToken -cne
                $HeldArtifactObservation.FileIdentityToken -or
            $Evidence.ArtifactSha256 -isnot [string] -or
            $Evidence.ArtifactSha256 -cnotmatch '^[a-f0-9]{64}$' -or
            $Evidence.ArtifactSha256 -cmatch '^0{64}$' -or
            $Evidence.ArtifactSha256 -cne
                $HeldArtifactObservation.ArtifactSha256 -or
            (($Evidence.ArtifactSizeBytes -isnot [int]) -and
                ($Evidence.ArtifactSizeBytes -isnot [long])) -or
            [long]$Evidence.ArtifactSizeBytes -lt 1 -or
            [long]$Evidence.ArtifactSizeBytes -gt
                $script:CddsiD027ClaudeMsixMaximumBytes -or
            [long]$Evidence.ArtifactSizeBytes -ne
                [long]$HeldArtifactObservation.ArtifactSizeBytes -or
            $Evidence.ContentBindingToken -isnot [string] -or
            $Evidence.ContentBindingToken -cne
                (Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $Evidence.ArtifactSha256 `
                    -ArtifactSizeBytes ([long]$Evidence.ArtifactSizeBytes))
        ) {
            return $false
        }
        if (-not (Test-CddsiD027ClaudeDownloadedArtifactObservation `
            -Observation $HeldArtifactObservation `
            -Receipt $DownloadReceipt `
            -ExpectedRunId $ExpectedRunId `
            -ExpectedStagingRootPath $ExpectedStagingRootPath `
            -ExpectedDestinationPath $ExpectedDestinationPath `
            -ValidationTimeUtc $ValidationTimeUtc)) {
            return $false
        }

        $manifestBindingToken =
            Get-CddsiD027ClaudeManifestBindingToken `
                -ManifestIdentity $ManifestIdentity
        if (
            $ManifestIdentity.ManifestBindingToken -isnot [string] -or
            $ManifestIdentity.ManifestBindingToken -cne
                $manifestBindingToken -or
            $Evidence.ManifestBindingToken -isnot [string] -or
            $Evidence.ManifestBindingToken -cne $manifestBindingToken -or
            $Evidence.PackageIdentityBindingToken -isnot [string] -or
            $Evidence.PackageIdentityBindingToken -cne
                $ManifestIdentity.PackageIdentityBindingToken
        ) {
            return $false
        }

        if (
            $Evidence.SignerCertificateDerBase64 -isnot [string] -or
            -not (Test-CddsiD027CanonicalBase64 `
                -Value $Evidence.SignerCertificateDerBase64 `
                -MinimumBytes 256 `
                -MaximumBytes $script:CddsiD027ClaudeSignerCertificateMaximumBytes) -or
            $Evidence.SignerCertificateDerSha256 -isnot [string] -or
            $Evidence.SignerCertificateDerSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Evidence.SignerCertificateDerSha256 -cmatch '^0{64}$' -or
            (($Evidence.SignerCertificateDerLengthBytes -isnot [int]) -and
                ($Evidence.SignerCertificateDerLengthBytes -isnot [long])) -or
            $Evidence.SignerCertificateThumbprintSha1 -isnot [string] -or
            $Evidence.SignerCertificateThumbprintSha1 -cnotmatch
                '^[a-f0-9]{40}$' -or
            $Evidence.SignerCertificateThumbprintSha1 -cmatch '^0{40}$' -or
            $Evidence.SignerSubject -isnot [string] -or
            $Evidence.SignerSubject.Length -lt 3 -or
            $Evidence.SignerSubject.Length -gt 8192 -or
            $Evidence.SignerSubject -match '[\x00-\x1f]' -or
            $Evidence.SignerSubjectTextSha256 -isnot [string] -or
            $Evidence.SignerSubjectTextSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Evidence.SignerSubjectTextSha256 -cmatch '^0{64}$' -or
            $Evidence.SignerSubjectNameRawDataSha256 -isnot [string] -or
            $Evidence.SignerSubjectNameRawDataSha256 -cnotmatch
                '^[a-f0-9]{64}$' -or
            $Evidence.SignerSubjectNameRawDataSha256 -cmatch '^0{64}$'
        ) {
            return $false
        }
        $certificateBytes = [Convert]::FromBase64String(
            $Evidence.SignerCertificateDerBase64
        )
        if (
            [long]$Evidence.SignerCertificateDerLengthBytes -ne
                [long]$certificateBytes.Length -or
            $certificateBytes.Length -lt 256 -or
            $certificateBytes.Length -gt
                $script:CddsiD027ClaudeSignerCertificateMaximumBytes
        ) {
            return $false
        }
        $certificate =
            [System.Security.Cryptography.X509Certificates.X509Certificate2]::new(
                $certificateBytes,
                [string]$null,
                [System.Security.Cryptography.X509Certificates.X509KeyStorageFlags]::EphemeralKeySet
            )
        if (
            $certificate.HasPrivateKey -or
            [Convert]::ToBase64String($certificate.RawData) -cne
                $Evidence.SignerCertificateDerBase64 -or
            -not [string]::Equals(
                $certificate.Subject,
                $Evidence.SignerSubject,
                [StringComparison]::Ordinal
            ) -or
            -not [string]::Equals(
                $Evidence.SignerSubject,
                $ManifestIdentity.Publisher,
                [StringComparison]::Ordinal
            )
        ) {
            return $false
        }

        $sha = [System.Security.Cryptography.SHA256]::Create()
        $certificateSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($certificate.RawData)
        ).Replace('-', '').ToLowerInvariant()
        $subjectTextSha256 = [BitConverter]::ToString(
            $sha.ComputeHash(
                [System.Text.Encoding]::UTF8.GetBytes(
                    $certificate.Subject
                )
            )
        ).Replace('-', '').ToLowerInvariant()
        $subjectNameRawDataSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($certificate.SubjectName.RawData)
        ).Replace('-', '').ToLowerInvariant()
        if (
            $Evidence.SignerCertificateDerSha256 -cne
                $certificateSha256 -or
            $Evidence.SignerCertificateThumbprintSha1 -cne
                ([string]$certificate.Thumbprint).ToLowerInvariant() -or
            $Evidence.SignerSubjectTextSha256 -cne
                $subjectTextSha256 -or
            $Evidence.SignerSubjectNameRawDataSha256 -cne
                $subjectNameRawDataSha256
        ) {
            return $false
        }

        foreach ($timestamp in @(
                $Evidence.ObservedAtUtc,
                $ValidationTimeUtc
            )) {
            if (
                $timestamp -isnot [string] -or
                $timestamp -notmatch
                    '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z$' -or
                -not (Test-CddsiUtcTimestampValue -Value $timestamp)
            ) {
                return $false
            }
        }
        $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
            [Globalization.DateTimeStyles]::AdjustToUniversal
        $format = "yyyy-MM-dd'T'HH:mm:ss'Z'"
        $evidenceTime = [DateTimeOffset]::ParseExact(
            $Evidence.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $heldTime = [DateTimeOffset]::ParseExact(
            $HeldArtifactObservation.ObservedAtUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        $validationTime = [DateTimeOffset]::ParseExact(
            $ValidationTimeUtc,
            $format,
            [Globalization.CultureInfo]::InvariantCulture,
            $style
        )
        if (
            $evidenceTime -lt $heldTime -or
            $evidenceTime -gt $heldTime.AddMinutes(5) -or
            $evidenceTime -gt $validationTime.AddSeconds(30) -or
            $validationTime -gt $evidenceTime.AddMinutes(5) -or
            $Evidence.EvidenceBindingToken -isnot [string] -or
            $Evidence.EvidenceBindingToken -cnotmatch '^[a-f0-9]{64}$' -or
            $Evidence.EvidenceBindingToken -cmatch '^0{64}$' -or
            $Evidence.EvidenceBindingToken -cne
                (Get-CddsiD027ClaudeMsixSignatureEvidenceBindingToken `
                    -Evidence $Evidence)
        ) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $certificate) { $certificate.Dispose() }
    }
}

function ConvertFrom-CddsiD027ClaudeAppxManifestBytes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][byte[]]$ManifestBytes
    )

    $memory = $null
    $reader = $null
    $sha = $null
    try {
        if (
            $null -eq $ManifestBytes -or
            $ManifestBytes.Length -lt 32 -or
            $ManifestBytes.Length -gt $script:CddsiD027ClaudeManifestMaximumBytes
        ) {
            throw 'Manifest bytes were outside the allowed bound.'
        }
        $manifestSnapshot = [byte[]]$ManifestBytes.Clone()
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $manifestSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($manifestSnapshot)
        ).Replace('-', '').ToLowerInvariant()
        $settings = New-Object System.Xml.XmlReaderSettings
        $settings.DtdProcessing = [System.Xml.DtdProcessing]::Prohibit
        $settings.XmlResolver = $null
        $settings.MaxCharactersInDocument =
            $script:CddsiD027ClaudeManifestMaximumBytes
        $settings.MaxCharactersFromEntities = 0
        $settings.IgnoreComments = $false
        $settings.IgnoreProcessingInstructions = $false
        $settings.IgnoreWhitespace = $false

        $memory = New-Object System.IO.MemoryStream(
            $manifestSnapshot,
            0,
            $manifestSnapshot.Length,
            $false,
            $true
        )
        $reader = [System.Xml.XmlReader]::Create($memory, $settings)
        $document = New-Object System.Xml.XmlDocument
        $document.PreserveWhitespace = $true
        $document.XmlResolver = $null
        $document.Load($reader)
        if ($null -ne $document.DocumentType) {
            throw 'Manifest document type declarations are prohibited.'
        }
        $root = $document.DocumentElement
        if (
            $null -eq $root -or
            $root.LocalName -cne 'Package' -or
            $root.NamespaceURI -cne $script:CddsiD027ClaudeManifestNamespace
        ) {
            throw 'Manifest package root identity was invalid.'
        }

        $identityCandidates = @(
            $root.ChildNodes |
                Where-Object {
                    $_.NodeType -eq [System.Xml.XmlNodeType]::Element -and
                    $_.LocalName -ceq 'Identity'
                }
        )
        if (
            $identityCandidates.Count -ne 1 -or
            $identityCandidates[0].NamespaceURI -cne
                $script:CddsiD027ClaudeManifestNamespace
        ) {
            throw 'Manifest requires one exact foundation Identity element.'
        }
        $identity = $identityCandidates[0]
        if ($identity.HasChildNodes) {
            throw 'Manifest Identity must not contain child nodes.'
        }
        $attributeNames = New-Object System.Collections.Generic.List[string]
        foreach ($attribute in @($identity.Attributes)) {
            if (
                $attribute.NamespaceURI -ceq
                    'http://www.w3.org/2000/xmlns/' -or
                $attribute.Prefix -ceq 'xmlns'
            ) {
                continue
            }
            if (-not [string]::IsNullOrEmpty($attribute.NamespaceURI)) {
                throw 'Manifest Identity attributes must be unqualified.'
            }
            $attributeNames.Add([string]$attribute.LocalName)
        }
        $requiredAttributes = @(
            'Name',
            'ProcessorArchitecture',
            'Publisher',
            'Version'
        )
        $allowedWithResourceId = @($requiredAttributes + 'ResourceId')
        $actualAttributeText =
            @($attributeNames.ToArray() | Sort-Object -CaseSensitive) -join "`n"
        $requiredAttributeText =
            @($requiredAttributes | Sort-Object -CaseSensitive) -join "`n"
        $resourceAttributeText =
            @($allowedWithResourceId | Sort-Object -CaseSensitive) -join "`n"
        if (
            $actualAttributeText -cne $requiredAttributeText -and
            $actualAttributeText -cne $resourceAttributeText
        ) {
            throw 'Manifest Identity attribute set was invalid.'
        }

        $packageName = [string]$identity.GetAttribute('Name')
        $publisher = [string]$identity.GetAttribute('Publisher')
        $packageVersion = [string]$identity.GetAttribute('Version')
        $architecture = [string]$identity.GetAttribute('ProcessorArchitecture')
        $resourceId = if ($attributeNames -ccontains 'ResourceId') {
            [string]$identity.GetAttribute('ResourceId')
        }
        else {
            ''
        }
        $versionMatch = [regex]::Match(
            $packageVersion,
            '^(?<a>0|[1-9][0-9]{0,4})\.(?<b>0|[1-9][0-9]{0,4})\.(?<c>0|[1-9][0-9]{0,4})\.(?<d>0|[1-9][0-9]{0,4})$',
            [System.Text.RegularExpressions.RegexOptions]::CultureInvariant
        )
        if (
            $packageName -cne 'Claude' -or
            $architecture -cne 'x64' -or
            -not $versionMatch.Success -or
            $publisher.Length -lt 3 -or
            $publisher.Length -gt 8192 -or
            $publisher -match '[\x00-\x1f]' -or
            $resourceId -cne ''
        ) {
            throw 'Claude package name, publisher, version, architecture or resource identity was invalid.'
        }
        foreach ($groupName in @('a', 'b', 'c', 'd')) {
            if ([int]::Parse(
                $versionMatch.Groups[$groupName].Value,
                [Globalization.CultureInfo]::InvariantCulture
            ) -gt 65535) {
                throw 'Claude package version component exceeded the MSIX bound.'
            }
        }

        $distinguishedName =
            New-Object System.Security.Cryptography.X509Certificates.X500DistinguishedName(
                $publisher
            )
        if (
            $null -eq $distinguishedName.RawData -or
            $distinguishedName.RawData.Length -lt 3
        ) {
            throw 'Claude package publisher distinguished name was invalid.'
        }
        $publisherTextSha256 = [BitConverter]::ToString(
            $sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($publisher))
        ).Replace('-', '').ToLowerInvariant()
        $publisherParsedX500RawDataSha256 = [BitConverter]::ToString(
            $sha.ComputeHash($distinguishedName.RawData)
        ).Replace('-', '').ToLowerInvariant()
        $identityBindingToken = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'ContractVersion=cddsi-d027-claude-package-identity-v1'
            'Name=Claude'
            ('PublisherTextSha256={0}' -f $publisherTextSha256)
            (
                'PublisherParsedX500RawDataSha256={0}' -f
                    $publisherParsedX500RawDataSha256
            )
            ('Version={0}' -f $packageVersion)
            'ProcessorArchitecture=x64'
            ('ResourceId={0}' -f $resourceId)
        ) -join "`n")

        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-claude-appx-manifest-v1'
            PackageName = $packageName
            Publisher = $publisher
            PublisherTextSha256 = $publisherTextSha256
            PublisherParsedX500RawDataSha256 =
                $publisherParsedX500RawDataSha256
            PackageVersion = $packageVersion
            Architecture = $architecture
            ResourceId = $resourceId
            PackageIdentityBindingToken = $identityBindingToken
            ManifestSha256 = $manifestSha256
            ManifestLengthBytes = [long]$manifestSnapshot.Length
        }
        $values = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) {
            $values[$property.Name] = $property.Value
        }
        $values['ManifestBindingToken'] =
            Get-CddsiD027ClaudeManifestBindingToken `
                -ManifestIdentity $withoutBinding
        return [pscustomobject]$values
    }
    catch {
        throw 'Claude Desktop AppxManifest.xml did not match the bounded D-027 x64 identity contract.'
    }
    finally {
        if ($null -ne $sha) { $sha.Dispose() }
        if ($null -ne $reader) { $reader.Dispose() }
        if ($null -ne $memory) { $memory.Dispose() }
    }
}

function Read-CddsiD027ClaudeMsixManifest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][System.IO.Stream]$PackageStream
    )

    $archive = $null
    $entryStream = $null
    $initialPosition = [long]0
    $restorePosition = $false
    try {
        if (
            $null -eq $PackageStream -or
            -not $PackageStream.CanRead -or
            -not $PackageStream.CanSeek
        ) {
            throw 'MSIX package stream must be readable and seekable.'
        }
        $initialPosition = [long]$PackageStream.Position
        if (
            $PackageStream.Length -lt 64 -or
            $PackageStream.Length -gt $script:CddsiD027ClaudeMsixMaximumBytes -or
            $initialPosition -lt 0 -or
            $initialPosition -gt $PackageStream.Length
        ) {
            throw 'MSIX package stream length or caller position was outside the standard x64 bound.'
        }
        $PackageStream.Position = 0
        $restorePosition = $true
        Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
        Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
        $archive = [System.IO.Compression.ZipArchive]::new(
            $PackageStream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $true
        )
        $entries = @($archive.Entries)
        if ($entries.Count -lt 1 -or $entries.Count -gt 4096) {
            throw 'MSIX ZIP entry count was outside the allowed range.'
        }
        $requiredRootEntries = @(
            'AppxManifest.xml',
            'AppxSignature.p7x',
            'AppxBlockMap.xml',
            '[Content_Types].xml'
        )
        $criticalEntries = @{}
        foreach ($requiredName in $requiredRootEntries) {
            $candidates = @(
                $entries |
                    Where-Object {
                        [string]::Equals(
                            $_.FullName,
                            $requiredName,
                            [StringComparison]::OrdinalIgnoreCase
                        )
                    }
            )
            if (
                $candidates.Count -ne 1 -or
                $candidates[0].FullName -cne $requiredName
            ) {
                throw 'MSIX requires one exact copy of every critical root entry.'
            }
            $criticalEntries[$requiredName] = $candidates[0]
        }
        $manifestEntry = $criticalEntries['AppxManifest.xml']
        if (
            $manifestEntry.Length -lt 32 -or
            $manifestEntry.Length -gt $script:CddsiD027ClaudeManifestMaximumBytes -or
            $manifestEntry.CompressedLength -lt 1 -or
            (
                $manifestEntry.Length -gt 65536 -and
                $manifestEntry.CompressedLength -lt
                    [Math]::Floor($manifestEntry.Length / 1000)
            )
        ) {
            throw 'MSIX manifest entry length or compression ratio was invalid.'
        }
        $manifestBytes = New-Object byte[] ([int]$manifestEntry.Length)
        $entryStream = $manifestEntry.Open()
        $offset = 0
        while ($offset -lt $manifestBytes.Length) {
            $read = $entryStream.Read(
                $manifestBytes,
                $offset,
                $manifestBytes.Length - $offset
            )
            if ($read -le 0) {
                throw 'MSIX manifest entry read was truncated.'
            }
            $offset += $read
        }
        if ($entryStream.ReadByte() -ne -1) {
            throw 'MSIX manifest entry exceeded its declared length.'
        }
        return ConvertFrom-CddsiD027ClaudeAppxManifestBytes `
            -ManifestBytes $manifestBytes
    }
    catch {
        throw 'Claude Desktop MSIX manifest could not be read from one bounded root ZIP entry.'
    }
    finally {
        if ($null -ne $entryStream) { $entryStream.Dispose() }
        if ($null -ne $archive) { $archive.Dispose() }
        if (
            $restorePosition -and
            $null -ne $PackageStream -and
            $PackageStream.CanSeek
        ) {
            $PackageStream.Position = $initialPosition
        }
    }
}

function Get-CddsiClaudeDesktopMsixStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$MinimumVersion,
        [Parameter(Mandatory = $true)][ValidateSet('PerUser', 'MachineWide', 'Unresolved')][string]$RequiredScope,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64', 'Unknown')][string]$ExpectedArchitecture
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    try {
        $minimum = [version]::Parse($MinimumVersion)
    }
    catch {
        throw 'MinimumVersion must be a valid version string.'
    }

    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion     = 1
        InstallType       = 'Unknown'
        InventoryCount    = 0
        Version           = $null
        Architecture      = 'Unknown'
        Scope             = 'Unknown'
        DeploymentChannel = 'Unknown'
        IdentityToken     = $null
        IdentityStatus    = 'Unknown'
        CapabilityStatus  = 'UNKNOWN'
        ReasonCodes       = @('DESKTOP_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Package -Operation Inspect -ResourceToken '<PACKAGE:CLAUDE_DESKTOP>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'DESKTOP_PROVIDER_FAILED' -MessageSafe 'Synthetic Claude Desktop package provider failed closed.' -Data $unknownData
    }

    $valid = (
        (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'Installations')) -and
        $observation.SchemaVersion -is [int] -and $observation.SchemaVersion -eq 1 -and
        $null -ne $observation.Installations
    )
    [object[]]$installations = @()
    if ($valid) {
        $installations = @($observation.Installations)
    }
    if ($valid) {
        foreach ($installation in $installations) {
            if (
                -not (Test-CddsiExactPropertySet -InputObject $installation -Expected @('InstallKind', 'Version', 'Architecture', 'Scope', 'DeploymentChannel', 'IdentityToken', 'IdentityStatus', 'Operational')) -or
                $installation.InstallKind -isnot [string] -or @('LegacyExe', 'Msix') -cnotcontains $installation.InstallKind -or
                $installation.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($installation.Version) -or
                $installation.Architecture -isnot [string] -or @('x64', 'arm64', 'Unknown') -cnotcontains $installation.Architecture -or
                $installation.Scope -isnot [string] -or @('PerUser', 'MachineWide', 'Unknown') -cnotcontains $installation.Scope -or
                $installation.DeploymentChannel -isnot [string] -or @('Standard', 'Offline', 'Unknown') -cnotcontains $installation.DeploymentChannel -or
                $installation.IdentityToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $installation.IdentityToken) -or
                $installation.IdentityStatus -isnot [string] -or @('Trusted', 'Untrusted', 'Unknown') -cnotcontains $installation.IdentityStatus -or
                $installation.Operational -isnot [bool]
            ) {
                $valid = $false
                break
            }
        }
    }
    if (-not $valid) {
        $unknownData.ReasonCodes = @('DESKTOP_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'DESKTOP_RESULT_INVALID' -MessageSafe 'Synthetic Claude Desktop inventory did not match the exact schema.' -Data $unknownData
    }

    if ($installations.Count -eq 0) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            InstallType       = 'None'
            InventoryCount    = 0
            Version           = $null
            Architecture      = 'Unknown'
            Scope             = 'Unknown'
            DeploymentChannel = 'Unknown'
            IdentityToken     = $null
            IdentityStatus    = 'Unknown'
            CapabilityStatus  = 'BLOCKED'
            ReasonCodes       = @('DESKTOP_MISSING')
        }
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop inventory completed.' -Data $data
    }

    if ($installations.Count -gt 1) {
        $kinds = @($installations | ForEach-Object { $_.InstallKind } | Sort-Object -Unique -CaseSensitive)
        $scopes = @($installations | Where-Object InstallKind -CEQ 'Msix' | ForEach-Object { $_.Scope } | Sort-Object -Unique -CaseSensitive)
        $msixCount = @($installations | Where-Object InstallKind -CEQ 'Msix').Count
        $reasons = @('DESKTOP_INSTALL_CONFLICT')
        if ($kinds.Count -gt 1) { $reasons += 'LEGACY_MSIX_CONFLICT' }
        if ($msixCount -gt 1) { $reasons += 'MSIX_DOUBLE_INSTALL_RISK' }
        if ($scopes.Count -gt 1) { $reasons += 'MSIX_SCOPE_CONFLICT' }
        $data = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            InstallType       = 'Conflict'
            InventoryCount    = $installations.Count
            Version           = $null
            Architecture      = 'Unknown'
            Scope             = 'Conflict'
            DeploymentChannel = 'Unknown'
            IdentityToken     = $null
            IdentityStatus    = 'Unknown'
            CapabilityStatus  = 'BLOCKED'
            ReasonCodes       = @($reasons)
        }
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop inventory found a conflict and failed closed.' -Data $data
    }

    $installation = $installations[0]
    if ($installation.InstallKind -ceq 'LegacyExe') {
        $data = [pscustomobject][ordered]@{
            SchemaVersion     = 1
            InstallType       = 'LegacyExe'
            InventoryCount    = 1
            Version           = $installation.Version
            Architecture      = $installation.Architecture
            Scope             = $installation.Scope
            DeploymentChannel = $installation.DeploymentChannel
            IdentityToken     = $installation.IdentityToken
            IdentityStatus    = $installation.IdentityStatus
            CapabilityStatus  = 'BLOCKED'
            ReasonCodes       = @('LEGACY_DESKTOP_UNSUPPORTED')
        }
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop inventory found an unsupported legacy installation.' -Data $data
    }

    try {
        $installedVersion = [version]::Parse($installation.Version)
    }
    catch {
        $unknownData.InventoryCount = 1
        $unknownData.ReasonCodes = @('DESKTOP_VERSION_INVALID')
        return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'DESKTOP_VERSION_INVALID' -MessageSafe 'Synthetic Claude Desktop version was not parseable.' -Data $unknownData
    }

    $blockedReasons = @()
    $unknownReasons = @()
    if ($installedVersion -lt $minimum) { $blockedReasons += 'DESKTOP_UPGRADE_REQUIRED' }
    if (-not $installation.Operational) { $blockedReasons += 'DESKTOP_INSTALLATION_BROKEN' }
    if ($installation.IdentityStatus -ceq 'Untrusted') { $blockedReasons += 'DESKTOP_IDENTITY_UNTRUSTED' }
    if ($installation.IdentityStatus -ceq 'Unknown') { $unknownReasons += 'DESKTOP_IDENTITY_UNKNOWN' }
    if ($ExpectedArchitecture -ceq 'Unknown') {
        $unknownReasons += 'TARGET_ARCHITECTURE_UNKNOWN'
    }
    elseif ($installation.Architecture -ceq 'Unknown') {
        $unknownReasons += 'DESKTOP_ARCHITECTURE_UNKNOWN'
    }
    elseif ($installation.Architecture -cne $ExpectedArchitecture) {
        $blockedReasons += 'DESKTOP_ARCHITECTURE_MISMATCH'
    }
    if ($RequiredScope -ceq 'Unresolved') {
        $unknownReasons += 'MSIX_SCOPE_DECISION_REQUIRED'
    }
    elseif ($installation.Scope -ceq 'Unknown') {
        $unknownReasons += 'MSIX_SCOPE_UNKNOWN'
    }
    elseif ($installation.Scope -cne $RequiredScope) {
        $blockedReasons += 'MSIX_SCOPE_MISMATCH'
    }

    if ($blockedReasons.Count -gt 0) {
        $capabilityStatus = 'BLOCKED'
        $reasonCodes = @($blockedReasons + $unknownReasons)
    }
    elseif ($unknownReasons.Count -gt 0) {
        $capabilityStatus = 'UNKNOWN'
        $reasonCodes = @($unknownReasons)
    }
    else {
        $capabilityStatus = 'READY'
        $reasonCodes = @('DESKTOP_MSIX_READY')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion     = 1
        InstallType       = 'Msix'
        InventoryCount    = 1
        Version           = $installation.Version
        Architecture      = $installation.Architecture
        Scope             = $installation.Scope
        DeploymentChannel = $installation.DeploymentChannel
        IdentityToken     = $installation.IdentityToken
        IdentityStatus    = $installation.IdentityStatus
        CapabilityStatus  = $capabilityStatus
        ReasonCodes       = @($reasonCodes)
    }
    return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Claude Desktop MSIX inventory completed.' -Data $data
}

function ConvertFrom-CddsiAnthropicMsixReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ReleaseDocument,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
        [Parameter(Mandatory = $true)][ValidateSet('Standard', 'Offline')][string]$Channel
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ReleaseDocument -Expected @('SchemaVersion', 'SourcePolicy', 'DescriptorId', 'ReleaseVersion', 'Assets'))) {
        throw 'Anthropic MSIX release document does not match the exact schema.'
    }
    $parsedVersion = $null
    if (
        -not (Test-CddsiSchemaVersionOne -Value $ReleaseDocument.SchemaVersion) -or
        $ReleaseDocument.SourcePolicy -isnot [string] -or $ReleaseDocument.SourcePolicy -cne 'anthropic_official_only' -or
        -not (Test-CddsiSafeIdentifierValue -Value $ReleaseDocument.DescriptorId -MaxLength 128) -or
        $ReleaseDocument.ReleaseVersion -isnot [string] -or -not [version]::TryParse($ReleaseDocument.ReleaseVersion, [ref]$parsedVersion) -or
        $null -eq $ReleaseDocument.Assets
    ) {
        throw 'Anthropic MSIX release document values are invalid.'
    }

    $assetFields = @(
        'Architecture', 'Channel', 'DownloadUri', 'FileNameToken', 'ArtifactSha256',
        'SizeBytes', 'SignerThumbprint', 'SignerSubjectToken', 'PublisherToken', 'PackageIdentityToken'
    )
    $selectedAssets = @()
    foreach ($asset in @($ReleaseDocument.Assets)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $asset -Expected $assetFields)) {
            throw 'Anthropic MSIX asset does not match the exact schema.'
        }
        if (
            $asset.Architecture -isnot [string] -or @('x64', 'arm64') -cnotcontains $asset.Architecture -or
            $asset.Channel -isnot [string] -or @('Standard', 'Offline') -cnotcontains $asset.Channel -or
            $asset.DownloadUri -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $asset.DownloadUri -ExpectedOwner Anthropic) -or
            $asset.FileNameToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $asset.FileNameToken) -or
            ($asset.SizeBytes -isnot [int] -and $asset.SizeBytes -isnot [long]) -or [long]$asset.SizeBytes -lt 1
        ) {
            throw 'Anthropic MSIX asset values are invalid.'
        }
        if ($null -ne $asset.ArtifactSha256 -and ($asset.ArtifactSha256 -isnot [string] -or $asset.ArtifactSha256 -notmatch '^[a-fA-F0-9]{64}$')) { throw 'Anthropic MSIX asset SHA-256 is invalid.' }
        if ($null -ne $asset.SignerThumbprint -and ($asset.SignerThumbprint -isnot [string] -or $asset.SignerThumbprint -notmatch '^(?:[a-fA-F0-9]{40}|[a-fA-F0-9]{64})$')) { throw 'Anthropic MSIX signer thumbprint is invalid.' }
        foreach ($name in @('SignerSubjectToken', 'PublisherToken', 'PackageIdentityToken')) {
            if ($null -ne $asset.$name -and ($asset.$name -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $asset.$name))) {
                throw ('Anthropic MSIX {0} is invalid.' -f $name)
            }
        }
        if ($asset.Architecture -ceq $Architecture -and $asset.Channel -ceq $Channel) { $selectedAssets += $asset }
    }
    if ($selectedAssets.Count -ne 1) { throw 'Anthropic MSIX metadata must contain exactly one requested asset.' }

    $selected = $selectedAssets[0]
    $resolved = (
        $null -ne $selected.ArtifactSha256 -and $null -ne $selected.SignerThumbprint -and
        $null -ne $selected.SignerSubjectToken -and $null -ne $selected.PublisherToken -and
        $null -ne $selected.PackageIdentityToken
    )
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion              = 1
        DescriptorId               = $ReleaseDocument.DescriptorId
        ArtifactType               = 'ClaudeDesktopMsix'
        SourcePolicy               = 'anthropic_official_only'
        SourceUri                  = $selected.DownloadUri
        SourceUriBindingToken      = Get-CddsiSourceUriBindingToken -SourceUri $selected.DownloadUri
        ReleaseVersion             = $ReleaseDocument.ReleaseVersion
        Architecture               = $selected.Architecture
        Channel                    = $selected.Channel
        FileNameToken              = $selected.FileNameToken
        ExpectedArtifactSha256     = if ($null -eq $selected.ArtifactSha256) { $null } else { $selected.ArtifactSha256.ToLowerInvariant() }
        ExpectedArtifactSizeBytes  = [long]$selected.SizeBytes
        ExpectedSignerThumbprint   = if ($null -eq $selected.SignerThumbprint) { $null } else { $selected.SignerThumbprint.ToLowerInvariant() }
        ExpectedSignerSubjectToken = $selected.SignerSubjectToken
        ExpectedPublisherToken     = $selected.PublisherToken
        ExpectedIdentityToken      = $selected.PackageIdentityToken
        RedirectPolicy             = 'same-owner-https-only'
        MaximumBytes               = if ($Channel -ceq 'Offline') { [long]4294967296 } else { [long]1073741824 }
        MetadataStatus             = if ($resolved) { 'READY' } else { 'UNRESOLVED' }
    }
    $descriptor = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) { $descriptor[$property.Name] = $property.Value }
    $descriptor['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $result = [pscustomobject]$descriptor
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $result -ExpectedArtifactType ClaudeDesktopMsix)) {
        throw 'Anthropic MSIX descriptor failed its immutable contract.'
    }
    return $result
}

function Get-CddsiOfficialMsixMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture,
        [Parameter(Mandatory = $true)][ValidateSet('Standard', 'Offline')][string]$Channel
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    try {
        $document = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Network -Operation Inspect -ResourceToken '<NETWORK:ANTHROPIC_MSIX_METADATA>' -Arguments ([ordered]@{ Architecture = $Architecture; Channel = $Channel })
        $descriptor = ConvertFrom-CddsiAnthropicMsixReleaseMetadata -ReleaseDocument $document -Architecture $Architecture -Channel $Channel
    }
    catch {
        return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'MSIX_METADATA_INVALID' -MessageSafe 'Synthetic Anthropic MSIX metadata failed closed.'
    }
    if ($descriptor.MetadataStatus -ceq 'READY') {
        return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Anthropic MSIX metadata resolved to an immutable descriptor.' -Data $descriptor
    }
    return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'MSIX_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'MSIX signer, identity or hash remains unresolved and installation is blocked.' -Data $descriptor
}

function Save-CddsiOfficialClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType ClaudeDesktopMsix)) {
        throw 'MSIX download plan requires an exact official artifact descriptor.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $DestinationPath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'DownloadClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion         = 1
        ArtifactType         = 'ClaudeDesktopMsix'
        DestinationPathToken = $pathBindingToken
        MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken
        CacheKey              = $ArtifactDescriptor.MetadataBindingToken
        CachePolicy           = 'unique-by-immutable-descriptor'
        WriteImplemented      = $false
    }
    $errorCode = if ($ArtifactDescriptor.MetadataStatus -ceq 'READY') { 'P4_PLAN_ONLY' } else { 'MSIX_ARTIFACT_CONTRACT_UNRESOLVED' }
    return New-CddsiOperationResult -Operation 'DownloadClaudeDesktopMsix' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode $errorCode -MessageSafe 'No network or file write occurred; only an immutable download/cache plan was returned.' -Data $data -PlannedChanges @('<DOWNLOAD:CLAUDE_DESKTOP_MSIX>')
}

function Test-CddsiClaudeDesktopMsixSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)][AllowNull()]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType ClaudeDesktopMsix -RequireResolved)) {
        return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'MSIX_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'Resolved MSIX hash and identity metadata are required before verification.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $PackagePath
    try {
        $fileObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'SignatureVerification' })
        $signatureObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Package -Operation Inspect -ResourceToken '<SIGNATURE:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; ArtifactSha256 = [string]$fileObservation.ArtifactSha256 })
        $evidence = New-CddsiSignatureEvidenceVerdict -Descriptor $ArtifactDescriptor -ExpectedArtifactType ClaudeDesktopMsix -PathBindingToken $pathBindingToken -SourceObservation $SourceObservation -FileObservation $fileObservation -SignatureObservation $signatureObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc
    }
    catch {
        return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'MSIX_SIGNATURE_OBSERVATION_FAILED' -MessageSafe 'Synthetic MSIX signature observation failed closed.'
    }
    if (-not $evidence.Valid) {
        return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'MSIX_SIGNATURE_REJECTED' -MessageSafe 'MSIX signature or immutable descriptor binding did not match.' -Data $evidence
    }
    return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic MSIX signature evidence v2 is fully bound.' -Data $evidence
}

function Install-CddsiClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $PackagePath -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) { throw '安装合同要求与目标包、source observation、run/profile 及 immutable descriptor 绑定的新鲜 v2 验签证据。' }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
    $pathBindingToken = Get-CddsiPathBindingToken -Path $PackagePath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'InstallClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $current = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'ExecutionTimeHashReverification' })
    if (
        -not (Test-CddsiExactPropertySet -InputObject $current -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes')) -or
        -not (Test-CddsiSchemaVersionOne -Value $current.SchemaVersion) -or
        $current.FileIdentityToken -isnot [string] -or $current.FileIdentityToken -cne $payload.FileIdentityToken -or
        $current.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $current.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
        ($current.ArtifactSizeBytes -isnot [int] -and $current.ArtifactSizeBytes -isnot [long]) -or [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 MSIX hash/size 复验失败；拒绝安装。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'ClaudeDesktopMsix'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'InstallClaudeDesktopMsix' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'MSIX hash was reverified through the fake provider; installation remains disabled.' -Data $data -PlannedChanges @('<INSTALL:CLAUDE_DESKTOP_MSIX>')
}

function Update-CddsiClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $PackagePath -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) { throw '升级合同要求与目标包、source observation、run/profile 及 immutable descriptor 绑定的新鲜 v2 验签证据。' }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
    $pathBindingToken = Get-CddsiPathBindingToken -Path $PackagePath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'UpdateClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $current = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:CLAUDE_DESKTOP_MSIX>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'ExecutionTimeHashReverification' })
    if (
        -not (Test-CddsiExactPropertySet -InputObject $current -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes')) -or
        -not (Test-CddsiSchemaVersionOne -Value $current.SchemaVersion) -or
        $current.FileIdentityToken -isnot [string] -or $current.FileIdentityToken -cne $payload.FileIdentityToken -or
        $current.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $current.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
        ($current.ArtifactSizeBytes -isnot [int] -and $current.ArtifactSizeBytes -isnot [long]) -or [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 MSIX hash/size 复验失败；拒绝升级。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'ClaudeDesktopMsix'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'UpdateClaudeDesktopMsix' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'MSIX hash was reverified through the fake provider; update remains disabled.' -Data $data -PlannedChanges @('<UPDATE:CLAUDE_DESKTOP_MSIX>')
}
