# Purge secret-bearing paths from entire git history (destructive — coordinate with team)
param(
  [string]$HubRoot = $(if ($env:BOSSMIND_HUB_ROOT) { $env:BOSSMIND_HUB_ROOT } else { "D:\BossMind" }),
  [switch]$Confirm
)

$ErrorActionPreference = "Stop"
if (-not $Confirm) {
  Write-Host "Refusing to run without -Confirm. This rewrites git history and requires force-push." -ForegroundColor Red
  exit 1
}

$paths = @(
  "bossmind-shared/automation/.env.master",
  "bossmind-shared/.env.master",
  "bossmind-shared/Global-files/.env.master",
  "bossmind-shared/automation/.env.core",
  "16-neon/.env.bossmind",
  "09-archives/02-resumora/.env.local",
  "bossmind-master-admin/.env.local"
)

Push-Location $HubRoot
$filterRepo = Get-Command git-filter-repo -ErrorAction SilentlyContinue
if (-not $filterRepo) {
  Write-Host "Install git-filter-repo: pip install git-filter-repo" -ForegroundColor Yellow
  Write-Host "Or use BFG: https://rtyley.github.io/bfg-repo-cleaner/" -ForegroundColor Yellow
  Pop-Location
  exit 2
}

$args = @("--force")
foreach ($p in $paths) { $args += "--path"; $args += $p; $args += "--invert-paths" }
Write-Host "Running: git filter-repo $($args -join ' ')" -ForegroundColor Cyan
& git filter-repo @args

Write-Host "Run secret scan + force-push only after rotating all exposed keys:" -ForegroundColor Yellow
Write-Host "  .\11-scripts\bossmind-secret-scan.ps1"
Write-Host "  git push --force-with-lease origin <branch>"
Pop-Location
