BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    . (Join-Path $script:RepoRoot 'lib\credential-helper-release.ps1')
    Import-CddsiLibraries

    $script:ValidationTimeUtc = '2030-01-01T00:04:00Z'
    $script:CandidateId = '10000000-0000-4000-8000-000000000001'
    $script:EvidenceRunId = '10000000-0000-4000-8000-000000000002'
    $script:CandidateChallenge = '10000000-0000-4000-8000-000000000003'
    $script:InstallRoot = 'C:\SyntheticInstall\CredentialHelper'
    $script:InstalledPath = 'C:\SyntheticInstall\CredentialHelper\cddsi-credential-helper.exe'
    $script:CurrentUserSidToken = ('a' * 64)

    function Copy-CddsiCredentialHelperReleaseFixture {
        param([Parameter(Mandatory = $true)][AllowNull()]$Value)
        if ($null -eq $Value -or $Value -is [string] -or $Value -is [ValueType]) { return $Value }
        if ($Value -is [System.Collections.IDictionary]) {
            $copy = [ordered]@{}
            foreach ($key in $Value.Keys) { $copy[$key] = Copy-CddsiCredentialHelperReleaseFixture -Value $Value[$key] }
            return $copy
        }
        if ($Value -is [System.Collections.IEnumerable]) {
            $items = @()
            foreach ($item in $Value) { $items += ,(Copy-CddsiCredentialHelperReleaseFixture -Value $item) }
            return ,$items
        }
        $properties = [ordered]@{}
        foreach ($property in $Value.PSObject.Properties) {
            $properties[$property.Name] = Copy-CddsiCredentialHelperReleaseFixture -Value $property.Value
        }
        return [pscustomobject]$properties
    }

    function New-CddsiCredentialHelperBuildFixture {
        $descriptor = [pscustomobject][ordered]@{
            SchemaVersion                   = 1
            ContractVersion                 = 'cddsi-credential-helper-build-v1'
            BuildId                         = '20000000-0000-4000-8000-000000000001'
            ReleaseVersion                  = '1.0.0-rc.1'
            CommitId                        = ('a' * 40)
            ImplementationKind              = 'SignedDotNetExe'
            ProtocolVersion                 = 'cddsi-credential-helper-protocol-v1'
            ExecutableFileName               = 'cddsi-credential-helper.exe'
            Architecture                    = 'X64'
            RuntimeIdentifier               = 'win-x64'
            TargetFramework                 = 'net8.0-windows'
            DotNetSdkVersion                = '8.0.408'
            CompilerVersion                 = '4.11.0'
            RuntimePackVersion              = '8.0.15'
            ToolchainDescriptorSha256       = ('1' * 64)
            DependencyLockSha256            = ('2' * 64)
            DependencyCount                 = 4
            SourceTreeSha256                = ('3' * 64)
            SourceManifestSha256            = ('4' * 64)
            SourceTreeEntryCount            = 12
            SbomFormat                      = 'CycloneDXJson15'
            SbomSha256                      = ('5' * 64)
            SbomComponentSetSha256          = ('6' * 64)
            SbomComponentCount              = 9
            PeSha256                        = ('7' * 64)
            PeSizeBytes                     = 5242880
            ExpectedSignerCertificateSha256 = ('8' * 64)
            ExpectedSignerSubjectSha256     = ('9' * 64)
            Deterministic                   = $true
            SelfContained                   = $true
            SingleFile                      = $true
            DependencyLockRequired          = $true
            AuthenticodeRequired            = $true
            ProducedAtUtc                   = '2030-01-01T00:00:00Z'
            DescriptorBindingToken          = $null
        }
        $descriptor.DescriptorBindingToken = Get-CddsiCredentialHelperBuildDescriptorBindingToken -Descriptor $descriptor
        return $descriptor
    }

    function New-CddsiCredentialHelperCandidateFixture {
        param(
            [Parameter(Mandatory = $true)]$BuildDescriptor,
            [string]$InstalledPath = $script:InstalledPath,
            [string]$CandidateId = $script:CandidateId
        )
        $rootToken = Get-CddsiPathBindingToken -Path $script:InstallRoot
        $pathToken = Get-CddsiPathBindingToken -Path $InstalledPath
        $signature = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-signature-v1'
            EvidenceId = '10000000-0000-4000-8000-000000000004'; CandidateId = $CandidateId
            BuildDescriptorBindingToken = $BuildDescriptor.DescriptorBindingToken; PeSha256 = $BuildDescriptor.PeSha256
            AuthenticodeStatus = 'Valid'; ChainTrusted = $true
            SignerCertificateSha256 = $BuildDescriptor.ExpectedSignerCertificateSha256
            SignerSubjectSha256 = $BuildDescriptor.ExpectedSignerSubjectSha256
            TimestampStatus = 'Valid'; TimestampUtc = '2030-01-01T00:01:00Z'
            ObservedAtUtc = '2030-01-01T00:02:00Z'; BindingToken = $null
        }
        $signature.BindingToken = Get-CddsiCredentialHelperSignatureEvidenceBindingToken -Evidence $signature
        $acl = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-acl-v1'
            EvidenceId = '10000000-0000-4000-8000-000000000005'; CandidateId = $CandidateId
            BuildDescriptorBindingToken = $BuildDescriptor.DescriptorBindingToken
            InstalledExecutablePathToken = $pathToken; OwnerSidToken = $script:CurrentUserSidToken
            ExpectedOwnerSidToken = $script:CurrentUserSidToken; AclDescriptorSha256 = ('b' * 64)
            AclPolicy = 'CurrentUserReadExecuteOnlyProtectedDacl'; DaclProtected = $true
            OwnerMatch = $true; CurrentUserReadExecute = $true; CurrentUserWrite = $false
            AdministratorsWrite = $true; SystemWrite = $true; UnexpectedWriteAceCount = 0
            ObservedAtUtc = '2030-01-01T00:02:30Z'; BindingToken = $null
        }
        $acl.BindingToken = Get-CddsiCredentialHelperAclEvidenceBindingToken -Evidence $acl
        $candidate = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-candidate-v1'
            CandidateId = $CandidateId; EvidenceRunId = $script:EvidenceRunId
            ChallengeNonce = $script:CandidateChallenge
            BuildDescriptorBindingToken = $BuildDescriptor.DescriptorBindingToken
            BinaryPresent = $true; ObservedPeSha256 = $BuildDescriptor.PeSha256
            ObservedPeSizeBytes = $BuildDescriptor.PeSizeBytes; InstallRootPathToken = $rootToken
            InstalledExecutablePathToken = $pathToken; FinalResolvedPathToken = $pathToken
            PathCanonical = $true; ReparsePointCount = 0
            SignatureEvidence = $signature; AclEvidence = $acl
            InvocationContractBindingToken = Get-CddsiCredentialHelperInvocationContractBindingToken
            ProtocolVersion = $BuildDescriptor.ProtocolVersion; ObservedAtUtc = '2030-01-01T00:03:00Z'
            Eligible = $true; BindingToken = $null
        }
        $candidate.BindingToken = Get-CddsiCredentialHelperCandidateEvidenceBindingToken -Evidence $candidate
        return $candidate
    }

    function Repair-CddsiCredentialHelperCandidateFixture {
        param([Parameter(Mandatory = $true)]$Candidate)
        $Candidate.SignatureEvidence.BindingToken = Get-CddsiCredentialHelperSignatureEvidenceBindingToken -Evidence $Candidate.SignatureEvidence
        $Candidate.AclEvidence.BindingToken = Get-CddsiCredentialHelperAclEvidenceBindingToken -Evidence $Candidate.AclEvidence
        $Candidate.BindingToken = Get-CddsiCredentialHelperCandidateEvidenceBindingToken -Evidence $Candidate
    }

    function New-CddsiCredentialHelperBlobFixture {
        param([Parameter(Mandatory = $true)]$Candidate)
        $entropy = Get-CddsiSupplyChainTextBindingToken -Text (@(
            $Candidate.BindingToken, $Candidate.ProtocolVersion, $Candidate.InstalledExecutablePathToken,
            $Candidate.ObservedPeSha256, $script:CurrentUserSidToken, '<CREDENTIAL_BLOB:DEEPSEEK>'
        ) -join "`n")
        $blob = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-protected-blob-v1'
            EvidenceId = '10000000-0000-4000-8000-000000000006'; CandidateId = $Candidate.CandidateId
            CandidateEvidenceBindingToken = $Candidate.BindingToken
            OperationNonce = '10000000-0000-4000-8000-000000000007'
            ProtocolVersion = $Candidate.ProtocolVersion; InstalledExecutablePathToken = $Candidate.InstalledExecutablePathToken
            HelperPeSha256 = $Candidate.ObservedPeSha256; BlobResourceToken = '<CREDENTIAL_BLOB:DEEPSEEK>'
            BlobHandleToken = '<DPAPI_BLOB:30000000-0000-4000-8000-000000000001>'
            EncryptedBlobSha256 = ('c' * 64); EncryptedBlobSizeBytes = 256; DpapiScope = 'CurrentUser'
            CurrentUserSidToken = $script:CurrentUserSidToken; ExpectedCurrentUserSidToken = $script:CurrentUserSidToken
            OwnerSidToken = $script:CurrentUserSidToken; EntropyContextSha256 = $entropy
            AclDescriptorSha256 = ('d' * 64); AclPolicy = 'CurrentUserOnlyProtectedDacl'
            DaclProtected = $true; OwnerMatch = $true; UnexpectedWriteAceCount = 0
            PlaintextPersisted = $false; ReadbackStatus = 'VerifiedEncryptedBlob'
            CreatedAtUtc = '2030-01-01T00:03:30Z'; Valid = $true; BindingToken = $null
        }
        $blob.BindingToken = Get-CddsiCredentialHelperProtectedBlobEvidenceBindingToken -Evidence $blob
        return $blob
    }

    function New-CddsiCredentialHelperInvocationFixture {
        param([Parameter(Mandatory = $true)]$Candidate)
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-credential-helper-invocation-v1'
            InvocationId = '10000000-0000-4000-8000-000000000008'; CandidateId = $Candidate.CandidateId
            CandidateEvidenceBindingToken = $Candidate.BindingToken
            InvocationChallenge = '10000000-0000-4000-8000-000000000009'
            ProtocolVersion = $Candidate.ProtocolVersion; InvocationKind = 'DirectExecutable'
            HelperContext = 'interactive'; PromptObserved = $false
            ArgumentCount = 0; ShellInvocation = $false; StandardInputRead = $false
            OutputKind = 'BareTokenSingleLine'; OutputValidated = $true; TokenLength = 32
            OutputPersisted = $false; OutputDigestPersisted = $false; StandardErrorEmpty = $true
            ExitCode = 0; InvocationStatus = 'Completed'; ElapsedMilliseconds = 250
            TimeoutSeconds = 60; TtlSeconds = 3600; ObservedPeSha256 = $Candidate.ObservedPeSha256
            InstalledExecutablePathToken = $Candidate.InstalledExecutablePathToken
            StartedAtUtc = '2030-01-01T00:03:10Z'; CompletedAtUtc = '2030-01-01T00:03:11Z'
            Valid = $true; BindingToken = $null
        }
        $evidence.BindingToken = Get-CddsiCredentialHelperInvocationEvidenceBindingToken -Evidence $evidence
        return $evidence
    }
}

