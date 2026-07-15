# deepseek-api.ps1 - Credential input and API validation contracts.
# No function in this scaffold performs a DeepSeek network request.

function New-CddsiCredentialHelperContract {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        SchemaVersion        = 1
        ContractVersion      = 'cddsi-credential-helper-v1'
        ImplementationKind   = 'SignedDotNetExe'
        InvocationKind       = 'DirectExecutable'
        ArgumentCount        = 0
        OutputFormat         = 'BareTokenSingleLine'
        ErrorOutputPolicy    = 'Empty'
        DpapiScope           = 'CurrentUser'
        CredentialResource   = '<CREDENTIAL:DEEPSEEK>'
        HelperResource       = '<CREDENTIAL_HELPER_EXE>'
        TtlSeconds           = 3600
        TimeoutSeconds       = 60
        SilentRefreshEnabled = $true
        PlaintextPersistence = $false
        ShellInvocation      = $false
    }
}

function Test-CddsiCredentialCaptureMetadata {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Metadata,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId
    )

    $required = @('SchemaVersion', 'RunId', 'HandleToken', 'CaptureNonce', 'Length', 'IsEmpty', 'HasLeadingOrTrailingWhitespace', 'ContainsWhitespace', 'ContainsControlCharacter', 'AsciiPrintableOnly', 'FormatValidated', 'Serializable')
    if (-not (Test-CddsiExactPropertySet -InputObject $Metadata -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Metadata.SchemaVersion)) { return $false }
    $expectedGuid = [guid]::Empty
    if (-not [guid]::TryParseExact($ExpectedRunId, 'D', [ref]$expectedGuid) -or $expectedGuid -eq [guid]::Empty -or $Metadata.RunId -cne $ExpectedRunId) { return $false }
    if ($Metadata.HandleToken -isnot [string] -or $Metadata.HandleToken -notmatch '^<CREDENTIAL_HANDLE:[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}>$') { return $false }
    if ($Metadata.CaptureNonce -isnot [string] -or $Metadata.CaptureNonce -notmatch '^nonce-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$') { return $false }
    if (@(Find-CddsiPotentialSecrets -Content $Metadata.HandleToken -Source '<credential-handle>').Count -ne 0) { return $false }
    if (($Metadata.Length -isnot [int] -and $Metadata.Length -isnot [long]) -or [long]$Metadata.Length -lt 20 -or [long]$Metadata.Length -gt 512) { return $false }
    foreach ($name in @('IsEmpty', 'HasLeadingOrTrailingWhitespace', 'ContainsWhitespace', 'ContainsControlCharacter', 'AsciiPrintableOnly', 'FormatValidated', 'Serializable')) {
        if ($Metadata.$name -isnot [bool]) { return $false }
    }
    return (-not $Metadata.IsEmpty -and -not $Metadata.HasLeadingOrTrailingWhitespace -and -not $Metadata.ContainsWhitespace -and -not $Metadata.ContainsControlCharacter -and $Metadata.AsciiPrintableOnly -and $Metadata.FormatValidated -and -not $Metadata.Serializable)
}

function Test-CddsiCredentialAuthorizationBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Binding
    )

    $required = @(
        'SchemaVersion', 'ContractVersion', 'Stage', 'ArtifactProfile', 'RunId',
        'ArtifactSha256', 'SidecarSha256', 'ContentDigest', 'GrantId', 'Nonce',
        'ClaimId', 'AuthorizationSessionRevision', 'ConfirmationId', 'Operation',
        'OperationUseId', 'OperationUseStateKeySha256', 'OperationUseRevision',
        'OperationUseClaimedAtUtc', 'OperationUseExpiresAtUtc', 'ReceiptBindingToken',
        'ProviderIdempotencyRequired', 'ProviderIdempotencyKey', 'BindingToken'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Binding -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Binding.SchemaVersion) -or $Binding.ContractVersion -cne 'cddsi-credential-authorization-binding-v1') { return $false }
    if ($Binding.Stage -isnot [string] -or $Binding.Stage -cnotin @('VmAcceptance', 'UserLive') -or $Binding.ArtifactProfile -cne $Binding.Stage) { return $false }
    foreach ($id in @($Binding.RunId, $Binding.GrantId, $Binding.Nonce, $Binding.ClaimId, $Binding.ConfirmationId, $Binding.OperationUseId)) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $id)) { return $false }
    }
    if (@(@($Binding.RunId, $Binding.GrantId, $Binding.Nonce, $Binding.ClaimId, $Binding.ConfirmationId, $Binding.OperationUseId) | Select-Object -Unique).Count -ne 6) { return $false }
    foreach ($hash in @($Binding.ArtifactSha256, $Binding.SidecarSha256, $Binding.ContentDigest, $Binding.OperationUseStateKeySha256, $Binding.ReceiptBindingToken, $Binding.BindingToken)) {
        if ($hash -isnot [string] -or $hash -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    if (@(@($Binding.ArtifactSha256, $Binding.SidecarSha256, $Binding.ContentDigest) | Select-Object -Unique).Count -ne 3) { return $false }
    if ($Binding.AuthorizationSessionRevision -isnot [int] -or $Binding.AuthorizationSessionRevision -lt 1 -or $Binding.OperationUseRevision -isnot [int] -or $Binding.OperationUseRevision -lt 1) { return $false }
    if ($Binding.Operation -isnot [string] -or $Binding.Operation -cnotin @('PersistCredential', 'RemoveCredential', 'RestoreCredentialState')) { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $Binding.OperationUseClaimedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $Binding.OperationUseExpiresAtUtc)) { return $false }
    if ([DateTimeOffset]::Parse($Binding.OperationUseClaimedAtUtc) -ge [DateTimeOffset]::Parse($Binding.OperationUseExpiresAtUtc)) { return $false }
    if ($Binding.ProviderIdempotencyRequired -isnot [bool] -or -not $Binding.ProviderIdempotencyRequired -or $Binding.ProviderIdempotencyKey -cne $Binding.OperationUseId) { return $false }

    $expectedToken = Get-CddsiSupplyChainTextBindingToken -Text ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}|{19}|{20}|{21}' -f
        $Binding.ContractVersion, $Binding.Stage, $Binding.ArtifactProfile, $Binding.RunId,
        $Binding.ArtifactSha256, $Binding.SidecarSha256, $Binding.ContentDigest,
        $Binding.GrantId, $Binding.Nonce, $Binding.ClaimId,
        $Binding.AuthorizationSessionRevision, $Binding.ConfirmationId, $Binding.Operation,
        $Binding.OperationUseId, $Binding.OperationUseStateKeySha256,
        $Binding.OperationUseRevision, $Binding.OperationUseClaimedAtUtc,
        $Binding.OperationUseExpiresAtUtc, $Binding.ReceiptBindingToken,
        $Binding.ProviderIdempotencyRequired, $Binding.ProviderIdempotencyKey, 'committed')
    return ($Binding.BindingToken -ceq $expectedToken)
}

function Resolve-CddsiCredentialAuthorizationBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$Confirmation,
        [Parameter(Mandatory = $true)]$CommittedOperationUseReceipt,
        [Parameter(Mandatory = $true)][ValidateSet('PersistCredential', 'RemoveCredential', 'RestoreCredentialState')][string]$ExpectedOperation,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    if (-not (Test-CddsiCanonicalUuidValue -Value $ExpectedRunId)) { throw 'ExpectedRunId 必须是 canonical UUID。' }
    foreach ($timestamp in @($OccurredAtUtc, $ValidationTimeUtc)) {
        if (-not (Test-CddsiUtcTimestampValue -Value $timestamp)) { throw 'Credential authorization timestamp 无效。' }
    }
    if ([DateTimeOffset]::Parse($OccurredAtUtc) -gt [DateTimeOffset]::Parse($ValidationTimeUtc)) { throw 'Credential authorization occurrence 不得位于未来。' }
    $bindingResult = Resolve-CddsiOperationAuthorizationBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -Confirmation $Confirmation -Operation $ExpectedOperation -RunId $ExpectedRunId `
        -NowUtc $ValidationTimeUtc
    if ($bindingResult.Status -cne 'SUCCEEDED' -or -not $bindingResult.Data.BindingValid) {
        throw 'Credential operation stage authorization binding 无效。'
    }
    if ($StageManifest.Stage -cnotin @('VmAcceptance', 'UserLive') -or
        $StageManifest.Stage -cne $StageManifest.ArtifactProfile) {
        throw 'Credential operation 只允许 VmAcceptance 或 UserLive。'
    }

    if ($null -eq $CommittedOperationUseReceipt -or -not (Test-CddsiCanonicalUuidValue -Value $CommittedOperationUseReceipt.OperationUseId)) { throw 'Committed OperationUse receipt 无效。' }
    if (-not (Test-CddsiCommittedOperationUseReceipt -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState -OperationUseState $CommittedOperationUseReceipt -Operation $ExpectedOperation -OperationUseId $CommittedOperationUseReceipt.OperationUseId -ValidationTimeUtc $ValidationTimeUtc)) {
        throw 'Credential operation 只接受 CAS store 读回的 CLAIMED receipt。'
    }
    $occurredAt = [DateTimeOffset]::Parse($OccurredAtUtc)
    $useClaimedAt = [DateTimeOffset]::Parse($CommittedOperationUseReceipt.ClaimedAtUtc)
    $useExpiresAt = [DateTimeOffset]::Parse($CommittedOperationUseReceipt.ExpiresAtUtc)
    if ($occurredAt -lt $useClaimedAt -or $occurredAt -ge $useExpiresAt) {
        throw 'Committed OperationUse receipt 时间窗无效。'
    }

    $bindingWithoutToken = [pscustomobject][ordered]@{
        SchemaVersion               = 1
        ContractVersion             = 'cddsi-credential-authorization-binding-v1'
        Stage                       = $StageManifest.Stage
        ArtifactProfile             = $StageManifest.ArtifactProfile
        RunId                       = $ExpectedRunId
        ArtifactSha256              = $StageManifest.ArtifactSha256
        SidecarSha256               = $StageManifest.SidecarSha256
        ContentDigest               = $StageManifest.ContentDigest
        GrantId                     = $OperationGrant.GrantId
        Nonce                       = $OperationGrant.Nonce
        ClaimId                     = $AuthorizationSession.ClaimId
        AuthorizationSessionRevision = [int]$AuthorizationSession.Revision
        ConfirmationId              = $Confirmation.ConfirmationId
        Operation                   = $ExpectedOperation
        OperationUseId              = $CommittedOperationUseReceipt.OperationUseId
        OperationUseStateKeySha256  = $CommittedOperationUseReceipt.StateKeySha256
        OperationUseRevision        = [int]$CommittedOperationUseReceipt.Revision
        OperationUseClaimedAtUtc    = $CommittedOperationUseReceipt.ClaimedAtUtc
        OperationUseExpiresAtUtc    = $CommittedOperationUseReceipt.ExpiresAtUtc
        ReceiptBindingToken         = $CommittedOperationUseReceipt.ReceiptBindingToken
        ProviderIdempotencyRequired = $true
        ProviderIdempotencyKey      = $CommittedOperationUseReceipt.OperationUseId
    }
    $bindingToken = Get-CddsiSupplyChainTextBindingToken -Text ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}|{9}|{10}|{11}|{12}|{13}|{14}|{15}|{16}|{17}|{18}|{19}|{20}|{21}' -f
        $bindingWithoutToken.ContractVersion, $bindingWithoutToken.Stage, $bindingWithoutToken.ArtifactProfile,
        $bindingWithoutToken.RunId, $bindingWithoutToken.ArtifactSha256, $bindingWithoutToken.SidecarSha256,
        $bindingWithoutToken.ContentDigest, $bindingWithoutToken.GrantId, $bindingWithoutToken.Nonce,
        $bindingWithoutToken.ClaimId, $bindingWithoutToken.AuthorizationSessionRevision,
        $bindingWithoutToken.ConfirmationId, $bindingWithoutToken.Operation, $bindingWithoutToken.OperationUseId,
        $bindingWithoutToken.OperationUseStateKeySha256, $bindingWithoutToken.OperationUseRevision,
        $bindingWithoutToken.OperationUseClaimedAtUtc, $bindingWithoutToken.OperationUseExpiresAtUtc,
        $bindingWithoutToken.ReceiptBindingToken, $bindingWithoutToken.ProviderIdempotencyRequired,
        $bindingWithoutToken.ProviderIdempotencyKey, 'committed')
    $binding = [pscustomobject][ordered]@{
        SchemaVersion               = $bindingWithoutToken.SchemaVersion
        ContractVersion             = $bindingWithoutToken.ContractVersion
        Stage                       = $bindingWithoutToken.Stage
        ArtifactProfile             = $bindingWithoutToken.ArtifactProfile
        RunId                       = $bindingWithoutToken.RunId
        ArtifactSha256              = $bindingWithoutToken.ArtifactSha256
        SidecarSha256               = $bindingWithoutToken.SidecarSha256
        ContentDigest               = $bindingWithoutToken.ContentDigest
        GrantId                     = $bindingWithoutToken.GrantId
        Nonce                       = $bindingWithoutToken.Nonce
        ClaimId                     = $bindingWithoutToken.ClaimId
        AuthorizationSessionRevision = $bindingWithoutToken.AuthorizationSessionRevision
        ConfirmationId              = $bindingWithoutToken.ConfirmationId
        Operation                   = $bindingWithoutToken.Operation
        OperationUseId              = $bindingWithoutToken.OperationUseId
        OperationUseStateKeySha256  = $bindingWithoutToken.OperationUseStateKeySha256
        OperationUseRevision        = $bindingWithoutToken.OperationUseRevision
        OperationUseClaimedAtUtc    = $bindingWithoutToken.OperationUseClaimedAtUtc
        OperationUseExpiresAtUtc    = $bindingWithoutToken.OperationUseExpiresAtUtc
        ReceiptBindingToken         = $bindingWithoutToken.ReceiptBindingToken
        ProviderIdempotencyRequired = $bindingWithoutToken.ProviderIdempotencyRequired
        ProviderIdempotencyKey      = $bindingWithoutToken.ProviderIdempotencyKey
        BindingToken                = $bindingToken
    }
    if (-not (Test-CddsiCredentialAuthorizationBinding -Binding $binding)) { throw 'Credential authorization binding 自校验失败。' }
    return $binding
}

function Test-CddsiCredentialProtectionEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedAuthorizationBinding,
        [Parameter(Mandatory = $true)][string]$ExpectedHandleToken,
        [Parameter(Mandatory = $true)][string]$ExpectedCaptureNonce,
        [Parameter(Mandatory = $true)][string]$ExpectedOperationNonce,
        [Parameter(Mandatory = $true)][string]$ExpectedHelperArtifactSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedCreatedAtUtc
    )

    $required = @('SchemaVersion', 'ContractVersion', 'Authorization', 'CredentialResource', 'SourceHandleToken', 'CaptureNonce', 'OperationNonce', 'HelperArtifactSha256', 'BlobToken', 'BlobResourceToken', 'DpapiScope', 'AclPolicy', 'OwnerBound', 'PlaintextPersisted', 'ReadbackStatus', 'CreatedAtUtc', 'ProviderIdempotencyRequired', 'ProviderIdempotencyKey', 'ProviderEvidenceSha256', 'Valid')
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected $required)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion)) { return $false }
    if ($Evidence.ContractVersion -cne 'cddsi-credential-helper-v1') { return $false }
    if (-not (Test-CddsiCredentialAuthorizationBinding -Binding $ExpectedAuthorizationBinding) -or -not (Test-CddsiCredentialAuthorizationBinding -Binding $Evidence.Authorization)) { return $false }
    if ((ConvertTo-CddsiJson -InputObject $Evidence.Authorization) -cne (ConvertTo-CddsiJson -InputObject $ExpectedAuthorizationBinding)) { return $false }
    if ($Evidence.Authorization.Operation -cne 'PersistCredential') { return $false }
    if ($Evidence.CredentialResource -cne '<CREDENTIAL:DEEPSEEK>') { return $false }
    if ($ExpectedHandleToken -notmatch '^<CREDENTIAL_HANDLE:[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}>$' -or $Evidence.SourceHandleToken -cne $ExpectedHandleToken) { return $false }
    if ($ExpectedCaptureNonce -notmatch '^nonce-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$' -or $Evidence.CaptureNonce -cne $ExpectedCaptureNonce) { return $false }
    if ($ExpectedOperationNonce -notmatch '^nonce-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$' -or $Evidence.OperationNonce -cne $ExpectedOperationNonce) { return $false }
    if ($ExpectedHelperArtifactSha256 -notmatch '^[a-f0-9]{64}$' -or $Evidence.HelperArtifactSha256 -cne $ExpectedHelperArtifactSha256) { return $false }
    if ($Evidence.BlobToken -isnot [string] -or $Evidence.BlobToken -notmatch '^<DPAPI_BLOB:[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}>$') { return $false }
    if (@(Find-CddsiPotentialSecrets -Content $Evidence.BlobToken -Source '<dpapi-blob-handle>').Count -ne 0) { return $false }
    if ($Evidence.BlobResourceToken -cne '<CREDENTIAL_BLOB:DEEPSEEK>') { return $false }
    if ($Evidence.DpapiScope -cne 'CurrentUser' -or $Evidence.AclPolicy -cne 'CurrentUserOnly') { return $false }
    if ($Evidence.ReadbackStatus -cne 'VERIFIED') { return $false }
    if (-not (Test-CddsiUtcTimestampValue -Value $ExpectedCreatedAtUtc) -or $Evidence.CreatedAtUtc -cne $ExpectedCreatedAtUtc) { return $false }
    if ($Evidence.ProviderIdempotencyRequired -isnot [bool] -or -not $Evidence.ProviderIdempotencyRequired -or $Evidence.ProviderIdempotencyKey -cne $ExpectedAuthorizationBinding.OperationUseId) { return $false }
    $expectedProviderEvidence = Get-CddsiSupplyChainTextBindingToken -Text ('{0}|{1}|{2}|{3}|{4}|{5}|{6}|{7}|{8}' -f
        $ExpectedAuthorizationBinding.BindingToken, $ExpectedHandleToken, $ExpectedCaptureNonce,
        $ExpectedOperationNonce, $ExpectedHelperArtifactSha256, $Evidence.BlobToken,
        $Evidence.ReadbackStatus, $ExpectedCreatedAtUtc, $ExpectedAuthorizationBinding.OperationUseId)
    if ($Evidence.ProviderEvidenceSha256 -isnot [string] -or $Evidence.ProviderEvidenceSha256 -cne $expectedProviderEvidence) { return $false }
    foreach ($name in @('OwnerBound', 'PlaintextPersisted', 'Valid')) {
        if ($Evidence.$name -isnot [bool]) { return $false }
    }
    return ($Evidence.OwnerBound -and -not $Evidence.PlaintextPersisted -and $Evidence.Valid)
}

function ConvertFrom-CddsiCredentialHelperOutput {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardOutput,
        [AllowEmptyString()][string]$StandardError = '',
        [Parameter(Mandatory = $true)][int]$ExitCode,
        [Parameter(Mandatory = $true)][ValidateSet('Completed', 'TimedOut', 'Cancelled', 'Failed')][string]$InvocationStatus,
        [Parameter(Mandatory = $true)][long]$ElapsedMilliseconds,
        [Parameter(Mandatory = $true)][string]$ExpectedHelperArtifactSha256,
        [Parameter(Mandatory = $true)][string]$ObservedHelperArtifactSha256
    )

    if ($InvocationStatus -cne 'Completed') { throw 'Credential helper 未正常完成。' }
    if ($ElapsedMilliseconds -lt 0 -or $ElapsedMilliseconds -gt 60000) { throw 'Credential helper 超出固定 timeout 合同。' }
    if ($ExpectedHelperArtifactSha256 -notmatch '^[a-f0-9]{64}$' -or $ObservedHelperArtifactSha256 -cne $ExpectedHelperArtifactSha256) { throw 'Credential helper artifact binding 无效。' }
    if ($ExitCode -ne 0) { throw 'Credential helper 必须以 0 退出。' }
    if (-not [string]::IsNullOrEmpty($StandardError)) { throw 'Credential helper 不得写入 stderr。' }
    if ($StandardOutput -match '[\r\n]') { throw 'Credential helper stdout 必须是单行 bare token。' }
    if (-not (Test-CddsiDeepSeekApiKeyFormat -ApiKey $StandardOutput)) { throw 'Credential helper stdout 不符合 token 安全合同。' }

    $secureValue = ConvertTo-SecureString -String $StandardOutput -AsPlainText -Force
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        OutputKind    = 'SecureString'
        TokenLength   = $StandardOutput.Length
        HelperArtifactSha256 = $ExpectedHelperArtifactSha256
        ElapsedMilliseconds = $ElapsedMilliseconds
        Serializable  = $false
        SecureValue   = $secureValue
    }
}

function Read-CddsiDeepSeekApiKeySecure {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [switch]$NonInteractive
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if ($NonInteractive) {
        return New-CddsiOperationResult -Operation 'ReadDeepSeekApiKeySecure' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'INTERACTIVE_INPUT_REQUIRED' -MessageSafe '需要本地安全交互输入；未读取标准输入、参数、环境变量或文件。' -Data ([pscustomobject][ordered]@{
            ReturnType        = 'SecureStringOrCredentialHandle'
            PlainTextArgument = $false
            Loggable          = $false
            Serializable      = $false
        })
    }

    $metadata = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider 'Credential' -Operation 'CaptureSecureInput' -ResourceToken '<CREDENTIAL:DEEPSEEK>' -Arguments ([ordered]@{
        PromptId          = 'deepseek_api_key'
        PlainTextDisabled = $true
    })
    if (-not (Test-CddsiCredentialCaptureMetadata -Metadata $metadata -ExpectedRunId $Context.RunId)) {
        throw 'Credential provider 返回了无效或可序列化的输入 metadata。'
    }
    return New-CddsiOperationResult -Operation 'ReadDeepSeekApiKeySecure' -Status 'SUCCEEDED' -Mode $Context.Mode -MessageSafe '凭据已由安全输入 provider 捕获；结果只包含不可序列化 handle metadata。' -Data $metadata
}

function Protect-CddsiDeepSeekCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)][string]$HandleToken,
        [Parameter(Mandatory = $true)][string]$CaptureNonce,
        [Parameter(Mandatory = $true)][string]$OperationNonce,
        [Parameter(Mandatory = $true)][string]$HelperArtifactSha256,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$Confirmation,
        [Parameter(Mandatory = $true)]$CommittedOperationUseReceipt,
        [Parameter(Mandatory = $true)][string]$CreatedAtUtc,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($HandleToken -notmatch '^<CREDENTIAL_HANDLE:[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}>$' -or @(Find-CddsiPotentialSecrets -Content $HandleToken -Source '<credential-handle>').Count -ne 0) { throw 'HandleToken 无效。' }
    if ($CaptureNonce -notmatch '^nonce-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$' -or $OperationNonce -notmatch '^nonce-[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}$' -or $CaptureNonce -ceq $OperationNonce) { throw 'Credential nonce binding 无效。' }
    if ($HelperArtifactSha256 -notmatch '^[a-f0-9]{64}$') { throw 'HelperArtifactSha256 无效。' }
    if (-not (Test-CddsiUtcTimestampValue -Value $CreatedAtUtc)) { throw 'CreatedAtUtc 无效。' }
    $credentialBinding = Resolve-CddsiCredentialAuthorizationBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState -Confirmation $Confirmation `
        -CommittedOperationUseReceipt $CommittedOperationUseReceipt `
        -ExpectedOperation PersistCredential -ExpectedRunId $Context.RunId `
        -OccurredAtUtc $CreatedAtUtc -ValidationTimeUtc $ValidationTimeUtc
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'ProtectDeepSeekCredential' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    if ($Mode -ne 'TestSafe') {
        return New-CddsiOperationResult -Operation 'ProtectDeepSeekCredential' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'LIVE_ADAPTER_REQUIRED' -MessageSafe '当前阶段不会调用真实 DPAPI 或写入 credential blob。' -PlannedChanges @('<CREDENTIAL:DEEPSEEK>')
    }

    $evidence = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider 'Credential' -Operation 'ProtectCurrentUser' -ResourceToken '<CREDENTIAL:DEEPSEEK>' -Arguments ([ordered]@{
        ContractVersion = 'cddsi-credential-protection-provider-v1'
        AuthorizationBindingToken = $credentialBinding.BindingToken
        Stage            = $credentialBinding.Stage
        ArtifactProfile  = $credentialBinding.ArtifactProfile
        RunId            = $credentialBinding.RunId
        ArtifactSha256   = $credentialBinding.ArtifactSha256
        SidecarSha256    = $credentialBinding.SidecarSha256
        ContentDigest    = $credentialBinding.ContentDigest
        GrantId          = $credentialBinding.GrantId
        ClaimId          = $credentialBinding.ClaimId
        ConfirmationId   = $credentialBinding.ConfirmationId
        Operation        = $credentialBinding.Operation
        OperationUseId   = $credentialBinding.OperationUseId
        OperationUseStateKeySha256 = $credentialBinding.OperationUseStateKeySha256
        OperationUseRevision = $credentialBinding.OperationUseRevision
        OperationUseReceiptBindingToken = $credentialBinding.ReceiptBindingToken
        ProviderIdempotencyRequired = $true
        ProviderIdempotencyKey = $credentialBinding.OperationUseId
        HandleToken     = $HandleToken
        CaptureNonce    = $CaptureNonce
        OperationNonce  = $OperationNonce
        HelperArtifactSha256 = $HelperArtifactSha256
        CreatedAtUtc    = $CreatedAtUtc
        Persist         = $false
    })
    if (-not (Test-CddsiCredentialProtectionEvidence -Evidence $evidence `
        -ExpectedAuthorizationBinding $credentialBinding -ExpectedHandleToken $HandleToken `
        -ExpectedCaptureNonce $CaptureNonce -ExpectedOperationNonce $OperationNonce `
        -ExpectedHelperArtifactSha256 $HelperArtifactSha256 -ExpectedCreatedAtUtc $CreatedAtUtc)) {
        throw 'Credential provider protection evidence 无效。'
    }
    return New-CddsiOperationResult -Operation 'ProtectDeepSeekCredential' -Status 'SUCCEEDED' -Mode $Mode -MessageSafe 'fake DPAPI CurrentUser 保护合同已验证；未持久化明文。' -Data $evidence
}

function Get-CddsiCredentialLifecycleProviderEvidenceSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PlanId,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][long]$Sequence,
        [Parameter(Mandatory = $true)][string]$Name,
        [Parameter(Mandatory = $true)][ValidateSet('SUCCEEDED', 'FAILED')][string]$Outcome,
        [Parameter(Mandatory = $true)][ValidateSet('NONE', 'UNCHANGED', 'CHANGED', 'UNKNOWN')][string]$MutationState,
        [Parameter(Mandatory = $true)][ValidateSet('PRIMARY', 'COMPENSATION')][string]$AuthorizationSlot,
        [Parameter(Mandatory = $true)][ValidateSet('PersistCredential', 'RemoveCredential', 'RestoreCredentialState')][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][int]$OperationUseRevision,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$OperationUseTerminalState,
        [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$AuthorizationBindingToken
    )

    foreach ($digest in @($PlanId, $TransactionId, $AuthorizationBindingToken)) {
        if ($digest -notmatch '^[a-f0-9]{64}$') { throw 'Credential lifecycle evidence digest binding 无效。' }
    }
    if ($Sequence -lt 1 -or [string]::IsNullOrEmpty($Name) -or $Name -notmatch '^[a-z][a-z0-9_]{2,80}$') { throw 'Credential lifecycle evidence step binding 无效。' }
    if (-not (Test-CddsiCanonicalUuidValue -Value $OperationUseId) -or $OperationUseRevision -lt 2) { throw 'Credential lifecycle evidence OperationUse binding 无效。' }
    if (-not (Test-CddsiUtcTimestampValue -Value $OccurredAtUtc)) { throw 'Credential lifecycle evidence timestamp 无效。' }
    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-credential-provider-event-v2', $PlanId, $TransactionId, $Sequence,
        $Name, $Outcome, $MutationState, $AuthorizationSlot, $Operation,
        $OperationUseId, $OperationUseRevision, $OperationUseTerminalState,
        $OccurredAtUtc, $AuthorizationBindingToken
    ) -join "`n")
}

function Get-CddsiCredentialLifecycleProviderAggregateSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PlanId,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][ValidateSet('PRIMARY', 'COMPENSATION')][string]$AuthorizationSlot,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$OperationUseId,
        [Parameter(Mandatory = $true)][int]$OperationUseRevision,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$OperationUseTerminalState,
        [Parameter(Mandatory = $true)][object[]]$Events
    )

    if ($PlanId -notmatch '^[a-f0-9]{64}$' -or $TransactionId -notmatch '^[a-f0-9]{64}$' -or
        -not (Test-CddsiCanonicalUuidValue -Value $OperationUseId) -or $OperationUseRevision -lt 2 -or
        @($Events).Count -lt 1) { throw 'Credential lifecycle aggregate binding 无效。' }
    $eventDigests = @()
    foreach ($event in @($Events)) {
        if ($event.ProviderEvidenceSha256 -isnot [string] -or $event.ProviderEvidenceSha256 -notmatch '^[a-f0-9]{64}$') {
            throw 'Credential lifecycle aggregate event evidence 无效。'
        }
        $eventDigests += $event.ProviderEvidenceSha256
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-credential-provider-aggregate-v2', $PlanId, $TransactionId,
        $AuthorizationSlot, $Operation, $OperationUseId, $OperationUseRevision,
        $OperationUseTerminalState, ($eventDigests -join '|')
    ) -join "`n")
}

function New-CddsiCredentialLifecyclePlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Install', 'Rotate', 'Revoke', 'Cleanup')][string]$Action,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$PrimaryConfirmation,
        [Parameter(Mandatory = $true)]$PrimaryCommittedOperationUseReceipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$CreatedAtUtc,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][string]$CredentialBlobToken,
        [AllowNull()][string]$PreviousBlobToken,
        [Parameter(Mandatory = $true)][string]$HelperArtifactSha256
    )

    if (-not (Test-CddsiCanonicalUuidValue -Value $ExpectedRunId)) { throw 'ExpectedRunId 必须是 canonical UUID。' }
    if (-not (Test-CddsiUtcTimestampValue -Value $CreatedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc) -or
        [DateTimeOffset]::Parse($CreatedAtUtc) -gt [DateTimeOffset]::Parse($ValidationTimeUtc)) { throw 'Credential lifecycle plan 时间无效。' }
    if ($HelperArtifactSha256 -notmatch '^[a-f0-9]{64}$') { throw 'Helper artifact binding 无效。' }
    $blobPattern = '^<DPAPI_BLOB:[a-f0-9]{8}-(?:[a-f0-9]{4}-){3}[a-f0-9]{12}>$'
    if ($CredentialBlobToken -notmatch $blobPattern) { throw 'CredentialBlobToken 无效。' }
    if ($Action -ceq 'Rotate') {
        if ([string]::IsNullOrEmpty($PreviousBlobToken) -or $PreviousBlobToken -notmatch $blobPattern -or $PreviousBlobToken -ceq $CredentialBlobToken) { throw 'Rotate 必须绑定不同的 previous blob。' }
    }
    elseif (-not [string]::IsNullOrEmpty($PreviousBlobToken)) { throw '只有 Rotate 允许 PreviousBlobToken。' }

    $primaryOperation = if ($Action -in @('Install', 'Rotate')) { 'PersistCredential' } else { 'RemoveCredential' }
    $compensationOperation = if ($Action -ceq 'Install') { 'RemoveCredential' } else { 'RestoreCredentialState' }
    $primaryBinding = Resolve-CddsiCredentialAuthorizationBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState -Confirmation $PrimaryConfirmation `
        -CommittedOperationUseReceipt $PrimaryCommittedOperationUseReceipt `
        -ExpectedOperation $primaryOperation -ExpectedRunId $ExpectedRunId `
        -OccurredAtUtc $CreatedAtUtc -ValidationTimeUtc $ValidationTimeUtc

    $stepNames = switch ($Action) {
        'Install' { @('capture_secure_input', 'protect_new_blob', 'verify_new_blob', 'install_signed_helper', 'verify_helper', 'activate_blob') }
        'Rotate' { @('capture_secure_input', 'protect_new_blob', 'verify_new_blob', 'activate_new_blob', 'verify_active_blob', 'revoke_old_blob', 'verify_old_absent') }
        'Revoke' { @('deactivate_blob', 'delete_owned_blob', 'verify_absent') }
        'Cleanup' { @('deactivate_blob', 'delete_owned_blob', 'delete_owned_helper', 'verify_absent') }
    }
    $mutationNames = @('protect_new_blob', 'install_signed_helper', 'activate_blob', 'activate_new_blob', 'revoke_old_blob', 'deactivate_blob', 'delete_owned_blob', 'delete_owned_helper')
    $steps = @()
    for ($index = 0; $index -lt $stepNames.Count; $index++) {
        $steps += [pscustomobject][ordered]@{
            Sequence          = $index + 1
            Name              = $stepNames[$index]
            Mutation          = ($mutationNames -ccontains $stepNames[$index])
            AuthorizationSlot = 'PRIMARY'
            Operation         = $primaryOperation
            OperationUseId    = $primaryBinding.OperationUseId
        }
    }

    $compensationStepNames = switch ($Action) {
        'Install' { @('remove_installed_credential_state', 'verify_install_state_absent') }
        'Rotate' { @('restore_previous_credential_state', 'verify_previous_credential_active') }
        'Revoke' { @('restore_revoked_credential_state', 'verify_credential_restored') }
        'Cleanup' { @('restore_cleaned_credential_and_helper', 'verify_cleanup_restored') }
    }
    $compensationSteps = @()
    for ($index = 0; $index -lt $compensationStepNames.Count; $index++) {
        $compensationSteps += [pscustomobject][ordered]@{
            Sequence          = $index + 1
            Name              = $compensationStepNames[$index]
            Mutation          = ($index -eq 0)
            AuthorizationSlot = 'COMPENSATION'
            Operation         = $compensationOperation
        }
    }
    $compensationSpec = [pscustomobject][ordered]@{
        SchemaVersion             = 1
        ContractVersion           = 'cddsi-credential-compensation-spec-v2'
        Action                    = $Action
        Operation                 = $compensationOperation
        AuthorizationIssuance     = 'AFTER_PRIMARY_FAILURE'
        ConfirmationPromptBinding = 'PLAN_TRANSACTION_PRIMARY_TERMINAL'
        Steps                     = @($compensationSteps)
    }

    $previousBinding = if ([string]::IsNullOrEmpty($PreviousBlobToken)) { '<null>' } else { $PreviousBlobToken }
    $stepDigest = Get-CddsiSupplyChainTextBindingToken -Text (@($steps | ForEach-Object {
        '{0}|{1}|{2}|{3}|{4}|{5}' -f $_.Sequence, $_.Name, $_.Mutation, $_.AuthorizationSlot, $_.Operation, $_.OperationUseId
    }) -join "`n")
    $compensationStepDigest = Get-CddsiSupplyChainTextBindingToken -Text (@($compensationSteps | ForEach-Object {
        '{0}|{1}|{2}|{3}|{4}' -f $_.Sequence, $_.Name, $_.Mutation, $_.AuthorizationSlot, $_.Operation
    }) -join "`n")
    $planId = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-credential-lifecycle-plan-v2', $Action, $CreatedAtUtc,
        $StageManifest.Stage, $ExpectedRunId, $StageManifest.ArtifactSha256,
        $StageManifest.SidecarSha256, $StageManifest.ContentDigest,
        $StageManifest.ArtifactProfile, $OperationGrant.GrantId,
        $AuthorizationSession.ClaimId, $AuthorizationSession.Revision,
        $CredentialBlobToken, $previousBinding, $HelperArtifactSha256,
        $primaryBinding.BindingToken, $primaryOperation,
        $compensationOperation, $stepDigest, $compensationStepDigest,
        'owner=true', 'acl=true', 'plaintext=false', 'environment=false',
        'commandline=false', 'trim=false'
    ) -join "`n")
    $transactionId = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-credential-lifecycle-transaction-v2', $planId, $Action,
        $ExpectedRunId, $primaryBinding.OperationUseId,
        $primaryBinding.OperationUseRevision, $primaryBinding.ReceiptBindingToken,
        $CredentialBlobToken, $previousBinding, $HelperArtifactSha256
    ) -join "`n")
    return [pscustomobject][ordered]@{
        SchemaVersion        = 1
        ContractVersion      = 'cddsi-credential-lifecycle-plan-v2'
        PlanId               = $planId
        TransactionId        = $transactionId
        Action               = $Action
        CreatedAtUtc         = $CreatedAtUtc
        Stage                = $StageManifest.Stage
        RunId                = $ExpectedRunId
        ArtifactSha256       = $StageManifest.ArtifactSha256
        SidecarSha256        = $StageManifest.SidecarSha256
        ContentDigest        = $StageManifest.ContentDigest
        Profile              = $StageManifest.ArtifactProfile
        GrantId              = $OperationGrant.GrantId
        ClaimId              = $AuthorizationSession.ClaimId
        AuthorizationSessionRevision = [int]$AuthorizationSession.Revision
        CredentialBlobToken  = $CredentialBlobToken
        PreviousBlobToken    = $PreviousBlobToken
        HelperArtifactSha256 = $HelperArtifactSha256
        PrimaryAuthorization = $primaryBinding
        Steps                = @($steps)
        CompensationSpec     = $compensationSpec
        RequiresOwnerCheck   = $true
        RequiresAclCheck     = $true
        AllowsPlaintext      = $false
        AllowsEnvironment    = $false
        AllowsCommandLine    = $false
        AllowsAutomaticTrim  = $false
    }
}

function Test-CddsiCredentialLifecycleEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Event,
        [Parameter(Mandatory = $true)][long]$ExpectedSequence,
        [Parameter(Mandatory = $true)]$ExpectedStep,
        [Parameter(Mandatory = $true)][string]$ExpectedOperationUseId,
        [Parameter(Mandatory = $true)][string]$ExpectedAuthorizationBindingToken,
        [Parameter(Mandatory = $true)]$ExpectedTerminalReceipt,
        [Parameter(Mandatory = $true)][string]$PlanId,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][string]$MinimumOccurredAtUtc,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        $properties = @(
            'Sequence', 'Name', 'Outcome', 'MutationState', 'AuthorizationSlot',
            'Operation', 'OperationUseId', 'OperationUseRevision',
            'OperationUseTerminalState', 'OccurredAtUtc', 'ProviderEvidenceSha256'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Event -Expected $properties)) { return $false }
        if (($Event.Sequence -isnot [int] -and $Event.Sequence -isnot [long]) -or [long]$Event.Sequence -ne $ExpectedSequence -or
            $Event.Name -cne $ExpectedStep.Name -or $Event.AuthorizationSlot -cne $ExpectedStep.AuthorizationSlot -or
            $Event.Operation -cne $ExpectedStep.Operation -or $Event.OperationUseId -cne $ExpectedOperationUseId -or
            $Event.OperationUseRevision -ne $ExpectedTerminalReceipt.Revision -or
            $Event.OperationUseTerminalState -cne $ExpectedTerminalReceipt.State) { return $false }
        if ($Event.Outcome -cnotin @('SUCCEEDED', 'FAILED') -or
            $Event.MutationState -cnotin @('NONE', 'UNCHANGED', 'CHANGED', 'UNKNOWN')) { return $false }
        if ($ExpectedStep.Mutation -isnot [bool]) { return $false }
        if (-not $ExpectedStep.Mutation -and $Event.MutationState -cne 'NONE') { return $false }
        if ($ExpectedStep.Mutation) {
            if ($Event.Outcome -ceq 'SUCCEEDED' -and $Event.MutationState -cnotin @('CHANGED', 'UNCHANGED')) { return $false }
            if ($Event.Outcome -ceq 'FAILED' -and $Event.MutationState -cnotin @('CHANGED', 'UNCHANGED', 'UNKNOWN')) { return $false }
        }
        if (-not (Test-CddsiUtcTimestampValue -Value $Event.OccurredAtUtc) -or
            -not (Test-CddsiUtcTimestampValue -Value $MinimumOccurredAtUtc) -or
            -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)) { return $false }
        $occurredAt = [DateTimeOffset]::Parse($Event.OccurredAtUtc)
        if ($occurredAt -lt [DateTimeOffset]::Parse($MinimumOccurredAtUtc) -or
            $occurredAt -lt [DateTimeOffset]::Parse($ExpectedTerminalReceipt.ClaimedAtUtc) -or
            $occurredAt -gt [DateTimeOffset]::Parse($ExpectedTerminalReceipt.OccurredAtUtc) -or
            $occurredAt -ge [DateTimeOffset]::Parse($ExpectedTerminalReceipt.ExpiresAtUtc) -or
            $occurredAt -gt [DateTimeOffset]::Parse($ValidationTimeUtc)) { return $false }
        $expectedEvidence = Get-CddsiCredentialLifecycleProviderEvidenceSha256 `
            -PlanId $PlanId -TransactionId $TransactionId -Sequence $ExpectedSequence `
            -Name $Event.Name -Outcome $Event.Outcome -MutationState $Event.MutationState `
            -AuthorizationSlot $Event.AuthorizationSlot -Operation $Event.Operation `
            -OperationUseId $Event.OperationUseId -OperationUseRevision $Event.OperationUseRevision `
            -OperationUseTerminalState $Event.OperationUseTerminalState `
            -OccurredAtUtc $Event.OccurredAtUtc -AuthorizationBindingToken $ExpectedAuthorizationBindingToken
        return ($Event.ProviderEvidenceSha256 -ceq $expectedEvidence)
    }
    catch { return $false }
}

