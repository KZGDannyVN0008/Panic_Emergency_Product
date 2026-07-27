Set-StrictMode -Version 2.0

$script:SfdEventCategories = @('APPLICATION_LIFECYCLE', 'DRY_RUN', 'PRODUCTION_RUN', 'SCAN', 'CLEANUP', 'UNINSTALL_TARGET', 'CLOUD_SYNC', 'NOTIFICATION', 'UPDATE', 'SYSTEM_ACTION', 'ERROR')
$script:SfdEventStatuses = @('STARTED', 'SUCCESS', 'PARTIAL_SUCCESS', 'FAILED', 'QUEUED', 'SKIPPED', 'PROTECTED', 'CANCELLED')

function Get-SfdEventValue {
    param($Object, [string]$Name, $Default = $null)
    if ($null -eq $Object) { return $Default }
    if ($Object -is [Collections.IDictionary]) {
        if ($Object.Contains($Name)) { return $Object[$Name] }
        return $Default
    }
    $property = $Object.PSObject.Properties[$Name]
    if ($property) { return $property.Value }
    $Default
}

function New-SfdEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$IncidentId,
        [Parameter(Mandatory = $true)][ValidateSet('APPLICATION_LIFECYCLE', 'DRY_RUN', 'PRODUCTION_RUN', 'SCAN', 'CLEANUP', 'UNINSTALL_TARGET', 'CLOUD_SYNC', 'NOTIFICATION', 'UPDATE', 'SYSTEM_ACTION', 'ERROR')][string]$Category,
        [Parameter(Mandatory = $true)][string]$Action,
        [Parameter(Mandatory = $true)][ValidateSet('STARTED', 'SUCCESS', 'PARTIAL_SUCCESS', 'FAILED', 'QUEUED', 'SKIPPED', 'PROTECTED', 'CANCELLED')][string]$Status,
        [Parameter(Mandatory = $true)][ValidateSet('DRY_RUN', 'PRODUCTION', 'INSTALL', 'UNINSTALL', 'UPDATE')][string]$Mode,
        [hashtable]$Context = @{},
        [hashtable]$Target = @{},
        [hashtable]$Result = @{}
    )

    $now = (Get-Date).ToUniversalTime()
    $info = Get-SfdApplicationInfo
    $errorDetails = [string](Get-SfdEventValue -Object $Result -Name 'Error_Details' -Default '')
    $event = [ordered]@{
        Event_ID = New-SfdIdentifier -Kind EVENT
        Incident_ID = $IncidentId
        Event_Timestamp = $now.ToString('o')
        Event_Date = $now.ToString('yyyy-MM-dd')
        Event_Category = $Category
        Event_Action = $Action
        Event_Status = $Status
        Mode = $Mode
        Full_Name = [string](Get-SfdEventValue $Context 'Full_Name' '')
        Work_Email = [string](Get-SfdEventValue $Context 'Work_Email' '')
        Department = [string](Get-SfdEventValue $Context 'Department' '')
        Device_ID = [string](Get-SfdEventValue $Context 'Device_ID' '')
        Device_Name = [string](Get-SfdEventValue $Context 'Device_Name' '')
        OS_Name = [string](Get-SfdEventValue $Context 'OS_Name' '')
        OS_Version = [string](Get-SfdEventValue $Context 'OS_Version' '')
        Windows_Username = [string](Get-SfdEventValue $Context 'Windows_Username' '')
        Is_Administrator = [bool](Get-SfdEventValue $Context 'Is_Administrator' $false)
        App_Version = $info.Version
        Previous_App_Version = [string](Get-SfdEventValue $Result 'Previous_App_Version' '')
        Target_Type = [string](Get-SfdEventValue $Target 'Target_Type' '')
        Target_Name = [string](Get-SfdEventValue $Target 'Target_Name' '')
        Target_Path = [string](Get-SfdEventValue $Target 'Target_Path' '')
        Installed = Get-SfdEventValue $Target 'Installed'
        Running = Get-SfdEventValue $Target 'Running'
        Profiles_Found = Get-SfdEventValue $Target 'Profiles_Found'
        Files_Found = Get-SfdEventValue $Target 'Files_Found'
        Estimated_Size_MB = Get-SfdEventValue $Target 'Estimated_Size_MB'
        Before_Status = [string](Get-SfdEventValue $Result 'Before_Status' '')
        Action_Result = [string](Get-SfdEventValue $Result 'Action_Result' '')
        After_Status = [string](Get-SfdEventValue $Result 'After_Status' '')
        Verification_Result = [string](Get-SfdEventValue $Result 'Verification_Result' '')
        Error_Code = [string](Get-SfdEventValue $Result 'Error_Code' '')
        Error_Details = Protect-SfdSecretText -Text $errorDetails
        Lark_Summary_Status = [string](Get-SfdEventValue $Result 'Lark_Summary_Status' '')
        Lark_Report_Status = [string](Get-SfdEventValue $Result 'Lark_Report_Status' '')
        Queue_Status = [string](Get-SfdEventValue $Result 'Queue_Status' '')
        Final_Action = [string](Get-SfdEventValue $Result 'Final_Action' '')
        Duration_Seconds = Get-SfdEventValue $Result 'Duration_Seconds'
    }
    [pscustomobject]$event
}
