/**
 * Fail-open client-side capture for studio hub/workspace API failures.
 * Never sends secrets, cookies, or auth headers — route + status + safe message only.
 */
function safeRoute(url) {
  try {
    const parsed = new URL(String(url || ""), "http://localhost");
    return parsed.pathname.slice(0, 500);
  } catch {
    return String(url || "").split("?")[0].slice(0, 500);
  }
}

function safeMessage(value, max = 240) {
  return String(value || "client_api_error")
    .replace(/(postgresql:\/\/)[^\s]+/gi, "$1[redacted]")
    .replace(/sk_(live|test)_[A-Za-z0-9]+/g, "sk_[redacted]")
    .replace(/pk_(live|test)_[A-Za-z0-9]+/g, "pk_[redacted]")
    .slice(0, max);
}

export function captureClientApiError(error, context = {}) {
  const route = safeRoute(context.route || context.url || "");
  const status = Number(context.status) || 0;
  const source = safeMessage(context.source || "client.studio.api", 120);
  const message = safeMessage(
    context.message || error?.message || `HTTP ${status || "error"} on ${route}`
  );

  try {
    const Sentry = require("@sentry/nextjs");
    Sentry?.captureException?.(error instanceof Error ? error : new Error(message), {
      tags: { route, source, status: String(status || "unknown") },
      extra: { parseError: context.parseError === true },
    });
  } catch {
    /* non-blocking */
  }

  try {
    fetch("/api/client/error-report", {
      method: "POST",
      credentials: "same-origin",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        event: "client_api_error",
        path: route,
        message,
        severity: status >= 500 ? "error" : "warn",
        detail: {
          status,
          source,
          parseError: context.parseError === true,
        },
      }),
    }).catch(() => {});
  } catch {
    /* non-blocking */
  }
}
