BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\vm-reset.ps1')
    . (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-vm-reset-live.ps1')

    function Copy-CddsiVmResetLiveFixture {
        param([Parameter(Mandatory = $true)]$Value)
        return [System.Management.Automation.PSSerializer]::Deserialize(
            [System.Management.Automation.PSSerializer]::Serialize($Value, 40)
        )
    }

    function Add-CddsiVmResetLiveEvidenceDigest {
        param(
            [Parameter(Mandatory = $true)]$Evidence,
            [Parameter(Mandatory = $true)][string[]]$Fields
        )
        $payload = [pscustomobject][ordered]@{}
        foreach ($name in $Fields) {
            Add-Member -InputObject $payload -NotePropertyName $name -NotePropertyValue $Evidence.$name
        }
        if ($null -eq $Evidence.PSObject.Properties['EvidenceDigest']) {
            Add-Member -InputObject $Evidence -NotePropertyName EvidenceDigest -NotePropertyValue ''
        }
        $Evidence.EvidenceDigest = Get-CddsiVmResetBindingToken -Value $payload
        return $Evidence
    }

    function New-CddsiVmResetLiveBaselineFixture {
        param([Parameter(Mandatory = $true)][string]$CapturedAtUtc)
        $specifications = @(
            @('OS', 'Environment', '<VM_RESET_BASELINE:OS>'),
            @('AppX', 'Package', '<VM_RESET_BASELINE:APPX>'),
            @('Git', 'Process', '<VM_RESET_BASELINE:GIT>'),
            @('VMP', 'Feature', '<VM_RESET_BASELINE:VMP>'),
            @('Registry', 'Registry', '<VM_RESET_BASELINE:REGISTRY>'),
            @('Credential', 'Credential', '<VM_RESET_BASELINE:CREDENTIAL>'),
            @('Checkpoint', 'FileSystem', '<VM_RESET_BASELINE:CHECKPOINT>'),
            @('FileSystem', 'FileSystem', '<VM_RESET_BASELINE:FILESYSTEM>')
        )
        $observations = @()
        for ($index = 0; $index -lt $specifications.Count; $index++) {
            $specification = $specifications[$index]
            $observations += [pscustomobject][ordered]@{
                Sequence = $index + 1
                Domain = $specification[0]
                Provider = $specification[1]
                ResourceToken = $specification[2]
                StateDigest = (($index + 1).ToString('x') * 64)
            }
        }
        $baseline = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-baseline-v1'
            VmIdentity = 'vm-fastlane-01'
            ImageSha256 = ('a' * 64)
            CapturedAtUtc = $CapturedAtUtc
            Observations = @($observations)
            BaselineDigest = ''
        }
        $baseline.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $baseline
        return $baseline
    }

    function New-CddsiVmResetLiveActionReceiptFixture {
        param(
            [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)]$Action,
            [bool]$Changed = $true,
            [string]$ProviderEvidenceDigest = ''
        )
        if ([string]::IsNullOrEmpty($ProviderEvidenceDigest)) {
            $ProviderEvidenceDigest = ([int]$Action.Sequence).ToString('x') * 64
        }
        $started = [DateTimeOffset]::Parse('2030-01-01T00:00:10Z').AddSeconds([int]$Action.Sequence)
        $completed = $started.AddSeconds(1)
        $withoutBinding = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-action-receipt-v1'
            CycleId = $Plan.CycleId
            PlanBindingToken = $Plan.PlanBindingToken
            Sequence = [int]$Action.Sequence
            ResourceId = $Action.ResourceId
            ResourceType = $Action.ResourceType
            Provider = $Action.Provider
            Operation = $Action.Operation
            ResourceToken = $Action.ResourceToken
            OwnershipReceiptBindingToken = $Action.OwnershipReceiptBindingToken
            ExecutionMode = 'Live'
            Outcome = 'COMPLETED'
            Changed = $Changed
            FailureCode = ''
            ProviderEvidenceDigest = $ProviderEvidenceDigest
            StartedAtUtc = $started.ToString('yyyy-MM-ddTHH:mm:ssZ')
            CompletedAtUtc = $completed.ToString('yyyy-MM-ddTHH:mm:ssZ')
        }
        $receipt = [pscustomobject][ordered]@{}
        foreach ($property in $withoutBinding.PSObject.Properties) {
            Add-Member -InputObject $receipt -NotePropertyName $property.Name -NotePropertyValue $property.Value
        }
        Add-Member -InputObject $receipt -NotePropertyName ReceiptBindingToken `
            -NotePropertyValue (Get-CddsiVmResetBindingToken -Value $withoutBinding)
        return $receipt
    }

    function New-CddsiVmResetLivePreflightEvidenceFixture {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [Parameter(Mandatory = $true)][int]$Sequence
        )
        $entry = $Fixture.Policy.AllowList[$Sequence - 1]
        $binding = $Fixture.Bindings[$Sequence - 1]
        $isPath = @('Checkpoint', 'OwnerMarkedDirectory') -ccontains $entry.ResourceType
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-preflight-evidence-v1'
            ResourceId = $entry.ResourceId
            ResourceToken = $entry.ResourceToken
            ResourceType = $entry.ResourceType
            Provider = $entry.Provider
            Operation = $entry.Operation
            OwnerRunId = $entry.OwnerRunId
            TargetBindingToken = $binding.TargetBindingToken
            ResourceIdentitySha256 = $entry.ResourceIdentitySha256
            Exists = $true
            ExactTargetMatched = $true
            OwnershipMatched = $true
            MarkerSha256 = $(if ($isPath) { $binding.TargetDescriptor.OwnerMarkerSha256 } else { 'NOT_APPLICABLE' })
            PreexistingPathBindingToken = $(if ($isPath) { $binding.TargetDescriptor.PreexistingPathBindingToken } else { 'NOT_APPLICABLE' })
            AncestorBindingToken = $(if ($isPath) { $binding.TargetDescriptor.AncestorBindingToken } else { 'NOT_APPLICABLE' })
            TargetIsReparsePoint = $false
            AncestorReparsePointCount = 0
            ExistedBeforeOwnerRun = $false
        }
        return Add-CddsiVmResetLiveEvidenceDigest -Evidence $evidence -Fields @(
            'SchemaVersion', 'ContractVersion', 'ResourceId', 'ResourceToken',
            'ResourceType', 'Provider', 'Operation', 'OwnerRunId',
            'TargetBindingToken', 'ResourceIdentitySha256', 'Exists',
            'ExactTargetMatched', 'OwnershipMatched', 'MarkerSha256',
            'PreexistingPathBindingToken', 'AncestorBindingToken',
            'TargetIsReparsePoint', 'AncestorReparsePointCount', 'ExistedBeforeOwnerRun'
        )
    }

    function New-CddsiVmResetProviderActionResultFixture {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [Parameter(Mandatory = $true)][int]$Sequence,
            [Parameter(Mandatory = $true)][string]$ProviderRequestBindingToken
        )
        $action = $Fixture.Plan.Actions[$Sequence - 1]
        $binding = $Fixture.Bindings[$Sequence - 1]
        $preflight = New-CddsiVmResetLivePreflightEvidenceFixture -Fixture $Fixture -Sequence $Sequence
        $postconditionFields = @(
            'SchemaVersion', 'ContractVersion', 'ProviderRequestBindingToken',
            'TargetBindingToken', 'InitialPreflightEvidenceDigest',
            'AtomicPreconditionValidated', 'ExactTargetMatched', 'OwnershipMatched',
            'TargetWasReparsePoint', 'AncestorReparsePointCount', 'ExactTargetAbsentAfter'
        )
        $result = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-provider-action-result-v1'
            ProviderRequestBindingToken = $ProviderRequestBindingToken
            TargetBindingToken = $binding.TargetBindingToken
            InitialPreflightEvidenceDigest = $preflight.EvidenceDigest
            AtomicPreconditionValidated = $true
            ExactTargetMatched = $true
            OwnershipMatched = $true
            TargetWasReparsePoint = $false
            AncestorReparsePointCount = 0
            ExactTargetAbsentAfter = $true
            PostconditionEvidenceDigest = ''
            ActionReceipt = $null
            ResultBindingToken = ''
        }
        $postconditionPayload = [pscustomobject][ordered]@{}
        foreach ($name in $postconditionFields) {
            Add-Member -InputObject $postconditionPayload -NotePropertyName $name -NotePropertyValue $result.$name
        }
        $result.PostconditionEvidenceDigest = Get-CddsiVmResetBindingToken -Value $postconditionPayload
        $result.ActionReceipt = New-CddsiVmResetLiveActionReceiptFixture -Plan $Fixture.Plan `
            -Action $action -ProviderEvidenceDigest $result.PostconditionEvidenceDigest
        $resultFields = @($postconditionFields + 'PostconditionEvidenceDigest' + 'ActionReceipt')
        $resultPayload = [pscustomobject][ordered]@{}
        foreach ($name in $resultFields) {
            Add-Member -InputObject $resultPayload -NotePropertyName $name -NotePropertyValue $result.$name
        }
        $result.ResultBindingToken = Get-CddsiVmResetBindingToken -Value $resultPayload
        return [pscustomobject]@{
            Result = $result
            Preflight = $preflight
            Action = $action
            Binding = $binding
        }
    }

    function New-CddsiVmResetLiveFixture {
        param(
            [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'Live',
            [ValidateSet('HostSandbox', 'CI', 'VmAcceptance')][string]$EnvironmentTier = 'VmAcceptance',
            [bool]$IsCi = $false
        )

        $ownerRunId = '51000000-0000-4000-8000-000000000001'
        $ownedRoot = 'C:\cddsi-vm-test\cddsi-vm-test-51000000-0000-4000-8000-000000000001'
        $markerPath = $ownedRoot + '\.cddsi-owner.json'
        $markerSha256 = 'b' * 64
        $preexistingPathBindingToken = 'c' * 64
        $ancestorBindingToken = 'd' * 64
        $descriptors = @(
            [pscustomobject][ordered]@{
                PackageFullName = 'CDDsi.Test.Package_1.0.0.0_x64__publisher'
            },
            [pscustomobject][ordered]@{
                Hive = 'HKCU'
                KeyPath = 'SOFTWARE\Policies\Claude'
                ValueName = 'ClaudeCodeEnv'
                RegistryView = 'Default'
            },
            [pscustomobject][ordered]@{
                TargetName = 'cddsi-vm-test:deepseek'
                CredentialType = 'Generic'
            },
            [pscustomobject][ordered]@{
                Path = $ownedRoot + '\resume-checkpoint.json'
                OwnedRootPath = $ownedRoot
                OwnerMarkerPath = $markerPath
                OwnerMarkerSha256 = $markerSha256
                ExpectedFileSha256 = 'e' * 64
                PreexistingPathBindingToken = $preexistingPathBindingToken
                AncestorBindingToken = $ancestorBindingToken
                ExistedBeforeOwnerRun = $false
            },
            [pscustomobject][ordered]@{
                Path = $ownedRoot
                OwnerMarkerPath = $markerPath
                OwnerMarkerSha256 = $markerSha256
                PreexistingPathBindingToken = $preexistingPathBindingToken
                AncestorBindingToken = $ancestorBindingToken
                ExistedBeforeOwnerRun = $false
            }
        )
        $specifications = @(
            @('desktop-package', 'Package', 'Package', 'Remove', '<VM_RESET_PACKAGE:CLAUDE_DESKTOP>'),
            @('managed-policy-value', 'HkcuValue', 'Registry', 'DeleteValue', '<VM_RESET_HKCU:MANAGED_POLICY>'),
            @('deepseek-credential', 'Credential', 'Credential', 'Delete', '<VM_RESET_CREDENTIAL:DEEPSEEK>'),
            @('resume-checkpoint', 'Checkpoint', 'FileSystem', 'DeleteFile', '<VM_RESET_CHECKPOINT:RESUME>'),
            @('owned-test-directory', 'OwnerMarkedDirectory', 'FileSystem', 'DeleteDirectory', '<VM_RESET_DIRECTORY:RUN_ROOT>')
        )

        $entries = @()
        $receipts = @()
        $bindings = @()
        for ($index = 0; $index -lt $specifications.Count; $index++) {
            $specification = $specifications[$index]
            $descriptor = $descriptors[$index]
            $targetBindingToken = Get-CddsiVmResetBindingToken -Value $descriptor
            $entryMarker = if ($specification[1] -ceq 'OwnerMarkedDirectory') { $markerSha256 } else { 'NOT_APPLICABLE' }
            $entryPath = if ($specification[1] -ceq 'OwnerMarkedDirectory') { $preexistingPathBindingToken } else { 'NOT_APPLICABLE' }
            $receiptWithoutBinding = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-vm-reset-ownership-receipt-v1'
                ReceiptId = ('52000000-0000-4000-8000-{0:d12}' -f ($index + 1))
                OwnerId = 'cddsi-vm-test'
                OwnerRunId = $ownerRunId
                ResourceId = $specification[0]
                ResourceType = $specification[1]
                Provider = $specification[2]
                Operation = $specification[3]
                ResourceToken = $specification[4]
                ResourceIdentitySha256 = $targetBindingToken
                MarkerSha256 = $entryMarker
                PreexistingPathBindingToken = $entryPath
                IssuedAtUtc = '2030-01-01T00:00:00Z'
            }
            $receiptBinding = Get-CddsiVmResetBindingToken -Value $receiptWithoutBinding
            $receipt = [pscustomobject][ordered]@{}
            foreach ($property in $receiptWithoutBinding.PSObject.Properties) {
                Add-Member -InputObject $receipt -NotePropertyName $property.Name -NotePropertyValue $property.Value
            }
            Add-Member -InputObject $receipt -NotePropertyName ReceiptBindingToken -NotePropertyValue $receiptBinding
            $receipts += $receipt
            $entries += [pscustomobject][ordered]@{
                Sequence = $index + 1
                ResourceId = $specification[0]
                ResourceType = $specification[1]
                Provider = $specification[2]
                Operation = $specification[3]
                ResourceToken = $specification[4]
                OwnerRunId = $ownerRunId
                ResourceIdentitySha256 = $targetBindingToken
                MarkerSha256 = $entryMarker
                PreexistingPathBindingToken = $entryPath
                OwnershipReceiptBindingToken = $receiptBinding
            }
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-vm-reset-resource-binding-v1'
                ResourceId = $specification[0]
                ResourceToken = $specification[4]
                ResourceType = $specification[1]
                Provider = $specification[2]
                Operation = $specification[3]
                OwnerRunId = $ownerRunId
                TargetDescriptor = $descriptor
                TargetBindingToken = $targetBindingToken
            }
        }

        $before = New-CddsiVmResetLiveBaselineFixture -CapturedAtUtc '2030-01-01T00:00:00Z'
        $after = New-CddsiVmResetLiveBaselineFixture -CapturedAtUtc '2030-01-01T00:01:00Z'
        $policy = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-policy-v1'
            PolicyId = '53000000-0000-4000-8000-000000000001'
            PolicyRevision = 1
            Lane = 'FastLane'
            EnvironmentResetMode = 'GuestReset'
            VmIdentity = $before.VmIdentity
            ImageSha256 = $before.ImageSha256
            Frozen = $true
            ExpectedBaselineDigest = $before.BaselineDigest
            AllowList = @($entries)
            AllowListDigest = ''
            ResetPolicyDigest = ''
        }
        $policy.AllowListDigest = Get-CddsiVmResetBindingToken -Value @($policy.AllowList)
        $policyPayload = [pscustomobject][ordered]@{
            SchemaVersion = $policy.SchemaVersion
            ContractVersion = $policy.ContractVersion
            PolicyId = $policy.PolicyId
            PolicyRevision = $policy.PolicyRevision
            Lane = $policy.Lane
            EnvironmentResetMode = $policy.EnvironmentResetMode
            VmIdentity = $policy.VmIdentity
            ImageSha256 = $policy.ImageSha256
            Frozen = $policy.Frozen
            ExpectedBaselineDigest = $policy.ExpectedBaselineDigest
            AllowList = @($policy.AllowList)
            AllowListDigest = $policy.AllowListDigest
        }
        $policy.ResetPolicyDigest = Get-CddsiVmResetBindingToken -Value $policyPayload
        $plan = New-CddsiVmResetPlan -Policy $policy -OwnershipReceipts $receipts `
            -CycleId '54000000-0000-4000-8000-000000000001'
        $adapterFileSha256 = '6' * 64
        $deviceAttestationPublicKeySha256 = '7' * 64
        $context = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-live-context-v1'
            RunId = '55000000-0000-4000-8000-000000000001'
            Mode = $Mode
            EnvironmentTier = $EnvironmentTier
            PrincipalRole = 'VmTester'
            IsCi = $IsCi
            VmIdentity = $policy.VmIdentity
            ImageSha256 = $policy.ImageSha256
            ResetPolicyDigest = $policy.ResetPolicyDigest
            PlanBindingToken = $plan.PlanBindingToken
            ControlIdentity = 'vm-tester-fastlane'
            AuthenticationDigest = 'f' * 64
            ProviderAdapterFileSha256 = $adapterFileSha256
            DeviceAttestationPublicKeySha256 = $deviceAttestationPublicKeySha256
        }

        $state = [pscustomobject]@{
            Calls = [System.Collections.ArrayList]@()
            FailOnMutationSequence = 0
            PreflightMutator = $null
            ActionChanged = $true
        }
        $capturedPolicy = $policy
        $capturedPlan = $plan
        $capturedBindings = @($bindings)
        $capturedBefore = $before
        $capturedAfter = $after
        $capturedState = $state
        $capturedAddEvidenceDigest = ${function:Add-CddsiVmResetLiveEvidenceDigest}
        $capturedCopyFixture = ${function:Copy-CddsiVmResetLiveFixture}
        $capturedNewActionReceipt = ${function:New-CddsiVmResetLiveActionReceiptFixture}
        $invoke = {
            param($request)
            [void]$capturedState.Calls.Add($request)
            if ($request.Operation -ceq 'AttestVmAcceptance') {
                $evidence = [pscustomobject][ordered]@{
                    SchemaVersion = 1
                    ContractVersion = 'cddsi-vm-reset-environment-attestation-v1'
                    EnvironmentTier = 'VmAcceptance'
                    VmIdentity = $capturedPolicy.VmIdentity
                    ImageSha256 = $capturedPolicy.ImageSha256
                    PrincipalRole = 'VmTester'
                    IsCi = $false
                    HostSystem = 'Windows'
                    ProviderKind = 'VmResetLive'
                    AttestedAtUtc = '2030-01-01T00:00:00Z'
                }
                return & $capturedAddEvidenceDigest -Evidence $evidence -Fields @(
                    'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'VmIdentity',
                    'ImageSha256', 'PrincipalRole', 'IsCi', 'HostSystem', 'ProviderKind', 'AttestedAtUtc'
                )
            }
            if ($request.Operation -ceq 'CaptureBaseline') {
                if ($request.Arguments.Phase -ceq 'Before') { return & $capturedCopyFixture -Value $capturedBefore }
                return & $capturedCopyFixture -Value $capturedAfter
            }
            if ($request.Operation -ceq 'ValidateExactTarget') {
                $sequence = [int]$request.Arguments.Sequence
                $entry = $capturedPolicy.AllowList[$sequence - 1]
                $binding = $capturedBindings[$sequence - 1]
                $isPath = @('Checkpoint', 'OwnerMarkedDirectory') -ccontains $entry.ResourceType
                $evidence = [pscustomobject][ordered]@{
                    SchemaVersion = 1
                    ContractVersion = 'cddsi-vm-reset-preflight-evidence-v1'
                    ResourceId = $entry.ResourceId
                    ResourceToken = $entry.ResourceToken
                    ResourceType = $entry.ResourceType
                    Provider = $entry.Provider
                    Operation = $entry.Operation
                    OwnerRunId = $entry.OwnerRunId
                    TargetBindingToken = $binding.TargetBindingToken
                    ResourceIdentitySha256 = $entry.ResourceIdentitySha256
                    Exists = $true
                    ExactTargetMatched = $true
                    OwnershipMatched = $true
                    MarkerSha256 = $(if ($isPath) { $binding.TargetDescriptor.OwnerMarkerSha256 } else { 'NOT_APPLICABLE' })
                    PreexistingPathBindingToken = $(if ($isPath) { $binding.TargetDescriptor.PreexistingPathBindingToken } else { 'NOT_APPLICABLE' })
                    AncestorBindingToken = $(if ($isPath) { $binding.TargetDescriptor.AncestorBindingToken } else { 'NOT_APPLICABLE' })
                    TargetIsReparsePoint = $false
                    AncestorReparsePointCount = 0
                    ExistedBeforeOwnerRun = $false
                }
                if ($capturedState.PreflightMutator -is [scriptblock]) {
                    & $capturedState.PreflightMutator $evidence $request
                }
                return & $capturedAddEvidenceDigest -Evidence $evidence -Fields @(
                    'SchemaVersion', 'ContractVersion', 'ResourceId', 'ResourceToken',
                    'ResourceType', 'Provider', 'Operation', 'OwnerRunId',
                    'TargetBindingToken', 'ResourceIdentitySha256', 'Exists',
                    'ExactTargetMatched', 'OwnershipMatched', 'MarkerSha256',
                    'PreexistingPathBindingToken', 'AncestorBindingToken',
                    'TargetIsReparsePoint', 'AncestorReparsePointCount', 'ExistedBeforeOwnerRun'
                )
            }
            if (@('Remove', 'DeleteValue', 'Delete', 'DeleteFile', 'DeleteDirectory') -ccontains $request.Operation) {
                $sequence = [int]$request.Arguments.Sequence
                if ($capturedState.FailOnMutationSequence -eq $sequence) {
                    throw 'Injected fake provider failure.'
                }
                return & $capturedNewActionReceipt -Plan $capturedPlan `
                    -Action $capturedPlan.Actions[$sequence - 1] -Changed $capturedState.ActionChanged
            }
            if ($request.Operation -ceq 'InspectFinalState') {
                $evidence = [pscustomobject][ordered]@{
                    SchemaVersion = 1
                    ContractVersion = 'cddsi-vm-reset-final-state-v1'
                    VmpState = 'KNOWN'
                    RebootState = 'KNOWN'
                    UninstallState = 'KNOWN'
                    CompensationState = 'KNOWN'
                    CleanupFailureCount = 0
                    UnknownMutationCount = 0
                    UnexpectedLedgerEntryCount = 0
                    SecretScanCount = 0
                }
                return & $capturedAddEvidenceDigest -Evidence $evidence -Fields @(
                    'SchemaVersion', 'ContractVersion', 'VmpState', 'RebootState',
                    'UninstallState', 'CompensationState', 'CleanupFailureCount',
                    'UnknownMutationCount', 'UnexpectedLedgerEntryCount', 'SecretScanCount'
                )
            }
            throw 'Unexpected fake provider request.'
        }.GetNewClosure()
        if ($Mode -ceq 'Live') {
            $adapter = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-vm-reset-provider-adapter-v2'
                Kind = 'VmResetLive'
                IsLive = $true
                AdapterId = 'cddsi-vm-reset-provider-windows-v2'
                AdapterFilePath = 'C:\cddsi-vm-operator\windows-vm-reset.ps1'
                AdapterFileSha256 = $adapterFileSha256
                DeviceAttestationPublicKeySha256 = $deviceAttestationPublicKeySha256
                AuthorizationEnvelope = [pscustomobject][ordered]@{
                    ControlAuthenticationDigest = $context.AuthenticationDigest
                    ResetPolicyDigest = $policy.ResetPolicyDigest
                    PlanBindingToken = $plan.PlanBindingToken
                }
                Invoke = $null
            }
        }
        else {
            $adapter = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-vm-reset-provider-adapter-v1'
                Kind = 'FakeVmReset'
                IsLive = $false
                AdapterId = 'cddsi-vm-reset-provider-fake-v1'
                AdapterFilePath = 'C:\cddsi-vm-operator\cddsi-vm-reset-provider-fake.ps1'
                AdapterFileSha256 = $adapterFileSha256
                DeviceAttestationPublicKeySha256 = $deviceAttestationPublicKeySha256
                Invoke = $invoke
            }
        }
        return [pscustomobject]@{
            Policy = $policy
            Plan = $plan
            Receipts = @($receipts)
            Bindings = @($bindings)
            Context = $context
            Adapter = $adapter
            State = $state
            BaselineBefore = $before
            BaselineAfter = $after
        }
    }

    function Invoke-CddsiVmResetLiveFixture {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [string]$MilestoneType = 'DevelopmentRetest',
            [switch]$AcknowledgeRealChanges,
            [switch]$ReceiptValidatorAvailable
        )
        return Invoke-CddsiVmResetLiveAdapter -Context $Fixture.Context -ProviderAdapter $Fixture.Adapter `
            -Policy $Fixture.Policy -Plan $Fixture.Plan -OwnershipReceipts $Fixture.Receipts `
            -ResourceBindings $Fixture.Bindings -MilestoneType $MilestoneType -Mode $Fixture.Context.Mode `
            -AcknowledgeRealChanges:$AcknowledgeRealChanges `
            -ReceiptValidatorAvailable:$ReceiptValidatorAvailable
    }
}

