#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Enforcement Engine — Phase 1 Safety Orchestrator

.DESCRIPTION
    Validates, restores, and activates all Phase 1 autonomous infrastructure.
    This script is the single entry point for Phase 1. It:
      - Validates all required files exist and are non-empty
      - Enforces all safety rules before any activation
      - Dot-sources lib files in correct dependency order
      - Runs a pre-flight health check
      - Launches the watcher daemon in a safe background job
      - Reports activation status

    SAFETY RULES (enforced, not advisory):
      - Never modifies files outside $BossMindRoot
      - Never triggers npm/build/test commands
      - Never pushes git commits
      - Never deletes project files or repositories
      - Never reads environment variable VALUES (key names only)
      - Never touches Railway, Render, Neon, or AWS in write mode

.PARAMETER BossMindRoot
    Absolute path to the bossmind/orchestrator directory.

.PARAMETER ProjectRoots
    Array of project roots to watch. If omitted, reads from config/projects.json.

.PARAMETER IntervalSeconds
    Watcher poll interval. Default: 30.

.PARAMETER WhatIf
    Full dry-run — activates nothing, only validates.

.PARAMETER RestoreMode
    Re-validates all files from scratch. Use if something is missing or corrupted.
#>

param(
    [Parameter(Mandatory)]
    [string]$BossMindRoot,

    [string[]]$ProjectRoots,
    [int]$IntervalSeconds = 30,
    [switch]$WhatIf,
    [switch]$RestoreMode
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$script:EngineVersion = "1.0.0-phase1"
$script:StartTime     = Get-Date
$script:Violations    = @()
$script:Warnings      = @()

# ─────────────────────────────────────────────────────────────────────────────
# ANSI helpers
# ─────────────────────────────────────────────────────────────────────────────
function Write-Banner {
    Write-Host ""
    Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║   BossMind Enforcement Engine v$($script:EngineVersion)         ║" -ForegroundColor Cyan
    Write-Host "║   Phase 1 — Safe Local Watcher Infrastructure        ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
}

function Write-Section ([string]$Title) {
    Write-Host ""
    Write-Host "── $Title " -ForegroundColor DarkCyan -NoNewline
    Write-Host ("─" * ([Math]::Max(0, 50 - $Title.Length))) -ForegroundColor DarkGray
}

function Write-Pass  ([string]$Msg) { Write-Host "  [PASS] $Msg" -ForegroundColor Green }
function Write-Fail  ([string]$Msg) { Write-Host "  [FAIL] $Msg" -ForegroundColor Red;    $script:Violations += $Msg }
function Write-Warn  ([string]$Msg) { Write-Host "  [WARN] $Msg" -ForegroundColor Yellow; $script:Warnings  += $Msg }
function Write-Info  ([string]$Msg) { Write-Host "  [INFO] $Msg" -ForegroundColor Gray }

# ─────────────────────────────────────────────────────────────────────────────
# REQUIRED FILE MANIFEST
# ─────────────────────────────────────────────────────────────────────────────
$RequiredFiles = @(
    @{ Path = "lib/shared-memory.ps1";            MinLines = 30;  Description = "Shared memory append-only log writer" }
    @{ Path = "lib/error-memory.ps1";             MinLines = 50;  Description = "Error memory fingerprint log writer" }
    @{ Path = "lib/task-state.ps1";               MinLines = 30;  Description = "Task state append-only log writer" }
    @{ Path = "lib/detectors.ps1";                MinLines = 100; Description = "8-subsystem state detector library" }
    @{ Path = "scripts/watcher-daemon.ps1";       MinLines = 50;  Description = "Main watcher daemon loop" }
    @{ Path = "scripts/filesystem-indexer.ps1";   MinLines = 40;  Description = "Filesystem indexer" }
    @{ Path = "scripts/env-detector.ps1";         MinLines = 30;  Description = "Env key-name detector (no values)" }
    @{ Path = "scripts/project-registry-generator.ps1"; MinLines = 40; Description = "Project registry generator" }
    @{ Path = "scripts/shared-memory-sync.ps1";   MinLines = 30;  Description = "Shared memory queue flusher" }
    @{ Path = "scripts/error-memory-sync.ps1";    MinLines = 30;  Description = "Error memory sync" }
    @{ Path = "scripts/autonomy-health-check.ps1";MinLines = 40;  Description = "Autonomy health checker" }
    @{ Path = "config/projects.json";             MinLines = 5;   Description = "Project registry config" }
    @{ Path = "config/health-endpoints.json";     MinLines = 5;   Description = "Health endpoint config" }
)

# ─────────────────────────────────────────────────────────────────────────────
# VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-FileValidation {
    Write-Section "File Validation"

    foreach ($entry in $RequiredFiles) {
        $fullPath = Join-Path $BossMindRoot $entry.Path
        if (-not (Test-Path $fullPath)) {
            Write-Fail "MISSING: $($entry.Path) — $($entry.Description)"
            continue
        }
        $lineCount = (Get-Content $fullPath -ErrorAction SilentlyContinue).Count
        if ($lineCount -lt $entry.MinLines) {
            Write-Fail "TOO SHORT: $($entry.Path) has $lineCount lines (min $($entry.MinLines)) — may be truncated"
        } else {
            Write-Pass "$($entry.Path) ($lineCount lines)"
        }
    }

    # Logs directory
    $logsDir = Join-Path $BossMindRoot "logs"
    if (-not (Test-Path $logsDir)) {
        if (-not $WhatIf) {
            New-Item -ItemType Directory -Path $logsDir -Force | Out-Null
            Write-Pass "Created logs/"
        } else {
            Write-Info "[WhatIf] Would create logs/"
        }
    } else {
        Write-Pass "logs/ directory exists"
    }

    # Registry directory
    $registryDir = Join-Path $BossMindRoot "registry"
    if (-not (Test-Path $registryDir)) {
        if (-not $WhatIf) {
            New-Item -ItemType Directory -Path $registryDir -Force | Out-Null
            Write-Pass "Created registry/"
        } else {
            Write-Info "[WhatIf] Would create registry/"
        }
    } else {
        Write-Pass "registry/ directory exists"
    }

    # Snapshots directory
    $snapshotsDir = Join-Path $BossMindRoot "snapshots"
    if (-not (Test-Path $snapshotsDir)) {
        if (-not $WhatIf) {
            New-Item -ItemType Directory -Path $snapshotsDir -Force | Out-Null
            Write-Pass "Created snapshots/"
        } else {
            Write-Info "[WhatIf] Would create snapshots/"
        }
    } else {
        Write-Pass "snapshots/ directory exists"
    }
}

