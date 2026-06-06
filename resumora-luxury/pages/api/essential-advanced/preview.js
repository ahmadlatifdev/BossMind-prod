/** Public marketing preview — video module titles (no embed URLs). */
const {
  sanitizeVideosForClient,
  validateVideoManifest,
} = require("../../../lib/essential-advanced/video-delivery");

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const lang = String(req.query.lang || "en").toLowerCase() === "fr" ? "fr" : "en";
  const validation = validateVideoManifest();

  res.setHeader("Cache-Control", "public, max-age=300, stale-while-revalidate=600");
  const features =
    lang === "fr"
      ? {
          simulations: 3,
          qaBank: "50–60",
          tips: "20+",
          autoGenerateOnPurchase: true,
          simulationsLabel: "3 simulations d'entretien avancées",
          videosLabel: "3 vidéos professionnelles de préparation",
          tipsLabel: "20+ conseils succès exécutifs",
        }
      : {
          simulations: 3,
          qaBank: "50-60",
          tips: "20+",
          autoGenerateOnPurchase: true,
          simulationsLabel: "3 advanced interview simulations",
          videosLabel: "3 professional interview training videos",
          tipsLabel: "20+ executive success tips",
        };

  return res.status(200).json({
    ok: true,
    planId: "essential_advanced",
    studioPath: "/studio/essential-advanced",
    lang,
    videoCount: validation.videoCount,
    manifestOk: validation.ok,
    videos: sanitizeVideosForClient(lang),
    features,
  });
}
