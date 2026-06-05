/**
 * Dynamic Web App Manifest — versioned icon URLs + no-store so Chrome/PWA pick up branding changes.
 * Served at /manifest.webmanifest via next.config rewrites (public static manifest removed).
 */
const { buildWebManifest } = require("../../lib/marketing/branding-assets");
const { getCached, setCached } = require("../../lib/perf/response-cache");

const CACHE_KEY = "branding-manifest-v1";
const CACHE_TTL_MS = 300_000;

export default function handler(req, res) {
  if (req.method !== "GET") {
    res.setHeader("Allow", "GET");
    return res.status(405).end();
  }
  let body = getCached(CACHE_KEY);
  if (!body) {
    body = JSON.stringify(buildWebManifest());
    setCached(CACHE_KEY, body, CACHE_TTL_MS);
  }
  res.setHeader("Content-Type", "application/manifest+json; charset=utf-8");
  res.setHeader("Cache-Control", "public, max-age=300, stale-while-revalidate=600");
  res.status(200).send(body);
}
