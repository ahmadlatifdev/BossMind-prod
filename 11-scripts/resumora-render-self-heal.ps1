# Resumora Render self-heal — env sync, optional redeploy, live verify (active repo only)
param(
  [string]$HubRoot = $(if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" }),
  [string]$LiveOrigin = "https://www.resumora.net",
  [switch]$ApplyEnv,
  [switch]$Redeploy,
  [switch]$Lock
)

$ErrorActionPreference = "Stop"
$Resumora = Join-Path $HubRoot "bossmind-resumora"
if (-not (Test-Path $Resumora)) {
  Write-Error "Resumora root not found: $Resumora"
}

function Test-LiveHealth {
  param([string]$Origin)
  try {
    $h = Invoke-RestMethod -Uri "$Origin/api/health" -TimeoutSec 45
    return @{
      ok = [bool]$h.ok
      databaseOk = [bool]$h.database.ok
      checkoutReady = [bool]$h.stripe.checkoutReady
      uptime = $h.uptime
    }
  } catch {
    return @{ ok = $false; databaseOk = $false; error = $_.Exception.Message }
  }
}

Write-Host "[render-self-heal] Hub env bootstrap..." -ForegroundColor Cyan
Push-Location $Resumora
try {
  npm run bossmind:hub-env-bootstrap | Out-Host
  if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

  Write-Host "[render-self-heal] Render env checklist..." -ForegroundColor Cyan
  npm run bossmind:render:env-checklist | Out-Host

  if ($ApplyEnv) {
    Write-Host "[render-self-heal] Applying env to Render (requires RENDER_API_KEY)..." -ForegroundColor Cyan
    npm run bossmind:render:env-sync -- --apply | Out-Host
    if ($LASTEXITCODE -ne 0) {
      Write-Host "  env-sync failed — set RENDER_API_KEY + RENDER_SERVICE_ID or paste from .bossmind/render-production-env.env" -ForegroundColor Yellow
    }
  }

  $before = Test-LiveHealth -Origin $LiveOrigin.TrimEnd("/")
  Write-Host "[render-self-heal] Live health: ok=$($before.ok) db=$($before.databaseOk)" -ForegroundColor $(if ($before.databaseOk) { "Green" } else { "Yellow" })

  $needsRedeploy = $Redeploy -or (-not $before.databaseOk)
  if ($needsRedeploy) {
    Write-Host "[render-self-heal] Triggering redeploy..." -ForegroundColor Cyan
    npm run bossmind:ultra:stabilize:redeploy | Out-Host
    Start-Sleep -Seconds 50
  }

  $ultraArgs = @()
  if ($Lock) { $ultraArgs += "--lock", "--i-understand-production" }
  Write-Host "[render-self-heal] Ultra-stabilization verify..." -ForegroundColor Cyan
  npm run bossmind:ultra:stabilize @ultraArgs | Out-Host
  exit $LASTEXITCODE
} finally {
  Pop-Location
}
