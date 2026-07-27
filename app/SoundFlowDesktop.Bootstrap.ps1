Set-StrictMode -Version 2.0

function Protect-SfdBootstrapText {
    param([AllowNull()][string]$Text)
    if ($null -eq $Text) { return '' }
    ($Text -replace 'https://open\.larksuite\.com/open-apis/bot/v2/hook/[A-Za-z0-9-]+', '[REDACTED_LARK_WEBHOOK]') -replace '[\r\n]+', ' '
}

function Write-SfdBootstrapLog {
    param(
        [Parameter(Mandatory = $true)][string]$DataDirectory,
        [Parameter(Mandatory = $true)][string]$Action,
        [AllowNull()][string]$Message = ''
    )
    try {
        $logDirectory = Join-Path $DataDirectory 'logs'
        New-Item -ItemType Directory -Path $logDirectory -Force | Out-Null
        $line = "{0}`t{1}`t{2}" -f (Get-Date).ToUniversalTime().ToString('o'), $Action, (Protect-SfdBootstrapText -Text $Message)
        Add-Content -LiteralPath (Join-Path $logDirectory 'application.log') -Value $line -Encoding UTF8
    } catch {}
}

function Show-SfdBootstrapError {
    param([Parameter(Mandatory = $true)][string]$Message)
    $safeMessage = Protect-SfdBootstrapText -Text $Message
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            $safeMessage,
            'SoundFlow Desktop',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Error
        ) | Out-Null
    } catch {
        try {
            $shell = New-Object -ComObject WScript.Shell
            $null = $shell.Popup($safeMessage, 0, 'SoundFlow Desktop', 16)
        } catch {}
    }
}

function Show-SfdBootstrapInformation {
    param([Parameter(Mandatory = $true)][string]$Message)
    try {
        Add-Type -AssemblyName System.Windows.Forms
        [System.Windows.Forms.MessageBox]::Show(
            $Message,
            'SoundFlow Desktop',
            [System.Windows.Forms.MessageBoxButtons]::OK,
            [System.Windows.Forms.MessageBoxIcon]::Information
        ) | Out-Null
    } catch {}
}
