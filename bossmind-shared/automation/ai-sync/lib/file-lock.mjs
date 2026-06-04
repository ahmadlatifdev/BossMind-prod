import fs from "fs";
import path from "path";

function lockFilePath(locksRoot, projectId, relativeFile) {
  const safe = relativeFile.replace(/[\\/]/g, "__");
  return path.join(locksRoot, projectId, `${safe}.lock.json`);
}

export function acquireFileLock({ locksRoot, projectId, filePath, owner, ttlMs = 900000 }) {
  const rel = filePath.replace(/\\/g, "/");
  const p = lockFilePath(locksRoot, projectId, rel);
  fs.mkdirSync(path.dirname(p), { recursive: true });

  if (fs.existsSync(p)) {
    const existing = JSON.parse(fs.readFileSync(p, "utf8"));
    const age = Date.now() - new Date(existing.timestamp).getTime();
    if (existing.status === "locked" && age < ttlMs && existing.owner !== owner) {
      return {
        acquired: false,
        conflict: true,
        existing,
        message: `File locked by ${existing.owner} since ${existing.timestamp}`,
      };
    }
  }

  const record = {
    projectName: projectId,
    filePath: rel,
    lockOwner: owner,
    owner,
    timestamp: new Date().toISOString(),
    status: "locked",
  };
  fs.writeFileSync(p, JSON.stringify(record, null, 2), "utf8");
  return { acquired: true, record, path: p };
}

export function releaseFileLock({ locksRoot, projectId, filePath, owner }) {
  const rel = filePath.replace(/\\/g, "/");
  const p = lockFilePath(locksRoot, projectId, rel);
  if (!fs.existsSync(p)) return { released: true, absent: true };
  const existing = JSON.parse(fs.readFileSync(p, "utf8"));
  if (existing.owner !== owner && existing.lockOwner !== owner) {
    return {
      released: false,
      conflict: true,
      message: `Cannot release: owned by ${existing.owner}`,
    };
  }
  const record = {
    ...existing,
    status: "released",
    releasedAt: new Date().toISOString(),
  };
  fs.writeFileSync(p, JSON.stringify(record, null, 2), "utf8");
  return { released: true, record };
}

export function listActiveLocks(locksRoot, projectId) {
  const dir = path.join(locksRoot, projectId);
  if (!fs.existsSync(dir)) return [];
  return fs
    .readdirSync(dir)
    .filter((f) => f.endsWith(".lock.json"))
    .map((f) => JSON.parse(fs.readFileSync(path.join(dir, f), "utf8")))
    .filter((r) => r.status === "locked");
}
