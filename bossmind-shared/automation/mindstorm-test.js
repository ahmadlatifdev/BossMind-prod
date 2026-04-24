const { generateMindstormIdea } = require("./mindstormEngine");

const idea = generateMindstormIdea({
  source: "bossmind-proof-ledger",
  category: "automation_optimization",
  title: "Optimize repeated clean-cycle logging",
  reason: "Proof ledger shows repeated healthy cycles; logs can be summarized to reduce noise.",
  affectedProjects: ["bossmind-prod"],
  affectedFiles: ["worker/supervisor.js"],
  expectedImpact: "medium",
  safetyScore: 95,
});

console.log("Mindstorm Test Result:", idea);