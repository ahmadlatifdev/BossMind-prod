const Sentry = require("@sentry/node");

// Engines
const { classifyIssue } = require("./autoFixEngine");
const { saveRepairTask } = require("./repairTaskLog");
const { createFixCommit } = require("./githubFixExecutor");
const { saveCrossProjectRepairMemory } = require("./crossProjectMemoryRouter");
const { saveErrorPattern } = require("./errorPatternLibrary");
const { isPatchSafe } = require("./safePatchGuard");

const SENTRY_TOKEN = process.env.SENTRY_TOKEN;
const ORG = "bossmind-main-ke";
const PROJECT = "node-express";

console.log("BossMind Self-Healing Supervisor started");

async function checkSentryIssues() {
  try {
    console.log("Supervisor check: scanning Sentry issues...");

    const res = await fetch(
      `https://sentry.io/api/0/projects/${ORG}/${PROJECT}/issues/?query=is:unresolved`,
      {
        headers: {
          Authorization: `Bearer ${SENTRY_TOKEN}`,
          "Content-Type": "application/json",
        },
      }
    );

    const data = await res.json();

    if (Array.isArray(data) && data.length > 0) {
      const issue = data[0];

      console.log("🚨 New Sentry issue:", issue.title);

      const result = classifyIssue(issue.title);

      console.log("🧠 Auto-Fix Classification:");
      console.log("Type:", result.type);
      console.log("Action:", result.action);

      // Save repair task
      const task = saveRepairTask(issue, result);

      // Cross-project memory
      saveCrossProjectRepairMemory({
        project: PROJECT,
        issueTitle: issue.title,
        issueType: result.type,
        action: result.action,
      });

      // Error pattern learning
      saveErrorPattern({
        issueTitle: issue.title,
        issueType: result.type,
        detectionPattern: issue.title.toLowerCase(),
        autoFixRule: result.action,
      });

      // Example auto-fix trigger with SAFE GUARD
      if (result.type === "missing_dependency") {
        console.log("⚙️ Preparing GitHub auto-fix...");

        const newContent = "// Auto-fix placeholder executed";

        const safety = isPatchSafe(newContent);

        if (!safety.safe) {
          console.log("⛔ Patch blocked:", safety.reason);
          return;
        }

        console.log("✅ Patch approved, executing...");

        await createFixCommit(
          "worker/fix-log.txt",
          newContent,
          "Auto-fix: missing dependency detected"
        );
      }

    } else {
      console.log("✅ No new issues");
    }
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();