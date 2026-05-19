const { exec } = require("child_process");
const path = require("path");

const BASE_DIR = "D:\\BossMind\\bossmind-shared\\automation";

function run(fileName) {
  const fullPath = path.join(BASE_DIR, fileName);

  return new Promise((resolve, reject) => {
    exec(`node "${fullPath}"`, { cwd: BASE_DIR }, (error, stdout, stderr) => {
      if (stdout) console.log(stdout);
      if (stderr) console.error(stderr);

      if (error) return reject(error);
      resolve();
    });
  });
}

async function loop() {
  console.log("AUTO_LOOP_START");

  try {
    await run("sentry-test.js");
    await run("run-mindstorm.js");
    await run("execute-repair.js");
    await run("neon-sync.js");

    console.log("LOOP_COMPLETED");
  } catch (err) {
    console.log("LOOP_ERROR_RETRYING");
  }

  setTimeout(loop, 10000);
}

loop();