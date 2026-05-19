const { Client } = require("pg");

async function main() {
  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  const state = {
    ui_buttons: [
      { name: "Test Command", command: "Write-Host BossMind TEST OK" },
      { name: "Pull Latest Code", command: "git pull" },
      { name: "Install Dependencies", command: "npm install" },
      { name: "Restart Services", command: "pm2 restart all" }
    ],
    version: "v1.0",
    modules: {
      execution: true,
      task_state: true,
      error_memory: true,
      self_healing: true,
      repair_engine: true
    }
  };

  await client.query(
    `INSERT INTO bossmind_system_state (key, value)
     VALUES ($1, $2)
     ON CONFLICT (key)
     DO UPDATE SET value = $2, updated_at = NOW()`,
    ["system_config", state]
  );

  console.log("System state saved");

  await client.end();
}

main().catch(err => {
  console.error("System state FAILED:", err.message);
  process.exit(1);
});