param(
  [string]$Project = "resumora"
)

$ValidatorPath = "D:\BossMind\bossmind-shared\optimization\validator-engine.ps1"
$RetryEngine = "D:\BossMind\bossmind-shared\optimization\retry-engine.ps1"
$DecisionLog = "D:\BossMind\bossmind-shared\optimization\decision-log.json"

$ValidationRaw = powershell -ExecutionPolicy Bypass -File $ValidatorPath
$Validation = $ValidationRaw | ConvertFrom-Json

$Decision = @{
  timestamp = (Get-Date).ToString("s")
  project = $Project
  validation = $Validation
  action = "NONE"
  reason = "System healthy"
}

$Degraded =
  $Validation.performance -ne "OK" -or
  $Validation.errors -ne "NONE" -or
  $Validation.memory -ne "VALID" -or
  $Validation.deployment -ne "LIVE"

if ($Degraded) {
  $Decision.action = "AUTO_HEAL_WITH_RETRY"
  $Decision.reason = "Degradation detected; retry engine triggered"

  powershell -ExecutionPolicy Bypass -File $RetryEngine -Project $Project
}

$Decision | ConvertTo-Json -Depth 6 | Set-Content $DecisionLog -Encoding UTF8
$Decision | ConvertTo-Json -Depth 6
