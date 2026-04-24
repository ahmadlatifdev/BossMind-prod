function isPatchSafe(newContent) {
  if (!newContent || typeof newContent !== "string") {
    return { safe: false, reason: "Empty or invalid content" };
  }

  // Block dangerous patterns
  const blockedPatterns = [
    "rm -rf",
    "process.exit",
    "while(true)",
    "eval(",
  ];

  for (const pattern of blockedPatterns) {
    if (newContent.includes(pattern)) {
      return { safe: false, reason: `Blocked pattern detected: ${pattern}` };
    }
  }

  // Basic size check (prevent partial/empty patches)
  if (newContent.length < 10) {
    return { safe: false, reason: "Content too short (possible incomplete patch)" };
  }

  return { safe: true };
}

module.exports = { isPatchSafe };