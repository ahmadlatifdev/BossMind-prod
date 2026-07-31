/**
 * Kimi K3 Content Layer — weekly organic drafts (blog, social, FAQ, CTAs).
 * Replaces former OpenAI/ChatGPT content layer. Env: KIMI_API_KEY or MOONSHOT_API_KEY.
 * No OpenAI fallback.
 */
const { getSiteUrl } = require("./seo-config");

const KIMI_BASE = "https://api.moonshot.ai/v1";

function resolveKimiKey() {
  return String(process.env.KIMI_API_KEY || process.env.MOONSHOT_API_KEY || "").trim();
}

function chatUrl(base) {
  const raw = String(base || KIMI_BASE).replace(/\/$/, "");
  return raw.endsWith("/v1") ? `${raw}/chat/completions` : `${raw}/v1/chat/completions`;
}

async function runKimiContentLayer({ weekId, dayTheme = "general" } = {}) {
  const key = resolveKimiKey();
  const siteUrl = getSiteUrl();
  const out = {
    generatedAt: new Date().toISOString(),
    weekId,
    dayTheme,
    siteUrl,
    provider: "kimi-k3",
    aiUsed: false,
    blogPosts: [],
    linkedinPosts: [],
    instagramCaptions: [],
    pinterestText: [],
    youtubeDescriptions: [],
    faqSections: [],
    ctaVariants: [],
  };

  if (!key) {
    out.note = "KIMI_API_KEY/MOONSHOT_API_KEY unset — no OpenAI fallback";
    return out;
  }

  const model = process.env.KIMI_MODEL || process.env.KIMI_CONTENT_MODEL || "kimi-k3";
  const base = process.env.KIMI_API_BASE || process.env.KIMI_BASE_URL || KIMI_BASE;
  const prompt = `Generate organic marketing JSON for Resumora (${siteUrl}), week ${weekId}, theme ${dayTheme}.
Keys: blogPosts (2 items {title, outline}), linkedinPosts (2), instagramCaptions (2), pinterestText (2),
youtubeDescriptions (1), faqSections (3 Q&A), ctaVariants (3). Luxury professional tone. No paid ads. JSON only.`;

  const res = await fetch(chatUrl(base), {
    method: "POST",
    headers: {
      Authorization: `Bearer ${key}`,
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: "Return valid JSON only. You are Kimi K3 for BossMind Resumora marketing." },
        { role: "user", content: prompt },
      ],
      max_completion_tokens: 4096,
      reasoning_effort: process.env.KIMI_REASONING_EFFORT || "high",
    }),
  });

  const raw = await res.text();
  if (!res.ok) {
    out.aiError = raw.slice(0, 500);
    return out;
  }

  try {
    const data = JSON.parse(raw);
    const content = data.choices?.[0]?.message?.content || "";
    const cleaned = content.replace(/^```(?:json)?\s*/i, "").replace(/\s*```$/i, "").trim();
    const j = JSON.parse(cleaned.match(/\{[\s\S]*\}/)?.[0] || cleaned);
    Object.assign(out, j, {
      aiUsed: true,
      provider: "kimi-k3",
      model: data.model || model,
      generatedAt: new Date().toISOString(),
    });
  } catch (e) {
    out.aiError = e.message || String(e);
  }

  return out;
}

/** @deprecated Use runKimiContentLayer — OpenAI removed. */
async function runOpenAiContentLayer(opts) {
  return runKimiContentLayer(opts);
}

module.exports = { runKimiContentLayer, runOpenAiContentLayer };
