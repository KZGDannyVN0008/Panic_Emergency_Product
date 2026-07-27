Set-StrictMode -Version 2.0

$script:SfdSheetColumns = @(
    'Event_ID', 'Incident_ID', 'Event_Timestamp', 'Event_Date', 'Event_Category',
    'Event_Action', 'Event_Status', 'Mode', 'Full_Name', 'Work_Email', 'Department',
    'Device_ID', 'Device_Name', 'OS_Name', 'OS_Version', 'Windows_Username',
    'Is_Administrator', 'App_Version', 'Previous_App_Version', 'Target_Type',
    'Target_Name', 'Target_Path', 'Installed', 'Running', 'Profiles_Found',
    'Files_Found', 'Estimated_Size_MB', 'Before_Status', 'Action_Result',
    'After_Status', 'Verification_Result', 'Error_Code', 'Error_Details',
    'Lark_Summary_Status', 'Lark_Report_Status', 'Queue_Status', 'Final_Action',
    'Duration_Seconds'
)

function ConvertTo-SfdBase64Url {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][byte[]]$Bytes)
    [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function Save-SfdGoogleToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)]$Token
    )
    $json = $Token | ConvertTo-Json -Depth 10 -Compress
    $protected = Protect-SfdDpapiValue -PlainText $json
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    Set-Content -LiteralPath $Path -Value $protected -Encoding Ascii
}

function Read-SfdGoogleToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)
    $protected = (Get-Content -LiteralPath $Path -Raw -Encoding Ascii).Trim()
    (Unprotect-SfdDpapiValue -ProtectedText $protected) | ConvertFrom-Json
}

function Invoke-SfdGoogleTokenRequest {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][hashtable]$Body
    )
    Invoke-RestMethod -Uri $Uri -Method Post -Body $Body -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 20 -ErrorAction Stop
}

function Get-SfdGoogleAccessToken {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$TokenPath)

    $token = Read-SfdGoogleToken -Path $TokenPath
    $expiresAt = [DateTimeOffset]::FromUnixTimeSeconds([int64]$token.expires_at)
    if ($token.access_token -and $expiresAt -gt [DateTimeOffset]::UtcNow.AddMinutes(2)) {
        return [string]$token.access_token
    }
    if (-not $token.refresh_token) { throw 'Google authorization must be reconnected.' }
    $refreshed = Invoke-SfdGoogleTokenRequest -Uri ([string]$token.token_uri) -Body @{
        client_id = [string]$token.client_id
        refresh_token = [string]$token.refresh_token
        grant_type = 'refresh_token'
    }
    $token.access_token = [string]$refreshed.access_token
    $token.expires_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + [int64]$refreshed.expires_in
    Save-SfdGoogleToken -Path $TokenPath -Token $token
    [string]$token.access_token
}

function Invoke-SfdGoogleApi {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateSet('Get', 'Post', 'Put')][string]$Method,
        [Parameter(Mandatory = $true)][string]$Uri,
        [Parameter(Mandatory = $true)][string]$TokenPath,
        $Body
    )
    $headers = @{ Authorization = 'Bearer ' + (Get-SfdGoogleAccessToken -TokenPath $TokenPath) }
    $arguments = @{
        Uri = $Uri
        Method = $Method
        Headers = $headers
        TimeoutSec = 20
        ErrorAction = 'Stop'
    }
    if ($null -ne $Body) {
        $arguments.Body = $Body | ConvertTo-Json -Depth 30 -Compress
        $arguments.ContentType = 'application/json; charset=utf-8'
    }
    Invoke-RestMethod @arguments
}

