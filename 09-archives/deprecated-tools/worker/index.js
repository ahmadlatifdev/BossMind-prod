require("./supervisor");
const Sentry = require("@sentry/node");

Sentry.init({
  dsn: "https://216ffa4485f88b8250100eee059110b5@o4511260643229696.ingest.us.sentry.io/4511260644474880",
  tracesSampleRate: 1.0,
  environment: "production",
});

async function runWorker() {
  console.log("BossMind worker started");

  setInterval(() => {
    console.log("BossMind worker alive");
  }, 60000);
}

runWorker().catch(async (error) => {
  Sentry.captureException(error);
  await Sentry.flush(5000);
  process.exit(1);
});
try { require('./futureAutomationEngine').startFutureAutomationEngine(); } catch(e) { console.log('Future automation engine safe-skip:', e.message); }
// LOCKED_BASELINE_95_PERCENT
