/**
 * Plan policy — free edit limits (Ahmed lock 2026-07-26).
 * BASIC=1, BALANCED(professional)=2, PROFESSIONAL(elite)=3, ADVANCED(essential_advanced)=0
 */
const FREE_EDITS_BY_PLAN = {
  basic: 1,
  professional: 2,
  elite: 3,
  essential_advanced: 0,
};

const PLAN_IDS = Object.keys(FREE_EDITS_BY_PLAN);

function isPlanId(planId) {
  return PLAN_IDS.includes(planId);
}

function getFreeEditsCount(planId) {
  return FREE_EDITS_BY_PLAN[planId] ?? 0;
}

function freeEditsLabel(planId, lang = "en") {
  const n = getFreeEditsCount(planId);
  const L = lang === "fr" ? "fr" : "en";
  if (planId === "essential_advanced") {
    return L === "fr"
      ? "0 révision — tutoriels vidéo et conseils uniquement"
      : "0 edits — Tutorial videos & tips only";
  }
  if (!n) return "";
  if (L === "fr") {
    return n === 1 ? "1 révision incluse" : `${n} révisions incluses`;
  }
  return n === 1 ? "1 included edit" : `${n} included edits`;
}

function planPolicySummary(planId, lang = "en") {
  return {
    planId,
    freeEdits: getFreeEditsCount(planId),
    freeEditsLabel: freeEditsLabel(planId, lang),
    isTutorialOnly: planId === "essential_advanced",
  };
}

function auditFreeEditsPolicy() {
  const expected = { basic: 1, professional: 2, elite: 3, essential_advanced: 0 };
  const ok = PLAN_IDS.every((id) => getFreeEditsCount(id) === expected[id]);
  return { ok, expected, actual: { ...FREE_EDITS_BY_PLAN } };
}

module.exports = {
  PLAN_IDS,
  FREE_EDITS_BY_PLAN,
  isPlanId,
  getFreeEditsCount,
  freeEditsLabel,
  planPolicySummary,
  auditFreeEditsPolicy,
};
