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

    const loopStatus = closeRepairLoop({
      issue,
      classification: result,
      validation,
      verification,
      rollback,
    });

    saveDeploymentSnapshot({
      verification,
      loopStatus,
    });

    predictNextRisk({
      verification,
      loopStatus,
    });
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();const Sentry = require("@sentry/node");

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
      "Supervisor scans Sentry, validates requirements, blocks wrong execution, verifies deployment, snapshots result, predicts risk, and avoids unsafe rollback.",
    protectedPreviousState:
      "Do not remove Sentry scan, worker alive loop, Validation AI, closed loop, snapshot deploy, predictive system, rollback controller, safe patch guard, cross-project memory, or error pattern learning.",
    forbiddenChanges: [
      "Do not hardcode SENTRY_TOKEN",
      "Do not re-add node-fetch",
      "Do not remove deployment verification",
      "Do not remove rollback protection",
      "Do not delete existing BossMind project files",
      "Do not modify Resumora locked client design from this worker task",
    ],
    rollbackCheckpoint: "commit d0795e8 + latest live Render worker before Requirement Lock Engine",
    successCondition:
      "Render logs show requirement lock valid, Sentry clean, deployment live, rollback not needed, closed loop clean, predictive risk low.",
  });
}

async function checkSentryIssues() {
  try {
    console.log("Supervisor check: scanning Sentry issues...");

    const requirementLock = buildDefaultRequirementLock();
    const lockValidation = validateRequirementLock(requirementLock);

    console.log("🔐 Requirement Lock:", lockValidation);

    if (!lockValidation.allowed) {
      console.log("⛔ Execution blocked by Requirement Lock:", lockValidation.reason);
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

    const loopStatus = closeRepairLoop({
      issue,
      classification: result,
      validation,
      verification,
      rollback,
    });

    saveDeploymentSnapshot({
      verification,
      loopStatus,
    });

    predictNextRisk({
      verification,
      loopStatus,
    });
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();