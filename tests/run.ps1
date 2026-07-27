[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$repositoryRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
$modulePath = Join-Path $repositoryRoot 'src\SoundFlowDesktop\SoundFlowDesktop.psd1'
$passed = 0

function Assert-Sfd {
    param([bool]$Condition, [string]$Message)
    if (-not $Condition) { throw "ASSERTION FAILED: $Message" }
    $script:passed++
    Write-Host "PASS: $Message"
}

foreach ($scriptFile in Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1') }) {
    $tokens = $null
    $errors = $null
    [Management.Automation.Language.Parser]::ParseFile($scriptFile.FullName, [ref]$tokens, [ref]$errors) | Out-Null
    Assert-Sfd ($errors.Count -eq 0) "PowerShell syntax: $($scriptFile.FullName.Substring($repositoryRoot.Length + 1))"
}

Import-Module $modulePath -Force
$manifestPath = Join-Path $repositoryRoot 'config\targets.windows.v1.json'
$manifest = Import-SfdTargetManifest -Path $manifestPath
Assert-Sfd (@($manifest.targets).Count -ge 50) 'Target manifest includes the requested initial coverage'
Assert-Sfd (@($manifest.targets | Group-Object target_id | Where-Object { $_.Count -gt 1 }).Count -eq 0) 'Target IDs are unique'
Assert-Sfd (@($manifest.targets | Where-Object { $_.uninstall_allowed }).Count -eq 0) 'Uninstall fallback remains disabled pending an explicit allowlist'

$environmentMap = @{
    USERPROFILE = 'C:\Users\Fixture'
    LOCALAPPDATA = 'C:\Users\Fixture\AppData\Local'
    APPDATA = 'C:\Users\Fixture\AppData\Roaming'
    PROGRAMDATA = 'C:\ProgramData'
    PROGRAMFILES = 'C:\Program Files'
    'PROGRAMFILES(X86)' = 'C:\Program Files (x86)'
    SYSTEMROOT = 'C:\Windows'
    SYSTEMDRIVE = 'C:'
    TEMP = 'C:\Users\Fixture\AppData\Local\Temp'
}
$resolved = Resolve-SfdTargetPath -Path '%LOCALAPPDATA%\Vendor\Product' -EnvironmentMap $environmentMap
Assert-Sfd ($resolved -eq 'C:\Users\Fixture\AppData\Local\Vendor\Product') 'Target variables resolve to a canonical path'
$unresolvedRejected = $false
try { $null = Resolve-SfdTargetPath -Path '%MISSING%\Product' -EnvironmentMap $environmentMap } catch { $unresolvedRejected = $true }
Assert-Sfd $unresolvedRejected 'Unresolved target variables are rejected'

$safe = Test-SfdCleanupPath -Path 'C:\Users\Fixture\AppData\Local\Vendor\Product' -ApprovedBases @('C:\Users\Fixture\AppData\Local\Vendor\Product') -ProtectedPaths @('C:\Windows', 'C:\Program Files') -AllowMissing
Assert-Sfd $safe.Safe 'A manifest-approved bounded path is accepted'
$root = Test-SfdCleanupPath -Path 'C:\' -ApprovedBases @('C:\') -ProtectedPaths @('C:\Windows') -AllowMissing
Assert-Sfd (-not $root.Safe -and 'DRIVE_ROOT' -in $root.Reasons) 'Drive roots are rejected'
$broad = Test-SfdCleanupPath -Path 'C:\Users\Fixture' -ApprovedBases @('C:\Users\Fixture\AppData\Local\Vendor') -ProtectedPaths @('C:\Windows') -AllowMissing
Assert-Sfd (-not $broad.Safe) 'Paths outside an approved target base are rejected'
$sync = Test-SfdCleanupPath -Path 'C:\Users\Fixture\OneDrive\Approved' -ApprovedBases @('C:\Users\Fixture\OneDrive\Approved') -ProtectedPaths @('C:\Windows') -ActiveSyncRoots @('C:\Users\Fixture\OneDrive') -AllowMissing
Assert-Sfd (-not $sync.Safe -and 'ACTIVE_SYNC_ROOT' -in $sync.Reasons) 'Active synchronized roots are rejected'

$temporary = Join-Path ([IO.Path]::GetTempPath()) ('sfd-tests-' + [guid]::NewGuid().ToString('N'))
New-Item -ItemType Directory -Path $temporary -Force | Out-Null
try {
    $queuePath = Join-Path $temporary 'queue\delivery.jsonl'
    Assert-Sfd (Add-SfdQueueRecord -Path $queuePath -EventId 'EVT-1' -Destination GOOGLE_SHEETS -Payload @{ value = 1 }) 'First queue record is added'
    Assert-Sfd (-not (Add-SfdQueueRecord -Path $queuePath -EventId 'EVT-1' -Destination GOOGLE_SHEETS -Payload @{ value = 1 })) 'Duplicate Event ID and destination are rejected'
    $retry = Invoke-SfdQueueRetry -Path $queuePath -DeliveryHandler { param($item) return $item.event_id -eq 'EVT-1' }
    Assert-Sfd ($retry.Delivered -eq 1 -and $retry.Remaining -eq 0) 'Queue retry delivers once and removes the record'

    function global:Invoke-RestMethod {
        param($Uri, $Method, $Body, $ContentType, $TimeoutSec, $ErrorAction)
        if ($script:SfdMockFailure) { throw 'mock delivery failure' }
        [pscustomobject]@{ code = 0 }
    }
    $script:SfdMockFailure = $false
    $larkSuccess = Invoke-SfdLarkSummary -WebhookUrl 'https://open.larksuite.com/open-apis/bot/v2/hook/00000000-0000-0000-0000-000000000000' -Title 'Fixture' -Summary 'Safe test'
    Assert-Sfd $larkSuccess.Delivered 'Lark summary success boundary is exercised with a mock'
    $script:SfdMockFailure = $true
    $larkFailure = Invoke-SfdLarkSummary -WebhookUrl 'https://open.larksuite.com/open-apis/bot/v2/hook/00000000-0000-0000-0000-000000000000' -Title 'Fixture' -Summary 'Safe test' -Attempts 1
    Assert-Sfd (-not $larkFailure.Delivered -and $larkFailure.Status -eq 'QUEUED') 'Lark summary failure returns a queueable result'
    Remove-Item Function:\Invoke-RestMethod -Force

    $reportFixture = Join-Path $temporary 'fixture-report.txt'
    Set-Content -LiteralPath $reportFixture -Value 'fixture report' -Encoding UTF8
    $fileSuccess = Invoke-SfdLarkReportUpload -ReportPath $reportFixture -AppId 'fixture-app' -AppSecret 'fixture-secret' -ReceiveId 'fixture-chat' -TokenHandler { 'fixture-token' } -FileUploadHandler { 'fixture-file-key' } -MessageHandler { $true }
    Assert-Sfd $fileSuccess.Delivered 'Lark TXT upload and message success boundary is exercised with mocks'
    $fileFailure = Invoke-SfdLarkReportUpload -ReportPath $reportFixture -AppId 'fixture-app' -AppSecret 'fixture-secret' -ReceiveId 'fixture-chat' -TokenHandler { throw 'mock upload failure' } -FileUploadHandler { 'unused' } -MessageHandler { $true }
    Assert-Sfd (-not $fileFailure.Delivered -and $fileFailure.Status -eq 'QUEUED') 'Lark TXT upload failure returns a queueable result'
    $filePending = Invoke-SfdLarkReportUpload -ReportPath $reportFixture
    Assert-Sfd ($filePending.Status -eq 'PENDING_CREDENTIALS') 'Lark TXT upload never reports delivery without app-bot credentials'

    $tokenPath = Join-Path $temporary 'credentials\google-token.dpapi'
    New-Item -ItemType Directory -Path (Split-Path -Parent $tokenPath) -Force | Out-Null
    $tokenJson = [ordered]@{
        access_token = 'mock-access-token'
        refresh_token = 'mock-refresh-token'
        expires_at = [DateTimeOffset]::UtcNow.AddHours(1).ToUnixTimeSeconds()
        client_id = 'mock-client'
        token_uri = 'https://oauth2.googleapis.com/token'
    } | ConvertTo-Json -Compress
    Set-Content -LiteralPath $tokenPath -Value (Protect-SfdDpapiValue -PlainText $tokenJson) -Encoding Ascii
    $script:SfdGoogleBodies = New-Object System.Collections.Generic.List[string]
    function global:Invoke-RestMethod {
        param($Uri, $Method, $Headers, $Body, $ContentType, $TimeoutSec, $ErrorAction)
        if ($Body) { $script:SfdGoogleBodies.Add([string]$Body) }
        if ($Uri -match '1%3A1') {
            return [pscustomobject]@{ values = @(@('Custom_Column', 'Event_ID')) }
        }
        if ($Uri -match 'B2%3AB') { return [pscustomobject]@{} }
        [pscustomobject]@{}
    }
    $sheetEvent = New-SfdEvent -IncidentId 'SFD-SHEET-TEST' -Category SCAN -Action SCAN_TARGET -Status SUCCESS -Mode DRY_RUN -Context @{} -Target @{ Target_Name = 'Fixture' }
    $sheetWrite = Write-SfdGoogleSheetEvents -TokenPath $tokenPath -SpreadsheetId 'fixture-sheet' -TabName 'Detail_Log' -Events @($sheetEvent)
    Assert-Sfd ($sheetWrite.Written -eq 1) 'Google Sheets append boundary succeeds with mocked HTTP'
    Assert-Sfd (@($script:SfdGoogleBodies | Where-Object { $_ -match [regex]::Escape($sheetEvent.Event_ID) }).Count -eq 1) 'Google Sheets payload contains the stable Event ID once'
    Remove-Item Function:\Invoke-RestMethod -Force

    $reportPath = Join-Path $temporary 'reports\fixture.txt'
    $result = [pscustomobject]@{
        TargetId = 'fixture.target'; Category = 'OTHER_APPROVED'; DisplayName = 'Fixture'
        Installed = $true; Running = $false; RunningProcessIds = @()
        Locations = @([pscustomobject]@{ Path = 'C:\Fixture'; Exists = $true; Files = 2; Directories = 1; Bytes = 1024; Profiles = 0 })
        Result = 'DETECTED'; Supported = $false
    }
    $context = @{ Device_Name = 'FIXTURE'; Full_Name = 'Test User'; Department = 'QA' }
    $report = New-SfdTextReport -Path $reportPath -IncidentId 'SFD-TEST' -Mode DRY_RUN -BeforeResults @($result) -Context $context
    Assert-Sfd ($report.Exists -and (Get-Content -LiteralPath $reportPath -Raw) -match 'Fixture') 'TXT report is generated from discovery results'

    $fixtureTarget = [pscustomobject]@{
        target_id = 'fixture.target'
        process_names = @('ProcessThatDoesNotExistSfd')
        approved_data_paths = @('C:\Fixture\DoesNotExist')
        credential_filters = @()
        cleanup_strategy = 'CLEAR_APPROVED_PATHS'
    }
    $cleanup = Invoke-SfdTargetCleanup -Target $fixtureTarget -EnvironmentMap $environmentMap -ProtectedPaths @('C:\Windows') -WhatIf -Confirm:$false
    Assert-Sfd ($cleanup.Result -eq 'CLEANED') 'WhatIf cleanup exercises the boundary without stopping processes or deleting data'

    $updateSource = Join-Path $temporary 'signed-setup-fixture.exe'
    Set-Content -LiteralPath $updateSource -Value 'signed setup fixture' -Encoding Ascii
    $updateHash = (Get-FileHash -LiteralPath $updateSource -Algorithm SHA256).Hash.ToLowerInvariant()
    $updateMetadata = [pscustomobject]@{
        schema_version = 1
        version = '1.1.0'
        windows = [pscustomobject]@{ setup_url = 'https://example.invalid/SoundFlowDesktop-Setup.exe'; sha256 = $updateHash }
    }
    $updateProgram = Join-Path $temporary 'program'
    $updateStaging = Join-Path $temporary 'update-staging'
    $updateRollback = Join-Path $temporary 'rollback'
    New-Item -ItemType Directory -Path $updateProgram -Force | Out-Null
    Set-Content -LiteralPath (Join-Path $updateProgram 'version.txt') -Value '1.0.0'
    $verifiedUpdate = Invoke-SfdUpdate -MetadataUrl 'https://example.invalid/update-manifest.json' -CurrentVersion '1.0.0' -TrustedPublisher 'Fixture' -StagingDirectory $updateStaging -ProgramDirectory $updateProgram -RollbackDirectory $updateRollback -DownloadOnly -MetadataHandler { $updateMetadata } -DownloadHandler { param($uri, $destination) Copy-Item -LiteralPath $updateSource -Destination $destination } -SignatureHandler { $true } -PackageVersionHandler { '1.1.0' }
    Assert-Sfd ($verifiedUpdate.Status -eq 'VERIFIED') 'Updater accepts matching checksum and trusted signature through safe test handlers'

    $badMetadata = [pscustomobject]@{
        schema_version = 1
        version = '1.1.0'
        windows = [pscustomobject]@{ setup_url = 'https://example.invalid/SoundFlowDesktop-Setup.exe'; sha256 = ('f' * 64) }
    }
    $checksumRejected = $false
    try {
        $null = Invoke-SfdUpdate -MetadataUrl 'https://example.invalid/update-manifest.json' -CurrentVersion '1.0.0' -TrustedPublisher 'Fixture' -StagingDirectory (Join-Path $temporary 'bad-staging') -ProgramDirectory $updateProgram -RollbackDirectory $updateRollback -DownloadOnly -MetadataHandler { $badMetadata } -DownloadHandler { param($uri, $destination) Copy-Item -LiteralPath $updateSource -Destination $destination } -SignatureHandler { $true } -PackageVersionHandler { '1.1.0' }
    } catch { $checksumRejected = $true }
    Assert-Sfd $checksumRejected 'Updater rejects an invalid SHA-256'

    $signatureRejected = $false
    try {
        $null = Invoke-SfdUpdate -MetadataUrl 'https://example.invalid/update-manifest.json' -CurrentVersion '1.0.0' -TrustedPublisher 'Fixture' -StagingDirectory (Join-Path $temporary 'signature-staging') -ProgramDirectory $updateProgram -RollbackDirectory $updateRollback -DownloadOnly -MetadataHandler { $updateMetadata } -DownloadHandler { param($uri, $destination) Copy-Item -LiteralPath $updateSource -Destination $destination } -SignatureHandler { $false } -PackageVersionHandler { '1.1.0' }
    } catch { $signatureRejected = $true }
    Assert-Sfd $signatureRejected 'Updater rejects an untrusted package signature'

    $olderMetadata = [pscustomobject]@{
        schema_version = 1
        version = '0.9.0'
        windows = [pscustomobject]@{ setup_url = 'https://example.invalid/SoundFlowDesktop-Setup.exe'; sha256 = $updateHash }
    }
    $downgrade = Invoke-SfdUpdate -MetadataUrl 'https://example.invalid/update-manifest.json' -CurrentVersion '1.0.0' -TrustedPublisher 'Fixture' -StagingDirectory (Join-Path $temporary 'downgrade-staging') -ProgramDirectory $updateProgram -RollbackDirectory $updateRollback -DownloadOnly -MetadataHandler { $olderMetadata } -DownloadHandler { throw 'download must not run' } -SignatureHandler { $true }
    Assert-Sfd ($downgrade.Status -eq 'CURRENT') 'Updater refuses an unapproved downgrade before download'

    $rollbackTriggered = $false
    try {
        $null = Invoke-SfdUpdate -MetadataUrl 'https://example.invalid/update-manifest.json' -CurrentVersion '1.0.0' -TrustedPublisher 'Fixture' -StagingDirectory (Join-Path $temporary 'rollback-staging') -ProgramDirectory $updateProgram -RollbackDirectory $updateRollback -MetadataHandler { $updateMetadata } -DownloadHandler { param($uri, $destination) Copy-Item -LiteralPath $updateSource -Destination $destination } -SignatureHandler { $true } -PackageVersionHandler { '1.1.0' } -InstallHandler { param($package, $program) Set-Content -LiteralPath (Join-Path $program 'version.txt') -Value 'broken'; return 1 }
    } catch { $rollbackTriggered = $true }
    Assert-Sfd ($rollbackTriggered -and (Get-Content -LiteralPath (Join-Path $updateProgram 'version.txt') -Raw).Trim() -eq '1.0.0') 'Failed update restores the previous program files'
} finally {
    Remove-Item -LiteralPath $temporary -Recurse -Force -ErrorAction SilentlyContinue
}

$sourceText = (Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
    Where-Object { $_.Extension -in @('.ps1', '.psm1', '.psd1', '.json', '.md', '.iss') } |
    ForEach-Object { Get-Content -LiteralPath $_.FullName -Raw }) -join "`n"
Assert-Sfd ($sourceText -notmatch 'open\.larksuite\.com/open-apis/bot/v2/hook/[0-9a-f]{8}-[0-9a-f-]{20,}') 'No real Lark webhook is present in source'
Assert-Sfd ($sourceText -match 'PRODUCTION_STARTED') 'Production-started alert is implemented'
Assert-Sfd ($sourceText -match 'Get-AuthenticodeSignature') 'Updater checks the trusted package signature'
Assert-Sfd ($sourceText -match 'Get-FileHash.+SHA256') 'Updater checks the package checksum'

$prohibited = '(?i)(^|[._-])(final(_v2)?|latest|new|fixed|backup|copy)([._-]|$)'
$badNames = @(Get-ChildItem -LiteralPath $repositoryRoot -Recurse -File |
    Where-Object { $_.Name -match $prohibited })
Assert-Sfd ($badNames.Count -eq 0) 'Repository filenames avoid prohibited migration suffixes'

Write-Host "SoundFlow Desktop tests completed: $passed assertions passed."
