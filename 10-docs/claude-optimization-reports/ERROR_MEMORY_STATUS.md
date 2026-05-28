# BossMind Error Memory Status
**Generated:** 2026-05-23

---

## Current Error Log State

**error_memory.jsonl:** NOT YET CREATED (watcher has not run against real projects)

This is the expected pre-activation state. The error memory system is fully implemented and will begin accumulating records immediately upon first watcher tick that encounters an error condition.

---

## Error Categories Detected by Watcher

| Error Category | Source Detector | Fingerprinted | Stored |
|----------------|----------------|---------------|--------|
| Build errors (TypeScript) | Get-BuildErrorState | YES | YES |
| Lint errors | Get-BuildErrorState | YES | YES |
| Test failures | Get-BuildErrorState | YES | YES |
| Health endpoint failures | Get-HealthState | YES | YES |
| S3 sync drift | Get-S3SyncState | YES | YES |
| Env file leaks | Get-FilesystemState | YES | YES |
| Missing required env keys | Get-EnvKeyNames | YES | YES |
| Watcher exceptions (internal) | daemon try/catch | YES | YES |

---

## Fingerprint Design

Every unique combination of errors produces a stable 8-character hex hash:

```
Input:  ["health_fail:railway-api:Connection refused", "lint: 3 errors"]
Sorted: ["health_fail:railway-api:Connection refused", "lint: 3 errors"]
Joined: "health_fail:railway-api:Connection refused|lint: 3 errors"
SHA256: a4f3c29b1e8d7f06...
Output: "a4f3c29b"  (first 4 bytes as lowercase hex)
```

Same errors across different projects, branches, or timestamps → **same hash**.  
This enables: regression detection, occurrence counting, repair strategy lookup.

---

## JSONL Record Schema

```json
{
  "_type": "error_memory",
  "_written": "2026-05-23T14:00:01.000Z",
  "project_id": "bossmind-resumora",
  "error_hash": "a4f3c29b",
  "source": "watcher",
  "errors": ["health_fail:railway-api:Connection refused"],
  "status": "new",
  "repair_strategy": null,
  "git_branch": "main",
  "git_commit": "a1b2c3d",
  "git_dirty": false,
  "tick": 5,
  "has_railway_toml": true,
  "has_render_yaml": false,
  "env_key_count": 12
}
```

**Note:** `errors` array contains error descriptions. No secret values. No env values.

---

## Anti-Regression Gate Behavior

When `regression-check.ps1` runs (pre-push hook):

```
1. Get-BuildErrorState detects current errors
2. Get-ErrorFingerprint hashes them → "a4f3c29b"
3. Get-ErrorMemoryByHash looks up "a4f3c29b" in log
4. If found AND no resolved record exists → BLOCK PUSH
5. If found AND resolved record exists → ALLOW PUSH
6. If not found → ALLOW PUSH (new error, not a regression)
```

---

## Repair Pattern Accumulation (Phase 2 capability)

The `repair_strategy` field is populated when:
- An operator manually resolves an error via `Set-ErrorResolved -RepairStrategy "..."`
- A Phase 2 autonomous repair loop successfully resolves and records the fix

Over time, the error memory log becomes a knowledge base of:
- Which error patterns recur
- Which branches they appear on
- Which repair strategies resolved them
- How many ticks before resolution

**This data is the foundation for Phase 2 autonomous repair.**

---

## Known Gaps

| Gap | Impact | Phase to fix |
|-----|--------|-------------|
| No auto-escalation after N failures | Manual intervention required | Phase 2 |
| No Slack/email alert on new hash | Errors silent until health check | Phase 2 |
| No repair strategy auto-lookup | Must manually record resolutions | Phase 2 |
| No cross-project error correlation | Each project isolated | Phase 3 |
| Log grows unbounded | Disk usage concern at scale | Phase 2 |
