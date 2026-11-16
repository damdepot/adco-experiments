import os
import re
from pathlib import Path


def strip_fences(s: str) -> str:
    t = s.strip()
    if t.startswith("```") and t.endswith("```"):
        lines = t.splitlines()
        if len(lines) >= 2:
            lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            return "\n".join(lines).strip()
    return t


def parse_response(text: str) -> dict[str, str]:
    parts = re.split(r'^### FILE:[ \t]*(.+?)[ \t]*$', text, flags=re.M)
    result: dict[str, str] = {}
    for i in range(1, len(parts) - 1, 2):
        path = parts[i].strip()
        body = strip_fences(parts[i + 1])
        result[path] = body
    return result


def safe_target(output_dir: Path, rel_path: str, allowed: set) -> "Path | None":
    if not rel_path or os.path.isabs(rel_path):
        return None
    parts = Path(rel_path).parts
    if ".." in parts:
        return None
    normalized = "/".join(parts)
    if normalized not in allowed:
        return None
    target = (output_dir / rel_path).resolve()
    root = output_dir.resolve()
    try:
        if not target.is_relative_to(root):
            return None
    except AttributeError:
        if os.path.commonpath([str(target), str(root)]) != str(root):
            return None
    return target


def select_files(output_dir: Path, db: str) -> tuple:
    # Query-layer workload compiled into a single driver file.
    if (output_dir / "db_app.py").exists():
        context = ["schema.sql"] if (output_dir / "schema.sql").exists() else []
        return ["db_app.py"], context

    if db.lower() in ("postgres", "postgresql"):
        driver = "drivers/postgresdriver.py"
    else:
        driver = "drivers/mysqldriver.py"

    rewrite_files = []
    if (output_dir / driver).exists():
        rewrite_files.append(driver)

    entry = None
    for cand in ("tpcc.py", "main.py"):
        if (output_dir / cand).exists():
            entry = cand
            break
    if entry:
        rewrite_files.append(entry)

    context_files = []
    for cand in ("tpcc.postgres.sql", "tpcc.sql", "schema.sql"):
        if (output_dir / cand).exists():
            context_files.append(cand)
            break

    return rewrite_files, context_files


def _read(output_dir: Path, relpath: str) -> str:
    return (output_dir / relpath).read_text(encoding="utf-8")


TASK = """# Task: Aggressively Optimize the Database-Backed Application

You are an expert software engineer specializing in application performance optimization, database systems, and SQL optimization.

Rewrite the provided application so it runs substantially faster against its database. Assume the current code leaves significant performance on the table and that larger gains are available than a cautious edit would find.

Optimize the application as a whole rather than individual functions or queries in isolation. Make the program faster, not merely different: renaming, reformatting, comments, dead-code removal and trivial refactors are not optimizations. If the execution path and the database work are essentially unchanged, you have not done the task.

Be aggressive. Do not settle for small, safe tweaks when a deeper restructuring would deliver more. You must change at least one file; returning the input unchanged is a failure.

The rewritten application must still do the same work and produce the same results as the original."""

RULES = [
    "Rules:",
    "- Only modify the files listed under FILES TO OPTIMIZE.",
    "- Return the FULL contents of every file you change, each preceded by a line exactly like:",
    "### FILE: <relative path>",
    "- Do not wrap file contents in markdown code fences.",
    "- If a file needs no change, omit it.",
    "- Do not add new files or dependencies.",
]


def build_prompt(output_dir: Path, rewrite_files: list, context_files: list) -> str:
    # Honestly naive single-shot baseline: task + files + I/O mechanics only.
    # No optimization guidance: whatever the model does with the code as-is is
    # the floor to beat.
    lines = [
        *TASK.splitlines(),
        "",
    ]
    lines.extend(RULES)
    lines.append("")
    if context_files:
        lines.append("DATABASE SCHEMA (read-only context):")
        for relpath in context_files:
            lines.append(f"===== BEGIN FILE: {relpath} =====")
            lines.append(_read(output_dir, relpath))
            lines.append("===== END FILE =====")
            lines.append("")
    lines.append("FILES TO OPTIMIZE:")
    for relpath in rewrite_files:
        lines.append(f"===== BEGIN FILE: {relpath} =====")
        lines.append(_read(output_dir, relpath))
        lines.append("===== END FILE =====")
    return "\n".join(lines)
