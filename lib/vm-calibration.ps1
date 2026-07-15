# vm-calibration.ps1 - Pure P10A disposable-VM calibration evidence contracts.
# This module records narrow calibration observations only. It never performs
# installation, system inspection, API calls or comprehensive P11 acceptance.
# All *BindingToken values below are SHA-256 integrity identifiers only. They do
# not authorize a transition; cross-process commit authority is established
# only by a verified RSA-SHA256 store signature over the exact receipt payload.

$script:CddsiVmCalibrationNotObserved = 'NOT_OBSERVED'
$script:CddsiVmCalibrationOperations = @(
    'InspectEnvironment',
    'AcquireCalibrationArtifacts',
    'VerifyCalibrationArtifacts',
    'CalibrateMsixScope',
    'CalibrateCredentialHelper',
    'CalibrateGit',
    'WriteCalibrationEvidence',
    'CleanupCalibrationResources'
)

function ConvertTo-CddsiVmCalibrationCanonicalValue {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return $null }
    if ($Value -is [string] -or $Value -is [char] -or $Value -is [bool] -or $Value -is [ValueType]) { return $Value }
    if ($Value -is [System.Collections.IDictionary]) {
        $map = [ordered]@{}
        foreach ($key in @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)) {
            $map[$key] = ConvertTo-CddsiVmCalibrationCanonicalValue -Value $Value[$key]
        }
        return [pscustomobject]$map
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $items = @()
        foreach ($item in $Value) { $items += ,(ConvertTo-CddsiVmCalibrationCanonicalValue -Value $item) }
        Write-Output -NoEnumerate $items
        return
    }
    $result = [ordered]@{}
    foreach ($property in @($Value.PSObject.Properties | Sort-Object -Property Name)) {
        $result[$property.Name] = ConvertTo-CddsiVmCalibrationCanonicalValue -Value $property.Value
    }
    return [pscustomobject]$result
}

function ConvertTo-CddsiVmCalibrationCanonicalJsonString {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Value)

    $builder = New-Object System.Text.StringBuilder
    [void]$builder.Append('"')
    foreach ($character in $Value.ToCharArray()) {
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
            continue
        }
        if ($code -lt 32) {
            [void]$builder.Append(('\u{0:x4}' -f $code))
        }
        else {
            [void]$builder.Append($character)
        }
    }
    [void]$builder.Append('"')
    return $builder.ToString()
}

function ConvertTo-CddsiVmCalibrationCanonicalJson {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    if ($null -eq $Value) { return 'null' }
    if ($Value -is [string]) { return ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value $Value }
    if ($Value -is [char]) { return ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value ([string]$Value) }
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
        if ([double]::IsNaN($Value) -or [double]::IsInfinity($Value)) { throw 'Canonical calibration JSON rejects non-finite numbers.' }
        return $Value.ToString('R', $invariant)
    }
    if ($Value -is [single]) {
        if ([single]::IsNaN($Value) -or [single]::IsInfinity($Value)) { throw 'Canonical calibration JSON rejects non-finite numbers.' }
        return $Value.ToString('R', $invariant)
    }
    if ($Value -is [guid]) {
        return ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value $Value.ToString('D').ToLowerInvariant()
    }
    if ($Value -is [DateTime]) {
        if ($Value.Kind -ne [DateTimeKind]::Utc) { throw 'Canonical calibration JSON requires UTC DateTime values.' }
        return ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', $invariant)
    }
    if ($Value -is [DateTimeOffset]) {
        if ($Value.Offset -ne [TimeSpan]::Zero) { throw 'Canonical calibration JSON requires UTC DateTimeOffset values.' }
        return ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value $Value.ToString('yyyy-MM-ddTHH:mm:ss.fffffffZ', $invariant)
    }

    if ($Value -is [System.Collections.IDictionary]) {
        $valueByKey = @{}
        $keys = New-Object System.Collections.Generic.List[string]
        foreach ($rawKey in $Value.Keys) {
            if ($rawKey -isnot [string] -or $valueByKey.ContainsKey($rawKey)) { throw 'Canonical calibration JSON requires unique string dictionary keys.' }
            $keys.Add($rawKey)
            $valueByKey[$rawKey] = $Value[$rawKey]
        }
        [string[]]$sortedKeys = @($keys)
        [Array]::Sort($sortedKeys, [StringComparer]::Ordinal)
        $parts = @()
        foreach ($key in $sortedKeys) {
            $parts += ((ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value $key) + ':' + (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $valueByKey[$key]))
        }
        return '{' + ($parts -join ',') + '}'
    }
    if ($Value -is [System.Collections.IEnumerable]) {
        $parts = @()
        foreach ($item in $Value) { $parts += ,(ConvertTo-CddsiVmCalibrationCanonicalJson -Value $item) }
        return '[' + ($parts -join ',') + ']'
    }

    $propertyByName = @{}
    $names = New-Object System.Collections.Generic.List[string]
    foreach ($property in $Value.PSObject.Properties) {
        if ($property.Name -isnot [string] -or $propertyByName.ContainsKey($property.Name)) { throw 'Canonical calibration JSON requires unique property names.' }
        $names.Add($property.Name)
        $propertyByName[$property.Name] = $property.Value
    }
    [string[]]$sortedNames = @($names)
    [Array]::Sort($sortedNames, [StringComparer]::Ordinal)
    $propertyParts = @()
    foreach ($name in $sortedNames) {
        $propertyParts += ((ConvertTo-CddsiVmCalibrationCanonicalJsonString -Value $name) + ':' + (ConvertTo-CddsiVmCalibrationCanonicalJson -Value $propertyByName[$name]))
    }
    return '{' + ($propertyParts -join ',') + '}'
}

function Get-CddsiVmCalibrationCanonicalBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Value)

    $json = ConvertTo-CddsiVmCalibrationCanonicalJson -Value $Value
    return Get-CddsiSupplyChainTextBindingToken -Text $json
}

function Test-CddsiVmCalibrationSha256Value {
    [CmdletBinding()]
    param([AllowNull()]$Value, [switch]$AllowNotObserved)

    if ($AllowNotObserved -and $Value -is [string] -and $Value -ceq $script:CddsiVmCalibrationNotObserved) { return $true }
    return ($Value -is [string] -and $Value -match '^[a-f0-9]{64}$')
}

function Test-CddsiVmCalibrationSafeText {
    [CmdletBinding()]
    param(
        [AllowNull()]$Value,
        [switch]$AllowEmpty,
        [switch]$AllowNotObserved,
        [ValidateRange(1, 512)][int]$MaxLength = 256
    )

    if ($AllowNotObserved -and $Value -is [string] -and $Value -ceq $script:CddsiVmCalibrationNotObserved) { return $true }
    if ($Value -isnot [string] -or $Value.Length -gt $MaxLength) { return $false }
    if (-not $AllowEmpty -and $Value.Length -eq 0) { return $false }
    if ($Value -match '[\x00-\x1F\x7F\{\}\[\]]') { return $false }
    if ($Value -match '(?i)(?:[A-Z]:\\|\\\\|/Users/|/home/)') { return $false }
    return (@(Find-CddsiPotentialSecrets -Content $Value -Source '<vm-calibration-text>').Count -eq 0)
}

