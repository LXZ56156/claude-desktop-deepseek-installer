# VM-only Windows deterministic reset provider.
#
# Import is deliberately inert: the top level contains immutable data and
# function definitions only. Real Windows access is reachable only from the
# provisioned Live factory after the frozen provider bytes, command bindings,
# authority and device signatures, disposable-VM identity and exact reset
# execution bundle have all validated. TestSafe and DryRun never construct a
# system adapter and never dispatch a provider call.

$script:CddsiWindowsVmResetProviderImportedPath = $PSCommandPath
$script:CddsiWindowsVmResetDeviceKeyName = 'cddsi-vm-reset-device-v1'
$script:CddsiWindowsVmResetProviderId = 'cddsi-vm-reset-provider-windows-v2'
$script:CddsiWindowsVmResetNotApplicable = 'NOT_APPLICABLE'
$script:CddsiWindowsVmResetProvisioningAnchorPath = 'C:\ProgramData\cddsi-vm-operator\provisioning\reset-anchor.json'
$script:CddsiWindowsVmResetOneShotGrantDirectory = 'C:\ProgramData\cddsi-vm-operator\provisioning\grants'
$script:CddsiWindowsVmResetAuthorizedRuntimes = @{}
$script:CddsiWindowsVmResetConsumedGrantHandles = @{}
$script:CddsiWindowsVmResetBaselineSpecifications = @(
    [pscustomobject][ordered]@{ Sequence = 1; Domain = 'OS';         Provider = 'Environment'; ResourceToken = '<VM_RESET_BASELINE:OS>' },
    [pscustomobject][ordered]@{ Sequence = 2; Domain = 'AppX';       Provider = 'Package';     ResourceToken = '<VM_RESET_BASELINE:APPX>' },
    [pscustomobject][ordered]@{ Sequence = 3; Domain = 'Git';        Provider = 'Process';     ResourceToken = '<VM_RESET_BASELINE:GIT>' },
    [pscustomobject][ordered]@{ Sequence = 4; Domain = 'VMP';        Provider = 'Feature';     ResourceToken = '<VM_RESET_BASELINE:VMP>' },
    [pscustomobject][ordered]@{ Sequence = 5; Domain = 'Registry';   Provider = 'Registry';    ResourceToken = '<VM_RESET_BASELINE:REGISTRY>' },
    [pscustomobject][ordered]@{ Sequence = 6; Domain = 'Credential'; Provider = 'Credential';  ResourceToken = '<VM_RESET_BASELINE:CREDENTIAL>' },
    [pscustomobject][ordered]@{ Sequence = 7; Domain = 'Checkpoint'; Provider = 'FileSystem';  ResourceToken = '<VM_RESET_BASELINE:CHECKPOINT>' },
    [pscustomobject][ordered]@{ Sequence = 8; Domain = 'FileSystem'; Provider = 'FileSystem';  ResourceToken = '<VM_RESET_BASELINE:FILESYSTEM>' }
)
$script:CddsiWindowsVmResetProviderOperationSpecifications = @(
    [pscustomobject][ordered]@{ Sequence = 1;  Provider = 'Environment'; Operation = 'AttestVmAcceptance'; ResourceType = 'Environment';          Mutation = $false; CommandId = 'attest-vm';            EntryPoint = 'Invoke-CddsiWindowsVmResetAttestVmInternal' },
    [pscustomobject][ordered]@{ Sequence = 2;  Provider = 'Environment'; Operation = 'CaptureBaseline';     ResourceType = 'Baseline';             Mutation = $false; CommandId = 'capture-baseline';     EntryPoint = 'Invoke-CddsiWindowsVmResetCaptureBaselineInternal' },
    [pscustomobject][ordered]@{ Sequence = 3;  Provider = 'Package';     Operation = 'ValidateExactTarget'; ResourceType = 'Package';              Mutation = $false; CommandId = 'preflight-package';    EntryPoint = 'Get-CddsiWindowsVmResetResourceObservationInternal' },
    [pscustomobject][ordered]@{ Sequence = 4;  Provider = 'Registry';    Operation = 'ValidateExactTarget'; ResourceType = 'HkcuValue';            Mutation = $false; CommandId = 'preflight-hkcu';       EntryPoint = 'Get-CddsiWindowsVmResetResourceObservationInternal' },
    [pscustomobject][ordered]@{ Sequence = 5;  Provider = 'Credential';  Operation = 'ValidateExactTarget'; ResourceType = 'Credential';           Mutation = $false; CommandId = 'preflight-credential'; EntryPoint = 'Get-CddsiWindowsVmResetResourceObservationInternal' },
    [pscustomobject][ordered]@{ Sequence = 6;  Provider = 'FileSystem';  Operation = 'ValidateExactTarget'; ResourceType = 'Checkpoint';           Mutation = $false; CommandId = 'preflight-checkpoint'; EntryPoint = 'Get-CddsiWindowsVmResetResourceObservationInternal' },
    [pscustomobject][ordered]@{ Sequence = 7;  Provider = 'FileSystem';  Operation = 'ValidateExactTarget'; ResourceType = 'OwnerMarkedDirectory'; Mutation = $false; CommandId = 'preflight-directory';  EntryPoint = 'Get-CddsiWindowsVmResetResourceObservationInternal' },
    [pscustomobject][ordered]@{ Sequence = 8;  Provider = 'Package';     Operation = 'Remove';              ResourceType = 'Package';              Mutation = $true;  CommandId = 'remove-package';       EntryPoint = 'Invoke-CddsiWindowsVmResetResourceMutationInternal' },
    [pscustomobject][ordered]@{ Sequence = 9;  Provider = 'Registry';    Operation = 'DeleteValue';         ResourceType = 'HkcuValue';            Mutation = $true;  CommandId = 'delete-hkcu';          EntryPoint = 'Invoke-CddsiWindowsVmResetResourceMutationInternal' },
    [pscustomobject][ordered]@{ Sequence = 10; Provider = 'Credential';  Operation = 'Delete';              ResourceType = 'Credential';           Mutation = $true;  CommandId = 'delete-credential';    EntryPoint = 'Invoke-CddsiWindowsVmResetResourceMutationInternal' },
    [pscustomobject][ordered]@{ Sequence = 11; Provider = 'FileSystem';  Operation = 'DeleteFile';          ResourceType = 'Checkpoint';           Mutation = $true;  CommandId = 'delete-checkpoint';    EntryPoint = 'Invoke-CddsiWindowsVmResetResourceMutationInternal' },
    [pscustomobject][ordered]@{ Sequence = 12; Provider = 'FileSystem';  Operation = 'DeleteDirectory';     ResourceType = 'OwnerMarkedDirectory'; Mutation = $true;  CommandId = 'delete-directory';     EntryPoint = 'Invoke-CddsiWindowsVmResetResourceMutationInternal' },
    [pscustomobject][ordered]@{ Sequence = 13; Provider = 'Environment'; Operation = 'InspectFinalState';    ResourceType = 'FinalState';           Mutation = $false; CommandId = 'inspect-final-state';  EntryPoint = 'Invoke-CddsiWindowsVmResetInspectFinalStateInternal' }
)

function Get-CddsiWindowsVmResetProviderOperationContract {
    [CmdletBinding()]
    param()

    return @($script:CddsiWindowsVmResetProviderOperationSpecifications | ForEach-Object {
        [pscustomobject][ordered]@{
            Sequence = $_.Sequence
            Provider = $_.Provider
            Operation = $_.Operation
            ResourceType = $_.ResourceType
            Mutation = $_.Mutation
            CommandId = $_.CommandId
            FileName = 'windows-vm-reset.ps1'
            EntryPoint = $_.EntryPoint
        }
    })
}

function Get-CddsiWindowsVmResetSha256HexInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

function ConvertFrom-CddsiWindowsVmResetBase64Internal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Value)

    if ($Value -isnot [string] -or $Value.Length -lt 8 -or $Value.Length -gt 4096) { return $null }
    try { return [Convert]::FromBase64String($Value) }
    catch { return $null }
}

function Test-CddsiWindowsVmResetPinnedBlobInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$BlobBase64,
        [Parameter(Mandatory = $true)][AllowNull()]$ExpectedSha256
    )

    if (-not (Test-CddsiVmCalibrationSha256Value -Value $ExpectedSha256)) { return $false }
    $bytes = ConvertFrom-CddsiWindowsVmResetBase64Internal -Value $BlobBase64
    return ($null -ne $bytes -and $bytes.Count -ge 32 -and
        (Get-CddsiWindowsVmResetSha256HexInternal -Bytes $bytes) -ceq $ExpectedSha256)
}

function Test-CddsiWindowsVmResetCommandBinding {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Binding,
        [Parameter(Mandatory = $true)]$Expected,
        [Parameter(Mandatory = $true)]$Policy
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Binding -Expected @(
        'SchemaVersion', 'ContractVersion', 'Sequence', 'Provider', 'Operation',
        'ResourceType', 'Mutation', 'CommandId', 'CommandFilePath',
        'CommandFileSha256', 'EntryPoint'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $Binding.SchemaVersion) -or
        $Binding.ContractVersion -cne 'cddsi-windows-vm-reset-command-binding-v2' -or
        ($Binding.Sequence -isnot [int] -and $Binding.Sequence -isnot [long]) -or
        [long]$Binding.Sequence -ne [long]$Expected.Sequence -or
        $Binding.Provider -cne $Expected.Provider -or $Binding.Operation -cne $Expected.Operation -or
        $Binding.ResourceType -cne $Expected.ResourceType -or
        $Binding.Mutation -isnot [bool] -or $Binding.Mutation -ne $Expected.Mutation -or
        $Binding.CommandId -cne $Expected.CommandId -or $Binding.EntryPoint -cne $Expected.EntryPoint -or
        $Binding.CommandFilePath -cne $Policy.ProviderFilePath -or
        $Binding.CommandFileSha256 -cne $Policy.ProviderFileSha256) {
        return $false
    }
    return $true
}

function Get-CddsiWindowsVmResetPolicyPayloadInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Policy)

    return [pscustomobject][ordered]@{
        SchemaVersion = $Policy.SchemaVersion
        ContractVersion = $Policy.ContractVersion
        EnvironmentTier = $Policy.EnvironmentTier
        VmIdentity = $Policy.VmIdentity
        ImageSha256 = $Policy.ImageSha256
        DisposableVmIdentitySha256 = $Policy.DisposableVmIdentitySha256
        ExpectedVmManufacturer = $Policy.ExpectedVmManufacturer
        ExpectedVmModel = $Policy.ExpectedVmModel
        ProviderAdapterId = $Policy.ProviderAdapterId
        ProviderFilePath = $Policy.ProviderFilePath
        ProviderFileSha256 = $Policy.ProviderFileSha256
        DeviceCngKeyName = $Policy.DeviceCngKeyName
        DevicePublicKeyCngBlobBase64 = $Policy.DevicePublicKeyCngBlobBase64
        DeviceAttestationPublicKeySha256 = $Policy.DeviceAttestationPublicKeySha256
        AuthorityPublicKeyCngBlobBase64 = $Policy.AuthorityPublicKeyCngBlobBase64
        DeviceAttestationAuthoritySha256 = $Policy.DeviceAttestationAuthoritySha256
        GitExecutablePath = $Policy.GitExecutablePath
        GitExecutableSha256 = $Policy.GitExecutableSha256
        CommandRootPath = $Policy.CommandRootPath
        CommandBindings = @($Policy.CommandBindings)
        Frozen = $Policy.Frozen
        LiveProvisioningState = $Policy.LiveProvisioningState
        AttestationNotBeforeUtc = $Policy.AttestationNotBeforeUtc
        AttestationExpiresAtUtc = $Policy.AttestationExpiresAtUtc
    }
}

