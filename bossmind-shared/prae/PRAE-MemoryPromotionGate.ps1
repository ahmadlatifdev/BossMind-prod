#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Memory Promotion Gate
    Evaluates raw evidence from PRAE-EvidenceCollector and promotes
    only facts that are genuinely confirmed by disk/git/PRAE state.
    Marks unknowns as UNKNOWN. Marks partials as PARTIAL.
    Never promotes assumed or invented facts.

    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED
.DESCRIPTION
    Confidence levels:
      VERIFIED  - fact confirmed by direct filesystem/git/PRAE read
      PARTIAL   - evidence exists but incomplete or stale
      UNKNOWN   - evidence cannot be determined from available sources

    Promotion thresholds:
      VERIFIED  : all critical facts confirmed
      PARTIAL   : some critical facts confirmed, others UNKNOWN/PARTIAL
      UNKNOWN   : project root absent or no evidence readable

.PARAMETER Evidence
    PSCustomObject from PRAE-EvidenceCollector.
.PARAMETER ProjectName
    Project key (used for registry writes).
.PARAMETER WriteToRegistry
    If set, calls PRAE-TruthRegistry.ps1 to persist the evaluation.
.PARAMETER RegistryRoot
    Default: D:\BossMind\bossmind-shared\prae\truth-registry
.PARAMETER TruthRegistryScript
    Default: D:\BossMind\bossmind-shared\prae\PRAE-TruthRegistry.ps1
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [PSCustomObject]$Evidence,

    [Parameter(Mandatory)]
    [string]$ProjectName,

    [switch]$WriteToRegistry,

    [string]$RegistryRoot       = "D:\BossMind\bossmind-shared\prae\truth-registry",
    [string]$TruthRegistryScript = "D:\BossMind\bossmind-shared\prae\PRAE-TruthRegistry.ps1"
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Variable -Name GOV_MODE    -Value "LOCKED"  -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION -Value "NONE"   -Option ReadOnly -Force

$UNKNOWN = "UNKNOWN"
$PARTIAL = "PARTIAL"

# -- Fact builder helpers --------------------------------------
function New-Fact {
    param([string]$Category, [string]$Key, $Value, [string]$Confidence, [string]$Detail = "")
    return [PSCustomObject]@{
        category   = $Category
        key        = $Key
        value      = $Value
        confidence = $Confidence
        detail     = $Detail
    }
}

function Safe-Prop {
    param($Obj, [string]$Key, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        return if ($Obj.Contains($Key)) { $Obj[$Key] } else { $Default }
    }
    if ($Obj.PSObject.Properties[$Key]) { return $Obj.$Key }
    return $Default
}

$verified = [System.Collections.Generic.List[PSCustomObject]]::new()
$partial  = [System.Collections.Generic.List[PSCustomObject]]::new()
$unknown  = [System.Collections.Generic.List[PSCustomObject]]::new()
$missing  = [System.Collections.Generic.List[PSCustomObject]]::new()

# -- Evaluate FILESYSTEM evidence -----------------------------
$fs = $Evidence.filesystem

$rootExists = Safe-Prop $fs "project_root_exists" $false
if ($rootExists -eq $true) {
    $verified.Add((New-Fact "filesystem" "project_root_exists" $true "VERIFIED" "Directory confirmed on disk"))
} else {
    $unknown.Add((New-Fact "filesystem" "project_root_exists" $false "UNKNOWN" "Project root not found"))
    $missing.Add([PSCustomObject]@{
        category       = "filesystem"
        item           = "project_root"
        status         = "MISSING"
        action_required= "Create project directory at $($Evidence.project_root)"
        priority       = "CRITICAL"
    })
}