function Test-CddsiVmCalibrationHttpsUri {
    [CmdletBinding()]
    param([AllowNull()]$Value, [switch]$AllowNoRedirect, [switch]$AllowNotObserved)

    if ($AllowNotObserved -and $Value -is [string] -and $Value -ceq $script:CddsiVmCalibrationNotObserved) { return $true }
    if ($AllowNoRedirect -and $Value -is [string] -and $Value -ceq 'NO_REDIRECT') { return $true }
    if ($Value -isnot [string] -or [string]::IsNullOrWhiteSpace($Value) -or $Value.Length -gt 2048) { return $false }
    $uri = $null
    if (-not [uri]::TryCreate($Value, [UriKind]::Absolute, [ref]$uri)) { return $false }
    if (
        $uri.Scheme -cne 'https' -or
        -not $uri.IsDefaultPort -or
        $Value -cne $uri.AbsoluteUri -or
        [string]::IsNullOrWhiteSpace($uri.Host) -or
        -not [string]::IsNullOrEmpty($uri.UserInfo) -or
        $uri.AbsolutePath.Contains('%') -or
        $uri.AbsolutePath.Contains('//') -or
        $uri.AbsolutePath.Contains('\')
    ) { return $false }
    if (-not [string]::IsNullOrEmpty($uri.Query) -or -not [string]::IsNullOrEmpty($uri.Fragment)) { return $false }
    return (@(Find-CddsiPotentialSecrets -Content $Value -Source '<vm-calibration-uri>').Count -eq 0)
}

function Test-CddsiVmCalibrationTimestampValue {
    [CmdletBinding()]
    param([AllowNull()]$Value)

    return (
        $Value -is [string] -and
        [regex]::IsMatch($Value, '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,7})?Z$') -and
        (Test-CddsiUtcTimestampValue -Value $Value)
    )
}

function Get-CddsiVmCalibrationOperationSetDigest {
    [CmdletBinding()]
    param()

    return Get-CddsiSupplyChainTextBindingToken -Text ("cddsi-vm-calibration-operation-set-v1`n" + (@($script:CddsiVmCalibrationOperations) -join "`n"))
}

function Get-CddsiVmCalibrationSessionAnchorToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$StageManifest,
        [Parameter(Mandatory = $true)]$OperationGrant,
        [Parameter(Mandatory = $true)]$AuthorizationSession,
        [Parameter(Mandatory = $true)]$WorkflowSessionState,
        [Parameter(Mandatory = $true)]$OperationUseStates
    )

    if (-not (Test-CddsiStageGrantSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession) -or
        -not (Test-CddsiWorkflowSessionBinding -StageManifest $StageManifest -OperationGrant $OperationGrant -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState)) {
        throw 'VM calibration session anchor requires one bound stage authorization session.'
    }
    if ($StageManifest.Stage -cne 'VmCalibration' -or $StageManifest.ArtifactProfile -cne 'VmCalibration') {
        throw 'VM calibration session anchor requires the VmCalibration profile.'
    }
    $states = @($OperationUseStates)
    if ($states.Count -ne $script:CddsiVmCalibrationOperations.Count -or
        @($OperationGrant.AllowedOperations).Count -ne $script:CddsiVmCalibrationOperations.Count) {
        throw 'VM calibration session anchor requires the exact eight-operation set.'
    }
    $stateKeys = [System.Collections.Generic.List[string]]::new()
    for ($index = 0; $index -lt $script:CddsiVmCalibrationOperations.Count; $index++) {
        $operation = $script:CddsiVmCalibrationOperations[$index]
        $state = $states[$index]
        if ($OperationGrant.AllowedOperations[$index] -cne $operation -or
            -not (Test-CddsiOperationUseBinding -StageManifest $StageManifest -OperationGrant $OperationGrant `
                -AuthorizationSession $AuthorizationSession -WorkflowSessionState $WorkflowSessionState `
                -OperationUseState $state) -or
            $state.Operation -cne $operation) {
            throw 'VM calibration operation-use states are not exact, ordered and bound.'
        }
        $stateKeys.Add($state.StateKeySha256)
    }
    if (@($stateKeys | Select-Object -Unique).Count -ne $stateKeys.Count) {
        throw 'VM calibration operation-use state keys must be unique.'
    }
    $payload = [pscustomobject][ordered]@{
        ContractVersion                 = 'cddsi-vm-calibration-session-anchor-v1'
        StageManifest                   = $StageManifest
        OperationGrant                  = $OperationGrant
        AuthorizationSession            = $AuthorizationSession
        WorkflowSessionStateKeySha256   = $WorkflowSessionState.StateKeySha256
        OperationSetDigestSha256        = Get-CddsiVmCalibrationOperationSetDigest
        OperationUseStateKeySha256      = @($stateKeys)
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Get-CddsiVmCalibrationSessionBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ExpectedSession)

    if (-not (Test-CddsiExactPropertySet -InputObject $ExpectedSession -Expected @(
        'SchemaVersion', 'ContractVersion', 'StageManifest', 'OperationGrant',
        'AuthorizationSession', 'WorkflowSessionState', 'OperationUseStates',
        'SessionAnchorToken', 'SessionBindingToken'
    ))) { throw 'ExpectedSession does not match the v2 binding schema.' }
    $payload = [pscustomobject][ordered]@{
        SchemaVersion        = $ExpectedSession.SchemaVersion
        ContractVersion      = $ExpectedSession.ContractVersion
        StageManifest        = $ExpectedSession.StageManifest
        OperationGrant       = $ExpectedSession.OperationGrant
        AuthorizationSession = $ExpectedSession.AuthorizationSession
        WorkflowSessionState = $ExpectedSession.WorkflowSessionState
        OperationUseStates   = @($ExpectedSession.OperationUseStates)
        SessionAnchorToken   = $ExpectedSession.SessionAnchorToken
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiVmCalibrationSession {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $ExpectedSession -Expected @(
            'SchemaVersion', 'ContractVersion', 'StageManifest', 'OperationGrant',
            'AuthorizationSession', 'WorkflowSessionState', 'OperationUseStates',
            'SessionAnchorToken', 'SessionBindingToken'
        ))) { return $false }
        if (($ExpectedSession.SchemaVersion -isnot [int] -and $ExpectedSession.SchemaVersion -isnot [long]) -or
            [long]$ExpectedSession.SchemaVersion -ne 2 -or
            $ExpectedSession.ContractVersion -cne 'cddsi-vm-calibration-session-v2') { return $false }
        if ($ExpectedSessionAnchorToken -notmatch '^[a-f0-9]{64}$' -or
            $ExpectedSession.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
            $ExpectedSession.SessionBindingToken -notmatch '^[a-f0-9]{64}$') { return $false }

        $manifest = $ExpectedSession.StageManifest
        $grant = $ExpectedSession.OperationGrant
        $authorization = $ExpectedSession.AuthorizationSession
        $workflow = $ExpectedSession.WorkflowSessionState
        $states = @($ExpectedSession.OperationUseStates)
        if (-not (Test-CddsiStageGrantSessionBinding -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $authorization) -or
            -not (Test-CddsiWorkflowSessionBinding -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $authorization -WorkflowSessionState $workflow)) { return $false }
        if ($manifest.Stage -cne 'VmCalibration' -or $manifest.ArtifactProfile -cne 'VmCalibration' -or
            $grant.ArtifactProfile -cne 'VmCalibration' -or $authorization.ArtifactProfile -cne 'VmCalibration' -or
            $workflow.State -cne 'COMPLETED') { return $false }

        $operations = @($grant.AllowedOperations)
        if ($operations.Count -ne $script:CddsiVmCalibrationOperations.Count -or
            $states.Count -ne $script:CddsiVmCalibrationOperations.Count) { return $false }
        $seenStateKeys = @{}
        $seenUseIds = @{}
        $seenIdempotencyKeys = @{}
        $previousOccurredAt = [DateTimeOffset]::Parse($authorization.ClaimedAtUtc)
        for ($index = 0; $index -lt $script:CddsiVmCalibrationOperations.Count; $index++) {
            $operation = $script:CddsiVmCalibrationOperations[$index]
            $state = $states[$index]
            if ($operations[$index] -cne $operation -or
                -not (Test-CddsiTerminalOperationUseReceipt -StageManifest $manifest -OperationGrant $grant `
                    -AuthorizationSession $authorization -WorkflowSessionState $workflow `
                    -OperationUseState $state -Operation $operation -OperationUseId $state.OperationUseId `
                    -Outcome COMPLETED -ExpectedProviderEvidenceDigest $state.ProviderEvidenceDigest)) { return $false }
            if ($seenStateKeys.ContainsKey($state.StateKeySha256) -or $seenUseIds.ContainsKey($state.OperationUseId) -or
                $seenIdempotencyKeys.ContainsKey($state.IdempotencyKey)) { return $false }
            $seenStateKeys[$state.StateKeySha256] = $true
            $seenUseIds[$state.OperationUseId] = $true
            $seenIdempotencyKeys[$state.IdempotencyKey] = $true
            $occurredAt = [DateTimeOffset]::Parse($state.OccurredAtUtc)
            if ($occurredAt -lt $previousOccurredAt) { return $false }
            $previousOccurredAt = $occurredAt
        }
        if ($workflow.TerminalOperationSetDigestSha256 -cne (Get-CddsiTerminalOperationSetDigest -OperationGrant $grant -OperationUseStates $states)) { return $false }
        $anchor = Get-CddsiVmCalibrationSessionAnchorToken -StageManifest $manifest -OperationGrant $grant `
            -AuthorizationSession $authorization -WorkflowSessionState $workflow -OperationUseStates $states
        if ($anchor -cne $ExpectedSessionAnchorToken -or
            $ExpectedSession.SessionBindingToken -cne (Get-CddsiVmCalibrationSessionBindingToken -ExpectedSession $ExpectedSession)) { return $false }
        if (-not (Test-CddsiVmCalibrationTimestampValue -Value $ValidationTimeUtc)) { return $false }
        $completed = [DateTimeOffset]::Parse($workflow.OccurredAtUtc)
        $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
        if ($completed -lt $previousOccurredAt -or $completed -ge [DateTimeOffset]::Parse($authorization.ExpiresAtUtc) -or
            $validationTime -lt $completed -or ($validationTime - $completed).TotalSeconds -gt $MaximumAgeSeconds) { return $false }
        return $true
    }
    catch { return $false }
}

function New-CddsiVmCalibrationSessionReference {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    if (-not (Test-CddsiVmCalibrationSession -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) { throw 'ExpectedSession 未通过 P10A 外部会话合同校验。' }
    return [pscustomobject][ordered]@{
        SchemaVersion            = 2
        ContractVersion          = 'cddsi-vm-calibration-session-reference-v2'
        SessionAnchorToken       = $ExpectedSessionAnchorToken
        SessionBindingToken      = $ExpectedSession.SessionBindingToken
        ArtifactSha256           = $ExpectedSession.OperationGrant.ArtifactSha256
        SidecarSha256            = $ExpectedSession.OperationGrant.SidecarSha256
        ContentDigest            = $ExpectedSession.OperationGrant.ContentDigest
        ArtifactProfile          = $ExpectedSession.OperationGrant.ArtifactProfile
        RunId                    = $ExpectedSession.OperationGrant.RunId
        GrantId                  = $ExpectedSession.OperationGrant.GrantId
        ClaimId                  = $ExpectedSession.AuthorizationSession.ClaimId
        WorkflowStateKeySha256   = $ExpectedSession.WorkflowSessionState.StateKeySha256
        TerminalSetDigestSha256  = $ExpectedSession.WorkflowSessionState.TerminalOperationSetDigestSha256
        IssuedAtUtc              = $ExpectedSession.OperationGrant.IssuedAtUtc
        ClaimedAtUtc             = $ExpectedSession.AuthorizationSession.ClaimedAtUtc
        CompletedAtUtc           = $ExpectedSession.WorkflowSessionState.OccurredAtUtc
        ExpiresAtUtc             = $ExpectedSession.AuthorizationSession.ExpiresAtUtc
    }
}

function Resolve-CddsiVmCalibrationSelection {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$MsixCandidates)

    $candidates = @($MsixCandidates)
    $candidateSetDigest = Get-CddsiVmCalibrationCanonicalBindingToken -Value $candidates
    $status = 'INCOMPLETE'
    $flavor = $script:CddsiVmCalibrationNotObserved
    $scope = $script:CddsiVmCalibrationNotObserved
    $selectedArtifactSha256 = $script:CddsiVmCalibrationNotObserved
    $reasonCode = 'MSIX_CANDIDATE_SET_INCOMPLETE'

    if ($candidates.Count -eq 2 -and $candidates[0].Flavor -ceq 'Standard' -and $candidates[1].Flavor -ceq 'Offline') {
        if (@($candidates | Where-Object { $_.Status -ceq 'NOT_OBSERVED' }).Count -gt 0) {
            $reasonCode = 'MSIX_CANDIDATE_NOT_OBSERVED'
        }
        elseif (@($candidates | Where-Object { $_.Status -ceq 'FAILED' }).Count -gt 0) {
            $status = 'FAILED'
            $reasonCode = 'MSIX_CANDIDATE_FAILED'
        }
        elseif (@($candidates | Where-Object { $_.Status -cne 'OBSERVED' }).Count -gt 0) {
            $status = 'FAILED'
            $reasonCode = 'MSIX_CANDIDATE_STATUS_INVALID'
        }
        else {
            $viable = @()
            foreach ($candidate in $candidates) {
                $recommendedScope = [string]$candidate.Deployments.RecommendedScope
                $scopeRecord = if ($recommendedScope -ceq 'PER_USER') { $candidate.Deployments.PerUser } elseif ($recommendedScope -ceq 'MACHINE_WIDE') { $candidate.Deployments.MachineWide } else { $null }
                if ($null -ne $scopeRecord -and
                    $scopeRecord.Result -ceq 'PASS' -and
                    $scopeRecord.PackageInstalled -is [bool] -and [bool]$scopeRecord.PackageInstalled -and
                    $scopeRecord.CoworkService -ceq 'PRESENT' -and
                    $candidate.Signer.AuthenticodeStatus -ceq 'VALID' -and
                    $candidate.Signer.ChainTrusted -is [bool] -and [bool]$candidate.Signer.ChainTrusted -and
                    $candidate.Signer.TimestampStatus -cne 'INVALID') {
                    $viable += $candidate
                }
            }
            if (@($viable | Where-Object { $_.Flavor -ceq 'Standard' }).Count -eq 1) {
                $selected = @($viable | Where-Object { $_.Flavor -ceq 'Standard' })[0]
                $status = 'SELECTED'
                $flavor = 'Standard'
                $scope = $selected.Deployments.RecommendedScope
                $selectedArtifactSha256 = $selected.ArtifactSha256
                $reasonCode = 'STANDARD_CANDIDATE_PREFERRED'
            }
            elseif (@($viable | Where-Object { $_.Flavor -ceq 'Offline' }).Count -eq 1) {
                $selected = @($viable | Where-Object { $_.Flavor -ceq 'Offline' })[0]
                $status = 'SELECTED'
                $flavor = 'Offline'
                $scope = $selected.Deployments.RecommendedScope
                $selectedArtifactSha256 = $selected.ArtifactSha256
                $reasonCode = 'OFFLINE_CANDIDATE_REQUIRED'
            }
            else {
                $status = 'FAILED'
                $reasonCode = 'NO_VIABLE_MSIX_CANDIDATE'
            }
        }
    }

    return [pscustomobject][ordered]@{
        SchemaVersion             = 1
        ContractVersion           = 'cddsi-vm-calibration-selection-v1'
        Status                    = $status
        Flavor                    = $flavor
        Scope                     = $scope
        SelectedArtifactSha256    = $selectedArtifactSha256
        CandidateSetDigestSha256  = $candidateSetDigest
        ReasonCode                = $reasonCode
    }
}

function Resolve-CddsiVmCalibrationReadiness {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$OsImage,
        [Parameter(Mandatory = $true)]$MsixCandidates,
        [Parameter(Mandatory = $true)]$Selection,
        [Parameter(Mandatory = $true)]$Git,
        [Parameter(Mandatory = $true)]$DesktopBehavior
    )

    $failed = $false
    $incomplete = $false
    $reasons = @()
    $seenReasons = @{}
    foreach ($pair in @(
        [pscustomobject]@{ Name = 'OS'; Value = $OsImage },
        [pscustomobject]@{ Name = 'GIT'; Value = $Git },
        [pscustomobject]@{ Name = 'DESKTOP_BEHAVIOR'; Value = $DesktopBehavior }
    )) {
        if ($null -eq $pair.Value -or $null -eq $pair.Value.PSObject.Properties['Status']) {
            $failed = $true
            $code = ('{0}_SCHEMA_INVALID' -f $pair.Name)
        }
        elseif ($pair.Value.Status -ceq 'FAILED') {
            $failed = $true
            $code = ('{0}_CALIBRATION_FAILED' -f $pair.Name)
        }
        elseif ($pair.Value.Status -ceq 'NOT_OBSERVED' -or (ConvertTo-CddsiJson -InputObject $pair.Value).Contains(('"{0}"' -f $script:CddsiVmCalibrationNotObserved))) {
            $incomplete = $true
            $code = ('{0}_NOT_OBSERVED' -f $pair.Name)
        }
        elseif ($pair.Value.Status -cne 'OBSERVED') {
            $failed = $true
            $code = ('{0}_STATUS_INVALID' -f $pair.Name)
        }
        else { $code = $null }
        if ($null -ne $code -and -not $seenReasons.ContainsKey($code)) { $seenReasons[$code] = $true; $reasons += $code }
    }

    $candidates = @($MsixCandidates)
    if ($candidates.Count -ne 2) {
        $incomplete = $true
        $seenReasons['MSIX_CANDIDATE_SET_INCOMPLETE'] = $true
        $reasons += 'MSIX_CANDIDATE_SET_INCOMPLETE'
    }
    else {
        foreach ($candidate in $candidates) {
            if ($candidate.Status -ceq 'FAILED') {
                $failed = $true
                if (-not $seenReasons.ContainsKey('MSIX_CANDIDATE_FAILED')) { $seenReasons['MSIX_CANDIDATE_FAILED'] = $true; $reasons += 'MSIX_CANDIDATE_FAILED' }
            }
            elseif ($candidate.Status -ceq 'NOT_OBSERVED' -or (ConvertTo-CddsiJson -InputObject $candidate).Contains(('"{0}"' -f $script:CddsiVmCalibrationNotObserved))) {
                $incomplete = $true
                if (-not $seenReasons.ContainsKey('MSIX_CANDIDATE_NOT_OBSERVED')) { $seenReasons['MSIX_CANDIDATE_NOT_OBSERVED'] = $true; $reasons += 'MSIX_CANDIDATE_NOT_OBSERVED' }
            }
            elseif ($candidate.Status -cne 'OBSERVED') {
                $failed = $true
                if (-not $seenReasons.ContainsKey('MSIX_CANDIDATE_STATUS_INVALID')) { $seenReasons['MSIX_CANDIDATE_STATUS_INVALID'] = $true; $reasons += 'MSIX_CANDIDATE_STATUS_INVALID' }
            }
            if ($candidate.Status -ceq 'OBSERVED' -and (
                $candidate.Signer.AuthenticodeStatus -ceq 'INVALID' -or
                ($candidate.Signer.ChainTrusted -is [bool] -and -not [bool]$candidate.Signer.ChainTrusted) -or
                $candidate.Signer.TimestampStatus -ceq 'INVALID'
            )) {
                $failed = $true
                if (-not $seenReasons.ContainsKey('MSIX_SIGNATURE_INVALID')) { $seenReasons['MSIX_SIGNATURE_INVALID'] = $true; $reasons += 'MSIX_SIGNATURE_INVALID' }
            }
        }
    }

    if ($Selection.Status -ceq 'INCOMPLETE') {
        $incomplete = $true
        if (-not $seenReasons.ContainsKey($Selection.ReasonCode)) { $seenReasons[$Selection.ReasonCode] = $true; $reasons += $Selection.ReasonCode }
    }
    elseif ($Selection.Status -ceq 'FAILED') {
        $failed = $true
        if (-not $seenReasons.ContainsKey($Selection.ReasonCode)) { $seenReasons[$Selection.ReasonCode] = $true; $reasons += $Selection.ReasonCode }
    }
    elseif ($Selection.Status -cne 'SELECTED') {
        $failed = $true
        if (-not $seenReasons.ContainsKey('MSIX_SELECTION_INVALID')) { $seenReasons['MSIX_SELECTION_INVALID'] = $true; $reasons += 'MSIX_SELECTION_INVALID' }
    }

    if ($OsImage.Status -ceq 'OBSERVED' -and $OsImage.NestedVirtualization -ceq 'UNSUPPORTED') {
        $failed = $true
        if (-not $seenReasons.ContainsKey('NESTED_VIRTUALIZATION_UNSUPPORTED')) { $seenReasons['NESTED_VIRTUALIZATION_UNSUPPORTED'] = $true; $reasons += 'NESTED_VIRTUALIZATION_UNSUPPORTED' }
    }
    if ($Git.Status -ceq 'OBSERVED' -and ($Git.Signer.AuthenticodeStatus -ceq 'INVALID' -or ($Git.Signer.ChainTrusted -is [bool] -and -not [bool]$Git.Signer.ChainTrusted))) {
        $failed = $true
        if (-not $seenReasons.ContainsKey('GIT_SIGNATURE_INVALID')) { $seenReasons['GIT_SIGNATURE_INVALID'] = $true; $reasons += 'GIT_SIGNATURE_INVALID' }
    }

    if ($DesktopBehavior.Status -ceq 'OBSERVED') {
        foreach ($pair in @(
            [pscustomobject]@{ Name = 'HELPER'; Value = $DesktopBehavior.Helper },
            [pscustomobject]@{ Name = 'CHOOSER'; Value = $DesktopBehavior.Chooser },
            [pscustomobject]@{ Name = 'HKCU'; Value = $DesktopBehavior.HkcuManagedPolicy }
        )) {
            if ($pair.Value.Result -ceq 'FAIL') {
                $failed = $true
                $code = ('{0}_BEHAVIOR_FAILED' -f $pair.Name)
                if (-not $seenReasons.ContainsKey($code)) { $seenReasons[$code] = $true; $reasons += $code }
            }
            elseif ($pair.Value.Result -ceq 'NOT_OBSERVED') {
                $incomplete = $true
                $code = ('{0}_BEHAVIOR_NOT_OBSERVED' -f $pair.Name)
                if (-not $seenReasons.ContainsKey($code)) { $seenReasons[$code] = $true; $reasons += $code }
            }
        }
        if ($DesktopBehavior.Helper.Result -ceq 'PASS' -and (
            -not [bool]$DesktopBehavior.Helper.Invoked -or -not [bool]$DesktopBehavior.Helper.StdoutSingleToken -or
            -not [bool]$DesktopBehavior.Helper.StderrSafe -or -not [bool]$DesktopBehavior.Helper.TimeoutEnforced -or
            -not [bool]$DesktopBehavior.Helper.SilentRefreshObserved
        )) {
            $failed = $true
            if (-not $seenReasons.ContainsKey('HELPER_CONTRACT_MISMATCH')) { $seenReasons['HELPER_CONTRACT_MISMATCH'] = $true; $reasons += 'HELPER_CONTRACT_MISMATCH' }
        }
        if ($DesktopBehavior.Chooser.Result -ceq 'PASS' -and (
            -not [bool]$DesktopBehavior.Chooser.Hidden -or -not [bool]$DesktopBehavior.Chooser.DeveloperModeSkipped -or
            -not [bool]$DesktopBehavior.Chooser.AnthropicLoginSkipped
        )) {
            $failed = $true
            if (-not $seenReasons.ContainsKey('CHOOSER_CONTRACT_MISMATCH')) { $seenReasons['CHOOSER_CONTRACT_MISMATCH'] = $true; $reasons += 'CHOOSER_CONTRACT_MISMATCH' }
        }
        if ($DesktopBehavior.HkcuManagedPolicy.Result -ceq 'PASS' -and (
            -not [bool]$DesktopBehavior.HkcuManagedPolicy.Effective -or $DesktopBehavior.HkcuManagedPolicy.ValueType -cne 'REG_SZ' -or
            [long]$DesktopBehavior.HkcuManagedPolicy.ValueCount -ne 15 -or -not [bool]$DesktopBehavior.HkcuManagedPolicy.HelperReferenceUsed -or
            [bool]$DesktopBehavior.HkcuManagedPolicy.ConfigLibraryWriterUsed -or [bool]$DesktopBehavior.HkcuManagedPolicy.RawValuesCaptured
        )) {
            $failed = $true
            if (-not $seenReasons.ContainsKey('HKCU_CONTRACT_MISMATCH')) { $seenReasons['HKCU_CONTRACT_MISMATCH'] = $true; $reasons += 'HKCU_CONTRACT_MISMATCH' }
        }
    }

    $status = if ($failed) { 'FAILED' } elseif ($incomplete) { 'INCOMPLETE' } else { 'COMPLETE' }
    if ($status -ceq 'COMPLETE') { $reasons = @('CALIBRATION_COMPLETE') }
    return [pscustomobject][ordered]@{
        SchemaVersion           = 1
        Status                  = $status
        ReasonCodes             = @($reasons)
        ScopeRecommendation     = if ($Selection.Status -ceq 'SELECTED') { $Selection.Scope } else { $script:CddsiVmCalibrationNotObserved }
        ComprehensiveAcceptance = $false
    }
}

