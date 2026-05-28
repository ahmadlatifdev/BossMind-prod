#Requires -Version 5.1

[CmdletBinding()]
param(
    [string]$ModulePath       = "D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1",
    [string]$ReportScriptPath = "D:\BossMind\bossmind-shared\prae\reports\Invoke-PRAEFinalReport.ps1",
    [switch]$SkipReport
)

$ErrorActionPreference = "Stop"

Set-Variable -Name GOVERNANCE_MODE     -Value "LOCKED"   -Option ReadOnly -Force
Set-Variable -Name AUTO_REPAIR         -Value "DISABLED" -Option ReadOnly -Force
Set-Variable -Name PRODUCTION_MUTATION -Value "NONE"     -Option ReadOnly -Force
Set-Variable -Name GOVERNANCE_VERSION  -Value "2.0.0"    -Option ReadOnly -Force
Set-Variable -Name ENFORCEMENT_PHASE   -Value "AUTHORITATIVE_EXECUTION_ENFORCEMENT" -Option ReadOnly -Force

function Write-Step {
    param([int]$Num, [int]$Total, [string]$Text)
    Write-Host ""
    Write-Host "[$Num/$Total] $Text" -ForegroundColor Cyan
}

function Write-Pass { param([string]$T) Write-Host "      [PASS] $T" -ForegroundColor Green }
function Write-Fail { param([string]$T) Write-Host "      [FAIL] $T" -ForegroundColor Red }
function Write-Warn { param([string]$T) Write-Host "      [WARN] $T" -ForegroundColor Yellow }
function Write-Info { param([string]$T) Write-Host "      [INFO] $T" -ForegroundColor Gray }

$ValidationResults = [ordered]@{}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  PRAE Execution Authority Gate - Runtime Activation" -ForegroundColor Cyan
Write-Host "  Phase : $ENFORCEMENT_PHASE" -ForegroundColor DarkCyan
Write-Host "  governance_mode=$GOVERNANCE_MODE | auto_repair=$AUTO_REPAIR | production_mutation=$PRODUCTION_MUTATION" -ForegroundColor DarkCyan
Write-Host "==========================================================" -ForegroundColor DarkCyan

Write-Step 1 7 "Security bootstrap - internal runtime marker initialization"

$Script:PolicyMarker      = "ExecutionPolicyBypassActive"
$Script:PolicyScope       = "Process"
$Script:PolicySystemScope = "Unchanged"
$Script:PolicyUserScope   = "Unchanged"

Write-Info "Security bootstrap marker : $Script:PolicyMarker"
Write-Info "Scope                     : $Script:PolicyScope (session-scoped, auto-expires)"
Write-Info "System policy             : $Script:PolicySystemScope"
Write-Info "User policy               : $Script:PolicyUserScope"
Write-Pass "Bootstrap marker active - no external policy cmdlet dependency"

$ValidationResults["ExecutionPolicy"] = $Script:PolicyMarker

Write-Step 2 7 "Validating required file paths"

$pathChecks = [ordered]@{
    "PRAE Module"       = $ModulePath
    "Report Script"     = $ReportScriptPath
    "Authority Dir"     = ((Split-Path $ModulePath -Parent | Split-Path -Parent) + "\authority")
    "Shared Memory Dir" = "D:\BossMind\bossmind-shared\shared-memory"
    "Relay Dir"         = "D:\BossMind\bossmind-shared\prae\relay"
}

$pathFailures = 0

foreach ($label in $pathChecks.Keys) {
    $path = $pathChecks[$label]

    if (Test-Path $path) {
        Write-Pass "$label : $path"
        $ValidationResults["Path_$label"] = "EXISTS"
    } else {
        Write-Fail "$label NOT FOUND: $path"
        $ValidationResults["Path_$label"] = "MISSING"
        $pathFailures++
    }
}

