const Sentry = require("@sentry/nextjs");

const dsn = process.env.SENTRY_DSN;

if (dsn) {
  Sentry.init({
    dsn,
    tracesSampleRate: 0.05,
    environment: process.env.NODE_ENV || "development",
    beforeSend(event) {
      try {
        const { recordSentryMirror } = require("./lib/shared/bossmind-shared-error-memory");
        const ex = event.exception?.values?.[0];
        recordSentryMirror({
          eventId: event.event_id,
          errorType: ex?.type || event.transaction || "sentry_server_error",
          errorMessage: ex?.value || event.message || "Sentry server event",
          level: event.level,
          environment: event.environment,
          projectKey: process.env.BOSSMIND_PROJECT_KEY || "resumora",
        }).catch(() => {});
        const proof = require("./lib/shared/bossmind-memory-proof");
        proof.markSentryDetectionReady({ eventId: event.event_id || null }).catch(() => {});
      } catch {
        /* non-blocking */
      }
      return event;
    },
  });
}

module.exports = Sentry;
