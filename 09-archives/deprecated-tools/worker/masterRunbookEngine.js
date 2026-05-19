const fs = require("fs");
const path = require("path");

const RUNBOOK_DIR = path.join(__dirname, "memory");
const RUNBOOK_FILE = path.join(RUNBOOK_DIR, "master-runbook-log.json");

function ensureRunbookFile() {
  if (!fs.existsSync(RUNBOOK_DIR)) {
    fs.mkdirSync(RUNBOOK_DIR, { recursive: true });
  }

  if (!fs.existsSync(RUNBOOK_FILE)) {
    fs.writeFileSync(RUNBOOK_FILE, JSON.stringify([], null, 2), "utf8");
  }
}

function executeRunbookStep(step) {
  ensureRunbookFile();

  const logs = JSON.parse(fs.readFileSync(RUNBOOK_FILE, "utf8"));

  const entry = {
    id: `runbook_${Date.now()}`,
    createdAt: new Date().toISOString(),
    phase: step.phase || "unknown",
    project: step.project || "unknown",
    action: step.action || "unknown",
    expectedOutput: step.expectedOutput || "unknown",
    status: "executed",
  };

  logs.push(entry);

  fs.writeFileSync(RUNBOOK_FILE, JSON.stringify(logs, null, 2), "utf8");

  console.log("📘 Runbook step executed:", entry.id);

  return entry;
}

module.exports = { executeRunbookStep };