const { performance } = require('perf_hooks');
const { execSync } = require('child_process');

function measureApiLatency(url) {
  const start = performance.now();
  try {
    execSync(curl -s -o /dev/null -w "%{time_total}" , { timeout: 5000 });
  } catch(e) { return -1; }
  return performance.now() - start;
}

function logToNeon(metric) {
  // In production, insert into performance_log table
  console.log([METRIC] );
}

setInterval(() => {
  const latency = measureApiLatency('https://www.resumora.net');
  if (latency > 0) logToNeon(pi_latency_ms:);
}, 60000);
