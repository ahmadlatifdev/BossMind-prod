/**
 * BossMind automatic memory / error / Sentry detector.
 * Read-only against Neon; scans env + filesystem signals. Never logs secrets.
 */
const fs = require("fs");
const path = require("path");
const { DATABASE_URL_ENV_KEYS, resolveDatabaseUrl, syncDatabaseEnvAliases } = require("./database-url");
const { ensureProjectEnv } = require("./ensure-project-env");
const { loadProjectEnv } = require("./load-project-env");
const {
  getSharedMemoryConfig,
  getSharedMemoryMode,
  verifyBossmindSharedMemory,
  redactDatabaseTarget,
  DEFAULT_SCHEMA,
} = require("./bossmind-shared-memory");

syncDatabaseEnvAliases();
ensureProjectEnv();
const envLoad = loadProjectEnv();
const loadedFiles = envLoad?.loadedFiles || [];
const ROOT = envLoad?.projectRoot || process.cwd();

const CANONICAL_SHARED_TABLES = [
  "task_state",
  "event_log",
  "error_memory",
  "missing_updates_log",
  "client_hub",
];

const SENTRY_ENV_KEYS = [
  "SENTRY_DSN",
  "NEXT_PUBLIC_SENTRY_DSN",
  "SENTRY_ORG",
  "SENTRY_PROJECT",
  "SENTRY_AUTH_TOKEN",
];

const BOSSMIND_PROJECTS = [
  "resumora",
  "elegancyart",
  "ai-video-generator",
  "tiktok-ai",
  "global-stock",
  "bossmind-core",
  "bossmind-shared",
];

function envKeyPresent(key) {
  const v = process.env[key];
  return v != null && String(v).trim() !== "";
}

function redactHostFromUrl() {
  const t = redactDatabaseTarget();
  return t.host || null;
}

function detectSentryPackage() {
  try {
    const pkg = require("../../package.json");
    return Boolean(
      pkg.dependencies?.["@sentry/nextjs"] ||
        pkg.dependencies?.["@sentry/node"] ||
        pkg.dependencies?.["@sentry/react"]
    );
  } catch {
    return false;
  }
}

function detectSentryConfigFiles() {
  const names = [
    "sentry.client.config.js",
    "sentry.server.config.js",
    "sentry.edge.config.js",
    "sentry.properties",
  ];
  return Object.fromEntries(
    names.map((n) => [n, fs.existsSync(path.join(ROOT, n))])
  );
}

function detectSentryInitInRepo() {
  const targets = [
    "sentry.client.config.js",
    "sentry.server.config.js",
    "lib/observability/sentry-api.js",
    "pages/_app.js",
  ];
  for (const rel of targets) {
    const abs = path.join(ROOT, rel);
    if (!fs.existsSync(abs)) continue;
    try {
      const text = fs.readFileSync(abs, "utf8");
      if (/Sentry\.init|@sentry\/nextjs/.test(text)) return { file: rel, found: true };
    } catch {
      /* ignore */
    }
  }
  return { file: null, found: false };
}

function detectLocalMemorySignals() {
  const signals = [];
  const checks = [
    ["orchestration-json", path.join(ROOT, "..", "13-shared-memory")],
    ["governance-ledger", path.join(ROOT, ".bossmind", "governance")],
    ["bossmind-shared-logs", path.join(ROOT, "..", "bossmind-shared", "logs")],
  ];
  for (const [id, p] of checks) {
    if (fs.existsSync(p)) signals.push(id);
  }
  return signals;
}

function detectCodeIntegrations() {
  const integrations = {
    neon_memory_dual: false,
    shared_error_module: false,
    client_error_report: false,
    runtime_log_dual: false,
    sentry_api_mirror: false,
    sentry_ingest_mirror: false,
    health_endpoints: false,
  };
  const files = {
    neon: path.join(ROOT, "lib/shared/neon-memory.js"),
    err: path.join(ROOT, "lib/shared/bossmind-shared-error-memory.js"),
    report: path.join(ROOT, "pages/api/client/error-report.js"),
    runtime: path.join(ROOT, "pages/api/client/runtime-log.js"),
    sentryApi: path.join(ROOT, "lib/observability/sentry-api.js"),
    ingest: path.join(ROOT, "pages/api/orchestration/sentry-ingest.js"),
    memHealth: path.join(ROOT, "pages/api/runtime/bossmind-memory-health.js"),
  };
  try {
    if (fs.existsSync(files.neon)) {
      const t = fs.readFileSync(files.neon, "utf8");
      integrations.neon_memory_dual = /bossmind-shared-memory|saveSharedEvent|dual/.test(t);
    }
    integrations.shared_error_module = fs.existsSync(files.err);
    integrations.client_error_report = fs.existsSync(files.report);
    if (fs.existsSync(files.runtime)) {
      const t = fs.readFileSync(files.runtime, "utf8");
      integrations.runtime_log_dual = /saveSharedEvent|bossmind-shared/.test(t);
    }
    if (fs.existsSync(files.sentryApi)) {
      const t = fs.readFileSync(files.sentryApi, "utf8");
      integrations.sentry_api_mirror = /recordSharedError|recordApiError/.test(t);
    }
    if (fs.existsSync(files.ingest)) {
      const t = fs.readFileSync(files.ingest, "utf8");
      integrations.sentry_ingest_mirror = /recordSentryMirror|bossmind-shared-error/.test(t);
    }
    integrations.health_endpoints = fs.existsSync(files.memHealth);
  } catch {
    /* ignore */
  }
  return integrations;
}

