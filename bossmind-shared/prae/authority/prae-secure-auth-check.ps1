$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$PossibleEnvFiles = @(
  "D:\BossMind\bossmind-resumora\.env.local",
  "D:\BossMind\bossmind-resumora\.env",
  "D:\BossMind\.env.master.local"
)

$Found = @()

foreach ($File in $PossibleEnvFiles) {
  if (Test-Path $File) {
    $HasSecret = Select-String -Path $File -Pattern "^BOSSMIND_ORCHESTRATION_SECRET=" -Quiet
    $Found += [PSCustomObject]@{
      file = $File
      exists = $true
      has_orchestration_secret = $HasSecret
    }
  } else {
    $Found += [PSCustomObject]@{
      file = $File
      exists = $false
      has_orchestration_secret = $false
    }
  }
}

$Event = @{
  timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  event = "PRAE_SECURE_AUTH_SECRET_DISCOVERY"
  result = if (($Found.has_orchestration_secret -contains $true)) { "SECRET_REFERENCE_FOUND" } else { "SECRET_REFERENCE_NOT_FOUND" }
  checked_files = $Found
  secret_value_exposed = $false
  production_mutation = "NONE"
} | ConvertTo-Json -Depth 20

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
