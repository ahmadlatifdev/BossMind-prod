$ErrorActionPreference = "Stop"

$root = "D:\BossMind"
$masterEnv = "D:\BossMind\bossmind-shared\.env.master"

if (!(Test-Path $masterEnv)) {
  throw "Missing master env: $masterEnv"
}

$master = Get-Content $masterEnv -Raw

$targets = @(
  "D:\BossMind\bossmind-resumora\.env",
  "D:\BossMind\bossmind-elegancyart\.env",
  "D:\BossMind\bossmind-ai-video-generator\.env",
  "D:\BossMind\bossmind-tiktok-ai\.env",
  "D:\BossMind\bossmind-global-stock\.env",
  "D:\BossMind\bossmind-shared\.env",
  "D:\BossMind\bossmind-shared\automation\.env"
)

foreach ($target in $targets) {
  New-Item -ItemType Directory -Force -Path (Split-Path $target) | Out-Null
  Set-Content -Path $target -Value $master -Encoding UTF8
  Write-Host "SYNCED ENV: $target" -ForegroundColor Green
}

Write-Host "ENV MASTER SYNC COMPLETE" -ForegroundColor Green
