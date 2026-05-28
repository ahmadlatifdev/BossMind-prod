$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$Targets = @(
  @{
    name = "resumora-production-health"
    url = "https://www.resumora.net/api/health"
  },
  @{
    name = "resumora-orchestration-health"
    url = "https://www.resumora.net/api/orchestration/bossmind-health"
  }
)

$Results = @()

foreach ($Target in $Targets) {
  try {
    $Response = Invoke-WebRequest -Uri $Target.url -Method GET -TimeoutSec 20
    $Results += [PSCustomObject]@{
      name = $Target.name
      url = $Target.url
      status_code = $Response.StatusCode
      success = ($Response.StatusCode -ge 200 -and $Response.StatusCode -lt 300)
    }
  } catch {
    $Results += [PSCustomObject]@{
      name = $Target.name
      url = $Target.url
      status_code = $null
      success = $false
      error = $_.Exception.Message
    }
  }
}

$Event = @{
  timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
  event = "PRAE_RUNTIME_HEALTH_VALIDATION"
  authority = "PRAE"
  result = if (($Results.success -contains $false)) { "FAILED_OR_PARTIAL" } else { "SUCCESS" }
  targets = $Results
  production_mutation = "NONE"
  ui_mutation = "NONE"
  restore_seal = "DISABLED"
} | ConvertTo-Json -Depth 20

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
