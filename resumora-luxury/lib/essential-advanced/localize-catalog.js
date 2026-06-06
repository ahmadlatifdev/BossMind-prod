const { normalizeLang, pickLang } = require("../i18n/pick-lang");

/** Flatten bilingual catalog objects for client UI (single active locale). */
function localizeInterviewPrepCatalog(catalog, lang) {
  const L = normalizeLang(lang);

  return {
    version: catalog.version,
    planId: catalog.planId,
    lang: L,
    counts: catalog.counts || {},
    assetKeys: catalog.assetKeys || [],
    videos: (catalog.videos || []).map((v) => ({
      id: v.id,
      durationMin: v.durationMin,
      title: pickLang(v.title, L),
      summary: pickLang(v.summary, L),
      protectedDelivery: v.protectedDelivery !== false,
    })),
    simulations: (catalog.simulations || []).map((s) => ({
      id: s.id,
      title: pickLang(s.title, L),
      level: pickLang(s.level, L),
      questions: (s.questions || []).map((q, index) => ({
        id: `${s.id}_q${index + 1}`,
        q: pickLang(q.q, L),
        a: pickLang(q.a, L),
      })),
    })),
    qaBank: (catalog.qaBank || []).map((item) => ({
      id: item.id,
      category: item.category,
      categoryLabel: pickLang(item.categoryLabel, L),
      q: pickLang(item.q, L),
      a: pickLang(item.a, L),
    })),
    tips: (catalog.tips || []).map((tip) => ({
      id: tip.id,
      text: pickLang(tip.text, L),
    })),
    executive: {
      id: catalog.executive?.id,
      title: pickLang(catalog.executive?.title, L),
      modules: (catalog.executive?.modules || []).map((m) => ({
        id: m.id,
        title: pickLang(m.title, L),
        body: pickLang(m.body, L),
      })),
    },
    downloads: (catalog.downloads || []).map((d) => ({
      id: d.id,
      title: typeof d.title === "string" ? d.title : pickLang(d.title, L),
      filename: d.filename,
    })),
  };
}

module.exports = { localizeInterviewPrepCatalog };