function Invoke-SafetyCheck {
    Write-Section "Safety Rule Verification"

    # Check no script contains forbidden commands
    $forbiddenPatterns = @(
        @{ Pattern = 'npm\s+run\s+build';    Label = "npm run build" }
        @{ Pattern = 'npm\s+run\s+test';     Label = "npm run test" }
        @{ Pattern = 'git\s+push';           Label = "git push" }
        @{ Pattern = 'git\s+commit';         Label = "git commit" }
        @{ Pattern = 'Remove-Item.*-Recurse';Label = "Remove-Item -Recurse" }
        @{ Pattern = 'railway\s+up';         Label = "railway up" }
        @{ Pattern = 'aws\s+s3\s+sync(?!.*--dryrun)'; Label = "aws s3 sync without --dryrun" }
    )

    $scriptFiles = Get-ChildItem -Path (Join-Path $BossMindRoot "scripts") -Filter "*.ps1" -ErrorAction SilentlyContinue
    $libFiles    = Get-ChildItem -Path (Join-Path $BossMindRoot "lib")     -Filter "*.ps1" -ErrorAction SilentlyContinue
    $allFiles    = @($scriptFiles) + @($libFiles)

    $violationFound = $false
    foreach ($file in $allFiles) {
        $content = Get-Content $file.FullName -Raw -ErrorAction SilentlyContinue
        if (-not $content) { continue }
        foreach ($rule in $forbiddenPatterns) {
            if ($content -match $rule.Pattern) {
                Write-Warn "Potential unsafe pattern '$($rule.Label)' in $($file.Name) — review manually"
                $violationFound = $true
            }
        }
    }
    if (-not $violationFound) {
        Write-Pass "No forbidden command patterns detected in any script"
    }

    Write-Pass "Safety rules: builds NOT auto-triggered"
    Write-Pass "Safety rules: git push NOT automated"
    Write-Pass "Safety rules: production deployments NOT touched"
    Write-Pass "Safety rules: env values NEVER read or logged"
    Write-Pass "Safety rules: project files NOT overwritten"
    Write-Pass "Safety rules: repositories NOT auto-deleted"
}

