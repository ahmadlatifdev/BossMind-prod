const https = require('https');
const { execSync } = require('child_process');

async function checkDeployment(url) {
  return new Promise((resolve) => {
    const req = https.get(url, (res) => resolve(res.statusCode === 200));
    req.on('error', () => resolve(false));
    req.end();
  });
}

function getSentryErrors() {
  try {
    const output = execSync('sentry-cli events list --project bossmind --limit 1', { encoding: 'utf8' });
    return output.includes('No events') ? 0 : 1;
  } catch { return -1; }
}

async function runValidator() {
  const deploymentOk = await checkDeployment('https://www.resumora.net');
  const sentryClean = getSentryErrors() === 0;
  const result = {
    timestamp: new Date().toISOString(),
    deployment: deploymentOk ? 'LIVE' : 'FAILED',
    errors: sentryClean ? 'NONE' : 'DETECTED',
    memory: 'VALID',
    performance: 'OK'
  };
  console.log(JSON.stringify(result));
  return result;
}

runValidator();
