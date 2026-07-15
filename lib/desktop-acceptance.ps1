# desktop-acceptance.ps1 - Synthetic acceptance, external-evidence and redacted-report contracts.
# This module never launches Claude Desktop, calls an API or performs UI automation.

function Get-CddsiAcceptancePlan {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Id = 'desktop_msix'; Description = 'Claude Desktop MSIX readiness'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'git_ready'; Description = 'Git for Windows readiness'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'cowork_ready'; Description = 'Cowork prerequisite readiness'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'config_atomic'; Description = 'Managed-policy backup and restore readiness'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'chat'; Description = 'Chat capability and UI evidence'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'code'; Description = 'Code capability and UI evidence'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'cowork'; Description = 'Cowork capability and UI evidence'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'claude_code_settings_not_accessed'; Description = 'Claude Code settings zero-read evidence'; Implemented = $true; Execution = 'SyntheticOnly' },
        [pscustomobject]@{ Id = 'api_key_leak_free'; Description = 'Secret scan evidence'; Implemented = $true; Execution = 'SyntheticOnly' }
    )
}

function Get-CddsiClaudeCodeSettingsIntegrityContract {
    [CmdletBinding()]
    param()

    return [pscustomobject][ordered]@{
        policy                  = 'do_not_read_or_modify'
        hashOnlyProviderAllowed = $false
        contentParsingAllowed   = $false
        contentLoggingAllowed   = $false
        implementationStatus    = 'policy_frozen'
    }
}

function Get-CddsiClaudeCodeSettingsFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    return New-CddsiOperationResult -Operation 'GetClaudeCodeSettingsFingerprint' -Status 'ACTION_REQUIRED' -Mode $Context.Mode -ErrorCode 'ZERO_READ_POLICY' -MessageSafe '零读取政策禁止定位、读取或哈希 settings.json。' -Data (Get-CddsiClaudeCodeSettingsIntegrityContract)
}

function Test-CddsiClaudeCodeSettingsUnchanged {
    [CmdletBinding()]
    param(
        [AllowNull()][string]$BeforeToken,
        [AllowNull()][string]$AfterToken
    )

    if ([string]::IsNullOrWhiteSpace($BeforeToken) -or [string]::IsNullOrWhiteSpace($AfterToken)) {
        return New-CddsiOperationResult -Operation 'VerifyClaudeCodeSettingsUnchanged' -Status 'ACTION_REQUIRED' -Mode 'TestSafe' -ErrorCode 'ZERO_READ_POLICY' -MessageSafe '未读取 Claude Code 配置；完整性由零访问证据证明。'
    }
    $status = if ($BeforeToken -ceq $AfterToken) { 'SUCCEEDED' } else { 'FAILED' }
    $errorCode = if ($status -ceq 'SUCCEEDED') { '' } else { 'TOKEN_MISMATCH' }
    return New-CddsiOperationResult -Operation 'VerifyClaudeCodeSettingsUnchanged' -Status $status -Mode 'TestSafe' -ErrorCode $errorCode -MessageSafe '仅比较调用方提供的不透明 synthetic token。' -Data ([pscustomobject]@{ Unchanged = ($BeforeToken -ceq $AfterToken) })
}

function Test-CddsiApiKeyLeak {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Content,
        [string]$Source = '<memory>'
    )

    $findings = @(Find-CddsiPotentialSecrets -Content $Content -Source $Source)
    return [pscustomobject][ordered]@{
        Passed   = ($findings.Count -eq 0)
        Findings = $findings
    }
}