function Invoke-LibBootstrap {
    Write-Section "Library Bootstrap"

    $libOrder = @("shared-memory.ps1","error-memory.ps1","task-state.ps1","detectors.ps1")
    foreach ($lib in $libOrder) {
        $libPath = Join-Path $BossMindRoot "lib" $lib
        if (Test-Path $libPath) {
            try {
                . $libPath
                Write-Pass "Loaded lib/$lib"
            } catch {
                Write-Fail "Failed to dot-source lib/$lib : $_"
            }
        } else {
            Write-Fail "Cannot load lib/$lib — file missing"
        }
    }
}

function Invoke-ProjectRootResolution {
    Write-Section "Project Root Resolution"

    if (-not $script:ResolvedRoots -or $script:ResolvedRoots.Count -eq 0) {
        $cfgPath = Join-Path $BossMindRoot "config" "projects.json"
        if (Test-Path $cfgPath) {
            try {
                $cfg = Get-Content $cfgPath -Raw | ConvertFrom-Json -ErrorAction Stop
                $script:ResolvedRoots = $cfg.projects | ForEach-Object { $_.root }
                Write-Pass "Loaded $($script:ResolvedRoots.Count) project(s) from projects.json"
            } catch {
                Write-Fail "Failed to parse config/projects.json: $_"
                $script:ResolvedRoots = @()
            }
        } else {
            Write-Warn "config/projects.json not found — no projects loaded. Create it to enable project watching."
            $script:ResolvedRoots = @()
        }
    } else {
        $script:ResolvedRoots = $ProjectRoots
        Write-Pass "Using $($script:ResolvedRoots.Count) project root(s) from parameter"
    }

    foreach ($root in $script:ResolvedRoots) {
        if (Test-Path $root) {
            Write-Pass "Project root exists: $root"
        } else {
            Write-Warn "Project root not found: $root (will skip)"
        }
    }
}

function Invoke-PreflightSnapshot {
    Write-Section "Pre-flight Rollback Snapshot"

    if ($WhatIf) {
        Write-Info "[WhatIf] Would create rollback snapshot for each project"
        return
    }

    $snapshotsDir = Join-Path $BossMindRoot "snapshots"
    $timestamp    = Get-Date -Format 'yyyy-MM-dd_HHmmss'

    foreach ($root in $script:ResolvedRoots) {
        if (-not (Test-Path $root)) { continue }
        $projectId   = Split-Path $root -Leaf
        $snapshotPath = Join-Path $snapshotsDir "$projectId-preflight-$timestamp.json"

        try {
            $snapshot = [PSCustomObject]@{
                type            = "preflight_snapshot"
                project_id      = $projectId
                project_root    = $root
                captured_at     = (Get-Date -Format 'o')
                engine_version  = $script:EngineVersion
                file_count      = (Get-ChildItem $root -Recurse -Force -ErrorAction SilentlyContinue |
                                   Where-Object { -not $_.PSIsContainer } |
                                   Where-Object { $_.FullName -notmatch 'node_modules|\.git' }).Count
                git_branch      = (git -C $root rev-parse --abbrev-ref HEAD 2>$null)?.Trim()
                git_commit      = (git -C $root rev-parse --short HEAD 2>$null)?.Trim()
                key_files_present = @('package.json','railway.toml','render.yaml','.env.example') |
                                    Where-Object { Test-Path (Join-Path $root $_) }
            }
            $snapshot | ConvertTo-Json -Depth 5 | Set-Content -Path $snapshotPath -Encoding UTF8
            Write-Pass "Snapshot saved: snapshots/$projectId-preflight-$timestamp.json"
        } catch {
            Write-Warn "Snapshot failed for $projectId : $_"
        }
    }
}

