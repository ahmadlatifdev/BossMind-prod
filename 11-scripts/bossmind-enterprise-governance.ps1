# Enterprise governance orchestration authority — event-driven closed loop
param(
  [string]$ProjectPath = "D:\BossMind\bossmind-resumora",
  [switch]$ClosedLoop,
  [switch]$SkipBuild,
  [switch]$SelfHeal
)

$ErrorActionPreference = "Continue"
$HubRoot = "D:\BossMind"
$LogRoot = "$HubRoot\bossmind-shared\logs"
$MemoryRoot = "$HubRoot\13-shared-memory"
$stamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH-mm-ss")
$logFile = Join-Path $LogRoot "enterprise-governance-$stamp.log"

function Log($m) {
  $line = "[$(Get-Date -Format o)] $m"
  Add-Content -Path $logFile -Value $line -ErrorAction SilentlyContinue
  Write-Host $line
}

New-Item -ItemType Directory -Force -Path $LogRoot, $MemoryRoot | Out-Null
Log "=== Enterprise governance orchestration ==="

Push-Location $ProjectPath
try {
  $npmArgs = @("run", "bossmind:governance:cycle")
  if ($ClosedLoop -or $SkipBuild -or $SelfHeal) { $npmArgs += "--" }
  if ($ClosedLoop) { $npmArgs += "--closed-loop" }
  if ($SkipBuild) { $npmArgs += "--skip-build" }
  if ($SelfHeal) { $npmArgs += "--self-heal" }

  Log "Phase: governance cycle"
  npm @npmArgs 2>&1 | Tee-Object -FilePath $logFile -Append
  $code = $LASTEXITCODE

  Log "Phase: deploy verify live"
  & "$PSScriptRoot\bossmind-deploy-verify-live.ps1" -ProjectPath $ProjectPath 2>&1 | Out-File -Append $logFile

  Log "Phase: render deploy validate"
  npm run bossmind:render:deploy-validate 2>&1 | Out-File -Append $logFile
} finally {
  Pop-Location
}

@{
  schema = "bossmind-enterprise-governance-ps1-v1"
  exitCode = $code
  logFile = $logFile
  completedAt = (Get-Date).ToUniversalTime().ToString("o")
} | ConvertTo-Json | Set-Content (Join-Path $MemoryRoot "resumora-enterprise-governance-ps1-$stamp.json") -Encoding UTF8

exit $code
