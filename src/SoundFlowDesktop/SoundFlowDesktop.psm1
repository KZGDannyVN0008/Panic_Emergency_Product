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
