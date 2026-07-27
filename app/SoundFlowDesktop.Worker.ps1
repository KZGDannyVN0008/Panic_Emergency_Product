[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][ValidateSet('DRY_RUN', 'PRODUCTION')][string]$Mode,
    [string]$ProgramDirectory = 'C:\Program Files\SoundFlowDesktop',
    [string]$DataDirectory = 'C:\ProgramData\SoundFlowDesktop'
)

$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $ProgramDirectory 'src\SoundFlowDesktop\SoundFlowDesktop.psd1') -Force

if ($Mode -eq 'PRODUCTION') {
    Add-Type -AssemblyName System.Windows.Forms
    $config = Import-SfdDeploymentConfiguration -Path (Join-Path $DataDirectory 'config\deployment.json') -AllowDisconnectedIntegrations
    $message = @"
AUTHORIZED EMERGENCY CLEANUP

Device: $env:COMPUTERNAME
Employee: $($config.full_name)
Mode: PRODUCTION

This will stop approved applications, remove manifest-approved local sessions
and data, verify the result, persist reports/queues, and then perform:
$($config.final_action)

Continue?
"@
    $answer = [System.Windows.Forms.MessageBox]::Show(
        $message,
        'SoundFlow Desktop - Production confirmation',
        [System.Windows.Forms.MessageBoxButtons]::YesNo,
        [System.Windows.Forms.MessageBoxIcon]::Warning,
        [System.Windows.Forms.MessageBoxDefaultButton]::Button2
    )
    if ($answer -ne [System.Windows.Forms.DialogResult]::Yes) {
        $cancelIncident = 'SFD-CANCELLED-' + [guid]::NewGuid().ToString('N').Substring(0, 12).ToUpperInvariant()
        $cancelContext = @{
            Full_Name = [string]$config.full_name
            Work_Email = [string]$config.work_email
            Department = [string]$config.department
            Device_ID = $env:COMPUTERNAME
            Device_Name = $env:COMPUTERNAME
            OS_Name = 'Windows'
            OS_Version = [string][Environment]::OSVersion.Version
            Windows_Username = $env:USERNAME
            Is_Administrator = $true
        }
        $cancelEvent = New-SfdEvent -IncidentId $cancelIncident -Category PRODUCTION_RUN -Action PRODUCTION_FAILED -Status CANCELLED -Mode PRODUCTION -Context $cancelContext -Result @{
            Action_Result = 'USER_CANCELLED_CONFIRMATION'
            Final_Action = 'NONE'
        }
        $cancelPath = Join-Path $DataDirectory ('state\' + $cancelIncident + '.events.jsonl')
        New-Item -ItemType Directory -Path (Split-Path -Parent $cancelPath) -Force | Out-Null
        ($cancelEvent | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $cancelPath -Encoding UTF8
        exit 2
    }
}

try {
    $result = Start-SfdIncident -Mode $Mode -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
    Write-Host ("Incident completed: {0}`nReport: {1}" -f $result.IncidentId, $result.ReportPath)
    exit 0
} catch {
    Write-Error (Protect-SfdSecretText -Text $_.Exception.Message)
    exit 1
}
