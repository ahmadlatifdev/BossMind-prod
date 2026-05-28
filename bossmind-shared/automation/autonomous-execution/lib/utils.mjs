import fs from "fs";
import path from "path";
import crypto from "crypto";

export function readJsonSafe(filePath) {
  try {
    if (!filePath || !fs.existsSync(filePath)) return null;
    return JSON.parse(fs.readFileSync(filePath, "utf8"));
  } catch {
    return null;
  }
}

export function writeJson(filePath, data) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
}

export function writeText(filePath, text) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  fs.writeFileSync(filePath, text, "utf8");
}

export function sha256(text) {
  return crypto.createHash("sha256").update(String(text || ""), "utf8").digest("hex");
}

export function sha256File(filePath) {
  try {
    const buf = fs.readFileSync(filePath);
    return crypto.createHash("sha256").update(buf).digest("hex");
  } catch {
    return null;
  }
}

export function nowIso() {
  return new Date().toISOString();
}

export function runId() {
  return `${new Date().toISOString().replace(/[:.]/g, "-")}-${crypto.randomBytes(3).toString("hex")}`;
}

export function listFilesRecursive(dir, { maxFiles = 5000, extensions = null } = {}) {
  const out = [];
  if (!dir || !fs.existsSync(dir)) return out;
  const stack = [dir];
  while (stack.length && out.length < maxFiles) {
    const current = stack.pop();
    let entries;
    try {
      entries = fs.readdirSync(current, { withFileTypes: true });
    } catch {
      continue;
    }
    for (const e of entries) {
      if (out.length >= maxFiles) break;
      const full = path.join(current, e.name);
      if (e.isDirectory()) {
        if (/node_modules|\.git|\.next|dist|build|coverage/i.test(full)) continue;
        stack.push(full);
      } else if (e.isFile()) {
        if (extensions && !extensions.some((ext) => full.toLowerCase().endsWith(ext))) continue;
        out.push(full);
      }
    }
  }
  return out;
}

export function readTailJsonl(filePath, limit = 20) {
  if (!filePath || !fs.existsSync(filePath)) return [];
  try {
    const lines = fs.readFileSync(filePath, "utf8").trim().split(/\r?\n/).filter(Boolean);
    return lines.slice(-limit).map((line) => {
      try {
        return JSON.parse(line);
      } catch {
        return { raw: line.slice(0, 200) };
      }
    });
  } catch {
    return [];
  }
}

export function statusFromBool(ok, partial = false) {
  if (ok) return "ACTIVE";
  if (partial) return "PARTIAL";
  return "BROKEN";
}
