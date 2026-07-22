function global:New-CddsiForegroundControlTestBody {
    param(
        [string]$Lane = 'host-to-vm',
        [string]$MessageId = '123e4567-e89b-42d3-a456-426614174000',
        [string]$CycleId = '223e4567-e89b-42d3-b456-426614174001',
        [string]$Kind = 'SESSION_START',
        [string]$SenderRole = 'HostCoordinator',
        [string]$ProductCommit = '0123456789abcdef0123456789abcdef01234567',
        [string]$TestProfile = 'FOREGROUND_CANARY',
        [string]$ResultStatus = 'NONE',
        [string]$ResultCode = 'NONE',
        [AllowNull()][object]$EvidencePath = $null,
        [AllowNull()][object]$EvidenceSha256 = $null,
        [string]$CreatedAtUtc = '2026-07-22T00:00:00Z',
        [string]$ExpiresAtUtc = '2026-07-22T00:05:00Z'
    )

    $pathJson = if ($null -eq $EvidencePath) { 'null' } else { '"' + $EvidencePath + '"' }
    $shaJson = if ($null -eq $EvidenceSha256) { 'null' } else { '"' + $EvidenceSha256 + '"' }
    return '{"Schema":"CDDsi_FOREGROUND_CONTROL_V1","Lane":"' + $Lane +
        '","MessageId":"' + $MessageId +
        '","CycleId":"' + $CycleId +
        '","Kind":"' + $Kind +
        '","SenderRole":"' + $SenderRole +
        '","ProductCommit":"' + $ProductCommit +
        '","TestProfile":"' + $TestProfile +
        '","ResultStatus":"' + $ResultStatus +
        '","ResultCode":"' + $ResultCode +
        '","EvidencePath":' + $pathJson +
        ',"EvidenceSha256":' + $shaJson +
        ',"CreatedAtUtc":"' + $CreatedAtUtc +
        '","ExpiresAtUtc":"' + $ExpiresAtUtc + '"}'
}

function global:ConvertTo-CddsiForegroundControlTestBytes {
    param(
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$Text
    )

    return [Text.UTF8Encoding]::new($false, $true).GetBytes($Text)
}

BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    $script:ControlPath = Join-Path $script:RepoRoot 'operator\realtime-relay\foreground-control.ps1'
    . $script:ControlPath

    $script:NowUtc = [datetimeoffset]'2026-07-22T00:01:00Z'
}

