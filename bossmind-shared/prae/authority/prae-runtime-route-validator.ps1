$PraeRoot = "D:\BossMind\bossmind-shared\prae"

$Routes = @(
    @{
        name = "resumora-production-health"
        url = "https://www.resumora.net/api/health"
        expected_status = 200
    },
    @{
        name = "resumora-orchestration-protected"
        url = "https://www.resumora.net/api/orchestration/bossmind-health"
        expected_status = 401
    }
)

$Results = @()

foreach ($Route in $Routes) {
    try {
        $Response = Invoke-WebRequest `
            -Uri $Route.url `
            -Method GET `
            -TimeoutSec 20 `
            -UseBasicParsing

        $StatusCode = [int]$Response.StatusCode
    }
    catch {
        if ($_.Exception.Response -ne $null) {
            $StatusCode = [int]$_.Exception.Response.StatusCode
        }
        else {
            $StatusCode = $null
        }
    }

    $Results += [PSCustomObject]@{
        name = $Route.name
        url = $Route.url
        expected_status = $Route.expected_status
        actual_status = $StatusCode
        passed = ($StatusCode -eq $Route.expected_status)
    }
}

$Event = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_RUNTIME_ROUTE_VALIDATION"
    authority = "PRAE"
    governance_mode = "LOCKED"
    production_mutation = "NONE"
    auto_repair = "DISABLED"
    routes = $Results
    result = if (($Results.passed -contains $false)) { "ALERT" } else { "SUCCESS" }
} | ConvertTo-Json -Depth 30

Add-Content -Path "$PraeRoot\runtime-ledger\prae-events.log" -Value $Event

$Event
