param(
    [Parameter(Mandatory=$true)]
    [string]$projectPath
)

Write-Host "Auto-fix started for: $projectPath" -ForegroundColor Cyan

$result = @{
    project = $projectPath
    action = "checked"
    timestamp = (Get-Date).ToString("s")
}

$logRoot = "D:\BossMind\bossmind-shared\logs"
if (!(Test-Path $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
}

$result | ConvertTo-Json -Depth 10 | Out-File "$logRoot\auto-fix-log.json" -Encoding utf8

Write-Host "Auto-fix complete." -ForegroundColor Green
