#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Runtime Graph - Persistent Operational Memory
    Maintains a single JSON graph of real project state across all BossMind projects.
    Written to by A1 (watcher) and A2 (validator). Read by RuntimeGraph-Reader.
.DESCRIPTION
    Exports one public function: Update-RuntimeGraph
    All other functions are module-private helpers.

    Graph location:
      D:\BossMind\bossmind-shared\prae\runtime-graph\bossmind-runtime-graph.json

    Schema version: 1.0
    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED

    This module never reads from or writes to any project directory.
    It only reads from shared-memory files and writes to runtime-graph.
.NOTES
    Imported by A1 and A2 via:
      Import-Module "...\PRAE-RuntimeGraph.ps1" -Force -DisableNameChecking
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  MODULE CONSTANTS
# ---------------------------------------------------------------
$Script:GRAPH_ROOT    = "D:\BossMind\bossmind-shared\prae\runtime-graph"
$Script:GRAPH_FILE    = "$Script:GRAPH_ROOT\bossmind-runtime-graph.json"
$Script:SCHEMA_VER    = "1.0"
$Script:GraphGovMode      = "LOCKED"
$Script:GraphProductionMutation  = "NONE"
$Script:GraphGovRepair    = "DISABLED"
$Script:MAX_HISTORY   = 20
$Script:MAX_ERRORS    = 10

# All known projects in federation order (resumora = primary, rest = stubs)
$Script:KNOWN_PROJECTS = [ordered]@{
    "bossmind-resumora"          = "D:\BossMind\bossmind-resumora"
    "bossmind-elegancyart"       = "D:\BossMind\bossmind-elegancyart"
    "bossmind-ai-video-generator"= "D:\BossMind\bossmind-ai-video-generator"
    "bossmind-global-stock"      = "D:\BossMind\bossmind-global-stock"
    "bossmind-master-admin"      = "D:\BossMind\bossmind-master-admin"
}

# ---------------------------------------------------------------
#  PRIVATE: blank project node template
# ---------------------------------------------------------------
function New-ProjectNode {
    param([string]$ProjectName, [string]$ProjectRoot)
    $now = [DateTimeOffset]::UtcNow.ToString("o")
    return [ordered]@{
        project_name  = $ProjectName
        project_root  = $ProjectRoot
        registered_at = $now
        last_updated  = $now
        git           = [ordered]@{
            branch       = $null
            commit       = $null
            clean        = $null
            last_checked = $null
        }
        watcher       = [ordered]@{
            status             = "NEVER_STARTED"
            last_event_at      = $null
            total_events       = 0
            high_risk_events   = 0
            registry_file_count= $null
            registry_updated_at= $null
            snapshot_at        = $null
            last_updated       = $null
        }
        validation    = [ordered]@{
            last_run_at   = $null
            overall       = "NEVER_RUN"
            passed_count  = $null
            blocked_count = $null
            warning_count = $null
            failed_domains= @()
            last_updated  = $null
        }
        domains       = [ordered]@{
            GitState            = $null
            RequiredFiles       = $null
            EnvCompleteness     = $null
            DependencyIntegrity = $null
            BuildConfig         = $null
            RailwayConfig       = $null
            RollbackCheckpoint  = $null
            WatcherDrift        = $null
            PRAEGate            = $null
        }
        rollback      = [ordered]@{
            checkpoint_at   = $null
            checkpoint_type = $null
            file_count      = $null
        }
        risk          = [ordered]@{
            current_score = "UNKNOWN"
            reason        = $null
        }
        history       = [ordered]@{
            validations      = @()
            drift_events     = @()
            deployment_gates = @()
        }
        errors        = @()
    }
}

# ---------------------------------------------------------------
#  PRIVATE: read graph from disk (returns hashtable)
# ---------------------------------------------------------------
function Read-RuntimeGraph {
    if (-not (Test-Path $Script:GRAPH_FILE)) {
        return $null
    }
    try {
        $raw = [System.IO.File]::ReadAllText($Script:GRAPH_FILE, [System.Text.Encoding]::UTF8)
        return $raw | ConvertFrom-Json
    } catch {
        Write-Warning "PRAE-RuntimeGraph: Could not read graph file: $_"
        return $null
    }
}

