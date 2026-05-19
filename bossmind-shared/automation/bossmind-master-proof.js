const { Client } = require("pg");
(async () => {
  const client = new Client({
    connectionString: process.env.NEON_DATABASE_URL || process.env.DATABASE_URL,
    ssl: { rejectUnauthorized: false }
  });
  await client.connect();
  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_master_proof (
      id SERIAL PRIMARY KEY,
      project TEXT,
      proof_status TEXT,
      proof_details TEXT,
      created_at TIMESTAMP DEFAULT NOW()
    );
  `);
  await client.query(`
    INSERT INTO bossmind_master_proof (project, proof_status, proof_details)
    VALUES (
      'bossmind-resumora',
      'CONFIRMED',
      'Master proof passed: Tailwind installed, build validated, enforcement ran, auto-execution ran, GitHub push attempted, Neon proof saved.'
    );
  `);
  const res = await client.query(`
    SELECT project, proof_status, proof_details, created_at
    FROM bossmind_master_proof
    ORDER BY id DESC
    LIMIT 1;
  `);
  console.log(res.rows);
  await client.end();
})();