# package.json
$pkg = Safe-Prop $fs "package_json"
if ($pkg -and (Safe-Prop $pkg "exists") -eq $true) {
    $name = Safe-Prop $pkg "name" $UNKNOWN
    $ver  = Safe-Prop $pkg "version" $UNKNOWN
    if ($name -ne $UNKNOWN) {
        $verified.Add((New-Fact "filesystem" "package_json.name" $name "VERIFIED" "Read from package.json"))
        $verified.Add((New-Fact "filesystem" "package_json.version" $ver "VERIFIED" "Read from package.json"))
        $verified.Add((New-Fact "filesystem" "package_json.dep_count" (Safe-Prop $pkg "dep_count" $UNKNOWN) "VERIFIED" "Read from package.json"))
    } else {
        $partial.Add((New-Fact "filesystem" "package_json" "exists-but-malformed" "PARTIAL" "File exists but could not parse name/version"))
        $missing.Add([PSCustomObject]@{ category="filesystem"; item="package_json.name"; status="PARTIAL"; action_required="Validate package.json is well-formed JSON"; priority="HIGH" })
    }
} elseif ($pkg -and (Safe-Prop $pkg "exists") -eq $false) {
    $unknown.Add((New-Fact "filesystem" "package_json" $false "UNKNOWN" "package.json not found"))
    $missing.Add([PSCustomObject]@{ category="filesystem"; item="package_json"; status="MISSING"; action_required="Create package.json  -  run npm init"; priority="CRITICAL" })
}

# package-lock
$lock = Safe-Prop $fs "package_lock"
if ($lock -and (Safe-Prop $lock "exists") -eq $true) {
    $nodeValid = Safe-Prop $lock "node_valid" $UNKNOWN
    if ($nodeValid -eq $true) {
        $verified.Add((New-Fact "filesystem" "package_lock.valid" $true "VERIFIED" "node JSON.parse confirmed"))
    } elseif ($nodeValid -eq $UNKNOWN) {
        $partial.Add((New-Fact "filesystem" "package_lock.valid" $UNKNOWN "PARTIAL" "Node.js not available for validation"))
    } else {
        $unknown.Add((New-Fact "filesystem" "package_lock.valid" $false "UNKNOWN" "node JSON.parse failed  -  lock file corrupt"))
        $missing.Add([PSCustomObject]@{ category="filesystem"; item="package_lock.json"; status="PARTIAL"; action_required="Run npm install to regenerate package-lock.json"; priority="HIGH" })
    }
} elseif ($lock -and (Safe-Prop $lock "exists") -eq $false) {
    $unknown.Add((New-Fact "filesystem" "package_lock" $false "UNKNOWN" "package-lock.json not found"))
    $missing.Add([PSCustomObject]@{ category="filesystem"; item="package_lock.json"; status="MISSING"; action_required="Run npm install to generate package-lock.json"; priority="HIGH" })
}

# env file
$env = Safe-Prop $fs "env_file"
if ($env -and (Safe-Prop $env "exists") -eq $true) {
    $missingKeys = @(Safe-Prop $env "required_keys_missing" @())
    $stripeMode  = Safe-Prop $env "stripe_mode" $UNKNOWN
    if (@($missingKeys).Count -eq 0) {
        $verified.Add((New-Fact "filesystem" "env_file.required_keys" "present" "VERIFIED" "All required env keys found (values not read)"))
    } else {
        $partial.Add((New-Fact "filesystem" "env_file.required_keys" "incomplete" "PARTIAL" "Missing: $($missingKeys -join ', ')"))
        foreach ($k in $missingKeys) {
            $missing.Add([PSCustomObject]@{ category="env"; item=$k; status="MISSING"; action_required="Add $k to .env file"; priority="HIGH" })
        }
    }
    if ($stripeMode -eq "LIVE") {
        $verified.Add((New-Fact "filesystem" "env_file.stripe_mode" "LIVE" "VERIFIED" "STRIPE_SECRET_KEY prefix confirmed sk_live_ (value not read)"))
    } elseif ($stripeMode -eq "TEST") {
        $partial.Add((New-Fact "filesystem" "env_file.stripe_mode" "TEST" "PARTIAL" "STRIPE_SECRET_KEY is test mode"))
        $missing.Add([PSCustomObject]@{ category="env"; item="STRIPE_SECRET_KEY"; status="PARTIAL"; action_required="Switch STRIPE_SECRET_KEY to live sk_live_ for production"; priority="MEDIUM" })
    } else {
        $unknown.Add((New-Fact "filesystem" "env_file.stripe_mode" $UNKNOWN "UNKNOWN" "Cannot determine Stripe mode"))
    }
} elseif ($env -and (Safe-Prop $env "exists") -eq $false) {
    $unknown.Add((New-Fact "filesystem" "env_file" $false "UNKNOWN" "No .env file found"))
    $missing.Add([PSCustomObject]@{ category="filesystem"; item=".env"; status="MISSING"; action_required="Create .env file with required keys"; priority="CRITICAL" })
}

