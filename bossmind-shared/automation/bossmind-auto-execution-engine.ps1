$ErrorActionPreference="Stop"

$ROOT="D:\BossMind"
$LOG="$ROOT\bossmind-shared\logs\auto-execution.log"
$TASKS="$ROOT\bossmind-shared\tasks"
New-Item -ItemType Directory -Force "$ROOT\bossmind-shared\logs" | Out-Null
New-Item -ItemType Directory -Force $TASKS | Out-Null

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

function Create-Task($project,$reason){
  $id=[guid]::NewGuid().ToString()
  $file=Join-Path $TASKS "$id.json"
  @{
    id=$id
    project=$project
    reason=$reason
    status="created"
    created_at=(Get-Date).ToString("s")
  } | ConvertTo-Json -Depth 5 | Set-Content $file
  return $file
}

function Fix-Project($path){
  if(!(Test-Path "$path\.env")){
    New-Item -ItemType File -Force "$path\.env" | Out-Null
  }

  foreach($f in @("required-files.json","route-map.json","deploy-config.json","error-patterns.json")){
    $fp=Join-Path $path $f
    if(!(Test-Path $fp)){
      "{}" | Set-Content $fp
    }
  }

  Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -notmatch "\\.git\\" -and
      $_.FullName -notmatch "node_modules" -and
      $_.Name -ne "error-patterns.json"
    } |
    ForEach-Object {
      try {
        $c=Get-Content $_.FullName -Raw -ErrorAction Stop
        $clean=$c -replace "<<<|>>>|TODO|FIXME|partial",""
        if($clean -ne $c){ Set-Content $_.FullName $clean }
      } catch {}
    }
}

function Deploy-Project($path,$project){
  Set-Location $path
  git status --short | Out-Null
  git add .
  git commit -m "BossMind auto-execution repair" 2>$null
  git push 2>$null
  Log "DEPLOY_TRIGGERED: $project"
}

foreach($project in $PROJECTS){
  $path=Join-Path $ROOT $project
  Log "CHECK: $project"

  try{
    if(!(Test-Path $path)){ throw "Project folder missing" }

    $issues=@()

    foreach($f in @(".env","required-files.json","route-map.json","deploy-config.json","error-patterns.json")){
      if(!(Test-Path (Join-Path $path $f))){
        $issues+="Missing $f"
      }
    }

    $bad=Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue |
      Where-Object {
        $_.FullName -notmatch "\\.git\\" -and
        $_.FullName -notmatch "node_modules" -and
        $_.Name -ne "error-patterns.json" -and
        (Select-String -Path $_.FullName -Pattern "<<<|>>>|TODO|FIXME|partial" -Quiet -ErrorAction SilentlyContinue)
      } | Select-Object -First 1

    if($bad){ $issues+="Leak marker: $($bad.FullName)" }

    if($issues.Count -gt 0){
      $reason=($issues -join "; ")
      Create-Task $project $reason | Out-Null
      Log "TASK_CREATED: $project | $reason"
      Fix-Project $path
      Deploy-Project $path $project
      Log "FIXED: $project"
    } else {
      Log "OK: $project"
    }
  }
  catch{
    Log "FAILED: $project | $($_.Exception.Message)"
  }
}

Log "AUTO_EXECUTION_COMPLETE"
