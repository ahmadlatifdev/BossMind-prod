#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Live State Watcher Daemon — Phase 1 (Full Integration)

.DESCRIPTION
    Polls all registered projects on a configurable interval.
    Per tick, for each project:
      1. Filesystem detection + indexing
      2. Git branch/repo state detection
      3. package.json command detection
      4. Env key-name detection (values NEVER captured)
      5. Build/test/lint error state (reads artifacts only)
      6. Deployment config detection (Railway, Render, GitHub Actions)
      7. AWS S3 sync drift detection
      8. Health endpoint probing

    Then:
      - Flushes state to shared_memory.jsonl (append-only)
      - Writes errors to error_memory.jsonl (append-only, fingerprinted)
      - Logs task transitions to task_state.jsonl (append-only)
      - Triggers filesystem-indexer and env-detector on change events
      - Updates service registry if project structure changed
      - Creates rollback snapshot if configured

    PHASE 1 SAFETY CONSTRAINTS (enforced):
      - Never modifies project files
      - Never runs npm/build/test commands
      - Never pushes git commits
      - Never deploys to Railway, Render, or any platform
      - Never exposes env variable values
      - Never deletes repositories or project files

.PARAMETER ProjectRoots
    Array of absolute project paths. Reads config/projects.json if omitted.

.PARAMETER IntervalSeconds
    Poll interval in seconds. Default: 30.

.PARAMETER LogDir
    JSONL log directory. Default: ../logs

.PARAMETER RegistryDir
    Registry output directory. Default: ../registry

.PARAMETER SnapshotDir
    Rollback snapshot directory. Default: ../snapshots

.PARAMETER NeonUrl
    Neon connection string. Reads BOSSMIND_NEON_URL env var if not passed.

.PARAMETER EnableFullIndex
    If set, runs full filesystem-indexer on every tick (slow for large projects).
    Default: indexes only on first tick, then on change detection.

.PARAMETER WhatIf
    Full dry-run — detects and reports but writes nothing.
#>

param(
    [string[]]$ProjectRoots,
    [int]$IntervalSeconds  = 30,
    [string]$LogDir        = (Join-Path $PSScriptRoot ".." "logs"),
    [string]$RegistryDir   = (Join-Path $PSScriptRoot ".." "registry"),
    [string]$SnapshotDir   = (Join-Path $PSScriptRoot ".." "snapshots"),
    [string]$NeonUrl       = $env:BOSSMIND_NEON_URL,
    [switch]$EnableFullIndex,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── Bootstrap ──────────────────────────────────────────────────────────────────
$libPath = Join-Path $PSScriptRoot ".." "lib"
. (Join-Path $libPath "shared-memory.ps1")
. (Join-Path $libPath "error-memory.ps1")
. (Join-Path $libPath "task-state.ps1")
. (Join-Path $libPath "detectors.ps1")

# Also load Phase 1 sync modules
$syncPath = $PSScriptRoot
. (Join-Path $syncPath "shared-memory-sync.ps1")
. (Join-Path $syncPath "error-memory-sync.ps1")

# ── Directory setup ────────────────────────────────────────────────────────────
foreach ($dir in @($LogDir, $RegistryDir, $SnapshotDir)) {
    if (-not (Test-Path $dir) -and -not $WhatIf) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }
}

$sharedMemoryLog = Join-Path $LogDir "shared_memory.jsonl"
$errorMemoryLog  = Join-Path $LogDir "error_memory.jsonl"
$taskStateLog    = Join-Path $LogDir "task_state.jsonl"

# ── Project root resolution ────────────────────────────────────────────────────
if (-not $ProjectRoots -or $ProjectRoots.Count -eq 0) {
    $cfgPath = Join-Path $PSScriptRoot ".." "config" "projects.json"
    if (Test-Path $cfgPath) {
        $cfg          = Get-Content $cfgPath -Raw | ConvertFrom-Json
        $ProjectRoots = $cfg.projects | ForEach-Object { $_.root }
    } else {
        Write-Error "No ProjectRoots and no config/projects.json found. Cannot start."
        exit 1
    }
}

# ── Baseline tracking (for change detection) ───────────────────────────────────
$script:LastFileCount  = @{}
$script:LastCommitHash = @{}
$script:TickCount      = 0

