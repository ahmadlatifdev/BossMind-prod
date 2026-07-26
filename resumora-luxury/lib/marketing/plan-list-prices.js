/**
 * Single source of truth for Resumora tier list prices (USD display).
 * Marketing labels → plan ids → USD:
 *   Basic → basic → $19
 *   Balanced → professional → $49
 *   Professional → elite → $79
 *   Advanced → essential_advanced → $110
 * One-time payments only. Do not mutate Stripe Price IDs from this file.
 */

export const BASIC_PRICE_USD = 19;
export const PRO_PRICE_USD = 49;
export const ELITE_PRICE_USD = 79;
export const ESSENTIAL_ADVANCED_PRICE_USD = 110;

export const TIER_LIST_PRICES_USD = {
  basic: BASIC_PRICE_USD,
  professional: PRO_PRICE_USD,
  elite: ELITE_PRICE_USD,
  essential_advanced: ESSENTIAL_ADVANCED_PRICE_USD,
};

/** Expected lock serviceKey → planId mapping for verification scripts. */
export const PLAN_SERVICE_KEYS = {
  basic: "essential_foundation",
  professional: "professional_career",
  elite: "executive_career",
  essential_advanced: "essential_career",
};
