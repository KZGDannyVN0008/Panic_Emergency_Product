Set-StrictMode -Version 2.0

function Stop-SfdTargetProcesses {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Target)

    $failures = New-Object System.Collections.Generic.List[string]
    foreach ($processName in @($Target.process_names)) {
        foreach ($process in @(Get-Process -Name $processName -ErrorAction SilentlyContinue)) {
            try {
                Stop-Process -Id $process.Id -Force -ErrorAction Stop
            } catch {
                $failures.Add("$processName/$($process.Id): $($_.Exception.Message)")
            }
        }
    }
    Start-Sleep -Milliseconds 250
    [pscustomobject]@{
        Success = ($failures.Count -eq 0)
        Failures = @($failures | ForEach-Object { Protect-SfdSecretText -Text $_ })
        Remaining = @($Target.process_names | Where-Object { Get-Process -Name $_ -ErrorAction SilentlyContinue })
    }
}

function Remove-SfdApprovedPath {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ApprovedBases,
        [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
        [string[]]$ActiveSyncRoots = @()
    )

    $safety = Test-SfdCleanupPath -Path $Path -ApprovedBases $ApprovedBases -ProtectedPaths $ProtectedPaths -ActiveSyncRoots $ActiveSyncRoots
    if (-not $safety.Safe) {
        return [pscustomobject]@{ Status = 'PROTECTED'; Path = $safety.Path; Reasons = $safety.Reasons }
    }
    if (-not $PSCmdlet.ShouldProcess($safety.Path, 'Remove manifest-approved local data')) {
        return [pscustomobject]@{ Status = 'SKIPPED'; Path = $safety.Path; Reasons = @('WHATIF_OR_DECLINED') }
    }
    try {
        Remove-Item -LiteralPath $safety.Path -Recurse -Force -ErrorAction Stop
        $remaining = Test-Path -LiteralPath $safety.Path
        [pscustomobject]@{
            Status = if ($remaining) { 'VERIFICATION_FAILED' } else { 'CLEANED' }
            Path = $safety.Path
            Reasons = @()
        }
    } catch {
        [pscustomobject]@{
            Status = 'FAILED'
            Path = $safety.Path
            Reasons = @(Protect-SfdSecretText -Text $_.Exception.Message)
        }
    }
}

function Clear-SfdApprovedDirectory {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
        [string[]]$ActiveSyncRoots = @()
    )
    $safety = Test-SfdCleanupPath -Path $Path -ApprovedBases @($Path) -ProtectedPaths $ProtectedPaths -ActiveSyncRoots $ActiveSyncRoots
    if (-not $safety.Safe) {
        return [pscustomobject]@{ Status = 'PROTECTED'; Path = $safety.Path; Reasons = $safety.Reasons }
    }
    if (-not $PSCmdlet.ShouldProcess($safety.Path, 'Clear contents of manifest-approved directory')) {
        return [pscustomobject]@{ Status = 'SKIPPED'; Path = $safety.Path; Reasons = @('WHATIF_OR_DECLINED') }
    }
    $failed = 0
    foreach ($child in @(Get-ChildItem -LiteralPath $safety.Path -Force -ErrorAction SilentlyContinue)) {
        if (($child.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) { $failed++; continue }
        try { Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction Stop }
        catch { $failed++ }
    }
    $remaining = @(Get-ChildItem -LiteralPath $safety.Path -Force -ErrorAction SilentlyContinue).Count
    [pscustomobject]@{
        Status = if ($remaining -eq 0 -and $failed -eq 0) { 'CLEANED' } elseif ($remaining -gt 0) { 'PARTIAL_SUCCESS' } else { 'FAILED' }
        Path = $safety.Path
        Reasons = if ($failed) { @("$failed item(s) could not be safely removed.") } else { @() }
    }
}