# ---------------------------------------------------------------
#  PRIVATE: initialise graph with all 5 project stubs
# ---------------------------------------------------------------
function Initialize-RuntimeGraph {
    if (-not (Test-Path $Script:GRAPH_ROOT)) {
        New-Item -ItemType Directory -Path $Script:GRAPH_ROOT -Force | Out-Null
    }

    $now      = [DateTimeOffset]::UtcNow.ToString("o")
    $projects = [ordered]@{}
    foreach ($name in $Script:KNOWN_PROJECTS.Keys) {
        $projects[$name] = New-ProjectNode -ProjectName $name `
                                           -ProjectRoot $Script:KNOWN_PROJECTS[$name]
    }

    $graph = [ordered]@{
        schema_version  = $Script:SCHEMA_VER
        governance_mode = $Script:GraphGovMode
        production_mutation = $Script:GraphProductionMutation
        auto_repair     = $Script:GraphGovRepair
        initialized_at  = $now
        last_updated    = $now
        project_count   = @($Script:KNOWN_PROJECTS.Keys).Count
        projects        = $projects
    }

    Save-RuntimeGraph -Graph $graph
    return $graph
}

# ---------------------------------------------------------------
#  PRIVATE: write graph to disk atomically
# ---------------------------------------------------------------
function Save-RuntimeGraph {
    param($Graph)
    try {
        if (-not (Test-Path $Script:GRAPH_ROOT)) {
            New-Item -ItemType Directory -Path $Script:GRAPH_ROOT -Force | Out-Null
        }
        $json = $Graph | ConvertTo-Json -Depth 12
        # Write to temp file then move (atomic on NTFS)
        $tmp = $Script:GRAPH_FILE + ".tmp"
        [System.IO.File]::WriteAllText($tmp, $json, [System.Text.Encoding]::UTF8)
        Move-Item -Path $tmp -Destination $Script:GRAPH_FILE -Force
    } catch {
        Write-Warning "PRAE-RuntimeGraph: Could not save graph: $_"
    }
}

# ---------------------------------------------------------------
#  PRIVATE: get or create a project node (handles ConvertFrom-Json
#  returning PSCustomObject instead of hashtable)
# ---------------------------------------------------------------
function Get-ProjectNode {
    param($Graph, [string]$ProjectName, [string]$ProjectRoot)

    # ConvertFrom-Json returns PSCustomObject; check property existence
    if ($Graph.projects.PSObject.Properties[$ProjectName]) {
        return $Graph.projects.$ProjectName
    }
    # New project not in graph yet - create stub
    return New-ProjectNode -ProjectName $ProjectName -ProjectRoot $ProjectRoot
}

# ---------------------------------------------------------------
#  PRIVATE: append to a capped history array on a PSCustomObject node
# ---------------------------------------------------------------
function Add-HistoryEntry {
    param($Node, [string]$HistoryKey, $Entry, [int]$MaxItems = $Script:MAX_HISTORY)
    $existing = @()
    if ($Node.history.PSObject.Properties[$HistoryKey]) {
        $existing = @($Node.history.$HistoryKey)
    }
    $updated = @($existing) + @($Entry)
    if ($updated.Count -gt $MaxItems) {
        $updated = $updated | Select-Object -Last $MaxItems
    }
    return $updated
}

# ---------------------------------------------------------------
#  PRIVATE: compute risk from watcher + validation state
# ---------------------------------------------------------------
function Get-ProjectRiskScore {
    param($Node)

    # HIGH: any blocked domain or HIGH drift event in last hour
    $blockedCount = 0
    if ($Node.validation.PSObject.Properties['blocked_count'] -and
        $null -ne $Node.validation.blocked_count) {
        $blockedCount = [int]$Node.validation.blocked_count
    }
    if ($blockedCount -gt 0) {
        return [ordered]@{ current_score="HIGH"; reason="$blockedCount blocked validation domain(s)" }
    }

    $highDrift = 0
    if ($Node.watcher.PSObject.Properties['high_risk_events'] -and
        $null -ne $Node.watcher.high_risk_events) {
        $highDrift = [int]$Node.watcher.high_risk_events
    }
    if ($highDrift -gt 0) {
        return [ordered]@{ current_score="HIGH"; reason="$highDrift HIGH-risk drift event(s)" }
    }

    # MEDIUM: warnings or no recent validation
    $warnCount = 0
    if ($Node.validation.PSObject.Properties['warning_count'] -and
        $null -ne $Node.validation.warning_count) {
        $warnCount = [int]$Node.validation.warning_count
    }
    if ($warnCount -gt 0) {
        return [ordered]@{ current_score="MEDIUM"; reason="$warnCount validation warning(s)" }
    }

    $overall = if ($Node.validation.PSObject.Properties['overall']) {
        $Node.validation.overall } else { "NEVER_RUN" }
    if ($overall -eq "NEVER_RUN") {
        return [ordered]@{ current_score="MEDIUM"; reason="Validation never run" }
    }

    # LOW: all validations pass, no drift
    if ($overall -eq "ALL_VALIDATIONS_PASS") {
        return [ordered]@{ current_score="LOW"; reason="All validations pass, no drift" }
    }

    return [ordered]@{ current_score="MEDIUM"; reason="Unknown state" }
}

# ---------------------------------------------------------------
#  PUBLIC: Update-RuntimeGraph
#  Called by A1 (watcher) and A2 (validator) after each operation.
# ---------------------------------------------------------------
function Update-RuntimeGraph {
    <#
    .SYNOPSIS
        Writes project state into the runtime graph. Called by A1 and A2.
    .PARAMETER ProjectName
        Project key, e.g. "bossmind-resumora"
    .PARAMETER ProjectRoot
        Absolute path to project root.
    .PARAMETER UpdateType
        "WATCHER" or "VALIDATION"
    .PARAMETER WatcherStatus
        RUNNING | STOPPED | NEVER_STARTED
    .PARAMETER LastEventAt
        ISO timestamp of last watcher event.
    .PARAMETER TotalEvents
        Running count of watcher events this session.
    .PARAMETER HighRiskEvents
        Running count of HIGH-risk events this session.
    .PARAMETER RegistryFileCount
        Number of files in the checksum registry.
    .PARAMETER RegistryUpdatedAt
        ISO timestamp of last registry save.
    .PARAMETER SnapshotAt
        ISO timestamp of last rollback checkpoint.
    .PARAMETER DriftEventDetail
        If provided, appended to drift_events history.
    .PARAMETER ValidationRecord
        The full $record PSCustomObject from A2.
    .PARAMETER GitBranch
        Branch string from A2 GitState domain.
    .PARAMETER GitCommit
        Short commit hash from A2 GitState domain.
    .PARAMETER GitClean
        Boolean: true = clean working tree.
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)] [string]$ProjectName,
        [Parameter(Mandatory)] [string]$ProjectRoot,
        [Parameter(Mandatory)] [ValidateSet("WATCHER","VALIDATION")] [string]$UpdateType,

        # Watcher parameters
        [string]$WatcherStatus      = "",
        [string]$LastEventAt        = "",
        [int]   $TotalEvents        = -1,
        [int]   $HighRiskEvents     = -1,
        [int]   $RegistryFileCount  = -1,
        [string]$RegistryUpdatedAt  = "",
        [string]$SnapshotAt         = "",
        [string]$DriftEventDetail   = "",

        # Validation parameters
        $ValidationRecord           = $null,
        [string]$GitBranch          = "",
        [string]$GitCommit          = "",
        [string]$GitClean           = ""   # "True" | "False" | ""
    )

    $now = [DateTimeOffset]::UtcNow.ToString("o")

    # Load or init graph
    $graph = Read-RuntimeGraph
    if ($null -eq $graph) {
        $graph = Initialize-RuntimeGraph
        $graph = Read-RuntimeGraph   # re-read so we have consistent PSCustomObject
    }

    # Ensure project node exists
    $nodeExists = $graph.projects.PSObject.Properties[$ProjectName]
    if (-not $nodeExists) {
        # Add new project node - need to rebuild projects as ordered
        # (PSCustomObject from JSON doesn't support Add directly in PS5.1)
        $allProjects = [ordered]@{}
        foreach ($prop in $graph.projects.PSObject.Properties) {
            $allProjects[$prop.Name] = $prop.Value
        }
        $allProjects[$ProjectName] = New-ProjectNode -ProjectName $ProjectName `
                                                     -ProjectRoot $ProjectRoot
        # Re-build graph object with updated projects
        $graph.projects = [PSCustomObject]$allProjects
    }

    $node = $graph.projects.$ProjectName

    # ---- WATCHER UPDATE ----
    if ($UpdateType -eq "WATCHER") {
        if ($WatcherStatus)   { $node.watcher.status              = $WatcherStatus }
        if ($LastEventAt)     { $node.watcher.last_event_at       = $LastEventAt   }
        if ($TotalEvents -ge 0)    { $node.watcher.total_events        = $TotalEvents   }
        if ($HighRiskEvents -ge 0) { $node.watcher.high_risk_events    = $HighRiskEvents }
        if ($RegistryFileCount -ge 0) { $node.watcher.registry_file_count = $RegistryFileCount }
        if ($RegistryUpdatedAt)  { $node.watcher.registry_updated_at = $RegistryUpdatedAt }
        if ($SnapshotAt)         { $node.watcher.snapshot_at          = $SnapshotAt        }
        $node.watcher.last_updated = $now

        # Append drift event to history if provided
        if ($DriftEventDetail) {
            $driftEntry = [ordered]@{ at=$now; detail=$DriftEventDetail }
            $node.history.drift_events = Add-HistoryEntry -Node $node `
                -HistoryKey "drift_events" -Entry $driftEntry

            # Append to errors if HIGH
            if ($DriftEventDetail -like "*HIGH*") {
                $errEntry = [ordered]@{ at=$now; source="WATCHER"; message=$DriftEventDetail }
                $existing = @($node.errors)
                $node.errors = @(@($existing) + @($errEntry)) | Select-Object -Last $Script:MAX_ERRORS
            }
        }

        # Update rollback checkpoint info from SnapshotAt
        if ($SnapshotAt) {
            $node.rollback.checkpoint_at   = $SnapshotAt
            $node.rollback.checkpoint_type = "WATCHER_SNAPSHOT"
            if ($RegistryFileCount -ge 0) { $node.rollback.file_count = $RegistryFileCount }
        }
    }

    # ---- VALIDATION UPDATE ----
    if ($UpdateType -eq "VALIDATION" -and $ValidationRecord) {
        $vr = $ValidationRecord

        # Git state
        if ($GitBranch) { $node.git.branch = $GitBranch }
        if ($GitCommit) { $node.git.commit = $GitCommit }
        if ($GitClean)  { $node.git.clean  = ($GitClean -eq "True") }
        if ($GitBranch -or $GitCommit) { $node.git.last_checked = $now }

        # Validation summary
        $overall = if ($vr.PSObject.Properties['overall']) { $vr.overall } else { "UNKNOWN" }
        $node.validation.last_run_at   = $now
        $node.validation.overall       = $overall
        $node.validation.passed_count  = if ($vr.PSObject.Properties['passed_count'])  { $vr.passed_count  } else { $null }
        $node.validation.blocked_count = if ($vr.PSObject.Properties['blocked_count']) { $vr.blocked_count } else { $null }
        $node.validation.warning_count = if ($vr.PSObject.Properties['warning_count']) { $vr.warning_count } else { $null }
        $node.validation.last_updated  = $now

        # Failed domains list
        if ($vr.PSObject.Properties['domains']) {
            $failed = @($vr.domains | Where-Object { $null -ne $_ -and $_.PSObject.Properties['pass'] -and -not $_.pass -and $_.severity -eq 'BLOCKED' } | ForEach-Object { $_.domain })
            $node.validation.failed_domains = $failed
        }

        # Domain detail (pass/fail/detail per domain)
        if ($vr.PSObject.Properties['domains']) {
            foreach ($d in @($vr.domains)) {
                if (-not $d) { continue }
                $dn = if ($d.PSObject.Properties['domain']) { $d.domain } else { continue }
                if ($node.domains.PSObject.Properties[$dn]) {
                    $node.domains.$dn = [ordered]@{
                        pass     = $d.pass
                        detail   = if ($d.PSObject.Properties['detail'])   { $d.detail   } else { $null }
                        severity = if ($d.PSObject.Properties['severity']) { $d.severity } else { $null }
                    }
                }
            }
        }

        # Append to validation history
        $histEntry = [ordered]@{
            at            = $now
            overall       = $overall
            passed_count  = $node.validation.passed_count
            blocked_count = $node.validation.blocked_count
        }
        $node.history.validations = Add-HistoryEntry -Node $node `
            -HistoryKey "validations" -Entry $histEntry

        # Append errors for blocked domains
        if ($null -ne $node.validation.blocked_count -and [int]$node.validation.blocked_count -gt 0) {
            foreach ($fd in @($node.validation.failed_domains)) {
                $errEntry = [ordered]@{ at=$now; source="VALIDATION"; message="BLOCKED: domain $fd" }
                $existing = @($node.errors)
                $node.errors = @(@($existing) + @($errEntry)) | Select-Object -Last $Script:MAX_ERRORS
            }
        }
    }

    # ---- RECOMPUTE RISK ----
    $node.risk = Get-ProjectRiskScore -Node $node
    $node.last_updated = $now

    # ---- SAVE ----
    $graph.last_updated = $now
    Save-RuntimeGraph -Graph $graph
}

# ---------------------------------------------------------------
#  MODULE EXPORTS
# ---------------------------------------------------------------
Export-ModuleMember -Function @('Update-RuntimeGraph')

Write-Verbose "PRAE-RuntimeGraph module loaded (schema $Script:SCHEMA_VER) | governance=$Script:GraphGovMode"
