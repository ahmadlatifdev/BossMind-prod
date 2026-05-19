const { spawn } = require('child_process');
const fs = require('fs');

function runValidator() {
  return new Promise((resolve) => {
    const proc = spawn('node', ['D:\BossMind\bossmind-shared\automation\optimization-validator.js']);
    let output = '';
    proc.stdout.on('data', d => output += d);
    proc.on('close', () => {
      try {
        const status = JSON.parse(output);
        resolve(status);
      } catch { resolve(null); }
    });
  });
}

async function mainLoop() {
  console.log([LOOP] Optimization cycle started at );
  const status = await runValidator();
  if (status && status.deployment !== 'LIVE') {
    console.log('[LOOP] Deployment degraded – triggering auto‑healing');
    const { exec } = require('child_process');
    exec('cd D:\BossMind\resumora-fresh && git push origin main --force', (err, out) => {
      console.log(err || out);
    });
  } else if (status) {
    console.log('[LOOP] System optimized – saving snapshot lock');
    fs.writeFileSync('D:\BossMind\bossmind-shared\automation\\last_optimized_lock.json', JSON.stringify(status, null, 2));
  }
  setTimeout(mainLoop, 120000);
}

mainLoop();