function Test-CddsiExternalE2eEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedEnvironmentImageSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ExpectedScenarioId,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][datetimeoffset]$ExpectedNowUtc,
        [Parameter(Mandatory = $true)][int]$MaxEvidenceAgeSeconds,
        [Parameter(Mandatory = $true)][object[]]$ExpectedSurfaceEvidenceTokens,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens
    )

    try {
        if ($null -eq $Evidence) { return $false }
        if ($MaxEvidenceAgeSeconds -lt 1 -or $MaxEvidenceAgeSeconds -gt 86400) { return $false }
        if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @('SchemaVersion', 'ArtifactSha256', 'EnvironmentImageSha256', 'Profile', 'ScenarioId', 'RunId', 'ObservedAtUtc', 'Surfaces'))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion)) { return $false }
        if ($ExpectedArtifactSha256 -notmatch '^[a-f0-9]{64}$' -or $Evidence.ArtifactSha256 -isnot [string] -or $Evidence.ArtifactSha256 -cne $ExpectedArtifactSha256) { return $false }
        if ($ExpectedEnvironmentImageSha256 -notmatch '^[a-f0-9]{64}$' -or $Evidence.EnvironmentImageSha256 -isnot [string] -or $Evidence.EnvironmentImageSha256 -cne $ExpectedEnvironmentImageSha256) { return $false }
        if ($ExpectedProfile -cnotin @('VmAcceptance', 'UserLive') -or $Evidence.Profile -isnot [string] -or $Evidence.Profile -cne $ExpectedProfile) { return $false }
        if (-not (Test-CddsiSafeIdentifierValue -Value $ExpectedScenarioId -MaxLength 128) -or $Evidence.ScenarioId -isnot [string] -or $Evidence.ScenarioId -cne $ExpectedScenarioId) { return $false }

        $expectedGuid = [guid]::Empty
        $evidenceGuid = [guid]::Empty
        if (-not [guid]::TryParse($ExpectedRunId, [ref]$expectedGuid) -or $expectedGuid -eq [guid]::Empty -or $expectedGuid.ToString('D') -cne $ExpectedRunId) { return $false }
        if ($Evidence.RunId -isnot [string] -or -not [guid]::TryParse($Evidence.RunId, [ref]$evidenceGuid) -or $evidenceGuid -eq [guid]::Empty -or $evidenceGuid.ToString('D') -cne $Evidence.RunId -or $Evidence.RunId -cne $ExpectedRunId) { return $false }

        if ($ExpectedNowUtc.Offset -ne [timespan]::Zero) { return $false }
        if ($Evidence.ObservedAtUtc -isnot [string]) { return $false }
        $observedAtUtc = [datetimeoffset]::MinValue
        $timestampFormat = "yyyy-MM-dd'T'HH:mm:ss.fffffff'Z'"
        if (-not [datetimeoffset]::TryParseExact($Evidence.ObservedAtUtc, $timestampFormat, [Globalization.CultureInfo]::InvariantCulture, ([Globalization.DateTimeStyles]::AssumeUniversal -bor [Globalization.DateTimeStyles]::AdjustToUniversal), [ref]$observedAtUtc)) { return $false }
        if ($observedAtUtc.ToUniversalTime().ToString($timestampFormat, [Globalization.CultureInfo]::InvariantCulture) -cne $Evidence.ObservedAtUtc) { return $false }
        if ($observedAtUtc -gt $ExpectedNowUtc) { return $false }
        if (($ExpectedNowUtc - $observedAtUtc).TotalSeconds -gt $MaxEvidenceAgeSeconds) { return $false }

        $expectedSurfaces = @('Chat', 'Code', 'Cowork')
        $expectedTokens = @($ExpectedSurfaceEvidenceTokens)
        if ($expectedTokens.Count -ne $expectedSurfaces.Count) { return $false }
        $trustedTokenBySurface = @{}
        $trustedStatusBySurface = @{}
        $allTrustedTokens = @{}
        for ($index = 0; $index -lt $expectedSurfaces.Count; $index++) {
            $expectedToken = $expectedTokens[$index]
            if ($null -eq $expectedToken -or -not (Test-CddsiExactPropertySet -InputObject $expectedToken -Expected @('Surface', 'Status', 'EvidenceToken'))) { return $false }
            if ($expectedToken.Surface -isnot [string] -or $expectedToken.Surface -cne $expectedSurfaces[$index]) { return $false }
            if ($expectedToken.Status -isnot [string] -or $expectedToken.Status -cnotin @('PASS', 'FAIL', 'NOT_TESTED')) { return $false }
            if ($expectedToken.Status -ceq 'NOT_TESTED') {
                if ($null -ne $expectedToken.EvidenceToken) { return $false }
            }
            else {
                if ($expectedToken.EvidenceToken -isnot [string] -or $expectedToken.EvidenceToken -notmatch '^[a-f0-9]{64}$' -or $allTrustedTokens.ContainsKey($expectedToken.EvidenceToken)) { return $false }
                $allTrustedTokens[$expectedToken.EvidenceToken] = $true
            }
            $trustedTokenBySurface[$expectedToken.Surface] = $expectedToken.EvidenceToken
            $trustedStatusBySurface[$expectedToken.Surface] = $expectedToken.Status
        }

        $consumedTokens = @{}
        foreach ($consumedToken in @($PreviouslyConsumedEvidenceTokens)) {
            if ($consumedToken -isnot [string] -or $consumedToken -notmatch '^[a-f0-9]{64}$' -or $consumedTokens.ContainsKey($consumedToken)) { return $false }
            $consumedTokens[$consumedToken] = $true
        }

        $surfaces = @($Evidence.Surfaces)
        if ($surfaces.Count -ne $expectedSurfaces.Count) { return $false }
        $presentedTokens = @{}
        for ($index = 0; $index -lt $expectedSurfaces.Count; $index++) {
            $surface = $surfaces[$index]
            if (-not (Test-CddsiExactPropertySet -InputObject $surface -Expected @('Surface', 'Status', 'EvidenceToken'))) { return $false }
            if ($surface.Surface -isnot [string] -or $surface.Surface -cne $expectedSurfaces[$index]) { return $false }
            if ($surface.Status -isnot [string] -or $surface.Status -cnotin @('PASS', 'FAIL', 'NOT_TESTED')) { return $false }
            if ($surface.Status -cne $trustedStatusBySurface[$surface.Surface]) { return $false }
            if ($surface.Status -ceq 'NOT_TESTED') {
                if ($null -ne $surface.EvidenceToken) { return $false }
            }
            else {
                if ($surface.EvidenceToken -isnot [string] -or $surface.EvidenceToken -notmatch '^[a-f0-9]{64}$') { return $false }
                if ($surface.EvidenceToken -cne $trustedTokenBySurface[$surface.Surface]) { return $false }
                if ($presentedTokens.ContainsKey($surface.EvidenceToken) -or $consumedTokens.ContainsKey($surface.EvidenceToken)) { return $false }
                $presentedTokens[$surface.EvidenceToken] = $true
            }
        }

        $serialized = ConvertTo-CddsiJson -InputObject $Evidence
        return (@(Find-CddsiPotentialSecrets -Content $serialized -Source '<external-e2e-evidence>').Count -eq 0)
    }
    catch {
        return $false
    }
}

function Resolve-CddsiCompensationStatus {
    [CmdletBinding()]
    param(
        [AllowEmptyCollection()][object[]]$Resources = @()
    )

    $seenResources = @{}
    $reasonCodes = @()
    $seenReasons = @{}
    $changedCount = 0
    $failedCount = 0
    $hasPartial = $false
    $hasUnsupported = $false
    $hasFull = $false

    foreach ($resource in @($Resources)) {
        if ($null -eq $resource -or -not (Test-CddsiExactPropertySet -InputObject $resource -Expected @('ResourceId', 'Ownership', 'Mutation', 'Status', 'ReasonCode'))) {
            throw 'Compensation resource schema 不完整或包含未知字段。'
        }
        if (-not (Test-CddsiSafeIdentifierValue -Value $resource.ResourceId -MaxLength 128) -or $seenResources.ContainsKey([string]$resource.ResourceId)) {
            throw 'Compensation ResourceId 必须安全且唯一。'
        }
        $seenResources[[string]$resource.ResourceId] = $true
        if ($resource.Ownership -isnot [string] -or $resource.Ownership -cnotin @('PROJECT', 'SHARED', 'EXTERNAL')) { throw 'Compensation Ownership 不受支持。' }
        if ($resource.Mutation -isnot [string] -or $resource.Mutation -cnotin @('NONE', 'CREATED', 'UPDATED', 'REMOVED', 'UNKNOWN')) { throw 'Compensation Mutation 不受支持。' }
        if ($resource.Status -isnot [string] -or $resource.Status -cnotin @('NOT_REQUIRED', 'FULL', 'PARTIAL', 'UNSUPPORTED', 'FAILED')) { throw 'Compensation Status 不受支持。' }
        if (-not (Test-CddsiSafeIdentifierValue -Value $resource.ReasonCode -MaxLength 64)) { throw 'Compensation ReasonCode 不安全。' }
        if ($resource.Mutation -ceq 'NONE' -and $resource.Status -cne 'NOT_REQUIRED') { throw '无变更资源只能为 NOT_REQUIRED。' }
        if ($resource.Mutation -cne 'NONE' -and $resource.Status -ceq 'NOT_REQUIRED') { throw '发生变更的资源不能为 NOT_REQUIRED。' }
        if ($resource.Mutation -ceq 'UNKNOWN' -and $resource.Status -cne 'FAILED') { throw '未知修改必须为 FAILED。' }
        if ($resource.Ownership -ceq 'PROJECT' -and $resource.Mutation -cne 'NONE' -and $resource.Status -cnotin @('FULL', 'FAILED')) {
            throw '项目拥有资源只允许 FULL 或 FAILED 补偿。'
        }

        if ($resource.Mutation -cne 'NONE') { $changedCount++ }
        switch -CaseSensitive ($resource.Status) {
            'FAILED' { $failedCount++ }
            'PARTIAL' { $hasPartial = $true }
            'UNSUPPORTED' { $hasUnsupported = $true }
            'FULL' { $hasFull = $true }
        }
        if (-not $seenReasons.ContainsKey([string]$resource.ReasonCode)) {
            $seenReasons[[string]$resource.ReasonCode] = $true
            $reasonCodes += [string]$resource.ReasonCode
        }
    }

    $status = 'NOT_REQUIRED'
    if ($failedCount -gt 0) { $status = 'FAILED' }
    elseif ($hasPartial) { $status = 'PARTIAL' }
    elseif ($hasUnsupported) { $status = 'UNSUPPORTED' }
    elseif ($hasFull) { $status = 'FULL' }

    $result = [pscustomobject][ordered]@{
        SchemaVersion        = 1
        Status               = $status
        ChangedResourceCount = $changedCount
        FailedResourceCount  = $failedCount
        ReasonCodes          = @($reasonCodes)
        Resources            = @($Resources | ForEach-Object { $_ })
    }
    if (@(Find-CddsiPotentialSecrets -Content (ConvertTo-CddsiJson -InputObject $result) -Source '<compensation-evidence>').Count -gt 0) {
        throw 'Compensation evidence 包含疑似凭据。'
    }
    return $result
}