function computeAutomationRates({ mode, schemaReady, integrations, sentryActive, sentryMirrorReady }) {
  const memoryPaths = 5;
  const memoryWired = [
    integrations.neon_memory_dual,
    integrations.runtime_log_dual,
    mode === "dual" || mode === "shared",
    schemaReady,
    integrations.health_endpoints,
  ].filter(Boolean).length;

  const errorPaths = 6;
  const errorWired = [
    integrations.shared_error_module,
    integrations.client_error_report,
    integrations.sentry_api_mirror,
    integrations.sentry_ingest_mirror,
    mode === "dual" || mode === "shared",
    schemaReady,
  ].filter(Boolean).length;

  const sentryAreas = 4;
  const sentryWired = [
    sentryActive,
    integrations.sentry_api_mirror,
    integrations.sentry_ingest_mirror,
    detectSentryConfigFiles()["sentry.server.config.js"],
  ].filter(Boolean).length;

  return {
    shared_memory: Math.round((memoryWired / memoryPaths) * 100),
    shared_error_memory: Math.round((errorWired / errorPaths) * 100),
    sentry: Math.round((sentryWired / sentryAreas) * 100),
  };
}

function resolveActiveMemoryMode({ mode, schemaReady, localSignals, publicInUse }) {
  const usingShared = mode === "shared" && schemaReady;
  const dual = mode === "dual" && schemaReady;
  const usingPublic = publicInUse && (mode === "off" || dual);
  const usingLocal = localSignals.length > 0;

  if (usingShared && !usingPublic && !usingLocal) return "bossmind_shared";
  if (usingShared && (usingPublic || usingLocal)) return "split";
  if (dual && (usingPublic || usingLocal)) return "split";
  if (usingPublic && usingLocal) return "split";
  if (usingPublic) return "public";
  if (usingLocal) return "local";
  if (mode === "off" && !schemaReady) return "none";
  return "none";
}

