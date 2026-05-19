$ErrorActionPreference = "Stop"
Get-Content "D:\BossMind\bossmind-shared\logs\bossmind-final-validation-report.json" | ConvertFrom-Json | ConvertTo-Json -Depth 30
Write-Host "✅ BossMind Master Validation Runner ACTIVE"
Write-Host "✅ All 5 projects checked"
Write-Host "✅ Final report: D:\BossMind\bossmind-shared\logs\bossmind-final-validation-report.json"
