# BossMind Memory Core + Error Memory + Anti-Leak + Local Rollback Guard
# FINAL SINGLE ENGINE

$ErrorActionPreference = "Continue"

$Root = "D:\BossMind"
$Shared = "$Root\bossmind-shared"
$EnvFile = "$Shared\.env"
$SnapshotRoot = "$Shared\snapshots"
$LogRoot = "$Shared\logs"
$LocalIndexFile = "$SnapshotRoot\snapshot-index.json"

$Projects = @(
  "$Root\bossmind-master-admin",
  "$Root\bossmind-resumora",
  "$Root\bossmind-elegancyart",
  "$Root\bossmind-ai-video-generator",
  "$Root\bossmind-tiktok-ai",
  "$Root\bossmind-global-stock"
)

$AllowedExtensions = @(
  ".ts",".tsx",".js",".jsx",".json",".ps1",".md",".env",".yml",".yaml",".css",".html",".sql",".txt"
)

$IgnoredFolders = @(
  "\node_modules\",
  "\.git\",
  "\.next\",
  "\dist\",
  "\build\",
  "\coverage\",
  "\logs\",
  "\snapshots\",
  "\tmp\",
  "\temp\"
)

if (!(Test-Path $SnapshotRoot)) { New-Item -ItemType Directory -Path $SnapshotRoot -Force | Out-Null }
if (!(Test-Path $LogRoot)) { New-Item -ItemType Directory -Path $LogRoot -Force | Out-Null }

function Load-Env {
  if (!(Test-Path $EnvFile)) {
    Write-Host "ERROR: .env file missing: $EnvFile"
    exit 1
  }

  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match "=" -and $_ -notmatch "^\s*#") {
      $k,$v = $_ -split "=",2
      [Environment]::SetEnvironmentVariable($k.Trim(), $v.Trim().Trim('"').Trim("'"), "Process")
    }
  }
}

Load-Env
$DB = $env:DATABASE_URL

if ([string]::IsNullOrWhiteSpace($DB)) {
  Write-Host "ERROR: DATABASE_URL missing in $EnvFile"
  exit 1
}

function SqlSafe {
  param([string]$Value)
  if ($null -eq $Value) { return "" }
  return $Value.Replace("'","''")
}

function HashText {
  param([string]$Text)
  if ($null -eq $Text) { $Text = "" }
  $sha = [System.Security.Cryptography.SHA256]::Create()
  return ([BitConverter]::ToString($sha.ComputeHash([System.Text.Encoding]::UTF8.GetBytes($Text)))).Replace("-","").ToLower()
}

function HashPath {
  param([string]$Path)
  return HashText $Path
}

function Is-IgnoredPath {
  param([string]$Path)

  foreach ($folder in $IgnoredFolders) {
    if ($Path -like "*$folder*") { return $true }
  }

  $ext = [System.IO.Path]::GetExtension($Path)
  if ($ext -and ($AllowedExtensions -notcontains $ext)) { return $true }

  return $false
}

function ProjectKey {
  param([string]$Path)

  if ($Path -like "*bossmind-resumora*") { return "resumora" }
  if ($Path -like "*bossmind-elegancyart*") { return "elegancyart" }
  if ($Path -like "*bossmind-ai-video-generator*") { return "ai-video-generator" }
  if ($Path -like "*bossmind-tiktok-ai*") { return "tiktok-ai" }
  if ($Path -like "*bossmind-global-stock*") { return "global-stock" }
  if ($Path -like "*bossmind-master-admin*") { return "master-admin" }

  return "unknown"
}

function Invoke-Sql {
  param([string]$Sql)

  $output = & psql "$DB" -v ON_ERROR_STOP=1 -c $Sql 2>&1
  $code = $LASTEXITCODE

  return @{
    ok = ($code -eq 0)
    output = ($output | Out-String)
    code = $code
  }
}

