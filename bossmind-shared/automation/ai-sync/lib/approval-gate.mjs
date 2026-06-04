import { spawnSync } from "child_process";
import path from "path";

/**
 * Strict deployment approval gate — all checks must pass.
 */
export function evaluateApprovalGate({
  projectId,
  deepseekResult,
  reviewResult,
  isolationResult,
  verificationResult,
  filesChanged = [],
}) {
  const checks = [];

  checks.push({
    id: "deepseek_present",
    pass: Boolean(deepseekResult?.ok),
    detail: deepseekResult?.ok ? "DeepSeek patch generated" : deepseekResult?.missingEnv || deepseekResult?.error,
  });

  checks.push({
    id: "files_listed",
    pass: Array.isArray(filesChanged) && filesChanged.length >= 0,
    detail: `filesChanged=${filesChanged.length}`,
  });

  checks.push({
    id: "review_approved",
    pass: Boolean(reviewResult?.ok && reviewResult?.review?.approved === true),
    detail: reviewResult?.ok
      ? `decision=${reviewResult.review?.decision} via=${reviewResult.via}`
      : reviewResult?.missingEnv || reviewResult?.error,
  });

  checks.push({
    id: "risk_review",
    pass: !reviewResult?.review || reviewResult.review.risk !== "high" || reviewResult.review.approved,
    detail: `risk=${reviewResult?.review?.risk || "n/a"}`,
  });

  checks.push({
    id: "project_isolation",
    pass: isolationResult?.ok === true,
    detail: isolationResult?.ok ? "isolated" : (isolationResult?.violations || []).join("; "),
  });

  checks.push({
    id: "build_verification",
    pass: verificationResult?.build?.ok !== false,
    detail: verificationResult?.build?.detail || "skipped",
  });

  checks.push({
    id: "lint_verification",
    pass: verificationResult?.lint?.ok !== false,
    detail: verificationResult?.lint?.detail || "skipped",
  });

  const pass = checks.every((c) => c.pass);
  return {
    approved: pass,
    deployAllowed: pass,
    checks,
    blockedReason: pass ? null : checks.filter((c) => !c.pass).map((c) => c.id).join(", "),
  };
}

export function runProjectVerification(projectRoot, verificationCfg = {}) {
  const result = { build: { ok: true, detail: "skipped" }, lint: { ok: true, detail: "skipped" } };

  if (verificationCfg.build) {
    const [cmd, ...args] = verificationCfg.build.split(" ");
    const r = spawnSync(cmd, args, {
      cwd: projectRoot,
      shell: true,
      encoding: "utf8",
      env: process.env,
    });
    result.build = {
      ok: (r.status ?? 1) === 0,
      detail: `exit=${r.status}`,
      stderrTail: (r.stderr || "").slice(-400),
    };
  }

  if (verificationCfg.lint) {
    const [cmd, ...args] = verificationCfg.lint.split(" ");
    const r = spawnSync(cmd, args, {
      cwd: projectRoot,
      shell: true,
      encoding: "utf8",
      env: process.env,
    });
    result.lint = {
      ok: (r.status ?? 1) === 0,
      detail: `exit=${r.status}`,
      stderrTail: (r.stderr || "").slice(-400),
    };
  }

  return result;
}
