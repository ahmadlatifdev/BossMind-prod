const fs = require("fs");
const path = require("path");

function savePendingAutomation(payload) {
  const dir = path.join(__dirname, "bossmind-shared", "n8n-pending");
  fs.mkdirSync(dir, { recursive: true });

  const file = path.join(dir, "pending-" + Date.now() + ".json");
  fs.writeFileSync(file, JSON.stringify(payload, null, 2));

  console.log("N8N fallback queue saved:", file);
  return { ok: true, mode: "fallback_queue", file };
}

async function notifyN8N(payload) {
  const url = process.env.N8N_WEBHOOK_URL;

  if (!url || url.includes("your-") || url.includes("REAL-") || url.includes("PASTE_")) {
    return savePendingAutomation(payload);
  }

  const res = await fetch(url, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(payload)
  });

  console.log("n8n webhook status:", res.status);
  return { ok: res.ok, status: res.status };
}

module.exports = { notifyN8N };
