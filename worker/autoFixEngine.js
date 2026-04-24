function classifyIssue(issueTitle) {
  const title = String(issueTitle || "").toLowerCase();

  if (title.includes("cannot find module")) {
    return {
      type: "missing_dependency",
      action: "Check package.json and install missing dependency safely",
    };
  }

  if (title.includes("requesthandler")) {
    return {
      type: "sentry_sdk_mismatch",
      action: "Replace deprecated Sentry handler usage",
    };
  }

  return {
    type: "unknown",
    action: "Send issue to DeepSeek/Copilot repair queue",
  };
}

module.exports = { classifyIssue };