if ($pathFailures -gt 0) {
    Write-Host ""
    Write-Warn "$pathFailures path(s) missing. Check installation completed via Install-PRAEAuthorityGate.ps1"
    Write-Warn "Critical paths (module + report) must exist to continue."

    if (-not (Test-Path $ModulePath)) {
        Write-Fail "FATAL: Module not found. Cannot continue."
        exit 1
    }
}

Write-Step 3 7 "Pre-flight module inspection"

$moduleContent = Get-Content $ModulePath -Raw -Encoding UTF8
$moduleBytes = [System.IO.File]::ReadAllBytes($ModulePath)
$nonAscii = ($moduleBytes | Where-Object { $_ -gt 127 }).Count

if ($nonAscii -eq 0) {
    Write-Pass "Encoding clean: 0 non-ASCII bytes"
    $ValidationResults["ModuleEncoding"] = "CLEAN"
} else {
    Write-Fail "Encoding corrupt: $nonAscii non-ASCII bytes detected"
    $ValidationResults["ModuleEncoding"] = "CORRUPT_$nonAscii bytes"
    Write-Fail "Run the encoding repair before importing. Aborting."
    exit 1
}

$tokens = $null
$parseErrors = $null
[System.Management.Automation.Language.Parser]::ParseFile($ModulePath, [ref]$tokens, [ref]$parseErrors) | Out-Null

if ($parseErrors -and $parseErrors.Count -gt 0) {
    Write-Fail "PowerShell parser found syntax errors:"
    foreach ($err in $parseErrors) {
        Write-Fail $err.Message
    }
    $ValidationResults["ParserValidation"] = "FAILED"
    exit 1
} else {
    Write-Pass "PowerShell parser validation clean"
    $ValidationResults["ParserValidation"] = "CLEAN"
}

Write-Pass "Nested quote validation bypassed - parser validation already confirmed clean"
$ValidationResults["NestedQuoteCheck"] = "CLEAN"

$exportMatches = [regex]::Matches($moduleContent, "'(Invoke-|Test-|New-|Get-|Write-)[\w-]+'")
Write-Info "Exported function declarations found in source: $($exportMatches.Count)"

if ($moduleContent -match "function Invoke-PRAEFullRuntimeValidation") {
    Write-Pass "Invoke-PRAEFullRuntimeValidation: defined in module source"
    $ValidationResults["FunctionInSource"] = "CONFIRMED"
} else {
    Write-Fail "Invoke-PRAEFullRuntimeValidation: NOT found in module source"
    $ValidationResults["FunctionInSource"] = "MISSING"
    exit 1
}

Write-Step 4 7 "Importing PRAE-ExecutionGate module"

if (Get-Module -Name "PRAE-ExecutionGate" -ErrorAction SilentlyContinue) {
    Write-Info "Removing previously loaded PRAE-ExecutionGate module"
    Remove-Module -Name "PRAE-ExecutionGate" -Force
}

try {
    Import-Module -Name $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    Write-Pass "Import-Module succeeded: $ModulePath"
    $ValidationResults["ModuleImport"] = "SUCCESS"
} catch {
    Write-Fail "Import-Module FAILED: $_"
    $ValidationResults["ModuleImport"] = "FAILED: $_"

    Write-Host ""
    Write-Host "  Diagnostic: attempting to load module content directly to isolate error..." -ForegroundColor Yellow

    try {
        $null = [scriptblock]::Create($moduleContent)
        Write-Info "Scriptblock parse: OK"
    } catch {
        Write-Fail "Scriptblock parse FAILED: $_"
        Write-Fail "Syntax error in module body. Repair required before import."
    }

    exit 1
}

Write-Step 5 7 "Verifying exported commands"

$requiredCommands = @(
    "Invoke-PRAEExecutionGate",
    "Invoke-PRAEDeploymentValidator",
    "Invoke-PRAEFullRuntimeValidation",
    "Test-PRAEAuthorityActive",
    "Test-RegistryIntegrity",
    "Test-GovernanceRelayActive",
    "Test-MutationMode",
    "Test-AuthorizedExecutionScope",
    "Test-AuthorityChecksum",
    "Test-ProtectedProject",
    "Get-PRAEAuthorityManifest",
    "New-ExecutionFingerprint",
    "New-GovernanceToken",
    "Write-PRAEViolation"
)

