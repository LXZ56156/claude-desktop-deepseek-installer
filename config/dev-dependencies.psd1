@{
    SchemaVersion = 1

    Pester = @{
        Version                = '5.6.1'
        ProvenanceStatus       = 'VendoredPinnedTree'
        RootRelativePath       = '.dev/modules/Pester/5.6.1'
        ManifestRelativePath   = 'Pester.psd1'
        ExpectedFileCount      = 20
        ExpectedTotalBytes     = 1145990
        ExpectedManifestSha256 = '644e3dd029b4f2fdd7b99395446dcd7211d5a1027f51285759c2465e6df671aa'
        ExpectedTreeSha256     = 'b4992fea36787bda13b0301e2c459a03910ada99c73fd5b3ed9943470fd84460'
        LicenseRelativePath    = 'third-party/Pester-5.6.1-LICENSE.txt'
        ExpectedLicenseBytes   = 11357
        ExpectedLicenseSha256  = 'c71d239df91726fc519c6eb72d318ec65820627232b2f796219e87dcf35d0ab4'
        TreeHashFormat         = 'ordinal-relative-path|sha256-lower|length joined with LF, UTF-8 without BOM'
        OfficialGalleryUrl     = 'https://www.powershellgallery.com/packages/Pester/5.6.1'
        OfficialProjectUrl     = 'https://github.com/Pester/Pester'
        OfficialLicenseUrl     = 'https://www.apache.org/licenses/LICENSE-2.0.html'
    }

    IsolationEvidenceSuites = @(
        @{
            RelativePath      = 'tests/Contract/IsolationEvidence.Tests.ps1'
            ExpectedTestCount = 16
        }
        @{
            RelativePath      = 'tests/Unit/FakeProviders.Tests.ps1'
            ExpectedTestCount = 10
        }
        @{
            RelativePath      = 'tests/Contract/SafetyBoundary.Tests.ps1'
            ExpectedTestCount = 6
        }
    )
}
