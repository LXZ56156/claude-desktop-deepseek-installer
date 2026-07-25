# git-for-windows.ps1 - Git for Windows detection and official-install contracts.
# This project never changes global Git configuration.

function Get-CddsiGitForWindowsStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][AllowNull()][AllowEmptyString()][string]$MinimumVersion
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    $minimum = $null
    if (-not [string]::IsNullOrWhiteSpace($MinimumVersion)) {
        try {
            $minimum = [version]::Parse($MinimumVersion)
        }
        catch {
            throw 'MinimumVersion must be null or a valid version string.'
        }
    }

    $unknownData = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        CandidateCount   = 0
        ExecutableToken  = $null
        Version          = $null
        Source           = 'Unknown'
        IdentityStatus   = 'Unknown'
        CapabilityState  = 'Unknown'
        ReuseEligible    = $false
        CapabilityStatus = 'UNKNOWN'
        ReasonCodes      = @('GIT_OBSERVATION_FAILED')
    }
    try {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Process -Operation Inspect -ResourceToken '<PROCESS:GIT_FOR_WINDOWS>' -Arguments ([ordered]@{})
    }
    catch {
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_PROVIDER_FAILED' -MessageSafe 'Synthetic Git for Windows provider failed closed.' -Data $unknownData
    }

    $valid = (
        (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'Candidates')) -and
        $observation.SchemaVersion -is [int] -and $observation.SchemaVersion -eq 1 -and
        $null -ne $observation.Candidates
    )
    [object[]]$candidates = @()
    if ($valid) {
        $candidates = @($observation.Candidates)
    }
    if ($valid) {
        foreach ($candidate in $candidates) {
            if (
                -not (Test-CddsiExactPropertySet -InputObject $candidate -Expected @('ExecutableToken', 'Version', 'Source', 'IdentityStatus', 'CapabilityState')) -or
                $candidate.ExecutableToken -isnot [string] -or -not (Test-CddsiLogicalResourceToken -ResourceToken $candidate.ExecutableToken) -or
                $candidate.Version -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate.Version) -or
                $candidate.Source -isnot [string] -or @('GitForWindows', 'Other', 'Unknown') -cnotcontains $candidate.Source -or
                $candidate.IdentityStatus -isnot [string] -or @('Trusted', 'Untrusted', 'Unknown') -cnotcontains $candidate.IdentityStatus -or
                $candidate.CapabilityState -isnot [string] -or @('Operational', 'Broken', 'Unknown') -cnotcontains $candidate.CapabilityState
            ) {
                $valid = $false
                break
            }
        }
    }
    if (-not $valid) {
        $unknownData.ReasonCodes = @('GIT_RESULT_INVALID')
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_RESULT_INVALID' -MessageSafe 'Synthetic Git inventory did not match the exact schema.' -Data $unknownData
    }

    if ($candidates.Count -eq 0) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion    = 1
            CandidateCount   = 0
            ExecutableToken  = $null
            Version          = $null
            Source           = 'Unknown'
            IdentityStatus   = 'Unknown'
            CapabilityState  = 'Unknown'
            ReuseEligible    = $false
            CapabilityStatus = 'BLOCKED'
            ReasonCodes      = @('GIT_MISSING')
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git inventory completed.' -Data $data
    }

    if ($candidates.Count -gt 1) {
        $data = [pscustomobject][ordered]@{
            SchemaVersion    = 1
            CandidateCount   = $candidates.Count
            ExecutableToken  = $null
            Version          = $null
            Source           = 'Unknown'
            IdentityStatus   = 'Unknown'
            CapabilityState  = 'Unknown'
            ReuseEligible    = $false
            CapabilityStatus = 'BLOCKED'
            ReasonCodes      = @('GIT_PATH_AMBIGUOUS')
        }
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git inventory found multiple candidates and failed closed.' -Data $data
    }

    $candidate = $candidates[0]
    try {
        $installedVersion = [version]::Parse($candidate.Version)
    }
    catch {
        $unknownData.CandidateCount = 1
        $unknownData.ReasonCodes = @('GIT_VERSION_INVALID')
        return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_VERSION_INVALID' -MessageSafe 'Synthetic Git version output was not parseable.' -Data $unknownData
    }

    $blockedReasons = @()
    $unknownReasons = @()
    if ($candidate.Source -ceq 'Other') { $blockedReasons += 'GIT_SOURCE_UNSUPPORTED' }
    if ($candidate.Source -ceq 'Unknown') { $unknownReasons += 'GIT_SOURCE_UNKNOWN' }
    if ($candidate.IdentityStatus -ceq 'Untrusted') { $blockedReasons += 'GIT_IDENTITY_UNTRUSTED' }
    if ($candidate.IdentityStatus -ceq 'Unknown') { $unknownReasons += 'GIT_IDENTITY_UNKNOWN' }
    if ($candidate.CapabilityState -ceq 'Broken') { $blockedReasons += 'GIT_CAPABILITY_BROKEN' }
    if ($candidate.CapabilityState -ceq 'Unknown') { $unknownReasons += 'GIT_CAPABILITY_UNKNOWN' }
    if ($null -eq $minimum) {
        $unknownReasons += 'GIT_MINIMUM_VERSION_UNRESOLVED'
    }
    elseif ($installedVersion -lt $minimum) {
        $blockedReasons += 'GIT_UPGRADE_REQUIRED'
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
        $reasonCodes = @('GIT_REUSE_READY')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion    = 1
        CandidateCount   = 1
        ExecutableToken  = $candidate.ExecutableToken
        Version          = $candidate.Version
        Source           = $candidate.Source
        IdentityStatus   = $candidate.IdentityStatus
        CapabilityState  = $candidate.CapabilityState
        ReuseEligible    = ($capabilityStatus -ceq 'READY')
        CapabilityStatus = $capabilityStatus
        ReasonCodes      = @($reasonCodes)
    }
    return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git for Windows inventory completed.' -Data $data
}

