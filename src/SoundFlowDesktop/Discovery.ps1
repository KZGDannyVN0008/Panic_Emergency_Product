Set-StrictMode -Version 2.0

function Get-SfdEnvironmentMap {
    [CmdletBinding()]
    param([string]$UserProfile)

    $currentProfile = [Environment]::GetFolderPath('UserProfile')
    if (-not $UserProfile) { $UserProfile = $currentProfile }
    $isCurrentProfile = $currentProfile -and ([IO.Path]::GetFullPath($UserProfile).TrimEnd('\') -eq [IO.Path]::GetFullPath($currentProfile).TrimEnd('\'))
    $localAppData = if ($isCurrentProfile -and $env:LOCALAPPDATA) { $env:LOCALAPPDATA } else { Join-Path $UserProfile 'AppData\Local' }
    $appData = if ($isCurrentProfile -and $env:APPDATA) { $env:APPDATA } else { Join-Path $UserProfile 'AppData\Roaming' }
    @{
        'USERPROFILE' = $UserProfile
        'LOCALAPPDATA' = $localAppData
        'APPDATA' = $appData
        'PROGRAMDATA' = $env:PROGRAMDATA
        'PROGRAMFILES' = $env:ProgramFiles
        'PROGRAMFILES(X86)' = ${env:ProgramFiles(x86)}
        'SYSTEMROOT' = $env:SystemRoot
        'SYSTEMDRIVE' = $env:SystemDrive
        'TEMP' = [IO.Path]::GetTempPath()
    }
}

function Get-SfdInstalledApplications {
    [CmdletBinding()]
    param()

    $applications = New-Object System.Collections.Generic.List[object]
    $locations = @(
        'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\Microsoft\Windows\CurrentVersion\Uninstall\*',
        'HKLM:\Software\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*'
    )
    if ($env:OS -eq 'Windows_NT') {
        foreach ($entry in @(Get-ItemProperty -Path $locations -ErrorAction SilentlyContinue)) {
            if (-not $entry.DisplayName) { continue }
            $applications.Add([pscustomobject]@{
                DisplayName = [string]$entry.DisplayName
                DisplayVersion = [string]$entry.DisplayVersion
                InstallLocation = [string]$entry.InstallLocation
                UninstallString = [string]$entry.UninstallString
                RegistryPath = [string]$entry.PSPath
                Source = 'REGISTRY'
            })
        }
        if (Get-Command Get-AppxPackage -ErrorAction SilentlyContinue) {
            foreach ($package in @(Get-AppxPackage -ErrorAction SilentlyContinue)) {
                $applications.Add([pscustomobject]@{
                    DisplayName = [string]$package.Name
                    DisplayVersion = [string]$package.Version
                    InstallLocation = [string]$package.InstallLocation
                    UninstallString = ''
                    RegistryPath = ''
                    Source = 'APPX'
                })
            }
        }
        foreach ($registrationRoot in @(
            'HKCU:\Software\Clients\StartMenuInternet\*',
            'HKLM:\Software\Clients\StartMenuInternet\*'
        )) {
            foreach ($registration in @(Get-Item -Path $registrationRoot -ErrorAction SilentlyContinue)) {
                $applications.Add([pscustomobject]@{
                    DisplayName = [string]$registration.PSChildName
                    DisplayVersion = ''
                    InstallLocation = ''
                    UninstallString = ''
                    RegistryPath = [string]$registration.PSPath
                    Source = 'CHROMIUM'
                })
            }
        }
    }
    $applications.ToArray()
}

function Get-SfdPathStatistics {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [int]$TimeoutSeconds = 60
    )

    $files = 0
    $directories = 0
    [int64]$bytes = 0
    $profileNames = New-Object System.Collections.Generic.HashSet[string]
    if (-not (Test-Path -LiteralPath $Path)) {
        return [pscustomobject]@{ Exists = $false; Files = 0; Directories = 0; Bytes = 0; Profiles = 0; ProfileNames = @(); TimedOut = $false }
    }
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $timedOut = $false
    try {
        foreach ($item in Get-ChildItem -LiteralPath $Path -Force -Recurse -ErrorAction SilentlyContinue) {
            if ($stopwatch.Elapsed.TotalSeconds -ge $TimeoutSeconds) {
                $timedOut = $true
                break
            }
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { continue }
            if (($item.Attributes -band [IO.FileAttributes]::Offline) -ne 0) { continue }
            if ($item.PSIsContainer) {
                $directories++
                if ($item.Name -eq 'Default' -or $item.Name -like 'Profile *' -or $item.Name -like '*.default*') {
                    $relative = $item.FullName.Substring($Path.TrimEnd('\').Length).TrimStart('\')
                    $null = $profileNames.Add($relative)
                }
            } else { $files++; $bytes += [int64]$item.Length }
        }
    } catch {}
    [pscustomobject]@{ Exists = $true; Files = $files; Directories = $directories; Bytes = $bytes; Profiles = $profileNames.Count; ProfileNames = @($profileNames | ForEach-Object { $_ }); TimedOut = $timedOut }
}

function Test-SfdInstallRule {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Rule,
        [Parameter(Mandatory = $true)][object[]]$InstalledApplications,
        [Parameter(Mandatory = $true)][hashtable]$EnvironmentMap
    )

    switch ([string]$Rule.type) {
        'PATH' {
            try { return Test-Path -LiteralPath (Resolve-SfdTargetPath -Path $Rule.value -EnvironmentMap $EnvironmentMap) }
            catch { return $false }
        }
        'UNINSTALL_DISPLAY_NAME' {
            return @($InstalledApplications | Where-Object { $_.DisplayName -match [string]$Rule.value }).Count -gt 0
        }
        'APPX_NAME' {
            return @($InstalledApplications | Where-Object { $_.Source -eq 'APPX' -and $_.DisplayName -match [string]$Rule.value }).Count -gt 0
        }
        'OFFICE_EXECUTABLE' {
            $roots = @($EnvironmentMap['PROGRAMFILES'], $EnvironmentMap['PROGRAMFILES(X86)']) | Where-Object { $_ }
            foreach ($root in $roots) {
                if (Test-Path -LiteralPath (Join-Path $root ('Microsoft Office\root\Office16\' + [string]$Rule.value))) { return $true }
            }
            return $false
        }
        'CHROMIUM_REGISTRATION' {
            return @($InstalledApplications | Where-Object {
                $_.Source -eq 'CHROMIUM' -and $_.DisplayName -notmatch '(?i)(Chrome|Edge|Brave|Opera)'
            }).Count -gt 0
        }
        'CREDENTIAL_MANAGER' {
            if ($env:OS -ne 'Windows_NT') { return $false }
            return @((cmdkey.exe /list 2>$null) | Where-Object { $_ -match '^\s*Target:' }).Count -gt 0
        }
        'SPECIAL_RECYCLE_BIN' {
            return $env:OS -eq 'Windows_NT'
        }
        default { return $false }
    }
}

function Get-SfdOneDriveState {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$UserProfile)
    $accounts = New-Object System.Collections.Generic.List[object]
    if ($env:OS -ne 'Windows_NT') { return [pscustomobject]@{ Accounts = @(); KnownFolderMove = @(); PlaceholderCount = 0 } }
    $currentProfile = [Environment]::GetFolderPath('UserProfile')
    if ([IO.Path]::GetFullPath($UserProfile).TrimEnd('\') -ne [IO.Path]::GetFullPath($currentProfile).TrimEnd('\')) {
        return [pscustomobject]@{ Accounts = @(); KnownFolderMove = @(); PlaceholderCount = 0; Status = 'OTHER_PROFILE_REGISTRY_NOT_LOADED' }
    }
    foreach ($accountKey in @(Get-ChildItem -LiteralPath 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) {
        $account = Get-ItemProperty -LiteralPath $accountKey.PSPath -ErrorAction SilentlyContinue
        if (-not $account.UserFolder) { continue }
        $accounts.Add([pscustomobject]@{
            AccountType = if ($accountKey.PSChildName -like 'Business*') { 'BUSINESS' } else { 'PERSONAL' }
            SyncRoot = [string]$account.UserFolder
            ActivelySyncing = [bool](Get-Process -Name OneDrive -ErrorAction SilentlyContinue)
        })
    }
    $knownFolderMove = New-Object System.Collections.Generic.List[object]
    foreach ($knownFolder in @('Desktop', 'MyDocuments')) {
        $knownPath = if ($knownFolder -eq 'Desktop') {
            [Environment]::GetFolderPath([Environment+SpecialFolder]::Desktop)
        } else {
            [Environment]::GetFolderPath([Environment+SpecialFolder]::MyDocuments)
        }
        foreach ($account in $accounts) {
            if ($knownPath -and (Test-SfdPathWithinBase -Path $knownPath -BasePath $account.SyncRoot)) {
                $knownFolderMove.Add([pscustomobject]@{ KnownFolder = $knownFolder; Path = $knownPath; SyncRoot = $account.SyncRoot })
            }
        }
    }
    $placeholderCount = 0
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    foreach ($account in $accounts) {
        foreach ($item in Get-ChildItem -LiteralPath $account.SyncRoot -Force -Recurse -ErrorAction SilentlyContinue) {
            if ($stopwatch.Elapsed.TotalSeconds -ge 5) { break }
            if (($item.Attributes -band [IO.FileAttributes]::Offline) -ne 0) { $placeholderCount++ }
        }
        if ($stopwatch.Elapsed.TotalSeconds -ge 5) { break }
    }
    [pscustomobject]@{
        Accounts = $accounts.ToArray()
        KnownFolderMove = $knownFolderMove.ToArray()
        PlaceholderCount = $placeholderCount
        Status = if ($accounts.Count) { 'DETECTED' } else { 'NOT_DETECTED' }
    }
}

function Invoke-SfdDiscovery {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]$Manifest,
        [string]$UserProfile,
        [switch]$ExcludeUnknownApplications
    )

    $environmentMap = Get-SfdEnvironmentMap -UserProfile $UserProfile
    $installedApplications = @(Get-SfdInstalledApplications)
    $processes = if ($env:OS -eq 'Windows_NT') { @(Get-Process -ErrorAction SilentlyContinue) } else { @() }
    $results = New-Object System.Collections.Generic.List[object]
    $matchedApplications = New-Object System.Collections.Generic.HashSet[string]

    foreach ($target in @($Manifest.targets)) {
        $installed = $false
        foreach ($rule in @($target.install_detection)) {
            if (Test-SfdInstallRule -Rule $rule -InstalledApplications $installedApplications -EnvironmentMap $environmentMap) {
                $installed = $true
            }
            if ($rule.type -in @('UNINSTALL_DISPLAY_NAME', 'APPX_NAME')) {
                foreach ($app in @($installedApplications | Where-Object { $_.DisplayName -match [string]$rule.value })) {
                    $null = $matchedApplications.Add([string]$app.DisplayName)
                }
            } elseif ($rule.type -eq 'CHROMIUM_REGISTRATION') {
                foreach ($app in @($installedApplications | Where-Object { $_.Source -eq 'CHROMIUM' })) {
                    $null = $matchedApplications.Add([string]$app.DisplayName)
                }
            }
        }
        if ($installed) {
            $displayPattern = [regex]::Escape([string]$target.display_name)
            foreach ($app in @($installedApplications | Where-Object { $_.DisplayName -match $displayPattern })) {
                $null = $matchedApplications.Add([string]$app.DisplayName)
            }
        }
        $running = @($processes | Where-Object { $_.ProcessName -in @($target.process_names) })
        $locations = New-Object System.Collections.Generic.List[object]
        foreach ($pathTemplate in @($target.approved_data_paths)) {
            try {
                $path = Resolve-SfdTargetPath -Path $pathTemplate -EnvironmentMap $environmentMap
                $stats = Get-SfdPathStatistics -Path $path -TimeoutSeconds ([int]$target.timeout_seconds)
                $locations.Add([pscustomobject]@{
                    Path = $path
                    Exists = $stats.Exists
                    Files = $stats.Files
                    Directories = $stats.Directories
                    Bytes = $stats.Bytes
                    Profiles = $stats.Profiles
                    ProfileNames = $stats.ProfileNames
                    TimedOut = $stats.TimedOut
                })
            } catch {
                $locations.Add([pscustomobject]@{
                    Path = [string]$pathTemplate
                    Exists = $false
                    Files = 0
                    Directories = 0
                    Bytes = 0
                    Profiles = 0
                    ProfileNames = @()
                    Error = Protect-SfdSecretText -Text $_.Exception.Message
                })
            }
        }
        $cloudSyncState = if ($target.target_id -eq 'cloud.onedrive') { Get-SfdOneDriveState -UserProfile $environmentMap['USERPROFILE'] } else { $null }
        $results.Add([pscustomobject]@{
            TargetId = [string]$target.target_id
            UserProfile = $environmentMap['USERPROFILE']
            Category = [string]$target.category
            DisplayName = [string]$target.display_name
            Installed = $installed
            Running = ($running.Count -gt 0)
            RunningProcessIds = @($running | ForEach-Object { $_.Id })
            Locations = $locations.ToArray()
            Result = if ($installed -or $running.Count -or @($locations | Where-Object { $_.Exists }).Count) { 'DETECTED' } else { 'SKIPPED' }
            Supported = ([string]$target.cleanup_strategy -ne 'REPORT_ONLY')
            CloudSyncState = $cloudSyncState
        })
    }
    if (-not $ExcludeUnknownApplications) {
        foreach ($application in @($installedApplications | Where-Object { -not $matchedApplications.Contains([string]$_.DisplayName) })) {
            $results.Add([pscustomobject]@{
                TargetId = 'unknown.' + ([guid]::NewGuid().ToString('N'))
                UserProfile = $environmentMap['USERPROFILE']
                Category = 'OTHER_APPROVED'
                DisplayName = [string]$application.DisplayName
                Installed = $true
                Running = $false
                RunningProcessIds = @()
                Locations = @()
                Result = 'DETECTED'
                Supported = $false
                CloudSyncState = $null
            })
        }
    }
    $results.ToArray()
}

function Get-SfdAccessibleUserProfiles {
    [CmdletBinding()]
    param([bool]$IsAdministrator)

    $current = [Environment]::GetFolderPath('UserProfile')
    if (-not $IsAdministrator -or $env:OS -ne 'Windows_NT') { return @($current) }
    $profiles = New-Object System.Collections.Generic.List[string]
    if ($current) { $profiles.Add([IO.Path]::GetFullPath($current)) }
    try {
        foreach ($profile in @(Get-CimInstance Win32_UserProfile -ErrorAction Stop | Where-Object {
            -not $_.Special -and $_.LocalPath -and (Test-Path -LiteralPath $_.LocalPath -PathType Container)
        })) {
            $full = [IO.Path]::GetFullPath([string]$profile.LocalPath)
            if (-not $profiles.Contains($full)) { $profiles.Add($full) }
        }
    } catch {}
    $profiles.ToArray()
}
