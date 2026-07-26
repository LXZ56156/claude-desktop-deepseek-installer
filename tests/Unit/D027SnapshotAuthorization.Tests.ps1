BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:SnapshotRunId = '27000000-0000-4000-8000-000000000127'
    $script:ExecutionArtifactSha256 = 'a' * 64
    $script:SnapshotRsa = New-Object System.Security.Cryptography.RSACryptoServiceProvider 2048
    $script:SnapshotRsa.PersistKeyInCsp = $false
    $publicParameters = $script:SnapshotRsa.ExportParameters($false)
    $modulusBase64 = [Convert]::ToBase64String($publicParameters.Modulus)
    $exponentBase64 = [Convert]::ToBase64String($publicParameters.Exponent)
    $script:AuthorityPolicy = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-d027-snapshot-authority-policy-v1'
        Configured = $true
        AuthorityId = 'd027-test-external-vm-operator'
        SignatureAlgorithm = 'RSA-SHA256-PKCS1-v1_5'
        AuthorityKeySha256 = Get-CddsiD027SnapshotAuthorityKeySha256 `
            -RsaModulusBase64 $modulusBase64 `
            -RsaExponentBase64 $exponentBase64
        RsaModulusBase64 = $modulusBase64
        RsaExponentBase64 = $exponentBase64
    }
    $script:PlatformObservation = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-d027-snapshot-platform-observation-v2'
        WindowsMajorVersion = [long]10
        WindowsBuildNumber = [long]26100
        WindowsProductType = 'Workstation'
        WindowsProductInfoCode = [long]48
        NativeArchitecture = 'x64'
        ProcessArchitecture = 'x64'
        PowerShellVersion = '5.1'
        VmIdentitySha256 = 'c' * 64
    }

    function Set-CddsiD027SnapshotReceiptSignature {
        param([Parameter(Mandatory = $true)]$Receipt)

        $Receipt.ReceiptBindingToken =
            Get-CddsiD027ExternalSnapshotReceiptBindingToken -Receipt $Receipt
        $text = 'cddsi-d027-external-clean-snapshot-receipt-signature-v1' +
            "`n" + $Receipt.ReceiptBindingToken
        $bytes = [System.Text.UTF8Encoding]::new($false, $true).GetBytes($text)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $hash = $sha.ComputeHash($bytes)
            $signature = $script:SnapshotRsa.SignHash(
                $hash,
                [System.Security.Cryptography.CryptoConfig]::MapNameToOID('SHA256')
            )
        }
        finally {
            $sha.Dispose()
        }
        $Receipt.AuthoritySignatureBase64 = [Convert]::ToBase64String($signature)
        return $Receipt
    }

    function New-CddsiD027SnapshotReceiptFixture {
        param(
            [string]$RunId = $script:SnapshotRunId,
            [string]$RestoreCompletedAtUtc = '2030-01-01T00:00:00Z',
            [string]$IssuedAtUtc = '2030-01-01T00:01:00Z',
            [string]$ExpiresAtUtc = '2030-01-01T00:11:00Z'
        )

        $receipt = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-d027-external-clean-snapshot-receipt-v2'
            AuthorityId = $script:AuthorityPolicy.AuthorityId
            AuthorityKeySha256 = $script:AuthorityPolicy.AuthorityKeySha256
            SignatureAlgorithm = 'RSA-SHA256-PKCS1-v1_5'
            AuthoritySignatureBase64 = ''
            ExternalSource = 'VmExternalHypervisor'
            RestoreState = 'CleanSnapshotRestored'
            VmDisposition = 'Disposable'
            RunId = $RunId
            Stage = 'VmAcceptance'
            EnvironmentTier = 'VmAcceptance'
            ArtifactProfile = 'VmAcceptance'
            Operation = 'InstallGitForWindows'
            ExecutionArtifactSha256 = $script:ExecutionArtifactSha256
            SnapshotIdentitySha256 = 'b' * 64
            VmIdentitySha256 = 'c' * 64
            RestorerIdentitySha256 = 'd' * 64
            WindowsMajorVersion = [long]10
            WindowsBuildNumber = [long]26100
            WindowsProductType = 'Workstation'
            WindowsProductInfoCode = [long]48
            NativeArchitecture = 'x64'
            ProcessArchitecture = 'x64'
            PowerShellVersion = '5.1'
            RestoreCompletedAtUtc = $RestoreCompletedAtUtc
            IssuedAtUtc = $IssuedAtUtc
            ExpiresAtUtc = $ExpiresAtUtc
            WorkloadBindingToken = Get-CddsiD027GitSnapshotWorkloadBindingToken `
                -RunId $RunId `
                -ExecutionArtifactSha256 $script:ExecutionArtifactSha256
            ReceiptBindingToken = ''
        }
        return Set-CddsiD027SnapshotReceiptSignature -Receipt $receipt
    }

    function Copy-CddsiD027SnapshotObject {
        param([Parameter(Mandatory = $true)]$Value)
        return ($Value | ConvertTo-Json -Depth 8 -Compress | ConvertFrom-Json)
    }

    function Write-CddsiD027SnapshotReceiptFixture {
        param(
            [Parameter(Mandatory = $true)]$Receipt,
            [string]$LeafName = 'd027-external-snapshot-receipt.json'
        )

        $path = Join-Path $TestDrive $LeafName
        $bytes = [System.Text.UTF8Encoding]::new($false).GetBytes(
            ($Receipt | ConvertTo-Json -Depth 8 -Compress)
        )
        [System.IO.File]::WriteAllBytes($path, $bytes)
        $sha = [System.Security.Cryptography.SHA256]::Create()
        try {
            $digest = [BitConverter]::ToString(
                $sha.ComputeHash($bytes)
            ).Replace('-', '').ToLowerInvariant()
        }
        finally {
            $sha.Dispose()
        }
        return [pscustomobject]@{
            Path = $path
            Sha256 = $digest
            Length = [long]$bytes.Length
        }
    }

    function New-CddsiD027SnapshotContextFixture {
        param([string]$RunId = $script:SnapshotRunId)
        return [pscustomobject]@{
            RunId = $RunId
            Mode = 'Live'
            Stage = 'VmAcceptance'
            EnvironmentTier = 'VmAcceptance'
            Paths = [pscustomobject]@{ Temp = $TestDrive }
            Providers = [pscustomobject]@{ Kind = 'Unloaded' }
        }
    }
}

