# desktop-config.ps1 - pure Claude Desktop 3P desired-state and policy contracts.
# P2 never reads or writes registry/configLibrary/credential material.

function Get-CddsiClaudeDesktopConfigLibraryPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$LocalAppDataPath
    )

    return Get-CddsiConfigLibraryPath -LocalAppDataPath $LocalAppDataPath
}

function Test-CddsiConfigLibraryTarget {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TargetPath,
        [Parameter(Mandatory = $true)][string]$LocalAppDataPath
    )

    try {
        if ([string]::IsNullOrWhiteSpace($LocalAppDataPath)) { return $false }
        $localRoot = [System.IO.Path]::GetFullPath($LocalAppDataPath).TrimEnd('\')
        $expected = [System.IO.Path]::GetFullPath((Get-CddsiClaudeDesktopConfigLibraryPath -LocalAppDataPath $localRoot)).TrimEnd('\')
        $actual = [System.IO.Path]::GetFullPath($TargetPath).TrimEnd('\')
        return [string]::Equals($expected, $actual, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Read-CddsiClaudeDesktopConfigLibrary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [string]$TargetPath,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ([string]::IsNullOrWhiteSpace($TargetPath)) { $TargetPath = $Context.Paths.ConfigLibrary }
    if (-not (Test-CddsiConfigLibraryTarget -TargetPath $TargetPath -LocalAppDataPath $Context.Paths.LocalAppData)) {
        throw '拒绝读取：目标不是受信任的 synthetic configLibrary 路径。'
    }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'ReadConfigLibrary' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'ReadConfigLibraryMetadata' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P2_DETECTION_PROVIDER_NOT_IMPLEMENTED' -MessageSafe 'P2 只接受 synthetic source metadata；未读取 configLibrary。'
}

function New-CddsiClaudeDesktopDesiredConfig {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        SchemaVersion         = 2
        ContractVersion       = 'claude-desktop-3p-managed-policy-v1'
        MinimumDesktopVersion = '1.20186.0'
        WindowsPolicyNoMergeSince = '1.19367.0'
        Provider = [pscustomobject][ordered]@{
            Kind       = 'gateway'
            BaseUrl    = 'https://api.deepseek.com/anthropic'
            AuthScheme = 'x-api-key'
        }
        ModelPolicy = [pscustomobject][ordered]@{
            DiscoveryEnabled = $false
            DefaultModel     = 'deepseek-v4-pro'
            Models = @(
                [pscustomobject][ordered]@{
                    Name          = 'deepseek-v4-pro'
                    LabelOverride = 'DeepSeek V4 Pro'
                    Supports1m    = $true
                }
                [pscustomobject][ordered]@{
                    Name          = 'deepseek-v4-flash'
                    LabelOverride = 'DeepSeek V4 Flash'
                    Supports1m    = $true
                }
            )
            ProviderAliasMappings = @(
                [pscustomobject][ordered]@{
                    Pattern     = 'claude-opus-*'
                    TargetModel = 'deepseek-v4-pro'
                    EnforcedBy  = 'deepseek-anthropic-compatibility'
                }
                [pscustomobject][ordered]@{
                    Pattern     = 'claude-sonnet-*'
                    TargetModel = 'deepseek-v4-flash'
                    EnforcedBy  = 'deepseek-anthropic-compatibility'
                }
                [pscustomobject][ordered]@{
                    Pattern     = 'claude-haiku-*'
                    TargetModel = 'deepseek-v4-flash'
                    EnforcedBy  = 'deepseek-anthropic-compatibility'
                }
            )
            FamilyTierSerializationPolicy = 'omit_unverified_duplicate_model_binding'
        }
        RequestedSurfaces = @('Chat', 'Code', 'Cowork')
        SurfacePolicy = [pscustomobject][ordered]@{
            ChatEnabled     = $true
            CodeEnabled     = $true
            CoworkEnabled   = $true
            AutoModeEnabled = $false
        }
        DeploymentChooserPolicy = [pscustomobject][ordered]@{
            Disabled = $true
        }
        CredentialReference = [pscustomobject][ordered]@{
            Kind                 = 'helper-script'
            HelperBinding        = '<CREDENTIAL_HELPER_PATH>'
            TtlSeconds           = 3600
            TimeoutSeconds       = 60
            SilentRefreshEnabled = $true
            PersistInConfig      = $false
        }
        Ownership = [pscustomobject][ordered]@{
            TargetSource              = 'HKCU_MANAGED_POLICY'
            ExistingSourcePolicy      = 'conflict-stop'
            ConfigLibraryWriterEnabled = $false
        }
    }
}

function Test-CddsiClaudeDesktopConfigContract {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config
    )

    $rootProperties = @(
        'SchemaVersion', 'ContractVersion', 'MinimumDesktopVersion',
        'WindowsPolicyNoMergeSince', 'Provider', 'ModelPolicy',
        'RequestedSurfaces', 'SurfacePolicy', 'DeploymentChooserPolicy',
        'CredentialReference', 'Ownership'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Config -Expected $rootProperties)) { return $false }
    if ($Config.SchemaVersion -isnot [int] -or $Config.SchemaVersion -ne 2) { return $false }
    if ($Config.ContractVersion -isnot [string] -or $Config.ContractVersion -cne 'claude-desktop-3p-managed-policy-v1') { return $false }
    if ($Config.MinimumDesktopVersion -isnot [string] -or $Config.MinimumDesktopVersion -cne '1.20186.0') { return $false }
    if ($Config.WindowsPolicyNoMergeSince -isnot [string] -or $Config.WindowsPolicyNoMergeSince -cne '1.19367.0') { return $false }

    if (-not (Test-CddsiExactPropertySet -InputObject $Config.Provider -Expected @('Kind', 'BaseUrl', 'AuthScheme'))) { return $false }
    if ($Config.Provider.Kind -isnot [string] -or $Config.Provider.Kind -cne 'gateway') { return $false }
    if ($Config.Provider.BaseUrl -isnot [string] -or $Config.Provider.BaseUrl -cne 'https://api.deepseek.com/anthropic') { return $false }
    if ($Config.Provider.AuthScheme -isnot [string] -or $Config.Provider.AuthScheme -cne 'x-api-key') { return $false }

    $modelPolicyProperties = @('DiscoveryEnabled', 'DefaultModel', 'Models', 'ProviderAliasMappings', 'FamilyTierSerializationPolicy')
    if (-not (Test-CddsiExactPropertySet -InputObject $Config.ModelPolicy -Expected $modelPolicyProperties)) { return $false }
    if ($Config.ModelPolicy.DiscoveryEnabled -isnot [bool] -or $Config.ModelPolicy.DiscoveryEnabled) { return $false }
    if ($Config.ModelPolicy.DefaultModel -isnot [string] -or $Config.ModelPolicy.DefaultModel -cne 'deepseek-v4-pro') { return $false }
    if ($Config.ModelPolicy.FamilyTierSerializationPolicy -isnot [string] -or $Config.ModelPolicy.FamilyTierSerializationPolicy -cne 'omit_unverified_duplicate_model_binding') { return $false }
    $models = @($Config.ModelPolicy.Models)
    if ($models.Count -ne 2) { return $false }
    $expectedModels = @(
        @('deepseek-v4-pro', 'DeepSeek V4 Pro'),
        @('deepseek-v4-flash', 'DeepSeek V4 Flash')
    )
    for ($index = 0; $index -lt $models.Count; $index++) {
        if (-not (Test-CddsiExactPropertySet -InputObject $models[$index] -Expected @('Name', 'LabelOverride', 'Supports1m'))) { return $false }
        if ($models[$index].Name -isnot [string] -or $models[$index].Name -cne $expectedModels[$index][0]) { return $false }
        if ($models[$index].LabelOverride -isnot [string] -or $models[$index].LabelOverride -cne $expectedModels[$index][1]) { return $false }
        if ($models[$index].Supports1m -isnot [bool] -or -not $models[$index].Supports1m) { return $false }
    }
    $aliasMappings = @($Config.ModelPolicy.ProviderAliasMappings)
    $expectedAliasMappings = @(
        @('claude-opus-*', 'deepseek-v4-pro'),
        @('claude-sonnet-*', 'deepseek-v4-flash'),
        @('claude-haiku-*', 'deepseek-v4-flash')
    )
    if ($aliasMappings.Count -ne $expectedAliasMappings.Count) { return $false }
    for ($index = 0; $index -lt $aliasMappings.Count; $index++) {
        if (-not (Test-CddsiExactPropertySet -InputObject $aliasMappings[$index] -Expected @('Pattern', 'TargetModel', 'EnforcedBy'))) { return $false }
        if ($aliasMappings[$index].Pattern -isnot [string] -or $aliasMappings[$index].Pattern -cne $expectedAliasMappings[$index][0]) { return $false }
        if ($aliasMappings[$index].TargetModel -isnot [string] -or $aliasMappings[$index].TargetModel -cne $expectedAliasMappings[$index][1]) { return $false }
        if ($aliasMappings[$index].EnforcedBy -isnot [string] -or $aliasMappings[$index].EnforcedBy -cne 'deepseek-anthropic-compatibility') { return $false }
    }

    $surfaces = @($Config.RequestedSurfaces)
    if ($surfaces.Count -ne 3 -or ($surfaces -join '|') -cne 'Chat|Code|Cowork') { return $false }
    foreach ($surface in $surfaces) {
        if ($surface -isnot [string]) { return $false }
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $Config.SurfacePolicy -Expected @('ChatEnabled', 'CodeEnabled', 'CoworkEnabled', 'AutoModeEnabled'))) { return $false }
    foreach ($name in @('ChatEnabled', 'CodeEnabled', 'CoworkEnabled')) {
        if ($Config.SurfacePolicy.$name -isnot [bool] -or -not $Config.SurfacePolicy.$name) { return $false }
    }
    if ($Config.SurfacePolicy.AutoModeEnabled -isnot [bool] -or $Config.SurfacePolicy.AutoModeEnabled) { return $false }

    if (-not (Test-CddsiExactPropertySet -InputObject $Config.DeploymentChooserPolicy -Expected @('Disabled'))) { return $false }
    if ($Config.DeploymentChooserPolicy.Disabled -isnot [bool] -or -not $Config.DeploymentChooserPolicy.Disabled) { return $false }
    $credentialProperties = @('Kind', 'HelperBinding', 'TtlSeconds', 'TimeoutSeconds', 'SilentRefreshEnabled', 'PersistInConfig')
    if (-not (Test-CddsiExactPropertySet -InputObject $Config.CredentialReference -Expected $credentialProperties)) { return $false }
    if ($Config.CredentialReference.Kind -isnot [string] -or $Config.CredentialReference.Kind -cne 'helper-script') { return $false }
    if ($Config.CredentialReference.HelperBinding -isnot [string] -or $Config.CredentialReference.HelperBinding -cne '<CREDENTIAL_HELPER_PATH>') { return $false }
    if ($Config.CredentialReference.TtlSeconds -isnot [int] -or $Config.CredentialReference.TtlSeconds -ne 3600) { return $false }
    if ($Config.CredentialReference.TimeoutSeconds -isnot [int] -or $Config.CredentialReference.TimeoutSeconds -ne 60) { return $false }
    if ($Config.CredentialReference.SilentRefreshEnabled -isnot [bool] -or -not $Config.CredentialReference.SilentRefreshEnabled) { return $false }
    if ($Config.CredentialReference.PersistInConfig -isnot [bool] -or $Config.CredentialReference.PersistInConfig) { return $false }

    if (-not (Test-CddsiExactPropertySet -InputObject $Config.Ownership -Expected @('TargetSource', 'ExistingSourcePolicy', 'ConfigLibraryWriterEnabled'))) { return $false }
    if ($Config.Ownership.TargetSource -isnot [string] -or $Config.Ownership.TargetSource -cne 'HKCU_MANAGED_POLICY') { return $false }
    if ($Config.Ownership.ExistingSourcePolicy -isnot [string] -or $Config.Ownership.ExistingSourcePolicy -cne 'conflict-stop') { return $false }
    if ($Config.Ownership.ConfigLibraryWriterEnabled -isnot [bool] -or $Config.Ownership.ConfigLibraryWriterEnabled) { return $false }

    $serialized = ConvertTo-CddsiJson -InputObject $Config
    return (@(Find-CddsiPotentialSecrets -Content $serialized -Source '<desired-config>').Count -eq 0)
}

function ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Config,
        [Parameter(Mandatory = $true)][string]$CredentialHelperPath
    )

    if (-not (Test-CddsiClaudeDesktopConfigContract -Config $Config)) {
        throw 'Config 不符合 claude-desktop-3p-managed-policy-v1 合同。'
    }
    if ([string]::IsNullOrWhiteSpace($CredentialHelperPath) -or $CredentialHelperPath -cne $CredentialHelperPath.Trim()) {
        throw 'CredentialHelperPath 必须是非空且无首尾空白的绝对本地路径。'
    }
    if ($CredentialHelperPath -notmatch '^[A-Za-z]:\\' -or $CredentialHelperPath.StartsWith('\\') -or $CredentialHelperPath.Contains('/')) {
        throw 'CredentialHelperPath 必须是绝对本地 Windows 路径；拒绝相对路径和 UNC。'
    }
    if ($CredentialHelperPath -match '[\x00-\x1F\x7F\*\?"<>\|]') {
        throw 'CredentialHelperPath 包含不允许的字符。'
    }
    if (@(Find-CddsiPotentialSecrets -Content $CredentialHelperPath -Source '<credential-helper-path>').Count -ne 0) {
        throw 'CredentialHelperPath 不得包含疑似凭据材料。'
    }
    $pathSegments = @($CredentialHelperPath.Substring(3).Split('\'))
    if ($pathSegments.Count -eq 0) { throw 'CredentialHelperPath 必须指向可执行文件。' }
    foreach ($segment in $pathSegments) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -ceq '.' -or $segment -ceq '..' -or $segment.EndsWith('.') -or $segment.EndsWith(' ')) {
            throw 'CredentialHelperPath 包含不安全或不规范的路径段。'
        }
    }
    try {
        $normalizedHelperPath = [System.IO.Path]::GetFullPath($CredentialHelperPath)
    }
    catch {
        throw 'CredentialHelperPath 无法按纯语法规则规范化。'
    }
    if (-not [string]::Equals($normalizedHelperPath, $CredentialHelperPath, [StringComparison]::OrdinalIgnoreCase)) {
        throw 'CredentialHelperPath 必须已经是规范化绝对路径。'
    }

    $modelPayload = @(
        $Config.ModelPolicy.Models | ForEach-Object {
            [pscustomobject][ordered]@{
                name          = $_.Name
                labelOverride = $_.LabelOverride
                supports1m    = $_.Supports1m
            }
        }
    )
    $modelJson = $modelPayload | ConvertTo-Json -Depth 5 -Compress
    $rawValues = [ordered]@{
        autoModeEnabled                               = 'false'
        chatTabEnabled                                = 'true'
        coworkTabEnabled                              = 'true'
        disableDeploymentModeChooser                  = 'true'
        inferenceCredentialHelper                     = $CredentialHelperPath
        inferenceCredentialHelperSilentRefreshEnabled = 'true'
        inferenceCredentialHelperTimeoutSec           = '60'
        inferenceCredentialHelperTtlSec               = '3600'
        inferenceCredentialKind                       = 'helper-script'
        inferenceGatewayAuthScheme                    = 'x-api-key'
        inferenceGatewayBaseUrl                       = 'https://api.deepseek.com/anthropic'
        inferenceModels                               = $modelJson
        inferenceProvider                             = 'gateway'
        isClaudeCodeForDesktopEnabled                 = 'true'
        modelDiscoveryEnabled                         = 'false'
    }
    [string[]]$names = @($rawValues.Keys | ForEach-Object { [string]$_ })
    [System.Array]::Sort($names, [System.StringComparer]::Ordinal)
    $values = @()
    foreach ($name in $names) {
        $values += [pscustomobject][ordered]@{
            Name = $name
            Type = 'REG_SZ'
            Data = [string]$rawValues[$name]
        }
    }

    return [pscustomobject][ordered]@{
        SchemaVersion   = 1
        ContractVersion = $Config.ContractVersion
        TargetSource    = 'HKCU_MANAGED_POLICY'
        RegistryKey     = 'HKCU\SOFTWARE\Policies\Claude'
        Values          = @($values | ForEach-Object { $_ })
    }
}

function Compare-CddsiClaudeDesktopConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Current,
        [Parameter(Mandatory = $true)]$Desired
    )

    if (-not (Test-CddsiClaudeDesktopConfigContract -Config $Desired)) {
        throw 'Desired 不符合固定 3P managed-policy 合同。'
    }
    if (-not (Test-CddsiExactPropertySet -InputObject $Current -Expected @('SchemaVersion', 'HklmManagedPolicy', 'HkcuManagedPolicy', 'ConfigLibrary'))) {
        throw 'Current source metadata schema 不完整或包含未知字段。'
    }
    if ($Current.SchemaVersion -isnot [int] -or $Current.SchemaVersion -ne 1) {
        throw 'Current source metadata schemaVersion 不受支持。'
    }

    $sourceDefinitions = @(
        [pscustomobject]@{ Property = 'HklmManagedPolicy'; Source = 'HKLM_MANAGED_POLICY' },
        [pscustomobject]@{ Property = 'HkcuManagedPolicy'; Source = 'HKCU_MANAGED_POLICY' },
        [pscustomobject]@{ Property = 'ConfigLibrary'; Source = 'CONFIG_LIBRARY' }
    )
    $existingSources = @()
    foreach ($definition in $sourceDefinitions) {
        $metadata = $Current.($definition.Property)
        if (-not (Test-CddsiExactPropertySet -InputObject $metadata -Expected @('Present', 'Ownership'))) {
            throw ('Current.{0} 必须只包含 Present 和 Ownership。' -f $definition.Property)
        }
        if ($metadata.Present -isnot [bool]) {
            throw ('Current.{0}.Present 必须是布尔值。' -f $definition.Property)
        }
        if ($metadata.Ownership -isnot [string] -or @('NONE', 'PROJECT', 'EXTERNAL', 'UNKNOWN') -cnotcontains $metadata.Ownership) {
            throw ('Current.{0}.Ownership 不受支持。' -f $definition.Property)
        }
        if ((-not $metadata.Present -and $metadata.Ownership -cne 'NONE') -or ($metadata.Present -and $metadata.Ownership -ceq 'NONE')) {
            throw ('Current.{0} 的 Present 与 Ownership 不一致。' -f $definition.Property)
        }
        if ($metadata.Present) { $existingSources += $definition.Source }
    }

    $effectiveSource = 'NONE'
    if ($Current.HklmManagedPolicy.Present) {
        $effectiveSource = 'HKLM_MANAGED_POLICY'
    }
    elseif ($Current.HkcuManagedPolicy.Present) {
        $effectiveSource = 'HKCU_MANAGED_POLICY'
    }
    elseif ($Current.ConfigLibrary.Present) {
        $effectiveSource = 'CONFIG_LIBRARY'
    }
    $conflict = ($existingSources.Count -gt 0)
    $status = if ($conflict) { 'ACTION_REQUIRED' } else { 'SUCCEEDED' }
    $errorCode = if ($conflict) { 'CONFIG_SOURCE_CONFLICT' } else { '' }
    $reasonCodes = if ($conflict) {
        @('CONFIG_SOURCE_CONFLICT', ('EFFECTIVE_SOURCE_{0}' -f $effectiveSource))
    }
    else {
        @('TARGET_AVAILABLE')
    }
    $data = [pscustomobject][ordered]@{
        SchemaVersion  = 1
        TargetSource   = 'HKCU_MANAGED_POLICY'
        EffectiveSource = $effectiveSource
        ExistingSources = @($existingSources | ForEach-Object { $_ })
        Conflict       = $conflict
        CanProceed     = (-not $conflict)
        ReasonCodes    = @($reasonCodes)
    }
    $message = if ($conflict) {
        '检测到 synthetic 配置来源占用；P2 默认停止且不读取配置正文。'
    }
    else {
        'synthetic source metadata 表明 HKCU managed-policy 目标可用。'
    }
    return New-CddsiOperationResult -Operation 'CompareManagedPolicySources' -Status $status -Mode 'TestSafe' -ErrorCode $errorCode -MessageSafe $message -Data $data
}

