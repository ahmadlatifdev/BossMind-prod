# Emergency secret remediation — migrate to .local, untrack, install hooks, optional history purge
param(
  [string]$HubRoot = $(if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" }),
  [switch]$MigrateToLocal,
  [switch]$UntrackFromGit,
  [switch]$InstallHooks,
  [switch]$PurgeHistory,
  [switch]$RunPostVerify
)

$ErrorActionPreference = "Stop"

$trackedEnvPaths = @(
  "bossmind-shared\.env.master",
  "bossmind-shared\Global-files\.env.master",
  "bossmind-shared\automation\.env.master",
  "bossmind-shared\automation\.env.core",
  "16-neon\.env.bossmind",
  "09-archives\02-resumora\.env.local",
  "bossmind-master-admin\.env.local"
)

$template = @"
# BOSSMIND — runtime secrets moved to .env.master.local (gitignored)
# ROTATED — revoke any key ever committed. Fill .env.master.local only.
# Template: bossmind-shared/automation/.env.master.example

"@

function Migrate-FileToLocal {
  param([string]$RelPath)
  $full = Join-Path $HubRoot $RelPath
  if (-not (Test-Path $full)) { return }
  $local = "$full.local"
  if (-not (Test-Path $local)) {
    Copy-Item -LiteralPath $full -Destination $local -Force
    Write-Host "  backed up -> $($local.Replace($HubRoot, ''))" -ForegroundColor Cyan
  }
  Set-Content -LiteralPath $full -Value $template -Encoding utf8 -NoNewline
  Add-Content -LiteralPath $full -Value "NEON_DATABASE_URL=`nDATABASE_URL=`nOPENAI_API_KEY=`nOPENROUTER_API_KEY=`nGITHUB_TOKEN=`nRENDER_API_KEY=`n"
}

Write-Host "[security] BossMind emergency remediation" -ForegroundColor Magenta

if ($MigrateToLocal) {
  Write-Host "[security] Migrating tracked env files to *.local backups..." -ForegroundColor Cyan
  foreach ($rel in $trackedEnvPaths) { Migrate-FileToLocal -RelPath $rel }
}

if ($UntrackFromGit) {
  Write-Host "[security] Removing env files from git index..." -ForegroundColor Cyan
  Push-Location $HubRoot
  foreach ($rel in $trackedEnvPaths) {
    $full = Join-Path $HubRoot $rel
    if (Test-Path $full) {
      git rm --cached -f $rel 2>$null
    }
  }
  Pop-Location
}

if ($InstallHooks) {
  & (Join-Path $HubRoot "11-scripts\install-git-hooks.ps1")
}

if ($PurgeHistory) {
  Write-Host "[security] History purge requires git-filter-repo. Run:" -ForegroundColor Yellow
  Write-Host "  .\11-scripts\bossmind-git-history-purge-secrets.ps1 -Confirm"
}

& (Join-Path $HubRoot "11-scripts\bossmind-secret-scan.ps1")

if ($RunPostVerify) {
  $resumora = Join-Path $HubRoot "bossmind-resumora"
  if (Test-Path $resumora) {
    Push-Location $resumora
    npm run bossmind:hub-env-bootstrap 2>&1 | Out-Null
    npm run bossmind:ultra:stabilize 2>&1 | Out-Host
    Pop-Location
  }
}

Write-Host @"

[security] MANUAL ROTATION REQUIRED (cannot auto-revoke third-party keys):
  - OpenAI:     https://platform.openai.com/api-keys
  - OpenRouter: https://openrouter.ai/keys
  - Render:     https://dashboard.render.com
  - GitHub:     https://github.com/settings/tokens
  - Neon:       https://console.neon.tech (reset DB password / connection string)
  - Stripe:     https://dashboard.stripe.com/apikeys

After rotation: update bossmind-shared/automation/.env.master.local then:
  npm run bossmind:hub-env-bootstrap  (in bossmind-resumora)
  npm run bossmind:render:env-sync -- --apply  (if RENDER_API_KEY set)

"@ -ForegroundColor Yellow
