# Read command from Neon
$cmd = node -e "
const { Client } = require('pg');
(async () => {
  const c = new Client({ connectionString: process.env.NEON_DB, ssl: { rejectUnauthorized: false } });
  await c.connect();
  const r = await c.query('SELECT command FROM bossmind_command_queue WHERE executed=false ORDER BY id ASC LIMIT 1');
  if (r.rows.length === 0) { console.log('NONE'); process.exit(0); }
  console.log(r.rows[0].command);
  await c.query('UPDATE bossmind_command_queue SET executed=true WHERE command=$1', [r.rows[0].command]);
  await c.end();
})();
"

if ($cmd -ne "NONE") {
    Write-Host "Executing command from queue: $cmd" -ForegroundColor Yellow
    Invoke-Expression $cmd
}