Write-Output "SELF_HEALING_START"

$taskEngine = "D:\BossMind\bossmind-shared\automation\task-engine.ps1"

if (!(Test-Path $taskEngine)) {
  Write-Output "SELF_HEALING_FAILED"
  Write-Output "MISSING:task-engine.ps1"
  exit 1
}

& $taskEngine
$firstRun = $LASTEXITCODE

if ($firstRun -eq 0) {
  Write-Output "SELF_HEALING_CLEAN"
  exit 0
}

Write-Output "SELF_HEALING_RETRY_START"

& "D:\BossMind\bossmind-shared\automation\anti-leak-fast.ps1"
$antiLeak = $LASTEXITCODE

if ($antiLeak -ne 0) {
  Write-Output "SELF_HEALING_BLOCKED_BY_ANTI_LEAK"
  exit 1
}

& $taskEngine
$secondRun = $LASTEXITCODE

if ($secondRun -eq 0) {
  Write-Output "SELF_HEALING_RECOVERED"
  exit 0
}

Write-Output "SELF_HEALING_FAILED"
exit 1
