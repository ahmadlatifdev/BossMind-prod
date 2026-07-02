require("../../../lib/shared/ensure-project-env");
const { readEngagementActor } = require("../../../lib/engagement/http-context");
const {
  parseCookies,
  readCookieHeader,
  readSessionToken,
} = require("../../../lib/engagement/cookies");
const { ensureEngagementSchema } = require("../../../lib/shared/neon-memory");
const { getWorkspaceOverview } = require("../../../lib/client/workspace-store");
const {
  activateBySessionId,
  retryActivateForActor,
} = require("../../../lib/client/entitlement-activation");
const { scopeStudioPlans } = require("../../../lib/client/studio-plan-scope");
const { getOnboardingState } = require("../../../lib/client/onboarding-journey");
const { canonicalPlanId } = require("../../../lib/client/plan-resolver");
const { captureRouteError } = require("../../../lib/observability/capture-route-error");
const { saveEvent } = require("../../../lib/shared/neon-memory");

const PROJECT_KEY = () => process.env.BOSSMIND_PROJECT_KEY || "resumora";

async function logWorkspaceTiming(payload) {
  try {
    await saveEvent({
      projectKey: PROJECT_KEY(),
      eventType: "studio.workspace.timing",
      severity: "info",
      source: "api.client.workspace",
      eventKey: `timing:${Date.now()}`,
      payload,
    });
  } catch {
    /* non-blocking */
  }
}

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const startedAt = Date.now();
  const timings = { startedAt };
  const lang = String(req.query.lang || "en").toLowerCase() === "fr" ? "fr" : "en";
  const sessionId = String(req.query.session_id || "").trim();
  const requestedPlanId = canonicalPlanId(req.query.planId || req.query.plan || "");

  try {
    res.setHeader("Cache-Control", "private, no-store, max-age=0");

    const schemaStarted = Date.now();
    const schema = await ensureEngagementSchema();
    timings.schemaMs = Date.now() - schemaStarted;

    if (schema?.enabled === false) {
      timings.totalMs = Date.now() - startedAt;
      console.error("[workspace] engagement_schema_unavailable", { reason: schema.reason, timings });
      captureRouteError(new Error(schema.reason || "engagement_schema_unavailable"), req, {
        route: "/api/client/workspace",
        errorType: "database_error",
        severity: "error",
        statusCode: 503,
      }).catch(() => {});
      return res.status(503).json({
        ok: false,
        signedIn: false,
        hasAccess: false,
        plans: [],
        selectedPlanId: null,
        error: "database_unavailable",
      });
    }

    const authStarted = Date.now();
    const cookies = parseCookies(readCookieHeader(req));
    const hasSessionCookie = Boolean(readSessionToken(cookies));
    const actor = await readEngagementActor(req, res);
    timings.authMs = Date.now() - authStarted;

    if (!actor.profileId) {
      timings.totalMs = Date.now() - startedAt;
      logWorkspaceTiming({ ...timings, signedIn: false, hasSessionCookie, sessionId: Boolean(sessionId) });
      return res.status(200).json({
        ok: true,
        signedIn: false,
        hasAccess: false,
        plans: [],
        selectedPlanId: null,
      });
    }

    let activationMeta = null;
    if (sessionId) {
      const activationStarted = Date.now();
      activationMeta = await activateBySessionId(sessionId, actor, lang).catch(() => null);
      timings.activationMs = Date.now() - activationStarted;
    }

    const workspaceStarted = Date.now();
    let base = await getWorkspaceOverview(actor.profileId, actor.profileEmail, lang);
    timings.workspaceMs = Date.now() - workspaceStarted;

    if (!base.plans?.length && sessionId) {
      const retryStarted = Date.now();
      const retry = await retryActivateForActor(actor, {
        sessionId,
        email: actor.profileEmail,
        lang,
      }).catch(() => null);
      timings.retryMs = Date.now() - retryStarted;
      if (retry?.result) activationMeta = retry.result;
      base = await getWorkspaceOverview(actor.profileId, actor.profileEmail, lang);
    }

    let plans = base.plans;

    if (!plans.length && activationMeta?.planId) {
      plans = [
        {
          planId: activationMeta.planId,
          documents: [],
          generationStatus: "queued",
        },
      ];
    }

    const onboarding = sessionId
      ? await getOnboardingState(actor.profileId, lang).catch(() => null)
      : null;

    const scoped = scopeStudioPlans({
      plans,
      lang,
      requestedPlanId,
      checkoutPlanId: sessionId && activationMeta?.planId ? activationMeta.planId : "",
      onboardingPlanId: onboarding?.activePlanId || "",
    });

    const ownedPlanIds = plans.map((plan) => canonicalPlanId(plan.planId)).filter(Boolean);
    const fulfillmentOk = activationMeta?.planActivated === true;
    timings.totalMs = Date.now() - startedAt;
    logWorkspaceTiming({ ...timings, signedIn: true, planCount: scoped.plans?.length || 0 });

    return res.status(200).json({
      ok: true,
      signedIn: true,
      email: actor.profileEmail || null,
      hasAccess: scoped.hasAccess,
      fulfillmentOk,
      planId: scoped.planId,
      selectedPlanId: scoped.selectedPlanId,
      selectedPlanName: scoped.selectedPlanName || scoped.displayName || null,
      selectedPlanSource: scoped.selectedPlanSource,
      displayName: scoped.displayName || activationMeta?.displayName || null,
      stripeCheckoutEmail: activationMeta?.stripeCheckoutEmail || null,
      supportEmail: process.env.RESUMORA_SUPPORT_EMAIL || "support@resumora.net",
      ownedPlanIds,
      plans: scoped.plans,
      duplicateActiveEntitlements: scoped.duplicateActiveEntitlements === true,
      entitlementCount: scoped.entitlementCount || ownedPlanIds.length,
      scopedPlansCount: scoped.scopedPlansCount ?? scoped.plans?.length ?? 0,
      activation: {
        paymentConfirmed: scoped.hasAccess,
        planActivated: scoped.hasAccess,
        workspaceReady: scoped.hasAccess,
        uploadsUnlocked: scoped.hasAccess,
        generationReady: scoped.hasAccess,
      },
    });
  } catch (e) {
    timings.totalMs = Date.now() - startedAt;
    console.error("[workspace] server_error", { message: e.message, timings });
    captureRouteError(e, req, {
      route: "/api/client/workspace",
      errorType: "api_error",
      statusCode: 500,
    }).catch(() => {});
    return res.status(500).json({
      ok: false,
      signedIn: false,
      hasAccess: false,
      plans: [],
      selectedPlanId: null,
      error: "server_error",
    });
  }
}
