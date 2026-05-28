# BOSSMIND — DEPLOYMENT PIPELINES
**Generated:** 2026-05-23 | **Analyst:** BossMind Cowork Agent

---

## PIPELINE OVERVIEW

| Project | Platform | Deploy Config | Auto Deploy | Status |
|---|---|---|---|---|
| bossmind-resumora | Railway | ✅ railway.json | ✅ Git push | **ACTIVE** |
| bossmind-supervisor-service | Railway | ✅ (separate service) | ✅ Git push | **BROKEN** |
| bossmind-master-admin | None | ❌ | ❌ | **NOT DEPLOYED** |
| bossmind-ai-video-generator | Railway (planned) | ⚠️ pending | ❌ | **MISSING** |
| bossmind-elegancyart | Railway (planned) | ⚠️ pending | ❌ | **MISSING** |
| bossmind-tiktok-ai | Railway (planned) | ⚠️ pending | ❌ | **MISSING** |
| bossmind-global-stock | Railway (planned) | ⚠️ pending | ❌ | **MISSING** |

---

## 1. RESUMORA — RAILWAY PIPELINE (PRIMARY)

```
Developer Machine (D:\BossMind\bossmind-resumora)
    │
    ├── Pre-commit Hook (.githooks/pre-commit)
    │   └── bossmind-pre-commit-secrets.ps1 → secret scan
    │
    ├── Pre-push Hook (.githooks/pre-push)
    │   └── bossmind-pre-push-secrets.ps1 → secret scan
    │
    └── git push origin main
            │
            ▼
    GitHub (github.com/ahmadlatifdev/bossmind-resumora)
            │
            ├── GitHub Actions: secret-scan.yml
            │   └── bossmind-secret-scan.ps1 → fail if secrets detected
            │
            └── Railway Auto-Deploy Trigger
                    │
                    ▼
            Railway Build:
                npm install
                    │
                    ▼
            Railway Start:
                node server.js
                ON_FAILURE → restart policy active
```

### Resumora Deploy Gates (npm scripts)
```
bossmind:enterprise:autonomous-chain
  └── bossmind:enterprise:preflight    (bossmind-enterprise-preflight.mjs)
      └── bossmind:deploy:gate         (bossmind-deploy-gate.mjs)
          └── bossmind:locked-production:verify (bossmind-locked-production-verify.mjs)

bossmind:enterprise:production-health (full chain):
  └── bossmind-sync-hub-database-env.mjs
  └── bossmind-render-env-bundle.mjs
  └── bossmind-production-full-recover.mjs
  └── bossmind-production-live-audit.mjs --apply-safe
```

### PM2 Process Config (ecosystem.config.cjs)
```
Process 1: resumora
  script: ./server.js
  instances: 1, exec_mode: fork
  max_memory_restart: 900M
  restart_delay: 3500ms

Process 2: bossmind-autonomous-runtime
  script: ./scripts/bossmind-autonomous-runtime.mjs
  instances: 1, exec_mode: fork
  max_memory_restart: 700M
  BOSSMIND_AUTONOMOUS_LOOP_MS: 60000 (prod)
  BOSSMIND_RUNTIME_SYNC_MS: 45000 (prod)
  BOSSMIND_AUTONOMY_MIN_SCORE: 90
```

**⚠️ Note:** PM2 config exists but Railway uses `node server.js` — PM2 is for local/manual use only. The `bossmind-autonomous-runtime` process is NOT running in Railway production.

---

## 2. SUPERVISOR SERVICE — RAILWAY PIPELINE

```
D:\BossMind\bossmind-supervisor-service
    │
    └── git push
            │
            ▼
    Railway Deploy:
        node supervisor.cjs
            │
            ▼
    ❌ CRASH — require('./autoFixEngine') → MODULE NOT FOUND
```

**This service is NOT functional in production.** The Railway deployment will crash on startup due to 17 missing `require()` modules. The `14-Railway-Production/supervisor/` staging folder is completely empty — no recovery plan staged.

