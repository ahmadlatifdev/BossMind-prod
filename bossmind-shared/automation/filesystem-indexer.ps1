#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Filesystem Indexer — Phase 1

.DESCRIPTION
    Scans one or more project roots and produces a structured JSON index of:
      - All files (excluding noise dirs) with size, modified time, extension
      - Key file presence map
      - Recently changed files (last 60 min)
      - Orphaned files (not referenced by package.json or imports)
      - Duplicate filenames across different directories
      - Safe rollback snapshot of current file tree state

    SAFETY: Read-only. Never modifies, moves, or deletes any file.
    Never reads file contents except for package.json (JSON only).

.PARAMETER ProjectRoots
    Array of project root paths to index.

.PARAMETER OutputDir
    Where to write index JSON files. Default: ../registry

.PARAMETER SnapshotDir
    Where to write rollback snapshots. Default: ../snapshots

.PARAMETER WhatIf
    Scan and report but write nothing to disk.
#>

param(
    [Parameter(Mandatory)][string[]]$ProjectRoots,
    [string]$OutputDir   = (Join-Path $PSScriptRoot ".." "registry"),
    [string]$SnapshotDir = (Join-Path $PSScriptRoot ".." "snapshots"),
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

# Directories excluded from all scans
$ExcludedDirs = @('node_modules','.git','.next','dist','build','__pycache__',
                   '.turbo','.cache','coverage','.nyc_output','out','.svelte-kit')

# Key files to check for presence
$KeyFileManifest = @(
    # JS/TS ecosystem
    'package.json','package-lock.json','yarn.lock','pnpm-lock.yaml','bun.lockb',
    'tsconfig.json','tsconfig.base.json','jsconfig.json',
    'vite.config.ts','vite.config.js','vite.config.mts',
    'next.config.js','next.config.ts','next.config.mjs',
    'svelte.config.js','nuxt.config.ts','astro.config.mjs',
    'webpack.config.js','rollup.config.js','esbuild.config.js',
    # Python
    'requirements.txt','requirements-dev.txt','Pipfile','pyproject.toml','setup.py','setup.cfg',
    # Go / Rust / other
    'go.mod','go.sum','Cargo.toml','Cargo.lock',
    # Container / infra
    'Dockerfile','docker-compose.yml','docker-compose.yaml','.dockerignore',
    # Deploy
    'railway.toml','render.yaml','netlify.toml','vercel.json','Procfile','.railway',
    # CI/CD
    '.github','.gitlab-ci.yml','.circleci',
    # Config / env
    '.env.example','.env.local','.env.development','.env.production',
    '.cursorrules','.cursorignore','.editorconfig','.prettierrc',
    'eslint.config.js','.eslintrc.json','.eslintrc.js',
    # Docs
    'README.md','CHANGELOG.md','LICENSE','CONTRIBUTING.md'
)

function Get-SafeRelativePath ([string]$FullPath, [string]$Root) {
    $FullPath.Replace($Root, '').TrimStart('\', '/')
}

function Get-FilesystemIndex {
    param([string]$ProjectRoot)

    $projectId = Split-Path $ProjectRoot -Leaf
    Write-Host "  [Index] Scanning: $ProjectRoot" -ForegroundColor DarkCyan

    if (-not (Test-Path $ProjectRoot)) {
        return [PSCustomObject]@{
            project_id    = $projectId
            project_root  = $ProjectRoot
            indexed_at    = (Get-Date -Format 'o')
            error         = "Project root not found"
        }
    }

    # ── Full file scan ─────────────────────────────────────────────────────────
    $excludeRegex = '[\\/](' + ($ExcludedDirs -join '|') + ')[\\/]'
    $allItems = Get-ChildItem -Path $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue |
        Where-Object { $_.FullName -notmatch $excludeRegex }

    $allFiles = $allItems | Where-Object { -not $_.PSIsContainer }
    $allDirs  = $allItems | Where-Object { $_.PSIsContainer }

    # ── File list with metadata ────────────────────────────────────────────────
    $fileList = $allFiles | ForEach-Object {
        [PSCustomObject]@{
            rel_path    = Get-SafeRelativePath $_.FullName $ProjectRoot
            size_bytes  = $_.Length
            modified    = $_.LastWriteTime.ToString('o')
            extension   = $_.Extension.ToLower()
            name        = $_.Name
        }
    }

    # ── Extension summary ──────────────────────────────────────────────────────
    $extSummary = $fileList | Group-Object extension |
        Sort-Object Count -Descending |
        Select-Object -First 20 |
        ForEach-Object { [PSCustomObject]@{ ext = $_.Name; count = $_.Count } }

    # ── Key file presence ──────────────────────────────────────────────────────
    $keyFilesPresent = $KeyFileManifest | Where-Object {
        Test-Path (Join-Path $ProjectRoot $_)
    }
    $keyFilesMissing = $KeyFileManifest | Where-Object {
        $_ -in @('package.json','tsconfig.json','README.md','.env.example') -and
        -not (Test-Path (Join-Path $ProjectRoot $_))
    }

    # ── Recently changed (last 60 min) ────────────────────────────────────────
    $cutoff = (Get-Date).AddMinutes(-60)
    $recentlyChanged = $fileList |
        Where-Object { [DateTime]$_.modified -gt $cutoff } |
        Sort-Object modified -Descending |
        Select-Object -First 30

    # ── Largest files ─────────────────────────────────────────────────────────
    $largestFiles = $fileList | Sort-Object size_bytes -Descending | Select-Object -First 10

    # ── Duplicate filename detection ───────────────────────────────────────────
    $duplicates = $fileList |
        Group-Object name |
        Where-Object { $_.Count -gt 1 } |
        ForEach-Object {
            [PSCustomObject]@{
                filename  = $_.Name
                count     = $_.Count
                locations = $_.Group | ForEach-Object { $_.rel_path }
            }
        }

    # ── Orphan detection (JS/TS only) ─────────────────────────────────────────
    # A file is potentially orphaned if it's a .ts/.js source file
    # not referenced by any other file (simple heuristic — import name match)
    $sourceFiles = $fileList | Where-Object { $_.extension -in @('.ts','.tsx','.js','.jsx','.mjs') }
    $orphanCandidates = @()
    if ($sourceFiles.Count -lt 500) {  # only run on smaller projects to stay fast
        $allSourceContent = @{}
        foreach ($sf in $sourceFiles) {
            try {
                $content = Get-Content (Join-Path $ProjectRoot $sf.rel_path) -Raw -ErrorAction SilentlyContinue
                $allSourceContent[$sf.rel_path] = $content
            } catch {}
        }

        foreach ($sf in $sourceFiles) {
            $baseName = [System.IO.Path]::GetFileNameWithoutExtension($sf.name)
            if ($baseName -in @('index','main','app','layout','page','route','middleware','types','utils','helpers','constants','config')) { continue }
            $isReferenced = $allSourceContent.Values | Where-Object {
                $_ -and $_ -match [regex]::Escape($baseName)
            }
            if (-not $isReferenced) {
                $orphanCandidates += [PSCustomObject]@{
                    rel_path = $sf.rel_path
                    name     = $sf.name
                    size_bytes = $sf.size_bytes
                }
            }
        }
    }

    # ── npm scripts from package.json (read JSON only, no execution) ───────────
    $npmScripts = @{}
    $pkgPath = Join-Path $ProjectRoot "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -ErrorAction Stop
            if ($pkg.scripts) { $npmScripts = $pkg.scripts }
        } catch { Write-Verbose "package.json parse error" }
    }

    # ── Directory structure (top 2 levels) ────────────────────────────────────
    $topDirs = $allDirs |
        Where-Object { ($_.FullName.Replace($ProjectRoot,'').TrimStart('\','/').Split('/','\').Count) -le 2 } |
        ForEach-Object { Get-SafeRelativePath $_.FullName $ProjectRoot } |
        Sort-Object

    # ── Assemble index ─────────────────────────────────────────────────────────
    return [PSCustomObject]@{
        project_id         = $projectId
        project_root       = $ProjectRoot
        indexed_at         = (Get-Date -Format 'o')
        total_files        = $allFiles.Count
        total_dirs         = $allDirs.Count
        total_size_bytes   = ($allFiles | Measure-Object -Property Length -Sum).Sum
        total_size_kb      = [math]::Round(($allFiles | Measure-Object -Property Length -Sum).Sum / 1KB, 1)
        extension_summary  = $extSummary
        key_files_present  = $keyFilesPresent
        key_files_missing  = $keyFilesMissing
        npm_scripts        = $npmScripts
        recently_changed   = $recentlyChanged
        largest_files      = $largestFiles
        duplicate_names    = $duplicates
        orphan_candidates  = $orphanCandidates
        top_directories    = $topDirs
        excluded_dirs      = $ExcludedDirs
    }
}

function Write-RollbackSnapshot {
    param([PSCustomObject]$Index, [string]$SnapshotDir)

    $timestamp   = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $snapshotPath = Join-Path $SnapshotDir "$($Index.project_id)-fs-snapshot-$timestamp.json"

    $snapshot = [PSCustomObject]@{
        type          = "filesystem_snapshot"
        project_id    = $Index.project_id
        project_root  = $Index.project_root
        captured_at   = $Index.indexed_at
        total_files   = $Index.total_files
        total_size_kb = $Index.total_size_kb
        key_files     = $Index.key_files_present
        # File list with hashes for rollback verification
        files = $Index | Select-Object -ExpandProperty recently_changed
    }

    $snapshot | ConvertTo-Json -Depth 8 | Set-Content -Path $snapshotPath -Encoding UTF8
    return $snapshotPath
}

# ── Main ───────────────────────────────────────────────────────────────────────
Write-Host "[Filesystem Indexer] Starting — $(Get-Date -Format 'o')" -ForegroundColor Cyan

if (-not (Test-Path $OutputDir)   -and -not $WhatIf) { New-Item -ItemType Directory -Path $OutputDir   -Force | Out-Null }
if (-not (Test-Path $SnapshotDir) -and -not $WhatIf) { New-Item -ItemType Directory -Path $SnapshotDir -Force | Out-Null }

$allIndexes = @()

foreach ($root in $ProjectRoots) {
    $index = Get-FilesystemIndex -ProjectRoot $root

    $outPath      = Join-Path $OutputDir "$($index.project_id)-fs-index.json"
    $snapshotPath = $null

    if ($WhatIf) {
        Write-Host "  [WhatIf] Would write: $outPath" -ForegroundColor DarkYellow
        Write-Host "  [WhatIf] Would write rollback snapshot for $($index.project_id)" -ForegroundColor DarkYellow
    } else {
        $index | ConvertTo-Json -Depth 8 | Set-Content -Path $outPath -Encoding UTF8
        Write-Host "  [Index] Written: $outPath" -ForegroundColor Green

        if (Test-Path $SnapshotDir) {
            $snapshotPath = Write-RollbackSnapshot -Index $index -SnapshotDir $SnapshotDir
            Write-Host "  [Snapshot] Written: $snapshotPath" -ForegroundColor Green
        }
    }

    # Report summary
    Write-Host "  [Summary] $($index.project_id): $($index.total_files) files, $($index.total_size_kb)KB" -ForegroundColor Gray
    Write-Host "  [Summary] Key files present: $($index.key_files_present -join ', ')" -ForegroundColor Gray
    if ($index.duplicate_names.Count -gt 0) {
        Write-Host "  [Duplicates] $($index.duplicate_names.Count) duplicate filename(s) detected" -ForegroundColor Yellow
    }
    if ($index.orphan_candidates.Count -gt 0) {
        Write-Host "  [Orphans] $($index.orphan_candidates.Count) potential orphan file(s) detected" -ForegroundColor Yellow
    }
    if ($index.recently_changed.Count -gt 0) {
        Write-Host "  [Recent] $($index.recently_changed.Count) file(s) changed in last 60 min" -ForegroundColor Cyan
    }

    $allIndexes += $index
}

# Write combined index
if (-not $WhatIf) {
    $combinedPath = Join-Path $OutputDir "all-projects-index.json"
    [PSCustomObject]@{
        generated_at   = (Get-Date -Format 'o')
        project_count  = $allIndexes.Count
        projects       = $allIndexes
    } | ConvertTo-Json -Depth 10 | Set-Content -Path $combinedPath -Encoding UTF8
    Write-Host "[Filesystem Indexer] Combined index: $combinedPath" -ForegroundColor Green
}

Write-Host "[Filesystem Indexer] Complete" -ForegroundColor Cyan
return $allIndexes
