const fs = require("fs");
const path = require("path");

const CORE_ENV = "D:\\BossMind\\bossmind-shared\\automation\\.env.core";

function loadCoreEnv() {
  if (!fs.existsSync(CORE_ENV)) {
    throw new Error("CORE_ENV_NOT_FOUND");
  }

  const lines = fs.readFileSync(CORE_ENV, "utf8").split(/\r?\n/);

  for (const line of lines) {
    const clean = line.trim();
    if (!clean || clean.startsWith("#") || !clean.includes("=")) continue;

    const [key, ...rest] = clean.split("=");
    const value = rest.join("=").trim();

    if (!process.env[key]) {
      process.env[key] = value;
      console.log(`LOADED: ${key}`);
    }
  }
}

loadCoreEnv();
console.log("ENV_CORE_LOADED");