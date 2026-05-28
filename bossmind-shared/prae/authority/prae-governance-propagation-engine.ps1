$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$Projects = @(
    "D:\BossMind\bossmind-resumora",
    "D:\BossMind\elegancyart",
    "D:\BossMind\ai-video-generator",
    "D:\BossMind\tiktok-ai",
    "D:\BossMind\global-stock",
    "D:\BossMind\bossmind-shared",
    "D:\BossMind\master-admin"
)

$Governance = @(
    "PRAE_GOVERNANCE_MODE=LOCKED",
    "PRAE_DEPLOYMENT_MODE=STAGED",
    "PRAE_UI_LOCK=ENABLED",
    "PRAE_RESTORE_SEAL=DISABLED",
    "PRAE_AUTONOMOUS_MUTATION=RESTRICTED",
    "PRAE_PRODUCTION_MUTATION=BLOCKED",
    "PRAE_AUTO_REPAIR=DISABLED",
    "PRAE_AUTHORITY=PRAE_ONLY"
)

$Results = @()

foreach ($Project in $Projects) {
    $ProjectExists = Test-Path $Project
    $GovernanceFile = Join-Path $Project ".prae-governance.local"

    if ($ProjectExists) {
        Set-Content -Path $GovernanceFile -Value $Governance -Encoding UTF8

        $Results += [PSCustomObject]@{
            project = $Project
            exists = $true
            governance_file = $GovernanceFile
            propagation = "APPLIED"
        }
    }
    else {
        $Results += [PSCustomObject]@{
            project = $Project
            exists = $false
            governance_file = $GovernanceFile
            propagation = "SKIPPED_PROJECT_NOT_FOUND"
        }
    }
}

$Event = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_CROSS_PROJECT_GOVERNANCE_PROPAGATION"
    authority = "PRAE"
    governance_mode = "LOCKED"
    production_mutation = "NONE"
    auto_repair = "DISABLED"
    results = $Results
} | ConvertTo-Json -Depth 30

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
