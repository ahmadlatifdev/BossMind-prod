#!/usr/bin/env node
/**
 * BossMind Permanent Autonomous Execution Engine
 *
 * CORE RULE: NO DIRECT EXECUTION — every request passes through 10 mandatory phases.
 *
 * Usage:
 *   node bossmind-autonomous-execution-engine.mjs --request "Fix Stripe webhook activation"
 *   node bossmind-autonomous-execution-engine.mjs --request-file ./request.txt
 *   node bossmind-autonomous-execution-engine.mjs --request "..." --execute  (explicit approval only)
 *
 * Outputs:
 *   13-shared-memory/TASK_CLASSIFICATION_REPORT.json
 *   13-shared-memory/RISK_SCORE.json
 *   13-shared-memory/IMPACT_REPORT.md
 *   13-shared-memory/SAFE_EXECUTION_PLAN.md
 *   13-shared-memory/bossmind-autonomous-execution-{runId}.json
 *   08-backups/{runId}/SNAPSHOT_MANIFEST.json
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";
import { readJsonSafe, writeJson, writeText, runId as makeRunId, nowIso } from "./lib/utils.mjs";
import {
  phase1Classify,
  phase2Impact,
  phase3Snapshot,
  phase4ToolRouting,
  phase5ExecutionEngine,
  phase6ValidationGates,
  phase7SelfHealing,
  phase8DesignLock,
  phase9AutonomyScore,
  phase10HumanGate,
} from "./lib/phases.mjs";

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const CONFIG_PATH = path.join(__dirname, "config.json");

function parseArgs(argv) {
  const args = { request: "", requestFile: null, execute: false, dryRun: true };
  for (let i = 2; i < argv.length; i++) {
    if (argv[i] === "--request" && argv[i + 1]) {
      args.request = argv[++i];
    } else if (argv[i] === "--request-file" && argv[i + 1]) {
      args.requestFile = argv[++i];
    } else if (argv[i] === "--execute") {
      args.execute = true;
      args.dryRun = false;
    } else if (argv[i] === "--help" || argv[i] === "-h") {
      args.help = true;
    }
  }
  return args;
}

function loadRequest(args) {
  if (args.requestFile && fs.existsSync(args.requestFile)) {
    return fs.readFileSync(args.requestFile, "utf8").trim();
  }
  return args.request || process.env.BOSSMIND_EXECUTION_REQUEST || "";
}

function appendTaskState(config, runIdValue, status, detail) {
  const logPath = path.join(config.automationRoot, "../logs/task-state-log.jsonl");
  const record = {
    _type: "task_state",
    _written: nowIso(),
    project_id: "bossmind-hub",
    task_name: "autonomous_execution_engine",
    task_id: `bossmind-hub.autonomous_execution_engine.${runIdValue}`,
    status,
    detail,
    metadata: { runId: runIdValue, engine: "bossmind-autonomous-execution/v1" },
  };
  try {
    fs.mkdirSync(path.dirname(logPath), { recursive: true });
    fs.appendFileSync(logPath, `${JSON.stringify(record)}\n`, "utf8");
  } catch {
    /* non-fatal */
  }
}

