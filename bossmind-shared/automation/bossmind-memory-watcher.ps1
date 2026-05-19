# BossMind Real-Time Auto Memory Watcher - Max Speed
# Watches all BossMind projects and logs confirmed changes into Neon-ready memory/event payloads.

$ErrorActionPreference = "Stop"

$BossRoot = "D:\BossMind"
$SharedRoot = "$BossRoot\bossmind-shared"
$LogDir = "$SharedRoot\logs"
$MemoryQueue = "$SharedRoot\logs\memory-watcher-queue.jsonl"

$Projects = @(
  "$BossRoot\bossmind-master-admin",
  "$BossRoot\bossmind-resumora",
  "$BossRoot\bossmind-elegancyart",
  "$BossRoot\bossmind-ai-video-generator",
  "$BossRoot\bossmind-tiktok-ai",
  "$BossRoot\bossmind-global-stock",
  "$BossRoot\bossmind-shared"
)

$IgnoredFolders = @(
  "\node_modules\",
  "\.git\",
  "\.next\",
  "\dist\",
  "\build\",
  "\coverage\",
  "\logs\",
  "\tmp\",
  "\temp\"
)

$AllowedExtensions = @(
  ".ts", ".tsx", ".js", ".jsx", ".json", ".ps1", ".md",
  ".env", ".yml", ".yaml", ".css", ".html", ".sql"
)

if (!(Test-Path $LogDir)) {
  New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

if (!(Test-Path $MemoryQueue)) {
  New-Item -ItemType File -Path $MemoryQueue -Force | Out-Null
}

function Test-IgnoredPath {
  param([string]$Path)

  foreach ($folder in $IgnoredFolders) {
    if ($Path -like "*$folder*") {
      return $true
    }
  }

  return $false
}

function Get-ProjectKey {
  param([string]$Path)

  if ($Path -like "*bossmind-master-admin*") { return "master-admin" }
  if ($Path -like "*bossmind-resumora*") { return "resumora" }
  if ($Path -like "*bossmind-elegancyart*") { return "elegancyart" }
  if ($Path -like "*bossmind-ai-video-generator*") { return "ai-video-generator" }
  if ($Path -like "*bossmind-tiktok-ai*") { return "tiktok-ai" }
  if ($Path -like "*bossmind-global-stock*") { return "global-stock" }
  if ($Path -like "*bossmind-shared*") { return "shared" }

  return "unknown"
}

function Write-MemoryEvent {
  param(
    [string]$EventType,
    [string]$FullPath
  )

  if ([string]::IsNullOrWhiteSpace($FullPath)) {
    return
  }

  if (Test-IgnoredPath -Path $FullPath) {
    return
  }

  $extension = [System.IO.Path]::GetExtension($FullPath)

  if ($AllowedExtensions -notcontains $extension -and $extension -ne "") {
    return
  }

  $projectKey = Get-ProjectKey -Path $FullPath

  $payload = [ordered]@{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    system = "BossMind"
    watcher = "real-time-auto-memory-watcher"
    mode = "max-speed"
    event_type = $EventType
    project_key = $projectKey
    file_path = $FullPath
    status = "queued_for_memory_sync"
  }

  $json = $payload | ConvertTo-Json -Compress -Depth 8

  Add-Content -Path $MemoryQueue -Value $json -Encoding UTF8

  Write-Host "MEMORY QUEUED [$EventType] [$projectKey] $FullPath"
}

foreach ($project in $Projects) {
  if (!(Test-Path $project)) {
    Write-Host "SKIPPED missing path: $project"
    continue
  }

  $watcher = New-Object System.IO.FileSystemWatcher
  $watcher.Path = $project
  $watcher.IncludeSubdirectories = $true
  $watcher.EnableRaisingEvents = $true
  $watcher.NotifyFilter = [System.IO.NotifyFilters]'FileName, LastWrite, DirectoryName, Size'

  Register-ObjectEvent $watcher Changed -Action {
    Write-MemoryEvent -EventType "file_changed" -FullPath $Event.SourceEventArgs.FullPath
  } | Out-Null

  Register-ObjectEvent $watcher Created -Action {
    Write-MemoryEvent -EventType "file_created" -FullPath $Event.SourceEventArgs.FullPath
  } | Out-Null

  Register-ObjectEvent $watcher Renamed -Action {
    Write-MemoryEvent -EventType "file_renamed" -FullPath $Event.SourceEventArgs.FullPath
  } | Out-Null

  Register-ObjectEvent $watcher Deleted -Action {
    Write-MemoryEvent -EventType "file_deleted" -FullPath $Event.SourceEventArgs.FullPath
  } | Out-Null

  Write-Host "WATCHING: $project"
}

Write-Host ""
Write-Host "BossMind real-time auto memory watcher is ACTIVE."
Write-Host "Queue file:"
Write-Host $MemoryQueue
Write-Host ""
Write-Host "Keep this PowerShell window open."

while ($true) {
  Start-Sleep -Seconds 1
}