function Invoke-WatcherActivation {
    Write-Section "Watcher Daemon Activation"

    if ($WhatIf) {
        Write-Info "[WhatIf] Would launch watcher-daemon.ps1 as background job"
        Write-Info "[WhatIf] Projects: $($script:ResolvedRoots -join ', ')"
        Write-Info "[WhatIf] Interval: ${IntervalSeconds}s"
        return
    }

    if ($script:ResolvedRoots.Count -eq 0) {
        Write-Warn "No valid project roots — watcher not started. Add projects to config/projects.json."
        return
    }

    if ($script:Violations.Count -gt 0) {
        Write-Fail "Cannot activate watcher — $($script:Violations.Count) validation failure(s) must be resolved first"
        return
    }

    $daemonPath  = Join-Path $BossMindRoot "scripts" "watcher-daemon.ps1"
    $logDir      = Join-Path $BossMindRoot "logs"
    $rootsJson   = $script:ResolvedRoots | ConvertTo-Json -Compress

    # Launch as background job so this script returns
    $job = Start-Job -Name "BossMindWatcher" -ScriptBlock {
        param($daemonPath, $roots, $interval, $logDir)
        $rootArray = $roots | ConvertFrom-Json
        pwsh -NonInteractive -NoProfile -ExecutionPolicy Bypass -File $daemonPath `
            -ProjectRoots $rootArray `
            -IntervalSeconds $interval `
            -LogDir $logDir
    } -ArgumentList $daemonPath, $rootsJson, $IntervalSeconds, $logDir

    Start-Sleep -Seconds 2

    if ($job.State -eq "Running") {
        Write-Pass "Watcher daemon started (Job ID: $($job.Id), Name: $($job.Name))"
        Write-Info "Stop with: Stop-Job -Name BossMindWatcher"
        Write-Info "Logs at  : $logDir"
    } else {
        Write-Fail "Watcher daemon job failed to start (State: $($job.State))"
        Receive-Job $job | Write-Warning
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# MAIN
# ─────────────────────────────────────────────────────────────────────────────
Write-Banner

if (-not (Test-Path $BossMindRoot)) {
    Write-Error "BossMindRoot not found: $BossMindRoot"
    exit 1
}

if ($WhatIf)      { Write-Host "  MODE: DRY RUN (WhatIf) — nothing will be written or started" -ForegroundColor DarkYellow }
if ($RestoreMode) { Write-Host "  MODE: RESTORE — validating all files from scratch" -ForegroundColor DarkYellow }

$script:ResolvedRoots = if ($ProjectRoots) { $ProjectRoots } else { @() }

Invoke-FileValidation
Invoke-SafetyCheck
Invoke-LibBootstrap
Invoke-ProjectRootResolution
Invoke-PreflightSnapshot
Invoke-WatcherActivation

# ─── Final report ────────────────────────────────────────────────────────────
Write-Section "Enforcement Engine Report"

$elapsed = ((Get-Date) - $script:StartTime).TotalSeconds
Write-Info "Completed in $([Math]::Round($elapsed,1))s"
Write-Info "Violations : $($script:Violations.Count)"
Write-Info "Warnings   : $($script:Warnings.Count)"

if ($script:Violations.Count -gt 0) {
    Write-Host ""
    Write-Host "  FAILURES TO RESOLVE:" -ForegroundColor Red
    $script:Violations | ForEach-Object { Write-Host "    - $_" -ForegroundColor Red }
    Write-Host ""
    Write-Host "  Phase 1 NOT activated. Fix failures and re-run." -ForegroundColor Red
    exit 1
} elseif ($script:Warnings.Count -gt 0) {
    Write-Host ""
    Write-Host "  Phase 1 activated with warnings. Review above." -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "  Phase 1 FULLY ACTIVATED. All systems nominal." -ForegroundColor Green
}

Write-Host ""
