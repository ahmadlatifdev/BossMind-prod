$PraeRoot = "D:\BossMind\bossmind-shared\prae"
$MasterEnvPath = "D:\BossMind\.env.master.local"

$EnvMap = @{}

if (Test-Path $MasterEnvPath) {
  Get-Content $MasterEnvPath | ForEach-Object {
    if ($_ -match "^\s*([^#][^=]+)=(.*)$") {
      $EnvMap[$matches[1].Trim()] = $matches[2].Trim()
    }
  }
}

$RequiredGovernance = @{
  PRAE_GOVERNANCE_MODE = "LOCKED"
  PRAE_DEPLOYMENT_MODE = "STAGED"
  PRAE_UI_LOCK = "ENABLED"
  PRAE_RESTORE_SEAL = "DISABLED"
  PRAE_AUTONOMOUS_MUTATION = "RESTRICTED"
  PRAE_PRODUCTION_MUTATION = "BLOCKED"
  PRAE_AUTO_REPAIR = "DISABLED"
  PRAE_AUTHORITY = "PRAE_ONLY"
}

$Checks = @()

foreach ($Key in $RequiredGovernance.Keys) {
  $Actual = $EnvMap[$Key]
  $Expected = $RequiredGovernance[$Key]

  $Checks += [PSCustomObject]@{
    key = $Key
    expected = $Expected
    actual = $Actual
    passed = ($Actual -eq $Expected)
  }
}

$Event = @{
  timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  event = "PRAE_GOVERNANCE_LOADER_VALIDATION"
  result = if (($Checks.passed -contains $false)) { "FAILED" } else { "SUCCESS" }
  master_env_exists = Test-Path $MasterEnvPath
  secret_values_exposed = $false
  production_mutation = "NONE"
  governance_checks = $Checks
} | ConvertTo-Json -Depth 30

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
