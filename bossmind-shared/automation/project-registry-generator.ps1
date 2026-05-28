#!/usr/bin/env pwsh
<#
.SYNOPSIS
    BossMind Project Registry Generator — Phase 1

.DESCRIPTION
    Auto-discovers project directories and builds a comprehensive service
    registry including:
      - Project identity (name, version, language, framework)
      - Git remote URLs and branch state
      - Detected deployment targets (Railway, Render, Vercel, etc.)
      - Package manager and script availability
      - Service dependencies from package.json
      - Health endpoint candidates
      - Cross-project dependency detection

    SAFETY: Read-only. Discovers by inspecting config files only.
    Never executes npm, git push, or any build command.
    Never modifies any project file.

.PARAMETER SearchRoots
    Parent directories to search for projects. Each immediate subdirectory
    that contains a package.json, go.mod, or pyproject.toml is a candidate.

.PARAMETER ExplicitRoots
    Explicit project root paths (skips auto-discovery).

.PARAMETER OutputDir
    Where to write the registry JSON. Default: ../registry

.PARAMETER WhatIf
    Discover and report but write nothing.
#>

param(
    [string[]]$SearchRoots,
    [string[]]$ExplicitRoots,
    [string]$OutputDir = (Join-Path $PSScriptRoot ".." "registry"),
    [switch]$WhatIf
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Continue"

$ProjectIndicators = @('package.json','go.mod','pyproject.toml','Cargo.toml','requirements.txt','Pipfile')

$FrameworkSignatures = @{
    'next.config.js'     = 'Next.js'
    'next.config.ts'     = 'Next.js'
    'nuxt.config.ts'     = 'Nuxt'
    'svelte.config.js'   = 'SvelteKit'
    'astro.config.mjs'   = 'Astro'
    'vite.config.ts'     = 'Vite'
    'vite.config.js'     = 'Vite'
    'remix.config.js'    = 'Remix'
    'gatsby-config.js'   = 'Gatsby'
    'angular.json'       = 'Angular'
    'vue.config.js'      = 'Vue'
    'webpack.config.js'  = 'Webpack'
    'express'            = 'Express'   # detected via package.json dep
    'fastapi'            = 'FastAPI'   # detected via requirements.txt
    'django'             = 'Django'
    'flask'              = 'Flask'
}

$DeploymentSignatures = @{
    'railway.toml'    = 'Railway'
    'render.yaml'     = 'Render'
    'vercel.json'     = 'Vercel'
    'netlify.toml'    = 'Netlify'
    'Procfile'        = 'Heroku/Railway'
    '.railway'        = 'Railway'
    'fly.toml'        = 'Fly.io'
    'serverless.yml'  = 'Serverless'
    'sam.yaml'        = 'AWS SAM'
    'template.yaml'   = 'AWS SAM'
    'docker-compose.yml' = 'Docker Compose'
    'Dockerfile'      = 'Docker'
    'k8s'             = 'Kubernetes'
    'helm'            = 'Helm/Kubernetes'
}

function Get-ProjectLanguage ([string]$Root) {
    if (Test-Path (Join-Path $Root "package.json"))    { return "JavaScript/TypeScript" }
    if (Test-Path (Join-Path $Root "go.mod"))          { return "Go" }
    if (Test-Path (Join-Path $Root "Cargo.toml"))      { return "Rust" }
    if (Test-Path (Join-Path $Root "pyproject.toml"))  { return "Python" }
    if (Test-Path (Join-Path $Root "requirements.txt")){ return "Python" }
    if (Test-Path (Join-Path $Root "Gemfile"))         { return "Ruby" }
    if (Test-Path (Join-Path $Root "pom.xml"))         { return "Java/Maven" }
    if (Test-Path (Join-Path $Root "build.gradle"))    { return "Java/Gradle" }
    if (Test-Path (Join-Path $Root "*.csproj"))        { return ".NET" }
    return "Unknown"
}

function Get-ProjectFramework ([string]$Root) {
    foreach ($sig in $FrameworkSignatures.GetEnumerator()) {
        if (Test-Path (Join-Path $Root $sig.Key)) { return $sig.Value }
    }
    # Check package.json dependencies for framework hints
    $pkgPath = Join-Path $Root "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $allDeps = @()
            if ($pkg.dependencies)    { $allDeps += ($pkg.dependencies | Get-Member -MemberType NoteProperty).Name }
            if ($pkg.devDependencies) { $allDeps += ($pkg.devDependencies | Get-Member -MemberType NoteProperty).Name }
            if ('next'      -in $allDeps) { return 'Next.js' }
            if ('nuxt'      -in $allDeps) { return 'Nuxt' }
            if ('svelte'    -in $allDeps) { return 'SvelteKit' }
            if ('astro'     -in $allDeps) { return 'Astro' }
            if ('express'   -in $allDeps) { return 'Express' }
            if ('fastify'   -in $allDeps) { return 'Fastify' }
            if ('hono'      -in $allDeps) { return 'Hono' }
            if ('react'     -in $allDeps) { return 'React' }
            if ('vue'       -in $allDeps) { return 'Vue' }
            if ('angular'   -in $allDeps) { return 'Angular' }
        } catch {}
    }
    return 'Unknown'
}

