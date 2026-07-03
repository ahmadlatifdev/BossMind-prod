const Sentry = require("@sentry/nextjs");

const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    tracesSampleRate: 0.05,
  });
}

module.exports = Sentry;
