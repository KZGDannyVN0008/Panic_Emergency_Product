Set-StrictMode -Version 2.0

function New-SfdTextReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$IncidentId,
        [Parameter(Mandatory = $true)][ValidateSet('DRY_RUN', 'PRODUCTION')][string]$Mode,
        [Parameter(Mandatory = $true)][object[]]$BeforeResults,
        [object[]]$CleanupResults = @(),
        [object[]]$AfterResults = @(),
        [Parameter(Mandatory = $true)]$Context
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $lines = New-Object System.Collections.Generic.List[string]
    $lines.Add('SoundFlow Desktop Incident Report')
    $lines.Add('Incident ID: ' + $IncidentId)
    $lines.Add('Generated UTC: ' + (Get-Date).ToUniversalTime().ToString('o'))
    $lines.Add('Mode: ' + $Mode)
    $lines.Add('Device: ' + [string]$Context.Device_Name)
    $lines.Add('Employee: ' + [string]$Context.Full_Name)
    $lines.Add('Department: ' + [string]$Context.Department)
    $lines.Add('')
    $lines.Add('BEFORE SCAN')
    foreach ($target in $BeforeResults) {
        $files = @($target.Locations | Measure-Object -Property Files -Sum).Sum
        $bytes = @($target.Locations | Measure-Object -Property Bytes -Sum).Sum
        $profiles = @($target.Locations | Measure-Object -Property Profiles -Sum).Sum
        $lines.Add(('{0} | {1} | installed={2} | running={3} | profiles={4} | files={5} | estimated_mb={6:N2} | supported={7}' -f
            $target.Result, $target.DisplayName, $target.Installed, $target.Running, [int]$profiles, [int]$files, ([double]$bytes / 1MB), $target.Supported))
        foreach ($location in @($target.Locations | Where-Object { $_.Exists })) {
            $lines.Add(('  PATH | {0} | files={1} | estimated_mb={2:N2}' -f $location.Path, $location.Files, ([double]$location.Bytes / 1MB)))
        }
        if ($target.PSObject.Properties['CloudSyncState'] -and $target.CloudSyncState) {
            foreach ($account in @($target.CloudSyncState.Accounts)) {
                $lines.Add(('  CLOUD SYNC | account_type={0} | root={1} | actively_syncing={2}' -f $account.AccountType, $account.SyncRoot, $account.ActivelySyncing))
            }
            foreach ($knownFolder in @($target.CloudSyncState.KnownFolderMove)) {
                $lines.Add(('  KNOWN FOLDER MOVE | folder={0} | path={1}' -f $knownFolder.KnownFolder, $knownFolder.Path))
            }
            $lines.Add(('  FILES ON DEMAND | online_only_placeholders_detected={0} | contents_not_opened=yes' -f $target.CloudSyncState.PlaceholderCount))
        }
    }
    if ($CleanupResults.Count) {
        $lines.Add('')
        $lines.Add('CLEANUP ACTIONS')
        foreach ($cleanup in $CleanupResults) {
            $lines.Add(('{0} | {1}' -f $cleanup.Result, $cleanup.TargetId))
            foreach ($action in @($cleanup.Actions)) {
                $lines.Add(('  {0} | {1} | {2}' -f $action.Type, $action.Result, [string]$action.Path))
            }
        }
    }
    if ($AfterResults.Count) {
        $lines.Add('')
        $lines.Add('AFTER SCAN')
        foreach ($target in $AfterResults) {
            $lines.Add(('{0} | {1} | installed={2} | running={3}' -f $target.Result, $target.DisplayName, $target.Installed, $target.Running))
        }
    }
    $safeLines = @($lines | ForEach-Object { Protect-SfdSecretText -Text $_ })
    Set-Content -LiteralPath $Path -Value $safeLines -Encoding UTF8
    Get-Item -LiteralPath $Path
}
