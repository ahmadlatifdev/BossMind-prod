# BossMind — non-destructive env template check (no secret values printed)
param(
  [string]$ResumoraRoot = "D:\BossMind\bossmind-resumora"
)

$ErrorActionPreference = "Stop"
$example = Join-Path $ResumoraRoot ".env.example"
if (-not (Test-Path $example)) {
  Write-Host "verify-env: no .env.example at $ResumoraRoot" -ForegroundColor Yellow
  exit 0
}

$requiredHints = @(
  "NEON_DATABASE_URL",
  "STRIPE",
  "BOSSMIND_ORCHESTRATION_SECRET"
)

$lines = Get-Content -LiteralPath $example
$keys = $lines | ForEach-Object {
  if ($_ -match "^\s*#") { return }
  if ($_ -match "^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=") { $Matches[1] }
} | Where-Object { $_ }

Write-Host "BossMind verify-env - .env.example keys: $($keys.Count)" -ForegroundColor Cyan
$warn = $false
foreach ($hint in $requiredHints) {
  $found = $keys | Where-Object { $_ -like "*$hint*" }
  if (-not $found) {
    Write-Host "  WARN: no key matching *$hint* in .env.example" -ForegroundColor Yellow
    $warn = $true
  }
}

if (Test-Path (Join-Path $ResumoraRoot ".env")) {
  Write-Host "  .env present (values not read)" -ForegroundColor Green
} else {
  Write-Host "  .env missing - use .env.example for local dev" -ForegroundColor Yellow
}

exit $(if ($warn) { 0 } else { 0 })
