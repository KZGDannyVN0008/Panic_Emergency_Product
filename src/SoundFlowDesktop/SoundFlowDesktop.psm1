Set-StrictMode -Version 2.0

$moduleRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$moduleFiles = @(
    'Core.psm1',
    'Configuration.psm1',
    'Manifest.psm1',
    'Safety.psm1',
    'Events.psm1',
    'Queue.psm1',
    'Discovery.psm1',
    'Cleanup.psm1',
    'Reporting.psm1',
    'Lark.psm1',
    'GoogleSheets.psm1',
    'Updater.psm1',
    'Incident.psm1'
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
