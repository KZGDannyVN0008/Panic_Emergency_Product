[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$FullName,
    [Parameter(Mandatory = $true)][string]$WorkEmail,
    [Parameter(Mandatory = $true)][string]$Department,
    [ValidateSet('NONE', 'LOGOUT', 'SHUTDOWN')][string]$FinalAction = 'LOGOUT',
    [string]$LarkWebhook,
    [string]$LarkWebhookFile,
    [string]$ProgramDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\SoundFlowDesktop'),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'SoundFlowDesktop'),
    [switch]$ConnectGoogleSheets
)

$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) { . $bootstrapPath }
Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'INSTALL_CONFIGURATION_STARTED'
trap {
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'INSTALL_CONFIGURATION_FAILED' -Message $_.Exception.Message
    exit 1
}
# On re-install, the data directory may still exist with ACLs set by a previous
# installation. Grant the current user full access BEFORE trying to write any
# files, so Configure.ps1 is never blocked by leftover permission restrictions.
if ($env:OS -eq 'Windows_NT' -and (Test-Path -LiteralPath $DataDirectory)) {
    $currentSid = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    icacls.exe $DataDirectory /grant ($currentSid + ':(OI)(CI)F') /T /C | Out-Null
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
        oauth_client_file = 'config\google-oauth-client.json'
        token_dpapi_file = 'credentials\users\{SID}\google-token.dpapi'
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
if ($LarkWebhookFile -and (Test-Path -LiteralPath $LarkWebhookFile)) {
    Remove-Item -LiteralPath $LarkWebhookFile -Force -ErrorAction SilentlyContinue
}
Write-SfdJsonAtomic -Path (Join-Path $paths.Config 'deployment.json') -Value $configuration

if ($ConnectGoogleSheets) {
    $oauthClientPath = Join-Path $paths.Data $configuration.google_sheets.oauth_client_file
    if (Test-Path -LiteralPath $oauthClientPath) {
        try {
            $tokenPath = Resolve-SfdUserCredentialPath -DataDirectory $paths.Data -RelativePath $configuration.google_sheets.token_dpapi_file
            $connection = Connect-SfdGoogleSheets -OAuthClientPath $oauthClientPath -TokenPath $tokenPath -SpreadsheetId $configuration.google_sheets.spreadsheet_id -TabName $configuration.google_sheets.tab_name
            if ($connection.Connected) {
                $configuration.google_sheets.enabled = $true
                Write-SfdJsonAtomic -Path (Join-Path $paths.Config 'deployment.json') -Value $configuration
                Write-Host 'Google Sheets: Connected'
            }
        } catch {
            Write-Warning ('Google Sheets: Not Connected. ' + (Protect-SfdSecretText -Text $_.Exception.Message))
        }
    } else {
        Write-Warning 'Google Sheets: Not Connected. The deployment OAuth client was not included.'
    }
}

# Restrict writable application state to administrators, SYSTEM, and the
# installing Windows user. Use the SID to avoid DOMAIN\username resolution
# failures on workgroup machines or accounts with non-ASCII characters.
if ($env:OS -eq 'Windows_NT') {
    $currentSid = '*' + [Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    icacls.exe $paths.Data /inheritance:r /grant:r 'SYSTEM:(OI)(CI)F' 'BUILTIN\Administrators:(OI)(CI)F' ($currentSid + ':(OI)(CI)F') /T /C | Out-Null
}

$null = Write-SfdLifecycleEvent -Action INSTALL -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'INSTALL_CONFIGURATION_COMPLETED'
Write-Host 'SoundFlow Desktop configuration completed.'
