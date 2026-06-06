#!/usr/bin/env node
import lock from "../config/resumora-stripe-payment-links-lock.json" with { type: "json" };

const PLANS = ["basic", "professional", "elite", "essential_advanced"];
const origin = process.argv[2] || "http://localhost:3000";

let ok = true;

for (const planId of PLANS) {
  const link = lock.planRoutes?.[planId]?.paymentLinkUrl;
  const priceId = lock.services?.find((s) => s.planIds?.includes(planId))?.priceId;
  process.stdout.write(`${planId}: price=${priceId || "MISSING"} link=${link ? "yes" : "MISSING"} `);

  if (!link) {
    ok = false;
    console.log("FAIL");
    continue;
  }

  try {
    const apiRes = await fetch(`${origin}/api/checkout`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ planId, priceId, planName: planId, planPrice: "19", locale: "en" }),
    });
    const apiBody = await apiRes.text();
    const linkRes = await fetch(link, { method: "GET", redirect: "manual" });
    const apiNote =
      apiRes.status === 200
        ? "session-ok"
        : apiRes.status === 503
          ? "session-fallback-link"
          : `api-${apiRes.status}`;
    const linkNote = linkRes.status >= 200 && linkRes.status < 400 ? "link-ok" : `link-${linkRes.status}`;
    const pass = linkNote === "link-ok" && (apiRes.status === 200 || apiRes.status === 503);
    if (!pass) ok = false;
    console.log(pass ? "PASS" : "FAIL", `(${apiNote}, ${linkNote})`, apiRes.status !== 200 ? apiBody.slice(0, 80) : "");
  } catch (err) {
    ok = false;
    console.log("FAIL", err.message);
  }
}

process.exit(ok ? 0 : 1);
