/**
 * Locked Stripe Payment Link URLs per plan (works without STRIPE_SECRET_KEY on server).
 */
let LOCK = null;
try {
  LOCK = require("../../config/resumora-stripe-payment-links-lock.json");
} catch {
  LOCK = null;
}

function resolvePaymentLinkUrl(planId) {
  const url = LOCK?.planRoutes?.[planId]?.paymentLinkUrl;
  return typeof url === "string" && url.startsWith("https://") ? url : "";
}

function paymentLinksReady() {
  const routes = LOCK?.planRoutes || {};
  return ["basic", "professional", "elite", "essential_advanced"].every((p) =>
    Boolean(routes[p]?.paymentLinkUrl)
  );
}

module.exports = { resolvePaymentLinkUrl, paymentLinksReady };
