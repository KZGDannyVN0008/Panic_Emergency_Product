[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('CONNECT', 'RECONNECT', 'DISCONNECT')][string]$Action,
    [string]$WebAppUrl,
    [string]$ProgramDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\SoundFlowDesktop'),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'SoundFlowDesktop')
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force
$configurationPath = Join-Path $DataDirectory 'config\deployment.json'
$configuration = Import-SfdDeploymentConfiguration -Path $configurationPath -AllowDisconnectedIntegrations
$credPath = Join-Path $DataDirectory ([string]$configuration.google_sheets.webapp_url_dpapi_file)

if ($Action -eq 'DISCONNECT') {
    if (Test-Path -LiteralPath $credPath) {
        Remove-Item -LiteralPath $credPath -Force -ErrorAction SilentlyContinue
    }
    $configuration.google_sheets.enabled = $false
    Write-SfdJsonAtomic -Path $configurationPath -Value $configuration
    Write-Host 'Google Sheets: Not Connected'
    exit 0
}

if (-not $WebAppUrl) { throw 'A Google Apps Script web app URL is required (-WebAppUrl).' }
$protected = Protect-SfdDpapiValue -PlainText $WebAppUrl
New-Item -ItemType Directory -Path (Split-Path -Parent $credPath) -Force | Out-Null
Set-Content -LiteralPath $credPath -Value $protected -Encoding Ascii
$configuration.google_sheets.enabled = $true
Write-SfdJsonAtomic -Path $configurationPath -Value $configuration
Write-Host 'Google Sheets: Connected'