# ── Header ─────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host "╔══════════════════════════════════════════════════════╗" -ForegroundColor Cyan
Write-Host "║   BossMind Watcher Daemon — Phase 1                 ║" -ForegroundColor Cyan
Write-Host "╚══════════════════════════════════════════════════════╝" -ForegroundColor Cyan
Write-Host "  Projects  : $($ProjectRoots -join ' | ')"
Write-Host "  Interval  : ${IntervalSeconds}s"
Write-Host "  Log dir   : $LogDir"
Write-Host "  Registry  : $RegistryDir"
Write-Host "  Neon sync : $(if ($NeonUrl) { 'enabled' } else { 'disabled' })"
Write-Host "  WhatIf    : $WhatIf"
Write-Host "  Started   : $(Get-Date -Format 'o')"
Write-Host ""

# ── Per-tick processing ────────────────────────────────────────────────────────
function Invoke-ProjectTick {
    param([string]$Root, [int]$TickCount)

    $projectId = Split-Path $Root -Leaf

    if (-not (Test-Path $Root)) {
        Write-Warning "  [$projectId] Root not found — skipping"
        return
    }

    Write-TaskState -LogPath $taskStateLog -ProjectId $projectId `
        -TaskName "watcher-tick-$TickCount" -Status "running" -WhatIf:$WhatIf

    try {
        # ── 8 Detectors ───────────────────────────────────────────────────────
        $fsState     = Get-FilesystemState  -ProjectRoot $Root
        $gitState    = Get-GitState         -ProjectRoot $Root
        $pkgState    = Get-PackageCommands  -ProjectRoot $Root
        $envState    = Get-EnvKeyNames      -ProjectRoot $Root
        $buildState  = Get-BuildErrorState  -ProjectRoot $Root
        $deployState = Get-DeploymentConfig -ProjectRoot $Root
        $s3State     = Get-S3SyncState      -ProjectRoot $Root
        $healthState = Get-HealthState      -ProjectRoot $Root -ProjectId $projectId

        # ── Assemble snapshot ─────────────────────────────────────────────────
        $snapshot = [PSCustomObject]@{
            schema_version = "1.0-phase1"
            project_id     = $projectId
            project_root   = $Root
            tick           = $TickCount
            captured_at    = (Get-Date -Format 'o')
            filesystem     = $fsState
            git            = $gitState
            package        = $pkgState
            env_keys       = $envState
            build          = $buildState
            deployment     = $deployState
            s3_sync        = $s3State
            health         = $healthState
        }

        # ── Shared memory append ───────────────────────────────────────────────
        Write-SharedMemoryLog -LogPath $sharedMemoryLog -Snapshot $snapshot -WhatIf:$WhatIf

        # ── Neon sync (if configured) ──────────────────────────────────────────
        if ($NeonUrl -and -not $WhatIf) {
            Sync-SharedMemoryToNeon -NeonUrl $NeonUrl -Snapshot $snapshot
        }

        # ── Error aggregation ─────────────────────────────────────────────────
        $errors = [System.Collections.Generic.List[string]]::new()

        if ($buildState.has_errors)               { $errors.AddRange([string[]]$buildState.errors) }
        if ($healthState.degraded)                { $errors.AddRange([string[]]$healthState.failures) }
        if ($s3State.drift_detected)              { $errors.Add("s3_drift: $($s3State.drift_summary)") }
        if ($envState.gitignored_leaks.Count -gt 0) {
            $errors.Add("env_leak_risk: $($envState.gitignored_leaks -join ', ')")
        }
        if ($envState.missing_required.Count -gt 0) {
            $errors.Add("env_missing_keys: $($envState.missing_required -join ', ')")
        }

        if ($errors.Count -gt 0) {
            Write-ErrorMemoryLog -LogPath $errorMemoryLog -ProjectId $projectId `
                -Errors $errors.ToArray() -Snapshot $snapshot -WhatIf:$WhatIf
        }

        # ── Change detection → trigger indexer ───────────────────────────────
        $currentFileCount  = $fsState.total_files
        $currentCommitHash = $gitState.commit_hash
        $lastFileCount     = $script:LastFileCount[$projectId]
        $lastCommitHash    = $script:LastCommitHash[$projectId]

        $filesChanged  = ($lastFileCount  -ne $null) -and ($lastFileCount  -ne $currentFileCount)
        $commitChanged = ($lastCommitHash -ne $null) -and ($lastCommitHash -ne $currentCommitHash)
        $isFirstTick   = ($lastFileCount  -eq $null)

        $script:LastFileCount[$projectId]  = $currentFileCount
        $script:LastCommitHash[$projectId] = $currentCommitHash

        if ($isFirstTick -or $filesChanged -or $commitChanged -or $EnableFullIndex) {
            $reason = if ($isFirstTick) { "first tick" } elseif ($commitChanged) { "commit changed" } else { "file count changed" }
            Write-Host "  [$projectId] Triggering indexer ($reason)" -ForegroundColor DarkCyan

            if (-not $WhatIf) {
                $indexerPath = Join-Path $PSScriptRoot "filesystem-indexer.ps1"
                $envDetPath  = Join-Path $PSScriptRoot "env-detector.ps1"
                $regGenPath  = Join-Path $PSScriptRoot "project-registry-generator.ps1"

                if (Test-Path $indexerPath) {
                    & $indexerPath -ProjectRoots @($Root) -OutputDir $RegistryDir -SnapshotDir $SnapshotDir
                }
                if (Test-Path $envDetPath) {
                    & $envDetPath -ProjectRoots @($Root) -OutputDir $RegistryDir
                }
                if ($isFirstTick -or $commitChanged) {
                    if (Test-Path $regGenPath) {
                        & $regGenPath -ExplicitRoots @($Root) -OutputDir $RegistryDir
                    }
                }
            }
        }

        # ── Autonomous change log ─────────────────────────────────────────────
        if ($fsState.recently_changed.Count -gt 0 -and -not $WhatIf) {
            $changeLogPath = Join-Path $LogDir "change_log.jsonl"
            $changeRecord = [ordered]@{
                _type      = "change_event"
                _written   = (Get-Date -Format 'o')
                project_id = $projectId
                tick       = $TickCount
                files      = $fsState.recently_changed
                git_dirty  = $gitState.dirty
                git_branch = $gitState.branch
            }
            Add-Content -Path $changeLogPath -Value ($changeRecord | ConvertTo-Json -Compress) -Encoding UTF8
        }

        # ── Task done ─────────────────────────────────────────────────────────
        Write-TaskState -LogPath $taskStateLog -ProjectId $projectId `
            -TaskName "watcher-tick-$TickCount" -Status "done" -WhatIf:$WhatIf

        $statusColor = if ($errors.Count -gt 0) { "Yellow" } else { "Green" }
        $statusLabel = if ($errors.Count -gt 0) { "degraded ($($errors.Count) issue(s))" } else { "healthy" }
        Write-Host "  [$projectId] $statusLabel | files:$($fsState.total_files) | branch:$($gitState.branch) | keys:$($envState.key_names.Count)" `
            -ForegroundColor $statusColor

    } catch {
        Write-Warning "  [$projectId] Tick exception: $_"
        Write-ErrorMemoryLog -LogPath $errorMemoryLog -ProjectId $projectId `
            -Errors @("watcher_exception: $_") -Snapshot $null -WhatIf:$WhatIf
        Write-TaskState -LogPath $taskStateLog -ProjectId $projectId `
            -TaskName "watcher-tick-$TickCount" -Status "failed" -Detail "$_" -WhatIf:$WhatIf
    }
}

# ── Main loop ──────────────────────────────────────────────────────────────────
while ($true) {
    $script:TickCount++
    Write-Host "[tick $($script:TickCount)] $(Get-Date -Format 'o')" -ForegroundColor DarkGray

    foreach ($root in $ProjectRoots) {
        Invoke-ProjectTick -Root $root -TickCount $script:TickCount
    }

    # Flush shared memory queue
    $flushed = Invoke-QueueFlush -ErrorAction SilentlyContinue
    if ($flushed -gt 0) { Write-Verbose "  Queue flushed: $flushed item(s)" }

    Write-Host ""
    Start-Sleep -Seconds $IntervalSeconds
}
