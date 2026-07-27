Set-StrictMode -Version 2.0

function Import-SfdTargetManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $manifest = Read-SfdJson -Path $Path
    $result = Test-SfdTargetManifest -Manifest $manifest
    if (-not $result.Valid) { throw ($result.Errors -join [Environment]::NewLine) }
    $manifest
}

function Test-SfdTargetManifest {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)]$Manifest)

    $errors = New-Object System.Collections.Generic.List[string]
    if ([int]$Manifest.schema_version -ne 1) { $errors.Add('Target manifest schema_version must be 1.') }
    if (-not $Manifest.manifest_version) { $errors.Add('manifest_version is required.') }
    $required = @(
        'target_id', 'category', 'display_name', 'supported_versions', 'risk_level',
        'process_names', 'install_detection', 'approved_data_paths', 'credential_filters',
        'cleanup_strategy', 'verification_strategy', 'timeout_seconds',
        'uninstall_allowed', 'uninstall_method', 'protected_paths', 'exclusions'
    )
    $allowedCategories = @('BROWSER', 'COMMUNICATION', 'OFFICE', 'AI_TOOL', 'DEVELOPER_TOOL', 'CLOUD_SYNC', 'VPN', 'PRODUCTIVITY', 'OTHER_APPROVED')
    $seen = @{}
    foreach ($target in @($Manifest.targets)) {
        foreach ($field in $required) {
            if (-not $target.PSObject.Properties[$field]) {
                $errors.Add("Target '$($target.target_id)' is missing '$field'.")
            }
        }
        if ($target.target_id -notmatch '^[a-z0-9][a-z0-9._-]+$') {
            $errors.Add("Invalid target_id: $($target.target_id)")
        } elseif ($seen.ContainsKey([string]$target.target_id)) {
            $errors.Add("Duplicate target_id: $($target.target_id)")
        } else {
            $seen[[string]$target.target_id] = $true
        }
        if ($target.category -notin $allowedCategories) {
            $errors.Add("Invalid category for '$($target.target_id)': $($target.category)")
        }
        if ([int]$target.timeout_seconds -lt 1 -or [int]$target.timeout_seconds -gt 900) {
            $errors.Add("Invalid timeout for '$($target.target_id)'.")
        }
        if ($target.uninstall_allowed -and -not $target.uninstall_method) {
            $errors.Add("Target '$($target.target_id)' permits uninstall without a method.")
        }
    }
    [pscustomobject]@{ Valid = ($errors.Count -eq 0); Errors = $errors.ToArray() }
}