function Test-CddsiVmCalibrationCleanupEvidence {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Cleanup)

    if (-not (Test-CddsiExactPropertySet -InputObject $Cleanup -Expected @(
        'SchemaVersion', 'Status', 'ObservedAtUtc', 'CalibrationArtifactsRemoved',
        'TemporaryCredentialRemoved', 'TemporaryPolicyRemoved', 'DesktopProcessesStopped',
        'FailureCode'
    ))) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Cleanup.SchemaVersion) -or
        $Cleanup.Status -cnotin @('COMPLETE', 'FAILED') -or
        -not (Test-CddsiVmCalibrationTimestampValue -Value $Cleanup.ObservedAtUtc)) { return $false }
    foreach ($name in @('CalibrationArtifactsRemoved', 'TemporaryCredentialRemoved', 'TemporaryPolicyRemoved', 'DesktopProcessesStopped')) {
        if ($Cleanup.$name -isnot [bool]) { return $false }
    }
    if ($Cleanup.Status -ceq 'COMPLETE') {
        return ($Cleanup.CalibrationArtifactsRemoved -and $Cleanup.TemporaryCredentialRemoved -and
            $Cleanup.TemporaryPolicyRemoved -and $Cleanup.DesktopProcessesStopped -and
            $Cleanup.FailureCode -is [string] -and $Cleanup.FailureCode -ceq '')
    }
    return (Test-CddsiSafeIdentifierValue -Value $Cleanup.FailureCode -MaxLength 64)
}

function Get-CddsiVmCalibrationOperationEvidenceRecords {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ObservationStartedAtUtc,
        [Parameter(Mandatory = $true)]$OsImage,
        [Parameter(Mandatory = $true)]$MsixCandidates,
        [Parameter(Mandatory = $true)]$Selection,
        [Parameter(Mandatory = $true)]$Git,
        [Parameter(Mandatory = $true)]$DesktopBehavior,
        [Parameter(Mandatory = $true)]$Readiness,
        [Parameter(Mandatory = $true)]$Cleanup
    )

    $candidates = @($MsixCandidates)
    if ($candidates.Count -ne 2) { throw 'VM calibration operation evidence requires exactly two MSIX candidates.' }
    $acquisition = [pscustomobject][ordered]@{
        Msix = @($candidates | ForEach-Object {
            [pscustomobject][ordered]@{
                Flavor = $_.Flavor; SourceUri = $_.SourceUri; RedirectUri = $_.RedirectUri
                RedirectCount = $_.RedirectCount; SizeBytes = $_.SizeBytes; ArtifactSha256 = $_.ArtifactSha256
            }
        })
        Git = [pscustomobject][ordered]@{
            ReleaseTag = $Git.ReleaseTag; AssetName = $Git.AssetName; SourceUri = $Git.SourceUri
            SizeBytes = $Git.SizeBytes; ArtifactSha256 = $Git.ArtifactSha256
        }
    }
    $verification = [pscustomobject][ordered]@{
        Msix = @($candidates | ForEach-Object {
            [pscustomobject][ordered]@{
                Flavor = $_.Flavor; Signer = $_.Signer; Certificate = $_.Certificate
                ManifestIdentity = $_.ManifestIdentity
            }
        })
        Git = [pscustomobject][ordered]@{ Signer = $Git.Signer; PeIdentity = $Git.PeIdentity }
    }
    $scope = [pscustomobject][ordered]@{
        Candidates = @($candidates | ForEach-Object {
            [pscustomobject][ordered]@{ Flavor = $_.Flavor; Deployments = $_.Deployments }
        })
        Selection = $Selection
    }
    $draft = [pscustomobject][ordered]@{
        ObservationStartedAtUtc = $ObservationStartedAtUtc
        OsImage = $OsImage
        MsixCandidates = $candidates
        Selection = $Selection
        Git = $Git
        DesktopBehavior = $DesktopBehavior
        Readiness = $Readiness
    }
    $payloads = @(
        $OsImage,
        $acquisition,
        $verification,
        $scope,
        $DesktopBehavior,
        $Git,
        $draft,
        $Cleanup
    )
    $records = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $script:CddsiVmCalibrationOperations.Count; $index++) {
        $operation = $script:CddsiVmCalibrationOperations[$index]
        $bindingPayload = [pscustomobject][ordered]@{
            ContractVersion = 'cddsi-vm-calibration-operation-evidence-v1'
            Operation = $operation
            Evidence = $payloads[$index]
        }
        $records.Add([pscustomobject][ordered]@{
            SchemaVersion         = 1
            ContractVersion       = 'cddsi-vm-calibration-operation-evidence-reference-v1'
            Operation             = $operation
            ProviderEvidenceDigest = Get-CddsiVmCalibrationCanonicalBindingToken -Value $bindingPayload
        })
    }
    return @($records)
}

function New-CddsiVmCalibrationOperationReceiptReferences {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)]$OperationEvidenceRecords
    )

    $records = @($OperationEvidenceRecords)
    $states = @($ExpectedSession.OperationUseStates)
    if ($records.Count -ne $script:CddsiVmCalibrationOperations.Count -or $states.Count -ne $records.Count) {
        throw 'VM calibration receipt references require the exact operation set.'
    }
    $references = [System.Collections.Generic.List[object]]::new()
    for ($index = 0; $index -lt $records.Count; $index++) {
        $record = $records[$index]
        $state = $states[$index]
        $operation = $script:CddsiVmCalibrationOperations[$index]
        if (-not (Test-CddsiExactPropertySet -InputObject $record -Expected @('SchemaVersion', 'ContractVersion', 'Operation', 'ProviderEvidenceDigest')) -or
            -not (Test-CddsiSchemaVersionOne -Value $record.SchemaVersion) -or
            $record.ContractVersion -cne 'cddsi-vm-calibration-operation-evidence-reference-v1' -or
            $record.Operation -cne $operation -or
            -not (Test-CddsiTerminalOperationUseReceipt -StageManifest $ExpectedSession.StageManifest `
                -OperationGrant $ExpectedSession.OperationGrant -AuthorizationSession $ExpectedSession.AuthorizationSession `
                -WorkflowSessionState $ExpectedSession.WorkflowSessionState -OperationUseState $state `
                -Operation $operation -OperationUseId $state.OperationUseId -Outcome COMPLETED `
                -ExpectedProviderEvidenceDigest $record.ProviderEvidenceDigest)) {
            throw 'VM calibration terminal operation receipt is not bound to its exported evidence.'
        }
        $references.Add([pscustomobject][ordered]@{
            SchemaVersion          = 1
            Operation              = $operation
            StateKeySha256         = $state.StateKeySha256
            OperationUseId         = $state.OperationUseId
            Revision               = $state.Revision
            OccurredAtUtc          = $state.OccurredAtUtc
            IdempotencyKey         = $state.IdempotencyKey
            ProviderEvidenceDigest = $state.ProviderEvidenceDigest
            ReceiptBindingToken    = $state.ReceiptBindingToken
        })
    }
    return @($references)
}

function Get-CddsiVmCalibrationEvidenceBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Evidence)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion           = $Evidence.SchemaVersion
        Purpose                 = $Evidence.Purpose
        SessionBinding          = $Evidence.SessionBinding
        ObservationStartedAtUtc = $Evidence.ObservationStartedAtUtc
        CompletedAtUtc          = $Evidence.CompletedAtUtc
        OsImage                 = $Evidence.OsImage
        MsixCandidates          = @($Evidence.MsixCandidates)
        Selection               = $Evidence.Selection
        Git                     = $Evidence.Git
        DesktopBehavior         = $Evidence.DesktopBehavior
        Readiness               = $Evidence.Readiness
        Cleanup                 = $Evidence.Cleanup
        OperationReceipts       = @($Evidence.OperationReceipts)
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function New-CddsiVmCalibrationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [Parameter(Mandatory = $true)][string]$ObservationStartedAtUtc,
        [Parameter(Mandatory = $true)]$OsImage,
        [Parameter(Mandatory = $true)]$MsixCandidates,
        [Parameter(Mandatory = $true)]$Git,
        [Parameter(Mandatory = $true)]$DesktopBehavior,
        [Parameter(Mandatory = $true)]$Cleanup,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    if (-not (Test-CddsiVmCalibrationSession -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) { throw 'ExpectedSession 未通过 P10A 外部会话合同校验。' }
    if (-not (Test-CddsiVmCalibrationCleanupEvidence -Cleanup $Cleanup)) { throw 'VM calibration cleanup evidence 无效。' }
    $selection = Resolve-CddsiVmCalibrationSelection -MsixCandidates $MsixCandidates
    $readiness = Resolve-CddsiVmCalibrationReadiness -OsImage $OsImage -MsixCandidates $MsixCandidates -Selection $selection -Git $Git -DesktopBehavior $DesktopBehavior
    $sessionBinding = New-CddsiVmCalibrationSessionReference -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds
    $operationEvidence = Get-CddsiVmCalibrationOperationEvidenceRecords -ObservationStartedAtUtc $ObservationStartedAtUtc -OsImage $OsImage -MsixCandidates $MsixCandidates -Selection $selection -Git $Git -DesktopBehavior $DesktopBehavior -Readiness $readiness -Cleanup $Cleanup
    $operationReceipts = New-CddsiVmCalibrationOperationReceiptReferences -ExpectedSession $ExpectedSession -OperationEvidenceRecords $operationEvidence
    $evidenceWithoutToken = [pscustomobject][ordered]@{
        SchemaVersion           = 2
        Purpose                 = 'P10A_VM_CALIBRATION_ONLY'
        SessionBinding          = $sessionBinding
        ObservationStartedAtUtc = $ObservationStartedAtUtc
        CompletedAtUtc          = $ExpectedSession.WorkflowSessionState.OccurredAtUtc
        OsImage                 = $OsImage
        MsixCandidates          = @($MsixCandidates)
        Selection               = $selection
        Git                     = $Git
        DesktopBehavior         = $DesktopBehavior
        Readiness               = $readiness
        Cleanup                 = $Cleanup
        OperationReceipts       = $operationReceipts
    }
    $evidence = [pscustomobject][ordered]@{
        SchemaVersion           = $evidenceWithoutToken.SchemaVersion
        Purpose                 = $evidenceWithoutToken.Purpose
        SessionBinding          = $evidenceWithoutToken.SessionBinding
        ObservationStartedAtUtc = $evidenceWithoutToken.ObservationStartedAtUtc
        CompletedAtUtc          = $evidenceWithoutToken.CompletedAtUtc
        OsImage                 = $evidenceWithoutToken.OsImage
        MsixCandidates          = $evidenceWithoutToken.MsixCandidates
        Selection               = $evidenceWithoutToken.Selection
        Git                     = $evidenceWithoutToken.Git
        DesktopBehavior         = $evidenceWithoutToken.DesktopBehavior
        Readiness               = $evidenceWithoutToken.Readiness
        Cleanup                 = $evidenceWithoutToken.Cleanup
        OperationReceipts       = $evidenceWithoutToken.OperationReceipts
        EvidenceBindingToken    = Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $evidenceWithoutToken
    }
    if (-not (Test-CddsiVmCalibrationEvidence -Evidence $evidence -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) {
        throw 'VM calibration evidence 未通过严格 schema、session 或 transcript 绑定校验。'
    }
    return $evidence
}

function Test-CddsiVmCalibrationEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    try {
        $notObserved = $script:CddsiVmCalibrationNotObserved
        if (-not (Test-CddsiVmCalibrationSession -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) { return $false }
        if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @(
            'SchemaVersion', 'Purpose', 'SessionBinding', 'ObservationStartedAtUtc',
            'CompletedAtUtc', 'OsImage', 'MsixCandidates', 'Selection', 'Git',
            'DesktopBehavior', 'Readiness', 'Cleanup', 'OperationReceipts',
            'EvidenceBindingToken'
        ))) { return $false }
        if (($Evidence.SchemaVersion -isnot [int] -and $Evidence.SchemaVersion -isnot [long]) -or
            [long]$Evidence.SchemaVersion -ne 2 -or $Evidence.Purpose -cne 'P10A_VM_CALIBRATION_ONLY') { return $false }

        $expectedReference = New-CddsiVmCalibrationSessionReference -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds
        if (-not (Test-CddsiExactPropertySet -InputObject $Evidence.SessionBinding -Expected @(
            'SchemaVersion', 'ContractVersion', 'SessionAnchorToken', 'SessionBindingToken', 'ArtifactSha256',
            'SidecarSha256', 'ContentDigest', 'ArtifactProfile', 'RunId', 'GrantId',
            'ClaimId', 'WorkflowStateKeySha256', 'TerminalSetDigestSha256',
            'IssuedAtUtc', 'ClaimedAtUtc', 'CompletedAtUtc', 'ExpiresAtUtc'
        ))) { return $false }
        if ((Get-CddsiVmCalibrationCanonicalBindingToken -Value $Evidence.SessionBinding) -cne
            (Get-CddsiVmCalibrationCanonicalBindingToken -Value $expectedReference)) { return $false }

        foreach ($timestamp in @($Evidence.ObservationStartedAtUtc, $Evidence.CompletedAtUtc)) {
            if (-not (Test-CddsiVmCalibrationTimestampValue -Value $timestamp)) { return $false }
        }
        if ($Evidence.CompletedAtUtc -cne $ExpectedSession.WorkflowSessionState.OccurredAtUtc) { return $false }
        $observationStart = [DateTimeOffset]::Parse($Evidence.ObservationStartedAtUtc)
        $claimed = [DateTimeOffset]::Parse($ExpectedSession.AuthorizationSession.ClaimedAtUtc)
        $completed = [DateTimeOffset]::Parse($ExpectedSession.WorkflowSessionState.OccurredAtUtc)
        if ($observationStart -lt $claimed -or $observationStart -ge $completed) { return $false }

        $os = $Evidence.OsImage
        if (-not (Test-CddsiExactPropertySet -InputObject $os -Expected @('Status', 'ObservedAtUtc', 'ImageSha256', 'Sku', 'Architecture', 'Build', 'Ubr', 'Language', 'PatchDate', 'NestedVirtualization', 'FailureCode'))) { return $false }
        if ($os.Status -cnotin @('OBSERVED', 'NOT_OBSERVED', 'FAILED') -or -not (Test-CddsiVmCalibrationTimestampValue -Value $os.ObservedAtUtc)) { return $false }
        if (-not (Test-CddsiVmCalibrationSha256Value -Value $os.ImageSha256 -AllowNotObserved) -or -not (Test-CddsiVmCalibrationSafeText -Value $os.Sku -AllowNotObserved -MaxLength 128)) { return $false }
        if ($os.Architecture -cnotin @('x64', 'arm64', $notObserved)) { return $false }
        if (($os.Build -isnot [int] -and $os.Build -isnot [long] -and $os.Build -cne $notObserved) -or (($os.Build -is [int] -or $os.Build -is [long]) -and [long]$os.Build -lt 19041)) { return $false }
        if (($os.Ubr -isnot [int] -and $os.Ubr -isnot [long] -and $os.Ubr -cne $notObserved) -or (($os.Ubr -is [int] -or $os.Ubr -is [long]) -and [long]$os.Ubr -lt 0)) { return $false }
        if ($os.Language -cne $notObserved -and ($os.Language -isnot [string] -or $os.Language -notmatch '^[a-z]{2}-[A-Z]{2}$')) { return $false }
        if ($os.PatchDate -cne $notObserved -and ($os.PatchDate -isnot [string] -or $os.PatchDate -notmatch '^\d{4}-\d{2}-\d{2}$')) { return $false }
        if ($os.NestedVirtualization -cnotin @('SUPPORTED', 'UNSUPPORTED', $notObserved)) { return $false }
        if ($os.Status -ceq 'OBSERVED' -and $os.FailureCode -cne '') { return $false }
        if ($os.Status -ceq 'NOT_OBSERVED' -and $os.FailureCode -cne $notObserved) { return $false }
        if ($os.Status -ceq 'FAILED' -and -not (Test-CddsiSafeIdentifierValue -Value $os.FailureCode -MaxLength 64)) { return $false }

        $candidates = @($Evidence.MsixCandidates)
        if ($Evidence.MsixCandidates -isnot [System.Array] -or $candidates.Count -ne 2 -or $candidates[0].Flavor -cne 'Standard' -or $candidates[1].Flavor -cne 'Offline') { return $false }
        foreach ($msix in $candidates) {
            if (-not (Test-CddsiExactPropertySet -InputObject $msix -Expected @('Status', 'ObservedAtUtc', 'Flavor', 'SourceUri', 'RedirectUri', 'RedirectCount', 'Version', 'SizeBytes', 'ArtifactSha256', 'Signer', 'Certificate', 'ManifestIdentity', 'Deployments', 'FailureCode'))) { return $false }
            if ($msix.Status -cnotin @('OBSERVED', 'NOT_OBSERVED', 'FAILED') -or $msix.Flavor -cnotin @('Standard', 'Offline') -or -not (Test-CddsiVmCalibrationTimestampValue -Value $msix.ObservedAtUtc)) { return $false }
            if (-not (Test-CddsiVmCalibrationHttpsUri -Value $msix.SourceUri -AllowNotObserved) -or -not (Test-CddsiVmCalibrationHttpsUri -Value $msix.RedirectUri -AllowNoRedirect -AllowNotObserved)) { return $false }
            if ($msix.SourceUri -cne $notObserved -and -not (Test-CddsiOfficialArtifactUri -SourceUri $msix.SourceUri -ExpectedOwner Anthropic)) { return $false }
            if ($msix.RedirectUri -notin @($notObserved, 'NO_REDIRECT') -and -not (Test-CddsiOfficialArtifactUri -SourceUri $msix.RedirectUri -ExpectedOwner Anthropic)) { return $false }
            if (($msix.RedirectCount -isnot [int] -and $msix.RedirectCount -isnot [long] -and $msix.RedirectCount -cne $notObserved) -or (($msix.RedirectCount -is [int] -or $msix.RedirectCount -is [long]) -and ([long]$msix.RedirectCount -lt 0 -or [long]$msix.RedirectCount -gt 10))) { return $false }
            if ($msix.RedirectUri -ceq 'NO_REDIRECT' -and $msix.RedirectCount -ne 0) { return $false }
            if ($msix.RedirectUri -notin @($notObserved, 'NO_REDIRECT') -and ([long]$msix.RedirectCount -lt 1 -or $msix.RedirectUri -ceq $msix.SourceUri)) { return $false }
            if ($msix.Version -cne $notObserved -and ($msix.Version -isnot [string] -or $msix.Version -notmatch '^\d+\.\d+\.\d+\.\d+$')) { return $false }
            if (($msix.SizeBytes -isnot [int] -and $msix.SizeBytes -isnot [long] -and $msix.SizeBytes -cne $notObserved) -or (($msix.SizeBytes -is [int] -or $msix.SizeBytes -is [long]) -and [long]$msix.SizeBytes -lt 1)) { return $false }
            if (-not (Test-CddsiVmCalibrationSha256Value -Value $msix.ArtifactSha256 -AllowNotObserved)) { return $false }

            $signer = $msix.Signer
            if (-not (Test-CddsiExactPropertySet -InputObject $signer -Expected @('AuthenticodeStatus', 'ChainTrusted', 'Subject', 'Thumbprint', 'TimestampStatus'))) { return $false }
            if ($signer.AuthenticodeStatus -cnotin @('VALID', 'INVALID', $notObserved) -or ($signer.ChainTrusted -isnot [bool] -and $signer.ChainTrusted -cne $notObserved)) { return $false }
            if (-not (Test-CddsiVmCalibrationSafeText -Value $signer.Subject -AllowNotObserved -MaxLength 256)) { return $false }
            if ($signer.Thumbprint -cne $notObserved -and ($signer.Thumbprint -isnot [string] -or $signer.Thumbprint -notmatch '^[a-f0-9]{40}$')) { return $false }
            if ($signer.TimestampStatus -cnotin @('VALID', 'NOT_PRESENT', 'INVALID', $notObserved)) { return $false }

            $certificate = $msix.Certificate
            if (-not (Test-CddsiExactPropertySet -InputObject $certificate -Expected @('CertificateSha256', 'SerialNumber', 'NotBeforeUtc', 'NotAfterUtc'))) { return $false }
            if (-not (Test-CddsiVmCalibrationSha256Value -Value $certificate.CertificateSha256 -AllowNotObserved)) { return $false }
            if ($certificate.SerialNumber -cne $notObserved -and ($certificate.SerialNumber -isnot [string] -or $certificate.SerialNumber -notmatch '^[A-Fa-f0-9]{2,64}$')) { return $false }
            foreach ($name in @('NotBeforeUtc', 'NotAfterUtc')) {
                if ($certificate.$name -cne $notObserved -and -not (Test-CddsiVmCalibrationTimestampValue -Value $certificate.$name)) { return $false }
            }
            if ($certificate.NotBeforeUtc -cne $notObserved -and $certificate.NotAfterUtc -cne $notObserved -and [DateTimeOffset]$certificate.NotAfterUtc -le [DateTimeOffset]$certificate.NotBeforeUtc) { return $false }

            $identity = $msix.ManifestIdentity
            if (-not (Test-CddsiExactPropertySet -InputObject $identity -Expected @('Name', 'Publisher', 'Version', 'ProcessorArchitecture', 'ResourceId', 'PackageFamilyName', 'PackageFullName'))) { return $false }
            foreach ($name in @('Name', 'Publisher', 'PackageFamilyName', 'PackageFullName')) {
                if (-not (Test-CddsiVmCalibrationSafeText -Value $identity.$name -AllowNotObserved -MaxLength 256)) { return $false }
            }
            if ($identity.Version -cne $notObserved -and ($identity.Version -isnot [string] -or $identity.Version -notmatch '^\d+\.\d+\.\d+\.\d+$')) { return $false }
            if ($identity.ProcessorArchitecture -cnotin @('x64', 'arm64', 'neutral', $notObserved)) { return $false }
            if (-not (Test-CddsiVmCalibrationSafeText -Value $identity.ResourceId -AllowEmpty -AllowNotObserved -MaxLength 128)) { return $false }
            if ($msix.Version -cne $notObserved -and $identity.Version -cne $notObserved -and $msix.Version -cne $identity.Version) { return $false }

            $deployments = $msix.Deployments
            if (-not (Test-CddsiExactPropertySet -InputObject $deployments -Expected @('PerUser', 'MachineWide', 'RecommendedScope', 'RecommendationCode'))) { return $false }
            foreach ($scopeRecord in @($deployments.PerUser, $deployments.MachineWide)) {
                if (-not (Test-CddsiExactPropertySet -InputObject $scopeRecord -Expected @('Result', 'PackageInstalled', 'CoworkService', 'ErrorCode'))) { return $false }
                if ($scopeRecord.Result -cnotin @('PASS', 'FAIL', 'NOT_OBSERVED')) { return $false }
                if ($scopeRecord.PackageInstalled -isnot [bool] -and $scopeRecord.PackageInstalled -cne $notObserved) { return $false }
                if ($scopeRecord.CoworkService -cnotin @('PRESENT', 'ABSENT', $notObserved)) { return $false }
                if ($scopeRecord.Result -ceq 'PASS' -and (-not [bool]$scopeRecord.PackageInstalled -or $scopeRecord.CoworkService -cne 'PRESENT' -or $scopeRecord.ErrorCode -cne '')) { return $false }
                if ($scopeRecord.Result -ceq 'FAIL' -and -not (Test-CddsiSafeIdentifierValue -Value $scopeRecord.ErrorCode -MaxLength 64)) { return $false }
                if ($scopeRecord.Result -ceq 'NOT_OBSERVED' -and ($scopeRecord.PackageInstalled -cne $notObserved -or $scopeRecord.CoworkService -cne $notObserved -or $scopeRecord.ErrorCode -cne $notObserved)) { return $false }
            }
            if ($deployments.RecommendedScope -cnotin @('PER_USER', 'MACHINE_WIDE', 'NONE', $notObserved)) { return $false }
            if ($deployments.RecommendedScope -ceq $notObserved) {
                if ($deployments.RecommendationCode -cne $notObserved) { return $false }
            }
            elseif ($deployments.RecommendedScope -ceq 'NONE') {
                if (-not (Test-CddsiSafeIdentifierValue -Value $deployments.RecommendationCode -MaxLength 64) -or
                    $deployments.PerUser.Result -cne 'FAIL' -or $deployments.MachineWide.Result -cne 'FAIL') { return $false }
            }
            else {
                if (-not (Test-CddsiSafeIdentifierValue -Value $deployments.RecommendationCode -MaxLength 64)) { return $false }
                $recommended = if ($deployments.RecommendedScope -ceq 'PER_USER') { $deployments.PerUser } else { $deployments.MachineWide }
                if ($recommended.Result -cne 'PASS' -or $recommended.CoworkService -cne 'PRESENT') { return $false }
            }
            if ($msix.Status -ceq 'OBSERVED' -and $msix.FailureCode -cne '') { return $false }
            if ($msix.Status -ceq 'NOT_OBSERVED' -and $msix.FailureCode -cne $notObserved) { return $false }
            if ($msix.Status -ceq 'FAILED' -and -not (Test-CddsiSafeIdentifierValue -Value $msix.FailureCode -MaxLength 64)) { return $false }

            if ($msix.Status -ceq 'OBSERVED') {
                if (@($msix.SourceUri, $msix.RedirectUri, $msix.Version, $msix.ArtifactSha256) -ccontains $notObserved) { return $false }
                $source = [uri]$msix.SourceUri
                if ($source.DnsSafeHost -ceq 'claude.ai') {
                    $architecture = if ($os.Architecture -ceq 'arm64') { 'arm64' } else { 'x64' }
                    $expectedPath = if ($msix.Flavor -ceq 'Offline') {
                        '/api/desktop/win32/{0}/offline/latest/redirect' -f $architecture
                    }
                    else {
                        '/api/desktop/win32/{0}/latest/redirect' -f $architecture
                    }
                    if ($source.AbsolutePath -cne $expectedPath) { return $false }
                }
            }
        }

        if (@($candidates | Where-Object { $_.Status -ceq 'OBSERVED' }).Count -eq 2) {
            if (
                $candidates[0].SourceUri -ceq $candidates[1].SourceUri -or
                $candidates[0].RedirectUri -ceq $candidates[1].RedirectUri -or
                $candidates[0].ArtifactSha256 -ceq $candidates[1].ArtifactSha256 -or
                $candidates[0].Signer.Thumbprint -cne $candidates[1].Signer.Thumbprint -or
                $candidates[0].Signer.Subject -cne $candidates[1].Signer.Subject -or
                $candidates[0].ManifestIdentity.Name -cne $candidates[1].ManifestIdentity.Name -or
                $candidates[0].ManifestIdentity.Publisher -cne $candidates[1].ManifestIdentity.Publisher -or
                $candidates[0].ManifestIdentity.PackageFamilyName -cne $candidates[1].ManifestIdentity.PackageFamilyName
            ) { return $false }
        }

        $git = $Evidence.Git
        if (-not (Test-CddsiExactPropertySet -InputObject $git -Expected @('Status', 'ObservedAtUtc', 'ReleaseTag', 'AssetName', 'SourceUri', 'Version', 'SizeBytes', 'ArtifactSha256', 'Signer', 'PeIdentity', 'FailureCode'))) { return $false }
        if ($git.Status -cnotin @('OBSERVED', 'NOT_OBSERVED', 'FAILED') -or -not (Test-CddsiVmCalibrationTimestampValue -Value $git.ObservedAtUtc)) { return $false }
        if ($git.ReleaseTag -cne $notObserved -and -not (Test-CddsiSafeIdentifierValue -Value $git.ReleaseTag -MaxLength 128)) { return $false }
        if (-not (Test-CddsiVmCalibrationSafeText -Value $git.AssetName -AllowNotObserved -MaxLength 256)) { return $false }
        if ($git.AssetName -cne $notObserved -and ($git.AssetName -match '[\\/:]' -or $git.AssetName -in @('.', '..'))) { return $false }
        if (-not (Test-CddsiVmCalibrationHttpsUri -Value $git.SourceUri -AllowNotObserved)) { return $false }
        if ($git.SourceUri -cne $notObserved -and -not (Test-CddsiOfficialArtifactUri -SourceUri $git.SourceUri -ExpectedOwner GitForWindows)) { return $false }
        if ($git.Version -cne $notObserved -and -not (Test-CddsiSafeIdentifierValue -Value $git.Version -MaxLength 128)) { return $false }
        if (($git.SizeBytes -isnot [int] -and $git.SizeBytes -isnot [long] -and $git.SizeBytes -cne $notObserved) -or (($git.SizeBytes -is [int] -or $git.SizeBytes -is [long]) -and [long]$git.SizeBytes -lt 1)) { return $false }
        if (-not (Test-CddsiVmCalibrationSha256Value -Value $git.ArtifactSha256 -AllowNotObserved)) { return $false }
        $gitSigner = $git.Signer
        if (-not (Test-CddsiExactPropertySet -InputObject $gitSigner -Expected @('AuthenticodeStatus', 'ChainTrusted', 'Subject', 'Thumbprint', 'CertificateSha256'))) { return $false }
        if ($gitSigner.AuthenticodeStatus -cnotin @('VALID', 'INVALID', $notObserved) -or ($gitSigner.ChainTrusted -isnot [bool] -and $gitSigner.ChainTrusted -cne $notObserved)) { return $false }
        if (-not (Test-CddsiVmCalibrationSafeText -Value $gitSigner.Subject -AllowNotObserved -MaxLength 256)) { return $false }
        if ($gitSigner.Thumbprint -cne $notObserved -and ($gitSigner.Thumbprint -isnot [string] -or $gitSigner.Thumbprint -notmatch '^[a-f0-9]{40}$')) { return $false }
        if (-not (Test-CddsiVmCalibrationSha256Value -Value $gitSigner.CertificateSha256 -AllowNotObserved)) { return $false }
        $pe = $git.PeIdentity
        if (-not (Test-CddsiExactPropertySet -InputObject $pe -Expected @('OriginalFilename', 'ProductName', 'CompanyName', 'FileVersion', 'Machine'))) { return $false }
        foreach ($name in @('OriginalFilename', 'ProductName', 'CompanyName', 'FileVersion')) {
            if (-not (Test-CddsiVmCalibrationSafeText -Value $pe.$name -AllowNotObserved -MaxLength 256)) { return $false }
        }
        if ($pe.OriginalFilename -cne $notObserved -and $pe.OriginalFilename -match '[\\/:]') { return $false }
        if ($pe.Machine -cnotin @('x64', 'arm64', $notObserved)) { return $false }
        if ($git.Status -ceq 'OBSERVED' -and $git.FailureCode -cne '') { return $false }
        if ($git.Status -ceq 'OBSERVED') {
            if (@($git.ReleaseTag, $git.AssetName, $git.SourceUri, $git.Version, $git.ArtifactSha256, $git.PeIdentity.OriginalFilename) -ccontains $notObserved) { return $false }
            $expectedGitPath = '/git-for-windows/git/releases/download/{0}/{1}' -f $git.ReleaseTag, $git.AssetName
            if (([uri]$git.SourceUri).AbsolutePath -cne $expectedGitPath -or $git.PeIdentity.OriginalFilename -cne $git.AssetName) { return $false }
        }
        if ($git.Status -ceq 'NOT_OBSERVED' -and $git.FailureCode -cne $notObserved) { return $false }
        if ($git.Status -ceq 'FAILED' -and -not (Test-CddsiSafeIdentifierValue -Value $git.FailureCode -MaxLength 64)) { return $false }

        $behavior = $Evidence.DesktopBehavior
        if (-not (Test-CddsiExactPropertySet -InputObject $behavior -Expected @('Status', 'ObservedAtUtc', 'Helper', 'Chooser', 'HkcuManagedPolicy', 'FailureCode'))) { return $false }
        if ($behavior.Status -cnotin @('OBSERVED', 'NOT_OBSERVED', 'FAILED') -or -not (Test-CddsiVmCalibrationTimestampValue -Value $behavior.ObservedAtUtc)) { return $false }
        $helper = $behavior.Helper
        if (-not (Test-CddsiExactPropertySet -InputObject $helper -Expected @('Result', 'Invoked', 'StdoutSingleToken', 'StderrSafe', 'TimeoutEnforced', 'TtlObservedSeconds', 'SilentRefreshObserved', 'ErrorCode'))) { return $false }
        if ($helper.Result -cnotin @('PASS', 'FAIL', 'NOT_OBSERVED')) { return $false }
        foreach ($name in @('Invoked', 'StdoutSingleToken', 'StderrSafe', 'TimeoutEnforced', 'SilentRefreshObserved')) {
            if ($helper.$name -isnot [bool] -and $helper.$name -cne $notObserved) { return $false }
        }
        if (($helper.TtlObservedSeconds -isnot [int] -and $helper.TtlObservedSeconds -isnot [long] -and $helper.TtlObservedSeconds -cne $notObserved) -or (($helper.TtlObservedSeconds -is [int] -or $helper.TtlObservedSeconds -is [long]) -and ([long]$helper.TtlObservedSeconds -lt 1 -or [long]$helper.TtlObservedSeconds -gt 86400))) { return $false }
        if ($helper.Result -ceq 'PASS' -and $helper.ErrorCode -cne '') { return $false }
        if ($helper.Result -ceq 'FAIL' -and -not (Test-CddsiSafeIdentifierValue -Value $helper.ErrorCode -MaxLength 64)) { return $false }
        if ($helper.Result -ceq 'NOT_OBSERVED' -and ($helper.Invoked -cne $notObserved -or $helper.StdoutSingleToken -cne $notObserved -or $helper.StderrSafe -cne $notObserved -or $helper.TimeoutEnforced -cne $notObserved -or $helper.TtlObservedSeconds -cne $notObserved -or $helper.SilentRefreshObserved -cne $notObserved -or $helper.ErrorCode -cne $notObserved)) { return $false }

        $chooser = $behavior.Chooser
        if (-not (Test-CddsiExactPropertySet -InputObject $chooser -Expected @('Result', 'Hidden', 'DeveloperModeSkipped', 'AnthropicLoginSkipped', 'ErrorCode'))) { return $false }
        if ($chooser.Result -cnotin @('PASS', 'FAIL', 'NOT_OBSERVED')) { return $false }
        foreach ($name in @('Hidden', 'DeveloperModeSkipped', 'AnthropicLoginSkipped')) {
            if ($chooser.$name -isnot [bool] -and $chooser.$name -cne $notObserved) { return $false }
        }
        if ($chooser.Result -ceq 'PASS' -and $chooser.ErrorCode -cne '') { return $false }
        if ($chooser.Result -ceq 'FAIL' -and -not (Test-CddsiSafeIdentifierValue -Value $chooser.ErrorCode -MaxLength 64)) { return $false }
        if ($chooser.Result -ceq 'NOT_OBSERVED' -and ($chooser.Hidden -cne $notObserved -or $chooser.DeveloperModeSkipped -cne $notObserved -or $chooser.AnthropicLoginSkipped -cne $notObserved -or $chooser.ErrorCode -cne $notObserved)) { return $false }

        $hkcu = $behavior.HkcuManagedPolicy
        if (-not (Test-CddsiExactPropertySet -InputObject $hkcu -Expected @('Result', 'Effective', 'ValueType', 'ValueCount', 'HelperReferenceUsed', 'ConfigLibraryWriterUsed', 'RawValuesCaptured', 'ErrorCode'))) { return $false }
        if ($hkcu.Result -cnotin @('PASS', 'FAIL', 'NOT_OBSERVED')) { return $false }
        foreach ($name in @('Effective', 'HelperReferenceUsed', 'ConfigLibraryWriterUsed', 'RawValuesCaptured')) {
            if ($hkcu.$name -isnot [bool] -and $hkcu.$name -cne $notObserved) { return $false }
        }
        if ($hkcu.ValueType -cnotin @('REG_SZ', $notObserved)) { return $false }
        if (($hkcu.ValueCount -isnot [int] -and $hkcu.ValueCount -isnot [long] -and $hkcu.ValueCount -cne $notObserved) -or (($hkcu.ValueCount -is [int] -or $hkcu.ValueCount -is [long]) -and [long]$hkcu.ValueCount -lt 0)) { return $false }
        if ($hkcu.Result -ceq 'PASS' -and $hkcu.ErrorCode -cne '') { return $false }
        if ($hkcu.Result -ceq 'FAIL' -and -not (Test-CddsiSafeIdentifierValue -Value $hkcu.ErrorCode -MaxLength 64)) { return $false }
        if ($hkcu.Result -ceq 'NOT_OBSERVED' -and ($hkcu.Effective -cne $notObserved -or $hkcu.ValueType -cne $notObserved -or $hkcu.ValueCount -cne $notObserved -or $hkcu.HelperReferenceUsed -cne $notObserved -or $hkcu.ConfigLibraryWriterUsed -cne $notObserved -or $hkcu.RawValuesCaptured -cne $notObserved -or $hkcu.ErrorCode -cne $notObserved)) { return $false }
        if ($behavior.Status -ceq 'OBSERVED' -and $behavior.FailureCode -cne '') { return $false }
        if ($behavior.Status -ceq 'NOT_OBSERVED' -and $behavior.FailureCode -cne $notObserved) { return $false }
        if ($behavior.Status -ceq 'FAILED' -and -not (Test-CddsiSafeIdentifierValue -Value $behavior.FailureCode -MaxLength 64)) { return $false }

        foreach ($observation in @($os, $candidates[0], $candidates[1], $git, $behavior)) {
            $observedAt = [DateTimeOffset]::Parse($observation.ObservedAtUtc)
            if ($observedAt -lt $observationStart -or $observedAt -gt $completed) { return $false }
        }

        $selection = $Evidence.Selection
        if (-not (Test-CddsiExactPropertySet -InputObject $selection -Expected @('SchemaVersion', 'ContractVersion', 'Status', 'Flavor', 'Scope', 'SelectedArtifactSha256', 'CandidateSetDigestSha256', 'ReasonCode'))) { return $false }
        $resolvedSelection = Resolve-CddsiVmCalibrationSelection -MsixCandidates $candidates
        if ((Get-CddsiVmCalibrationCanonicalBindingToken -Value $selection) -cne (Get-CddsiVmCalibrationCanonicalBindingToken -Value $resolvedSelection)) { return $false }

        $readiness = $Evidence.Readiness
        if (-not (Test-CddsiExactPropertySet -InputObject $readiness -Expected @('SchemaVersion', 'Status', 'ReasonCodes', 'ScopeRecommendation', 'ComprehensiveAcceptance'))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $readiness.SchemaVersion) -or $readiness.Status -cnotin @('COMPLETE', 'INCOMPLETE', 'FAILED') -or $readiness.ComprehensiveAcceptance -isnot [bool] -or $readiness.ComprehensiveAcceptance) { return $false }
        $resolvedReadiness = Resolve-CddsiVmCalibrationReadiness -OsImage $os -MsixCandidates $candidates -Selection $resolvedSelection -Git $git -DesktopBehavior $behavior
        if ((Get-CddsiVmCalibrationCanonicalBindingToken -Value $readiness) -cne (Get-CddsiVmCalibrationCanonicalBindingToken -Value $resolvedReadiness)) { return $false }

        if (-not (Test-CddsiVmCalibrationCleanupEvidence -Cleanup $Evidence.Cleanup) -or $Evidence.Cleanup.Status -cne 'COMPLETE') { return $false }
        $cleanupObservedAt = [DateTimeOffset]::Parse($Evidence.Cleanup.ObservedAtUtc)
        if ($cleanupObservedAt -lt $observationStart -or $cleanupObservedAt -gt $completed) { return $false }

        $operationEvidence = Get-CddsiVmCalibrationOperationEvidenceRecords -ObservationStartedAtUtc $Evidence.ObservationStartedAtUtc -OsImage $os -MsixCandidates $candidates -Selection $selection -Git $git -DesktopBehavior $behavior -Readiness $readiness -Cleanup $Evidence.Cleanup
        $expectedReceipts = New-CddsiVmCalibrationOperationReceiptReferences -ExpectedSession $ExpectedSession -OperationEvidenceRecords $operationEvidence
        if ($Evidence.OperationReceipts -isnot [System.Array] -or @($Evidence.OperationReceipts).Count -ne $script:CddsiVmCalibrationOperations.Count -or
            (Get-CddsiVmCalibrationCanonicalBindingToken -Value @($Evidence.OperationReceipts)) -cne
            (Get-CddsiVmCalibrationCanonicalBindingToken -Value @($expectedReceipts))) { return $false }
        $receiptTimes = @($expectedReceipts | ForEach-Object { [DateTimeOffset]::Parse($_.OccurredAtUtc) })
        $candidateLatest = @($candidates | ForEach-Object { [DateTimeOffset]::Parse($_.ObservedAtUtc) } | Sort-Object -Descending | Select-Object -First 1)[0]
        $allObservationLatest = @(
            [DateTimeOffset]::Parse($os.ObservedAtUtc),
            $candidateLatest,
            [DateTimeOffset]::Parse($git.ObservedAtUtc),
            [DateTimeOffset]::Parse($behavior.ObservedAtUtc)
        ) | Sort-Object -Descending | Select-Object -First 1
        if ($receiptTimes[0] -lt [DateTimeOffset]::Parse($os.ObservedAtUtc) -or
            $receiptTimes[1] -lt $candidateLatest -or
            $receiptTimes[2] -lt $candidateLatest -or
            $receiptTimes[3] -lt $candidateLatest -or
            $receiptTimes[4] -lt [DateTimeOffset]::Parse($behavior.ObservedAtUtc) -or
            $receiptTimes[5] -lt [DateTimeOffset]::Parse($git.ObservedAtUtc) -or
            $receiptTimes[6] -lt $allObservationLatest -or
            $cleanupObservedAt -lt $receiptTimes[6] -or
            $receiptTimes[7] -lt $cleanupObservedAt) { return $false }
        if (-not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.EvidenceBindingToken) -or $Evidence.EvidenceBindingToken -cne (Get-CddsiVmCalibrationEvidenceBindingToken -Evidence $Evidence)) { return $false }

        $serialized = ConvertTo-CddsiJson -InputObject $Evidence
        if ($serialized -match '(?i)"(?:path|userName|username|rawRegistry|rawResponse|responseBody|registryValues|canFreezeP10B)"\s*:') { return $false }
        return (@(Find-CddsiPotentialSecrets -Content $serialized -Source '<vm-calibration-evidence>').Count -eq 0)
    }
    catch { return $false }
}

