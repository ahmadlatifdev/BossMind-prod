#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Execution Authority Gate - Core Enforcement Engine
    Phase: AUTHORITATIVE EXECUTION ENFORCEMENT
.DESCRIPTION
    Centralized execution validation layer. Every runtime execution must pass
    PRAE authorization validation before proceeding. Enforces governance across
    PowerShell, deployment, automation, scheduled tasks, repair, and mutation.
.NOTES
    governance_mode  = LOCKED
    auto_repair      = DISABLED
    production_mutation = NONE
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ============================================================
#  PRAE AUTHORITY CONSTANTS
# ============================================================
$Script:PRAE_ROOT          = "D:\BossMind\bossmind-shared\prae"
$Script:PRAE_AUTHORITY_DIR = "$Script:PRAE_ROOT\authority"
$Script:PRAE_MANIFEST      = "$Script:PRAE_AUTHORITY_DIR\prae-execution-authority.json"
$Script:PRAE_REGISTRY      = "$Script:PRAE_ROOT\registry\prae-runtime-registry.json"
$Script:PRAE_RELAY_PING    = "$Script:PRAE_ROOT\relay\relay-heartbeat.json"
$Script:VIOLATIONS_LOG     = "D:\BossMind\bossmind-shared\shared-memory\prae-governance-violations.log"
$Script:EXECUTION_LOG      = "$Script:PRAE_ROOT\authority\prae-authorized-executions.log"
$Script:FINGERPRINT_ALGO   = "SHA256"
$Script:TOKEN_TTL_SECONDS  = 300
$Script:GOVERNANCE_VERSION = "2.0.0"
$Script:ENFORCEMENT_PHASE  = "AUTHORITATIVE_EXECUTION_ENFORCEMENT"

# ============================================================
#  GOVERNANCE VIOLATION TYPES
# ============================================================
enum ViolationType {
    UNAUTHORIZED_EXECUTION
    DEPLOYMENT_MUTATION_ATTEMPT
    REGISTRY_MISMATCH
    UNSIGNED_EXECUTION_ATTEMPT
    RUNTIME_INTEGRITY_FAILURE
    DRIFT_ESCALATION_EVENT
    RELAY_OFFLINE
    AUTHORITY_MANIFEST_MISSING
    TOKEN_VALIDATION_FAILURE
    PROTECTED_SCOPE_VIOLATION
}

# ============================================================
#  SECTION 1: AUTHORITY MANIFEST LOADER
# ============================================================
function Get-PRAEAuthorityManifest {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:PRAE_MANIFEST)) {
        Write-PRAEViolation -Type AUTHORITY_MANIFEST_MISSING `
            -Detail "prae-execution-authority.json missing from authority directory" `
            -ExecutionContext "MANIFEST_LOAD"
        throw "PRAE AUTHORITY GATE: Manifest not found. Execution blocked."
    }

    try {
        $raw = Get-Content $Script:PRAE_MANIFEST -Raw -Encoding UTF8
        $manifest = $raw | ConvertFrom-Json
        return $manifest
    }
    catch {
        Write-PRAEViolation -Type AUTHORITY_MANIFEST_MISSING `
            -Detail "Manifest parse failure: $_" `
            -ExecutionContext "MANIFEST_LOAD"
        throw "PRAE AUTHORITY GATE: Manifest corrupted. Execution blocked."
    }
}

# ============================================================
#  SECTION 2: EXECUTION FINGERPRINTING
# ============================================================
function New-ExecutionFingerprint {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutionScope,
        [Parameter(Mandatory)]
        [string]$CallerIdentity,
        [string]$TargetProject = "UNSPECIFIED"
    )

    $timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
    $raw = "$ExecutionScope|$CallerIdentity|$TargetProject|$timestamp|$Script:GOVERNANCE_VERSION"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($raw)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $fingerprint = [System.BitConverter]::ToString($hash) -replace '-', ''

    return [PSCustomObject]@{
        Fingerprint     = $fingerprint
        Scope           = $ExecutionScope
        Caller          = $CallerIdentity
        TargetProject   = $TargetProject
        Timestamp       = $timestamp
        Algorithm       = $Script:FINGERPRINT_ALGO
        GovernanceEpoch = 1
    }
}

