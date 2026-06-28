const { destroySession } = require("../../../lib/engagement/store");
const {
  parseCookies,
  readCookieHeader,
  readSessionToken,
  clearSessionCookies,
} = require("../../../lib/engagement/cookies");

export default async function handler(req, res) {
  if (req.method !== "POST") {
    res.setHeader("Allow", "POST");
    return res.status(405).json({ error: "Method not allowed" });
  }

  const cookies = parseCookies(readCookieHeader(req));
  const token = readSessionToken(cookies);
  if (token) {
    await destroySession(token);
  }

  res.setHeader("Set-Cookie", clearSessionCookies());
  return res.status(200).json({ ok: true });
}
