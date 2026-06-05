import { NextResponse } from "next/server";
import type { NextRequest } from "next/server";

const WINDOW_MS = 60_000;
const MAX_REQUESTS = Number(process.env.API_RATE_LIMIT_PER_MIN || 120);
const buckets = new Map<string, { count: number; resetAt: number }>();

function clientIp(req: NextRequest) {
  return (
    req.headers.get("x-real-ip") ||
    req.headers.get("x-forwarded-for")?.split(",")[0]?.trim() ||
    "anonymous"
  );
}

function isRateLimited(ip: string) {
  const now = Date.now();
  let bucket = buckets.get(ip);
  if (!bucket || now > bucket.resetAt) {
    bucket = { count: 0, resetAt: now + WINDOW_MS };
  }
  bucket.count += 1;
  buckets.set(ip, bucket);
  if (buckets.size > 10_000) {
    for (const [key, value] of buckets) {
      if (now > value.resetAt) buckets.delete(key);
    }
  }
  return {
    limited: bucket.count > MAX_REQUESTS,
    remaining: Math.max(0, MAX_REQUESTS - bucket.count),
    limit: MAX_REQUESTS,
  };
}

export function middleware(request: NextRequest) {
  const { pathname } = request.nextUrl;

  if (pathname.startsWith("/api/")) {
    const ip = clientIp(request);
    const rl = isRateLimited(ip);
    if (rl.limited) {
      return NextResponse.json(
        { ok: false, error: "rate_limit", message: "Too many requests. Retry shortly." },
        {
          status: 429,
          headers: {
            "Retry-After": "60",
            "X-RateLimit-Limit": String(rl.limit),
            "X-RateLimit-Remaining": "0",
          },
        }
      );
    }

    const response = NextResponse.next();
    response.headers.set("X-RateLimit-Limit", String(rl.limit));
    response.headers.set("X-RateLimit-Remaining", String(rl.remaining));
    response.headers.set("X-Content-Type-Options", "nosniff");
    response.headers.set("Referrer-Policy", "strict-origin-when-cross-origin");
    return response;
  }

  return NextResponse.next();
}

export const config = {
  matcher: ["/api/:path*"],
};
