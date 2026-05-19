const fs = require("fs");
const path = require("path");

const LIBRARY_DIR = path.join(__dirname, "memory");
const LIBRARY_FILE = path.join(LIBRARY_DIR, "error-pattern-library.json");

function ensureLibraryFile() {
  if (!fs.existsSync(LIBRARY_DIR)) {
    fs.mkdirSync(LIBRARY_DIR, { recursive: true });
  }

  if (!fs.existsSync(LIBRARY_FILE)) {
    fs.writeFileSync(LIBRARY_FILE, JSON.stringify([], null, 2), "utf8");
  }
}

function saveErrorPattern(pattern) {
  ensureLibraryFile();

  const current = JSON.parse(fs.readFileSync(LIBRARY_FILE, "utf8"));

  const entry = {
    id: `pattern_${Date.now()}`,
    createdAt: new Date().toISOString(),
    issueTitle: pattern.issueTitle || "unknown",
    issueType: pattern.issueType || "unknown",
    detectionPattern: pattern.detectionPattern || "unknown",
    autoFixRule: pattern.autoFixRule || "unknown",
    reusableAcrossProjects: true,
  };

  current.push(entry);

  fs.writeFileSync(LIBRARY_FILE, JSON.stringify(current, null, 2), "utf8");

  console.log("📚 Error pattern saved:", entry.id);

  return entry;
}

module.exports = { saveErrorPattern };