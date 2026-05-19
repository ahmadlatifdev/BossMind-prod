param(
    [string]$Project = "resumora"
)

$RepoPath = "D:\BossMind\bossmind-$Project"

Write-Host "🚀 FORCE DEPLOY TRIGGER STARTED"

# Step 1 — create unique change
$stamp = Get-Date -Format "yyyyMMddHHmmss"
$file = "$RepoPath\deploy-trigger.txt"
"deploy-$stamp" | Out-File -FilePath $file -Encoding utf8

# Step 2 — push change
cd $RepoPath
git add -A
git commit -m "AUTO DEPLOY TRIGGER $stamp"
git push

# Step 3 — wait for Railway
Write-Host "⏳ Waiting for deployment..."
Start-Sleep -Seconds 90

# Step 4 — verify live
$url = "https://resumora.net/client?cachebust=$stamp"

try {
    $res = Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 30
    if ($res.StatusCode -eq 200) {
        Write-Host "✅ LIVE DEPLOY SUCCESS"
    } else {
        Write-Host "⚠️ Unexpected response"
    }
}
catch {
    Write-Host "❌ DEPLOY FAILED OR NOT LIVE YET"
}