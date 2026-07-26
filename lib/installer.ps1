# Narrow Git for Windows and Claude Desktop installation path.

function Resolve-CddsiGitReleaseAsset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Release
    )

    if ($Release.PSObject.Properties.Name -notcontains 'immutable' -or
        $Release.immutable -isnot [bool] -or
        -not $Release.immutable -or
        $Release.draft -ne $false -or
        $Release.prerelease -ne $false -or
        $Release.tag_name -notmatch '^v(?<Base>\d+\.\d+\.\d+)\.windows\.(?<Revision>\d+)$') {
        Throw-CddsiError -Code 'GIT_METADATA_INVALID' `
            -Message 'Git 官方 release metadata 不完整或不是 immutable 正式版本。'
    }

    $tag = [string]$Release.tag_name
    $baseVersion = $Matches.Base
    $revision = [int]$Matches.Revision
    $expectedArtifactVersion = if ($revision -eq 1) {
        $baseVersion
    }
    else {
        '{0}.{1}' -f $baseVersion, $revision
    }
    $expectedName = 'Git-{0}-64-bit.exe' -f $expectedArtifactVersion
    $assets = @($Release.assets | Where-Object { $_.name -ceq $expectedName })
    if ($assets.Count -ne 1) {
        Throw-CddsiError -Code 'GIT_METADATA_INVALID' `
            -Message 'Git 官方 release 中没有唯一的 x64 installer。'
    }

    $asset = $assets[0]
    $expectedUrl = 'https://github.com/git-for-windows/git/releases/download/{0}/{1}' -f `
        $tag, $expectedName
    if ($asset.browser_download_url -cne $expectedUrl -or
        $asset.state -cne 'uploaded' -or
        $asset.size -isnot [long] -and $asset.size -isnot [int] -or
        [long]$asset.size -lt 1048576 -or
        [long]$asset.size -gt 1073741824 -or
        $asset.digest -notmatch '^sha256:(?<Hash>[a-f0-9]{64})$') {
        Throw-CddsiError -Code 'GIT_METADATA_INVALID' `
            -Message 'Git x64 installer metadata 的 URL、长度或 SHA-256 无效。'
    }

    [pscustomobject][ordered]@{
        Tag          = $tag
        Version      = [version]$expectedArtifactVersion
        FileName     = $expectedName
        Uri          = $expectedUrl
        Size         = [long]$asset.size
        Sha256       = $Matches.Hash
        PublishedUtc = [string]$Release.published_at
    }
}

function Get-CddsiGitVersion {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Executable
    )

    try {
        $output = @(& $Executable --version 2>$null)
        if ($LASTEXITCODE -ne 0 -or $output.Count -ne 1 -or
            $output[0] -notmatch '^git version (?<Version>\d+\.\d+\.\d+)(?:\.windows\.\d+)?$') {
            return $null
        }
        return [version]$Matches.Version
    }
    catch {
        return $null
    }
}

function Get-CddsiGitStatus {
    [CmdletBinding()]
    param()

    $candidatePaths = @(
        (Join-Path $env:ProgramFiles 'Git\cmd\git.exe')
        (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd\git.exe')
    ) | Select-Object -Unique
    $present = @($candidatePaths | Where-Object {
        Test-Path -LiteralPath $_ -PathType Leaf
    })
    if ($present.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Installed = $false
            Healthy   = $false
            Path      = $null
            Version   = $null
        }
    }
    $valid = @()
    foreach ($path in $present) {
        try {
            [void](Get-CddsiTrustedSignature -Path $path -Artifact Git)
            $version = Get-CddsiGitVersion -Executable $path
            if ($null -ne $version) {
                $valid += [pscustomobject]@{
                    Path    = [System.IO.Path]::GetFullPath($path)
                    Version = $version
                }
            }
        }
        catch {
            # An invalid canonical installation is repaired by the official installer.
        }
    }
    if ($valid.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Installed = $true
            Healthy   = $false
            Path      = $null
            Version   = $null
        }
    }
    $selected = $valid | Sort-Object Version -Descending | Select-Object -First 1
    [pscustomobject][ordered]@{
        Installed = $true
        Healthy   = $true
        Path      = $selected.Path
        Version   = $selected.Version
    }
}

