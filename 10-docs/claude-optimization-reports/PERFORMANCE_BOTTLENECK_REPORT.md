# BossMind Performance Bottleneck Report
**Generated:** 2026-05-23  
**Method:** Static code analysis — no runtime profiling (watcher not yet run against real projects)

---

## Identified Bottlenecks by Severity

### CRITICAL — Will cause timeouts at scale

#### BN-001: Unbounded `Get-ChildItem -Recurse` on large projects
**Location:** `filesystem-indexer.ps1` + `lib/detectors.ps1:Get-FilesystemState`  
**Impact:** A project with 50,000+ files (e.g. after npm install in wrong dir) will take 30-120 seconds to scan, blocking the entire watcher tick.

**Current code:**
```powershell
$allItems = Get-ChildItem -Path $ProjectRoot -Recurse -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $excludeRegex }
```

**Fix (implement before running on large projects):**
```powershell
# Add depth limit and file count early-exit
$allItems = Get-ChildItem -Path $ProjectRoot -Recurse -Depth 8 -Force -ErrorAction SilentlyContinue |
    Where-Object { $_.FullName -notmatch $excludeRegex } |
    Select-Object -First 10000  # hard cap — log warning if hit
```

---

#### BN-002: Orphan detection runs full content scan
**Location:** `filesystem-indexer.ps1:Get-FilesystemIndex` — orphan detection block  
**Impact:** For projects with 100-500 source files, reads every file's content to check import references. At 500 files × 50KB average = 25MB of file reads per scan.

**Current mitigation:** Already skipped for projects >500 source files.  
**Recommended fix:** Implement an import graph cache between ticks. Only re-scan files whose modified timestamp changed.

---

### HIGH — Degrades performance on multi-project setups

#### BN-003: Sequential project scanning (no parallelism)
**Location:** `scripts/watcher-daemon.ps1` — main foreach loop  
**Impact:** 8 projects × 30 seconds scan each = 4 minutes per tick. Interval would need to be 5+ minutes.

**Current code:**
```powershell
foreach ($root in $ProjectRoots) {
    Invoke-ProjectTick -Root $root -TickCount $script:TickCount
}
```

**Fix (PS7+ only):**
```powershell
$ProjectRoots | ForEach-Object -Parallel {
    # requires passing functions via $using: — complex but achievable
    Invoke-ProjectTick -Root $_ -TickCount $using:TickCount
} -ThrottleLimit 4
```

---

#### BN-004: Registry regeneration on every commit change
**Location:** `scripts/watcher-daemon.ps1:Invoke-ProjectTick` — change detection block  
**Impact:** Every push triggers `project-registry-generator.ps1` which re-reads all config files for all projects. At 8 projects this is ~40 file reads.

**Fix:** Debounce with a minimum interval:
```powershell
$script:LastRegistryRegen = @{}
$minRegenInterval = 300  # 5 minutes
$lastRegen = $script:LastRegistryRegen[$projectId]
if (-not $lastRegen -or ((Get-Date) - $lastRegen).TotalSeconds -gt $minRegenInterval) {
    & $regGenPath ...
    $script:LastRegistryRegen[$projectId] = Get-Date
}
```

---

### MEDIUM — Noticeable at moderate scale

#### BN-005: Full JSONL scan for Read-SharedMemoryLatest
**Location:** `lib/shared-memory.ps1:Read-SharedMemoryLatest`  
**Impact:** Reads entire log file into memory and reverses it. After 30 days at 30s intervals with 8 projects = 691,200 lines. Reading and reversing 691,200 lines takes ~2-5 seconds.

**Fix:** Maintain a separate `shared_memory_index.json` with the byte offset of the last record per project. Use `[System.IO.FileStream]` with `Seek` to read only the last record.

---

