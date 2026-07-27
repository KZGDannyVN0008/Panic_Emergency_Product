[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('INSTALL', 'UNINSTALL')][string]$Action,
    [string]$ProgramDirectory = 'C:\Program Files\SoundFlowDesktop',
    [string]$DataDirectory = 'C:\ProgramData\SoundFlowDesktop'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force
try {
    $result = Write-SfdLifecycleEvent -Action $Action -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
    Write-Host ("Lifecycle event persisted: {0}" -f $result.IncidentId)
    exit 0
} catch {
    Write-Warning (Protect-SfdSecretText -Text $_.Exception.Message)
    exit 2
}
