Describe 'DevelopmentOnly deterministic Fast Lane Git outbox runtime' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        . (Join-Path $script:RepoRoot 'lib\common.ps1')
        . (Join-Path $script:RepoRoot 'lib\vm-test-relay.ps1')
        . (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-synthetic-rehearsal.ps1')
        $script:RunnerPath = Join-Path $script:RepoRoot 'operator\fast-lane\invoke-git-outbox.ps1'
        . $script:RunnerPath
        $trustedGitPath = Get-Variable -Name CddsiTrustedHarnessGitExecutablePath `
            -Scope Global -ErrorAction SilentlyContinue
        $trustedGitSha = Get-Variable -Name CddsiTrustedHarnessGitGrantSha256 `
            -Scope Global -ErrorAction SilentlyContinue
        $script:GitExecutable = if ($null -ne $trustedGitPath) {
            [string]$trustedGitPath.Value
        } else {
            (Get-Command git.exe -CommandType Application -ErrorAction Stop).Source
        }
        $script:GitExecutableSha256 = (Get-FileHash -LiteralPath $script:GitExecutable -Algorithm SHA256).Hash.ToLowerInvariant()
        if ($null -ne $trustedGitSha -and $script:GitExecutableSha256 -cne [string]$trustedGitSha.Value) {
            throw 'Trusted harness Git SHA-256 binding drifted.'
        }
        $script:RunnerSha256 = (Get-FileHash -LiteralPath $script:RunnerPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $script:FixtureRoots = [Collections.ArrayList]::new()
        $script:OutboxFixtureTemplateRoot = $null
        $script:OutboxFixtureTemplateGenesis = $null

        function Invoke-FixtureGit {
            param([Parameter(Mandatory = $true)][string[]]$Arguments)
            $output = & $script:GitExecutable -c core.hooksPath=NUL -c credential.helper= @Arguments 2>&1
            if ($LASTEXITCODE -ne 0) { throw ('Fixture Git failed: ' + (($output | ForEach-Object { [string]$_ }) -join ' ')) }
            return @($output | ForEach-Object { [string]$_ })
        }

        function Initialize-OutboxFixtureTemplate {
            if (-not [string]::IsNullOrWhiteSpace($script:OutboxFixtureTemplateRoot)) { return }
            $root = Join-Path ([IO.Path]::GetTempPath()) ('cddsi-test-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($root)
            $owner = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-local-transport-owner-v1'
                Owner = 'CDDsiFastLaneGitOutboxTests'; SyntheticOnly = $true
            }
            [IO.File]::WriteAllText(
                (Join-Path $root '.cddsi-owner.json'),
                ((ConvertTo-CddsiVmTestRelayCanonicalJson $owner) + "`n"),
                (New-Object Text.UTF8Encoding($false)))
            [void]$script:FixtureRoots.Add($root)
            $work = Join-Path $root 'writer'
            $remote = Join-Path $root 'control.git'
            [void](Invoke-FixtureGit @('init', '--quiet', $work))
            [void][IO.Directory]::CreateDirectory((Join-Path $work 'outbox'))
            [IO.File]::WriteAllText(
                (Join-Path $work 'README.md'), "fixture`n", (New-Object Text.UTF8Encoding($false)))
            [IO.File]::WriteAllText(
                (Join-Path $work 'outbox\README.md'), "outbox`n", (New-Object Text.UTF8Encoding($false)))
            [void](Invoke-FixtureGit @('-C', $work, 'add', 'README.md', 'outbox/README.md'))
            [void](Invoke-FixtureGit @(
                '-C', $work, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@invalid',
                'commit', '--quiet', '-m', 'genesis'
            ))
            [void](Invoke-FixtureGit @('-C', $work, 'branch', '-M', 'main'))
            [void](Invoke-FixtureGit @('init', '--bare', '--quiet', $remote))
            [void](Invoke-FixtureGit @('-C', $work, 'remote', 'add', 'origin', '../control.git'))
            [void](Invoke-FixtureGit @('-C', $work, 'push', '--quiet', '-u', 'origin', 'main'))
            $script:OutboxFixtureTemplateGenesis = (
                [string](Invoke-FixtureGit @('-C', $work, 'rev-parse', 'HEAD') | Select-Object -First 1)
            ).Trim()
            $script:OutboxFixtureTemplateRoot = $root
        }

        function New-OutboxFixture {
            param(
                [long]$NumericId = 101,
                [ValidateSet('host-to-vm', 'vm-to-host')][string]$Direction = 'host-to-vm'
            )
            $root = Join-Path ([IO.Path]::GetTempPath()) ('cddsi-test-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($root)
            $owner = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-local-transport-owner-v1'
                Owner = 'CDDsiFastLaneGitOutboxTests'; SyntheticOnly = $true
            }
            $marker = Join-Path $root '.cddsi-owner.json'
            [IO.File]::WriteAllText($marker, ((ConvertTo-CddsiVmTestRelayCanonicalJson $owner) + "`n"), (New-Object Text.UTF8Encoding($false)))
            [void]$script:FixtureRoots.Add($root)
            # Keep the synthetic plane roots short enough that the required
            # state-root leaf still exercises Git long-path support inside the
            # already nested isolated quality sandbox.
            $productRoot = Join-Path $root 'p'
            $operatorWorkspaceRoot = Join-Path $root 'o'
            [void][IO.Directory]::CreateDirectory($productRoot)
            [void][IO.Directory]::CreateDirectory($operatorWorkspaceRoot)
            $workspaceOwner = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-operator-workspace-owner-v1'
                Owner = 'CDDsiFastLaneOperatorWorkspace'; OperatorPlaneOnly = $true
                ProductRootPathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $productRoot
                OperatorWorkspacePathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $operatorWorkspaceRoot
            }
            [IO.File]::WriteAllText(
                (Join-Path $operatorWorkspaceRoot '.cddsi-owner.json'),
                ((ConvertTo-CddsiVmTestRelayCanonicalJson $workspaceOwner) + "`n"),
                (New-Object Text.UTF8Encoding($false)))
            Initialize-OutboxFixtureTemplate
            Copy-Item -LiteralPath (Join-Path $script:OutboxFixtureTemplateRoot 'writer') `
                -Destination $root -Recurse -Force
            Copy-Item -LiteralPath (Join-Path $script:OutboxFixtureTemplateRoot 'control.git') `
                -Destination $root -Recurse -Force
            $work = Join-Path $root 'writer'
            $remote = Join-Path $root 'control.git'
            $genesis = $script:OutboxFixtureTemplateGenesis
            $identity = 'synthetic/' + $Direction
            $authority = 'synthetic/CddsiFastLaneProtectionAuthority'
            $policySha = '6' * 64
            $evidence = [pscustomobject][ordered]@{
                SchemaVersion = 2
                ContractVersion = 'cddsi-fast-lane-control-repo-protection-v3'
                RepositoryIdentity = $identity
                RepositoryNumericId = $NumericId
                RepositoryNodeId = ('LOCAL_NODE_' + $NumericId)
                Visibility = 'PUBLIC'
                RemoteRef = 'refs/heads/main'
                ForcePushAllowed = $false
                BranchDeletionAllowed = $false
                HistoryRewriteAllowed = $false
                Authority = $authority
                ProtectionPolicySha256 = $policySha
                PreviousReceiptSha256 = $null
                ObservedAtUtc = '2030-01-01T00:00:00.0000000Z'
                ValidUntilUtc = '2030-01-01T00:30:00.0000000Z'
                ReceiptId = ('11111111-1111-4111-8111-{0:d12}' -f $NumericId)
            }
            $evidenceSha = Get-CddsiSupplyChainTextBindingToken -Text `
                (ConvertTo-CddsiVmTestRelayCanonicalJson $evidence)
            $protectionAuthorityBindingToken = '5' * 64
            $protectionTrustRoot = Join-Path $operatorWorkspaceRoot 'control-protection-trust'
            [void][IO.Directory]::CreateDirectory($protectionTrustRoot)
            $protectionRootMarker = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-protection-authority-trust-root-v1'
                Owner = 'CDDsiFastLaneProtectionAuthorityTrust'; OperatorPlaneOnly = $true
                ProtectionAuthority = $authority
                ProtectionAuthorityBindingToken = $protectionAuthorityBindingToken
                ProductRootPathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $productRoot
                OperatorWorkspacePathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $operatorWorkspaceRoot
            }
            Write-CddsiFastLaneCanonicalFile -Path (Join-Path $protectionTrustRoot '.cddsi-owner.json') `
                -Value $protectionRootMarker
            $protectionAssertion = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-protection-authority-assertion-v1'
                ExternallyVerified = $true; ProtectionAuthority = $authority
                ProtectionAuthorityBindingToken = $protectionAuthorityBindingToken
                ProtectionPolicySha256 = $policySha; ProtectionEvidenceSha256 = $evidenceSha
                RepositoryIdentity = $identity; RepositoryNumericId = $NumericId
                RepositoryNodeId = ('LOCAL_NODE_' + $NumericId); RemoteRef = 'refs/heads/main'
                PreviousReceiptSha256 = $null; ObservedAtUtc = $evidence.ObservedAtUtc
                ValidUntilUtc = $evidence.ValidUntilUtc; ReceiptId = $evidence.ReceiptId
            }
            $protectionAssertionPath = Join-Path $protectionTrustRoot ('protection-' + $evidence.ReceiptId + '.json')
            Write-CddsiFastLaneCanonicalFile -Path $protectionAssertionPath -Value $protectionAssertion
            return [pscustomobject]@{
                Root = $root; Work = $work; Remote = $remote; Genesis = $genesis; Identity = $identity
                ProductRoot = $productRoot; OperatorWorkspaceRoot = $operatorWorkspaceRoot
                StateRoot = Join-Path $operatorWorkspaceRoot ('fl-' + [guid]::NewGuid().ToString('N'))
                Evidence = $evidence; Direction = $Direction
                ReadCredentialProfileId = 'synthetic.' + $Direction + '.read'
                WriteCredentialProfileId = 'synthetic.' + $Direction + '.write'
                AuthenticatedSenderRole = $(if ($Direction -ceq 'host-to-vm') { 'HostCoordinator' } else { 'VmTester' })
                ExpectedProtectionAuthority = $authority; ExpectedProtectionPolicySha256 = $policySha
                EvidenceSha256 = $evidenceSha; ProtectionTrustRoot = $protectionTrustRoot
                ProtectionAuthorityAssertionPath = $protectionAssertionPath
                ExpectedProtectionAuthorityAssertionSha256 = (Get-FileHash $protectionAssertionPath -Algorithm SHA256).Hash.ToLowerInvariant()
                ExpectedProtectionAuthorityBindingToken = $protectionAuthorityBindingToken
            }
        }

        function Get-OutboxParameters {
            param(
                [Parameter(Mandatory = $true)]$Fixture,
                [ValidateSet('Poll', 'Publish')][string]$Operation = 'Poll'
            )
            return @{
                StateRoot = $Fixture.StateRoot
                ProductRoot = $Fixture.ProductRoot
                OperatorWorkspaceRoot = $Fixture.OperatorWorkspaceRoot
                GitExecutable = $script:GitExecutable
                GitExecutableSha256 = $script:GitExecutableSha256
                RunnerSha256 = $script:RunnerSha256
                RepositoryUri = $Fixture.Remote
                RepositoryIdentity = $Fixture.Identity
                ProtectionEvidence = $Fixture.Evidence
                ProtectionEvidenceSha256 = $Fixture.EvidenceSha256
                ExpectedRepositoryNumericId = [long]$Fixture.Evidence.RepositoryNumericId
                ExpectedRepositoryNodeId = [string]$Fixture.Evidence.RepositoryNodeId
                ExpectedRepositoryVisibility = 'PUBLIC'
                ExpectedProtectionAuthority = $Fixture.ExpectedProtectionAuthority
                ExpectedProtectionPolicySha256 = $Fixture.ExpectedProtectionPolicySha256
                ProtectionTrustRoot = $Fixture.ProtectionTrustRoot
                ProtectionAuthorityAssertionPath = $Fixture.ProtectionAuthorityAssertionPath
                ExpectedProtectionAuthorityAssertionSha256 = $Fixture.ExpectedProtectionAuthorityAssertionSha256
                ExpectedProtectionAuthorityBindingToken = $Fixture.ExpectedProtectionAuthorityBindingToken
                CredentialProfileId = $(if ($Operation -ceq 'Poll') {
                    $Fixture.ReadCredentialProfileId
                } else {
                    $Fixture.WriteCredentialProfileId
                })
                ExpectedGenesisCommit = $Fixture.Genesis
                HostToVmRepositoryIdentity = 'synthetic/host-to-vm'
                VmToHostRepositoryIdentity = 'synthetic/vm-to-host'
                ProductRepositoryIdentity = 'synthetic/product'
                AuthenticatedOutbox = $Fixture.Direction
                AuthenticatedSenderRoles = @($Fixture.AuthenticatedSenderRole)
                ValidationTimeUtc = '2030-01-01T00:05:00.0000000Z'
            }
        }

        function New-InitialRequestMessage {
            param(
                [Parameter(Mandatory = $true)]$State,
                [string]$CycleId = '91000000-0000-4000-8000-000000000101',
                [string]$MessageId = '92000000-0000-4000-8000-000000000101',
                [string]$RunId = '94000000-0000-4000-8000-000000000101',
                [long]$Sequence = 1,
                [AllowNull()]$PreviousMessageSha256 = $null
            )
            $payload = New-CddsiFastLaneSyntheticPayload TEST_REQUEST $CycleId $RunId
            $envelope = New-CddsiFastLaneSyntheticEnvelope -State $State -Payload $payload `
                -MessageId $MessageId -CycleId $CycleId -Sequence $Sequence -MessageType TEST_REQUEST `
                -SenderRole HostCoordinator -Outbox host-to-vm -Status TEST_REQUESTED -RunId $RunId `
                -PreviousMessageSha256 $PreviousMessageSha256 -Nonce ([guid]::NewGuid().ToString('D'))
            return [pscustomobject][ordered]@{ Envelope = $envelope; Payload = $payload }
        }

        function Add-OutboxCommit {
            param(
                [Parameter(Mandatory = $true)]$Fixture,
                [Parameter(Mandatory = $true)]$Message,
                [string]$CommitMessage = 'append message'
            )
            [void](Invoke-FixtureGit @('-C', $Fixture.Work, 'pull', '--quiet', '--ff-only', 'origin', 'main'))
            $sequence = ([long]$Message.Envelope.Sequence).ToString('D12', [Globalization.CultureInfo]::InvariantCulture)
            $relative = 'outbox/' + $sequence + '-' + $Message.Envelope.MessageId + '.json'
            $path = Join-Path $Fixture.Work $relative.Replace('/', [IO.Path]::DirectorySeparatorChar)
            $canonical = ConvertTo-CddsiVmTestRelayCanonicalJson $Message
            [IO.File]::WriteAllText($path, ($canonical + "`n"), (New-Object Text.UTF8Encoding($false)))
            [void](Invoke-FixtureGit @('-C', $Fixture.Work, 'add', '--', $relative))
            [void](Invoke-FixtureGit @('-C', $Fixture.Work, '-c', 'user.name=Fixture', '-c', 'user.email=fixture@invalid', 'commit', '--quiet', '-m', $CommitMessage, '--', $relative))
            [void](Invoke-FixtureGit @('-C', $Fixture.Work, 'push', '--quiet', 'origin', 'main'))
            return ([string](Invoke-FixtureGit @('-C', $Fixture.Work, 'rev-parse', 'HEAD') | Select-Object -First 1)).Trim()
        }

        function Set-ProtectionTrustInput {
            param(
                [Parameter(Mandatory = $true)]$Fixture,
                [Parameter(Mandatory = $true)]$Evidence,
                [Parameter(Mandatory = $true)][string]$EvidenceSha256,
                [Parameter(Mandatory = $true)][string]$Authority,
                [Parameter(Mandatory = $true)][string]$PolicySha256,
                [Parameter(Mandatory = $true)][string]$AuthorityBindingToken
            )

            $trustRoot = Join-Path $Fixture.OperatorWorkspaceRoot 'control-protection-trust'
            [void][IO.Directory]::CreateDirectory($trustRoot)
            $rootMarker = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-protection-authority-trust-root-v1'
                Owner = 'CDDsiFastLaneProtectionAuthorityTrust'; OperatorPlaneOnly = $true
                ProtectionAuthority = $Authority; ProtectionAuthorityBindingToken = $AuthorityBindingToken
                ProductRootPathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $Fixture.ProductRoot
                OperatorWorkspacePathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $Fixture.OperatorWorkspaceRoot
            }
            Write-CddsiFastLaneCanonicalFile -Path (Join-Path $trustRoot '.cddsi-owner.json') -Value $rootMarker
            $assertion = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-protection-authority-assertion-v1'
                ExternallyVerified = $true; ProtectionAuthority = $Authority
                ProtectionAuthorityBindingToken = $AuthorityBindingToken
                ProtectionPolicySha256 = $PolicySha256; ProtectionEvidenceSha256 = $EvidenceSha256
                RepositoryIdentity = $Evidence.RepositoryIdentity
                RepositoryNumericId = [long]$Evidence.RepositoryNumericId
                RepositoryNodeId = $Evidence.RepositoryNodeId; RemoteRef = $Evidence.RemoteRef
                PreviousReceiptSha256 = $Evidence.PreviousReceiptSha256
                ObservedAtUtc = $Evidence.ObservedAtUtc; ValidUntilUtc = $Evidence.ValidUntilUtc
                ReceiptId = $Evidence.ReceiptId
            }
            $assertionPath = Join-Path $trustRoot ('protection-' + $Evidence.ReceiptId + '.json')
            Write-CddsiFastLaneCanonicalFile -Path $assertionPath -Value $assertion
            return @{
                ProtectionTrustRoot = $trustRoot; ProtectionAuthorityAssertionPath = $assertionPath
                ExpectedProtectionAuthorityAssertionSha256 = (Get-FileHash $assertionPath -Algorithm SHA256).Hash.ToLowerInvariant()
                ExpectedProtectionAuthorityBindingToken = $AuthorityBindingToken
            }
        }

        function New-SnapshotReadySequence {
            param([long]$NumericId)

            $cycleId = ('95000000-0000-4000-8000-{0:d12}' -f $NumericId)
            $runId = ('96000000-0000-4000-8000-{0:d12}' -f $NumericId)
            $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
            $request = New-InitialRequestMessage -State $state -CycleId $cycleId `
                -MessageId ('97000000-0000-4000-8000-{0:d12}' -f ($NumericId * 10 + 1)) `
                -RunId $runId -Sequence 1
            $request.Envelope.EnvironmentResetMode = 'SnapshotRestore'
            $requestTransition = Resolve-CddsiVmTestRelayTransition -State $state `
                -Envelope $request.Envelope -Payload $request.Payload `
                -ValidationTimeUtc '2030-01-01T00:05:00.0000000Z' `
                -AuthenticatedSenderRole HostCoordinator -AuthenticatedOutbox host-to-vm
            if (-not $requestTransition.Accepted) { throw ('Snapshot request fixture rejected: ' + $requestTransition.ErrorCode) }

            $ackPayload = New-CddsiFastLaneSyntheticPayload VM_ACK $cycleId $runId
            $ackEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $requestTransition.State -Payload $ackPayload `
                -MessageId ('97000000-0000-4000-8000-{0:d12}' -f ($NumericId * 10 + 2)) `
                -CycleId $cycleId -Sequence 2 -MessageType VM_ACK -SenderRole VmTester `
                -Outbox vm-to-host -Status VM_ACKED -RunId $runId `
                -PreviousMessageSha256 $requestTransition.MessageSha256 `
                -Nonce ('98000000-0000-4000-8000-{0:d12}' -f ($NumericId * 10 + 2))
            $ackEnvelope.EnvironmentResetMode = 'SnapshotRestore'
            $ackTransition = Resolve-CddsiVmTestRelayTransition -State $requestTransition.State `
                -Envelope $ackEnvelope -Payload $ackPayload `
                -ValidationTimeUtc '2030-01-01T00:05:00.0000000Z' `
                -AuthenticatedSenderRole VmTester -AuthenticatedOutbox vm-to-host
            if (-not $ackTransition.Accepted) { throw ('Snapshot ack fixture rejected: ' + $ackTransition.ErrorCode) }

            $authorityToken = '6' * 64
            $receiptSha = 'f' * 64
            $snapshotPayload = [pscustomobject][ordered]@{
                SchemaVersion = '1'; ContractVersion = 'cddsi-vm-test-relay-snapshot-ready-v1'
                Code = 'EXTERNAL_SNAPSHOT_VERIFIED'; ExternalReceiptAuthority = 'HypervisorSupervisor'
                ExternalReceiptAuthorityBindingToken = $authorityToken
            }
            $snapshotEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $ackTransition.State `
                -Payload $snapshotPayload `
                -MessageId ('97000000-0000-4000-8000-{0:d12}' -f ($NumericId * 10 + 3)) `
                -CycleId $cycleId -Sequence 3 -MessageType SNAPSHOT_READY -SenderRole HostCoordinator `
                -Outbox host-to-vm -Status ENVIRONMENT_PREPARING -RunId $runId `
                -PreviousMessageSha256 $ackTransition.MessageSha256 `
                -Nonce ('98000000-0000-4000-8000-{0:d12}' -f ($NumericId * 10 + 3))
            $snapshotEnvelope.EnvironmentResetMode = 'SnapshotRestore'
            $snapshotEnvelope.SnapshotReceiptSha256 = $receiptSha
            return [pscustomobject]@{
                AckState = $ackTransition.State
                Message = [pscustomobject][ordered]@{ Envelope = $snapshotEnvelope; Payload = $snapshotPayload }
                CycleId = $cycleId; RunId = $runId
                SnapshotReceiptSha256 = $receiptSha; SnapshotAuthorityBindingToken = $authorityToken
            }
        }

        function New-SnapshotTrustInput {
            param(
                [Parameter(Mandatory = $true)]$Fixture,
                [Parameter(Mandatory = $true)]$Sequence
            )

            $trustRoot = Join-Path $Fixture.OperatorWorkspaceRoot 'external-snapshot-trust'
            [void][IO.Directory]::CreateDirectory($trustRoot)
            $rootMarker = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-external-snapshot-trust-root-v1'
                Owner = 'CDDsiFastLaneExternalSnapshotTrust'; OperatorPlaneOnly = $true
                ExternalReceiptAuthority = 'HypervisorSupervisor'
                ProductRootPathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $Fixture.ProductRoot
                OperatorWorkspacePathSha256 = Get-CddsiFastLaneCanonicalPathSha256 $Fixture.OperatorWorkspaceRoot
            }
            Write-CddsiFastLaneCanonicalFile -Path (Join-Path $trustRoot '.cddsi-owner.json') -Value $rootMarker
            $assertion = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-external-snapshot-trust-v1'
                ExternalReceiptAuthority = 'HypervisorSupervisor'; ExternallyVerified = $true
                SnapshotReceiptSha256 = $Sequence.SnapshotReceiptSha256
                SnapshotAuthorityBindingToken = $Sequence.SnapshotAuthorityBindingToken
                HostToVmRepositoryIdentity = 'synthetic/host-to-vm'
                VmToHostRepositoryIdentity = 'synthetic/vm-to-host'
                ProductRepositoryIdentity = 'synthetic/product'
                RepositoryIdentity = $Fixture.Identity; AuthenticatedOutbox = $Fixture.Direction
                CycleId = $Sequence.CycleId; RunId = $Sequence.RunId
                ObservedAtUtc = '2030-01-01T00:04:00.0000000Z'
                ValidUntilUtc = '2030-01-01T00:30:00.0000000Z'
            }
            $assertionPath = Join-Path $trustRoot ('snapshot-trust-' + $Sequence.CycleId + '.json')
            Write-CddsiFastLaneCanonicalFile -Path $assertionPath -Value $assertion
            return [pscustomobject]@{
                Assertion = $assertion
                Parameters = @{
                    SnapshotTrustRoot = $trustRoot; SnapshotTrustAssertionPath = $assertionPath
                    ExpectedSnapshotTrustAssertionSha256 = (Get-FileHash $assertionPath -Algorithm SHA256).Hash.ToLowerInvariant()
                    ExternallyVerifiedSnapshotReceiptSha256 = $Sequence.SnapshotReceiptSha256
                    ExternallyVerifiedSnapshotAuthorityBindingToken = $Sequence.SnapshotAuthorityBindingToken
                }
            }
        }

        function Set-RunnerRelayState {
            param([Parameter(Mandatory = $true)]$Fixture, [Parameter(Mandatory = $true)]$RelayState)

            $path = Join-Path $Fixture.StateRoot 'state.json'
            $state = Read-CddsiFastLaneCanonicalFile -Path $path -MaximumBytes 1048576
            $state.RelayState = $RelayState
            $state.Revision = [long]$state.Revision + 1
            Write-CddsiFastLaneCanonicalFile -Path $path -Value $state
        }
    }

    AfterAll {
        foreach ($root in @($script:FixtureRoots)) {
            if ([string]::IsNullOrEmpty([string]$root)) { continue }
            $full = [IO.Path]::GetFullPath($root)
            $leaf = [IO.Path]::GetFileName($full)
            $marker = Join-Path $full '.cddsi-owner.json'
            if (
                $leaf -match '^cddsi-test-[a-f0-9]{32}$' -and
                [IO.File]::Exists($marker) -and
                [IO.File]::ReadAllText($marker).Contains('cddsi-fast-lane-local-transport-owner-v1')
            ) {
                foreach ($file in [IO.Directory]::EnumerateFiles($full, '*', [IO.SearchOption]::AllDirectories)) {
                    [IO.File]::SetAttributes($file, [IO.FileAttributes]::Normal)
                }
                [IO.Directory]::Delete($full, $true)
            }
        }
    }

    It 'keeps TestSafe and DryRun free of Git, transport, and mutation' {
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $fixture = New-OutboxFixture
            $parameters = Get-OutboxParameters $fixture
            $result = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode $mode @parameters
            $result.Status | Should -BeExactly 'PLANNED'
            $result.GitInvocationCount | Should -Be 0
            $result.OperatorGitTransportCount | Should -Be 0
            $result.LocalStateMutationCount | Should -Be 0
            $result.ProductNetworkRequestCount | Should -Be 0
            $result.HostProductLiveInvocationCount | Should -Be 0
            $result.VmProductWriteCount | Should -Be 0
            [IO.Directory]::Exists($fixture.StateRoot) | Should -BeFalse
        }

        $fixture = New-OutboxFixture -NumericId 109
        $parameters = Get-OutboxParameters $fixture
        $parameters.StateRoot = Join-Path $fixture.ProductRoot ('fl-' + [guid]::NewGuid().ToString('N'))
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*STATE_ROOT_INSIDE_PRODUCT_ROOT_FORBIDDEN*'
    }

    It 'publishes one D12 append-only path with ordinary fast-forward push and bound receipts' {
        $fixture = New-OutboxFixture
        $parameters = Get-OutboxParameters $fixture -Operation Publish
        $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        $message = New-InitialRequestMessage $state
        $published = Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $message -ExpectedRemoteHead $fixture.Genesis @parameters
        $published.PublishedPath | Should -BeExactly ('outbox/000000000001-' + $message.Envelope.MessageId + '.json')
        $published.OperatorRemoteMutationCount | Should -Be 1
        $published.ProductNetworkRequestCount | Should -Be 0
        $published.HostProductLiveInvocationCount | Should -Be 0
        $published.VmProductWriteCount | Should -Be 0
        $published.RecoveredPublishCount | Should -Be 0
        [IO.File]::Exists((Join-Path $fixture.StateRoot 'pending-publish.json')) | Should -BeFalse
        $published.RunnerSha256 | Should -BeExactly $script:RunnerSha256
        $published.ProtectionEvidenceSha256 | Should -BeExactly $fixture.EvidenceSha256
        $diff = @(Invoke-FixtureGit @(('--git-dir=' + $fixture.Remote), 'diff-tree', '--no-commit-id', '--name-status', '-r', 'refs/heads/main'))
        @($diff).Count | Should -Be 1
        $diff[0] | Should -BeExactly ('A' + "`t" + $published.PublishedPath)
        (Get-Content -Raw $script:RunnerPath) | Should -Not -Match "'push'[^\r\n]+--force"
    }

    It 'recovers an exact successful remote push after pre-state-persist failure without re-pushing' {
        $fixture = New-OutboxFixture -NumericId 110
        $parameters = Get-OutboxParameters $fixture -Operation Publish
        $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        $message = New-InitialRequestMessage $state
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $message -ExpectedRemoteHead $fixture.Genesis `
            -FailureInjection AfterRemotePushBeforeStatePersist @parameters } |
            Should -Throw '*INJECTED_AFTER_REMOTE_PUSH_BEFORE_STATE_PERSIST*'
        $remoteHeadAfterFailure = ([string](Invoke-FixtureGit @(
            ('--git-dir=' + $fixture.Remote), 'rev-parse', 'refs/heads/main') | Select-Object -First 1)).Trim()
        $remoteHeadAfterFailure | Should -Not -BeExactly $fixture.Genesis
        [IO.File]::Exists((Join-Path $fixture.StateRoot 'pending-publish.json')) | Should -BeTrue

        $recovered = Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $message -ExpectedRemoteHead $fixture.Genesis @parameters
        $remoteHeadAfterRecovery = ([string](Invoke-FixtureGit @(
            ('--git-dir=' + $fixture.Remote), 'rev-parse', 'refs/heads/main') | Select-Object -First 1)).Trim()
        $recovered.Status | Should -BeExactly 'RECOVERED'
        $recovered.RecoveredPublishCount | Should -Be 1
        $recovered.OperatorRemoteMutationCount | Should -Be 0
        $recovered.PublishedCommit | Should -BeExactly $remoteHeadAfterFailure
        $remoteHeadAfterRecovery | Should -BeExactly $remoteHeadAfterFailure
        $recovered.RelayState.ActiveStatus | Should -BeExactly 'TEST_REQUESTED'
        [IO.File]::Exists((Join-Path $fixture.StateRoot 'pending-publish.json')) | Should -BeFalse
    }

    It 'rotates protection receipts only through a strictly monotonic predecessor chain' {
        $fixture = New-OutboxFixture -NumericId 111
        $parameters = Get-OutboxParameters $fixture
        [void](Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters)

        $secondReceipt = ConvertTo-CddsiFastLaneJsonData (ConvertFrom-Json `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $fixture.Evidence))
        $secondReceipt.PreviousReceiptSha256 = $fixture.EvidenceSha256
        $secondReceipt.ObservedAtUtc = '2030-01-01T00:10:00.0000000Z'
        $secondReceipt.ValidUntilUtc = '2030-01-01T00:40:00.0000000Z'
        $secondReceipt.ReceiptId = '11111111-1111-4111-8111-000000000211'
        $secondSha = Get-CddsiSupplyChainTextBindingToken -Text (ConvertTo-CddsiVmTestRelayCanonicalJson $secondReceipt)
        $parameters.ProtectionEvidence = $secondReceipt
        $parameters.ProtectionEvidenceSha256 = $secondSha
        $secondTrust = Set-ProtectionTrustInput -Fixture $fixture -Evidence $secondReceipt `
            -EvidenceSha256 $secondSha -Authority $fixture.ExpectedProtectionAuthority `
            -PolicySha256 $fixture.ExpectedProtectionPolicySha256 `
            -AuthorityBindingToken $fixture.ExpectedProtectionAuthorityBindingToken
        foreach ($item in $secondTrust.GetEnumerator()) { $parameters[$item.Key] = $item.Value }
        $parameters.ValidationTimeUtc = '2030-01-01T00:15:00.0000000Z'
        $rotated = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters
        $rotated.ProtectionReceiptRotated | Should -BeTrue
        $stored = Read-CddsiFastLaneCanonicalFile (Join-Path $fixture.StateRoot 'state.json') 1048576
        $stored.Repositories[0].ProtectionEvidenceSha256 | Should -BeExactly $secondSha
        $stored.Repositories[0].ProtectionAuthority | Should -BeExactly $fixture.ExpectedProtectionAuthority
        $stored.Repositories[0].ProtectionPolicySha256 | Should -BeExactly $fixture.ExpectedProtectionPolicySha256

        $parameters.ProtectionEvidence = $fixture.Evidence
        $parameters.ProtectionEvidenceSha256 = $fixture.EvidenceSha256
        $parameters.ProtectionAuthorityAssertionPath = $fixture.ProtectionAuthorityAssertionPath
        $parameters.ExpectedProtectionAuthorityAssertionSha256 = $fixture.ExpectedProtectionAuthorityAssertionSha256
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters } |
            Should -Throw '*PROTECTION_RECEIPT_ROLLBACK_OR_FORK*'

        $forged = ConvertTo-CddsiFastLaneJsonData (ConvertFrom-Json `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $secondReceipt))
        $forged.PreviousReceiptSha256 = $secondSha
        $forged.ObservedAtUtc = '2030-01-01T00:20:00.0000000Z'
        $forged.ValidUntilUtc = '2030-01-01T00:50:00.0000000Z'
        $forged.ReceiptId = '11111111-1111-4111-8111-000000000511'
        $forgedSha = Get-CddsiSupplyChainTextBindingToken -Text `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $forged)
        $forgedTrust = Set-ProtectionTrustInput -Fixture $fixture -Evidence $forged `
            -EvidenceSha256 $forgedSha -Authority $fixture.ExpectedProtectionAuthority `
            -PolicySha256 $fixture.ExpectedProtectionPolicySha256 `
            -AuthorityBindingToken $fixture.ExpectedProtectionAuthorityBindingToken
        $parameters.ProtectionEvidence = $forged
        $parameters.ProtectionEvidenceSha256 = $forgedSha
        $parameters.ProtectionAuthorityAssertionPath = $forgedTrust.ProtectionAuthorityAssertionPath
        $parameters.ExpectedProtectionAuthorityAssertionSha256 = $secondTrust.ExpectedProtectionAuthorityAssertionSha256
        $parameters.ValidationTimeUtc = '2030-01-01T00:25:00.0000000Z'
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters } |
            Should -Throw '*PROTECTION_AUTHORITY_ASSERTION_HASH_MISMATCH*'

        $fork = ConvertTo-CddsiFastLaneJsonData (ConvertFrom-Json `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $secondReceipt))
        $fork.PreviousReceiptSha256 = '0' * 64
        $fork.ObservedAtUtc = '2030-01-01T00:20:00.0000000Z'
        $fork.ValidUntilUtc = '2030-01-01T00:50:00.0000000Z'
        $fork.ReceiptId = '11111111-1111-4111-8111-000000000311'
        $parameters.ProtectionEvidence = $fork
        $parameters.ProtectionEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $fork)
        $forkTrust = Set-ProtectionTrustInput -Fixture $fixture -Evidence $fork `
            -EvidenceSha256 $parameters.ProtectionEvidenceSha256 `
            -Authority $fixture.ExpectedProtectionAuthority `
            -PolicySha256 $fixture.ExpectedProtectionPolicySha256 `
            -AuthorityBindingToken $fixture.ExpectedProtectionAuthorityBindingToken
        foreach ($item in $forkTrust.GetEnumerator()) { $parameters[$item.Key] = $item.Value }
        $parameters.ValidationTimeUtc = '2030-01-01T00:25:00.0000000Z'
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters } |
            Should -Throw '*PROTECTION_RECEIPT_ROLLBACK_OR_FORK*'

        $nonMonotonic = ConvertTo-CddsiFastLaneJsonData (ConvertFrom-Json `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $secondReceipt))
        $nonMonotonic.PreviousReceiptSha256 = $secondSha
        $nonMonotonic.ValidUntilUtc = '2030-01-01T00:50:00.0000000Z'
        $nonMonotonic.ReceiptId = '11111111-1111-4111-8111-000000000411'
        $parameters.ProtectionEvidence = $nonMonotonic
        $parameters.ProtectionEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $nonMonotonic)
        $nonMonotonicTrust = Set-ProtectionTrustInput -Fixture $fixture -Evidence $nonMonotonic `
            -EvidenceSha256 $parameters.ProtectionEvidenceSha256 `
            -Authority $fixture.ExpectedProtectionAuthority `
            -PolicySha256 $fixture.ExpectedProtectionPolicySha256 `
            -AuthorityBindingToken $fixture.ExpectedProtectionAuthorityBindingToken
        foreach ($item in $nonMonotonicTrust.GetEnumerator()) { $parameters[$item.Key] = $item.Value }
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters } |
            Should -Throw '*PROTECTION_RECEIPT_NOT_MONOTONIC*'
    }

    It 'requires protected out-of-band snapshot trust for poll, publish, and crash recovery' {
        $pollFixture = New-OutboxFixture -NumericId 114
        $pollSequence = New-SnapshotReadySequence -NumericId 114
        $pollTrust = New-SnapshotTrustInput -Fixture $pollFixture -Sequence $pollSequence
        $pollParameters = Get-OutboxParameters $pollFixture
        [void](Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @pollParameters)
        Set-RunnerRelayState -Fixture $pollFixture -RelayState $pollSequence.AckState
        [void](Add-OutboxCommit $pollFixture $pollSequence.Message 'snapshot ready')
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @pollParameters } |
            Should -Throw '*SNAPSHOT_TRUST_ASSERTION_REQUIRED*'
        foreach ($item in $pollTrust.Parameters.GetEnumerator()) { $pollParameters[$item.Key] = $item.Value }
        $pollParameters.ExternallyVerifiedSnapshotReceiptSha256 = 'a' * 64
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @pollParameters } |
            Should -Throw '*SNAPSHOT_TRUST_ASSERTION_INVALID*'
        $pollParameters.ExternallyVerifiedSnapshotReceiptSha256 = $pollSequence.SnapshotReceiptSha256
        $consumed = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @pollParameters
        $consumed.RelayState.ActiveStatus | Should -BeExactly 'ENVIRONMENT_PREPARING'
        $consumed.SnapshotTrustInputSource | Should -BeExactly 'ProtectedOperatorWorkspace'
        $consumed.SnapshotTrustAssertionSha256 | Should -BeExactly `
            $pollTrust.Parameters.ExpectedSnapshotTrustAssertionSha256

        $publishFixture = New-OutboxFixture -NumericId 115
        $publishSequence = New-SnapshotReadySequence -NumericId 115
        $publishTrust = New-SnapshotTrustInput -Fixture $publishFixture -Sequence $publishSequence
        $publishParameters = Get-OutboxParameters $publishFixture -Operation Publish
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode TestSafe `
            -Message $publishSequence.Message -ExpectedRemoteHead $publishFixture.Genesis @publishParameters } |
            Should -Throw '*SNAPSHOT_TRUST_ASSERTION_REQUIRED*'
        foreach ($item in $publishTrust.Parameters.GetEnumerator()) { $publishParameters[$item.Key] = $item.Value }
        $nonSnapshot = New-InitialRequestMessage `
            (New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product)
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode TestSafe `
            -Message $nonSnapshot -ExpectedRemoteHead $publishFixture.Genesis @publishParameters } |
            Should -Throw '*SNAPSHOT_TRUST_INPUT_NOT_APPLICABLE*'
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $publishSequence.Message -ExpectedRemoteHead $publishFixture.Genesis @publishParameters } |
            Should -Throw '*RELAY_REJECTED:*'
        Set-RunnerRelayState -Fixture $publishFixture -RelayState $publishSequence.AckState
        $published = Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $publishSequence.Message -ExpectedRemoteHead $publishFixture.Genesis @publishParameters
        $published.Status | Should -BeExactly 'SUCCEEDED'
        $published.RelayState.ActiveStatus | Should -BeExactly 'ENVIRONMENT_PREPARING'

        $recoveryFixture = New-OutboxFixture -NumericId 116
        $recoverySequence = New-SnapshotReadySequence -NumericId 116
        $recoveryTrust = New-SnapshotTrustInput -Fixture $recoveryFixture -Sequence $recoverySequence
        $recoveryParameters = Get-OutboxParameters $recoveryFixture -Operation Publish
        foreach ($item in $recoveryTrust.Parameters.GetEnumerator()) { $recoveryParameters[$item.Key] = $item.Value }
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $recoverySequence.Message -ExpectedRemoteHead $recoveryFixture.Genesis @recoveryParameters } |
            Should -Throw '*RELAY_REJECTED:*'
        Set-RunnerRelayState -Fixture $recoveryFixture -RelayState $recoverySequence.AckState
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $recoverySequence.Message -ExpectedRemoteHead $recoveryFixture.Genesis `
            -FailureInjection AfterRemotePushBeforeStatePersist @recoveryParameters } |
            Should -Throw '*INJECTED_AFTER_REMOTE_PUSH_BEFORE_STATE_PERSIST*'
        $recoveryTrust.Assertion.ExternallyVerified = $false
        Write-CddsiFastLaneCanonicalFile -Path $recoveryParameters.SnapshotTrustAssertionPath `
            -Value $recoveryTrust.Assertion
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $recoverySequence.Message -ExpectedRemoteHead $recoveryFixture.Genesis @recoveryParameters } |
            Should -Throw '*SNAPSHOT_TRUST_ASSERTION_HASH_MISMATCH*'
        $recoveryTrust.Assertion.ExternallyVerified = $true
        Write-CddsiFastLaneCanonicalFile -Path $recoveryParameters.SnapshotTrustAssertionPath `
            -Value $recoveryTrust.Assertion
        $recovered = Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $recoverySequence.Message -ExpectedRemoteHead $recoveryFixture.Genesis @recoveryParameters
        $recovered.Status | Should -BeExactly 'RECOVERED'
        $recovered.RecoveredPublishCount | Should -Be 1
        $recovered.OperatorRemoteMutationCount | Should -Be 0
        $recovered.RelayState.ActiveStatus | Should -BeExactly 'ENVIRONMENT_PREPARING'
    }

    It 'polls canonical commits through the relay transition and obeys the message bound' {
        $fixture = New-OutboxFixture
        $parameters = Get-OutboxParameters $fixture
        $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        $request = New-InitialRequestMessage $state
        [void](Add-OutboxCommit $fixture $request 'request')
        $requestTransition = Resolve-CddsiVmTestRelayTransition -State $state -Envelope $request.Envelope -Payload $request.Payload `
            -ValidationTimeUtc '2030-01-01T00:05:00.0000000Z' -AuthenticatedSenderRole HostCoordinator -AuthenticatedOutbox host-to-vm
        $stopPayload = New-CddsiFastLaneSyntheticPayload STOP $request.Envelope.CycleId $request.Envelope.RunId
        $stopEnvelope = New-CddsiFastLaneSyntheticEnvelope -State $requestTransition.State -Payload $stopPayload `
            -MessageId '92000000-0000-4000-8000-000000000102' -CycleId $request.Envelope.CycleId -Sequence 2 `
            -MessageType STOP -SenderRole HostCoordinator -Outbox host-to-vm -Status STOPPED -RunId $request.Envelope.RunId `
            -PreviousMessageSha256 $requestTransition.MessageSha256 -Nonce '93000000-0000-4000-8000-000000000102'
        [void](Add-OutboxCommit $fixture ([pscustomobject][ordered]@{ Envelope = $stopEnvelope; Payload = $stopPayload }) 'stop')
        $first = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive -MaximumMessageCount 1 @parameters
        $first.ProcessedMessageCount | Should -Be 1
        $first.MoreAvailable | Should -BeTrue
        $first.RelayState.ActiveStatus | Should -BeExactly 'TEST_REQUESTED'
        $second = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive -MaximumMessageCount 1 @parameters
        $second.ProcessedMessageCount | Should -Be 1
        $second.MoreAvailable | Should -BeFalse
        $second.RelayState.StoppedCycleIds | Should -Contain $request.Envelope.CycleId
    }

    It 'derives exactly one relay sender role from repository direction and credential profile' {
        $hostFixture = New-OutboxFixture -NumericId 112 -Direction host-to-vm
        $hostParameters = Get-OutboxParameters $hostFixture
        $hostPlan = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @hostParameters
        $hostPlan.AuthenticatedSenderRole | Should -BeExactly 'HostCoordinator'
        foreach ($forbiddenRole in @('Human', 'HypervisorSupervisor')) {
            $hostParameters.AuthenticatedSenderRoles = @($forbiddenRole)
            { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @hostParameters } | Should -Throw
        }
        $hostParameters.AuthenticatedSenderRoles = @('VmTester')
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @hostParameters } |
            Should -Throw '*AUTHENTICATED_ROLE_NOT_FROZEN_FOR_CREDENTIAL*'
        $hostParameters.AuthenticatedSenderRoles = @('HostCoordinator')
        $hostParameters.CredentialProfileId = $hostFixture.WriteCredentialProfileId
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @hostParameters } |
            Should -Throw '*CREDENTIAL_DIRECTION_ROLE_AUTHORITY_MISMATCH*'

        $vmFixture = New-OutboxFixture -NumericId 113 -Direction vm-to-host
        $vmParameters = Get-OutboxParameters $vmFixture
        $vmPlan = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @vmParameters
        $vmPlan.AuthenticatedSenderRole | Should -BeExactly 'VmTester'
        $vmParameters.AuthenticatedSenderRoles = @('HostCoordinator')
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @vmParameters } |
            Should -Throw '*AUTHENTICATED_ROLE_NOT_FROZEN_FOR_CREDENTIAL*'
        $vmParameters.AuthenticatedSenderRoles = @('VmTester', 'Human')
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @vmParameters } | Should -Throw
    }

    It 'rejects duplicate IDs and tampered payload text without executing it' {
        $fixture = New-OutboxFixture
        $parameters = Get-OutboxParameters $fixture
        $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        $request = New-InitialRequestMessage $state
        [void](Add-OutboxCommit $fixture $request 'first')
        $first = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters
        $duplicate = New-InitialRequestMessage -State $first.RelayState -CycleId $request.Envelope.CycleId `
            -MessageId $request.Envelope.MessageId -RunId $request.Envelope.RunId -Sequence 2 `
            -PreviousMessageSha256 $first.RelayState.ActiveMessageSha256
        [void](Add-OutboxCommit $fixture $duplicate 'duplicate')
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters } |
            Should -Throw '*RELAY_REJECTED:MESSAGE_REPLAY*'

        $tamperFixture = New-OutboxFixture -NumericId 102
        $tamperParameters = Get-OutboxParameters $tamperFixture
        $tamperState = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        $tampered = New-InitialRequestMessage $tamperState
        $sentinel = Join-Path $tamperFixture.Root 'payload-executed.txt'
        $tampered.Payload.RequestKind = ('$(Set-Content -LiteralPath "' + $sentinel + '" -Value bad)')
        [void](Add-OutboxCommit $tamperFixture $tampered 'tampered')
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @tamperParameters } |
            Should -Throw '*RELAY_REJECTED:RELAY_ENVELOPE_INVALID*'
        [IO.File]::Exists($sentinel) | Should -BeFalse
    }

    It 'rejects rewritten history, wrong genesis, and a rebound repository URI' {
        $fixture = New-OutboxFixture
        $parameters = Get-OutboxParameters $fixture
        $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        [void](Add-OutboxCommit $fixture (New-InitialRequestMessage $state) 'request')
        [void](Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters)
        [void](Invoke-FixtureGit @(('--git-dir=' + $fixture.Remote), 'update-ref', 'refs/heads/main', $fixture.Genesis))
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @parameters } |
            Should -Throw '*REMOTE_HISTORY_REWRITE*'

        $wrongGenesis = New-OutboxFixture -NumericId 103
        $wrongGenesisParameters = Get-OutboxParameters $wrongGenesis
        $wrongGenesisParameters.ExpectedGenesisCommit = 'a' * 40
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @wrongGenesisParameters } |
            Should -Throw '*PINNED_GENESIS_MISMATCH*'

        $bound = New-OutboxFixture -NumericId 104
        $boundParameters = Get-OutboxParameters $bound
        [void](Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @boundParameters)
        $other = New-OutboxFixture -NumericId 105
        $boundParameters.RepositoryUri = $other.Remote
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @boundParameters } |
            Should -Throw '*LOCAL_REMOTE_BINDING_MISMATCH*'
    }

    It 'rejects stale publish CAS and a held single-instance lock' {
        $fixture = New-OutboxFixture
        $parameters = Get-OutboxParameters $fixture -Operation Publish
        $state = New-CddsiVmTestRelayState synthetic/host-to-vm synthetic/vm-to-host synthetic/product
        $message = New-InitialRequestMessage $state
        [void](Add-OutboxCommit $fixture $message 'racing writer')
        { Invoke-CddsiFastLaneGitOutbox -Operation Publish -Mode Live -AcknowledgeOperatorPlaneLive `
            -Message $message -ExpectedRemoteHead $fixture.Genesis @parameters } | Should -Throw '*REMOTE_CAS_MISMATCH*'

        $lockFixture = New-OutboxFixture -NumericId 106
        $lockParameters = Get-OutboxParameters $lockFixture
        [void](Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @lockParameters)
        $lock = [IO.File]::Open((Join-Path $lockFixture.StateRoot '.cddsi.lock'), [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode Live -AcknowledgeOperatorPlaneLive @lockParameters } |
                Should -Throw '*FAST_LANE_SINGLE_INSTANCE_LOCKED*'
        }
        finally { $lock.Dispose() }
    }

    It 'fails closed on runner, Git, and protection receipt binding changes and never retries' {
        $fixture = New-OutboxFixture
        $parameters = Get-OutboxParameters $fixture
        $parameters.GitExecutableSha256 = '0' * 64
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } | Should -Throw '*GIT_EXECUTABLE_HASH_MISMATCH*'
        $parameters.GitExecutableSha256 = $script:GitExecutableSha256
        $parameters.RunnerSha256 = '0' * 64
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } | Should -Throw '*RUNNER_HASH_MISMATCH*'
        $parameters.RunnerSha256 = $script:RunnerSha256
        $parameters.ProtectionEvidenceSha256 = '0' * 64
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } | Should -Throw '*PROTECTION_EVIDENCE_HASH_MISMATCH*'
        $parameters.ProtectionEvidenceSha256 = $fixture.EvidenceSha256
        $plan = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe -MaximumRetryCount 0 @parameters
        $plan.MaximumRetryCount | Should -Be 0
        $plan.RetryCount | Should -Be 0
        $plan.MaximumMessageCount | Should -Be 32
        $plan.MaximumRuntimeSeconds | Should -Be 45
        $plan.MaximumOutputBytes | Should -Be 65536
        $plan.MaximumMessageBodyBytes | Should -Be 65536
        $plan.MaximumAgeSeconds | Should -Be 900
        $plan.MaximumClockSkewSeconds | Should -Be 120
        $plan.HostProductLiveInvocationCount | Should -Be 0
        $plan.VmProductWriteCount | Should -Be 0

        $parameters.ExpectedProtectionAuthority = 'synthetic/UntrustedSelfReportedAuthority'
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*CREDENTIAL_DIRECTION_ROLE_AUTHORITY_MISMATCH*'
        $parameters.ExpectedProtectionAuthority = $fixture.ExpectedProtectionAuthority
        $parameters.ExpectedProtectionPolicySha256 = '9' * 64
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*PROTECTION_EVIDENCE_INVALID*'
        $parameters.ExpectedProtectionPolicySha256 = $fixture.ExpectedProtectionPolicySha256

        $parameters.ExpectedRepositoryNumericId = 999L
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } | Should -Throw '*PROTECTION_EVIDENCE_INVALID*'
        $parameters.ExpectedRepositoryNumericId = [long]$fixture.Evidence.RepositoryNumericId
        $parameters.ProtectionEvidence.Visibility = 'PRIVATE'
        $parameters.ProtectionEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $parameters.ProtectionEvidence)
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*PROTECTION_EVIDENCE_INVALID*'
        $parameters.ProtectionEvidence.Visibility = 'PUBLIC'
        $parameters.ProtectionEvidenceSha256 = $fixture.EvidenceSha256
        $parameters.ProtectionEvidence.ValidUntilUtc = '2030-01-01T01:00:00.0000001Z'
        $parameters.ProtectionEvidenceSha256 = Get-CddsiSupplyChainTextBindingToken -Text `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $parameters.ProtectionEvidence)
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*PROTECTION_EVIDENCE_EXPIRED_OR_STALE*'
    }

    It 'binds a frozen SSH profile without exposing paths or starting a process' {
        $fixture = New-OutboxFixture -NumericId 107
        $special = Join-Path $fixture.Root 'ssh files & pinned'
        [void][IO.Directory]::CreateDirectory($special)
        $deployKey = Join-Path $special 'deploy key & test'
        [IO.File]::WriteAllText($deployKey, 'synthetic-private-key-fixture', (New-Object Text.UTF8Encoding($false)))
        $ssh = Join-Path $special 'synthetic-ssh.exe'
        [IO.File]::WriteAllBytes(
            $ssh,
            [Text.Encoding]::ASCII.GetBytes('synthetic-ssh-executable-fixture'))
        $policy = Import-PowerShellDataFile (Join-Path $script:RepoRoot 'config\fast-lane-policy.psd1')
        $knownHosts = Join-Path $script:RepoRoot $policy.SshTrust.KnownHostsSourcePath.Replace('/', '\')
        $sshSha = (Get-FileHash $ssh -Algorithm SHA256).Hash.ToLowerInvariant()
        $deployKeySha = (Get-FileHash $deployKey -Algorithm SHA256).Hash.ToLowerInvariant()
        $knownHostsSha = (Get-FileHash $knownHosts -Algorithm SHA256).Hash.ToLowerInvariant()
        $knownHostsSha | Should -BeExactly $policy.SshTrust.KnownHostsSha256
        $identity = 'github.com/LXZ56156/cddsi-host-to-vm'
        $authority = 'github.com/LXZ56156/cddsi-control-protection-authority-v1'
        $protectionPolicySha = '7' * 64
        $evidence = [pscustomobject][ordered]@{
            SchemaVersion = 2; ContractVersion = 'cddsi-fast-lane-control-repo-protection-v3'
            RepositoryIdentity = $identity; RepositoryNumericId = 7001L; RepositoryNodeId = 'R_SYNTHETIC_7001'
            Visibility = 'PUBLIC'; RemoteRef = 'refs/heads/main'; ForcePushAllowed = $false
            BranchDeletionAllowed = $false; HistoryRewriteAllowed = $false
            Authority = $authority; ProtectionPolicySha256 = $protectionPolicySha; PreviousReceiptSha256 = $null
            ObservedAtUtc = '2030-01-01T00:00:00.0000000Z'; ValidUntilUtc = '2030-01-01T00:30:00.0000000Z'
            ReceiptId = '11111111-1111-4111-8111-000000007001'
        }
        $evidenceSha = Get-CddsiSupplyChainTextBindingToken -Text `
            (ConvertTo-CddsiVmTestRelayCanonicalJson $evidence)
        $protectionAuthorityBindingToken = '8' * 64
        $protectionTrust = Set-ProtectionTrustInput -Fixture $fixture -Evidence $evidence `
            -EvidenceSha256 $evidenceSha -Authority $authority -PolicySha256 $protectionPolicySha `
            -AuthorityBindingToken $protectionAuthorityBindingToken
        $parameters = @{
            StateRoot = Join-Path $fixture.OperatorWorkspaceRoot ('fl-' + [guid]::NewGuid().ToString('N'))
            ProductRoot = $fixture.ProductRoot; OperatorWorkspaceRoot = $fixture.OperatorWorkspaceRoot
            GitExecutable = $script:GitExecutable; GitExecutableSha256 = $script:GitExecutableSha256
            RunnerSha256 = $script:RunnerSha256; RepositoryUri = 'git@github.com:LXZ56156/cddsi-host-to-vm.git'
            RepositoryIdentity = $identity; ProtectionEvidence = $evidence
            ProtectionEvidenceSha256 = $evidenceSha
            ExpectedRepositoryNumericId = 7001L; ExpectedRepositoryNodeId = 'R_SYNTHETIC_7001'
            ExpectedRepositoryVisibility = 'PUBLIC'
            ExpectedProtectionAuthority = $authority; ExpectedProtectionPolicySha256 = $protectionPolicySha
            ProtectionTrustRoot = $protectionTrust.ProtectionTrustRoot
            ProtectionAuthorityAssertionPath = $protectionTrust.ProtectionAuthorityAssertionPath
            ExpectedProtectionAuthorityAssertionSha256 = $protectionTrust.ExpectedProtectionAuthorityAssertionSha256
            ExpectedProtectionAuthorityBindingToken = $protectionAuthorityBindingToken
            CredentialProfileId = 'vm.host-to-vm.read'; ExpectedGenesisCommit = 'a' * 40
            HostToVmRepositoryIdentity = $identity; VmToHostRepositoryIdentity = 'github.com/LXZ56156/cddsi-vm-to-host'
            ProductRepositoryIdentity = 'github.com/LXZ56156/claude-desktop-deepseek-installer'
            AuthenticatedOutbox = 'host-to-vm'; AuthenticatedSenderRoles = @('HostCoordinator')
            ValidationTimeUtc = '2030-01-01T00:05:00.0000000Z'
            SshExecutable = $ssh; SshExecutableSha256 = $sshSha; ExpectedSshExecutableSha256 = $sshSha
            DeployKeyPath = $deployKey; DeployKeySha256 = $deployKeySha; ExpectedDeployKeySha256 = $deployKeySha
            KnownHostsPath = $knownHosts; KnownHostsSha256 = $knownHostsSha; ExpectedKnownHostsSha256 = $knownHostsSha
        }
        $plan = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters
        $plan.Status | Should -BeExactly 'PLANNED'
        $plan.TransportKind | Should -BeExactly 'Ssh'
        $plan.GitInvocationCount | Should -Be 0
        $serialized = ConvertTo-CddsiVmTestRelayCanonicalJson $plan
        $serialized | Should -Not -Match ([regex]::Escape($special))
        $serialized | Should -Not -Match 'synthetic-private-key-fixture'
        (ConvertTo-CddsiFastLaneSshCommandArgument $deployKey) | Should -BeExactly ("'" + $deployKey + "'")
        $parameters.CredentialProfileId = 'host.host-to-vm.write'
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*CREDENTIAL_DIRECTION_ROLE_AUTHORITY_MISMATCH*'
        $parameters.CredentialProfileId = 'vm.host-to-vm.read'
        $parameters.ExpectedKnownHostsSha256 = '0' * 64
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*SSH_FROZEN_TRUST_BINDING_MISMATCH*'
        $parameters.ExpectedKnownHostsSha256 = $knownHostsSha
        [void][IO.Directory]::CreateDirectory($parameters.StateRoot)
        $insideKey = Join-Path $parameters.StateRoot 'deploy-key'
        [IO.File]::WriteAllText($insideKey, 'must-not-be-archived-with-state', (New-Object Text.UTF8Encoding($false)))
        $parameters.DeployKeyPath = $insideKey
        $parameters.DeployKeySha256 = (Get-FileHash $insideKey -Algorithm SHA256).Hash.ToLowerInvariant()
        $parameters.ExpectedDeployKeySha256 = $parameters.DeployKeySha256
        { Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe @parameters } |
            Should -Throw '*DEPLOY_KEY_INSIDE_STATE_ROOT_FORBIDDEN*'
    }

    It 'uses an exact clean process environment and terminates a timed-out process tree' {
        Initialize-CddsiFastLaneBoundedProcessType
        $fixture = New-OutboxFixture -NumericId 108
        $commandProcessor = (Get-Command cmd.exe -CommandType Application -ErrorAction Stop).Source
        $systemRoot = Split-Path (Split-Path $commandProcessor -Parent) -Parent
        $runnerSource = [IO.File]::ReadAllText($script:RunnerPath)
        $runnerSource | Should -Match 'info\.EnvironmentVariables\.Clear\(\);'
        $runnerSource | Should -Match "'core\.longpaths=true'"
        $failureContext = @{
            StateRoot = $fixture.Root; GitExecutable = $script:GitExecutable
            MaximumRuntimeSeconds = 10; MaximumGitCommandSeconds = 10; MaximumOutputBytes = 4096
            Stopwatch = [Diagnostics.Stopwatch]::StartNew(); TransportKind = 'LocalFile'
        }
        $failureMessage = $null
        try {
            [void](Invoke-CddsiFastLaneGitCommand -Context $failureContext `
                -Arguments @('cddsi-synthetic-unknown-command'))
        }
        catch { $failureMessage = $_.Exception.Message }
        $failureMessage | Should -Match '^GIT_COMMAND_FAILED:1:[-0-9]+$'
        $failureMessage | Should -Not -Match ([regex]::Escape($fixture.Root))
        $probeCode = 'echo %GIT_CONFIG_COUNT%^|%GIT_SSH_COMMAND%^|%HTTPS_PROXY%^|%SAFE_VALUE%'
        $probeArguments = (@('/d', '/c', $probeCode) |
            ForEach-Object { ConvertTo-CddsiFastLaneGitQuotedArgument $_ }) -join ' '
        $cleanEnvironment = @{
            SystemRoot = $systemRoot
            WINDIR = $systemRoot
            ComSpec = $commandProcessor
            SAFE_VALUE = 'clean'
        }
        $probe = [Cddsi.FastLane.BoundedProcessRunner]::Run(
            $commandProcessor, $probeArguments, $fixture.Root, $cleanEnvironment, $null, 10000, 4096)
        $probe.ExitCode | Should -Be 0
        $probe.JobAssigned | Should -BeTrue
        $probe.StandardOutput.Trim() | Should -BeExactly '%GIT_CONFIG_COUNT%|%GIT_SSH_COMMAND%|%HTTPS_PROXY%|clean'

        $sentinel = Join-Path $fixture.Root 'child-survived.txt'
        $childScript = Join-Path $fixture.Root 'child.cmd'
        $parentScript = Join-Path $fixture.Root 'parent.cmd'
        $childBody = "@echo off`r`n`"%SystemRoot%\System32\ping.exe`" -n 5 127.0.0.1 >NUL`r`n> `"" + $sentinel + "`" echo bad`r`n"
        $parentBody = "@echo off`r`nstart `"`" /b `"%SystemRoot%\System32\cmd.exe`" /d /c call `"" + $childScript +
            "`"`r`n`"%SystemRoot%\System32\ping.exe`" -n 31 127.0.0.1 >NUL`r`n"
        [IO.File]::WriteAllText($childScript, $childBody, [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($parentScript, $parentBody, [Text.Encoding]::ASCII)
        $treeArguments = (@('/d', '/c', 'call', $parentScript) |
            ForEach-Object { ConvertTo-CddsiFastLaneGitQuotedArgument $_ }) -join ' '
        $tree = [Cddsi.FastLane.BoundedProcessRunner]::Run(
            $commandProcessor, $treeArguments, $fixture.Root, $cleanEnvironment, $null, 2000, 4096)
        $tree.TimedOut | Should -BeTrue
        $tree.JobAssigned | Should -BeTrue
        $tree.ProcessTreeTerminated | Should -BeTrue
        Start-Sleep -Seconds 5
        [IO.File]::Exists($sentinel) | Should -BeFalse
    }
}
