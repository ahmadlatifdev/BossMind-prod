/**
 * Canonical Resumora plan registry — server-side source of truth.
 * Ahmed lock 2026-07-26: one-time payments only; edits 1/2/3/0.
 * Prices remain Basic $19 (locked; request text said $29 — not applied).
 * Client may submit planId only; amounts/mode/edits resolved here.
 */

const { FREE_EDITS_BY_PLAN } = require("./plan-policy");

const CANONICAL_PLANS = Object.freeze({
  basic: Object.freeze({
    planId: "basic",
    displayName: "Basic",
    amountCents: 1900,
    currency: "usd",
    paymentMode: "payment",
    freeEdits: 1,
    isTutorialOnly: false,
    entitlementKey: "basic",
    successPath: "/studio",
    cancelPath: "/pricing",
    active: true,
    configVersion: "resumora-one-time-20260726",
  }),
  professional: Object.freeze({
    planId: "professional",
    displayName: "Balanced",
    amountCents: 4900,
    currency: "usd",
    paymentMode: "payment",
    freeEdits: 2,
    isTutorialOnly: false,
    entitlementKey: "professional",
    successPath: "/studio",
    cancelPath: "/pricing",
    active: true,
    configVersion: "resumora-one-time-20260726",
  }),
  elite: Object.freeze({
    planId: "elite",
    displayName: "Professional",
    amountCents: 7900,
    currency: "usd",
    paymentMode: "payment",
    freeEdits: 3,
    isTutorialOnly: false,
    entitlementKey: "elite",
    successPath: "/studio",
    cancelPath: "/pricing",
    active: true,
    configVersion: "resumora-one-time-20260726",
  }),
  essential_advanced: Object.freeze({
    planId: "essential_advanced",
    displayName: "Advanced",
    amountCents: 11000,
    currency: "usd",
    paymentMode: "payment",
    freeEdits: 0,
    isTutorialOnly: true,
    description: "Tutorial videos and tips only",
    entitlementKey: "essential_advanced",
    successPath: "/studio/essential-advanced",
    cancelPath: "/pricing",
    active: true,
    configVersion: "resumora-one-time-20260726",
  }),
});

function getCanonicalPlan(planId) {
  return CANONICAL_PLANS[planId] || null;
}

function assertEditsMatchPolicy() {
  for (const [id, plan] of Object.entries(CANONICAL_PLANS)) {
    if (plan.freeEdits !== FREE_EDITS_BY_PLAN[id]) {
      throw new Error(`EDIT_MISMATCH: ${id} registry=${plan.freeEdits} policy=${FREE_EDITS_BY_PLAN[id]}`);
    }
  }
  return true;
}

module.exports = {
  CANONICAL_PLANS,
  getCanonicalPlan,
  assertEditsMatchPolicy,
  REGISTRY_VERSION: "resumora-one-time-20260726",
};
