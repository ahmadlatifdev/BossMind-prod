$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$LocalEnvFiles = @(
  "D:\BossMind\bossmind-resumora\.env.local",
  "D:\BossMind\bossmind-resumora\.env",
  "D:\BossMind\.env.master.local"
)

$Needles = @(
  "RENDER_API_KEY",
  "RENDER_SERVICE_ID",
  "BOSSMIND_ORCHESTRATION_SECRET",
  "STRIPE_WEBHOOK_SECRET"
)

$Results = @()

foreach ($File in $LocalEnvFiles) {
  $Entry = [ordered]@{
    file = $File
    exists = Test-Path $File
    keys = @{}
  }

  foreach ($Needle in $Needles) {
    $Entry.keys[$Needle] = $false
  }

  if ($Entry.exists) {
    foreach ($Needle in $Needles) {
      $Entry.keys[$Needle] = Select-String -Path $File -Pattern "^$Needle=" -Quiet
    }
  }

  $Results += [PSCustomObject]$Entry
}

$Event = @{
  timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  event = "PRAE_RENDER_ENV_REFERENCE_CHECK"
  result = "LOCAL_REFERENCE_SCAN_COMPLETE"
  checked_files = $Results
  secret_values_exposed = $false
  render_mutation = "NONE"
  production_mutation = "NONE"
} | ConvertTo-Json -Depth 30

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
