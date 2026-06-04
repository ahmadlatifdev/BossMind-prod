import fs from "fs";
import path from "path";

const DEFAULT_SOURCES = [
  "D:/BossMind/bossmind-shared/automation/.env.master.local",
  "D:/BossMind/bossmind-shared/.env.master.local",
  "D:/BossMind/bossmind-shared/Global-files/.env.master.local",
  "D:/BossMind/16-neon/.env.bossmind.local",
  "D:/BossMind/bossmind-resumora/.env.local",
  "D:/BossMind/bossmind-resumora/.env",
  "D:/BossMind/bossmind-shared/.env",
  "D:/BossMind/bossmind-shared/Global-files/.env",
  "D:/BossMind/bossmind-shared/automation/.env",
  "D:/BossMind/16-neon/.env",
  "D:/BossMind/.env.master.local",
];

function parseEnvContent(content) {
  const out = {};
  for (const line of content.split(/\r?\n/)) {
    const t = line.trim();
    if (!t || t.startsWith("#") || !t.includes("=")) continue;
    const eq = t.indexOf("=");
    const key = t.slice(0, eq).trim();
    let val = t.slice(eq + 1).trim();
    if (
      (val.startsWith('"') && val.endsWith('"')) ||
      (val.startsWith("'") && val.endsWith("'"))
    ) {
      val = val.slice(1, -1);
    }
    if (val) out[key] = val;
  }
  return out;
}

export function loadHubEnv(hubRoot = "D:/BossMind") {
  const sources = DEFAULT_SOURCES.map((p) =>
    p.replace(/^D:\/BossMind/, hubRoot.replace(/\\/g, "/"))
  );
  let merged = { ...process.env };
  const loadedFrom = [];
  for (const src of sources) {
    if (!fs.existsSync(src)) continue;
    merged = { ...parseEnvContent(fs.readFileSync(src, "utf8")), ...merged };
    loadedFrom.push(src);
  }
  return { env: merged, loadedFrom };
}

export function applyHubEnv(hubRoot = "D:/BossMind") {
  const { env } = loadHubEnv(hubRoot);
  for (const [k, v] of Object.entries(env)) {
    if (v && !process.env[k]) process.env[k] = v;
  }
  return env;
}
