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


TASK = """# Task: Optimize the Database-Backed Application

You are an expert software engineer specializing in application performance optimization, database systems, and SQL optimization.

Your task is to analyze and optimize the provided codebase to improve its overall execution performance, particularly for database-intensive workloads.

## Objectives

Optimize the application to achieve better end-to-end performance while preserving its original functionality and behavior.

Consider optimization opportunities across the entire application, including:

1. **Application Logic**
   - Identify inefficient algorithms, redundant computations, and unnecessary operations.
   - Reduce unnecessary object creation, data copying, and memory usage.
   - Improve application control flow and resource management.
   - Optimize transaction handling and database connection usage.

2. **Database Interaction**
   - Identify inefficient database access patterns.
   - Reduce unnecessary database round trips.
   - Improve query execution efficiency.
   - Optimize parameterized SQL statements and query construction.
   - Identify opportunities for batching operations.
   - Reduce unnecessary data retrieval and processing.

3. **Application-Database Interaction**
   - Identify inefficiencies between application logic and database operations.
   - Optimize how application operations interact with database transactions.
   - Reduce unnecessary communication between the application and database.
   - Improve coordination between application-level processing and SQL execution.

## Constraints

- Preserve the original application functionality and business logic.
- Maintain the existing database schema and data model.
- Preserve transaction correctness and ACID properties.
- Preserve concurrency safety and consistency guarantees.
- Do not remove required operations or weaken correctness guarantees for performance gains.
- Maintain compatibility with the existing database system and application environment.
- Avoid introducing unnecessary external dependencies.
- Do not make changes that compromise the correctness of database operations.

## Instructions

1. Examine the provided repository and understand its architecture, application logic, and database interactions.
2. Identify potential performance bottlenecks and optimization opportunities.
3. Apply appropriate optimizations directly to the source code.
4. Optimize the application as a whole rather than focusing exclusively on SQL queries or individual functions.
5. Keep modifications practical and consistent with the existing codebase.

Apply all changes only to the files listed under FILES TO OPTIMIZE; treat every other file as read-only context.

## Expected Output

Provide the optimized codebase with all necessary source code modifications.

Also provide a concise summary containing:

- Files modified.
- Optimizations implemented.
- Expected performance benefits.
- Any assumptions or potential limitations.

Prioritize measurable end-to-end performance improvements while maintaining functional equivalence with the original application."""

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