Describe 'Credential helper D-010 release contract' {
    It 'freezes SignedDotNetExe, locked supply chain, CurrentUser DPAPI and direct invocation' {
        $contract = New-CddsiCredentialHelperReleaseContract
        $contract.ImplementationKind | Should -BeExactly 'SignedDotNetExe'
        $contract.DependencyLockRequired | Should -BeTrue
        $contract.AuthenticodeRequired | Should -BeTrue
        $contract.DpapiScope | Should -BeExactly 'CurrentUser'
        $contract.PlaintextPersistence | Should -BeFalse
        $contract.ArgumentCount | Should -Be 0
        $contract.ShellInvocation | Should -BeFalse
        $contract.AllowedOutputKinds | Should -Be @('BareTokenSingleLine', 'ExactJsonV1')
        $contract.StandardErrorPolicy | Should -BeExactly 'Empty'
        $contract.ContextEnvironmentVariableName | Should -BeExactly 'CLAUDE_HELPER_CONTEXT'
        $contract.AllowedHelperContexts | Should -Be @(
            'interactive', 'mid-session-refresh', 'scheduled-task', 'setup-test', 'background'
        )
        $contract.DefaultTimeoutSeconds | Should -Be 60
        $contract.MidSessionRefreshTimeoutSeconds | Should -Be 20
        $contract.PromptPolicy | Should -BeExactly 'Forbidden'
        $contract.TtlSeconds | Should -Be 3600
    }

    It 'contains declarations and pure helpers only' {
        $tokens = $null
        $errors = $null
        $path = Join-Path $script:RepoRoot 'lib\credential-helper-release.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        @($ast.EndBlock.Statements | Where-Object { $_ -isnot [System.Management.Automation.Language.FunctionDefinitionAst] }).Count | Should -Be 0
        $forbidden = @('Test-Path', 'Get-Content', 'Get-Item', 'Get-ChildItem', 'Get-FileHash', 'Get-AuthenticodeSignature', 'Start-Process', 'Invoke-Expression', 'Add-Type')
        $commands = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true))
        @($commands | Where-Object { $forbidden -ccontains $_.GetCommandName() }).Count | Should -Be 0
        $typeNames = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.TypeExpressionAst] }, $true) | ForEach-Object { $_.TypeName.FullName })
        @($typeNames | Where-Object { $_ -match '^(?:System\.)?Security\.Cryptography\.ProtectedData$|^(?:System\.)?Diagnostics\.Process$|^(?:System\.)?IO\.(?:File|Directory)$' }).Count | Should -Be 0
    }
}

