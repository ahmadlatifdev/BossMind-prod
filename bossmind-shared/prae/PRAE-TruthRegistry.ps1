#Requires -Version 5.1
<#
.SYNOPSIS
    PRAE Truth Registry
    Stores and retrieves evidence-confirmed facts for each project.
    Only writes records that have been evaluated by the Memory Promotion Gate.
    Appends history; never overwrites previous entries.

    governance_mode=LOCKED  production_mutation=NONE  auto_repair=DISABLED
.PARAMETER Action
    Read | Write | History | Summary
.PARAMETER ProjectName
    e.g. "bossmind-resumora"
.PARAMETER Record
    PSCustomObject from PRAE-MemoryPromotionGate to write.
.PARAMETER RegistryRoot
    Default: D:\BossMind\bossmind-shared\prae\truth-registry
.PARAMETER MaxHistory
    Maximum records to keep per project. Default: 50.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidateSet("Read","Write","History","Summary")]
    [string]$Action,

    [Parameter(Mandatory)]
    [string]$ProjectName,

    [PSCustomObject]$Record  = $null,

    [string]$RegistryRoot = "D:\BossMind\bossmind-shared\prae\truth-registry",
    [int]   $MaxHistory   = 50
)

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Set-Variable -Name GOV_MODE    -Value "LOCKED"  -Option ReadOnly -Force
Set-Variable -Name GOV_MUTATION -Value "NONE"   -Option ReadOnly -Force

$safeName     = $ProjectName.ToLower().Replace(' ','-').Replace('/','-')
$registryFile = Join-Path $RegistryRoot "$safeName-truth-registry.json"
$UNKNOWN      = "UNKNOWN"

# -- Helpers ---------------------------------------------------
function Ensure-Dir {
    param([string]$Path)
    if (-not (Test-Path $Path)) {
        New-Item -ItemType Directory -Path $Path -Force | Out-Null
    }
}

function Read-Registry {
    if (-not (Test-Path $registryFile)) { return [PSCustomObject]@{ project=$ProjectName; records=@() } }
    try {
        $raw = [System.IO.File]::ReadAllText($registryFile, [System.Text.Encoding]::UTF8)
        return $raw | ConvertFrom-Json
    } catch {
        Write-Warning "PRAE-TruthRegistry: Cannot read $registryFile : $_"
        return [PSCustomObject]@{ project=$ProjectName; records=@() }
    }
}

function Save-Registry {
    param([PSCustomObject]$Reg)
    Ensure-Dir $RegistryRoot
    $tmp = $registryFile + ".tmp"
    $Reg | ConvertTo-Json -Depth 15 |
        ForEach-Object { [System.IO.File]::WriteAllText($tmp, $_, [System.Text.Encoding]::UTF8) }
    Move-Item -Path $tmp -Destination $registryFile -Force
}

