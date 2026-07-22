Set-StrictMode -Version Latest

$script:CddsiRealtimeRelayClientPath = if ([string]::IsNullOrEmpty($PSCommandPath)) {
    $null
}
else {
    [IO.Path]::GetFullPath($PSCommandPath)
}
$script:CddsiRealtimeGitOutboxRunnerPath = if ([string]::IsNullOrEmpty($script:CddsiRealtimeRelayClientPath)) {
    $null
}
else {
    [IO.Path]::GetFullPath([IO.Path]::Combine(
            [IO.Path]::GetDirectoryName([IO.Path]::GetDirectoryName($script:CddsiRealtimeRelayClientPath)),
            'fast-lane',
            'invoke-git-outbox.ps1'
        ))
}
$script:CddsiRealtimeNotificationSchema = 'cddsi-relay-notification-v1'
$script:CddsiRealtimeAckSchema = 'cddsi-relay-ack-v1'
$script:CddsiRealtimeStateSchema = 'cddsi-realtime-relay-watcher-state-v1'
$script:CddsiRealtimeContextSchema = 'cddsi-realtime-relay-context-v1'
$script:CddsiRealtimeAssertionSchema = 'cddsi-realtime-relay-runtime-assertion-v1'
$script:CddsiRealtimePublisherContextSchema = 'cddsi-realtime-relay-publisher-context-v1'
$script:CddsiRealtimePublisherAssertionSchema = 'cddsi-realtime-relay-publisher-runtime-assertion-v1'
$script:CddsiRealtimeCleanupAssertionSchema = 'cddsi-realtime-relay-cleanup-runtime-assertion-v1'
$script:CddsiRealtimeCredentialBlobSchema = 'cddsi-realtime-relay-dpapi-credential-v1'
$script:CddsiRealtimeCredentialProviderSchema = 'cddsi-realtime-relay-credential-provider-v2'
$script:CddsiRealtimeStateProviderSchema = 'cddsi-realtime-relay-owned-state-provider-v2'
$script:CddsiRealtimeLiveTransportProviderSchema = 'cddsi-realtime-relay-live-transport-provider-v1'
$script:CddsiRealtimeLiveClockProviderSchema = 'cddsi-realtime-relay-live-clock-provider-v1'
$script:CddsiRealtimeFixedWakeProviderSchema = 'cddsi-realtime-relay-fixed-git-outbox-wake-provider-v2'
$script:CddsiRealtimeWakeProofSchema = 'cddsi-realtime-relay-wake-proof-v1'
$script:CddsiRealtimePublisherStateSchema = 'cddsi-realtime-relay-publisher-state-v1'
$script:CddsiRealtimePublishPointerSchema = 'cddsi-realtime-relay-publish-pointer-v1'
$script:CddsiRealtimePublishResultSchema = 'cddsi-realtime-relay-publish-result-v1'
$script:CddsiRealtimeCleanupResultSchema = 'cddsi-realtime-relay-cleanup-result-v1'
$script:CddsiRealtimeCredentialProvisionResultSchema = 'cddsi-realtime-relay-credential-provision-result-v1'
$script:CddsiRealtimeCredentialFileName = '.relay-credential.dpapi.json'
$script:CddsiRealtimeCredentialNextFileName = '.relay-credential.dpapi.next.json'
$script:CddsiRealtimeCredentialBackupFileName = '.relay-credential.dpapi.backup.json'
$script:CddsiRealtimeStateBackupFileName = 'watcher-state.backup.json'
$script:CddsiRealtimeAuthAudience = 'cddsi-realtime-relay-v1'
$script:CddsiRealtimeFixedResumePrompt = 'Resume the fixed operator task and process only its verified protected control-repository inbox.'
$script:CddsiRealtimeMaxBodyBytes = 4096
$script:CddsiRealtimeMaxCredentialBlobBytes = 2048
$script:CddsiRealtimeMaxClockSkewSeconds = 90
$script:CddsiRealtimeMaxTtlSeconds = 600
$script:CddsiRealtimeMaxAssertionLifetimeSeconds = 600
$script:CddsiRealtimePublisherTtlSeconds = 300
$script:CddsiRealtimeMaxSafeInteger = [long]9007199254740991
$script:CddsiRealtimeLiveSessions = @{}
$script:CddsiRealtimeNotificationProperties = @(
    'Schema', 'Lane', 'MessageId', 'Sequence', 'PreviousSha256', 'PayloadSha256',
    'RepositoryId', 'Ref', 'Commit', 'CreatedAt', 'Expiry', 'SenderRole'
)
$script:CddsiRealtimeStateProperties = @(
    'SchemaVersion', 'Lane', 'LastConsumedSequence', 'LastAckedSequence',
    'LastMessageSha256', 'ProcessedMessages', 'Revision'
)
$script:CddsiRealtimeCredentialBlobProperties = @(
    'ClientId', 'Environment', 'KeyId', 'ProtectedSecretBase64', 'ProtectionScope',
    'SchemaVersion', 'StateRootBindingToken'
)
$script:CddsiRealtimeCredentialProvisionResultProperties = @(
    'SchemaVersion', 'Mode', 'Status', 'Code', 'Changed', 'CredentialBlobSha256',
    'ClientId', 'Environment', 'KeyId'
)
$script:CddsiRealtimeCredentialProviderProperties = @(
    'SchemaVersion', 'StorageKind', 'ClientId', 'Environment', 'KeyId', 'CredentialFileName',
    'StateRoot', 'RunId', 'OwnerSid', 'OwnershipTokenSha256', 'StateRootBindingToken',
    'CredentialBlobSha256', 'BindingToken', 'ClientAdapterSha256'
)
$script:CddsiRealtimeStateProviderProperties = @(
    'SchemaVersion', 'ProviderKind', 'StateRoot', 'RunId', 'OwnerSid',
    'OwnershipTokenSha256', 'BindingToken', 'ClientAdapterSha256'
)
$script:CddsiRealtimeLiveTransportProviderProperties = @(
    'SchemaVersion', 'ProviderKind', 'Endpoint', 'ClientId', 'SessionId',
    'ClientAdapterSha256', 'BindingToken'
)
$script:CddsiRealtimeLiveClockProviderProperties = @(
    'SchemaVersion', 'ProviderKind', 'ClientAdapterSha256'
)
$script:CddsiRealtimeLiveContextProperties = @(
    'SchemaVersion', 'Mode', 'ProviderKind', 'Endpoint', 'ClientId',
    'ClientAdapterSha256', 'Providers'
)
$script:CddsiRealtimeLiveProviderSetProperties = @(
    'State', 'Transport', 'Wake', 'Clock', 'Credential'
)
$script:CddsiRealtimeLiveAssertionProperties = @(
    'SchemaVersion', 'Status', 'Lane', 'ClientId', 'Endpoint', 'Environment', 'KeyId',
    'CredentialStorageKind', 'CredentialBindingToken', 'StateRootBindingToken',
    'WakeAdapterId', 'WakeAdapterSha256', 'WakeBindingSha256', 'GitOutboxRunnerSha256',
    'CodexResumeBindingSha256',
    'ClientAdapterSha256', 'IssuedAtUtc', 'ExpiresAtUtc'
)
$script:CddsiRealtimeFixedWakeProviderProperties = @(
    'SchemaVersion', 'AdapterId', 'Lane', 'ClientId', 'AdapterSha256',
    'BindingSha256', 'GitOutboxRunnerSha256', 'GitOutboxStateRootSha256',
    'CodexExecutable', 'CodexExecutableSha256', 'CodexSessionId', 'CodexWorkingRoot',
    'CodexWorkingRootSha256', 'CodexHome', 'CodexHomeSha256', 'CodexUserProfile',
    'CodexUserProfileSha256', 'CodexLocalAppData', 'CodexLocalAppDataSha256',
    'CodexTempRoot', 'CodexTempRootSha256', 'CodexTempOwnerMarkerSha256',
    'CodexMaximumRuntimeSeconds', 'CodexPromptSha256',
    'CodexArgumentContractSha256', 'CodexResumeBindingSha256', 'Binding'
)
$script:CddsiRealtimePublisherLiveContextProperties = @(
    'SchemaVersion', 'Mode', 'ProviderKind', 'Endpoint', 'ClientId',
    'ClientAdapterSha256', 'Providers'
)
$script:CddsiRealtimePublisherProviderSetProperties = @('State', 'Transport', 'Clock', 'Credential')
$script:CddsiRealtimePublisherAssertionProperties = @(
    'SchemaVersion', 'Status', 'Lane', 'ClientId', 'Endpoint', 'Environment', 'KeyId',
    'CredentialStorageKind', 'CredentialBindingToken', 'StateRootBindingToken',
    'ClientAdapterSha256', 'IssuedAtUtc', 'ExpiresAtUtc'
)
$script:CddsiRealtimeCleanupAssertionProperties = @(
    'SchemaVersion', 'Status', 'Action', 'Mode', 'ClientId',
    'StateRootBindingToken', 'ClientAdapterSha256', 'IssuedAtUtc', 'ExpiresAtUtc'
)
$script:CddsiRealtimeWakeProofProperties = @('SchemaVersion', 'Lane', 'Entries', 'Revision')
$script:CddsiRealtimePublishPointerProperties = @(
    'SchemaVersion', 'Lane', 'MessageId', 'PayloadSha256', 'Commit'
)
$script:CddsiRealtimePublisherStateProperties = @(
    'SchemaVersion', 'Lane', 'LastPublishedSequence', 'LastMessageSha256',
    'PendingPublish', 'PublishedMessages', 'Revision'
)
$script:CddsiRealtimeGitOutboxBindingProperties = @(
    'StateRoot', 'ProductRoot', 'OperatorWorkspaceRoot', 'GitExecutable',
    'GitExecutableSha256', 'RunnerSha256', 'RepositoryUri', 'RepositoryIdentity',
    'ProtectionEvidence', 'ProtectionEvidenceSha256', 'ExpectedRepositoryNumericId',
    'ExpectedRepositoryNodeId', 'ExpectedRepositoryVisibility',
    'ExpectedProtectionAuthority', 'ExpectedProtectionPolicySha256', 'ProtectionTrustRoot',
    'ProtectionAuthorityAssertionPath', 'ExpectedProtectionAuthorityAssertionSha256',
    'ExpectedProtectionAuthorityBindingToken', 'CredentialProfileId', 'SshExecutable',
    'SshExecutableSha256', 'ExpectedSshExecutableSha256', 'DeployKeyPath', 'DeployKeySha256',
    'ExpectedDeployKeySha256', 'KnownHostsPath', 'KnownHostsSha256',
    'ExpectedKnownHostsSha256', 'ExpectedGenesisCommit', 'RemoteRef',
    'HostToVmRepositoryIdentity', 'VmToHostRepositoryIdentity', 'ProductRepositoryIdentity',
    'AuthenticatedOutbox', 'AuthenticatedSenderRoles', 'MaximumRuntimeSeconds',
    'MaximumGitCommandSeconds', 'MaximumOutputBytes', 'MaximumMessageBodyBytes',
    'MaximumAgeSeconds', 'MaximumClockSkewSeconds', 'ProtectionEvidenceMaximumAgeSeconds'
)
$script:CddsiRealtimeWatcherResultCodes = @(
    'REALTIME_CONTEXT_INVALID', 'REALTIME_PROVIDER_MISSING', 'REALTIME_NONLIVE_PROVIDER_NOT_FAKE',
    'REALTIME_LIVE_PROVIDER_INVALID', 'REALTIME_RUNTIME_ASSERTION_INVALID',
    'REALTIME_RUNTIME_BINDING_MISMATCH', 'REALTIME_RUNTIME_ASSERTION_EXPIRED',
    'REALTIME_SYNTHETIC_ASSERTION_INVALID', 'REALTIME_CREDENTIAL_NOT_READY',
    'REALTIME_CREDENTIAL_RESULT_INVALID', 'REALTIME_STATE_ROOT_RESULT_INVALID',
    'REALTIME_STATE_ROOT_INVALID', 'REALTIME_SINGLE_INSTANCE_LOCK_FAILED', 'REALTIME_STATE_INVALID',
    'REALTIME_TRANSPORT_RESULT_INVALID', 'REALTIME_TRANSPORT_MESSAGE_INVALID',
    'REALTIME_RECONNECT_EXHAUSTED', 'REALTIME_JITTER_INVALID', 'REALTIME_NOTIFICATION_INVALID',
    'REALTIME_WRONG_LANE', 'REALTIME_READER_IDENTITY_MISMATCH', 'REALTIME_MESSAGE_ID_REPLAY',
    'REALTIME_DUPLICATE_DRIFT', 'REALTIME_STATE_DUPLICATE_SEQUENCE', 'REALTIME_SEQUENCE_GAP',
    'REALTIME_PREVIOUS_HASH_MISMATCH', 'REALTIME_FIXED_WAKE_RESULT_INVALID',
    'REALTIME_FIXED_WAKE_REJECTED', 'REALTIME_WAKE_PROOF_MISSING',
    'REALTIME_WAKE_PROOF_INVALID', 'REALTIME_ACK_RESULT_INVALID', 'REALTIME_ACK_RETRY_EXHAUSTED',
    'REALTIME_ACK_PENDING_NOT_REPLAYED', 'REALTIME_DELIVERY_LIMIT_EXCEEDED',
    'REALTIME_STATE_ATOMIC_WRITE_FAILED', 'REALTIME_STATE_REVISION_EXHAUSTED',
    'REALTIME_WATCH_BLOCKED'
)
$script:CddsiRealtimePublisherResultCodes = @(
    'REALTIME_PUBLISH_CONTEXT_INVALID', 'REALTIME_PUBLISH_PROVIDER_MISSING',
    'REALTIME_PUBLISH_NONLIVE_PROVIDER_NOT_FAKE', 'REALTIME_PUBLISH_LIVE_PROVIDER_INVALID',
    'REALTIME_PUBLISH_ASSERTION_INVALID', 'REALTIME_PUBLISH_BINDING_MISMATCH',
    'REALTIME_PUBLISH_ASSERTION_EXPIRED', 'REALTIME_PUBLISH_WRITER_IDENTITY_MISMATCH',
    'REALTIME_PUBLISH_NOTIFICATION_INVALID', 'REALTIME_PUBLISH_CONFIRMATION_REQUIRED',
    'REALTIME_PUBLISH_STATE_ROOT_INVALID', 'REALTIME_PUBLISH_LOCK_FAILED',
    'REALTIME_PUBLISH_STATE_INVALID', 'REALTIME_PUBLISH_PENDING_CONFLICT',
    'REALTIME_PUBLISH_STATE_ATOMIC_WRITE_FAILED',
    'REALTIME_PUBLISH_RESULT_INVALID', 'REALTIME_PUBLISH_REJECTED',
    'REALTIME_PUBLISH_BLOCKED'
)

function Get-CddsiRealtimeRelaySha256Internal {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$Bytes
    )

    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
    }
}

function Get-CddsiRealtimeRelayTextSha256Internal {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    return Get-CddsiRealtimeRelaySha256Internal -Bytes ([Text.UTF8Encoding]::new($false, $true).GetBytes($Text))
}

function Test-CddsiRealtimeRelayExactPropertySetInternal {
    param(
        [Parameter(Mandatory = $true)]$InputObject,
        [Parameter(Mandatory = $true)][string[]]$Expected
    )

    if ($null -eq $InputObject -or $null -eq $InputObject.PSObject) {
        return $false
    }
    $actual = @($InputObject.PSObject.Properties.Name | Sort-Object -CaseSensitive)
    $required = @($Expected | Sort-Object -CaseSensitive)
    if ($actual.Count -ne $required.Count) {
        return $false
    }
    for ($index = 0; $index -lt $required.Count; $index++) {
        if ($actual[$index] -cne $required[$index]) {
            return $false
        }
    }
    return $true
}

function ConvertTo-CddsiRealtimeRelayCanonicalNotificationInternal {
    param(
        [Parameter(Mandatory = $true)]$Message
    )

    $canonical = [ordered]@{
        Commit = $Message.Commit
        CreatedAt = $Message.CreatedAt
        Expiry = $Message.Expiry
        Lane = $Message.Lane
        MessageId = $Message.MessageId
        PayloadSha256 = $Message.PayloadSha256
        PreviousSha256 = $Message.PreviousSha256
        Ref = $Message.Ref
        RepositoryId = $Message.RepositoryId
        Schema = $Message.Schema
        SenderRole = $Message.SenderRole
        Sequence = $Message.Sequence
    }
    return ConvertTo-Json -InputObject $canonical -Compress -Depth 3
}

function ConvertTo-CddsiRealtimeRelayCanonicalAckInternal {
    param(
        [Parameter(Mandatory = $true)]$Ack
    )

    $canonical = [ordered]@{
        AckStatus = $Ack.AckStatus
        AckedAt = $Ack.AckedAt
        Lane = $Ack.Lane
        MessageId = $Ack.MessageId
        PayloadSha256 = $Ack.PayloadSha256
        Schema = $Ack.Schema
        SenderRole = $Ack.SenderRole
        Sequence = $Ack.Sequence
    }
    return ConvertTo-Json -InputObject $canonical -Compress -Depth 3
}

function Test-CddsiRealtimeRelayUtcSecondInternal {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value,
        [Parameter(Mandatory = $true)][ref]$Parsed
    )

    $candidate = [DateTimeOffset]::MinValue
    $valid = [DateTimeOffset]::TryParseExact(
        $Value,
        'yyyy-MM-ddTHH:mm:ssZ',
        [Globalization.CultureInfo]::InvariantCulture,
        [Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal,
        [ref]$candidate
    )
    if (-not $valid -or $candidate.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture) -cne $Value) {
        return $false
    }
    $Parsed.Value = $candidate
    return $true
}

function Get-CddsiRealtimeRelayLanePolicyInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if ($Lane -ceq 'host-to-vm') {
        return [pscustomobject][ordered]@{
            Lane = $Lane
            WriterClientId = 'host-coordinator-v1'
            ReaderClientId = 'vm-tester-v1'
            SenderRole = 'HostCoordinator'
            ReaderRole = 'VmTester'
            RepositoryId = '1301870499'
        }
    }
    return [pscustomobject][ordered]@{
        Lane = $Lane
        WriterClientId = 'vm-tester-v1'
        ReaderClientId = 'host-coordinator-v1'
        SenderRole = 'VmTester'
        ReaderRole = 'HostCoordinator'
        RepositoryId = '1301870545'
    }
}

function Test-CddsiRealtimeRelayNotificationInternal {
    param(
        [Parameter(Mandatory = $true)][string]$RawMessage,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc,
        [ValidateSet('Strict', 'StoredConsumedReplay')][string]$ValidationMode = 'Strict'
    )

    try {
        $utf8 = [Text.UTF8Encoding]::new($false, $true)
        if ($utf8.GetByteCount($RawMessage) -gt $script:CddsiRealtimeMaxBodyBytes) {
            throw 'BODY_TOO_LARGE'
        }
        $keyMatches = @([regex]::Matches($RawMessage, '"([A-Za-z][A-Za-z0-9]*)":'))
        if ($keyMatches.Count -ne $script:CddsiRealtimeNotificationProperties.Count) {
            throw 'SCHEMA_KEYS_INVALID'
        }
        $seen = @{}
        foreach ($match in $keyMatches) {
            $name = $match.Groups[1].Value
            if ($seen.ContainsKey($name)) {
                throw 'DUPLICATE_JSON_KEY'
            }
            $seen[$name] = $true
        }
        try {
            if ((Get-Command ConvertFrom-Json).Parameters.ContainsKey('DateKind')) {
                $message = ConvertFrom-Json -InputObject $RawMessage -DateKind String -ErrorAction Stop
            }
            else {
                $message = ConvertFrom-Json -InputObject $RawMessage -ErrorAction Stop
            }
        }
        catch {
            throw 'MALFORMED_JSON'
        }
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $message -Expected $script:CddsiRealtimeNotificationProperties)) {
            throw 'SCHEMA_KEYS_INVALID'
        }
        if ((ConvertTo-CddsiRealtimeRelayCanonicalNotificationInternal -Message $message) -cne $RawMessage) {
            throw 'NON_CANONICAL_JSON'
        }
        if ($message.Schema -cne $script:CddsiRealtimeNotificationSchema) {
            throw 'INVALID_SCHEMA'
        }
        foreach ($stringProperty in @(
                'Schema', 'Lane', 'MessageId', 'PayloadSha256', 'RepositoryId', 'Ref',
                'Commit', 'CreatedAt', 'Expiry', 'SenderRole'
            )) {
            if ($message.$stringProperty -isnot [string]) {
                throw 'INVALID_FIELD_TYPE'
            }
        }
        if ($null -ne $message.PreviousSha256 -and $message.PreviousSha256 -isnot [string]) {
            throw 'INVALID_FIELD_TYPE'
        }
        if (@('host-to-vm', 'vm-to-host') -cnotcontains $message.Lane) {
            throw 'INVALID_LANE'
        }
        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $message.Lane
        if ($message.SenderRole -cne $policy.SenderRole) {
            throw 'WRONG_SENDER_ROLE'
        }
        if ($message.RepositoryId -cne $policy.RepositoryId) {
            throw 'WRONG_REPOSITORY'
        }
        if ($message.Ref -cne 'refs/heads/main') {
            throw 'INVALID_REF'
        }
        if ($message.MessageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$') {
            throw 'INVALID_MESSAGE_ID'
        }
        if ($message.Sequence -isnot [int] -and $message.Sequence -isnot [long]) {
            throw 'INVALID_SEQUENCE'
        }
        if ([long]$message.Sequence -lt 1 -or
            [long]$message.Sequence -gt $script:CddsiRealtimeMaxSafeInteger) {
            throw 'INVALID_SEQUENCE'
        }
        if ($null -ne $message.PreviousSha256 -and $message.PreviousSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'INVALID_PREVIOUS_HASH'
        }
        if ($message.PayloadSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'INVALID_PAYLOAD_HASH'
        }
        if ($message.Commit -cnotmatch '^[0-9a-f]{40}$') {
            throw 'INVALID_COMMIT'
        }
        $created = [DateTimeOffset]::MinValue
        $expiry = [DateTimeOffset]::MinValue
        if (-not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $message.CreatedAt -Parsed ([ref]$created))) {
            throw 'INVALID_CREATED_AT'
        }
        if (-not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $message.Expiry -Parsed ([ref]$expiry))) {
            throw 'INVALID_EXPIRY'
        }
        if ($ValidationMode -ceq 'Strict' -and
            [Math]::Abs(($created - $NowUtc).TotalSeconds) -gt $script:CddsiRealtimeMaxClockSkewSeconds) {
            throw 'CREATED_AT_OUTSIDE_WINDOW'
        }
        if ($ValidationMode -ceq 'Strict' -and $expiry -le $NowUtc) {
            throw 'MESSAGE_EXPIRED'
        }
        if ($expiry -le $created -or ($expiry - $created).TotalSeconds -gt $script:CddsiRealtimeMaxTtlSeconds) {
            throw 'INVALID_TTL'
        }
        return [pscustomobject][ordered]@{
            Valid = $true
            Code = 'VALID'
            Message = $message
            MessageSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $RawMessage
        }
    }
    catch {
        $code = [string]$_.Exception.Message
        if ($code -notmatch '^[A-Z0-9_]+$') {
            $code = 'INVALID_NOTIFICATION'
        }
        return [pscustomobject][ordered]@{
            Valid = $false
            Code = $code
            Message = $null
            MessageSha256 = $null
        }
    }
}

function New-CddsiRealtimeRelayInitialStateInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeStateSchema
        Lane = $Lane
        LastConsumedSequence = [long]0
        LastAckedSequence = [long]0
        LastMessageSha256 = $null
        ProcessedMessages = @()
        Revision = [long]0
    }
}

function Test-CddsiRealtimeRelayStateInternal {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $State -Expected $script:CddsiRealtimeStateProperties)) {
        return $false
    }
    if ($State.SchemaVersion -cne $script:CddsiRealtimeStateSchema -or $State.Lane -cne $Lane) {
        return $false
    }
    if ($State.SchemaVersion -isnot [string] -or $State.Lane -isnot [string] -or
        ($null -ne $State.LastMessageSha256 -and $State.LastMessageSha256 -isnot [string])) {
        return $false
    }
    foreach ($number in @($State.LastConsumedSequence, $State.LastAckedSequence, $State.Revision)) {
        if (($number -isnot [int] -and $number -isnot [long]) -or [long]$number -lt 0 -or
            [long]$number -gt $script:CddsiRealtimeMaxSafeInteger) {
            return $false
        }
    }
    if ([long]$State.LastAckedSequence -gt [long]$State.LastConsumedSequence) {
        return $false
    }
    if ([long]$State.LastConsumedSequence -eq 0 -and $null -ne $State.LastMessageSha256) {
        return $false
    }
    if ([long]$State.LastConsumedSequence -gt 0 -and $State.LastMessageSha256 -cnotmatch '^[0-9a-f]{64}$') {
        return $false
    }
    if ($null -eq $State.ProcessedMessages -or $State.ProcessedMessages -isnot [Array] -or
        @($State.ProcessedMessages).Count -gt 256) {
        return $false
    }
    $processedCount = @($State.ProcessedMessages).Count
    if ($processedCount -eq 0 -and [long]$State.LastConsumedSequence -ne 0) {
        return $false
    }
    $expectedSequence = [long]$State.LastConsumedSequence - $processedCount + 1
    if ($processedCount -gt 0 -and $expectedSequence -lt 1) {
        return $false
    }
    $seenMessageIds = @{}
    $lastProcessedHash = $null
    foreach ($processed in @($State.ProcessedMessages)) {
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $processed -Expected @(
                    'MessageId', 'Sequence', 'MessageSha256', 'PayloadSha256'
                ))) {
            return $false
        }
        if (($processed.Sequence -isnot [int] -and $processed.Sequence -isnot [long]) -or
            [long]$processed.Sequence -ne $expectedSequence -or
            $processed.MessageId -isnot [string] -or
            $processed.MessageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $processed.MessageSha256 -isnot [string] -or
            $processed.MessageSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $processed.PayloadSha256 -isnot [string] -or
            $processed.PayloadSha256 -cnotmatch '^[0-9a-f]{64}$') {
            return $false
        }
        if ($seenMessageIds.ContainsKey($processed.MessageId)) {
            return $false
        }
        $seenMessageIds[$processed.MessageId] = $true
        $lastProcessedHash = $processed.MessageSha256
        $expectedSequence++
    }
    if ($processedCount -gt 0 -and $lastProcessedHash -cne $State.LastMessageSha256) {
        return $false
    }
    return $true
}

