#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Error Memory Sync — Phase 1

.DESCRIPTION
    Persists error fingerprints to the append-only error_memory.jsonl log
    and optionally syncs to Neon. Provides deduplication via SHA256 hashing,
    occurrence tracking, and repair strategy storage.

    Error memory is the anti-regression backbone:
      - Same error pattern → same hash → recognized as known regression
      - Occurrence count drives escalation decisions
      - Repair strategy fields enable autonomous remediation in Phase 2+
      - Records are NEVER deleted (append-only by design)

    SAFETY: Never reads secret values. Never triggers builds or pushes.

.PARAMETER LogPath
    Path to error_memory.jsonl. Default: ../logs/error_memory.jsonl

.PARAMETER NeonUrl
    Neon connection string. Reads from BOSSMIND_NEON_URL if not passed.

.PARAMETER WhatIf
    Process but write nothing.
#>

param(
    [string]$LogPath   = (Join-Path $PSScriptRoot ".." "logs" "error_memory.jsonl"),
    [string]$NeonUrl   = $env:BOSSMIND_NEON_URL,
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# ─────────────────────────────────────────────────────────────────────────────
# FINGERPRINTING
# ─────────────────────────────────────────────────────────────────────────────
function Get-ErrorFingerprint {
    <#
    .SYNOPSIS
        Stable 8-char SHA256 fingerprint for an array of error strings.
        Sorted before hashing so order doesn't change the hash.
    #>
    param([Parameter(Mandatory)][string[]]$Errors)

    $combined = ($Errors | Sort-Object) -join "|"
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $sha256   = [System.Security.Cryptography.SHA256]::Create()
    $hash     = $sha256.ComputeHash($bytes)
    $sha256.Dispose()
    return [System.BitConverter]::ToString($hash[0..3]).Replace("-","").ToLower()
}

# ─────────────────────────────────────────────────────────────────────────────
# WRITE (append-only)
# ─────────────────────────────────────────────────────────────────────────────
function Write-ErrorMemory {
    <#
    .SYNOPSIS
        Appends one error record to the error memory log.
    .PARAMETER ProjectId       Project identifier
    .PARAMETER Errors          Array of error strings (content only, no secrets)
    .PARAMETER Snapshot        Current watcher snapshot for context (optional)
    .PARAMETER Status          new | resolved | escalated
    .PARAMETER RepairStrategy  Human-readable repair strategy (optional)
    .PARAMETER Source          Which detector generated this error
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string[]]$Errors,
        [PSCustomObject]$Snapshot,
        [ValidateSet("new","resolved","escalated","suppressed")][string]$Status = "new",
        [string]$RepairStrategy,
        [string]$Source = "watcher",
        [switch]$WhatIf
    )

    $hash = Get-ErrorFingerprint -Errors $Errors

    $record = [ordered]@{
        _type            = "error_memory"
        _written         = (Get-Date -Format 'o')
        project_id       = $ProjectId
        error_hash       = $hash
        source           = $Source
        errors           = $Errors
        status           = $Status
        repair_strategy  = $RepairStrategy
        # Context from snapshot (safe fields only — no secrets)
        git_branch       = $Snapshot?.git?.branch
        git_commit       = $Snapshot?.git?.commit_hash
        git_dirty        = $Snapshot?.git?.dirty
        tick             = $Snapshot?.tick
        has_railway_toml = $Snapshot?.deployment?.railway_toml
        has_render_yaml  = $Snapshot?.deployment?.render_yaml
        env_key_count    = $Snapshot?.env_keys?.key_names?.Count
    }

    $line = $record | ConvertTo-Json -Depth 6 -Compress

    if ($WhatIf) {
        Write-Host "[WhatIf] ErrorMemory: [$hash] $ProjectId — $($Errors -join '; ' | Select-Object -First 80)" -ForegroundColor DarkYellow
        return $hash
    }

    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -NoNewline:$false

    if ($NeonUrl) { Invoke-ErrorNeonSync -Record $record }

    Write-Verbose "[ErrorMemory] Appended [$hash] $ProjectId ($Status)"
    return $hash
}

# ─────────────────────────────────────────────────────────────────────────────
# READ
# ─────────────────────────────────────────────────────────────────────────────
function Get-ErrorMemoryByHash {
    param([Parameter(Mandatory)][string]$ErrorHash)

    if (-not (Test-Path $LogPath)) { return $null }

    $records = Get-Content $LogPath -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null } } |
        Where-Object { $_ -and $_.error_hash -eq $ErrorHash }

    if (-not $records -or @($records).Count -eq 0) { return $null }

    $arr = @($records)
    return [PSCustomObject]@{
        hash              = $ErrorHash
        occurrence_count  = $arr.Count
        first_seen        = $arr[0]._written
        last_seen         = $arr[-1]._written
        statuses          = $arr.status | Sort-Object -Unique
        repair_strategies = ($arr | Where-Object { $_.repair_strategy } |
                             Select-Object -ExpandProperty repair_strategy | Sort-Object -Unique)
        projects          = $arr.project_id | Sort-Object -Unique
        records           = $arr
    }
}

