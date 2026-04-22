require("dotenv").config();
const Sentry = require("@sentry/node");
const express = require("express");

const app = express();
const PORT = process.env.PORT || 3010;

Sentry.init({
  dsn: process.env.SENTRY_DSN,
  tracesSampleRate: 1.0,
});

// NEW correct middleware (NO Handlers)
app.use(Sentry.Handlers?.requestHandler?.() || ((req,res,next)=>next()));

app.use(express.json());

app.get("/", (req, res) => {
  res.send("BossMind Worker LIVE");
});

app.get("/sentry-test", (req, res) => {
  throw new Error("BossMind LIVE error test");
});

// Error capture
app.use(Sentry.Handlers?.errorHandler?.() || ((err,req,res,next)=>next(err)));

app.listen(PORT, () => {
  console.log(`LIVE on port ${PORT}`);
});