#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Missing/Partial Resolver
    Reads the truth registry, extracts all MISSING and PARTIAL items,
    generates prioritised actionable task records, and writes them to
    the missing-partials directory.
    Prints a clean resolution summary to the console.

    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED
.PARAMETER ProjectName
    e.g. "bossmind-resumora"
.PARAMETER RegistryRoot
    Default: D:\BossMind\bossmind-shared\prae\truth-registry
.PARAMETER MissingPartialsRoot
    Default: D:\BossMind\bossmind-shared\prae\missing-partials
.PARAMETER TruthRegistryScript
    Default: D:\BossMind\bossmind-shared\prae\PRAE-TruthRegistry.ps1
.PARAMETER ShowAll
    Show all items including resolved ones.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [string]$ProjectName,

    [string]$RegistryRoot        = "D:\BossMind\bossmind-shared\prae\truth-registry",
    [string]$MissingPartialsRoot = "D:\BossMind\bossmind-shared\prae\missing-partials",
    [string]$TruthRegistryScript = "D:\BossMind\bossmind-shared\prae\PRAE-TruthRegistry.ps1",
    [switch]$ShowAll
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Variable -Name GOV_MODE    -Value "LOCKED"  -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION -Value "NONE"   -Option ReadOnly -Force

$safeName   = $ProjectName.ToLower().Replace(' ','-').Replace('/','-')
$outputFile = Join-Path $MissingPartialsRoot "$safeName-missing-partials.json"

# -- Read latest truth registry record ------------------------
$latestRecord = $null
if (Test-Path $TruthRegistryScript) {
    $latestRecord = & $TruthRegistryScript -Action Read -ProjectName $ProjectName -RegistryRoot $RegistryRoot
} else {
    # Fallback: read file directly
    $regFile = Join-Path $RegistryRoot "$safeName-truth-registry.json"
    if (Test-Path $regFile) {
        try {
            $reg = Get-Content $regFile -Raw -Encoding UTF8 | ConvertFrom-Json
            $latestRecord = @($reg.records) | Select-Object -Last 1
        } catch {
            Write-Warning "Cannot read truth registry: $_"
        }
    }
}

if ($null -eq $latestRecord -or $latestRecord.overall_confidence -eq "UNKNOWN" -and -not $latestRecord.PSObject.Properties['missing_partials']) {
    Write-Host ""
    Write-Host "  No truth registry record found for $ProjectName" -ForegroundColor Yellow
    Write-Host "  Run PRAE-EvidenceCollector.ps1 + PRAE-MemoryPromotionGate.ps1 first." -ForegroundColor Gray
    Write-Host ""
    return
}

$missing = @($latestRecord.missing_partials)
$now     = [DateTimeOffset]::UtcNow.ToString("o")

# -- Build resolution task list --------------------------------
$priorityOrder = @{ "CRITICAL"=0; "HIGH"=1; "MEDIUM"=2; "LOW"=3 }
$tasks = @($missing | Sort-Object {
    $p = $_.priority
    if ($priorityOrder.Contains($p)) { $priorityOrder[$p] } else { 99 }
})

# -- Write to missing-partials file ---------------------------
if (-not (Test-Path $MissingPartialsRoot)) {
    New-Item -ItemType Directory -Path $MissingPartialsRoot -Force | Out-Null
}

$output = [ordered]@{
    project_name          = $ProjectName
    generated_at          = $now
    governance_mode       = $GOV_MODE
    production_mutation   = $GOV_MUTATION
    source_confidence     = $latestRecord.overall_confidence
    source_evaluated_at   = if ($latestRecord.PSObject.Properties['evaluated_at']) { $latestRecord.evaluated_at } else { "UNKNOWN" }
    total_items           = @($tasks).Count
    critical_count        = @($tasks | Where-Object { $_.priority -eq "CRITICAL" }).Count
    high_count            = @($tasks | Where-Object { $_.priority -eq "HIGH"     }).Count
    medium_count          = @($tasks | Where-Object { $_.priority -eq "MEDIUM"   }).Count
    tasks                 = $tasks
}

$tmp = $outputFile + ".tmp"
$output | ConvertTo-Json -Depth 8 |
    ForEach-Object { [System.IO.File]::WriteAllText($tmp, $_, [System.Text.Encoding]::UTF8) }
Move-Item -Path $tmp -Destination $outputFile -Force

# -- Console report --------------------------------------------
Write-Host ""
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host "  |  PRAE Missing/Partial Resolver                   |" -ForegroundColor Cyan
Write-Host "  |  Project: $($ProjectName.PadRight(39))|" -ForegroundColor DarkCyan
Write-Host "  +--------------------------------------------------+" -ForegroundColor DarkCyan
Write-Host ""

$confColor = switch ($latestRecord.overall_confidence) {
    "VERIFIED" { "Green" } "PARTIAL" { "Yellow" } default { "Gray" }
}
Write-Host "  Source confidence : " -NoNewline -ForegroundColor Gray
Write-Host $latestRecord.overall_confidence -ForegroundColor $confColor
Write-Host "  Total action items: $(@($tasks).Count)" -ForegroundColor White
Write-Host "  File: $outputFile" -ForegroundColor Gray
Write-Host ""

if (@($tasks).Count -eq 0) {
    Write-Host "  No missing or partial items. All evidence verified." -ForegroundColor Green
    Write-Host ""
    return
}

# Group by priority
foreach ($priority in @("CRITICAL","HIGH","MEDIUM","LOW")) {
    $group = @($tasks | Where-Object { $_.priority -eq $priority })
    if (@($group).Count -eq 0) { continue }

    $color = switch ($priority) {
        "CRITICAL" { "Red"     }
        "HIGH"     { "DarkYellow" }
        "MEDIUM"   { "Yellow"  }
        "LOW"      { "Gray"    }
    }
    Write-Host "  [$priority] $(@($group).Count) item(s)" -ForegroundColor $color
    foreach ($task in $group) {
        $statusTag = if ($task.status -eq "MISSING") { "[MISSING]" } else { "[PARTIAL]" }
        Write-Host "    $statusTag $($task.category)/$($task.item)" -ForegroundColor $color
        Write-Host "           $($task.action_required)" -ForegroundColor Gray
    }
    Write-Host ""
}

Write-Host "  governance_mode=$GOV_MODE  production_mutation=$GOV_MUTATION" -ForegroundColor DarkCyan
Write-Host ""

return [PSCustomObject]$output
