/**
 * Canonical studio plan IDs and selected-plan resolution for Client Hub.
 * IDs: basic | professional | elite | essential_advanced
 */
const ALLOWED_PLAN_IDS = ["basic", "professional", "elite", "essential_advanced"];

const PLAN_ALIASES = {
  basic: "basic",
  professional: "professional",
  pro: "professional",
  elite: "elite",
  executive: "elite",
  essential_advanced: "essential_advanced",
  "essential-advanced": "essential_advanced",
  essential_advanced_studio: "essential_advanced",
  "essential-foundations": "basic",
  essential_foundations: "basic",
  "essential-foundation": "basic",
  essential_foundation: "basic",
  "professional-career-package": "professional",
  professional_career_package: "professional",
  professional_career: "professional",
  "executive-career-package": "elite",
  executive_career_package: "elite",
  executive_career: "elite",
  essential_career: "essential_advanced",
};

const SERVICE_KEY_TO_PLAN = {
  essential_foundation: "basic",
  professional_career: "professional",
  executive_career: "elite",
  essential_career: "essential_advanced",
  linkedin_optimization: "professional",
  interview_preparation: "elite",
  custom_cover_letter: "professional",
  translation_tls: "basic",
};

const ACTIVE_STUDIO_PLAN_KEY = "rs_active_studio_plan";

function normalizeRawPlanId(raw) {
  return String(raw || "")
    .trim()
    .toLowerCase()
    .replace(/\s+/g, "_");
}

function canonicalPlanId(raw) {
  const key = normalizeRawPlanId(raw);
  if (!key) return "";
  if (ALLOWED_PLAN_IDS.includes(key)) return key;
  if (PLAN_ALIASES[key]) return PLAN_ALIASES[key];
  if (SERVICE_KEY_TO_PLAN[key]) return SERVICE_KEY_TO_PLAN[key];
  const dashed = key.replace(/_/g, "-");
  if (PLAN_ALIASES[dashed]) return PLAN_ALIASES[dashed];
  return "";
}

function isAllowedPlanId(planId) {
  return ALLOWED_PLAN_IDS.includes(planId);
}

/**
 * Pick the single plan the Client Hub should expose.
 * Priority: explicit request → checkout session → persisted client → newest entitlement.
 */
function resolveSelectedPlanId({
  requestedPlanId = "",
  checkoutPlanId = "",
  persistedPlanId = "",
  pendingCheckoutPlanId = "",
  onboardingPlanId = "",
  entitlements = [],
} = {}) {
  const trySources = [
    { id: canonicalPlanId(requestedPlanId), source: "query" },
    { id: canonicalPlanId(checkoutPlanId), source: "checkout_session" },
    { id: canonicalPlanId(persistedPlanId), source: "client_storage" },
    { id: canonicalPlanId(pendingCheckoutPlanId), source: "pending_checkout" },
    { id: canonicalPlanId(onboardingPlanId), source: "onboarding" },
  ];

  const owned = entitlements
    .map((row) => ({
      planId: canonicalPlanId(row.planId || row.plan_id),
      grantedAt: row.grantedAt || row.granted_at || null,
      updatedAt: row.updatedAt || row.updated_at || null,
      createdAt: row.createdAt || row.created_at || null,
    }))
    .filter((row) => row.planId);

  function entitlementSortTime(row) {
    for (const value of [row.grantedAt, row.updatedAt, row.createdAt]) {
      if (!value) continue;
      const t = new Date(value).getTime();
      if (!Number.isNaN(t)) return t;
    }
    return 0;
  }

  for (const candidate of trySources) {
    if (!candidate.id) continue;
    if (candidate.source === "checkout_session" || candidate.source === "query") {
      return { planId: candidate.id, source: candidate.source };
    }
    if (!owned.length || owned.some((row) => row.planId === candidate.id)) {
      return { planId: candidate.id, source: candidate.source };
    }
  }

  if (owned.length) {
    const newest = [...owned].sort((a, b) => entitlementSortTime(b) - entitlementSortTime(a))[0];
    return { planId: newest.planId, source: "newest_entitlement" };
  }

  return { planId: "", source: "none" };
}

function narrowPlansToSelected(plans, selectedPlanId) {
  const id = canonicalPlanId(selectedPlanId);
  if (!id || !Array.isArray(plans) || !plans.length) return [];
  const match = plans.find((plan) => canonicalPlanId(plan.planId) === id);
  return match ? [match] : [];
}

function readSelectedStudioPlan() {
  if (typeof sessionStorage === "undefined") return "";
  try {
    return canonicalPlanId(sessionStorage.getItem(ACTIVE_STUDIO_PLAN_KEY));
  } catch {
    return "";
  }
}

function persistSelectedStudioPlan(planId) {
  const id = canonicalPlanId(planId);
  if (!id || typeof sessionStorage === "undefined") return;
  try {
    sessionStorage.setItem(ACTIVE_STUDIO_PLAN_KEY, id);
  } catch {
    /* ignore */
  }
}

function clearSelectedStudioPlan() {
  if (typeof sessionStorage === "undefined") return;
  try {
    sessionStorage.removeItem(ACTIVE_STUDIO_PLAN_KEY);
  } catch {
    /* ignore */
  }
}

module.exports = {
  ALLOWED_PLAN_IDS,
  ACTIVE_STUDIO_PLAN_KEY,
  canonicalPlanId,
  isAllowedPlanId,
  resolveSelectedPlanId,
  narrowPlansToSelected,
  readSelectedStudioPlan,
  persistSelectedStudioPlan,
  clearSelectedStudioPlan,
};
