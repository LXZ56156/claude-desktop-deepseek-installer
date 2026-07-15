BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\vm-reset.ps1')
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function Copy-CddsiVmResetFixture {
        param([Parameter(Mandatory = $true)]$Value)
        return $Value | ConvertTo-Json -Depth 30 | ConvertFrom-Json
    }

    function New-CddsiVmResetBaselineFixture {
        param(
            [string]$CapturedAtUtc = '2030-01-01T00:00:00Z',
            [string[]]$StateDigests
        )
        if ($null -eq $StateDigests) { $StateDigests = @(1..8 | ForEach-Object { $_.ToString('x') * 64 }) }
        $specifications = @(
            [pscustomobject]@{ Domain = 'OS'; Provider = 'Environment'; ResourceToken = '<VM_RESET_BASELINE:OS>' },
            [pscustomobject]@{ Domain = 'AppX'; Provider = 'Package'; ResourceToken = '<VM_RESET_BASELINE:APPX>' },
            [pscustomobject]@{ Domain = 'Git'; Provider = 'Process'; ResourceToken = '<VM_RESET_BASELINE:GIT>' },
            [pscustomobject]@{ Domain = 'VMP'; Provider = 'Feature'; ResourceToken = '<VM_RESET_BASELINE:VMP>' },
            [pscustomobject]@{ Domain = 'Registry'; Provider = 'Registry'; ResourceToken = '<VM_RESET_BASELINE:REGISTRY>' },
            [pscustomobject]@{ Domain = 'Credential'; Provider = 'Credential'; ResourceToken = '<VM_RESET_BASELINE:CREDENTIAL>' },
            [pscustomobject]@{ Domain = 'Checkpoint'; Provider = 'FileSystem'; ResourceToken = '<VM_RESET_BASELINE:CHECKPOINT>' },
            [pscustomobject]@{ Domain = 'FileSystem'; Provider = 'FileSystem'; ResourceToken = '<VM_RESET_BASELINE:FILESYSTEM>' }
        )
        $observations = @()
        for ($index = 0; $index -lt $specifications.Count; $index++) {
            $specification = $specifications[$index]
            $observations += [pscustomobject][ordered]@{
                Sequence = $index + 1; Domain = $specification.Domain; Provider = $specification.Provider
                ResourceToken = $specification.ResourceToken; StateDigest = $StateDigests[$index]
            }
        }
        $baseline = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-baseline-v1'; VmIdentity = 'vm-fastlane-01'
            ImageSha256 = ('a' * 64); CapturedAtUtc = $CapturedAtUtc; Observations = @($observations); BaselineDigest = ''
        }
        $baseline.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $baseline
        return $baseline
    }

    function New-CddsiVmResetOwnershipBundle {
        $ownerRunId = '41000000-0000-4000-8000-000000000001'
        $specifications = @(
            [pscustomobject]@{ ResourceId = 'desktop-package'; ResourceType = 'Package'; Provider = 'Package'; Operation = 'Remove'; ResourceToken = '<VM_RESET_PACKAGE:CLAUDE_DESKTOP>'; Identity = ('1' * 64); Marker = 'NOT_APPLICABLE'; Path = 'NOT_APPLICABLE' },
            [pscustomobject]@{ ResourceId = 'managed-policy-value'; ResourceType = 'HkcuValue'; Provider = 'Registry'; Operation = 'DeleteValue'; ResourceToken = '<VM_RESET_HKCU:MANAGED_POLICY>'; Identity = ('2' * 64); Marker = 'NOT_APPLICABLE'; Path = 'NOT_APPLICABLE' },
            [pscustomobject]@{ ResourceId = 'deepseek-credential'; ResourceType = 'Credential'; Provider = 'Credential'; Operation = 'Delete'; ResourceToken = '<VM_RESET_CREDENTIAL:DEEPSEEK>'; Identity = ('3' * 64); Marker = 'NOT_APPLICABLE'; Path = 'NOT_APPLICABLE' },
            [pscustomobject]@{ ResourceId = 'resume-checkpoint'; ResourceType = 'Checkpoint'; Provider = 'FileSystem'; Operation = 'DeleteFile'; ResourceToken = '<VM_RESET_CHECKPOINT:RESUME>'; Identity = ('4' * 64); Marker = 'NOT_APPLICABLE'; Path = 'NOT_APPLICABLE' },
            [pscustomobject]@{ ResourceId = 'owned-test-directory'; ResourceType = 'OwnerMarkedDirectory'; Provider = 'FileSystem'; Operation = 'DeleteDirectory'; ResourceToken = '<VM_RESET_DIRECTORY:RUN_ROOT>'; Identity = ('5' * 64); Marker = ('b' * 64); Path = ('c' * 64) }
        )
        $entries = @()
        $receipts = @()
        for ($index = 0; $index -lt $specifications.Count; $index++) {
            $specification = $specifications[$index]
            $receiptWithoutBinding = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-ownership-receipt-v1'
                ReceiptId = ('42000000-0000-4000-8000-{0:d12}' -f ($index + 1)); OwnerId = 'cddsi-vm-test'
                OwnerRunId = $ownerRunId; ResourceId = $specification.ResourceId; ResourceType = $specification.ResourceType
                Provider = $specification.Provider; Operation = $specification.Operation; ResourceToken = $specification.ResourceToken
                ResourceIdentitySha256 = $specification.Identity; MarkerSha256 = $specification.Marker
                PreexistingPathBindingToken = $specification.Path; IssuedAtUtc = '2030-01-01T00:00:00Z'
            }
            $binding = Get-CddsiVmResetBindingToken -Value $receiptWithoutBinding
            $receipt = [pscustomobject][ordered]@{}
            foreach ($property in $receiptWithoutBinding.PSObject.Properties) { Add-Member -InputObject $receipt -NotePropertyName $property.Name -NotePropertyValue $property.Value }
            Add-Member -InputObject $receipt -NotePropertyName ReceiptBindingToken -NotePropertyValue $binding
            $receipts += $receipt
            $entries += [pscustomobject][ordered]@{
                Sequence = $index + 1; ResourceId = $specification.ResourceId; ResourceType = $specification.ResourceType
                Provider = $specification.Provider; Operation = $specification.Operation; ResourceToken = $specification.ResourceToken
                OwnerRunId = $ownerRunId; ResourceIdentitySha256 = $specification.Identity; MarkerSha256 = $specification.Marker
                PreexistingPathBindingToken = $specification.Path; OwnershipReceiptBindingToken = $binding
            }
        }
        return [pscustomobject]@{ Entries = @($entries); Receipts = @($receipts) }
    }

    function Update-CddsiVmResetPolicyBindings {
        param([Parameter(Mandatory = $true)]$Policy)
        $Policy.AllowListDigest = Get-CddsiVmResetBindingToken -Value @($Policy.AllowList)
        $payload = [pscustomobject][ordered]@{
            SchemaVersion = $Policy.SchemaVersion; ContractVersion = $Policy.ContractVersion; PolicyId = $Policy.PolicyId
            PolicyRevision = $Policy.PolicyRevision; Lane = $Policy.Lane; EnvironmentResetMode = $Policy.EnvironmentResetMode
            VmIdentity = $Policy.VmIdentity; ImageSha256 = $Policy.ImageSha256; Frozen = $Policy.Frozen
            ExpectedBaselineDigest = $Policy.ExpectedBaselineDigest; AllowList = @($Policy.AllowList); AllowListDigest = $Policy.AllowListDigest
        }
        $Policy.ResetPolicyDigest = Get-CddsiVmResetBindingToken -Value $payload
        return $Policy
    }

    function New-CddsiVmResetPolicyFixture {
        param([Parameter(Mandatory = $true)]$Baseline, [Parameter(Mandatory = $true)]$OwnershipBundle)
        $policy = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-policy-v1'; PolicyId = '43000000-0000-4000-8000-000000000001'
            PolicyRevision = 1; Lane = 'FastLane'; EnvironmentResetMode = 'GuestReset'; VmIdentity = $Baseline.VmIdentity
            ImageSha256 = $Baseline.ImageSha256; Frozen = $true; ExpectedBaselineDigest = $Baseline.BaselineDigest
            AllowList = @($OwnershipBundle.Entries); AllowListDigest = ''; ResetPolicyDigest = ''
        }
        return Update-CddsiVmResetPolicyBindings -Policy $policy
    }

    function New-CddsiVmResetFinalStateFixture {
        param(
            [string]$VmpState = 'KNOWN', [string]$RebootState = 'KNOWN', [string]$UninstallState = 'KNOWN',
            [string]$CompensationState = 'KNOWN'
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-final-state-v1'; VmpState = $VmpState
            RebootState = $RebootState; UninstallState = $UninstallState; CompensationState = $CompensationState
        }
    }

    function New-CddsiVmResetFinalProviderResult {
        param(
            [int]$CleanupFailureCount = 0, [int]$UnknownMutationCount = 0, [int]$UnexpectedLedgerEntryCount = 0,
            [int]$SecretScanCount = 0, [string]$VmpState = 'KNOWN', [string]$RebootState = 'KNOWN',
            [string]$UninstallState = 'KNOWN', [string]$CompensationState = 'KNOWN'
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-final-state-v1'; VmpState = $VmpState
            RebootState = $RebootState; UninstallState = $UninstallState; CompensationState = $CompensationState
            CleanupFailureCount = $CleanupFailureCount; UnknownMutationCount = $UnknownMutationCount
            UnexpectedLedgerEntryCount = $UnexpectedLedgerEntryCount; SecretScanCount = $SecretScanCount
        }
    }

    function New-CddsiVmResetActionReceiptsFixture {
        param([Parameter(Mandatory = $true)]$Plan, [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$ExecutionMode = 'TestSafe')
        $receipts = @()
        foreach ($action in @($Plan.Actions)) {
            $withoutBinding = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-action-receipt-v1'; CycleId = $Plan.CycleId
                PlanBindingToken = $Plan.PlanBindingToken; Sequence = $action.Sequence; ResourceId = $action.ResourceId
                ResourceType = $action.ResourceType; Provider = $action.Provider; Operation = $action.Operation
                ResourceToken = $action.ResourceToken; OwnershipReceiptBindingToken = $action.OwnershipReceiptBindingToken
                ExecutionMode = $ExecutionMode; Outcome = 'COMPLETED'; Changed = $false; FailureCode = ''
                ProviderEvidenceDigest = (($action.Sequence + 8).ToString('x') * 64)
                StartedAtUtc = '2030-01-01T00:00:01Z'; CompletedAtUtc = '2030-01-01T00:00:02Z'
            }
            $receipt = [pscustomobject][ordered]@{}
            foreach ($property in $withoutBinding.PSObject.Properties) { Add-Member -InputObject $receipt -NotePropertyName $property.Name -NotePropertyValue $property.Value }
            Add-Member -InputObject $receipt -NotePropertyName ReceiptBindingToken -NotePropertyValue (Get-CddsiVmResetBindingToken -Value $withoutBinding)
            $receipts += $receipt
        }
        return @($receipts)
    }

    function New-CddsiVmResetExpectedCalls {
        param(
            [Parameter(Mandatory = $true)]$Policy, [Parameter(Mandatory = $true)]$Plan,
            [Parameter(Mandatory = $true)]$BaselineBefore, [Parameter(Mandatory = $true)]$BaselineAfter,
            [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ActionReceipts,
            [Parameter(Mandatory = $true)]$FinalProviderResult
        )
        $calls = @()
        foreach ($observation in @($BaselineBefore.Observations)) {
            $calls += [pscustomobject]@{
                Provider = $observation.Provider; Operation = 'Inspect'; ResourceToken = $observation.ResourceToken
                Arguments = [ordered]@{ Purpose = 'VmResetBaseline'; Phase = 'Before'; ResetPolicyDigest = $Policy.ResetPolicyDigest }
                Result = [pscustomobject]@{ SchemaVersion = 1; StateDigest = $observation.StateDigest }
            }
        }
        foreach ($action in @($Plan.Actions)) {
            $matching = @($ActionReceipts | Where-Object { $_.Sequence -eq $action.Sequence })
            $result = if ($matching.Count -eq 1) { $matching[0] } else { $null }
            $calls += [pscustomobject]@{
                Provider = $action.Provider; Operation = 'Inspect'; ResourceToken = $action.ResourceToken
                Arguments = [ordered]@{
                    Purpose = 'VmResetSyntheticAction'; PlanBindingToken = $Plan.PlanBindingToken; Sequence = [int]$action.Sequence
                    TargetOperation = $action.Operation; OwnershipReceiptBindingToken = $action.OwnershipReceiptBindingToken
                }
                Result = $result
            }
        }
        foreach ($observation in @($BaselineAfter.Observations)) {
            $calls += [pscustomobject]@{
                Provider = $observation.Provider; Operation = 'Inspect'; ResourceToken = $observation.ResourceToken
                Arguments = [ordered]@{ Purpose = 'VmResetBaseline'; Phase = 'After'; ResetPolicyDigest = $Policy.ResetPolicyDigest }
                Result = [pscustomobject]@{ SchemaVersion = 1; StateDigest = $observation.StateDigest }
            }
        }
        $calls += [pscustomobject]@{
            Provider = 'Environment'; Operation = 'Inspect'; ResourceToken = '<VM_RESET_STATE:FINAL>'
            Arguments = [ordered]@{ Purpose = 'VmResetFinalState'; PlanBindingToken = $Plan.PlanBindingToken }
            Result = $FinalProviderResult
        }
        return @($calls)
    }

    function New-CddsiVmResetFixture {
        param(
            [ValidateSet('TestSafe', 'DryRun')][string]$Mode = 'TestSafe',
            [string[]]$AfterStateDigests,
            $FinalProviderResult
        )
        $before = New-CddsiVmResetBaselineFixture -CapturedAtUtc '2030-01-01T00:00:00Z'
        $after = New-CddsiVmResetBaselineFixture -CapturedAtUtc '2030-01-01T00:00:03Z' -StateDigests $AfterStateDigests
        $ownership = New-CddsiVmResetOwnershipBundle
        $policy = New-CddsiVmResetPolicyFixture -Baseline $before -OwnershipBundle $ownership
        $plan = New-CddsiVmResetPlan -Policy $policy -OwnershipReceipts $ownership.Receipts -CycleId '44000000-0000-4000-8000-000000000001'
        $actions = New-CddsiVmResetActionReceiptsFixture -Plan $plan -ExecutionMode $Mode
        if ($null -eq $FinalProviderResult) { $FinalProviderResult = New-CddsiVmResetFinalProviderResult }
        $calls = New-CddsiVmResetExpectedCalls -Policy $policy -Plan $plan -BaselineBefore $before -BaselineAfter $after -ActionReceipts $actions -FinalProviderResult $FinalProviderResult
        return [pscustomobject]@{
            BaselineBefore = $before; BaselineAfter = $after; Ownership = $ownership; Policy = $policy
            Plan = $plan; Actions = $actions; FinalProviderResult = $FinalProviderResult; ExpectedCalls = $calls
        }
    }
}

