# Autonomous Resumora client-journey repair — PowerShell diagnostics + Node closed loop
$ErrorActionPreference = "Continue"
$ProjectPath = "D:\BossMind\bossmind-resumora"
$LogRoot = "D:\BossMind\bossmind-shared\logs"
$MemoryRoot = "D:\BossMind\13-shared-memory"

if (!(Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }
if (!(Test-Path $MemoryRoot)) { New-Item -ItemType Directory -Path $MemoryRoot -Force | Out-Null }

$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm-ss")
$diagLog = Join-Path $LogRoot "client-journey-autonomous-diag-$stamp.log"

function Write-Diag($msg) {
  $line = "[$(Get-Date -Format o)] $msg"
  Add-Content -Path $diagLog -Value $line
  Write-Host $line
}

Write-Diag "=== BossMind client-journey autonomous repair ==="

Push-Location $ProjectPath
try {
  Write-Diag "Phase: git status"
  git status --short 2>&1 | Out-File -Append $diagLog

  Write-Diag "Phase: env checklist (keys only)"
  npm run bossmind:render:env-checklist 2>&1 | Out-File -Append $diagLog

  Write-Diag "Phase: autonomous repair script"
  npm run bossmind:client-journey:autonomous-repair 2>&1 | Tee-Object -FilePath $diagLog -Append
  $repairExit = $LASTEXITCODE

  Write-Diag "Phase: live deploy verify"
  & "$PSScriptRoot\bossmind-deploy-verify-live.ps1" -ProjectPath $ProjectPath 2>&1 | Out-File -Append $diagLog
} finally {
  Pop-Location
}

$summary = @{
  schema     = "bossmind-client-journey-autonomous-repair-ps1-v1"
  completedAt = (Get-Date).ToUniversalTime().ToString("o")
  diagLog    = $diagLog
  repairExit = $repairExit
}
$memPath = Join-Path $MemoryRoot "resumora-client-journey-autonomous-repair-$stamp.json"
$summary | ConvertTo-Json -Depth 6 | Set-Content -Path $memPath -Encoding UTF8
Write-Diag "Saved memory: $memPath"
exit $repairExit
