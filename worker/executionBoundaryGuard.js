function validateExecutionBoundary({ requestedFile, requirementLock }) {
  if (!requirementLock || requirementLock.status !== "locked") {
    return {
      allowed: false,
      reason: "No active locked requirement found",
    };
  }

  if (!requestedFile || requestedFile !== requirementLock.filePath) {
    return {
      allowed: false,
      reason: `Blocked: attempted file outside locked boundary (${requestedFile})`,
    };
  }

  return {
    allowed: true,
    reason: "Execution boundary approved",
  };
}

module.exports = { validateExecutionBoundary };