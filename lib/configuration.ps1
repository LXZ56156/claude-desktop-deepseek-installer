# DPAPI credential helper and minimal HKCU managed configuration.

$script:CddsiManagedPolicyNames = @(
    'inferenceProvider'
    'inferenceCredentialKind'
    'inferenceCredentialHelper'
    'inferenceGatewayBaseUrl'
    'inferenceGatewayAuthScheme'
    'modelDiscoveryEnabled'
    'inferenceModels'
    'chatTabEnabled'
)

function Get-CddsiPolicyValueSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Settings,

        [Parameter(Mandatory = $true)]
        [string]$HelperPath
    )

    $modelJson = @($Settings.models) | ConvertTo-Json -Compress -Depth 5
    [ordered]@{
        inferenceProvider                  = [string]$Settings.provider.kind
        inferenceCredentialKind            = 'helper-script'
        inferenceCredentialHelper          = $HelperPath
        inferenceGatewayBaseUrl            = [string]$Settings.provider.baseUrl
        inferenceGatewayAuthScheme         = [string]$Settings.provider.authScheme
        modelDiscoveryEnabled              = 'false'
        inferenceModels                    = $modelJson
        chatTabEnabled                     = 'true'
    }
}

function Get-CddsiRegistryValueNames {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        return @()
    }
    $key = Get-Item -LiteralPath $Path -ErrorAction Stop
    return @($key.GetValueNames())
}

function Invoke-CddsiClaudePolicyMutationDirect {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $SetValues,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [string[]]$RemoveNames
    )

    $parent = $null
    $key = $null
    try {
        $parent = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
            'SOFTWARE\Policies',
            $true
        )
        if ($null -eq $parent) {
            throw (New-Object UnauthorizedAccessException -ArgumentList (
                'HKCU Policies is not writable.'
            ))
        }
        if (@($SetValues.Keys).Count -gt 0) {
            $key = $parent.CreateSubKey('Claude')
        }
        else {
            $key = $parent.OpenSubKey('Claude', $true)
        }
        if ($null -eq $key) {
            return
        }
        foreach ($entry in $SetValues.GetEnumerator()) {
            $key.SetValue(
                [string]$entry.Key,
                [string]$entry.Value,
                [Microsoft.Win32.RegistryValueKind]::String
            )
        }
        foreach ($name in $RemoveNames) {
            $key.DeleteValue($name, $false)
        }
        $deleteEmpty = $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
        $key.Dispose()
        $key = $null
        if ($deleteEmpty) {
            $parent.DeleteSubKey('Claude', $false)
        }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
        if ($null -ne $parent) { $parent.Dispose() }
    }
}

