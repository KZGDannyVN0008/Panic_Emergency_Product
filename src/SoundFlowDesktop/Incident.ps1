Set-StrictMode -Version 2.0

function Get-SfdExecutionContext {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Configuration)

    $isAdministrator = $false
    if ($env:OS -eq 'Windows_NT') {
        $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
        $principal = [Security.Principal.WindowsPrincipal]::new($identity)
        $isAdministrator = $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    }
    $deviceId = $env:COMPUTERNAME
    if ($env:OS -eq 'Windows_NT') {
        try {
            $machineGuid = (Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Cryptography' -Name MachineGuid -ErrorAction Stop).MachineGuid
            if ($machineGuid) { $deviceId = [string]$machineGuid }
        } catch {}
    }
    $os = [Environment]::OSVersion
    @{
        Full_Name = [string]$Configuration.full_name
        Work_Email = [string]$Configuration.work_email
        Department = [string]$Configuration.department
        Device_ID = $deviceId
        Device_Name = $env:COMPUTERNAME
        OS_Name = if ($env:OS -eq 'Windows_NT') { 'Windows' } else { [string]$os.Platform }
        OS_Version = [string]$os.Version
        Windows_Username = $env:USERNAME
        Is_Administrator = $isAdministrator
    }
}

function Write-SfdLocalEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Events
    )
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    foreach ($event in $Events) {
        ($event | ConvertTo-Json -Depth 30 -Compress) | Add-Content -LiteralPath $Path -Encoding UTF8
    }
}

function New-SfdTargetEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$IncidentId,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$DiscoveryResult,
        [string]$Action = 'SCAN_TARGET',
        [string]$Status = 'SUCCESS',
        $CleanupResult,
        $AfterDiscoveryResult
    )
    $files = @($DiscoveryResult.Locations | Measure-Object -Property Files -Sum).Sum
    $bytes = @($DiscoveryResult.Locations | Measure-Object -Property Bytes -Sum).Sum
    $profiles = @($DiscoveryResult.Locations | Measure-Object -Property Profiles -Sum).Sum
    $paths = @($DiscoveryResult.Locations | Where-Object { $_.Exists } | ForEach-Object { $_.Path })
    $actionResult = if ($CleanupResult) { [string]$CleanupResult.Result } else { [string]$DiscoveryResult.Result }
    $afterStatus = ''
    $verificationResult = 'NOT_APPLICABLE'
    if ($CleanupResult -and $AfterDiscoveryResult) {
        $remainingPaths = @($AfterDiscoveryResult.Locations | Where-Object { $_.Exists }).Count
        $remainingFiles = @($AfterDiscoveryResult.Locations | Measure-Object -Property Files -Sum).Sum
        $stateVerified = if ($CleanupResult.VerificationStrategy -eq 'DIRECTORY_EMPTY') { [int]$remainingFiles -eq 0 } else { $remainingPaths -eq 0 }
        $verificationResult = if ($CleanupResult.Result -in @('CLEANED', 'UNINSTALLED') -and -not $AfterDiscoveryResult.Running -and $stateVerified) { 'VERIFICATION_PASSED' } else { 'VERIFICATION_FAILED' }
        $afterStatus = [string]$AfterDiscoveryResult.Result
    }
    $eventCategory = if ($CleanupResult -and $CleanupResult.Result -eq 'UNINSTALLED') {
        'UNINSTALL_TARGET'
    } elseif ($DiscoveryResult.Category -eq 'CLOUD_SYNC') {
        'CLOUD_SYNC'
    } elseif ($CleanupResult) {
        'CLEANUP'
    } else {
        'SCAN'
    }
    $eventAction = if ($CleanupResult -and $CleanupResult.Result -eq 'UNINSTALLED') {
        'UNINSTALL_TARGET_APP'
    } elseif ($CleanupResult -and $DiscoveryResult.TargetId -eq 'cloud.onedrive') {
        'ONEDRIVE_DISCONNECT'
    } else {
        $Action
    }
    New-SfdEvent -IncidentId $IncidentId -Category $eventCategory -Action $eventAction -Status $Status -Mode $Mode -Context $Context -Target @{
        Target_Type = [string]$DiscoveryResult.Category
        Target_Name = [string]$DiscoveryResult.DisplayName
        Target_Path = $paths -join '; '
        Installed = [bool]$DiscoveryResult.Installed
        Running = [bool]$DiscoveryResult.Running
        Profiles_Found = [int]$profiles
        Files_Found = [int]$files
        Estimated_Size_MB = [math]::Round(([double]$bytes / 1MB), 3)
    } -Result @{
        Before_Status = [string]$DiscoveryResult.Result
        Action_Result = $actionResult
        After_Status = $afterStatus
        Verification_Result = $verificationResult
    }
}

