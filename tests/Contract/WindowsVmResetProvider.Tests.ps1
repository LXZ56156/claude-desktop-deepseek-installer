BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'lib\vm-reset.ps1')
    . (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-vm-reset-live.ps1')
    . (Join-Path $script:RepoRoot 'operator\fast-lane\providers\windows-vm-reset.ps1')

    # The isolated PS7 worker intentionally excludes the Windows AppX module
    # path. Declare inert commands so Pester can install mocks without module
    # auto-discovery; an unmocked call remains a hard test failure.
    function Get-AppxPackage {
        [CmdletBinding()]
        param([string]$Name)
        throw 'Synthetic Get-AppxPackage test stub must be mocked.'
    }

    function Remove-AppxPackage {
        [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
        param([string]$Package)
        throw 'Synthetic Remove-AppxPackage test stub must be mocked.'
    }

    function Copy-CddsiWindowsVmResetFixture {
        param([Parameter(Mandatory = $true)]$Value)
        return [System.Management.Automation.PSSerializer]::Deserialize(
            [System.Management.Automation.PSSerializer]::Serialize($Value, 50)
        )
    }

    function Get-CddsiWindowsVmResetFixtureBlob {
        param([Parameter(Mandatory = $true)][byte]$Byte)
        $bytes = [byte[]]::new(72)
        for ($index = 0; $index -lt $bytes.Count; $index++) { $bytes[$index] = $Byte }
        return [pscustomobject]@{
            Base64 = [Convert]::ToBase64String($bytes)
            Sha256 = Get-CddsiWindowsVmResetSha256HexInternal -Bytes $bytes
        }
    }

    function New-CddsiWindowsVmResetDirectoryAclFixture {
        param(
            [string]$OwnerSid = 'S-1-5-18',
            [AllowEmptyCollection()][object[]]$Rules = @()
        )

        $acl = [System.Security.AccessControl.DirectorySecurity]::new()
        $acl.SetOwner([System.Security.Principal.SecurityIdentifier]::new($OwnerSid))
        foreach ($rule in @($Rules)) {
            $acl.AddAccessRule([System.Security.AccessControl.FileSystemAccessRule]::new(
                [System.Security.Principal.SecurityIdentifier]::new([string]$rule.Sid),
                [System.Security.AccessControl.FileSystemRights]$rule.Rights,
                [System.Security.AccessControl.AccessControlType]::Allow
            ))
        }
        return $acl
    }

    function New-CddsiWindowsVmResetTrustPolicyFixture {
        param([ValidateSet('UNPROVISIONED', 'PROVISIONED')][string]$State = 'UNPROVISIONED')
        $device = Get-CddsiWindowsVmResetFixtureBlob -Byte 17
        $authority = Get-CddsiWindowsVmResetFixtureBlob -Byte 34
        $providerPath = 'C:\cddsi-vm-operator\providers\windows-vm-reset.ps1'
        $operations = @(Get-CddsiWindowsVmResetProviderOperationContract)
        $bindings = @($operations | ForEach-Object {
            [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-windows-vm-reset-command-binding-v2'
                Sequence = [int]$_.Sequence
                Provider = $_.Provider
                Operation = $_.Operation
                ResourceType = $_.ResourceType
                Mutation = [bool]$_.Mutation
                CommandId = $_.CommandId
                CommandFilePath = $providerPath
                CommandFileSha256 = 'b' * 64
                EntryPoint = $_.EntryPoint
            }
        })
        $policy = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-windows-vm-reset-trust-policy-v2'
            EnvironmentTier = 'VmAcceptance'
            VmIdentity = 'vm-fastlane-01'
            ImageSha256 = 'a' * 64
            DisposableVmIdentitySha256 = '9' * 64
            ExpectedVmManufacturer = 'Microsoft Corporation'
            ExpectedVmModel = 'Virtual Machine'
            ProviderAdapterId = 'cddsi-vm-reset-provider-windows-v2'
            ProviderFilePath = $providerPath
            ProviderFileSha256 = 'b' * 64
            DeviceCngKeyName = 'cddsi-vm-reset-device-v1'
            DevicePublicKeyCngBlobBase64 = $device.Base64
            DeviceAttestationPublicKeySha256 = $device.Sha256
            AuthorityPublicKeyCngBlobBase64 = $authority.Base64
            DeviceAttestationAuthoritySha256 = $authority.Sha256
            GitExecutablePath = 'C:\Program Files\Git\cmd\git.exe'
            GitExecutableSha256 = '8' * 64
            CommandRootPath = 'C:\cddsi-vm-operator\providers'
            CommandBindings = @($bindings)
            Frozen = $true
            LiveProvisioningState = $State
            AttestationNotBeforeUtc = '2030-01-01T00:00:00Z'
            AttestationExpiresAtUtc = '2030-01-01T01:00:00Z'
            PolicyBindingToken = ''
        }
        $policy.PolicyBindingToken = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetPolicyPayloadInternal -Policy $policy
        )
        return $policy
    }

    function New-CddsiWindowsVmResetDeploymentEvidenceFixture {
        param([Parameter(Mandatory = $true)]$TrustPolicy)
        $signature = [Convert]::ToBase64String(([byte[]](1..64)))
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-windows-vm-reset-deployment-evidence-v2'
            EnvironmentTier = 'VmAcceptance'
            HostSystem = 'Windows'
            VmIdentity = $TrustPolicy.VmIdentity
            ImageSha256 = $TrustPolicy.ImageSha256
            DisposableVmIdentitySha256 = $TrustPolicy.DisposableVmIdentitySha256
            SupervisorVmIdentityReceiptBindingToken = '7' * 64
            ProviderFilePath = $TrustPolicy.ProviderFilePath
            ObservedProviderFileSha256 = $TrustPolicy.ProviderFileSha256
            DeviceAttestationPublicKeySha256 = $TrustPolicy.DeviceAttestationPublicKeySha256
            DeviceAttestationAuthoritySha256 = $TrustPolicy.DeviceAttestationAuthoritySha256
            CommandSetDigest = Get-CddsiWindowsVmResetCommandSetDigestInternal -Policy $TrustPolicy
            ChallengeSha256 = '6' * 64
            AuthorityProvisioningPayloadSha256 = ''
            AuthoritySignatureAlgorithm = 'ECDSA_P256_SHA256'
            AuthoritySignatureBase64 = $signature
            DeviceAttestationPayloadSha256 = ''
            DeviceSignatureAlgorithm = 'ECDSA_P256_SHA256'
            DeviceSignatureBase64 = $signature
            CommandEvidence = @($TrustPolicy.CommandBindings | ForEach-Object {
                [pscustomobject][ordered]@{
                    Sequence = $_.Sequence
                    CommandId = $_.CommandId
                    CommandFilePath = $_.CommandFilePath
                    ObservedCommandFileSha256 = $_.CommandFileSha256
                }
            })
            NotBeforeUtc = $TrustPolicy.AttestationNotBeforeUtc
            ExpiresAtUtc = $TrustPolicy.AttestationExpiresAtUtc
            VerifiedAtUtc = '2030-01-01T00:00:01Z'
            CryptographicVerificationState = 'SIGNED_PENDING_LOCAL_VERIFICATION'
            EvidenceBindingToken = ''
        }
        $evidence.AuthorityProvisioningPayloadSha256 = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetAuthorityPayloadInternal -Evidence $evidence
        )
        $evidence.DeviceAttestationPayloadSha256 = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetDeviceAttestationPayloadInternal -Evidence $evidence
        )
        $fields = @(
            'SchemaVersion', 'ContractVersion', 'EnvironmentTier', 'HostSystem',
            'VmIdentity', 'ImageSha256', 'DisposableVmIdentitySha256',
            'SupervisorVmIdentityReceiptBindingToken', 'ProviderFilePath',
            'ObservedProviderFileSha256', 'DeviceAttestationPublicKeySha256',
            'DeviceAttestationAuthoritySha256', 'CommandSetDigest', 'ChallengeSha256',
            'AuthorityProvisioningPayloadSha256', 'AuthoritySignatureAlgorithm',
            'AuthoritySignatureBase64', 'DeviceAttestationPayloadSha256',
            'DeviceSignatureAlgorithm', 'DeviceSignatureBase64', 'CommandEvidence',
            'NotBeforeUtc', 'ExpiresAtUtc', 'VerifiedAtUtc',
            'CryptographicVerificationState'
        )
        $evidence.EvidenceBindingToken = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiVmResetEvidencePayload -Evidence $evidence -PropertyNames $fields
        )
        return $evidence
    }

    function New-CddsiWindowsVmResetExecutionFixture {
        param([Parameter(Mandatory = $true)]$TrustPolicy)
        $ownerRunId = '61000000-0000-4000-8000-000000000001'
        $ownedRoot = 'C:\cddsi-vm-test\cddsi-vm-test-' + $ownerRunId
        $markerPath = $ownedRoot + '\.cddsi-owner.json'
        $markerSha = 'c' * 64
        $preexisting = 'd' * 64
        $ancestor = 'e' * 64
        $descriptors = @(
            [pscustomobject][ordered]@{ PackageFullName = 'CDDsi.Test.Package_1.0.0.0_x64__publisher' },
            [pscustomobject][ordered]@{ Hive = 'HKCU'; KeyPath = 'SOFTWARE\Policies\Claude'; ValueName = 'ClaudeCodeEnv'; RegistryView = 'Default' },
            [pscustomobject][ordered]@{ TargetName = 'cddsi-vm-test:deepseek'; CredentialType = 'Generic' },
            [pscustomobject][ordered]@{
                Path = $ownedRoot + '\checkpoint.json'; OwnedRootPath = $ownedRoot
                OwnerMarkerPath = $markerPath; OwnerMarkerSha256 = $markerSha
                ExpectedFileSha256 = 'f' * 64; PreexistingPathBindingToken = $preexisting
                AncestorBindingToken = $ancestor; ExistedBeforeOwnerRun = $false
            },
            [pscustomobject][ordered]@{
                Path = $ownedRoot; OwnerMarkerPath = $markerPath
                OwnerMarkerSha256 = $markerSha; PreexistingPathBindingToken = $preexisting
                AncestorBindingToken = $ancestor; ExistedBeforeOwnerRun = $false
            }
        )
        $types = @('Package', 'HkcuValue', 'Credential', 'Checkpoint', 'OwnerMarkedDirectory')
        $providers = @('Package', 'Registry', 'Credential', 'FileSystem', 'FileSystem')
        $operations = @('Remove', 'DeleteValue', 'Delete', 'DeleteFile', 'DeleteDirectory')
        $tokens = @('<VM_RESET_PACKAGE:TEST>', '<VM_RESET_HKCU:TEST>', '<VM_RESET_CREDENTIAL:TEST>', '<VM_RESET_CHECKPOINT:TEST>', '<VM_RESET_DIRECTORY:TEST>')
        $receipts = @()
        $entries = @()
        $bindings = @()
        for ($index = 0; $index -lt 5; $index++) {
            $resourceId = 'resource-' + ($index + 1)
            $identity = Get-CddsiVmResetBindingToken -Value $descriptors[$index]
            $receiptPayload = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-ownership-receipt-v1'
                ReceiptId = ('62000000-0000-4000-8000-{0:d12}' -f ($index + 1))
                OwnerId = 'cddsi-vm-test'; OwnerRunId = $ownerRunId
                ResourceId = $resourceId; ResourceType = $types[$index]
                Provider = $providers[$index]; Operation = $operations[$index]
                ResourceToken = $tokens[$index]; ResourceIdentitySha256 = $identity
                MarkerSha256 = $(if ($types[$index] -ceq 'OwnerMarkedDirectory') { $markerSha } else { 'NOT_APPLICABLE' })
                PreexistingPathBindingToken = $(if ($types[$index] -ceq 'OwnerMarkedDirectory') { $preexisting } else { 'NOT_APPLICABLE' })
                IssuedAtUtc = '2030-01-01T00:00:00Z'
            }
            $receipt = [pscustomobject][ordered]@{}
            foreach ($name in $receiptPayload.PSObject.Properties.Name) {
                Add-Member -InputObject $receipt -NotePropertyName $name -NotePropertyValue $receiptPayload.$name
            }
            Add-Member -InputObject $receipt -NotePropertyName ReceiptBindingToken `
                -NotePropertyValue (Get-CddsiVmResetBindingToken -Value $receiptPayload)
            $receipts += $receipt
            $entries += [pscustomobject][ordered]@{
                Sequence = $index + 1; ResourceId = $resourceId; ResourceType = $types[$index]
                Provider = $providers[$index]; Operation = $operations[$index]
                ResourceToken = $tokens[$index]; OwnerRunId = $ownerRunId
                ResourceIdentitySha256 = $identity
                MarkerSha256 = $receipt.MarkerSha256
                PreexistingPathBindingToken = $receipt.PreexistingPathBindingToken
                OwnershipReceiptBindingToken = $receipt.ReceiptBindingToken
            }
            $bindings += [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-resource-binding-v1'
                ResourceId = $resourceId; ResourceToken = $tokens[$index]
                ResourceType = $types[$index]; Provider = $providers[$index]
                Operation = $operations[$index]; OwnerRunId = $ownerRunId
                TargetDescriptor = $descriptors[$index]; TargetBindingToken = $identity
            }
        }
        $observations = @()
        for ($index = 0; $index -lt 8; $index++) {
            $spec = $script:CddsiWindowsVmResetBaselineSpecifications[$index]
            $observations += [pscustomobject][ordered]@{
                Sequence = $spec.Sequence; Domain = $spec.Domain; Provider = $spec.Provider
                ResourceToken = $spec.ResourceToken; StateDigest = ($index + 1).ToString('x') * 64
            }
        }
        $baseline = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-baseline-v1'
            VmIdentity = $TrustPolicy.VmIdentity; ImageSha256 = $TrustPolicy.ImageSha256
            CapturedAtUtc = '2030-01-01T00:00:00Z'; Observations = @($observations); BaselineDigest = ''
        }
        $baseline.BaselineDigest = Get-CddsiVmResetBaselineDigest -Baseline $baseline
        $policy = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-policy-v1'
            PolicyId = '63000000-0000-4000-8000-000000000001'; PolicyRevision = 1
            Lane = 'FastLane'; EnvironmentResetMode = 'GuestReset'
            VmIdentity = $TrustPolicy.VmIdentity; ImageSha256 = $TrustPolicy.ImageSha256
            Frozen = $true; ExpectedBaselineDigest = $baseline.BaselineDigest
            AllowList = @($entries); AllowListDigest = ''; ResetPolicyDigest = ''
        }
        $policy.AllowListDigest = Get-CddsiVmResetBindingToken -Value @($policy.AllowList)
        $policyPayload = [pscustomobject][ordered]@{
            SchemaVersion = $policy.SchemaVersion; ContractVersion = $policy.ContractVersion
            PolicyId = $policy.PolicyId; PolicyRevision = $policy.PolicyRevision; Lane = $policy.Lane
            EnvironmentResetMode = $policy.EnvironmentResetMode; VmIdentity = $policy.VmIdentity
            ImageSha256 = $policy.ImageSha256; Frozen = $policy.Frozen
            ExpectedBaselineDigest = $policy.ExpectedBaselineDigest; AllowList = @($policy.AllowList)
            AllowListDigest = $policy.AllowListDigest
        }
        $policy.ResetPolicyDigest = Get-CddsiVmResetBindingToken -Value $policyPayload
        $plan = New-CddsiVmResetPlan -Policy $policy -OwnershipReceipts $receipts `
            -CycleId '64000000-0000-4000-8000-000000000001'
        return [pscustomobject]@{
            Policy = $policy; Plan = $plan; Receipts = @($receipts); Bindings = @($bindings)
            BaselineObservations = @($observations)
        }
    }

    function New-CddsiWindowsVmResetFakeSystem {
        param(
            [Parameter(Mandatory = $true)]$Execution,
            [ValidateSet('Happy', 'NoChange', 'PartialFailure', 'Toctou')][string]$Scenario = 'Happy'
        )
        $state = [ordered]@{ Clock = 0; MutationCalls = 0; InspectCounts = @{}; Resources = @{} }
        foreach ($binding in $Execution.Bindings) {
            $state.Resources[$binding.ResourceType] = [ordered]@{
                Sequence = [int](@($Execution.Bindings).IndexOf($binding) + 1)
                Exists = ($Scenario -cne 'NoChange')
                Generation = 1
                Binding = $binding
            }
            $state.InspectCounts[$binding.ResourceType] = 0
        }
        $capturedState = $state
        $capturedScenario = $Scenario
        $capturedExecution = $Execution
        $capturedBindingToken = ${function:Get-CddsiVmResetBindingToken}
        $invoke = {
            param($operation, $arguments)
            switch -CaseSensitive ($operation) {
                'GetUtcNow' {
                    $capturedState.Clock++
                    return ([DateTimeOffset]::Parse('2030-01-01T00:00:00Z').AddSeconds($capturedState.Clock)).ToString('o')
                }
                'GetVmIdentity' {
                    return [pscustomobject][ordered]@{
                        Manufacturer = 'Microsoft Corporation'; Model = 'Virtual Machine'
                        HardwareUuid = '65000000-0000-4000-8000-000000000001'; IdentitySha256 = '9' * 64
                    }
                }
                'CaptureBaselineDomain' {
                    $match = @($capturedExecution.BaselineObservations | Where-Object Domain -CEQ $arguments.Domain)
                    return [pscustomobject][ordered]@{ Availability = 'KNOWN'; StateDigest = $match[0].StateDigest }
                }
                'InspectResource' {
                    $resource = $capturedState.Resources[$arguments.ResourceType]
                    $capturedState.InspectCounts[$arguments.ResourceType]++
                    if ($capturedScenario -ceq 'Toctou' -and $resource.Sequence -eq 1 -and
                        $capturedState.InspectCounts[$arguments.ResourceType] -eq 2) { $resource.Generation++ }
                    $atomic = & $capturedBindingToken -Value ([pscustomobject][ordered]@{
                        ResourceType = $arguments.ResourceType; Exists = [bool]$resource.Exists
                        Generation = [int]$resource.Generation
                    })
                    $descriptor = $resource.Binding.TargetDescriptor
                    $isFile = @('Checkpoint', 'OwnerMarkedDirectory') -ccontains $arguments.ResourceType
                    return [pscustomobject][ordered]@{
                        Availability = 'KNOWN'; Exists = [bool]$resource.Exists
                        ExactTargetMatched = $true; OwnershipMatched = $true
                        MarkerSha256 = $(if ($isFile) { $descriptor.OwnerMarkerSha256 } else { 'NOT_APPLICABLE' })
                        PreexistingPathBindingToken = $(if ($isFile) { $descriptor.PreexistingPathBindingToken } else { 'NOT_APPLICABLE' })
                        AncestorBindingToken = $(if ($isFile) { $descriptor.AncestorBindingToken } else { 'NOT_APPLICABLE' })
                        TargetIsReparsePoint = $false; AncestorReparsePointCount = 0
                        ExistedBeforeOwnerRun = $false; AtomicIdentityToken = $atomic; StateDigest = $atomic
                    }
                }
                'MutateResource' {
                    $resource = $capturedState.Resources[$arguments.ResourceType]
                    $atomic = & $capturedBindingToken -Value ([pscustomobject][ordered]@{
                        ResourceType = $arguments.ResourceType; Exists = [bool]$resource.Exists
                        Generation = [int]$resource.Generation
                    })
                    if ($atomic -cne $arguments.ExpectedAtomicIdentityToken) { throw 'FAKE_TOCTOU' }
                    if (-not $resource.Exists) {
                        return [pscustomobject][ordered]@{ MutationAttempted = $false; Changed = $false; Outcome = 'COMPLETED'; FailureCode = '' }
                    }
                    $capturedState.MutationCalls++
                    $resource.Exists = $false
                    $resource.Generation++
                    if ($capturedScenario -ceq 'PartialFailure' -and $resource.Sequence -eq 2) { throw 'FAKE_PARTIAL_FAILURE' }
                    return [pscustomobject][ordered]@{ MutationAttempted = $true; Changed = $true; Outcome = 'COMPLETED'; FailureCode = '' }
                }
                'InspectFinalState' {
                    return [pscustomobject][ordered]@{
                        VmpState = 'KNOWN'; RebootState = 'KNOWN'; UninstallState = 'KNOWN'
                        CompensationState = 'KNOWN'; CleanupFailureCount = 0
                        UnknownMutationCount = 0; UnexpectedLedgerEntryCount = 0; SecretScanCount = 0
                    }
                }
                default { throw 'UNEXPECTED_FAKE_SYSTEM_OPERATION' }
            }
        }.GetNewClosure()
        return [pscustomobject]@{
            Interface = [pscustomobject][ordered]@{ Kind = 'FakeWindowsVmResetSystemV1'; Invoke = $invoke }
            State = $state
        }
    }

    function New-CddsiWindowsVmResetRequestFixture {
        param(
            [Parameter(Mandatory = $true)][string]$Provider,
            [Parameter(Mandatory = $true)][string]$Operation,
            [Parameter(Mandatory = $true)][string]$ResourceToken,
            [Parameter(Mandatory = $true)][System.Collections.IDictionary]$Arguments
        )
        $payload = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-vm-reset-provider-request-v1'
            Provider = $Provider; Operation = $Operation; ResourceToken = $ResourceToken
            Arguments = $Arguments
        }
        return [pscustomobject][ordered]@{
            SchemaVersion = $payload.SchemaVersion; ContractVersion = $payload.ContractVersion
            Provider = $payload.Provider; Operation = $payload.Operation
            ResourceToken = $payload.ResourceToken; Arguments = $payload.Arguments
            RequestBindingToken = Get-CddsiVmResetBindingToken -Value $payload
        }
    }

    function New-CddsiWindowsVmResetSimulationFixture {
        param([ValidateSet('Happy', 'NoChange', 'PartialFailure', 'Toctou')][string]$Scenario = 'Happy')
        $trust = New-CddsiWindowsVmResetTrustPolicyFixture -State PROVISIONED
        $deployment = New-CddsiWindowsVmResetDeploymentEvidenceFixture -TrustPolicy $trust
        $execution = New-CddsiWindowsVmResetExecutionFixture -TrustPolicy $trust
        $fake = New-CddsiWindowsVmResetFakeSystem -Execution $execution -Scenario $Scenario
        $sign = { param($digest) [Convert]::ToBase64String([Text.Encoding]::UTF8.GetBytes($digest)) }
        $signer = [pscustomobject][ordered]@{
            Kind = 'FakeWindowsVmResetSignerV1'; PublicKeySha256 = $trust.DeviceAttestationPublicKeySha256
            Sign = $sign
        }
        $runtime = New-CddsiWindowsVmResetSimulationRuntime -TrustPolicy $trust `
            -DeploymentEvidence $deployment -Policy $execution.Policy -Plan $execution.Plan `
            -OwnershipReceipts $execution.Receipts -ResourceBindings $execution.Bindings `
            -FakeSystemApi $fake.Interface -FakeSigner $signer
        return [pscustomobject]@{
            Trust = $trust; Deployment = $deployment; Execution = $execution
            Fake = $fake; Runtime = $runtime
        }
    }

    function Invoke-CddsiWindowsVmResetSimulationPreamble {
        param([Parameter(Mandatory = $true)]$Fixture)
        $execution = $Fixture.Execution
        $attest = New-CddsiWindowsVmResetRequestFixture -Provider Environment `
            -Operation AttestVmAcceptance -ResourceToken '<VM_RESET_ENVIRONMENT:VM_ACCEPTANCE>' `
            -Arguments ([ordered]@{
                RunId = '66000000-0000-4000-8000-000000000001'
                VmIdentity = $execution.Policy.VmIdentity; ImageSha256 = $execution.Policy.ImageSha256
                ResetPolicyDigest = $execution.Policy.ResetPolicyDigest
                PlanBindingToken = $execution.Plan.PlanBindingToken; PrincipalRole = 'VmTester'
            })
        Invoke-CddsiWindowsVmResetSimulationRequest -Runtime $Fixture.Runtime -Request $attest | Out-Null
        $baseline = New-CddsiWindowsVmResetRequestFixture -Provider Environment -Operation CaptureBaseline `
            -ResourceToken '<VM_RESET_BASELINE:BEFORE>' -Arguments ([ordered]@{
                Phase = 'Before'; ResetPolicyDigest = $execution.Policy.ResetPolicyDigest
                PlanBindingToken = $execution.Plan.PlanBindingToken
            })
        Invoke-CddsiWindowsVmResetSimulationRequest -Runtime $Fixture.Runtime -Request $baseline | Out-Null
        $preflights = @()
        for ($index = 0; $index -lt $execution.Policy.AllowList.Count; $index++) {
            $entry = $execution.Policy.AllowList[$index]
            $binding = $execution.Bindings[$index]
            $request = New-CddsiWindowsVmResetRequestFixture -Provider $entry.Provider `
                -Operation ValidateExactTarget -ResourceToken $entry.ResourceToken -Arguments ([ordered]@{
                    PlanBindingToken = $execution.Plan.PlanBindingToken; Sequence = [int]$entry.Sequence
                    OwnershipReceiptBindingToken = $entry.OwnershipReceiptBindingToken
                    TargetBindingToken = $binding.TargetBindingToken; TargetDescriptor = $binding.TargetDescriptor
                })
            $preflights += Invoke-CddsiWindowsVmResetSimulationRequest -Runtime $Fixture.Runtime -Request $request
        }
        return @($preflights)
    }

    function Invoke-CddsiWindowsVmResetSimulationAction {
        param(
            [Parameter(Mandatory = $true)]$Fixture,
            [Parameter(Mandatory = $true)][int]$Sequence,
            [Parameter(Mandatory = $true)]$Preflight
        )
        $action = $Fixture.Execution.Plan.Actions[$Sequence - 1]
        $binding = $Fixture.Execution.Bindings[$Sequence - 1]
        $request = New-CddsiWindowsVmResetRequestFixture -Provider $action.Provider `
            -Operation $action.Operation -ResourceToken $action.ResourceToken -Arguments ([ordered]@{
                Purpose = 'VmResetLiveMutation'; PlanBindingToken = $Fixture.Execution.Plan.PlanBindingToken
                Sequence = [int]$action.Sequence; ResourceId = $action.ResourceId
                ResourceType = $action.ResourceType
                OwnershipReceiptBindingToken = $action.OwnershipReceiptBindingToken
                TargetBindingToken = $binding.TargetBindingToken; TargetDescriptor = $binding.TargetDescriptor
                PreflightEvidenceDigest = $Preflight.EvidenceDigest
                RequireAtomicTargetRevalidation = $true
            })
        return Invoke-CddsiWindowsVmResetSimulationRequest -Runtime $Fixture.Runtime -Request $request
    }
}

