$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$Checks = @()

# Runtime Route Checks
$Routes = @(
    @{
        name = "production-health"
        url = "https://www.resumora.net/api/health"
        expected = 200
    },
    @{
        name = "orchestration-protection"
        url = "https://www.resumora.net/api/orchestration/bossmind-health"
        expected = 401
    }
)

foreach ($Route in $Routes) {

    try {

        $Response = Invoke-WebRequest `
            -Uri $Route.url `
            -Method GET `
            -TimeoutSec 20 `
            -UseBasicParsing

        $Status = [int]$Response.StatusCode
    }
    catch {

        if ($_.Exception.Response -ne $null) {
            $Status = [int]$_.Exception.Response.StatusCode
        }
        else {
            $Status = $null
        }
    }

    $Checks += [PSCustomObject]@{
        type = "runtime-route"
        target = $Route.name
        expected = $Route.expected
        actual = $Status
        passed = ($Status -eq $Route.expected)
    }
}

# Governance File Checks
$GovernanceFiles = @(
    "$PraeRoot\runtime-ledger\prae-runtime-ledger.json",
    "$PraeRoot\checksums\prae-checksum-registry.json",
    "$PraeRoot\deployment-validation\prae-deployment-authority.json",
    "$PraeRoot\authority\prae-runtime-validation.json"
)

foreach ($File in $GovernanceFiles) {

    $Exists = Test-Path $File

    $Checks += [PSCustomObject]@{
        type = "governance-file"
        target = $File
        expected = "EXISTS"
        actual = if ($Exists) { "EXISTS" } else { "MISSING" }
        passed = $Exists
    }
}

$Result = if (($Checks.passed -contains $false)) {
    "DRIFT_ALERT"
}
else {
    "DEPLOYMENT_STABLE"
}

$Event = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_DEPLOYMENT_DRIFT_VALIDATION"
    authority = "PRAE"
    governance_mode = "LOCKED"
    production_mutation = "NONE"
    auto_repair = "DISABLED"
    deployment_state = $Result
    checks = $Checks
} | ConvertTo-Json -Depth 40

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

Write-Host ""
Write-Host "====================================="
Write-Host " PRAE DEPLOYMENT DRIFT VALIDATOR"
Write-Host "====================================="
Write-Host ""

$Event