function Resolve-CddsiAcceptanceStatus {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$Capabilities,
        [Parameter(Mandatory = $true)][object[]]$UiEvidence,
        [Parameter(Mandatory = $true)]$Compensation,
        [switch]$Cancelled
    )

    $expectedSurfaces = @('Chat', 'Code', 'Cowork')
    if (@($Capabilities).Count -ne 3 -or @($UiEvidence).Count -ne 3) { throw 'Acceptance 必须精确包含 Chat、Code、Cowork。' }
    $readyCount = 0
    $hasBlocked = $false
    $hasPendingRestart = $false
    $hasUnsupported = $false
    $hasUnknown = $false
    $hasUiFailure = $false
    $uiPassCount = 0
    $hasUiNotTested = $false
    $externalUiCount = 0
    $seenUiTokens = @{}
    $reasonCodes = @()
    $seenReasons = @{}

    for ($index = 0; $index -lt $expectedSurfaces.Count; $index++) {
        $capability = $Capabilities[$index]
        $ui = $UiEvidence[$index]
        if ($null -eq $capability -or -not (Test-CddsiExactPropertySet -InputObject $capability -Expected @('Surface', 'Status', 'ReasonCodes'))) { throw 'Capability evidence schema 无效。' }
        if ($null -eq $ui -or -not (Test-CddsiExactPropertySet -InputObject $ui -Expected @('Surface', 'Status', 'Source', 'EvidenceToken'))) { throw 'UI evidence schema 无效。' }
        if ($capability.Surface -cne $expectedSurfaces[$index] -or $ui.Surface -cne $expectedSurfaces[$index]) { throw 'Surface 顺序或名称无效。' }
        if ($capability.Status -isnot [string] -or $capability.Status -cnotin @('READY', 'BLOCKED', 'PENDING_RESTART', 'UNSUPPORTED', 'UNKNOWN')) { throw 'Capability status 无效。' }
        if ($ui.Status -isnot [string] -or $ui.Status -cnotin @('PASS', 'FAIL', 'NOT_TESTED')) { throw 'UI status 无效。' }
        if ($ui.Source -isnot [string] -or $ui.Source -cnotin @('NONE', 'EXTERNAL')) { throw 'UI source 无效。' }
        if ($ui.Source -ceq 'NONE' -and ($ui.Status -cne 'NOT_TESTED' -or $null -ne $ui.EvidenceToken)) { throw 'NONE UI evidence 只能为 NOT_TESTED。' }
        if ($ui.Source -ceq 'EXTERNAL') {
            $externalUiCount++
            if ($ui.Status -ceq 'NOT_TESTED') {
                if ($null -ne $ui.EvidenceToken) { throw 'NOT_TESTED UI evidence 不得携带 token。' }
            }
            elseif ($ui.EvidenceToken -isnot [string] -or $ui.EvidenceToken -notmatch '^[a-f0-9]{64}$' -or $seenUiTokens.ContainsKey($ui.EvidenceToken)) { throw 'UI evidence token 必须是逐 surface 唯一的小写 SHA-256 token。' }
            else { $seenUiTokens[$ui.EvidenceToken] = $true }
        }
        if ($ui.Status -ceq 'PASS' -and $capability.Status -cne 'READY') { throw '非 READY capability 不能拥有 PASS UI evidence。' }

        if ($capability.ReasonCodes -isnot [array]) { throw 'Capability ReasonCodes 必须是显式数组。' }
        $entryReasons = @($capability.ReasonCodes)
        if ($capability.Status -ceq 'READY' -and $entryReasons.Count -ne 0) { throw 'READY capability 不得携带阻断 reason。' }
        if ($capability.Status -cne 'READY' -and $entryReasons.Count -eq 0) { throw '非 READY capability 必须至少携带一个阻断 reason。' }
        $entrySeen = @{}
        foreach ($reason in $entryReasons) {
            if (-not (Test-CddsiSafeIdentifierValue -Value $reason -MaxLength 64) -or $entrySeen.ContainsKey([string]$reason)) { throw 'Capability ReasonCodes 必须安全且唯一。' }
            if ($reason -cin @('ALL_SURFACES_READY', 'ALL_SURFACES_ACCEPTED', 'USER_CANCELLED', 'CHAT_UI_FAILED', 'CHAT_UI_NOT_TESTED', 'CODE_UI_FAILED', 'CODE_UI_NOT_TESTED', 'COWORK_UI_FAILED', 'COWORK_UI_NOT_TESTED', 'COMPENSATION_FAILED', 'COMPENSATION_PARTIAL', 'COMPENSATION_UNSUPPORTED')) { throw 'Capability ReasonCodes 不得伪造 reducer 保留 reason。' }
            $entrySeen[[string]$reason] = $true
            if (-not $seenReasons.ContainsKey([string]$reason)) {
                $seenReasons[[string]$reason] = $true
                $reasonCodes += [string]$reason
            }
        }

        switch -CaseSensitive ($capability.Status) {
            'READY' { $readyCount++ }
            'BLOCKED' { $hasBlocked = $true }
            'PENDING_RESTART' { $hasPendingRestart = $true }
            'UNSUPPORTED' { $hasUnsupported = $true }
            'UNKNOWN' { $hasUnknown = $true }
        }
        if ($ui.Status -ceq 'FAIL') {
            $hasUiFailure = $true
            $uiReason = ('{0}_UI_FAILED' -f $expectedSurfaces[$index].ToUpperInvariant())
            if (-not $seenReasons.ContainsKey($uiReason)) { $seenReasons[$uiReason] = $true; $reasonCodes += $uiReason }
        }
        elseif ($ui.Status -ceq 'PASS') {
            $uiPassCount++
        }
        else {
            $hasUiNotTested = $true
            $uiReason = ('{0}_UI_NOT_TESTED' -f $expectedSurfaces[$index].ToUpperInvariant())
            if (-not $seenReasons.ContainsKey($uiReason)) { $seenReasons[$uiReason] = $true; $reasonCodes += $uiReason }
        }
    }

    if ($externalUiCount -notin @(0, 3)) { throw 'UI evidence source 必须全部为 NONE 或全部为 EXTERNAL。' }

    if ($null -eq $Compensation -or -not (Test-CddsiExactPropertySet -InputObject $Compensation -Expected @('SchemaVersion', 'Status', 'ChangedResourceCount', 'FailedResourceCount', 'ReasonCodes', 'Resources'))) {
        throw 'Compensation reducer evidence schema 无效。'
    }
    $reducedCompensation = Resolve-CddsiCompensationStatus -Resources @($Compensation.Resources)
    foreach ($name in @('SchemaVersion', 'Status', 'ChangedResourceCount', 'FailedResourceCount')) {
        if ($Compensation.$name -cne $reducedCompensation.$name) { throw 'Compensation reducer evidence 不一致。' }
    }
    $expectedCompReasons = @($reducedCompensation.ReasonCodes)
    $actualCompReasons = @($Compensation.ReasonCodes)
    if ($expectedCompReasons.Count -ne $actualCompReasons.Count) { throw 'Compensation ReasonCodes 不一致。' }
    for ($index = 0; $index -lt $expectedCompReasons.Count; $index++) {
        if ($expectedCompReasons[$index] -cne $actualCompReasons[$index]) { throw 'Compensation ReasonCodes 不一致。' }
    }

    $status = 'ACTION_REQUIRED'
    if ($Compensation.Status -ceq 'FAILED' -or $hasUiFailure) { $status = 'FAILED' }
    elseif ($Compensation.Status -in @('PARTIAL', 'UNSUPPORTED')) { $status = 'PARTIAL' }
    elseif ($Cancelled) { $status = 'CANCELLED' }
    elseif ($hasPendingRestart) { $status = 'RESTART_REQUIRED' }
    elseif ($hasUnknown) { $status = 'ACTION_REQUIRED' }
    elseif ($hasBlocked -or $hasUnsupported) {
        $status = if ($readyCount -gt 0) { 'PARTIAL' } else { 'ACTION_REQUIRED' }
    }
    elseif ($readyCount -eq 3 -and $uiPassCount -eq 3) { $status = 'SUCCEEDED' }
    elseif ($readyCount -eq 3 -and $hasUiNotTested) {
        $status = if ($uiPassCount -gt 0) { 'PARTIAL' } else { 'ACTION_REQUIRED' }
    }

    if ($Cancelled -and -not $seenReasons.ContainsKey('USER_CANCELLED')) { $seenReasons['USER_CANCELLED'] = $true; $reasonCodes += 'USER_CANCELLED' }
    if ($readyCount -eq 3 -and -not $seenReasons.ContainsKey('ALL_SURFACES_READY')) { $seenReasons['ALL_SURFACES_READY'] = $true; $reasonCodes += 'ALL_SURFACES_READY' }
    if ($status -ceq 'SUCCEEDED' -and -not $seenReasons.ContainsKey('ALL_SURFACES_ACCEPTED')) { $reasonCodes += 'ALL_SURFACES_ACCEPTED' }
    if ($Compensation.Status -in @('FAILED', 'PARTIAL', 'UNSUPPORTED')) {
        $compReason = ('COMPENSATION_{0}' -f $Compensation.Status)
        if (-not $seenReasons.ContainsKey($compReason)) { $reasonCodes += $compReason }
    }

    $errorCode = switch -CaseSensitive ($status) {
        'SUCCEEDED' { '' }
        'PARTIAL' { 'ACCEPTANCE_PARTIAL' }
        'RESTART_REQUIRED' { 'RESTART_REQUIRED' }
        'ACTION_REQUIRED' { 'ACTION_REQUIRED' }
        'CANCELLED' { 'USER_CANCELLED' }
        'FAILED' { 'ACCEPTANCE_FAILED' }
    }
    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        Status        = $status
        Success       = ($status -ceq 'SUCCEEDED')
        ErrorCode     = $errorCode
        ReasonCodes   = @($reasonCodes)
    }
}

