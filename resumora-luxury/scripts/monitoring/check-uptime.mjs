#!/usr/bin/env node
/**
 * Uptime probe for resumora-luxury. Exits 1 on failure so CI/cron can alert.
 * Set ALERT_WEBHOOK_URL (Slack/Discord) and/or ALERT_EMAIL_TO (logged; wire via webhook).
 */
const url = process.env.UPTIME_URL || "https://resumora-luxury.vercel.app/api/health?lite=1";
const maxMs = Number(process.env.UPTIME_MAX_MS || 5000);
const webhook = process.env.ALERT_WEBHOOK_URL || "";
const emailTo = process.env.ALERT_EMAIL_TO || "";

async function sendAlert(payload) {
  if (webhook) {
    try {
      await fetch(webhook, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          text: payload.message,
          blocks: [
            {
              type: "section",
              text: { type: "mrkdwn", text: payload.message },
            },
          ],
        }),
      });
    } catch (err) {
      console.error("[uptime] webhook alert failed:", err.message);
    }
  }
  if (emailTo) {
    console.error(`[uptime] email alert target=${emailTo} message=${payload.message}`);
  }
}

async function main() {
  const started = Date.now();
  let ok = false;
  let status = 0;
  let body = "";

  try {
    const res = await fetch(url, { signal: AbortSignal.timeout(maxMs) });
    status = res.status;
    body = await res.text();
    ok = res.ok;
  } catch (err) {
    const elapsed = Date.now() - started;
    const message = `🔴 Resumora Luxury DOWN — ${url} — ${err.message} (${elapsed}ms)`;
    console.error(message);
    await sendAlert({ message });
    process.exit(1);
  }

  const elapsed = Date.now() - started;
  if (!ok || elapsed > maxMs) {
    const message = `🔴 Resumora Luxury unhealthy — HTTP ${status} in ${elapsed}ms — ${body.slice(0, 200)}`;
    console.error(message);
    await sendAlert({ message });
    process.exit(1);
  }

  console.log(`✅ Uptime OK — HTTP ${status} in ${elapsed}ms — ${url}`);
}

main();
