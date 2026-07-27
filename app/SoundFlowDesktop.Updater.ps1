[CmdletBinding()]
param(
    [string]$ProgramDirectory = 'C:\Program Files\SoundFlowDesktop',
    [string]$DataDirectory = 'C:\ProgramData\SoundFlowDesktop'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force
$config = Import-SfdDeploymentConfiguration -Path (Join-Path $DataDirectory 'config\deployment.json') -AllowDisconnectedIntegrations
$info = Get-SfdApplicationInfo
$staging = Join-Path $DataDirectory ('state\update-' + [guid]::NewGuid().ToString('N'))
$rollback = Join-Path $DataDirectory ('state\rollback\' + $info.Version)
$productionLock = Join-Path $DataDirectory 'locks\production.lock'
$updateIncident = 'SFD-UPDATE-' + [guid]::NewGuid().ToString('N').Substring(0, 12).ToUpperInvariant()
$updateEventPath = Join-Path $DataDirectory ('state\' + $updateIncident + '.events.jsonl')
$identity = [Security.Principal.WindowsIdentity]::GetCurrent()
$isAdministrator = ([Security.Principal.WindowsPrincipal]::new($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$eventContext = @{
    Full_Name = [string]$config.full_name
    Work_Email = [string]$config.work_email
    Department = [string]$config.department
    Device_ID = $env:COMPUTERNAME
    Device_Name = $env:COMPUTERNAME
    OS_Name = 'Windows'
    OS_Version = [string][Environment]::OSVersion.Version
    Windows_Username = $env:USERNAME
    Is_Administrator = $isAdministrator
}
$startedEvent = New-SfdEvent -IncidentId $updateIncident -Category UPDATE -Action APP_UPDATE_STARTED -Status STARTED -Mode UPDATE -Context $eventContext -Result @{ Previous_App_Version = $info.Version }
New-Item -ItemType Directory -Path (Split-Path -Parent $updateEventPath) -Force | Out-Null
($startedEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $updateEventPath -Encoding UTF8

try {
    $result = Invoke-SfdUpdate -MetadataUrl ([string]$config.update.metadata_url) -CurrentVersion $info.Version -TrustedPublisher ([string]$config.update.trusted_publisher) -StagingDirectory $staging -ProgramDirectory $ProgramDirectory -RollbackDirectory $rollback -ProductionLockPath $productionLock -AllowDowngrade:([bool]$config.update.allow_downgrade)
    $completedEvent = New-SfdEvent -IncidentId $updateIncident -Category UPDATE -Action APP_UPDATE_COMPLETED -Status SUCCESS -Mode UPDATE -Context $eventContext -Result @{
        Previous_App_Version = $info.Version
        Action_Result = [string]$result.Status
        After_Status = [string]$result.Version
    }
    if ($result.Version) { $completedEvent.App_Version = [string]$result.Version }
    ($completedEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $updateEventPath -Encoding UTF8
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        ('Update status: ' + $result.Status),
        'SoundFlow Desktop - Update',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 0
} catch {
    $failedEvent = New-SfdEvent -IncidentId $updateIncident -Category UPDATE -Action APP_UPDATE_FAILED -Status FAILED -Mode UPDATE -Context $eventContext -Result @{
        Previous_App_Version = $info.Version
        Error_Code = 'UPDATE_FAILED'
        Error_Details = $_.Exception.Message
    }
    ($failedEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $updateEventPath -Encoding UTF8
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        (Protect-SfdSecretText -Text $_.Exception.Message),
        'SoundFlow Desktop - Update failed',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
