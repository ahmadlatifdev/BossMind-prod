param(
    [Parameter(Mandatory=$true)]
    [string]$projectPath
)

Write-Host "Deploy verify started for: $projectPath" -ForegroundColor Cyan

$alive = Test-Path $projectPath

$result = @{
    project = $projectPath
    deploy_status = if ($alive) { "reachable_local" } else { "missing" }
    timestamp = (Get-Date).ToString("s")
}

$logRoot = "D:\BossMind\bossmind-shared\logs"
if (!(Test-Path $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
}

$result | ConvertTo-Json -Depth 10 | Out-File "$logRoot\deploy-verify-log.json" -Encoding utf8

Write-Host "Deploy verify complete." -ForegroundColor Green
