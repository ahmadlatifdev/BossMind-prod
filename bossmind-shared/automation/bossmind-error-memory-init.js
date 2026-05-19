const { Client } = require("pg");

async function main() {
  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_error_memory (
      id SERIAL PRIMARY KEY,
      project TEXT,
      error_type TEXT,
      error_message TEXT,
      fix_action TEXT,
      payload JSONB,
      created_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  console.log("Error-memory table ready.");

  await client.end();
}

main().catch(err => {
  console.error("Error-memory init failed:", err.message);
  process.exit(1);
});