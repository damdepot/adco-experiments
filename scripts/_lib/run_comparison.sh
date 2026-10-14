#!/usr/bin/env bash
#
# Compare OLTP results across labels.
#
# Files are fixed-name (each baseline runs once into a wiped method dir):
# <label>/benchmarks/*.csv, or multi-rep <label>_r1.csv, _r2, ... (plus
# legacy flat/stamped). Labels are
# auto-discovered from <label>.csv / <label>_rN.csv files in RESULTS_DIR
# (canonical column order, unrecognised labels last), falling back to
# run-stamped <label>_<RUN_ID>[_rN].csv (latest run wins). runExperiment*
# logs/aliases stay ignored. For every
# label the txn/s of column 4 is averaged across reps, per transaction
# type, and printed alongside the percentage change relative to the first
# present label. Higher is better.
#
# Usage:
#   scripts/_lib/run_comparison.sh
#
# Results live in <repo>/results/<workload> (e.g. results/tpcc or
# results/smallbank) unless RESULTS_DIR is set. Labels with no parseable
# rows are skipped with a WARNING.
# NOTE: RESULTS_DIR honors a caller-provided env override.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${ROOT}/results/tpcc}"

python3 - "${RESULTS_DIR}" <<'PY'
import csv
import glob
import os
import re
import sys

results_dir = sys.argv[1]


def all_csvs():
    # Layout: <RESULTS_DIR>/<label>/benchmarks/*.csv; also accept flat
    # <RESULTS_DIR>/*.csv and legacy one-level <label>/*.csv (recursive).
    return sorted(
        set(glob.glob(os.path.join(results_dir, "**", "*.csv"), recursive=True))
    )


def label_of(basename):
    # Fixed names (<label>.csv or <label>_rN.csv) plus run-stamped
    # <label>_<RUN_ID>[_rN].csv fallback. runExperiment* logs never match.
    if basename.startswith("runExperiment"):
        return None
    m = re.match(r"^([A-Za-z][A-Za-z0-9-]*?)(?:_r\d+)?\.csv$", basename)
    if m:
        return m.group(1)
    m = re.match(r"^([A-Za-z][A-Za-z0-9-]*?)_(\d{8}_\d{6})(?:_r\d+)?\.csv$", basename)
    if m:
        return m.group(1)
    return None


def run_id_of(basename):
    m = re.match(r"^[A-Za-z][A-Za-z0-9-]*?_(\d{8}_\d{6})(?:_r\d+)?\.csv$", basename)
    return m.group(1) if m else ""


def rep_files(label):
    files = sorted(
        glob.glob(os.path.join(results_dir, "**", f"{label}_r*.csv"), recursive=True)
    )
    files = [f for f in files if re.search(r"_r\d+\.csv$", f)]
    if not files:
        plains = sorted(
            glob.glob(os.path.join(results_dir, "**", f"{label}.csv"), recursive=True)
        )
        if plains:
            files = plains[:1]
    if not files:
        # Fallback: run-stamped <label>_<RUN_ID>[_rN].csv; latest run wins.
        stamped = glob.glob(
            os.path.join(results_dir, "**", f"{label}_*.csv"), recursive=True
        )
        by_run = {}
        for f in stamped:
            m = re.match(
                r"^" + re.escape(label) + r"_(\d{8}_\d{6})(?:_r\d+)?\.csv$",
                os.path.basename(f),
            )
            if m:
                by_run.setdefault(m.group(1), []).append(f)
        if by_run:
            files = sorted(by_run[max(by_run)])
    return files


# Auto-discover labels from fixed-name CSVs.
candidates = set()
for path in all_csvs():
    label = label_of(os.path.basename(path))
    if label:
        candidates.add(label)
if not candidates:
    sys.stderr.write(f"ERROR: no result CSVs found in {results_dir}.\n")
    sys.exit(1)
# Canonical column order (matches run_reports.sh --systems); unrecognised
# labels follow, alphabetically.
CANONICAL = [
    "baseline", "py-dbridge", "naive-llm", "ottertune", "gptuner",
    "agenttune", "aco", "dco", "adco",
]
labels = sorted(
    candidates,
    key=lambda l: (CANONICAL.index(l) if l in CANONICAL else len(CANONICAL), l),
)

data = {}
order = []
for label in labels:
    files = rep_files(label)
    if not files:
        sys.stderr.write(
            f"WARNING: missing {label}[_rN].csv (skipping '{label}')\n"
        )
        data[label] = None
        continue
    sums = {}
    counts = {}
    for path in files:
        with open(path, newline="") as fh:
            reader = csv.reader(fh)
            next(reader, None)
            for row in reader:
                if len(row) < 4:
                    continue
                txn = row[0].strip()
                if not txn or txn.lower() == "transaction":
                    continue
                try:
                    rate = float(row[3])
                except ValueError:
                    continue
                sums[txn] = sums.get(txn, 0.0) + rate
                counts[txn] = counts.get(txn, 0) + 1
                if txn not in order:
                    order.append(txn)
    data[label] = {t: sums[t] / counts[t] for t in sums} if sums else None
    if data[label] is None:
        sys.stderr.write(
            f"WARNING: no parseable rows in {label} (skipping '{label}')\n"
        )

present = [label for label in labels if data[label] is not None]
if not present:
    sys.stderr.write(
        f"ERROR: no result CSVs found in {results_dir}\n"
    )
    sys.exit(1)

ref = present[0]
base = data[ref]

print(f"OLTP txn/s vs {ref} (higher better)")
print(f"Source: {results_dir}")
print()

header = f"{'TRANSACTION':<12}"
for label in present:
    header += f"|{label[:13]:^13}"
print(header)

for txn in order:
    line = f"{txn[:12]:<12}"
    for label in present:
        rates = data[label]
        if txn not in rates:
            line += f"|{'-':^13}"
        elif label == ref:
            line += f"|{rates[txn]:>13.1f}"
        else:
            b = base.get(txn, 0.0)
            pct = (rates[txn] - b) / b * 100 if b > 0 else 0.0
            line += f"|{f'{rates[txn]:.1f} ({pct:+.0f}%)':>13}"
    print(line)

# Geometric mean of per-transaction speedups vs ref (TOTAL excluded).
geo = {}
for label in present:
    if label == ref:
        continue
    vals = []
    for txn in order:
        if txn.upper() == 'TOTAL':
            continue
        b = base.get(txn, 0.0)
        r = data[label].get(txn)
        if b and r:
            vals.append(r / b)
    if vals:
        p = 1.0
        for v in vals:
            p *= v
        geo[label] = p ** (1.0 / len(vals))
    else:
        geo[label] = 0.0

gline = f"{'Geo Mean Spd':<12}"
for label in present:
    if label == ref:
        gline += f"|{'-':^13}"
    else:
        g = geo.get(label, 0.0)
        gline += f"|{f'{g:.2f}x' if g > 0 else 'N/A':>13}"
print(gline)

print()
print(f"Note: higher is better; percentages are relative to {ref}.")
PY
