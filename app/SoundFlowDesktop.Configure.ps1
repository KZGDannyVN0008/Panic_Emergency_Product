[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FullName,
    [Parameter(Mandatory = $true)][string]$WorkEmail,
    [Parameter(Mandatory = $true)][string]$Department,
    [ValidateSet('NONE', 'LOGOUT', 'SHUTDOWN')][string]$FinalAction = 'LOGOUT',
    [string]$LarkWebhook,
    [string]$LarkWebhookFile,
    [string]$GoogleWebAppUrl,
    [string]$GoogleWebAppUrlFile,
    [string]$ProgramDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\SoundFlowDesktop'),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'SoundFlowDesktop')
)

$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) { . $bootstrapPath }
Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'INSTALL_CONFIGURATION_STARTED'
trap {
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'INSTALL_CONFIGURATION_FAILED' -Message $_.Exception.Message
    exit 1
}
# Recover from a previous installation that may have applied overly restrictive
# ACLs to the data directory. takeown retakes ownership (always allowed for the
# file owner), then icacls restores inherited permissions so normal access works.
if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $DataDirectory)) {
    takeown.exe /F $DataDirectory /R /D Y 2>$null | Out-Null
    icacls.exe $DataDirectory /reset /T /C | Out-Null
}
Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force
$paths = Get-SfdPaths -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
foreach ($directory in @($paths.Config, $paths.Credentials, $paths.Logs, $paths.Reports, $paths.Queue, $paths.State, $paths.Locks)) {
    New-Item -ItemType Directory -Path $directory -Force | Out-Null
}
if (-not $LarkWebhook -and $LarkWebhookFile -and (Test-Path -LiteralPath $LarkWebhookFile -PathType Leaf)) {
    $LarkWebhook = (Get-Content -LiteralPath $LarkWebhookFile -Raw -Encoding Ascii).Trim()
}

$configuration = [ordered]@{
    schema_version = 1
    full_name = $FullName.Trim()
    work_email = $WorkEmail.Trim()
    department = $Department.Trim()
    final_action = $FinalAction
    lark = [ordered]@{
        enabled = [bool]$LarkWebhook
        webhook_dpapi_file = 'credentials\lark-webhook.dpapi'
        app_id = ''
        app_secret_dpapi_file = 'credentials\lark-app-secret.dpapi'
        receive_id = ''
        receive_id_type = 'chat_id'
    }
    google_sheets = [ordered]@{
        enabled = $false
        spreadsheet_id = '13IfeDIiDPJlzXBMLrpYDvjqRsoElLLy28y1pBVgjsr0'
        tab_name = 'Detail_Log'
        webapp_url_dpapi_file = 'credentials\google-webapp-url.dpapi'
    }
    update = [ordered]@{
        metadata_url = 'https://github.com/KZGDannyVN0008/Panic_Emergency_Product/releases/latest/download/update-manifest.json'
        trusted_publisher = 'KZG'
        allow_downgrade = $false
    }
}

if ($LarkWebhook) {
    if ($LarkWebhook -notmatch '^https://open\.larksuite\.com/open-apis/bot/v2/hook/[A-Za-z0-9-]+$') {
        throw 'The Lark webhook format is invalid.'
    }
    $protectedWebhook = Protect-SfdDpapiValue -PlainText $LarkWebhook
    Set-Content -LiteralPath (Join-Path $paths.Data $configuration.lark.webhook_dpapi_file) -Value $protectedWebhook -Encoding Ascii
}
if (-not $GoogleWebAppUrl -and $GoogleWebAppUrlFile -and (Test-Path -LiteralPath $GoogleWebAppUrlFile -PathType Leaf)) {
    $GoogleWebAppUrl = (Get-Content -LiteralPath $GoogleWebAppUrlFile -Raw -Encoding Ascii).Trim()
}
if ($LarkWebhookFile -and (Test-Path -LiteralPath $LarkWebhookFile)) {
    Remove-Item -LiteralPath $LarkWebhookFile -Force -ErrorAction SilentlyContinue
}
if ($GoogleWebAppUrlFile -and (Test-Path -LiteralPath $GoogleWebAppUrlFile)) {
    Remove-Item -LiteralPath $GoogleWebAppUrlFile -Force -ErrorAction SilentlyContinue
}
if ($GoogleWebAppUrl) {
    $protectedUrl = Protect-SfdDpapiValue -PlainText $GoogleWebAppUrl
    $credDir = Split-Path -Parent (Join-Path $paths.Data $configuration.google_sheets.webapp_url_dpapi_file)
    New-Item -ItemType Directory -Path $credDir -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $paths.Data $configuration.google_sheets.webapp_url_dpapi_file) -Value $protectedUrl -Encoding Ascii
    $configuration.google_sheets.enabled = $true
    Write-Host 'Google Sheets: Connected'
}
Write-SfdJsonAtomic -Path (Join-Path $paths.Config 'deployment.json') -Value $configuration


$null = Write-SfdLifecycleEvent -Action INSTALL -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'INSTALL_CONFIGURATION_COMPLETED'
Write-Host 'SoundFlow Desktop configuration completed.'
