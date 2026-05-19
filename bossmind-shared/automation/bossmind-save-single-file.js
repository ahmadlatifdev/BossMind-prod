const fs = require("fs");
const { Client } = require("pg");

async function main() {
  const filePath = process.argv[2];

  if (!filePath || !fs.existsSync(filePath)) {
    process.exit(0);
  }

  const content = fs.readFileSync(filePath, "utf8");

  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_code_memory (
      file_path TEXT PRIMARY KEY,
      content TEXT,
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  await client.query(
    `INSERT INTO bossmind_code_memory (file_path, content)
     VALUES ($1, $2)
     ON CONFLICT (file_path)
     DO UPDATE SET content = $2, updated_at = NOW()`,
    [filePath, content]
  );

  await client.end();

  console.log("Saved:", filePath);
}

main().catch(err => {
  console.error("Single file save failed:", err.message);
  process.exit(1);
});