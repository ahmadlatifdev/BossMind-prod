#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Evidence Collector
    Reads REAL system state from filesystem, git, PRAE infrastructure,
    and runtime graph. Returns only facts that can be verified on disk.
    Never assumes, never invents, never prints secret values.
.DESCRIPTION
    Evidence sources (all read-only, no mutations):
      - Filesystem: project structure, config files, node_modules
      - Git:        branch, commit, clean state, last message
      - PRAE infra: relay, registry, manifest, violations log,
                    checksum registry, rollback checkpoint,
                    deployment validations, runtime graph node
      - Runtime:    PRAE module importable, gate callable

    Returns a [PSCustomObject] with all evidence.
    Unknown values are set to the string "UNKNOWN".
    Values that cannot be read without secrets are omitted entirely.

    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED
.PARAMETER ProjectName
    e.g. "bossmind-resumora"
.PARAMETER ProjectRoot
    e.g. "D:\BossMind\bossmind-resumora"
.PARAMETER SharedMemRoot
    Default: D:\BossMind\bossmind-shared\shared-memory
.PARAMETER PRAERoot
    Default: D:\BossMind\bossmind-shared\prae
.PARAMETER PRAEModulePath
    Default: D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectName,

    [Parameter(Mandatory)]
    [string]$ProjectRoot,

    [string]$SharedMemRoot  = "D:\BossMind\bossmind-shared\shared-memory",
    [string]$PRAERoot       = "D:\BossMind\bossmind-shared\prae",
    [string]$PRAEModulePath = "D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# -- Governance constants --------------------------------------
Set-Variable -Name GOV_MODE    -Value "LOCKED"  -Option ReadOnly -Force
Set-Variable -Name GOV_REPAIR  -Value "DISABLED" -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION -Value "NONE"   -Option ReadOnly -Force

$EVIDENCE_VERSION = "1.0"
$UNKNOWN          = "UNKNOWN"

# -- Safe read helpers -----------------------------------------
function Safe-ReadJson {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $null }
    try { return Get-Content $Path -Raw -Encoding UTF8 | ConvertFrom-Json }
    catch { return $null }
}

function Safe-LineCount {
    param([string]$Path)
    if (-not (Test-Path $Path)) { return $UNKNOWN }
    try { return @(Get-Content $Path -Encoding UTF8).Count }
    catch { return $UNKNOWN }
}

function Safe-AgeSeconds {
    param([string]$IsoTimestamp)
    if (-not $IsoTimestamp -or $IsoTimestamp -eq $UNKNOWN) { return $UNKNOWN }
    try {
        $ts  = [DateTimeOffset]::Parse($IsoTimestamp)
        return [int]([DateTimeOffset]::UtcNow - $ts).TotalSeconds
    } catch { return $UNKNOWN }
}

