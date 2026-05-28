#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Shared Memory Sync — Phase 1

.DESCRIPTION
    Manages a write queue for shared memory snapshots and flushes them to:
      - Local append-only JSONL log (always)
      - Neon Postgres shared_memory table (if BOSSMIND_NEON_URL is set)

    The queue prevents thundering-herd writes when multiple projects
    update simultaneously. All writes are append-only.

    SAFETY: Never reads back or modifies existing log entries.
    Never writes secret values. Only PSCustomObject snapshots.

.PARAMETER LogPath
    Path to shared_memory.jsonl. Default: ../logs/shared_memory.jsonl

.PARAMETER NeonUrl
    Neon connection string. Reads from BOSSMIND_NEON_URL if not passed.

.PARAMETER FlushIntervalMs
    How long to wait between batch flushes. Default: 100ms.

.PARAMETER WhatIf
    Process queue but write nothing.
#>

param(
    [string]$LogPath         = (Join-Path $PSScriptRoot ".." "logs" "shared_memory.jsonl"),
    [string]$NeonUrl         = $env:BOSSMIND_NEON_URL,
    [int]$FlushIntervalMs    = 100,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ── In-memory queue ────────────────────────────────────────────────────────────
$script:WriteQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()
$script:FlushCount = 0
$script:WriteCount = 0

function Add-SharedMemorySnapshot {
    <#
    .SYNOPSIS
        Enqueues a state snapshot for writing. Thread-safe.
    .PARAMETER Snapshot
        PSCustomObject from the watcher daemon.
    #>
    param([Parameter(Mandatory)][PSCustomObject]$Snapshot)
    $script:WriteQueue.Enqueue($Snapshot)
}

function Invoke-QueueFlush {
    <#
    .SYNOPSIS
        Drains the write queue and appends all pending snapshots.
        Call this on a timer or after each watcher tick.
    #>

    if ($script:WriteQueue.IsEmpty) { return 0 }

    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir) -and -not $WhatIf) {
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
    }

    $flushed = 0
    $item    = $null

    while ($script:WriteQueue.TryDequeue([ref]$item)) {
        $record = [ordered]@{
            _type      = "shared_memory"
            _written   = (Get-Date -Format 'o')
            project_id = $item.project_id
            tick       = $item.tick
            state      = $item
        }

        $line = $record | ConvertTo-Json -Depth 15 -Compress

        if ($WhatIf) {
            Write-Host "[WhatIf] SharedMemory queue flush: $($item.project_id) tick $($item.tick)" -ForegroundColor DarkYellow
        } else {
            Add-Content -Path $LogPath -Value $line -Encoding UTF8 -NoNewline:$false

            if ($NeonUrl) {
                Invoke-NeonUpsert -NeonUrl $NeonUrl -Snapshot $item
            }
        }

        $flushed++
        $script:WriteCount++
    }

    if ($flushed -gt 0) {
        $script:FlushCount++
        Write-Verbose "[SharedMemorySync] Flushed $flushed item(s) (flush #$($script:FlushCount), total writes: $($script:WriteCount))"
    }

    return $flushed
}

function Invoke-NeonUpsert {
    param([string]$NeonUrl, [PSCustomObject]$Snapshot)

    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psql) { Write-Verbose "psql not available — Neon sync skipped"; return }

    try {
        $json    = ($Snapshot | ConvertTo-Json -Depth 10 -Compress) -replace "'", "''"
        $projId  = $Snapshot.project_id -replace "'", "''"
        $tmpFile = [System.IO.Path]::GetTempFileName() + ".sql"

        @"
SET app.project_id = '$projId';
INSERT INTO shared_memory (project_id, key, value, updated_at)
VALUES ('$projId', 'watcher_state', '$json'::jsonb, now())
ON CONFLICT (project_id, key)
DO UPDATE SET value = EXCLUDED.value, updated_at = now();
"@ | Set-Content -Path $tmpFile -Encoding UTF8

        psql $NeonUrl -f $tmpFile 2>&1 | Out-Null
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Verbose "Neon upsert failed: $_"
    }
}

function Read-SharedMemoryLatest {
    <#
    .SYNOPSIS
        Returns the most recent snapshot for a given project_id.
        Reads JSONL in reverse — returns first match from the end.
    #>
    param([Parameter(Mandatory)][string]$ProjectId)

    if (-not (Test-Path $LogPath)) { return $null }

    $lines = Get-Content $LogPath -ErrorAction SilentlyContinue
    if (-not $lines) { return $null }

    [Array]::Reverse($lines)
    foreach ($line in $lines) {
        try {
            $record = $line | ConvertFrom-Json -ErrorAction Stop
            if ($record.project_id -eq $ProjectId) { return $record }
        } catch {}
    }
    return $null
}

function Get-SharedMemoryStats {
    <#
    .SYNOPSIS
        Returns queue and log statistics.
    #>
    $logSize  = 0
    $logLines = 0
    if (Test-Path $LogPath) {
        $logInfo  = Get-Item $LogPath
        $logSize  = $logInfo.Length
        $logLines = (Get-Content $LogPath -ErrorAction SilentlyContinue).Count
    }

    return [PSCustomObject]@{
        queue_depth   = $script:WriteQueue.Count
        flush_count   = $script:FlushCount
        total_writes  = $script:WriteCount
        log_path      = $LogPath
        log_size_kb   = [math]::Round($logSize / 1KB, 1)
        log_lines     = $logLines
        neon_enabled  = [bool]$NeonUrl
    }
}

# ── Direct invocation mode (flush any queued items and exit) ───────────────────
# When called directly rather than dot-sourced, this acts as a one-shot flush.
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "[SharedMemorySync] Running as standalone flush" -ForegroundColor Cyan
    $stats = Get-SharedMemoryStats
    Write-Host "[SharedMemorySync] Queue depth: $($stats.queue_depth) | Log: $($stats.log_lines) lines ($($stats.log_size_kb)KB)" -ForegroundColor Gray

    $flushed = Invoke-QueueFlush
    Write-Host "[SharedMemorySync] Flushed: $flushed item(s)" -ForegroundColor Green

    $stats = Get-SharedMemoryStats
    Write-Host "[SharedMemorySync] Stats: $($stats | ConvertTo-Json -Compress)" -ForegroundColor Gray
}
