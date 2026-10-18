import argparse
import os
import py_compile
import shutil
import sys
from pathlib import Path

from .rewrite import build_prompt, parse_response, safe_target, select_files


def main() -> None:
    parser = argparse.ArgumentParser(description="Naive single-shot LLM rewriter")
    parser.add_argument("--source-dir", required=True)
    parser.add_argument("--output-dir", required=True)
    parser.add_argument("--db", default="postgres")
    parser.add_argument("--model", default="gemini-3.5-flash-lite")
    args = parser.parse_args()

    repo_root = Path(__file__).resolve().parents[3]
    from dotenv import load_dotenv

    load_dotenv(repo_root / ".env")

    source_dir = Path(args.source_dir)
    output_dir = Path(args.output_dir)

    if not source_dir.is_dir():
        print(f"ERROR: source-dir is not a directory: {source_dir}", file=sys.stderr)
        sys.exit(1)

    shutil.rmtree(output_dir, ignore_errors=True)
    shutil.copytree(
        source_dir,
        output_dir,
        ignore=shutil.ignore_patterns(
            ".git", ".venv", "venv", "__pycache__", "*.pyc"
        ),
    )

    rewrite_files, context_files = select_files(output_dir, args.db)
    if not rewrite_files or not (
        rewrite_files[0] == "db_app.py" or rewrite_files[0].startswith("drivers/")
    ):
        print(
            f"ERROR: no driver file found for db={args.db} in {output_dir}",
            file=sys.stderr,
        )
        sys.exit(1)

    originals: dict[str, bytes] = {
        rel: (output_dir / rel).read_bytes() for rel in rewrite_files
    }
    prompt = build_prompt(output_dir, rewrite_files, context_files)

    try:
        from google import genai
        from google.genai import types

        client = genai.Client(
            vertexai=True,
            project=os.environ["GOOGLE_CLOUD_PROJECT"],
            location=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"),
        )
        resp = client.models.generate_content(
            model=args.model,
            contents=prompt,
            config=types.GenerateContentConfig(
                temperature=0.0, max_output_tokens=65536
            ),
        )
        text = resp.text or ""
    except Exception as exc:
        print(f"WARNING: LLM call failed: {exc}", file=sys.stderr)
        sys.exit(1)

    parsed = parse_response(text)
    (output_dir.parent / "llm_response.txt").write_text(text, encoding="utf-8")

    changed = 0
    restored = 0
    for path, content in parsed.items():
        target = safe_target(output_dir, path, set(rewrite_files))
        if target is None:
            print(f"WARNING: unsafe or unknown target, skipping: {path}", file=sys.stderr)
            continue
        target.write_text(content, encoding="utf-8")
        try:
            # shortcut: syntax-only check; runtime import errors are not caught
            py_compile.compile(str(target), doraise=True)
            changed += 1
        except Exception as exc:
            if path in originals:
                target.write_bytes(originals[path])
            print(f"WARNING: compile failed, restored {path}: {exc}", file=sys.stderr)
            restored += 1

    print(f"files changed: {changed}, restored: {restored}")
    if changed == 0:
        print("ERROR: rewrite produced no usable files", file=sys.stderr)
        sys.exit(1)
    sys.exit(0)


if __name__ == "__main__":
    main()