function Assert-CddsiRealtimeRelayContextInternal {
    param(
        [Parameter(Mandatory = $true)]$RelayContext,
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$RuntimeAssertion
    )

    if ($null -eq $RelayContext -or $null -eq $RelayContext.PSObject -or
        $null -eq $RelayContext.PSObject.Properties['SchemaVersion'] -or
        $null -eq $RelayContext.PSObject.Properties['Mode'] -or
        $null -eq $RelayContext.PSObject.Properties['Providers'] -or
        $RelayContext.SchemaVersion -cne $script:CddsiRealtimeContextSchema -or
        $RelayContext.Mode -cne $Mode -or $null -eq $RelayContext.Providers) {
        throw 'REALTIME_CONTEXT_INVALID'
    }
    $requiredProviders = @('State', 'Transport', 'Wake', 'Clock', 'Credential')
    foreach ($name in $requiredProviders) {
        if ($null -eq $RelayContext.Providers.$name) {
            throw 'REALTIME_PROVIDER_MISSING'
        }
    }
    $providerKind = [string]$RelayContext.ProviderKind
    if ($Mode -cne 'Live' -and $providerKind -cne 'Fake') {
        throw 'REALTIME_NONLIVE_PROVIDER_NOT_FAKE'
    }
    if ($Mode -ceq 'Live') {
        if ($PSVersionTable.PSVersion.Major -ne 7 -or $providerKind -cne 'Live') {
            throw 'REALTIME_LIVE_PROVIDER_INVALID'
        }
        [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                -RelayContext $RelayContext -Lane $Lane -RuntimeAssertion $RuntimeAssertion)
    }
    else {
        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
        if ($RuntimeAssertion.SchemaVersion -cne $script:CddsiRealtimeAssertionSchema -or
            $RuntimeAssertion.Status -cne 'SYNTHETIC' -or $RuntimeAssertion.Lane -cne $Lane -or
            $RuntimeAssertion.ClientId -cne $policy.ReaderClientId -or
            $RelayContext.ClientId -cne $RuntimeAssertion.ClientId) {
            throw 'REALTIME_SYNTHETIC_ASSERTION_INVALID'
        }
    }
    $credentialReady = if ($Mode -ceq 'Live') {
        try {
            [void](Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal `
                    -CredentialProvider $RelayContext.Providers.Credential -Operation Validate)
            $true
        }
        catch {
            $false
        }
    }
    else {
        if ($RelayContext.Providers.Credential.TestReady -isnot [scriptblock]) {
            throw 'REALTIME_CREDENTIAL_RESULT_INVALID'
        }
        & $RelayContext.Providers.Credential.TestReady
    }
    if ($credentialReady -isnot [bool]) {
        throw 'REALTIME_CREDENTIAL_RESULT_INVALID'
    }
    if (-not $credentialReady) {
        throw 'REALTIME_CREDENTIAL_NOT_READY'
    }
}

function Copy-CddsiRealtimeRelayPlainDataInternal {
    param(
        [AllowNull()]$Value,
        [ValidateRange(0, 16)][int]$Depth = 0
    )

    if ($Depth -ge 16) {
        throw 'REALTIME_WAKE_BINDING_INVALID'
    }
    if ($null -eq $Value) {
        return $null
    }
    if ($Value -is [scriptblock] -or $Value -is [Delegate] -or
        $Value -is [Management.Automation.CommandInfo] -or $Value -is [Type] -or
        $Value -is [Reflection.MemberInfo]) {
        throw 'REALTIME_WAKE_BINDING_EXECUTABLE_FORBIDDEN'
    }
    if ($Value -is [string] -or $Value -is [bool] -or $Value -is [byte] -or
        $Value -is [int16] -or $Value -is [int] -or $Value -is [long]) {
        return $Value
    }
    if ($Value -is [Array]) {
        if ($Value.Count -gt 256) {
            throw 'REALTIME_WAKE_BINDING_INVALID'
        }
        $copy = @()
        foreach ($item in $Value) {
            $copy += ,(Copy-CddsiRealtimeRelayPlainDataInternal -Value $item -Depth ($Depth + 1))
        }
        return ,$copy
    }
    if ($Value -is [Collections.IDictionary]) {
        if ($Value.Count -gt 128) {
            throw 'REALTIME_WAKE_BINDING_INVALID'
        }
        $copy = [ordered]@{}
        foreach ($key in @($Value.Keys)) {
            if ($key -isnot [string] -or $key -cnotmatch '^[A-Za-z][A-Za-z0-9]{0,63}$') {
                throw 'REALTIME_WAKE_BINDING_INVALID'
            }
            $copy[$key] = Copy-CddsiRealtimeRelayPlainDataInternal -Value $Value[$key] -Depth ($Depth + 1)
        }
        return [pscustomobject]$copy
    }
    if ($Value.PSObject.TypeNames[0] -ceq 'System.Management.Automation.PSCustomObject') {
        $properties = @($Value.PSObject.Properties)
        if ($properties.Count -gt 128 -or @($properties | Where-Object {
                    $_.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty -or
                    $_.Name -cnotmatch '^[A-Za-z][A-Za-z0-9]{0,63}$'
                }).Count -ne 0) {
            throw 'REALTIME_WAKE_BINDING_INVALID'
        }
        $copy = [ordered]@{}
        foreach ($property in $properties) {
            $copy[$property.Name] = Copy-CddsiRealtimeRelayPlainDataInternal `
                -Value $property.Value -Depth ($Depth + 1)
        }
        return [pscustomobject]$copy
    }
    throw 'REALTIME_WAKE_BINDING_INVALID'
}

function Test-CddsiRealtimeRelayDataDescriptorInternal {
    param(
        [Parameter(Mandatory = $true)]$Descriptor,
        [Parameter(Mandatory = $true)][string[]]$ExpectedProperties
    )

    try {
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $Descriptor `
                -Expected $ExpectedProperties) -or
            @($Descriptor.PSObject.Properties | Where-Object {
                    $_.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty
                }).Count -ne 0) {
            return $false
        }
        [void](Copy-CddsiRealtimeRelayPlainDataInternal -Value $Descriptor)
        return $true
    }
    catch {
        return $false
    }
}

function Get-CddsiRealtimeRelayFileSha256Internal {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    $fullPath = [IO.Path]::GetFullPath($Path)
    $file = [IO.FileInfo]::new($fullPath)
    if (-not $file.Exists -or (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
        -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $file.DirectoryName)) {
        throw 'REALTIME_WAKE_SOURCE_INVALID'
    }
    $stream = [IO.File]::Open($fullPath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($stream))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        $stream.Dispose()
    }
}

function Get-CddsiRealtimeRelayClientAdapterSha256Internal {
    if ([string]::IsNullOrEmpty($script:CddsiRealtimeRelayClientPath)) {
        throw 'REALTIME_CLIENT_ADAPTER_SOURCE_INVALID'
    }
    return Get-CddsiRealtimeRelayFileSha256Internal -Path $script:CddsiRealtimeRelayClientPath
}

function Assert-CddsiRealtimeRelayFixedWakeSourcesInternal {
    param(
        [Parameter(Mandatory = $true)][string]$AdapterSha256,
        [Parameter(Mandatory = $true)][string]$GitOutboxRunnerSha256,
        [Parameter(Mandatory = $true)][string]$CodexExecutable,
        [Parameter(Mandatory = $true)][string]$CodexExecutableSha256
    )

    if ($AdapterSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $GitOutboxRunnerSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $CodexExecutableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]::IsNullOrEmpty($script:CddsiRealtimeRelayClientPath) -or
        [string]::IsNullOrEmpty($script:CddsiRealtimeGitOutboxRunnerPath) -or
        (Get-CddsiRealtimeRelayFileSha256Internal -Path $script:CddsiRealtimeRelayClientPath) -cne $AdapterSha256 -or
        (Get-CddsiRealtimeRelayFileSha256Internal -Path $script:CddsiRealtimeGitOutboxRunnerPath) -cne
        $GitOutboxRunnerSha256 -or
        -not [IO.Path]::IsPathRooted($CodexExecutable) -or
        [IO.Path]::GetFullPath($CodexExecutable) -cne $CodexExecutable -or
        [IO.Path]::GetFileName($CodexExecutable) -ine 'codex.exe' -or
        (Get-CddsiRealtimeRelayFileSha256Internal -Path $CodexExecutable) -cne
        $CodexExecutableSha256) {
        throw 'REALTIME_WAKE_SOURCE_HASH_MISMATCH'
    }
    $commands = @(Get-Command -Name 'Invoke-CddsiFastLaneGitOutbox' -CommandType Function -All `
            -ErrorAction SilentlyContinue)
    if ($commands.Count -ne 1 -or
        [string]::IsNullOrEmpty($commands[0].ScriptBlock.File) -or
        [IO.Path]::GetFullPath($commands[0].ScriptBlock.File) -cne $script:CddsiRealtimeGitOutboxRunnerPath) {
        throw 'REALTIME_WAKE_FIXED_ENTRY_INVALID'
    }
}

function Get-CddsiRealtimeRelayCodexArgumentContractSha256Internal {
    $argumentContract = @(
        'exec', 'resume', '--json', '<FIXED_UUID_SESSION_ID>',
        '<SOURCE_CONSTANT_PROMPT>'
    ) -join "`n"
    return Get-CddsiRealtimeRelayTextSha256Internal -Text (
        'cddsi-realtime-relay-codex-argv-v1' + "`n" + $argumentContract
    )
}

function Get-CddsiRealtimeRelayCodexResumeBindingSha256Internal {
    param(
        [Parameter(Mandatory = $true)][string]$CodexExecutable,
        [Parameter(Mandatory = $true)][string]$CodexExecutableSha256,
        [Parameter(Mandatory = $true)][string]$CodexSessionId,
        [Parameter(Mandatory = $true)][string]$CodexWorkingRoot,
        [Parameter(Mandatory = $true)][string]$CodexWorkingRootSha256,
        [Parameter(Mandatory = $true)][string]$CodexHome,
        [Parameter(Mandatory = $true)][string]$CodexHomeSha256,
        [Parameter(Mandatory = $true)][string]$CodexUserProfile,
        [Parameter(Mandatory = $true)][string]$CodexUserProfileSha256,
        [Parameter(Mandatory = $true)][string]$CodexLocalAppData,
        [Parameter(Mandatory = $true)][string]$CodexLocalAppDataSha256,
        [Parameter(Mandatory = $true)][string]$CodexTempRoot,
        [Parameter(Mandatory = $true)][string]$CodexTempRootSha256,
        [Parameter(Mandatory = $true)][string]$CodexTempOwnerMarkerSha256,
        [Parameter(Mandatory = $true)][int]$CodexMaximumRuntimeSeconds,
        [Parameter(Mandatory = $true)][string]$CodexPromptSha256,
        [Parameter(Mandatory = $true)][string]$CodexArgumentContractSha256
    )

    $values = @(
        'cddsi-realtime-relay-codex-resume-binding-v1',
        $CodexExecutable, $CodexExecutableSha256, $CodexSessionId,
        $CodexWorkingRoot, $CodexWorkingRootSha256,
        $CodexHome, $CodexHomeSha256, $CodexUserProfile, $CodexUserProfileSha256,
        $CodexLocalAppData, $CodexLocalAppDataSha256,
        $CodexTempRoot, $CodexTempRootSha256, $CodexTempOwnerMarkerSha256,
        $CodexMaximumRuntimeSeconds.ToString([Globalization.CultureInfo]::InvariantCulture),
        $CodexPromptSha256, $CodexArgumentContractSha256
    )
    return Get-CddsiRealtimeRelayTextSha256Internal -Text ($values -join "`n")
}

function Get-CddsiRealtimeRelayCodexTempOwnerMarkerInternal {
    param(
        [Parameter(Mandatory = $true)][string]$CodexSessionId,
        [Parameter(Mandatory = $true)][string]$CodexTempRootSha256
    )

    return ConvertTo-Json -Compress -InputObject ([ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-codex-temp-owner-v1'
            CodexSessionId = $CodexSessionId
            CodexTempRootSha256 = $CodexTempRootSha256
        })
}

function Assert-CddsiRealtimeRelayCodexResumeBindingInternal {
    param(
        [Parameter(Mandatory = $true)]$WakeProvider,
        [switch]$VerifySource
    )

    $fullExecutable = [IO.Path]::GetFullPath([string]$WakeProvider.CodexExecutable)
    $fullWorkingRoot = [IO.Path]::GetFullPath([string]$WakeProvider.CodexWorkingRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullCodexHome = [IO.Path]::GetFullPath([string]$WakeProvider.CodexHome).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullUserProfile = [IO.Path]::GetFullPath([string]$WakeProvider.CodexUserProfile).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullLocalAppData = [IO.Path]::GetFullPath([string]$WakeProvider.CodexLocalAppData).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullTempRoot = [IO.Path]::GetFullPath([string]$WakeProvider.CodexTempRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $environmentRootsValid = $true
    foreach ($environmentRoot in @($fullCodexHome, $fullUserProfile, $fullLocalAppData)) {
        if (-not [IO.Path]::IsPathRooted($environmentRoot) -or
            -not [IO.Directory]::Exists($environmentRoot) -or
            -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $environmentRoot)) {
            $environmentRootsValid = $false
        }
    }
    $tempRootSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $fullTempRoot
    $tempMarkerText = Get-CddsiRealtimeRelayCodexTempOwnerMarkerInternal `
        -CodexSessionId $WakeProvider.CodexSessionId -CodexTempRootSha256 $tempRootSha256
    $tempMarkerValid = $false
    try {
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        $expectedTempParent = [IO.Path]::GetFullPath([string]$WakeProvider.Binding.StateRoot).TrimEnd(
            [IO.Path]::DirectorySeparatorChar
        )
        $tempMarkerPath = [IO.Path]::Combine($fullTempRoot, '.cddsi-codex-temp-owner.json')
        if ([IO.Path]::GetDirectoryName($fullTempRoot).TrimEnd(
                [IO.Path]::DirectorySeparatorChar) -ceq $expectedTempParent -and
            [IO.DirectoryInfo]::new($fullTempRoot).Name -ceq
            ('codex-wake-' + $WakeProvider.CodexSessionId) -and
            [IO.Directory]::Exists($fullTempRoot) -and
            (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullTempRoot) -and
            (Test-CddsiRealtimeRelayProtectedDirectoryAclInternal `
                -StateRoot $fullTempRoot -OwnerSid $currentSid)) {
            $tempMarkerBytes = Read-CddsiRealtimeRelayBoundedFileInternal `
                -Path $tempMarkerPath -MaximumBytes 1024 `
                -FailureCode 'REALTIME_WAKE_CODEX_TEMP_INVALID'
            try {
                $actualTempMarker = [Text.UTF8Encoding]::new($false, $true).GetString(
                    $tempMarkerBytes
                )
                $tempMarkerValid = $actualTempMarker -ceq $tempMarkerText -and
                (Get-CddsiRealtimeRelaySha256Internal -Bytes $tempMarkerBytes) -ceq
                $WakeProvider.CodexTempOwnerMarkerSha256
            }
            finally {
                [Array]::Clear($tempMarkerBytes, 0, $tempMarkerBytes.Length)
            }
        }
    }
    catch {
        $tempMarkerValid = $false
    }
    if (-not [IO.Path]::IsPathRooted([string]$WakeProvider.CodexExecutable) -or
        $fullExecutable -cne $WakeProvider.CodexExecutable -or
        [IO.Path]::GetFileName($fullExecutable) -ine 'codex.exe' -or
        -not [IO.Path]::IsPathRooted([string]$WakeProvider.CodexWorkingRoot) -or
        $fullWorkingRoot -cne $WakeProvider.CodexWorkingRoot -or
        -not [IO.Directory]::Exists($fullWorkingRoot) -or
        -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullWorkingRoot) -or
        -not $environmentRootsValid -or
        -not $tempMarkerValid -or
        $WakeProvider.CodexExecutableSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $WakeProvider.CodexSessionId -cnotmatch
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        ($WakeProvider.CodexMaximumRuntimeSeconds -isnot [int] -and
            $WakeProvider.CodexMaximumRuntimeSeconds -isnot [long]) -or
        [long]$WakeProvider.CodexMaximumRuntimeSeconds -lt 5 -or
        [long]$WakeProvider.CodexMaximumRuntimeSeconds -gt 300 -or
        $WakeProvider.CodexWorkingRootSha256 -cne
        (Get-CddsiRealtimeRelayTextSha256Internal -Text $fullWorkingRoot) -or
        $WakeProvider.CodexHome -cne $fullCodexHome -or
        $WakeProvider.CodexHomeSha256 -cne
        (Get-CddsiRealtimeRelayTextSha256Internal -Text $fullCodexHome) -or
        $WakeProvider.CodexUserProfile -cne $fullUserProfile -or
        $WakeProvider.CodexUserProfileSha256 -cne
        (Get-CddsiRealtimeRelayTextSha256Internal -Text $fullUserProfile) -or
        $WakeProvider.CodexLocalAppData -cne $fullLocalAppData -or
        $WakeProvider.CodexLocalAppDataSha256 -cne
        (Get-CddsiRealtimeRelayTextSha256Internal -Text $fullLocalAppData) -or
        $WakeProvider.CodexTempRoot -cne $fullTempRoot -or
        $WakeProvider.CodexTempRootSha256 -cne $tempRootSha256 -or
        $WakeProvider.CodexTempOwnerMarkerSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        $WakeProvider.CodexPromptSha256 -cne
        (Get-CddsiRealtimeRelayTextSha256Internal -Text $script:CddsiRealtimeFixedResumePrompt) -or
        $WakeProvider.CodexArgumentContractSha256 -cne
        (Get-CddsiRealtimeRelayCodexArgumentContractSha256Internal)) {
        throw 'REALTIME_WAKE_CODEX_BINDING_INVALID'
    }
    $expectedResumeBinding = Get-CddsiRealtimeRelayCodexResumeBindingSha256Internal `
        -CodexExecutable $fullExecutable `
        -CodexExecutableSha256 $WakeProvider.CodexExecutableSha256 `
        -CodexSessionId $WakeProvider.CodexSessionId `
        -CodexWorkingRoot $fullWorkingRoot `
        -CodexWorkingRootSha256 $WakeProvider.CodexWorkingRootSha256 `
        -CodexHome $fullCodexHome -CodexHomeSha256 $WakeProvider.CodexHomeSha256 `
        -CodexUserProfile $fullUserProfile `
        -CodexUserProfileSha256 $WakeProvider.CodexUserProfileSha256 `
        -CodexLocalAppData $fullLocalAppData `
        -CodexLocalAppDataSha256 $WakeProvider.CodexLocalAppDataSha256 `
        -CodexTempRoot $fullTempRoot -CodexTempRootSha256 $tempRootSha256 `
        -CodexTempOwnerMarkerSha256 $WakeProvider.CodexTempOwnerMarkerSha256 `
        -CodexMaximumRuntimeSeconds ([int]$WakeProvider.CodexMaximumRuntimeSeconds) `
        -CodexPromptSha256 $WakeProvider.CodexPromptSha256 `
        -CodexArgumentContractSha256 $WakeProvider.CodexArgumentContractSha256
    if ($WakeProvider.CodexResumeBindingSha256 -cne $expectedResumeBinding) {
        throw 'REALTIME_WAKE_CODEX_BINDING_INVALID'
    }
    if ($VerifySource) {
        Assert-CddsiRealtimeRelayFixedWakeSourcesInternal `
            -AdapterSha256 $WakeProvider.AdapterSha256 `
            -GitOutboxRunnerSha256 $WakeProvider.GitOutboxRunnerSha256 `
            -CodexExecutable $fullExecutable `
            -CodexExecutableSha256 $WakeProvider.CodexExecutableSha256
    }
}

function Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal {
    param(
        [Parameter(Mandatory = $true)]$Binding
    )

    if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $Binding `
            -Expected $script:CddsiRealtimeGitOutboxBindingProperties)) {
        throw 'REALTIME_WAKE_BINDING_INVALID'
    }
    $plain = Copy-CddsiRealtimeRelayPlainDataInternal -Value $Binding
    $lines = @('cddsi-realtime-relay-fixed-git-outbox-binding-v1')
    foreach ($name in $script:CddsiRealtimeGitOutboxBindingProperties) {
        $value = $plain.$name
        if ($name -ceq 'ProtectionEvidence') {
            $value = $plain.ProtectionEvidenceSha256
        }
        if ($null -eq $value) {
            $encoded = 'n:'
        }
        elseif ($value -is [string]) {
            if ($value -match '[\u0000-\u001f\u007f]') {
                throw 'REALTIME_WAKE_BINDING_INVALID'
            }
            $byteCount = [Text.UTF8Encoding]::new($false, $true).GetByteCount($value)
            $encoded = 's:{0}:{1}' -f $byteCount, $value
        }
        elseif ($value -is [bool]) {
            $encoded = if ($value) { 'b:1' } else { 'b:0' }
        }
        elseif ($value -is [byte] -or $value -is [int16] -or $value -is [int] -or $value -is [long]) {
            $encoded = 'i:' + ([long]$value).ToString([Globalization.CultureInfo]::InvariantCulture)
        }
        elseif ($value -is [Array] -and $name -ceq 'AuthenticatedSenderRoles' -and $value.Count -eq 1 -and
            $value[0] -is [string]) {
            $encoded = 'a:1:' + $value[0]
        }
        else {
            throw 'REALTIME_WAKE_BINDING_INVALID'
        }
        $lines += $name
        $lines += $encoded
    }
    return Get-CddsiRealtimeRelayTextSha256Internal -Text ($lines -join "`n")
}

function Assert-CddsiRealtimeRelayGitOutboxBindingInternal {
    param(
        [Parameter(Mandatory = $true)]$Binding,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$GitOutboxRunnerSha256
    )

    [void](Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal -Binding $Binding)
    $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
    $expectedClient = if ($Lane -ceq 'host-to-vm') { 'vm-tester-v1' } else { 'host-coordinator-v1' }
    $expectedSender = if ($Lane -ceq 'host-to-vm') { 'HostCoordinator' } else { 'VmTester' }
    if ($ClientId -cne $expectedClient -or $Binding.AuthenticatedOutbox -cne $Lane -or
        $Binding.RemoteRef -cne 'refs/heads/main' -or
        $Binding.ExpectedRepositoryVisibility -cne 'PUBLIC' -or
        $Binding.RunnerSha256 -cne $GitOutboxRunnerSha256 -or
        $Binding.AuthenticatedSenderRoles -isnot [Array] -or
        @($Binding.AuthenticatedSenderRoles).Count -ne 1 -or
        $Binding.AuthenticatedSenderRoles[0] -cne $expectedSender -or
        ($Binding.ExpectedRepositoryNumericId -isnot [int] -and
            $Binding.ExpectedRepositoryNumericId -isnot [long]) -or
        [long]$Binding.ExpectedRepositoryNumericId -le 0 -or
        ([long]$Binding.ExpectedRepositoryNumericId).ToString(
            [Globalization.CultureInfo]::InvariantCulture) -cne $policy.RepositoryId -or
        -not [IO.Path]::IsPathRooted([string]$Binding.StateRoot) -or
        -not [IO.Path]::IsPathRooted([string]$Binding.ProductRoot) -or
        -not [IO.Path]::IsPathRooted([string]$Binding.OperatorWorkspaceRoot) -or
        -not [IO.Path]::IsPathRooted([string]$Binding.GitExecutable)) {
        throw 'REALTIME_WAKE_BINDING_INVALID'
    }
    foreach ($hashName in @(
            'GitExecutableSha256', 'RunnerSha256', 'ProtectionEvidenceSha256',
            'ExpectedProtectionPolicySha256', 'ExpectedProtectionAuthorityAssertionSha256',
            'ExpectedProtectionAuthorityBindingToken'
        )) {
        if ($Binding.$hashName -isnot [string] -or $Binding.$hashName -cnotmatch '^[0-9a-f]{64}$') {
            throw 'REALTIME_WAKE_BINDING_INVALID'
        }
    }
    if ($Binding.ExpectedGenesisCommit -isnot [string] -or
        $Binding.ExpectedGenesisCommit -cnotmatch '^[0-9a-f]{40}$') {
        throw 'REALTIME_WAKE_BINDING_INVALID'
    }
    if ([long]$Binding.MaximumRuntimeSeconds -lt 5 -or [long]$Binding.MaximumRuntimeSeconds -gt 45 -or
        [long]$Binding.MaximumGitCommandSeconds -lt 1 -or
        [long]$Binding.MaximumGitCommandSeconds -gt 45 -or
        [long]$Binding.MaximumOutputBytes -lt 4096 -or [long]$Binding.MaximumOutputBytes -gt 65536 -or
        [long]$Binding.MaximumMessageBodyBytes -lt 64 -or
        [long]$Binding.MaximumMessageBodyBytes -gt 65536 -or
        [long]$Binding.MaximumAgeSeconds -lt 1 -or [long]$Binding.MaximumAgeSeconds -gt 900 -or
        [long]$Binding.MaximumClockSkewSeconds -lt 0 -or
        [long]$Binding.MaximumClockSkewSeconds -gt 120 -or
        [long]$Binding.ProtectionEvidenceMaximumAgeSeconds -lt 60 -or
        [long]$Binding.ProtectionEvidenceMaximumAgeSeconds -gt 3600) {
        throw 'REALTIME_WAKE_BINDING_INVALID'
    }
}

function Test-CddsiRealtimeRelayFixedWakeProviderContractInternal {
    param(
        [Parameter(Mandatory = $true)]$WakeProvider,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [switch]$VerifySource
    )

    try {
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $WakeProvider `
                -Expected $script:CddsiRealtimeFixedWakeProviderProperties) -or
            @($WakeProvider.PSObject.Properties | Where-Object {
                    $_.MemberType -ne [Management.Automation.PSMemberTypes]::NoteProperty
                }).Count -ne 0 -or
            $WakeProvider.SchemaVersion -cne $script:CddsiRealtimeFixedWakeProviderSchema -or
            $WakeProvider.AdapterId -cne 'cddsi-fast-lane-fixed-resume-v1' -or
            $WakeProvider.Lane -cne $Lane -or $WakeProvider.ClientId -cne $ClientId -or
            $WakeProvider.AdapterSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $WakeProvider.BindingSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $WakeProvider.GitOutboxRunnerSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $WakeProvider.GitOutboxStateRootSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $WakeProvider.CodexResumeBindingSha256 -cnotmatch '^[0-9a-f]{64}$') {
            return $false
        }
        Assert-CddsiRealtimeRelayGitOutboxBindingInternal -Binding $WakeProvider.Binding `
            -Lane $Lane -ClientId $ClientId `
            -GitOutboxRunnerSha256 $WakeProvider.GitOutboxRunnerSha256
        if ((Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal -Binding $WakeProvider.Binding) -cne
            $WakeProvider.BindingSha256 -or
            (Get-CddsiRealtimeRelayTextSha256Internal -Text (
                    [IO.Path]::GetFullPath([string]$WakeProvider.Binding.StateRoot).TrimEnd(
                        [IO.Path]::DirectorySeparatorChar
                    )
                )) -cne $WakeProvider.GitOutboxStateRootSha256) {
            return $false
        }
        Assert-CddsiRealtimeRelayCodexResumeBindingInternal -WakeProvider $WakeProvider `
            -VerifySource:$VerifySource
        if ($VerifySource) {
            Assert-CddsiRealtimeRelayFixedWakeSourcesInternal `
                -AdapterSha256 $WakeProvider.AdapterSha256 `
                -GitOutboxRunnerSha256 $WakeProvider.GitOutboxRunnerSha256 `
                -CodexExecutable $WakeProvider.CodexExecutable `
                -CodexExecutableSha256 $WakeProvider.CodexExecutableSha256
        }
        return $true
    }
    catch {
        return $false
    }
}

function New-CddsiRealtimeRelayFixedGitOutboxWakeProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)]$GitOutboxBinding,
        [Parameter(Mandatory = $true)][string]$ExpectedBindingSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedAdapterSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedGitOutboxRunnerSha256,
        [Parameter(Mandatory = $true)][string]$CodexExecutable,
        [Parameter(Mandatory = $true)][string]$ExpectedCodexExecutableSha256,
        [Parameter(Mandatory = $true)][string]$CodexSessionId,
        [Parameter(Mandatory = $true)][string]$CodexWorkingRoot,
        [Parameter(Mandatory = $true)][string]$CodexHome,
        [Parameter(Mandatory = $true)][string]$CodexUserProfile,
        [Parameter(Mandatory = $true)][string]$CodexLocalAppData,
        [Parameter(Mandatory = $true)][string]$CodexTempRoot,
        [Parameter(Mandatory = $true)][ValidateRange(5, 300)][int]$CodexMaximumRuntimeSeconds
    )

    if ($ExpectedBindingSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'REALTIME_WAKE_BINDING_INVALID'
    }
    $plainBinding = Copy-CddsiRealtimeRelayPlainDataInternal -Value $GitOutboxBinding
    Assert-CddsiRealtimeRelayGitOutboxBindingInternal -Binding $plainBinding -Lane $Lane `
        -ClientId $ClientId -GitOutboxRunnerSha256 $ExpectedGitOutboxRunnerSha256
    if ((Get-CddsiRealtimeRelayGitOutboxBindingSha256Internal -Binding $plainBinding) -cne
        $ExpectedBindingSha256) {
        throw 'REALTIME_WAKE_BINDING_HASH_MISMATCH'
    }
    Assert-CddsiRealtimeRelayFixedWakeSourcesInternal -AdapterSha256 $ExpectedAdapterSha256 `
        -GitOutboxRunnerSha256 $ExpectedGitOutboxRunnerSha256 `
        -CodexExecutable ([IO.Path]::GetFullPath($CodexExecutable)) `
        -CodexExecutableSha256 $ExpectedCodexExecutableSha256
    $fullCodexExecutable = [IO.Path]::GetFullPath($CodexExecutable)
    $fullCodexWorkingRoot = [IO.Path]::GetFullPath($CodexWorkingRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullCodexHome = [IO.Path]::GetFullPath($CodexHome).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $fullCodexUserProfile = [IO.Path]::GetFullPath($CodexUserProfile).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullCodexLocalAppData = [IO.Path]::GetFullPath($CodexLocalAppData).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $fullCodexTempRoot = [IO.Path]::GetFullPath($CodexTempRoot).TrimEnd(
        [IO.Path]::DirectorySeparatorChar
    )
    $codexWorkingRootSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $fullCodexWorkingRoot
    $codexHomeSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $fullCodexHome
    $codexUserProfileSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $fullCodexUserProfile
    $codexLocalAppDataSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $fullCodexLocalAppData
    $codexTempRootSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $fullCodexTempRoot
    $codexTempOwnerMarkerSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text (
        Get-CddsiRealtimeRelayCodexTempOwnerMarkerInternal `
            -CodexSessionId $CodexSessionId -CodexTempRootSha256 $codexTempRootSha256
    )
    $codexPromptSha256 = Get-CddsiRealtimeRelayTextSha256Internal `
        -Text $script:CddsiRealtimeFixedResumePrompt
    $codexArgumentContractSha256 = Get-CddsiRealtimeRelayCodexArgumentContractSha256Internal
    $codexResumeBindingSha256 = Get-CddsiRealtimeRelayCodexResumeBindingSha256Internal `
        -CodexExecutable $fullCodexExecutable `
        -CodexExecutableSha256 $ExpectedCodexExecutableSha256 `
        -CodexSessionId $CodexSessionId -CodexWorkingRoot $fullCodexWorkingRoot `
        -CodexWorkingRootSha256 $codexWorkingRootSha256 `
        -CodexHome $fullCodexHome -CodexHomeSha256 $codexHomeSha256 `
        -CodexUserProfile $fullCodexUserProfile `
        -CodexUserProfileSha256 $codexUserProfileSha256 `
        -CodexLocalAppData $fullCodexLocalAppData `
        -CodexLocalAppDataSha256 $codexLocalAppDataSha256 `
        -CodexTempRoot $fullCodexTempRoot -CodexTempRootSha256 $codexTempRootSha256 `
        -CodexTempOwnerMarkerSha256 $codexTempOwnerMarkerSha256 `
        -CodexMaximumRuntimeSeconds $CodexMaximumRuntimeSeconds `
        -CodexPromptSha256 $codexPromptSha256 `
        -CodexArgumentContractSha256 $codexArgumentContractSha256
    $provider = [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeFixedWakeProviderSchema
        AdapterId = 'cddsi-fast-lane-fixed-resume-v1'
        Lane = $Lane
        ClientId = $ClientId
        AdapterSha256 = $ExpectedAdapterSha256
        BindingSha256 = $ExpectedBindingSha256
        GitOutboxRunnerSha256 = $ExpectedGitOutboxRunnerSha256
        GitOutboxStateRootSha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text (
            [IO.Path]::GetFullPath([string]$plainBinding.StateRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
        )
        CodexExecutable = $fullCodexExecutable
        CodexExecutableSha256 = $ExpectedCodexExecutableSha256
        CodexSessionId = $CodexSessionId
        CodexWorkingRoot = $fullCodexWorkingRoot
        CodexWorkingRootSha256 = $codexWorkingRootSha256
        CodexHome = $fullCodexHome
        CodexHomeSha256 = $codexHomeSha256
        CodexUserProfile = $fullCodexUserProfile
        CodexUserProfileSha256 = $codexUserProfileSha256
        CodexLocalAppData = $fullCodexLocalAppData
        CodexLocalAppDataSha256 = $codexLocalAppDataSha256
        CodexTempRoot = $fullCodexTempRoot
        CodexTempRootSha256 = $codexTempRootSha256
        CodexTempOwnerMarkerSha256 = $codexTempOwnerMarkerSha256
        CodexMaximumRuntimeSeconds = $CodexMaximumRuntimeSeconds
        CodexPromptSha256 = $codexPromptSha256
        CodexArgumentContractSha256 = $codexArgumentContractSha256
        CodexResumeBindingSha256 = $codexResumeBindingSha256
        Binding = $plainBinding
    }
    Assert-CddsiRealtimeRelayCodexResumeBindingInternal -WakeProvider $provider -VerifySource
    return $provider
}

function Invoke-CddsiRealtimeRelayBoundedProcessRunnerInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Executable,
        [Parameter(Mandatory = $true)][string]$ArgumentText,
        [Parameter(Mandatory = $true)][string]$WorkingDirectory,
        [Parameter(Mandatory = $true)][hashtable]$Environment,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$StandardInput,
        [Parameter(Mandatory = $true)][int]$TimeoutMilliseconds,
        [Parameter(Mandatory = $true)][int]$MaximumOutputBytes
    )

    return [Cddsi.FastLane.BoundedProcessRunner]::Run(
        $Executable,
        $ArgumentText,
        $WorkingDirectory,
        $Environment,
        $StandardInput,
        $TimeoutMilliseconds,
        $MaximumOutputBytes
    )
}

