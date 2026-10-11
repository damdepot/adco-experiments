#!/usr/bin/env bash
#
# Compare OLTP results across labels for one run.
#
# Files are multi-rep: <label>_<RUN_ID>_r1.csv, _r2, ... (a single-rep run
# produces <label>_<RUN_ID>.csv). Labels are auto-discovered from files in
# RESULTS_DIR matching <label>_<RUN_ID>.csv / <label>_<RUN_ID>_rN.csv for the
# given RUN_ID (baseline first when present, otherwise alphabetical). For
# every label the txn/s of column 4 is averaged across that run's reps, per
# transaction type, and printed alongside the percentage change relative to
# the first present label. Higher is better.
#
# Usage:
#   scripts/_lib/run_comparison.sh [RUN_ID]
#
# RUN_ID defaults to the newest run that has baseline files. Results live in
# <repo>/results/tpcc unless RESULTS_DIR is set. Labels with no parseable
# rows are skipped with a WARNING.
# NOTE: RESULTS_DIR honors a caller-provided env override.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RESULTS_DIR="${RESULTS_DIR:-${ROOT}/results/tpcc}"
RUN_ID="${1:-}"

python3 - "${RESULTS_DIR}" "${RUN_ID}" <<'PY'
import csv
import glob
import os
import re
import sys

results_dir = sys.argv[1]
run_id = sys.argv[2] if len(sys.argv) > 2 else ""


def rep_files(label, run):
    files = sorted(glob.glob(os.path.join(results_dir, f"{label}_{run}_r*.csv")))
    files = [f for f in files if re.search(r"_r\d+\.csv$", f)]
    if not files:
        plain = os.path.join(results_dir, f"{label}_{run}.csv")
        if os.path.isfile(plain):
            files = [plain]
    return files


if not run_id:
    ids = set()
    for path in glob.glob(os.path.join(results_dir, "baseline_*.csv")):
        m = re.search(r"baseline_(\d{8}_\d{6})(?:_r\d+)?\.csv$", os.path.basename(path))
        if m:
            ids.add(m.group(1))
    if not ids:
        sys.stderr.write(
            f"ERROR: no baseline result files found in {results_dir}; pass a RUN_ID.\n"
        )
        sys.exit(1)
    run_id = sorted(ids)[-1]

# Auto-discover labels: filename prefix before _<RUN_ID> for this RUN_ID.
candidates = set()
for path in glob.glob(os.path.join(results_dir, "*.csv")):
    m = re.match(r"^(.*)_(\d{8}_\d{6})(?:_r\d+)?\.csv$", os.path.basename(path))
    if m and m.group(2) == run_id and m.group(1):
        candidates.add(m.group(1))
labels = sorted(candidates)
if "baseline" in labels:
    labels.remove("baseline")
    labels.insert(0, "baseline")

data = {}
order = []
for label in labels:
    files = rep_files(label, run_id)
    if not files:
        sys.stderr.write(
            f"WARNING: missing {label}_{run_id}[_rN].csv (skipping '{label}')\n"
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
            f"WARNING: no parseable rows in {label}_{run_id} (skipping '{label}')\n"
        )

present = [label for label in labels if data[label] is not None]
if not present:
    sys.stderr.write(
        f"ERROR: no result CSVs found in {results_dir} for RUN_ID {run_id}\n"
    )
    sys.exit(1)

ref = present[0]
base = data[ref]

print(f"OLTP comparison — transaction rate (txn/s), % change vs {ref}")
print(f"Source: {results_dir} (RUN_ID {run_id})")
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