function Get-CddsiCasStoreAuthorityKeyFingerprint {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$StoreAuthorityPublicKey)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion   = $StoreAuthorityPublicKey.SchemaVersion
        ContractVersion = $StoreAuthorityPublicKey.ContractVersion
        Algorithm       = $StoreAuthorityPublicKey.Algorithm
        KeyId           = $StoreAuthorityPublicKey.KeyId
        ModulusBase64   = $StoreAuthorityPublicKey.ModulusBase64
        ExponentBase64  = $StoreAuthorityPublicKey.ExponentBase64
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiCasStoreAuthorityPublicKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$StoreAuthorityPublicKey)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $StoreAuthorityPublicKey -Expected @(
            'SchemaVersion', 'ContractVersion', 'Algorithm', 'KeyId',
            'ModulusBase64', 'ExponentBase64', 'FingerprintSha256'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $StoreAuthorityPublicKey.SchemaVersion) -or
            $StoreAuthorityPublicKey.ContractVersion -cne 'cddsi-cas-store-authority-public-key-v1' -or
            $StoreAuthorityPublicKey.Algorithm -cne 'RSA-SHA256-PKCS1-v1_5' -or
            -not (Test-CddsiCanonicalUuidValue -Value $StoreAuthorityPublicKey.KeyId) -or
            $StoreAuthorityPublicKey.FingerprintSha256 -isnot [string] -or
            $StoreAuthorityPublicKey.FingerprintSha256 -notmatch '^[a-f0-9]{64}$') { return $false }
        $modulus = [Convert]::FromBase64String($StoreAuthorityPublicKey.ModulusBase64)
        $exponent = [Convert]::FromBase64String($StoreAuthorityPublicKey.ExponentBase64)
        if ([Convert]::ToBase64String($modulus) -cne $StoreAuthorityPublicKey.ModulusBase64 -or
            [Convert]::ToBase64String($exponent) -cne $StoreAuthorityPublicKey.ExponentBase64 -or
            $modulus.Length -lt 256 -or $modulus.Length -gt 512 -or
            $exponent.Length -lt 3 -or $exponent.Length -gt 8 -or
            $modulus[0] -eq 0 -or $exponent[0] -eq 0 -or
            $StoreAuthorityPublicKey.FingerprintSha256 -cne
                (Get-CddsiCasStoreAuthorityKeyFingerprint -StoreAuthorityPublicKey $StoreAuthorityPublicKey)) { return $false }
        $rsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $parameters = [System.Security.Cryptography.RSAParameters]::new()
            $parameters.Modulus = $modulus
            $parameters.Exponent = $exponent
            $rsa.ImportParameters($parameters)
        }
        finally { if ($null -ne $rsa) { $rsa.Dispose() } }
        return $true
    }
    catch { return $false }
}

