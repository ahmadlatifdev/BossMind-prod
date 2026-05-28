#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Phase A1 - Realtime Filesystem Watcher (bossmind-resumora)
    Monitors the resumora project directory for mutations, scores risk,
    maintains a checksum registry, and writes an append-only event log.
.DESCRIPTION
    Uses .NET FileSystemWatcher for true realtime event detection (no polling).
    Events are queued thread-safely and dispatched every second.
    This script NEVER writes to the watched project directory.
    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED

    Outputs (all under shared-memory, never under the project):
      resumora-watcher-events.log         append-only event log
      resumora-checksum-registry.json     live SHA-256 registry
      resumora-rollback-checkpoint.json   snapshot on demand / at startup

    Run modes:
      Normal     : runs until Ctrl-C, logs all events
      -Snapshot  : takes a one-time checksum snapshot and exits
      -Validate  : reads existing registry, compares to disk, reports drift

.PARAMETER ProjectRoot
    Root of the project to watch.
    Default: D:\BossMind\bossmind-resumora
.PARAMETER SharedMemRoot
    Root of the shared-memory output directory.
    Default: D:\BossMind\bossmind-shared\shared-memory
.PARAMETER PRAEModulePath
    Path to PRAE-ExecutionGate.psm1 for violation logging.
    Default: D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1
.PARAMETER DispatchIntervalMs
    How often (milliseconds) the dispatcher processes queued events.
    Default: 1000 (1 second). Minimum: 200.
.PARAMETER Snapshot
    Take a one-time checksum snapshot of all tracked files and exit.
.PARAMETER Validate
    Compare current disk state against stored checksum registry and exit.
    Exits 0 if clean, exits 1 if drift detected.
