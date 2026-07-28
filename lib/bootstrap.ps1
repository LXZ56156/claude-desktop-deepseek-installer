# bootstrap.ps1 only locates and loads the small D-027 practical runtime.

$script:CddsiProjectRoot = Split-Path -Parent $PSScriptRoot
$script:CddsiLibraryLoadOrder = @(
    'common.ps1'
    'installer.ps1'
    'configuration.ps1'
    'workflow.ps1'
)
$script:CddsiLibrariesImported = $false

foreach ($fileName in $script:CddsiLibraryLoadOrder) {
    . (Join-Path $PSScriptRoot $fileName)
}
$script:CddsiLibrariesImported = $true

function Import-CddsiLibraries {
    [CmdletBinding()]
    param()

    if (-not $script:CddsiLibrariesImported) {
        throw 'D-027 practical runtime libraries were not loaded.'
    }
}
