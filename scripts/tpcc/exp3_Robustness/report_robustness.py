#!/usr/bin/env python3
"""Robustness-only report: one table across every arm sweep.

Reads results/tpcc/robustness/<arm>/latest.json (written by run_arm_robustness.sh)
and writes reports/tpcc/robustness.md. Arms without a sweep are not listed.
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


def build(docs):
    lines = ["# TPC-C Robustness Report", "",
             f"Generated {datetime.now(timezone.utc).strftime('%Y-%m-%dT%H:%M:%SZ')} "
             "from `results/tpcc/robustness/*/latest.json`.", "",
             "| Arm | Runs | Scale | PASS | FAIL | SUSPECT | UNVERIFIED | Status |",
             "| :--- | :---: | :---: | :---: | :---: | :---: | :---: | :--- |"]
    for doc in docs:
        counts = doc.get("counts") or {}
        runs = int(doc.get("runs_completed") or 0)
        scale = f"{doc.get('verify_warehouses')} wh" if doc.get("verify_warehouses") else "-"
        lines.append(
            f"| {doc['arm']} | {runs} | {scale} | "
            f"{int(counts.get('pass') or 0)} | {int(counts.get('fail') or 0)} | "
            f"{int(counts.get('warn') or 0)} | {int(counts.get('unverified') or 0)} | "
            f"{doc.get('status') or 'UNVERIFIED'} |"
        )
    lines.append("")

    failures = [(doc["arm"], f) for doc in docs for f in (doc.get("failures") or [])]
    if failures:
        lines.append("## Failed runs")
        lines.append("")
        for arm, failure in failures:
            checks = "; ".join(" ".join(str(c).split()) for c in (failure.get("failed_checks") or []))
            lines.append(f"- **{arm}** run {failure.get('run', '?')}: "
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
        lines.append(f"- **{doc['arm']}**: " + ", ".join(pieces))
    lines.append("")
    return "\n".join(lines)


def main():
    docs = load()
    text = build(docs)
    os.makedirs(OUT_DIR, exist_ok=True)
    with open(OUT_FILE, "w", encoding="utf-8") as handle:
        handle.write(text)
    print(text)
    print(f"report: {os.path.relpath(OUT_FILE, ROOT)}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
