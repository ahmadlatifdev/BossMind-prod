param(
  [string]$LogFile = "D:\BossMind\bossmind-shared\automation\sentry-history.json"
)

Write-Output "SENTRY_HISTORY_START"

$entry = [pscustomobject]@{
  timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  system = "BossMind"
  target = "sentry_update_history"
  status = "recorded"
  source = "local_automation"
}

if (Test-Path $LogFile) {
  $history = Get-Content $LogFile | ConvertFrom-Json
  if ($history -isnot [System.Array]) {
    $history = @($history)
  }
} else {
  $history = @()
}

$history += $entry

$history | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $LogFile

Write-Output "SENTRY_HISTORY_RECORDED"
exit 0
