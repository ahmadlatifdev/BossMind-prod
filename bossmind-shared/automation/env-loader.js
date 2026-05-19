const fs = require("fs");
const path = require("path");

const ROOT_DIRS = [
  "D:\\BossMind",
  "D:\\Shakhsy11"
];

const OUTPUT_DIR = "D:\\BossMind\\bossmind-shared\\automation\\memory";
const OUTPUT_FILE = path.join(OUTPUT_DIR, "env-registry.json");

const REQUIRED_KEYS = [
  "DEEPSEEK_API_KEY",
  "GITHUB_TOKEN",
  "GITHUB_OWNER",
  "GITHUB_REPO",
  "GITHUB_BRANCH",
  "DEPLOY_WEBHOOK_URL",
  "RAILWAY_TOKEN",
  "RENDER_API_KEY",
  "NEON_DATABASE_URL",
  "SENTRY_DSN"
];

const SKIP_DIRS = new Set([
  "node_modules",
  ".git",
  ".next",
  "dist",
  "build",
  ".vercel",
  ".railway"
]);

function ensureOutputDir() {
  if (!fs.existsSync(OUTPUT_DIR)) {
    fs.mkdirSync(OUTPUT_DIR, { recursive: true });
  }
}

function findEnvFiles(dir, results = []) {
  if (!fs.existsSync(dir)) return results;

  const entries = fs.readdirSync(dir, { withFileTypes: true });

  for (const entry of entries) {
    const fullPath = path.join(dir, entry.name);

    if (entry.isDirectory() && !SKIP_DIRS.has(entry.name)) {
      findEnvFiles(fullPath, results);
    }

    if (
      entry.isFile() &&
      (entry.name === ".env" ||
        entry.name === ".env.local" ||
        entry.name === ".env.production" ||
        entry.name === ".env.development")
    ) {
      results.push(fullPath);
    }
  }

  return results;
}

function parseEnvFile(filePath) {
  const content = fs.readFileSync(filePath, "utf8");
  const found = {};

  for (const line of content.split(/\r?\n/)) {
    const trimmed = line.trim();

    if (!trimmed || trimmed.startsWith("#") || !trimmed.includes("=")) continue;

    const [key, ...valueParts] = trimmed.split("=");
    const cleanKey = key.trim();
    const value = valueParts.join("=").trim();

    if (REQUIRED_KEYS.includes(cleanKey) && value) {
      found[cleanKey] = {
        exists: true,
        maskedValue:
          value.length > 8
            ? `${value.slice(0, 4)}********${value.slice(-4)}`
            : "********",
        sourceFile: filePath
      };
    }
  }

  return found;
}

function main() {
  ensureOutputDir();

  const envFiles = [];
  for (const root of ROOT_DIRS) {
    findEnvFiles(root, envFiles);
  }

  const registry = {
    generatedAt: new Date().toISOString(),
    rootsScanned: ROOT_DIRS,
    envFilesScanned: envFiles.length,
    envFiles,
    keys: {}
  };

  for (const file of envFiles) {
    const parsed = parseEnvFile(file);

    for (const [key, data] of Object.entries(parsed)) {
      if (!registry.keys[key]) {
        registry.keys[key] = data;
      }
    }
  }

  fs.writeFileSync(OUTPUT_FILE, JSON.stringify(registry, null, 2), "utf8");

  console.log("ENV_LOADER_COMPLETED");
  console.log("ROOTS_SCANNED:", ROOT_DIRS.join(" | "));
  console.log("ENV_FILES_SCANNED:", envFiles.length);
  console.log("REGISTRY_SAVED:", OUTPUT_FILE);

  for (const key of REQUIRED_KEYS) {
    console.log(`${key}: ${registry.keys[key] ? "FOUND" : "MISSING"}`);
  }
}

main();