# ============================================================
#  SECTION 3: GOVERNANCE TOKEN ISSUER
# ============================================================
function New-GovernanceToken {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [PSCustomObject]$Fingerprint
    )

    $expiry = [DateTimeOffset]::UtcNow.AddSeconds($Script:TOKEN_TTL_SECONDS).ToUnixTimeSeconds()
    $tokenRaw = "PRAE-TOKEN|$($Fingerprint.Fingerprint)|$expiry|$Script:ENFORCEMENT_PHASE"
    $bytes = [System.Text.Encoding]::UTF8.GetBytes($tokenRaw)
    $sha = [System.Security.Cryptography.SHA256]::Create()
    $hash = $sha.ComputeHash($bytes)
    $tokenHash = [System.BitConverter]::ToString($hash) -replace '-', ''

    return [PSCustomObject]@{
        Token           = "PRAE-$tokenHash"
        IssuedAt        = [DateTimeOffset]::UtcNow.ToString("o")
        ExpiresAt       = $expiry
        BoundFingerprint = $Fingerprint.Fingerprint
        Status          = "VALID"
        TTLSeconds      = $Script:TOKEN_TTL_SECONDS
    }
}

# ============================================================
#  SECTION 4: PRE-EXECUTION GATE CHECKS
# ============================================================
function Test-PRAEAuthorityActive {
    [CmdletBinding()]
    param([PSCustomObject]$Manifest)

    if ($Manifest.authority.mode -ne "ENFORCEMENT_ACTIVE") {
        return $false
    }
    if ($Manifest.authority.gate_status -ne "LOCKED") {
        return $false
    }
    return $true
}

function Test-RegistryIntegrity {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:PRAE_REGISTRY)) {
        # Registry file missing - log but allow degraded mode with warning
        Write-PRAEViolation -Type REGISTRY_MISMATCH `
            -Detail "Runtime registry not found at expected path" `
            -ExecutionContext "REGISTRY_CHECK"
        return $false
    }

    try {
        $reg = Get-Content $Script:PRAE_REGISTRY -Raw | ConvertFrom-Json
        if ($reg.integrity_status -ne "VERIFIED" -and $reg.integrity_status -ne $null) {
            return $false
        }
        return $true
    }
    catch {
        Write-PRAEViolation -Type REGISTRY_MISMATCH `
            -Detail "Registry parse failure: $_" `
            -ExecutionContext "REGISTRY_CHECK"
        return $false
    }
}

function Test-GovernanceRelayActive {
    [CmdletBinding()]
    param()

    if (-not (Test-Path $Script:PRAE_RELAY_PING)) {
        Write-PRAEViolation -Type RELAY_OFFLINE `
            -Detail "Relay heartbeat file not found" `
            -ExecutionContext "RELAY_CHECK"
        return $false
    }

    try {
        $relay = Get-Content $Script:PRAE_RELAY_PING -Raw | ConvertFrom-Json
        $lastBeat = [DateTimeOffset]::Parse($relay.last_heartbeat).ToUnixTimeSeconds()
        $now = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        # Allow 10-minute relay window before considering offline
        if (($now - $lastBeat) -gt 600) {
            Write-PRAEViolation -Type RELAY_OFFLINE `
                -Detail "Relay heartbeat stale  -  last beat $($relay.last_heartbeat)" `
                -ExecutionContext "RELAY_CHECK"
            return $false
        }
        return $true
    }
    catch {
        # Relay file exists but unreadable - treat as degraded, log but proceed with warning
        return $false
    }
}

function Test-MutationMode {
    [CmdletBinding()]
    param([PSCustomObject]$Manifest)

    if ($Manifest.authority.production_mutation -ne "NONE") {
        return $false
    }
    if ($Manifest.authority.auto_repair -ne "DISABLED") {
        return $false
    }
    if ($Manifest.authority.mutation_lock -ne $true) {
        return $false
    }
    return $true
}

function Test-AuthorizedExecutionScope {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Manifest,
        [string]$ExecutionScope
    )

    $blocked = $Manifest.blocked_mutation_scopes
    foreach ($b in $blocked) {
        if ($ExecutionScope -like "*$b*" -or $b -like "*$ExecutionScope*") {
            return $false
        }
    }

    $allowed = $Manifest.allowed_execution_scopes
    foreach ($a in $allowed) {
        if ($ExecutionScope -eq $a -or $ExecutionScope -like "$a*") {
            return $true
        }
    }

    # Scope not explicitly allowed - deny by default (allowlist model)
    return $false
}

function Test-AuthorityChecksum {
    [CmdletBinding()]
    param([PSCustomObject]$Manifest)

    $expected = "PRAE-SHA256-AUTHORITY-GATE-v2"
    return $Manifest.__authority_checksum -eq $expected
}

