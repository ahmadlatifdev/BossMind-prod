param([string]$Mode="RUN")

Write-Host "BossMind Auto-Trigger Engine (Background Mode) Started..." -ForegroundColor Cyan

while ($true) {

    $logPath = "D:\BossMind\bossmind-shared\logs\master-runner-log.json"

    if (Test-Path $logPath) {

        $log = Get-Content $logPath -Raw

        if ($log -match "FAILED" -or $log -match "invalid JSON") {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File D:\BossMind\bossmind-shared\automation\bossmind-master-runner.ps1 -Mode FIX_MEMORY_SAVE"
        }

        if ($log -match "404" -or $log -match "Unable to connect") {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File D:\BossMind\bossmind-shared\automation\bossmind-master-runner.ps1 -Mode FORCE_REBUILD_DEPLOY_VERIFY"
        }

        if ($log -match "up-to-date") {
            Start-Process powershell -ArgumentList "-ExecutionPolicy Bypass -File D:\BossMind\bossmind-shared\automation\bossmind-master-runner.ps1 -Mode FORCE_REBUILD_DEPLOY_VERIFY"
        }

    }

    Start-Sleep -Seconds 15
}

