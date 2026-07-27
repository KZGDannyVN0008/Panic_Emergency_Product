[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$InnoSetupCompiler,
    [string]$OAuthClientPath,
    [string]$SignTool,
    [string]$CertificateThumbprint,
    [string]$TimestampUrl = 'http://timestamp.digicert.com'
)

$ErrorActionPreference = 'Stop'
$root = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$scriptPath = Join-Path $PSScriptRoot 'SoundFlowDesktop.iss'
$staging = Join-Path $PSScriptRoot 'staging'
New-Item -ItemType Directory -Path $staging -Force | Out-Null
if ($OAuthClientPath) {
    $oauth = Get-Content -LiteralPath $OAuthClientPath -Raw | ConvertFrom-Json
    if (-not $oauth.installed.client_id) { throw 'An installed-desktop Google OAuth client is required.' }
    Copy-Item -LiteralPath $OAuthClientPath -Destination (Join-Path $staging 'google-oauth-client.json') -Force
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
    Remove-Item -LiteralPath (Join-Path $staging 'google-oauth-client.json') -Force -ErrorAction SilentlyContinue
}
