import fs from "fs";
import path from "path";
import crypto from "crypto";

function dayStamp() {
  return new Date().toISOString().slice(0, 10);
}

export function proofLogPath(logsRoot, projectId = "hub") {
  return path.join(logsRoot, `proof-${projectId}-${dayStamp()}.jsonl`);
}

export function appendProofLog(logsRoot, entry) {
  const projectId = entry.projectName || entry.projectId || "hub";
  const p = proofLogPath(logsRoot, projectId);
  fs.mkdirSync(path.dirname(p), { recursive: true });
  const record = {
    schema: "bossmind-ai-sync-proof/v1",
    timestamp: new Date().toISOString(),
    checksum: null,
    ...entry,
  };
  const body = JSON.stringify(record);
  record.checksum = crypto.createHash("sha256").update(body).digest("hex").slice(0, 16);
  const line = `${JSON.stringify(record)}\n`;
  fs.appendFileSync(p, line, "utf8");
  return { path: p, record };
}

export function readProofLogs(logsRoot, projectId, limit = 50) {
  const p = proofLogPath(logsRoot, projectId);
  if (!fs.existsSync(p)) return [];
  const lines = fs.readFileSync(p, "utf8").trim().split("\n").filter(Boolean);
  return lines.slice(-limit).map((l) => JSON.parse(l));
}

export function writeHubSummary(sharedMemoryRoot, summary) {
  const p = path.join(sharedMemoryRoot, "bossmind-ai-sync-latest.json");
  fs.mkdirSync(path.dirname(p), { recursive: true });
  summary.updatedAt = new Date().toISOString();
  fs.writeFileSync(p, JSON.stringify(summary, null, 2), "utf8");
  return p;
}
