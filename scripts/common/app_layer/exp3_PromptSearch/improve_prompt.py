"""Revise the general optimization guidance prompt from a verifier failure.

Given the current guidance (bullet lines), a verifier failure report and the
failing rewrite diff, ask one LLM for a revised, still workload-agnostic
guidance prompt. The shell orchestrator calls this; the pure helpers below are
kept module-level so they can be tested without the LLM.

Usage:
  improve_prompt.py --current FILE --output FILE --feedback FILE --diff FILE \
      --deny "token1,token2" --meta FILE [--model M] [--temperature F] \
      [--max-bytes N] [--max-bullets N]
"""

import argparse
import hashlib
import json
import os
import re
import sys
from datetime import datetime, timezone
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[4]
DIFF_LIMIT = 6000


def strip_fences(text):
    t = text.strip()
    if t.startswith("```") and t.endswith("```"):
        lines = t.splitlines()
        if len(lines) >= 2:
            lines = lines[1:]
            if lines and lines[-1].strip() == "```":
                lines = lines[:-1]
            return "\n".join(lines).strip()
    return t


def parse_guidance(text):
    """Bullet lines only, with their indented continuations; '*' becomes '-'."""
    bullets = []
    for raw in strip_fences(text).splitlines():
        line = raw.rstrip()
        if line.startswith("* "):
            line = "- " + line[2:]
        if line.startswith("- "):
            bullets.append(line)
        elif bullets and line[:1] in (" ", "\t") and line.strip():
            bullets.append(line)
        # anything else is preamble/epilogue prose: dropped
    return bullets


def find_violations(text, tokens):
    hits = []
    for token in tokens:
        if not token:
            continue
        if re.search(r"\b" + re.escape(token) + r"\b", text, re.IGNORECASE):
            hits.append(token)
    return hits


def drop_violations(lines, tokens):
    """Drop each offending bullet together with its indented continuations."""
    kept, dropped = [], []
    group, hit = [], False
    for line in lines + [None]:
        if line is None or line.startswith("- "):
            if group:
                (dropped if hit else kept).extend(group)
            group, hit = ([line], False) if line is not None else ([], False)
        else:
            group.append(line)
        if line is not None and find_violations(line, tokens):
            hit = True
    return kept, dropped


def guidance_bytes(lines):
    return len(("\n".join(lines) + "\n").encode("utf-8")) if lines else 0


def _smoke_key(line):
    """Message after the log level, so timestamps do not defeat dedupe."""
    match = re.search(r"\b(?:WARNING|ERROR|CRITICAL):\s*(.*)", line)
    return (match.group(1) if match else line).strip()


def summarize_smoke_log(path, limit=15):
    """Dedupe a smoke log by message, keep one example per error with a repeat
    count, and fold multi-line tracebacks into one entry."""
    try:
        with open(path, encoding="utf-8", errors="replace") as handle:
            lines = handle.readlines()
    except OSError:
        return []

    entries = []
    index = {}
    i = 0
    while i < len(lines):
        line = lines[i].rstrip("\n")
        if "Traceback" in line:
            block = [line.strip()]
            i += 1
            while i < len(lines) and lines[i].strip() and len(block) < 6:
                block.append(lines[i].strip())
                i += 1
            key = "traceback:" + block[-1]
            message = " | ".join(block)
        elif "WARNING:" in line or "ERROR" in line:
            message = line.strip()
            key = _smoke_key(line)
            i += 1
        else:
            i += 1
            continue

        if key in index:
            entries[index[key]][2] += 1
        else:
            index[key] = len(entries)
            entries.append([key, message, 1])

    out = []
    for _, message, count in entries[:limit]:
        if len(message) > 500:
            message = message[:497] + "..."
        out.append(message + (" (x{})".format(count) if count > 1 else ""))
    return out


def apply_caps(lines, max_bullets, max_bytes):
    """Cut whole bullets/lines at boundaries; the first bullet always survives."""
    out, bullets, size, truncated = [], 0, 0, False
    for line in lines:
        starts_bullet = line.startswith("- ")
        if starts_bullet:
            if bullets >= max_bullets:
                truncated = True
                continue
            bullets += 1
        line_bytes = len((line + "\n").encode("utf-8"))
        if out and size + line_bytes > max_bytes:
            truncated = True
            continue
        out.append(line)
        size += line_bytes
    return out, truncated


