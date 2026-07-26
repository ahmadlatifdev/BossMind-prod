<#
.SYNOPSIS
  Orchestrate all Resumora detectors and aggregate JSON results (detection-only).
#>
param(
  [string]$Project = "resumora",
  [string]$EvidenceDir = "",
  [switch]$Simulation
)
$ErrorActionPreference = "Continue"
. "D:\BossMind\engineering\detectors\_common.ps1"
$paths = Get-BossMindPaths -Project $Project
if (-not $EvidenceDir) {
  $EvidenceDir = Join-Path $paths.DetectionsRoot (Get-Date -Format "yyyyMMdd-HHmmss")
  New-Item -ItemType Directory -Path $EvidenceDir -Force | Out-Null
}

$detectors = @(
  "detect-build.ps1",
  "detect-runtime.ps1",
  "detect-auth.ps1",
  "detect-ui.ps1",
  "detect-security.ps1",
  "detect-resumora-specific.ps1",
  "detect-resumora-checkout.ps1"
)

$results = @()
$allFailures = @()
$overall = "PASS"

foreach ($d in $detectors) {
  $script = Join-Path "D:\BossMind\scripts\self-healing" $d
  $args = @("-Project", $Project, "-EvidenceDir", $EvidenceDir)
  if ($Simulation) { $args += "-Simulation" }
  $output = & powershell -NoProfile -ExecutionPolicy Bypass -File $script @args 2>&1 | Out-String
  $code = $LASTEXITCODE
  $jsonPath = Join-Path $EvidenceDir ($d -replace '\.ps1$', '.json')
  $parsed = $null
  if (Test-Path $jsonPath) {
    try { $parsed = Get-Content $jsonPath -Raw | ConvertFrom-Json } catch { $parsed = $null }
  }
  $status = if ($parsed) { $parsed.status } elseif ($code -ne 0) { "FAIL" } else { "PASS" }
  if ($status -eq "FAIL") { $overall = "FAIL" }
  elseif ($status -eq "WARNING" -and $overall -eq "PASS") { $overall = "WARNING" }
  if ($parsed -and $parsed.failures) {
    foreach ($f in @($parsed.failures)) { $allFailures += $f }
  }
  $results += [ordered]@{
    detector = ($d -replace '\.ps1$', '')
    status   = $status
    exitCode = $code
    evidence = $jsonPath
  }
}

$aggregate = [ordered]@{
  detector     = "detect-resumora"
  project      = $Project
  status       = $overall
  simulation   = [bool]$Simulation
  checks       = $results
  failures     = $allFailures
  evidencePath = (Join-Path $EvidenceDir "detect-resumora.json")
  generatedAt  = (Get-Date).ToString("o")
  mode         = "detection-only"
}
$aggJson = $aggregate | ConvertTo-Json -Depth 10
Set-Content -Path $aggregate.evidencePath -Value $aggJson -Encoding UTF8
Write-Output $aggJson
if ($overall -eq "FAIL") { exit 1 }
exit 0
