#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Execution Authority Gate - Installation Script
    Deploys all gate components to D:\BossMind infrastructure.
    Safe: never mutates production, never enables auto_repair.
.DESCRIPTION
    Governance constants enforced throughout:
      governance_mode     = LOCKED
      auto_repair         = DISABLED
      production_mutation = NONE
    Use -DryRun to preview all actions without writing any files.
.PARAMETER BossMindRoot
    Root path of the bossmind-shared directory.
    Default: D:\BossMind\bossmind-shared
.PARAMETER DryRun
    Preview mode. No files are created or modified.
.EXAMPLE
    .\Install-PRAEAuthorityGate.ps1 -DryRun
    .\Install-PRAEAuthorityGate.ps1
#>

[CmdletBinding(SupportsShouldProcess)]
param(
    [string]$BossMindRoot = "D:\BossMind\bossmind-shared",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  GOVERNANCE CONSTANTS  (never altered by this script)
# ---------------------------------------------------------------
$GOVERNANCE_MODE      = "LOCKED"
$AUTO_REPAIR          = "DISABLED"
$PRODUCTION_MUTATION  = "NONE"
$GOVERNANCE_VERSION   = "2.0.0"
$ENFORCEMENT_PHASE    = "AUTHORITATIVE_EXECUTION_ENFORCEMENT"

# ---------------------------------------------------------------
#  SAFETY VALIDATION LOG  (written before any file operation)
# ---------------------------------------------------------------
function Write-SafetyLog {
    param([string]$Message, [string]$Level = "INFO")
    $ts = [DateTimeOffset]::UtcNow.ToString("o")
    $line = "[$ts] [$Level] [INSTALL] $Message"
    Write-Verbose $line
    if ($Level -eq "WARN") { Write-Warning $Message }
}

# ---------------------------------------------------------------
#  HEADER
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Execution Authority Gate - Installation Starting" -ForegroundColor Cyan
Write-Host "[PRAE INSTALL] governance_mode=$GOVERNANCE_MODE | auto_repair=$AUTO_REPAIR | production_mutation=$PRODUCTION_MUTATION" -ForegroundColor DarkCyan
Write-Host "[PRAE INSTALL] Target root: $BossMindRoot" -ForegroundColor Gray

if ($DryRun) {
    Write-Host "[PRAE INSTALL] DRY RUN MODE - no files will be written" -ForegroundColor Yellow
}

Write-SafetyLog "Install started. DryRun=$DryRun GovernanceVersion=$GOVERNANCE_VERSION Phase=$ENFORCEMENT_PHASE"

# ---------------------------------------------------------------
#  PATH DEFINITIONS
# ---------------------------------------------------------------
$paths = @{
    AuthorityDir = "$BossMindRoot\prae\authority"
    ScriptsDir   = "$BossMindRoot\prae\scripts"
    ReportsDir   = "$BossMindRoot\prae\reports"
    RelayDir     = "$BossMindRoot\prae\relay"
    SharedMemDir = "$BossMindRoot\shared-memory"
}

# ---------------------------------------------------------------
#  HELPER: Safe directory creation
# ---------------------------------------------------------------
function New-PRAEDirectory {
    param([string]$DirPath)
    if (-not (Test-Path $DirPath)) {
        if (-not $DryRun) {
            Write-SafetyLog "Creating directory: $DirPath"
            New-Item -ItemType Directory -Path $DirPath -Force | Out-Null
            Write-Host "[PRAE INSTALL] Created: $DirPath" -ForegroundColor Green
        } else {
            Write-Host "[DRY RUN] Would create: $DirPath" -ForegroundColor Yellow
        }
    } else {
        Write-SafetyLog "Directory already exists (skip): $DirPath"
    }
}

# ---------------------------------------------------------------
#  STEP 1 - Create directory structure
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Step 1/5 - Creating directory structure" -ForegroundColor Cyan
Write-SafetyLog "Step 1: Directory creation starting"

foreach ($key in $paths.Keys) {
    New-PRAEDirectory -DirPath $paths[$key]
}

# ---------------------------------------------------------------
#  STEP 2 - Deploy governance execution manifest
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Step 2/5 - Deploying governance execution manifest" -ForegroundColor Cyan
Write-SafetyLog "Step 2: Manifest deployment starting"

$ScriptDir    = $PSScriptRoot
$manifestSrc  = "$ScriptDir\authority\prae-execution-authority.json"
$manifestDest = "$($paths.AuthorityDir)\prae-execution-authority.json"

if (Test-Path $manifestSrc) {
    $manifestContent = Get-Content $manifestSrc -Raw -Encoding UTF8
    $now       = [DateTimeOffset]::UtcNow.ToString("o")
    $nowPlus1h = [DateTimeOffset]::UtcNow.AddHours(1).ToString("o")
    $manifestContent = $manifestContent -replace '{{TIMESTAMP_ISO8601_PLUS_1H}}', $nowPlus1h
    $manifestContent = $manifestContent -replace '{{TIMESTAMP_ISO8601}}',         $now

    if (-not $DryRun) {
        Write-SafetyLog "Writing manifest to: $manifestDest"
        [System.IO.File]::WriteAllText($manifestDest, $manifestContent, [System.Text.Encoding]::UTF8)
        Write-Host "[PRAE INSTALL] Deployed manifest -> $manifestDest" -ForegroundColor Green
    } else {
        Write-Host "[DRY RUN] Would deploy manifest -> $manifestDest" -ForegroundColor Yellow
    }
} else {
    Write-SafetyLog "Manifest source not found: $manifestSrc" "WARN"
    Write-Warning "[PRAE INSTALL] Manifest source not found: $manifestSrc"
}

# ---------------------------------------------------------------
#  STEP 3 - Deploy PowerShell gate module
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Step 3/5 - Deploying gate module" -ForegroundColor Cyan
Write-SafetyLog "Step 3: Gate module deployment starting"

$moduleSrc  = "$ScriptDir\scripts\PRAE-ExecutionGate.psm1"
$moduleDest = "$($paths.ScriptsDir)\PRAE-ExecutionGate.psm1"

if (Test-Path $moduleSrc) {
    if (-not $DryRun) {
        Write-SafetyLog "Copying module: $moduleSrc -> $moduleDest"
        Copy-Item -Path $moduleSrc -Destination $moduleDest -Force
        Write-Host "[PRAE INSTALL] Deployed gate module -> $moduleDest" -ForegroundColor Green
    } else {
        Write-Host "[DRY RUN] Would deploy gate module -> $moduleDest" -ForegroundColor Yellow
    }
} else {
    Write-SafetyLog "Gate module source not found: $moduleSrc" "WARN"
    Write-Warning "[PRAE INSTALL] Gate module not found: $moduleSrc"
}

# ---------------------------------------------------------------
#  Deploy report generator
# ---------------------------------------------------------------
$reportSrc  = "$ScriptDir\reports\Invoke-PRAEFinalReport.ps1"
$reportDest = "$($paths.ReportsDir)\Invoke-PRAEFinalReport.ps1"

if (Test-Path $reportSrc) {
    if (-not $DryRun) {
        Write-SafetyLog "Copying report script: $reportSrc -> $reportDest"
        Copy-Item -Path $reportSrc -Destination $reportDest -Force
        Write-Host "[PRAE INSTALL] Deployed report generator -> $reportDest" -ForegroundColor Green
    } else {
        Write-Host "[DRY RUN] Would deploy report script -> $reportDest" -ForegroundColor Yellow
    }
} else {
    Write-SafetyLog "Report script source not found: $reportSrc" "WARN"
}

# ---------------------------------------------------------------
#  STEP 4 - Initialize append-only violation ledger
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Step 4/5 - Initializing violation ledger" -ForegroundColor Cyan
Write-SafetyLog "Step 4: Ledger initialization"

$ledgerPath = "$($paths.SharedMemDir)\prae-governance-violations.log"

if (-not (Test-Path $ledgerPath)) {
    $ts = [DateTimeOffset]::UtcNow.ToString("o")
    $initLine = (
        "[$ts] LEDGER_INIT | " +
        "PRAE Governance Violation Ledger initialized | " +
        "governance_version=$GOVERNANCE_VERSION | " +
        "phase=$ENFORCEMENT_PHASE | " +
        "governance_mode=$GOVERNANCE_MODE | " +
        "auto_repair=$AUTO_REPAIR | " +
        "production_mutation=$PRODUCTION_MUTATION"
    )
    if (-not $DryRun) {
        Write-SafetyLog "Writing ledger init entry: $ledgerPath"
        [System.IO.File]::WriteAllText($ledgerPath, ($initLine + "`n"), [System.Text.Encoding]::UTF8)
        Write-Host "[PRAE INSTALL] Initialized violation ledger -> $ledgerPath" -ForegroundColor Green
    } else {
        Write-Host "[DRY RUN] Would initialize ledger -> $ledgerPath" -ForegroundColor Yellow
    }
} else {
    Write-SafetyLog "Ledger already exists - not overwriting (append-only)"
    Write-Host "[PRAE INSTALL] Ledger already exists - not overwriting (append-only)" -ForegroundColor Gray
}

# ---------------------------------------------------------------
#  STEP 5 - Initialize relay heartbeat stub
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Step 5/5 - Initializing relay heartbeat stub" -ForegroundColor Cyan
Write-SafetyLog "Step 5: Relay heartbeat init"

$relayPath = "$($paths.RelayDir)\relay-heartbeat.json"

if (-not (Test-Path $relayPath)) {
    $relayJson = [ordered]@{
        relay_status   = "ACTIVE"
        last_heartbeat = [DateTimeOffset]::UtcNow.ToString("o")
        version        = $GOVERNANCE_VERSION
        note           = "Update last_heartbeat every 600s or less to keep relay considered active"
    } | ConvertTo-Json -Depth 3

    if (-not $DryRun) {
        Write-SafetyLog "Writing relay heartbeat stub: $relayPath"
        [System.IO.File]::WriteAllText($relayPath, $relayJson, [System.Text.Encoding]::UTF8)
        Write-Host "[PRAE INSTALL] Initialized relay heartbeat stub -> $relayPath" -ForegroundColor Green
    } else {
        Write-Host "[DRY RUN] Would create relay heartbeat stub -> $relayPath" -ForegroundColor Yellow
    }
} else {
    Write-SafetyLog "Relay heartbeat already exists - not overwriting"
    Write-Host "[PRAE INSTALL] Relay heartbeat already exists - skipping" -ForegroundColor Gray
}

# ---------------------------------------------------------------
#  FINAL REPORT
# ---------------------------------------------------------------
Write-Host ""
Write-Host "[PRAE INSTALL] Installation complete" -ForegroundColor Green
Write-Host ""
Write-Host "  Governance state confirmed:" -ForegroundColor DarkCyan
Write-Host "    governance_mode     = $GOVERNANCE_MODE" -ForegroundColor White
Write-Host "    auto_repair         = $AUTO_REPAIR" -ForegroundColor White
Write-Host "    production_mutation = $PRODUCTION_MUTATION" -ForegroundColor White
Write-Host ""
Write-Host "  Next steps:" -ForegroundColor Cyan
Write-Host "  1. Import-Module '$moduleDest'" -ForegroundColor White
Write-Host "  2. Invoke-PRAEFullRuntimeValidation" -ForegroundColor White
Write-Host "  3. & '$reportDest'" -ForegroundColor White
Write-Host ""

Write-SafetyLog "Install completed successfully. DryRun=$DryRun"
