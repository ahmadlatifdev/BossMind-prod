#!/usr/bin/env node
/**
 * BossMind AI Sync Orchestrator — production workflow controller.
 * DeepSeek (repair) → Claude/KIMI (review) → verification → approval gate → deploy (gated).
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { applyHubEnv } from "./lib/hub-env.mjs";
import { probeAiEnv } from "./lib/env-status.mjs";
import { generateRepairPatch } from "./lib/deepseek-client.mjs";
import { reviewDeepSeekOutput } from "./lib/review-client.mjs";
import {
  readProjectState,
  writeProjectState,
  recordAiDecision,
  recordReview,
  syncToNeon,
  hydrateFromNeon,
} from "./lib/shared-memory.mjs";
import { acquireFileLock, releaseFileLock, listActiveLocks } from "./lib/file-lock.mjs";
import { appendProofLog, readProofLogs, writeHubSummary } from "./lib/proof-log.mjs";
import {
  resolveProject,
  assertProjectIsolation,
  projectExists,
} from "./lib/project-guard.mjs";
import { evaluateApprovalGate, runProjectVerification } from "./lib/approval-gate.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = path.join(__dirname, "config.json");

function loadConfig() {
  return JSON.parse(fs.readFileSync(CONFIG_PATH, "utf8"));
}

function loadProjectsRegistry(cfg) {
  return JSON.parse(fs.readFileSync(cfg.projectsRegistry, "utf8"));
}

function paths(cfg) {
  return {
    logsRoot: path.join(cfg.syncRoot, "logs"),
    locksRoot: path.join(cfg.syncRoot, "locks"),
    sharedMemoryRoot: cfg.sharedMemoryRoot,
  };
}

const PRAE_BLOCKED_DEPLOY =
  process.env.PRAE_PRODUCTION_MUTATION === "BLOCKED" ||
  process.env.PRAE_AUTO_REPAIR === "DISABLED";

/** Parse `--unset VAR` flags (e.g. npm run ai-sync:env -- --unset ANTHROPIC_API_KEY). */
function parseCliOptions(argv) {
  const unsetKeys = [];
  const positional = [];
  for (let i = 0; i < argv.length; i++) {
    if (argv[i] === "--unset" && argv[i + 1]) {
      unsetKeys.push(argv[i + 1]);
      i++;
    } else if (!argv[i].startsWith("--")) {
      positional.push(argv[i]);
    }
  }
  return { unsetKeys, positional };
}

function applyUnsetKeys(env, unsetKeys) {
  for (const key of unsetKeys) {
    delete env[key];
    delete process.env[key];
  }
  return env;
}

