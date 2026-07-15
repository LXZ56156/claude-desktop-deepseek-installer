BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\execution-context.ps1')

    function New-CddsiCommonTestDescriptor {
        param([string]$ArtifactType = 'ClaudeDesktopMsix')

        $isMsix = $ArtifactType -ceq 'ClaudeDesktopMsix'
        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            DescriptorId = if ($isMsix) { 'synthetic-msix-descriptor' } else { 'synthetic-git-descriptor' }
            ArtifactType = $ArtifactType
            SourcePolicy = if ($isMsix) { 'anthropic_official_only' } else { 'git_for_windows_official_only' }
            SourceUri = if ($isMsix) { 'https://downloads.claude.com/synthetic-fixtures/Claude.msix' } else { 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.3/Git-2.53.0-64-bit.exe' }
            SourceUriBindingToken = $null
            ReleaseVersion = if ($isMsix) { '1.20186.0' } else { '2.53.0' }
            Architecture = 'x64'
            Channel = if ($isMsix) { 'Standard' } else { 'Installer' }
            FileNameToken = if ($isMsix) { '<ARTIFACT_FILE:CLAUDE_X64_STANDARD>' } else { '<ARTIFACT_FILE:GIT_X64_INSTALLER>' }
            ExpectedArtifactSha256 = ('a' * 64)
            ExpectedArtifactSizeBytes = [long]1000
            ExpectedSignerThumbprint = ('1' * 40)
            ExpectedSignerSubjectToken = '<SIGNER_SUBJECT:SYNTHETIC>'
            ExpectedPublisherToken = '<PUBLISHER:SYNTHETIC>'
            ExpectedIdentityToken = '<IDENTITY:SYNTHETIC>'
            RedirectPolicy = 'same-owner-https-only'
            MaximumBytes = [long]2000
            MetadataStatus = 'READY'
        }
        $withoutBinding.SourceUriBindingToken = Get-CddsiSourceUriBindingToken -SourceUri $withoutBinding.SourceUri
        $descriptor = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) { $descriptor[$property.Name] = $property.Value }
        $descriptor['MetadataBindingToken'] = Get-CddsiArtifactDescriptorBindingToken -Descriptor $withoutBinding
        return [pscustomobject]$descriptor
    }

    function New-CddsiCommonTestSourceObservation {
        param($Descriptor, [string]$RunId = '20000000-0000-4000-8000-000000000401', [string]$ArtifactProfile = 'VmAcceptance')

        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-source-observation-v1'; RunId = $RunId; ArtifactProfile = $ArtifactProfile
            DescriptorId = $Descriptor.DescriptorId; MetadataBindingToken = $Descriptor.MetadataBindingToken
            RequestUri = $Descriptor.SourceUri; FinalUri = $Descriptor.SourceUri; RedirectUris = @()
            RedirectChainBindingToken = Get-CddsiSupplyChainTextBindingToken -Text $Descriptor.SourceUri
            RedirectCount = 0; ArtifactSha256 = $Descriptor.ExpectedArtifactSha256
            ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes; ObservationId = 'synthetic-source-observation'
            ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
        $result = [ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) { $result[$property.Name] = $property.Value }
        $result['SourceObservationBindingToken'] = Get-CddsiSourceObservationBindingToken -Observation $withoutBinding
        return [pscustomobject]$result
    }

    function New-CddsiCommonTestEvidence {
        param([string]$Path, $Descriptor, $SourceObservation, [string]$RunId = '20000000-0000-4000-8000-000000000401', [string]$ArtifactProfile = 'VmAcceptance')

        $fileObservation = [pscustomobject]@{ SchemaVersion = 1; FileIdentityToken = ('f' * 64); ArtifactSha256 = $Descriptor.ExpectedArtifactSha256; ArtifactSizeBytes = $Descriptor.ExpectedArtifactSizeBytes }
        $signatureObservation = [pscustomobject]@{
            SchemaVersion = 1; ArtifactSha256 = $Descriptor.ExpectedArtifactSha256; AuthenticodeStatus = 'Valid'; ChainTrusted = $true
            SignerThumbprint = $Descriptor.ExpectedSignerThumbprint; SignerSubjectToken = $Descriptor.ExpectedSignerSubjectToken
            PublisherToken = $Descriptor.ExpectedPublisherToken; IdentityToken = $Descriptor.ExpectedIdentityToken
            Architecture = $Descriptor.Architecture; ArtifactVersion = $Descriptor.ReleaseVersion
            ObservationId = 'synthetic-observation'; ObservedAtUtc = '2030-01-01T00:00:00Z'
        }
        return New-CddsiSignatureEvidenceVerdict -Descriptor $Descriptor -ExpectedArtifactType $Descriptor.ArtifactType -PathBindingToken (Get-CddsiPathBindingToken -Path $Path) -SourceObservation $SourceObservation -FileObservation $fileObservation -SignatureObservation $signatureObservation -ExpectedRunId $RunId -ExpectedProfile $ArtifactProfile -ValidationTimeUtc '2030-01-01T00:00:01Z'
    }
}

