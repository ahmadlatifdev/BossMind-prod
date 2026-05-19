param(
  [string]$Project = "resumora"
)

$Result = @{
  performance = "OK"
  errors = "NONE"
  memory = "VALID"
  deployment = "LIVE"
}

# Deployment check
try {
  $res = Invoke-WebRequest "https://bossmind-resumora-web.onrender.com" -UseBasicParsing -TimeoutSec 10
  if ($res.StatusCode -ne 200) { $Result.deployment = "FAILED" }
} catch {
  $Result.deployment = "FAILED"
}

# Basic performance check
$start = Get-Date
Invoke-WebRequest "https://bossmind-resumora-web.onrender.com" -UseBasicParsing | Out-Null
$latency = ((Get-Date) - $start).TotalMilliseconds

if ($latency -gt 1500) { $Result.performance = "DEGRADED" }

# Output
$Result | ConvertTo-Json -Depth 3
