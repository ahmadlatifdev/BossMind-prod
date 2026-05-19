$ErrorActionPreference = "Stop"

$root = "D:\BossMind"
$shared = "$root\bossmind-shared"
$logs = "$shared\logs"
$proofLog = "$logs\bossmind-validation-final-proof-lock.json"

$projects = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
)

$requiredProjectItems = @(
    "automation",
    "required-files.json",
    "route-map.json",
    "deploy-config.json",
    "error-patterns.json"
)

$requiredSharedFiles = @(
    "bossmind-validation-engine.ps1",
    "bossmind-validation-runtime.ps1",
    "bossmind-master-validation-runner.ps1",
    "bossmind-auto-validation-loop.ps1",
    "bossmind-validation-scheduler.ps1"
)

$projectResults = @()
foreach ($project in $projects) {
    $projectPath = Join-Path $root $project
    $missing = @()

    foreach ($item in $requiredProjectItems) {
        if (!(Test-Path (Join-Path $projectPath $item))) {
            $missing += $item
        }
    }

    $projectResults += [ordered]@{
        project = $project
        status = if ($missing.Count -eq 0) { "PASSED" } else { "FAILED" }
        missing = $missing
    }
}

$sharedResults = @()
foreach ($file in $requiredSharedFiles) {
    $path = Join-Path "$shared\automation" $file
    $sharedResults += [ordered]@{
        file = $file
        exists = Test-Path $path
    }
}

$task = Get-ScheduledTask -TaskName "BossMind-Continuous-Validation-Layer" -ErrorAction SilentlyContinue

$finalStatus =
    if (
        (($projectResults | Where-Object { $_.status -eq "FAILED" }).Count -eq 0) -and
        (($sharedResults | Where-Object { $_.exists -eq $false }).Count -eq 0) -and
        ($null -ne $task)
    ) {
        "LOCKED_ACTIVE"
    } else {
        "FAILED"
    }

$report = [ordered]@{
    timestamp = (Get-Date).ToString("s")
    step = "Step #11"
    layer = "BossMind Validation Layer Final Proof Lock"
    scope = "All 5 projects"
    project_structure = $projectResults
    shared_validation_files = $sharedResults
    scheduler_exists = [bool]$task
    scheduler_state = if ($task) { $task.State.ToString() } else { "MISSING" }
    final_status = $finalStatus
}

$report | ConvertTo-Json -Depth 30 | Set-Content -Path $proofLog -Encoding UTF8

Write-Host "✅ Step #11 COMPLETE"
Write-Host "✅ Final proof check completed"
Write-Host "✅ Validation Layer status: $finalStatus"
Write-Host "✅ Log saved: $proofLog"