Describe 'common safety helpers' {
    It 'defaults to TestSafe and rejects conflicting modes' {
        (Resolve-CddsiExecutionMode) | Should -Be 'TestSafe'
        (Resolve-CddsiExecutionMode -DryRun) | Should -Be 'DryRun'
        { Resolve-CddsiExecutionMode -TestSafe -Live } | Should -Throw
    }

    It 'keeps all real mutation disabled during scaffold stage' {
        Mock Assert-CddsiExecutionContext { return $true }
        $context = [pscustomobject]@{ Mode = 'Live' }
        (Test-CddsiRealMutationAllowed -ExecutionContext $context -Mode Live -AcknowledgeRealChanges) | Should -BeFalse
        { Assert-CddsiMutationAllowed -ExecutionContext $context -Operation 'probe' -Mode Live -AcknowledgeRealChanges } | Should -Throw
    }

    It 'returns an exact D-019 result and derives Success only from SUCCEEDED' {
        $result = New-CddsiOperationResult -Operation 'probe' -Status 'ACTION_REQUIRED' -Mode DryRun
        $result.PSObject.Properties.Name | Should -Contain 'RestartRequired'
        $result.PSObject.Properties.Name | Should -Contain 'PlannedChanges'
        $result.Success | Should -BeFalse
        $result.Changed | Should -BeFalse
        (New-CddsiOperationResult -Operation 'probe' -Status 'SUCCEEDED' -Mode TestSafe).Success | Should -BeTrue
        { New-CddsiOperationResult -Operation 'probe' -Status 'planned' -Mode TestSafe } | Should -Throw
        { New-CddsiOperationResult -Operation 'probe' -Status 'SUCCEEDED' -Mode DryRun -Changed $true } | Should -Throw
        (Get-Command New-CddsiOperationResult).Parameters.Keys | Should -Not -Contain 'Success'
    }

    It 'redacts complete key material without retaining a suffix' {
        $key = 'sk-' + ('A' * 32)
        $safe = Protect-CddsiSecret -Text ("credential=$key")
        $safe | Should -Not -Match ([regex]::Escape($key))
        $safe | Should -Match '\[REDACTED\]'
        $safe | Should -Not -Match 'AAAA'
    }

    It 'finds a synthetic key but never returns the raw match' {
        $key = 'sk-' + ('B' * 31) + '-'
        $findings = @(Find-CddsiPotentialSecrets -Content ("line`n$key") -Source 'memory')
        $findings.Count | Should -Be 1
        $findings[0].Line | Should -Be 2
        ($findings | ConvertTo-Json -Depth 5) | Should -Not -Match ([regex]::Escape($key))
    }

    It 'detects and fully redacts JSON credentials authorization and private keys' {
        $token = 'T' * 32
        $privateLabel = 'PRIVATE' + ' KEY'
        $content = "{`"apiKey`":`"$token`"}`nauthorization=$token`n-----BEGIN $privateLabel-----`n$token`n-----END $privateLabel-----"
        $findings = @(Find-CddsiPotentialSecrets -Content $content -Source 'synthetic')
        @($findings.Type) | Should -Contain 'CredentialAssignment'
        @($findings.Type) | Should -Contain 'PrivateKey'
        ($findings | ConvertTo-Json -Depth 5) | Should -Not -Match $token
        (Protect-CddsiSecret -Text $content) | Should -Not -Match $token
        (Protect-CddsiLogMessage -Message $content) | Should -Not -Match $token
    }

    It 'validates without silently trimming API key input' {
        $key = 'sk-' + ('C' * 24)
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey $key) | Should -BeTrue
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey ('z' * 24)) | Should -BeTrue
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey ('x' * 19)) | Should -BeFalse
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey ('x' * 513)) | Should -BeFalse
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey (" $key")) | Should -BeFalse
        (Test-CddsiDeepSeekApiKeyFormat -ApiKey ($key + "`n")) | Should -BeFalse
    }

    It 'accepts only canonical lowercase non-empty UUID values for cross-module grants' {
        (Test-CddsiCanonicalUuidValue -Value '10000000-0000-4000-8000-000000000501') | Should -BeTrue
        (Test-CddsiCanonicalUuidValue -Value '1a000000-0000-4000-8000-000000000501'.ToUpperInvariant()) | Should -BeFalse
        (Test-CddsiCanonicalUuidValue -Value '00000000-0000-0000-0000-000000000000') | Should -BeFalse
        (Test-CddsiCanonicalUuidValue -Value 'grant-10000000-0000-4000-8000-000000000501') | Should -BeFalse
    }

    It 'accepts only invariant Z-form UTC timestamp strings' {
        (Test-CddsiUtcTimestampValue -Value '2030-01-01T00:00:00Z') | Should -BeTrue
        (Test-CddsiUtcTimestampValue -Value '2030-01-01T00:00:00.1234567Z') | Should -BeTrue
        (Test-CddsiUtcTimestampValue -Value '2030-01-01T00:00:00+00:00') | Should -BeFalse
        (Test-CddsiUtcTimestampValue -Value '01/01/2030 00:00:00Z') | Should -BeFalse
        (Test-CddsiUtcTimestampValue -Value '2030-02-30T00:00:00Z') | Should -BeFalse
    }

    It 'rejects forged or incomplete signature evidence' {
        $path = Join-Path $TestDrive 'Claude.msix'
        $descriptor = New-CddsiCommonTestDescriptor
        $sourceObservation = New-CddsiCommonTestSourceObservation -Descriptor $descriptor
        $runId = $sourceObservation.RunId
        $validationTimeUtc = '2030-01-01T00:00:01Z'
        (Test-CddsiSignatureEvidence -Evidence ([pscustomobject]@{ Valid = $true }) -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse
        $v1Evidence = [pscustomobject]@{
            SchemaVersion = 1
            ArtifactType = 'ClaudeDesktopMsix'
            PathBindingToken = Get-CddsiPathBindingToken -Path $path
            ArtifactSha256 = ('a' * 64)
            Valid = $true
            AuthenticodeStatus = 'Valid'
            ChainTrusted = $true
            PublisherMatch = $true
            IdentityMatch = $true
            SourcePolicy = 'anthropic_official_only'
        }
        (Test-CddsiSignatureEvidence -Evidence $v1Evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse
        $evidence = New-CddsiCommonTestEvidence -Path $path -Descriptor $descriptor -SourceObservation $sourceObservation -RunId $runId
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeTrue
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath (Join-Path $TestDrive 'Other.msix') -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse
        $evidence.Valid = 'true'
        $evidence.SchemaVersion = '1'
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse
    }

    It 'compares provider-supplied artifact hashes without reading a file' {
        $expected = 'a' * 64
        (Test-CddsiArtifactHashBinding -ActualSha256 ('A' * 64) -ExpectedSha256 $expected) | Should -BeTrue
        (Test-CddsiArtifactHashBinding -ActualSha256 ('b' * 64) -ExpectedSha256 $expected) | Should -BeFalse
        (Test-CddsiArtifactHashBinding -ActualSha256 'invalid' -ExpectedSha256 $expected) | Should -BeFalse
    }

    It 'accepts only exact official artifact routes without query fragments or encoded traversal' {
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://downloads.claude.com/releases/Claude.msix' -ExpectedOwner Anthropic) | Should -BeTrue
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://downloads.claude.ai/windows/Claude.msix' -ExpectedOwner Anthropic) | Should -BeTrue
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://claude.ai/api/desktop/win32/x64/latest/redirect' -ExpectedOwner Anthropic) | Should -BeTrue
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://downloads.claude.com/releases/Claude.msix?token=synthetic' -ExpectedOwner Anthropic) | Should -BeFalse
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://downloads.claude.com:8443/releases/Claude.msix' -ExpectedOwner Anthropic) | Should -BeFalse
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://downloads.claude.com/releases/../Other.msix' -ExpectedOwner Anthropic) | Should -BeFalse
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://downloads.claude.com/releases/%00Claude.msix' -ExpectedOwner Anthropic) | Should -BeFalse
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://evil.claude.com/releases/Claude.msix' -ExpectedOwner Anthropic) | Should -BeFalse
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.3/Git-2.53.0-64-bit.exe' -ExpectedOwner GitForWindows) | Should -BeTrue
        (Test-CddsiOfficialArtifactUri -SourceUri 'https://github.com/git-for-windows/git/releases/download/v2.53.0.windows.3/%252e%252e.exe' -ExpectedOwner GitForWindows) | Should -BeFalse
        { Get-CddsiSourceUriBindingToken -SourceUri 'https://downloads.claude.com/releases/Claude.msix?token=synthetic' } | Should -Throw
        { Get-CddsiSourceUriBindingToken -SourceUri 'https://downloads.claude.com/releases/../Other.msix' } | Should -Throw
    }

    It 'binds source provenance and rejects future or cross-run observations' {
        $descriptor = New-CddsiCommonTestDescriptor
        $source = New-CddsiCommonTestSourceObservation -Descriptor $descriptor
        (Test-CddsiSourceObservation -Observation $source -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -ExpectedRunId $source.RunId -ExpectedProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z') | Should -BeTrue
        (Test-CddsiSourceObservation -Observation $source -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -ExpectedRunId $source.RunId -ExpectedProfile UserLive -ValidationTimeUtc '2030-01-01T00:00:01Z') | Should -BeFalse
        (Test-CddsiSourceObservation -Observation $source -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -ExpectedRunId $source.RunId -ExpectedProfile VmAcceptance -ValidationTimeUtc '2029-12-31T23:59:59Z') | Should -BeFalse
        (Test-CddsiSourceObservation -Observation $source -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -ExpectedRunId '20000000-0000-4000-8000-000000000499' -ExpectedProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z') | Should -BeFalse
        $tampered = $source | ConvertTo-Json -Depth 8 | ConvertFrom-Json
        $tampered.FinalUri = 'https://downloads.claude.ai/windows/Other.msix'
        (Test-CddsiSourceObservation -Observation $tampered -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -ExpectedRunId $source.RunId -ExpectedProfile VmAcceptance -ValidationTimeUtc '2030-01-01T00:00:01Z') | Should -BeFalse
    }

    It 'rejects descriptor channel mismatches and artifacts larger than the declared cap' {
        $descriptor = New-CddsiCommonTestDescriptor
        $descriptor.Channel = 'Installer'
        $descriptor.MetadataBindingToken = Get-CddsiArtifactDescriptorBindingToken -Descriptor $descriptor
        (Test-CddsiArtifactDescriptor -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -RequireResolved) | Should -BeFalse

        $descriptor = New-CddsiCommonTestDescriptor
        $descriptor.MaximumBytes = [long]999
        $descriptor.MetadataBindingToken = Get-CddsiArtifactDescriptorBindingToken -Descriptor $descriptor
        (Test-CddsiArtifactDescriptor -Descriptor $descriptor -ExpectedArtifactType ClaudeDesktopMsix -RequireResolved) | Should -BeFalse
    }

    It 'binds only explicit absolute artifact paths' {
        { Get-CddsiPathBindingToken -Path 'relative\artifact.msix' } | Should -Throw
        (Get-CddsiPathBindingToken -Path 'C:\Synthetic\artifact.msix') | Should -Match '^[a-f0-9]{64}$'
    }

    It 'requires an exact signature-evidence schema and absolute target binding' {
        $path = 'C:\Synthetic\artifact.msix'
        $descriptor = New-CddsiCommonTestDescriptor
        $sourceObservation = New-CddsiCommonTestSourceObservation -Descriptor $descriptor
        $runId = $sourceObservation.RunId
        $validationTimeUtc = '2030-01-01T00:00:01Z'
        $evidence = New-CddsiCommonTestEvidence -Path $path -Descriptor $descriptor -SourceObservation $sourceObservation -RunId $runId
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeTrue
        $evidence | Add-Member -NotePropertyName Bypass -NotePropertyValue $true
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse
        $evidence.PSObject.Properties.Remove('Bypass')
        (Test-CddsiSignatureEvidence -Evidence $evidence -ExpectedPath 'relative.msix' -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse

        $failedWrapper = New-CddsiOperationResult -Operation Verify -Status FAILED -Data $evidence
        (Test-CddsiSignatureEvidence -Evidence $failedWrapper -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeFalse
        $successfulWrapper = New-CddsiOperationResult -Operation Verify -Status SUCCEEDED -Data $evidence
        (Test-CddsiSignatureEvidence -Evidence $successfulWrapper -ExpectedPath $path -ExpectedArtifactType ClaudeDesktopMsix -Descriptor $descriptor -SourceObservation $sourceObservation -ExpectedRunId $runId -ExpectedProfile VmAcceptance -ValidationTimeUtc $validationTimeUtc) | Should -BeTrue
    }

    It 'keeps logger initialization side-effect free and disables file sinks in P1' {
        $context = [pscustomobject]@{ Mode = 'TestSafe' }
        $pathTokens = [ordered]@{
            '%LOCALAPPDATA%' = 'C:\SyntheticProfile\AppData\Local'
            '%USERPROFILE%' = 'C:\SyntheticProfile'
            '%USERNAME%' = 'SyntheticUser'
            '%TEMP%' = 'C:\SyntheticTemp'
        }
        (Initialize-CddsiConsoleEncoding) | Should -BeFalse
        { Initialize-CddsiLogger -ExecutionContext $context -EnableFileLogging -Mode TestSafe } | Should -Throw
        { Initialize-CddsiLogger -ExecutionContext ([pscustomobject]@{ Mode = 'DryRun' }) -Mode TestSafe } | Should -Throw
        Initialize-CddsiLogger -ExecutionContext $context -Mode TestSafe | Should -BeNullOrEmpty
        { Write-CddsiLog -ExecutionContext $context -Message 'must fail closed' } | Should -Throw
        Initialize-CddsiLogger -ExecutionContext $context -Mode TestSafe -PathTokenValues $pathTokens | Should -BeNullOrEmpty
        Get-CddsiLogPath | Should -BeNullOrEmpty

        $token = 'L' * 32
        $output = Write-CddsiLog -ExecutionContext $context -Level INFO -TimestampUtc '2030-01-01T00:00:00Z' -Message ("authorization=$token path=C:\SyntheticProfile\secret.txt") 6>&1 | Out-String
        $output | Should -Not -Match $token
        $output | Should -Not -Match 'SyntheticProfile'
        $output | Should -Match '\[REDACTED\]'
        $output | Should -Match '%USERPROFILE%'
    }

    It 'parses caller-supplied JSON without reading a path' {
        (ConvertFrom-CddsiJson -Content '{"schemaVersion":1}').schemaVersion | Should -Be 1
        { ConvertFrom-CddsiJson -Content '{' -Source '<synthetic>' } | Should -Throw
    }

    It 'creates an in-memory Chinese acceptance report with path user and credential redaction' {
        $token = 'sk-' + ('R' * 24)
        $syntheticUser = 'SyntheticUser'
        $syntheticProfile = 'C:\SyntheticProfile'
        $userPath = Join-Path $syntheticProfile 'secret.txt'
        $result = [pscustomobject]@{ status = '通过'; path = $userPath; user = $syntheticUser; authorization = $token }
        $pathTokens = [ordered]@{
            '%LOCALAPPDATA%' = 'C:\SyntheticProfile\AppData\Local'
            '%USERPROFILE%' = $syntheticProfile
            '%USERNAME%' = $syntheticUser
            '%TEMP%' = 'C:\SyntheticTemp'
        }
        $report = New-CddsiAcceptanceReport -Results $result -PathTokenValues $pathTokens
        $report.language | Should -Be 'zh-CN'
        $report.redacted | Should -BeTrue
        $report.persisted | Should -BeFalse
        $report.content | Should -Match '验收报告'
        $report.content | Should -Not -Match ([regex]::Escape($token))
        $report.content | Should -Not -Match ([regex]::Escape($syntheticUser))
        $report.content | Should -Not -Match ([regex]::Escape($syntheticProfile))
    }
}
