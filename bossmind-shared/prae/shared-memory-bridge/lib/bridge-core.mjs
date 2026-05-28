import fs from "fs";
import path from "path";
import { appendJsonl, nowIso, projectExists, readJsonSafe, sha256 } from "./utils.mjs";

const BLOCKED_ACTIONS = [
  "force_deploy",
  "force-deployment",
  "baseline_reset",
  "baseline-reset",
  "baseline_restore",
  "baseline_seal",
  "unsafe_repair_loop",
  "direct_production_mutation",
  "unauthorized_orchestration_override",
  "automatic_ui_overwrite",
  "auto_repair",
  "auto-repair",
];

export function validateGovernanceInheritance(config, masterEnv) {
  const expected = config.governanceInheritance || {};
  const inherited = [];
  for (const [key, expectedValue] of Object.entries(expected)) {
    const actual = masterEnv.keys[key] || null;
    inherited.push({
      project_scope: "all_registered",
      key,
      expected: expectedValue,
      actual: actual || null,
      inherited: actual === expectedValue,
      status: actual === expectedValue ? "ACTIVE" : "PARTIAL",
    });
  }
  const allOk = inherited.every((i) => i.inherited);
  return { ok: allOk, inherited, status: allOk ? "ACTIVE" : "PARTIAL" };
}

export function applyProjectGovernance(config) {
  const projects = [];
  for (const p of config.projects || []) {
    const exists = projectExists(p.root);
    projects.push({
      project_id: p.project_id,
      root: p.root,
      exists_on_disk: exists,
      governance: { ...config.governanceInheritance },
      inheritance_status: exists ? "ACTIVE" : "BROKEN",
    });
  }
  return projects;
}

export function validateAuthorityFiles(config) {
  const praeRoot = config.praeRoot;
  const results = [];
  for (const rel of config.authorityFiles || []) {
    const full = path.join(praeRoot, rel);
    const data = readJsonSafe(full);
    results.push({
      file: rel,
      exists: fs.existsSync(full),
      status: data?.status || (fs.existsSync(full) ? "UNKNOWN" : "MISSING"),
      system: data?.system || null,
    });
  }
  const ok = results.every((r) => r.exists);
  return { ok, results, status: ok ? "ACTIVE" : "BROKEN" };
}

export function checkSecurityBlocks(requestText = "") {
  const text = String(requestText || "").toLowerCase();
  const triggered = BLOCKED_ACTIONS.filter((a) => text.includes(a.replace(/_/g, " ")) || text.includes(a));
  return {
    ok: triggered.length === 0,
    blockedActionsEnforced: BLOCKED_ACTIONS,
    triggered,
    status: triggered.length ? "BLOCKED" : "ACTIVE",
  };
}

export function appendGlobalLedger(config, eventType, payload = {}) {
  const ledgerPath = path.join(config.globalLedgerRoot, "governance-events.jsonl");
  const record = {
    schema: "bossmind-prae-global-ledger-event/v1",
    timestamp_utc: nowIso(),
    event: eventType,
    checksum: null,
    secret_values_exposed: false,
    production_mutation: "NONE",
    auto_repair: "DISABLED",
    ...payload,
  };
  const lineChecksum = appendJsonl(ledgerPath, record);
  record.checksum = lineChecksum;

  const runtimeLog = path.join(config.praeRoot, "runtime-ledger/prae-events.log");
  appendJsonl(runtimeLog, {
    timestamp_utc: record.timestamp_utc,
    event: eventType,
    bridge: true,
    checksum: lineChecksum,
    result: payload.result || "RECORDED",
  });

  const sharedMem = path.join(config.praeRoot, "../automation/logs/shared_memory.jsonl");
  appendJsonl(sharedMem, {
    _type: "prae_bridge_sync",
    _written: record.timestamp_utc,
    project_id: "bossmind-hub",
    event: eventType,
    checksum: lineChecksum,
    governance_mode: config.governanceInheritance?.PRAE_GOVERNANCE_MODE || "LOCKED",
  });

  return record;
}

