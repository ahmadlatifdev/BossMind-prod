param(
  [string]$Task
)

switch ($Task) {

  "bossmind-resumora" {
    Write-Host "Deploying Resumora..."
    cd D:\BossMind\bossmind-resumora
    git pull
    npm install
    npm run build
  }

  "bossmind-elegancyart" {
    Write-Host "Updating ElegancyArt..."
    cd D:\BossMind\bossmind-elegancyart
    git pull
  }

  "bossmind-ai-video-generator" {
    Write-Host "Running Video Generator..."
    cd D:\BossMind\bossmind-ai-video-generator
    node worker.js
  }

  "bossmind-tiktok-ai" {
    Write-Host "Running TikTok Automation..."
    cd D:\BossMind\bossmind-tiktok-ai
    node tiktok.js
  }

  "bossmind-global-stock" {
    Write-Host "Syncing Stock System..."
    cd D:\BossMind\bossmind-global-stock
    node sync.js
  }

  default {
    Write-Host "No task matched"
  }
}

$time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

$result = @{
  task = $Task
  status = "executed"
  timestamp = $time
}

$result | ConvertTo-Json | Set-Content ".\last-run-result.json" -Encoding UTF8
