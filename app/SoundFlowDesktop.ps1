[CmdletBinding()]
param(
    [string]$ProgramDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\SoundFlowDesktop'),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'SoundFlowDesktop')
)

$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) { . $bootstrapPath }
try {
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'APP_OPENED'
    Add-Type -AssemblyName System.Windows.Forms
    Add-Type -AssemblyName System.Drawing
} catch {
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'APP_OPEN_FAILED' -Message $_.Exception.Message
    Show-SfdBootstrapError -Message $_.Exception.Message
    exit 1
}
$iconPath = Join-Path $ProgramDirectory 'assets\SoundFlowDesktop.ico'

function New-SfdButton {
    param([string]$Text, [int]$Top)
    $button = New-Object System.Windows.Forms.Button
    $button.Text = $Text
    $button.Width = 300
    $button.Height = 52
    $button.Left = 42
    $button.Top = $Top
    $button.Font = New-Object System.Drawing.Font -ArgumentList 'Segoe UI', 11, ([System.Drawing.FontStyle]::Bold)
    $button.BackColor = [System.Drawing.Color]::FromArgb(32, 142, 82)
    $button.ForeColor = [System.Drawing.Color]::White
    $button.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $button
}

function Start-SfdWorker {
    param([string]$Mode)
    $worker = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Worker.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $worker + '" -Mode ' + $Mode + ' -ProgramDirectory "' + $ProgramDirectory + '" -DataDirectory "' + $DataDirectory + '"'
    if ($Mode -eq 'PRODUCTION') {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs
    } else {
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden
    }
}

function Show-SfdRunDialog {
    $runForm = New-Object System.Windows.Forms.Form
    $runForm.Text = 'SoundFlow Desktop - Run'
    $runForm.ClientSize = New-Object System.Drawing.Size -ArgumentList 384, 210
    $runForm.StartPosition = 'CenterScreen'
    $runForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
    $runForm.MaximizeBox = $false
    if (Test-Path -LiteralPath $iconPath) { $runForm.Icon = [System.Drawing.Icon]::new($iconPath) }
    $dryButton = New-SfdButton -Text 'DRY RUN - Scan Only' -Top 34
    $productionButton = New-SfdButton -Text 'PRODUCTION - Emergency Clean' -Top 112
    $dryButton.Add_Click({ $runForm.Close(); Start-SfdWorker -Mode DRY_RUN })
    $productionButton.Add_Click({ $runForm.Close(); Start-SfdWorker -Mode PRODUCTION })
    $runForm.Controls.AddRange(@($dryButton, $productionButton))
    $runForm.AcceptButton = $dryButton
    $runForm.ShowDialog() | Out-Null
}

$form = New-Object System.Windows.Forms.Form
$form.Text = 'SoundFlow Desktop'
$form.ClientSize = New-Object System.Drawing.Size -ArgumentList 384, 210
$form.StartPosition = 'CenterScreen'
$form.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::FixedDialog
$form.MaximizeBox = $false
if (Test-Path -LiteralPath $iconPath) { $form.Icon = [System.Drawing.Icon]::new($iconPath) }
$updateButton = New-SfdButton -Text 'UPDATE' -Top 34
$runButton = New-SfdButton -Text 'RUN' -Top 112
$updateButton.Add_Click({
    $updater = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Updater.ps1'
    $arguments = '-NoProfile -ExecutionPolicy Bypass -File "' + $updater + '" -ProgramDirectory "' + $ProgramDirectory + '" -DataDirectory "' + $DataDirectory + '"'
    Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -WindowStyle Hidden
})
$runButton.Add_Click({ Show-SfdRunDialog })
$form.Controls.AddRange(@($updateButton, $runButton))
$form.ShowDialog() | Out-Null
