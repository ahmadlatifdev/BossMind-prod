# Enterprise BossMind + Resumora stabilization — autonomous PowerShell orchestration
param(
  [string]$ProjectPath = "D:\BossMind\bossmind-resumora",
  [switch]$SkipBuild,
  [switch]$SkipPush
)

$ErrorActionPreference = "Continue"
$HubRoot = "D:\BossMind"
$LogRoot = "$HubRoot\bossmind-shared\logs"
$MemoryRoot = "$HubRoot\13-shared-memory"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm-ss")
$logFile = Join-Path $LogRoot "enterprise-stabilization-$stamp.log"

function Log($msg) {
  $line = "[$(Get-Date -Format o)] $msg"
  Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
  Write-Host $line
}

New-Item -ItemType Directory -Force -Path $LogRoot, $MemoryRoot | Out-Null
Log "=== Enterprise stabilization cycle ==="

Push-Location $ProjectPath
try {
  Log "Phase: render env checklist"
  npm run bossmind:render:env-checklist 2>&1 | Out-File -Append $logFile

  $buildFlag = if ($SkipBuild) { "--skip-build" } else { "" }
  Log "Phase: enterprise stabilization (Node)"
  npm run bossmind:enterprise:stabilization -- $buildFlag 2>&1 | Tee-Object -FilePath $logFile -Append
  $exitCode = $LASTEXITCODE

  if (-not $SkipPush -and $exitCode -eq 0) {
    Log "Phase: git push (if dirty)"
    $status = git status --porcelain 2>&1
    if ($status) {
      git add -A 2>&1 | Out-File -Append $logFile
      git commit -m "Enterprise stabilization cycle $stamp" 2>&1 | Out-File -Append $logFile
      git push origin main 2>&1 | Out-File -Append $logFile
    }
  }

  Log "Phase: live deploy verify"
  & "$PSScriptRoot\bossmind-deploy-verify-live.ps1" -ProjectPath $ProjectPath 2>&1 | Out-File -Append $logFile

  Log "Phase: client journey repair"
  npm run bossmind:client-journey:autonomous-repair -- --skip-push 2>&1 | Out-File -Append $logFile
} finally {
  Pop-Location
}

$summary = @{
  schema      = "bossmind-enterprise-stabilization-ps1-v1"
  completedAt = (Get-Date).ToUniversalTime().ToString("o")
  exitCode    = $exitCode
  logFile     = $logFile
}
$summary | ConvertTo-Json -Depth 4 | Set-Content (Join-Path $MemoryRoot "resumora-enterprise-stabilization-$stamp.json") -Encoding UTF8
exit $exitCode
