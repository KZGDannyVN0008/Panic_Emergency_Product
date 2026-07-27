Set-StrictMode -Version 2.0

function Test-SfdLarkResponse {
    [CmdletBinding()]
    param($Response)

    if ($null -eq $Response) { return $false }
    if ($Response.PSObject.Properties['code'] -and [int]$Response.code -eq 0) { return $true }
    if ($Response.PSObject.Properties['StatusCode'] -and [int]$Response.StatusCode -eq 0) { return $true }
    $false
}

function Invoke-SfdLarkSummary {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$WebhookUrl,
        [Parameter(Mandatory = $true)][string]$Title,
        [Parameter(Mandatory = $true)][string]$Summary,
        [ValidateSet('blue', 'green', 'yellow', 'orange', 'red')][string]$Color = 'blue',
        [int]$Attempts = 2
    )

    if ($WebhookUrl -notmatch '^https://open\.larksuite\.com/open-apis/bot/v2/hook/[A-Za-z0-9-]+$') {
        throw 'The configured Lark webhook URL is invalid.'
    }
    $body = Protect-SfdSecretText -Text $Summary
    if ($body.Length -gt 6000) { $body = $body.Substring(0, 6000) }
    $payload = @{
        msg_type = 'interactive'
        card = @{
            config = @{ wide_screen_mode = $true }
            header = @{ title = @{ tag = 'plain_text'; content = $Title }; template = $Color }
            elements = @(@{ tag = 'div'; text = @{ tag = 'lark_md'; content = $body } })
        }
    } | ConvertTo-Json -Depth 20 -Compress
    $errorText = ''
    for ($attempt = 1; $attempt -le $Attempts; $attempt++) {
        try {
            $response = Invoke-RestMethod -Uri $WebhookUrl -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 10 -ErrorAction Stop
            if (Test-SfdLarkResponse -Response $response) {
                return [pscustomobject]@{ Delivered = $true; Status = 'SUCCESS'; Error = '' }
            }
            $errorText = 'Lark returned a non-success response.'
        } catch {
            $errorText = Protect-SfdSecretText -Text $_.Exception.Message
        }
        if ($attempt -lt $Attempts) { Start-Sleep -Seconds $attempt }
    }
    [pscustomobject]@{ Delivered = $false; Status = 'QUEUED'; Error = $errorText }
}

function Get-SfdLarkTenantToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$AppId,
        [Parameter(Mandatory = $true)][string]$AppSecret
    )

    $payload = @{ app_id = $AppId; app_secret = $AppSecret } | ConvertTo-Json -Compress
    $response = Invoke-RestMethod -Uri 'https://open.larksuite.com/open-apis/auth/v3/tenant_access_token/internal' -Method Post -Body $payload -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 -ErrorAction Stop
    if ([int]$response.code -ne 0 -or -not $response.tenant_access_token) {
        throw 'Lark app authentication failed.'
    }
    [string]$response.tenant_access_token
}

function Send-SfdLarkFile {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Token,
        [Parameter(Mandatory = $true)][string]$Path
    )

    Add-Type -AssemblyName System.Net.Http
    $client = [Net.Http.HttpClient]::new()
    $client.DefaultRequestHeaders.Authorization = [Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $Token)
    $content = [Net.Http.MultipartFormDataContent]::new()
    $fileType = [Net.Http.StringContent]::new('stream')
    $content.Add($fileType, 'file_type')
    $fileName = [IO.Path]::GetFileName($Path)
    $fileBytes = [IO.File]::ReadAllBytes($Path)
    $fileContent = [Net.Http.ByteArrayContent]::new($fileBytes)
    $fileContent.Headers.ContentType = [Net.Http.Headers.MediaTypeHeaderValue]::new('text/plain')
    $content.Add($fileContent, 'file', $fileName)
    try {
        $response = $client.PostAsync('https://open.larksuite.com/open-apis/im/v1/files', $content).GetAwaiter().GetResult()
        $json = $response.Content.ReadAsStringAsync().GetAwaiter().GetResult() | ConvertFrom-Json
        if (-not $response.IsSuccessStatusCode -or [int]$json.code -ne 0 -or -not $json.data.file_key) {
            throw 'Lark file upload failed.'
        }
        [string]$json.data.file_key
    } finally {
        $content.Dispose()
        $client.Dispose()
    }
}

function Invoke-SfdLarkReportUpload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$ReportPath,
        [string]$AppId,
        [string]$AppSecret,
        [string]$ReceiveId,
        [ValidateSet('chat_id', 'open_id', 'user_id', 'union_id', 'email')][string]$ReceiveIdType = 'chat_id',
        [scriptblock]$TokenHandler,
        [scriptblock]$FileUploadHandler,
        [scriptblock]$MessageHandler
    )

    if (-not $AppId -or -not $AppSecret -or -not $ReceiveId) {
        return [pscustomobject]@{
            Delivered = $false
            Status = 'PENDING_CREDENTIALS'
            Error = 'Lark app-bot credentials and destination are required for TXT delivery.'
        }
    }
    try {
        $token = if ($TokenHandler) { & $TokenHandler $AppId $AppSecret } else { Get-SfdLarkTenantToken -AppId $AppId -AppSecret $AppSecret }
        $fileKey = if ($FileUploadHandler) { & $FileUploadHandler $token $ReportPath } else { Send-SfdLarkFile -Token $token -Path $ReportPath }
        $messageBody = @{
            receive_id = $ReceiveId
            msg_type = 'file'
            content = (@{ file_key = $fileKey } | ConvertTo-Json -Compress)
        } | ConvertTo-Json -Compress
        $uri = 'https://open.larksuite.com/open-apis/im/v1/messages?receive_id_type=' + [Uri]::EscapeDataString($ReceiveIdType)
        $headers = @{ Authorization = 'Bearer ' + $token }
        if ($MessageHandler) {
            if (-not (& $MessageHandler $token $uri $messageBody)) { throw 'Lark file message delivery failed.' }
        } else {
            $response = Invoke-RestMethod -Uri $uri -Method Post -Headers $headers -Body $messageBody -ContentType 'application/json; charset=utf-8' -TimeoutSec 15 -ErrorAction Stop
            if ([int]$response.code -ne 0) { throw 'Lark file message delivery failed.' }
        }
        [pscustomobject]@{ Delivered = $true; Status = 'SUCCESS'; Error = '' }
    } catch {
        [pscustomobject]@{ Delivered = $false; Status = 'QUEUED'; Error = Protect-SfdSecretText -Text $_.Exception.Message }
    }
}
