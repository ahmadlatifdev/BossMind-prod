param(
  [string]$Project = "resumora"
)

$Runner = "D:\BossMind\bossmind-shared\automation\bossmind-master-runner.ps1"

$Result = @{
  attempts = 0
  final_status = "FAILED"
}

for ($i = 1; $i -le 3; $i++) {

  Write-Host "Attempt $i..."

  try {
    powershell -ExecutionPolicy Bypass -File $Runner -Project $Project -Action restore-deploy-verify
    $Result.attempts = $i
    $Result.final_status = "SUCCESS"
    break
  } catch {
    if ($i -eq 3) {
      Write-Host "Switching to fallback strategy (final attempt)..."
    }
  }
}

$Result | ConvertTo-Json -Depth 3
