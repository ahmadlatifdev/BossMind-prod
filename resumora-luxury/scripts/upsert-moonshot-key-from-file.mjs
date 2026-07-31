#!/usr/bin/env node
/**
 * Upsert Moonshot/Kimi key from a one-line temp file. Never prints the key.
 * Usage: node scripts/upsert-moonshot-key-from-file.mjs <path-to-temp-file>
 */
import fs from "fs";

const src = process.argv[2];
if (!src || !fs.existsSync(src)) {
  console.error("MISSING_FILE");
  process.exit(2);
}
const KEY = String(fs.readFileSync(src, "utf8")).trim().replace(/^["']|["']$/g, "");
if (!KEY || KEY.length < 20) {
  console.error("INVALID_KEY");
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
  KIMI_REASONING_EFFORT: "high",
};

const report = [];
for (const f of files) {
  try {
    report.push({ file: f.replace(/\\/g, "/"), changes: upsert(f, map), keyLen: KEY.length });
  } catch (e) {
    report.push({ file: f, error: e.message });
  }
}

// Cloud Run env-vars YAML (temp) — key present only in this file
const yamlPath = "D:/BossMind/config/.kimi-cloudrun-env.yaml";
fs.writeFileSync(yamlPath, `KIMI_API_KEY: "${KEY}"\nMOONSHOT_API_KEY: "${KEY}"\nKIMI_MODEL: "kimi-k3"\n`);

console.log(
  JSON.stringify(
    {
      ok: true,
      keyLen: KEY.length,
      files: report.map((r) => ({ file: r.file, changes: r.changes, error: r.error })),
      cloudRunEnvFile: yamlPath,
    },
    null,
    2,
  ),
);