function New-CddsiAcceptanceEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][object[]]$ExpectedCapabilities,
        [Parameter(Mandatory = $true)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedEnvironmentImageSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ExpectedScenarioId,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][datetimeoffset]$ExpectedNowUtc,
        [Parameter(Mandatory = $true)][ValidateRange(1, 86400)][int]$MaxEvidenceAgeSeconds,
        [Parameter(Mandatory = $true)][object[]]$ExpectedSurfaceEvidenceTokens,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens,
        [AllowNull()]$ExternalE2eEvidence,
        [AllowEmptyCollection()][object[]]$CompensationResources = @(),
        [switch]$Cancelled
    )

    if ($ExpectedArtifactSha256 -notmatch '^[a-f0-9]{64}$') { throw 'ExpectedArtifactSha256 必须是小写 SHA-256。' }
    if ($ExpectedEnvironmentImageSha256 -notmatch '^[a-f0-9]{64}$') { throw 'ExpectedEnvironmentImageSha256 必须是小写 SHA-256。' }
    if ($ExpectedProfile -cnotin @('VmAcceptance', 'UserLive')) { throw 'ExpectedProfile 不受支持。' }
    if (-not (Test-CddsiSafeIdentifierValue -Value $ExpectedScenarioId -MaxLength 128)) { throw 'ExpectedScenarioId 无效。' }
    $parsedRunId = [guid]::Empty
    if (-not [guid]::TryParse($ExpectedRunId, [ref]$parsedRunId) -or $parsedRunId -eq [guid]::Empty -or $parsedRunId.ToString('D') -cne $ExpectedRunId) { throw 'ExpectedRunId 必须是规范化小写非空 GUID。' }
    if ($ExpectedNowUtc.Offset -ne [timespan]::Zero) { throw 'ExpectedNowUtc 必须是 UTC。' }

    $expectedSurfaces = @('Chat', 'Code', 'Cowork')
    $expectedTokens = @($ExpectedSurfaceEvidenceTokens)
    if ($expectedTokens.Count -ne $expectedSurfaces.Count) { throw 'ExpectedSurfaceEvidenceTokens 必须精确包含三个 surface。' }
    $seenExpectedTokens = @{}
    for ($index = 0; $index -lt $expectedSurfaces.Count; $index++) {
        $entry = $expectedTokens[$index]
        if ($null -eq $entry -or -not (Test-CddsiExactPropertySet -InputObject $entry -Expected @('Surface', 'Status', 'EvidenceToken')) -or $entry.Surface -cne $expectedSurfaces[$index] -or $entry.Status -isnot [string] -or $entry.Status -cnotin @('PASS', 'FAIL', 'NOT_TESTED')) {
            throw 'ExpectedSurfaceEvidenceTokens 必须按固定顺序提供逐 surface 唯一的小写 SHA-256 token。'
        }
        if ($entry.Status -ceq 'NOT_TESTED') {
            if ($null -ne $entry.EvidenceToken) { throw 'NOT_TESTED trusted surface 不得携带 evidence token。' }
        }
        elseif ($entry.EvidenceToken -isnot [string] -or $entry.EvidenceToken -notmatch '^[a-f0-9]{64}$' -or $seenExpectedTokens.ContainsKey($entry.EvidenceToken)) {
            throw 'ExpectedSurfaceEvidenceTokens 必须按固定顺序提供逐 surface 唯一的小写 SHA-256 token。'
        }
        else { $seenExpectedTokens[$entry.EvidenceToken] = $true }
    }
    $seenConsumedTokens = @{}
    foreach ($consumedToken in @($PreviouslyConsumedEvidenceTokens)) {
        if ($consumedToken -isnot [string] -or $consumedToken -notmatch '^[a-f0-9]{64}$' -or $seenConsumedTokens.ContainsKey($consumedToken)) { throw 'PreviouslyConsumedEvidenceTokens 必须唯一且格式有效。' }
        $seenConsumedTokens[$consumedToken] = $true
    }

    $uiEvidence = @()
    $externalObservedAtUtc = $null
    if ($null -eq $ExternalE2eEvidence) {
        foreach ($surface in $expectedSurfaces) {
            $uiEvidence += [pscustomobject][ordered]@{ Surface = $surface; Status = 'NOT_TESTED'; Source = 'NONE'; EvidenceToken = $null }
        }
    }
    else {
        if (-not (Test-CddsiExternalE2eEvidence -Evidence $ExternalE2eEvidence -ExpectedArtifactSha256 $ExpectedArtifactSha256 -ExpectedEnvironmentImageSha256 $ExpectedEnvironmentImageSha256 -ExpectedProfile $ExpectedProfile -ExpectedScenarioId $ExpectedScenarioId -ExpectedRunId $ExpectedRunId -ExpectedNowUtc $ExpectedNowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -ExpectedSurfaceEvidenceTokens $ExpectedSurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens)) {
            throw 'External E2E evidence 未通过可信 artifact/environment/profile/scenario/run/time/token 绑定。'
        }
        $externalObservedAtUtc = [string]$ExternalE2eEvidence.ObservedAtUtc
        foreach ($surface in @($ExternalE2eEvidence.Surfaces)) {
            $uiEvidence += [pscustomobject][ordered]@{ Surface = $surface.Surface; Status = $surface.Status; Source = 'EXTERNAL'; EvidenceToken = $surface.EvidenceToken }
        }
    }

    $compensation = Resolve-CddsiCompensationStatus -Resources $CompensationResources
    $run = Resolve-CddsiAcceptanceStatus -Capabilities $ExpectedCapabilities -UiEvidence $uiEvidence -Compensation $compensation -Cancelled:$Cancelled
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion          = 1
        ArtifactSha256         = $ExpectedArtifactSha256
        EnvironmentImageSha256 = $ExpectedEnvironmentImageSha256
        Profile                = $ExpectedProfile
        ScenarioId             = $ExpectedScenarioId
        RunId                  = $ExpectedRunId
        ExternalObservedAtUtc  = $externalObservedAtUtc
        RequestedSurfaces      = @('Chat', 'Code', 'Cowork')
        Cancelled              = $Cancelled.IsPresent
        Capabilities           = @($ExpectedCapabilities | ForEach-Object { $_ })
        UiEvidence             = @($uiEvidence)
        Compensation           = $compensation
        Run                    = $run
    }
    if (-not (Test-CddsiAcceptanceEvidence -Evidence $evidence -ExpectedCapabilities $ExpectedCapabilities -ExpectedArtifactSha256 $ExpectedArtifactSha256 -ExpectedEnvironmentImageSha256 $ExpectedEnvironmentImageSha256 -ExpectedProfile $ExpectedProfile -ExpectedScenarioId $ExpectedScenarioId -ExpectedRunId $ExpectedRunId -ExpectedNowUtc $ExpectedNowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -ExpectedSurfaceEvidenceTokens $ExpectedSurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens)) { throw '生成的 acceptance evidence 未通过可信输入复核。' }
    return $evidence
}

