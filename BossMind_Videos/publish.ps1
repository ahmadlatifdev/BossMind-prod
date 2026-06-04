# BossMind Video Publisher (local orchestrator)
# Uses folder flags + optional webhook trigger (no hardcoded keys).
# Folder layout (relative to this script):
#   .\_LIVE\          -> input videos + flags
#   .\_PUBLISHED\     -> archived published videos
#   .\_ERROR\         -> failed items
# Log:
#   .\_LIVE\publish.log

$ErrorActionPreference = "Stop"

function Write-Log {
  param([string]$Msg)
  $ts = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $line = "[$ts] $Msg"
  Add-Content -Path $script:LOG -Value $line -Encoding UTF8
}

# Root = folder where publish.ps1 sits
$ROOT = Split-Path -Parent $MyInvocation.MyCommand.Path

$LIVE = Join-Path $ROOT "_LIVE"
$PUBLISHED = Join-Path $ROOT "_PUBLISHED"
$ERRORDIR = Join-Path $ROOT "_ERROR"

if (!(Test-Path $LIVE)) { throw "Missing folder: $LIVE" }

if (!(Test-Path $PUBLISHED)) { New-Item -ItemType Directory -Path $PUBLISHED | Out-Null }
if (!(Test-Path $ERRORDIR)) { New-Item -ItemType Directory -Path $ERRORDIR | Out-Null }

$LOG = Join-Path $LIVE "publish.log"
if (!(Test-Path $LOG)) { New-Item -ItemType File -Path $LOG | Out-Null }

Write-Log "=== PUBLISH RUN: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') ==="

# Flags (optional)
$flagPublish = Join-Path $LIVE "publish.flag"
$flagRun     = Join-Path $LIVE "run.flag"
$flagQueue   = Join-Path $LIVE "queue.flag"
$flagStatus  = Join-Path $LIVE "status.flag"

# Find latest MP4 in _LIVE
$video = Get-ChildItem -Path $LIVE -Filter "*.mp4" -File -ErrorAction SilentlyContinue |
         Sort-Object LastWriteTime -Descending |
         Select-Object -First 1

if (-not $video) {
  Write-Log "No .mp4 found in _LIVE. Nothing to publish."
  exit 0
}

Write-Log "LIVE video detected: $($video.Name)"

# Mark status
try {
  "READY" | Set-Content -Path $flagStatus -Encoding UTF8
} catch {}

# Prepare output name (keeps original, adds timestamp)
$stamp = Get-Date -Format "yyyyMMdd-HHmmss"
$outName = "{0}_{1}{2}" -f [IO.Path]::GetFileNameWithoutExtension($video.Name), $stamp, $video.Extension
$outPath = Join-Path $PUBLISHED $outName

# Optional webhook trigger (set as an environment variable)
# Example later: $env:BOSSMIND_MAKE_WEBHOOK="https://hook.us2.make.com/xxxxx"
$WEBHOOK = $env:BOSSMIND_MAKE_WEBHOOK

try {
  Write-Log "Publishing: $($video.Name)"

  # 1) Move to _PUBLISHED (this is your 'published' archive step)
  Move-Item -Path $video.FullName -Destination $outPath -Force
  Write-Log "Moved to: $outPath"

  # 2) If webhook exists, notify Make/n8n/etc (hands-free trigger)
  if ($WEBHOOK -and $WEBHOOK.Trim().Length -gt 10) {
    Write-Log "Webhook detected. Triggering..."
    $payload = @{
      status    = "READY_TO_UPLOAD"
      file_name = $outName
      file_path = $outPath
      folder    = "BossMind_Videos"
      ts        = (Get-Date).ToString("o")
    } | ConvertTo-Json -Depth 5

    Invoke-RestMethod -Method Post -Uri $WEBHOOK -ContentType "application/json" -Body $payload | Out-Null
    Write-Log "Webhook OK."
  } else {
    Write-Log "No BOSSMIND_MAKE_WEBHOOK set. Skipping remote upload trigger."
  }

  # 3) Clean flags that should be one-shot
  foreach ($f in @($flagPublish,$flagRun,$flagQueue)) {
    if (Test-Path $f) { Remove-Item $f -Force -ErrorAction SilentlyContinue }
  }

  Write-Log "Done."
  exit 0
}
catch {
  Write-Log "ERROR: $($_.Exception.Message)"

  # Move any remaining mp4 (if still in _LIVE) into _ERROR
  try {
    if (Test-Path $video.FullName) {
      $errPath = Join-Path $ERRORDIR $video.Name
      Move-Item -Path $video.FullName -Destination $errPath -Force
      Write-Log "Moved to ERROR: $errPath"
    }
  } catch {}

  try { "ERROR" | Set-Content -Path $flagStatus -Encoding UTF8 } catch {}
  exit 1
}
