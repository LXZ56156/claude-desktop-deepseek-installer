function New-CddsiRealtimeRelayForegroundControlValidationResultInternal {
    param(
        [Parameter(Mandatory = $true)][ValidateSet('OK', 'BLOCKED')][string]$Status,
        [Parameter(Mandatory = $true)][string]$Code,
        [AllowNull()][string]$BodySha256,
        [AllowNull()][psobject]$Body
    )

    return [pscustomobject][ordered]@{
        Schema     = 'CDDsi_FOREGROUND_CONTROL_VALIDATION_V1'
        Status     = $Status
        Code       = $Code
        BodySha256 = $BodySha256
        Body       = $Body
    }
}

function Get-CddsiRealtimeRelayForegroundControlSha256Internal {
    param(
        [Parameter(Mandatory = $true)][byte[]]$Bytes
    )

    $sha256 = [System.Security.Cryptography.SHA256]::Create()
    try {
        $digest = $sha256.ComputeHash($Bytes)
        return (($digest | ForEach-Object { $_.ToString('x2') }) -join '')
    }
    finally {
        $sha256.Dispose()
    }
}

function New-CddsiRealtimeRelayForegroundControlInvalidInternal {
    param(
        [AllowNull()][string]$BodySha256
    )

    return New-CddsiRealtimeRelayForegroundControlValidationResultInternal `
        -Status 'BLOCKED' `
        -Code 'FOREGROUND_CONTROL_INVALID' `
        -BodySha256 $BodySha256 `
        -Body $null
}

function Test-CddsiRealtimeRelayForegroundControlStringInternal {
    param(
        [AllowNull()]$Value
    )

    return $null -ne $Value -and $Value -is [string]
}

