const { Pool } = require("pg");
const fs = require("fs");
const path = require("path");
require("dotenv").config({ path: path.join(__dirname, ".env") });

const pool = new Pool({
  connectionString: process.env.NEON_DATABASE_URL,
  ssl: { rejectUnauthorized: false }
});

const repairLogPath = path.join(__dirname, "memory", "repair-log.json");

async function syncToNeon() {
  const logs = JSON.parse(fs.readFileSync(repairLogPath, "utf8"));
  const latest = logs[logs.length - 1];

  await pool.query(`
    CREATE TABLE IF NOT EXISTS bossmind_repair_logs (
      id TEXT PRIMARY KEY,
      data JSONB,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await pool.query(
    `INSERT INTO bossmind_repair_logs (id, data)
     VALUES ($1, $2)
     ON CONFLICT (id) DO NOTHING`,
    [latest.id, latest]
  );

  console.log("NEON_SYNC_SUCCESS");
  await pool.end();
}

syncToNeon().catch(async (err) => {
  console.error("NEON_SYNC_FAILED");
  console.error(err.message);
  await pool.end().catch(() => {});
  process.exit(1);
});
