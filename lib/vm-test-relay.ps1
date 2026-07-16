# vm-test-relay.ps1 - Pure Fast Lane VM test relay contracts.
# This operator-coordination module performs no Git, network, filesystem,
# scheduled-task, process, VM, product or Live operation. Formal Lane is
# deliberately unavailable until its external signature and CAS authorities
# are implemented.

$script:CddsiVmTestRelayProtocolVersion = 'cddsi-vm-test-relay-v1'
$script:CddsiVmTestRelayStateVersion = 'cddsi-vm-test-relay-state-v1'
$script:CddsiVmTestRelayRepositoryIdentityPattern = '^(?:github\.com/[A-Za-z0-9][A-Za-z0-9._-]{0,63}/[A-Za-z0-9][A-Za-z0-9._-]{0,95}|synthetic/[A-Za-z0-9][A-Za-z0-9._-]{0,95})$'
$script:CddsiVmTestRelayEnvelopeProperties = @(
    'SchemaVersion', 'ProtocolVersion', 'Lane', 'MessageId', 'CycleId',
    'Sequence', 'MessageType', 'SenderRole', 'HostToVmRepositoryIdentity',
    'VmToHostRepositoryIdentity', 'PhysicalControlRepositoryIdentity',
    'ProductRepositoryIdentity', 'Outbox', 'CreatedAtUtc', 'ExpiresAtUtc',
    'Nonce', 'ExpectedStateBindingToken', 'PreviousMessageSha256',
    'RepositoryCommitSha', 'RepairRef', 'ArtifactProfile', 'CandidateId',
    'ArtifactSha256', 'SidecarSha256', 'RunbookSha256', 'VmImageSha256',
    'OsMatrixCell', 'RunId', 'EnvironmentResetMode', 'ResetPolicySha256',
    'ResetAllowListSha256', 'OperationGrantSha256', 'SessionAnchorSha256',
    'CleanReceiptSha256', 'SnapshotReceiptSha256', 'PayloadSha256',
    'MessageBodyLength', 'EvidenceUri', 'EvidenceSha256', 'Status',
    'SigningKeyId', 'SignatureAlgorithm', 'Signature'
)
$script:CddsiVmTestRelayStateProperties = @(
    'SchemaVersion', 'ProtocolVersion', 'HostToVmRepositoryIdentity',
    'VmToHostRepositoryIdentity', 'ProductRepositoryIdentity', 'Revision',
    'ActiveCycleId', 'ActiveStatus',
    'ActiveSequence', 'ActiveMessageSha256', 'ActiveBinding', 'ActiveOutcome',
    'ActiveCleanReceiptSha256', 'ActiveSnapshotReceiptSha256',
    'ActiveEvidenceUri', 'ActiveEvidenceSha256', 'ActiveRepairSourceCycleId',
    'PendingRepair', 'RepairSourceCycleId', 'SeenMessageIds',
    'CompletedCycleIds', 'StoppedCycleIds', 'StateBindingToken'
)
$script:CddsiVmTestRelayBindingProperties = @(
    'HostToVmRepositoryIdentity', 'VmToHostRepositoryIdentity',
    'ProductRepositoryIdentity', 'RepairRef',
    'OsMatrixCell', 'RunId', 'RepositoryCommitSha', 'ArtifactProfile',
    'CandidateId', 'ArtifactSha256', 'SidecarSha256', 'RunbookSha256',
    'VmImageSha256', 'EnvironmentResetMode', 'ResetPolicySha256',
    'ResetAllowListSha256', 'OperationGrantSha256', 'SessionAnchorSha256'
)
$script:CddsiVmTestRelayMessageTypes = @(
    'TEST_REQUEST', 'VM_ACK', 'SNAPSHOT_READY', 'CLEAN_READY',
    'TEST_STARTED', 'TEST_RESULT', 'HOST_ACK', 'FIX_READY', 'STOP'
)
$script:CddsiVmTestRelayMessageRoles = @{
    TEST_REQUEST   = @('HostCoordinator')
    VM_ACK         = @('VmTester')
    SNAPSHOT_READY = @('HostCoordinator')
    CLEAN_READY    = @('VmTester')
    TEST_STARTED   = @('VmTester')
    TEST_RESULT    = @('VmTester')
    HOST_ACK       = @('HostCoordinator')
    FIX_READY      = @('HostCoordinator')
    STOP           = @('HostCoordinator')
}
$script:CddsiVmTestRelayMessageOutboxes = @{
    HostCoordinator = 'host-to-vm'
    VmTester        = 'vm-to-host'
}
$script:CddsiVmTestRelayMessageStatuses = @{
    VM_ACK         = @('VM_ACKED')
    SNAPSHOT_READY = @('ENVIRONMENT_PREPARING')
    CLEAN_READY    = @('CLEAN_READY')
    TEST_STARTED   = @('TEST_RUNNING')
    HOST_ACK       = @('HOST_ACKED')
    FIX_READY      = @('CANDIDATE_REBUILT')
    STOP           = @('STOPPED')
}

