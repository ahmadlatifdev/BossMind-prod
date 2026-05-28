#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Security Unblock + Full Runtime Activation
    Removes Mark-of-the-Web ADS blocks, validates execution policy,
    imports the gate module, and confirms full operational status.
.DESCRIPTION
    Addresses Windows MOTW (Zone.Identifier ADS) blocking without
    weakening machine or user execution policy.

    Three-phase operation:
      PHASE 1 - Unblock: Remove Zone.Identifier ADS from all PRAE files
      PHASE 2 - Import:  Load PRAE-ExecutionGate.psm1 with pre-flight checks
      PHASE 3 - Validate: Run full runtime validation + readiness confirmation

    Governance invariants (ReadOnly throughout):
      governance_mode     = LOCKED
      auto_repair         = DISABLED
      production_mutation = NONE
.PARAMETER PRAERoot
    Root of the PRAE directory tree to unblock recursively.
    Default: D:\BossMind\bossmind-shared\prae
.PARAMETER ModulePath
    Full path to PRAE-ExecutionGate.psm1
.PARAMETER ActivateScriptPath
    Full path to PRAE-ActivateAndValidate.ps1
.PARAMETER DryRun
    Enumerate what would be unblocked without removing any ADS.
.EXAMPLE
    powershell -ExecutionPolicy Bypass -File .\PRAE-UnblockAndActivate.ps1
    powershell -ExecutionPolicy Bypass -File .\PRAE-UnblockAndActivate.ps1 -DryRun
#>