async function main() {
  const args = parseArgs(process.argv);
  if (args.help) {
    console.log(`BossMind Autonomous Execution Engine — NO DIRECT EXECUTION

  node bossmind-autonomous-execution-engine.mjs --request "your task description"
  node bossmind-autonomous-execution-engine.mjs --request-file task.txt [--execute]
`);
    process.exit(0);
  }

  const config = readJsonSafe(CONFIG_PATH);
  if (!config) {
    console.error(JSON.stringify({ ok: false, error: "config_missing", path: CONFIG_PATH }));
    process.exit(1);
  }

  const requestText = loadRequest(args);
  if (!requestText) {
    console.error(JSON.stringify({ ok: false, error: "missing_request", hint: "Use --request or --request-file" }));
    process.exit(1);
  }

  const runIdValue = makeRunId();
  const projectsConfig = readJsonSafe(path.join(config.automationRoot, "projects.json"));
  const projects = projectsConfig?.projects || [];

  appendTaskState(config, runIdValue, "running", "phase_1_classification");

  // PHASE 1 — Classification
  const classification = phase1Classify(requestText, config, projects);
  writeJson(path.join(config.sharedMemoryRoot, "TASK_CLASSIFICATION_REPORT.json"), classification);

  // PHASE 2 — Impact analysis
  appendTaskState(config, runIdValue, "running", "phase_2_impact");
  const { impacts, risk, impactMd, planMd } = phase2Impact(classification, config, projects);
  writeJson(path.join(config.sharedMemoryRoot, "RISK_SCORE.json"), risk);
  writeText(path.join(config.sharedMemoryRoot, "IMPACT_REPORT.md"), impactMd);
  writeText(path.join(config.sharedMemoryRoot, "SAFE_EXECUTION_PLAN.md"), planMd);

  // PHASE 3 — Snapshot + protection
  appendTaskState(config, runIdValue, "running", "phase_3_snapshot");
  const snapshot = risk.snapshotRequired
    ? phase3Snapshot(classification, impacts, config, runIdValue)
    : { backupDir: null, manifest: null, fileCount: 0, skipped: true };

  // PHASE 4 — Tool routing
  const toolRouting = phase4ToolRouting(classification, config);

  // PHASE 5 — Execution engine (dry-run by default)
  appendTaskState(config, runIdValue, "running", "phase_5_execution");
  const execution = phase5ExecutionEngine(config, classification, { dryRun: !args.execute });

  // PHASE 6 — Validation gates
  const validationGates = phase6ValidationGates(config, execution.results);

  // PHASE 7 — Self-healing
  const selfHealing = phase7SelfHealing(config, classification);

  // PHASE 8 — Design lock
  const designLock = phase8DesignLock(config);

  // PHASE 9 — Autonomy score
  const autonomyScore = phase9AutonomyScore(config, validationGates, designLock);

  // PHASE 10 — Human gate
  const humanGate = phase10HumanGate(risk, classification);

  const complete =
    validationGates.overall !== "BROKEN" &&
    (!risk.humanApprovalRequired || args.execute) &&
    execution.results.every((r) => r.ok);

  const finalReport = {
    schema: "bossmind-autonomous-execution-cycle/v1",
    runId: runIdValue,
    timestamp: nowIso(),
    coreRule: config.coreRule,
    requestHash: classification.requestHash,
    requestSummary: classification.requestSummary,
    phases: {
      classification: { status: "ACTIVE", report: "TASK_CLASSIFICATION_REPORT.json" },
      impactAnalysis: { status: "ACTIVE", reports: ["IMPACT_REPORT.md", "RISK_SCORE.json", "SAFE_EXECUTION_PLAN.md"] },
      snapshot: {
        status: snapshot.skipped ? "SKIPPED" : snapshot.fileCount > 0 ? "ACTIVE" : "PARTIAL",
        backupDir: snapshot.backupDir,
        fileCount: snapshot.fileCount,
      },
      toolRouting: { status: "ACTIVE", tools: toolRouting.routing.map((r) => r.tool) },
      execution: {
        status: execution.directExecutionBlocked ? "DRY_RUN" : complete ? "ACTIVE" : "PARTIAL",
        dryRun: execution.dryRun,
        steps: execution.steps,
      },
      validationGates: { status: validationGates.overall, gates: validationGates.gates },
      selfHealing: { status: selfHealing.status },
      designLock: { status: designLock.status, locked: designLock.locked },
      autonomyScore: { status: autonomyScore.status, scores: autonomyScore.scores, meetsTarget: autonomyScore.meetsTarget },
      humanGate: { humanRequired: humanGate.humanRequired },
    },
    classification,
    risk,
    toolRouting,
    execution,
    validationGates,
    selfHealing,
    designLock,
    autonomyScore,
    humanGate,
    completion: {
      complete: complete && autonomyScore.meetsTarget,
      validated: validationGates.overall !== "BROKEN",
      deployed: args.execute && execution.results.some((r) => r.step === "production_rollout"),
      verified: execution.results.some((r) => r.step === "health_check_verification" && r.ok),
      monitored: true,
      recoverable: snapshot.fileCount > 0 || Boolean(snapshot.skipped),
      regressionSafe: designLock.status !== "BROKEN",
      productionStable: validationGates.gates.deployment_healthy?.status === "ACTIVE",
      note: complete
        ? "Cycle complete per validation gates"
        : "NOT COMPLETE — deploy, verify, or human approval still required",
    },
  };

  const reportPath = path.join(config.sharedMemoryRoot, `bossmind-autonomous-execution-${runIdValue}.json`);
  writeJson(reportPath, finalReport);

  appendTaskState(
    config,
    runIdValue,
    complete ? "done" : "escalated",
    finalReport.completion.note
  );

  console.log(JSON.stringify(finalReport, null, 2));

  if (process.env.BOSSMIND_EXECUTION_STRICT === "1" && !complete) {
    process.exit(1);
  }
}

main().catch((err) => {
  console.error(JSON.stringify({ ok: false, error: err.message, stack: err.stack?.split("\n").slice(0, 5) }));
  process.exit(1);
});