def failure_summary(feedback):
    parts = []
    status = feedback.get("rewrite_status")
    if status:
        parts.append("rewrite_status: {}".format(status))
    tail = (feedback.get("rewrite_log_tail") or "").strip()
    if tail:
        parts.append("rewrite_log_tail:\n{}".format(tail))
    smoke_errors = feedback.get("smoke_errors") or []
    if not smoke_errors and feedback.get("smoke_log"):
        smoke_errors = summarize_smoke_log(feedback["smoke_log"])
    if smoke_errors:
        parts.append("smoke_errors:\n{}".format("\n".join(smoke_errors)))
    checks = ((feedback.get("verify") or {}).get("checks")) or {}
    if isinstance(checks, dict):
        items = [dict(check or {}, name=name) for name, check in checks.items()]
    else:
        items = checks
    for check in items:
        state = str(check.get("status", "")).upper()
        if state not in ("FAIL", "WARN"):
            continue
        name = check.get("name") or check.get("id") or "check"
        issues = "; ".join(str(i) for i in (check.get("issues") or []))
        parts.append("- {} [{}]: {}".format(name, state, issues or "(no detail)"))
    return "\n".join(parts) if parts else "(no failure details reported)"


def build_prompt(current, feedback, diff, deny, max_bullets, max_bytes):
    deny_note = ""
    if deny:
        deny_note = (
            "\nNever use these forbidden tokens (case-insensitive): {}.\n".format(
                ", ".join(deny)
            )
        )
    return (
        "You revise optimization guidance for an LLM that rewrites database "
        "application code. The guidance must stay general: every rule must "
        "apply to any database application.\n\n"
        "CURRENT GUIDANCE:\n{}\n\n"
        "FAILURE SUMMARY:\n{}\n\n"
        "FAILING DIFF (truncated):\n{}\n\n"
        "CONSTRAINTS:\n"
        "- Return ONLY bullet lines, one rule per bullet.\n"
        "- Each bullet is a general rule about SQL, driver or application "
        "patterns applicable to any codebase.\n"
        "- Do not mention any specific benchmark, table, transaction, column "
        "or literal value.\n"
        "- No code and no markdown fences.\n"
        "- Keep rules that still hold.\n"
        "- If a rule is implicated in the failure, rewrite or remove it; a wrong "
        "rule is worse than no rule.\n"
        "- Merge and compress instead of appending forever.\n"
        "- At most {} bullets and {} bytes.\n"
        "- Address each failure above with a general rule.\n"
        "- Do not weaken behavior-preservation rules.\n"
        "{}".format(
            current.strip() or "(none)",
            failure_summary(feedback),
            diff.strip()[:DIFF_LIMIT] or "(no diff)",
            max_bullets,
            max_bytes,
            deny_note,
        )
    )


def call_llm(model, temperature, prompt):
    from dotenv import load_dotenv

    load_dotenv(REPO_ROOT / ".env")
    from google import genai
    from google.genai import types

    client = genai.Client(
        vertexai=True,
        project=os.environ["GOOGLE_CLOUD_PROJECT"],
        location=os.environ.get("GOOGLE_CLOUD_LOCATION", "global"),
    )
    resp = client.models.generate_content(
        model=model,
        contents=prompt,
        config=types.GenerateContentConfig(
            temperature=temperature, max_output_tokens=65536
        ),
    )
    return resp.text or ""


def read_text(path):
    try:
        return Path(path).read_text(encoding="utf-8")
    except (OSError, UnicodeDecodeError) as exc:
        print("ERROR: cannot read {}: {}".format(path, exc), file=sys.stderr)
        sys.exit(1)


def write_meta(path, payload):
    try:
        Path(path).write_text(
            json.dumps(payload, indent=2) + "\n", encoding="utf-8"
        )
    except OSError as exc:
        print("ERROR: cannot write meta {}: {}".format(path, exc), file=sys.stderr)
        sys.exit(1)