async function runSyncForProject({ cfg, env, registry, projectId, taskDescription, dryRun = false }) {
  const p = paths(cfg);
  const project = resolveProject(registry, projectId);
  if (!project) {
    return { ok: false, error: `Unknown project: ${projectId}` };
  }
  if (!projectExists(project.root)) {
    return { ok: false, error: `Project root missing: ${project.root}` };
  }

  let state = readProjectState(p.sharedMemoryRoot, projectId);
  const neonHydrate = await hydrateFromNeon(env, projectId);
  if (neonHydrate.ok) {
    state.projectStatus = neonHydrate.state.projectStatus;
    state.errorMemory = neonHydrate.state.errorMemory || state.errorMemory;
    state.deploymentHistory = neonHydrate.state.deploymentHistory || state.deploymentHistory;
  }

  state.projectStatus = "sync_running";
  state.taskState = [{ taskKey: `sync:${Date.now()}`, status: "in_progress", task: taskDescription }];
  writeProjectState(p.sharedMemoryRoot, projectId, state);

  const isolationPre = assertProjectIsolation({ projectRoot: project.root, touchedPaths: [] });
  if (!isolationPre.ok) {
    appendProofLog(p.logsRoot, {
      projectName: projectId,
      aiEngine: "orchestrator",
      reviewResult: "blocked",
      deploymentResult: "blocked",
      remainingErrors: isolationPre.violations,
    });
    return { ok: false, blocked: true, reason: "isolation", isolationPre };
  }

  const deepseekResult = await generateRepairPatch({
    env,
    config: cfg,
    projectId,
    taskDescription,
    context: { projectRoot: project.root, dryRun },
  });

  if (!deepseekResult.ok) {
    state.projectStatus = "blocked";
    state.blockers = [`DEEPSEEK: ${deepseekResult.missingEnv || deepseekResult.error}`];
    writeProjectState(p.sharedMemoryRoot, projectId, state);
    appendProofLog(p.logsRoot, {
      projectName: projectId,
      aiEngine: "deepseek",
      reviewResult: "n/a",
      buildResult: "skipped",
      testResult: "skipped",
      deploymentResult: "blocked",
      remainingErrors: [deepseekResult.missingEnv || deepseekResult.error],
    });
    return { ok: false, blocked: true, deepseekResult };
  }

  const filesChanged = deepseekResult.patch?.files || [];
  const locks = [];
  for (const f of filesChanged.slice(0, 20)) {
    const rel = typeof f === "string" ? f : f.path || String(f);
    const lock = acquireFileLock({
      locksRoot: p.locksRoot,
      projectId,
      filePath: rel,
      owner: "bossmind-ai-sync",
    });
    locks.push({ rel, lock });
    if (lock.conflict) {
      appendProofLog(p.logsRoot, {
        projectName: projectId,
        aiEngine: "deepseek",
        filesChanged: filesChanged.map(String),
        reviewResult: "blocked",
        deploymentResult: "blocked",
        remainingErrors: [lock.message],
      });
      return { ok: false, blocked: true, reason: "file_lock_conflict", lock };
    }
  }

  const reviewResult = await reviewDeepSeekOutput({
    env,
    config: cfg,
    projectId,
    deepseekResult,
    taskDescription,
  });

  for (const { rel } of locks) {
    releaseFileLock({
      locksRoot: p.locksRoot,
      projectId,
      filePath: rel,
      owner: "bossmind-ai-sync",
    });
  }

  const isolationPost = assertProjectIsolation({
    projectRoot: project.root,
    touchedPaths: filesChanged.map((f) => (typeof f === "string" ? f : f.path || String(f))),
  });

  const verificationCfg = cfg.verification?.[projectId] || {};
  let verificationResult = { build: { ok: true, detail: "dry_run_skipped" }, lint: { ok: true, detail: "dry_run_skipped" } };
  if (!dryRun && (verificationCfg.build || verificationCfg.lint)) {
    verificationResult = runProjectVerification(project.root, verificationCfg);
  }

  const gate = evaluateApprovalGate({
    projectId,
    deepseekResult,
    reviewResult,
    isolationResult: isolationPost,
    verificationResult,
    filesChanged,
  });

  state = recordAiDecision(state, {
    engine: "deepseek",
    summary: deepseekResult.patch?.summary || "patch generated",
    files: filesChanged,
  });
  state = recordReview(state, {
    via: reviewResult.via,
    approved: reviewResult.review?.approved,
    decision: reviewResult.review?.decision,
    risk: reviewResult.review?.risk,
  });
  state.projectStatus = gate.approved ? "review_approved" : "review_rejected";
  state.blockers = gate.approved ? [] : [gate.blockedReason];
  writeProjectState(p.sharedMemoryRoot, projectId, state);

  await syncToNeon(env, projectId, {
    eventType: "ai_sync.completed",
    severity: gate.approved ? "info" : "warn",
    taskState: {
      taskKey: `sync:${projectId}`,
      status: gate.approved ? "approved" : "rejected",
      assignedAgent: "bossmind-ai-sync",
      payload: { taskDescription, dryRun },
    },
    deployment: {
      status: gate.deployAllowed && !PRAE_BLOCKED_DEPLOY ? "approved_staged" : "blocked",
      summary: gate.blockedReason || "approved pending deploy",
      metadata: { praeBlocked: PRAE_BLOCKED_DEPLOY, dryRun },
    },
  });

  const deployAllowed = gate.deployAllowed && !PRAE_BLOCKED_DEPLOY && !dryRun;
  const deploymentResult = deployAllowed
    ? "allowed_staged"
    : PRAE_BLOCKED_DEPLOY
      ? "blocked_prae"
      : dryRun
        ? "dry_run_no_deploy"
        : "blocked_gate";

  appendProofLog(p.logsRoot, {
    projectName: projectId,
    aiEngine: `deepseek+${reviewResult.via || "review"}`,
    filesChanged: filesChanged.map(String),
    commandsExecuted: deepseekResult.patch?.commands || [],
    buildResult: verificationResult.build?.detail,
    testResult: verificationResult.lint?.detail,
    reviewResult: reviewResult.review?.decision || reviewResult.error || "missing",
    deploymentResult,
    remainingErrors: state.blockers,
  });

  return {
    ok: gate.approved,
    projectId,
    deepseekResult,
    reviewResult,
    gate,
    verificationResult,
    deploymentResult,
    praeBlocked: PRAE_BLOCKED_DEPLOY,
  };
}

async function cmdEnvCheck(env) {
  return probeAiEnv(env);
}

async function cmdDryRun(cfg, env, registry, projectId) {
  return runSyncForProject({
    cfg,
    env,
    registry,
    projectId,
    taskDescription: "Dry-run health check: verify orchestration pipeline without applying patches.",
    dryRun: true,
  });
}

async function cmdLockTest(cfg, projectId = "resumora") {
  const p = paths(cfg);
  const testFile = "__ai_sync_lock_test__.txt";
  const a = acquireFileLock({
    locksRoot: p.locksRoot,
    projectId,
    filePath: testFile,
    owner: "test-owner-a",
  });
  const b = acquireFileLock({
    locksRoot: p.locksRoot,
    projectId,
    filePath: testFile,
    owner: "test-owner-b",
  });
  releaseFileLock({
    locksRoot: p.locksRoot,
    projectId,
    filePath: testFile,
    owner: "test-owner-a",
  });
  return {
    firstAcquired: a.acquired,
    secondConflict: b.conflict === true,
    activeLocks: listActiveLocks(p.locksRoot, projectId).length,
    pass: a.acquired && b.conflict === true,
  };
}