function ConvertTo-CddsiVmTestRelayCanonicalJson {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return 'null' }

    if ($Value -is [string] -or $Value -is [char]) {
        $text = [string]$Value
        $builder = New-Object System.Text.StringBuilder
        [void]$builder.Append('"')
        foreach ($character in $text.ToCharArray()) {
            $code = [int][char]$character
            $escape = $null
            switch ($code) {
                8 { $escape = '\b'; break }
                9 { $escape = '\t'; break }
                10 { $escape = '\n'; break }
                12 { $escape = '\f'; break }
                13 { $escape = '\r'; break }
                34 { $escape = '\"'; break }
                92 { $escape = '\\'; break }
            }
            if ($null -ne $escape) {
                [void]$builder.Append($escape)
            }
            elseif ($code -lt 32) {
                [void]$builder.Append(('\u{0:x4}' -f $code))
            }
            else {
                [void]$builder.Append($character)
            }
        }
        [void]$builder.Append('"')
        return $builder.ToString()
    }

    if ($Value -is [bool]) { return $(if ($Value) { 'true' } else { 'false' }) }

    $invariant = [Globalization.CultureInfo]::InvariantCulture
    if (
        $Value -is [byte] -or $Value -is [sbyte] -or
        $Value -is [int16] -or $Value -is [uint16] -or
        $Value -is [int32] -or $Value -is [uint32] -or
        $Value -is [int64] -or $Value -is [uint64]
    ) {
        return [Convert]::ToString($Value, $invariant)
    }
    if ($Value -is [decimal]) { return $Value.ToString('G29', $invariant) }
    if ($Value -is [double]) {
        if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) {
            throw 'Canonical relay JSON rejects non-finite numbers.'
        }
        return $Value.ToString('R', $invariant)
    }
    if ($Value -is [single]) {
        if ([single]::IsNaN($Value) -or [single]::IsInfinity($Value)) {
            throw 'Canonical relay JSON rejects non-finite numbers.'
        }
        return $Value.ToString('R', $invariant)
    }
    if ($Value -is [guid]) {
        return ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Value.ToString('D').ToLowerInvariant()
    }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -ne [DateTimeKind]::Utc) { throw 'Canonical relay JSON requires UTC DateTime values.' }
        return ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', $invariant)
    }
    if ($Value -is [DateTimeOffset]) {
        if ($Value.Offset -ne [TimeSpan]::Zero) { throw 'Canonical relay JSON requires UTC DateTimeOffset values.' }
        return ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', $invariant)
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $valueByKey = @{}
        $keys = New-Object System.Collections.Generic.List[string]
        foreach ($rawKey in $Value.Keys) {
            if ($rawKey -isnot [string] -or $valueByKey.ContainsKey($rawKey)) {
                throw 'Canonical relay JSON requires unique string dictionary keys.'
            }
            $keys.Add($rawKey)
            $valueByKey[$rawKey] = $Value[$rawKey]
        }
        [string[]]$sortedKeys = @($keys)
        [Array]::Sort($sortedKeys, [StringComparer]::Ordinal)
        $parts = @()
        foreach ($key in $sortedKeys) {
            $parts += ((ConvertTo-CddsiVmTestRelayCanonicalJson -Value $key) + ':' +
                (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $valueByKey[$key]))
        }
        return '{' + ($parts -join ',') + '}'
    }

    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = @()
        foreach ($item in $Value) { $parts += ,(ConvertTo-CddsiVmTestRelayCanonicalJson -Value $item) }
        return '[' + ($parts -join ',') + ']'
    }

    $propertyByName = @{}
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -isnot [string] -or $propertyByName.ContainsKey($property.Name)) {
            throw 'Canonical relay JSON requires unique property names.'
        }
        $names.Add($property.Name)
        $propertyByName[$property.Name] = $property.Value
    }
    [string[]]$sortedNames = @($names)
    [Array]::Sort($sortedNames, [StringComparer]::Ordinal)
    $propertyParts = @()
    foreach ($name in $sortedNames) {
        $propertyParts += ((ConvertTo-CddsiVmTestRelayCanonicalJson -Value $name) + ':' +
            (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $propertyByName[$name]))
    }
    return '{' + ($propertyParts -join ',') + '}'
}

function Get-CddsiVmTestRelayPayloadSha256 {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Payload)

    return Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Payload)
}

function Get-CddsiVmTestRelayMessageSha256 {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Envelope,
        [Parameter(Mandatory = $true)]$Payload
    )

    $message = [pscustomobject][ordered]@{ Envelope = $Envelope; Payload = $Payload }
    return Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $message)
}

function Get-CddsiVmTestRelayStateBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$State)

    if (-not (Test-CddsiExactPropertySet -InputObject $State -Expected $script:CddsiVmTestRelayStateProperties)) {
        throw 'Relay state does not match the exact state schema.'
    }
    $payload = [ordered]@{}
    foreach ($name in $script:CddsiVmTestRelayStateProperties) {
        if ($name -cne 'StateBindingToken') { $payload[$name] = $State.$name }
    }
    return Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $payload)
}

