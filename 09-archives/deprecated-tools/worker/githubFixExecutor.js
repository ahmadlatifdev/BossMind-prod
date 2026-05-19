const GITHUB_TOKEN = process.env.GITHUB_TOKEN;
const OWNER = "ahmadlatifdev";
const REPO = "BossMind-prod";

async function createFixCommit(filePath, newContent, message) {
  try {
    // Get current file SHA
    const getRes = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/contents/${filePath}`,
      {
        headers: {
          Authorization: `Bearer ${GITHUB_TOKEN}`,
        },
      }
    );

    const fileData = await getRes.json();

    const sha = fileData.sha;

    const contentEncoded = Buffer.from(newContent).toString("base64");

    // Update file
    const res = await fetch(
      `https://api.github.com/repos/${OWNER}/${REPO}/contents/${filePath}`,
      {
        method: "PUT",
        headers: {
          Authorization: `Bearer ${GITHUB_TOKEN}`,
          "Content-Type": "application/json",
        },
        body: JSON.stringify({
          message,
          content: contentEncoded,
          sha,
        }),
      }
    );

    const result = await res.json();

    console.log("🚀 GitHub auto-fix commit created:", result.commit?.sha);
  } catch (err) {
    console.log("GitHub executor error:", err.message);
  }
}

module.exports = { createFixCommit };