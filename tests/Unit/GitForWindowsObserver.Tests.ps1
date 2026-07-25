BeforeAll {
    $script:RepoRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
    . (Join-Path $script:RepoRoot 'tests\Support\TestContext.ps1')

    function New-CddsiObserverProbeResult {
        param(
            [bool]$Started = $true,
            [bool]$TimedOut = $false,
            [bool]$TerminationComplete = $true,
            [bool]$OutputTruncated = $false,
            [AllowNull()][object]$ExitCode = 0,
            [string]$StdOut = "git version 2.55.0.windows.3`r`n",
            [string]$StdErr = ''
        )
        return [pscustomobject][ordered]@{
            SchemaVersion = 1
            Started = $Started
            TimedOut = $TimedOut
            TerminationComplete = $TerminationComplete
            OutputTruncated = $OutputTruncated
            ExitCode = $ExitCode
            StdOut = $StdOut
            StdErr = $StdErr
        }
    }

    function New-CddsiObserverPeBytes {
        param([ValidateSet('x64', 'x86', 'arm64')][string]$Machine = 'x64')
        $bytes = New-Object byte[] 512
        $bytes[0] = 0x4d
        $bytes[1] = 0x5a
        [BitConverter]::GetBytes([int]0x80).CopyTo($bytes, 0x3c)
        [BitConverter]::GetBytes([uint32]0x00004550).CopyTo($bytes, 0x80)
        $machineValue = switch ($Machine) {
            'x64' { [uint16]0x8664 }
            'x86' { [uint16]0x014c }
            'arm64' { [uint16]0xaa64 }
        }
        [BitConverter]::GetBytes($machineValue).CopyTo($bytes, 0x84)
        return $bytes
    }

    function New-CddsiObserverIdentityResult {
        param([string]$ExecutablePath, [string]$IdentityStatus = 'Trusted')
        $pathToken = Get-CddsiPathBindingToken -Path $ExecutablePath
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsExecutable' -Status SUCCEEDED -Mode Live -Data ([pscustomobject][ordered]@{
            SchemaVersion = 3
            PathBindingToken = $pathToken
            FileIdentityToken = ('f' * 64)
            InstallRootBindingToken = ('b' * 64)
            CorePathBindingToken = ('c' * 64)
            HttpsPathBindingToken = ('d' * 64)
            DependencyIdentityToken = ('e' * 64)
            DependencyCount = 5
            ArtifactSha256 = ('a' * 64)
            ArtifactSizeBytes = [long]512
            FileVersion = '2.55.0.windows.3'
            PeMachine = 'x64'
            AuthenticodeStatus = 'Valid'
            SignerThumbprint = ('1' * 40)
            SignerSubjectToken = '<SIGNER_SUBJECT:GIT_FOR_WINDOWS_JOHANNES_SCHINDELIN>'
            PublisherToken = '<PUBLISHER:GIT_DEVELOPMENT_COMMUNITY>'
            IdentityToken = if ($IdentityStatus -ceq 'Trusted') { '<IDENTITY:GIT_FOR_WINDOWS_X64_PROTECTED_BUNDLE>' } else { $null }
            IdentityStatus = $IdentityStatus
            ProtectionStatus = if ($IdentityStatus -ceq 'Trusted') { 'Protected' } else { 'Untrusted' }
            RegistryStatus = if ($IdentityStatus -ceq 'Trusted') { 'Trusted' } else { 'Unknown' }
            ComponentCount = if ($IdentityStatus -ceq 'Trusted') { 3 } else { 0 }
            ReasonCodes = if ($IdentityStatus -ceq 'Trusted') { @() } else { @('GIT_SIGNER_UNTRUSTED') }
        })
    }

    function New-CddsiObserverComponentResult {
        param(
            [Parameter(Mandatory = $true)][string]$ComponentPath,
            [Parameter(Mandatory = $true)][ValidateSet('PathLauncher', 'Core', 'HttpsTransport')][string]$ComponentRole,
            [string]$IdentityStatus = 'Trusted',
            [string]$FileVersion = '2.55.0.windows.3'
        )
        $roleMarker = switch ($ComponentRole) {
            'PathLauncher' { '1' }
            'Core' { '2' }
            'HttpsTransport' { '3' }
        }
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsSignedComponent' -Status SUCCEEDED -Mode Live -Data ([pscustomobject][ordered]@{
            SchemaVersion = 1
            ComponentRole = $ComponentRole
            PathBindingToken = Get-CddsiPathBindingToken -Path $ComponentPath
            FileIdentityToken = ($roleMarker * 64)
            ArtifactSha256 = ($roleMarker * 64)
            ArtifactSizeBytes = [long]4096
            FileVersion = $FileVersion
            PeMachine = 'x64'
            AuthenticodeStatus = 'Valid'
            SignerThumbprint = ('a' * 40)
            IdentityStatus = $IdentityStatus
            ReasonCodes = if ($IdentityStatus -ceq 'Trusted') { @() } else { @('GIT_COMPONENT_SIGNER_UNTRUSTED') }
        })
    }

    function New-CddsiObserverProtectionResult {
        param(
            [Parameter(Mandatory = $true)][string]$InstallRoot,
            [string]$ProtectionStatus = 'Protected'
        )
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsInstallProtection' -Status SUCCEEDED -Mode Live -Data ([pscustomobject][ordered]@{
            SchemaVersion = 1
            ProtectionStatus = $ProtectionStatus
            InstallRootBindingToken = if ($ProtectionStatus -ceq 'Protected') {
                Get-CddsiPathBindingToken -Path $InstallRoot
            } else {
                $null
            }
            RequiredPathCount = if ($ProtectionStatus -ceq 'Protected') { 10 } else { 0 }
            ReasonCodes = if ($ProtectionStatus -ceq 'Protected') { @() } else { @('GIT_INSTALL_USER_WRITABLE') }
        })
    }

    function New-CddsiObserverRegistryResult {
        param(
            [Parameter(Mandatory = $true)][string]$InstallRoot,
            [string]$RegistryStatus = 'Trusted',
            [string]$CurrentVersion = '2.55.0.3'
        )
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsRegistry' -Status SUCCEEDED -Mode Live -Data ([pscustomobject][ordered]@{
            SchemaVersion = 1
            RegistryStatus = $RegistryStatus
            InstallRootBindingToken = if ($RegistryStatus -ceq 'Trusted') {
                Get-CddsiPathBindingToken -Path $InstallRoot
            } else {
                $null
            }
            RegistryIdentityToken = if ($RegistryStatus -ceq 'Trusted') {
                'e' * 64
            } else {
                $null
            }
            CurrentVersion = if ($RegistryStatus -ceq 'Trusted') { $CurrentVersion } else { $null }
            ReasonCodes = if ($RegistryStatus -ceq 'Trusted') { @() } else { @('GIT_INSTALL_REGISTRY_PATH_MISMATCH') }
        })
    }

    function New-CddsiObserverPrivateDllResult {
        param(
            [string]$IdentityStatus = 'Trusted',
            [string]$DependencyIdentityToken = ('9' * 64),
            [int]$DependencyCount = 5
        )
        return New-CddsiOperationResult -Operation 'ObserveGitForWindowsPrivateDlls' -Status SUCCEEDED -Mode Live -Data ([pscustomobject][ordered]@{
            SchemaVersion = 1
            IdentityStatus = $IdentityStatus
            DependencyIdentityToken = if ($IdentityStatus -ceq 'Trusted') { $DependencyIdentityToken } else { $null }
            DependencyCount = if ($IdentityStatus -ceq 'Trusted') { $DependencyCount } else { 0 }
            ReasonCodes = if ($IdentityStatus -ceq 'Trusted') { @() } else { @('GIT_PRIVATE_DLL_REQUIRED_MISSING') }
        })
    }

    function New-CddsiObserverProbeSuccess {
        return New-CddsiOperationResult -Operation 'ProbeGitForWindowsVersion' -Status SUCCEEDED -Mode Live -Data ([pscustomobject][ordered]@{
            SchemaVersion = 1
            Valid = $true
            ReasonCode = $null
            Version = '2.55.0.windows.3'
            ComparisonVersion = '2.55.0.3'
            WindowsRevision = 3
        })
    }
}

