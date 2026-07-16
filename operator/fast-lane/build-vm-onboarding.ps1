[CmdletBinding()]
param(
    [switch]$ImportOnly
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$entryImportOnly = $PSBoundParameters.ContainsKey('ImportOnly') -and $ImportOnly.IsPresent
$repositoryRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

. (Join-Path $repositoryRoot 'lib\bootstrap.ps1')
Import-CddsiLibraries
. (Join-Path $repositoryRoot 'scripts\build-release.ps1') -ImportOnly
. (Join-Path (Split-Path -Parent (Split-Path -Parent $PSScriptRoot)) 'operator\fast-lane\invoke-git-outbox.ps1')

$script:CddsiFastLaneOnboardingOutputMarker = '.cddsi-vm-onboarding-output.json'
$script:CddsiFastLaneOnboardingZipName = 'cddsi-fast-lane-vm-onboarding.zip'
$script:CddsiFastLaneOnboardingManifestPath = 'manifest.json'
$script:CddsiFastLaneOnboardingInventoryPath = 'inventory.json'
$script:CddsiFastLaneOnboardingFixedTimestampUtc = '1980-01-01T00:00:00Z'
$script:CddsiFastLaneOnboardingMaximumFileBytes = 16MB
$script:CddsiFastLaneOnboardingMaximumBundleBytes = 64MB
$script:CddsiFastLaneOnboardingMaximumEntryCount = 256
$script:CddsiFastLaneOnboardingRepositoryNames = [ordered]@{
    Product  = 'LXZ56156/claude-desktop-deepseek-installer'
    HostToVm = 'LXZ56156/cddsi-host-to-vm'
    VmToHost = 'LXZ56156/cddsi-vm-to-host'
}

function Get-CddsiFastLaneOnboardingFileSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    $stream = $null
    try {
        $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        if ($null -ne $stream) { $stream.Dispose() }
        $sha.Dispose()
    }
}

function Get-CddsiFastLaneOnboardingBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Value)

    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $Value
}

function New-CddsiFastLaneOnboardingSourceGitContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$GitExecutable,
        [Parameter(Mandatory = $true)][string]$GitExecutableSha256,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$SandboxRoot
    )

    if (-not [System.IO.Path]::IsPathRooted($GitExecutable)) {
        throw 'VM onboarding source Git executable must be an absolute path.'
    }
    $gitFull = Get-CddsiCanonicalPath -Path $GitExecutable
    if (-not [System.IO.File]::Exists($gitFull) -or
        [System.IO.Path]::GetFileName($gitFull) -ine 'git.exe') {
        throw 'VM onboarding source Git executable must be the exact git.exe file.'
    }
    Assert-CddsiNoReparsePath -Path $gitFull -StopRoot ([System.IO.Path]::GetPathRoot($gitFull))
    if ($GitExecutableSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        (Get-CddsiFastLaneOnboardingFileSha256 -Path $gitFull) -cne $GitExecutableSha256) {
        throw 'VM onboarding source Git executable SHA-256 differs.'
    }
    if (Test-CddsiPathWithinRoot -Path $gitFull -Root $SourceRoot) {
        throw 'VM onboarding source Git executable must remain outside the source repository.'
    }

    Initialize-CddsiFastLaneBoundedProcessType
    return @{
        GitExecutable = $gitFull
        GitExecutableSha256 = $GitExecutableSha256
        SourceRoot = $SourceRoot
        StateRoot = $SandboxRoot
        MaximumRuntimeSeconds = 45
        MaximumGitCommandSeconds = 10
        MaximumOutputBytes = 4MB
        Stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        GitInvocationCount = 0
        OperatorGitTransportCount = 0
        LocalStateMutationCount = 0
        JobAssignmentCount = 0
        ProcessTreeTerminationCount = 0
    }
}

function Invoke-CddsiFastLaneOnboardingSourceGit {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [AllowNull()][string]$StandardInput = $null
    )

    $fixedArguments = @(
        '-c', 'core.fsmonitor=false',
        '-c', 'core.untrackedCache=false',
        '-c', 'submodule.recurse=false',
        '-c', 'core.autocrlf=false',
        '-c', 'core.safecrlf=true',
        '-c', 'core.attributesFile=NUL',
        '-C', $Context.SourceRoot
    ) + @($Arguments)
    return Invoke-CddsiFastLaneGitCommand -Context $Context -Arguments $fixedArguments `
        -StandardInput $StandardInput `
        -AdditionalEnvironment @{ GIT_OPTIONAL_LOCKS = '0'; GIT_ATTR_NOSYSTEM = '1' }
}

function Get-CddsiFastLaneOnboardingGitScalar {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string[]]$Arguments,
        [Parameter(Mandatory = $true)][string]$FailureMessage
    )

    $result = Invoke-CddsiFastLaneOnboardingSourceGit -Context $Context -Arguments $Arguments
    $value = $result.StandardOutput.Trim()
    if ([string]::IsNullOrWhiteSpace($value) -or $value.Contains("`r") -or $value.Contains("`n")) {
        throw $FailureMessage
    }
    return $value
}

function Assert-CddsiFastLaneOnboardingNoUnsafeGitAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$RelativePaths
    )

    if ($RelativePaths.Count -eq 0) { return }
    $attributeNames = @('filter', 'working-tree-encoding', 'ident')
    $standardInput = ($RelativePaths -join [char]0) + [char]0
    $result = Invoke-CddsiFastLaneOnboardingSourceGit -Context $Context `
        -Arguments (@('check-attr', '-z') + $attributeNames + @('--stdin')) `
        -StandardInput $standardInput
    $tokens = @($result.StandardOutput.Split([char]0))
    $expectedTokenCount = ($RelativePaths.Count * $attributeNames.Count * 3) + 1
    if ($tokens.Count -ne $expectedTokenCount -or $tokens[-1] -cne '') {
        throw 'VM onboarding repository Git attribute response is invalid.'
    }

    $tokenIndex = 0
    foreach ($relativePath in $RelativePaths) {
        foreach ($attributeName in $attributeNames) {
            if ($tokens[$tokenIndex] -cne $relativePath -or
                $tokens[$tokenIndex + 1] -cne $attributeName) {
                throw 'VM onboarding repository Git attribute response is not path-bound.'
            }
            if ($tokens[$tokenIndex + 2] -cne 'unspecified') {
                throw ('VM onboarding source path has an unsafe Git clean attribute: {0}' -f $relativePath)
            }
            $tokenIndex += 3
        }
    }
}

function Assert-CddsiFastLaneOnboardingSafeGitAttributes {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $attributeNames = @('text', 'eol', 'filter', 'working-tree-encoding', 'ident')
    $result = Invoke-CddsiFastLaneOnboardingSourceGit -Context $Context `
        -Arguments (@('check-attr', '-z') + $attributeNames + @('--', $RelativePath))
    $tokens = @($result.StandardOutput.Split([char]0))
    if ($tokens.Count -ne (($attributeNames.Count * 3) + 1) -or $tokens[-1] -cne '') {
        throw ('VM onboarding Git attribute response is invalid: {0}' -f $RelativePath)
    }

    $attributes = [ordered]@{}
    for ($index = 0; $index -lt $attributeNames.Count; $index++) {
        $offset = $index * 3
        $name = $attributeNames[$index]
        if ($tokens[$offset] -cne $RelativePath -or $tokens[$offset + 1] -cne $name) {
            throw ('VM onboarding Git attribute response is not path-bound: {0}' -f $RelativePath)
        }
        $attributes[$name] = $tokens[$offset + 2]
    }

    if ($attributes.text -cne 'set' -or @('lf', 'crlf') -cnotcontains $attributes.eol) {
        throw ('VM onboarding source path must use explicit built-in text/eol conversion: {0}' -f $RelativePath)
    }
    foreach ($unsafeName in @('filter', 'working-tree-encoding', 'ident')) {
        if ($attributes[$unsafeName] -cne 'unspecified') {
            throw ('VM onboarding source path has an unsafe Git clean attribute: {0}' -f $RelativePath)
        }
    }
}

function Assert-CddsiFastLaneOnboardingSourceRepository {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ProductCommitSha
    )

    $inside = Get-CddsiFastLaneOnboardingGitScalar -Context $Context `
        -Arguments @('rev-parse', '--is-inside-work-tree') `
        -FailureMessage 'VM onboarding source repository work-tree check failed.'
    if ($inside -cne 'true') { throw 'VM onboarding source root is not a Git work tree.' }

    $topLevel = Get-CddsiFastLaneOnboardingGitScalar -Context $Context `
        -Arguments @('rev-parse', '--show-toplevel') `
        -FailureMessage 'VM onboarding source repository root check failed.'
    $topLevelFull = Get-CddsiCanonicalPath -Path $topLevel
    if (-not $topLevelFull.Equals($Context.SourceRoot, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'VM onboarding source root must be the exact Git repository root.'
    }

    $head = Get-CddsiFastLaneOnboardingGitScalar -Context $Context `
        -Arguments @('rev-parse', '--verify', 'HEAD^{commit}') `
        -FailureMessage 'VM onboarding source repository HEAD check failed.'
    if ($head -cne $ProductCommitSha) {
        throw 'VM onboarding source repository HEAD differs from the exact product commit.'
    }
    $tree = Get-CddsiFastLaneOnboardingGitScalar -Context $Context `
        -Arguments @('rev-parse', '--verify', 'HEAD^{tree}') `
        -FailureMessage 'VM onboarding source repository tree check failed.'
    if ($tree -cnotmatch '^[a-f0-9]{40}$') {
        throw 'VM onboarding source repository tree identity is invalid.'
    }

    $committedBlobs = [System.Collections.Generic.Dictionary[string,object]]::new([StringComparer]::Ordinal)
    $treeListing = Invoke-CddsiFastLaneOnboardingSourceGit -Context $Context `
        -Arguments @('ls-tree', '-r', '-z', '--full-tree', $ProductCommitSha)
    foreach ($record in @($treeListing.StandardOutput.Split([char]0) | Where-Object { $_.Length -gt 0 })) {
        if ($record -cnotmatch '^(?<mode>[0-7]{6}) (?<type>blob|commit) (?<sha>[a-f0-9]{40})\t(?<path>.+)$' -or
            $committedBlobs.ContainsKey($Matches.path)) {
            throw 'VM onboarding source repository tree listing is invalid.'
        }
        $committedBlobs.Add($Matches.path, [pscustomobject][ordered]@{
            Mode = $Matches.mode; Type = $Matches.type; Sha = $Matches.sha
        })
    }
    $Context.CommittedBlobs = $committedBlobs

    $committedBlobPaths = [string[]]@($committedBlobs.Keys | Where-Object {
        $committedBlobs[$_].Type -ceq 'blob'
    })
    [Array]::Sort($committedBlobPaths, [StringComparer]::Ordinal)
    Assert-CddsiFastLaneOnboardingNoUnsafeGitAttributes -Context $Context `
        -RelativePaths $committedBlobPaths

    $status = Invoke-CddsiFastLaneOnboardingSourceGit -Context $Context `
        -Arguments @('status', '--porcelain=v1', '-z', '--untracked-files=all', '--ignore-submodules=none')
    if ($status.StandardOutput.Length -ne 0) {
        throw 'VM onboarding source repository must be clean, including untracked files.'
    }
    return [pscustomobject][ordered]@{
        CommitSha = $head
        TreeSha = $tree
        SourceCommitVerified = $true
        GitExecutableSha256 = $Context.GitExecutableSha256
    }
}

