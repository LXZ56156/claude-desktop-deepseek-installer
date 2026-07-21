#requires -Version 7.5
[CmdletBinding()]
param([string]$PackagePath, [switch]$AcknowledgeRelayOnlyLive)
Set-StrictMode -Version Latest
$script:CddsiVmSmokeMaximumSequence = 9007199254740991L
$script:CddsiVmSmokeEmptySha256 = 'e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855'
function Get-CddsiVmSmokeSha256Internal {
    param([Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text)
    $bytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($Text)
    $algorithm = [Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($algorithm.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $algorithm.Dispose()
        [Array]::Clear($bytes, 0, $bytes.Length)
    }
}
function Test-CddsiVmSmokeOwnerOnlyAclDescriptorInternal {
    param(
        [Parameter(Mandatory = $true)][Security.AccessControl.FileSecurity]$Security,
        [Parameter(Mandatory = $true)][Security.Principal.SecurityIdentifier]$CurrentUser
    )
    try {
        if ($Security.GetOwner([Security.Principal.SecurityIdentifier]).Value -cne
            $CurrentUser.Value) { return $false }
        $rules = @($Security.GetAccessRules(
                $true,
                $true,
                [Security.Principal.SecurityIdentifier]
            ))
        if ($rules.Count -ne 1) { return $false }
        $rule = $rules[0]
        return $rule.IdentityReference.Value -ceq $CurrentUser.Value -and
            $rule.AccessControlType -eq [Security.AccessControl.AccessControlType]::Allow -and
            $rule.FileSystemRights -eq [Security.AccessControl.FileSystemRights]::FullControl
    }
    catch { return $false }
}
function Test-CddsiVmSmokePackageOwnerOnlyAclInternal {
    param([Parameter(Mandatory = $true)][IO.FileInfo]$Item)
    try {
        if ([Environment]::OSVersion.Platform -ne [PlatformID]::Win32NT) { return $false }
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().User
        if ($null -eq $currentUser) { return $false }
        $sections = [Security.AccessControl.AccessControlSections]::Owner -bor
            [Security.AccessControl.AccessControlSections]::Access
        $security = [IO.FileSystemAclExtensions]::GetAccessControl($Item, $sections)
        return Test-CddsiVmSmokeOwnerOnlyAclDescriptorInternal `
            -Security $security -CurrentUser $currentUser
    }
    catch { return $false }
}
function ConvertFrom-CddsiVmSmokePackageInternal {
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    $secretBytes = $null
    try {
        $text = [Text.UTF8Encoding]::new($false, $true).GetString($Bytes)
        $value = ConvertFrom-Json -InputObject $text -DateKind String -Depth 4 -ErrorAction Stop
        $expected = @(
            'ClientId', 'Endpoint', 'Environment', 'ExpectedHostMessageId',
            'ExpectedHostSequence', 'ExpiryMinutes', 'KeyId', 'ReplyCommit',
            'ReplyPayloadSha256', 'ReplyRef', 'ReplyRepositoryId', 'Schema',
            'SecretBase64Url', 'VmToHostPreviousSha256', 'VmToHostSequence'
        )
        if ((@($value.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join "`n") -cne
            ($expected -join "`n")) {
            throw 'VM_RELAY_PACKAGE_SCHEMA_INVALID'
        }
        $stringFields = @('ClientId', 'Endpoint', 'Environment', 'ExpectedHostMessageId', 'KeyId', 'ReplyCommit',
            'ReplyPayloadSha256', 'ReplyRef', 'ReplyRepositoryId', 'Schema', 'SecretBase64Url')
        if (@($stringFields | Where-Object { $value.$_ -isnot [string] }).Count -ne 0 -or
            $value.ExpectedHostSequence -isnot [long] -or $value.VmToHostSequence -isnot [long] -or
            $value.ExpiryMinutes -isnot [long] -or ($null -ne $value.VmToHostPreviousSha256 -and
                $value.VmToHostPreviousSha256 -isnot [string])) { throw 'VM_RELAY_PACKAGE_SCHEMA_INVALID' }
        try { $endpoint = [uri][string]$value.Endpoint } catch { throw 'VM_RELAY_PACKAGE_ENDPOINT_INVALID' }
        if ($value.Schema -cne 'cddsi-relay-vm-handoff-v1' -or
            $value.Environment -cne 'production-v1' -or $value.ClientId -cne 'vm-tester-v1' -or
            [string]$value.KeyId -cnotmatch '^[a-z0-9](?:[a-z0-9._-]{0,62}[a-z0-9])?$' -or
            -not $endpoint.IsAbsoluteUri -or $endpoint.Scheme -cne 'https' -or
            -not $endpoint.IsDefaultPort -or $endpoint.Port -ne 443 -or
            $endpoint.UserInfo.Length -ne 0 -or $endpoint.AbsolutePath -cne '/' -or
            $endpoint.Query.Length -ne 0 -or $endpoint.Fragment.Length -ne 0 -or
            $endpoint.Host -cnotmatch '^[a-z0-9-]+\.[a-z0-9-]+\.workers\.dev$') {
            throw 'VM_RELAY_PACKAGE_ENDPOINT_INVALID'
        }
        $hostSequence = [long]$value.ExpectedHostSequence
        $replySequence = [long]$value.VmToHostSequence
        $expiryMinutes = [int]$value.ExpiryMinutes
        $previous = $value.VmToHostPreviousSha256
        if ([string]$value.ExpectedHostMessageId -cnotmatch
            '^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$' -or
            $hostSequence -lt 1 -or $hostSequence -gt $script:CddsiVmSmokeMaximumSequence -or
            $replySequence -lt 1 -or $replySequence -gt $script:CddsiVmSmokeMaximumSequence -or
            [string]$value.ReplyPayloadSha256 -cnotmatch '^[0-9a-f]{64}$' -or
            $value.ReplyRepositoryId -cne '1301870545' -or
            $value.ReplyRef -cne 'refs/heads/main' -or
            [string]$value.ReplyCommit -cnotmatch '^[0-9a-f]{40}$' -or
            $expiryMinutes -lt 1 -or $expiryMinutes -gt 10 -or
            ($replySequence -eq 1 -and $null -ne $previous) -or
            ($replySequence -gt 1 -and [string]$previous -cnotmatch '^[0-9a-f]{64}$')) {
            throw 'VM_RELAY_PACKAGE_SCHEMA_INVALID'
        }
        $secretText = [string]$value.SecretBase64Url
        if ($secretText -cnotmatch '^[A-Za-z0-9_-]{43}$') {
            throw 'VM_RELAY_PACKAGE_SECRET_INVALID'
        }
        try {
            $secretBytes = [Convert]::FromBase64String(
                $secretText.Replace('-', '+').Replace('_', '/') + '='
            )
        }
        catch { throw 'VM_RELAY_PACKAGE_SECRET_INVALID' }
        if ($secretBytes.Length -ne 32) { throw 'VM_RELAY_PACKAGE_SECRET_INVALID' }
        $value.SecretBase64Url = $null
        return [pscustomobject][ordered]@{
            Endpoint = $endpoint.GetLeftPart([UriPartial]::Authority)
            Environment = [string]$value.Environment; ClientId = [string]$value.ClientId
            KeyId = [string]$value.KeyId; SecretBytes = $secretBytes
            ExpectedHostMessageId = [string]$value.ExpectedHostMessageId
            ExpectedHostSequence = $hostSequence; VmToHostSequence = $replySequence
            VmToHostPreviousSha256 = $previous
            ReplyPayloadSha256 = [string]$value.ReplyPayloadSha256
            ReplyRepositoryId = [string]$value.ReplyRepositoryId
            ReplyRef = [string]$value.ReplyRef; ReplyCommit = [string]$value.ReplyCommit
            ExpiryMinutes = $expiryMinutes
        }
    }
    catch {
        if ($null -ne $secretBytes) { [Array]::Clear($secretBytes, 0, $secretBytes.Length) }
        if ($_.Exception.Message -cmatch '^VM_RELAY_[A-Z0-9_]+$') { throw }
        throw 'VM_RELAY_PACKAGE_SCHEMA_INVALID'
    }
    finally {
        $text = $null
        $secretText = $null
    }
}
function New-CddsiVmSmokeHeadersInternal {
    param(
        [Parameter(Mandatory = $true)]$Package, [Parameter(Mandatory = $true)][string]$Method,
        [Parameter(Mandatory = $true)][string]$Target,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Body,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc)
    $nonceBytes = [byte[]]::new(32)
    try {
        [Security.Cryptography.RandomNumberGenerator]::Fill($nonceBytes)
        $nonce = [Convert]::ToBase64String($nonceBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
    }
    finally { [Array]::Clear($nonceBytes, 0, $nonceBytes.Length) }
    $timestamp = $NowUtc.ToUniversalTime().ToString(
        'yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture
    )
    $bodySha256 = if ($Body.Length -eq 0) { $script:CddsiVmSmokeEmptySha256 } else {
        Get-CddsiVmSmokeSha256Internal -Text $Body
    }
    $canonical = @(
        'CDDsi-HMAC-SHA256-v2', 'cddsi-realtime-relay-v1', $Package.Environment,
        $Package.KeyId, $Package.ClientId, $Method, $Target, $timestamp, $nonce, $bodySha256
    ) -join "`n"
    $hmac = [Security.Cryptography.HMACSHA256]::new($Package.SecretBytes)
    try {
        $canonicalBytes = [Text.UTF8Encoding]::new($false, $true).GetBytes($canonical)
        try {
            $signature = ([BitConverter]::ToString($hmac.ComputeHash($canonicalBytes))).Replace('-', '').ToLowerInvariant()
        }
        finally { [Array]::Clear($canonicalBytes, 0, $canonicalBytes.Length) }
    }
    finally { $hmac.Dispose() }
    return [ordered]@{
        'x-cddsi-audience' = 'cddsi-realtime-relay-v1'
        'x-cddsi-environment' = $Package.Environment; 'x-cddsi-key-id' = $Package.KeyId
        'x-cddsi-client-id' = $Package.ClientId; 'x-cddsi-timestamp' = $timestamp
        'x-cddsi-nonce' = $nonce; 'x-cddsi-body-sha256' = $bodySha256
        'x-cddsi-signature' = $signature
    }
}
function Invoke-CddsiVmSmokeHttpInternal {
    param([Parameter(Mandatory = $true)]$Request, [AllowNull()][scriptblock]$HttpHandler,
        [AllowNull()]$HttpClient)
    if ($null -ne $HttpHandler) {
        $response = @(& $HttpHandler $Request)
        if ($response.Count -ne 1 -or $response[0].StatusCode -isnot [int] -or
            $response[0].ContentType -cne 'application/json' -or
            $response[0].Body -isnot [string]) {
            throw 'VM_RELAY_HTTP_HANDLER_INVALID'
        }
        return $response[0]
    }
    $message = [Net.Http.HttpRequestMessage]::new(
        [Net.Http.HttpMethod]::new($Request.Method), [uri]$Request.Uri
    )
    $response = $null
    try {
        foreach ($name in $Request.Headers.Keys) {
            [void]$message.Headers.TryAddWithoutValidation($name, [string]$Request.Headers[$name])
        }
        if ($Request.Method -ceq 'POST') {
            $message.Content = [Net.Http.StringContent]::new(
                $Request.Body, [Text.UTF8Encoding]::new($false), 'application/json'
            )
        }
        $response = $HttpClient.SendAsync($message).GetAwaiter().GetResult()
        $body = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult()
        if ([Text.Encoding]::UTF8.GetByteCount($body) -gt 16384) {
            throw 'VM_RELAY_HTTP_RESPONSE_TOO_LARGE'
        }
        return [pscustomobject][ordered]@{
            StatusCode = [int]$response.StatusCode
            ContentType = [string]$response.Content.Headers.ContentType.MediaType
            Body = $body
        }
    }
    catch {
        if ($_.Exception.Message -cmatch '^VM_RELAY_[A-Z0-9_]+$') { throw }
        throw 'VM_RELAY_HTTP_REQUEST_FAILED'
    }
    finally {
        if ($null -ne $response) { $response.Dispose() }
        $message.Dispose()
    }
}
function Get-CddsiVmSmokeHostMessageInternal {
    param([Parameter(Mandatory = $true)]$Response, [Parameter(Mandatory = $true)]$Package,
        [Parameter(Mandatory = $true)][DateTimeOffset]$NowUtc)
    if ($Response.Schema -cne 'cddsi-relay-response-v1' -or $Response.Status -cne 'OK' -or
        $Response.Code -cne 'MESSAGES' -or $Response.Lane -cne 'host-to-vm' -or
        [long]$Response.After -ne ($Package.ExpectedHostSequence - 1)) {
        throw 'VM_RELAY_HOST_MESSAGE_RESPONSE_INVALID'
    }
    $entries = @($Response.Messages | Where-Object {
            $_.Notification.MessageId -ceq $Package.ExpectedHostMessageId -and
            [long]$_.Notification.Sequence -eq $Package.ExpectedHostSequence
        })
    if ($entries.Count -ne 1) { throw 'VM_RELAY_EXPECTED_HOST_MESSAGE_NOT_FOUND' }
    $entry = $entries[0]
    $message = $entry.Notification
    $expectedFields = @(
        'Commit', 'CreatedAt', 'Expiry', 'Lane', 'MessageId', 'PayloadSha256',
        'PreviousSha256', 'Ref', 'RepositoryId', 'Schema', 'SenderRole', 'Sequence'
    )
    if ((@($message.PSObject.Properties.Name | Sort-Object -CaseSensitive) -join "`n") -cne
        ($expectedFields -join "`n") -or
        $message.Schema -cne 'cddsi-relay-notification-v1' -or
        $message.Lane -cne 'host-to-vm' -or $message.SenderRole -cne 'HostCoordinator' -or
        $message.RepositoryId -cne '1301870499' -or $message.Ref -cne 'refs/heads/main' -or
        [string]$message.PayloadSha256 -cnotmatch '^[0-9a-f]{64}$' -or
        [string]$message.Commit -cnotmatch '^[0-9a-f]{40}$' -or
        ([long]$message.Sequence -eq 1 -and $null -ne $message.PreviousSha256) -or
        ([long]$message.Sequence -gt 1 -and
            [string]$message.PreviousSha256 -cnotmatch '^[0-9a-f]{64}$') -or
        [string]$entry.MessageSha256 -cnotmatch '^[0-9a-f]{64}$') {
        throw 'VM_RELAY_HOST_MESSAGE_INVALID'
    }
    $created = [DateTimeOffset]::MinValue
    $expiry = [DateTimeOffset]::MinValue
    $style = [Globalization.DateTimeStyles]::AssumeUniversal -bor
        [Globalization.DateTimeStyles]::AdjustToUniversal
    if (-not [DateTimeOffset]::TryParseExact(
            [string]$message.CreatedAt, 'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$created
        ) -or -not [DateTimeOffset]::TryParseExact(
            [string]$message.Expiry, 'yyyy-MM-ddTHH:mm:ssZ',
            [Globalization.CultureInfo]::InvariantCulture, $style, [ref]$expiry
        ) -or $expiry -le $NowUtc -or $expiry -le $created -or
        ($expiry - $created).TotalMinutes -gt 10) {
        throw 'VM_RELAY_HOST_MESSAGE_EXPIRED'
    }
    $canonical = ConvertTo-Json -Compress -Depth 3 -InputObject ([ordered]@{
            Commit = $message.Commit; CreatedAt = $message.CreatedAt; Expiry = $message.Expiry
            Lane = $message.Lane; MessageId = $message.MessageId
            PayloadSha256 = $message.PayloadSha256; PreviousSha256 = $message.PreviousSha256
            Ref = $message.Ref; RepositoryId = $message.RepositoryId; Schema = $message.Schema
            SenderRole = $message.SenderRole; Sequence = [long]$message.Sequence
        })
    if ((Get-CddsiVmSmokeSha256Internal -Text $canonical) -cne $entry.MessageSha256) {
        throw 'VM_RELAY_HOST_MESSAGE_HASH_MISMATCH'
    }
    return $message
}
function Invoke-CddsiRelayVmSmoke {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PackagePath,
        [switch]$AcknowledgeRelayOnlyLive, [AllowNull()][scriptblock]$HttpHandler,
        [DateTimeOffset]$NowUtc = [DateTimeOffset]::UtcNow)
    if (-not $AcknowledgeRelayOnlyLive) {
        return [pscustomobject][ordered]@{
            Schema = 'VM_RELAY_SMOKE_V1'; Status = 'PLANNED'; Code = 'ACKNOWLEDGEMENT_REQUIRED'
            Mode = 'Plan'; PackageDeleted = $false; NetworkRequestCount = 0
        }
    }
        $packageBytes = $null
        $package = $null
    $client = $null
    $clientHandler = $null
    $packageDeleted = $false
        $requestCount = 0; $stage = 'PACKAGE'
    try {
        try { $fullPath = [IO.Path]::GetFullPath($PackagePath) } catch { throw 'VM_RELAY_PACKAGE_PATH_INVALID' }
        if (-not [IO.File]::Exists($fullPath)) { throw 'VM_RELAY_PACKAGE_PATH_INVALID' }
        $attributes = [IO.File]::GetAttributes($fullPath)
        if (($attributes -band [IO.FileAttributes]::Directory) -ne 0 -or
            ($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
            throw 'VM_RELAY_PACKAGE_PATH_INVALID'
        }
        if (-not (Test-CddsiVmSmokePackageOwnerOnlyAclInternal -Item ([IO.FileInfo]::new($fullPath)))) {
            throw 'VM_RELAY_PACKAGE_ACL_INVALID'
        }
        $packageBytes = [IO.File]::ReadAllBytes($fullPath)
        if ($packageBytes.Length -lt 2 -or $packageBytes.Length -gt 4096) {
            throw 'VM_RELAY_PACKAGE_SIZE_INVALID'
        }
        try { [IO.File]::Delete($fullPath); $packageDeleted = $true } catch {
            throw 'VM_RELAY_PACKAGE_DELETE_FAILED'
        }
        $package = ConvertFrom-CddsiVmSmokePackageInternal -Bytes $packageBytes
        [Array]::Clear($packageBytes, 0, $packageBytes.Length)
        $packageBytes = $null
        if ($null -eq $HttpHandler) {
            $clientHandler = [Net.Http.HttpClientHandler]::new()
            $clientHandler.AllowAutoRedirect = $false
            $client = [Net.Http.HttpClient]::new($clientHandler, $false)
            $client.Timeout = [TimeSpan]::FromSeconds(20)
        }
        $stage = 'HEALTH'
        $healthRequest = [pscustomobject]@{
            Method = 'GET'; Uri = $package.Endpoint + '/v1/health'; CanonicalTarget = '/v1/health'
            Headers = [ordered]@{}; Body = ''
        }
        $requestCount++
        $healthResponse = Invoke-CddsiVmSmokeHttpInternal $healthRequest $HttpHandler $client
        try { $health = ConvertFrom-Json $healthResponse.Body -DateKind String -Depth 4 -ErrorAction Stop }
        catch { throw 'VM_RELAY_RESPONSE_JSON_INVALID' }
        if ($healthResponse.StatusCode -ne 200 -or $healthResponse.ContentType -cne 'application/json' -or
            $health.Schema -cne 'cddsi-relay-health-v1' -or $health.Status -cne 'OK' -or
            $health.Version -cne 'v1') { throw 'VM_RELAY_HEALTH_FAILED' }
        $stage = 'READ'
        $readTarget = '/v1/messages/host-to-vm?after=' + ($package.ExpectedHostSequence - 1)
        $readRequest = [pscustomobject]@{
            Method = 'GET'; Uri = $package.Endpoint + $readTarget; CanonicalTarget = $readTarget
            Headers = New-CddsiVmSmokeHeadersInternal $package 'GET' $readTarget '' $NowUtc
            Body = ''
        }
        $requestCount++
        $readResponse = Invoke-CddsiVmSmokeHttpInternal $readRequest $HttpHandler $client
        if ($readResponse.StatusCode -ne 200 -or $readResponse.ContentType -cne 'application/json') {
            throw 'VM_RELAY_HOST_MESSAGE_READ_FAILED'
        }
        try { $read = ConvertFrom-Json $readResponse.Body -DateKind String -Depth 8 -ErrorAction Stop }
        catch { throw 'VM_RELAY_RESPONSE_JSON_INVALID' }
        $hostMessage = Get-CddsiVmSmokeHostMessageInternal $read $package $NowUtc
        $stage = 'ACK'
        $ackBody = ConvertTo-Json -Compress -InputObject ([ordered]@{
                AckStatus = 'CONSUMED'
                AckedAt = $NowUtc.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
                Lane = 'host-to-vm'; MessageId = $hostMessage.MessageId
                PayloadSha256 = $hostMessage.PayloadSha256; Schema = 'cddsi-relay-ack-v1'
                SenderRole = 'VmTester'; Sequence = [long]$hostMessage.Sequence
            })
        $ackRequest = [pscustomobject]@{
            Method = 'POST'; Uri = $package.Endpoint + '/v1/ack'; CanonicalTarget = '/v1/ack'
            Headers = New-CddsiVmSmokeHeadersInternal $package 'POST' '/v1/ack' $ackBody $NowUtc
            Body = $ackBody
        }
        $requestCount++
        $ackResponse = Invoke-CddsiVmSmokeHttpInternal $ackRequest $HttpHandler $client
        try { $ack = ConvertFrom-Json $ackResponse.Body -DateKind String -Depth 4 -ErrorAction Stop }
        catch { throw 'VM_RELAY_RESPONSE_JSON_INVALID' }
        if ($ackResponse.StatusCode -ne 200 -or $ackResponse.ContentType -cne 'application/json' -or
            $ack.Schema -cne 'cddsi-relay-response-v1' -or $ack.Status -cne 'OK' -or
            @('ACKED', 'ACK_IDEMPOTENT') -cnotcontains [string]$ack.Code -or
            $ack.Lane -cne 'host-to-vm' -or $ack.MessageId -cne $hostMessage.MessageId -or
            [long]$ack.Sequence -ne [long]$hostMessage.Sequence) { throw 'VM_RELAY_ACK_FAILED' }
        $stage = 'PUBLISH'
        $replyId = [guid]::NewGuid().ToString('D').ToLowerInvariant()
        $created = $NowUtc.ToUniversalTime()
        $replyBody = ConvertTo-Json -Compress -InputObject ([ordered]@{
                Commit = $package.ReplyCommit
                CreatedAt = $created.ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
                Expiry = $created.AddMinutes($package.ExpiryMinutes).ToString('yyyy-MM-ddTHH:mm:ssZ', [Globalization.CultureInfo]::InvariantCulture)
                Lane = 'vm-to-host'; MessageId = $replyId
                PayloadSha256 = $package.ReplyPayloadSha256
                PreviousSha256 = $package.VmToHostPreviousSha256
                Ref = $package.ReplyRef; RepositoryId = $package.ReplyRepositoryId
                Schema = 'cddsi-relay-notification-v1'; SenderRole = 'VmTester'
                Sequence = [long]$package.VmToHostSequence
            })
        $replySha256 = Get-CddsiVmSmokeSha256Internal $replyBody
        $publishTarget = '/v1/publish/vm-to-host'
        $publishRequest = [pscustomobject]@{
            Method = 'POST'; Uri = $package.Endpoint + $publishTarget; CanonicalTarget = $publishTarget
            Headers = New-CddsiVmSmokeHeadersInternal $package 'POST' $publishTarget $replyBody $NowUtc
            Body = $replyBody
        }
        $requestCount++
        $publishResponse = Invoke-CddsiVmSmokeHttpInternal $publishRequest $HttpHandler $client
        try { $published = ConvertFrom-Json $publishResponse.Body -DateKind String -Depth 4 -ErrorAction Stop }
        catch { throw 'VM_RELAY_RESPONSE_JSON_INVALID' }
        if ($publishResponse.StatusCode -ne 201 -or $publishResponse.ContentType -cne 'application/json' -or
            $published.Schema -cne 'cddsi-relay-response-v1' -or $published.Status -cne 'OK' -or
            $published.Code -cne 'PUBLISHED' -or $published.Lane -cne 'vm-to-host' -or
            $published.MessageId -cne $replyId -or
            [long]$published.Sequence -ne $package.VmToHostSequence -or
            $published.MessageSha256 -cne $replySha256) { throw 'VM_RELAY_PUBLISH_FAILED' }
        return [pscustomobject][ordered]@{
            Schema = 'VM_RELAY_SMOKE_REPORT_V1'
            HostMessageId = [string]$hostMessage.MessageId
            HostSequence = [long]$hostMessage.Sequence
            VmMessageId = $replyId
            VmSequence = [long]$package.VmToHostSequence
            VmPayloadSha256 = [string]$package.ReplyPayloadSha256
            VmMessageSha256 = [string]$published.MessageSha256
        }
    }
    catch {
        $code = [string]$_.Exception.Message
        if ($code -cnotmatch '^VM_RELAY_[A-Z0-9_]+$') { $code = 'VM_RELAY_' + $stage + '_FAILED' }
        return [pscustomobject][ordered]@{
            Schema = 'VM_RELAY_SMOKE_V1'; Status = 'FAILED'; Code = $code
            Mode = 'RelayOnlyLive'; PackageDeleted = $packageDeleted
            NetworkRequestCount = $requestCount
        }
    }
    finally {
        if ($null -ne $packageBytes) { [Array]::Clear($packageBytes, 0, $packageBytes.Length) }
        if ($null -ne $package -and $null -ne $package.SecretBytes) {
            [Array]::Clear($package.SecretBytes, 0, $package.SecretBytes.Length)
            $package.SecretBytes = $null
        }
        if ($null -ne $client) { $client.Dispose() }
        if ($null -ne $clientHandler) { $clientHandler.Dispose() }
    }
}
if ($MyInvocation.InvocationName -cne '.') {
    if ([string]::IsNullOrWhiteSpace($PackagePath)) { throw 'PackagePath is required.' }
    Invoke-CddsiRelayVmSmoke -PackagePath $PackagePath `
        -AcknowledgeRelayOnlyLive:$AcknowledgeRelayOnlyLive |
        ConvertTo-Json -Compress -Depth 4
}