Describe 'D-027 native Windows client platform boundary' {
    It 'locks the native AMD64 workstation proof conditions into the implementation' {
        $source = [System.IO.File]::ReadAllText(
            (Join-Path $script:RepoRoot 'lib\git-for-windows.ps1')
        )
        $source | Should -Match 'IsWow64Process2'
        $source | Should -Match 'IMAGE_FILE_MACHINE_AMD64\s*=\s*0x8664'
        $source | Should -Match 'RtlGetVersion'
        $source | Should -Match 'VER_NT_WORKSTATION\s*=\s*1'
    }

    It 'fails the Live assertion closed when native platform proof is unavailable' {
        Mock Test-CddsiD027Windows11X64Platform { return $false }
        $context = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = $TestDrive }
        }

        { Assert-CddsiD027GitLiveContext -ExecutionContext $context } |
            Should -Throw '*Windows 11 x64*'
    }

    It 'rejects a missing product temp before any Live observer work' {
        $context = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = (Join-Path $TestDrive 'missing-product-temp') }
        }

        { Assert-CddsiD027GitLiveContext -ExecutionContext $context } |
            Should -Throw '*explicit local product temp path*'
    }
}

Describe 'D-027 Git for Windows version and PE parsing' {
    It 'maps windows.1 and later revisions to exact installer receipt versions' {
        (ConvertTo-CddsiGitInstallerReceiptVersion -GitVersion '2.54.0.windows.1') |
            Should -BeExactly '2.54.0'
        (ConvertTo-CddsiGitInstallerReceiptVersion -GitVersion '2.55.0.windows.3') |
            Should -BeExactly '2.55.0.3'
        { ConvertTo-CddsiGitInstallerReceiptVersion -GitVersion '2.55.0' } |
            Should -Throw '*exact Git for Windows version*'
    }

    It 'parses only the exact Git for Windows version line' {
        $parsed = ConvertFrom-CddsiGitVersionProbeResult -ProbeResult (New-CddsiObserverProbeResult)
        $parsed.Valid | Should -BeTrue
        $parsed.Version | Should -BeExactly '2.55.0.windows.3'
        $parsed.ComparisonVersion | Should -BeExactly '2.55.0.3'
        $parsed.WindowsRevision | Should -Be 3

        foreach ($stdout in @(
            'git version 2.55.0',
            "git version 2.55.0.windows.3`r`nsecond line",
            ' git version 2.55.0.windows.3',
            'git version 02.55.0.windows.3'
        )) {
            $rejected = ConvertFrom-CddsiGitVersionProbeResult -ProbeResult (New-CddsiObserverProbeResult -StdOut $stdout)
            $rejected.Valid | Should -BeFalse
            $rejected.ReasonCode | Should -BeExactly 'GIT_VERSION_OUTPUT_INVALID'
            ($rejected | ConvertTo-Json -Compress) | Should -Not -Match 'second line'
        }
    }

    It 'maps timeout incomplete termination truncation nonzero and stderr to stable safe reasons' {
        $cases = @(
            [pscustomobject]@{ Result = New-CddsiObserverProbeResult -Started $false; Reason = 'GIT_VERSION_PROBE_NOT_STARTED' }
            [pscustomobject]@{ Result = New-CddsiObserverProbeResult -TimedOut $true -ExitCode $null; Reason = 'GIT_VERSION_PROBE_TIMEOUT' }
            [pscustomobject]@{ Result = New-CddsiObserverProbeResult -TerminationComplete $false; Reason = 'GIT_VERSION_PROBE_TERMINATION_INCOMPLETE' }
            [pscustomobject]@{ Result = New-CddsiObserverProbeResult -OutputTruncated $true -ExitCode $null -StdOut ('x' * 128); Reason = 'GIT_VERSION_OUTPUT_LIMIT_EXCEEDED' }
            [pscustomobject]@{ Result = New-CddsiObserverProbeResult -ExitCode 7; Reason = 'GIT_VERSION_PROBE_NONZERO' }
            [pscustomobject]@{ Result = New-CddsiObserverProbeResult -StdErr 'C:\unsafe\sentinel'; Reason = 'GIT_VERSION_PROBE_STDERR' }
        )
        foreach ($case in $cases) {
            $parsed = ConvertFrom-CddsiGitVersionProbeResult -ProbeResult $case.Result
            $parsed.Valid | Should -BeFalse
            $parsed.ReasonCode | Should -BeExactly $case.Reason
            ($parsed | ConvertTo-Json -Compress) | Should -Not -Match 'unsafe|sentinel'
        }
    }

    It 'requires the exact bounded-output probe schema' {
        $missingTruncationField = [pscustomobject][ordered]@{
            SchemaVersion = 1
            Started = $true
            TimedOut = $false
            TerminationComplete = $true
            ExitCode = 0
            StdOut = "git version 2.55.0.windows.3`r`n"
            StdErr = ''
        }
        { ConvertFrom-CddsiGitVersionProbeResult -ProbeResult $missingTruncationField } |
            Should -Throw '*exact schema*'

        { ConvertFrom-CddsiGitVersionProbeResult -ProbeResult (
            New-CddsiObserverProbeResult -OutputTruncated ([bool]$false)
        ) } | Should -Not -Throw
    }

    It 'recognizes x64 and rejects other or malformed PE headers' {
        foreach ($machine in @('x64', 'x86', 'arm64')) {
            $bytes = New-CddsiObserverPeBytes -Machine $machine
            (ConvertFrom-CddsiGitPeHeader -HeaderBytes $bytes -ImageLength $bytes.Length) | Should -BeExactly $machine
        }
        $badMz = New-CddsiObserverPeBytes
        $badMz[0] = 0
        (ConvertFrom-CddsiGitPeHeader -HeaderBytes $badMz -ImageLength $badMz.Length) | Should -BeExactly 'Invalid'
        $badOffset = New-CddsiObserverPeBytes
        [BitConverter]::GetBytes([int]4090).CopyTo($badOffset, 0x3c)
        (ConvertFrom-CddsiGitPeHeader -HeaderBytes $badOffset -ImageLength $badOffset.Length) | Should -BeExactly 'Invalid'
    }
}