function Remove-SfdCredentialEntries {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param([Parameter(Mandatory = $true)][string[]]$Filters)

    if ($env:OS -ne 'Windows_NT' -or -not $Filters.Count) { return @() }
    $results = New-Object System.Collections.Generic.List[object]
    foreach ($line in @(cmdkey.exe /list 2>$null)) {
        if ($line -notmatch '^\s*Target:\s*(.+)$') { continue }
        $target = [string]$matches[1]
        if (-not @($Filters | Where-Object { $target -match $_ }).Count) { continue }
        $cleanTarget = $target -replace '^LegacyGeneric:target=', '' -replace '^WindowsLive:target=', ''
        if ($PSCmdlet.ShouldProcess($cleanTarget, 'Delete approved Windows Credential Manager entry')) {
            cmdkey.exe "/delete:$cleanTarget" | Out-Null
            $results.Add([pscustomobject]@{
                Target = $cleanTarget
                Status = if ($LASTEXITCODE -eq 0) { 'CLEANED' } else { 'FAILED' }
            })
        }
    }
    $results.ToArray()
}

function Test-SfdCredentialEntriesAbsent {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string[]]$Filters)
    if ($env:OS -ne 'Windows_NT' -or -not $Filters.Count) { return $true }
    foreach ($line in @(cmdkey.exe /list 2>$null)) {
        if ($line -notmatch '^\s*Target:\s*(.+)$') { continue }
        $credentialTarget = [string]$matches[1]
        if (@($Filters | Where-Object { $credentialTarget -match $_ }).Count) { return $false }
    }
    $true
}

