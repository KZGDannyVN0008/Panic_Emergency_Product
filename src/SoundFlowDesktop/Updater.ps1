Set-StrictMode -Version 2.0

function ConvertTo-SfdVersion {
    [CmdletBinding()]
    param([Parameter(Mandatory = $true)][string]$Value)
    if ($Value -notmatch '^v?(\d+)\.(\d+)\.(\d+)$') { throw "Invalid semantic version: $Value" }
    [version]("$($matches[1]).$($matches[2]).$($matches[3])")
}

function Test-SfdAuthenticodePublisher {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$Path,
        [Parameter(Mandatory = $true)][string]$TrustedPublisher
    )
    if ($env:OS -ne 'Windows_NT') { throw 'Authenticode validation requires Windows.' }
    $signature = Get-AuthenticodeSignature -LiteralPath $Path
    if ($signature.Status -ne 'Valid' -or -not $signature.SignerCertificate) { return $false }
    [string]$signature.SignerCertificate.Subject -like ('*' + $TrustedPublisher + '*')
}

function Invoke-SfdUpdate {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][string]$MetadataUrl,
        [Parameter(Mandatory = $true)][string]$CurrentVersion,
        [Parameter(Mandatory = $true)][string]$TrustedPublisher,
        [Parameter(Mandatory = $true)][string]$StagingDirectory,
        [Parameter(Mandatory = $true)][string]$ProgramDirectory,
        [Parameter(Mandatory = $true)][string]$RollbackDirectory,
        [string]$ProductionLockPath,
        [switch]$AllowDowngrade,
        [switch]$DownloadOnly,
        [scriptblock]$MetadataHandler,
        [scriptblock]$DownloadHandler,
        [scriptblock]$SignatureHandler,
        [scriptblock]$PackageVersionHandler,
        [scriptblock]$InstallHandler
    )

    if ($ProductionLockPath -and (Test-Path -LiteralPath $ProductionLockPath)) {
        $lockProbe = $null
        try {
            $lockProbe = [IO.File]::Open($ProductionLockPath, [IO.FileMode]::Open, [IO.FileAccess]::ReadWrite, [IO.FileShare]::None)
        } catch {
            throw 'An update cannot run while Production is active.'
        } finally {
            if ($lockProbe) { $lockProbe.Dispose() }
        }
    }
    if ($MetadataUrl -notmatch '^https://') { throw 'Update metadata must use HTTPS.' }
    $metadata = if ($MetadataHandler) { & $MetadataHandler $MetadataUrl } else { Invoke-RestMethod -Uri $MetadataUrl -Method Get -TimeoutSec 15 -ErrorAction Stop }
    if ([int]$metadata.schema_version -ne 1) { throw 'Unsupported update manifest schema.' }
    $available = ConvertTo-SfdVersion -Value ([string]$metadata.version)
    $current = ConvertTo-SfdVersion -Value $CurrentVersion
    if (-not $AllowDowngrade -and $available -le $current) {
        return [pscustomobject]@{ Status = 'CURRENT'; Version = [string]$metadata.version; PackagePath = '' }
    }
    if ([string]$metadata.windows.setup_url -notmatch '^https://' -or [string]$metadata.windows.sha256 -notmatch '^[a-fA-F0-9]{64}$') {
        throw 'The Windows update entry is invalid.'
    }
    New-Item -ItemType Directory -Path $StagingDirectory -Force | Out-Null
    $packagePath = Join-Path $StagingDirectory 'SoundFlowDesktop-Setup.exe'
    if ($DownloadHandler) {
        & $DownloadHandler ([string]$metadata.windows.setup_url) $packagePath
    } else {
        Invoke-WebRequest -Uri ([string]$metadata.windows.setup_url) -OutFile $packagePath -UseBasicParsing -TimeoutSec 120
    }
    $actualHash = (Get-FileHash -LiteralPath $packagePath -Algorithm SHA256).Hash
    if ($actualHash -ne [string]$metadata.windows.sha256) {
        Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        throw 'The update package checksum does not match.'
    }
    $signatureTrusted = if ($SignatureHandler) { [bool](& $SignatureHandler $packagePath $TrustedPublisher) } else { Test-SfdAuthenticodePublisher -Path $packagePath -TrustedPublisher $TrustedPublisher }
    if (-not $signatureTrusted) {
        Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        throw 'The update package publisher signature is not trusted.'
    }
    $packageVersion = if ($PackageVersionHandler) {
        [string](& $PackageVersionHandler $packagePath)
    } else {
        [string](Get-Item -LiteralPath $packagePath).VersionInfo.ProductVersion
    }
    if ((ConvertTo-SfdVersion -Value $packageVersion) -ne $available) {
        Remove-Item -LiteralPath $packagePath -Force -ErrorAction SilentlyContinue
        throw 'The update package identity version does not match the release manifest.'
    }
    if ($DownloadOnly) {
        return [pscustomobject]@{ Status = 'VERIFIED'; Version = [string]$metadata.version; PackagePath = $packagePath }
    }
    if (-not (Test-Path -LiteralPath $ProgramDirectory -PathType Container)) {
        throw "The installed program directory was not found: $ProgramDirectory"
    }
    if (Test-Path -LiteralPath $RollbackDirectory) {
        Remove-Item -LiteralPath $RollbackDirectory -Recurse -Force
    }
    New-Item -ItemType Directory -Path $RollbackDirectory -Force | Out-Null
    Copy-Item -Path (Join-Path $ProgramDirectory '*') -Destination $RollbackDirectory -Recurse -Force
    $installerExitCode = if ($InstallHandler) {
        [int](& $InstallHandler $packagePath $ProgramDirectory)
    } else {
        $process = Start-Process -FilePath $packagePath -ArgumentList '/UPDATE=1','/VERYSILENT','/SUPPRESSMSGBOXES','/NORESTART' -Wait -PassThru
        [int]$process.ExitCode
    }
    if ($installerExitCode -ne 0) {
        foreach ($child in @(Get-ChildItem -LiteralPath $ProgramDirectory -Force -ErrorAction SilentlyContinue)) {
            Remove-Item -LiteralPath $child.FullName -Recurse -Force -ErrorAction SilentlyContinue
        }
        Copy-Item -Path (Join-Path $RollbackDirectory '*') -Destination $ProgramDirectory -Recurse -Force
        throw "The update installer failed with exit code $installerExitCode; the previous program files were restored."
    }
    [pscustomobject]@{ Status = 'UPDATED'; Version = [string]$metadata.version; PackagePath = $packagePath }
}