function New-CddsiRealtimeRelayFixedCodexInvocationInternal {
    param(
        [Parameter(Mandatory = $true)]$WakeProvider
    )

    Assert-CddsiRealtimeRelayCodexResumeBindingInternal -WakeProvider $WakeProvider -VerifySource
    if ($null -eq ('Cddsi.FastLane.BoundedProcessRunner' -as [type])) {
        throw 'REALTIME_FIXED_WAKE_REJECTED'
    }
    $quoteCommand = @(Get-Command -Name 'ConvertTo-CddsiFastLaneGitQuotedArgument' `
            -CommandType Function -All -ErrorAction SilentlyContinue)
    if ($quoteCommand.Count -ne 1 -or
        [string]::IsNullOrEmpty($quoteCommand[0].ScriptBlock.File) -or
        [IO.Path]::GetFullPath($quoteCommand[0].ScriptBlock.File) -cne
        $script:CddsiRealtimeGitOutboxRunnerPath) {
        throw 'REALTIME_FIXED_WAKE_REJECTED'
    }
    $argumentText = (@(
            'exec', 'resume', '--json', $WakeProvider.CodexSessionId,
            $script:CddsiRealtimeFixedResumePrompt
        ) | ForEach-Object {
            ConvertTo-CddsiFastLaneGitQuotedArgument -Value ([string]$_)
        }) -join ' '
    $systemRoot = [Environment]::GetEnvironmentVariable('SystemRoot', 'Machine')
    $windir = [Environment]::GetEnvironmentVariable('WINDIR', 'Machine')
    if ([string]::IsNullOrEmpty($systemRoot) -and -not [string]::IsNullOrEmpty($windir)) {
        $systemRoot = $windir
    }
    if ([string]::IsNullOrEmpty($windir) -and -not [string]::IsNullOrEmpty($systemRoot)) {
        $windir = $systemRoot
    }
    if ([string]::IsNullOrEmpty($systemRoot) -or [string]::IsNullOrEmpty($windir)) {
        throw 'REALTIME_FIXED_WAKE_REJECTED'
    }
    return [pscustomobject][ordered]@{
        Executable = $WakeProvider.CodexExecutable
        ArgumentText = $argumentText
        WorkingDirectory = $WakeProvider.CodexWorkingRoot
        Environment = @{
            SystemRoot = $systemRoot
            WINDIR = $windir
            HOME = $WakeProvider.CodexUserProfile
            USERPROFILE = $WakeProvider.CodexUserProfile
            LOCALAPPDATA = $WakeProvider.CodexLocalAppData
            CODEX_HOME = $WakeProvider.CodexHome
            TEMP = $WakeProvider.CodexTempRoot
            TMP = $WakeProvider.CodexTempRoot
            NO_COLOR = '1'
        }
        StandardInput = ''
        TimeoutMilliseconds = [int]$WakeProvider.CodexMaximumRuntimeSeconds * 1000
        MaximumOutputBytes = 4096
    }
}

function ConvertTo-CddsiRealtimeRelayFixedCodexResultInternal {
    param(
        [Parameter(Mandatory = $true)]$RunnerResult
    )

    foreach ($booleanName in @('TimedOut', 'Truncated', 'JobAssigned', 'ProcessTreeTerminated')) {
        if ($null -eq $RunnerResult.PSObject.Properties[$booleanName] -or
            $RunnerResult.$booleanName -isnot [bool]) {
            throw 'REALTIME_FIXED_WAKE_REJECTED'
        }
    }
    if ($null -eq $RunnerResult.PSObject.Properties['ExitCode'] -or
        $RunnerResult.ExitCode -isnot [int] -or
        $null -eq $RunnerResult.PSObject.Properties['StandardOutput'] -or
        $RunnerResult.StandardOutput -isnot [string] -or
        $null -eq $RunnerResult.PSObject.Properties['StandardError'] -or
        $RunnerResult.StandardError -isnot [string] -or
        -not $RunnerResult.JobAssigned -or $RunnerResult.TimedOut -or
        $RunnerResult.ProcessTreeTerminated -or $RunnerResult.ExitCode -ne 0) {
        throw 'REALTIME_FIXED_WAKE_REJECTED'
    }
    return [pscustomobject][ordered]@{
        Started = $true
        Completed = $true
        ExitCode = 0
        TimedOut = $false
        JobAssigned = $true
        ProcessTreeTerminated = $false
        EnvironmentInheritedCount = 0
        OutputDiscarded = $true
    }
}

function Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal {
    param(
        [Parameter(Mandatory = $true)]$WakeProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    if ($PSVersionTable.PSVersion.Major -ne 7) {
        throw 'REALTIME_FIXED_WAKE_REJECTED'
    }
    $remaining = $AuthorizationExpiresAtUtc -
    (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)
    if ($remaining.TotalSeconds -le ([int]$WakeProvider.CodexMaximumRuntimeSeconds + 5)) {
        throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
    }
    try {
        $invocation = New-CddsiRealtimeRelayFixedCodexInvocationInternal `
            -WakeProvider $WakeProvider
        $result = Invoke-CddsiRealtimeRelayBoundedProcessRunnerInternal `
            -Executable $invocation.Executable -ArgumentText $invocation.ArgumentText `
            -WorkingDirectory $invocation.WorkingDirectory `
            -Environment $invocation.Environment -StandardInput $invocation.StandardInput `
            -TimeoutMilliseconds $invocation.TimeoutMilliseconds `
            -MaximumOutputBytes $invocation.MaximumOutputBytes
        return ConvertTo-CddsiRealtimeRelayFixedCodexResultInternal -RunnerResult $result
    }
    catch {
        if ($_.Exception.Message -ceq 'REALTIME_RUNTIME_ASSERTION_EXPIRED') {
            throw
        }
        throw 'REALTIME_FIXED_WAKE_REJECTED'
    }
}

function Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal {
    param(
        [Parameter(Mandatory = $true)]$WakeProvider,
        [Parameter(Mandatory = $true)]$WakeEvent,
        [Parameter(Mandatory = $true)]$StateProvider,
        [Parameter(Mandatory = $true)]$AuditSession,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)]$RelayContext,
        [Parameter(Mandatory = $true)]$RuntimeAssertion,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $WakeEvent -Expected @(
                'SchemaVersion', 'Verb', 'Lane', 'MessageId', 'Sequence', 'RepositoryId',
                'Ref', 'Commit', 'PayloadSha256'
            )) -or
        $WakeEvent.SchemaVersion -cne 'cddsi-realtime-relay-wake-event-v1' -or
        $WakeEvent.Verb -cne 'CONTROL_REPO_POINTER_AVAILABLE' -or
        -not (Test-CddsiRealtimeRelayFixedWakeProviderContractInternal -WakeProvider $WakeProvider `
            -Lane $WakeEvent.Lane -ClientId $WakeProvider.ClientId -VerifySource) -or
        [string]$WakeProvider.Binding.ExpectedRepositoryNumericId -cne $WakeEvent.RepositoryId -or
        $WakeProvider.Binding.RemoteRef -cne $WakeEvent.Ref) {
        throw 'REALTIME_FIXED_WAKE_PROVIDER_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $StateProvider -VerifySource)) {
        throw 'REALTIME_FIXED_WAKE_PROVIDER_INVALID'
    }

    $arguments = @{}
    foreach ($name in $script:CddsiRealtimeGitOutboxBindingProperties) {
        $arguments[$name] = $WakeProvider.Binding.$name
    }
    $arguments['Operation'] = 'Poll'
    $arguments['Mode'] = 'Live'
    $arguments['AcknowledgeOperatorPlaneLive'] = $true
    $arguments['ExpectedWakePointer'] = $WakeEvent
    $arguments['MaximumMessageCount'] = 1
    $arguments['MaximumRetryCount'] = 0
    $arguments['FailureInjection'] = 'None'
    $arguments['ValidationTimeUtc'] = [DateTimeOffset]::UtcNow.ToString(
        'yyyy-MM-ddTHH:mm:ss.fffffffZ',
        [Globalization.CultureInfo]::InvariantCulture
    )
    $result = Invoke-CddsiFastLaneGitOutbox @arguments
    if ($null -eq $result -or $null -eq $result.PSObject.Properties['WakeReceipt'] -or
        $null -eq $result.WakeReceipt) {
        throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
    }
    $receipt = $result.WakeReceipt
    $receiptProperties = @(
        'SchemaVersion', 'ContractVersion', 'Status', 'Lane', 'MessageId', 'Sequence',
        'RepositoryId', 'Ref', 'Commit', 'PayloadSha256', 'RepositoryIdentityVerified',
        'PayloadSha256Verified', 'FixedEntryInvoked', 'Consumed'
    )
    if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $receipt `
            -Expected $receiptProperties) -or
        ($receipt.SchemaVersion -isnot [int] -and $receipt.SchemaVersion -isnot [long]) -or
        [long]$receipt.SchemaVersion -ne 1 -or
        $receipt.ContractVersion -cne 'cddsi-fast-lane-wake-receipt-v1' -or
        @('CONSUMED_NOW', 'ALREADY_CONSUMED') -cnotcontains $receipt.Status -or
        $receipt.Lane -cne $WakeEvent.Lane -or $receipt.MessageId -cne $WakeEvent.MessageId -or
        [long]$receipt.Sequence -ne [long]$WakeEvent.Sequence -or
        $receipt.RepositoryId -cne $WakeEvent.RepositoryId -or $receipt.Ref -cne $WakeEvent.Ref -or
        $receipt.Commit -cne $WakeEvent.Commit -or
        $receipt.PayloadSha256 -cne $WakeEvent.PayloadSha256) {
        throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
    }
    foreach ($metricName in @('GitInvocationCount', 'OperatorGitTransportCount', 'LocalStateMutationCount')) {
        if ($null -eq $result.PSObject.Properties[$metricName] -or
            ($result.$metricName -isnot [int] -and $result.$metricName -isnot [long]) -or
            [long]$result.$metricName -lt 0) {
            throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
        }
    }
    if ($null -eq $result.PSObject.Properties['ProductNetworkRequestCount'] -or
        $result.ProductNetworkRequestCount -ne 0) {
        throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
    }
    $AuditSession.OperatorGitInvocationCount =
    [long]$AuditSession.OperatorGitInvocationCount + [long]$result.GitInvocationCount
    $AuditSession.OperatorGitTransportCount =
    [long]$AuditSession.OperatorGitTransportCount + [long]$result.OperatorGitTransportCount
    $AuditSession.OperatorLocalStateMutationCount =
    [long]$AuditSession.OperatorLocalStateMutationCount + [long]$result.LocalStateMutationCount
    if ([long]$result.LocalStateMutationCount -gt 0 -or $receipt.Status -ceq 'CONSUMED_NOW') {
        $AuditSession.PersistentChangeObserved = $true
    }
    if ($receipt.FixedEntryInvoked -isnot [bool]) {
        throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
    }
    foreach ($name in @('RepositoryIdentityVerified', 'PayloadSha256Verified', 'Consumed')) {
        if ($receipt.$name -isnot [bool] -or -not $receipt.$name) {
            throw 'REALTIME_FIXED_WAKE_REJECTED'
        }
    }
    $proofState = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
        -StateProvider $StateProvider -Operation LoadWakeProof -Lane $WakeEvent.Lane
    if (-not (Test-CddsiRealtimeRelayWakeProofStateInternal `
            -State $proofState -Lane $WakeEvent.Lane)) {
        throw 'REALTIME_WAKE_PROOF_INVALID'
    }
    $proofMatches = @($proofState.Entries | Where-Object {
            $_.MessageId -ceq $WakeEvent.MessageId
        })
    $fixedEntryInvoked = $false
    $previouslyInvoked = $false
    $processSpawnCount = 0L
    $proofLocalMutationCount = 0L
    if ($proofMatches.Count -gt 1 -or
        ($proofMatches.Count -eq 1 -and (
            [long]$proofMatches[0].Sequence -ne [long]$WakeEvent.Sequence -or
            $proofMatches[0].Commit -cne $WakeEvent.Commit -or
            $proofMatches[0].PayloadSha256 -cne $WakeEvent.PayloadSha256
        ))) {
        throw 'REALTIME_WAKE_PROOF_INVALID'
    }
    if ($receipt.Status -ceq 'CONSUMED_NOW' -and $proofMatches.Count -ne 0) {
        throw 'REALTIME_WAKE_PROOF_INVALID'
    }
    if ($proofMatches.Count -eq 1 -and $proofMatches[0].Status -ceq 'SUCCEEDED') {
        if ($receipt.Status -cne 'ALREADY_CONSUMED') {
            throw 'REALTIME_WAKE_PROOF_INVALID'
        }
        $previouslyInvoked = $true
    }
    else {
        if ($proofMatches.Count -eq 0) {
            if ([long]$proofState.Revision -ge $script:CddsiRealtimeMaxSafeInteger) {
                throw 'REALTIME_WAKE_PROOF_INVALID'
            }
            $proofState.Entries = @($proofState.Entries) + @(
                [pscustomobject][ordered]@{
                    MessageId = $WakeEvent.MessageId
                    Sequence = [long]$WakeEvent.Sequence
                    Commit = $WakeEvent.Commit
                    PayloadSha256 = $WakeEvent.PayloadSha256
                    Status = 'PENDING'
                }
            )
            if (@($proofState.Entries).Count -gt 256) {
                $proofState.Entries = @($proofState.Entries | Select-Object -Last 256)
            }
            $proofState.Revision = [long]$proofState.Revision + 1
            Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $StateProvider -Operation CommitWakeProof -State $proofState
            $AuditSession.OperatorLocalStateMutationCount =
            [long]$AuditSession.OperatorLocalStateMutationCount + 1
            $AuditSession.PersistentChangeObserved = $true
            $proofLocalMutationCount++
            $proofMatches = @($proofState.Entries | Where-Object {
                    $_.MessageId -ceq $WakeEvent.MessageId
                })
        }
        if ($proofMatches.Count -ne 1 -or $proofMatches[0].Status -cne 'PENDING') {
            throw 'REALTIME_WAKE_PROOF_MISSING'
        }
        $remaining = $AuthorizationExpiresAtUtc -
        (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)
        if ($remaining.TotalSeconds -le ([int]$WakeProvider.CodexMaximumRuntimeSeconds + 5)) {
            throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        }
        $AuditSession.OperatorCodexProcessSpawnCount =
        [long]$AuditSession.OperatorCodexProcessSpawnCount + 1
        $processSpawnCount = 1L
        [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                -RelayContext $RelayContext -Lane $WakeEvent.Lane `
                -RuntimeAssertion $RuntimeAssertion)
        $resume = Invoke-CddsiRealtimeRelayFixedCodexResumeProcessInternal `
            -WakeProvider $WakeProvider -ClockProvider $ClockProvider `
            -AuthorizationExpiresAtUtc $AuthorizationExpiresAtUtc
        if ($null -eq $resume -or -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                -InputObject $resume -Expected @(
                    'Started', 'Completed', 'ExitCode', 'TimedOut', 'JobAssigned',
                    'ProcessTreeTerminated', 'EnvironmentInheritedCount', 'OutputDiscarded'
                )) -or
            $resume.Started -isnot [bool] -or $resume.Completed -isnot [bool] -or
            $resume.TimedOut -isnot [bool] -or
            $resume.JobAssigned -isnot [bool] -or
            $resume.ProcessTreeTerminated -isnot [bool] -or
            $resume.OutputDiscarded -isnot [bool] -or
            ($resume.ExitCode -isnot [int] -and $resume.ExitCode -isnot [long]) -or
            ($resume.EnvironmentInheritedCount -isnot [int] -and
                $resume.EnvironmentInheritedCount -isnot [long]) -or
            -not $resume.Started -or -not $resume.Completed -or $resume.TimedOut -or
            -not $resume.JobAssigned -or $resume.ProcessTreeTerminated -or
            -not $resume.OutputDiscarded -or
            [long]$resume.EnvironmentInheritedCount -ne 0 -or
            [long]$resume.ExitCode -ne 0) {
            throw 'REALTIME_FIXED_WAKE_REJECTED'
        }
        $AuditSession.FixedWakeEffectCount = [long]$AuditSession.FixedWakeEffectCount + 1
        $AuditSession.PersistentChangeObserved = $true
        [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                -RelayContext $RelayContext -Lane $WakeEvent.Lane `
                -RuntimeAssertion $RuntimeAssertion)
        if ([long]$proofState.Revision -ge $script:CddsiRealtimeMaxSafeInteger) {
            throw 'REALTIME_WAKE_PROOF_INVALID'
        }
        $proofMatches[0].Status = 'SUCCEEDED'
        $proofState.Revision = [long]$proofState.Revision + 1
        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
            -StateProvider $StateProvider -Operation CommitWakeProof -State $proofState
        $AuditSession.OperatorLocalStateMutationCount =
        [long]$AuditSession.OperatorLocalStateMutationCount + 1
        $proofLocalMutationCount++
        $fixedEntryInvoked = $true
    }
    return [pscustomobject][ordered]@{
        FixedEntryInvoked = $fixedEntryInvoked
        PreviouslyInvoked = $previouslyInvoked
        Consumed = $true
        RepositoryIdentityVerified = $true
        PayloadSha256Verified = $true
        GitInvocationCount = [long]$result.GitInvocationCount
        OperatorGitTransportCount = [long]$result.OperatorGitTransportCount
        OperatorLocalStateMutationCount = [long]$result.LocalStateMutationCount +
        $proofLocalMutationCount
        OperatorCodexProcessSpawnCount = $processSpawnCount
        FixedWakeEffectCount = $(if ($fixedEntryInvoked) { 1L } else { 0L })
    }
}

function Invoke-CddsiRealtimeRelayWatcher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$RelayExecutionContext,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$RuntimeAssertion,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [ValidateRange(1, 32)][int]$MaxReconnectAttempts = 5,
        [ValidateRange(1, 256)][int]$MaxMessages = 64
    )

    $processedCount = 0
    $duplicateCount = 0
    $ackCount = 0
    $reconnectCount = 0
    $observedFrameCount = 0
    $operatorRelayNetworkRequestCount = 0L
    $operatorGitInvocationCount = 0L
    $operatorGitTransportCount = 0L
    $operatorLocalStateMutationCount = 0L
    $operatorCodexProcessSpawnCount = 0L
    $fixedWakeEffectCount = 0L
    $persistentChangeObserved = $false
    $trustedLiveSessionId = $null
    $maximumObservedFrames = [Math]::Min(1024, ($MaxMessages * 4) + $MaxReconnectAttempts)
    $lockHandle = $null
    $lifecycleLockHandle = $null
    $liveAssertionExpiresAt = [DateTimeOffset]::MaxValue
    try {
        if ($Mode -ceq 'Live') {
            $trustedLiveSessionId = Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
                -RelayContext $RelayExecutionContext
        }
        Assert-CddsiRealtimeRelayContextInternal -RelayContext $RelayExecutionContext -Mode $Mode `
            -Lane $Lane -RuntimeAssertion $RuntimeAssertion
        if ($Mode -ceq 'Live' -and -not (Test-CddsiRealtimeRelayUtcSecondInternal `
                -Value $RuntimeAssertion.ExpiresAtUtc -Parsed ([ref]$liveAssertionExpiresAt))) {
            throw 'REALTIME_RUNTIME_ASSERTION_INVALID'
        }
        $providers = $RelayExecutionContext.Providers
        if ($Mode -ceq 'Live') {
            $trustedLiveSessionId = [string]$providers.Transport.SessionId
        }
        $rootResult = if ($Mode -ceq 'Live') {
            [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                    -RelayContext $RelayExecutionContext -Lane $Lane `
                    -RuntimeAssertion $RuntimeAssertion)
            Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $providers.State -Operation ValidateRoot
        }
        else {
            & $providers.State.ValidateRoot
        }
        if ($null -eq $rootResult -or -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                -InputObject $rootResult -Expected @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created'))) {
            throw 'REALTIME_STATE_ROOT_RESULT_INVALID'
        }
        foreach ($booleanName in @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created')) {
            if ($rootResult.$booleanName -isnot [bool]) {
                throw 'REALTIME_STATE_ROOT_RESULT_INVALID'
            }
        }
        if (-not $rootResult.Valid -or -not $rootResult.OwnerMarked -or
            -not $rootResult.AclProtected -or -not $rootResult.NoReparse) {
            throw 'REALTIME_STATE_ROOT_INVALID'
        }
        if ($Mode -ceq 'Live' -and $rootResult.Created) {
            $sessionForRoot = Get-CddsiRealtimeRelayLiveSessionInternal `
                -TransportProvider $providers.Transport
            $sessionForRoot.PersistentChangeObserved = $true
            $sessionForRoot.OperatorLocalStateMutationCount =
            [long]$sessionForRoot.OperatorLocalStateMutationCount + 1
        }
        if ($Mode -ceq 'Live') {
            [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                    -RelayContext $RelayExecutionContext -Lane $Lane `
                    -RuntimeAssertion $RuntimeAssertion)
            $lifecycleLockHandle = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $providers.State -Operation AcquireLifecycleLock
            try {
                $postLifecycleRoot = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $providers.State -Operation ValidateRoot
                if ($null -eq $postLifecycleRoot -or
                    -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                        -InputObject $postLifecycleRoot `
                        -Expected @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created')) -or
                    $postLifecycleRoot.Valid -isnot [bool] -or
                    -not $postLifecycleRoot.Valid -or $postLifecycleRoot.Created) {
                    throw 'REALTIME_STATE_ROOT_INVALID'
                }
                $lockHandle = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $providers.State -Operation AcquireLock
            }
            finally {
                if ($null -ne $lifecycleLockHandle) {
                    $lifecycleLockHandle.Dispose()
                    $lifecycleLockHandle = $null
                }
            }
        }
        else {
            $lockHandle = & $providers.State.AcquireLock
        }
        if ($null -eq $lockHandle) {
            throw 'REALTIME_SINGLE_INSTANCE_LOCK_FAILED'
        }
        $state = if ($Mode -ceq 'Live') {
            [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                    -RelayContext $RelayExecutionContext -Lane $Lane `
                    -RuntimeAssertion $RuntimeAssertion)
            Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $providers.State -Operation Load -Lane $Lane
        }
        else {
            & $providers.State.Load $Lane
        }
        if ($null -eq $state) {
            $state = New-CddsiRealtimeRelayInitialStateInternal -Lane $Lane
        }
        if (-not (Test-CddsiRealtimeRelayStateInternal -State $state -Lane $Lane)) {
            throw 'REALTIME_STATE_INVALID'
        }
        $receiveFailureCount = 0
        $ackFailureCount = 0
        while ($processedCount -lt $MaxMessages -or
            [long]$state.LastAckedSequence -lt [long]$state.LastConsumedSequence) {
            $ackFailed = $false
            if ($Mode -ceq 'Live') {
                [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                        -RelayContext $RelayExecutionContext -Lane $Lane `
                        -RuntimeAssertion $RuntimeAssertion)
            }
            if ($Mode -ceq 'Live') {
                try {
                    $receive = Invoke-CddsiRealtimeRelayLiveTransportReceiveInternal `
                        -TransportProvider $providers.Transport `
                        -CredentialProvider $providers.Credential `
                        -ClockProvider $providers.Clock -Lane $Lane `
                        -After ([long]$state.LastAckedSequence) `
                        -MaxMessages $MaxMessages `
                        -AuthorizationExpiresAtUtc $liveAssertionExpiresAt
                }
                finally {
                    $operatorRelayNetworkRequestCount =
                    Get-CddsiRealtimeRelayOperatorNetworkRequestCountBySessionIdInternal `
                        -SessionId $trustedLiveSessionId
                }
            }
            else {
                $receive = & $providers.Transport.Receive $Lane ([long]$state.LastAckedSequence) `
                    $MaxMessages $liveAssertionExpiresAt
            }
            if ($null -eq $receive -or
                (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $receive `
                        -Expected @('Status', 'Messages')) -and
                    -not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $receive `
                        -Expected @('Status', 'Messages', 'Code'))) -or
                $receive.Status -isnot [string] -or
                $receive.Messages -isnot [Array] -or
                @('Connected', 'Disconnected', 'Stopped') -cnotcontains $receive.Status) {
                throw 'REALTIME_TRANSPORT_RESULT_INVALID'
            }
            foreach ($transportMessage in @($receive.Messages)) {
                if ($transportMessage -isnot [string]) {
                    throw 'REALTIME_TRANSPORT_MESSAGE_INVALID'
                }
            }
            if ($receive.Status -ceq 'Stopped') {
                if ([long]$state.LastAckedSequence -lt [long]$state.LastConsumedSequence) {
                    throw 'REALTIME_ACK_PENDING_NOT_REPLAYED'
                }
                break
            }
            if ($receive.Status -ceq 'Disconnected') {
                $reconnectCount++
                $receiveFailureCount++
                if ($receiveFailureCount -ge $MaxReconnectAttempts) {
                    throw 'REALTIME_RECONNECT_EXHAUSTED'
                }
                $baseDelay = [Math]::Min(30000, [Math]::Pow(2, $receiveFailureCount - 1) * 1000)
                $jitter = if ($Mode -ceq 'Live') {
                    Get-CddsiRealtimeRelayLiveJitterMillisecondsInternal `
                        -ClockProvider $providers.Clock -Maximum 250
                }
                else {
                    & $providers.Clock.GetJitterMilliseconds 250
                }
                if ($jitter -isnot [int] -or $jitter -lt 0 -or $jitter -gt 250) {
                    throw 'REALTIME_JITTER_INVALID'
                }
                if ($Mode -ceq 'Live') {
                    Invoke-CddsiRealtimeRelayLiveDelayInternal -ClockProvider $providers.Clock `
                        -Milliseconds ([int]$baseDelay + $jitter)
                }
                else {
                    & $providers.Clock.Delay ([int]$baseDelay + $jitter)
                }
                continue
            }
            $receiveFailureCount = 0
            foreach ($rawMessage in @($receive.Messages)) {
                if ($processedCount -ge $MaxMessages -and
                    [long]$state.LastAckedSequence -ge [long]$state.LastConsumedSequence) {
                    break
                }
                $observedFrameCount++
                if ($observedFrameCount -gt $maximumObservedFrames) {
                    throw 'REALTIME_DELIVERY_LIMIT_EXCEEDED'
                }
                $now = if ($Mode -ceq 'Live') {
                    Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $providers.Clock
                }
                else {
                    & $providers.Clock.GetUtcNow
                }
                $validation = Test-CddsiRealtimeRelayNotificationInternal `
                    -RawMessage ([string]$rawMessage) -NowUtc $now
                if (-not $validation.Valid -and @(
                        'CREATED_AT_OUTSIDE_WINDOW', 'MESSAGE_EXPIRED'
                    ) -ccontains $validation.Code) {
                    $storedReplay = Test-CddsiRealtimeRelayNotificationInternal `
                        -RawMessage ([string]$rawMessage) -NowUtc $now `
                        -ValidationMode StoredConsumedReplay
                    if ($storedReplay.Valid) {
                        $storedMatches = @($state.ProcessedMessages | Where-Object {
                                [long]$_.Sequence -eq [long]$storedReplay.Message.Sequence -and
                                $_.MessageId -ceq $storedReplay.Message.MessageId -and
                                $_.MessageSha256 -ceq $storedReplay.MessageSha256 -and
                                $_.PayloadSha256 -ceq $storedReplay.Message.PayloadSha256
                            })
                        if ($storedMatches.Count -eq 1) {
                            $validation = $storedReplay
                        }
                    }
                }
                if (-not $validation.Valid) {
                    throw 'REALTIME_NOTIFICATION_INVALID'
                }
                $message = $validation.Message
                if ($message.Lane -cne $Lane) {
                    throw 'REALTIME_WRONG_LANE'
                }
                $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
                if ($RuntimeAssertion.ClientId -cne $policy.ReaderClientId) {
                    throw 'REALTIME_READER_IDENTITY_MISMATCH'
                }
                $existing = @($state.ProcessedMessages | Where-Object {
                        [long]$_.Sequence -eq [long]$message.Sequence
                    })
                $existingMessageId = @($state.ProcessedMessages | Where-Object {
                        $_.MessageId -ceq $message.MessageId
                    })
                if ($existingMessageId.Count -gt 1 -or
                    ($existingMessageId.Count -eq 1 -and
                        [long]$existingMessageId[0].Sequence -ne [long]$message.Sequence)) {
                    throw 'REALTIME_MESSAGE_ID_REPLAY'
                }
                if ($existing.Count -eq 1) {
                    if ($existing[0].MessageId -cne $message.MessageId -or
                        $existing[0].MessageSha256 -cne $validation.MessageSha256 -or
                        $existing[0].PayloadSha256 -cne $message.PayloadSha256) {
                        throw 'REALTIME_DUPLICATE_DRIFT'
                    }
                    $duplicateCount++
                }
                elseif ($existing.Count -gt 1) {
                    throw 'REALTIME_STATE_DUPLICATE_SEQUENCE'
                }
                else {
                    if ([long]$message.Sequence -ne ([long]$state.LastConsumedSequence + 1)) {
                        throw 'REALTIME_SEQUENCE_GAP'
                    }
                    $expectedPrevious = if ([long]$state.LastConsumedSequence -eq 0) { $null } else { $state.LastMessageSha256 }
                    if ($message.PreviousSha256 -cne $expectedPrevious) {
                        throw 'REALTIME_PREVIOUS_HASH_MISMATCH'
                    }
                    $wakeEvent = [pscustomobject][ordered]@{
                        SchemaVersion = 'cddsi-realtime-relay-wake-event-v1'
                        Verb = 'CONTROL_REPO_POINTER_AVAILABLE'
                        Lane = $message.Lane
                        MessageId = $message.MessageId
                        Sequence = [long]$message.Sequence
                        RepositoryId = $message.RepositoryId
                        Ref = $message.Ref
                        Commit = $message.Commit
                        PayloadSha256 = $message.PayloadSha256
                    }
                    $wake = if ($Mode -ceq 'Live') {
                        [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                                -RelayContext $RelayExecutionContext -Lane $Lane `
                                -RuntimeAssertion $RuntimeAssertion)
                        Invoke-CddsiRealtimeRelayFixedGitOutboxWakeInternal `
                            -WakeProvider $providers.Wake -WakeEvent $wakeEvent `
                            -StateProvider $providers.State `
                            -AuditSession (Get-CddsiRealtimeRelayLiveSessionInternal `
                                -TransportProvider $providers.Transport) `
                            -ClockProvider $providers.Clock `
                            -RelayContext $RelayExecutionContext `
                            -RuntimeAssertion $RuntimeAssertion `
                            -AuthorizationExpiresAtUtc $liveAssertionExpiresAt
                    }
                    else {
                        & $providers.Wake.InvokeFixed $wakeEvent
                    }
                    if ($null -eq $wake -or -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                            -InputObject $wake -Expected @(
                                'FixedEntryInvoked', 'PreviouslyInvoked', 'Consumed',
                                'RepositoryIdentityVerified', 'PayloadSha256Verified',
                                'GitInvocationCount', 'OperatorGitTransportCount',
                                'OperatorLocalStateMutationCount',
                                'OperatorCodexProcessSpawnCount', 'FixedWakeEffectCount'
                            ))) {
                        throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
                    }
                    foreach ($wakeBoolean in @(
                            'FixedEntryInvoked', 'PreviouslyInvoked', 'Consumed',
                            'RepositoryIdentityVerified', 'PayloadSha256Verified'
                        )) {
                        if ($wake.$wakeBoolean -isnot [bool]) {
                            throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
                        }
                    }
                    foreach ($wakeMetric in @(
                            'GitInvocationCount', 'OperatorGitTransportCount',
                            'OperatorLocalStateMutationCount',
                            'OperatorCodexProcessSpawnCount', 'FixedWakeEffectCount'
                        )) {
                        if (($wake.$wakeMetric -isnot [int] -and $wake.$wakeMetric -isnot [long]) -or
                            [long]$wake.$wakeMetric -lt 0) {
                            throw 'REALTIME_FIXED_WAKE_RESULT_INVALID'
                        }
                    }
                    if ($wake.FixedEntryInvoked -eq $wake.PreviouslyInvoked -or
                        -not $wake.Consumed -or
                        -not $wake.RepositoryIdentityVerified -or -not $wake.PayloadSha256Verified) {
                        throw 'REALTIME_FIXED_WAKE_REJECTED'
                    }
                    $state.ProcessedMessages = @($state.ProcessedMessages) + @(
                        [pscustomobject][ordered]@{
                            MessageId = $message.MessageId
                            Sequence = [long]$message.Sequence
                            MessageSha256 = $validation.MessageSha256
                            PayloadSha256 = $message.PayloadSha256
                        }
                    )
                    if (@($state.ProcessedMessages).Count -gt 256) {
                        $state.ProcessedMessages = @($state.ProcessedMessages | Select-Object -Last 256)
                    }
                    $state.LastConsumedSequence = [long]$message.Sequence
                    $state.LastMessageSha256 = $validation.MessageSha256
                    if ([long]$state.Revision -ge $script:CddsiRealtimeMaxSafeInteger) {
                        throw 'REALTIME_STATE_REVISION_EXHAUSTED'
                    }
                    $state.Revision = [long]$state.Revision + 1
                    if ($Mode -ceq 'Live') {
                        [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                                -RelayContext $RelayExecutionContext -Lane $Lane `
                                -RuntimeAssertion $RuntimeAssertion)
                        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                            -StateProvider $providers.State -Operation CommitAtomically -State $state
                        $stateSession = Get-CddsiRealtimeRelayLiveSessionInternal `
                            -TransportProvider $providers.Transport
                        $stateSession.PersistentChangeObserved = $true
                        $stateSession.OperatorLocalStateMutationCount =
                        [long]$stateSession.OperatorLocalStateMutationCount + 1
                    }
                    else {
                        & $providers.State.CommitAtomically $state
                    }
                    $processedCount++
                }
                if ($Mode -ceq 'Live') {
                    [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                            -RelayContext $RelayExecutionContext -Lane $Lane `
                            -RuntimeAssertion $RuntimeAssertion)
                }
                $ackNow = if ($Mode -ceq 'Live') {
                    Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $providers.Clock
                }
                else {
                    & $providers.Clock.GetUtcNow
                }
                $ack = [pscustomobject][ordered]@{
                    Schema = $script:CddsiRealtimeAckSchema
                    Lane = $message.Lane
                    MessageId = $message.MessageId
                    Sequence = [long]$message.Sequence
                    PayloadSha256 = $message.PayloadSha256
                    AckStatus = 'CONSUMED'
                    AckedAt = $ackNow.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
                    SenderRole = $policy.ReaderRole
                }
                $ackBody = ConvertTo-CddsiRealtimeRelayCanonicalAckInternal -Ack $ack
                if ($Mode -ceq 'Live') {
                    [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                            -RelayContext $RelayExecutionContext -Lane $Lane `
                            -RuntimeAssertion $RuntimeAssertion)
                    try {
                        $ackResult = Invoke-CddsiRealtimeRelayLiveTransportAckInternal `
                            -TransportProvider $providers.Transport `
                            -CredentialProvider $providers.Credential `
                            -ClockProvider $providers.Clock -Body $ackBody `
                            -AuthorizationExpiresAtUtc $liveAssertionExpiresAt
                    }
                    finally {
                        $operatorRelayNetworkRequestCount =
                        Get-CddsiRealtimeRelayOperatorNetworkRequestCountBySessionIdInternal `
                            -SessionId $trustedLiveSessionId
                    }
                }
                else {
                    $ackResult = & $providers.Transport.Ack $ackBody
                }
                if ($null -eq $ackResult -or -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                        -InputObject $ackResult -Expected @('Accepted')) -or
                    $ackResult.Accepted -isnot [bool]) {
                    throw 'REALTIME_ACK_RESULT_INVALID'
                }
                if (-not $ackResult.Accepted) {
                    $reconnectCount++
                    $ackFailureCount++
                    $ackFailed = $true
                    break
                }
                $ackFailureCount = 0
                if ([long]$message.Sequence -gt [long]$state.LastAckedSequence) {
                    $state.LastAckedSequence = [long]$message.Sequence
                    if ([long]$state.Revision -ge $script:CddsiRealtimeMaxSafeInteger) {
                        throw 'REALTIME_STATE_REVISION_EXHAUSTED'
                    }
                    $state.Revision = [long]$state.Revision + 1
                    if ($Mode -ceq 'Live') {
                        [void](Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal `
                                -RelayContext $RelayExecutionContext -Lane $Lane `
                                -RuntimeAssertion $RuntimeAssertion)
                        Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                            -StateProvider $providers.State -Operation CommitAtomically -State $state
                        $ackStateSession = Get-CddsiRealtimeRelayLiveSessionInternal `
                            -TransportProvider $providers.Transport
                        $ackStateSession.PersistentChangeObserved = $true
                        $ackStateSession.OperatorLocalStateMutationCount =
                        [long]$ackStateSession.OperatorLocalStateMutationCount + 1
                    }
                    else {
                        & $providers.State.CommitAtomically $state
                    }
                }
                $ackCount++
            }
            if ($ackFailed) {
                if ($ackFailureCount -ge $MaxReconnectAttempts) {
                    throw 'REALTIME_ACK_RETRY_EXHAUSTED'
                }
                $baseDelay = [Math]::Min(30000, [Math]::Pow(2, $ackFailureCount - 1) * 1000)
                $jitter = if ($Mode -ceq 'Live') {
                    Get-CddsiRealtimeRelayLiveJitterMillisecondsInternal `
                        -ClockProvider $providers.Clock -Maximum 250
                }
                else {
                    & $providers.Clock.GetJitterMilliseconds 250
                }
                if ($jitter -isnot [int] -or $jitter -lt 0 -or $jitter -gt 250) {
                    throw 'REALTIME_JITTER_INVALID'
                }
                if ($Mode -ceq 'Live') {
                    Invoke-CddsiRealtimeRelayLiveDelayInternal -ClockProvider $providers.Clock `
                        -Milliseconds ([int]$baseDelay + $jitter)
                }
                else {
                    & $providers.Clock.Delay ([int]$baseDelay + $jitter)
                }
                continue
            }
            if (@($receive.Messages).Count -eq 0) {
                if ([long]$state.LastAckedSequence -lt [long]$state.LastConsumedSequence) {
                    throw 'REALTIME_ACK_PENDING_NOT_REPLAYED'
                }
                if ($null -ne $receive.PSObject.Properties['Code'] -and
                    $receive.Code -ceq 'REALTIME_WEBSOCKET_IDLE') {
                    continue
                }
                break
            }
        }
        if ($Mode -ceq 'Live' -and -not [string]::IsNullOrEmpty($trustedLiveSessionId)) {
            $audit = Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal `
                -SessionId $trustedLiveSessionId
            $operatorRelayNetworkRequestCount = $audit.OperatorRelayNetworkRequestCount
            $operatorGitInvocationCount = $audit.OperatorGitInvocationCount
            $operatorGitTransportCount = $audit.OperatorGitTransportCount
            $operatorLocalStateMutationCount = $audit.OperatorLocalStateMutationCount
            $operatorCodexProcessSpawnCount = $audit.OperatorCodexProcessSpawnCount
            $fixedWakeEffectCount = $audit.FixedWakeEffectCount
            $persistentChangeObserved = $audit.PersistentChangeObserved
        }
        return [pscustomobject][ordered]@{
            Status = 'SUCCEEDED'
            Code = 'REALTIME_WATCH_COMPLETE'
            Mode = $Mode
            Changed = ($Mode -ceq 'Live' -and $persistentChangeObserved)
            ProcessedCount = $processedCount
            DuplicateCount = $duplicateCount
            AckCount = $ackCount
            ReconnectCount = $reconnectCount
            LastConsumedSequence = [long]$state.LastConsumedSequence
            LastAckedSequence = [long]$state.LastAckedSequence
            ProductLiveAttemptCount = 0
            RealRegistryAccessCount = 0
            ProductNetworkRequestCount = 0
            OperatorRelayNetworkRequestCount = $operatorRelayNetworkRequestCount
            OperatorGitInvocationCount = $operatorGitInvocationCount
            OperatorGitTransportCount = $operatorGitTransportCount
            OperatorLocalStateMutationCount = $operatorLocalStateMutationCount
            OperatorCodexProcessSpawnCount = $operatorCodexProcessSpawnCount
            FixedWakeEffectCount = $fixedWakeEffectCount
            RealNetworkAccessCount = 0
            RealCredentialManagerAccessCount = 0
            ProductProcessSpawnCount = 0
            OutsideOwnedStateWriteCount = 0
            UnexpectedLedgerEntryCount = 0
            MutationSpyCount = 0
        }
    }
    catch {
        if ($Mode -ceq 'Live' -and -not [string]::IsNullOrEmpty($trustedLiveSessionId)) {
            $audit = Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal `
                -SessionId $trustedLiveSessionId
            $operatorRelayNetworkRequestCount = $audit.OperatorRelayNetworkRequestCount
            $operatorGitInvocationCount = $audit.OperatorGitInvocationCount
            $operatorGitTransportCount = $audit.OperatorGitTransportCount
            $operatorLocalStateMutationCount = $audit.OperatorLocalStateMutationCount
            $operatorCodexProcessSpawnCount = $audit.OperatorCodexProcessSpawnCount
            $fixedWakeEffectCount = $audit.FixedWakeEffectCount
            $persistentChangeObserved = $audit.PersistentChangeObserved
        }
        $code = [string]$_.Exception.Message
        if ($script:CddsiRealtimeWatcherResultCodes -cnotcontains $code) {
            $code = 'REALTIME_WATCH_BLOCKED'
        }
        return [pscustomobject][ordered]@{
            Status = 'BLOCKED'
            Code = $code
            Mode = $Mode
            Changed = ($Mode -ceq 'Live' -and $persistentChangeObserved)
            ProcessedCount = $processedCount
            DuplicateCount = $duplicateCount
            AckCount = $ackCount
            ReconnectCount = $reconnectCount
            LastConsumedSequence = $null
            LastAckedSequence = $null
            ProductLiveAttemptCount = 0
            RealRegistryAccessCount = 0
            ProductNetworkRequestCount = 0
            OperatorRelayNetworkRequestCount = $operatorRelayNetworkRequestCount
            OperatorGitInvocationCount = $operatorGitInvocationCount
            OperatorGitTransportCount = $operatorGitTransportCount
            OperatorLocalStateMutationCount = $operatorLocalStateMutationCount
            OperatorCodexProcessSpawnCount = $operatorCodexProcessSpawnCount
            FixedWakeEffectCount = $fixedWakeEffectCount
            RealNetworkAccessCount = 0
            RealCredentialManagerAccessCount = 0
            ProductProcessSpawnCount = 0
            OutsideOwnedStateWriteCount = 0
            UnexpectedLedgerEntryCount = 0
            MutationSpyCount = 0
        }
    }
    finally {
        try {
            if ($Mode -ceq 'Live') {
                if (-not [string]::IsNullOrEmpty($trustedLiveSessionId)) {
                    Close-CddsiRealtimeRelayTrustedLiveSessionInternal `
                        -TrustedSessionId $trustedLiveSessionId
                }
            }
            elseif ($null -ne $RelayExecutionContext -and $null -ne $RelayExecutionContext.PSObject -and
                $null -ne $RelayExecutionContext.PSObject.Properties['Providers'] -and
                $null -ne $RelayExecutionContext.Providers -and
                $null -ne $RelayExecutionContext.Providers.PSObject.Properties['Transport'] -and
                $null -ne $RelayExecutionContext.Providers.Transport -and
                $null -ne $RelayExecutionContext.Providers.Transport.PSObject.Properties['Close']) {
                & $RelayExecutionContext.Providers.Transport.Close
            }
        }
        catch {
            # Cleanup failures are deliberately not allowed to disclose provider exception text.
        }
        try {
            if ($null -ne $lifecycleLockHandle -and $Mode -ceq 'Live') {
                $lifecycleLockHandle.Dispose()
            }
        }
        catch {
            # Lifecycle lock release remains best-effort and does not read caller data.
        }
        try {
            if ($null -ne $lockHandle -and $null -ne $RelayExecutionContext -and
                $null -ne $RelayExecutionContext.PSObject -and
                $null -ne $RelayExecutionContext.PSObject.Properties['Providers'] -and
                $null -ne $RelayExecutionContext.Providers -and
                $null -ne $RelayExecutionContext.Providers.PSObject.Properties['State'] -and
                $null -ne $RelayExecutionContext.Providers.State) {
                if ($Mode -ceq 'Live') {
                    $lockHandle.Dispose()
                }
                else {
                    & $RelayExecutionContext.Providers.State.ReleaseLock $lockHandle
                }
            }
        }
        catch {
            # Lock release remains best-effort and exception text is never returned or logged.
        }
    }
}

function Get-CddsiRealtimeRelayRandomNonceInternal {
    $bytes = [byte[]]::new(32)
    $generator = [Security.Cryptography.RandomNumberGenerator]::Create()
    try {
        $generator.GetBytes($bytes)
        return [Convert]::ToBase64String($bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
        $generator.Dispose()
    }
}

function Test-CddsiRealtimeRelayNoReparsePathInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $current = [IO.DirectoryInfo]::new($fullPath)
        while ($null -ne $current) {
            if ($current.Exists -and (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
                return $false
            }
            $current = $current.Parent
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-CddsiRealtimeRelayStateBindingTokenInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    $fullPath = [IO.Path]::GetFullPath($StateRoot).TrimEnd([IO.Path]::DirectorySeparatorChar)
    return Get-CddsiRealtimeRelayTextSha256Internal -Text (
        'cddsi-realtime-relay-state-root-v1|{0}|{1}|{2}' -f $fullPath, $OwnerSid, $OwnershipTokenSha256
    )
}

function Get-CddsiRealtimeRelayOwnerMarkerTextInternal {
    param(
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    return ConvertTo-Json -Compress -InputObject ([ordered]@{
            SchemaVersion = 'cddsi-realtime-relay-owner-v1'
            RunId = $RunId
            OwnerSid = $OwnerSid
            OwnershipTokenSha256 = $OwnershipTokenSha256
        })
}

function Set-CddsiRealtimeRelayProtectedDirectoryAclInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$OwnerSid
    )

    $owner = [Security.Principal.SecurityIdentifier]::new($OwnerSid)
    $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $security = [Security.AccessControl.DirectorySecurity]::new()
    $security.SetOwner($owner)
    $security.SetAccessRuleProtection($true, $false)
    $inheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
        [Security.AccessControl.InheritanceFlags]::ObjectInherit
    foreach ($sid in @($owner, $system)) {
        $rule = [Security.AccessControl.FileSystemAccessRule]::new(
            $sid,
            [Security.AccessControl.FileSystemRights]::FullControl,
            $inheritance,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow
        )
        [void]$security.AddAccessRule($rule)
    }
    $directory = [IO.DirectoryInfo]::new($StateRoot)
    $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
    if ($null -ne $aclExtensions) {
        [IO.FileSystemAclExtensions]::SetAccessControl($directory, $security)
    }
    else {
        $directory.SetAccessControl($security)
    }
}

function Test-CddsiRealtimeRelayProtectedDirectoryAclInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$OwnerSid
    )

    try {
        $owner = [Security.Principal.SecurityIdentifier]::new($OwnerSid)
        $system = [Security.Principal.SecurityIdentifier]::new('S-1-5-18')
        $directory = [IO.DirectoryInfo]::new($StateRoot)
        $sections = [Security.AccessControl.AccessControlSections]::Owner -bor `
            [Security.AccessControl.AccessControlSections]::Access
        $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
        if ($null -ne $aclExtensions) {
            $security = [IO.FileSystemAclExtensions]::GetAccessControl($directory, $sections)
        }
        else {
            $security = $directory.GetAccessControl($sections)
        }
        if (-not $security.AreAccessRulesProtected -or
            $security.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne $owner.Value) {
            return $false
        }
        $rules = @($security.GetAccessRules(
                $true,
                $false,
                [Security.Principal.SecurityIdentifier]
            ))
        if ($rules.Count -ne 2) {
            return $false
        }
        $expectedSids = @($owner.Value, $system.Value) | Sort-Object -CaseSensitive
        $actualSids = @($rules | ForEach-Object { $_.IdentityReference.Value } | Sort-Object -CaseSensitive)
        if (($expectedSids -join "`n") -cne ($actualSids -join "`n")) {
            return $false
        }
        $expectedInheritance = [Security.AccessControl.InheritanceFlags]::ContainerInherit -bor `
            [Security.AccessControl.InheritanceFlags]::ObjectInherit
        foreach ($rule in $rules) {
            if ($rule.IsInherited -or
                $rule.AccessControlType -ne [Security.AccessControl.AccessControlType]::Allow -or
                $rule.FileSystemRights -ne [Security.AccessControl.FileSystemRights]::FullControl -or
                $rule.InheritanceFlags -ne $expectedInheritance -or
                $rule.PropagationFlags -ne [Security.AccessControl.PropagationFlags]::None) {
                return $false
            }
        }
        return $true
    }
    catch {
        return $false
    }
}

function Assert-CddsiRealtimeRelayOwnedStateRootExistingInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        $OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or $OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'REALTIME_STATE_BINDING_INVALID'
    }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($OwnerSid -cne $currentSid) {
        throw 'REALTIME_STATE_OWNER_NOT_CURRENT_USER'
    }
    $fullPath = [IO.Path]::GetFullPath($StateRoot)
    if (-not [IO.Path]::IsPathRooted($fullPath) -or
        [IO.DirectoryInfo]::new($fullPath).Name -cne ('cddsi-realtime-relay-' + $RunId) -or
        -not [IO.Directory]::Exists($fullPath) -or
        -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullPath) -or
        -not (Test-CddsiRealtimeRelayProtectedDirectoryAclInternal -StateRoot $fullPath -OwnerSid $OwnerSid) -or
        [IO.File]::Exists([IO.Path]::Combine($fullPath, '.cleanup-tombstone.json'))) {
        throw 'REALTIME_STATE_ROOT_INVALID'
    }
    $markerBytes = Read-CddsiRealtimeRelayBoundedFileInternal `
        -Path ([IO.Path]::Combine($fullPath, '.cddsi-owner.json')) -MaximumBytes 1024 `
        -FailureCode 'REALTIME_STATE_OWNER_MISMATCH'
    try {
        $actualMarker = [Text.UTF8Encoding]::new($false, $true).GetString($markerBytes)
        $expectedMarker = Get-CddsiRealtimeRelayOwnerMarkerTextInternal -RunId $RunId `
            -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
        if ($actualMarker -cne $expectedMarker) {
            throw 'REALTIME_STATE_OWNER_MISMATCH'
        }
    }
    finally {
        [Array]::Clear($markerBytes, 0, $markerBytes.Length)
    }
    return $fullPath
}

function Initialize-CddsiRealtimeRelayOwnedStateRootInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    try {
        if ($RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or $OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'REALTIME_STATE_BINDING_INVALID'
        }
        $fullPath = [IO.Path]::GetFullPath($StateRoot)
        $expectedLeaf = 'cddsi-realtime-relay-{0}' -f $RunId
        if ([IO.DirectoryInfo]::new($fullPath).Name -cne $expectedLeaf) {
            throw 'REALTIME_STATE_ROOT_NAME_INVALID'
        }
        if (-not [IO.Path]::IsPathRooted($fullPath) -or -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullPath)) {
            throw 'REALTIME_STATE_REPARSE_OR_PATH_INVALID'
        }
        $created = $false
        if (-not [IO.Directory]::Exists($fullPath)) {
            [void][IO.Directory]::CreateDirectory($fullPath)
            $created = $true
            Set-CddsiRealtimeRelayProtectedDirectoryAclInternal -StateRoot $fullPath -OwnerSid $OwnerSid
        }
        if (-not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullPath) -or
            -not (Test-CddsiRealtimeRelayProtectedDirectoryAclInternal -StateRoot $fullPath -OwnerSid $OwnerSid)) {
            throw 'REALTIME_STATE_ACL_INVALID'
        }
        if ([IO.File]::Exists([IO.Path]::Combine($fullPath, '.cleanup-tombstone.json'))) {
            throw 'REALTIME_STATE_ROOT_TOMBSTONED'
        }
        $markerPath = [IO.Path]::Combine($fullPath, '.cddsi-owner.json')
        if ([IO.File]::Exists($markerPath) -and
            (([IO.FileInfo]::new($markerPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
            throw 'REALTIME_STATE_MARKER_REPARSE'
        }
        $expectedMarker = Get-CddsiRealtimeRelayOwnerMarkerTextInternal -RunId $RunId -OwnerSid $OwnerSid `
            -OwnershipTokenSha256 $OwnershipTokenSha256
        if ([IO.File]::Exists($markerPath)) {
            $markerBytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $markerPath -MaximumBytes 1024 `
                -FailureCode 'REALTIME_STATE_OWNER_MISMATCH'
            try {
                $actualMarker = [Text.UTF8Encoding]::new($false, $true).GetString($markerBytes)
                if ($actualMarker -cne $expectedMarker) {
                    throw 'REALTIME_STATE_OWNER_MISMATCH'
                }
            }
            finally {
                [Array]::Clear($markerBytes, 0, $markerBytes.Length)
            }
        }
        else {
            $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($expectedMarker)
            $stream = [IO.FileStream]::new(
                $markerPath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None,
                4096,
                [IO.FileOptions]::WriteThrough
            )
            try {
                $stream.Write($bytes, 0, $bytes.Length)
                $stream.Flush($true)
            }
            finally {
                $stream.Dispose()
            }
        }
        return [pscustomobject][ordered]@{
            Valid = $true
            OwnerMarked = $true
            AclProtected = $true
            NoReparse = $true
            Created = $created
        }
    }
    catch {
        return [pscustomobject][ordered]@{
            Valid = $false
            OwnerMarked = $false
            AclProtected = $false
            NoReparse = $false
            Created = $false
        }
    }
}

function Test-CddsiRealtimeRelayStateFilePathSafeInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    try {
        $fullPath = [IO.Path]::GetFullPath($Path)
        $parentPath = [IO.Path]::GetDirectoryName($fullPath)
        if ([string]::IsNullOrWhiteSpace($parentPath) -or
            -not [IO.Directory]::Exists($parentPath)) {
            return $true
        }
        $matchingEntries = @(
            [IO.Directory]::EnumerateFileSystemEntries($parentPath) |
                Where-Object {
                    [IO.Path]::GetFullPath($_).Equals(
                        $fullPath, [StringComparison]::OrdinalIgnoreCase
                    )
                }
        )
        if ($matchingEntries.Count -eq 0) {
            return $true
        }
        if ($matchingEntries.Count -ne 1) {
            return $false
        }
        $attributes = [IO.File]::GetAttributes($matchingEntries[0])
        return (($attributes -band [IO.FileAttributes]::Directory) -eq 0) -and
        (($attributes -band [IO.FileAttributes]::ReparsePoint) -eq 0)
    }
    catch {
        return $false
    }
}

