$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$RequiredFiles = @(
  "$PraeRoot\runtime-ledger\prae-runtime-ledger.json",
  "$PraeRoot\checksums\prae-checksum-registry.json",
  "$PraeRoot\deployment-validation\prae-deployment-authority.json",
  "$PraeRoot\drift-detection\prae-drift-authority.json",
  "$PraeRoot\repair-simulation\prae-repair-authority.json",
  "$PraeRoot\authority\prae-runtime-validation.json"
)

$Results = @()

foreach ($File in $RequiredFiles) {
  $Results += [PSCustomObject]@{
    file = $File
    exists = Test-Path $File
  }
}

$Event = @{
  timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  event = "PRAE_VALIDATION_RUN"
  result = if (($Results.exists -contains $false)) { "FAILED" } else { "SUCCESS" }
  checked_files = $Results
} | ConvertTo-Json -Depth 20

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
