#!/usr/bin/env pwsh
<#
    detectors.ps1 — BossMind Live State Watcher v1
    All eight detection subsystems. Dot-source this from watcher-daemon.ps1.
    Every function returns a plain PSCustomObject safe for JSON serialisation.
    SECURITY: env key names are captured; values are NEVER read or logged.
#>

Set-StrictMode -Version Latest

# ─────────────────────────────────────────────────────────────────────────────
# 1. FILESYSTEM DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Get-FilesystemState {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        root          = $ProjectRoot
        exists        = $false
        total_files   = 0
        total_dirs    = 0
        total_size_kb = 0
        key_files     = @()
        recently_changed = @()
        gitignored_leaks = @()
    }

    if (-not (Test-Path $ProjectRoot)) { return [PSCustomObject]$result }
    $result.exists = $true

    $allItems = Get-ChildItem -Path $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch '[\\/](\.git|node_modules|\.next|dist|build|__pycache__)[\\/]' }

    $result.total_files   = ($allItems | Where-Object { -not $_.PSIsContainer }).Count
    $result.total_dirs    = ($allItems | Where-Object { $_.PSIsContainer }).Count
    $result.total_size_kb = [math]::Round(
        ($allItems | Where-Object { -not $_.PSIsContainer } | Measure-Object -Property Length -Sum).Sum / 1KB, 1
    )

    # Key file presence check
    $keyFiles = @(
        'package.json', 'package-lock.json', 'yarn.lock', 'pnpm-lock.yaml',
        'requirements.txt', 'Pipfile', 'pyproject.toml', 'go.mod',
        'Dockerfile', 'docker-compose.yml', '.dockerignore',
        'railway.toml', 'render.yaml', '.github',
        'tsconfig.json', 'vite.config.ts', 'vite.config.js',
        'next.config.js', 'next.config.ts',
        '.env.example', '.env.local', '.cursorrules', '.cursorignore',
        'README.md', 'CHANGELOG.md'
    )
    $result.key_files = $keyFiles | Where-Object {
        Test-Path (Join-Path $ProjectRoot $_)
    }

    # Files changed in last 60 minutes
    $cutoff = (Get-Date).AddMinutes(-60)
    $result.recently_changed = $allItems |
        Where-Object { -not $_.PSIsContainer -and $_.LastWriteTime -gt $cutoff } |
        Select-Object -First 20 |
        ForEach-Object { $_.FullName.Replace($ProjectRoot, '').TrimStart('\','/') }

    # Leak check: real .env files that should never be committed
    $envLeaks = Get-ChildItem -Path $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\.env(\.[^.]+)?$' -and $_.Name -ne '.env.example' }
    $result.gitignored_leaks = $envLeaks | ForEach-Object {
        $relPath = $_.FullName.Replace($ProjectRoot, '').TrimStart('\','/')
        # Check if covered by .gitignore
        $ignored = $false
        try {
            $ignored = (git -C $ProjectRoot check-ignore -q $_.FullName 2>$null; $LASTEXITCODE -eq 0)
        } catch {}
        if (-not $ignored) { $relPath }  # only report if NOT gitignored (= dangerous)
    }

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 2. GIT STATE DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Get-GitState {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        is_repo          = $false
        branch           = $null
        commit_hash      = $null
        commit_message   = $null
        commit_author    = $null
        commit_timestamp = $null
        dirty            = $false
        staged_count     = 0
        unstaged_count   = 0
        untracked_count  = 0
        ahead            = 0
        behind           = 0
        stash_count      = 0
        last_tag         = $null
        remotes          = @()
    }

    $gitDir = Join-Path $ProjectRoot ".git"
    if (-not (Test-Path $gitDir)) { return [PSCustomObject]$result }
    $result.is_repo = $true

    try {
        $result.branch          = (git -C $ProjectRoot rev-parse --abbrev-ref HEAD 2>$null)?.Trim()
        $result.commit_hash     = (git -C $ProjectRoot rev-parse --short HEAD 2>$null)?.Trim()
        $result.commit_message  = (git -C $ProjectRoot log -1 --format="%s" 2>$null)?.Trim()
        $result.commit_author   = (git -C $ProjectRoot log -1 --format="%an" 2>$null)?.Trim()
        $result.commit_timestamp= (git -C $ProjectRoot log -1 --format="%aI" 2>$null)?.Trim()
        $result.last_tag        = (git -C $ProjectRoot describe --tags --abbrev=0 2>$null)?.Trim()

        # Status counts
        $status = git -C $ProjectRoot status --porcelain 2>$null
        if ($status) {
            $lines = $status -split "`n" | Where-Object { $_ }
            $result.staged_count   = ($lines | Where-Object { $_ -match '^[MADRC]' }).Count
            $result.unstaged_count = ($lines | Where-Object { $_ -match '^.[MD]' }).Count
            $result.untracked_count= ($lines | Where-Object { $_ -match '^\?\?' }).Count
            $result.dirty          = $lines.Count -gt 0
        }

        # Ahead / behind remote
        $tracking = git -C $ProjectRoot rev-parse --abbrev-ref '@{upstream}' 2>$null
        if ($tracking) {
            $counts = git -C $ProjectRoot rev-list --left-right --count "HEAD...$tracking" 2>$null
            if ($counts -match '(\d+)\s+(\d+)') {
                $result.ahead  = [int]$Matches[1]
                $result.behind = [int]$Matches[2]
            }
        }

        $result.stash_count = [int]((git -C $ProjectRoot stash list 2>$null | Measure-Object -Line).Lines)
        $result.remotes     = (git -C $ProjectRoot remote 2>$null) -split "`n" | Where-Object { $_ }

    } catch { Write-Verbose "Git detection error: $_" }

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 3. PACKAGE.JSON COMMAND DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Get-PackageCommands {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        found           = $false
        name            = $null
        version         = $null
        scripts         = @{}
        has_dev_script  = $false
        has_build_script= $false
        has_test_script = $false
        has_lint_script = $false
        has_start_script= $false
        package_manager = "unknown"
        runtime_deps_count  = 0
        dev_deps_count      = 0
    }

    $pkgPath = Join-Path $ProjectRoot "package.json"
    if (-not (Test-Path $pkgPath)) { return [PSCustomObject]$result }

    try {
        $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $result.found   = $true
        $result.name    = $pkg.name
        $result.version = $pkg.version

        if ($pkg.scripts) {
            $result.scripts          = $pkg.scripts | ConvertTo-Json | ConvertFrom-Json  # clone
            $result.has_dev_script   = [bool]$pkg.scripts.dev
            $result.has_build_script = [bool]$pkg.scripts.build
            $result.has_test_script  = [bool]($pkg.scripts.test -or $pkg.scripts.tests)
            $result.has_lint_script  = [bool]($pkg.scripts.lint -or $pkg.scripts.check)
            $result.has_start_script = [bool]$pkg.scripts.start
        }

        $result.runtime_deps_count = if ($pkg.dependencies)    { ($pkg.dependencies | Get-Member -MemberType NoteProperty).Count } else { 0 }
        $result.dev_deps_count     = if ($pkg.devDependencies) { ($pkg.devDependencies | Get-Member -MemberType NoteProperty).Count } else { 0 }

        # Detect package manager
        if (Test-Path (Join-Path $ProjectRoot "pnpm-lock.yaml"))    { $result.package_manager = "pnpm" }
        elseif (Test-Path (Join-Path $ProjectRoot "yarn.lock"))     { $result.package_manager = "yarn" }
        elseif (Test-Path (Join-Path $ProjectRoot "package-lock.json")) { $result.package_manager = "npm" }
        elseif (Test-Path (Join-Path $ProjectRoot "bun.lockb"))     { $result.package_manager = "bun" }

    } catch { Write-Verbose "package.json parse error: $_" }

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 4. ENV KEY-NAME DETECTION (VALUES NEVER LOGGED)
# ─────────────────────────────────────────────────────────────────────────────
function Get-EnvKeyNames {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        env_files_found  = @()
        key_names        = @()       # KEY NAMES ONLY — values are never read
        missing_required = @()
        secret_pattern_warning = $false
    }

    # Pattern: lines that look like KEY=... — extract KEY name only
    $envPattern = '^([A-Z][A-Z0-9_]+)\s*='

    $envFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.Name -match '^\.env' } |
        Where-Object { $_.FullName -notmatch 'node_modules' }

    $allKeys = [System.Collections.Generic.HashSet[string]]::new()

    foreach ($file in $envFiles) {
        $relPath = $file.FullName.Replace($ProjectRoot, '').TrimStart('\','/')
        $result.env_files_found += $relPath

        try {
            $lines = Get-Content $file.FullName -ErrorAction Stop
            foreach ($line in $lines) {
                if ($line -match $envPattern) {
                    $allKeys.Add($Matches[1]) | Out-Null
                }
            }
        } catch { Write-Verbose "Could not read env file: $($file.FullName)" }
    }

    $result.key_names = $allKeys | Sort-Object

    # Check .env.example for keys that should exist
    $examplePath = Join-Path $ProjectRoot ".env.example"
    if (Test-Path $examplePath) {
        $exampleKeys = [System.Collections.Generic.HashSet[string]]::new()
        Get-Content $examplePath | ForEach-Object {
            if ($_ -match $envPattern) { $exampleKeys.Add($Matches[1]) | Out-Null }
        }
        $result.missing_required = $exampleKeys | Where-Object { $_ -notin $allKeys } | Sort-Object
    }

    # Warn if any key name itself looks like it might be a secret (paranoia check)
    $suspiciousKeyNames = $result.key_names | Where-Object {
        $_ -match 'PASSWORD|SECRET|TOKEN|KEY|CREDENTIAL|PRIVATE' -and
        $_ -notmatch '_URL$|_HOST$|_PORT$|_NAME$|_PATH$|_DIR$|_ENV$'
    }
    $result.secret_pattern_warning = $suspiciousKeyNames.Count -gt 0

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 5. BUILD / TEST / LINT ERROR CAPTURE
# ─────────────────────────────────────────────────────────────────────────────
function Get-BuildErrorState {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        has_errors     = $false
        errors         = @()
        typescript_ok  = $null
        lint_ok        = $null
        test_exit_code = $null
        log_files_found = @()
    }

    # Scan for common error log files left by build tools
    $logPatterns = @('*.log', 'npm-debug.log', 'yarn-error.log', 'build-error.log', '.next/trace')
    foreach ($pattern in $logPatterns) {
        $found = Get-ChildItem -Path $ProjectRoot -Filter $pattern -Recurse -ErrorAction SilentlyContinue |
            Where-Object { $_.FullName -notmatch 'node_modules' } |
            Select-Object -First 5
        $result.log_files_found += $found | ForEach-Object {
            $_.FullName.Replace($ProjectRoot,'').TrimStart('\','/')
        }
    }

    # TypeScript check (non-destructive: just parse tsconfig presence + last compile output)
    $tsconfigPath = Join-Path $ProjectRoot "tsconfig.json"
    if (Test-Path $tsconfigPath) {
        # Look for tsbuildinfo or ts-error files from last compile
        $tsErrorFile = Join-Path $ProjectRoot ".ts-errors.log"
        if (Test-Path $tsErrorFile) {
            $tsErrors = Get-Content $tsErrorFile -ErrorAction SilentlyContinue
            if ($tsErrors) {
                $result.typescript_ok = $false
                $result.has_errors    = $true
                $result.errors       += $tsErrors | Select-Object -First 10
            } else {
                $result.typescript_ok = $true
            }
        } else {
            $result.typescript_ok = $null  # no record yet — unknown
        }
    }

    # Lint check — look for eslint output file if project wrote one
    $lintOutputFile = Join-Path $ProjectRoot ".lint-output.log"
    if (Test-Path $lintOutputFile) {
        $lintContent = Get-Content $lintOutputFile -Raw -ErrorAction SilentlyContinue
        if ($lintContent -match '\d+ error') {
            $result.lint_ok    = $false
            $result.has_errors = $true
            $result.errors    += "lint: $($lintContent.Substring(0, [Math]::Min(200, $lintContent.Length)))"
        } else {
            $result.lint_ok = $true
        }
    }

    # Test result file — look for jest/vitest JSON output
    $testResultFiles = @(
        'test-results.json', 'junit.xml', '.vitest-result.json',
        'coverage/coverage-summary.json'
    )
    foreach ($tf in $testResultFiles) {
        $tfPath = Join-Path $ProjectRoot $tf
        if (Test-Path $tfPath) {
            try {
                $content = Get-Content $tfPath -Raw -ErrorAction Stop
                if ($content -match '"numFailedTests"\s*:\s*([1-9]\d*)' -or
                    $content -match '"failures"\s*:\s*([1-9]\d*)') {
                    $result.test_exit_code = 1
                    $result.has_errors     = $true
                    $result.errors        += "test_failures_detected in $tf"
                } else {
                    $result.test_exit_code = 0
                }
            } catch {}
            break
        }
    }

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 6. DEPLOYMENT CONFIG DETECTION
# ─────────────────────────────────────────────────────────────────────────────
function Get-DeploymentConfig {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        railway_toml      = $false
        railway_toml_data = $null
        render_yaml       = $false
        render_yaml_data  = $null
        github_workflows  = @()
        dockerfile        = $false
        docker_compose    = $false
        vercel_json       = $false
        netlify_toml      = $false
        procfile          = $false
    }

    # Railway
    $railwayPath = Join-Path $ProjectRoot "railway.toml"
    if (Test-Path $railwayPath) {
        $result.railway_toml = $true
        $result.railway_toml_data = (Get-Content $railwayPath -ErrorAction SilentlyContinue) -join "`n" |
            Select-Object -First 1  # store raw for reference; truncated
        $result.railway_toml_data = (Get-Content $railwayPath -ErrorAction SilentlyContinue |
            Select-Object -First 20) -join "`n"
    }

    # Render
    $renderPath = Join-Path $ProjectRoot "render.yaml"
    if (Test-Path $renderPath) {
        $result.render_yaml = $true
        $result.render_yaml_data = (Get-Content $renderPath -ErrorAction SilentlyContinue |
            Select-Object -First 20) -join "`n"
    }

    # GitHub Actions workflows
    $workflowDir = Join-Path $ProjectRoot ".github" "workflows"
    if (Test-Path $workflowDir) {
        $result.github_workflows = Get-ChildItem $workflowDir -Filter "*.yml" -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name }
    }

    $result.dockerfile     = Test-Path (Join-Path $ProjectRoot "Dockerfile")
    $result.docker_compose = (Test-Path (Join-Path $ProjectRoot "docker-compose.yml")) -or
                             (Test-Path (Join-Path $ProjectRoot "docker-compose.yaml"))
    $result.vercel_json    = Test-Path (Join-Path $ProjectRoot "vercel.json")
    $result.netlify_toml   = Test-Path (Join-Path $ProjectRoot "netlify.toml")
    $result.procfile       = Test-Path (Join-Path $ProjectRoot "Procfile")

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 7. AWS S3 SYNC VALIDATION
# ─────────────────────────────────────────────────────────────────────────────
function Get-S3SyncState {
    param([string]$ProjectRoot)

    $result = [ordered]@{
        configured       = $false
        bucket           = $null
        profile          = $null
        reachable        = $null
        drift_detected   = $false
        drift_summary    = $null
        last_sync_marker = $null
        s3_config_file   = $null
    }

    # Look for BossMind S3 config file
    $s3ConfigPath = Join-Path $ProjectRoot ".bossmind-s3.json"
    if (-not (Test-Path $s3ConfigPath)) {
        # Also check orchestrator-level config
        $s3ConfigPath = Join-Path $PSScriptRoot ".." "config" "s3.json"
    }
    if (-not (Test-Path $s3ConfigPath)) { return [PSCustomObject]$result }

    try {
        $s3Config = Get-Content $s3ConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
        $result.configured    = $true
        $result.bucket        = $s3Config.bucket
        $result.profile       = $s3Config.profile ?? "default"
        $result.s3_config_file = $s3ConfigPath
    } catch {
        Write-Verbose "S3 config parse error: $_"
        return [PSCustomObject]$result
    }

    # Check AWS CLI availability
    $awsCli = Get-Command aws -ErrorAction SilentlyContinue
    if (-not $awsCli) {
        $result.reachable = $null  # can't check without CLI
        return [PSCustomObject]$result
    }

    # Check sync marker file (written by your sync script)
    $syncMarkerPath = Join-Path $ProjectRoot ".bossmind-s3-sync.json"
    if (Test-Path $syncMarkerPath) {
        try {
            $marker = Get-Content $syncMarkerPath -Raw | ConvertFrom-Json
            $result.last_sync_marker = $marker
        } catch {}
    }

    # Probe bucket reachability (non-destructive ls)
    try {
        $profileArgs = if ($result.profile -ne "default") { @("--profile", $result.profile) } else { @() }
        $lsOutput = aws s3 ls "s3://$($result.bucket)/" @profileArgs --max-items 1 2>&1
        $result.reachable = ($LASTEXITCODE -eq 0)
    } catch {
        $result.reachable = $false
    }

    # Drift check: compare local build dir vs S3 (if sync source configured)
    if ($result.reachable -and $s3Config.local_path) {
        $localPath = Join-Path $ProjectRoot $s3Config.local_path
        if (Test-Path $localPath) {
            try {
                $profileArgs = if ($result.profile -ne "default") { @("--profile", $result.profile) } else { @() }
                $dryRun = aws s3 sync $localPath "s3://$($result.bucket)/$($s3Config.prefix ?? '')" `
                    @profileArgs --dryrun 2>&1
                $driftLines = $dryRun | Where-Object { $_ -match '^\(dryrun\)' }
                $result.drift_detected = $driftLines.Count -gt 0
                $result.drift_summary  = if ($driftLines.Count -gt 0) {
                    "$($driftLines.Count) files would be synced"
                } else { "in sync" }
            } catch {
                $result.drift_summary = "drift check failed: $_"
            }
        }
    }

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# 8. HEALTH ENDPOINT PROBES
# ─────────────────────────────────────────────────────────────────────────────
function Get-HealthState {
    param([string]$ProjectRoot, [string]$ProjectId)

    $result = [ordered]@{
        degraded   = $false
        failures   = @()
        endpoints  = @()
    }

    # Read endpoint config from project or orchestrator
    $healthConfigPath = Join-Path $ProjectRoot ".bossmind-health.json"
    if (-not (Test-Path $healthConfigPath)) {
        $healthConfigPath = Join-Path $PSScriptRoot ".." "config" "health-endpoints.json"
    }

    $endpoints = @()
    if (Test-Path $healthConfigPath) {
        try {
            $cfg = Get-Content $healthConfigPath -Raw | ConvertFrom-Json -ErrorAction Stop
            # Support both flat and per-project config
            if ($cfg.$ProjectId) { $endpoints = $cfg.$ProjectId }
            elseif ($cfg.endpoints) { $endpoints = $cfg.endpoints }
        } catch { Write-Verbose "Health config parse error: $_" }
    }

    foreach ($ep in $endpoints) {
        $epResult = [ordered]@{
            name           = $ep.name ?? $ep.url
            url            = $ep.url
            expected_status = $ep.expected_status ?? 200
            actual_status  = $null
            response_ms    = $null
            ok             = $false
            error          = $null
        }

        $sw = [System.Diagnostics.Stopwatch]::StartNew()
        try {
            $resp = Invoke-WebRequest -Uri $ep.url -TimeoutSec ($ep.timeout_sec ?? 10) `
                -UseBasicParsing -ErrorAction Stop
            $sw.Stop()
            $epResult.actual_status = $resp.StatusCode
            $epResult.response_ms   = $sw.ElapsedMilliseconds
            $epResult.ok            = ($resp.StatusCode -eq $epResult.expected_status)
        } catch {
            $sw.Stop()
            $epResult.response_ms = $sw.ElapsedMilliseconds
            $epResult.error       = $_.Exception.Message
            $epResult.ok          = $false
        }

        if (-not $epResult.ok) {
            $result.degraded = $true
            $result.failures += "health_fail:$($epResult.name):$($epResult.error ?? $epResult.actual_status)"
        }

        $result.endpoints += [PSCustomObject]$epResult
    }

    return [PSCustomObject]$result
}

# ─────────────────────────────────────────────────────────────────────────────
# NEON SYNC (OPTIONAL)
# ─────────────────────────────────────────────────────────────────────────────
function Sync-ToNeon {
    param([string]$NeonUrl, [PSCustomObject]$Snapshot)

    $psql = Get-Command psql -ErrorAction SilentlyContinue
    if (-not $psql) {
        Write-Verbose "psql not found — skipping Neon sync"
        return
    }

    $json = $Snapshot | ConvertTo-Json -Depth 10 -Compress
    # Escape single quotes for SQL
    $json = $json -replace "'", "''"

    $sql = @"
INSERT INTO shared_memory (project_id, key, value, updated_at)
VALUES ('$($Snapshot.project_id)', 'watcher_state', '$json'::jsonb, now())
ON CONFLICT (project_id, key)
DO UPDATE SET value = EXCLUDED.value, updated_at = now();
"@

    try {
        $sql | psql $NeonUrl -c "-" 2>&1 | Out-Null
    } catch {
        Write-Verbose "Neon sync failed: $_"
    }
}