function Test-CddsiWindowsVmResetTrustPolicy {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Policy)

    if (-not (Test-CddsiExactPropertySet -InputObject $Policy -Expected @(
        'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'VmIdentity',
        'ImageSha256', 'DisposableVmIdentitySha256', 'ExpectedVmManufacturer',
        'ExpectedVmModel', 'ProviderAdapterId', 'ProviderFilePath',
        'ProviderFileSha256', 'DeviceCngKeyName', 'DevicePublicKeyCngBlobBase64',
        'DeviceAttestationPublicKeySha256', 'AuthorityPublicKeyCngBlobBase64',
        'DeviceAttestationAuthoritySha256', 'GitExecutablePath',
        'GitExecutableSha256', 'CommandRootPath', 'CommandBindings', 'Frozen',
        'LiveProvisioningState', 'AttestationNotBeforeUtc',
        'AttestationExpiresAtUtc', 'PolicyBindingToken'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $Policy.SchemaVersion) -or
        $Policy.ContractVersion -cne 'cddsi-windows-vm-reset-trust-policy-v2' -or
        $Policy.EnvironmentTier -cne 'VmAcceptance' -or
        -not (Test-CddsiSafeIdentifierValue -Value $Policy.VmIdentity -MaxLength 128) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.ImageSha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.DisposableVmIdentitySha256) -or
        -not (Test-CddsiWindowsVmResetDisplayFactInternal -Value $Policy.ExpectedVmManufacturer) -or
        -not (Test-CddsiWindowsVmResetDisplayFactInternal -Value $Policy.ExpectedVmModel) -or
        $Policy.ProviderAdapterId -cne $script:CddsiWindowsVmResetProviderId -or
        -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Policy.ProviderFilePath) -or
        [IO.Path]::GetFileName($Policy.ProviderFilePath) -cne 'windows-vm-reset.ps1' -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.ProviderFileSha256) -or
        $Policy.DeviceCngKeyName -cne $script:CddsiWindowsVmResetDeviceKeyName -or
        -not (Test-CddsiWindowsVmResetPinnedBlobInternal -BlobBase64 $Policy.DevicePublicKeyCngBlobBase64 `
            -ExpectedSha256 $Policy.DeviceAttestationPublicKeySha256) -or
        -not (Test-CddsiWindowsVmResetPinnedBlobInternal -BlobBase64 $Policy.AuthorityPublicKeyCngBlobBase64 `
            -ExpectedSha256 $Policy.DeviceAttestationAuthoritySha256) -or
        -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Policy.GitExecutablePath) -or
        [IO.Path]::GetFileName($Policy.GitExecutablePath) -cne 'git.exe' -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.GitExecutableSha256) -or
        -not (Test-CddsiVmResetLiveCanonicalLocalPath -Path $Policy.CommandRootPath) -or
        -not (Test-CddsiVmResetLiveChildPath -Path $Policy.ProviderFilePath -Root $Policy.CommandRootPath) -or
        $Policy.Frozen -isnot [bool] -or -not $Policy.Frozen -or
        @('UNPROVISIONED', 'PROVISIONED') -cnotcontains $Policy.LiveProvisioningState -or
        -not (Test-CddsiUtcTimestampValue -Value $Policy.AttestationNotBeforeUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Policy.AttestationExpiresAtUtc) -or
        [DateTimeOffset]::Parse($Policy.AttestationExpiresAtUtc) -le [DateTimeOffset]::Parse($Policy.AttestationNotBeforeUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Policy.PolicyBindingToken)) {
        return $false
    }

    $expectedOperations = @(Get-CddsiWindowsVmResetProviderOperationContract)
    $bindings = @($Policy.CommandBindings)
    if ($bindings.Count -ne $expectedOperations.Count) { return $false }
    for ($index = 0; $index -lt $expectedOperations.Count; $index++) {
        if (-not (Test-CddsiWindowsVmResetCommandBinding -Binding $bindings[$index] `
            -Expected $expectedOperations[$index] -Policy $Policy)) { return $false }
    }
    return ($Policy.PolicyBindingToken -ceq (Get-CddsiVmResetBindingToken -Value (
        Get-CddsiWindowsVmResetPolicyPayloadInternal -Policy $Policy
    )))
}

function Get-CddsiWindowsVmResetCommandSetDigestInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Policy)

    return Get-CddsiVmResetBindingToken -Value @($Policy.CommandBindings)
}

function Get-CddsiWindowsVmResetAuthorityPayloadInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Evidence)

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-windows-vm-reset-authority-provisioning-v1'
        VmIdentity = $Evidence.VmIdentity
        ImageSha256 = $Evidence.ImageSha256
        DisposableVmIdentitySha256 = $Evidence.DisposableVmIdentitySha256
        SupervisorVmIdentityReceiptBindingToken = $Evidence.SupervisorVmIdentityReceiptBindingToken
        DeviceAttestationPublicKeySha256 = $Evidence.DeviceAttestationPublicKeySha256
        ProviderFileSha256 = $Evidence.ObservedProviderFileSha256
        CommandSetDigest = $Evidence.CommandSetDigest
        NotBeforeUtc = $Evidence.NotBeforeUtc
        ExpiresAtUtc = $Evidence.ExpiresAtUtc
    }
}

function Get-CddsiWindowsVmResetDeviceAttestationPayloadInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Evidence)

    return [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-windows-vm-reset-device-deployment-attestation-v1'
        ChallengeSha256 = $Evidence.ChallengeSha256
        AuthorityProvisioningPayloadSha256 = $Evidence.AuthorityProvisioningPayloadSha256
        ProviderFilePath = $Evidence.ProviderFilePath
        ObservedProviderFileSha256 = $Evidence.ObservedProviderFileSha256
        CommandEvidenceDigest = Get-CddsiVmResetBindingToken -Value @($Evidence.CommandEvidence)
        VerifiedAtUtc = $Evidence.VerifiedAtUtc
    }
}

function Test-CddsiWindowsVmResetDeploymentEvidence {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Evidence,
        [Parameter(Mandatory = $true)]$Policy
    )

    if (-not (Test-CddsiWindowsVmResetTrustPolicy -Policy $Policy) -or
        -not (Test-CddsiExactPropertySet -InputObject $Evidence -Expected @(
            'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'HostSystem',
            'VmIdentity', 'ImageSha256', 'DisposableVmIdentitySha256',
            'SupervisorVmIdentityReceiptBindingToken',
            'ProviderFilePath', 'ObservedProviderFileSha256',
            'DeviceAttestationPublicKeySha256', 'DeviceAttestationAuthoritySha256',
            'CommandSetDigest', 'ChallengeSha256',
            'AuthorityProvisioningPayloadSha256', 'AuthoritySignatureAlgorithm',
            'AuthoritySignatureBase64', 'DeviceAttestationPayloadSha256',
            'DeviceSignatureAlgorithm', 'DeviceSignatureBase64', 'CommandEvidence',
            'NotBeforeUtc', 'ExpiresAtUtc', 'VerifiedAtUtc',
            'CryptographicVerificationState', 'EvidenceBindingToken'
        )) -or -not (Test-CddsiSchemaVersionOne -Value $Evidence.SchemaVersion) -or
        $Evidence.ContractVersion -cne 'cddsi-windows-vm-reset-deployment-evidence-v2' -or
        $Evidence.EnvironmentTier -cne 'VmAcceptance' -or $Evidence.HostSystem -cne 'Windows' -or
        $Evidence.VmIdentity -cne $Policy.VmIdentity -or $Evidence.ImageSha256 -cne $Policy.ImageSha256 -or
        $Evidence.DisposableVmIdentitySha256 -cne $Policy.DisposableVmIdentitySha256 -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.SupervisorVmIdentityReceiptBindingToken) -or
        $Evidence.ProviderFilePath -cne $Policy.ProviderFilePath -or
        $Evidence.ObservedProviderFileSha256 -cne $Policy.ProviderFileSha256 -or
        $Evidence.DeviceAttestationPublicKeySha256 -cne $Policy.DeviceAttestationPublicKeySha256 -or
        $Evidence.DeviceAttestationAuthoritySha256 -cne $Policy.DeviceAttestationAuthoritySha256 -or
        $Evidence.CommandSetDigest -cne (Get-CddsiWindowsVmResetCommandSetDigestInternal -Policy $Policy) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.ChallengeSha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.AuthorityProvisioningPayloadSha256) -or
        $Evidence.AuthoritySignatureAlgorithm -cne 'ECDSA_P256_SHA256' -or
        $null -eq (ConvertFrom-CddsiWindowsVmResetBase64Internal -Value $Evidence.AuthoritySignatureBase64) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.DeviceAttestationPayloadSha256) -or
        $Evidence.DeviceSignatureAlgorithm -cne 'ECDSA_P256_SHA256' -or
        $null -eq (ConvertFrom-CddsiWindowsVmResetBase64Internal -Value $Evidence.DeviceSignatureBase64) -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.NotBeforeUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.ExpiresAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Evidence.VerifiedAtUtc) -or
        $Evidence.NotBeforeUtc -cne $Policy.AttestationNotBeforeUtc -or
        $Evidence.ExpiresAtUtc -cne $Policy.AttestationExpiresAtUtc -or
        $Evidence.CryptographicVerificationState -cne 'SIGNED_PENDING_LOCAL_VERIFICATION' -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Evidence.EvidenceBindingToken)) {
        return $false
    }

    $commandEvidence = @($Evidence.CommandEvidence)
    if ($commandEvidence.Count -ne @($Policy.CommandBindings).Count) { return $false }
    for ($index = 0; $index -lt $commandEvidence.Count; $index++) {
        $item = $commandEvidence[$index]
        $binding = $Policy.CommandBindings[$index]
        if (-not (Test-CddsiExactPropertySet -InputObject $item -Expected @(
            'Sequence', 'CommandId', 'CommandFilePath', 'ObservedCommandFileSha256'
        )) -or [long]$item.Sequence -ne [long]$binding.Sequence -or
            $item.CommandId -cne $binding.CommandId -or
            $item.CommandFilePath -cne $binding.CommandFilePath -or
            $item.ObservedCommandFileSha256 -cne $binding.CommandFileSha256) { return $false }
    }

    $authorityDigest = Get-CddsiVmResetBindingToken -Value (
        Get-CddsiWindowsVmResetAuthorityPayloadInternal -Evidence $Evidence
    )
    $deviceDigest = Get-CddsiVmResetBindingToken -Value (
        Get-CddsiWindowsVmResetDeviceAttestationPayloadInternal -Evidence $Evidence
    )
    if ($Evidence.AuthorityProvisioningPayloadSha256 -cne $authorityDigest -or
        $Evidence.DeviceAttestationPayloadSha256 -cne $deviceDigest) { return $false }

    $fields = @(
        'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'HostSystem',
        'VmIdentity', 'ImageSha256', 'DisposableVmIdentitySha256',
        'SupervisorVmIdentityReceiptBindingToken',
        'ProviderFilePath', 'ObservedProviderFileSha256',
        'DeviceAttestationPublicKeySha256', 'DeviceAttestationAuthoritySha256',
        'CommandSetDigest', 'ChallengeSha256', 'AuthorityProvisioningPayloadSha256',
        'AuthoritySignatureAlgorithm', 'AuthoritySignatureBase64',
        'DeviceAttestationPayloadSha256', 'DeviceSignatureAlgorithm',
        'DeviceSignatureBase64', 'CommandEvidence', 'NotBeforeUtc', 'ExpiresAtUtc',
        'VerifiedAtUtc', 'CryptographicVerificationState'
    )
    return ($Evidence.EvidenceBindingToken -ceq (Get-CddsiVmResetBindingToken -Value (
        Get-CddsiVmResetEvidencePayload -Evidence $Evidence -PropertyNames $fields
    )))
}

function Test-CddsiWindowsVmResetEcdsaSignatureInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$PublicKeyBlobBase64,
        [Parameter(Mandatory = $true)][string]$DigestSha256,
        [Parameter(Mandatory = $true)][string]$SignatureBase64
    )

    if (-not (Test-CddsiVmCalibrationSha256Value -Value $DigestSha256)) { return $false }
    $publicBytes = ConvertFrom-CddsiWindowsVmResetBase64Internal -Value $PublicKeyBlobBase64
    $signature = ConvertFrom-CddsiWindowsVmResetBase64Internal -Value $SignatureBase64
    if ($null -eq $publicBytes -or $null -eq $signature) { return $false }
    $key = $null
    $ecdsa = $null
    try {
        $key = [System.Security.Cryptography.CngKey]::Import(
            $publicBytes,
            [System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob
        )
        $ecdsa = [System.Security.Cryptography.ECDsaCng]::new($key)
        $digestBytes = [byte[]]::new(32)
        for ($index = 0; $index -lt 32; $index++) {
            $digestBytes[$index] = [Convert]::ToByte($DigestSha256.Substring($index * 2, 2), 16)
        }
        return $ecdsa.VerifyHash($digestBytes, $signature)
    }
    catch { return $false }
    finally {
        if ($null -ne $ecdsa) { $ecdsa.Dispose() }
        if ($null -ne $key) { $key.Dispose() }
    }
}

function Test-CddsiWindowsVmResetLiveAuthorization {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)][AllowNull()]$DeploymentEvidence,
        [Parameter(Mandatory = $true)][string]$VerificationTimeUtc
    )

    if (-not (Test-CddsiWindowsVmResetTrustPolicy -Policy $Policy) -or
        $Policy.LiveProvisioningState -cne 'PROVISIONED' -or
        -not (Test-CddsiWindowsVmResetDeploymentEvidence -Evidence $DeploymentEvidence -Policy $Policy) -or
        -not (Test-CddsiUtcTimestampValue -Value $VerificationTimeUtc)) { return $false }
    $now = [DateTimeOffset]::Parse($VerificationTimeUtc)
    if ($now -lt [DateTimeOffset]::Parse($DeploymentEvidence.NotBeforeUtc) -or
        $now -gt [DateTimeOffset]::Parse($DeploymentEvidence.ExpiresAtUtc) -or
        [DateTimeOffset]::Parse($DeploymentEvidence.VerifiedAtUtc) -gt $now) { return $false }
    return (
        (Test-CddsiWindowsVmResetEcdsaSignatureInternal `
            -PublicKeyBlobBase64 $Policy.AuthorityPublicKeyCngBlobBase64 `
            -DigestSha256 $DeploymentEvidence.AuthorityProvisioningPayloadSha256 `
            -SignatureBase64 $DeploymentEvidence.AuthoritySignatureBase64) -and
        (Test-CddsiWindowsVmResetEcdsaSignatureInternal `
            -PublicKeyBlobBase64 $Policy.DevicePublicKeyCngBlobBase64 `
            -DigestSha256 $DeploymentEvidence.DeviceAttestationPayloadSha256 `
            -SignatureBase64 $DeploymentEvidence.DeviceSignatureBase64)
    )
}

function Get-CddsiWindowsVmResetFileSha256Internal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $stream = [System.IO.File]::Open($Path, [System.IO.FileMode]::Open,
        [System.IO.FileAccess]::Read, [System.IO.FileShare]::Read)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($stream))).Replace('-', '').ToLowerInvariant() }
    finally {
        $stream.Dispose()
        $sha.Dispose()
    }
}

function Test-CddsiWindowsVmResetLocalBytesInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Policy)

    try {
        $imported = [IO.Path]::GetFullPath($script:CddsiWindowsVmResetProviderImportedPath)
        $expected = [IO.Path]::GetFullPath($Policy.ProviderFilePath)
        if (-not [string]::Equals($imported, $expected, [StringComparison]::OrdinalIgnoreCase)) { return $false }
        $providerHash = Get-CddsiWindowsVmResetFileSha256Internal -Path $imported
        if ($providerHash -cne $Policy.ProviderFileSha256) { return $false }
        foreach ($binding in @($Policy.CommandBindings)) {
            if ($binding.CommandFilePath -cne $Policy.ProviderFilePath -or
                $binding.CommandFileSha256 -cne $providerHash) { return $false }
        }
        return $true
    }
    catch { return $false }
}

function Test-CddsiWindowsVmResetExecutionBundleInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TrustPolicy,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][object[]]$ResourceBindings
    )

    if (-not (Test-CddsiVmResetPolicy -Policy $Policy) -or
        $Policy.VmIdentity -cne $TrustPolicy.VmIdentity -or
        $Policy.ImageSha256 -cne $TrustPolicy.ImageSha256 -or
        -not (Test-CddsiVmResetPlan -Plan $Plan -Policy $Policy -OwnershipReceipts $OwnershipReceipts)) {
        return $false
    }
    $entries = @($Policy.AllowList)
    if ($OwnershipReceipts.Count -ne $entries.Count -or $ResourceBindings.Count -ne $entries.Count) { return $false }
    foreach ($entry in $entries) {
        $receipts = @($OwnershipReceipts | Where-Object ReceiptBindingToken -CEQ $entry.OwnershipReceiptBindingToken)
        $bindings = @($ResourceBindings | Where-Object ResourceToken -CEQ $entry.ResourceToken)
        if ($receipts.Count -ne 1 -or $bindings.Count -ne 1 -or
            -not (Test-CddsiVmResetOwnershipReceipt -Receipt $receipts[0] -AllowListEntry $entry) -or
            -not (Test-CddsiVmResetLiveResourceBinding -Binding $bindings[0] -AllowListEntry $entry)) {
            return $false
        }
    }
    return $true
}

function Test-CddsiWindowsVmResetDisplayFactInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Value)

    return ($Value -is [string] -and $Value.Length -ge 1 -and $Value.Length -le 128 -and
        $Value -match '^[A-Za-z0-9][A-Za-z0-9 ._()/-]*$')
}

function Get-CddsiWindowsVmResetVmIdentityInternal {
    [CmdletBinding()]
    param()

    $systems = @(Get-CimInstance -ClassName Win32_ComputerSystem -ErrorAction Stop)
    $products = @(Get-CimInstance -ClassName Win32_ComputerSystemProduct -ErrorAction Stop)
    if ($systems.Count -ne 1 -or $products.Count -ne 1) {
        throw 'VM_IDENTITY_UNAVAILABLE'
    }
    $manufacturer = [string]$systems[0].Manufacturer
    $model = [string]$systems[0].Model
    $uuid = ([string]$products[0].UUID).ToLowerInvariant()
    if (-not (Test-CddsiWindowsVmResetDisplayFactInternal -Value $manufacturer) -or
        -not (Test-CddsiWindowsVmResetDisplayFactInternal -Value $model) -or
        $uuid -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
        $uuid -ceq '00000000-0000-0000-0000-000000000000') {
        throw 'VM_IDENTITY_INVALID'
    }
    $payload = [pscustomobject][ordered]@{
        Manufacturer = $manufacturer
        Model = $model
        HardwareUuid = $uuid
    }
    return [pscustomobject][ordered]@{
        Manufacturer = $manufacturer
        Model = $model
        HardwareUuid = $uuid
        IdentitySha256 = Get-CddsiVmResetBindingToken -Value $payload
    }
}

function New-CddsiWindowsVmResetDeviceSignerInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$TrustPolicy)

    $key = $null
    try {
        $key = [System.Security.Cryptography.CngKey]::Open($TrustPolicy.DeviceCngKeyName)
        if ($key.AlgorithmGroup.AlgorithmGroup -cne 'ECDSA') { throw 'DEVICE_KEY_ALGORITHM_INVALID' }
        $publicBytes = $key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
        $publicHash = Get-CddsiWindowsVmResetSha256HexInternal -Bytes $publicBytes
        if ($publicHash -cne $TrustPolicy.DeviceAttestationPublicKeySha256 -or
            [Convert]::ToBase64String($publicBytes) -cne $TrustPolicy.DevicePublicKeyCngBlobBase64) {
            throw 'DEVICE_KEY_BINDING_MISMATCH'
        }
        return [pscustomobject][ordered]@{
            Kind = 'WindowsCngDeviceSignerV1'
            KeyName = $TrustPolicy.DeviceCngKeyName
            PublicKeySha256 = $publicHash
        }
    }
    finally {
        if ($null -ne $key) { $key.Dispose() }
    }
}

function Invoke-CddsiWindowsVmResetDeviceSignInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Signer,
        [Parameter(Mandatory = $true)][string]$DigestSha256,
        [switch]$Simulation
    )

    if (-not (Test-CddsiVmCalibrationSha256Value -Value $DigestSha256)) {
        throw 'SIGNATURE_DIGEST_INVALID'
    }
    if ($Simulation.IsPresent) {
        if ($Signer.Kind -cne 'FakeWindowsVmResetSignerV1' -or $Signer.Sign -isnot [scriptblock]) {
            throw 'FAKE_SIGNER_INVALID'
        }
        return & $Signer.Sign $DigestSha256
    }
    if ($Signer.Kind -cne 'WindowsCngDeviceSignerV1' -or
        $Signer.KeyName -cne $script:CddsiWindowsVmResetDeviceKeyName) {
        throw 'DEVICE_SIGNER_INVALID'
    }
    $key = $null
    $ecdsa = $null
    try {
        $key = [System.Security.Cryptography.CngKey]::Open($Signer.KeyName)
        $publicBytes = $key.Export([System.Security.Cryptography.CngKeyBlobFormat]::EccPublicBlob)
        if ((Get-CddsiWindowsVmResetSha256HexInternal -Bytes $publicBytes) -cne $Signer.PublicKeySha256) {
            throw 'DEVICE_KEY_CHANGED'
        }
        $ecdsa = [System.Security.Cryptography.ECDsaCng]::new($key)
        $digestBytes = [byte[]]::new(32)
        for ($index = 0; $index -lt 32; $index++) {
            $digestBytes[$index] = [Convert]::ToByte($DigestSha256.Substring($index * 2, 2), 16)
        }
        return [Convert]::ToBase64String($ecdsa.SignHash($digestBytes))
    }
    finally {
        if ($null -ne $ecdsa) { $ecdsa.Dispose() }
        if ($null -ne $key) { $key.Dispose() }
    }
}

function Initialize-CddsiWindowsVmResetCredentialNativeInternal {
    [CmdletBinding()]
    param()

    if ($null -ne ('CddsiVmResetNativeCredential' -as [type])) { return }
    $source = @'
using System;
using System.ComponentModel;
using System.Runtime.InteropServices;

public static class CddsiVmResetNativeCredential
{
    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Unicode)]
    private struct CREDENTIAL
    {
        public UInt32 Flags;
        public UInt32 Type;
        public IntPtr TargetName;
        public IntPtr Comment;
        public System.Runtime.InteropServices.ComTypes.FILETIME LastWritten;
        public UInt32 CredentialBlobSize;
        public IntPtr CredentialBlob;
        public UInt32 Persist;
        public UInt32 AttributeCount;
        public IntPtr Attributes;
        public IntPtr TargetAlias;
        public IntPtr UserName;
    }

    [DllImport("advapi32.dll", EntryPoint = "CredReadW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredRead(string target, UInt32 type, UInt32 flags, out IntPtr credential);

    [DllImport("advapi32.dll", EntryPoint = "CredDeleteW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern bool CredDelete(string target, UInt32 type, UInt32 flags);

    [DllImport("advapi32.dll", SetLastError = true)]
    private static extern void CredFree(IntPtr buffer);

    public static int ProbeGeneric(string target)
    {
        IntPtr pointer;
        if (CredRead(target, 1, 0, out pointer))
        {
            try
            {
                CREDENTIAL value = (CREDENTIAL)Marshal.PtrToStructure(pointer, typeof(CREDENTIAL));
                string observed = Marshal.PtrToStringUni(value.TargetName);
                return String.Equals(observed, target, StringComparison.Ordinal) ? 1 : -87;
            }
            finally { CredFree(pointer); }
        }
        int error = Marshal.GetLastWin32Error();
        return error == 1168 ? 0 : -error;
    }

    public static int DeleteGeneric(string target)
    {
        if (CredDelete(target, 1, 0)) { return 1; }
        int error = Marshal.GetLastWin32Error();
        return error == 1168 ? 0 : -error;
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Initialize-CddsiWindowsVmResetGrantNativeInternal {
    [CmdletBinding()]
    param()

    if ($null -ne ('CddsiVmResetOneShotGrant' -as [type])) { return }
    $source = @'
using System;
using System.ComponentModel;
using System.IO;
using System.Runtime.InteropServices;
using Microsoft.Win32.SafeHandles;

public sealed class CddsiVmResetOneShotGrant : IDisposable
{
    private const UInt32 GENERIC_READ = 0x80000000;
    private const UInt32 DELETE = 0x00010000;
    private const UInt32 OPEN_EXISTING = 3;
    private const UInt32 FILE_ATTRIBUTE_NORMAL = 0x00000080;
    private const Int32 FileDispositionInfo = 4;
    private readonly FileStream stream;
    private bool disposed;

    [StructLayout(LayoutKind.Sequential)]
    private struct FILE_DISPOSITION_INFO
    {
        [MarshalAs(UnmanagedType.Bool)]
        public bool DeleteFile;
    }

    [DllImport("kernel32.dll", EntryPoint = "CreateFileW", CharSet = CharSet.Unicode, SetLastError = true)]
    private static extern SafeFileHandle CreateFile(
        string fileName, UInt32 desiredAccess, UInt32 shareMode, IntPtr securityAttributes,
        UInt32 creationDisposition, UInt32 flagsAndAttributes, IntPtr templateFile);

    [DllImport("kernel32.dll", SetLastError = true)]
    private static extern bool SetFileInformationByHandle(
        SafeFileHandle handle, Int32 informationClass,
        ref FILE_DISPOSITION_INFO information, UInt32 bufferSize);

    public CddsiVmResetOneShotGrant(string path)
    {
        SafeFileHandle handle = CreateFile(
            path, GENERIC_READ | DELETE, 0, IntPtr.Zero,
            OPEN_EXISTING, FILE_ATTRIBUTE_NORMAL, IntPtr.Zero);
        if (handle.IsInvalid)
        {
            int error = Marshal.GetLastWin32Error();
            handle.Dispose();
            throw new Win32Exception(error, "ONE_SHOT_GRANT_EXCLUSIVE_OPEN_FAILED");
        }
        stream = new FileStream(handle, FileAccess.Read, 4096, false);
    }

    public byte[] ReadAllBytes(Int32 maximumLength)
    {
        if (disposed) { throw new ObjectDisposedException("CddsiVmResetOneShotGrant"); }
        if (stream.Length < 1 || stream.Length > maximumLength)
        {
            throw new InvalidDataException("ONE_SHOT_GRANT_LENGTH_INVALID");
        }
        byte[] bytes = new byte[stream.Length];
        stream.Position = 0;
        int offset = 0;
        while (offset < bytes.Length)
        {
            int read = stream.Read(bytes, offset, bytes.Length - offset);
            if (read <= 0) { throw new EndOfStreamException("ONE_SHOT_GRANT_READ_INCOMPLETE"); }
            offset += read;
        }
        return bytes;
    }

    public void CommitDelete()
    {
        if (disposed) { throw new ObjectDisposedException("CddsiVmResetOneShotGrant"); }
        FILE_DISPOSITION_INFO information = new FILE_DISPOSITION_INFO { DeleteFile = true };
        UInt32 size = (UInt32)Marshal.SizeOf(typeof(FILE_DISPOSITION_INFO));
        if (!SetFileInformationByHandle(stream.SafeFileHandle, FileDispositionInfo, ref information, size))
        {
            throw new Win32Exception(Marshal.GetLastWin32Error(), "ONE_SHOT_GRANT_ATOMIC_DELETE_FAILED");
        }
    }

    public void Dispose()
    {
        if (disposed) { return; }
        disposed = true;
        stream.Dispose();
    }
}
'@
    Add-Type -TypeDefinition $source -Language CSharp -ErrorAction Stop
}

function Get-CddsiWindowsVmResetBytesSha256Internal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try { return ([BitConverter]::ToString($sha.ComputeHash($Bytes))).Replace('-', '').ToLowerInvariant() }
    finally { $sha.Dispose() }
}

function Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]
        [ValidateSet('ProvisioningAnchor', 'OneShotGrant')]
        [string]$Purpose
    )

    if (-not [IO.Directory]::Exists($Path)) {
        if ($Purpose -ceq 'ProvisioningAnchor') {
            throw 'PROVISIONING_ANCHOR_DIRECTORY_UNAVAILABLE'
        }
        throw 'ONE_SHOT_GRANT_DIRECTORY_UNAVAILABLE'
    }
    if (Test-CddsiWindowsVmResetReparseInternal -Path $Path) {
        if ($Purpose -ceq 'ProvisioningAnchor') {
            throw 'PROVISIONING_ANCHOR_DIRECTORY_REPARSE_POINT'
        }
        throw 'ONE_SHOT_GRANT_DIRECTORY_REPARSE_POINT'
    }

    $directoryAcl = Get-Acl -LiteralPath $Path -ErrorAction Stop
    $systemSid = 'S-1-5-18'
    $administratorsSid = 'S-1-5-32-544'
    $directoryOwnerSid = $directoryAcl.GetOwner(
        [System.Security.Principal.SecurityIdentifier]).Value
    if ($directoryOwnerSid -cne $systemSid) {
        if ($Purpose -ceq 'ProvisioningAnchor') {
            throw 'PROVISIONING_ANCHOR_DIRECTORY_OWNER_INVALID'
        }
        throw 'ONE_SHOT_GRANT_DIRECTORY_OWNER_INVALID'
    }

    $directoryMutationRights = (
        [System.Security.AccessControl.FileSystemRights]::WriteData -bor
        [System.Security.AccessControl.FileSystemRights]::AppendData -bor
        [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [System.Security.AccessControl.FileSystemRights]::Delete -bor
        [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [System.Security.AccessControl.FileSystemRights]::TakeOwnership
    )
    foreach ($rule in @($directoryAcl.GetAccessRules(
        $true, $true, [System.Security.Principal.SecurityIdentifier]))) {
        if ($rule.AccessControlType -ne [System.Security.AccessControl.AccessControlType]::Allow) {
            continue
        }
        $sid = $rule.IdentityReference.Value
        $rights = [System.Security.AccessControl.FileSystemRights]$rule.FileSystemRights
        if ($sid -cne $systemSid -and $sid -cne $administratorsSid -and
            (($rights -band $directoryMutationRights) -ne 0)) {
            if ($Purpose -ceq 'ProvisioningAnchor') {
                throw 'PROVISIONING_ANCHOR_DIRECTORY_ACL_TOO_BROAD'
            }
            throw 'ONE_SHOT_GRANT_DIRECTORY_ACL_TOO_BROAD'
        }
    }
}

function Open-CddsiWindowsVmResetOneShotGrantInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Anchor)

    $path = [string]$Anchor.OneShotGrantFilePath
    if (-not (Test-CddsiWindowsVmResetOneShotGrantPathInternal `
        -Path $path -GrantId $Anchor.OneShotGrantId) -or
        -not [IO.File]::Exists($path) -or
        (Test-CddsiWindowsVmResetReparseInternal -Path $path)) {
        throw 'ONE_SHOT_GRANT_FILE_UNAVAILABLE'
    }
    $ancestor = Get-CddsiWindowsVmResetAncestorObservationInternal -Path $path
    if ($ancestor.ReparsePointCount -ne 0) { throw 'ONE_SHOT_GRANT_ANCESTOR_REPARSE_POINT' }
    $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
    $systemSid = [System.Security.Principal.SecurityIdentifier]::new('S-1-5-18')
    $ownerSid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier])
    if ($ownerSid.Value -cne $systemSid.Value) { throw 'ONE_SHOT_GRANT_OWNER_INVALID' }
    $currentIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent()
    $currentSid = $currentIdentity.User.Value
    if ($currentSid -cne $Anchor.OneShotGrantConsumerSid) {
        throw 'ONE_SHOT_GRANT_CONSUMER_IDENTITY_MISMATCH'
    }
    $administratorsSid = 'S-1-5-32-544'
    if (@($currentIdentity.Groups | ForEach-Object { $_.Value }) -ccontains $administratorsSid) {
        throw 'ONE_SHOT_GRANT_CONSUMER_ADMINISTRATOR_FORBIDDEN'
    }
    $grantDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
    if (-not [string]::Equals(
        $grantDirectory, [IO.Path]::GetFullPath($script:CddsiWindowsVmResetOneShotGrantDirectory),
        [StringComparison]::OrdinalIgnoreCase
    )) { throw 'ONE_SHOT_GRANT_DIRECTORY_INVALID' }
    Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
        -Path $grantDirectory -Purpose OneShotGrant
    $rules = @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))
    $delete = [System.Security.AccessControl.FileSystemRights]::Delete
    $forbidden = (
        [System.Security.AccessControl.FileSystemRights]::WriteData -bor
        [System.Security.AccessControl.FileSystemRights]::AppendData -bor
        [System.Security.AccessControl.FileSystemRights]::WriteExtendedAttributes -bor
        [System.Security.AccessControl.FileSystemRights]::WriteAttributes -bor
        [System.Security.AccessControl.FileSystemRights]::DeleteSubdirectoriesAndFiles -bor
        [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [System.Security.AccessControl.FileSystemRights]::TakeOwnership
    )
    $consumerDeleteAllowed = $false
    foreach ($rule in $rules) {
        $sid = $rule.IdentityReference.Value
        $rights = [System.Security.AccessControl.FileSystemRights]$rule.FileSystemRights
        if ($rule.AccessControlType -ceq [System.Security.AccessControl.AccessControlType]::Deny) {
            if ($sid -ceq $currentSid -and (($rights -band $delete) -ne 0)) {
                throw 'ONE_SHOT_GRANT_CONSUMER_DELETE_DENIED'
            }
            continue
        }
        if ($sid -ceq $systemSid.Value) {
            if ($sid -ceq $currentSid -and (($rights -band $delete) -ne 0)) {
                $consumerDeleteAllowed = $true
            }
            continue
        }
        if (($rights -band $forbidden) -ne 0 -or
            ($sid -cne $currentSid -and (($rights -band $delete) -ne 0))) {
            throw 'ONE_SHOT_GRANT_ACL_TOO_BROAD'
        }
        if ($sid -ceq $currentSid -and (($rights -band $delete) -ne 0)) {
            $consumerDeleteAllowed = $true
        }
    }
    if (-not $consumerDeleteAllowed) { throw 'ONE_SHOT_GRANT_DELETE_CAPABILITY_MISSING' }
    Initialize-CddsiWindowsVmResetGrantNativeInternal
    return [CddsiVmResetOneShotGrant]::new($path)
}

function Test-CddsiWindowsVmResetReparseInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    return (([System.IO.File]::GetAttributes($Path) -band [System.IO.FileAttributes]::ReparsePoint) -ne 0)
}

function Get-CddsiWindowsVmResetAncestorObservationInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $parent = [IO.Path]::GetDirectoryName($Path.TrimEnd([IO.Path]::DirectorySeparatorChar))
    if ([string]::IsNullOrWhiteSpace($parent)) { throw 'OWNED_PATH_PARENT_INVALID' }
    $items = @()
    $reparseCount = 0
    $current = [IO.Path]::GetFullPath($parent).TrimEnd([IO.Path]::DirectorySeparatorChar)
    while (-not [string]::IsNullOrWhiteSpace($current)) {
        if (-not [IO.Directory]::Exists($current)) { throw 'OWNED_PATH_ANCESTOR_MISSING' }
        $attributes = [IO.File]::GetAttributes($current)
        $isReparse = (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0)
        if ($isReparse) { $reparseCount++ }
        $items += [pscustomobject][ordered]@{
            Path = $current.ToUpperInvariant()
            Attributes = [int64]$attributes
            IsReparsePoint = $isReparse
        }
        $next = [IO.Path]::GetDirectoryName($current)
        if ([string]::IsNullOrWhiteSpace($next) -or
            [string]::Equals($next, $current, [StringComparison]::OrdinalIgnoreCase)) { break }
        $current = $next.TrimEnd([IO.Path]::DirectorySeparatorChar)
    }
    return [pscustomobject][ordered]@{
        ReparsePointCount = $reparseCount
        BindingToken = Get-CddsiVmResetBindingToken -Value @($items)
    }
}

function Get-CddsiWindowsVmResetDirectoryTreeDigestInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$RootPath)

    $entries = [System.Collections.Generic.List[object]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($RootPath)
    $totalBytes = [int64]0
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        foreach ($path in @([IO.Directory]::EnumerateFileSystemEntries($directory))) {
            if (-not (Test-CddsiVmResetLiveChildPath -Path $path -Root $RootPath)) {
                throw 'OWNED_DIRECTORY_ENUMERATION_ESCAPED_ROOT'
            }
            $attributes = [IO.File]::GetAttributes($path)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'OWNED_DIRECTORY_REPARSE_POINT'
            }
            $relative = $path.Substring($RootPath.TrimEnd('\').Length + 1).Replace('\', '/')
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) {
                $entries.Add([pscustomobject][ordered]@{ Path = $relative; Kind = 'Directory'; Length = 0; Sha256 = $script:CddsiWindowsVmResetNotApplicable })
                $pending.Push($path)
            }
            else {
                $info = [IO.FileInfo]::new($path)
                $totalBytes += $info.Length
                if ($totalBytes -gt 1073741824) { throw 'OWNED_DIRECTORY_BYTE_LIMIT_EXCEEDED' }
                $entries.Add([pscustomobject][ordered]@{ Path = $relative; Kind = 'File'; Length = $info.Length; Sha256 = Get-CddsiWindowsVmResetFileSha256Internal -Path $path })
            }
            if ($entries.Count -gt 10000) { throw 'OWNED_DIRECTORY_ENTRY_LIMIT_EXCEEDED' }
        }
    }
    return Get-CddsiVmResetBindingToken -Value @($entries | Sort-Object Path -CaseSensitive)
}

function New-CddsiWindowsVmResetObservationInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][bool]$Exists,
        [Parameter(Mandatory = $true)][bool]$ExactTargetMatched,
        [Parameter(Mandatory = $true)][bool]$OwnershipMatched,
        [Parameter(Mandatory = $true)][string]$MarkerSha256,
        [Parameter(Mandatory = $true)][string]$PreexistingPathBindingToken,
        [Parameter(Mandatory = $true)][string]$AncestorBindingToken,
        [Parameter(Mandatory = $true)][bool]$TargetIsReparsePoint,
        [Parameter(Mandatory = $true)][int]$AncestorReparsePointCount,
        [Parameter(Mandatory = $true)][bool]$ExistedBeforeOwnerRun,
        [Parameter(Mandatory = $true)]$StatePayload
    )

    return [pscustomobject][ordered]@{
        Availability = 'KNOWN'
        Exists = $Exists
        ExactTargetMatched = $ExactTargetMatched
        OwnershipMatched = $OwnershipMatched
        MarkerSha256 = $MarkerSha256
        PreexistingPathBindingToken = $PreexistingPathBindingToken
        AncestorBindingToken = $AncestorBindingToken
        TargetIsReparsePoint = $TargetIsReparsePoint
        AncestorReparsePointCount = $AncestorReparsePointCount
        ExistedBeforeOwnerRun = $ExistedBeforeOwnerRun
        AtomicIdentityToken = Get-CddsiVmResetBindingToken -Value $StatePayload
        StateDigest = Get-CddsiVmResetBindingToken -Value $StatePayload
    }
}

function Get-CddsiWindowsVmResetResourceObservationInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$ResourceToken
    )

    $bound = Get-CddsiWindowsVmResetAuthorizedResourceInternal -Runtime $Runtime `
        -ResourceToken $ResourceToken
    $ResourceType = [string]$bound.Entry.ResourceType
    $Descriptor = $bound.Binding.TargetDescriptor
    $OwnerRunId = [string]$bound.Entry.OwnerRunId
    if (-not (Test-CddsiVmResetLiveTargetDescriptor -Descriptor $Descriptor `
        -ResourceType $ResourceType -OwnerRunId $OwnerRunId)) {
        throw 'RESOURCE_DESCRIPTOR_UNSAFE'
    }
    switch -CaseSensitive ($ResourceType) {
        'Package' {
            $packages = @(Get-AppxPackage -Name $Descriptor.PackageFullName -ErrorAction Stop |
                Where-Object { $_.PackageFullName -ceq $Descriptor.PackageFullName })
            if ($packages.Count -gt 1) { throw 'PACKAGE_TARGET_AMBIGUOUS' }
            $exists = ($packages.Count -eq 1)
            $payload = [pscustomobject][ordered]@{
                ResourceType = $ResourceType
                PackageFullName = $Descriptor.PackageFullName
                Exists = $exists
                PackageFamilyName = $(if ($exists) { [string]$packages[0].PackageFamilyName } else { $script:CddsiWindowsVmResetNotApplicable })
                PublisherId = $(if ($exists) { [string]$packages[0].PublisherId } else { $script:CddsiWindowsVmResetNotApplicable })
            }
            return New-CddsiWindowsVmResetObservationInternal -Exists:$exists `
                -ExactTargetMatched:$true -OwnershipMatched:$true `
                -MarkerSha256 $script:CddsiWindowsVmResetNotApplicable `
                -PreexistingPathBindingToken $script:CddsiWindowsVmResetNotApplicable `
                -AncestorBindingToken $script:CddsiWindowsVmResetNotApplicable `
                -TargetIsReparsePoint:$false -AncestorReparsePointCount 0 `
                -ExistedBeforeOwnerRun:$false -StatePayload $payload
        }
        'HkcuValue' {
            $key = $null
            try {
                $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Descriptor.KeyPath, $false)
                $exists = $false
                $kind = $script:CddsiWindowsVmResetNotApplicable
                $valueDigest = $script:CddsiWindowsVmResetNotApplicable
                if ($null -ne $key) {
                    $exists = @($key.GetValueNames() | Where-Object { $_ -ceq $Descriptor.ValueName }).Count -eq 1
                    if ($exists) {
                        $kind = [string]$key.GetValueKind($Descriptor.ValueName)
                        $value = $key.GetValue($Descriptor.ValueName, $null,
                            [Microsoft.Win32.RegistryValueOptions]::DoNotExpandEnvironmentNames)
                        $valueDigest = Get-CddsiVmResetBindingToken -Value ([pscustomobject][ordered]@{
                            Kind = $kind
                            Value = $value
                        })
                    }
                }
                $payload = [pscustomobject][ordered]@{
                    ResourceType = $ResourceType
                    Hive = 'HKCU'
                    KeyPath = $Descriptor.KeyPath
                    ValueName = $Descriptor.ValueName
                    Exists = $exists
                    ValueKind = $kind
                    ValueDigest = $valueDigest
                }
                return New-CddsiWindowsVmResetObservationInternal -Exists:$exists `
                    -ExactTargetMatched:$true -OwnershipMatched:$true `
                    -MarkerSha256 $script:CddsiWindowsVmResetNotApplicable `
                    -PreexistingPathBindingToken $script:CddsiWindowsVmResetNotApplicable `
                    -AncestorBindingToken $script:CddsiWindowsVmResetNotApplicable `
                    -TargetIsReparsePoint:$false -AncestorReparsePointCount 0 `
                    -ExistedBeforeOwnerRun:$false -StatePayload $payload
            }
            finally { if ($null -ne $key) { $key.Dispose() } }
        }
        'Credential' {
            Initialize-CddsiWindowsVmResetCredentialNativeInternal
            $probe = [CddsiVmResetNativeCredential]::ProbeGeneric($Descriptor.TargetName)
            if ($probe -lt 0) { throw ('CREDENTIAL_PROBE_FAILED_{0}' -f (-1 * $probe)) }
            $exists = ($probe -eq 1)
            $payload = [pscustomobject][ordered]@{
                ResourceType = $ResourceType
                TargetName = $Descriptor.TargetName
                CredentialType = 'Generic'
                Exists = $exists
            }
            return New-CddsiWindowsVmResetObservationInternal -Exists:$exists `
                -ExactTargetMatched:$true -OwnershipMatched:$true `
                -MarkerSha256 $script:CddsiWindowsVmResetNotApplicable `
                -PreexistingPathBindingToken $script:CddsiWindowsVmResetNotApplicable `
                -AncestorBindingToken $script:CddsiWindowsVmResetNotApplicable `
                -TargetIsReparsePoint:$false -AncestorReparsePointCount 0 `
                -ExistedBeforeOwnerRun:$false -StatePayload $payload
        }
        'Checkpoint' {
            $ancestor = Get-CddsiWindowsVmResetAncestorObservationInternal -Path $Descriptor.OwnedRootPath
            $rootExists = [IO.Directory]::Exists($Descriptor.OwnedRootPath)
            $exists = [IO.File]::Exists($Descriptor.Path)
            $targetReparse = $false
            $markerMatches = $false
            $fileMatches = $false
            $actualFileSha = $script:CddsiWindowsVmResetNotApplicable
            if ($rootExists -and (Test-CddsiWindowsVmResetReparseInternal -Path $Descriptor.OwnedRootPath)) {
                throw 'OWNED_ROOT_REPARSE_POINT'
            }
            if ($exists) {
                $targetReparse = Test-CddsiWindowsVmResetReparseInternal -Path $Descriptor.Path
                if ($targetReparse) { throw 'CHECKPOINT_REPARSE_POINT' }
                if (-not [IO.File]::Exists($Descriptor.OwnerMarkerPath)) { throw 'OWNER_MARKER_MISSING' }
                if (Test-CddsiWindowsVmResetReparseInternal -Path $Descriptor.OwnerMarkerPath) { throw 'OWNER_MARKER_REPARSE_POINT' }
                $markerMatches = (Get-CddsiWindowsVmResetFileSha256Internal -Path $Descriptor.OwnerMarkerPath) -ceq $Descriptor.OwnerMarkerSha256
                $actualFileSha = Get-CddsiWindowsVmResetFileSha256Internal -Path $Descriptor.Path
                $fileMatches = $actualFileSha -ceq $Descriptor.ExpectedFileSha256
            }
            else {
                $markerMatches = $true
                $fileMatches = $true
            }
            $ancestorMatches = $ancestor.BindingToken -ceq $Descriptor.AncestorBindingToken
            $exact = ($fileMatches -and $markerMatches -and $ancestorMatches)
            $payload = [pscustomobject][ordered]@{
                ResourceType = $ResourceType
                Path = $Descriptor.Path
                Exists = $exists
                FileSha256 = $actualFileSha
                MarkerSha256 = $Descriptor.OwnerMarkerSha256
                AncestorBindingToken = $ancestor.BindingToken
                TargetIsReparsePoint = $targetReparse
            }
            return New-CddsiWindowsVmResetObservationInternal -Exists:$exists `
                -ExactTargetMatched:$exact -OwnershipMatched:$exact `
                -MarkerSha256 $Descriptor.OwnerMarkerSha256 `
                -PreexistingPathBindingToken $Descriptor.PreexistingPathBindingToken `
                -AncestorBindingToken $ancestor.BindingToken `
                -TargetIsReparsePoint:$targetReparse `
                -AncestorReparsePointCount ([int]$ancestor.ReparsePointCount) `
                -ExistedBeforeOwnerRun:$false -StatePayload $payload
        }
        'OwnerMarkedDirectory' {
            $ancestor = Get-CddsiWindowsVmResetAncestorObservationInternal -Path $Descriptor.Path
            $exists = [IO.Directory]::Exists($Descriptor.Path)
            $targetReparse = $false
            $markerMatches = $false
            $treeDigest = $script:CddsiWindowsVmResetNotApplicable
            if ($exists) {
                $targetReparse = Test-CddsiWindowsVmResetReparseInternal -Path $Descriptor.Path
                if ($targetReparse) { throw 'OWNED_DIRECTORY_REPARSE_POINT' }
                if (-not [IO.File]::Exists($Descriptor.OwnerMarkerPath)) { throw 'OWNER_MARKER_MISSING' }
                if (Test-CddsiWindowsVmResetReparseInternal -Path $Descriptor.OwnerMarkerPath) { throw 'OWNER_MARKER_REPARSE_POINT' }
                $markerMatches = (Get-CddsiWindowsVmResetFileSha256Internal -Path $Descriptor.OwnerMarkerPath) -ceq $Descriptor.OwnerMarkerSha256
                $treeDigest = Get-CddsiWindowsVmResetDirectoryTreeDigestInternal -RootPath $Descriptor.Path
            }
            else { $markerMatches = $true }
            $ancestorMatches = $ancestor.BindingToken -ceq $Descriptor.AncestorBindingToken
            $exact = ($markerMatches -and $ancestorMatches)
            $payload = [pscustomobject][ordered]@{
                ResourceType = $ResourceType
                Path = $Descriptor.Path
                Exists = $exists
                TreeDigest = $treeDigest
                MarkerSha256 = $Descriptor.OwnerMarkerSha256
                AncestorBindingToken = $ancestor.BindingToken
                TargetIsReparsePoint = $targetReparse
            }
            return New-CddsiWindowsVmResetObservationInternal -Exists:$exists `
                -ExactTargetMatched:$exact -OwnershipMatched:$exact `
                -MarkerSha256 $Descriptor.OwnerMarkerSha256 `
                -PreexistingPathBindingToken $Descriptor.PreexistingPathBindingToken `
                -AncestorBindingToken $ancestor.BindingToken `
                -TargetIsReparsePoint:$targetReparse `
                -AncestorReparsePointCount ([int]$ancestor.ReparsePointCount) `
                -ExistedBeforeOwnerRun:$false -StatePayload $payload
        }
        default { throw 'RESOURCE_TYPE_UNAVAILABLE' }
    }
}

