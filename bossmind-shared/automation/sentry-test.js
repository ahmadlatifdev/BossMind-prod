require("dotenv").config();
const Sentry = require("@sentry/node");

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
});

try {
  throw new Error("BossMind Test Error");
} catch (e) {
  Sentry.captureException(e);
  console.log("SENTRY_EVENT_SENT");
}