function Test-CddsiRealtimeRelayForegroundControlEvidencePathInternal {
    param(
        [Parameter(Mandatory = $true)][string]$Path
    )

    if ($Path.Length -lt 1 -or $Path.Length -gt 240 -or
        $Path.StartsWith('/', [StringComparison]::Ordinal) -or
        $Path.EndsWith('/', [StringComparison]::Ordinal) -or
        $Path.Contains('//') -or $Path.Contains('\') -or $Path.Contains(':') -or
        $Path -cnotmatch '^[A-Za-z0-9][A-Za-z0-9._/-]*\z') {
        return $false
    }

    foreach ($segment in $Path.Split('/')) {
        if ($segment.Length -eq 0 -or $segment -ceq '.' -or $segment -ceq '..') {
            return $false
        }
    }
    return $true
}

function ConvertFrom-CddsiRealtimeRelayForegroundControlBody {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][byte[]]$BodyBytes,
        [Parameter(Mandatory = $true)][string]$ExpectedLane,
        [Parameter(Mandatory = $true)][datetimeoffset]$NowUtc
    )

    $bodySha256 = $null
    if ($BodyBytes.Length -lt 1 -or $BodyBytes.Length -gt 4096 -or
        @('host-to-vm', 'vm-to-host') -cnotcontains $ExpectedLane) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }
    if (($BodyBytes.Length -ge 3 -and
            $BodyBytes[0] -eq 0xef -and $BodyBytes[1] -eq 0xbb -and $BodyBytes[2] -eq 0xbf) -or
        @($BodyBytes | Where-Object { $_ -eq 0 }).Count -gt 0) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    try {
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $BodyJson = $utf8.GetString($BodyBytes)
    }
    catch {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }
    $bodySha256 = Get-CddsiRealtimeRelayForegroundControlSha256Internal -Bytes $BodyBytes
    if ($BodyJson -cmatch '[\u0000-\u001f]') {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $canonicalPattern = '^\{"Schema":"(?<Schema>[^"]*)","Lane":"(?<Lane>[^"]*)",' +
        '"MessageId":"(?<MessageId>[^"]*)","CycleId":"(?<CycleId>[^"]*)",' +
        '"Kind":"(?<Kind>[^"]*)","SenderRole":"(?<SenderRole>[^"]*)",' +
        '"ProductCommit":"(?<ProductCommit>[^"]*)","TestProfile":"(?<TestProfile>[^"]*)",' +
        '"ResultStatus":"(?<ResultStatus>[^"]*)","ResultCode":"(?<ResultCode>[^"]*)",' +
        '"EvidencePath":(?<EvidencePath>null|"[^"]*"),' +
        '"EvidenceSha256":(?<EvidenceSha256>null|"[^"]*"),' +
        '"CreatedAtUtc":"(?<CreatedAtUtc>[^"]*)",' +
        '"ExpiresAtUtc":"(?<ExpiresAtUtc>[^"]*)"\}\z'
    $match = [regex]::Match(
        $BodyJson,
        $canonicalPattern,
        [Text.RegularExpressions.RegexOptions]::CultureInvariant
    )
    if (-not $match.Success) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $expectedProperties = @(
        'Schema'
        'Lane'
        'MessageId'
        'CycleId'
        'Kind'
        'SenderRole'
        'ProductCommit'
        'TestProfile'
        'ResultStatus'
        'ResultCode'
        'EvidencePath'
        'EvidenceSha256'
        'CreatedAtUtc'
        'ExpiresAtUtc'
    )
    $evidencePathValue = $match.Groups['EvidencePath'].Value
    $evidenceShaValue = $match.Groups['EvidenceSha256'].Value
    $parsedEvidencePath = $null
    $parsedEvidenceSha256 = $null
    if ($evidencePathValue -cne 'null') {
        $parsedEvidencePath = $evidencePathValue.Substring(1, $evidencePathValue.Length - 2)
    }
    if ($evidenceShaValue -cne 'null') {
        $parsedEvidenceSha256 = $evidenceShaValue.Substring(1, $evidenceShaValue.Length - 2)
    }
    $body = [pscustomobject][ordered]@{
        Schema         = $match.Groups['Schema'].Value
        Lane           = $match.Groups['Lane'].Value
        MessageId      = $match.Groups['MessageId'].Value
        CycleId        = $match.Groups['CycleId'].Value
        Kind           = $match.Groups['Kind'].Value
        SenderRole     = $match.Groups['SenderRole'].Value
        ProductCommit  = $match.Groups['ProductCommit'].Value
        TestProfile    = $match.Groups['TestProfile'].Value
        ResultStatus   = $match.Groups['ResultStatus'].Value
        ResultCode     = $match.Groups['ResultCode'].Value
        EvidencePath   = $parsedEvidencePath
        EvidenceSha256 = $parsedEvidenceSha256
        CreatedAtUtc   = $match.Groups['CreatedAtUtc'].Value
        ExpiresAtUtc   = $match.Groups['ExpiresAtUtc'].Value
    }
    $properties = @($body.PSObject.Properties)
    if ($properties.Count -ne $expectedProperties.Count -or
        (@($properties.Name) -join "`n") -cne ($expectedProperties -join "`n") -or
        @($properties | Where-Object { $_.MemberType -cne 'NoteProperty' }).Count -gt 0) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    foreach ($name in @(
        'Schema', 'Lane', 'MessageId', 'CycleId', 'Kind', 'SenderRole',
        'ProductCommit', 'TestProfile', 'ResultStatus', 'ResultCode',
        'CreatedAtUtc', 'ExpiresAtUtc'
    )) {
        if (-not (Test-CddsiRealtimeRelayForegroundControlStringInternal -Value $body.$name)) {
            return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
        }
    }

    if ($body.Schema -cne 'CDDsi_FOREGROUND_CONTROL_V1' -or
        $body.Lane -cne $ExpectedLane -or
        @('host-to-vm', 'vm-to-host') -cnotcontains $body.Lane) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }
    $expectedRole = if ($body.Lane -ceq 'host-to-vm') { 'HostCoordinator' } else { 'VmTester' }
    if ($body.SenderRole -cne $expectedRole) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $uuidV4Pattern = '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z'
    if ($body.MessageId -cnotmatch $uuidV4Pattern -or $body.CycleId -cnotmatch $uuidV4Pattern -or
        $body.ProductCommit -cnotmatch '^[0-9a-f]{40}\z') {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    if (@(
        'SESSION_START', 'SESSION_READY', 'TEST_REQUEST', 'TEST_RESULT',
        'FIX_READY', 'HOST_ACK', 'STOP'
    ) -cnotcontains $body.Kind -or
        @(
        'FOREGROUND_CANARY', 'FOCUSED_REGRESSION', 'QUALITY', 'RELEASE_DRYRUN'
    ) -cnotcontains $body.TestProfile -or
        @('NONE', 'READY', 'PASSED', 'FAILED', 'BLOCKED') -cnotcontains $body.ResultStatus -or
        $body.ResultCode.Length -lt 1 -or $body.ResultCode.Length -gt 64 -or
        $body.ResultCode -cnotmatch '^(?:NONE|[A-Z][A-Z0-9]*(?:_[A-Z0-9]+)*)\z') {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $kindAndResultValid = $false
    if ($body.Lane -ceq 'host-to-vm') {
        $kindAndResultValid = @(
            'SESSION_START', 'TEST_REQUEST', 'FIX_READY', 'HOST_ACK', 'STOP'
        ) -ccontains $body.Kind -and
            $body.ResultStatus -ceq 'NONE' -and $body.ResultCode -ceq 'NONE'
    }
    elseif ($body.Kind -ceq 'SESSION_READY') {
        $kindAndResultValid = $body.ResultStatus -ceq 'READY' -and
            $body.ResultCode -ceq 'NONE'
    }
    elseif ($body.Kind -ceq 'TEST_RESULT') {
        $kindAndResultValid = @('PASSED', 'FAILED', 'BLOCKED') -ccontains $body.ResultStatus
        if ($kindAndResultValid) {
            if ($body.ResultStatus -ceq 'PASSED') {
                $kindAndResultValid = $body.ResultCode -ceq 'NONE'
            }
            else {
                $kindAndResultValid = $body.ResultCode -cne 'NONE'
            }
        }
    }
    if (-not $kindAndResultValid) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $evidencePathIsNull = $null -eq $body.EvidencePath
    $evidenceShaIsNull = $null -eq $body.EvidenceSha256
    if ($evidencePathIsNull -ne $evidenceShaIsNull) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }
    if (-not $evidencePathIsNull) {
        if (-not (Test-CddsiRealtimeRelayForegroundControlStringInternal -Value $body.EvidencePath) -or
            -not (Test-CddsiRealtimeRelayForegroundControlStringInternal -Value $body.EvidenceSha256) -or
            -not (Test-CddsiRealtimeRelayForegroundControlEvidencePathInternal -Path $body.EvidencePath) -or
            $body.EvidenceSha256 -cnotmatch '^[0-9a-f]{64}\z') {
            return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
        }
    }

    if ($body.CreatedAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z' -or
        $body.ExpiresAtUtc -cnotmatch '^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z\z') {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }
    [datetimeoffset]$createdAt = [datetimeoffset]::MinValue
    [datetimeoffset]$expiresAt = [datetimeoffset]::MinValue
    $timestampStyle = [Globalization.DateTimeStyles]::AssumeUniversal -bor
        [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [datetimeoffset]::TryParseExact(
            $body.CreatedAtUtc,
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            [Globalization.CultureInfo]::InvariantCulture,
            $timestampStyle,
            [ref]$createdAt
        ) -or
        -not [datetimeoffset]::TryParseExact(
            $body.ExpiresAtUtc,
            "yyyy-MM-dd'T'HH:mm:ss'Z'",
            [Globalization.CultureInfo]::InvariantCulture,
            $timestampStyle,
            [ref]$expiresAt
        )) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $now = $NowUtc.ToUniversalTime()
    if ($expiresAt -le $createdAt -or
        ($expiresAt - $createdAt).TotalSeconds -gt 600 -or
        $expiresAt -le $now -or
        $createdAt -gt $now.AddSeconds(120)) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    $evidencePathJson = if ($evidencePathIsNull) { 'null' } else { '"' + $body.EvidencePath + '"' }
    $evidenceShaJson = if ($evidenceShaIsNull) { 'null' } else { '"' + $body.EvidenceSha256 + '"' }
    $canonical = '{"Schema":"' + $body.Schema +
        '","Lane":"' + $body.Lane +
        '","MessageId":"' + $body.MessageId +
        '","CycleId":"' + $body.CycleId +
        '","Kind":"' + $body.Kind +
        '","SenderRole":"' + $body.SenderRole +
        '","ProductCommit":"' + $body.ProductCommit +
        '","TestProfile":"' + $body.TestProfile +
        '","ResultStatus":"' + $body.ResultStatus +
        '","ResultCode":"' + $body.ResultCode +
        '","EvidencePath":' + $evidencePathJson +
        ',"EvidenceSha256":' + $evidenceShaJson +
        ',"CreatedAtUtc":"' + $body.CreatedAtUtc +
        '","ExpiresAtUtc":"' + $body.ExpiresAtUtc + '"}'
    if ($BodyJson -cne $canonical) {
        return New-CddsiRealtimeRelayForegroundControlInvalidInternal -BodySha256 $bodySha256
    }

    return New-CddsiRealtimeRelayForegroundControlValidationResultInternal `
        -Status 'OK' `
        -Code 'FOREGROUND_CONTROL_VALID' `
        -BodySha256 $bodySha256 `
        -Body $body
}
