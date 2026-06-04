/**
 * DeepSeek — coding, repair, refactor, patch-generation engine.
 */
export async function deepseekChat({
  apiKey,
  baseUrl = "https://api.deepseek.com",
  model = "deepseek-chat",
  messages,
  maxTokens = 2048,
  temperature = 0.2,
}) {
  if (!apiKey) {
    return { ok: false, error: "DEEPSEEK_API_KEY is not set", text: "" };
  }
  const res = await fetch(`${baseUrl.replace(/\/$/, "")}/v1/chat/completions`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json",
      Authorization: `Bearer ${apiKey}`,
    },
    body: JSON.stringify({ model, messages, max_tokens: maxTokens, temperature }),
  });
  const data = await res.json().catch(() => ({}));
  if (!res.ok) {
    return {
      ok: false,
      error: data?.error?.message || res.statusText || "DeepSeek request failed",
      text: "",
      status: res.status,
    };
  }
  return { ok: true, text: data?.choices?.[0]?.message?.content || "", model, raw: data };
}

export async function generateRepairPatch({
  env,
  config,
  projectId,
  taskDescription,
  context = {},
}) {
  const apiKey = env.DEEPSEEK_API_KEY;
  if (!apiKey) {
    return {
      ok: false,
      blocked: true,
      missingEnv: "DEEPSEEK_API_KEY",
      patch: null,
    };
  }

  const system = [
    "You are BossMind DeepSeek repair engine.",
    "Return strict JSON only:",
    '{"summary":"","risk":"low|medium|high","files":[],"patchPlan":"","unifiedDiff":"","commands":[]}',
    "Do not deploy. Do not modify locked luxury UI unless task explicitly requires it.",
    `Project: ${projectId}`,
  ].join("\n");

  const user = [
    `Task: ${taskDescription}`,
    `Context: ${JSON.stringify(context).slice(0, 12000)}`,
  ].join("\n");

  const r = await deepseekChat({
    apiKey,
    baseUrl: config.deepseek?.baseUrl || "https://api.deepseek.com",
    model: config.deepseek?.coderModel || "deepseek-chat",
    messages: [
      { role: "system", content: system },
      { role: "user", content: user },
    ],
    maxTokens: 2500,
    temperature: 0.15,
  });

  if (!r.ok) {
    return { ok: false, blocked: true, error: r.error, patch: null };
  }

  let parsed = null;
  try {
    const m = r.text.match(/\{[\s\S]*\}/);
    parsed = m ? JSON.parse(m[0]) : { summary: r.text, raw: r.text };
  } catch {
    parsed = { summary: r.text, raw: r.text, parseError: true };
  }

  return {
    ok: true,
    engine: "deepseek",
    model: config.deepseek?.coderModel || "deepseek-chat",
    patch: parsed,
    raw: r.text,
  };
}