function ConvertFrom-CddsiGitHubReleaseMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ReleaseDocument,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $ReleaseDocument -Expected @('tag_name', 'draft', 'prerelease', 'html_url', 'assets'))) {
        throw 'GitHub release document does not match the normalized exact schema.'
    }
    if (
        $ReleaseDocument.tag_name -isnot [string] -or
        $ReleaseDocument.draft -isnot [bool] -or $ReleaseDocument.draft -or
        $ReleaseDocument.prerelease -isnot [bool] -or $ReleaseDocument.prerelease -or
        $ReleaseDocument.html_url -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $ReleaseDocument.html_url -ExpectedOwner GitForWindows) -or
        $null -eq $ReleaseDocument.assets
    ) {
        throw 'GitHub release identity, draft or prerelease state is invalid.'
    }
    $tagMatch = [regex]::Match($ReleaseDocument.tag_name, '^v(?<version>[0-9]+\.[0-9]+\.[0-9]+)\.windows\.(?<revision>[1-9][0-9]*)$')
    if (-not $tagMatch.Success) { throw 'Git for Windows release tag does not match vX.windows.N.' }
    $releaseVersion = $tagMatch.Groups['version'].Value
    $releaseRevision = $tagMatch.Groups['revision'].Value
    $artifactVersion = '{0}.{1}' -f $releaseVersion, $releaseRevision
    # Git for Windows omits ".1" from installer file names for windows.1
    # releases, but appends later revision numbers (for example,
    # Git-2.55.0.3-64-bit.exe for v2.55.0.windows.3).
    $installerFileVersion = if ($releaseRevision -ceq '1') { $releaseVersion } else { $artifactVersion }
    $expectedTagUri = 'https://github.com/git-for-windows/git/releases/tag/' + $ReleaseDocument.tag_name
    if ($ReleaseDocument.html_url -cne $expectedTagUri) { throw 'GitHub release URL is not bound to the declared tag.' }

    $assetFields = @('name', 'browser_download_url', 'size', 'state', 'content_type', 'digest')
    $assetNamePattern = if ($Architecture -ceq 'x64') {
        '^Git-' + [regex]::Escape($installerFileVersion) + '-64-bit\.exe$'
    }
    else {
        '^Git-' + [regex]::Escape($installerFileVersion) + '-arm64\.exe$'
    }
    $installerContentTypes = @('application/executable', 'application/x-msdownload')
    $selectedAssets = @()
    foreach ($asset in @($ReleaseDocument.assets)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $asset -Expected $assetFields)) {
            throw 'GitHub release asset does not match the normalized exact schema.'
        }
        if (
            $asset.name -isnot [string] -or
            $asset.browser_download_url -isnot [string] -or -not (Test-CddsiOfficialArtifactUri -SourceUri $asset.browser_download_url -ExpectedOwner GitForWindows) -or
            ($asset.size -isnot [int] -and $asset.size -isnot [long]) -or [long]$asset.size -lt 1 -or
            $asset.state -isnot [string] -or $asset.state -cne 'uploaded' -or
            $asset.content_type -isnot [string] -or [string]::IsNullOrWhiteSpace($asset.content_type) -or
            ($null -ne $asset.digest -and $asset.digest -isnot [string])
        ) {
            throw 'GitHub release asset values are invalid.'
        }
        if ($asset.name -match $assetNamePattern) {
            if ($installerContentTypes -cnotcontains $asset.content_type) {
                throw 'GitHub installer asset content type is invalid.'
            }
            if ($asset.digest -isnot [string] -or $asset.digest -notmatch '^sha256:[a-fA-F0-9]{64}$') {
                throw 'GitHub installer asset requires an exact SHA-256 digest.'
            }
            $selectedAssets += $asset
        }
    }
    if ($selectedAssets.Count -ne 1) { throw 'GitHub release metadata must contain exactly one installer for the requested architecture.' }
    $selected = $selectedAssets[0]
    $expectedAssetPrefix = 'https://github.com/git-for-windows/git/releases/download/' + $ReleaseDocument.tag_name + '/'
    if ($selected.browser_download_url -cne ($expectedAssetPrefix + $selected.name)) {
        throw 'GitHub asset URL is not exactly bound to the declared tag and asset name.'
    }
    $artifactSha256 = $selected.digest.Substring(7).ToLowerInvariant()

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion              = 1
        DescriptorId               = ('git-for-windows-{0}-windows-{1}-{2}' -f $releaseVersion, $releaseRevision, $Architecture)
        ArtifactType               = 'GitForWindowsInstaller'
        SourcePolicy               = 'git_for_windows_official_only'
        SourceUri                  = $selected.browser_download_url
        SourceUriBindingToken      = Get-CddsiSourceUriBindingToken -SourceUri $selected.browser_download_url
        ReleaseVersion             = $artifactVersion
        Architecture               = $Architecture
        Channel                    = 'Installer'
        FileNameToken              = if ($Architecture -ceq 'x64') { '<ARTIFACT_FILE:GIT_X64_INSTALLER>' } else { '<ARTIFACT_FILE:GIT_ARM64_INSTALLER>' }
        ExpectedArtifactSha256     = $artifactSha256
        ExpectedArtifactSizeBytes  = [long]$selected.size
        ExpectedSignerThumbprint   = $null
        ExpectedSignerSubjectToken = $null
        ExpectedPublisherToken     = $null
        ExpectedIdentityToken      = $null
        RedirectPolicy             = 'same-owner-https-only'
        MaximumBytes               = [long]1073741824
        MetadataStatus             = 'UNRESOLVED'
    }
    $descriptor = [ordered]@{}
    foreach ($property in $withoutBinding.PSObject.Properties) { $descriptor[$property.Name] = $property.Value }
    $descriptor['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
    $result = [pscustomobject]$descriptor
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $result -ExpectedArtifactType GitForWindowsInstaller)) {
        throw 'Git for Windows descriptor failed its immutable contract.'
    }
    return $result
}

function Get-CddsiOfficialGitInstallerMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][ValidateSet('x64', 'arm64')][string]$Architecture
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    try {
        $document = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Network -Operation Inspect -ResourceToken '<NETWORK:GIT_FOR_WINDOWS_RELEASES_API>' -Arguments ([ordered]@{ Architecture = $Architecture })
        $descriptor = ConvertFrom-CddsiGitHubReleaseMetadata -ReleaseDocument $document -Architecture $Architecture
    }
    catch {
        return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_METADATA_INVALID' -MessageSafe 'Synthetic GitHub release metadata failed closed.'
    }
    return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'GIT_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'GitHub metadata resolved version and digest, but signer and installer identity remain unresolved.' -Data $descriptor
}

function Save-CddsiOfficialGitInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller)) {
        throw 'Git download plan requires an exact official artifact descriptor.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $DestinationPath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'DownloadGitForWindows' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion         = 1
        ArtifactType         = 'GitForWindowsInstaller'
        DestinationPathToken = $pathBindingToken
        MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken
        CacheKey              = $ArtifactDescriptor.MetadataBindingToken
        CachePolicy           = 'unique-by-immutable-descriptor'
        WriteImplemented      = $false
    }
    $errorCode = if ($ArtifactDescriptor.MetadataStatus -ceq 'READY') { 'P4_PLAN_ONLY' } else { 'GIT_ARTIFACT_CONTRACT_UNRESOLVED' }
    return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode $errorCode -MessageSafe 'No network or file write occurred; only an immutable download/cache plan was returned.' -Data $data -PlannedChanges @('<DOWNLOAD:GIT_FOR_WINDOWS_INSTALLER>')
}

