#!/usr/bin/env pwsh
<#
    task-state.ps1 — BossMind Live State Watcher v1
    Append-only JSONL writer for the task state log.
    Records transitions: pending → running → done | failed | escalated.
    Never modifies existing records — each state change is a new line.
#>

Set-StrictMode -Version Latest

function Write-TaskState {
    <#
    .SYNOPSIS
        Appends a task state transition record to the task state JSONL log.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$ProjectId,
        [Parameter(Mandatory)][string]$TaskName,
        [Parameter(Mandatory)]
        [ValidateSet("pending","running","done","failed","escalated","cancelled")]
        [string]$Status,
        [string]$Detail,
        [hashtable]$Metadata,
        [switch]$WhatIf
    )

    $record = [ordered]@{
        _type      = "task_state"
        _written   = (Get-Date -Format 'o')
        project_id = $ProjectId
        task_name  = $TaskName
        task_id    = "$ProjectId.$TaskName.$(Get-Date -Format 'yyyyMMddHHmmss')"
        status     = $Status
        detail     = $Detail
        metadata   = $Metadata
    }

    $line = $record | ConvertTo-Json -Depth 6 -Compress

    if ($WhatIf) {
        Write-Host "[WhatIf] Would log task [$TaskName] → $Status" -ForegroundColor DarkYellow
        return
    }

    $dir = Split-Path $LogPath -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    Add-Content -Path $LogPath -Value $line -Encoding UTF8 -NoNewline:$false
}

function Get-TaskHistory {
    <#
    .SYNOPSIS
        Returns all state records for a given task name within a project.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [Parameter(Mandatory)][string]$ProjectId,
        [string]$TaskName,
        [int]$LastN = 50
    )

    if (-not (Test-Path $LogPath)) { return @() }

    Get-Content $LogPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object {
            $_ -and $_.project_id -eq $ProjectId -and
            (-not $TaskName -or $_.task_name -eq $TaskName)
        } |
        Select-Object -Last $LastN
}

function Get-RunningTasks {
    <#
    .SYNOPSIS
        Returns all tasks currently in 'running' or 'pending' state.
        Useful for detecting stuck tasks.
    #>
    param(
        [Parameter(Mandatory)][string]$LogPath,
        [string]$ProjectId
    )

    if (-not (Test-Path $LogPath)) { return @() }

    $allRecords = Get-Content $LogPath -ErrorAction SilentlyContinue |
        ForEach-Object {
            try { $_ | ConvertFrom-Json -ErrorAction Stop } catch { $null }
        } |
        Where-Object { $_ -and (-not $ProjectId -or $_.project_id -eq $ProjectId) }

    # Group by task_name and check last known status
    $allRecords | Group-Object task_name | ForEach-Object {
        $last = $_.Group | Select-Object -Last 1
        if ($last.status -in @("running","pending")) { $last }
    }
}
