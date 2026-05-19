param(
  [string]$TaskFile = "D:\BossMind\bossmind-shared\automation\tasks.json",
  [string]$LogFile = "D:\BossMind\bossmind-shared\automation\task-engine-log.json"
)

Write-Output "TASK_ENGINE_START"

if (!(Test-Path $TaskFile)) {
  Write-Output "TASK_FILE_MISSING"
  exit 1
}

$tasks = Get-Content $TaskFile | ConvertFrom-Json
$log = @()

foreach ($task in $tasks) {

  if ($task.status -eq "done") {
    Write-Output "SKIPPED_DONE:$($task.name)"
    continue
  }

  Write-Output "RUNNING:$($task.name)"

  $start = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

  cmd /c $task.command
  $exitCode = $LASTEXITCODE

  $end = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

  $log += [pscustomobject]@{
    id = $task.id
    name = $task.name
    command = $task.command
    start = $start
    end = $end
    exit_code = $exitCode
  }

  if ($exitCode -ne 0) {
    $task.status = "failed"
    $tasks | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $TaskFile
    $log | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $LogFile

    Write-Output "FAILED:$($task.name)"
    Write-Output "TASK_ENGINE_STOPPED"
    exit 1
  }

  $task.status = "done"
  $tasks | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $TaskFile

  Write-Output "DONE:$($task.name)"
}

$log | ConvertTo-Json -Depth 10 | Set-Content -Encoding UTF8 $LogFile

Write-Output "TASK_ENGINE_COMPLETE"
exit 0
