/**
 * Reports which AI/review keys are present — never returns secret values.
 */
export function probeAiEnv(env = process.env) {
  const pick = (keys) => {
    const present = keys.filter((k) => Boolean(String(env[k] || "").trim()));
    return { present: present.length > 0, keys: present, missing: keys.filter((k) => !present.includes(k)) };
  };

  const deepseek = pick(["DEEPSEEK_API_KEY"]);
  const claudeNative = pick(["ANTHROPIC_API_KEY"]);
  const kimiNative = pick(["KIMI_API_KEY", "MOONSHOT_API_KEY"]);
  const openRouter = pick(["OPENROUTER_API_KEY"]);
  const neon = pick(["NEON_DATABASE_URL", "DATABASE_URL"]);

  const reviewVia =
    claudeNative.present
      ? "anthropic"
      : kimiNative.present
        ? "moonshot"
        : openRouter.present
          ? "openrouter"
          : null;

  return {
    deepseek: {
      ...deepseek,
      requiredVar: "DEEPSEEK_API_KEY",
      active: deepseek.present,
    },
    review: {
      claudeNative,
      kimiNative,
      openRouter,
      reviewVia,
      active: Boolean(reviewVia),
      requiredVarsIfMissing: reviewVia
        ? []
        : ["ANTHROPIC_API_KEY", "KIMI_API_KEY or MOONSHOT_API_KEY", "OPENROUTER_API_KEY"],
    },
    neon: {
      ...neon,
      active: neon.present,
      requiredVar: "NEON_DATABASE_URL or DATABASE_URL",
    },
  };
}