function Test-CddsiAcceptanceEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][object[]]$ExpectedCapabilities,
        [Parameter(Mandatory = $true)][string]$ExpectedArtifactSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedEnvironmentImageSha256,
        [Parameter(Mandatory = $true)][string]$ExpectedProfile,
        [Parameter(Mandatory = $true)][string]$ExpectedScenarioId,
        [Parameter(Mandatory = $true)][string]$ExpectedRunId,
        [Parameter(Mandatory = $true)][datetimeoffset]$ExpectedNowUtc,
        [Parameter(Mandatory = $true)][int]$MaxEvidenceAgeSeconds,
        [Parameter(Mandatory = $true)][object[]]$ExpectedSurfaceEvidenceTokens,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens
    )

    try {
        if ($null -eq $Evidence -or -not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @('SchemaVersion', 'ArtifactSha256', 'EnvironmentImageSha256', 'Profile', 'ScenarioId', 'RunId', 'ExternalObservedAtUtc', 'RequestedSurfaces', 'Cancelled', 'Capabilities', 'UiEvidence', 'Compensation', 'Run'))) { return $false }
        if ($MaxEvidenceAgeSeconds -lt 1 -or $MaxEvidenceAgeSeconds -gt 86400) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion)) { return $false }
        if ($ExpectedArtifactSha256 -notmatch '^[a-f0-9]{64}$' -or $Evidence.ArtifactSha256 -isnot [string] -or $Evidence.ArtifactSha256 -cne $ExpectedArtifactSha256) { return $false }
        if ($ExpectedEnvironmentImageSha256 -notmatch '^[a-f0-9]{64}$' -or $Evidence.EnvironmentImageSha256 -isnot [string] -or $Evidence.EnvironmentImageSha256 -cne $ExpectedEnvironmentImageSha256) { return $false }
        if ($ExpectedProfile -cnotin @('VmAcceptance', 'UserLive') -or $Evidence.Profile -isnot [string] -or $Evidence.Profile -cne $ExpectedProfile) { return $false }
        if (-not (Test-CddsiSafeIdentifierValue -Value $ExpectedScenarioId -MaxLength 128) -or $Evidence.ScenarioId -isnot [string] -or $Evidence.ScenarioId -cne $ExpectedScenarioId) { return $false }
        $expectedRunGuid = [guid]::Empty
        $evidenceRunGuid = [guid]::Empty
        if (-not [guid]::TryParse($ExpectedRunId, [ref]$expectedRunGuid) -or $expectedRunGuid -eq [guid]::Empty -or $expectedRunGuid.ToString('D') -cne $ExpectedRunId) { return $false }
        if ($Evidence.RunId -isnot [string] -or -not [guid]::TryParse($Evidence.RunId, [ref]$evidenceRunGuid) -or $evidenceRunGuid -eq [guid]::Empty -or $evidenceRunGuid.ToString('D') -cne $Evidence.RunId -or $Evidence.RunId -cne $ExpectedRunId) { return $false }
        if ($ExpectedNowUtc.Offset -ne [timespan]::Zero) { return $false }
        if ($Evidence.Cancelled -isnot [bool]) { return $false }
        $requested = @($Evidence.RequestedSurfaces)
        if ($requested.Count -ne 3 -or ($requested -join '|') -cne 'Chat|Code|Cowork') { return $false }
        if ($null -eq $Evidence.Run -or -not (Test-CddsiExactPropertySet -InputObject $Evidence.Run -Expected @('SchemaVersion', 'Status', 'Success', 'ErrorCode', 'ReasonCodes'))) { return $false }

        $expectedCapabilityEntries = @($ExpectedCapabilities)
        $actualCapabilityEntries = @($Evidence.Capabilities)
        if ($expectedCapabilityEntries.Count -ne 3 -or $actualCapabilityEntries.Count -ne 3) { return $false }
        for ($index = 0; $index -lt 3; $index++) {
            $expectedCapability = $expectedCapabilityEntries[$index]
            $actualCapability = $actualCapabilityEntries[$index]
            if ($null -eq $expectedCapability -or $null -eq $actualCapability) { return $false }
            if (-not (Test-CddsiExactPropertySet -InputObject $expectedCapability -Expected @('Surface', 'Status', 'ReasonCodes'))) { return $false }
            if (-not (Test-CddsiExactPropertySet -InputObject $actualCapability -Expected @('Surface', 'Status', 'ReasonCodes'))) { return $false }
            if ($expectedCapability.ReasonCodes -isnot [array] -or $actualCapability.ReasonCodes -isnot [array]) { return $false }
            if ($actualCapability.Surface -cne $expectedCapability.Surface -or $actualCapability.Status -cne $expectedCapability.Status) { return $false }
            $expectedCapabilityReasons = @($expectedCapability.ReasonCodes)
            $actualCapabilityReasons = @($actualCapability.ReasonCodes)
            if ($expectedCapabilityReasons.Count -ne $actualCapabilityReasons.Count) { return $false }
            for ($reasonIndex = 0; $reasonIndex -lt $expectedCapabilityReasons.Count; $reasonIndex++) {
                if ($actualCapabilityReasons[$reasonIndex] -cne $expectedCapabilityReasons[$reasonIndex]) { return $false }
            }
        }

        $expectedSurfaces = @('Chat', 'Code', 'Cowork')
        $expectedTokens = @($ExpectedSurfaceEvidenceTokens)
        if ($expectedTokens.Count -ne 3) { return $false }
        $seenExpectedTokens = @{}
        for ($index = 0; $index -lt 3; $index++) {
            $entry = $expectedTokens[$index]
            if ($null -eq $entry -or -not (Test-CddsiExactPropertySet -InputObject $entry -Expected @('Surface', 'Status', 'EvidenceToken')) -or $entry.Surface -cne $expectedSurfaces[$index] -or $entry.Status -isnot [string] -or $entry.Status -cnotin @('PASS', 'FAIL', 'NOT_TESTED')) { return $false }
            if ($entry.Status -ceq 'NOT_TESTED') {
                if ($null -ne $entry.EvidenceToken) { return $false }
            }
            else {
                if ($entry.EvidenceToken -isnot [string] -or $entry.EvidenceToken -notmatch '^[a-f0-9]{64}$' -or $seenExpectedTokens.ContainsKey($entry.EvidenceToken)) { return $false }
                $seenExpectedTokens[$entry.EvidenceToken] = $true
            }
        }
        $seenConsumedTokens = @{}
        foreach ($consumedToken in @($PreviouslyConsumedEvidenceTokens)) {
            if ($consumedToken -isnot [string] -or $consumedToken -notmatch '^[a-f0-9]{64}$' -or $seenConsumedTokens.ContainsKey($consumedToken)) { return $false }
            $seenConsumedTokens[$consumedToken] = $true
        }

        $uiEntries = @($Evidence.UiEvidence)
        if ($uiEntries.Count -ne 3) { return $false }
        $sourceValues = @($uiEntries | ForEach-Object { $_.Source } | Select-Object -Unique)
        if ($sourceValues.Count -ne 1 -or $sourceValues[0] -cnotin @('NONE', 'EXTERNAL')) { return $false }
        if ($sourceValues[0] -ceq 'NONE') {
            if ($null -ne $Evidence.ExternalObservedAtUtc) { return $false }
        }
        else {
            if ($Evidence.ExternalObservedAtUtc -isnot [string]) { return $false }
            $externalSurfaces = @()
            foreach ($uiEntry in $uiEntries) {
                $externalSurfaces += [pscustomobject][ordered]@{ Surface = $uiEntry.Surface; Status = $uiEntry.Status; EvidenceToken = $uiEntry.EvidenceToken }
            }
            $externalEvidence = [pscustomobject][ordered]@{
                SchemaVersion          = 1
                ArtifactSha256         = $Evidence.ArtifactSha256
                EnvironmentImageSha256 = $Evidence.EnvironmentImageSha256
                Profile                = $Evidence.Profile
                ScenarioId             = $Evidence.ScenarioId
                RunId                  = $Evidence.RunId
                ObservedAtUtc           = $Evidence.ExternalObservedAtUtc
                Surfaces                = @($externalSurfaces)
            }
            if (-not (Test-CddsiExternalE2eEvidence -Evidence $externalEvidence -ExpectedArtifactSha256 $ExpectedArtifactSha256 -ExpectedEnvironmentImageSha256 $ExpectedEnvironmentImageSha256 -ExpectedProfile $ExpectedProfile -ExpectedScenarioId $ExpectedScenarioId -ExpectedRunId $ExpectedRunId -ExpectedNowUtc $ExpectedNowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -ExpectedSurfaceEvidenceTokens $ExpectedSurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens)) { return $false }
        }

        $resolved = Resolve-CddsiAcceptanceStatus -Capabilities @($Evidence.Capabilities) -UiEvidence @($Evidence.UiEvidence) -Compensation $Evidence.Compensation -Cancelled:([bool]$Evidence.Cancelled)
        foreach ($name in @('SchemaVersion', 'Status', 'Success', 'ErrorCode')) {
            if ($Evidence.Run.$name -cne $resolved.$name) { return $false }
        }
        $expectedReasons = @($resolved.ReasonCodes)
        $actualReasons = @($Evidence.Run.ReasonCodes)
        if ($expectedReasons.Count -ne $actualReasons.Count) { return $false }
        for ($index = 0; $index -lt $expectedReasons.Count; $index++) {
            if ($expectedReasons[$index] -cne $actualReasons[$index]) { return $false }
        }
        return (@(Find-CddsiPotentialSecrets -Content (ConvertTo-CddsiJson -InputObject $Evidence) -Source '<acceptance-evidence>').Count -eq 0)
    }
    catch {
        return $false
    }
}

