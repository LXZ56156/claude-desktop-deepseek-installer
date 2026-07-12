[CmdletBinding()]
param(
    [string]$PesterVersion = '5.6.1',
    [switch]$Force
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$moduleRoot = Join-Path $root '.dev\modules'
$pesterManifest = Join-Path $moduleRoot ("Pester\{0}\Pester.psd1" -f $PesterVersion)

if ((Test-Path -LiteralPath $pesterManifest -PathType Leaf) -and -not $Force) {
    Remove-Module Pester -Force -ErrorAction SilentlyContinue
    $loaded = Import-Module $pesterManifest -Force -PassThru -ErrorAction Stop
    if ($loaded.Version.ToString() -ne $PesterVersion) { throw '仓库本地 Pester 版本不匹配。' }
    Write-Host "[bootstrap-dev] Pester $PesterVersion 已位于仓库本地目录。"
    return
}

if (-not (Test-Path -LiteralPath $moduleRoot -PathType Container)) {
    New-Item -ItemType Directory -Path $moduleRoot -Force | Out-Null
}

Write-Host "[bootstrap-dev] 正在把 Pester $PesterVersion 保存到 .dev/modules（不会安装到全局或 CurrentUser）。"
Save-Module -Name Pester -RequiredVersion $PesterVersion -Repository PSGallery -Path $moduleRoot -Force -ErrorAction Stop

if (-not (Test-Path -LiteralPath $pesterManifest -PathType Leaf)) {
    throw "Pester 本地依赖初始化失败: $pesterManifest"
}

Remove-Module Pester -Force -ErrorAction SilentlyContinue
$loaded = Import-Module $pesterManifest -Force -PassThru -ErrorAction Stop
if ($loaded.Version.ToString() -ne $PesterVersion) {
    throw '加载到的 Pester 版本与固定版本不一致。'
}
Write-Host "[bootstrap-dev] 完成：Pester $PesterVersion，仅仓库本地可用。"
