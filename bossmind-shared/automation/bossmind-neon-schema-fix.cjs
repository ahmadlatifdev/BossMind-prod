const { Client } = require("pg");

async function main() {
  const client = new Client({
    connectionString: process.env.DATABASE_URL || process.env.NEON_DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`DROP TABLE IF EXISTS bossmind_task_state CASCADE;`);
  await client.query(`DROP TABLE IF EXISTS bossmind_error_memory CASCADE;`);
  await client.query(`DROP TABLE IF EXISTS bossmind_shared_memory CASCADE;`);

  await client.query(`
    CREATE TABLE bossmind_task_state (
      id BIGSERIAL PRIMARY KEY,
      task_key TEXT UNIQUE NOT NULL,
      task_value JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await client.query(`
    CREATE TABLE bossmind_error_memory (
      id BIGSERIAL PRIMARY KEY,
      error_key TEXT UNIQUE NOT NULL,
      error_value JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await client.query(`
    CREATE TABLE bossmind_shared_memory (
      id BIGSERIAL PRIMARY KEY,
      memory_key TEXT UNIQUE NOT NULL,
      memory_value JSONB NOT NULL,
      updated_at TIMESTAMPTZ NOT NULL DEFAULT NOW()
    );
  `);

  await client.end();

  console.log("Neon schema fixed");
}

main().catch(err => {
  console.error("Schema fix failed");
  console.error(err.message);
  process.exit(1);
});
