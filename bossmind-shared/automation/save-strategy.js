const { Client } = require("pg");

(async () => {
  const client = new Client({
    connectionString: process.env.NEON_DATABASE_URL || process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_system_strategies (
      id SERIAL PRIMARY KEY,
      name TEXT,
      strategy TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await client.query(`
    INSERT INTO bossmind_system_strategies (name, strategy)
    VALUES (
      'Sentry Auto-Fix BossMind Strategy',
      'Sentry → Webhook → Neon → DeepSeek → LangGraph → PowerShell → GitHub → Deploy → Verify → Neon Proof → Close Issue'
    );
  `);

  const res = await client.query(`
    SELECT name, created_at
    FROM bossmind_system_strategies
    ORDER BY id DESC
    LIMIT 1
  `);

  console.log(res.rows);

  await client.end();
})();
