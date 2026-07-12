# git-for-windows.ps1 - Git for Windows detection and official-install contracts.
# This project never changes global Git configuration.

function Get-CddsiGitForWindowsStatus {
    [CmdletBinding()]
    param()

    return New-CddsiOperationResult -Operation 'DetectGitForWindows' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe 'Git for Windows 只读检测尚未实现。'
}

function Get-CddsiOfficialGitInstallerMetadata {
    [CmdletBinding()]
    param()

    $data = [pscustomobject][ordered]@{
        source             = 'git_for_windows_official'
        downloadUri        = $null
        expectedPublisher  = $null
        signatureRequired  = $true
        metadataStatus     = 'awaiting_official_verification'
    }
    return New-CddsiOperationResult -Operation 'ResolveGitInstallerMetadata' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '官方来源与签名身份尚待确认。' -Data $data
}

function Test-CddsiGitInstallerSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallerPath
    )

    $data = [pscustomobject][ordered]@{
        FileName           = Split-Path -Leaf $InstallerPath
        SchemaVersion      = 1
        ArtifactType       = 'GitForWindowsInstaller'
        PathBindingToken   = Get-CddsiPathBindingToken -Path $InstallerPath
        ArtifactSha256     = $null
        Valid              = $false
        AuthenticodeStatus = 'NotChecked'
        ChainTrusted       = $false
        PublisherMatch     = $false
        IdentityMatch      = $false
        SourcePolicy       = 'git_for_windows_official_only'
    }
    return New-CddsiOperationResult -Operation 'VerifyGitInstallerSignature' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe 'Git 安装包验签尚未实现。' -Data $data
}

function Save-CddsiOfficialGitInstaller {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'DownloadGitForWindows' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'DownloadGitForWindows' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会发起 Git for Windows 下载；仅返回未来计划。' -PlannedChanges @($DestinationPath)
}

function Install-CddsiGitForWindows {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$InstallerPath,
        [Parameter(Mandatory = $true)]$SignatureEvidence,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if (-not (Test-CddsiSignatureEvidence -Evidence $SignatureEvidence -ExpectedPath $InstallerPath -ExpectedArtifactType GitForWindowsInstaller)) { throw '安装合同要求与目标安装包绑定的有效验签证据。' }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'InstallGitForWindows' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
        $evidencePayload = Get-CddsiSignatureEvidencePayload -Evidence $SignatureEvidence
        if (-not (Test-CddsiArtifactHashBinding -Path $InstallerPath -ExpectedSha256 $evidencePayload.ArtifactSha256)) { throw '安装前文件 SHA-256 与验签证据不一致。' }
        # TODO: repeat complete signature verification immediately before use.
    }
    return New-CddsiOperationResult -Operation 'InstallGitForWindows' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会启动 Git 安装程序，也不会修改 Git 配置。' -PlannedChanges @($InstallerPath)
}
