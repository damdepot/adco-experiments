#!/usr/bin/env bash
#
# Compare OLTP results across labels.
#
# Files are fixed-name (each baseline runs once into a wiped method dir):
# <label>.csv, or multi-rep <label>_r1.csv, _r2, ... Labels are
# auto-discovered from <label>.csv / <label>_rN.csv files in RESULTS_DIR
# (baseline first when present, otherwise alphabetical). runExperiment*
# logs/aliases and old <label>_<RUN_ID>.csv files are ignored. For every
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
    # New layout: <RESULTS_DIR>/<label>/*.csv; also accept flat <RESULTS_DIR>/*.csv.
    return sorted(
        set(glob.glob(os.path.join(results_dir, "*.csv")))
        | set(glob.glob(os.path.join(results_dir, "*", "*.csv")))
    )


def label_of(basename):
    # Fixed names only: <label>.csv or <label>_rN.csv. runExperiment* logs
    # and legacy <label>_<RUN_ID>.csv files never match.
    m = re.match(r"^([A-Za-z][A-Za-z0-9-]*?)(?:_r\d+)?\.csv$", basename)
    if not m or basename.startswith("runExperiment"):
        return None
    return m.group(1)


def rep_files(label):
    files = sorted(
        glob.glob(os.path.join(results_dir, label, f"{label}_r*.csv"))
        + glob.glob(os.path.join(results_dir, f"{label}_r*.csv"))
    )
    files = [f for f in files if re.search(r"_r\d+\.csv$", f)]
    if not files:
        for plain in (
            os.path.join(results_dir, label, f"{label}.csv"),
            os.path.join(results_dir, f"{label}.csv"),
        ):
            if os.path.isfile(plain):
                files = [plain]
                break
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
labels = sorted(candidates)
if "baseline" in labels:
    labels.remove("baseline")
    labels.insert(0, "baseline")

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

print(f"OLTP comparison — transaction rate (txn/s), % change vs {ref}")
print(f"Source: {results_dir}")
print()

header = f"{'TRANSACTION':<14}"
for label in present:
    header += f"{'|':^3}{label:>18}"
print(header)

for txn in order:
    line = f"{txn:<14}"
    for label in present:
        rates = data[label]
        if txn not in rates:
            line += f"{'|':^3}{'-':>18}"
        elif label == ref:
            line += f"{'|':^3}{rates[txn]:>18.2f}"
        else:
            b = base.get(txn, 0.0)
            pct = (rates[txn] - b) / b * 100 if b > 0 else 0.0
            line += f"{'|':^3}{f'{rates[txn]:.2f} ({pct:+.1f}%)':>18}"
    print(line)

print()
print(f"Note: higher is better; percentages are relative to {ref}.")
PY