function Remove-CddsiWindowsVmResetOwnedDirectoryInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$ResourceToken,
        [Parameter(Mandatory = $true)]$MutationPermit
    )

    if (-not [object]::ReferenceEquals($Runtime.ActiveMutationPermit, $MutationPermit) -or
        -not $MutationPermit.Used -or -not $MutationPermit.DirectoryDeletionActivated -or
        $MutationPermit.ResourceToken -cne $ResourceToken) {
        throw 'OWNED_DIRECTORY_MUTATION_PERMIT_REQUIRED'
    }
    $bound = Get-CddsiWindowsVmResetAuthorizedResourceInternal -Runtime $Runtime `
        -ResourceToken $ResourceToken
    if ($bound.Entry.ResourceType -cne 'OwnerMarkedDirectory' -or
        $bound.Binding.ResourceType -cne 'OwnerMarkedDirectory') {
        throw 'OWNED_DIRECTORY_RESOURCE_BINDING_REQUIRED'
    }
    $RootPath = [string]$bound.Binding.TargetDescriptor.Path

    $directories = [System.Collections.Generic.List[string]]::new()
    $pending = [System.Collections.Generic.Stack[string]]::new()
    $pending.Push($RootPath)
    while ($pending.Count -gt 0) {
        $directory = $pending.Pop()
        $directories.Add($directory)
        foreach ($path in @([IO.Directory]::EnumerateFileSystemEntries($directory))) {
            if (-not (Test-CddsiVmResetLiveChildPath -Path $path -Root $RootPath)) {
                throw 'OWNED_DIRECTORY_DELETE_ESCAPED_ROOT'
            }
            $attributes = [IO.File]::GetAttributes($path)
            if (($attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'OWNED_DIRECTORY_DELETE_REPARSE_POINT'
            }
            if (($attributes -band [IO.FileAttributes]::Directory) -ne 0) { $pending.Push($path) }
            else { [IO.File]::Delete($path) }
        }
        if ($directories.Count -gt 10000) { throw 'OWNED_DIRECTORY_DELETE_ENTRY_LIMIT_EXCEEDED' }
    }
    foreach ($directory in @($directories | Sort-Object { $_.Length } -Descending)) {
        [IO.Directory]::Delete($directory, $false)
    }
}

function Invoke-CddsiWindowsVmResetResourceMutationInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$ResourceToken,
        [Parameter(Mandatory = $true)][string]$ExpectedAtomicIdentityToken
    )

    $permit = Assert-CddsiWindowsVmResetActiveMutationPermitInternal -Runtime $Runtime `
        -ResourceToken $ResourceToken `
        -ExpectedAtomicIdentityToken $ExpectedAtomicIdentityToken
    $permit.Used = $true
    $bound = Get-CddsiWindowsVmResetAuthorizedResourceInternal -Runtime $Runtime `
        -ResourceToken $ResourceToken
    $ResourceType = [string]$bound.Entry.ResourceType
    $Descriptor = $bound.Binding.TargetDescriptor
    $OwnerRunId = [string]$bound.Entry.OwnerRunId
    # Third observation occurs inside the fixed mutation primitive. It closes
    # the core-engine-to-primitive gap and binds the mutation to the exact state
    # immediately observed by the engine.
    $current = Get-CddsiWindowsVmResetResourceObservationInternal `
        -Runtime $Runtime -ResourceToken $ResourceToken
    if ($current.Availability -cne 'KNOWN' -or -not $current.ExactTargetMatched -or
        -not $current.OwnershipMatched -or $current.TargetIsReparsePoint -or
        [int]$current.AncestorReparsePointCount -ne 0 -or
        $current.AtomicIdentityToken -cne $ExpectedAtomicIdentityToken) {
        throw 'RESOURCE_TOCTOU_DETECTED'
    }
    if (-not $current.Exists) {
        return [pscustomobject][ordered]@{ MutationAttempted = $false; Changed = $false; Outcome = 'COMPLETED'; FailureCode = '' }
    }
    switch -CaseSensitive ($ResourceType) {
        'Package' {
            Remove-AppxPackage -Package $Descriptor.PackageFullName -Confirm:$false -ErrorAction Stop
            break
        }
        'HkcuValue' {
            $key = $null
            try {
                $key = [Microsoft.Win32.Registry]::CurrentUser.OpenSubKey($Descriptor.KeyPath, $true)
                if ($null -eq $key) { throw 'REGISTRY_KEY_DISAPPEARED' }
                $names = @($key.GetValueNames() | Where-Object { $_ -ceq $Descriptor.ValueName })
                if ($names.Count -ne 1) { throw 'REGISTRY_VALUE_CHANGED' }
                $key.DeleteValue($Descriptor.ValueName, $true)
            }
            finally { if ($null -ne $key) { $key.Dispose() } }
            break
        }
        'Credential' {
            Initialize-CddsiWindowsVmResetCredentialNativeInternal
            $deleted = [CddsiVmResetNativeCredential]::DeleteGeneric($Descriptor.TargetName)
            if ($deleted -ne 1) { throw ('CREDENTIAL_DELETE_FAILED_{0}' -f $deleted) }
            break
        }
        'Checkpoint' {
            [IO.File]::Delete($Descriptor.Path)
            break
        }
        'OwnerMarkedDirectory' {
            $permit.DirectoryDeletionActivated = $true
            Remove-CddsiWindowsVmResetOwnedDirectoryInternal -Runtime $Runtime `
                -ResourceToken $ResourceToken -MutationPermit $permit
            break
        }
        default { throw 'RESOURCE_MUTATION_UNAVAILABLE' }
    }
    return [pscustomobject][ordered]@{ MutationAttempted = $true; Changed = $true; Outcome = 'COMPLETED'; FailureCode = '' }
}

function Invoke-CddsiWindowsVmResetGitVersionInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$TrustPolicy)

    if ((Get-CddsiWindowsVmResetFileSha256Internal -Path $TrustPolicy.GitExecutablePath) -cne
        $TrustPolicy.GitExecutableSha256) { throw 'GIT_EXECUTABLE_HASH_CHANGED' }
    $startInfo = [System.Diagnostics.ProcessStartInfo]::new()
    $startInfo.FileName = $TrustPolicy.GitExecutablePath
    $startInfo.Arguments = '--version'
    $startInfo.UseShellExecute = $false
    $startInfo.CreateNoWindow = $true
    $startInfo.RedirectStandardOutput = $true
    $startInfo.RedirectStandardError = $true
    $process = [System.Diagnostics.Process]::new()
    $process.StartInfo = $startInfo
    try {
        if (-not $process.Start()) { throw 'GIT_VERSION_PROCESS_START_FAILED' }
        if (-not $process.WaitForExit(10000)) {
            try { $process.Kill() } catch {}
            throw 'GIT_VERSION_PROCESS_TIMEOUT'
        }
        $stdout = $process.StandardOutput.ReadToEnd().Trim()
        $stderr = $process.StandardError.ReadToEnd().Trim()
        if ($process.ExitCode -ne 0 -or $stdout -notmatch '^git version [0-9]+\.[0-9]+\.[0-9]+(?:\.[A-Za-z0-9]+)?(?:\.windows\.[0-9]+)?$' -or
            -not [string]::IsNullOrWhiteSpace($stderr)) { throw 'GIT_VERSION_PROCESS_INVALID' }
        return $stdout
    }
    finally { $process.Dispose() }
}

function Get-CddsiWindowsVmResetVmpStateInternal {
    [CmdletBinding()]
    param()

    try {
        $features = @(Get-WindowsOptionalFeature -Online -FeatureName VirtualMachinePlatform -ErrorAction Stop)
        if ($features.Count -ne 1 -or @('Enabled', 'Disabled', 'Enable Pending', 'Disable Pending') -cnotcontains [string]$features[0].State) {
            return [pscustomobject][ordered]@{ Availability = 'UNAVAILABLE'; State = 'UNKNOWN' }
        }
        return [pscustomobject][ordered]@{
            Availability = 'KNOWN'
            State = [string]$features[0].State
        }
    }
    catch { return [pscustomobject][ordered]@{ Availability = 'UNAVAILABLE'; State = 'UNKNOWN' } }
}

function Get-CddsiWindowsVmResetPendingRebootInternal {
    [CmdletBinding()]
    param()

    $base = $null
    $session = $null
    try {
        $base = [Microsoft.Win32.Registry]::LocalMachine
        $cbs = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending', $false)
        $wu = $base.OpenSubKey('SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired', $false)
        $session = $base.OpenSubKey('SYSTEM\CurrentControlSet\Control\Session Manager', $false)
        if ($null -eq $session) { return [pscustomobject][ordered]@{ Availability = 'UNAVAILABLE'; Pending = $null } }
        $pendingRename = @($session.GetValueNames() | Where-Object { $_ -ceq 'PendingFileRenameOperations' }).Count -eq 1
        $pending = ($null -ne $cbs -or $null -ne $wu -or $pendingRename)
        if ($null -ne $cbs) { $cbs.Dispose() }
        if ($null -ne $wu) { $wu.Dispose() }
        return [pscustomobject][ordered]@{ Availability = 'KNOWN'; Pending = $pending }
    }
    catch { return [pscustomobject][ordered]@{ Availability = 'UNAVAILABLE'; Pending = $null } }
    finally { if ($null -ne $session) { $session.Dispose() } }
}

function Get-CddsiWindowsVmResetBaselineDomainInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Domain,
        [Parameter(Mandatory = $true)]$Runtime
    )

    switch -CaseSensitive ($Domain) {
        'OS' {
            $operatingSystems = @(Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop)
            if ($operatingSystems.Count -ne 1) { throw 'BASELINE_OS_UNAVAILABLE' }
            $identity = Get-CddsiWindowsVmResetVmIdentityInternal
            $payload = [pscustomobject][ordered]@{
                Domain = 'OS'
                Version = [string]$operatingSystems[0].Version
                BuildNumber = [string]$operatingSystems[0].BuildNumber
                OsArchitecture = [string]$operatingSystems[0].OSArchitecture
                VmIdentitySha256 = $identity.IdentitySha256
            }
            break
        }
        'AppX' {
            $getCommand = Get-Command -Name Get-AppxPackage -CommandType Cmdlet -ErrorAction Stop
            $removeCommand = Get-Command -Name Remove-AppxPackage -CommandType Cmdlet -ErrorAction Stop
            foreach ($binding in @($Runtime.ResourceBindings | Where-Object ResourceType -CEQ 'Package')) {
                $null = Get-CddsiWindowsVmResetResourceObservationInternal -Runtime $Runtime `
                    -ResourceToken $binding.ResourceToken
            }
            $payload = [pscustomobject][ordered]@{
                Domain = 'AppX'
                GetCommandModule = [string]$getCommand.ModuleName
                GetCommandVersion = [string]$getCommand.Version
                RemoveCommandModule = [string]$removeCommand.ModuleName
                RemoveCommandVersion = [string]$removeCommand.Version
                FrozenTargetDigest = Get-CddsiVmResetBindingToken -Value @($Runtime.ResourceBindings |
                    Where-Object ResourceType -CEQ 'Package' | ForEach-Object TargetBindingToken)
            }
            break
        }
        'Git' {
            $payload = [pscustomobject][ordered]@{
                Domain = 'Git'
                ExecutablePath = $Runtime.TrustPolicy.GitExecutablePath
                ExecutableSha256 = $Runtime.TrustPolicy.GitExecutableSha256
                Version = Invoke-CddsiWindowsVmResetGitVersionInternal -TrustPolicy $Runtime.TrustPolicy
            }
            break
        }
        'VMP' {
            $vmp = Get-CddsiWindowsVmResetVmpStateInternal
            if ($vmp.Availability -cne 'KNOWN') { throw 'BASELINE_VMP_UNAVAILABLE' }
            $payload = [pscustomobject][ordered]@{ Domain = 'VMP'; State = $vmp.State }
            break
        }
        'Registry' {
            $hiveName = [string][Microsoft.Win32.Registry]::CurrentUser.Name
            if ([string]::IsNullOrWhiteSpace($hiveName)) { throw 'BASELINE_REGISTRY_UNAVAILABLE' }
            $payload = [pscustomobject][ordered]@{
                Domain = 'Registry'
                Hive = 'HKCU'
                ApiState = 'AVAILABLE'
                FrozenTargetDigest = Get-CddsiVmResetBindingToken -Value @($Runtime.ResourceBindings |
                    Where-Object ResourceType -CEQ 'HkcuValue' | ForEach-Object TargetBindingToken)
            }
            break
        }
        'Credential' {
            Initialize-CddsiWindowsVmResetCredentialNativeInternal
            foreach ($binding in @($Runtime.ResourceBindings | Where-Object ResourceType -CEQ 'Credential')) {
                $probe = [CddsiVmResetNativeCredential]::ProbeGeneric($binding.TargetDescriptor.TargetName)
                if ($probe -lt 0) { throw 'BASELINE_CREDENTIAL_UNAVAILABLE' }
            }
            $payload = [pscustomobject][ordered]@{
                Domain = 'Credential'
                ApiState = 'AVAILABLE'
                FrozenTargetDigest = Get-CddsiVmResetBindingToken -Value @($Runtime.ResourceBindings |
                    Where-Object ResourceType -CEQ 'Credential' | ForEach-Object TargetBindingToken)
            }
            break
        }
        'Checkpoint' {
            $ancestorTokens = @()
            foreach ($binding in @($Runtime.ResourceBindings | Where-Object ResourceType -CEQ 'Checkpoint')) {
                $ancestor = Get-CddsiWindowsVmResetAncestorObservationInternal -Path $binding.TargetDescriptor.OwnedRootPath
                if ($ancestor.ReparsePointCount -ne 0 -or
                    $ancestor.BindingToken -cne $binding.TargetDescriptor.AncestorBindingToken) {
                    throw 'BASELINE_CHECKPOINT_ANCESTOR_DRIFT'
                }
                $ancestorTokens += $ancestor.BindingToken
            }
            $payload = [pscustomobject][ordered]@{ Domain = 'Checkpoint'; AncestorBindingTokens = @($ancestorTokens) }
            break
        }
        'FileSystem' {
            $ancestorTokens = @()
            foreach ($binding in @($Runtime.ResourceBindings | Where-Object ResourceType -CEQ 'OwnerMarkedDirectory')) {
                $ancestor = Get-CddsiWindowsVmResetAncestorObservationInternal -Path $binding.TargetDescriptor.Path
                if ($ancestor.ReparsePointCount -ne 0 -or
                    $ancestor.BindingToken -cne $binding.TargetDescriptor.AncestorBindingToken) {
                    throw 'BASELINE_FILESYSTEM_ANCESTOR_DRIFT'
                }
                $ancestorTokens += $ancestor.BindingToken
            }
            $payload = [pscustomobject][ordered]@{ Domain = 'FileSystem'; AncestorBindingTokens = @($ancestorTokens) }
            break
        }
        default { throw 'BASELINE_DOMAIN_UNAVAILABLE' }
    }
    return [pscustomobject][ordered]@{
        Availability = 'KNOWN'
        StateDigest = Get-CddsiVmResetBindingToken -Value $payload
    }
}

function Get-CddsiWindowsVmResetFinalStateInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Runtime)

    $vmp = Get-CddsiWindowsVmResetVmpStateInternal
    $reboot = Get-CddsiWindowsVmResetPendingRebootInternal
    $uninstallKnown = $true
    foreach ($binding in @($Runtime.ResourceBindings | Where-Object ResourceType -CEQ 'Package')) {
        try {
            $observation = Get-CddsiWindowsVmResetResourceObservationInternal -Runtime $Runtime `
                -ResourceToken $binding.ResourceToken
            if ($observation.Availability -cne 'KNOWN' -or $observation.Exists) { $uninstallKnown = $false }
        }
        catch { $uninstallKnown = $false }
    }
    $outcomes = @($Runtime.ActionOutcomes)
    $failed = @($outcomes | Where-Object Outcome -CEQ 'FAILED').Count
    $ambiguous = @($outcomes | Where-Object Outcome -CEQ 'AMBIGUOUS').Count
    $compensationKnown = ($failed -eq 0 -and $ambiguous -eq 0 -and
        $outcomes.Count -eq @($Runtime.Plan.Actions).Count)
    return [pscustomobject][ordered]@{
        VmpState = $(if ($vmp.Availability -ceq 'KNOWN') { 'KNOWN' } else { 'UNKNOWN' })
        RebootState = $(if ($reboot.Availability -ceq 'KNOWN' -and -not $reboot.Pending) { 'KNOWN' } else { 'UNKNOWN' })
        UninstallState = $(if ($uninstallKnown) { 'KNOWN' } else { 'UNKNOWN' })
        CompensationState = $(if ($compensationKnown) { 'KNOWN' } else { 'UNKNOWN' })
        CleanupFailureCount = [int]$failed
        UnknownMutationCount = [int]$ambiguous
        UnexpectedLedgerEntryCount = [int]$Runtime.UnexpectedRequestCount
        SecretScanCount = 0
    }
}

function Assert-CddsiWindowsVmResetFactoryCapabilityInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Capability,
        [AllowNull()]$Runtime
    )

    if ($null -eq $Capability) {
        throw 'WINDOWS_VM_RESET_FACTORY_CAPABILITY_REQUIRED'
    }
    $runtimeHandleProperty = $Capability.PSObject.Properties['RuntimeHandle']
    if ($null -eq $runtimeHandleProperty -or
        -not (Test-CddsiCanonicalUuidValue -Value $runtimeHandleProperty.Value) -or
        -not $script:CddsiWindowsVmResetAuthorizedRuntimes.ContainsKey($runtimeHandleProperty.Value)) {
        throw 'WINDOWS_VM_RESET_FACTORY_CAPABILITY_REQUIRED'
    }
    $runtimeHandle = [string]$runtimeHandleProperty.Value
    $runtime = $script:CddsiWindowsVmResetAuthorizedRuntimes[$runtimeHandle]
    if ($runtime.ExecutionKind -cne 'LiveWindows' -or -not $runtime.AuthorizationActivated -or
        -not [object]::ReferenceEquals($runtime.FactoryCapability, $Capability) -or
        ($null -ne $Runtime -and -not [object]::ReferenceEquals($runtime, $Runtime)) -or
        -not $script:CddsiWindowsVmResetConsumedGrantHandles.ContainsKey(
            $runtime.ProvisioningAnchor.OneShotGrantId
        ) -or $script:CddsiWindowsVmResetConsumedGrantHandles[
            $runtime.ProvisioningAnchor.OneShotGrantId
        ] -cne $runtimeHandle) {
        throw 'WINDOWS_VM_RESET_FACTORY_CAPABILITY_INVALID'
    }
    $anchor = Get-CddsiWindowsVmResetProvisioningAnchorInternal
    $now = [DateTimeOffset]::UtcNow
    if ($anchor.AnchorBindingToken -cne $runtime.ProvisioningAnchor.AnchorBindingToken -or
        $now -lt [DateTimeOffset]::Parse($anchor.NotBeforeUtc) -or
        $now -gt [DateTimeOffset]::Parse($anchor.ExpiresAtUtc) -or
        $anchor.ExpectedCycleId -cne $runtime.Plan.CycleId -or
        $anchor.ExpectedResetPolicyDigest -cne $runtime.Policy.ResetPolicyDigest -or
        $anchor.ExpectedPlanBindingToken -cne $runtime.Plan.PlanBindingToken -or
        $anchor.ExpectedOwnershipSetDigest -cne (Get-CddsiVmResetBindingToken -Value @($runtime.OwnershipReceipts)) -or
        $anchor.ExpectedResourceBindingSetDigest -cne (Get-CddsiVmResetBindingToken -Value @($runtime.ResourceBindings)) -or
        $anchor.ExpectedControlAuthenticationDigest -cne $runtime.ControlAuthenticationDigest) {
        throw 'WINDOWS_VM_RESET_ONE_SHOT_GRANT_INVALID'
    }
}

function Get-CddsiWindowsVmResetFactoryCapabilityInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Runtime)

    $property = $Runtime.PSObject.Properties['FactoryCapability']
    if ($null -eq $property) { return $null }
    return $property.Value
}

