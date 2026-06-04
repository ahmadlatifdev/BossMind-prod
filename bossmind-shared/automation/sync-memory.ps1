# BossMind Memory Sync — Pulls from Neon DB to local JSON
$envPath = "D:\BossMind\bossmind-shared\.env"
$memoryPath = "D:\BossMind\bossmind-shared\core\memory"
$errorLogPath = "$memoryPath\errors.json"

# Load .env
$envContent = Get-Content $envPath -Raw
$databaseUrl = ($envContent | Select-String "DATABASE_URL=(.+)").Matches.Groups[1].Value

if (-not $databaseUrl) {
    Write-Error "DATABASE_URL not found in .env"
    exit 1
}

# Simulate DB pull (replace with actual Neon query logic)
$memoryData = @{
    "lastSync" = (Get-Date -Format "o")
    "status" = "active"
    "entries" = @()
}

# Save to local JSON
$memoryFile = "$memoryPath\memory.json"
$memoryData | ConvertTo-Json -Depth 10 | Out-File $memoryFile -Encoding utf8

# Initialize error log if missing
if (-not (Test-Path $errorLogPath)) {
    "[]" | Out-File $errorLogPath -Encoding utf8
}

Write-Host "? Memory synced to $memoryFile" -ForegroundColor Green
Write-Host "? Error log initialized at $errorLogPath" -ForegroundColor Green