function Test-CddsiConfigOperationAuthorizationBundle {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$AuthorizationBundle,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][ValidateSet('CLAIMED', 'COMPLETED', 'ABORTED')][string]$ExpectedState,
        [AllowNull()][string]$ValidationTimeUtc,
        [AllowNull()][string]$ExpectedProviderEvidenceDigest
    )

    $bundleFields = @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState')
    if (-not (Test-CddsiExactPropertySet -InputObject $AuthorizationBundle -Expected $bundleFields)) { return $false }
    if ($null -eq $AuthorizationBundle.OperationUseState -or $AuthorizationBundle.OperationUseState.State -cne $ExpectedState) { return $false }

    try {
        if ($ExpectedState -ceq 'CLAIMED') {
            if ($ValidationTimeUtc -isnot [string]) { return $false }
            return [bool](Test-CddsiCommittedOperationUseReceipt `
                -StageManifest $AuthorizationBundle.StageManifest `
                -OperationGrant $AuthorizationBundle.OperationGrant `
                -AuthorizationSession $AuthorizationBundle.AuthorizationSession `
                -WorkflowSessionState $AuthorizationBundle.WorkflowSessionState `
                -OperationUseState $AuthorizationBundle.OperationUseState `
                -Operation $Operation `
                -OperationUseId $OperationUseId `
                -ValidationTimeUtc $ValidationTimeUtc)
        }

        if ($ExpectedProviderEvidenceDigest -isnot [string] -or $ExpectedProviderEvidenceDigest -notmatch '^[a-f0-9]{64}$') { return $false }
        return [bool](Test-CddsiTerminalOperationUseReceipt `
            -StageManifest $AuthorizationBundle.StageManifest `
            -OperationGrant $AuthorizationBundle.OperationGrant `
            -AuthorizationSession $AuthorizationBundle.AuthorizationSession `
            -WorkflowSessionState $AuthorizationBundle.WorkflowSessionState `
            -OperationUseState $AuthorizationBundle.OperationUseState `
            -Operation $Operation `
            -OperationUseId $OperationUseId `
            -Outcome $ExpectedState `
            -ExpectedProviderEvidenceDigest $ExpectedProviderEvidenceDigest)
    }
    catch {
        return $false
    }
}

function Get-CddsiConfigBackupEvidenceBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence
    )

    $bindingText = @(
        'cddsi-config-backup-evidence-v2',
        [string]$Evidence.RunId,
        [string]$Evidence.ArtifactSha256,
        [string]$Evidence.SidecarSha256,
        [string]$Evidence.ContentDigest,
        [string]$Evidence.Profile,
        [string]$Evidence.GrantId,
        [string]$Evidence.ClaimId,
        [string]$Evidence.ConfirmationId,
        [string]$Evidence.Operation,
        [string]$Evidence.OperationUseId,
        [string]$Evidence.OperationUseReceiptBindingToken,
        [string]$Evidence.BackupId,
        [string]$Evidence.TargetSource,
        [string]$Evidence.RegistryKeyToken,
        [string]$Evidence.ValueCount,
        [string]$Evidence.ValueSetSha256,
        [string]$Evidence.BlobToken,
        [string]$Evidence.OwnerBindingToken,
        [string]$Evidence.ReadbackSha256,
        [string]$Evidence.ProtectionEvidenceSha256,
        [string]$Evidence.OperationNonce,
        [string]$Evidence.CreatedAtUtc,
        [string]$Evidence.Protection,
        [string]$Evidence.AclPolicy,
        ([string]$Evidence.OwnerBound).ToLowerInvariant(),
        ([string]$Evidence.Restorable).ToLowerInvariant(),
        ([string]$Evidence.RedactedSnapshot).ToLowerInvariant()
    ) -join '|'
    return Get-CddsiSupplyChainTextBindingToken -Text $bindingText
}

function Test-CddsiConfigBackupEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$BackupAuthorization
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'BindingToken', 'RunId', 'ArtifactSha256',
        'SidecarSha256', 'ContentDigest', 'Profile', 'GrantId', 'ClaimId', 'ConfirmationId',
        'Operation', 'OperationUseId', 'OperationUseReceiptBindingToken', 'BackupId',
        'TargetSource', 'RegistryKeyToken', 'ValueCount', 'ValueSetSha256', 'BlobToken',
        'OwnerBindingToken', 'ReadbackSha256', 'ProtectionEvidenceSha256', 'OperationNonce',
        'CreatedAtUtc', 'Protection', 'AclPolicy', 'OwnerBound', 'Restorable', 'RedactedSnapshot'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or $Evidence.ContractVersion -cne 'cddsi-config-backup-evidence-v2') { return $false }
    if ($Evidence.BindingToken -isnot [string] -or $Evidence.BindingToken -cne (Get-CddsiConfigBackupEvidenceBindingToken -Evidence $Evidence)) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $BackupAuthorization -Expected @(
        'StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState', 'OperationUseState'
    ))) { return $false }

    $operationState = $BackupAuthorization.OperationUseState
    if (-not (Test-CddsiConfigOperationAuthorizationBundle -AuthorizationBundle $BackupAuthorization -Operation 'BackupManagedPolicy' -OperationUseId $Evidence.OperationUseId -ExpectedState COMPLETED -ExpectedProviderEvidenceDigest $Evidence.ProtectionEvidenceSha256)) { return $false }
    foreach ($name in @('RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'GrantId', 'ClaimId', 'ConfirmationId', 'OperationUseId')) {
        if ($Evidence.$name -cne $operationState.$name) { return $false }
    }
    if ($Evidence.Profile -cne $operationState.ArtifactProfile -or @('VmAcceptance', 'UserLive') -cnotcontains $Evidence.Profile) { return $false }
    if ($Evidence.Operation -cne 'BackupManagedPolicy' -or $Evidence.OperationUseReceiptBindingToken -cne $operationState.ReceiptBindingToken) { return $false }
    if (-not (Test-CddsiCanonicalUuidValue -Value $Evidence.RunId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.GrantId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.ClaimId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.ConfirmationId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.OperationUseId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Evidence.OperationNonce)) { return $false }
    if (@(@($Evidence.RunId, $Evidence.GrantId, $Evidence.ClaimId, $Evidence.ConfirmationId, $Evidence.OperationUseId, $Evidence.OperationNonce) | Select-Object -Unique).Count -ne 6) { return $false }
    foreach ($hash in @($Evidence.ArtifactSha256, $Evidence.SidecarSha256, $Evidence.ContentDigest, $Evidence.OperationUseReceiptBindingToken, $Evidence.ValueSetSha256, $Evidence.OwnerBindingToken, $Evidence.ReadbackSha256, $Evidence.ProtectionEvidenceSha256)) {
        if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    if ($Evidence.BackupId -isnot [string] -or $Evidence.BackupId -notmatch '^backup-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { return $false }
    if ($Evidence.BlobToken -isnot [string] -or $Evidence.BlobToken -notmatch '^<CONFIG_BACKUP_BLOB:[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}>$') { return $false }
    $backupUuid = $Evidence.BackupId.Substring('backup-'.Length)
    $blobUuid = $Evidence.BlobToken.Substring('<CONFIG_BACKUP_BLOB:'.Length, 36)
    if (@(@(
        $Evidence.RunId, $Evidence.GrantId, $Evidence.ClaimId, $Evidence.ConfirmationId,
        $Evidence.OperationUseId, $Evidence.OperationNonce, $backupUuid, $blobUuid
    ) | Select-Object -Unique).Count -ne 8) { return $false }
    if ($Evidence.TargetSource -cne 'HKCU_MANAGED_POLICY' -or $Evidence.RegistryKeyToken -cne '<HKCU_MANAGED_POLICY>') { return $false }
    if (($Evidence.ValueCount -isnot [int] -and $Evidence.ValueCount -isnot [long]) -or [long]$Evidence.ValueCount -lt 0 -or [long]$Evidence.ValueCount -gt 64) { return $false }
    if ($Evidence.ReadbackSha256 -cne $Evidence.ValueSetSha256) { return $false }

    $ownerBinding = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-config-backup-owner-v2', $Evidence.RunId, $Evidence.ArtifactSha256,
        $Evidence.SidecarSha256, $Evidence.ContentDigest, $Evidence.Profile, $Evidence.GrantId,
        $Evidence.ClaimId, $Evidence.OperationUseId, $Evidence.BackupId, $Evidence.BlobToken,
        $Evidence.OperationNonce
    ) -join '|')
    if ($Evidence.OwnerBindingToken -cne $ownerBinding) { return $false }
    $providerEvidenceDigest = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-config-backup-provider-evidence-v2', $Evidence.RunId, $Evidence.ArtifactSha256,
        $Evidence.SidecarSha256, $Evidence.ContentDigest, $Evidence.Profile, $Evidence.GrantId,
        $Evidence.ClaimId, $Evidence.ConfirmationId, $Evidence.Operation, $Evidence.OperationUseId,
        $Evidence.BackupId, $Evidence.TargetSource, $Evidence.RegistryKeyToken,
        [string]$Evidence.ValueCount, $Evidence.ValueSetSha256, $Evidence.BlobToken,
        $Evidence.OwnerBindingToken, $Evidence.ReadbackSha256, $Evidence.OperationNonce,
        $Evidence.CreatedAtUtc, $Evidence.Protection, $Evidence.AclPolicy,
        ([string]$Evidence.OwnerBound).ToLowerInvariant(),
        ([string]$Evidence.Restorable).ToLowerInvariant(),
        ([string]$Evidence.RedactedSnapshot).ToLowerInvariant()
    ) -join '|')
    if ($Evidence.ProtectionEvidenceSha256 -cne $providerEvidenceDigest) { return $false }
    if ($Evidence.CreatedAtUtc -isnot [string] -or
        $Evidence.CreatedAtUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$' -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.CreatedAtUtc)) { return $false }
    try {
        $created = [DateTimeOffset]::Parse($Evidence.CreatedAtUtc)
        $claimed = [DateTimeOffset]::Parse($operationState.ClaimedAtUtc)
        $occurred = [DateTimeOffset]::Parse($operationState.OccurredAtUtc)
        $expires = [DateTimeOffset]::Parse($operationState.ExpiresAtUtc)
        if ($created -lt $claimed -or $created -gt $occurred -or $occurred -ge $expires) { return $false }
    }
    catch { return $false }

    if ($Evidence.Protection -cne 'DPAPI_CURRENT_USER' -or $Evidence.AclPolicy -cne 'CURRENT_USER_ONLY') { return $false }
    foreach ($name in @('OwnerBound', 'Restorable', 'RedactedSnapshot')) {
        if ($Evidence.$name -isnot [bool]) { return $false }
    }
    return ($Evidence.OwnerBound -and $Evidence.Restorable -and -not $Evidence.RedactedSnapshot)
}

function Test-CddsiManagedPolicyValueSet {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ValueSet
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $ValueSet -Expected @('SchemaVersion', 'ContractVersion', 'TargetSource', 'RegistryKey', 'Values'))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $ValueSet.SchemaVersion)) { return $false }
        if ($ValueSet.ContractVersion -isnot [string] -or $ValueSet.ContractVersion -cne 'claude-desktop-3p-managed-policy-v1') { return $false }
        if ($ValueSet.TargetSource -isnot [string] -or $ValueSet.TargetSource -cne 'HKCU_MANAGED_POLICY') { return $false }
        if ($ValueSet.RegistryKey -isnot [string] -or $ValueSet.RegistryKey -cne 'HKCU\SOFTWARE\Policies\Claude') { return $false }
        $values = @($ValueSet.Values)
        if ($ValueSet.Values -isnot [System.Array] -or $values.Count -ne 15) { return $false }
        foreach ($value in $values) {
            if (-not (Test-CddsiExactPropertySet -InputObject $value -Expected @('Name', 'Type', 'Data'))) { return $false }
            if ($value.Name -isnot [string] -or $value.Type -isnot [string] -or $value.Data -isnot [string]) { return $false }
        }
        $helperEntries = @($values | Where-Object { $_.Name -is [string] -and $_.Name -ceq 'inferenceCredentialHelper' })
        if ($helperEntries.Count -ne 1) { return $false }
        $expected = ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet -Config (New-CddsiClaudeDesktopDesiredConfig) -CredentialHelperPath $helperEntries[0].Data
        $expectedValues = @($expected.Values)
        for ($index = 0; $index -lt $expectedValues.Count; $index++) {
            foreach ($name in @('Name', 'Type', 'Data')) {
                if ($values[$index].$name -cne $expectedValues[$index].$name) { return $false }
            }
        }
        return (@(Find-CddsiPotentialSecrets -Content (ConvertTo-CddsiJson -InputObject $ValueSet) -Source '<managed-policy-value-set>').Count -eq 0)
    }
    catch {
        return $false
    }
}

function New-CddsiConfigBackupPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$SourceDecision,
        [Parameter(Mandatory = $true)]$BackupAuthorization,
        [Parameter(Mandatory = $true)][string]$BackupId,
        [Parameter(Mandatory = $true)][string]$OperationNonce,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $operationResultProperties = @('Operation', 'Status', 'Success', 'Changed', 'Mode', 'ErrorCode', 'MessageSafe', 'Data', 'RestartRequired', 'PlannedChanges', 'Warnings')
    if (-not (Test-CddsiExactPropertySet -InputObject $SourceDecision -Expected $operationResultProperties) -or
        -not (Test-CddsiExactPropertySet -InputObject $SourceDecision.Data -Expected @('SchemaVersion', 'TargetSource', 'EffectiveSource', 'ExistingSources', 'Conflict', 'CanProceed', 'ReasonCodes'))) { throw '配置来源决定 schema 无效。' }
    if ($SourceDecision.Operation -cne 'CompareManagedPolicySources' -or $SourceDecision.Mode -cne 'TestSafe' -or $SourceDecision.Changed -or $SourceDecision.RestartRequired) { throw '配置来源决定 provenance 无效。' }
    if ($SourceDecision.Status -cne 'SUCCEEDED' -or $SourceDecision.Success -isnot [bool] -or -not $SourceDecision.Success -or $SourceDecision.Data.CanProceed -isnot [bool] -or -not $SourceDecision.Data.CanProceed) {
        throw '配置来源未证明可写。'
    }
    if ($SourceDecision.Data.SchemaVersion -ne 1 -or $SourceDecision.Data.TargetSource -cne 'HKCU_MANAGED_POLICY' -or $SourceDecision.Data.Conflict -isnot [bool] -or $SourceDecision.Data.Conflict -or @($SourceDecision.Data.ExistingSources).Count -ne 0) { throw '配置来源存在冲突或证据不完整。' }
    if ($BackupId -notmatch '^backup-[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') { throw 'BackupId 必须是 canonical backup UUID。' }
    if (-not (Test-CddsiCanonicalUuidValue -Value $OperationNonce)) { throw 'OperationNonce 必须是 canonical UUID。' }
    $operationUseId = [string]$BackupAuthorization.OperationUseState.OperationUseId
    if (-not (Test-CddsiConfigOperationAuthorizationBundle -AuthorizationBundle $BackupAuthorization -Operation 'BackupManagedPolicy' -OperationUseId $operationUseId -ExpectedState CLAIMED -ValidationTimeUtc $ValidationTimeUtc)) { throw 'BackupManagedPolicy authorization 未提交或绑定无效。' }
    $state = $BackupAuthorization.OperationUseState
    if ($state.ArtifactProfile -cnotin @('VmAcceptance', 'UserLive')) { throw '配置 backup profile 无效。' }
    if (@(@($state.RunId, $state.GrantId, $state.ClaimId, $state.ConfirmationId, $state.OperationUseId, $OperationNonce) | Select-Object -Unique).Count -ne 6) { throw '配置 backup identifier 不得碰撞。' }
    if (@($state.RunId, $state.GrantId, $state.ClaimId, $state.ConfirmationId, $state.OperationUseId, $OperationNonce) -ccontains $BackupId.Substring('backup-'.Length)) { throw 'BackupId 不得与授权标识碰撞。' }

    $sourceDecisionSha256 = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiJson -InputObject $SourceDecision)
    $planId = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-config-backup-plan-v2', $state.RunId, $state.ArtifactSha256, $state.SidecarSha256,
        $state.ContentDigest, $state.ArtifactProfile, $state.GrantId, $state.ClaimId,
        $state.ConfirmationId, $state.OperationUseId, $state.ReceiptBindingToken,
        $BackupId, $OperationNonce, $sourceDecisionSha256, $ValidationTimeUtc
    ) -join '|')

    return [pscustomobject][ordered]@{
        SchemaVersion   = 2
        ContractVersion = 'cddsi-config-backup-plan-v2'
        PlanId          = $planId
        RunId           = $state.RunId
        ArtifactSha256  = $state.ArtifactSha256
        SidecarSha256   = $state.SidecarSha256
        ContentDigest   = $state.ContentDigest
        Profile         = $state.ArtifactProfile
        GrantId         = $state.GrantId
        ClaimId         = $state.ClaimId
        ConfirmationId  = $state.ConfirmationId
        OperationUseId  = $state.OperationUseId
        AuthorizationReceiptBindingToken = $state.ReceiptBindingToken
        TargetSource    = 'HKCU_MANAGED_POLICY'
        RegistryKeyToken = '<HKCU_MANAGED_POLICY>'
        BackupId        = $BackupId
        OperationNonce  = $OperationNonce
        SourceDecisionSha256 = $sourceDecisionSha256
        ValidationTimeUtc = $ValidationTimeUtc
        AuthorizationExpiresAtUtc = $state.ExpiresAtUtc
        Steps           = @('source_validated', 'backup_create', 'backup_readback', 'commit_backup')
        CleanupAuthorizationSlot = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-config-post-backup-authorization-slot-template-v1'
            Operation = 'RemoveManagedPolicyBackup'
            Trigger = 'BACKUP_CREATION_OR_LIFECYCLE_CLEANUP'
            Required = $true
            IndependentOperationUseRequired = $true
            IssuancePhase = 'POST_BACKUP_TERMINAL_ONLY'
            MustBindBackupTerminalReceipt = $true
            MustUseFreshConfirmation = $true
        }
    }
}

function New-CddsiConfigTransactionPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$SourceDecision,
        [Parameter(Mandatory = $true)]$ValueSet,
        [Parameter(Mandatory = $true)]$BackupEvidence,
        [Parameter(Mandatory = $true)]$BackupAuthorization,
        [Parameter(Mandatory = $true)]$WriteAuthorization,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    $operationResultProperties = @('Operation', 'Status', 'Success', 'Changed', 'Mode', 'ErrorCode', 'MessageSafe', 'Data', 'RestartRequired', 'PlannedChanges', 'Warnings')
    if (-not (Test-CddsiExactPropertySet -InputObject $SourceDecision -Expected $operationResultProperties) -or
        -not (Test-CddsiExactPropertySet -InputObject $SourceDecision.Data -Expected @('SchemaVersion', 'TargetSource', 'EffectiveSource', 'ExistingSources', 'Conflict', 'CanProceed', 'ReasonCodes'))) { throw '配置来源决定 schema 无效。' }
    if ($SourceDecision.Operation -cne 'CompareManagedPolicySources' -or $SourceDecision.Mode -cne 'TestSafe' -or $SourceDecision.Changed -or $SourceDecision.RestartRequired -or
        $SourceDecision.Status -cne 'SUCCEEDED' -or $SourceDecision.Success -isnot [bool] -or -not $SourceDecision.Success -or
        $SourceDecision.Data.SchemaVersion -ne 1 -or $SourceDecision.Data.TargetSource -cne 'HKCU_MANAGED_POLICY' -or
        $SourceDecision.Data.Conflict -isnot [bool] -or $SourceDecision.Data.Conflict -or
        $SourceDecision.Data.CanProceed -isnot [bool] -or -not $SourceDecision.Data.CanProceed -or
        @($SourceDecision.Data.ExistingSources).Count -ne 0) { throw '配置来源未证明当前可写。' }
    if (-not (Test-CddsiManagedPolicyValueSet -ValueSet $ValueSet)) { throw 'ValueSet contract 无效。' }
    if (-not (Test-CddsiConfigBackupEvidence -Evidence $BackupEvidence -BackupAuthorization $BackupAuthorization)) { throw '不可变 backup evidence 或已完成授权 receipt 无效。' }

    $writeUseId = [string]$WriteAuthorization.OperationUseState.OperationUseId
    if (-not (Test-CddsiConfigOperationAuthorizationBundle -AuthorizationBundle $WriteAuthorization -Operation 'WriteManagedPolicy' -OperationUseId $writeUseId -ExpectedState CLAIMED -ValidationTimeUtc $ValidationTimeUtc)) { throw 'WriteManagedPolicy authorization 未提交或绑定无效。' }
    $backupState = $BackupAuthorization.OperationUseState
    $writeState = $WriteAuthorization.OperationUseState
    foreach ($name in @(
        'Stage', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'ArtifactProfile',
        'GrantId', 'Nonce', 'ClaimId', 'AuthorizationSessionRevision',
        'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision', 'ExpiresAtUtc'
    )) {
        if ($backupState.$name -cne $writeState.$name) { throw 'Backup 与 write authorization package/session binding 不一致。' }
    }
    if ($writeState.ArtifactProfile -cnotin @('VmAcceptance', 'UserLive')) { throw '配置 write profile 无效。' }
    if ($backupState.OperationUseId -ceq $writeState.OperationUseId -or
        $backupState.ConfirmationId -ceq $writeState.ConfirmationId -or
        $backupState.ReceiptBindingToken -ceq $writeState.ReceiptBindingToken) { throw 'Backup 与 write 必须使用独立 operation-use receipt。' }
    if ([DateTimeOffset]::Parse($backupState.OccurredAtUtc) -ge [DateTimeOffset]::Parse($writeState.ClaimedAtUtc)) {
        throw 'WriteManagedPolicy claim 必须晚于 backup terminal receipt。'
    }

    $sourceDecisionSha256 = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiJson -InputObject $SourceDecision)
    $desiredValueSetSha256 = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiJson -InputObject $ValueSet)
    $planId = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-config-write-plan-v2', $writeState.RunId, $writeState.ArtifactSha256,
        $writeState.SidecarSha256, $writeState.ContentDigest, $writeState.ArtifactProfile,
        $writeState.GrantId, $writeState.ClaimId, $BackupEvidence.BindingToken,
        $backupState.OperationUseId, $backupState.ReceiptBindingToken, $writeState.OperationUseId,
        $writeState.ReceiptBindingToken, $sourceDecisionSha256, $desiredValueSetSha256,
        $ValidationTimeUtc
    ) -join '|')
    $transactionId = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-config-write-transaction-v2', $planId, $BackupEvidence.BackupId,
        $BackupEvidence.ValueSetSha256, $desiredValueSetSha256, $writeState.OperationUseId
    ) -join '|')

    return [pscustomobject][ordered]@{
        SchemaVersion = 2
        ContractVersion = 'cddsi-config-write-transaction-v2'
        PlanId = $planId
        TransactionId = $transactionId
        RunId = $writeState.RunId
        ArtifactSha256 = $writeState.ArtifactSha256
        SidecarSha256 = $writeState.SidecarSha256
        ContentDigest = $writeState.ContentDigest
        Profile = $writeState.ArtifactProfile
        GrantId = $writeState.GrantId
        ClaimId = $writeState.ClaimId
        BackupId = $BackupEvidence.BackupId
        BackupEvidenceBindingToken = $BackupEvidence.BindingToken
        BackupValueSetSha256 = $BackupEvidence.ValueSetSha256
        BackupOperationUseId = $backupState.OperationUseId
        BackupAuthorizationReceiptBindingToken = $backupState.ReceiptBindingToken
        WriteOperationUseId = $writeState.OperationUseId
        WriteConfirmationId = $writeState.ConfirmationId
        WriteAuthorizationReceiptBindingToken = $writeState.ReceiptBindingToken
        WriteClaimedAtUtc = $writeState.ClaimedAtUtc
        WriteAuthorizationExpiresAtUtc = $writeState.ExpiresAtUtc
        SourceDecisionSha256 = $sourceDecisionSha256
        DesiredValueSetSha256 = $desiredValueSetSha256
        ValidationTimeUtc = $ValidationTimeUtc
        TargetSource = 'HKCU_MANAGED_POLICY'
        RegistryKeyToken = '<HKCU_MANAGED_POLICY>'
        ValueCount = 15
        Steps = @('policy_write', 'policy_readback', 'commit')
        RequiresAtomicCompensation = $true
        ConfigLibraryWriterEnabled = $false
        RequiredAuthorizationSlots = @(
            [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-config-post-write-authorization-slot-template-v1'
                Operation = 'RestoreManagedPolicy'
                Trigger = 'WRITE_MUTATION_REQUIRES_COMPENSATION'
                Required = $true
                IndependentOperationUseRequired = $true
                IssuancePhase = 'POST_WRITE_TERMINAL_ONLY'
                MustBindPlanAndTransaction = $true
                MustBindPrimaryTerminalReceipt = $true
                MustUseFreshConfirmation = $true
            },
            [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-config-post-write-authorization-slot-template-v1'
                Operation = 'RemoveManagedPolicyBackup'
                Trigger = 'BACKUP_LIFECYCLE_CLEANUP'
                Required = $true
                IndependentOperationUseRequired = $true
                IssuancePhase = 'POST_WRITE_TERMINAL_ONLY'
                MustBindPlanAndTransaction = $true
                MustBindPrimaryTerminalReceipt = $true
                MustUseFreshConfirmation = $true
            }
        )
    }
}

function Resolve-CddsiConfigTransactionTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Transcript,
        [Parameter(Mandatory = $true)]$ExpectedPlan,
        [Parameter(Mandatory = $true)]$SourceDecision,
        [Parameter(Mandatory = $true)]$ValueSet,
        [Parameter(Mandatory = $true)]$BackupEvidence,
        [Parameter(Mandatory = $true)]$BackupAuthorization,
        [Parameter(Mandatory = $true)]$WriteAuthorization,
        [Parameter(Mandatory = $true)]$WriteTerminalAuthorization
    )

    $rebuiltPlan = New-CddsiConfigTransactionPlan -SourceDecision $SourceDecision -ValueSet $ValueSet -BackupEvidence $BackupEvidence -BackupAuthorization $BackupAuthorization -WriteAuthorization $WriteAuthorization -ValidationTimeUtc $ExpectedPlan.ValidationTimeUtc
    if ((ConvertTo-CddsiJson -InputObject $ExpectedPlan -Depth 30) -cne (ConvertTo-CddsiJson -InputObject $rebuiltPlan -Depth 30)) { throw 'ExpectedPlan 无法从原始授权与 evidence 精确重建。' }

    $transcriptProperties = @(
        'SchemaVersion', 'ContractVersion', 'PlanId', 'TransactionId', 'RunId', 'ArtifactSha256',
        'SidecarSha256', 'ContentDigest', 'Profile', 'GrantId', 'ClaimId', 'BackupId',
        'BackupEvidenceBindingToken', 'BackupOperationUseId', 'WriteOperationUseId', 'Events'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Transcript -Expected $transcriptProperties)) { throw 'Transaction transcript schema 无效。' }
    if (($Transcript.SchemaVersion -isnot [int] -and $Transcript.SchemaVersion -isnot [long]) -or [long]$Transcript.SchemaVersion -ne 2 -or $Transcript.ContractVersion -cne 'cddsi-config-write-transaction-v2') { throw 'Transaction transcript contract 无效。' }
    foreach ($name in @('PlanId', 'TransactionId', 'RunId', 'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'Profile', 'GrantId', 'ClaimId', 'BackupId', 'BackupEvidenceBindingToken', 'BackupOperationUseId', 'WriteOperationUseId')) {
        if ($Transcript.$name -cne $ExpectedPlan.$name) { throw 'Transaction transcript binding 无效。' }
    }

    $events = @($Transcript.Events)
    if ($events.Count -lt 1 -or $events.Count -gt 3) { throw 'Transaction transcript event count 无效。' }
    $expectedSteps = @('policy_write', 'policy_readback', 'commit')
    $seenEvidence = @{}
    $previousTime = [DateTimeOffset]::Parse($ExpectedPlan.WriteClaimedAtUtc)
    $expiresAt = [DateTimeOffset]::Parse($ExpectedPlan.WriteAuthorizationExpiresAtUtc)
    $failureIndex = -1
    $mutationSeen = $false
    for ($index = 0; $index -lt $events.Count; $index++) {
        $event = $events[$index]
        if (-not (Test-CddsiExactPropertySet -InputObject $event -Expected @('Sequence', 'Name', 'Outcome', 'MutationState', 'OccurredAtUtc', 'OperationUseId', 'ProviderEvidenceSha256'))) { throw 'Transaction event schema 无效。' }
        if (($event.Sequence -isnot [int] -and $event.Sequence -isnot [long]) -or [long]$event.Sequence -ne ($index + 1)) { throw 'Transaction event sequence 无效。' }
        if ($event.Name -isnot [string] -or $event.Name -cne $expectedSteps[$index]) { throw 'Transaction event order 无效。' }
        if ($event.Outcome -isnot [string] -or @('SUCCEEDED', 'FAILED') -cnotcontains $event.Outcome) { throw 'Transaction event outcome 无效。' }
        if ($event.MutationState -isnot [string] -or @('NONE', 'UNCHANGED', 'CHANGED', 'UNKNOWN') -cnotcontains $event.MutationState) { throw 'Transaction event mutation state 无效。' }
        if ($event.OperationUseId -isnot [string] -or $event.OperationUseId -cne $ExpectedPlan.WriteOperationUseId) { throw 'Transaction event operation-use binding 无效。' }
        if ($event.OccurredAtUtc -isnot [string] -or $event.OccurredAtUtc -notmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$' -or -not (Test-CddsiUtcTimestampValue -Value $event.OccurredAtUtc)) { throw 'Transaction event time 无效。' }
        $occurredAt = [DateTimeOffset]::Parse($event.OccurredAtUtc)
        if ($occurredAt -lt $previousTime -or $occurredAt -ge $expiresAt) { throw 'Transaction event time window 无效。' }
        $previousTime = $occurredAt

        if ($index -eq 0) {
            if ($event.Outcome -ceq 'SUCCEEDED' -and $event.MutationState -cnotin @('UNCHANGED', 'CHANGED')) { throw '成功 policy write 必须明确 mutation。' }
            if ($event.Outcome -ceq 'FAILED' -and $event.MutationState -cnotin @('UNCHANGED', 'CHANGED', 'UNKNOWN')) { throw '失败 policy write 必须明确 mutation。' }
        }
        elseif ($event.MutationState -cne 'NONE') { throw 'readback/commit 不得声明 mutation。' }

        $expectedProviderEvidence = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-config-provider-event-v2', $ExpectedPlan.PlanId, $ExpectedPlan.TransactionId,
            $ExpectedPlan.WriteOperationUseId, [string]($index + 1), $event.Name, $event.Outcome,
            $event.MutationState, $event.OccurredAtUtc
        ) -join '|')
        if ($event.ProviderEvidenceSha256 -isnot [string] -or $event.ProviderEvidenceSha256 -cne $expectedProviderEvidence -or $seenEvidence.ContainsKey($event.ProviderEvidenceSha256)) { throw 'Transaction provider evidence binding 无效或重放。' }
        $seenEvidence[$event.ProviderEvidenceSha256] = $true
        if ($event.MutationState -in @('CHANGED', 'UNKNOWN')) { $mutationSeen = $true }
        if ($event.Outcome -ceq 'FAILED') {
            $failureIndex = $index
            if ($events.Count -ne ($index + 1)) { throw 'Transaction failure 后不得继续。' }
            break
        }
    }

    if ($failureIndex -lt 0 -and $events.Count -ne 3) { throw '成功 Transaction transcript 没有终态。' }
    $transcriptEvidenceDigest = Get-CddsiSupplyChainTextBindingToken -Text ((@($events | ForEach-Object { $_.ProviderEvidenceSha256 })) -join '|')
    $terminalOutcome = if ($failureIndex -lt 0) { 'COMPLETED' } else { 'ABORTED' }
    if (-not (Test-CddsiConfigOperationAuthorizationBundle -AuthorizationBundle $WriteTerminalAuthorization -Operation 'WriteManagedPolicy' -OperationUseId $ExpectedPlan.WriteOperationUseId -ExpectedState $terminalOutcome -ExpectedProviderEvidenceDigest $transcriptEvidenceDigest)) { throw 'WriteManagedPolicy terminal operation-use receipt 无效。' }
    foreach ($bundlePart in @('StageManifest', 'OperationGrant', 'AuthorizationSession', 'WorkflowSessionState')) {
        if ((ConvertTo-CddsiJson -InputObject $WriteTerminalAuthorization.$bundlePart -Depth 30) -cne
            (ConvertTo-CddsiJson -InputObject $WriteAuthorization.$bundlePart -Depth 30)) {
            throw 'WriteManagedPolicy terminal receipt 与原 CLAIMED bundle 不同源。'
        }
    }
    $claimedWriteState = $WriteAuthorization.OperationUseState
    $terminalWriteState = $WriteTerminalAuthorization.OperationUseState
    foreach ($name in @(
        'SchemaVersion', 'ContractVersion', 'StateKeySha256', 'Stage', 'ArtifactProfile', 'RunId',
        'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'GrantId', 'Nonce', 'ClaimId',
        'AuthorizationSessionRevision', 'WorkflowSessionStateKeySha256', 'WorkflowSessionRevision',
        'ConfirmationId', 'ConfirmationPromptDigest', 'ConfirmedAtUtc', 'ConfirmationConsumed',
        'Operation', 'OperationUseId', 'ClaimedAtUtc', 'ExpiresAtUtc', 'ProviderIdempotencyRequired'
    )) {
        if ($terminalWriteState.$name -cne $claimedWriteState.$name) {
            throw 'WriteManagedPolicy terminal receipt 的不可变 claim binding 漂移。'
        }
    }
    if ($terminalWriteState.Revision -ne ($claimedWriteState.Revision + 1) -or
        $terminalWriteState.OccurredAtUtc -cne $events[$events.Count - 1].OccurredAtUtc) {
        throw 'WriteManagedPolicy terminal receipt revision 或时间不一致。'
    }

    $cleanupSlot = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-config-post-write-authorization-slot-v1'
        Operation = 'RemoveManagedPolicyBackup'
        Trigger = 'BACKUP_LIFECYCLE_CLEANUP'
        Required = $true
        IndependentOperationUseRequired = $true
        PlanId = $ExpectedPlan.PlanId
        TransactionId = $ExpectedPlan.TransactionId
        BackupId = $ExpectedPlan.BackupId
        PrimaryOperation = 'WriteManagedPolicy'
        PrimaryOperationUseId = $ExpectedPlan.WriteOperationUseId
        PrimaryTerminalState = $terminalOutcome
        PrimaryTerminalReceiptBindingToken = $terminalWriteState.ReceiptBindingToken
        PrimaryProviderEvidenceDigest = $terminalWriteState.ProviderEvidenceDigest
        EarliestClaimAtUtc = $terminalWriteState.OccurredAtUtc
        MustUseFreshConfirmation = $true
        MustUseFreshOperationUseId = $true
    }
    $restoreSlot = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-config-post-write-authorization-slot-v1'
        Operation = 'RestoreManagedPolicy'
        Trigger = 'WRITE_MUTATION_REQUIRES_COMPENSATION'
        Required = $true
        IndependentOperationUseRequired = $true
        PlanId = $ExpectedPlan.PlanId
        TransactionId = $ExpectedPlan.TransactionId
        BackupId = $ExpectedPlan.BackupId
        PrimaryOperation = 'WriteManagedPolicy'
        PrimaryOperationUseId = $ExpectedPlan.WriteOperationUseId
        PrimaryTerminalState = $terminalOutcome
        PrimaryTerminalReceiptBindingToken = $terminalWriteState.ReceiptBindingToken
        PrimaryProviderEvidenceDigest = $terminalWriteState.ProviderEvidenceDigest
        EarliestClaimAtUtc = $terminalWriteState.OccurredAtUtc
        MustUseFreshConfirmation = $true
        MustUseFreshOperationUseId = $true
    }
    if ($failureIndex -lt 0) {
        return New-CddsiOperationResult -Operation 'ResolveConfigTransaction' -Status 'SUCCEEDED' -Mode 'TestSafe' -MessageSafe '配置 write transaction 已提交；backup cleanup 仍需独立授权。' -Data ([pscustomobject][ordered]@{
            TransactionStatus = 'COMMITTED'
            CompensationStatus = 'NOT_APPLICABLE'
            BackupCleanupStatus = 'REQUIRED_NOT_PROVEN'
            MutationOutcomeKnown = $true
            TransactionId = $ExpectedPlan.TransactionId
            PlanId = $ExpectedPlan.PlanId
            BackupId = $ExpectedPlan.BackupId
            RequiredAuthorizationSlots = @($cleanupSlot)
        })
    }

    $requiredSlots = @($cleanupSlot)
    if ($mutationSeen) { $requiredSlots = @($restoreSlot, $cleanupSlot) }
    return New-CddsiOperationResult -Operation 'ResolveConfigTransaction' -Status 'FAILED' -Mode 'TestSafe' `
        -ErrorCode $(if ($mutationSeen) { 'CONFIG_RESTORE_REQUIRED_NOT_PROVEN' } else { 'CONFIG_WRITE_FAILED_UNCHANGED' }) `
        -MessageSafe $(if ($mutationSeen) { '配置 write 失败且可能已变更；必须取得独立 RestoreManagedPolicy 授权后补偿。' } else { '配置 write 确认未变更；backup cleanup 仍需独立授权。' }) `
        -Data ([pscustomobject][ordered]@{
            TransactionStatus = 'FAILED'
            CompensationStatus = $(if ($mutationSeen) { 'REQUIRED_NOT_PROVEN' } else { 'NOT_APPLICABLE' })
            BackupCleanupStatus = 'REQUIRED_NOT_PROVEN'
            MutationOutcomeKnown = (-not $mutationSeen)
            TransactionId = $ExpectedPlan.TransactionId
            PlanId = $ExpectedPlan.PlanId
            BackupId = $ExpectedPlan.BackupId
            RequiredAuthorizationSlots = @($requiredSlots)
        })
}

function New-CddsiConfigRestorableBackup {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'BackupManagedPolicy' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'BackupManagedPolicy' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P2_BACKUP_NOT_IMPLEMENTED' -MessageSafe 'P2 不读取或备份 managed policy；未来恢复包必须使用 DPAPI 或等效保护。' -PlannedChanges @('<HKCU_MANAGED_POLICY>')
}

function New-CddsiConfigRedactedSnapshot {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'CreateRedactedManagedPolicySnapshot' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'CreateRedactedManagedPolicySnapshot' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P2_SNAPSHOT_NOT_IMPLEMENTED' -MessageSafe 'P2 不读取 policy 值；只定义无原始配置正文的未来快照边界。'
}

function Write-CddsiClaudeDesktopConfigAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)]$DesiredConfig,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if (-not (Test-CddsiClaudeDesktopConfigContract -Config $DesiredConfig)) {
        throw 'DesiredConfig 不符合固定 3P managed-policy 合同。'
    }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'WriteManagedPolicyAtomic' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'WriteManagedPolicyAtomic' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P2_WRITER_DISABLED' -MessageSafe 'P2 配置 writer 关闭；未写入 registry 或 configLibrary。' -PlannedChanges @('<HKCU_MANAGED_POLICY>')
}

function Restore-CddsiClaudeDesktopConfig {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$BackupId,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($BackupId -notmatch '^backup-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$') { throw 'BackupId 格式无效。' }
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'RestoreManagedPolicy' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'RestoreManagedPolicy' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'P2_RESTORE_NOT_IMPLEMENTED' -MessageSafe 'P2 不读取备份或恢复 policy。' -Data ([pscustomobject]@{ BackupId = $BackupId }) -PlannedChanges @('<HKCU_MANAGED_POLICY>')
}