Describe 'foreground control body pure parser and validator' {
    It 'accepts the exact canonical host-to-VM body and returns only parsed data' {
        $json = New-CddsiForegroundControlTestBody
        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'host-to-vm' `
            -NowUtc $script:NowUtc

        $result.Schema | Should -BeExactly 'CDDsi_FOREGROUND_CONTROL_VALIDATION_V1'
        $result.Status | Should -BeExactly 'OK'
        $result.Code | Should -BeExactly 'FOREGROUND_CONTROL_VALID'
        $result.BodySha256 | Should -Match '^[0-9a-f]{64}$'
        $result.Body.Schema | Should -BeExactly 'CDDsi_FOREGROUND_CONTROL_V1'
        $result.Body.Lane | Should -BeExactly 'host-to-vm'
        $result.Body.SenderRole | Should -BeExactly 'HostCoordinator'
        $result.Body.EvidencePath | Should -BeNullOrEmpty
        @($result.PSObject.Properties.Name) | Should -Be @(
            'Schema', 'Status', 'Code', 'BodySha256', 'Body'
        )
    }

    It 'accepts the opposite VM-to-host role and a paired safe evidence pointer' {
        $json = New-CddsiForegroundControlTestBody `
            -Lane 'vm-to-host' `
            -Kind 'TEST_RESULT' `
            -SenderRole 'VmTester' `
            -ResultStatus 'FAILED' `
            -ResultCode 'FOCUSED_TEST_FAILED' `
            -EvidencePath 'evidence/cycle-01/result.json' `
            -EvidenceSha256 ('b' * 64)

        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'vm-to-host' `
            -NowUtc $script:NowUtc

        $result.Status | Should -BeExactly 'OK'
        $result.Body.SenderRole | Should -BeExactly 'VmTester'
        $result.Body.EvidencePath | Should -BeExactly 'evidence/cycle-01/result.json'
        $result.Body.EvidenceSha256 | Should -BeExactly ('b' * 64)
    }

    It 'accepts the two fixed VM success forms' -TestCases @(
        @{
            Kind = 'SESSION_READY'
            Status = 'READY'
        }
        @{
            Kind = 'TEST_RESULT'
            Status = 'PASSED'
        }
    ) {
        param($Kind, $Status)

        $json = New-CddsiForegroundControlTestBody `
            -Lane 'vm-to-host' -Kind $Kind -SenderRole 'VmTester' -ResultStatus $Status
        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'vm-to-host' -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'OK'
        $result.Body.ResultCode | Should -BeExactly 'NONE'
    }

    It 'returns a deterministic SHA-256 over the exact canonical body bytes' {
        $json = New-CddsiForegroundControlTestBody
        $first = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
        $second = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc

        $sha = [Security.Cryptography.SHA256]::Create()
        try {
            $expected = (($sha.ComputeHash([Text.UTF8Encoding]::new($false, $true).GetBytes($json)) |
                    ForEach-Object { $_.ToString('x2') }) -join '')
        }
        finally {
            $sha.Dispose()
        }
        $first.BodySha256 | Should -BeExactly $expected
        $second.BodySha256 | Should -BeExactly $expected
    }

    It 'exposes only the raw byte body contract plus fixed lane and clock inputs' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:ControlPath,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $entry = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'ConvertFrom-CddsiRealtimeRelayForegroundControlBody'
        }, $true))
        $entry.Count | Should -Be 1
        @($entry[0].Body.ParamBlock.Parameters.Name.VariablePath.UserPath) |
            Should -Be @('BodyBytes', 'ExpectedLane', 'NowUtc')
        $bodyParameter = @($entry[0].Body.ParamBlock.Parameters | Where-Object {
            $_.Name.VariablePath.UserPath -ceq 'BodyBytes'
        })[0]
        $bodyParameter.StaticType | Should -BeExactly ([byte[]])
    }

    It 'rejects invalid UTF-8, a UTF-8 BOM, NUL, empty bytes, and oversized bytes before parsing' {
        $validBytes = ConvertTo-CddsiForegroundControlTestBytes `
            -Text (New-CddsiForegroundControlTestBody)
        $nulBytes = [byte[]](@($validBytes[0..20]) + @(0) + @($validBytes[21..($validBytes.Length - 1)]))
        $cases = @(
            [pscustomobject]@{ Bytes = [byte[]]@() }
            [pscustomobject]@{ Bytes = [byte[]](0xc3, 0x28) }
            [pscustomobject]@{ Bytes = [byte[]](@(0xef, 0xbb, 0xbf) + @($validBytes)) }
            [pscustomobject]@{ Bytes = $nulBytes }
            [pscustomobject]@{ Bytes = [byte[]](@(0x78) * 4097) }
        )

        foreach ($case in $cases) {
            $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
                -BodyBytes $case.Bytes -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
            $result.Status | Should -BeExactly 'BLOCKED'
            $result.Code | Should -BeExactly 'FOREGROUND_CONTROL_INVALID'
            $result.BodySha256 | Should -BeNullOrEmpty
            $result.Body | Should -BeNullOrEmpty
        }
    }

    It 'rejects literal CR, LF, TAB, and other control characters in fixed fields' -TestCases @(
        @{
            Name = 'MessageId LF'
            Json = New-CddsiForegroundControlTestBody `
                -MessageId ('123e4567-e89b-42d3-a456-426614174000' + "`n")
        }
        @{
            Name = 'ProductCommit CR'
            Json = New-CddsiForegroundControlTestBody `
                -ProductCommit ('0123456789abcdef0123456789abcdef01234567' + "`r")
        }
        @{
            Name = 'ResultCode TAB'
            Json = New-CddsiForegroundControlTestBody -ResultCode ("NONE`t")
        }
        @{
            Name = 'EvidencePath unit separator'
            Json = New-CddsiForegroundControlTestBody `
                -EvidencePath ('evidence/result.json' + [char]0x1f) `
                -EvidenceSha256 ('a' * 64)
        }
    ) {
        param($Name, $Json)

        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $Json) `
            -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'FOREGROUND_CONTROL_INVALID'
        $result.Body | Should -BeNullOrEmpty
    }

    It 'rejects every non-NUL ASCII control character before canonical parsing' {
        $messageId = '123e4567-e89b-42d3-a456-426614174000'
        foreach ($codePoint in 1..31) {
            $json = New-CddsiForegroundControlTestBody `
                -MessageId ($messageId + [char]$codePoint)
            $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
                -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
                -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
            $result.Status | Should -BeExactly 'BLOCKED'
            $result.Body | Should -BeNullOrEmpty
        }
    }

    It 'rejects schema, lane, role, enum, identifier, commit, and result-code drift' -TestCases @(
        @{ Name = 'schema'; Json = (New-CddsiForegroundControlTestBody).Replace('CDDsi_FOREGROUND_CONTROL_V1', 'OTHER') ; Lane = 'host-to-vm' }
        @{ Name = 'expected lane'; Json = New-CddsiForegroundControlTestBody; Lane = 'vm-to-host' }
        @{ Name = 'sender role'; Json = New-CddsiForegroundControlTestBody -SenderRole 'VmTester'; Lane = 'host-to-vm' }
        @{ Name = 'lane'; Json = New-CddsiForegroundControlTestBody -Lane 'other'; Lane = 'other' }
        @{ Name = 'message UUID version'; Json = New-CddsiForegroundControlTestBody -MessageId '123e4567-e89b-12d3-a456-426614174000'; Lane = 'host-to-vm' }
        @{ Name = 'cycle UUID uppercase'; Json = New-CddsiForegroundControlTestBody -CycleId '223E4567-E89B-42D3-B456-426614174001'; Lane = 'host-to-vm' }
        @{ Name = 'commit uppercase'; Json = New-CddsiForegroundControlTestBody -ProductCommit '0123456789ABCDEF0123456789ABCDEF01234567'; Lane = 'host-to-vm' }
        @{ Name = 'kind'; Json = New-CddsiForegroundControlTestBody -Kind 'RUN_COMMAND'; Lane = 'host-to-vm' }
        @{ Name = 'profile'; Json = New-CddsiForegroundControlTestBody -TestProfile 'EVERYTHING'; Lane = 'host-to-vm' }
        @{ Name = 'status'; Json = New-CddsiForegroundControlTestBody -ResultStatus 'SUCCESS'; Lane = 'host-to-vm' }
        @{ Name = 'free text code'; Json = New-CddsiForegroundControlTestBody -ResultCode 'run this command'; Lane = 'host-to-vm' }
        @{ Name = 'lowercase code'; Json = New-CddsiForegroundControlTestBody -ResultCode 'failed_code'; Lane = 'host-to-vm' }
    ) {
        param($Name, $Json, $Lane)

        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $Json) `
            -ExpectedLane $Lane -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'FOREGROUND_CONTROL_INVALID'
        $result.Body | Should -BeNullOrEmpty
    }

    It 'enforces the fixed lane, kind, status, and result-code matrix' -TestCases @(
        @{
            Name = 'VM kind on host lane'
            Json = New-CddsiForegroundControlTestBody -Kind 'SESSION_READY' -ResultStatus 'READY'
            Lane = 'host-to-vm'
        }
        @{
            Name = 'host kind on VM lane'
            Json = New-CddsiForegroundControlTestBody -Lane 'vm-to-host' -Kind 'HOST_ACK' `
                -SenderRole 'VmTester'
            Lane = 'vm-to-host'
        }
        @{
            Name = 'SESSION_READY without READY'
            Json = New-CddsiForegroundControlTestBody -Lane 'vm-to-host' -Kind 'SESSION_READY' `
                -SenderRole 'VmTester'
            Lane = 'vm-to-host'
        }
        @{
            Name = 'SESSION_READY with result code'
            Json = New-CddsiForegroundControlTestBody -Lane 'vm-to-host' -Kind 'SESSION_READY' `
                -SenderRole 'VmTester' -ResultStatus 'READY' -ResultCode 'READY_WITH_DETAIL'
            Lane = 'vm-to-host'
        }
        @{
            Name = 'TEST_RESULT with NONE status'
            Json = New-CddsiForegroundControlTestBody -Lane 'vm-to-host' -Kind 'TEST_RESULT' `
                -SenderRole 'VmTester'
            Lane = 'vm-to-host'
        }
        @{
            Name = 'failed TEST_RESULT without code'
            Json = New-CddsiForegroundControlTestBody -Lane 'vm-to-host' -Kind 'TEST_RESULT' `
                -SenderRole 'VmTester' -ResultStatus 'FAILED'
            Lane = 'vm-to-host'
        }
        @{
            Name = 'passed TEST_RESULT with failure code'
            Json = New-CddsiForegroundControlTestBody -Lane 'vm-to-host' -Kind 'TEST_RESULT' `
                -SenderRole 'VmTester' -ResultStatus 'PASSED' -ResultCode 'UNEXPECTED_CODE'
            Lane = 'vm-to-host'
        }
        @{
            Name = 'host request with result status'
            Json = New-CddsiForegroundControlTestBody -Kind 'TEST_REQUEST' -ResultStatus 'READY'
            Lane = 'host-to-vm'
        }
    ) {
        param($Name, $Json, $Lane)

        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $Json) `
            -ExpectedLane $Lane -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'FOREGROUND_CONTROL_INVALID'
        $result.Body | Should -BeNullOrEmpty
    }

    It 'rejects noncanonical JSON, duplicate or extra keys, wrong types, and oversized input' -TestCases @(
        @{ Name = 'leading whitespace'; Json = ' ' + (New-CddsiForegroundControlTestBody) }
        @{ Name = 'trailing newline'; Json = (New-CddsiForegroundControlTestBody) + "`n" }
        @{ Name = 'extra key'; Json = (New-CddsiForegroundControlTestBody).Replace('{"Schema"', '{"Extra":"x","Schema"') }
        @{ Name = 'duplicate key'; Json = (New-CddsiForegroundControlTestBody).Replace('{"Schema"', '{"Schema":"CDDsi_FOREGROUND_CONTROL_V1","Schema"') }
        @{ Name = 'property order'; Json = (New-CddsiForegroundControlTestBody).Replace('"Lane":"host-to-vm","MessageId"', '"MessageId":"123e4567-e89b-42d3-a456-426614174000","Lane"') }
        @{ Name = 'numeric kind'; Json = (New-CddsiForegroundControlTestBody).Replace('"Kind":"SESSION_START"', '"Kind":7') }
        @{ Name = 'escaped schema'; Json = (New-CddsiForegroundControlTestBody).Replace('CDDsi_FOREGROUND', 'CDDsi\u005fFOREGROUND') }
        @{ Name = 'array root'; Json = '[' + (New-CddsiForegroundControlTestBody) + ']' }
        @{ Name = 'malformed'; Json = '{' }
        @{ Name = 'oversized'; Json = 'x' * 4097 }
    ) {
        param($Name, $Json)

        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $Json) `
            -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Code | Should -BeExactly 'FOREGROUND_CONTROL_INVALID'
        $result.Body | Should -BeNullOrEmpty
        @($result.PSObject.Properties.Name) | Should -Be @(
            'Schema', 'Status', 'Code', 'BodySha256', 'Body'
        )
    }

    It 'requires evidence path and digest together and rejects unsafe paths or hashes' -TestCases @(
        @{ Name = 'path only'; Path = 'evidence/result.json'; Sha = $null }
        @{ Name = 'sha only'; Path = $null; Sha = ('a' * 64) }
        @{ Name = 'parent traversal'; Path = '../result.json'; Sha = ('a' * 64) }
        @{ Name = 'embedded traversal'; Path = 'evidence/../result.json'; Sha = ('a' * 64) }
        @{ Name = 'absolute'; Path = '/evidence/result.json'; Sha = ('a' * 64) }
        @{ Name = 'backslash'; Path = 'evidence\result.json'; Sha = ('a' * 64) }
        @{ Name = 'drive'; Path = 'C:/evidence/result.json'; Sha = ('a' * 64) }
        @{ Name = 'double separator'; Path = 'evidence//result.json'; Sha = ('a' * 64) }
        @{ Name = 'uppercase digest'; Path = 'evidence/result.json'; Sha = ('A' * 64) }
        @{ Name = 'short digest'; Path = 'evidence/result.json'; Sha = ('a' * 63) }
    ) {
        param($Name, $Path, $Sha)

        $json = New-CddsiForegroundControlTestBody -EvidencePath $Path -EvidenceSha256 $Sha
        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Body | Should -BeNullOrEmpty
    }

    It 'enforces UTC-second timestamps, a five-minute TTL, expiry, and future skew' -TestCases @(
        @{ Name = 'fractional creation'; Created = '2026-07-22T00:00:00.000Z'; Expires = '2026-07-22T00:05:00Z' }
        @{ Name = 'offset creation'; Created = '2026-07-22T08:00:00+08:00'; Expires = '2026-07-22T00:05:00Z' }
        @{ Name = 'nonpositive TTL'; Created = '2026-07-22T00:02:00Z'; Expires = '2026-07-22T00:02:00Z' }
        @{ Name = 'long TTL'; Created = '2026-07-22T00:00:00Z'; Expires = '2026-07-22T00:05:01Z' }
        @{ Name = 'expired'; Created = '2026-07-21T23:59:00Z'; Expires = '2026-07-22T00:01:00Z' }
        @{ Name = 'future skew'; Created = '2026-07-22T00:03:01Z'; Expires = '2026-07-22T00:04:01Z' }
        @{ Name = 'invalid date'; Created = '2026-02-30T00:00:00Z'; Expires = '2026-02-30T00:01:00Z' }
    ) {
        param($Name, $Created, $Expires)

        $json = New-CddsiForegroundControlTestBody -CreatedAtUtc $Created -ExpiresAtUtc $Expires
        $result = ConvertFrom-CddsiRealtimeRelayForegroundControlBody `
            -BodyBytes (ConvertTo-CddsiForegroundControlTestBytes -Text $json) `
            -ExpectedLane 'host-to-vm' -NowUtc $script:NowUtc
        $result.Status | Should -BeExactly 'BLOCKED'
        $result.Body | Should -BeNullOrEmpty
    }

    It 'contains no command or script execution primitive' {
        $tokens = $null
        $errors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile(
            $script:ControlPath,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        $commands = @($ast.FindAll({
            param($node)
            $node -is [Management.Automation.Language.CommandAst]
        }, $true))
        @($commands | Where-Object {
            $_.InvocationOperator -eq [Management.Automation.Language.TokenKind]::Ampersand -or
                @('Invoke-Expression', 'Invoke-Command', 'Start-Process', 'Start-Job') -ccontains $_.GetCommandName()
        }).Count | Should -Be 0
        [IO.File]::ReadAllText($script:ControlPath) | Should -Not -Match 'ScriptBlock|ProcessStartInfo|ClientWebSocket'
    }
}
