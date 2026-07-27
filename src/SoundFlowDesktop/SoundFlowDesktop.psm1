Set-StrictMode -Version 2.0

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleFiles = @(
    'Core.ps1',
    'Configuration.ps1',
    'Manifest.ps1',
    'Safety.ps1',
    'Events.ps1',
    'Queue.ps1',
    'Discovery.ps1',
    'Cleanup.ps1',
    'Reporting.ps1',
    'Lark.ps1',
    'GoogleSheets.ps1',
    'Updater.ps1',
    'Incident.ps1'
)

foreach ($moduleFile in $moduleFiles) {
    . (Join-Path $moduleRoot $moduleFile)
}

Export-ModuleMember -Function @(
    'Get-SfdApplicationInfo',
    'Get-SfdPaths',
    'Read-SfdJson',
    'Write-SfdJsonAtomic',
    'Protect-SfdSecretText',
    'Protect-SfdDpapiValue',
    'Unprotect-SfdDpapiValue',
    'Resolve-SfdUserCredentialPath',
    'Import-SfdDeploymentConfiguration',
    'Import-SfdTargetManifest',
    'Test-SfdTargetManifest',
    'Resolve-SfdTargetPath',
    'Test-SfdCleanupPath',
    'New-SfdEvent',
    'Add-SfdQueueRecord',
    'Invoke-SfdQueueRetry',
    'Invoke-SfdDiscovery',
    'Invoke-SfdTargetCleanup',
    'New-SfdTextReport',
    'Invoke-SfdLarkSummary',
    'Invoke-SfdLarkReportUpload',
    'Connect-SfdGoogleSheets',
    'Disconnect-SfdGoogleSheets',
    'Write-SfdGoogleSheetEvents',
    'Invoke-SfdUpdate',
    'Write-SfdLifecycleEvent',
    'Start-SfdIncident'
)
