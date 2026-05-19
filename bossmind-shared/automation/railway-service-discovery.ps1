Write-Host "Fetching Railway services via CLI..." -ForegroundColor Cyan

railway whoami

railway status > "D:\BossMind\bossmind-shared\logs\railway-services.txt"

Write-Host "---- OUTPUT ----" -ForegroundColor Yellow
Get-Content "D:\BossMind\bossmind-shared\logs\railway-services.txt"
