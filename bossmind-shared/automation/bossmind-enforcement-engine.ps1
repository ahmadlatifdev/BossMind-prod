$ErrorActionPreference="Stop"
$BASE_PATH="D:\BossMind"
$LOG_DIR="$BASE_PATH\bossmind-shared\logs"
$LOG_PATH="$LOG_DIR\enforcement.log"
New-Item -ItemType Directory -Force $LOG_DIR | Out-Null
"=== BossMind Enforcement Run $(Get-Date) ===" | Set-Content $LOG_PATH

$PROJECTS=@("bossmind-resumora","bossmind-elegancyart","bossmind-ai-video-generator","bossmind-tiktok-ai","bossmind-global-stock")
$REQUIRED=@("required-files.json","route-map.json","deploy-config.json","error-patterns.json",".env")

function AddLog($m){ $m | Tee-Object -FilePath $LOG_PATH -Append }

foreach($proj in $PROJECTS){
  $path=Join-Path $BASE_PATH $proj
  AddLog "CHECK: $proj"

  try{
    if(!(Test-Path $path)){ throw "Project folder missing: $path" }

    foreach($f in $REQUIRED){
      if(!(Test-Path (Join-Path $path $f))){
        throw "Missing required file: $f"
      }
    }

    $bad=Get-ChildItem $path -Recurse -File -ErrorAction SilentlyContinue | Where-Object {
      $_.FullName -notmatch "\\.git\\" -and
      $_.FullName -notmatch "node_modules" -and
      $_.Name -ne "error-patterns.json" -and
      (Select-String -Path $_.FullName -Pattern "<<<|>>>|TODO|FIXME|partial" -Quiet -ErrorAction SilentlyContinue)
    } | Select-Object -First 1

    if($bad){ throw "Leak marker found in: $($bad.FullName)" }

    Set-Location $path
    git status | Out-Null

    AddLog "OK: $proj"
  }
  catch{
    AddLog "ROLLBACK: $proj"
    AddLog "REASON: $($_.Exception.Message)"

    if(Test-Path $path){
      Set-Location $path
      git fetch --all
      git reset --hard origin/main
    }
  }
}

AddLog "SYSTEM ENFORCEMENT CHECK COMPLETE"
