#!/usr/bin/env python3
"""Robustness-only report: one table across every arm sweep.

Reads results/tpcc/robustness/<arm>/latest.json (written by run_arm_robustness.sh)
and writes reports/tpcc/robustness.md. Arms without a sweep are not listed.
The terminal gets an aligned plain-text table; the file gets markdown.
"""

import glob
import json
import os
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
RESULTS = os.path.join(ROOT, "results", "tpcc", "robustness")
OUT_DIR = os.path.join(ROOT, "reports", "tpcc")
OUT_FILE = os.path.join(OUT_DIR, "robustness.md")

ORDER = ["naive-llm", "aco", "adco", "py-dbridge"]
DISPLAY = {"naive-llm": "Naive-LLM", "aco": "ACo", "adco": "ADCo", "py-dbridge": "Py-DBridge"}
SYMBOL = {"PASS": "✓", "FAIL": "✗", "WARN": "!", "UNVERIFIED": "?"}


def load():
    docs = []
    for path in sorted(glob.glob(os.path.join(RESULTS, "*", "latest.json"))):
        try:
            with open(path, encoding="utf-8") as handle:
                doc = json.load(handle)
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict) and doc.get("arm"):
            docs.append(doc)
    docs.sort(key=lambda d: (ORDER.index(d["arm"]) if d["arm"] in ORDER else len(ORDER), d["arm"]))
    return docs


def display(doc):
    return DISPLAY.get(doc["arm"], doc["arm"])


def counts(doc):
    c = doc.get("counts") or {}
    return (int(c.get("pass") or 0), int(c.get("fail") or 0),
            int(c.get("warn") or 0), int(c.get("unverified") or 0))


def failed_runs(doc):
    return [f.get("run") for f in (doc.get("failures") or [])]


def fmt_duration(seconds):
    return f"{seconds}s" if seconds is not None else "-"


def text_report(docs):
    rows = []
    for doc in docs:
        passed, failed, warn, unverified = counts(doc)
        total = int(doc.get("runs_completed") or 0)
        rate = f"{100 * passed / total:.0f}%" if total else "-"
        fails = ", ".join(str(r) for r in failed_runs(doc)) or "-"
        rows.append((display(doc), total, passed, failed, warn + unverified, rate,
                     doc.get("status") or "UNVERIFIED", fails))

    headers = ("Arm", "Runs", "Pass", "Fail", "Other", "Rate", "Status", "Failed runs")
    widths = [max(len(str(r[i])) for r in [headers] + rows) for i in range(len(headers))]
    widths[0] = max(widths[0], 12)

    def line(values):
        return "  ".join(
            str(v).ljust(widths[i]) if i == 0 or i >= 5 else str(v).rjust(widths[i])
            for i, v in enumerate(values)
        ).rstrip()

    out = []
    seeds = sorted({str(d.get("verify_seed_db") or "-") for d in docs})
    scales = sorted({str(d.get("verify_warehouses") or "-") for d in docs})
    out.append("TPC-C Robustness Report")
    out.append(f"seed: {', '.join(seeds)}   scale: {', '.join(s + ' wh' for s in scales)}"
               if len(scales) > 1 else f"seed: {seeds[0] if seeds else '-'}   scale: {scales[0] if scales else '-'} wh")
    out.append("")
    out.append(line(headers))
    out.append(line(["-" * w for w in widths]))
    for row in rows:
        out.append(line(row))
    out.append("")
    out.append("Per-run:  ✓ PASS   ✗ FAIL   ! SUSPECT   ? UNVERIFIED")
    max_runs = max([len(d.get("runs") or []) for d in docs] or [0])
    if max_runs:
        label_width = widths[0]
        out.append(" " * (label_width + 2) + "  ".join(str(i).rjust(4) for i in range(1, max_runs + 1)))
        for doc in docs:
            marks = []
            for i in range(max_runs):
                runs = doc.get("runs") or []
                state = runs[i].get("verify_status") if i < len(runs) else None
                marks.append((SYMBOL.get(str(state).upper(), "-") if state else "-").rjust(4))
            out.append(display(doc).ljust(label_width) + "  " + "  ".join(marks))
    out.append("")

    failures = [(doc, f) for doc in docs for f in (doc.get("failures") or [])]
    if failures:
        out.append("Failed runs:")
        for doc, failure in failures:
            checks = "; ".join(" ".join(str(c).split()) for c in (failure.get("failed_checks") or []))
            if len(checks) > 140:
                checks = checks[:137] + "..."
            out.append(f"  {display(doc)} run {failure.get('run', '?')}: "
                       f"{failure.get('status', '?')} — {checks or 'no detail'}")
        out.append("")

    out.append("Sweeps:")
    for doc in docs:
        pieces = [f"seed {doc.get('verify_seed_db') or '-'}",
                  f"scale {doc.get('verify_warehouses') or '-'}",
                  f"model {doc.get('model') or '-'}"]
        if doc.get("tree_name"):
            pieces.append(f"tree {doc['tree_name']}")
        if doc.get("prompt_sha256"):
            pieces.append(f"prompt {doc['prompt_sha256'][:12]}")
        pieces.append(f"at {doc.get('timestamp') or '-'}")
        out.append(f"  {display(doc)}: " + ", ".join(pieces))
    return "\n".join(out)


