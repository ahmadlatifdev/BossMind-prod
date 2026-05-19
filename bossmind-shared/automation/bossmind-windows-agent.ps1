# ===============================
# BossMind Windows Active Agent
# ===============================

$ErrorActionPreference = "SilentlyContinue"

# ===== CONFIG =====
$LogPath = "D:\BossMind\bossmind-shared\logs\bossmind-agent.log"

# 🔴 REPLACE WITH YOUR REAL NEON ENDPOINT
$NeonApi = "https://YOUR-NEON-ENDPOINT/api/tasks"

# LM Studio (optional fallback)
$LMStudioExe = "$env:LOCALAPPDATA\Programs\LM Studio\LM Studio.exe"
$LMCheckUrl = "http://127.0.0.1:1234/v1/models"

# ===== INIT =====
New-Item -ItemType Directory -Force -Path (Split-Path $LogPath) | Out-Null

function Log($msg) {
    $time = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    Add-Content -Path $LogPath -Value "[$time] $msg"
}

function Get-Tasks {
    try {
        $res = Invoke-RestMethod -Uri $NeonApi -Method GET -TimeoutSec 10
        return $res
    } catch {
        Log "ERROR: Failed to fetch tasks from Neon"
        return @()
    }
}

function Update-Task($id, $status, $output) {
    try {
        $body = @{
            status = $status
            output = $output
        } | ConvertTo-Json -Depth 5

        Invoke-RestMethod -Uri "$NeonApi/$id" -Method POST -Body $body -ContentType "application/json"
    } catch {
        Log "ERROR: Failed to update task $id"
    }
}

function Run-Command($cmd) {
    try {
        Log "RUN: $cmd"
        $result = powershell -NoProfile -ExecutionPolicy Bypass -Command $cmd 2>&1
        return $result
    } catch {
        return "ERROR: $_"
    }
}

function Test-LMStudio {
    try {
        $r = Invoke-WebRequest -Uri $LMCheckUrl -UseBasicParsing -TimeoutSec 5
        return ($r.StatusCode -eq 200)
    } catch {
        return $false
    }
}

function Start-LMStudio {
    if (!(Test-Path $LMStudioExe)) {
        Log "LM Studio not found"
        return
    }

    $running = Get-Process | Where-Object {
        $_.ProcessName -like "*LMStudio*" -or $_.ProcessName -like "*LM Studio*"
    }

    if (!$running) {
        Log "Starting LM Studio..."
        Start-Process -FilePath $LMStudioExe
        Start-Sleep -Seconds 15
    }

    if (Test-LMStudio) {
        Log "LM Studio ONLINE"
    } else {
        Log "LM Studio started but API OFFLINE"
    }
}

# ===== START =====
Log "BossMind ACTIVE AGENT STARTED"

while ($true) {

    # 1. Fetch tasks from Neon
    $tasks = Get-Tasks

    foreach ($t in $tasks) {

        if ($t.status -ne "pending") { continue }

        Log "TASK: $($t.id) → $($t.command)"

        # 2. Execute command
        $result = Run-Command $t.command

        # 3. Update result
        Update-Task $t.id "done" ($result | Out-String)

        Log "DONE: $($t.id)"
    }

    # 4. Optional: Keep LM Studio alive (fallback)
    if (!(Test-LMStudio)) {
        Log "LM Studio offline → restarting"
        Start-LMStudio
    }

    Start-Sleep -Seconds 10
}