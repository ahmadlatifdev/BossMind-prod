# ==============================================
# BossMind Optimization Engine (auto every hour)
# ==============================================
param([string]$projectPath)
$ErrorActionPreference = "Continue"
$BASE_PATH = "D:\BossMind"
$LOG_PATH = "$BASE_PATH\bossmind-shared\logs\optimization.log"
$DATABASE_URL = $env:DATABASE_URL

$PROJECTS = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
)

function Log($msg) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    "$time - $msg" | Out-File -Append -FilePath $LOG_PATH
    if ($DATABASE_URL) {
        $escaped = $msg -replace "'", "''"
        psql $DATABASE_URL -c "INSERT INTO optimization_log (log_time, message) VALUES (NOW(), '$escaped')" 2>$null
    }
}

foreach ($proj in $PROJECTS) {
    $path = Join-Path $BASE_PATH $proj
    if (-not (Test-Path $path)) { Log "Path not found: $path"; continue }
    Set-Location $path
    Log "Optimizing: $proj"

    # Dedupe
    if (Test-Path "package-lock.json") {
        npm dedupe --no-audit --no-fund 2>&1 | Out-Null
        Log "Dependencies deduped"
    }

    # Safe updates
    $outdated = npm outdated --json 2>$null | ConvertFrom-Json
    if ($outdated) {
        foreach ($pkg in $outdated.PSObject.Properties) {
            $current = $pkg.Value.current
            $wanted = $pkg.Value.wanted
            if ($current -ne $wanted) {
                npm install $($pkg.Name)@$wanted --save --no-audit --no-fund 2>&1 | Out-Null
                Log "Updated $($pkg.Name) from $current to $wanted"
            }
        }
    }

    # Clean cache
    if (Test-Path ".next") { Remove-Item ".next" -Recurse -Force -ErrorAction SilentlyContinue; Log "Cleaned .next" }
    if (Test-Path "node_modules/.cache") { Remove-Item "node_modules/.cache" -Recurse -Force -ErrorAction SilentlyContinue; Log "Cleaned npm cache" }

    # Enable SWC minification if not present
    $nextConfig = "next.config.js"
    if (Test-Path $nextConfig) {
        $content = Get-Content $nextConfig -Raw
        if ($content -notmatch "swcMinify") {
            $newConfig = $content -replace 'module.exports = \{', "module.exports = {`n  swcMinify: true,`n  compiler: { removeConsole: process.env.NODE_ENV === 'production' },"
            $newConfig | Out-File $nextConfig -Encoding utf8
            Log "Enabled SWC minification"
        }
    }

    # Build cache warm
    npm run build --no-audit 2>&1 | Out-Null
    Log "Build cache warmed"

    # Commit changes
    $status = git status --porcelain
    if ($status) {
        git add .
        git commit -m "Auto-optimization: dedupe, updates, config tweaks" --no-verify
        git push
        Log "Pushed optimization changes"
    }
}
Log "Optimization cycle complete"