#### BN-006: ConvertTo-Json -Depth 15 on every tick
**Location:** `lib/shared-memory.ps1:Write-SharedMemoryLog`  
**Impact:** The full snapshot at depth 15 can be 5-20KB per project per tick. JSON serialization at depth 15 is expensive for complex objects.

**Fix:** Reduce depth to 8 for production (sufficient for all current fields):
```powershell
$line = $record | ConvertTo-Json -Depth 8 -Compress  # was -Depth 15
```

---

#### BN-007: Health endpoint probe is synchronous
**Location:** `lib/detectors.ps1:Get-HealthState`  
**Impact:** If a health endpoint times out at 15 seconds, the entire tick for that project is blocked for 15 seconds.

**Fix:** Use `Start-Job` or `[System.Net.Http.HttpClient]` with async for endpoint probing:
```powershell
# Create jobs for all endpoints simultaneously
$jobs = $endpoints | ForEach-Object { 
    Start-Job -ScriptBlock { Invoke-WebRequest -Uri $using:ep.url -TimeoutSec 10 ... }
}
$results = $jobs | Wait-Job -Timeout 12 | Receive-Job
```

---

### LOW — Minor efficiency improvements

#### BN-008: git commands called individually per property
**Location:** `lib/detectors.ps1:Get-GitState`  
**Impact:** 8+ separate `git -C $root` subprocess calls per tick per project. Each git subprocess has ~50-100ms startup overhead.

**Fix:** Combine into fewer git calls using `git log --format` with multiple placeholders:
```powershell
$logLine = git -C $root log -1 --format="%H|%s|%an|%aI" 2>$null
$parts   = $logLine -split '\|'
# branch, status, stash still need separate calls
```

#### BN-009: Regex compiled fresh each tick
**Location:** `lib/detectors.ps1:Get-EnvKeyNames`  
**Impact:** Minor — regex `'^([A-Z][A-Z0-9_]+)\s*='` recompiled on each call.

**Fix:**
```powershell
# At script scope, outside function:
$script:EnvKeyPattern = [regex]'^([A-Z][A-Z0-9_]+)\s*='
# Then: $script:EnvKeyPattern.Match($line)
```

---

## Performance Budget Estimate (8 projects, current code)

| Operation | Time estimate | Per tick total |
|-----------|--------------|----------------|
| Get-ChildItem per project (1k files) | ~2s | 16s |
| Git state (8 subprocess calls) | ~0.8s | 6.4s |
| Package.json read | ~0.05s | 0.4s |
| Env key scan | ~0.1s | 0.8s |
| Build artifact check | ~0.1s | 0.8s |
| Deploy config check | ~0.05s | 0.4s |
| Health probes (sequential, no timeout hit) | ~0.5s | 4s |
| JSONL write | ~0.05s | 0.4s |
| Registry regen (first tick only) | ~1s | 8s |
| **TOTAL (first tick)** | | **~37s** |
| **TOTAL (subsequent ticks, no regen)** | | **~29s** |

**Recommendation: Set IntervalSeconds = 60 minimum for 8 projects. Use -ThrottleLimit 4 parallel scanning for production.**

---

## Optimization Priority Matrix

| Fix | Effort | Impact | Priority |
|-----|--------|--------|----------|
| Add depth limit to Get-ChildItem | Low (1 line) | HIGH | P1 |
| Reduce ConvertTo-Json depth 15→8 | Low (1 line) | MEDIUM | P1 |
| Debounce registry regeneration | Low (5 lines) | HIGH | P1 |
| Parallelize project scanning | Medium (20 lines) | VERY HIGH | P2 |
| Shared memory index for fast reads | Medium (30 lines) | HIGH | P2 |
| Async health endpoint probing | High (50 lines) | MEDIUM | P2 |
| Git batch subprocess calls | Medium (15 lines) | LOW | P3 |
| Regex pre-compilation | Low (2 lines) | LOW | P3 |
| Import graph cache for orphan detection | High (100 lines) | MEDIUM | P3 |
