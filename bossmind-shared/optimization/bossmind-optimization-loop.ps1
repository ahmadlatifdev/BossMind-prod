# BossMind FULL Elite Autonomous Loop

while ($true) {

    Write-Host "=== BossMind Optimization Cycle ==="

    # Step 1 — Decision Engine (includes retry + auto-heal)
    $decision = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\optimization\decision-engine.ps1" | ConvertFrom-Json

    # Step 2 — Prediction Engine
    powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\optimization\prediction-engine.ps1"

    # Step 3 — Performance Profiler
    powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\optimization\performance-profiler.ps1"

    # Step 4 — Auto Snapshot ONLY if healthy
    if ($decision.action -eq "NONE") {
        Write-Host "System stable → locking snapshot..."
        powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\optimization\auto-snapshot-lock.ps1"
    }

    # Step 5 — Wait
    Start-Sleep -Seconds 300
}
