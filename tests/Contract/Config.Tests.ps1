BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')
    $fixturePath = Join-Path $script:RepoRoot 'tests\Fixtures\claude-desktop-3p-contract-v1.json'
    $defaultsPath = Join-Path $script:RepoRoot 'config\deepseek-desktop.defaults.json'
    $script:ConfigFixture = [System.IO.File]::ReadAllText($fixturePath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json
    $script:Defaults = [System.IO.File]::ReadAllText($defaultsPath, [System.Text.Encoding]::UTF8) | ConvertFrom-Json

    function New-CddsiSyntheticSourceMetadata {
        param(
            [bool]$HklmPresent,
            [bool]$HkcuPresent,
            [bool]$ConfigLibraryPresent
        )

        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            HklmManagedPolicy = [pscustomobject][ordered]@{
                Present   = $HklmPresent
                Ownership = if ($HklmPresent) { 'UNKNOWN' } else { 'NONE' }
            }
            HkcuManagedPolicy = [pscustomobject][ordered]@{
                Present   = $HkcuPresent
                Ownership = if ($HkcuPresent) { 'UNKNOWN' } else { 'NONE' }
            }
            ConfigLibrary = [pscustomobject][ordered]@{
                Present   = $ConfigLibraryPresent
                Ownership = if ($ConfigLibraryPresent) { 'UNKNOWN' } else { 'NONE' }
            }
        }
    }

    function ConvertTo-CddsiFixtureUtcText {
        param($Value)

        if ($Value -is [datetime]) {
            return $Value.ToUniversalTime().ToString('yyyy-MM-ddTHH:mm:ssZ', [System.Globalization.CultureInfo]::InvariantCulture)
        }
        return [string]$Value
    }

    function New-CddsiSyntheticConfigStageContext {
        param([int]$IdentityBase = 300)

        $operations = @('BackupManagedPolicy', 'WriteManagedPolicy')
        $bindings = @()
        for ($index = 0; $index -lt $operations.Count; $index++) {
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-operation-confirmation-binding-v1'
                ConfirmationId = '50000000-0000-4000-8000-{0}' -f (($IdentityBase + $index + 1).ToString('000000000000'))
                Operation = $operations[$index]
                PromptDigest = (($index + 1).ToString('x')).PadLeft(64, '0')
                Required = $true
            }
        }
        $manifest = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-stage-manifest-v1'; Stage = 'VmAcceptance'; ArtifactProfile = 'VmAcceptance'
            ArtifactVersion = '1.2.3'; CommitId = ('a' * 40); ArtifactSha256 = ('b' * 64); SidecarSha256 = ('d' * 64)
            ContentDigest = ('c' * 64); CreatedAtUtc = '2030-01-01T00:00:00Z'
        }
        $grant = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-operation-grant-v2'; GrantId = ('10000000-0000-4000-8000-{0}' -f (($IdentityBase + 2).ToString('000000000000')))
            ArtifactSha256 = $manifest.ArtifactSha256; SidecarSha256 = $manifest.SidecarSha256; ContentDigest = $manifest.ContentDigest
            ArtifactProfile = 'VmAcceptance'; RunId = ('20000000-0000-4000-8000-{0}' -f (($IdentityBase + 2).ToString('000000000000')))
            IssuedAtUtc = '2030-01-01T00:00:00Z'; ExpiresAtUtc = '2030-01-01T01:00:00Z'
            Nonce = ('30000000-0000-4000-8000-{0}' -f (($IdentityBase + 2).ToString('000000000000'))); AllowedOperations = @($operations); SingleUse = $true
            ConfirmationBindings = @($bindings)
        }
        $session = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-authorization-session-v1'; State = 'CLAIMED'
            GrantId = $grant.GrantId; Nonce = $grant.Nonce; ClaimId = ('40000000-0000-4000-8000-{0}' -f (($IdentityBase + 2).ToString('000000000000')))
            RunId = $grant.RunId; ArtifactSha256 = $grant.ArtifactSha256; SidecarSha256 = $grant.SidecarSha256
            ContentDigest = $grant.ContentDigest; ArtifactProfile = $grant.ArtifactProfile
            ClaimedAtUtc = '2030-01-01T00:01:00Z'; ExpiresAtUtc = $grant.ExpiresAtUtc; Revision = 1
        }
        $workflow = New-CddsiWorkflowSessionState -StageManifest $manifest -OperationGrant $grant -AuthorizationSession $session
        return [pscustomobject][ordered]@{ StageManifest = $manifest; OperationGrant = $grant; AuthorizationSession = $session; WorkflowSessionState = $workflow }
    }

    function New-CddsiSyntheticConfigAuthorizationBundle {
        param(
            [Parameter(Mandatory = $true)]$StageContext,
            [Parameter(Mandatory = $true)][string]$Operation,
            [Parameter(Mandatory = $true)][string]$OperationUseId,
            [Parameter(Mandatory = $true)][string]$ClaimedAtUtc
        )

        $grant = $StageContext.OperationGrant
        $session = $StageContext.AuthorizationSession
        $binding = @($grant.ConfirmationBindings | Where-Object { $_.Operation -ceq $Operation })[0]
        $confirmation = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-interactive-confirmation-v2'; ConfirmationId = $binding.ConfirmationId
            GrantId = $grant.GrantId; ClaimId = $session.ClaimId; PromptDigest = $binding.PromptDigest
            ArtifactSha256 = $grant.ArtifactSha256; SidecarSha256 = $grant.SidecarSha256; ContentDigest = $grant.ContentDigest
            ArtifactProfile = $grant.ArtifactProfile; RunId = $grant.RunId; Nonce = $grant.Nonce; Operation = $Operation
            Confirmed = $true; ConfirmedAtUtc = ([DateTimeOffset]::Parse($ClaimedAtUtc).AddSeconds(-10)).ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $available = New-CddsiOperationUseState -StageManifest $StageContext.StageManifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $StageContext.WorkflowSessionState -Operation $Operation
        $proposal = Resolve-CddsiOperationAuthorization -StageManifest $StageContext.StageManifest -OperationGrant $grant `
            -AuthorizationSession $session -WorkflowSessionState $StageContext.WorkflowSessionState -OperationUseState $available `
            -Confirmation $confirmation -Operation $Operation -OperationUseId $OperationUseId -ExpectedRevision 0 `
            -RunId $grant.RunId -NowUtc $ClaimedAtUtc
        if (-not $proposal.Data.AuthorizationProposed) { throw 'synthetic operation-use claim failed' }
        return [pscustomobject][ordered]@{
            StageManifest = $StageContext.StageManifest
            OperationGrant = $grant
            AuthorizationSession = $session
            WorkflowSessionState = $StageContext.WorkflowSessionState
            OperationUseState = $proposal.Data.ProposedOperationUseState
        }
    }

    function Complete-CddsiSyntheticConfigAuthorizationBundle {
        param(
            [Parameter(Mandatory = $true)]$AuthorizationBundle,
            [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'ABORTED')][string]$Outcome,
            [Parameter(Mandatory = $true)][string]$ProviderEvidenceDigest,
            [Parameter(Mandatory = $true)][string]$OccurredAtUtc,
            [Parameter(Mandatory = $true)][string]$IdempotencyKey
        )

        $state = $AuthorizationBundle.OperationUseState
        $terminal = Resolve-CddsiOperationUseTerminal -StageManifest $AuthorizationBundle.StageManifest `
            -OperationGrant $AuthorizationBundle.OperationGrant -AuthorizationSession $AuthorizationBundle.AuthorizationSession `
            -WorkflowSessionState $AuthorizationBundle.WorkflowSessionState -OperationUseState $state `
            -Operation $state.Operation -OperationUseId $state.OperationUseId -ExpectedRevision 1 -Outcome $Outcome `
            -ProviderEvidenceDigest $ProviderEvidenceDigest -OccurredAtUtc $OccurredAtUtc -IdempotencyKey $IdempotencyKey `
            -TerminalReasonCode $(if ($Outcome -ceq 'ABORTED') { 'PROVIDER_FAILED' } else { '' })
        if (-not $terminal.Data.Terminalized) { throw 'synthetic operation-use terminalization failed' }
        return [pscustomobject][ordered]@{
            StageManifest = $AuthorizationBundle.StageManifest
            OperationGrant = $AuthorizationBundle.OperationGrant
            AuthorizationSession = $AuthorizationBundle.AuthorizationSession
            WorkflowSessionState = $AuthorizationBundle.WorkflowSessionState
            OperationUseState = $terminal.Data.TerminalOperationUseState
        }
    }

    function New-CddsiSyntheticConfigBackupEvidence {
        param([Parameter(Mandatory = $true)]$BackupAuthorization)

        $state = $BackupAuthorization.OperationUseState
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-config-backup-evidence-v2'; BindingToken = $null
            RunId = $state.RunId; ArtifactSha256 = $state.ArtifactSha256; SidecarSha256 = $state.SidecarSha256
            ContentDigest = $state.ContentDigest; Profile = $state.ArtifactProfile; GrantId = $state.GrantId; ClaimId = $state.ClaimId
            ConfirmationId = $state.ConfirmationId; Operation = 'BackupManagedPolicy'; OperationUseId = $state.OperationUseId
            OperationUseReceiptBindingToken = $state.ReceiptBindingToken
            BackupId = 'backup-90000000-0000-4000-8000-000000000301'; TargetSource = 'HKCU_MANAGED_POLICY'; RegistryKeyToken = '<HKCU_MANAGED_POLICY>'
            ValueCount = 0; ValueSetSha256 = ('8' * 64); BlobToken = '<CONFIG_BACKUP_BLOB:a0000000-0000-4000-8000-000000000301>'
            OwnerBindingToken = $null; ReadbackSha256 = ('8' * 64); ProtectionEvidenceSha256 = $null
            OperationNonce = '80000000-0000-4000-8000-000000000301'; CreatedAtUtc = '2030-01-01T00:03:00Z'
            Protection = 'DPAPI_CURRENT_USER'; AclPolicy = 'CURRENT_USER_ONLY'; OwnerBound = $true; Restorable = $true; RedactedSnapshot = $false
        }
        $evidence.OwnerBindingToken = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-config-backup-owner-v2', $evidence.RunId, $evidence.ArtifactSha256, $evidence.SidecarSha256,
            $evidence.ContentDigest, $evidence.Profile, $evidence.GrantId, $evidence.ClaimId,
            $evidence.OperationUseId, $evidence.BackupId, $evidence.BlobToken, $evidence.OperationNonce
        ) -join '|')
        $evidence.ProtectionEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-config-backup-provider-evidence-v2', $evidence.RunId, $evidence.ArtifactSha256,
            $evidence.SidecarSha256, $evidence.ContentDigest, $evidence.Profile, $evidence.GrantId,
            $evidence.ClaimId, $evidence.ConfirmationId, $evidence.Operation, $evidence.OperationUseId,
            $evidence.BackupId, $evidence.TargetSource, $evidence.RegistryKeyToken,
            [string]$evidence.ValueCount, $evidence.ValueSetSha256, $evidence.BlobToken,
            $evidence.OwnerBindingToken, $evidence.ReadbackSha256, $evidence.OperationNonce,
            $evidence.CreatedAtUtc, $evidence.Protection, $evidence.AclPolicy,
            ([string]$evidence.OwnerBound).ToLowerInvariant(),
            ([string]$evidence.Restorable).ToLowerInvariant(),
            ([string]$evidence.RedactedSnapshot).ToLowerInvariant()
        ) -join '|')
        $evidence.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken -Evidence $evidence
        return $evidence
    }

    function New-CddsiSyntheticConfigTransactionPlan {
        $stage = New-CddsiSyntheticConfigStageContext
        $backupClaim = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $stage -Operation BackupManagedPolicy `
            -OperationUseId '60000000-0000-4000-8000-000000000301' -ClaimedAtUtc '2030-01-01T00:02:00Z'
        $backupDraft = New-CddsiSyntheticConfigBackupEvidence -BackupAuthorization $backupClaim
        $backupTerminal = Complete-CddsiSyntheticConfigAuthorizationBundle -AuthorizationBundle $backupClaim -Outcome COMPLETED `
            -ProviderEvidenceDigest $backupDraft.ProtectionEvidenceSha256 -OccurredAtUtc '2030-01-01T00:04:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000301'
        $backupEvidence = New-CddsiSyntheticConfigBackupEvidence -BackupAuthorization $backupTerminal
        $writeClaim = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $stage -Operation WriteManagedPolicy `
            -OperationUseId '60000000-0000-4000-8000-000000000302' -ClaimedAtUtc '2030-01-01T00:05:00Z'
        $desired = New-CddsiClaudeDesktopDesiredConfig
        $current = New-CddsiSyntheticSourceMetadata -HklmPresent $false -HkcuPresent $false -ConfigLibraryPresent $false
        $decision = Compare-CddsiClaudeDesktopConfig -Current $current -Desired $desired
        $valueSet = ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet -Config $desired -CredentialHelperPath 'C:\cddsi-synthetic\credential\helper.exe'
        $plan = New-CddsiConfigTransactionPlan -SourceDecision $decision -ValueSet $valueSet -BackupEvidence $backupEvidence `
            -BackupAuthorization $backupTerminal -WriteAuthorization $writeClaim -ValidationTimeUtc '2030-01-01T00:05:00Z'
        return [pscustomobject][ordered]@{
            Plan = $plan; SourceDecision = $decision; ValueSet = $valueSet; BackupEvidence = $backupEvidence
            BackupAuthorization = $backupTerminal; WriteAuthorization = $writeClaim; StageContext = $stage
        }
    }

    function New-CddsiSyntheticConfigTransactionTranscript {
        param(
            [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)][object[]]$Events
        )

        return [pscustomobject][ordered]@{
            SchemaVersion = 2
            ContractVersion = 'cddsi-config-write-transaction-v2'
            PlanId = $Plan.PlanId
            RunId = $Plan.RunId
            ArtifactSha256 = $Plan.ArtifactSha256
            SidecarSha256 = $Plan.SidecarSha256
            ContentDigest = $Plan.ContentDigest
            Profile = $Plan.Profile
            GrantId = $Plan.GrantId
            ClaimId = $Plan.ClaimId
            TransactionId = $Plan.TransactionId
            BackupId = $Plan.BackupId
            BackupEvidenceBindingToken = $Plan.BackupEvidenceBindingToken
            BackupOperationUseId = $Plan.BackupOperationUseId
            WriteOperationUseId = $Plan.WriteOperationUseId
            Events = @($Events)
        }
    }

    function New-CddsiSyntheticConfigTransactionEvent {
        param(
            [Parameter(Mandatory = $true)][int]$Sequence,
            [Parameter(Mandatory = $true)][string]$Name,
            [ValidateSet('SUCCEEDED', 'FAILED')][string]$Outcome = 'SUCCEEDED',
            [ValidateSet('NONE', 'UNCHANGED', 'CHANGED', 'UNKNOWN')][string]$MutationState = 'NONE',
            [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)][string]$OccurredAtUtc
        )

        if (-not $PSBoundParameters.ContainsKey('MutationState') -and $Name -ceq 'policy_write') {
            $MutationState = if ($Outcome -ceq 'SUCCEEDED') { 'CHANGED' } else { 'UNKNOWN' }
        }
        $providerEvidence = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-config-provider-event-v2', $Plan.PlanId, $Plan.TransactionId, $Plan.WriteOperationUseId,
            [string]$Sequence, $Name, $Outcome, $MutationState, $OccurredAtUtc
        ) -join '|')
        return [pscustomobject][ordered]@{
            Sequence = $Sequence
            Name = $Name
            Outcome = $Outcome
            MutationState = $MutationState
            OccurredAtUtc = $OccurredAtUtc
            OperationUseId = $Plan.WriteOperationUseId
            ProviderEvidenceSha256 = $providerEvidence
        }
    }
}