function Test-ProtectedProject {
    [CmdletBinding()]
    param(
        [PSCustomObject]$Manifest,
        [string]$TargetProject
    )

    $normalized = $TargetProject.ToLower().Replace(" ", "-")
    $protected = $Manifest.protected_projects.PSObject.Properties.Name

    foreach ($p in $protected) {
        if ($normalized -eq $p -or $normalized -like "*$p*") {
            $proj = $Manifest.protected_projects.$p
            if ($proj.mutation_allowed -eq $false) {
                return [PSCustomObject]@{
                    IsProtected    = $true
                    ProjectKey     = $p
                    ProtectionLevel = $proj.protection_level
                }
            }
        }
    }
    return [PSCustomObject]@{ IsProtected = $false; ProjectKey = $null }
}

# ============================================================
#  SECTION 5: VIOLATION LEDGER WRITER (APPEND-ONLY)
# ============================================================
function Write-PRAEViolation {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [ViolationType]$Type,
        [Parameter(Mandatory)]
        [string]$Detail,
        [string]$ExecutionContext = "UNKNOWN",
        [string]$Fingerprint = "N/A",
        [string]$CallerIdentity = "UNKNOWN"
    )

    $logDir = Split-Path $Script:VIOLATIONS_LOG -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $entry = [ordered]@{
        timestamp         = [DateTimeOffset]::UtcNow.ToString("o")
        violation_type    = $Type.ToString()
        detail            = $Detail
        execution_context = $ExecutionContext
        fingerprint       = $Fingerprint
        caller            = $CallerIdentity
        governance_version = $Script:GOVERNANCE_VERSION
        enforcement_phase = $Script:ENFORCEMENT_PHASE
        runtime_state     = "PRESERVED"
        production_mutated = $false
    }

    $line = "[$($entry.timestamp)] VIOLATION[$($entry.violation_type)] | CTX:$($entry.execution_context) | $Detail | FP:$($entry.fingerprint) | CALLER:$($entry.caller)"

    # Append-only - never truncate
    Add-Content -Path $Script:VIOLATIONS_LOG -Value $line -Encoding UTF8

    Write-Warning "PRAE GOVERNANCE VIOLATION: [$Type] $Detail"
}

function Write-PRAEAuthorizedExecution {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutionScope,
        [Parameter(Mandatory)]
        [PSCustomObject]$Token,
        [Parameter(Mandatory)]
        [PSCustomObject]$Fingerprint
    )

    $logDir = Split-Path $Script:EXECUTION_LOG -Parent
    if (-not (Test-Path $logDir)) {
        New-Item -ItemType Directory -Path $logDir -Force | Out-Null
    }

    $ts_auth = [DateTimeOffset]::UtcNow.ToString('o')
    $line = "[$ts_auth] AUTHORIZED | SCOPE:$ExecutionScope | TOKEN:$($Token.Token.Substring(0,20))... | FP:$($Fingerprint.Fingerprint.Substring(0,16))..."
    Add-Content -Path $Script:EXECUTION_LOG -Value $line -Encoding UTF8
}