function Open-CddsiRealtimeRelayExclusiveLockFileInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$UnsafePathFailureCode
    )

    if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $Path)) {
        throw $UnsafePathFailureCode
    }
    if ([IO.File]::Exists($Path)) {
        return [IO.FileStream]::new(
            $Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None, 1, [IO.FileOptions]::WriteThrough
        )
    }
    try {
        return [IO.FileStream]::new(
            $Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None, 1, [IO.FileOptions]::WriteThrough
        )
    }
    catch [IO.IOException] {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $Path)) {
            throw $UnsafePathFailureCode
        }
        return [IO.FileStream]::new(
            $Path, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite,
            [IO.FileShare]::None, 1, [IO.FileOptions]::WriteThrough
        )
    }
}

function Read-CddsiRealtimeRelayStateFileInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $Path)) {
        throw 'REALTIME_STATE_FILE_REPARSE'
    }
    $bytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $Path `
        -MaximumBytes 131072 -FailureCode 'REALTIME_STATE_FILE_INVALID'
    try {
        try {
            $raw = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $state = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        }
        catch {
            throw 'REALTIME_STATE_JSON_INVALID'
        }
        if (-not (Test-CddsiRealtimeRelayStateInternal -State $state -Lane $Lane)) {
            throw 'REALTIME_STATE_INVALID'
        }
        if ((ConvertTo-Json -Compress -Depth 6 -InputObject $state) -cne $raw) {
            throw 'REALTIME_STATE_NON_CANONICAL'
        }
        return $state
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Read-CddsiRealtimeRelayStateInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    $statePath = [IO.Path]::Combine($StateRoot, 'watcher-state.json')
    $nextPath = [IO.Path]::Combine($StateRoot, 'watcher-state.next.json')
    $backupPath = [IO.Path]::Combine($StateRoot, $script:CddsiRealtimeStateBackupFileName)
    if (-not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $StateRoot)) {
        throw 'REALTIME_STATE_REPARSE_OR_PATH_INVALID'
    }
    foreach ($path in @($statePath, $nextPath, $backupPath)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $path)) {
            throw 'REALTIME_STATE_FILE_REPARSE'
        }
    }
    if ([IO.File]::Exists($backupPath)) {
        if ([IO.File]::Exists($statePath)) {
            [IO.File]::Delete($backupPath)
        }
        else {
            [void](Read-CddsiRealtimeRelayStateFileInternal -Path $backupPath -Lane $Lane)
            [IO.File]::Move($backupPath, $statePath)
        }
    }
    if (-not [IO.File]::Exists($statePath) -and [IO.File]::Exists($nextPath)) {
        $candidate = Read-CddsiRealtimeRelayStateFileInternal -Path $nextPath -Lane $Lane
        [IO.File]::Move($nextPath, $statePath)
        return $candidate
    }
    elseif ([IO.File]::Exists($statePath) -and [IO.File]::Exists($nextPath)) {
        [IO.File]::Delete($nextPath)
    }
    if (-not [IO.File]::Exists($statePath)) {
        return $null
    }
    return Read-CddsiRealtimeRelayStateFileInternal -Path $statePath -Lane $Lane
}

function Move-CddsiRealtimeRelayStateCandidateAtomicInternal {
    param(
        [Parameter(Mandatory = $true)][string]$NextPath,
        [Parameter(Mandatory = $true)][string]$StatePath,
        [Parameter(Mandatory = $true)][string]$BackupPath,
        [Parameter(Mandatory = $true)][bool]$ReplaceExisting
    )

    if ($ReplaceExisting) {
        [IO.File]::Replace($NextPath, $StatePath, $BackupPath, $true)
        try {
            if ([IO.File]::Exists($BackupPath) -and
                (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $BackupPath)) {
                [IO.File]::Delete($BackupPath)
            }
        }
        catch {
            # The backup is owner-only state; later exact-root cleanup removes it.
        }
        return
    }
    [IO.File]::Move($NextPath, $StatePath)
}

function Write-CddsiRealtimeRelayStateAtomicInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)]$State
    )

    if (-not (Test-CddsiRealtimeRelayStateInternal -State $State -Lane $State.Lane)) {
        throw 'REALTIME_STATE_INVALID'
    }
    $statePath = [IO.Path]::Combine($StateRoot, 'watcher-state.json')
    $nextPath = [IO.Path]::Combine($StateRoot, 'watcher-state.next.json')
    $backupPath = [IO.Path]::Combine($StateRoot, $script:CddsiRealtimeStateBackupFileName)
    if (-not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $StateRoot)) {
        throw 'REALTIME_STATE_REPARSE_OR_PATH_INVALID'
    }
    foreach ($path in @($statePath, $nextPath, $backupPath)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $path)) {
            throw 'REALTIME_STATE_FILE_REPARSE'
        }
    }
    if ([IO.File]::Exists($backupPath)) {
        throw 'REALTIME_STATE_BACKUP_EXISTS'
    }
    if ([IO.File]::Exists($nextPath)) {
        [IO.File]::Delete($nextPath)
    }
    $raw = ConvertTo-Json -Compress -Depth 6 -InputObject $State
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($raw)
    $stream = [IO.FileStream]::new(
        $nextPath,
        [IO.FileMode]::CreateNew,
        [IO.FileAccess]::Write,
        [IO.FileShare]::None,
        4096,
        [IO.FileOptions]::WriteThrough
    )
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
    }
    [void](Read-CddsiRealtimeRelayStateFileInternal -Path $nextPath -Lane $State.Lane)
    Move-CddsiRealtimeRelayStateCandidateAtomicInternal -NextPath $nextPath `
        -StatePath $statePath -BackupPath $backupPath `
        -ReplaceExisting ([IO.File]::Exists($statePath))
}

function Get-CddsiRealtimeRelayWakeProofPathsInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    $stem = 'wake-proof-' + $Lane
    return [pscustomobject][ordered]@{
        Current = [IO.Path]::Combine($StateRoot, $stem + '.json')
        Next = [IO.Path]::Combine($StateRoot, $stem + '.next.json')
        Backup = [IO.Path]::Combine($StateRoot, $stem + '.backup.json')
    }
}

function New-CddsiRealtimeRelayWakeProofStateInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeWakeProofSchema
        Lane = $Lane
        Entries = @()
        Revision = [long]0
    }
}

function Test-CddsiRealtimeRelayWakeProofStateInternal {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $State `
            -Expected $script:CddsiRealtimeWakeProofProperties) -or
        $State.SchemaVersion -cne $script:CddsiRealtimeWakeProofSchema -or
        $State.Lane -cne $Lane -or $State.Entries -isnot [Array] -or
        @($State.Entries).Count -gt 256 -or
        ($State.Revision -isnot [int] -and $State.Revision -isnot [long]) -or
        [long]$State.Revision -lt 0 -or [long]$State.Revision -gt $script:CddsiRealtimeMaxSafeInteger) {
        return $false
    }
    $seen = @{}
    foreach ($entry in @($State.Entries)) {
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $entry -Expected @(
                    'MessageId', 'Sequence', 'Commit', 'PayloadSha256', 'Status'
                )) -or
            $entry.MessageId -isnot [string] -or
            $entry.MessageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            ($entry.Sequence -isnot [int] -and $entry.Sequence -isnot [long]) -or
            [long]$entry.Sequence -lt 1 -or [long]$entry.Sequence -gt $script:CddsiRealtimeMaxSafeInteger -or
            $entry.Commit -isnot [string] -or $entry.Commit -cnotmatch '^[0-9a-f]{40}$' -or
            $entry.PayloadSha256 -isnot [string] -or
            $entry.PayloadSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            @('PENDING', 'SUCCEEDED') -cnotcontains $entry.Status -or
            $seen.ContainsKey($entry.MessageId)) {
            return $false
        }
        $seen[$entry.MessageId] = $true
    }
    return $true
}

function Read-CddsiRealtimeRelayWakeProofFileInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $Path)) {
        throw 'REALTIME_WAKE_PROOF_FILE_REPARSE'
    }
    $bytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $Path -MaximumBytes 131072 `
        -FailureCode 'REALTIME_WAKE_PROOF_FILE_INVALID'
    try {
        try {
            $raw = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $state = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        }
        catch {
            throw 'REALTIME_WAKE_PROOF_JSON_INVALID'
        }
        if (-not (Test-CddsiRealtimeRelayWakeProofStateInternal -State $state -Lane $Lane) -or
            (ConvertTo-Json -Compress -Depth 5 -InputObject $state) -cne $raw) {
            throw 'REALTIME_WAKE_PROOF_INVALID'
        }
        return $state
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Read-CddsiRealtimeRelayWakeProofStateInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    $paths = Get-CddsiRealtimeRelayWakeProofPathsInternal -StateRoot $StateRoot -Lane $Lane
    foreach ($path in @($paths.Current, $paths.Next, $paths.Backup)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $path)) {
            throw 'REALTIME_WAKE_PROOF_FILE_REPARSE'
        }
    }
    if ([IO.File]::Exists($paths.Backup)) {
        if ([IO.File]::Exists($paths.Current)) {
            [IO.File]::Delete($paths.Backup)
        }
        else {
            [void](Read-CddsiRealtimeRelayWakeProofFileInternal -Path $paths.Backup -Lane $Lane)
            [IO.File]::Move($paths.Backup, $paths.Current)
        }
    }
    if (-not [IO.File]::Exists($paths.Current) -and [IO.File]::Exists($paths.Next)) {
        $candidate = Read-CddsiRealtimeRelayWakeProofFileInternal -Path $paths.Next -Lane $Lane
        [IO.File]::Move($paths.Next, $paths.Current)
        return $candidate
    }
    if ([IO.File]::Exists($paths.Current) -and [IO.File]::Exists($paths.Next)) {
        [IO.File]::Delete($paths.Next)
    }
    if (-not [IO.File]::Exists($paths.Current)) {
        return New-CddsiRealtimeRelayWakeProofStateInternal -Lane $Lane
    }
    return Read-CddsiRealtimeRelayWakeProofFileInternal -Path $paths.Current -Lane $Lane
}

function Write-CddsiRealtimeRelayWakeProofStateAtomicInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)]$State
    )

    if (-not (Test-CddsiRealtimeRelayWakeProofStateInternal -State $State -Lane $State.Lane)) {
        throw 'REALTIME_WAKE_PROOF_INVALID'
    }
    $paths = Get-CddsiRealtimeRelayWakeProofPathsInternal -StateRoot $StateRoot -Lane $State.Lane
    foreach ($path in @($paths.Current, $paths.Next, $paths.Backup)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $path)) {
            throw 'REALTIME_WAKE_PROOF_FILE_REPARSE'
        }
    }
    if ([IO.File]::Exists($paths.Backup)) {
        throw 'REALTIME_WAKE_PROOF_BACKUP_EXISTS'
    }
    if ([IO.File]::Exists($paths.Next)) {
        [IO.File]::Delete($paths.Next)
    }
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
        (ConvertTo-Json -Compress -Depth 5 -InputObject $State)
    )
    $stream = [IO.FileStream]::new(
        $paths.Next, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough
    )
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
    [void](Read-CddsiRealtimeRelayWakeProofFileInternal -Path $paths.Next -Lane $State.Lane)
    Move-CddsiRealtimeRelayStateCandidateAtomicInternal -NextPath $paths.Next `
        -StatePath $paths.Current -BackupPath $paths.Backup `
        -ReplaceExisting ([IO.File]::Exists($paths.Current))
}

function Get-CddsiRealtimeRelayPublisherStatePathsInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    $stem = 'publisher-state-' + $Lane
    return [pscustomobject][ordered]@{
        Current = [IO.Path]::Combine($StateRoot, $stem + '.json')
        Next = [IO.Path]::Combine($StateRoot, $stem + '.next.json')
        Backup = [IO.Path]::Combine($StateRoot, $stem + '.backup.json')
        Lock = [IO.Path]::Combine($StateRoot, '.publisher-' + $Lane + '.lock')
    }
}

function New-CddsiRealtimeRelayPublisherStateInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimePublisherStateSchema
        Lane = $Lane
        LastPublishedSequence = [long]0
        LastMessageSha256 = $null
        PendingPublish = $null
        PublishedMessages = @()
        Revision = [long]0
    }
}

function Test-CddsiRealtimeRelayPublisherStateInternal {
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $State `
            -Expected $script:CddsiRealtimePublisherStateProperties) -or
        $State.SchemaVersion -cne $script:CddsiRealtimePublisherStateSchema -or
        $State.Lane -cne $Lane -or
        ($State.LastPublishedSequence -isnot [int] -and
            $State.LastPublishedSequence -isnot [long]) -or
        [long]$State.LastPublishedSequence -lt 0 -or
        [long]$State.LastPublishedSequence -gt $script:CddsiRealtimeMaxSafeInteger -or
        ($State.Revision -isnot [int] -and $State.Revision -isnot [long]) -or
        [long]$State.Revision -lt 0 -or [long]$State.Revision -gt $script:CddsiRealtimeMaxSafeInteger -or
        $State.PublishedMessages -isnot [Array] -or
        @($State.PublishedMessages).Count -gt 256) {
        return $false
    }
    $published = @($State.PublishedMessages)
    if ([long]$State.LastPublishedSequence -eq 0) {
        if ($null -ne $State.LastMessageSha256 -or $published.Count -ne 0) {
            return $false
        }
    }
    elseif ($State.LastMessageSha256 -isnot [string] -or
        $State.LastMessageSha256 -cnotmatch '^[0-9a-f]{64}$' -or $published.Count -eq 0) {
        return $false
    }
    $expectedSequence = [long]$State.LastPublishedSequence - $published.Count + 1
    $seenIds = @{}
    foreach ($entry in $published) {
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $entry -Expected @(
                    'MessageId', 'Sequence', 'MessageSha256', 'PayloadSha256', 'Commit'
                )) -or
            $entry.MessageId -isnot [string] -or
            $entry.MessageId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            ($entry.Sequence -isnot [int] -and $entry.Sequence -isnot [long]) -or
            [long]$entry.Sequence -ne $expectedSequence -or
            $entry.MessageSha256 -isnot [string] -or
            $entry.MessageSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $entry.PayloadSha256 -isnot [string] -or
            $entry.PayloadSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $entry.Commit -isnot [string] -or
            $entry.Commit -cnotmatch '^[0-9a-f]{40}$' -or
            $seenIds.ContainsKey($entry.MessageId)) {
            return $false
        }
        $seenIds[$entry.MessageId] = $true
        $expectedSequence++
    }
    if ($published.Count -gt 0 -and
        $published[-1].MessageSha256 -cne $State.LastMessageSha256) {
        return $false
    }
    if ($null -ne $State.PendingPublish) {
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                -InputObject $State.PendingPublish -Expected @('CanonicalBody', 'MessageSha256')) -or
            $State.PendingPublish.CanonicalBody -isnot [string] -or
            $State.PendingPublish.MessageSha256 -isnot [string] -or
            $State.PendingPublish.MessageSha256 -cnotmatch '^[0-9a-f]{64}$') {
            return $false
        }
        $validation = Test-CddsiRealtimeRelayNotificationInternal `
            -RawMessage $State.PendingPublish.CanonicalBody `
            -NowUtc ([DateTimeOffset]::UtcNow) -ValidationMode StoredConsumedReplay
        if (-not $validation.Valid -or $validation.MessageSha256 -cne
            $State.PendingPublish.MessageSha256 -or $validation.Message.Lane -cne $Lane -or
            [long]$validation.Message.Sequence -ne ([long]$State.LastPublishedSequence + 1) -or
            $validation.Message.PreviousSha256 -cne $State.LastMessageSha256 -or
            $seenIds.ContainsKey($validation.Message.MessageId)) {
            return $false
        }
    }
    return $true
}

function Read-CddsiRealtimeRelayPublisherStateFileInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $Path)) {
        throw 'REALTIME_PUBLISH_STATE_FILE_REPARSE'
    }
    $bytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $Path -MaximumBytes 262144 `
        -FailureCode 'REALTIME_PUBLISH_STATE_FILE_INVALID'
    try {
        try {
            $raw = [Text.UTF8Encoding]::new($false, $true).GetString($bytes)
            $state = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        }
        catch {
            throw 'REALTIME_PUBLISH_STATE_JSON_INVALID'
        }
        if (-not (Test-CddsiRealtimeRelayPublisherStateInternal -State $state -Lane $Lane) -or
            (ConvertTo-Json -Compress -Depth 8 -InputObject $state) -cne $raw) {
            throw 'REALTIME_PUBLISH_STATE_INVALID'
        }
        return $state
    }
    finally {
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}

function Read-CddsiRealtimeRelayPublisherStateInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane
    )

    $paths = Get-CddsiRealtimeRelayPublisherStatePathsInternal -StateRoot $StateRoot -Lane $Lane
    foreach ($path in @($paths.Current, $paths.Next, $paths.Backup)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $path)) {
            throw 'REALTIME_PUBLISH_STATE_FILE_REPARSE'
        }
    }
    if ([IO.File]::Exists($paths.Backup)) {
        if ([IO.File]::Exists($paths.Current)) {
            [IO.File]::Delete($paths.Backup)
        }
        else {
            [void](Read-CddsiRealtimeRelayPublisherStateFileInternal -Path $paths.Backup -Lane $Lane)
            [IO.File]::Move($paths.Backup, $paths.Current)
        }
    }
    if (-not [IO.File]::Exists($paths.Current) -and [IO.File]::Exists($paths.Next)) {
        $candidate = Read-CddsiRealtimeRelayPublisherStateFileInternal -Path $paths.Next -Lane $Lane
        [IO.File]::Move($paths.Next, $paths.Current)
        return $candidate
    }
    if ([IO.File]::Exists($paths.Current) -and [IO.File]::Exists($paths.Next)) {
        [IO.File]::Delete($paths.Next)
    }
    if (-not [IO.File]::Exists($paths.Current)) {
        return New-CddsiRealtimeRelayPublisherStateInternal -Lane $Lane
    }
    return Read-CddsiRealtimeRelayPublisherStateFileInternal -Path $paths.Current -Lane $Lane
}

function Write-CddsiRealtimeRelayPublisherStateAtomicInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)]$State
    )

    if (-not (Test-CddsiRealtimeRelayPublisherStateInternal -State $State -Lane $State.Lane)) {
        throw 'REALTIME_PUBLISH_STATE_INVALID'
    }
    $paths = Get-CddsiRealtimeRelayPublisherStatePathsInternal `
        -StateRoot $StateRoot -Lane $State.Lane
    foreach ($path in @($paths.Current, $paths.Next, $paths.Backup)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal -Path $path)) {
            throw 'REALTIME_PUBLISH_STATE_FILE_REPARSE'
        }
    }
    if ([IO.File]::Exists($paths.Backup)) {
        throw 'REALTIME_PUBLISH_STATE_BACKUP_EXISTS'
    }
    if ([IO.File]::Exists($paths.Next)) {
        [IO.File]::Delete($paths.Next)
    }
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes(
        (ConvertTo-Json -Compress -Depth 8 -InputObject $State)
    )
    $stream = [IO.FileStream]::new(
        $paths.Next, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write,
        [IO.FileShare]::None, 4096, [IO.FileOptions]::WriteThrough
    )
    try {
        $stream.Write($bytes, 0, $bytes.Length)
        $stream.Flush($true)
    }
    finally {
        $stream.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
    [void](Read-CddsiRealtimeRelayPublisherStateFileInternal -Path $paths.Next -Lane $State.Lane)
    Move-CddsiRealtimeRelayStateCandidateAtomicInternal -NextPath $paths.Next `
        -StatePath $paths.Current -BackupPath $paths.Backup `
        -ReplaceExisting ([IO.File]::Exists($paths.Current))
}

