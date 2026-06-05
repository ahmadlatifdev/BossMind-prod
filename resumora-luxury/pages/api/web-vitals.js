/** Ingest Core Web Vitals beacons from client (LCP, CLS, INP/FID). */
const { saveEvent } = require("../../lib/shared/neon-memory");

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ ok: false });
  }

  const body = req.body && typeof req.body === "object" ? req.body : {};
  const payload = {
    name: body.name,
    value: body.value,
    rating: body.rating,
    path: body.path || "/",
    id: body.id,
    ts: Date.now(),
  };

  try {
    if (process.env.NEON_DATABASE_URL) {
      await saveEvent({
        projectKey: "resumora",
        eventType: "web_vital",
        payload,
      });
    }
  } catch {
    /* fail-open for vitals */
  }

  return res.status(204).end();
}
