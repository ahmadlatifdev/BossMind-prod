const http = require("http");
const { execFile } = require("child_process");
const fs = require("fs");
const path = require("path");

const envPath = path.join(__dirname, "..", ".env");
const env = Object.fromEntries(
  fs.readFileSync(envPath, "utf8")
    .split(/\r?\n/)
    .filter(Boolean)
    .map(line => {
      const i = line.indexOf("=");
      return [line.slice(0, i), line.slice(i + 1)];
    })
);

const PORT = Number(env.BOSSMIND_AGENT_PORT || 7077);
const KEY = env.BOSSMIND_REMOTE_RUN_KEY;
const RUNNER = env.BOSSMIND_MASTER_RUNNER;
const ALLOWED_PROJECTS = new Set((env.BOSSMIND_ALLOWED_PROJECTS || "").split(","));
const ALLOWED_ACTIONS = new Set((env.BOSSMIND_ALLOWED_ACTIONS || "").split(","));

function json(res, code, data) {
  res.writeHead(code, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data, null, 2));
}

const server = http.createServer((req, res) => {
  if (req.method !== "POST" || req.url !== "/run") {
    return json(res, 404, { ok: false, error: "not_found" });
  }

  if (req.headers["x-bossmind-key"] !== KEY) {
    return json(res, 401, { ok: false, error: "unauthorized" });
  }

  let body = "";
  req.on("data", chunk => body += chunk);
  req.on("end", () => {
    try {
      const input = JSON.parse(body || "{}");
      const project = input.project;
      const action = input.action;

      if (!ALLOWED_PROJECTS.has(project)) {
        return json(res, 403, { ok: false, error: "project_not_allowed" });
      }

      if (!ALLOWED_ACTIONS.has(action)) {
        return json(res, 403, { ok: false, error: "action_not_allowed" });
      }

      execFile(
        "powershell.exe",
        [
          "-ExecutionPolicy", "Bypass",
          "-File", RUNNER,
          "-Project", project,
          "-Action", action
        ],
        { windowsHide: true },
        (error, stdout, stderr) => {
          json(res, error ? 500 : 200, {
            ok: !error,
            project,
            action,
            stdout,
            stderr,
            error: error ? error.message : null
          });
        }
      );
    } catch (e) {
      json(res, 400, { ok: false, error: e.message });
    }
  });
});

server.listen(PORT, "127.0.0.1", () => {
  console.log(`BossMind Remote Agent active on http://127.0.0.1:${PORT}/run`);
});
