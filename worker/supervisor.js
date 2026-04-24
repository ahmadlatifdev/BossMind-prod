const Sentry = require("@sentry/node");

// Auto-fix engine
const { classifyIssue } = require("./autoFixEngine");

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
    } else {
      console.log("✅ No new issues");
    }
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

setInterval(checkSentryIssues, 60000);
checkSentryIssues();