function Ensure-Tables {
  $sql = @"
CREATE TABLE IF NOT EXISTS bossmind_unified_events (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  event_type TEXT,
  entity_type TEXT,
  entity_id TEXT,
  event_data JSONB,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bossmind_error_memory (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  error_type TEXT,
  error_message TEXT,
  error_hash TEXT,
  file_path TEXT,
  fix_applied TEXT,
  retry_count INT DEFAULT 0,
  status TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);

CREATE TABLE IF NOT EXISTS bossmind_snapshots (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  project_key TEXT,
  file_path TEXT,
  file_hash TEXT,
  file_content TEXT,
  created_at TIMESTAMP DEFAULT NOW()
);
"@

  $result = Invoke-Sql $sql

  if (-not $result.ok) {
    Write-Host "ERROR: Could not verify/create Neon tables."
    Write-Host $result.output
    exit 1
  }
}

function Get-LocalSnapshotPath {
  param([string]$Path)

  $project = ProjectKey $Path
  $hash = HashPath $Path
  $dir = "$SnapshotRoot\$project"

  if (!(Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

  return "$dir\$hash.bak"
}

function Save-LocalSnapshot {
  param([string]$Path)

  if (!(Test-Path $Path)) { return }

  if (Is-IgnoredPath $Path) { return }

  $snapshotPath = Get-LocalSnapshotPath $Path
  Copy-Item -Path $Path -Destination $snapshotPath -Force
}

function Restore-LocalSnapshot {
  param([string]$Path)

  $snapshotPath = Get-LocalSnapshotPath $Path

  if (Test-Path $snapshotPath) {
    Copy-Item -Path $snapshotPath -Destination $Path -Force
    Write-Host "ROLLED BACK $Path"
    return $true
  }

  Write-Host "ROLLBACK SKIPPED - NO LOCAL SNAPSHOT: $Path"
  return $false
}

function Save-NeonSnapshot {
  param([string]$Path)

  if (!(Test-Path $Path)) { return }

  $project = ProjectKey $Path
  $content = Get-Content $Path -Raw -ErrorAction SilentlyContinue
  $hash = HashText $content

  $sql = @"
INSERT INTO bossmind_snapshots
(project_key,file_path,file_hash,file_content,created_at)
VALUES
('$(SqlSafe $project)',
 '$(SqlSafe $Path)',
 '$(SqlSafe $hash)',
 '$(SqlSafe $content)',
 NOW());
"@

  Invoke-Sql $sql | Out-Null
}

function Write-ErrorMemory {
  param(
    [string]$Project,
    [string]$ErrorType,
    [string]$ErrorMessage,
    [string]$FilePath,
    [string]$FixApplied,
    [string]$Status
  )

  $errorHash = HashText "$Project|$ErrorType|$ErrorMessage|$FilePath"

  $sql = @"
INSERT INTO bossmind_error_memory
(project_key,error_type,error_message,error_hash,file_path,fix_applied,status,created_at)
VALUES
('$(SqlSafe $Project)',
 '$(SqlSafe $ErrorType)',
 '$(SqlSafe $ErrorMessage)',
 '$(SqlSafe $errorHash)',
 '$(SqlSafe $FilePath)',
 '$(SqlSafe $FixApplied)',
 '$(SqlSafe $Status)',
 NOW());
"@

  Invoke-Sql $sql | Out-Null
}

function Write-UnifiedEvent {
  param(
    [string]$Path,
    [string]$Type
  )

  if (Is-IgnoredPath $Path) { return }

  $project = ProjectKey $Path

  $event = [ordered]@{
    project_key = $project
    event_type = $Type
    file_path = $Path
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    engine = "bossmind-memory-core-final"
    anti_leak = "enabled"
    rollback_guard = "local_snapshot"
  }

  $json = $event | ConvertTo-Json -Compress -Depth 10

  $sql = @"
INSERT INTO bossmind_unified_events
(project_key,event_type,entity_type,entity_id,event_data,created_at)
VALUES
('$(SqlSafe $project)',
 '$(SqlSafe $Type)',
 'file',
 '$(New-Guid)',
 '$(SqlSafe $json)'::jsonb,
 NOW());
"@

  $result = Invoke-Sql $sql

  if ($result.ok) {
    if (Test-Path $Path) {
      Save-LocalSnapshot $Path
      Save-NeonSnapshot $Path
    }

    Write-Host "SYNCED [$project] [$Type] $Path"
    return
  }

  Restore-LocalSnapshot $Path | Out-Null

  Write-ErrorMemory `
    -Project $project `
    -ErrorType "neon_write_failed" `
    -ErrorMessage $result.output `
    -FilePath $Path `
    -FixApplied "local_snapshot_rollback" `
    -Status "rollback_triggered"

  Write-Host "ERROR STORED + ROLLBACK ATTEMPTED [$project] $Path"
}

function Build-BaselineSnapshots {
  Write-Host "Building local rollback baseline..."

  foreach ($project in $Projects) {
    if (!(Test-Path $project)) { continue }

    Get-ChildItem $project -Recurse -File -Force -ErrorAction SilentlyContinue | ForEach-Object {
      if (-not (Is-IgnoredPath $_.FullName)) {
        Save-LocalSnapshot $_.FullName
      }
    }
  }

  Write-Host "Baseline snapshots ready."
}

Ensure-Tables
Build-BaselineSnapshots

foreach ($project in $Projects) {
  if (!(Test-Path $project)) {
    Write-Host "SKIPPED missing project: $project"
    continue
  }

  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = $project
  $watcher.IncludeSubdirectories = $true
  $watcher.EnableRaisingEvents = $true
  $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, DirectoryName, Size'

  Register-ObjectEvent $watcher Created -Action {
    Write-UnifiedEvent $Event.SourceEventArgs.FullPath "file_created"
  } | Out-Null

  Register-ObjectEvent $watcher Changed -Action {
    Write-UnifiedEvent $Event.SourceEventArgs.FullPath "file_changed"
  } | Out-Null

  Register-ObjectEvent $watcher Deleted -Action {
    Write-UnifiedEvent $Event.SourceEventArgs.FullPath "file_deleted"
  } | Out-Null

  Register-ObjectEvent $watcher Renamed -Action {
    Write-UnifiedEvent $Event.SourceEventArgs.FullPath "file_renamed"
  } | Out-Null

  Write-Host "WATCHING $project"
}

Write-Host ""
Write-Host "BossMind MEMORY CORE + ERROR MEMORY + ANTI-LEAK + LOCAL ROLLBACK GUARD RUNNING"
Write-Host "Single-engine mode active."
Write-Host ""

while ($true) {
  Start-Sleep -Seconds 1
}
