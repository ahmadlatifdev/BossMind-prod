# BossMind AI Sync - production verification (no secret values printed)
$ErrorActionPreference = "Continue"
$HubRoot = "D:\BossMind"
$SyncRoot = Join-Path $HubRoot "bossmind-shared\automation\ai-sync"
$Orchestrator = Join-Path $SyncRoot "bossmind-ai-sync-orchestrator.mjs"
$Results = @{}

function Record($Name, $Pass, $Detail) {
  $script:Results[$Name] = @{ pass = $Pass; detail = $Detail }
}

Write-Host "=== BossMind AI Sync Verification ===" -ForegroundColor Cyan
Write-Host "Timestamp: $(Get-Date -Format o)"

# 1. Git status (hub root)
Write-Host "`n--- git status (BossMind hub) ---"
Push-Location $HubRoot
$gitStatus = git status --short 2>&1 | Out-String
Pop-Location
Write-Host $gitStatus
Record "git_status" $true "captured"

# 2. File tree for orchestration / logs / locks
Write-Host "`n--- ai-sync file tree ---"
$treePaths = @(
  $SyncRoot,
  (Join-Path $SyncRoot "lib"),
  (Join-Path $SyncRoot "logs"),
  (Join-Path $SyncRoot "locks"),
  (Join-Path $SyncRoot "scripts")
)
foreach ($tp in $treePaths) {
  if (Test-Path $tp) {
    Get-ChildItem -Path $tp -Recurse -File | ForEach-Object { $_.FullName.Replace($HubRoot, "D:/BossMind") }
  }
}
Record "file_tree" $true "listed"

# 3. Environment variable check (names only)
Write-Host "`n--- environment probe ---"
$envNames = @(
  "DEEPSEEK_API_KEY",
  "ANTHROPIC_API_KEY",
  "KIMI_API_KEY",
  "MOONSHOT_API_KEY",
  "OPENROUTER_API_KEY",
  "NEON_DATABASE_URL",
  "DATABASE_URL"
)
$envReport = @{}
foreach ($n in $envNames) {
  $val = [Environment]::GetEnvironmentVariable($n, "Process")
  if (-not $val) { $val = [Environment]::GetEnvironmentVariable($n, "User") }
  if (-not $val) { $val = [Environment]::GetEnvironmentVariable($n, "Machine") }
  $envReport[$n] = if ($val -and $val.Trim().Length -gt 0) { "SET" } else { "MISSING" }
}
$envReport | Format-Table -AutoSize
$deepseekOk = $envReport["DEEPSEEK_API_KEY"] -eq "SET"
$reviewOk = (
  $envReport["ANTHROPIC_API_KEY"] -eq "SET" -or
  $envReport["KIMI_API_KEY"] -eq "SET" -or
  $envReport["MOONSHOT_API_KEY"] -eq "SET" -or
  $envReport["OPENROUTER_API_KEY"] -eq "SET"
)
Record "env_deepseek" $deepseekOk $(if ($deepseekOk) { "DEEPSEEK_API_KEY present" } else { "DEEPSEEK_API_KEY missing" })
Record "env_review" $reviewOk $(if ($reviewOk) { "review key present" } else { "ANTHROPIC/KIMI/OPENROUTER missing" })

Push-Location (Join-Path $HubRoot "bossmind-shared\automation")
$nodeEnv = node $Orchestrator env-check 2>&1 | Out-String
Pop-Location
Write-Host $nodeEnv
Record "orchestrator_env_check" ($LASTEXITCODE -eq 0) "exit=$LASTEXITCODE"

# 4. Build check (resumora)
Write-Host "`n--- build check (resumora) ---"
$ResumoraRoot = Join-Path $HubRoot "bossmind-resumora"
if (Test-Path $ResumoraRoot) {
  Push-Location $ResumoraRoot
  npm run build 2>&1 | Select-Object -Last 15
  $buildExit = $LASTEXITCODE
  Pop-Location
  Record "build_resumora" ($buildExit -eq 0) "exit=$buildExit"
} else {
  Record "build_resumora" $false "bossmind-resumora missing"
}

# 5. Lint (resumora)
Write-Host "`n--- lint check (resumora) ---"
if (Test-Path $ResumoraRoot) {
  Push-Location $ResumoraRoot
  npm run lint 2>&1 | Select-Object -Last 10
  $lintExit = $LASTEXITCODE
  Pop-Location
  Record "lint_resumora" ($lintExit -eq 0) "exit=$lintExit (pre-existing failures may fail)"
} else {
  Record "lint_resumora" $false "skipped"
}

# 6. AI sync dry run
Write-Host "`n--- AI sync dry run (resumora) ---"
Push-Location (Join-Path $HubRoot "bossmind-shared\automation")
node $Orchestrator dry-run resumora 2>&1 | Select-Object -Last 40
$dryExit = $LASTEXITCODE
Pop-Location
Record "ai_sync_dry_run" ($dryExit -eq 0) "exit=$dryExit"

# 7. Approval gate test
Write-Host "`n--- approval gate test ---"
Push-Location (Join-Path $HubRoot "bossmind-shared\automation")
node $Orchestrator approval-gate-test 2>&1
$gateExit = $LASTEXITCODE
Pop-Location
Record "approval_gate_test" ($gateExit -eq 0) "exit=$gateExit"

# 8. File lock conflict test
Write-Host "`n--- file lock conflict test ---"
Push-Location (Join-Path $HubRoot "bossmind-shared\automation")
node $Orchestrator lock-test resumora 2>&1
$lockExit = $LASTEXITCODE
Pop-Location
Record "file_lock_test" ($lockExit -eq 0) "exit=$lockExit"

# 9. Centralized log write/read
Write-Host "`n--- proof log test ---"
Push-Location (Join-Path $HubRoot "bossmind-shared\automation")
node $Orchestrator log-test hub 2>&1
$logExit = $LASTEXITCODE
Pop-Location
Record "proof_log_test" ($logExit -eq 0) "exit=$logExit"

# Summary
Write-Host "`n=== VERIFICATION SUMMARY ===" -ForegroundColor Cyan
$allPass = $true
foreach ($k in ($Results.Keys | Sort-Object)) {
  $r = $Results[$k]
  $icon = if ($r.pass) { "PASS" } else { "FAIL" }
  if (-not $r.pass) { $allPass = $false }
  Write-Host ("{0,-24} {1,-6} {2}" -f $k, $icon, $r.detail)
}

if (-not $deepseekOk) {
  Write-Host "`nBLOCKED: DEEPSEEK_API_KEY is required." -ForegroundColor Red
}
if (-not $reviewOk) {
  Write-Host "BLOCKED: Set ANTHROPIC_API_KEY, KIMI_API_KEY/MOONSHOT_API_KEY, or OPENROUTER_API_KEY for review." -ForegroundColor Red
}

if ($allPass -and $deepseekOk -and $reviewOk) {
  Write-Host "`nAll required checks passed. AI sync infrastructure is active (deploy still gated by PRAE)." -ForegroundColor Green
  exit 0
} else {
  Write-Host "`nNot fully synced - see FAIL/BLOCKED items above." -ForegroundColor Yellow
  exit 1
}
