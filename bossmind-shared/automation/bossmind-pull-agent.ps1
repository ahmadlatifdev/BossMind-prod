$ErrorActionPreference = "Stop"

$API = "https://bossmind-executor.up.railway.app/task"   # will be used later
$KEY = "BOSSMIND_SECURE_KEY_2026"

Write-Host "✅ BossMind PULL AGENT ACTIVE"

while ($true) {

    try {
        $task = Invoke-RestMethod $API -Method GET

        if ($task -and $task.action) {

            $action = $task.action

            switch ($action) {
                "health" {
                    $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-unified-health-monitor.ps1"
                }
                "validation" {
                    $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-auto-validation-loop.ps1"
                }
                "risk" {
                    $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-predictive-risk-engine.ps1"
                }
                "performance" {
                    $out = powershell -ExecutionPolicy Bypass -File "D:\BossMind\bossmind-shared\automation\bossmind-performance-profiler.ps1"
                }
                default {
                    $out = "Unknown action"
                }
            }

            $result = @{
                key = $KEY
                action = $action
                result = $out
            }

            Invoke-RestMethod "$API/result" -Method POST -Body ($result | ConvertTo-Json -Depth 10) -ContentType "application/json"

            $log = @{
                timestamp = (Get-Date).ToString("s")
                action = $action
                status = "EXECUTED"
            }

            $log | ConvertTo-Json | Set-Content $logFile -Encoding UTF8
        }
    }
    catch {}

    Start-Sleep -Seconds 5
}
