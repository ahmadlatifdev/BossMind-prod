/**
 * Unit tests — one-time pricing + edit matrix (Ahmed lock 2026-07-26).
 */
const { describe, it } = require("node:test");
const assert = require("node:assert/strict");
const {
  FREE_EDITS_BY_PLAN,
  getFreeEditsCount,
  auditFreeEditsPolicy,
  freeEditsLabel,
} = require("../lib/client/plan-policy");
const {
  CANONICAL_PLANS,
  getCanonicalPlan,
  assertEditsMatchPolicy,
  REGISTRY_VERSION,
} = require("../lib/client/canonical-plan-registry");
const {
  assertApprovedAppBase,
  getStudioCheckoutCancelUrl,
  getStudioCheckoutSuccessUrl,
} = require("../lib/marketing/stripe-checkout-urls");

describe("edit matrix 1/2/3/0", () => {
  it("matches Ahmed lock", () => {
    assert.equal(getFreeEditsCount("basic"), 1);
    assert.equal(getFreeEditsCount("professional"), 2);
    assert.equal(getFreeEditsCount("elite"), 3);
    assert.equal(getFreeEditsCount("essential_advanced"), 0);
    assert.equal(FREE_EDITS_BY_PLAN.elite, 3);
    assert.equal(FREE_EDITS_BY_PLAN.essential_advanced, 0);
  });

  it("audit passes", () => {
    const a = auditFreeEditsPolicy();
    assert.equal(a.ok, true);
  });

  it("Advanced is tutorial-only label", () => {
    assert.match(freeEditsLabel("essential_advanced", "en"), /Tutorial/i);
    assert.match(freeEditsLabel("essential_advanced", "en"), /0 edits/i);
  });

  it("registry matches policy", () => {
    assert.equal(assertEditsMatchPolicy(), true);
    assert.equal(REGISTRY_VERSION, "resumora-one-time-20260726");
  });
});

describe("canonical one-time prices", () => {
  it("uses locked USD amounts (Basic $19)", () => {
    assert.equal(getCanonicalPlan("basic").amountCents, 1900);
    assert.equal(getCanonicalPlan("professional").amountCents, 4900);
    assert.equal(getCanonicalPlan("elite").amountCents, 7900);
    assert.equal(getCanonicalPlan("essential_advanced").amountCents, 11000);
  });

  it("rejects $99 for Professional", () => {
    assert.notEqual(CANONICAL_PLANS.elite.amountCents, 9900);
  });

  it("payment mode is payment not subscription", () => {
    for (const p of Object.values(CANONICAL_PLANS)) {
      assert.equal(p.paymentMode, "payment");
    }
  });

  it("Advanced is tutorial-only with 0 edits", () => {
    const a = getCanonicalPlan("essential_advanced");
    assert.equal(a.freeEdits, 0);
    assert.equal(a.isTutorialOnly, true);
  });
});

describe("checkout redirect hosts", () => {
  it("allows resumora.net", () => {
    assert.equal(assertApprovedAppBase("https://resumora.net"), "https://resumora.net");
  });

  it("rejects Render", () => {
    assert.throws(() => assertApprovedAppBase("https://bossmind-resumora-web.onrender.com"), /FORBIDDEN/);
  });

  it("rejects Vercel", () => {
    assert.throws(() => assertApprovedAppBase("https://foo.vercel.app"), /FORBIDDEN/);
  });

  it("success URL uses studio path", () => {
    process.env.RESUMORA_STRIPE_SUCCESS_BASE_URL = "https://resumora.net";
    process.env.RESUMORA_ALLOW_NON_CANONICAL_HOST = "1";
    const url = getStudioCheckoutSuccessUrl("basic");
    assert.match(url, /^https:\/\/resumora\.net\/studio\?checkout=success/);
    assert.match(url, /session_id=\{CHECKOUT_SESSION_ID\}/);
  });

  it("cancel URL uses /pricing", () => {
    process.env.RESUMORA_STRIPE_SUCCESS_BASE_URL = "https://resumora.net";
    const url = getStudioCheckoutCancelUrl("https://resumora.net");
    assert.equal(url, "https://resumora.net/pricing");
  });
});
