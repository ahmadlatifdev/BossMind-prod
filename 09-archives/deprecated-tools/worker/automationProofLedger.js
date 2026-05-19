const fs = require("fs");
const path = require("path");
const crypto = require("crypto");

const LEDGER_DIR = path.join(__dirname, "memory");
const LEDGER_FILE = path.join(LEDGER_DIR, "automation-proof-ledger.json");

function ensureLedgerFile() {
  if (!fs.existsSync(LEDGER_DIR)) {
    fs.mkdirSync(LEDGER_DIR, { recursive: true });
  }

  if (!fs.existsSync(LEDGER_FILE)) {
    fs.writeFileSync(LEDGER_FILE, JSON.stringify([], null, 2), "utf8");
  }
}

function createChecksum(entry) {
  return crypto
    .createHash("sha256")
    .update(JSON.stringify(entry))
    .digest("hex");
}

function saveProofLedgerEntry(entry) {
  ensureLedgerFile();

  const ledger = JSON.parse(fs.readFileSync(LEDGER_FILE, "utf8"));

  const proof = {
    id: `proof_${Date.now()}`,
    timestamp: new Date().toISOString(),
    requirementLockId: entry.requirementLockId || null,
    allowedFiles: entry.allowedFiles || [],
    blockedFiles: entry.blockedFiles || [],
    changedFiles: entry.changedFiles || [],
    validationResult: entry.validationResult || null,
    deploymentResult: entry.deploymentResult || null,
    rollbackStatus: entry.rollbackStatus || null,
    sentryStatus: entry.sentryStatus || null,
  };

  proof.finalChecksum = createChecksum(proof);

  ledger.push(proof);

  fs.writeFileSync(LEDGER_FILE, JSON.stringify(ledger, null, 2), "utf8");

  console.log("🧾 Automation proof ledger saved:", proof.id);
  console.log("🔒 Proof checksum:", proof.finalChecksum);

  return proof;
}

module.exports = { saveProofLedgerEntry };