Describe 'VM-only deterministic reset live adapter boundary' {
    It 'is plan-only by default and dispatches no provider operation in TestSafe or DryRun' {
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $fixture = New-CddsiVmResetLiveFixture -Mode $mode -EnvironmentTier HostSandbox
            $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            $result.Changed | Should -BeFalse
            $result.ErrorCode | Should -BeExactly 'VM_ACCEPTANCE_LIVE_REQUIRED'
            $result.Data.Disposition | Should -BeExactly 'PLAN_ONLY'
            $result.Data.MutationState | Should -BeExactly 'NOT_STARTED'
            $result.Data.ProviderCallCount | Should -Be 0
            @($fixture.State.Calls).Count | Should -Be 0
        }
    }

    It 'rejects HostSandbox and CI Live before provider dispatch even with acknowledgement' {
        $cases = @(
            @{ Tier = 'HostSandbox'; IsCi = $false },
            @{ Tier = 'CI'; IsCi = $true },
            @{ Tier = 'VmAcceptance'; IsCi = $true }
        )
        foreach ($case in $cases) {
            $fixture = New-CddsiVmResetLiveFixture -Mode Live -EnvironmentTier $case.Tier -IsCi $case.IsCi
            $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture -AcknowledgeRealChanges -ReceiptValidatorAvailable
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            $result.ErrorCode | Should -BeExactly 'HOST_OR_CI_LIVE_FORBIDDEN'
            $result.Changed | Should -BeFalse
            $result.Data.ProviderCallCount | Should -Be 0
            @($fixture.State.Calls).Count | Should -Be 0
        }
    }

    It 'requires explicit real-change acknowledgement and a receipt validator before VM provider dispatch' {
        $fixture = New-CddsiVmResetLiveFixture
        $withoutAck = Invoke-CddsiVmResetLiveFixture -Fixture $fixture -ReceiptValidatorAvailable
        $withoutAck.ErrorCode | Should -BeExactly 'REAL_CHANGE_ACKNOWLEDGEMENT_REQUIRED'
        @($fixture.State.Calls).Count | Should -Be 0

        $fixture = New-CddsiVmResetLiveFixture
        $withoutValidator = Invoke-CddsiVmResetLiveFixture -Fixture $fixture -AcknowledgeRealChanges
        $withoutValidator.ErrorCode | Should -BeExactly 'SNAPSHOT_RESTORE_REQUIRED'
        $withoutValidator.Data.ReasonCodes | Should -Contain 'RECEIPT_VALIDATOR_UNAVAILABLE'
        $withoutValidator.Data.SnapshotRestoreRequired | Should -BeTrue
        @($fixture.State.Calls).Count | Should -Be 0
    }

    It 'requires an external snapshot for every formal or milestone run before provider dispatch' {
        foreach ($milestone in @('FirstP10A', 'FreezeFactsP10A', 'FormalP11Pass', 'ReleaseMilestone', 'P12Final')) {
            $fixture = New-CddsiVmResetLiveFixture
            $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture -MilestoneType $milestone `
                -AcknowledgeRealChanges -ReceiptValidatorAvailable
            $result.ErrorCode | Should -BeExactly 'SNAPSHOT_RESTORE_REQUIRED'
            $result.Data.RequiredResetMode | Should -BeExactly 'SnapshotRestore'
            $result.Data.ReasonCodes | Should -Contain 'MILESTONE_REQUIRES_SNAPSHOT'
            @($fixture.State.Calls).Count | Should -Be 0
        }
    }

    It 'keeps even a caller-declared VM Live context blocked until the fixed adapter and device trust chain are provisioned' {
        $fixture = New-CddsiVmResetLiveFixture
        $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture -AcknowledgeRealChanges -ReceiptValidatorAvailable

        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.Changed | Should -BeFalse
        $result.ErrorCode | Should -BeExactly 'VM_RESET_LIVE_TRUST_CHAIN_UNPROVISIONED'
        $result.Data.SnapshotRestoreRequired | Should -BeTrue
        $result.Data.MutationState | Should -BeExactly 'NOT_STARTED'
        $result.Data.RealMutationPerformed | Should -BeFalse
        $result.Data.ReasonCodes | Should -Contain 'FIXED_ADAPTER_SHA_UNVERIFIED'
        $result.Data.ReasonCodes | Should -Contain 'VM_DEVICE_ATTESTATION_TRUST_UNVERIFIED'
        $result.Data.ReasonCodes | Should -Contain 'WINDOWS_LIVE_PROVIDER_UNAVAILABLE'
        $result.Data.ProviderCallCount | Should -Be 0
        @($fixture.State.Calls).Count | Should -Be 0
    }

    It 'rejects an out-of-scope resource mapping before provider dispatch' {
        $fixture = New-CddsiVmResetLiveFixture
        $fixture.Bindings[1].TargetDescriptor.Hive = 'HKLM'
        $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture -AcknowledgeRealChanges -ReceiptValidatorAvailable
        $result.ErrorCode | Should -BeExactly 'RESOURCE_BINDING_INVALID'
        $result.Changed | Should -BeFalse
        @($fixture.State.Calls).Count | Should -Be 0
    }

    It 'limits HKCU and filesystem targets to the project policy root and owner-run directory name' {
        $fixture = New-CddsiVmResetLiveFixture
        $ownerRunId = $fixture.Policy.AllowList[4].OwnerRunId
        Test-CddsiVmResetLiveTargetDescriptor -Descriptor $fixture.Bindings[4].TargetDescriptor `
            -ResourceType OwnerMarkedDirectory -OwnerRunId $ownerRunId | Should -BeTrue

        $registry = Copy-CddsiVmResetLiveFixture -Value $fixture.Bindings[1].TargetDescriptor
        $registry.KeyPath = 'Software\Microsoft\Windows'
        Test-CddsiVmResetLiveTargetDescriptor -Descriptor $registry -ResourceType HkcuValue `
            -OwnerRunId $ownerRunId | Should -BeFalse

        foreach ($path in @(
            'C:\',
            'C:\cddsi-vm-test\not-owned',
            'C:\cddsi-vm-test\cddsi-vm-test-51000000-0000-4000-8000-000000000002',
            ('C:\cddsi-vm-test\cddsi-vm-test-' + $ownerRunId + ':stream'),
            ('C:\NUL\cddsi-vm-test-' + $ownerRunId)
        )) {
            $directory = Copy-CddsiVmResetLiveFixture -Value $fixture.Bindings[4].TargetDescriptor
            $directory.Path = $path
            $directory.OwnerMarkerPath = [IO.Path]::Combine($path, '.cddsi-owner.json')
            Test-CddsiVmResetLiveTargetDescriptor -Descriptor $directory `
                -ResourceType OwnerMarkedDirectory -OwnerRunId $ownerRunId | Should -BeFalse
        }
    }

    It 'binds context to the declared fixed adapter and VM device public-key digests without dispatch' {
        $fixture = New-CddsiVmResetLiveFixture -Mode DryRun -EnvironmentTier HostSandbox
        $fixture.Context.ProviderAdapterFileSha256 = '9' * 64
        $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture
        $result.ErrorCode | Should -BeExactly 'VM_RESET_CONTEXT_INVALID'
        $result.Changed | Should -BeFalse
        $result.Data.ProviderCallCount | Should -Be 0
        @($fixture.State.Calls).Count | Should -Be 0
    }

    It 'rejects a caller-supplied Invoke scriptblock on the live v2 adapter with zero dispatch' {
        $fixture = New-CddsiVmResetLiveFixture
        $callerInvokeCount = 0
        $fixture.Adapter.Invoke = {
            param($request)
            $callerInvokeCount++
            throw 'caller scriptblock must never run'
        }
        $result = Invoke-CddsiVmResetLiveFixture -Fixture $fixture `
            -AcknowledgeRealChanges -ReceiptValidatorAvailable
        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.ErrorCode | Should -BeExactly 'PROVIDER_ADAPTER_INVALID'
        $result.Changed | Should -BeFalse
        $result.Data.ProviderCallCount | Should -Be 0
        $callerInvokeCount | Should -Be 0
        @($fixture.State.Calls).Count | Should -Be 0
    }

    It 'rejects owner marker path binding ancestor and reparse evidence without provider dispatch' {
        $cases = @(
            { param($evidence) $evidence.MarkerSha256 = '1' * 64 },
            { param($evidence) $evidence.PreexistingPathBindingToken = '2' * 64 },
            { param($evidence) $evidence.AncestorBindingToken = '3' * 64 },
            { param($evidence) $evidence.TargetIsReparsePoint = $true },
            { param($evidence) $evidence.AncestorReparsePointCount = 1 },
            { param($evidence) $evidence.ExistedBeforeOwnerRun = $true }
        )
        foreach ($mutator in $cases) {
            $fixture = New-CddsiVmResetLiveFixture
            $evidence = New-CddsiVmResetLivePreflightEvidenceFixture -Fixture $fixture -Sequence 5
            & $mutator $evidence
            $evidence = Add-CddsiVmResetLiveEvidenceDigest -Evidence $evidence -Fields @(
                'SchemaVersion', 'ContractVersion', 'ResourceId', 'ResourceToken',
                'ResourceType', 'Provider', 'Operation', 'OwnerRunId',
                'TargetBindingToken', 'ResourceIdentitySha256', 'Exists',
                'ExactTargetMatched', 'OwnershipMatched', 'MarkerSha256',
                'PreexistingPathBindingToken', 'AncestorBindingToken',
                'TargetIsReparsePoint', 'AncestorReparsePointCount', 'ExistedBeforeOwnerRun'
            )
            Test-CddsiVmResetPreflightEvidence -Evidence $evidence -Binding $fixture.Bindings[4] `
                -AllowListEntry $fixture.Policy.AllowList[4] | Should -BeFalse
            @($fixture.State.Calls).Count | Should -Be 0
        }
    }

    It 'reports confirmed prior changes even when the current mutation state is unknown' {
        $fixture = New-CddsiVmResetLiveFixture
        $receipts = @(
            New-CddsiVmResetLiveActionReceiptFixture -Plan $fixture.Plan -Action $fixture.Plan.Actions[0] -Changed $true
            New-CddsiVmResetLiveActionReceiptFixture -Plan $fixture.Plan -Action $fixture.Plan.Actions[1] -Changed $true
        )
        $result = New-CddsiVmResetLiveBlockedResult -Mode Live -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' `
            -ReasonCodes @('ACTION_STATE_AMBIGUOUS') -Plan $fixture.Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null -ActionReceipts $receipts -MutationState UNKNOWN

        $result.Status | Should -BeExactly 'ACTION_REQUIRED'
        $result.ErrorCode | Should -BeExactly 'SNAPSHOT_RESTORE_REQUIRED'
        $result.Changed | Should -BeTrue
        $result.Data.RequiredResetMode | Should -BeExactly 'SnapshotRestore'
        $result.Data.SnapshotRestoreRequired | Should -BeTrue
        $result.Data.ReasonCodes | Should -Contain 'ACTION_STATE_AMBIGUOUS'
        $result.Data.MutationState | Should -BeExactly 'UNKNOWN'
        $result.Data.RealMutationPerformed | Should -BeTrue
        @($result.Data.ActionReceipts).Count | Should -Be 2
        $result.Data.BaselineAfter | Should -BeNullOrEmpty
        @($fixture.State.Calls).Count | Should -Be 0
    }

    It 'binds each provider action result to the current request target preflight and action' {
        $fixture = New-CddsiVmResetLiveFixture
        $requestBinding = '8' * 64
        $actionResult = New-CddsiVmResetProviderActionResultFixture -Fixture $fixture -Sequence 1 `
            -ProviderRequestBindingToken $requestBinding
        Test-CddsiVmResetProviderActionResult -Result $actionResult.Result -Plan $fixture.Plan `
            -ExpectedAction $actionResult.Action -ExpectedRequestBindingToken $requestBinding `
            -Binding $actionResult.Binding -PreflightEvidence $actionResult.Preflight | Should -BeTrue

        foreach ($propertyName in @(
            'ProviderRequestBindingToken', 'TargetBindingToken', 'InitialPreflightEvidenceDigest',
            'AtomicPreconditionValidated', 'OwnershipMatched', 'TargetWasReparsePoint',
            'AncestorReparsePointCount', 'ExactTargetAbsentAfter'
        )) {
            $tampered = Copy-CddsiVmResetLiveFixture -Value $actionResult.Result
            switch ($propertyName) {
                'AtomicPreconditionValidated' { $tampered.$propertyName = $false; break }
                'OwnershipMatched' { $tampered.$propertyName = $false; break }
                'TargetWasReparsePoint' { $tampered.$propertyName = $true; break }
                'AncestorReparsePointCount' { $tampered.$propertyName = 1; break }
                'ExactTargetAbsentAfter' { $tampered.$propertyName = $false; break }
                default { $tampered.$propertyName = '9' * 64; break }
            }
            Test-CddsiVmResetProviderActionResult -Result $tampered -Plan $fixture.Plan `
                -ExpectedAction $actionResult.Action -ExpectedRequestBindingToken $requestBinding `
                -Binding $actionResult.Binding -PreflightEvidence $actionResult.Preflight | Should -BeFalse
        }

        $swapped = Copy-CddsiVmResetLiveFixture -Value $actionResult.Result
        $swapped.ActionReceipt = New-CddsiVmResetLiveActionReceiptFixture -Plan $fixture.Plan `
            -Action $fixture.Plan.Actions[1] -ProviderEvidenceDigest $swapped.PostconditionEvidenceDigest
        Test-CddsiVmResetProviderActionResult -Result $swapped -Plan $fixture.Plan `
            -ExpectedAction $actionResult.Action -ExpectedRequestBindingToken $requestBinding `
            -Binding $actionResult.Binding -PreflightEvidence $actionResult.Preflight | Should -BeFalse
    }

    It 'rejects unsigned v1 action results for a live provider while retaining the non-live fixture path' {
        $fixture = New-CddsiVmResetLiveFixture
        $requestBinding = '8' * 64
        $actionResult = New-CddsiVmResetProviderActionResultFixture -Fixture $fixture -Sequence 1 `
            -ProviderRequestBindingToken $requestBinding
        $liveAdapter = [pscustomobject][ordered]@{
            Kind = 'VmResetLive'
            DeviceAttestationPublicKeySha256 = '7' * 64
        }
        Test-CddsiVmResetProviderActionResult -Result $actionResult.Result -Plan $fixture.Plan `
            -ExpectedAction $actionResult.Action -ExpectedRequestBindingToken $requestBinding `
            -Binding $actionResult.Binding -PreflightEvidence $actionResult.Preflight `
            -ProviderAdapter $liveAdapter | Should -BeFalse

        $fakeAdapter = [pscustomobject][ordered]@{
            Kind = 'FakeVmReset'
            DeviceAttestationPublicKeySha256 = '7' * 64
        }
        Test-CddsiVmResetProviderActionResult -Result $actionResult.Result -Plan $fixture.Plan `
            -ExpectedAction $actionResult.Action -ExpectedRequestBindingToken $requestBinding `
            -Binding $actionResult.Binding -PreflightEvidence $actionResult.Preflight `
            -ProviderAdapter $fakeAdapter | Should -BeTrue
    }

    It 'contains no direct system mutation enumeration process or task-scheduler commands' {
        $path = Join-Path $script:RepoRoot 'operator\fast-lane\invoke-vm-reset-live.ps1'
        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($path, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $source = [System.IO.File]::ReadAllText($path)
        $source | Should -Match '\$requiresSignedV2Result\s*=\s*\('
        $source | Should -Match 'if\s*\(\$requiresSignedV2Result\s+-and\s+-not\s+\$isV2\)\s*\{\s*return\s+\$false\s*\}'
        $source | Should -Match 'Test-CddsiWindowsVmResetAdapterDeviceSignature'
        $commandNames = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst]
        }, $true) | ForEach-Object { $_.GetCommandName() })
        foreach ($forbidden in @(
            'Invoke-Expression', 'Start-Process', 'Get-ChildItem', 'Remove-Item',
            'Remove-AppxPackage', 'Get-AppxPackage', 'Remove-ItemProperty',
            'Get-ItemProperty', 'Get-ScheduledTask', 'Unregister-ScheduledTask',
            'Get-Credential', 'cmd.exe', 'reg.exe', 'schtasks.exe',
            'powershell.exe', 'pwsh.exe'
        )) {
            $commandNames | Should -Not -Contain $forbidden
        }
    }
}