Describe 'D-027 Git PATH and process isolation plans' {
    It 'deduplicates one canonical executable and fails closed for missing ambiguity shadow and invalid paths' {
        $missing = Resolve-CddsiGitExecutablePathSet -CandidatePaths @() -ShadowPaths @()
        $missing.Status | Should -BeExactly 'MISSING'
        @($missing.ReasonCodes) | Should -Contain 'GIT_MISSING'

        $one = Resolve-CddsiGitExecutablePathSet -CandidatePaths @(
            'C:\Tools\Git\git.exe',
            'c:\tools\git\.\GIT.EXE'
        ) -ShadowPaths @()
        $one.Status | Should -BeExactly 'READY'
        $one.CandidateCount | Should -Be 1

        $ambiguous = Resolve-CddsiGitExecutablePathSet -CandidatePaths @(
            'C:\Tools\Git\git.exe',
            'D:\Other\Git\git.exe'
        ) -ShadowPaths @()
        $ambiguous.Status | Should -BeExactly 'AMBIGUOUS'
        @($ambiguous.ReasonCodes) | Should -Contain 'GIT_PATH_AMBIGUOUS'

        $shadowed = Resolve-CddsiGitExecutablePathSet -CandidatePaths @('C:\Tools\Git\git.exe') -ShadowPaths @('C:\Tools\Git\git.cmd')
        $shadowed.Status | Should -BeExactly 'SHADOWED'
        @($shadowed.ReasonCodes) | Should -Contain 'GIT_PATH_SHADOWED'

        foreach ($invalid in @('git.exe', '\\server\share\git.exe', '\\?\C:\Tools\git.exe')) {
            (Resolve-CddsiGitExecutablePathSet -CandidatePaths @($invalid) -ShadowPaths @()).Status | Should -BeExactly 'INVALID'
        }
    }

    It 'builds an exact absolute no-shell core probe with a cleared allowlisted environment' {
        $startInfo = New-CddsiGitVersionProbeStartInfo `
            -ExecutablePath 'C:\Program Files\Git\mingw64\bin\git.exe' `
            -SystemRootPath 'C:\Windows' `
            -ProductTempPath 'C:\CDDsi\owned-temp'
        $startInfo.FileName | Should -BeExactly 'C:\Program Files\Git\mingw64\bin\git.exe'
        $startInfo.Arguments | Should -BeExactly '--version'
        $startInfo.WorkingDirectory | Should -BeExactly 'C:\Program Files\Git\mingw64\bin'
        $startInfo.UseShellExecute | Should -BeFalse
        $startInfo.CreateNoWindow | Should -BeTrue
        $startInfo.LoadUserProfile | Should -BeFalse
        $startInfo.RedirectStandardInput | Should -BeTrue
        $startInfo.RedirectStandardOutput | Should -BeTrue
        $startInfo.RedirectStandardError | Should -BeTrue
        $startInfo.StandardOutputEncoding.WebName | Should -BeExactly 'utf-8'
        $startInfo.StandardOutputEncoding.GetPreamble().Length | Should -Be 0
        $startInfo.StandardErrorEncoding.WebName | Should -BeExactly 'utf-8'

        $expectedNames = @(
            'ComSpec', 'GCM_INTERACTIVE', 'GIT_CONFIG_COUNT', 'GIT_CONFIG_GLOBAL',
            'GIT_CONFIG_NOSYSTEM', 'GIT_CONFIG_SYSTEM', 'GIT_TERMINAL_PROMPT',
            'HOME', 'LC_ALL', 'SystemRoot', 'TEMP', 'TMP', 'USERPROFILE', 'WINDIR',
            'XDG_CONFIG_HOME'
        ) | Sort-Object
        @($startInfo.EnvironmentVariables.Keys | ForEach-Object { [string]$_ } | Sort-Object) |
            Should -Be $expectedNames
        $startInfo.EnvironmentVariables['GIT_CONFIG_NOSYSTEM'] | Should -BeExactly '1'
        $startInfo.EnvironmentVariables['GIT_CONFIG_SYSTEM'] | Should -BeExactly 'NUL'
        $startInfo.EnvironmentVariables['GIT_CONFIG_GLOBAL'] | Should -BeExactly 'NUL'
        $startInfo.EnvironmentVariables['GCM_INTERACTIVE'] | Should -BeExactly 'Never'
        $startInfo.EnvironmentVariables['HOME'] | Should -BeExactly 'C:\CDDsi\owned-temp'
        $startInfo.EnvironmentVariables['TEMP'] | Should -BeExactly 'C:\CDDsi\owned-temp'
        @($startInfo.EnvironmentVariables.Keys) | Should -Not -Contain 'PATH'
        @($startInfo.EnvironmentVariables.Keys) | Should -Not -Contain 'PATHEXT'
    }
}

Describe 'D-027 protected Git private DLL identity' {
    BeforeEach {
        Mock Assert-CddsiD027GitLiveContext { return $true }
        $script:dllContext = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = $TestDrive }
        }
        $script:dllBin = Join-Path (
            [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
        ) 'Git\mingw64\bin'
        $script:dllNames = @(
            'libiconv-2.dll',
            'libintl-8.dll',
            'libpcre2-8-0.dll',
            'libwinpthread-1.dll',
            'zlib1.dll'
        )
        $script:dllPaths = @(
            $script:dllNames | ForEach-Object { Join-Path $script:dllBin $_ }
        )
        Mock Get-ChildItem {
            $items = @(
                $script:dllPaths | ForEach-Object {
                    [pscustomobject]@{ FullName = $_ }
                }
            )
            [array]::Reverse($items)
            return $items
        } -ParameterFilter {
            $LiteralPath -eq $script:dllBin -and $Filter -eq '*.dll'
        }
        Mock Get-Item {
            return [pscustomobject]@{
                PSIsContainer = $false
                Length = [long]4096
                Attributes = [System.IO.FileAttributes]::Normal
            }
        }
        Mock Get-FileHash {
            return [pscustomobject]@{
                Hash = Get-CddsiSupplyChainTextBindingToken -Text ([string]$LiteralPath)
            }
        }
    }

    It 'binds the exact required DLL set independent of enumeration order without returning paths' {
        $first = Get-CddsiGitForWindowsPrivateDllObservation `
            -ExecutionContext $script:dllContext `
            -BinPath $script:dllBin `
            -ExpectedPaths $script:dllPaths
        $second = Get-CddsiGitForWindowsPrivateDllObservation `
            -ExecutionContext $script:dllContext `
            -BinPath $script:dllBin `
            -ExpectedPaths @($script:dllPaths[4..0])

        $first.Status | Should -BeExactly 'SUCCEEDED'
        $first.Data.IdentityStatus | Should -BeExactly 'Trusted'
        $first.Data.DependencyCount | Should -Be 5
        $first.Data.DependencyIdentityToken | Should -Match '^[a-f0-9]{64}$'
        $second.Data.DependencyIdentityToken |
            Should -BeExactly $first.Data.DependencyIdentityToken
        ($first | ConvertTo-Json -Depth 8 -Compress) |
            Should -Not -Match ([regex]::Escape($script:dllBin))
    }

    It 'rejects a missing required private import before hashing' {
        $paths = @($script:dllPaths[0..3]) + @(Join-Path $script:dllBin 'extra.dll')
        $result = Get-CddsiGitForWindowsPrivateDllObservation `
            -ExecutionContext $script:dllContext `
            -BinPath $script:dllBin `
            -ExpectedPaths $paths

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.IdentityStatus | Should -BeExactly 'Untrusted'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PRIVATE_DLL_REQUIRED_MISSING'
        Should -Invoke Get-FileHash -Times 0 -Exactly
    }

    It 'fails closed when an observed DLL is a reparse point' {
        Mock Get-Item {
            return [pscustomobject]@{
                PSIsContainer = $false
                Length = [long]4096
                Attributes = [System.IO.FileAttributes]::ReparsePoint
            }
        }
        $result = Get-CddsiGitForWindowsPrivateDllObservation `
            -ExecutionContext $script:dllContext `
            -BinPath $script:dllBin `
            -ExpectedPaths $script:dllPaths

        $result.Status | Should -BeExactly 'FAILED'
        $result.ErrorCode | Should -BeExactly 'GIT_PRIVATE_DLL_OBSERVATION_FAILED'
        ($result | ConvertTo-Json -Depth 8 -Compress) |
            Should -Not -Match ([regex]::Escape($script:dllBin))
    }
}

Describe 'D-027 signed Git component identity' {
    BeforeEach {
        Mock Assert-CddsiD027GitLiveContext { return $true }
        $script:componentPath = Join-Path $TestDrive 'git.exe'
        $bytes = New-CddsiObserverPeBytes
        [System.IO.File]::WriteAllBytes($script:componentPath, $bytes)
        $script:componentItem = [pscustomobject]@{
            PSIsContainer = $false
            Length = [long]$bytes.Length
            Attributes = [System.IO.FileAttributes]::Normal
            VersionInfo = [pscustomobject]@{
                FileDescription = 'Git for Windows'
                ProductName = 'Git'
                CompanyName = 'The Git Development Community'
                OriginalFilename = 'git.exe'
                FileVersion = '2.55.0.windows.3'
                ProductVersion = '2.55.0.windows.3'
            }
        }
        Mock Get-Item { return $script:componentItem } -ParameterFilter { $LiteralPath -eq $script:componentPath }
        Mock Get-AuthenticodeSignature {
            return [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Johannes Schindelin, O=Johannes Schindelin, L=Bruehl, C=DE'
                    Thumbprint = ('1' * 40)
                }
                TimeStamperCertificate = [pscustomobject]@{ Subject = 'CN=Synthetic Timestamp' }
            }
        } -ParameterFilter { $LiteralPath -eq $script:componentPath }
    }

    It 'trusts a calibrated signed x64 component without returning its path' {
        $context = [pscustomobject]@{ Mode = 'Live'; Paths = [ordered]@{ Temp = $TestDrive } }
        $result = Get-CddsiGitForWindowsSignedComponentObservation `
            -ExecutionContext $context `
            -ComponentPath $script:componentPath `
            -ComponentRole PathLauncher
        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.IdentityStatus | Should -BeExactly 'Trusted'
        $result.Data.ComponentRole | Should -BeExactly 'PathLauncher'
        $result.Data.PeMachine | Should -BeExactly 'x64'
        $result.Data.FileVersion | Should -BeExactly '2.55.0.windows.3'
        $result.Data.FileIdentityToken | Should -Match '^[a-f0-9]{64}$'
        ($result | ConvertTo-Json -Depth 10) | Should -Not -Match ([regex]::Escape($script:componentPath))
    }

    It 'rejects an uncalibrated component signer' {
        Mock Get-AuthenticodeSignature {
            return [pscustomobject]@{
                Status = 'Valid'
                SignerCertificate = [pscustomobject]@{ Subject = 'CN=Other Publisher'; Thumbprint = ('2' * 40) }
                TimeStamperCertificate = [pscustomobject]@{ Subject = 'CN=Synthetic Timestamp' }
            }
        } -ParameterFilter { $LiteralPath -eq $script:componentPath }
        $context = [pscustomobject]@{ Mode = 'Live'; Paths = [ordered]@{ Temp = $TestDrive } }
        $result = Get-CddsiGitForWindowsSignedComponentObservation `
            -ExecutionContext $context `
            -ComponentPath $script:componentPath `
            -ComponentRole PathLauncher
        $result.Data.IdentityStatus | Should -BeExactly 'Untrusted'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_COMPONENT_SIGNER_UNTRUSTED'
    }

    It 'does not read a component outside explicit Live mode' {
        Mock Assert-CddsiD027GitLiveContext { throw 'not Live' }
        Mock Get-Item { throw 'must not read' }
        $context = [pscustomobject]@{ Mode = 'DryRun'; Paths = [ordered]@{ Temp = $TestDrive } }
        { Get-CddsiGitForWindowsSignedComponentObservation -ExecutionContext $context -ComponentPath 'C:\Tools\git.exe' -ComponentRole Core } |
            Should -Throw
        Should -Invoke Get-Item -Times 0 -Exactly
    }
}

Describe 'D-027 protected Git installation ACL boundary' {
    BeforeEach {
        Mock Assert-CddsiD027GitLiveContext { return $true }
        $script:aclContext = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = $TestDrive }
        }
        $script:programFiles = [Environment]::GetFolderPath(
            [Environment+SpecialFolder]::ProgramFiles
        )
        $script:aclRoot = Join-Path $script:programFiles 'Git'
        $script:aclRequired = @(
            (Join-Path $script:aclRoot 'cmd'),
            (Join-Path $script:aclRoot 'cmd\git.exe'),
            (Join-Path $script:aclRoot 'mingw64\bin'),
            (Join-Path $script:aclRoot 'mingw64\bin\git.exe'),
            (Join-Path $script:aclRoot 'mingw64\libexec\git-core'),
            (Join-Path $script:aclRoot 'mingw64\libexec\git-core\git-remote-https.exe')
        )
        Mock New-Object {
            return [pscustomobject]@{
                DriveType = [System.IO.DriveType]::Fixed
                DriveFormat = 'NTFS'
            }
        } -ParameterFilter { $TypeName -ceq 'System.IO.DriveInfo' }
        Mock Test-CddsiCurrentProcessElevated { return $false }
        Mock Get-Item {
            return [pscustomobject]@{
                Attributes = [System.IO.FileAttributes]::Normal
            }
        }
    }

    It 'accepts only protected Program Files writers and inherit-only Creator Owner' {
        $script:protectedAcl = New-Object Security.AccessControl.DirectorySecurity
        $script:protectedAcl.SetSecurityDescriptorSddlForm(
            'O:BAG:BAD:AI' +
            '(A;OICI;FA;;;SY)' +
            '(A;OICI;FA;;;BA)' +
            '(A;OICI;0x1200a9;;;BU)' +
            '(A;OICIIO;GA;;;CO)'
        )
        Mock Get-Acl { return $script:protectedAcl }

        $result = Test-CddsiGitProtectedInstallPathSet `
            -ExecutionContext $script:aclContext `
            -InstallRoot $script:aclRoot `
            -RequiredPaths $script:aclRequired

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.ProtectionStatus | Should -BeExactly 'Protected'
        $result.Data.RequiredPathCount | Should -Be 8
        @($result.Data.ReasonCodes).Count | Should -Be 0
    }

    It 'rejects a non-inherit-only Users write grant before any process probe' {
        $script:writableAcl = New-Object Security.AccessControl.DirectorySecurity
        $script:writableAcl.SetSecurityDescriptorSddlForm(
            'O:BAG:BAD:AI' +
            '(A;OICI;FA;;;SY)' +
            '(A;OICI;FA;;;BA)' +
            '(A;OICI;0x1200a9;;;BU)' +
            '(A;;GW;;;BU)'
        )
        Mock Get-Acl { return $script:writableAcl }

        $result = Test-CddsiGitProtectedInstallPathSet `
            -ExecutionContext $script:aclContext `
            -InstallRoot $script:aclRoot `
            -RequiredPaths $script:aclRequired

        $result.Data.ProtectionStatus | Should -BeExactly 'Untrusted'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_INSTALL_USER_WRITABLE'
    }
}

Describe 'D-027 protected Git installation bundle identity' {
    BeforeEach {
        Mock Assert-CddsiD027GitLiveContext { return $true }
        $script:bundleContext = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = $TestDrive }
        }
        $script:bundleRoot = Join-Path (
            [Environment]::GetFolderPath([Environment+SpecialFolder]::ProgramFiles)
        ) 'Git'
        $script:bundleLauncher = Join-Path $script:bundleRoot 'cmd\git.exe'
        $script:bundleBin = Join-Path $script:bundleRoot 'mingw64\bin'
        $script:bundleDllNames = @(
            'libiconv-2.dll',
            'libintl-8.dll',
            'libpcre2-8-0.dll',
            'libwinpthread-1.dll',
            'zlib1.dll'
        )
        $script:bundleDllPaths = @(
            $script:bundleDllNames | ForEach-Object { Join-Path $script:bundleBin $_ }
        )

        Mock Test-CddsiGitProtectedInstallPathSet {
            return New-CddsiObserverProtectionResult -InstallRoot $InstallRoot
        }
        Mock Get-ChildItem {
            return @(
                $script:bundleDllPaths | ForEach-Object {
                    [pscustomobject]@{ FullName = $_ }
                }
            )
        } -ParameterFilter {
            $LiteralPath -eq $script:bundleBin -and $Filter -eq '*.dll'
        }
        Mock Get-CddsiGitForWindowsPrivateDllObservation {
            return New-CddsiObserverPrivateDllResult
        }
        Mock Get-CddsiGitForWindowsSignedComponentObservation {
            return New-CddsiObserverComponentResult `
                -ComponentPath $ComponentPath `
                -ComponentRole $ComponentRole
        }
        Mock Get-CddsiGitForWindowsRegistryObservation {
            return New-CddsiObserverRegistryResult -InstallRoot $ExpectedInstallRoot
        }
    }

    It 'binds the protected launcher core HTTPS transport and exact machine receipt' {
        $result = Get-CddsiGitForWindowsExecutableObservation `
            -ExecutionContext $script:bundleContext `
            -ExecutablePath $script:bundleLauncher

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.SchemaVersion | Should -Be 3
        $result.Data.IdentityStatus | Should -BeExactly 'Trusted'
        $result.Data.IdentityToken | Should -BeExactly '<IDENTITY:GIT_FOR_WINDOWS_X64_PROTECTED_BUNDLE>'
        $result.Data.ProtectionStatus | Should -BeExactly 'Protected'
        $result.Data.RegistryStatus | Should -BeExactly 'Trusted'
        $result.Data.ComponentCount | Should -Be 3
        $result.Data.FileIdentityToken | Should -Match '^[a-f0-9]{64}$'
        $result.Data.CorePathBindingToken | Should -Match '^[a-f0-9]{64}$'
        $result.Data.HttpsPathBindingToken | Should -Match '^[a-f0-9]{64}$'
        $result.Data.DependencyIdentityToken | Should -Match '^[a-f0-9]{64}$'
        $result.Data.DependencyCount | Should -Be 5
        @($result.Data.ReasonCodes).Count | Should -Be 0

        Should -Invoke Test-CddsiGitProtectedInstallPathSet -Times 1 -Exactly -ParameterFilter {
            $InstallRoot -eq $script:bundleRoot -and
            @($RequiredPaths).Count -eq 8
        }
        Should -Invoke Test-CddsiGitProtectedInstallPathSet -Times 1 -Exactly -ParameterFilter {
            if ($InstallRoot -ne $script:bundleRoot -or @($RequiredPaths).Count -ne 13) {
                return $false
            }
            foreach ($dllPath in $script:bundleDllPaths) {
                if (@($RequiredPaths) -notcontains $dllPath) { return $false }
            }
            return $true
        }
        Should -Invoke Get-CddsiGitForWindowsPrivateDllObservation -Times 1 -Exactly -ParameterFilter {
            $BinPath -eq $script:bundleBin -and
            @($ExpectedPaths).Count -eq 5
        }
        Should -Invoke Get-CddsiGitForWindowsSignedComponentObservation -Times 1 -Exactly -ParameterFilter {
            $ComponentRole -ceq 'PathLauncher' -and
            $ComponentPath -eq (Join-Path $script:bundleRoot 'cmd\git.exe')
        }
        Should -Invoke Get-CddsiGitForWindowsSignedComponentObservation -Times 1 -Exactly -ParameterFilter {
            $ComponentRole -ceq 'Core' -and
            $ComponentPath -eq (Join-Path $script:bundleRoot 'mingw64\bin\git.exe')
        }
        Should -Invoke Get-CddsiGitForWindowsSignedComponentObservation -Times 1 -Exactly -ParameterFilter {
            $ComponentRole -ceq 'HttpsTransport' -and
            $ComponentPath -eq (Join-Path $script:bundleRoot 'mingw64\libexec\git-core\git-remote-https.exe')
        }
        Should -Invoke Get-CddsiGitForWindowsRegistryObservation -Times 1 -Exactly -ParameterFilter {
            $ExpectedInstallRoot -eq $script:bundleRoot -and
            $ExpectedReceiptVersion -ceq '2.55.0.3'
        }
    }

    It 'fails closed when the machine receipt does not bind the protected bundle' {
        Mock Get-CddsiGitForWindowsRegistryObservation {
            return New-CddsiObserverRegistryResult `
                -InstallRoot $ExpectedInstallRoot `
                -RegistryStatus Untrusted
        }

        $result = Get-CddsiGitForWindowsExecutableObservation `
            -ExecutionContext $script:bundleContext `
            -ExecutablePath $script:bundleLauncher

        $result.Status | Should -BeExactly 'SUCCEEDED'
        $result.Data.IdentityStatus | Should -BeExactly 'Untrusted'
        $result.Data.ProtectionStatus | Should -BeExactly 'Protected'
        $result.Data.RegistryStatus | Should -BeExactly 'Untrusted'
        $result.Data.IdentityToken | Should -BeNullOrEmpty
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_INSTALL_REGISTRY_PATH_MISMATCH'
    }

    It 'fails closed before signed components and registry when a required private DLL is absent' {
        Mock Get-CddsiGitForWindowsPrivateDllObservation {
            return New-CddsiObserverPrivateDllResult -IdentityStatus Untrusted
        }

        $result = Get-CddsiGitForWindowsExecutableObservation `
            -ExecutionContext $script:bundleContext `
            -ExecutablePath $script:bundleLauncher

        $result.Data.IdentityStatus | Should -BeExactly 'Untrusted'
        $result.Data.ProtectionStatus | Should -BeExactly 'Protected'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PRIVATE_DLL_REQUIRED_MISSING'
        Should -Invoke Get-CddsiGitForWindowsSignedComponentObservation -Times 0 -Exactly
        Should -Invoke Get-CddsiGitForWindowsRegistryObservation -Times 0 -Exactly
    }

    It 'changes the protected bundle identity when the private DLL identity changes' {
        $script:dependencyToken = '8' * 64
        Mock Get-CddsiGitForWindowsPrivateDllObservation {
            return New-CddsiObserverPrivateDllResult `
                -DependencyIdentityToken $script:dependencyToken
        }
        $first = Get-CddsiGitForWindowsExecutableObservation `
            -ExecutionContext $script:bundleContext `
            -ExecutablePath $script:bundleLauncher

        $script:dependencyToken = '9' * 64
        $second = Get-CddsiGitForWindowsExecutableObservation `
            -ExecutionContext $script:bundleContext `
            -ExecutablePath $script:bundleLauncher

        $first.Data.FileIdentityToken | Should -Not -BeExactly $second.Data.FileIdentityToken
    }
}