function Get-CddsiFastLaneOnboardingCommittedBlob {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][hashtable]$Context,
        [Parameter(Mandatory = $true)][string]$ProductCommitSha,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    if (-not $Context.ContainsKey('CommittedBlobs') -or
        -not $Context.CommittedBlobs.ContainsKey($RelativePath) -or
        $Context.CommittedBlobs[$RelativePath].Type -cne 'blob') {
        throw ('VM onboarding allow-list path is not one exact committed blob: {0}' -f $RelativePath)
    }
    $blobSha = [string]$Context.CommittedBlobs[$RelativePath].Sha
    Assert-CddsiFastLaneOnboardingSafeGitAttributes -Context $Context -RelativePath $RelativePath
    $workingBlobSha = Get-CddsiFastLaneOnboardingGitScalar -Context $Context `
        -Arguments @('hash-object', ('--path={0}' -f $RelativePath), '--', $RelativePath) `
        -FailureMessage ('VM onboarding working-tree blob hash is invalid: {0}' -f $RelativePath)
    if ($workingBlobSha -cnotmatch '^[a-f0-9]{40}$') {
        throw ('VM onboarding working-tree blob hash is invalid: {0}' -f $RelativePath)
    }
    if ($workingBlobSha -cne $blobSha) {
        throw ('VM onboarding working tree does not match the committed blob: {0}' -f $RelativePath)
    }
    return $blobSha
}

function Write-CddsiFastLaneOnboardingCanonicalFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    Write-CddsiUtf8CreateNew -Path $Path -Content ((ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Value) + "`n")
}

function Assert-CddsiFastLaneOnboardingSandbox {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Sandbox)

    if (-not (Test-CddsiExactPropertySet -InputObject $Sandbox -Expected @(
        'Root', 'TempBase', 'RunId', 'OwnershipToken', 'MarkerPath', 'Paths', 'CanaryValue',
        'CanaryPaths', 'CanaryFileSha256'
    ))) { throw 'VM onboarding build requires an exact caller-owned HostSandbox.' }
    if (-not [System.IO.Directory]::Exists($Sandbox.Root)) { throw 'VM onboarding HostSandbox is unavailable.' }
    Assert-CddsiNoReparsePath -Path $Sandbox.Root -StopRoot $Sandbox.TempBase
    $null = Read-CddsiOwnerMarker -Sandbox $Sandbox
}

function Assert-CddsiFastLaneOnboardingOutputPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$OutputDirectory
    )

    $outputFull = Get-CddsiCanonicalPath -Path $OutputDirectory
    if (-not (Test-CddsiPathWithinRoot -Path $outputFull -Root $Sandbox.Root)) {
        throw 'VM onboarding output must be inside the caller-owned HostSandbox.'
    }
    if ([System.IO.Directory]::Exists($outputFull) -or [System.IO.File]::Exists($outputFull)) {
        throw 'VM onboarding output must not already exist.'
    }
    $parent = Split-Path -Parent $outputFull
    if (-not [System.IO.Directory]::Exists($parent)) { throw 'VM onboarding output parent must already exist.' }
    Assert-CddsiNoReparsePath -Path $parent -StopRoot $Sandbox.Root
    Assert-CddsiNoReparsePath -Path $outputFull -StopRoot $Sandbox.Root -PathMayNotExist
    return $outputFull
}

function Test-CddsiFastLaneOnboardingForbiddenRelativePath {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $segments = @($Path.Split('/') | ForEach-Object { $_.ToLowerInvariant() })
    foreach ($forbidden in @('.git', '.dev', '.ssh', 'tests', 'secrets', 'credentials')) {
        if ($segments -contains $forbidden) { return $true }
    }
    $leaf = $segments[$segments.Count - 1]
    foreach ($suffix in @('.key', '.pem', '.pfx', '.p12', '.kdbx')) {
        if ($leaf.EndsWith($suffix, [StringComparison]::Ordinal)) { return $true }
    }
    return $false
}

function Assert-CddsiFastLaneOnboardingNoUserPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )

    $bytes = [System.IO.File]::ReadAllBytes($Path)
    $content = [System.Text.Encoding]::GetEncoding(28591).GetString($bytes)
    $patterns = @(
        '(?i)(?<![A-Za-z0-9_])[A-Za-z]:[\\/]',
        '(?<![\\])\\\\[^\\/\r\n]+[\\/]',
        '(?m)(?<![A-Za-z0-9_:/.-])/(?!/)(?:[A-Za-z0-9._-]+/)*[A-Za-z0-9._-]+'
    )
    foreach ($pattern in $patterns) {
        if ([regex]::IsMatch($content, $pattern)) {
            throw ('VM onboarding source contains a host-specific absolute path: {0}' -f $RelativePath)
        }
    }
}

