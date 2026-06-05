/** Lightweight performance + uptime snapshot for BossMind monitoring. */
const { getCached, setCached } = require("../../lib/perf/response-cache");

const CACHE_KEY = "perf-dashboard";
const CACHE_TTL_MS = 30_000;

export default async function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).json({ ok: false });
  }

  const cached = getCached(CACHE_KEY);
  if (cached) {
    res.setHeader("Cache-Control", "public, max-age=30");
    return res.status(200).json(cached);
  }

  const started = Date.now();
  const origin = process.env.VERCEL_URL
    ? `https://${process.env.VERCEL_URL}`
    : "https://resumora-luxury.vercel.app";

  let homeMs = null;
  let homeOk = false;
  try {
    const t0 = Date.now();
    const r = await fetch(`${origin}/api/health?lite=1`, { signal: AbortSignal.timeout(8000) });
    homeMs = Date.now() - t0;
    homeOk = r.ok;
  } catch {
    homeMs = -1;
  }

  const snapshot = {
    ok: homeOk,
    generatedAt: new Date().toISOString(),
    origin,
    probes: {
      healthLiteMs: homeMs,
      healthLiteOk: homeOk,
      dashboardBuildMs: Date.now() - started,
    },
    targets: { apiP95Ms: 100, uptimeCheckMinutes: 5 },
    vitalsIngest: "/api/web-vitals",
    vercelAnalytics: "https://vercel.com/resumora/resumora-luxury/analytics",
    inspector: "https://vercel.com/resumora/resumora-luxury",
  };

  setCached(CACHE_KEY, snapshot, CACHE_TTL_MS);
  res.setHeader("Cache-Control", "public, max-age=30");
  return res.status(200).json(snapshot);
}
