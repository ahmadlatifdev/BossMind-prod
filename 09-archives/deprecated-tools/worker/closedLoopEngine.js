function closeRepairLoop({
  issue,
  classification,
  validation,
  verification,
  rollback,
}) {
  const loopStatus = {
    closedAt: new Date().toISOString(),
    issueDetected: Boolean(issue && issue.title),
    classified: Boolean(classification && classification.type),
    validated: Boolean(validation),
    approved: Boolean(validation && validation.approved),
    deploymentHealthy: Boolean(verification && verification.ok),
    rollbackNeeded: Boolean(rollback && rollback.rolledBack),
    finalStatus:
      verification && verification.ok && !(rollback && rollback.rolledBack)
        ? "closed_clean"
        : "requires_attention",
  };

  console.log("🔁 Closed Loop Result:", loopStatus);

  return loopStatus;
}

module.exports = { closeRepairLoop };