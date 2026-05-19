const fs = require("fs");
const path = require("path");

const LOG_DIR = path.join(__dirname, "logs");
const LOG_FILE = path.join(LOG_DIR, "repair-tasks.json");

function ensureLogFile() {
  if (!fs.existsSync(LOG_DIR)) {
    fs.mkdirSync(LOG_DIR, { recursive: true });
  }

  if (!fs.existsSync(LOG_FILE)) {
    fs.writeFileSync(LOG_FILE, "[]", "utf8");
  }
}

function saveRepairTask(issue, classification) {
  ensureLogFile();

  const current = JSON.parse(fs.readFileSync(LOG_FILE, "utf8"));

  const task = {
    id: `repair_${Date.now()}`,
    createdAt: new Date().toISOString(),
    issueTitle: issue.title || "Unknown issue",
    issueId: issue.id || null,
    issuePermalink: issue.permalink || null,
    type: classification.type,
    action: classification.action,
    status: "queued",
  };

  current.push(task);

  fs.writeFileSync(LOG_FILE, JSON.stringify(current, null, 2), "utf8");

  console.log("📝 Repair task saved:", task.id);

  return task;
}

module.exports = { saveRepairTask };