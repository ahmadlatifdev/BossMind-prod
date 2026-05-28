#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Reboot Persistence Registration
    Registers two scheduled tasks so PRAE auto-validates after reboot and logon.
.DESCRIPTION
    Creates:
      BossMind-PRAE-AutoValidate-Startup  triggers on system startup
      BossMind-PRAE-AutoValidate-Logon    triggers on current user logon

    Both tasks run:
      powershell.exe -NoProfile -ExecutionPolicy Bypass
          -File "<ActivateScript>" -SkipReport

    Nothing in this script modifies any existing PRAE file.
    governance_mode=LOCKED  auto_repair=DISABLED  production_mutation=NONE
.EXAMPLE
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "D:\BossMind\bossmind-shared\prae\PRAE-RegisterPersistence.ps1"
#>

[CmdletBinding()]
param(
    [string]$ActivateScript = "D:\BossMind\bossmind-shared\prae\PRAE-ActivateAndValidate.ps1",
    [string]$TaskNameStartup = "BossMind-PRAE-AutoValidate-Startup",
    [string]$TaskNameLogon   = "BossMind-PRAE-AutoValidate-Logon",
    [string]$TaskFolder      = "\BossMind\PRAE",
    [switch]$Unregister
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  GOVERNANCE CONSTANTS (ReadOnly)
# ---------------------------------------------------------------
Set-Variable -Name GOV_MODE     -Value "LOCKED"   -Option ReadOnly -Force
Set-Variable -Name GOV_REPAIR   -Value "DISABLED"  -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION -Value "NONE"      -Option ReadOnly -Force

# ---------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------
function Write-Info  { param([string]$T) Write-Host "  [INFO ] $T" -ForegroundColor Gray    }
function Write-Pass  { param([string]$T) Write-Host "  [PASS ] $T" -ForegroundColor Green   }
function Write-Fail  { param([string]$T) Write-Host "  [FAIL ] $T" -ForegroundColor Red     }
function Write-Warn  { param([string]$T) Write-Host "  [WARN ] $T" -ForegroundColor Yellow  }
function Write-Step  { param([string]$T) Write-Host "`n  -- $T" -ForegroundColor Cyan       }

# ---------------------------------------------------------------
#  HEADER
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE Reboot Persistence Registration            |" -ForegroundColor Cyan
Write-Host "  |  governance_mode=LOCKED  auto_repair=DISABLED    |" -ForegroundColor DarkCyan
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan

# ---------------------------------------------------------------
#  UNREGISTER MODE
# ---------------------------------------------------------------
if ($Unregister) {
    Write-Step "Unregister mode - removing PRAE scheduled tasks"
    foreach ($name in @($TaskNameStartup, $TaskNameLogon)) {
        $existing = Get-ScheduledTask -TaskName $name -ErrorAction SilentlyContinue
        if ($existing) {
            Unregister-ScheduledTask -TaskName $name -Confirm:$false
            Write-Pass "Removed: $name"
        } else {
            Write-Info "Not found (already absent): $name"
        }
    }
    Write-Host ""
    return
}

# ---------------------------------------------------------------
#  STEP 1: Pre-flight checks (read-only)
# ---------------------------------------------------------------
Write-Step "Step 1/4 - Pre-flight checks"

# Activate script must exist
if (-not (Test-Path $ActivateScript)) {
    Write-Fail "Activate script not found: $ActivateScript"
    Write-Fail "Run Install-PRAEAuthorityGate.ps1 first."
    exit 1
}
Write-Pass "Activate script exists: $ActivateScript"

# Must not be read-only (task scheduler writes nothing to it, just a safety confirm)
$item = Get-Item $ActivateScript
Write-Info "File size: $($item.Length) bytes  LastWrite: $($item.LastWriteTime)"

# Confirm powershell.exe location
$psExe = "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe"
if (-not (Test-Path $psExe)) {
    $psExe = "powershell.exe"  # fallback to PATH resolution
    Write-Warn "powershell.exe not at default path - using PATH: $psExe"
} else {
    Write-Pass "powershell.exe: $psExe"
}

# Current user identity (tasks run as this user)
$currentUser = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
Write-Info "Registering tasks to run as: $currentUser"

# ---------------------------------------------------------------
#  STEP 2: Build shared task components
# ---------------------------------------------------------------
Write-Step "Step 2/4 - Building task components"

# Action: same for both tasks
$taskArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$ActivateScript`" -SkipReport"
$action   = New-ScheduledTaskAction -Execute $psExe -Argument $taskArgs
Write-Info "Action: $psExe $taskArgs"

# Settings: lightweight, won't wake machine, won't run on battery demand
$settings = New-ScheduledTaskSettingsSet `
    -ExecutionTimeLimit (New-TimeSpan -Minutes 5) `
    -MultipleInstances  IgnoreNew `
    -StartWhenAvailable `
    -DontStopIfGoingOnBatteries `
    -AllowStartIfOnBatteries
Write-Pass "Task settings built"

# Principal: run as current user, only when logged in, highest available privilege
$principal = New-ScheduledTaskPrincipal `
    -UserId    $currentUser `
    -LogonType Interactive `
    -RunLevel  Highest
Write-Pass "Principal: $currentUser (Interactive, Highest)"

# ---------------------------------------------------------------
#  STEP 3: Register both tasks
# ---------------------------------------------------------------
Write-Step "Step 3/4 - Registering scheduled tasks"

# -- Task 1: Startup trigger --
$triggerStartup = New-ScheduledTaskTrigger -AtStartup
Write-Info "Startup trigger: fires on system boot"

$taskDefStartup = New-ScheduledTask `
    -Action    $action `
    -Trigger   $triggerStartup `
    -Settings  $settings `
    -Principal $principal `
    -Description "PRAE governance auto-validation on system startup. governance_mode=LOCKED auto_repair=DISABLED production_mutation=NONE"

try {
    # Remove existing before re-registering (idempotent)
    $existing = Get-ScheduledTask -TaskName $TaskNameStartup -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskNameStartup -Confirm:$false
        Write-Info "Replaced existing task: $TaskNameStartup"
    }
    Register-ScheduledTask `
        -TaskName   $TaskNameStartup `
        -TaskPath   $TaskFolder `
        -InputObject $taskDefStartup `
        -Force | Out-Null
    Write-Pass "Registered: $TaskFolder\$TaskNameStartup"
} catch {
    Write-Fail "Failed to register startup task: $_"
    exit 1
}

