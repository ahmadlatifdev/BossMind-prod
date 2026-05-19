const fs = require("fs");
const path = require("path");

const ROOTS = ["D:\\BossMind", "D:\\Shakhsy11"];
const CORE_ENV = "D:\\BossMind\\bossmind-shared\\automation\\.env.core";

const CORE_KEYS = [
  "NEON_DATABASE_URL",
  "SENTRY_DSN",
  "DEEPSEEK_API_KEY"
];

const SKIP = new Set(["node_modules", ".git", ".next", "dist", "build"]);

function findEnvFiles(dir, results = []) {
  if (!fs.existsSync(dir)) return results;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.isDirectory() && !SKIP.has(entry.name)) {
      findEnvFiles(full, results);
    }

    if (entry.isFile() && entry.name.startsWith(".env")) {
      results.push(full);
    }
  }

  return results;
}

function parse(file) {
  const content = fs.readFileSync(file, "utf8");
  const found = {};

  for (const line of content.split(/\r?\n/)) {
    const clean = line.trim();
    if (!clean || clean.startsWith("#") || !clean.includes("=")) continue;

    const [key, ...rest] = clean.split("=");
    const value = rest.join("=").trim();

    if (CORE_KEYS.includes(key.trim()) && value && !value.includes("YOUR_")) {
      found[key.trim()] = value;
    }
  }

  return found;
}

function main() {
  const envFiles = [];
  ROOTS.forEach(root => findEnvFiles(root, envFiles));

  const core = {};

  for (const file of envFiles) {
    const parsed = parse(file);
    for (const [k, v] of Object.entries(parsed)) {
      if (!core[k]) core[k] = v;
    }
  }

  const output = Object.entries(core)
    .map(([k, v]) => `${k}=${v}`)
    .join("\n");

  fs.writeFileSync(
    CORE_ENV,
    "# BossMind Core Shared Environment\n\n" + output + "\n",
    "utf8"
  );

  console.log("ENV_CORE_UPDATED");
  console.log("KEYS_FOUND:", Object.keys(core).length);
}

main();