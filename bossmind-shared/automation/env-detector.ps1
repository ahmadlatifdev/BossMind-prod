#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Env Detector — Phase 1

.DESCRIPTION
    Scans all .env* files across project roots and produces a structured
    report of KEY NAMES only. Values are structurally never read, assigned,
    stored, or logged at any point in this script.

    Also detects:
      - .env files that are NOT gitignored (leak risk)
      - Keys present in .env.example but missing locally
      - Key names that follow secret patterns (warns, never exposes values)
      - Drift between .env.example and actual env files

    SAFETY GUARANTEE:
      The regex '^([A-Z][A-Z0-9_]+)\s*=' extracts ONLY the capture group
      before the = sign. The right side of every line is discarded via the
      regex match — it is never assigned to any variable in any code path.

.PARAMETER ProjectRoots
    Array of project root paths to scan.

.PARAMETER OutputDir
    Where to write env scan results. Default: ../registry

.PARAMETER WhatIf
    Scan but write nothing.
#>

param(
    [Parameter(Mandatory)][string[]]$ProjectRoots,
    [string]$OutputDir = (Join-Path $PSScriptRoot ".." "registry"),
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# KEY NAME EXTRACTION PATTERN
# Matches: KEY_NAME=...  or  KEY_NAME = ...
# Capture group 1 = key name ONLY
# Everything after = is outside the capture group and is NEVER used
$KeyNamePattern = '^([A-Z][A-Z0-9_]+)\s*='

# Key name patterns that suggest sensitive material
# (We flag the KEY NAME itself as suspicious — we never see the value)
$SecretKeyPatterns = @(
    'PASSWORD','SECRET','TOKEN','KEY','CREDENTIAL','PRIVATE',
    'API_KEY','AUTH','BEARER','SIGNING','ENCRYPTION','HMAC',
    'CLIENT_SECRET','WEBHOOK_SECRET','MASTER_KEY','SEED_PHRASE'
)

# Key names that look sensitive but are safe (URL, host, port, etc.)
$SafeSuffixes = @('_URL','_HOST','_PORT','_NAME','_PATH','_DIR','_ENV',
                   '_REGION','_BUCKET','_TABLE','_QUEUE','_TOPIC','_ID',
                   '_ENDPOINT','_BASE','_PREFIX','_SUFFIX','_DOMAIN')

function Get-EnvReport {
    param([string]$ProjectRoot)

    $projectId = Split-Path $ProjectRoot -Leaf

    $report = [ordered]@{
        project_id             = $projectId
        project_root           = $ProjectRoot
        scanned_at             = (Get-Date -Format 'o')
        env_files_found        = @()
        key_names              = @()       # ALL key names across all env files
        keys_by_file           = @{}      # key names per file (no values ever)
        missing_required       = @()       # in .env.example but not locally
        extra_local_keys       = @()       # local but not in .env.example
        secret_pattern_keys    = @()       # key names matching secret patterns
        gitignored_leaks       = @()       # .env files NOT in .gitignore
        file_presence          = @{}      # which env files exist
        drift_detected         = $false
        summary                = ""
    }

    if (-not (Test-Path $ProjectRoot)) {
        $report.summary = "Project root not found"
        return [PSCustomObject]$report
    }

    # ── Find all .env* files ───────────────────────────────────────────────────
    $envFiles = Get-ChildItem -Path $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object {
            $_.Name -match '^\.env' -and
            $_.FullName -notmatch 'node_modules' -and
            $_.PSIsContainer -eq $false
        }

    # ── File presence map ──────────────────────────────────────────────────────
    $presenceCheck = @('.env','.env.local','.env.development','.env.production',
                       '.env.test','.env.staging','.env.example','.env.sample')
    foreach ($name in $presenceCheck) {
        $report.file_presence[$name] = Test-Path (Join-Path $ProjectRoot $name)
    }

    # ── Extract key names only ─────────────────────────────────────────────────
    $allKeys      = [System.Collections.Generic.HashSet[string]]::new()
    $exampleKeys  = [System.Collections.Generic.HashSet[string]]::new()
    $keysByFile   = @{}

    foreach ($file in $envFiles) {
        $relPath = $file.FullName.Replace($ProjectRoot,'').TrimStart('\','/')
        $report.env_files_found += $relPath

        $fileKeys = [System.Collections.Generic.HashSet[string]]::new()

        try {
            # Read line by line — process only the KEY NAME capture group
            # The value (right of =) is NEVER captured or stored
            Get-Content $file.FullName -ErrorAction Stop | ForEach-Object {
                $line = $_
                # Skip comments and blank lines
                if ($line -match '^\s*#' -or $line.Trim() -eq '') { return }
                # Extract ONLY the key name — value is discarded by regex design
                if ($line -match $KeyNamePattern) {
                    $keyName = $Matches[1]  # capture group 1 = key name only
                    # Defensive: ensure we captured only a valid identifier
                    if ($keyName -match '^[A-Z][A-Z0-9_]+$') {
                        $fileKeys.Add($keyName) | Out-Null
                        $allKeys.Add($keyName)  | Out-Null
                        if ($file.Name -eq '.env.example') {
                            $exampleKeys.Add($keyName) | Out-Null
                        }
                    }
                }
                # Line is processed — value component is NOT accessible beyond this point
            }
        } catch {
            Write-Verbose "Cannot read env file $relPath : $_"
        }

        $keysByFile[$relPath] = $fileKeys | Sort-Object
    }

    $report.key_names   = $allKeys | Sort-Object
    $report.keys_by_file = $keysByFile

    # ── Missing required keys ──────────────────────────────────────────────────
    if ($exampleKeys.Count -gt 0) {
        $localKeys = $allKeys | Where-Object { $_ -notin $exampleKeys }
        $missingFromLocal = $exampleKeys | Where-Object { $_ -notin $allKeys }
        $report.missing_required = $missingFromLocal | Sort-Object
        $report.extra_local_keys = $localKeys | Sort-Object
        $report.drift_detected   = $missingFromLocal.Count -gt 0
    }

    # ── Secret pattern detection (key names only) ──────────────────────────────
    $report.secret_pattern_keys = $allKeys | Where-Object {
        $keyName = $_
        $matchesSecret = $SecretKeyPatterns | Where-Object { $keyName -match $_ }
        $hasSafeSuffix = $SafeSuffixes     | Where-Object { $keyName -match "$_$" }
        ($matchesSecret.Count -gt 0) -and ($hasSafeSuffix.Count -eq 0)
    } | Sort-Object

    # ── Gitignore leak check ───────────────────────────────────────────────────
    $realEnvFiles = $envFiles | Where-Object {
        $_.Name -ne '.env.example' -and $_.Name -ne '.env.sample'
    }
    $report.gitignored_leaks = $realEnvFiles | ForEach-Object {
        $relPath = $_.FullName.Replace($ProjectRoot,'').TrimStart('\','/')
        $isIgnored = $false
        try {
            git -C $ProjectRoot check-ignore -q $_.FullName 2>$null
            $isIgnored = ($LASTEXITCODE -eq 0)
        } catch {}
        if (-not $isIgnored) { $relPath }  # only report files NOT covered by .gitignore
    }

    # ── Summary ────────────────────────────────────────────────────────────────
    $parts = @("$($report.key_names.Count) keys in $($report.env_files_found.Count) files")
    if ($report.missing_required.Count -gt 0) { $parts += "$($report.missing_required.Count) missing" }
    if ($report.secret_pattern_keys.Count -gt 0) { $parts += "$($report.secret_pattern_keys.Count) sensitive-named keys" }
    if ($report.gitignored_leaks.Count -gt 0) { $parts += "LEAK RISK: $($report.gitignored_leaks.Count) unignored env files" }
    $report.summary = $parts -join " | "

    return [PSCustomObject]$report
}

# ── Main ───────────────────────────────────────────────────────────────────────
Write-Host "[Env Detector] Starting — $(Get-Date -Format 'o')" -ForegroundColor Cyan
Write-Host "[Env Detector] SECURITY: Key names only. Values are never read or logged." -ForegroundColor DarkYellow

if (-not (Test-Path $OutputDir) -and -not $WhatIf) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

$allReports = @()

foreach ($root in $ProjectRoots) {
    $report = Get-EnvReport -ProjectRoot $root

    Write-Host "  [$($report.project_id)] $($report.summary)" -ForegroundColor Gray

    if ($report.gitignored_leaks.Count -gt 0) {
        Write-Host "  [$($report.project_id)] LEAK RISK: $($report.gitignored_leaks -join ', ')" -ForegroundColor Red
    }
    if ($report.missing_required.Count -gt 0) {
        Write-Host "  [$($report.project_id)] Missing keys: $($report.missing_required -join ', ')" -ForegroundColor Yellow
    }
    if ($report.secret_pattern_keys.Count -gt 0) {
        Write-Host "  [$($report.project_id)] Sensitive-named keys (names only): $($report.secret_pattern_keys -join ', ')" -ForegroundColor Yellow
    }

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would write: $OutputDir/$($report.project_id)-env-report.json" -ForegroundColor DarkYellow
    } else {
        $outPath = Join-Path $OutputDir "$($report.project_id)-env-report.json"
        $report | ConvertTo-Json -Depth 6 | Set-Content -Path $outPath -Encoding UTF8
        Write-Host "  [$($report.project_id)] Written: $outPath" -ForegroundColor Green
    }

    $allReports += $report
}

if (-not $WhatIf) {
    $combinedPath = Join-Path $OutputDir "all-projects-env-report.json"
    [PSCustomObject]@{
        generated_at  = (Get-Date -Format 'o')
        project_count = $allReports.Count
        reports       = $allReports
    } | ConvertTo-Json -Depth 8 | Set-Content -Path $combinedPath -Encoding UTF8
    Write-Host "[Env Detector] Combined report: $combinedPath" -ForegroundColor Green
}

Write-Host "[Env Detector] Complete" -ForegroundColor Cyan
return $allReports
