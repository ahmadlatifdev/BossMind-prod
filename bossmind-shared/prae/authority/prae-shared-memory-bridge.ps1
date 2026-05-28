$PraeRoot = "D:\BossMind\bossmind-shared\prae"
$SharedMemoryRoot = "D:\BossMind\bossmind-shared\shared-memory"
$BridgeRoot = "$PraeRoot\shared-memory-bridge"

New-Item -ItemType Directory -Path $SharedMemoryRoot -Force | Out-Null
New-Item -ItemType Directory -Path $BridgeRoot -Force | Out-Null

$DashboardPath = "$PraeRoot\runtime-ledger\prae-governance-dashboard.json"
$LedgerPath = "$PraeRoot\runtime-ledger\prae-events.log"

$BridgeReport = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_SHARED_MEMORY_BRIDGE_SYNC"
    authority = "PRAE"
    governance_mode = "LOCKED"
    deployment_mode = "STAGED"
    production_mutation = "NONE"
    auto_repair = "DISABLED"
    dashboard_exists = Test-Path $DashboardPath
    ledger_exists = Test-Path $LedgerPath
    sync_targets = @{
        dashboard_copy = "$SharedMemoryRoot\prae-governance-dashboard.json"
        ledger_copy = "$SharedMemoryRoot\prae-events.log"
        bridge_report = "$BridgeRoot\prae-shared-memory-bridge-report.json"
    }
}

if (Test-Path $DashboardPath) {
    Copy-Item $DashboardPath "$SharedMemoryRoot\prae-governance-dashboard.json" -Force
}

if (Test-Path $LedgerPath) {
    Copy-Item $LedgerPath "$SharedMemoryRoot\prae-events.log" -Force
}

$BridgeJson = $BridgeReport | ConvertTo-Json -Depth 30

Set-Content -Path "$BridgeRoot\prae-shared-memory-bridge-report.json" -Value $BridgeJson -Encoding UTF8
Add-Content -Path $LedgerPath -Value $BridgeJson

Write-Host ""
Write-Host "====================================="
Write-Host " PRAE SHARED MEMORY BRIDGE SYNCED"
Write-Host "====================================="
Write-Host ""

$BridgeJson
