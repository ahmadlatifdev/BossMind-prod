# BossMind Neon Memory Sync Engine - Max Speed
# Reads memory-watcher queue and syncs events into Neon through DATABASE_URL.

$ErrorActionPreference = "Stop"

$SharedRoot = "D:\BossMind\bossmind-shared"
$QueueFile = "$SharedRoot\logs\memory-watcher-queue.jsonl"
$ProcessedFile = "$SharedRoot\logs\memory-watcher-processed.jsonl"
$FailedFile = "$SharedRoot\logs\memory-watcher-failed.jsonl"
$EnvFile = "$SharedRoot\.env"

function Load-EnvFile {
  param([string]$Path)

  if (!(Test-Path $Path)) {
    throw ".env file not found: $Path"
  }

  Get-Content $Path | ForEach-Object {
    if ($_ -match "^\s*#" -or $_ -notmatch "=") { return }

    $name, $value = $_ -split "=", 2
    $name = $name.Trim()
    $value = $value.Trim().Trim('"').Trim("'")

    [Environment]::SetEnvironmentVariable($name, $value, "Process")
  }
}

Load-EnvFile -Path $EnvFile

$DatabaseUrl = [Environment]::GetEnvironmentVariable("DATABASE_URL", "Process")

if ([string]::IsNullOrWhiteSpace($DatabaseUrl)) {
  throw "DATABASE_URL is missing from D:\BossMind\bossmind-shared\.env"
}

if (!(Test-Path $QueueFile)) {
  New-Item -ItemType File -Path $QueueFile -Force | Out-Null
}

if (!(Test-Path $ProcessedFile)) {
  New-Item -ItemType File -Path $ProcessedFile -Force | Out-Null
}

if (!(Test-Path $FailedFile)) {
  New-Item -ItemType File -Path $FailedFile -Force | Out-Null
}

function Invoke-NeonSync {
  param([object]$Event)

  $sql = @"
INSERT INTO bossmind_unified_events
(project_key, event_type, entity_type, entity_id, event_data, created_at)
VALUES
(
  '$($Event.project_key.Replace("'", "''"))',
  '$($Event.event_type.Replace("'", "''"))',
  'file',
  '$([guid]::NewGuid().ToString())',
  '$((($Event | ConvertTo-Json -Compress -Depth 10).Replace("'", "''")))'::jsonb,
  NOW()
);
"@

  $env:PGPASSWORD = ""

  $conn = New-Object Npgsql.NpgsqlConnection($env:DATABASE_URL); $conn.Open(); $cmd = $conn.CreateCommand(); $cmd.CommandText = $sql; $cmd.ExecuteNonQuery(); $conn.Close();
}

Write-Host "BossMind Neon Memory Sync Engine ACTIVE"
Write-Host "Reading queue:"
Write-Host $QueueFile

while ($true) {
  try {
    $lines = [System.IO.File]::ReadAllLines($QueueFile)

    if ($lines.Count -gt 0) {
      [System.IO.File]::WriteAllText($QueueFile, "")

      foreach ($line in $lines) {
        if ([string]::IsNullOrWhiteSpace($line)) { continue }

        try {
          $event = $line | ConvertFrom-Json
          Invoke-NeonSync -Event $event

          $processedPayload = [ordered]@{
            synced_at_utc = (Get-Date).ToUniversalTime().ToString("o")
            status = "synced_to_neon"
            source = $event
          }

          Add-Content -Path $ProcessedFile -Value ($processedPayload | ConvertTo-Json -Compress -Depth 12) -Encoding UTF8
          Write-Host "SYNCED [$($event.project_key)] [$($event.event_type)] $($event.file_path)"
        }
        catch {
          $failedPayload = [ordered]@{
            failed_at_utc = (Get-Date).ToUniversalTime().ToString("o")
            status = "failed_neon_sync"
            error = $_.Exception.Message
            raw = $line
          }

          Add-Content -Path $FailedFile -Value ($failedPayload | ConvertTo-Json -Compress -Depth 12) -Encoding UTF8
          Write-Host "FAILED: $($_.Exception.Message)"
        }
      }
    }
  }
  catch {
    Write-Host "SYNC LOOP ERROR: $($_.Exception.Message)"
  }

  Start-Sleep -Milliseconds 500
}



