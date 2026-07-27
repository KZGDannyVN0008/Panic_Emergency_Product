[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('CONNECT', 'RECONNECT', 'DISCONNECT')][string]$Action,
    [string]$ProgramDirectory = 'C:\Program Files\SoundFlowDesktop',
    [string]$DataDirectory = 'C:\ProgramData\SoundFlowDesktop',
    [switch]$Revoke
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force
$configurationPath = Join-Path $DataDirectory 'config\deployment.json'
$configuration = Import-SfdDeploymentConfiguration -Path $configurationPath -AllowDisconnectedIntegrations
$tokenPath = Resolve-SfdUserCredentialPath -DataDirectory $DataDirectory -RelativePath ([string]$configuration.google_sheets.token_dpapi_file)

if ($Action -eq 'DISCONNECT') {
    $result = Disconnect-SfdGoogleSheets -TokenPath $tokenPath -Revoke:$Revoke
    $configuration.google_sheets.enabled = $false
    Write-SfdJsonAtomic -Path $configurationPath -Value $configuration
    Write-Host $result.Status
    exit 0
}

$oauthPath = Join-Path $DataDirectory ([string]$configuration.google_sheets.oauth_client_file)
$result = Connect-SfdGoogleSheets -OAuthClientPath $oauthPath -TokenPath $tokenPath -SpreadsheetId ([string]$configuration.google_sheets.spreadsheet_id) -TabName ([string]$configuration.google_sheets.tab_name)
$configuration.google_sheets.enabled = [bool]$result.Connected
Write-SfdJsonAtomic -Path $configurationPath -Value $configuration
Write-Host $result.Status
