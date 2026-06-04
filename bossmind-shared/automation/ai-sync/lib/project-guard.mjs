import fs from "fs";
import path from "path";

const FORBIDDEN_ROOTS = [
  "D:/Shakhsy11",
  "D:/BossMind-Apps",
];

export function resolveProject(projectsRegistry, projectId) {
  const projects = projectsRegistry?.projects || [];
  return projects.find((p) => p.project_id === projectId) || null;
}

export function assertProjectIsolation({ projectRoot, touchedPaths = [] }) {
  const rootNorm = path.resolve(projectRoot).toLowerCase();
  const violations = [];

  for (const forbidden of FORBIDDEN_ROOTS) {
    if (rootNorm.startsWith(path.resolve(forbidden).toLowerCase())) {
      violations.push(`project root in forbidden archive: ${forbidden}`);
    }
  }

  for (const rel of touchedPaths) {
    const abs = path.resolve(projectRoot, rel);
    if (!abs.toLowerCase().startsWith(rootNorm)) {
      violations.push(`path escapes project root: ${rel}`);
    }
    for (const forbidden of FORBIDDEN_ROOTS) {
      if (abs.toLowerCase().startsWith(path.resolve(forbidden).toLowerCase())) {
        violations.push(`path in forbidden root: ${rel}`);
      }
    }
  }

  return {
    ok: violations.length === 0,
    violations,
    projectRoot: rootNorm,
  };
}

export function projectExists(projectRoot) {
  return fs.existsSync(projectRoot);
}
