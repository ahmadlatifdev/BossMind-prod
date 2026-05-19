const fs = require("fs");
const { Client } = require("pg");

async function main() {
  const payloadPath = "D:/BossMind/bossmind-shared/logs/temp-payload.json";
  const raw = fs.readFileSync(payloadPath, "utf8");

  let data;
  try {
    data = JSON.parse(raw);
  } catch (e) {
    console.error("Invalid JSON payload");
    process.exit(1);
  }

  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_execution_logs (
      id SERIAL PRIMARY KEY,
      project TEXT,
      status TEXT,
      reason TEXT,
      payload JSONB,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  await client.query(
    `INSERT INTO bossmind_execution_logs (project, status, reason, payload)
     VALUES ($1, $2, $3, $4)`,
    [
      data.project || null,
      data.status || null,
      data.reason || null,
      JSON.stringify(data)
    ]
  );

  await client.end();

  console.log("Neon DB insert OK");
}

main().catch(err => {
  console.error("Neon insert FAILED:", err.message);
  process.exit(1);
});