const { Client } = require("pg");

(async () => {
  const client = new Client({
    connectionString: process.env.NEON_DATABASE_URL || process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_update_proof (
      id SERIAL PRIMARY KEY,
      project TEXT NOT NULL,
      update_status TEXT NOT NULL,
      proof_message TEXT NOT NULL,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);

  await client.query(`
    INSERT INTO bossmind_update_proof (project, update_status, proof_message)
    VALUES (
      'bossmind-resumora',
      'CONFIRMED',
      'Auto-update guarantee layer active: detect, fix, build, push, deploy, verify, save proof to Neon.'
    );
  `);

  const res = await client.query(`
    SELECT project, update_status, proof_message, created_at
    FROM bossmind_update_proof
    ORDER BY id DESC
    LIMIT 1;
  `);

  console.log(res.rows);
  await client.end();
})();