function Invoke-CddsiClaudePolicyMutation {
    [CmdletBinding()]
    param(
        $SetValues = @{},
        [string[]]$RemoveNames = @()
    )

    $setEntries = @($SetValues.GetEnumerator())
    $setNames = @($setEntries | ForEach-Object { [string]$_.Key })
    $remove = @($RemoveNames)
    $allNames = @($setNames + $remove)
    if (@($allNames | Where-Object {
        $_ -cnotin $script:CddsiManagedPolicyNames
    }).Count -ne 0 -or
        @($allNames | Sort-Object -Unique).Count -ne $allNames.Count) {
        Throw-CddsiError -Code 'CLAUDE_POLICY_MUTATION_INVALID' `
            -Message 'Claude policy mutation 包含非项目拥有或重复的值名。'
    }

    try {
        Invoke-CddsiClaudePolicyMutationDirect `
            -SetValues $SetValues -RemoveNames $remove
        return
    }
    catch {
        $accessDenied = $false
        $cursor = $_.Exception
        while ($null -ne $cursor) {
            if ($cursor -is [UnauthorizedAccessException] -or
                $cursor -is [Security.SecurityException]) {
                $accessDenied = $true
                break
            }
            $cursor = $cursor.InnerException
        }
        if (-not $accessDenied) {
            Throw-CddsiError -Code 'CLAUDE_POLICY_WRITE_FAILED' `
                -Message '无法写入当前用户 Claude managed policy。'
        }
    }

    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    $encode = {
        param([string]$Value)
        [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($Value))
    }
    $setRows = @($setEntries | Sort-Object Key | ForEach-Object {
        '{0}:{1}' -f (& $encode ([string]$_.Key)),
            (& $encode ([string]$_.Value))
    })
    $removeRows = @($remove | Sort-Object | ForEach-Object {
        & $encode $_
    })
    $allowedRows = @($script:CddsiManagedPolicyNames | Sort-Object |
        ForEach-Object { & $encode $_ })
    $literal = {
        param([string[]]$Rows)
        if ($Rows.Count -eq 0) { return '' }
        return ($Rows | ForEach-Object { "    '$_'" }) -join ",`r`n"
    }
    $elevatedSource = @'
$ErrorActionPreference = 'Stop'
$expectedSid = '__SID__'
if ([Security.Principal.WindowsIdentity]::GetCurrent().User.Value -cne $expectedSid) {
    exit 43
}
$setRows = @(
__SET_ROWS__
)
$removeRows = @(
__REMOVE_ROWS__
)
$allowedRows = @(
__ALLOWED_ROWS__
)
$decode = {
    param([string]$Value)
    [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($Value))
}
$allowed = @($allowedRows | ForEach-Object { & $decode $_ })
$setValues = [ordered]@{}
foreach ($row in $setRows) {
    $parts = @($row.Split(':'))
    if ($parts.Count -ne 2) { exit 44 }
    $name = & $decode $parts[0]
    if ($name -cnotin $allowed -or $setValues.Contains($name)) { exit 44 }
    $setValues[$name] = & $decode $parts[1]
}
$removeNames = @($removeRows | ForEach-Object { & $decode $_ })
if (@($removeNames | Where-Object { $_ -cnotin $allowed }).Count -ne 0 -or
    @($removeNames | Sort-Object -Unique).Count -ne $removeNames.Count) {
    exit 44
}
$parent = $null
$key = $null
try {
    $parent = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey(
        'SOFTWARE\Policies',
        $true
    )
    if ($null -eq $parent) { exit 44 }
    if ($setValues.Count -gt 0) {
        $key = $parent.CreateSubKey('Claude')
    }
    else {
        $key = $parent.OpenSubKey('Claude', $true)
    }
    if ($null -eq $key) { exit 0 }
    foreach ($entry in $setValues.GetEnumerator()) {
        $key.SetValue(
            [string]$entry.Key,
            [string]$entry.Value,
            [Microsoft.Win32.RegistryValueKind]::String
        )
    }
    foreach ($name in $removeNames) {
        $key.DeleteValue($name, $false)
    }
    $deleteEmpty = $key.ValueCount -eq 0 -and $key.SubKeyCount -eq 0
    $key.Dispose()
    $key = $null
    if ($deleteEmpty) {
        $parent.DeleteSubKey('Claude', $false)
    }
}
catch {
    exit 44
}
finally {
    if ($null -ne $key) { $key.Dispose() }
    if ($null -ne $parent) { $parent.Dispose() }
}
exit 0
'@
    $elevatedSource = $elevatedSource.
        Replace('__SID__', $currentSid).
        Replace('__SET_ROWS__', (& $literal $setRows)).
        Replace('__REMOVE_ROWS__', (& $literal $removeRows)).
        Replace('__ALLOWED_ROWS__', (& $literal $allowedRows))
    $encodedCommand = [Convert]::ToBase64String(
        [Text.Encoding]::Unicode.GetBytes($elevatedSource)
    )
    $powershell = Join-Path $env:SystemRoot `
        'System32\WindowsPowerShell\v1.0\powershell.exe'
    try {
        $process = Start-Process -FilePath $powershell `
            -ArgumentList @(
                '-NoLogo',
                '-NoProfile',
                '-NonInteractive',
                '-ExecutionPolicy',
                'Bypass',
                '-EncodedCommand',
                $encodedCommand
            ) `
            -WorkingDirectory (Join-Path $env:SystemRoot 'System32') `
            -Verb RunAs -WindowStyle Hidden `
            -Wait -PassThru -ErrorAction Stop
    }
    catch {
        $nativeCode = 0
        $cursor = $_.Exception
        while ($null -ne $cursor) {
            if ($cursor -is [ComponentModel.Win32Exception]) {
                $nativeCode = $cursor.NativeErrorCode
                break
            }
            $cursor = $cursor.InnerException
        }
        if ($nativeCode -eq 1223 -or
            $_.Exception.Message -match '(?i)cancel|canceled|cancelled|1223|取消') {
            Throw-CddsiError -Code 'USER_CANCELLED' `
                -Message '用户取消了 Claude HKCU policy 写入所需的 UAC。'
        }
        Throw-CddsiError -Code 'CLAUDE_POLICY_WRITE_FAILED' `
            -Message '无法启动 Claude HKCU policy 的同用户 UAC 写入。'
    }
    switch ($process.ExitCode) {
        0 { return }
        43 {
            Throw-CddsiError -Code 'CLAUDE_CURRENT_USER_ELEVATION_REQUIRED' `
                -Message 'UAC 必须使用当前 Windows 用户批准，不能切换到其他管理员账户。'
        }
        default {
            Throw-CddsiError -Code 'CLAUDE_POLICY_WRITE_FAILED' `
                -Message 'Claude HKCU policy 的同用户 UAC 写入失败。'
        }
    }
}

function Test-CddsiOwnedInstallation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Paths
    )

    if (-not (Test-Path -LiteralPath $Paths.OwnershipMarker -PathType Leaf) -or
        -not (Test-Path -LiteralPath $script:CddsiOwnershipPath)) {
        return $false
    }
    try {
        $marker = Get-Content -LiteralPath $Paths.OwnershipMarker -Raw -Encoding UTF8
        $owner = (Get-ItemProperty -LiteralPath $script:CddsiOwnershipPath `
            -Name OwnerId -ErrorAction Stop).OwnerId
        return $marker.Trim() -ceq $script:CddsiOwnerId -and
            $owner -ceq $script:CddsiOwnerId
    }
    catch {
        return $false
    }
}

function Assert-CddsiConfigurationPreflight {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        $Paths
    )

    $helperSource = Join-Path $ProjectRoot 'helper\CddsiCredentialHelper.cs'
    if (-not (Test-Path -LiteralPath $helperSource -PathType Leaf)) {
        Throw-CddsiError -Code 'CREDENTIAL_HELPER_SOURCE_NOT_FOUND' `
            -Message 'Credential helper 源文件缺失。'
    }

    if (Test-Path -LiteralPath $Paths.Root) {
        $rootItem = Get-Item -LiteralPath $Paths.Root -Force -ErrorAction Stop
        if (-not $rootItem.PSIsContainer -or
            ($rootItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-CddsiError -Code 'PRODUCT_DIRECTORY_UNSAFE' `
                -Message '产品私有目录不是普通目录，拒绝继续。'
        }
        if (-not (Test-CddsiOwnedInstallation -Paths $Paths)) {
            Throw-CddsiError -Code 'PRODUCT_DIRECTORY_CONFLICT' `
                -Message '产品私有目录已存在且不属于本项目。'
        }
    }

    $machineNames = @(Get-CddsiRegistryValueNames -Path $script:CddsiMachinePolicyPath |
        Where-Object { $_ -cnotin @('disableAutoUpdates', 'autoUpdaterEnforcementHours') })
    if ($machineNames.Count -gt 0) {
        Throw-CddsiError -Code 'CLAUDE_MACHINE_POLICY_CONFLICT' `
            -Message '检测到现有 Claude 机器级 managed policy；HKCU 配置不会生效。'
    }

    $configLibrary = Join-Path $env:LOCALAPPDATA 'Claude-3p\configLibrary'
    if (Test-Path -LiteralPath $configLibrary) {
        $configItem = Get-Item -LiteralPath $configLibrary -Force -ErrorAction Stop
        if (-not $configItem.PSIsContainer -or
            ($configItem.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            Throw-CddsiError -Code 'CLAUDE_LOCAL_CONFIG_CONFLICT' `
                -Message 'Claude 3P 本地配置路径不是安全的普通目录。'
        }
        $localEntries = @(Get-ChildItem -LiteralPath $configLibrary -Force `
            -ErrorAction Stop | Select-Object -First 1)
        if ($localEntries.Count -gt 0) {
            Throw-CddsiError -Code 'CLAUDE_LOCAL_CONFIG_CONFLICT' `
                -Message '检测到现有 Claude 3P 本地配置；为避免覆盖，安装器已停止。'
        }
    }

    $userNames = @(Get-CddsiRegistryValueNames -Path $script:CddsiPolicyPath)
    if ($userNames.Count -gt 0 -and -not (Test-CddsiOwnedInstallation -Paths $Paths)) {
        Throw-CddsiError -Code 'CLAUDE_USER_POLICY_CONFLICT' `
            -Message '检测到非本项目拥有的 Claude 用户级 managed policy。'
    }
}

function Install-CddsiCredentialHelper {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        $Paths
    )

    $source = Join-Path $ProjectRoot 'helper\CddsiCredentialHelper.cs'
    $frameworkRoot = if ([Environment]::Is64BitProcess) {
        Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319'
    }
    else {
        Join-Path $env:SystemRoot 'Microsoft.NET\Framework\v4.0.30319'
    }
    $compiler = Join-Path $frameworkRoot 'csc.exe'
    if (-not (Test-Path -LiteralPath $compiler -PathType Leaf)) {
        Throw-CddsiError -Code 'CSHARP_COMPILER_NOT_FOUND' `
            -Message 'Windows .NET Framework C# compiler 不可用。'
    }

    New-CddsiPrivateDirectory -Path $Paths.Root
    $temporaryHelper = Join-Path $Paths.Root (
        'helper-{0}.exe' -f ([guid]::NewGuid().ToString('N'))
    )
    $arguments = @(
        '/nologo'
        '/target:exe'
        '/platform:anycpu'
        '/optimize+'
        '/debug-'
        ('/out:"{0}"' -f $temporaryHelper)
        '/reference:System.dll'
        '/reference:System.Security.dll'
        ('"{0}"' -f $source)
    )
    try {
        $process = Start-Process -FilePath $compiler -ArgumentList $arguments `
            -WorkingDirectory $Paths.Root -Wait -PassThru -NoNewWindow `
            -ErrorAction Stop
        if ($process.ExitCode -ne 0 -or
            -not (Test-Path -LiteralPath $temporaryHelper -PathType Leaf)) {
            Throw-CddsiError -Code 'CREDENTIAL_HELPER_BUILD_FAILED' `
                -Message 'Credential helper 本地编译失败。'
        }
        Set-CddsiPrivateFileAcl -Path $temporaryHelper
        Move-Item -LiteralPath $temporaryHelper -Destination $Paths.Helper `
            -Force -ErrorAction Stop
        Set-CddsiPrivateFileAcl -Path $Paths.Helper
    }
    finally {
        if (Test-Path -LiteralPath $temporaryHelper) {
            Remove-Item -LiteralPath $temporaryHelper -Force -ErrorAction SilentlyContinue
        }
    }

    $item = Get-Item -LiteralPath $Paths.Helper -ErrorAction Stop
    if ($item.Length -lt 4096 -or $item.Length -gt 1048576) {
        Throw-CddsiError -Code 'CREDENTIAL_HELPER_BUILD_FAILED' `
            -Message 'Credential helper 输出大小不合理。'
    }
    return Get-CddsiFileSha256 -Path $Paths.Helper
}

function Protect-CddsiSecureString {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [System.Security.SecureString]$SecureString,

        [Parameter(Mandatory = $true)]
        [string]$Destination
    )

    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $bstr = [IntPtr]::Zero
    $characters = $null
    $plaintext = $null
    $encrypted = $null
    try {
        $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecureString)
        $characterCount = [Runtime.InteropServices.Marshal]::ReadInt32($bstr, -4) / 2
        if ($characterCount -lt 8 -or $characterCount -gt 4096) {
            Throw-CddsiError -Code 'API_KEY_INVALID' `
                -Message 'API Key 长度不合理。'
        }
        $characters = New-Object char[] $characterCount
        for ($index = 0; $index -lt $characterCount; $index++) {
            $character = [char][Runtime.InteropServices.Marshal]::ReadInt16(
                $bstr,
                ($index * 2)
            )
            if ([int]$character -lt 0x21 -or [int]$character -gt 0x7e) {
                Throw-CddsiError -Code 'API_KEY_INVALID' `
                    -Message 'API Key 只能包含可打印 ASCII 字符且不能包含空白。'
            }
            $characters[$index] = $character
        }
        $plaintext = [Text.Encoding]::UTF8.GetBytes($characters)
        $encrypted = [Security.Cryptography.ProtectedData]::Protect(
            $plaintext,
            $script:CddsiCredentialEntropy,
            [Security.Cryptography.DataProtectionScope]::CurrentUser
        )
        $temporary = '{0}.new-{1}' -f $Destination, ([guid]::NewGuid().ToString('N'))
        try {
            [IO.File]::WriteAllBytes($temporary, $encrypted)
            Set-CddsiPrivateFileAcl -Path $temporary
            Move-Item -LiteralPath $temporary -Destination $Destination `
                -Force -ErrorAction Stop
            Set-CddsiPrivateFileAcl -Path $Destination
        }
        finally {
            if (Test-Path -LiteralPath $temporary) {
                Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
            }
        }
    }
    finally {
        if ($null -ne $characters) {
            [Array]::Clear($characters, 0, $characters.Length)
        }
        if ($null -ne $plaintext) {
            [Array]::Clear($plaintext, 0, $plaintext.Length)
        }
        if ($null -ne $encrypted) {
            [Array]::Clear($encrypted, 0, $encrypted.Length)
        }
        if ($bstr -ne [IntPtr]::Zero) {
            [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr)
        }
    }
}

function Save-CddsiOwnershipState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Paths,

        [Parameter(Mandatory = $true)]
        [string[]]$PolicyValueNames,

        [Parameter(Mandatory = $true)]
        [string]$HelperSha256,

        [Parameter(Mandatory = $true)]
        [string]$SourceSha256
    )

    $state = [ordered]@{
        SchemaVersion    = $script:CddsiStateSchemaVersion
        OwnerId          = $script:CddsiOwnerId
        Completed        = $true
        PolicyValueNames = @($PolicyValueNames)
        HelperSha256     = $HelperSha256
        HelperSourceSha256 = $SourceSha256
        UpdatedAtUtc     = [DateTimeOffset]::UtcNow.ToString('o')
    }
    $json = $state | ConvertTo-Json -Depth 4
    $temporary = '{0}.new-{1}' -f $Paths.State, ([guid]::NewGuid().ToString('N'))
    try {
        [IO.File]::WriteAllText(
            $temporary,
            $json,
            (New-Object Text.UTF8Encoding($false))
        )
        Set-CddsiPrivateFileAcl -Path $temporary
        Move-Item -LiteralPath $temporary -Destination $Paths.State `
            -Force -ErrorAction Stop
        Set-CddsiPrivateFileAcl -Path $Paths.State
    }
    finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Set-CddsiClaudeConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot,

        [Parameter(Mandatory = $true)]
        $Settings,

        [switch]$NonInteractive
    )

    $paths = Get-CddsiProductPaths
    Assert-CddsiConfigurationPreflight -ProjectRoot $ProjectRoot -Paths $paths
    $alreadyOwned = Test-CddsiOwnedInstallation -Paths $paths
    $changed = $false
    $policySnapshot = $null
    $existingState = $null
    $sourceHash = Get-CddsiFileSha256 -Path (
        Join-Path $ProjectRoot 'helper\CddsiCredentialHelper.cs'
    )
    if ($alreadyOwned) {
        try {
            $existingState = Get-Content -LiteralPath $paths.State -Raw `
                -Encoding UTF8 -ErrorAction Stop | ConvertFrom-Json
            $stateNames = @($existingState.PolicyValueNames)
            if ($existingState.SchemaVersion -ne $script:CddsiStateSchemaVersion -or
                $existingState.OwnerId -cne $script:CddsiOwnerId -or
                $existingState.HelperSha256 -notmatch '^[a-f0-9]{64}$' -or
                $existingState.HelperSourceSha256 -notmatch '^[a-f0-9]{64}$' -or
                $stateNames.Count -ne $script:CddsiManagedPolicyNames.Count -or
                @($stateNames | Sort-Object -Unique).Count -ne $stateNames.Count -or
                @($stateNames | Where-Object {
                    $_ -cnotin $script:CddsiManagedPolicyNames
                }).Count -ne 0) {
                Throw-CddsiError -Code 'OWNERSHIP_STATE_INVALID' `
                    -Message '既有项目状态损坏，未继续覆盖配置。'
            }
        }
        catch {
            if ($_.Exception.Message -match '^OWNERSHIP_STATE_INVALID\|') {
                throw
            }
            Throw-CddsiError -Code 'OWNERSHIP_STATE_INVALID' `
                -Message '既有项目状态损坏，未继续覆盖配置。'
        }
    }

    if ($NonInteractive -and
        -not (Test-Path -LiteralPath $paths.Credential -PathType Leaf)) {
        Throw-CddsiError -Code 'API_KEY_INPUT_REQUIRED' `
            -Message '首次配置需要在本机遮罩提示中输入 DeepSeek API Key。'
    }

    New-CddsiPrivateDirectory -Path $paths.Root
    if (-not $alreadyOwned) {
        [IO.File]::WriteAllText(
            $paths.OwnershipMarker,
            $script:CddsiOwnerId,
            (New-Object Text.UTF8Encoding($false))
        )
        Set-CddsiPrivateFileAcl -Path $paths.OwnershipMarker
        $changed = $true
    }

    try {
        $helperHash = $null
        if ($null -ne $existingState -and
            $existingState.HelperSourceSha256 -ceq $sourceHash -and
            (Test-Path -LiteralPath $paths.Helper -PathType Leaf) -and
            (Get-CddsiFileSha256 -Path $paths.Helper) -ceq
                $existingState.HelperSha256) {
            $helperHash = [string]$existingState.HelperSha256
        }
        else {
            $helperHash = Install-CddsiCredentialHelper `
                -ProjectRoot $ProjectRoot -Paths $paths
            $changed = $true
        }

        if (-not (Test-Path -LiteralPath $paths.Credential -PathType Leaf)) {
            $secureKey = Read-Host '请输入 DeepSeek API Key（输入内容不会显示）' `
                -AsSecureString
            try {
                Protect-CddsiSecureString -SecureString $secureKey `
                    -Destination $paths.Credential
            }
            finally {
                $secureKey.Dispose()
            }
            $changed = $true
        }
        else {
            $credentialLength = (Get-Item -LiteralPath $paths.Credential `
                -ErrorAction Stop).Length
            if ($credentialLength -lt 16 -or $credentialLength -gt 32768) {
                Throw-CddsiError -Code 'CREDENTIAL_BLOB_INVALID' `
                    -Message '既有 DPAPI credential blob 大小无效；请先恢复配置后重装。'
            }
        }

        if (-not $alreadyOwned) {
            New-Item -Path $script:CddsiOwnershipPath -Force -ErrorAction Stop |
                Out-Null
            New-ItemProperty -LiteralPath $script:CddsiOwnershipPath `
                -Name OwnerId -Value $script:CddsiOwnerId -PropertyType String `
                -Force -ErrorAction Stop | Out-Null
            $changed = $true
        }

        $values = Get-CddsiPolicyValueSet -Settings $Settings `
            -HelperPath $paths.Helper
        $policySnapshot = [ordered]@{}
        if (Test-Path -LiteralPath $script:CddsiPolicyPath) {
            $policyKey = Get-Item -LiteralPath $script:CddsiPolicyPath `
                -ErrorAction Stop
            foreach ($name in @($values.Keys)) {
                if ($policyKey.GetValueNames() -ccontains $name) {
                    $policySnapshot[$name] = [pscustomobject][ordered]@{
                        Exists = $true
                        Value  = $policyKey.GetValue(
                            $name,
                            $null,
                            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames
                        )
                        Kind   = $policyKey.GetValueKind($name)
                    }
                }
                else {
                    $policySnapshot[$name] = [pscustomobject]@{
                        Exists = $false
                        Value  = $null
                        Kind   = $null
                    }
                }
            }
        }
        else {
            foreach ($name in @($values.Keys)) {
                $policySnapshot[$name] = [pscustomobject]@{
                    Exists = $false
                    Value  = $null
                    Kind   = $null
                }
            }
        }
        $pendingValues = [ordered]@{}
        foreach ($entry in $values.GetEnumerator()) {
            $prior = $policySnapshot[$entry.Key]
            if (-not $prior.Exists -or
                $prior.Kind -ne [Microsoft.Win32.RegistryValueKind]::String -or
                [string]$prior.Value -cne [string]$entry.Value) {
                $pendingValues[$entry.Key] = [string]$entry.Value
                $changed = $true
            }
        }
        if ($pendingValues.Count -gt 0) {
            Invoke-CddsiClaudePolicyMutation -SetValues $pendingValues
        }

        $readback = Get-ItemProperty -LiteralPath $script:CddsiPolicyPath `
            -ErrorAction Stop
        foreach ($entry in $values.GetEnumerator()) {
            if ([string]$readback.($entry.Key) -cne [string]$entry.Value) {
                Throw-CddsiError -Code 'CLAUDE_POLICY_READBACK_FAILED' `
                    -Message 'Claude managed policy 写入后的 readback 不一致。'
            }
            $kind = (Get-Item -LiteralPath $script:CddsiPolicyPath).GetValueKind(
                $entry.Key
            )
            if ($kind -ne [Microsoft.Win32.RegistryValueKind]::String) {
                Throw-CddsiError -Code 'CLAUDE_POLICY_READBACK_FAILED' `
                    -Message 'Claude managed policy value type 不是 REG_SZ。'
            }
        }

        if ($changed -or $null -eq $existingState) {
            Save-CddsiOwnershipState -Paths $paths `
                -PolicyValueNames @($values.Keys) `
                -HelperSha256 $helperHash -SourceSha256 $sourceHash
        }
        return [pscustomobject][ordered]@{
            Changed = $changed
            Owned   = $true
        }
    }
    catch {
        $failure = $_.Exception
        if ($alreadyOwned -and $null -ne $policySnapshot) {
            $restoreValues = [ordered]@{}
            $removeNames = @()
            foreach ($entry in $policySnapshot.GetEnumerator()) {
                if ($entry.Value.Exists) {
                    $restoreValues[$entry.Key] = [string]$entry.Value.Value
                }
                else {
                    $removeNames += [string]$entry.Key
                }
            }
            try {
                Invoke-CddsiClaudePolicyMutation `
                    -SetValues $restoreValues -RemoveNames $removeNames
            }
            catch {
                # Preserve the primary failure, matching the original rollback
                # behavior while limiting attempted cleanup to owned values.
            }
        }
        elseif (-not $alreadyOwned) {
            try {
                Invoke-CddsiClaudePolicyMutation `
                    -RemoveNames $script:CddsiManagedPolicyNames
            }
            catch {
                # Preserve the primary failure.
            }
            Remove-Item -LiteralPath $script:CddsiOwnershipPath -Force `
                -ErrorAction SilentlyContinue
            foreach ($file in @(
                $paths.Credential,
                $paths.Helper,
                $paths.State,
                $paths.OwnershipMarker
            )) {
                Remove-Item -LiteralPath $file -Force -ErrorAction SilentlyContinue
            }
            if ((Test-Path -LiteralPath $paths.Root -PathType Container) -and
                @(Get-ChildItem -LiteralPath $paths.Root -Force `
                    -ErrorAction SilentlyContinue).Count -eq 0) {
                Remove-Item -LiteralPath $paths.Root -Force `
                    -ErrorAction SilentlyContinue
            }
        }
        throw $failure
    }
}

