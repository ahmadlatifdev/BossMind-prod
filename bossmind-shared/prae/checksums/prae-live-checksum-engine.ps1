#Requires -Version 5.1
<#
.SYNOPSIS
  PRAE live checksum engine — SHA256 via .NET (no Get-FileHash dependency).

.DESCRIPTION
  Read-only checksum validation. Does not expose secret values or mutate production.
#>
$ErrorActionPreference = "Stop"
$PraeRoot = "D:\BossMind\bossmind-shared\prae"

function Get-PraeSha256Checksum {
    param([Parameter(Mandatory)][string]$FilePath)

    if (-not (Test-Path -LiteralPath $FilePath)) {
        return $null
    }

    $sha = [System.Security.Cryptography.SHA256]::Create()
    try {
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hashBytes = $sha.ComputeHash($stream)
        }
        finally {
            $stream.Close()
        }
        return ([BitConverter]::ToString($hashBytes)).Replace("-", "").ToLowerInvariant()
    }
    finally {
        $sha.Dispose()
    }
}

$Targets = @(
    "D:\BossMind\bossmind-resumora\lib\client\webhook-activation.js",
    "D:\BossMind\bossmind-resumora\pages\api\webhooks\stripe.js",
    "D:\BossMind\bossmind-resumora\pages\api\stripe\webhook-health.js",
    "D:\BossMind\bossmind-shared\prae\runtime-ledger\prae-runtime-ledger.json",
    "D:\BossMind\bossmind-shared\prae\checksums\prae-checksum-registry.json",
    "D:\BossMind\13-shared-memory\locked-interfaces.json",
    "D:\BossMind\bossmind-shared\prae\checksums\prae-checksum-report-MISSING-TEST.json"
)

$Checksums = @()

foreach ($Target in $Targets) {
    if (Test-Path -LiteralPath $Target) {
        $hash = Get-PraeSha256Checksum -FilePath $Target
        if ([string]::IsNullOrWhiteSpace($hash)) {
            throw "SHA256 generation failed for existing file: $Target"
        }
        $Checksums += [ordered]@{
            file      = $Target
            exists    = $true
            algorithm = "SHA256"
            checksum  = $hash
        }
    }
    else {
        $Checksums += [ordered]@{
            file      = $Target
            exists    = $false
            algorithm = "SHA256"
            checksum  = "FILE_NOT_FOUND"
        }
    }
}

$nullChecksums = @($Checksums | Where-Object { $null -eq $_.checksum -or [string]::IsNullOrWhiteSpace([string]$_.checksum) })
if ($Checksums.Count -eq 0) {
    throw "PRAE checksum engine produced empty checksums array"
}
if ($nullChecksums.Count -gt 0) {
    throw "PRAE checksum engine produced null/empty checksum values"
}

$Report = [ordered]@{
    schema              = "bossmind-prae-checksum-report/v1"
    timestamp_utc       = (Get-Date).ToUniversalTime().ToString("o")
    event               = "PRAE_LIVE_CHECKSUM_VALIDATION"
    authority           = "PRAE_ONLY"
    governance_mode     = "LOCKED"
    deployment_mode     = "STAGED"
    production_mutation = "NONE"
    auto_repair         = "DISABLED"
    secret_values_exposed = $false
    hash_method         = "System.Security.Cryptography.SHA256"
    checksum_count      = $Checksums.Count
    checksums           = @($Checksums)
}

$ReportPath = Join-Path $PraeRoot "checksums\prae-checksum-report.json"
$ReportJson = $Report | ConvertTo-Json -Depth 30
Set-Content -Path $ReportPath -Value $ReportJson -Encoding UTF8

$LedgerEvent = @{
    timestamp_utc       = $Report.timestamp_utc
    event               = "PRAE_LIVE_CHECKSUM_VALIDATION"
    authority           = "PRAE_ONLY"
    governance_mode     = "LOCKED"
    deployment_mode     = "STAGED"
    production_mutation = "NONE"
    auto_repair         = "DISABLED"
    secret_values_exposed = $false
    hash_method         = "System.Security.Cryptography.SHA256"
    checksum_count      = $Checksums.Count
    result              = "SUCCESS"
    checksums           = @($Checksums)
} | ConvertTo-Json -Depth 30 -Compress

Add-Content -Path (Join-Path $PraeRoot "runtime-ledger\prae-events.log") -Value $LedgerEvent -Encoding UTF8

Write-Host ""
Write-Host "====================================="
Write-Host " PRAE LIVE CHECKSUM ENGINE ACTIVE"
Write-Host "====================================="
Write-Host ""
Write-Host "Governance Mode     : LOCKED"
Write-Host "Deployment Mode     : STAGED"
Write-Host "Production Mutation : NONE"
Write-Host "Auto Repair         : DISABLED"
Write-Host "Hash Method         : .NET SHA256"
Write-Host "Checksum Count      : $($Checksums.Count)"
Write-Host ""
Write-Host $ReportJson