function Get-SfdConfigurationSecret {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$DataDirectory,
        [AllowNull()][string]$RelativePath
    )
    if (-not $RelativePath) { return '' }
    $path = Join-Path $DataDirectory $RelativePath
    if (-not (Test-Path -LiteralPath $path)) { return '' }
    $protected = (Get-Content -LiteralPath $path -Raw -Encoding Ascii).Trim()
    Unprotect-SfdDpapiValue -ProtectedText $protected
}

function Invoke-SfdOperationalDelivery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][object[]]$Events,
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [Parameter(Mandatory = $true)][string]$SummaryTitle,
        [Parameter(Mandatory = $true)][string]$SummaryBody,
        [switch]$SummaryOnly
    )

    $queuePath = Join-Path $Paths.Queue 'delivery.jsonl'
    $summaryResult = [pscustomobject]@{ Delivered = $false; Status = 'SKIPPED'; Error = '' }
    $reportResult = [pscustomobject]@{ Delivered = $false; Status = 'SKIPPED'; Error = '' }
    $deliveryEventId = [string]$Events[$Events.Count - 1].Event_ID
    if ($Configuration.lark.enabled) {
        try {
            $webhook = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath $Configuration.lark.webhook_dpapi_file
            if (-not $webhook) { throw 'Lark summary webhook is not configured.' }
            $summaryResult = Invoke-SfdLarkSummary -WebhookUrl $webhook -Title $SummaryTitle -Summary $SummaryBody
        } catch {
            $summaryResult = [pscustomobject]@{ Delivered = $false; Status = 'QUEUED'; Error = Protect-SfdSecretText -Text $_.Exception.Message }
        }
        if (-not $summaryResult.Delivered) {
            $null = Add-SfdQueueRecord -Path $queuePath -EventId $deliveryEventId -Destination LARK_SUMMARY -Payload @{
                title = $SummaryTitle
                summary = $SummaryBody
            } -LastError $summaryResult.Error
        }
        if (-not $SummaryOnly) {
            try {
                $appSecret = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath $Configuration.lark.app_secret_dpapi_file
                $reportResult = Invoke-SfdLarkReportUpload -ReportPath $ReportPath -AppId ([string]$Configuration.lark.app_id) -AppSecret $appSecret -ReceiveId ([string]$Configuration.lark.receive_id) -ReceiveIdType $(if ($Configuration.lark.receive_id_type) { [string]$Configuration.lark.receive_id_type } else { 'chat_id' })
            } catch {
                $reportResult = [pscustomobject]@{ Delivered = $false; Status = 'QUEUED'; Error = Protect-SfdSecretText -Text $_.Exception.Message }
            }
            if (-not $reportResult.Delivered) {
                $null = Add-SfdQueueRecord -Path $queuePath -EventId $deliveryEventId -Destination LARK_REPORT -Payload @{
                    report_path = $ReportPath
                } -LastError $reportResult.Error
            }
        }
    }

    $sheetStatus = 'SKIPPED'
    if ($Configuration.google_sheets.enabled) {
        try {
            $webAppUrl = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath ([string]$Configuration.google_sheets.webapp_url_dpapi_file)
            $null = Write-SfdGoogleSheetEvents -WebAppUrl $webAppUrl -TabName ([string]$Configuration.google_sheets.tab_name) -Events $Events
            $sheetStatus = 'SUCCESS'
        } catch {
            $sheetStatus = 'QUEUED'
            foreach ($event in $Events) {
                $null = Add-SfdQueueRecord -Path $queuePath -EventId ([string]$event.Event_ID) -Destination GOOGLE_SHEETS -Payload $event -LastError $_.Exception.Message
            }
        }
    }
    [pscustomobject]@{
        LarkSummaryStatus = $summaryResult.Status
        LarkReportStatus = $reportResult.Status
        GoogleSheetsStatus = $sheetStatus
        QueuePath = $queuePath
    }
}

