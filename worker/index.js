require('dotenv').config(); const Sentry = require('@sentry/node'); Sentry.init({ dsn: process.env.SENTRY_DSN }); throw new Error('SENTRY LIVE TEST NOW');