function Get-CddsiTrustedSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path,

        [Parameter(Mandatory = $true)]
        [ValidateSet('Git', 'Claude')]
        [string]$Artifact
    )

    $signature = Get-AuthenticodeSignature -LiteralPath $Path -ErrorAction Stop
    if ($signature.Status -ne [System.Management.Automation.SignatureStatus]::Valid -or
        $null -eq $signature.SignerCertificate -or
        [string]::IsNullOrWhiteSpace($signature.SignerCertificate.Subject)) {
        Throw-CddsiError -Code ('{0}_SIGNATURE_INVALID' -f $Artifact.ToUpperInvariant()) `
            -Message ('{0} 安装包的 Authenticode 签名不受信任。' -f $Artifact)
    }
    $subject = [string]$signature.SignerCertificate.Subject
    $subjectAccepted = switch ($Artifact) {
        'Git' {
            $subject -match '^CN=Johannes Schindelin, O=Johannes Schindelin, .+, C=DE$'
            break
        }
        'Claude' {
            $subject -match '^CN="Anthropic, PBC", O="Anthropic, PBC", .+, C=US, SERIALNUMBER=4860621,'
            break
        }
    }
    if (-not $subjectAccepted) {
        Throw-CddsiError -Code ('{0}_SIGNER_INVALID' -f $Artifact.ToUpperInvariant()) `
            -Message ('{0} 安装包签名有效，但发布者不是预期的官方发布者。' -f $Artifact)
    }
    return $signature
}