function Get-GitInfo ([string]$Root) {
    $info = [ordered]@{
        is_repo        = $false
        remote_url     = $null
        remote_name    = $null
        default_branch = $null
        current_branch = $null
        commit_hash    = $null
        commit_message = $null
        is_dirty       = $false
        ahead          = 0
        behind         = 0
    }
    if (-not (Test-Path (Join-Path $Root ".git"))) { return [PSCustomObject]$info }
    $info.is_repo = $true
    try {
        $info.current_branch = (git -C $Root rev-parse --abbrev-ref HEAD 2>$null)?.Trim()
        $info.commit_hash    = (git -C $Root rev-parse --short HEAD 2>$null)?.Trim()
        $info.commit_message = (git -C $Root log -1 --format="%s" 2>$null)?.Trim()
        $info.remote_name    = (git -C $Root remote 2>$null | Select-Object -First 1)?.Trim()
        if ($info.remote_name) {
            $info.remote_url = (git -C $Root remote get-url $info.remote_name 2>$null)?.Trim()
        }
        $status = git -C $Root status --porcelain 2>$null
        $info.is_dirty = ($status -and ($status -split "`n" | Where-Object { $_ }).Count -gt 0)
    } catch {}
    return [PSCustomObject]$info
}

function Get-DeploymentTargets ([string]$Root) {
    $targets = @()
    foreach ($sig in $DeploymentSignatures.GetEnumerator()) {
        if (Test-Path (Join-Path $Root $sig.Key)) {
            $targets += $sig.Value
        }
    }
    return $targets | Select-Object -Unique
}

function Get-ServiceEntry ([string]$Root) {
    $projectId = Split-Path $Root -Leaf
    $language  = Get-ProjectLanguage  -Root $Root
    $framework = Get-ProjectFramework -Root $Root
    $git       = Get-GitInfo          -Root $Root
    $deploys   = Get-DeploymentTargets -Root $Root

    # Read package.json safely
    $pkgName    = $null
    $pkgVersion = $null
    $scripts    = @{}
    $runtimeDeps = @()
    $devDeps    = @()

    $pkgPath = Join-Path $Root "package.json"
    if (Test-Path $pkgPath) {
        try {
            $pkg = Get-Content $pkgPath -Raw | ConvertFrom-Json -ErrorAction Stop
            $pkgName    = $pkg.name
            $pkgVersion = $pkg.version
            if ($pkg.scripts) {
                $scripts = $pkg.scripts | ConvertTo-Json | ConvertFrom-Json
            }
            if ($pkg.dependencies)    { $runtimeDeps = ($pkg.dependencies | Get-Member -MemberType NoteProperty).Name }
            if ($pkg.devDependencies) { $devDeps     = ($pkg.devDependencies | Get-Member -MemberType NoteProperty).Name }
        } catch {}
    }

    # Detect health endpoint candidates from common patterns
    $healthEndpointCandidates = @('/health','/ready','/ping','/status','/api/health','/api/status')

    # Detect port from various config files
    $detectedPort = $null
    $portSources  = @('.env.example','.env.local','.env')
    foreach ($src in $portSources) {
        $srcPath = Join-Path $Root $src
        if (Test-Path $srcPath) {
            try {
                $portLine = Get-Content $srcPath | Where-Object { $_ -match '^PORT\s*=' } | Select-Object -First 1
                if ($portLine -match '^PORT\s*=\s*(\d+)') {
                    $detectedPort = [int]$Matches[1]
                    break
                }
            } catch {}
        }
    }

    # GitHub Actions workflow names
    $workflows = @()
    $wfDir = Join-Path $Root ".github" "workflows"
    if (Test-Path $wfDir) {
        $workflows = Get-ChildItem $wfDir -Filter "*.yml" -ErrorAction SilentlyContinue |
            ForEach-Object { $_.Name }
    }

    return [PSCustomObject]@{
        project_id                = $projectId
        package_name              = $pkgName
        package_version           = $pkgVersion
        root_path                 = $Root
        language                  = $language
        framework                 = $framework
        deployment_targets        = $deploys
        git                       = $git
        scripts                   = $scripts
        runtime_deps_count        = $runtimeDeps.Count
        dev_deps_count            = $devDeps.Count
        runtime_deps              = $runtimeDeps | Select-Object -First 30
        github_workflows          = $workflows
        detected_port             = $detectedPort
        health_endpoint_candidates = $healthEndpointCandidates
        registered_at             = (Get-Date -Format 'o')
    }
}

