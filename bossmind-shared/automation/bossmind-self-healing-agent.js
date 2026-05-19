const { Client } = require("pg");

async function main() {
  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  const res = await client.query(`
    SELECT * FROM bossmind_error_memory
    ORDER BY id DESC
    LIMIT 5
  `);

  if (res.rows.length === 0) {
    console.log("No errors detected.");
    await client.end();
    return;
  }

  for (const row of res.rows) {
    console.log("Detected error:", row.error_message);

    // Basic auto-heal logic (placeholder)
    console.log("Auto-heal action triggered for:", row.project);
  }

  await client.end();
}

main().catch(err => {
  console.error("Self-healing failed:", err.message);
  process.exit(1);
});