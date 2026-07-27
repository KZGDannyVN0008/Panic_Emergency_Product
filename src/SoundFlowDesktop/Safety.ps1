Set-StrictMode -Version 2.0

function Resolve-SfdTargetPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][hashtable]$EnvironmentMap
    )

    if ([string]::IsNullOrWhiteSpace($Path)) { throw 'Target path is empty.' }
    $expanded = $Path
    foreach ($key in $EnvironmentMap.Keys) {
        if (-not [string]::IsNullOrWhiteSpace([string]$EnvironmentMap[$key])) {
            $expanded = $expanded.Replace('%' + $key + '%', [string]$EnvironmentMap[$key])
        }
    }
    if ($expanded -match '%[A-Za-z0-9_()]+%') {
        throw "Target path contains an unresolved variable: $expanded"
    }
    if (-not [IO.Path]::IsPathRooted($expanded)) { throw "Target path is not absolute: $expanded" }
    [IO.Path]::GetFullPath($expanded).TrimEnd('\')
}

function Test-SfdPathWithinBase {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$BasePath
    )

    $full = [IO.Path]::GetFullPath($Path).TrimEnd('\')
    $base = [IO.Path]::GetFullPath($BasePath).TrimEnd('\')
    $full.Equals($base, [StringComparison]::OrdinalIgnoreCase) -or
        $full.StartsWith($base + '\', [StringComparison]::OrdinalIgnoreCase)
}

function Test-SfdCleanupPath {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string[]]$ApprovedBases,
        [Parameter(Mandatory = $true)][string[]]$ProtectedPaths,
        [string[]]$ActiveSyncRoots = @(),
        [switch]$AllowMissing
    )

    $reasons = New-Object System.Collections.Generic.List[string]
    if ([string]::IsNullOrWhiteSpace($Path)) {
        $reasons.Add('EMPTY_PATH')
        return [pscustomobject]@{ Safe = $false; Path = $Path; Reasons = @($reasons) }
    }
    if ($Path.IndexOfAny([char[]]'*?') -ge 0) { $reasons.Add('WILDCARD_PATH') }
    try { $full = [IO.Path]::GetFullPath($Path).TrimEnd('\') }
    catch {
        $reasons.Add('INVALID_PATH')
        return [pscustomobject]@{ Safe = $false; Path = $Path; Reasons = @($reasons) }
    }
    if ($full -match '^[A-Za-z]:$') { $reasons.Add('DRIVE_ROOT') }
    if (-not (@($ApprovedBases | Where-Object { Test-SfdPathWithinBase -Path $full -BasePath $_ }).Count)) {
        $reasons.Add('OUTSIDE_APPROVED_BASE')
    }
    foreach ($protected in $ProtectedPaths) {
        if (Test-SfdPathWithinBase -Path $full -BasePath $protected) {
            $reasons.Add('PROTECTED_PATH')
            break
        }
    }
    foreach ($syncRoot in $ActiveSyncRoots) {
        if (Test-SfdPathWithinBase -Path $full -BasePath $syncRoot) {
            $reasons.Add('ACTIVE_SYNC_ROOT')
            break
        }
    }
    if (Test-Path -LiteralPath $full) {
        try {
            $item = Get-Item -LiteralPath $full -Force -ErrorAction Stop
            if (($item.Attributes -band [IO.FileAttributes]::ReparsePoint) -ne 0) {
                $reasons.Add('REPARSE_POINT')
            }
        } catch {
            $reasons.Add('PATH_INSPECTION_FAILED')
        }
    } elseif (-not $AllowMissing) {
        $reasons.Add('PATH_NOT_FOUND')
    }
    [pscustomobject]@{ Safe = ($reasons.Count -eq 0); Path = $full; Reasons = @($reasons) }
}