function Remove-CddsiRealtimeRelayOwnedStateRootInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    $fullPath = [IO.Path]::GetFullPath($StateRoot)
    $expectedLeaf = 'cddsi-realtime-relay-{0}' -f $RunId
    $markerPath = [IO.Path]::Combine($fullPath, '.cddsi-owner.json')
    if (-not [IO.Directory]::Exists($fullPath) -or
        [IO.DirectoryInfo]::new($fullPath).Name -cne $expectedLeaf -or
        -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullPath) -or
        -not (Test-CddsiRealtimeRelayProtectedDirectoryAclInternal -StateRoot $fullPath -OwnerSid $OwnerSid) -or
        -not [IO.File]::Exists($markerPath) -or
        (([IO.FileInfo]::new($markerPath).Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw 'REALTIME_STATE_CLEANUP_ROOT_INVALID'
    }
    $markerBytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $markerPath -MaximumBytes 1024 `
        -FailureCode 'REALTIME_STATE_CLEANUP_ROOT_INVALID'
    try {
        $actualMarker = [Text.UTF8Encoding]::new($false, $true).GetString($markerBytes)
        $expectedMarker = Get-CddsiRealtimeRelayOwnerMarkerTextInternal -RunId $RunId -OwnerSid $OwnerSid `
            -OwnershipTokenSha256 $OwnershipTokenSha256
        if ($actualMarker -cne $expectedMarker) {
            throw 'REALTIME_STATE_CLEANUP_ROOT_INVALID'
        }
    }
    finally {
        [Array]::Clear($markerBytes, 0, $markerBytes.Length)
    }
    $lifecycleLockPath = [IO.Path]::Combine($fullPath, '.lifecycle.lock')
    $lockPath = [IO.Path]::Combine($fullPath, '.watcher.lock')
    foreach ($cleanupLockPath in @($lifecycleLockPath, $lockPath)) {
        if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal `
                -Path $cleanupLockPath)) {
            throw 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'
        }
    }
    $lifecycleLock = Open-CddsiRealtimeRelayExclusiveLockFileInternal `
        -Path $lifecycleLockPath `
        -UnsafePathFailureCode 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'
    $lock = $null
    $publisherLocks = @()
    try {
        $lock = Open-CddsiRealtimeRelayExclusiveLockFileInternal `
            -Path $lockPath `
            -UnsafePathFailureCode 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'
        foreach ($lane in @('host-to-vm', 'vm-to-host')) {
            $publisherLockPath = [IO.Path]::Combine(
                $fullPath,
                '.publisher-' + $lane + '.lock'
            )
            if ([IO.File]::Exists($publisherLockPath)) {
                if (-not (Test-CddsiRealtimeRelayStateFilePathSafeInternal `
                        -Path $publisherLockPath)) {
                    throw 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'
                }
                $publisherLocks += [IO.FileStream]::new(
                    $publisherLockPath,
                    [IO.FileMode]::Open,
                    [IO.FileAccess]::ReadWrite,
                    [IO.FileShare]::None,
                    1,
                    [IO.FileOptions]::WriteThrough
                )
            }
        }
        $allowedLeaves = @(
            '.cddsi-owner.json', '.cleanup-tombstone.json', '.lifecycle.lock',
            '.watcher.lock', '.publisher-host-to-vm.lock',
            '.publisher-vm-to-host.lock',
            'watcher-state.json', 'watcher-state.next.json',
            $script:CddsiRealtimeStateBackupFileName,
            $script:CddsiRealtimeCredentialFileName,
            $script:CddsiRealtimeCredentialNextFileName,
            $script:CddsiRealtimeCredentialBackupFileName,
            'wake-proof-host-to-vm.json', 'wake-proof-host-to-vm.next.json',
            'wake-proof-host-to-vm.backup.json', 'wake-proof-vm-to-host.json',
            'wake-proof-vm-to-host.next.json', 'wake-proof-vm-to-host.backup.json'
        )
        $entries = @([IO.Directory]::EnumerateFileSystemEntries($fullPath))
        foreach ($entry in $entries) {
            $item = [IO.FileInfo]::new($entry)
            if (-not $item.Exists -or
                (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
                $allowedLeaves -cnotcontains $item.Name) {
                throw 'REALTIME_STATE_CLEANUP_ENTRY_INVALID'
            }
        }
        $tombstonePath = [IO.Path]::Combine($fullPath, '.cleanup-tombstone.json')
        $tombstone = ConvertTo-Json -Compress -InputObject ([ordered]@{
                SchemaVersion = 'cddsi-realtime-relay-cleanup-v1'
                StateRootBindingToken = Get-CddsiRealtimeRelayStateBindingTokenInternal `
                    -StateRoot $fullPath -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
            })
        if ([IO.File]::Exists($tombstonePath)) {
            $actualTombstone = [Text.UTF8Encoding]::new($false, $true).GetString(
                [IO.File]::ReadAllBytes($tombstonePath)
            )
            if ($actualTombstone -cne $tombstone) {
                throw 'REALTIME_STATE_CLEANUP_TOMBSTONE_INVALID'
            }
        }
        else {
            $tombstoneBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($tombstone)
            $tombstoneStream = [IO.FileStream]::new(
                $tombstonePath,
                [IO.FileMode]::CreateNew,
                [IO.FileAccess]::Write,
                [IO.FileShare]::None,
                4096,
                [IO.FileOptions]::WriteThrough
            )
            try {
                $tombstoneStream.Write($tombstoneBytes, 0, $tombstoneBytes.Length)
                $tombstoneStream.Flush($true)
            }
            finally {
                $tombstoneStream.Dispose()
            }
        }
        foreach ($leaf in @(
                'watcher-state.next.json', $script:CddsiRealtimeStateBackupFileName,
                'watcher-state.json',
                $script:CddsiRealtimeCredentialNextFileName,
                $script:CddsiRealtimeCredentialBackupFileName,
                $script:CddsiRealtimeCredentialFileName,
                'wake-proof-host-to-vm.next.json', 'wake-proof-host-to-vm.backup.json',
                'wake-proof-host-to-vm.json', 'wake-proof-vm-to-host.next.json',
                'wake-proof-vm-to-host.backup.json', 'wake-proof-vm-to-host.json'
            )) {
            $path = [IO.Path]::Combine($fullPath, $leaf)
            if ([IO.File]::Exists($path)) {
                [IO.File]::Delete($path)
            }
        }
    }
    finally {
        for ($publisherLockIndex = $publisherLocks.Count - 1;
            $publisherLockIndex -ge 0; $publisherLockIndex--) {
            $publisherLocks[$publisherLockIndex].Dispose()
        }
        if ($null -ne $lock) {
            $lock.Dispose()
        }
        $lifecycleLock.Dispose()
    }
    return [pscustomobject][ordered]@{
        SensitiveStateRemoved = $true
        RootTombstoned = $true
        RootRemoved = $false
        StateRootBindingToken = Get-CddsiRealtimeRelayStateBindingTokenInternal `
            -StateRoot $fullPath -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
    }
}

function New-CddsiRealtimeRelayOwnedStateProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) {
        throw 'REALTIME_STATE_REQUIRES_WINDOWS'
    }
    if ($RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        $OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or $OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'REALTIME_STATE_BINDING_INVALID'
    }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($OwnerSid -cne $currentSid) {
        throw 'REALTIME_STATE_OWNER_NOT_CURRENT_USER'
    }
    $fullPath = [IO.Path]::GetFullPath($StateRoot)
    $bindingToken = Get-CddsiRealtimeRelayStateBindingTokenInternal -StateRoot $fullPath `
        -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeStateProviderSchema
        ProviderKind = 'OWNED_STATE'
        StateRoot = $fullPath
        RunId = $RunId
        OwnerSid = $OwnerSid
        OwnershipTokenSha256 = $OwnershipTokenSha256
        BindingToken = $bindingToken
        ClientAdapterSha256 = Get-CddsiRealtimeRelayClientAdapterSha256Internal
    }
}

function Test-CddsiRealtimeRelayStateProviderShapeInternal {
    param(
        [Parameter(Mandatory = $true)]$StateProvider
    )

    try {
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $StateProvider `
                -ExpectedProperties $script:CddsiRealtimeStateProviderProperties) -or
            $StateProvider.SchemaVersion -cne $script:CddsiRealtimeStateProviderSchema -or
            $StateProvider.ProviderKind -cne 'OWNED_STATE' -or
            $StateProvider.RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $StateProvider.OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or
            $StateProvider.OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $StateProvider.BindingToken -cnotmatch '^[0-9a-f]{64}$' -or
            $StateProvider.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            -not [IO.Path]::IsPathRooted([string]$StateProvider.StateRoot) -or
            [IO.Path]::GetFullPath([string]$StateProvider.StateRoot) -cne $StateProvider.StateRoot -or
            [IO.DirectoryInfo]::new([string]$StateProvider.StateRoot).Name -cne
            ('cddsi-realtime-relay-' + $StateProvider.RunId) -or
            (Get-CddsiRealtimeRelayStateBindingTokenInternal -StateRoot $StateProvider.StateRoot `
                -OwnerSid $StateProvider.OwnerSid `
                -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256) -cne
            $StateProvider.BindingToken) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-CddsiRealtimeRelayStateProviderContractInternal {
    param(
        [Parameter(Mandatory = $true)]$StateProvider,
        [switch]$VerifySource
    )

    try {
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $StateProvider `
                -ExpectedProperties $script:CddsiRealtimeStateProviderProperties) -or
            $StateProvider.SchemaVersion -cne $script:CddsiRealtimeStateProviderSchema -or
            $StateProvider.ProviderKind -cne 'OWNED_STATE' -or
            $StateProvider.RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $StateProvider.OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or
            $StateProvider.OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $StateProvider.BindingToken -cnotmatch '^[0-9a-f]{64}$' -or
            $StateProvider.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            -not [IO.Path]::IsPathRooted([string]$StateProvider.StateRoot) -or
            [IO.Path]::GetFullPath([string]$StateProvider.StateRoot) -cne $StateProvider.StateRoot -or
            [IO.DirectoryInfo]::new([string]$StateProvider.StateRoot).Name -cne
            ('cddsi-realtime-relay-' + $StateProvider.RunId)) {
            return $false
        }
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($StateProvider.OwnerSid -cne $currentSid -or
            (Get-CddsiRealtimeRelayStateBindingTokenInternal -StateRoot $StateProvider.StateRoot `
                -OwnerSid $StateProvider.OwnerSid `
                -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256) -cne
            $StateProvider.BindingToken) {
            return $false
        }
        if ($VerifySource -and
            (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -cne $StateProvider.ClientAdapterSha256) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-CddsiRealtimeRelayOwnedStateOperationInternal {
    param(
        [Parameter(Mandatory = $true)]$StateProvider,
        [Parameter(Mandatory = $true)][ValidateSet(
            'ValidateRoot', 'AcquireLock', 'Load', 'CommitAtomically',
            'LoadWakeProof', 'CommitWakeProof', 'ReleaseLock',
            'AcquireLifecycleLock', 'ReleaseLifecycleLock',
            'AcquirePublisherLock', 'LoadPublisher', 'CommitPublisher',
            'ReleasePublisherLock'
        )][string]$Operation,
        [AllowNull()][string]$Lane = $null,
        [AllowNull()]$State = $null,
        [AllowNull()]$Handle = $null
    )

    if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $StateProvider -VerifySource)) {
        throw 'REALTIME_STATE_PROVIDER_INVALID'
    }
    if ($Operation -ceq 'ValidateRoot') {
        return Initialize-CddsiRealtimeRelayOwnedStateRootInternal `
            -StateRoot $StateProvider.StateRoot -RunId $StateProvider.RunId `
            -OwnerSid $StateProvider.OwnerSid `
            -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256
    }
    $validatedRoot = Assert-CddsiRealtimeRelayOwnedStateRootExistingInternal `
        -StateRoot $StateProvider.StateRoot -RunId $StateProvider.RunId `
        -OwnerSid $StateProvider.OwnerSid `
        -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256
    if ($Operation -ceq 'AcquireLifecycleLock') {
        $lifecycleLockPath = [IO.Path]::Combine($validatedRoot, '.lifecycle.lock')
        return Open-CddsiRealtimeRelayExclusiveLockFileInternal `
            -Path $lifecycleLockPath `
            -UnsafePathFailureCode 'REALTIME_LIFECYCLE_LOCK_REPARSE'
    }
    if ($Operation -ceq 'AcquireLock') {
        $lockPath = [IO.Path]::Combine($validatedRoot, '.watcher.lock')
        return Open-CddsiRealtimeRelayExclusiveLockFileInternal `
            -Path $lockPath -UnsafePathFailureCode 'REALTIME_LOCK_REPARSE'
    }
    if ($Operation -ceq 'Load') {
        return Read-CddsiRealtimeRelayStateInternal -StateRoot $validatedRoot -Lane $Lane
    }
    if ($Operation -ceq 'CommitAtomically') {
        Write-CddsiRealtimeRelayStateAtomicInternal -StateRoot $validatedRoot -State $State
        return
    }
    if ($Operation -ceq 'AcquirePublisherLock') {
        $publisherPaths = Get-CddsiRealtimeRelayPublisherStatePathsInternal `
            -StateRoot $validatedRoot -Lane $Lane
        return Open-CddsiRealtimeRelayExclusiveLockFileInternal `
            -Path $publisherPaths.Lock `
            -UnsafePathFailureCode 'REALTIME_PUBLISH_LOCK_REPARSE'
    }
    if ($Operation -ceq 'LoadWakeProof') {
        return Read-CddsiRealtimeRelayWakeProofStateInternal -StateRoot $validatedRoot -Lane $Lane
    }
    if ($Operation -ceq 'CommitWakeProof') {
        Write-CddsiRealtimeRelayWakeProofStateAtomicInternal -StateRoot $validatedRoot -State $State
        return
    }
    if ($Operation -ceq 'LoadPublisher') {
        return Read-CddsiRealtimeRelayPublisherStateInternal `
            -StateRoot $validatedRoot -Lane $Lane
    }
    if ($Operation -ceq 'CommitPublisher') {
        Write-CddsiRealtimeRelayPublisherStateAtomicInternal `
            -StateRoot $validatedRoot -State $State
        return
    }
    if ($Operation -ceq 'ReleasePublisherLock') {
        $expectedPublisherLock = (Get-CddsiRealtimeRelayPublisherStatePathsInternal `
                -StateRoot $validatedRoot -Lane $Lane).Lock
        if ($Handle -isnot [IO.FileStream] -or
            [IO.Path]::GetFullPath($Handle.Name) -cne $expectedPublisherLock) {
            throw 'REALTIME_PUBLISH_LOCK_HANDLE_INVALID'
        }
        $Handle.Dispose()
        return
    }
    if ($Operation -ceq 'ReleaseLifecycleLock') {
        $expectedLifecycleLock = [IO.Path]::Combine($validatedRoot, '.lifecycle.lock')
        if ($Handle -isnot [IO.FileStream] -or
            [IO.Path]::GetFullPath($Handle.Name) -cne $expectedLifecycleLock) {
            throw 'REALTIME_LIFECYCLE_LOCK_HANDLE_INVALID'
        }
        $Handle.Dispose()
        return
    }
    $expectedLockPath = [IO.Path]::Combine($validatedRoot, '.watcher.lock')
    if ($Handle -isnot [IO.FileStream] -or
        [IO.Path]::GetFullPath($Handle.Name) -cne $expectedLockPath) {
        throw 'REALTIME_LOCK_HANDLE_INVALID'
    }
    $Handle.Dispose()
}

function Test-CddsiRealtimeRelayRootsDisjointInternal {
    param(
        [Parameter(Mandatory = $true)][string]$FirstRoot,
        [Parameter(Mandatory = $true)][string]$SecondRoot
    )

    try {
        $separator = [IO.Path]::DirectorySeparatorChar
        $first = [IO.Path]::GetFullPath($FirstRoot).TrimEnd($separator)
        $second = [IO.Path]::GetFullPath($SecondRoot).TrimEnd($separator)
        if ($first.Length -eq 0 -or $second.Length -eq 0 -or
            $first.Equals($second, [StringComparison]::OrdinalIgnoreCase)) {
            return $false
        }
        return -not $first.StartsWith($second + $separator, [StringComparison]::OrdinalIgnoreCase) -and
        -not $second.StartsWith($first + $separator, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Assert-CddsiRealtimeRelayCleanupLiveAuthorizationCurrentInternal {
    param(
        [Parameter(Mandatory = $true)]$RelayExecutionContext,
        [Parameter(Mandatory = $true)]$StateProvider,
        [Parameter(Mandatory = $true)]$RuntimeAssertion,
        [Parameter(Mandatory = $true)][DateTimeOffset]$IssuedAtUtc,
        [Parameter(Mandatory = $true)][DateTimeOffset]$ExpiresAtUtc
    )

    $trustedSessionId = Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
        -RelayContext $RelayExecutionContext
    if ([string]::IsNullOrEmpty($trustedSessionId) -or
        -not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RelayExecutionContext `
            -ExpectedProperties $script:CddsiRealtimeLiveContextProperties) -or
        -not (Test-CddsiRealtimeRelayDataDescriptorInternal `
            -Descriptor $RelayExecutionContext.Providers `
            -ExpectedProperties $script:CddsiRealtimeLiveProviderSetProperties) -or
        $RelayExecutionContext.SchemaVersion -cne $script:CddsiRealtimeContextSchema -or
        $RelayExecutionContext.Mode -cne 'Live' -or
        $RelayExecutionContext.ProviderKind -cne 'Live' -or
        $RelayExecutionContext.ClientId -cne $RuntimeAssertion.ClientId -or
        $RelayExecutionContext.ClientAdapterSha256 -cne
        (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -or
        $RuntimeAssertion.ClientAdapterSha256 -cne
        $RelayExecutionContext.ClientAdapterSha256 -or
        -not [object]::ReferenceEquals(
            $RelayExecutionContext.Providers.State.PSObject,
            $StateProvider.PSObject
        ) -or
        -not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $StateProvider -VerifySource) -or
        $StateProvider.BindingToken -cne $RuntimeAssertion.StateRootBindingToken -or
        -not (Test-CddsiRealtimeRelayLiveTransportProviderContractInternal `
            -TransportProvider $RelayExecutionContext.Providers.Transport `
            -VerifySource -VerifySession) -or
        -not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $RelayExecutionContext.Providers.Clock -VerifySource) -or
        -not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $RelayExecutionContext.Providers.Credential `
            -ClientId $RelayExecutionContext.ClientId `
            -StateRootBindingToken $StateProvider.BindingToken -VerifySource)) {
        throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
    }
    $wakeProvider = $RelayExecutionContext.Providers.Wake
    if ($null -eq $wakeProvider.PSObject.Properties['Lane'] -or
        $null -eq $wakeProvider.PSObject.Properties['ClientId'] -or
        @('host-to-vm', 'vm-to-host') -cnotcontains $wakeProvider.Lane -or
        $wakeProvider.ClientId -cne $RelayExecutionContext.ClientId -or
        -not (Test-CddsiRealtimeRelayFixedWakeProviderContractInternal `
            -WakeProvider $wakeProvider -Lane $wakeProvider.Lane `
            -ClientId $wakeProvider.ClientId -VerifySource) -or
        -not (Test-CddsiRealtimeRelayRootsDisjointInternal `
            -FirstRoot $StateProvider.StateRoot `
            -SecondRoot $wakeProvider.Binding.StateRoot)) {
        throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
    }
    $now = [DateTimeOffset]::UtcNow
    if ($RuntimeAssertion.Status -cne 'AUTHORIZED' -or $IssuedAtUtc -gt $now -or
        $ExpiresAtUtc -le $now) {
        throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
    }
    return $trustedSessionId
}

function Remove-CddsiRealtimeRelayOwnedState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$RelayExecutionContext,
        [Parameter(Mandatory = $true)]$StateProvider,
        [Parameter(Mandatory = $true)]$RuntimeAssertion,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeOwnedStateCleanup
    )

    $trustedLiveSessionId = $null
    try {
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RuntimeAssertion `
                -ExpectedProperties $script:CddsiRealtimeCleanupAssertionProperties) -or
            $RuntimeAssertion.SchemaVersion -cne $script:CddsiRealtimeCleanupAssertionSchema -or
            $RuntimeAssertion.Action -cne 'REMOVE_OWNED_RELAY_STATE' -or
            $RuntimeAssertion.Mode -cne $Mode -or
            @('host-coordinator-v1', 'vm-tester-v1') -cnotcontains $RuntimeAssertion.ClientId -or
            $RuntimeAssertion.StateRootBindingToken -cnotmatch '^[0-9a-f]{64}$' -or
            $RuntimeAssertion.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'REALTIME_CLEANUP_ASSERTION_INVALID'
        }
        $cleanupIssued = [DateTimeOffset]::MinValue
        $cleanupExpires = [DateTimeOffset]::MinValue
        if (-not (Test-CddsiRealtimeRelayUtcSecondInternal `
                -Value $RuntimeAssertion.IssuedAtUtc -Parsed ([ref]$cleanupIssued)) -or
            -not (Test-CddsiRealtimeRelayUtcSecondInternal `
                -Value $RuntimeAssertion.ExpiresAtUtc -Parsed ([ref]$cleanupExpires)) -or
            $cleanupExpires -le $cleanupIssued -or
            ($cleanupExpires - $cleanupIssued).TotalSeconds -gt
            $script:CddsiRealtimeMaxAssertionLifetimeSeconds) {
            throw 'REALTIME_CLEANUP_ASSERTION_INVALID'
        }
        if ($null -eq $RelayExecutionContext -or $null -eq $RelayExecutionContext.PSObject -or
            $null -eq $RelayExecutionContext.PSObject.Properties['SchemaVersion'] -or
            $null -eq $RelayExecutionContext.PSObject.Properties['Mode'] -or
            $null -eq $RelayExecutionContext.PSObject.Properties['ProviderKind'] -or
            $null -eq $RelayExecutionContext.PSObject.Properties['Providers'] -or
            $RelayExecutionContext.Mode -cne $Mode -or
            $RelayExecutionContext.ClientId -cne $RuntimeAssertion.ClientId -or
            $null -eq $RelayExecutionContext.Providers -or
            $null -eq $RelayExecutionContext.Providers.PSObject.Properties['State'] -or
            $null -eq $RelayExecutionContext.Providers.State) {
            throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
        }
        if ($Mode -cne 'Live') {
            if ($RuntimeAssertion.Status -cne 'SYNTHETIC' -or
                $RelayExecutionContext.ProviderKind -cne 'Fake' -or
                $null -eq $StateProvider.PSObject.Properties['BindingToken'] -or
                $StateProvider.BindingToken -cne $RuntimeAssertion.StateRootBindingToken -or
                -not [object]::ReferenceEquals(
                    $RelayExecutionContext.Providers.State.PSObject,
                    $StateProvider.PSObject
                )) {
                throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
            }
            return [pscustomobject][ordered]@{
                SchemaVersion = $script:CddsiRealtimeCleanupResultSchema
                Status = 'PLANNED'
                Code = 'REALTIME_STATE_CLEANUP_PLANNED'
                Mode = $Mode
                Changed = $false
                SensitiveStateRemoved = $false
                RootTombstoned = $false
                RootRemoved = $false
                StateRootBindingToken = $null
                ProductLiveAttemptCount = 0
                RealRegistryAccessCount = 0
                ProductNetworkRequestCount = 0
                OperatorRelayNetworkRequestCount = 0
                OperatorGitInvocationCount = 0
                OperatorGitTransportCount = 0
                OperatorLocalStateMutationCount = 0
                RealNetworkAccessCount = 0
                RealCredentialManagerAccessCount = 0
                ProductProcessSpawnCount = 0
                OperatorCodexProcessSpawnCount = 0
                FixedWakeEffectCount = 0
                OutsideOwnedStateWriteCount = 0
                UnexpectedLedgerEntryCount = 0
                MutationSpyCount = 0
            }
        }
        if ($PSVersionTable.PSVersion.Major -ne 7 -or
            -not $AcknowledgeOwnedStateCleanup) {
            throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
        }
        $trustedLiveSessionId = Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
            -RelayContext $RelayExecutionContext
        $authorizedSessionId = Assert-CddsiRealtimeRelayCleanupLiveAuthorizationCurrentInternal `
            -RelayExecutionContext $RelayExecutionContext -StateProvider $StateProvider `
            -RuntimeAssertion $RuntimeAssertion -IssuedAtUtc $cleanupIssued `
            -ExpiresAtUtc $cleanupExpires
        if ([string]::IsNullOrEmpty($trustedLiveSessionId) -or
            $authorizedSessionId -cne $trustedLiveSessionId) {
            throw 'REALTIME_CLEANUP_CONTEXT_INVALID'
        }
        [void](Assert-CddsiRealtimeRelayCleanupLiveAuthorizationCurrentInternal `
                -RelayExecutionContext $RelayExecutionContext -StateProvider $StateProvider `
                -RuntimeAssertion $RuntimeAssertion -IssuedAtUtc $cleanupIssued `
                -ExpiresAtUtc $cleanupExpires)
        $cleanup = Remove-CddsiRealtimeRelayOwnedStateRootInternal `
            -StateRoot $StateProvider.StateRoot -RunId $StateProvider.RunId `
            -OwnerSid $StateProvider.OwnerSid `
            -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256
        return [pscustomobject][ordered]@{
            SchemaVersion = $script:CddsiRealtimeCleanupResultSchema
            Status = 'SUCCEEDED'
            Code = 'REALTIME_STATE_CLEANUP_COMPLETE'
            Mode = $Mode
            Changed = $true
            SensitiveStateRemoved = [bool]$cleanup.SensitiveStateRemoved
            RootTombstoned = [bool]$cleanup.RootTombstoned
            RootRemoved = [bool]$cleanup.RootRemoved
            StateRootBindingToken = $cleanup.StateRootBindingToken
            ProductLiveAttemptCount = 0
            RealRegistryAccessCount = 0
            ProductNetworkRequestCount = 0
            OperatorRelayNetworkRequestCount = 0
            OperatorGitInvocationCount = 0
            OperatorGitTransportCount = 0
            OperatorLocalStateMutationCount = 1
            RealNetworkAccessCount = 0
            RealCredentialManagerAccessCount = 0
            ProductProcessSpawnCount = 0
            OperatorCodexProcessSpawnCount = 0
            FixedWakeEffectCount = 0
            OutsideOwnedStateWriteCount = 0
            UnexpectedLedgerEntryCount = 0
            MutationSpyCount = 0
        }
    }
    finally {
        if ($Mode -ceq 'Live' -and -not [string]::IsNullOrEmpty($trustedLiveSessionId)) {
            Close-CddsiRealtimeRelayTrustedLiveSessionInternal -TrustedSessionId $trustedLiveSessionId
        }
    }
}

function Read-CddsiRealtimeRelayBoundedFileInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][ValidateRange(1, 1048576)][int]$MaximumBytes,
        [Parameter(Mandatory = $true)][string]$FailureCode
    )

    if (-not [IO.File]::Exists($Path)) {
        throw $FailureCode
    }
    $file = [IO.FileInfo]::new($Path)
    if (-not $file.Exists -or (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)) {
        throw $FailureCode
    }
    $stream = $null
    $bytes = $null
    try {
        $stream = [IO.FileStream]::new(
            $Path,
            [IO.FileMode]::Open,
            [IO.FileAccess]::Read,
            [IO.FileShare]::Read,
            4096,
            [IO.FileOptions]::SequentialScan
        )
        if ($stream.Length -lt 1 -or $stream.Length -gt $MaximumBytes) {
            throw $FailureCode
        }
        $bytes = [byte[]]::new([int]$stream.Length)
        $offset = 0
        while ($offset -lt $bytes.Length) {
            $read = $stream.Read($bytes, $offset, $bytes.Length - $offset)
            if ($read -le 0) {
                throw $FailureCode
            }
            $offset += $read
        }
        $file.Refresh()
        if (-not $file.Exists -or (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) -or
            $stream.Length -ne $bytes.Length) {
            throw $FailureCode
        }
        $result = $bytes
        $bytes = $null
        return $result
    }
    catch {
        if ($null -ne $bytes) {
            [Array]::Clear($bytes, 0, $bytes.Length)
        }
        throw $FailureCode
    }
    finally {
        if ($null -ne $stream) {
            $stream.Dispose()
        }
    }
}

function Assert-CddsiRealtimeRelayOwnedStateRootReadOnlyInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256
    )

    if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
        $PSVersionTable.PSVersion.Major -ne 7) {
        throw 'REALTIME_CREDENTIAL_REQUIRES_WINDOWS_POWERSHELL7'
    }
    if ($RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        $OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or $OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'REALTIME_CREDENTIAL_STATE_BINDING_INVALID'
    }
    $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    if ($OwnerSid -cne $currentSid) {
        throw 'REALTIME_CREDENTIAL_OWNER_NOT_CURRENT_USER'
    }
    $fullPath = [IO.Path]::GetFullPath($StateRoot)
    $expectedLeaf = 'cddsi-realtime-relay-{0}' -f $RunId
    if (-not [IO.Path]::IsPathRooted($fullPath) -or
        [IO.DirectoryInfo]::new($fullPath).Name -cne $expectedLeaf -or
        -not [IO.Directory]::Exists($fullPath) -or
        -not (Test-CddsiRealtimeRelayNoReparsePathInternal -Path $fullPath) -or
        -not (Test-CddsiRealtimeRelayProtectedDirectoryAclInternal -StateRoot $fullPath -OwnerSid $OwnerSid)) {
        throw 'REALTIME_CREDENTIAL_STATE_ROOT_INVALID'
    }
    if ([IO.File]::Exists([IO.Path]::Combine($fullPath, '.cleanup-tombstone.json'))) {
        throw 'REALTIME_CREDENTIAL_STATE_ROOT_TOMBSTONED'
    }
    $markerPath = [IO.Path]::Combine($fullPath, '.cddsi-owner.json')
    $markerBytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $markerPath -MaximumBytes 1024 `
        -FailureCode 'REALTIME_CREDENTIAL_OWNER_MARKER_INVALID'
    try {
        try {
            $actualMarker = [Text.UTF8Encoding]::new($false, $true).GetString($markerBytes)
        }
        catch {
            throw 'REALTIME_CREDENTIAL_OWNER_MARKER_INVALID'
        }
        $expectedMarker = Get-CddsiRealtimeRelayOwnerMarkerTextInternal -RunId $RunId -OwnerSid $OwnerSid `
            -OwnershipTokenSha256 $OwnershipTokenSha256
        if ($actualMarker -cne $expectedMarker) {
            throw 'REALTIME_CREDENTIAL_OWNER_MARKER_INVALID'
        }
    }
    finally {
        [Array]::Clear($markerBytes, 0, $markerBytes.Length)
    }
    return $fullPath
}

function ConvertTo-CddsiRealtimeRelayCanonicalCredentialBlobInternal {
    param(
        [Parameter(Mandatory = $true)]$CredentialBlob
    )

    return ConvertTo-Json -Compress -Depth 2 -InputObject ([ordered]@{
            ClientId = $CredentialBlob.ClientId
            Environment = $CredentialBlob.Environment
            KeyId = $CredentialBlob.KeyId
            ProtectedSecretBase64 = $CredentialBlob.ProtectedSecretBase64
            ProtectionScope = $CredentialBlob.ProtectionScope
            SchemaVersion = $CredentialBlob.SchemaVersion
            StateRootBindingToken = $CredentialBlob.StateRootBindingToken
        })
}

function Read-CddsiRealtimeRelayCredentialBlobInternal {
    param(
        [Parameter(Mandatory = $true)][string]$CredentialPath,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [AllowNull()][string]$Environment = $null,
        [AllowNull()][string]$KeyId = $null,
        [Parameter(Mandatory = $true)][string]$StateRootBindingToken
    )

    $rawBytes = Read-CddsiRealtimeRelayBoundedFileInternal -Path $CredentialPath `
        -MaximumBytes $script:CddsiRealtimeMaxCredentialBlobBytes `
        -FailureCode 'REALTIME_CREDENTIAL_BLOB_INVALID'
    $protectedBytes = $null
    try {
        try {
            $raw = [Text.UTF8Encoding]::new($false, $true).GetString($rawBytes)
        }
        catch {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        $keyMatches = @([regex]::Matches($raw, '"([A-Za-z][A-Za-z0-9]*)":'))
        if ($keyMatches.Count -ne $script:CddsiRealtimeCredentialBlobProperties.Count -or
            @($keyMatches | ForEach-Object { $_.Groups[1].Value } | Sort-Object -Unique).Count -ne
            $script:CddsiRealtimeCredentialBlobProperties.Count) {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        try {
            $blob = ConvertFrom-Json -InputObject $raw -ErrorAction Stop
        }
        catch {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        $environmentSpecified = -not [string]::IsNullOrEmpty($Environment)
        $keyIdSpecified = -not [string]::IsNullOrEmpty($KeyId)
        if ($environmentSpecified -ne $keyIdSpecified -or
            -not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $blob `
                -Expected $script:CddsiRealtimeCredentialBlobProperties) -or
            (ConvertTo-CddsiRealtimeRelayCanonicalCredentialBlobInternal -CredentialBlob $blob) -cne $raw -or
            @($script:CddsiRealtimeCredentialBlobProperties | Where-Object {
                    $blob.$_ -isnot [string]
                }).Count -ne 0 -or
            $blob.SchemaVersion -cne $script:CddsiRealtimeCredentialBlobSchema -or
            $blob.ClientId -cne $ClientId -or
            $blob.Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
            $blob.KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$' -or
            ($environmentSpecified -and $blob.Environment -cne $Environment) -or
            ($keyIdSpecified -and $blob.KeyId -cne $KeyId) -or
            $blob.ProtectionScope -cne 'CurrentUser' -or
            $blob.StateRootBindingToken -cne $StateRootBindingToken) {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        try {
            $protectedBytes = [Convert]::FromBase64String($blob.ProtectedSecretBase64)
        }
        catch {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        if ($protectedBytes.Length -lt 48 -or $protectedBytes.Length -gt 1024 -or
            [Convert]::ToBase64String($protectedBytes) -cne $blob.ProtectedSecretBase64) {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        return [pscustomobject][ordered]@{
            CredentialBlob = $blob
            CredentialBlobSha256 = Get-CddsiRealtimeRelaySha256Internal -Bytes $rawBytes
        }
    }
    catch {
        throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
    }
    finally {
        if ($null -ne $protectedBytes) {
            [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
        }
        [Array]::Clear($rawBytes, 0, $rawBytes.Length)
    }
}

function Assert-CddsiRealtimeRelayCredentialArtifactsCurrentInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot
    )

    try {
        foreach ($leaf in @(
                $script:CddsiRealtimeCredentialNextFileName,
                $script:CddsiRealtimeCredentialBackupFileName
            )) {
            if (@([IO.Directory]::EnumerateFileSystemEntries(
                        $StateRoot,
                        $leaf,
                        [IO.SearchOption]::TopDirectoryOnly
                    )).Count -ne 0) {
                throw 'REALTIME_CREDENTIAL_STALE_ARTIFACT'
            }
        }
    }
    catch {
        throw 'REALTIME_CREDENTIAL_STALE_ARTIFACT'
    }
}

function Get-CddsiRealtimeRelayCredentialEntropyInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId,
        [Parameter(Mandatory = $true)][string]$StateRootBindingToken
    )

    $entropyText = 'cddsi-realtime-relay-dpapi-entropy-v1|{0}|{1}|{2}|{3}' -f `
        $ClientId, $Environment, $KeyId, $StateRootBindingToken
    $entropyTextBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($entropyText)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ,$algorithm.ComputeHash($entropyTextBytes)
    }
    finally {
        if ($null -ne $entropyTextBytes) {
            [Array]::Clear($entropyTextBytes, 0, $entropyTextBytes.Length)
        }
        $algorithm.Dispose()
    }
}

function Protect-CddsiRealtimeRelaySecretCurrentUserInternal {
    param(
        [Parameter(Mandatory = $true)][byte[]]$SecretBytes,
        [Parameter(Mandatory = $true)][byte[]]$EntropyBytes
    )

    return ,([Security.Cryptography.ProtectedData]::Protect(
        $SecretBytes,
        $EntropyBytes,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    ))
}

function Unprotect-CddsiRealtimeRelaySecretCurrentUserInternal {
    param(
        [Parameter(Mandatory = $true)][byte[]]$ProtectedBytes,
        [Parameter(Mandatory = $true)][byte[]]$EntropyBytes
    )

    return ,([Security.Cryptography.ProtectedData]::Unprotect(
        $ProtectedBytes,
        $EntropyBytes,
        [Security.Cryptography.DataProtectionScope]::CurrentUser
    ))
}

function New-CddsiRealtimeRelayCredentialProvisionResultInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode,
        [Parameter(Mandatory = $true)][ValidateSet('PLANNED', 'SUCCEEDED')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][bool]$Changed,
        [AllowNull()][string]$CredentialBlobSha256,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeCredentialProvisionResultSchema
        Mode = $Mode
        Status = $Status
        Code = $Code
        Changed = $Changed
        CredentialBlobSha256 = $CredentialBlobSha256
        ClientId = $ClientId
        Environment = $Environment
        KeyId = $KeyId
    }
}

function Test-CddsiRealtimeRelayCredentialCandidateInternal {
    param(
        [Parameter(Mandatory = $true)][string]$CredentialPath,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId,
        [Parameter(Mandatory = $true)][string]$StateRootBindingToken,
        [Parameter(Mandatory = $true)][byte[]]$ExpectedSecretBytes
    )

    $protectedBytes = $null
    $entropyBytes = $null
    $roundTripSecretBytes = $null
    try {
        $loaded = Read-CddsiRealtimeRelayCredentialBlobInternal -CredentialPath $CredentialPath `
            -ClientId $ClientId -Environment $Environment -KeyId $KeyId `
            -StateRootBindingToken $StateRootBindingToken
        $protectedBytes = [Convert]::FromBase64String(
            $loaded.CredentialBlob.ProtectedSecretBase64
        )
        $entropyBytes = [byte[]](Get-CddsiRealtimeRelayCredentialEntropyInternal `
                -ClientId $ClientId -Environment $Environment -KeyId $KeyId `
                -StateRootBindingToken $StateRootBindingToken)
        $roundTripSecretBytes = [byte[]](
            Unprotect-CddsiRealtimeRelaySecretCurrentUserInternal `
                -ProtectedBytes $protectedBytes -EntropyBytes $entropyBytes
        )
        if ($ExpectedSecretBytes.Length -ne 32 -or $roundTripSecretBytes.Length -ne 32 -or
            -not [Security.Cryptography.CryptographicOperations]::FixedTimeEquals(
                $ExpectedSecretBytes,
                $roundTripSecretBytes
            )) {
            throw 'REALTIME_CREDENTIAL_CANDIDATE_INVALID'
        }
        return $loaded.CredentialBlobSha256
    }
    catch {
        throw 'REALTIME_CREDENTIAL_CANDIDATE_INVALID'
    }
    finally {
        if ($null -ne $roundTripSecretBytes) {
            [Array]::Clear($roundTripSecretBytes, 0, $roundTripSecretBytes.Length)
        }
        if ($null -ne $entropyBytes) {
            [Array]::Clear($entropyBytes, 0, $entropyBytes.Length)
        }
        if ($null -ne $protectedBytes) {
            [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
        }
    }
}

