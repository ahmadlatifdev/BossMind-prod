$envFile = "D:\BossMind\bossmind-shared\.env"

if (!(Test-Path $envFile)) {
    Write-Host "SECURE ENV MISSING" -ForegroundColor Red
    exit 1
}

Get-Content $envFile | ForEach-Object {
    if ($_ -match "^\s*[^#][^=]+=") {
        $key, $value = $_ -split "=", 2
        [System.Environment]::SetEnvironmentVariable($key.Trim(), $value.Trim(), "Process")
    }
}

Write-Host "SECURE ENV LOADED" -ForegroundColor Green
