#Requires -Version 5.1
<#
.SYNOPSIS
  PRAE Governance Bootstrap — safe initialization without secret exposure or production mutation.
#>
param(
  [string]$HubRoot = "D:\BossMind",
  [switch]$Silent
)

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

$BridgeRoot = Join-Path $HubRoot "bossmind-shared\prae\shared-memory-bridge"
$BootstrapScript = Join-Path $BridgeRoot "prae-shared-memory-bridge.mjs"
$GovernanceLoader = Join-Path $HubRoot "bossmind-shared\prae\authority\prae-governance-loader.ps1"
$GlobalLedger = Join-Path $HubRoot "bossmind-shared\prae\global-ledger"

@(
  $GlobalLedger,
  (Join-Path $GlobalLedger "deployment-proof"),
  (Join-Path $GlobalLedger "drift-evidence"),
  (Join-Path $GlobalLedger "repair-simulation")
) | ForEach-Object {
  if (-not (Test-Path $_)) { New-Item -ItemType Directory -Force -Path $_ | Out-Null }
}

if (-not (Test-Path (Join-Path $GlobalLedger "governance-events.jsonl"))) {
  $init = @{
    schema = "bossmind-prae-global-ledger-init/v1"
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    event = "PRAE_GLOBAL_LEDGER_INITIALIZED"
    append_only = $true
    secret_values_exposed = $false
    production_mutation = "NONE"
  } | ConvertTo-Json -Compress
  Add-Content -Path (Join-Path $GlobalLedger "governance-events.jsonl") -Value $init -Encoding UTF8
}

if (Test-Path $GovernanceLoader) {
  & $GovernanceLoader | Out-Null
}

if (-not (Test-Path $BootstrapScript)) {
  throw "Bridge engine not found: $BootstrapScript"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) { throw "Node.js required for PRAE bridge bootstrap" }

& node $BootstrapScript
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if (-not $Silent) {
  Write-Host "PRAE governance bootstrap complete." -ForegroundColor Green
}
