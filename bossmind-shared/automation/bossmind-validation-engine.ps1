# ================================
# BossMind Validation + Optimization Engine
# ================================

$timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

Write-Host "🔍 VALIDATION ENGINE STARTED @ $timestamp"

# ----------- CONFIG -----------
$projects = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
)

$basePath = "D:\BossMind"
$logFile = "$basePath\bossmind-shared\logs\validation-log.txt"

# ----------- FUNCTIONS -----------

function Check-ServiceAlive {
    param($project)

    $path = "$basePath\$project"

    if (Test-Path $path) {
        Write-Host "✅ $project path OK"
        return $true
    } else {
        Write-Host "❌ $project path MISSING"
        return $false
    }
}

function Check-Env {
    param($project)

    $envPath = "$basePath\$project\.env"

    if (Test-Path $envPath) {
        Write-Host "✅ .env OK for $project"
        return $true
    } else {
        Write-Host "⚠️ .env missing for $project"
        return $false
    }
}

function Check-Build {
    param($project)

    $pkg = "$basePath\$project\package.json"

    if (Test-Path $pkg) {
        Write-Host "✅ package.json OK ($project)"
        return $true
    } else {
        Write-Host "❌ Missing package.json ($project)"
        return $false
    }
}

function Log-Result {
    param($text)

    Add-Content -Path $logFile -Value "$timestamp - $text"
}

# ----------- VALIDATION LOOP -----------

$globalStatus = "OK"

foreach ($project in $projects) {

    Write-Host "`n🔎 Checking: $project"

    $alive = Check-ServiceAlive $project
    $env   = Check-Env $project
    $build = Check-Build $project

    if (-not ($alive -and $env -and $build)) {
        $globalStatus = "DEGRADED"
        Log-Result "$project FAILED validation"
    } else {
        Log-Result "$project PASSED validation"
    }
}

# ----------- OPTIMIZATION CHECK -----------

Write-Host "`n⚡ Optimization Scan..."

$cpu = Get-Counter '\Processor(_Total)\% Processor Time'
$ram = Get-Counter '\Memory\Available MBytes'

Write-Host "CPU Load: $($cpu.CounterSamples.CookedValue)%"
Write-Host "Available RAM: $($ram.CounterSamples.CookedValue) MB"

if ($cpu.CounterSamples.CookedValue -gt 85) {
    $globalStatus = "DEGRADED"
    Log-Result "High CPU usage detected"
}

if ($ram.CounterSamples.CookedValue -lt 500) {
    $globalStatus = "DEGRADED"
    Log-Result "Low memory detected"
}

# ----------- FINAL STATUS -----------

Write-Host "`n📊 FINAL STATUS: $globalStatus"
Log-Result "SYSTEM STATUS = $globalStatus"

if ($globalStatus -eq "DEGRADED") {
    Write-Host "⚠️ Triggering Auto-Healing..."
    & "$basePath\bossmind-shared\automation\bossmind-auto-fix.ps1"
}

Write-Host "✅ VALIDATION COMPLETE"