async function cmdLogTest(cfg, projectId = "hub") {
  const p = paths(cfg);
  const w = appendProofLog(p.logsRoot, {
    projectName: projectId,
    aiEngine: "verify",
    filesChanged: [],
    commandsExecuted: ["log-test"],
    buildResult: "n/a",
    testResult: "n/a",
    reviewResult: "test",
    deploymentResult: "none",
    remainingErrors: [],
  });
  const read = readProofLogs(p.logsRoot, projectId, 5);
  return { written: Boolean(w.path), readCount: read.length, pass: read.length > 0 };
}

async function cmdApprovalGateTest(cfg, env) {
  const gatePass = evaluateApprovalGate({
    projectId: "test",
    deepseekResult: { ok: true },
    reviewResult: { ok: true, review: { approved: true, decision: "approve", risk: "low" } },
    isolationResult: { ok: true },
    verificationResult: {
      build: { ok: true, detail: "exit=0" },
      lint: { ok: true, detail: "exit=0" },
    },
    filesChanged: ["lib/example.js"],
  });
  const gateFail = evaluateApprovalGate({
    projectId: "test",
    deepseekResult: { ok: true },
    reviewResult: { ok: true, review: { approved: false, decision: "reject", risk: "high" } },
    isolationResult: { ok: true },
    verificationResult: { build: { ok: true }, lint: { ok: true } },
    filesChanged: [],
  });
  return {
    passCase: gatePass.approved === true,
    failCase: gateFail.approved === false,
    pass: gatePass.approved && !gateFail.approved,
  };
}

async function main() {
  const { unsetKeys, positional } = parseCliOptions(process.argv.slice(2));
  const command = positional[0] || "help";
  // npm on Windows may pass `env-check ANTHROPIC_API_KEY` without `--unset`
  if (
    command === "env-check" &&
    positional[1] &&
    /^[A-Z][A-Z0-9_]*$/.test(positional[1]) &&
    !unsetKeys.includes(positional[1])
  ) {
    unsetKeys.push(positional[1]);
  }
  const cfg = loadConfig();
  const env = applyUnsetKeys(applyHubEnv(cfg.hubRoot), unsetKeys);
  const registry = loadProjectsRegistry(cfg);
  const p = paths(cfg);
  fs.mkdirSync(p.logsRoot, { recursive: true });
  fs.mkdirSync(p.locksRoot, { recursive: true });

  let result;

  switch (command) {
    case "env-check":
      result = await cmdEnvCheck(env);
      break;
    case "dry-run": {
      const projectId = positional[1] || cfg.activeProjectIds[0];
      result = await cmdDryRun(cfg, env, registry, projectId);
      break;
    }
    case "sync-all": {
      const outcomes = {};
      for (const id of cfg.activeProjectIds) {
        outcomes[id] = await runSyncForProject({
          cfg,
          env,
          registry,
          projectId: id,
          taskDescription: positional[1] || "Scheduled AI sync health pass.",
          dryRun: process.argv.includes("--dry-run"),
        });
      }
      result = outcomes;
      break;
    }
    case "lock-test":
      result = await cmdLockTest(cfg, positional[1] || "resumora");
      break;
    case "log-test":
      result = await cmdLogTest(cfg, positional[1] || "hub");
      break;
    case "approval-gate-test":
      result = await cmdApprovalGateTest(cfg, env);
      break;
    case "gate-eval": {
      const projectId = positional[1] || "resumora";
      result = await cmdDryRun(cfg, env, registry, projectId);
      break;
    }
    default:
      console.log(`BossMind AI Sync Orchestrator

Commands:
  env-check              Probe API keys (no secrets)
  dry-run [projectId]    Full pipeline without deploy
  sync-all [--dry-run]   Run all active projects
  lock-test [projectId]  File lock conflict test
  log-test [projectId]   Proof log write/read test
  approval-gate-test     Unit test approval gate logic

Flags (after -- via npm):
  --unset VAR            Omit VAR from this run (e.g. --unset ANTHROPIC_API_KEY)
`);
      process.exit(0);
  }

  const summary = {
    command,
    at: new Date().toISOString(),
    ...(unsetKeys.length ? { unsetKeys } : {}),
    env: await cmdEnvCheck(env),
    result,
  };
  writeHubSummary(p.sharedMemoryRoot, summary);
  console.log(JSON.stringify(summary, null, 2));

  const envOk = summary.env.deepseek.active && summary.env.review.active;
  const cmdOk =
    command === "env-check"
      ? envOk
      : command === "lock-test" || command === "log-test" || command === "approval-gate-test"
        ? result?.pass
        : result?.ok !== false;

  process.exit(envOk && cmdOk ? 0 : 1);
}

main().catch((e) => {
  console.error(e);
  process.exit(1);
});