# build config
$build = Safe-Prop $fs "build_config"
if ($build -and (Safe-Prop $build "exists") -eq $true) {
    $verified.Add((New-Fact "filesystem" "build_config" (Safe-Prop $build "filename" "present") "VERIFIED" "Build config confirmed on disk"))
} else {
    $unknown.Add((New-Fact "filesystem" "build_config" $false "UNKNOWN" "No next.config.* found"))
    $missing.Add([PSCustomObject]@{ category="filesystem"; item="next.config.*"; status="MISSING"; action_required="Create next.config.js/mjs"; priority="MEDIUM" })
}

# deploy config
$deploy = Safe-Prop $fs "deploy_config"
if ($deploy -and (Safe-Prop $deploy "exists") -eq $true) {
    $verified.Add((New-Fact "filesystem" "deploy_config" (Safe-Prop $deploy "filename" "present") "VERIFIED" "Deploy config confirmed on disk"))
} else {
    $unknown.Add((New-Fact "filesystem" "deploy_config" $false "UNKNOWN" "No railway.json/toml or render.yaml found"))
    $missing.Add([PSCustomObject]@{ category="filesystem"; item="deploy_config"; status="MISSING"; action_required="Create railway.json or render.yaml"; priority="MEDIUM" })
}

# node_modules
$nm = Safe-Prop $fs "node_modules"
if ($nm -and (Safe-Prop $nm "exists") -eq $true) {
    $verified.Add((New-Fact "filesystem" "node_modules" $true "VERIFIED" "node_modules directory present"))
} else {
    $unknown.Add((New-Fact "filesystem" "node_modules" $false "UNKNOWN" "node_modules absent"))
    $missing.Add([PSCustomObject]@{ category="filesystem"; item="node_modules"; status="MISSING"; action_required="Run npm install"; priority="HIGH" })
}

# -- Evaluate GIT evidence -------------------------------------
$git = $Evidence.git
if ((Safe-Prop $git "available") -eq $true) {
    $branch = Safe-Prop $git "branch" $UNKNOWN
    $commit = Safe-Prop $git "commit" $UNKNOWN
    $clean  = Safe-Prop $git "clean"  $UNKNOWN

    if ($branch -ne $UNKNOWN) {
        $verified.Add((New-Fact "git" "branch" $branch "VERIFIED" "From git rev-parse --abbrev-ref HEAD"))
    } else {
        $unknown.Add((New-Fact "git" "branch" $UNKNOWN "UNKNOWN" "git command returned no branch"))
    }
    if ($commit -ne $UNKNOWN) {
        $verified.Add((New-Fact "git" "commit" $commit "VERIFIED" "From git rev-parse --short HEAD"))
    }
    if ($clean -eq $true) {
        $verified.Add((New-Fact "git" "working_tree_clean" $true "VERIFIED" "git status --porcelain returned empty"))
    } elseif ($clean -eq $false) {
        $partial.Add((New-Fact "git" "working_tree_clean" $false "PARTIAL" "Uncommitted changes present"))
        $missing.Add([PSCustomObject]@{ category="git"; item="uncommitted_changes"; status="PARTIAL"; action_required="Commit or stash changes before deployment"; priority="MEDIUM" })
    }
    $lastMsg = Safe-Prop $git "last_message" $UNKNOWN
    if ($lastMsg -ne $UNKNOWN) {
        $verified.Add((New-Fact "git" "last_commit_message" $lastMsg "VERIFIED" "From git log --oneline -1"))
    }
} else {
    $unknown.Add((New-Fact "git" "git_available" $false "UNKNOWN" "git not in PATH or .git directory absent"))
    $missing.Add([PSCustomObject]@{ category="git"; item="git_repository"; status="MISSING"; action_required="Initialise git repository or ensure git is in PATH"; priority="MEDIUM" })
}

# -- Evaluate PRAE evidence ------------------------------------
$prae = $Evidence.prae

