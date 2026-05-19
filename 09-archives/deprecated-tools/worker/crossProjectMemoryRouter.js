const fs = require("fs");
const path = require("path");

const MEMORY_DIR = path.join(__dirname, "memory");
const MEMORY_FILE = path.join(MEMORY_DIR, "cross-project-repair-memory.json");

const PROJECTS = [
  "bossmind-resumora",
  "bossmind-elegancyart",
  "bossmind-ai-video-generator",
  "bossmind-tiktok-ai",
  "bossmind-global-stock",
];

function ensureMemoryFile() {
  if (!fs.existsSync(MEMORY_DIR)) {
    fs.mkdirSync(MEMORY_DIR, { recursive: true });
  }

  if (!fs.existsSync(MEMORY_FILE)) {
    fs.writeFileSync(
      MEMORY_FILE,
      JSON.stringify(
        {
          createdAt: new Date().toISOString(),
          projects: PROJECTS,
          repairMemory: [],
        },
        null,
        2
      ),
      "utf8"
    );
  }
}

function saveCrossProjectRepairMemory(entry) {
  ensureMemoryFile();

  const memory = JSON.parse(fs.readFileSync(MEMORY_FILE, "utf8"));

  const repairEntry = {
    id: `memory_${Date.now()}`,
    createdAt: new Date().toISOString(),
    project: entry.project || "unknown",
    issueTitle: entry.issueTitle || "unknown",
    issueType: entry.issueType || "unknown",
    action: entry.action || "unknown",
    status: entry.status || "saved",
  };

  memory.repairMemory.push(repairEntry);

  fs.writeFileSync(MEMORY_FILE, JSON.stringify(memory, null, 2), "utf8");

  console.log("🧠 Cross-project repair memory saved:", repairEntry.id);

  return repairEntry;
}

module.exports = {
  PROJECTS,
  saveCrossProjectRepairMemory,
};