function Invoke-SfdConfiguredQueueRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)]$Paths
    )
    $queuePath = Join-Path $Paths.Queue 'delivery.jsonl'
    if (-not (Test-Path -LiteralPath $queuePath)) {
        return [pscustomobject]@{ Processed = 0; Delivered = 0; Remaining = 0 }
    }
    $handler = {
        param($item)
        switch ([string]$item.destination) {
            'LARK_SUMMARY' {
                $webhook = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath $Configuration.lark.webhook_dpapi_file
                if (-not $webhook) { return $false }
                $result = Invoke-SfdLarkSummary -WebhookUrl $webhook -Title ([string]$item.payload.title) -Summary ([string]$item.payload.summary)
                return [bool]$result.Delivered
            }
            'LARK_REPORT' {
                $appSecret = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath $Configuration.lark.app_secret_dpapi_file
                $result = Invoke-SfdLarkReportUpload -ReportPath ([string]$item.payload.report_path) -AppId ([string]$Configuration.lark.app_id) -AppSecret $appSecret -ReceiveId ([string]$Configuration.lark.receive_id) -ReceiveIdType $(if ($Configuration.lark.receive_id_type) { [string]$Configuration.lark.receive_id_type } else { 'chat_id' })
                return [bool]$result.Delivered
            }
            'GOOGLE_SHEETS' {
                $webAppUrl = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath ([string]$Configuration.google_sheets.webapp_url_dpapi_file)
                $result = Write-SfdGoogleSheetEvents -WebAppUrl $webAppUrl -TabName ([string]$Configuration.google_sheets.tab_name) -Events @($item.payload)
                return $result.Status -eq 'SUCCESS'
            }
            default { return $false }
        }
    }
    Invoke-SfdQueueRetry -Path $queuePath -DeliveryHandler $handler
}

function Write-SfdDeliveryOutcomeEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$IncidentId,
        [Parameter(Mandatory = $true)][string]$Mode,
        [Parameter(Mandatory = $true)]$Context,
        [Parameter(Mandatory = $true)]$Delivery,
        [Parameter(Mandatory = $true)]$Configuration,
        [Parameter(Mandatory = $true)]$Paths,
        [Parameter(Mandatory = $true)][string]$EventPath
    )
    $outcomes = @(
        @{ Action = 'LARK_SUMMARY_SEND'; Value = [string]$Delivery.LarkSummaryStatus },
        @{ Action = 'LARK_REPORT_SEND'; Value = [string]$Delivery.LarkReportStatus },
        @{ Action = 'GOOGLE_SHEET_WRITE'; Value = [string]$Delivery.GoogleSheetsStatus }
    )
    $events = New-Object System.Collections.Generic.List[object]
    foreach ($outcome in $outcomes) {
        $eventStatus = if ($outcome.Value -eq 'SUCCESS') { 'SUCCESS' } elseif ($outcome.Value -in @('QUEUED', 'PENDING_CREDENTIALS')) { 'QUEUED' } else { 'SKIPPED' }
        $event = New-SfdEvent -IncidentId $IncidentId -Category NOTIFICATION -Action $outcome.Action -Status $eventStatus -Mode $Mode -Context $Context -Result @{
            Action_Result = $outcome.Value
            Queue_Status = if ($eventStatus -eq 'QUEUED') { 'QUEUED' } else { 'NOT_QUEUED' }
        }
        $events.Add($event)
    }
    Write-SfdLocalEvents -Path $EventPath -Events $events.ToArray()
    if ($Configuration.google_sheets.enabled) {
        try {
            $webAppUrl = Get-SfdConfigurationSecret -DataDirectory $Paths.Data -RelativePath ([string]$Configuration.google_sheets.webapp_url_dpapi_file)
            $null = Write-SfdGoogleSheetEvents -WebAppUrl $webAppUrl -TabName ([string]$Configuration.google_sheets.tab_name) -Events $events.ToArray()
        } catch {
            $queuePath = Join-Path $Paths.Queue 'delivery.jsonl'
            foreach ($event in $events) {
                $null = Add-SfdQueueRecord -Path $queuePath -EventId ([string]$event.Event_ID) -Destination GOOGLE_SHEETS -Payload $event -LastError $_.Exception.Message
            }
        }
    }
    $events.ToArray()
}