function Save-CddsiWebFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [uri]$Uri,

        [Parameter(Mandatory = $true)]
        [string]$Destination,

        [Parameter(Mandatory = $true)]
        [ValidateRange(1, 1073741824)]
        [long]$MaximumBytes,

        [hashtable]$Headers = @{}
    )

    [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
    Add-Type -AssemblyName System.Net.Http -ErrorAction Stop
    $handler = New-Object System.Net.Http.HttpClientHandler
    $handler.AllowAutoRedirect = $true
    $handler.MaxAutomaticRedirections = 5
    $handler.UseDefaultCredentials = $false
    $client = New-Object System.Net.Http.HttpClient($handler)
    $client.Timeout = [TimeSpan]::FromMinutes(30)
    $response = $null
    $input = $null
    $output = $null
    $completed = $false
    try {
        foreach ($entry in $Headers.GetEnumerator()) {
            if (-not $client.DefaultRequestHeaders.TryAddWithoutValidation(
                [string]$entry.Key,
                [string]$entry.Value
            )) {
                Throw-CddsiError -Code 'DOWNLOAD_HEADER_INVALID' `
                    -Message '官方下载请求包含无效 header。'
            }
        }
        $response = $client.GetAsync(
            $Uri,
            [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead
        ).GetAwaiter().GetResult()
        $response.EnsureSuccessStatusCode()
        if ($null -ne $response.Content.Headers.ContentLength -and
            [long]$response.Content.Headers.ContentLength -gt $MaximumBytes) {
            Throw-CddsiError -Code 'DOWNLOAD_TOO_LARGE' `
                -Message '官方下载长度超过产品安全上限。'
        }

        $input = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $output = New-Object System.IO.FileStream(
            $Destination,
            [System.IO.FileMode]::CreateNew,
            [System.IO.FileAccess]::Write,
            [System.IO.FileShare]::None,
            65536,
            [System.IO.FileOptions]::SequentialScan
        )
        $buffer = New-Object byte[] 65536
        [long]$total = 0
        while (($read = $input.Read($buffer, 0, $buffer.Length)) -gt 0) {
            $total += $read
            if ($total -gt $MaximumBytes) {
                Throw-CddsiError -Code 'DOWNLOAD_TOO_LARGE' `
                    -Message '官方下载长度超过产品安全上限。'
            }
            $output.Write($buffer, 0, $read)
        }
        $output.Flush($true)
        $completed = $true
        return [pscustomobject][ordered]@{
            FinalUri = [uri]$response.RequestMessage.RequestUri
            Bytes    = $total
        }
    }
    catch {
        if ($_.Exception.Message -match '^[A-Z0-9_]{3,80}\|') {
            throw
        }
        Throw-CddsiError -Code 'DOWNLOAD_FAILED' `
            -Message '官方下载失败；请检查网络后重试。'
    }
    finally {
        if ($null -ne $output) { $output.Dispose() }
        if ($null -ne $input) { $input.Dispose() }
        if ($null -ne $response) { $response.Dispose() }
        $client.Dispose()
        $handler.Dispose()
        if (-not $completed -and
            (Test-Path -LiteralPath $Destination -PathType Leaf)) {
            Remove-Item -LiteralPath $Destination -Force `
                -ErrorAction SilentlyContinue
        }
    }
}

function Install-CddsiGitIfNeeded {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempDirectory
    )

    $before = Get-CddsiGitStatus
    if ($before.Healthy) {
        $gitDirectory = Split-Path -Parent $before.Path
        if (@($env:Path -split ';') -notcontains $gitDirectory) {
            $env:Path = '{0};{1}' -f $gitDirectory, $env:Path
        }
        return [pscustomobject][ordered]@{
            Changed = $false
            Path    = $before.Path
            Version = $before.Version
        }
    }

    $headers = @{
        Accept               = 'application/vnd.github+json'
        'X-GitHub-Api-Version' = '2022-11-28'
        'User-Agent'         = 'Claude-Desktop-DeepSeek-Installer'
    }
    try {
        [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
        $release = Invoke-RestMethod `
            -Uri 'https://api.github.com/repos/git-for-windows/git/releases/latest' `
            -Headers $headers -UseBasicParsing -ErrorAction Stop
    }
    catch {
        Throw-CddsiError -Code 'GIT_METADATA_UNAVAILABLE' `
            -Message '无法读取 Git for Windows 官方 release metadata。'
    }
    $descriptor = Resolve-CddsiGitReleaseAsset -Release $release
    $installerPath = Join-Path $TempDirectory $descriptor.FileName
    [void](Save-CddsiWebFile -Uri ([uri]$descriptor.Uri) `
        -Destination $installerPath -MaximumBytes $descriptor.Size `
        -Headers @{ 'User-Agent' = $headers.'User-Agent' })

    $item = Get-Item -LiteralPath $installerPath -ErrorAction Stop
    $hash = Get-CddsiFileSha256 -Path $installerPath
    if ($item.Length -ne $descriptor.Size -or $hash -cne $descriptor.Sha256) {
        Throw-CddsiError -Code 'GIT_HASH_MISMATCH' `
            -Message 'Git installer 的长度或 SHA-256 与官方 metadata 不一致。'
    }
    [void](Get-CddsiTrustedSignature -Path $installerPath -Artifact Git)

    $preExecutionHash = Get-CddsiFileSha256 -Path $installerPath
    if ($preExecutionHash -cne $descriptor.Sha256) {
        Throw-CddsiError -Code 'GIT_TOCTOU_MISMATCH' `
            -Message 'Git installer 在执行前发生变化。'
    }

    $arguments = @(
        '/VERYSILENT'
        '/NORESTART'
        '/NOCANCEL'
        '/SP-'
        '/SUPPRESSMSGBOXES'
        '/o:PathOption=Cmd'
    )
    try {
        $process = Start-Process -FilePath $installerPath `
            -ArgumentList $arguments -WorkingDirectory (Join-Path $env:SystemRoot 'System32') `
            -Verb RunAs -Wait -PassThru -ErrorAction Stop
    }
    catch {
        if ($_.Exception.Message -match '(?i)cancel|canceled|cancelled|1223') {
            Throw-CddsiError -Code 'USER_CANCELLED' -Message '用户取消了 Git 安装或 UAC。'
        }
        Throw-CddsiError -Code 'GIT_INSTALL_FAILED' -Message 'Git installer 无法启动。'
    }
    if ($process.ExitCode -ne 0) {
        Throw-CddsiError -Code 'GIT_INSTALL_FAILED' `
            -Message ('Git installer 返回非零退出码 {0}。' -f $process.ExitCode)
    }

    $after = Get-CddsiGitStatus
    if (-not $after.Healthy) {
        Throw-CddsiError -Code 'GIT_READBACK_FAILED' `
            -Message 'Git 安装结束，但 readback 未找到可工作的唯一 Git。'
    }
    $gitDirectory = Split-Path -Parent $after.Path
    if (@($env:Path -split ';') -notcontains $gitDirectory) {
        $env:Path = '{0};{1}' -f $gitDirectory, $env:Path
    }
    return [pscustomobject][ordered]@{
        Changed = $true
        Path    = $after.Path
        Version = $after.Version
    }
}

function Read-CddsiClaudeMsixIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    Add-Type -AssemblyName System.IO.Compression -ErrorAction Stop
    Add-Type -AssemblyName System.IO.Compression.FileSystem -ErrorAction Stop
    $stream = $null
    $archive = $null
    try {
        $stream = [System.IO.File]::Open(
            $Path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $archive = New-Object System.IO.Compression.ZipArchive(
            $stream,
            [System.IO.Compression.ZipArchiveMode]::Read,
            $false
        )
        $entries = @($archive.Entries | Where-Object {
            $_.FullName -ceq 'AppxManifest.xml'
        })
        if ($entries.Count -ne 1 -or $entries[0].Length -gt 1048576) {
            Throw-CddsiError -Code 'CLAUDE_MANIFEST_INVALID' `
                -Message 'Claude MSIX 中没有唯一、受限的 AppxManifest.xml。'
        }
        $reader = New-Object System.IO.StreamReader(
            $entries[0].Open(),
            [System.Text.Encoding]::UTF8,
            $true,
            4096,
            $false
        )
        try {
            [xml]$xml = $reader.ReadToEnd()
        }
        finally {
            $reader.Dispose()
        }
        $identity = $xml.SelectSingleNode(
            '/*[local-name()="Package"]/*[local-name()="Identity"]'
        )
        if ($null -eq $identity -or
            $identity.Name -cne 'Claude' -or
            $identity.ProcessorArchitecture -cne 'x64' -or
            [string]::IsNullOrWhiteSpace($identity.Publisher)) {
            Throw-CddsiError -Code 'CLAUDE_IDENTITY_INVALID' `
                -Message 'Claude MSIX package identity 或架构不符合预期。'
        }
        try {
            $version = [version]$identity.Version
        }
        catch {
            Throw-CddsiError -Code 'CLAUDE_IDENTITY_INVALID' `
                -Message 'Claude MSIX version 无法解析。'
        }
        [pscustomobject][ordered]@{
            Name         = [string]$identity.Name
            Publisher    = [string]$identity.Publisher
            Architecture = [string]$identity.ProcessorArchitecture
            Version      = $version
        }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        if ($null -ne $stream) { $stream.Dispose() }
    }
}

function Get-CddsiClaudeStatus {
    [CmdletBinding()]
    param(
        [string]$ExpectedPublisher = ''
    )

    try {
        $packages = @(Get-AppxPackage -Name Claude -ErrorAction Stop |
            Where-Object {
                [string]$_.Architecture -ceq 'X64' -and
                [string]$_.Publisher -match '^CN="Anthropic, PBC", O="Anthropic, PBC", .+, C=US, SERIALNUMBER=4860621,' -and
                ([string]::IsNullOrEmpty($ExpectedPublisher) -or
                    [string]$_.Publisher -ceq $ExpectedPublisher)
            })
    }
    catch {
        $packages = @()
    }
    if ($packages.Count -eq 0) {
        return [pscustomobject][ordered]@{
            Installed = $false
            Version   = $null
        }
    }
    $best = $packages | Sort-Object Version -Descending | Select-Object -First 1
    [pscustomobject][ordered]@{
        Installed = $true
        Version   = [version]$best.Version
    }
}

function Stop-CddsiClaudeProcesses {
    [CmdletBinding()]
    param()

    $processes = @(Get-Process -Name Claude -ErrorAction SilentlyContinue)
    if ($processes.Count -eq 0) {
        return $false
    }
    try {
        $processes | Stop-Process -Force -ErrorAction Stop
        return $true
    }
    catch {
        Throw-CddsiError -Code 'CLAUDE_CLOSE_REQUIRED' `
            -Message 'Claude Desktop 正在运行且无法安全关闭；请保存工作后手动退出。'
    }
}

function Install-CddsiClaudeDesktop {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$TempDirectory
    )

    $source = [uri]'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
    $path = Join-Path $TempDirectory 'Claude-latest-x64.msix'
    $response = Save-CddsiWebFile -Uri $source -Destination $path `
        -MaximumBytes 1073741824 `
        -Headers @{ 'User-Agent' = 'Claude-Desktop-DeepSeek-Installer' }
    $finalUri = [uri]$response.FinalUri
    if ($finalUri.Scheme -cne 'https' -or
        $finalUri.DnsSafeHost.ToLowerInvariant() -cne 'downloads.claude.ai' -or
        $finalUri.AbsolutePath -notmatch '^/releases/win32/x64/.+\.msix$') {
        Throw-CddsiError -Code 'CLAUDE_SOURCE_INVALID' `
            -Message 'Claude 下载未落在官方 x64 MSIX 来源。'
    }

    $item = Get-Item -LiteralPath $path -ErrorAction Stop
    if ($item.Length -lt 1048576 -or $item.Length -gt 1073741824) {
        Throw-CddsiError -Code 'CLAUDE_DOWNLOAD_INVALID' `
            -Message 'Claude MSIX 的下载长度不合理。'
    }
    $downloadHash = Get-CddsiFileSha256 -Path $path
    $signature = Get-CddsiTrustedSignature -Path $path -Artifact Claude
    $identity = Read-CddsiClaudeMsixIdentity -Path $path
    if ($identity.Publisher -cne $signature.SignerCertificate.Subject) {
        Throw-CddsiError -Code 'CLAUDE_PUBLISHER_MISMATCH' `
            -Message 'Claude MSIX manifest Publisher 与签名证书 Subject 不一致。'
    }

    $before = Get-CddsiClaudeStatus -ExpectedPublisher $identity.Publisher
    if ($before.Installed -and $before.Version -ge $identity.Version) {
        return [pscustomobject][ordered]@{
            Changed = $false
            Version = $before.Version
            Sha256  = $downloadHash
        }
    }

    $preExecutionHash = Get-CddsiFileSha256 -Path $path
    if ($preExecutionHash -cne $downloadHash) {
        Throw-CddsiError -Code 'CLAUDE_TOCTOU_MISMATCH' `
            -Message 'Claude MSIX 在安装前发生变化。'
    }
    [void](Stop-CddsiClaudeProcesses)
    try {
        Add-AppxPackage -Path $path -ForceApplicationShutdown -ErrorAction Stop
    }
    catch {
        Throw-CddsiError -Code 'CLAUDE_INSTALL_FAILED' `
            -Message 'Windows 无法安装官方 Claude MSIX。'
    }

    $after = Get-CddsiClaudeStatus -ExpectedPublisher $identity.Publisher
    if (-not $after.Installed -or $after.Version -lt $identity.Version) {
        Throw-CddsiError -Code 'CLAUDE_READBACK_FAILED' `
            -Message 'Claude 安装结束，但 AppX readback 未确认目标版本。'
    }
    [pscustomobject][ordered]@{
        Changed = $true
        Version = $after.Version
        Sha256  = $downloadHash
    }
}
