function predictNextRisk({ verification, loopStatus }) {
  const risks = [];

  if (!verification || verification.ok !== true) {
    risks.push("deployment_health_risk");
  }

  if (loopStatus && loopStatus.finalStatus !== "closed_clean") {
    risks.push("repair_loop_not_clean");
  }

  if (loopStatus && loopStatus.rollbackNeeded === true) {
    risks.push("rollback_pattern_detected");
  }

  const prediction = {
    checkedAt: new Date().toISOString(),
    riskLevel: risks.length === 0 ? "low" : risks.length === 1 ? "medium" : "high",
    risks,
    recommendation:
      risks.length === 0
        ? "System healthy. Continue monitoring."
        : "Run verifier and block auto-patch until risk is cleared.",
  };

  console.log("🔮 Predictive System:", prediction);

  return prediction;
}

module.exports = { predictNextRisk };