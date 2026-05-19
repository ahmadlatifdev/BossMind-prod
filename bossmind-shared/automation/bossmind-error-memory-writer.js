const fs = require("fs");
const { Client } = require("pg");

async function main() {
  const payloadPath = "D:/BossMind/bossmind-shared/logs/temp-payload.json";
  const data = JSON.parse(fs.readFileSync(payloadPath, "utf8"));

  if (!data.error_message) {
    process.exit(0);
  }

  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    INSERT INTO bossmind_error_memory (project, error_type, error_message, fix_action, payload)
    VALUES ($1, $2, $3, $4, $5)
  `, [
    data.project,
    data.error_type || "runtime",
    data.error_message,
    data.fix_action || "auto-fix pending",
    data
  ]);

  await client.end();

  console.log("Error memory saved");
}

main().catch(err => {
  console.error("Error memory FAILED:", err.message);
  process.exit(1);
});