function Invoke-CddsiWindowsVmResetSystemApiInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$Operation,
        [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Arguments
    )

    if ($Runtime.ExecutionKind -ceq 'Simulation') {
        if ($Runtime.SystemApi.Kind -cne 'FakeWindowsVmResetSystemV1' -or
            $Runtime.SystemApi.Invoke -isnot [scriptblock]) { throw 'FAKE_SYSTEM_API_INVALID' }
        $fakeArguments = $Arguments
        if ($Operation -ceq 'InspectResource' -or $Operation -ceq 'MutateResource') {
            $bound = Get-CddsiWindowsVmResetRuntimeEntryInternal -Runtime $Runtime `
                -ResourceToken $Arguments.ResourceToken
            $fakeArguments = [ordered]@{
                ResourceType = $bound.Entry.ResourceType
                Descriptor = $bound.Binding.TargetDescriptor
                OwnerRunId = $bound.Entry.OwnerRunId
            }
            if ($Operation -ceq 'MutateResource') {
                $fakeArguments.ExpectedAtomicIdentityToken = $Arguments.ExpectedAtomicIdentityToken
            }
        }
        return & $Runtime.SystemApi.Invoke $Operation $fakeArguments
    }
    if ($Runtime.ExecutionKind -cne 'LiveWindows' -or
        $Runtime.SystemApi.Kind -cne 'WindowsVmResetNativeV2') {
        throw 'WINDOWS_SYSTEM_API_INVALID'
    }
    $factoryCapability = Get-CddsiWindowsVmResetFactoryCapabilityInternal -Runtime $Runtime
    Assert-CddsiWindowsVmResetFactoryCapabilityInternal -Capability $factoryCapability -Runtime $Runtime
    switch -CaseSensitive ($Operation) {
        'GetUtcNow' { return [DateTimeOffset]::UtcNow.ToString('o') }
        'GetVmIdentity' { return Get-CddsiWindowsVmResetVmIdentityInternal }
        'CaptureBaselineDomain' {
            return Get-CddsiWindowsVmResetBaselineDomainInternal -Domain $Arguments.Domain -Runtime $Runtime
        }
        'InspectResource' {
            if (-not (Test-CddsiWindowsVmResetExactMapInternal -Value $Arguments `
                -Expected @('ResourceToken'))) { throw 'WINDOWS_INSPECTION_ARGUMENTS_INVALID' }
            return Get-CddsiWindowsVmResetResourceObservationInternal -Runtime $Runtime `
                -ResourceToken $Arguments.ResourceToken
        }
        'MutateResource' {
            if (-not (Test-CddsiWindowsVmResetExactMapInternal -Value $Arguments `
                -Expected @('ResourceToken', 'ExpectedAtomicIdentityToken'))) {
                throw 'WINDOWS_MUTATION_ARGUMENTS_INVALID'
            }
            return Invoke-CddsiWindowsVmResetResourceMutationInternal -Runtime $Runtime `
                -ResourceToken $Arguments.ResourceToken `
                -ExpectedAtomicIdentityToken $Arguments.ExpectedAtomicIdentityToken
        }
        'InspectFinalState' { return Get-CddsiWindowsVmResetFinalStateInternal -Runtime $Runtime }
        default { throw 'WINDOWS_SYSTEM_OPERATION_UNAVAILABLE' }
    }
}

function Get-CddsiWindowsVmResetRuntimeEntryInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$ResourceToken
    )

    $entries = @($Runtime.Policy.AllowList | Where-Object ResourceToken -CEQ $ResourceToken)
    $bindings = @($Runtime.ResourceBindings | Where-Object ResourceToken -CEQ $ResourceToken)
    $receipts = @($Runtime.OwnershipReceipts | Where-Object ResourceToken -CEQ $ResourceToken)
    if ($entries.Count -ne 1 -or $bindings.Count -ne 1 -or $receipts.Count -ne 1) {
        throw 'RUNTIME_RESOURCE_BINDING_MISSING'
    }
    return [pscustomobject][ordered]@{
        Entry = $entries[0]
        Binding = $bindings[0]
        OwnershipReceipt = $receipts[0]
    }
}

function Get-CddsiWindowsVmResetAuthorizedResourceInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$ResourceToken
    )

    if ($Runtime.ExecutionKind -cne 'LiveWindows') {
        throw 'WINDOWS_VM_RESET_LIVE_RUNTIME_REQUIRED'
    }
    $factoryCapability = Get-CddsiWindowsVmResetFactoryCapabilityInternal -Runtime $Runtime
    Assert-CddsiWindowsVmResetFactoryCapabilityInternal -Capability $factoryCapability -Runtime $Runtime
    $bound = Get-CddsiWindowsVmResetRuntimeEntryInternal -Runtime $Runtime `
        -ResourceToken $ResourceToken
    if ($bound.Entry.ResourceToken -cne $ResourceToken -or
        $bound.Binding.ResourceToken -cne $ResourceToken -or
        $bound.OwnershipReceipt.ResourceToken -cne $ResourceToken -or
        $bound.Entry.ResourceType -cne $bound.Binding.ResourceType -or
        $bound.Entry.OwnerRunId -cne $bound.Binding.OwnerRunId -or
        $bound.Entry.OwnerRunId -cne $bound.OwnershipReceipt.OwnerRunId -or
        $bound.Entry.OwnershipReceiptBindingToken -cne
            $bound.OwnershipReceipt.ReceiptBindingToken -or
        -not (Test-CddsiVmResetOwnershipReceipt -Receipt $bound.OwnershipReceipt `
            -AllowListEntry $bound.Entry) -or
        -not (Test-CddsiVmResetLiveResourceBinding -Binding $bound.Binding `
            -AllowListEntry $bound.Entry)) {
        throw 'WINDOWS_VM_RESET_AUTHORIZED_RESOURCE_INVALID'
    }
    return $bound
}

function Assert-CddsiWindowsVmResetActiveMutationPermitInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)][string]$ResourceToken,
        [Parameter(Mandatory = $true)][string]$ExpectedAtomicIdentityToken
    )

    $permit = $Runtime.ActiveMutationPermit
    if ($null -eq $permit -or $permit.Used -isnot [bool] -or $permit.Used -or
        $permit.DirectoryDeletionActivated -isnot [bool] -or
        $permit.DirectoryDeletionActivated -or
        $permit.ResourceToken -cne $ResourceToken -or
        $permit.ExpectedAtomicIdentityToken -cne $ExpectedAtomicIdentityToken -or
        [int]$permit.Sequence -ne [int]$Runtime.NextActionSequence -or
        $permit.PermitBindingToken -cne (Get-CddsiVmResetBindingToken -Value (
            [pscustomobject][ordered]@{
                RuntimePermitSecret = $Runtime.MutationPermitSecret
                ResourceToken = $ResourceToken
                ExpectedAtomicIdentityToken = $ExpectedAtomicIdentityToken
                Sequence = [int]$permit.Sequence
                RequestBindingToken = $permit.RequestBindingToken
            }
        ))) {
        throw 'WINDOWS_VM_RESET_ACTIVE_MUTATION_PERMIT_REQUIRED'
    }
    return $permit
}

function Test-CddsiWindowsVmResetExactMapInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Value,
        [Parameter(Mandatory = $true)][string[]]$Expected
    )

    if ($Value -isnot [System.Collections.IDictionary]) { return $false }
    $actualNames = @($Value.Keys | ForEach-Object { [string]$_ } | Sort-Object)
    $expectedNames = @($Expected | Sort-Object)
    return ($actualNames.Count -eq $expectedNames.Count -and
        ($actualNames -join "`n") -ceq ($expectedNames -join "`n"))
}

function Test-CddsiWindowsVmResetRequestInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Request)

    if (-not (Test-CddsiExactPropertySet -InputObject $Request -Expected @(
        'SchemaVersion', 'ContractVersion', 'Provider', 'Operation',
        'ResourceToken', 'Arguments', 'RequestBindingToken'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $Request.SchemaVersion) -or
        $Request.ContractVersion -cne 'cddsi-vm-reset-provider-request-v1' -or
        $Request.Provider -isnot [string] -or $Request.Operation -isnot [string] -or
        $Request.ResourceToken -isnot [string] -or
        $Request.Arguments -isnot [System.Collections.IDictionary] -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Request.RequestBindingToken)) {
        return $false
    }
    $payload = [pscustomobject][ordered]@{
        SchemaVersion = $Request.SchemaVersion
        ContractVersion = $Request.ContractVersion
        Provider = $Request.Provider
        Operation = $Request.Operation
        ResourceToken = $Request.ResourceToken
        Arguments = $Request.Arguments
    }
    return ($Request.RequestBindingToken -ceq (Get-CddsiVmResetBindingToken -Value $payload))
}

function Invoke-CddsiWindowsVmResetAttestVmInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    if ($Runtime.Attested -or $Request.ResourceToken -cne '<VM_RESET_ENVIRONMENT:VM_ACCEPTANCE>' -or
        -not (Test-CddsiWindowsVmResetExactMapInternal -Value $Request.Arguments -Expected @(
            'RunId', 'VmIdentity', 'ImageSha256', 'ResetPolicyDigest',
            'PlanBindingToken', 'PrincipalRole'
        )) -or $Request.Arguments.VmIdentity -cne $Runtime.Policy.VmIdentity -or
        $Request.Arguments.ImageSha256 -cne $Runtime.Policy.ImageSha256 -or
        $Request.Arguments.ResetPolicyDigest -cne $Runtime.Policy.ResetPolicyDigest -or
        $Request.Arguments.PlanBindingToken -cne $Runtime.Plan.PlanBindingToken -or
        $Request.Arguments.PrincipalRole -cne 'VmTester') {
        throw 'ENVIRONMENT_ATTESTATION_REQUEST_INVALID'
    }
    $identity = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation GetVmIdentity -Arguments ([ordered]@{})
    if ($identity.IdentitySha256 -cne $Runtime.TrustPolicy.DisposableVmIdentitySha256 -or
        $identity.Manufacturer -cne $Runtime.TrustPolicy.ExpectedVmManufacturer -or
        $identity.Model -cne $Runtime.TrustPolicy.ExpectedVmModel) {
        throw 'DISPOSABLE_VM_IDENTITY_MISMATCH'
    }
    $attestedAt = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation GetUtcNow -Arguments ([ordered]@{})
    $payload = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-environment-attestation-v2'
        EnvironmentTier = 'VmAcceptance'
        VmIdentity = $Runtime.Policy.VmIdentity
        ImageSha256 = $Runtime.Policy.ImageSha256
        PrincipalRole = 'VmTester'
        IsCi = $false
        HostSystem = 'Windows'
        ProviderKind = 'VmResetLive'
        DisposableVmIdentitySha256 = $identity.IdentitySha256
        DeviceAttestationPublicKeySha256 = $Runtime.Signer.PublicKeySha256
        AttestedAtUtc = $attestedAt
        ProviderRequestBindingToken = $Request.RequestBindingToken
    }
    $digest = Get-CddsiVmResetBindingToken -Value $payload
    $signature = Invoke-CddsiWindowsVmResetDeviceSignInternal -Signer $Runtime.Signer `
        -DigestSha256 $digest -Simulation:($Runtime.ExecutionKind -ceq 'Simulation')
    $Runtime.Attested = $true
    return [pscustomobject][ordered]@{
        SchemaVersion = $payload.SchemaVersion
        ContractVersion = $payload.ContractVersion
        EnvironmentTier = $payload.EnvironmentTier
        VmIdentity = $payload.VmIdentity
        ImageSha256 = $payload.ImageSha256
        PrincipalRole = $payload.PrincipalRole
        IsCi = $payload.IsCi
        HostSystem = $payload.HostSystem
        ProviderKind = $payload.ProviderKind
        DisposableVmIdentitySha256 = $payload.DisposableVmIdentitySha256
        DeviceAttestationPublicKeySha256 = $payload.DeviceAttestationPublicKeySha256
        AttestedAtUtc = $payload.AttestedAtUtc
        ProviderRequestBindingToken = $payload.ProviderRequestBindingToken
        AttestationPayloadSha256 = $digest
        DeviceSignatureAlgorithm = 'ECDSA_P256_SHA256'
        DeviceSignatureBase64 = $signature
        EvidenceDigest = $digest
    }
}

function Invoke-CddsiWindowsVmResetCaptureBaselineInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    if (-not $Runtime.Attested -or -not (Test-CddsiWindowsVmResetExactMapInternal -Value $Request.Arguments -Expected @(
        'Phase', 'ResetPolicyDigest', 'PlanBindingToken'
    )) -or @('Before', 'After') -cnotcontains $Request.Arguments.Phase -or
        $Request.Arguments.ResetPolicyDigest -cne $Runtime.Policy.ResetPolicyDigest -or
        $Request.Arguments.PlanBindingToken -cne $Runtime.Plan.PlanBindingToken -or
        $Request.ResourceToken -cne ('<VM_RESET_BASELINE:{0}>' -f $Request.Arguments.Phase.ToUpperInvariant())) {
        throw 'BASELINE_REQUEST_INVALID'
    }
    if ($Request.Arguments.Phase -ceq 'Before') {
        if ($Runtime.BaselineBeforeCaptured) { throw 'BASELINE_BEFORE_DUPLICATED' }
    }
    elseif (-not $Runtime.BaselineBeforeCaptured -or
        $Runtime.NextActionSequence -ne (@($Runtime.Plan.Actions).Count + 1)) {
        throw 'BASELINE_AFTER_OUT_OF_SEQUENCE'
    }
    $observations = @()
    foreach ($specification in $script:CddsiWindowsVmResetBaselineSpecifications) {
        $domain = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
            -Operation CaptureBaselineDomain -Arguments ([ordered]@{ Domain = $specification.Domain })
        if ($null -eq $domain -or $domain.Availability -cne 'KNOWN' -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $domain.StateDigest)) {
            throw ('BASELINE_DOMAIN_UNAVAILABLE_{0}' -f $specification.Domain.ToUpperInvariant())
        }
        $observations += [pscustomobject][ordered]@{
            Sequence = [int]$specification.Sequence
            Domain = $specification.Domain
            Provider = $specification.Provider
            ResourceToken = $specification.ResourceToken
            StateDigest = $domain.StateDigest
        }
    }
    $capturedAt = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation GetUtcNow -Arguments ([ordered]@{})
    $baseline = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-baseline-v1'
        VmIdentity = $Runtime.Policy.VmIdentity
        ImageSha256 = $Runtime.Policy.ImageSha256
        CapturedAtUtc = $capturedAt
        Observations = @($observations)
        BaselineDigest = ''
    }
    $baseline.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $baseline
    if ($baseline.BaselineDigest -cne $Runtime.Policy.ExpectedBaselineDigest) {
        throw 'BASELINE_DIGEST_DRIFT'
    }
    if ($Request.Arguments.Phase -ceq 'Before') { $Runtime.BaselineBeforeCaptured = $true }
    else { $Runtime.BaselineAfterCaptured = $true }
    return $baseline
}

