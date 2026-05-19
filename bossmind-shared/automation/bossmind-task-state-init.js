const { Client } = require("pg");

async function main() {
  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_task_state (
      id SERIAL PRIMARY KEY,
      project TEXT,
      last_status TEXT,
      last_reason TEXT,
      last_run TIMESTAMPTZ DEFAULT NOW(),
      metadata JSONB
    );
  `);

  console.log("Task-state table ready.");

  await client.end();
}

main().catch(err => {
  console.error("Task-state init failed:", err.message);
  process.exit(1);
});