[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('INSTALL', 'UNINSTALL')][string]$Action,
    [string]$ProgramDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\SoundFlowDesktop'),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'SoundFlowDesktop')
)

$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) { . $bootstrapPath }
Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action ($Action + '_REQUESTED')
try {
    Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force
    $result = Write-SfdLifecycleEvent -Action $Action -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action ($Action + '_COMPLETED') -Message $result.IncidentId
    exit 0
} catch {
    $message = if (Get-Command Protect-SfdSecretText -ErrorAction SilentlyContinue) { Protect-SfdSecretText -Text $_.Exception.Message } else { $_.Exception.Message }
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action ($Action + '_FAILED') -Message $message
    exit 2
}
