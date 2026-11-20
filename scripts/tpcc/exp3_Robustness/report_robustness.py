#!/usr/bin/env python3
"""Robustness-only report: one table across every arm sweep.

Reads results/<workload>/robustness/<arm>/latest.json (written by each
workload's run_arm_robustness.sh) and writes reports/<workload>/robustness.md.
Arms without a sweep are not listed. The terminal gets an aligned plain-text
table; the file gets markdown.

    report_robustness.py [--workload tpcc|smallbank]

Lives under scripts/tpcc/ because the TPC-C harness created it; it is shared
with SmallBank via the workload table below.
"""

import argparse
import glob
import json
import os
import sys
from datetime import datetime, timezone

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))

WORKLOADS = {
    "tpcc": {
        "title": "TPC-C",
        "order": ["naive-llm", "naive-llm-agenttune", "agenttune-naive-llm", "aco", "adco", "py-dbridge"],
        "display": {"naive-llm": "Naive-LLM", "naive-llm-agenttune": "Naive-LLM + AgentTune",
                    "agenttune-naive-llm": "AgentTune + Naive-LLM", "aco": "ACo", "adco": "ADCo",
                    "py-dbridge": "Py-DBridge"},
        "scale_key": "verify_warehouses",
        "scale_label": "wh",
    },
    "smallbank": {
        "title": "SmallBank",
        "order": ["naive-llm", "aco", "adco", "py-dbridge"],
        "display": {"naive-llm": "Naive-LLM", "aco": "ACo", "adco": "ADCo",
                    "py-dbridge": "Py-DBridge"},
        "scale_key": "verify_accounts",
        "scale_label": "accounts",
    },
}
SYMBOL = {"PASS": "✓", "FAIL": "✗", "WARN": "!", "UNVERIFIED": "?"}


def load(workload):
    results = os.path.join(ROOT, "results", workload, "robustness")
    spec = WORKLOADS[workload]
    docs = []
    for path in sorted(glob.glob(os.path.join(results, "*", "latest.json"))):
        try:
            with open(path, encoding="utf-8") as handle:
                doc = json.load(handle)
        except (OSError, ValueError):
            continue
        if isinstance(doc, dict) and doc.get("arm"):
            docs.append(doc)
    docs.sort(key=lambda d: (spec["order"].index(d["arm"]) if d["arm"] in spec["order"]
                             else len(spec["order"]), d["arm"]))
    return docs


def display(doc, spec):
    return spec["display"].get(doc["arm"], doc["arm"])


def counts(doc):
    c = doc.get("counts") or {}
    return (int(c.get("pass") or 0), int(c.get("fail") or 0),
            int(c.get("warn") or 0), int(c.get("unverified") or 0))


def failed_runs(doc):
    return [f.get("run") for f in (doc.get("failures") or [])]


def scale_text(doc, spec):
    value = doc.get(spec["scale_key"])
    return str(value) if value not in (None, "") else "-"


def text_report(docs, workload):
    spec = WORKLOADS[workload]
    rows = []
    for doc in docs:
        passed, failed, warn, unverified = counts(doc)
        total = int(doc.get("runs_completed") or 0)
        rate = f"{100 * passed / total:.0f}%" if total else "-"
        fails = ", ".join(str(r) for r in failed_runs(doc)) or "-"
        rows.append((display(doc, spec), total, passed, failed, warn + unverified, rate,
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
    scales = sorted({scale_text(d, spec) for d in docs})
    out.append(f"{spec['title']} Robustness Report")
    out.append(f"seed: {', '.join(seeds)}   scale: {', '.join(s + ' ' + spec['scale_label'] for s in scales)}"
               if len(scales) > 1 else f"seed: {seeds[0] if seeds else '-'}   scale: {scales[0] if scales else '-'} {spec['scale_label']}")
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
            out.append(display(doc, spec).ljust(label_width) + "  " + "  ".join(marks))
    out.append("")

    failures = [(doc, f) for doc in docs for f in (doc.get("failures") or [])]
    if failures:
        out.append("Failed runs:")
        for doc, failure in failures:
            checks = "; ".join(" ".join(str(c).split()) for c in (failure.get("failed_checks") or []))
            if len(checks) > 140:
                checks = checks[:137] + "..."
            out.append(f"  {display(doc, spec)} run {failure.get('run', '?')}: "
                       f"{failure.get('status', '?')} — {checks or 'no detail'}")
        out.append("")

    out.append("Sweeps:")
    for doc in docs:
        pieces = [f"seed {doc.get('verify_seed_db') or '-'}",
                  f"scale {scale_text(doc, spec)}",
                  f"model {doc.get('model') or '-'}"]
        if doc.get("tree_name"):
            pieces.append(f"tree {doc['tree_name']}")
        pieces.append(f"at {doc.get('timestamp') or '-'}")
        out.append(f"  {display(doc, spec)}: " + ", ".join(pieces))
    return "\n".join(out)


def markdown_report(docs, workload):
    spec = WORKLOADS[workload]
    lines = [f"# {spec['title']} Robustness Report", "",
             f"Generated {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} "
             f"from `results/{workload}/robustness/*/latest.json`.", "",
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
        lines.append(f"| {display(doc, spec)} | {total} | {passed} | {failed} | "
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
            lines.append(f"| {display(doc, spec)} | " + " | ".join(marks) + " |")
        lines.append("")

    failures = [(doc, f) for doc in docs for f in (doc.get("failures") or [])]
    if failures:
        lines.append("## Failed runs")
        lines.append("")
        for doc, failure in failures:
            checks = "; ".join(" ".join(str(c).split()) for c in (failure.get("failed_checks") or []))
            lines.append(f"- **{display(doc, spec)}** run {failure.get('run', '?')}: "
                         f"{failure.get('status', '?')} — {checks or 'no detail'}")
        lines.append("")

    lines.append("## Sweeps")
    lines.append("")
    for doc in docs:
        pieces = [f"seed `{doc.get('verify_seed_db') or '-'}`",
                  f"scale {scale_text(doc, spec)}",
                  f"model `{doc.get('model') or '-'}`"]
        if doc.get("tree_name"):
            pieces.append(f"tree `{doc['tree_name']}`")
        pieces.append(f"timestamp `{doc.get('timestamp') or '-'}`")
        lines.append(f"- **{display(doc, spec)}**: " + ", ".join(pieces))
    lines.append("")
    return "\n".join(lines)


def main():
    parser = argparse.ArgumentParser(description="Robustness-only report across arm sweeps.")
    parser.add_argument("--workload", choices=sorted(WORKLOADS), default="tpcc",
                        help="workload to report (default: tpcc)")
    args = parser.parse_args()

    docs = load(args.workload)
    if not docs:
        print(f"No robustness summaries found under results/{args.workload}/robustness/.")
        return 1
    out_dir = os.path.join(ROOT, "reports", args.workload)
    out_file = os.path.join(out_dir, "robustness.md")
    os.makedirs(out_dir, exist_ok=True)
    with open(out_file, "w", encoding="utf-8") as handle:
        handle.write(markdown_report(docs, args.workload))
    print(text_report(docs, args.workload))
    print(f"\nreport: {os.path.relpath(out_file, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