def main():
    parser = argparse.ArgumentParser(description="Revise prompt-search guidance")
    parser.add_argument("--current", required=True)
    parser.add_argument("--output", required=True)
    parser.add_argument("--feedback", required=True)
    parser.add_argument("--diff", default=None)
    parser.add_argument("--deny", default="")
    parser.add_argument("--model", default="gemini-3.5-flash-lite")
    parser.add_argument("--temperature", type=float, default=0.2)
    parser.add_argument("--max-bytes", type=int, default=4096)
    parser.add_argument("--max-bullets", type=int, default=25)
    parser.add_argument("--meta", required=True)
    args = parser.parse_args()

    current = read_text(args.current)
    try:
        feedback = json.loads(read_text(args.feedback))
    except ValueError as exc:
        print("ERROR: bad feedback JSON {}: {}".format(args.feedback, exc),
              file=sys.stderr)
        sys.exit(1)
    if not isinstance(feedback, dict):
        print("ERROR: feedback must be a JSON object", file=sys.stderr)
        sys.exit(1)

    diff = ""
    if args.diff and Path(args.diff).is_file():
        diff = read_text(args.diff)
    deny = [t.strip().lower() for t in args.deny.split(",") if t.strip()]

    prompt = build_prompt(
        current, feedback, diff, deny, args.max_bullets, args.max_bytes
    )
    attempts = 0
    try:
        attempts += 1
        bullets = parse_guidance(call_llm(args.model, args.temperature, prompt))
    except Exception as exc:
        print("ERROR: LLM call failed: {}".format(exc), file=sys.stderr)
        sys.exit(1)
    if not bullets:
        print("ERROR: model returned no bullet lines", file=sys.stderr)
        sys.exit(1)

    guidance = "\n".join(bullets)
    hits = find_violations(guidance, deny)
    sanitized = list(hits)
    if hits:
        retry = (
            prompt
            + "\n\nYOUR PREVIOUS ANSWER:\n{}\n\nThat answer used forbidden "
            "tokens: {}. Rewrite it without them.\n".format(guidance, ", ".join(hits))
        )
        try:
            attempts += 1
            bullets = parse_guidance(call_llm(args.model, args.temperature, retry))
        except Exception as exc:
            print("ERROR: LLM re-ask failed: {}".format(exc), file=sys.stderr)
            sys.exit(1)
        if not bullets:
            print("ERROR: model returned no bullet lines", file=sys.stderr)
            sys.exit(1)
        guidance = "\n".join(bullets)
        hits = find_violations(guidance, deny)
        sanitized = sorted(set(sanitized) | set(hits))

    dropped = []
    if hits:
        bullets, dropped = drop_violations(bullets, deny)

    over = len([b for b in bullets if b.startswith("- ")]) > args.max_bullets or (
        guidance_bytes(bullets) > args.max_bytes
    )
    truncated = False
    if over:
        retry = (
            prompt
            + "\n\nYOUR PREVIOUS ANSWER:\n{}\n\nIt exceeds the caps ({} "
            "bullets, {} bytes). Merge and compress it to at most {} bullets "
            "and {} bytes.\n".format(
                "\n".join(bullets),
                len([b for b in bullets if b.startswith("- ")]),
                guidance_bytes(bullets),
                args.max_bullets,
                args.max_bytes,
            )
        )
        try:
            attempts += 1
            bullets = parse_guidance(call_llm(args.model, args.temperature, retry))
        except Exception as exc:
            print("ERROR: LLM re-ask failed: {}".format(exc), file=sys.stderr)
            sys.exit(1)
        if bullets:
            bullets, extra = drop_violations(bullets, deny)
            dropped.extend(extra)
            if extra:
                sanitized = sorted(set(sanitized) | set(find_violations(
                    "\n".join(extra), deny)))

    bullets, capped = apply_caps(bullets, args.max_bullets, args.max_bytes)
    truncated = truncated or capped
    if not bullets:
        print("ERROR: no guidance bullets survived", file=sys.stderr)
        sys.exit(1)

    text = "\n".join(bullets) + "\n"
    try:
        Path(args.output).write_text(text, encoding="utf-8")
    except OSError as exc:
        print("ERROR: cannot write output {}: {}".format(args.output, exc),
              file=sys.stderr)
        sys.exit(1)

    data = text.encode("utf-8")
    write_meta(args.meta, {
        "model": args.model,
        "temperature": args.temperature,
        "attempts": attempts,
        "generated_sha256": hashlib.sha256(data).hexdigest(),
        "bytes": len(data),
        "bullets": len([b for b in bullets if b.startswith("- ")]),
        "sanitized_tokens": sanitized,
        "dropped_bullets": dropped,
        "truncated": truncated,
        "timestamp": datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
    })

    print(
        "improved: {} bullets, {} bytes, sanitized={}, dropped={}".format(
            len([b for b in bullets if b.startswith("- ")]),
            len(data),
            len(sanitized),
            len(dropped),
        )
    )


if __name__ == "__main__":
    main()
