#Requires -Version 5.1
<#
.SYNOPSIS
  BossMind Permanent Autonomous Execution Runner — mandatory staged workflow entry point.

.DESCRIPTION
  NO DIRECT EXECUTION. Routes every request through the 10-phase autonomous execution engine.
  PowerShell wrapper for Windows automation, schedulers, and agent bridges.

.EXAMPLE
  .\bossmind-autonomous-execution-runner.ps1 -Request "Deploy Stripe webhook activation to Render"
.EXAMPLE
  .\bossmind-autonomous-execution-runner.ps1 -RequestFile "D:\BossMind\13-shared-memory\latest-request.txt"
#>
param(
  [string]$Request = "",
  [string]$RequestFile = "",
  [switch]$Execute,
  [switch]$Strict
)

$ErrorActionPreference = "Stop"
Import-Module Microsoft.PowerShell.Utility -ErrorAction SilentlyContinue

$EngineRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$Engine = Join-Path $EngineRoot "autonomous-execution\bossmind-autonomous-execution-engine.mjs"
$HubRoot = "D:\BossMind"
$LogDir = Join-Path $HubRoot "bossmind-shared\logs"
New-Item -ItemType Directory -Force -Path $LogDir | Out-Null

if (-not (Test-Path $Engine)) {
  Write-Error "Engine not found: $Engine"
}

$nodeArgs = @($Engine)
if ($RequestFile -and (Test-Path $RequestFile)) {
  $nodeArgs += @("--request-file", $RequestFile)
} elseif ($Request) {
  $nodeArgs += @("--request", $Request)
} else {
  Write-Error "Provide -Request or -RequestFile. Direct execution is forbidden without classification."
}

if ($Execute) { $nodeArgs += "--execute" }
if ($Strict) { $env:BOSSMIND_EXECUTION_STRICT = "1" }

$logFile = Join-Path $LogDir "autonomous-execution-$(Get-Date -Format 'yyyyMMdd-HHmmss').log"
Write-Host "BossMind Autonomous Execution Engine — NO DIRECT EXECUTION" -ForegroundColor Cyan
Write-Host "Log: $logFile"

& node @nodeArgs 2>&1 | Tee-Object -FilePath $logFile
exit $LASTEXITCODE