function ConvertTo-CddsiFastLaneOnboardingFileSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Git', 'Runtime', 'Reset', 'Prompt', 'Runbook')][string]$Category,
        [Parameter(Mandatory = $true)][object[]]$Specifications,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][hashtable]$SourceGitContext,
        [Parameter(Mandatory = $true)][string]$ProductCommitSha
    )

    if (@($Specifications).Count -lt 1) { throw ('VM onboarding {0} file set must not be empty.' -f $Category) }
    $items = [System.Collections.Generic.List[object]]::new()
    foreach ($specification in @($Specifications)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $specification -Expected @('Path', 'Sha256'))) {
            throw ('VM onboarding {0} file specification schema drifted.' -f $Category)
        }
        $relative = ConvertTo-CddsiReleaseRelativePath -Path ([string]$specification.Path)
        if (Test-CddsiFastLaneOnboardingForbiddenRelativePath -Path $relative) {
            throw ('VM onboarding file path is forbidden: {0}' -f $relative)
        }
        $expectedSha = [string]$specification.Sha256
        if ($expectedSha -cnotmatch '^[a-f0-9]{64}$') { throw 'VM onboarding expected file SHA-256 is invalid.' }
        $full = Get-CddsiCanonicalPath -Path (Join-Path $SourceRoot ($relative.Replace('/', '\')))
        if (-not (Test-CddsiPathWithinRoot -Path $full -Root $SourceRoot) -or -not [System.IO.File]::Exists($full)) {
            throw ('VM onboarding allow-list entry is missing: {0}' -f $relative)
        }
        Assert-CddsiNoReparsePath -Path $full -StopRoot $SourceRoot
        $length = [long]([System.IO.FileInfo]::new($full).Length)
        if ($length -lt 0 -or $length -gt $script:CddsiFastLaneOnboardingMaximumFileBytes) {
            throw ('VM onboarding file length is outside the fixed limit: {0}' -f $relative)
        }
        $actualSha = Get-CddsiFastLaneOnboardingFileSha256 -Path $full
        if ($actualSha -cne $expectedSha) { throw ('VM onboarding source hash differs: {0}' -f $relative) }
        $gitBlobSha = Get-CddsiFastLaneOnboardingCommittedBlob -Context $SourceGitContext `
            -ProductCommitSha $ProductCommitSha -RelativePath $relative
        $sourceScanItem = [pscustomobject][ordered]@{ RelativePath = $relative; FullPath = $full }
        $null = Invoke-CddsiReleaseFileSecretScan -Items @($sourceScanItem) -Layer Source
        Assert-CddsiFastLaneOnboardingNoUserPath -Path $full -RelativePath $relative
        $categoryToken = $Category.ToLowerInvariant()
        $bundlePath = ConvertTo-CddsiReleaseRelativePath -Path ('payload/{0}/{1}' -f $categoryToken, $relative)
        $items.Add([pscustomobject][ordered]@{
            Category = $Category; SourcePath = $relative; BundlePath = $bundlePath
            Sha256 = $expectedSha; GitBlobSha = $gitBlobSha; LengthBytes = $length; FullPath = $full
        })
    }
    return [object[]]$items.ToArray()
}

function ConvertTo-CddsiFastLaneOnboardingTools {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][object[]]$ToolSpecifications)

    if (@($ToolSpecifications).Count -lt 1) { throw 'VM onboarding tool specifications must not be empty.' }
    $items = [System.Collections.Generic.List[object]]::new()
    $ids = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
    $paths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    foreach ($tool in @($ToolSpecifications)) {
        if (-not (Test-CddsiExactPropertySet -InputObject $tool -Expected @('ToolId', 'VmPath', 'Sha256'))) {
            throw 'VM onboarding tool specification schema drifted.'
        }
        $toolId = [string]$tool.ToolId
        $vmPath = [string]$tool.VmPath
        $sha256 = [string]$tool.Sha256
        if ($toolId -cnotmatch '^[A-Za-z][A-Za-z0-9._-]{0,63}$' -or -not $ids.Add($toolId)) {
            throw 'VM onboarding tool identity is invalid or duplicated.'
        }
        if ($vmPath -notmatch '^(?i)%(?:PROGRAMFILES|PROGRAMFILES\(X86\)|SYSTEMROOT)%\\[A-Za-z0-9 ._()\-\\]+\.exe$' -or
            $vmPath.Contains('..') -or -not $paths.Add($vmPath)) {
            throw 'VM onboarding tool path must be a unique fixed system-path token ending in .exe.'
        }
        if ($sha256 -cnotmatch '^[a-f0-9]{64}$') { throw 'VM onboarding tool SHA-256 is invalid.' }
        $items.Add([pscustomobject][ordered]@{ ToolId = $toolId; VmPath = $vmPath; Sha256 = $sha256 })
    }
    $ordered = [object[]]$items.ToArray()
    [Array]::Sort($ordered, [System.Collections.Generic.Comparer[object]]::Create(
        [System.Comparison[object]]{ param($left, $right) [StringComparer]::Ordinal.Compare([string]$left.ToolId, [string]$right.ToolId) }
    ))
    $requiredTools = [ordered]@{
        Git = '%PROGRAMFILES%\Git\cmd\git.exe'
        OpenSSH = '%PROGRAMFILES%\Git\usr\bin\ssh.exe'
        PowerShell7 = '%PROGRAMFILES%\PowerShell\7\pwsh.exe'
        WindowsPowerShell = '%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    if ((@($ordered.ToolId | Sort-Object) -join "`n") -cne (@($requiredTools.Keys | Sort-Object) -join "`n")) {
        throw 'VM onboarding tools must contain exactly Git, OpenSSH, PowerShell7, and WindowsPowerShell.'
    }
    foreach ($item in $ordered) {
        if ($item.VmPath -cne $requiredTools[$item.ToolId]) {
            throw ('VM onboarding fixed tool path differs: {0}' -f $item.ToolId)
        }
    }
    return [object[]]$ordered
}

function Assert-CddsiFastLaneOnboardingRepositoryIdentity {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Role,
        [Parameter(Mandatory = $true)][long]$Id,
        [Parameter(Mandatory = $true)][string]$NodeId,
        [Parameter(Mandatory = $true)][string]$FullName,
        [Parameter(Mandatory = $true)][string]$ExpectedFullName
    )

    if ($Id -le 0 -or $NodeId -cnotmatch '^[A-Za-z0-9_=-]{4,128}$' -or $FullName -cne $ExpectedFullName) {
        throw ('VM onboarding {0} repository identity is invalid.' -f $Role)
    }
    return [pscustomobject][ordered]@{ Id = $Id; NodeId = $NodeId; FullName = $FullName }
}

function Assert-CddsiFastLaneOnboardingPolicyBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PolicyPath,
        [Parameter(Mandatory = $true)][string]$PolicySha256,
        [Parameter(Mandatory = $true)][string]$KnownHostsSourcePath,
        [Parameter(Mandatory = $true)][string]$KnownHostsSha256,
        [Parameter(Mandatory = $true)]$ProductRepository,
        [Parameter(Mandatory = $true)]$HostToVmRepository,
        [Parameter(Mandatory = $true)]$VmToHostRepository,
        [Parameter(Mandatory = $true)][string]$ProductCommitSha,
        [Parameter(Mandatory = $true)][string]$RepairRef,
        [Parameter(Mandatory = $true)][string]$HostToVmGenesisSha,
        [Parameter(Mandatory = $true)][string]$VmToHostGenesisSha
    )

    $policy = Import-PowerShellDataFile -LiteralPath $PolicyPath
    if ($policy.SchemaVersion -ne 1 -or $policy.ProtocolVersion -cne 'cddsi-vm-test-relay-v1' -or
        $policy.Lane -cne 'Fast' -or $policy.ControlPlane.Topology -cne 'DirectionalRepositoryPair' -or
        -not $policy.ProductRemote.PrivateRequired -or -not $policy.ProductRemote.VmReadOnly -or
        -not $policy.ControlPlane.PrivateRepositoryRequired -or
        -not $policy.ControlPlane.ServerProtectedHistoryRequired -or
        -not $policy.ControlPlane.PinnedGenesisRequired -or
        -not $policy.ControlPlane.CompareAndSwapRequired -or
        $policy.ControlPlane.ForcePushAllowed -or $policy.ControlPlane.HistoryRewriteAllowed -or
        $policy.ControlPlane.DeletePublishedMessage) {
        throw 'VM onboarding committed Fast Lane policy is not the frozen private append-only contract.'
    }
    if ($policy.SshTrust.GitHubHost -cne 'github.com' -or
        $policy.SshTrust.OpenSshToolId -cne 'OpenSSH' -or
        $policy.SshTrust.OpenSshVmPath -cne '%PROGRAMFILES%\Git\usr\bin\ssh.exe' -or
        $policy.SshTrust.KnownHostsSourcePath -cne 'operator/fast-lane/trust/github-known-hosts' -or
        $policy.SshTrust.KnownHostsSourcePath -cne $KnownHostsSourcePath -or
        $policy.SshTrust.KnownHostsSha256 -cne $KnownHostsSha256 -or
        -not $policy.SshTrust.StrictHostKeyCheckingRequired) {
        throw 'VM onboarding SSH executable or GitHub known-hosts trust differs from committed policy.'
    }
    $repositoryBindings = @(
        [pscustomobject]@{ Actual = $ProductRepository; Expected = $policy.ProductRemote; Genesis = $ProductCommitSha; Ref = $RepairRef; TokenName = 'Product' },
        [pscustomobject]@{ Actual = $HostToVmRepository; Expected = $policy.ControlPlane.HostToVm; Genesis = $HostToVmGenesisSha; Ref = $policy.ControlPlane.HostToVm.Ref; TokenName = 'HostToVm' },
        [pscustomobject]@{ Actual = $VmToHostRepository; Expected = $policy.ControlPlane.VmToHost; Genesis = $VmToHostGenesisSha; Ref = $policy.ControlPlane.VmToHost.Ref; TokenName = 'VmToHost' }
    )
    foreach ($binding in $repositoryBindings) {
        $token = [string]$binding.Expected.RepositoryToken
        if ($token -cnotmatch '^github\.com/([A-Za-z0-9][A-Za-z0-9._-]{0,63}/[A-Za-z0-9][A-Za-z0-9._-]{0,95})$' -or
            $binding.Actual.FullName -cne $Matches[1] -or
            [long]$binding.Actual.Id -ne [long]$binding.Expected.RepositoryId -or
            $binding.Actual.NodeId -cne $binding.Expected.RepositoryNodeId) {
            throw ('VM onboarding repository differs from committed policy: {0}' -f $binding.TokenName)
        }
        if ($binding.TokenName -cne 'Product' -and $binding.Genesis -cne $binding.Expected.GenesisCommitSha) {
            throw ('VM onboarding genesis differs from committed policy: {0}' -f $binding.TokenName)
        }
    }
    if ($RepairRef -cnotlike $policy.ProductRemote.HostWriteRefPattern -or
        $policy.ControlPlane.HostToVm.Ref -cne 'refs/heads/main' -or
        $policy.ControlPlane.VmToHost.Ref -cne 'refs/heads/main' -or
        [long]$policy.Automation.IntervalMinutes -ne 1 -or
        $policy.Automation.Host.InitialStatus -cne 'PAUSED' -or
        $policy.Automation.Vm.InitialStatus -cne 'PAUSED' -or
        -not $policy.Automation.Vm.MustBeCreatedOnVmDevice) {
        throw 'VM onboarding ref or automation facts differ from committed policy.'
    }

    return [pscustomobject][ordered]@{
        Path = 'payload/git/config/fast-lane-policy.psd1'
        Sha256 = $PolicySha256
        ProtocolVersion = $policy.ProtocolVersion
        ProductRepository = [pscustomobject][ordered]@{
            RepositoryToken = $policy.ProductRemote.RepositoryToken
            Id = [long]$policy.ProductRemote.RepositoryId
            NodeId = $policy.ProductRemote.RepositoryNodeId
            FullName = $ProductRepository.FullName
            HostWriteRefPattern = $policy.ProductRemote.HostWriteRefPattern
        }
        HostToVmRepository = [pscustomobject][ordered]@{
            RepositoryToken = $policy.ControlPlane.HostToVm.RepositoryToken
            Id = [long]$policy.ControlPlane.HostToVm.RepositoryId
            NodeId = $policy.ControlPlane.HostToVm.RepositoryNodeId
            FullName = $HostToVmRepository.FullName
            Ref = $policy.ControlPlane.HostToVm.Ref
            GenesisSha = $policy.ControlPlane.HostToVm.GenesisCommitSha
        }
        VmToHostRepository = [pscustomobject][ordered]@{
            RepositoryToken = $policy.ControlPlane.VmToHost.RepositoryToken
            Id = [long]$policy.ControlPlane.VmToHost.RepositoryId
            NodeId = $policy.ControlPlane.VmToHost.RepositoryNodeId
            FullName = $VmToHostRepository.FullName
            Ref = $policy.ControlPlane.VmToHost.Ref
            GenesisSha = $policy.ControlPlane.VmToHost.GenesisCommitSha
        }
        Automation = [pscustomobject][ordered]@{
            IntervalMinutes = [long]$policy.Automation.IntervalMinutes
            HostAutomationId = $policy.Automation.Host.AutomationId
            HostInitialStatus = $policy.Automation.Host.InitialStatus
            VmAutomationId = $policy.Automation.Vm.AutomationId
            VmInitialStatus = $policy.Automation.Vm.InitialStatus
            VmMustBeCreatedOnDevice = [bool]$policy.Automation.Vm.MustBeCreatedOnVmDevice
        }
        Envelope = [pscustomobject][ordered]@{
            MaximumAgeSeconds = [long]$policy.Envelope.MaximumAgeSec
            MaximumClockSkewSeconds = [long]$policy.Envelope.MaximumClockSkewSec
        }
        SshTrust = [pscustomobject][ordered]@{
            GitHubHost = $policy.SshTrust.GitHubHost
            OpenSshToolId = $policy.SshTrust.OpenSshToolId
            OpenSshVmPath = $policy.SshTrust.OpenSshVmPath
            KnownHostsPath = 'payload/git/operator/fast-lane/trust/github-known-hosts'
            KnownHostsSha256 = $policy.SshTrust.KnownHostsSha256
            StrictHostKeyCheckingRequired = [bool]$policy.SshTrust.StrictHostKeyCheckingRequired
        }
    }
}

function New-CddsiFastLaneNegativePermissionRunbook {
    [CmdletBinding()]
    param()

    $runbook = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-fast-lane-negative-permission-runbook-v1'
        Purpose = 'VM_ROLE_NEGATIVE_PERMISSION_VALIDATION'
        Cases = @(
            [pscustomobject][ordered]@{ Sequence = 1; Identity = 'VmTester'; Target = 'ProductRepository'; Operation = 'FetchExactCommit'; Expected = 'ALLOWED' },
            [pscustomobject][ordered]@{ Sequence = 2; Identity = 'VmTester'; Target = 'ProductRepository'; Operation = 'Push'; Expected = 'DENIED' },
            [pscustomobject][ordered]@{ Sequence = 3; Identity = 'VmTester'; Target = 'ProductRepository'; Operation = 'CreateBranchTagReleasePrOrWorkflowDispatch'; Expected = 'DENIED' },
            [pscustomobject][ordered]@{ Sequence = 4; Identity = 'VmTester'; Target = 'HostToVmRepository'; Operation = 'Append'; Expected = 'DENIED' },
            [pscustomobject][ordered]@{ Sequence = 5; Identity = 'VmTester'; Target = 'VmToHostRepository'; Operation = 'AppendNewMessage'; Expected = 'ALLOWED' },
            [pscustomobject][ordered]@{ Sequence = 6; Identity = 'VmTester'; Target = 'VmToHostRepository'; Operation = 'ForcePushDeleteOrRewritePublishedMessage'; Expected = 'DENIED' }
        )
        SuccessCriteria = [pscustomobject][ordered]@{
            AllCasesObserved = $true; ProductWriteDenied = $true; WrongDirectionWriteDenied = $true
            HistoryRewriteDenied = $true; SecretFindingCount = 0
        }
        BindingToken = $null
    }
    $payload = [ordered]@{}
    foreach ($property in $runbook.PSObject.Properties) { if ($property.Name -cne 'BindingToken') { $payload[$property.Name] = $property.Value } }
    $runbook.BindingToken = Get-CddsiFastLaneOnboardingBindingToken -Value $payload
    return $runbook
}

function New-CddsiFastLaneUnattendedSmokeRunbook {
    [CmdletBinding()]
    param()

    $runbook = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-fast-lane-unattended-smoke-runbook-v1'
        Purpose = 'DIAGNOSTIC_ONLY_UNATTENDED_FAST_LANE_SMOKE'
        Preconditions = [pscustomobject][ordered]@{
            ExactCommitVerified = $true; NegativePermissionsPassed = $true; ResetPolicyFrozen = $true
            PayloadExecutionForbidden = $true; SingleActiveCycle = $true
        }
        Steps = @(
            [pscustomobject][ordered]@{ Sequence = 1; Sender = 'HostCoordinator'; MessageType = 'TEST_REQUEST'; Outbox = 'host-to-vm'; ExpectedState = 'TEST_REQUESTED' },
            [pscustomobject][ordered]@{ Sequence = 2; Sender = 'VmTester'; MessageType = 'VM_ACK'; Outbox = 'vm-to-host'; ExpectedState = 'VM_ACKED' },
            [pscustomobject][ordered]@{ Sequence = 3; Sender = 'VmTester'; MessageType = 'CLEAN_READY'; Outbox = 'vm-to-host'; ExpectedState = 'CLEAN_READY' },
            [pscustomobject][ordered]@{ Sequence = 4; Sender = 'VmTester'; MessageType = 'TEST_STARTED'; Outbox = 'vm-to-host'; ExpectedState = 'TEST_RUNNING' },
            [pscustomobject][ordered]@{ Sequence = 5; Sender = 'VmTester'; MessageType = 'TEST_RESULT'; Outbox = 'vm-to-host'; ExpectedState = 'TEST_PASSED_OR_FAILED_OR_BLOCKED' },
            [pscustomobject][ordered]@{ Sequence = 6; Sender = 'HostCoordinator'; MessageType = 'HOST_ACK'; Outbox = 'host-to-vm'; ExpectedState = 'HOST_ACKED' }
        )
        RequiredAssertions = [pscustomobject][ordered]@{
            MinutePolling = $true; PreviousHashAndSequenceVerified = $true; DuplicateRejected = $true
            StopHonored = $true; ProductCodeUnchanged = $true; HostProductLiveCount = 0
            SecretFindingCount = 0; ResultClass = 'DIAGNOSTIC_ONLY'
        }
        BindingToken = $null
    }
    $payload = [ordered]@{}
    foreach ($property in $runbook.PSObject.Properties) { if ($property.Name -cne 'BindingToken') { $payload[$property.Name] = $property.Value } }
    $runbook.BindingToken = Get-CddsiFastLaneOnboardingBindingToken -Value $payload
    return $runbook
}

function Copy-CddsiFastLaneOnboardingFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$SourcePath,
        [Parameter(Mandatory = $true)][string]$DestinationPath,
        [Parameter(Mandatory = $true)][string]$SandboxRoot
    )

    $parent = Split-Path -Parent $DestinationPath
    [void][System.IO.Directory]::CreateDirectory($parent)
    Assert-CddsiNoReparsePath -Path $parent -StopRoot $SandboxRoot
    $source = $null
    $destination = $null
    try {
        $source = [System.IO.File]::Open($SourcePath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
        $destination = [System.IO.File]::Open($DestinationPath, [System.IO.FileMode]::CreateNew, [System.IO.FileAccess]::Write, [System.IO.FileShare]::None)
        $source.CopyTo($destination)
        $destination.Flush()
    }
    finally {
        if ($null -ne $destination) { $destination.Dispose() }
        if ($null -ne $source) { $source.Dispose() }
    }
}

function Test-CddsiFastLaneOnboardingStoreZip {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][int]$ExpectedEntryCount
    )

    $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $reader = [System.IO.BinaryReader]::new($stream)
    $count = 0
    $sawCentralDirectory = $false
    try {
        while ($stream.Position -lt $stream.Length) {
            $signature = $reader.ReadUInt32()
            if ($signature -eq [uint32]0x02014b50) { $sawCentralDirectory = $true; break }
            if ($signature -ne [uint32]0x04034b50) { return $false }
            $null = $reader.ReadUInt16()
            $flags = $reader.ReadUInt16()
            $method = $reader.ReadUInt16()
            $time = $reader.ReadUInt16()
            $date = $reader.ReadUInt16()
            $null = $reader.ReadUInt32()
            $compressed = $reader.ReadUInt32()
            $uncompressed = $reader.ReadUInt32()
            $nameLength = $reader.ReadUInt16()
            $extraLength = $reader.ReadUInt16()
            if ($flags -ne 0x0800 -or $method -ne 0 -or $time -ne 0 -or $date -ne 0x0021 -or
                $compressed -ne $uncompressed -or $nameLength -eq 0 -or $extraLength -ne 0) { return $false }
            $nextPosition = $stream.Position + [long]$nameLength + [long]$extraLength + [long]$compressed
            if ($nextPosition -gt $stream.Length) { return $false }
            $stream.Position = $nextPosition
            $count++
        }
        return ($sawCentralDirectory -and $count -eq $ExpectedEntryCount)
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
}

function Get-CddsiFastLaneOnboardingZipPreflight {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ZipPath)

    $zipLength = [long]([System.IO.FileInfo]::new($ZipPath).Length)
    if ($zipLength -le 0 -or $zipLength -gt $script:CddsiFastLaneOnboardingMaximumBundleBytes) {
        throw 'VM onboarding ZIP length is outside the fixed bundle limit.'
    }
    Initialize-CddsiReleaseCompression
    $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        $entries = @($archive.Entries)
        if ($entries.Count -lt 1 -or $entries.Count -gt $script:CddsiFastLaneOnboardingMaximumEntryCount) {
            throw 'VM onboarding ZIP entry count is outside the fixed limit.'
        }
        $names = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
        $entryLengths = [ordered]@{}
        [long]$totalUncompressed = 0
        foreach ($entry in $entries) {
            if ([string]::IsNullOrEmpty($entry.Name) -or -not $names.Add([string]$entry.FullName)) {
                throw 'VM onboarding ZIP contains a directory, duplicate, or case-alias entry.'
            }
            if ([long]$entry.Length -lt 0 -or [long]$entry.CompressedLength -lt 0 -or
                [long]$entry.Length -gt $script:CddsiFastLaneOnboardingMaximumFileBytes -or
                [long]$entry.CompressedLength -gt $script:CddsiFastLaneOnboardingMaximumFileBytes) {
                throw 'VM onboarding ZIP entry length is outside the fixed limit.'
            }
            $entryLengths[[string]$entry.FullName] = [long]$entry.Length
            $totalUncompressed += [long]$entry.Length
            if ($totalUncompressed -gt $script:CddsiFastLaneOnboardingMaximumBundleBytes) {
                throw 'VM onboarding ZIP aggregate content exceeds the fixed bundle limit.'
            }
        }
        return [pscustomobject][ordered]@{
            ZipLengthBytes = $zipLength
            EntryCount = $entries.Count
            TotalUncompressedBytes = $totalUncompressed
            EntryLengths = $entryLengths
        }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $stream.Dispose()
    }
}

function Get-CddsiFastLaneOnboardingZipJson {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ZipPath,
        [Parameter(Mandatory = $true)][string]$EntryName
    )

    Initialize-CddsiReleaseCompression
    $stream = [System.IO.File]::Open($ZipPath, [System.IO.FileMode]::Open, [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $archive = $null
    try {
        $archive = [System.IO.Compression.ZipArchive]::new($stream, [System.IO.Compression.ZipArchiveMode]::Read, $false)
        $matches = @($archive.Entries | Where-Object { $_.FullName -ceq $EntryName })
        if ($matches.Count -ne 1) { throw ('VM onboarding ZIP is missing exact entry: {0}' -f $EntryName) }
        if ([long]$matches[0].Length -gt $script:CddsiFastLaneOnboardingMaximumFileBytes) {
            throw ('VM onboarding ZIP JSON entry exceeds the fixed limit: {0}' -f $EntryName)
        }
        $entryStream = $matches[0].Open()
        $reader = [System.IO.StreamReader]::new($entryStream, (New-Object System.Text.UTF8Encoding($false, $true)), $true)
        try { return $reader.ReadToEnd() }
        finally { $reader.Dispose(); $entryStream.Dispose() }
    }
    finally {
        if ($null -ne $archive) { $archive.Dispose() }
        $stream.Dispose()
    }
}

function Test-CddsiFastLaneVmOnboardingBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$ZipPath
    )

    Assert-CddsiFastLaneOnboardingSandbox -Sandbox $Sandbox
    $zipFull = Get-CddsiCanonicalPath -Path $ZipPath
    if (-not (Test-CddsiPathWithinRoot -Path $zipFull -Root $Sandbox.Root) -or -not [System.IO.File]::Exists($zipFull)) {
        throw 'VM onboarding ZIP is unavailable or outside the caller-owned HostSandbox.'
    }
    Assert-CddsiNoReparsePath -Path $zipFull -StopRoot $Sandbox.Root
    $preflight = Get-CddsiFastLaneOnboardingZipPreflight -ZipPath $zipFull
    if (-not (Test-CddsiFastLaneOnboardingStoreZip -ZipPath $zipFull -ExpectedEntryCount $preflight.EntryCount)) {
        throw 'VM onboarding ZIP is not the deterministic Store ZIP contract.'
    }
    $manifestText = Get-CddsiFastLaneOnboardingZipJson -ZipPath $zipFull -EntryName $script:CddsiFastLaneOnboardingManifestPath
    $inventoryText = Get-CddsiFastLaneOnboardingZipJson -ZipPath $zipFull -EntryName $script:CddsiFastLaneOnboardingInventoryPath
    $manifest = $manifestText | ConvertFrom-Json -ErrorAction Stop
    $inventory = $inventoryText | ConvertFrom-Json -ErrorAction Stop
    if ($manifestText -notmatch '"EntryTimestampUtc":"1980-01-01T00:00:00Z"') {
        throw 'VM onboarding manifest ZIP timestamp is not the fixed canonical value.'
    }
    # PowerShell 7 may infer ISO JSON strings as DateTime while Windows
    # PowerShell 5.1 leaves them as strings. Normalize the one frozen timestamp
    # before the cross-engine canonical round trip.
    $manifest.Zip.EntryTimestampUtc = $script:CddsiFastLaneOnboardingFixedTimestampUtc
    $canonicalManifestText = (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $manifest) + "`n"
    $canonicalInventoryText = (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $inventory) + "`n"
    if ($manifestText -cne $canonicalManifestText -or $inventoryText -cne $canonicalInventoryText) {
        $label = if ($manifestText -cne $canonicalManifestText) { 'manifest' } else { 'inventory' }
        throw ('VM onboarding {0} is not canonical JSON.' -f $label)
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest -Expected @(
        'SchemaVersion', 'ContractVersion', 'Purpose', 'EvidenceClass', 'Mode', 'Policy', 'Product',
        'ControlRepositories', 'FileSets', 'Tools', 'Constraints', 'Automation', 'Runbooks',
        'Inventory', 'Zip', 'ManifestBindingToken'
    )) -or $manifest.SchemaVersion -ne 1 -or
        $manifest.ContractVersion -cne 'cddsi-fast-lane-vm-onboarding-manifest-v1' -or
        $manifest.Purpose -cne 'P10A_0A_VM_ONBOARDING_DIAGNOSTIC_ONLY' -or
        $manifest.EvidenceClass -cne 'DIAGNOSTIC_ONLY' -or $manifest.Mode -cne 'DryRun') {
        throw 'VM onboarding manifest schema or classification is invalid.'
    }
    $manifestPayload = [ordered]@{}
    foreach ($property in $manifest.PSObject.Properties) { if ($property.Name -cne 'ManifestBindingToken') { $manifestPayload[$property.Name] = $property.Value } }
    if ($manifest.ManifestBindingToken -cne (Get-CddsiFastLaneOnboardingBindingToken -Value $manifestPayload)) {
        throw 'VM onboarding manifest binding token differs.'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Policy -Expected @(
        'Path', 'Sha256', 'ProtocolVersion', 'ProductRepository', 'HostToVmRepository',
            'VmToHostRepository', 'Automation', 'Envelope', 'SshTrust'
        )) -or
        $manifest.Policy.Path -cne 'payload/git/config/fast-lane-policy.psd1' -or
        $manifest.Policy.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $manifest.Policy.ProtocolVersion -cne 'cddsi-vm-test-relay-v1') {
        throw 'VM onboarding committed policy binding is invalid.'
    }
    $policyRepositorySchemas = [ordered]@{
        ProductRepository = @('RepositoryToken', 'Id', 'NodeId', 'FullName', 'HostWriteRefPattern')
        HostToVmRepository = @('RepositoryToken', 'Id', 'NodeId', 'FullName', 'Ref', 'GenesisSha')
        VmToHostRepository = @('RepositoryToken', 'Id', 'NodeId', 'FullName', 'Ref', 'GenesisSha')
    }
    foreach ($name in $policyRepositorySchemas.Keys) {
        $repository = $manifest.Policy.$name
        if (-not (Test-CddsiExactPropertySet -InputObject $repository -Expected $policyRepositorySchemas[$name]) -or
            $repository.RepositoryToken -cne ('github.com/' + $repository.FullName) -or
            ($repository.Id -isnot [int] -and $repository.Id -isnot [long]) -or [long]$repository.Id -lt 1 -or
            $repository.NodeId -cnotmatch '^[A-Za-z0-9_=-]{4,128}$') {
            throw ('VM onboarding policy repository binding is invalid: {0}' -f $name)
        }
    }
    if ($manifest.Policy.HostToVmRepository.Ref -cne 'refs/heads/main' -or
        $manifest.Policy.VmToHostRepository.Ref -cne 'refs/heads/main' -or
        $manifest.Policy.HostToVmRepository.GenesisSha -cnotmatch '^[a-f0-9]{40}$' -or
        $manifest.Policy.VmToHostRepository.GenesisSha -cnotmatch '^[a-f0-9]{40}$' -or
        $manifest.Policy.ProductRepository.HostWriteRefPattern -cne 'refs/heads/codex/repair/*') {
        throw 'VM onboarding policy ref or genesis binding is invalid.'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Policy.Automation -Expected @(
            'IntervalMinutes', 'HostAutomationId', 'HostInitialStatus', 'VmAutomationId',
            'VmInitialStatus', 'VmMustBeCreatedOnDevice'
        )) -or
        -not (Test-CddsiExactPropertySet -InputObject $manifest.Policy.Envelope -Expected @(
            'MaximumAgeSeconds', 'MaximumClockSkewSeconds'
        )) -or
        -not (Test-CddsiExactPropertySet -InputObject $manifest.Policy.SshTrust -Expected @(
            'GitHubHost', 'OpenSshToolId', 'OpenSshVmPath', 'KnownHostsPath',
            'KnownHostsSha256', 'StrictHostKeyCheckingRequired'
        )) -or
        $manifest.Policy.SshTrust.GitHubHost -cne 'github.com' -or
        $manifest.Policy.SshTrust.OpenSshToolId -cne 'OpenSSH' -or
        $manifest.Policy.SshTrust.OpenSshVmPath -cne '%PROGRAMFILES%\Git\usr\bin\ssh.exe' -or
        $manifest.Policy.SshTrust.KnownHostsPath -cne 'payload/git/operator/fast-lane/trust/github-known-hosts' -or
        $manifest.Policy.SshTrust.KnownHostsSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        -not $manifest.Policy.SshTrust.StrictHostKeyCheckingRequired) {
        throw 'VM onboarding policy automation or envelope binding is invalid.'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Product -Expected @(
            'Repository', 'CommitSha', 'RepairRef', 'TreeSha', 'SourceCommitVerified',
            'GitExecutableSha256', 'VmAccess', 'CodeWriteAuthority'
        )) -or
        -not (Test-CddsiExactPropertySet -InputObject $manifest.Product.Repository -Expected @('Id', 'NodeId', 'FullName')) -or
        $manifest.Product.Repository.FullName -cne $script:CddsiFastLaneOnboardingRepositoryNames.Product -or
        $manifest.ControlRepositories.HostToVm.Repository.FullName -cne $script:CddsiFastLaneOnboardingRepositoryNames.HostToVm -or
        $manifest.ControlRepositories.VmToHost.Repository.FullName -cne $script:CddsiFastLaneOnboardingRepositoryNames.VmToHost -or
        $manifest.Product.CommitSha -cnotmatch '^[a-f0-9]{40}$' -or
        $manifest.Product.TreeSha -cnotmatch '^[a-f0-9]{40}$' -or
        $manifest.Product.SourceCommitVerified -isnot [bool] -or -not $manifest.Product.SourceCommitVerified -or
        $manifest.Product.GitExecutableSha256 -cnotmatch '^[a-f0-9]{64}$' -or
        $manifest.Product.VmAccess -cne 'READ_ONLY_EXACT_COMMIT' -or
        $manifest.Product.CodeWriteAuthority -cne 'HOST_ONLY_REPAIR_REF') {
        throw 'VM onboarding repository or commit identity is invalid.'
    }
    if ([long]$manifest.Product.Repository.Id -ne [long]$manifest.Policy.ProductRepository.Id -or
        $manifest.Product.Repository.NodeId -cne $manifest.Policy.ProductRepository.NodeId -or
        $manifest.Product.Repository.FullName -cne $manifest.Policy.ProductRepository.FullName -or
        $manifest.Product.RepairRef -cnotlike $manifest.Policy.ProductRepository.HostWriteRefPattern -or
        [long]$manifest.ControlRepositories.HostToVm.Repository.Id -ne [long]$manifest.Policy.HostToVmRepository.Id -or
        $manifest.ControlRepositories.HostToVm.Repository.NodeId -cne $manifest.Policy.HostToVmRepository.NodeId -or
        $manifest.ControlRepositories.HostToVm.GenesisSha -cne $manifest.Policy.HostToVmRepository.GenesisSha -or
        [long]$manifest.ControlRepositories.VmToHost.Repository.Id -ne [long]$manifest.Policy.VmToHostRepository.Id -or
        $manifest.ControlRepositories.VmToHost.Repository.NodeId -cne $manifest.Policy.VmToHostRepository.NodeId -or
        $manifest.ControlRepositories.VmToHost.GenesisSha -cne $manifest.Policy.VmToHostRepository.GenesisSha) {
        throw 'VM onboarding manifest repository facts contradict the committed policy binding.'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $inventory -Expected @(
            'SchemaVersion', 'ContractVersion', 'EntryCount', 'Entries',
            'BundleContentDigestSha256', 'InventoryBindingToken'
        )) -or $inventory.SchemaVersion -ne 1 -or
        $inventory.ContractVersion -cne 'cddsi-fast-lane-vm-onboarding-inventory-v1') {
        throw 'VM onboarding inventory schema is invalid.'
    }
    $entries = @($inventory.Entries)
    if (($inventory.EntryCount -isnot [int] -and $inventory.EntryCount -isnot [long]) -or
        [long]$inventory.EntryCount -ne $entries.Count -or $entries.Count -gt $script:CddsiFastLaneOnboardingMaximumEntryCount) {
        throw 'VM onboarding inventory entry count differs.'
    }
    $allowedCategories = @('Git', 'Runtime', 'Reset', 'Prompt', 'Runbook', 'GeneratedRunbook')
    for ($entryIndex = 0; $entryIndex -lt $entries.Count; $entryIndex++) {
        $entry = $entries[$entryIndex]
        if (-not (Test-CddsiExactPropertySet -InputObject $entry -Expected @(
                'Ordinal', 'Category', 'Path', 'SourcePath', 'Sha256', 'GitBlobSha', 'LengthBytes'
            )) -or
            ($entry.Ordinal -isnot [int] -and $entry.Ordinal -isnot [long]) -or
            [long]$entry.Ordinal -ne ($entryIndex + 1) -or
            $entry.Category -isnot [string] -or $allowedCategories -cnotcontains $entry.Category -or
            $entry.Path -isnot [string] -or $entry.Sha256 -cnotmatch '^[a-f0-9]{64}$' -or
            ($entry.LengthBytes -isnot [int] -and $entry.LengthBytes -isnot [long]) -or
            [long]$entry.LengthBytes -lt 0 -or
            [long]$entry.LengthBytes -gt $script:CddsiFastLaneOnboardingMaximumFileBytes) {
            throw 'VM onboarding inventory entry schema is invalid.'
        }
        $canonicalEntryPath = ConvertTo-CddsiReleaseRelativePath -Path ([string]$entry.Path)
        if ($canonicalEntryPath -cne [string]$entry.Path -or
            -not $preflight.EntryLengths.Contains([string]$entry.Path) -or
            [long]$preflight.EntryLengths[[string]$entry.Path] -ne [long]$entry.LengthBytes) {
            throw 'VM onboarding inventory entry path or length differs.'
        }
        if ($entry.Category -ceq 'GeneratedRunbook') {
            if ($null -ne $entry.SourcePath -or $null -ne $entry.GitBlobSha) {
                throw 'VM onboarding generated entry contains a source binding.'
            }
        }
        elseif ($entry.SourcePath -isnot [string] -or $entry.GitBlobSha -cnotmatch '^[a-f0-9]{40}$') {
            throw 'VM onboarding source entry is missing its committed blob binding.'
        }
    }
    $policyEntries = @($entries | Where-Object {
        $_.Category -ceq 'Git' -and $_.Path -ceq $manifest.Policy.Path -and
        $_.SourcePath -ceq 'config/fast-lane-policy.psd1'
    })
    if ($policyEntries.Count -ne 1 -or $policyEntries[0].Sha256 -cne $manifest.Policy.Sha256) {
        throw 'VM onboarding committed policy hash is not bound to the inventory entry.'
    }
    $knownHostsEntries = @($entries | Where-Object {
        $_.Category -ceq 'Git' -and $_.Path -ceq $manifest.Policy.SshTrust.KnownHostsPath -and
        $_.SourcePath -ceq 'operator/fast-lane/trust/github-known-hosts'
    })
    if ($knownHostsEntries.Count -ne 1 -or
        $knownHostsEntries[0].Sha256 -cne $manifest.Policy.SshTrust.KnownHostsSha256) {
        throw 'VM onboarding GitHub known-hosts hash is not bound to the inventory entry.'
    }
    $inventoryPayload = [ordered]@{}
    foreach ($property in $inventory.PSObject.Properties) { if ($property.Name -cne 'InventoryBindingToken') { $inventoryPayload[$property.Name] = $property.Value } }
    if ($inventory.InventoryBindingToken -cne (Get-CddsiFastLaneOnboardingBindingToken -Value $inventoryPayload)) {
        throw 'VM onboarding inventory binding token differs.'
    }
    $contentPayload = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-onboarding-content-v1'; Entries = @($inventory.Entries)
    }
    $contentDigest = Get-CddsiFastLaneOnboardingBindingToken -Value $contentPayload
    if ($contentDigest -cne $inventory.BundleContentDigestSha256 -or
        $contentDigest -cne $manifest.Inventory.BundleContentDigestSha256) {
        throw 'VM onboarding bundle content digest differs.'
    }
    $inventoryBytes = (New-Object System.Text.UTF8Encoding($false)).GetBytes($inventoryText)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { $inventorySha = ([BitConverter]::ToString($sha.ComputeHash($inventoryBytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
    if ($inventorySha -cne $manifest.Inventory.Sha256) { throw 'VM onboarding inventory SHA-256 differs.' }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Inventory -Expected @(
            'Path', 'Sha256', 'EntryCount', 'BundleContentDigestSha256', 'InventoryBindingToken'
        )) -or
        $manifest.Inventory.Path -cne $script:CddsiFastLaneOnboardingInventoryPath -or
        [long]$manifest.Inventory.EntryCount -ne $entries.Count -or
        $manifest.Inventory.InventoryBindingToken -cne $inventory.InventoryBindingToken) {
        throw 'VM onboarding manifest inventory reference differs.'
    }

    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.FileSets -Expected @('Git', 'Runtime', 'Reset', 'Prompt', 'Runbook'))) {
        throw 'VM onboarding manifest file-set schema is invalid.'
    }
    foreach ($category in @('Git', 'Runtime', 'Reset', 'Prompt', 'Runbook')) {
        $expectedFileSet = @($entries | Where-Object Category -eq $category | ForEach-Object {
            [pscustomobject][ordered]@{
                Path = $_.SourcePath; BundlePath = $_.Path; Sha256 = $_.Sha256; GitBlobSha = $_.GitBlobSha
            }
        })
        $actualFileSet = @($manifest.FileSets.$category)
        if ((Get-CddsiFastLaneOnboardingBindingToken -Value $actualFileSet) -cne
            (Get-CddsiFastLaneOnboardingBindingToken -Value $expectedFileSet)) {
            throw ('VM onboarding manifest file set differs: {0}' -f $category)
        }
    }

    $requiredTools = [ordered]@{
        Git = '%PROGRAMFILES%\Git\cmd\git.exe'
        OpenSSH = '%PROGRAMFILES%\Git\usr\bin\ssh.exe'
        PowerShell7 = '%PROGRAMFILES%\PowerShell\7\pwsh.exe'
        WindowsPowerShell = '%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe'
    }
    $tools = @($manifest.Tools)
    if ($tools.Count -ne $requiredTools.Count) { throw 'VM onboarding manifest tool set differs.' }
    foreach ($toolId in $requiredTools.Keys) {
        $matches = @($tools | Where-Object { $_.ToolId -ceq $toolId })
        if ($matches.Count -ne 1 -or
            -not (Test-CddsiExactPropertySet -InputObject $matches[0] -Expected @('ToolId', 'VmPath', 'Sha256')) -or
            $matches[0].VmPath -cne $requiredTools[$toolId] -or
            $matches[0].Sha256 -cnotmatch '^[a-f0-9]{64}$') {
            throw ('VM onboarding manifest fixed tool binding differs: {0}' -f $toolId)
        }
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Automation -Expected @(
            'IntervalMinutes', 'HostAutomationId', 'HostInitialStatus', 'VmAutomationId',
            'VmInitialStatus', 'VmMustBeCreatedOnDevice', 'SingleActiveCycle', 'CompareAndSwapRequired',
            'SequenceAndPreviousHashRequired', 'MaximumMessageAgeSeconds',
            'MaximumClockSkewSeconds', 'HostRole', 'VmRole', 'StopRequired', 'ResultClass'
        )) -or
        [long]$manifest.Automation.IntervalMinutes -ne [long]$manifest.Policy.Automation.IntervalMinutes -or
        $manifest.Automation.HostAutomationId -cne $manifest.Policy.Automation.HostAutomationId -or
        $manifest.Automation.HostInitialStatus -cne $manifest.Policy.Automation.HostInitialStatus -or
        $manifest.Automation.VmAutomationId -cne $manifest.Policy.Automation.VmAutomationId -or
        $manifest.Automation.VmInitialStatus -cne $manifest.Policy.Automation.VmInitialStatus -or
        $manifest.Automation.VmMustBeCreatedOnDevice -ne $manifest.Policy.Automation.VmMustBeCreatedOnDevice -or
        [long]$manifest.Automation.MaximumMessageAgeSeconds -ne [long]$manifest.Policy.Envelope.MaximumAgeSeconds -or
        [long]$manifest.Automation.MaximumClockSkewSeconds -ne [long]$manifest.Policy.Envelope.MaximumClockSkewSeconds -or
        $manifest.Automation.HostInitialStatus -cne 'PAUSED' -or
        $manifest.Automation.VmInitialStatus -cne 'PAUSED' -or
        -not $manifest.Automation.VmMustBeCreatedOnDevice -or
        $manifest.Automation.ResultClass -cne 'DIAGNOSTIC_ONLY') {
        throw 'VM onboarding manifest automation facts contradict the committed policy binding.'
    }

    $expectedConstraints = [pscustomobject][ordered]@{
        VmMayEditProductCode = $false; VmMayCommitOrPushProductCode = $false
        HostIsOnlyProductCodeWriter = $true; HostMayRunProductLive = $false
        VmMayChangeRunbook = $false; VmMayBuildCandidate = $false
        PayloadTextMayExecute = $false; AutoMerge = $false; AutoPromotion = $false; AutoRelease = $false
        CredentialsIncluded = $false; UserPathsIncluded = $false; SecretFindingCount = 0
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Constraints -Expected @(
            'VmMayEditProductCode', 'VmMayCommitOrPushProductCode', 'HostIsOnlyProductCodeWriter',
            'HostMayRunProductLive', 'VmMayChangeRunbook', 'VmMayBuildCandidate', 'PayloadTextMayExecute',
            'AutoMerge', 'AutoPromotion', 'AutoRelease', 'CredentialsIncluded', 'UserPathsIncluded',
            'SecretFindingCount'
        )) -or
        (Get-CddsiFastLaneOnboardingBindingToken -Value $manifest.Constraints) -cne
        (Get-CddsiFastLaneOnboardingBindingToken -Value $expectedConstraints)) {
        throw 'VM onboarding manifest constraints differ.'
    }

    if (-not (Test-CddsiExactPropertySet -InputObject $manifest.Zip -Expected @(
            'Format', 'Compression', 'EntryTimestampUtc', 'EntryOrder', 'ExpectedEntries'
        )) -or
        $manifest.Zip.Format -cne 'ZIP32' -or $manifest.Zip.Compression -cne 'Store' -or
        $manifest.Zip.EntryTimestampUtc -cne $script:CddsiFastLaneOnboardingFixedTimestampUtc -or
        $manifest.Zip.EntryOrder -cne 'Ordinal') {
        throw 'VM onboarding manifest ZIP contract differs.'
    }
    $expectedEntries = @($script:CddsiFastLaneOnboardingManifestPath, $script:CddsiFastLaneOnboardingInventoryPath) + @($entries | ForEach-Object Path)
    $expectedEntries = [string[]]$expectedEntries
    [Array]::Sort($expectedEntries, [StringComparer]::Ordinal)
    $manifestExpectedEntries = [string[]]@($manifest.Zip.ExpectedEntries)
    if (($manifestExpectedEntries -join "`n") -cne ($expectedEntries -join "`n") -or
        $preflight.EntryCount -ne $expectedEntries.Count) {
        throw 'VM onboarding manifest expected ZIP entries differ.'
    }
    $zipEvidence = Test-CddsiReleaseZipLayer -ZipPath $zipFull -PackageFiles $expectedEntries -SandboxRoot $Sandbox.Root
    foreach ($entry in $entries) {
        if ([string]$zipEvidence.ContentHashes[[string]$entry.Path] -cne [string]$entry.Sha256) {
            throw ('VM onboarding ZIP entry hash differs: {0}' -f $entry.Path)
        }
    }
    if (-not (Test-CddsiFastLaneOnboardingStoreZip -ZipPath $zipFull -ExpectedEntryCount $expectedEntries.Count)) {
        throw 'VM onboarding ZIP is not the deterministic Store ZIP contract.'
    }
    return [pscustomobject][ordered]@{
        IsValid = $true; EntryCount = $expectedEntries.Count; InventoryExact = $true; SecretFindings = 0
        Compression = 'Store'; EntryTimestampUtc = $script:CddsiFastLaneOnboardingFixedTimestampUtc
        BundleContentDigestSha256 = $contentDigest; ManifestBindingToken = $manifest.ManifestBindingToken
    }
}

function New-CddsiFastLaneVmOnboardingBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Sandbox,
        [Parameter(Mandatory = $true)][string]$SourceRoot,
        [Parameter(Mandatory = $true)][string]$SourceGitExecutable,
        [Parameter(Mandatory = $true)][string]$SourceGitExecutableSha256,
        [Parameter(Mandatory = $true)][string]$OutputDirectory,
        [Parameter(Mandatory = $true)][string]$ProductCommitSha,
        [Parameter(Mandatory = $true)][string]$RepairRef,
        [Parameter(Mandatory = $true)][long]$ProductRepositoryId,
        [Parameter(Mandatory = $true)][string]$ProductRepositoryNodeId,
        [Parameter(Mandatory = $true)][string]$ProductRepositoryFullName,
        [Parameter(Mandatory = $true)][long]$HostToVmRepositoryId,
        [Parameter(Mandatory = $true)][string]$HostToVmRepositoryNodeId,
        [Parameter(Mandatory = $true)][string]$HostToVmRepositoryFullName,
        [Parameter(Mandatory = $true)][long]$VmToHostRepositoryId,
        [Parameter(Mandatory = $true)][string]$VmToHostRepositoryNodeId,
        [Parameter(Mandatory = $true)][string]$VmToHostRepositoryFullName,
        [Parameter(Mandatory = $true)][string]$HostToVmGenesisSha,
        [Parameter(Mandatory = $true)][string]$VmToHostGenesisSha,
        [Parameter(Mandatory = $true)][object[]]$GitFileSpecifications,
        [Parameter(Mandatory = $true)][object[]]$RuntimeFileSpecifications,
        [Parameter(Mandatory = $true)][object[]]$ResetFileSpecifications,
        [Parameter(Mandatory = $true)][object[]]$PromptFileSpecifications,
        [Parameter(Mandatory = $true)][object[]]$RunbookFileSpecifications,
        [Parameter(Mandatory = $true)][object[]]$ToolSpecifications,
        [ValidateSet('DryRun')][string]$Mode = 'DryRun'
    )

    Assert-CddsiFastLaneOnboardingSandbox -Sandbox $Sandbox
    if ($ProductCommitSha -cnotmatch '^[a-f0-9]{40}$') { throw 'VM onboarding product commit SHA must be an exact lowercase SHA-1.' }
    if ($RepairRef -cnotmatch '^refs/heads/codex/repair/[a-z0-9][a-z0-9._/-]{0,119}$' -or
        $RepairRef.Contains('..') -or $RepairRef.Contains('//') -or $RepairRef.EndsWith('.lock', [StringComparison]::Ordinal)) {
        throw 'VM onboarding repair ref is invalid.'
    }
    foreach ($genesisSha in @($HostToVmGenesisSha, $VmToHostGenesisSha)) {
        if ($genesisSha -cnotmatch '^[a-f0-9]{40}$') { throw 'VM onboarding control genesis SHA must be an exact lowercase SHA-1.' }
    }
    if ($HostToVmGenesisSha -ceq $VmToHostGenesisSha) { throw 'VM onboarding directional control genesis SHAs must be distinct.' }
    $productRepository = Assert-CddsiFastLaneOnboardingRepositoryIdentity -Role Product -Id $ProductRepositoryId `
        -NodeId $ProductRepositoryNodeId -FullName $ProductRepositoryFullName -ExpectedFullName $script:CddsiFastLaneOnboardingRepositoryNames.Product
    $hostToVmRepository = Assert-CddsiFastLaneOnboardingRepositoryIdentity -Role HostToVm -Id $HostToVmRepositoryId `
        -NodeId $HostToVmRepositoryNodeId -FullName $HostToVmRepositoryFullName -ExpectedFullName $script:CddsiFastLaneOnboardingRepositoryNames.HostToVm
    $vmToHostRepository = Assert-CddsiFastLaneOnboardingRepositoryIdentity -Role VmToHost -Id $VmToHostRepositoryId `
        -NodeId $VmToHostRepositoryNodeId -FullName $VmToHostRepositoryFullName -ExpectedFullName $script:CddsiFastLaneOnboardingRepositoryNames.VmToHost
    if (@(@($productRepository.Id, $hostToVmRepository.Id, $vmToHostRepository.Id) | Select-Object -Unique).Count -ne 3 -or
        @(@($productRepository.NodeId, $hostToVmRepository.NodeId, $vmToHostRepository.NodeId) | Select-Object -Unique).Count -ne 3) {
        throw 'VM onboarding repository identities must be distinct.'
    }
    $sourceFull = Get-CddsiCanonicalPath -Path $SourceRoot
    if (-not [System.IO.Directory]::Exists($sourceFull)) { throw 'VM onboarding source root is unavailable.' }
    Assert-CddsiNoReparsePath -Path $sourceFull -StopRoot ([System.IO.Path]::GetPathRoot($sourceFull))
    $outputFull = Assert-CddsiFastLaneOnboardingOutputPath -Sandbox $Sandbox -OutputDirectory $OutputDirectory
    $outputCreated = $false
    try {
    $sourceGitContext = New-CddsiFastLaneOnboardingSourceGitContext `
        -GitExecutable $SourceGitExecutable -GitExecutableSha256 $SourceGitExecutableSha256 `
        -SourceRoot $sourceFull -SandboxRoot $Sandbox.Root
    $sourceBinding = Assert-CddsiFastLaneOnboardingSourceRepository `
        -Context $sourceGitContext -ProductCommitSha $ProductCommitSha
    $tools = @(ConvertTo-CddsiFastLaneOnboardingTools -ToolSpecifications $ToolSpecifications)
    $allFiles = [System.Collections.Generic.List[object]]::new()
    foreach ($set in @(
        [pscustomobject]@{ Category = 'Git'; Specs = $GitFileSpecifications },
        [pscustomobject]@{ Category = 'Runtime'; Specs = $RuntimeFileSpecifications },
        [pscustomobject]@{ Category = 'Reset'; Specs = $ResetFileSpecifications },
        [pscustomobject]@{ Category = 'Prompt'; Specs = $PromptFileSpecifications },
        [pscustomobject]@{ Category = 'Runbook'; Specs = $RunbookFileSpecifications }
    )) {
        foreach ($item in @(ConvertTo-CddsiFastLaneOnboardingFileSet -Category $set.Category `
            -Specifications $set.Specs -SourceRoot $sourceFull -SourceGitContext $sourceGitContext `
            -ProductCommitSha $ProductCommitSha)) {
            $allFiles.Add($item)
        }
    }
    $requiredPaths = [ordered]@{
        Git = @(
            'config/fast-lane-policy.psd1',
            'operator/fast-lane/trust/github-known-hosts'
        )
        Runtime = @(
            'lib/common.ps1',
            'lib/vm-calibration.ps1',
            'lib/vm-test-relay.ps1',
            'operator/fast-lane/invoke-git-outbox.ps1'
        )
        Reset = @(
            'lib/vm-reset.ps1',
            'operator/fast-lane/invoke-vm-reset-live.ps1',
            'operator/fast-lane/providers/windows-vm-reset.ps1'
        )
        Prompt = @('operator/fast-lane/prompts/vm-poll.md')
        Runbook = @(
            'operator/fast-lane/runbooks/negative-permissions.md',
            'operator/fast-lane/runbooks/reset-smoke.md',
            'operator/fast-lane/runbooks/unattended-smoke.md',
            'operator/fast-lane/runbooks/vm-bootstrap.md'
        )
    }
    foreach ($category in $requiredPaths.Keys) {
        $observedPaths = @($allFiles | Where-Object Category -eq $category | ForEach-Object SourcePath)
        foreach ($requiredPath in @($requiredPaths[$category])) {
            if (@($observedPaths | Where-Object { $_ -ceq $requiredPath }).Count -ne 1) {
                throw ('VM onboarding {0} file set must contain the exact required entry: {1}' -f $category, $requiredPath)
            }
        }
    }
    $requiredContentMarkers = [ordered]@{
        'config/fast-lane-policy.psd1' = @(
            'ProtocolVersion',
            'ControlPlane',
            'KnownHostsSha256'
        )
        'operator/fast-lane/trust/github-known-hosts' = @(
            'github.com ssh-ed25519 ',
            'github.com ecdsa-sha2-nistp256 ',
            'github.com ssh-rsa '
        )
        'lib/common.ps1' = @('function Test-CddsiExactPropertySet')
        'lib/vm-calibration.ps1' = @('function ConvertTo-CddsiVmCalibrationCanonicalJson')
        'lib/vm-test-relay.ps1' = @('function Test-CddsiVmTestRelayEnvelope')
        'lib/vm-reset.ps1' = @('function Invoke-CddsiVmGuestReset')
        'operator/fast-lane/invoke-git-outbox.ps1' = @(
            'function Invoke-CddsiFastLaneGitOutbox',
            'cddsi-fast-lane-git-outbox-v1'
        )
        'operator/fast-lane/invoke-vm-reset-live.ps1' = @(
            'function Invoke-CddsiVmResetLiveAdapter',
            'cddsi-vm-reset-live-adapter-result-v1'
        )
        'operator/fast-lane/providers/windows-vm-reset.ps1' = @('cddsi-vm-reset-provider-windows-v2')
        'operator/fast-lane/prompts/vm-poll.md' = @('# VmTester minute poll')
        'operator/fast-lane/runbooks/negative-permissions.md' = @('# VM negative-permission runbook')
        'operator/fast-lane/runbooks/reset-smoke.md' = @('# Deterministic guest-reset smoke runbook')
        'operator/fast-lane/runbooks/unattended-smoke.md' = @('# Unattended Fast Lane smoke runbook')
        'operator/fast-lane/runbooks/vm-bootstrap.md' = @('# VM bootstrap runbook')
    }
    foreach ($requiredPath in $requiredContentMarkers.Keys) {
        $match = @($allFiles | Where-Object SourcePath -eq $requiredPath)
        if ($match.Count -ne 1) { throw ('VM onboarding required file is not unique: {0}' -f $requiredPath) }
        $requiredText = [System.IO.File]::ReadAllText($match[0].FullPath, [System.Text.Encoding]::UTF8)
        foreach ($marker in @($requiredContentMarkers[$requiredPath])) {
            if (-not $requiredText.Contains($marker)) {
                throw ('VM onboarding required file does not match its reviewed purpose: {0}' -f $requiredPath)
            }
        }
    }
    $policyItems = @($allFiles | Where-Object {
        $_.Category -ceq 'Git' -and $_.SourcePath -ceq 'config/fast-lane-policy.psd1'
    })
    if ($policyItems.Count -ne 1) { throw 'VM onboarding committed policy entry is not unique.' }
    $knownHostsItems = @($allFiles | Where-Object {
        $_.Category -ceq 'Git' -and $_.SourcePath -ceq 'operator/fast-lane/trust/github-known-hosts'
    })
    if ($knownHostsItems.Count -ne 1) { throw 'VM onboarding committed GitHub known-hosts entry is not unique.' }
    $policyBinding = Assert-CddsiFastLaneOnboardingPolicyBinding `
        -PolicyPath $policyItems[0].FullPath -PolicySha256 $policyItems[0].Sha256 `
        -KnownHostsSourcePath $knownHostsItems[0].SourcePath -KnownHostsSha256 $knownHostsItems[0].Sha256 `
        -ProductRepository $productRepository -HostToVmRepository $hostToVmRepository `
        -VmToHostRepository $vmToHostRepository -ProductCommitSha $ProductCommitSha `
        -RepairRef $RepairRef -HostToVmGenesisSha $HostToVmGenesisSha `
        -VmToHostGenesisSha $VmToHostGenesisSha
    $sourcePaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    $bundlePaths = [System.Collections.Generic.HashSet[string]]::new([StringComparer]::OrdinalIgnoreCase)
    [long]$totalBytes = 0
    foreach ($item in @($allFiles)) {
        if (-not $sourcePaths.Add($item.SourcePath) -or -not $bundlePaths.Add($item.BundlePath)) {
            throw 'VM onboarding file specifications contain a duplicate or case alias.'
        }
        $totalBytes += [long]$item.LengthBytes
    }
    if ($totalBytes -gt $script:CddsiFastLaneOnboardingMaximumBundleBytes) { throw 'VM onboarding payload exceeds the fixed bundle size limit.' }

        [void][System.IO.Directory]::CreateDirectory($outputFull)
        $outputCreated = $true
        Assert-CddsiNoReparsePath -Path $outputFull -StopRoot $Sandbox.Root
        $outputMarker = [pscustomobject][ordered]@{
            SchemaVersion = 1; MarkerType = 'CddsiFastLaneVmOnboardingOutput'; RunId = $Sandbox.RunId
            OwnershipToken = $Sandbox.OwnershipToken
            OutputRootBindingSha256 = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($outputFull).ToUpperInvariant())
        }
        Write-CddsiFastLaneOnboardingCanonicalFile -Path (Join-Path $outputFull $script:CddsiFastLaneOnboardingOutputMarker) -Value $outputMarker
        $stagingRoot = Join-Path $outputFull 'staging'
        [void][System.IO.Directory]::CreateDirectory($stagingRoot)
        $inventoryEntries = [System.Collections.Generic.List[object]]::new()
        foreach ($item in @($allFiles)) {
            $destination = Join-Path $stagingRoot ($item.BundlePath.Replace('/', '\'))
            Copy-CddsiFastLaneOnboardingFile -SourcePath $item.FullPath -DestinationPath $destination -SandboxRoot $Sandbox.Root
            if ((Get-CddsiFastLaneOnboardingFileSha256 -Path $destination) -cne $item.Sha256) {
                throw ('VM onboarding copied file hash differs: {0}' -f $item.BundlePath)
            }
            $inventoryEntries.Add([pscustomobject][ordered]@{
                Ordinal = 0; Category = $item.Category; Path = $item.BundlePath; SourcePath = $item.SourcePath
                Sha256 = $item.Sha256; GitBlobSha = $item.GitBlobSha; LengthBytes = [long]$item.LengthBytes
            })
        }
        $negativeRunbook = New-CddsiFastLaneNegativePermissionRunbook
        $smokeRunbook = New-CddsiFastLaneUnattendedSmokeRunbook
        $generatedRunbooks = @(
            [pscustomobject]@{ Path = 'runbooks/negative-permissions.json'; Value = $negativeRunbook; Purpose = $negativeRunbook.Purpose },
            [pscustomobject]@{ Path = 'runbooks/unattended-smoke.json'; Value = $smokeRunbook; Purpose = $smokeRunbook.Purpose }
        )
        foreach ($generated in $generatedRunbooks) {
            $full = Join-Path $stagingRoot ($generated.Path.Replace('/', '\'))
            [void][System.IO.Directory]::CreateDirectory((Split-Path -Parent $full))
            Write-CddsiFastLaneOnboardingCanonicalFile -Path $full -Value $generated.Value
            $inventoryEntries.Add([pscustomobject][ordered]@{
                Ordinal = 0; Category = 'GeneratedRunbook'; Path = $generated.Path; SourcePath = $null
                Sha256 = Get-CddsiFastLaneOnboardingFileSha256 -Path $full; GitBlobSha = $null
                LengthBytes = [long]([System.IO.FileInfo]::new($full).Length)
            })
        }
        $entries = [object[]]$inventoryEntries.ToArray()
        [Array]::Sort($entries, [System.Collections.Generic.Comparer[object]]::Create(
            [System.Comparison[object]]{ param($left, $right) [StringComparer]::Ordinal.Compare([string]$left.Path, [string]$right.Path) }
        ))
        for ($index = 0; $index -lt $entries.Count; $index++) { $entries[$index].Ordinal = $index + 1 }
        $contentPayload = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-onboarding-content-v1'; Entries = @($entries)
        }
        $contentDigest = Get-CddsiFastLaneOnboardingBindingToken -Value $contentPayload
        $inventory = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-onboarding-inventory-v1'
            EntryCount = $entries.Count; Entries = @($entries); BundleContentDigestSha256 = $contentDigest
            InventoryBindingToken = $null
        }
        $inventoryPayload = [ordered]@{}
        foreach ($property in $inventory.PSObject.Properties) { if ($property.Name -cne 'InventoryBindingToken') { $inventoryPayload[$property.Name] = $property.Value } }
        $inventory.InventoryBindingToken = Get-CddsiFastLaneOnboardingBindingToken -Value $inventoryPayload
        $inventoryFull = Join-Path $stagingRoot $script:CddsiFastLaneOnboardingInventoryPath
        Write-CddsiFastLaneOnboardingCanonicalFile -Path $inventoryFull -Value $inventory
        $inventorySha = Get-CddsiFastLaneOnboardingFileSha256 -Path $inventoryFull
        $fileSets = [ordered]@{}
        foreach ($category in @('Git', 'Runtime', 'Reset', 'Prompt', 'Runbook')) {
            $fileSets[$category] = @($entries | Where-Object Category -eq $category | ForEach-Object {
                [pscustomobject][ordered]@{
                    Path = $_.SourcePath; BundlePath = $_.Path; Sha256 = $_.Sha256; GitBlobSha = $_.GitBlobSha
                }
            })
        }
        $zipEntries = @($script:CddsiFastLaneOnboardingManifestPath, $script:CddsiFastLaneOnboardingInventoryPath) + @($entries | ForEach-Object Path)
        $zipEntries = [string[]]$zipEntries
        [Array]::Sort($zipEntries, [StringComparer]::Ordinal)
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-fast-lane-vm-onboarding-manifest-v1'
            Purpose = 'P10A_0A_VM_ONBOARDING_DIAGNOSTIC_ONLY'
            EvidenceClass = 'DIAGNOSTIC_ONLY'
            Mode = $Mode
            Policy = $policyBinding
            Product = [pscustomobject][ordered]@{
                Repository = $productRepository; CommitSha = $ProductCommitSha; RepairRef = $RepairRef
                TreeSha = $sourceBinding.TreeSha; SourceCommitVerified = $sourceBinding.SourceCommitVerified
                GitExecutableSha256 = $sourceBinding.GitExecutableSha256
                VmAccess = 'READ_ONLY_EXACT_COMMIT'; CodeWriteAuthority = 'HOST_ONLY_REPAIR_REF'
            }
            ControlRepositories = [pscustomobject][ordered]@{
                HostToVm = [pscustomobject][ordered]@{ Repository = $hostToVmRepository; GenesisSha = $HostToVmGenesisSha; VmAccess = 'READ_ONLY'; HostAccess = 'APPEND_ONLY' }
                VmToHost = [pscustomobject][ordered]@{ Repository = $vmToHostRepository; GenesisSha = $VmToHostGenesisSha; VmAccess = 'APPEND_ONLY'; HostAccess = 'READ_ONLY' }
            }
            FileSets = $fileSets
            Tools = @($tools)
            Constraints = [pscustomobject][ordered]@{
                VmMayEditProductCode = $false; VmMayCommitOrPushProductCode = $false
                HostIsOnlyProductCodeWriter = $true; HostMayRunProductLive = $false
                VmMayChangeRunbook = $false; VmMayBuildCandidate = $false
                PayloadTextMayExecute = $false; AutoMerge = $false; AutoPromotion = $false; AutoRelease = $false
                CredentialsIncluded = $false; UserPathsIncluded = $false; SecretFindingCount = 0
            }
            Automation = [pscustomobject][ordered]@{
                IntervalMinutes = $policyBinding.Automation.IntervalMinutes
                HostAutomationId = $policyBinding.Automation.HostAutomationId
                HostInitialStatus = $policyBinding.Automation.HostInitialStatus
                VmAutomationId = $policyBinding.Automation.VmAutomationId
                VmInitialStatus = $policyBinding.Automation.VmInitialStatus
                VmMustBeCreatedOnDevice = $policyBinding.Automation.VmMustBeCreatedOnDevice
                SingleActiveCycle = $true; CompareAndSwapRequired = $true
                SequenceAndPreviousHashRequired = $true
                MaximumMessageAgeSeconds = $policyBinding.Envelope.MaximumAgeSeconds
                MaximumClockSkewSeconds = $policyBinding.Envelope.MaximumClockSkewSeconds
                HostRole = 'HostCoordinator'; VmRole = 'VmTester'; StopRequired = $true
                ResultClass = 'DIAGNOSTIC_ONLY'
            }
            Runbooks = [pscustomobject][ordered]@{
                NegativePermissions = [pscustomobject][ordered]@{ Path = 'runbooks/negative-permissions.json'; Sha256 = ($entries | Where-Object Path -eq 'runbooks/negative-permissions.json').Sha256; BindingToken = $negativeRunbook.BindingToken }
                UnattendedSmoke = [pscustomobject][ordered]@{ Path = 'runbooks/unattended-smoke.json'; Sha256 = ($entries | Where-Object Path -eq 'runbooks/unattended-smoke.json').Sha256; BindingToken = $smokeRunbook.BindingToken }
            }
            Inventory = [pscustomobject][ordered]@{
                Path = $script:CddsiFastLaneOnboardingInventoryPath; Sha256 = $inventorySha
                EntryCount = $entries.Count; BundleContentDigestSha256 = $contentDigest
                InventoryBindingToken = $inventory.InventoryBindingToken
            }
            Zip = [pscustomobject][ordered]@{
                Format = 'ZIP32'; Compression = 'Store'; EntryTimestampUtc = $script:CddsiFastLaneOnboardingFixedTimestampUtc
                EntryOrder = 'Ordinal'; ExpectedEntries = @($zipEntries)
            }
            ManifestBindingToken = $null
        }
        $manifestPayload = [ordered]@{}
        foreach ($property in $manifest.PSObject.Properties) { if ($property.Name -cne 'ManifestBindingToken') { $manifestPayload[$property.Name] = $property.Value } }
        $manifest.ManifestBindingToken = Get-CddsiFastLaneOnboardingBindingToken -Value $manifestPayload
        $manifestFull = Join-Path $stagingRoot $script:CddsiFastLaneOnboardingManifestPath
        Write-CddsiFastLaneOnboardingCanonicalFile -Path $manifestFull -Value $manifest
        $packageItems = @(Get-CddsiReleasePackageItems -RepositoryRoot $stagingRoot -PackageFiles $zipEntries)
        $null = Invoke-CddsiReleaseFileSecretScan -Items $packageItems -Layer Staging
        $zipPath = Join-Path $outputFull $script:CddsiFastLaneOnboardingZipName
        New-CddsiReleaseSimulationZip -StagingRoot $stagingRoot -ZipPath $zipPath -PackageFiles $zipEntries -SandboxRoot $Sandbox.Root
        $validation = Test-CddsiFastLaneVmOnboardingBundle -Sandbox $Sandbox -ZipPath $zipPath
        return [pscustomobject][ordered]@{
            Status = 'SUCCEEDED'; Mode = $Mode; Changed = $false; BundleMaterialized = $true
            EvidenceClass = 'DIAGNOSTIC_ONLY'; OutputRoot = $outputFull; ZipPath = $zipPath
            ZipSha256 = Get-CddsiFastLaneOnboardingFileSha256 -Path $zipPath
            ZipLengthBytes = [long]([System.IO.FileInfo]::new($zipPath).Length)
            ZipEntries = @($zipEntries); ZipEntryCount = $validation.EntryCount; ZipCompression = $validation.Compression
            ZipEntryTimestampUtc = $validation.EntryTimestampUtc; SecretFindings = $validation.SecretFindings
            ManifestPath = $script:CddsiFastLaneOnboardingManifestPath; ManifestBindingToken = $manifest.ManifestBindingToken
            InventoryPath = $script:CddsiFastLaneOnboardingInventoryPath; InventorySha256 = $inventorySha
            BundleContentDigestSha256 = $contentDigest; Constraints = $manifest.Constraints
            ProductCommitSha = $ProductCommitSha; ProductTreeSha = $sourceBinding.TreeSha
            SourceCommitVerified = $sourceBinding.SourceCommitVerified
            SourceGitExecutableSha256 = $sourceBinding.GitExecutableSha256
        }
    }
    catch {
        $primaryError = $_
        $cleanupOutcome = 'NotStarted'
        if ($outputCreated -and [System.IO.Directory]::Exists($outputFull)) {
            try {
                $cleanupOutcome = 'SkippedUnsafe'
                $markerPath = Join-Path $outputFull $script:CddsiFastLaneOnboardingOutputMarker
                if ([System.IO.File]::Exists($markerPath)) {
                    $marker = ([System.IO.File]::ReadAllText($markerPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json -ErrorAction Stop)
                    $binding = Get-CddsiSha256Text -Text ([System.IO.Path]::GetFullPath($outputFull).ToUpperInvariant())
                    if ($marker.MarkerType -ceq 'CddsiFastLaneVmOnboardingOutput' -and $marker.RunId -ceq $Sandbox.RunId -and
                        $marker.OwnershipToken -ceq $Sandbox.OwnershipToken -and $marker.OutputRootBindingSha256 -ceq $binding) {
                        [System.IO.Directory]::Delete($outputFull, $true)
                        $cleanupOutcome = 'Succeeded'
                    }
                }
            }
            catch { $cleanupOutcome = 'Failed' }
        }
        $primaryError.Exception.Data['CddsiCleanupOutcome'] = $cleanupOutcome
        throw $primaryError
    }
}

if ($entryImportOnly) { return }
throw 'VM onboarding bundle assembly is fail closed. Dot-source with -ImportOnly and invoke the explicit sandbox-bound builder.'
