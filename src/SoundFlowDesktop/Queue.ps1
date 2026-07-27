Set-StrictMode -Version 2.0

function Get-SfdQueueItems {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Path)

    $items = New-Object System.Collections.Generic.List[object]
    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return @() }
    foreach ($line in Get-Content -LiteralPath $Path -Encoding UTF8) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        try { $items.Add(($line | ConvertFrom-Json)) }
        catch {
            $items.Add([pscustomobject]@{
                event_id = ''
                destination = 'INVALID'
                created_at = ''
                attempts = 0
                payload = $null
                last_error = 'INVALID_QUEUE_RECORD'
                raw_record = $line
            })
        }
    }
    $items.ToArray()
}

function Add-SfdQueueRecord {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$EventId,
        [Parameter(Mandatory = $true)][ValidateSet('LARK_SUMMARY', 'LARK_REPORT', 'GOOGLE_SHEETS')][string]$Destination,
        [Parameter(Mandatory = $true)]$Payload,
        [string]$LastError = ''
    )

    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $existing = @(Get-SfdQueueItems -Path $Path | Where-Object {
        $_.event_id -eq $EventId -and $_.destination -eq $Destination
    })
    if ($existing.Count) { return $false }
    $record = [ordered]@{
        event_id = $EventId
        destination = $Destination
        created_at = (Get-Date).ToUniversalTime().ToString('o')
        attempts = 0
        payload = $Payload
        last_error = Protect-SfdSecretText -Text $LastError
    }
    ($record | ConvertTo-Json -Depth 30 -Compress) |
        Add-Content -LiteralPath $Path -Encoding UTF8
    $true
}

function Write-SfdQueueItems {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][object[]]$Items
    )

    if (-not $Items.Count) {
        if (Test-Path -LiteralPath $Path) {
            Remove-Item -LiteralPath $Path -Force
        }
        return
    }
    $parent = Split-Path -Parent $Path
    New-Item -ItemType Directory -Path $parent -Force | Out-Null
    $temporary = Join-Path $parent ('.queue.' + [guid]::NewGuid().ToString('N') + '.tmp')
    try {
        $lines = @($Items | ForEach-Object { $_ | ConvertTo-Json -Depth 30 -Compress })
        Set-Content -LiteralPath $temporary -Value $lines -Encoding UTF8
        if (Test-Path -LiteralPath $Path) {
            [IO.File]::Replace($temporary, $Path, $null, $true)
        } else {
            [IO.File]::Move($temporary, $Path)
        }
    } finally {
        if (Test-Path -LiteralPath $temporary) {
            Remove-Item -LiteralPath $temporary -Force -ErrorAction SilentlyContinue
        }
    }
}

function Invoke-SfdQueueRetry {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][scriptblock]$DeliveryHandler,
        [int]$MaximumItems = 100
    )

    $remaining = New-Object System.Collections.Generic.List[object]
    $delivered = New-Object System.Collections.Generic.List[string]
    $items = @(Get-SfdQueueItems -Path $Path)
    $processed = 0
    foreach ($item in $items) {
        if ($processed -ge $MaximumItems -or $item.destination -eq 'INVALID') {
            $remaining.Add($item)
            continue
        }
        $processed++
        try {
            $ok = [bool](& $DeliveryHandler $item)
            if ($ok) {
                $delivered.Add([string]$item.event_id)
            } else {
                $item.attempts = [int]$item.attempts + 1
                $remaining.Add($item)
            }
        } catch {
            $item.attempts = [int]$item.attempts + 1
            $item.last_error = Protect-SfdSecretText -Text $_.Exception.Message
            $remaining.Add($item)
        }
    }
    Write-SfdQueueItems -Path $Path -Items $remaining.ToArray()
    [pscustomobject]@{
        Processed = $processed
        Delivered = $delivered.Count
        Remaining = $remaining.Count
        DeliveredEventIds = $delivered.ToArray()
    }
}
