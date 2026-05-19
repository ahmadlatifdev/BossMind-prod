# Scan for secret patterns — reports paths only, never prints values
param(
  [string]$Root = $(if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" }),
  [switch]$IncludeArchives
)

$ErrorActionPreference = "Stop"
$patterns = @(
  @{ Name = "openai_sk"; Regex = 'sk-proj-[A-Za-z0-9_-]{20,}' },
  @{ Name = "openai_legacy"; Regex = 'sk-[a-zA-Z0-9]{20,}' },
  @{ Name = "openrouter"; Regex = 'sk-or-v1-[A-Za-z0-9]+' },
  @{ Name = "github_pat"; Regex = 'ghp_[A-Za-z0-9]{20,}' },
  @{ Name = "github_pat_v2"; Regex = 'github_pat_[A-Za-z0-9_]+' },
  @{ Name = "render"; Regex = 'rnd_[A-Za-z0-9]+' },
  @{ Name = "neon_url"; Regex = 'postgresql://[^:]+:[^@\s]+@' },
  @{ Name = "stripe_sk"; Regex = 'sk_live_[A-Za-z0-9]+' },
  @{ Name = "stripe_test"; Regex = 'sk_test_[A-Za-z0-9]+' }
)

$skipDirs = @('node_modules', '.git', '.next', 'dist', 'build', 'windows-heal')
if (-not $IncludeArchives) { $skipDirs += '09-archives', '08-backups' }
$skipFiles = @(
  'bossmind-secret-scan.ps1',
  'bossmind-pre-commit-secrets.ps1',
  'bossmind-pre-push-secrets.ps1',
  'anti-leak-fast.ps1',
  '.env.master.example'
)

$hits = @()
Get-ChildItem -Path $Root -Recurse -File -ErrorAction SilentlyContinue | ForEach-Object {
  $rel = $_.FullName.Substring($Root.Length).TrimStart('\')
  foreach ($part in $skipDirs) {
    if ($rel -match [regex]::Escape($part)) { return }
  }
  if ($_.Name -match '\.(png|jpg|jpeg|gif|webp|ico|woff2?|ttf|eot|zip|lock)$') { return }
  if ($_.Name -match '\.local$' -or $_.Name -eq '.env' -or $_.Name -eq '.env.local') { return }
  foreach ($sf in $skipFiles) { if ($_.Name -eq $sf) { return } }
  if ($rel -match 'render-production-env\.env$') { return }
  if ($rel -match '13-shared-memory[\\/]security-') { return }
  try {
    $text = [IO.File]::ReadAllText($_.FullName)
  } catch { return }
  foreach ($p in $patterns) {
    if ($text -match $p.Regex) {
      $hits += [pscustomobject]@{ File = $rel; Pattern = $p.Name }
      break
    }
  }
}

$report = @{
  scannedAt = (Get-Date).ToUniversalTime().ToString("o")
  root = $Root
  hitCount = $hits.Count
  files = ($hits | Select-Object -ExpandProperty File -Unique)
  byPattern = $hits | Group-Object Pattern | ForEach-Object { @{ pattern = $_.Name; count = $_.Count } }
}

$outDir = Join-Path $Root "13-shared-memory"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$outPath = Join-Path $outDir "security-scan-latest.json"
$report | ConvertTo-Json -Depth 6 | Set-Content -Path $outPath -Encoding utf8

Write-Host "BossMind secret scan: $($hits.Count) hit(s) in $($report.files.Count) file(s)" -ForegroundColor $(if ($hits.Count -eq 0) { "Green" } else { "Red" })
if ($hits.Count -gt 0) {
  $report.files | ForEach-Object { Write-Host "  $_" -ForegroundColor Yellow }
  Write-Host "Report: $outPath"
  exit 2
}
Write-Host "Report: $outPath" -ForegroundColor Green
exit 0
