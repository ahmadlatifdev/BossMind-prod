const fs = require("fs");
const path = require("path");

const SNAPSHOT_DIR = path.join(__dirname, "snapshots");

function ensureSnapshotDir() {
  if (!fs.existsSync(SNAPSHOT_DIR)) {
    fs.mkdirSync(SNAPSHOT_DIR, { recursive: true });
  }
}

function saveDeploymentSnapshot({ verification, loopStatus }) {
  ensureSnapshotDir();

  const snapshot = {
    id: `snapshot_${Date.now()}`,
    createdAt: new Date().toISOString(),
    verification,
    loopStatus,
    status: verification && verification.ok ? "healthy_snapshot" : "failed_snapshot",
  };

  const filePath = path.join(SNAPSHOT_DIR, `${snapshot.id}.json`);

  fs.writeFileSync(filePath, JSON.stringify(snapshot, null, 2), "utf8");

  console.log("📸 Deployment snapshot saved:", snapshot.id);

  return snapshot;
}

module.exports = { saveDeploymentSnapshot };