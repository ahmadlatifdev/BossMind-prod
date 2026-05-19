const fs = require("fs");
const path = require("path");
const { Client } = require("pg");

const ROOT = "D:/BossMind";

function getTargetFiles(dir, fileList = []) {
  const allowedFolders = [
    "bossmind-shared",
    "bossmind-master-admin",
    "bossmind-resumora",
    "bossmind-elegancyart",
    "bossmind-ai-video-generator",
    "bossmind-tiktok-ai",
    "bossmind-global-stock"
  ];

  const parts = dir.split(path.sep);

  if (parts.length > 3) {
    const projectFolder = parts[2];
    if (!allowedFolders.includes(projectFolder)) return fileList;
  }

  const files = fs.readdirSync(dir);

  files.forEach(file => {
    const fullPath = path.join(dir, file);

    if (
      fullPath.includes("node_modules") ||
      fullPath.includes(".git") ||
      fullPath.includes("dist") ||
      fullPath.includes("build")
    ) return;

    if (fs.statSync(fullPath).isDirectory()) {
      getTargetFiles(fullPath, fileList);
    } else {
      if (
        fullPath.endsWith(".js") ||
        fullPath.endsWith(".ts") ||
        fullPath.endsWith(".jsx") ||
        fullPath.endsWith(".tsx") ||
        fullPath.endsWith(".json")
      ) {
        fileList.push(fullPath);
      }
    }
  });

  return fileList;
}

async function main() {
  const client = new Client({
    connectionString: process.env.NEON_DB,
    ssl: { rejectUnauthorized: false }
  });

  await client.connect();

  await client.query(`
    CREATE TABLE IF NOT EXISTS bossmind_code_memory (
      file_path TEXT PRIMARY KEY,
      content TEXT,
      updated_at TIMESTAMPTZ DEFAULT NOW()
    );
  `);

  const files = getTargetFiles(ROOT);

  console.log("Scanning files:", files.length);

  for (const file of files) {
    try {
      const content = fs.readFileSync(file, "utf8");

      await client.query(
        `INSERT INTO bossmind_code_memory (file_path, content)
         VALUES ($1, $2)
         ON CONFLICT (file_path)
         DO UPDATE SET content = $2, updated_at = NOW()`,
        [file, content]
      );

      console.log("Saved:", file);

    } catch {
      // silent skip
    }
  }

  await client.end();

  console.log("Auto memory sync COMPLETE (FAST)");
}

main();