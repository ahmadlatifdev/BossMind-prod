const { Client } = require("pg");

async function main() {
  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_system_state (
      id SERIAL PRIMARY KEY,
      key TEXT UNIQUE,
      value JSONB,
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  console.log("System-state table ready.");

  await client.end();
}

main().catch(err => {
  console.error("System-state init failed:", err.message);
  process.exit(1);
});