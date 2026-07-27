[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InnoSetupCompiler,
    [string]$GoogleWebAppUrl = $env:SOUNDFLOW_GOOGLE_WEBAPP_URL,
    [string]$LarkWebhook = $env:SOUNDFLOW_LARK_WEBHOOK,
    [switch]$RequireLarkWebhook,
    [string]$SignTool,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'SoundFlowDesktop.iss'
$staging = Join-Path $PSScriptRoot 'staging'
New-Item -ItemType Directory -Path $staging -Force | Out-Null
if ($GoogleWebAppUrl) {
    if ($GoogleWebAppUrl -notmatch '^https://script\.google\.com/') {
        throw 'SOUNDFLOW_GOOGLE_WEBAPP_URL must be a Google Apps Script web app URL.'
    }
    Set-Content -LiteralPath (Join-Path $staging 'google-webapp-url.txt') -Value $GoogleWebAppUrl -Encoding Ascii
}
if ($LarkWebhook) {
    if ($LarkWebhook -notmatch '^https://open\.larksuite\.com/open-apis/bot/v2/hook/[A-Za-z0-9-]+$') {
        throw 'SOUNDFLOW_LARK_WEBHOOK is not a valid Lark custom-bot webhook URL.'
    }
    Set-Content -LiteralPath (Join-Path $staging 'lark-webhook.txt') -Value $LarkWebhook -Encoding Ascii
} elseif ($RequireLarkWebhook) {
    throw 'SOUNDFLOW_LARK_WEBHOOK must be configured as a GitHub Actions secret for distributable builds.'
}

try {
    & $InnoSetupCompiler $scriptPath
    if ($LASTEXITCODE -ne 0) { throw "Inno Setup failed with exit code $LASTEXITCODE." }
    $setup = Join-Path $PSScriptRoot 'output\SoundFlowDesktop-Setup.exe'
    if (-not (Test-Path -LiteralPath $setup)) { throw 'Setup output was not created.' }
    if ($SignTool -and $CertificateThumbprint) {
        & $SignTool sign /sha1 $CertificateThumbprint /fd SHA256 /tr $TimestampUrl /td SHA256 $setup
        if ($LASTEXITCODE -ne 0) { throw "Package signing failed with exit code $LASTEXITCODE." }
    }
    $hash = (Get-FileHash -LiteralPath $setup -Algorithm SHA256).Hash.ToLowerInvariant()
    Set-Content -LiteralPath ($setup + '.sha256') -Value ($hash + '  SoundFlowDesktop-Setup.exe') -Encoding Ascii
    Write-Host "Built: $setup"
} finally {
    Remove-Item -LiteralPath (Join-Path $staging 'google-webapp-url.txt') -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $staging 'lark-webhook.txt') -Force -ErrorAction SilentlyContinue
}
