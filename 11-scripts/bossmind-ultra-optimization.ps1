# BossMind ultra-optimization mission (hub + Resumora)
$ErrorActionPreference = "Stop"
$HubRoot = if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" }
$Resumora = Join-Path $HubRoot "bossmind-resumora"

Write-Host "[optimize] Secret scan..." -ForegroundColor Cyan
& (Join-Path $HubRoot "11-scripts\bossmind-secret-scan.ps1")

Push-Location $Resumora
try {
  npm run bossmind:ultra:optimize
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
