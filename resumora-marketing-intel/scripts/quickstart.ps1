# Resumora Marketing Intelligence — local quickstart (Windows)
$ErrorActionPreference = "Stop"
$Root = Split-Path -Parent $PSScriptRoot
Set-Location $Root

Write-Host "== Resumora Marketing Intel quickstart ==" -ForegroundColor Cyan
Write-Host "Safety: AD writes DISABLED"

if (-not (Test-Path .venv)) {
  py -3.11 -m venv .venv
  if ($LASTEXITCODE -ne 0) { python -m venv .venv }
}
& .\.venv\Scripts\Activate.ps1
python -m pip install -U pip
pip install -r requirements.txt
pip install -e .

if (-not (Test-Path .env)) {
  Copy-Item .env.example .env
  Write-Host "Created .env from .env.example"
}

New-Item -ItemType Directory -Force -Path artifacts\models, artifacts\reports, secrets | Out-Null
python -m marketing_intel.jobs.train_models
python -m marketing_intel.jobs.watch_competitor_prices

Write-Host ""
Write-Host "Start dashboard:" -ForegroundColor Green
Write-Host "  streamlit run dashboard/dashboard_app.py"
