#!/usr/bin/env bash
#
# Baseline measurement (no tuning tool) — canonical seed-once +
# bench_arm_from_seed pattern (cf. benchmarks/run0_smallbank.sh).
#
#   RUN_ID, bench_lock, SEED_DB, bench_seed_once, per-arm bench_arm_from_seed,
#   comparison call (scripts/_lib/run_comparison.sh per benchmark subdir).
#
# Contract (env-overridable, benchmarks scale):
#   CPU_CORES=2 MEMORY_GB=8 REPS=3 DURATION=60 WARMUP=10
#   WAREHOUSES=6 CLIENTS=6 ACCOUNTS=1000000 TRANSACTIONS=60000
#
# Canonical rep CSVs live in:
#   results/db_layer/baseline/benchmarks/<benchmark>/<tag>_<RUN_ID>[_rN].csv
# Legacy single-file aliases are refreshed at the top-level benchmarks/ dir
# (runExperiment1-<benchmark>-postgres) so scripts/db_layer/exp2_Reports keeps
# working (it globs top-level names only; subdirs are invisible to it).
#
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-8}"
export REPS="${REPS:-3}"
export DURATION="${DURATION:-60}"
export WARMUP="${WARMUP:-10}"
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"
export ACCOUNTS="${ACCOUNTS:-1000000}"
export TRANSACTIONS="${TRANSACTIONS:-60000}"
export SETTLE_SECS="${SETTLE_SECS:-5}"
export DBMS="${DBMS:-postgres}"

# shellcheck disable=SC1090
source "${LIB}"

RESULTS_BASE="${EXP_PATH}/results/db_layer/baseline/benchmarks"
mkdir -p "${RESULTS_BASE}"

export RUN_ID="$(date +%Y%m%d_%H%M%S)"

# Single-writer: never Down/Restart the DB under a concurrent run.
bench_lock "${EXP_PATH}"

# Copy canonical rep CSVs to legacy top-level aliases for report.py compat.
# $1=subdir $2=tag $3=benchmark
legacy_sync() {
    local subdir="$1" tag="$2" benchmark="$3"
    local prefix="${RESULTS_BASE}/runExperiment1-${benchmark}-${DBMS}"
    local f last=""
    for f in "${subdir}/${tag}_${RUN_ID}"*.csv; do
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

# ── SmallBank ─────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/db_layer/exp1_Baselines/runExperiment1-Workload-Smallbank.sh"
SMALLBANK_RESULTS="${RESULTS_BASE}/smallbank"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline smallbank <<-----------------"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"
legacy_sync "${SMALLBANK_RESULTS}" "baseline" "smallbank"

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${SMALLBANK_RESULTS}" "${EXP_PATH}/scripts/_lib/run_comparison.sh" "${RUN_ID}"

# ── TPC-C ─────────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/db_layer/exp1_Baselines/runExperiment1-Workload-TPCC.sh"
TPCC_RESULTS="${RESULTS_BASE}/tpcc"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_seed_once "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> Baseline tpcc <<-----------------"
bench_arm_from_seed "baseline" "baseline" "tpcc" "${SEED_DB_TPCC}"
legacy_sync "${TPCC_RESULTS}" "baseline" "tpcc"

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${TPCC_RESULTS}" "${EXP_PATH}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
