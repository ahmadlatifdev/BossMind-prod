const fs = require("fs");
const path = require("path");

const ROOTS = ["D:\\BossMind", "D:\\Shakhsy11"];
const MASTER_ENV = "D:\\BossMind\\bossmind-shared\\automation\\.env.master";
const REGISTRY = "D:\\BossMind\\bossmind-shared\\automation\\memory\\env-master-registry.json";

const SKIP_DIRS = new Set(["node_modules", ".git", ".next", "dist", "build", ".vercel", ".railway"]);

function findEnvFiles(dir, results = []) {
  if (!fs.existsSync(dir)) return results;

  for (const entry of fs.readdirSync(dir, { withFileTypes: true })) {
    const full = path.join(dir, entry.name);

    if (entry.isDirectory() && !SKIP_DIRS.has(entry.name)) {
      findEnvFiles(full, results);
    }

    if (entry.isFile() && [".env", ".env.local", ".env.production", ".env.development"].includes(entry.name)) {
      results.push(full);
    }
  }

  return results;
}

function parseEnv(file) {
  const lines = fs.readFileSync(file, "utf8").split(/\r?\n/);
  const vars = {};

  for (const line of lines) {
    const clean = line.trim();
    if (!clean || clean.startsWith("#") || !clean.includes("=")) continue;

    const [key, ...rest] = clean.split("=");
    const value = rest.join("=").trim();

    if (key && value && !value.includes("YOUR_")) {
      vars[key.trim()] = { value, sourceFile: file };
    }
  }

  return vars;
}

function mask(value) {
  if (!value) return "";
  return value.length > 10 ? `${value.slice(0, 4)}********${value.slice(-4)}` : "********";
}

function main() {
  const envFiles = [];
  ROOTS.forEach(root => findEnvFiles(root, envFiles));

  const master = {};
  const registry = {
    generatedAt: new Date().toISOString(),
    envFilesScanned: envFiles.length,
    masterFile: MASTER_ENV,
    keys: {}
  };

  for (const file of envFiles) {
    const vars = parseEnv(file);

    for (const [key, data] of Object.entries(vars)) {
      if (!master[key]) {
        master[key] = data.value;
        registry.keys[key] = {
          maskedValue: mask(data.value),
          sourceFile: data.sourceFile
        };
      }
    }
  }

  const output = Object.entries(master)
    .map(([key, value]) => `${key}=${value}`)
    .join("\n");

  fs.writeFileSync(MASTER_ENV, output + "\n", "utf8");
  fs.writeFileSync(REGISTRY, JSON.stringify(registry, null, 2), "utf8");

  console.log("ENV_MASTER_CREATED");
  console.log("ENV_FILES_SCANNED:", envFiles.length);
  console.log("KEYS_SAVED:", Object.keys(master).length);
  console.log("MASTER_ENV:", MASTER_ENV);
  console.log("REGISTRY:", REGISTRY);
}

main();