function Test-SfdCurrentRecycleBinEmpty {
    [CmdletBinding()]
    param()
    if ($env:OS -ne 'Windows_NT') { return $true }
    $sid = [string][Security.Principal.WindowsIdentity]::GetCurrent().User.Value
    foreach ($drive in @(Get-PSDrive -PSProvider FileSystem -ErrorAction SilentlyContinue)) {
        $userBin = Join-Path $drive.Root ('$Recycle.Bin\' + $sid)
        if (Test-Path -LiteralPath $userBin) {
            if (@(Get-ChildItem -LiteralPath $userBin -Force -ErrorAction SilentlyContinue).Count) { return $false }
        }
    }
    $true
}

function Test-SfdOneDriveDisconnected {
    [CmdletBinding()]
    param()

    if (Get-Process -Name OneDrive -ErrorAction SilentlyContinue) { return $false }
    $accountKeys = @(
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Personal',
        'HKCU:\Software\Microsoft\OneDrive\Accounts\Business1'
    )
    foreach ($key in $accountKeys) {
        if (Test-Path -LiteralPath $key) {
            $properties = Get-ItemProperty -LiteralPath $key -ErrorAction SilentlyContinue
            if ($properties.UserFolder) { return $false }
        }
    }
    $true
}

function Get-SfdActiveSyncRoots {
    [CmdletBinding()]
    param()
    $roots = New-Object System.Collections.Generic.List[string]
    if ($env:OS -ne 'Windows_NT') { return @() }
    $activeProcessNames = @('OneDrive', 'GoogleDriveFS', 'Dropbox', 'Box', 'BoxDrive')
    if (-not @(Get-Process -Name $activeProcessNames -ErrorAction SilentlyContinue).Count) { return @() }
    foreach ($accountKey in @(Get-ChildItem -LiteralPath 'HKCU:\Software\Microsoft\OneDrive\Accounts' -ErrorAction SilentlyContinue)) {
        $account = Get-ItemProperty -LiteralPath $accountKey.PSPath -ErrorAction SilentlyContinue
        if ($account.UserFolder -and (Test-Path -LiteralPath $account.UserFolder)) {
            $roots.Add([IO.Path]::GetFullPath([string]$account.UserFolder))
        }
    }
    foreach ($candidate in @(
        $env:OneDrive,
        $env:OneDriveCommercial,
        $env:OneDriveConsumer,
        (Join-Path ([Environment]::GetFolderPath('UserProfile')) 'Dropbox')
    ) | Where-Object { $_ -and (Test-Path -LiteralPath $_) }) {
        $full = [IO.Path]::GetFullPath([string]$candidate)
        if (-not $roots.Contains($full)) { $roots.Add($full) }
    }
    $roots.ToArray()
}

function Invoke-SfdTargetCleanup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)][hashtable]$EnvironmentMap,
        [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
        [string[]]$ActiveSyncRoots = @(),
        [bool]$CredentialScopeAvailable = $true
    )

    if ([string]$Target.cleanup_strategy -eq 'REPORT_ONLY') {
        return [pscustomobject]@{ TargetId = $Target.target_id; Result = 'PROTECTED'; VerificationStrategy = $Target.verification_strategy; Actions = @('REPORT_ONLY') }
    }
    if ([string]$Target.cleanup_strategy -eq 'CLEAR_RECYCLE_BIN') {
        if (-not $CredentialScopeAvailable) {
            return [pscustomobject]@{ TargetId = $Target.target_id; Result = 'PROTECTED'; VerificationStrategy = $Target.verification_strategy; Actions = @('OTHER_USER_RECYCLE_BIN') }
        }
        if ($WhatIfPreference) {
            return [pscustomobject]@{ TargetId = $Target.target_id; Result = 'CLEANED'; VerificationStrategy = $Target.verification_strategy; Actions = @('WHATIF_RECYCLE_BIN') }
        }
        try {
            Clear-RecycleBin -Force -ErrorAction Stop
            $empty = Test-SfdCurrentRecycleBinEmpty
            return [pscustomobject]@{ TargetId = $Target.target_id; Result = if ($empty) { 'CLEANED' } else { 'VERIFICATION_FAILED' }; VerificationStrategy = $Target.verification_strategy; Actions = @('RECYCLE_BIN_CLEARED', $(if ($empty) { 'VERIFICATION_PASSED' } else { 'VERIFICATION_FAILED' })) }
        } catch {
            return [pscustomobject]@{ TargetId = $Target.target_id; Result = 'FAILED'; VerificationStrategy = $Target.verification_strategy; Actions = @(Protect-SfdSecretText -Text $_.Exception.Message) }
        }
    }
    if ([string]$Target.cleanup_strategy -eq 'DISCONNECT_THEN_CLEAR_APPROVED_PATHS') {
        if (-not (Test-SfdOneDriveDisconnected)) {
            return [pscustomobject]@{
                TargetId = $Target.target_id
                Result = 'PROTECTED'
                VerificationStrategy = $Target.verification_strategy
                Actions = @('SYNC_DISCONNECT_NOT_VERIFIED')
            }
        }
    }
    $stopwatch = [Diagnostics.Stopwatch]::StartNew()
    $timeoutSeconds = if ($Target.PSObject.Properties['timeout_seconds']) { [int]$Target.timeout_seconds } else { 60 }
    $actions = New-Object System.Collections.Generic.List[object]
    $processResult = if ($WhatIfPreference) {
        [pscustomobject]@{ Success = $true; Failures = @(); Remaining = @() }
    } else {
        Stop-SfdTargetProcesses -Target $Target
    }
    $actions.Add([pscustomobject]@{ Type = 'PROCESS_STOP'; Result = if ($processResult.Remaining.Count) { 'FAILED' } else { 'CLEANED' }; Detail = $processResult })
    foreach ($pathTemplate in @($Target.approved_data_paths)) {
        if ($stopwatch.Elapsed.TotalSeconds -ge $timeoutSeconds) {
            $actions.Add([pscustomobject]@{ Type = 'TIMEOUT'; Result = 'FAILED'; Detail = "Target exceeded $timeoutSeconds seconds." })
            break
        }
        try {
            $path = Resolve-SfdTargetPath -Path $pathTemplate -EnvironmentMap $EnvironmentMap
            if (-not (Test-Path -LiteralPath $path)) {
                $actions.Add([pscustomobject]@{ Type = 'PATH'; Path = $path; Result = 'SKIPPED' })
                continue
            }
            $removeResult = if ([string]$Target.cleanup_strategy -eq 'CLEAR_DIRECTORY_CONTENTS') {
                Clear-SfdApprovedDirectory -Path $path -ProtectedPaths $ProtectedPaths -ActiveSyncRoots $ActiveSyncRoots -Confirm:$false -WhatIf:$WhatIfPreference
            } else {
                Remove-SfdApprovedPath -Path $path -ApprovedBases @($path) -ProtectedPaths $ProtectedPaths -ActiveSyncRoots $ActiveSyncRoots -Confirm:$false -WhatIf:$WhatIfPreference
            }
            $actions.Add([pscustomobject]@{ Type = 'PATH'; Path = $path; Result = $removeResult.Status; Detail = $removeResult })
        } catch {
            $actions.Add([pscustomobject]@{ Type = 'PATH'; Path = $pathTemplate; Result = 'FAILED'; Detail = Protect-SfdSecretText -Text $_.Exception.Message })
        }
    }
    if ($CredentialScopeAvailable) {
        $credentialResults = if (@($Target.credential_filters).Count) {
            @(Remove-SfdCredentialEntries -Filters @($Target.credential_filters) -Confirm:$false -WhatIf:$WhatIfPreference)
        } else {
            @()
        }
        foreach ($credentialResult in $credentialResults) {
            $actions.Add([pscustomobject]@{ Type = 'CREDENTIAL'; Result = $credentialResult.Status; Detail = $credentialResult })
        }
        if (@($Target.credential_filters).Count -and -not $WhatIfPreference) {
            $credentialsAbsent = Test-SfdCredentialEntriesAbsent -Filters @($Target.credential_filters)
            $actions.Add([pscustomobject]@{ Type = 'CREDENTIAL_VERIFY'; Result = if ($credentialsAbsent) { 'CLEANED' } else { 'VERIFICATION_FAILED' } })
        }
    } elseif (@($Target.credential_filters).Count) {
        $actions.Add([pscustomobject]@{ Type = 'CREDENTIAL'; Result = 'PROTECTED'; Detail = 'Credential Manager cannot be safely impersonated for another profile.' })
    }
    $failed = @($actions | Where-Object { $_.Result -in @('FAILED', 'VERIFICATION_FAILED') }).Count
    $protected = @($actions | Where-Object { $_.Result -eq 'PROTECTED' }).Count
    $result = if ($failed -and $failed -lt $actions.Count) { 'PARTIAL_SUCCESS' } elseif ($failed) { 'FAILED' } elseif ($protected) { 'PROTECTED' } else { 'CLEANED' }
    [pscustomobject]@{ TargetId = $Target.target_id; Result = $result; VerificationStrategy = $Target.verification_strategy; Actions = $actions.ToArray() }
}