Describe 'Credential helper build and candidate evidence' {
    BeforeEach {
        $script:Build = New-CddsiCredentialHelperBuildFixture
        $script:Candidate = New-CddsiCredentialHelperCandidateFixture -BuildDescriptor $script:Build
    }

    It 'accepts one exact deterministic, locked and signed build descriptor' {
        Test-CddsiCredentialHelperBuildDescriptor -Descriptor $script:Build -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeTrue
    }

    It 'rejects source, SBOM, toolchain, dependency-lock, PE, signer and protocol drift' {
        foreach ($case in @(
            @{ Name = 'SourceTreeSha256'; Value = ('e' * 64) },
            @{ Name = 'SbomSha256'; Value = ('e' * 64) },
            @{ Name = 'ToolchainDescriptorSha256'; Value = ('e' * 64) },
            @{ Name = 'DependencyLockSha256'; Value = ('e' * 64) },
            @{ Name = 'PeSha256'; Value = ('e' * 64) },
            @{ Name = 'ExpectedSignerCertificateSha256'; Value = ('e' * 64) },
            @{ Name = 'ProtocolVersion'; Value = 'cddsi-credential-helper-protocol-v2' }
        )) {
            $copy = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Build
            $copy.($case.Name) = $case.Value
            Test-CddsiCredentialHelperBuildDescriptor -Descriptor $copy -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }
        foreach ($flag in @('Deterministic', 'SelfContained', 'SingleFile', 'DependencyLockRequired', 'AuthenticodeRequired')) {
            $copy = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Build
            $copy.$flag = $false
            $copy.DescriptorBindingToken = Get-CddsiCredentialHelperBuildDescriptorBindingToken -Descriptor $copy
            Test-CddsiCredentialHelperBuildDescriptor -Descriptor $copy -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }
    }

    It 'accepts a fresh path-, hash-, signer-, ACL- and challenge-bound candidate' {
        Test-CddsiCredentialHelperCandidateEvidence -Evidence $script:Candidate -ExpectedBuildDescriptor $script:Build `
            -ExpectedCandidateId $script:CandidateId -ExpectedEvidenceRunId $script:EvidenceRunId `
            -ExpectedChallengeNonce $script:CandidateChallenge -ExpectedInstallRootPath $script:InstallRoot `
            -ExpectedInstalledExecutablePath $script:InstalledPath `
            -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeTrue
    }

    It 'never admits a missing or unsigned binary to a candidate' {
        $missing = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Candidate
        $missing.BinaryPresent = $false
        Repair-CddsiCredentialHelperCandidateFixture -Candidate $missing
        $unsigned = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Candidate
        $unsigned.SignatureEvidence.AuthenticodeStatus = 'NotSigned'
        Repair-CddsiCredentialHelperCandidateFixture -Candidate $unsigned
        foreach ($copy in @($missing, $unsigned)) {
            Test-CddsiCredentialHelperCandidateEvidence -Evidence $copy -ExpectedBuildDescriptor $script:Build `
                -ExpectedCandidateId $script:CandidateId -ExpectedEvidenceRunId $script:EvidenceRunId `
                -ExpectedChallengeNonce $script:CandidateChallenge -ExpectedInstallRootPath $script:InstallRoot `
                -ExpectedInstalledExecutablePath $script:InstalledPath `
                -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }
    }

    It 'rejects hash, signature, path, ACL, owner, protocol and replay drift even with repaired local digests' {
        $attacks = @(
            { param($x) $x.ObservedPeSha256 = ('e' * 64) },
            { param($x) $x.SignatureEvidence.ChainTrusted = $false },
            { param($x) $x.SignatureEvidence.SignerCertificateSha256 = ('e' * 64) },
            { param($x) $x.InstallRootPathToken = ('e' * 64) },
            { param($x) $x.InstalledExecutablePathToken = ('e' * 64) },
            { param($x) $x.FinalResolvedPathToken = ('e' * 64) },
            { param($x) $x.PathCanonical = $false },
            { param($x) $x.ReparsePointCount = 1 },
            { param($x) $x.AclEvidence.OwnerSidToken = ('e' * 64) },
            { param($x) $x.AclEvidence.CurrentUserWrite = $true },
            { param($x) $x.ProtocolVersion = 'cddsi-credential-helper-protocol-v2' },
            { param($x) $x.ChallengeNonce = '10000000-0000-4000-8000-000000000010' }
        )
        foreach ($attack in $attacks) {
            $copy = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Candidate
            & $attack $copy
            Repair-CddsiCredentialHelperCandidateFixture -Candidate $copy
            Test-CddsiCredentialHelperCandidateEvidence -Evidence $copy -ExpectedBuildDescriptor $script:Build `
                -ExpectedCandidateId $script:CandidateId -ExpectedEvidenceRunId $script:EvidenceRunId `
                -ExpectedChallengeNonce $script:CandidateChallenge -ExpectedInstallRootPath $script:InstallRoot `
                -ExpectedInstalledExecutablePath $script:InstalledPath `
                -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }
    }

    It 'rejects dot segments, trailing aliases and Windows device names in the approved helper root' {
        foreach ($root in @(
            'C:\SyntheticInstall\..\CredentialHelper',
            'C:\SyntheticInstall\.\CredentialHelper',
            'C:\SyntheticInstall\CredentialHelper.',
            'C:\SyntheticInstall\CredentialHelper ',
            'C:\SyntheticInstall\CON',
            'C:\SyntheticInstall\COM¹'
        )) {
            Test-CddsiCredentialHelperCandidateEvidence -Evidence $script:Candidate -ExpectedBuildDescriptor $script:Build `
                -ExpectedCandidateId $script:CandidateId -ExpectedEvidenceRunId $script:EvidenceRunId `
                -ExpectedChallengeNonce $script:CandidateChallenge -ExpectedInstallRootPath $root `
                -ExpectedInstalledExecutablePath ($root + '\cddsi-credential-helper.exe') `
                -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }
    }
}

