#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Runtime Graph Reader
    Prints a clean operational summary of all BossMind project states.
.DESCRIPTION
    Reads D:\BossMind\bossmind-shared\prae\runtime-graph\bossmind-runtime-graph.json
    and renders a structured console view: one row per project, then detailed
    sections for any project that has errors or blocked domains.

    Exit codes:
      0 = all registered projects are either PASS or NEVER_RUN
      1 = one or more projects have DEPLOYMENT_BLOCKED or HIGH risk

    Does not write to any project directory.
    Does not modify the graph file.
    governance_mode=LOCKED  production_mutation=NONE
.PARAMETER GraphPath
    Override the default graph file location.
.PARAMETER ProjectFilter
    Show only this project (partial match). Default: all projects.
.PARAMETER ShowHistory
    Include last 5 history entries per project.
.PARAMETER Json
    Output raw JSON of the full graph instead of the formatted view.
.EXAMPLE
    # Full summary
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "D:\BossMind\bossmind-shared\prae\PRAE-RuntimeGraph-Reader.ps1"

    # Single project detail
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-RuntimeGraph-Reader.ps1" -ProjectFilter "resumora"

    # Include history
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-RuntimeGraph-Reader.ps1" -ShowHistory

    # Machine-readable JSON
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-RuntimeGraph-Reader.ps1" -Json
#>

