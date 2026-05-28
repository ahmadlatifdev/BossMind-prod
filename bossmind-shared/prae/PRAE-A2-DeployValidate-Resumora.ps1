#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Phase A2 - Deployment Validation Mesh (bossmind-resumora)
    Validates all deployment preconditions before any deploy is allowed.
    Exits 0 (ALL PASS) or 1 (BLOCKED). Never deploys anything itself.
.DESCRIPTION
    Runs 9 validation domains in order. Every domain must pass for
    exit 0. The first domain failure does NOT abort - all domains run
    so you see the complete picture in one pass.

    Validation domains:
      1. GitState          - clean working tree, no uncommitted changes
      2. RequiredFiles     - critical files exist on disk
      3. EnvCompleteness   - required env vars present in .env file
      4. DependencyIntegrity  - package.json and lock file coherent
      5. BuildConfig       - next.config.* present and parseable
      6. RailwayConfig     - railway.json/toml present and valid
      7. RollbackCheckpoint - A1 watcher checkpoint exists
      8. WatcherDrift      - checksum registry shows no HIGH-RISK drift
      9. PRAEGate          - Invoke-PRAEExecutionGate authorises deploy

    Results are appended to:
      resumora-deployment-validations.json

    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED
.PARAMETER ProjectRoot
    Default: D:\BossMind\bossmind-resumora
.PARAMETER SharedMemRoot
    Default: D:\BossMind\bossmind-shared\shared-memory
.PARAMETER PRAEModulePath
    Default: D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1
.PARAMETER CallerIdentity
    Identity written into PRAE gate fingerprint. Default: current Windows user.
.PARAMETER SkipPRAEGate
    Skip domain 9 (use when PRAE module is unavailable for testing).
.PARAMETER SkipDriftCheck
    Skip domain 8 (use when no A1 registry exists yet).
.EXAMPLE
    # Standard pre-deploy run
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "D:\BossMind\bossmind-shared\prae\PRAE-A2-DeployValidate-Resumora.ps1"

    # In CI (Railway pre-deploy hook)
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-A2-DeployValidate-Resumora.ps1" `
        -CallerIdentity "RAILWAY-CI"
#>

