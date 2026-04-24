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
const { saveDeploymentSnapshot } = require("./snapshotDeployEngine");
const { predictNextRisk } = require("./predictiveSystem");
const {
  createRequirementLock,
  validateRequirementLock,
} = require("./requirementLockEngine");

const SENTRY_TOKEN = process.env.SENTRY_TOKEN;
const ORG = "bossmind-main-ke";
const PROJECT = "node-express";

console.log("BossMind Self-Healing Supervisor started");

function buildDefaultRequirementLock() {
  return createRequirementLock({
    project: "bossmind-prod",
    filePath: "worker/supervisor.js",
    expectedOutput:
      "Supervisor full automation + validation + lock + deploy verify + snapshot + prediction",
    protectedPreviousState:
      "Do not remove core automation layers",
    forbiddenChanges: [
      "Do not hardcode SENTRY_TOKEN",
      "Do not re-add node-fetch",
    ],
    rollbackCheckpoint: "latest stable deploy",
    successCondition: "logs show clean + no issues",
  });
}

async function checkSentryIssues() {
  try {
    console.log("Supervisor check: scanning Sentry issues...");

    const requirementLock = buildDefaultRequirementLock();
    const lockValidation = validateRequirementLock(requirementLock);

    console.log("🔐 Requirement Lock:", lockValidation);

    if (!lockValidation.allowed) {
      console.log("⛔ Blocked:", lockValidation.reason);
      return;
    }

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

      console.log("🚨 Issue:", issue.title);

      result = classifyIssue(issue.title);

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

      const newContent = "// Auto-fix placeholder";
      safety = isPatchSafe(newContent);
    } else {
      console.log("✅ No new issues");
    }

    const verification = await verifyDeployment();
    console.log("🔎 Deployment:", verification);

    const validation = validateRepairDecision({
      issue,
      classification: result,
      patchSafety: safety,
      deployment: verification,
    });

    console.log("🤖 Validation:", validation);

    if (validation.approved && result?.type === "missing_dependency") {
      await createFixCommit(
        "worker/fix-log.txt",
        "// Auto-fix placeholder",
        "Auto-fix"
      );
    } else {
      console.log("⛔ Blocked by Validation");
    }

    const rollback = await rollbackIfNeeded(verification);

    console.log(
      rollback.rolledBack ? "♻️ Rollback executed" : "✅ No rollback"
    );

    const loopStatus = closeRepairLoop({
      issue,
      classification: result,
      validation,
      verification,
      rollback,
    });

    saveDeploymentSnapshot({ verification, loopStatus });

    predictNextRisk({ verification, loopStatus });
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();