function Test-CddsiVmTestRelayEnvelope {
    [CmdletBinding()]
    param(
        [AllowNull()]$Envelope,
        [AllowNull()]$Payload,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][string]$ExpectedHostToVmRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$ExpectedVmToHostRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$ExpectedProductRepositoryIdentity,
        [Parameter(Mandatory = $true)]
        [ValidateSet('HostCoordinator', 'VmTester')]
        [string]$AuthenticatedSenderRole,
        [Parameter(Mandatory = $true)]
        [ValidateSet('host-to-vm', 'vm-to-host')]
        [string]$AuthenticatedOutbox,
        [AllowNull()][string]$ExternallyVerifiedSnapshotReceiptSha256 = $null,
        [AllowNull()][string]$ExternallyVerifiedSnapshotAuthorityBindingToken = $null,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 900,
        [ValidateRange(0, 300)][int]$MaximumClockSkewSeconds = 60,
        [ValidateRange(64, 1048576)][int]$MaximumMessageBodyBytes = 65536
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Envelope -Expected $script:CddsiVmTestRelayEnvelopeProperties)) {
        return $false
    }
    if (
        $Envelope.SchemaVersion -isnot [string] -or $Envelope.SchemaVersion -cne '1' -or
        $Envelope.ProtocolVersion -isnot [string] -or $Envelope.ProtocolVersion -cne $script:CddsiVmTestRelayProtocolVersion -or
        $Envelope.Lane -isnot [string] -or $Envelope.Lane -cne 'Fast'
    ) { return $false }

    $isSha256 = {
        param([AllowNull()]$Value, [bool]$AllowNull)
        if ($null -eq $Value) { return $AllowNull }
        return ($Value -is [string] -and $Value -match '^[a-f0-9]{64}$')
    }
    $isRepositoryIdentity = {
        param([AllowNull()]$Value)
        return (
            $Value -is [string] -and $Value.Length -le 192 -and
            [regex]::IsMatch($Value, $script:CddsiVmTestRelayRepositoryIdentityPattern)
        )
    }
    $isNonNegativeInteger = {
        param([AllowNull()]$Value)
        return (($Value -is [int] -or $Value -is [long]) -and [long]$Value -ge 0)
    }

    if (
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.MessageId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.CycleId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.Nonce) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.RunId)
    ) { return $false }
    if (
        ($Envelope.Sequence -isnot [int] -and $Envelope.Sequence -isnot [long]) -or
        [long]$Envelope.Sequence -lt 1 -or [long]$Envelope.Sequence -gt [int]::MaxValue
    ) { return $false }
    if ($script:CddsiVmTestRelayMessageTypes -cnotcontains $Envelope.MessageType) { return $false }
    if ($script:CddsiVmTestRelayMessageRoles[$Envelope.MessageType] -cnotcontains $Envelope.SenderRole) { return $false }
    if ($Envelope.SenderRole -cne $AuthenticatedSenderRole) { return $false }
    if (-not $script:CddsiVmTestRelayMessageOutboxes.ContainsKey($Envelope.SenderRole)) { return $false }
    if ($script:CddsiVmTestRelayMessageOutboxes[$Envelope.SenderRole] -cne $Envelope.Outbox) { return $false }
    if ($Envelope.Outbox -cne $AuthenticatedOutbox) { return $false }

    if (
        -not (& $isRepositoryIdentity $Envelope.HostToVmRepositoryIdentity) -or
        -not (& $isRepositoryIdentity $Envelope.VmToHostRepositoryIdentity) -or
        -not (& $isRepositoryIdentity $Envelope.PhysicalControlRepositoryIdentity) -or
        -not (& $isRepositoryIdentity $Envelope.ProductRepositoryIdentity) -or
        $Envelope.HostToVmRepositoryIdentity -cne $ExpectedHostToVmRepositoryIdentity -or
        $Envelope.VmToHostRepositoryIdentity -cne $ExpectedVmToHostRepositoryIdentity -or
        $Envelope.ProductRepositoryIdentity -cne $ExpectedProductRepositoryIdentity -or
        $Envelope.HostToVmRepositoryIdentity -ceq $Envelope.VmToHostRepositoryIdentity -or
        $Envelope.HostToVmRepositoryIdentity -ceq $Envelope.ProductRepositoryIdentity -or
        $Envelope.VmToHostRepositoryIdentity -ceq $Envelope.ProductRepositoryIdentity
    ) { return $false }
    $expectedPhysicalRepositoryIdentity = if ($AuthenticatedOutbox -ceq 'host-to-vm') {
        $ExpectedHostToVmRepositoryIdentity
    }
    else {
        $ExpectedVmToHostRepositoryIdentity
    }
    if ($Envelope.PhysicalControlRepositoryIdentity -cne $expectedPhysicalRepositoryIdentity) { return $false }
    if (
        $Envelope.RepairRef -isnot [string] -or $Envelope.RepairRef.Length -gt 192 -or
        -not [regex]::IsMatch($Envelope.RepairRef, '^refs/heads/codex/repair/[A-Za-z0-9][A-Za-z0-9._/-]*$') -or
        $Envelope.RepairRef.Contains('..') -or $Envelope.RepairRef.Contains('//') -or
        $Envelope.RepairRef.EndsWith('/')
    ) { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $Envelope.OsMatrixCell -MaxLength 128)) { return $false }
    if (@('VmCalibration', 'VmAcceptance', 'UserLive') -cnotcontains $Envelope.ArtifactProfile) { return $false }
    if ($null -ne $Envelope.CandidateId -and -not (Test-CddsiSafeIdentifierValue -Value $Envelope.CandidateId -MaxLength 128)) { return $false }
    if ($Envelope.ArtifactProfile -cne 'VmCalibration' -and $null -eq $Envelope.CandidateId) { return $false }
    if ($Envelope.RepositoryCommitSha -isnot [string] -or $Envelope.RepositoryCommitSha -notmatch '^(?:[a-f0-9]{40}|[a-f0-9]{64})$') { return $false }
    foreach ($name in @(
        'ArtifactSha256', 'SidecarSha256', 'RunbookSha256', 'VmImageSha256',
        'ResetPolicySha256', 'ResetAllowListSha256', 'OperationGrantSha256',
        'SessionAnchorSha256', 'PayloadSha256', 'ExpectedStateBindingToken'
    )) {
        if (-not (& $isSha256 $Envelope.$name $false)) { return $false }
    }
    foreach ($name in @('PreviousMessageSha256', 'CleanReceiptSha256', 'SnapshotReceiptSha256', 'EvidenceSha256')) {
        if (-not (& $isSha256 $Envelope.$name $true)) { return $false }
    }
    if (@('GuestReset', 'SnapshotRestore') -cnotcontains $Envelope.EnvironmentResetMode) { return $false }

    if (
        -not (Test-CddsiUtcTimestampValue -Value $Envelope.CreatedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Envelope.ExpiresAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $ValidationTimeUtc)
    ) { return $false }
    $createdAt = [DateTimeOffset]::Parse($Envelope.CreatedAtUtc)
    $expiresAt = [DateTimeOffset]::Parse($Envelope.ExpiresAtUtc)
    $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
    if (
        $createdAt -gt $validationTime.AddSeconds($MaximumClockSkewSeconds) -or
        ($validationTime - $createdAt).TotalSeconds -gt $MaximumAgeSeconds -or
        $expiresAt -le $createdAt -or $expiresAt -le $validationTime -or
        ($expiresAt - $createdAt).TotalSeconds -gt $MaximumAgeSeconds
    ) { return $false }
    if ([long]$Envelope.Sequence -eq 1) {
        if ($null -ne $Envelope.PreviousMessageSha256) { return $false }
    }
    elseif ($null -eq $Envelope.PreviousMessageSha256) { return $false }

    if (
        ($Envelope.MessageBodyLength -isnot [int] -and $Envelope.MessageBodyLength -isnot [long]) -or
        [long]$Envelope.MessageBodyLength -lt 2 -or
        [long]$Envelope.MessageBodyLength -gt $MaximumMessageBodyBytes
    ) { return $false }
    try {
        $canonicalPayload = ConvertTo-CddsiVmTestRelayCanonicalJson -Value $Payload
        $payloadLength = [Text.Encoding]::UTF8.GetByteCount($canonicalPayload)
        $payloadSha256 = Get-CddsiSupplyChainTextBindingToken -Text $canonicalPayload
    }
    catch { return $false }
    if ([long]$Envelope.MessageBodyLength -ne [long]$payloadLength -or $Envelope.PayloadSha256 -cne $payloadSha256) { return $false }
    if (@(Find-CddsiPotentialSecrets -Content $canonicalPayload -Source '<vm-test-relay-payload>').Count -ne 0) { return $false }

    if (
        $null -ne $Envelope.SigningKeyId -or
        $null -ne $Envelope.SignatureAlgorithm -or
        $null -ne $Envelope.Signature
    ) { return $false }

    $hasEvidenceUri = $null -ne $Envelope.EvidenceUri
    $hasEvidenceSha256 = $null -ne $Envelope.EvidenceSha256
    if ($hasEvidenceUri -ne $hasEvidenceSha256) { return $false }
    if ($hasEvidenceUri) {
        if (
            $Envelope.EvidenceUri -isnot [string] -or $Envelope.EvidenceUri.Length -gt 320 -or
            -not [regex]::IsMatch($Envelope.EvidenceUri, '^diagnostic/[A-Za-z0-9][A-Za-z0-9._/-]*$') -or
            $Envelope.EvidenceUri.Contains('..') -or $Envelope.EvidenceUri.Contains('//')
        ) { return $false }
        if (@('TEST_RESULT', 'HOST_ACK') -cnotcontains $Envelope.MessageType) { return $false }
    }

    if ($Envelope.EnvironmentResetMode -ceq 'GuestReset' -and $null -ne $Envelope.SnapshotReceiptSha256) { return $false }
    if ($Envelope.MessageType -ceq 'SNAPSHOT_READY') {
        if ($Envelope.EnvironmentResetMode -cne 'SnapshotRestore' -or $null -eq $Envelope.SnapshotReceiptSha256 -or $null -ne $Envelope.CleanReceiptSha256) { return $false }
    }
    $cleanRequired = @('CLEAN_READY', 'TEST_STARTED', 'TEST_RESULT', 'HOST_ACK') -ccontains $Envelope.MessageType
    if ($cleanRequired -and $null -eq $Envelope.CleanReceiptSha256) { return $false }
    if ($cleanRequired -and $Envelope.EnvironmentResetMode -ceq 'SnapshotRestore' -and $null -eq $Envelope.SnapshotReceiptSha256) { return $false }
    if (@('TEST_REQUEST', 'VM_ACK', 'FIX_READY') -ccontains $Envelope.MessageType) {
        if ($null -ne $Envelope.CleanReceiptSha256 -or $null -ne $Envelope.SnapshotReceiptSha256 -or $hasEvidenceUri) { return $false }
    }
    if (@('CLEAN_READY', 'TEST_STARTED') -ccontains $Envelope.MessageType -and $hasEvidenceUri) { return $false }

    if ($Envelope.MessageType -ceq 'TEST_REQUEST') {
        $expected = @('SchemaVersion', 'ContractVersion', 'RequestKind', 'PriorCycleId')
        if (-not (Test-CddsiExactPropertySet -InputObject $Payload -Expected $expected)) { return $false }
        if ($Payload.SchemaVersion -cne '1' -or $Payload.ContractVersion -cne 'cddsi-vm-test-relay-test-request-v1') { return $false }
        if ($Payload.RequestKind -ceq 'Initial') {
            if ($null -ne $Payload.PriorCycleId -or $Envelope.Status -cne 'TEST_REQUESTED') { return $false }
        }
        elseif ($Payload.RequestKind -ceq 'Retest') {
            if (-not (Test-CddsiCanonicalUuidValue -Value $Payload.PriorCycleId) -or $Envelope.Status -cne 'RETEST_REQUESTED') { return $false }
        }
        else { return $false }
    }
    elseif ($Envelope.MessageType -ceq 'SNAPSHOT_READY') {
        $expected = @(
            'SchemaVersion', 'ContractVersion', 'Code', 'ExternalReceiptAuthority',
            'ExternalReceiptAuthorityBindingToken'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Payload -Expected $expected)) { return $false }
        if (
            $Payload.SchemaVersion -cne '1' -or
            $Payload.ContractVersion -cne 'cddsi-vm-test-relay-snapshot-ready-v1' -or
            $Payload.Code -cne 'EXTERNAL_SNAPSHOT_VERIFIED' -or
            $Payload.ExternalReceiptAuthority -cne 'HypervisorSupervisor' -or
            -not (& $isSha256 $Payload.ExternalReceiptAuthorityBindingToken $false) -or
            -not (& $isSha256 $ExternallyVerifiedSnapshotReceiptSha256 $false) -or
            -not (& $isSha256 $ExternallyVerifiedSnapshotAuthorityBindingToken $false) -or
            $Envelope.SnapshotReceiptSha256 -cne $ExternallyVerifiedSnapshotReceiptSha256 -or
            $Payload.ExternalReceiptAuthorityBindingToken -cne
                $ExternallyVerifiedSnapshotAuthorityBindingToken -or
            $Envelope.Status -cne 'ENVIRONMENT_PREPARING'
        ) { return $false }
    }
    elseif ($Envelope.MessageType -ceq 'TEST_RESULT') {
        $expected = @(
            'SchemaVersion', 'ContractVersion', 'CycleId', 'RunId', 'Phase',
            'MatrixCell', 'OverallStatus', 'EvidenceClass', 'AcceptanceReceiptUri',
            'AcceptanceReceiptSha256', 'SecretFindingCount',
            'ForbiddenMutationCount', 'UnexpectedLedgerEntryCount', 'SummaryCode'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Payload -Expected $expected)) { return $false }
        if (
            $Payload.SchemaVersion -cne '1' -or
            $Payload.ContractVersion -cne 'cddsi-vm-test-relay-test-result-v1' -or
            $Payload.CycleId -cne $Envelope.CycleId -or $Payload.RunId -cne $Envelope.RunId -or
            $Payload.MatrixCell -cne $Envelope.OsMatrixCell -or
            @('Synthetic', 'P10A', 'P11') -cnotcontains $Payload.Phase -or
            @('PASS', 'FAIL', 'BLOCKED') -cnotcontains $Payload.OverallStatus -or
            $Payload.EvidenceClass -cne 'Diagnostic' -or
            $null -ne $Payload.AcceptanceReceiptUri -or
            $null -ne $Payload.AcceptanceReceiptSha256 -or
            -not (& $isNonNegativeInteger $Payload.SecretFindingCount) -or
            -not (& $isNonNegativeInteger $Payload.ForbiddenMutationCount) -or
            -not (& $isNonNegativeInteger $Payload.UnexpectedLedgerEntryCount) -or
            [long]$Payload.SecretFindingCount -ne 0 -or
            -not (Test-CddsiSafeIdentifierValue -Value $Payload.SummaryCode -MaxLength 128)
        ) { return $false }
        $expectedStatus = @{ PASS = 'TEST_PASSED'; FAIL = 'TEST_FAILED'; BLOCKED = 'TEST_BLOCKED' }[$Payload.OverallStatus]
        if ($Envelope.Status -cne $expectedStatus) { return $false }
        if (
            $Payload.OverallStatus -ceq 'PASS' -and
            ([long]$Payload.ForbiddenMutationCount -ne 0 -or [long]$Payload.UnexpectedLedgerEntryCount -ne 0)
        ) { return $false }
    }
    elseif ($Envelope.MessageType -ceq 'FIX_READY') {
        $expected = @('SchemaVersion', 'ContractVersion', 'RepairSourceCycleId', 'ChangeClass', 'CandidateRebuilt')
        if (-not (Test-CddsiExactPropertySet -InputObject $Payload -Expected $expected)) { return $false }
        if (
            $Payload.SchemaVersion -cne '1' -or
            $Payload.ContractVersion -cne 'cddsi-vm-test-relay-fix-ready-v1' -or
            -not (Test-CddsiCanonicalUuidValue -Value $Payload.RepairSourceCycleId) -or
            @('ProductCode', 'CalibrationPackage', 'CandidateRebuild') -cnotcontains $Payload.ChangeClass -or
            $Payload.CandidateRebuilt -isnot [bool] -or -not $Payload.CandidateRebuilt -or
            $Envelope.Status -cne 'CANDIDATE_REBUILT'
        ) { return $false }
    }
    elseif ($Envelope.MessageType -ceq 'STOP') {
        $expected = @('SchemaVersion', 'ContractVersion', 'ReasonCode')
        if (-not (Test-CddsiExactPropertySet -InputObject $Payload -Expected $expected)) { return $false }
        if (
            $Payload.SchemaVersion -cne '1' -or
            $Payload.ContractVersion -cne 'cddsi-vm-test-relay-stop-v1' -or
            -not (Test-CddsiSafeIdentifierValue -Value $Payload.ReasonCode -MaxLength 128) -or
            $Envelope.Status -cne 'STOPPED'
        ) { return $false }
    }
    else {
        $expected = @('SchemaVersion', 'ContractVersion', 'Code')
        if (-not (Test-CddsiExactPropertySet -InputObject $Payload -Expected $expected)) { return $false }
        if (
            $Payload.SchemaVersion -cne '1' -or
            $Payload.ContractVersion -cne 'cddsi-vm-test-relay-control-v1' -or
            -not (Test-CddsiSafeIdentifierValue -Value $Payload.Code -MaxLength 128) -or
            $script:CddsiVmTestRelayMessageStatuses[$Envelope.MessageType] -cnotcontains $Envelope.Status
        ) { return $false }
    }

    return $true
}

