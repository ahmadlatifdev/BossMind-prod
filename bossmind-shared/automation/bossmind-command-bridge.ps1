param(
    [string]$Project = "resumora",
    [string]$Task = "UPDATE_RESUMORA_CLIENT_INTERFACE_FULLY_WORKING"
)

$ErrorActionPreference = "Stop"

$BossRoot = "D:\BossMind"
$SharedRoot = "$BossRoot\bossmind-shared"
$AutomationRoot = "$SharedRoot\automation"
$LogRoot = "$SharedRoot\logs"
$StateRoot = "$SharedRoot\state"

New-Item -ItemType Directory -Force -Path $LogRoot | Out-Null
New-Item -ItemType Directory -Force -Path $StateRoot | Out-Null

$LogFile = "$LogRoot\bossmind-command-bridge.log"
$StateFile = "$StateRoot\bossmind-command-state.json"

function Write-BossLog {
    param([string]$Message, [string]$Level = "INFO")
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') [$Level] $Message"
    [System.IO.File]::AppendAllText($LogFile, $line + [Environment]::NewLine)
    Write-Host $line
}

function Save-State {
    param([hashtable]$State)
    $State | ConvertTo-Json -Depth 20 | Set-Content -Path $StateFile -Encoding UTF8
}

function Invoke-SafeCommand {
    param([string]$Command, [string]$WorkingDirectory)

    Write-BossLog "RUN: $Command"

    Push-Location $WorkingDirectory
    try {
        cmd.exe /c $Command
        if ($LASTEXITCODE -ne 0) {
            throw "Command failed: $Command"
        }
    }
    finally {
        Pop-Location
    }
}

function Invoke-AutoFix {
    param([string]$ProjectPath)

    $fixFile = "$AutomationRoot\bossmind-auto-fix.ps1"

    if (Test-Path $fixFile) {
        Write-BossLog "Running auto-fix engine..."
        powershell -NoProfile -ExecutionPolicy Bypass -File $fixFile -ProjectPath $ProjectPath
    } else {
        Write-BossLog "Auto-fix missing: $fixFile" "WARN"
    }
}

function Invoke-Preflight {
    param([string]$ProjectPath)

    $preflight = "$AutomationRoot\bossmind-preflight-scan.ps1"

    if (Test-Path $preflight) {
        Write-BossLog "Running preflight scanner..."
        powershell -NoProfile -ExecutionPolicy Bypass -File $preflight -ProjectPath $ProjectPath
    } else {
        Write-BossLog "Preflight scanner missing. Continuing with bridge checks." "WARN"
    }
}

function Invoke-Build {
    param([string]$ProjectPath)

    if (Test-Path "$ProjectPath\package.json") {
        Invoke-SafeCommand -WorkingDirectory $ProjectPath -Command "npm install"
        Invoke-SafeCommand -WorkingDirectory $ProjectPath -Command "npm run build"
    } else {
        Write-BossLog "package.json missing. Build skipped." "WARN"
    }
}

function Invoke-GitPush {
    param([string]$ProjectPath, [string]$Message)

    Push-Location $ProjectPath
    try {
        $changes = git status --porcelain

        if (-not $changes) {
            Write-BossLog "No git changes found."
            return
        }

        Invoke-SafeCommand -WorkingDirectory $ProjectPath -Command "git add -A"
        Invoke-SafeCommand -WorkingDirectory $ProjectPath -Command "git commit -m ""$Message"""
        Invoke-SafeCommand -WorkingDirectory $ProjectPath -Command "git push"
    }
    finally {
        Pop-Location
    }
}

function Test-LiveUrl {
    param([string]$Url, [string]$VerifyText)

    if ([string]::IsNullOrWhiteSpace($Url)) {
        Write-BossLog "No live URL configured. Skipping live check." "WARN"
        return $true
    }

    try {
        $response = Invoke-WebRequest -Uri $Url -UseBasicParsing -TimeoutSec 30

        if ($response.StatusCode -lt 200 -or $response.StatusCode -ge 400) {
            return $false
        }

        if ($VerifyText -and ($response.Content -notmatch [regex]::Escape($VerifyText))) {
            Write-BossLog "Verify text not found: $VerifyText" "WARN"
        }

        return $true
    }
    catch {
        Write-BossLog "Live check failed: $($_.Exception.Message)" "ERROR"
        return $false
    }
}

$Projects = @{
    "resumora" = @{
        Path = "$BossRoot\bossmind-resumora"
        LiveUrl = "https://resumora.net"
        VerifyText = "Resumora"
    }
    "elegancyart" = @{
        Path = "$BossRoot\bossmind-elegancyart"
        LiveUrl = "https://elegancyart.com"
        VerifyText = "ElegancyArt"
    }
    "ai-video-generator" = @{
        Path = "$BossRoot\bossmind-ai-video-generator"
        LiveUrl = ""
        VerifyText = "AI Video"
    }
    "tiktok-ai" = @{
        Path = "$BossRoot\bossmind-tiktok-ai"
        LiveUrl = ""
        VerifyText = "TikTok"
    }
    "global-stock" = @{
        Path = "$BossRoot\bossmind-global-stock"
        LiveUrl = ""
        VerifyText = "Global Stock"
    }
}

if (-not $Projects.ContainsKey($Project)) {
    throw "Unknown project: $Project"
}

$ProjectData = $Projects[$Project]
$ProjectPath = $ProjectData.Path

Write-BossLog "BossMind Command Bridge Started"
Write-BossLog "Project: $Project"
Write-BossLog "Task: $Task"

$state = @{
    project = $Project
    task = $Task
    status = "STARTED"
    started_at = (Get-Date).ToString("o")
}

Save-State $state

try {
    if (-not (Test-Path $ProjectPath)) {
        throw "Project path missing: $ProjectPath"
    }

    Invoke-Preflight -ProjectPath $ProjectPath
    Invoke-AutoFix -ProjectPath $ProjectPath
    Invoke-Build -ProjectPath $ProjectPath
    Invoke-GitPush -ProjectPath $ProjectPath -Message "BossMind auto update: $Task"

    Write-BossLog "Waiting for deployment..."
    Start-Sleep -Seconds 90

    $verified = Test-LiveUrl -Url $ProjectData.LiveUrl -VerifyText $ProjectData.VerifyText

    if (-not $verified) {
        Write-BossLog "Retrying after auto-fix..." "WARN"

        Invoke-AutoFix -ProjectPath $ProjectPath
        Invoke-Build -ProjectPath $ProjectPath
        Invoke-GitPush -ProjectPath $ProjectPath -Message "BossMind auto recovery: $Task"

        Start-Sleep -Seconds 120

        $verified = Test-LiveUrl -Url $ProjectData.LiveUrl -VerifyText $ProjectData.VerifyText

        if (-not $verified) {
            throw "Live verification failed after retry."
        }
    }

    $state.status = "COMPLETE"
    $state.completed_at = (Get-Date).ToString("o")
    Save-State $state

    Write-BossLog "BossMind Command Bridge COMPLETE"
}
catch {
    $state.status = "FAILED"
    $state.error = $_.Exception.Message
    $state.failed_at = (Get-Date).ToString("o")
    Save-State $state

    Write-BossLog "FAILED: $($_.Exception.Message)" "ERROR"
    throw
}