function Get-CddsiConfigurationStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$ProjectRoot
    )

    $settings = Get-CddsiSettings -ProjectRoot $ProjectRoot
    $paths = Get-CddsiProductPaths
    $owned = Test-CddsiOwnedInstallation -Paths $paths
    $helperPresent = Test-Path -LiteralPath $paths.Helper -PathType Leaf
    $credentialPresent = Test-Path -LiteralPath $paths.Credential -PathType Leaf
    $matches = $false
    $integrityMatches = $false
    if ($owned -and $helperPresent -and $credentialPresent -and
        (Test-Path -LiteralPath $script:CddsiPolicyPath)) {
        try {
            $expected = Get-CddsiPolicyValueSet -Settings $settings `
                -HelperPath $paths.Helper
            $readback = Get-ItemProperty -LiteralPath $script:CddsiPolicyPath `
                -ErrorAction Stop
            $matches = $true
            foreach ($entry in $expected.GetEnumerator()) {
                if ([string]$readback.($entry.Key) -cne [string]$entry.Value) {
                    $matches = $false
                    break
                }
            }
            $state = Get-Content -LiteralPath $paths.State -Raw -Encoding UTF8 `
                -ErrorAction Stop | ConvertFrom-Json
            $sourceHash = Get-CddsiFileSha256 -Path (
                Join-Path $ProjectRoot 'helper\CddsiCredentialHelper.cs'
            )
            $helperHash = Get-CddsiFileSha256 -Path $paths.Helper
            $credentialLength = (Get-Item -LiteralPath $paths.Credential `
                -ErrorAction Stop).Length
            $stateNames = @($state.PolicyValueNames)
            $integrityMatches =
                $state.SchemaVersion -eq $script:CddsiStateSchemaVersion -and
                $state.OwnerId -ceq $script:CddsiOwnerId -and
                $state.HelperSourceSha256 -ceq $sourceHash -and
                $state.HelperSha256 -ceq $helperHash -and
                $credentialLength -ge 16 -and
                $credentialLength -le 32768 -and
                $stateNames.Count -eq $script:CddsiManagedPolicyNames.Count -and
                @($stateNames | Sort-Object -Unique).Count -eq $stateNames.Count -and
                @($stateNames | Where-Object {
                    $_ -cnotin $script:CddsiManagedPolicyNames
                }).Count -eq 0
        }
        catch {
            $matches = $false
            $integrityMatches = $false
        }
    }
    [pscustomobject][ordered]@{
        Owned             = $owned
        HelperPresent     = $helperPresent
        CredentialPresent = $credentialPresent
        PolicyMatches     = $matches
        IntegrityMatches  = $integrityMatches
    }
}

