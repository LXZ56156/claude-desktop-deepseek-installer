# vm-reset.ps1 - Pure P10A-0A deterministic guest-reset contracts.
#
# This operator-coordination module is intentionally not loaded by the default
# product bootstrap. It performs no filesystem, registry, package, credential,
# process, scheduled-task, network or clock access at load time. TestSafe and
# DryRun use only declared fake-provider Inspect calls. Scaffold Live execution
# remains fail closed before any provider dispatch.

$script:CddsiVmResetResourceTypeOrder = @(
    'Package',
    'HkcuValue',
    'Credential',
    'Checkpoint',
    'OwnerMarkedDirectory'
)

$script:CddsiVmResetBaselineSpecifications = @(
    [pscustomobject][ordered]@{ Sequence = 1; Domain = 'OS';         Provider = 'Environment'; ResourceToken = '<VM_RESET_BASELINE:OS>' },
    [pscustomobject][ordered]@{ Sequence = 2; Domain = 'AppX';       Provider = 'Package';     ResourceToken = '<VM_RESET_BASELINE:APPX>' },
    [pscustomobject][ordered]@{ Sequence = 3; Domain = 'Git';        Provider = 'Process';     ResourceToken = '<VM_RESET_BASELINE:GIT>' },
    [pscustomobject][ordered]@{ Sequence = 4; Domain = 'VMP';        Provider = 'Feature';     ResourceToken = '<VM_RESET_BASELINE:VMP>' },
    [pscustomobject][ordered]@{ Sequence = 5; Domain = 'Registry';   Provider = 'Registry';    ResourceToken = '<VM_RESET_BASELINE:REGISTRY>' },
    [pscustomobject][ordered]@{ Sequence = 6; Domain = 'Credential'; Provider = 'Credential';  ResourceToken = '<VM_RESET_BASELINE:CREDENTIAL>' },
    [pscustomobject][ordered]@{ Sequence = 7; Domain = 'Checkpoint'; Provider = 'FileSystem';  ResourceToken = '<VM_RESET_BASELINE:CHECKPOINT>' },
    [pscustomobject][ordered]@{ Sequence = 8; Domain = 'FileSystem'; Provider = 'FileSystem';  ResourceToken = '<VM_RESET_BASELINE:FILESYSTEM>' }
)

$script:CddsiVmResetNotApplicable = 'NOT_APPLICABLE'

function Get-CddsiVmResetBindingToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Value
    )

    # The already-gated P10A canonical encoder is reused only as a pure SHA-256
    # integrity primitive. A binding token is not an authorization receipt.
    return Get-CddsiVmCalibrationCanonicalBindingToken -Value $Value
}

function Test-CddsiVmResetAllowListEntry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Entry
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Entry -Expected @(
        'Sequence', 'ResourceId', 'ResourceType', 'Provider', 'Operation',
        'ResourceToken', 'OwnerRunId', 'ResourceIdentitySha256', 'MarkerSha256',
        'PreexistingPathBindingToken', 'OwnershipReceiptBindingToken'
    ))) { return $false }

    if (($Entry.Sequence -isnot [int] -and $Entry.Sequence -isnot [long]) -or [long]$Entry.Sequence -lt 1 -or [long]$Entry.Sequence -gt 128) { return $false }
    if (-not (Test-CddsiSafeIdentifierValue -Value $Entry.ResourceId -MaxLength 64)) { return $false }
    if ($script:CddsiVmResetResourceTypeOrder -cnotcontains $Entry.ResourceType) { return $false }
    if (-not (Test-CddsiCanonicalUuidValue -Value $Entry.OwnerRunId)) { return $false }
    if (-not (Test-CddsiVmCalibrationSha256Value -Value $Entry.ResourceIdentitySha256)) { return $false }
    if (-not (Test-CddsiVmCalibrationSha256Value -Value $Entry.OwnershipReceiptBindingToken)) { return $false }

    $expectedProvider = ''
    $expectedOperation = ''
    $tokenPattern = ''
    switch -CaseSensitive ($Entry.ResourceType) {
        'Package' {
            $expectedProvider = 'Package'
            $expectedOperation = 'Remove'
            $tokenPattern = '^<VM_RESET_PACKAGE:[A-Z0-9][A-Z0-9_.:-]{0,63}>$'
            break
        }
        'HkcuValue' {
            $expectedProvider = 'Registry'
            $expectedOperation = 'DeleteValue'
            $tokenPattern = '^<VM_RESET_HKCU:[A-Z0-9][A-Z0-9_.:-]{0,63}>$'
            break
        }
        'Credential' {
            $expectedProvider = 'Credential'
            $expectedOperation = 'Delete'
            $tokenPattern = '^<VM_RESET_CREDENTIAL:[A-Z0-9][A-Z0-9_.:-]{0,63}>$'
            break
        }
        'Checkpoint' {
            $expectedProvider = 'FileSystem'
            $expectedOperation = 'DeleteFile'
            $tokenPattern = '^<VM_RESET_CHECKPOINT:[A-Z0-9][A-Z0-9_.:-]{0,63}>$'
            break
        }
        'OwnerMarkedDirectory' {
            $expectedProvider = 'FileSystem'
            $expectedOperation = 'DeleteDirectory'
            $tokenPattern = '^<VM_RESET_DIRECTORY:[A-Z0-9][A-Z0-9_.:-]{0,63}>$'
            break
        }
        default { return $false }
    }

    if ($Entry.Provider -cne $expectedProvider -or $Entry.Operation -cne $expectedOperation) { return $false }
    if ($Entry.ResourceToken -isnot [string] -or $Entry.ResourceToken -notmatch $tokenPattern) { return $false }
    if (-not (Test-CddsiLogicalResourceToken -ResourceToken $Entry.ResourceToken)) { return $false }

    if ($Entry.ResourceType -ceq 'OwnerMarkedDirectory') {
        if (-not (Test-CddsiVmCalibrationSha256Value -Value $Entry.MarkerSha256) -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $Entry.PreexistingPathBindingToken)) { return $false }
    }
    elseif ($Entry.MarkerSha256 -isnot [string] -or $Entry.MarkerSha256 -cne $script:CddsiVmResetNotApplicable -or
        $Entry.PreexistingPathBindingToken -isnot [string] -or $Entry.PreexistingPathBindingToken -cne $script:CddsiVmResetNotApplicable) {
        return $false
    }

    return $true
}

function Test-CddsiVmResetOwnershipReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Receipt,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $AllowListEntry
    )

    if (-not (Test-CddsiVmResetAllowListEntry -Entry $AllowListEntry)) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $Receipt -Expected @(
        'SchemaVersion', 'ContractVersion', 'ReceiptId', 'OwnerId', 'OwnerRunId',
        'ResourceId', 'ResourceType', 'Provider', 'Operation', 'ResourceToken',
        'ResourceIdentitySha256', 'MarkerSha256', 'PreexistingPathBindingToken',
        'IssuedAtUtc', 'ReceiptBindingToken'
    ))) { return $false }

    if (-not (Test-CddsiSchemaVersionOne -Value $Receipt.SchemaVersion) -or
        $Receipt.ContractVersion -cne 'cddsi-vm-reset-ownership-receipt-v1' -or
        -not (Test-CddsiCanonicalUuidValue -Value $Receipt.ReceiptId) -or
        $Receipt.OwnerId -cne 'cddsi-vm-test' -or
        -not (Test-CddsiUtcTimestampValue -Value $Receipt.IssuedAtUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Receipt.ReceiptBindingToken)) { return $false }

    foreach ($name in @(
        'OwnerRunId', 'ResourceId', 'ResourceType', 'Provider', 'Operation',
        'ResourceToken', 'ResourceIdentitySha256', 'MarkerSha256',
        'PreexistingPathBindingToken'
    )) {
        if ($Receipt.$name -isnot [string] -or $Receipt.$name -cne $AllowListEntry.$name) { return $false }
    }

    $payload = [pscustomobject][ordered]@{
        SchemaVersion                = $Receipt.SchemaVersion
        ContractVersion              = $Receipt.ContractVersion
        ReceiptId                    = $Receipt.ReceiptId
        OwnerId                      = $Receipt.OwnerId
        OwnerRunId                   = $Receipt.OwnerRunId
        ResourceId                   = $Receipt.ResourceId
        ResourceType                 = $Receipt.ResourceType
        Provider                     = $Receipt.Provider
        Operation                    = $Receipt.Operation
        ResourceToken                = $Receipt.ResourceToken
        ResourceIdentitySha256       = $Receipt.ResourceIdentitySha256
        MarkerSha256                 = $Receipt.MarkerSha256
        PreexistingPathBindingToken  = $Receipt.PreexistingPathBindingToken
        IssuedAtUtc                  = $Receipt.IssuedAtUtc
    }
    $expectedBinding = Get-CddsiVmResetBindingToken -Value $payload
    return ($Receipt.ReceiptBindingToken -ceq $expectedBinding -and $AllowListEntry.OwnershipReceiptBindingToken -ceq $expectedBinding)
}

function Test-CddsiVmResetPolicy {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Policy
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Policy -Expected @(
        'SchemaVersion', 'ContractVersion', 'PolicyId', 'PolicyRevision', 'Lane',
        'EnvironmentResetMode', 'VmIdentity', 'ImageSha256', 'Frozen',
        'ExpectedBaselineDigest', 'AllowList', 'AllowListDigest', 'ResetPolicyDigest'
    ))) { return $false }

    if (-not (Test-CddsiSchemaVersionOne -Value $Policy.SchemaVersion) -or
        $Policy.ContractVersion -cne 'cddsi-vm-reset-policy-v1' -or
        -not (Test-CddsiCanonicalUuidValue -Value $Policy.PolicyId) -or
        ($Policy.PolicyRevision -isnot [int] -and $Policy.PolicyRevision -isnot [long]) -or
        [long]$Policy.PolicyRevision -lt 1 -or
        $Policy.Lane -cne 'FastLane' -or
        $Policy.EnvironmentResetMode -cne 'GuestReset' -or
        -not (Test-CddsiSafeIdentifierValue -Value $Policy.VmIdentity -MaxLength 128) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.ImageSha256) -or
        $Policy.Frozen -isnot [bool] -or -not $Policy.Frozen -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.ExpectedBaselineDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.AllowListDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.ResetPolicyDigest)) { return $false }

    $entries = @($Policy.AllowList)
    if ($entries.Count -lt 1 -or $entries.Count -gt 128) { return $false }

    $resourceIds = @()
    $resourceTokens = @()
    $receiptBindings = @()
    $previousTypeIndex = -1
    for ($index = 0; $index -lt $entries.Count; $index++) {
        $entry = $entries[$index]
        if (-not (Test-CddsiVmResetAllowListEntry -Entry $entry) -or [int]$entry.Sequence -ne ($index + 1)) { return $false }
        $typeIndex = [Array]::IndexOf($script:CddsiVmResetResourceTypeOrder, [string]$entry.ResourceType)
        if ($typeIndex -lt $previousTypeIndex) { return $false }
        $previousTypeIndex = $typeIndex
        $resourceIds += [string]$entry.ResourceId
        $resourceTokens += [string]$entry.ResourceToken
        $receiptBindings += [string]$entry.OwnershipReceiptBindingToken
    }

    foreach ($values in @($resourceIds, $resourceTokens, $receiptBindings)) {
        if (@($values | Sort-Object -Unique -CaseSensitive).Count -ne @($values).Count) { return $false }
    }

    $expectedAllowListDigest = Get-CddsiVmResetBindingToken -Value @($entries)
    if ($Policy.AllowListDigest -cne $expectedAllowListDigest) { return $false }
    $payload = [pscustomobject][ordered]@{
        SchemaVersion          = $Policy.SchemaVersion
        ContractVersion        = $Policy.ContractVersion
        PolicyId               = $Policy.PolicyId
        PolicyRevision         = $Policy.PolicyRevision
        Lane                   = $Policy.Lane
        EnvironmentResetMode   = $Policy.EnvironmentResetMode
        VmIdentity             = $Policy.VmIdentity
        ImageSha256            = $Policy.ImageSha256
        Frozen                 = $Policy.Frozen
        ExpectedBaselineDigest = $Policy.ExpectedBaselineDigest
        AllowList              = @($entries)
        AllowListDigest        = $Policy.AllowListDigest
    }
    return ($Policy.ResetPolicyDigest -ceq (Get-CddsiVmResetBindingToken -Value $payload))
}

