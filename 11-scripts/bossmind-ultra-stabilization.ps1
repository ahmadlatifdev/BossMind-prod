# BossMind hub ultra-stabilization (active Resumora only — no archives)
$ErrorActionPreference = "Stop"
$HubRoot = if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" }
$Resumora = Join-Path $HubRoot "bossmind-resumora"

Write-Host "[ultra] Hub integrity checks..."
& (Join-Path $HubRoot "11-scripts\verify-imports.ps1")
& (Join-Path $HubRoot "11-scripts\verify-routes.ps1")

Write-Host "[ultra] Resumora orchestrator..."
Push-Location $Resumora
try {
  npm run bossmind:ultra:stabilize
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
} finally {
  Pop-Location
}

Write-Host "[ultra] Done. See 13-shared-memory/resumora-ultra-stabilization-*.json"
