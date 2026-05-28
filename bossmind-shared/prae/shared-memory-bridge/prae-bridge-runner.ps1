#Requires -Version 5.1
<#
.SYNOPSIS
  PRAE Shared Memory Bridge — single entry point (governance-first, NO DIRECT EXECUTION).
#>
param(
  [string]$HubRoot = "D:\BossMind",
  [switch]$BootstrapOnly,
  [switch]$InstallScheduler,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
$BridgeRoot = Join-Path $HubRoot "bossmind-shared\prae\shared-memory-bridge"
$Bootstrap = Join-Path $BridgeRoot "prae-bridge-bootstrap.ps1"
$Runner = Join-Path $BridgeRoot "prae-governance-runner.ps1"

if (-not (Test-Path $Bootstrap)) { throw "Missing: $Bootstrap" }

& $Bootstrap -HubRoot $HubRoot
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }

if ($BootstrapOnly) { exit 0 }

if ($InstallScheduler) {
  & $Runner -HubRoot $HubRoot -InstallScheduler
}

if ($Strict) {
  & node (Join-Path $BridgeRoot "prae-shared-memory-bridge.mjs") --strict
} else {
  & node (Join-Path $BridgeRoot "prae-shared-memory-bridge.mjs")
}
exit $LASTEXITCODE
