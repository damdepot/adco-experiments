#!/usr/bin/env python3
"""List every robustness sweep recorded for an arm, one row per sweep.

    log_robustness_runs.py [arm] [--workload tpcc|smallbank] [--full-scale]

Reads out/app_layer/<robustness|robustness-full-scale>/<arm>/<timestamp>/summary.json
and prints the key fields: benchmark, model, temperature, success rate and the
median TOTAL rate of the sweep's verify smokes. Older summaries predate
temperature logging and show 'n/r'.
"""

import argparse
import csv
import glob
import json
import os

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__)))))


def total_rate(path):
    try:
        with open(path, newline="", encoding="utf-8") as handle:
            for row in csv.reader(handle):
                if len(row) >= 4 and row[0].strip().upper() == "TOTAL":
                    return float(row[3])
    except (OSError, ValueError):
        pass
    return None


def sweep_rate(sweep_dir, passed_runs):
    values = []
    for path in glob.glob(os.path.join(sweep_dir, "r*", "verify.smoke.csv")):
        run = os.path.basename(os.path.dirname(path))[1:]
        if passed_runs is not None and int(run) not in passed_runs:
            continue
        value = total_rate(path)
        if value is not None:
            values.append(value)
    if not values:
        return None
    values.sort()
    middle = len(values) // 2
    if len(values) % 2:
        return values[middle]
    return (values[middle - 1] + values[middle]) / 2.0


def rows(base, workload):
    for path in sorted(glob.glob(os.path.join(base, "*", "summary.json"))):
        try:
            with open(path, encoding="utf-8") as handle:
                doc = json.load(handle)
        except (OSError, ValueError):
            continue
        # Sweeps for different workloads share out/app_layer/<mode>/<arm>/.
        # Legacy summaries without a workload field are TPC-C.
        if (doc.get("workload") or "tpcc") != workload:
            continue
        sweep_dir = os.path.dirname(path)
        counts = doc.get("counts") or {}
        total = sum(int(counts.get(k) or 0) for k in ("pass", "fail", "warn", "unverified"))
        total = total or int(doc.get("runs_completed") or 0)
        passed = int(counts.get("pass") or 0)
        rate = f"{passed}/{total} ({100.0 * passed / total:.0f}%)" if total else "0/0 (-)"
        temperature = doc.get("temperature")
        details = doc.get("runs") or []
        passed_runs = {int(r["run"]) for r in details
                       if r.get("verify_status") == "PASS"} if details else None
        tps = sweep_rate(sweep_dir, passed_runs)
        yield (
            doc.get("timestamp") or os.path.basename(sweep_dir),
            doc.get("workload") or "-",
            doc.get("model") or "-",
            "n/r" if temperature in (None, "") else str(temperature),
            rate,
            "-" if tps is None else f"{tps:.1f}",
            doc.get("status") or "-",
        )


def main():
    parser = argparse.ArgumentParser(description="List recorded robustness sweeps for an arm.")
    parser.add_argument("arm", nargs="?", default="naive-llm", help="arm name (default: naive-llm)")
    parser.add_argument("--workload", choices=("tpcc", "smallbank"), default="tpcc",
                        help="workload filter/label (default: tpcc)")
    parser.add_argument("--full-scale", action="store_true",
                        help="read out/app_layer/robustness-full-scale instead of robustness")
    args = parser.parse_args()

    mode = "robustness-full-scale" if args.full_scale else "robustness"
    base = os.path.join(ROOT, "out", "app_layer", mode, args.arm)
    data = list(rows(base, args.workload))
    if not data:
        print(f"No robustness summaries under {os.path.relpath(base, ROOT)}/.")
        return 1
    header = ("Timestamp", "Benchmark", "Model", "Temp", "Success rate", "TPS (median)", "Status")
    widths = [max(len(str(row[i])) for row in data + [header]) for i in range(len(header))]
    print(f"{args.arm} robustness runs ({args.workload})")
    print(f"Source: {os.path.relpath(base, ROOT)}/")
    print()
    print("  ".join(h.ljust(widths[i]) for i, h in enumerate(header)).rstrip())
    print("  ".join("-" * w for w in widths))
    for row in data:
        cells = [str(row[i]).ljust(widths[i]) if i < 3 else str(row[i]).rjust(widths[i])
                 for i in range(len(row))]
        print("  ".join(cells).rstrip())
    print()
    print("TPS: median TOTAL rate from PASS runs' verify smokes.")
    print("     Failed runs are excluded; this is not a benchmark number.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
