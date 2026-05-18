# BossMind — verify Resumora protected routes/shell files still exist
param(
  [string]$ResumoraRoot = "D:\BossMind\bossmind-resumora"
)

$ErrorActionPreference = "Stop"
$surfacePath = Join-Path $ResumoraRoot "config\bossmind-protected-surface.json"
if (-not (Test-Path $surfacePath)) {
  Write-Host "verify-routes: missing $surfacePath" -ForegroundColor Red
  exit 1
}

$config = Get-Content -LiteralPath $surfacePath -Raw | ConvertFrom-Json
$paths = @()
if ($config.shellLockPaths) { $paths += $config.shellLockPaths }
if ($config.surfaceLockPaths) { $paths += $config.surfaceLockPaths }

$missing = @()
foreach ($rel in $paths) {
  $full = Join-Path $ResumoraRoot ($rel -replace "/", "\")
  if (-not (Test-Path -LiteralPath $full)) { $missing += $rel }
}

Write-Host "BossMind verify-routes - $($paths.Count) locked paths" -ForegroundColor Cyan
if ($missing.Count -gt 0) {
  foreach ($m in $missing) { Write-Host "  MISSING: $m" -ForegroundColor Red }
  exit 1
}
Write-Host "verify-routes: OK" -ForegroundColor Green
exit 0
