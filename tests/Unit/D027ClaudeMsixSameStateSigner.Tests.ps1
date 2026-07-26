BeforeAll {
    $script:RepoRoot =
        Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
    . (Join-Path $script:RepoRoot 'lib\bootstrap.ps1')
    Import-CddsiLibraries

    $script:DesktopMsixPath =
        Join-Path $script:RepoRoot 'lib\desktop-msix.ps1'
    $script:DesktopMsixSource =
        [System.IO.File]::ReadAllText($script:DesktopMsixPath)
    $script:NativeTypeDefinition =
        $script:CddsiD027ClaudeMsixSameStateSignerNativeTypeDefinition
    $script:ExpectedObservationProperties = @(
        'SchemaVersion',
        'ContractVersion',
        'ObservationMethod',
        'VerificationMethod',
        'SignerExtractionMethod',
        'StateLifecycle',
        'FinalPathBindingToken',
        'CallerFileHandleSupplied',
        'FinalPathStableAcrossVerification',
        'FileFactsStableAcrossVerification',
        'ProviderOpenedFile',
        'PrimarySignerCount',
        'SecondarySignatureCount',
        'WinVerifyTrustTrusted',
        'WinVerifyTrustStatus',
        'WinVerifyTrustNativeStatusHex',
        'WinVerifyTrustRevocationMode',
        'StateCloseCompleted',
        'StateCloseNativeStatusHex',
        'StreamPositionRestored',
        'PrimarySignerCertificateDerBytes',
        'PrimarySignerCertificateDerLengthBytes'
    )
}

