# deepseek-api.ps1 - Credential input and API validation contracts.
# No function in this scaffold performs a DeepSeek network request.

function Read-CddsiDeepSeekApiKeySecure {
    [CmdletBinding()]
    param(
        [switch]$NonInteractive
    )

    $data = [pscustomobject][ordered]@{
        returnType       = 'SecureStringOrCredentialHandle'
        acceptsPlainTextArgument = $false
        loggable         = $false
        stateSerializable = $false
        implemented      = $false
    }
    return New-CddsiOperationResult -Operation 'ReadDeepSeekApiKeySecure' -Status 'not_implemented' -Mode 'TestSafe' -MessageSafe '安全输入接口已定义，但不会读取输入。' -Data $data
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
        [AllowNull()][Security.SecureString]$ApiKey,
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$AcknowledgeRealChanges
    )

    if ($Mode -eq 'Live') {
        Assert-CddsiMutationAllowed -Operation 'ValidateDeepSeekApi' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
    }
    return New-CddsiOperationResult -Operation 'ValidateDeepSeekApi' -Status 'planned' -Success $true -Mode $Mode -MessageSafe '不会发送 DeepSeek API 请求。' -Data ([pscustomobject]@{ CredentialAccepted = ($null -ne $ApiKey); RequestSent = $false })
}