# -- GIT evidence ---------------------------------------------
function Get-GitEvidence {
    param([string]$Root)
    $result = [ordered]@{
        available    = $false
        branch       = $UNKNOWN
        commit       = $UNKNOWN
        clean        = $UNKNOWN
        last_message = $UNKNOWN
    }

    if (-not (Test-Path (Join-Path $Root ".git"))) { return $result }

    $gitExe = Get-Command git -ErrorAction SilentlyContinue
    if (-not $gitExe) { return $result }
    $result.available = $true

    Push-Location $Root
    try {
        # Branch
        $branch = (& git rev-parse --abbrev-ref HEAD 2>&1)
        if ($LASTEXITCODE -eq 0) { $result.branch = $branch.Trim() }

        # Commit
        $commit = (& git rev-parse --short HEAD 2>&1)
        if ($LASTEXITCODE -eq 0) { $result.commit = $commit.Trim() }

        # Clean state
        $status = (& git status --porcelain 2>&1)
        if ($LASTEXITCODE -eq 0) {
            $result.clean = (@($status | Where-Object { $_ -match '\S' }).Count -eq 0)
        }

        # Last commit message (no author, no email, no secrets)
        $msg = (& git log --oneline -1 2>&1)
        if ($LASTEXITCODE -eq 0) {
            # Strip the hash prefix, keep only the message text
            $result.last_message = ($msg -replace '^[0-9a-f]{5,12}\s+', '').Trim()
        }
    } catch { <# non-fatal #> }
    finally { Pop-Location }

    return $result
}

# -- FILESYSTEM evidence ---------------------------------------
function Get-FilesystemEvidence {
    param([string]$Root)

    $result = [ordered]@{
        project_root_exists = (Test-Path $Root)
        package_json        = $UNKNOWN
        package_lock        = $UNKNOWN
        env_file            = $UNKNOWN
        build_config        = $UNKNOWN
        deploy_config       = $UNKNOWN
        node_modules        = $UNKNOWN
        directories         = $UNKNOWN
    }

    if (-not $result.project_root_exists) { return $result }

    # package.json
    $pkgPath = Join-Path $Root "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
            $depCount = 0
            if ($pkg.dependencies)    { $depCount += ($pkg.dependencies    | Get-Member -MemberType NoteProperty).Count }
            if ($pkg.devDependencies) { $depCount += ($pkg.devDependencies | Get-Member -MemberType NoteProperty).Count }
            $result.package_json = [ordered]@{
                exists    = $true
                name      = if ($pkg.name)    { $pkg.name }    else { $UNKNOWN }
                version   = if ($pkg.version) { $pkg.version } else { $UNKNOWN }
                dep_count = $depCount
            }
        } catch {
            $result.package_json = [ordered]@{ exists=$true; name=$UNKNOWN; version=$UNKNOWN; dep_count=$UNKNOWN; parse_error=$true }
        }
    } else {
        $result.package_json = [ordered]@{ exists=$false }
    }

    # package-lock.json
    $lockPath = Join-Path $Root "package-lock.json"
    if (Test-Path $lockPath) {
        $lockSize = (Get-Item $lockPath).Length
        # Validate via node if available
        $nodeOk = $UNKNOWN
        $nodeExe = Get-Command node -ErrorAction SilentlyContinue
        if ($nodeExe) {
            $escaped = $lockPath.Replace('\','/')
            $nodeOut = & node -e "JSON.parse(require('fs').readFileSync('$escaped','utf8')); process.exit(0)" 2>&1
            $nodeOk  = ($LASTEXITCODE -eq 0)
        }
        $result.package_lock = [ordered]@{ exists=$true; size_bytes=$lockSize; node_valid=$nodeOk }
    } else {
        $result.package_lock = [ordered]@{ exists=$false }
    }

    # .env file (presence + required key check  -  NO values printed)
    $envCandidates = @('.env','.env.production','.env.local','.env.production.local')
    $envFile = $envCandidates | ForEach-Object { Join-Path $Root $_ } |
               Where-Object { Test-Path $_ } | Select-Object -First 1
    if ($envFile) {
        try {
            $envContent = Get-Content $envFile -Raw -Encoding UTF8
            $requiredKeys = @('DATABASE_URL','NEXTAUTH_SECRET','NEXTAUTH_URL')
            $stripeKeys   = @('STRIPE_SECRET_KEY','STRIPE_PUBLISHABLE_KEY','NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY')
            $presentKeys  = @($requiredKeys | Where-Object { $envContent -match "(?m)^$_\s*=" })
            $hasStripe    = @($stripeKeys   | Where-Object { $envContent -match "(?m)^$_\s*=" }).Count -gt 0
            $keyCount     = ([regex]::Matches($envContent,'(?m)^\w+\s*=')).Count
            # Check live vs test Stripe keys WITHOUT printing values
            $hasLiveSecret = $envContent -match '(?m)^STRIPE_SECRET_KEY\s*=\s*sk_live_'
            $hasTestSecret = $envContent -match '(?m)^STRIPE_SECRET_KEY\s*=\s*sk_test_'
            $result.env_file = [ordered]@{
                exists               = $true
                filename             = [System.IO.Path]::GetFileName($envFile)
                total_keys           = $keyCount
                required_keys_present= @($presentKeys).Count
                required_keys_missing= @($requiredKeys | Where-Object { $presentKeys -notcontains $_ })
                stripe_key_present   = $hasStripe
                stripe_mode          = if ($hasLiveSecret) { "LIVE" } elseif ($hasTestSecret) { "TEST" } else { $UNKNOWN }
                # NOTE: no key values are stored or printed
            }
        } catch {
            $result.env_file = [ordered]@{ exists=$true; filename=[System.IO.Path]::GetFileName($envFile); parse_error=$true }
        }
    } else {
        $result.env_file = [ordered]@{ exists=$false }
    }

    # Build config
    $buildCandidates = @('next.config.js','next.config.ts','next.config.mjs','next.config.cjs')
    $buildFile = $buildCandidates | Where-Object { Test-Path (Join-Path $Root $_) } | Select-Object -First 1
    $result.build_config = if ($buildFile) {
        [ordered]@{ exists=$true; filename=$buildFile }
    } else { [ordered]@{ exists=$false } }

    # Deploy config
    $deployCandidates = @('railway.json','railway.toml','render.yaml','render.yml')
    $deployFile = $deployCandidates | Where-Object { Test-Path (Join-Path $Root $_) } | Select-Object -First 1
    $result.deploy_config = if ($deployFile) {
        [ordered]@{ exists=$true; filename=$deployFile }
    } else { [ordered]@{ exists=$false } }

    # node_modules
    $nmPath = Join-Path $Root "node_modules"
    $result.node_modules = [ordered]@{ exists=(Test-Path $nmPath) }

    # Key directories
    $dirs = @('app','pages','lib','api','middleware','src','components')
    $presentDirs = $dirs | Where-Object { Test-Path (Join-Path $Root $_) }
    $result.directories = [ordered]@{
        present = @($presentDirs)
        absent  = @($dirs | Where-Object { $presentDirs -notcontains $_ })
    }

    return $result
}

