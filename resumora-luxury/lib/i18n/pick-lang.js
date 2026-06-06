/** Pick EN/FR string from bilingual record or plain string. */
function normalizeLang(lang) {
  return String(lang || "en").toLowerCase() === "fr" ? "fr" : "en";
}

function pickLang(record, lang, fallback = "") {
  if (record == null) return fallback;
  if (typeof record === "string") return record;
  const L = normalizeLang(lang);
  return record[L] || record.en || record.fr || fallback;
}

module.exports = { normalizeLang, pickLang };
