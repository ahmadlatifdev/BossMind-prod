#!/usr/bin/env pwsh
<#
    error-memory.ps1 — BossMind Live State Watcher v1
    Append-only JSONL writer for the error memory log.
    Each error gets a stable hash (fingerprint) so the same error
    is recognisable across multiple occurrences without duplication.
    Records are NEVER deleted — this is the regression history.
#>

Set-StrictMode -Version Latest

function Get-ErrorFingerprint {
    <#
    .SYNOPSIS
        Produces a stable 8-char hash for an error string or array of errors.
        Same errors → same hash, regardless of timestamp or project.
    #>
    param([string[]]$Errors)

    $combined = ($Errors | Sort-Object) -join "|"
    $bytes    = [System.Text.Encoding]::UTF8.GetBytes($combined)
    $hash     = [System.Security.Cryptography.SHA256]::Create().ComputeHash($bytes)
    return [System.BitConverter]::ToString($hash[0..3]).Replace("-","").ToLower()
}

function Write-ErrorMemoryLog {
    <#
    .SYNOPSIS
        Appends an error record to the error memory JSONL log.
    .DESCRIPTION
        Each call appends one line regardless of whether this error was
        seen before. Callers can use Get-ErrorMemoryByHash to check prior
        occurrence count and repair history before taking action.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string[]]$Errors,
        [PSCustomObject]$Snapshot,
        [string]$Status = "new",   # new | resolved | escalated
        [string]$RepairStrategy,
        [switch]$WhatIf
    )

    $hash = Get-ErrorFingerprint -Errors $Errors

    $record = [ordered]@{
        _type            = "error_memory"
        _written         = (Get-Date -Format 'o')
        project_id       = $ProjectId
        error_hash       = $hash
        errors           = $Errors
        status           = $Status
        repair_strategy  = $RepairStrategy
        # Safe context — no secret values
        git_branch       = $Snapshot?.git?.branch
        git_commit       = $Snapshot?.git?.commit_hash
        git_dirty        = $Snapshot?.git?.dirty
        deploy_config    = [bool]($Snapshot?.deployment?.railway_toml -or $Snapshot?.deployment?.render_yaml)
        tick             = $Snapshot?.tick
    }

    $line = $record | ConvertTo-Json -Depth 8 -Compress

    if ($WhatIf) {
        Write-Host "[WhatIf] Would append error [$hash] to $LogPath" -ForegroundColor DarkYellow
        return
    }

    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -NoNewline:$false
}

function Get-ErrorMemoryByHash {
    <#
    .SYNOPSIS
        Returns all records with a given error hash from the log.
        Returns $null if never seen before.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$ErrorHash
    )

    if (-not (Test-Path $LogPath)) { return $null }

    $matches = Get-Content $LogPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object { $_ -and $_.error_hash -eq $ErrorHash }

    if (-not $matches) { return $null }

    return [PSCustomObject]@{
        hash            = $ErrorHash
        occurrence_count = @($matches).Count
        first_seen      = ($matches | Select-Object -First 1)._written
        last_seen       = ($matches | Select-Object -Last 1)._written
        statuses        = $matches.status | Select-Object -Unique
        repair_strategies = ($matches | Where-Object { $_.repair_strategy } | Select-Object -ExpandProperty repair_strategy -Unique)
        records         = $matches
    }
}

function Get-ErrorMemorySummary {
    <#
    .SYNOPSIS
        Returns a summary of all errors in the log for a project.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [string]$ProjectId
    )

    if (-not (Test-Path $LogPath)) { return @() }

    $records = Get-Content $LogPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object { $_ -and (-not $ProjectId -or $_.project_id -eq $ProjectId) }

    $records | Group-Object error_hash | ForEach-Object {
        $grp = $_.Group
        [PSCustomObject]@{
            error_hash  = $_.Name
            count       = $_.Count
            project_id  = ($grp | Select-Object -First 1).project_id
            first_seen  = ($grp | Select-Object -First 1)._written
            last_seen   = ($grp | Select-Object -Last 1)._written
            last_status = ($grp | Select-Object -Last 1).status
            errors      = ($grp | Select-Object -First 1).errors
        }
    } | Sort-Object count -Descending
}