function Connect-SfdGoogleSheets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$OAuthClientPath,
        [Parameter(Mandatory = $true)][string]$TokenPath,
        [Parameter(Mandatory = $true)][string]$SpreadsheetId,
        [string]$TabName = 'Detail_Log',
        [int]$TimeoutSeconds = 180
    )

    $raw = Read-SfdJson -Path $OAuthClientPath
    $client = $raw.installed
    if (-not $client.client_id) { throw 'An installed-desktop OAuth client is required.' }
    $rng = [Security.Cryptography.RandomNumberGenerator]::Create()
    $verifierBytes = New-Object byte[] 48
    $stateBytes = New-Object byte[] 24
    $rng.GetBytes($verifierBytes)
    $rng.GetBytes($stateBytes)
    $rng.Dispose()
    $verifier = ConvertTo-SfdBase64Url -Bytes $verifierBytes
    $state = ConvertTo-SfdBase64Url -Bytes $stateBytes
    $sha = [Security.Cryptography.SHA256]::Create()
    $challenge = ConvertTo-SfdBase64Url -Bytes ($sha.ComputeHash([Text.Encoding]::ASCII.GetBytes($verifier)))
    $sha.Dispose()

    $listener = [Net.Sockets.TcpListener]::new([Net.IPAddress]::Loopback, 0)
    $listener.Start()
    $port = ([Net.IPEndPoint]$listener.LocalEndpoint).Port
    $redirectUri = 'http://127.0.0.1:' + $port + '/'
    $scope = 'https://www.googleapis.com/auth/spreadsheets'
    $query = @{
        client_id = [string]$client.client_id
        redirect_uri = $redirectUri
        response_type = 'code'
        scope = $scope
        state = $state
        code_challenge = $challenge
        code_challenge_method = 'S256'
        access_type = 'offline'
        prompt = 'consent'
    }.GetEnumerator() | ForEach-Object {
        [Uri]::EscapeDataString([string]$_.Key) + '=' + [Uri]::EscapeDataString([string]$_.Value)
    }
    $authUri = [string]$client.auth_uri + '?' + ($query -join '&')
    Start-Process $authUri
    try {
        $pending = $listener.AcceptTcpClientAsync()
        if (-not $pending.Wait($TimeoutSeconds * 1000)) { throw 'Google authorization timed out or was cancelled.' }
        $tcp = $pending.Result
        $stream = $tcp.GetStream()
        $reader = [IO.StreamReader]::new($stream, [Text.Encoding]::ASCII, $false, 1024, $true)
        $requestLine = $reader.ReadLine()
        while ($reader.ReadLine()) {}
        $target = ($requestLine -split ' ')[1]
        $callback = [Uri]('http://127.0.0.1:' + $port + $target)
        $parameters = @{}
        foreach ($pair in $callback.Query.TrimStart('?').Split('&')) {
            $parts = $pair.Split('=', 2)
            if ($parts.Count -eq 2) {
                $parameters[[Uri]::UnescapeDataString($parts[0])] = [Uri]::UnescapeDataString($parts[1].Replace('+', ' '))
            }
        }
        $message = 'Google Sheets authorization received. You may close this tab.'
        $messageBytes = [Text.Encoding]::UTF8.GetBytes($message)
        $headerBytes = [Text.Encoding]::ASCII.GetBytes("HTTP/1.1 200 OK`r`nContent-Type: text/plain; charset=utf-8`r`nContent-Length: $($messageBytes.Length)`r`nConnection: close`r`n`r`n")
        $stream.Write($headerBytes, 0, $headerBytes.Length)
        $stream.Write($messageBytes, 0, $messageBytes.Length)
        $stream.Dispose()
        $tcp.Dispose()
    } finally {
        $listener.Stop()
    }
    if ($parameters.state -ne $state) { throw 'Google OAuth state mismatch.' }
    if ($parameters.error) { throw ('Google authorization failed: ' + [string]$parameters.error) }
    if (-not $parameters.code) { throw 'Google did not return an authorization code.' }
    $tokenResponse = Invoke-SfdGoogleTokenRequest -Uri ([string]$client.token_uri) -Body @{
        client_id = [string]$client.client_id
        code = [string]$parameters.code
        code_verifier = $verifier
        grant_type = 'authorization_code'
        redirect_uri = $redirectUri
    }
    $token = [ordered]@{
        access_token = [string]$tokenResponse.access_token
        refresh_token = [string]$tokenResponse.refresh_token
        token_type = [string]$tokenResponse.token_type
        expires_at = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds() + [int64]$tokenResponse.expires_in
        client_id = [string]$client.client_id
        token_uri = [string]$client.token_uri
    }
    Save-SfdGoogleToken -Path $TokenPath -Token $token
    $null = Invoke-SfdGoogleApi -Method Get -Uri ('https://sheets.googleapis.com/v4/spreadsheets/' + $SpreadsheetId + '?fields=spreadsheetId') -TokenPath $TokenPath
    Ensure-SfdGoogleSheetHeaders -TokenPath $TokenPath -SpreadsheetId $SpreadsheetId -TabName $TabName
    [pscustomobject]@{ Connected = $true; Status = 'Google Sheets: Connected' }
}

function Disconnect-SfdGoogleSheets {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TokenPath,
        [switch]$Revoke
    )
    if (-not (Test-Path -LiteralPath $TokenPath)) {
        return [pscustomobject]@{ Disconnected = $true; Revoked = $false; Status = 'NOT_CONNECTED' }
    }
    $revoked = $false
    if ($Revoke) {
        $token = Read-SfdGoogleToken -Path $TokenPath
        $value = if ($token.refresh_token) { [string]$token.refresh_token } else { [string]$token.access_token }
        if ($value) {
            Invoke-RestMethod -Uri 'https://oauth2.googleapis.com/revoke' -Method Post -Body @{ token = $value } -ContentType 'application/x-www-form-urlencoded' -TimeoutSec 20 -ErrorAction Stop | Out-Null
            $revoked = $true
        }
    }
    Remove-Item -LiteralPath $TokenPath -Force
    [pscustomobject]@{ Disconnected = $true; Revoked = $revoked; Status = 'Google Sheets: Not Connected' }
}

