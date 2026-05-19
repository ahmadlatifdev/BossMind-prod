# ==============================================
# BossMind Global ENV Orchestrator
# ==============================================
$ErrorActionPreference = "Stop"
$masterEnv = "D:\BossMind\bossmind-shared\.env"
$projects = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
)
$requiredVars = @("DATABASE_URL", "DEEPSEEK_API_KEY", "RAILWAY_TOKEN")  # add others as needed

if (-not (Test-Path $masterEnv)) {
    Write-Host "❌ Master .env not found: $masterEnv" -ForegroundColor Red
    exit 1
}

$masterContent = Get-Content $masterEnv -Raw
$missing = @()
foreach ($var in $requiredVars) {
    if ($masterContent -notmatch "$var=") {
        $missing += $var
        Write-Host "⚠️ Missing required variable: $var" -ForegroundColor Yellow
    }
}
if ($missing.Count -gt 0) {
    Write-Host "❌ Cannot sync – missing required vars in master .env" -ForegroundColor Red
    exit 1
}

foreach ($proj in $projects) {
    $target = "D:\BossMind\$proj\.env"
    $masterContent | Out-File $target -Encoding utf8 -Force
    Write-Host "✅ Synced $proj" -ForegroundColor Green
}

Write-Host "🎯 All projects synced from master .env" -ForegroundColor Cyan