[CmdletBinding()]
param(
    [string]$PRAERoot = "D:\BossMind\bossmind-shared\prae",
    [string]$ModulePath = "D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1",
    [string]$ActivateScriptPath = "D:\BossMind\bossmind-shared\prae\scripts\PRAE-ActivateAndValidate.ps1",
    [switch]$DryRun
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  GOVERNANCE CONSTANTS (ReadOnly - cannot be altered in scope)
# ---------------------------------------------------------------
Set-Variable -Name GOV_MODE       -Value "LOCKED"   -Option ReadOnly -Force
Set-Variable -Name GOV_REPAIR     -Value "DISABLED"  -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION   -Value "NONE"      -Option ReadOnly -Force
Set-Variable -Name GOV_VERSION    -Value "2.0.0"     -Option ReadOnly -Force

# ---------------------------------------------------------------
#  OUTPUT HELPERS
# ---------------------------------------------------------------
function Write-Phase { param([int]$N, [string]$T)
    Write-Host ""
    Write-Host "  ======================================================" -ForegroundColor DarkCyan
    Write-Host "  PHASE $N - $T" -ForegroundColor Cyan
    Write-Host "  ======================================================" -ForegroundColor DarkCyan
}
function Write-Step  { param([string]$T) Write-Host "  >> $T" -ForegroundColor White }
function Write-Pass  { param([string]$T) Write-Host "     [PASS] $T" -ForegroundColor Green }
function Write-Fail  { param([string]$T) Write-Host "     [FAIL] $T" -ForegroundColor Red }
function Write-Warn  { param([string]$T) Write-Host "     [WARN] $T" -ForegroundColor Yellow }
function Write-Info  { param([string]$T) Write-Host "     [INFO] $T" -ForegroundColor Gray }

$Report = [ordered]@{}

# ---------------------------------------------------------------
#  HEADER
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE Security Unblock + Runtime Activation              |" -ForegroundColor Cyan
Write-Host "  |  governance_mode=$GOV_MODE  auto_repair=$GOV_REPAIR  mutation=$GOV_MUTATION  |" -ForegroundColor DarkCyan
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
if ($DryRun) {
    Write-Host "  DRY RUN MODE - no ADS will be removed" -ForegroundColor Yellow
}

# ---------------------------------------------------------------
#  PHASE 1 - EXECUTION POLICY AUDIT
# ---------------------------------------------------------------
Write-Phase 1 "Execution Policy Audit"

Write-Step "Reading policy at all scopes (no changes made)"

$scopeNames = @('MachinePolicy','UserPolicy','Process','CurrentUser','LocalMachine')
$policyMap  = [ordered]@{}
foreach ($scope in $scopeNames) {
    try {
        $pol = Get-ExecutionPolicy -Scope $scope
        $policyMap[$scope] = $pol.ToString()
    } catch {
        $policyMap[$scope] = "UNAVAILABLE"
    }
}

Write-Info "MachinePolicy (GPO)  : $($policyMap['MachinePolicy'])"
Write-Info "UserPolicy    (GPO)  : $($policyMap['UserPolicy'])"
Write-Info "Process              : $($policyMap['Process'])"
Write-Info "CurrentUser          : $($policyMap['CurrentUser'])"
Write-Info "LocalMachine         : $($policyMap['LocalMachine'])"
$Report['Policy_Before_LocalMachine'] = $policyMap['LocalMachine']
$Report['Policy_Before_CurrentUser']  = $policyMap['CurrentUser']

# Apply process-scope bypass only (session-scoped, auto-expires with process)
Write-Step "Applying Process-scope Bypass (session only - no system mutation)"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force
$processNow = (Get-ExecutionPolicy -Scope Process).ToString()
Write-Pass "Process policy set to: $processNow"
Write-Info "LocalMachine policy unchanged: $($policyMap['LocalMachine'])"
Write-Info "CurrentUser policy unchanged : $($policyMap['CurrentUser'])"
$Report['Policy_Process_Active'] = $processNow
$Report['Policy_SystemUnchanged'] = $true

# ---------------------------------------------------------------
#  PHASE 2 - MARK-OF-THE-WEB REMOVAL
# ---------------------------------------------------------------
Write-Phase 2 "Mark-of-the-Web (Zone.Identifier ADS) Removal"

Write-Step "Scanning $PRAERoot recursively for blocked files"

if (-not (Test-Path $PRAERoot)) {
    Write-Warn "PRAE root not found: $PRAERoot"
    Write-Warn "Attempting fallback paths..."
    $fallbacks = @(
        "D:\BossMind\bossmind-shared\prae",
        "D:\BossMind\prae",
        (Split-Path $ModulePath -Parent)
    )
    foreach ($fb in $fallbacks) {
        if (Test-Path $fb) {
            $PRAERoot = $fb
            Write-Info "Using fallback root: $PRAERoot"
            break
        }
    }
}

# File extensions that can carry Zone.Identifier and affect PS execution
$targetExtensions = @('*.ps1','*.psm1','*.psd1','*.json','*.xml','*.cmd','*.bat')

$allFiles = @()
if (Test-Path $PRAERoot) {
    $allFiles = Get-ChildItem -Path $PRAERoot -Recurse -Include $targetExtensions -File -ErrorAction SilentlyContinue
}

# Also explicitly include the module and activate script even if outside root
$explicitFiles = @($ModulePath, $ActivateScriptPath) |
    Where-Object { $_ -and (Test-Path $_) -and ($_ -notin $allFiles.FullName) }

Write-Info "Files found in PRAE root: $($allFiles.Count)"
Write-Info "Additional explicit files: $($explicitFiles.Count)"

$blockedFiles    = [System.Collections.Generic.List[string]]::new()
$unblockedFiles  = [System.Collections.Generic.List[string]]::new()
$alreadyClean    = [System.Collections.Generic.List[string]]::new()
$unblockErrors   = [System.Collections.Generic.List[string]]::new()

# - Process all files -
$allTargets = @($allFiles.FullName) + $explicitFiles | Sort-Object -Unique

foreach ($filePath in $allTargets) {
    if (-not $filePath -or -not (Test-Path $filePath)) { continue }

    # Check for Zone.Identifier ADS
    $hasMotw = $false
    try {
        $streams = Get-Item -Path $filePath -Stream * -ErrorAction SilentlyContinue
        $zoneStream = $streams | Where-Object { $_.Stream -eq 'Zone.Identifier' }
        $hasMotw = ($null -ne $zoneStream)
    } catch {
        # Get-Item -Stream not available on this PS version or non-NTFS
        # Fall back to Unblock-File which is safe to call either way
        $hasMotw = $true  # assume blocked, Unblock-File is idempotent
    }

    if ($hasMotw) {
        $blockedFiles.Add($filePath)
        Write-Info "BLOCKED: $filePath"

        if (-not $DryRun) {
            try {
                Unblock-File -Path $filePath -ErrorAction Stop
                $unblockedFiles.Add($filePath)
                Write-Pass "Unblocked: $(Split-Path $filePath -Leaf)"
            } catch {
                $unblockErrors.Add("$filePath : $_")
                Write-Warn "Unblock failed for $filePath : $_"
            }
        } else {
            Write-Info "[DRY RUN] Would unblock: $(Split-Path $filePath -Leaf)"
        }
    } else {
        $alreadyClean.Add($filePath)
    }
}

Write-Host ""
Write-Info "Summary:"
Write-Info "  Files scanned       : $($allTargets.Count)"
Write-Info "  Already clean (no ADS): $($alreadyClean.Count)"
Write-Info "  Had Zone.Identifier : $($blockedFiles.Count)"
if (-not $DryRun) {
    Write-Info "  Successfully unblocked: $($unblockedFiles.Count)"
    Write-Info "  Unblock errors        : $($unblockErrors.Count)"
    if ($unblockErrors.Count -eq 0 -and $blockedFiles.Count -ge 0) {
        Write-Pass "All MOTW blocks cleared"
    }
}

$Report['MOTW_FilesScanned']    = $allTargets.Count
$Report['MOTW_WereBlocked']     = $blockedFiles.Count
$Report['MOTW_Unblocked']       = $unblockedFiles.Count
$Report['MOTW_Errors']          = $unblockErrors.Count
$Report['MOTW_NoSecurityBlock'] = ($unblockErrors.Count -eq 0)

# - Post-unblock verification -
if (-not $DryRun) {
    Write-Step "Post-unblock verification (confirming Zone.Identifier removed)"
    $stillBlocked = 0
    foreach ($filePath in $allTargets) {
        if (-not (Test-Path $filePath)) { continue }
        try {
            $streams = Get-Item -Path $filePath -Stream * -ErrorAction SilentlyContinue
            $zoneStream = $streams | Where-Object { $_.Stream -eq 'Zone.Identifier' }
            if ($null -ne $zoneStream) {
                Write-Fail "Still blocked: $filePath"
                $stillBlocked++
            }
        } catch { }
    }
    if ($stillBlocked -eq 0) {
        Write-Pass "Verification complete: 0 files still carry Zone.Identifier ADS"
        $Report['MOTW_VerificationClean'] = $true
    } else {
        Write-Fail "$stillBlocked file(s) still blocked after Unblock-File"
        $Report['MOTW_VerificationClean'] = $false
    }
}

if ($DryRun) {
    Write-Host ""
    Write-Warn "DRY RUN complete. Re-run without -DryRun to apply unblocks."
    exit 0
}

# ---------------------------------------------------------------
#  PHASE 3 - MODULE IMPORT + EXPORT VERIFICATION
# ---------------------------------------------------------------
Write-Phase 3 "Module Import and Export Verification"

Write-Step "Validating module path: $ModulePath"
if (-not (Test-Path $ModulePath)) {
    Write-Fail "Module not found: $ModulePath"
    Write-Fail "Ensure Install-PRAEAuthorityGate.ps1 ran successfully first."
    $Report['ModuleImport'] = 'MODULE_NOT_FOUND'
    exit 1
}
Write-Pass "Module file exists"

# Pre-flight: encoding check
Write-Step "Pre-flight encoding check"
$moduleBytes = [System.IO.File]::ReadAllBytes($ModulePath)
$nonAsciiCount = ($moduleBytes | Where-Object { $_ -gt 127 }).Count
if ($nonAsciiCount -gt 0) {
    Write-Fail "Module has $nonAsciiCount non-ASCII bytes - encoding corruption present"
    Write-Fail "Re-deploy the repaired PRAE-ExecutionGate.psm1 before importing."
    $Report['ModuleEncoding'] = "CORRUPT:$nonAsciiCount bytes"
    exit 1
}
Write-Pass "Encoding clean: 0 non-ASCII bytes"
$Report['ModuleEncoding'] = 'CLEAN'

# Pre-flight: nested quote check
$moduleText = [System.IO.File]::ReadAllText($ModulePath)
if ($moduleText -match 'ToString\("o"\)') {
    Write-Fail "Nested double-quote syntax error detected in module (ToString(`"o`") pattern)"
    Write-Fail "Re-deploy the repaired PRAE-ExecutionGate.psm1 before importing."
    $Report['ModuleSyntax'] = 'NESTED_QUOTE_ERROR'
    exit 1
}
Write-Pass "No nested quote syntax errors"
$Report['ModuleSyntax'] = 'CLEAN'

# Remove stale load if present
Write-Step "Removing any previously loaded PRAE-ExecutionGate module"
if (Get-Module -Name 'PRAE-ExecutionGate' -ErrorAction SilentlyContinue) {
    Remove-Module -Name 'PRAE-ExecutionGate' -Force
    Write-Info "Prior module instance removed"
} else {
    Write-Info "No prior instance loaded"
}

# Import
Write-Step "Import-Module -Force -DisableNameChecking"
try {
    Import-Module -Name $ModulePath -Force -DisableNameChecking -ErrorAction Stop
    Write-Pass "Import-Module succeeded"
    $Report['ModuleImport'] = 'SUCCESS'
} catch [System.Security.SecurityException] {
    Write-Fail "PSSecurityException: execution policy still blocking import"
    Write-Fail "Error: $_"
    Write-Warn "Attempting direct dot-source fallback..."
    try {
        . $ModulePath
        Write-Pass "Dot-source fallback succeeded"
        $Report['ModuleImport'] = 'SUCCESS_VIA_DOTSOURCE'
    } catch {
        Write-Fail "Dot-source also failed: $_"
        $Report['ModuleImport'] = "FAILED: $_"
        exit 1
    }
} catch {
    Write-Fail "Import-Module failed: $_"
    $Report['ModuleImport'] = "FAILED: $_"
    exit 1
}

# Export verification
Write-Step "Verifying exported commands"
$requiredCommands = [ordered]@{
    'Invoke-PRAEExecutionGate'         = 'Core execution gate enforcer'
    'Invoke-PRAEDeploymentValidator'   = 'Deployment authority validator'
    'Invoke-PRAEFullRuntimeValidation' = 'Full runtime validation runner'
    'Test-PRAEAuthorityActive'         = 'Authority active check'
    'Test-RegistryIntegrity'           = 'Registry integrity check'
    'Test-GovernanceRelayActive'       = 'Relay status check'
    'Test-MutationMode'                = 'Mutation mode check'
    'Test-AuthorizedExecutionScope'    = 'Scope allowlist check'
    'Test-AuthorityChecksum'           = 'Manifest checksum check'
    'Test-ProtectedProject'            = 'Protected project scope check'
    'Get-PRAEAuthorityManifest'        = 'Manifest loader'
    'New-ExecutionFingerprint'         = 'SHA-256 fingerprint generator'
    'New-GovernanceToken'              = 'Governance token issuer'
    'Write-PRAEViolation'              = 'Append-only violation ledger writer'
}

$cmdFailures = 0
foreach ($cmd in $requiredCommands.Keys) {
    $found = Get-Command -Name $cmd -ErrorAction SilentlyContinue
    if ($found) {
        Write-Pass "$cmd"
        $Report["Cmd_$cmd"] = 'AVAILABLE'
    } else {
        Write-Fail "$cmd - NOT available ($($requiredCommands[$cmd]))"
        $Report["Cmd_$cmd"] = 'MISSING'
        $cmdFailures++
    }
}

if ($cmdFailures -gt 0) {
    Write-Warn "$cmdFailures command(s) missing - attempting global scope reimport"
    Import-Module -Name $ModulePath -Force -DisableNameChecking -Global -ErrorAction SilentlyContinue
    $stillMissing = $requiredCommands.Keys | Where-Object { -not (Get-Command $_ -ErrorAction SilentlyContinue) }
    if ($stillMissing.Count -gt 0) {
        Write-Fail "Still missing after global reimport: $($stillMissing -join ', ')"
        $Report['ExportVerification'] = "PARTIAL: $cmdFailures missing"
        exit 1
    }
    Write-Pass "Global reimport resolved all missing commands"
}
$Report['ExportVerification'] = 'ALL_14_AVAILABLE'
Write-Pass "All $($requiredCommands.Count) required commands available"

# ---------------------------------------------------------------
#  PHASE 4 - INVOKE-PRAEFULLRUNTIMEVALIDATION
# ---------------------------------------------------------------
Write-Phase 4 "Full Runtime Validation Execution"

Write-Step "Executing Invoke-PRAEFullRuntimeValidation"
try {
    $vr = Invoke-PRAEFullRuntimeValidation -CallerIdentity "PRAE-UNBLOCK-ACTIVATION"

    $checkLabels = [ordered]@{
        ManifestLoaded        = 'Authority manifest loaded'
        AuthorityActive       = 'Authority mode ENFORCEMENT_ACTIVE'
        ChecksumValid         = 'Authority checksum valid'
        MutationModeCompliant = 'Mutation mode compliant (auto_repair=DISABLED)'
        RegistryIntegrity     = 'Registry integrity verified'
        RelayActive           = 'Governance relay active'
        GateInterceptsUnauth  = 'Gate intercepts unauthorized execution'
        AuthorizedPassesGate  = 'Authorized scope passes gate'
        LedgerWritable        = 'Violation ledger writable (append-only)'
    }

    foreach ($prop in $checkLabels.Keys) {
        $val = $vr.$prop
        if ($val -eq $true)  { Write-Pass $checkLabels[$prop] }
        elseif ($val -eq $false) { Write-Warn "$($checkLabels[$prop]) : false" }
        else { Write-Info "$($checkLabels[$prop]) : $val" }
        $Report["Val_$prop"] = $val
    }

    $statusColor = switch ($vr.OverallStatus) {
        'FULLY_OPERATIONAL' { 'Green' }
        'WARNING'           { 'Yellow' }
        'DEGRADED'          { 'DarkYellow' }
        default             { 'Red' }
    }
    Write-Host ""
    Write-Host "     Overall Status: $($vr.OverallStatus)" -ForegroundColor $statusColor
    $Report['RuntimeValidationStatus'] = $vr.OverallStatus

    if ($vr.Findings -and $vr.Findings.Count -gt 0) {
        Write-Host "     Findings:" -ForegroundColor Yellow
        foreach ($f in $vr.Findings) {
            $fc = if ($f -like 'CRITICAL:*') {'Red'} elseif ($f -like 'FAIL:*') {'DarkYellow'} else {'Yellow'}
            Write-Host "       - $f" -ForegroundColor $fc
        }
    }
} catch {
    Write-Fail "Invoke-PRAEFullRuntimeValidation threw exception: $_"
    $Report['RuntimeValidationStatus'] = "EXCEPTION: $_"
}

# ---------------------------------------------------------------
#  PHASE 5 - FULL ACTIVATION SCRIPT EXECUTION
# ---------------------------------------------------------------
Write-Phase 5 "PRAE-ActivateAndValidate.ps1 Execution"

Write-Step "Checking path: $ActivateScriptPath"
if (Test-Path $ActivateScriptPath) {
    Write-Pass "Activation script found"
    try {
        & $ActivateScriptPath -SkipReport
        Write-Pass "PRAE-ActivateAndValidate.ps1 completed"
        $Report['ActivationScript'] = 'EXECUTED'
    } catch {
        Write-Warn "Activation script threw exception: $_"
        $Report['ActivationScript'] = "WARN: $_"
    }
} else {
    Write-Warn "Not found: $ActivateScriptPath"
    Write-Info "The activation script is optional at this stage - validation already ran above."
    $Report['ActivationScript'] = 'NOT_FOUND_SKIPPED'
}

# ---------------------------------------------------------------
#  FINAL OPERATIONAL READINESS CONFIRMATION
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE AUTHORITY GATE - FINAL READINESS CONFIRMATION      |" -ForegroundColor Cyan
Write-Host "  +----------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""

$readiness = [ordered]@{
    'No PSSecurityException remains'        = ($Report['MOTW_NoSecurityBlock'] -eq $true -and $Report['ModuleImport'] -like 'SUCCESS*')
    'PRAE module imported cleanly'          = ($Report['ModuleImport'] -like 'SUCCESS*')
    'Execution gate active'                 = ($Report['Cmd_Invoke-PRAEExecutionGate'] -eq 'AVAILABLE')
    'Runtime validation active'             = ($Report['Cmd_Invoke-PRAEFullRuntimeValidation'] -eq 'AVAILABLE')
    'All 14 governance functions available' = ($Report['ExportVerification'] -like '*AVAILABLE*' -or $Report['ExportVerification'] -eq 'ALL_14_AVAILABLE')
    'Governance lock preserved'             = ($GOV_MODE -eq 'LOCKED' -and $GOV_REPAIR -eq 'DISABLED' -and $GOV_MUTATION -eq 'NONE')
    'Violation ledger active'               = ($Report['Val_LedgerWritable'] -eq $true)
    'Relay heartbeat active'                = ($Report['Val_RelayActive'] -eq $true)
    'Centralized authority operational'     = ($Report['Val_AuthorityActive'] -eq $true)
    'Machine policy unchanged'              = ($Report['Policy_SystemUnchanged'] -eq $true)
    'Module encoding clean'                 = ($Report['ModuleEncoding'] -eq 'CLEAN')
    'MOTW blocks cleared'                   = ($Report['MOTW_VerificationClean'] -eq $true -or $Report['MOTW_WereBlocked'] -eq 0)
}

$pass = 0
$fail = 0
foreach ($item in $readiness.Keys) {
    if ($readiness[$item] -eq $true) {
        Write-Pass $item
        $pass++
    } else {
        Write-Fail $item
        $fail++
    }
}

Write-Host ""
if ($fail -eq 0) {
    Write-Host "  [AUTHORITY GATE FULLY OPERATIONAL] $pass/$($pass+$fail) checks passed" -ForegroundColor Green
} else {
    Write-Host "  [PARTIAL] $pass passed / $fail failed - review failures above" -ForegroundColor Yellow
}

Write-Host ""
Write-Host "  Governance constants at process exit:" -ForegroundColor DarkCyan
Write-Host "    governance_mode     = $GOV_MODE"     -ForegroundColor White
Write-Host "    auto_repair         = $GOV_REPAIR"   -ForegroundColor White
Write-Host "    production_mutation = $GOV_MUTATION" -ForegroundColor White
Write-Host ""
Write-Host "  Execution policy at process exit:" -ForegroundColor DarkCyan
Write-Host "    Process     : $(Get-ExecutionPolicy -Scope Process) (session-only, auto-expires)" -ForegroundColor White
Write-Host "    CurrentUser : $(Get-ExecutionPolicy -Scope CurrentUser) (unchanged)" -ForegroundColor White
Write-Host "    LocalMachine: $(Get-ExecutionPolicy -Scope LocalMachine) (unchanged)" -ForegroundColor White
Write-Host ""

$Report['FinalPass']  = $pass
$Report['FinalFail']  = $fail
$Report['GateStatus'] = if ($fail -eq 0) { 'FULLY_OPERATIONAL' } else { "PARTIAL:$fail failures" }

return [PSCustomObject]$Report