function Get-CddsiCasCommitReceiptSigningPayload {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$CommitReceipt)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion                      = $CommitReceipt.SchemaVersion
        ContractVersion                    = $CommitReceipt.ContractVersion
        Purpose                            = $CommitReceipt.Purpose
        Domain                             = $CommitReceipt.Domain
        SignatureAlgorithm                 = $CommitReceipt.SignatureAlgorithm
        StoreAuthorityKeyId                = $CommitReceipt.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $CommitReceipt.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId                    = $CommitReceipt.StoreInstanceId
        StoreEpoch                         = $CommitReceipt.StoreEpoch
        TransactionId                      = $CommitReceipt.TransactionId
        CommitId                           = $CommitReceipt.CommitId
        StateKeySha256                     = $CommitReceipt.StateKeySha256
        OldRevision                        = $CommitReceipt.OldRevision
        NewRevision                        = $CommitReceipt.NewRevision
        OldStateBindingToken               = $CommitReceipt.OldStateBindingToken
        NewStateBindingToken               = $CommitReceipt.NewStateBindingToken
        ProposalBindingToken               = $CommitReceipt.ProposalBindingToken
        ProposalNonce                      = $CommitReceipt.ProposalNonce
        SessionAnchorToken                 = $CommitReceipt.SessionAnchorToken
        SessionBindingToken                = $CommitReceipt.SessionBindingToken
        EvidenceBindingToken               = $CommitReceipt.EvidenceBindingToken
        ConsumptionId                      = $CommitReceipt.ConsumptionId
        FreezeId                           = $CommitReceipt.FreezeId
        FactsBindingToken                  = $CommitReceipt.FactsBindingToken
        CommittedAtUtc                     = $CommitReceipt.CommittedAtUtc
        ExpiresAtUtc                       = $CommitReceipt.ExpiresAtUtc
    }
    return ConvertTo-CddsiVmCalibrationCanonicalJson -Value $payload
}

function Get-CddsiCasCommitReceiptBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$CommitReceipt)

    $payload = [pscustomobject][ordered]@{
        SigningPayload  = Get-CddsiCasCommitReceiptSigningPayload -CommitReceipt $CommitReceipt
        SignatureBase64 = $CommitReceipt.SignatureBase64
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiCasCommitReceiptSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$CommitReceipt,
        [Parameter(Mandatory = $true)]$StoreAuthorityPublicKey
    )

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $CommitReceipt -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'Domain', 'SignatureAlgorithm',
            'StoreAuthorityKeyId', 'StoreAuthorityKeyFingerprintSha256', 'StoreInstanceId',
            'StoreEpoch', 'TransactionId', 'CommitId', 'StateKeySha256', 'OldRevision',
            'NewRevision', 'OldStateBindingToken', 'NewStateBindingToken',
            'ProposalBindingToken', 'ProposalNonce', 'SessionAnchorToken',
            'SessionBindingToken', 'EvidenceBindingToken', 'ConsumptionId', 'FreezeId',
            'FactsBindingToken', 'CommittedAtUtc', 'ExpiresAtUtc', 'SignatureBase64',
            'ReceiptBindingToken'
        )) -or -not (Test-CddsiCasStoreAuthorityPublicKey -StoreAuthorityPublicKey $StoreAuthorityPublicKey)) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $CommitReceipt.SchemaVersion) -or
            $CommitReceipt.ContractVersion -cne 'cddsi-cas-commit-receipt-v1' -or
            $CommitReceipt.SignatureAlgorithm -cne 'RSA-SHA256-PKCS1-v1_5' -or
            $CommitReceipt.StoreAuthorityKeyId -cne $StoreAuthorityPublicKey.KeyId -or
            $CommitReceipt.StoreAuthorityKeyFingerprintSha256 -cne $StoreAuthorityPublicKey.FingerprintSha256 -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitReceipt.StoreInstanceId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitReceipt.TransactionId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitReceipt.CommitId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitReceipt.ProposalNonce) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitReceipt.ConsumptionId) -or
            $CommitReceipt.StoreEpoch -isnot [int] -and $CommitReceipt.StoreEpoch -isnot [long]) { return $false }
        if (@(
            $CommitReceipt.StoreInstanceId, $CommitReceipt.TransactionId,
            $CommitReceipt.CommitId, $CommitReceipt.ProposalNonce,
            $CommitReceipt.ConsumptionId, $CommitReceipt.FreezeId
        ) | Where-Object { $null -ne $_ } | Group-Object | Where-Object { $_.Count -gt 1 }) { return $false }
        if ([long]$CommitReceipt.StoreEpoch -lt 1 -or
            ($CommitReceipt.OldRevision -isnot [int] -and $CommitReceipt.OldRevision -isnot [long]) -or
            ($CommitReceipt.NewRevision -isnot [int] -and $CommitReceipt.NewRevision -isnot [long]) -or
            [long]$CommitReceipt.OldRevision -lt 0 -or
            [long]$CommitReceipt.NewRevision -ne ([long]$CommitReceipt.OldRevision + 1)) { return $false }
        foreach ($name in @(
            'StoreAuthorityKeyFingerprintSha256', 'StateKeySha256', 'OldStateBindingToken',
            'NewStateBindingToken', 'ProposalBindingToken', 'SessionAnchorToken',
            'SessionBindingToken', 'EvidenceBindingToken', 'ReceiptBindingToken'
        )) {
            if ($CommitReceipt.$name -isnot [string] -or $CommitReceipt.$name -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (($CommitReceipt.Purpose -ceq 'P10A_CONSUMPTION_COMMIT' -and
                ($CommitReceipt.Domain -cne 'P10A_VM_CALIBRATION_CONSUMPTION' -or
                    $null -ne $CommitReceipt.FreezeId -or $null -ne $CommitReceipt.FactsBindingToken)) -or
            ($CommitReceipt.Purpose -ceq 'P10B_RELEASE_FACTS_FREEZE_COMMIT' -and
                ($CommitReceipt.Domain -cne 'P10B_RELEASE_FACTS_FREEZE' -or
                    -not (Test-CddsiCanonicalUuidValue -Value $CommitReceipt.FreezeId) -or
                    $CommitReceipt.FactsBindingToken -isnot [string] -or $CommitReceipt.FactsBindingToken -notmatch '^[a-f0-9]{64}$')) -or
            $CommitReceipt.Purpose -cnotin @('P10A_CONSUMPTION_COMMIT', 'P10B_RELEASE_FACTS_FREEZE_COMMIT')) { return $false }
        if (-not (Test-CddsiVmCalibrationTimestampValue -Value $CommitReceipt.CommittedAtUtc) -or
            -not (Test-CddsiVmCalibrationTimestampValue -Value $CommitReceipt.ExpiresAtUtc) -or
            [DateTimeOffset]::Parse($CommitReceipt.CommittedAtUtc) -ge [DateTimeOffset]::Parse($CommitReceipt.ExpiresAtUtc)) { return $false }
        $signature = [Convert]::FromBase64String($CommitReceipt.SignatureBase64)
        if ([Convert]::ToBase64String($signature) -cne $CommitReceipt.SignatureBase64 -or
            $signature.Length -lt 256 -or $signature.Length -gt 512 -or
            $CommitReceipt.ReceiptBindingToken -cne (Get-CddsiCasCommitReceiptBindingToken -CommitReceipt $CommitReceipt)) { return $false }
        $rsa = [System.Security.Cryptography.RSA]::Create()
        try {
            $parameters = [System.Security.Cryptography.RSAParameters]::new()
            $parameters.Modulus = [Convert]::FromBase64String($StoreAuthorityPublicKey.ModulusBase64)
            $parameters.Exponent = [Convert]::FromBase64String($StoreAuthorityPublicKey.ExponentBase64)
            $rsa.ImportParameters($parameters)
            $data = [Text.Encoding]::UTF8.GetBytes((Get-CddsiCasCommitReceiptSigningPayload -CommitReceipt $CommitReceipt))
            return $rsa.VerifyData($data, $signature, [Security.Cryptography.HashAlgorithmName]::SHA256, [Security.Cryptography.RSASignaturePadding]::Pkcs1)
        }
        finally { if ($null -ne $rsa) { $rsa.Dispose() } }
    }
    catch { return $false }
}

