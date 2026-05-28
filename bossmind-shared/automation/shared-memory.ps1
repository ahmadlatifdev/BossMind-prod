#!/usr/bin/env pwsh
<#
    shared-memory.ps1 — BossMind Live State Watcher v1
    Append-only JSONL writer for the shared memory log.
    Each call adds one line — nothing is ever deleted or overwritten.
#>

Set-StrictMode -Version Latest

function Write-SharedMemoryLog {
    <#
    .SYNOPSIS
        Appends one state snapshot as a JSONL record.
    .DESCRIPTION
        Records are always appended. The file grows indefinitely.
        To read the latest state per project, read lines in reverse
        and take the first match for the project_id.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][PSCustomObject]$Snapshot,
        [switch]$WhatIf
    )

    $record = [ordered]@{
        _type      = "shared_memory"
        _written   = (Get-Date -Format 'o')
        project_id = $Snapshot.project_id
        tick       = $Snapshot.tick
        state      = $Snapshot
    }

    $line = $record | ConvertTo-Json -Depth 15 -Compress

    if ($WhatIf) {
        Write-Host "[WhatIf] Would append to $LogPath : $($line.Substring(0, [Math]::Min(120, $line.Length)))..." -ForegroundColor DarkYellow
        return
    }

    # Ensure directory exists
    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    # Append-only — never truncate
    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -NoNewline:$false
}

function Read-SharedMemoryLatest {
    <#
    .SYNOPSIS
        Returns the most recent state snapshot for a given project_id.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$ProjectId
    )

    if (-not (Test-Path $LogPath)) { return $null }

    # Read in reverse to find latest quickly
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
