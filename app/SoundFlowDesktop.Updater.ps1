[CmdletBinding()]
param(
    [string]$ProgramDirectory = (Join-Path $env:LOCALAPPDATA 'Programs\SoundFlowDesktop'),
    [string]$DataDirectory = (Join-Path $env:LOCALAPPDATA 'SoundFlowDesktop')
)

$ErrorActionPreference = 'Stop'
$bootstrapPath = Join-Path $ProgramDirectory 'app\SoundFlowDesktop.Bootstrap.ps1'
if (Test-Path -LiteralPath $bootstrapPath) { . $bootstrapPath }
Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'UPDATE_REQUESTED'
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

function Send-SfdUpdateLarkNotification {
    param(
        [Parameter(Mandatory = $true)]$Event,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Summary
    )
    if (-not $config.lark.enabled) { return 'SKIPPED' }
    try {
        $secretPath = Join-Path $DataDirectory ([string]$config.lark.webhook_dpapi_file)
        if (-not (Test-Path -LiteralPath $secretPath -PathType Leaf)) { throw 'Lark webhook configuration is unavailable.' }
        $protected = (Get-Content -LiteralPath $secretPath -Raw -Encoding Ascii).Trim()
        $webhook = Unprotect-SfdDpapiValue -ProtectedText $protected
        $delivery = Invoke-SfdLarkSummary -WebhookUrl $webhook -Title $Title -Summary $Summary
        if (-not $delivery.Delivered) { throw [string]$delivery.Error }
        return 'SUCCESS'
    } catch {
        $queuePath = Join-Path $DataDirectory 'queue\delivery.jsonl'
        $null = Add-SfdQueueRecord -Path $queuePath -EventId ([string]$Event.Event_ID) -Destination LARK_SUMMARY -Payload @{
            title = $Title
            summary = $Summary
        } -LastError $_.Exception.Message
        return 'QUEUED'
    }
}

$startedEvent = New-SfdEvent -IncidentId $updateIncident -Category UPDATE -Action APP_UPDATE_STARTED -Status STARTED -Mode UPDATE -Context $eventContext -Result @{ Previous_App_Version = $info.Version }
New-Item -ItemType Directory -Path (Split-Path -Parent $updateEventPath) -Force | Out-Null
($startedEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $updateEventPath -Encoding UTF8
$null = Send-SfdUpdateLarkNotification -Event $startedEvent -Title 'SoundFlow Desktop - UPDATE STARTED' -Summary ("Device: {0}`nUser: {1}`nCurrent version: {2}" -f $env:COMPUTERNAME, $env:USERNAME, $info.Version)

try {
    $result = Invoke-SfdUpdate -MetadataUrl ([string]$config.update.metadata_url) -CurrentVersion $info.Version -TrustedPublisher ([string]$config.update.trusted_publisher) -StagingDirectory $staging -ProgramDirectory $ProgramDirectory -RollbackDirectory $rollback -ProductionLockPath $productionLock -AllowDowngrade:([bool]$config.update.allow_downgrade)
    $completedEvent = New-SfdEvent -IncidentId $updateIncident -Category UPDATE -Action APP_UPDATE_COMPLETED -Status SUCCESS -Mode UPDATE -Context $eventContext -Result @{
        Previous_App_Version = $info.Version
        Action_Result = [string]$result.Status
        After_Status = [string]$result.Version
    }
    if ($result.Version) { $completedEvent.App_Version = [string]$result.Version }
    ($completedEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $updateEventPath -Encoding UTF8
    $null = Send-SfdUpdateLarkNotification -Event $completedEvent -Title 'SoundFlow Desktop - UPDATE COMPLETED' -Summary ("Device: {0}`nUser: {1}`nStatus: {2}`nVersion: {3}" -f $env:COMPUTERNAME, $env:USERNAME, $result.Status, $result.Version)
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'UPDATE_COMPLETED' -Message ([string]$result.Status)
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        ('Update status: ' + $result.Status),
        'SoundFlow Desktop - Update',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Information
    ) | Out-Null
    exit 0
} catch {
    $failureMessage = $_.Exception.Message
    $failedEvent = New-SfdEvent -IncidentId $updateIncident -Category UPDATE -Action APP_UPDATE_FAILED -Status FAILED -Mode UPDATE -Context $eventContext -Result @{
        Previous_App_Version = $info.Version
        Error_Code = 'UPDATE_FAILED'
        Error_Details = $failureMessage
    }
    ($failedEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $updateEventPath -Encoding UTF8
    $null = Send-SfdUpdateLarkNotification -Event $failedEvent -Title 'SoundFlow Desktop - UPDATE FAILED' -Summary ("Device: {0}`nUser: {1}`nError: {2}" -f $env:COMPUTERNAME, $env:USERNAME, (Protect-SfdSecretText -Text $failureMessage))
    Write-SfdBootstrapLog -DataDirectory $DataDirectory -Action 'UPDATE_FAILED' -Message $failureMessage
    Add-Type -AssemblyName System.Windows.Forms
    [System.Windows.Forms.MessageBox]::Show(
        (Protect-SfdSecretText -Text $failureMessage),
        'SoundFlow Desktop - Update failed',
        [System.Windows.Forms.MessageBoxButtons]::OK,
        [System.Windows.Forms.MessageBoxIcon]::Error
    ) | Out-Null
    exit 1
}