function Invoke-CddsiWindowsVmResetPreflightInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    if (-not $Runtime.BaselineBeforeCaptured -or $Runtime.NextActionSequence -ne 1) {
        throw 'RESOURCE_PREFLIGHT_OUT_OF_SEQUENCE'
    }
    $bound = Get-CddsiWindowsVmResetRuntimeEntryInternal -Runtime $Runtime -ResourceToken $Request.ResourceToken
    $entry = $bound.Entry
    $binding = $bound.Binding
    if ($Request.Provider -cne $entry.Provider -or $Request.Operation -cne 'ValidateExactTarget' -or
        -not (Test-CddsiWindowsVmResetExactMapInternal -Value $Request.Arguments -Expected @(
            'PlanBindingToken', 'Sequence', 'OwnershipReceiptBindingToken',
            'TargetBindingToken', 'TargetDescriptor'
        )) -or $Request.Arguments.PlanBindingToken -cne $Runtime.Plan.PlanBindingToken -or
        [int]$Request.Arguments.Sequence -ne [int]$entry.Sequence -or
        $Request.Arguments.OwnershipReceiptBindingToken -cne $entry.OwnershipReceiptBindingToken -or
        $Request.Arguments.TargetBindingToken -cne $binding.TargetBindingToken -or
        (Get-CddsiVmResetBindingToken -Value $Request.Arguments.TargetDescriptor) -cne
            (Get-CddsiVmResetBindingToken -Value $binding.TargetDescriptor) -or
        $Runtime.PreflightByToken.ContainsKey($entry.ResourceToken)) {
        throw 'RESOURCE_PREFLIGHT_REQUEST_INVALID'
    }
    $observed = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation InspectResource -Arguments ([ordered]@{
            ResourceToken = $entry.ResourceToken
        })
    if ($observed.Availability -cne 'KNOWN' -or -not $observed.ExactTargetMatched -or
        -not $observed.OwnershipMatched -or $observed.TargetIsReparsePoint -or
        [int]$observed.AncestorReparsePointCount -ne 0 -or $observed.ExistedBeforeOwnerRun) {
        throw 'RESOURCE_PREFLIGHT_UNSAFE'
    }
    $fields = [ordered]@{
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
        Exists = [bool]$observed.Exists
        ExactTargetMatched = [bool]$observed.ExactTargetMatched
        OwnershipMatched = [bool]$observed.OwnershipMatched
        MarkerSha256 = $observed.MarkerSha256
        PreexistingPathBindingToken = $observed.PreexistingPathBindingToken
        AncestorBindingToken = $observed.AncestorBindingToken
        TargetIsReparsePoint = [bool]$observed.TargetIsReparsePoint
        AncestorReparsePointCount = [int]$observed.AncestorReparsePointCount
        ExistedBeforeOwnerRun = [bool]$observed.ExistedBeforeOwnerRun
    }
    $evidence = [pscustomobject][ordered]@{}
    foreach ($name in $fields.Keys) { Add-Member -InputObject $evidence -NotePropertyName $name -NotePropertyValue $fields[$name] }
    Add-Member -InputObject $evidence -NotePropertyName EvidenceDigest `
        -NotePropertyValue (Get-CddsiVmResetBindingToken -Value $evidence)
    $Runtime.PreflightByToken[$entry.ResourceToken] = [pscustomobject][ordered]@{
        Evidence = $evidence
        AtomicIdentityToken = $observed.AtomicIdentityToken
        StateDigest = $observed.StateDigest
    }
    return $evidence
}

function New-CddsiWindowsVmResetActionResultInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request,
        [Parameter(Mandatory = $true)]$Action,
        [Parameter(Mandatory = $true)]$Binding,
        [Parameter(Mandatory = $true)]$Initial,
        [Parameter(Mandatory = $true)]$Immediate,
        [Parameter(Mandatory = $true)]$Postcondition,
        [Parameter(Mandatory = $true)][bool]$AtomicPreconditionValidated,
        [Parameter(Mandatory = $true)][ValidateSet('COMPLETED', 'FAILED', 'AMBIGUOUS')][string]$Outcome,
        [Parameter(Mandatory = $true)][bool]$Changed,
        [Parameter(Mandatory = $true)][AllowEmptyString()][string]$FailureCode,
        [Parameter(Mandatory = $true)][string]$StartedAtUtc,
        [Parameter(Mandatory = $true)][string]$CompletedAtUtc
    )

    $immediateDigest = Get-CddsiVmResetBindingToken -Value $Immediate
    $postFields = [ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-provider-action-result-v2'
        ProviderRequestBindingToken = $Request.RequestBindingToken
        TargetBindingToken = $Binding.TargetBindingToken
        InitialPreflightEvidenceDigest = $Initial.Evidence.EvidenceDigest
        ImmediatePreflightEvidenceDigest = $immediateDigest
        AtomicPreconditionValidated = $AtomicPreconditionValidated
        ExactTargetMatched = [bool]$Postcondition.ExactTargetMatched
        OwnershipMatched = [bool]$Postcondition.OwnershipMatched
        TargetWasReparsePoint = [bool]$Postcondition.TargetIsReparsePoint
        AncestorReparsePointCount = [int]$Postcondition.AncestorReparsePointCount
        ExactTargetAbsentAfter = (-not [bool]$Postcondition.Exists)
        Outcome = $Outcome
        Changed = $Changed
        FailureCode = $FailureCode
    }
    $postPayload = [pscustomobject][ordered]@{}
    foreach ($name in $postFields.Keys) { Add-Member -InputObject $postPayload -NotePropertyName $name -NotePropertyValue $postFields[$name] }
    $postDigest = Get-CddsiVmResetBindingToken -Value $postPayload
    $receiptPayload = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-action-receipt-v1'
        CycleId = $Runtime.Plan.CycleId
        PlanBindingToken = $Runtime.Plan.PlanBindingToken
        Sequence = [int]$Action.Sequence
        ResourceId = $Action.ResourceId
        ResourceType = $Action.ResourceType
        Provider = $Action.Provider
        Operation = $Action.Operation
        ResourceToken = $Action.ResourceToken
        OwnershipReceiptBindingToken = $Action.OwnershipReceiptBindingToken
        ExecutionMode = 'Live'
        Outcome = $Outcome
        Changed = $Changed
        FailureCode = $FailureCode
        ProviderEvidenceDigest = $postDigest
        StartedAtUtc = $StartedAtUtc
        CompletedAtUtc = $CompletedAtUtc
    }
    $receipt = [pscustomobject][ordered]@{}
    foreach ($name in $receiptPayload.PSObject.Properties.Name) {
        Add-Member -InputObject $receipt -NotePropertyName $name -NotePropertyValue $receiptPayload.$name
    }
    Add-Member -InputObject $receipt -NotePropertyName ReceiptBindingToken `
        -NotePropertyValue (Get-CddsiVmResetBindingToken -Value $receiptPayload)
    $resultPayload = [pscustomobject][ordered]@{
        Postcondition = $postPayload
        PostconditionEvidenceDigest = $postDigest
        ActionReceipt = $receipt
    }
    $resultDigest = Get-CddsiVmResetBindingToken -Value $resultPayload
    $signedReceiptDigest = Get-CddsiVmResetBindingToken -Value ([pscustomobject][ordered]@{
        ProviderRequestBindingToken = $Request.RequestBindingToken
        TargetBindingToken = $Binding.TargetBindingToken
        InitialPreflightEvidenceDigest = $Initial.Evidence.EvidenceDigest
        ImmediatePreflightEvidenceDigest = $immediateDigest
        PostconditionEvidenceDigest = $postDigest
        ReceiptBindingToken = $receipt.ReceiptBindingToken
        Outcome = $Outcome
        Changed = $Changed
    })
    $signature = Invoke-CddsiWindowsVmResetDeviceSignInternal -Signer $Runtime.Signer `
        -DigestSha256 $signedReceiptDigest -Simulation:($Runtime.ExecutionKind -ceq 'Simulation')
    return [pscustomobject][ordered]@{
        SchemaVersion = $postFields.SchemaVersion
        ContractVersion = $postFields.ContractVersion
        ProviderRequestBindingToken = $postFields.ProviderRequestBindingToken
        TargetBindingToken = $postFields.TargetBindingToken
        InitialPreflightEvidenceDigest = $postFields.InitialPreflightEvidenceDigest
        ImmediatePreflightEvidenceDigest = $postFields.ImmediatePreflightEvidenceDigest
        AtomicPreconditionValidated = $postFields.AtomicPreconditionValidated
        ExactTargetMatched = $postFields.ExactTargetMatched
        OwnershipMatched = $postFields.OwnershipMatched
        TargetWasReparsePoint = $postFields.TargetWasReparsePoint
        AncestorReparsePointCount = $postFields.AncestorReparsePointCount
        ExactTargetAbsentAfter = $postFields.ExactTargetAbsentAfter
        Outcome = $postFields.Outcome
        Changed = $postFields.Changed
        FailureCode = $postFields.FailureCode
        PostconditionEvidenceDigest = $postDigest
        ActionReceipt = $receipt
        SignedReceiptDigest = $signedReceiptDigest
        ReceiptSignerPublicKeySha256 = $Runtime.Signer.PublicKeySha256
        ReceiptSignatureAlgorithm = 'ECDSA_P256_SHA256'
        ReceiptSignatureBase64 = $signature
        ResultBindingToken = $resultDigest
    }
}

function Invoke-CddsiWindowsVmResetMutationInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    $sequence = [int]$Request.Arguments.Sequence
    if ($sequence -ne [int]$Runtime.NextActionSequence) { throw 'MUTATION_SEQUENCE_INVALID' }
    $actions = @($Runtime.Plan.Actions)
    if ($sequence -lt 1 -or $sequence -gt $actions.Count) { throw 'MUTATION_SEQUENCE_OUT_OF_RANGE' }
    $action = $actions[$sequence - 1]
    $bound = Get-CddsiWindowsVmResetRuntimeEntryInternal -Runtime $Runtime -ResourceToken $Request.ResourceToken
    $entry = $bound.Entry
    $binding = $bound.Binding
    if ($Request.Provider -cne $action.Provider -or $Request.Operation -cne $action.Operation -or
        -not (Test-CddsiWindowsVmResetExactMapInternal -Value $Request.Arguments -Expected @(
            'Purpose', 'PlanBindingToken', 'Sequence', 'ResourceId', 'ResourceType',
            'OwnershipReceiptBindingToken', 'TargetBindingToken', 'TargetDescriptor',
            'PreflightEvidenceDigest', 'RequireAtomicTargetRevalidation'
        )) -or $Request.Arguments.Purpose -cne 'VmResetLiveMutation' -or
        $Request.Arguments.PlanBindingToken -cne $Runtime.Plan.PlanBindingToken -or
        $Request.Arguments.ResourceId -cne $action.ResourceId -or
        $Request.Arguments.ResourceType -cne $action.ResourceType -or
        $Request.Arguments.OwnershipReceiptBindingToken -cne $action.OwnershipReceiptBindingToken -or
        $Request.Arguments.TargetBindingToken -cne $binding.TargetBindingToken -or
        (Get-CddsiVmResetBindingToken -Value $Request.Arguments.TargetDescriptor) -cne
            (Get-CddsiVmResetBindingToken -Value $binding.TargetDescriptor) -or
        $Request.Arguments.RequireAtomicTargetRevalidation -isnot [bool] -or
        -not $Request.Arguments.RequireAtomicTargetRevalidation -or
        -not $Runtime.PreflightByToken.ContainsKey($action.ResourceToken)) {
        throw 'MUTATION_REQUEST_INVALID'
    }
    $initial = $Runtime.PreflightByToken[$action.ResourceToken]
    if ($Request.Arguments.PreflightEvidenceDigest -cne $initial.Evidence.EvidenceDigest) {
        throw 'MUTATION_PREFLIGHT_BINDING_MISMATCH'
    }
    $started = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation GetUtcNow -Arguments ([ordered]@{})
    $atomicValidated = $false
    $failureCode = ''
    $outcome = 'FAILED'
    $changed = $false
    $immediate = $null
    $post = $null
    try {
        $immediate = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
            -Operation InspectResource -Arguments ([ordered]@{
                ResourceToken = $entry.ResourceToken
            })
        $atomicValidated = ($immediate.Availability -ceq 'KNOWN' -and
            $immediate.ExactTargetMatched -and $immediate.OwnershipMatched -and
            -not $immediate.TargetIsReparsePoint -and
            [int]$immediate.AncestorReparsePointCount -eq 0 -and
            -not $immediate.ExistedBeforeOwnerRun -and
            $immediate.AtomicIdentityToken -ceq $initial.AtomicIdentityToken -and
            $immediate.StateDigest -ceq $initial.StateDigest)
        if (-not $atomicValidated) {
            $failureCode = 'RESOURCE_TOCTOU_DETECTED'
            $post = $immediate
        }
        else {
            $permitFields = [pscustomobject][ordered]@{
                RuntimePermitSecret = $Runtime.MutationPermitSecret
                ResourceToken = $entry.ResourceToken
                ExpectedAtomicIdentityToken = $immediate.AtomicIdentityToken
                Sequence = $sequence
                RequestBindingToken = $Request.RequestBindingToken
            }
            $Runtime.ActiveMutationPermit = [pscustomobject][ordered]@{
                ResourceToken = $entry.ResourceToken
                ExpectedAtomicIdentityToken = $immediate.AtomicIdentityToken
                Sequence = $sequence
                RequestBindingToken = $Request.RequestBindingToken
                PermitBindingToken = Get-CddsiVmResetBindingToken -Value $permitFields
                Used = $false
                DirectoryDeletionActivated = $false
            }
            try {
                $mutation = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
                    -Operation MutateResource -Arguments ([ordered]@{
                        ResourceToken = $entry.ResourceToken
                        ExpectedAtomicIdentityToken = $immediate.AtomicIdentityToken
                    })
            }
            finally { $Runtime.ActiveMutationPermit = $null }
            $post = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
                -Operation InspectResource -Arguments ([ordered]@{
                    ResourceToken = $entry.ResourceToken
                })
            if ($mutation.Outcome -ceq 'COMPLETED' -and $post.Availability -ceq 'KNOWN' -and
                $post.ExactTargetMatched -and $post.OwnershipMatched -and
                -not $post.TargetIsReparsePoint -and
                [int]$post.AncestorReparsePointCount -eq 0 -and -not $post.Exists) {
                $outcome = 'COMPLETED'
                $changed = [bool]$mutation.Changed
            }
            else {
                $outcome = 'AMBIGUOUS'
                $failureCode = 'POSTCONDITION_UNPROVEN'
                $changed = ([bool]$initial.Evidence.Exists -and $post.Availability -ceq 'KNOWN' -and -not $post.Exists)
            }
        }
    }
    catch {
        $outcome = 'AMBIGUOUS'
        $failureCode = 'MUTATION_STATE_AMBIGUOUS'
        try {
            $post = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
                -Operation InspectResource -Arguments ([ordered]@{
                    ResourceToken = $entry.ResourceToken
                })
            $changed = ([bool]$initial.Evidence.Exists -and $post.Availability -ceq 'KNOWN' -and -not $post.Exists)
        }
        catch { $post = $null }
    }
    if ($null -eq $immediate) {
        $immediate = [pscustomobject][ordered]@{
            Availability = 'UNAVAILABLE'; Exists = $true; ExactTargetMatched = $false
            OwnershipMatched = $false; MarkerSha256 = $script:CddsiWindowsVmResetNotApplicable
            PreexistingPathBindingToken = $script:CddsiWindowsVmResetNotApplicable
            AncestorBindingToken = $script:CddsiWindowsVmResetNotApplicable
            TargetIsReparsePoint = $false; AncestorReparsePointCount = 0
            ExistedBeforeOwnerRun = $false; AtomicIdentityToken = ('0' * 64); StateDigest = ('0' * 64)
        }
    }
    if ($null -eq $post) {
        $post = [pscustomobject][ordered]@{
            Availability = 'UNAVAILABLE'; Exists = $true; ExactTargetMatched = $false
            OwnershipMatched = $false; MarkerSha256 = $script:CddsiWindowsVmResetNotApplicable
            PreexistingPathBindingToken = $script:CddsiWindowsVmResetNotApplicable
            AncestorBindingToken = $script:CddsiWindowsVmResetNotApplicable
            TargetIsReparsePoint = $false; AncestorReparsePointCount = 0
            ExistedBeforeOwnerRun = $false; AtomicIdentityToken = ('0' * 64); StateDigest = ('0' * 64)
        }
    }
    $completed = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation GetUtcNow -Arguments ([ordered]@{})
    $result = New-CddsiWindowsVmResetActionResultInternal -Runtime $Runtime -Request $Request `
        -Action $action -Binding $binding -Initial $initial -Immediate $immediate `
        -Postcondition $post -AtomicPreconditionValidated:$atomicValidated `
        -Outcome $outcome -Changed:$changed -FailureCode $failureCode `
        -StartedAtUtc $started -CompletedAtUtc $completed
    $Runtime.ActionOutcomes.Add([pscustomobject][ordered]@{
        Sequence = $sequence
        ResourceToken = $action.ResourceToken
        Outcome = $outcome
        Changed = $changed
    }) | Out-Null
    $Runtime.NextActionSequence = $sequence + 1
    return $result
}

function Invoke-CddsiWindowsVmResetInspectFinalStateInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    if (-not $Runtime.BaselineAfterCaptured -or $Request.ResourceToken -cne '<VM_RESET_STATE:FINAL>' -or
        -not (Test-CddsiWindowsVmResetExactMapInternal -Value $Request.Arguments -Expected @(
            'ResetPolicyDigest', 'PlanBindingToken'
        )) -or $Request.Arguments.ResetPolicyDigest -cne $Runtime.Policy.ResetPolicyDigest -or
        $Request.Arguments.PlanBindingToken -cne $Runtime.Plan.PlanBindingToken) {
        throw 'FINAL_STATE_REQUEST_INVALID'
    }
    $state = Invoke-CddsiWindowsVmResetSystemApiInternal -Runtime $Runtime `
        -Operation InspectFinalState -Arguments ([ordered]@{})
    $payload = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-vm-reset-final-state-v1'
        VmpState = $(if (@('KNOWN', 'UNKNOWN') -ccontains $state.VmpState) { $state.VmpState } else { 'UNKNOWN' })
        RebootState = $(if (@('KNOWN', 'UNKNOWN') -ccontains $state.RebootState) { $state.RebootState } else { 'UNKNOWN' })
        UninstallState = $(if (@('KNOWN', 'UNKNOWN') -ccontains $state.UninstallState) { $state.UninstallState } else { 'UNKNOWN' })
        CompensationState = $(if (@('KNOWN', 'UNKNOWN') -ccontains $state.CompensationState) { $state.CompensationState } else { 'UNKNOWN' })
        CleanupFailureCount = [int]$state.CleanupFailureCount
        UnknownMutationCount = [int]$state.UnknownMutationCount
        UnexpectedLedgerEntryCount = [int]$state.UnexpectedLedgerEntryCount
        SecretScanCount = [int]$state.SecretScanCount
    }
    $result = [pscustomobject][ordered]@{}
    foreach ($name in $payload.PSObject.Properties.Name) {
        Add-Member -InputObject $result -NotePropertyName $name -NotePropertyValue $payload.$name
    }
    Add-Member -InputObject $result -NotePropertyName EvidenceDigest `
        -NotePropertyValue (Get-CddsiVmResetBindingToken -Value $payload)
    $Runtime.FinalStateInspected = $true
    return $result
}

function Invoke-CddsiWindowsVmResetProviderRequestCoreInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    if (-not (Test-CddsiWindowsVmResetRequestInternal -Request $Request)) {
        $Runtime.UnexpectedRequestCount = [int]$Runtime.UnexpectedRequestCount + 1
        throw 'PROVIDER_REQUEST_INVALID'
    }
    $Runtime.ProviderCallCount = [int]$Runtime.ProviderCallCount + 1
    switch -CaseSensitive ('{0}:{1}' -f $Request.Provider, $Request.Operation) {
        'Environment:AttestVmAcceptance' {
            return Invoke-CddsiWindowsVmResetAttestVmInternal -Runtime $Runtime -Request $Request
        }
        'Environment:CaptureBaseline' {
            return Invoke-CddsiWindowsVmResetCaptureBaselineInternal -Runtime $Runtime -Request $Request
        }
        'Package:ValidateExactTarget' { return Invoke-CddsiWindowsVmResetPreflightInternal -Runtime $Runtime -Request $Request }
        'Registry:ValidateExactTarget' { return Invoke-CddsiWindowsVmResetPreflightInternal -Runtime $Runtime -Request $Request }
        'Credential:ValidateExactTarget' { return Invoke-CddsiWindowsVmResetPreflightInternal -Runtime $Runtime -Request $Request }
        'FileSystem:ValidateExactTarget' { return Invoke-CddsiWindowsVmResetPreflightInternal -Runtime $Runtime -Request $Request }
        'Package:Remove' { return Invoke-CddsiWindowsVmResetMutationInternal -Runtime $Runtime -Request $Request }
        'Registry:DeleteValue' { return Invoke-CddsiWindowsVmResetMutationInternal -Runtime $Runtime -Request $Request }
        'Credential:Delete' { return Invoke-CddsiWindowsVmResetMutationInternal -Runtime $Runtime -Request $Request }
        'FileSystem:DeleteFile' { return Invoke-CddsiWindowsVmResetMutationInternal -Runtime $Runtime -Request $Request }
        'FileSystem:DeleteDirectory' { return Invoke-CddsiWindowsVmResetMutationInternal -Runtime $Runtime -Request $Request }
        'Environment:InspectFinalState' {
            return Invoke-CddsiWindowsVmResetInspectFinalStateInternal -Runtime $Runtime -Request $Request
        }
        default {
            $Runtime.UnexpectedRequestCount = [int]$Runtime.UnexpectedRequestCount + 1
            throw 'PROVIDER_OPERATION_UNAVAILABLE'
        }
    }
}

function Test-CddsiWindowsVmResetSidValueInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Value)

    if ($Value -isnot [string] -or $Value.Length -gt 184 -or
        $Value -notmatch '^S-1-(?:[0-9]+-){1,14}[0-9]+$') { return $false }
    try {
        $sid = [System.Security.Principal.SecurityIdentifier]::new($Value)
        return $sid.Value -ceq $Value
    }
    catch { return $false }
}

function Test-CddsiWindowsVmResetOneShotGrantPathInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Path,
        [Parameter(Mandatory = $true)][AllowNull()]$GrantId
    )

    if ($Path -isnot [string] -or -not (Test-CddsiCanonicalUuidValue -Value $GrantId)) {
        return $false
    }
    try {
        $expected = [IO.Path]::Combine(
            $script:CddsiWindowsVmResetOneShotGrantDirectory,
            $GrantId.ToLowerInvariant() + '.grant.json'
        )
        return [string]::Equals(
            [IO.Path]::GetFullPath($Path), [IO.Path]::GetFullPath($expected),
            [StringComparison]::OrdinalIgnoreCase
        )
    }
    catch { return $false }
}

function Get-CddsiWindowsVmResetOneShotGrantPayloadInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Grant)

    return [pscustomobject][ordered]@{
        SchemaVersion = $Grant.SchemaVersion
        ContractVersion = $Grant.ContractVersion
        OneShotGrantId = $Grant.OneShotGrantId
        ExecutionNonce = $Grant.ExecutionNonce
        ExpectedCycleId = $Grant.ExpectedCycleId
        ExpectedResetPolicyDigest = $Grant.ExpectedResetPolicyDigest
        ExpectedPlanBindingToken = $Grant.ExpectedPlanBindingToken
        ExpectedOwnershipSetDigest = $Grant.ExpectedOwnershipSetDigest
        ExpectedResourceBindingSetDigest = $Grant.ExpectedResourceBindingSetDigest
        ExpectedControlAuthenticationDigest = $Grant.ExpectedControlAuthenticationDigest
        NotBeforeUtc = $Grant.NotBeforeUtc
        ExpiresAtUtc = $Grant.ExpiresAtUtc
    }
}

function Test-CddsiWindowsVmResetOneShotGrantInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$Grant,
        [Parameter(Mandatory = $true)]$Anchor,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][object[]]$ResourceBindings,
        [Parameter(Mandatory = $true)][string]$ControlAuthenticationDigest,
        [Parameter(Mandatory = $true)][string]$VerificationTimeUtc
    )

    if (-not (Test-CddsiExactPropertySet -InputObject $Grant -Expected @(
        'SchemaVersion', 'ContractVersion', 'OneShotGrantId', 'ExecutionNonce',
        'ExpectedCycleId', 'ExpectedResetPolicyDigest', 'ExpectedPlanBindingToken',
        'ExpectedOwnershipSetDigest', 'ExpectedResourceBindingSetDigest',
        'ExpectedControlAuthenticationDigest', 'NotBeforeUtc', 'ExpiresAtUtc',
        'GrantBindingToken'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $Grant.SchemaVersion) -or
        $Grant.ContractVersion -cne 'cddsi-windows-vm-reset-one-shot-grant-v1' -or
        -not (Test-CddsiCanonicalUuidValue -Value $Grant.OneShotGrantId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Grant.ExecutionNonce) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Grant.ExpectedCycleId) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Grant.ExpectedResetPolicyDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Grant.ExpectedPlanBindingToken) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Grant.ExpectedOwnershipSetDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Grant.ExpectedResourceBindingSetDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Grant.ExpectedControlAuthenticationDigest) -or
        -not (Test-CddsiUtcTimestampValue -Value $Grant.NotBeforeUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Grant.ExpiresAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $VerificationTimeUtc) -or
        [DateTimeOffset]::Parse($Grant.ExpiresAtUtc) -le [DateTimeOffset]::Parse($Grant.NotBeforeUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Grant.GrantBindingToken) -or
        $Grant.GrantBindingToken -cne (Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetOneShotGrantPayloadInternal -Grant $Grant
        ))) { return $false }
    $now = [DateTimeOffset]::Parse($VerificationTimeUtc)
    return (
        $now -ge [DateTimeOffset]::Parse($Grant.NotBeforeUtc) -and
        $now -le [DateTimeOffset]::Parse($Grant.ExpiresAtUtc) -and
        $Grant.OneShotGrantId -ceq $Anchor.OneShotGrantId -and
        $Grant.ExecutionNonce -ceq $Anchor.OneShotExecutionNonce -and
        $Grant.ExpectedCycleId -ceq $Plan.CycleId -and
        $Grant.ExpectedResetPolicyDigest -ceq $Policy.ResetPolicyDigest -and
        $Grant.ExpectedPlanBindingToken -ceq $Plan.PlanBindingToken -and
        $Grant.ExpectedOwnershipSetDigest -ceq
            (Get-CddsiVmResetBindingToken -Value @($OwnershipReceipts)) -and
        $Grant.ExpectedResourceBindingSetDigest -ceq
            (Get-CddsiVmResetBindingToken -Value @($ResourceBindings)) -and
        $Grant.ExpectedControlAuthenticationDigest -ceq $ControlAuthenticationDigest
    )
}

function Test-CddsiWindowsVmResetProvisioningAnchorInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Anchor)

    if (-not (Test-CddsiExactPropertySet -InputObject $Anchor -Expected @(
        'SchemaVersion', 'ContractVersion', 'ExpectedAuthorityPublicKeySha256',
        'ExpectedTrustPolicyBindingToken', 'ExpectedVmIdentity',
        'ExpectedImageSha256', 'ExpectedDisposableVmIdentitySha256',
        'ExpectedVmManufacturer', 'ExpectedVmModel', 'ExpectedProviderFileSha256',
        'SupervisorVmIdentityReceiptBindingToken', 'OneShotGrantId',
        'OneShotExecutionNonce', 'OneShotGrantFilePath',
        'OneShotGrantFileSha256', 'OneShotGrantConsumerSid',
        'ExpectedCycleId', 'ExpectedResetPolicyDigest', 'ExpectedPlanBindingToken',
        'ExpectedOwnershipSetDigest', 'ExpectedResourceBindingSetDigest',
        'ExpectedControlAuthenticationDigest', 'NotBeforeUtc', 'ExpiresAtUtc',
        'AnchorBindingToken'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $Anchor.SchemaVersion) -or
        $Anchor.ContractVersion -cne 'cddsi-windows-vm-reset-provisioning-anchor-v1' -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedAuthorityPublicKeySha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedTrustPolicyBindingToken) -or
        -not (Test-CddsiSafeIdentifierValue -Value $Anchor.ExpectedVmIdentity -MaxLength 128) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedImageSha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedDisposableVmIdentitySha256) -or
        -not (Test-CddsiWindowsVmResetDisplayFactInternal -Value $Anchor.ExpectedVmManufacturer) -or
        -not (Test-CddsiWindowsVmResetDisplayFactInternal -Value $Anchor.ExpectedVmModel) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedProviderFileSha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.SupervisorVmIdentityReceiptBindingToken) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Anchor.OneShotGrantId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Anchor.OneShotExecutionNonce) -or
        -not (Test-CddsiWindowsVmResetOneShotGrantPathInternal `
            -Path $Anchor.OneShotGrantFilePath -GrantId $Anchor.OneShotGrantId) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.OneShotGrantFileSha256) -or
        -not (Test-CddsiWindowsVmResetSidValueInternal -Value $Anchor.OneShotGrantConsumerSid) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Anchor.ExpectedCycleId) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedResetPolicyDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedPlanBindingToken) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedOwnershipSetDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedResourceBindingSetDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.ExpectedControlAuthenticationDigest) -or
        -not (Test-CddsiUtcTimestampValue -Value $Anchor.NotBeforeUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Anchor.ExpiresAtUtc) -or
        [DateTimeOffset]::Parse($Anchor.ExpiresAtUtc) -le [DateTimeOffset]::Parse($Anchor.NotBeforeUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Anchor.AnchorBindingToken)) {
        return $false
    }
    $payload = [pscustomobject][ordered]@{
        SchemaVersion = $Anchor.SchemaVersion
        ContractVersion = $Anchor.ContractVersion
        ExpectedAuthorityPublicKeySha256 = $Anchor.ExpectedAuthorityPublicKeySha256
        ExpectedTrustPolicyBindingToken = $Anchor.ExpectedTrustPolicyBindingToken
        ExpectedVmIdentity = $Anchor.ExpectedVmIdentity
        ExpectedImageSha256 = $Anchor.ExpectedImageSha256
        ExpectedDisposableVmIdentitySha256 = $Anchor.ExpectedDisposableVmIdentitySha256
        ExpectedVmManufacturer = $Anchor.ExpectedVmManufacturer
        ExpectedVmModel = $Anchor.ExpectedVmModel
        ExpectedProviderFileSha256 = $Anchor.ExpectedProviderFileSha256
        SupervisorVmIdentityReceiptBindingToken = $Anchor.SupervisorVmIdentityReceiptBindingToken
        OneShotGrantId = $Anchor.OneShotGrantId
        OneShotExecutionNonce = $Anchor.OneShotExecutionNonce
        OneShotGrantFilePath = $Anchor.OneShotGrantFilePath
        OneShotGrantFileSha256 = $Anchor.OneShotGrantFileSha256
        OneShotGrantConsumerSid = $Anchor.OneShotGrantConsumerSid
        ExpectedCycleId = $Anchor.ExpectedCycleId
        ExpectedResetPolicyDigest = $Anchor.ExpectedResetPolicyDigest
        ExpectedPlanBindingToken = $Anchor.ExpectedPlanBindingToken
        ExpectedOwnershipSetDigest = $Anchor.ExpectedOwnershipSetDigest
        ExpectedResourceBindingSetDigest = $Anchor.ExpectedResourceBindingSetDigest
        ExpectedControlAuthenticationDigest = $Anchor.ExpectedControlAuthenticationDigest
        NotBeforeUtc = $Anchor.NotBeforeUtc
        ExpiresAtUtc = $Anchor.ExpiresAtUtc
    }
    return ($Anchor.AnchorBindingToken -ceq (Get-CddsiVmResetBindingToken -Value $payload))
}