function Write-SfdLifecycleEvent {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('INSTALL', 'UNINSTALL')][string]$Action,
        [Parameter(Mandatory = $true)][string]$ProgramDirectory,
        [Parameter(Mandatory = $true)][string]$DataDirectory
    )
    $paths = Get-SfdPaths -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
    foreach ($directory in @($paths.Reports, $paths.Queue, $paths.State)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $configuration = Import-SfdDeploymentConfiguration -Path (Join-Path $paths.Config 'deployment.json') -AllowDisconnectedIntegrations
    $context = Get-SfdExecutionContext -Configuration $configuration
    $incidentId = New-SfdIdentifier -Kind INCIDENT
    $eventAction = if ($Action -eq 'INSTALL') { 'APP_INSTALL' } else { 'APP_UNINSTALL' }
    $event = New-SfdEvent -IncidentId $incidentId -Category APPLICATION_LIFECYCLE -Action $eventAction -Status SUCCESS -Mode $Action -Context $context
    $eventPath = Join-Path $paths.State ($incidentId + '.events.jsonl')
    Write-SfdLocalEvents -Path $eventPath -Events @($event)
    $reportPath = Join-Path $paths.Reports ($incidentId + '.txt')
    Set-Content -LiteralPath $reportPath -Value @(
        'SoundFlow Desktop lifecycle event',
        'Incident ID: ' + $incidentId,
        'Action: ' + $eventAction,
        'Device: ' + $context.Device_Name,
        'Employee: ' + $context.Full_Name,
        'Persisted UTC: ' + (Get-Date).ToUniversalTime().ToString('o')
    ) -Encoding UTF8
    $delivery = Invoke-SfdOperationalDelivery -Configuration $configuration -Paths $paths -Events @($event) -ReportPath $reportPath -SummaryTitle ('SoundFlow Desktop - ' + $eventAction.Replace('_', ' ')) -SummaryBody ("Incident: {0}`nDevice: {1}`nEmployee: {2}`nAction: {3}`nStatus: persisted" -f $incidentId, $context.Device_Name, $context.Full_Name, $eventAction) -SummaryOnly
    $null = Write-SfdDeliveryOutcomeEvents -IncidentId $incidentId -Mode $Action -Context $context -Delivery $delivery -Configuration $configuration -Paths $paths -EventPath $eventPath
    [pscustomobject]@{ IncidentId = $incidentId; EventPath = $eventPath; Delivery = $delivery }
}

