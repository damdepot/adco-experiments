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


def build_prompt(output_dir: Path, rewrite_files: list, context_files: list) -> str:
    lines = [
        "You are a coding assistant optimizing a database application.",
        "",
        "Task: improve the performance of the application below without changing its",
        "observable behavior or its public interface. Performance here means the speed",
        "and throughput of this application's own execution against its database.",
        "",
        "Rules:",
        "- Only modify the files listed under FILES TO OPTIMIZE.",
        "- Use the current idiomatic features of the programming language. Where you",
        "  find outdated or deprecated constructs, convert them to their modern",
        "  equivalents.",
        "- Preserve not only control flow but the data the application reads and writes.",
        "- When several separate lookups are combined into one query, the database may",
        "  return the matching rows in any order: keep every result tied to the input",
        "  it came from by key, never by position.",
        "- Send values through the driver's own binding, never by building statements",
        "  or bulk data by hand, so values are escaped and typed correctly.",
        "- Return the FULL contents of every file you change, each preceded by a line exactly like:",
        "### FILE: <relative path>",
        "- Do not wrap file contents in markdown code fences.",
        "- If a file needs no change, omit it.",
        "- Do not add new files or dependencies.",
        "",
    ]
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
