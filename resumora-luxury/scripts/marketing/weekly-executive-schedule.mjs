#!/usr/bin/env node
/**
 * BossMind weekly executive social schedule (Mon / Wed / Fri).
 * Reports next slot dates; optionally persists via social-growth-engine when NEON is set.
 */
import fs from "fs";
import path from "path";
import { fileURLToPath } from "url";

const root = path.join(path.dirname(fileURLToPath(import.meta.url)), "..", "..");
const schedulePath = path.join(root, "config", "resumora-weekly-executive-schedule.json");
const schedule = JSON.parse(fs.readFileSync(schedulePath, "utf8"));

function nextWeekday(from, targetDow) {
  const d = new Date(from);
  const diff = (targetDow - d.getDay() + 7) % 7 || 7;
  d.setDate(d.getDate() + diff);
  d.setUTCHours(schedule.publishUtcHour, 0, 0, 0);
  return d;
}

const now = new Date();
const upcoming = schedule.slots.map((slot) => {
  const at = nextWeekday(now, slot.weekdayIndex);
  return {
    ...slot,
    nextPublishIso: at.toISOString(),
    nextPublishLocal: at.toLocaleString("en-CA", { timeZone: schedule.timezone }),
  };
});

const report = {
  generatedAt: now.toISOString(),
  timezone: schedule.timezone,
  active: Boolean(process.env.NEON_DATABASE_URL),
  upcoming,
};

const outDir = path.join(root, ".bossmind");
fs.mkdirSync(outDir, { recursive: true });
const outFile = path.join(outDir, "weekly-executive-schedule.json");
fs.writeFileSync(outFile, JSON.stringify(report, null, 2));

console.log(JSON.stringify(report, null, 2));
console.log(`\nWrote ${outFile}`);

if (process.argv.includes("--orchestrate") && process.env.NEON_DATABASE_URL) {
  const { spawnSync } = await import("node:child_process");
  const r = spawnSync("node", ["scripts/marketing/run-social-growth-engine.mjs", "--persist-neon"], {
    cwd: root,
    stdio: "inherit",
    shell: true,
  });
  process.exit(r.status ?? 1);
}
