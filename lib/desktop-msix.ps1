# desktop-msix.ps1 - Claude Desktop MSIX lifecycle contracts.
# Signature verification is mandatory and has no bypass parameter.

function Get-CddsiClaudeDesktopMsixStatus {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectClaudeDesktopMsix' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe 'MSIX 检测尚未实现。'
}

function Get-CddsiOfficialMsixMetadata {
    [CmdletBinding()]
    param()

    $data = [pscustomobject][ordered]@{
        source          = 'anthropic_official'
        downloadUri     = $null
        expectedPublisher = $null
        packageIdentity = $null
        signatureRequired = $true
        metadataStatus  = 'awaiting_official_verification'
    }
    return New-CddsiOperationResult -Operation 'ResolveOfficialMsixMetadata' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '官方分发 URL、Publisher 与包身份尚待确认。' -Data $data
}

function Save-CddsiOfficialClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'DownloadClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'DownloadClaudeDesktopMsix' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会发起网络请求；仅返回未来下载计划。' -PlannedChanges @($DestinationPath)
}

function Test-CddsiClaudeDesktopMsixSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath
    )

    $data = [pscustomobject][ordered]@{
        packagePathToken = Split-Path -Leaf $PackagePath
        SchemaVersion      = 1
        ArtifactType       = 'ClaudeDesktopMsix'
        PathBindingToken   = Get-CddsiPathBindingToken -Path $PackagePath
        ArtifactSha256     = $null
        Valid              = $false
        AuthenticodeStatus = 'NotChecked'
        ChainTrusted       = $false
        PublisherMatch     = $false
        IdentityMatch      = $false
        SourcePolicy       = 'anthropic_official_only'
    }
    return New-CddsiOperationResult -Operation 'VerifyClaudeDesktopMsixSignature' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '验签合同已定义，未读取包。' -Data $data
}

function Install-CddsiClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $PackagePath -ExpectedArtifactType ClaudeDesktopMsix)) { throw '安装合同要求与目标包绑定的有效验签证据。' }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'InstallClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
        $evidencePayload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
        if (-not (Test-CddsiArtifactHashBinding -Path $PackagePath -ExpectedSha256 $evidencePayload.ArtifactSha256)) { throw '安装前文件 SHA-256 与验签证据不一致。' }
        # TODO: re-run Authenticode, chain, Publisher and identity checks on the
        # same immutable artifact immediately before the future install call.
    }
    return New-CddsiOperationResult -Operation 'InstallClaudeDesktopMsix' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会调用 Add-AppxPackage；仅返回未来安装计划。' -PlannedChanges @($PackagePath)
}

function Update-CddsiClaudeDesktopMsix {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PackagePath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $PackagePath -ExpectedArtifactType ClaudeDesktopMsix)) { throw '升级合同要求与目标包绑定的有效验签证据。' }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'UpdateClaudeDesktopMsix' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
        $evidencePayload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
        if (-not (Test-CddsiArtifactHashBinding -Path $PackagePath -ExpectedSha256 $evidencePayload.ArtifactSha256)) { throw '升级前文件 SHA-256 与验签证据不一致。' }
        # TODO: repeat complete signature verification immediately before use.
    }
    return New-CddsiOperationResult -Operation 'UpdateClaudeDesktopMsix' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会升级 MSIX；仅返回未来升级计划。' -PlannedChanges @($PackagePath)
}
