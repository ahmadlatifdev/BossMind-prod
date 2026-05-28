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

export function sha256(text) {
  return crypto.createHash("sha256").update(String(text || ""), "utf8").digest("hex");
}

export function nowIso() {
  return new Date().toISOString();
}

export function appendJsonl(filePath, record) {
  fs.mkdirSync(path.dirname(filePath), { recursive: true });
  const line = JSON.stringify(record);
  fs.appendFileSync(filePath, `${line}\n`, "utf8");
  return sha256(line);
}

export function loadMasterEnvKeys(masterEnvPath) {
  const keys = {};
  if (!masterEnvPath || !fs.existsSync(masterEnvPath)) return { keys, exists: false };
  const lines = fs.readFileSync(masterEnvPath, "utf8").split(/\r?\n/);
  for (const line of lines) {
    const m = line.match(/^\s*([^#][^=]+)=(.*)$/);
    if (m) keys[m[1].trim()] = m[2].trim();
  }
  return { keys, exists: true };
}

export function maskEnvValue(key, value) {
  if (!value) return null;
  const sensitive = /secret|key|token|password|url|database/i.test(key);
  if (sensitive) return value ? "***configured***" : null;
  return value;
}

export function projectExists(root) {
  try {
    return Boolean(root && fs.existsSync(root));
  } catch {
    return false;
  }
}

export async function probeUrl(url, timeoutMs = 15000) {
  const ac = new AbortController();
  const tid = setTimeout(() => ac.abort(), timeoutMs);
  try {
    const r = await fetch(url, { signal: ac.signal, redirect: "follow" });
    const text = await r.text();
    let json = null;
    try {
      json = JSON.parse(text);
    } catch {
      json = { rawPreview: text.slice(0, 200) };
    }
    clearTimeout(tid);
    return { ok: r.ok, status: r.status, url, json };
  } catch (e) {
    clearTimeout(tid);
    return { ok: false, url, error: e.message || String(e) };
  }
}
