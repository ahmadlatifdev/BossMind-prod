# Block git commit when staged files contain secret patterns
$ErrorActionPreference = "Stop"
$patterns = @(
  'sk-proj-[A-Za-z0-9_-]{20,}',
  'sk-or-v1-[A-Za-z0-9]+',
  'ghp_[A-Za-z0-9]{20,}',
  'github_pat_[A-Za-z0-9_]+',
  'rnd_[A-Za-z0-9]+',
  'postgresql://[^:]+:[^@\s]+@'
)

$staged = git diff --cached --name-only --diff-filter=ACM 2>$null
if (-not $staged) { exit 0 }

$blocked = @()
$skipPaths = @(
  '11-scripts/bossmind-secret-scan.ps1',
  '11-scripts/bossmind-pre-commit-secrets.ps1',
  '11-scripts/bossmind-pre-push-secrets.ps1',
  'bossmind-shared/automation/anti-leak-fast.ps1'
)

foreach ($f in $staged) {
  if ($f -match '\.(png|jpg|lock)$') { continue }
  if ($f -match '\.env\.master\.local$') { continue }
  if ($skipPaths -contains ($f -replace '\\', '/')) { continue }
  $content = git show ":$f" 2>$null
  if (-not $content) { continue }
  foreach ($p in $patterns) {
    if ($content -match $p) {
      $blocked += $f
      break
    }
  }
}

if ($blocked.Count -gt 0) {
  Write-Host "COMMIT BLOCKED — likely secrets in staged files:" -ForegroundColor Red
  $blocked | ForEach-Object { Write-Host "  $_" }
  Write-Host "Use .env.master.local (gitignored) or rotate and remove secrets." -ForegroundColor Yellow
  exit 1
}
exit 0