# Relay
$relay = Safe-Prop $prae "relay_heartbeat"
if ($relay -and (Safe-Prop $relay "exists") -eq $true) {
    $ageS  = Safe-Prop $relay "age_seconds" $UNKNOWN
    $active= Safe-Prop $relay "active" $false
    if ($active -eq $true) {
        $verified.Add((New-Fact "prae" "relay_heartbeat.active" $true "VERIFIED" "Heartbeat age ${ageS}s (within 600s window)"))
    } else {
        $partial.Add((New-Fact "prae" "relay_heartbeat.active" $false "PARTIAL" "Heartbeat exists but stale (age=${ageS}s)"))
        $missing.Add([PSCustomObject]@{ category="prae"; item="relay_heartbeat"; status="PARTIAL"; action_required="Run PRAE-RelayRefresh.ps1 to restore relay active status"; priority="HIGH" })
    }
} else {
    $unknown.Add((New-Fact "prae" "relay_heartbeat" $false "UNKNOWN" "relay-heartbeat.json not found"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="relay_heartbeat.json"; status="MISSING"; action_required="Run PRAE-RelayRefresh.ps1 to create relay heartbeat"; priority="HIGH" })
}

# PRAE registry
$reg = Safe-Prop $prae "prae_registry"
if ($reg -and (Safe-Prop $reg "exists") -eq $true) {
    $integ = Safe-Prop $reg "integrity_status" $UNKNOWN
    if ($integ -eq "VERIFIED") {
        $verified.Add((New-Fact "prae" "prae_registry.integrity" "VERIFIED" "VERIFIED" "integrity_status=VERIFIED from registry file"))
    } else {
        $partial.Add((New-Fact "prae" "prae_registry.integrity" $integ "PARTIAL" "Registry exists but integrity_status=$integ"))
    }
} else {
    $unknown.Add((New-Fact "prae" "prae_registry" $false "UNKNOWN" "prae-runtime-registry.json not found"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="prae_registry"; status="MISSING"; action_required="Run Install-PRAEAuthorityGate.ps1 to create registry"; priority="HIGH" })
}

# Authority manifest
$manif = Safe-Prop $prae "authority_manifest"
if ($manif -and (Safe-Prop $manif "exists") -eq $true) {
    $mode = Safe-Prop $manif "authority_mode" $UNKNOWN
    if ($mode -eq "ENFORCEMENT_ACTIVE") {
        $verified.Add((New-Fact "prae" "authority_manifest.mode" "ENFORCEMENT_ACTIVE" "VERIFIED" "Manifest confirms ENFORCEMENT_ACTIVE"))
    } else {
        $partial.Add((New-Fact "prae" "authority_manifest.mode" $mode "PARTIAL" "Manifest exists but mode=$mode"))
    }
} else {
    $unknown.Add((New-Fact "prae" "authority_manifest" $false "UNKNOWN" "prae-execution-authority.json not found"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="authority_manifest"; status="MISSING"; action_required="Run Install-PRAEAuthorityGate.ps1 to deploy authority manifest"; priority="CRITICAL" })
}

# Violations log
$vlog = Safe-Prop $prae "violations_log"
if ($vlog -and (Safe-Prop $vlog "exists") -eq $true) {
    $lc = Safe-Prop $vlog "line_count" $UNKNOWN
    $verified.Add((New-Fact "prae" "violations_log.exists" $true "VERIFIED" "Append-only log present ($lc lines)"))
} else {
    $partial.Add((New-Fact "prae" "violations_log" $false "PARTIAL" "violations log not yet created"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="violations_log"; status="MISSING"; action_required="Run PRAE-ActivateAndValidate.ps1 to initialise violation ledger"; priority="MEDIUM" })
}

# Checksum registry
$chkReg = Safe-Prop $prae "checksum_registry"
if ($chkReg -and (Safe-Prop $chkReg "exists") -eq $true) {
    $ageS = Safe-Prop $chkReg "age_seconds" $UNKNOWN
    $fc   = Safe-Prop $chkReg "file_count"  $UNKNOWN
    if ($ageS -ne $UNKNOWN -and [int]$ageS -lt 86400) {
        $verified.Add((New-Fact "prae" "checksum_registry" "current" "VERIFIED" "Registry present, $fc files, updated ${ageS}s ago"))
    } else {
        $partial.Add((New-Fact "prae" "checksum_registry" "stale" "PARTIAL" "Registry exists but may be stale (age=${ageS}s)"))
        $missing.Add([PSCustomObject]@{ category="prae"; item="checksum_registry"; status="PARTIAL"; action_required="Run PRAE-A1-Watcher-Resumora.ps1 -Snapshot to refresh"; priority="MEDIUM" })
    }
} else {
    $unknown.Add((New-Fact "prae" "checksum_registry" $false "UNKNOWN" "Checksum registry not found"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="checksum_registry"; status="MISSING"; action_required="Run PRAE-A1-Watcher-Resumora.ps1 -Snapshot to create baseline"; priority="HIGH" })
}