function Resolve-CddsiCredentialLifecycleTranscript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$Transcript,
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$PrimaryConfirmation,
        [Parameter(Mandatory = $true)]$PrimaryCommittedOperationUseReceipt,
        [Parameter(Mandatory = $true)]$PrimaryTerminalOperationUseReceipt,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][string]$ExpectedCreatedAtUtc,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][string]$ExpectedCredentialBlobToken,
        [AllowNull()][string]$ExpectedPreviousBlobToken,
        [Parameter(Mandatory = $true)][string]$ExpectedHelperArtifactSha256,
        [AllowNull()]$CompensationStageManifest = $null,
        [AllowNull()]$CompensationOperationGrant = $null,
        [AllowNull()]$CompensationAuthorizationSession = $null,
        [AllowNull()]$CompensationWorkflowSessionState = $null,
        [AllowNull()]$CompensationConfirmation = $null,
        [AllowNull()]$CompensationCommittedOperationUseReceipt = $null,
        [AllowNull()]$CompensationTerminalOperationUseReceipt = $null
    )

    $planProperties = @(
        'SchemaVersion', 'ContractVersion', 'PlanId', 'TransactionId', 'Action',
        'CreatedAtUtc', 'Stage', 'RunId', 'ArtifactSha256', 'SidecarSha256',
        'ContentDigest', 'Profile', 'GrantId', 'ClaimId',
        'AuthorizationSessionRevision', 'CredentialBlobToken', 'PreviousBlobToken',
        'HelperArtifactSha256', 'PrimaryAuthorization', 'Steps', 'CompensationSpec',
        'RequiresOwnerCheck', 'RequiresAclCheck', 'AllowsPlaintext',
        'AllowsEnvironment', 'AllowsCommandLine', 'AllowsAutomaticTrim'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Plan -Expected $planProperties) -or
        -not (Test-CddsiSchemaVersionOne -Value $Plan.SchemaVersion) -or
        $Plan.ContractVersion -cne 'cddsi-credential-lifecycle-plan-v2') { throw 'Credential lifecycle plan schema 无效。' }
    $expectedPlan = New-CddsiCredentialLifecyclePlan -Action $Plan.Action `
        -StageManifest $StageManifest -OperationGrant $OperationGrant `
        -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
        -PrimaryConfirmation $PrimaryConfirmation `
        -PrimaryCommittedOperationUseReceipt $PrimaryCommittedOperationUseReceipt `
        -ExpectedRunId $ExpectedRunId -CreatedAtUtc $ExpectedCreatedAtUtc `
        -ValidationTimeUtc $ValidationTimeUtc `
        -CredentialBlobToken $ExpectedCredentialBlobToken `
        -PreviousBlobToken $ExpectedPreviousBlobToken `
        -HelperArtifactSha256 $ExpectedHelperArtifactSha256
    if ((ConvertTo-CddsiJson -InputObject $Plan) -cne (ConvertTo-CddsiJson -InputObject $expectedPlan)) {
        throw 'Credential lifecycle plan strict binding 或 digest 无效。'
    }

    $transcriptProperties = @(
        'SchemaVersion', 'ContractVersion', 'PlanId', 'TransactionId', 'Action',
        'RunId', 'PrimaryOperationUseId', 'PrimaryTerminalReceiptBindingToken',
        'CompensationAuthorizationBindingToken', 'CompensationOperationUseId',
        'CompensationTerminalReceiptBindingToken', 'Events'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Transcript -Expected $transcriptProperties) -or
        -not (Test-CddsiSchemaVersionOne -Value $Transcript.SchemaVersion) -or
        $Transcript.ContractVersion -cne 'cddsi-credential-lifecycle-transcript-v2' -or
        $Transcript.PlanId -cne $Plan.PlanId -or $Transcript.TransactionId -cne $Plan.TransactionId -or
        $Transcript.Action -cne $Plan.Action -or $Transcript.RunId -cne $Plan.RunId -or
        $Transcript.PrimaryOperationUseId -cne $Plan.PrimaryAuthorization.OperationUseId) {
        throw 'Credential lifecycle transcript binding 无效。'
    }
    if (-not (Test-CddsiOperationUseBinding -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $PrimaryTerminalOperationUseReceipt)) {
        throw 'Primary terminal OperationUse receipt 无效。'
    }
    if ($PrimaryTerminalOperationUseReceipt.OperationUseId -cne $Plan.PrimaryAuthorization.OperationUseId -or
        $PrimaryTerminalOperationUseReceipt.Operation -cne $Plan.PrimaryAuthorization.Operation -or
        $PrimaryTerminalOperationUseReceipt.StateKeySha256 -cne $Plan.PrimaryAuthorization.OperationUseStateKeySha256 -or
        $PrimaryTerminalOperationUseReceipt.Revision -ne ($Plan.PrimaryAuthorization.OperationUseRevision + 1) -or
        $Transcript.PrimaryTerminalReceiptBindingToken -cne $PrimaryTerminalOperationUseReceipt.ReceiptBindingToken) {
        throw 'Primary terminal receipt 与 plan use 不一致。'
    }

    $events = @($Transcript.Events)
    $steps = @($Plan.Steps)
    if ($events.Count -lt 1 -or $events.Count -gt ($steps.Count + 2)) { throw 'Credential lifecycle transcript event count 无效。' }
    $compensationBundleProvided = @(
        $CompensationStageManifest, $CompensationOperationGrant, $CompensationAuthorizationSession,
        $CompensationWorkflowSessionState, $CompensationConfirmation,
        $CompensationCommittedOperationUseReceipt, $CompensationTerminalOperationUseReceipt
    ) | Where-Object { $null -ne $_ }
    $primaryEvents = @()
    $compensationEvents = @()
    $compensationStarted = $false
    foreach ($event in $events) {
        if ($event.PSObject.Properties.Name -notcontains 'AuthorizationSlot') { throw 'Credential lifecycle event schema 无效。' }
        if ($event.AuthorizationSlot -ceq 'COMPENSATION') { $compensationStarted = $true; $compensationEvents += $event }
        elseif ($event.AuthorizationSlot -ceq 'PRIMARY' -and -not $compensationStarted) { $primaryEvents += $event }
        else { throw 'Credential lifecycle authorization slot order 无效。' }
    }
    if ($primaryEvents.Count -lt 1 -or $primaryEvents.Count -gt $steps.Count) { throw 'Primary credential event count 无效。' }
    $primaryFailureIndex = -1
    $mutationSeen = $false
    $seenEvidence = @{}
    $previousOccurredAt = $Plan.CreatedAtUtc
    for ($index = 0; $index -lt $primaryEvents.Count; $index++) {
        $event = $primaryEvents[$index]
        if (-not (Test-CddsiCredentialLifecycleEvent -Event $event -ExpectedSequence ($index + 1) `
            -ExpectedStep $steps[$index] -ExpectedOperationUseId $Plan.PrimaryAuthorization.OperationUseId `
            -ExpectedAuthorizationBindingToken $Plan.PrimaryAuthorization.BindingToken `
            -ExpectedTerminalReceipt $PrimaryTerminalOperationUseReceipt -PlanId $Plan.PlanId `
            -TransactionId $Plan.TransactionId -MinimumOccurredAtUtc $previousOccurredAt `
            -ValidationTimeUtc $ValidationTimeUtc)) { throw 'Primary credential lifecycle event 无效。' }
        if ($seenEvidence.ContainsKey($event.ProviderEvidenceSha256)) { throw 'Credential lifecycle provider evidence 重放。' }
        $seenEvidence[$event.ProviderEvidenceSha256] = $true
        $previousOccurredAt = $event.OccurredAtUtc
        if ($event.MutationState -in @('CHANGED', 'UNKNOWN')) { $mutationSeen = $true }
        if ($event.Outcome -ceq 'FAILED') {
            if ($index -ne ($primaryEvents.Count - 1)) { throw 'Primary failure 后不得继续 primary event。' }
            $primaryFailureIndex = $index
        }
    }
    $primaryFailed = ($primaryFailureIndex -ge 0)
    if (-not $primaryFailed -and $primaryEvents.Count -ne $steps.Count) { throw 'Credential lifecycle primary transcript 未到终态。' }
    $expectedPrimaryTerminalState = if ($primaryFailed) { 'ABORTED' } else { 'COMPLETED' }
    if ($PrimaryTerminalOperationUseReceipt.State -cne $expectedPrimaryTerminalState -or
        $PrimaryTerminalOperationUseReceipt.OccurredAtUtc -cne $primaryEvents[-1].OccurredAtUtc -or
        ($primaryFailed -and $PrimaryTerminalOperationUseReceipt.TerminalReasonCode -cne 'PROVIDER_FAILED') -or
        (-not $primaryFailed -and $PrimaryTerminalOperationUseReceipt.TerminalReasonCode -cne '')) {
        throw 'Primary terminal outcome 与 transcript 不一致。'
    }
    $primaryAggregate = Get-CddsiCredentialLifecycleProviderAggregateSha256 `
        -PlanId $Plan.PlanId -TransactionId $Plan.TransactionId -AuthorizationSlot PRIMARY `
        -Operation $Plan.PrimaryAuthorization.Operation `
        -OperationUseId $Plan.PrimaryAuthorization.OperationUseId `
        -OperationUseRevision $PrimaryTerminalOperationUseReceipt.Revision `
        -OperationUseTerminalState $PrimaryTerminalOperationUseReceipt.State `
        -Events $primaryEvents
    if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $StageManifest `
        -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession `
        -WorkflowSessionState $WorkflowSessionState `
        -OperationUseState $PrimaryTerminalOperationUseReceipt `
        -Operation $Plan.PrimaryAuthorization.Operation `
        -OperationUseId $Plan.PrimaryAuthorization.OperationUseId `
        -Outcome $expectedPrimaryTerminalState -ExpectedProviderEvidenceDigest $primaryAggregate)) {
        throw 'Primary terminal provider evidence 无效。'
    }

    if (-not $primaryFailed) {
        if ($compensationEvents.Count -ne 0 -or $null -ne $Transcript.CompensationAuthorizationBindingToken -or
            $null -ne $Transcript.CompensationOperationUseId -or $null -ne $Transcript.CompensationTerminalReceiptBindingToken -or
            @($compensationBundleProvided).Count -ne 0) {
            throw '成功路径不得生成补偿授权或补偿事件。'
        }
        return New-CddsiOperationResult -Operation 'ResolveCredentialLifecycle' -Status 'SUCCEEDED' -Mode 'TestSafe' `
            -MessageSafe 'synthetic credential lifecycle primary operation 已完整提交。' `
            -Data ([pscustomobject][ordered]@{ PlanId = $Plan.PlanId; TransactionId = $Plan.TransactionId; CompensationStatus = 'NOT_REQUIRED'; MutationOutcomeKnown = $true })
    }
    if (-not $mutationSeen) {
        if ($compensationEvents.Count -ne 0 -or @($compensationBundleProvided).Count -ne 0) { throw '未发生 mutation 的 credential failure 不得附带补偿。' }
        return New-CddsiOperationResult -Operation 'ResolveCredentialLifecycle' -Status 'FAILED' -Mode 'TestSafe' `
            -ErrorCode 'CREDENTIAL_LIFECYCLE_FAILED' -MessageSafe 'synthetic credential lifecycle 在 mutation 前失败。' `
            -Data ([pscustomobject][ordered]@{ PlanId = $Plan.PlanId; TransactionId = $Plan.TransactionId; CompensationStatus = 'NOT_REQUIRED'; MutationOutcomeKnown = $true })
    }

    if ($compensationEvents.Count -eq 0) {
        if ($null -ne $Transcript.CompensationAuthorizationBindingToken -or $null -ne $Transcript.CompensationOperationUseId -or
            $null -ne $Transcript.CompensationTerminalReceiptBindingToken -or @($compensationBundleProvided).Count -ne 0) {
            throw '缺少 compensation events 时不得附带或伪造 compensation bundle。'
        }
        return New-CddsiOperationResult -Operation 'ResolveCredentialLifecycle' -Status 'FAILED' -Mode 'TestSafe' `
            -ErrorCode 'CREDENTIAL_COMPENSATION_NOT_PROVEN' -MessageSafe 'credential mutation 后尚未签发并证明独立补偿授权。' `
            -Data ([pscustomobject][ordered]@{ PlanId = $Plan.PlanId; TransactionId = $Plan.TransactionId; CompensationStatus = 'REQUIRED_NOT_PROVEN'; MutationOutcomeKnown = $false })
    }
    if ($compensationEvents.Count -ne @($Plan.CompensationSpec.Steps).Count) { throw 'Credential compensation event count 无效。' }
    foreach ($value in @(
        $CompensationStageManifest, $CompensationOperationGrant, $CompensationAuthorizationSession,
        $CompensationWorkflowSessionState, $CompensationConfirmation,
        $CompensationCommittedOperationUseReceipt, $CompensationTerminalOperationUseReceipt
    )) { if ($null -eq $value) { throw 'Credential compensation bundle 不完整。' } }

    $failureOccurredAt = $PrimaryTerminalOperationUseReceipt.OccurredAtUtc
    $compensationOperation = $Plan.CompensationSpec.Operation
    $expectedPromptDigest = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-credential-compensation-confirmation-v2', $Plan.PlanId,
        $Plan.TransactionId, $PrimaryTerminalOperationUseReceipt.ReceiptBindingToken,
        $primaryAggregate, $failureOccurredAt, $Plan.Action, $compensationOperation
    ) -join "`n")
    $compensationPromptBinding = @($CompensationOperationGrant.ConfirmationBindings | Where-Object { $_.Operation -ceq $compensationOperation })
    if ($compensationPromptBinding.Count -ne 1 -or $compensationPromptBinding[0].PromptDigest -cne $expectedPromptDigest -or
        $CompensationConfirmation.PromptDigest -cne $expectedPromptDigest) { throw 'Credential compensation confirmation 未绑定原 transaction/failure receipt。' }
    if ([DateTimeOffset]::Parse($CompensationOperationGrant.IssuedAtUtc) -lt [DateTimeOffset]::Parse($failureOccurredAt) -or
        [DateTimeOffset]::Parse($CompensationAuthorizationSession.ClaimedAtUtc) -lt [DateTimeOffset]::Parse($failureOccurredAt) -or
        [DateTimeOffset]::Parse($CompensationConfirmation.ConfirmedAtUtc) -lt [DateTimeOffset]::Parse($failureOccurredAt) -or
        [DateTimeOffset]::Parse($CompensationCommittedOperationUseReceipt.ClaimedAtUtc) -lt [DateTimeOffset]::Parse($failureOccurredAt)) {
        throw 'Credential compensation authorization 不得早于 primary failure。'
    }
    if ($CompensationStageManifest.Stage -cne $Plan.Stage -or $CompensationStageManifest.ArtifactProfile -cne $Plan.Profile -or
        $CompensationStageManifest.ArtifactSha256 -cne $Plan.ArtifactSha256 -or
        $CompensationStageManifest.SidecarSha256 -cne $Plan.SidecarSha256 -or
        $CompensationStageManifest.ContentDigest -cne $Plan.ContentDigest -or
        $CompensationOperationGrant.RunId -cne $Plan.RunId) { throw 'Credential compensation bundle 跨 artifact/run。' }
    $compensationBinding = Resolve-CddsiCredentialAuthorizationBinding `
        -StageManifest $CompensationStageManifest -OperationGrant $CompensationOperationGrant `
        -AuthorizationSession $CompensationAuthorizationSession `
        -WorkflowSessionState $CompensationWorkflowSessionState `
        -Confirmation $CompensationConfirmation `
        -CommittedOperationUseReceipt $CompensationCommittedOperationUseReceipt `
        -ExpectedOperation $compensationOperation -ExpectedRunId $Plan.RunId `
        -OccurredAtUtc $compensationEvents[0].OccurredAtUtc -ValidationTimeUtc $ValidationTimeUtc
    foreach ($primaryId in @(
        $Plan.PrimaryAuthorization.GrantId, $Plan.PrimaryAuthorization.Nonce,
        $Plan.PrimaryAuthorization.ClaimId, $Plan.PrimaryAuthorization.ConfirmationId,
        $Plan.PrimaryAuthorization.OperationUseId, $Plan.PrimaryAuthorization.OperationUseStateKeySha256
    )) {
        if (@(
            $compensationBinding.GrantId, $compensationBinding.Nonce,
            $compensationBinding.ClaimId, $compensationBinding.ConfirmationId,
            $compensationBinding.OperationUseId, $compensationBinding.OperationUseStateKeySha256
        ) -ccontains $primaryId) { throw 'Credential compensation authorization 必须使用独立 grant/claim/confirmation/use。' }
    }
    $compensationBindingToken = Get-CddsiSupplyChainTextBindingToken -Text (@(
        'cddsi-credential-compensation-authorization-v2', $Plan.PlanId,
        $Plan.TransactionId, $Plan.Action, $compensationOperation,
        $PrimaryTerminalOperationUseReceipt.ReceiptBindingToken, $primaryAggregate,
        $failureOccurredAt, $expectedPromptDigest, $compensationBinding.BindingToken
    ) -join "`n")
    if ($Transcript.CompensationAuthorizationBindingToken -cne $compensationBindingToken -or
        $Transcript.CompensationOperationUseId -cne $compensationBinding.OperationUseId -or
        $Transcript.CompensationTerminalReceiptBindingToken -cne $CompensationTerminalOperationUseReceipt.ReceiptBindingToken) {
        throw 'Credential compensation transcript binding 无效。'
    }
    if (-not (Test-CddsiOperationUseBinding -StageManifest $CompensationStageManifest `
        -OperationGrant $CompensationOperationGrant -AuthorizationSession $CompensationAuthorizationSession `
        -WorkflowSessionState $CompensationWorkflowSessionState `
        -OperationUseState $CompensationTerminalOperationUseReceipt) -or
        $CompensationTerminalOperationUseReceipt.OperationUseId -cne $compensationBinding.OperationUseId -or
        $CompensationTerminalOperationUseReceipt.StateKeySha256 -cne $compensationBinding.OperationUseStateKeySha256 -or
        $CompensationTerminalOperationUseReceipt.Revision -ne ($compensationBinding.OperationUseRevision + 1)) {
        throw 'Credential compensation terminal receipt 无效。'
    }
    $compensationSteps = @($Plan.CompensationSpec.Steps)
    $compensationFailed = $false
    $previousOccurredAt = $failureOccurredAt
    for ($index = 0; $index -lt $compensationEvents.Count; $index++) {
        $event = $compensationEvents[$index]
        if (-not (Test-CddsiCredentialLifecycleEvent -Event $event `
            -ExpectedSequence ($primaryEvents.Count + $index + 1) `
            -ExpectedStep $compensationSteps[$index] `
            -ExpectedOperationUseId $compensationBinding.OperationUseId `
            -ExpectedAuthorizationBindingToken $compensationBindingToken `
            -ExpectedTerminalReceipt $CompensationTerminalOperationUseReceipt `
            -PlanId $Plan.PlanId -TransactionId $Plan.TransactionId `
            -MinimumOccurredAtUtc $previousOccurredAt -ValidationTimeUtc $ValidationTimeUtc)) {
            throw 'Credential compensation event 无效。'
        }
        if ($seenEvidence.ContainsKey($event.ProviderEvidenceSha256)) { throw 'Credential compensation provider evidence 重放。' }
        $seenEvidence[$event.ProviderEvidenceSha256] = $true
        $previousOccurredAt = $event.OccurredAtUtc
        if ($event.Outcome -ceq 'FAILED') { $compensationFailed = $true }
    }
    $expectedCompensationTerminalState = if ($compensationFailed) { 'ABORTED' } else { 'COMPLETED' }
    if ($CompensationTerminalOperationUseReceipt.State -cne $expectedCompensationTerminalState -or
        $CompensationTerminalOperationUseReceipt.OccurredAtUtc -cne $compensationEvents[-1].OccurredAtUtc -or
        ($compensationFailed -and $CompensationTerminalOperationUseReceipt.TerminalReasonCode -cne 'COMPENSATION_FAILED') -or
        (-not $compensationFailed -and $CompensationTerminalOperationUseReceipt.TerminalReasonCode -cne '')) {
        throw 'Credential compensation terminal outcome 无效。'
    }
    $compensationAggregate = Get-CddsiCredentialLifecycleProviderAggregateSha256 `
        -PlanId $Plan.PlanId -TransactionId $Plan.TransactionId -AuthorizationSlot COMPENSATION `
        -Operation $compensationOperation -OperationUseId $compensationBinding.OperationUseId `
        -OperationUseRevision $CompensationTerminalOperationUseReceipt.Revision `
        -OperationUseTerminalState $CompensationTerminalOperationUseReceipt.State `
        -Events $compensationEvents
    if (-not (Test-CddsiTerminalOperationUseReceipt -StageManifest $CompensationStageManifest `
        -OperationGrant $CompensationOperationGrant -AuthorizationSession $CompensationAuthorizationSession `
        -WorkflowSessionState $CompensationWorkflowSessionState `
        -OperationUseState $CompensationTerminalOperationUseReceipt `
        -Operation $compensationOperation -OperationUseId $compensationBinding.OperationUseId `
        -Outcome $expectedCompensationTerminalState -ExpectedProviderEvidenceDigest $compensationAggregate)) {
        throw 'Credential compensation terminal provider evidence 无效。'
    }
    $restored = -not $compensationFailed
    return New-CddsiOperationResult -Operation 'ResolveCredentialLifecycle' -Status 'FAILED' -Mode 'TestSafe' `
        -ErrorCode $(if ($restored) { 'CREDENTIAL_LIFECYCLE_FAILED_RESTORED' } else { 'CREDENTIAL_RESTORE_FAILED' }) `
        -MessageSafe $(if ($restored) { 'credential lifecycle 失败，action-specific state 已恢复并重读。' } else { 'credential lifecycle 失败且补偿执行失败。' }) `
        -Data ([pscustomobject][ordered]@{ PlanId = $Plan.PlanId; TransactionId = $Plan.TransactionId; CompensationStatus = $(if ($restored) { 'FULL' } else { 'UNRECOVERABLE' }); MutationOutcomeKnown = $restored })
}

function ConvertTo-CddsiDeepSeekApiErrorClass {
    [CmdletBinding()]
    param(
        [AllowNull()][Nullable[int]]$HttpStatusCode,
        [ValidateSet('', 'Timeout', 'Dns', 'Tls', 'Proxy', 'Cancelled', 'Transport')]
        [string]$ExceptionKind = ''
    )

    if (-not [string]::IsNullOrWhiteSpace($ExceptionKind)) {
        $canonicalKind = switch ($ExceptionKind.ToLowerInvariant()) {
            'timeout' { 'Timeout' }
            'dns' { 'Dns' }
            'tls' { 'Tls' }
            'proxy' { 'Proxy' }
            'cancelled' { 'Cancelled' }
            'transport' { 'Transport' }
        }
        $retryable = $canonicalKind -in @('Timeout', 'Dns', 'Transport')
        return [pscustomobject][ordered]@{
            Class = $canonicalKind
            StatusCode = $null
            Retryable = $retryable
            UserMessage = '网络请求未执行或未完成。'
        }
    }

    $code = if ($null -eq $HttpStatusCode) { 0 } else { [int]$HttpStatusCode }
    $class = 'Unknown'
    $retry = $false
    switch ($code) {
        400 { $class = 'InvalidInput' }
        401 { $class = 'Unauthorized' }
        402 { $class = 'Billing' }
        403 { $class = 'Forbidden' }
        404 { $class = 'NotFound' }
        422 { $class = 'Validation' }
        429 { $class = 'RateLimited'; $retry = $true }
        408 { $class = 'Timeout'; $retry = $true }
        default {
            if ($code -ge 500 -and $code -le 599) { $class = 'ServerError'; $retry = $true }
        }
    }
    return [pscustomobject][ordered]@{
        Class = $class
        StatusCode = if ($code -eq 0) { $null } else { $code }
        Retryable = $retry
        UserMessage = 'DeepSeek API 错误已归类；技术正文不得包含凭据。'
    }
}

function Invoke-CddsiDeepSeekApiValidation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [AllowNull()][Security.SecureString]$ApiKey,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'ValidateDeepSeekApi' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'ValidateDeepSeekApi' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SCAFFOLD_ONLY' -MessageSafe '不会发送 DeepSeek API 请求。' -Data ([pscustomobject]@{ CredentialProvided = ($null -ne $ApiKey); RequestSent = $false })
}