.EXAMPLE
    # Run watcher (foreground, Ctrl-C to stop)
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "D:\BossMind\bossmind-shared\prae\PRAE-A1-Watcher-Resumora.ps1"

    # One-time snapshot
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-A1-Watcher-Resumora.ps1" -Snapshot

    # Drift validation (use in CI/pre-deploy)
    powershell.exe -NoProfile -ExecutionPolicy Bypass `
        -File "...\PRAE-A1-Watcher-Resumora.ps1" -Validate
#>

[CmdletBinding(DefaultParameterSetName = 'Watch')]
param(
    [string]$ProjectRoot    = "D:\BossMind\bossmind-resumora",
    [string]$SharedMemRoot  = "D:\BossMind\bossmind-shared\shared-memory",
    [string]$PRAEModulePath = "D:\BossMind\bossmind-shared\prae\scripts\PRAE-ExecutionGate.psm1",
    [string]$RuntimeGraphModulePath = "D:\BossMind\bossmind-shared\prae\PRAE-RuntimeGraph.ps1",
    [int]$DispatchIntervalMs = 1000,

    [Parameter(ParameterSetName = 'Snapshot')]
    [switch]$Snapshot,

    [Parameter(ParameterSetName = 'Validate')]
    [switch]$Validate
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# ---------------------------------------------------------------
#  GOVERNANCE CONSTANTS (ReadOnly)
# ---------------------------------------------------------------
Set-Variable -Name GraphGovMode     -Value "LOCKED"   -Option ReadOnly -Force
Set-Variable -Name GraphGovRepair   -Value "DISABLED"  -Option ReadOnly -Force
Set-Variable -Name GraphGovMutation -Value "NONE"      -Option ReadOnly -Force
Set-Variable -Name PROJECT_NAME -Value "bossmind-resumora" -Option ReadOnly -Force

# ---------------------------------------------------------------
#  OUTPUT PATHS (shared-memory only, never inside project)
# ---------------------------------------------------------------
$EventLog        = Join-Path $SharedMemRoot "resumora-watcher-events.log"
$ChecksumReg     = Join-Path $SharedMemRoot "resumora-checksum-registry.json"
$RollbackChk     = Join-Path $SharedMemRoot "resumora-rollback-checkpoint.json"

# ---------------------------------------------------------------
#  MONITORED FILE PATTERNS
# ---------------------------------------------------------------
$TrackedExtensions = @(
    '*.json', '*.js', '*.ts', '*.tsx', '*.jsx',
    '*.env', '*.yaml', '*.yml', '*.lock',
    '*.config', '*.mjs', '*.cjs', '*.toml'
)

# Directories to exclude from watching (exact segment names)
$ExcludedSegments = @('node_modules', '.next', '.git', 'dist', '.turbo', 'coverage', 'out')

# ---------------------------------------------------------------
#  RISK SCORING
# ---------------------------------------------------------------
function Get-RiskScore {
    param([string]$FilePath, [string]$ChangeType)
    $name = Split-Path $FilePath -Leaf
    $lower = $FilePath.ToLower().Replace('\', '/')

    # Deletions are always HIGH
    if ($ChangeType -eq 'Deleted') { return 'HIGH' }

    # Critical config files
    $highPatterns = @(
        'package.json', 'package-lock.json', 'railway.json',
        'railway.toml', 'render.yaml', 'next.config', '.env'
    )
    foreach ($p in $highPatterns) {
        if ($name -like "*$p*" -or $lower -like "*$p*") { return 'HIGH' }
    }

    # Critical directories
    if ($lower -match '/(middleware|stripe|auth|config)/') { return 'HIGH' }

    # Medium priority directories
    if ($lower -match '/(app|pages|lib|api|src)/') { return 'MEDIUM' }

    return 'LOW'
}

# ---------------------------------------------------------------
#  PATH FILTER: skip excluded directories
# ---------------------------------------------------------------
function Test-PathTracked {
    param([string]$FilePath)
    $segments = $FilePath.Split([IO.Path]::DirectorySeparatorChar)
    foreach ($seg in $segments) {
        if ($ExcludedSegments -contains $seg) { return $false }
    }
    return $true
}

# ---------------------------------------------------------------
#  SHA-256 CHECKSUM
# ---------------------------------------------------------------
function Get-FileChecksum {
    param([string]$FilePath)
    try {
        if (-not (Test-Path $FilePath -PathType Leaf)) { return 'FILE_ABSENT' }
        $sha = [System.Security.Cryptography.SHA256]::Create()
        $stream = [System.IO.File]::OpenRead($FilePath)
        try {
            $hash = $sha.ComputeHash($stream)
            return [System.BitConverter]::ToString($hash) -replace '-', ''
        } finally {
            $stream.Dispose()
            $sha.Dispose()
        }
    } catch {
        return "CHECKSUM_ERROR: $_"
    }
}

# ---------------------------------------------------------------
#  OUTPUT HELPERS
# ---------------------------------------------------------------
function Write-WatcherInfo  { param([string]$T) Write-Host "  [INFO ] $T" -ForegroundColor Gray    }
function Write-WatcherPass  { param([string]$T) Write-Host "  [PASS ] $T" -ForegroundColor Green   }
function Write-WatcherWarn  { param([string]$T) Write-Host "  [WARN ] $T" -ForegroundColor Yellow  }
function Write-WatcherHigh  { param([string]$T) Write-Host "  [HIGH ] $T" -ForegroundColor Red     }
function Write-WatcherMed   { param([string]$T) Write-Host "  [MED  ] $T" -ForegroundColor DarkYellow }

# ---------------------------------------------------------------
#  EVENT LOG WRITER (append-only)
# ---------------------------------------------------------------
function Write-WatcherEvent {
    param(
        [string]$ChangeType,
        [string]$FilePath,
        [string]$Risk,
        [string]$Checksum = "N/A",
        [string]$Extra = ""
    )
    $ts   = [DateTimeOffset]::UtcNow.ToString("o")
    $rel  = $FilePath.Replace($ProjectRoot, '').TrimStart('\').TrimStart('/')
    $line = "[$ts] $ChangeType | RISK:$Risk | $rel | SHA:$($Checksum.Substring(0, [Math]::Min(12,$Checksum.Length)))... | $Extra"
    try {
        $logDir = Split-Path $EventLog -Parent
        if (-not (Test-Path $logDir)) { New-Item -ItemType Directory -Path $logDir -Force | Out-Null }
        [System.IO.File]::AppendAllText($EventLog, $line + "`r`n", [System.Text.Encoding]::UTF8)
    } catch { <# non-fatal: console still shows the event #> }

    switch ($Risk) {
        'HIGH'   { Write-WatcherHigh "$ChangeType | $rel" }
        'MEDIUM' { Write-WatcherMed  "$ChangeType | $rel" }
        default  { Write-WatcherInfo "$ChangeType | $rel" }
    }
}

# ---------------------------------------------------------------
#  PRAE VIOLATION RELAY (optional  -  loads module if available)
# ---------------------------------------------------------------
$PRAELoaded = $false
if (Test-Path $PRAEModulePath) {
    try {
        if (-not (Get-Module 'PRAE-ExecutionGate' -ErrorAction SilentlyContinue)) {
            Import-Module $PRAEModulePath -Force -DisableNameChecking -ErrorAction Stop
        }
        $PRAELoaded = $true
    } catch {
        Write-WatcherWarn "PRAE module load failed (non-fatal): $_"
    }
}

# Load runtime graph module (optional - non-fatal if absent)
$GraphLoaded = $false
if (Test-Path $RuntimeGraphModulePath) {
    try {
        if (-not (Get-Module 'PRAE-RuntimeGraph' -ErrorAction SilentlyContinue)) {
            Import-Module $RuntimeGraphModulePath -Force -DisableNameChecking -ErrorAction Stop
        }
        $GraphLoaded = $true
    } catch {
        Write-WatcherWarn "RuntimeGraph module load failed (non-fatal): $_"
    }
}

function Send-PRAEDriftAlert {
    param([string]$FilePath, [string]$Detail)
    if (-not $PRAELoaded) { return }
    try {
        Write-PRAEViolation `
            -Type            DRIFT_ESCALATION_EVENT `
            -Detail          $Detail `
            -ExecutionContext "A1-WATCHER" `
            -CallerIdentity  "PRAE-A1-WATCHER-RESUMORA"
    } catch { <# non-fatal #> }
}

# ---------------------------------------------------------------
#  CHECKSUM REGISTRY HELPERS
# ---------------------------------------------------------------
function Read-ChecksumRegistry {
    if (Test-Path $ChecksumReg) {
        try {
            return (Get-Content $ChecksumReg -Raw -Encoding UTF8 | ConvertFrom-Json)
        } catch { }
    }
    return [PSCustomObject]@{ project=$PROJECT_NAME; files=[PSCustomObject]@{}; updated_at="" }
}

function Save-ChecksumRegistry {
    param([hashtable]$FileMap)
    $obj = [ordered]@{
        project        = $PROJECT_NAME
        governance_mode = $GraphGovMode
        updated_at     = [DateTimeOffset]::UtcNow.ToString("o")
        file_count     = @($FileMap.Keys).Count
        files          = $FileMap
    }
    $json = $obj | ConvertTo-Json -Depth 5
    $dir  = Split-Path $ChecksumReg -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    [System.IO.File]::WriteAllText($ChecksumReg, $json, [System.Text.Encoding]::UTF8)
}

# ---------------------------------------------------------------
#  SNAPSHOT: scan all tracked files and build checksum registry
# ---------------------------------------------------------------
function Invoke-ChecksumSnapshot {
    param([switch]$IsRollback)

    Write-WatcherInfo "Scanning $ProjectRoot for tracked files..."
    $fileMap = @{}
    $count   = 0

    if (-not (Test-Path $ProjectRoot)) {
        Write-WatcherWarn "Project root not found: $ProjectRoot"
        return $fileMap
    }

    $allFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $ResolvedPath = if ($_.PSObject.Properties.Name -contains "FullName") { $_.FullName } else { [string]$_ }
            $fileExt = [System.IO.Path]::GetExtension($ResolvedPath).ToLower()
            $baseName = [System.IO.Path]::GetFileName($ResolvedPath).ToLower()
            $isEnvFile = $baseName -like ".env*" -or $baseName -eq ".env"
            $trackedExts = @(".json",".js",".ts",".tsx",".jsx",".env",".yaml",
                             ".yml",".lock",".config",".mjs",".cjs",".toml","")
            (Test-PathTracked $ResolvedPath) -and ($fileExt -in $trackedExts -or $isEnvFile)
        }

    foreach ($file in $allFiles) {
        $checksum = Get-FileChecksum $file.FullName
        $rel      = $file.FullName.Replace($ProjectRoot, '').TrimStart('\').TrimStart('/')
        $risk     = Get-RiskScore $file.FullName 'Changed'
        $fileMap[$rel] = [ordered]@{
            checksum    = $checksum
            risk        = $risk
            size        = $file.Length
            last_write  = $file.LastWriteTimeUtc.ToString("o")
        }
        $count++
    }

    Write-WatcherInfo "Snapshot complete: $count files"
    return $fileMap
}

# ---------------------------------------------------------------
#  HEADER
# ---------------------------------------------------------------
Write-Host ""
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE A1 - Filesystem Watcher                    |" -ForegroundColor Cyan
Write-Host "  |  Project : bossmind-resumora                     |" -ForegroundColor DarkCyan
Write-Host "  |  governance_mode=LOCKED  mutation=NONE           |" -ForegroundColor DarkCyan
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""
Write-WatcherInfo "Project root : $ProjectRoot"
Write-WatcherInfo "Event log    : $EventLog"
Write-WatcherInfo "Checksum reg : $ChecksumReg"
Write-WatcherInfo "PRAE module  : $(if($PRAELoaded){'LOADED'}else{'NOT LOADED (non-fatal)'})"
Write-WatcherInfo "Mode         : $($PSCmdlet.ParameterSetName)"
Write-Host ""

# ---------------------------------------------------------------
#  MODE: SNAPSHOT
# ---------------------------------------------------------------
if ($Snapshot) {
    Write-WatcherInfo "Taking checksum snapshot..."
    $fileMap  = Invoke-ChecksumSnapshot
    Save-ChecksumRegistry -FileMap $fileMap

    # Also save as rollback checkpoint with timestamp
    $checkpoint = [ordered]@{
        project         = $PROJECT_NAME
        governance_mode = $GraphGovMode
        checkpoint_at   = [DateTimeOffset]::UtcNow.ToString("o")
        checkpoint_type = "MANUAL_SNAPSHOT"
        file_count      = @($fileMap.Keys).Count
        files           = $fileMap
    }
    [System.IO.File]::WriteAllText(
        $RollbackChk,
        ($checkpoint | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8)

    Write-WatcherPass "Snapshot saved: $($fileMap.Count) files"
    Write-WatcherPass "Checksum registry: $ChecksumReg"
    Write-WatcherPass "Rollback checkpoint: $RollbackChk"
    Write-WatcherInfo "governance_mode=$GraphGovMode  production_mutation=$GraphGovMutation"
    exit 0
}

# ---------------------------------------------------------------
#  MODE: VALIDATE (drift check)
# ---------------------------------------------------------------
if ($Validate) {
    Write-WatcherInfo "Comparing disk state against stored registry..."

    $registry = Read-ChecksumRegistry
    if (-not $registry.files) {
        Write-WatcherWarn "No checksum registry found. Run -Snapshot first."
        exit 1
    }

    $driftItems = [System.Collections.Generic.List[string]]::new()
    $newFiles   = [System.Collections.Generic.List[string]]::new()
    $missing    = [System.Collections.Generic.List[string]]::new()

    # Check registered files
    $regFiles = $registry.files | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($rel in $regFiles) {
        $fullPath = Join-Path $ProjectRoot $rel
        if (-not (Test-Path $fullPath)) {
            $missing.Add($rel)
            continue
        }
        $currentHash  = Get-FileChecksum $fullPath
        $registeredHash = $registry.files.$rel.checksum
        if ($currentHash -ne $registeredHash) {
            $driftItems.Add("MODIFIED: $rel")
        }
    }

    # Check for new unregistered files
    $diskFiles = Get-ChildItem -Path $ProjectRoot -Recurse -File -ErrorAction SilentlyContinue |
        Where-Object {
            $ResolvedPath = if ($_.PSObject.Properties.Name -contains 'FullName') { $_.FullName } else { [string]$_ }
            Test-PathTracked $ResolvedPath
        } |
        ForEach-Object {
            $ResolvedPath = if ($_.PSObject.Properties.Name -contains 'FullName') { $_.FullName } else { [string]$_ }
            $ResolvedPath.Replace($ProjectRoot,'').TrimStart('\').TrimStart('/')
        }
    foreach ($rel in $diskFiles) {
        if ($regFiles -notcontains $rel) {
            $newFiles.Add("NEW: $rel")
        }
    }

    Write-Host ""
    $totalDrift = @($driftItems).Count + @($missing).Count + @($newFiles).Count

    if (@($driftItems).Count -gt 0) {
        Write-WatcherWarn "Modified files ($(@($driftItems).Count)):"
        foreach ($d in $driftItems) { Write-WatcherWarn "  $d" }
    }
    if (@($missing).Count -gt 0) {
        Write-WatcherHigh "Missing files ($(@($missing).Count)):"
        foreach ($d in $missing) { Write-WatcherHigh "  $d" }
    }
    if (@($newFiles).Count -gt 0) {
        Write-WatcherInfo "New unregistered files ($(@($newFiles).Count)):"
        foreach ($d in $newFiles) { Write-WatcherInfo "  $d" }
    }

    Write-Host ""
    if ($totalDrift -eq 0) {
        Write-WatcherPass "DRIFT CHECK CLEAN - disk matches registry ($($regFiles.Count) files verified)"
        exit 0
    } else {
        Write-WatcherWarn "DRIFT DETECTED: $totalDrift item(s) differ from registry"
        Send-PRAEDriftAlert -FilePath $ProjectRoot -Detail "Validate mode: $totalDrift drift items in $PROJECT_NAME"
        exit 1
    }
}

# ---------------------------------------------------------------
#  MODE: WATCH (realtime)
# ---------------------------------------------------------------

# Validate project root exists
if (-not (Test-Path $ProjectRoot)) {
    Write-WatcherWarn "Project root not found: $ProjectRoot"
    Write-WatcherWarn "Watcher will start but will not detect events until path exists."
}

# Load or build initial checksum registry
$checksumMap = @{}
$registry = Read-ChecksumRegistry
if ($registry.files) {
    $regFiles = $registry.files | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name
    foreach ($rel in $regFiles) {
        $checksumMap[$rel] = $registry.files.$rel.checksum
    }
    Write-WatcherInfo "Loaded registry: $($checksumMap.Count) files"
} else {
    Write-WatcherInfo "No existing registry - taking startup snapshot..."
    $checksumMap = Invoke-ChecksumSnapshot
    Save-ChecksumRegistry -FileMap $checksumMap

    # Startup rollback checkpoint
    $checkpoint = [ordered]@{
        project         = $PROJECT_NAME
        governance_mode = $GraphGovMode
        checkpoint_at   = [DateTimeOffset]::UtcNow.ToString("o")
        checkpoint_type = "STARTUP_SNAPSHOT"
        file_count      = @($checksumMap.Keys).Count
        files           = $checksumMap
    }
    [System.IO.File]::WriteAllText(
        $RollbackChk,
        ($checkpoint | ConvertTo-Json -Depth 5),
        [System.Text.Encoding]::UTF8)
    Write-WatcherPass "Startup checkpoint saved: $($checksumMap.Count) files"
}

# Log startup event
Write-WatcherEvent -ChangeType "WATCHER_START" -FilePath $ProjectRoot `
    -Risk "LOW" -Checksum "000000000000" `
    -Extra "registry_files=$($checksumMap.Count) governance=$GraphGovMode"

# ---------------------------------------------------------------
#  FILESYSTEMWATCHER SETUP
# ---------------------------------------------------------------
$eventQueue = [System.Collections.Concurrent.ConcurrentQueue[PSCustomObject]]::new()

# Create ONE watcher on the project root with IncludeSubdirectories
$watcher                       = [System.IO.FileSystemWatcher]::new()
$watcher.Path                  = $ProjectRoot
$watcher.IncludeSubdirectories = $true
$watcher.NotifyFilter          = (
    [System.IO.NotifyFilters]::FileName    -bor
    [System.IO.NotifyFilters]::DirectoryName -bor
    [System.IO.NotifyFilters]::LastWrite   -bor
    [System.IO.NotifyFilters]::Size
)
$watcher.EnableRaisingEvents   = $false   # enabled after handlers registered

# Shared enqueue closure
$enqueueScript = {
    param($sender, $e)
    $obj = [PSCustomObject]@{
        ChangeType = $e.ChangeType.ToString()
        FullPath   = $e.FullPath
        OldPath    = if ($e.PSObject.Properties['OldFullPath']) { $e.OldFullPath } else { $null }
        Queued     = [DateTimeOffset]::UtcNow
    }
    $eventQueue.Enqueue($obj) | Out-Null
}

# Register event handlers (Changed, Created, Deleted, Renamed)
$handlerChanged  = Register-ObjectEvent -InputObject $watcher -EventName 'Changed'  -Action $enqueueScript
$handlerCreated  = Register-ObjectEvent -InputObject $watcher -EventName 'Created'  -Action $enqueueScript
$handlerDeleted  = Register-ObjectEvent -InputObject $watcher -EventName 'Deleted'  -Action $enqueueScript
$handlerRenamed  = Register-ObjectEvent -InputObject $watcher -EventName 'Renamed'  -Action $enqueueScript

$watcher.EnableRaisingEvents = $true

Write-WatcherPass "FileSystemWatcher active on: $ProjectRoot"
Write-WatcherInfo "Dispatch interval: ${DispatchIntervalMs}ms | Press Ctrl-C to stop"

# Notify runtime graph: watcher started
if ($GraphLoaded) {
    try {
        Update-RuntimeGraph -ProjectName $PROJECT_NAME -ProjectRoot $ProjectRoot `
            -UpdateType WATCHER -WatcherStatus "RUNNING" `
            -RegistryFileCount @($checksumMap.Keys).Count `
            -SnapshotAt (if ($RollbackChk -and (Test-Path $RollbackChk)) {
                try { (Get-Content $RollbackChk -Raw | ConvertFrom-Json).checkpoint_at }
                catch { "" } } else { "" })
    } catch { <# non-fatal #> }
}
Write-Host ""

