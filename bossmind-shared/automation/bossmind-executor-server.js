const express = require("express");
const { exec } = require("child_process");

const app = express();
app.use(express.json());

const run = (cmd) =>
  new Promise((resolve) => {
    exec(cmd, (err, stdout, stderr) => {
      resolve({ err: err?.message, stdout, stderr });
    });
  });

app.post("/health", async (req, res) => {
  const out = await run('powershell -ExecutionPolicy Bypass -File "D:\\BossMind\\bossmind-shared\\automation\\bossmind-unified-health-monitor.ps1"');
  res.json(out);
});

app.post("/validation", async (req, res) => {
  const out = await run('powershell -ExecutionPolicy Bypass -File "D:\\BossMind\\bossmind-shared\\automation\\bossmind-auto-validation-loop.ps1"');
  res.json(out);
});

app.post("/risk", async (req, res) => {
  const out = await run('powershell -ExecutionPolicy Bypass -File "D:\\BossMind\\bossmind-shared\\automation\\bossmind-predictive-risk-engine.ps1"');
  res.json(out);
});

app.listen(3000, () => {
  console.log("BossMind Executor API running on port 3000");
});
