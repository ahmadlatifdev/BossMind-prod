param(
  [string]$ProjectPath="D:\BossMind\bossmind-resumora",
  [string]$Url="https://resumora.net/client",
  [string]$ExpectedText="Resumora Luxury Client Interface (LIVE)",
  [int]$MaxMinutes=10
)

$ErrorActionPreference="Continue"
$start=Get-Date
$stamp=Get-Date -Format "yyyyMMddHHmmss"
Write-Host "BossMind live auto-verify started..."

while(((Get-Date)-$start).TotalMinutes -lt $MaxMinutes){
  try{
    $checkUrl="$Url?bossmind_check=$stamp"
    $res=Invoke-WebRequest -Uri $checkUrl -UseBasicParsing -TimeoutSec 30
    if($res.Content -match [regex]::Escape($ExpectedText)){
      Write-Host " LIVE VERIFIED: New UI is active"
      exit 0
    } else {
      Write-Host " Live site responding, but new UI not visible yet. Retrying..."
    }
  } catch {
    Write-Host " Live check failed. Retrying..."
  }

  Start-Sleep -Seconds 30
}

Write-Host " Not live after wait. Forcing one rebuild..."
cd $ProjectPath
git commit --allow-empty -m "BossMind auto retry deploy $stamp"
git push

Start-Sleep -Seconds 120

$res=Invoke-WebRequest -Uri "$Url?bossmind_final=$stamp" -UseBasicParsing -TimeoutSec 30
if($res.Content -match [regex]::Escape($ExpectedText)){
  Write-Host " LIVE VERIFIED AFTER AUTO-RETRY"
  exit 0
}

Write-Host " LIVE VERIFY FAILED: Railway deployment layer needs API/status connection."
exit 1