# -- PRAE INFRASTRUCTURE evidence -----------------------------
function Get-PRAEEvidence {
    param([string]$PRAERoot, [string]$SharedMemRoot, [string]$ProjectName)

    $prefix   = $ProjectName.ToLower().Replace(' ','-')
    $relayPath= Join-Path $PRAERoot "relay\relay-heartbeat.json"
    $regPath  = Join-Path $PRAERoot "registry\prae-runtime-registry.json"
    $manifPath= Join-Path $PRAERoot "authority\prae-execution-authority.json"
    $violPath = Join-Path $SharedMemRoot "prae-governance-violations.log"
    $chkRegP  = Join-Path $SharedMemRoot "$prefix-checksum-registry.json"
    $rollbP   = Join-Path $SharedMemRoot "$prefix-rollback-checkpoint.json"
    $deplValP = Join-Path $SharedMemRoot "$prefix-deployment-validations.json"
    $graphP   = Join-Path $PRAERoot "runtime-graph\bossmind-runtime-graph.json"

    $result = [ordered]@{}

    # Relay heartbeat
    $relay = Safe-ReadJson $relayPath
    if ($relay) {
        $ageS = Safe-AgeSeconds $relay.last_heartbeat
        $result.relay_heartbeat = [ordered]@{
            exists      = $true
            age_seconds = $ageS
            active      = ($ageS -ne $UNKNOWN -and [int]$ageS -lt 600)
            status      = if ($relay.relay_status) { $relay.relay_status } else { $UNKNOWN }
        }
    } else {
        $result.relay_heartbeat = [ordered]@{ exists=$false; active=$false }
    }

    # PRAE registry
    $reg = Safe-ReadJson $regPath
    $result.prae_registry = if ($reg) {
        [ordered]@{ exists=$true; integrity_status=if($reg.integrity_status){$reg.integrity_status}else{$UNKNOWN} }
    } else { [ordered]@{ exists=$false } }

    # Authority manifest
    $manif = Safe-ReadJson $manifPath
    $result.authority_manifest = if ($manif) {
        [ordered]@{
            exists         = $true
            authority_mode = if($manif.authority.mode){$manif.authority.mode}else{$UNKNOWN}
            governance_mode= if($manif.authority.governance_mode){$manif.authority.governance_mode}else{$UNKNOWN}
        }
    } else { [ordered]@{ exists=$false } }

    # Violations log
    $violCount = Safe-LineCount $violPath
    $result.violations_log = [ordered]@{ exists=(Test-Path $violPath); line_count=$violCount }

    # Checksum registry
    $chkReg = Safe-ReadJson $chkRegP
    $result.checksum_registry = if ($chkReg) {
        [ordered]@{
            exists      = $true
            file_count  = if($chkReg.file_count -ne $null){$chkReg.file_count}else{$UNKNOWN}
            updated_at  = if($chkReg.updated_at){$chkReg.updated_at}else{$UNKNOWN}
            age_seconds = Safe-AgeSeconds (if($chkReg.updated_at){$chkReg.updated_at}else{""})
        }
    } else { [ordered]@{ exists=$false } }

    # Rollback checkpoint
    $rollb = Safe-ReadJson $rollbP
    $result.rollback_checkpoint = if ($rollb) {
        [ordered]@{
            exists          = $true
            checkpoint_at   = if($rollb.checkpoint_at){$rollb.checkpoint_at}else{$UNKNOWN}
            checkpoint_type = if($rollb.checkpoint_type){$rollb.checkpoint_type}else{$UNKNOWN}
            file_count      = if($rollb.file_count -ne $null){$rollb.file_count}else{$UNKNOWN}
            age_seconds     = Safe-AgeSeconds (if($rollb.checkpoint_at){$rollb.checkpoint_at}else{""}  )
        }
    } else { [ordered]@{ exists=$false } }

    # Last deployment validation
    $deplVals = Safe-ReadJson $deplValP
    $result.last_deployment_validation = if ($deplVals) {
        $records = @($deplVals)
        $last    = $records | Select-Object -Last 1
        if ($last) {
            [ordered]@{
                exists       = $true
                overall      = if($last.overall){$last.overall}else{$UNKNOWN}
                validated_at = if($last.validated_at){$last.validated_at}else{$UNKNOWN}
                age_seconds  = Safe-AgeSeconds (if($last.validated_at){$last.validated_at}else{""})
                record_count = @($records).Count
            }
        } else { [ordered]@{ exists=$true; overall=$UNKNOWN } }
    } else { [ordered]@{ exists=$false } }

    # Runtime graph node
    $graph = Safe-ReadJson $graphP
    $result.runtime_graph_node = if ($graph -and $graph.projects.PSObject.Properties[$ProjectName]) {
        $node = $graph.projects.$ProjectName
        [ordered]@{
            exists             = $true
            validation_overall = if($node.validation.overall){$node.validation.overall}else{$UNKNOWN}
            watcher_status     = if($node.watcher.status){$node.watcher.status}else{$UNKNOWN}
            risk_score         = if($node.risk.current_score){$node.risk.current_score}else{$UNKNOWN}
            last_updated       = if($node.last_updated){$node.last_updated}else{$UNKNOWN}
        }
    } else { [ordered]@{ exists=$false } }

    return $result
}

