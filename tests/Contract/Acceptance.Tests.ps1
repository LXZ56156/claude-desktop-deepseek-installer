BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    $script:AcceptanceNowUtc = [datetimeoffset]'2026-07-14T08:00:00Z'
    $script:AcceptanceObservedAtUtc = '2026-07-14T07:59:30.0000000Z'
    $script:AcceptanceEnvironmentImageSha256 = ('b' * 64)

    function Get-CddsiAcceptanceExpectedParameters {
        param(
            [string]$ArtifactSha256 = ('a' * 64),
            [string]$EnvironmentImageSha256 = ('b' * 64),
            [Alias('Profile')][string]$ArtifactProfile = 'VmAcceptance',
            [string]$ScenarioId = 'synthetic_happy_path',
            [string]$RunId = '00000000-0000-0000-0000-000000000901',
            [datetimeoffset]$NowUtc = ([datetimeoffset]'2026-07-14T08:00:00Z'),
            [int]$MaxEvidenceAgeSeconds = 300,
            [object[]]$SurfaceEvidenceTokens,
            [AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens = @()
        )

        if ($null -eq $SurfaceEvidenceTokens) {
            $SurfaceEvidenceTokens = @(
                [pscustomobject][ordered]@{ Surface = 'Chat'; Status = 'PASS'; EvidenceToken = ('c' * 64) },
                [pscustomobject][ordered]@{ Surface = 'Code'; Status = 'PASS'; EvidenceToken = ('d' * 64) },
                [pscustomobject][ordered]@{ Surface = 'Cowork'; Status = 'PASS'; EvidenceToken = ('e' * 64) }
            )
        }
        return @{
            ExpectedArtifactSha256          = $ArtifactSha256
            ExpectedEnvironmentImageSha256 = $EnvironmentImageSha256
            ExpectedProfile                 = $ArtifactProfile
            ExpectedScenarioId              = $ScenarioId
            ExpectedRunId                   = $RunId
            ExpectedNowUtc                  = $NowUtc
            MaxEvidenceAgeSeconds           = $MaxEvidenceAgeSeconds
            ExpectedSurfaceEvidenceTokens   = @($SurfaceEvidenceTokens)
            PreviouslyConsumedEvidenceTokens = @($PreviouslyConsumedEvidenceTokens)
        }
    }

    function New-CddsiAcceptanceCapabilityFixture {
        param(
            [string]$Chat = 'READY',
            [string]$Code = 'READY',
            [string]$Cowork = 'READY'
        )

        $statuses = @($Chat, $Code, $Cowork)
        $names = @('Chat', 'Code', 'Cowork')
        $result = @()
        for ($index = 0; $index -lt $names.Count; $index++) {
            $reasons = if ($statuses[$index] -ceq 'READY') { @() } else { @(('{0}_{1}' -f $names[$index].ToUpperInvariant(), $statuses[$index])) }
            $result += [pscustomobject][ordered]@{ Surface = $names[$index]; Status = $statuses[$index]; ReasonCodes = @($reasons) }
        }
        return @($result)
    }

    function New-CddsiExternalE2eEvidenceFixture {
        param(
            [string]$ArtifactSha256 = ('a' * 64),
            [string]$EnvironmentImageSha256 = ('b' * 64),
            [Alias('Profile')][string]$ArtifactProfile = 'VmAcceptance',
            [string]$ScenarioId = 'synthetic_happy_path',
            [string]$RunId = '00000000-0000-0000-0000-000000000901',
            [string]$ObservedAtUtc = '2026-07-14T07:59:30.0000000Z',
            [object[]]$SurfaceEvidenceTokens,
            [string]$Chat = 'PASS',
            [string]$Code = 'PASS',
            [string]$Cowork = 'PASS'
        )

        if ($null -eq $SurfaceEvidenceTokens) {
            $SurfaceEvidenceTokens = (Get-CddsiAcceptanceExpectedParameters).ExpectedSurfaceEvidenceTokens
        }
        $statuses = @($Chat, $Code, $Cowork)
        $names = @('Chat', 'Code', 'Cowork')
        $surfaces = @()
        for ($index = 0; $index -lt $names.Count; $index++) {
            $token = if ($statuses[$index] -ceq 'NOT_TESTED') { $null } else { [string]$SurfaceEvidenceTokens[$index].EvidenceToken }
            $surfaces += [pscustomobject][ordered]@{ Surface = $names[$index]; Status = $statuses[$index]; EvidenceToken = $token }
        }
        return [pscustomobject][ordered]@{
            SchemaVersion          = 1
            ArtifactSha256         = $ArtifactSha256
            EnvironmentImageSha256 = $EnvironmentImageSha256
            Profile                = $ArtifactProfile
            ScenarioId             = $ScenarioId
            RunId                  = $RunId
            ObservedAtUtc           = $ObservedAtUtc
            Surfaces                = @($surfaces)
        }
    }

    function New-CddsiBoundAcceptanceEvidenceFixture {
        param(
            [Parameter(Mandatory = $true)][object[]]$Capabilities,
            [string]$ArtifactSha256 = ('a' * 64),
            [string]$EnvironmentImageSha256 = ('b' * 64),
            [Alias('Profile')][string]$ArtifactProfile = 'VmAcceptance',
            [string]$ScenarioId = 'synthetic_happy_path',
            [string]$RunId = '00000000-0000-0000-0000-000000000901',
            [datetimeoffset]$NowUtc = ([datetimeoffset]'2026-07-14T08:00:00Z'),
            [int]$MaxEvidenceAgeSeconds = 300,
            [object[]]$SurfaceEvidenceTokens,
            [AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens = @(),
            [AllowNull()]$ExternalE2eEvidence,
            [AllowEmptyCollection()][object[]]$CompensationResources = @(),
            [switch]$Cancelled
        )

        $expected = Get-CddsiAcceptanceExpectedParameters -ArtifactSha256 $ArtifactSha256 -EnvironmentImageSha256 $EnvironmentImageSha256 -ArtifactProfile $ArtifactProfile -ScenarioId $ScenarioId -RunId $RunId -NowUtc $NowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -SurfaceEvidenceTokens $SurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens
        return New-CddsiAcceptanceEvidence -ExpectedCapabilities $Capabilities @expected -ExternalE2eEvidence $ExternalE2eEvidence -CompensationResources $CompensationResources -Cancelled:$Cancelled
    }

    function Test-CddsiBoundAcceptanceEvidenceFixture {
        param(
            [Parameter(Mandatory = $true)]$Evidence,
            [object[]]$ExpectedCapabilities,
            [string]$ArtifactSha256 = ('a' * 64),
            [string]$EnvironmentImageSha256 = ('b' * 64),
            [Alias('Profile')][string]$ArtifactProfile = 'VmAcceptance',
            [string]$ScenarioId = 'synthetic_happy_path',
            [string]$RunId = '00000000-0000-0000-0000-000000000901',
            [datetimeoffset]$NowUtc = ([datetimeoffset]'2026-07-14T08:00:00Z'),
            [int]$MaxEvidenceAgeSeconds = 300,
            [object[]]$SurfaceEvidenceTokens,
            [AllowEmptyCollection()][string[]]$PreviouslyConsumedEvidenceTokens = @()
        )

        if ($null -eq $ExpectedCapabilities) { $ExpectedCapabilities = New-CddsiAcceptanceCapabilityFixture }
        $expected = Get-CddsiAcceptanceExpectedParameters -ArtifactSha256 $ArtifactSha256 -EnvironmentImageSha256 $EnvironmentImageSha256 -ArtifactProfile $ArtifactProfile -ScenarioId $ScenarioId -RunId $RunId -NowUtc $NowUtc -MaxEvidenceAgeSeconds $MaxEvidenceAgeSeconds -SurfaceEvidenceTokens $SurfaceEvidenceTokens -PreviouslyConsumedEvidenceTokens $PreviouslyConsumedEvidenceTokens
        return Test-CddsiAcceptanceEvidence -Evidence $Evidence -ExpectedCapabilities $ExpectedCapabilities @expected
    }
}

Describe 'P9 synthetic acceptance evidence' {
    It 'creates strict fixed-surface evidence and keeps UI NOT_TESTED without external evidence' {
        $evidence = New-CddsiBoundAcceptanceEvidenceFixture `
            -Capabilities (New-CddsiAcceptanceCapabilityFixture) `
            -ArtifactSha256 ('a' * 64) `
            -Profile VmAcceptance `
            -ScenarioId synthetic_happy_path `
            -RunId '00000000-0000-0000-0000-000000000901'

        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $evidence) | Should -BeTrue
        @($evidence.RequestedSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        @($evidence.Capabilities.Surface) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        @($evidence.UiEvidence.Surface) -join '|' | Should -BeExactly 'Chat|Code|Cowork'
        (@($evidence.UiEvidence.Status | Select-Object -Unique) -join '|') | Should -BeExactly 'NOT_TESTED'
        (@($evidence.UiEvidence.Source | Select-Object -Unique) -join '|') | Should -BeExactly 'NONE'
        $evidence.Run.Status | Should -BeExactly 'ACTION_REQUIRED'
        $evidence.Run.Success | Should -BeFalse
        @($evidence.Run.ReasonCodes) | Should -Contain 'CHAT_UI_NOT_TESTED'
        $evidence.Compensation.Status | Should -BeExactly 'NOT_REQUIRED'
    }

    It 'rejects missing reordered duplicated and extra surface evidence' {
        $evidence = New-CddsiBoundAcceptanceEvidenceFixture `
            -Capabilities (New-CddsiAcceptanceCapabilityFixture) `
            -ArtifactSha256 ('a' * 64) `
            -Profile VmAcceptance `
            -ScenarioId strict_surfaces `
            -RunId '00000000-0000-0000-0000-000000000902'

        $reordered = ConvertFrom-CddsiJson -Content (ConvertTo-CddsiJson -InputObject $evidence)
        $reordered.RequestedSurfaces = @('Chat', 'Cowork', 'Code')
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $reordered -ScenarioId strict_surfaces -RunId '00000000-0000-0000-0000-000000000902') | Should -BeFalse

        $duplicate = ConvertFrom-CddsiJson -Content (ConvertTo-CddsiJson -InputObject $evidence)
        $duplicate.Capabilities[2].Surface = 'Code'
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $duplicate -ScenarioId strict_surfaces -RunId '00000000-0000-0000-0000-000000000902') | Should -BeFalse

        $missing = ConvertFrom-CddsiJson -Content (ConvertTo-CddsiJson -InputObject $evidence)
        $missing.Capabilities = @($missing.Capabilities | Select-Object -First 2)
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $missing -ScenarioId strict_surfaces -RunId '00000000-0000-0000-0000-000000000902') | Should -BeFalse

        $extra = ConvertFrom-CddsiJson -Content (ConvertTo-CddsiJson -InputObject $evidence)
        $extra | Add-Member -NotePropertyName CapabilitySelector -NotePropertyValue $true
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $extra -ScenarioId strict_surfaces -RunId '00000000-0000-0000-0000-000000000902') | Should -BeFalse
    }

    It 'maps every non-success readiness family without disabling a requested surface' {
        $pending = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture -Cowork PENDING_RESTART) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId pending_restart -RunId '00000000-0000-0000-0000-000000000903'
        $pending.Run.Status | Should -BeExactly 'RESTART_REQUIRED'

        $partial = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture -Cowork BLOCKED) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId blocked_cowork -RunId '00000000-0000-0000-0000-000000000904'
        $partial.Run.Status | Should -BeExactly 'PARTIAL'
        @($partial.RequestedSurfaces).Count | Should -Be 3

        $action = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture -Chat BLOCKED -Code UNSUPPORTED -Cowork BLOCKED) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId all_blocked -RunId '00000000-0000-0000-0000-000000000905'
        $action.Run.Status | Should -BeExactly 'ACTION_REQUIRED'

        $unknown = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture -Code UNKNOWN) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId unknown_code -RunId '00000000-0000-0000-0000-000000000906'
        $unknown.Run.Status | Should -BeExactly 'ACTION_REQUIRED'

        $cancelled = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId user_cancelled -RunId '00000000-0000-0000-0000-000000000907' -Cancelled
        $cancelled.Run.Status | Should -BeExactly 'CANCELLED'
        $cancelled.Run.Success | Should -BeFalse
    }

    It 'enforces exact blocker reason semantics for capability readiness' {
        $readyWithReason = New-CddsiAcceptanceCapabilityFixture
        $readyWithReason[0].ReasonCodes = @('CHAT_BLOCKER_FORGED')
        { New-CddsiBoundAcceptanceEvidenceFixture -Capabilities $readyWithReason -ScenarioId ready_with_reason -RunId '00000000-0000-0000-0000-000000000913' } | Should -Throw

        $blockedWithoutReason = New-CddsiAcceptanceCapabilityFixture -Code BLOCKED
        $blockedWithoutReason[1].ReasonCodes = @()
        { New-CddsiBoundAcceptanceEvidenceFixture -Capabilities $blockedWithoutReason -ScenarioId blocked_without_reason -RunId '00000000-0000-0000-0000-000000000914' } | Should -Throw

        $reservedReason = New-CddsiAcceptanceCapabilityFixture -Code BLOCKED
        $reservedReason[1].ReasonCodes = @('ALL_SURFACES_ACCEPTED')
        { New-CddsiBoundAcceptanceEvidenceFixture -Capabilities $reservedReason -ScenarioId reserved_reason -RunId '00000000-0000-0000-0000-000000000916' } | Should -Throw
    }

    It 'binds external E2E evidence to artifact profile scenario and runId' {
        $external = New-CddsiExternalE2eEvidenceFixture
        $trusted = Get-CddsiAcceptanceExpectedParameters
        (Test-CddsiExternalE2eEvidence -Evidence $external @trusted) | Should -BeTrue
        $wrongArtifact = Get-CddsiAcceptanceExpectedParameters -ArtifactSha256 ('f' * 64)
        (Test-CddsiExternalE2eEvidence -Evidence $external @wrongArtifact) | Should -BeFalse
        $wrongProfile = Get-CddsiAcceptanceExpectedParameters -Profile UserLive
        (Test-CddsiExternalE2eEvidence -Evidence $external @wrongProfile) | Should -BeFalse
        $wrongScenario = Get-CddsiAcceptanceExpectedParameters -ScenarioId other_scenario
        (Test-CddsiExternalE2eEvidence -Evidence $external @wrongScenario) | Should -BeFalse
        $wrongRun = Get-CddsiAcceptanceExpectedParameters -RunId '00000000-0000-0000-0000-000000000999'
        (Test-CddsiExternalE2eEvidence -Evidence $external @wrongRun) | Should -BeFalse
    }

    It 'rejects future stale non-canonical and cross-environment external evidence' {
        $trusted = Get-CddsiAcceptanceExpectedParameters

        $wrongEnvironment = New-CddsiExternalE2eEvidenceFixture -EnvironmentImageSha256 ('f' * 64)
        (Test-CddsiExternalE2eEvidence -Evidence $wrongEnvironment @trusted) | Should -BeFalse

        $future = New-CddsiExternalE2eEvidenceFixture -ObservedAtUtc '2026-07-14T08:00:00.0000001Z'
        (Test-CddsiExternalE2eEvidence -Evidence $future @trusted) | Should -BeFalse

        $stale = New-CddsiExternalE2eEvidenceFixture -ObservedAtUtc '2026-07-14T07:54:59.9999999Z'
        (Test-CddsiExternalE2eEvidence -Evidence $stale @trusted) | Should -BeFalse

        $nonCanonicalTime = New-CddsiExternalE2eEvidenceFixture -ObservedAtUtc '2026-07-14T07:59:30Z'
        (Test-CddsiExternalE2eEvidence -Evidence $nonCanonicalTime @trusted) | Should -BeFalse

        $nonCanonicalRun = New-CddsiExternalE2eEvidenceFixture -RunId '00000000-0000-0000-0000-00000000090A'
        $nonCanonicalExpected = Get-CddsiAcceptanceExpectedParameters -RunId '00000000-0000-0000-0000-00000000090A'
        (Test-CddsiExternalE2eEvidence -Evidence $nonCanonicalRun @nonCanonicalExpected) | Should -BeFalse
    }

    It 'rejects cross-surface duplicate and previously consumed evidence tokens' {
        $trusted = Get-CddsiAcceptanceExpectedParameters

        $swapped = New-CddsiExternalE2eEvidenceFixture
        $chatToken = $swapped.Surfaces[0].EvidenceToken
        $swapped.Surfaces[0].EvidenceToken = $swapped.Surfaces[1].EvidenceToken
        $swapped.Surfaces[1].EvidenceToken = $chatToken
        (Test-CddsiExternalE2eEvidence -Evidence $swapped @trusted) | Should -BeFalse

        $statusFlip = New-CddsiExternalE2eEvidenceFixture
        $statusFlip.Surfaces[0].Status = 'FAIL'
        (Test-CddsiExternalE2eEvidence -Evidence $statusFlip @trusted) | Should -BeFalse

        $duplicateExpectedTokens = @(
            [pscustomobject]@{ Surface = 'Chat'; Status = 'PASS'; EvidenceToken = ('c' * 64) },
            [pscustomobject]@{ Surface = 'Code'; Status = 'PASS'; EvidenceToken = ('c' * 64) },
            [pscustomobject]@{ Surface = 'Cowork'; Status = 'PASS'; EvidenceToken = ('e' * 64) }
        )
        $duplicateTrusted = Get-CddsiAcceptanceExpectedParameters -SurfaceEvidenceTokens $duplicateExpectedTokens
        (Test-CddsiExternalE2eEvidence -Evidence (New-CddsiExternalE2eEvidenceFixture) @duplicateTrusted) | Should -BeFalse

        $replayedTrusted = Get-CddsiAcceptanceExpectedParameters -PreviouslyConsumedEvidenceTokens @(('d' * 64))
        (Test-CddsiExternalE2eEvidence -Evidence (New-CddsiExternalE2eEvidenceFixture) @replayedTrusted) | Should -BeFalse
    }

    It 'requires all three bound external UI checks before reporting success' {
        $external = New-CddsiExternalE2eEvidenceFixture
        $accepted = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId synthetic_happy_path -RunId '00000000-0000-0000-0000-000000000901' -ExternalE2eEvidence $external
        $accepted.Run.Status | Should -BeExactly 'SUCCEEDED'
        $accepted.Run.Success | Should -BeTrue
        @($accepted.Run.ReasonCodes) | Should -Contain 'ALL_SURFACES_ACCEPTED'

        $partialExternal = New-CddsiExternalE2eEvidenceFixture -Cowork NOT_TESTED
        $partialTokens = @(
            [pscustomobject]@{ Surface = 'Chat'; Status = 'PASS'; EvidenceToken = ('c' * 64) },
            [pscustomobject]@{ Surface = 'Code'; Status = 'PASS'; EvidenceToken = ('d' * 64) },
            [pscustomobject]@{ Surface = 'Cowork'; Status = 'NOT_TESTED'; EvidenceToken = $null }
        )
        $partial = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId synthetic_happy_path -RunId '00000000-0000-0000-0000-000000000901' -SurfaceEvidenceTokens $partialTokens -ExternalE2eEvidence $partialExternal
        $partial.Run.Status | Should -BeExactly 'PARTIAL'
        $partial.Run.Success | Should -BeFalse
        @($partial.Run.ReasonCodes) | Should -Contain 'COWORK_UI_NOT_TESTED'
    }

    It 'requires trusted expected inputs when revalidating accepted evidence' {
        $external = New-CddsiExternalE2eEvidenceFixture
        $accepted = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ExternalE2eEvidence $external
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $accepted) | Should -BeTrue

        $wrongEnvironment = Get-CddsiAcceptanceExpectedParameters -EnvironmentImageSha256 ('f' * 64)
        (Test-CddsiAcceptanceEvidence -Evidence $accepted -ExpectedCapabilities (New-CddsiAcceptanceCapabilityFixture) @wrongEnvironment) | Should -BeFalse

        $replayed = Get-CddsiAcceptanceExpectedParameters -PreviouslyConsumedEvidenceTokens @(('c' * 64))
        (Test-CddsiAcceptanceEvidence -Evidence $accepted -ExpectedCapabilities (New-CddsiAcceptanceCapabilityFixture) @replayed) | Should -BeFalse

        $crossSurface = ConvertFrom-CddsiJson -Content (ConvertTo-CddsiJson -InputObject $accepted)
        $crossSurface.UiEvidence[0].EvidenceToken = ('d' * 64)
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $crossSurface) | Should -BeFalse

        $trustedBlockedCapabilities = New-CddsiAcceptanceCapabilityFixture -Code BLOCKED
        (Test-CddsiBoundAcceptanceEvidenceFixture -Evidence $accepted -ExpectedCapabilities $trustedBlockedCapabilities) | Should -BeFalse
    }

    It 'rejects malformed external UI evidence and propagates an external FAIL' {
        $trusted = Get-CddsiAcceptanceExpectedParameters
        $missingToken = New-CddsiExternalE2eEvidenceFixture
        $missingToken.Surfaces[0].EvidenceToken = $null
        (Test-CddsiExternalE2eEvidence -Evidence $missingToken @trusted) | Should -BeFalse

        $extraField = New-CddsiExternalE2eEvidenceFixture
        $extraField.Surfaces[0] | Add-Member -NotePropertyName ScreenshotPath -NotePropertyValue 'C:\synthetic\screen.png'
        (Test-CddsiExternalE2eEvidence -Evidence $extraField @trusted) | Should -BeFalse

        $failedExternal = New-CddsiExternalE2eEvidenceFixture -Cowork FAIL
        $failedTokens = @(
            [pscustomobject]@{ Surface = 'Chat'; Status = 'PASS'; EvidenceToken = ('c' * 64) },
            [pscustomobject]@{ Surface = 'Code'; Status = 'PASS'; EvidenceToken = ('d' * 64) },
            [pscustomobject]@{ Surface = 'Cowork'; Status = 'FAIL'; EvidenceToken = ('e' * 64) }
        )
        $evidence = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId synthetic_happy_path -RunId '00000000-0000-0000-0000-000000000901' -SurfaceEvidenceTokens $failedTokens -ExternalE2eEvidence $failedExternal
        $evidence.Run.Status | Should -BeExactly 'FAILED'
        $evidence.Run.Success | Should -BeFalse
        @($evidence.Run.ReasonCodes) | Should -Contain 'COWORK_UI_FAILED'
    }

    It 'reduces resource compensation without treating the whole machine as one transaction' {
        (Resolve-CddsiCompensationStatus).Status | Should -BeExactly 'NOT_REQUIRED'

        $projectFull = [pscustomobject][ordered]@{ ResourceId = 'managed_policy'; Ownership = 'PROJECT'; Mutation = 'UPDATED'; Status = 'FULL'; ReasonCode = 'RESTORED_EXACT' }
        $sharedUnsupported = [pscustomobject][ordered]@{ ResourceId = 'git_upgrade'; Ownership = 'SHARED'; Mutation = 'UPDATED'; Status = 'UNSUPPORTED'; ReasonCode = 'NO_DOWNGRADE' }
        $reduced = Resolve-CddsiCompensationStatus -Resources @($projectFull, $sharedUnsupported)
        $reduced.Status | Should -BeExactly 'UNSUPPORTED'
        $reduced.ChangedResourceCount | Should -Be 2
        $reduced.FailedResourceCount | Should -Be 0

        $projectPartial = [pscustomobject][ordered]@{ ResourceId = 'credential_blob'; Ownership = 'PROJECT'; Mutation = 'UPDATED'; Status = 'PARTIAL'; ReasonCode = 'PARTIAL_RESTORE' }
        { Resolve-CddsiCompensationStatus -Resources @($projectPartial) } | Should -Throw

        $unknownNonFailure = [pscustomobject][ordered]@{ ResourceId = 'policy_unknown'; Ownership = 'PROJECT'; Mutation = 'UNKNOWN'; Status = 'FULL'; ReasonCode = 'UNKNOWN_CHANGE' }
        { Resolve-CddsiCompensationStatus -Resources @($unknownNonFailure) } | Should -Throw
    }

    It 'elevates failed or partial compensation into stable non-success runtime states' {
        $failedResource = [pscustomobject][ordered]@{ ResourceId = 'managed_policy'; Ownership = 'PROJECT'; Mutation = 'UPDATED'; Status = 'FAILED'; ReasonCode = 'RESTORE_FAILED' }
        $failed = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId compensation_failed -RunId '00000000-0000-0000-0000-000000000908' -CompensationResources @($failedResource)
        $failed.Run.Status | Should -BeExactly 'FAILED'

        $partialResource = [pscustomobject][ordered]@{ ResourceId = 'desktop_upgrade'; Ownership = 'SHARED'; Mutation = 'UPDATED'; Status = 'PARTIAL'; ReasonCode = 'NO_AUTOMATIC_DOWNGRADE' }
        $partial = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId compensation_partial -RunId '00000000-0000-0000-0000-000000000909' -CompensationResources @($partialResource)
        $partial.Run.Status | Should -BeExactly 'PARTIAL'
    }

    It 'allows success only with complete UI evidence and acceptable compensation' {
        $external = New-CddsiExternalE2eEvidenceFixture -ScenarioId compensation_full -RunId '00000000-0000-0000-0000-000000000915'
        $fullResource = [pscustomobject][ordered]@{ ResourceId = 'managed_policy'; Ownership = 'PROJECT'; Mutation = 'UPDATED'; Status = 'FULL'; ReasonCode = 'RESTORED_EXACT' }
        $full = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ScenarioId compensation_full -RunId '00000000-0000-0000-0000-000000000915' -ExternalE2eEvidence $external -CompensationResources @($fullResource)
        $full.Compensation.Status | Should -BeExactly 'FULL'
        $full.Run.Status | Should -BeExactly 'SUCCEEDED'

        $unsupportedResource = [pscustomobject][ordered]@{ ResourceId = 'git_upgrade'; Ownership = 'SHARED'; Mutation = 'UPDATED'; Status = 'UNSUPPORTED'; ReasonCode = 'NO_DOWNGRADE' }
        $unsupported = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ScenarioId compensation_full -RunId '00000000-0000-0000-0000-000000000915' -ExternalE2eEvidence $external -CompensationResources @($unsupportedResource)
        $unsupported.Run.Status | Should -BeExactly 'PARTIAL'
        $unsupported.Run.Success | Should -BeFalse
    }

    It 'keeps per-surface synthetic checks free of UI API process and mutations' {
        $context = New-CddsiTestExecutionContext -RunId '00000000-0000-0000-0000-000000000910'
        $chat = Test-CddsiChatAcceptance -ExecutionContext $context -CapabilityStatus READY -UiStatus PASS
        $chatNotTested = Test-CddsiChatAcceptance -ExecutionContext $context -CapabilityStatus READY -UiStatus NOT_TESTED
        $code = Test-CddsiCodeAcceptance -ExecutionContext $context -CapabilityStatus BLOCKED -UiStatus NOT_TESTED
        $cowork = Test-CddsiCoworkAcceptance -ExecutionContext $context -CapabilityStatus PENDING_RESTART -UiStatus NOT_TESTED

        $chat.Status | Should -BeExactly 'SUCCEEDED'
        $chatNotTested.Status | Should -BeExactly 'ACTION_REQUIRED'
        $chatNotTested.ErrorCode | Should -BeExactly 'CHAT_UI_NOT_TESTED'
        $code.Status | Should -BeExactly 'ACTION_REQUIRED'
        $cowork.Status | Should -BeExactly 'RESTART_REQUIRED'
        foreach ($result in @($chat, $chatNotTested, $code, $cowork)) {
            $result.Changed | Should -BeFalse
            $result.Data.RealUiExecuted | Should -BeFalse
            $result.Data.ApiRequestSent | Should -BeFalse
            $result.Data.ProcessStarted | Should -BeFalse
        }
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $context) | Should -BeTrue
    }

    It 'orchestrates only validated synthetic evidence and never promotes absent evidence' {
        $context = New-CddsiTestExecutionContext -RunId '00000000-0000-0000-0000-000000000911'
        $missing = Invoke-CddsiDesktopAcceptance -ExecutionContext $context -Mode TestSafe
        $missing.Status | Should -BeExactly 'ACTION_REQUIRED'

        $external = New-CddsiExternalE2eEvidenceFixture -ScenarioId orchestrated -RunId '00000000-0000-0000-0000-000000000911'
        $trusted = Get-CddsiAcceptanceExpectedParameters -ScenarioId orchestrated -RunId '00000000-0000-0000-0000-000000000911'
        $evidence = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile VmAcceptance -ScenarioId orchestrated -RunId '00000000-0000-0000-0000-000000000911' -ExternalE2eEvidence $external
        { Invoke-CddsiDesktopAcceptance -ExecutionContext $context -Mode TestSafe -AcceptanceEvidence $evidence } | Should -Throw
        $result = Invoke-CddsiDesktopAcceptance -ExecutionContext $context -Mode TestSafe -AcceptanceEvidence $evidence -ExpectedCapabilities (New-CddsiAcceptanceCapabilityFixture) @trusted
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Changed | Should -BeFalse
        $result.Data.Run.Success | Should -BeTrue
        Assert-CddsiFakeProviderExpectations -ExecutionContext $context -RequireNoMutations | Should -BeTrue
        Assert-CddsiIsolationEvidence -Evidence (Get-CddsiIsolationEvidence -ExecutionContext $context) | Should -BeTrue

        $replayed = Get-CddsiAcceptanceExpectedParameters -ScenarioId orchestrated -RunId '00000000-0000-0000-0000-000000000911' -PreviouslyConsumedEvidenceTokens @(('e' * 64))
        { Invoke-CddsiDesktopAcceptance -ExecutionContext $context -Mode TestSafe -AcceptanceEvidence $evidence -ExpectedCapabilities (New-CddsiAcceptanceCapabilityFixture) @replayed } | Should -Throw
    }

    It 'generates only in-memory redacted reports with fixed-surface summaries' {
        $external = New-CddsiExternalE2eEvidenceFixture -Profile UserLive -ScenarioId report_synthetic -RunId '00000000-0000-0000-0000-000000000912'
        $trusted = Get-CddsiAcceptanceExpectedParameters -Profile UserLive -ScenarioId report_synthetic -RunId '00000000-0000-0000-0000-000000000912'
        $evidence = New-CddsiBoundAcceptanceEvidenceFixture -Capabilities (New-CddsiAcceptanceCapabilityFixture) -ArtifactSha256 ('a' * 64) -Profile UserLive -ScenarioId report_synthetic -RunId '00000000-0000-0000-0000-000000000912' -ExternalE2eEvidence $external
        { New-CddsiAcceptanceReport -Results $evidence -PathTokenValues ([ordered]@{}) } | Should -Throw
        $report = New-CddsiAcceptanceReport -Results $evidence -PathTokenValues ([ordered]@{ '%LOCALAPPDATA%' = 'C:\SyntheticProfile\AppData\Local'; '%USERPROFILE%' = 'C:\SyntheticProfile'; '%USERNAME%' = 'SyntheticUser'; '%TEMP%' = 'C:\SyntheticTemp' }) -ExpectedCapabilities (New-CddsiAcceptanceCapabilityFixture) @trusted
        $report.schemaVersion | Should -Be 1
        $report.language | Should -BeExactly 'zh-CN'
        $report.redacted | Should -BeTrue
        $report.persisted | Should -BeFalse
        $report.runtimeStatus | Should -BeExactly 'SUCCEEDED'
        @($report.requestedSurfaces) -join '|' | Should -BeExactly 'Chat|Code|Cowork'

        $token = 'sk-' + ('Z' * 24)
        $generic = [pscustomobject]@{ Status = 'SUCCEEDED'; Success = $true; path = 'C:\SyntheticProfile\secret.txt'; user = 'SyntheticUser'; authorization = $token }
        $safe = New-CddsiAcceptanceReport -Results $generic -PathTokenValues ([ordered]@{ '%LOCALAPPDATA%' = 'C:\SyntheticProfile\AppData\Local'; '%USERPROFILE%' = 'C:\SyntheticProfile'; '%USERNAME%' = 'SyntheticUser'; '%TEMP%' = 'C:\SyntheticTemp' })
        $safe.success | Should -BeFalse
        $safe.content | Should -Not -Match ([regex]::Escape($token))
        $safe.content | Should -Not -Match 'SyntheticUser'
        $safe.content | Should -Not -Match ([regex]::Escape('C:\SyntheticProfile'))
        $safe.content | Should -Match '%USERPROFILE%'
    }
}