Describe 'D-027 Git probe implementation guardrails' {
    It 'uses the exact signed core plan and has no unbounded reader or Process Kill call' {
        $parseErrors = $null
        $tokens = $null
        $libraryPath = Join-Path $script:RepoRoot 'lib\git-for-windows.ps1'
        $libraryAst = [System.Management.Automation.Language.Parser]::ParseFile(
            $libraryPath,
            [ref]$tokens,
            [ref]$parseErrors
        )
        @($parseErrors).Count | Should -Be 0

        $forbiddenMembers = @($libraryAst.FindAll({
            param($node)
            if ($node -isnot [System.Management.Automation.Language.MemberExpressionAst]) {
                return $false
            }
            $member = $node.Member.Extent.Text.Trim("'`"")
            return $member -like 'ReadToEnd*' -or $member -ceq 'Kill'
        }, $true))
        @($forbiddenMembers).Count | Should -Be 0

        $probeFunction = @($libraryAst.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.FunctionDefinitionAst] -and
            $node.Name -ceq 'Invoke-CddsiGitVersionProbe'
        }, $true))
        $probeFunction.Count | Should -Be 1
        $startInfoCommands = @($probeFunction[0].Body.FindAll({
            param($node)
            $node -is [System.Management.Automation.Language.CommandAst] -and
            $node.GetCommandName() -ceq 'New-CddsiGitVersionProbeStartInfo'
        }, $true))
        $startInfoCommands.Count | Should -Be 1
        $startInfoCommands[0].Extent.Text | Should -Match '(?s)-ExecutablePath\s+\$corePath\b'

        $source = [System.IO.File]::ReadAllText($libraryPath)
        $source | Should -Not -Match '\.ReadToEnd(?:Async)?\s*\('
        $source | Should -Not -Match '\.Kill\s*\('
        $source | Should -Not -Match 'DateTime\.UtcNow'
        $source | Should -Match 'Stopwatch\.StartNew\(\)'
        $source | Should -Match 'CancelSynchronousIo'
        $source | Should -Match 'if \(attributeListInitialized\) DeleteProcThreadAttributeList'
        $source | Should -Match '\.GetValueKind\(\$valueName\)'
        $source | Should -Match 'GIT_INSTALL_REGISTRY_VALUE_KIND_INVALID'
        $source | Should -Match '(?s)\$lockPaths\s*=\s*@\(\$launcherPath,\s*\$corePath,\s*\$httpsPath\)\s*\+\s*@\(\$privateDllPaths\)'
        $source | Should -Match '(?s)\[Cddsi\.D027\.GitProbeRunner\]::Run\(.+?,\s*128,\s*5000\s*\)'
    }

    It 'loads the bounded runner type without starting a real Git process in Pester' {
        Initialize-CddsiD027GitProbeRunnerType
        $runnerType = 'Cddsi.D027.GitProbeRunner' -as [type]
        $runnerType | Should -Not -BeNullOrEmpty
        $runMethod = $runnerType.GetMethod('Run')
        $runMethod | Should -Not -BeNullOrEmpty
        @($runMethod.GetParameters()).Count | Should -Be 6
    }
}