function Test-CddsiChatAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('READY', 'BLOCKED', 'PENDING_RESTART', 'UNSUPPORTED', 'UNKNOWN')][string]$CapabilityStatus = 'UNKNOWN',
        [ValidateSet('PASS', 'FAIL', 'NOT_TESTED')][string]$UiStatus = 'NOT_TESTED'
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if ($UiStatus -ceq 'PASS' -and $CapabilityStatus -cne 'READY') { throw 'Chat UI PASS 要求 capability READY。' }
    $status = if ($UiStatus -ceq 'FAIL') { 'FAILED' } elseif ($CapabilityStatus -ceq 'PENDING_RESTART') { 'RESTART_REQUIRED' } elseif ($CapabilityStatus -ceq 'READY' -and $UiStatus -ceq 'PASS') { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }
    $errorCode = if ($status -ceq 'SUCCEEDED') { '' } elseif ($status -ceq 'FAILED') { 'CHAT_UI_FAILED' } elseif ($status -ceq 'RESTART_REQUIRED') { 'CHAT_PENDING_RESTART' } elseif ($CapabilityStatus -ceq 'READY') { 'CHAT_UI_NOT_TESTED' } else { 'CHAT_NOT_READY' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; Surface = 'Chat'; CapabilityStatus = $CapabilityStatus; UiStatus = $UiStatus; RealUiExecuted = $false; ApiRequestSent = $false; ProcessStarted = $false }
    return New-CddsiOperationResult -Operation 'AcceptChat' -Status $status -Mode $Context.Mode -ErrorCode $errorCode -MessageSafe 'Chat 仅消费 synthetic readiness/UI evidence；未启动 Desktop 或发送请求。' -Data $data
}

