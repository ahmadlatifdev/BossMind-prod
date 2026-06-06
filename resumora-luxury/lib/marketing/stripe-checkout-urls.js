/**
 * Stripe Checkout / Payment Link success redirect — always land on /studio (not Stripe host page).
 */
function normalizeBaseUrl(value) {
  return String(value || "")
    .trim()
    .replace(/\/$/, "");
}

function getStripeSuccessBaseUrl() {
  const vercel =
    process.env.VERCEL_URL && !process.env.VERCEL_URL.startsWith("http")
      ? `https://${process.env.VERCEL_URL}`
      : process.env.VERCEL_URL;
  return normalizeBaseUrl(
    process.env.RESUMORA_STRIPE_SUCCESS_BASE_URL ||
      process.env.NEXT_PUBLIC_SITE_URL ||
      vercel ||
      "https://resumora-luxury.vercel.app"
  );
}

function getPlanStudioPath(planId) {
  try {
    const { getDeliverableForPlan } = require("../client/deliverables-catalog");
    return getDeliverableForPlan(planId)?.studioPath || "/studio";
  } catch {
    return planId === "essential_advanced" ? "/studio/essential-advanced" : "/studio";
  }
}

/** Stripe replaces {CHECKOUT_SESSION_ID} on redirect. */
function getStudioCheckoutSuccessUrl(planId) {
  const base = getStripeSuccessBaseUrl();
  const studioPath = planId ? getPlanStudioPath(planId) : "/studio";
  return `${base}${studioPath}?checkout=success&session_id={CHECKOUT_SESSION_ID}`;
}

function getStudioCheckoutCancelUrl(requestOrigin) {
  const base = requestOrigin ? normalizeBaseUrl(requestOrigin) : getStripeSuccessBaseUrl();
  return `${base}/cancel`;
}

function paymentLinkAfterCompletion() {
  return {
    type: "redirect",
    redirect: {
      url: getStudioCheckoutSuccessUrl(),
    },
  };
}

module.exports = {
  getStripeSuccessBaseUrl,
  getPlanStudioPath,
  getStudioCheckoutSuccessUrl,
  getStudioCheckoutCancelUrl,
  paymentLinkAfterCompletion,
};