# -- Task 2: Logon trigger --
$triggerLogon = New-ScheduledTaskTrigger -AtLogOn -User $currentUser
Write-Info "Logon trigger: fires when $currentUser logs on"

$taskDefLogon = New-ScheduledTask `
    -Action    $action `
    -Trigger   $triggerLogon `
    -Settings  $settings `
    -Principal $principal `
    -Description "PRAE governance auto-validation on user logon. governance_mode=LOCKED auto_repair=DISABLED production_mutation=NONE"

try {
    $existing = Get-ScheduledTask -TaskName $TaskNameLogon -ErrorAction SilentlyContinue
    if ($existing) {
        Unregister-ScheduledTask -TaskName $TaskNameLogon -Confirm:$false
        Write-Info "Replaced existing task: $TaskNameLogon"
    }
    Register-ScheduledTask `
        -TaskName   $TaskNameLogon `
        -TaskPath   $TaskFolder `
        -InputObject $taskDefLogon `
        -Force | Out-Null
    Write-Pass "Registered: $TaskFolder\$TaskNameLogon"
} catch {
    Write-Fail "Failed to register logon task: $_"
    exit 1
}

# ---------------------------------------------------------------
#  STEP 4: Verification
# ---------------------------------------------------------------
Write-Step "Step 4/4 - Verifying registration"

$verifyResults = @()
foreach ($taskName in @($TaskNameStartup, $TaskNameLogon)) {
    $task = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($task) {
        $state   = $task.State.ToString()
        $trigger = ($task.Triggers | ForEach-Object { $_.CimClass.CimClassName }) -join ", "
        Write-Pass "$taskName"
        Write-Info "  State  : $state"
        Write-Info "  Trigger: $trigger"
        Write-Info "  Path   : $($task.TaskPath)"
        $verifyResults += $true
    } else {
        Write-Fail "$taskName NOT FOUND after registration"
        $verifyResults += $false
    }
}

# ---------------------------------------------------------------
#  RESULT
# ---------------------------------------------------------------
Write-Host ""
$allOk = $verifyResults -notcontains $false
if ($allOk) {
    Write-Host "  [REGISTERED] Both PRAE persistence tasks active." -ForegroundColor Green
    Write-Host "  PRAE auto-validation will run on reboot and logon." -ForegroundColor Green
} else {
    Write-Host "  [PARTIAL] One or more tasks failed to register." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Governance state at exit:" -ForegroundColor DarkCyan
Write-Host "    governance_mode     = $GOV_MODE"     -ForegroundColor White
Write-Host "    auto_repair         = $GOV_REPAIR"   -ForegroundColor White
Write-Host "    production_mutation = $GOV_MUTATION" -ForegroundColor White
Write-Host ""
Write-Host "  Verify with:" -ForegroundColor Gray
Write-Host "    Get-ScheduledTask -TaskName '$TaskNameStartup'" -ForegroundColor Gray
Write-Host "    Get-ScheduledTask -TaskName '$TaskNameLogon'"   -ForegroundColor Gray
Write-Host "  Remove with:" -ForegroundColor Gray
Write-Host "    .\PRAE-RegisterPersistence.ps1 -Unregister" -ForegroundColor Gray
Write-Host ""

if (-not $allOk) { exit 1 }