function Move-CddsiRealtimeRelayCredentialCandidateAtomicInternal {
    param(
        [Parameter(Mandatory = $true)][string]$CandidatePath,
        [Parameter(Mandatory = $true)][string]$CredentialPath,
        [Parameter(Mandatory = $true)][bool]$ReplaceExisting
    )

    if ($ReplaceExisting) {
        try {
            [IO.File]::Replace($CandidatePath, $CredentialPath, $null)
        }
        catch {
            $replaceFailure = $_.Exception
            while ($null -ne $replaceFailure.InnerException) {
                $replaceFailure = $replaceFailure.InnerException
            }
            if ($replaceFailure -isnot [ArgumentException] -or
                $replaceFailure.ParamName -cne 'path' -or
                -not [IO.File]::Exists($CandidatePath) -or
                -not [IO.File]::Exists($CredentialPath)) {
                throw
            }
            [IO.File]::Move($CandidatePath, $CredentialPath, $true)
        }
        return
    }
    [IO.File]::Move($CandidatePath, $CredentialPath)
}

function Set-CddsiRealtimeRelayDpapiCredential {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StateProvider,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId,
        [Parameter(Mandatory = $true)][object]$SecretBytes,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeCredentialWrite,
        [switch]$AllowCreate,
        [AllowNull()][string]$ExpectedCurrentCredentialBlobSha256 = $null
    )

    $candidateCreatedByThisInvocation = $false
    $candidatePath = $null
    $lockHandle = $null
    $secretCopy = $null
    $entropyBytes = $null
    $protectedBytes = $null
    $canonicalBytes = $null
    try {
        if ($SecretBytes -isnot [byte[]] -or $SecretBytes.Length -ne 32) {
            throw 'REALTIME_CREDENTIAL_SECRET_INPUT_INVALID'
        }
        if ($Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
            $KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$' -or
            -not (Test-CddsiRealtimeRelayStateProviderShapeInternal `
                -StateProvider $StateProvider)) {
            throw 'REALTIME_CREDENTIAL_PROVISION_INPUT_INVALID'
        }
        if ($AllowCreate) {
            if (-not [string]::IsNullOrEmpty($ExpectedCurrentCredentialBlobSha256)) {
                throw 'REALTIME_CREDENTIAL_CREATE_CAS_FORBIDDEN'
            }
        }
        elseif ([string]::IsNullOrEmpty($ExpectedCurrentCredentialBlobSha256) -or
            $ExpectedCurrentCredentialBlobSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'REALTIME_CREDENTIAL_ROTATION_CAS_REQUIRED'
        }
        if ($Mode -cne 'Live') {
            return New-CddsiRealtimeRelayCredentialProvisionResultInternal -Mode $Mode `
                -Status PLANNED -Code $(if ($AllowCreate) {
                        'REALTIME_CREDENTIAL_CREATE_PLANNED'
                    }
                    else {
                        'REALTIME_CREDENTIAL_ROTATION_PLANNED'
                    }) -Changed $false -CredentialBlobSha256 $null -ClientId $ClientId `
                -Environment $Environment -KeyId $KeyId
        }
        if (-not $AcknowledgeCredentialWrite) {
            throw 'REALTIME_CREDENTIAL_LIVE_CONFIRMATION_REQUIRED'
        }
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT -or
            $PSVersionTable.PSVersion.Major -ne 7) {
            throw 'REALTIME_CREDENTIAL_REQUIRES_WINDOWS_POWERSHELL7'
        }
        if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
                -StateProvider $StateProvider -VerifySource)) {
            throw 'REALTIME_STATE_PROVIDER_INVALID'
        }
        if ($AllowCreate) {
            $rootResult = Initialize-CddsiRealtimeRelayOwnedStateRootInternal `
                -StateRoot $StateProvider.StateRoot -RunId $StateProvider.RunId `
                -OwnerSid $StateProvider.OwnerSid `
                -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256
            if ($null -eq $rootResult -or -not $rootResult.Valid -or
                -not $rootResult.OwnerMarked -or -not $rootResult.AclProtected -or
                -not $rootResult.NoReparse) {
                throw 'REALTIME_CREDENTIAL_STATE_ROOT_INVALID'
            }
        }
        else {
            [void](Assert-CddsiRealtimeRelayOwnedStateRootExistingInternal `
                    -StateRoot $StateProvider.StateRoot -RunId $StateProvider.RunId `
                    -OwnerSid $StateProvider.OwnerSid `
                    -OwnershipTokenSha256 $StateProvider.OwnershipTokenSha256)
        }
        try {
            $lockHandle = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $StateProvider -Operation AcquireLock
        }
        catch {
            throw 'REALTIME_CREDENTIAL_SINGLE_INSTANCE_LOCK_FAILED'
        }
        $credentialPath = [IO.Path]::Combine(
            $StateProvider.StateRoot,
            $script:CddsiRealtimeCredentialFileName
        )
        $candidatePath = [IO.Path]::Combine(
            $StateProvider.StateRoot,
            $script:CddsiRealtimeCredentialNextFileName
        )
        $backupPath = [IO.Path]::Combine(
            $StateProvider.StateRoot,
            $script:CddsiRealtimeCredentialBackupFileName
        )
        foreach ($path in @($credentialPath, $candidatePath, $backupPath)) {
            if ([IO.Directory]::Exists($path) -or
                ([IO.File]::Exists($path) -and
                    (([IO.FileInfo]::new($path).Attributes -band
                        [IO.FileAttributes]::ReparsePoint) -ne 0))) {
                throw 'REALTIME_CREDENTIAL_PATH_INVALID'
            }
        }
        if ([IO.File]::Exists($candidatePath)) {
            throw 'REALTIME_CREDENTIAL_NEXT_EXISTS'
        }
        if ([IO.File]::Exists($backupPath)) {
            throw 'REALTIME_CREDENTIAL_BACKUP_EXISTS'
        }
        $credentialExists = [IO.File]::Exists($credentialPath)
        if ($AllowCreate) {
            if ($credentialExists) {
                throw 'REALTIME_CREDENTIAL_ALREADY_EXISTS'
            }
        }
        else {
            if (-not $credentialExists) {
                throw 'REALTIME_CREDENTIAL_CREATE_REQUIRED'
            }
            $current = Read-CddsiRealtimeRelayCredentialBlobInternal `
                -CredentialPath $credentialPath -ClientId $ClientId `
                -StateRootBindingToken $StateProvider.BindingToken
            if ($current.CredentialBlobSha256 -cne $ExpectedCurrentCredentialBlobSha256) {
                throw 'REALTIME_CREDENTIAL_ROTATION_CAS_MISMATCH'
            }
        }
        $secretCopy = [byte[]]::new(32)
        [Array]::Copy([byte[]]$SecretBytes, $secretCopy, 32)
        $entropyBytes = [byte[]](Get-CddsiRealtimeRelayCredentialEntropyInternal `
                -ClientId $ClientId -Environment $Environment -KeyId $KeyId `
                -StateRootBindingToken $StateProvider.BindingToken)
        $protectedBytes = [byte[]](Protect-CddsiRealtimeRelaySecretCurrentUserInternal `
                -SecretBytes $secretCopy -EntropyBytes $entropyBytes)
        if ($null -eq $protectedBytes -or $protectedBytes.Length -lt 48 -or
            $protectedBytes.Length -gt 1024) {
            throw 'REALTIME_CREDENTIAL_PROTECT_FAILED'
        }
        $credentialBlob = [pscustomobject][ordered]@{
            ClientId = $ClientId
            Environment = $Environment
            KeyId = $KeyId
            ProtectedSecretBase64 = [Convert]::ToBase64String($protectedBytes)
            ProtectionScope = 'CurrentUser'
            SchemaVersion = $script:CddsiRealtimeCredentialBlobSchema
            StateRootBindingToken = $StateProvider.BindingToken
        }
        $canonical = ConvertTo-CddsiRealtimeRelayCanonicalCredentialBlobInternal `
            -CredentialBlob $credentialBlob
        $canonicalBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($canonical)
        if ($canonicalBytes.Length -lt 1 -or
            $canonicalBytes.Length -gt $script:CddsiRealtimeMaxCredentialBlobBytes) {
            throw 'REALTIME_CREDENTIAL_BLOB_INVALID'
        }
        $candidateStream = [IO.FileStream]::new(
            $candidatePath,
            [IO.FileMode]::CreateNew,
            [IO.FileAccess]::Write,
            [IO.FileShare]::None,
            4096,
            [IO.FileOptions]::WriteThrough
        )
        $candidateCreatedByThisInvocation = $true
        try {
            $candidateStream.Write($canonicalBytes, 0, $canonicalBytes.Length)
            $candidateStream.Flush($true)
        }
        finally {
            $candidateStream.Dispose()
        }
        $credentialBlobSha256 = Test-CddsiRealtimeRelayCredentialCandidateInternal `
            -CredentialPath $candidatePath -ClientId $ClientId -Environment $Environment `
            -KeyId $KeyId -StateRootBindingToken $StateProvider.BindingToken `
            -ExpectedSecretBytes $secretCopy
        if ($credentialBlobSha256 -cnotmatch '^[0-9a-f]{64}$') {
            throw 'REALTIME_CREDENTIAL_CANDIDATE_INVALID'
        }
        Move-CddsiRealtimeRelayCredentialCandidateAtomicInternal `
            -CandidatePath $candidatePath -CredentialPath $credentialPath `
            -ReplaceExisting $credentialExists
        $candidateCreatedByThisInvocation = $false
        return New-CddsiRealtimeRelayCredentialProvisionResultInternal -Mode Live `
            -Status SUCCEEDED -Code $(if ($AllowCreate) {
                    'REALTIME_CREDENTIAL_CREATED'
                }
                else {
                    'REALTIME_CREDENTIAL_ROTATED'
                }) -Changed $true -CredentialBlobSha256 $credentialBlobSha256 `
            -ClientId $ClientId -Environment $Environment -KeyId $KeyId
    }
    catch {
        $code = [string]$_.Exception.Message
        $knownCodes = @(
            'REALTIME_CREDENTIAL_SECRET_INPUT_INVALID',
            'REALTIME_CREDENTIAL_PROVISION_INPUT_INVALID',
            'REALTIME_CREDENTIAL_CREATE_CAS_FORBIDDEN',
            'REALTIME_CREDENTIAL_ROTATION_CAS_REQUIRED',
            'REALTIME_CREDENTIAL_LIVE_CONFIRMATION_REQUIRED',
            'REALTIME_CREDENTIAL_REQUIRES_WINDOWS_POWERSHELL7',
            'REALTIME_STATE_PROVIDER_INVALID',
            'REALTIME_CREDENTIAL_STATE_ROOT_INVALID',
            'REALTIME_CREDENTIAL_SINGLE_INSTANCE_LOCK_FAILED',
            'REALTIME_CREDENTIAL_PATH_INVALID',
            'REALTIME_CREDENTIAL_NEXT_EXISTS',
            'REALTIME_CREDENTIAL_BACKUP_EXISTS',
            'REALTIME_CREDENTIAL_ALREADY_EXISTS',
            'REALTIME_CREDENTIAL_CREATE_REQUIRED',
            'REALTIME_CREDENTIAL_ROTATION_CAS_MISMATCH',
            'REALTIME_CREDENTIAL_PROTECT_FAILED',
            'REALTIME_CREDENTIAL_BLOB_INVALID',
            'REALTIME_CREDENTIAL_CANDIDATE_INVALID'
        )
        if ($knownCodes -cnotcontains $code) {
            $code = 'REALTIME_CREDENTIAL_PROVISION_FAILED'
        }
        throw $code
    }
    finally {
        if ($candidateCreatedByThisInvocation -and
            -not [string]::IsNullOrEmpty($candidatePath)) {
            try {
                if ([IO.File]::Exists($candidatePath) -and
                    (([IO.FileInfo]::new($candidatePath).Attributes -band
                        [IO.FileAttributes]::ReparsePoint) -eq 0)) {
                    [IO.File]::Delete($candidatePath)
                }
            }
            catch {
                # Cleanup is best-effort and never discloses a path or provider exception.
            }
        }
        if ($null -ne $lockHandle) {
            try {
                $lockHandle.Dispose()
            }
            catch {
                # Lock cleanup is best-effort and never discloses a handle exception.
            }
        }
        foreach ($buffer in @($canonicalBytes, $protectedBytes, $entropyBytes, $secretCopy)) {
            if ($null -ne $buffer) {
                [Array]::Clear($buffer, 0, $buffer.Length)
            }
        }
    }
}

function Invoke-CddsiRealtimeRelayDpapiCredentialOperationInternal {
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId,
        [Parameter(Mandatory = $true)][string]$StateRootBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedCredentialBlobSha256,
        [Parameter(Mandatory = $true)][ValidateSet('Validate', 'Sign')][string]$Operation,
        [AllowEmptyString()][string]$CanonicalRequest = ''
    )

    $protectedBytes = $null
    $entropyBytes = $null
    $secretBytes = $null
    try {
        $validatedRoot = Assert-CddsiRealtimeRelayOwnedStateRootReadOnlyInternal -StateRoot $StateRoot `
            -RunId $RunId -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
        Assert-CddsiRealtimeRelayCredentialArtifactsCurrentInternal -StateRoot $validatedRoot
        $credentialPath = [IO.Path]::Combine($validatedRoot, $script:CddsiRealtimeCredentialFileName)
        $loaded = Read-CddsiRealtimeRelayCredentialBlobInternal -CredentialPath $credentialPath `
            -ClientId $ClientId -Environment $Environment -KeyId $KeyId `
            -StateRootBindingToken $StateRootBindingToken
        if ($loaded.CredentialBlobSha256 -cne $ExpectedCredentialBlobSha256) {
            throw 'REALTIME_CREDENTIAL_BLOB_DRIFT'
        }
        $protectedBytes = [Convert]::FromBase64String($loaded.CredentialBlob.ProtectedSecretBase64)
        $entropyBytes = [byte[]](Get-CddsiRealtimeRelayCredentialEntropyInternal `
                -ClientId $ClientId -Environment $Environment -KeyId $KeyId `
                -StateRootBindingToken $StateRootBindingToken)
        $secretBytes = [byte[]](Unprotect-CddsiRealtimeRelaySecretCurrentUserInternal `
                -ProtectedBytes $protectedBytes -EntropyBytes $entropyBytes)
        if ($null -eq $secretBytes -or $secretBytes.Length -ne 32) {
            throw 'REALTIME_CREDENTIAL_SECRET_LENGTH_INVALID'
        }
        if ($Operation -ceq 'Validate') {
            return $true
        }
        if ([Text.UTF8Encoding]::new($false, $true).GetByteCount($CanonicalRequest) -gt 4096) {
            throw 'REALTIME_CANONICAL_REQUEST_INVALID'
        }
        return Get-CddsiRealtimeRelayHmacInternal -SecretBytes $secretBytes `
            -CanonicalRequest $CanonicalRequest
    }
    catch {
        throw 'REALTIME_CREDENTIAL_UNAVAILABLE'
    }
    finally {
        if ($null -ne $secretBytes) {
            [Array]::Clear($secretBytes, 0, $secretBytes.Length)
        }
        if ($null -ne $entropyBytes) {
            [Array]::Clear($entropyBytes, 0, $entropyBytes.Length)
        }
        if ($null -ne $protectedBytes) {
            [Array]::Clear($protectedBytes, 0, $protectedBytes.Length)
        }
    }
}

function Get-CddsiRealtimeRelayCredentialBindingTokenInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId,
        [Parameter(Mandatory = $true)][string]$StateRootBindingToken,
        [Parameter(Mandatory = $true)][string]$CredentialBlobSha256,
        [Parameter(Mandatory = $true)][string]$ClientAdapterSha256
    )

    return Get-CddsiRealtimeRelayTextSha256Internal -Text (
        'cddsi-realtime-relay-credential-binding-v2|{0}|{1}|{2}|{3}|{4}|{5}' -f `
            $ClientId, $Environment, $KeyId, $StateRootBindingToken, $CredentialBlobSha256,
            $ClientAdapterSha256
    )
}

function New-CddsiRealtimeRelayDpapiCredentialProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$StateRoot,
        [Parameter(Mandatory = $true)][string]$RunId,
        [Parameter(Mandatory = $true)][string]$OwnerSid,
        [Parameter(Mandatory = $true)][string]$OwnershipTokenSha256,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId
    )

    if ($Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
        $KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$') {
        throw 'REALTIME_CREDENTIAL_AUTH_SCOPE_INVALID'
    }

    $fullPath = Assert-CddsiRealtimeRelayOwnedStateRootReadOnlyInternal -StateRoot $StateRoot `
        -RunId $RunId -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
    Assert-CddsiRealtimeRelayCredentialArtifactsCurrentInternal -StateRoot $fullPath
    $stateRootBindingToken = Get-CddsiRealtimeRelayStateBindingTokenInternal -StateRoot $fullPath `
        -OwnerSid $OwnerSid -OwnershipTokenSha256 $OwnershipTokenSha256
    $credentialPath = [IO.Path]::Combine($fullPath, $script:CddsiRealtimeCredentialFileName)
    $loaded = Read-CddsiRealtimeRelayCredentialBlobInternal -CredentialPath $credentialPath `
        -ClientId $ClientId -Environment $Environment -KeyId $KeyId `
        -StateRootBindingToken $stateRootBindingToken
    $credentialBlobSha256 = $loaded.CredentialBlobSha256
    $clientAdapterSha256 = Get-CddsiRealtimeRelayClientAdapterSha256Internal
    $bindingToken = Get-CddsiRealtimeRelayCredentialBindingTokenInternal -ClientId $ClientId `
        -Environment $Environment -KeyId $KeyId `
        -StateRootBindingToken $stateRootBindingToken -CredentialBlobSha256 $credentialBlobSha256 `
        -ClientAdapterSha256 $clientAdapterSha256
    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeCredentialProviderSchema
        StorageKind = 'DPAPI_CURRENT_USER'
        ClientId = $ClientId
        Environment = $Environment
        KeyId = $KeyId
        CredentialFileName = $script:CddsiRealtimeCredentialFileName
        StateRoot = $fullPath
        RunId = $RunId
        OwnerSid = $OwnerSid
        OwnershipTokenSha256 = $OwnershipTokenSha256
        StateRootBindingToken = $stateRootBindingToken
        CredentialBlobSha256 = $credentialBlobSha256
        BindingToken = $bindingToken
        ClientAdapterSha256 = $clientAdapterSha256
    }
}

function Test-CddsiRealtimeRelayCredentialProviderContractInternal {
    param(
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$StateRootBindingToken,
        [switch]$VerifySource
    )

    try {
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $CredentialProvider `
                -ExpectedProperties $script:CddsiRealtimeCredentialProviderProperties) -or
            $CredentialProvider.SchemaVersion -cne $script:CddsiRealtimeCredentialProviderSchema -or
            $CredentialProvider.StorageKind -cne 'DPAPI_CURRENT_USER' -or
            $CredentialProvider.ClientId -cne $ClientId -or
            $CredentialProvider.Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
            $CredentialProvider.KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$' -or
            $CredentialProvider.CredentialFileName -cne $script:CddsiRealtimeCredentialFileName -or
            $CredentialProvider.RunId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $CredentialProvider.OwnerSid -cnotmatch '^S-1-[0-9-]+$' -or
            $CredentialProvider.OwnershipTokenSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            -not [IO.Path]::IsPathRooted([string]$CredentialProvider.StateRoot) -or
            [IO.Path]::GetFullPath([string]$CredentialProvider.StateRoot) -cne $CredentialProvider.StateRoot -or
            [IO.DirectoryInfo]::new([string]$CredentialProvider.StateRoot).Name -cne
            ('cddsi-realtime-relay-' + $CredentialProvider.RunId) -or
            $CredentialProvider.StateRootBindingToken -cne $StateRootBindingToken -or
            $CredentialProvider.CredentialBlobSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $CredentialProvider.BindingToken -cnotmatch '^[0-9a-f]{64}$' -or
            $CredentialProvider.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$') {
            return $false
        }
        $currentSid = [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
        if ($CredentialProvider.OwnerSid -cne $currentSid -or
            (Get-CddsiRealtimeRelayStateBindingTokenInternal -StateRoot $CredentialProvider.StateRoot `
                -OwnerSid $CredentialProvider.OwnerSid `
                -OwnershipTokenSha256 $CredentialProvider.OwnershipTokenSha256) -cne
            $CredentialProvider.StateRootBindingToken) {
            return $false
        }
        $expectedBinding = Get-CddsiRealtimeRelayCredentialBindingTokenInternal -ClientId $ClientId `
            -Environment $CredentialProvider.Environment -KeyId $CredentialProvider.KeyId `
            -StateRootBindingToken $StateRootBindingToken `
            -CredentialBlobSha256 $CredentialProvider.CredentialBlobSha256 `
            -ClientAdapterSha256 $CredentialProvider.ClientAdapterSha256
        if ($CredentialProvider.BindingToken -cne $expectedBinding) {
            return $false
        }
        if ($VerifySource -and
            (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -cne
            $CredentialProvider.ClientAdapterSha256) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal {
    param(
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)][ValidateSet('Validate', 'Sign')][string]$Operation,
        [AllowEmptyString()][string]$CanonicalRequest = ''
    )

    if (-not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $CredentialProvider -ClientId $CredentialProvider.ClientId `
            -StateRootBindingToken $CredentialProvider.StateRootBindingToken -VerifySource)) {
        throw 'REALTIME_CREDENTIAL_PROVIDER_INVALID'
    }
    return Invoke-CddsiRealtimeRelayDpapiCredentialOperationInternal `
        -StateRoot $CredentialProvider.StateRoot -RunId $CredentialProvider.RunId `
        -OwnerSid $CredentialProvider.OwnerSid `
        -OwnershipTokenSha256 $CredentialProvider.OwnershipTokenSha256 `
        -ClientId $CredentialProvider.ClientId -Environment $CredentialProvider.Environment `
        -KeyId $CredentialProvider.KeyId `
        -StateRootBindingToken $CredentialProvider.StateRootBindingToken `
        -ExpectedCredentialBlobSha256 $CredentialProvider.CredentialBlobSha256 `
        -Operation $Operation -CanonicalRequest $CanonicalRequest
}

function Get-CddsiRealtimeRelayHmacInternal {
    param(
        [Parameter(Mandatory = $true)][byte[]]$SecretBytes,
        [Parameter(Mandatory = $true)][string]$CanonicalRequest
    )

    if ($SecretBytes.Length -ne 32) {
        throw 'REALTIME_SECRET_LENGTH_INVALID'
    }
    $hmac = [Security.Cryptography.HMACSHA256]::new($SecretBytes)
    try {
        return ([BitConverter]::ToString($hmac.ComputeHash(
                    [Text.UTF8Encoding]::new($false, $true).GetBytes($CanonicalRequest)
                ))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $hmac.Dispose()
    }
}

function New-CddsiRealtimeRelayCanonicalRequestInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Environment,
        [Parameter(Mandatory = $true)][string]$KeyId,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$CanonicalTarget,
        [Parameter(Mandatory = $true)][string]$Timestamp,
        [Parameter(Mandatory = $true)][string]$Nonce,
        [Parameter(Mandatory = $true)][string]$BodySha256
    )

    $parsedTimestamp = [DateTimeOffset]::MinValue
    if ($Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
        $KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$' -or
        $CanonicalTarget -cnotmatch '^/v1/[a-z0-9][a-z0-9/?&=.-]{0,255}$' -or
        -not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $Timestamp -Parsed ([ref]$parsedTimestamp)) -or
        $Nonce -cnotmatch '^[A-Za-z0-9_-]{43}$' -or
        $BodySha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'REALTIME_CANONICAL_REQUEST_INVALID'
    }
    return @(
        'CDDsi-HMAC-SHA256-v2', $script:CddsiRealtimeAuthAudience, $Environment, $KeyId,
        $ClientId, $Method, $CanonicalTarget, $Timestamp, $Nonce, $BodySha256
    ) -join "`n"
}

function New-CddsiRealtimeRelayAuthHeadersInternal {
    param(
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateSet('GET', 'POST')][string]$Method,
        [Parameter(Mandatory = $true)][string]$CanonicalTarget,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Body,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc,
        [Parameter(Mandatory = $true, ParameterSetName = 'CredentialProvider')]$CredentialProvider,
        [Parameter(Mandatory = $true, ParameterSetName = 'SyntheticResolver')][scriptblock]$SecretResolver,
        [Parameter(Mandatory = $true, ParameterSetName = 'SyntheticResolver')][string]$Environment,
        [Parameter(Mandatory = $true, ParameterSetName = 'SyntheticResolver')][string]$KeyId
    )

    $timestamp = $NowUtc.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
    $nonce = Get-CddsiRealtimeRelayRandomNonceInternal
    $bodySha256 = Get-CddsiRealtimeRelayTextSha256Internal -Text $Body
    if ($PSCmdlet.ParameterSetName -ceq 'CredentialProvider') {
        if ($null -eq $CredentialProvider -or
            $null -eq $CredentialProvider.PSObject.Properties['StateRootBindingToken'] -or
            -not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
                -CredentialProvider $CredentialProvider -ClientId $ClientId `
                -StateRootBindingToken $CredentialProvider.StateRootBindingToken -VerifySource)) {
            throw 'REALTIME_CREDENTIAL_PROVIDER_INVALID'
        }
        $Environment = [string]$CredentialProvider.Environment
        $KeyId = [string]$CredentialProvider.KeyId
    }
    $canonical = New-CddsiRealtimeRelayCanonicalRequestInternal -Environment $Environment `
        -KeyId $KeyId -ClientId $ClientId -Method $Method -CanonicalTarget $CanonicalTarget `
        -Timestamp $timestamp -Nonce $nonce -BodySha256 $bodySha256
    if ($PSCmdlet.ParameterSetName -ceq 'CredentialProvider') {
        $signature = Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal `
            -CredentialProvider $CredentialProvider -Operation Sign -CanonicalRequest $canonical
        if ($signature -isnot [string] -or $signature -cnotmatch '^[0-9a-f]{64}$') {
            throw 'REALTIME_CREDENTIAL_SIGNATURE_INVALID'
        }
    }
    else {
        $resolvedSecret = @(& $SecretResolver)
        $secret = $null
        try {
            if ($resolvedSecret.Count -ne 32 -or
                @($resolvedSecret | Where-Object { $_ -isnot [byte] }).Count -ne 0) {
                throw 'REALTIME_SECRET_RESOLVER_INVALID'
            }
            $secret = [byte[]]::new(32)
            for ($index = 0; $index -lt $secret.Length; $index++) {
                $secret[$index] = [byte]$resolvedSecret[$index]
            }
            $signature = Get-CddsiRealtimeRelayHmacInternal -SecretBytes $secret -CanonicalRequest $canonical
        }
        finally {
            if ($null -ne $secret) {
                [Array]::Clear($secret, 0, $secret.Length)
            }
            [Array]::Clear($resolvedSecret, 0, $resolvedSecret.Length)
        }
    }
    return [pscustomobject][ordered]@{
        'x-cddsi-audience' = $script:CddsiRealtimeAuthAudience
        'x-cddsi-environment' = $Environment
        'x-cddsi-key-id' = $KeyId
        'x-cddsi-client-id' = $ClientId
        'x-cddsi-timestamp' = $timestamp
        'x-cddsi-nonce' = $nonce
        'x-cddsi-body-sha256' = $bodySha256
        'x-cddsi-signature' = $signature
    }
}

function Test-CddsiRealtimeRelayLiveEndpointInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint
    )

    try {
        $uri = [uri]$Endpoint
        return $uri.IsAbsoluteUri -and $uri.Scheme -ceq 'wss' -and
        $uri.AbsolutePath -ceq '/' -and $uri.Query.Length -eq 0 -and
        $uri.Fragment.Length -eq 0 -and $uri.UserInfo.Length -eq 0 -and
        $uri.IsDefaultPort -and $uri.Port -eq 443 -and
        $uri.Host -cmatch '^[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev$' -and
        $uri.AbsoluteUri -ceq $Endpoint
    }
    catch {
        return $false
    }
}

function Get-CddsiRealtimeRelayLiveTransportBindingTokenInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Endpoint,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)][string]$SessionId,
        [Parameter(Mandatory = $true)][string]$ClientAdapterSha256
    )

    return Get-CddsiRealtimeRelayTextSha256Internal -Text (
        'cddsi-realtime-relay-live-transport-binding-v1|{0}|{1}|{2}|{3}' -f `
            $Endpoint, $ClientId, $SessionId, $ClientAdapterSha256
    )
}

function Test-CddsiRealtimeRelayLiveTransportProviderContractInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider,
        [switch]$VerifySource,
        [switch]$VerifySession
    )

    try {
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $TransportProvider `
                -ExpectedProperties $script:CddsiRealtimeLiveTransportProviderProperties) -or
            $TransportProvider.SchemaVersion -cne $script:CddsiRealtimeLiveTransportProviderSchema -or
            $TransportProvider.ProviderKind -cne 'STATIC_WEBSOCKET_HTTP' -or
            @('host-coordinator-v1', 'vm-tester-v1') -cnotcontains $TransportProvider.ClientId -or
            $TransportProvider.SessionId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $TransportProvider.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $TransportProvider.BindingToken -cnotmatch '^[0-9a-f]{64}$' -or
            -not (Test-CddsiRealtimeRelayLiveEndpointInternal -Endpoint $TransportProvider.Endpoint)) {
            return $false
        }
        $expectedBinding = Get-CddsiRealtimeRelayLiveTransportBindingTokenInternal `
            -Endpoint $TransportProvider.Endpoint -ClientId $TransportProvider.ClientId `
            -SessionId $TransportProvider.SessionId `
            -ClientAdapterSha256 $TransportProvider.ClientAdapterSha256
        if ($TransportProvider.BindingToken -cne $expectedBinding) {
            return $false
        }
        if ($VerifySource -and
            (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -cne
            $TransportProvider.ClientAdapterSha256) {
            return $false
        }
        if ($VerifySession -and -not $script:CddsiRealtimeLiveSessions.ContainsKey(
                [string]$TransportProvider.SessionId
            )) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Test-CddsiRealtimeRelayLiveClockProviderContractInternal {
    param(
        [Parameter(Mandatory = $true)]$ClockProvider,
        [switch]$VerifySource
    )

    try {
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $ClockProvider `
                -ExpectedProperties $script:CddsiRealtimeLiveClockProviderProperties) -or
            $ClockProvider.SchemaVersion -cne $script:CddsiRealtimeLiveClockProviderSchema -or
            $ClockProvider.ProviderKind -cne 'STATIC_SYSTEM_CLOCK' -or
            $ClockProvider.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$') {
            return $false
        }
        if ($VerifySource -and
            (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -cne
            $ClockProvider.ClientAdapterSha256) {
            return $false
        }
        return $true
    }
    catch {
        return $false
    }
}

function Get-CddsiRealtimeRelayLiveUtcNowInternal {
    param(
        [Parameter(Mandatory = $true)]$ClockProvider
    )

    if (-not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $ClockProvider -VerifySource)) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    return [DateTimeOffset]::UtcNow
}

function Get-CddsiRealtimeRelayLiveJitterMillisecondsInternal {
    param(
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][ValidateRange(0, 1000)][int]$Maximum
    )

    if (-not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $ClockProvider -VerifySource)) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    return [Security.Cryptography.RandomNumberGenerator]::GetInt32(0, $Maximum + 1)
}

function Invoke-CddsiRealtimeRelayLiveDelayInternal {
    param(
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][ValidateRange(0, 60000)][int]$Milliseconds
    )

    if (-not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $ClockProvider -VerifySource)) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    [Threading.Thread]::Sleep($Milliseconds)
}