function Invoke-SfdAllowedUninstall {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param(
        [Parameter(Mandatory = $true)]$Target,
        [Parameter(Mandatory = $true)]$Allowlist
    )
    $allowed = $Allowlist.targets | Where-Object { $_.target_id -eq $Target.target_id } | Select-Object -First 1
    if (-not $Target.uninstall_allowed -or -not $allowed) {
        return [pscustomobject]@{ Result = 'SKIPPED'; Detail = 'Target is not on both uninstall allowlists.' }
    }
    if (-not $Target.uninstall_method -or [string]$Target.uninstall_method.type -ne 'MSI_PRODUCT_CODE') {
        return [pscustomobject]@{ Result = 'PROTECTED'; Detail = 'Only an explicit MSI product code is supported.' }
    }
    $productCode = [string]$Target.uninstall_method.product_code
    if ($productCode -notmatch '^\{[0-9A-Fa-f-]{36}\}$' -or [string]$allowed.product_code -ne $productCode) {
        return [pscustomobject]@{ Result = 'PROTECTED'; Detail = 'The approved MSI product code does not match.' }
    }
    if (-not $PSCmdlet.ShouldProcess([string]$Target.display_name, 'Run approved MSI uninstall fallback')) {
        return [pscustomobject]@{ Result = 'SKIPPED'; Detail = 'WhatIf or declined.' }
    }
    try {
        $process = Start-Process -FilePath 'msiexec.exe' -ArgumentList '/x', $productCode, '/qn', '/norestart' -Wait -PassThru -ErrorAction Stop
        if ($process.ExitCode -in @(0, 1605, 1614)) {
            return [pscustomobject]@{ Result = 'UNINSTALLED'; Detail = "MSI exit code $($process.ExitCode)." }
        }
        [pscustomobject]@{ Result = 'FAILED'; Detail = "MSI exit code $($process.ExitCode)." }
    } catch {
        [pscustomobject]@{ Result = 'FAILED'; Detail = Protect-SfdSecretText -Text $_.Exception.Message }
    }
}
