# BossMind Error Memory + Retry Engine (FINAL)

$ErrorActionPreference = "Stop"

$SharedRoot = "D:\BossMind\bossmind-shared"
$FailedFile = "$SharedRoot\logs\memory-watcher-failed.jsonl"
$EnvFile = "$SharedRoot\.env"

function Load-Env {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match "=") {
      $k,$v = $_ -split "=",2
      [Environment]::SetEnvironmentVariable($k.Trim(),$v.Trim(),"Process")
    }
  }
}

Load-Env

$DB = $env:DATABASE_URL

function Write-ErrorMemory {
  param($event,$err)

  $hash = "$($event.project_key)|$($event.event_type)|$($event.file_path)"
  $json = $event | ConvertTo-Json -Compress

  $sql = @"
INSERT INTO bossmind_error_memory
(project_key,error_type,error_message,error_hash,file_path,fix_applied,status)
VALUES
('$($event.project_key)',
 'runtime_error',
 '$($err.Replace("'", "''"))',
 '$($hash)',
 '$($event.file_path)',
 'retry_engine',
 'captured');
"@

  psql "$DB" -c $sql | Out-Null
}

function Send-ToNeon {
  param($event)

  $json = $event | ConvertTo-Json -Compress

  $sql = @"
INSERT INTO bossmind_unified_events
(project_key,event_type,entity_type,entity_id,event_data,created_at)
VALUES
('$($event.project_key)',
 '$($event.event_type)',
 'file',
 '$(New-Guid)',
 '$json'::jsonb,
 NOW());
"@

  psql "$DB" -c $sql | Out-Null
}

Write-Host "Error Memory + Retry Engine ACTIVE"

while ($true) {

  if (Test-Path $FailedFile) {

    $lines = Get-Content $FailedFile

    if ($lines.Count -gt 0) {

      Clear-Content $FailedFile

      foreach ($line in $lines) {

        try {
          $entry = $line | ConvertFrom-Json
          $event = $entry.raw | ConvertFrom-Json

          Send-ToNeon $event

          Write-Host "RETRY SUCCESS"

        } catch {

          Write-ErrorMemory $event $_.Exception.Message

          Add-Content $FailedFile $line

          Write-Host "ERROR STORED IN MEMORY"
        }
      }
    }
  }

  Start-Sleep -Seconds 5
}