Describe 'D-027 live Git PATH observer classification' {
    BeforeEach {
        Mock Assert-CddsiD027GitLiveContext { return $true }
        Mock Assert-CddsiExecutionContext { return $true }
        $script:savedPath = $env:Path
        $script:savedPathExt = $env:PATHEXT
        $script:liveContext = [pscustomobject]@{
            Mode = 'Live'
            Paths = [ordered]@{ Temp = (Join-Path $TestDrive 'owned-temp') }
        }
        New-Item -ItemType Directory -Path $script:liveContext.Paths.Temp -Force | Out-Null
        Mock Get-CddsiGitForWindowsExecutableObservation {
            return New-CddsiObserverIdentityResult -ExecutablePath $ExecutablePath
        }
        Mock Invoke-CddsiGitVersionProbe { return New-CddsiObserverProbeSuccess }
        Mock New-Object {
            return [pscustomobject]@{ DriveType = [System.IO.DriveType]::Fixed }
        } -ParameterFilter { $TypeName -ceq 'System.IO.DriveInfo' }
    }

    AfterEach {
        $env:Path = $script:savedPath
        $env:PATHEXT = $script:savedPathExt
    }

    It 'returns missing without identity or process probing' {
        $empty = Join-Path $TestDrive 'empty'
        New-Item -ItemType Directory -Path $empty | Out-Null
        $env:Path = $empty
        $result = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $script:liveContext -MinimumVersion '2.45.0'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_MISSING'
        $result.Data.ReuseEligible | Should -BeFalse
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }

    It 'deduplicates repeated PATH entries and returns ready only after identity probe and recheck' {
        $directory = Join-Path $TestDrive 'git-one'
        New-Item -ItemType Directory -Path $directory | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'git.exe'), (New-Object byte[] 1))
        $env:Path = $directory + ';' + (Join-Path $directory '.')
        $result = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $script:liveContext -MinimumVersion '2.45.0'
        $result.Data.CapabilityStatus | Should -BeExactly 'READY'
        $result.Data.ReuseEligible | Should -BeTrue
        $result.Data.Version | Should -BeExactly '2.55.0.windows.3'
        $result.Data.ExecutableToken | Should -Match '^<GIT_EXECUTABLE:PATH_SHA256:[A-F0-9]{64}>$'
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 2 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 1 -Exactly
    }

    It 'fails closed for two distinct executables before identity or process probing' {
        $directories = @((Join-Path $TestDrive 'git-a'), (Join-Path $TestDrive 'git-b'))
        foreach ($directory in $directories) {
            New-Item -ItemType Directory -Path $directory | Out-Null
            [System.IO.File]::WriteAllBytes((Join-Path $directory 'git.exe'), (New-Object byte[] 1))
        }
        $env:Path = $directories -join ';'
        $result = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $script:liveContext -MinimumVersion '2.45.0'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PATH_AMBIGUOUS'
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }

    It 'fails closed for a command shadow before identity or process probing' {
        $directory = Join-Path $TestDrive 'git-shadow'
        New-Item -ItemType Directory -Path $directory | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'git.exe'), (New-Object byte[] 1))
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'git.cmd'), (New-Object byte[] 1))
        $env:Path = $directory
        $result = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $script:liveContext -MinimumVersion '2.45.0'
        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PATH_SHADOWED'
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }

    It 'fails closed for a PowerShell shadow or malformed PATHEXT before probing' {
        $directory = Join-Path $TestDrive 'git-script-shadow'
        New-Item -ItemType Directory -Path $directory | Out-Null
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'git.exe'), (New-Object byte[] 1))
        [System.IO.File]::WriteAllBytes((Join-Path $directory 'git.ps1'), (New-Object byte[] 1))
        $env:Path = $directory
        $shadowed = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $script:liveContext -MinimumVersion '2.45.0'
        @($shadowed.Data.ReasonCodes) | Should -Contain 'GIT_PATH_SHADOWED'

        Remove-Item -LiteralPath (Join-Path $directory 'git.ps1') -Force
        $env:PATHEXT = '.EXE;BROKEN'
        $invalid = Get-CddsiLiveGitForWindowsObservation -ExecutionContext $script:liveContext -MinimumVersion '2.45.0'
        @($invalid.Data.ReasonCodes) | Should -Contain 'GIT_PATH_INVALID'
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }

    It 'rejects a mapped or network PATH volume without touching its filesystem' {
        $directory = Join-Path $TestDrive 'network-path'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $env:Path = $directory
        Mock New-Object {
            return [pscustomobject]@{ DriveType = [System.IO.DriveType]::Network }
        } -ParameterFilter { $TypeName -ceq 'System.IO.DriveInfo' }
        Mock Get-Item { throw 'must not touch the mapped filesystem' }
        Mock Test-Path { throw 'must not test the mapped filesystem' }

        $result = Get-CddsiLiveGitForWindowsObservation `
            -ExecutionContext $script:liveContext `
            -MinimumVersion '2.45.0'

        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PATH_INVALID'
        Should -Invoke Get-Item -Times 0 -Exactly
        Should -Invoke Test-Path -Times 0 -Exactly
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }

    It 'rejects a reparse ancestor before testing any command candidate' {
        $directory = Join-Path $TestDrive 'reparse-path'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $env:Path = $directory
        Mock Get-Item {
            return [pscustomobject]@{
                PSIsContainer = $true
                Attributes = [System.IO.FileAttributes]::ReparsePoint
            }
        }
        Mock Test-Path { throw 'must not test a reparse path' }

        $result = Get-CddsiLiveGitForWindowsObservation `
            -ExecutionContext $script:liveContext `
            -MinimumVersion '2.45.0'

        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PATH_INVALID'
        Should -Invoke Test-Path -Times 0 -Exactly
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }

    It 'converts a fixed-volume candidate I/O failure to the stable invalid PATH result' {
        $directory = Join-Path $TestDrive 'io-failure-path'
        New-Item -ItemType Directory -Path $directory | Out-Null
        $env:Path = $directory
        Mock Test-Path { throw 'synthetic private path detail' }

        $result = Get-CddsiLiveGitForWindowsObservation `
            -ExecutionContext $script:liveContext `
            -MinimumVersion '2.45.0'

        @($result.Data.ReasonCodes) | Should -Contain 'GIT_PATH_INVALID'
        ($result | ConvertTo-Json -Depth 8 -Compress) |
            Should -Not -Match 'synthetic private path detail'
        Should -Invoke Get-CddsiGitForWindowsExecutableObservation -Times 0 -Exactly
        Should -Invoke Invoke-CddsiGitVersionProbe -Times 0 -Exactly
    }
}
