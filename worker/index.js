const Sentry = require('@sentry/node'); Sentry.init({ dsn: 'https://216ffa4485f88b8250100eee059110b5@o4511260643229696.ingest.us.sentry.io/4511260644474880' }); async function run(){ Sentry.captureException(new Error('SENTRY FINAL DIRECT DSN')); await Sentry.flush(5000); console.log('FLUSH DONE'); setInterval(()=>console.log('alive'),60000); } run();
//force update