function Start-SfdIncident {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('DRY_RUN', 'PRODUCTION')][string]$Mode,
        [Parameter(Mandatory = $true)][string]$ProgramDirectory,
        [Parameter(Mandatory = $true)][string]$DataDirectory,
        [switch]$NoSystemAction
    )

    $startTime = Get-Date
    $paths = Get-SfdPaths -ProgramDirectory $ProgramDirectory -DataDirectory $DataDirectory
    foreach ($directory in @($paths.Config, $paths.Credentials, $paths.Logs, $paths.Reports, $paths.Queue, $paths.State, $paths.Locks)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }
    $configuration = Import-SfdDeploymentConfiguration -Path (Join-Path $paths.Config 'deployment.json') -AllowDisconnectedIntegrations
    $manifest = Import-SfdTargetManifest -Path (Join-Path $paths.Program 'config\targets.windows.v1.json')
    $context = Get-SfdExecutionContext -Configuration $configuration
    $null = Invoke-SfdConfiguredQueueRetry -Configuration $configuration -Paths $paths
    if ($Mode -eq 'PRODUCTION' -and -not $context.Is_Administrator) {
        throw 'Production requires standard UAC elevation.'
    }
    $incidentId = New-SfdIdentifier -Kind INCIDENT
    $eventPath = Join-Path $paths.State ($incidentId + '.events.jsonl')
    $reportPath = Join-Path $paths.Reports ($incidentId + '.txt')
    $lockStream = $null
    try {
        if ($Mode -eq 'PRODUCTION') {
            $lockPath = Join-Path $paths.Locks 'production.lock'
            try {
                $lockStream = [IO.File]::Open($lockPath, [IO.FileMode]::OpenOrCreate, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
            } catch {
                throw 'Another Production run is already active.'
            }
        }
        $events = New-Object System.Collections.Generic.List[object]
        $startAction = if ($Mode -eq 'DRY_RUN') { 'DRY_RUN_STARTED' } else { 'PRODUCTION_STARTED' }
        $startCategory = if ($Mode -eq 'DRY_RUN') { 'DRY_RUN' } else { 'PRODUCTION_RUN' }
        $startEvent = New-SfdEvent -IncidentId $incidentId -Category $startCategory -Action $startAction -Status STARTED -Mode $Mode -Context $context
        $events.Add($startEvent)
        Write-SfdLocalEvents -Path $eventPath -Events @($startEvent)

        if ($configuration.lark.enabled -or $configuration.google_sheets.enabled) {
            $startedReport = Join-Path $paths.Reports ($incidentId + '.started.txt')
            Set-Content -LiteralPath $startedReport -Value @(
                ('SoundFlow Desktop ' + $Mode + ' started'),
                'Incident ID: ' + $incidentId,
                'Device: ' + $context.Device_Name,
                'Employee: ' + $context.Full_Name
            ) -Encoding UTF8
            $startedDelivery = Invoke-SfdOperationalDelivery -Configuration $configuration -Paths $paths -Events @($startEvent) -ReportPath $startedReport -SummaryTitle ('SoundFlow Desktop - ' + $startAction.Replace('_', ' ')) -SummaryBody ("Incident: {0}`nDevice: {1}`nUser: {2}`nMode: {3}`nStatus: run started" -f $incidentId, $context.Device_Name, $context.Windows_Username, $Mode) -SummaryOnly
            $null = Write-SfdDeliveryOutcomeEvents -IncidentId $incidentId -Mode $Mode -Context $context -Delivery $startedDelivery -Configuration $configuration -Paths $paths -EventPath $eventPath
        }

        $profilePaths = @(Get-SfdAccessibleUserProfiles -IsAdministrator ([bool]$context.Is_Administrator))
        $beforeList = New-Object System.Collections.Generic.List[object]
        for ($profileIndex = 0; $profileIndex -lt $profilePaths.Count; $profileIndex++) {
            foreach ($profileResult in @(Invoke-SfdDiscovery -Manifest $manifest -UserProfile $profilePaths[$profileIndex] -ExcludeUnknownApplications:($profileIndex -gt 0))) {
                $beforeList.Add($profileResult)
            }
        }
        $before = $beforeList.ToArray()
        foreach ($targetResult in $before) {
            $targetEvent = New-SfdTargetEvent -IncidentId $incidentId -Mode $Mode -Context $context -DiscoveryResult $targetResult
            $events.Add($targetEvent)
            Write-SfdLocalEvents -Path $eventPath -Events @($targetEvent)
            foreach ($location in @($targetResult.Locations)) {
                foreach ($profileName in @($location.ProfileNames)) {
                    $profileEvent = New-SfdEvent -IncidentId $incidentId -Category SCAN -Action SCAN_TARGET -Status SUCCESS -Mode $Mode -Context $context -Target @{
                        Target_Type = [string]$targetResult.Category
                        Target_Name = ([string]$targetResult.DisplayName + ' profile')
                        Target_Path = Join-Path ([string]$location.Path) ([string]$profileName)
                        Installed = [bool]$targetResult.Installed
                        Running = [bool]$targetResult.Running
                        Profiles_Found = 1
                    } -Result @{ Before_Status = 'DETECTED'; Verification_Result = 'NOT_APPLICABLE' }
                    $events.Add($profileEvent)
                    Write-SfdLocalEvents -Path $eventPath -Events @($profileEvent)
                }
            }
        }
        $cleanupResults = @()
        $after = @()
        if ($Mode -eq 'PRODUCTION') {
            $protectedConfig = Read-SfdJson -Path (Join-Path $paths.Program 'config\protected-paths.json')
            $uninstallAllowlist = Read-SfdJson -Path (Join-Path $paths.Program 'config\uninstall-allowlist.json')
            $protectedPaths = @($protectedConfig.protected_literal_paths) + @($paths.Data)
            $activeSyncRoots = @(Get-SfdActiveSyncRoots)
            $detectedSupportedResults = @($before | Where-Object { $_.Result -eq 'DETECTED' -and $_.Supported })
            foreach ($detectedResult in $detectedSupportedResults) {
                $target = $manifest.targets | Where-Object { $_.target_id -eq $detectedResult.TargetId } | Select-Object -First 1
                if (-not $target) { continue }
                $targetEnvironmentMap = Get-SfdEnvironmentMap -UserProfile ([string]$detectedResult.UserProfile)
                $currentProfile = [Environment]::GetFolderPath('UserProfile')
                $credentialScopeAvailable = ([IO.Path]::GetFullPath([string]$detectedResult.UserProfile).TrimEnd('\') -eq [IO.Path]::GetFullPath($currentProfile).TrimEnd('\'))
                $cleanup = Invoke-SfdTargetCleanup -Target $target -EnvironmentMap $targetEnvironmentMap -ProtectedPaths $protectedPaths -ActiveSyncRoots $activeSyncRoots -CredentialScopeAvailable:$credentialScopeAvailable -Confirm:$false -WhatIf:$WhatIfPreference
                $cleanup | Add-Member -NotePropertyName UserProfile -NotePropertyValue ([string]$detectedResult.UserProfile)
                $cleanupResults += $cleanup
            }
            $afterList = New-Object System.Collections.Generic.List[object]
            for ($profileIndex = 0; $profileIndex -lt $profilePaths.Count; $profileIndex++) {
                foreach ($profileResult in @(Invoke-SfdDiscovery -Manifest $manifest -UserProfile $profilePaths[$profileIndex] -ExcludeUnknownApplications:($profileIndex -gt 0))) {
                    $afterList.Add($profileResult)
                }
            }
            $after = $afterList.ToArray()
            foreach ($cleanup in $cleanupResults) {
                $beforeResult = $before | Where-Object { $_.TargetId -eq $cleanup.TargetId -and $_.UserProfile -eq $cleanup.UserProfile } | Select-Object -First 1
                $afterResult = $after | Where-Object { $_.TargetId -eq $cleanup.TargetId -and $_.UserProfile -eq $cleanup.UserProfile } | Select-Object -First 1
                $target = $manifest.targets | Where-Object { $_.target_id -eq $cleanup.TargetId } | Select-Object -First 1
                $remainingPaths = @($afterResult.Locations | Where-Object { $_.Exists }).Count
                $remainingFiles = @($afterResult.Locations | Measure-Object -Property Files -Sum).Sum
                $stateRemains = if ($target.verification_strategy -eq 'DIRECTORY_EMPTY') { [int]$remainingFiles -gt 0 } else { $remainingPaths -gt 0 }
                $verificationFailed = $afterResult.Running -or $stateRemains
                if ($verificationFailed) {
                    if ($target -and $target.uninstall_allowed) {
                        $uninstallResult = Invoke-SfdAllowedUninstall -Target $target -Allowlist $uninstallAllowlist -Confirm:$false -WhatIf:$WhatIfPreference
                        $cleanup.Actions += [pscustomobject]@{ Type = 'UNINSTALL_FALLBACK'; Result = $uninstallResult.Result; Detail = $uninstallResult.Detail }
                        if ($uninstallResult.Result -eq 'UNINSTALLED') {
                            $rescanned = @(Invoke-SfdDiscovery -Manifest ([pscustomobject]@{ targets = @($target) }) -UserProfile ([string]$cleanup.UserProfile) -ExcludeUnknownApplications)
                            $afterResult = $rescanned | Select-Object -First 1
                            $remainingPaths = @($afterResult.Locations | Where-Object { $_.Exists }).Count
                            $verificationFailed = $afterResult.Running -or $remainingPaths -gt 0 -or $afterResult.Installed
                            if (-not $verificationFailed) { $cleanup.Result = 'UNINSTALLED' }
                        }
                    }
                }
                if ($verificationFailed -and $cleanup.Result -notin @('FAILED', 'PARTIAL_SUCCESS', 'PROTECTED')) {
                    $cleanup.Result = 'VERIFICATION_FAILED'
                }
                $status = if ($verificationFailed) { 'FAILED' } elseif ($cleanup.Result -in @('CLEANED', 'UNINSTALLED')) { 'SUCCESS' } elseif ($cleanup.Result -eq 'PARTIAL_SUCCESS') { 'PARTIAL_SUCCESS' } elseif ($cleanup.Result -eq 'PROTECTED') { 'PROTECTED' } else { 'FAILED' }
                $cleanupEvent = New-SfdTargetEvent -IncidentId $incidentId -Mode $Mode -Context $context -DiscoveryResult $beforeResult -Action CLEAN_TARGET -Status $status -CleanupResult $cleanup -AfterDiscoveryResult $afterResult
                $events.Add($cleanupEvent)
                Write-SfdLocalEvents -Path $eventPath -Events @($cleanupEvent)
            }
        }
        $null = New-SfdTextReport -Path $reportPath -IncidentId $incidentId -Mode $Mode -BeforeResults $before -CleanupResults $cleanupResults -AfterResults $after -Context $context
        $detectedCount = @($before | Where-Object { $_.Result -eq 'DETECTED' }).Count
        $failedCount = @($cleanupResults | Where-Object { $_.Result -in @('FAILED', 'PARTIAL_SUCCESS', 'PROTECTED', 'VERIFICATION_FAILED') }).Count
        $completionAction = if ($Mode -eq 'DRY_RUN') { 'DRY_RUN_COMPLETED' } else { 'PRODUCTION_COMPLETED' }
        $completionStatus = if ($failedCount) { 'PARTIAL_SUCCESS' } else { 'SUCCESS' }
        $completionEvent = New-SfdEvent -IncidentId $incidentId -Category $startCategory -Action $completionAction -Status $completionStatus -Mode $Mode -Context $context -Result @{
            Action_Result = if ($Mode -eq 'DRY_RUN') { 'SCAN_ONLY' } else { 'CLEANUP_AND_VERIFICATION' }
            Final_Action = [string]$configuration.final_action
            Duration_Seconds = [math]::Round(((Get-Date) - $startTime).TotalSeconds, 3)
        }
        $events.Add($completionEvent)
        Write-SfdLocalEvents -Path $eventPath -Events @($completionEvent)
        if ($Mode -eq 'PRODUCTION' -and [string]$configuration.final_action -in @('LOGOUT', 'SHUTDOWN')) {
            $systemAction = if ([string]$configuration.final_action -eq 'LOGOUT') { 'WINDOWS_LOGOUT' } else { 'WINDOWS_SHUTDOWN' }
            $systemEvent = New-SfdEvent -IncidentId $incidentId -Category SYSTEM_ACTION -Action $systemAction -Status STARTED -Mode $Mode -Context $context -Result @{
                Action_Result = 'PERSISTED_BEFORE_SYSTEM_ACTION'
                Final_Action = [string]$configuration.final_action
            }
            $events.Add($systemEvent)
            Write-SfdLocalEvents -Path $eventPath -Events @($systemEvent)
        }
        $eventsForFinalDelivery = if ($Mode -eq 'PRODUCTION') { @($events | Select-Object -Skip 1) } else { $events.ToArray() }
        $delivery = Invoke-SfdOperationalDelivery -Configuration $configuration -Paths $paths -Events $eventsForFinalDelivery -ReportPath $reportPath -SummaryTitle ('SoundFlow Desktop - ' + $completionAction.Replace('_', ' ')) -SummaryBody ("Incident: {0}`nDevice: {1}`nEmployee: {2}`nMode: {3}`nDetected targets: {4}`nTargets requiring attention: {5}`nReport persisted locally: yes" -f $incidentId, $context.Device_Name, $context.Full_Name, $Mode, $detectedCount, $failedCount)
        $null = Write-SfdDeliveryOutcomeEvents -IncidentId $incidentId -Mode $Mode -Context $context -Delivery $delivery -Configuration $configuration -Paths $paths -EventPath $eventPath

        if ($Mode -eq 'PRODUCTION' -and -not $NoSystemAction -and -not $WhatIfPreference) {
            if ([string]$configuration.final_action -eq 'LOGOUT') {
                shutdown.exe /l /f
            } elseif ([string]$configuration.final_action -eq 'SHUTDOWN') {
                shutdown.exe /s /f /t 0
            }
        }
        [pscustomobject]@{
            IncidentId = $incidentId
            Mode = $Mode
            ReportPath = $reportPath
            EventPath = $eventPath
            DetectedTargets = $detectedCount
            AttentionTargets = $failedCount
            Delivery = $delivery
        }
    } catch {
        if ($incidentId) {
            $errorEvent = New-SfdEvent -IncidentId $incidentId -Category ERROR -Action $(if ($Mode -eq 'PRODUCTION') { 'PRODUCTION_FAILED' } else { 'DRY_RUN_COMPLETED' }) -Status FAILED -Mode $Mode -Context $context -Result @{
                Error_Code = 'INCIDENT_FAILED'
                Error_Details = $_.Exception.Message
                Final_Action = 'NONE'
            }
            Write-SfdLocalEvents -Path $eventPath -Events @($errorEvent)
        }
        throw
    } finally {
        if ($lockStream) {
            $lockPath = $lockStream.Name
            $lockStream.Dispose()
            Remove-Item -LiteralPath $lockPath -Force -ErrorAction SilentlyContinue
        }
    }
}
