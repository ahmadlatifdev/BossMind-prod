/**
 * Claude / KIMI independent review engine.
 * Tries: Anthropic → Moonshot/Kimi → OpenRouter (Claude or Kimi model).
 */
async function openAiCompatibleReview({ baseUrl, apiKey, model, system, user }) {
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/v1/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({
      model,
      messages: [
        { role: "system", content: system },
        { role: "user", content: user },
      ],
      max_tokens: 1200,
      temperature: 0.1,
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return {
      ok: false,
      error: data?.error?.message || res.statusText,
      text: "",
    };
  }
  return { ok: true, text: data?.choices?.[0]?.message?.content || "", model };
}

async function anthropicReview({ apiKey, model, system, user }) {
  const res = await fetch("https://api.anthropic.com/v1/messages", {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      "x-api-key": apiKey,
      "anthropic-version": "2023-06-01",
    },
    body: JSON.stringify({
      model,
      max_tokens: 1200,
      system,
      messages: [{ role: "user", content: user }],
    }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return { ok: false, error: data?.error?.message || res.statusText, text: "" };
  }
  const text = (data.content || [])
    .filter((c) => c.type === "text")
    .map((c) => c.text)
    .join("\n");
  return { ok: true, text, model, via: "anthropic" };
}

export async function reviewDeepSeekOutput({ env, config, projectId, deepseekResult, taskDescription }) {
  const system = [
    "You are BossMind independent review (Claude/KIMI role).",
    "Review the DeepSeek patch plan for production safety.",
    'Return JSON only: {"approved":boolean,"decision":"approve|reject","risk":"low|medium|high","reasons":[],"requiredChanges":[]}',
    "Reject if: cross-project paths, UI lock violation, missing verification, high risk without mitigation.",
  ].join("\n");

  const user = [
    `Project: ${projectId}`,
    `Task: ${taskDescription}`,
    `DeepSeek output: ${JSON.stringify(deepseekResult).slice(0, 14000)}`,
  ].join("\n\n");

  const cfg = config.review || {};

  if (env.ANTHROPIC_API_KEY) {
    const r = await anthropicReview({
      apiKey: env.ANTHROPIC_API_KEY,
      model: cfg.anthropicModel || "claude-3-5-sonnet-20241022",
      system,
      user,
    });
    if (r.ok) return parseReview(r, "anthropic");
    return { ok: false, error: r.error, via: "anthropic" };
  }

  const kimiKey = env.KIMI_API_KEY || env.MOONSHOT_API_KEY;
  if (kimiKey) {
    const r = await openAiCompatibleReview({
      baseUrl: env.KIMI_BASE_URL || "https://api.moonshot.ai/v1",
      apiKey: kimiKey,
      model: env.KIMI_MODEL_NAME || cfg.moonshotModel || "moonshot-v1-8k",
      system,
      user,
    });
    if (r.ok) return parseReview({ ...r, via: "moonshot" }, "moonshot");
    return { ok: false, error: r.error, via: "moonshot" };
  }

  if (env.OPENROUTER_API_KEY) {
    const model =
      env.BOSSMIND_REVIEW_MODEL ||
      cfg.openRouterModelClaude ||
      "anthropic/claude-3.5-sonnet";
    const r = await openAiCompatibleReview({
      baseUrl: "https://openrouter.ai/api",
      apiKey: env.OPENROUTER_API_KEY,
      model,
      system,
      user,
    });
    if (r.ok) return parseReview({ ...r, via: "openrouter", model }, "openrouter");
    return { ok: false, error: r.error, via: "openrouter" };
  }

  return {
    ok: false,
    blocked: true,
    missingEnv: "ANTHROPIC_API_KEY, KIMI_API_KEY/MOONSHOT_API_KEY, or OPENROUTER_API_KEY",
    review: null,
  };
}

function parseReview(r, via) {
  let review = null;
  try {
    const m = r.text.match(/\{[\s\S]*\}/);
    review = m ? JSON.parse(m[0]) : null;
  } catch {
    review = null;
  }
  if (!review) {
    const approved = /"approved"\s*:\s*true/i.test(r.text) || /\bapprove\b/i.test(r.text);
    review = {
      approved,
      decision: approved ? "approve" : "reject",
      risk: "medium",
      reasons: [r.text.slice(0, 500)],
      requiredChanges: [],
      raw: r.text,
    };
  }
  return {
    ok: true,
    via,
    model: r.model,
    review,
    raw: r.text,
  };
}
