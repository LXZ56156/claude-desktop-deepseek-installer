BeforeAll {
    $script:ProjectRoot = Split-Path -Parent $PSScriptRoot
    . (Join-Path $script:ProjectRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries
}

Describe 'D-027 practical entry' {
    It 'keeps all three DryRun actions side-effect free' {
        foreach ($action in @('Install', 'Diagnose', 'Restore')) {
            $result = & (Join-Path $script:ProjectRoot 'Start-Here.ps1') `
                -Action $action -DryRun -PassThru
            $result.Status | Should -BeExactly 'SUCCEEDED'
            $result.Changed | Should -BeFalse
            $result.Data.Mode | Should -BeExactly 'DryRun'
        }
    }

    It 'rejects conflicting modes before any live workflow' {
        $result = & (Join-Path $script:ProjectRoot 'Start-Here.ps1') `
            -Action Install -Live -DryRun -PassThru
        $result.Status | Should -BeExactly 'FAILED'
        $result.ErrorCode | Should -BeExactly 'MODE_CONFLICT'
        $result.Changed | Should -BeFalse
    }

    It 'uses the four-module bootstrap and no retired runtime' {
        $bootstrap = [IO.File]::ReadAllText(
            (Join-Path $script:ProjectRoot 'lib\bootstrap.ps1')
        )
        foreach ($name in @('common.ps1', 'installer.ps1', 'configuration.ps1', 'workflow.ps1')) {
            $bootstrap | Should -Match ([regex]::Escape($name))
        }
        $bootstrap | Should -Not -Match 'snapshot|relay|fake-provider|calibration'
    }
}

Describe 'official configuration projection' {
    It 'projects the exact minimal REG_SZ value set' {
        $settings = Get-CddsiSettings -ProjectRoot $script:ProjectRoot
        $values = Get-CddsiPolicyValueSet -Settings $settings `
            -HelperPath 'C:\ProgramData\probe\helper.exe'
        @($values.Keys).Count | Should -Be 8
        (@($values.Keys) -join ',') | Should -BeExactly (
            'inferenceProvider,inferenceCredentialKind,inferenceCredentialHelper,' +
            'inferenceGatewayBaseUrl,inferenceGatewayAuthScheme,modelDiscoveryEnabled,' +
            'inferenceModels,chatTabEnabled'
        )
        foreach ($value in $values.Values) {
            $value | Should -BeOfType [string]
        }
        $values.inferenceCredentialKind | Should -BeExactly 'helper-script'
        $values.inferenceGatewayAuthScheme | Should -BeExactly 'x-api-key'
        $values.inferenceGatewayBaseUrl | Should -BeExactly 'https://api.deepseek.com/anthropic'
        $values.modelDiscoveryEnabled | Should -BeExactly 'false'
    }

    It 'uses only the current fixed DeepSeek V4 model IDs' {
        $settings = Get-CddsiSettings -ProjectRoot $script:ProjectRoot
        (@($settings.models.name) -join ',') |
            Should -BeExactly 'deepseek-v4-pro,deepseek-v4-flash'
        $models = (Get-CddsiPolicyValueSet -Settings $settings `
            -HelperPath 'C:\probe.exe').inferenceModels | ConvertFrom-Json
        (@($models.name) -join ',') |
            Should -BeExactly 'deepseek-v4-pro,deepseek-v4-flash'
        @($models | Where-Object { $_.PSObject.Properties.Name -contains 'supports1m' }).Count |
            Should -Be 0
    }
}

Describe 'Git acquisition contract' {
    BeforeEach {
        $script:ValidGitRelease = [pscustomobject]@{
            immutable    = $true
            draft        = $false
            prerelease   = $false
            tag_name     = 'v2.55.0.windows.3'
            published_at = '2026-07-22T00:00:00Z'
            assets       = @(
                [pscustomobject]@{
                    name                 = 'Git-2.55.0.3-64-bit.exe'
                    browser_download_url = 'https://github.com/git-for-windows/git/releases/download/v2.55.0.windows.3/Git-2.55.0.3-64-bit.exe'
                    state                = 'uploaded'
                    size                 = [long]65388144
                    digest               = 'sha256:af12577d0fdff74243a5988197aa49b957d5044edc17004f6ddf0768996f1dca'
                }
            )
        }
    }

    It 'accepts a current-shaped immutable official release' {
        $asset = Resolve-CddsiGitReleaseAsset -Release $script:ValidGitRelease
        $asset.Version.ToString() | Should -BeExactly '2.55.0.3'
        $asset.Size | Should -Be 65388144
        $asset.Sha256 | Should -BeExactly 'af12577d0fdff74243a5988197aa49b957d5044edc17004f6ddf0768996f1dca'
    }

    It 'rejects mutable metadata and a non-official asset URL' {
        $script:ValidGitRelease.immutable = $false
        { Resolve-CddsiGitReleaseAsset -Release $script:ValidGitRelease } |
            Should -Throw '*GIT_METADATA_INVALID*'
        $script:ValidGitRelease.immutable = $true
        $script:ValidGitRelease.assets[0].browser_download_url = 'https://example.invalid/Git.exe'
        { Resolve-CddsiGitReleaseAsset -Release $script:ValidGitRelease } |
            Should -Throw '*GIT_METADATA_INVALID*'
    }

    It 'pins trusted signer organizations instead of accepting any valid signature' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status            = [Management.Automation.SignatureStatus]::Valid
                SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Example Corp, O=Example Corp, C=US'
                }
            }
        }
        { Get-CddsiTrustedSignature -Path 'C:\probe.exe' -Artifact Git } |
            Should -Throw '*GIT_SIGNER_INVALID*'
        { Get-CddsiTrustedSignature -Path 'C:\probe.msix' -Artifact Claude } |
            Should -Throw '*CLAUDE_SIGNER_INVALID*'
    }

    It 'accepts the expected Git and Anthropic signer subject shapes' {
        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status            = [Management.Automation.SignatureStatus]::Valid
                SignerCertificate = [pscustomobject]@{
                    Subject = 'CN=Johannes Schindelin, O=Johannes Schindelin, L=Bruehl, C=DE'
                }
            }
        }
        { Get-CddsiTrustedSignature -Path 'C:\probe.exe' -Artifact Git } |
            Should -Not -Throw

        Mock Get-AuthenticodeSignature {
            [pscustomobject]@{
                Status            = [Management.Automation.SignatureStatus]::Valid
                SignerCertificate = [pscustomobject]@{
                    Subject = 'CN="Anthropic, PBC", O="Anthropic, PBC", L=San Francisco, S=California, C=US, SERIALNUMBER=4860621, OID.2.5.4.15=Private Organization'
                }
            }
        }
        { Get-CddsiTrustedSignature -Path 'C:\probe.msix' -Artifact Claude } |
            Should -Not -Throw
    }

    It 'checks digest and signature before execution and rehashes immediately before execution' {
        $source = [IO.File]::ReadAllText(
            (Join-Path $script:ProjectRoot 'lib\installer.ps1')
        )
        $signature = $source.IndexOf(
            'Get-CddsiTrustedSignature -Path $installerPath -Artifact Git'
        )
        $rehash = $source.IndexOf(
            '$preExecutionHash = Get-CddsiFileSha256 -Path $installerPath'
        )
        $execute = $source.IndexOf(
            'Start-Process -FilePath $installerPath'
        )
        $signature | Should -BeGreaterThan -1
        $rehash | Should -BeGreaterThan $signature
        $execute | Should -BeGreaterThan $rehash
        $source | Should -Match 'HttpCompletionOption\]::ResponseHeadersRead'
        $source | Should -Match 'DOWNLOAD_TOO_LARGE'
        $source | Should -Not -Match 'Get-Command git\.exe'
    }
}

