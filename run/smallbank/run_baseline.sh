#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-2}"
export DURATION="${DURATION:-180}"
export WARMUP="${WARMUP:-30}"
export WAREHOUSES="${WAREHOUSES:-32}"
export CLIENTS="${CLIENTS:-8}"
export ACCOUNTS="${ACCOUNTS:-5000000}"
export TRANSACTIONS="${TRANSACTIONS:-300000}"
export SETTLE_SECS="${SETTLE_SECS:-5}"
export DBMS="${DBMS:-postgres}"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# clean baseline results ONCE
rm -rf results/smallbank/baseline
mkdir -p results/smallbank/baseline/benchmarks

CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

# Copy canonical rep CSVs to single-file aliases for report.py compat.
# $1=subdir $2=tag $3=benchmark
legacy_sync() {
    local subdir="$1" tag="$2" benchmark="$3"
    local prefix="${subdir}/runExperiment1-${benchmark}-${DBMS}"
    local f last=""
    for f in "${subdir}/${tag}.csv"; do
        if [ ! -e "$f" ]; then
            continue
        fi
        cp "$f" "${prefix}-$(basename "$f" .csv).csv"
        last="$f"
    done
    if [ -n "${last}" ]; then
        cp "${last}" "${prefix}"
    fi
}

### Baseline: Smallbank (single db-arm measurement; its aliases feed both the
### db-layer and app-layer reports, so no second app-phase run is needed)
### **********
export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"
SMALLBANK_RESULTS="${ROOT}/results/smallbank/baseline/benchmarks"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"

# Snapshot taken once (load only when missing/stale, else reuse).
# restore_defaults => default knobs; asserts prove it + catch stale scale.
bench_assert_seed "${SEED_DB_SMALLBANK}"
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "${SEED_DB_SMALLBANK}" "accounts" "${ACCOUNTS}"

echo "----------------->> Baseline smallbank <<-----------------"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"
legacy_sync "${SMALLBANK_RESULTS}" "baseline" "smallbank"