function Get-CddsiRealtimeRelayLiveSessionInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider
    )

    if (-not (Test-CddsiRealtimeRelayLiveTransportProviderContractInternal `
            -TransportProvider $TransportProvider -VerifySource -VerifySession)) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    $session = $script:CddsiRealtimeLiveSessions[[string]$TransportProvider.SessionId]
    if ($null -eq $session -or $session.ClientId -cne $TransportProvider.ClientId -or
        $session.Endpoint -cne $TransportProvider.Endpoint -or
        $session.BindingToken -cne $TransportProvider.BindingToken -or
        ($session.OperatorRelayNetworkRequestCount -isnot [int] -and
            $session.OperatorRelayNetworkRequestCount -isnot [long]) -or
        [long]$session.OperatorRelayNetworkRequestCount -lt 0 -or
        ($session.OperatorGitInvocationCount -isnot [int] -and
            $session.OperatorGitInvocationCount -isnot [long]) -or
        ($session.OperatorGitTransportCount -isnot [int] -and
            $session.OperatorGitTransportCount -isnot [long]) -or
        ($session.OperatorLocalStateMutationCount -isnot [int] -and
            $session.OperatorLocalStateMutationCount -isnot [long]) -or
        ($session.OperatorCodexProcessSpawnCount -isnot [int] -and
            $session.OperatorCodexProcessSpawnCount -isnot [long]) -or
        ($session.FixedWakeEffectCount -isnot [int] -and
            $session.FixedWakeEffectCount -isnot [long]) -or
        [long]$session.OperatorGitInvocationCount -lt 0 -or
        [long]$session.OperatorGitTransportCount -lt 0 -or
        [long]$session.OperatorLocalStateMutationCount -lt 0 -or
        [long]$session.OperatorCodexProcessSpawnCount -lt 0 -or
        [long]$session.FixedWakeEffectCount -lt 0 -or
        $session.PersistentChangeObserved -isnot [bool]) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    return $session
}

function Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal {
    param(
        [Parameter(Mandatory = $true)]$RelayContext
    )

    $contextSessionIds = @()
    foreach ($key in @($script:CddsiRealtimeLiveSessions.Keys)) {
        $session = $script:CddsiRealtimeLiveSessions[$key]
        try {
            if ($key -cmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -and
                $null -ne $session -and $null -ne $session.PSObject -and
                $null -ne $session.PSObject.Properties['ContextReference'] -and
                $null -ne $session.ContextReference -and
                [object]::ReferenceEquals(
                    $session.ContextReference.PSObject,
                    $RelayContext.PSObject
                )) {
                $contextSessionIds += [string]$key
            }
        }
        catch {
            # A malformed unrelated table entry never becomes cleanup authority.
        }
    }
    if ($contextSessionIds.Count -eq 1) {
        return $contextSessionIds[0]
    }
    return $null
}

function Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal {
    param(
        [Parameter(Mandatory = $true)][string]$SessionId
    )

    $zero = [pscustomobject][ordered]@{
        OperatorRelayNetworkRequestCount = 0L
        OperatorGitInvocationCount = 0L
        OperatorGitTransportCount = 0L
        OperatorLocalStateMutationCount = 0L
        OperatorCodexProcessSpawnCount = 0L
        FixedWakeEffectCount = 0L
        PersistentChangeObserved = $false
    }
    if ($SessionId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        -not $script:CddsiRealtimeLiveSessions.ContainsKey($SessionId)) {
        return $zero
    }
    $session = $script:CddsiRealtimeLiveSessions[$SessionId]
    try {
        foreach ($name in @(
                'OperatorRelayNetworkRequestCount', 'OperatorGitInvocationCount',
                'OperatorGitTransportCount', 'OperatorLocalStateMutationCount',
                'OperatorCodexProcessSpawnCount', 'FixedWakeEffectCount'
            )) {
            if (($session.$name -isnot [int] -and $session.$name -isnot [long]) -or
                [long]$session.$name -lt 0) {
                return $zero
            }
        }
        if ($session.PersistentChangeObserved -isnot [bool]) {
            return $zero
        }
        return [pscustomobject][ordered]@{
            OperatorRelayNetworkRequestCount = [long]$session.OperatorRelayNetworkRequestCount
            OperatorGitInvocationCount = [long]$session.OperatorGitInvocationCount
            OperatorGitTransportCount = [long]$session.OperatorGitTransportCount
            OperatorLocalStateMutationCount = [long]$session.OperatorLocalStateMutationCount
            OperatorCodexProcessSpawnCount = [long]$session.OperatorCodexProcessSpawnCount
            FixedWakeEffectCount = [long]$session.FixedWakeEffectCount
            PersistentChangeObserved = [bool]$session.PersistentChangeObserved
        }
    }
    catch {
        return $zero
    }
}

function Get-CddsiRealtimeRelayOperatorNetworkRequestCountInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider
    )

    try {
        $session = Get-CddsiRealtimeRelayLiveSessionInternal -TransportProvider $TransportProvider
        return [long]$session.OperatorRelayNetworkRequestCount
    }
    catch {
        return 0L
    }
}

function Get-CddsiRealtimeRelayOperatorNetworkRequestCountBySessionIdInternal {
    param(
        [Parameter(Mandatory = $true)][string]$SessionId
    )

    if ($SessionId -cnotmatch '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        -not $script:CddsiRealtimeLiveSessions.ContainsKey($SessionId)) {
        return 0L
    }
    $session = $script:CddsiRealtimeLiveSessions[$SessionId]
    if ($null -eq $session -or
        ($session.OperatorRelayNetworkRequestCount -isnot [int] -and
            $session.OperatorRelayNetworkRequestCount -isnot [long]) -or
        [long]$session.OperatorRelayNetworkRequestCount -lt 0) {
        return 0L
    }
    return [long]$session.OperatorRelayNetworkRequestCount
}

function Close-CddsiRealtimeRelayTrustedLiveSessionInternal {
    param(
        [Parameter(Mandatory = $true)][string]$TrustedSessionId
    )

    if ($TrustedSessionId -cnotmatch
        '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
        -not $script:CddsiRealtimeLiveSessions.ContainsKey($TrustedSessionId)) {
        return
    }
    $session = $script:CddsiRealtimeLiveSessions[$TrustedSessionId]
    try {
        $socket = $null
        try {
            if ($null -ne $session -and $null -ne $session.PSObject -and
                $null -ne $session.PSObject.Properties['Socket']) {
                $socket = $session.Socket
            }
        }
        catch {
            $socket = $null
        }
        if ($null -ne $socket) {
            try {
                $socket.Abort()
            }
            catch {
                # A trusted cleanup never copies or exposes socket exception text.
            }
            try {
                $socket.Dispose()
            }
            catch {
                # Disposal remains best-effort; the exact session is still removed below.
            }
            try {
                $session.Socket = $null
            }
            catch {
                # The internal table entry is removed even if its shape was corrupted.
            }
        }
    }
    finally {
        [void]$script:CddsiRealtimeLiveSessions.Remove($TrustedSessionId)
    }
}

function Assert-CddsiRealtimeRelayLiveAuthorizationCurrentInternal {
    param(
        [Parameter(Mandatory = $true)]$RelayContext,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$RuntimeAssertion
    )

    if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RelayContext `
            -ExpectedProperties $script:CddsiRealtimeLiveContextProperties) -or
        -not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RelayContext.Providers `
            -ExpectedProperties $script:CddsiRealtimeLiveProviderSetProperties) -or
        $RelayContext.SchemaVersion -cne $script:CddsiRealtimeContextSchema -or
        $RelayContext.Mode -cne 'Live' -or $RelayContext.ProviderKind -cne 'Live' -or
        $RelayContext.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -cne
        $RelayContext.ClientAdapterSha256 -or
        -not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RuntimeAssertion `
            -ExpectedProperties $script:CddsiRealtimeLiveAssertionProperties)) {
        throw 'REALTIME_RUNTIME_ASSERTION_INVALID'
    }
    if ($RuntimeAssertion.SchemaVersion -cne $script:CddsiRealtimeAssertionSchema -or
        $RuntimeAssertion.Status -cne 'AUTHORIZED' -or $RuntimeAssertion.Lane -cne $Lane -or
        $RuntimeAssertion.CredentialStorageKind -cne 'DPAPI_CURRENT_USER' -or
        $RuntimeAssertion.WakeAdapterId -cne 'cddsi-fast-lane-fixed-resume-v1' -or
        $RuntimeAssertion.Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
        $RuntimeAssertion.KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$' -or
        $RuntimeAssertion.ClientAdapterSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'REALTIME_RUNTIME_ASSERTION_INVALID'
    }
    $issued = [DateTimeOffset]::MinValue
    $expires = [DateTimeOffset]::MinValue
    if (-not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $RuntimeAssertion.IssuedAtUtc `
            -Parsed ([ref]$issued)) -or
        -not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $RuntimeAssertion.ExpiresAtUtc `
            -Parsed ([ref]$expires)) -or $expires -le $issued -or
        ($expires - $issued).TotalSeconds -gt $script:CddsiRealtimeMaxAssertionLifetimeSeconds) {
        throw 'REALTIME_RUNTIME_ASSERTION_INVALID'
    }
    $providers = $RelayContext.Providers
    if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $providers.State -VerifySource) -or
        -not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $providers.Credential -ClientId $RelayContext.ClientId `
            -StateRootBindingToken $providers.State.BindingToken -VerifySource) -or
        -not (Test-CddsiRealtimeRelayFixedWakeProviderContractInternal `
            -WakeProvider $providers.Wake -Lane $Lane -ClientId $RelayContext.ClientId `
            -VerifySource) -or
        -not (Test-CddsiRealtimeRelayLiveTransportProviderContractInternal `
            -TransportProvider $providers.Transport -VerifySource -VerifySession) -or
        -not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $providers.Clock -VerifySource)) {
        throw 'REALTIME_RUNTIME_BINDING_MISMATCH'
    }
    $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
    if ($RuntimeAssertion.ClientId -cne $policy.ReaderClientId -or
        $RelayContext.ClientId -cne $RuntimeAssertion.ClientId -or
        $RelayContext.Endpoint -cne $RuntimeAssertion.Endpoint -or
        $providers.Transport.Endpoint -cne $RuntimeAssertion.Endpoint -or
        $providers.Transport.ClientId -cne $RuntimeAssertion.ClientId -or
        $providers.State.BindingToken -cne $RuntimeAssertion.StateRootBindingToken -or
        $providers.Credential.StorageKind -cne $RuntimeAssertion.CredentialStorageKind -or
        $providers.Credential.BindingToken -cne $RuntimeAssertion.CredentialBindingToken -or
        $providers.Credential.Environment -cne $RuntimeAssertion.Environment -or
        $providers.Credential.KeyId -cne $RuntimeAssertion.KeyId -or
        $providers.Wake.AdapterId -cne $RuntimeAssertion.WakeAdapterId -or
        $providers.Wake.AdapterSha256 -cne $RuntimeAssertion.WakeAdapterSha256 -or
        $providers.Wake.BindingSha256 -cne $RuntimeAssertion.WakeBindingSha256 -or
        $providers.Wake.GitOutboxRunnerSha256 -cne $RuntimeAssertion.GitOutboxRunnerSha256 -or
        $providers.Wake.CodexResumeBindingSha256 -cne
        $RuntimeAssertion.CodexResumeBindingSha256 -or
        $RelayContext.ClientAdapterSha256 -cne $RuntimeAssertion.ClientAdapterSha256 -or
        $providers.State.ClientAdapterSha256 -cne $RuntimeAssertion.ClientAdapterSha256 -or
        $providers.Credential.ClientAdapterSha256 -cne $RuntimeAssertion.ClientAdapterSha256 -or
        $providers.Transport.ClientAdapterSha256 -cne $RuntimeAssertion.ClientAdapterSha256 -or
        $providers.Clock.ClientAdapterSha256 -cne $RuntimeAssertion.ClientAdapterSha256) {
        throw 'REALTIME_RUNTIME_BINDING_MISMATCH'
    }
    $now = Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $providers.Clock
    if ($issued -gt $now -or $expires -le $now) {
        throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
    }
    return $expires
}

function Close-CddsiRealtimeRelayWebSocketSessionInternal {
    param(
        [Parameter(Mandatory = $true)]$Session
    )

    if ($null -ne $Session.Socket) {
        try {
            $Session.Socket.Abort()
        }
        finally {
            $Session.Socket.Dispose()
            $Session.Socket = $null
        }
    }
}

function Invoke-CddsiRealtimeRelayWebSocketReceiveInternal {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][uri]$Endpoint,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][long]$After,
        [Parameter(Mandatory = $true)][int]$MaxMessages,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    $target = '/v1/watch?after={0}&lane={1}' -f $After, $Lane
    $builder = [UriBuilder]::new($Endpoint)
    $builder.Path = '/v1/watch'
    $builder.Query = 'after={0}&lane={1}' -f $After, $Lane
    $receiveTimeout = $null
    $receiveWindowWasIdleBudget = $false
    $receiveCancellationObserved = $false
    try {
        if ($null -eq $Session.Socket -or
            $Session.Socket.State -ne [Net.WebSockets.WebSocketState]::Open) {
            Close-CddsiRealtimeRelayWebSocketSessionInternal -Session $Session
            if ($AuthorizationExpiresAtUtc -le
                (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
                throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
            }
            $headers = New-CddsiRealtimeRelayAuthHeadersInternal -ClientId $ClientId -Method GET `
                -CanonicalTarget $target -Body '' -NowUtc $NowUtc -CredentialProvider $CredentialProvider
            $socket = [Net.WebSockets.ClientWebSocket]::new()
            try {
                $socket.Options.UseDefaultCredentials = $false
                $socket.Options.Proxy = $null
                $socket.Options.KeepAliveInterval = [TimeSpan]::FromSeconds(20)
                foreach ($property in $headers.PSObject.Properties) {
                    $socket.Options.SetRequestHeader($property.Name, [string]$property.Value)
                }
                $connectRemaining = $AuthorizationExpiresAtUtc -
                (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)
                if ($connectRemaining.TotalMilliseconds -le 0) {
                    throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
                }
                $connectWindow = [TimeSpan]::FromSeconds([Math]::Min(30, $connectRemaining.TotalSeconds))
                $connectTimeout = [Threading.CancellationTokenSource]::new($connectWindow)
                try {
                    $Session.OperatorRelayNetworkRequestCount =
                    [long]$Session.OperatorRelayNetworkRequestCount + 1
                    [void]$socket.ConnectAsync(
                        $builder.Uri,
                        $connectTimeout.Token
                    ).GetAwaiter().GetResult()
                }
                finally {
                    $connectTimeout.Dispose()
                }
                $Session.Socket = $socket
            }
            catch {
                $socket.Dispose()
                throw
            }
        }
        $remaining = $AuthorizationExpiresAtUtc -
        (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)
        if ($remaining.TotalMilliseconds -le 0) {
            throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        }
        $receiveWindow = [TimeSpan]::FromSeconds([Math]::Min(60, $remaining.TotalSeconds))
        $receiveWindowWasIdleBudget = $remaining.TotalSeconds -ge 60
        $receiveTimeout = [Threading.CancellationTokenSource]::new($receiveWindow)
        $messageStream = [IO.MemoryStream]::new($script:CddsiRealtimeMaxBodyBytes)
        try {
            do {
                if ($AuthorizationExpiresAtUtc -le
                    (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
                    throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
                }
                $buffer = [byte[]]::new(1024)
                $segment = [ArraySegment[byte]]::new($buffer)
                $Session.OperatorRelayNetworkRequestCount =
                [long]$Session.OperatorRelayNetworkRequestCount + 1
                $result = $Session.Socket.ReceiveAsync(
                    $segment,
                    $receiveTimeout.Token
                ).GetAwaiter().GetResult()
                if ($result.MessageType -eq [Net.WebSockets.WebSocketMessageType]::Close) {
                    if ($messageStream.Length -ne 0) {
                        throw 'REALTIME_WEBSOCKET_FRAME_INVALID'
                    }
                    Close-CddsiRealtimeRelayWebSocketSessionInternal -Session $Session
                    return [pscustomobject][ordered]@{
                        Status = 'Disconnected'
                        Messages = @()
                        Code = 'REALTIME_WEBSOCKET_REMOTE_CLOSE'
                    }
                }
                if ($result.MessageType -ne [Net.WebSockets.WebSocketMessageType]::Text -or
                    ($messageStream.Length + $result.Count) -gt $script:CddsiRealtimeMaxBodyBytes) {
                    throw 'REALTIME_WEBSOCKET_FRAME_INVALID'
                }
                if ($result.Count -gt 0) {
                    $messageStream.Write($buffer, 0, $result.Count)
                }
            } while (-not $result.EndOfMessage)
            $message = [Text.UTF8Encoding]::new($false, $true).GetString($messageStream.ToArray())
        }
        catch {
            if ($null -ne $receiveTimeout) {
                $receiveCancellationObserved = $receiveTimeout.IsCancellationRequested
            }
            if ($_.Exception.Message -ceq 'REALTIME_WEBSOCKET_FRAME_INVALID') {
                throw
            }
            if ($_.Exception -is [Text.DecoderFallbackException]) {
                throw 'REALTIME_WEBSOCKET_UTF8_INVALID'
            }
            throw
        }
        finally {
            $messageStream.Dispose()
            $receiveTimeout.Dispose()
        }
        return [pscustomobject][ordered]@{ Status = 'Connected'; Messages = @($message) }
    }
    catch {
        if ($receiveWindowWasIdleBudget -and $receiveCancellationObserved -and
            $_.Exception -is [OperationCanceledException] -and
            $null -ne $Session.Socket -and
            $Session.Socket.State -eq [Net.WebSockets.WebSocketState]::Open -and
            $AuthorizationExpiresAtUtc -gt
            (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
            return [pscustomobject][ordered]@{
                Status = 'Connected'
                Messages = @()
                Code = 'REALTIME_WEBSOCKET_IDLE'
            }
        }
        Close-CddsiRealtimeRelayWebSocketSessionInternal -Session $Session
        if ($_.Exception.Message -ceq 'REALTIME_RUNTIME_ASSERTION_EXPIRED') {
            throw
        }
        return [pscustomobject][ordered]@{ Status = 'Disconnected'; Messages = @(); Code = 'REALTIME_TRANSPORT_DISCONNECTED' }
    }
}

function Invoke-CddsiRealtimeRelayAckInternal {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][uri]$Endpoint,
        [Parameter(Mandatory = $true)][string]$ClientId,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    if ($AuthorizationExpiresAtUtc -le
        (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
        throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
    }
    $headers = New-CddsiRealtimeRelayAuthHeadersInternal -ClientId $ClientId -Method POST `
        -CanonicalTarget '/v1/ack' -Body $Body -NowUtc $NowUtc -CredentialProvider $CredentialProvider
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseDefaultCredentials = $false
    $handler.UseProxy = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $client.MaxResponseContentBufferSize = 4096
    $builder = [UriBuilder]::new($Endpoint)
    $builder.Scheme = 'https'
    $builder.Port = -1
    $builder.Path = '/v1/ack'
    $builder.Query = ''
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $builder.Uri)
    $request.Content = [Net.Http.StringContent]::new($Body, [Text.UTF8Encoding]::new($false), 'application/json')
    foreach ($property in $headers.PSObject.Properties) {
        [void]$request.Headers.TryAddWithoutValidation($property.Name, [string]$property.Value)
    }
    try {
        if ($AuthorizationExpiresAtUtc -le
            (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
            throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
        }
        $Session.OperatorRelayNetworkRequestCount =
        [long]$Session.OperatorRelayNetworkRequestCount + 1
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            if ([int]$response.StatusCode -ne 200 -or $null -eq $response.Content.Headers.ContentType -or
                $response.Content.Headers.ContentType.MediaType -cne 'application/json') {
                return [pscustomobject][ordered]@{ Accepted = $false }
            }
            $rawResponse = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ([Text.UTF8Encoding]::new($false, $true).GetByteCount($rawResponse) -gt 4096) {
                return [pscustomobject][ordered]@{ Accepted = $false }
            }
            $responseKeyMatches = @([regex]::Matches($rawResponse, '"([A-Za-z][A-Za-z0-9]*)":'))
            $responseKeyNames = @($responseKeyMatches | ForEach-Object { $_.Groups[1].Value })
            if ($responseKeyMatches.Count -ne 6 -or
                @($responseKeyNames | Sort-Object -Unique).Count -ne 6) {
                return [pscustomobject][ordered]@{ Accepted = $false }
            }
            try {
                $ackRequest = ConvertFrom-Json -InputObject $Body -ErrorAction Stop
                $ackResponse = ConvertFrom-Json -InputObject $rawResponse -ErrorAction Stop
            }
            catch {
                return [pscustomobject][ordered]@{ Accepted = $false }
            }
            if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $ackResponse `
                    -Expected @('Schema', 'Status', 'Code', 'Lane', 'Sequence', 'MessageId')) -or
                $ackResponse.Schema -cne 'cddsi-relay-response-v1' -or
                $ackResponse.Status -cne 'OK' -or
                @('ACKED', 'ACK_IDEMPOTENT') -cnotcontains $ackResponse.Code -or
                $ackResponse.Lane -cne $ackRequest.Lane -or
                $ackResponse.MessageId -cne $ackRequest.MessageId -or
                ($ackResponse.Sequence -isnot [int] -and $ackResponse.Sequence -isnot [long]) -or
                [long]$ackResponse.Sequence -ne [long]$ackRequest.Sequence) {
                return [pscustomobject][ordered]@{ Accepted = $false }
            }
            return [pscustomobject][ordered]@{ Accepted = $true }
        }
        finally {
            $response.Dispose()
        }
    }
    catch {
        if ($_.Exception.Message -ceq 'REALTIME_RUNTIME_ASSERTION_EXPIRED') {
            throw
        }
        return [pscustomobject][ordered]@{ Accepted = $false }
    }
    finally {
        $request.Dispose()
        $client.Dispose()
    }
}

function Invoke-CddsiRealtimeRelayLiveTransportReceiveInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][long]$After,
        [Parameter(Mandatory = $true)][int]$MaxMessages,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    $session = Get-CddsiRealtimeRelayLiveSessionInternal -TransportProvider $TransportProvider
    if (-not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $CredentialProvider -ClientId $TransportProvider.ClientId `
            -StateRootBindingToken $CredentialProvider.StateRootBindingToken -VerifySource) -or
        -not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $ClockProvider -VerifySource)) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    $now = Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider
    if ($AuthorizationExpiresAtUtc -le $now) {
        throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
    }
    return Invoke-CddsiRealtimeRelayWebSocketReceiveInternal -Session $session `
        -Endpoint ([uri]$TransportProvider.Endpoint) -ClientId $TransportProvider.ClientId `
        -CredentialProvider $CredentialProvider -ClockProvider $ClockProvider -NowUtc $now `
        -Lane $Lane -After $After -MaxMessages $MaxMessages `
        -AuthorizationExpiresAtUtc $AuthorizationExpiresAtUtc
}

function Invoke-CddsiRealtimeRelayLiveTransportAckInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    $session = Get-CddsiRealtimeRelayLiveSessionInternal -TransportProvider $TransportProvider
    if (-not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $CredentialProvider -ClientId $TransportProvider.ClientId `
            -StateRootBindingToken $CredentialProvider.StateRootBindingToken -VerifySource) -or
        -not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $ClockProvider -VerifySource)) {
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    $now = Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider
    if ($AuthorizationExpiresAtUtc -le $now) {
        throw 'REALTIME_RUNTIME_ASSERTION_EXPIRED'
    }
    $result = Invoke-CddsiRealtimeRelayAckInternal -Session $session `
        -Endpoint ([uri]$TransportProvider.Endpoint) -ClientId $TransportProvider.ClientId `
        -CredentialProvider $CredentialProvider -ClockProvider $ClockProvider -NowUtc $now `
        -Body $Body -AuthorizationExpiresAtUtc $AuthorizationExpiresAtUtc
    if (-not $result.Accepted) {
        Close-CddsiRealtimeRelayWebSocketSessionInternal -Session $session
    }
    return $result
}

function Invoke-CddsiRealtimeRelayPublishHttpInternal {
    param(
        [Parameter(Mandatory = $true)]$Session,
        [Parameter(Mandatory = $true)][uri]$Endpoint,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    if ($AuthorizationExpiresAtUtc -le
        (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
        throw 'REALTIME_PUBLISH_ASSERTION_EXPIRED'
    }
    $canonicalTarget = '/v1/publish/' + $Lane
    $headers = New-CddsiRealtimeRelayAuthHeadersInternal -ClientId $ClientId -Method POST `
        -CanonicalTarget $canonicalTarget -Body $Body -NowUtc $NowUtc `
        -CredentialProvider $CredentialProvider
    $handler = [Net.Http.HttpClientHandler]::new()
    $handler.AllowAutoRedirect = $false
    $handler.UseDefaultCredentials = $false
    $handler.UseProxy = $false
    $client = [Net.Http.HttpClient]::new($handler, $true)
    $client.Timeout = [TimeSpan]::FromSeconds(30)
    $client.MaxResponseContentBufferSize = 4096
    $builder = [UriBuilder]::new($Endpoint)
    $builder.Scheme = 'https'
    $builder.Port = -1
    $builder.Path = $canonicalTarget
    $builder.Query = ''
    $request = [Net.Http.HttpRequestMessage]::new([Net.Http.HttpMethod]::Post, $builder.Uri)
    $request.Content = [Net.Http.StringContent]::new(
        $Body,
        [Text.UTF8Encoding]::new($false),
        'application/json'
    )
    foreach ($property in $headers.PSObject.Properties) {
        [void]$request.Headers.TryAddWithoutValidation($property.Name, [string]$property.Value)
    }
    try {
        if ($AuthorizationExpiresAtUtc -le
            (Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider)) {
            throw 'REALTIME_PUBLISH_ASSERTION_EXPIRED'
        }
        $Session.OperatorRelayNetworkRequestCount =
        [long]$Session.OperatorRelayNetworkRequestCount + 1
        $response = $client.SendAsync($request).GetAwaiter().GetResult()
        try {
            $statusCode = [int]$response.StatusCode
            if (@(200, 201) -cnotcontains $statusCode -or
                $null -eq $response.Content.Headers.ContentType -or
                $response.Content.Headers.ContentType.MediaType -cne 'application/json') {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            $rawResponse = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
            if ([Text.UTF8Encoding]::new($false, $true).GetByteCount($rawResponse) -gt 4096) {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            $responseKeyMatches = @([regex]::Matches($rawResponse, '"([A-Za-z][A-Za-z0-9]*)":'))
            $responseKeyNames = @($responseKeyMatches | ForEach-Object { $_.Groups[1].Value })
            if ($responseKeyMatches.Count -ne 7 -or
                @($responseKeyNames | Sort-Object -Unique).Count -ne 7) {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            try {
                $publishRequest = ConvertFrom-Json -InputObject $Body -ErrorAction Stop
                $publishResponse = ConvertFrom-Json -InputObject $rawResponse -ErrorAction Stop
            }
            catch {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $publishResponse `
                    -Expected @(
                        'Schema', 'Status', 'Code', 'Lane', 'Sequence', 'MessageId',
                        'MessageSha256'
                    )) -or
                $publishResponse.Schema -cne 'cddsi-relay-response-v1' -or
                $publishResponse.Status -cne 'OK' -or
                @('PUBLISHED', 'PUBLISHED_IDEMPOTENT') -cnotcontains $publishResponse.Code -or
                (($statusCode -eq 201) -ne ($publishResponse.Code -ceq 'PUBLISHED')) -or
                $publishResponse.Lane -cne $Lane -or
                $publishResponse.Lane -cne $publishRequest.Lane -or
                $publishResponse.MessageId -cne $publishRequest.MessageId -or
                ($publishResponse.Sequence -isnot [int] -and
                    $publishResponse.Sequence -isnot [long]) -or
                [long]$publishResponse.Sequence -ne [long]$publishRequest.Sequence -or
                $publishResponse.MessageSha256 -isnot [string] -or
                $publishResponse.MessageSha256 -cnotmatch '^[0-9a-f]{64}$' -or
                $publishResponse.MessageSha256 -cne
                (Get-CddsiRealtimeRelayTextSha256Internal -Text $Body)) {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            $canonicalResponse = ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{
                    Schema = $publishResponse.Schema
                    Status = $publishResponse.Status
                    Code = $publishResponse.Code
                    Lane = $publishResponse.Lane
                    Sequence = [long]$publishResponse.Sequence
                    MessageId = $publishResponse.MessageId
                    MessageSha256 = $publishResponse.MessageSha256
                })
            if ($canonicalResponse -cne $rawResponse) {
                return [pscustomobject][ordered]@{
                    Accepted = $false
                    Code = 'REJECTED'
                    MessageSha256 = $null
                }
            }
            return [pscustomobject][ordered]@{
                Accepted = $true
                Code = [string]$publishResponse.Code
                MessageSha256 = [string]$publishResponse.MessageSha256
            }
        }
        finally {
            $response.Dispose()
        }
    }
    catch {
        if ($_.Exception.Message -ceq 'REALTIME_PUBLISH_ASSERTION_EXPIRED') {
            throw
        }
        return [pscustomobject][ordered]@{
            Accepted = $false
            Code = 'REJECTED'
            MessageSha256 = $null
        }
    }
    finally {
        $request.Dispose()
        $client.Dispose()
    }
}

function Invoke-CddsiRealtimeRelayLiveTransportPublishInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$ClockProvider,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)][string]$Body,
        [Parameter(Mandatory = $true)][DateTimeOffset]$AuthorizationExpiresAtUtc
    )

    $session = Get-CddsiRealtimeRelayLiveSessionInternal -TransportProvider $TransportProvider
    if (-not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $CredentialProvider -ClientId $TransportProvider.ClientId `
            -StateRootBindingToken $CredentialProvider.StateRootBindingToken -VerifySource) -or
        -not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $ClockProvider -VerifySource)) {
        throw 'REALTIME_PUBLISH_LIVE_PROVIDER_INVALID'
    }
    $now = Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $ClockProvider
    if ($AuthorizationExpiresAtUtc -le $now) {
        throw 'REALTIME_PUBLISH_ASSERTION_EXPIRED'
    }
    return Invoke-CddsiRealtimeRelayPublishHttpInternal -Session $session `
        -Endpoint ([uri]$TransportProvider.Endpoint) -ClientId $TransportProvider.ClientId `
        -CredentialProvider $CredentialProvider -ClockProvider $ClockProvider -NowUtc $now `
        -Lane $Lane -Body $Body -AuthorizationExpiresAtUtc $AuthorizationExpiresAtUtc
}

function Close-CddsiRealtimeRelayLiveTransportInternal {
    param(
        [Parameter(Mandatory = $true)]$TransportProvider,
        [switch]$RemoveSession
    )

    $session = Get-CddsiRealtimeRelayLiveSessionInternal -TransportProvider $TransportProvider
    try {
        Close-CddsiRealtimeRelayWebSocketSessionInternal -Session $session
    }
    finally {
        if ($RemoveSession) {
            $script:CddsiRealtimeLiveSessions.Remove([string]$TransportProvider.SessionId)
        }
    }
}

function New-CddsiRealtimeRelayLiveProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uri]$Endpoint,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$FixedWakeProvider,
        [Parameter(Mandatory = $true)]$StateProvider
    )

    if ($PSVersionTable.PSVersion.Major -ne 7) {
        throw 'REALTIME_LIVE_REQUIRES_POWERSHELL7'
    }
    if (-not (Test-CddsiRealtimeRelayLiveEndpointInternal -Endpoint $Endpoint.AbsoluteUri)) {
        throw 'REALTIME_ENDPOINT_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $StateProvider -VerifySource)) {
        throw 'REALTIME_LIVE_BINDING_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $CredentialProvider -ClientId $ClientId `
            -StateRootBindingToken $StateProvider.BindingToken -VerifySource)) {
        throw 'REALTIME_CREDENTIAL_PROVIDER_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayFixedWakeProviderContractInternal `
            -WakeProvider $FixedWakeProvider -Lane $Lane -ClientId $ClientId -VerifySource)) {
        throw 'REALTIME_FIXED_WAKE_PROVIDER_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayRootsDisjointInternal `
            -FirstRoot $StateProvider.StateRoot `
            -SecondRoot $FixedWakeProvider.Binding.StateRoot)) {
        throw 'REALTIME_LIVE_BINDING_INVALID'
    }
    $clientAdapterSha256 = Get-CddsiRealtimeRelayClientAdapterSha256Internal
    $sessionId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
    $transportBinding = Get-CddsiRealtimeRelayLiveTransportBindingTokenInternal `
        -Endpoint $Endpoint.AbsoluteUri -ClientId $ClientId -SessionId $sessionId `
        -ClientAdapterSha256 $clientAdapterSha256
    $transport = [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeLiveTransportProviderSchema
        ProviderKind = 'STATIC_WEBSOCKET_HTTP'
        Endpoint = $Endpoint.AbsoluteUri
        ClientId = $ClientId
        SessionId = $sessionId
        ClientAdapterSha256 = $clientAdapterSha256
        BindingToken = $transportBinding
    }
    $clock = [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeLiveClockProviderSchema
        ProviderKind = 'STATIC_SYSTEM_CLOCK'
        ClientAdapterSha256 = $clientAdapterSha256
    }
    $script:CddsiRealtimeLiveSessions[$sessionId] = [pscustomobject][ordered]@{
        Socket = $null
        OperatorRelayNetworkRequestCount = 0L
        OperatorGitInvocationCount = 0L
        OperatorGitTransportCount = 0L
        OperatorLocalStateMutationCount = 0L
        OperatorCodexProcessSpawnCount = 0L
        FixedWakeEffectCount = 0L
        PersistentChangeObserved = $false
        Endpoint = $Endpoint.AbsoluteUri
        ClientId = $ClientId
        BindingToken = $transportBinding
        ContextReference = $null
    }
    $context = [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeContextSchema
        Mode = 'Live'
        ProviderKind = 'Live'
        Endpoint = $Endpoint.AbsoluteUri
        ClientId = $ClientId
        ClientAdapterSha256 = $clientAdapterSha256
        Providers = [pscustomobject][ordered]@{
            State = $StateProvider
            Transport = $transport
            Wake = $FixedWakeProvider
            Clock = $clock
            Credential = $CredentialProvider
        }
    }
    if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $context `
            -ExpectedProperties $script:CddsiRealtimeLiveContextProperties)) {
        $script:CddsiRealtimeLiveSessions.Remove($sessionId)
        throw 'REALTIME_LIVE_PROVIDER_INVALID'
    }
    $script:CddsiRealtimeLiveSessions[$sessionId].ContextReference = $context
    return $context
}

function Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal {
    param(
        [Parameter(Mandatory = $true)]$RelayContext,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$RuntimeAssertion
    )

    if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RelayContext `
            -ExpectedProperties $script:CddsiRealtimePublisherLiveContextProperties) -or
        -not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RelayContext.Providers `
            -ExpectedProperties $script:CddsiRealtimePublisherProviderSetProperties) -or
        $RelayContext.SchemaVersion -cne $script:CddsiRealtimePublisherContextSchema -or
        $RelayContext.Mode -cne 'Live' -or $RelayContext.ProviderKind -cne 'Live' -or
        $RelayContext.ClientAdapterSha256 -cne
        (Get-CddsiRealtimeRelayClientAdapterSha256Internal) -or
        -not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $RuntimeAssertion `
            -ExpectedProperties $script:CddsiRealtimePublisherAssertionProperties)) {
        throw 'REALTIME_PUBLISH_ASSERTION_INVALID'
    }
    $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
    if ($RuntimeAssertion.SchemaVersion -cne $script:CddsiRealtimePublisherAssertionSchema -or
        $RuntimeAssertion.Status -cne 'AUTHORIZED' -or $RuntimeAssertion.Lane -cne $Lane -or
        $RuntimeAssertion.ClientId -cne $policy.WriterClientId -or
        $RelayContext.ClientId -cne $policy.WriterClientId -or
        $RuntimeAssertion.CredentialStorageKind -cne 'DPAPI_CURRENT_USER' -or
        $RuntimeAssertion.Environment -cnotmatch '^[a-z0-9](?:[a-z0-9-]{0,30}[a-z0-9])?$' -or
        $RuntimeAssertion.KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$') {
        throw 'REALTIME_PUBLISH_WRITER_IDENTITY_MISMATCH'
    }
    $issued = [DateTimeOffset]::MinValue
    $expires = [DateTimeOffset]::MinValue
    if (-not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $RuntimeAssertion.IssuedAtUtc `
            -Parsed ([ref]$issued)) -or
        -not (Test-CddsiRealtimeRelayUtcSecondInternal -Value $RuntimeAssertion.ExpiresAtUtc `
            -Parsed ([ref]$expires)) -or $expires -le $issued -or
        ($expires - $issued).TotalSeconds -gt $script:CddsiRealtimeMaxAssertionLifetimeSeconds) {
        throw 'REALTIME_PUBLISH_ASSERTION_INVALID'
    }
    $providers = $RelayContext.Providers
    if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $providers.State -VerifySource) -or
        -not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $providers.Credential -ClientId $policy.WriterClientId `
            -StateRootBindingToken $providers.State.BindingToken -VerifySource) -or
        -not (Test-CddsiRealtimeRelayLiveTransportProviderContractInternal `
            -TransportProvider $providers.Transport -VerifySource -VerifySession) -or
        -not (Test-CddsiRealtimeRelayLiveClockProviderContractInternal `
            -ClockProvider $providers.Clock -VerifySource)) {
        throw 'REALTIME_PUBLISH_BINDING_MISMATCH'
    }
    if ($RelayContext.Endpoint -cne $RuntimeAssertion.Endpoint -or
        $providers.Transport.Endpoint -cne $RuntimeAssertion.Endpoint -or
        $providers.Transport.ClientId -cne $policy.WriterClientId -or
        $providers.State.BindingToken -cne $RuntimeAssertion.StateRootBindingToken -or
        $providers.Credential.StorageKind -cne $RuntimeAssertion.CredentialStorageKind -or
        $providers.Credential.BindingToken -cne $RuntimeAssertion.CredentialBindingToken -or
        $providers.Credential.Environment -cne $RuntimeAssertion.Environment -or
        $providers.Credential.KeyId -cne $RuntimeAssertion.KeyId -or
        $RuntimeAssertion.ClientAdapterSha256 -cne $RelayContext.ClientAdapterSha256 -or
        $providers.State.ClientAdapterSha256 -cne $RelayContext.ClientAdapterSha256 -or
        $providers.Credential.ClientAdapterSha256 -cne $RelayContext.ClientAdapterSha256 -or
        $providers.Transport.ClientAdapterSha256 -cne $RelayContext.ClientAdapterSha256 -or
        $providers.Clock.ClientAdapterSha256 -cne $RelayContext.ClientAdapterSha256) {
        throw 'REALTIME_PUBLISH_BINDING_MISMATCH'
    }
    $now = Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $providers.Clock
    if ($issued -gt $now -or $expires -le $now) {
        throw 'REALTIME_PUBLISH_ASSERTION_EXPIRED'
    }
    return $expires
}

