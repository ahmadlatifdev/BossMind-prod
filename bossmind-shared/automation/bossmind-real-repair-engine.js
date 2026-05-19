const { Client } = require("pg");

async function main() {
  if (!process.env.NEON_DB) {
    throw new Error("NEON_DB environment variable is missing");
  }

  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  const res = await client.query(`
    SELECT id, project, error_type, error_message, fix_action, payload, created_at
    FROM bossmind_error_memory
    ORDER BY id DESC
    LIMIT 1
  `);

  if (res.rows.length === 0) {
    console.log("No repair needed.");
    await client.end();
    return;
  }

  const error = res.rows[0];

  console.log("Repair target:", error.project);
  console.log("Error type:", error.error_type);
  console.log("Error message:", error.error_message);
  console.log("Repair engine ready.");

  await client.end();
}

main().catch(err => {
  console.error("Repair engine failed FULL ERROR:");
  console.error(err);
  process.exit(1);
});