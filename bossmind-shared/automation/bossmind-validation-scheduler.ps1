$ErrorActionPreference = "Stop"

$loopFile = "D:\BossMind\bossmind-shared\automation\bossmind-auto-validation-loop.ps1"
$schedulerLog = "D:\BossMind\bossmind-shared\logs\bossmind-validation-scheduler-log.json"
$taskName = "BossMind-Continuous-Validation-Layer"

$action = New-ScheduledTaskAction -Execute "powershell.exe" -Argument "-NoProfile -ExecutionPolicy Bypass -File "$loopFile""
$trigger = New-ScheduledTaskTrigger -Once -At (Get-Date).AddMinutes(1) -RepetitionInterval (New-TimeSpan -Minutes 5)
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -StartWhenAvailable

if (Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue) {
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
}

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Description "BossMind continuous validation loop for all 5 projects" | Out-Null

Start-ScheduledTask -TaskName $taskName

$report = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    step = "Step #10"
    layer = "BossMind Continuous Validation Scheduler"
    scope = "All 5 projects"
    scheduled_task = $taskName
    interval_minutes = 5
    status = "ACTIVE"
}

$report | ConvertTo-Json -Depth 20 | Set-Content -Path $schedulerLog -Encoding UTF8

Write-Host "✅ Step #10 COMPLETE"
Write-Host "✅ Continuous Validation Scheduler ACTIVE"
Write-Host "✅ Runs every 5 minutes"
Write-Host "✅ Task name: $taskName"
Write-Host "✅ Log saved: $schedulerLog"
