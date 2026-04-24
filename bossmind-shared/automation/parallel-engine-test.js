const { runParallelExecution } = require("./parallel-execution-engine");

async function testParallelEngine() {
  const result = await runParallelExecution([
    {
      taskId: "parallel_resumora_001",
      project: "bossmind-resumora",
      requirementLockId: "lock_resumora_test",
      lockedFileScope: ["bossmind-resumora/app/page.tsx"],
    },
    {
      taskId: "parallel_worker_001",
      project: "bossmind-prod",
      requirementLockId: "lock_worker_test",
      lockedFileScope: ["worker/supervisor.js"],
    },
  ]);

  console.log("Parallel Execution Result:", result);
}

testParallelEngine();