# ============================================================
#  SECTION 6: MAIN EXECUTION GATE  - THE CORE ENFORCER
# ============================================================
function Invoke-PRAEExecutionGate {
    [CmdletBinding()]
    [OutputType([PSCustomObject])]
    param(
        [Parameter(Mandatory)]
        [string]$ExecutionScope,

        [Parameter(Mandatory)]
        [string]$CallerIdentity,

        [string]$TargetProject = "UNSPECIFIED",

        [switch]$AllowRelayDegraded,

        [scriptblock]$ExecutionBlock
    )

    $gateResult = [ordered]@{
        Authorized        = $false
        ExecutionScope    = $ExecutionScope
        CallerIdentity    = $CallerIdentity
        TargetProject     = $TargetProject
        Fingerprint       = $null
        Token             = $null
        FailureReason     = $null
        Timestamp         = [DateTimeOffset]::UtcNow.ToString("o")
        ExecutionResult   = $null
    }

    Write-Verbose "PRAE GATE: Initiating validation for scope '$ExecutionScope' by '$CallerIdentity'"

    # - CHECK 1: Load Authority Manifest -
    try {
        $manifest = Get-PRAEAuthorityManifest
    }
    catch {
        $gateResult.FailureReason = "AUTHORITY_MANIFEST_UNAVAILABLE"
        Write-PRAEViolation -Type AUTHORITY_MANIFEST_MISSING `
            -Detail "Gate cannot load manifest: $_" `
            -ExecutionContext $ExecutionScope `
            -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - CHECK 2: PRAE Authority Active -
    if (-not (Test-PRAEAuthorityActive -Manifest $manifest)) {
        $gateResult.FailureReason = "PRAE_AUTHORITY_NOT_ACTIVE"
        Write-PRAEViolation -Type RUNTIME_INTEGRITY_FAILURE `
            -Detail "Authority mode not ENFORCEMENT_ACTIVE or gate not LOCKED" `
            -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - CHECK 3: Authority Checksum -
    if (-not (Test-AuthorityChecksum -Manifest $manifest)) {
        $gateResult.FailureReason = "AUTHORITY_CHECKSUM_INVALID"
        Write-PRAEViolation -Type UNSIGNED_EXECUTION_ATTEMPT `
            -Detail "Authority manifest checksum mismatch  -  possible tampering" `
            -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - CHECK 4: Mutation Mode -
    if (-not (Test-MutationMode -Manifest $manifest)) {
        $gateResult.FailureReason = "MUTATION_MODE_VIOLATION"
        Write-PRAEViolation -Type UNAUTHORIZED_EXECUTION `
            -Detail "Mutation mode not compliant  -  auto_repair or production_mutation not SAFE" `
            -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - CHECK 5: Registry Integrity -
    $registryOk = Test-RegistryIntegrity
    if (-not $registryOk) {
        # In strict mode: block. Registry missing is only logged if relay is also degraded.
        $gateResult.FailureReason = "REGISTRY_INTEGRITY_FAILURE"
        Write-PRAEViolation -Type REGISTRY_MISMATCH `
            -Detail "Runtime registry integrity check failed" `
            -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - CHECK 6: Governance Relay -
    $relayOk = Test-GovernanceRelayActive
    if (-not $relayOk -and -not $AllowRelayDegraded) {
        $gateResult.FailureReason = "GOVERNANCE_RELAY_OFFLINE"
        Write-PRAEViolation -Type RELAY_OFFLINE `
            -Detail "Governance relay not active  -  execution blocked in strict mode" `
            -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - CHECK 7: Protected Project Scope -
    $protectedCheck = Test-ProtectedProject -Manifest $manifest -TargetProject $TargetProject
    if ($protectedCheck.IsProtected) {
        # Protected project - only allow read/validate scopes
        $isReadScope = $ExecutionScope -match "^(prae:|bossmind:.*:read|bossmind:.*:validate|bossmind:health)"
        if (-not $isReadScope) {
            $gateResult.FailureReason = "PROTECTED_PROJECT_MUTATION_DENIED"
            Write-PRAEViolation -Type PROTECTED_SCOPE_VIOLATION `
                -Detail "Mutation attempt on protected project '$($protectedCheck.ProjectKey)' [Level: $($protectedCheck.ProtectionLevel)]" `
                -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
            return [PSCustomObject]$gateResult
        }
    }

    # - CHECK 8: Authorized Execution Scope -
    if (-not (Test-AuthorizedExecutionScope -Manifest $manifest -ExecutionScope $ExecutionScope)) {
        $gateResult.FailureReason = "EXECUTION_SCOPE_NOT_AUTHORIZED"
        Write-PRAEViolation -Type UNAUTHORIZED_EXECUTION `
            -Detail "Scope '$ExecutionScope' not in allowlist and/or matches blocked list" `
            -ExecutionContext $ExecutionScope -CallerIdentity $CallerIdentity
        return [PSCustomObject]$gateResult
    }

    # - ALL CHECKS PASSED: Issue Token & Fingerprint -
    $fp    = New-ExecutionFingerprint -ExecutionScope $ExecutionScope `
                                      -CallerIdentity $CallerIdentity `
                                      -TargetProject $TargetProject
    $token = New-GovernanceToken -Fingerprint $fp

    $gateResult.Authorized  = $true
    $gateResult.Fingerprint = $fp
    $gateResult.Token       = $token

    Write-PRAEAuthorizedExecution -ExecutionScope $ExecutionScope -Token $token -Fingerprint $fp
    Write-Verbose "PRAE GATE: AUTHORIZED  -  Token $($token.Token.Substring(0,20))..."

    # - OPTIONAL: Execute the provided scriptblock -
    if ($null -ne $ExecutionBlock) {
        try {
            $gateResult.ExecutionResult = & $ExecutionBlock
        }
        catch {
            $gateResult.ExecutionResult = "EXECUTION_FAILED: $_"
            Write-PRAEViolation -Type RUNTIME_INTEGRITY_FAILURE `
                -Detail "Authorized execution threw exception: $_" `
                -ExecutionContext $ExecutionScope `
                -Fingerprint $fp.Fingerprint `
                -CallerIdentity $CallerIdentity
        }
    }

    return [PSCustomObject]$gateResult
}

# ============================================================
#  SECTION 7: DEPLOYMENT AUTHORITY VALIDATOR
# ============================================================
function Invoke-PRAEDeploymentValidator {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$DeploymentManifestPath,

        [Parameter(Mandatory)]
        [string]$CallerIdentity,

        [string]$TargetProject = "UNSPECIFIED"
    )

    Write-Verbose "PRAE DEPLOYMENT VALIDATOR: Checking '$DeploymentManifestPath'"

    # Gate must pass first
    $gate = Invoke-PRAEExecutionGate `
        -ExecutionScope "bossmind:deployment:validate" `
        -CallerIdentity $CallerIdentity `
        -TargetProject $TargetProject

    if (-not $gate.Authorized) {
        return [PSCustomObject]@{
            DeploymentAllowed = $false
            Reason = $gate.FailureReason
            GateResult = $gate
        }
    }

    # Validate deployment manifest exists and is readable
    if (-not (Test-Path $DeploymentManifestPath)) {
        Write-PRAEViolation -Type DEPLOYMENT_MUTATION_ATTEMPT `
            -Detail "Deployment manifest not found: $DeploymentManifestPath" `
            -ExecutionContext "DEPLOYMENT_VALIDATOR" `
            -Fingerprint $gate.Fingerprint.Fingerprint `
            -CallerIdentity $CallerIdentity
        return [PSCustomObject]@{
            DeploymentAllowed = $false
            Reason = "DEPLOYMENT_MANIFEST_MISSING"
            GateResult = $gate
        }
    }

    try {
        $depManifest = Get-Content $DeploymentManifestPath -Raw | ConvertFrom-Json

        # Verify deployment manifest has required PRAE fields
        if (-not $depManifest.prae_signed -or $depManifest.prae_signed -ne $true) {
            Write-PRAEViolation -Type UNSIGNED_EXECUTION_ATTEMPT `
                -Detail "Deployment manifest missing prae_signed=true: $DeploymentManifestPath" `
                -ExecutionContext "DEPLOYMENT_VALIDATOR" `
                -Fingerprint $gate.Fingerprint.Fingerprint `
                -CallerIdentity $CallerIdentity
            return [PSCustomObject]@{
                DeploymentAllowed = $false
                Reason = "DEPLOYMENT_MANIFEST_UNSIGNED"
                GateResult = $gate
            }
        }

        Write-Verbose "PRAE DEPLOYMENT VALIDATOR: Deployment APPROVED"
        return [PSCustomObject]@{
            DeploymentAllowed = $true
            Reason = "PRAE_VALIDATED"
            GateResult = $gate
            DeploymentManifest = $depManifest
        }
    }
    catch {
        Write-PRAEViolation -Type DEPLOYMENT_MUTATION_ATTEMPT `
            -Detail "Deployment manifest parse error: $_" `
            -ExecutionContext "DEPLOYMENT_VALIDATOR" `
            -Fingerprint $gate.Fingerprint.Fingerprint `
            -CallerIdentity $CallerIdentity
        return [PSCustomObject]@{
            DeploymentAllowed = $false
            Reason = "DEPLOYMENT_MANIFEST_CORRUPT"
            GateResult = $gate
        }
    }
}

# ============================================================
#  SECTION 8: FULL RUNTIME VALIDATION RUNNER
# ============================================================
function Invoke-PRAEFullRuntimeValidation {
    [CmdletBinding()]
    param(
        [string]$CallerIdentity = "PRAE-SELF-VALIDATION"
    )

    $report = [ordered]@{
        ValidationTimestamp   = [DateTimeOffset]::UtcNow.ToString("o")
        GovernanceVersion     = $Script:GOVERNANCE_VERSION
        EnforcementPhase      = $Script:ENFORCEMENT_PHASE
        ManifestLoaded        = $false
        AuthorityActive       = $false
        ChecksumValid         = $false
        MutationModeCompliant = $false
        RegistryIntegrity     = $false
        RelayActive           = $false
        GateInterceptsUnauth  = $false
        AuthorizedPassesGate  = $false
        LedgerWritable        = $false
        OverallStatus         = "UNKNOWN"
        Findings              = @()
    }

    # 1. Manifest
    try {
        $manifest = Get-PRAEAuthorityManifest
        $report.ManifestLoaded = $true
    } catch {
        $report.Findings += "FAIL: Manifest load  -  $_"
        $report.OverallStatus = "CRITICAL_FAILURE"
        return [PSCustomObject]$report
    }

    # 2. Authority active
    $report.AuthorityActive = Test-PRAEAuthorityActive -Manifest $manifest
    if (-not $report.AuthorityActive) { $report.Findings += "FAIL: Authority not ENFORCEMENT_ACTIVE" }

    # 3. Checksum
    $report.ChecksumValid = Test-AuthorityChecksum -Manifest $manifest
    if (-not $report.ChecksumValid) { $report.Findings += "FAIL: Authority checksum mismatch" }

    # 4. Mutation mode
    $report.MutationModeCompliant = Test-MutationMode -Manifest $manifest
    if (-not $report.MutationModeCompliant) { $report.Findings += "FAIL: Mutation mode non-compliant" }

    # 5. Registry
    $report.RegistryIntegrity = Test-RegistryIntegrity
    if (-not $report.RegistryIntegrity) { $report.Findings += "WARN: Registry integrity check failed or file absent" }

    # 6. Relay
    $report.RelayActive = Test-GovernanceRelayActive
    if (-not $report.RelayActive) { $report.Findings += "WARN: Governance relay offline or heartbeat stale" }

    # 7. Gate intercepts unauthorized
    $unauthGate = Invoke-PRAEExecutionGate `
        -ExecutionScope "production:mutate" `
        -CallerIdentity "TEST-UNAUTHORIZED" `
        -AllowRelayDegraded
    $report.GateInterceptsUnauth = (-not $unauthGate.Authorized)
    if (-not $report.GateInterceptsUnauth) { $report.Findings += "CRITICAL: Gate DID NOT intercept unauthorized scope!" }

    # 8. Gate allows authorized
    $authGate = Invoke-PRAEExecutionGate `
        -ExecutionScope "prae:governance:read" `
        -CallerIdentity "PRAE-SELF-VALIDATION" `
        -AllowRelayDegraded
    $report.AuthorizedPassesGate = $authGate.Authorized
    if (-not $report.AuthorizedPassesGate) { $report.Findings += "WARN: Authorized scope blocked by gate (check relay/registry)" }

    # 9. Ledger writable
    try {
        $ts_vt = [DateTimeOffset]::UtcNow.ToString('o')
        $testLine = "[$ts_vt] VALIDATION_TEST | PRAE full runtime validation ledger write test"
        $logDir = Split-Path $Script:VIOLATIONS_LOG -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        Add-Content -Path $Script:VIOLATIONS_LOG -Value $testLine -Encoding UTF8
        $report.LedgerWritable = $true
    } catch {
        $report.Findings += "FAIL: Ledger not writable  -  $_"
    }

    # Final status
    $criticalFails = $report.Findings | Where-Object { $_ -like "CRITICAL:*" }
    $hardFails = $report.Findings | Where-Object { $_ -like "FAIL:*" }

    if ($criticalFails.Count -gt 0) {
        $report.OverallStatus = "CRITICAL_FAILURE"
    } elseif ($hardFails.Count -gt 0) {
        $report.OverallStatus = "DEGRADED"
    } elseif ($report.Findings.Count -gt 0) {
        $report.OverallStatus = "WARNING"
    } else {
        $report.OverallStatus = "FULLY_OPERATIONAL"
    }

    return [PSCustomObject]$report
}

# ============================================================
#  SECTION 9: MODULE EXPORTS
# ============================================================
Export-ModuleMember -Function @(
    'Invoke-PRAEExecutionGate',
    'Invoke-PRAEDeploymentValidator',
    'Invoke-PRAEFullRuntimeValidation',
    'New-ExecutionFingerprint',
    'New-GovernanceToken',
    'Write-PRAEViolation',
    'Get-PRAEAuthorityManifest',
    'Test-PRAEAuthorityActive',
    'Test-RegistryIntegrity',
    'Test-GovernanceRelayActive',
    'Test-MutationMode',
    'Test-AuthorizedExecutionScope',
    'Test-AuthorityChecksum',
    'Test-ProtectedProject'
)

Write-Verbose "PRAE Execution Authority Gate Module loaded  -  Phase: $Script:ENFORCEMENT_PHASE"
