$script:CddsiRelayVmSmokePowerShell7 = $PSVersionTable.PSVersion.Major -ge 7

Describe 'relay-only VM manual smoke' {
    BeforeAll {
        $script:CddsiRelayVmSmokePowerShell7 = $PSVersionTable.PSVersion.Major -ge 7
        $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
        $script:SmokePath = Join-Path $script:RepoRoot 'operator\realtime-relay\invoke-vm-smoke.ps1'
        if ($script:CddsiRelayVmSmokePowerShell7) { . $script:SmokePath }
        $script:SmokeNow = [DateTimeOffset]::Parse('2030-01-01T00:00:00Z')

        function Test-CddsiRelayVmSmokePowerShell7OnlyCase {
            if ($script:CddsiRelayVmSmokePowerShell7) { return $true }
            $PSVersionTable.PSVersion.Major | Should -Be 5
            $parseErrors = $null
            [void][Management.Automation.Language.Parser]::ParseFile(
                $script:SmokePath,
                [ref]$null,
                [ref]$parseErrors
            )
            @($parseErrors).Count | Should -Be 0
            return $false
        }

        function Set-CddsiRelayVmSmokeTestAcl {
            param([Parameter(Mandatory = $true)][string]$Path, [switch]$Wide)

            $owner = [Security.Principal.WindowsIdentity]::GetCurrent().User
            $security = [Security.AccessControl.FileSecurity]::new()
            $security.SetOwner($owner)
            $security.SetAccessRuleProtection($true, $false)
            [void]$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                    $owner,
                    [Security.AccessControl.FileSystemRights]::FullControl,
                    [Security.AccessControl.AccessControlType]::Allow
                ))
            if ($Wide) {
                $world = [Security.Principal.SecurityIdentifier]::new(
                    [Security.Principal.WellKnownSidType]::WorldSid,
                    $null
                )
                [void]$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                        $world,
                        [Security.AccessControl.FileSystemRights]::Read,
                        [Security.AccessControl.AccessControlType]::Allow
                    ))
            }
            [IO.FileSystemAclExtensions]::SetAccessControl([IO.FileInfo]::new($Path), $security)
        }

        function New-CddsiRelayVmSmokeTestFixture {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)][byte[]]$SecretBytes,
                [long]$ExpectedHostSequence = 1,
                [long]$VmToHostSequence = 1,
                [AllowNull()]$VmToHostPreviousSha256 = $null
            )

            $secret = [Convert]::ToBase64String($SecretBytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
            $package = [ordered]@{
                Schema = 'cddsi-relay-vm-handoff-v1'
                Endpoint = 'https://cddsi-relay.example.workers.dev'
                Environment = 'production-v1'
                ClientId = 'vm-tester-v1'
                KeyId = 'vm-2026-07'
                SecretBase64Url = $secret
                ExpectedHostMessageId = '10000000-0000-4000-8000-000000000001'
                ExpectedHostSequence = $ExpectedHostSequence
                VmToHostSequence = $VmToHostSequence
                VmToHostPreviousSha256 = $VmToHostPreviousSha256
                ReplyPayloadSha256 = '2' * 64
                ReplyRepositoryId = '1301870545'
                ReplyRef = 'refs/heads/main'
                ReplyCommit = '3' * 40
                ExpiryMinutes = 5
            }
            [IO.File]::WriteAllText(
                $Path,
                (ConvertTo-Json -Compress -Depth 4 -InputObject $package),
                [Text.UTF8Encoding]::new($false)
            )
            Set-CddsiRelayVmSmokeTestAcl -Path $Path
            return [pscustomobject][ordered]@{
                Path = $Path
                Endpoint = $package.Endpoint
                KeyId = $package.KeyId
                SecretBase64Url = $secret
                Package = $package
            }
        }

        function New-CddsiRelayVmSmokeTestHostMessage {
            param(
                [switch]$IncludeUntrustedText,
                [long]$Sequence = 1,
                [AllowNull()]$PreviousSha256 = $null
            )

            $message = [ordered]@{
                Commit = '4' * 40
                CreatedAt = '2029-12-31T23:59:50Z'
                Expiry = '2030-01-01T00:05:00Z'
                Lane = 'host-to-vm'
                MessageId = '10000000-0000-4000-8000-000000000001'
                PayloadSha256 = '5' * 64
                PreviousSha256 = $PreviousSha256
                Ref = 'refs/heads/main'
                RepositoryId = '1301870499'
                Schema = 'cddsi-relay-notification-v1'
                SenderRole = 'HostCoordinator'
                Sequence = $Sequence
            }
            if ($IncludeUntrustedText) {
                $message.UntrustedText = '[IO.File]::WriteAllText($sentinel, ''EXECUTED'')'
            }
            return [pscustomobject]$message
        }

        function New-CddsiRelayVmSmokeTestHandler {
            param(
                [Parameter(Mandatory = $true)]$HostMessage,
                [Parameter(Mandatory = $true)][AllowEmptyCollection()][Collections.ArrayList]$Requests,
                [switch]$FailAck
            )

            $hostCanonical = ConvertTo-Json -Compress -Depth 4 -InputObject $HostMessage
            $hostSha256 = Get-CddsiVmSmokeSha256Internal -Text $hostCanonical
            $readBody = ConvertTo-Json -Compress -Depth 8 -InputObject ([ordered]@{
                    Schema = 'cddsi-relay-response-v1'
                    Status = 'OK'
                    Code = 'MESSAGES'
                    Lane = 'host-to-vm'
                    After = 0
                    Messages = @([ordered]@{
                            Notification = $HostMessage
                            MessageSha256 = $hostSha256
                        })
                })
            $fail = [bool]$FailAck
            return {
                param($Request)

                [void]$Requests.Add($Request)
                switch -CaseSensitive ($Request.CanonicalTarget) {
                    '/v1/health' {
                        return [pscustomobject][ordered]@{
                            StatusCode = 200
                            ContentType = 'application/json'
                            Body = '{"Schema":"cddsi-relay-health-v1","Status":"OK","Version":"v1"}'
                        }
                    }
                    '/v1/messages/host-to-vm?after=0' {
                        return [pscustomobject][ordered]@{
                            StatusCode = 200
                            ContentType = 'application/json'
                            Body = $readBody
                        }
                    }
                    '/v1/ack' {
                        if ($fail) {
                            return [pscustomobject][ordered]@{
                                StatusCode = 503
                                ContentType = 'application/json'
                                Body = '{"Schema":"cddsi-relay-response-v1","Status":"REJECTED","Code":"STORAGE_FAILURE"}'
                            }
                        }
                        $ack = ConvertFrom-Json -InputObject $Request.Body -DateKind String
                        return [pscustomobject][ordered]@{
                            StatusCode = 200
                            ContentType = 'application/json'
                            Body = ConvertTo-Json -Compress -InputObject ([ordered]@{
                                    Schema = 'cddsi-relay-response-v1'
                                    Status = 'OK'
                                    Code = 'ACKED'
                                    Lane = 'host-to-vm'
                                    Sequence = [long]$ack.Sequence
                                    MessageId = [string]$ack.MessageId
                                })
                        }
                    }
                    '/v1/publish/vm-to-host' {
                        $reply = ConvertFrom-Json -InputObject $Request.Body -DateKind String
                        $replyBytes = [Text.UTF8Encoding]::new($false).GetBytes($Request.Body)
                        $algorithm = [Security.Cryptography.SHA256]::Create()
                        try {
                            $replySha256 = ([BitConverter]::ToString(
                                    $algorithm.ComputeHash($replyBytes)
                                )).Replace('-', '').ToLowerInvariant()
                        }
                        finally {
                            $algorithm.Dispose()
                            [Array]::Clear($replyBytes, 0, $replyBytes.Length)
                        }
                        return [pscustomobject][ordered]@{
                            StatusCode = 201
                            ContentType = 'application/json'
                            Body = ConvertTo-Json -Compress -InputObject ([ordered]@{
                                    Schema = 'cddsi-relay-response-v1'
                                    Status = 'OK'
                                    Code = 'PUBLISHED'
                                    Lane = 'vm-to-host'
                                    Sequence = [long]$reply.Sequence
                                    MessageId = [string]$reply.MessageId
                                    MessageSha256 = $replySha256
                                })
                        }
                    }
                    default { throw 'UNEXPECTED_FAKE_HTTP_TARGET' }
                }
            }.GetNewClosure()
        }

        function Test-CddsiRelayVmSmokeTestSignature {
            param(
                [Parameter(Mandatory = $true)]$Request,
                [Parameter(Mandatory = $true)][byte[]]$SecretBytes
            )

            $headers = $Request.Headers
            $canonical = @(
                'CDDsi-HMAC-SHA256-v2'
                'cddsi-realtime-relay-v1'
                'production-v1'
                'vm-2026-07'
                'vm-tester-v1'
                $Request.Method
                $Request.CanonicalTarget
                $headers['x-cddsi-timestamp']
                $headers['x-cddsi-nonce']
                $headers['x-cddsi-body-sha256']
            ) -join "`n"
            $hmac = [Security.Cryptography.HMACSHA256]::new($SecretBytes)
            try {
                $bytes = [Text.UTF8Encoding]::new($false).GetBytes($canonical)
                try {
                    $actual = ([BitConverter]::ToString($hmac.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant()
                }
                finally {
                    [Array]::Clear($bytes, 0, $bytes.Length)
                }
            }
            finally {
                $hmac.Dispose()
            }
            return $actual -ceq $headers['x-cddsi-signature']
        }
    }

    It 'plans without reading, deleting, or sending the one-time package' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $secretBytes = [byte[]](1..32)
        $fixture = New-CddsiRelayVmSmokeTestFixture -Path (Join-Path $TestDrive 'plan.json') `
            -SecretBytes $secretBytes
        $invocationCount = 0
        $handler = { $invocationCount++; throw 'NETWORK_MUST_NOT_RUN' }.GetNewClosure()

        $result = Invoke-CddsiRelayVmSmoke -PackagePath $fixture.Path -HttpHandler $handler

        $result.Status | Should -BeExactly 'PLANNED'
        $result.Code | Should -BeExactly 'ACKNOWLEDGEMENT_REQUIRED'
        $result.NetworkRequestCount | Should -Be 0
        $result.PackageDeleted | Should -BeFalse
        [IO.File]::Exists($fixture.Path) | Should -BeTrue
        $invocationCount | Should -Be 0
    }

    It 'rejects a package with a wider ACL before reading, deleting, or sending it' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $secretBytes = [byte[]](1..32)
        $fixture = New-CddsiRelayVmSmokeTestFixture -Path (Join-Path $TestDrive 'wide-acl.json') `
            -SecretBytes $secretBytes
        Set-CddsiRelayVmSmokeTestAcl -Path $fixture.Path -Wide
        $invocationCount = 0
        $handler = { $invocationCount++; throw 'NETWORK_MUST_NOT_RUN' }.GetNewClosure()

        $result = Invoke-CddsiRelayVmSmoke -PackagePath $fixture.Path `
            -AcknowledgeRelayOnlyLive -HttpHandler $handler -NowUtc $script:SmokeNow

        $result.Status | Should -BeExactly 'FAILED'
        $result.Code | Should -BeExactly 'VM_RELAY_PACKAGE_ACL_INVALID'
        $result.PackageDeleted | Should -BeFalse
        $result.NetworkRequestCount | Should -Be 0
        [IO.File]::Exists($fixture.Path) | Should -BeTrue
        $invocationCount | Should -Be 0
        [Array]::Clear($secretBytes, 0, $secretBytes.Length)
    }

    It 'rejects an ACL descriptor not owned by the current user' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $currentUser = [Security.Principal.WindowsIdentity]::GetCurrent().User
        $otherOwner = [Security.Principal.SecurityIdentifier]::new(
            [Security.Principal.WellKnownSidType]::LocalSystemSid,
            $null
        )
        $security = [Security.AccessControl.FileSecurity]::new()
        $security.SetOwner($otherOwner)
        $security.SetAccessRuleProtection($true, $false)
        [void]$security.AddAccessRule([Security.AccessControl.FileSystemAccessRule]::new(
                $currentUser,
                [Security.AccessControl.FileSystemRights]::FullControl,
                [Security.AccessControl.AccessControlType]::Allow
            ))

        Test-CddsiVmSmokeOwnerOnlyAclDescriptorInternal `
            -Security $security -CurrentUser $currentUser | Should -BeFalse
    }

    It 'rejects a host message whose previous hash does not match its sequence position' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        foreach ($case in @(
                @{ Sequence = 1L; Previous = '6' * 64 }
                @{ Sequence = 2L; Previous = $null }
            )) {
            $message = New-CddsiRelayVmSmokeTestHostMessage `
                -Sequence $case.Sequence -PreviousSha256 $case.Previous
            $canonical = ConvertTo-Json -Compress -Depth 4 -InputObject $message
            $response = [pscustomobject][ordered]@{
                Schema = 'cddsi-relay-response-v1'; Status = 'OK'; Code = 'MESSAGES'
                Lane = 'host-to-vm'; After = $case.Sequence - 1
                Messages = @([ordered]@{
                        Notification = $message
                        MessageSha256 = Get-CddsiVmSmokeSha256Internal -Text $canonical
                    })
            }
            $package = [pscustomobject]@{
                ExpectedHostMessageId = $message.MessageId
                ExpectedHostSequence = $case.Sequence
            }

            { Get-CddsiVmSmokeHostMessageInternal `
                    -Response $response -Package $package -NowUtc $script:SmokeNow } |
                Should -Throw -ExpectedMessage 'VM_RELAY_HOST_MESSAGE_INVALID'
        }
    }

    It 'signs the inverse VM directions, deletes the package, ACKs, and publishes only a pointer' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $secretBytes = [byte[]](1..32)
        $fixture = New-CddsiRelayVmSmokeTestFixture -Path (Join-Path $TestDrive 'live.json') `
            -SecretBytes $secretBytes
        $requests = [Collections.ArrayList]::new()
        $handler = New-CddsiRelayVmSmokeTestHandler `
            -HostMessage (New-CddsiRelayVmSmokeTestHostMessage) -Requests $requests

        $probeBytes = [IO.File]::ReadAllBytes($fixture.Path)
        try {
            $probePackage = ConvertFrom-CddsiVmSmokePackageInternal -Bytes $probeBytes
            $probePackage.ExpectedHostSequence | Should -Be 1
            [Array]::Clear($probePackage.SecretBytes, 0, $probePackage.SecretBytes.Length)
        }
        finally {
            [Array]::Clear($probeBytes, 0, $probeBytes.Length)
        }

        $result = Invoke-CddsiRelayVmSmoke -PackagePath $fixture.Path `
            -AcknowledgeRelayOnlyLive -HttpHandler $handler -NowUtc $script:SmokeNow

        @($result.PSObject.Properties.Name) | Should -BeExactly @(
            'Schema', 'HostMessageId', 'HostSequence', 'VmMessageId', 'VmSequence',
            'VmPayloadSha256', 'VmMessageSha256'
        )
        $result.Schema | Should -BeExactly 'VM_RELAY_SMOKE_REPORT_V1'
        $result.HostMessageId | Should -BeExactly $fixture.Package.ExpectedHostMessageId
        $result.HostSequence | Should -Be 1
        $result.VmSequence | Should -Be 1
        $result.VmPayloadSha256 | Should -BeExactly ('2' * 64)
        $result.VmMessageSha256 | Should -Match '^[0-9a-f]{64}$'
        [IO.File]::Exists($fixture.Path) | Should -BeFalse

        @($requests | ForEach-Object CanonicalTarget) | Should -BeExactly @(
            '/v1/health'
            '/v1/messages/host-to-vm?after=0'
            '/v1/ack'
            '/v1/publish/vm-to-host'
        )
        foreach ($request in @($requests | Select-Object -Skip 1)) {
            $request.Headers['x-cddsi-client-id'] | Should -BeExactly 'vm-tester-v1'
            $request.Headers['x-cddsi-nonce'] | Should -Match '^[A-Za-z0-9_-]{43}$'
            (Test-CddsiRelayVmSmokeTestSignature -Request $request -SecretBytes $secretBytes) |
                Should -BeTrue
        }
        $requests[1].Method | Should -BeExactly 'GET'
        $requests[2].Method | Should -BeExactly 'POST'
        $requests[3].Method | Should -BeExactly 'POST'
        $reply = ConvertFrom-Json -InputObject $requests[3].Body -DateKind String
        $reply.Lane | Should -BeExactly 'vm-to-host'
        $reply.SenderRole | Should -BeExactly 'VmTester'
        $reply.RepositoryId | Should -BeExactly '1301870545'
        $reply.PayloadSha256 | Should -BeExactly ('2' * 64)
        @($reply.PSObject.Properties.Name) | Should -Not -Contain 'Payload'

        $serialized = ConvertTo-Json -Compress -Depth 4 -InputObject $result
        $serialized | Should -Not -Match ([regex]::Escape($fixture.SecretBase64Url))
        $serialized | Should -Not -Match ([regex]::Escape($fixture.Endpoint))
        $serialized | Should -Not -Match ([regex]::Escape($fixture.KeyId))
        [Array]::Clear($secretBytes, 0, $secretBytes.Length)
    }

    It 'never executes an untrusted response field and fails before ACK' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $secretBytes = [byte[]](33..64)
        $fixture = New-CddsiRelayVmSmokeTestFixture -Path (Join-Path $TestDrive 'untrusted.json') `
            -SecretBytes $secretBytes
        $sentinel = Join-Path $TestDrive 'must-not-exist.txt'
        $requests = [Collections.ArrayList]::new()
        $handler = New-CddsiRelayVmSmokeTestHandler `
            -HostMessage (New-CddsiRelayVmSmokeTestHostMessage -IncludeUntrustedText) `
            -Requests $requests

        $result = Invoke-CddsiRelayVmSmoke -PackagePath $fixture.Path `
            -AcknowledgeRelayOnlyLive -HttpHandler $handler -NowUtc $script:SmokeNow

        $result.Status | Should -BeExactly 'FAILED'
        $result.Code | Should -BeExactly 'VM_RELAY_HOST_MESSAGE_INVALID'
        $result.PackageDeleted | Should -BeTrue
        $result.NetworkRequestCount | Should -Be 2
        [IO.File]::Exists($fixture.Path) | Should -BeFalse
        [IO.File]::Exists($sentinel) | Should -BeFalse
        [Array]::Clear($secretBytes, 0, $secretBytes.Length)
    }

    It 'returns a redacted fixed failure and does not publish after a lost ACK response' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $secretBytes = [byte[]](65..96)
        $fixture = New-CddsiRelayVmSmokeTestFixture -Path (Join-Path $TestDrive 'ack-failure.json') `
            -SecretBytes $secretBytes
        $requests = [Collections.ArrayList]::new()
        $handler = New-CddsiRelayVmSmokeTestHandler `
            -HostMessage (New-CddsiRelayVmSmokeTestHostMessage) -Requests $requests -FailAck

        $result = Invoke-CddsiRelayVmSmoke -PackagePath $fixture.Path `
            -AcknowledgeRelayOnlyLive -HttpHandler $handler -NowUtc $script:SmokeNow

        $result.Status | Should -BeExactly 'FAILED'
        $result.Code | Should -BeExactly 'VM_RELAY_ACK_FAILED'
        $result.PackageDeleted | Should -BeTrue
        $result.NetworkRequestCount | Should -Be 3
        @($requests | Where-Object CanonicalTarget -CEQ '/v1/publish/vm-to-host').Count |
            Should -Be 0
        $serialized = ConvertTo-Json -Compress -Depth 4 -InputObject $result
        $serialized | Should -Not -Match ([regex]::Escape($fixture.SecretBase64Url))
        $serialized | Should -Not -Match 'STORAGE_FAILURE'
        [Array]::Clear($secretBytes, 0, $secretBytes.Length)
    }

    It 'classifies the script and focused test as DevelopmentOnly' {
        if (-not (Test-CddsiRelayVmSmokePowerShell7OnlyCase)) { return }
        $manifest = Import-PowerShellDataFile -LiteralPath (
            Join-Path $script:RepoRoot 'scripts\release-manifest.psd1'
        )
        foreach ($relative in @(
                'operator/realtime-relay/invoke-vm-smoke.ps1'
                'tests/Contract/RealtimeRelayVmSmoke.Tests.ps1'
            )) {
            @($manifest.PackageFiles) | Should -Not -Contain $relative
            @($manifest.DevelopmentOnlyFiles) | Should -Contain $relative
        }
    }
}
