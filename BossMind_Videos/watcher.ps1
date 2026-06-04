# BossMind Orchestrator Watcher v1
$ROOT = "D:\Shakhsy11\Bossmind-orchestrator\BossMind_Videos"
$LIVE = Join-Path $ROOT "_LIVE"
$READY = Join-Path $ROOT "_READY"
$PUBLISH = Join-Path $ROOT "_PUBLISH"

$fire = Join-Path $ROOT "FIRE.flag"

Write-Host "BossMind Watcher started..." -ForegroundColor Cyan

while ($true) {
    if (Test-Path $fire) {

        # If LIVE has video and flags, rotate state
        if (Test-Path $LIVE) {
            $mp4 = Get-ChildItem $LIVE -Filter *.mp4 -ErrorAction SilentlyContinue
            if ($mp4) {
                Write-Host "LIVE video detected: $($mp4.Name)" -ForegroundColor Green

                # Create state flags
                Set-Content (Join-Path $LIVE "status.flag") "LIVE"
                Set-Content (Join-Path $LIVE "run.flag") "RUN"
                Set-Content (Join-Path $LIVE "queue.flag") "QUEUE"
                Set-Content (Join-Path $LIVE "publish.flag") "READY"

                Write-Host "State flags refreshed." -ForegroundColor Yellow
            }
        }

    }

    Start-Sleep -Seconds 3
}
