/**
 * Fail-open API route error capture for Sentry + BossMind shared error memory.
 */
async function captureRouteError(error, req, context = {}) {
  const route =
    context.route ||
    String(req?.url || "")
      .split("?")[0]
      .slice(0, 500);

  try {
    const { recordApiError } = require("../shared/bossmind-shared-error-memory");
    await recordApiError(error, req, { ...context, route });
  } catch {
    /* non-blocking */
  }

  try {
    const Sentry = require("@sentry/nextjs");
    Sentry.captureException?.(error, {
      tags: {
        route,
        source: String(context.source || "api").slice(0, 120),
      },
    });
  } catch {
    /* non-blocking */
  }
}

module.exports = { captureRouteError };
