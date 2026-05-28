$Targets = @(
  "D:\BossMind",
  "D:\Shakhsy11"
)

$Ledger = "D:\BossMind\bossmind-shared\shared-memory\prae-events.log"

function Write-PraeEvent {
  param([string]$Event)

  $Entry = @{
    timestamp_utc = (Get-Date).ToUniversalTime().ToString("o")
    authority = "PRAE"
    event = $Event
  } | ConvertTo-Json -Compress

  Add-Content -Path $Ledger -Value $Entry -Encoding UTF8
}

foreach ($Target in $Targets) {

  if (Test-Path $Target) {

    $Watcher = New-Object IO.FileSystemWatcher
    $Watcher.Path = $Target
    $Watcher.IncludeSubdirectories = $true
    $Watcher.EnableRaisingEvents = $true

    Register-ObjectEvent $Watcher Created -Action {
      Write-PraeEvent "FILESYSTEM_CREATED"
    } | Out-Null

    Register-ObjectEvent $Watcher Deleted -Action {
      Write-PraeEvent "FILESYSTEM_DELETED"
    } | Out-Null

    Register-ObjectEvent $Watcher Changed -Action {
      Write-PraeEvent "FILESYSTEM_CHANGED"
    } | Out-Null

    Register-ObjectEvent $Watcher Renamed -Action {
      Write-PraeEvent "FILESYSTEM_RENAMED"
    } | Out-Null
  }
}

Write-PraeEvent "PRAE_RUNTIME_WATCH_ACTIVE"

while ($true) {
  Start-Sleep -Seconds 10
}
