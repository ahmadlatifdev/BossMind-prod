# Live deployment verification — probes production APIs (non-destructive)
param(
  [string]$ProjectPath = "D:\BossMind\bossmind-resumora",
  [string[]]$Origins = @("https://www.resumora.net", "https://bossmind-resumora-web.onrender.com")
)

$ErrorActionPreference = "Continue"
$logRoot = "D:\BossMind\bossmind-shared\logs"
if (!(Test-Path $logRoot)) { New-Item -ItemType Directory -Path $logRoot -Force | Out-Null }

function Invoke-ProbeJson {
  param([string]$Url, [string]$Method = "GET", [string]$Body = $null)
  try {
    $params = @{
      Uri             = $Url
      Method          = $Method
      TimeoutSec      = 35
      UseBasicParsing = $true
    }
    if ($Body) {
      $params.ContentType = "application/json"
      $params.Body = $Body
    }
    $r = Invoke-WebRequest @params
    $parsed = $null
    try { $parsed = $r.Content | ConvertFrom-Json } catch { $parsed = @{} }
    return @{ ok = $true; status = [int]$r.StatusCode; body = $parsed }
  } catch {
    $status = 0
    if ($_.Exception.Response) { $status = [int]$_.Exception.Response.StatusCode }
    return @{ ok = $false; status = $status; error = $_.Exception.Message }
  }
}

$sites = @()
foreach ($origin in $Origins) {
  $o = $origin.TrimEnd("/")
  $health = Invoke-ProbeJson "$o/api/health"
  $db = Invoke-ProbeJson "$o/api/runtime/database-health"
  $regBody = (@{
    email       = "deploy-verify-$(Get-Date -Format 'yyyyMMddHHmmss')@resumora.invalid"
    password    = "DeployVerify1!"
    displayName = "DeployVerify"
  } | ConvertTo-Json -Compress)
  $register = Invoke-ProbeJson "$o/api/engagement/register" "POST" $regBody
  $loginBody = '{"email":"probe@resumora.invalid","password":"wrong"}'
  $login = Invoke-ProbeJson "$o/api/engagement/login" "POST" $loginBody
  $stripe = Invoke-ProbeJson "$o/api/stripe/status"
  $bootstrap = Invoke-ProbeJson "$o/api/client/checkout-bootstrap?lang=en"

  $regOk = $register.status -eq 200 -or $register.status -eq 201
  $dbOk = $false
  if ($health.body.database) { $dbOk = $health.body.database.ok -eq $true }

  $sites += @{
    origin          = $o
    gitCommit       = $health.body.gitCommit
    databaseOk      = $dbOk
    registerStatus  = $register.status
    registerOk      = $regOk
    loginStatus     = $login.status
    stripeStatus    = $stripe.status
    bootstrapStatus = $bootstrap.status
    healthy         = ($dbOk -and $regOk -and $health.status -eq 200)
  }
}

$localHead = $null
if (Test-Path (Join-Path $ProjectPath ".git")) {
  Push-Location $ProjectPath
  try { $localHead = (git rev-parse HEAD 2>$null).Trim() } finally { Pop-Location }
}

$result = @{
  schema       = "bossmind-deploy-verify-live-v1"
  verifiedAt   = (Get-Date).ToUniversalTime().ToString("o")
  projectPath  = $ProjectPath
  localGitHead = $localHead
  sites        = $sites
  deployDrift  = ($sites | Where-Object { $_.gitCommit -and $localHead -and $_.gitCommit -ne $localHead }).Count -gt 0
  allHealthy   = ($sites | Where-Object { -not $_.healthy }).Count -eq 0
}

$result | ConvertTo-Json -Depth 12 | Out-File (Join-Path $logRoot "deploy-verify-log.json") -Encoding utf8
$memOut = Join-Path "D:\BossMind\13-shared-memory" "resumora-deploy-verify-live-$(Get-Date -Format 'yyyy-MM-dd').json"
$result | ConvertTo-Json -Depth 12 | Out-File $memOut -Encoding utf8

Write-Host "Deploy verify live: allHealthy=$($result.allHealthy) drift=$($result.deployDrift)" -ForegroundColor $(if ($result.allHealthy) { "Green" } else { "Yellow" })
if (-not $result.allHealthy) { exit 2 }
exit 0
