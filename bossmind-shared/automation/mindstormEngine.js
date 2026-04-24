const fs = require("fs");
const path = require("path");

const MINDSTORM_DIR = path.join(__dirname, "memory");
const MINDSTORM_FILE = path.join(MINDSTORM_DIR, "mindstorm-ideas.json");

function ensureMindstormFile() {
  if (!fs.existsSync(MINDSTORM_DIR)) {
    fs.mkdirSync(MINDSTORM_DIR, { recursive: true });
  }

  if (!fs.existsSync(MINDSTORM_FILE)) {
    fs.writeFileSync(MINDSTORM_FILE, JSON.stringify([], null, 2), "utf8");
  }
}

function generateMindstormIdea(input) {
  ensureMindstormFile();

  const ideas = JSON.parse(fs.readFileSync(MINDSTORM_FILE, "utf8"));

  const idea = {
    id: `mindstorm_${Date.now()}`,
    createdAt: new Date().toISOString(),
    source: input.source || "bossmind-proof-ledger",
    category: input.category || "automation_optimization",
    title: input.title || "System optimization opportunity",
    reason: input.reason || "Detected repeatable improvement opportunity",
    affectedProjects: input.affectedProjects || [],
    affectedFiles: input.affectedFiles || [],
    expectedImpact: input.expectedImpact || "medium",
    safetyScore: input.safetyScore || 90,
    executionMode: "suggestion_only",
    status: "pending_review",
  };

  ideas.push(idea);

  fs.writeFileSync(MINDSTORM_FILE, JSON.stringify(ideas, null, 2), "utf8");

  console.log("🧠 Mindstorm idea saved:", idea.id);

  return idea;
}

module.exports = { generateMindstormIdea };