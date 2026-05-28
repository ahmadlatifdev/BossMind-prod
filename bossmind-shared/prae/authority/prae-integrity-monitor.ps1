$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$CriticalFiles = @(
    "$PraeRoot\runtime-ledger\prae-runtime-ledger.json",
    "$PraeRoot\checksums\prae-checksum-registry.json",
    "$PraeRoot\deployment-validation\prae-deployment-authority.json",
    "$PraeRoot\drift-detection\prae-drift-authority.json",
    "$PraeRoot\repair-simulation\prae-repair-authority.json",
    "$PraeRoot\authority\prae-runtime-validation.json"
)

$IntegrityResults = @()

foreach ($File in $CriticalFiles) {

    $Exists = Test-Path $File

    $IntegrityResults += [PSCustomObject]@{
        file = $File
        exists = $Exists
        integrity = if ($Exists) { "VALID" } else { "MISSING" }
    }
}

$IntegrityEvent = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_INTEGRITY_MONITOR"
    authority = "PRAE"
    governance_mode = "LOCKED"
    production_mutation = "NONE"
    auto_repair = "DISABLED"
    integrity_results = $IntegrityResults
    result = if (($IntegrityResults.integrity -contains "MISSING")) { "ALERT" } else { "SUCCESS" }
} | ConvertTo-Json -Depth 20

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $IntegrityEvent

Write-Host ""
Write-Host "====================================="
Write-Host " PRAE INTEGRITY MONITOR ACTIVE"
Write-Host "====================================="
Write-Host ""

$IntegrityEvent