Describe 'D-027 Claude MSIX private same-state signer observation' {
    It 'keeps the native primitive outside the PowerShell command surface' {
        $script:CddsiD027ClaudeMsixSameStateSignerObserver.GetType().
            FullName |
            Should -BeExactly (
                'System.Func`2[[System.IO.FileStream, mscorlib, ' +
                'Version=4.0.0.0, Culture=neutral, ' +
                'PublicKeyToken=b77a5c561934e089],' +
                '[System.Object, mscorlib, Version=4.0.0.0, ' +
                'Culture=neutral, PublicKeyToken=b77a5c561934e089]]'
            )

        $tokens = $null
        $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile(
            $script:DesktopMsixPath,
            [ref]$tokens,
            [ref]$errors
        )
        @($errors).Count | Should -Be 0
        @(
            $ast.FindAll(
                {
                    param($node)
                    $node -is
                        [System.Management.Automation.Language.FunctionDefinitionAst] -and
                    $node.Name -cmatch 'SameState|NativeObservation'
                },
                $true
            )
        ).Count | Should -Be 0
        @(
            Get-Command `
                '*CddsiD027ClaudeMsixSameState*' `
                -CommandType Function `
                -ErrorAction SilentlyContinue
        ).Count | Should -Be 0
        ([regex]::Matches(
            $script:DesktopMsixSource,
            '\[System\.Func\[System\.IO\.FileStream, object\]\]'
        )).Count | Should -Be 1
    }

    It 'returns one exact path-free fail-closed schema for invalid input' {
        $result =
            $script:CddsiD027ClaudeMsixSameStateSignerObserver.Invoke(
                $null
            )

        (@($result.PSObject.Properties.Name) -join ',') |
            Should -BeExactly (
                $script:ExpectedObservationProperties -join ','
            )
        $result.SchemaVersion | Should -Be 1
        $result.ContractVersion |
            Should -BeExactly (
                'cddsi-d027-claude-msix-' +
                'same-state-native-observation-v1'
            )
        $result.ObservationMethod |
            Should -BeExactly 'CallerHeldFileStreamNativeObservation'
        $result.VerificationMethod |
            Should -BeExactly 'WinVerifyTrustExGenericVerifyV2'
        $result.SignerExtractionMethod |
            Should -BeExactly (
                'WTHelperPrimarySignerCertificateFromSameState'
            )
        $result.StateLifecycle |
            Should -BeExactly 'VerifyExtractCopyCloseRequired'
        $result.WinVerifyTrustTrusted | Should -BeFalse
        $result.WinVerifyTrustStatus |
            Should -BeExactly 'InvalidInput'
        $result.WinVerifyTrustRevocationMode |
            Should -BeExactly 'NotChecked'
        $result.FinalPathBindingToken | Should -BeNullOrEmpty
        $result.PrimarySignerCertificateDerBytes |
            Should -BeNullOrEmpty
        ($result | ConvertTo-Json -Compress) |
            Should -Not -Match '(?i)FinalPath["'']?\s*:|Exception|Stack'
    }

    It 'pins the Win11 x64 ABI and the complete modern WINTRUST_DATA tail' {
        $path = Join-Path $TestDrive 'abi-probe.msix'
        [System.IO.File]::WriteAllBytes(
            $path,
            [byte[]]@(0x50, 0x4b, 0x03, 0x04)
        )
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            [void]$script:CddsiD027ClaudeMsixSameStateSignerObserver.
                Invoke($stream)
        }
        finally {
            $stream.Dispose()
        }

        $nativeType =
            $script:CddsiD027ClaudeMsixSameStateSignerNativeType
        $nativeType | Should -Not -BeNullOrEmpty
        $abiMethod = $nativeType.GetMethod(
            'GetAbiSizes',
            [Reflection.BindingFlags]'Public,Static'
        )
        $abi = $abiMethod.Invoke($null, @())
        $abi.OsVersionInfoEx | Should -Be 284
        $abi.WinTrustFileInfo | Should -Be 32
        $abi.WinTrustData | Should -Be 88
        $abi.WinTrustSignatureSettings | Should -Be 32
        $abi.ByHandleFileInformation | Should -Be 52
        $abi.ProviderDataSignersPrefix | Should -Be 136
        $abi.ProviderSignersOffset | Should -Be 120
        $abi.ProviderSignerHead | Should -Be 24
        $abi.ProviderCertHead | Should -Be 16
        $abi.CertContext | Should -Be 40
        $script:NativeTypeDefinition |
            Should -Match 'IntPtr pSignatureSettings;'
        $script:NativeTypeDefinition |
            Should -Match (
                'pSignatureSettings\s*=\s*' +
                'signatureSettingsPointer'
            )
        $script:NativeTypeDefinition |
            Should -Match 'VER_NT_WORKSTATION'
        $script:NativeTypeDefinition |
            Should -Match 'IsWow64Process2'
        $script:NativeTypeDefinition |
            Should -Match 'IMAGE_FILE_MACHINE_AMD64'
        $script:DesktopMsixSource |
            Should -Match (
                '\$PSVersionTable\.PSVersion\.Major -ne 5' +
                '[\s\S]+?' +
                '\$PSVersionTable\.PSVersion\.Minor -ne 1'
            )
    }

    It 'fixes no-UI no-network VERIFY extract copy CLOSE policy' {
        $script:NativeTypeDefinition |
            Should -Match 'WinVerifyTrustEx'
        $script:NativeTypeDefinition |
            Should -Match (
                '00AAC56B-CD44-11d0-8CC2-00C04FC295EE'
            )
        $script:NativeTypeDefinition |
            Should -Match 'WTD_UI_NONE'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_REVOKE_NONE'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_REVOCATION_CHECK_NONE'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_CACHE_ONLY_URL_RETRIEVAL'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_DISABLE_MD2_MD4'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_UICONTEXT_INSTALL'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_STATEACTION_VERIFY'
        $script:NativeTypeDefinition |
            Should -Match 'WTD_STATEACTION_CLOSE'
        $script:NativeTypeDefinition |
            Should -Match 'nativeStatus != 0'

        $verifyIndex = $script:NativeTypeDefinition.IndexOf(
            'int nativeStatus = WinVerifyTrustEx(',
            [StringComparison]::Ordinal
        )
        $providerIndex = $script:NativeTypeDefinition.IndexOf(
            'ExtractProviderPrimarySigner(',
            $verifyIndex,
            [StringComparison]::Ordinal
        )
        $closeIndex = $script:NativeTypeDefinition.IndexOf(
            'trustData.dwStateAction = WTD_STATEACTION_CLOSE;',
            $providerIndex,
            [StringComparison]::Ordinal
        )
        $verifyIndex | Should -BeGreaterThan -1
        $providerIndex | Should -BeGreaterThan $verifyIndex
        $closeIndex | Should -BeGreaterThan $providerIndex

        $providerHelperIndex = $script:NativeTypeDefinition.IndexOf(
            'WTHelperProvDataFromStateData(stateData)',
            $closeIndex,
            [StringComparison]::Ordinal
        )
        $extractIndex = $script:NativeTypeDefinition.IndexOf(
            'ExtractPrimarySignerCertificate(',
            $providerHelperIndex,
            [StringComparison]::Ordinal
        )
        $signerIndex = $script:NativeTypeDefinition.IndexOf(
            'WTHelperGetProvSignerFromChain(',
            $extractIndex,
            [StringComparison]::Ordinal
        )
        $certIndex = $script:NativeTypeDefinition.IndexOf(
            'WTHelperGetProvCertFromChain(',
            $signerIndex,
            [StringComparison]::Ordinal
        )
        $copyIndex = $script:NativeTypeDefinition.IndexOf(
            'Marshal.Copy(',
            $certIndex,
            [StringComparison]::Ordinal
        )
        $providerHelperIndex | Should -BeGreaterThan $closeIndex
        $extractIndex | Should -BeGreaterThan $providerHelperIndex
        $signerIndex | Should -BeGreaterThan $extractIndex
        $certIndex | Should -BeGreaterThan $signerIndex
        $copyIndex | Should -BeGreaterThan $certIndex
        $script:NativeTypeDefinition |
            Should -Match (
                'ExtractPrimarySignerCertificate\(' +
                '[\s\S]+?Marshal\.Copy\('
            )
    }

    It 'derives the required path from the held handle and rejects provider reopen or signer ambiguity' {
        $script:NativeTypeDefinition |
            Should -Match 'GetFinalPathNameByHandleW'
        $script:NativeTypeDefinition |
            Should -Match 'GetFileInformationByHandle'
        $script:NativeTypeDefinition |
            Should -Match 'SameHeldFileFacts'
        $script:NativeTypeDefinition |
            Should -Match (
                'afterFinalPathBindingToken[\s\S]+?' +
                'StringComparison\.Ordinal'
            )
        $script:NativeTypeDefinition |
            Should -Match 'fileInfo\.hFile = rawHandle'
        $script:NativeTypeDefinition |
            Should -Match 'fileInfo\.pcwszFilePath = pathPointer'
        $script:NativeTypeDefinition |
            Should -Match 'DangerousAddRef'
        $script:NativeTypeDefinition |
            Should -Match 'DangerousRelease'
        $script:NativeTypeDefinition |
            Should -Match 'provider\.fOpenedFile != 0'
        $script:NativeTypeDefinition |
            Should -Match 'provider\.csSigners != 1'
        $script:NativeTypeDefinition |
            Should -Match 'WSS_GET_SECONDARY_SIG_COUNT'
        $script:NativeTypeDefinition |
            Should -Match 'signatureSettings\.cSecondarySigs != 0'
        $script:NativeTypeDefinition |
            Should -Match 'UInt32\.MaxValue'
        $script:NativeTypeDefinition |
            Should -Match (
                'WTHelperGetProvSignerFromChain\(' +
                '\s*providerPointer,\s*0,\s*false,\s*0\)'
            )
        $script:NativeTypeDefinition |
            Should -Match (
                'WTHelperGetProvCertFromChain' +
                '\(signerPointer,\s*0\)'
            )
        $script:NativeTypeDefinition |
            Should -Not -Match (
                'Get-AuthenticodeSignature|' +
                'File\.Open|new\s+FileStream|CreateFile'
            )
    }

    It 'rejects an unsigned MSIX while closing state and preserving the caller stream' {
        $path = Join-Path $TestDrive 'unsigned-probe.msix'
        [System.IO.File]::WriteAllBytes(
            $path,
            [byte[]]@(
                0x50, 0x4b, 0x03, 0x04,
                0x00, 0x00, 0x00, 0x00
            )
        )
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        try {
            $stream.Position = 3
            $result =
                $script:CddsiD027ClaudeMsixSameStateSignerObserver.
                    Invoke($stream)

            $result.WinVerifyTrustTrusted | Should -BeFalse
            $result.WinVerifyTrustStatus |
                Should -BeIn @(
                    'NoSignature',
                    'UnsupportedSubject',
                    'Untrusted',
                    'PolicyRejected'
                )
            $result.WinVerifyTrustNativeStatusHex |
                Should -Match '^0x[0-9A-F]{8}$'
            $result.CallerFileHandleSupplied | Should -BeTrue
            $result.FinalPathStableAcrossVerification |
                Should -BeTrue
            $result.FileFactsStableAcrossVerification |
                Should -BeTrue
            $result.StateCloseCompleted | Should -BeTrue
            $result.StateCloseNativeStatusHex |
                Should -BeExactly '0x00000000'
            $result.StreamPositionRestored | Should -BeTrue
            $result.FinalPathBindingToken |
                Should -BeExactly (
                    Get-CddsiPathBindingToken -Path $path
                )
            $result.PrimarySignerCertificateDerBytes |
                Should -BeNullOrEmpty
            $result.PrimarySignerCertificateDerLengthBytes |
                Should -BeNullOrEmpty
            $stream.Position | Should -Be 3
            $stream.CanRead | Should -BeTrue
            $stream.SafeFileHandle.IsClosed | Should -BeFalse
            foreach (
                $stringValue in @(
                    $result.PSObject.Properties |
                        Where-Object {
                            $_.Value -is [string]
                        } |
                        ForEach-Object {
                            [string]$_.Value
                        }
                )
            ) {
                $stringValue.IndexOf(
                    $path,
                    [StringComparison]::OrdinalIgnoreCase
                ) | Should -Be -1
            }
        }
        finally {
            $stream.Dispose()
        }
    }

    It 'fails closed for a disposed stream without disclosing its path' {
        $path = Join-Path $TestDrive 'disposed-probe.msix'
        [System.IO.File]::WriteAllBytes(
            $path,
            [byte[]]@(0x50, 0x4b, 0x03, 0x04)
        )
        $stream = [System.IO.FileStream]::new(
            $path,
            [System.IO.FileMode]::Open,
            [System.IO.FileAccess]::Read,
            [System.IO.FileShare]::Read
        )
        $stream.Dispose()

        $result =
            $script:CddsiD027ClaudeMsixSameStateSignerObserver.
                Invoke($stream)

        $result.WinVerifyTrustTrusted | Should -BeFalse
        $result.WinVerifyTrustStatus |
            Should -BeExactly 'InvalidInput'
        $result.FinalPathBindingToken |
            Should -BeNullOrEmpty
        $result.PrimarySignerCertificateDerBytes |
            Should -BeNullOrEmpty
        foreach (
            $stringValue in @(
                $result.PSObject.Properties |
                    Where-Object {
                        $_.Value -is [string]
                    } |
                    ForEach-Object {
                        [string]$_.Value
                    }
            )
        ) {
            $stringValue.IndexOf(
                $path,
                [StringComparison]::OrdinalIgnoreCase
            ) | Should -Be -1
        }
    }

    It 'records the clean-sentinel preload guard and no session authority' {
        $script:DesktopMsixSource |
            Should -Match '\$preexistingTypes\.Count -ne 0'
        $script:DesktopMsixSource |
            Should -Match '\[object\]::ReferenceEquals'
        $script:DesktopMsixSource |
            Should -Match (
                'NativeAssemblyFullName'
            )
        $script:DesktopMsixSource |
            Should -Not -Match (
                'Enable-CddsiD027ClaudeLiveSessionAuthorization|' +
                'Assert-CddsiD027ClaudeLiveContext'
            )
        @(
            Get-Command `
                'Enable-CddsiD027ClaudeLiveSessionAuthorization',
                'Assert-CddsiD027ClaudeLiveContext' `
                -ErrorAction SilentlyContinue
        ).Count | Should -Be 0
    }
}
