$ErrorActionPreference="SilentlyContinue"

$Apps = @(
  @{ Name="bossmind-resumora"; Path="D:\BossMind\bossmind-resumora"; Port=3000; Command="npm run dev" },
  @{ Name="bossmind-elegancyart"; Path="D:\BossMind\bossmind-elegancyart"; Port=3001; Command="npm run dev -- -p 3001" },
  @{ Name="bossmind-ai-video-generator"; Path="D:\BossMind\bossmind-ai-video-generator"; Port=3002; Command="npm run dev -- -p 3002" },
  @{ Name="bossmind-tiktok-ai"; Path="D:\BossMind\bossmind-tiktok-ai"; Port=3003; Command="npm run dev -- -p 3003" },
  @{ Name="bossmind-global-stock"; Path="D:\BossMind\bossmind-global-stock"; Port=3004; Command="npm run dev -- -p 3004" }
)

$Log="D:\BossMind\bossmind-shared\logs\bossmind-global-keepalive.log"

function Log($m){
  "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') $m" | Out-File -FilePath $Log -Append
}

foreach($App in $Apps){
  if(!(Test-Path $App.Path)){
    Log "MISSING: $($App.Name) folder not found"
    continue
  }

  $Listening = Get-NetTCPConnection -LocalPort $App.Port -State Listen -ErrorAction SilentlyContinue

  if($Listening){
    Log "OK: $($App.Name) already running on port $($App.Port)"
    continue
  }

  Log "STARTING: $($App.Name) on port $($App.Port)"

  Start-Process -FilePath "cmd.exe" -ArgumentList "/c cd /d `"$($App.Path)`" && $($App.Command)" -WindowStyle Minimized

  Start-Sleep -Seconds 8

  $Check = Get-NetTCPConnection -LocalPort $App.Port -State Listen -ErrorAction SilentlyContinue

  if($Check){
    Log "CONFIRMED: $($App.Name) running on http://localhost:$($App.Port)"
  } else {
    Log "FAILED: $($App.Name) not listening on port $($App.Port)"
  }
}

Log "GLOBAL_KEEPALIVE_CHECK_COMPLETE"