# -- ACTION: Write ---------------------------------------------
if ($Action -eq "Write") {
    if ($null -eq $Record) {
        Write-Warning "PRAE-TruthRegistry: Write called with no Record."
        return $null
    }

    # Validate record has required fields
    if (-not $Record.PSObject.Properties['overall_confidence']) {
        Write-Warning "PRAE-TruthRegistry: Record missing overall_confidence  -  rejected."
        return $null
    }
    if (-not $Record.PSObject.Properties['evidence_collected_at']) {
        Write-Warning "PRAE-TruthRegistry: Record missing evidence_collected_at  -  rejected."
        return $null
    }

    $reg     = Read-Registry
    $records = @($reg.records)

    # Build new entry with write timestamp
    $entry = [ordered]@{
        registry_entry_at   = [DateTimeOffset]::UtcNow.ToString("o")
        overall_confidence  = $Record.overall_confidence
        evidence_collected_at = $Record.evidence_collected_at
        project_name        = $ProjectName
        governance_mode     = $GOV_MODE
        production_mutation = $GOV_MUTATION
        evidence_summary    = $Record.PSObject.Properties['evidence_summary'] ? $Record.evidence_summary : $null
        verified_facts      = $Record.PSObject.Properties['verified_facts']   ? $Record.verified_facts   : @()
        partial_facts       = $Record.PSObject.Properties['partial_facts']    ? $Record.partial_facts    : @()
        unknown_facts       = $Record.PSObject.Properties['unknown_facts']    ? $Record.unknown_facts    : @()
        missing_partials    = $Record.PSObject.Properties['missing_partials'] ? $Record.missing_partials : @()
        raw_evidence_ref    = $Record.PSObject.Properties['raw_evidence_ref'] ? $Record.raw_evidence_ref : $null
    }

    $records = @($records) + @([PSCustomObject]$entry)

    # Cap history
    if ($records.Count -gt $MaxHistory) {
        $records = $records | Select-Object -Last $MaxHistory
    }

    $newReg = [ordered]@{
        project          = $ProjectName
        registry_version = "1.0"
        governance_mode  = $GOV_MODE
        last_updated     = [DateTimeOffset]::UtcNow.ToString("o")
        record_count     = @($records).Count
        records          = $records
    }

    Save-Registry -Reg ([PSCustomObject]$newReg)
    Write-Verbose "PRAE-TruthRegistry: Written record for $ProjectName (confidence=$($entry.overall_confidence))"
    return [PSCustomObject]$entry
}

# -- ACTION: Read (latest record) ------------------------------
if ($Action -eq "Read") {
    $reg = Read-Registry
    $records = @($reg.records)
    if ($records.Count -eq 0) {
        return [PSCustomObject]@{
            project_name       = $ProjectName
            overall_confidence = $UNKNOWN
            note               = "No records in truth registry"
        }
    }
    return $records | Select-Object -Last 1
}

# -- ACTION: History (all records) ----------------------------
if ($Action -eq "History") {
    $reg = Read-Registry
    return @($reg.records)
}

# -- ACTION: Summary -------------------------------------------
if ($Action -eq "Summary") {
    $reg     = Read-Registry
    $records = @($reg.records)

    if ($records.Count -eq 0) {
        Write-Host "  $ProjectName : No truth registry records" -ForegroundColor Gray
        return
    }

    $latest     = $records | Select-Object -Last 1
    $confidence = $latest.overall_confidence
    $color      = switch ($confidence) {
        "VERIFIED" { "Green"  }
        "PARTIAL"  { "Yellow" }
        "UNKNOWN"  { "Gray"   }
        default    { "DarkGray" }
    }

    $age = "?"
    try {
        $ts  = [DateTimeOffset]::Parse($latest.registry_entry_at)
        $sec = [int]([DateTimeOffset]::UtcNow - $ts).TotalSeconds
        $age = if ($sec -lt 60) { "${sec}s ago" } elseif ($sec -lt 3600) { "$([int]($sec/60))m ago" } else { "$([int]($sec/3600))h ago" }
    } catch {}

    Write-Host "  $ProjectName" -NoNewline -ForegroundColor White
    Write-Host "  [$confidence]" -NoNewline -ForegroundColor $color
    Write-Host "  $age  ($($records.Count) records)" -ForegroundColor Gray

    $verified = @($latest.verified_facts)
    $partial  = @($latest.partial_facts)
    $unknown  = @($latest.unknown_facts)
    $missing  = @($latest.missing_partials)

    if (@($verified).Count) {
        Write-Host "    Verified : $(@($verified).Count) facts" -ForegroundColor Green
    }
    if (@($partial).Count) {
        Write-Host "    Partial  : $(@($partial).Count) facts" -ForegroundColor Yellow
    }
    if (@($unknown).Count) {
        Write-Host "    Unknown  : $(@($unknown).Count) facts" -ForegroundColor Gray
    }
    if (@($missing).Count) {
        Write-Host "    Missing  : $(@($missing).Count) action items" -ForegroundColor Red
    }
}
