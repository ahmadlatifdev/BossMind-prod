require("dotenv").config();
const Sentry = require("@sentry/node");

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0
});

console.log("BossMind worker started");

setTimeout(() => {
  Sentry.captureException(new Error("BossMind Render Worker Sentry test error"));
  console.log("Sentry test error sent");
}, 3000);

setInterval(() => {
  console.log("BossMind worker alive");
}, 60000);
