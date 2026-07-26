/**
 * Stripe Checkout / Payment Link success redirect — always land on resumora.net studio.
 * Rejects forbidden hosts (Render, Vercel, localhost in production, blocked Firebase projects).
 */
function normalizeBaseUrl(value) {
  return String(value || "")
    .trim()
    .replace(/\/$/, "");
}

const FORBIDDEN_HOST_SNIPPETS = [
  "onrender.com",
  "render.com",
  "vercel.app",
  "vercel.com",
  "key-journal-378204",
  "bossmind-resumora-web",
  "northflank",
  "railway.app",
  "squarespace",
];

function assertApprovedAppBase(url) {
  const base = normalizeBaseUrl(url);
  if (!base) {
    throw new Error("CANONICAL_APP_URL_MISSING");
  }
  let host = "";
  try {
    host = new URL(base).hostname.toLowerCase();
  } catch {
    throw new Error("CANONICAL_APP_URL_INVALID");
  }
  const blob = `${base} ${host}`.toLowerCase();
  for (const bad of FORBIDDEN_HOST_SNIPPETS) {
    if (blob.includes(bad)) {
      throw new Error(`FORBIDDEN_CHECKOUT_HOST: ${bad}`);
    }
  }
  const isProd = process.env.NODE_ENV === "production" || process.env.RESUMORA_REQUIRE_PROD_HOST === "1";
  if (isProd && (host === "localhost" || host === "127.0.0.1")) {
    throw new Error("FORBIDDEN_CHECKOUT_HOST: localhost");
  }
  if (isProd && host !== "resumora.net" && !host.endsWith(".resumora.net")) {
    // Allow only resumora.net in production unless explicitly overridden after validation
    if (process.env.RESUMORA_ALLOW_NON_CANONICAL_HOST !== "1") {
      throw new Error(`FORBIDDEN_CHECKOUT_HOST: ${host}`);
    }
  }
  return base;
}

function getStripeSuccessBaseUrl() {
  const raw =
    process.env.RESUMORA_STRIPE_SUCCESS_BASE_URL ||
    process.env.NEXT_PUBLIC_SITE_URL ||
    process.env.NEXT_PUBLIC_BASE_URL ||
    "https://resumora.net";
  return assertApprovedAppBase(raw);
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
  // Prefer canonical app URL; ignore unapproved request origins in production
  let base;
  try {
    base = getStripeSuccessBaseUrl();
  } catch {
    base = "https://resumora.net";
  }
  if (requestOrigin) {
    try {
      const originBase = assertApprovedAppBase(requestOrigin);
      base = originBase;
    } catch {
      /* keep canonical */
    }
  }
  return `${base}/pricing`;
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
  assertApprovedAppBase,
  FORBIDDEN_HOST_SNIPPETS,
};
