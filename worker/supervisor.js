const Sentry = require("@sentry/node");

// Engines
const { classifyIssue } = require("./autoFixEngine");
const { saveRepairTask } = require("./repairTaskLog");
const { createFixCommit } = require("./githubFixExecutor");
const { saveCrossProjectRepairMemory } = require("./crossProjectMemoryRouter");
const { saveErrorPattern } = require("./errorPatternLibrary");
const { isPatchSafe } = require("./safePatchGuard");
const { verifyDeployment } = require("./deploymentVerifier");
const { rollbackIfNeeded } = require("./rollbackController");
const { validateRepairDecision } = require("./validationAI");
const { closeRepairLoop } = require("./closedLoopEngine");

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

    let issue = null;
    let result = null;
    let safety = null;

    if (Array.isArray(data) && data.length > 0) {
      issue = data[0];

      console.log("🚨 New Sentry issue:", issue.title);

      result = classifyIssue(issue.title);

      console.log("🧠 Auto-Fix Classification:");
      console.log("Type:", result.type);
      console.log("Action:", result.action);

      saveRepairTask(issue, result);

      saveCrossProjectRepairMemory({
        project: PROJECT,
        issueTitle: issue.title,
        issueType: result.type,
        action: result.action,
      });

      saveErrorPattern({
        issueTitle: issue.title,
        issueType: result.type,
        detectionPattern: issue.title.toLowerCase(),
        autoFixRule: result.action,
      });

      const newContent = "// Auto-fix placeholder executed";
      safety = isPatchSafe(newContent);
    } else {
      console.log("✅ No new issues");
    }

    const verification = await verifyDeployment();
    console.log("🔎 Deployment status:", verification);

    const validation = validateRepairDecision({
      issue,
      classification: result,
      patchSafety: safety,
      deployment: verification,
    });

    console.log("🤖 Validation AI:", validation);

    if (validation.approved && result && result.type === "missing_dependency") {
      console.log("⚙️ Approved → executing auto-fix...");

      await createFixCommit(
        "worker/fix-log.txt",
        "// Auto-fix placeholder executed",
        "Auto-fix: missing dependency detected"
      );
    } else if (!validation.approved) {
      console.log("⛔ Blocked by Validation AI:", validation.reason);
    }

    const rollback = await rollbackIfNeeded(verification);

    if (rollback.rolledBack) {
      console.log("♻️ Rollback executed:", rollback.reason);
    } else {
      console.log("✅ Rollback not needed");
    }

    closeRepairLoop({
      issue,
      classification: result,
      validation,
      verification,
      rollback,
    });

  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();