function Restore-CddsiClaudeConfiguration {
    [CmdletBinding()]
    param()

    $paths = Get-CddsiProductPaths
    if (-not (Test-CddsiOwnedInstallation -Paths $paths)) {
        Throw-CddsiError -Code 'OWNED_CONFIGURATION_NOT_FOUND' `
            -Message '没有找到由本项目拥有的配置，因此未删除任何内容。'
    }

    $names = @()
    try {
        $state = Get-Content -LiteralPath $paths.State -Raw -Encoding UTF8 |
            ConvertFrom-Json
        if ($state.SchemaVersion -ne $script:CddsiStateSchemaVersion -or
            $state.OwnerId -cne $script:CddsiOwnerId) {
            Throw-CddsiError -Code 'OWNERSHIP_STATE_INVALID' `
                -Message '项目 ownership state 无效。'
        }
        $names = @($state.PolicyValueNames)
        if ($names.Count -ne $script:CddsiManagedPolicyNames.Count -or
            @($names | Sort-Object -Unique).Count -ne $names.Count -or
            @($names | Where-Object {
                $_ -isnot [string] -or $_ -cnotin $script:CddsiManagedPolicyNames
            }).Count -ne 0) {
            Throw-CddsiError -Code 'OWNERSHIP_STATE_INVALID' `
                -Message '项目 ownership state 包含未授权的 policy 名称。'
        }
    }
    catch {
        if ($_.Exception.Message -match '^OWNERSHIP_STATE_INVALID\|') {
            throw
        }
        Throw-CddsiError -Code 'OWNERSHIP_STATE_INVALID' `
            -Message '无法读取项目 ownership state。'
    }

    foreach ($file in @($paths.Credential, $paths.Helper)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        }
    }
    Invoke-CddsiClaudePolicyMutation -RemoveNames $names
    foreach ($file in @($paths.State, $paths.OwnershipMarker)) {
        if (Test-Path -LiteralPath $file -PathType Leaf) {
            Remove-Item -LiteralPath $file -Force -ErrorAction Stop
        }
    }
    Remove-Item -LiteralPath $script:CddsiOwnershipPath -Force `
        -ErrorAction SilentlyContinue
    if (@(Get-ChildItem -LiteralPath $paths.Root -Force -ErrorAction Stop).Count -eq 0) {
        Remove-Item -LiteralPath $paths.Root -Force -ErrorAction Stop
    }
    [pscustomobject][ordered]@{
        Changed = $true
        RestoredToAbsent = $true
    }
}
