import { useCallback, useMemo, useState } from "react";
import { setPendingCheckoutPlan } from "@/lib/marketing/checkout-plan-persistence";
import { QUOTE_STORAGE_KEY } from "@/lib/marketing/service-quote-pricing";
import { resolveStripePriceId } from "@/lib/marketing/stripe-plan-map";
import { resolvePaymentLinkUrl } from "@/lib/marketing/stripe-plan-payment-link";
import { pricingPlans } from "@/lib/marketing/site-copy";
import { freeEditsLabel } from "@/lib/client/plan-policy";
import { officialPlanStripeName } from "@/lib/marketing/bossmind-brand-authority.constants";
import { trackGa4 } from "@/lib/marketing/resumora-ga4-events";

function logStripeInternal(code, payload) {
  console.error(`[Resumora Stripe:${code}]`, payload);
}

function readAlignedServiceDraft(planId) {
  if (typeof window === "undefined") return "";
  try {
    const raw = sessionStorage.getItem(QUOTE_STORAGE_KEY);
    if (!raw) return "";
    const b = JSON.parse(raw);
    if (b?.quote?.tier !== planId) return "";
    return typeof b.metaCompact === "string" ? b.metaCompact : "";
  } catch {
    return "";
  }
}

export function useStripePlans() {
  return useMemo(
    () =>
      pricingPlans.map((plan) => ({
        ...plan,
        priceId: resolveStripePriceId(plan.id),
      })),
    []
  );
}

function readUtmFromLocation() {
  if (typeof window === "undefined") {
    return { utm_source: "", utm_medium: "", utm_campaign: "" };
  }
  try {
    const p = new URLSearchParams(window.location.search);
    return {
      utm_source: p.get("utm_source") || "",
      utm_medium: p.get("utm_medium") || "",
      utm_campaign: p.get("utm_campaign") || "",
    };
  } catch {
    return { utm_source: "", utm_medium: "", utm_campaign: "" };
  }
}

function userFacingCheckoutError(status, data) {
  if (status === 503) {
    return "Payment service is not available (check STRIPE_SECRET_KEY on the server).";
  }
  if (data && typeof data.error === "string" && data.error.length > 0) {
    return data.error.length > 180 ? `${data.error.slice(0, 177)}…` : data.error;
  }
  if (status === 400) {
    return "Checkout was rejected (often missing or invalid Stripe Price IDs).";
  }
  return "Checkout could not start. See the console for details.";
}

function redirectToPaymentLink(planId, pageLang) {
  const url = resolvePaymentLinkUrl(planId);
  if (!url || typeof window === "undefined") return false;
  trackGa4("begin_checkout", {
    plan_id: planId,
    currency: "USD",
    flow: "payment_link",
    locale: pageLang,
  });
  window.location.assign(url);
  return true;
}

export function useStripeCheckout(activeLang = "en") {
  const [busyPlan, setBusyPlan] = useState("");
  const [checkoutError, setCheckoutError] = useState("");
  const [checkoutSummary, setCheckoutSummary] = useState(null);
  const dynamicPlans = useStripePlans();
  const pageLang = activeLang === "fr" ? "fr" : "en";

  const handleCheckout = useCallback(async (planId, planName, planPrice) => {
    setCheckoutError("");
    const planMeta = dynamicPlans.find((p) => p.id === planId);
    const priceId = planMeta?.priceId || "";
    const paymentLink = resolvePaymentLinkUrl(planId);

    if (!priceId && !paymentLink) {
      setCheckoutError(
        `Stripe Price ID missing for "${planId}". Set NEXT_PUBLIC_STRIPE_PRICE_* in .env.local and redeploy.`
      );
      return;
    }

    trackGa4("begin_checkout", {
      plan_id: planId,
      plan_name: planName,
      currency: "USD",
      value: planPrice,
      locale: pageLang,
    });
    setPendingCheckoutPlan(planId);
    setBusyPlan(planId);
    setCheckoutSummary({
      planId,
      planName,
      planPrice,
      freeEditsLabel: freeEditsLabel(planId, pageLang),
    });

    const stripePublicKey = process.env.NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY;

    try {
      if (!stripePublicKey && paymentLink) {
        redirectToPaymentLink(planId, pageLang);
        return;
      }

      const utm = readUtmFromLocation();
      const serviceDraftSummary = readAlignedServiceDraft(planId);
      const officialPlanName = officialPlanStripeName(planId);
      const response = await fetch("/api/checkout", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          planId,
          priceId,
          planName: officialPlanName || planName,
          planPrice,
          serviceDraftSummary,
          locale: pageLang,
          lang: pageLang,
          ...utm,
        }),
      });
      const data = await response.json().catch(() => ({}));

      if (!response.ok || !data.id) {
        if (paymentLink && (response.status === 503 || response.status === 500)) {
          redirectToPaymentLink(planId, pageLang);
          return;
        }
        logStripeInternal(response.status === 400 ? "CHECKOUT_REJECTED" : "CHECKOUT_HTTP_ERROR", {
          planId,
          httpStatus: response.status,
          error: data?.error,
          hint: data?.hint,
        });
        setCheckoutError(userFacingCheckoutError(response.status, data));
        return;
      }

      if (!stripePublicKey) {
        if (paymentLink) {
          redirectToPaymentLink(planId, pageLang);
          return;
        }
        setCheckoutError("Missing publishable key (NEXT_PUBLIC_STRIPE_PUBLISHABLE_KEY).");
        return;
      }

      const stripeLib = await import("@stripe/stripe-js");
      const stripe = await stripeLib.loadStripe(stripePublicKey);
      if (!stripe) {
        if (paymentLink) {
          redirectToPaymentLink(planId, pageLang);
          return;
        }
        setCheckoutError("Could not load Stripe.js.");
        return;
      }

      const { error } = await stripe.redirectToCheckout({ sessionId: data.id });
      if (error) {
        if (paymentLink) {
          redirectToPaymentLink(planId, pageLang);
          return;
        }
        logStripeInternal("STRIPE_REDIRECT_ERROR", {
          planId,
          message: error.message,
          code: error.code,
          type: error.type,
        });
        setCheckoutError(error.message || "Stripe redirect failed.");
      }
    } catch (error) {
      if (paymentLink && redirectToPaymentLink(planId, pageLang)) {
        return;
      }
      const message = error?.message ?? String(error);
      logStripeInternal("CHECKOUT_CLIENT_FLOW_ERROR", { planId, message });
      setCheckoutError("Checkout error — see console for details.");
    } finally {
      setBusyPlan("");
    }
  }, [dynamicPlans, pageLang]);

  return { busyPlan, handleCheckout, dynamicPlans, checkoutError, checkoutSummary };
}
