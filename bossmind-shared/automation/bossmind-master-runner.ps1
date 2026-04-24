function Load-IncidentChain {
    $path = "D:\BossMind\bossmind-shared\automation\incident-repair-chain.json"
    if (Test-Path $path) {
        $chain = Get-Content $path | ConvertFrom-Json
        return $chain
    } else {
        Write-Output "Incident chain file missing."
        exit
    }
}

$GLOBAL:IncidentChain = Load-IncidentChain
Write-Output "Incident Repair Chain Loaded: $($GLOBAL:IncidentChain.chain_name)"