param(
    [Parameter(Mandatory=$true)]
    [string]$projectPath
)

Write-Host "Preflight scan started for: $projectPath" -ForegroundColor Cyan

$result = @{
    project = $projectPath
    exists = Test-Path $projectPath
    packageJson = Test-Path "$projectPath\package.json"
    appFolder = Test-Path "$projectPath\app"
    srcFolder = Test-Path "$projectPath\src"
    timestamp = (Get-Date).ToString("s")
}

$logRoot = "D:\BossMind\bossmind-shared\logs"
if (!(Test-Path $logRoot)) {
    New-Item -ItemType Directory -Path $logRoot -Force | Out-Null
}

$result | ConvertTo-Json -Depth 10 | Out-File "$logRoot\preflight-scan-log.json" -Encoding utf8

Write-Host "Preflight scan complete." -ForegroundColor Green