Describe 'Claude Desktop 3P managed-policy contract' {
    It 'pins the official fixture applicability and source provenance' {
        $script:ConfigFixture.fixtureSchemaVersion | Should -Be 1
        $script:ConfigFixture.fixtureId | Should -BeExactly 'claude-desktop-3p-windows-managed-policy-v1'
        $script:ConfigFixture.contractVersion | Should -BeExactly 'claude-desktop-3p-managed-policy-v1'
        (ConvertTo-CddsiFixtureUtcText -Value $script:ConfigFixture.verifiedAtUtc) | Should -BeExactly '2026-07-14T00:00:00Z'
        $script:ConfigFixture.applicability.platform | Should -BeExactly 'Windows'
        $script:ConfigFixture.applicability.minimumDesktopVersion | Should -BeExactly '1.20186.0'
        $script:ConfigFixture.applicability.windowsPolicyNoMergeSince | Should -BeExactly '1.19367.0'
        $script:ConfigFixture.applicability.documentationBaselineVersion | Should -BeExactly '1.20186.0'
        $script:ConfigFixture.applicability.registryKey | Should -BeExactly 'HKCU\SOFTWARE\Policies\Claude'
        $script:ConfigFixture.applicability.registryValueType | Should -BeExactly 'REG_SZ'
        @($script:ConfigFixture.applicability.sourcePrecedence) -join '|' | Should -BeExactly 'HKLM_MANAGED_POLICY|HKCU_MANAGED_POLICY|CONFIG_LIBRARY'
        @($script:ConfigFixture.sources).Count | Should -Be 6
        foreach ($source in @($script:ConfigFixture.sources)) {
            $source.url | Should -Match '^https://(claude\.com|api-docs\.deepseek\.com)/'
            (ConvertTo-CddsiFixtureUtcText -Value $source.verifiedAtUtc) | Should -BeExactly '2026-07-14T00:00:00Z'
        }
    }

    It 'keeps defaults desired state and fixture on the same versioned contract' {
        $config = New-CddsiClaudeDesktopDesiredConfig
        (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeTrue
        $script:Defaults.schemaVersion | Should -Be 2
        $script:Defaults.projectStage | Should -BeExactly 'scaffold'
        $script:Defaults.desktop3p.contractVersion | Should -BeExactly $config.ContractVersion
        $script:Defaults.desktop3p.minimumDesktopVersion | Should -BeExactly $config.MinimumDesktopVersion
        $script:Defaults.desktop3p.windowsPolicyNoMergeSince | Should -BeExactly $config.WindowsPolicyNoMergeSince
        $script:Defaults.desktop3p.targetSource | Should -BeExactly $config.Ownership.TargetSource
        $script:Defaults.desktop3p.registryKey | Should -BeExactly 'HKCU\SOFTWARE\Policies\Claude'
        $script:Defaults.desktop3p.existingSourcePolicy | Should -BeExactly $config.Ownership.ExistingSourcePolicy
        $script:Defaults.desktop3p.configLibraryWriterEnabled | Should -BeFalse
        $script:Defaults.desktop3p.claudeCodeSettingsPolicy | Should -BeExactly 'do_not_read_or_modify'
        $script:Defaults.desktop3p.provider.kind | Should -BeExactly $config.Provider.Kind
        $script:Defaults.desktop3p.provider.baseUrl | Should -BeExactly $config.Provider.BaseUrl
        $script:Defaults.desktop3p.provider.authScheme | Should -BeExactly $config.Provider.AuthScheme
        $script:Defaults.desktop3p.modelPolicy.discoveryEnabled | Should -BeFalse
        $script:Defaults.desktop3p.modelPolicy.defaultModel | Should -BeExactly $config.ModelPolicy.DefaultModel
        @($script:Defaults.desktop3p.modelPolicy.models.name) -join '|' | Should -BeExactly 'deepseek-v4-pro|deepseek-v4-flash'
        @($script:Defaults.desktop3p.requestedSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        $script:Defaults.desktop3p.surfacePolicy.chatEnabled | Should -BeTrue
        $script:Defaults.desktop3p.surfacePolicy.codeEnabled | Should -BeTrue
        $script:Defaults.desktop3p.surfacePolicy.coworkEnabled | Should -BeTrue
        $script:Defaults.desktop3p.surfacePolicy.autoModeEnabled | Should -BeFalse
        $script:Defaults.desktop3p.deploymentChooserPolicy.disabled | Should -BeTrue
        $script:Defaults.desktop3p.credentialReference.kind | Should -BeExactly 'helper-script'
        $script:Defaults.desktop3p.credentialReference.helperBinding | Should -BeExactly '<CREDENTIAL_HELPER_PATH>'
        $script:Defaults.desktop3p.credentialReference.ttlSeconds | Should -Be 3600
        $script:Defaults.desktop3p.credentialReference.timeoutSeconds | Should -Be 60
        $script:Defaults.desktop3p.credentialReference.silentRefreshEnabled | Should -BeTrue
        $script:Defaults.desktop3p.credentialReference.persistInConfig | Should -BeFalse
        $script:Defaults.desktop3p.validationRequestEnabled | Should -BeFalse
    }

    It 'serializes an exact ordinal REG_SZ value set matching the fixture' {
        $helperPath = 'C:\cddsi-synthetic\credential\cddsi-credential-helper.exe'
        $valueSet = ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet -Config (New-CddsiClaudeDesktopDesiredConfig) -CredentialHelperPath $helperPath
        (Test-CddsiExactPropertySet -InputObject $valueSet -Expected @('SchemaVersion', 'ContractVersion', 'TargetSource', 'RegistryKey', 'Values')) | Should -BeTrue
        $valueSet.SchemaVersion | Should -Be 1
        $valueSet.ContractVersion | Should -BeExactly $script:ConfigFixture.contractVersion
        $valueSet.TargetSource | Should -BeExactly 'HKCU_MANAGED_POLICY'
        $valueSet.RegistryKey | Should -BeExactly 'HKCU\SOFTWARE\Policies\Claude'
        @($valueSet.Values).Count | Should -Be 15

        $actualNames = @($valueSet.Values.Name)
        $expectedNames = @($script:ConfigFixture.policyValues.Name)
        $actualNames -join "`n" | Should -BeExactly ($expectedNames -join "`n")
        foreach ($value in @($valueSet.Values)) {
            (Test-CddsiExactPropertySet -InputObject $value -Expected @('Name', 'Type', 'Data')) | Should -BeTrue
            $value.Type | Should -BeExactly 'REG_SZ'
            $value.Data | Should -BeOfType [string]
            $fixtureValue = @($script:ConfigFixture.policyValues | Where-Object { $_.Name -ceq $value.Name })
            @($fixtureValue).Count | Should -Be 1
            $expectedData = [string]$fixtureValue[0].Data
            if ($expectedData -ceq '<CREDENTIAL_HELPER_PATH>') { $expectedData = $helperPath }
            $value.Data | Should -BeExactly $expectedData
        }
        @($valueSet.Values | Where-Object { $_.Name -ceq 'inferenceModels' })[0].Data |
            Should -BeExactly '[{"name":"deepseek-v4-pro","labelOverride":"DeepSeek V4 Pro","supports1m":true},{"name":"deepseek-v4-flash","labelOverride":"DeepSeek V4 Flash","supports1m":true}]'
    }

    It 'keeps provider-side Claude alias mapping separate from unverified family-tier serialization' {
        $config = New-CddsiClaudeDesktopDesiredConfig
        $config.ModelPolicy.FamilyTierSerializationPolicy | Should -BeExactly 'omit_unverified_duplicate_model_binding'
        @($config.ModelPolicy.ProviderAliasMappings.Pattern) -join '|' |
            Should -BeExactly 'claude-opus-*|claude-sonnet-*|claude-haiku-*'
        @($config.ModelPolicy.ProviderAliasMappings.TargetModel) -join '|' |
            Should -BeExactly 'deepseek-v4-pro|deepseek-v4-flash|deepseek-v4-flash'
        $serializedModels = @((ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet -Config $config -CredentialHelperPath 'C:\cddsi-synthetic\credential\helper.exe').Values |
            Where-Object { $_.Name -ceq 'inferenceModels' })[0].Data
        $serializedModels | Should -Not -Match 'anthropicFamilyTier'
        $serializedModels | Should -Not -Match 'isFamilyDefault'
        $serializedModels | Should -Not -Match 'deepseek-chat|deepseek-reasoner'
    }

    It 'fails closed on every desired-state drift and credential material injection' {
        $mutators = @(
            { param($config) Add-Member -InputObject $config -NotePropertyName Unknown -NotePropertyValue $true },
            { param($config) $config.SchemaVersion = 3 },
            { param($config) $config.ContractVersion = 'unknown' },
            { param($config) $config.MinimumDesktopVersion = '1.19367.0' },
            { param($config) $config.Provider.Kind = 'DeepSeek' },
            { param($config) $config.Provider.BaseUrl = 'https://api.deepseek.com' },
            { param($config) $config.Provider.AuthScheme = 'bearer' },
            { param($config) $config.ModelPolicy.DiscoveryEnabled = $true },
            { param($config) $config.ModelPolicy.DefaultModel = 'deepseek-v4-flash' },
            { param($config) $config.ModelPolicy.Models[0].Name = 'deepseek-chat' },
            { param($config) $config.ModelPolicy.Models[1].Name = 'deepseek-reasoner' },
            { param($config) $config.ModelPolicy.Models[0].Supports1m = $false },
            { param($config) $config.ModelPolicy.ProviderAliasMappings[1].TargetModel = 'deepseek-v4-pro' },
            { param($config) $config.RequestedSurfaces = @('Chat') },
            { param($config) $config.SurfacePolicy.ChatEnabled = $false },
            { param($config) $config.SurfacePolicy.CodeEnabled = $false },
            { param($config) $config.SurfacePolicy.CoworkEnabled = $false },
            { param($config) $config.SurfacePolicy.AutoModeEnabled = $true },
            { param($config) $config.DeploymentChooserPolicy.Disabled = $false },
            { param($config) $config.CredentialReference.Kind = 'static' },
            { param($config) $config.CredentialReference.HelperBinding = ('s' + 'k-' + ('x' * 26)) },
            { param($config) $config.CredentialReference.TimeoutSeconds = 61 },
            { param($config) $config.CredentialReference.SilentRefreshEnabled = $false },
            { param($config) $config.CredentialReference.PersistInConfig = $true },
            { param($config) $config.Ownership.TargetSource = 'CONFIG_LIBRARY' },
            { param($config) $config.Ownership.ConfigLibraryWriterEnabled = $true }
        )
        foreach ($mutator in $mutators) {
            $config = New-CddsiClaudeDesktopDesiredConfig
            & $mutator $config
            (Test-CddsiClaudeDesktopConfigContract -Config $config) | Should -BeFalse
        }
        (Test-CddsiClaudeDesktopConfigContract -Config ([pscustomobject]@{ SchemaVersion = 2 })) | Should -BeFalse
    }

    It 'exposes no capability selector or readiness override parameters' {
        $desiredParameters = (Get-Command New-CddsiClaudeDesktopDesiredConfig).Parameters.Keys
        foreach ($forbidden in @('Models', 'Surfaces', 'RequestedSurfaces', 'Readiness', 'Capabilities')) {
            $desiredParameters -contains $forbidden | Should -BeFalse
        }
        $serializerParameters = (Get-Command ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet).Parameters.Keys
        foreach ($forbidden in @('Models', 'Surfaces', 'RequestedSurfaces', 'Readiness', 'Capabilities', 'TargetSource')) {
            $serializerParameters -contains $forbidden | Should -BeFalse
        }
    }

    It 'accepts only normalized local helper paths and never probes path existence' {
        $config = New-CddsiClaudeDesktopDesiredConfig
        $validPath = 'C:\cddsi-synthetic\credential\cddsi-credential-helper.exe'
        { ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet -Config $config -CredentialHelperPath $validPath } | Should -Not -Throw
        foreach ($invalidPath in @(
            'helper.exe',
            '\\server\share\helper.exe',
            'C:/unsafe/helper.exe',
            'C:\safe\..\helper.exe',
            'C:\safe\\helper.exe',
            "C:\safe`n\helper.exe",
            'C:\safe\helper.exe ',
            ('C:\safe\' + ('s' + 'k-' + ('x' * 26)) + '.exe')
        )) {
            { ConvertTo-CddsiClaudeDesktopManagedPolicyValueSet -Config $config -CredentialHelperPath $invalidPath } | Should -Throw
        }
    }

    It 'matches all eight synthetic source precedence cases without reading values' {
        foreach ($case in @($script:ConfigFixture.sourceResolutionCases)) {
            $current = New-CddsiSyntheticSourceMetadata -HklmPresent ([bool]$case.hklmPresent) -HkcuPresent ([bool]$case.hkcuPresent) -ConfigLibraryPresent ([bool]$case.configLibraryPresent)
            $result = Compare-CddsiClaudeDesktopConfig -Current $current -Desired (New-CddsiClaudeDesktopDesiredConfig)
            $result.Status | Should -BeExactly $case.status
            $result.ErrorCode | Should -BeExactly $case.errorCode
            $result.Changed | Should -BeFalse
            $result.Data.EffectiveSource | Should -BeExactly $case.effectiveSource
            @($result.Data.ExistingSources) -join '|' | Should -BeExactly (@($case.existingSources) -join '|')
            $result.Data.Conflict | Should -Be ([bool]$case.conflict)
            $result.Data.CanProceed | Should -Be ([bool]$case.canProceed)
            @($result.Data.ReasonCodes) -join '|' | Should -BeExactly (@($case.reasonCodes) -join '|')
        }
    }

    It 'rejects malformed or value-bearing source metadata' {
        $current = New-CddsiSyntheticSourceMetadata -HklmPresent $false -HkcuPresent $false -ConfigLibraryPresent $false
        $current.HklmManagedPolicy.Present = 'false'
        { Compare-CddsiClaudeDesktopConfig -Current $current -Desired (New-CddsiClaudeDesktopDesiredConfig) } | Should -Throw
        $current = New-CddsiSyntheticSourceMetadata -HklmPresent $false -HkcuPresent $false -ConfigLibraryPresent $false
        $current.HkcuManagedPolicy.Ownership = 'PROJECT'
        { Compare-CddsiClaudeDesktopConfig -Current $current -Desired (New-CddsiClaudeDesktopDesiredConfig) } | Should -Throw
        $current = New-CddsiSyntheticSourceMetadata -HklmPresent $true -HkcuPresent $false -ConfigLibraryPresent $false
        Add-Member -InputObject $current.HklmManagedPolicy -NotePropertyName Values -NotePropertyValue @{ inferenceProvider = 'gateway' }
        { Compare-CddsiClaudeDesktopConfig -Current $current -Desired (New-CddsiClaudeDesktopDesiredConfig) } | Should -Throw
        $current = New-CddsiSyntheticSourceMetadata -HklmPresent $false -HkcuPresent $false -ConfigLibraryPresent $false
        $desired = New-CddsiClaudeDesktopDesiredConfig
        $desired.SurfacePolicy.CodeEnabled = $false
        { Compare-CddsiClaudeDesktopConfig -Current $current -Desired $desired } | Should -Throw
    }

    It 'separates backup creation from the write transaction and requires independent authorization slots' {
        $fixture = New-CddsiSyntheticConfigTransactionPlan
        $plan = $fixture.Plan
        (Test-CddsiConfigBackupEvidence -Evidence $fixture.BackupEvidence -BackupAuthorization $fixture.BackupAuthorization) | Should -BeTrue
        @($plan.Steps) -join '|' | Should -BeExactly 'policy_write|policy_readback|commit'
        @($plan.Steps) | Should -Not -Contain 'backup_create'
        @($plan.RequiredAuthorizationSlots.Operation) -join '|' | Should -BeExactly 'RestoreManagedPolicy|RemoveManagedPolicyBackup'
        @($fixture.StageContext.OperationGrant.AllowedOperations) -join '|' | Should -BeExactly 'BackupManagedPolicy|WriteManagedPolicy'
        @($plan.RequiredAuthorizationSlots | Where-Object { $_.IssuancePhase -cne 'POST_WRITE_TERMINAL_ONLY' }).Count | Should -Be 0
        @($plan.RequiredAuthorizationSlots | Where-Object { -not $_.MustBindPrimaryTerminalReceipt }).Count | Should -Be 0
        $plan.BackupOperationUseId | Should -Not -Be $plan.WriteOperationUseId
        $plan.BackupAuthorizationReceiptBindingToken | Should -Not -Be $plan.WriteAuthorizationReceiptBindingToken

        $stage = New-CddsiSyntheticConfigStageContext
        $backupClaim = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $stage -Operation BackupManagedPolicy `
            -OperationUseId '60000000-0000-4000-8000-000000000311' -ClaimedAtUtc '2030-01-01T00:02:00Z'
        $backupPlan = New-CddsiConfigBackupPlan -SourceDecision $fixture.SourceDecision -BackupAuthorization $backupClaim `
            -BackupId 'backup-90000000-0000-4000-8000-000000000311' -OperationNonce '80000000-0000-4000-8000-000000000311' `
            -ValidationTimeUtc '2030-01-01T00:02:00Z'
        @($backupPlan.Steps) -join '|' | Should -BeExactly 'source_validated|backup_create|backup_readback|commit_backup'
        @($backupPlan.Steps) | Should -Not -Contain 'policy_write'
        $backupPlan.CleanupAuthorizationSlot.Operation | Should -BeExactly 'RemoveManagedPolicyBackup'
        $backupPlan.CleanupAuthorizationSlot.IssuancePhase | Should -BeExactly 'POST_BACKUP_TERMINAL_ONLY'
    }

    It 'binds immutable backup evidence to the terminal operation receipt owner and time window' {
        $fixture = New-CddsiSyntheticConfigTransactionPlan
        $evidence = $fixture.BackupEvidence
        (Test-CddsiConfigBackupEvidence -Evidence $evidence -BackupAuthorization $fixture.BackupAuthorization) | Should -BeTrue
        (Test-CddsiConfigBackupEvidence -Evidence $evidence -BackupAuthorization $fixture.WriteAuthorization) | Should -BeFalse

        foreach ($mutation in @(
            { param($candidate) $candidate.BindingToken = ('0' * 64) },
            { param($candidate) $candidate.OwnerBindingToken = ('0' * 64); $candidate.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken $candidate },
            { param($candidate) $candidate.ProtectionEvidenceSha256 = ('1' * 64); $candidate.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken $candidate },
            { param($candidate) $candidate.CreatedAtUtc = '2030-01-01T00:04:01Z'; $candidate.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken $candidate },
            { param($candidate) $candidate.OperationUseId = '60000000-0000-4000-8000-000000000399'; $candidate.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken $candidate },
            { param($candidate) $candidate.BackupId = 'backup-00000000000000000000000000000000'; $candidate.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken $candidate }
        )) {
            $candidate = $evidence | ConvertTo-Json -Depth 20 | ConvertFrom-Json
            & $mutation $candidate
            (Test-CddsiConfigBackupEvidence -Evidence $candidate -BackupAuthorization $fixture.BackupAuthorization) | Should -BeFalse
        }

        $arbitraryClaim = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $fixture.StageContext -Operation BackupManagedPolicy `
            -OperationUseId '60000000-0000-4000-8000-000000000399' -ClaimedAtUtc '2030-01-01T00:02:00Z'
        $arbitraryTerminal = Complete-CddsiSyntheticConfigAuthorizationBundle -AuthorizationBundle $arbitraryClaim -Outcome COMPLETED `
            -ProviderEvidenceDigest ('1' * 64) -OccurredAtUtc '2030-01-01T00:04:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000399'
        $arbitraryEvidence = New-CddsiSyntheticConfigBackupEvidence -BackupAuthorization $arbitraryTerminal
        $arbitraryEvidence.ProtectionEvidenceSha256 = ('1' * 64)
        $arbitraryEvidence.BindingToken = Get-CddsiConfigBackupEvidenceBindingToken -Evidence $arbitraryEvidence
        (Test-CddsiConfigBackupEvidence -Evidence $arbitraryEvidence -BackupAuthorization $arbitraryTerminal) | Should -BeFalse
    }

    It 'rejects authorization swaps source drift and malformed managed policy values' {
        $fixture = New-CddsiSyntheticConfigTransactionPlan
        $plan = $fixture.Plan
        $plan.PlanId | Should -Match '^[a-f0-9]{64}$'
        $plan.TransactionId | Should -Match '^[a-f0-9]{64}$'
        $plan.RunId | Should -BeExactly '20000000-0000-4000-8000-000000000302'

        { New-CddsiConfigTransactionPlan -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.WriteAuthorization -WriteAuthorization $fixture.WriteAuthorization -ValidationTimeUtc $plan.ValidationTimeUtc } | Should -Throw
        { New-CddsiConfigTransactionPlan -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $fixture.BackupAuthorization -ValidationTimeUtc $plan.ValidationTimeUtc } | Should -Throw

        $conflict = Compare-CddsiClaudeDesktopConfig -Current (New-CddsiSyntheticSourceMetadata -HklmPresent $true -HkcuPresent $false -ConfigLibraryPresent $false) -Desired (New-CddsiClaudeDesktopDesiredConfig)
        { New-CddsiConfigTransactionPlan -SourceDecision $conflict -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $fixture.WriteAuthorization -ValidationTimeUtc $plan.ValidationTimeUtc } | Should -Throw

        $nullValues = $fixture.ValueSet | ConvertTo-Json -Depth 20 | ConvertFrom-Json
        $nullValues.Values = @(1..15 | ForEach-Object { $null })
        { New-CddsiConfigTransactionPlan -SourceDecision $fixture.SourceDecision -ValueSet $nullValues -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $fixture.WriteAuthorization -ValidationTimeUtc $plan.ValidationTimeUtc } | Should -Throw

        $earlyWrite = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $fixture.StageContext -Operation WriteManagedPolicy `
            -OperationUseId '60000000-0000-4000-8000-000000000398' -ClaimedAtUtc '2030-01-01T00:03:00Z'
        { New-CddsiConfigTransactionPlan -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $earlyWrite -ValidationTimeUtc '2030-01-01T00:03:00Z' } | Should -Throw

        $nextSession = New-CddsiSyntheticConfigStageContext -IdentityBase 400
        $nextSessionWrite = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $nextSession -Operation WriteManagedPolicy `
            -OperationUseId '60000000-0000-4000-8000-000000000397' -ClaimedAtUtc '2030-01-01T00:05:00Z'
        { New-CddsiConfigTransactionPlan -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $nextSessionWrite -ValidationTimeUtc '2030-01-01T00:05:00Z' } | Should -Throw
    }

    It 'commits only a canonical event transcript and a matching terminal provider receipt' {
        $fixture = New-CddsiSyntheticConfigTransactionPlan
        $plan = $fixture.Plan
        $events = @(
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 1 -Name policy_write -OccurredAtUtc '2030-01-01T00:06:00Z'),
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 2 -Name policy_readback -OccurredAtUtc '2030-01-01T00:07:00Z'),
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 3 -Name commit -OccurredAtUtc '2030-01-01T00:08:00Z')
        )
        $transcript = New-CddsiSyntheticConfigTransactionTranscript -Plan $plan -Events $events
        $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text (@($events.ProviderEvidenceSha256) -join '|')
        $terminal = Complete-CddsiSyntheticConfigAuthorizationBundle -AuthorizationBundle $fixture.WriteAuthorization -Outcome COMPLETED `
            -ProviderEvidenceDigest $providerDigest -OccurredAtUtc '2030-01-01T00:08:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000302'
        $result = Resolve-CddsiConfigTransactionTranscript -Transcript $transcript -ExpectedPlan $plan `
            -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $fixture.WriteAuthorization -WriteTerminalAuthorization $terminal
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.TransactionStatus | Should -BeExactly 'COMMITTED'
        $result.Data.CompensationStatus | Should -BeExactly 'NOT_APPLICABLE'
        $result.Data.BackupCleanupStatus | Should -BeExactly 'REQUIRED_NOT_PROVEN'
        @($result.Data.RequiredAuthorizationSlots.Operation) | Should -Contain 'RemoveManagedPolicyBackup'
        $result.Data.RequiredAuthorizationSlots[0].PrimaryTerminalReceiptBindingToken | Should -BeExactly $terminal.OperationUseState.ReceiptBindingToken
        $result.Data.RequiredAuthorizationSlots[0].EarliestClaimAtUtc | Should -BeExactly $terminal.OperationUseState.OccurredAtUtc
    }

    It 'rejects rehashed forged plans self-reported evidence time travel and order attacks' {
        $fixture = New-CddsiSyntheticConfigTransactionPlan
        $plan = $fixture.Plan
        $events = @(
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 1 -Name policy_write -OccurredAtUtc '2030-01-01T00:06:00Z'),
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 2 -Name policy_readback -OccurredAtUtc '2030-01-01T00:07:00Z'),
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 3 -Name commit -OccurredAtUtc '2030-01-01T00:08:00Z')
        )
        $transcript = New-CddsiSyntheticConfigTransactionTranscript -Plan $plan -Events $events
        $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text (@($events.ProviderEvidenceSha256) -join '|')
        $terminal = Complete-CddsiSyntheticConfigAuthorizationBundle -AuthorizationBundle $fixture.WriteAuthorization -Outcome COMPLETED `
            -ProviderEvidenceDigest $providerDigest -OccurredAtUtc '2030-01-01T00:08:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000302'
        $arguments = @{
            Transcript = $transcript; ExpectedPlan = $plan; SourceDecision = $fixture.SourceDecision; ValueSet = $fixture.ValueSet
            BackupEvidence = $fixture.BackupEvidence; BackupAuthorization = $fixture.BackupAuthorization
            WriteAuthorization = $fixture.WriteAuthorization; WriteTerminalAuthorization = $terminal
        }

        $forgedPlan = $plan | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $forgedPlan.RunId = 'not-a-guid'
        $forgedPlan.PlanId = Get-CddsiSupplyChainTextBindingToken -Text ('forged|' + $forgedPlan.RunId)
        $forgedPlan.TransactionId = Get-CddsiSupplyChainTextBindingToken -Text ('forged|' + $forgedPlan.PlanId)
        $forgedArguments = $arguments.Clone()
        $forgedArguments.ExpectedPlan = $forgedPlan
        { Resolve-CddsiConfigTransactionTranscript @forgedArguments } | Should -Throw

        $selfReported = $transcript | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $selfReported.Events[0].ProviderEvidenceSha256 = ('1' * 64)
        $selfReportedArguments = $arguments.Clone()
        $selfReportedArguments.Transcript = $selfReported
        { Resolve-CddsiConfigTransactionTranscript @selfReportedArguments } | Should -Throw

        $timeTravel = $transcript | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $timeTravel.Events[0].OccurredAtUtc = '2030-01-01T00:04:59Z'
        $timeTravel.Events[0].ProviderEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text (@(
            'cddsi-config-provider-event-v2', $plan.PlanId, $plan.TransactionId, $plan.WriteOperationUseId,
            '1', 'policy_write', 'SUCCEEDED', 'CHANGED', $timeTravel.Events[0].OccurredAtUtc
        ) -join '|')
        $timeTravelArguments = $arguments.Clone()
        $timeTravelArguments.Transcript = $timeTravel
        { Resolve-CddsiConfigTransactionTranscript @timeTravelArguments } | Should -Throw

        $orderAttack = $plan | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $orderAttack.Steps = @('backup_create', 'policy_write', 'policy_readback', 'commit')
        $orderArguments = $arguments.Clone()
        $orderArguments.ExpectedPlan = $orderAttack
        { Resolve-CddsiConfigTransactionTranscript @orderArguments } | Should -Throw

        $alternateStage = New-CddsiSyntheticConfigStageContext -IdentityBase 400
        $alternateClaim = New-CddsiSyntheticConfigAuthorizationBundle -StageContext $alternateStage -Operation WriteManagedPolicy `
            -OperationUseId $plan.WriteOperationUseId -ClaimedAtUtc '2030-01-01T00:05:00Z'
        $alternateTerminal = Complete-CddsiSyntheticConfigAuthorizationBundle -AuthorizationBundle $alternateClaim -Outcome COMPLETED `
            -ProviderEvidenceDigest $providerDigest -OccurredAtUtc '2030-01-01T00:08:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000402'
        $terminalSwapArguments = $arguments.Clone()
        $terminalSwapArguments.WriteTerminalAuthorization = $alternateTerminal
        { Resolve-CddsiConfigTransactionTranscript @terminalSwapArguments } | Should -Throw
    }

    It 'requires independent restore authorization after an uncertain write and never accepts a fake compensation tail' {
        $fixture = New-CddsiSyntheticConfigTransactionPlan
        $plan = $fixture.Plan
        $events = @(
            (New-CddsiSyntheticConfigTransactionEvent -Plan $plan -Sequence 1 -Name policy_write -Outcome FAILED -MutationState UNKNOWN -OccurredAtUtc '2030-01-01T00:06:00Z')
        )
        $transcript = New-CddsiSyntheticConfigTransactionTranscript -Plan $plan -Events $events
        $providerDigest = Get-CddsiSupplyChainTextBindingToken -Text (@($events.ProviderEvidenceSha256) -join '|')
        $terminal = Complete-CddsiSyntheticConfigAuthorizationBundle -AuthorizationBundle $fixture.WriteAuthorization -Outcome ABORTED `
            -ProviderEvidenceDigest $providerDigest -OccurredAtUtc '2030-01-01T00:06:00Z' -IdempotencyKey '70000000-0000-4000-8000-000000000302'
        $result = Resolve-CddsiConfigTransactionTranscript -Transcript $transcript -ExpectedPlan $plan `
            -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $fixture.WriteAuthorization -WriteTerminalAuthorization $terminal
        $result.Status | Should -BeExactly 'FAILED'
        $result.Data.CompensationStatus | Should -BeExactly 'REQUIRED_NOT_PROVEN'
        $result.Data.BackupCleanupStatus | Should -BeExactly 'REQUIRED_NOT_PROVEN'
        @($result.Data.RequiredAuthorizationSlots.Operation) -join '|' | Should -BeExactly 'RestoreManagedPolicy|RemoveManagedPolicyBackup'
        foreach ($slot in @($result.Data.RequiredAuthorizationSlots)) {
            $slot.PrimaryTerminalState | Should -BeExactly 'ABORTED'
            $slot.PrimaryTerminalReceiptBindingToken | Should -BeExactly $terminal.OperationUseState.ReceiptBindingToken
            $slot.EarliestClaimAtUtc | Should -BeExactly '2030-01-01T00:06:00Z'
            $slot.MustUseFreshConfirmation | Should -BeTrue
            $slot.MustUseFreshOperationUseId | Should -BeTrue
        }

        $fakeTail = $transcript | ConvertTo-Json -Depth 30 | ConvertFrom-Json
        $fakeTail.Events += [pscustomobject][ordered]@{
            Sequence = 2; Name = 'restore_backup'; Outcome = 'SUCCEEDED'; MutationState = 'CHANGED'
            OccurredAtUtc = '2030-01-01T00:07:00Z'; OperationUseId = $plan.WriteOperationUseId; ProviderEvidenceSha256 = ('2' * 64)
        }
        { Resolve-CddsiConfigTransactionTranscript -Transcript $fakeTail -ExpectedPlan $plan `
            -SourceDecision $fixture.SourceDecision -ValueSet $fixture.ValueSet -BackupEvidence $fixture.BackupEvidence `
            -BackupAuthorization $fixture.BackupAuthorization -WriteAuthorization $fixture.WriteAuthorization -WriteTerminalAuthorization $terminal } | Should -Throw
    }

    It 'keeps every P2 mutation-shaped function plan-only and registry-targeted' {
        foreach ($name in @(
            'New-CddsiConfigRestorableBackup',
            'New-CddsiConfigRedactedSnapshot',
            'Write-CddsiClaudeDesktopConfigAtomic',
            'Restore-CddsiClaudeDesktopConfig'
        )) {
            (Get-Command $name).Parameters.Keys -contains 'TargetPath' | Should -BeFalse
        }
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $results = @(
            New-CddsiConfigRestorableBackup -ExecutionContext $context -Mode TestSafe
            New-CddsiConfigRedactedSnapshot -ExecutionContext $context -Mode TestSafe
            Write-CddsiClaudeDesktopConfigAtomic -ExecutionContext $context -DesiredConfig (New-CddsiClaudeDesktopDesiredConfig) -Mode TestSafe
            Restore-CddsiClaudeDesktopConfig -ExecutionContext $context -BackupId 'backup-00000000-0000-0000-0000-000000000399' -Mode TestSafe
        )
        foreach ($result in $results) {
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            $result.Changed | Should -BeFalse
            if (@($result.PlannedChanges).Count -gt 0) {
                @($result.PlannedChanges) -join '|' | Should -BeExactly '<HKCU_MANAGED_POLICY>'
            }
        }
        @($context.AccessLedger.Entries).Count | Should -Be 0
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        @((Get-ChildItem -LiteralPath $TestDrive -Force -Recurse -ErrorAction Stop)).Count | Should -Be 0
        { Restore-CddsiClaudeDesktopConfig -ExecutionContext $context -BackupId 'arbitrary' -Mode TestSafe } | Should -Throw
    }

    It 'retains configLibrary as a synthetic detection target only' {
        $local = Join-Path $TestDrive 'LocalAppData'
        $expected = Join-Path $local 'Claude-3p\configLibrary'
        (Test-CddsiConfigLibraryTarget -TargetPath $expected -LocalAppDataPath $local) | Should -BeTrue
        (Test-CddsiConfigLibraryTarget -TargetPath (Join-Path $TestDrive '.claude\settings.json') -LocalAppDataPath $local) | Should -BeFalse
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        $result = Read-CddsiClaudeDesktopConfigLibrary -ExecutionContext $context -TargetPath $context.Paths.ConfigLibrary -Mode TestSafe
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.Changed | Should -BeFalse
        @($context.AccessLedger.Entries).Count | Should -Be 0
    }

    It 'does not resolve or read Claude Code settings in its integrity contract' {
        $contract = Get-CddsiClaudeCodeSettingsIntegrityContract
        $contract.policy | Should -BeExactly 'do_not_read_or_modify'
        $contract.contentParsingAllowed | Should -BeFalse
        $contract.hashOnlyProviderAllowed | Should -BeFalse
    }
}