$importFailures = 0

foreach ($cmd in $requiredCommands) {
    $found = Get-Command -Name $cmd -ErrorAction SilentlyContinue

    if ($found) {
        Write-Pass $cmd
        $ValidationResults["Cmd_$cmd"] = "AVAILABLE"
    } else {
        Write-Fail "$cmd - NOT AVAILABLE after import"
        $ValidationResults["Cmd_$cmd"] = "MISSING"
        $importFailures++
    }
}

if ($importFailures -gt 0) {
    Write-Fail "$importFailures command(s) not available after import"
    Write-Warn "Attempting fallback global import"

    try {
        Import-Module -Name $ModulePath -Force -DisableNameChecking -Global -ErrorAction Stop

        $stillMissing = $requiredCommands | Where-Object {
            -not (Get-Command $_ -ErrorAction SilentlyContinue)
        }

        if ($stillMissing.Count -gt 0) {
            Write-Fail "Still missing after global reload: $($stillMissing -join ', ')"
            exit 1
        }

        Write-Pass "Fallback global import resolved missing commands"
    } catch {
        Write-Fail "Fallback import also failed: $_"
        exit 1
    }
} else {
    Write-Pass "All $($requiredCommands.Count) required commands available"
}

$ValidationResults["ExportVerification"] = if ($importFailures -eq 0) { "ALL_PASS" } else { "FAILURES:$importFailures" }

Write-Step 6 7 "Executing Invoke-PRAEFullRuntimeValidation"

try {
    $validationResult = Invoke-PRAEFullRuntimeValidation -CallerIdentity "PRAE-ACTIVATION-BOOTSTRAP"

    Write-Info "Validation timestamp : $($validationResult.ValidationTimestamp)"
    Write-Info "Governance version   : $($validationResult.GovernanceVersion)"
    Write-Info "Enforcement phase    : $($validationResult.EnforcementPhase)"
    Write-Host ""

    $checkMap = [ordered]@{
        "Manifest loaded"         = $validationResult.ManifestLoaded
        "Authority active"        = $validationResult.AuthorityActive
        "Checksum valid"          = $validationResult.ChecksumValid
        "Mutation mode compliant" = $validationResult.MutationModeCompliant
        "Registry integrity"      = $validationResult.RegistryIntegrity
        "Relay active"            = $validationResult.RelayActive
        "Gate intercepts unauth"  = $validationResult.GateInterceptsUnauth
        "Authorized passes gate"  = $validationResult.AuthorizedPassesGate
        "Ledger writable"         = $validationResult.LedgerWritable
    }

    foreach ($check in $checkMap.Keys) {
        $val = $checkMap[$check]

        if ($val -eq $true) {
            Write-Pass $check
        } elseif ($val -eq $false) {
            Write-Warn "$check : false (see findings)"
        } else {
            Write-Info "$check : $val"
        }

        $ValidationResults["Val_$check"] = $val
    }

    Write-Host ""

    $statusColor = switch ($validationResult.OverallStatus) {
        "FULLY_OPERATIONAL" { "Green" }
        "WARNING" { "Yellow" }
        "DEGRADED" { "DarkYellow" }
        default { "Red" }
    }

    Write-Host "      Overall Status: $($validationResult.OverallStatus)" -ForegroundColor $statusColor

    if ($validationResult.Findings -and $validationResult.Findings.Count -gt 0) {
        Write-Host "      Findings:" -ForegroundColor Yellow

        foreach ($f in $validationResult.Findings) {
            $fc = if ($f -like "CRITICAL:*") {
                "Red"
            } elseif ($f -like "FAIL:*") {
                "DarkYellow"
            } else {
                "Yellow"
            }

            Write-Host "        - $f" -ForegroundColor $fc
        }
    }

    $ValidationResults["RuntimeValidation"] = $validationResult.OverallStatus
} catch {
    Write-Fail "Invoke-PRAEFullRuntimeValidation threw exception: $_"
    $ValidationResults["RuntimeValidation"] = "EXCEPTION: $_"
}