Describe 'VM-only Windows deterministic reset provider' {
    It 'freezes three environment operations and five exact mutation classes in one hashed provider file' {
        $operations = @(Get-CddsiWindowsVmResetProviderOperationContract)
        $operations.Count | Should -Be 13
        @($operations | Where-Object Mutation).Count | Should -Be 5
        @($operations | Where-Object Mutation | ForEach-Object { '{0}:{1}:{2}' -f $_.Provider, $_.Operation, $_.ResourceType }) | Should -Be @(
            'Package:Remove:Package', 'Registry:DeleteValue:HkcuValue',
            'Credential:Delete:Credential', 'FileSystem:DeleteFile:Checkpoint',
            'FileSystem:DeleteDirectory:OwnerMarkedDirectory'
        )
        @($operations | ForEach-Object FileName | Select-Object -Unique) | Should -Be @('windows-vm-reset.ps1')
        $operations[0].Operation | Should -BeExactly 'AttestVmAcceptance'
        $operations[1].Operation | Should -BeExactly 'CaptureBaseline'
        $operations[-1].Operation | Should -BeExactly 'InspectFinalState'
    }

    It 'validates frozen v2 trust and signed deployment shapes but rejects unverified cryptography' {
        $policy = New-CddsiWindowsVmResetTrustPolicyFixture -State PROVISIONED
        $evidence = New-CddsiWindowsVmResetDeploymentEvidenceFixture -TrustPolicy $policy
        Test-CddsiWindowsVmResetTrustPolicy -Policy $policy | Should -BeTrue
        Test-CddsiWindowsVmResetDeploymentEvidence -Evidence $evidence -Policy $policy | Should -BeTrue
        Test-CddsiWindowsVmResetLiveAuthorization -Policy $policy -DeploymentEvidence $evidence `
            -VerificationTimeUtc '2030-01-01T00:00:02Z' | Should -BeFalse
        $tampered = Copy-CddsiWindowsVmResetFixture -Value $policy
        $tampered.CommandBindings[0].CommandFileSha256 = '1' * 64
        Test-CddsiWindowsVmResetTrustPolicy -Policy $tampered | Should -BeFalse
    }

    It 'rejects a caller self-signed authority that differs from the independent one-shot anchor' {
        $policy = New-CddsiWindowsVmResetTrustPolicyFixture -State PROVISIONED
        $evidence = New-CddsiWindowsVmResetDeploymentEvidenceFixture -TrustPolicy $policy
        $execution = New-CddsiWindowsVmResetExecutionFixture -TrustPolicy $policy
        $anchor = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-windows-vm-reset-provisioning-anchor-v1'
            ExpectedAuthorityPublicKeySha256 = $policy.DeviceAttestationAuthoritySha256
            ExpectedTrustPolicyBindingToken = $policy.PolicyBindingToken
            ExpectedVmIdentity = $policy.VmIdentity; ExpectedImageSha256 = $policy.ImageSha256
            ExpectedDisposableVmIdentitySha256 = $policy.DisposableVmIdentitySha256
            ExpectedVmManufacturer = $policy.ExpectedVmManufacturer; ExpectedVmModel = $policy.ExpectedVmModel
            ExpectedProviderFileSha256 = $policy.ProviderFileSha256
            SupervisorVmIdentityReceiptBindingToken = $evidence.SupervisorVmIdentityReceiptBindingToken
            OneShotGrantId = '67000000-0000-4000-8000-000000000001'
            OneShotExecutionNonce = '67000000-0000-4000-8000-000000000002'
            OneShotGrantFilePath = 'C:\ProgramData\cddsi-vm-operator\provisioning\grants\67000000-0000-4000-8000-000000000001.grant.json'
            OneShotGrantFileSha256 = '6' * 64
            OneShotGrantConsumerSid = 'S-1-5-21-1000-1000-1000-1001'
            ExpectedCycleId = $execution.Plan.CycleId
            ExpectedResetPolicyDigest = $execution.Policy.ResetPolicyDigest
            ExpectedPlanBindingToken = $execution.Plan.PlanBindingToken
            ExpectedOwnershipSetDigest = Get-CddsiVmResetBindingToken -Value @($execution.Receipts)
            ExpectedResourceBindingSetDigest = Get-CddsiVmResetBindingToken -Value @($execution.Bindings)
            ExpectedControlAuthenticationDigest = '5' * 64
            NotBeforeUtc = '2030-01-01T00:00:00Z'; ExpiresAtUtc = '2030-01-01T01:00:00Z'
            AnchorBindingToken = ''
        }
        $anchorPayload = [pscustomobject][ordered]@{}
        foreach ($name in @($anchor.PSObject.Properties.Name | Where-Object { $_ -cne 'AnchorBindingToken' })) {
            Add-Member -InputObject $anchorPayload -NotePropertyName $name -NotePropertyValue $anchor.$name
        }
        $anchor.AnchorBindingToken = Get-CddsiVmResetBindingToken -Value $anchorPayload
        Test-CddsiWindowsVmResetTrustAgainstAnchorInternal -Anchor $anchor -TrustPolicy $policy `
            -DeploymentEvidence $evidence -Policy $execution.Policy -Plan $execution.Plan `
            -OwnershipReceipts $execution.Receipts -ResourceBindings $execution.Bindings `
            -ControlAuthenticationDigest ('5' * 64) -VerificationTimeUtc '2030-01-01T00:00:02Z' | Should -BeTrue

        $grant = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-windows-vm-reset-one-shot-grant-v1'
            OneShotGrantId = $anchor.OneShotGrantId
            ExecutionNonce = $anchor.OneShotExecutionNonce
            ExpectedCycleId = $execution.Plan.CycleId
            ExpectedResetPolicyDigest = $execution.Policy.ResetPolicyDigest
            ExpectedPlanBindingToken = $execution.Plan.PlanBindingToken
            ExpectedOwnershipSetDigest = Get-CddsiVmResetBindingToken -Value @($execution.Receipts)
            ExpectedResourceBindingSetDigest = Get-CddsiVmResetBindingToken -Value @($execution.Bindings)
            ExpectedControlAuthenticationDigest = '5' * 64
            NotBeforeUtc = '2030-01-01T00:00:00Z'
            ExpiresAtUtc = '2030-01-01T01:00:00Z'
            GrantBindingToken = ''
        }
        $grant.GrantBindingToken = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetOneShotGrantPayloadInternal -Grant $grant
        )
        Test-CddsiWindowsVmResetOneShotGrantInternal -Grant $grant -Anchor $anchor `
            -Policy $execution.Policy -Plan $execution.Plan `
            -OwnershipReceipts $execution.Receipts -ResourceBindings $execution.Bindings `
            -ControlAuthenticationDigest ('5' * 64) `
            -VerificationTimeUtc '2030-01-01T00:00:02Z' | Should -BeTrue
        $replayedGrant = Copy-CddsiWindowsVmResetFixture -Value $grant
        $replayedGrant.ExecutionNonce = '67000000-0000-4000-8000-000000000003'
        $replayedGrant.GrantBindingToken = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetOneShotGrantPayloadInternal -Grant $replayedGrant
        )
        Test-CddsiWindowsVmResetOneShotGrantInternal -Grant $replayedGrant -Anchor $anchor `
            -Policy $execution.Policy -Plan $execution.Plan `
            -OwnershipReceipts $execution.Receipts -ResourceBindings $execution.Bindings `
            -ControlAuthenticationDigest ('5' * 64) `
            -VerificationTimeUtc '2030-01-01T00:00:02Z' | Should -BeFalse

        $selfSigned = New-CddsiWindowsVmResetTrustPolicyFixture -State PROVISIONED
        $otherAuthority = Get-CddsiWindowsVmResetFixtureBlob -Byte 99
        $selfSigned.AuthorityPublicKeyCngBlobBase64 = $otherAuthority.Base64
        $selfSigned.DeviceAttestationAuthoritySha256 = $otherAuthority.Sha256
        $selfSigned.PolicyBindingToken = Get-CddsiVmResetBindingToken -Value (
            Get-CddsiWindowsVmResetPolicyPayloadInternal -Policy $selfSigned
        )
        $selfEvidence = New-CddsiWindowsVmResetDeploymentEvidenceFixture -TrustPolicy $selfSigned
        Test-CddsiWindowsVmResetTrustAgainstAnchorInternal -Anchor $anchor -TrustPolicy $selfSigned `
            -DeploymentEvidence $selfEvidence -Policy $execution.Policy -Plan $execution.Plan `
            -OwnershipReceipts $execution.Receipts -ResourceBindings $execution.Bindings `
            -ControlAuthenticationDigest ('5' * 64) -VerificationTimeUtc '2030-01-01T00:00:02Z' | Should -BeFalse
    }

    It 'accepts a non-reparse SYSTEM-owned provisioning directory with only trusted mutation access' {
        $directory = [IO.Directory]::CreateDirectory((Join-Path $TestDrive 'provisioning-safe')).FullName
        $script:ProvisioningDirectoryAcl = New-CddsiWindowsVmResetDirectoryAclFixture -Rules @(
            [pscustomobject]@{
                Sid = 'S-1-5-18'
                Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
            },
            [pscustomobject]@{
                Sid = 'S-1-5-32-544'
                Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
            },
            [pscustomobject]@{
                Sid = 'S-1-5-32-545'
                Rights = [System.Security.AccessControl.FileSystemRights]::ReadAndExecute
            }
        )
        Mock Get-Acl { $script:ProvisioningDirectoryAcl }

        {
            Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
                -Path $directory -Purpose ProvisioningAnchor
        } | Should -Not -Throw
        {
            Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
                -Path $directory -Purpose OneShotGrant
        } | Should -Not -Throw
        Should -Invoke Get-Acl -Times 2 -Exactly
    }

    It 'rejects a reparse provisioning-anchor parent before reading its ACL' {
        $directory = [IO.Directory]::CreateDirectory((Join-Path $TestDrive 'provisioning-reparse')).FullName
        Mock Test-CddsiWindowsVmResetReparseInternal { $true }
        Mock Get-Acl { throw 'ACL access must not run for a reparse directory' }

        {
            Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
                -Path $directory -Purpose ProvisioningAnchor
        } | Should -Throw '*PROVISIONING_ANCHOR_DIRECTORY_REPARSE_POINT*'
        Should -Invoke Get-Acl -Times 0 -Exactly
    }

    It 'rejects a provisioning-anchor parent not owned exactly by SYSTEM' {
        $directory = [IO.Directory]::CreateDirectory((Join-Path $TestDrive 'provisioning-owner')).FullName
        $script:ProvisioningDirectoryAcl = New-CddsiWindowsVmResetDirectoryAclFixture `
            -OwnerSid 'S-1-5-32-544'
        Mock Get-Acl { $script:ProvisioningDirectoryAcl }

        {
            Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
                -Path $directory -Purpose ProvisioningAnchor
        } | Should -Throw '*PROVISIONING_ANCHOR_DIRECTORY_OWNER_INVALID*'
    }

    It 'rejects non-SYSTEM and non-Administrators mutation access on the provisioning-anchor parent' {
        $directory = [IO.Directory]::CreateDirectory((Join-Path $TestDrive 'provisioning-acl')).FullName
        $script:ProvisioningDirectoryAcl = New-CddsiWindowsVmResetDirectoryAclFixture -Rules @(
            [pscustomobject]@{
                Sid = 'S-1-5-18'
                Rights = [System.Security.AccessControl.FileSystemRights]::FullControl
            },
            [pscustomobject]@{
                Sid = 'S-1-5-32-545'
                Rights = [System.Security.AccessControl.FileSystemRights]::WriteData
            }
        )
        Mock Get-Acl { $script:ProvisioningDirectoryAcl }

        {
            Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal `
                -Path $directory -Purpose ProvisioningAnchor
        } | Should -Throw '*PROVISIONING_ANCHOR_DIRECTORY_ACL_TOO_BROAD*'
    }

    It 'keeps TestSafe and DryRun plan-only with zero real provider or Windows calls' {
        Mock Get-CimInstance { throw 'must not run' }
        Mock Get-AppxPackage { throw 'must not run' }
        Mock Remove-AppxPackage { throw 'must not run' }
        Mock Get-CddsiWindowsVmResetFileSha256Internal { throw 'file access must not run' }
        Mock Get-CddsiWindowsVmResetProvisioningAnchorInternal { throw 'anchor access must not run' }
        Mock Open-CddsiWindowsVmResetOneShotGrantInternal { throw 'grant access must not run' }
        Mock Initialize-CddsiWindowsVmResetGrantNativeInternal { throw 'grant native access must not run' }
        Mock Get-CddsiWindowsVmResetVmIdentityInternal { throw 'identity access must not run' }
        Mock Get-CddsiWindowsVmResetResourceObservationInternal { throw 'resource access must not run' }
        Mock Initialize-CddsiWindowsVmResetCredentialNativeInternal { throw 'credential access must not run' }
        Mock Invoke-CddsiWindowsVmResetGitVersionInternal { throw 'process access must not run' }
        Mock Get-CddsiWindowsVmResetVmpStateInternal { throw 'feature access must not run' }
        Mock Invoke-CddsiWindowsVmResetResourceMutationInternal { throw 'mutation must not run' }
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $policy = New-CddsiWindowsVmResetTrustPolicyFixture -State PROVISIONED
            $result = New-CddsiWindowsVmResetProvider -TrustPolicy $policy -Mode $mode
            $result.Status | Should -BeExactly 'ACTION_REQUIRED'
            $result.ErrorCode | Should -BeExactly 'VM_ACCEPTANCE_LIVE_REQUIRED'
            $result.Changed | Should -BeFalse
            $result.Data.ProviderAdapter | Should -BeNullOrEmpty
            $result.Data.RealAccessPerformed | Should -BeFalse
            $result.Data.ProviderCallCount | Should -Be 0
        }
        Should -Invoke Get-CimInstance -Times 0 -Exactly
        Should -Invoke Get-AppxPackage -Times 0 -Exactly
        Should -Invoke Remove-AppxPackage -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetFileSha256Internal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetProvisioningAnchorInternal -Times 0 -Exactly
        Should -Invoke Open-CddsiWindowsVmResetOneShotGrantInternal -Times 0 -Exactly
        Should -Invoke Initialize-CddsiWindowsVmResetGrantNativeInternal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetVmIdentityInternal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetResourceObservationInternal -Times 0 -Exactly
        Should -Invoke Initialize-CddsiWindowsVmResetCredentialNativeInternal -Times 0 -Exactly
        Should -Invoke Invoke-CddsiWindowsVmResetGitVersionInternal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetVmpStateInternal -Times 0 -Exactly
        Should -Invoke Invoke-CddsiWindowsVmResetResourceMutationInternal -Times 0 -Exactly
    }

    It 'simulates all five mutations with JIT preflight postcondition and signed receipts without a real provider call' {
        $fixture = New-CddsiWindowsVmResetSimulationFixture -Scenario Happy
        $preflights = Invoke-CddsiWindowsVmResetSimulationPreamble -Fixture $fixture
        $results = @()
        for ($sequence = 1; $sequence -le 5; $sequence++) {
            $results += Invoke-CddsiWindowsVmResetSimulationAction -Fixture $fixture `
                -Sequence $sequence -Preflight $preflights[$sequence - 1]
        }
        @($results | Where-Object Outcome -CNE 'COMPLETED').Count | Should -Be 0
        @($results | Where-Object { -not $_.Changed }).Count | Should -Be 0
        @($results | Where-Object { -not $_.AtomicPreconditionValidated -or -not $_.ExactTargetAbsentAfter }).Count | Should -Be 0
        @($results | Where-Object { $_.SignedReceiptDigest -notmatch '^[a-f0-9]{64}$' }).Count | Should -Be 0
        @($results | Where-Object { [string]::IsNullOrWhiteSpace($_.ReceiptSignatureBase64) }).Count | Should -Be 0
        $fixture.Fake.State.MutationCalls | Should -Be 5
        $fixture.Runtime.RealProviderCallCount | Should -Be 0
    }

    It 'proves idempotent no-change actions without invoking a fake mutation primitive' {
        $fixture = New-CddsiWindowsVmResetSimulationFixture -Scenario NoChange
        $preflights = Invoke-CddsiWindowsVmResetSimulationPreamble -Fixture $fixture
        $results = for ($sequence = 1; $sequence -le 5; $sequence++) {
            Invoke-CddsiWindowsVmResetSimulationAction -Fixture $fixture `
                -Sequence $sequence -Preflight $preflights[$sequence - 1]
        }
        @($results | Where-Object Changed).Count | Should -Be 0
        @($results | Where-Object Outcome -CNE 'COMPLETED').Count | Should -Be 0
        $fixture.Fake.State.MutationCalls | Should -Be 0
        $fixture.Runtime.RealProviderCallCount | Should -Be 0
    }

    It 'records confirmed prior change and ambiguous partial failure instead of reporting clean' {
        $fixture = New-CddsiWindowsVmResetSimulationFixture -Scenario PartialFailure
        $preflights = Invoke-CddsiWindowsVmResetSimulationPreamble -Fixture $fixture
        $first = Invoke-CddsiWindowsVmResetSimulationAction -Fixture $fixture -Sequence 1 -Preflight $preflights[0]
        $second = Invoke-CddsiWindowsVmResetSimulationAction -Fixture $fixture -Sequence 2 -Preflight $preflights[1]
        $first.Outcome | Should -BeExactly 'COMPLETED'
        $first.Changed | Should -BeTrue
        $second.Outcome | Should -BeExactly 'AMBIGUOUS'
        $second.Changed | Should -BeTrue
        $fixture.Runtime.RealProviderCallCount | Should -Be 0
    }

    It 'blocks a TOCTOU state change before mutation and emits a failed signed receipt' {
        $fixture = New-CddsiWindowsVmResetSimulationFixture -Scenario Toctou
        $preflights = Invoke-CddsiWindowsVmResetSimulationPreamble -Fixture $fixture
        $result = Invoke-CddsiWindowsVmResetSimulationAction -Fixture $fixture -Sequence 1 -Preflight $preflights[0]
        $result.Outcome | Should -BeExactly 'FAILED'
        $result.FailureCode | Should -BeExactly 'RESOURCE_TOCTOU_DETECTED'
        $result.AtomicPreconditionValidated | Should -BeFalse
        $fixture.Fake.State.MutationCalls | Should -Be 0
        $fixture.Runtime.RealProviderCallCount | Should -Be 0
    }

    It 'rejects dangerous target paths and direct forged LiveWindows core or mutation calls before real access' {
        $fixture = New-CddsiWindowsVmResetSimulationFixture
        $danger = Copy-CddsiWindowsVmResetFixture -Value $fixture.Execution.Bindings[4].TargetDescriptor
        $danger.Path = 'C:\'
        Test-CddsiVmResetLiveTargetDescriptor -Descriptor $danger -ResourceType OwnerMarkedDirectory `
            -OwnerRunId $fixture.Execution.Bindings[4].OwnerRunId | Should -BeFalse
        $registry = Copy-CddsiWindowsVmResetFixture -Value $fixture.Execution.Bindings[1].TargetDescriptor
        $registry.KeyPath = 'SOFTWARE\Microsoft\Windows\CurrentVersion\Run'
        Test-CddsiVmResetLiveTargetDescriptor -Descriptor $registry -ResourceType HkcuValue `
            -OwnerRunId $fixture.Execution.Bindings[1].OwnerRunId | Should -BeFalse

        Mock Get-CimInstance { throw 'real access reached' }
        Mock Get-AppxPackage { throw 'real access reached' }
        Mock Remove-AppxPackage { throw 'real mutation reached' }
        Mock Get-CddsiWindowsVmResetFileSha256Internal { throw 'real file access reached' }
        Mock Get-CddsiWindowsVmResetProvisioningAnchorInternal { throw 'real anchor access reached' }
        Mock Open-CddsiWindowsVmResetOneShotGrantInternal { throw 'real grant access reached' }
        Mock Initialize-CddsiWindowsVmResetGrantNativeInternal { throw 'real grant native access reached' }
        Mock Get-CddsiWindowsVmResetVmIdentityInternal { throw 'real identity access reached' }
        Mock Get-CddsiWindowsVmResetResourceObservationInternal { throw 'real resource access reached' }
        Mock Initialize-CddsiWindowsVmResetCredentialNativeInternal { throw 'real credential access reached' }
        Mock Invoke-CddsiWindowsVmResetGitVersionInternal { throw 'real process access reached' }
        Mock Get-CddsiWindowsVmResetVmpStateInternal { throw 'real feature access reached' }
        $forgedRuntime = [pscustomobject][ordered]@{
            ExecutionKind = 'LiveWindows'; SystemApi = [pscustomobject]@{ Kind = 'WindowsVmResetNativeV2' }
            UnexpectedRequestCount = 0; ProviderCallCount = 0; Attested = $false
            Policy = $fixture.Execution.Policy; Plan = $fixture.Execution.Plan
            ActiveMutationPermit = $null; NextActionSequence = 1
            MutationPermitSecret = '68000000-0000-4000-8000-000000000003'
        }
        $request = New-CddsiWindowsVmResetRequestFixture -Provider Environment `
            -Operation AttestVmAcceptance -ResourceToken '<VM_RESET_ENVIRONMENT:VM_ACCEPTANCE>' `
            -Arguments ([ordered]@{
                RunId = '68000000-0000-4000-8000-000000000001'
                VmIdentity = $fixture.Execution.Policy.VmIdentity
                ImageSha256 = $fixture.Execution.Policy.ImageSha256
                ResetPolicyDigest = $fixture.Execution.Policy.ResetPolicyDigest
                PlanBindingToken = $fixture.Execution.Plan.PlanBindingToken; PrincipalRole = 'VmTester'
            })
        { Invoke-CddsiWindowsVmResetProviderRequestCoreInternal -Runtime $forgedRuntime -Request $request } | Should -Throw '*FACTORY_CAPABILITY*'
        Add-Member -InputObject $forgedRuntime -NotePropertyName FactoryCapability `
            -NotePropertyValue ([pscustomobject]@{})
        { Invoke-CddsiWindowsVmResetProviderRequestCoreInternal -Runtime $forgedRuntime -Request $request } | Should -Throw '*FACTORY_CAPABILITY*'
        { Invoke-CddsiWindowsVmResetResourceMutationInternal -Runtime $forgedRuntime `
            -ResourceToken '<VM_RESET:ARBITRARY_PACKAGE>' `
            -ExpectedAtomicIdentityToken ('1' * 64) } | Should -Throw '*MUTATION_PERMIT*'
        { Remove-CddsiWindowsVmResetOwnedDirectoryInternal -Runtime $forgedRuntime `
            -ResourceToken '<VM_RESET:ARBITRARY_DIRECTORY>' `
            -MutationPermit ([pscustomobject]@{
                Used = $true; DirectoryDeletionActivated = $true
                ResourceToken = '<VM_RESET:ARBITRARY_DIRECTORY>'
            }) } | Should -Throw '*MUTATION_PERMIT*'
        Should -Invoke Get-CimInstance -Times 0 -Exactly
        Should -Invoke Get-AppxPackage -Times 0 -Exactly
        Should -Invoke Remove-AppxPackage -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetFileSha256Internal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetProvisioningAnchorInternal -Times 0 -Exactly
        Should -Invoke Open-CddsiWindowsVmResetOneShotGrantInternal -Times 0 -Exactly
        Should -Invoke Initialize-CddsiWindowsVmResetGrantNativeInternal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetVmIdentityInternal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetResourceObservationInternal -Times 0 -Exactly
        Should -Invoke Initialize-CddsiWindowsVmResetCredentialNativeInternal -Times 0 -Exactly
        Should -Invoke Invoke-CddsiWindowsVmResetGitVersionInternal -Times 0 -Exactly
        Should -Invoke Get-CddsiWindowsVmResetVmpStateInternal -Times 0 -Exactly
    }

    It 'keeps all real Windows primitives in the one development-only provider file behind capability assertions' {
        $providerPath = Join-Path $script:RepoRoot 'operator\fast-lane\providers\windows-vm-reset.ps1'
        $dispatcherPath = Join-Path $script:RepoRoot 'operator\fast-lane\invoke-vm-reset-live.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($providerPath, [ref]$tokens, [ref]$errors)
        @($errors).Count | Should -Be 0
        $commandNames = @($ast.FindAll({ param($node) $node -is [System.Management.Automation.Language.CommandAst] }, $true) | ForEach-Object { $_.GetCommandName() })
        foreach ($required in @('Get-CimInstance', 'Get-AppxPackage', 'Remove-AppxPackage', 'Get-WindowsOptionalFeature', 'Add-Type', 'Get-Acl')) {
            $commandNames | Should -Contain $required
        }
        $dispatcherText = [IO.File]::ReadAllText($dispatcherPath)
        foreach ($primitive in @('Remove-AppxPackage', 'CredDeleteW', 'DeleteValue(', '[IO.File]::Delete(', '[IO.Directory]::Delete(')) {
            $dispatcherText | Should -Not -Match ([regex]::Escape($primitive))
        }
        $providerText = [IO.File]::ReadAllText($providerPath)
        $providerText | Should -Match 'Get-CddsiWindowsVmResetFactoryCapabilityInternal -Runtime \$Runtime'
        $providerText | Should -Match 'Assert-CddsiWindowsVmResetFactoryCapabilityInternal -Capability \$factoryCapability'
        $providerText | Should -Match 'Assert-CddsiWindowsVmResetActiveMutationPermitInternal'
        $providerText | Should -Match 'Get-CddsiWindowsVmResetAuthorizedResourceInternal -Runtime \$Runtime'
        $providerText | Should -Match 'ExpectedOwnershipSetDigest'
        $providerText | Should -Match 'ExpectedResourceBindingSetDigest'
        $providerText | Should -Match 'ExpectedControlAuthenticationDigest'
        $providerText | Should -Match 'OneShotExecutionNonce'
        $providerText | Should -Match 'OneShotGrantFileSha256'
        $providerText | Should -Match 'ONE_SHOT_GRANT_CONSUMER_ADMINISTRATOR_FORBIDDEN'
        $providerText | Should -Match 'ONE_SHOT_GRANT_DIRECTORY_OWNER_INVALID'
        $providerText | Should -Match 'ONE_SHOT_GRANT_DIRECTORY_ACL_TOO_BROAD'
        $providerText | Should -Match 'PROVISIONING_ANCHOR_DIRECTORY_REPARSE_POINT'
        $providerText | Should -Match 'PROVISIONING_ANCHOR_DIRECTORY_OWNER_INVALID'
        $providerText | Should -Match 'PROVISIONING_ANCHOR_DIRECTORY_ACL_TOO_BROAD'
        $directoryGuardAst = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal'
        }, $true))[0]
        $anchorReaderAst = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Get-CddsiWindowsVmResetProvisioningAnchorInternal'
        }, $true))[0]
        $grantReaderAst = @($ast.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Open-CddsiWindowsVmResetOneShotGrantInternal'
        }, $true))[0]
        $directoryGuardAst.Extent.Text | Should -Match '\$directoryAcl = Get-Acl -LiteralPath \$Path'
        $directoryGuardAst.Extent.Text | Should -Match "'S-1-5-18'"
        $directoryGuardAst.Extent.Text | Should -Match "'S-1-5-32-544'"
        $anchorReaderAst.Extent.Text | Should -Match `
            'Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal\s+`\s+-Path \$anchorDirectory -Purpose ProvisioningAnchor'
        $grantReaderAst.Extent.Text | Should -Match `
            'Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal\s+`\s+-Path \$grantDirectory -Purpose OneShotGrant'
        $anchorReaderAst.Extent.Text.IndexOf(
            'Assert-CddsiWindowsVmResetSystemOwnedProvisioningDirectoryInternal',
            [StringComparison]::Ordinal
        ) | Should -BeLessThan $anchorReaderAst.Extent.Text.IndexOf(
            '[IO.File]::Exists($path)', [StringComparison]::Ordinal
        )
        $providerText | Should -Match 'CreateFile\('
        $providerText | Should -Match 'desiredAccess, UInt32 shareMode'
        $providerText | Should -Match 'path, GENERIC_READ \| DELETE, 0,'
        $providerText | Should -Match '\$grantHandle\.CommitDelete\(\)'
        $providerText.IndexOf('$grantHandle.CommitDelete()', [StringComparison]::Ordinal) | `
            Should -BeLessThan $providerText.IndexOf(
                '$script:CddsiWindowsVmResetAuthorizedRuntimes[$envelope.RuntimeHandle] = $runtime',
                [StringComparison]::Ordinal
            )
    }
}
