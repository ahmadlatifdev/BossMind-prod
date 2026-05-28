$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$LogEvent = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_PERSISTENT_RUNNER_EXECUTION"
    governance_mode = "LOCKED"
    deployment_mode = "STAGED"
    production_mutation = "BLOCKED"
    auto_repair = "DISABLED"
    authority = "PRAE_ONLY"
    result = "RUNNING"
} | ConvertTo-Json -Depth 20

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $LogEvent

Write-Host ""
Write-Host "====================================="
Write-Host " PRAE PERSISTENT GOVERNANCE ACTIVE"
Write-Host "====================================="
Write-Host ""
Write-Host "Governance Mode  : LOCKED"
Write-Host "Deployment Mode : STAGED"
Write-Host "Production Edit : BLOCKED"
Write-Host "Auto Repair     : DISABLED"
Write-Host "Authority       : PRAE_ONLY"
Write-Host ""