AfterAll {
    if ($null -ne $script:SnapshotRsa) {
        $script:SnapshotRsa.Dispose()
    }
}

Describe 'D-027 signed external clean-snapshot receipt' {
    BeforeEach {
        $script:CddsiD027GitLiveSessionAuthorization = $null
    }

    It 'accepts a valid ephemeral RSA-SHA256 PKCS#1 v1.5 signature' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $receipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeTrue
    }

    It 'rejects signature, key and authority tampering even with a recomputed binding' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        foreach ($mutation in @(
            @{ Name = 'AuthorityId'; Value = 'd027-other-external-vm-operator' },
            @{ Name = 'AuthorityKeySha256'; Value = ('e' * 64) },
            @{ Name = 'SignatureAlgorithm'; Value = 'RSA-SHA512-PKCS1-v1_5' }
        )) {
            $changed = Copy-CddsiD027SnapshotObject -Value $receipt
            $changed.PSObject.Properties[$mutation.Name].Value = $mutation.Value
            $changed = Set-CddsiD027SnapshotReceiptSignature -Receipt $changed
            (Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $changed `
                -ExpectedRunId $script:SnapshotRunId `
                -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy) |
                    Should -BeFalse -Because $mutation.Name
        }

        $badSignature = Copy-CddsiD027SnapshotObject -Value $receipt
        $signatureBytes = [Convert]::FromBase64String(
            $badSignature.AuthoritySignatureBase64
        )
        $signatureBytes[0] = $signatureBytes[0] -bxor 1
        $badSignature.AuthoritySignatureBase64 =
            [Convert]::ToBase64String($signatureBytes)
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $badSignature `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse
    }

    It 'rejects unconfigured production policy and all placeholder hashes' {
        $productionPolicy = Get-CddsiD027SnapshotAuthorityPolicy `
            -ExecutionContext (New-CddsiD027SnapshotContextFixture)
        $productionPolicy.Configured | Should -BeFalse
        $productionPolicy.AuthorityKeySha256 | Should -BeExactly ('0' * 64)
        $productionPolicy.RsaModulusBase64 | Should -BeNullOrEmpty
        $receipt = New-CddsiD027SnapshotReceiptFixture
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $receipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $productionPolicy) | Should -BeFalse

        foreach ($name in @(
            'AuthorityKeySha256',
            'ExecutionArtifactSha256',
            'SnapshotIdentitySha256',
            'VmIdentitySha256',
            'RestorerIdentitySha256',
            'WorkloadBindingToken',
            'ReceiptBindingToken'
        )) {
            $changed = Copy-CddsiD027SnapshotObject -Value $receipt
            $changed.PSObject.Properties[$name].Value = '0' * 64
            (Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $changed `
                -ExpectedRunId $script:SnapshotRunId `
                -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy) |
                    Should -BeFalse -Because $name
        }
    }

    It 'rejects two-type precedence bypasses after recomputing binding and signature' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        foreach ($name in @(
            'WindowsMajorVersion',
            'WindowsBuildNumber',
            'WindowsProductInfoCode'
        )) {
            $changed = Copy-CddsiD027SnapshotObject -Value $receipt
            $changed.PSObject.Properties[$name].Value =
                [string]$changed.PSObject.Properties[$name].Value
            $changed = Set-CddsiD027SnapshotReceiptSignature -Receipt $changed
            (Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $changed `
                -ExpectedRunId $script:SnapshotRunId `
                -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy) |
                    Should -BeFalse -Because $name
        }
    }

    It 'binds exact workload, platform and freshness' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        foreach ($mutation in @(
            @{ Name = 'Stage'; Value = 'VmDevelopment' },
            @{ Name = 'EnvironmentTier'; Value = 'UserLive' },
            @{ Name = 'ArtifactProfile'; Value = 'UserLive' },
            @{ Name = 'Operation'; Value = 'ObserveGitForWindows' },
            @{ Name = 'ExecutionArtifactSha256'; Value = ('e' * 64) },
            @{ Name = 'PowerShellVersion'; Value = '7.6' }
        )) {
            $changed = Copy-CddsiD027SnapshotObject -Value $receipt
            $changed.PSObject.Properties[$mutation.Name].Value = $mutation.Value
            $changed = Set-CddsiD027SnapshotReceiptSignature -Receipt $changed
            (Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $changed `
                -ExpectedRunId $script:SnapshotRunId `
                -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy) |
                    Should -BeFalse -Because $mutation.Name
        }
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $receipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:12:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse

        $otherVmPlatform =
            Copy-CddsiD027SnapshotObject -Value $script:PlatformObservation
        $otherVmPlatform.VmIdentitySha256 = 'f' * 64
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $receipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $otherVmPlatform `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse

        $longReceipt = New-CddsiD027SnapshotReceiptFixture `
            -ExpiresAtUtc '2030-01-01T01:31:01Z'
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $longReceipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse

        $boundedReceipt = New-CddsiD027SnapshotReceiptFixture `
            -ExpiresAtUtc '2030-01-01T01:31:00Z'
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $boundedReceipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T01:15:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeTrue
    }
}

Describe 'D-027 snapshot receipt file identity' {
    BeforeEach {
        Mock Assert-CddsiD027GitLiveBootstrapContext { return $true }
    }

    It 'locks, identifies and hashes the exact direct-child JSON before parsing' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        $file = Write-CddsiD027SnapshotReceiptFixture -Receipt $receipt
        $context = New-CddsiD027SnapshotContextFixture
        $read = Read-CddsiD027ExternalSnapshotReceipt `
            -ExecutionContext $context `
            -ReceiptPath $file.Path `
            -ExpectedReceiptSha256 $file.Sha256
        $read.ReceiptSha256 | Should -BeExactly $file.Sha256
        $read.ReceiptLengthBytes | Should -Be $file.Length

        $definition =
            (Get-Command Read-CddsiD027ExternalSnapshotReceipt).Definition
        $exclusiveIndex = $definition.IndexOf(
            '[System.IO.FileShare]::None',
            [StringComparison]::Ordinal
        )
        $identityIndex = $definition.IndexOf(
            'Get-CddsiD027SnapshotReceiptHeldFileObservation',
            [StringComparison]::Ordinal
        )
        $byteReadIndex = $definition.IndexOf(
            '$bytes =',
            [StringComparison]::Ordinal
        )
        $exclusiveIndex | Should -BeGreaterThan -1
        $identityIndex | Should -BeGreaterThan $exclusiveIndex
        $byteReadIndex | Should -BeGreaterThan $identityIndex

        {
            Read-CddsiD027ExternalSnapshotReceipt `
                -ExecutionContext $context `
                -ReceiptPath ($file.Path + ':alternate-stream') `
                -ExpectedReceiptSha256 $file.Sha256
        } | Should -Throw '*exact product-temp file*'
    }

    It 'rejects a hard-linked receipt by held-handle link count' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        $file = Write-CddsiD027SnapshotReceiptFixture -Receipt $receipt
        $linkPath = Join-Path $TestDrive 'd027-receipt-hardlink.json'
        try {
            New-Item -ItemType HardLink -Path $linkPath -Target $file.Path `
                -ErrorAction Stop | Out-Null
        }
        catch {
            Set-ItResult -Skipped -Because (
                'The TestDrive filesystem could not create a hard link: ' +
                $_.Exception.GetType().Name
            )
            return
        }
        {
            Read-CddsiD027ExternalSnapshotReceipt `
                -ExecutionContext (New-CddsiD027SnapshotContextFixture) `
                -ReceiptPath $file.Path `
                -ExpectedReceiptSha256 $file.Sha256
        } | Should -Throw '*exact product-temp file*'
    }
}

Describe 'D-027 signed process authorization and install terminal states' {
    BeforeEach {
        $script:CddsiD027GitLiveSessionAuthorization = $null
        $script:UseProductionSnapshotPolicy = $false
        Mock Assert-CddsiD027GitLiveBootstrapContext { return $true }
        Mock Get-CddsiD027SnapshotPlatformObservation {
            return $script:PlatformObservation
        }
        Mock Get-CddsiD027SnapshotAuthorityPolicy {
            if ($script:UseProductionSnapshotPolicy) {
                return $script:ProductionSnapshotPolicy
            }
            return $script:AuthorityPolicy
        }
    }

    It 'revalidates the signed receipt on every assertion and fails closed on session tamper' {
        $now = [DateTimeOffset]::UtcNow
        $receipt = New-CddsiD027SnapshotReceiptFixture `
            -RestoreCompletedAtUtc $now.AddMinutes(-1).ToString('yyyy-MM-ddTHH:mm:ssZ') `
            -IssuedAtUtc $now.AddSeconds(-30).ToString('yyyy-MM-ddTHH:mm:ssZ') `
            -ExpiresAtUtc $now.AddMinutes(10).ToString('yyyy-MM-ddTHH:mm:ssZ')
        Mock Read-CddsiD027ExternalSnapshotReceipt {
            return [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-d027-external-snapshot-receipt-read-v1'
                Receipt = $receipt
                ReceiptSha256 = 'e' * 64
                ReceiptLengthBytes = [long]4096
            }
        }
        $context = New-CddsiD027SnapshotContextFixture
        $activation = Enable-CddsiD027GitLiveSessionAuthorization `
            -ExecutionContext $context `
            -ReceiptPath (Join-Path $TestDrive 'receipt.json') `
            -ExpectedReceiptSha256 ('e' * 64) `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256
        $activation.Status | Should -BeExactly 'SUCCEEDED'
        $activation.Data.ReceiptBindingToken |
            Should -BeExactly $receipt.ReceiptBindingToken
        (Assert-CddsiD027GitLiveContext -ExecutionContext $context) |
            Should -BeTrue

        $script:CddsiD027GitLiveSessionAuthorization.Receipt.VmIdentitySha256 =
            'f' * 64
        { Assert-CddsiD027GitLiveContext -ExecutionContext $context } |
            Should -Throw '*signed by the pinned authority*'
        $script:CddsiD027GitLiveSessionAuthorization | Should -BeNullOrEmpty
    }

    It 'hard-blocks activation with the tracked unconfigured production policy' {
        $script:ProductionSnapshotPolicy =
            Microsoft.PowerShell.Utility\Import-PowerShellDataFile -LiteralPath (
                Join-Path $script:RepoRoot 'config\d027-snapshot-authority.psd1'
            )
        $script:ProductionSnapshotPolicy = [pscustomobject][ordered]@{
            SchemaVersion = $script:ProductionSnapshotPolicy.SchemaVersion
            ContractVersion = $script:ProductionSnapshotPolicy.ContractVersion
            Configured = $script:ProductionSnapshotPolicy.Configured
            AuthorityId = $script:ProductionSnapshotPolicy.AuthorityId
            SignatureAlgorithm = $script:ProductionSnapshotPolicy.SignatureAlgorithm
            AuthorityKeySha256 = $script:ProductionSnapshotPolicy.AuthorityKeySha256
            RsaModulusBase64 = $script:ProductionSnapshotPolicy.RsaModulusBase64
            RsaExponentBase64 = $script:ProductionSnapshotPolicy.RsaExponentBase64
        }
        $script:UseProductionSnapshotPolicy = $true
        $receipt = New-CddsiD027SnapshotReceiptFixture
        Mock Read-CddsiD027ExternalSnapshotReceipt {
            return [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-d027-external-snapshot-receipt-read-v1'
                Receipt = $receipt
                ReceiptSha256 = 'e' * 64
                ReceiptLengthBytes = [long]4096
            }
        }
        $result = Enable-CddsiD027GitLiveSessionAuthorization `
            -ExecutionContext (New-CddsiD027SnapshotContextFixture) `
            -ReceiptPath (Join-Path $TestDrive 'receipt.json') `
            -ExpectedReceiptSha256 ('e' * 64) `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.ErrorCode |
            Should -BeExactly 'D027_EXTERNAL_SNAPSHOT_AUTHORIZATION_INVALID'
    }

    It 'fails closed with no session and keeps the gate VmAcceptance-only' {
        $context = New-CddsiD027SnapshotContextFixture
        { Assert-CddsiD027GitLiveContext -ExecutionContext $context } |
            Should -Throw '*signed by the pinned authority*'
        (Get-Command Install-CddsiGitForWindows).Definition |
            Should -Match "\`$ArtifactProfile -cne 'VmAcceptance'"
    }

    It 'maps timeout-still-running and post-authorization failures to controlled PARTIAL' {
        $stillRunning = ConvertTo-CddsiD027GitInstallerExitResult `
            -Started $true `
            -UacCancelled $false `
            -ExitCode $null `
            -ReadbackTrusted $false `
            -ChangedObserved $true `
            -RestartObserved $false `
            -InstallerStillRunning $true
        $stillRunning.Status | Should -BeExactly 'PARTIAL'
        $stillRunning.ErrorCode | Should -BeExactly 'GIT_INSTALLER_STILL_RUNNING'

        $expired = ConvertTo-CddsiD027GitInstallerExitResult `
            -Started $true `
            -UacCancelled $false `
            -ExitCode 0 `
            -ReadbackTrusted $false `
            -ChangedObserved $true `
            -RestartObserved $false `
            -PostInstallAuthorizationInvalid $true
        $expired.Status | Should -BeExactly 'PARTIAL'
        $expired.ErrorCode |
            Should -BeExactly 'GIT_INSTALL_POST_AUTHORIZATION_INVALID'
    }

    It 'revalidates signed authorization immediately before Start-Process and skips readback while running' {
        $definition = (Get-Command Install-CddsiGitForWindows).Definition
        $startIndex = $definition.IndexOf(
            'Start-Process',
            [StringComparison]::Ordinal
        )
        $assertIndex = $definition.LastIndexOf(
            'Assert-CddsiD027GitLiveContext',
            $startIndex,
            [StringComparison]::Ordinal
        )
        $bindingIndex = $definition.LastIndexOf(
            'Receipt.ReceiptBindingToken',
            $startIndex,
            [StringComparison]::Ordinal
        )
        $assertIndex | Should -BeGreaterThan -1
        $bindingIndex | Should -BeGreaterThan $assertIndex
        $startIndex | Should -BeGreaterThan $bindingIndex
        $definition | Should -Match (
            '\$started -and\s+-not \$installerStillRunning -and\s+' +
            '-not \$completionObservationFailed -and\s+' +
            '\$null -ne \$exitCode -and\s+\[int\]\$exitCode -eq 0'
        )
        $definition | Should -Match (
            'GIT_INSTALLER_STILL_RUNNING|InstallerStillRunning'
        )
        $definition | Should -Match (
            'no completion or persistent PATH readback was claimed'
        )
    }
}