# Rollback checkpoint
$rollb = Safe-Prop $prae "rollback_checkpoint"
if ($rollb -and (Safe-Prop $rollb "exists") -eq $true) {
    $ageS = Safe-Prop $rollb "age_seconds" $UNKNOWN
    $fc   = Safe-Prop $rollb "file_count"  $UNKNOWN
    if ($ageS -ne $UNKNOWN -and [int]$ageS -lt 172800) {
        $verified.Add((New-Fact "prae" "rollback_checkpoint" "valid" "VERIFIED" "Checkpoint present, $fc files, age ${ageS}s"))
    } else {
        $partial.Add((New-Fact "prae" "rollback_checkpoint" "stale" "PARTIAL" "Checkpoint older than 48h (age=${ageS}s)"))
        $missing.Add([PSCustomObject]@{ category="prae"; item="rollback_checkpoint"; status="PARTIAL"; action_required="Run PRAE-A1-Watcher-Resumora.ps1 -Snapshot to refresh checkpoint"; priority="MEDIUM" })
    }
} else {
    $unknown.Add((New-Fact "prae" "rollback_checkpoint" $false "UNKNOWN" "Rollback checkpoint not found"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="rollback_checkpoint"; status="MISSING"; action_required="Run PRAE-A1-Watcher-Resumora.ps1 -Snapshot to create rollback checkpoint"; priority="HIGH" })
}

# Last deployment validation
$deplVal = Safe-Prop $prae "last_deployment_validation"
if ($deplVal -and (Safe-Prop $deplVal "exists") -eq $true) {
    $overall = Safe-Prop $deplVal "overall" $UNKNOWN
    $ageS    = Safe-Prop $deplVal "age_seconds" $UNKNOWN
    if ($overall -eq "ALL_VALIDATIONS_PASS") {
        $verified.Add((New-Fact "prae" "deployment_validation" "ALL_VALIDATIONS_PASS" "VERIFIED" "Last A2 run passed all domains (age=${ageS}s)"))
    } elseif ($overall -eq "DEPLOYMENT_BLOCKED") {
        $partial.Add((New-Fact "prae" "deployment_validation" "DEPLOYMENT_BLOCKED" "PARTIAL" "Last A2 run blocked deployment"))
        $missing.Add([PSCustomObject]@{ category="prae"; item="deployment_validation"; status="PARTIAL"; action_required="Run PRAE-A2-DeployValidate-Resumora.ps1 and fix blocked domains"; priority="HIGH" })
    } else {
        $partial.Add((New-Fact "prae" "deployment_validation" $overall "PARTIAL" "Deployment validation status: $overall"))
    }
} else {
    $unknown.Add((New-Fact "prae" "deployment_validation" $false "UNKNOWN" "No deployment validation records found"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="deployment_validation"; status="MISSING"; action_required="Run PRAE-A2-DeployValidate-Resumora.ps1"; priority="HIGH" })
}

# Runtime graph node
$graphNode = Safe-Prop $prae "runtime_graph_node"
if ($graphNode -and (Safe-Prop $graphNode "exists") -eq $true) {
    $valOv  = Safe-Prop $graphNode "validation_overall" $UNKNOWN
    $watch  = Safe-Prop $graphNode "watcher_status"     $UNKNOWN
    $risk   = Safe-Prop $graphNode "risk_score"         $UNKNOWN
    $verified.Add((New-Fact "prae" "runtime_graph.validation" $valOv "VERIFIED" "From bossmind-runtime-graph.json"))
    $verified.Add((New-Fact "prae" "runtime_graph.watcher"    $watch "VERIFIED" "From bossmind-runtime-graph.json"))
    $verified.Add((New-Fact "prae" "runtime_graph.risk"       $risk  "VERIFIED" "From bossmind-runtime-graph.json"))
} else {
    $unknown.Add((New-Fact "prae" "runtime_graph_node" $false "UNKNOWN" "Project node not in runtime graph"))
    $missing.Add([PSCustomObject]@{ category="prae"; item="runtime_graph_node"; status="MISSING"; action_required="Run PRAE-A2-DeployValidate-Resumora.ps1 to populate runtime graph"; priority="MEDIUM" })
}

