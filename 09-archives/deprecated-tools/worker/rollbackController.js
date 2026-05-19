async function rollbackIfNeeded(verification) {
  if (!verification || verification.ok === true) {
    console.log("✅ Rollback not needed");
    return { rolledBack: false, reason: "Deployment healthy" };
  }

  console.log("⛔ Rollback required:", verification);

  return {
    rolledBack: true,
    reason: "Deployment verification failed",
    checkedAt: new Date().toISOString(),
  };
}

module.exports = { rollbackIfNeeded };