# Install BossMind pre-commit / pre-push secret guards
param(
  [string]$HubRoot = $(if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" })
)

$ErrorActionPreference = "Stop"
$hooksDir = Join-Path $HubRoot ".githooks"
New-Item -ItemType Directory -Force -Path $hooksDir | Out-Null

$preCommit = @'
#!/bin/sh
# BossMind — block commits containing likely secrets
ROOT="$(git rev-parse --show-toplevel)"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$ROOT/11-scripts/bossmind-pre-commit-secrets.ps1" || exit 1
'@

$prePush = @'
#!/bin/sh
# BossMind — block push if staged/working tree scan fails
ROOT="$(git rev-parse --show-toplevel)"
pwsh -NoProfile -ExecutionPolicy Bypass -File "$ROOT/11-scripts/bossmind-secret-scan.ps1" || exit 1
pwsh -NoProfile -ExecutionPolicy Bypass -File "$ROOT/11-scripts/bossmind-pre-push-secrets.ps1" || exit 1
'@

Set-Content -Path (Join-Path $hooksDir "pre-commit") -Value $preCommit -Encoding utf8 -NoNewline
Set-Content -Path (Join-Path $hooksDir "pre-push") -Value $prePush -Encoding utf8 -NoNewline

$gitHooks = Join-Path $HubRoot ".git\hooks"
New-Item -ItemType Directory -Force -Path $gitHooks | Out-Null

$hookBody = @"
#!/bin/sh
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$($HubRoot -replace '\\','/')/11-scripts/bossmind-pre-commit-secrets.ps1"
"@
$pushBody = @"
#!/bin/sh
exec pwsh -NoProfile -ExecutionPolicy Bypass -File "$($HubRoot -replace '\\','/')/11-scripts/bossmind-pre-push-secrets.ps1"
"@

Set-Content -Path (Join-Path $gitHooks "pre-commit") -Value $hookBody -Encoding utf8 -NoNewline
Set-Content -Path (Join-Path $gitHooks "pre-push") -Value $pushBody -Encoding utf8 -NoNewline

Write-Host "Installed git hooks -> $gitHooks" -ForegroundColor Green