function Get-CddsiVmResetBaselineDigest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Baseline
    )

    $payload = [pscustomobject][ordered]@{
        SchemaVersion   = $Baseline.SchemaVersion
        ContractVersion = $Baseline.ContractVersion
        VmIdentity      = $Baseline.VmIdentity
        ImageSha256     = $Baseline.ImageSha256
        Observations    = @($Baseline.Observations)
    }
    return Get-CddsiVmResetBindingToken -Value $payload
}

function Test-CddsiVmResetBaseline {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Baseline,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Policy
    )

    if (-not (Test-CddsiVmResetPolicy -Policy $Policy)) { return $false }
    if (-not (Test-CddsiExactPropertySet -InputObject $Baseline -Expected @(
        'SchemaVersion', 'ContractVersion', 'VmIdentity', 'ImageSha256',
        'CapturedAtUtc', 'Observations', 'BaselineDigest'
    ))) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Baseline.SchemaVersion) -or
        $Baseline.ContractVersion -cne 'cddsi-vm-reset-baseline-v1' -or
        $Baseline.VmIdentity -cne $Policy.VmIdentity -or
        $Baseline.ImageSha256 -cne $Policy.ImageSha256 -or
        -not (Test-CddsiUtcTimestampValue -Value $Baseline.CapturedAtUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Baseline.BaselineDigest)) { return $false }

    $observations = @($Baseline.Observations)
    if ($observations.Count -ne $script:CddsiVmResetBaselineSpecifications.Count) { return $false }
    for ($index = 0; $index -lt $observations.Count; $index++) {
        $observation = $observations[$index]
        $expected = $script:CddsiVmResetBaselineSpecifications[$index]
        if (-not (Test-CddsiExactPropertySet -InputObject $observation -Expected @(
            'Sequence', 'Domain', 'Provider', 'ResourceToken', 'StateDigest'
        ))) { return $false }
        if (($observation.Sequence -isnot [int] -and $observation.Sequence -isnot [long]) -or
            [long]$observation.Sequence -ne [long]$expected.Sequence -or
            $observation.Domain -cne $expected.Domain -or
            $observation.Provider -cne $expected.Provider -or
            $observation.ResourceToken -cne $expected.ResourceToken -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $observation.StateDigest)) { return $false }
    }

    $expectedDigest = Get-CddsiVmResetBaselineDigest -Baseline $Baseline
    return ($Baseline.BaselineDigest -ceq $expectedDigest -and $Baseline.BaselineDigest -ceq $Policy.ExpectedBaselineDigest)
}

function New-CddsiVmResetPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        $Policy,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$OwnershipReceipts,

        [Parameter(Mandatory = $true)]
        [string]$CycleId
    )

    if (-not (Test-CddsiVmResetPolicy -Policy $Policy)) { throw 'VM reset policy is invalid or is not frozen.' }
    if (-not (Test-CddsiCanonicalUuidValue -Value $CycleId)) { throw 'CycleId must be a canonical non-empty UUID.' }
    $entries = @($Policy.AllowList)
    $receipts = @($OwnershipReceipts)
    if ($receipts.Count -ne $entries.Count) { throw 'Every frozen allow-list entry requires exactly one ownership receipt.' }

    $actions = @()
    foreach ($entry in $entries) {
        $matches = @($receipts | Where-Object { $_.ReceiptBindingToken -is [string] -and $_.ReceiptBindingToken -ceq $entry.OwnershipReceiptBindingToken })
        if ($matches.Count -ne 1 -or -not (Test-CddsiVmResetOwnershipReceipt -Receipt $matches[0] -AllowListEntry $entry)) {
            throw 'Ownership receipt is missing, duplicated, or not bound to the frozen allow-list entry.'
        }
        $actions += [pscustomobject][ordered]@{
            Sequence                       = [int]$entry.Sequence
            ResourceId                     = $entry.ResourceId
            ResourceType                   = $entry.ResourceType
            Provider                       = $entry.Provider
            Operation                      = $entry.Operation
            ResourceToken                  = $entry.ResourceToken
            OwnershipReceiptBindingToken   = $entry.OwnershipReceiptBindingToken
        }
    }

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion      = 1
        ContractVersion    = 'cddsi-vm-reset-plan-v1'
        CycleId            = $CycleId
        VmIdentity         = $Policy.VmIdentity
        ImageSha256        = $Policy.ImageSha256
        ResetPolicyDigest  = $Policy.ResetPolicyDigest
        AllowListDigest    = $Policy.AllowListDigest
        Frozen             = $true
        Actions            = @($actions)
    }
    return [pscustomobject][ordered]@{
        SchemaVersion      = $withoutBinding.SchemaVersion
        ContractVersion    = $withoutBinding.ContractVersion
        CycleId            = $withoutBinding.CycleId
        VmIdentity         = $withoutBinding.VmIdentity
        ImageSha256        = $withoutBinding.ImageSha256
        ResetPolicyDigest  = $withoutBinding.ResetPolicyDigest
        AllowListDigest    = $withoutBinding.AllowListDigest
        Frozen             = $withoutBinding.Frozen
        Actions            = $withoutBinding.Actions
        PlanBindingToken   = Get-CddsiVmResetBindingToken -Value $withoutBinding
    }
}

function Test-CddsiVmResetPlan {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Plan,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Policy,

        [Parameter(Mandatory = $true)]
        [AllowEmptyCollection()]
        [object[]]$OwnershipReceipts
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Plan -Expected @(
        'SchemaVersion', 'ContractVersion', 'CycleId', 'VmIdentity', 'ImageSha256',
        'ResetPolicyDigest', 'AllowListDigest', 'Frozen', 'Actions', 'PlanBindingToken'
    ))) { return $false }
    if (-not (Test-CddsiVmCalibrationSha256Value -Value $Plan.PlanBindingToken)) { return $false }

    try {
        $expected = New-CddsiVmResetPlan -Policy $Policy -OwnershipReceipts $OwnershipReceipts -CycleId $Plan.CycleId
    }
    catch { return $false }
    return (
        $Plan.PlanBindingToken -ceq $expected.PlanBindingToken -and
        (Get-CddsiVmResetBindingToken -Value $Plan) -ceq (Get-CddsiVmResetBindingToken -Value $expected)
    )
}