function Assert-CddsiRealtimeRelayPublisherContextInternal {
    param(
        [Parameter(Mandatory = $true)]$RelayContext,
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$RuntimeAssertion
    )

    if ($null -eq $RelayContext -or $null -eq $RelayContext.PSObject -or
        $null -eq $RelayContext.PSObject.Properties['SchemaVersion'] -or
        $null -eq $RelayContext.PSObject.Properties['Mode'] -or
        $null -eq $RelayContext.PSObject.Properties['ProviderKind'] -or
        $null -eq $RelayContext.PSObject.Properties['ClientId'] -or
        $null -eq $RelayContext.PSObject.Properties['Providers'] -or
        $RelayContext.SchemaVersion -cne $script:CddsiRealtimePublisherContextSchema -or
        $RelayContext.Mode -cne $Mode -or $null -eq $RelayContext.Providers) {
        throw 'REALTIME_PUBLISH_CONTEXT_INVALID'
    }
    $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
    if ($RelayContext.ClientId -cne $policy.WriterClientId) {
        throw 'REALTIME_PUBLISH_WRITER_IDENTITY_MISMATCH'
    }
    foreach ($providerName in $script:CddsiRealtimePublisherProviderSetProperties) {
        if ($null -eq $RelayContext.Providers.PSObject.Properties[$providerName] -or
            $null -eq $RelayContext.Providers.$providerName) {
            throw 'REALTIME_PUBLISH_PROVIDER_MISSING'
        }
    }
    if ($Mode -ceq 'Live') {
        if ($PSVersionTable.PSVersion.Major -ne 7 -or $RelayContext.ProviderKind -cne 'Live') {
            throw 'REALTIME_PUBLISH_LIVE_PROVIDER_INVALID'
        }
        [void](Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                -RelayContext $RelayContext -Lane $Lane -RuntimeAssertion $RuntimeAssertion)
    }
    else {
        if ($RelayContext.ProviderKind -cne 'Fake' -or
            -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                -InputObject $RuntimeAssertion `
                -Expected $script:CddsiRealtimePublisherAssertionProperties) -or
            $RuntimeAssertion.SchemaVersion -cne $script:CddsiRealtimePublisherAssertionSchema -or
            $RuntimeAssertion.Status -cne 'SYNTHETIC' -or
            $RuntimeAssertion.Lane -cne $Lane -or
            $RuntimeAssertion.ClientId -cne $policy.WriterClientId) {
            throw 'REALTIME_PUBLISH_ASSERTION_INVALID'
        }
    }
    $credentialReady = if ($Mode -ceq 'Live') {
        try {
            [void](Invoke-CddsiRealtimeRelayCredentialProviderOperationInternal `
                    -CredentialProvider $RelayContext.Providers.Credential -Operation Validate)
            $true
        }
        catch { $false }
    }
    else {
        if ($RelayContext.Providers.Credential.TestReady -isnot [scriptblock]) {
            throw 'REALTIME_PUBLISH_PROVIDER_MISSING'
        }
        & $RelayContext.Providers.Credential.TestReady
    }
    if ($credentialReady -isnot [bool] -or -not $credentialReady) {
        throw 'REALTIME_CREDENTIAL_NOT_READY'
    }
}

function New-CddsiRealtimeRelayLivePublisher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][uri]$Endpoint,
        [Parameter(Mandatory = $true)][ValidateSet('host-coordinator-v1', 'vm-tester-v1')][string]$ClientId,
        [Parameter(Mandatory = $true)][ValidateSet('host-to-vm', 'vm-to-host')][string]$Lane,
        [Parameter(Mandatory = $true)]$CredentialProvider,
        [Parameter(Mandatory = $true)]$StateProvider
    )

    if ($PSVersionTable.PSVersion.Major -ne 7) {
        throw 'REALTIME_LIVE_REQUIRES_POWERSHELL7'
    }
    $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $Lane
    if ($ClientId -cne $policy.WriterClientId) {
        throw 'REALTIME_PUBLISH_WRITER_IDENTITY_MISMATCH'
    }
    if (-not (Test-CddsiRealtimeRelayLiveEndpointInternal -Endpoint $Endpoint.AbsoluteUri)) {
        throw 'REALTIME_ENDPOINT_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayStateProviderContractInternal `
            -StateProvider $StateProvider -VerifySource)) {
        throw 'REALTIME_PUBLISH_LIVE_PROVIDER_INVALID'
    }
    if (-not (Test-CddsiRealtimeRelayCredentialProviderContractInternal `
            -CredentialProvider $CredentialProvider -ClientId $ClientId `
            -StateRootBindingToken $StateProvider.BindingToken -VerifySource)) {
        throw 'REALTIME_CREDENTIAL_PROVIDER_INVALID'
    }
    $clientAdapterSha256 = Get-CddsiRealtimeRelayClientAdapterSha256Internal
    $sessionId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
    $transportBinding = Get-CddsiRealtimeRelayLiveTransportBindingTokenInternal `
        -Endpoint $Endpoint.AbsoluteUri -ClientId $ClientId -SessionId $sessionId `
        -ClientAdapterSha256 $clientAdapterSha256
    $transport = [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeLiveTransportProviderSchema
        ProviderKind = 'STATIC_WEBSOCKET_HTTP'
        Endpoint = $Endpoint.AbsoluteUri
        ClientId = $ClientId
        SessionId = $sessionId
        ClientAdapterSha256 = $clientAdapterSha256
        BindingToken = $transportBinding
    }
    $clock = [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimeLiveClockProviderSchema
        ProviderKind = 'STATIC_SYSTEM_CLOCK'
        ClientAdapterSha256 = $clientAdapterSha256
    }
    $script:CddsiRealtimeLiveSessions[$sessionId] = [pscustomobject][ordered]@{
        Socket = $null
        OperatorRelayNetworkRequestCount = 0L
        OperatorGitInvocationCount = 0L
        OperatorGitTransportCount = 0L
        OperatorLocalStateMutationCount = 0L
        OperatorCodexProcessSpawnCount = 0L
        FixedWakeEffectCount = 0L
        PersistentChangeObserved = $false
        Endpoint = $Endpoint.AbsoluteUri
        ClientId = $ClientId
        BindingToken = $transportBinding
        ContextReference = $null
    }
    try {
        $context = [pscustomobject][ordered]@{
            SchemaVersion = $script:CddsiRealtimePublisherContextSchema
            Mode = 'Live'
            ProviderKind = 'Live'
            Endpoint = $Endpoint.AbsoluteUri
            ClientId = $ClientId
            ClientAdapterSha256 = $clientAdapterSha256
            Providers = [pscustomobject][ordered]@{
                State = $StateProvider
                Transport = $transport
                Clock = $clock
                Credential = $CredentialProvider
            }
        }
        if (-not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $context `
                -ExpectedProperties $script:CddsiRealtimePublisherLiveContextProperties) -or
            -not (Test-CddsiRealtimeRelayDataDescriptorInternal -Descriptor $context.Providers `
                -ExpectedProperties $script:CddsiRealtimePublisherProviderSetProperties)) {
            throw 'REALTIME_PUBLISH_LIVE_PROVIDER_INVALID'
        }
        $script:CddsiRealtimeLiveSessions[$sessionId].ContextReference = $context
        return $context
    }
    catch {
        Close-CddsiRealtimeRelayTrustedLiveSessionInternal -TrustedSessionId $sessionId
        throw
    }
}

function New-CddsiRealtimeRelayPublishResultInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('SUCCEEDED', 'BLOCKED')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode,
        [Parameter(Mandatory = $true)][bool]$Changed,
        [AllowNull()][string]$Lane,
        [AllowNull()][string]$MessageId,
        [AllowNull()]$Sequence,
        [AllowNull()][string]$MessageSha256,
        [Parameter(Mandatory = $true)][bool]$Idempotent,
        [Parameter(Mandatory = $true)][long]$OperatorRelayNetworkRequestCount,
        [Parameter(Mandatory = $true)][long]$OperatorLocalStateMutationCount
    )

    return [pscustomobject][ordered]@{
        SchemaVersion = $script:CddsiRealtimePublishResultSchema
        Status = $Status
        Code = $Code
        Mode = $Mode
        Changed = $Changed
        Lane = $Lane
        MessageId = $MessageId
        Sequence = $Sequence
        MessageSha256 = $MessageSha256
        Idempotent = $Idempotent
        ProductLiveAttemptCount = 0
        RealRegistryAccessCount = 0
        ProductNetworkRequestCount = 0
        OperatorRelayNetworkRequestCount = $OperatorRelayNetworkRequestCount
        OperatorGitInvocationCount = 0
        OperatorGitTransportCount = 0
        OperatorLocalStateMutationCount = $OperatorLocalStateMutationCount
        OperatorCodexProcessSpawnCount = 0
        FixedWakeEffectCount = 0
        RealNetworkAccessCount = 0
        RealCredentialManagerAccessCount = 0
        ProductProcessSpawnCount = 0
        OutsideOwnedStateWriteCount = 0
        UnexpectedLedgerEntryCount = 0
        MutationSpyCount = 0
    }
}

function Invoke-CddsiRealtimeRelayPublish {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$RelayExecutionContext,
        [Parameter(Mandatory = $true)]$PublishPointer,
        [Parameter(Mandatory = $true)]$RuntimeAssertion,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeOperatorPlaneLive
    )

    $trustedLiveSessionId = $null
    $lockHandle = $null
    $lifecycleLockHandle = $null
    $stateProviderReference = $null
    $operatorRelayNetworkRequestCount = 0L
    $operatorLocalStateMutationCount = 0L
    $persistentChangeObserved = $false
    $resultLane = $null
    $resultMessageId = $null
    $resultSequence = $null
    $resultMessageSha256 = $null
    try {
        if ($Mode -ceq 'Live') {
            $trustedLiveSessionId = Get-CddsiRealtimeRelayTrustedLiveSessionIdForContextInternal `
                -RelayContext $RelayExecutionContext
        }
        if (-not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                -InputObject $PublishPointer -Expected $script:CddsiRealtimePublishPointerProperties) -or
            $PublishPointer.SchemaVersion -isnot [string] -or
            $PublishPointer.SchemaVersion -cne $script:CddsiRealtimePublishPointerSchema -or
            $PublishPointer.Lane -isnot [string] -or
            @('host-to-vm', 'vm-to-host') -cnotcontains $PublishPointer.Lane -or
            $PublishPointer.MessageId -isnot [string] -or
            $PublishPointer.MessageId -cnotmatch
            '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $PublishPointer.PayloadSha256 -isnot [string] -or
            $PublishPointer.PayloadSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $PublishPointer.Commit -isnot [string] -or
            $PublishPointer.Commit -cnotmatch '^[0-9a-f]{40}$') {
            throw 'REALTIME_PUBLISH_NOTIFICATION_INVALID'
        }
        $resultLane = [string]$PublishPointer.Lane
        $policy = Get-CddsiRealtimeRelayLanePolicyInternal -Lane $resultLane
        if ($null -eq $RelayExecutionContext -or $null -eq $RelayExecutionContext.PSObject -or
            $null -eq $RelayExecutionContext.PSObject.Properties['ClientId'] -or
            $RelayExecutionContext.ClientId -cne $policy.WriterClientId) {
            throw 'REALTIME_PUBLISH_WRITER_IDENTITY_MISMATCH'
        }
        if ($Mode -ceq 'Live' -and -not $AcknowledgeOperatorPlaneLive) {
            throw 'REALTIME_PUBLISH_CONFIRMATION_REQUIRED'
        }
        Assert-CddsiRealtimeRelayPublisherContextInternal `
            -RelayContext $RelayExecutionContext -Mode $Mode -Lane $resultLane `
            -RuntimeAssertion $RuntimeAssertion
        $providers = $RelayExecutionContext.Providers
        $stateProviderReference = $providers.State
        $liveAssertionExpiresAt = if ($Mode -ceq 'Live') {
            Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                -RelayContext $RelayExecutionContext -Lane $resultLane `
                -RuntimeAssertion $RuntimeAssertion
        }
        else {
            [DateTimeOffset]::MaxValue
        }
        if ($Mode -ceq 'Live') {
            $rootResult = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $stateProviderReference -Operation ValidateRoot
            if ($null -eq $rootResult -or
                -not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $rootResult `
                    -Expected @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created')) -or
                $rootResult.Valid -isnot [bool] -or $rootResult.OwnerMarked -isnot [bool] -or
                $rootResult.AclProtected -isnot [bool] -or $rootResult.NoReparse -isnot [bool] -or
                $rootResult.Created -isnot [bool] -or -not $rootResult.Valid -or
                -not $rootResult.OwnerMarked -or -not $rootResult.AclProtected -or
                -not $rootResult.NoReparse) {
                throw 'REALTIME_PUBLISH_STATE_ROOT_INVALID'
            }
            if ($rootResult.Created) {
                $session = Get-CddsiRealtimeRelayLiveSessionInternal `
                    -TransportProvider $providers.Transport
                $session.OperatorLocalStateMutationCount =
                [long]$session.OperatorLocalStateMutationCount + 1
                $session.PersistentChangeObserved = $true
            }
            $lifecycleLockPath = [IO.Path]::Combine(
                $stateProviderReference.StateRoot,
                '.lifecycle.lock'
            )
            $lifecycleLockAlreadyExisted = [IO.File]::Exists($lifecycleLockPath)
            try {
                $lifecycleLockHandle = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $stateProviderReference -Operation AcquireLifecycleLock
            }
            catch {
                throw 'REALTIME_PUBLISH_LOCK_FAILED'
            }
            if (-not $lifecycleLockAlreadyExisted) {
                $session = Get-CddsiRealtimeRelayLiveSessionInternal `
                    -TransportProvider $providers.Transport
                $session.OperatorLocalStateMutationCount =
                [long]$session.OperatorLocalStateMutationCount + 1
                $session.PersistentChangeObserved = $true
            }
            $postLockRootResult = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $stateProviderReference -Operation ValidateRoot
            if ($null -eq $postLockRootResult -or
                -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                    -InputObject $postLockRootResult `
                    -Expected @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created')) -or
                $postLockRootResult.Valid -isnot [bool] -or
                -not $postLockRootResult.Valid -or $postLockRootResult.Created) {
                throw 'REALTIME_PUBLISH_STATE_ROOT_INVALID'
            }
            $publisherPaths = Get-CddsiRealtimeRelayPublisherStatePathsInternal `
                -StateRoot $stateProviderReference.StateRoot -Lane $resultLane
            $lockAlreadyExisted = [IO.File]::Exists($publisherPaths.Lock)
            try {
                $lockHandle = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $stateProviderReference -Operation AcquirePublisherLock `
                    -Lane $resultLane
            }
            catch {
                throw 'REALTIME_PUBLISH_LOCK_FAILED'
            }
            if (-not $lockAlreadyExisted) {
                $session = Get-CddsiRealtimeRelayLiveSessionInternal `
                    -TransportProvider $providers.Transport
                $session.OperatorLocalStateMutationCount =
                [long]$session.OperatorLocalStateMutationCount + 1
                $session.PersistentChangeObserved = $true
            }
            $lifecycleLockHandle.Dispose()
            $lifecycleLockHandle = $null
            $state = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $stateProviderReference -Operation LoadPublisher -Lane $resultLane
        }
        else {
            foreach ($operation in @(
                    'ValidateRoot', 'AcquirePublisherLock', 'LoadPublisher',
                    'CommitPublisher', 'ReleasePublisherLock'
                )) {
                if ($providers.State.$operation -isnot [scriptblock]) {
                    throw 'REALTIME_PUBLISH_PROVIDER_MISSING'
                }
            }
            $rootResult = & $providers.State.ValidateRoot
            if ($null -eq $rootResult -or
                -not (Test-CddsiRealtimeRelayExactPropertySetInternal -InputObject $rootResult `
                    -Expected @('Valid', 'OwnerMarked', 'AclProtected', 'NoReparse', 'Created')) -or
                $rootResult.Valid -isnot [bool] -or -not $rootResult.Valid -or
                $rootResult.OwnerMarked -isnot [bool] -or -not $rootResult.OwnerMarked -or
                $rootResult.AclProtected -isnot [bool] -or -not $rootResult.AclProtected -or
                $rootResult.NoReparse -isnot [bool] -or -not $rootResult.NoReparse -or
                $rootResult.Created -isnot [bool]) {
                throw 'REALTIME_PUBLISH_STATE_ROOT_INVALID'
            }
            $lockHandle = & $providers.State.AcquirePublisherLock $resultLane
            if ($null -eq $lockHandle) {
                throw 'REALTIME_PUBLISH_LOCK_FAILED'
            }
            $state = & $providers.State.LoadPublisher $resultLane
        }
        if (-not (Test-CddsiRealtimeRelayPublisherStateInternal -State $state -Lane $resultLane)) {
            throw 'REALTIME_PUBLISH_STATE_INVALID'
        }
        $publishedMatches = @($state.PublishedMessages | Where-Object {
                $_.MessageId -ceq $PublishPointer.MessageId
            })
        if ($publishedMatches.Count -gt 1) {
            throw 'REALTIME_PUBLISH_STATE_INVALID'
        }
        if ($publishedMatches.Count -eq 1) {
            $publishedMatch = $publishedMatches[0]
            if ($publishedMatch.PayloadSha256 -cne $PublishPointer.PayloadSha256 -or
                $publishedMatch.Commit -cne $PublishPointer.Commit) {
                throw 'REALTIME_PUBLISH_PENDING_CONFLICT'
            }
            $resultMessageId = [string]$publishedMatch.MessageId
            $resultSequence = [long]$publishedMatch.Sequence
            $resultMessageSha256 = [string]$publishedMatch.MessageSha256
            if ($Mode -ceq 'Live') {
                $audit = Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal `
                    -SessionId $trustedLiveSessionId
                $operatorRelayNetworkRequestCount = $audit.OperatorRelayNetworkRequestCount
                $operatorLocalStateMutationCount = $audit.OperatorLocalStateMutationCount
                $persistentChangeObserved = $audit.PersistentChangeObserved
            }
            return New-CddsiRealtimeRelayPublishResultInternal -Status SUCCEEDED `
                -Code PUBLISHED_IDEMPOTENT -Mode $Mode `
                -Changed ($Mode -ceq 'Live' -and $persistentChangeObserved) `
                -Lane $resultLane -MessageId $resultMessageId -Sequence $resultSequence `
                -MessageSha256 $resultMessageSha256 -Idempotent $true `
                -OperatorRelayNetworkRequestCount $operatorRelayNetworkRequestCount `
                -OperatorLocalStateMutationCount $operatorLocalStateMutationCount
        }
        $now = if ($Mode -ceq 'Live') {
            Get-CddsiRealtimeRelayLiveUtcNowInternal -ClockProvider $providers.Clock
        }
        else {
            if ($providers.Clock.GetUtcNow -isnot [scriptblock]) {
                throw 'REALTIME_PUBLISH_PROVIDER_MISSING'
            }
            & $providers.Clock.GetUtcNow
        }
        if ($now -isnot [DateTimeOffset]) {
            throw 'REALTIME_PUBLISH_PROVIDER_MISSING'
        }
        $canonicalBody = $null
        $pendingWasReused = $false
        if ($null -ne $state.PendingPublish) {
            $pendingValidation = Test-CddsiRealtimeRelayNotificationInternal `
                -RawMessage $state.PendingPublish.CanonicalBody -NowUtc $now `
                -ValidationMode StoredConsumedReplay
            if (-not $pendingValidation.Valid -or
                $pendingValidation.MessageSha256 -cne $state.PendingPublish.MessageSha256) {
                throw 'REALTIME_PUBLISH_STATE_INVALID'
            }
            if ($pendingValidation.Message.Lane -cne $resultLane -or
                $pendingValidation.Message.MessageId -cne $PublishPointer.MessageId -or
                $pendingValidation.Message.PayloadSha256 -cne $PublishPointer.PayloadSha256 -or
                $pendingValidation.Message.Commit -cne $PublishPointer.Commit) {
                throw 'REALTIME_PUBLISH_PENDING_CONFLICT'
            }
            $canonicalBody = [string]$state.PendingPublish.CanonicalBody
            $resultMessageSha256 = [string]$state.PendingPublish.MessageSha256
            $resultMessageId = [string]$pendingValidation.Message.MessageId
            $resultSequence = [long]$pendingValidation.Message.Sequence
            $pendingWasReused = $true
        }
        else {
            if ([long]$state.LastPublishedSequence -ge $script:CddsiRealtimeMaxSafeInteger -or
                [long]$state.Revision -ge $script:CddsiRealtimeMaxSafeInteger) {
                throw 'REALTIME_PUBLISH_STATE_INVALID'
            }
            $message = [pscustomobject][ordered]@{
                Schema = $script:CddsiRealtimeNotificationSchema
                Lane = $resultLane
                MessageId = $PublishPointer.MessageId
                Sequence = [long]$state.LastPublishedSequence + 1
                PreviousSha256 = $state.LastMessageSha256
                PayloadSha256 = $PublishPointer.PayloadSha256
                RepositoryId = $policy.RepositoryId
                Ref = 'refs/heads/main'
                Commit = $PublishPointer.Commit
                CreatedAt = $now.ToUniversalTime().ToString(
                    'yyyy-MM-ddTHH:mm:ssZ',
                    [Globalization.CultureInfo]::InvariantCulture
                )
                Expiry = $now.ToUniversalTime().AddSeconds(
                    $script:CddsiRealtimePublisherTtlSeconds
                ).ToString(
                    'yyyy-MM-ddTHH:mm:ssZ',
                    [Globalization.CultureInfo]::InvariantCulture
                )
                SenderRole = $policy.SenderRole
            }
            $canonicalBody = ConvertTo-CddsiRealtimeRelayCanonicalNotificationInternal `
                -Message $message
            $validation = Test-CddsiRealtimeRelayNotificationInternal `
                -RawMessage $canonicalBody -NowUtc $now
            if (-not $validation.Valid -or $validation.Message.Lane -cne $resultLane -or
                $validation.Message.PayloadSha256 -cne $PublishPointer.PayloadSha256 -or
                $validation.Message.Commit -cne $PublishPointer.Commit) {
                throw 'REALTIME_PUBLISH_NOTIFICATION_INVALID'
            }
            $resultMessageId = [string]$message.MessageId
            $resultSequence = [long]$message.Sequence
            $resultMessageSha256 = [string]$validation.MessageSha256
            $state.PendingPublish = [pscustomobject][ordered]@{
                CanonicalBody = $canonicalBody
                MessageSha256 = $resultMessageSha256
            }
            $state.Revision = [long]$state.Revision + 1
            try {
                if ($Mode -ceq 'Live') {
                    [void](Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                            -RelayContext $RelayExecutionContext -Lane $resultLane `
                            -RuntimeAssertion $RuntimeAssertion)
                    Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                        -StateProvider $stateProviderReference -Operation CommitPublisher `
                        -State $state
                    $session = Get-CddsiRealtimeRelayLiveSessionInternal `
                        -TransportProvider $providers.Transport
                    $session.OperatorLocalStateMutationCount =
                    [long]$session.OperatorLocalStateMutationCount + 1
                    $session.PersistentChangeObserved = $true
                }
                else {
                    & $providers.State.CommitPublisher $state
                }
            }
            catch {
                if ($_.Exception.Message -ceq 'REALTIME_PUBLISH_ASSERTION_EXPIRED') {
                    throw
                }
                throw 'REALTIME_PUBLISH_STATE_ATOMIC_WRITE_FAILED'
            }
        }
        if ($Mode -ceq 'Live') {
            [void](Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                    -RelayContext $RelayExecutionContext -Lane $resultLane `
                    -RuntimeAssertion $RuntimeAssertion)
            try {
                $publishResult = Invoke-CddsiRealtimeRelayLiveTransportPublishInternal `
                    -TransportProvider $providers.Transport `
                    -CredentialProvider $providers.Credential `
                    -ClockProvider $providers.Clock -Lane $resultLane -Body $canonicalBody `
                    -AuthorizationExpiresAtUtc $liveAssertionExpiresAt
            }
            finally {
                $audit = Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal `
                    -SessionId $trustedLiveSessionId
                $operatorRelayNetworkRequestCount = $audit.OperatorRelayNetworkRequestCount
            }
        }
        else {
            if ($providers.Transport.Publish -isnot [scriptblock]) {
                throw 'REALTIME_PUBLISH_PROVIDER_MISSING'
            }
            $publishResult = & $providers.Transport.Publish $resultLane $canonicalBody
        }
        if ($null -eq $publishResult -or
            -not (Test-CddsiRealtimeRelayExactPropertySetInternal `
                -InputObject $publishResult -Expected @('Accepted', 'Code', 'MessageSha256')) -or
            $publishResult.Accepted -isnot [bool] -or $publishResult.Code -isnot [string] -or
            ($null -ne $publishResult.MessageSha256 -and
                $publishResult.MessageSha256 -isnot [string])) {
            throw 'REALTIME_PUBLISH_RESULT_INVALID'
        }
        if (-not $publishResult.Accepted) {
            throw 'REALTIME_PUBLISH_REJECTED'
        }
        if (@('PUBLISHED', 'PUBLISHED_IDEMPOTENT') -cnotcontains $publishResult.Code -or
            $publishResult.MessageSha256 -cne $resultMessageSha256) {
            throw 'REALTIME_PUBLISH_RESULT_INVALID'
        }
        if ($Mode -ceq 'Live') {
            [void](Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                    -RelayContext $RelayExecutionContext -Lane $resultLane `
                    -RuntimeAssertion $RuntimeAssertion)
            $persistedState = Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                -StateProvider $stateProviderReference -Operation LoadPublisher -Lane $resultLane
            if (-not (Test-CddsiRealtimeRelayPublisherStateInternal `
                    -State $persistedState -Lane $resultLane) -or
                (ConvertTo-Json -Compress -Depth 8 -InputObject $persistedState) -cne
                (ConvertTo-Json -Compress -Depth 8 -InputObject $state)) {
                throw 'REALTIME_PUBLISH_PENDING_CONFLICT'
            }
            $state = $persistedState
        }
        if ($null -eq $state.PendingPublish -or
            $state.PendingPublish.CanonicalBody -cne $canonicalBody -or
            $state.PendingPublish.MessageSha256 -cne $resultMessageSha256 -or
            [long]$state.Revision -ge $script:CddsiRealtimeMaxSafeInteger) {
            throw 'REALTIME_PUBLISH_PENDING_CONFLICT'
        }
        $state.LastPublishedSequence = [long]$resultSequence
        $state.LastMessageSha256 = $resultMessageSha256
        $state.PublishedMessages = @($state.PublishedMessages) + @(
            [pscustomobject][ordered]@{
                MessageId = $resultMessageId
                Sequence = [long]$resultSequence
                MessageSha256 = $resultMessageSha256
                PayloadSha256 = $PublishPointer.PayloadSha256
                Commit = $PublishPointer.Commit
            }
        )
        if (@($state.PublishedMessages).Count -gt 256) {
            $state.PublishedMessages = @($state.PublishedMessages | Select-Object -Last 256)
        }
        $state.PendingPublish = $null
        $state.Revision = [long]$state.Revision + 1
        try {
            if ($Mode -ceq 'Live') {
                [void](Assert-CddsiRealtimeRelayPublisherLiveAuthorizationCurrentInternal `
                        -RelayContext $RelayExecutionContext -Lane $resultLane `
                        -RuntimeAssertion $RuntimeAssertion)
                Invoke-CddsiRealtimeRelayOwnedStateOperationInternal `
                    -StateProvider $stateProviderReference -Operation CommitPublisher -State $state
                $session = Get-CddsiRealtimeRelayLiveSessionInternal `
                    -TransportProvider $providers.Transport
                $session.OperatorLocalStateMutationCount =
                [long]$session.OperatorLocalStateMutationCount + 1
                $session.PersistentChangeObserved = $true
            }
            else {
                & $providers.State.CommitPublisher $state
            }
        }
        catch {
            if ($_.Exception.Message -ceq 'REALTIME_PUBLISH_ASSERTION_EXPIRED') {
                throw
            }
            throw 'REALTIME_PUBLISH_STATE_ATOMIC_WRITE_FAILED'
        }
        if ($Mode -ceq 'Live') {
            $audit = Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal `
                -SessionId $trustedLiveSessionId
            $operatorRelayNetworkRequestCount = $audit.OperatorRelayNetworkRequestCount
            $operatorLocalStateMutationCount = $audit.OperatorLocalStateMutationCount
            $persistentChangeObserved = $audit.PersistentChangeObserved
        }
        return New-CddsiRealtimeRelayPublishResultInternal -Status SUCCEEDED `
            -Code $publishResult.Code -Mode $Mode `
            -Changed ($Mode -ceq 'Live' -and $persistentChangeObserved) -Lane $resultLane `
            -MessageId $resultMessageId -Sequence $resultSequence `
            -MessageSha256 $resultMessageSha256 `
            -Idempotent ($publishResult.Code -ceq 'PUBLISHED_IDEMPOTENT') `
            -OperatorRelayNetworkRequestCount $operatorRelayNetworkRequestCount `
            -OperatorLocalStateMutationCount $operatorLocalStateMutationCount
    }
    catch {
        if ($Mode -ceq 'Live' -and -not [string]::IsNullOrEmpty($trustedLiveSessionId)) {
            $audit = Get-CddsiRealtimeRelayLiveAuditSnapshotBySessionIdInternal `
                -SessionId $trustedLiveSessionId
            $operatorRelayNetworkRequestCount = $audit.OperatorRelayNetworkRequestCount
            $operatorLocalStateMutationCount = $audit.OperatorLocalStateMutationCount
            $persistentChangeObserved = $audit.PersistentChangeObserved
        }
        $code = [string]$_.Exception.Message
        if ($code -cmatch '^REALTIME_PUBLISH_LOCK_') {
            $code = 'REALTIME_PUBLISH_LOCK_FAILED'
        }
        elseif ($code -cmatch '^REALTIME_PUBLISH_STATE_' -and
            $script:CddsiRealtimePublisherResultCodes -cnotcontains $code) {
            $code = 'REALTIME_PUBLISH_STATE_INVALID'
        }
        elseif ($script:CddsiRealtimePublisherResultCodes -cnotcontains $code) {
            $code = 'REALTIME_PUBLISH_BLOCKED'
        }
        return New-CddsiRealtimeRelayPublishResultInternal -Status BLOCKED -Code $code `
            -Mode $Mode -Changed ($Mode -ceq 'Live' -and $persistentChangeObserved) `
            -Lane $resultLane -MessageId $resultMessageId -Sequence $resultSequence `
            -MessageSha256 $resultMessageSha256 -Idempotent $false `
            -OperatorRelayNetworkRequestCount $operatorRelayNetworkRequestCount `
            -OperatorLocalStateMutationCount $operatorLocalStateMutationCount
    }
    finally {
        try {
            if ($null -ne $lockHandle -and $null -ne $stateProviderReference) {
                if ($Mode -ceq 'Live') {
                    $lockHandle.Dispose()
                }
                else {
                    & $stateProviderReference.ReleasePublisherLock $resultLane $lockHandle
                }
            }
        }
        catch {
            # Lock release is best-effort and never exposes provider exception text.
        }
        try {
            if ($null -ne $lifecycleLockHandle -and $Mode -ceq 'Live') {
                $lifecycleLockHandle.Dispose()
            }
        }
        catch {
            # The validated lifecycle lock is released without re-reading caller context.
        }
        if ($Mode -ceq 'Live' -and -not [string]::IsNullOrEmpty($trustedLiveSessionId)) {
            Close-CddsiRealtimeRelayTrustedLiveSessionInternal -TrustedSessionId $trustedLiveSessionId
        }
    }
}
