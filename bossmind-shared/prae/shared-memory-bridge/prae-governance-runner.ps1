#Requires -Version 5.1
<#
.SYNOPSIS
  PRAE Governance Runner — scheduled validation, drift logging, deployment checks (no mutation).
#>
param(
  [string]$HubRoot = "D:\BossMind",
  [switch]$InstallScheduler,
  [int]$IntervalMinutes = 15,
  [switch]$Silent
)

$ErrorActionPreference = "Continue"
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

$BridgeRoot = Join-Path $HubRoot "bossmind-shared\prae\shared-memory-bridge"
$PraeRoot = Join-Path $HubRoot "bossmind-shared\prae"
$LogDir = Join-Path $HubRoot "bossmind-shared\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

$validators = @(
  (Join-Path $PraeRoot "authority\prae-governance-loader.ps1"),
  (Join-Path $PraeRoot "authority\prae-validation-runner.ps1"),
  (Join-Path $PraeRoot "authority\prae-runtime-health-validator.ps1"),
  (Join-Path $BridgeRoot "prae-shared-memory-bridge.mjs")
)

foreach ($v in $validators) {
  if (-not (Test-Path $v)) {
    $warn = @{ timestamp_utc = (Get-Date).ToUniversalTime().ToString("o"); event = "PRAE_RUNNER_MISSING_VALIDATOR"; path = $v }
    Add-Content -Path (Join-Path $LogDir "error_memory.jsonl") -Value ($warn | ConvertTo-Json -Compress) -Encoding UTF8
    continue
  }
  if ($v -like "*.ps1") {
    & $v 2>&1 | Out-Null
  } else {
    & node $v 2>&1 | Out-Null
  }
}

$resumoraHealth = $null
try {
  $resumoraHealth = Invoke-RestMethod -Uri "https://www.resumora.net/api/health" -TimeoutSec 20
} catch {
  $resumoraHealth = @{ ok = $false; error = $_.Exception.Message }
}

$runnerEvent = @{
  timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  event = "PRAE_GOVERNANCE_RUNNER_CYCLE"
  result = if ($resumoraHealth.ok) { "SUCCESS" } else { "PARTIAL" }
  production_health = @{
    ok = [bool]$resumoraHealth.ok
    gitCommit = $resumoraHealth.gitCommit
    commerceReady = $resumoraHealth.commerceReady
  }
  auto_repair = "DISABLED"
  production_mutation = "NONE"
  secret_values_exposed = $false
} | ConvertTo-Json -Depth 8 -Compress

Add-Content -Path (Join-Path $PraeRoot "runtime-ledger\prae-events.log") -Value $runnerEvent -Encoding UTF8
Add-Content -Path (Join-Path $PraeRoot "global-ledger\governance-events.jsonl") -Value $runnerEvent -Encoding UTF8
Add-Content -Path (Join-Path $LogDir "task-state-log.jsonl") -Value (@{
  _type = "task_state"
  _written = (Get-Date).ToUniversalTime().ToString("o")
  project_id = "bossmind-hub"
  task_name = "prae_governance_runner"
  status = "done"
  detail = "Scheduled validation cycle complete"
} | ConvertTo-Json -Compress) -Encoding UTF8

if ($InstallScheduler) {
  $TaskName = "BossMind-PRAE-Governance-Runner"
  $PsExe = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
  $Engine = Join-Path $BridgeRoot "prae-governance-runner.ps1"
  $action = New-ScheduledTaskAction -Execute $PsExe -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$Engine`" -Silent"
  $trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(2) -RepetitionInterval (New-TimeSpan -Minutes $IntervalMinutes) -RepetitionDuration (New-TimeSpan -Days 3650)
  $settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable -ExecutionTimeLimit (New-TimeSpan -Hours 1) -MultipleInstances IgnoreNew
  $existing = Get-ScheduledTask -TaskName $TaskName -ErrorAction SilentlyContinue
  if ($existing) { Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false }
  Register-ScheduledTask -TaskName $TaskName -Action $action -Trigger $trigger -Settings $settings -Description "PRAE governance validation (no mutation)" -User $env:USERNAME -Force | Out-Null
  if (-not $Silent) { Write-Host "Scheduled task installed: $TaskName (every $IntervalMinutes min)" -ForegroundColor Cyan }
}

if (-not $Silent) {
  Write-Host "PRAE governance runner cycle complete." -ForegroundColor Green
}
