#!/usr/bin/env bash
#
# DCo + ADCo experiments — canonical seed-once + bench_arm_from_seed pattern
# (cf. benchmarks/run0_smallbank.sh, run2_dco_smallbank.sh).
#
#   RUN_ID, bench_lock, SEED_DB, bench_seed_once, per-arm bench_arm_from_seed
#   with tool fns, comparison call per benchmark.
#
# Contract (env-overridable, benchmarks scale):
#   CPU_CORES=2 MEMORY_GB=8 REPS=3 DURATION=60 WARMUP=10
#   WAREHOUSES=6 CLIENTS=6 ACCOUNTS=1000000 TRANSACTIONS=60000
#
# Post-tool bench_restore semantics come from bench_arm_from_seed (tool
# screening writes are scrubbed), followed by Restart/WaitFor cold buffers
# before measure. Knob settings live in postgresql.auto.conf and survive the
# restore, so the restore resets data only, not tuning.
#
# Optimized arms run the baseline app path (knob-only delta, as in
# run2_dco_smallbank.sh); ADCo's rewritten sandbox is retained under
# out/db_layer/ADCo-results (or DCo-results) for inspection.
#
# Canonical rep CSVs: results/db_layer/adco/benchmarks/<benchmark>/
#   <tag>_<RUN_ID>[_rN].csv  (tags: baseline, dco, adco)
# Legacy aliases (report.py compat) are refreshed at the top level:
#   results/db_layer/dco/benchmarks/runExperiment1-<bm>-postgres-<model>
#   results/db_layer/adco/benchmarks/runExperiment1-<bm>-postgres-<model>
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
MODEL="${MODEL:-gemini-3.5-flash-lite}"

# shellcheck disable=SC1090
source "${LIB}"

ADCO_BASE="${EXP_PATH}/results/db_layer/adco/benchmarks"
DCO_BASE="${EXP_PATH}/results/db_layer/dco/benchmarks"
mkdir -p "${ADCO_BASE}" "${DCO_BASE}"
mkdir -p "${EXP_PATH}/out/db_layer/ADCo-results" "${EXP_PATH}/out/db_layer/DCo-results"

export RUN_ID="$(date +%Y%m%d_%H%M%S)"

bench_lock "${EXP_PATH}"

CMDADCo="${EXP_PATH}/scripts/db_layer/exp0_ADCo/runExperiment0.sh"

# $1=subdir $2=tag $3=top-level base dir $4=benchmark (legacy keeps -<model> suffix)
legacy_sync() {
    local subdir="$1" tag="$2" base="$3" benchmark="$4"
    local prefix="${base}/runExperiment1-${benchmark}-${DBMS}-${MODEL}"
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
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/db_layer/exp0_ADCo/runExperiment0-Workload-Smallbank-ADCo.sh"
SMALLBANK_RESULTS="${ADCO_BASE}/smallbank"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

run_dco_smallbank_tool() {
    if ! "$CMDADCo" DCo "${MODEL}" "${DBMS}" smallbank; then
        echo "ERROR: DCo tuning failed; skipping post-DCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

run_adco_smallbank_tool() {
    if ! "$CMDADCo" ADCo "${MODEL}" "${DBMS}" smallbank; then
        echo "ERROR: ADCo tuning failed; skipping post-ADCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline smallbank <<-----------------"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> DCo smallbank <<-----------------"
bench_arm_from_seed "dco" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_dco_smallbank_tool
legacy_sync "${SMALLBANK_RESULTS}" "dco" "${DCO_BASE}" "smallbank"

echo "----------------->> ADCo smallbank <<-----------------"
bench_arm_from_seed "adco" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_adco_smallbank_tool
legacy_sync "${SMALLBANK_RESULTS}" "adco" "${ADCO_BASE}" "smallbank"

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${SMALLBANK_RESULTS}" "${EXP_PATH}/scripts/_lib/run_comparison.sh" "${RUN_ID}"

# ── TPC-C ─────────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/db_layer/exp0_ADCo/runExperiment0-Workload-TPCC-ADCo.sh"
TPCC_RESULTS="${ADCO_BASE}/tpcc"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"

run_dco_tpcc_tool() {
    if ! "$CMDADCo" DCo "${MODEL}" "${DBMS}" tpcc; then
        echo "ERROR: DCo tuning failed; skipping post-DCo TPCC measurement and CSV." >&2
        return 1
    fi
}

run_adco_tpcc_tool() {
    if ! "$CMDADCo" ADCo "${MODEL}" "${DBMS}" tpcc; then
        echo "ERROR: ADCo tuning failed; skipping post-ADCo TPCC measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_seed_once "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> Baseline tpcc <<-----------------"
bench_arm_from_seed "baseline" "baseline" "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> DCo tpcc <<-----------------"
bench_arm_from_seed "dco" "baseline" "tpcc" "${SEED_DB_TPCC}" run_dco_tpcc_tool
legacy_sync "${TPCC_RESULTS}" "dco" "${DCO_BASE}" "tpcc"

echo "----------------->> ADCo tpcc <<-----------------"
bench_arm_from_seed "adco" "baseline" "tpcc" "${SEED_DB_TPCC}" run_adco_tpcc_tool
legacy_sync "${TPCC_RESULTS}" "adco" "${ADCO_BASE}" "tpcc"

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${TPCC_RESULTS}" "${EXP_PATH}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