function Test-CddsiVmResetActionReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Receipt,

        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Plan
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Receipt -Expected @(
        'SchemaVersion', 'ContractVersion', 'CycleId', 'PlanBindingToken',
        'Sequence', 'ResourceId', 'ResourceType', 'Provider', 'Operation',
        'ResourceToken', 'OwnershipReceiptBindingToken', 'ExecutionMode',
        'Outcome', 'Changed', 'FailureCode', 'ProviderEvidenceDigest',
        'StartedAtUtc', 'CompletedAtUtc', 'ReceiptBindingToken'
    ))) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Receipt.SchemaVersion) -or
        $Receipt.ContractVersion -cne 'cddsi-vm-reset-action-receipt-v1' -or
        $Receipt.CycleId -isnot [string] -or $Receipt.CycleId -cne $Plan.CycleId -or
        $Receipt.PlanBindingToken -isnot [string] -or $Receipt.PlanBindingToken -cne $Plan.PlanBindingToken -or
        @('TestSafe', 'DryRun', 'Live') -cnotcontains $Receipt.ExecutionMode -or
        @('COMPLETED', 'FAILED', 'AMBIGUOUS') -cnotcontains $Receipt.Outcome -or
        $Receipt.Changed -isnot [bool] -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Receipt.ProviderEvidenceDigest) -or
        -not (Test-CddsiUtcTimestampValue -Value $Receipt.StartedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Receipt.CompletedAtUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Receipt.ReceiptBindingToken)) { return $false }
    if ($Receipt.ExecutionMode -cne 'Live' -and $Receipt.Changed) { return $false }
    if ([DateTimeOffset]::Parse($Receipt.CompletedAtUtc) -lt [DateTimeOffset]::Parse($Receipt.StartedAtUtc)) { return $false }
    if ($Receipt.Outcome -ceq 'COMPLETED') {
        if ($Receipt.FailureCode -isnot [string] -or $Receipt.FailureCode -cne '') { return $false }
    }
    elseif (-not (Test-CddsiSafeIdentifierValue -Value $Receipt.FailureCode -MaxLength 64)) { return $false }

    $actions = @($Plan.Actions)
    if (($Receipt.Sequence -isnot [int] -and $Receipt.Sequence -isnot [long]) -or [long]$Receipt.Sequence -lt 1 -or [long]$Receipt.Sequence -gt $actions.Count) { return $false }
    $action = $actions[[int]$Receipt.Sequence - 1]
    foreach ($name in @('Sequence', 'ResourceId', 'ResourceType', 'Provider', 'Operation', 'ResourceToken', 'OwnershipReceiptBindingToken')) {
        if ($Receipt.$name -is [string]) {
            if ($Receipt.$name -cne $action.$name) { return $false }
        }
        elseif ([long]$Receipt.$name -ne [long]$action.$name) { return $false }
    }

    $payload = [pscustomobject][ordered]@{
        SchemaVersion                   = $Receipt.SchemaVersion
        ContractVersion                 = $Receipt.ContractVersion
        CycleId                         = $Receipt.CycleId
        PlanBindingToken                = $Receipt.PlanBindingToken
        Sequence                        = $Receipt.Sequence
        ResourceId                      = $Receipt.ResourceId
        ResourceType                    = $Receipt.ResourceType
        Provider                        = $Receipt.Provider
        Operation                       = $Receipt.Operation
        ResourceToken                   = $Receipt.ResourceToken
        OwnershipReceiptBindingToken    = $Receipt.OwnershipReceiptBindingToken
        ExecutionMode                   = $Receipt.ExecutionMode
        Outcome                         = $Receipt.Outcome
        Changed                         = $Receipt.Changed
        FailureCode                     = $Receipt.FailureCode
        ProviderEvidenceDigest          = $Receipt.ProviderEvidenceDigest
        StartedAtUtc                    = $Receipt.StartedAtUtc
        CompletedAtUtc                  = $Receipt.CompletedAtUtc
    }
    return ($Receipt.ReceiptBindingToken -ceq (Get-CddsiVmResetBindingToken -Value $payload))
}

