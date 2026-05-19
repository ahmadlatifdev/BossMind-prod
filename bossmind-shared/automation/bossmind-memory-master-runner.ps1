# BossMind Memory Master Runner (FULL SYSTEM)

$ErrorActionPreference = "Stop"

$AutomationRoot = "D:\BossMind\bossmind-shared\automation"

$Watcher = "$AutomationRoot\bossmind-memory-watcher.ps1"
$Sync = "$AutomationRoot\bossmind-memory-sync.ps1"
$Retry = "$AutomationRoot\bossmind-memory-retry.ps1"

Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$Sync`""
Start-Sleep -Seconds 2

Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$Watcher`""
Start-Sleep -Seconds 2

Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -NoExit -File `"$Retry`""

Write-Host "BossMind FULL Memory System started:"
Write-Host "1. Neon Sync Engine"
Write-Host "2. Real-Time Watcher"
Write-Host "3. Retry Engine"