Describe 'Credential helper protected blob contract' {
    BeforeEach {
        $script:Build = New-CddsiCredentialHelperBuildFixture
        $script:Candidate = New-CddsiCredentialHelperCandidateFixture -BuildDescriptor $script:Build
        $script:Blob = New-CddsiCredentialHelperBlobFixture -Candidate $script:Candidate
    }

    It 'accepts only opaque DPAPI CurrentUser evidence bound to candidate, owner, ACL and nonce' {
        Test-CddsiCredentialHelperProtectedBlobEvidence -Evidence $script:Blob -ExpectedCandidateEvidence $script:Candidate `
            -ExpectedOperationNonce '10000000-0000-4000-8000-000000000007' `
            -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeTrue
        $script:Blob.PSObject.Properties.Name | Should -Not -Contain 'Plaintext'
        $script:Blob.PSObject.Properties.Name | Should -Not -Contain 'SecureValue'
    }

    It 'rejects replay, path, version, binary, scope, owner, ACL, entropy and plaintext drift' {
        $attacks = @(
            { param($x) $x.OperationNonce = '10000000-0000-4000-8000-000000000010' },
            { param($x) $x.InstalledExecutablePathToken = ('e' * 64) },
            { param($x) $x.ProtocolVersion = 'cddsi-credential-helper-protocol-v2' },
            { param($x) $x.HelperPeSha256 = ('e' * 64) },
            { param($x) $x.DpapiScope = 'LocalMachine' },
            { param($x) $x.OwnerSidToken = ('e' * 64) },
            { param($x) $x.DaclProtected = $false },
            { param($x) $x.EntropyContextSha256 = ('e' * 64) },
            { param($x) $x.PlaintextPersisted = $true }
        )
        foreach ($attack in $attacks) {
            $copy = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Blob
            & $attack $copy
            $copy.BindingToken = Get-CddsiCredentialHelperProtectedBlobEvidenceBindingToken -Evidence $copy
            Test-CddsiCredentialHelperProtectedBlobEvidence -Evidence $copy -ExpectedCandidateEvidence $script:Candidate `
                -ExpectedOperationNonce '10000000-0000-4000-8000-000000000007' `
                -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }
        $hashDrift = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Blob
        $hashDrift.EncryptedBlobSha256 = ('e' * 64)
        Test-CddsiCredentialHelperProtectedBlobEvidence -Evidence $hashDrift -ExpectedCandidateEvidence $script:Candidate `
            -ExpectedOperationNonce '10000000-0000-4000-8000-000000000007' `
            -ExpectedCurrentUserSidToken $script:CurrentUserSidToken -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
    }
}

