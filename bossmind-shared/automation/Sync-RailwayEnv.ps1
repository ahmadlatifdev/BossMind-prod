# Sync master .env to Railway service
param([string]$serviceName = "bossmind-web")
$masterEnv = "D:\BossMind\bossmind-shared\.env"
$lines = Get-Content $masterEnv
foreach ($line in $lines) {
    if ($line -match "^([^=]+)=(.*)") {
        $key = $matches[1]
        $value = $matches[2]
        railway variables set --service $serviceName "$key=$value" 2>&1 | Out-Null
        Write-Host "Set $key on $serviceName"
    }
}
