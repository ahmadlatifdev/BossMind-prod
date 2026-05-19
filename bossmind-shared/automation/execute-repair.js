require("./env-core-loader");

const fs = require("fs");
const path = require("path");
const fetch = require("node-fetch");
const { Octokit } = require("@octokit/rest");

const memoryDir = path.join(__dirname, "memory");
const ideasPath = path.join(memoryDir, "mindstorm-ideas.json");
const repairLogPath = path.join(memoryDir, "repair-log.json");

function readJson(filePath, fallback) {
  if (!fs.existsSync(filePath)) return fallback;
  return JSON.parse(fs.readFileSync(filePath, "utf8"));
}

function writeJson(filePath, data) {
  fs.writeFileSync(filePath, JSON.stringify(data, null, 2), "utf8");
}

function requireEnv(key) {
  if (!process.env[key] || process.env[key].includes("YOUR_")) {
    throw new Error(`MISSING_ENV_${key}`);
  }
  return process.env[key];
}

async function callDeepSeek(latestIdea) {
  const apiKey = requireEnv("DEEPSEEK_API_KEY");

  const response = await fetch("https://api.deepseek.com/v1/chat/completions", {
    method: "POST",
    headers: {
      Authorization: `Bearer ${apiKey}`,
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      model: "deepseek-chat",
      messages: [
        {
          role: "system",
          content:
            "You are BossMind repair analyst. Return a concise JSON repair plan with rootCause, fixPlan, files, risk, and verification."
        },
        {
          role: "user",
          content: JSON.stringify(latestIdea)
        }
      ]
    })
  });

  const data = await response.json();

  if (!response.ok) {
    throw new Error(`DEEPSEEK_FAILED_${response.status}: ${JSON.stringify(data)}`);
  }

  console.log("AI_RESPONSE_RECEIVED");

  return data.choices?.[0]?.message?.content || "NO_DEEPSEEK_CONTENT";
}

async function triggerGitHub(latestIdea, aiResult) {
  const octokit = new Octokit({
    auth: requireEnv("GITHUB_TOKEN")
  });

  const owner = requireEnv("GITHUB_OWNER");
  const repo = requireEnv("GITHUB_REPO");

  await octokit.repos.createDispatchEvent({
    owner,
    repo,
    event_type: "bossmind_auto_fix",
    client_payload: {
      ideaId: latestIdea.id,
      source: latestIdea.source,
      title: latestIdea.title,
      aiResult
    }
  });

  console.log("GITHUB_TRIGGERED");

  return {
    status: "triggered",
    owner,
    repo,
    event_type: "bossmind_auto_fix"
  };
}

async function triggerDeploy() {
  const webhook = requireEnv("DEPLOY_WEBHOOK_URL");

  const response = await fetch(webhook, {
    method: "POST"
  });

  if (!response.ok) {
    throw new Error(`DEPLOY_TRIGGER_FAILED_${response.status}`);
  }

  console.log("DEPLOY_TRIGGERED");

  return {
    status: "triggered",
    httpStatus: response.status
  };
}

async function main() {
  if (!fs.existsSync(memoryDir)) fs.mkdirSync(memoryDir, { recursive: true });

  const ideas = readJson(ideasPath, []);
  const latestIdea = ideas[ideas.length - 1];

  if (!latestIdea) {
    throw new Error("NO_MINDSTORM_IDEA_FOUND");
  }

  const aiResult = await callDeepSeek(latestIdea);
  const githubResult = await triggerGitHub(latestIdea, aiResult);
  const deployResult = await triggerDeploy();

  const repairResult = {
    id: `repair_${Date.now()}`,
    sourceIdeaId: latestIdea.id,
    createdAt: new Date().toISOString(),
    system: "BossMind",
    mode: "real_autonomous_repair_engine_v2",
    status: "completed",
    steps: {
      sentryInput: {
        status: "received",
        source: latestIdea.source,
        title: latestIdea.title,
        reason: latestIdea.reason
      },
      deepseekAnalysis: {
        status: "executed_real_api",
        result: aiResult
      },
      githubFix: githubResult,
      deployVerification: deployResult,
      memorySave: {
        status: "saved_local_first",
        target: repairLogPath
      }
    }
  };

  const logs = readJson(repairLogPath, []);
  logs.push(repairResult);
  writeJson(repairLogPath, logs);

  console.log("REPAIR_ENGINE_COMPLETED_REAL");
}

main().catch((error) => {
  console.error("REPAIR_ENGINE_FAILED");
  console.error(error.message);
  process.exit(1);
});