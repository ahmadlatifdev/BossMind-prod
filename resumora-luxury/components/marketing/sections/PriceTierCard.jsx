import { useState } from "react";
import { translations } from "@/lib/marketing/site-copy";
import { freeEditsLabel } from "@/lib/client/plan-policy";

/** Same visible count on every card so feature lists share one baseline. */
const VISIBLE_FEATURES = 3;

export default function PriceTierCard({ plan, lang, busyPlan, onCheckout, quoteMatch }) {
  const t = translations[lang];
  const features = plan.features[lang] || [];
  const isEa = plan.id === "essential_advanced";
  const [expanded, setExpanded] = useState(false);
  const visible = expanded ? features : features.slice(0, VISIBLE_FEATURES);
  const hasMore = features.length > VISIBLE_FEATURES;

  const showFlagship = plan.badge === "flagship";
  const showBalanced = plan.badge === "balanced";
  const showAdvanced = plan.badge === "advanced";
  const showPopular = plan.id === "professional";
  const hasBadge = showFlagship || showBalanced || showAdvanced || showPopular;
  const subtitle = freeEditsLabel(plan.id, lang);

  return (
    <article
      className={`rs-price-card rs-price-card--lux luxury-card rs-price-card--aligned rs-price-card--${plan.id}`}
      data-featured={plan.featured}
      data-tier={plan.id}
      data-quote-match={quoteMatch ? "true" : "false"}
    >
      {/* Fixed-height badge slot — reserved even when empty so titles share a baseline */}
      <div className="rs-price-badge-slot rs-price-flag-row" aria-hidden={!hasBadge}>
        {showFlagship ? <span className="rs-price-flag">{t.badgeBestValue}</span> : null}
        {showBalanced ? <span className="rs-price-flag rs-price-flag--balanced">{t.badgeBalanced}</span> : null}
        {showAdvanced ? (
          <span className="rs-price-flag rs-price-flag--upgrade">{t.badgeEssentialAdvanced}</span>
        ) : null}
        {showPopular ? <span className="rs-price-flag rs-price-flag--popular">{t.badgeMostPopular}</span> : null}
      </div>

      <header className="rs-price-plan-header">
        <h3 className="rs-price-tier-name">{plan.name[lang]}</h3>
      </header>

      <div className="rs-price-amount-block">
        <span className="rs-price-amount-value">{plan.price}</span>
        <span className="rs-price-one-time">· {t.pricingOneTimeNote}</span>
      </div>

      {/* Fixed-height subtitle slot (edit-count) — empty for Enterprise */}
      <p
        className="rs-price-subtitle-slot rs-price-free-edits"
        data-rs-free-edits={plan.freeEdits || 0}
        data-empty={subtitle ? "false" : "true"}
      >
        {subtitle || "\u00a0"}
      </p>

      <div className="rs-price-tagline-slot" aria-hidden="true" />

      {features.length > 0 ? (
        <ul className="rs-price-features rs-price-features--compact">
          {visible.map((f) => (
            <li key={f}>{f}</li>
          ))}
        </ul>
      ) : (
        <ul className="rs-price-features rs-price-features--compact" aria-hidden="true" />
      )}

      {/* Push deliverables link + CTA to the bottom */}
      <div className="rs-price-card-spacer" aria-hidden="true" />

      {hasMore ? (
        <button
          type="button"
          className="rs-price-expand"
          onClick={() => setExpanded((v) => !v)}
          aria-expanded={expanded}
        >
          {expanded ? t.pricingHideFeatures : t.pricingViewAllFeatures}
        </button>
      ) : (
        <span className="rs-price-expand rs-price-expand-spacer" aria-hidden>
          {"\u00a0"}
        </span>
      )}

      <footer className="rs-price-card-footer">
        <button
          type="button"
          className={`rs-price-btn btn-primary${
            plan.id === "elite"
              ? " rs-price-btn--elite"
              : isEa
                ? " rs-price-btn--essential-advanced"
                : ""
          }`}
          disabled={Boolean(busyPlan)}
          aria-busy={busyPlan === plan.id}
          data-rs-plan-id={plan.id}
          data-rs-checkout-cta="select-plan"
          onClick={() => onCheckout(plan.id, plan.name[lang], plan.price.replace(/[^\d]/g, ""))}
        >
          {busyPlan === plan.id ? t.processing : t.selectPlan}
        </button>
      </footer>
    </article>
  );
}
