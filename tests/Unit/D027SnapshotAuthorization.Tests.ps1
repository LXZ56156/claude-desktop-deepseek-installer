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
            [string]$ExpiresAtUtc = '2030-01-01T00:11:00Z',
            [string]$Operation = 'InstallGitForWindows',
            [string]$ExecutionArtifactSha256 =
                $script:ExecutionArtifactSha256,
            [AllowNull()][AllowEmptyString()][string]$WorkloadBindingToken = ''
        )

        if ([string]::IsNullOrEmpty($WorkloadBindingToken)) {
            if ($Operation -cne 'InstallGitForWindows') {
                throw 'A non-Git snapshot receipt fixture requires an explicit workload token.'
            }
            $WorkloadBindingToken =
                Get-CddsiD027GitSnapshotWorkloadBindingToken `
                    -RunId $RunId `
                    -ExecutionArtifactSha256 $ExecutionArtifactSha256
        }
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
            Operation = $Operation
            ExecutionArtifactSha256 = $ExecutionArtifactSha256
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
            WorkloadBindingToken = $WorkloadBindingToken
            ReceiptBindingToken = ''
        }
        return Set-CddsiD027SnapshotReceiptSignature -Receipt $receipt
    }

    function Set-CddsiD027ClaudeSnapshotWorkloadBinding {
        param([Parameter(Mandatory = $true)]$WorkloadDescriptor)

        $WorkloadDescriptor.WorkloadBindingToken =
            Get-CddsiD027ClaudeSnapshotWorkloadBindingToken `
                -WorkloadDescriptor $WorkloadDescriptor
        return $WorkloadDescriptor
    }

    function New-CddsiD027ClaudeSnapshotWorkloadFixture {
        param(
            [string]$RunId = $script:SnapshotRunId,
            [string]$CandidateZipSha256 =
                $script:ExecutionArtifactSha256,
            [long]$CandidateZipLengthBytes = [long](256MB),
            [long]$CandidateSbomLengthBytes = [long](1MB),
            [long]$CredentialHelperPeLengthBytes = [long](50MB),
            [string]$ClaudeMsixSha256 = ('b' * 64),
            [long]$ClaudeMsixLengthBytes = [long](512MB)
        )

        $values = [ordered]@{
            SchemaVersion = 1
            ContractVersion =
                'cddsi-d027-claude-machine-wide-snapshot-workload-v1'
            WorkloadKind = 'ClaudeDesktopMachineWide'
            RunId = $RunId
            Stage = 'VmAcceptance'
            EnvironmentTier = 'VmAcceptance'
            ArtifactProfile = 'VmAcceptance'
            Operation = 'ProvisionClaudeDesktopMachineWide'
            CandidateCommitSha = '1' * 40
            CandidateTreeSha = '2' * 40
            CandidateZipSha256 = $CandidateZipSha256
            CandidateZipLengthBytes = $CandidateZipLengthBytes
            CandidateContentManifestBindingToken = 'c' * 64
            CandidateSbomSha256 = 'd' * 64
            CandidateSbomLengthBytes = $CandidateSbomLengthBytes
            CredentialHelperSourceTreeSha256 = 'e' * 64
            CredentialHelperSourceManifestSha256 = 'f' * 64
            CredentialHelperPeSha256 = '1' * 64
            CredentialHelperPeLengthBytes = $CredentialHelperPeLengthBytes
            CredentialHelperBuildDescriptorBindingToken = '2' * 64
            CredentialHelperSignatureEvidenceBindingToken = '3' * 64
            ClaudeMsixSha256 = $ClaudeMsixSha256
            ClaudeMsixLengthBytes = $ClaudeMsixLengthBytes
            ClaudeMsixContentBindingToken =
                Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $ClaudeMsixSha256 `
                    -ArtifactSizeBytes $ClaudeMsixLengthBytes
            ClaudeDownloadReceiptBindingToken = '4' * 64
            ClaudeHeldFileIdentityToken = '5' * 64
            ClaudeManifestBindingToken = '6' * 64
            ClaudePackageIdentityBindingToken = '7' * 64
            ClaudeSignatureEvidenceBindingToken = '8' * 64
        }
        $descriptor = [pscustomobject]$values
        $values['WorkloadBindingToken'] =
            Get-CddsiD027ClaudeSnapshotWorkloadBindingToken `
                -WorkloadDescriptor $descriptor
        return [pscustomobject]$values
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

    It 'loads the extracted declaration-only core before Claude and Git domains' {
        $corePath = Join-Path `
            $script:RepoRoot `
            'lib\d027-snapshot-authorization.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $corePath,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        @(
            $ast.EndBlock.Statements |
                Where-Object {
                    $_ -isnot [System.Management.Automation.Language.AssignmentStatementAst] -and
                    $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst]
                }
        ).Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq
                    'Test-CddsiD027ExternalSnapshotReceiptCommonProof'
        }, $true)).Count | Should -Be 0

        $commonProofAssignments = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.AssignmentStatementAst] -and
                $node.Left.Extent.Text -ceq
                    '$script:CddsiD027ExternalSnapshotReceiptCommonProof'
        }, $true))
        $commonProofAssignments.Count | Should -Be 1
        $commonProofAssignments[0].Right.Extent.Text.StartsWith(
            '[Func[object, string, string, object, string, object, bool]]{',
            [StringComparison]::Ordinal
        ) | Should -BeTrue

        $commonProofInvocations = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.InvokeMemberExpressionAst] -and
                $node.Member.Extent.Text -ceq 'Invoke' -and
                $node.Expression.Extent.Text -ceq
                    '$script:CddsiD027ExternalSnapshotReceiptCommonProof'
        }, $true))
        $commonProofInvocations.Count | Should -Be 2
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
                $node.InvocationOperator -ne
                    [System.Management.Automation.Language.TokenKind]::Unknown
        }, $true)).Count | Should -Be 0

        $reflectionFindings = @($ast.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.MemberExpressionAst]) {
                return $false
            }
            $member = $node.Member.Extent.Text.Trim("'`"")
            $expression = $node.Expression.Extent.Text
            return (
                ($node.Static -and $member -ieq 'GetType') -or
                ($expression -match
                    '(?i)(?:^|\[)(?:System\.)?Activator\]?$' -and
                    $member -match '(?i)^CreateInstance$') -or
                ($expression -match '(?i)Assembly' -and
                    $member -match
                        '(?i)^Load(?:File|From|WithPartialName)?$') -or
                $member -ieq 'InvokeMember' -or
                ($member -ieq 'Invoke' -and
                    $expression -match
                        '(?i)(MethodInfo|method|constructor|member)') -or
                ($expression -match
                    '(?i)(ScriptBlock|(?:Automation\.)?PowerShell)' -and
                    $member -match '(?i)^(Create|AddScript)$') -or
                $member -ieq 'AddScript'
            )
        }, $true))
        $reflectionFindings.Count | Should -Be 0
        @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.TypeConstraintAst] -and
                $node.TypeName.FullName -match '^System\.Reflection\.'
        }, $true)).Count | Should -Be 0

        $snapshotIndex = [Array]::IndexOf(
            [string[]]$script:CddsiLibraryLoadOrder,
            'd027-snapshot-authorization.ps1'
        )
        $executionContextIndex = [Array]::IndexOf(
            [string[]]$script:CddsiLibraryLoadOrder,
            'execution-context.ps1'
        )
        $desktopIndex = [Array]::IndexOf(
            [string[]]$script:CddsiLibraryLoadOrder,
            'desktop-msix.ps1'
        )
        $gitIndex = [Array]::IndexOf(
            [string[]]$script:CddsiLibraryLoadOrder,
            'git-for-windows.ps1'
        )
        $snapshotIndex | Should -BeGreaterThan $executionContextIndex
        $desktopIndex | Should -BeGreaterThan $snapshotIndex
        $gitIndex | Should -BeGreaterThan $snapshotIndex

        foreach ($name in @(
                'Get-CddsiD027ClaudeSnapshotWorkloadBindingToken',
                'Test-CddsiD027ClaudeSnapshotWorkloadDescriptor',
                'Test-CddsiD027ExternalSnapshotReceipt',
                'Test-CddsiD027ClaudeExternalSnapshotReceipt',
                'Enable-CddsiD027GitLiveSessionAuthorization',
                'Assert-CddsiD027GitLiveContext'
            )) {
            [IO.Path]::GetFileName(
                (Get-Command $name -CommandType Function).ScriptBlock.File
            ) | Should -BeExactly 'd027-snapshot-authorization.ps1'
        }
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

    It 'keeps invalid Git wrapper expectations fail-closed without throwing' {
        $receipt = New-CddsiD027SnapshotReceiptFixture
        {
            $script:InvalidRunResult = Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $receipt `
                -ExpectedRunId 'not-a-run-id' `
                -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy
        } | Should -Not -Throw
        $script:InvalidRunResult | Should -BeFalse

        {
            $script:InvalidHashResult = Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $receipt `
                -ExpectedRunId $script:SnapshotRunId `
                -ExpectedExecutionArtifactSha256 ('0' * 64) `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy
        } | Should -Not -Throw
        $script:InvalidHashResult | Should -BeFalse
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

Describe 'D-027 Claude machine-wide snapshot workload binding' {
    It 'accepts one exact candidate, helper and Claude artifact binding' {
        $descriptor = New-CddsiD027ClaudeSnapshotWorkloadFixture
        (Test-CddsiD027ClaudeSnapshotWorkloadDescriptor `
            -WorkloadDescriptor $descriptor) | Should -BeTrue
        $descriptor.WorkloadBindingToken |
            Should -BeExactly (
                Get-CddsiD027ClaudeSnapshotWorkloadBindingToken `
                    -WorkloadDescriptor $descriptor
            )
        $descriptor.ClaudeMsixContentBindingToken |
            Should -BeExactly (
                Get-CddsiD027ClaudeContentBindingToken `
                    -ArtifactSha256 $descriptor.ClaudeMsixSha256 `
                    -ArtifactSizeBytes $descriptor.ClaudeMsixLengthBytes
            )
        $descriptor.WorkloadBindingToken |
            Should -Not -BeExactly (
                Get-CddsiD027GitSnapshotWorkloadBindingToken `
                    -RunId $descriptor.RunId `
                    -ExecutionArtifactSha256 $descriptor.CandidateZipSha256
            )
        @($descriptor.PSObject.Properties.Name) -join "`n" |
            Should -BeExactly (@(
                'SchemaVersion',
                'ContractVersion',
                'WorkloadKind',
                'RunId',
                'Stage',
                'EnvironmentTier',
                'ArtifactProfile',
                'Operation',
                'CandidateCommitSha',
                'CandidateTreeSha',
                'CandidateZipSha256',
                'CandidateZipLengthBytes',
                'CandidateContentManifestBindingToken',
                'CandidateSbomSha256',
                'CandidateSbomLengthBytes',
                'CredentialHelperSourceTreeSha256',
                'CredentialHelperSourceManifestSha256',
                'CredentialHelperPeSha256',
                'CredentialHelperPeLengthBytes',
                'CredentialHelperBuildDescriptorBindingToken',
                'CredentialHelperSignatureEvidenceBindingToken',
                'ClaudeMsixSha256',
                'ClaudeMsixLengthBytes',
                'ClaudeMsixContentBindingToken',
                'ClaudeDownloadReceiptBindingToken',
                'ClaudeHeldFileIdentityToken',
                'ClaudeManifestBindingToken',
                'ClaudePackageIdentityBindingToken',
                'ClaudeSignatureEvidenceBindingToken',
                'WorkloadBindingToken'
            ) -join "`n")
    }

    It 'rejects exact-schema, fixed-value, type and content-binding drift' {
        foreach ($mutation in @(
            @{ Name = 'ContractVersion'; Value = 'other-contract' },
            @{ Name = 'WorkloadKind'; Value = 'ClaudeDesktopCurrentUser' },
            @{ Name = 'Operation'; Value = 'InstallGitForWindows' },
            @{ Name = 'CandidateCommitSha'; Value = ('A' * 40) },
            @{ Name = 'CandidateTreeSha'; Value = ('0' * 40) },
            @{ Name = 'CandidateZipSha256'; Value = ('0' * 64) },
            @{ Name = 'CandidateZipLengthBytes'; Value = '268435456' },
            @{ Name = 'ClaudeDownloadReceiptBindingToken'; Value = ('A' * 64) },
            @{ Name = 'ClaudeSignatureEvidenceBindingToken'; Value = ('0' * 64) },
            @{ Name = 'ClaudeMsixSha256'; Value = ('9' * 64) }
        )) {
            $changed = Copy-CddsiD027SnapshotObject `
                -Value (New-CddsiD027ClaudeSnapshotWorkloadFixture)
            $changed.PSObject.Properties[$mutation.Name].Value = $mutation.Value
            $changed = Set-CddsiD027ClaudeSnapshotWorkloadBinding `
                -WorkloadDescriptor $changed
            (Test-CddsiD027ClaudeSnapshotWorkloadDescriptor `
                -WorkloadDescriptor $changed) |
                    Should -BeFalse -Because $mutation.Name
        }

        $extra = New-CddsiD027ClaudeSnapshotWorkloadFixture
        $extra | Add-Member -NotePropertyName Unexpected -NotePropertyValue 'x'
        (Test-CddsiD027ClaudeSnapshotWorkloadDescriptor `
            -WorkloadDescriptor $extra) | Should -BeFalse
        {
            Get-CddsiD027ClaudeSnapshotWorkloadBindingToken `
                -WorkloadDescriptor $extra
        } | Should -Throw '*exact binding schema*'
    }

    It 'pins explicit candidate, SBOM, helper PE and Claude MSIX length caps' {
        $maximum = New-CddsiD027ClaudeSnapshotWorkloadFixture `
            -CandidateZipLengthBytes ([long](1GB)) `
            -CandidateSbomLengthBytes ([long](8MB)) `
            -CredentialHelperPeLengthBytes ([long](100MB)) `
            -ClaudeMsixLengthBytes ([long](1GB))
        (Test-CddsiD027ClaudeSnapshotWorkloadDescriptor `
            -WorkloadDescriptor $maximum) | Should -BeTrue

        foreach ($mutation in @(
            @{ Name = 'CandidateZipLengthBytes'; Value = [long](1GB) + 1 },
            @{ Name = 'CandidateSbomLengthBytes'; Value = [long](8MB) + 1 },
            @{ Name = 'CredentialHelperPeLengthBytes'; Value = [long](100MB) + 1 },
            @{ Name = 'ClaudeMsixLengthBytes'; Value = [long](1GB) + 1 }
        )) {
            $changed = Copy-CddsiD027SnapshotObject -Value $maximum
            $changed.PSObject.Properties[$mutation.Name].Value = $mutation.Value
            $changed = Set-CddsiD027ClaudeSnapshotWorkloadBinding `
                -WorkloadDescriptor $changed
            (Test-CddsiD027ClaudeSnapshotWorkloadDescriptor `
                -WorkloadDescriptor $changed) |
                    Should -BeFalse -Because $mutation.Name
        }
    }

    It 'keeps caller-selectable operation and workload tokens out of domain wrappers' {
        foreach ($name in @(
            'Test-CddsiD027ExternalSnapshotReceipt',
            'Test-CddsiD027ClaudeExternalSnapshotReceipt'
        )) {
            $parameters = (Get-Command $name -CommandType Function).Parameters.Keys
            $parameters | Should -Not -Contain 'ExpectedOperation'
            $parameters | Should -Not -Contain 'ExpectedWorkloadBindingToken'
        }
        Get-Command Enable-CddsiD027ClaudeLiveSessionAuthorization `
            -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Assert-CddsiD027ClaudeLiveContext `
            -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        Get-Command Test-CddsiD027ExternalSnapshotReceiptCommonProof `
            -ErrorAction SilentlyContinue | Should -BeNullOrEmpty
        (Get-Command Enable-CddsiD027GitLiveSessionAuthorization).Definition |
            Should -Not -Match 'ExternalSnapshotReceiptCommonProof'
        (Get-Command Assert-CddsiD027GitLiveContext).Definition |
            Should -Not -Match 'ExternalSnapshotReceiptCommonProof'
    }
}

Describe 'D-027 fixed Git and Claude snapshot receipt domains' {
    It 'accepts only the matching fixed wrapper for valid signed receipts' {
        $descriptor = New-CddsiD027ClaudeSnapshotWorkloadFixture
        $gitReceipt = New-CddsiD027SnapshotReceiptFixture
        $claudeReceipt = New-CddsiD027SnapshotReceiptFixture `
            -Operation 'ProvisionClaudeDesktopMachineWide' `
            -ExecutionArtifactSha256 $descriptor.CandidateZipSha256 `
            -WorkloadBindingToken $descriptor.WorkloadBindingToken

        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $gitReceipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeTrue
        (Test-CddsiD027ClaudeExternalSnapshotReceipt `
            -Receipt $gitReceipt `
            -WorkloadDescriptor $descriptor `
            -ExpectedRunId $script:SnapshotRunId `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse

        (Test-CddsiD027ClaudeExternalSnapshotReceipt `
            -Receipt $claudeReceipt `
            -WorkloadDescriptor $descriptor `
            -ExpectedRunId $script:SnapshotRunId `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeTrue
        (Test-CddsiD027ExternalSnapshotReceipt `
            -Receipt $claudeReceipt `
            -ExpectedRunId $script:SnapshotRunId `
            -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse
    }

    It 'rejects re-signed cross-domain operation and workload-token pairings' {
        $descriptor = New-CddsiD027ClaudeSnapshotWorkloadFixture
        $gitToken = Get-CddsiD027GitSnapshotWorkloadBindingToken `
            -RunId $script:SnapshotRunId `
            -ExecutionArtifactSha256 $script:ExecutionArtifactSha256
        $claudeOperationGitToken = New-CddsiD027SnapshotReceiptFixture `
            -Operation 'ProvisionClaudeDesktopMachineWide' `
            -ExecutionArtifactSha256 $descriptor.CandidateZipSha256 `
            -WorkloadBindingToken $gitToken
        $gitOperationClaudeToken = New-CddsiD027SnapshotReceiptFixture `
            -Operation 'InstallGitForWindows' `
            -ExecutionArtifactSha256 $descriptor.CandidateZipSha256 `
            -WorkloadBindingToken $descriptor.WorkloadBindingToken

        foreach ($receipt in @(
            $claudeOperationGitToken,
            $gitOperationClaudeToken
        )) {
            (Test-CddsiD027ExternalSnapshotReceipt `
                -Receipt $receipt `
                -ExpectedRunId $script:SnapshotRunId `
                -ExpectedExecutionArtifactSha256 $script:ExecutionArtifactSha256 `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse
            (Test-CddsiD027ClaudeExternalSnapshotReceipt `
                -Receipt $receipt `
                -WorkloadDescriptor $descriptor `
                -ExpectedRunId $script:SnapshotRunId `
                -PlatformObservation $script:PlatformObservation `
                -ValidationTimeUtc '2030-01-01T00:02:00Z' `
                -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse
        }
    }

    It 'binds the receipt to the expected run, candidate ZIP and exact descriptor' {
        $descriptor = New-CddsiD027ClaudeSnapshotWorkloadFixture
        $wrongArtifact = New-CddsiD027SnapshotReceiptFixture `
            -Operation 'ProvisionClaudeDesktopMachineWide' `
            -ExecutionArtifactSha256 ('9' * 64) `
            -WorkloadBindingToken $descriptor.WorkloadBindingToken
        (Test-CddsiD027ClaudeExternalSnapshotReceipt `
            -Receipt $wrongArtifact `
            -WorkloadDescriptor $descriptor `
            -ExpectedRunId $script:SnapshotRunId `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse

        $otherDescriptor = Copy-CddsiD027SnapshotObject -Value $descriptor
        $otherDescriptor.ClaudeSignatureEvidenceBindingToken = '9' * 64
        $otherDescriptor = Set-CddsiD027ClaudeSnapshotWorkloadBinding `
            -WorkloadDescriptor $otherDescriptor
        $otherReceipt = New-CddsiD027SnapshotReceiptFixture `
            -Operation 'ProvisionClaudeDesktopMachineWide' `
            -ExecutionArtifactSha256 $otherDescriptor.CandidateZipSha256 `
            -WorkloadBindingToken $otherDescriptor.WorkloadBindingToken
        (Test-CddsiD027ClaudeExternalSnapshotReceipt `
            -Receipt $otherReceipt `
            -WorkloadDescriptor $descriptor `
            -ExpectedRunId $script:SnapshotRunId `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse
        (Test-CddsiD027ClaudeExternalSnapshotReceipt `
            -Receipt $otherReceipt `
            -WorkloadDescriptor $otherDescriptor `
            -ExpectedRunId $script:SnapshotRunId `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeTrue

        (Test-CddsiD027ClaudeExternalSnapshotReceipt `
            -Receipt $otherReceipt `
            -WorkloadDescriptor $otherDescriptor `
            -ExpectedRunId '27000000-0000-4000-8000-000000000128' `
            -PlatformObservation $script:PlatformObservation `
            -ValidationTimeUtc '2030-01-01T00:02:00Z' `
            -AuthorityPolicy $script:AuthorityPolicy) | Should -BeFalse
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