function Get-CddsiVmCalibrationConsumptionStateKey {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ConsumptionState)

    $payload = [pscustomobject][ordered]@{
        ContractVersion                    = 'cddsi-vm-calibration-consumption-state-key-v2'
        Purpose                            = $ConsumptionState.Purpose
        StoreAuthorityKeyId                = $ConsumptionState.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $ConsumptionState.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId                    = $ConsumptionState.StoreInstanceId
        StoreEpoch                         = $ConsumptionState.StoreEpoch
        SessionAnchorToken                 = $ConsumptionState.SessionAnchorToken
        SessionBindingToken                = $ConsumptionState.SessionBindingToken
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Get-CddsiVmCalibrationConsumptionBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$ConsumptionState)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion                      = $ConsumptionState.SchemaVersion
        ContractVersion                    = $ConsumptionState.ContractVersion
        Purpose                            = $ConsumptionState.Purpose
        StateKeySha256                     = $ConsumptionState.StateKeySha256
        State                              = $ConsumptionState.State
        StoreAuthorityKeyId                = $ConsumptionState.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $ConsumptionState.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId                    = $ConsumptionState.StoreInstanceId
        StoreEpoch                         = $ConsumptionState.StoreEpoch
        SessionAnchorToken                 = $ConsumptionState.SessionAnchorToken
        SessionBindingToken                = $ConsumptionState.SessionBindingToken
        EvidenceBindingToken               = $ConsumptionState.EvidenceBindingToken
        ConsumptionId                      = $ConsumptionState.ConsumptionId
        ConsumedAtUtc                      = $ConsumptionState.ConsumedAtUtc
        ExpiresAtUtc                       = $ConsumptionState.ExpiresAtUtc
        Revision                           = $ConsumptionState.Revision
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiVmCalibrationConsumptionState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$ConsumptionState)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $ConsumptionState -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'StateKeySha256', 'State',
            'StoreAuthorityKeyId', 'StoreAuthorityKeyFingerprintSha256',
            'StoreInstanceId', 'StoreEpoch',
            'SessionAnchorToken', 'SessionBindingToken', 'EvidenceBindingToken',
            'ConsumptionId', 'ConsumedAtUtc', 'ExpiresAtUtc', 'Revision',
            'StateBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $ConsumptionState.SchemaVersion) -or
            $ConsumptionState.ContractVersion -cne 'cddsi-vm-calibration-consumption-state-v2' -or
            $ConsumptionState.Purpose -cne 'P10A_CONSUMPTION_STATE' -or
            $ConsumptionState.State -cnotin @('AVAILABLE', 'CONSUMED')) { return $false }
        foreach ($name in @('StateKeySha256', 'StoreAuthorityKeyFingerprintSha256', 'SessionAnchorToken', 'SessionBindingToken', 'StateBindingToken')) {
            if ($ConsumptionState.$name -isnot [string] -or $ConsumptionState.$name -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (-not (Test-CddsiCanonicalUuidValue -Value $ConsumptionState.StoreAuthorityKeyId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $ConsumptionState.StoreInstanceId) -or
            ($ConsumptionState.StoreEpoch -isnot [int] -and $ConsumptionState.StoreEpoch -isnot [long]) -or
            [long]$ConsumptionState.StoreEpoch -lt 1) { return $false }
        if (-not (Test-CddsiVmCalibrationTimestampValue -Value $ConsumptionState.ExpiresAtUtc)) { return $false }
        if ($ConsumptionState.State -ceq 'AVAILABLE') {
            if ($null -ne $ConsumptionState.EvidenceBindingToken -or $null -ne $ConsumptionState.ConsumptionId -or
                $null -ne $ConsumptionState.ConsumedAtUtc -or $ConsumptionState.Revision -ne 0) { return $false }
        }
        else {
            if ($ConsumptionState.EvidenceBindingToken -isnot [string] -or $ConsumptionState.EvidenceBindingToken -notmatch '^[a-f0-9]{64}$' -or
                -not (Test-CddsiCanonicalUuidValue -Value $ConsumptionState.ConsumptionId) -or
                -not (Test-CddsiVmCalibrationTimestampValue -Value $ConsumptionState.ConsumedAtUtc) -or
                $ConsumptionState.Revision -ne 1 -or
                [DateTimeOffset]::Parse($ConsumptionState.ConsumedAtUtc) -ge [DateTimeOffset]::Parse($ConsumptionState.ExpiresAtUtc)) { return $false }
        }
        return ($ConsumptionState.StateKeySha256 -ceq (Get-CddsiVmCalibrationConsumptionStateKey -ConsumptionState $ConsumptionState) -and
            $ConsumptionState.StateBindingToken -ceq (Get-CddsiVmCalibrationConsumptionBindingToken -ConsumptionState $ConsumptionState))
    }
    catch { return $false }
}

function New-CddsiVmCalibrationConsumptionState {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)]$StoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$StoreInstanceId,
        [Parameter(Mandatory = $true)][long]$StoreEpoch,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    if (-not (Test-CddsiVmCalibrationSession -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds)) {
        throw 'A fresh externally anchored terminal session is required for calibration consumption.'
    }
    if (-not (Test-CddsiCasStoreAuthorityPublicKey -StoreAuthorityPublicKey $StoreAuthorityPublicKey) -or
        -not (Test-CddsiCanonicalUuidValue -Value $StoreInstanceId) -or $StoreEpoch -lt 1) {
        throw 'A valid and explicitly pinned CAS store authority is required for calibration consumption.'
    }
    $state = [pscustomobject][ordered]@{
        SchemaVersion                      = 1
        ContractVersion                    = 'cddsi-vm-calibration-consumption-state-v2'
        Purpose                            = 'P10A_CONSUMPTION_STATE'
        StateKeySha256                     = $null
        State                              = 'AVAILABLE'
        StoreAuthorityKeyId                = $StoreAuthorityPublicKey.KeyId
        StoreAuthorityKeyFingerprintSha256 = $StoreAuthorityPublicKey.FingerprintSha256
        StoreInstanceId                    = $StoreInstanceId
        StoreEpoch                         = $StoreEpoch
        SessionAnchorToken                 = $ExpectedSessionAnchorToken
        SessionBindingToken                = $ExpectedSession.SessionBindingToken
        EvidenceBindingToken               = $null
        ConsumptionId                      = $null
        ConsumedAtUtc                      = $null
        ExpiresAtUtc                       = $ExpectedSession.AuthorizationSession.ExpiresAtUtc
        Revision                           = 0
        StateBindingToken                  = $null
    }
    $state.StateKeySha256 = Get-CddsiVmCalibrationConsumptionStateKey -ConsumptionState $state
    $state.StateBindingToken = Get-CddsiVmCalibrationConsumptionBindingToken -ConsumptionState $state
    if (-not (Test-CddsiVmCalibrationConsumptionState -ConsumptionState $state)) { throw 'Calibration consumption state construction failed closed.' }
    return $state
}

function Get-CddsiVmCalibrationConsumptionProposalBindingToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$CommitProposal)

    $payload = [pscustomobject][ordered]@{
        SchemaVersion                      = $CommitProposal.SchemaVersion
        ContractVersion                    = $CommitProposal.ContractVersion
        Purpose                            = $CommitProposal.Purpose
        Domain                             = $CommitProposal.Domain
        StoreAuthorityKeyId                = $CommitProposal.StoreAuthorityKeyId
        StoreAuthorityKeyFingerprintSha256 = $CommitProposal.StoreAuthorityKeyFingerprintSha256
        StoreInstanceId                    = $CommitProposal.StoreInstanceId
        StoreEpoch                         = $CommitProposal.StoreEpoch
        TransactionId                      = $CommitProposal.TransactionId
        StateKeySha256                     = $CommitProposal.StateKeySha256
        OldRevision                        = $CommitProposal.OldRevision
        NewRevision                        = $CommitProposal.NewRevision
        OldStateBindingToken               = $CommitProposal.OldStateBindingToken
        NewStateBindingToken               = $CommitProposal.NewStateBindingToken
        ProposalNonce                      = $CommitProposal.ProposalNonce
        SessionAnchorToken                 = $CommitProposal.SessionAnchorToken
        SessionBindingToken                = $CommitProposal.SessionBindingToken
        EvidenceBindingToken               = $CommitProposal.EvidenceBindingToken
        ConsumptionId                      = $CommitProposal.ConsumptionId
        FreezeId                           = $CommitProposal.FreezeId
        FactsBindingToken                  = $CommitProposal.FactsBindingToken
        ProposedState                      = $CommitProposal.ProposedState
    }
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $payload
}

function Test-CddsiVmCalibrationConsumptionCommitProposal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$CommitProposal)

    try {
        if (-not (Test-CddsiExactPropertySet -InputObject $CommitProposal -Expected @(
            'SchemaVersion', 'ContractVersion', 'Purpose', 'Domain', 'StoreAuthorityKeyId',
            'StoreAuthorityKeyFingerprintSha256', 'StoreInstanceId', 'StoreEpoch',
            'TransactionId', 'StateKeySha256', 'OldRevision', 'NewRevision',
            'OldStateBindingToken', 'NewStateBindingToken', 'ProposalNonce',
            'SessionAnchorToken', 'SessionBindingToken', 'EvidenceBindingToken',
            'ConsumptionId', 'FreezeId', 'FactsBindingToken', 'ProposedState',
            'ProposalBindingToken'
        ))) { return $false }
        if (-not (Test-CddsiSchemaVersionOne -Value $CommitProposal.SchemaVersion) -or
            $CommitProposal.ContractVersion -cne 'cddsi-vm-calibration-consumption-commit-proposal-v1' -or
            $CommitProposal.Purpose -cne 'P10A_CONSUMPTION_COMMIT' -or
            $CommitProposal.Domain -cne 'P10A_VM_CALIBRATION_CONSUMPTION' -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.StoreAuthorityKeyId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.StoreInstanceId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.TransactionId) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.ProposalNonce) -or
            -not (Test-CddsiCanonicalUuidValue -Value $CommitProposal.ConsumptionId) -or
            $null -ne $CommitProposal.FreezeId -or $null -ne $CommitProposal.FactsBindingToken -or
            ($CommitProposal.StoreEpoch -isnot [int] -and $CommitProposal.StoreEpoch -isnot [long]) -or
            ($CommitProposal.OldRevision -isnot [int] -and $CommitProposal.OldRevision -isnot [long]) -or
            ($CommitProposal.NewRevision -isnot [int] -and $CommitProposal.NewRevision -isnot [long]) -or
            [long]$CommitProposal.StoreEpoch -lt 1 -or [long]$CommitProposal.OldRevision -ne 0 -or
            [long]$CommitProposal.NewRevision -ne 1) { return $false }
        foreach ($name in @(
            'StoreAuthorityKeyFingerprintSha256', 'StateKeySha256', 'OldStateBindingToken',
            'NewStateBindingToken', 'SessionAnchorToken', 'SessionBindingToken',
            'EvidenceBindingToken', 'ProposalBindingToken'
        )) {
            if ($CommitProposal.$name -isnot [string] -or $CommitProposal.$name -notmatch '^[a-f0-9]{64}$') { return $false }
        }
        if (-not (Test-CddsiVmCalibrationConsumptionState -ConsumptionState $CommitProposal.ProposedState) -or
            $CommitProposal.ProposedState.State -cne 'CONSUMED' -or
            $CommitProposal.ProposedState.StateKeySha256 -cne $CommitProposal.StateKeySha256 -or
            $CommitProposal.ProposedState.StateBindingToken -cne $CommitProposal.NewStateBindingToken -or
            $CommitProposal.ProposedState.Revision -ne $CommitProposal.NewRevision -or
            $CommitProposal.ProposedState.StoreAuthorityKeyId -cne $CommitProposal.StoreAuthorityKeyId -or
            $CommitProposal.ProposedState.StoreAuthorityKeyFingerprintSha256 -cne $CommitProposal.StoreAuthorityKeyFingerprintSha256 -or
            $CommitProposal.ProposedState.StoreInstanceId -cne $CommitProposal.StoreInstanceId -or
            [long]$CommitProposal.ProposedState.StoreEpoch -ne [long]$CommitProposal.StoreEpoch -or
            $CommitProposal.ProposedState.SessionAnchorToken -cne $CommitProposal.SessionAnchorToken -or
            $CommitProposal.ProposedState.SessionBindingToken -cne $CommitProposal.SessionBindingToken -or
            $CommitProposal.ProposedState.EvidenceBindingToken -cne $CommitProposal.EvidenceBindingToken -or
            $CommitProposal.ProposedState.ConsumptionId -cne $CommitProposal.ConsumptionId -or
            $CommitProposal.ProposalBindingToken -cne
                (Get-CddsiVmCalibrationConsumptionProposalBindingToken -CommitProposal $CommitProposal)) { return $false }
        return $true
    }
    catch { return $false }
}

function Test-CddsiCommittedVmCalibrationConsumptionReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ConsumptionState,
        [Parameter(Mandatory = $true)]$CommitReceipt,
        [Parameter(Mandatory = $true)]$StoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedEvidenceBindingToken,
        [Parameter(Mandatory = $true)][string]$ExpectedConsumptionId,
        [Parameter(Mandatory = $true)][string]$ExpectedTransactionId,
        [Parameter(Mandatory = $true)][string]$ExpectedProposalNonce,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc
    )

    try {
        if (-not (Test-CddsiVmCalibrationConsumptionState -ConsumptionState $ConsumptionState) -or
            $ConsumptionState.State -cne 'CONSUMED' -or
            $ConsumptionState.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
            $ConsumptionState.SessionBindingToken -cne $ExpectedSessionBindingToken -or
            $ConsumptionState.EvidenceBindingToken -cne $ExpectedEvidenceBindingToken -or
            $ConsumptionState.ConsumptionId -cne $ExpectedConsumptionId -or
            -not (Test-CddsiCasCommitReceiptSignature -CommitReceipt $CommitReceipt -StoreAuthorityPublicKey $StoreAuthorityPublicKey) -or
            -not (Test-CddsiVmCalibrationTimestampValue -Value $ValidationTimeUtc)) { return $false }
        $availableState = [pscustomobject][ordered]@{
            SchemaVersion = $ConsumptionState.SchemaVersion; ContractVersion = $ConsumptionState.ContractVersion
            Purpose = $ConsumptionState.Purpose; StateKeySha256 = $ConsumptionState.StateKeySha256; State = 'AVAILABLE'
            StoreAuthorityKeyId = $ConsumptionState.StoreAuthorityKeyId
            StoreAuthorityKeyFingerprintSha256 = $ConsumptionState.StoreAuthorityKeyFingerprintSha256
            StoreInstanceId = $ConsumptionState.StoreInstanceId; StoreEpoch = $ConsumptionState.StoreEpoch
            SessionAnchorToken = $ConsumptionState.SessionAnchorToken; SessionBindingToken = $ConsumptionState.SessionBindingToken
            EvidenceBindingToken = $null; ConsumptionId = $null; ConsumedAtUtc = $null
            ExpiresAtUtc = $ConsumptionState.ExpiresAtUtc; Revision = 0; StateBindingToken = $null
        }
        $availableState.StateBindingToken = Get-CddsiVmCalibrationConsumptionBindingToken -ConsumptionState $availableState
        $proposal = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-calibration-consumption-commit-proposal-v1'
            Purpose = 'P10A_CONSUMPTION_COMMIT'; Domain = 'P10A_VM_CALIBRATION_CONSUMPTION'
            StoreAuthorityKeyId = $ConsumptionState.StoreAuthorityKeyId
            StoreAuthorityKeyFingerprintSha256 = $ConsumptionState.StoreAuthorityKeyFingerprintSha256
            StoreInstanceId = $ConsumptionState.StoreInstanceId; StoreEpoch = $ConsumptionState.StoreEpoch
            TransactionId = $ExpectedTransactionId; StateKeySha256 = $ConsumptionState.StateKeySha256
            OldRevision = 0; NewRevision = 1; OldStateBindingToken = $availableState.StateBindingToken
            NewStateBindingToken = $ConsumptionState.StateBindingToken; ProposalNonce = $ExpectedProposalNonce
            SessionAnchorToken = $ExpectedSessionAnchorToken; SessionBindingToken = $ExpectedSessionBindingToken
            EvidenceBindingToken = $ExpectedEvidenceBindingToken; ConsumptionId = $ExpectedConsumptionId
            FreezeId = $null; FactsBindingToken = $null; ProposedState = $ConsumptionState; ProposalBindingToken = $null
        }
        $proposal.ProposalBindingToken = Get-CddsiVmCalibrationConsumptionProposalBindingToken -CommitProposal $proposal
        if (-not (Test-CddsiVmCalibrationConsumptionCommitProposal -CommitProposal $proposal) -or
            $CommitReceipt.Purpose -cne $proposal.Purpose -or $CommitReceipt.Domain -cne $proposal.Domain -or
            $CommitReceipt.StoreInstanceId -cne $proposal.StoreInstanceId -or [long]$CommitReceipt.StoreEpoch -ne [long]$proposal.StoreEpoch -or
            $CommitReceipt.TransactionId -cne $ExpectedTransactionId -or $CommitReceipt.StateKeySha256 -cne $proposal.StateKeySha256 -or
            [long]$CommitReceipt.OldRevision -ne 0 -or [long]$CommitReceipt.NewRevision -ne 1 -or
            $CommitReceipt.OldStateBindingToken -cne $proposal.OldStateBindingToken -or
            $CommitReceipt.NewStateBindingToken -cne $proposal.NewStateBindingToken -or
            $CommitReceipt.ProposalBindingToken -cne $proposal.ProposalBindingToken -or
            $CommitReceipt.ProposalNonce -cne $ExpectedProposalNonce -or
            $CommitReceipt.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
            $CommitReceipt.SessionBindingToken -cne $ExpectedSessionBindingToken -or
            $CommitReceipt.EvidenceBindingToken -cne $ExpectedEvidenceBindingToken -or
            $CommitReceipt.ConsumptionId -cne $ExpectedConsumptionId -or
            $CommitReceipt.ExpiresAtUtc -cne $ConsumptionState.ExpiresAtUtc -or
            [DateTimeOffset]::Parse($CommitReceipt.CommittedAtUtc) -lt [DateTimeOffset]::Parse($ConsumptionState.ConsumedAtUtc)) { return $false }
        $validationTime = [DateTimeOffset]::Parse($ValidationTimeUtc)
        return ($validationTime -ge [DateTimeOffset]::Parse($CommitReceipt.CommittedAtUtc) -and
            $validationTime -lt [DateTimeOffset]::Parse($ConsumptionState.ExpiresAtUtc))
    }
    catch { return $false }
}