[CmdletBinding()]
param(
    [string]$GraphPath     = "D:\BossMind\bossmind-shared\prae\runtime-graph\bossmind-runtime-graph.json",
    [string]$ProjectFilter = "",
    [switch]$ShowHistory,
    [switch]$Json
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  GOVERNANCE CONSTANTS (ReadOnly)
# ---------------------------------------------------------------
Set-Variable -Name GOV_MODE     -Value "LOCKED" -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION -Value "NONE"   -Option ReadOnly -Force

# ---------------------------------------------------------------
#  HELPERS
# ---------------------------------------------------------------
function Get-Prop {
    param($Obj, [string]$Key, $Default = $null)
    if ($null -eq $Obj) { return $Default }
    if ($Obj -is [System.Collections.IDictionary]) {
        return if ($Obj.Contains($Key)) { $Obj[$Key] } else { $Default }
    }
    if ($Obj.PSObject.Properties[$Key]) { return $Obj.$Key }
    return $Default
}

function Format-Age {
    param([string]$IsoTimestamp)
    if (-not $IsoTimestamp) { return "never" }
    try {
        $ts  = [DateTimeOffset]::Parse($IsoTimestamp)
        $age = [DateTimeOffset]::UtcNow - $ts
        if ($age.TotalSeconds -lt 60)  { return "$([int]$age.TotalSeconds)s ago" }
        if ($age.TotalMinutes -lt 60)  { return "$([int]$age.TotalMinutes)m ago" }
        if ($age.TotalHours   -lt 24)  { return "$([int]$age.TotalHours)h ago" }
        return "$([int]$age.TotalDays)d ago"
    } catch { return $IsoTimestamp }
}

function Write-Ruler { param([int]$W=62)
    Write-Host ("  " + "-" * $W) -ForegroundColor DarkGray }

function Write-Col {
    param([string]$Label, [string]$Value, [string]$Color = "Gray", [int]$LabelW = 22)
    $lbl = $Label.PadRight($LabelW)
    Write-Host "    $lbl" -NoNewline -ForegroundColor DarkGray
    Write-Host $Value -ForegroundColor $Color
}

function Get-RiskColor {
    param([string]$Score)
    switch ($Score) {
        "HIGH"    { return "Red"     }
        "MEDIUM"  { return "Yellow"  }
        "LOW"     { return "Green"   }
        default   { return "Gray"    }
    }
}

function Get-ValidationColor {
    param([string]$Overall)
    switch ($Overall) {
        "ALL_VALIDATIONS_PASS" { return "Green"  }
        "DEPLOYMENT_BLOCKED"   { return "Red"    }
        "NEVER_RUN"            { return "Gray"   }
        default                { return "Yellow" }
    }
}

function Get-WatcherColor {
    param([string]$Status)
    switch ($Status) {
        "RUNNING"       { return "Green"  }
        "STOPPED"       { return "Yellow" }
        "NEVER_STARTED" { return "Gray"   }
        default         { return "Gray"   }
    }
}

# ---------------------------------------------------------------
#  LOAD GRAPH
# ---------------------------------------------------------------
if (-not (Test-Path $GraphPath)) {
    Write-Host ""
    Write-Host "  PRAE Runtime Graph not found: $GraphPath" -ForegroundColor Yellow
    Write-Host "  Run PRAE-A1-Watcher-Resumora.ps1 -Snapshot or" -ForegroundColor Gray
    Write-Host "  PRAE-A2-DeployValidate-Resumora.ps1 to populate the graph." -ForegroundColor Gray
    Write-Host ""
    exit 0
}

try {
    $raw   = [System.IO.File]::ReadAllText($GraphPath, [System.Text.Encoding]::UTF8)
    $graph = $raw | ConvertFrom-Json
} catch {
    Write-Host "  Cannot read graph file: $_" -ForegroundColor Red
    exit 1
}

# ---------------------------------------------------------------
#  JSON MODE
# ---------------------------------------------------------------
if ($Json) {
    Write-Host $raw
    exit 0
}

# ---------------------------------------------------------------
#  HEADER
# ---------------------------------------------------------------
$schemaVer  = Get-Prop $graph "schema_version" "?"
$lastUpd    = Get-Prop $graph "last_updated"   ""
$govMode    = Get-Prop $graph "governance_mode" "?"
$initAt     = Get-Prop $graph "initialized_at"  ""

Write-Host ""
Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  BossMind Runtime Graph                                      |" -ForegroundColor Cyan
Write-Host "  |  governance_mode=$govMode  production_mutation=$GOV_MUTATION$((" " * [Math]::Max(0, 14 - $govMode.Length - $GOV_MUTATION.Length)))|" -ForegroundColor DarkCyan
Write-Host "  +--------------------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""
Write-Col "Graph version"   "schema $schemaVer"
Write-Col "Initialized"     (Format-Age $initAt)
Write-Col "Last updated"    (Format-Age $lastUpd)
Write-Col "Graph file"      $GraphPath
Write-Host ""

# ---------------------------------------------------------------
#  PROJECT LIST
# ---------------------------------------------------------------
$projects = $graph.PSObject.Properties | Where-Object { $_.Name -eq "projects" }
if (-not $projects) {
    Write-Host "  No projects in graph." -ForegroundColor Gray
    exit 0
}

$projectMap = $graph.projects
$projectNames = $projectMap.PSObject.Properties | Select-Object -ExpandProperty Name

if ($ProjectFilter) {
    $projectNames = $projectNames | Where-Object { $_ -like "*$ProjectFilter*" }
}

$overallExitCode = 0

foreach ($pname in $projectNames) {
    $node = $projectMap.$pname
    if ($null -eq $node) { continue }

    # Core values
    $watcherStatus  = Get-Prop (Get-Prop $node "watcher") "status"          "NEVER_STARTED"
    $totalEvents    = Get-Prop (Get-Prop $node "watcher") "total_events"     0
    $highRisk       = Get-Prop (Get-Prop $node "watcher") "high_risk_events" 0
    $regFiles       = Get-Prop (Get-Prop $node "watcher") "registry_file_count" $null
    $lastEvent      = Get-Prop (Get-Prop $node "watcher") "last_event_at"    ""
    $snapshotAt     = Get-Prop (Get-Prop $node "watcher") "snapshot_at"      ""

    $valOverall     = Get-Prop (Get-Prop $node "validation") "overall"       "NEVER_RUN"
    $valLastRun     = Get-Prop (Get-Prop $node "validation") "last_run_at"   ""
    $passedCount    = Get-Prop (Get-Prop $node "validation") "passed_count"  $null
    $blockedCount   = Get-Prop (Get-Prop $node "validation") "blocked_count" $null
    $warnCount      = Get-Prop (Get-Prop $node "validation") "warning_count" $null
    $failedDomains  = @(Get-Prop (Get-Prop $node "validation") "failed_domains" @())

    $gitBranch      = Get-Prop (Get-Prop $node "git") "branch" $null
    $gitCommit      = Get-Prop (Get-Prop $node "git") "commit" $null
    $gitClean       = Get-Prop (Get-Prop $node "git") "clean"  $null

    $riskScore      = Get-Prop (Get-Prop $node "risk") "current_score" "UNKNOWN"
    $riskReason     = Get-Prop (Get-Prop $node "risk") "reason"        ""

    $chkAt          = Get-Prop (Get-Prop $node "rollback") "checkpoint_at"   $null
    $chkFiles       = Get-Prop (Get-Prop $node "rollback") "file_count"      $null

    $lastUpdNode    = Get-Prop $node "last_updated" ""
    $errors         = @(Get-Prop $node "errors" @())

    # Compute exit code
    if ($valOverall -eq "DEPLOYMENT_BLOCKED" -or $riskScore -eq "HIGH") {
        $overallExitCode = 1
    }

    # ---- PROJECT HEADER ----
    Write-Ruler
    $riskColor = Get-RiskColor $riskScore
    $riskTag   = "[$riskScore]".PadRight(8)
    Write-Host "  $riskTag $pname" -ForegroundColor $riskColor -NoNewline
    if ($lastUpdNode) {
        Write-Host "  (updated $(Format-Age $lastUpdNode))" -ForegroundColor DarkGray
    } else {
        Write-Host ""
    }
    Write-Ruler

    # ---- WATCHER ROW ----
    $watchColor  = Get-WatcherColor $watcherStatus
    $watchDetail = "events:$totalEvents  high-risk:$highRisk"
    if ($regFiles) { $watchDetail += "  registry:$regFiles files" }
    if ($lastEvent) { $watchDetail += "  last:$(Format-Age $lastEvent)" }
    Write-Col "Watcher" "$watcherStatus  $watchDetail" $watchColor

    # Snapshot / rollback
    $chkStr = if ($chkAt) { "$(Format-Age $chkAt)$(if($chkFiles){" ($chkFiles files)"})" } else { "none" }
    $chkColor = if ($chkAt) { "Green" } else { "Yellow" }
    Write-Col "Rollback checkpoint" $chkStr $chkColor

    # ---- VALIDATION ROW ----
    $valColor  = Get-ValidationColor $valOverall
    $valDetail = $valOverall
    if ($null -ne $passedCount -or $null -ne $blockedCount) {
        $valDetail += "  pass:$passedCount  block:$blockedCount  warn:$warnCount"
    }
    if ($valLastRun) { $valDetail += "  ($(Format-Age $valLastRun))" }
    Write-Col "Validation" $valDetail $valColor

    # Failed domains
    if (@($failedDomains).Count -gt 0) {
        Write-Col "  Blocked domains" ($failedDomains -join ", ") "Red"
    }

    # Domain grid (compact - only show non-null domains)
    $domainNode = Get-Prop $node "domains"
    if ($domainNode) {
        $domainNames = $domainNode.PSObject.Properties | Select-Object -ExpandProperty Name
        $domainLine  = ""
        foreach ($dn in $domainNames) {
            $dv = $domainNode.$dn
            if ($null -eq $dv) { continue }
            $pass = if ($dv.PSObject.Properties['pass']) { $dv.pass } else { $null }
            $sym  = if ($pass -eq $true) { "[+]" } elseif ($pass -eq $false) { "[X]" } else { "[-]" }
            $domainLine += "$sym$dn  "
        }
        if ($domainLine) {
            Write-Col "  Domains" $domainLine.TrimEnd() $(if ($valOverall -eq "ALL_VALIDATIONS_PASS") {"Green"} else {"Yellow"})
        }
    }

    # ---- GIT ROW ----
    if ($gitBranch -or $gitCommit) {
        $gitCleanStr = if ($null -eq $gitClean) { "" } elseif ($gitClean) { " (clean)" } else { " (DIRTY)" }
        $gitColor    = if ($null -eq $gitClean) { "Gray" } elseif ($gitClean) { "Green" } else { "Red" }
        Write-Col "Git" "$gitBranch @ $gitCommit$gitCleanStr" $gitColor
    } else {
        Write-Col "Git" "not yet checked" "Gray"
    }

    # ---- RISK ROW ----
    Write-Col "Risk" "$riskScore  $riskReason" $riskColor

    # ---- ERRORS ----
    if (@($errors).Count -gt 0) {
        Write-Col "Recent errors" "($(@($errors).Count) total)" "Red"
        foreach ($e in (@($errors) | Select-Object -Last 3)) {
            $eAt  = if ($e.PSObject.Properties['at'])      { Format-Age $e.at }      else { "" }
            $eSrc = if ($e.PSObject.Properties['source'])  { $e.source }             else { "" }
            $eMsg = if ($e.PSObject.Properties['message']) { $e.message }            else { "$e" }
            Write-Host "      [$eAt] [$eSrc] $eMsg" -ForegroundColor Red
        }
    }

    # ---- HISTORY (optional) ----
    if ($ShowHistory) {
        $histNode = Get-Prop $node "history"
        if ($histNode) {
            $valHist  = @(Get-Prop $histNode "validations"   @())
            $driftHist= @(Get-Prop $histNode "drift_events"  @())

            if (@($valHist).Count -gt 0) {
                Write-Host "    Validation history (last $([Math]::Min(5, @($valHist).Count))):" -ForegroundColor DarkGray
                foreach ($h in (@($valHist) | Select-Object -Last 5)) {
                    $hAt  = if ($h.PSObject.Properties['at'])      { Format-Age $h.at }  else { "" }
                    $hOv  = if ($h.PSObject.Properties['overall']) { $h.overall }        else { "?" }
                    $hCol = if ($hOv -eq "ALL_VALIDATIONS_PASS") { "Green" } else { "Red" }
                    Write-Host "      [$hAt] $hOv" -ForegroundColor $hCol
                }
            }

            if (@($driftHist).Count -gt 0) {
                Write-Host "    Drift history (last $([Math]::Min(5, @($driftHist).Count))):" -ForegroundColor DarkGray
                foreach ($h in (@($driftHist) | Select-Object -Last 5)) {
                    $hAt = if ($h.PSObject.Properties['at'])     { Format-Age $h.at } else { "" }
                    $hD  = if ($h.PSObject.Properties['detail']) { $h.detail }        else { "$h" }
                    Write-Host "      [$hAt] $hD" -ForegroundColor Yellow
                }
            }
        }
    }

    Write-Host ""
}

# ---------------------------------------------------------------
#  FOOTER SUMMARY
# ---------------------------------------------------------------
Write-Ruler
$totalProjects  = @($projectNames).Count
$passProjects   = @($projectNames | Where-Object {
    $v = Get-Prop (Get-Prop $projectMap.$_ "validation") "overall" "NEVER_RUN"
    $v -eq "ALL_VALIDATIONS_PASS" }) | Measure-Object | Select-Object -ExpandProperty Count
$blockProjects  = @($projectNames | Where-Object {
    $v = Get-Prop (Get-Prop $projectMap.$_ "validation") "overall" "NEVER_RUN"
    $v -eq "DEPLOYMENT_BLOCKED" }) | Measure-Object | Select-Object -ExpandProperty Count
$neverProjects  = $totalProjects - $passProjects - $blockProjects

Write-Host "  Summary: $totalProjects project(s)  " -NoNewline -ForegroundColor Gray
Write-Host "PASS:$passProjects  " -NoNewline -ForegroundColor Green
Write-Host "BLOCKED:$blockProjects  " -NoNewline -ForegroundColor $(if($blockProjects -gt 0){"Red"}else{"Gray"})
Write-Host "PENDING:$neverProjects" -ForegroundColor Gray
Write-Host "  governance_mode=$GOV_MODE  production_mutation=$GOV_MUTATION" -ForegroundColor DarkCyan
Write-Host ""

exit $overallExitCode
