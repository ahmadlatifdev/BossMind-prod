#!/usr/bin/env node
/**
 * Upsert Moonshot/Kimi API key into vault + local env files WITHOUT printing the value.
 * Usage (PowerShell):
 *   $env:MOONSHOT_API_KEY = 'sk-...'
 *   node scripts/upsert-moonshot-key.mjs
 * Or:
 *   node scripts/upsert-moonshot-key.mjs --from-env
 */
import fs from "fs";

const KEY = String(process.env.MOONSHOT_API_KEY || process.env.KIMI_API_KEY || "").trim();
if (!KEY) {
  console.error("MISSING: set MOONSHOT_API_KEY or KIMI_API_KEY in the environment, then re-run.");
  process.exit(2);
}

const files = [
  "D:/BossMind/config/secrets.env",
  "D:/BossMind/resumora-luxury/.env.local",
  "D:/BossMind/resumora-luxury/.env.production",
  "D:/BossMind/resumora-luxury/.env.resumora-live",
];

function upsert(file, map) {
  let text = fs.existsSync(file) ? fs.readFileSync(file, "utf8") : "";
  if (text && !text.endsWith("\n")) text += "\n";
  const changed = [];
  for (const [k, v] of Object.entries(map)) {
    const re = new RegExp(`(^|\\n)${k}=[^\\r\\n]*`);
    if (re.test(text)) {
      text = text.replace(re, `$1${k}=${v}`);
      changed.push(`updated:${k}`);
    } else {
      text += `${k}=${v}\n`;
      changed.push(`added:${k}`);
    }
  }
  fs.writeFileSync(file, text);
  return changed;
}

const map = {
  KIMI_API_KEY: KEY,
  MOONSHOT_API_KEY: KEY,
  KIMI_MODEL: "kimi-k3",
  MOONSHOT_MODEL: "kimi-k3",
  KIMI_API_BASE: "https://api.moonshot.ai/v1",
  KIMI_BASE_URL: "https://api.moonshot.ai/v1",
  MOONSHOT_BASE_URL: "https://api.moonshot.ai/v1",
};

const report = [];
for (const f of files) {
  try {
    report.push({ file: f, changes: upsert(f, map), keyLen: KEY.length });
  } catch (e) {
    report.push({ file: f, error: e.message });
  }
}
console.log(JSON.stringify({ ok: true, files: report.map((r) => ({ file: r.file, changes: r.changes, keyLen: r.keyLen, error: r.error })) }, null, 2));
console.log("Key stored (length only logged). Run: node scripts/diagnostics/kimi-k3-smoke-test.mjs");
