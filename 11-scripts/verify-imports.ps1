# BossMind - scan workspace repos for invalid import aliases (ROOT, broken @/ paths)
param(
  [string]$Root = "D:\BossMind",
  [string[]]$RepoNames = @(
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock",
    "bossmind-master-admin",
    "bossmind-shared"
  )
)

$ErrorActionPreference = "Stop"
$patterns = @(
  'from\s+[''"]@?/?ROOT',
  'import\s+[''"]@?/?ROOT',
  'from\s+[''"]ROOT/',
  'require\s*\(\s*[''"]@?/?ROOT',
  'require\s*\(\s*[''"]ROOT/'
)

$fail = $false
Write-Host "BossMind verify-imports - root: $Root" -ForegroundColor Cyan

foreach ($repo in $RepoNames) {
  $dir = Join-Path $Root $repo
  if (-not (Test-Path $dir)) {
    Write-Host "  skip (missing): $repo" -ForegroundColor DarkGray
    continue
  }
  $ext = @("*.ts", "*.tsx", "*.js", "*.jsx", "*.mjs")
  $files = Get-ChildItem -Path $dir -Recurse -Include $ext -File -ErrorAction SilentlyContinue |
    Where-Object {
      $_.FullName -notmatch "\\node_modules\\" -and
      $_.FullName -notmatch "\\\.next\\" -and
      $_.FullName -notmatch "\\config\\bossmind-baseline-snapshots\\"
    }
  foreach ($f in $files) {
    $text = Get-Content -LiteralPath $f.FullName -Raw -ErrorAction SilentlyContinue
    if (-not $text) { continue }
    foreach ($pat in $patterns) {
      if ($text -match $pat) {
        Write-Host "  FAIL $($f.FullName) - pattern: $pat" -ForegroundColor Red
        $fail = $true
      }
    }
  }
  Write-Host "  scanned: $repo ($($files.Count) files)" -ForegroundColor Green
}

if ($fail) {
  Write-Host ""
  Write-Host "verify-imports: FAILED - fix invalid ROOT/@/ROOT imports before build/deploy." -ForegroundColor Red
  exit 1
}
Write-Host ""
Write-Host "verify-imports: OK" -ForegroundColor Green
exit 0