function New-CddsiVmTestRelayState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$HostToVmRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$VmToHostRepositoryIdentity,
        [Parameter(Mandatory = $true)][string]$ProductRepositoryIdentity
    )

    if (
        $HostToVmRepositoryIdentity.Length -gt 192 -or
        $VmToHostRepositoryIdentity.Length -gt 192 -or
        $ProductRepositoryIdentity.Length -gt 192 -or
        -not [regex]::IsMatch($HostToVmRepositoryIdentity, $script:CddsiVmTestRelayRepositoryIdentityPattern) -or
        -not [regex]::IsMatch($VmToHostRepositoryIdentity, $script:CddsiVmTestRelayRepositoryIdentityPattern) -or
        -not [regex]::IsMatch($ProductRepositoryIdentity, $script:CddsiVmTestRelayRepositoryIdentityPattern) -or
        $HostToVmRepositoryIdentity -ceq $VmToHostRepositoryIdentity -or
        $HostToVmRepositoryIdentity -ceq $ProductRepositoryIdentity -or
        $VmToHostRepositoryIdentity -ceq $ProductRepositoryIdentity
    ) { throw 'Relay state requires three distinct canonical repository identities.' }

    $state = [pscustomobject][ordered]@{
        SchemaVersion                 = 1
        ProtocolVersion               = $script:CddsiVmTestRelayStateVersion
        HostToVmRepositoryIdentity    = $HostToVmRepositoryIdentity
        VmToHostRepositoryIdentity    = $VmToHostRepositoryIdentity
        ProductRepositoryIdentity     = $ProductRepositoryIdentity
        Revision                      = 0
        ActiveCycleId                 = $null
        ActiveStatus                  = 'IDLE'
        ActiveSequence                = 0
        ActiveMessageSha256           = $null
        ActiveBinding                 = $null
        ActiveOutcome                 = $null
        ActiveCleanReceiptSha256      = $null
        ActiveSnapshotReceiptSha256   = $null
        ActiveEvidenceUri             = $null
        ActiveEvidenceSha256          = $null
        ActiveRepairSourceCycleId     = $null
        PendingRepair                 = $false
        RepairSourceCycleId           = $null
        SeenMessageIds                = @()
        CompletedCycleIds             = @()
        StoppedCycleIds               = @()
        StateBindingToken             = $null
    }
    $state.StateBindingToken = Get-CddsiVmTestRelayStateBindingToken -State $state
    return $state
}