export function propagateDriftAlert(config, driftEvent) {
  const alerts = [];
  for (const p of config.projects || []) {
    if (!projectExists(p.root)) continue;
    const alert = {
      timestamp_utc: nowIso(),
      project_id: p.project_id,
      alert_type: "PRAE_DRIFT_DETECTED",
      auto_repair: "DISABLED",
      production_mutation: "BLOCKED",
      ui_overwrite: "BLOCKED",
      drift: driftEvent,
    };
    alerts.push(alert);
    appendJsonl(path.join(config.globalLedgerRoot, "drift-alerts.jsonl"), alert);
  }
  appendGlobalLedger(config, "PRAE_DRIFT_PROPAGATED", {
    result: "ALERT_ONLY",
    drift: driftEvent,
    propagated_projects: alerts.map((a) => a.project_id),
  });
  return { ok: true, alerts, status: "ACTIVE", autoRepair: false };
}

export function validateDeploymentAuthority(config, probes = {}) {
  const deploymentAuth = readJsonSafe(
    path.join(config.praeRoot, "deployment-validation/prae-deployment-authority.json")
  );
  const gates = (config.deploymentGates || []).map((gate) => {
    let status = "PARTIAL";
    if (gate === "checksum_validation") status = probes.checksumOk ? "ACTIVE" : "PARTIAL";
    if (gate === "runtime_validation") status = probes.runtimeOk ? "ACTIVE" : "PARTIAL";
    if (gate === "webhook_validation") status = probes.webhookOk ? "ACTIVE" : "PARTIAL";
    if (gate === "ui_lock_validation") status = probes.uiLockOk ? "ACTIVE" : "PARTIAL";
    if (gate === "prae_governance_validation") status = probes.governanceOk ? "ACTIVE" : "PARTIAL";
    return { gate, status, directDeploymentAllowed: false };
  });
  const allActive = gates.every((g) => g.status === "ACTIVE");
  return {
    ok: allActive,
    deployment_mode: deploymentAuth?.deployment_mode || "STAGED",
    deployment_authority: deploymentAuth?.deployment_authority || "PRAE_ONLY",
    blocked_actions: deploymentAuth?.blocked_actions || [],
    gates,
    directDeploymentBlocked: true,
    status: allActive ? "ACTIVE" : "PARTIAL",
  };
}

export function updateRuntimeLedger(config, snapshot) {
  const ledgerPath = path.join(config.praeRoot, "runtime-ledger/prae-runtime-ledger.json");
  const existing = readJsonSafe(ledgerPath) || {};
  const merged = {
    ...existing,
    system: "PRAE",
    status: snapshot.overallStatus || "ACTIVE",
    governance_mode: config.governanceInheritance?.PRAE_GOVERNANCE_MODE || "LOCKED",
    deployment_validation: snapshot.deploymentValidation || "ACTIVE",
    drift_detection: snapshot.driftDetection || "ACTIVE",
    checksum_enforcement: snapshot.checksumEnforcement || "ACTIVE",
    bridge_sync: "ACTIVE",
    updated_utc: nowIso(),
    bridge_checksum: sha256(JSON.stringify(snapshot)),
  };
  fs.writeFileSync(ledgerPath, JSON.stringify(merged, null, 2), "utf8");
  return merged;
}

export function storeDeploymentProof(config, proof) {
  const dir = path.join(config.globalLedgerRoot, "deployment-proof");
  fs.mkdirSync(dir, { recursive: true });
  const name = `proof-${nowIso().replace(/[:.]/g, "-")}.json`;
  const filePath = path.join(dir, name);
  const record = {
    schema: "bossmind-prae-deployment-proof/v1",
    timestamp_utc: nowIso(),
    checksum: sha256(JSON.stringify(proof)),
    secret_values_exposed: false,
    ...proof,
  };
  fs.writeFileSync(filePath, JSON.stringify(record, null, 2), "utf8");
  appendGlobalLedger(config, "PRAE_DEPLOYMENT_PROOF_STORED", {
    result: "SUCCESS",
    proof_file: name,
    checksum: record.checksum,
  });
  return record;
}

export function storeRepairSimulation(config, simulation) {
  const dir = path.join(config.globalLedgerRoot, "repair-simulation");
  fs.mkdirSync(dir, { recursive: true });
  const record = {
    schema: "bossmind-prae-repair-simulation/v1",
    timestamp_utc: nowIso(),
    mode: "SIMULATION_ONLY",
    production_mutation: "NONE",
    auto_repair: "DISABLED",
    ...simulation,
  };
  appendJsonl(path.join(dir, "history.jsonl"), record);
  appendGlobalLedger(config, "PRAE_REPAIR_SIMULATION", { result: "SIMULATED", simulation_id: record.timestamp_utc });
  return record;
}
