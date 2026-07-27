Set-StrictMode -Version 2.0

function Import-SfdDeploymentConfiguration {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [switch]$AllowDisconnectedIntegrations
    )

    $config = Read-SfdJson -Path $Path
    $errors = New-Object System.Collections.Generic.List[string]

    foreach ($field in @('full_name', 'work_email', 'department', 'final_action')) {
        if (-not ($config.PSObject.Properties.Name -contains $field) -or -not [string]$config.$field) {
            $errors.Add("Missing configuration field: $field")
        }
    }
    if ($config.final_action -notin @('NONE', 'LOGOUT', 'SHUTDOWN')) {
        $errors.Add('final_action must be NONE, LOGOUT, or SHUTDOWN.')
    }
    if ($config.work_email -and [string]$config.work_email -notmatch '^[^@\s]+@[^@\s]+\.[^@\s]+$') {
        $errors.Add('work_email is not a valid email address.')
    }
    if (-not $AllowDisconnectedIntegrations) {
        if (-not $config.lark.enabled -and -not $config.google_sheets.enabled) {
            $errors.Add('At least one operational integration must be enabled.')
        }
    }
    if ($errors.Count) { throw ($errors -join [Environment]::NewLine) }
    $config
}

function Protect-SfdDpapiValue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$PlainText)

    if ($env:OS -ne 'Windows_NT') { throw 'Windows DPAPI is only available on Windows.' }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $bytes = [Text.Encoding]::UTF8.GetBytes($PlainText)
    $protected = [System.Security.Cryptography.ProtectedData]::Protect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [Convert]::ToBase64String($protected)
}

function Unprotect-SfdDpapiValue {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$ProtectedText)

    if ($env:OS -ne 'Windows_NT') { throw 'Windows DPAPI is only available on Windows.' }
    Add-Type -AssemblyName System.Security -ErrorAction Stop
    $bytes = [Convert]::FromBase64String($ProtectedText)
    $plain = [System.Security.Cryptography.ProtectedData]::Unprotect(
        $bytes,
        $null,
        [System.Security.Cryptography.DataProtectionScope]::CurrentUser
    )
    [Text.Encoding]::UTF8.GetString($plain)
}