---

## 3. RENDER PIPELINE (CONFIGURED, UNCONFIRMED)

```
RENDER_API_KEY → present in .env files
15-render-production/ → EMPTY (ZONE.md only)

Available scripts (not yet confirmed live):
- bossmind:render:env-bundle      → bossmind-render-env-bundle.mjs
- bossmind:render:env-sync        → bossmind-render-production-env-sync.mjs
- bossmind:render:deploy-validate → bossmind-render-deploy-validate.mjs
- bossmind:render:env-checklist   → bossmind-render-env-checklist.mjs
- bossmind:render:env-handsfree   → bossmind-render-env-handsfree.mjs
- resumora-render-self-heal.ps1   → 11-scripts/
```

**Status:** Render integration is scripted but no active Render service has been confirmed. The self-heal script exists for Resumora on Render — suggests historical Render use or planned migration.

---

## 4. GITHUB CI/CD

### Active Workflow: `.github/workflows/secret-scan.yml`
```yaml
Trigger: push to main/master, pull_request
Runner: ubuntu-latest
Steps:
  1. actions/checkout@v4
  2. Run bossmind-secret-scan.ps1 (PowerShell on Ubuntu)
     └── If missing: error "bossmind-secret-scan.ps1 missing"
```

**Coverage:** Secret leak detection only. No build validation, no test runner, no deployment workflow in CI.

**Missing CI Workflows:**
- ❌ Build verification
- ❌ Automated tests
- ❌ Dependency vulnerability scan
- ❌ Lighthouse / performance check
- ❌ Deploy status verification

---

## 5. ENVIRONMENT VARIABLE PIPELINE

```
.env.master.example (template)
    │
    └── → .env.master.local (gitignored, filled manually)
            │
            ├── bossmind-hub-env-bootstrap.mjs → generates bossmind-resumora/.env
            ├── bossmind-render-env-bundle.mjs → syncs to Render
            ├── bossmind-sync-hub-database-env.mjs → syncs to Neon hub
            └── bossmind-aws-storage-env-sync.mjs → syncs AWS vars
```

**Issue:** `ai-config.json` shows `"apiKey": ""` — DeepSeek API key is missing from the ai-config file even though DEEPSEEK_API_KEY is in .env. The config reads from a separate path.

---

## 6. DEPLOYMENT CONFLICTS DETECTED

| Conflict | Details | Risk |
|---|---|---|
| Dual deploy targets | Scripts mention both Railway AND Render for Resumora | RISKY — unclear which is canonical |
| PM2 vs Railway | ecosystem.config.cjs defines 2 apps but Railway only uses node server.js | RISKY — autonomous-runtime not in prod |
| Service IDs blank | service-registry.json has empty railway_service_id for all projects | BROKEN — automation can't target services |
| Supervisor crash | supervisor.cjs crashes on start | CRITICAL |
| 15-render-production EMPTY | Render staging folder has nothing | RISKY |
| 14-Railway-Production/supervisor EMPTY | Railway supervisor staging empty | RISKY |

---

## 7. BACKUP PIPELINE STATUS

| Backup Type | Status | Notes |
|---|---|---|
| Rolling 30d (master-admin) | ✅ ACTIVE | `.bossmind/backups/rolling-30d/` — last verified 2026-05-15 |
| Anti-leak snapshots | ✅ Present | bossmind-shared/anti-leak-snapshots/ |
| Locked snapshots | ✅ Present | bossmind-shared/locked-snapshots/resumora/ |
| Per-project snapshots | ✅ Present | bossmind-shared/snapshots/ (5 projects) |
| Daily backup script | ⚠️ MANUAL | npm run bossmind:backup:daily |
| Multi-project backup | ⚠️ MANUAL | npm run bossmind:backup:multi |
| Recovery simulation | ⚠️ MANUAL | npm run bossmind:backup:simulate |
| Cloud backup (S3) | ⚠️ UNKNOWN | AWS credentials present, backup-to-S3 not confirmed |