Describe 'Claude MSIX contract' {
    It 'reads only the expected Claude x64 manifest identity' {
        Add-Type -AssemblyName System.IO.Compression.FileSystem
        $sourceDirectory = Join-Path $TestDrive 'valid-msix'
        New-Item -ItemType Directory -Path $sourceDirectory | Out-Null
        $manifest = @'
<?xml version="1.0" encoding="utf-8"?>
<Package xmlns="http://schemas.microsoft.com/appx/manifest/foundation/windows10">
  <Identity Name="Claude" Publisher="CN=&quot;Anthropic, PBC&quot;, O=&quot;Anthropic, PBC&quot;, L=San Francisco, S=California, C=US, SERIALNUMBER=4860621" Version="1.2.3.4" ProcessorArchitecture="x64" />
</Package>
'@
        Set-Content -LiteralPath (Join-Path $sourceDirectory 'AppxManifest.xml') `
            -Value $manifest -Encoding UTF8
        $msix = Join-Path $TestDrive 'Claude.msix'
        [IO.Compression.ZipFile]::CreateFromDirectory($sourceDirectory, $msix)
        $identity = Read-CddsiClaudeMsixIdentity -Path $msix
        $identity.Name | Should -BeExactly 'Claude'
        $identity.Architecture | Should -BeExactly 'x64'
        $identity.Version.ToString() | Should -BeExactly '1.2.3.4'
    }

    It 'binds the official endpoint, official host, signature, publisher and pre-install hash' {
        $source = [IO.File]::ReadAllText(
            (Join-Path $script:ProjectRoot 'lib\installer.ps1')
        )
        $source | Should -Match ([regex]::Escape(
            'https://claude.ai/api/desktop/win32/x64/msix/latest/redirect'
        ))
        $source | Should -Match "downloads\.claude\.ai"
        $signature = $source.IndexOf(
            'Get-CddsiTrustedSignature -Path $path -Artifact Claude'
        )
        $rehash = $source.IndexOf(
            '$preExecutionHash = Get-CddsiFileSha256 -Path $path'
        )
        $install = $source.IndexOf('Add-AppxPackage -Path $path')
        $signature | Should -BeGreaterThan -1
        $rehash | Should -BeGreaterThan $signature
        $install | Should -BeGreaterThan $rehash
    }
}

Describe 'credential boundary' {
    It 'compiles the helper with the Windows 11 in-box compiler' {
        $compiler = Join-Path $env:SystemRoot 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
        Test-Path -LiteralPath $compiler -PathType Leaf | Should -BeTrue
        $output = Join-Path $TestDrive 'DeepSeekCredentialHelper.exe'
        & $compiler /nologo /target:exe /platform:anycpu /optimize+ /debug- `
            "/out:$output" /reference:System.dll /reference:System.Security.dll `
            (Join-Path $script:ProjectRoot 'helper\CddsiCredentialHelper.cs')
        $LASTEXITCODE | Should -Be 0
        (Get-Item -LiteralPath $output).Length | Should -BeGreaterThan 4095
    }

    It 'runs the real helper installation function inside TestDrive' {
        $projectCopy = Join-Path $TestDrive 'release with spaces'
        New-Item -ItemType Directory -Path (
            Join-Path $projectCopy 'helper'
        ) | Out-Null
        Copy-Item -LiteralPath (
            Join-Path $script:ProjectRoot 'helper\CddsiCredentialHelper.cs'
        ) -Destination (Join-Path $projectCopy 'helper\CddsiCredentialHelper.cs')
        $targetRoot = Join-Path $TestDrive 'helper install with spaces'
        $paths = [pscustomobject]@{
            Root   = $targetRoot
            Helper = Join-Path $targetRoot 'DeepSeekCredentialHelper.exe'
        }
        $hash = Install-CddsiCredentialHelper `
            -ProjectRoot $projectCopy -Paths $paths
        $hash | Should -Match '^[a-f0-9]{64}$'
        Test-Path -LiteralPath $paths.Helper -PathType Leaf | Should -BeTrue
        (Get-Item -LiteralPath $paths.Helper).Length | Should -BeGreaterThan 4095
    }

    It 'takes no key from arguments or environment and writes no plaintext string object' {
        $source = [IO.File]::ReadAllText(
            (Join-Path $script:ProjectRoot 'helper\CddsiCredentialHelper.cs')
        )
        $source | Should -Not -Match 'string\[\]\s+args|GetCommandLineArgs|GetEnvironmentVariable'
        $source | Should -Not -Match 'GetString\(plaintext\)|Write\(token\)'
        $source | Should -Match 'DataProtectionScope\.CurrentUser'
        $source | Should -Match 'OpenStandardOutput'
        $source | Should -Match 'Array\.Clear\(plaintext'
    }

    It 'never stores a static API key or accesses Claude Code settings' {
        $runtimeFiles = @(
            'Start-Here.ps1'
            'lib/common.ps1'
            'lib/installer.ps1'
            'lib/configuration.ps1'
            'lib/workflow.ps1'
            'helper/CddsiCredentialHelper.cs'
            'config/deepseek-desktop.defaults.json'
        )
        $content = ($runtimeFiles | ForEach-Object {
            [IO.File]::ReadAllText((Join-Path $script:ProjectRoot $_))
        }) -join "`n"
        $content | Should -Not -Match 'inferenceGatewayApiKey'
        $content | Should -Not -Match '(?i)\bsk-[A-Za-z0-9_-]{20,}\b'
        $content | Should -Not -Match '(?i)(Test-Path|Get-Item|Get-Content|Set-Content).{0,120}\.claude.{0,40}settings\.json'
        $content | Should -Match 'ProtectedData\]::Protect'
    }
}