function Test-CddsiCodeAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('READY', 'BLOCKED', 'PENDING_RESTART', 'UNSUPPORTED', 'UNKNOWN')][string]$CapabilityStatus = 'UNKNOWN',
        [ValidateSet('PASS', 'FAIL', 'NOT_TESTED')][string]$UiStatus = 'NOT_TESTED'
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if ($UiStatus -ceq 'PASS' -and $CapabilityStatus -cne 'READY') { throw 'Code UI PASS 要求 capability READY。' }
    $status = if ($UiStatus -ceq 'FAIL') { 'FAILED' } elseif ($CapabilityStatus -ceq 'PENDING_RESTART') { 'RESTART_REQUIRED' } elseif ($CapabilityStatus -ceq 'READY' -and $UiStatus -ceq 'PASS') { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }
    $errorCode = if ($status -ceq 'SUCCEEDED') { '' } elseif ($status -ceq 'FAILED') { 'CODE_UI_FAILED' } elseif ($status -ceq 'RESTART_REQUIRED') { 'CODE_PENDING_RESTART' } elseif ($CapabilityStatus -ceq 'READY') { 'CODE_UI_NOT_TESTED' } else { 'CODE_NOT_READY' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; Surface = 'Code'; CapabilityStatus = $CapabilityStatus; UiStatus = $UiStatus; RealUiExecuted = $false; ApiRequestSent = $false; ProcessStarted = $false }
    return New-CddsiOperationResult -Operation 'AcceptCode' -Status $status -Mode $Context.Mode -ErrorCode $errorCode -MessageSafe 'Code 仅消费 synthetic readiness/UI evidence；未启动 Desktop 或执行 Code 工作流。' -Data $data
}

function Test-CddsiCoworkAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('READY', 'BLOCKED', 'PENDING_RESTART', 'UNSUPPORTED', 'UNKNOWN')][string]$CapabilityStatus = 'UNKNOWN',
        [ValidateSet('PASS', 'FAIL', 'NOT_TESTED')][string]$UiStatus = 'NOT_TESTED'
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context | Out-Null
    if ($UiStatus -ceq 'PASS' -and $CapabilityStatus -cne 'READY') { throw 'Cowork UI PASS 要求 capability READY。' }
    $status = if ($UiStatus -ceq 'FAIL') { 'FAILED' } elseif ($CapabilityStatus -ceq 'PENDING_RESTART') { 'RESTART_REQUIRED' } elseif ($CapabilityStatus -ceq 'READY' -and $UiStatus -ceq 'PASS') { 'SUCCEEDED' } else { 'ACTION_REQUIRED' }
    $errorCode = if ($status -ceq 'SUCCEEDED') { '' } elseif ($status -ceq 'FAILED') { 'COWORK_UI_FAILED' } elseif ($status -ceq 'RESTART_REQUIRED') { 'COWORK_PENDING_RESTART' } elseif ($CapabilityStatus -ceq 'READY') { 'COWORK_UI_NOT_TESTED' } else { 'COWORK_NOT_READY' }
    $data = [pscustomobject][ordered]@{ SchemaVersion = 1; Surface = 'Cowork'; CapabilityStatus = $CapabilityStatus; UiStatus = $UiStatus; RealUiExecuted = $false; ApiRequestSent = $false; ProcessStarted = $false }
    return New-CddsiOperationResult -Operation 'AcceptCowork' -Status $status -Mode $Context.Mode -ErrorCode $errorCode -MessageSafe 'Cowork 仅消费 synthetic readiness/UI evidence；未启动 Desktop 或执行 Cowork 工作流。' -Data $data
}

function Get-CddsiRepairPlan {
    [CmdletBinding()]
    param()

    return @(
        [pscustomobject]@{ Id = 'repair_msix'; Action = '重新检测并验签 Claude Desktop MSIX'; SyntheticImplemented = $true; LiveImplemented = $false },
        [pscustomobject]@{ Id = 'repair_git'; Action = '重新检测 Git for Windows'; SyntheticImplemented = $true; LiveImplemented = $false },
        [pscustomobject]@{ Id = 'repair_cowork'; Action = '重新评估 Cowork 前置条件'; SyntheticImplemented = $true; LiveImplemented = $false },
        [pscustomobject]@{ Id = 'repair_config'; Action = '按资源所有权生成恢复/补偿计划'; SyntheticImplemented = $true; LiveImplemented = $false }
    )
}

