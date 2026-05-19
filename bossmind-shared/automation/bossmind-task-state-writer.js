const fs = require("fs");
const { Client } = require("pg");

async function main() {
  const payloadPath = "D:/BossMind/bossmind-shared/logs/temp-payload.json";
  const data = JSON.parse(fs.readFileSync(payloadPath, "utf8"));

  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    INSERT INTO bossmind_task_state (project, last_status, last_reason, metadata)
    VALUES ($1, $2, $3, $4)
  `, [
    data.project,
    data.status,
    data.reason,
    data
  ]);

  await client.end();

  console.log("Task-state updated");
}

main().catch(err => {
  console.error("Task-state write FAILED:", err.message);
  process.exit(1);
});