function ConvertTo-SfdColumnName {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][int]$Number)
    $name = ''
    while ($Number -gt 0) {
        $Number--
        $name = [char](65 + ($Number % 26)) + $name
        $Number = [math]::Floor($Number / 26)
    }
    $name
}

function Ensure-SfdGoogleSheetHeaders {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TokenPath,
        [Parameter(Mandatory = $true)][string]$SpreadsheetId,
        [string]$TabName = 'Detail_Log'
    )

    $escapedTab = "'" + $TabName.Replace("'", "''") + "'"
    $range = [Uri]::EscapeDataString($escapedTab + '!1:1')
    $uri = 'https://sheets.googleapis.com/v4/spreadsheets/' + $SpreadsheetId + '/values/' + $range
    $existingResponse = Invoke-SfdGoogleApi -Method Get -Uri $uri -TokenPath $TokenPath
    $headers = @()
    if ($existingResponse.PSObject.Properties.Name -contains 'values' -and $existingResponse.values -and @($existingResponse.values).Count) {
        $headers = @($existingResponse.values[0] | ForEach-Object { [string]$_ })
    }
    $changed = $false
    foreach ($column in $script:SfdSheetColumns) {
        if ($column -notin $headers) { $headers += $column; $changed = $true }
    }
    if (-not $headers.Count) { $headers = @($script:SfdSheetColumns); $changed = $true }
    if ($changed) {
        $lastColumn = ConvertTo-SfdColumnName -Number $headers.Count
        $writeRange = [Uri]::EscapeDataString($escapedTab + '!A1:' + $lastColumn + '1')
        $writeUri = 'https://sheets.googleapis.com/v4/spreadsheets/' + $SpreadsheetId + '/values/' + $writeRange + '?valueInputOption=RAW'
        $headerRows = [Array]::CreateInstance([object], 1)
        $headerRows[0] = [object[]]$headers
        $null = Invoke-SfdGoogleApi -Method Put -Uri $writeUri -TokenPath $TokenPath -Body @{
            majorDimension = 'ROWS'
            values = $headerRows
        }
    }
    @($headers)
}

function Write-SfdGoogleSheetEvents {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$TokenPath,
        [Parameter(Mandatory = $true)][string]$SpreadsheetId,
        [string]$TabName = 'Detail_Log',
        [Parameter(Mandatory = $true)][object[]]$Events
    )

    $headers = @(Ensure-SfdGoogleSheetHeaders -TokenPath $TokenPath -SpreadsheetId $SpreadsheetId -TabName $TabName)
    $eventIdIndex = [array]::IndexOf($headers, 'Event_ID')
    if ($eventIdIndex -lt 0) { throw 'Detail_Log does not contain an Event_ID column.' }
    $eventIdColumn = ConvertTo-SfdColumnName -Number ($eventIdIndex + 1)
    $escapedTab = "'" + $TabName.Replace("'", "''") + "'"
    $eventIdRange = [Uri]::EscapeDataString($escapedTab + '!' + $eventIdColumn + '2:' + $eventIdColumn)
    $eventIdUri = 'https://sheets.googleapis.com/v4/spreadsheets/' + $SpreadsheetId + '/values/' + $eventIdRange
    $existingIdsResponse = Invoke-SfdGoogleApi -Method Get -Uri $eventIdUri -TokenPath $TokenPath
    $existingIds = New-Object System.Collections.Generic.HashSet[string]
    if ($existingIdsResponse.PSObject.Properties.Name -contains 'values') {
        foreach ($row in @($existingIdsResponse.values)) {
            if (@($row).Count -and [string]$row[0]) { $null = $existingIds.Add([string]$row[0]) }
        }
    }
    $rows = New-Object System.Collections.Generic.List[object]
    foreach ($event in $Events) {
        if ($existingIds.Contains([string]$event.Event_ID)) { continue }
        $row = New-Object System.Collections.Generic.List[object]
        foreach ($header in $headers) {
            if ($event.PSObject.Properties.Name -contains $header) { $row.Add($event.$header) } else { $row.Add('') }
        }
        $rows.Add([object[]]$row.ToArray())
    }
    if (-not $rows.Count) { return [pscustomobject]@{ Written = 0; Status = 'SKIPPED' } }
    $range = [Uri]::EscapeDataString($escapedTab + '!A:' + (ConvertTo-SfdColumnName -Number $headers.Count))
    $uri = 'https://sheets.googleapis.com/v4/spreadsheets/' + $SpreadsheetId + '/values/' + $range + ':append?valueInputOption=USER_ENTERED&insertDataOption=INSERT_ROWS'
    $values = [Array]::CreateInstance([object], $rows.Count)
    for ($rowIndex = 0; $rowIndex -lt $rows.Count; $rowIndex++) { $values[$rowIndex] = $rows[$rowIndex] }
    $null = Invoke-SfdGoogleApi -Method Post -Uri $uri -TokenPath $TokenPath -Body @{
        majorDimension = 'ROWS'
        values = $values
    }
    [pscustomobject]@{ Written = $rows.Count; Status = 'SUCCESS' }
}
