# BOSSMIND — SAFE AUTONOMY UPGRADE PLAN
**Generated:** 2026-05-23 | **Analyst:** BossMind Cowork Agent  
**Current Autonomy:** 34% | **Target:** 85%+

---

## CORE PRINCIPLE
> **Never modify production files automatically. Never overwrite working deployments. Every step is verified before the next begins. Production safety takes priority over speed.**

---

## CURRENT AUTONOMY BASELINE

| Subsystem | Score | Classification |
|---|---|---|
| bossmind-resumora | 60% | **PARTIAL** |
| bossmind-supervisor-service | 10% | **BROKEN** |
| bossmind-master-admin | 15% | **PARTIAL** |
| bossmind-shared automation | 25% | **PARTIAL** |
| Shared Memory | 30% | **PARTIAL** |
| Error Memory | 15% | **BROKEN** |
| AWS/S3 | 40% | **PARTIAL** |
| Neon Integration | 55% | **PARTIAL** |
| CI/CD Pipeline | 20% | **PARTIAL** |
| Render Integration | 15% | **PARTIAL** |
| Railway Integration | 45% | **PARTIAL** |
| AI Video Generator | 0% | **MISSING** |
| ElegancyArt | 0% | **MISSING** |
| TikTok AI | 0% | **MISSING** |
| Global Stock | 0% | **MISSING** |
| **OVERALL SYSTEM** | **34%** | **PARTIAL** |

---

## PHASE 1 — STABILIZE EXISTING SYSTEMS (Week 1)
**Goal:** Get all currently-deployed systems to 100% functional  
**Risk Level:** LOW (no new code, only fixes)  
**Production Impact:** ZERO (no production file changes)

### Step 1.1 — Fix Supervisor Service (CRITICAL)
```
Action: Create missing module stubs in bossmind-supervisor-service/
Files to create (stubs first, then wire):
  - autoFixEngine.js
  - repairTaskLog.js
  - githubFixExecutor.js
  - crossProjectMemoryRouter.js
  - errorPatternLibrary.js
  - safePatchGuard.js
  - deploymentVerifier.js
  - rollbackController.js
  - validationAI.js
  - closedLoopEngine.js
  - snapshotDeployEngine.js
  - predictiveSystem.js
  - requirementLockEngine.js
  - masterRunbookEngine.js
  - executionBoundaryGuard.js
  - automationProofLedger.js
  - powerShellControlledRunner.js

Verification: node supervisor.cjs → must run without crash
Deploy: git push → Railway redeploys supervisor
Safety check: verify Railway logs show "BossMind Self-Healing Supervisor started"
```

### Step 1.2 — Restore Enforcement Engine
```
Action: Copy bossmind-enforcement-engine.ps1.bak → bossmind-enforcement-engine.ps1
Test: Run script in dry-run mode
Verification: Script executes without error
```

### Step 1.3 — Populate Railway Service IDs
```
Action: Run 'railway status' or use Railway dashboard
  → Get real service IDs for deployed Resumora and Supervisor
  → Update bossmind-shared/automation/service-registry.json
  → Update bossmind-shared/automation/railway-deploy-config.json
  → Update all scripts that reference railway_service_id
Verification: Automation scripts can target services correctly
```

### Step 1.4 — Fix ai-config.json API Key
```
Action: Update bossmind-shared/config/ai-config.json
  → Read apiKey from process.env.DEEPSEEK_API_KEY at runtime
  → OR populate from .env.master.local bootstrap
Verification: AI router authenticates successfully
```

### Step 1.5 — Flush Memory Watcher Queue
```
Action: Run bossmind-shared/automation/bossmind-auto-memory-watcher.ps1
  → Process all 348KB of pending queue items
  → Monitor memory-watcher-failed.jsonl for new failures
Verification: memory-watcher-queue.jsonl size drops to near-zero
```

---

## PHASE 2 — ACTIVATE CONTINUOUS LOOPS (Week 2)
**Goal:** Move from manual triggers to always-on loops  
**Risk Level:** MEDIUM (new processes running)  
**Production Impact:** LOW (additive only)

### Step 2.1 — Deploy Autonomous Runtime to Railway
```
Current: bossmind-autonomous-runtime runs via PM2 (local only)
Action: Add second Railway service OR extend server.js to spawn runtime loop

Option A (Recommended — Lower Risk):
  Create bossmind-resumora/runtime-agent.js
  → Imports bossmind-autonomous-runtime.mjs logic
  → Runs as separate Railway service
  Deploy: New Railway service in project
  Verification: Railway logs confirm loop running every 60s

Option B (Simpler but coupled):
  In server.js, after server.listen() → spawn child process
  → node scripts/bossmind-autonomous-runtime.mjs
  Risk: Single process failure takes down both
```

### Step 2.2 — Schedule Memory Watcher (Windows)
```
Action: Use Windows Task Scheduler OR n8n webhook
  → Run bossmind-auto-memory-watcher.ps1 every 30 minutes
  → OR: Schedule via npm run bossmind:runtime:sync:once on cron

Verification: 
  - memory-watcher-queue.jsonl stays below 10KB
  - memory-watcher-processed.jsonl grows
  - No failures in memory-watcher-failed.jsonl
```

### Step 2.3 — Wire Neon DB Auto-Sync
```
Action: Add bossmind-neon-memory-sync.cjs to PM2 / Railway schedule
  → Run every 15 minutes
  → Sync local repair-log.json → Neon DB
  → Implement log rotation: archive entries > 30 days old

Verification:
  - Neon DB receives regular writes
  - repair-log.json stays below 500KB
```