function Test-CddsiWindowsVmResetTrustAgainstAnchorInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Anchor,
        [Parameter(Mandatory = $true)]$TrustPolicy,
        [Parameter(Mandatory = $true)]$DeploymentEvidence,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][object[]]$ResourceBindings,
        [Parameter(Mandatory = $true)][string]$ControlAuthenticationDigest,
        [Parameter(Mandatory = $true)][string]$VerificationTimeUtc
    )

    if (-not (Test-CddsiWindowsVmResetProvisioningAnchorInternal -Anchor $Anchor) -or
        -not (Test-CddsiWindowsVmResetTrustPolicy -Policy $TrustPolicy) -or
        -not (Test-CddsiWindowsVmResetDeploymentEvidence -Evidence $DeploymentEvidence -Policy $TrustPolicy) -or
        -not (Test-CddsiUtcTimestampValue -Value $VerificationTimeUtc)) { return $false }
    $now = [DateTimeOffset]::Parse($VerificationTimeUtc)
    return (
        $now -ge [DateTimeOffset]::Parse($Anchor.NotBeforeUtc) -and
        $now -le [DateTimeOffset]::Parse($Anchor.ExpiresAtUtc) -and
        $Anchor.ExpectedAuthorityPublicKeySha256 -ceq $TrustPolicy.DeviceAttestationAuthoritySha256 -and
        $Anchor.ExpectedTrustPolicyBindingToken -ceq $TrustPolicy.PolicyBindingToken -and
        $Anchor.ExpectedVmIdentity -ceq $TrustPolicy.VmIdentity -and
        $Anchor.ExpectedImageSha256 -ceq $TrustPolicy.ImageSha256 -and
        $Anchor.ExpectedDisposableVmIdentitySha256 -ceq $TrustPolicy.DisposableVmIdentitySha256 -and
        $Anchor.ExpectedVmManufacturer -ceq $TrustPolicy.ExpectedVmManufacturer -and
        $Anchor.ExpectedVmModel -ceq $TrustPolicy.ExpectedVmModel -and
        $Anchor.ExpectedProviderFileSha256 -ceq $TrustPolicy.ProviderFileSha256 -and
        $Anchor.SupervisorVmIdentityReceiptBindingToken -ceq
            $DeploymentEvidence.SupervisorVmIdentityReceiptBindingToken -and
        $Anchor.ExpectedCycleId -ceq $Plan.CycleId -and
        $Anchor.ExpectedResetPolicyDigest -ceq $Policy.ResetPolicyDigest -and
        $Anchor.ExpectedPlanBindingToken -ceq $Plan.PlanBindingToken -and
        $Anchor.ExpectedOwnershipSetDigest -ceq (Get-CddsiVmResetBindingToken -Value @($OwnershipReceipts)) -and
        $Anchor.ExpectedResourceBindingSetDigest -ceq (Get-CddsiVmResetBindingToken -Value @($ResourceBindings)) -and
        $Anchor.ExpectedControlAuthenticationDigest -ceq $ControlAuthenticationDigest
    )
}

function Get-CddsiWindowsVmResetProvisioningAnchorInternal {
    [CmdletBinding()]
    param()

    $path = $script:CddsiWindowsVmResetProvisioningAnchorPath
    $anchorDirectory = [IO.Path]::GetDirectoryName([IO.Path]::GetFullPath($path))
    Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
        -Path $anchorDirectory -Purpose ProvisioningAnchor
    $ancestor = Get-CddsiWindowsVmResetAncestorObservationInternal -Path $path
    if ($ancestor.ReparsePointCount -ne 0) { throw 'PROVISIONING_ANCHOR_REPARSE_POINT' }
    if (-not [IO.File]::Exists($path) -or (Test-CddsiWindowsVmResetReparseInternal -Path $path)) {
        throw 'PROVISIONING_ANCHOR_UNAVAILABLE'
    }
    $acl = Get-Acl -LiteralPath $path -ErrorAction Stop
    $ownerSid = $acl.GetOwner([System.Security.Principal.SecurityIdentifier]).Value
    if ($ownerSid -cne 'S-1-5-18') { throw 'PROVISIONING_ANCHOR_OWNER_INVALID' }
    $writeMask = [System.Security.AccessControl.FileSystemRights]::Write -bor
        [System.Security.AccessControl.FileSystemRights]::Modify -bor
        [System.Security.AccessControl.FileSystemRights]::FullControl -bor
        [System.Security.AccessControl.FileSystemRights]::ChangePermissions -bor
        [System.Security.AccessControl.FileSystemRights]::TakeOwnership
    foreach ($rule in @($acl.GetAccessRules($true, $true, [System.Security.Principal.SecurityIdentifier]))) {
        if ($rule.AccessControlType -eq [System.Security.AccessControl.AccessControlType]::Allow -and
            (($rule.FileSystemRights -band $writeMask) -ne 0) -and
            $rule.IdentityReference.Value -cne 'S-1-5-18') {
            throw 'PROVISIONING_ANCHOR_WRITABLE_BY_UNTRUSTED_PRINCIPAL'
        }
    }
    $stream = [IO.File]::Open($path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
    $reader = [IO.StreamReader]::new($stream, [Text.UTF8Encoding]::new($false, $true), $true, 4096, $false)
    try {
        if ($stream.Length -lt 32 -or $stream.Length -gt 65536) { throw 'PROVISIONING_ANCHOR_SIZE_INVALID' }
        $anchor = $reader.ReadToEnd() | ConvertFrom-Json -ErrorAction Stop
    }
    finally {
        $reader.Dispose()
        $stream.Dispose()
    }
    if (-not (Test-CddsiWindowsVmResetProvisioningAnchorInternal -Anchor $anchor)) {
        throw 'PROVISIONING_ANCHOR_INVALID'
    }
    return $anchor
}

function New-CddsiWindowsVmResetRuntimeInternal {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Simulation', 'LiveWindows')][string]$ExecutionKind,
        [Parameter(Mandatory = $true)]$TrustPolicy,
        [Parameter(Mandatory = $true)]$DeploymentEvidence,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][object[]]$ResourceBindings,
        [Parameter(Mandatory = $true)]$SystemApi,
        [Parameter(Mandatory = $true)]$Signer,
        [AllowNull()]$ProvisioningAnchor
    )

    return [pscustomobject][ordered]@{
        ExecutionKind = $ExecutionKind
        TrustPolicy = $TrustPolicy
        DeploymentEvidence = $DeploymentEvidence
        Policy = $Policy
        Plan = $Plan
        OwnershipReceipts = @($OwnershipReceipts)
        ResourceBindings = @($ResourceBindings)
        SystemApi = $SystemApi
        Signer = $Signer
        ProvisioningAnchor = $ProvisioningAnchor
        Attested = $false
        BaselineBeforeCaptured = $false
        BaselineAfterCaptured = $false
        FinalStateInspected = $false
        PreflightByToken = @{}
        ActionOutcomes = [System.Collections.ArrayList]@()
        NextActionSequence = 1
        MutationPermitSecret = [Guid]::NewGuid().ToString().ToLowerInvariant()
        ActiveMutationPermit = $null
        ProviderCallCount = 0
        RealProviderCallCount = 0
        UnexpectedRequestCount = 0
    }
}

function New-CddsiWindowsVmResetSimulationRuntime {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TrustPolicy,
        [Parameter(Mandatory = $true)]$DeploymentEvidence,
        [Parameter(Mandatory = $true)]$Policy,
        [Parameter(Mandatory = $true)]$Plan,
        [Parameter(Mandatory = $true)][object[]]$OwnershipReceipts,
        [Parameter(Mandatory = $true)][object[]]$ResourceBindings,
        [Parameter(Mandatory = $true)]$FakeSystemApi,
        [Parameter(Mandatory = $true)]$FakeSigner
    )

    if ($FakeSystemApi.Kind -cne 'FakeWindowsVmResetSystemV1' -or
        $FakeSystemApi.Invoke -isnot [scriptblock] -or
        $FakeSigner.Kind -cne 'FakeWindowsVmResetSignerV1' -or
        $FakeSigner.Sign -isnot [scriptblock] -or
        -not (Test-CddsiWindowsVmResetExecutionBundleInternal -TrustPolicy $TrustPolicy `
            -Policy $Policy -Plan $Plan -OwnershipReceipts $OwnershipReceipts `
            -ResourceBindings $ResourceBindings)) {
        throw 'SIMULATION_RUNTIME_INVALID'
    }
    return New-CddsiWindowsVmResetRuntimeInternal -ExecutionKind Simulation `
        -TrustPolicy $TrustPolicy -DeploymentEvidence $DeploymentEvidence `
        -Policy $Policy -Plan $Plan -OwnershipReceipts $OwnershipReceipts `
        -ResourceBindings $ResourceBindings -SystemApi $FakeSystemApi -Signer $FakeSigner `
        -ProvisioningAnchor $null
}

function Invoke-CddsiWindowsVmResetSimulationRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Runtime,
        [Parameter(Mandatory = $true)]$Request
    )

    if ($Runtime.ExecutionKind -cne 'Simulation' -or $Runtime.RealProviderCallCount -ne 0) {
        throw 'SIMULATION_RUNTIME_REQUIRED'
    }
    return Invoke-CddsiWindowsVmResetProviderRequestCoreInternal -Runtime $Runtime -Request $Request
}

function Get-CddsiWindowsVmResetAuthorizationPayloadInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Envelope)

    return [pscustomobject][ordered]@{
        SchemaVersion = $Envelope.SchemaVersion
        ContractVersion = $Envelope.ContractVersion
        RuntimeHandle = $Envelope.RuntimeHandle
        ProviderAdapterId = $Envelope.ProviderAdapterId
        ProviderFileSha256 = $Envelope.ProviderFileSha256
        DeviceAttestationPublicKeySha256 = $Envelope.DeviceAttestationPublicKeySha256
        TrustPolicyBindingToken = $Envelope.TrustPolicyBindingToken
        DeploymentEvidenceBindingToken = $Envelope.DeploymentEvidenceBindingToken
        ProvisioningAnchorBindingToken = $Envelope.ProvisioningAnchorBindingToken
        OneShotGrantId = $Envelope.OneShotGrantId
        OneShotExecutionNonce = $Envelope.OneShotExecutionNonce
        ResetPolicyDigest = $Envelope.ResetPolicyDigest
        PlanBindingToken = $Envelope.PlanBindingToken
        OwnershipSetDigest = $Envelope.OwnershipSetDigest
        ResourceBindingSetDigest = $Envelope.ResourceBindingSetDigest
        ControlAuthenticationDigest = $Envelope.ControlAuthenticationDigest
        VmIdentity = $Envelope.VmIdentity
        ImageSha256 = $Envelope.ImageSha256
        IssuedAtUtc = $Envelope.IssuedAtUtc
        ExpiresAtUtc = $Envelope.ExpiresAtUtc
    }
}

function Test-CddsiWindowsVmResetAuthorizationEnvelopeInternal {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$Envelope)

    if (-not (Test-CddsiExactPropertySet -InputObject $Envelope -Expected @(
        'SchemaVersion', 'ContractVersion', 'RuntimeHandle', 'ProviderAdapterId',
        'ProviderFileSha256', 'DeviceAttestationPublicKeySha256',
        'TrustPolicyBindingToken', 'DeploymentEvidenceBindingToken',
        'ProvisioningAnchorBindingToken', 'OneShotGrantId', 'OneShotExecutionNonce',
        'ResetPolicyDigest', 'PlanBindingToken',
        'OwnershipSetDigest', 'ResourceBindingSetDigest', 'VmIdentity',
        'ImageSha256', 'ControlAuthenticationDigest', 'IssuedAtUtc',
        'ExpiresAtUtc', 'AuthorizationPayloadSha256',
        'DeviceSignatureAlgorithm', 'DeviceSignatureBase64'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $Envelope.SchemaVersion) -or
        $Envelope.ContractVersion -cne 'cddsi-windows-vm-reset-authorization-envelope-v1' -or
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.RuntimeHandle) -or
        $Envelope.ProviderAdapterId -cne $script:CddsiWindowsVmResetProviderId -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.ProviderFileSha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.DeviceAttestationPublicKeySha256) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.TrustPolicyBindingToken) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.DeploymentEvidenceBindingToken) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.ProvisioningAnchorBindingToken) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.OneShotGrantId) -or
        -not (Test-CddsiCanonicalUuidValue -Value $Envelope.OneShotExecutionNonce) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.ResetPolicyDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.PlanBindingToken) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.OwnershipSetDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.ResourceBindingSetDigest) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.ControlAuthenticationDigest) -or
        -not (Test-CddsiSafeIdentifierValue -Value $Envelope.VmIdentity -MaxLength 128) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.ImageSha256) -or
        -not (Test-CddsiUtcTimestampValue -Value $Envelope.IssuedAtUtc) -or
        -not (Test-CddsiUtcTimestampValue -Value $Envelope.ExpiresAtUtc) -or
        [DateTimeOffset]::Parse($Envelope.ExpiresAtUtc) -le [DateTimeOffset]::Parse($Envelope.IssuedAtUtc) -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $Envelope.AuthorizationPayloadSha256) -or
        $Envelope.DeviceSignatureAlgorithm -cne 'ECDSA_P256_SHA256' -or
        $null -eq (ConvertFrom-CddsiWindowsVmResetBase64Internal -Value $Envelope.DeviceSignatureBase64)) {
        return $false
    }
    return ($Envelope.AuthorizationPayloadSha256 -ceq (Get-CddsiVmResetBindingToken -Value (
        Get-CddsiWindowsVmResetAuthorizationPayloadInternal -Envelope $Envelope
    )))
}

