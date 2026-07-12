BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'DeepSeek API contracts' {
    It 'classifies stable HTTP error families' {
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 400).Class | Should -Be 'InvalidInput'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 401).Class | Should -Be 'Unauthorized'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 402).Class | Should -Be 'Billing'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 422).Class | Should -Be 'Validation'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 429).Retryable | Should -BeTrue
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 503).Class | Should -Be 'ServerError'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 599).Class | Should -Be 'ServerError'
        (ConvertTo-CddsiDeepSeekApiErrorClass -HttpStatusCode 408).Class | Should -Be 'Timeout'
    }

    It 'classifies transport errors without technical secret text' {
        $result = ConvertTo-CddsiDeepSeekApiErrorClass -ExceptionKind Timeout
        $result.Class | Should -Be 'Timeout'
        $result.Retryable | Should -BeTrue
        $result.PSObject.Properties.Name | Should -Not -Contain 'RawResponse'
        (ConvertTo-CddsiDeepSeekApiErrorClass -ExceptionKind timeout).Class | Should -BeExactly 'Timeout'
    }

    It 'defines secure input without reading the console' {
        $result = Read-CddsiDeepSeekApiKeySecure -NonInteractive
        $result.Status | Should -Be 'not_implemented'
        $result.Data.acceptsPlainTextArgument | Should -BeFalse
        $result.Data.stateSerializable | Should -BeFalse
    }

    It 'never sends an API request in TestSafe' {
        $result = Invoke-CddsiDeepSeekApiValidation -Mode TestSafe
        $result.Status | Should -Be 'planned'
        $result.Data.RequestSent | Should -BeFalse
    }
}