$eventCount    = 0
$highRiskCount = 0
$lastSave      = [DateTimeOffset]::UtcNow

# Cleanup on Ctrl-C
try {
    # ---------------------------------------------------------------
    #  DISPATCHER LOOP
    # ---------------------------------------------------------------
    while ($true) {
        Start-Sleep -Milliseconds $DispatchIntervalMs

        $item = [PSCustomObject]$null
        while ($eventQueue.TryDequeue([ref]$item)) {
            $path = $item.FullPath

            # Skip excluded directories
            if (-not (Test-PathTracked $path)) { continue }

            # Skip files with untracked extensions
            $ext = [System.IO.Path]::GetExtension($path).ToLower()
            $trackedExt = @('.json','.js','.ts','.tsx','.jsx','.env','.yaml',
                            '.yml','.lock','.config','.mjs','.cjs','.toml','')
            # Allow files with no extension if they're in a critical path (e.g. .env)
            $baseName = [System.IO.Path]::GetFileName($path).ToLower()
            $isEnv    = $baseName -like '.env*' -or $baseName -eq '.env'
            if ($ext -notin $trackedExt -and -not $isEnv) { continue }

            $changeType = $item.ChangeType
            $risk       = Get-RiskScore $path $changeType

            # Compute checksum (skip for deletions)
            $checksum = "N/A"
            if ($changeType -ne 'Deleted' -and (Test-Path $path -PathType Leaf)) {
                $checksum = Get-FileChecksum $path
            }

            # Update in-memory checksum map
            $rel = $path.Replace($ProjectRoot, '').TrimStart('\').TrimStart('/')
            if ($changeType -eq 'Deleted') {
                $checksumMap.Remove($rel)
            } else {
                $checksumMap[$rel] = $checksum
            }

            # Log event
            Write-WatcherEvent -ChangeType $changeType -FilePath $path `
                -Risk $risk -Checksum $checksum

            $eventCount++
            if ($risk -eq 'HIGH') {
                $highRiskCount++
                $driftDetail = "HIGH-RISK $changeType on $rel in $PROJECT_NAME"
                Send-PRAEDriftAlert -FilePath $path -Detail $driftDetail
                if ($GraphLoaded) {
                    try {
                        Update-RuntimeGraph -ProjectName $PROJECT_NAME `
                            -ProjectRoot $ProjectRoot -UpdateType WATCHER `
                            -WatcherStatus "RUNNING" -TotalEvents $eventCount `
                            -HighRiskEvents $highRiskCount `
                            -LastEventAt ([DateTimeOffset]::UtcNow.ToString('o')) `
                            -DriftEventDetail $driftDetail
                    } catch { <# non-fatal #> }
                }
            }

            # Handle rename: update old path entry
            if ($changeType -eq 'Renamed' -and $item.OldPath) {
                $oldRel = $item.OldPath.Replace($ProjectRoot,'').TrimStart('\').TrimStart('/')
                $checksumMap.Remove($oldRel)
                Write-WatcherEvent -ChangeType "RENAME_FROM" -FilePath $item.OldPath `
                    -Risk $risk -Checksum "N/A" -Extra "renamed_to=$rel"
            }
        }

        # Persist checksum registry every 30 seconds if events occurred
        $elapsed = ([DateTimeOffset]::UtcNow - $lastSave).TotalSeconds
        if ($elapsed -ge 30 -and $eventCount -gt 0) {
            try {
                Save-ChecksumRegistry -FileMap $checksumMap
                $lastSave = [DateTimeOffset]::UtcNow
                if ($GraphLoaded) {
                    Update-RuntimeGraph -ProjectName $PROJECT_NAME `
                        -ProjectRoot $ProjectRoot -UpdateType WATCHER `
                        -WatcherStatus "RUNNING" -TotalEvents $eventCount `
                        -HighRiskEvents $highRiskCount `
                        -RegistryFileCount @($checksumMap.Keys).Count `
                        -RegistryUpdatedAt ([DateTimeOffset]::UtcNow.ToString('o')) `
                        -LastEventAt ([DateTimeOffset]::UtcNow.ToString('o'))
                }
            } catch { <# non-fatal #> }
        }

        # Status line every 60 seconds
        if (([DateTimeOffset]::UtcNow.Second % 60) -eq 0 -and [DateTimeOffset]::UtcNow.Second -ne 59) {
            Write-WatcherInfo "Heartbeat: $eventCount events | $highRiskCount HIGH-RISK | registry: $($checksumMap.Count) files"
        }
    }
} finally {
    # ---------------------------------------------------------------
    #  CLEANUP: unregister event handlers, flush registry
    # ---------------------------------------------------------------
    $watcher.EnableRaisingEvents = $false
    foreach ($h in @($handlerChanged, $handlerCreated, $handlerDeleted, $handlerRenamed)) {
        try { Unregister-Event -SourceIdentifier $h.Name -ErrorAction SilentlyContinue } catch {}
    }
    $watcher.Dispose()

    # Final registry save
    try {
        Save-ChecksumRegistry -FileMap $checksumMap
    } catch {}

    # Stop event
    Write-WatcherEvent -ChangeType "WATCHER_STOP" -FilePath $ProjectRoot `
        -Risk "LOW" -Checksum "000000000000" `
        -Extra "total_events=$eventCount high_risk=$highRiskCount"

    Write-Host ""
    if ($GraphLoaded) {
        try {
            Update-RuntimeGraph -ProjectName $PROJECT_NAME -ProjectRoot $ProjectRoot `
                -UpdateType WATCHER -WatcherStatus "STOPPED" `
                -TotalEvents $eventCount -HighRiskEvents $highRiskCount `
                -RegistryFileCount @($checksumMap.Keys).Count `
                -RegistryUpdatedAt ([DateTimeOffset]::UtcNow.ToString('o'))
        } catch { <# non-fatal #> }
    }
    Write-WatcherInfo "Watcher stopped. Total events: $eventCount | HIGH-RISK: $highRiskCount"
    Write-WatcherInfo "governance_mode=$GraphGovMode  production_mutation=$GraphGovMutation"
    Write-Host ""
}