# -- PRAE RUNTIME evidence -------------------------------------
function Get-PRAERuntimeEvidence {
    param([string]$ModulePath, [string]$ProjectName)

    $result = [ordered]@{
        module_exists    = (Test-Path $ModulePath)
        module_importable= $false
        gate_callable    = $false
        gate_result      = $UNKNOWN
    }

    if (-not $result.module_exists) { return $result }

    # Encoding pre-check
    $bytes    = [System.IO.File]::ReadAllBytes($ModulePath)
    $nonAscii = ($bytes | Where-Object { $_ -gt 127 -and $_ -ne 0xEF -and $_ -ne 0xBB -and $_ -ne 0xBF }).Count
    if ($nonAscii -gt 0) {
        $result.module_encoding_clean = $false
        return $result
    }
    $result.module_encoding_clean = $true

    try {
        if (-not (Get-Module 'PRAE-ExecutionGate' -ErrorAction SilentlyContinue)) {
            Import-Module $ModulePath -Force -DisableNameChecking -ErrorAction Stop
        }
        $result.module_importable = $true
    } catch {
        $result.module_import_error = $_.Exception.Message
        return $result
    }

    # Test gate with a safe read-only scope
    try {
        $gate = Invoke-PRAEExecutionGate `
            -ExecutionScope "prae:governance:read" `
            -CallerIdentity "PRAE-EVIDENCE-COLLECTOR" `
            -TargetProject  $ProjectName `
            -AllowRelayDegraded
        $result.gate_callable = $true
        $result.gate_result   = if ($gate.Authorized) { "AUTHORIZED" } else { "BLOCKED:$($gate.FailureReason)" }
    } catch {
        $result.gate_callable     = $false
        $result.gate_call_error   = $_.Exception.Message
    }

    return $result
}

# -- MAIN: Collect all evidence --------------------------------
Write-Verbose "PRAE-EvidenceCollector: collecting evidence for $ProjectName"

$evidence = [ordered]@{
    project_name        = $ProjectName
    project_root        = $ProjectRoot
    evidence_version    = $EVIDENCE_VERSION
    collected_at        = [DateTimeOffset]::UtcNow.ToString("o")
    governance_mode     = $GOV_MODE
    production_mutation = $GOV_MUTATION
    auto_repair         = $GOV_REPAIR
    filesystem          = Get-FilesystemEvidence -Root $ProjectRoot
    git                 = Get-GitEvidence -Root $ProjectRoot
    prae                = Get-PRAEEvidence -PRAERoot $PRAERoot -SharedMemRoot $SharedMemRoot -ProjectName $ProjectName
    prae_runtime        = Get-PRAERuntimeEvidence -ModulePath $PRAEModulePath -ProjectName $ProjectName
}

Write-Verbose "PRAE-EvidenceCollector: collection complete"
return [PSCustomObject]$evidence
