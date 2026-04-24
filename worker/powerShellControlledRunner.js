const { execFile } = require("child_process");

const ALLOWED_COMMANDS = new Set([
  "git",
  "npm",
  "node",
  "powershell",
  "pwsh",
]);

const BLOCKED_PATTERNS = [
  "rm -rf",
  "del /s",
  "format",
  "Remove-Item -Recurse -Force",
  "Invoke-Expression",
  "iex",
  "curl ",
  "wget ",
];

function runControlledPowerShell({ command, args = [], requirementLock, boundaryCheck }) {
  return new Promise((resolve) => {
    if (!requirementLock || requirementLock.status !== "locked") {
      return resolve({
        ok: false,
        reason: "Blocked: no valid Requirement Lock",
      });
    }

    if (!boundaryCheck || boundaryCheck.allowed !== true) {
      return resolve({
        ok: false,
        reason: "Blocked: Execution Boundary not approved",
      });
    }

    if (!ALLOWED_COMMANDS.has(command)) {
      return resolve({
        ok: false,
        reason: `Blocked command: ${command}`,
      });
    }

    const joined = [command, ...args].join(" ");

    for (const pattern of BLOCKED_PATTERNS) {
      if (joined.includes(pattern)) {
        return resolve({
          ok: false,
          reason: `Blocked dangerous pattern: ${pattern}`,
        });
      }
    }

    execFile(command, args, { shell: false }, (error, stdout, stderr) => {
      if (error) {
        return resolve({
          ok: false,
          reason: error.message,
          stdout,
          stderr,
        });
      }

      return resolve({
        ok: true,
        stdout,
        stderr,
      });
    });
  });
}

module.exports = { runControlledPowerShell };