function Test-CddsiVmTestRelayState {
    [CmdletBinding()]
    param([AllowNull()]$State)

    if (-not (Test-CddsiExactPropertySet -InputObject $State -Expected $script:CddsiVmTestRelayStateProperties)) { return $false }
    if (
        ($State.SchemaVersion -isnot [int] -and $State.SchemaVersion -isnot [long]) -or [long]$State.SchemaVersion -ne 1 -or
        $State.ProtocolVersion -isnot [string] -or $State.ProtocolVersion -cne $script:CddsiVmTestRelayStateVersion -or
        ($State.Revision -isnot [int] -and $State.Revision -isnot [long]) -or [long]$State.Revision -lt 0 -or
        $State.PendingRepair -isnot [bool] -or
        $State.StateBindingToken -isnot [string] -or $State.StateBindingToken -notmatch '^[a-f0-9]{64}$'
    ) { return $false }
    try {
        if ($State.StateBindingToken -cne (Get-CddsiVmTestRelayStateBindingToken -State $State)) { return $false }
    }
    catch { return $false }

    if (
        $State.HostToVmRepositoryIdentity -isnot [string] -or
        $State.VmToHostRepositoryIdentity -isnot [string] -or
        $State.ProductRepositoryIdentity -isnot [string] -or
        -not [regex]::IsMatch($State.HostToVmRepositoryIdentity, $script:CddsiVmTestRelayRepositoryIdentityPattern) -or
        -not [regex]::IsMatch($State.VmToHostRepositoryIdentity, $script:CddsiVmTestRelayRepositoryIdentityPattern) -or
        -not [regex]::IsMatch($State.ProductRepositoryIdentity, $script:CddsiVmTestRelayRepositoryIdentityPattern) -or
        $State.HostToVmRepositoryIdentity -ceq $State.VmToHostRepositoryIdentity -or
        $State.HostToVmRepositoryIdentity -ceq $State.ProductRepositoryIdentity -or
        $State.VmToHostRepositoryIdentity -ceq $State.ProductRepositoryIdentity
    ) { return $false }

    foreach ($name in @('SeenMessageIds', 'CompletedCycleIds', 'StoppedCycleIds')) {
        if ($State.$name -isnot [System.Array]) { return $false }
        $values = @($State.$name)
        if ($values.Count -ne @($values | Sort-Object -Unique).Count) { return $false }
        foreach ($value in $values) {
            if (-not (Test-CddsiCanonicalUuidValue -Value $value)) { return $false }
        }
    }
    if (@($State.CompletedCycleIds | Where-Object { $State.StoppedCycleIds -ccontains $_ }).Count -ne 0) { return $false }

    if ($State.PendingRepair) {
        if (-not (Test-CddsiCanonicalUuidValue -Value $State.RepairSourceCycleId)) { return $false }
        if ($State.CompletedCycleIds -cnotcontains $State.RepairSourceCycleId) { return $false }
    }
    elseif ($null -ne $State.RepairSourceCycleId) { return $false }

    if ($null -eq $State.ActiveCycleId) {
        if (
            $State.ActiveStatus -cne 'IDLE' -or [long]$State.ActiveSequence -ne 0 -or
            $null -ne $State.ActiveMessageSha256 -or $null -ne $State.ActiveBinding -or
            $null -ne $State.ActiveOutcome -or $null -ne $State.ActiveCleanReceiptSha256 -or
            $null -ne $State.ActiveSnapshotReceiptSha256 -or $null -ne $State.ActiveEvidenceUri -or
            $null -ne $State.ActiveEvidenceSha256 -or $null -ne $State.ActiveRepairSourceCycleId
        ) { return $false }
        return $true
    }

    if (
        -not (Test-CddsiCanonicalUuidValue -Value $State.ActiveCycleId) -or
        $State.CompletedCycleIds -ccontains $State.ActiveCycleId -or
        $State.StoppedCycleIds -ccontains $State.ActiveCycleId -or
        ($State.ActiveSequence -isnot [int] -and $State.ActiveSequence -isnot [long]) -or
        [long]$State.ActiveSequence -lt 1 -or
        $State.ActiveMessageSha256 -isnot [string] -or $State.ActiveMessageSha256 -notmatch '^[a-f0-9]{64}$' -or
        $State.PendingRepair
    ) { return $false }
    if (@(
        'CANDIDATE_REBUILT', 'TEST_REQUESTED', 'RETEST_REQUESTED', 'VM_ACKED',
        'ENVIRONMENT_PREPARING', 'CLEAN_READY', 'TEST_RUNNING',
        'TEST_PASSED', 'TEST_FAILED', 'TEST_BLOCKED'
    ) -cnotcontains $State.ActiveStatus) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $State.ActiveBinding -Expected $script:CddsiVmTestRelayBindingProperties)) { return $false }
    if (
        $State.ActiveBinding.HostToVmRepositoryIdentity -cne $State.HostToVmRepositoryIdentity -or
        $State.ActiveBinding.VmToHostRepositoryIdentity -cne $State.VmToHostRepositoryIdentity -or
        $State.ActiveBinding.ProductRepositoryIdentity -cne $State.ProductRepositoryIdentity
    ) { return $false }
    foreach ($name in @(
        'ArtifactSha256', 'SidecarSha256', 'RunbookSha256', 'VmImageSha256',
        'ResetPolicySha256', 'ResetAllowListSha256', 'OperationGrantSha256',
        'SessionAnchorSha256'
    )) {
        if ($State.ActiveBinding.$name -isnot [string] -or $State.ActiveBinding.$name -notmatch '^[a-f0-9]{64}$') { return $false }
    }
    foreach ($name in @('ActiveCleanReceiptSha256', 'ActiveSnapshotReceiptSha256', 'ActiveEvidenceSha256')) {
        if ($null -ne $State.$name -and ($State.$name -isnot [string] -or $State.$name -notmatch '^[a-f0-9]{64}$')) { return $false }
    }
    if (($null -eq $State.ActiveEvidenceUri) -ne ($null -eq $State.ActiveEvidenceSha256)) { return $false }
    if ($State.ActiveBinding.EnvironmentResetMode -ceq 'GuestReset' -and $null -ne $State.ActiveSnapshotReceiptSha256) { return $false }
    if (@('CLEAN_READY', 'TEST_RUNNING', 'TEST_PASSED', 'TEST_FAILED', 'TEST_BLOCKED') -ccontains $State.ActiveStatus) {
        if ($null -eq $State.ActiveCleanReceiptSha256) { return $false }
        if ($State.ActiveBinding.EnvironmentResetMode -ceq 'SnapshotRestore' -and $null -eq $State.ActiveSnapshotReceiptSha256) { return $false }
    }
    if (@('TEST_PASSED', 'TEST_FAILED', 'TEST_BLOCKED') -ccontains $State.ActiveStatus) {
        if (@('PASS', 'FAIL', 'BLOCKED') -cnotcontains $State.ActiveOutcome) { return $false }
    }
    elseif ($null -ne $State.ActiveOutcome) { return $false }
    if ($null -ne $State.ActiveRepairSourceCycleId -and -not (Test-CddsiCanonicalUuidValue -Value $State.ActiveRepairSourceCycleId)) { return $false }
    if ($State.ActiveStatus -ceq 'CANDIDATE_REBUILT' -and $null -eq $State.ActiveRepairSourceCycleId) { return $false }
    return $true
}

