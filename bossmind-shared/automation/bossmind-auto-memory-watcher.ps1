# BossMind Real-Time Auto Memory Watcher - Maximum Speed

$automationRoot = "D:\BossMind\bossmind-shared\automation"
$watchRoots = @(
    "D:\BossMind\bossmind-shared",
    "D:\BossMind\bossmind-master-admin",
    "D:\BossMind\bossmind-resumora",
    "D:\BossMind\bossmind-elegancyart",
    "D:\BossMind\bossmind-ai-video-generator",
    "D:\BossMind\bossmind-tiktok-ai",
    "D:\BossMind\bossmind-global-stock"
)

$exclude = "\\node_modules\\|\\.git\\|\\dist\\|\\build\\|\\logs\\|\\.next\\"
$pending = @{}

Write-Host "BossMind MAX-SPEED Auto Memory Watcher ACTIVE" -ForegroundColor Green

foreach ($root in $watchRoots) {
    if (Test-Path $root) {
        $watcher = New-Object System.IO.FileSystemWatcher
        $watcher.Path = $root
        $watcher.IncludeSubdirectories = $true
        $watcher.EnableRaisingEvents = $true
        $watcher.Filter = "*.*"

        Register-ObjectEvent $watcher Changed -Action {
            $path = $Event.SourceEventArgs.FullPath
            if ($path -notmatch $using:exclude -and $path -match "\.(js|ts|jsx|tsx|json|ps1)$") {
                $global:pending[$path] = Get-Date
            }
        } | Out-Null

        Register-ObjectEvent $watcher Created -Action {
            $path = $Event.SourceEventArgs.FullPath
            if ($path -notmatch $using:exclude -and $path -match "\.(js|ts|jsx|tsx|json|ps1)$") {
                $global:pending[$path] = Get-Date
            }
        } | Out-Null
    }
}

while ($true) {
    Start-Sleep -Seconds 3

    if ($pending.Count -gt 0) {
        $changedFiles = $pending.Keys
        $pending.Clear()

        foreach ($file in $changedFiles) {
            node "$automationRoot\bossmind-save-single-file.js" "$file"
        }

        Write-Host "Saved changed files:" $changedFiles.Count -ForegroundColor Green
    }
}