function Resolve-CddsiVmResetDisposition {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Policy,
        [Parameter(Mandatory = $true)][AllowNull()]$Plan,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ActionReceipts,
        [Parameter(Mandatory = $true)][AllowNull()]$BaselineBefore,
        [Parameter(Mandatory = $true)][AllowNull()]$BaselineAfter,
        [Parameter(Mandatory = $true)][AllowNull()]$FinalState,

        [ValidateRange(0, 2147483647)][int]$CleanupFailureCount = 0,
        [ValidateRange(0, 2147483647)][int]$UnknownMutationCount = 0,
        [ValidateRange(0, 2147483647)][int]$UnexpectedLedgerEntryCount = 0,
        [ValidateRange(0, 2147483647)][int]$SecretScanCount = 0,
        [bool]$ReceiptValidatorAvailable = $true,

        [ValidateSet('DevelopmentRetest', 'FirstP10A', 'FreezeFactsP10A', 'FormalP11Pass', 'ReleaseMilestone', 'P12Final')]
        [string]$MilestoneType = 'DevelopmentRetest'
    )

    $reasons = [System.Collections.ArrayList]@()
    if ($MilestoneType -cne 'DevelopmentRetest') { [void]$reasons.Add('MILESTONE_REQUIRES_SNAPSHOT') }
    if (-not $ReceiptValidatorAvailable) { [void]$reasons.Add('RECEIPT_VALIDATOR_UNAVAILABLE') }

    $policyValid = Test-CddsiVmResetPolicy -Policy $Policy
    if (-not $policyValid) { [void]$reasons.Add('RESET_POLICY_INVALID') }

    $receiptArray = @($OwnershipReceipts)
    if ($policyValid -and $receiptArray.Count -lt @($Policy.AllowList).Count) { [void]$reasons.Add('OWNERSHIP_RECEIPT_MISSING') }
    if ($policyValid -and $receiptArray.Count -gt @($Policy.AllowList).Count) { [void]$reasons.Add('OWNERSHIP_RECEIPT_INVALID') }

    $planValid = $false
    if ($policyValid) { $planValid = Test-CddsiVmResetPlan -Plan $Plan -Policy $Policy -OwnershipReceipts $receiptArray }
    if (-not $planValid) { [void]$reasons.Add('RESET_PLAN_INVALID') }

    $beforeValid = $false
    $afterValid = $false
    if ($policyValid) {
        $beforeValid = Test-CddsiVmResetBaseline -Baseline $BaselineBefore -Policy $Policy
        $afterValid = Test-CddsiVmResetBaseline -Baseline $BaselineAfter -Policy $Policy
    }
    if (-not $beforeValid -or -not $afterValid -or
        ($beforeValid -and $afterValid -and $BaselineBefore.BaselineDigest -cne $BaselineAfter.BaselineDigest)) {
        [void]$reasons.Add('BASELINE_DRIFT')
    }

    $actionArray = @($ActionReceipts)
    if ($planValid) {
        $expectedActionCount = @($Plan.Actions).Count
        if ($actionArray.Count -lt $expectedActionCount) { [void]$reasons.Add('ACTION_RECEIPT_MISSING') }
        if ($actionArray.Count -gt $expectedActionCount) { [void]$reasons.Add('ACTION_RECEIPT_INVALID') }
        foreach ($action in @($Plan.Actions)) {
            $matches = @($actionArray | Where-Object { $_.Sequence -eq $action.Sequence })
            if ($matches.Count -eq 0) { continue }
            if ($matches.Count -ne 1 -or -not (Test-CddsiVmResetActionReceipt -Receipt $matches[0] -Plan $Plan)) {
                [void]$reasons.Add('ACTION_RECEIPT_INVALID')
                continue
            }
            if ($matches[0].Outcome -ceq 'FAILED') { [void]$reasons.Add('CLEANUP_FAILURE') }
            if ($matches[0].Outcome -ceq 'AMBIGUOUS') { [void]$reasons.Add('ACTION_STATE_AMBIGUOUS') }
        }
    }

    if ($CleanupFailureCount -ne 0) { [void]$reasons.Add('CLEANUP_FAILURE') }
    if ($UnknownMutationCount -ne 0) { [void]$reasons.Add('UNKNOWN_MUTATION') }
    if ($UnexpectedLedgerEntryCount -ne 0) { [void]$reasons.Add('UNEXPECTED_LEDGER_ENTRY') }
    if ($SecretScanCount -ne 0) { [void]$reasons.Add('SECRET_SCAN_FINDING') }

    if (-not (Test-CddsiExactPropertySet -InputObject $FinalState -Expected @(
        'SchemaVersion', 'ContractVersion', 'VmpState', 'RebootState',
        'UninstallState', 'CompensationState'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $FinalState.SchemaVersion) -or
        $FinalState.ContractVersion -cne 'cddsi-vm-reset-final-state-v1') {
        [void]$reasons.Add('FINAL_STATE_INVALID')
    }
    else {
        foreach ($name in @('VmpState', 'RebootState', 'UninstallState', 'CompensationState')) {
            if (@('KNOWN', 'UNKNOWN') -cnotcontains $FinalState.$name) { [void]$reasons.Add('FINAL_STATE_INVALID') }
        }
        if ($FinalState.VmpState -cne 'KNOWN') { [void]$reasons.Add('VMP_STATE_AMBIGUOUS') }
        if ($FinalState.RebootState -cne 'KNOWN') { [void]$reasons.Add('REBOOT_STATE_AMBIGUOUS') }
        if ($FinalState.UninstallState -cne 'KNOWN') { [void]$reasons.Add('UNINSTALL_STATE_AMBIGUOUS') }
        if ($FinalState.CompensationState -cne 'KNOWN') { [void]$reasons.Add('COMPENSATION_STATE_AMBIGUOUS') }
    }

    $uniqueReasons = @()
    foreach ($reason in @($reasons)) {
        if ($uniqueReasons -cnotcontains $reason) { $uniqueReasons += [string]$reason }
    }
    $canIssue = ($uniqueReasons.Count -eq 0)
    return [pscustomobject][ordered]@{
        SchemaVersion           = 1
        ContractVersion         = 'cddsi-vm-reset-disposition-v1'
        Disposition             = $(if ($canIssue) { 'CLEAN_READY' } else { 'BLOCKED' })
        RequiredResetMode       = $(if ($canIssue) { 'GuestReset' } else { 'SnapshotRestore' })
        CanIssueCleanReady       = $canIssue
        SnapshotRestoreRequired = (-not $canIssue)
        ReasonCodes             = @($uniqueReasons)
    }
}

function New-CddsiVmCleanReadyReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ActionReceipts,
        [Parameter(Mandatory = $true)]$BaselineBefore,
        [Parameter(Mandatory = $true)]$BaselineAfter,
        [Parameter(Mandatory = $true)]$FinalState,
        [Parameter(Mandatory = $true)][string]$StartedAtUtc,
        [Parameter(Mandatory = $true)][string]$CompletedAtUtc,
        [Parameter(Mandatory = $true)][string]$ControlIdentity,
        [Parameter(Mandatory = $true)][string]$AuthenticationDigest,
        [Parameter(Mandatory = $true)][ValidateSet('TestSafe', 'DryRun', 'Live')][string]$ExecutionMode,

        [ValidateRange(0, 2147483647)][int]$CleanupFailureCount = 0,
        [ValidateRange(0, 2147483647)][int]$UnknownMutationCount = 0,
        [ValidateRange(0, 2147483647)][int]$UnexpectedLedgerEntryCount = 0,
        [ValidateRange(0, 2147483647)][int]$SecretScanCount = 0,
        [bool]$ReceiptValidatorAvailable = $true
    )

    if (-not (Test-CddsiUtcTimestampValue -Value $StartedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $CompletedAtUtc) -or
        [DateTimeOffset]::Parse($CompletedAtUtc) -lt [DateTimeOffset]::Parse($StartedAtUtc)) { throw 'CLEAN_READY timestamps are invalid.' }
    if (-not (Test-CddsiSafeIdentifierValue -Value $ControlIdentity -MaxLength 128)) { throw 'Control identity is invalid.' }
    if (-not (Test-CddsiVmCalibrationSha256Value -Value $AuthenticationDigest)) { throw 'Authentication digest is invalid.' }

    $disposition = Resolve-CddsiVmResetDisposition -Policy $Policy -Plan $Plan `
        -OwnershipReceipts $OwnershipReceipts -ActionReceipts $ActionReceipts `
        -BaselineBefore $BaselineBefore -BaselineAfter $BaselineAfter -FinalState $FinalState `
        -CleanupFailureCount $CleanupFailureCount -UnknownMutationCount $UnknownMutationCount `
        -UnexpectedLedgerEntryCount $UnexpectedLedgerEntryCount -SecretScanCount $SecretScanCount `
        -ReceiptValidatorAvailable $ReceiptValidatorAvailable -MilestoneType DevelopmentRetest
    if (-not $disposition.CanIssueCleanReady) { throw ('CLEAN_READY is forbidden; snapshot restore is required: {0}.' -f (@($disposition.ReasonCodes) -join ',')) }

    $started = [DateTimeOffset]::Parse($StartedAtUtc)
    $completed = [DateTimeOffset]::Parse($CompletedAtUtc)
    $beforeTime = [DateTimeOffset]::Parse($BaselineBefore.CapturedAtUtc)
    $afterTime = [DateTimeOffset]::Parse($BaselineAfter.CapturedAtUtc)
    if ($beforeTime -lt $started -or $afterTime -lt $beforeTime -or $afterTime -gt $completed) { throw 'Baseline capture order is invalid.' }
    foreach ($actionReceipt in @($ActionReceipts)) {
        if ($actionReceipt.ExecutionMode -cne $ExecutionMode) { throw 'Action receipt execution modes must match CLEAN_READY.' }
        if ([DateTimeOffset]::Parse($actionReceipt.StartedAtUtc) -lt $started -or
            [DateTimeOffset]::Parse($actionReceipt.CompletedAtUtc) -gt $completed) { throw 'Action receipt time is outside the reset interval.' }
    }

    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion                    = 1
        ContractVersion                  = 'cddsi-vm-clean-ready-receipt-v1'
        Lane                             = 'FastLane'
        EvidenceClass                    = 'DIAGNOSTIC_ONLY'
        State                            = 'CLEAN_READY'
        CycleId                          = $Plan.CycleId
        VmIdentity                       = $Policy.VmIdentity
        ImageSha256                      = $Policy.ImageSha256
        ResetPolicyDigest                = $Policy.ResetPolicyDigest
        AllowListDigest                  = $Policy.AllowListDigest
        ResetPlanBindingToken            = $Plan.PlanBindingToken
        BaselineBeforeDigest             = $BaselineBefore.BaselineDigest
        BaselineAfterDigest              = $BaselineAfter.BaselineDigest
        OwnershipReceiptBindingTokens    = @($Policy.AllowList | ForEach-Object { $_.OwnershipReceiptBindingToken })
        ActionReceiptBindingTokens       = @($ActionReceipts | Sort-Object Sequence | ForEach-Object { $_.ReceiptBindingToken })
        StartedAtUtc                     = $StartedAtUtc
        CompletedAtUtc                   = $CompletedAtUtc
        ExecutionMode                    = $ExecutionMode
        CleanupFailureCount              = $CleanupFailureCount
        UnknownMutationCount             = $UnknownMutationCount
        UnexpectedLedgerEntryCount       = $UnexpectedLedgerEntryCount
        SecretScanCount                  = $SecretScanCount
        FinalState                       = [pscustomobject][ordered]@{
            SchemaVersion     = $FinalState.SchemaVersion
            ContractVersion   = $FinalState.ContractVersion
            VmpState          = $FinalState.VmpState
            RebootState       = $FinalState.RebootState
            UninstallState    = $FinalState.UninstallState
            CompensationState = $FinalState.CompensationState
        }
        ControlIdentity                  = $ControlIdentity
        AuthenticationDigest             = $AuthenticationDigest
        SnapshotReceiptBindingToken      = $script:CddsiVmResetNotApplicable
    }
    return [pscustomobject][ordered]@{
        SchemaVersion                    = $withoutBinding.SchemaVersion
        ContractVersion                  = $withoutBinding.ContractVersion
        Lane                             = $withoutBinding.Lane
        EvidenceClass                    = $withoutBinding.EvidenceClass
        State                            = $withoutBinding.State
        CycleId                          = $withoutBinding.CycleId
        VmIdentity                       = $withoutBinding.VmIdentity
        ImageSha256                      = $withoutBinding.ImageSha256
        ResetPolicyDigest                = $withoutBinding.ResetPolicyDigest
        AllowListDigest                  = $withoutBinding.AllowListDigest
        ResetPlanBindingToken            = $withoutBinding.ResetPlanBindingToken
        BaselineBeforeDigest             = $withoutBinding.BaselineBeforeDigest
        BaselineAfterDigest              = $withoutBinding.BaselineAfterDigest
        OwnershipReceiptBindingTokens    = $withoutBinding.OwnershipReceiptBindingTokens
        ActionReceiptBindingTokens       = $withoutBinding.ActionReceiptBindingTokens
        StartedAtUtc                     = $withoutBinding.StartedAtUtc
        CompletedAtUtc                   = $withoutBinding.CompletedAtUtc
        ExecutionMode                    = $withoutBinding.ExecutionMode
        CleanupFailureCount              = $withoutBinding.CleanupFailureCount
        UnknownMutationCount             = $withoutBinding.UnknownMutationCount
        UnexpectedLedgerEntryCount       = $withoutBinding.UnexpectedLedgerEntryCount
        SecretScanCount                  = $withoutBinding.SecretScanCount
        FinalState                       = $withoutBinding.FinalState
        ControlIdentity                  = $withoutBinding.ControlIdentity
        AuthenticationDigest             = $withoutBinding.AuthenticationDigest
        SnapshotReceiptBindingToken      = $withoutBinding.SnapshotReceiptBindingToken
        ReceiptBindingToken              = Get-CddsiVmResetBindingToken -Value $withoutBinding
    }
}

function Test-CddsiVmCleanReadyReceipt {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Receipt,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ActionReceipts,
        [Parameter(Mandatory = $true)]$BaselineBefore,
        [Parameter(Mandatory = $true)]$BaselineAfter,
        [Parameter(Mandatory = $true)]$FinalState
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Receipt -Expected @(
        'SchemaVersion', 'ContractVersion', 'Lane', 'EvidenceClass', 'State', 'CycleId',
        'VmIdentity', 'ImageSha256', 'ResetPolicyDigest', 'AllowListDigest',
        'ResetPlanBindingToken', 'BaselineBeforeDigest', 'BaselineAfterDigest',
        'OwnershipReceiptBindingTokens', 'ActionReceiptBindingTokens', 'StartedAtUtc',
        'CompletedAtUtc', 'ExecutionMode', 'CleanupFailureCount', 'UnknownMutationCount',
        'UnexpectedLedgerEntryCount', 'SecretScanCount', 'FinalState', 'ControlIdentity',
        'AuthenticationDigest', 'SnapshotReceiptBindingToken', 'ReceiptBindingToken'
    ))) { return $false }
    if (-not (Test-CddsiVmCalibrationSha256Value -Value $Receipt.ReceiptBindingToken)) { return $false }
    try {
        $expected = New-CddsiVmCleanReadyReceipt -Policy $Policy -Plan $Plan `
            -OwnershipReceipts $OwnershipReceipts -ActionReceipts $ActionReceipts `
            -BaselineBefore $BaselineBefore -BaselineAfter $BaselineAfter -FinalState $FinalState `
            -StartedAtUtc $Receipt.StartedAtUtc -CompletedAtUtc $Receipt.CompletedAtUtc `
            -ControlIdentity $Receipt.ControlIdentity -AuthenticationDigest $Receipt.AuthenticationDigest `
            -ExecutionMode $Receipt.ExecutionMode -CleanupFailureCount $Receipt.CleanupFailureCount `
            -UnknownMutationCount $Receipt.UnknownMutationCount `
            -UnexpectedLedgerEntryCount $Receipt.UnexpectedLedgerEntryCount `
            -SecretScanCount $Receipt.SecretScanCount -ReceiptValidatorAvailable $true
    }
    catch { return $false }
    return (
        $Receipt.ReceiptBindingToken -ceq $expected.ReceiptBindingToken -and
        (Get-CddsiVmResetBindingToken -Value $Receipt) -ceq (Get-CddsiVmResetBindingToken -Value $expected)
    )
}

function Invoke-CddsiVmGuestReset {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][string]$CycleId,
        [Parameter(Mandatory = $true)][string]$StartedAtUtc,
        [Parameter(Mandatory = $true)][string]$CompletedAtUtc,
        [Parameter(Mandatory = $true)][string]$ControlIdentity,
        [Parameter(Mandatory = $true)][string]$AuthenticationDigest,

        [ValidateSet('DevelopmentRetest', 'FirstP10A', 'FreezeFactsP10A', 'FormalP11Pass', 'ReleaseMilestone', 'P12Final')]
        [string]$MilestoneType = 'DevelopmentRetest',

        [bool]$ReceiptValidatorAvailable = $true,

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [switch]$AcknowledgeRealChanges
    )

    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    if ($Mode -ceq 'Live') {
        Assert-CddsiMutationAllowed -ExecutionContext $Context -Operation 'VmDeterministicGuestReset' -Mode $Mode -AcknowledgeRealChanges:$AcknowledgeRealChanges
        throw 'Scaffold Live VM reset remains fail closed.'
    }
    if (-not (Test-CddsiUtcTimestampValue -Value $StartedAtUtc) -or -not (Test-CddsiUtcTimestampValue -Value $CompletedAtUtc) -or
        [DateTimeOffset]::Parse($CompletedAtUtc) -lt [DateTimeOffset]::Parse($StartedAtUtc)) { throw 'VM reset interval is invalid.' }
    if (-not (Test-CddsiSafeIdentifierValue -Value $ControlIdentity -MaxLength 128) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $AuthenticationDigest)) { throw 'VM reset control authentication metadata is invalid.' }

    $plan = New-CddsiVmResetPlan -Policy $Policy -OwnershipReceipts $OwnershipReceipts -CycleId $CycleId
    $plannedChanges = @($plan.Actions | ForEach-Object { '{0}:{1}:{2}' -f $_.Provider, $_.Operation, $_.ResourceToken })
    if ($MilestoneType -cne 'DevelopmentRetest') {
        return New-CddsiOperationResult -Operation 'VmDeterministicGuestReset' -Status 'ACTION_REQUIRED' -Mode $Mode `
            -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' -MessageSafe 'The requested milestone requires an external snapshot restore.' `
            -PlannedChanges $plannedChanges -Data ([pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-runner-result-v1'; EvidenceClass = 'DIAGNOSTIC_ONLY'
                Disposition = 'BLOCKED'; RequiredResetMode = 'SnapshotRestore'; SnapshotRestoreRequired = $true; ResetPlan = $plan
                BaselineBefore = $null; BaselineAfter = $null; ActionReceipts = @(); FinalState = $null
                CleanReadyReceipt = $null; RealMutationPerformed = $false
            })
    }

    $beforeObservations = @()
    foreach ($specification in $script:CddsiVmResetBaselineSpecifications) {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider $specification.Provider `
            -Operation 'Inspect' -ResourceToken $specification.ResourceToken -Arguments ([ordered]@{
                Purpose = 'VmResetBaseline'; Phase = 'Before'; ResetPolicyDigest = $Policy.ResetPolicyDigest
            })
        if (-not (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'StateDigest')) -or
            -not (Test-CddsiSchemaVersionOne -Value $observation.SchemaVersion) -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $observation.StateDigest)) { throw 'Fake baseline provider returned invalid evidence.' }
        $beforeObservations += [pscustomobject][ordered]@{
            Sequence = $specification.Sequence; Domain = $specification.Domain; Provider = $specification.Provider
            ResourceToken = $specification.ResourceToken; StateDigest = $observation.StateDigest
        }
    }
    $baselineBefore = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-baseline-v1'; VmIdentity = $Policy.VmIdentity
        ImageSha256 = $Policy.ImageSha256; CapturedAtUtc = $StartedAtUtc; Observations = @($beforeObservations)
        BaselineDigest = ''
    }
    $baselineBefore.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $baselineBefore

    $actionReceipts = @()
    foreach ($action in @($plan.Actions)) {
        $actionReceipt = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider $action.Provider `
            -Operation 'Inspect' -ResourceToken $action.ResourceToken -Arguments ([ordered]@{
                Purpose = 'VmResetSyntheticAction'; PlanBindingToken = $plan.PlanBindingToken
                Sequence = [int]$action.Sequence; TargetOperation = $action.Operation
                OwnershipReceiptBindingToken = $action.OwnershipReceiptBindingToken
            })
        if ($null -ne $actionReceipt) { $actionReceipts += ,$actionReceipt }
    }

    $afterObservations = @()
    foreach ($specification in $script:CddsiVmResetBaselineSpecifications) {
        $observation = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider $specification.Provider `
            -Operation 'Inspect' -ResourceToken $specification.ResourceToken -Arguments ([ordered]@{
                Purpose = 'VmResetBaseline'; Phase = 'After'; ResetPolicyDigest = $Policy.ResetPolicyDigest
            })
        if (-not (Test-CddsiExactPropertySet -InputObject $observation -Expected @('SchemaVersion', 'StateDigest')) -or
            -not (Test-CddsiSchemaVersionOne -Value $observation.SchemaVersion) -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $observation.StateDigest)) { throw 'Fake baseline provider returned invalid evidence.' }
        $afterObservations += [pscustomobject][ordered]@{
            Sequence = $specification.Sequence; Domain = $specification.Domain; Provider = $specification.Provider
            ResourceToken = $specification.ResourceToken; StateDigest = $observation.StateDigest
        }
    }
    $baselineAfter = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-baseline-v1'; VmIdentity = $Policy.VmIdentity
        ImageSha256 = $Policy.ImageSha256; CapturedAtUtc = $CompletedAtUtc; Observations = @($afterObservations)
        BaselineDigest = ''
    }
    $baselineAfter.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $baselineAfter

    $finalStateResult = Invoke-CddsiProviderOperation -ExecutionContext $Context -Provider 'Environment' `
        -Operation 'Inspect' -ResourceToken '<VM_RESET_STATE:FINAL>' -Arguments ([ordered]@{
            Purpose = 'VmResetFinalState'; PlanBindingToken = $plan.PlanBindingToken
        })
    $finalState = $null
    $cleanupFailureCount = 0
    $unknownMutationCount = 0
    $unexpectedLedgerEntryCount = 0
    $secretScanCount = 0
    if (Test-CddsiExactPropertySet -InputObject $finalStateResult -Expected @(
        'SchemaVersion', 'ContractVersion', 'VmpState', 'RebootState', 'UninstallState',
        'CompensationState', 'CleanupFailureCount', 'UnknownMutationCount',
        'UnexpectedLedgerEntryCount', 'SecretScanCount'
    )) {
        $finalState = [pscustomobject][ordered]@{
            SchemaVersion = $finalStateResult.SchemaVersion; ContractVersion = $finalStateResult.ContractVersion
            VmpState = $finalStateResult.VmpState; RebootState = $finalStateResult.RebootState
            UninstallState = $finalStateResult.UninstallState; CompensationState = $finalStateResult.CompensationState
        }
        foreach ($name in @('CleanupFailureCount', 'UnknownMutationCount', 'UnexpectedLedgerEntryCount', 'SecretScanCount')) {
            $value = $finalStateResult.$name
            if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -lt 0 -or [long]$value -gt 2147483647) {
                $finalState = $null
                break
            }
        }
        if ($null -ne $finalState) {
            $cleanupFailureCount = [int]$finalStateResult.CleanupFailureCount
            $unknownMutationCount = [int]$finalStateResult.UnknownMutationCount
            $unexpectedLedgerEntryCount = [int]$finalStateResult.UnexpectedLedgerEntryCount
            $secretScanCount = [int]$finalStateResult.SecretScanCount
        }
    }

    $disposition = Resolve-CddsiVmResetDisposition -Policy $Policy -Plan $plan `
        -OwnershipReceipts $OwnershipReceipts -ActionReceipts $actionReceipts `
        -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -FinalState $finalState `
        -CleanupFailureCount $cleanupFailureCount -UnknownMutationCount $unknownMutationCount `
        -UnexpectedLedgerEntryCount $unexpectedLedgerEntryCount -SecretScanCount $secretScanCount `
        -ReceiptValidatorAvailable $ReceiptValidatorAvailable -MilestoneType $MilestoneType

    $cleanReceipt = $null
    if ($disposition.CanIssueCleanReady) {
        $cleanReceipt = New-CddsiVmCleanReadyReceipt -Policy $Policy -Plan $plan `
            -OwnershipReceipts $OwnershipReceipts -ActionReceipts $actionReceipts `
            -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -FinalState $finalState `
            -StartedAtUtc $StartedAtUtc -CompletedAtUtc $CompletedAtUtc `
            -ControlIdentity $ControlIdentity -AuthenticationDigest $AuthenticationDigest -ExecutionMode $Mode `
            -CleanupFailureCount $cleanupFailureCount -UnknownMutationCount $unknownMutationCount `
            -UnexpectedLedgerEntryCount $unexpectedLedgerEntryCount -SecretScanCount $secretScanCount `
            -ReceiptValidatorAvailable $ReceiptValidatorAvailable
    }

    $data = [pscustomobject][ordered]@{
        SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-runner-result-v1'; EvidenceClass = 'DIAGNOSTIC_ONLY'
        Disposition = $disposition.Disposition; RequiredResetMode = $disposition.RequiredResetMode
        SnapshotRestoreRequired = $disposition.SnapshotRestoreRequired
        ResetPlan = $plan; BaselineBefore = $baselineBefore; BaselineAfter = $baselineAfter
        ActionReceipts = @($actionReceipts); FinalState = $finalState; CleanReadyReceipt = $cleanReceipt
        RealMutationPerformed = $false
    }
    if (-not $disposition.CanIssueCleanReady) {
        return New-CddsiOperationResult -Operation 'VmDeterministicGuestReset' -Status 'ACTION_REQUIRED' -Mode $Mode `
            -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' -MessageSafe 'Guest reset could not prove a clean baseline; external snapshot restore is required.' `
            -PlannedChanges $plannedChanges -Warnings @($disposition.ReasonCodes) -Data $data
    }

    return New-CddsiOperationResult -Operation 'VmDeterministicGuestReset' -Status 'SUCCEEDED' -Mode $Mode `
        -MessageSafe 'Synthetic Fast Lane guest-reset rehearsal produced a diagnostic-only CLEAN_READY receipt.' `
        -PlannedChanges $plannedChanges -Data $data
}
