function validateRepairDecision({ issue, classification, patchSafety, deployment }) {
  const checks = {
    hasIssue: Boolean(issue && issue.title),
    hasClassification: Boolean(classification && classification.type),
    patchSafe: !patchSafety || patchSafety.safe === true,
    deploymentHealthy: !deployment || deployment.ok === true,
  };

  const approved =
    checks.hasIssue &&
    checks.hasClassification &&
    checks.patchSafe &&
    checks.deploymentHealthy;

  return {
    approved,
    checks,
    decision: approved ? "approved" : "blocked",
    reason: approved
      ? "Repair decision validated"
      : "Repair decision failed validation checks",
    checkedAt: new Date().toISOString(),
  };
}

module.exports = { validateRepairDecision };