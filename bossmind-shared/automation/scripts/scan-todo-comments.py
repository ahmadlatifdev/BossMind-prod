#!/usr/bin/env python3
"""
Scan D:\\BossMind for TODO comments in source/code files and write a report.

Usage:
  python scan-todo-comments.py
  python scan-todo-comments.py --root D:/BossMind --out report.json
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import asdict, dataclass
from datetime import datetime, timezone
from pathlib import Path

DEFAULT_ROOT = Path(r"D:\BossMind")

# Directories to skip (relative names anywhere in path)
SKIP_FILE_NAMES = {
    "scan-todo-comments.py",  # meta-comments in this scanner
}

SKIP_DIR_NAMES = {
    ".git",
    ".next",
    ".turbo",
    ".cache",
    ".venv",
    "venv",
    "node_modules",
    "__pycache__",
    "dist",
    "build",
    "out",
    "coverage",
    ".cursor",
    "_archive",
}

# File extensions treated as code / markup with comments
CODE_EXTENSIONS = {
    ".py",
    ".js",
    ".mjs",
    ".cjs",
    ".ts",
    ".tsx",
    ".jsx",
    ".java",
    ".kt",
    ".go",
    ".rs",
    ".c",
    ".h",
    ".cpp",
    ".hpp",
    ".cs",
    ".php",
    ".rb",
    ".swift",
    ".scala",
    ".sql",
    ".sh",
    ".bash",
    ".ps1",
    ".psm1",
    ".yaml",
    ".yml",
    ".json",
    ".jsonc",
    ".html",
    ".htm",
    ".css",
    ".scss",
    ".sass",
    ".less",
    ".vue",
    ".svelte",
    ".md",
    ".mdx",
    ".xml",
    ".toml",
    ".ini",
    ".cfg",
    ".env.example",
}

# TODO in line comments (#, //, --) or block comments (/* */, <!-- -->)
TODO_PATTERN = re.compile(
    r"(?i)(?:"
    r"(?:^|\s)(?:#|//|--)\s*TODO\b[^\n]*"
    r"|/\*[^*]*\bTODO\b[^*]*\*/"
    r"|<!--[^>]*\bTODO\b[^>]*-->"
    r"|^\s*\*\s+TODO\b[^\n]*"
    r")",
    re.MULTILINE,
)

# Line must look like a real comment containing TODO (not string/regex literals)
COMMENT_LINE_TODO = re.compile(
    r"(?i)^\s*"
    r"(?:#|//|--|/\*+|<!--|\*)\s*"
    r".*\bTODO\b",
)


@dataclass
class TodoHit:
    file: str
    line: int
    column: int
    text: str


def should_skip_dir(path: Path) -> bool:
    return path.name in SKIP_DIR_NAMES


def is_code_file(path: Path) -> bool:
    if path.suffix.lower() in CODE_EXTENSIONS:
        return True
    name = path.name.lower()
    if name in ("dockerfile", "makefile", "gemfile", "rakefile"):
        return True
    return False


def extract_todos(content: str, path: Path) -> list[TodoHit]:
    hits: list[TodoHit] = []
    lines = content.splitlines()

    for match in TODO_PATTERN.finditer(content):
        line_no = content[: match.start()].count("\n") + 1
        line_text = lines[line_no - 1] if line_no <= len(lines) else match.group(0)
        col = match.start() - content.rfind("\n", 0, match.start())
        hits.append(
            TodoHit(
                file=str(path),
                line=line_no,
                column=col,
                text=line_text.strip(),
            )
        )

    seen_lines = {h.line for h in hits}
    for i, line in enumerate(lines, start=1):
        if i in seen_lines:
            continue
        if COMMENT_LINE_TODO.match(line):
            hits.append(
                TodoHit(
                    file=str(path),
                    line=i,
                    column=line.upper().find("TODO") + 1,
                    text=line.strip(),
                )
            )
    return hits


def scan_root(root: Path) -> list[TodoHit]:
    all_hits: list[TodoHit] = []
    if not root.is_dir():
        raise FileNotFoundError(f"Root not found: {root}")

    for path in root.rglob("*"):
        if not path.is_file():
            continue
        if any(part in SKIP_DIR_NAMES for part in path.parts):
            continue
        if path.name in SKIP_FILE_NAMES or not is_code_file(path):
            continue
        try:
            text = path.read_text(encoding="utf-8", errors="replace")
        except OSError as exc:
            print(f"skip (read error): {path} — {exc}", file=sys.stderr)
            continue
        all_hits.extend(extract_todos(text, path))

    all_hits.sort(key=lambda h: (h.file.lower(), h.line, h.column))
    return all_hits


def write_reports(hits: list[TodoHit], root: Path, out_base: Path) -> tuple[Path, Path]:
    out_base.parent.mkdir(parents=True, exist_ok=True)
    json_path = out_base.with_suffix(".json")
    txt_path = out_base.with_suffix(".txt")

    by_file: dict[str, list[dict]] = {}
    for h in hits:
        by_file.setdefault(h.file, []).append(asdict(h))

    payload = {
        "schema": "bossmind-todo-scan/v1",
        "root": str(root),
        "scannedAt": datetime.now(timezone.utc).isoformat(),
        "totalHits": len(hits),
        "fileCount": len(by_file),
        "hits": [asdict(h) for h in hits],
        "byFile": by_file,
    }
    json_path.write_text(json.dumps(payload, indent=2), encoding="utf-8")

    lines = [
        f"BossMind TODO scan report",
        f"Root: {root}",
        f"Scanned: {payload['scannedAt']}",
        f"Total TODO hits: {len(hits)}",
        f"Files with TODOs: {len(by_file)}",
        "",
    ]
    current_file = None
    for h in hits:
        if h.file != current_file:
            current_file = h.file
            lines.append(f"\n## {h.file}")
        lines.append(f"  L{h.line}:{h.column}  {h.text}")

    txt_path.write_text("\n".join(lines) + "\n", encoding="utf-8")
    return json_path, txt_path


def main() -> int:
    parser = argparse.ArgumentParser(description="Scan BossMind for TODO comments.")
    parser.add_argument("--root", type=Path, default=DEFAULT_ROOT, help="Scan root directory")
    parser.add_argument(
        "--out",
        type=Path,
        default=None,
        help="Report base path without extension (default: <root>/bossmind-shared/logs/todo-scan-<date>)",
    )
    args = parser.parse_args()
    root = args.root.resolve()
    stamp = datetime.now().strftime("%Y-%m-%d")
    out_base = args.out or (root / "bossmind-shared" / "logs" / f"todo-scan-{stamp}")

    print(f"Scanning {root} ...")
    hits = scan_root(root)
    json_path, txt_path = write_reports(hits, root, out_base)

    print(f"Found {len(hits)} TODO(s) in {len({h.file for h in hits})} file(s).")
    print(f"JSON: {json_path}")
    print(f"Text: {txt_path}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