function Test-CddsiWindowsVmResetProviderAdapterAuthorization {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][AllowNull()]$ProviderAdapter)

    if (-not (Test-CddsiExactPropertySet -InputObject $ProviderAdapter -Expected @(
        'SchemaVersion', 'ContractVersion', 'Kind', 'IsLive', 'AdapterId',
        'AdapterFilePath', 'AdapterFileSha256', 'DeviceAttestationPublicKeySha256',
        'AuthorizationEnvelope', 'Invoke'
    )) -or -not (Test-CddsiSchemaVersionOne -Value $ProviderAdapter.SchemaVersion) -or
        $ProviderAdapter.ContractVersion -cne 'cddsi-vm-reset-provider-adapter-v2' -or
        $ProviderAdapter.Kind -cne 'VmResetLive' -or $ProviderAdapter.IsLive -isnot [bool] -or
        -not $ProviderAdapter.IsLive -or $ProviderAdapter.AdapterId -cne $script:CddsiWindowsVmResetProviderId -or
        $ProviderAdapter.Invoke -ne $null -or
        -not (Test-CddsiWindowsVmResetAuthorizationEnvelopeInternal -Envelope $ProviderAdapter.AuthorizationEnvelope)) {
        return $false
    }
    $envelope = $ProviderAdapter.AuthorizationEnvelope
    if (-not $script:CddsiWindowsVmResetAuthorizedRuntimes.ContainsKey($envelope.RuntimeHandle)) { return $false }
    $runtime = $script:CddsiWindowsVmResetAuthorizedRuntimes[$envelope.RuntimeHandle]
    if ($runtime.ExecutionKind -cne 'LiveWindows' -or $null -eq $runtime.ProvisioningAnchor -or
        $ProviderAdapter.AdapterFilePath -cne $runtime.TrustPolicy.ProviderFilePath -or
        $ProviderAdapter.AdapterFileSha256 -cne $runtime.TrustPolicy.ProviderFileSha256 -or
        $ProviderAdapter.DeviceAttestationPublicKeySha256 -cne $runtime.TrustPolicy.DeviceAttestationPublicKeySha256 -or
        $envelope.ProviderFileSha256 -cne $runtime.TrustPolicy.ProviderFileSha256 -or
        $envelope.DeviceAttestationPublicKeySha256 -cne $runtime.TrustPolicy.DeviceAttestationPublicKeySha256 -or
        $envelope.TrustPolicyBindingToken -cne $runtime.TrustPolicy.PolicyBindingToken -or
        $envelope.DeploymentEvidenceBindingToken -cne $runtime.DeploymentEvidence.EvidenceBindingToken -or
        $envelope.ProvisioningAnchorBindingToken -cne $runtime.ProvisioningAnchor.AnchorBindingToken -or
        $envelope.OneShotGrantId -cne $runtime.ProvisioningAnchor.OneShotGrantId -or
        $envelope.OneShotExecutionNonce -cne $runtime.ProvisioningAnchor.OneShotExecutionNonce -or
        $envelope.ResetPolicyDigest -cne $runtime.Policy.ResetPolicyDigest -or
        $envelope.PlanBindingToken -cne $runtime.Plan.PlanBindingToken -or
        $envelope.OwnershipSetDigest -cne (Get-CddsiVmResetBindingToken -Value @($runtime.OwnershipReceipts)) -or
        $envelope.ResourceBindingSetDigest -cne (Get-CddsiVmResetBindingToken -Value @($runtime.ResourceBindings)) -or
        $envelope.ControlAuthenticationDigest -cne $runtime.ControlAuthenticationDigest -or
        $envelope.VmIdentity -cne $runtime.Policy.VmIdentity -or
        $envelope.ImageSha256 -cne $runtime.Policy.ImageSha256) { return $false }
    $now = [DateTimeOffset]::UtcNow
    if ($now -lt [DateTimeOffset]::Parse($envelope.IssuedAtUtc) -or
        $now -gt [DateTimeOffset]::Parse($envelope.ExpiresAtUtc) -or
        -not (Test-CddsiWindowsVmResetEcdsaSignatureInternal `
            -PublicKeyBlobBase64 $runtime.TrustPolicy.DevicePublicKeyCngBlobBase64 `
            -DigestSha256 $envelope.AuthorizationPayloadSha256 `
            -SignatureBase64 $envelope.DeviceSignatureBase64) -or
        -not (Test-CddsiWindowsVmResetLocalBytesInternal -Policy $runtime.TrustPolicy)) {
        return $false
    }
    try {
        $currentAnchor = Get-CddsiWindowsVmResetProvisioningAnchorInternal
        if ($currentAnchor.AnchorBindingToken -cne $runtime.ProvisioningAnchor.AnchorBindingToken) { return $false }
        $identity = Get-CddsiWindowsVmResetVmIdentityInternal
        if ($identity.IdentitySha256 -cne $runtime.TrustPolicy.DisposableVmIdentitySha256 -or
            $identity.Manufacturer -cne $runtime.TrustPolicy.ExpectedVmManufacturer -or
            $identity.Model -cne $runtime.TrustPolicy.ExpectedVmModel) { return $false }
    }
    catch { return $false }
    return $true
}

function Test-CddsiWindowsVmResetAdapterDeviceSignature {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][AllowNull()]$ProviderAdapter,
        [Parameter(Mandatory = $true)][string]$DigestSha256,
        [Parameter(Mandatory = $true)][string]$SignatureBase64
    )

    if ($null -eq $ProviderAdapter -or $null -eq $ProviderAdapter.AuthorizationEnvelope -or
        -not (Test-CddsiVmCalibrationSha256Value -Value $DigestSha256)) { return $false }
    $handle = $ProviderAdapter.AuthorizationEnvelope.RuntimeHandle
    if (-not $script:CddsiWindowsVmResetAuthorizedRuntimes.ContainsKey($handle)) { return $false }
    $runtime = $script:CddsiWindowsVmResetAuthorizedRuntimes[$handle]
    if ($ProviderAdapter.DeviceAttestationPublicKeySha256 -cne
        $runtime.TrustPolicy.DeviceAttestationPublicKeySha256) { return $false }
    return Test-CddsiWindowsVmResetEcdsaSignatureInternal `
        -PublicKeyBlobBase64 $runtime.TrustPolicy.DevicePublicKeyCngBlobBase64 `
        -DigestSha256 $DigestSha256 -SignatureBase64 $SignatureBase64
}

function Invoke-CddsiWindowsVmResetAuthorizedRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$ProviderAdapter,
        [Parameter(Mandatory = $true)]$Request
    )

    if (-not (Test-CddsiWindowsVmResetProviderAdapterAuthorization -ProviderAdapter $ProviderAdapter)) {
        throw 'WINDOWS_VM_RESET_ADAPTER_AUTHORIZATION_INVALID'
    }
    $handle = $ProviderAdapter.AuthorizationEnvelope.RuntimeHandle
    $runtime = $script:CddsiWindowsVmResetAuthorizedRuntimes[$handle]
    try {
        return Invoke-CddsiWindowsVmResetProviderRequestCoreInternal -Runtime $runtime -Request $Request
    }
    finally {
        if ($Request.Provider -ceq 'Environment' -and $Request.Operation -ceq 'InspectFinalState') {
            $script:CddsiWindowsVmResetAuthorizedRuntimes.Remove($handle)
        }
    }
}

function New-CddsiWindowsVmResetProvider {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$TrustPolicy,
        [AllowNull()]$DeploymentEvidence,
        [AllowNull()]$Policy,
        [AllowNull()]$Plan,
        [AllowEmptyCollection()][object[]]$OwnershipReceipts = @(),
        [AllowEmptyCollection()][object[]]$ResourceBindings = @(),
        [string]$ControlAuthenticationDigest = '',

        [ValidateSet('TestSafe', 'DryRun', 'Live')]
        [string]$Mode = 'TestSafe',

        [switch]$AcknowledgeRealChanges
    )

    if ($null -eq (Get-Command -Name New-CddsiOperationResult -CommandType Function -ErrorAction SilentlyContinue)) {
        throw 'Required operation-result contract is not loaded.'
    }
    if (-not (Test-CddsiWindowsVmResetTrustPolicy -Policy $TrustPolicy)) {
        throw 'Windows VM reset trust policy is invalid or is not frozen.'
    }
    $operationPlan = @(Get-CddsiWindowsVmResetProviderOperationContract | ForEach-Object {
        '{0}:{1}:{2}:{3}' -f $_.Provider, $_.Operation, $_.ResourceType, $_.CommandId
    })
    $data = [pscustomobject][ordered]@{
        SchemaVersion = 1
        ContractVersion = 'cddsi-windows-vm-reset-provider-factory-result-v2'
        EvidenceClass = 'DIAGNOSTIC_ONLY'
        ProvisioningState = $TrustPolicy.LiveProvisioningState
        ProviderAdapter = $null
        RealAccessPerformed = $false
        OneShotGrantConsumed = $false
        ProviderCallCount = 0
        BlockedLiveOperations = @($script:CddsiWindowsVmResetProviderOperationSpecifications | ForEach-Object {
            '{0}:{1}:{2}' -f $_.Provider, $_.Operation, $_.ResourceType
        })
        RequiredResetMode = 'SnapshotRestore'
    }
    if ($Mode -cne 'Live') {
        return New-CddsiOperationResult -Operation 'NewWindowsVmResetProvider' `
            -Status 'ACTION_REQUIRED' -Mode $Mode -Changed:$false `
            -ErrorCode 'VM_ACCEPTANCE_LIVE_REQUIRED' `
            -MessageSafe 'Windows VM reset provider remained plan-only; no provider adapter or system access was created.' `
            -PlannedChanges $operationPlan -Warnings @('VM_ACCEPTANCE_LIVE_REQUIRED') -Data $data
    }
    if (-not $AcknowledgeRealChanges.IsPresent) {
        return New-CddsiOperationResult -Operation 'NewWindowsVmResetProvider' `
            -Status 'ACTION_REQUIRED' -Mode Live -Changed:$false `
            -ErrorCode 'REAL_CHANGE_ACKNOWLEDGEMENT_REQUIRED' `
            -MessageSafe 'Windows VM reset Live provider requires separate real-change acknowledgement.' `
            -PlannedChanges $operationPlan -Warnings @('REAL_CHANGE_ACKNOWLEDGEMENT_REQUIRED') -Data $data
    }

    $data.RealAccessPerformed = $true
    $grantHandle = $null
    try {
        if ($TrustPolicy.LiveProvisioningState -cne 'PROVISIONED' -or $null -eq $DeploymentEvidence -or
            $null -eq $Policy -or $null -eq $Plan -or
            -not (Test-CddsiVmCalibrationSha256Value -Value $ControlAuthenticationDigest)) {
            throw 'VM_RESET_LIVE_PREREQUISITE_MISSING'
        }
        $verificationTime = [DateTimeOffset]::UtcNow.ToString('o')
        $anchor = Get-CddsiWindowsVmResetProvisioningAnchorInternal
        if ($script:CddsiWindowsVmResetConsumedGrantHandles.ContainsKey($anchor.OneShotGrantId)) {
            throw 'VM_RESET_ONE_SHOT_GRANT_ALREADY_CONSUMED'
        }
        if (-not (Test-CddsiWindowsVmResetTrustAgainstAnchorInternal -Anchor $anchor `
            -TrustPolicy $TrustPolicy -DeploymentEvidence $DeploymentEvidence `
            -Policy $Policy -Plan $Plan -OwnershipReceipts $OwnershipReceipts `
            -ResourceBindings $ResourceBindings `
            -ControlAuthenticationDigest $ControlAuthenticationDigest `
            -VerificationTimeUtc $verificationTime) -or
            -not (Test-CddsiWindowsVmResetLiveAuthorization -Policy $TrustPolicy `
                -DeploymentEvidence $DeploymentEvidence -VerificationTimeUtc $verificationTime) -or
            -not (Test-CddsiWindowsVmResetLocalBytesInternal -Policy $TrustPolicy) -or
            (Get-CddsiWindowsVmResetFileSha256Internal -Path $TrustPolicy.GitExecutablePath) -cne
                $TrustPolicy.GitExecutableSha256 -or
            -not (Test-CddsiWindowsVmResetExecutionBundleInternal -TrustPolicy $TrustPolicy `
                -Policy $Policy -Plan $Plan -OwnershipReceipts $OwnershipReceipts `
                -ResourceBindings $ResourceBindings)) {
            throw 'VM_RESET_LIVE_TRUST_VALIDATION_FAILED'
        }
        $identity = Get-CddsiWindowsVmResetVmIdentityInternal
        if ($identity.IdentitySha256 -cne $TrustPolicy.DisposableVmIdentitySha256 -or
            $identity.Manufacturer -cne $TrustPolicy.ExpectedVmManufacturer -or
            $identity.Model -cne $TrustPolicy.ExpectedVmModel) {
            throw 'DISPOSABLE_VM_IDENTITY_MISMATCH'
        }
        $grantHandle = Open-CddsiWindowsVmResetOneShotGrantInternal -Anchor $anchor
        $grantBytes = $grantHandle.ReadAllBytes(65536)
        if ($grantBytes.Count -ge 3 -and $grantBytes[0] -eq 0xef -and
            $grantBytes[1] -eq 0xbb -and $grantBytes[2] -eq 0xbf) {
            throw 'ONE_SHOT_GRANT_UTF8_BOM_FORBIDDEN'
        }
        if ((Get-CddsiWindowsVmResetBytesSha256Internal -Bytes $grantBytes) -cne
            $anchor.OneShotGrantFileSha256) { throw 'ONE_SHOT_GRANT_FILE_HASH_MISMATCH' }
        $utf8 = [System.Text.UTF8Encoding]::new($false, $true)
        $grantText = $utf8.GetString($grantBytes)
        $grant = ConvertFrom-Json -InputObject $grantText -ErrorAction Stop
        if (-not (Test-CddsiWindowsVmResetOneShotGrantInternal -Grant $grant `
            -Anchor $anchor -Policy $Policy -Plan $Plan `
            -OwnershipReceipts $OwnershipReceipts -ResourceBindings $ResourceBindings `
            -ControlAuthenticationDigest $ControlAuthenticationDigest `
            -VerificationTimeUtc $verificationTime)) {
            throw 'ONE_SHOT_GRANT_BINDING_INVALID'
        }
        $signer = New-CddsiWindowsVmResetDeviceSignerInternal -TrustPolicy $TrustPolicy
        $runtimeHandle = [Guid]::NewGuid().ToString().ToLowerInvariant()
        $factoryCapability = [pscustomobject][ordered]@{
            RuntimeHandle = $runtimeHandle
            CapabilityNonce = [Guid]::NewGuid().ToString().ToLowerInvariant()
        }
        # Live runtime construction is intentionally inlined in the fully gated
        # factory. The public-looking helper above creates simulation runtimes;
        # a caller-created LiveWindows runtime has no registered capability and
        # is rejected by the lowest system/mutation primitives.
        $runtime = [pscustomobject][ordered]@{
            ExecutionKind = 'LiveWindows'
            TrustPolicy = $TrustPolicy
            DeploymentEvidence = $DeploymentEvidence
            Policy = $Policy
            Plan = $Plan
            OwnershipReceipts = @($OwnershipReceipts)
            ResourceBindings = @($ResourceBindings)
            SystemApi = [pscustomobject][ordered]@{ Kind = 'WindowsVmResetNativeV2' }
            Signer = $signer
            ProvisioningAnchor = $anchor
            OneShotExecutionNonce = $anchor.OneShotExecutionNonce
            ControlAuthenticationDigest = $ControlAuthenticationDigest
            FactoryCapability = $factoryCapability
            AuthorizationActivated = $false
            Attested = $false
            BaselineBeforeCaptured = $false
            BaselineAfterCaptured = $false
            FinalStateInspected = $false
            PreflightByToken = @{}
            ActionOutcomes = [System.Collections.ArrayList]@()
            NextActionSequence = 1
            MutationPermitSecret = [Guid]::NewGuid().ToString().ToLowerInvariant()
            ActiveMutationPermit = $null
            ProviderCallCount = 0
            RealProviderCallCount = 0
            UnexpectedRequestCount = 0
        }
        $issued = [DateTimeOffset]::UtcNow
        $expiry = [DateTimeOffset]::Parse($DeploymentEvidence.ExpiresAtUtc)
        $anchorExpiry = [DateTimeOffset]::Parse($anchor.ExpiresAtUtc)
        if ($anchorExpiry -lt $expiry) { $expiry = $anchorExpiry }
        $shortExpiry = $issued.AddMinutes(10)
        if ($shortExpiry -lt $expiry) { $expiry = $shortExpiry }
        if ($expiry -le $issued) { throw 'VM_RESET_AUTHORIZATION_EXPIRED' }
        $envelope = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-windows-vm-reset-authorization-envelope-v1'
            RuntimeHandle = $runtimeHandle
            ProviderAdapterId = $script:CddsiWindowsVmResetProviderId
            ProviderFileSha256 = $TrustPolicy.ProviderFileSha256
            DeviceAttestationPublicKeySha256 = $TrustPolicy.DeviceAttestationPublicKeySha256
            TrustPolicyBindingToken = $TrustPolicy.PolicyBindingToken
            DeploymentEvidenceBindingToken = $DeploymentEvidence.EvidenceBindingToken
            ProvisioningAnchorBindingToken = $anchor.AnchorBindingToken
            OneShotGrantId = $anchor.OneShotGrantId
            OneShotExecutionNonce = $anchor.OneShotExecutionNonce
            ResetPolicyDigest = $Policy.ResetPolicyDigest
            PlanBindingToken = $Plan.PlanBindingToken
            OwnershipSetDigest = Get-CddsiVmResetBindingToken -Value @($OwnershipReceipts)
            ResourceBindingSetDigest = Get-CddsiVmResetBindingToken -Value @($ResourceBindings)
            ControlAuthenticationDigest = $ControlAuthenticationDigest
            VmIdentity = $Policy.VmIdentity
            ImageSha256 = $Policy.ImageSha256
            IssuedAtUtc = $issued.ToString('o')
            ExpiresAtUtc = $expiry.ToString('o')
            AuthorizationPayloadSha256 = ''
            DeviceSignatureAlgorithm = 'ECDSA_P256_SHA256'
            DeviceSignatureBase64 = ''
        }
        $envelope.AuthorizationPayloadSha256 = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetAuthorizationPayloadInternal -Envelope $envelope
        )
        $envelope.DeviceSignatureBase64 = Invoke-CddsiWindowsVmResetDeviceSignInternal `
            -Signer $signer -DigestSha256 $envelope.AuthorizationPayloadSha256
        $grantHandle.CommitDelete()
        $grantHandle.Dispose()
        $grantHandle = $null
        $data.OneShotGrantConsumed = $true
        $runtime.AuthorizationActivated = $true
        $script:CddsiWindowsVmResetAuthorizedRuntimes[$envelope.RuntimeHandle] = $runtime
        $script:CddsiWindowsVmResetConsumedGrantHandles[$anchor.OneShotGrantId] = `
            $envelope.RuntimeHandle
        $adapter = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-vm-reset-provider-adapter-v2'
            Kind = 'VmResetLive'
            IsLive = $true
            AdapterId = $script:CddsiWindowsVmResetProviderId
            AdapterFilePath = $TrustPolicy.ProviderFilePath
            AdapterFileSha256 = $TrustPolicy.ProviderFileSha256
            DeviceAttestationPublicKeySha256 = $TrustPolicy.DeviceAttestationPublicKeySha256
            AuthorizationEnvelope = $envelope
            Invoke = $null
        }
        $data.ProvisioningState = 'PROVISIONED'
        $data.ProviderAdapter = $adapter
        $data.BlockedLiveOperations = @()
        $data.RequiredResetMode = 'GuestReset'
        return New-CddsiOperationResult -Operation 'NewWindowsVmResetProvider' `
            -Status 'SUCCEEDED' -Mode Live -Changed:$false `
            -MessageSafe 'VM-only Windows reset provider was authorized without performing a reset mutation.' `
            -PlannedChanges $operationPlan -Data $data
    }
    catch {
        if ($null -ne $grantHandle) {
            try { $grantHandle.Dispose() } catch {}
            $grantHandle = $null
        }
        return New-CddsiOperationResult -Operation 'NewWindowsVmResetProvider' `
            -Status 'ACTION_REQUIRED' -Mode Live -Changed:$false `
            -ErrorCode 'WINDOWS_VM_RESET_PROVIDER_UNAVAILABLE' `
            -MessageSafe 'VM-only Windows reset provider trust or platform prerequisites are unavailable.' `
            -PlannedChanges $operationPlan -Warnings @(
                'SNAPSHOT_RESTORE_REQUIRED',
                'WINDOWS_VM_RESET_PROVIDER_UNAVAILABLE'
            ) -Data $data
    }
}
