const { getDeliverableForPlan } = require("./deliverables-catalog");
const {
  canonicalPlanId,
  resolveSelectedPlanId,
  narrowPlansToSelected,
} = require("./plan-resolver");

function decoratePlans(plans, lang) {
  return (plans || []).map((p) => {
    const planId = canonicalPlanId(p.planId || p.plan_id);
    const deliverable = getDeliverableForPlan(planId, lang);
    return {
      ...p,
      planId,
      displayName: deliverable?.displayName || p.displayName || planId,
      studioPath: deliverable?.studioPath || p.studioPath || "/studio",
      features: deliverable?.features || p.features || [],
      freeEditsLabel: deliverable?.freeEditsLabel || p.freeEditsLabel || "",
    };
  });
}

/**
 * Reduce a workspace/hub payload to a single selected plan (server-side).
 */
function scopeStudioPlans({
  plans = [],
  lang = "en",
  requestedPlanId = "",
  checkoutPlanId = "",
  persistedPlanId = "",
  pendingCheckoutPlanId = "",
  onboardingPlanId = "",
}) {
  const decorated = decoratePlans(plans, lang);
  const entitlements = decorated.map((plan) => ({
    planId: plan.planId,
    grantedAt: plan.grantedAt,
  }));

  const { planId: selectedPlanId, source: selectedPlanSource } = resolveSelectedPlanId({
    requestedPlanId,
    checkoutPlanId,
    persistedPlanId,
    pendingCheckoutPlanId,
    onboardingPlanId,
    entitlements,
  });

  const scopedPlans = narrowPlansToSelected(decorated, selectedPlanId);
  const active = scopedPlans[0] || null;
  const duplicateActiveEntitlements = entitlements.length > 1;
  const scopedPlansCount = scopedPlans.length;

  if (duplicateActiveEntitlements) {
    console.info("[studio-plan-scope] duplicate_active_entitlements", {
      entitlementCount: entitlements.length,
      selectedPlanId: active?.planId || selectedPlanId || null,
      selectedPlanSource,
      scopedPlansCount,
    });
  }

  return {
    plans: scopedPlans,
    selectedPlanId: active?.planId || selectedPlanId || null,
    selectedPlanName: active?.displayName || null,
    selectedPlanSource,
    planId: active?.planId || selectedPlanId || null,
    displayName: active?.displayName || null,
    hasAccess: scopedPlans.length > 0,
    duplicateActiveEntitlements,
    entitlementCount: entitlements.length,
    scopedPlansCount,
  };
}

module.exports = {
  decoratePlans,
  scopeStudioPlans,
};
