# VM-only deterministic reset adapter boundary.
#
# This development-only operator entry point is not loaded by product bootstrap
# and performs no system access at load time. TestSafe and DryRun are plan-only.
# Live dispatch is possible only through an injected provider adapter after the
# frozen reset policy, ownership receipts, plan, resource bindings, VM tier,
# explicit acknowledgement, and receipt validator gates all succeed.

$script:CddsiVmResetLiveNotApplicable = 'NOT_APPLICABLE'
$script:CddsiVmResetLiveResourceTypes = @(
    'Package',
    'HkcuValue',
    'Credential',
    'Checkpoint',
    'OwnerMarkedDirectory'
)
$script:CddsiVmResetLiveProviderIds = [ordered]@{
    FakeVmReset = 'cddsi-vm-reset-provider-fake-v1'
    VmResetLive = 'cddsi-vm-reset-provider-windows-v2'
}
$script:CddsiVmResetLiveProviderFileNames = [ordered]@{
    FakeVmReset = 'cddsi-vm-reset-provider-fake.ps1'
    VmResetLive = 'windows-vm-reset.ps1'
}

function Test-CddsiVmResetLiveCanonicalLocalPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [AllowNull()]
        $Path
    )

    if ($Path -isnot [string] -or [string]::IsNullOrWhiteSpace($Path) -or
        $Path.Length -gt 512 -or $Path -notmatch '^[A-Za-z]:\\' -or
        $Path -match '[\x00-\x1f\*\?\[\]]' -or
        $Path.Substring(2) -match ':' -or
        $Path -match '(^|\\)\.\.?(\\|$)' -or $Path -match '^\\\\') {
        return $false
    }

    foreach ($segment in @($Path.Substring(3).Split([IO.Path]::DirectorySeparatorChar))) {
        if ([string]::IsNullOrWhiteSpace($segment) -or $segment -match '[\. ]$' -or
            $segment -match '^(?i:CON|PRN|AUX|NUL|COM[1-9]|LPT[1-9])(?:\..*)?$') {
            return $false
        }
    }

    try {
        $fullPath = [IO.Path]::GetFullPath($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
        $candidate = $Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
        return [string]::Equals($fullPath, $candidate, [StringComparison]::OrdinalIgnoreCase)
    }
    catch {
        return $false
    }
}

function Test-CddsiVmResetLiveOwnedRootPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Path,
        [Parameter(Mandatory = $true)][AllowNull()]$OwnerRunId
    )

    if (-not (Test-CddsiCanonicalUuidValue -Value $OwnerRunId) -or
        -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Path)) {
        return $false
    }
    $pathRoot = [IO.Path]::GetPathRoot($Path).TrimEnd([IO.Path]::DirectorySeparatorChar)
    $candidate = $Path.TrimEnd([IO.Path]::DirectorySeparatorChar)
    if ([string]::Equals($pathRoot, $candidate, [StringComparison]::OrdinalIgnoreCase)) {
        return $false
    }
    $expectedLeaf = 'cddsi-vm-test-' + $OwnerRunId.ToLowerInvariant()
    return [string]::Equals([IO.Path]::GetFileName($candidate), $expectedLeaf, [StringComparison]::Ordinal)
}

function Test-CddsiVmResetLiveChildPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$Root
    )

    if (-not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Path) -or
        -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Root)) {
        return $false
    }
    $rootPrefix = $Root.TrimEnd([IO.Path]::DirectorySeparatorChar) + [IO.Path]::DirectorySeparatorChar
    return $Path.StartsWith($rootPrefix, [StringComparison]::OrdinalIgnoreCase)
}

function Test-CddsiVmResetLiveTargetDescriptor {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Descriptor,
        [Parameter(Mandatory = $true)][string]$ResourceType,
        [Parameter(Mandatory = $true)][string]$OwnerRunId
    )

    if ($script:CddsiVmResetLiveResourceTypes -cnotcontains $ResourceType) { return $false }

    switch -CaseSensitive ($ResourceType) {
        'Package' {
            if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected @('PackageFullName'))) { return $false }
            return ($Descriptor.PackageFullName -is [string] -and
                $Descriptor.PackageFullName -match '^[A-Za-z0-9][A-Za-z0-9._-]{0,255}$')
        }
        'HkcuValue' {
            if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected @(
                'Hive', 'KeyPath', 'ValueName', 'RegistryView'
            ))) { return $false }
            if ($Descriptor.Hive -cne 'HKCU' -or $Descriptor.RegistryView -cne 'Default') { return $false }
            if ($Descriptor.KeyPath -isnot [string] -or $Descriptor.KeyPath.Length -gt 256 -or
                $Descriptor.KeyPath -cnotmatch '^SOFTWARE\\Policies\\Claude(?:\\[A-Za-z0-9_-]+)*$' -or
                $Descriptor.KeyPath -match '[\*\?\[\]]') { return $false }
            return ($Descriptor.ValueName -is [string] -and $Descriptor.ValueName.Length -ge 1 -and
                $Descriptor.ValueName.Length -le 128 -and $Descriptor.ValueName -notmatch '[\x00-\x1f\*\?\[\]\\]')
        }
        'Credential' {
            if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected @('TargetName', 'CredentialType'))) { return $false }
            return ($Descriptor.CredentialType -ceq 'Generic' -and $Descriptor.TargetName -is [string] -and
                $Descriptor.TargetName -match '^cddsi-vm-test:[A-Za-z0-9][A-Za-z0-9._:-]{0,127}$')
        }
        'Checkpoint' {
            if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected @(
                'Path', 'OwnedRootPath', 'OwnerMarkerPath', 'OwnerMarkerSha256',
                'ExpectedFileSha256', 'PreexistingPathBindingToken',
                'AncestorBindingToken', 'ExistedBeforeOwnerRun'
            ))) { return $false }
            if (-not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Descriptor.Path) -or
                -not (Test-CddsiVmResetLiveOwnedRootPath -Path $Descriptor.OwnedRootPath -OwnerRunId $OwnerRunId) -or
                -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Descriptor.OwnerMarkerPath) -or
                -not (Test-CddsiVmResetLiveChildPath -Path $Descriptor.Path -Root $Descriptor.OwnedRootPath) -or
                $Descriptor.ExistedBeforeOwnerRun -isnot [bool] -or $Descriptor.ExistedBeforeOwnerRun) { return $false }
            $expectedMarkerPath = [IO.Path]::Combine($Descriptor.OwnedRootPath, '.cddsi-owner.json')
            if (-not [string]::Equals($Descriptor.OwnerMarkerPath, $expectedMarkerPath, [StringComparison]::OrdinalIgnoreCase)) { return $false }
            foreach ($name in @('OwnerMarkerSha256', 'ExpectedFileSha256', 'PreexistingPathBindingToken', 'AncestorBindingToken')) {
                if (-not (Test-CddsiVmCalibrationSha256Value -Value $Descriptor.$name)) { return $false }
            }
            return $true
        }
        'OwnerMarkedDirectory' {
            if (-not (Test-CddsiExactPropertySet -InputObject $Descriptor -Expected @(
                'Path', 'OwnerMarkerPath', 'OwnerMarkerSha256',
                'PreexistingPathBindingToken', 'AncestorBindingToken',
                'ExistedBeforeOwnerRun'
            ))) { return $false }
            if (-not (Test-CddsiVmResetLiveOwnedRootPath -Path $Descriptor.Path -OwnerRunId $OwnerRunId) -or
                -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Descriptor.OwnerMarkerPath) -or
                $Descriptor.ExistedBeforeOwnerRun -isnot [bool] -or $Descriptor.ExistedBeforeOwnerRun) { return $false }
            $expectedMarkerPath = [IO.Path]::Combine($Descriptor.Path, '.cddsi-owner.json')
            if (-not [string]::Equals($Descriptor.OwnerMarkerPath, $expectedMarkerPath, [StringComparison]::OrdinalIgnoreCase)) { return $false }
            foreach ($name in @('OwnerMarkerSha256', 'PreexistingPathBindingToken', 'AncestorBindingToken')) {
                if (-not (Test-CddsiVmCalibrationSha256Value -Value $Descriptor.$name)) { return $false }
            }
            return $true
        }
        default { return $false }
    }
}

function Test-CddsiVmResetLiveResourceBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Binding,
        [Parameter(Mandatory = $true)][AllowNull()]$AllowListEntry
    )

    if (-not (Test-CddsiVmResetAllowListEntry -Entry $AllowListEntry) -or
        -not (Test-CddsiExactPropertySet -InputObject $Binding -Expected @(
            'SchemaVersion', 'ContractVersion', 'ResourceId', 'ResourceToken',
            'ResourceType', 'Provider', 'Operation', 'OwnerRunId',
            'TargetDescriptor', 'TargetBindingToken'
        ))) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Binding.SchemaVersion) -or
        $Binding.ContractVersion -cne 'cddsi-vm-reset-resource-binding-v1' -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Binding.TargetBindingToken) -or
        -not (Test-CddsiVmResetLiveTargetDescriptor -Descriptor $Binding.TargetDescriptor `
            -ResourceType $Binding.ResourceType -OwnerRunId $Binding.OwnerRunId)) {
        return $false
    }
    foreach ($name in @('ResourceId', 'ResourceToken', 'ResourceType', 'Provider', 'Operation', 'OwnerRunId')) {
        if ($Binding.$name -isnot [string] -or $Binding.$name -cne $AllowListEntry.$name) { return $false }
    }
    $expectedTargetBinding = Get-CddsiVmResetBindingToken -Value $Binding.TargetDescriptor
    if ($Binding.TargetBindingToken -cne $expectedTargetBinding -or
        $Binding.TargetBindingToken -cne $AllowListEntry.ResourceIdentitySha256) { return $false }

    if ($Binding.ResourceType -ceq 'OwnerMarkedDirectory') {
        if ($Binding.TargetDescriptor.OwnerMarkerSha256 -cne $AllowListEntry.MarkerSha256 -or
            $Binding.TargetDescriptor.PreexistingPathBindingToken -cne $AllowListEntry.PreexistingPathBindingToken) {
            return $false
        }
    }
    return $true
}

function Test-CddsiVmResetLiveContext {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Context,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$ProviderAdapter
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Context -Expected @(
        'SchemaVersion', 'ContractVersion', 'RunId', 'Mode', 'EnvironmentTier',
        'PrincipalRole', 'IsCi', 'VmIdentity', 'ImageSha256',
        'ResetPolicyDigest', 'PlanBindingToken', 'ControlIdentity',
        'AuthenticationDigest', 'ProviderAdapterFileSha256',
        'DeviceAttestationPublicKeySha256'
    ))) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Context.SchemaVersion) -or
        $Context.ContractVersion -cne 'cddsi-vm-reset-live-context-v1' -or
        -not (Test-CddsiCanonicalUuidValue -Value $Context.RunId) -or
        $Context.Mode -cne $Mode -or @('TestSafe', 'DryRun', 'Live') -cnotcontains $Context.Mode -or
        @('HostSandbox', 'CI', 'VmAcceptance') -cnotcontains $Context.EnvironmentTier -or
        $Context.PrincipalRole -cne 'VmTester' -or $Context.IsCi -isnot [bool] -or
        $Context.VmIdentity -cne $Policy.VmIdentity -or $Context.ImageSha256 -cne $Policy.ImageSha256 -or
        $Context.ResetPolicyDigest -cne $Policy.ResetPolicyDigest -or
        $Context.PlanBindingToken -cne $Plan.PlanBindingToken -or
        -not (Test-CddsiSafeIdentifierValue -Value $Context.ControlIdentity -MaxLength 128) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Context.AuthenticationDigest) -or
        $Context.ProviderAdapterFileSha256 -cne $ProviderAdapter.AdapterFileSha256 -or
        $Context.DeviceAttestationPublicKeySha256 -cne $ProviderAdapter.DeviceAttestationPublicKeySha256) {
        return $false
    }
    if ($ProviderAdapter.Kind -ceq 'VmResetLive' -and (
        $null -eq $ProviderAdapter.AuthorizationEnvelope -or
        $ProviderAdapter.AuthorizationEnvelope.ResetPolicyDigest -cne $Context.ResetPolicyDigest -or
        $ProviderAdapter.AuthorizationEnvelope.PlanBindingToken -cne $Context.PlanBindingToken -or
        $ProviderAdapter.AuthorizationEnvelope.ControlAuthenticationDigest -cne $Context.AuthenticationDigest
    )) { return $false }
    return $true
}

function Test-CddsiVmResetProviderAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$ProviderAdapter
    )

    if ($null -eq $ProviderAdapter -or $ProviderAdapter.Kind -isnot [string] -or
        @('FakeVmReset', 'VmResetLive') -cnotcontains $ProviderAdapter.Kind) { return $false }
    if ($ProviderAdapter.Kind -ceq 'FakeVmReset') {
        if (-not (Test-CddsiExactPropertySet -InputObject $ProviderAdapter -Expected @(
            'SchemaVersion', 'ContractVersion', 'Kind', 'IsLive', 'AdapterId',
            'AdapterFilePath', 'AdapterFileSha256', 'DeviceAttestationPublicKeySha256',
            'Invoke'
        )) -or $ProviderAdapter.ContractVersion -cne 'cddsi-vm-reset-provider-adapter-v1' -or
            $ProviderAdapter.Invoke -isnot [scriptblock]) { return $false }
    }
    else {
        if (-not (Test-CddsiExactPropertySet -InputObject $ProviderAdapter -Expected @(
            'SchemaVersion', 'ContractVersion', 'Kind', 'IsLive', 'AdapterId',
            'AdapterFilePath', 'AdapterFileSha256', 'DeviceAttestationPublicKeySha256',
            'AuthorizationEnvelope', 'Invoke'
        )) -or $ProviderAdapter.ContractVersion -cne 'cddsi-vm-reset-provider-adapter-v2' -or
            $null -ne $ProviderAdapter.Invoke -or $null -eq $ProviderAdapter.AuthorizationEnvelope) {
            return $false
        }
    }
    if (-not (Test-CddsiSchemaVersionOne -Value $ProviderAdapter.SchemaVersion) -or
        $ProviderAdapter.IsLive -isnot [bool] -or
        -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $ProviderAdapter.AdapterFilePath) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $ProviderAdapter.AdapterFileSha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $ProviderAdapter.DeviceAttestationPublicKeySha256)) {
        return $false
    }
    $expectedIsLive = ($ProviderAdapter.Kind -ceq 'VmResetLive')
    $expectedId = $script:CddsiVmResetLiveProviderIds[$ProviderAdapter.Kind]
    $expectedFileName = $script:CddsiVmResetLiveProviderFileNames[$ProviderAdapter.Kind]
    return (
        $ProviderAdapter.IsLive -eq $expectedIsLive -and
        $ProviderAdapter.AdapterId -is [string] -and $ProviderAdapter.AdapterId -ceq $expectedId -and
        [IO.Path]::GetFileName($ProviderAdapter.AdapterFilePath) -ceq $expectedFileName
    )
}

function Get-CddsiVmResetEvidencePayload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Evidence,
        [Parameter(Mandatory = $true)][string[]]$PropertyNames
    )

    $payload = [pscustomobject][ordered]@{}
    foreach ($name in $PropertyNames) {
        Add-Member -InputObject $payload -NotePropertyName $name -NotePropertyValue $Evidence.$name
    }
    return $payload
}

function Test-CddsiVmResetEnvironmentAttestation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Attestation,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Policy,
        [AllowNull()]$ProviderAdapter
    )

    $v1Fields = @(
        'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'VmIdentity',
        'ImageSha256', 'PrincipalRole', 'IsCi', 'HostSystem', 'ProviderKind',
        'AttestedAtUtc'
    )
    if ($null -ne $Attestation -and $Attestation.ContractVersion -ceq
        'cddsi-vm-reset-environment-attestation-v1') {
        $fields = $v1Fields
        if (-not (Test-CddsiExactPropertySet -InputObject $Attestation -Expected @($fields + 'EvidenceDigest'))) { return $false }
    }
    else {
        $fields = @(
            'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'VmIdentity',
            'ImageSha256', 'PrincipalRole', 'IsCi', 'HostSystem', 'ProviderKind',
            'DisposableVmIdentitySha256', 'DeviceAttestationPublicKeySha256',
            'AttestedAtUtc', 'ProviderRequestBindingToken'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Attestation -Expected @(
            $fields + 'AttestationPayloadSha256' + 'DeviceSignatureAlgorithm' +
            'DeviceSignatureBase64' + 'EvidenceDigest'
        ))) { return $false }
    }
    if (-not (Test-CddsiSchemaVersionOne -Value $Attestation.SchemaVersion) -or
        @('cddsi-vm-reset-environment-attestation-v1', 'cddsi-vm-reset-environment-attestation-v2') -cnotcontains $Attestation.ContractVersion -or
        $Attestation.EnvironmentTier -cne 'VmAcceptance' -or
        $Attestation.EnvironmentTier -cne $Context.EnvironmentTier -or
        $Attestation.VmIdentity -cne $Policy.VmIdentity -or
        $Attestation.ImageSha256 -cne $Policy.ImageSha256 -or
        $Attestation.PrincipalRole -cne 'VmTester' -or $Attestation.IsCi -isnot [bool] -or $Attestation.IsCi -or
        $Attestation.HostSystem -cne 'Windows' -or $Attestation.ProviderKind -cne 'VmResetLive' -or
        -not (Test-CddsiUtcTimestampValue -Value $Attestation.AttestedAtUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Attestation.EvidenceDigest)) { return $false }
    $payload = Get-CddsiVmResetEvidencePayload -Evidence $Attestation -PropertyNames $fields
    $digest = Get-CddsiVmResetBindingToken -Value $payload
    if ($Attestation.EvidenceDigest -cne $digest) { return $false }
    if ($Attestation.ContractVersion -ceq 'cddsi-vm-reset-environment-attestation-v1') { return $true }
    return (
        $null -ne $ProviderAdapter -and
        (Test-CddsiVmCalibrationSha256Value -Value $Attestation.DisposableVmIdentitySha256) -and
        $Attestation.DeviceAttestationPublicKeySha256 -ceq $ProviderAdapter.DeviceAttestationPublicKeySha256 -and
        $Attestation.AttestationPayloadSha256 -ceq $digest -and
        $Attestation.DeviceSignatureAlgorithm -ceq 'ECDSA_P256_SHA256' -and
        $null -ne (Get-Command -Name Test-CddsiWindowsVmResetAdapterDeviceSignature `
            -CommandType Function -ErrorAction SilentlyContinue) -and
        (Test-CddsiWindowsVmResetAdapterDeviceSignature -ProviderAdapter $ProviderAdapter `
            -DigestSha256 $digest -SignatureBase64 $Attestation.DeviceSignatureBase64)
    )
}

function Test-CddsiVmResetPreflightEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Evidence,
        [Parameter(Mandatory = $true)]$Binding,
        [Parameter(Mandatory = $true)]$AllowListEntry
    )

    $fields = @(
        'SchemaVersion', 'ContractVersion', 'ResourceId', 'ResourceToken',
        'ResourceType', 'Provider', 'Operation', 'OwnerRunId',
        'TargetBindingToken', 'ResourceIdentitySha256', 'Exists',
        'ExactTargetMatched', 'OwnershipMatched', 'MarkerSha256',
        'PreexistingPathBindingToken', 'AncestorBindingToken',
        'TargetIsReparsePoint', 'AncestorReparsePointCount',
        'ExistedBeforeOwnerRun'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @($fields + 'EvidenceDigest')) -or
        -not (Test-CddsiVmResetLiveResourceBinding -Binding $Binding -AllowListEntry $AllowListEntry)) { return $false }
    if (-not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-vm-reset-preflight-evidence-v1' -or
        $Evidence.Exists -isnot [bool] -or $Evidence.ExactTargetMatched -isnot [bool] -or
        -not $Evidence.ExactTargetMatched -or $Evidence.OwnershipMatched -isnot [bool] -or
        -not $Evidence.OwnershipMatched -or $Evidence.TargetIsReparsePoint -isnot [bool] -or
        $Evidence.TargetIsReparsePoint -or
        ($Evidence.AncestorReparsePointCount -isnot [int] -and $Evidence.AncestorReparsePointCount -isnot [long]) -or
        [long]$Evidence.AncestorReparsePointCount -ne 0 -or
        $Evidence.ExistedBeforeOwnerRun -isnot [bool] -or $Evidence.ExistedBeforeOwnerRun -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.EvidenceDigest)) { return $false }
    foreach ($name in @('ResourceId', 'ResourceToken', 'ResourceType', 'Provider', 'Operation', 'OwnerRunId')) {
        if ($Evidence.$name -isnot [string] -or $Evidence.$name -cne $AllowListEntry.$name) { return $false }
    }
    if ($Evidence.TargetBindingToken -cne $Binding.TargetBindingToken -or
        $Evidence.ResourceIdentitySha256 -cne $AllowListEntry.ResourceIdentitySha256) { return $false }

    if (@('Checkpoint', 'OwnerMarkedDirectory') -ccontains $Binding.ResourceType) {
        $descriptor = $Binding.TargetDescriptor
        if ($Evidence.MarkerSha256 -cne $descriptor.OwnerMarkerSha256 -or
            $Evidence.PreexistingPathBindingToken -cne $descriptor.PreexistingPathBindingToken -or
            $Evidence.AncestorBindingToken -cne $descriptor.AncestorBindingToken) { return $false }
    }
    else {
        foreach ($name in @('MarkerSha256', 'PreexistingPathBindingToken', 'AncestorBindingToken')) {
            if ($Evidence.$name -cne $script:CddsiVmResetLiveNotApplicable) { return $false }
        }
    }
    $payload = Get-CddsiVmResetEvidencePayload -Evidence $Evidence -PropertyNames $fields
    return ($Evidence.EvidenceDigest -ceq (Get-CddsiVmResetBindingToken -Value $payload))
}

function Test-CddsiVmResetFinalStateEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Evidence
    )

    $fields = @(
        'SchemaVersion', 'ContractVersion', 'VmpState', 'RebootState',
        'UninstallState', 'CompensationState', 'CleanupFailureCount',
        'UnknownMutationCount', 'UnexpectedLedgerEntryCount', 'SecretScanCount'
    )
    if (-not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @($fields + 'EvidenceDigest')) -or
        -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-vm-reset-final-state-v1' -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.EvidenceDigest)) { return $false }
    foreach ($name in @('VmpState', 'RebootState', 'UninstallState', 'CompensationState')) {
        if (@('KNOWN', 'UNKNOWN') -cnotcontains $Evidence.$name) { return $false }
    }
    foreach ($name in @('CleanupFailureCount', 'UnknownMutationCount', 'UnexpectedLedgerEntryCount', 'SecretScanCount')) {
        $value = $Evidence.$name
        if (($value -isnot [int] -and $value -isnot [long]) -or [long]$value -lt 0 -or [long]$value -gt 2147483647) {
            return $false
        }
    }
    $payload = Get-CddsiVmResetEvidencePayload -Evidence $Evidence -PropertyNames $fields
    return ($Evidence.EvidenceDigest -ceq (Get-CddsiVmResetBindingToken -Value $payload))
}

function Test-CddsiVmResetProviderActionResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Result,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)]$ExpectedAction,
        [Parameter(Mandatory = $true)][string]$ExpectedRequestBindingToken,
        [Parameter(Mandatory = $true)]$Binding,
        [Parameter(Mandatory = $true)]$PreflightEvidence,
        [AllowNull()]$ProviderAdapter
    )

    if ($null -eq $Result -or -not (Test-CddsiSchemaVersionOne -Value $Result.SchemaVersion) -or
        $Result.ProviderRequestBindingToken -cne $ExpectedRequestBindingToken -or
        $Result.TargetBindingToken -cne $Binding.TargetBindingToken -or
        $Result.InitialPreflightEvidenceDigest -cne $PreflightEvidence.EvidenceDigest -or
        $Result.AtomicPreconditionValidated -isnot [bool] -or
        $Result.ExactTargetMatched -isnot [bool] -or
        $Result.OwnershipMatched -isnot [bool] -or
        $Result.TargetWasReparsePoint -isnot [bool] -or
        ($Result.AncestorReparsePointCount -isnot [int] -and $Result.AncestorReparsePointCount -isnot [long]) -or
        $Result.ExactTargetAbsentAfter -isnot [bool] -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Result.PostconditionEvidenceDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Result.ResultBindingToken) -or
        -not (Test-CddsiVmResetActionReceipt -Receipt $Result.ActionReceipt -Plan $Plan)) {
        return $false
    }
    $isV2 = ($Result.ContractVersion -ceq 'cddsi-vm-reset-provider-action-result-v2')
    $providerKindProperty = if ($null -eq $ProviderAdapter) {
        $null
    }
    else {
        $ProviderAdapter.PSObject.Properties['Kind']
    }
    $requiresSignedV2Result = (
        $null -ne $providerKindProperty -and
        $providerKindProperty.Value -is [string] -and
        $providerKindProperty.Value -ceq 'VmResetLive'
    )
    if ($requiresSignedV2Result -and -not $isV2) { return $false }
    if (-not $isV2 -and $Result.ContractVersion -cne 'cddsi-vm-reset-provider-action-result-v1') { return $false }
    if ($isV2) {
        $postconditionFields = @(
            'SchemaVersion', 'ContractVersion', 'ProviderRequestBindingToken',
            'TargetBindingToken', 'InitialPreflightEvidenceDigest',
            'ImmediatePreflightEvidenceDigest', 'AtomicPreconditionValidated',
            'ExactTargetMatched', 'OwnershipMatched', 'TargetWasReparsePoint',
            'AncestorReparsePointCount', 'ExactTargetAbsentAfter', 'Outcome',
            'Changed', 'FailureCode'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Result -Expected @(
            $postconditionFields + 'PostconditionEvidenceDigest' + 'ActionReceipt' +
            'SignedReceiptDigest' + 'ReceiptSignerPublicKeySha256' +
            'ReceiptSignatureAlgorithm' + 'ReceiptSignatureBase64' + 'ResultBindingToken'
        )) -or -not (Test-CddsiVmCalibrationSha256Value -Value $Result.ImmediatePreflightEvidenceDigest) -or
            @('COMPLETED', 'FAILED', 'AMBIGUOUS') -cnotcontains $Result.Outcome -or
            $Result.Changed -isnot [bool] -or $Result.FailureCode -isnot [string] -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $Result.SignedReceiptDigest) -or
            $Result.ReceiptSignerPublicKeySha256 -cne $ProviderAdapter.DeviceAttestationPublicKeySha256 -or
            $Result.ReceiptSignatureAlgorithm -cne 'ECDSA_P256_SHA256') { return $false }
        if ($Result.ActionReceipt.Outcome -cne $Result.Outcome -or
            $Result.ActionReceipt.Changed -ne $Result.Changed -or
            $Result.ActionReceipt.FailureCode -cne $Result.FailureCode) { return $false }
        if ($Result.Outcome -ceq 'COMPLETED') {
            if (-not $Result.AtomicPreconditionValidated -or -not $Result.ExactTargetMatched -or
                -not $Result.OwnershipMatched -or $Result.TargetWasReparsePoint -or
                [long]$Result.AncestorReparsePointCount -ne 0 -or -not $Result.ExactTargetAbsentAfter -or
                $Result.FailureCode -cne '') { return $false }
        }
        elseif ($Result.FailureCode -notmatch '^[A-Z0-9_]{1,64}$') { return $false }
    }
    else {
        $postconditionFields = @(
            'SchemaVersion', 'ContractVersion', 'ProviderRequestBindingToken',
            'TargetBindingToken', 'InitialPreflightEvidenceDigest',
            'AtomicPreconditionValidated', 'ExactTargetMatched', 'OwnershipMatched',
            'TargetWasReparsePoint', 'AncestorReparsePointCount', 'ExactTargetAbsentAfter'
        )
        if (-not (Test-CddsiExactPropertySet -InputObject $Result -Expected @(
            $postconditionFields + 'PostconditionEvidenceDigest' + 'ActionReceipt' + 'ResultBindingToken'
        )) -or -not $Result.AtomicPreconditionValidated -or -not $Result.ExactTargetMatched -or
            -not $Result.OwnershipMatched -or $Result.TargetWasReparsePoint -or
            [long]$Result.AncestorReparsePointCount -ne 0 -or -not $Result.ExactTargetAbsentAfter) {
            return $false
        }
    }
    foreach ($name in @(
        'Sequence', 'ResourceId', 'ResourceType', 'Provider', 'Operation',
        'ResourceToken', 'OwnershipReceiptBindingToken'
    )) {
        if ($Result.ActionReceipt.$name -is [string]) {
            if ($Result.ActionReceipt.$name -cne $ExpectedAction.$name) { return $false }
        }
        elseif ([long]$Result.ActionReceipt.$name -ne [long]$ExpectedAction.$name) {
            return $false
        }
    }
    $postconditionPayload = Get-CddsiVmResetEvidencePayload -Evidence $Result -PropertyNames $postconditionFields
    if ($Result.PostconditionEvidenceDigest -cne (Get-CddsiVmResetBindingToken -Value $postconditionPayload) -or
        $Result.ActionReceipt.ProviderEvidenceDigest -cne $Result.PostconditionEvidenceDigest) {
        return $false
    }
    if (-not $isV2) {
        $resultFields = @($postconditionFields + 'PostconditionEvidenceDigest' + 'ActionReceipt')
        $resultPayload = Get-CddsiVmResetEvidencePayload -Evidence $Result -PropertyNames $resultFields
        return ($Result.ResultBindingToken -ceq (Get-CddsiVmResetBindingToken -Value $resultPayload))
    }
    $resultPayload = [pscustomobject][ordered]@{
        Postcondition = $postconditionPayload
        PostconditionEvidenceDigest = $Result.PostconditionEvidenceDigest
        ActionReceipt = $Result.ActionReceipt
    }
    $expectedSignedDigest = Get-CddsiVmResetBindingToken -Value ([pscustomobject][ordered]@{
        ProviderRequestBindingToken = $Result.ProviderRequestBindingToken
        TargetBindingToken = $Result.TargetBindingToken
        InitialPreflightEvidenceDigest = $Result.InitialPreflightEvidenceDigest
        ImmediatePreflightEvidenceDigest = $Result.ImmediatePreflightEvidenceDigest
        PostconditionEvidenceDigest = $Result.PostconditionEvidenceDigest
        ReceiptBindingToken = $Result.ActionReceipt.ReceiptBindingToken
        Outcome = $Result.Outcome
        Changed = $Result.Changed
    })
    return (
        $Result.ResultBindingToken -ceq (Get-CddsiVmResetBindingToken -Value $resultPayload) -and
        $Result.SignedReceiptDigest -ceq $expectedSignedDigest -and
        $null -ne $ProviderAdapter -and
        $null -ne (Get-Command -Name Test-CddsiWindowsVmResetAdapterDeviceSignature `
            -CommandType Function -ErrorAction SilentlyContinue) -and
        (Test-CddsiWindowsVmResetAdapterDeviceSignature -ProviderAdapter $ProviderAdapter `
            -DigestSha256 $Result.SignedReceiptDigest -SignatureBase64 $Result.ReceiptSignatureBase64)
    )
}

function Invoke-CddsiVmResetInjectedProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ProviderAdapter,
        [Parameter(Mandatory = $true)][string]$Provider,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][string]$ResourceToken,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Arguments,
        [Parameter(Mandatory = $true)][ref]$CallCount
    )

    if (-not (Test-CddsiVmResetProviderAdapter -ProviderAdapter $ProviderAdapter)) {
        throw 'VM reset provider adapter is invalid.'
    }
    $withoutBinding = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-provider-request-v1'
        Provider = $Provider
        Operation = $Operation
        ResourceToken = $ResourceToken
        Arguments = $Arguments
    }
    $request = [pscustomobject][ordered]@{
        SchemaVersion = $withoutBinding.SchemaVersion
        ContractVersion = $withoutBinding.ContractVersion
        Provider = $withoutBinding.Provider
        Operation = $withoutBinding.Operation
        ResourceToken = $withoutBinding.ResourceToken
        Arguments = $withoutBinding.Arguments
        RequestBindingToken = Get-CddsiVmResetBindingToken -Value $withoutBinding
    }
    $CallCount.Value = [int]$CallCount.Value + 1
    if ($ProviderAdapter.Kind -ceq 'VmResetLive') {
        if ($null -eq (Get-Command -Name Invoke-CddsiWindowsVmResetAuthorizedRequest `
            -CommandType Function -ErrorAction SilentlyContinue)) {
            throw 'Fixed Windows VM reset provider is not loaded.'
        }
        $providerResult = Invoke-CddsiWindowsVmResetAuthorizedRequest `
            -ProviderAdapter $ProviderAdapter -Request $request
    }
    else {
        $providerResult = & $ProviderAdapter.Invoke $request
    }
    return [pscustomobject][ordered]@{
        RequestBindingToken = $request.RequestBindingToken
        Result = $providerResult
    }
}

function New-CddsiVmResetLiveAdapterData {
    [CmdletBinding()]
    param(
        [AllowNull()]$Plan,
        [string]$Disposition,
        [string]$RequiredResetMode,
        [bool]$SnapshotRestoreRequired,
        [AllowNull()]$EnvironmentAttestation,
        [AllowEmptyCollection()][object[]]$PreflightEvidence = @(),
        [AllowNull()]$BaselineBefore,
        [AllowNull()]$BaselineAfter,
        [AllowEmptyCollection()][object[]]$ActionReceipts = @(),
        [AllowNull()]$FinalState,
        [AllowNull()]$CleanReadyReceipt,
        [ValidateSet('NOT_STARTED', 'UNCHANGED', 'CHANGED', 'UNKNOWN')][string]$MutationState = 'NOT_STARTED',
        [ValidateRange(0, 2147483647)][int]$ProviderCallCount = 0,
        [string[]]$ReasonCodes = @()
    )

    $confirmedMutationPerformed = (@($ActionReceipts | Where-Object {
        $_.Changed -is [bool] -and $_.Changed
    }).Count -gt 0)
    $realMutationPerformed = if ($confirmedMutationPerformed -or $MutationState -ceq 'CHANGED') {
        $true
    }
    elseif ($MutationState -ceq 'UNKNOWN') {
        $null
    }
    else {
        $false
    }

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-live-adapter-result-v1'
        EvidenceClass = 'DIAGNOSTIC_ONLY'
        Disposition = $Disposition
        RequiredResetMode = $RequiredResetMode
        SnapshotRestoreRequired = $SnapshotRestoreRequired
        ResetPlan = $Plan
        EnvironmentAttestation = $EnvironmentAttestation
        PreflightEvidence = @($PreflightEvidence)
        BaselineBefore = $BaselineBefore
        BaselineAfter = $BaselineAfter
        ActionReceipts = @($ActionReceipts)
        FinalState = $FinalState
        CleanReadyReceipt = $CleanReadyReceipt
        MutationState = $MutationState
        RealMutationPerformed = $realMutationPerformed
        ProviderCallCount = $ProviderCallCount
        ReasonCodes = @($ReasonCodes)
    }
}

function New-CddsiVmResetLiveBlockedResult {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)][string]$ErrorCode,
        [Parameter(Mandatory = $true)][string[]]$ReasonCodes,
        [AllowNull()]$Plan,
        [bool]$SnapshotRestoreRequired,
        [AllowNull()]$EnvironmentAttestation,
        [AllowEmptyCollection()][object[]]$PreflightEvidence = @(),
        [AllowNull()]$BaselineBefore,
        [AllowNull()]$BaselineAfter,
        [AllowEmptyCollection()][object[]]$ActionReceipts = @(),
        [AllowNull()]$FinalState,
        [ValidateSet('NOT_STARTED', 'UNCHANGED', 'CHANGED', 'UNKNOWN')][string]$MutationState = 'NOT_STARTED',
        [ValidateRange(0, 2147483647)][int]$ProviderCallCount = 0,
        [string[]]$PlannedChanges = @()
    )

    $requiredResetMode = if ($SnapshotRestoreRequired) { 'SnapshotRestore' } else { 'GuestReset' }
    $data = New-CddsiVmResetLiveAdapterData -Plan $Plan -Disposition 'BLOCKED' `
        -RequiredResetMode $requiredResetMode -SnapshotRestoreRequired $SnapshotRestoreRequired `
        -EnvironmentAttestation $EnvironmentAttestation -PreflightEvidence $PreflightEvidence `
        -BaselineBefore $BaselineBefore -BaselineAfter $BaselineAfter -ActionReceipts $ActionReceipts `
        -FinalState $FinalState -CleanReadyReceipt $null -MutationState $MutationState `
        -ProviderCallCount $ProviderCallCount -ReasonCodes $ReasonCodes
    $confirmedChanged = (@($ActionReceipts | Where-Object {
        $_.Changed -is [bool] -and $_.Changed
    }).Count -gt 0) -or $MutationState -ceq 'CHANGED'
    return New-CddsiOperationResult -Operation 'VmDeterministicGuestResetLiveAdapter' `
        -Status 'ACTION_REQUIRED' -Mode $Mode -Changed:$confirmedChanged -ErrorCode $ErrorCode `
        -MessageSafe 'VM deterministic reset was blocked by a fixed safety gate.' `
        -PlannedChanges $PlannedChanges -Warnings $ReasonCodes -Data $data
}

function Invoke-CddsiVmResetLiveAdapter {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][Alias('ExecutionContext')]$Context,
        [Parameter(Mandatory = $true)]$ProviderAdapter,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][AllowEmptyCollection()][object[]]$ResourceBindings,

        [ValidateSet('DevelopmentRetest', 'FirstP10A', 'FreezeFactsP10A', 'FormalP11Pass', 'ReleaseMilestone', 'P12Final')]
        [string]$MilestoneType = 'DevelopmentRetest',

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [switch]$ReceiptValidatorAvailable,
        [switch]$AcknowledgeRealChanges
    )

    $requiredCommands = @(
        'Get-CddsiVmResetBindingToken', 'Test-CddsiVmResetPolicy',
        'Test-CddsiVmResetOwnershipReceipt', 'Test-CddsiVmResetPlan',
        'Test-CddsiVmResetBaseline', 'Test-CddsiVmResetActionReceipt',
        'Resolve-CddsiVmResetDisposition', 'New-CddsiVmCleanReadyReceipt',
        'New-CddsiOperationResult'
    )
    foreach ($commandName in $requiredCommands) {
        if ($null -eq (Get-Command -Name $commandName -CommandType Function -ErrorAction SilentlyContinue)) {
            throw ('Required VM reset contract is not loaded: {0}' -f $commandName)
        }
    }
    if (@('TestSafe', 'DryRun', 'Live') -cnotcontains $Mode) {
        throw 'VM reset execution mode casing is invalid.'
    }

    $plannedChanges = @()
    if (-not (Test-CddsiVmResetPolicy -Policy $Policy)) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'RESET_POLICY_INVALID' `
            -ReasonCodes @('RESET_POLICY_INVALID') -Plan $null -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null
    }

    $receiptArray = @($OwnershipReceipts)
    $entryArray = @($Policy.AllowList)
    if ($receiptArray.Count -ne $entryArray.Count) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'OWNERSHIP_RECEIPT_INVALID' `
            -ReasonCodes @('OWNERSHIP_RECEIPT_INVALID') -Plan $Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null
    }
    foreach ($entry in $entryArray) {
        $matches = @($receiptArray | Where-Object {
            $_.ReceiptBindingToken -is [string] -and
            $_.ReceiptBindingToken -ceq $entry.OwnershipReceiptBindingToken
        })
        if ($matches.Count -ne 1 -or -not (Test-CddsiVmResetOwnershipReceipt -Receipt $matches[0] -AllowListEntry $entry)) {
            return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'OWNERSHIP_RECEIPT_INVALID' `
                -ReasonCodes @('OWNERSHIP_RECEIPT_INVALID') -Plan $Plan -SnapshotRestoreRequired $true `
                -EnvironmentAttestation $null
        }
    }
    if (-not (Test-CddsiVmResetPlan -Plan $Plan -Policy $Policy -OwnershipReceipts $receiptArray)) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'RESET_PLAN_INVALID' `
            -ReasonCodes @('RESET_PLAN_INVALID') -Plan $Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null
    }
    $plannedChanges = @($Plan.Actions | ForEach-Object {
        '{0}:{1}:{2}' -f $_.Provider, $_.Operation, $_.ResourceToken
    })

    $bindingArray = @($ResourceBindings)
    if ($bindingArray.Count -ne $entryArray.Count) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'RESOURCE_BINDING_INVALID' `
            -ReasonCodes @('RESOURCE_BINDING_INVALID') -Plan $Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }
    $orderedBindings = @()
    foreach ($entry in $entryArray) {
        $matches = @($bindingArray | Where-Object {
            $_.ResourceToken -is [string] -and $_.ResourceToken -ceq $entry.ResourceToken
        })
        if ($matches.Count -ne 1 -or -not (Test-CddsiVmResetLiveResourceBinding -Binding $matches[0] -AllowListEntry $entry)) {
            return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'RESOURCE_BINDING_INVALID' `
                -ReasonCodes @('RESOURCE_BINDING_INVALID') -Plan $Plan -SnapshotRestoreRequired $true `
                -EnvironmentAttestation $null -PlannedChanges $plannedChanges
        }
        $orderedBindings += $matches[0]
    }

    if (-not (Test-CddsiVmResetProviderAdapter -ProviderAdapter $ProviderAdapter)) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'PROVIDER_ADAPTER_INVALID' `
            -ReasonCodes @('PROVIDER_ADAPTER_INVALID') -Plan $Plan -SnapshotRestoreRequired $false `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }
    if (-not (Test-CddsiVmResetLiveContext -Context $Context -Mode $Mode -Policy $Policy `
        -Plan $Plan -ProviderAdapter $ProviderAdapter)) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'VM_RESET_CONTEXT_INVALID' `
            -ReasonCodes @('VM_RESET_CONTEXT_INVALID') -Plan $Plan -SnapshotRestoreRequired $false `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }

    if ($MilestoneType -cne 'DevelopmentRetest') {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' `
            -ReasonCodes @('MILESTONE_REQUIRES_SNAPSHOT') -Plan $Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }
    if ($Mode -cne 'Live') {
        $data = New-CddsiVmResetLiveAdapterData -Plan $Plan -Disposition 'PLAN_ONLY' `
            -RequiredResetMode 'GuestReset' -SnapshotRestoreRequired $false `
            -EnvironmentAttestation $null -MutationState 'NOT_STARTED' -ProviderCallCount 0 `
            -ReasonCodes @('VM_ACCEPTANCE_LIVE_REQUIRED')
        return New-CddsiOperationResult -Operation 'VmDeterministicGuestResetLiveAdapter' `
            -Status 'ACTION_REQUIRED' -Mode $Mode -Changed:$false -ErrorCode 'VM_ACCEPTANCE_LIVE_REQUIRED' `
            -MessageSafe 'Plan validated; no provider dispatch occurred outside Live VM acceptance.' `
            -PlannedChanges $plannedChanges -Warnings @('VM_ACCEPTANCE_LIVE_REQUIRED') -Data $data
    }
    if ($Context.EnvironmentTier -cne 'VmAcceptance' -or $Context.IsCi) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'HOST_OR_CI_LIVE_FORBIDDEN' `
            -ReasonCodes @('HOST_OR_CI_LIVE_FORBIDDEN') -Plan $Plan -SnapshotRestoreRequired $false `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }
    if (-not $AcknowledgeRealChanges.IsPresent) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'REAL_CHANGE_ACKNOWLEDGEMENT_REQUIRED' `
            -ReasonCodes @('REAL_CHANGE_ACKNOWLEDGEMENT_REQUIRED') -Plan $Plan -SnapshotRestoreRequired $false `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }
    if (-not $ReceiptValidatorAvailable.IsPresent) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' `
            -ReasonCodes @('RECEIPT_VALIDATOR_UNAVAILABLE') -Plan $Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }
    if ($ProviderAdapter.Kind -cne 'VmResetLive' -or -not $ProviderAdapter.IsLive) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'LIVE_PROVIDER_REQUIRED' `
            -ReasonCodes @('LIVE_PROVIDER_REQUIRED') -Plan $Plan -SnapshotRestoreRequired $false `
            -EnvironmentAttestation $null -PlannedChanges $plannedChanges
    }

    # Live never invokes ProviderAdapter.Invoke. The only accepted adapter is a
    # v2 handle registered by the fixed Windows provider factory after local
    # byte hashing, the SYSTEM-owned provisioning anchor, authority and device
    # signatures, disposable-VM identity and the exact execution bundle have
    # all validated. A caller-created object or scriptblock has no registered
    # runtime handle and remains zero-dispatch.
    if ($null -eq (Get-Command -Name Test-CddsiWindowsVmResetProviderAdapterAuthorization `
        -CommandType Function -ErrorAction SilentlyContinue) -or
        -not (Test-CddsiWindowsVmResetProviderAdapterAuthorization -ProviderAdapter $ProviderAdapter)) {
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode `
            -ErrorCode 'VM_RESET_LIVE_TRUST_CHAIN_UNPROVISIONED' `
            -ReasonCodes @(
                'FIXED_ADAPTER_SHA_UNVERIFIED',
                'VM_DEVICE_ATTESTATION_TRUST_UNVERIFIED',
                'WINDOWS_LIVE_PROVIDER_UNAVAILABLE'
            ) -Plan $Plan -SnapshotRestoreRequired $true -EnvironmentAttestation $null `
            -PlannedChanges $plannedChanges
    }

    $providerCallCount = 0
    $mutationDispatchCount = 0
    $environmentAttestation = $null
    $baselineBefore = $null
    $baselineAfter = $null
    $preflightEvidence = @()
    $actionReceipts = @()
    $finalState = $null
    $currentStage = 'ENVIRONMENT_ATTESTATION'

    try {
        $providerDispatch = Invoke-CddsiVmResetInjectedProvider -ProviderAdapter $ProviderAdapter `
            -Provider 'Environment' -Operation 'AttestVmAcceptance' `
            -ResourceToken '<VM_RESET_ENVIRONMENT:VM_ACCEPTANCE>' -Arguments ([ordered]@{
                RunId = $Context.RunId
                VmIdentity = $Policy.VmIdentity
                ImageSha256 = $Policy.ImageSha256
                ResetPolicyDigest = $Policy.ResetPolicyDigest
                PlanBindingToken = $Plan.PlanBindingToken
                PrincipalRole = $Context.PrincipalRole
            }) -CallCount ([ref]$providerCallCount)
        $environmentAttestation = $providerDispatch.Result
        if (-not (Test-CddsiVmResetEnvironmentAttestation -Attestation $environmentAttestation `
            -Context $Context -Policy $Policy -ProviderAdapter $ProviderAdapter)) {
            throw 'Environment attestation is invalid.'
        }

        $currentStage = 'BASELINE_BEFORE'
        $providerDispatch = Invoke-CddsiVmResetInjectedProvider -ProviderAdapter $ProviderAdapter `
            -Provider 'Environment' -Operation 'CaptureBaseline' `
            -ResourceToken '<VM_RESET_BASELINE:BEFORE>' -Arguments ([ordered]@{
                Phase = 'Before'
                ResetPolicyDigest = $Policy.ResetPolicyDigest
                PlanBindingToken = $Plan.PlanBindingToken
            }) -CallCount ([ref]$providerCallCount)
        $baselineBefore = $providerDispatch.Result
        if (-not (Test-CddsiVmResetBaseline -Baseline $baselineBefore -Policy $Policy)) {
            throw 'Baseline before is invalid or drifted.'
        }

        $currentStage = 'RESOURCE_PREFLIGHT'
        for ($index = 0; $index -lt $entryArray.Count; $index++) {
            $entry = $entryArray[$index]
            $binding = $orderedBindings[$index]
            $providerDispatch = Invoke-CddsiVmResetInjectedProvider -ProviderAdapter $ProviderAdapter `
                -Provider $entry.Provider -Operation 'ValidateExactTarget' `
                -ResourceToken $entry.ResourceToken -Arguments ([ordered]@{
                    PlanBindingToken = $Plan.PlanBindingToken
                    Sequence = [int]$entry.Sequence
                    OwnershipReceiptBindingToken = $entry.OwnershipReceiptBindingToken
                    TargetBindingToken = $binding.TargetBindingToken
                    TargetDescriptor = $binding.TargetDescriptor
                }) -CallCount ([ref]$providerCallCount)
            $evidence = $providerDispatch.Result
            if (-not (Test-CddsiVmResetPreflightEvidence -Evidence $evidence -Binding $binding -AllowListEntry $entry)) {
                throw 'Resource preflight evidence is invalid.'
            }
            $preflightEvidence += $evidence
        }

        $currentStage = 'MUTATION'
        for ($index = 0; $index -lt $Plan.Actions.Count; $index++) {
            $action = $Plan.Actions[$index]
            $binding = $orderedBindings[$index]
            $preflight = $preflightEvidence[$index]
            $mutationDispatchCount++
            $providerDispatch = Invoke-CddsiVmResetInjectedProvider -ProviderAdapter $ProviderAdapter `
                -Provider $action.Provider -Operation $action.Operation `
                -ResourceToken $action.ResourceToken -Arguments ([ordered]@{
                    Purpose = 'VmResetLiveMutation'
                    PlanBindingToken = $Plan.PlanBindingToken
                    Sequence = [int]$action.Sequence
                    ResourceId = $action.ResourceId
                    ResourceType = $action.ResourceType
                    OwnershipReceiptBindingToken = $action.OwnershipReceiptBindingToken
                    TargetBindingToken = $binding.TargetBindingToken
                    TargetDescriptor = $binding.TargetDescriptor
                    PreflightEvidenceDigest = $preflight.EvidenceDigest
                    RequireAtomicTargetRevalidation = $true
                }) -CallCount ([ref]$providerCallCount)
            $providerActionResult = $providerDispatch.Result
            if (-not (Test-CddsiVmResetProviderActionResult -Result $providerActionResult -Plan $Plan `
                -ExpectedAction $action -ExpectedRequestBindingToken $providerDispatch.RequestBindingToken `
                -Binding $binding -PreflightEvidence $preflight -ProviderAdapter $ProviderAdapter)) {
                throw 'Provider action result is not bound to the exact request and atomic target postcondition.'
            }
            $receipt = $providerActionResult.ActionReceipt
            $actionReceipts += $receipt
            if ($receipt.Outcome -cne 'COMPLETED') {
                throw 'Action receipt did not prove a completed state.'
            }
        }

        $currentStage = 'BASELINE_AFTER'
        $providerDispatch = Invoke-CddsiVmResetInjectedProvider -ProviderAdapter $ProviderAdapter `
            -Provider 'Environment' -Operation 'CaptureBaseline' `
            -ResourceToken '<VM_RESET_BASELINE:AFTER>' -Arguments ([ordered]@{
                Phase = 'After'
                ResetPolicyDigest = $Policy.ResetPolicyDigest
                PlanBindingToken = $Plan.PlanBindingToken
            }) -CallCount ([ref]$providerCallCount)
        $baselineAfter = $providerDispatch.Result
        if (-not (Test-CddsiVmResetBaseline -Baseline $baselineAfter -Policy $Policy)) {
            throw 'Baseline after is invalid or drifted.'
        }

        $currentStage = 'FINAL_STATE'
        $providerDispatch = Invoke-CddsiVmResetInjectedProvider -ProviderAdapter $ProviderAdapter `
            -Provider 'Environment' -Operation 'InspectFinalState' `
            -ResourceToken '<VM_RESET_STATE:FINAL>' -Arguments ([ordered]@{
                ResetPolicyDigest = $Policy.ResetPolicyDigest
                PlanBindingToken = $Plan.PlanBindingToken
            }) -CallCount ([ref]$providerCallCount)
        $finalEvidence = $providerDispatch.Result
        if (-not (Test-CddsiVmResetFinalStateEvidence -Evidence $finalEvidence)) {
            throw 'Final state evidence is invalid.'
        }
        $finalState = [pscustomobject][ordered]@{
            SchemaVersion = $finalEvidence.SchemaVersion
            ContractVersion = $finalEvidence.ContractVersion
            VmpState = $finalEvidence.VmpState
            RebootState = $finalEvidence.RebootState
            UninstallState = $finalEvidence.UninstallState
            CompensationState = $finalEvidence.CompensationState
        }

        $currentStage = 'DISPOSITION'
        $disposition = Resolve-CddsiVmResetDisposition -Policy $Policy -Plan $Plan `
            -OwnershipReceipts $receiptArray -ActionReceipts $actionReceipts `
            -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -FinalState $finalState `
            -CleanupFailureCount ([int]$finalEvidence.CleanupFailureCount) `
            -UnknownMutationCount ([int]$finalEvidence.UnknownMutationCount) `
            -UnexpectedLedgerEntryCount ([int]$finalEvidence.UnexpectedLedgerEntryCount) `
            -SecretScanCount ([int]$finalEvidence.SecretScanCount) `
            -ReceiptValidatorAvailable $true -MilestoneType DevelopmentRetest
        if (-not $disposition.CanIssueCleanReady) {
            $mutationState = if (@($actionReceipts | Where-Object { $_.Changed }).Count -gt 0) { 'CHANGED' } else { 'UNCHANGED' }
            return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' `
                -ReasonCodes @($disposition.ReasonCodes) -Plan $Plan -SnapshotRestoreRequired $true `
                -EnvironmentAttestation $environmentAttestation -PreflightEvidence $preflightEvidence `
                -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -ActionReceipts $actionReceipts `
                -FinalState $finalState -MutationState $mutationState -ProviderCallCount $providerCallCount `
                -PlannedChanges $plannedChanges
        }

        $currentStage = 'CLEAN_READY_RECEIPT'
        $cleanReadyReceipt = New-CddsiVmCleanReadyReceipt -Policy $Policy -Plan $Plan `
            -OwnershipReceipts $receiptArray -ActionReceipts $actionReceipts `
            -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -FinalState $finalState `
            -StartedAtUtc $baselineBefore.CapturedAtUtc -CompletedAtUtc $baselineAfter.CapturedAtUtc `
            -ControlIdentity $Context.ControlIdentity -AuthenticationDigest $Context.AuthenticationDigest `
            -ExecutionMode Live -CleanupFailureCount ([int]$finalEvidence.CleanupFailureCount) `
            -UnknownMutationCount ([int]$finalEvidence.UnknownMutationCount) `
            -UnexpectedLedgerEntryCount ([int]$finalEvidence.UnexpectedLedgerEntryCount) `
            -SecretScanCount ([int]$finalEvidence.SecretScanCount) -ReceiptValidatorAvailable $true
    }
    catch {
        $reason = switch -CaseSensitive ($currentStage) {
            'ENVIRONMENT_ATTESTATION' { 'VM_ENVIRONMENT_ATTESTATION_INVALID'; break }
            'BASELINE_BEFORE' { 'BASELINE_DRIFT'; break }
            'RESOURCE_PREFLIGHT' { 'RESOURCE_PREFLIGHT_INVALID'; break }
            'MUTATION' { 'ACTION_STATE_AMBIGUOUS'; break }
            'BASELINE_AFTER' { 'BASELINE_DRIFT'; break }
            'FINAL_STATE' { 'FINAL_STATE_INVALID'; break }
            'CLEAN_READY_RECEIPT' { 'ACTION_RECEIPT_INVALID'; break }
            default { 'UNKNOWN_MUTATION'; break }
        }
        $mutationState = if ($mutationDispatchCount -gt 0) { 'UNKNOWN' } else { 'NOT_STARTED' }
        return New-CddsiVmResetLiveBlockedResult -Mode $Mode -ErrorCode 'SNAPSHOT_RESTORE_REQUIRED' `
            -ReasonCodes @($reason) -Plan $Plan -SnapshotRestoreRequired $true `
            -EnvironmentAttestation $environmentAttestation -PreflightEvidence $preflightEvidence `
            -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -ActionReceipts $actionReceipts `
            -FinalState $finalState -MutationState $mutationState -ProviderCallCount $providerCallCount `
            -PlannedChanges $plannedChanges
    }

    $changed = (@($actionReceipts | Where-Object { $_.Changed }).Count -gt 0)
    $mutationState = if ($changed) { 'CHANGED' } else { 'UNCHANGED' }
    $data = New-CddsiVmResetLiveAdapterData -Plan $Plan -Disposition 'CLEAN_READY' `
        -RequiredResetMode 'GuestReset' -SnapshotRestoreRequired $false `
        -EnvironmentAttestation $environmentAttestation -PreflightEvidence $preflightEvidence `
        -BaselineBefore $baselineBefore -BaselineAfter $baselineAfter -ActionReceipts $actionReceipts `
        -FinalState $finalState -CleanReadyReceipt $cleanReadyReceipt -MutationState $mutationState `
        -ProviderCallCount $providerCallCount -ReasonCodes @()
    return New-CddsiOperationResult -Operation 'VmDeterministicGuestResetLiveAdapter' `
        -Status 'SUCCEEDED' -Mode Live -Changed:$changed `
        -MessageSafe 'VM-only deterministic guest reset completed through the injected provider adapter.' `
        -PlannedChanges $plannedChanges -Data $data
}
