# Block push if tracked env master files still contain live secret patterns
$ErrorActionPreference = "Stop"
$forbiddenTracked = @(
  "bossmind-shared/automation/.env.master",
  "bossmind-shared/.env.master",
  "bossmind-shared/Global-files/.env.master",
  "16-neon/.env.bossmind"
)

$patterns = @(
  'sk-proj-',
  'sk-or-v1-',
  'ghp_',
  'rnd_',
  'postgresql://[^:]+:[^@\s]+@'
)

foreach ($rel in $forbiddenTracked) {
  if (-not (Test-Path $rel)) { continue }
  $t = Get-Content -LiteralPath $rel -Raw -ErrorAction SilentlyContinue
  if (-not $t) { continue }
  foreach ($p in $patterns) {
    if ($t -match $p) {
      Write-Host "PUSH BLOCKED — $rel still contains secrets. Run bossmind-security-remediate.ps1 -MigrateToLocal -UntrackFromGit" -ForegroundColor Red
      exit 1
    }
  }
}
exit 0
