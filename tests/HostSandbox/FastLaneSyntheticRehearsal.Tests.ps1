BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\common.ps1')
    . (Join-Path $script:RepoRoot 'lib\vm-test-relay.ps1')
    . (Join-Path $script:RepoRoot 'operator\fast-lane\invoke-synthetic-rehearsal.ps1')
}

Describe 'P10A-0A fully synthetic Fast Lane rehearsal' {
    It 'exercises both directional outboxes and fail-closed relay behavior without product Live' {
        $root = Join-Path $TestDrive 'cddsi-fastlane-synthetic-96000000-0000-4000-8000-000000000001'
        $evidence = Invoke-CddsiFastLaneSyntheticRehearsal -Mode TestSafe -SandboxRoot $root

        $evidence.Summary.OverallStatus | Should -BeExactly 'PASS'
        $evidence.Summary.ExpectationCount | Should -Be 7
        $evidence.Summary.ExpectationFailedCount | Should -Be 0
        @($evidence.Cases.Name) | Should -Contain 'duplicate_message'
        @($evidence.Cases.Name) | Should -Contain 'stale_message'
        @($evidence.Cases.Name) | Should -Contain 'tampered_payload'
        @($evidence.Cases.Name) | Should -Contain 'wrong_direction'
        @($evidence.Cases.Name) | Should -Contain 'stop_closes_cycle'
        (@($evidence.Cases | Where-Object Name -eq 'post_stop_continuation')[0]).ErrorCode |
            Should -BeExactly 'CYCLE_CLOSED'
        (@($evidence.Cases | Where-Object Name -eq 'duplicate_message')[0]).ErrorCode |
            Should -BeExactly 'MESSAGE_REPLAY'

        @($evidence.Outboxes.Name) -join '|' | Should -BeExactly 'host-to-vm|vm-to-host'
        ($evidence.Outboxes | Measure-Object -Property MessageCount -Sum).Sum | Should -BeGreaterThan 2
        $evidence.ProductChanged | Should -BeFalse
        $evidence.ProductLiveOperationCount | Should -Be 0
        $evidence.NetworkAccessCount | Should -Be 0
        $evidence.GitInvocationCount | Should -Be 0
        $evidence.RealSystemProbeCount | Should -Be 0
        $evidence.SecretFindingCount | Should -Be 0

        $evidencePath = Join-Path $root 'evidence\rehearsal.json'
        $bytes = [IO.File]::ReadAllBytes($evidencePath)
        ($bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) | Should -BeFalse
        $text = [Text.Encoding]::UTF8.GetString($bytes)
        $text.EndsWith("`n") | Should -BeTrue
        $parsed = $text.TrimEnd("`n") | ConvertFrom-Json
        $parsed.EvidenceSha256 | Should -BeExactly $evidence.EvidenceSha256
        (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $parsed) + "`n" | Should -BeExactly $text
    }

    It 'is deterministic across caller-owned roots and has no Live mode' {
        $firstRoot = Join-Path $TestDrive 'cddsi-fastlane-synthetic-96000000-0000-4000-8000-000000000002'
        $secondRoot = Join-Path $TestDrive 'cddsi-fastlane-synthetic-96000000-0000-4000-8000-000000000003'
        $first = Invoke-CddsiFastLaneSyntheticRehearsal -Mode DryRun -SandboxRoot $firstRoot
        $second = Invoke-CddsiFastLaneSyntheticRehearsal -Mode DryRun -SandboxRoot $secondRoot
        (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $first) |
            Should -BeExactly (ConvertTo-CddsiVmTestRelayCanonicalJson -Value $second)
        { Invoke-CddsiFastLaneSyntheticRehearsal -Mode Live -SandboxRoot (Join-Path $TestDrive 'unused') } |
            Should -Throw
    }
}
