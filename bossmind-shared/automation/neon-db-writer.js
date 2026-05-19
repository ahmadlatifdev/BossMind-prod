const { Client } = require("pg");

const client = new Client({
  connectionString: process.env.NEON_DB,
  ssl: { rejectUnauthorized: false }
});

async function main() {
  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_execution_logs (
      id SERIAL PRIMARY KEY,
      project TEXT,
      status TEXT,
      reason TEXT,
      project_exists BOOLEAN,
      payload JSONB,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  console.log("Neon table ready.");

  await client.end();
}

main().catch((error) => {
  console.error("Neon writer failed:", error.message);
  process.exit(1);
});