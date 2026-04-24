const Sentry = require("@sentry/node");
// Use secure environment variable (DO NOT hardcode token)
const SENTRY_TOKEN = process.env.SENTRY_TOKEN;

// Your Sentry org + project
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
      console.log("🚨 New Sentry issue detected:", data[0].title);
    } else {
      console.log("✅ No new issues");
    }
  } catch (err) {
    console.log("Supervisor error:", err.message);
  }
}

// Run every 60 seconds
setInterval(checkSentryIssues, 60000);

// Run immediately on start
checkSentryIssues();