function Test-CddsiGitInstallerSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)][AllowNull()]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if (-not (Test-CddsiArtifactDescriptor -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller -RequireResolved)) {
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'GIT_ARTIFACT_CONTRACT_UNRESOLVED' -MessageSafe 'Resolved Git hash and signer identity metadata are required before verification.'
    }
    $pathBindingToken = Get-CddsiPathBindingToken -Path $InstallerPath
    try {
        $fileObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'SignatureVerification' })
        $signatureObservation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider Package -Operation Inspect -ResourceToken '<SIGNATURE:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; ArtifactSha256 = [string]$fileObservation.ArtifactSha256 })
        $evidence = New-CddsiSignatureEvidenceVerdict -Descriptor $ArtifactDescriptor -ExpectedArtifactType GitForWindowsInstaller -PathBindingToken $pathBindingToken -SourceObservation $SourceObservation -FileObservation $fileObservation -SignatureObservation $signatureObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc
    }
    catch {
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_SIGNATURE_OBSERVATION_FAILED' -MessageSafe 'Synthetic Git signature observation failed closed.'
    }
    if (-not $evidence.Valid) {
        return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'FAILED' -Mode $Context.Mode -ErrorCode 'GIT_SIGNATURE_REJECTED' -MessageSafe 'Git signature or immutable descriptor binding did not match.' -Data $evidence
    }
    return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe 'Synthetic Git signature evidence v2 is fully bound.' -Data $evidence
}

function Install-CddsiGitForWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [Parameter(Mandatory = $true)]$ArtifactDescriptor,
        [Parameter(Mandatory = $true)]$SourceObservation,
        [Parameter(Mandatory = $true)][ValidateSet('VmCalibration', 'VmAcceptance', 'UserLive')][string]$ArtifactProfile,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $InstallerPath -ExpectedArtifactType GitForWindowsInstaller -Descriptor $ArtifactDescriptor -SourceObservation $SourceObservation -ExpectedRunId $Context.RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc $ValidationTimeUtc)) { throw '安装合同要求与目标安装包、source observation、run/profile 及 immutable descriptor 绑定的新鲜 v2 验签证据。' }
    $payload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
    $pathBindingToken = Get-CddsiPathBindingToken -Path $InstallerPath
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'InstallGitForWindows' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    $current = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider FileSystem -Operation Inspect -ResourceToken '<ARTIFACT:GIT_FOR_WINDOWS_INSTALLER>' -Arguments ([ordered]@{ PathBindingToken = $pathBindingToken; Purpose = 'ExecutionTimeHashReverification' })
    if (
        -not (Test-CddsiExactPropertySet -InputObject $current -Expected @('SchemaVersion', 'FileIdentityToken', 'ArtifactSha256', 'ArtifactSizeBytes')) -or
        -not (Test-CddsiSchemaVersionOne -Value $current.SchemaVersion) -or
        $current.FileIdentityToken -isnot [string] -or $current.FileIdentityToken -cne $payload.FileIdentityToken -or
        $current.ArtifactSha256 -isnot [string] -or -not (Test-CddsiArtifactHashBinding -ActualSha256 $current.ArtifactSha256 -ExpectedSha256 $payload.ArtifactSha256) -or
        ($current.ArtifactSizeBytes -isnot [int] -and $current.ArtifactSizeBytes -isnot [long]) -or [long]$current.ArtifactSizeBytes -ne [long]$payload.ArtifactSizeBytes
    ) { throw '执行时 Git installer hash/size 复验失败；拒绝安装。' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; ArtifactType = 'GitForWindowsInstaller'; PathBindingToken = $pathBindingToken; FileIdentityToken = $payload.FileIdentityToken; ArtifactSha256 = $payload.ArtifactSha256; MetadataBindingToken = $ArtifactDescriptor.MetadataBindingToken; SourceObservationBindingToken = $SourceObservation.SourceObservationBindingToken; ExecutionHashReverified = $true; AtomicVerifyAndInstallRequiredForLive = $true; LiveInstallImplemented = $false }
    return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P4_PLAN_ONLY' -MessageSafe 'Git installer hash was reverified through the fake provider; installation remains disabled.' -Data $data -PlannedChanges @('<INSTALL:GIT_FOR_WINDOWS>')
}