function Get-ErrorMemorySummary {
    param([string]$ProjectId, [int]$TopN = 20)

    if (-not (Test-Path $LogPath)) { return @() }

    $records = Get-Content $LogPath -ErrorAction SilentlyContinue |
        ForEach-Object { try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null } } |
        Where-Object { $_ -and (-not $ProjectId -or $_.project_id -eq $ProjectId) }

    @($records) | Group-Object error_hash | ForEach-Object {
        $grp = @($_.Group)
        [PSCustomObject]@{
            error_hash   = $_.Name
            count        = $_.Count
            project_id   = $grp[0].project_id
            source       = $grp[0].source
            first_seen   = $grp[0]._written
            last_seen    = $grp[-1]._written
            last_status  = $grp[-1].status
            is_resolved  = ($grp | Where-Object { $_.status -eq "resolved" }).Count -gt 0
            errors       = $grp[0].errors
        }
    } | Sort-Object count -Descending | Select-Object -First $TopN
}

function Test-IsKnownRegression {
    <#
    .SYNOPSIS
        Returns true if this error pattern is a known unresolved regression.
        Used by the anti-regression gate to block pushes.
    #>
    param([Parameter(Mandatory)][string[]]$Errors)

    $hash    = Get-ErrorFingerprint -Errors $Errors
    $history = Get-ErrorMemoryByHash -ErrorHash $hash
    if (-not $history -or $history.occurrence_count -eq 0) { return $false }

    $resolvedCount = ($history.records | Where-Object { $_.status -eq "resolved" }).Count
    return $resolvedCount -eq 0  # known, never resolved = regression
}

function Set-ErrorResolved {
    <#
    .SYNOPSIS
        Marks an error hash as resolved by appending a resolved record.
        DOES NOT modify existing records — appends a new resolution record.
    #>
    param(
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$ErrorHash,
        [string]$RepairStrategy = "manually resolved"
    )

    $history = Get-ErrorMemoryByHash -ErrorHash $ErrorHash
    if (-not $history) {
        Write-Warning "[ErrorMemory] Hash $ErrorHash not found in log"
        return
    }

    # Get the original errors from the first record
    $originalErrors = $history.records[0].errors

    Write-ErrorMemory -ProjectId $ProjectId `
        -Errors $originalErrors `
        -Status "resolved" `
        -RepairStrategy $RepairStrategy `
        -WhatIf:$WhatIf
    Write-Host "[ErrorMemory] Marked $ErrorHash as resolved" -ForegroundColor Green
}

# ─────────────────────────────────────────────────────────────────────────────
# NEON SYNC
# ─────────────────────────────────────────────────────────────────────────────
function Invoke-ErrorNeonSync {
    param([hashtable]$Record)

    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psql) { return }

    try {
        $errJson  = ($Record.errors | ConvertTo-Json -Compress) -replace "'", "''"
        $projId   = $Record.project_id -replace "'", "''"
        $hash     = $Record.error_hash
        $status   = $Record.status
        $written  = $Record._written
        $tmpFile  = [System.IO.Path]::GetTempFileName() + ".sql"

        @"
INSERT INTO error_memory (project_id, error_hash, errors, status, git_branch, git_commit, written_at)
VALUES (
  '$projId',
  '$hash',
  '$errJson'::jsonb,
  '$status',
  $(if ($Record.git_branch) { "'$($Record.git_branch)'" } else { 'NULL' }),
  $(if ($Record.git_commit) { "'$($Record.git_commit)'" } else { 'NULL' }),
  '$written'
);
"@ | Set-Content -Path $tmpFile -Encoding UTF8

        psql $NeonUrl -f $tmpFile 2>&1 | Out-Null
        Remove-Item $tmpFile -Force -ErrorAction SilentlyContinue
    } catch {
        Write-Verbose "Error Neon sync failed: $_"
    }
}

# ─────────────────────────────────────────────────────────────────────────────
# STANDALONE MODE
# ─────────────────────────────────────────────────────────────────────────────
if ($MyInvocation.InvocationName -ne '.') {
    Write-Host "[ErrorMemorySync] Running standalone report" -ForegroundColor Cyan

    if (Test-Path $LogPath) {
        $summary = Get-ErrorMemorySummary
        Write-Host "[ErrorMemorySync] Error summary ($($summary.Count) unique hashes):" -ForegroundColor Gray
        $summary | Format-Table error_hash, count, project_id, last_status, first_seen -AutoSize
    } else {
        Write-Host "[ErrorMemorySync] No error memory log found at $LogPath" -ForegroundColor Yellow
    }
}
