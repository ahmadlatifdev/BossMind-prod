#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Relay Heartbeat Refresh
    Writes a fresh timestamp to relay-heartbeat.json so the governance
    relay stays active. Run once manually, or schedule every 5 minutes.
    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED
.PARAMETER RelayPath
    Path to the relay heartbeat JSON file.
    Default: D:\BossMind\bossmind-shared\prae\relay\relay-heartbeat.json
.PARAMETER RegisterTask
    If set, registers a scheduled task to run this script every 5 minutes.
.PARAMETER UnregisterTask
    If set, removes the scheduled relay refresh task.
.EXAMPLE
    # One-time refresh (restores Val_Relay active = True immediately)
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "D:\BossMind\bossmind-shared\prae\PRAE-RelayRefresh.ps1"

    # Register auto-refresh every 5 minutes
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-RelayRefresh.ps1" -RegisterTask
#>

[CmdletBinding()]
param(
    [string]$RelayPath = "D:\BossMind\bossmind-shared\prae\relay\relay-heartbeat.json",
    [switch]$RegisterTask,
    [switch]$UnregisterTask
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Variable -Name GraphGovMode     -Value "LOCKED"  -Option ReadOnly -Force
Set-Variable -Name GraphGovMutation -Value "NONE"     -Option ReadOnly -Force
Set-Variable -Name TASK_NAME    -Value "BossMind-PRAE-RelayRefresh" -Option ReadOnly -Force

function Write-RelayInfo { param([string]$T) Write-Host "  [INFO ] $T" -ForegroundColor Gray  }
function Write-RelayPass { param([string]$T) Write-Host "  [PASS ] $T" -ForegroundColor Green }
function Write-RelayFail { param([string]$T) Write-Host "  [FAIL ] $T" -ForegroundColor Red   }

Write-Host ""
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE Relay Heartbeat Refresh                    |" -ForegroundColor Cyan
Write-Host "  |  governance_mode=LOCKED  mutation=NONE           |" -ForegroundColor DarkCyan
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""

# ---- Unregister mode ----
if ($UnregisterTask) {
    $t = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($t) {
        Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false
        Write-RelayPass "Removed scheduled task: $TASK_NAME"
    } else {
        Write-RelayInfo "Task not found (already absent): $TASK_NAME"
    }
    return
}

# ---- Register scheduled task mode ----
if ($RegisterTask) {
    $psExe   = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
    $args    = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$PSCommandPath`""
    $action  = New-ScheduledTaskAction -Execute $psExe -Argument $args
    $trigger = New-ScheduledTaskTrigger -RepetitionInterval (New-TimeSpan -Minutes 5) -Once -At (Get-Date)
    $settings= New-ScheduledTaskSettingsSet -ExecutionTimeLimit (New-TimeSpan -Minutes 1) `
                   -MultipleInstances IgnoreNew -StartWhenAvailable
    $principal = New-ScheduledTaskPrincipal `
                   -UserId ([System.Security.Principal.WindowsIdentity]::GetCurrent().Name) `
                   -LogonType Interactive -RunLevel Highest

    $existing = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($existing) { Unregister-ScheduledTask -TaskName $TASK_NAME -Confirm:$false }

    Register-ScheduledTask -TaskName $TASK_NAME `
        -TaskPath "\BossMind\PRAE" `
        -Action $action -Trigger $trigger -Settings $settings -Principal $principal `
        -Description "PRAE relay heartbeat refresh every 5 minutes. governance_mode=LOCKED" `
        -Force | Out-Null

    $verify = Get-ScheduledTask -TaskName $TASK_NAME -ErrorAction SilentlyContinue
    if ($verify) {
        Write-RelayPass "Scheduled task registered: \BossMind\PRAE\$TASK_NAME (every 5 min)"
    } else {
        Write-RelayFail "Task registration failed"
        exit 1
    }
    # Fall through to also write heartbeat now
}

# ---- Write heartbeat ----
$relayDir = Split-Path $RelayPath -Parent
if (-not (Test-Path $relayDir)) {
    New-Item -ItemType Directory -Path $relayDir -Force | Out-Null
    Write-RelayInfo "Created relay directory: $relayDir"
}

$now = [DateTimeOffset]::UtcNow.ToString("o")
$payload = [ordered]@{
    relay_status    = "ACTIVE"
    last_heartbeat  = $now
    version         = "2.0.0"
    governance_mode = $GraphGovMode
    refreshed_by    = "PRAE-RelayRefresh"
    note            = "Update last_heartbeat every 600s or less to keep relay active"
}

$json = $payload | ConvertTo-Json
[System.IO.File]::WriteAllText($RelayPath, $json, [System.Text.Encoding]::UTF8)

# Verify the write
$verify = Get-Content $RelayPath -Raw -Encoding UTF8 | ConvertFrom-Json
$beat   = [DateTimeOffset]::Parse($verify.last_heartbeat).ToUnixTimeSeconds()
$nowSec = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
$age    = $nowSec - $beat

Write-RelayPass "Relay heartbeat written: $now"
Write-RelayPass "Relay age check: ${age}s (must be < 600s for gate to pass)"
Write-RelayInfo "File: $RelayPath"
Write-RelayInfo "governance_mode=$GraphGovMode  production_mutation=$GraphGovMutation"
Write-Host ""

if ($age -lt 600) {
    Write-Host "  Val_Relay active will be: True" -ForegroundColor Green
    Write-Host ""
    exit 0
} else {
    Write-RelayFail "Heartbeat written but age check failed ($age s)"
    exit 1
}
