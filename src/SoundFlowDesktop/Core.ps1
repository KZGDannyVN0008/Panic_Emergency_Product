Set-StrictMode -Version 2.0

function Get-SfdApplicationInfo {
    [CmdletBinding()]
    param()

    [pscustomobject][ordered]@{
        ProductName = 'SoundFlow Desktop'
        ProductId = 'SoundFlowDesktop'
        Version = '1.0.0'
        Publisher = 'KZG'
        ProgramDirectory = 'C:\Program Files\SoundFlowDesktop'
        DataDirectory = 'C:\ProgramData\SoundFlowDesktop'
        UpdateRepository = 'KZGDannyVN0008/Panic_Emergency_Product'
    }
}

function Get-SfdPaths {
    [CmdletBinding()]
    param(
        [string]$ProgramDirectory,
        [string]$DataDirectory
    )

    $info = Get-SfdApplicationInfo
    if (-not $ProgramDirectory) { $ProgramDirectory = $info.ProgramDirectory }
    if (-not $DataDirectory) { $DataDirectory = $info.DataDirectory }

    [pscustomobject][ordered]@{
        Program = [IO.Path]::GetFullPath($ProgramDirectory)
        Data = [IO.Path]::GetFullPath($DataDirectory)
        Config = Join-Path $DataDirectory 'config'
        Credentials = Join-Path $DataDirectory 'credentials'
        Logs = Join-Path $DataDirectory 'logs'
        Reports = Join-Path $DataDirectory 'reports'
        Queue = Join-Path $DataDirectory 'queue'
        State = Join-Path $DataDirectory 'state'
        Locks = Join-Path $DataDirectory 'locks'
    }
}

function Read-SfdJson {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) {
        throw "JSON file was not found: $Path"
    }
    Get-Content -LiteralPath $Path -Raw -Encoding UTF8 | ConvertFrom-Json
}

function Write-SfdJsonAtomic {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Value
    )

    $parent = Split-Path -Parent $Path
    if (-not $parent) { throw "A parent directory is required: $Path" }
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ('.' + [IO.Path]::GetFileName($Path) + '.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $Value | ConvertTo-Json -Depth 30 | Set-Content -LiteralPath $temporary -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporary, $Path, $null, $true)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function New-SfdIdentifier {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][ValidateSet('INCIDENT', 'EVENT')][string]$Kind)

    $prefix = if ($Kind -eq 'INCIDENT') { 'SFD' } else { 'EVT' }
    '{0}-{1}-{2}' -f $prefix, (Get-Date).ToUniversalTime().ToString('yyyyMMddTHHmmssfffZ'), ([guid]::NewGuid().ToString('N').Substring(0, 12).ToUpperInvariant())
}

function Protect-SfdSecretText {
    [CmdletBinding()]
    param([AllowNull()][string]$Text)

    if (-not $Text) { return $Text }
    $redacted = $Text
    $redacted = $redacted -replace 'https://open\.larksuite\.com/open-apis/bot/v2/hook/[A-Za-z0-9-]+', '[REDACTED_LARK_WEBHOOK]'
    $redacted = $redacted -replace '(?i)(access_token|refresh_token|client_secret|authorization)\s*[:=]\s*[^,\s;]+', '$1=[REDACTED]'
    $redacted
}

function Resolve-SfdUserCredentialPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataDirectory,
        [Parameter(Mandatory = $true)][string]$RelativePath
    )
    $sid = if ($env:OS -eq 'Windows_NT') {
        [string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    } else {
        [Environment]::UserName
    }
    $safeSid = $sid -replace '[^A-Za-z0-9._-]', '_'
    Join-Path $DataDirectory ($RelativePath.Replace('{SID}', $safeSid))
}
