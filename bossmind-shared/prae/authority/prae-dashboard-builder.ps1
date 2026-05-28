$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$Tasks = @(
    "BossMind-PRAE-Persistent-Governance",
    "BossMind-PRAE-Continuous-Governance",
    "BossMind-PRAE-Runtime-Route-Validation"
)

$TaskStatus = foreach ($Task in $Tasks) {

    $Found = Get-ScheduledTask -TaskName $Task -ErrorAction SilentlyContinue

    [PSCustomObject]@{
        task = $Task
        exists = ($null -ne $Found)
        state = if ($Found) { $Found.State.ToString() } else { "MISSING" }
    }
}

$Dashboard = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    system = "PRAE-GOVERNANCE-DASHBOARD"
    governance_mode = "LOCKED"
    deployment_mode = "STAGED"
    authority = "PRAE_ONLY"
    auto_repair = "DISABLED"
    production_mutation = "BLOCKED"
    ui_lock = "ENABLED"
    scheduled_tasks = $TaskStatus
} | ConvertTo-Json -Depth 30

$OutPath = "$PraeRoot\runtime-ledger\prae-governance-dashboard.json"

Set-Content -Path $OutPath -Value $Dashboard -Encoding UTF8

Write-Host ""
Write-Host "====================================="
Write-Host " PRAE GOVERNANCE DASHBOARD CREATED"
Write-Host "====================================="
Write-Host ""

Get-Content $OutPath