# ── Main ───────────────────────────────────────────────────────────────────────
Write-Host "[Registry Generator] Starting — $(Get-Date -Format 'o')" -ForegroundColor Cyan

if (-not (Test-Path $OutputDir) -and -not $WhatIf) {
    New-Item -ItemType Directory -Path $OutputDir -Force | Out-Null
}

# ── Resolve all project roots ──────────────────────────────────────────────────
$resolvedRoots = [System.Collections.Generic.List[string]]::new()

if ($ExplicitRoots) {
    $ExplicitRoots | ForEach-Object { $resolvedRoots.Add($_) }
}

if ($SearchRoots) {
    foreach ($searchRoot in $SearchRoots) {
        if (-not (Test-Path $searchRoot)) { continue }
        Get-ChildItem -Path $searchRoot -Directory -ErrorAction SilentlyContinue | ForEach-Object {
            $hasIndicator = $ProjectIndicators | Where-Object { Test-Path (Join-Path $_.FullName $_) }
            if ($hasIndicator -and $_.FullName -notin $resolvedRoots) {
                $resolvedRoots.Add($_.FullName)
            }
        }
    }
}

Write-Host "[Registry Generator] Found $($resolvedRoots.Count) project(s)" -ForegroundColor Gray

# ── Build registry ─────────────────────────────────────────────────────────────
$registry = @()
foreach ($root in $resolvedRoots) {
    Write-Host "  [Register] $root" -ForegroundColor DarkCyan
    $entry = Get-ServiceEntry -Root $root
    $registry += $entry
    Write-Host "  [Register] $($entry.project_id): $($entry.language) / $($entry.framework) → $($entry.deployment_targets -join ', ')" -ForegroundColor Gray
}

# ── Cross-project dependency detection ────────────────────────────────────────
$crossDeps = @()
foreach ($entry in $registry) {
    foreach ($other in $registry) {
        if ($entry.project_id -eq $other.project_id) { continue }
        if ($entry.package_name -and $entry.package_name -in $other.runtime_deps) {
            $crossDeps += [PSCustomObject]@{
                consumer = $other.project_id
                provider = $entry.project_id
                type     = "npm_dependency"
            }
        }
    }
}

# ── Write registry ─────────────────────────────────────────────────────────────
$fullRegistry = [PSCustomObject]@{
    generated_at        = (Get-Date -Format 'o')
    project_count       = $registry.Count
    cross_dependencies  = $crossDeps
    projects            = $registry
}

if ($WhatIf) {
    Write-Host "[WhatIf] Would write: $OutputDir/service-registry.json" -ForegroundColor DarkYellow
    $fullRegistry | ConvertTo-Json -Depth 8 | Select-Object -First 50
} else {
    $outPath = Join-Path $OutputDir "service-registry.json"
    $fullRegistry | ConvertTo-Json -Depth 8 | Set-Content -Path $outPath -Encoding UTF8
    Write-Host "[Registry Generator] Written: $outPath" -ForegroundColor Green

    # Also write per-project entries for quick lookup
    foreach ($entry in $registry) {
        $perProjectPath = Join-Path $OutputDir "$($entry.project_id)-registry.json"
        $entry | ConvertTo-Json -Depth 8 | Set-Content -Path $perProjectPath -Encoding UTF8
    }
}

Write-Host "[Registry Generator] Complete — $($registry.Count) project(s) registered" -ForegroundColor Cyan
return $fullRegistry