function Resolve-CddsiVmTestRelayTransition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$State,
        [Parameter(Mandatory = $true)]$Envelope,
        [Parameter(Mandatory = $true)]$Payload,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)]
        [ValidateSet('HostCoordinator', 'VmTester')]
        [string]$AuthenticatedSenderRole,
        [Parameter(Mandatory = $true)]
        [ValidateSet('host-to-vm', 'vm-to-host')]
        [string]$AuthenticatedOutbox,
        [AllowNull()][string]$ExternallyVerifiedSnapshotReceiptSha256 = $null,
        [AllowNull()][string]$ExternallyVerifiedSnapshotAuthorityBindingToken = $null,
        [ValidateRange(1, 86400)][int]$MaximumAgeSeconds = 900,
        [ValidateRange(0, 300)][int]$MaximumClockSkewSeconds = 60,
        [ValidateRange(64, 1048576)][int]$MaximumMessageBodyBytes = 65536
    )

    $reject = {
        param([string]$ErrorCode, [AllowNull()][string]$MessageSha256)
        return [pscustomobject][ordered]@{
            SchemaVersion             = 1
            ContractVersion           = 'cddsi-vm-test-relay-transition-v1'
            Accepted                  = $false
            Advanced                  = $false
            ErrorCode                 = $ErrorCode
            MessageSha256             = $MessageSha256
            PreviousStateBindingToken = $State.StateBindingToken
            State                     = $State
        }
    }

    if (-not (Test-CddsiVmTestRelayState -State $State)) { return & $reject 'RELAY_STATE_INVALID' $null }
    if ($Envelope.Lane -is [string] -and $Envelope.Lane -ceq 'Formal') { return & $reject 'FORMAL_LANE_UNAVAILABLE' $null }
    if (-not (Test-CddsiVmTestRelayEnvelope -Envelope $Envelope -Payload $Payload `
        -ValidationTimeUtc $ValidationTimeUtc `
        -ExpectedHostToVmRepositoryIdentity $State.HostToVmRepositoryIdentity `
        -ExpectedVmToHostRepositoryIdentity $State.VmToHostRepositoryIdentity `
        -ExpectedProductRepositoryIdentity $State.ProductRepositoryIdentity `
        -AuthenticatedSenderRole $AuthenticatedSenderRole `
        -AuthenticatedOutbox $AuthenticatedOutbox `
        -ExternallyVerifiedSnapshotReceiptSha256 $ExternallyVerifiedSnapshotReceiptSha256 `
        -ExternallyVerifiedSnapshotAuthorityBindingToken $ExternallyVerifiedSnapshotAuthorityBindingToken `
        -MaximumAgeSeconds $MaximumAgeSeconds `
        -MaximumClockSkewSeconds $MaximumClockSkewSeconds `
        -MaximumMessageBodyBytes $MaximumMessageBodyBytes)) {
        return & $reject 'RELAY_ENVELOPE_INVALID' $null
    }

    $messageSha256 = Get-CddsiVmTestRelayMessageSha256 -Envelope $Envelope -Payload $Payload
    if ($State.SeenMessageIds -ccontains $Envelope.MessageId) { return & $reject 'MESSAGE_REPLAY' $messageSha256 }
    if ($Envelope.ExpectedStateBindingToken -cne $State.StateBindingToken) { return & $reject 'STATE_CAS_MISMATCH' $messageSha256 }
    if ($State.CompletedCycleIds -ccontains $Envelope.CycleId -or $State.StoppedCycleIds -ccontains $Envelope.CycleId) {
        return & $reject 'CYCLE_CLOSED' $messageSha256
    }

    $binding = [pscustomobject][ordered]@{
        HostToVmRepositoryIdentity = $Envelope.HostToVmRepositoryIdentity
        VmToHostRepositoryIdentity = $Envelope.VmToHostRepositoryIdentity
        ProductRepositoryIdentity = $Envelope.ProductRepositoryIdentity
        RepairRef                  = $Envelope.RepairRef
        OsMatrixCell               = $Envelope.OsMatrixCell
        RunId                      = $Envelope.RunId
        RepositoryCommitSha        = $Envelope.RepositoryCommitSha
        ArtifactProfile            = $Envelope.ArtifactProfile
        CandidateId                = $Envelope.CandidateId
        ArtifactSha256             = $Envelope.ArtifactSha256
        SidecarSha256              = $Envelope.SidecarSha256
        RunbookSha256              = $Envelope.RunbookSha256
        VmImageSha256              = $Envelope.VmImageSha256
        EnvironmentResetMode       = $Envelope.EnvironmentResetMode
        ResetPolicySha256          = $Envelope.ResetPolicySha256
        ResetAllowListSha256       = $Envelope.ResetAllowListSha256
        OperationGrantSha256       = $Envelope.OperationGrantSha256
        SessionAnchorSha256        = $Envelope.SessionAnchorSha256
    }

    $nextValues = [ordered]@{}
    foreach ($name in $script:CddsiVmTestRelayStateProperties) { $nextValues[$name] = $State.$name }
    $nextValues.Revision = [long]$State.Revision + 1
    $nextValues.SeenMessageIds = @($State.SeenMessageIds) + @($Envelope.MessageId)

    if ($null -eq $State.ActiveCycleId) {
        if ([long]$Envelope.Sequence -ne 1 -or $null -ne $Envelope.PreviousMessageSha256) {
            return & $reject 'SEQUENCE_MISMATCH' $messageSha256
        }
        if ($Envelope.MessageType -ceq 'TEST_REQUEST') {
            if ($State.PendingRepair -or $Payload.RequestKind -cne 'Initial' -or $Envelope.Status -cne 'TEST_REQUESTED') {
                return & $reject 'ILLEGAL_STATE_TRANSITION' $messageSha256
            }
            $activeRepairSource = $null
        }
        elseif ($Envelope.MessageType -ceq 'FIX_READY') {
            if (-not $State.PendingRepair -or $Payload.RepairSourceCycleId -cne $State.RepairSourceCycleId) {
                return & $reject 'ILLEGAL_STATE_TRANSITION' $messageSha256
            }
            $activeRepairSource = $Payload.RepairSourceCycleId
            $nextValues.PendingRepair = $false
            $nextValues.RepairSourceCycleId = $null
        }
        else { return & $reject 'ILLEGAL_STATE_TRANSITION' $messageSha256 }

        $nextValues.ActiveCycleId = $Envelope.CycleId
        $nextValues.ActiveStatus = $Envelope.Status
        $nextValues.ActiveSequence = [long]$Envelope.Sequence
        $nextValues.ActiveMessageSha256 = $messageSha256
        $nextValues.ActiveBinding = $binding
        $nextValues.ActiveOutcome = $null
        $nextValues.ActiveCleanReceiptSha256 = $null
        $nextValues.ActiveSnapshotReceiptSha256 = $null
        $nextValues.ActiveEvidenceUri = $null
        $nextValues.ActiveEvidenceSha256 = $null
        $nextValues.ActiveRepairSourceCycleId = $activeRepairSource
    }
    else {
        if ($Envelope.CycleId -cne $State.ActiveCycleId) { return & $reject 'ACTIVE_CYCLE_CONFLICT' $messageSha256 }
        if ([long]$Envelope.Sequence -ne ([long]$State.ActiveSequence + 1)) { return & $reject 'SEQUENCE_MISMATCH' $messageSha256 }
        if ($Envelope.PreviousMessageSha256 -cne $State.ActiveMessageSha256) { return & $reject 'PREVIOUS_MESSAGE_MISMATCH' $messageSha256 }
        if ((ConvertTo-CddsiVmTestRelayCanonicalJson -Value $binding) -cne
            (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $State.ActiveBinding)) {
            return & $reject 'CYCLE_BINDING_MISMATCH' $messageSha256
        }

        $isStop = $Envelope.MessageType -ceq 'STOP'
        $legal = $false
        if ($isStop) {
            $legal = $true
        }
        elseif ($State.ActiveStatus -ceq 'CANDIDATE_REBUILT') {
            $legal = (
                $Envelope.MessageType -ceq 'TEST_REQUEST' -and
                $Envelope.Status -ceq 'RETEST_REQUESTED' -and
                $Payload.RequestKind -ceq 'Retest' -and
                $Payload.PriorCycleId -ceq $State.ActiveRepairSourceCycleId
            )
        }
        elseif (@('TEST_REQUESTED', 'RETEST_REQUESTED') -ccontains $State.ActiveStatus) {
            $legal = ($Envelope.MessageType -ceq 'VM_ACK' -and $Envelope.Status -ceq 'VM_ACKED')
        }
        elseif ($State.ActiveStatus -ceq 'VM_ACKED') {
            if ($State.ActiveBinding.EnvironmentResetMode -ceq 'GuestReset') {
                $legal = ($Envelope.MessageType -ceq 'CLEAN_READY' -and $Envelope.Status -ceq 'CLEAN_READY')
            }
            else {
                $legal = ($Envelope.MessageType -ceq 'SNAPSHOT_READY' -and $Envelope.Status -ceq 'ENVIRONMENT_PREPARING')
            }
        }
        elseif ($State.ActiveStatus -ceq 'ENVIRONMENT_PREPARING') {
            $legal = ($Envelope.MessageType -ceq 'CLEAN_READY' -and $Envelope.Status -ceq 'CLEAN_READY')
        }
        elseif ($State.ActiveStatus -ceq 'CLEAN_READY') {
            $legal = ($Envelope.MessageType -ceq 'TEST_STARTED' -and $Envelope.Status -ceq 'TEST_RUNNING')
        }
        elseif ($State.ActiveStatus -ceq 'TEST_RUNNING') {
            $legal = ($Envelope.MessageType -ceq 'TEST_RESULT' -and @('TEST_PASSED', 'TEST_FAILED', 'TEST_BLOCKED') -ccontains $Envelope.Status)
        }
        elseif (@('TEST_PASSED', 'TEST_FAILED', 'TEST_BLOCKED') -ccontains $State.ActiveStatus) {
            $legal = ($Envelope.MessageType -ceq 'HOST_ACK' -and $Envelope.Status -ceq 'HOST_ACKED')
        }
        if (-not $legal) { return & $reject 'ILLEGAL_STATE_TRANSITION' $messageSha256 }

        if ($null -ne $State.ActiveSnapshotReceiptSha256 -and $Envelope.SnapshotReceiptSha256 -cne $State.ActiveSnapshotReceiptSha256) {
            return & $reject 'SNAPSHOT_RECEIPT_MISMATCH' $messageSha256
        }
        if ($null -ne $State.ActiveCleanReceiptSha256 -and $Envelope.CleanReceiptSha256 -cne $State.ActiveCleanReceiptSha256) {
            return & $reject 'CLEAN_RECEIPT_MISMATCH' $messageSha256
        }
        if ($Envelope.MessageType -ceq 'HOST_ACK') {
            if ($Envelope.EvidenceUri -cne $State.ActiveEvidenceUri -or $Envelope.EvidenceSha256 -cne $State.ActiveEvidenceSha256) {
                return & $reject 'EVIDENCE_REFERENCE_MISMATCH' $messageSha256
            }
        }

        $nextValues.ActiveStatus = $Envelope.Status
        $nextValues.ActiveSequence = [long]$Envelope.Sequence
        $nextValues.ActiveMessageSha256 = $messageSha256
        if ($Envelope.MessageType -ceq 'SNAPSHOT_READY') {
            $nextValues.ActiveSnapshotReceiptSha256 = $Envelope.SnapshotReceiptSha256
        }
        if ($Envelope.MessageType -ceq 'CLEAN_READY') {
            $nextValues.ActiveCleanReceiptSha256 = $Envelope.CleanReceiptSha256
            $nextValues.ActiveSnapshotReceiptSha256 = $Envelope.SnapshotReceiptSha256
        }
        if ($Envelope.MessageType -ceq 'TEST_RESULT') {
            $nextValues.ActiveOutcome = $Payload.OverallStatus
            $nextValues.ActiveEvidenceUri = $Envelope.EvidenceUri
            $nextValues.ActiveEvidenceSha256 = $Envelope.EvidenceSha256
        }

        if ($isStop -or $Envelope.MessageType -ceq 'HOST_ACK') {
            $closedCycleId = $State.ActiveCycleId
            if ($isStop) {
                $nextValues.StoppedCycleIds = @($State.StoppedCycleIds) + @($closedCycleId)
                $nextValues.PendingRepair = $false
                $nextValues.RepairSourceCycleId = $null
            }
            else {
                $nextValues.CompletedCycleIds = @($State.CompletedCycleIds) + @($closedCycleId)
                $requiresRepair = @('FAIL', 'BLOCKED') -ccontains $State.ActiveOutcome
                $nextValues.PendingRepair = $requiresRepair
                $nextValues.RepairSourceCycleId = $(if ($requiresRepair) { $closedCycleId } else { $null })
            }
            $nextValues.ActiveCycleId = $null
            $nextValues.ActiveStatus = 'IDLE'
            $nextValues.ActiveSequence = 0
            $nextValues.ActiveMessageSha256 = $null
            $nextValues.ActiveBinding = $null
            $nextValues.ActiveOutcome = $null
            $nextValues.ActiveCleanReceiptSha256 = $null
            $nextValues.ActiveSnapshotReceiptSha256 = $null
            $nextValues.ActiveEvidenceUri = $null
            $nextValues.ActiveEvidenceSha256 = $null
            $nextValues.ActiveRepairSourceCycleId = $null
        }
    }

    $nextValues.StateBindingToken = $null
    $nextState = [pscustomobject]$nextValues
    $nextState.StateBindingToken = Get-CddsiVmTestRelayStateBindingToken -State $nextState
    if (-not (Test-CddsiVmTestRelayState -State $nextState)) { return & $reject 'RELAY_NEXT_STATE_INVALID' $messageSha256 }

    return [pscustomobject][ordered]@{
        SchemaVersion             = 1
        ContractVersion           = 'cddsi-vm-test-relay-transition-v1'
        Accepted                  = $true
        Advanced                  = $true
        ErrorCode                 = ''
        MessageSha256             = $messageSha256
        PreviousStateBindingToken = $State.StateBindingToken
        State                     = $nextState
    }
}
