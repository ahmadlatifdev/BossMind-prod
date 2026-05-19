param(
  [string]$Project = "resumora"
)

$LogPath = "D:\BossMind\bossmind-shared\optimization\performance-log.json"

$start = Get-Date
$response = Invoke-WebRequest "https://bossmind-resumora-web.onrender.com" -UseBasicParsing
$latency = ((Get-Date) - $start).TotalMilliseconds

$data = @{
  timestamp = (Get-Date).ToString("s")
  project = $Project
  metric_type = "api_latency"
  value = [math]::Round($latency,2)
  threshold = 1500
  status = if ($latency -lt 1500) { "OK" } else { "DEGRADED" }
}

$data | ConvertTo-Json -Depth 3 | Add-Content $LogPath

$data | ConvertTo-Json -Depth 3
