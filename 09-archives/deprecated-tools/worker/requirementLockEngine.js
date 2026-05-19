const fs = require("fs");
const path = require("path");

const LOCK_DIR = path.join(__dirname, "memory");
const LOCK_FILE = path.join(LOCK_DIR, "requirement-locks.json");

function ensureLockFile() {
  if (!fs.existsSync(LOCK_DIR)) {
    fs.mkdirSync(LOCK_DIR, { recursive: true });
  }

  if (!fs.existsSync(LOCK_FILE)) {
    fs.writeFileSync(LOCK_FILE, JSON.stringify([], null, 2), "utf8");
  }
}

function createRequirementLock(task) {
  ensureLockFile();

  const locks = JSON.parse(fs.readFileSync(LOCK_FILE, "utf8"));

  const lock = {
    id: `requirement_lock_${Date.now()}`,
    createdAt: new Date().toISOString(),
    project: task.project,
    filePath: task.filePath,
    expectedOutput: task.expectedOutput,
    protectedPreviousState: task.protectedPreviousState,
    forbiddenChanges: task.forbiddenChanges || [],
    rollbackCheckpoint: task.rollbackCheckpoint,
    successCondition: task.successCondition,
    status: "locked",
  };

  locks.push(lock);

  fs.writeFileSync(LOCK_FILE, JSON.stringify(locks, null, 2), "utf8");

  console.log("🔐 Requirement locked:", lock.id);

  return lock;
}

function validateRequirementLock(lock) {
  const requiredFields = [
    "project",
    "filePath",
    "expectedOutput",
    "protectedPreviousState",
    "rollbackCheckpoint",
    "successCondition",
  ];

  const missing = requiredFields.filter((field) => !lock[field]);

  if (missing.length > 0) {
    return {
      allowed: false,
      reason: `Missing lock fields: ${missing.join(", ")}`,
    };
  }

  return {
    allowed: true,
    reason: "Requirement lock valid",
  };
}

module.exports = {
  createRequirementLock,
  validateRequirementLock,
};