require("../../../lib/shared/ensure-project-env");
const { readEngagementActor } = require("../../../lib/engagement/http-context");
const { ensureEngagementSchema } = require("../../../lib/shared/neon-memory");
const { listEntitlementsForUser } = require("../../../lib/client/entitlements-store");
const { scopeStudioPlans } = require("../../../lib/client/studio-plan-scope");
const { activateBySessionId } = require("../../../lib/client/entitlement-activation");
const { getOnboardingState } = require("../../../lib/client/onboarding-journey");
const { canonicalPlanId } = require("../../../lib/client/plan-resolver");
const { getDeliverableForPlan } = require("../../../lib/client/deliverables-catalog");

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const lang = String(req.query.lang || "en").toLowerCase() === "fr" ? "fr" : "en";
  const sessionId = String(req.query.session_id || "").trim();
  const requestedPlanId = canonicalPlanId(req.query.planId || req.query.plan || "");

  try {
    res.setHeader("Cache-Control", "private, no-store, max-age=0");
    await ensureEngagementSchema();
    const actor = await readEngagementActor(req, res);
    const rows = await listEntitlementsForUser(actor.profileId, actor.profileEmail);

    let activationMeta = null;
    if (sessionId && actor.profileId) {
      activationMeta = await activateBySessionId(sessionId, actor, lang).catch(() => null);
    }

    const onboarding = actor.profileId
      ? await getOnboardingState(actor.profileId, lang).catch(() => null)
      : null;

    const scoped = scopeStudioPlans({
      plans: rows.map((row) => ({
        planId: row.plan_id,
        grantedAt: row.granted_at,
        welcomeDownloadUrl: null,
        freeEdits: null,
      })),
      lang,
      requestedPlanId,
      checkoutPlanId: sessionId && activationMeta?.planId ? activationMeta.planId : "",
      onboardingPlanId: onboarding?.activePlanId || "",
    });

    const plans = scoped.plans.map((plan) => {
      const row = rows.find((entry) => entry.plan_id === plan.planId);
      const deliverable = getDeliverableForPlan(plan.planId, lang);
      return {
        planId: plan.planId,
        grantedAt: row?.granted_at || plan.grantedAt || null,
        displayName: plan.displayName,
        studioPath: plan.studioPath,
        welcomeDownloadUrl: deliverable?.welcomeAssetId
          ? `/api/client/download?assetId=${encodeURIComponent(deliverable.welcomeAssetId)}&planId=${encodeURIComponent(plan.planId)}&lang=${lang}`
          : null,
        features: plan.features,
        freeEdits: deliverable?.freeEdits ?? 0,
        freeEditsLabel: plan.freeEditsLabel,
      };
    });

    const ownedPlanIds = rows
      .map((row) => canonicalPlanId(row.plan_id))
      .filter(Boolean);

    return res.status(200).json({
      ok: true,
      signedIn: Boolean(actor.profileId),
      email: actor.profileEmail || null,
      lang,
      plans,
      ownedPlanIds,
      selectedPlanId: scoped.selectedPlanId,
      selectedPlanName: scoped.selectedPlanName || scoped.displayName || null,
      selectedPlanSource: scoped.selectedPlanSource,
      planId: scoped.planId,
      hasAccess: scoped.hasAccess,
      duplicateActiveEntitlements: scoped.duplicateActiveEntitlements === true,
      entitlementCount: scoped.entitlementCount || ownedPlanIds.length,
      scopedPlansCount: scoped.scopedPlansCount ?? plans.length,
    });
  } catch (e) {
    return res.status(500).json({ error: e.message || "Server error" });
  }
}
