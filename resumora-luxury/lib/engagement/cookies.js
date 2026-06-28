const COOKIE_VISITOR = "rs_vid";
/** Firebase Hosting forwards only __session on GET (dynamic routes). See hosting/manage-cache#using_cookies */
const COOKIE_SESSION = "__session";
const COOKIE_SESSION_LEGACY = "rs_sess";

function parseCookies(header) {
  if (!header) return {};
  return Object.fromEntries(
    header.split(";").map((part) => {
      const idx = part.indexOf("=");
      if (idx < 1) return ["", ""];
      const k = part.slice(0, idx).trim();
      const v = decodeURIComponent(part.slice(idx + 1).trim());
      return [k, v];
    }).filter(([k]) => k)
  );
}

function readCookieHeader(req) {
  if (!req) return "";
  const headers = req.headers || {};
  if (typeof headers.get === "function") {
    const fromGet = headers.get("cookie") || headers.get("Cookie");
    if (fromGet) return fromGet;
  }
  const direct = headers.cookie ?? headers.Cookie;
  if (Array.isArray(direct)) return direct.join("; ");
  if (typeof direct === "string" && direct) return direct;
  if (req.cookies && typeof req.cookies === "object") {
    const parts = Object.entries(req.cookies)
      .filter(([, v]) => v != null && v !== "")
      .map(([k, v]) => `${k}=${v}`);
    if (parts.length) return parts.join("; ");
  }
  const raw = req.rawHeaders;
  if (Array.isArray(raw)) {
    for (let i = 0; i < raw.length - 1; i += 2) {
      if (String(raw[i]).toLowerCase() === "cookie") {
        return String(raw[i + 1] || "");
      }
    }
  }
  return "";
}

function readSessionToken(cookies) {
  if (!cookies) return null;
  return cookies[COOKIE_SESSION] || cookies[COOKIE_SESSION_LEGACY] || null;
}

function serializeCookie(name, value, options = {}) {
  const parts = [`${name}=${encodeURIComponent(value)}`, "Path=/", "SameSite=Lax"];
  if (options.httpOnly !== false) parts.push("HttpOnly");
  if (process.env.NODE_ENV === "production") parts.push("Secure");
  if (options.maxAge != null) parts.push(`Max-Age=${options.maxAge}`);
  return parts.join("; ");
}

function clearCookie(name) {
  const secure = process.env.NODE_ENV === "production" ? "; Secure" : "";
  return `${name}=; Path=/; Max-Age=0; HttpOnly; SameSite=Lax${secure}`;
}

function clearSessionCookies() {
  return [clearCookie(COOKIE_SESSION), clearCookie(COOKIE_SESSION_LEGACY)];
}

module.exports = {
  COOKIE_SESSION,
  COOKIE_SESSION_LEGACY,
  COOKIE_VISITOR,
  parseCookies,
  readCookieHeader,
  readSessionToken,
  serializeCookie,
  clearCookie,
  clearSessionCookies,
};
