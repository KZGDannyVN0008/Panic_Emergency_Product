@{
    RootModule = 'SoundFlowDesktop.psm1'
    ModuleVersion = '1.0.1'
    GUID = 'd17dd3f1-415b-4816-a9e2-20bdc7932115'
    Author = 'KZG'
    CompanyName = 'KZG'
    Copyright = '(c) KZG. All rights reserved.'
    Description = 'SoundFlow Desktop Windows emergency scan and authorized cleanup engine.'
    PowerShellVersion = '5.1'
    CompatiblePSEditions = @('Desktop', 'Core')
    FunctionsToExport = @(
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
    CmdletsToExport = @()
    VariablesToExport = @()
    AliasesToExport = @()
    PrivateData = @{
        PSData = @{
            Tags = @('Windows', 'Security', 'Emergency', 'Cleanup')
            ProjectUri = 'https://github.com/KZGDannyVN0008/Panic_Emergency_Product'
        }
    }
}
