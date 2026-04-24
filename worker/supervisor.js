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
const { executeRunbookStep } = require("./masterRunbookEngine");
const { validateExecutionBoundary } = require("./executionBoundaryGuard");
const { saveProofLedgerEntry } = require("./automationProofLedger");

const SENTRY_TOKEN = process.env.SENTRY_TOKEN;
const ORG = "bossmind-main-ke";
const PROJECT = "node-express";

console.log("BossMind Self-Healing Supervisor started");

function buildRequirementLock() {
  return createRequirementLock({
    project: "bossmind-prod",
    filePath: "worker/supervisor.js",
    expectedOutput: "Strict execution within locked boundary",
    protectedPreviousState: "All core layers must remain intact",
    forbiddenChanges: [
      "Do not modify unrelated files",
      "Do not extend execution scope",
    ],
    rollbackCheckpoint: "latest stable deploy",
    successCondition: "System runs clean within boundary",
  });
}

async function checkSentryIssues() {
  try {
    console.log("Supervisor check: scanning Sentry issues...");

    executeRunbookStep({
      phase: "START",
      project: PROJECT,
      action: "scan_sentry",
      expectedOutput: "Scan for unresolved issues",
    });

    const requirementLock = buildRequirementLock();
    const lockValidation = validateRequirementLock(requirementLock);

    console.log("🔐 Requirement Lock:", lockValidation);

    if (!lockValidation.allowed) {
      console.log("⛔ Blocked:", lockValidation.reason);
      return;
    }

    const boundaryCheck = validateExecutionBoundary({
      requestedFile: "worker/supervisor.js",
      requirementLock,
    });

    console.log("🛡️ Execution Boundary:", boundaryCheck);

    if (!boundaryCheck.allowed) {
      console.log("⛔ Blocked by Boundary Guard:", boundaryCheck.reason);
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
    let sentryStatus = "clean";

    if (Array.isArray(data) && data.length > 0) {
      issue = data[0];
      sentryStatus = "issue_detected";

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

    let changedFiles = [];

    if (validation.approved && result?.type === "missing_dependency") {
      executeRunbookStep({
        phase: "FIX",
        project: PROJECT,
        action: "auto_fix_commit",
        expectedOutput: "Fix applied via GitHub",
      });

      await createFixCommit(
        "worker/fix-log.txt",
        "// Auto-fix placeholder",
        "Auto-fix"
      );

      changedFiles.push("worker/fix-log.txt");
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

    const prediction = predictNextRisk({ verification, loopStatus });

    // NEW: PROOF LEDGER SAVE
    saveProofLedgerEntry({
      requirementLockId: requirementLock.id,
      allowedFiles: ["worker/supervisor.js"],
      blockedFiles: [],
      changedFiles,
      validationResult: validation,
      deploymentResult: verification,
      rollbackStatus: rollback,
      sentryStatus,
    });

    executeRunbookStep({
      phase: "END",
      project: PROJECT,
      action: "cycle_complete",
      expectedOutput: prediction.riskLevel,
    });
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();