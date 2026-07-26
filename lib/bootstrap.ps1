# bootstrap.ps1 - Project-root discovery and dependency loading only.
# Loading this file has no network, user-profile, process-control or system side effects.

$script:CddsiLibDirectory = $PSScriptRoot
$script:CddsiProjectRoot = Split-Path -Parent $script:CddsiLibDirectory
$script:CddsiLibrariesImported = $false
$script:CddsiLibraryLoadOrder = @(
    'logger.ps1',
    'common.ps1',
    'stage-policy.ps1',
    'vm-calibration.ps1',
    'release-facts.ps1',
    'release-artifact.ps1',
    'state.ps1',
    'execution-context.ps1',
    'd027-snapshot-authorization.ps1',
    'fake-providers.ps1',
    'state-store.ps1',
    'desktop-env-check.ps1',
    'desktop-msix.ps1',
    'git-for-windows.ps1',
    'cowork-readiness.ps1',
    'deepseek-api.ps1',
    'credential-helper-release.ps1',
    'desktop-config.ps1',
    'desktop-lifecycle.ps1',
    'desktop-acceptance.ps1',
    'orchestrator.ps1'
)

function Get-CddsiProjectRoot {
    [CmdletBinding()]
    param()

    return $script:CddsiProjectRoot
}

function Import-CddsiLibraries {
    [CmdletBinding()]
    param()

    if (-not $script:CddsiLibrariesImported) {
        throw '库未在 bootstrap 的调用作用域中完成加载。请重新 dot-source bootstrap.ps1。'
    }
}

function Initialize-CddsiScript {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [Alias('ExecutionContext')]$Context,

        [string]$ScriptName = 'cddsi',
        [ValidateSet('TestSafe', 'DryRun', 'Live')][string]$Mode = 'TestSafe',
        [switch]$EnableFileLogging,

        [AllowNull()]
        [System.Collections.IDictionary]$PathTokenValues
    )

    Import-CddsiLibraries
    Assert-CddsiExecutionContext -ExecutionContext $Context -ExpectedMode $Mode | Out-Null
    Initialize-CddsiLogger -ExecutionContext $Context -ScriptName $ScriptName -Mode $Mode -EnableFileLogging:$EnableFileLogging -PathTokenValues $PathTokenValues | Out-Null
    return $script:CddsiProjectRoot
}

# Dot-source at bootstrap scope so public functions remain visible to the
# caller. This only defines functions and constants; it performs no workflow.
foreach ($fileName in $script:CddsiLibraryLoadOrder) {
    $path = Join-Path $script:CddsiLibDirectory $fileName
    . $path
}
$script:CddsiLibrariesImported = $true