function Invoke-CddsiDesktopRepair {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges,
        [AllowEmptyCollection()][object[]]$CompensationResources = @()
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'DesktopRepair' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    $data = [pscustomobject][ordered]@{ Plan = @(Get-CddsiRepairPlan); Compensation = Resolve-CddsiCompensationStatus -Resources $CompensationResources; RealMutationExecuted = $false }
    return New-CddsiOperationResult -Operation 'DesktopRepair' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'SYNTHETIC_PLAN_ONLY' -MessageSafe '修复只生成 synthetic 资源级补偿结果；未读取或修改本机。' -Data $data
}

function Invoke-CddsiDesktopAcceptance {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges,
        [AllowNull()]$AcceptanceEvidence,
        [AllowNull()][object[]]$ExpectedCapabilities,
        [string]$ExpectedArtifactSha256,
        [string]$ExpectedEnvironmentImageSha256,
        [string]$ExpectedProfile,
        [string]$ExpectedScenarioId,
        [string]$ExpectedRunId,
        [datetimeoffset]$ExpectedNowUtc,
        [int]$MaxEvidenceAgeSeconds,
        [AllowNull()][object[]]$ExpectedSurfaceEvidenceTokens,
        [AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -eq 'Live') { Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'DesktopAcceptance' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges }
    if ($null -eq $AcceptanceEvidence) {
        return New-CddsiOperationResult -Operation 'DesktopAcceptance' -Status 'ACTION_REQUIRED' -Mode $Mode -ErrorCode 'EVIDENCE_REQUIRED' -MessageSafe '未提供 synthetic acceptance evidence；不会访问 Desktop、API、进程或 UI。' -Data (Get-CddsiAcceptancePlan)
    }
    foreach ($requiredExpectedParameter in @('ExpectedCapabilities', 'ExpectedArtifactSha256', 'ExpectedEnvironmentImageSha256', 'ExpectedProfile', 'ExpectedScenarioId', 'ExpectedRunId', 'ExpectedNowUtc', 'MaxEvidenceAgeSeconds', 'ExpectedSurfaceEvidenceTokens', 'PreviouslyConsumedEvidenceTokens')) {
        if (-not $PSBoundParameters.ContainsKey($requiredExpectedParameter)) { throw ('AcceptanceEvidence 要求显式可信参数 {0}。' -f $requiredExpectedParameter) }
    }
    if ($ExpectedRunId -cne [string]$Context.RunId) { throw 'ExpectedRunId 与 ExecutionContext.RunId 不一致。' }
    if (-not (Test-CddsiAcceptanceEvidence -Evidence $AcceptanceEvidence -ExpectedCapabilities $ExpectedCapabilities -ExpectedArtifactSha256 $ExpectedArtifactSha256 -ExpectedEnvironmentImageSha256 $ExpectedEnvironmentImageSha256 -ExpectedProfile $ExpectedProfile -ExpectedScenarioId $ExpectedScenarioId -ExpectedRunId $ExpectedRunId -ExpectedNowUtc $ExpectedNowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -ExpectedSurfaceEvidenceTokens $ExpectedSurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens)) { throw 'AcceptanceEvidence 未通过可信绑定、时效、重放或状态归约验证。' }
    return New-CddsiOperationResult -Operation 'DesktopAcceptance' -Status $AcceptanceEvidence.Run.Status -Mode $Mode -ErrorCode $AcceptanceEvidence.Run.ErrorCode -MessageSafe '已归约 synthetic acceptance evidence；真实 UI、API 和进程均未执行。' -Data $AcceptanceEvidence
}

function New-CddsiAcceptanceReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Results,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$PathTokenValues,
        [AllowNull()][object[]]$ExpectedCapabilities,
        [string]$ExpectedArtifactSha256,
        [string]$ExpectedEnvironmentImageSha256,
        [string]$ExpectedProfile,
        [string]$ExpectedScenarioId,
        [string]$ExpectedRunId,
        [datetimeoffset]$ExpectedNowUtc,
        [int]$MaxEvidenceAgeSeconds,
        [AllowNull()][object[]]$ExpectedSurfaceEvidenceTokens,
        [AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens
    )

    $looksLikeAcceptanceEvidence = $false
    if ($null -ne $Results) {
        $resultNames = @($Results.PSObject.Properties.Name)
        $looksLikeAcceptanceEvidence = ($resultNames -ccontains 'RequestedSurfaces' -or $resultNames -ccontains 'Capabilities' -or $resultNames -ccontains 'UiEvidence')
    }
    if ($looksLikeAcceptanceEvidence) {
        foreach ($requiredExpectedParameter in @('ExpectedCapabilities', 'ExpectedArtifactSha256', 'ExpectedEnvironmentImageSha256', 'ExpectedProfile', 'ExpectedScenarioId', 'ExpectedRunId', 'ExpectedNowUtc', 'MaxEvidenceAgeSeconds', 'ExpectedSurfaceEvidenceTokens', 'PreviouslyConsumedEvidenceTokens')) {
            if (-not $PSBoundParameters.ContainsKey($requiredExpectedParameter)) { throw ('验收报告要求显式可信参数 {0}。' -f $requiredExpectedParameter) }
        }
        if (-not (Test-CddsiAcceptanceEvidence -Evidence $Results -ExpectedCapabilities $ExpectedCapabilities -ExpectedArtifactSha256 $ExpectedArtifactSha256 -ExpectedEnvironmentImageSha256 $ExpectedEnvironmentImageSha256 -ExpectedProfile $ExpectedProfile -ExpectedScenarioId $ExpectedScenarioId -ExpectedRunId $ExpectedRunId -ExpectedNowUtc $ExpectedNowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -ExpectedSurfaceEvidenceTokens $ExpectedSurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens)) {
            throw '拒绝报告未通过可信绑定、时效、重放或状态归约验证的 acceptance evidence。'
        }
    }

    $safe = Protect-CddsiReportText -Text (ConvertTo-CddsiJson -InputObject $Results) -PathTokenValues $PathTokenValues
    if (@(Find-CddsiPotentialSecrets -Content $safe -Source '<acceptance-report>').Count -gt 0) {
        throw '验收报告在脱敏后仍包含疑似凭据，已拒绝生成。'
    }
    $runtimeStatus = 'UNKNOWN'
    $success = $false
    if ($looksLikeAcceptanceEvidence) {
        $runtimeStatus = [string]$Results.Run.Status
        $success = [bool]$Results.Run.Success
    }
    elseif ($null -ne $Results.PSObject.Properties['Status'] -and $Results.Status -is [string]) {
        $runtimeStatus = [string]$Results.Status
    }
    return [pscustomobject][ordered]@{
        schemaVersion     = 1
        language          = 'zh-CN'
        redacted          = $true
        runtimeStatus     = $runtimeStatus
        success           = $success
        requestedSurfaces = @('Chat', 'Code', 'Cowork')
        content           = "Claude Desktop 验收报告（已脱敏）`n$safe"
        persisted         = $false
    }
}
