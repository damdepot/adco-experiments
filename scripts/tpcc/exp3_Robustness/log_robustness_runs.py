#!/usr/bin/env python3
"""List every robustness sweep recorded for an arm, one row per sweep.

Reads out/app_layer/robustness/<arm>/<timestamp>/summary.json and prints the
key fields: benchmark, model, temperature and success rate. Older summaries
predate temperature logging and show 'n/r'.
"""

import glob
import json
import os
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))
ARM = sys.argv[1] if len(sys.argv) > 1 else "naive-llm"
BASE = os.path.join(ROOT, "out", "app_layer", "robustness", ARM)


def rows():
    for path in sorted(glob.glob(os.path.join(BASE, "*", "summary.json"))):
        try:
            with open(path, encoding="utf-8") as handle:
                doc = json.load(handle)
        except (OSError, ValueError):
            continue
        counts = doc.get("counts") or {}
        total = sum(int(counts.get(k) or 0) for k in ("pass", "fail", "warn", "unverified"))
        total = total or int(doc.get("runs_completed") or 0)
        passed = int(counts.get("pass") or 0)
        rate = f"{passed}/{total} ({100.0 * passed / total:.0f}%)" if total else "0/0 (-)"
        temperature = doc.get("temperature")
        yield (
            doc.get("timestamp") or os.path.basename(os.path.dirname(path)),
            doc.get("workload") or "-",
            doc.get("model") or "-",
            "n/r" if temperature in (None, "") else str(temperature),
            rate,
            doc.get("status") or "-",
        )


def main():
    data = list(rows())
    if not data:
        print(f"No robustness summaries under {os.path.relpath(BASE, ROOT)}/.")
        return 1
    header = ("Timestamp", "Benchmark", "Model", "Temp", "Success rate", "Status")
    widths = [max(len(str(row[i])) for row in data + [header]) for i in range(len(header))]
    print(f"{ARM} robustness runs")
    print(f"Source: {os.path.relpath(BASE, ROOT)}/")
    print()
    print("  ".join(h.ljust(widths[i]) for i, h in enumerate(header)).rstrip())
    print("  ".join("-" * w for w in widths))
    for row in data:
        cells = [str(row[i]).ljust(widths[i]) if i < 3 else str(row[i]).rjust(widths[i])
                 for i in range(len(row))]
        print("  ".join(cells).rstrip())
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
