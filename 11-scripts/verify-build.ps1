# BossMind — run production build in canonical Resumora repo
param(
  [string]$ResumoraRoot = "D:\BossMind\bossmind-resumora",
  [switch]$SkipInstall
)

$ErrorActionPreference = "Stop"
if (-not (Test-Path $ResumoraRoot)) {
  Write-Host "verify-build: repo not found at $ResumoraRoot" -ForegroundColor Red
  exit 1
}

Write-Host "BossMind verify-build - $ResumoraRoot" -ForegroundColor Cyan
Push-Location $ResumoraRoot
try {
  & "$PSScriptRoot\verify-imports.ps1" -Root (Split-Path $ResumoraRoot -Parent)
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  if (-not $SkipInstall -and -not (Test-Path "node_modules\next\package.json")) {
    Write-Host "  npm ci ..." -ForegroundColor Yellow
    npm ci
    if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
  }

  Write-Host "  npm run build ..." -ForegroundColor Yellow
  npm run build
  exit $LASTEXITCODE
}
finally {
  Pop-Location
}
