# Third-Party Notices

## Pester 5.6.1

This repository vendors the locked Pester 5.6.1 runtime tree under
`.dev/modules/Pester/5.6.1` solely as a development and test dependency. It is
not a product runtime dependency and must not be included in the installer
release package.

Pester is copyright the Pester Team and is licensed under the Apache License
2.0.

The full license text distributed with this vendored development dependency is
`third-party/Pester-5.6.1-LICENSE.txt`.

- Official PowerShell Gallery package: <https://www.powershellgallery.com/packages/Pester/5.6.1>
- Official project: <https://github.com/Pester/Pester>
- Apache License 2.0: <https://www.apache.org/licenses/LICENSE-2.0.html>

The exact vendored file count, byte count, manifest SHA-256, and whole-tree
SHA-256 are recorded in `config/dev-dependencies.psd1`. The repository verifier
does not download, install, update, repair, or import Pester.