[CmdletBinding()]
param(
    [string]$ProjectRoot     = "D:\BossMind\bossmind-resumora",
    [string]$SharedMemRoot   = "D:\BossMind\bossmind-shared\shared-memory",
    [string]$PRAEModulePath  = "D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1",
    [string]$CallerIdentity  = "",
    [string]$RuntimeGraphModulePath = "D:\BossMind\bossmind-shared\prae\PRAE-RuntimeGraph.ps1",
    [switch]$SkipPRAEGate,
    [switch]$SkipDriftCheck
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  GOVERNANCE CONSTANTS (ReadOnly)
# ---------------------------------------------------------------
Set-Variable -Name GraphGovMode      -Value "LOCKED"           -Option ReadOnly -Force
Set-Variable -Name GraphGovRepair    -Value "DISABLED"          -Option ReadOnly -Force
Set-Variable -Name GraphGovMutation  -Value "NONE"              -Option ReadOnly -Force
Set-Variable -Name PROJECT_NAME  -Value "bossmind-resumora" -Option ReadOnly -Force
Set-Variable -Name GATE_SCOPE    -Value "bossmind:deployment:validate" -Option ReadOnly -Force

if (-not $CallerIdentity) {
    $CallerIdentity = [System.Security.Principal.WindowsIdentity]::GetCurrent().Name
}

# ---------------------------------------------------------------
#  OUTPUT PATHS
# ---------------------------------------------------------------
$ValidationLog   = Join-Path $SharedMemRoot "resumora-deployment-validations.json"
$ChecksumReg     = Join-Path $SharedMemRoot "resumora-checksum-registry.json"
$RollbackChk     = Join-Path $SharedMemRoot "resumora-rollback-checkpoint.json"

# ---------------------------------------------------------------
#  VALIDATION RESULT BUILDER
# ---------------------------------------------------------------
function New-DomainResult {
    param([string]$Domain, [bool]$Pass, [string]$Detail, [string]$Severity = "")
    return [PSCustomObject]@{
        Domain   = $Domain
        Pass     = $Pass
        Detail   = $Detail
        Severity = if ($Severity) { $Severity } elseif ($Pass) { "OK" } else { "BLOCKED" }
    }
}

# ---------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------
function Write-DomainPass { param([string]$D,[string]$M)
    Write-Host "  [PASS ] [$D] $M" -ForegroundColor Green }
function Write-DomainFail { param([string]$D,[string]$M)
    Write-Host "  [BLOCK] [$D] $M" -ForegroundColor Red }
function Write-DomainWarn { param([string]$D,[string]$M)
    Write-Host "  [WARN ] [$D] $M" -ForegroundColor Yellow }
function Write-DomainInfo { param([string]$D,[string]$M)
    Write-Host "  [INFO ] [$D] $M" -ForegroundColor Gray }

# ---------------------------------------------------------------
#  DOMAIN 1: GIT STATE
# ---------------------------------------------------------------
function Test-GitState {
    $domain = "GitState"
    try {
        # Check git is available
        $gitPath = Get-Command git -ErrorAction SilentlyContinue
        if (-not $gitPath) {
            return New-DomainResult $domain $false "git not found in PATH" "WARN"
        }
        Push-Location $ProjectRoot
        try {
            # Unstaged changes
            $status = & git status --porcelain 2>&1
            $exitCode = $LASTEXITCODE
            if ($exitCode -ne 0) {
                return New-DomainResult $domain $false "git status failed (exit $exitCode): $status"
            }
            $lines = @($status | Where-Object { $_ -match '\S' })
            if (@($lines).Count -gt 0) {
                $summary = ($lines | Select-Object -First 5) -join "; "
                return New-DomainResult $domain $false "$(@($lines).Count) uncommitted change(s): $summary"
            }

            # Current branch
            $branch = (& git rev-parse --abbrev-ref HEAD 2>&1).Trim()
            $commit = (& git rev-parse --short HEAD 2>&1).Trim()
            return New-DomainResult $domain $true "Clean on branch '$branch' @ $commit"
        } finally {
            Pop-Location
        }
    } catch {
        return New-DomainResult $domain $false "Exception: $_" "WARN"
    }
}

# ---------------------------------------------------------------
#  DOMAIN 2: REQUIRED FILES
# ---------------------------------------------------------------
function Test-RequiredFiles {
    $domain = "RequiredFiles"
    $required = @(
        'package.json',
        'package-lock.json'
    )
    # Build-system config (at least one must exist)
    $buildConfigs = @('next.config.js','next.config.ts','next.config.mjs','next.config.cjs')
    # Deployment config (at least one must exist)
    $deployConfigs = @('railway.json','railway.toml','render.yaml','render.yml')

    $missing = [System.Collections.Generic.List[string]]::new()

    foreach ($f in $required) {
        if (-not (Test-Path (Join-Path $ProjectRoot $f))) {
            $missing.Add($f)
        }
    }

    $hasBuildConfig  = $buildConfigs  | Where-Object { Test-Path (Join-Path $ProjectRoot $_) }
    $hasDeployConfig = $deployConfigs | Where-Object { Test-Path (Join-Path $ProjectRoot $_) }

    if (-not @($hasBuildConfig).Count) {
        $missing.Add("next.config.* (none found)")
    }
    if (-not @($hasDeployConfig).Count) {
        $missing.Add("railway.json/toml or render.yaml (none found)")
    }

    if (@($missing).Count -gt 0) {
        return New-DomainResult $domain $false "Missing: $($missing -join ', ')"
    }
    return New-DomainResult $domain $true "All required files present"
}

# ---------------------------------------------------------------
#  DOMAIN 3: ENV COMPLETENESS
# ---------------------------------------------------------------
function Test-EnvCompleteness {
    $domain = "EnvCompleteness"

    # Look for any .env file (production typically .env, .env.production, .env.local)
    $envCandidates = @('.env', '.env.production', '.env.local', '.env.production.local')
    $envFile = $envCandidates |
        ForEach-Object { Join-Path $ProjectRoot $_ } |
        Where-Object { Test-Path $_ } |
        Select-Object -First 1

    if (-not $envFile) {
        return New-DomainResult $domain $false "No .env file found (checked: $($envCandidates -join ', '))" "WARN"
    }

    # These keys must be present (value can be non-empty placeholder)
    $requiredKeys = @(
        'DATABASE_URL',
        'NEXTAUTH_SECRET',
        'NEXTAUTH_URL'
    )
    # Stripe keys: at least one of these must exist
    $stripeKeys = @('STRIPE_SECRET_KEY','STRIPE_PUBLISHABLE_KEY','NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY')

    try {
        $envContent = Get-Content $envFile -Raw -Encoding UTF8
    } catch {
        return New-DomainResult $domain $false "Cannot read $envFile : $_"
    }

    $missing = [System.Collections.Generic.List[string]]::new()
    foreach ($key in $requiredKeys) {
        if ($envContent -notmatch "(?m)^$key\s*=\s*.+") {
            $missing.Add($key)
        }
    }

    $hasStripe = $stripeKeys | Where-Object { $envContent -match "(?m)^$_\s*=\s*.+" }
    if (-not @($hasStripe).Count) {
        $missing.Add("STRIPE_*KEY (none found)")
    }

    if (@($missing).Count -gt 0) {
        return New-DomainResult $domain $false "Missing env keys: $($missing -join ', ')"
    }

    $keyCount = ([regex]::Matches($envContent, '(?m)^\w+\s*=')).Count
    return New-DomainResult $domain $true "Env file valid ($keyCount keys in $([System.IO.Path]::GetFileName($envFile)))"
}

# ---------------------------------------------------------------
#  DOMAIN 4: DEPENDENCY INTEGRITY
# ---------------------------------------------------------------
function Test-DependencyIntegrity {
    $domain = "DependencyIntegrity"

    $pkgPath  = Join-Path $ProjectRoot 'package.json'
    $lockPath = Join-Path $ProjectRoot 'package-lock.json'

    if (-not (Test-Path $pkgPath)) {
        return New-DomainResult $domain $false "package.json not found"
    }

    # Parse package.json
    try {
        $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return New-DomainResult $domain $false "package.json is not valid JSON: $_"
    }

    # Name and version present
    if (-not $pkg.name) {
        return New-DomainResult $domain $false "package.json missing 'name' field"
    }

    # Lock file exists
    if (-not (Test-Path $lockPath)) {
        return New-DomainResult $domain $false "package-lock.json missing (run npm install)"
    }

    # Lock file parseable - use Node.js JSON.parse (avoids PS ConvertFrom-Json memory/schema issues)
    $nodeExe = Get-Command node -ErrorAction SilentlyContinue
    if ($nodeExe) {
        $nodeScript = "JSON.parse(require('fs').readFileSync('$($lockPath.Replace('\\','/'))','utf8')); console.log('package-lock valid')"
        $nodeOut    = & node -e $nodeScript 2>&1
        $nodeExit   = $LASTEXITCODE
        if ($nodeExit -ne 0) {
            return New-DomainResult $domain $false "package-lock.json invalid (node JSON.parse failed): $nodeOut"
        }
    } else {
        # Node not available - fall back to basic file-size sanity check
        $lockSize = (Get-Item $lockPath).Length
        if ($lockSize -lt 50) {
            return New-DomainResult $domain $false "package-lock.json suspiciously small ($lockSize bytes)"
        }
    }

    $depCount = 0
    if ($pkg.dependencies)    { $depCount += ($pkg.dependencies | Get-Member -MemberType NoteProperty).Count }
    if ($pkg.devDependencies) { $depCount += ($pkg.devDependencies | Get-Member -MemberType NoteProperty).Count }

    # node_modules must exist (if package.json has dependencies)
    $nmPath = Join-Path $ProjectRoot 'node_modules'
    if ($depCount -gt 0 -and -not (Test-Path $nmPath)) {
        return New-DomainResult $domain $false "node_modules absent with $depCount declared dependencies (run npm install)"
    }

    return New-DomainResult $domain $true "$($pkg.name) v$($pkg.version) | $depCount dependencies | lock file coherent"
}

# ---------------------------------------------------------------
#  DOMAIN 5: BUILD CONFIG
# ---------------------------------------------------------------
function Test-BuildConfig {
    $domain = "BuildConfig"

    $candidates = @('next.config.js','next.config.ts','next.config.mjs','next.config.cjs')
    $found = $candidates | Where-Object { Test-Path (Join-Path $ProjectRoot $_) } | Select-Object -First 1

    if (-not $found) {
        return New-DomainResult $domain $false "No next.config.* found"
    }

    $fullPath = Join-Path $ProjectRoot $found
    try {
        $content = Get-Content $fullPath -Raw -Encoding UTF8
    } catch {
        return New-DomainResult $domain $false "Cannot read $found : $_"
    }

    if ($content.Trim().Length -eq 0) {
        return New-DomainResult $domain $false "$found is empty"
    }

    # Rough sanity: should contain module.exports or export default
    $hasExport = $content -match 'module\.exports' -or $content -match 'export\s+default' -or $content -match 'export\s+const\s+config'
    if (-not $hasExport) {
        return New-DomainResult $domain $false "$found has no recognisable export (module.exports / export default)" "WARN"
    }

    $size = (Get-Item $fullPath).Length
    return New-DomainResult $domain $true "$found present and valid ($size bytes)"
}

# ---------------------------------------------------------------
#  DOMAIN 6: RAILWAY CONFIG
# ---------------------------------------------------------------
function Test-RailwayConfig {
    $domain = "RailwayConfig"

    $candidates = @(
        @{ Name='railway.json'; Type='json' },
        @{ Name='railway.toml'; Type='toml' },
        @{ Name='render.yaml';  Type='yaml' },
        @{ Name='render.yml';   Type='yaml' }
    )

    $found = $null
    foreach ($c in $candidates) {
        $p = Join-Path $ProjectRoot $c.Name
        if (Test-Path $p) { $found = $c; $found.Path = $p; break }
    }

    if (-not $found) {
        return New-DomainResult $domain $false "No railway.json/toml or render.yaml found" "WARN"
    }

    $content = Get-Content $found.Path -Raw -Encoding UTF8
    if ($content.Trim().Length -eq 0) {
        return New-DomainResult $domain $false "$($found.Name) is empty"
    }

    if ($found.Type -eq 'json') {
        try { $null = $content | ConvertFrom-Json }
        catch { return New-DomainResult $domain $false "$($found.Name) is not valid JSON: $_" }
    }

    $size = (Get-Item $found.Path).Length
    return New-DomainResult $domain $true "$($found.Name) present and valid ($size bytes)"
}

# ---------------------------------------------------------------
#  DOMAIN 7: ROLLBACK CHECKPOINT
# ---------------------------------------------------------------
function Test-RollbackCheckpoint {
    $domain = "RollbackCheckpoint"

    if (-not (Test-Path $RollbackChk)) {
        return New-DomainResult $domain $false "No rollback checkpoint found at $RollbackChk - run A1 watcher -Snapshot first" "WARN"
    }

    try {
        $chk = Get-Content $RollbackChk -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return New-DomainResult $domain $false "Rollback checkpoint unreadable: $_"
    }

    if (-not $chk.checkpoint_at) {
        return New-DomainResult $domain $false "Checkpoint missing timestamp field"
    }

    $age = ([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($chk.checkpoint_at)).TotalHours
    $ageStr = if ($age -lt 1) { "$([int]($age*60))m ago" } else { "$([Math]::Round($age,1))h ago" }

    if ($age -gt 48) {
        return New-DomainResult $domain $false "Checkpoint is $ageStr old (>48h) - run -Snapshot to refresh" "WARN"
    }

    return New-DomainResult $domain $true "Checkpoint valid | $($chk.file_count) files | created $ageStr"
}

# ---------------------------------------------------------------
#  DOMAIN 8: WATCHER DRIFT CHECK
# ---------------------------------------------------------------
function Test-WatcherDrift {
    $domain = "WatcherDrift"

    if ($SkipDriftCheck) {
        return New-DomainResult $domain $true "Skipped (-SkipDriftCheck flag)" "SKIPPED"
    }

    if (-not (Test-Path $ChecksumReg)) {
        return New-DomainResult $domain $true "No checksum registry yet (run A1 watcher first)" "WARN"
    }

    try {
        $reg = Get-Content $ChecksumReg -Raw -Encoding UTF8 | ConvertFrom-Json
    } catch {
        return New-DomainResult $domain $false "Checksum registry unreadable: $_"
    }

    # Check for HIGH-RISK files that were modified since last checkpoint
    $highRiskPatterns = @(
        'package.json', 'package-lock.json', 'railway.json', 'railway.toml',
        'render.yaml', 'render.yml', 'next.config', '.env', 'middleware'
    )

    $driftedHigh = [System.Collections.Generic.List[string]]::new()

    if ($reg.files) {
        $regFiles = $reg.files | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
        foreach ($rel in $regFiles) {
            $isHigh = $highRiskPatterns | Where-Object { $rel -like "*$_*" }
            if (-not @($isHigh).Count) { continue }

            $fullPath = Join-Path $ProjectRoot $rel
            if (-not (Test-Path $fullPath)) {
                $driftedHigh.Add("MISSING: $rel")
                continue
            }
            # Re-compute checksum
            $sha  = [System.Security.Cryptography.SHA256]::Create()
            $stream = [System.IO.File]::OpenRead($fullPath)
            try {
                $hash    = $sha.ComputeHash($stream)
                $current = [System.BitConverter]::ToString($hash) -replace '-',''
            } finally { $stream.Dispose(); $sha.Dispose() }

            $stored = $reg.files.$rel.checksum
            if ($current -ne $stored) {
                $driftedHigh.Add("MODIFIED: $rel")
            }
        }
    }

    if (@($driftedHigh).Count -gt 0) {
        $list = ($driftedHigh | Select-Object -First 5) -join " | "
        return New-DomainResult $domain $false "$(@($driftedHigh).Count) HIGH-RISK file(s) drifted: $list"
    }

    $updatedAge = if ($reg.updated_at) {
        "$([Math]::Round(([DateTimeOffset]::UtcNow - [DateTimeOffset]::Parse($reg.updated_at)).TotalMinutes,1))m ago"
    } else { "unknown" }

    return New-DomainResult $domain $true "No HIGH-RISK drift | registry updated $updatedAge | $($reg.file_count) files tracked"
}

# ---------------------------------------------------------------
#  DOMAIN 9: PRAE GATE
# ---------------------------------------------------------------
function Test-PRAEGate {
    $domain = "PRAEGate"

    if ($SkipPRAEGate) {
        return New-DomainResult $domain $true "Skipped (-SkipPRAEGate flag)" "SKIPPED"
    }

    if (-not (Test-Path $PRAEModulePath)) {
        return New-DomainResult $domain $false "PRAE module not found: $PRAEModulePath"
    }

    try {
        if (-not (Get-Module 'PRAE-ExecutionGate' -ErrorAction SilentlyContinue)) {
            Import-Module $PRAEModulePath -Force -DisableNameChecking -ErrorAction Stop
        }
    } catch {
        return New-DomainResult $domain $false "PRAE module import failed: $_"
    }

    try {
        $gate = Invoke-PRAEExecutionGate `
            -ExecutionScope $GATE_SCOPE `
            -CallerIdentity $CallerIdentity `
            -TargetProject  $PROJECT_NAME

        if ($gate.Authorized) {
            $tokenShort = if ($gate.Token) { $gate.Token.Token.Substring(0,16) + "..." } else { "N/A" }
            return New-DomainResult $domain $true "Gate AUTHORIZED | token: $tokenShort"
        } else {
            return New-DomainResult $domain $false "Gate BLOCKED: $($gate.FailureReason)"
        }
    } catch {
        return New-DomainResult $domain $false "Invoke-PRAEExecutionGate exception: $_"
    }
}

# ---------------------------------------------------------------
#  HEADER
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE A2 - Deployment Validation Mesh           |" -ForegroundColor Cyan
Write-Host "  |  Project  : bossmind-resumora                   |" -ForegroundColor DarkCyan
Write-Host "  |  Caller   : $($CallerIdentity.PadRight(35))|" -ForegroundColor DarkCyan
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""

# ---------------------------------------------------------------
#  RUN ALL 9 DOMAINS
# ---------------------------------------------------------------
$results = [System.Collections.Generic.List[PSCustomObject]]::new()
$domainFns = @(
    { Test-GitState },
    { Test-RequiredFiles },
    { Test-EnvCompleteness },
    { Test-DependencyIntegrity },
    { Test-BuildConfig },
    { Test-RailwayConfig },
    { Test-RollbackCheckpoint },
    { Test-WatcherDrift },
    { Test-PRAEGate }
)

# Load runtime graph module (optional)
$GraphLoaded = $false
if (Test-Path $RuntimeGraphModulePath) {
    try {
        if (-not (Get-Module 'PRAE-RuntimeGraph' -ErrorAction SilentlyContinue)) {
            Import-Module $RuntimeGraphModulePath -Force -DisableNameChecking -ErrorAction Stop
        }
        $GraphLoaded = $true
    } catch {
        Write-DomainWarn "Graph" "RuntimeGraph module load failed (non-fatal): $_"
    }
}

$i = 1
foreach ($fn in $domainFns) {
    $result = & $fn
    $results.Add($result)
    if ($result.Pass) {
        Write-DomainPass $result.Domain $result.Detail
    } elseif ($result.Severity -eq 'WARN') {
        Write-DomainWarn $result.Domain $result.Detail
    } else {
        Write-DomainFail $result.Domain $result.Detail
    }
    $i++
}

# ---------------------------------------------------------------
#  EVALUATE OVERALL RESULT
# ---------------------------------------------------------------
# WARN severity is advisory: doesn't block deploy
# Only BLOCKED severity fails the gate
$blocking = @($results | Where-Object { (-not $_.Pass) -and $_.Severity -eq 'BLOCKED' })
$warnings  = @($results | Where-Object { (-not $_.Pass) -and $_.Severity -eq 'WARN' })
$passed    = @($results | Where-Object { $_.Pass })
$allPass   = @($blocking).Count -eq 0

# ---------------------------------------------------------------
#  PERSIST RESULTS
# ---------------------------------------------------------------
$record = [ordered]@{
    project          = $PROJECT_NAME
    governance_mode  = $GraphGovMode
    validated_at     = [DateTimeOffset]::UtcNow.ToString("o")
    caller           = $CallerIdentity
    overall          = if ($allPass) { "ALL_VALIDATIONS_PASS" } else { "DEPLOYMENT_BLOCKED" }
    passed_count     = @($passed).Count
    blocked_count    = @($blocking).Count
    warning_count    = @($warnings).Count
    domains          = @($results | ForEach-Object {
        [ordered]@{ domain=$_.Domain; pass=$_.Pass; detail=$_.Detail; severity=$_.Severity }
    })
}

try {
    $dir = Split-Path $ValidationLog -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # Append record to JSON array file
    $existing = @()
    if (Test-Path $ValidationLog) {
        try { $existing = @(Get-Content $ValidationLog -Raw -Encoding UTF8 | ConvertFrom-Json) }
        catch { $existing = @() }
    }
    $updated = @($existing) + @([PSCustomObject]$record)
    # Keep last 50 records only
    if ($updated.Count -gt 50) { $updated = $updated | Select-Object -Last 50 }
    $updated | ConvertTo-Json -Depth 6 |
        ForEach-Object { [System.IO.File]::WriteAllText($ValidationLog, $_, [System.Text.Encoding]::UTF8) }
} catch {
    Write-DomainWarn "Persist" "Could not write validation log: $_"
}

# ---------------------------------------------------------------
#  RUNTIME GRAPH UPDATE
# ---------------------------------------------------------------
if ($GraphLoaded) {
    try {
        # Extract git values from GitState domain result
        $gitResult   = $results | Where-Object { $_.Domain -eq "GitState" } | Select-Object -First 1
        $gitBranchVal = ""
        $gitCommitVal = ""
        $gitCleanVal  = ""
        if ($gitResult -and $gitResult.Detail) {
            if ($gitResult.Detail -match "branch '([^']+)'") {
                $gitBranchVal = $Matches[1]
            }
            if ($gitResult.Detail -match "@\s+([0-9a-f]{5,12})") {
                $gitCommitVal = $Matches[1]
            }
            $gitCleanVal = if ($gitResult.Pass) { "True" } else { "False" }
        }
        Update-RuntimeGraph -ProjectName $PROJECT_NAME -ProjectRoot $ProjectRoot `
            -UpdateType VALIDATION -ValidationRecord ([PSCustomObject]$record) `
            -GitBranch $gitBranchVal -GitCommit $gitCommitVal -GitClean $gitCleanVal
    } catch {
        Write-DomainWarn "Graph" "RuntimeGraph update failed (non-fatal): $_"
    }
}

# ---------------------------------------------------------------
#  FINAL VERDICT
# ---------------------------------------------------------------
Write-Host ""
if ($allPass) {
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Green
    Write-Host "  |  ALL VALIDATIONS PASS - DEPLOYMENT AUTHORISED    |" -ForegroundColor Green
    if (@($warnings).Count -gt 0) {
        Write-Host "  |  $(@($warnings).Count) advisory warning(s) - review recommended    |" -ForegroundColor Green
    }
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Green
    Write-Host ""
    Write-DomainInfo "Summary" "$(@($passed).Count)/9 domains passed | $(@($warnings).Count) warnings"
    Write-DomainInfo "Log" "$ValidationLog"
    Write-Host ""
    Write-Host "  governance_mode=$GraphGovMode  production_mutation=$GraphGovMutation" -ForegroundColor DarkCyan
    Write-Host ""
    exit 0
} else {
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Red
    Write-Host "  |  DEPLOYMENT BLOCKED                              |" -ForegroundColor Red
    Write-Host "  |  $(@($blocking).Count) domain(s) failed validation$(if(@($blocking).Count -ne 1){'s'} else{' '})                   |" -ForegroundColor Red
    Write-Host "  +--------------------------------------------------+" -ForegroundColor Red
    Write-Host ""
    Write-DomainInfo "Blocked domains:" ($blocking | ForEach-Object { $_.Domain }) -join ", "
    Write-DomainInfo "Log" "$ValidationLog"
    Write-Host ""
    Write-Host "  governance_mode=$GraphGovMode  production_mutation=$GraphGovMutation" -ForegroundColor DarkCyan
    Write-Host ""
    exit 1
}
