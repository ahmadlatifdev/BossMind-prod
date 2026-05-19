$ErrorActionPreference = "Stop"

$root = "D:\BossMind"
$shared = "$root\bossmind-shared"
$logs = "$shared\logs"
$logFile = "$logs\validation-runtime-log.json"

$projects = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
)

$results = @()

foreach ($project in $projects) {
    $path = Join-Path $root $project

    $results += [ordered]@{
        project = $project
        path = $path
        folder_exists = Test-Path $path
        automation_folder_exists = Test-Path (Join-Path $path "automation")
        required_files_json_exists = Test-Path (Join-Path $path "required-files.json")
        route_map_json_exists = Test-Path (Join-Path $path "route-map.json")
        deploy_config_json_exists = Test-Path (Join-Path $path "deploy-config.json")
        error_patterns_json_exists = Test-Path (Join-Path $path "error-patterns.json")
    }
}

$report = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    layer = "BossMind Validation Runtime"
    scope = "All 5 projects"
    database_url_loaded = [bool]$env:DATABASE_URL
    validation_runtime = "ACTIVE"
    total_projects_checked = $projects.Count
    results = $results
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $logFile -Encoding UTF8

Write-Host "✅ BossMind Validation Runtime ACTIVE"
Write-Host "✅ Checked all 5 project folders"
Write-Host "✅ Log saved: $logFile"
