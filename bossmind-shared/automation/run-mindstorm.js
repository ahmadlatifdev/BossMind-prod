const path = require("path");

// load engine
const { generateMindstormIdea } = require("./mindstormEngine");

// optional: ensure working directory is correct
process.chdir(__dirname);

// execute with real Sentry-trigger context
try {
  const result = generateMindstormIdea({
    source: "sentry",
    category: "error_repair",
    title: "Auto repair from Sentry event",
    reason: "Triggered by real Sentry cloud error",
    affectedProjects: ["BossMind"],
    affectedFiles: [],
    expectedImpact: "high",
    safetyScore: 95
  });

  console.log("EXECUTION_SUCCESS");
  console.log(result);

} catch (err) {
  console.error("EXECUTION_FAILED");
  console.error(err);
}