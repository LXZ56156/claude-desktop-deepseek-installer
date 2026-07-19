Describe 'DevelopmentOnly deterministic Fast Lane Git outbox runtime' {
    BeforeAll {
        $script:RepoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..\..')).Path
        . (Join-Path $script:RepoRoot 'lib\common.ps1')
        . (Join-Path $script:RepoRoot 'lib\vm-test-relay.ps1')
        . (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-synthetic-rehearsal.ps1')
        $script:RunnerPath = Join-Path $script:RepoRoot 'operator\fast-lane\invoke-git-outbox.ps1'
        . $script:RunnerPath
        $script:FixtureRoots = [Collections.ArrayList]::new()
        $capturedFunctionDefinitions = [Collections.Generic.List[string]]::new()
        $runnerTokens = $null; $runnerParseErrors = $null
        $runnerAst = [Management.Automation.Language.Parser]::ParseFile(
            $script:RunnerPath, [ref]$runnerTokens, [ref]$runnerParseErrors)
        if (@($runnerParseErrors).Count -ne 0) { throw 'VM_BOOTSTRAP_TEST_RUNTIME_PARSE_FAILED' }
        $directFacadeNames = [ordered]@{
            'Invoke-CddsiFastLaneVmBootstrap' = 'Invoke-CddsiTestDirectVmBootstrap'
            'Invoke-CddsiFastLaneVmBootstrapOnboarding' = 'Invoke-CddsiTestDirectVmBootstrapOnboarding'
            'New-CddsiFastLaneVmBootstrapHandoff' = 'New-CddsiTestDirectVmBootstrapHandoff'
            'Set-CddsiFastLaneVmBootstrapProtectedAcl' = 'Set-CddsiTestDirectVmBootstrapProtectedAcl'
            'Invoke-CddsiFastLaneVmBootstrapKeygenProcess' = 'Invoke-CddsiTestDirectVmBootstrapKeygenProcess'
            'Remove-CddsiFastLaneVmBootstrapOwnedRoot' = 'Remove-CddsiTestDirectVmBootstrapOwnedRoot'
            'Remove-CddsiFastLaneVmBootstrapOwnedPackageRoot' = 'Remove-CddsiTestDirectVmBootstrapOwnedPackageRoot'
            'Expand-CddsiFastLaneVmBootstrapPackage' = 'Expand-CddsiTestDirectVmBootstrapPackage'
            'New-CddsiFastLaneVmBootstrapOnboardingFailureResult' = 'New-CddsiTestDirectVmBootstrapOnboardingFailureResult'
        }
        foreach ($facadeName in @($directFacadeNames.Keys)) {
            $facadeAst = @($runnerAst.EndBlock.Statements | Where-Object {
                $_ -is [Management.Automation.Language.FunctionDefinitionAst] -and
                    $_.Name -ceq $facadeName
            })
            if ($facadeAst.Count -ne 1) {
                throw ('VM_BOOTSTRAP_TEST_DIRECT_FACADE_AST_INVALID:' + $facadeName)
            }
            $sourceHeader = 'function ' + $facadeName
            $renamedHeader = 'function ' + $directFacadeNames[$facadeName]
            $definitionText = $facadeAst[0].Extent.Text
            if (-not $definitionText.StartsWith($sourceHeader, [StringComparison]::Ordinal)) {
                throw ('VM_BOOTSTRAP_TEST_DIRECT_FACADE_HEADER_INVALID:' + $facadeName)
            }
            [void]$capturedFunctionDefinitions.Add(
                $renamedHeader + $definitionText.Substring($sourceHeader.Length))
        }
        $handoffOnboardingAst = @($runnerAst.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding'
        }, $true))
        if ($handoffOnboardingAst.Count -ne 1) {
            throw 'VM_BOOTSTRAP_TEST_HANDOFF_ONBOARDING_AST_INVALID'
        }
        $onboardingAst = @($handoffOnboardingAst[0].Body.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'Invoke-CddsiFastLaneVmBootstrapOnboardingClosure'
        }, $true))
        if ($onboardingAst.Count -ne 1) { throw 'VM_BOOTSTRAP_TEST_ONBOARDING_CLOSURE_AST_INVALID' }
        $phaseOneSourceHeader = 'function Invoke-CddsiFastLaneVmBootstrapOnboardingClosure'
        $phaseOneTestHeader = 'function Invoke-CddsiTestVmBootstrapPhaseOneClosure'
        $phaseOneDefinitionText = $onboardingAst[0].Extent.Text
        if (-not $phaseOneDefinitionText.StartsWith(
                $phaseOneSourceHeader, [StringComparison]::Ordinal)) {
            throw 'VM_BOOTSTRAP_TEST_ONBOARDING_CLOSURE_HEADER_INVALID'
        }
        [void]$capturedFunctionDefinitions.Add(
            $phaseOneTestHeader + $phaseOneDefinitionText.Substring($phaseOneSourceHeader.Length))
        foreach ($nestedName in @(
            'New-CddsiFastLaneVmBootstrapDirectoryCreateOnly',
            'Set-CddsiFastLaneVmBootstrapProtectedAcl',
            'Remove-CddsiFastLaneVmBootstrapOwnedTreeSafely',
            'Remove-CddsiFastLaneVmBootstrapOwnedRoot',
            'Remove-CddsiFastLaneVmBootstrapOwnedPackageRoot',
            'Expand-CddsiFastLaneVmBootstrapPackage',
            'New-CddsiFastLaneVmBootstrapOnboardingFailureResult',
            'Invoke-CddsiFastLaneVmBootstrapMutationClosure'
        )) {
            $nestedAst = @($onboardingAst[0].Body.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -ceq $nestedName
            }, $true))
            if ($nestedAst.Count -ne 1) { throw ('VM_BOOTSTRAP_TEST_NESTED_AST_INVALID:' + $nestedName) }
            [void]$capturedFunctionDefinitions.Add($nestedAst[0].Extent.Text)
        }
        foreach ($phaseTwoHelperName in @(
            'Test-CddsiFastLaneVmBootstrapInteger',
            'Test-CddsiFastLaneVmBootstrapExecutionContext',
            'Test-CddsiFastLaneVmAutomationContract',
            'Test-CddsiFastLaneVmBootstrapResultBinding',
            'Test-CddsiFastLaneVmRepositoryAndProtectionFacts',
            'Test-CddsiFastLaneVmAutomationCurrentTaskBinding',
            'New-CddsiFastLaneVmAutomationPrompt',
            'ConvertFrom-CddsiFastLaneVmAutomationTomlBasicString',
            'Read-CddsiFastLaneVmAutomationToml',
            'Read-CddsiFastLaneVmAutomationTomlIdentity',
            'Get-CddsiFastLaneVmAutomationTomlMatch',
            'Get-CddsiFastLaneVmAutomationTomlReadback'
        )) {
            $phaseTwoHelperAst = @($handoffOnboardingAst[0].Body.FindAll({
                param($node)
                $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -ceq $phaseTwoHelperName
            }, $true))
            if ($phaseTwoHelperAst.Count -ne 1) {
                throw ('VM_BOOTSTRAP_TEST_PHASE2_HELPER_AST_INVALID:' + $phaseTwoHelperName)
            }
            [void]$capturedFunctionDefinitions.Add($phaseTwoHelperAst[0].Extent.Text)
        }
        $handoffClosureAst = @($handoffOnboardingAst[0].Body.FindAll({
            param($node)
            $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                $node.Name -ceq 'New-CddsiFastLaneVmBootstrapHandoffClosure'
        }, $true))
        if ($handoffClosureAst.Count -ne 1) { throw 'VM_BOOTSTRAP_TEST_HANDOFF_CLOSURE_AST_INVALID' }
        [void]$capturedFunctionDefinitions.Add($handoffClosureAst[0].Extent.Text)
        $capturedFunctionsRoot = Join-Path ([IO.Path]::GetTempPath()) `
            ('cddsi-test-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($capturedFunctionsRoot)
        $capturedFunctionsOwner = [pscustomobject][ordered]@{
            SchemaVersion = 1
            ContractVersion = 'cddsi-fast-lane-local-transport-owner-v1'
            Owner = 'CDDsiFastLaneGitOutboxTests'
            SyntheticOnly = $true
        }
        [IO.File]::WriteAllText(
            (Join-Path $capturedFunctionsRoot '.cddsi-owner.json'),
            ((ConvertTo-CddsiVmTestRelayCanonicalJson $capturedFunctionsOwner) + "`n"),
            (New-Object Text.UTF8Encoding($false)))
        [void]$script:FixtureRoots.Add($capturedFunctionsRoot)
        $capturedFunctionsPath = Join-Path $capturedFunctionsRoot 'captured-functions.ps1'
        [IO.File]::WriteAllText(
            $capturedFunctionsPath,
            (($capturedFunctionDefinitions -join "`r`n`r`n") + "`r`n"),
            (New-Object Text.UTF8Encoding($true)))
        . $capturedFunctionsPath
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
        $script:OutboxFixtureTemplateRoot = $null
        $script:OutboxFixtureTemplateGenesis = $null

        function Invoke-FixtureGit {
            param([Parameter(Mandatory = $true)][string[]]$Arguments)
            $output = & $script:GitExecutable -c core.hooksPath=NUL -c credential.helper= `
                -c gc.auto=0 -c maintenance.auto=false @Arguments 2>&1
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
                MaximumRuntimeSeconds = 10
                MaximumGitCommandSeconds = 2
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

        function Get-SyntheticZipCrc32 {
            param([Parameter(Mandatory = $true)][byte[]]$Bytes)

            [uint64]$crc = [uint32]::MaxValue
            foreach ($value in $Bytes) {
                $crc = [uint64](($crc -bxor [uint64]$value) -band [uint64]4294967295)
                for ($bit = 0; $bit -lt 8; $bit++) {
                    if (($crc -band [uint64]1) -ne 0) {
                        $crc = [uint64]((($crc -shr 1) -bxor [uint64]3988292384) -band [uint64]4294967295)
                    }
                    else { $crc = [uint64](($crc -shr 1) -band [uint64]4294967295) }
                }
            }
            return [uint32](($crc -bxor [uint64]4294967295) -band [uint64]4294967295)
        }

        function New-SyntheticStoreZip {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)][System.Collections.IDictionary]$EntryBytes
            )

            $stream = [IO.File]::Open($Path, [IO.FileMode]::CreateNew, [IO.FileAccess]::Write, [IO.FileShare]::None)
            $writer = New-Object IO.BinaryWriter($stream, (New-Object Text.UTF8Encoding($false)), $true)
            $central = @()
            try {
                foreach ($name in @($EntryBytes.Keys)) {
                    $nameBytes = [Text.Encoding]::UTF8.GetBytes([string]$name)
                    [byte[]]$content = $EntryBytes[$name]
                    $crc = Get-SyntheticZipCrc32 $content
                    $offset = [uint32]$stream.Position
                    $writer.Write([uint32]0x04034B50)
                    $writer.Write([uint16]10); $writer.Write([uint16]0x0800); $writer.Write([uint16]0)
                    $writer.Write([uint16]0); $writer.Write([uint16]0x0021)
                    $writer.Write([uint32]$crc); $writer.Write([uint32]$content.Length); $writer.Write([uint32]$content.Length)
                    $writer.Write([uint16]$nameBytes.Length); $writer.Write([uint16]0)
                    $writer.Write($nameBytes); $writer.Write($content)
                    $central += [pscustomobject]@{
                        NameBytes = $nameBytes; Crc32 = [uint32]$crc
                        Length = [uint32]$content.Length; Offset = $offset
                    }
                }
                $centralOffset = [uint32]$stream.Position
                foreach ($item in $central) {
                    $writer.Write([uint32]0x02014B50)
                    $writer.Write([uint16]10); $writer.Write([uint16]10)
                    $writer.Write([uint16]0x0800); $writer.Write([uint16]0)
                    $writer.Write([uint16]0); $writer.Write([uint16]0x0021)
                    $writer.Write([uint32]$item.Crc32); $writer.Write([uint32]$item.Length); $writer.Write([uint32]$item.Length)
                    $writer.Write([uint16]$item.NameBytes.Length); $writer.Write([uint16]0); $writer.Write([uint16]0)
                    $writer.Write([uint16]0); $writer.Write([uint16]0); $writer.Write([uint32]0)
                    $writer.Write([uint32]$item.Offset); $writer.Write([byte[]]$item.NameBytes)
                }
                $centralSize = [uint32]($stream.Position - $centralOffset)
                $writer.Write([uint32]0x06054B50)
                $writer.Write([uint16]0); $writer.Write([uint16]0)
                $writer.Write([uint16]$central.Count); $writer.Write([uint16]$central.Count)
                $writer.Write([uint32]$centralSize); $writer.Write([uint32]$centralOffset); $writer.Write([uint16]0)
                $writer.Flush(); $stream.Flush($true)
            }
            finally { $writer.Dispose(); $stream.Dispose() }
        }

        function New-VmBootstrapFixture {
            $root = Join-Path ([IO.Path]::GetTempPath()) ('cddsi-test-' + [guid]::NewGuid().ToString('N'))
            [void][IO.Directory]::CreateDirectory($root)
            $rootOwner = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-local-transport-owner-v1'
                Owner = 'CDDsiFastLaneGitOutboxTests'; SyntheticOnly = $true
            }
            [IO.File]::WriteAllText(
                (Join-Path $root '.cddsi-owner.json'),
                ((ConvertTo-CddsiVmTestRelayCanonicalJson $rootOwner) + "`n"),
                (New-Object Text.UTF8Encoding($false)))
            [void]$script:FixtureRoots.Add($root)
            $productRoot = Join-Path $root 'product'
            $operatorRoot = Join-Path $root 'operator'
            $projectOwnerRoot = Join-Path $operatorRoot 'CDDsi'
            $fastLaneOwnerRoot = Join-Path $projectOwnerRoot 'FastLane'
            $packageParent = Join-Path $fastLaneOwnerRoot 'packages'
            $credentialParent = Join-Path $fastLaneOwnerRoot 'credentials'
            $programFilesRoot = Join-Path $root 'program-files'
            $systemRoot = Join-Path $root 'windows'
            foreach ($path in @(
                $productRoot, $operatorRoot, $projectOwnerRoot, $fastLaneOwnerRoot,
                $packageParent, $credentialParent,
                $programFilesRoot, $systemRoot
            )) {
                [void][IO.Directory]::CreateDirectory($path)
            }
            foreach ($ownedParent in @(
                @{ Path = $projectOwnerRoot; Role = 'Project' },
                @{ Path = $fastLaneOwnerRoot; Role = 'FastLane' },
                @{ Path = $packageParent; Role = 'PackageParent' },
                @{ Path = $credentialParent; Role = 'CredentialParent' }
            )) {
                Set-CddsiFastLaneVmBootstrapProtectedAcl `
                    -Path $ownedParent.Path -PathKind Directory
                $parentMarker = [pscustomobject][ordered]@{
                    SchemaVersion = 1
                    ContractVersion = 'cddsi-fast-lane-bootstrap-directory-owner-v1'
                    Role = $ownedParent.Role
                    RootBindingSha256 = Get-CddsiFastLaneVmBootstrapOwnedDirectoryBindingToken `
                        $ownedParent.Path
                    AclBindingSha256 = Get-CddsiFastLaneVmBootstrapAclBindingToken `
                        -Path $ownedParent.Path -PathKind Directory
                }
                Write-CddsiFastLaneCanonicalFile `
                    -Path (Join-Path $ownedParent.Path '.cddsi-directory-owner.json') `
                    -Value $parentMarker -CreateOnly
            }

            $toolSpecs = @(
                [pscustomobject]@{ ToolId = 'Git'; VmPath = '%PROGRAMFILES%\Git\cmd\git.exe'; RelativePath = 'Git\cmd\git.exe' },
                [pscustomobject]@{ ToolId = 'OpenSSH'; VmPath = '%PROGRAMFILES%\Git\usr\bin\ssh.exe'; RelativePath = 'Git\usr\bin\ssh.exe' },
                [pscustomobject]@{ ToolId = 'OpenSSHKeygen'; VmPath = '%PROGRAMFILES%\Git\usr\bin\ssh-keygen.exe'; RelativePath = 'Git\usr\bin\ssh-keygen.exe' },
                [pscustomobject]@{ ToolId = 'PowerShell7'; VmPath = '%PROGRAMFILES%\PowerShell\7\pwsh.exe'; RelativePath = 'PowerShell\7\pwsh.exe' },
                [pscustomobject]@{ ToolId = 'WindowsPowerShell'; VmPath = '%SYSTEMROOT%\System32\WindowsPowerShell\v1.0\powershell.exe'; RelativePath = 'System32\WindowsPowerShell\v1.0\powershell.exe' }
            )
            $tools = @()
            $keygenPath = $null
            foreach ($toolSpec in $toolSpecs) {
                $toolRoot = if ($toolSpec.ToolId -ceq 'WindowsPowerShell') { $systemRoot } else { $programFilesRoot }
                $toolPath = Join-Path $toolRoot $toolSpec.RelativePath
                [void][IO.Directory]::CreateDirectory([IO.Path]::GetDirectoryName($toolPath))
                [IO.File]::WriteAllBytes($toolPath, [Text.Encoding]::ASCII.GetBytes('synthetic-' + $toolSpec.ToolId))
                $toolSha = (Get-FileHash -LiteralPath $toolPath -Algorithm SHA256).Hash.ToLowerInvariant()
                $tools += [pscustomobject][ordered]@{
                    ToolId = $toolSpec.ToolId; VmPath = $toolSpec.VmPath; Sha256 = $toolSha
                }
                if ($toolSpec.ToolId -ceq 'OpenSSHKeygen') { $keygenPath = $toolPath }
            }

            $sourcePaths = @(
                'config/fast-lane-policy.psd1',
                'operator/fast-lane/trust/github-known-hosts',
                'operator/fast-lane/invoke-git-outbox.ps1',
                'operator/fast-lane/prompts/vm-poll.md',
                'lib/vm-reset.ps1',
                'operator/fast-lane/invoke-vm-reset-live.ps1',
                'operator/fast-lane/providers/windows-vm-reset.ps1',
                'lib/common.ps1', 'lib/vm-calibration.ps1', 'lib/vm-test-relay.ps1',
                'operator/fast-lane/runbooks/negative-permissions.md',
                'operator/fast-lane/runbooks/reset-smoke.md',
                'operator/fast-lane/runbooks/unattended-smoke.md',
                'operator/fast-lane/runbooks/vm-bootstrap.md',
                'runbooks/negative-permissions.json', 'runbooks/unattended-smoke.json'
            )
            $entryBytes = [ordered]@{}
            $inventoryEntries = @()
            for ($index = 0; $index -lt $sourcePaths.Count; $index++) {
                $entryPath = 'payload/runtime/{0:d2}.txt' -f ($index + 1)
                $bytes = [Text.Encoding]::UTF8.GetBytes(('fixture-content-{0:d2}' -f ($index + 1)))
                $entryBytes[$entryPath] = $bytes
                $inventoryEntries += [pscustomobject][ordered]@{
                    Ordinal = $index + 1; Category = 'Runtime'; Path = $entryPath
                    SourcePath = $sourcePaths[$index]; Sha256 = Get-CddsiFastLaneVmBootstrapBytesSha256 $bytes
                    GitBlobSha = 'a' * 40; LengthBytes = $bytes.Length
                }
            }
            $contentPayload = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-onboarding-content-v1'
                Entries = @($inventoryEntries)
            }
            $contentDigest = Get-CddsiFastLaneVmBootstrapBindingToken $contentPayload
            $inventory = [pscustomobject][ordered]@{
                SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-onboarding-inventory-v1'
                EntryCount = 16; Entries = @($inventoryEntries); BundleContentDigestSha256 = $contentDigest
                InventoryBindingToken = $null
            }
            $inventoryPayload = [ordered]@{}
            foreach ($property in $inventory.PSObject.Properties) {
                if ($property.Name -cne 'InventoryBindingToken') { $inventoryPayload[$property.Name] = $property.Value }
            }
            $inventory.InventoryBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $inventoryPayload
            $inventoryBytes = (New-Object Text.UTF8Encoding($false)).GetBytes(
                (ConvertTo-CddsiVmTestRelayCanonicalJson $inventory) + "`n")
            $inventorySha = Get-CddsiFastLaneVmBootstrapBytesSha256 $inventoryBytes
            $policyEntry = @($inventoryEntries | Where-Object SourcePath -eq 'config/fast-lane-policy.psd1')[0]
            $knownHostsEntry = @($inventoryEntries | Where-Object SourcePath -eq 'operator/fast-lane/trust/github-known-hosts')[0]
            $commitSha = '1' * 40
            $treeSha = '2' * 40
            $hostToVmGenesis = '3' * 40
            $vmToHostGenesis = '4' * 40
            $gitExecutableSha = [string](@($tools | Where-Object ToolId -eq 'Git')[0]).Sha256
            $zipEntryNames = [string[]]@('manifest.json', 'inventory.json') + [string[]]@($inventoryEntries.Path)
            [Array]::Sort($zipEntryNames, [StringComparer]::Ordinal)
            $manifest = [pscustomobject][ordered]@{
                SchemaVersion = 3; ContractVersion = 'cddsi-fast-lane-vm-onboarding-manifest-v3'
                Purpose = 'P10A_0A_VM_ONBOARDING_DIAGNOSTIC_ONLY'; EvidenceClass = 'DIAGNOSTIC_ONLY'; Mode = 'DryRun'
                Policy = [pscustomobject][ordered]@{
                    Path = 'payload/git/config/fast-lane-policy.psd1'; Sha256 = $policyEntry.Sha256
                    ProtocolVersion = 'cddsi-vm-test-relay-v1'
                    ProductRepository = [pscustomobject][ordered]@{
                        RepositoryToken = 'github.com/synthetic/product'; Id = 7001L
                        NodeId = 'R_SYNTHETIC_PRODUCT'; FullName = 'synthetic/product'
                        Visibility = 'PUBLIC'; HostWriteRefPattern = 'refs/heads/codex/repair/*'
                    }
                    HostToVmRepository = [pscustomobject][ordered]@{
                        RepositoryToken = 'github.com/synthetic/host-to-vm'; Id = 7002L
                        NodeId = 'R_SYNTHETIC_HOST_TO_VM'; FullName = 'synthetic/host-to-vm'
                        Visibility = 'PUBLIC'; Ref = 'refs/heads/main'; GenesisSha = $hostToVmGenesis
                    }
                    VmToHostRepository = [pscustomobject][ordered]@{
                        RepositoryToken = 'github.com/synthetic/vm-to-host'; Id = 7003L
                        NodeId = 'R_SYNTHETIC_VM_TO_HOST'; FullName = 'synthetic/vm-to-host'
                        Visibility = 'PUBLIC'; Ref = 'refs/heads/main'; GenesisSha = $vmToHostGenesis
                    }
                    Automation = [pscustomobject][ordered]@{
                        IntervalMinutes = 1
                        HostAutomationId = 'cddsi-fast-lane-hostcoordinator-minute-poll'
                        HostInitialStatus = 'PAUSED'
                        VmAutomationId = 'cddsi-fast-lane-vmtester-minute-poll'
                        VmInitialStatus = 'PAUSED'; VmMustBeCreatedOnDevice = $true
                        BootstrapAutomation = [pscustomobject][ordered]@{
                            Id = 'cddsi-fast-lane-vmtester-minute-poll'; Kind = 'heartbeat'
                            Name = 'CDDsi Fast Lane VmTester minute poll'; Status = 'PAUSED'
                            RRule = 'FREQ=MINUTELY;INTERVAL=1'; CadenceMinutes = 1
                            DestinationContract = 'local'; TargetTaskToken = 'CURRENT_TASK'
                            ReconcileMode = 'CREATE_OR_UPDATE_EXACTLY_ONE'
                        }
                    }
                    Envelope = [pscustomobject][ordered]@{
                        MaximumAgeSeconds = 900; MaximumClockSkewSeconds = 120
                    }
                    SshTrust = [pscustomobject][ordered]@{
                        GitHubHost = 'github.com'; OpenSshToolId = 'OpenSSH'
                        OpenSshVmPath = '%PROGRAMFILES%\Git\usr\bin\ssh.exe'
                        OpenSshKeygenToolId = 'OpenSSHKeygen'
                        OpenSshKeygenVmPath = '%PROGRAMFILES%\Git\usr\bin\ssh-keygen.exe'
                        KnownHostsPath = 'payload/git/operator/fast-lane/trust/github-known-hosts'
                        KnownHostsSha256 = $knownHostsEntry.Sha256; StrictHostKeyCheckingRequired = $true
                    }
                }
                Product = [pscustomobject][ordered]@{
                    CommitSha = $commitSha; TreeSha = $treeSha; SourceCommitVerified = $true
                    Repository = [pscustomobject][ordered]@{
                        Id = 7001L; NodeId = 'R_SYNTHETIC_PRODUCT'; FullName = 'synthetic/product'
                    }
                    RepairRef = 'refs/heads/codex/repair/bootstrap-fixture'
                    GitExecutableSha256 = $gitExecutableSha
                    VmAccess = 'READ_ONLY_EXACT_COMMIT'; CodeWriteAuthority = 'HOST_ONLY_REPAIR_REF'
                }
                ControlRepositories = [pscustomobject][ordered]@{
                    HostToVm = [pscustomobject][ordered]@{
                        Repository = [pscustomobject][ordered]@{
                            Id = 7002L; NodeId = 'R_SYNTHETIC_HOST_TO_VM'; FullName = 'synthetic/host-to-vm'
                        }
                        GenesisSha = $hostToVmGenesis; VmAccess = 'READ_ONLY'; HostAccess = 'APPEND_ONLY'
                    }
                    VmToHost = [pscustomobject][ordered]@{
                        Repository = [pscustomobject][ordered]@{
                            Id = 7003L; NodeId = 'R_SYNTHETIC_VM_TO_HOST'; FullName = 'synthetic/vm-to-host'
                        }
                        GenesisSha = $vmToHostGenesis; VmAccess = 'APPEND_ONLY'; HostAccess = 'READ_ONLY'
                    }
                }
                Tools = @($tools)
                Constraints = [pscustomobject][ordered]@{
                    VmMayEditProductCode = $false; VmMayCommitOrPushProductCode = $false
                    HostMayRunProductLive = $false; CredentialsIncluded = $false
                    AutoMerge = $false; AutoPromotion = $false; AutoRelease = $false
                }
                Automation = [pscustomobject][ordered]@{
                    VmAutomationId = 'cddsi-fast-lane-vmtester-minute-poll'
                    VmInitialStatus = 'PAUSED'; IntervalMinutes = 1
                }
                BootstrapAutomation = [pscustomobject][ordered]@{
                    Id = 'cddsi-fast-lane-vmtester-minute-poll'
                    Kind = 'heartbeat'; Name = 'CDDsi Fast Lane VmTester minute poll'
                    Status = 'PAUSED'; RRule = 'FREQ=MINUTELY;INTERVAL=1'; CadenceMinutes = 1
                    DestinationContract = 'local'; TargetTaskToken = 'CURRENT_TASK'
                    ReconcileMode = 'CREATE_OR_UPDATE_EXACTLY_ONE'
                }
                Inventory = [pscustomobject][ordered]@{
                    Sha256 = $inventorySha; InventoryBindingToken = $inventory.InventoryBindingToken
                    BundleContentDigestSha256 = $contentDigest
                }
                Zip = [pscustomobject][ordered]@{
                    EntryTimestampUtc = '1980-01-01T00:00:00Z'; ExpectedEntries = @($zipEntryNames)
                }
                ManifestBindingToken = $null
            }
            $manifestPayload = [ordered]@{}
            foreach ($property in $manifest.PSObject.Properties) {
                if ($property.Name -cne 'ManifestBindingToken') { $manifestPayload[$property.Name] = $property.Value }
            }
            $manifest.ManifestBindingToken = Get-CddsiFastLaneVmBootstrapBindingToken $manifestPayload
            $manifestBytes = (New-Object Text.UTF8Encoding($false)).GetBytes(
                (ConvertTo-CddsiVmTestRelayCanonicalJson $manifest) + "`n")
            $zipPath = Join-Path $root 'cddsi-fast-lane-vm-onboarding.zip'
            $allEntryBytes = [ordered]@{}
            foreach ($entryName in $zipEntryNames) {
                $allEntryBytes[$entryName] = if ($entryName -ceq 'manifest.json') { $manifestBytes }
                elseif ($entryName -ceq 'inventory.json') { $inventoryBytes }
                else { [byte[]]$entryBytes[$entryName] }
            }
            New-SyntheticStoreZip -Path $zipPath -EntryBytes $allEntryBytes
            $zipSha = (Get-FileHash -LiteralPath $zipPath -Algorithm SHA256).Hash.ToLowerInvariant()
            $packageArguments = @{
                ZipPath = $zipPath; ExpectedZipSha256 = $zipSha
                ExpectedZipLengthBytes = [IO.FileInfo]::new($zipPath).Length
                ExpectedManifestSha256 = Get-CddsiFastLaneVmBootstrapBytesSha256 $manifestBytes
                ExpectedManifestLengthBytes = $manifestBytes.Length
                ExpectedManifestBindingToken = $manifest.ManifestBindingToken
                ExpectedInventorySha256 = $inventorySha; ExpectedInventoryLengthBytes = $inventoryBytes.Length
                ExpectedInventoryBindingToken = $inventory.InventoryBindingToken
                ExpectedBundleContentDigestSha256 = $contentDigest
                ExpectedProductCommitSha = $commitSha; ExpectedProductTreeSha = $treeSha
                ProgramFilesRoot = $programFilesRoot; SystemRoot = $systemRoot
            }
            return [pscustomobject]@{
                Root = $root; ProductRoot = $productRoot; OperatorRoot = $operatorRoot
                PackageParent = $packageParent; CredentialParent = $credentialParent
                CredentialRoot = Join-Path $credentialParent `
                    ('cddsi-vm-bootstrap-' + [guid]::NewGuid().ToString('N'))
                PackageStagingRoot = Join-Path $packageParent `
                    ('cddsi-vm-package-' + [guid]::NewGuid().ToString('N'))
                PackageArguments = $packageArguments; KeygenPath = $keygenPath
                KeygenSha256 = (@($tools | Where-Object ToolId -eq 'OpenSSHKeygen')[0]).Sha256
            }
        }

        function Invoke-VmBootstrapFixtureCore {
            param(
                [Parameter(Mandatory = $true)]$Package,
                [Parameter(Mandatory = $true)][string]$CredentialRoot,
                [Parameter(Mandatory = $true)][string]$ProductRoot,
                [Parameter(Mandatory = $true)][string]$SshKeygenExecutable,
                [Parameter(Mandatory = $true)][string]$ExpectedSshKeygenSha256
            )
            $createdOwnership = $null
            return Invoke-CddsiFastLaneVmBootstrapMutationClosure `
                -Package $Package -CredentialRoot $CredentialRoot -ProductRoot $ProductRoot `
                -SshKeygenExecutable $SshKeygenExecutable `
                -ExpectedSshKeygenSha256 $ExpectedSshKeygenSha256 `
                -CreatedOwnership ([ref]$createdOwnership)
        }

        function New-VmAutomationTomlFixture {
            param(
                [Parameter(Mandatory = $true)]$Fixture,
                [Parameter(Mandatory = $true)][string]$Prompt
            )

            $localApplicationDataRoot = Join-Path $Fixture.Root 'local-app-data'
            $codexHome = Join-Path $Fixture.Root 'codex-home'
            $automationRoot = Join-Path $codexHome 'automations'
            $automationDirectory = Join-Path $automationRoot 'cddsi-fast-lane-vmtester-minute-poll'
            foreach ($path in @($localApplicationDataRoot, $codexHome, $automationRoot, $automationDirectory)) {
                [void][IO.Directory]::CreateDirectory($path)
            }
            $encodedPrompt = $Prompt.Replace('\', '\\').Replace('"', '\"').Replace("`b", '\b').
                Replace("`t", '\t').Replace("`n", '\n').Replace("`f", '\f').Replace("`r", '\r')
            $text = @(
                'version = 1'
                'id = "cddsi-fast-lane-vmtester-minute-poll"'
                'kind = "heartbeat"'
                'name = "CDDsi Fast Lane VmTester minute poll"'
                ('prompt = "' + $encodedPrompt + '"')
                'status = "PAUSED"'
                'rrule = "FREQ=MINUTELY;INTERVAL=1"'
                'target_thread_id = "019f7000-1234-7abc-8def-0123456789ab"'
                'created_at = 100'
                'updated_at = 101'
            ) -join "`n"
            $canonicalText = $text + "`n"
            $bytes = (New-Object Text.UTF8Encoding($false, $true)).GetBytes($canonicalText)
            $tomlPath = Join-Path $automationDirectory 'automation.toml'
            [IO.File]::WriteAllBytes($tomlPath, $bytes)
            return [pscustomobject]@{
                LocalApplicationDataRoot = $localApplicationDataRoot
                CodexHome = $codexHome; AutomationRoot = $automationRoot
                AutomationDirectory = $automationDirectory; TomlPath = $tomlPath
                Text = $text; CanonicalText = $canonicalText; Bytes = $bytes
                Sha256 = Get-CddsiFastLaneVmBootstrapBytesSha256 $bytes
                LengthBytes = [long]$bytes.LongLength; Prompt = $Prompt
                TargetThreadId = '019f7000-1234-7abc-8def-0123456789ab'
            }
        }

        function Invoke-VmAutomationTomlMatchForTest {
            param([Parameter(Mandatory = $true)][string]$AutomationRoot)

            $match = $null
            try {
                $match = Get-CddsiFastLaneVmAutomationTomlMatch -AutomationRoot $AutomationRoot
                return $match
            }
            finally {
                if ($null -ne $match -and $null -ne $match.Stream) {
                    $match.Stream.Dispose()
                }
            }
        }

        function Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects {
            param([Parameter(Mandatory = $true)]$Result)

            $Result.Status | Should -BeExactly 'VM_BOOTSTRAP_BLOCKED'
            $Result.Changed | Should -BeFalse
            $Result.DirectoryCreateCount | Should -Be 0
            $Result.FileWriteCount | Should -Be 0
            $Result.AclMutationCount | Should -Be 0
            $Result.ProcessInvocationCount | Should -Be 0
            $Result.DirectoryDeleteCount | Should -Be 0
            $Result.CleanupRequired | Should -BeFalse
            $Result.CleanupSucceeded | Should -BeTrue
            $Result.NetworkRequestCount | Should -Be 0
            $Result.GitInvocationCount | Should -Be 0
            $Result.ProductLiveInvocationCount | Should -Be 0
            $Result.ProductWriteCount | Should -Be 0
        }

        function Assert-VmAutomationTomlLeaseReleased {
            param([Parameter(Mandatory = $true)][string]$Path)

            $exclusive = [IO.File]::Open(
                $Path, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::None)
            try { $exclusive.CanRead | Should -BeTrue }
            finally { $exclusive.Dispose() }
        }

        function Get-VmBootstrapTestDirectorySecurity {
            param([Parameter(Mandatory = $true)][string]$Path)

            $sections = [Security.AccessControl.AccessControlSections]::Access -bor
                [Security.AccessControl.AccessControlSections]::Owner
            $directory = [IO.DirectoryInfo]::new($Path)
            $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
            if ($null -ne $aclExtensions) {
                return [IO.FileSystemAclExtensions]::GetAccessControl($directory, $sections)
            }
            return $directory.GetAccessControl($sections)
        }

        function Set-VmBootstrapTestDirectorySecurity {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Security
            )

            $directory = [IO.DirectoryInfo]::new($Path)
            $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
            if ($null -ne $aclExtensions) {
                [IO.FileSystemAclExtensions]::SetAccessControl($directory, $Security)
                return
            }
            $directory.SetAccessControl($Security)
        }

        function Get-VmBootstrapTestFileSecurity {
            param([Parameter(Mandatory = $true)][string]$Path)

            $sections = [Security.AccessControl.AccessControlSections]::Access -bor
                [Security.AccessControl.AccessControlSections]::Owner
            $file = [IO.FileInfo]::new($Path)
            $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
            if ($null -ne $aclExtensions) {
                return [IO.FileSystemAclExtensions]::GetAccessControl($file, $sections)
            }
            return $file.GetAccessControl($sections)
        }

        function Set-VmBootstrapTestFileSecurity {
            param(
                [Parameter(Mandatory = $true)][string]$Path,
                [Parameter(Mandatory = $true)]$Security
            )

            $file = [IO.FileInfo]::new($Path)
            $aclExtensions = 'System.IO.FileSystemAclExtensions' -as [type]
            if ($null -ne $aclExtensions) {
                [IO.FileSystemAclExtensions]::SetAccessControl($file, $Security)
                return
            }
            $file.SetAccessControl($Security)
        }

        function Remove-CddsiGitOutboxFixtureRootSafely {
            param([Parameter(Mandatory = $true)][string]$Root)

            $fullRoot = [IO.Path]::GetFullPath($Root).TrimEnd(
                [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $tempRoot = [IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd(
                [IO.Path]::DirectorySeparatorChar, [IO.Path]::AltDirectorySeparatorChar)
            $parent = [IO.Directory]::GetParent($fullRoot)
            if (
                $null -eq $parent -or
                -not $parent.FullName.Equals($tempRoot, [StringComparison]::OrdinalIgnoreCase) -or
                [IO.Path]::GetFileName($fullRoot) -notmatch '^cddsi-test-[a-f0-9]{32}$'
            ) {
                throw 'GIT_OUTBOX_FIXTURE_CLEANUP_ROOT_INVALID'
            }
            if (-not [IO.Directory]::Exists($fullRoot)) { return }

            $rootInfo = [IO.DirectoryInfo]::new($fullRoot)
            if (($rootInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'GIT_OUTBOX_FIXTURE_CLEANUP_REPARSE_BLOCKED'
            }
            $markerPath = Join-Path $fullRoot '.cddsi-owner.json'
            if (-not [IO.File]::Exists($markerPath)) {
                throw 'GIT_OUTBOX_FIXTURE_CLEANUP_OWNER_INVALID'
            }
            $markerInfo = [IO.FileInfo]::new($markerPath)
            if (($markerInfo.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                throw 'GIT_OUTBOX_FIXTURE_CLEANUP_REPARSE_BLOCKED'
            }
            try {
                $owner = ConvertFrom-Json -InputObject ([IO.File]::ReadAllText($markerPath)) `
                    -ErrorAction Stop
            } catch {
                throw 'GIT_OUTBOX_FIXTURE_CLEANUP_OWNER_INVALID'
            }
            if (
                -not (Test-CddsiExactPropertySet -InputObject $owner -Expected @(
                    'SchemaVersion', 'ContractVersion', 'Owner', 'SyntheticOnly'
                )) -or
                $owner.SchemaVersion -ne 1 -or
                $owner.ContractVersion -cne 'cddsi-fast-lane-local-transport-owner-v1' -or
                $owner.Owner -cne 'CDDsiFastLaneGitOutboxTests' -or
                $owner.SyntheticOnly -ne $true
            ) {
                throw 'GIT_OUTBOX_FIXTURE_CLEANUP_OWNER_INVALID'
            }

            $pending = [Collections.Generic.Stack[IO.DirectoryInfo]]::new()
            $directories = [Collections.Generic.List[IO.DirectoryInfo]]::new()
            $files = [Collections.Generic.List[IO.FileInfo]]::new()
            $pending.Push($rootInfo)
            while ($pending.Count -gt 0) {
                $current = $pending.Pop()
                if (($current.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                    throw 'GIT_OUTBOX_FIXTURE_CLEANUP_REPARSE_BLOCKED'
                }
                $directories.Add($current)
                foreach ($file in $current.EnumerateFiles(
                        '*', [IO.SearchOption]::TopDirectoryOnly)) {
                    if (($file.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw 'GIT_OUTBOX_FIXTURE_CLEANUP_REPARSE_BLOCKED'
                    }
                    $files.Add($file)
                }
                foreach ($child in $current.EnumerateDirectories(
                        '*', [IO.SearchOption]::TopDirectoryOnly)) {
                    if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                        throw 'GIT_OUTBOX_FIXTURE_CLEANUP_REPARSE_BLOCKED'
                    }
                    $pending.Push($child)
                }
            }

            foreach ($file in $files) {
                $file.Attributes = [IO.FileAttributes]::Normal
                $file.Delete()
            }
            foreach ($directory in @($directories | Sort-Object `
                        @{ Expression = { $_.FullName.Length }; Descending = $true }, `
                        @{ Expression = { $_.FullName }; Descending = $true })) {
                $directory.Attributes = [IO.FileAttributes]::Directory
                $directory.Delete($false)
            }
        }
    }

    AfterAll {
        $cleanupFailures = [Collections.Generic.List[string]]::new()
        foreach ($root in @($script:FixtureRoots)) {
            if ([string]::IsNullOrEmpty([string]$root)) { continue }
            try {
                Remove-CddsiGitOutboxFixtureRootSafely -Root $root
            } catch {
                $cleanupFailures.Add([string]$_.Exception.Message)
            }
        }
        if ($cleanupFailures.Count -ne 0) {
            throw ('GIT_OUTBOX_FIXTURE_CLEANUP_FAILED:' + ($cleanupFailures -join ','))
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
        $defaultBudgetParameters = @{} + $parameters
        [void]$defaultBudgetParameters.Remove('MaximumRuntimeSeconds')
        [void]$defaultBudgetParameters.Remove('MaximumGitCommandSeconds')
        $plan = Invoke-CddsiFastLaneGitOutbox -Operation Poll -Mode TestSafe `
            -MaximumRetryCount 0 @defaultBudgetParameters
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

    It 'uses an exact clean process environment and proves process-tree quiescence on every exit' {
        Initialize-CddsiFastLaneBoundedProcessType
        $fixture = New-OutboxFixture -NumericId 108
        $commandProcessor = (Get-Command cmd.exe -CommandType Application -ErrorAction Stop).Source
        $systemRoot = Split-Path (Split-Path $commandProcessor -Parent) -Parent
        $runnerSource = [IO.File]::ReadAllText($script:RunnerPath)
        $runnerSource | Should -Match 'info\.EnvironmentVariables\.Clear\(\);'
        $runnerSource | Should -Match "'core\.longpaths=true'"
        $runnerSource | Should -Match "'gc\.auto=0'"
        $runnerSource | Should -Match "'maintenance\.auto=false'"
        $runnerSource | Should -Match 'QueryInformationJobObject'
        $runnerSource | Should -Match 'ActiveProcesses'
        $runnerSource | Should -Match 'RequireUnassignedProcessExit'
        $runnerSource | Should -Match 'CleanupAssignedProcess'
        $runnerSource | Should -Match 'bool outputJoined'
        $runnerSource | Should -Match 'bool errorJoined'
        $runnerSource | Should -Match 'GIT_PROCESS_TREE_QUIESCENCE_FORCED'
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

        $treeWorkingRoot = Join-Path $fixture.Root 'process-tree-working-root'
        [void][IO.Directory]::CreateDirectory($treeWorkingRoot)
        $sentinel = Join-Path $treeWorkingRoot 'child-survived.txt'
        $childScript = Join-Path $treeWorkingRoot 'child.cmd'
        $parentScript = Join-Path $treeWorkingRoot 'parent.cmd'
        $childBody = "@echo off`r`n`"%SystemRoot%\System32\ping.exe`" -n 5 127.0.0.1 >NUL`r`n> `"" + $sentinel + "`" echo bad`r`n"
        $parentBody = "@echo off`r`nstart `"`" /b `"%SystemRoot%\System32\cmd.exe`" /d /c call `"" + $childScript +
            "`"`r`n`"%SystemRoot%\System32\ping.exe`" -n 31 127.0.0.1 >NUL`r`n"
        [IO.File]::WriteAllText($childScript, $childBody, [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($parentScript, $parentBody, [Text.Encoding]::ASCII)
        $treeArguments = (@('/d', '/c', 'call', $parentScript) |
            ForEach-Object { ConvertTo-CddsiFastLaneGitQuotedArgument $_ }) -join ' '
        $tree = [Cddsi.FastLane.BoundedProcessRunner]::Run(
            $commandProcessor, $treeArguments, $treeWorkingRoot, $cleanEnvironment, $null, 2000, 4096)
        $tree.TimedOut | Should -BeTrue
        $tree.JobAssigned | Should -BeTrue
        $tree.ProcessTreeTerminated | Should -BeTrue
        [IO.File]::Exists($sentinel) | Should -BeFalse
        [IO.File]::Delete($childScript)
        [IO.File]::Delete($parentScript)
        { [IO.Directory]::Delete($treeWorkingRoot, $false) } | Should -Not -Throw
        [IO.Directory]::Exists($treeWorkingRoot) | Should -BeFalse

        $normalWorkingRoot = Join-Path $fixture.Root 'normal-parent-exit-working-root'
        [void][IO.Directory]::CreateDirectory($normalWorkingRoot)
        $normalSentinel = Join-Path $normalWorkingRoot 'normal-child-survived.txt'
        $normalChildScript = Join-Path $normalWorkingRoot 'normal-child.cmd'
        $normalParentScript = Join-Path $normalWorkingRoot 'normal-parent.cmd'
        $normalChildBody = "@echo off`r`n`"%SystemRoot%\System32\ping.exe`" -n 31 127.0.0.1 >NUL`r`n> `"" +
            $normalSentinel + "`" echo bad`r`n"
        $normalParentBody = "@echo off`r`n`"%SystemRoot%\System32\ping.exe`" -n 2 127.0.0.1 >NUL`r`n" +
            "start `"`" /b `"%SystemRoot%\System32\cmd.exe`" /d /c call `"" + $normalChildScript +
            "`"`r`nexit /b 0`r`n"
        [IO.File]::WriteAllText($normalChildScript, $normalChildBody, [Text.Encoding]::ASCII)
        [IO.File]::WriteAllText($normalParentScript, $normalParentBody, [Text.Encoding]::ASCII)
        $normalArguments = (@('/d', '/c', 'call', $normalParentScript) |
            ForEach-Object { ConvertTo-CddsiFastLaneGitQuotedArgument $_ }) -join ' '
        $normal = [Cddsi.FastLane.BoundedProcessRunner]::Run(
            $commandProcessor, $normalArguments, $normalWorkingRoot,
            $cleanEnvironment, $null, 10000, 4096)
        $normal.ExitCode | Should -Be 0
        $normal.TimedOut | Should -BeFalse
        $normal.JobAssigned | Should -BeTrue
        $normal.ProcessTreeTerminated | Should -BeTrue
        [IO.File]::Exists($normalSentinel) | Should -BeFalse
        [IO.File]::Delete($normalChildScript)
        [IO.File]::Delete($normalParentScript)
        { [IO.Directory]::Delete($normalWorkingRoot, $false) } | Should -Not -Throw
        [IO.Directory]::Exists($normalWorkingRoot) | Should -BeFalse
    }

    It 'permanently rejects every direct bootstrap authority before writes or processes' {
        $fixture = New-VmBootstrapFixture
        $fakeContext = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-execution-context-v1'
            Kind = 'HostSandboxFake'; SyntheticOnly = $true; MutationAllowed = $false
        }
        foreach ($mode in @('TestSafe','DryRun','Live')) {
            $coreMessage = $null
            try {
                Invoke-CddsiTestDirectVmBootstrap -Mode $mode -AcknowledgeVmBootstrapLive `
                    -Package ([pscustomobject]@{ Forged = $true }) `
                    -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
                    -SshKeygenExecutable $fixture.KeygenPath -ExpectedSshKeygenSha256 ('0' * 64)
            }
            catch { $coreMessage = $_.Exception.Message }
            $coreMessage | Should -BeExactly 'VM_BOOTSTRAP_CORE_DIRECT_INVOCATION_FORBIDDEN'

            $phaseOneArguments = @{} + $fixture.PackageArguments
            $phaseOneArguments.BootstrapExecutionContext = $fakeContext
            $phaseOneArguments.ProductRoot = $fixture.ProductRoot
            $phaseOneArguments.PackageStagingRoot = $fixture.PackageStagingRoot
            $phaseOneArguments.CredentialRoot = $fixture.CredentialRoot
            $phaseOneArguments.ExpectedAutomationTargetCurrentTaskToken = 'CURRENT_TASK'
            $phaseOneMessage = $null
            try { Invoke-CddsiTestDirectVmBootstrapOnboarding -Mode $mode @phaseOneArguments }
            catch { $phaseOneMessage = $_.Exception.Message }
            $phaseOneMessage | Should -BeExactly 'VM_BOOTSTRAP_PHASE1_DIRECT_INVOCATION_FORBIDDEN'
        }

        $handoffMessage = $null
        try { New-CddsiTestDirectVmBootstrapHandoff }
        catch { $handoffMessage = $_.Exception.Message }
        $handoffMessage | Should -BeExactly 'VM_BOOTSTRAP_HANDOFF_DIRECT_INVOCATION_FORBIDDEN'

        $directHelperCalls = @(
            { Set-CddsiTestDirectVmBootstrapProtectedAcl -Path $fixture.Root },
            { Invoke-CddsiTestDirectVmBootstrapKeygenProcess -Executable $fixture.KeygenPath -PrivateKeyPath (Join-Path $fixture.Root 'key') -ProfileId 'vm.host-to-vm.read' },
            { Remove-CddsiTestDirectVmBootstrapOwnedRoot -CredentialRoot $fixture.CredentialRoot -RunId ([guid]::Empty.ToString()) },
            { Remove-CddsiTestDirectVmBootstrapOwnedPackageRoot -StagingRoot $fixture.PackageStagingRoot -RunId ([guid]::Empty.ToString()) },
            { Expand-CddsiTestDirectVmBootstrapPackage -Package ([pscustomobject]@{}) -StagingRoot $fixture.PackageStagingRoot -ProductRoot $fixture.ProductRoot -CredentialRoot $fixture.CredentialRoot },
            { New-CddsiTestDirectVmBootstrapOnboardingFailureResult -Mode TestSafe -FailureException ([InvalidOperationException]::new('synthetic')) -Staging $null }
        )
        foreach ($call in $directHelperCalls) {
            $message = $null
            try { & $call } catch { $message = $_.Exception.Message }
            $message | Should -Match '^VM_BOOTSTRAP_(MUTATION_HELPER|FAILURE_HANDLER)_DIRECT_INVOCATION_FORBIDDEN$'
        }
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeFalse
        [IO.Directory]::Exists($fixture.PackageStagingRoot) | Should -BeFalse
    }

    It 'validates the immutable package and the complete phase2 TestSafe and DryRun matrix' {
        $fixture = New-VmBootstrapFixture
        $packageArguments = $fixture.PackageArguments
        $package = Test-CddsiFastLaneVmOnboardingPackage @packageArguments
        $package.IsValid | Should -BeTrue
        (Test-CddsiExactPropertySet -InputObject $package -Expected @(
            'SchemaVersion', 'ContractVersion', 'Status', 'IsValid', 'EvidenceClass',
            'ZipSha256', 'ZipLengthBytes', 'ManifestSha256', 'ManifestLengthBytes',
            'ManifestBindingToken', 'InventorySha256', 'InventoryLengthBytes',
            'InventoryBindingToken', 'BundleContentDigestSha256', 'ProductCommitSha',
            'ProductTreeSha', 'VmAutomationId', 'VmAutomationStatus', 'Tools', 'ToolCount',
            'SourceBindings', 'RepositoryFacts', 'ProtectionFacts', 'CredentialProfiles',
            'AutomationContract', 'InventoryEntries', 'InternalBoundZipBytes', 'ArchiveReadOnly',
            'CredentialStatus', 'RuntimeProtectionAssertionStatus', 'NetworkRequestCount',
            'GitInvocationCount', 'ProductLiveInvocationCount', 'ProductWriteCount'
        )) | Should -BeTrue
        $package.ToolCount | Should -Be 5
        $package.AutomationContract.ReconcileMode | Should -BeExactly 'CREATE_OR_UPDATE_EXACTLY_ONE'
        $package.AutomationContract.TargetTaskToken | Should -BeExactly 'CURRENT_TASK'
        $package.SourceBindings.PolicySha256 | Should -Match '^[a-f0-9]{64}$'
        (Test-CddsiExactPropertySet -InputObject $package.RepositoryFacts `
            -Expected @('Product', 'HostToVm', 'VmToHost')) | Should -BeTrue
        foreach ($role in @('Product', 'HostToVm', 'VmToHost')) {
            $expectedProperties = @(
                'RepositoryIdentity', 'RepositoryNumericId', 'RepositoryNodeId',
                'Visibility', 'Ref', 'IntendedAccess'
            )
            if ($role -cne 'Product') { $expectedProperties += 'GenesisCommitSha' }
            (Test-CddsiExactPropertySet -InputObject $package.RepositoryFacts.$role `
                -Expected $expectedProperties) | Should -BeTrue
            ($package.RepositoryFacts.$role.RepositoryNumericId -is [long]) | Should -BeTrue
            $package.RepositoryFacts.$role.Visibility | Should -BeExactly 'PUBLIC'
        }
        $package.RepositoryFacts.Product.RepositoryIdentity | Should -BeExactly 'github.com/synthetic/product'
        $package.RepositoryFacts.Product.Ref | Should -BeExactly 'refs/heads/codex/repair/bootstrap-fixture'
        $package.RepositoryFacts.Product.IntendedAccess | Should -BeExactly 'READ_ONLY_EXACT_COMMIT'
        $package.RepositoryFacts.HostToVm.RepositoryIdentity | Should -BeExactly 'github.com/synthetic/host-to-vm'
        $package.RepositoryFacts.HostToVm.GenesisCommitSha | Should -BeExactly ('3' * 40)
        $package.RepositoryFacts.HostToVm.IntendedAccess | Should -BeExactly 'READ_ONLY'
        $package.RepositoryFacts.VmToHost.RepositoryIdentity | Should -BeExactly 'github.com/synthetic/vm-to-host'
        $package.RepositoryFacts.VmToHost.GenesisCommitSha | Should -BeExactly ('4' * 40)
        $package.RepositoryFacts.VmToHost.IntendedAccess | Should -BeExactly 'APPEND_ONLY'
        (Test-CddsiExactPropertySet -InputObject $package.ProtectionFacts -Expected @(
            'RepositoryVisibility', 'PolicySha256', 'HostProtectionFactsAreSenderAuthority',
            'RemoteAuthorizationStatus', 'RuntimeProtectionAssertionStatus'
        )) | Should -BeTrue
        $package.ProtectionFacts.RepositoryVisibility | Should -BeExactly 'PUBLIC'
        $package.ProtectionFacts.PolicySha256 | Should -BeExactly $package.SourceBindings.PolicySha256
        ($package.ProtectionFacts.HostProtectionFactsAreSenderAuthority -is [bool]) | Should -BeTrue
        $package.ProtectionFacts.HostProtectionFactsAreSenderAuthority | Should -BeFalse
        $package.ProtectionFacts.RemoteAuthorizationStatus | Should -BeExactly 'UNPROVISIONED'
        $package.ProtectionFacts.RuntimeProtectionAssertionStatus | Should -BeExactly 'UNPROVISIONED'
        (New-CddsiFastLaneVmBootstrapPlan -Package $package -CredentialRoot $fixture.CredentialRoot `
            -ProductRoot $fixture.ProductRoot).Mode | Should -BeExactly 'TestSafe'

        $bootstrapExecutionContext = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-execution-context-v1'
            Kind = 'HostSandboxFake'; SyntheticOnly = $true; MutationAllowed = $false
            SandboxRoot = $fixture.Root
            SandboxRootBindingToken = Get-CddsiFastLaneCanonicalPathSha256 $fixture.Root
        }
        $phaseTwoPrompt = "synthetic `"quote`" slash\ back`b tab`t line`nform`freturn`r 你好 😀"
        $tomlFixture = New-VmAutomationTomlFixture -Fixture $fixture -Prompt $phaseTwoPrompt
        $phaseTwoArguments = @{} + $fixture.PackageArguments
        $phaseTwoArguments.BootstrapExecutionContext = $bootstrapExecutionContext
        $phaseTwoArguments.LocalApplicationDataRoot = $tomlFixture.LocalApplicationDataRoot
        $phaseTwoArguments.CodexHome = $tomlFixture.CodexHome
        $phaseTwoArguments.ExpectedAutomationTargetCurrentTaskToken = 'CURRENT_TASK'
        $currentThreadId = '019f7000-1234-7abc-8def-0123456789ab'
        $differentValidThreadId = '019f7000-1234-7abc-8def-0123456789ac'
        (Test-CddsiFastLaneVmAutomationCurrentTaskBinding `
            -ObservedTargetThreadId $currentThreadId -ExpectedCurrentThreadId $currentThreadId) |
            Should -BeTrue
        (Test-CddsiFastLaneVmAutomationCurrentTaskBinding `
            -ObservedTargetThreadId $differentValidThreadId -ExpectedCurrentThreadId $currentThreadId) |
            Should -BeFalse

        $phaseTwoBoundPaths = @(
            $phaseTwoArguments.ZipPath,
            $phaseTwoArguments.ProgramFilesRoot,
            $phaseTwoArguments.SystemRoot,
            $phaseTwoArguments.LocalApplicationDataRoot,
            $phaseTwoArguments.CodexHome
        )
        (Test-CddsiFastLaneVmBootstrapExecutionContext `
            -Context $bootstrapExecutionContext -BoundPaths $phaseTwoBoundPaths) |
            Should -BeTrue
        $forgedBindingContext = $bootstrapExecutionContext.PSObject.Copy()
        $forgedBindingContext.SandboxRootBindingToken = '0' * 64
        (Test-CddsiFastLaneVmBootstrapExecutionContext `
            -Context $forgedBindingContext -BoundPaths $phaseTwoBoundPaths) |
            Should -BeFalse

        $foreignSandboxRoot = Join-Path ([IO.Path]::GetTempPath()) `
            ('cddsi-test-' + [guid]::NewGuid().ToString('N'))
        [void]$script:FixtureRoots.Add($foreignSandboxRoot)
        try {
            [void][IO.Directory]::CreateDirectory($foreignSandboxRoot)
            $foreignSandboxOwner = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-fast-lane-local-transport-owner-v1'
                Owner = 'CDDsiFastLaneGitOutboxTests'
                SyntheticOnly = $true
            }
            [IO.File]::WriteAllText(
                (Join-Path $foreignSandboxRoot '.cddsi-owner.json'),
                ((ConvertTo-CddsiVmTestRelayCanonicalJson $foreignSandboxOwner) + "`n"),
                (New-Object Text.UTF8Encoding($false)))
            $foreignTomlFixture = New-VmAutomationTomlFixture `
                -Fixture ([pscustomobject]@{ Root = $foreignSandboxRoot }) `
                -Prompt 'foreign synthetic phase2 prompt'
            $foreignZipPath = Join-Path $foreignSandboxRoot 'foreign-valid-onboarding.zip'
            [IO.File]::WriteAllBytes(
                $foreignZipPath,
                [IO.File]::ReadAllBytes($phaseTwoArguments.ZipPath))
            foreach ($outsidePath in @(
                @{ Name = 'CodexHome'; Value = $foreignTomlFixture.CodexHome },
                @{ Name = 'LocalApplicationDataRoot'; Value = $foreignTomlFixture.LocalApplicationDataRoot },
                @{ Name = 'ZipPath'; Value = $foreignZipPath }
            )) {
                $outsideArguments = @{} + $phaseTwoArguments
                $outsideArguments[$outsidePath.Name] = $outsidePath.Value
                (Test-CddsiFastLaneVmBootstrapExecutionContext `
                    -Context $bootstrapExecutionContext -BoundPaths @(
                        $outsideArguments.ZipPath,
                        $outsideArguments.ProgramFilesRoot,
                        $outsideArguments.SystemRoot,
                        $outsideArguments.LocalApplicationDataRoot,
                        $outsideArguments.CodexHome
                    )) | Should -BeFalse
                $blockedOutside = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
                    -Mode TestSafe @outsideArguments
                Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blockedOutside
                $blockedOutside.PackageRevalidated | Should -BeFalse
            }
        } finally {
            if ([IO.Directory]::Exists($foreignSandboxRoot)) {
                Remove-CddsiGitOutboxFixtureRootSafely -Root $foreignSandboxRoot
            }
            [void]$script:FixtureRoots.Remove($foreignSandboxRoot)
        }
        $unrelatedAutomationDirectory = Join-Path `
            (Split-Path $tomlFixture.AutomationDirectory -Parent) 'unrelated-valid-automation'
        [void][IO.Directory]::CreateDirectory($unrelatedAutomationDirectory)
        $unrelatedAutomationToml = @(
            'version = 1'
            'id = "unrelated-valid-automation"'
            'kind = "cron"'
            'name = "Unrelated valid automation"'
            'prompt = "unrelated"'
            'status = "PAUSED"'
            'rrule = "FREQ=HOURLY;INTERVAL=2"'
            'model = "gpt-5.6-sol"'
            'reasoning_effort = "high"'
            'execution_environment = "local"'
            'target = { type = "project", project_id = "local-0123456789abcdef0123456789abcdef" }'
            'cwds = ["D:\\synthetic"]'
            'created_at = 200'
            'updated_at = 201'
        ) -join "`n"
        [IO.File]::WriteAllText(
            (Join-Path $unrelatedAutomationDirectory 'automation.toml'),
            ($unrelatedAutomationToml + "`n"),
            (New-Object Text.UTF8Encoding($false)))
        $beforeEntries = @([IO.Directory]::EnumerateFileSystemEntries(
                $tomlFixture.LocalApplicationDataRoot, '*', [IO.SearchOption]::TopDirectoryOnly))
        $phaseTwoPlans = @{}
        foreach ($mode in @('TestSafe', 'DryRun')) {
            $orchestrated = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding -Mode $mode @phaseTwoArguments
            $phaseTwoPlans[$mode] = $orchestrated
            $orchestrated.Status | Should -BeExactly 'PLANNED'
            $orchestrated.Mode | Should -BeExactly $mode
            $orchestrated.Changed | Should -BeFalse
            $orchestrated.AutomationTomlSchemaVerified | Should -BeTrue
            $orchestrated.AutomationTargetCurrentTaskVerified | Should -BeFalse
            $orchestrated.AutomationPromptBindingDeferred | Should -BeTrue
            $orchestrated.AutomationMatchCount | Should -Be 1
            $orchestrated.AutomationTomlSha256 | Should -BeExactly $tomlFixture.Sha256
            $orchestrated.AutomationTomlLengthBytes | Should -Be $tomlFixture.LengthBytes
            $orchestrated.AutomationPromptReadbackSha256 | Should -BeExactly `
                (Get-CddsiSupplyChainTextBindingToken -Text $tomlFixture.Prompt)
            $orchestrated.DirectoryCreateCount | Should -Be 0
            $orchestrated.FileWriteCount | Should -Be 0
            $orchestrated.AclMutationCount | Should -Be 0
            $orchestrated.ProcessInvocationCount | Should -Be 0
            $orchestrated.DirectoryDeleteCount | Should -Be 0
            $orchestrated.CleanupRequired | Should -BeFalse
            $orchestrated.CleanupSucceeded | Should -BeTrue
            $orchestrated.NetworkRequestCount | Should -Be 0
            $orchestrated.GitInvocationCount | Should -Be 0
            $orchestrated.ProductLiveInvocationCount | Should -Be 0
            $orchestrated.ProductWriteCount | Should -Be 0
            Assert-VmAutomationTomlLeaseReleased -Path $tomlFixture.TomlPath
        }
        @([IO.Directory]::EnumerateFileSystemEntries(
                $tomlFixture.LocalApplicationDataRoot, '*', [IO.SearchOption]::TopDirectoryOnly)).Count |
            Should -Be $beforeEntries.Count
        $vmDeviceWithoutAck = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-execution-context-v1'
            Kind = 'VmDevice'; SyntheticOnly = $false; MutationAllowed = $true
            SandboxRoot = ''; SandboxRootBindingToken = '0' * 64
        }
        foreach ($liveNegativeCase in @(
            @{ Context = $bootstrapExecutionContext; Acknowledge = $false },
            @{ Context = $bootstrapExecutionContext; Acknowledge = $true },
            @{ Context = $vmDeviceWithoutAck; Acknowledge = $false }
        )) {
            $liveNegativeArguments = @{} + $phaseTwoArguments
            $liveNegativeArguments.BootstrapExecutionContext = $liveNegativeCase.Context
            if ($liveNegativeCase.Acknowledge) {
                $liveNegativeArguments.AcknowledgeVmBootstrapLive = $true
            }
            $blockedLive = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
                -Mode Live @liveNegativeArguments
            Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blockedLive
            $blockedLive.BlockerCode | Should -BeExactly 'LIVE_ACK_REQUIRED'
            $blockedLive.PackageRevalidated | Should -BeFalse
        }
        foreach ($unsafePath in @('../escape', 'payload/file:ads', 'payload/CON.txt',
            '/absolute', 'payload\backslash', 'payload/../escape')) {
            Test-CddsiFastLaneVmBootstrapSafeRelativePath $unsafePath | Should -BeFalse
        }

        $badArguments = @{} + $fixture.PackageArguments
        $badArguments.ExpectedZipSha256 = '0' * 64
        { Test-CddsiFastLaneVmOnboardingPackage @badArguments } | Should -Throw '*VM_BOOTSTRAP_ZIP_HASH_MISMATCH*'
        $originalZipBytes = [IO.File]::ReadAllBytes($fixture.PackageArguments.ZipPath)
        $localMethodBytes = [byte[]]$originalZipBytes.Clone()
        $localMethodBytes[8] = 8
        $localMethodPath = Join-Path $fixture.Root 'local-method-drift.zip'
        [IO.File]::WriteAllBytes($localMethodPath, $localMethodBytes)
        $localMethodArguments = @{} + $fixture.PackageArguments
        $localMethodArguments.ZipPath = $localMethodPath
        $localMethodArguments.ExpectedZipSha256 = Get-CddsiFastLaneVmBootstrapBytesSha256 $localMethodBytes
        { Test-CddsiFastLaneVmOnboardingPackage @localMethodArguments } |
            Should -Throw '*VM_BOOTSTRAP_ZIP_STORE_HEADERS_INVALID*'
        $centralOffset = -1
        for ($offset = 0; $offset -le ($originalZipBytes.Length - 4); $offset++) {
            if ($originalZipBytes[$offset] -eq 0x50 -and $originalZipBytes[$offset + 1] -eq 0x4b -and
                $originalZipBytes[$offset + 2] -eq 0x01 -and $originalZipBytes[$offset + 3] -eq 0x02) {
                $centralOffset = $offset; break
            }
        }
        $centralOffset | Should -BeGreaterThan 0
        $centralMethodBytes = [byte[]]$originalZipBytes.Clone()
        $centralMethodBytes[$centralOffset + 10] = 8
        $centralMethodPath = Join-Path $fixture.Root 'central-method-drift.zip'
        [IO.File]::WriteAllBytes($centralMethodPath, $centralMethodBytes)
        $centralMethodArguments = @{} + $fixture.PackageArguments
        $centralMethodArguments.ZipPath = $centralMethodPath
        $centralMethodArguments.ExpectedZipSha256 = Get-CddsiFastLaneVmBootstrapBytesSha256 $centralMethodBytes
        { Test-CddsiFastLaneVmOnboardingPackage @centralMethodArguments } |
            Should -Throw '*VM_BOOTSTRAP_ZIP_STORE_HEADERS_INVALID*'
        $badOnboardingArguments = @{} + $phaseTwoArguments
        $badOnboardingArguments.ExpectedZipSha256 = '0' * 64
        $blocked = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding -Mode TestSafe @badOnboardingArguments
        Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blocked
        $blocked.BlockerCode | Should -BeExactly 'PACKAGE_BINDING_INVALID'
        $blocked.PrivateKeyIncluded | Should -BeFalse
        $blocked.RealPathIncluded | Should -BeFalse
        $blocked.SidIncluded | Should -BeFalse
        $blockedJson = ConvertTo-CddsiVmTestRelayCanonicalJson $blocked
        $blockedJson | Should -Not -Match ([regex]::Escape($fixture.Root))

        $phaseTwoCommand = Get-Command Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding
        $expectedPhaseTwoParameters = @(
            'Mode','BootstrapExecutionContext','ZipPath','ExpectedZipSha256','ExpectedZipLengthBytes',
            'ExpectedManifestSha256','ExpectedManifestLengthBytes','ExpectedManifestBindingToken',
            'ExpectedInventorySha256','ExpectedInventoryLengthBytes','ExpectedInventoryBindingToken',
            'ExpectedBundleContentDigestSha256','ExpectedProductCommitSha','ExpectedProductTreeSha',
            'ProgramFilesRoot','SystemRoot','LocalApplicationDataRoot','CodexHome',
            'ExpectedAutomationTargetCurrentTaskToken','AcknowledgeVmBootstrapLive'
        )
        $commonParameterNames = @(
            'Verbose','Debug','ErrorAction','WarningAction','InformationAction','ProgressAction',
            'ErrorVariable','WarningVariable','InformationVariable','OutVariable','OutBuffer',
            'PipelineVariable'
        )
        $actualPhaseTwoParameters = @($phaseTwoCommand.Parameters.Keys | Where-Object {
                $commonParameterNames -cnotcontains $_
            } | Sort-Object)
        ($actualPhaseTwoParameters -join "`n") | Should -BeExactly `
            (@($expectedPhaseTwoParameters | Sort-Object) -join "`n")
        foreach ($phaseTwoParameterName in $expectedPhaseTwoParameters) {
            @($phaseTwoCommand.Parameters[$phaseTwoParameterName].Aliases).Count | Should -Be 0
            $parameterAttributes = @(
                $phaseTwoCommand.Parameters[$phaseTwoParameterName].Attributes | Where-Object {
                    $_ -is [Management.Automation.ParameterAttribute]
                })
            $expectedMandatory = @('Mode', 'AcknowledgeVmBootstrapLive') -cnotcontains `
                $phaseTwoParameterName
            @($parameterAttributes | Where-Object Mandatory).Count | Should -Be `
                $(if ($expectedMandatory) { 1 } else { 0 })
        }
        $expectedPhaseTwoParameterTypes = [ordered]@{
            Mode = [string]; BootstrapExecutionContext = [object]; ZipPath = [string]
            ExpectedZipSha256 = [string]; ExpectedZipLengthBytes = [long]
            ExpectedManifestSha256 = [string]; ExpectedManifestLengthBytes = [long]
            ExpectedManifestBindingToken = [string]; ExpectedInventorySha256 = [string]
            ExpectedInventoryLengthBytes = [long]; ExpectedInventoryBindingToken = [string]
            ExpectedBundleContentDigestSha256 = [string]; ExpectedProductCommitSha = [string]
            ExpectedProductTreeSha = [string]; ProgramFilesRoot = [string]; SystemRoot = [string]
            LocalApplicationDataRoot = [string]; CodexHome = [string]
            ExpectedAutomationTargetCurrentTaskToken = [string]
            AcknowledgeVmBootstrapLive = [switch]
        }
        foreach ($phaseTwoType in $expectedPhaseTwoParameterTypes.GetEnumerator()) {
            $phaseTwoCommand.Parameters[$phaseTwoType.Key].ParameterType |
                Should -Be $phaseTwoType.Value
        }
        $modeValidateSet = @($phaseTwoCommand.Parameters.Mode.Attributes | Where-Object {
                $_ -is [Management.Automation.ValidateSetAttribute]
            })
        $modeValidateSet.Count | Should -Be 1
        (@($modeValidateSet[0].ValidValues) -join '|') |
            Should -BeExactly 'TestSafe|DryRun|Live'
        $phaseTwoRuntimeAst = $phaseTwoCommand.ScriptBlock.Ast
        $modeParameterAst = @($phaseTwoRuntimeAst.Body.ParamBlock.Parameters | Where-Object {
                $_.Name.VariablePath.UserPath -ceq 'Mode'
            })
        $modeParameterAst.Count | Should -Be 1
        $modeParameterAst[0].DefaultValue.Extent.Text | Should -BeExactly "'TestSafe'"
        $phaseOneClosureAst = @($phaseTwoRuntimeAst.Body.FindAll({
                    param($node)
                    $node -is [Management.Automation.Language.FunctionDefinitionAst] -and
                        $node.Name -ceq 'Invoke-CddsiFastLaneVmBootstrapOnboardingClosure'
                }, $true))
        $phaseOneClosureAst.Count | Should -Be 1
        $phaseOneInternalParameters = @(
            $phaseOneClosureAst[0].Body.ParamBlock.Parameters.Name.VariablePath.UserPath)
        foreach ($internalParameter in @(
            'InternalStagingOwnership','InternalCredentialOwnership','InternalCompensationContext'
        )) { $phaseOneInternalParameters | Should -Contain $internalParameter }
        $phaseTwoRuntimeAst.Extent.Text | Should -Match `
            '(?s)InternalCompensationContext\s*=\s*\$compensationContext.*?Invoke-CddsiFastLaneVmBootstrapOnboardingClosure'
        $phaseTwoRuntimeAst.Extent.Text | Should -Match `
            '(?s)\$phaseOne\s*=\s*Invoke-CddsiFastLaneVmBootstrapOnboardingClosure.*?\$automationReadbackMatch\s*=\s*Get-CddsiFastLaneVmAutomationTomlReadback.*?\$handoff\s*=\s*New-CddsiFastLaneVmBootstrapHandoffClosure'
        $phaseTwoRuntimeAst.Extent.Text | Should -Match `
            '(?s)\$automationMatch\.MatchCount\s*-eq\s*0.*?Get-CddsiFastLaneVmAutomationTomlMatch.*?VM_BOOTSTRAP_AUTOMATION_STATE_CHANGED_DURING_PHASE1'
        $phaseTwoRuntimeAst.Extent.Text | Should -Match `
            '(?s)\$automationReadbackMatch\.Toml\.Prompt\s*-cne\s*\[string\]\$phaseOne\.AutomationPrompt.*?New-CddsiFastLaneVmBootstrapHandoffClosure.*?-AutomationToml\s+\$automationReadbackMatch\.Toml'
        $phaseTwoRuntimeAst.Extent.Text | Should -Match `
            '(?s)finally\s*\{\s*if\s*\(\$null\s*-ne\s*\$automationReadbackStream\).*?Dispose\(\).*?if\s*\(\$null\s*-ne\s*\$automationStream\).*?Dispose\(\)'
        foreach ($forbiddenParameter in @(
            'BootstrapResult','AutomationPrompt','AutomationObservation','ObservationJsonBase64',
            'ProductRoot','PackageStagingRoot','CredentialRoot'
        )) { $phaseTwoCommand.Parameters.ContainsKey($forbiddenParameter) | Should -BeFalse }

        $validToml = $tomlFixture.Text + "`n"
        $beforeLocalEntries = @([IO.Directory]::EnumerateFileSystemEntries(
                $tomlFixture.LocalApplicationDataRoot, '*', [IO.SearchOption]::TopDirectoryOnly))

        $firstPlan = $phaseTwoPlans['TestSafe']
        $secondPlan = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding -Mode TestSafe @phaseTwoArguments
        $firstPlan.Status | Should -BeExactly 'PLANNED'
        $firstPlan.AutomationMatchCount | Should -Be 1
        $firstPlan.AutomationTomlSha256 | Should -BeExactly $tomlFixture.Sha256
        $secondPlan.AutomationTomlSha256 | Should -BeExactly $tomlFixture.Sha256
        $firstPlan.AutomationTomlLengthBytes | Should -Be $tomlFixture.LengthBytes
        $secondPlan.AutomationTomlLengthBytes | Should -Be $tomlFixture.LengthBytes
        $firstPlan.AutomationPromptReadbackSha256 |
            Should -BeExactly (Get-CddsiSupplyChainTextBindingToken -Text $tomlFixture.Prompt)
        $secondPlan.AutomationPromptReadbackSha256 |
            Should -BeExactly $firstPlan.AutomationPromptReadbackSha256
        $tomlFixture.Prompt | Should -BeExactly $phaseTwoPrompt
        Assert-VmAutomationTomlLeaseReleased -Path $tomlFixture.TomlPath

        $identityHidingDirectory = Join-Path `
            (Split-Path $tomlFixture.AutomationDirectory -Parent) 'identity-hiding-automation'
        [void][IO.Directory]::CreateDirectory($identityHidingDirectory)
        $identityHidingPath = Join-Path $identityHidingDirectory 'automation.toml'
        $unrelatedCanonicalToml = $unrelatedAutomationToml + "`n"
        $identityHidingTomlValues = @(
            ($unrelatedCanonicalToml -replace '(?m)^id = ', '"id" = '),
            ($unrelatedCanonicalToml -replace '(?m)^name = ', '"name" = '),
            ($unrelatedCanonicalToml -replace '(?m)^id = ', '"\u0069d" = '),
            ($unrelatedCanonicalToml -replace '(?m)^name = ', '"\u006eame" = '),
            ($unrelatedCanonicalToml -replace '(?m)^id = ', "'id' = "),
            ($unrelatedCanonicalToml -replace '(?m)^name = ', "'name' = "),
            ($unrelatedCanonicalToml -replace '(?m)^id = "[^"]+"$',
                'id = "cddsi\u002dfast-lane-vmtester-minute-poll"'),
            ($unrelatedCanonicalToml -replace '(?m)^name = "[^"]+"$',
                'name = "CDDsi Fast Lane VmTester minute\u0020poll"')
        )
        try {
        foreach ($identityHidingToml in $identityHidingTomlValues) {
                [IO.File]::WriteAllText(
                    $identityHidingPath,
                    $identityHidingToml,
                    (New-Object Text.UTF8Encoding($false)))
                { Invoke-VmAutomationTomlMatchForTest `
                        -AutomationRoot (Split-Path $tomlFixture.AutomationDirectory -Parent) } |
                    Should -Throw '*VM_BOOTSTRAP_AUTOMATION_*'
            }
        }
        finally {
            if ([IO.File]::Exists($identityHidingPath)) { [IO.File]::Delete($identityHidingPath) }
            [IO.Directory]::Delete($identityHidingDirectory, $false)
        }

        $unrelatedExactTargetToml = $validToml.
            Replace(
                'id = "cddsi-fast-lane-vmtester-minute-poll"',
                'id = "fully-unrelated-valid-id"').
            Replace(
                'name = "CDDsi Fast Lane VmTester minute poll"',
                'name = "Fully unrelated valid name"')
        try {
            [IO.File]::WriteAllText(
                $tomlFixture.TomlPath,
                $unrelatedExactTargetToml,
                (New-Object Text.UTF8Encoding($false)))
            { Invoke-VmAutomationTomlMatchForTest `
                    -AutomationRoot (Split-Path $tomlFixture.AutomationDirectory -Parent) } |
                Should -Throw '*VM_BOOTSTRAP_AUTOMATION_*'
        }
        finally {
            [IO.File]::WriteAllText(
                $tomlFixture.TomlPath,
                $validToml,
                (New-Object Text.UTF8Encoding($false)))
        }

        $invalidTomlValues = @(
            ($validToml + "extra = 1`n"),
            ($validToml -replace '(?m)^updated_at = 101\r?\n', ''),
            ($validToml + 'id = "cddsi-fast-lane-vmtester-minute-poll"' + "`n"),
            ($validToml -replace 'status = "PAUSED"', 'status = "ACTIVE"'),
            ($validToml -replace 'rrule = "FREQ=MINUTELY;INTERVAL=1"', 'rrule = "FREQ=HOURLY"'),
            ($validToml -replace 'target_thread_id = "[^"]+"', 'target_thread_id = "wrong-task"'),
            ($validToml -replace 'id = "cddsi-fast-lane-vmtester-minute-poll"', 'id = "forged-id"'),
            ($validToml -replace 'name = "CDDsi Fast Lane VmTester minute poll"', 'name = "forged-name"'),
            ($validToml -replace '(?m)^prompt = .+$', 'prompt = "bad\xescape"'),
            ($validToml -replace '(?m)^version = 1$', 'version = 2'),
            ($validToml -replace '(?m)^kind = "heartbeat"$', 'kind = "cron"'),
            ($validToml -replace '(?m)^created_at = 100$', 'created_at = 102'),
            ($validToml -replace '(?m)^updated_at = 101$', 'updated_at = -1'),
            ($validToml -replace '(?m)^updated_at = 101$', 'updated_at = 9223372036854775808')
        )
        $invalidTomlIndex = 0
        foreach ($invalidToml in $invalidTomlValues) {
            [IO.File]::WriteAllText($tomlFixture.TomlPath, $invalidToml, (New-Object Text.UTF8Encoding($false)))
            { Invoke-VmAutomationTomlMatchForTest `
                    -AutomationRoot (Split-Path $tomlFixture.AutomationDirectory -Parent) } |
                Should -Throw '*VM_BOOTSTRAP_AUTOMATION_*'
            if ($invalidTomlIndex -eq 0) {
                $blocked = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding -Mode TestSafe @phaseTwoArguments
                Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blocked
                $blocked.PackageRevalidated | Should -BeFalse
            }
            $invalidTomlIndex++
        }

        $validBytes = (New-Object Text.UTF8Encoding($false)).GetBytes($validToml)
        $bomBytes = [byte[]]@([byte]0xef,[byte]0xbb,[byte]0xbf) + $validBytes
        [IO.File]::WriteAllBytes($tomlFixture.TomlPath, $bomBytes)
        { Invoke-VmAutomationTomlMatchForTest `
                -AutomationRoot (Split-Path $tomlFixture.AutomationDirectory -Parent) } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_TOML_BOM_FORBIDDEN*'
        Assert-VmAutomationTomlLeaseReleased -Path $tomlFixture.TomlPath

        $nulBytes = [byte[]]$validBytes.Clone()
        $nulBytes[0] = 0
        $invalidUtf8Bytes = [byte[]]$validBytes.Clone()
        $invalidUtf8Bytes[1] = 0xc3
        $invalidUtf8Bytes[2] = 0x28
        $bareCrBytes = [byte[]]$validBytes.Clone()
        $firstLfIndex = [Array]::IndexOf($bareCrBytes, [byte]10)
        $firstLfIndex | Should -BeGreaterThan 0
        $bareCrBytes[$firstLfIndex] = 13
        $oversizeBytes = New-Object byte[] 262145
        $invalidTomlByteCases = New-Object 'Collections.Generic.List[byte[]]'
        $invalidTomlByteCases.Add($invalidUtf8Bytes)
        $invalidTomlByteCases.Add($nulBytes)
        $invalidTomlByteCases.Add($bareCrBytes)
        $invalidTomlByteCases.Add($oversizeBytes)
        foreach ($invalidTomlBytes in $invalidTomlByteCases) {
            [IO.File]::WriteAllBytes($tomlFixture.TomlPath, $invalidTomlBytes)
            { Invoke-VmAutomationTomlMatchForTest `
                    -AutomationRoot (Split-Path $tomlFixture.AutomationDirectory -Parent) } |
                Should -Throw
            Assert-VmAutomationTomlLeaseReleased -Path $tomlFixture.TomlPath
        }
        [IO.File]::WriteAllBytes($tomlFixture.TomlPath, $validBytes)

        $duplicateDirectory = Join-Path (Split-Path $tomlFixture.AutomationDirectory -Parent) 'duplicate-task'
        [void][IO.Directory]::CreateDirectory($duplicateDirectory)
        $duplicateToml = Join-Path $duplicateDirectory 'automation.toml'
        [IO.File]::WriteAllText($duplicateToml, $validToml, (New-Object Text.UTF8Encoding($false)))
        try {
            $blocked = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
                -Mode TestSafe @phaseTwoArguments
            Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blocked
        }
        finally { [IO.File]::Delete($duplicateToml); [IO.Directory]::Delete($duplicateDirectory, $false) }

        $exclusiveStream = [IO.File]::Open(
            $tomlFixture.TomlPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        try {
            $blocked = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
                -Mode TestSafe @phaseTwoArguments
            Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blocked
        }
        finally { $exclusiveStream.Dispose() }

        $forgedTargetArguments = @{} + $phaseTwoArguments
        $forgedTargetArguments.ExpectedAutomationTargetCurrentTaskToken = 'FORGED_TASK'
        $blocked = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
            -Mode TestSafe @forgedTargetArguments
        Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blocked
        foreach ($forgery in @(
            @{ Name = 'ProgramFilesRoot'; Value = 'relative-program-files' },
            @{ Name = 'SystemRoot'; Value = 'relative-system-root' },
            @{ Name = 'CodexHome'; Value = (Join-Path $fixture.Root 'missing-codex-home') }
        )) {
            $forgedArguments = @{} + $phaseTwoArguments
            $forgedArguments[$forgery.Name] = $forgery.Value
            (Test-CddsiFastLaneVmBootstrapExecutionContext `
                -Context $bootstrapExecutionContext -BoundPaths @(
                    $forgedArguments.ZipPath,
                    $forgedArguments.ProgramFilesRoot,
                    $forgedArguments.SystemRoot,
                    $forgedArguments.LocalApplicationDataRoot,
                    $forgedArguments.CodexHome
                )) | Should -BeFalse
            $blockedForgery = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
                -Mode TestSafe @forgedArguments
            Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blockedForgery
            $blockedForgery.PackageRevalidated | Should -BeFalse
        }
        $forgedContextArguments = @{} + $phaseTwoArguments
        $forgedContextArguments.BootstrapExecutionContext = [pscustomobject][ordered]@{
            SchemaVersion = 1; ContractVersion = 'cddsi-fast-lane-vm-bootstrap-execution-context-v1'
            Kind = 'HostSandboxFake'; SyntheticOnly = $true; MutationAllowed = $true
            SandboxRoot = $fixture.Root
            SandboxRootBindingToken = Get-CddsiFastLaneCanonicalPathSha256 $fixture.Root
        }
        $blocked = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
            -Mode TestSafe @forgedContextArguments
        Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blocked

        $junction = Join-Path $fixture.Root 'codex-home-junction'
        New-Item -ItemType Junction -Path $junction -Target $tomlFixture.CodexHome -ErrorAction Stop | Out-Null
        try {
            $junctionArguments = @{} + $phaseTwoArguments
            $junctionArguments.CodexHome = $junction
            (Test-CddsiFastLaneVmBootstrapExecutionContext `
                -Context $bootstrapExecutionContext -BoundPaths @(
                    $junctionArguments.ZipPath,
                    $junctionArguments.ProgramFilesRoot,
                    $junctionArguments.SystemRoot,
                    $junctionArguments.LocalApplicationDataRoot,
                    $junctionArguments.CodexHome
                )) | Should -BeFalse
            $blockedJunction = Invoke-CddsiFastLaneVmBootstrapHandoffOnboarding `
                -Mode TestSafe @junctionArguments
            Assert-VmBootstrapPhaseTwoBlockedWithoutSideEffects $blockedJunction
            $blockedJunction.PackageRevalidated | Should -BeFalse
        }
        finally { [IO.Directory]::Delete($junction, $false) }

        @([IO.Directory]::EnumerateFileSystemEntries(
                $tomlFixture.LocalApplicationDataRoot, '*', [IO.SearchOption]::TopDirectoryOnly)).Count |
            Should -Be $beforeLocalEntries.Count
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeFalse
        [IO.Directory]::Exists($fixture.PackageStagingRoot) | Should -BeFalse
    }

    It 'stages three distinct mocked keypairs with protected receipts and reuses the exact valid root idempotently' {
        $fixture = New-VmBootstrapFixture
        $packageArguments = $fixture.PackageArguments
        $package = Test-CddsiFastLaneVmOnboardingPackage @packageArguments
        Mock Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
            param($Executable, $PrivateKeyPath, $ProfileId, $Operation)
            $ordinal = [Array]::IndexOf($script:CddsiFastLaneVmBootstrapProfiles, $ProfileId) + 1
            $blob = [byte[]]@(0..63 | ForEach-Object { [byte](($_ + ($ordinal * 17)) % 256) })
            $publicPrefix = 'ssh-ed25519 ' + [Convert]::ToBase64String($blob)
            if ($Operation -ceq 'DerivePublic') {
                return [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; Truncated = $false; JobAssigned = $true
                    StandardOutput = $publicPrefix + "`n"
                }
            }
            [IO.File]::WriteAllText($PrivateKeyPath, ('synthetic-private-material-' + $ProfileId + ('x' * 64)), (New-Object Text.UTF8Encoding($false)))
            [IO.File]::WriteAllText(
                ($PrivateKeyPath + '.pub'),
                ($publicPrefix + ' cddsi:' + $ProfileId + "`n"),
                (New-Object Text.UTF8Encoding($false)))
            return [pscustomobject]@{
                ExitCode = 0; TimedOut = $false; Truncated = $false; JobAssigned = $true; StandardOutput = ''
            }
        }
        $first = Invoke-VmBootstrapFixtureCore -Package $package -CredentialRoot $fixture.CredentialRoot `
            -ProductRoot $fixture.ProductRoot -SshKeygenExecutable $fixture.KeygenPath `
            -ExpectedSshKeygenSha256 $fixture.KeygenSha256
        $first.Status | Should -BeExactly 'VM_BOOTSTRAP_LOCAL_STAGED'
        $first.CredentialStatus | Should -BeExactly 'KEYPAIR_STAGED'
        $first.VmCredentialReady | Should -BeFalse
        $first.ProfileCount | Should -Be 3
        $first.DirectoryCreateCount | Should -Be 1
        $first.FileWriteCount | Should -Be 11
        $first.AclMutationCount | Should -Be 12
        $first.ProcessInvocationCount | Should -Be 6
        @($first.Profiles.PublicKeyFingerprint | Select-Object -Unique).Count | Should -Be 3
        @($first.Profiles.ReceiptSha256 | Select-Object -Unique).Count | Should -Be 3
        Test-CddsiFastLaneVmBootstrapProtectedAcl -Path $fixture.CredentialRoot -PathKind Directory | Should -BeTrue
        foreach ($bootstrapCredential in $first.Profiles) {
            $bootstrapCredential.State | Should -BeExactly 'KEYPAIR_STAGED'
            $bootstrapCredential.VmCredentialReady | Should -BeFalse
            $bootstrapCredential.PublicKeyFingerprint | Should -Match '^SHA256:[A-Za-z0-9+/]+$'
            $bootstrapCredential.ReceiptSha256 | Should -Match '^[a-f0-9]{64}$'
            Test-CddsiFastLaneVmBootstrapProtectedAcl `
                -Path (Join-Path $fixture.CredentialRoot ($bootstrapCredential.ProfileId + '.receipt.json')) -PathKind File |
                Should -BeTrue
        }
        $serialized = ConvertTo-CddsiVmTestRelayCanonicalJson $first
        $serialized | Should -Not -Match ([regex]::Escape($fixture.CredentialRoot))
        $serialized | Should -Not -Match 'synthetic-private-material'
        $serialized | Should -Not -Match ([regex]::Escape([Security.Principal.WindowsIdentity]::GetCurrent().User.Value))

        $second = Invoke-VmBootstrapFixtureCore -Package $package -CredentialRoot $fixture.CredentialRoot `
            -ProductRoot $fixture.ProductRoot -SshKeygenExecutable $fixture.KeygenPath `
            -ExpectedSshKeygenSha256 $fixture.KeygenSha256
        $second.ReusedExisting | Should -BeTrue
        $second.Changed | Should -BeFalse
        $second.DirectoryCreateCount | Should -Be 0
        $second.FileWriteCount | Should -Be 0
        $second.AclMutationCount | Should -Be 0
        $second.ProcessInvocationCount | Should -Be 3
        Assert-MockCalled Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Times 9 -Exactly

        $inheritingCredentialSecurity = Get-VmBootstrapTestDirectorySecurity `
            -Path $fixture.CredentialRoot
        $inheritingCredentialSecurity.SetAccessRuleProtection($false, $true)
        Set-VmBootstrapTestDirectorySecurity -Path $fixture.CredentialRoot `
            -Security $inheritingCredentialSecurity
        Test-CddsiFastLaneVmBootstrapProtectedAcl `
            -Path $fixture.CredentialRoot -PathKind Directory | Should -BeFalse
        { Invoke-VmBootstrapFixtureCore -Package $package `
                -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
                -SshKeygenExecutable $fixture.KeygenPath `
                -ExpectedSshKeygenSha256 $fixture.KeygenSha256 } |
            Should -Throw '*VM_BOOTSTRAP_EXISTING_ROOT_INVALID*'
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeTrue
        Assert-MockCalled Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Times 9 -Exactly
        Set-CddsiFastLaneVmBootstrapProtectedAcl `
            -Path $fixture.CredentialRoot -PathKind Directory
        Test-CddsiFastLaneVmBootstrapProtectedAcl `
            -Path $fixture.CredentialRoot -PathKind Directory | Should -BeTrue

        $profileForAclDrift = $script:CddsiFastLaneVmBootstrapProfiles[0]
        $credentialFilePaths = @(
            (Join-Path $fixture.CredentialRoot '.cddsi-owner.json'),
            (Join-Path $fixture.CredentialRoot ($profileForAclDrift + '.key')),
            (Join-Path $fixture.CredentialRoot ($profileForAclDrift + '.key.pub')),
            (Join-Path $fixture.CredentialRoot ($profileForAclDrift + '.receipt.json'))
        )
        $everyoneSid = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
        foreach ($credentialFilePath in $credentialFilePaths) {
            $widenedFileSecurity = Get-VmBootstrapTestFileSecurity -Path $credentialFilePath
            $extraFileRule = New-Object Security.AccessControl.FileSystemAccessRule(
                $everyoneSid, [Security.AccessControl.FileSystemRights]::Read,
                [Security.AccessControl.AccessControlType]::Allow)
            [void]$widenedFileSecurity.AddAccessRule($extraFileRule)
            Set-VmBootstrapTestFileSecurity -Path $credentialFilePath -Security $widenedFileSecurity
            Test-CddsiFastLaneVmBootstrapProtectedAcl `
                -Path $credentialFilePath -PathKind File | Should -BeFalse
            { Invoke-VmBootstrapFixtureCore -Package $package `
                    -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
                    -SshKeygenExecutable $fixture.KeygenPath `
                    -ExpectedSshKeygenSha256 $fixture.KeygenSha256 } |
                Should -Throw '*VM_BOOTSTRAP_EXISTING_*'
            [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeTrue
            Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $credentialFilePath -PathKind File
            Test-CddsiFastLaneVmBootstrapProtectedAcl `
                -Path $credentialFilePath -PathKind File | Should -BeTrue
        }
        Assert-MockCalled Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Times 9 -Exactly

        Mock Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
            param($Executable, $PrivateKeyPath, $ProfileId, $Operation)
            $ordinal = [Array]::IndexOf($script:CddsiFastLaneVmBootstrapProfiles, $ProfileId) + 1
            $blob = [byte[]]@(0..63 | ForEach-Object { [byte](($_ + ($ordinal * 17)) % 256) })
            if ($Operation -ceq 'DerivePublic' -and
                $ProfileId -ceq $script:CddsiFastLaneVmBootstrapProfiles[1]) {
                return [pscustomobject]@{
                    ExitCode = 1; TimedOut = $false; Truncated = $false; JobAssigned = $true
                    StandardOutput = ''; StandardError = 'synthetic derive failure'
                }
            }
            return [pscustomobject]@{
                ExitCode = 0; TimedOut = $false; Truncated = $false; JobAssigned = $true
                StandardOutput = ('ssh-ed25519 ' + [Convert]::ToBase64String($blob) + "`n")
            }
        }
        $reuseFailure = $null
        try {
            [void](Invoke-VmBootstrapFixtureCore -Package $package `
                -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
                -SshKeygenExecutable $fixture.KeygenPath `
                -ExpectedSshKeygenSha256 $fixture.KeygenSha256)
        }
        catch { $reuseFailure = $_.Exception }
        $reuseFailure.Message | Should -Match 'VM_BOOTSTRAP_EXISTING_KEYPAIR_DERIVATION_FAILED'
        $reuseAccounting = Get-CddsiFastLaneVmBootstrapFailureAccounting $reuseFailure
        $reuseAccounting.DirectoryCreateCount | Should -Be 0
        $reuseAccounting.FileWriteCount | Should -Be 0
        $reuseAccounting.AclMutationCount | Should -Be 0
        $reuseAccounting.ProcessInvocationCount | Should -Be 2
        $reuseAccounting.DirectoryDeleteCount | Should -Be 0
        $reuseAccounting.CleanupRequired | Should -BeFalse
        $reuseAccounting.CleanupSucceeded | Should -BeTrue
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeTrue

        $prompt = New-CddsiFastLaneVmAutomationPrompt -Package $package -BootstrapResult $second
        foreach ($binding in @(
            $package.SourceBindings.PolicySha256, $package.SourceBindings.KnownHostsSha256,
            $package.SourceBindings.RunnerSha256, $package.SourceBindings.VmPollPromptSha256,
            $package.SourceBindings.ResetLibrarySha256, $package.SourceBindings.ResetRunnerSha256,
            $package.SourceBindings.ResetProviderSha256
        )) { $prompt | Should -Match $binding }
        foreach ($tool in $package.Tools) { $prompt | Should -Match $tool.Sha256 }
        foreach ($bootstrapCredential in $second.Profiles) {
            $prompt | Should -Match $bootstrapCredential.ReceiptSha256
        }
        $productRepositoryLine = 'Role=Product;RepositoryIdentity=github.com/synthetic/product;' +
            'RepositoryNumericId=7001;RepositoryNodeId=R_SYNTHETIC_PRODUCT;Visibility=PUBLIC;' +
            'Ref=refs/heads/codex/repair/bootstrap-fixture;IntendedAccess=READ_ONLY_EXACT_COMMIT'
        $hostToVmRepositoryLine = 'Role=HostToVm;RepositoryIdentity=github.com/synthetic/host-to-vm;' +
            'RepositoryNumericId=7002;RepositoryNodeId=R_SYNTHETIC_HOST_TO_VM;Visibility=PUBLIC;' +
            'Ref=refs/heads/main;IntendedAccess=READ_ONLY;GenesisCommitSha=' + ('3' * 40)
        $vmToHostRepositoryLine = 'Role=VmToHost;RepositoryIdentity=github.com/synthetic/vm-to-host;' +
            'RepositoryNumericId=7003;RepositoryNodeId=R_SYNTHETIC_VM_TO_HOST;Visibility=PUBLIC;' +
            'Ref=refs/heads/main;IntendedAccess=APPEND_ONLY;GenesisCommitSha=' + ('4' * 40)
        $prompt.Contains('RepositoryFacts=' + $productRepositoryLine + '|' +
            $hostToVmRepositoryLine + '|' + $vmToHostRepositoryLine) | Should -BeTrue
        $prompt.Contains('ProtectionFacts=RepositoryVisibility=PUBLIC;PolicySha256=' +
            $package.SourceBindings.PolicySha256 +
            ';HostProtectionFactsAreSenderAuthority=false;RemoteAuthorizationStatus=UNPROVISIONED;' +
            'RuntimeProtectionAssertionStatus=UNPROVISIONED') | Should -BeTrue
        $prompt | Should -Match 'never sender authority'
        $prompt | Should -Not -Match '(?i)ruleset|19068339|19068292|19068313'
        $prompt | Should -Match 'PAUSED'
        $prompt | Should -Match 'VmCredentialReady=false'
        $prompt | Should -Match 'UNPROVISIONED'
        $forgedRepositoryPackage = $package.PSObject.Copy()
        $forgedProductFact = $package.RepositoryFacts.Product.PSObject.Copy()
        $forgedProductFact.RepositoryIdentity = 'github.com/synthetic/forged-product'
        $forgedRepositoryPackage.RepositoryFacts = [pscustomobject][ordered]@{
            Product = $forgedProductFact
            HostToVm = $package.RepositoryFacts.HostToVm
            VmToHost = $package.RepositoryFacts.VmToHost
        }
        { New-CddsiFastLaneVmAutomationPrompt -Package $forgedRepositoryPackage `
                -BootstrapResult $second } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_REPOSITORY_FACTS_INVALID*'
        $forgedProtectionPackage = $package.PSObject.Copy()
        $forgedProtectionPackage.ProtectionFacts = [pscustomobject][ordered]@{
            RepositoryVisibility = 'PUBLIC'; PolicySha256 = $package.SourceBindings.PolicySha256
            HostProtectionFactsAreSenderAuthority = $true
            RemoteAuthorizationStatus = 'UNPROVISIONED'
            RuntimeProtectionAssertionStatus = 'UNPROVISIONED'
        }
        { New-CddsiFastLaneVmAutomationPrompt -Package $forgedProtectionPackage `
                -BootstrapResult $second } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_REPOSITORY_FACTS_INVALID*'
        $extraFactsPackage = $package.PSObject.Copy()
        $extraProtectionFacts = $package.ProtectionFacts.PSObject.Copy()
        $extraProtectionFacts | Add-Member -NotePropertyName RulesetId -NotePropertyValue 19068339
        $extraFactsPackage.ProtectionFacts = $extraProtectionFacts
        { New-CddsiFastLaneVmAutomationPrompt -Package $extraFactsPackage `
                -BootstrapResult $second } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_REPOSITORY_FACTS_INVALID*'

        $handoffTomlFixture = New-VmAutomationTomlFixture -Fixture $fixture -Prompt $prompt
        $automationReadback = $null
        $automationMatch = Get-CddsiFastLaneVmAutomationTomlMatch `
            -AutomationRoot (Split-Path $handoffTomlFixture.AutomationDirectory -Parent)
        try {
            $automationMatch.MatchCount | Should -Be 1
            $automationToml = $automationMatch.Toml
            $automationToml.Prompt | Should -BeExactly $prompt
            $automationMatch.Stream.CanRead | Should -BeTrue
            { Assert-VmAutomationTomlLeaseReleased -Path $handoffTomlFixture.TomlPath } |
                Should -Throw
            $automationMatch.Stream.Position = 0
            $tomlMemory = New-Object IO.MemoryStream
            try {
                $automationMatch.Stream.CopyTo($tomlMemory)
                $tomlBytes = [byte[]]$tomlMemory.ToArray()
            }
            finally { $tomlMemory.Dispose() }
            $automationToml.TomlSha256 | Should -BeExactly `
                (Get-CddsiFastLaneVmBootstrapBytesSha256 $tomlBytes)
            $automationToml.TomlLengthBytes | Should -Be $tomlBytes.LongLength
            $midPhaseDuplicateDirectory = Join-Path $handoffTomlFixture.AutomationRoot `
                'mid-phase-duplicate'
            [IO.Directory]::CreateDirectory($midPhaseDuplicateDirectory) | Out-Null
            $midPhaseDuplicatePath = Join-Path $midPhaseDuplicateDirectory 'automation.toml'
            [IO.File]::WriteAllBytes($midPhaseDuplicatePath, $handoffTomlFixture.Bytes)
            try {
                { Get-CddsiFastLaneVmAutomationTomlReadback `
                        -AutomationRoot $handoffTomlFixture.AutomationRoot `
                        -OriginalMatch $automationMatch } |
                    Should -Throw '*VM_BOOTSTRAP_AUTOMATION_MATCH_COUNT_INVALID*'
                $automationMatch.Stream.CanRead | Should -BeTrue
                $automationMatch.Stream.Position = 0
                $automationMatch.Stream.ReadByte() | Should -BeGreaterOrEqual 0
            }
            finally {
                [IO.File]::Delete($midPhaseDuplicatePath)
                [IO.Directory]::Delete($midPhaseDuplicateDirectory, $false)
            }
            $automationReadback = Get-CddsiFastLaneVmAutomationTomlReadback `
                -AutomationRoot $handoffTomlFixture.AutomationRoot `
                -OriginalMatch $automationMatch
            $automationReadback.Stream.CanRead | Should -BeTrue
            $automationToml = $automationReadback.Toml
            $automationToml.TomlSha256 | Should -BeExactly $handoffTomlFixture.Sha256
            $automationToml.TomlLengthBytes | Should -Be $handoffTomlFixture.LengthBytes
            $expectedCurrentThreadId = $automationToml.TargetThreadId
            $handoff = New-CddsiFastLaneVmBootstrapHandoffClosure `
                -Package $package -BootstrapResult $second -AutomationToml $automationToml `
                -ExpectedCurrentThreadId $expectedCurrentThreadId
            $repeatHandoff = New-CddsiFastLaneVmBootstrapHandoffClosure `
                -Package $package -BootstrapResult $second -AutomationToml $automationToml `
                -ExpectedCurrentThreadId $expectedCurrentThreadId
            $handoff.Status | Should -BeExactly 'VM_BOOTSTRAP_STAGED'
            $handoff.PackageRevalidated | Should -BeTrue
            $expectedHandoffProperties = @(
                'SchemaVersion','ContractVersion','Status','EvidenceClass','BootstrapOnly',
                'PackageRevalidated','ProductCommitSha','ProductTreeSha','ZipSha256','ZipLengthBytes',
                'ManifestSha256','ManifestLengthBytes','ManifestBindingToken','InventorySha256',
                'InventoryLengthBytes','InventoryBindingToken','BundleContentDigestSha256','PublicProfiles',
                'PublicProfileCount','AutomationContract','AutomationId','AutomationStatus',
                'AutomationPromptSha256','AutomationTomlSha256','AutomationTomlLengthBytes',
                'AutomationTargetThreadBindingToken','AutomationReadbackBindingToken','CredentialStatus',
                'RemoteAuthorizationStatus','VmCredentialReady','RuntimeProtectionAssertionStatus',
                'PrivateKeyIncluded','RealPathIncluded','SidIncluded','NetworkRequestCount','GitInvocationCount',
                'ProductLiveInvocationCount','ProductWriteCount','CanStartVmIntegration','P10A0AComplete',
                'CanStartFormalP10A'
            )
            Test-CddsiExactPropertySet -InputObject $handoff -Expected $expectedHandoffProperties |
                Should -BeTrue
            $handoff.AutomationTomlSha256 | Should -BeExactly $automationToml.TomlSha256
            $handoff.AutomationTomlLengthBytes | Should -Be $automationToml.TomlLengthBytes
            $handoff.AutomationTargetThreadBindingToken | Should -BeExactly `
                (Get-CddsiSupplyChainTextBindingToken -Text $automationToml.TargetThreadId)
            $expectedObservation = [pscustomobject][ordered]@{
                SchemaVersion = 1
                ContractVersion = 'cddsi-fast-lane-vm-automation-observation-v3'
                MatchCount = 1; Id = $automationToml.Id; Kind = $automationToml.Kind
                Name = $automationToml.Name; Status = $automationToml.Status
                RRule = $automationToml.RRule; TargetThreadId = $automationToml.TargetThreadId
                CadenceMinutes = [long]$package.AutomationContract.CadenceMinutes
                DestinationContract = $package.AutomationContract.DestinationContract
                TargetTaskToken = $package.AutomationContract.TargetTaskToken
                ReconcileMode = $package.AutomationContract.ReconcileMode
                Prompt = $automationToml.Prompt
                PromptSha256 = Get-CddsiSupplyChainTextBindingToken -Text $automationToml.Prompt
                TomlSha256 = $automationToml.TomlSha256
                TomlLengthBytes = [long]$automationToml.TomlLengthBytes
            }
            $handoff.AutomationReadbackBindingToken | Should -BeExactly `
                (Get-CddsiFastLaneVmBootstrapBindingToken $expectedObservation)
            $handoff.AutomationReadbackBindingToken |
                Should -BeExactly $repeatHandoff.AutomationReadbackBindingToken
            $handoff.VmCredentialReady | Should -BeFalse
            $handoff.CanStartVmIntegration | Should -BeFalse
            $handoff.PrivateKeyIncluded | Should -BeFalse
            $handoff.RealPathIncluded | Should -BeFalse
            $handoff.SidIncluded | Should -BeFalse
            (ConvertTo-CddsiVmTestRelayCanonicalJson $handoff) |
                Should -Not -Match ([regex]::Escape($fixture.Root))

            foreach ($mutation in @(
                { param($value) $value.Prompt = $value.Prompt + "`nforged" },
                { param($value) $value.Status = 'ACTIVE' },
                { param($value) $value.RRule = 'FREQ=HOURLY' },
                { param($value) $value.TargetThreadId = 'wrong-task' },
                { param($value) $value.TomlSha256 = 'z' * 64 },
                { param($value) $value.TomlLengthBytes = 1 }
            )) {
                $forgedToml = $automationToml.PSObject.Copy()
                & $mutation $forgedToml
                { New-CddsiFastLaneVmBootstrapHandoffClosure -Package $package `
                        -BootstrapResult $second -AutomationToml $forgedToml `
                        -ExpectedCurrentThreadId $expectedCurrentThreadId } |
                    Should -Throw '*VM_BOOTSTRAP_HANDOFF_BINDING_INVALID*'
            }
            { New-CddsiFastLaneVmBootstrapHandoffClosure -Package $package `
                    -BootstrapResult $second -AutomationToml $automationToml `
                    -ExpectedCurrentThreadId '019f7000-1234-7abc-8def-0123456789ac' } |
                Should -Throw '*VM_BOOTSTRAP_HANDOFF_BINDING_INVALID*'
            $extraToml = $automationToml.PSObject.Copy()
            $extraToml | Add-Member -NotePropertyName Observation -NotePropertyValue 'forged'
            { New-CddsiFastLaneVmBootstrapHandoffClosure -Package $package `
                    -BootstrapResult $second -AutomationToml $extraToml `
                    -ExpectedCurrentThreadId $expectedCurrentThreadId } |
                Should -Throw '*VM_BOOTSTRAP_HANDOFF_BINDING_INVALID*'
            $forgedResult = $second.PSObject.Copy()
            $forgedResult.ProductTreeSha = 'f' * 40
            { New-CddsiFastLaneVmBootstrapHandoffClosure -Package $package `
                    -BootstrapResult $forgedResult -AutomationToml $automationToml `
                    -ExpectedCurrentThreadId $expectedCurrentThreadId } |
                Should -Throw '*VM_BOOTSTRAP_HANDOFF_RESULT_BINDING_INVALID*'
            $roundTrippedBoundResult = ConvertFrom-Json `
                (ConvertTo-CddsiVmTestRelayCanonicalJson $second)
            Test-CddsiFastLaneVmBootstrapResultBinding `
                -Package $package -BootstrapResult $roundTrippedBoundResult | Should -BeTrue
            foreach ($resultMutation in @(
                { param($value) $value.Status = 'VM_BOOTSTRAP_STAGED' },
                { param($value) $value.DirectoryCreateCount = 99 },
                { param($value) $value.PrivateKeyIncluded = $true },
                { param($value) $value.Profiles = @($value.Profiles[2], $value.Profiles[1], $value.Profiles[0]) },
                { param($value) $value.Profiles[0].ReceiptBindingToken = '0' * 64 },
                { param($value) $value.Profiles[0].PublicKey = $value.Profiles[0].PublicKey + ' forged' }
            )) {
                $forgedBoundResult = ConvertFrom-Json `
                    (ConvertTo-CddsiVmTestRelayCanonicalJson $second)
                & $resultMutation $forgedBoundResult
                { New-CddsiFastLaneVmBootstrapHandoffClosure -Package $package `
                        -BootstrapResult $forgedBoundResult -AutomationToml $automationToml `
                        -ExpectedCurrentThreadId $expectedCurrentThreadId } |
                    Should -Throw '*VM_BOOTSTRAP_HANDOFF_RESULT_BINDING_INVALID*'
            }
            $extraResult = $second.PSObject.Copy()
            $extraResult | Add-Member -NotePropertyName Observation -NotePropertyValue 'forged'
            { New-CddsiFastLaneVmBootstrapHandoffClosure -Package $package `
                    -BootstrapResult $extraResult -AutomationToml $automationToml `
                    -ExpectedCurrentThreadId $expectedCurrentThreadId } |
                Should -Throw '*VM_BOOTSTRAP_HANDOFF_RESULT_BINDING_INVALID*'
        }
        finally {
            if ($null -ne $automationReadback -and $null -ne $automationReadback.Stream) {
                $automationReadback.Stream.Dispose()
            }
            if ($null -ne $automationMatch -and $null -ne $automationMatch.Stream) {
                $automationMatch.Stream.Dispose()
            }
        }
        Assert-VmAutomationTomlLeaseReleased -Path $handoffTomlFixture.TomlPath

        $disposedOriginal = [pscustomobject][ordered]@{
            MatchCount = 1
            AutomationDirectory = $automationMatch.AutomationDirectory
            TomlPath = $automationMatch.TomlPath
            Toml = $automationMatch.Toml
            Stream = $automationMatch.Stream
        }
        { Get-CddsiFastLaneVmAutomationTomlReadback `
                -AutomationRoot $handoffTomlFixture.AutomationRoot `
                -OriginalMatch $disposedOriginal } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_ORIGINAL_LEASE_INVALID*'
        $extraOriginal = $disposedOriginal.PSObject.Copy()
        $extraOriginal | Add-Member -NotePropertyName ForgedObservation -NotePropertyValue $true
        { Get-CddsiFastLaneVmAutomationTomlReadback `
                -AutomationRoot $handoffTomlFixture.AutomationRoot `
                -OriginalMatch $extraOriginal } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_ORIGINAL_LEASE_INVALID*'
        $missingOriginal = [pscustomobject][ordered]@{
            MatchCount = 1
            AutomationDirectory = $automationMatch.AutomationDirectory
            Toml = $automationMatch.Toml
            Stream = $automationMatch.Stream
        }
        { Get-CddsiFastLaneVmAutomationTomlReadback `
                -AutomationRoot $handoffTomlFixture.AutomationRoot `
                -OriginalMatch $missingOriginal } |
            Should -Throw '*VM_BOOTSTRAP_AUTOMATION_ORIGINAL_LEASE_INVALID*'
        $memoryOriginalStream = New-Object IO.MemoryStream
        try {
            $memoryOriginal = [pscustomobject][ordered]@{
                MatchCount = 1
                AutomationDirectory = $automationMatch.AutomationDirectory
                TomlPath = $automationMatch.TomlPath
                Toml = $automationMatch.Toml
                Stream = $memoryOriginalStream
            }
            { Get-CddsiFastLaneVmAutomationTomlReadback `
                    -AutomationRoot $handoffTomlFixture.AutomationRoot `
                    -OriginalMatch $memoryOriginal } |
                Should -Throw '*VM_BOOTSTRAP_AUTOMATION_ORIGINAL_LEASE_INVALID*'
        }
        finally { $memoryOriginalStream.Dispose() }

        $forgedLeasePath = Join-Path $fixture.Root 'forged-original-lease.bin'
        [IO.File]::WriteAllBytes($forgedLeasePath, [byte[]]@(1, 2, 3, 4))
        $forgedOriginalStream = [IO.File]::Open(
            $forgedLeasePath, [IO.FileMode]::Open, [IO.FileAccess]::Read, [IO.FileShare]::Read)
        try {
            foreach ($originalMutation in @(
                { param($value) $value.AutomationDirectory = Join-Path $fixture.Root 'forged-automation' },
                { param($value) $value.TomlPath = Join-Path $fixture.Root 'forged-automation.toml' },
                { param($value) $value.Toml.TomlSha256 = '0' * 64 },
                { param($value) $value.Toml.TomlLengthBytes = [long]($value.Toml.TomlLengthBytes + 1) },
                { param($value) $value.Toml.Prompt = [string]$value.Toml.Prompt + ' forged' }
            )) {
                $forgedOriginal = [pscustomobject][ordered]@{
                    MatchCount = 1
                    AutomationDirectory = $automationMatch.AutomationDirectory
                    TomlPath = $automationMatch.TomlPath
                    Toml = ConvertFrom-Json (ConvertTo-CddsiVmTestRelayCanonicalJson $automationMatch.Toml)
                    Stream = $forgedOriginalStream
                }
                & $originalMutation $forgedOriginal
                { Get-CddsiFastLaneVmAutomationTomlReadback `
                        -AutomationRoot $handoffTomlFixture.AutomationRoot `
                        -OriginalMatch $forgedOriginal } |
                    Should -Throw '*VM_BOOTSTRAP_AUTOMATION_READBACK_INVALID*'
                Assert-VmAutomationTomlLeaseReleased -Path $handoffTomlFixture.TomlPath
            }
        }
        finally { $forgedOriginalStream.Dispose() }
    }

    It 'rejects ACL or owner-marker drift anywhere in the loader-owned parent chain before mutation' {
        $fixture = New-VmBootstrapFixture
        $packageArguments = @{} + $fixture.PackageArguments
        $packageArguments.BoundZipBytes = [IO.File]::ReadAllBytes($fixture.PackageArguments.ZipPath)
        $package = Test-CddsiFastLaneVmOnboardingPackage @packageArguments
        Mock Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
            throw 'PARENT_CHAIN_VALIDATION_MUST_PRECEDE_KEYGEN'
        }
        $fastLaneRoot = Split-Path $fixture.PackageParent -Parent
        $projectOwnerRoot = Split-Path $fastLaneRoot -Parent
        $packageAction = {
            param($BoundPackage, $BoundFixture)
            Expand-CddsiFastLaneVmBootstrapPackage -Package $BoundPackage `
                -StagingRoot $BoundFixture.PackageStagingRoot `
                -ProductRoot (Join-Path $BoundFixture.PackageStagingRoot 'payload') `
                -CredentialRoot $BoundFixture.CredentialRoot
        }
        $credentialAction = {
            param($BoundPackage, $BoundFixture)
            Invoke-VmBootstrapFixtureCore -Package $BoundPackage `
                -CredentialRoot $BoundFixture.CredentialRoot -ProductRoot $BoundFixture.ProductRoot `
                -SshKeygenExecutable $BoundFixture.KeygenPath `
                -ExpectedSshKeygenSha256 $BoundFixture.KeygenSha256
        }
        $parentCases = @(
            @{ Path = $projectOwnerRoot; Role = 'Project'; Action = $packageAction },
            @{ Path = $fastLaneRoot; Role = 'FastLane'; Action = $packageAction },
            @{ Path = $fixture.PackageParent; Role = 'PackageParent'; Action = $packageAction },
            @{ Path = $fixture.CredentialParent; Role = 'CredentialParent'; Action = $credentialAction }
        )
        $everyoneSid = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
        foreach ($parentCase in $parentCases) {
            $parentSecurity = Get-VmBootstrapTestDirectorySecurity -Path $parentCase.Path
            $extraParentRule = New-Object Security.AccessControl.FileSystemAccessRule(
                $everyoneSid, [Security.AccessControl.FileSystemRights]::Read,
                [Security.AccessControl.InheritanceFlags]::None,
                [Security.AccessControl.PropagationFlags]::None,
                [Security.AccessControl.AccessControlType]::Allow)
            [void]$parentSecurity.AddAccessRule($extraParentRule)
            Set-VmBootstrapTestDirectorySecurity -Path $parentCase.Path -Security $parentSecurity
            { & ([scriptblock]$parentCase.Action) $package $fixture } | Should -Throw '*PARENT_INVALID*'
            Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $parentCase.Path -PathKind Directory
            Test-CddsiFastLaneVmBootstrapOwnedParent `
                -Path $parentCase.Path -Role $parentCase.Role | Should -BeTrue

            $parentMarkerPath = Join-Path $parentCase.Path '.cddsi-directory-owner.json'
            $originalMarkerBytes = [IO.File]::ReadAllBytes($parentMarkerPath)
            $forgedMarker = Read-CddsiFastLaneCanonicalFile -Path $parentMarkerPath -MaximumBytes 16384
            $forgedMarker | Add-Member -NotePropertyName Forged -NotePropertyValue $true
            Write-CddsiFastLaneCanonicalFile -Path $parentMarkerPath -Value $forgedMarker
            try { { & ([scriptblock]$parentCase.Action) $package $fixture } | Should -Throw '*PARENT_INVALID*' }
            finally { [IO.File]::WriteAllBytes($parentMarkerPath, $originalMarkerBytes) }
            Test-CddsiFastLaneVmBootstrapOwnedParent `
                -Path $parentCase.Path -Role $parentCase.Role | Should -BeTrue
        }
        [IO.Directory]::Exists($fixture.PackageStagingRoot) | Should -BeFalse
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeFalse
        Assert-MockCalled Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Times 0 -Exactly
    }

    It 'cleans both newly owned staging and credential roots after a post-bootstrap phase2 failure' {
        $fixture = New-VmBootstrapFixture
        $packageArguments = @{} + $fixture.PackageArguments
        $packageArguments.BoundZipBytes = [IO.File]::ReadAllBytes($fixture.PackageArguments.ZipPath)
        $package = Test-CddsiFastLaneVmOnboardingPackage @packageArguments
        Mock Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
            param($Executable, $PrivateKeyPath, $ProfileId, $Operation)
            $ordinal = [Array]::IndexOf($script:CddsiFastLaneVmBootstrapProfiles, $ProfileId) + 1
            $blob = [byte[]]@(0..63 | ForEach-Object { [byte](($_ + ($ordinal * 19)) % 256) })
            $publicPrefix = 'ssh-ed25519 ' + [Convert]::ToBase64String($blob)
            if ($Operation -ceq 'DerivePublic') {
                return [pscustomobject]@{
                    ExitCode = 0; TimedOut = $false; Truncated = $false; JobAssigned = $true
                    StandardOutput = $publicPrefix + "`n"
                }
            }
            [IO.File]::WriteAllText(
                $PrivateKeyPath, ('post-bootstrap-private-' + $ProfileId + ('x' * 64)),
                (New-Object Text.UTF8Encoding($false)))
            [IO.File]::WriteAllText(
                ($PrivateKeyPath + '.pub'), ($publicPrefix + ' cddsi:' + $ProfileId + "`n"),
                (New-Object Text.UTF8Encoding($false)))
            return [pscustomobject]@{
                ExitCode = 0; TimedOut = $false; Truncated = $false; JobAssigned = $true
                StandardOutput = ''
            }
        }

        $staging = Expand-CddsiFastLaneVmBootstrapPackage -Package $package `
            -StagingRoot $fixture.PackageStagingRoot `
            -ProductRoot (Join-Path $fixture.PackageStagingRoot 'payload') `
            -CredentialRoot $fixture.CredentialRoot
        $staging | Add-Member -NotePropertyName StagingRoot `
            -NotePropertyValue ([IO.Path]::GetFullPath($fixture.PackageStagingRoot))
        $credentialOwnership = $null
        $bootstrap = Invoke-CddsiFastLaneVmBootstrapMutationClosure -Package $package `
            -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
            -SshKeygenExecutable $fixture.KeygenPath `
            -ExpectedSshKeygenSha256 $fixture.KeygenSha256 `
            -CreatedOwnership ([ref]$credentialOwnership)
        $credentialOwnership.Changed | Should -BeTrue

        $failure = New-Object InvalidOperationException(
            'VM_BOOTSTRAP_AUTOMATION_PROMPT_BINDING_INVALID')
        $internalStagingRef = 'must be cleared'
        $internalCredentialRef = 'must be cleared'
        $compensationArguments = @{} + $fixture.PackageArguments
        $compensationArguments.Mode = 'Live'
        $compensationArguments.BootstrapExecutionContext = [pscustomobject]@{}
        $compensationArguments.ProductRoot = $fixture.ProductRoot
        $compensationArguments.PackageStagingRoot = $fixture.PackageStagingRoot
        $compensationArguments.CredentialRoot = $fixture.CredentialRoot
        $compensationArguments.ExpectedAutomationTargetCurrentTaskToken = 'CURRENT_TASK'
        $compensationArguments.AcknowledgeVmBootstrapLive = $true
        $compensationArguments.InternalStagingOwnership = ([ref]$internalStagingRef)
        $compensationArguments.InternalCredentialOwnership = ([ref]$internalCredentialRef)
        $compensationArguments.InternalCompensationContext = [pscustomobject][ordered]@{
            FailureException = $failure; Staging = $staging; Bootstrap = $bootstrap
            CredentialOwnership = $credentialOwnership
        }
        $blocked = Invoke-CddsiTestVmBootstrapPhaseOneClosure @compensationArguments
        $internalStagingRef | Should -BeNullOrEmpty
        $internalCredentialRef | Should -BeNullOrEmpty
        $blocked.Status | Should -BeExactly 'VM_BOOTSTRAP_BLOCKED'
        $blocked.Changed | Should -BeFalse
        $blocked.DirectoryCreateCount | Should -Be 4
        $blocked.FileWriteCount | Should -Be 31
        $blocked.AclMutationCount | Should -Be 13
        $blocked.ProcessInvocationCount | Should -Be 6
        $blocked.DirectoryDeleteCount | Should -Be 2
        $blocked.CleanupRequired | Should -BeTrue
        $blocked.CleanupSucceeded | Should -BeTrue
        [IO.Directory]::Exists($fixture.PackageStagingRoot) | Should -BeFalse
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeFalse
        Assert-MockCalled Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Times 6 -Exactly
    }

    It 'fails closed on keygen hash, JobAssigned, overlapping roots, and an unowned existing root' {
        $fixture = New-VmBootstrapFixture
        $packageArguments = $fixture.PackageArguments
        $package = Test-CddsiFastLaneVmOnboardingPackage @packageArguments
        Mock Invoke-CddsiFastLaneVmBootstrapKeygenProcess {
            param($Executable, $PrivateKeyPath, $ProfileId, $Operation)
            [IO.File]::WriteAllText($PrivateKeyPath, ('x' * 64), (New-Object Text.UTF8Encoding($false)))
            [IO.File]::WriteAllText(
                ($PrivateKeyPath + '.pub'),
                ('ssh-ed25519 ' + [Convert]::ToBase64String([byte[]](0..63)) + ' cddsi:' + $ProfileId),
                (New-Object Text.UTF8Encoding($false)))
            return [pscustomobject]@{ ExitCode = 0; TimedOut = $false; Truncated = $false; JobAssigned = $false }
        }
        { Invoke-VmBootstrapFixtureCore `
            -Package $package -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
            -SshKeygenExecutable $fixture.KeygenPath -ExpectedSshKeygenSha256 ('0' * 64) } |
            Should -Throw '*VM_BOOTSTRAP_KEYGEN_PACKAGE_BINDING_MISMATCH*'
        { New-CddsiFastLaneVmBootstrapPlan -Package $package `
            -CredentialRoot (Join-Path $fixture.ProductRoot ('cddsi-vm-bootstrap-' + ('a' * 32))) `
            -ProductRoot $fixture.ProductRoot } | Should -Throw '*VM_BOOTSTRAP_CREDENTIAL_ROOT_FORBIDDEN*'

        $keygenFailure = $null
        try {
            [void](Invoke-VmBootstrapFixtureCore `
                -Package $package -CredentialRoot $fixture.CredentialRoot -ProductRoot $fixture.ProductRoot `
                -SshKeygenExecutable $fixture.KeygenPath -ExpectedSshKeygenSha256 $fixture.KeygenSha256)
        }
        catch { $keygenFailure = $_.Exception }
        $keygenFailure.Message | Should -Match 'VM_BOOTSTRAP_KEYGEN_FAILED'
        $failureAccounting = Get-CddsiFastLaneVmBootstrapFailureAccounting $keygenFailure
        $failureAccounting.DirectoryCreateCount | Should -Be 1
        $failureAccounting.FileWriteCount | Should -Be 3
        $failureAccounting.AclMutationCount | Should -Be 2
        $failureAccounting.ProcessInvocationCount | Should -Be 1
        $failureAccounting.DirectoryDeleteCount | Should -Be 1
        $failureAccounting.CleanupRequired | Should -BeTrue
        $failureAccounting.CleanupSucceeded | Should -BeTrue
        [IO.Directory]::Exists($fixture.CredentialRoot) | Should -BeFalse
        Assert-MockCalled Invoke-CddsiFastLaneVmBootstrapKeygenProcess -Times 1 -Exactly

        $unownedRoot = Join-Path $fixture.CredentialParent `
            ('cddsi-vm-bootstrap-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($unownedRoot)
        { Invoke-VmBootstrapFixtureCore `
            -Package $package -CredentialRoot $unownedRoot -ProductRoot $fixture.ProductRoot `
            -SshKeygenExecutable $fixture.KeygenPath -ExpectedSshKeygenSha256 $fixture.KeygenSha256 } |
            Should -Throw '*VM_BOOTSTRAP_EXISTING_ROOT_INVALID*'
        [IO.Directory]::Exists($unownedRoot) | Should -BeTrue
    }

    It 'cleans only a newly created exact owner-marked package root and never deletes reused or unknown roots' {
        $fixture = New-VmBootstrapFixture
        $boundArguments = @{} + $fixture.PackageArguments
        $boundArguments.BoundZipBytes = [IO.File]::ReadAllBytes($fixture.PackageArguments.ZipPath)
        $package = Test-CddsiFastLaneVmOnboardingPackage @boundArguments
        $stagedProductRoot = Join-Path $fixture.PackageStagingRoot 'payload'

        $newStaging = Expand-CddsiFastLaneVmBootstrapPackage -Package $package `
            -StagingRoot $fixture.PackageStagingRoot -ProductRoot $stagedProductRoot `
            -CredentialRoot $fixture.CredentialRoot
        $newStaging.DirectoryCreateCount | Should -Be 3
        $newStaging.FileWriteCount | Should -Be 20
        $newStaging.AclMutationCount | Should -Be 1
        Test-CddsiFastLaneVmBootstrapProtectedAcl `
            -Path $fixture.PackageStagingRoot -PathKind Directory | Should -BeTrue
        $newStaging | Add-Member -NotePropertyName StagingRoot `
            -NotePropertyValue ([IO.Path]::GetFullPath($fixture.PackageStagingRoot))
        $injectedFailure = New-Object InvalidOperationException('VM_BOOTSTRAP_KEYGEN_FAILED')
        $stagingMarkerPath = Join-Path $fixture.PackageStagingRoot '.cddsi-owner.json'
        $originalStagingMarkerBytes = [IO.File]::ReadAllBytes($stagingMarkerPath)
        $malformedRunIdMarker = Read-CddsiFastLaneCanonicalFile `
            -Path $stagingMarkerPath -MaximumBytes 32768
        $malformedRunIdMarker.RunId = 'a' + ('-' * 35)
        Test-CddsiFastLaneVmBootstrapPackageMarker -Marker $malformedRunIdMarker `
            -Package $package -StagingRootBindingToken $newStaging.RootBindingToken `
            -ExpectedStage Extracted | Should -BeFalse
        $forgedStagingMarker = Read-CddsiFastLaneCanonicalFile `
            -Path $stagingMarkerPath -MaximumBytes 32768
        $forgedStagingMarker.Stage = 'Extracting'
        Write-CddsiFastLaneCanonicalFile -Path $stagingMarkerPath -Value $forgedStagingMarker
        $tamperedCleanup = New-CddsiFastLaneVmBootstrapOnboardingFailureResult -Mode Live `
            -FailureException $injectedFailure -Staging $newStaging
        $tamperedCleanup.BlockerCode | Should -BeExactly 'OWNED_CLEANUP_FAILED'
        $tamperedCleanup.CleanupRequired | Should -BeTrue
        $tamperedCleanup.CleanupSucceeded | Should -BeFalse
        $tamperedCleanup.DirectoryDeleteCount | Should -Be 0
        [IO.Directory]::Exists($fixture.PackageStagingRoot) | Should -BeTrue
        [IO.File]::WriteAllBytes($stagingMarkerPath, $originalStagingMarkerBytes)
        $cleaned = New-CddsiFastLaneVmBootstrapOnboardingFailureResult -Mode Live `
            -FailureException $injectedFailure -Staging $newStaging
        $cleaned.Status | Should -BeExactly 'VM_BOOTSTRAP_BLOCKED'
        $cleaned.BlockerCode | Should -BeExactly 'PINNED_TOOL_OR_KEYPAIR_INVALID'
        $cleaned.DirectoryCreateCount | Should -Be 3
        $cleaned.FileWriteCount | Should -Be 20
        $cleaned.AclMutationCount | Should -Be 1
        $cleaned.DirectoryDeleteCount | Should -Be 1
        $cleaned.CleanupRequired | Should -BeTrue
        $cleaned.CleanupSucceeded | Should -BeTrue
        $cleaned.Changed | Should -BeFalse
        [IO.Directory]::Exists($fixture.PackageStagingRoot) | Should -BeFalse

        $reusedRoot = Join-Path $fixture.PackageParent `
            ('cddsi-vm-package-' + [guid]::NewGuid().ToString('N'))
        $reusedProductRoot = Join-Path $reusedRoot 'payload'
        [void](Expand-CddsiFastLaneVmBootstrapPackage -Package $package -StagingRoot $reusedRoot `
            -ProductRoot $reusedProductRoot -CredentialRoot $fixture.CredentialRoot)
        $widenedStagingSecurity = Get-VmBootstrapTestDirectorySecurity -Path $reusedRoot
        $everyoneSid = New-Object Security.Principal.SecurityIdentifier('S-1-1-0')
        $extraStagingRule = New-Object Security.AccessControl.FileSystemAccessRule(
            $everyoneSid, [Security.AccessControl.FileSystemRights]::Read,
            [Security.AccessControl.InheritanceFlags]::None,
            [Security.AccessControl.PropagationFlags]::None,
            [Security.AccessControl.AccessControlType]::Allow)
        [void]$widenedStagingSecurity.AddAccessRule($extraStagingRule)
        Set-VmBootstrapTestDirectorySecurity -Path $reusedRoot -Security $widenedStagingSecurity
        Test-CddsiFastLaneVmBootstrapProtectedAcl `
            -Path $reusedRoot -PathKind Directory | Should -BeFalse
        { Expand-CddsiFastLaneVmBootstrapPackage -Package $package -StagingRoot $reusedRoot `
                -ProductRoot $reusedProductRoot -CredentialRoot $fixture.CredentialRoot } |
            Should -Throw '*VM_BOOTSTRAP_PACKAGE_STAGING_OWNER_INVALID*'
        [IO.Directory]::Exists($reusedRoot) | Should -BeTrue
        Set-CddsiFastLaneVmBootstrapProtectedAcl -Path $reusedRoot -PathKind Directory
        Test-CddsiFastLaneVmBootstrapProtectedAcl `
            -Path $reusedRoot -PathKind Directory | Should -BeTrue

        $unexpectedEmptyDirectory = Join-Path $reusedRoot 'unexpected-empty'
        [void][IO.Directory]::CreateDirectory($unexpectedEmptyDirectory)
        { Expand-CddsiFastLaneVmBootstrapPackage -Package $package -StagingRoot $reusedRoot `
                -ProductRoot $reusedProductRoot -CredentialRoot $fixture.CredentialRoot } |
            Should -Throw '*VM_BOOTSTRAP_PACKAGE_STAGING_REUSE_INVALID*'
        [IO.Directory]::Exists($unexpectedEmptyDirectory) | Should -BeTrue
        [IO.Directory]::Delete($unexpectedEmptyDirectory, $false)

        $outsideStagingTarget = Join-Path $fixture.Root 'outside-staging-target'
        [void][IO.Directory]::CreateDirectory($outsideStagingTarget)
        $outsideStagingFile = Join-Path $outsideStagingTarget 'must-remain.txt'
        [IO.File]::WriteAllText($outsideStagingFile, 'must remain')
        $descendantJunction = Join-Path $reusedRoot 'unexpected-junction'
        New-Item -ItemType Junction -Path $descendantJunction `
            -Target $outsideStagingTarget -ErrorAction Stop | Out-Null
        try {
            { Expand-CddsiFastLaneVmBootstrapPackage -Package $package -StagingRoot $reusedRoot `
                    -ProductRoot $reusedProductRoot -CredentialRoot $fixture.CredentialRoot } |
                Should -Throw '*VM_BOOTSTRAP_PACKAGE_STAGING_REUSE_INVALID*'
            [IO.File]::Exists($outsideStagingFile) | Should -BeTrue
        }
        finally {
            if ([IO.Directory]::Exists($descendantJunction)) {
                [IO.Directory]::Delete($descendantJunction, $false)
            }
        }
        $reused = Expand-CddsiFastLaneVmBootstrapPackage -Package $package -StagingRoot $reusedRoot `
            -ProductRoot $reusedProductRoot -CredentialRoot $fixture.CredentialRoot
        $reused.ReusedExisting | Should -BeTrue
        $reused.AclMutationCount | Should -Be 0
        $reused | Add-Member -NotePropertyName StagingRoot -NotePropertyValue ([IO.Path]::GetFullPath($reusedRoot))
        $reusedFailure = New-CddsiFastLaneVmBootstrapOnboardingFailureResult -Mode Live `
            -FailureException $injectedFailure -Staging $reused
        $reusedFailure.CleanupRequired | Should -BeFalse
        $reusedFailure.CleanupSucceeded | Should -BeTrue
        $reusedFailure.DirectoryDeleteCount | Should -Be 0
        [IO.Directory]::Exists($reusedRoot) | Should -BeTrue

        $unknownRoot = Join-Path $fixture.PackageParent `
            ('cddsi-vm-package-' + [guid]::NewGuid().ToString('N'))
        [void][IO.Directory]::CreateDirectory($unknownRoot)
        $unknown = [pscustomobject]@{
            Changed = $true; ReusedExisting = $false; StagingRoot = $unknownRoot
            OwnerRunId = [guid]::NewGuid().ToString('D'); DirectoryCreateCount = 0
            FileWriteCount = 0; AclMutationCount = 0
        }
        $unknownFailure = New-CddsiFastLaneVmBootstrapOnboardingFailureResult -Mode Live `
            -FailureException $injectedFailure -Staging $unknown
        $unknownFailure.BlockerCode | Should -BeExactly 'OWNED_CLEANUP_FAILED'
        $unknownFailure.CleanupRequired | Should -BeTrue
        $unknownFailure.CleanupSucceeded | Should -BeFalse
        $unknownFailure.DirectoryDeleteCount | Should -Be 0
        [IO.Directory]::Exists($unknownRoot) | Should -BeTrue
        (ConvertTo-CddsiVmTestRelayCanonicalJson $unknownFailure) |
            Should -Not -Match ([regex]::Escape($unknownRoot))
    }
}
