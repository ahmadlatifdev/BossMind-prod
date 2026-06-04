import fs from "fs";
import path from "path";
import crypto from "crypto";
import pg from "pg";

function nowIso() {
  return new Date().toISOString();
}

function statePath(sharedMemoryRoot, projectId) {
  return path.join(sharedMemoryRoot, `ai-sync-state-${projectId}.json`);
}

export function readProjectState(sharedMemoryRoot, projectId) {
  const p = statePath(sharedMemoryRoot, projectId);
  if (!fs.existsSync(p)) {
    return {
      projectId,
      updatedAt: null,
      projectStatus: "unknown",
      taskState: [],
      errorMemory: [],
      deploymentHistory: [],
      aiDecisions: [],
      reviewHistory: [],
      blockers: [],
    };
  }
  return JSON.parse(fs.readFileSync(p, "utf8"));
}

export function writeProjectState(sharedMemoryRoot, projectId, state) {
  const p = statePath(sharedMemoryRoot, projectId);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  state.updatedAt = nowIso();
  state.projectId = projectId;
  fs.writeFileSync(p, JSON.stringify(state, null, 2), "utf8");
  return p;
}

export function recordAiDecision(state, decision) {
  state.aiDecisions = state.aiDecisions || [];
  state.aiDecisions.unshift({ ...decision, at: nowIso() });
  state.aiDecisions = state.aiDecisions.slice(0, 100);
  return state;
}

export function recordReview(state, reviewRecord) {
  state.reviewHistory = state.reviewHistory || [];
  state.reviewHistory.unshift({ ...reviewRecord, at: nowIso() });
  state.reviewHistory = state.reviewHistory.slice(0, 100);
  return state;
}

function dbUrl(env) {
  return env.NEON_DATABASE_URL || env.DATABASE_URL || "";
}

export async function syncToNeon(env, projectId, payload) {
  const url = dbUrl(env);
  if (!url) {
    return { ok: false, reason: "NEON_DATABASE_URL or DATABASE_URL missing" };
  }

  const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  try {
    await client.connect();

    const fp = crypto
      .createHash("sha256")
      .update(`${projectId}|ai_sync|${payload.eventType}|${JSON.stringify(payload).slice(0, 500)}`)
      .digest("hex");

    await client.query(
      `INSERT INTO event_log (project_key, event_type, severity, source, event_key, payload)
       VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
      [
        projectId,
        payload.eventType || "ai_sync.event",
        payload.severity || "info",
        "bossmind-ai-sync",
        payload.eventKey || `ai_sync:${Date.now()}`,
        JSON.stringify(payload),
      ]
    );

    if (payload.errorMemory) {
      const em = payload.errorMemory;
      await client.query(
        `INSERT INTO error_memory
         (fingerprint, project_key, error_type, error_message, stack_excerpt, root_cause, fix_pattern, times_seen, last_seen_at, updated_at)
         VALUES ($1, $2, $3, $4, $5, $6, $7, 1, NOW(), NOW())
         ON CONFLICT (fingerprint) DO UPDATE SET
           times_seen = error_memory.times_seen + 1,
           fix_pattern = COALESCE(EXCLUDED.fix_pattern, error_memory.fix_pattern),
           last_seen_at = NOW(),
           updated_at = NOW()`,
        [
          fp,
          projectId,
          em.errorType || "ai_sync",
          em.errorMessage || "ai_sync_record",
          em.stackExcerpt || "",
          em.rootCause || "",
          em.fixPattern || "",
        ]
      );
    }

    if (payload.taskState) {
      const ts = payload.taskState;
      await client.query(
        `INSERT INTO task_state (project_key, task_key, status, assigned_agent, payload, updated_at)
         VALUES ($1, $2, $3, $4, $5::jsonb, NOW())
         ON CONFLICT (project_key, task_key) DO UPDATE SET
           status = EXCLUDED.status,
           assigned_agent = EXCLUDED.assigned_agent,
           payload = EXCLUDED.payload,
           updated_at = NOW()`,
        [
          projectId,
          ts.taskKey || `ai_sync:${Date.now()}`,
          ts.status || "completed",
          ts.assignedAgent || "bossmind-ai-sync",
          JSON.stringify(ts.payload || {}),
        ]
      );
    }

    if (payload.deployment) {
      const d = payload.deployment;
      await client.query(
        `INSERT INTO deployment_history (project_key, commit_hash, environment, status, summary, metadata)
         VALUES ($1, $2, $3, $4, $5, $6::jsonb)`,
        [
          projectId,
          d.commitHash || null,
          d.environment || "production",
          d.status || "blocked",
          d.summary || "ai-sync gate",
          JSON.stringify(d.metadata || {}),
        ]
      );
    }

    return { ok: true };
  } catch (e) {
    return { ok: false, reason: e.message || String(e) };
  } finally {
    await client.end().catch(() => {});
  }
}

export async function hydrateFromNeon(env, projectId) {
  const url = dbUrl(env);
  if (!url) return { ok: false, state: null };

  const client = new pg.Client({ connectionString: url, ssl: { rejectUnauthorized: false } });
  try {
    await client.connect();
    const events = (
      await client.query(
        `SELECT event_type, severity, source, payload, created_at
         FROM event_log WHERE project_key = $1
         ORDER BY created_at DESC LIMIT 30`,
        [projectId]
      )
    ).rows;
    const errors = (
      await client.query(
        `SELECT error_type, error_message, fix_pattern, times_seen, last_seen_at
         FROM error_memory WHERE project_key = $1
         ORDER BY last_seen_at DESC LIMIT 20`,
        [projectId]
      )
    ).rows;
    const deploys = (
      await client.query(
        `SELECT commit_hash, status, summary, created_at
         FROM deployment_history WHERE project_key = $1
         ORDER BY created_at DESC LIMIT 15`,
        [projectId]
      )
    ).rows;
    return {
      ok: true,
      state: {
        projectId,
        projectStatus: "hydrated",
        recentEvents: events,
        errorMemory: errors,
        deploymentHistory: deploys,
      },
    };
  } catch (e) {
    return { ok: false, reason: e.message };
  } finally {
    await client.end().catch(() => {});
  }
}