async function detectBossmindMemory() {
  const resolved = resolveDatabaseUrl();
  const connection = redactDatabaseTarget();
  const verify = await verifyBossmindSharedMemory();
  const mode = getSharedMemoryMode();
  const config = getSharedMemoryConfig();

  const schemas = {
    bossmind_shared: Boolean(verify.schemaExists),
    bossmind_memory: false,
    public: connection.configured,
  };

  if (connection.configured) {
    try {
      const { getSqlClient, getSharedMemorySchema } = require("./bossmind-shared-memory");
      const sql = getSqlClient();
      if (sql) {
        const rows = await sql.query(
          `SELECT schema_name FROM information_schema.schemata WHERE schema_name = 'bossmind_memory' LIMIT 1`
        );
        schemas.bossmind_memory = Boolean(rows?.[0]?.schema_name);
      }
    } catch {
      /* ignore */
    }
  }

  const schemaName = DEFAULT_SCHEMA;
  const tables = {};
  for (const name of CANONICAL_SHARED_TABLES) {
    tables[`${schemaName}.${name}`] = Boolean(verify.tables?.[name]);
  }

  const sentryEnv = Object.fromEntries(SENTRY_ENV_KEYS.map((k) => [k, envKeyPresent(k)]));
  const sentryDsn = envKeyPresent("SENTRY_DSN") || envKeyPresent("NEXT_PUBLIC_SENTRY_DSN");
  const sentryPackage = detectSentryPackage();
  const sentryConfigFiles = detectSentryConfigFiles();
  const sentryInit = detectSentryInitInRepo();
  const sentry_active = sentryDsn && sentryPackage && sentryConfigFiles["sentry.server.config.js"];

  const integrations = detectCodeIntegrations();
  const localSignals = detectLocalMemorySignals();
  const schemaReady = verify.allCanonicalPresent;
  const publicInUse = fs.existsSync(path.join(ROOT, "lib/shared/neon-memory.js"));

  const active_memory_mode = resolveActiveMemoryMode({
    mode,
    schemaReady,
    localSignals,
    publicInUse,
  });

  const writesEnabled = mode === "dual" || mode === "shared";
  const shared_memory_active = writesEnabled && schemaReady && active_memory_mode !== "none";
  const shared_error_memory_active =
    writesEnabled && schemaReady && integrations.shared_error_module;
  const sentry_to_neon_active =
    integrations.sentry_ingest_mirror &&
    integrations.sentry_api_mirror &&
    (writesEnabled || sentry_active);

  const automation_rate = computeAutomationRates({
    mode,
    schemaReady,
    integrations,
    sentryActive: sentry_active,
    sentryMirrorReady: sentry_to_neon_active,
  });

  const gaps = [];
  if (!connection.configured) gaps.push("database_url_missing");
  if (!schemas.bossmind_shared) gaps.push("bossmind_shared_schema_missing");
  if (!schemaReady) gaps.push("bossmind_shared_tables_incomplete");
  if (mode === "off") gaps.push("bossmind_memory_mode_off");
  if (active_memory_mode === "public" || active_memory_mode === "split")
    gaps.push("still_using_public_or_split_memory");
  if (localSignals.length) gaps.push("local_json_memory_signals_present");
  if (!integrations.client_error_report) gaps.push("client_error_report_endpoint_missing");
  if (!sentryDsn) gaps.push("sentry_dsn_missing");
  if (!sentryConfigFiles["sentry.server.config.js"]) gaps.push("sentry_server_config_missing");
  for (const k of SENTRY_ENV_KEYS) {
    if (!sentryEnv[k]) gaps.push(`env_missing:${k}`);
  }
  if (!shared_memory_active) gaps.push("shared_memory_not_active");
  if (!shared_error_memory_active) gaps.push("shared_error_memory_not_active");
  if (!sentry_to_neon_active) gaps.push("sentry_to_neon_mirror_not_active");

  const missingSentryEnv = SENTRY_ENV_KEYS.filter((k) => !sentryEnv[k]);

  const memory_layers = {
    bossmind_shared: {
      present: schemas.bossmind_shared,
      canonical_ready: schemaReady,
      role: "target_protected_source_of_truth",
    },
    public_memory: {
      present: schemas.public,
      active: publicInUse && (mode === "off" || mode === "dual" || active_memory_mode === "public"),
      role: "legacy_active_runtime_until_shared_proven",
    },
    bossmind_memory: {
      present: schemas.bossmind_memory,
      role: "legacy_orchestration_schema_read_only",
    },
    local_json: {
      present: localSignals.length > 0,
      signals: localSignals,
      role: "offline_orchestration_artifacts",
    },
  };

  const duplicate_memory_detected =
    memory_layers.public_memory.active &&
    (memory_layers.bossmind_memory.present ||
      memory_layers.local_json.present ||
      !memory_layers.bossmind_shared.present);

  const memory_deprecation = {
    duplicate_memory_detected,
    active_memory_mode,
    safe_action: !schemas.bossmind_shared
      ? "align_neon_url_to_branch_with_bossmind_shared_or_run_idempotent_ddl_on_production_endpoint"
      : !schemaReady
        ? "complete_bossmind_shared_canonical_tables_on_production_endpoint"
        : mode === "off"
          ? "enable_bossmind_memory_mode_dual_after_schema_on_production_connection"
          : active_memory_mode === "split"
            ? "run_proof_writes_then_consider_shared_mode"
            : "monitor_only",
    do_not_delete: ["public.*", "bossmind_memory.*", "local_json_memory", "bossmind_shared.*"],
  };

  return {
    database: {
      configured: connection.configured,
      source: resolved.source,
      host_redacted: connection.host,
      database: connection.database,
      checked_keys: DATABASE_URL_ENV_KEYS,
      project_root: ROOT,
      loaded_env_files: loadedFiles,
      process_cwd: process.cwd(),
      cwd_matches_project_root: path.resolve(process.cwd()) === path.resolve(ROOT),
    },
    schemas: {
      ...schemas,
      observed: verify.observedSchemas || [],
    },
    tables,
    active_memory_mode,
    shared_memory_active,
    shared_error_memory_active,
    sentry_active,
    sentry_to_neon_active,
    automation_rate,
    gaps: [...new Set(gaps)],
    projects: BOSSMIND_PROJECTS,
    memory_mode: mode,
    memory_schema: config.schema,
    memory_schema_write_target: config.schema,
    memory_schema_verify_target: schemaName,
    local_memory_signals: localSignals,
    code_integrations: integrations,
    sentry: {
      package_installed: sentryPackage,
      config_files: sentryConfigFiles,
      init_detected: sentryInit,
      env_present: sentryEnv,
      missing_env_names: missingSentryEnv,
    },
    proof: {
      schema_status: verify.status,
      all_canonical_tables: schemaReady,
    },
    memory_layers,
    memory_deprecation,
  };
}

module.exports = {
  detectBossmindMemory,
  BOSSMIND_PROJECTS,
  CANONICAL_SHARED_TABLES,
};