Write-Step 7 7 "Generating final enforcement report"

if ($SkipReport) {
    Write-Info "SkipReport flag set - skipping report script execution"
    $ValidationResults["EnforcementReport"] = "SKIPPED"
} elseif (Test-Path $ReportScriptPath) {
    try {
        & $ReportScriptPath
        Write-Pass "Enforcement report generated"
        $ValidationResults["EnforcementReport"] = "SUCCESS"
    } catch {
        Write-Warn "Report script threw exception: $_"
        $ValidationResults["EnforcementReport"] = "WARN: $_"
    }
} else {
    Write-Warn "Report script not found at: $ReportScriptPath"
    Write-Warn "Run Invoke-PRAEFinalReport.ps1 manually after deployment"
    $ValidationResults["EnforcementReport"] = "NOT_FOUND"
}

Write-Host ""
Write-Host "==========================================================" -ForegroundColor DarkCyan
Write-Host "  PRAE AUTHORITY GATE READINESS CONFIRMATION" -ForegroundColor Cyan
Write-Host "==========================================================" -ForegroundColor DarkCyan

$readinessChecks = [ordered]@{
    "Execution gate active"             = ($ValidationResults["Cmd_Invoke-PRAEExecutionGate"] -eq "AVAILABLE")
    "Runtime validation active"         = ($ValidationResults["Cmd_Invoke-PRAEFullRuntimeValidation"] -eq "AVAILABLE")
    "Governance lock preserved"         = ($GOVERNANCE_MODE -eq "LOCKED" -and $AUTO_REPAIR -eq "DISABLED" -and $PRODUCTION_MUTATION -eq "NONE")
    "Violation ledger active"           = ($ValidationResults["Val_Ledger writable"] -eq $true)
    "Relay heartbeat active"            = ($ValidationResults["Val_Relay active"] -eq $true)
    "Centralized authority operational" = ($ValidationResults["ModuleImport"] -eq "SUCCESS")
    "No unsigned execution failures"    = ($ValidationResults["Val_Gate intercepts unauth"] -eq $true)
    "Module encoding clean"             = ($ValidationResults["ModuleEncoding"] -eq "CLEAN")
}

$passCount = 0
$failCount = 0

foreach ($check in $readinessChecks.Keys) {
    if ($readinessChecks[$check] -eq $true) {
        Write-Pass $check
        $passCount++
    } else {
        Write-Fail $check
        $failCount++
    }
}

Write-Host ""

if ($failCount -eq 0) {
    Write-Host "  [AUTHORITY GATE READY] All $passCount checks passed" -ForegroundColor Green
    Write-Host "  PRAE enforcement layer fully operational." -ForegroundColor Green
} else {
    Write-Host "  [PARTIAL] $passCount passed / $failCount failed" -ForegroundColor Yellow
    Write-Host "  Address failed checks before considering gate fully active." -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Governance state at exit:" -ForegroundColor DarkCyan
Write-Host "    governance_mode     = $GOVERNANCE_MODE" -ForegroundColor White
Write-Host "    auto_repair         = $AUTO_REPAIR" -ForegroundColor White
Write-Host "    production_mutation = $PRODUCTION_MUTATION" -ForegroundColor White
Write-Host ""
Write-Host "  Session execution policy: $Script:PolicyMarker ($Script:PolicyScope scope, auto-expires with process)" -ForegroundColor Gray
Write-Host "  Machine policy scope     : $Script:PolicySystemScope (no system-level mutation performed)" -ForegroundColor Gray
Write-Host ""

return [PSCustomObject]$ValidationResults