Describe 'owned restore contract' {
    BeforeEach {
        $root = Join-Path $TestDrive 'owned-install'
        New-Item -ItemType Directory -Path $root -Force | Out-Null
        $script:OwnedPaths = [pscustomobject]@{
            Root            = $root
            Credential      = Join-Path $root 'credential.bin'
            Helper          = Join-Path $root 'DeepSeekCredentialHelper.exe'
            State           = Join-Path $root 'state.json'
            OwnershipMarker = Join-Path $root '.cddsi-owner'
        }
        foreach ($path in @(
            $script:OwnedPaths.Credential,
            $script:OwnedPaths.Helper,
            $script:OwnedPaths.OwnershipMarker
        )) {
            Set-Content -LiteralPath $path -Value 'synthetic' -Encoding UTF8
        }
        $state = [ordered]@{
            SchemaVersion    = 1
            OwnerId          = 'claude-desktop-deepseek-installer'
            PolicyValueNames = @($script:CddsiManagedPolicyNames)
        }
        $state | ConvertTo-Json | Set-Content `
            -LiteralPath $script:OwnedPaths.State -Encoding UTF8
        Mock Get-CddsiProductPaths { $script:OwnedPaths }
        Mock Test-CddsiOwnedInstallation { $true }
        Mock Get-CddsiRegistryValueNames { @() }
        Mock Remove-ItemProperty {}
        Mock Remove-Item {}
    }

    It 'removes only the fixed eight policy values' {
        $result = Restore-CddsiClaudeConfiguration
        $result.Changed | Should -BeTrue
        $result.RestoredToAbsent | Should -BeTrue
        Should -Invoke Remove-ItemProperty -Times 8 -Exactly
    }

    It 'rejects a state-injected policy name before any deletion' {
        $state = Get-Content -LiteralPath $script:OwnedPaths.State -Raw |
            ConvertFrom-Json
        $state.PolicyValueNames[0] = 'unrelatedPolicy'
        $state | ConvertTo-Json | Set-Content `
            -LiteralPath $script:OwnedPaths.State -Encoding UTF8
        { Restore-CddsiClaudeConfiguration } |
            Should -Throw '*OWNERSHIP_STATE_INVALID*'
        Should -Invoke Remove-ItemProperty -Times 0 -Exactly
        Should -Invoke Remove-Item -Times 0 -Exactly
    }
}

Describe 'public function contract' {
    It 'matches mandatory parameters and Action ValidateSet values' {
        $contract = Import-PowerShellDataFile -LiteralPath (
            Join-Path $script:ProjectRoot 'config\public-functions.psd1'
        )
        foreach ($entry in $contract.Functions) {
            $command = Get-Command -Name $entry.Name -CommandType Function
            foreach ($name in $entry.MandatoryParameters) {
                $parameter = $command.Parameters[$name]
                $parameter | Should -Not -BeNullOrEmpty
                @($parameter.Attributes | Where-Object {
                    $_ -is [Management.Automation.ParameterAttribute] -and $_.Mandatory
                }).Count | Should -Be 1
            }
            $validateSet = @($command.Parameters.Action.Attributes | Where-Object {
                $_ -is [Management.Automation.ValidateSetAttribute]
            })
            $validateSet.Count | Should -Be 1
            (($validateSet[0].ValidValues | Sort-Object) -join ',') |
                Should -BeExactly (($entry.ActionValidateSet | Sort-Object) -join ',')
        }
    }
}
