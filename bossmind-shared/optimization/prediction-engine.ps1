param(
  [string]$Project = "resumora"
)

$PerformanceLog = "D:\BossMind\bossmind-shared\optimization\performance-log.json"
$PredictionLog = "D:\BossMind\bossmind-shared\optimization\prediction-log.json"

$Status = @{
  timestamp = (Get-Date).ToString("s")
  project = $Project
  risk = "LOW"
  reason = "No rising performance risk detected"
  recommended_action = "NONE"
}

if (Test-Path $PerformanceLog) {
  $Raw = Get-Content $PerformanceLog -Raw

  $Matches = [regex]::Matches($Raw, '"value"\s*:\s*([0-9.]+)')
  $Values = @()

  foreach ($m in $Matches) {
    $Values += [double]$m.Groups[1].Value
  }

  if ($Values.Count -ge 3) {
    $Last3 = $Values | Select-Object -Last 3

    if ($Last3[0] -lt $Last3[1] -and $Last3[1] -lt $Last3[2]) {
      $Status.risk = "MEDIUM"
      $Status.reason = "Latency rising across last 3 cycles"
      $Status.recommended_action = "PREVENTIVE_VERIFY"
    }

    if ($Last3[-1] -gt 1500) {
      $Status.risk = "HIGH"
      $Status.reason = "Latency exceeded threshold"
      $Status.recommended_action = "AUTO_HEAL"
    }
  }
}

$Status | ConvertTo-Json -Depth 5 | Set-Content $PredictionLog -Encoding UTF8
$Status | ConvertTo-Json -Depth 5
