# BossMind one-click recovery — imports, routes, build (Resumora hub)
param(
  [string]$ResumoraRoot = "D:\BossMind\bossmind-resumora",
  [switch]$Push,
  [string]$CommitMessage = "BossMind recovery: import/build verify"
)

$ErrorActionPreference = "Stop"
$scripts = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "=== BossMind Recovery ===" -ForegroundColor Cyan
& "$scripts\verify-imports.ps1"
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$scripts\verify-routes.ps1" -ResumoraRoot $ResumoraRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& "$scripts\verify-env.ps1" -ResumoraRoot $ResumoraRoot
& "$scripts\verify-build.ps1" -ResumoraRoot $ResumoraRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

Push-Location $ResumoraRoot
try {
  git status -sb
  if ($Push) {
    $dirty = git status --porcelain
    if ($dirty) {
      git add -A
      git commit -m $CommitMessage
      git push
    } else {
      Write-Host "Working tree clean — nothing to commit." -ForegroundColor Yellow
    }
  }
}
finally {
  Pop-Location
}

Write-Host "=== Recovery complete ===" -ForegroundColor Green
