$ErrorActionPreference="Stop"

$ROOT="D:\BossMind"
$LOG="$ROOT\bossmind-shared\logs\ultra-mode.log"
New-Item -ItemType Directory -Force "$ROOT\bossmind-shared\logs" | Out-Null

$PROJECTS=@(
  "bossmind-resumora",
  "bossmind-elegancyart",
  "bossmind-ai-video-generator",
  "bossmind-tiktok-ai",
  "bossmind-global-stock"
)

function Log($m){
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Tee-Object -FilePath $LOG -Append
}

foreach($project in $PROJECTS){
  $path=Join-Path $ROOT $project
  Log "ULTRA_CHECK: $project"

  if(!(Test-Path $path)){
    Log "MISSING_PROJECT: $project"
    continue
  }

  Set-Location $path

  git fetch --all | Out-Null

  $dirty=(git status --short)
  if($dirty){
    Log "UNCOMMITTED_CHANGES_FOUND: $project"
    git add .
    git commit -m "BossMind ultra-mode auto-save" 2>$null
    git push 2>$null
    Log "AUTO_SAVED_AND_PUSHED: $project"
  } else {
    Log "CLEAN: $project"
  }

  if(Test-Path "package.json"){
    npm audit --audit-level=high 2>$null
    Log "SECURITY_AUDIT_DONE: $project"
  }

  Log "ULTRA_OK: $project"
}

Log "ULTRA_MODE_COMPLETE"
