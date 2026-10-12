#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP_PATH="${ROOT}"
cd "${ROOT}"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-2}"
export DURATION="${DURATION:-180}"
export WARMUP="${WARMUP:-30}"
export WAREHOUSES="${WAREHOUSES:-32}"
export CLIENTS="${CLIENTS:-8}"
export SETTLE_SECS="${SETTLE_SECS:-5}"
export DBMS="${DBMS:-postgres}"

# shellcheck disable=SC1090
source "${LIB}"

# clean baseline results ONCE at top
rm -rf results/tpcc/baseline
mkdir -p results/tpcc/baseline/benchmarks

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

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

# ── TPC-C baseline (single db-arm measurement; its aliases feed both the
# db-layer and app-layer reports, so no second app-phase run is needed) ──
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"
TPCC_RESULTS="${EXP_PATH}/results/tpcc/baseline/benchmarks"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"
# Snapshot taken once (load only when missing/stale, else reuse).
# restore_defaults => default knobs; asserts prove it + catch stale scale.
bench_assert_seed "${SEED_DB_TPCC}"
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "${SEED_DB_TPCC}" "warehouse" "${WAREHOUSES}"

echo "----------------->> Baseline tpcc <<-----------------"
bench_arm_from_seed "baseline" "baseline" "tpcc" "${SEED_DB_TPCC}"
legacy_sync "${TPCC_RESULTS}" "baseline" "tpcc"