function Resolve-CddsiVmCalibrationConsumption {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)]$ExpectedSession,
        [Parameter(Mandatory = $true)][string]$ExpectedSessionAnchorToken,
        [Parameter(Mandatory = $true)]$ConsumptionState,
        [Parameter(Mandatory = $true)]$StoreAuthorityPublicKey,
        [Parameter(Mandatory = $true)][string]$ConsumptionId,
        [Parameter(Mandatory = $true)][string]$TransactionId,
        [Parameter(Mandatory = $true)][string]$ProposalNonce,
        [Parameter(Mandatory = $true)][AllowNull()]$CommittedConsumptionReceipt,
        [Parameter(Mandatory = $true)][int]$ExpectedRevision,
        [Parameter(Mandatory = $true)][string]$ValidationTimeUtc,
        [ValidateRange(1, 604800)][int]$MaximumAgeSeconds = 86400
    )

    $reasonCodes = [System.Collections.Generic.List[string]]::new()
    $valid = Test-CddsiVmCalibrationEvidence -Evidence $Evidence -ExpectedSession $ExpectedSession -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ValidationTimeUtc $ValidationTimeUtc -MaximumAgeSeconds $MaximumAgeSeconds
    if (-not $valid) { $reasonCodes.Add('EVIDENCE_SESSION_INVALID') }
    $stateValid = Test-CddsiVmCalibrationConsumptionState -ConsumptionState $ConsumptionState
    if (-not $stateValid) { $reasonCodes.Add('CONSUMPTION_STATE_INVALID') }
    elseif ($ConsumptionState.SessionAnchorToken -cne $ExpectedSessionAnchorToken -or
        $ConsumptionState.SessionBindingToken -cne $ExpectedSession.SessionBindingToken) { $reasonCodes.Add('CONSUMPTION_SESSION_MISMATCH') }
    elseif (-not (Test-CddsiCasStoreAuthorityPublicKey -StoreAuthorityPublicKey $StoreAuthorityPublicKey) -or
        $ConsumptionState.StoreAuthorityKeyId -cne $StoreAuthorityPublicKey.KeyId -or
        $ConsumptionState.StoreAuthorityKeyFingerprintSha256 -cne $StoreAuthorityPublicKey.FingerprintSha256) {
        $reasonCodes.Add('CONSUMPTION_STORE_AUTHORITY_MISMATCH')
    }
    if (-not (Test-CddsiCanonicalUuidValue -Value $ConsumptionId)) { $reasonCodes.Add('CONSUMPTION_ID_INVALID') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $TransactionId) -or $TransactionId -ceq $ConsumptionId) { $reasonCodes.Add('CONSUMPTION_TRANSACTION_ID_INVALID') }
    if (-not (Test-CddsiCanonicalUuidValue -Value $ProposalNonce) -or @($ConsumptionId, $TransactionId) -ccontains $ProposalNonce) { $reasonCodes.Add('CONSUMPTION_PROPOSAL_NONCE_INVALID') }
    elseif (@(
        $ExpectedSession.OperationGrant.RunId,
        $ExpectedSession.OperationGrant.GrantId,
        $ExpectedSession.OperationGrant.Nonce,
        $ExpectedSession.AuthorizationSession.ClaimId,
        @($ExpectedSession.OperationGrant.ConfirmationBindings | ForEach-Object { $_.ConfirmationId }),
        @($ExpectedSession.OperationUseStates | ForEach-Object { $_.OperationUseId; $_.IdempotencyKey })
    ) -ccontains $ConsumptionId) { $reasonCodes.Add('CONSUMPTION_ID_COLLISION') }
    if ($ExpectedRevision -lt 0) { $reasonCodes.Add('EXPECTED_REVISION_INVALID') }
    $complete = ($valid -and $Evidence.Readiness.Status -ceq 'COMPLETE' -and
        @($Evidence.MsixCandidates).Count -eq 2 -and
        @($Evidence.MsixCandidates | Where-Object { $_.Status -ceq 'OBSERVED' }).Count -eq 2 -and
        $Evidence.Selection.Status -ceq 'SELECTED' -and $Evidence.Cleanup.Status -ceq 'COMPLETE')
    if ($valid -and -not $complete) { $reasonCodes.Add('CALIBRATION_NOT_COMPLETE') }

    $proposedState = $null
    $commitProposal = $null
    $idempotentReplay = $false
    $requiresCas = $false
    $canFreeze = $false
    if ($reasonCodes.Count -eq 0 -and $stateValid -and $complete) {
        if ($ConsumptionState.State -ceq 'CONSUMED') {
            $sameReceipt = (
                $ConsumptionState.EvidenceBindingToken -ceq $Evidence.EvidenceBindingToken -and
                $ConsumptionState.ConsumptionId -ceq $ConsumptionId
            )
            if ($sameReceipt -and [long]$ConsumptionState.Revision -eq [long]$ExpectedRevision -and
                $null -ne $CommittedConsumptionReceipt -and
                (Test-CddsiCommittedVmCalibrationConsumptionReceipt -ConsumptionState $ConsumptionState `
                    -CommitReceipt $CommittedConsumptionReceipt -StoreAuthorityPublicKey $StoreAuthorityPublicKey `
                    -ExpectedSessionAnchorToken $ExpectedSessionAnchorToken -ExpectedSessionBindingToken $ExpectedSession.SessionBindingToken `
                    -ExpectedEvidenceBindingToken $Evidence.EvidenceBindingToken -ExpectedConsumptionId $ConsumptionId `
                    -ExpectedTransactionId $TransactionId -ExpectedProposalNonce $ProposalNonce `
                    -ValidationTimeUtc $ValidationTimeUtc)) {
                $proposedState = $ConsumptionState
                $idempotentReplay = $true
                $canFreeze = $true
            }
            elseif ($null -eq $CommittedConsumptionReceipt) { $reasonCodes.Add('CONSUMPTION_SIGNED_RECEIPT_REQUIRED') }
            elseif ([long]$ConsumptionState.Revision -ne [long]$ExpectedRevision) { $reasonCodes.Add('CONSUMPTION_CONCURRENCY_CONFLICT') }
            elseif ($ConsumptionState.ConsumptionId -ceq $ConsumptionId) { $reasonCodes.Add('CONSUMPTION_COMMIT_RECEIPT_INVALID') }
            else { $reasonCodes.Add('CALIBRATION_EVIDENCE_REPLAY') }
        }
        elseif ($ExpectedRevision -ne $ConsumptionState.Revision) {
            $reasonCodes.Add('CONSUMPTION_CONCURRENCY_CONFLICT')
        }
        elseif ([DateTimeOffset]::Parse($ValidationTimeUtc) -ge [DateTimeOffset]::Parse($ConsumptionState.ExpiresAtUtc)) {
            $reasonCodes.Add('CONSUMPTION_STATE_EXPIRED')
        }
        else {
            if ($null -ne $CommittedConsumptionReceipt) {
                $reasonCodes.Add('CONSUMPTION_CURRENT_STATE_NOT_COMMITTED')
            }
            $proposedState = [pscustomobject][ordered]@{
                SchemaVersion = $ConsumptionState.SchemaVersion; ContractVersion = $ConsumptionState.ContractVersion
                Purpose = $ConsumptionState.Purpose; StateKeySha256 = $ConsumptionState.StateKeySha256; State = 'CONSUMED'
                StoreAuthorityKeyId = $ConsumptionState.StoreAuthorityKeyId
                StoreAuthorityKeyFingerprintSha256 = $ConsumptionState.StoreAuthorityKeyFingerprintSha256
                StoreInstanceId = $ConsumptionState.StoreInstanceId; StoreEpoch = $ConsumptionState.StoreEpoch
                SessionAnchorToken = $ConsumptionState.SessionAnchorToken; SessionBindingToken = $ConsumptionState.SessionBindingToken
                EvidenceBindingToken = $Evidence.EvidenceBindingToken; ConsumptionId = $ConsumptionId
                ConsumedAtUtc = $ValidationTimeUtc; ExpiresAtUtc = $ConsumptionState.ExpiresAtUtc
                Revision = $ConsumptionState.Revision + 1; StateBindingToken = $null
            }
            $proposedState.StateBindingToken = Get-CddsiVmCalibrationConsumptionBindingToken -ConsumptionState $proposedState
            if (-not (Test-CddsiVmCalibrationConsumptionState -ConsumptionState $proposedState)) {
                $reasonCodes.Add('CONSUMPTION_PROPOSAL_INVALID')
                $proposedState = $null
            }
            elseif ($reasonCodes.Count -eq 0) {
                $commitProposal = [pscustomobject][ordered]@{
                    SchemaVersion = 1; ContractVersion = 'cddsi-vm-calibration-consumption-commit-proposal-v1'
                    Purpose = 'P10A_CONSUMPTION_COMMIT'; Domain = 'P10A_VM_CALIBRATION_CONSUMPTION'
                    StoreAuthorityKeyId = $ConsumptionState.StoreAuthorityKeyId
                    StoreAuthorityKeyFingerprintSha256 = $ConsumptionState.StoreAuthorityKeyFingerprintSha256
                    StoreInstanceId = $ConsumptionState.StoreInstanceId; StoreEpoch = $ConsumptionState.StoreEpoch
                    TransactionId = $TransactionId; StateKeySha256 = $ConsumptionState.StateKeySha256
                    OldRevision = $ConsumptionState.Revision; NewRevision = $proposedState.Revision
                    OldStateBindingToken = $ConsumptionState.StateBindingToken
                    NewStateBindingToken = $proposedState.StateBindingToken; ProposalNonce = $ProposalNonce
                    SessionAnchorToken = $ExpectedSessionAnchorToken; SessionBindingToken = $ExpectedSession.SessionBindingToken
                    EvidenceBindingToken = $Evidence.EvidenceBindingToken; ConsumptionId = $ConsumptionId
                    FreezeId = $null; FactsBindingToken = $null; ProposedState = $proposedState; ProposalBindingToken = $null
                }
                $commitProposal.ProposalBindingToken = Get-CddsiVmCalibrationConsumptionProposalBindingToken -CommitProposal $commitProposal
                if (-not (Test-CddsiVmCalibrationConsumptionCommitProposal -CommitProposal $commitProposal)) {
                    $reasonCodes.Add('CONSUMPTION_COMMIT_PROPOSAL_INVALID')
                    $commitProposal = $null
                    $proposedState = $null
                }
                else { $requiresCas = $true }
            }
        }
    }

    $readyToCommit = ($null -ne $proposedState -and $requiresCas -and $reasonCodes.Count -eq 0)
    $readyToFreeze = ($canFreeze -and $idempotentReplay -and $reasonCodes.Count -eq 0)

    return [pscustomobject][ordered]@{
        SchemaVersion            = 1
        ContractVersion          = 'cddsi-vm-calibration-consumption-v2'
        Status                   = if ($readyToFreeze) { 'READY_TO_FREEZE' } elseif ($readyToCommit) { 'READY_TO_COMMIT' } else { 'BLOCKED' }
        CanFreezeP10B            = $readyToFreeze
        RequiresAtomicCompareAndSwap = $readyToCommit
        IdempotentReplay         = $idempotentReplay
        StateKeySha256           = if ($stateValid) { $ConsumptionState.StateKeySha256 } else { $null }
        PreviousRevision         = if ($stateValid) { $ConsumptionState.Revision } else { $null }
        NextRevision             = if ($null -ne $proposedState) { $proposedState.Revision } else { $null }
        ProposedConsumptionState = $proposedState
        CommitProposal            = $commitProposal
        CommittedReceiptVerified  = $readyToFreeze
        IntegrityTokensAreAuthorization = $false
        EvidenceBindingToken     = if ($valid) { $Evidence.EvidenceBindingToken } else { $null }
        SessionBindingToken      = if ($valid) { $Evidence.SessionBinding.SessionBindingToken } else { $null }
        SelectedFlavor           = if ($readyToFreeze) { $Evidence.Selection.Flavor } else { $null }
        SelectedScope            = if ($readyToFreeze) { $Evidence.Selection.Scope } else { $null }
        ReasonCodes              = if ($readyToFreeze) { @('P10B_FREEZE_READY') } elseif ($readyToCommit) { @('CONSUMPTION_COMMIT_REQUIRED') } else { @($reasonCodes | Select-Object -Unique) }
        ComprehensiveAcceptance  = $false
    }
}
