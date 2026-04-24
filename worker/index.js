const express = require("express");
const Sentry = require("@sentry/node");

// Init Sentry
Sentry.init({
  dsn: "https://216ffa4485f88b8250100eee059110b5@o4511260643229696.ingest.us.sentry.io/4511260644474880",
  tracesSampleRate: 1.0,
});

const app = express();

// Sentry request handler (FIXED)
app.use(Sentry.Handlers.requestHandler());

// Middlewares
app.use(express.json());
app.use(express.urlencoded({ extended: true }));

// Test route
app.get("/", (req, res) => {
  res.status(200).json({ ok: true });
});

// Force error route (for testing)
app.get("/error", () => {
  throw new Error("SENTRY TEST ERROR");
});

// Sentry error handler
app.use(Sentry.Handlers.errorHandler());

// Start server
const PORT = Number(process.env.PORT) || 3010;

app.listen(PORT, () => {
  console.log(`Server running on ${PORT}`);
});