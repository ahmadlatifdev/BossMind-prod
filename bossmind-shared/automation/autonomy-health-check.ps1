#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Autonomy Health Check — Phase 1

.DESCRIPTION
    Validates that all Phase 1 autonomous systems are active and healthy:
      - Watcher daemon is running (job or scheduled task)
      - JSONL logs are growing (not stale)
      - Shared memory has recent snapshots
      - Error memory log is accessible
      - Task state log shows completed ticks
      - Registry files exist and are recent
      - No stuck tasks (running state for > threshold)
      - No env leaks across any project

    Outputs a structured health report and exits with:
      0 = fully healthy
      1 = degraded (warnings only)
      2 = critical failure

.PARAMETER BossMindRoot
    Path to bossmind/orchestrator directory.

.PARAMETER MaxStaleMinutes
    How old a shared memory log can be before considered stale. Default: 5.

.PARAMETER MaxStuckMinutes
    How long a task can stay in 'running' before considered stuck. Default: 3.
#>

param(
    [Parameter(Mandatory)][string]$BossMindRoot,
    [int]$MaxStaleMinutes = 5,
    [int]$MaxStuckMinutes = 3
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$logDir      = Join-Path $BossMindRoot "logs"
$registryDir = Join-Path $BossMindRoot "registry"
$snapshotDir = Join-Path $BossMindRoot "snapshots"

$checks   = [System.Collections.Generic.List[PSCustomObject]]::new()
$critical = 0
$warnings = 0

function Add-Check {
    param(
        [string]$Category,
        [string]$Name,
        [ValidateSet("pass","warn","fail")][string]$Status,
        [string]$Detail
    )
    $color = switch ($Status) {
        "pass" { "Green"  }
        "warn" { "Yellow" }
        "fail" { "Red"    }
    }
    $icon = switch ($Status) {
        "pass" { "[OK]  " }
        "warn" { "[WARN]" }
        "fail" { "[FAIL]" }
    }
    Write-Host "  $icon $Category / $Name$(if ($Detail) { " — $Detail" })" -ForegroundColor $color
    $checks.Add([PSCustomObject]@{
        category = $Category
        name     = $Name
        status   = $Status
        detail   = $Detail
        checked_at = (Get-Date -Format 'o')
    })
    if ($Status -eq "fail") { $script:critical++ }
    if ($Status -eq "warn") { $script:warnings++ }
}

Write-Host ""
Write-Host "BossMind Autonomy Health Check — $(Get-Date -Format 'o')" -ForegroundColor Cyan
Write-Host ("─" * 60) -ForegroundColor DarkGray

# ─────────────────────────────────────────────────────────────────────────────
# 1. DIRECTORY STRUCTURE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[1] Directory structure" -ForegroundColor DarkCyan
foreach ($dir in @($logDir, $registryDir, $snapshotDir)) {
    $name = Split-Path $dir -Leaf
    if (Test-Path $dir) { Add-Check "Dirs" $name "pass" $dir }
    else                { Add-Check "Dirs" $name "fail" "Missing: $dir" }
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. WATCHER DAEMON STATUS
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[2] Watcher daemon" -ForegroundColor DarkCyan

$watcherJob  = Get-Job -Name "BossMindWatcher" -ErrorAction SilentlyContinue
$watcherTask = Get-ScheduledTask -TaskName "BossMindWatcher" -ErrorAction SilentlyContinue

if ($watcherJob -and $watcherJob.State -eq "Running") {
    Add-Check "Watcher" "background-job" "pass" "State: Running, ID: $($watcherJob.Id)"
} elseif ($watcherJob) {
    Add-Check "Watcher" "background-job" "warn" "State: $($watcherJob.State) — may have stopped"
} else {
    Add-Check "Watcher" "background-job" "warn" "No PowerShell background job found"
}

if ($watcherTask) {
    $taskInfo    = Get-ScheduledTaskInfo -TaskName "BossMindWatcher" -ErrorAction SilentlyContinue
    $lastResult  = $taskInfo?.LastTaskResult
    $lastRunTime = $taskInfo?.LastRunTime
    if ($lastResult -eq 0) {
        Add-Check "Watcher" "scheduled-task" "pass" "Last run: $lastRunTime, Result: 0"
    } elseif ($lastResult -ne $null) {
        Add-Check "Watcher" "scheduled-task" "warn" "Last result: $lastResult at $lastRunTime"
    } else {
        Add-Check "Watcher" "scheduled-task" "warn" "Task registered but never run"
    }
} else {
    Add-Check "Watcher" "scheduled-task" "warn" "Not registered (OK for development mode)"
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. LOG FILE HEALTH
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[3] Log files" -ForegroundColor DarkCyan

$sharedMemLog = Join-Path $logDir "shared_memory.jsonl"
$errorMemLog  = Join-Path $logDir "error_memory.jsonl"
$taskStateLog = Join-Path $logDir "task_state.jsonl"

foreach ($logEntry in @(
    @{ Path=$sharedMemLog; Name="shared_memory.jsonl"; Required=$true  }
    @{ Path=$errorMemLog;  Name="error_memory.jsonl";  Required=$false }
    @{ Path=$taskStateLog; Name="task_state.jsonl";    Required=$true  }
)) {
    if (-not (Test-Path $logEntry.Path)) {
        $status = if ($logEntry.Required) { "fail" } else { "warn" }
        Add-Check "Logs" $logEntry.Name $status "File not found"
        continue
    }

    $info     = Get-Item $logEntry.Path
    $sizeKB   = [math]::Round($info.Length / 1KB, 1)
    $lines    = (Get-Content $logEntry.Path -ErrorAction SilentlyContinue).Count
    $ageMin   = [math]::Round(((Get-Date) - $info.LastWriteTime).TotalMinutes, 1)

    if ($logEntry.Name -eq "shared_memory.jsonl" -and $ageMin -gt $MaxStaleMinutes) {
        Add-Check "Logs" $logEntry.Name "warn" "$lines lines, ${sizeKB}KB — STALE ($ageMin min since last write)"
    } elseif ($lines -eq 0) {
        Add-Check "Logs" $logEntry.Name "warn" "Empty file"
    } else {
        Add-Check "Logs" $logEntry.Name "pass" "$lines lines, ${sizeKB}KB, last write ${ageMin}min ago"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. SHARED MEMORY CONTENT
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[4] Shared memory content" -ForegroundColor DarkCyan

if (Test-Path $sharedMemLog) {
    $lines = Get-Content $sharedMemLog -ErrorAction SilentlyContinue
    $validRecords = @($lines | ForEach-Object {
        try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    } | Where-Object { $_ })

    if ($validRecords.Count -gt 0) {
        $lastRecord = $validRecords | Select-Object -Last 1
        $ageMin = [math]::Round(((Get-Date) - [DateTime]$lastRecord._written).TotalMinutes, 1)

        Add-Check "Memory" "record-validity" "pass" "$($validRecords.Count) valid JSONL records"
        Add-Check "Memory" "latest-age" $(if ($ageMin -le $MaxStaleMinutes) { "pass" } else { "warn" }) `
            "Latest record is ${ageMin} min old"

        # Check projects represented
        $projects = $validRecords | ForEach-Object { $_.project_id } | Sort-Object -Unique
        Add-Check "Memory" "project-coverage" "pass" "Projects: $($projects -join ', ')"

        # Verify no secret values leaked
        $leakHits = Select-String -Path $sharedMemLog -Pattern '=[A-Za-z0-9/+]{20,}' -ErrorAction SilentlyContinue |
            Where-Object { $_.Line -notmatch '"key_names"' }
        if ($leakHits) {
            Add-Check "Memory" "secret-leak-check" "fail" "POTENTIAL VALUE LEAK — review log immediately"
        } else {
            Add-Check "Memory" "secret-leak-check" "pass" "No secret values detected in log"
        }
    } else {
        Add-Check "Memory" "record-validity" "warn" "No valid JSONL records parseable"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. TASK STATE
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[5] Task state" -ForegroundColor DarkCyan

if (Test-Path $taskStateLog) {
    $taskLines = Get-Content $taskStateLog -ErrorAction SilentlyContinue
    $taskRecords = @($taskLines | ForEach-Object {
        try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
    } | Where-Object { $_ })

    $doneCount   = ($taskRecords | Where-Object { $_.status -eq "done" }).Count
    $failedCount = ($taskRecords | Where-Object { $_.status -eq "failed" }).Count

    Add-Check "Tasks" "completion-rate" $(if ($failedCount -eq 0) { "pass" } else { "warn" }) `
        "Done: $doneCount, Failed: $failedCount"

    # Stuck task detection
    $stuckThreshold = (Get-Date).AddMinutes(-$MaxStuckMinutes)
    $runningTasks   = $taskRecords | Group-Object task_name | ForEach-Object {
        $last = @($_.Group) | Select-Object -Last 1
        if ($last.status -in @("running","pending")) {
            $age = [math]::Round(((Get-Date) - [DateTime]$last._written).TotalMinutes, 1)
            if ([DateTime]$last._written -lt $stuckThreshold) {
                [PSCustomObject]@{ name=$last.task_name; age_min=$age; status=$last.status }
            }
        }
    } | Where-Object { $_ }

    if ($runningTasks) {
        Add-Check "Tasks" "stuck-tasks" "warn" "Stuck: $($runningTasks | ForEach-Object { "$($_.name) ($($_.age_min)min)" } | Select-Object -First 5 | Join-String -Separator ', ')"
    } else {
        Add-Check "Tasks" "stuck-tasks" "pass" "No stuck tasks detected"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. REGISTRY
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[6] Registry" -ForegroundColor DarkCyan

$serviceRegistry = Join-Path $registryDir "service-registry.json"
if (Test-Path $serviceRegistry) {
    try {
        $reg = Get-Content $serviceRegistry -Raw | ConvertFrom-Json
        $ageMin = [math]::Round(((Get-Date) - [DateTime]$reg.generated_at).TotalMinutes, 1)
        Add-Check "Registry" "service-registry" "pass" "$($reg.project_count) projects, ${ageMin}min old"
    } catch {
        Add-Check "Registry" "service-registry" "warn" "Found but not parseable"
    }
} else {
    Add-Check "Registry" "service-registry" "warn" "Not yet generated — run project-registry-generator.ps1"
}

$envReports = Get-ChildItem $registryDir -Filter "*-env-report.json" -ErrorAction SilentlyContinue
if ($envReports) {
    Add-Check "Registry" "env-reports" "pass" "$($envReports.Count) env report(s) present"
} else {
    Add-Check "Registry" "env-reports" "warn" "No env reports — run env-detector.ps1"
}

$fsIndexes = Get-ChildItem $registryDir -Filter "*-fs-index.json" -ErrorAction SilentlyContinue
if ($fsIndexes) {
    Add-Check "Registry" "fs-indexes" "pass" "$($fsIndexes.Count) filesystem index(es) present"
} else {
    Add-Check "Registry" "fs-indexes" "warn" "No filesystem indexes — run filesystem-indexer.ps1"
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. SNAPSHOTS
# ─────────────────────────────────────────────────────────────────────────────
Write-Host "`n[7] Rollback snapshots" -ForegroundColor DarkCyan

$snapshots = Get-ChildItem $snapshotDir -Filter "*.json" -ErrorAction SilentlyContinue |
    Sort-Object LastWriteTime -Descending

if ($snapshots) {
    $latestSnap = $snapshots | Select-Object -First 1
    $snapAgeMin = [math]::Round(((Get-Date) - $latestSnap.LastWriteTime).TotalMinutes, 1)
    Add-Check "Snapshots" "rollback-snapshots" "pass" "$($snapshots.Count) snapshot(s) — latest: ${snapAgeMin}min ago"
} else {
    Add-Check "Snapshots" "rollback-snapshots" "warn" "No snapshots yet — run enforcement engine to create"
}

# ─────────────────────────────────────────────────────────────────────────────
# FINAL REPORT
# ─────────────────────────────────────────────────────────────────────────────
Write-Host ""
Write-Host ("─" * 60) -ForegroundColor DarkGray

$passCount = ($checks | Where-Object { $_.status -eq "pass" }).Count
$total     = $checks.Count

Write-Host "RESULTS: $passCount/$total pass | $($script:warnings) warnings | $($script:critical) failures" -ForegroundColor $(
    if ($script:critical -gt 0) { "Red" }
    elseif ($script:warnings -gt 0) { "Yellow" }
    else { "Green" }
)

# Autonomy estimate
$autonomyPct = [math]::Round(($passCount / $total) * 100, 0)
Write-Host "AUTONOMY: ${autonomyPct}% systems operational" -ForegroundColor $(
    if ($autonomyPct -ge 90) { "Green" }
    elseif ($autonomyPct -ge 70) { "Yellow" }
    else { "Red" }
)

# Write health report to registry
$reportPath = Join-Path $registryDir "autonomy-health-report.json"
[PSCustomObject]@{
    generated_at    = (Get-Date -Format 'o')
    pass_count      = $passCount
    total_checks    = $total
    warnings        = $script:warnings
    critical        = $script:critical
    autonomy_pct    = $autonomyPct
    checks          = $checks
} | ConvertTo-Json -Depth 6 | Set-Content -Path $reportPath -Encoding UTF8

Write-Host "Report: $reportPath" -ForegroundColor Gray
Write-Host ""

# Exit code
if ($script:critical -gt 0) { exit 2 }
if ($script:warnings -gt 0) { exit 1 }
exit 0