Describe 'Credential helper invocation contract' {
    BeforeEach {
        $script:Build = New-CddsiCredentialHelperBuildFixture
        $script:Candidate = New-CddsiCredentialHelperCandidateFixture -BuildDescriptor $script:Build
        $script:Invocation = New-CddsiCredentialHelperInvocationFixture -Candidate $script:Candidate
        $script:OutputArgs = @{
            HelperContext = 'interactive'; PromptObserved = $false
            ArgumentCount = 0; ShellInvocation = $false; StandardInputRead = $false
            StandardError = ''; ExitCode = 0; InvocationStatus = 'Completed'; ElapsedMilliseconds = 250
            TimeoutSeconds = 60; TtlSeconds = 3600; ExpectedHelperPeSha256 = $script:Build.PeSha256
            ObservedHelperPeSha256 = $script:Build.PeSha256
            ExpectedInstalledExecutablePathToken = $script:Candidate.InstalledExecutablePathToken
            ObservedInstalledExecutablePathToken = $script:Candidate.InstalledExecutablePathToken
        }
    }

    It 'accepts one bare token line or the exact one-property JSON form without persisting either' {
        Test-CddsiCredentialHelperInvocationOutput @script:OutputArgs -OutputKind BareTokenSingleLine `
            -StandardOutput 'synthetic_token_value_1234567890' | Should -BeTrue
        Test-CddsiCredentialHelperInvocationOutput @script:OutputArgs -OutputKind ExactJsonV1 `
            -StandardOutput '{"token":"synthetic_token_value_1234567890"}' | Should -BeTrue
        Test-CddsiCredentialHelperInvocationOutput @script:OutputArgs -OutputKind ExactJsonV1 `
            -StandardOutput '{ "token":"synthetic_token_value_1234567890"}' | Should -BeFalse
        Test-CddsiCredentialHelperInvocationOutput @script:OutputArgs -OutputKind ExactJsonV1 `
            -StandardOutput '{"token":"synthetic_token_value_1234567890","extra":true}' | Should -BeFalse
    }

    It 'honors CLAUDE_HELPER_CONTEXT and clamps mid-session refresh to twenty seconds without prompting' {
        foreach ($context in @('interactive', 'scheduled-task', 'setup-test', 'background')) {
            $args = @{} + $script:OutputArgs
            $args.HelperContext = $context
            Test-CddsiCredentialHelperInvocationOutput @args -OutputKind BareTokenSingleLine `
                -StandardOutput 'synthetic_token_value_1234567890' | Should -BeTrue
        }
        $refresh = @{} + $script:OutputArgs
        $refresh.HelperContext = 'mid-session-refresh'
        $refresh.TimeoutSeconds = 20
        Test-CddsiCredentialHelperInvocationOutput @refresh -OutputKind BareTokenSingleLine `
            -StandardOutput 'synthetic_token_value_1234567890' | Should -BeTrue
        $refresh.PromptObserved = $true
        Test-CddsiCredentialHelperInvocationOutput @refresh -OutputKind BareTokenSingleLine `
            -StandardOutput 'synthetic_token_value_1234567890' | Should -BeFalse
    }

    It 'rejects arguments, shell, stdin, multiline output, stderr, timeout, TTL, exit, hash and path drift' {
        foreach ($mutation in @(
            @{ ArgumentCount = 1 }, @{ ShellInvocation = $true }, @{ StandardInputRead = $true },
            @{ PromptObserved = $true }, @{ HelperContext = 'mid-session-refresh' },
            @{ StandardError = 'synthetic diagnostic' }, @{ ExitCode = 1 }, @{ InvocationStatus = 'TimedOut' },
            @{ ElapsedMilliseconds = 60001L }, @{ TimeoutSeconds = 59 }, @{ TtlSeconds = 3599 },
            @{ ObservedHelperPeSha256 = ('e' * 64) }, @{ ObservedInstalledExecutablePathToken = ('e' * 64) }
        )) {
            $args = @{} + $script:OutputArgs
            foreach ($name in $mutation.Keys) { $args[$name] = $mutation[$name] }
            Test-CddsiCredentialHelperInvocationOutput @args -OutputKind BareTokenSingleLine `
                -StandardOutput 'synthetic_token_value_1234567890' | Should -BeFalse
        }
        Test-CddsiCredentialHelperInvocationOutput @script:OutputArgs -OutputKind BareTokenSingleLine `
            -StandardOutput "synthetic_token_value_1234567890`n" | Should -BeFalse
    }

    It 'accepts a fresh non-secret receipt and rejects replay or contract drift' {
        Test-CddsiCredentialHelperInvocationEvidence -Evidence $script:Invocation -ExpectedCandidateEvidence $script:Candidate `
            -ExpectedInvocationId '10000000-0000-4000-8000-000000000008' `
            -ExpectedInvocationChallenge '10000000-0000-4000-8000-000000000009' `
            -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeTrue
        foreach ($mutation in @(
            @{ InvocationChallenge = '10000000-0000-4000-8000-000000000010' },
            @{ HelperContext = 'mid-session-refresh' }, @{ PromptObserved = $true },
            @{ ArgumentCount = 1 }, @{ ShellInvocation = $true }, @{ OutputPersisted = $true },
            @{ OutputDigestPersisted = $true }, @{ StandardErrorEmpty = $false }, @{ TtlSeconds = 3599 },
            @{ ObservedPeSha256 = ('e' * 64) }, @{ ProtocolVersion = 'cddsi-credential-helper-protocol-v2' }
        )) {
            $copy = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Invocation
            foreach ($name in $mutation.Keys) { $copy.$name = $mutation[$name] }
            $copy.BindingToken = Get-CddsiCredentialHelperInvocationEvidenceBindingToken -Evidence $copy
            Test-CddsiCredentialHelperInvocationEvidence -Evidence $copy -ExpectedCandidateEvidence $script:Candidate `
                -ExpectedInvocationId '10000000-0000-4000-8000-000000000008' `
                -ExpectedInvocationChallenge '10000000-0000-4000-8000-000000000009' `
                -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
        }

        $refresh = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Invocation
        $refresh.HelperContext = 'mid-session-refresh'
        $refresh.TimeoutSeconds = 20
        $refresh.BindingToken = Get-CddsiCredentialHelperInvocationEvidenceBindingToken -Evidence $refresh
        Test-CddsiCredentialHelperInvocationEvidence -Evidence $refresh -ExpectedCandidateEvidence $script:Candidate `
            -ExpectedInvocationId '10000000-0000-4000-8000-000000000008' `
            -ExpectedInvocationChallenge '10000000-0000-4000-8000-000000000009' `
            -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeTrue

        $unbounded = Copy-CddsiCredentialHelperReleaseFixture -Value $script:Invocation
        $unbounded.StartedAtUtc = '2029-01-01T00:03:10Z'
        $unbounded.BindingToken = Get-CddsiCredentialHelperInvocationEvidenceBindingToken -Evidence $unbounded
        Test-CddsiCredentialHelperInvocationEvidence -Evidence $unbounded -ExpectedCandidateEvidence $script:Candidate `
            -ExpectedInvocationId '10000000-0000-4000-8000-000000000008' `
            -ExpectedInvocationChallenge '10000000-0000-4000-8000-000000000009' `
            -ValidationTimeUtc $script:ValidationTimeUtc | Should -BeFalse
    }
}
