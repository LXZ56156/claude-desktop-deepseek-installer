# desktop-msix.ps1 - Claude Desktop MSIX lifecycle contracts.
# Signature verification is mandatory and has no bypass parameter.

$script:CddsiD027ClaudeStandardX64SourceUri =
    'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
$script:CddsiD027ClaudeMsixMaximumBytes = [long](1GB)
$script:CddsiD027ClaudeManifestMaximumBytes = [long](1MB)
$script:CddsiD027ClaudeManifestNamespace =
    'http://schemas.microsoft.com/appx/manifest/foundation/windows10'

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
            $ManifestBytes,
            0,
            $ManifestBytes.Length,
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
        $sha = [System.Security.Cryptography.SHA256]::Create()
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

        return [pscustomobject][ordered]@{
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
        }
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