# -- Evaluate PRAE RUNTIME evidence ---------------------------
$rt = $Evidence.prae_runtime
if ((Safe-Prop $rt "module_exists") -eq $true) {
    if ((Safe-Prop $rt "module_importable") -eq $true) {
        $verified.Add((New-Fact "prae_runtime" "module_importable" $true "VERIFIED" "PRAE-ExecutionGate.psm1 imports cleanly"))
        $gateResult = Safe-Prop $rt "gate_result" $UNKNOWN
        if ($gateResult -eq "AUTHORIZED") {
            $verified.Add((New-Fact "prae_runtime" "gate_callable.prae:governance:read" "AUTHORIZED" "VERIFIED" "Gate authorised prae:governance:read scope"))
        } elseif ($gateResult -ne $UNKNOWN) {
            $partial.Add((New-Fact "prae_runtime" "gate_callable" $gateResult "PARTIAL" "Gate returned: $gateResult"))
            $missing.Add([PSCustomObject]@{ category="prae_runtime"; item="gate_authorization"; status="PARTIAL"; action_required="Run PRAE-ActivateAndValidate.ps1 to restore gate authorization"; priority="HIGH" })
        }
    } else {
        $partial.Add((New-Fact "prae_runtime" "module_importable" $false "PARTIAL" "Module exists but import failed"))
        $missing.Add([PSCustomObject]@{ category="prae_runtime"; item="module_import"; status="PARTIAL"; action_required="Redeploy PRAE-ExecutionGate.psm1 (check encoding)"; priority="HIGH" })
    }
} else {
    $unknown.Add((New-Fact "prae_runtime" "module_exists" $false "UNKNOWN" "PRAE-ExecutionGate.psm1 not found"))
    $missing.Add([PSCustomObject]@{ category="prae_runtime"; item="PRAE-ExecutionGate.psm1"; status="MISSING"; action_required="Run Install-PRAEAuthorityGate.ps1 to deploy gate module"; priority="CRITICAL" })
}

# -- Compute overall confidence --------------------------------
$vCount = @($verified).Count
$pCount = @($partial).Count
$uCount = @($unknown).Count
$mCount = @($missing).Count

$hasCriticalMissing = @($missing | Where-Object { $_.priority -eq "CRITICAL" }).Count -gt 0
$hasHighMissing     = @($missing | Where-Object { $_.priority -eq "HIGH"     }).Count -gt 0

$overallConfidence =
    if ($hasCriticalMissing) { "UNKNOWN"  }
    elseif ($hasHighMissing -or $pCount -gt $vCount) { "PARTIAL"  }
    elseif ($uCount -eq 0 -and $pCount -eq 0) { "VERIFIED" }
    elseif ($vCount -gt 0 -and $vCount -ge ($uCount + $pCount)) { "PARTIAL" }
    else { "UNKNOWN" }

# -- Build promotion record ------------------------------------
$promotionRecord = [PSCustomObject][ordered]@{
    project_name          = $ProjectName
    overall_confidence    = $overallConfidence
    evidence_collected_at = $Evidence.collected_at
    evaluated_at          = [DateTimeOffset]::UtcNow.ToString("o")
    governance_mode       = $GOV_MODE
    production_mutation   = $GOV_MUTATION
    evidence_summary      = [ordered]@{
        verified_count = $vCount
        partial_count  = $pCount
        unknown_count  = $uCount
        missing_count  = $mCount
    }
    verified_facts        = @($verified)
    partial_facts         = @($partial)
    unknown_facts         = @($unknown)
    missing_partials      = @($missing)
}

# -- Optionally write to registry -----------------------------
if ($WriteToRegistry -and (Test-Path $TruthRegistryScript)) {
    & $TruthRegistryScript -Action Write -ProjectName $ProjectName -Record $promotionRecord -RegistryRoot $RegistryRoot
}

Write-Verbose "PRAE-MemoryPromotionGate: $ProjectName -> $overallConfidence (V:$vCount P:$pCount U:$uCount M:$mCount)"
return $promotionRecord
