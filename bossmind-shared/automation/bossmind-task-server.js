const express = require("express");
const app = express();

app.use(express.json());

let currentTask = null;
let lastResult = null;

app.get("/task", (req, res) => {
  res.json(currentTask || {});
  currentTask = null;
});

app.post("/task", (req, res) => {
  currentTask = req.body;
  res.json({ status: "TASK_RECEIVED" });
});

app.post("/task/result", (req, res) => {
  lastResult = req.body;
  console.log("RESULT:", lastResult);
  res.json({ status: "RESULT_SAVED" });
});

app.get("/result", (req, res) => {
  res.json(lastResult || {});
});

app.listen(3000, () => {
  console.log("BossMind Task Server running");
});
