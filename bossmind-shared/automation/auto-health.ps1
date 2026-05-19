Write-Output "AUTO_HEALTH_START"

$antiLeak = "D:\BossMind\bossmind-shared\automation\anti-leak-fast.ps1"

if (!(Test-Path $antiLeak)) {
  Write-Output "AUTO_HEALTH_FAILED"
  Write-Output "MISSING:anti-leak-fast.ps1"
  exit 1
}

Write-Output "CHECK:ANTI_LEAK"
& $antiLeak

if ($LASTEXITCODE -ne 0) {
  Write-Output "AUTO_HEALTH_FAILED"
  exit 1
}

Write-Output "AUTO_HEALTH_CLEAN"
exit 0