def markdown_report(docs):
    lines = ["# TPC-C Robustness Report", "",
             f"Generated {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} "
             "from `results/tpcc/robustness/*/latest.json`.", "",
             "Legend: **PASS** all four gates, **FAIL** any gate failed, "
             "**SUSPECT** warnings only, **UNVERIFIED** no verdict.", "",
             "## Summary", "",
             "| Arm | Runs | Pass | Fail | Other | Rate | Status | Failed runs |",
             "| :--- | ---: | ---: | ---: | ---: | ---: | :--- | :--- |"]
    for doc in docs:
        passed, failed, warn, unverified = counts(doc)
        total = int(doc.get("runs_completed") or 0)
        rate = f"{100 * passed / total:.0f}%" if total else "-"
        fails = ", ".join(str(r) for r in failed_runs(doc)) or "-"
        lines.append(f"| {display(doc)} | {total} | {passed} | {failed} | "
                     f"{warn + unverified} | {rate} | {doc.get('status') or 'UNVERIFIED'} | {fails} |")
    lines.append("")

    max_runs = max([len(d.get("runs") or []) for d in docs] or [0])
    if max_runs:
        lines.append("## Per-run")
        lines.append("")
        lines.append("| Arm | " + " | ".join(str(i) for i in range(1, max_runs + 1)) + " |")
        lines.append("| :--- | " + " | ".join(":---:" for _ in range(max_runs)) + " |")
        for doc in docs:
            runs = doc.get("runs") or []
            marks = []
            for i in range(max_runs):
                state = runs[i].get("verify_status") if i < len(runs) else None
                marks.append(SYMBOL.get(str(state).upper(), "-") if state else "-")
            lines.append(f"| {display(doc)} | " + " | ".join(marks) + " |")
        lines.append("")

    failures = [(doc, f) for doc in docs for f in (doc.get("failures") or [])]
    if failures:
        lines.append("## Failed runs")
        lines.append("")
        for doc, failure in failures:
            checks = "; ".join(" ".join(str(c).split()) for c in (failure.get("failed_checks") or []))
            lines.append(f"- **{display(doc)}** run {failure.get('run', '?')}: "
                         f"{failure.get('status', '?')} — {checks or 'no detail'}")
        lines.append("")

    lines.append("## Sweeps")
    lines.append("")
    for doc in docs:
        pieces = [f"seed `{doc.get('verify_seed_db') or '-'}`",
                  f"scale {doc.get('verify_warehouses') or '-'}",
                  f"model `{doc.get('model') or '-'}`"]
        if doc.get("tree_name"):
            pieces.append(f"tree `{doc['tree_name']}`")
        if doc.get("prompt_sha256"):
            pieces.append(f"prompt `{doc['prompt_sha256'][:12]}`")
        pieces.append(f"timestamp `{doc.get('timestamp') or '-'}`")
        lines.append(f"- **{display(doc)}**: " + ", ".join(pieces))
    lines.append("")
    return "\n".join(lines)


def main():
    docs = load()
    if not docs:
        print("No robustness summaries found under results/tpcc/robustness/.")
        return 1
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as handle:
        handle.write(markdown_report(docs))
    print(text_report(docs))
    print(f"\nreport: {os.path.relpath(OUT_FILE, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