### Step 2.4 — Activate n8n Bridge
```
Action: Confirm N8N_WEBHOOK_URL is live
  → Test: curl POST to N8N_WEBHOOK_URL
  → Wire bossmind-n8n-bridge.ps1 to automation loops
  → Route Sentry alerts → n8n → supervisor repair chain

Verification: n8n receives test webhook and responds
```

---

## PHASE 3 — ENHANCE SUPERVISOR SELF-HEALING (Week 3)
**Goal:** Build out all missing supervisor modules with real logic  
**Risk Level:** MEDIUM  
**Production Impact:** LOW (supervisor is separate service)

### Step 3.1 — Implement Core Repair Modules
Priority order:
1. `deploymentVerifier.js` — Check Railway/Render health endpoints
2. `validationAI.js` — Basic validation using existing AI router
3. `errorPatternLibrary.js` — Load from bossmind-shared error-patterns.json
4. `safePatchGuard.js` — Verify no dangerous patch patterns
5. `rollbackController.js` — Trigger Railway rollback via API
6. `crossProjectMemoryRouter.js` — Write to Neon DB memory schema

### Step 3.2 — Wire GitHub Auto-Fix
```
ONLY implement for non-production branches:
  - githubFixExecutor.js → creates PRs (never direct pushes to main)
  - Require human approval before merge
  - Gate: isPatchSafe() must return true
  - Gate: validateRepairDecision() must approve
```

### Step 3.3 — Connect Proof Ledger
```
automationProofLedger.js → writes repair audit trail to Neon DB
Every repair cycle generates immutable proof entry
Links to: requirementLockId, changedFiles, validation, deployment result
```

---

## PHASE 4 — BUILD MISSING PROJECTS (Weeks 4-8)
**Goal:** Activate 4 stub projects  
**Risk Level:** LOW (new projects, no production impact)  
**Production Impact:** ZERO (new services)

### Priority Order (based on business value)
1. **bossmind-elegancyart** (existing art business, direct revenue)
2. **bossmind-ai-video-generator** (existing npm scripts in Resumora)
3. **bossmind-tiktok-ai** (TikTok credentials already configured)
4. **bossmind-global-stock** (lowest urgency)

### Each Project — Minimum Viable Deploy
```
Per project checklist:
□ Create package.json with start script
□ Create server.js (Express or Next.js)
□ Create railway.json (build + deploy)
□ Populate deploy-config.json with real values
□ Add railway_service_id to service-registry.json
□ Configure .env for the project
□ Add to bossmind:backup:multi orchestrator
□ Deploy to Railway
□ Verify health endpoint responds
```

---

## PHASE 5 — FULL AUTONOMY HARDENING (Month 2)
**Goal:** Push overall autonomy above 80%  
**Risk Level:** LOW-MEDIUM  

### Step 5.1 — Master Admin — Deploy
```
Action: Add railway.json or render.yaml to bossmind-master-admin
Deploy: Separate Railway or Render service
Secure: Admin authentication via NextAuth or API key
```

### Step 5.2 — CI/CD Expansion
```
Add GitHub Actions workflows:
  - build-verify.yml → npm run validate:all on PR
  - deploy-gate.yml → npm run bossmind:deploy:gate on merge
  - neon-health.yml → weekly Neon connectivity check
  - backup-verify.yml → weekly backup health check
```

### Step 5.3 — Render + Railway Redundancy
```
Decision: Confirm Resumora canonical platform (Railway vs Render)
If dual:
  - Deploy Resumora to Render as hot-standby
  - Route via Cloudflare or health-check failover
If single:
  - Remove Render scripts that aren't needed
  - Clean up 15-render-production/
```

### Step 5.4 — S3 Backup Automation
```
Action: Wire bossmind-backup-daily.mjs → S3 upload
  → Daily: compress and push key project files to S3
  → Retention: 30 days
  → Verify: aws-validate-resumora-storage.mjs passes
```

---

## PROJECTED AUTONOMY AFTER EACH PHASE

| Phase | Timeline | Projected Autonomy | Key Unlock |
|---|---|---|---|
| Baseline (now) | — | **34%** | — |
| Phase 1 (Stabilize) | Week 1 | **52%** | Supervisor fixed, loops enabled |
| Phase 2 (Activate Loops) | Week 2 | **65%** | Continuous memory + runtime sync |
| Phase 3 (Supervisor) | Week 3 | **72%** | Error capture + auto-repair live |
| Phase 4 (New Projects) | Weeks 4-8 | **78%** | 4 new deployments live |
| Phase 5 (Hardening) | Month 2 | **87%** | Full CI/CD + redundancy |

---

## WHAT WILL NEVER BE FULLY AUTOMATED (Intentionally)

| Action | Why Human Required |
|---|---|
| Approving PRs from auto-fix | Code quality gate |
| Rotating API keys | Security audit required |
| Production environment variable changes | Risk of breaking live systems |
| Merging to main branch | Final human sign-off |
| Billing/Stripe plan changes | Revenue risk |
| Launching new Railway services | Cost and naming decisions |
| Supabase vs S3 storage migration | Data integrity risk |

---

## QUICK WIN CHECKLIST (Do Today)

- [ ] Restore bossmind-enforcement-engine.ps1 from .bak
- [ ] Delete 3 junk .txt files from bossmind-shared/automation/
- [ ] Delete bossmind-bridge-worker.js duplicate
- [ ] Archive old bossmind-master-runner.ps1 backups
- [ ] Run bossmind-auto-memory-watcher.ps1 to flush queue
- [ ] Populate service-registry.json with real Railway IDs
- [ ] Create stub modules for supervisor.cjs (17 files)
- [ ] Rotate repair-log.json (archive entries > May 3)