Describe 'P10A-0A deterministic guest reset contract' {
    It 'validates the exact frozen allow-list and ownership receipts including owner-marked directory bindings' {
        $fixture = New-CddsiVmResetFixture
        Test-CddsiVmResetPolicy -Policy $fixture.Policy | Should -BeTrue
        for ($index = 0; $index -lt $fixture.Policy.AllowList.Count; $index++) {
            Test-CddsiVmResetOwnershipReceipt -Receipt $fixture.Ownership.Receipts[$index] -AllowListEntry $fixture.Policy.AllowList[$index] | Should -BeTrue
        }
        $directoryReceipt = Copy-CddsiVmResetFixture -Value $fixture.Ownership.Receipts[-1]
        $directoryReceipt.MarkerSha256 = ('d' * 64)
        Test-CddsiVmResetOwnershipReceipt -Receipt $directoryReceipt -AllowListEntry $fixture.Policy.AllowList[-1] | Should -BeFalse
    }

    It 'rejects out-of-allow-list resources, unknown operations, reordered actions, and missing ownership receipts' {
        $fixture = New-CddsiVmResetFixture
        $outside = Copy-CddsiVmResetFixture -Value $fixture.Policy
        $outside.AllowList[1].ResourceToken = '<REAL_REGISTRY>'
        Update-CddsiVmResetPolicyBindings -Policy $outside | Out-Null
        Test-CddsiVmResetPolicy -Policy $outside | Should -BeFalse

        $unknown = Copy-CddsiVmResetFixture -Value $fixture.Policy
        $unknown.AllowList[0].Operation = 'InvokeExpression'
        Update-CddsiVmResetPolicyBindings -Policy $unknown | Out-Null
        Test-CddsiVmResetPolicy -Policy $unknown | Should -BeFalse

        $reordered = Copy-CddsiVmResetFixture -Value $fixture.Policy
        $temporary = $reordered.AllowList[0]; $reordered.AllowList[0] = $reordered.AllowList[1]; $reordered.AllowList[1] = $temporary
        $reordered.AllowList[0].Sequence = 1; $reordered.AllowList[1].Sequence = 2
        Update-CddsiVmResetPolicyBindings -Policy $reordered | Out-Null
        Test-CddsiVmResetPolicy -Policy $reordered | Should -BeFalse

        { New-CddsiVmResetPlan -Policy $fixture.Policy -OwnershipReceipts @($fixture.Ownership.Receipts | Select-Object -Skip 1) -CycleId $fixture.Plan.CycleId } | Should -Throw
    }

    It 'binds the baseline digest to all eight frozen domains and detects pre or post drift' {
        $fixture = New-CddsiVmResetFixture
        Test-CddsiVmResetBaseline -Baseline $fixture.BaselineBefore -Policy $fixture.Policy | Should -BeTrue
        Test-CddsiVmResetBaseline -Baseline $fixture.BaselineAfter -Policy $fixture.Policy | Should -BeTrue
        $drift = Copy-CddsiVmResetFixture -Value $fixture.BaselineAfter
        $drift.Observations[3].StateDigest = ('f' * 64)
        $drift.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $drift
        Test-CddsiVmResetBaseline -Baseline $drift -Policy $fixture.Policy | Should -BeFalse
    }

    It 'requires SnapshotRestore for missing receipts, failures, mutations, drift, and milestone or state ambiguity' {
        $fixture = New-CddsiVmResetFixture
        $finalState = New-CddsiVmResetFinalStateFixture
        $ready = Resolve-CddsiVmResetDisposition -Policy $fixture.Policy -Plan $fixture.Plan `
            -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
            -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $finalState
        $ready.Disposition | Should -BeExactly 'CLEAN_READY'
        $ready.RequiredResetMode | Should -BeExactly 'GuestReset'

        $cases = @(
            [pscustomobject]@{ Reason = 'OWNERSHIP_RECEIPT_MISSING'; Ownership = @($fixture.Ownership.Receipts | Select-Object -Skip 1); Actions = $fixture.Actions; Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 0; Unknown = 0; Unexpected = 0; Secret = 0; Validator = $true; Milestone = 'DevelopmentRetest' },
            [pscustomobject]@{ Reason = 'ACTION_RECEIPT_MISSING'; Ownership = $fixture.Ownership.Receipts; Actions = @($fixture.Actions | Select-Object -Skip 1); Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 0; Unknown = 0; Unexpected = 0; Secret = 0; Validator = $true; Milestone = 'DevelopmentRetest' },
            [pscustomobject]@{ Reason = 'CLEANUP_FAILURE'; Ownership = $fixture.Ownership.Receipts; Actions = $fixture.Actions; Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 1; Unknown = 0; Unexpected = 0; Secret = 0; Validator = $true; Milestone = 'DevelopmentRetest' },
            [pscustomobject]@{ Reason = 'UNKNOWN_MUTATION'; Ownership = $fixture.Ownership.Receipts; Actions = $fixture.Actions; Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 0; Unknown = 1; Unexpected = 0; Secret = 0; Validator = $true; Milestone = 'DevelopmentRetest' },
            [pscustomobject]@{ Reason = 'UNEXPECTED_LEDGER_ENTRY'; Ownership = $fixture.Ownership.Receipts; Actions = $fixture.Actions; Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 0; Unknown = 0; Unexpected = 1; Secret = 0; Validator = $true; Milestone = 'DevelopmentRetest' },
            [pscustomobject]@{ Reason = 'SECRET_SCAN_FINDING'; Ownership = $fixture.Ownership.Receipts; Actions = $fixture.Actions; Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 0; Unknown = 0; Unexpected = 0; Secret = 1; Validator = $true; Milestone = 'DevelopmentRetest' },
            [pscustomobject]@{ Reason = 'RECEIPT_VALIDATOR_UNAVAILABLE'; Ownership = $fixture.Ownership.Receipts; Actions = $fixture.Actions; Before = $fixture.BaselineBefore; After = $fixture.BaselineAfter; State = $finalState; Cleanup = 0; Unknown = 0; Unexpected = 0; Secret = 0; Validator = $false; Milestone = 'DevelopmentRetest' }
        )
        foreach ($case in $cases) {
            $result = Resolve-CddsiVmResetDisposition -Policy $fixture.Policy -Plan $fixture.Plan `
                -OwnershipReceipts $case.Ownership -ActionReceipts $case.Actions -BaselineBefore $case.Before `
                -BaselineAfter $case.After -FinalState $case.State -CleanupFailureCount $case.Cleanup `
                -UnknownMutationCount $case.Unknown -UnexpectedLedgerEntryCount $case.Unexpected `
                -SecretScanCount $case.Secret -ReceiptValidatorAvailable $case.Validator -MilestoneType $case.Milestone
            $result.Disposition | Should -BeExactly 'BLOCKED'
            $result.RequiredResetMode | Should -BeExactly 'SnapshotRestore'
            $result.ReasonCodes | Should -Contain $case.Reason
        }

        foreach ($milestone in @('FirstP10A', 'FreezeFactsP10A', 'FormalP11Pass', 'ReleaseMilestone', 'P12Final')) {
            $result = Resolve-CddsiVmResetDisposition -Policy $fixture.Policy -Plan $fixture.Plan `
                -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
                -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $finalState -MilestoneType $milestone
            $result.Disposition | Should -BeExactly 'BLOCKED'
            $result.ReasonCodes | Should -Contain 'MILESTONE_REQUIRES_SNAPSHOT'
        }

        foreach ($stateName in @('VmpState', 'RebootState', 'UninstallState', 'CompensationState')) {
            $ambiguous = New-CddsiVmResetFinalStateFixture
            $ambiguous.$stateName = 'UNKNOWN'
            $result = Resolve-CddsiVmResetDisposition -Policy $fixture.Policy -Plan $fixture.Plan `
                -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
                -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $ambiguous
            $result.Disposition | Should -BeExactly 'BLOCKED'
            $result.RequiredResetMode | Should -BeExactly 'SnapshotRestore'
            $result.ReasonCodes | Should -Contain (($stateName -replace 'State$', '').ToUpperInvariant() + '_STATE_AMBIGUOUS')
        }

        $drift = Copy-CddsiVmResetFixture -Value $fixture.BaselineAfter
        $drift.Observations[0].StateDigest = ('f' * 64)
        $drift.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $drift
        $result = Resolve-CddsiVmResetDisposition -Policy $fixture.Policy -Plan $fixture.Plan `
            -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
            -BaselineBefore $fixture.BaselineBefore -BaselineAfter $drift -FinalState $finalState
        $result.Disposition | Should -BeExactly 'BLOCKED'
        $result.ReasonCodes | Should -Contain 'BASELINE_DRIFT'
    }

    It 'issues only a diagnostic Fast Lane CLEAN_READY receipt when every binding and count is clean' {
        $fixture = New-CddsiVmResetFixture
        $finalState = New-CddsiVmResetFinalStateFixture
        $receipt = New-CddsiVmCleanReadyReceipt -Policy $fixture.Policy -Plan $fixture.Plan `
            -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
            -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $finalState `
            -StartedAtUtc '2030-01-01T00:00:00Z' -CompletedAtUtc '2030-01-01T00:00:03Z' `
            -ControlIdentity 'vm-tester-fastlane' -AuthenticationDigest ('e' * 64) -ExecutionMode TestSafe
        $receipt.State | Should -BeExactly 'CLEAN_READY'
        $receipt.EvidenceClass | Should -BeExactly 'DIAGNOSTIC_ONLY'
        $receipt.SnapshotReceiptBindingToken | Should -BeExactly 'NOT_APPLICABLE'
        Test-CddsiVmCleanReadyReceipt -Receipt $receipt -Policy $fixture.Policy -Plan $fixture.Plan `
            -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
            -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $finalState | Should -BeTrue

        $forged = Copy-CddsiVmResetFixture -Value $receipt
        $forged.EvidenceClass = 'FORMAL'
        Test-CddsiVmCleanReadyReceipt -Receipt $forged -Policy $fixture.Policy -Plan $fixture.Plan `
            -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
            -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $finalState | Should -BeFalse
        { New-CddsiVmCleanReadyReceipt -Policy $fixture.Policy -Plan $fixture.Plan `
            -OwnershipReceipts $fixture.Ownership.Receipts -ActionReceipts $fixture.Actions `
            -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter -FinalState $finalState `
            -StartedAtUtc '2030-01-01T00:00:00Z' -CompletedAtUtc '2030-01-01T00:00:03Z' `
            -ControlIdentity 'vm-tester-fastlane' -AuthenticationDigest ('e' * 64) -ExecutionMode TestSafe `
            -CleanupFailureCount 1 } | Should -Throw
    }

    It 'runs the complete TestSafe and DryRun fake-provider rehearsal with Changed false and zero mutation spy' {
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $fixture = New-CddsiVmResetFixture -Mode $mode
            $context = New-CddsiTestExecutionContext -Mode $mode -SandboxRoot $TestDrive `
                -RunId $(if ($mode -ceq 'TestSafe') { '45000000-0000-4000-8000-000000000001' } else { '45000000-0000-4000-8000-000000000002' }) `
                -ExpectedCalls $fixture.ExpectedCalls
            $result = Invoke-CddsiVmGuestReset -ExecutionContext $context -Policy $fixture.Policy `
                -OwnershipReceipts $fixture.Ownership.Receipts -CycleId $fixture.Plan.CycleId `
                -StartedAtUtc '2030-01-01T00:00:00Z' -CompletedAtUtc '2030-01-01T00:00:03Z' `
                -ControlIdentity 'vm-tester-fastlane' -AuthenticationDigest ('e' * 64) -Mode $mode
            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.Changed | Should -BeFalse
            $result.Data.Disposition | Should -BeExactly 'CLEAN_READY'
            $result.Data.RequiredResetMode | Should -BeExactly 'GuestReset'
            $result.Data.RealMutationPerformed | Should -BeFalse
            $result.Data.CleanReadyReceipt.ExecutionMode | Should -BeExactly $mode
            Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
            Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $context) | Should -BeTrue
        }
    }

    It 'blocks the fake runner on baseline drift, cleanup failure, or a missing action receipt' {
        $scenarios = @(
            [pscustomobject]@{ Kind = 'Drift'; After = @(('f' * 64)) + @(2..8 | ForEach-Object { $_.ToString('x') * 64 }); Final = (New-CddsiVmResetFinalProviderResult); Missing = $false; Reason = 'BASELINE_DRIFT' },
            [pscustomobject]@{ Kind = 'Cleanup'; After = $null; Final = (New-CddsiVmResetFinalProviderResult -CleanupFailureCount 1); Missing = $false; Reason = 'CLEANUP_FAILURE' },
            [pscustomobject]@{ Kind = 'Missing'; After = $null; Final = (New-CddsiVmResetFinalProviderResult); Missing = $true; Reason = 'ACTION_RECEIPT_MISSING' }
        )
        foreach ($scenario in $scenarios) {
            $fixture = New-CddsiVmResetFixture -AfterStateDigests $scenario.After -FinalProviderResult $scenario.Final
            if ($scenario.Missing) {
                $fixture.ExpectedCalls = New-CddsiVmResetExpectedCalls -Policy $fixture.Policy -Plan $fixture.Plan `
                    -BaselineBefore $fixture.BaselineBefore -BaselineAfter $fixture.BaselineAfter `
                    -ActionReceipts @($fixture.Actions | Select-Object -SkipLast 1) -FinalProviderResult $fixture.FinalProviderResult
            }
            $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive -RunId ('46000000-0000-4000-8000-{0}' -f ([Math]::Abs($scenario.Kind.GetHashCode()).ToString().PadLeft(12, '0').Substring(0, 12))) -ExpectedCalls $fixture.ExpectedCalls
            $result = Invoke-CddsiVmGuestReset -ExecutionContext $context -Policy $fixture.Policy `
                -OwnershipReceipts $fixture.Ownership.Receipts -CycleId $fixture.Plan.CycleId `
                -StartedAtUtc '2030-01-01T00:00:00Z' -CompletedAtUtc '2030-01-01T00:00:03Z' `
                -ControlIdentity 'vm-tester-fastlane' -AuthenticationDigest ('e' * 64) -Mode TestSafe
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            $result.Data.Disposition | Should -BeExactly 'BLOCKED'
            $result.Data.RequiredResetMode | Should -BeExactly 'SnapshotRestore'
            $result.Warnings | Should -Contain $scenario.Reason
            $result.Data.CleanReadyReceipt | Should -BeNullOrEmpty
            Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        }
    }

    It 'fails Scaffold Live before provider dispatch and treats free text as inert untrusted data' {
        $fixture = New-CddsiVmResetFixture
        $context = New-CddsiTestExecutionContext -SandboxRoot $TestDrive
        { Invoke-CddsiVmGuestReset -ExecutionContext $context -Policy $fixture.Policy `
            -OwnershipReceipts $fixture.Ownership.Receipts -CycleId $fixture.Plan.CycleId `
            -StartedAtUtc '2030-01-01T00:00:00Z' -CompletedAtUtc '2030-01-01T00:00:03Z' `
            -ControlIdentity 'vm-tester-fastlane' -AuthenticationDigest ('e' * 64) -Mode Live -AcknowledgeRealChanges } | Should -Throw
        $context.Providers.Cursor | Should -Be 0
        @($context.Providers.MutationSpy).Count | Should -Be 0

        $script:VmResetInjectedTextExecuted = $false
        $injected = Copy-CddsiVmResetFixture -Value $fixture.Policy
        Add-Member -InputObject $injected.AllowList[0] -NotePropertyName Command -NotePropertyValue { $script:VmResetInjectedTextExecuted = $true }
        Test-CddsiVmResetPolicy -Policy $injected | Should -BeFalse
        $script:VmResetInjectedTextExecuted | Should -BeFalse

        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $script:RepoRoot 'lib\vm-reset.ps1'), [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $commandNames = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        foreach ($forbidden in @('Invoke-Expression', 'Start-Process', 'Remove-Item', 'Remove-AppxPackage', 'Remove-ItemProperty', 'reg.exe', 'schtasks.exe', 'cmd.exe', 'powershell.exe')) {
            $commandNames | Should -Not -Contain $forbidden
        }
    }
}
