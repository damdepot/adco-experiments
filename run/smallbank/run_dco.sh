#!/usr/bin/env bash
#
# DCo experiments (SmallBank only) — canonical seed-once +
# bench_arm_from_seed pattern (cf. benchmarks/run0_smallbank.sh,
# run2_dco_smallbank.sh).
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
# run2_dco_smallbank.sh); DCo's rewritten sandbox is retained under
# out/db_layer/DCo-results for inspection.
#
# Canonical rep CSVs: results/<benchmark>/dco/benchmarks/
#   <tag>_<RUN_ID>[_rN].csv  (tags: baseline, dco)
# Single-file aliases (report.py compat) are refreshed alongside the rep CSVs:
#   results/<benchmark>/dco/benchmarks/runExperiment1-<bm>-postgres-<model>
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

DCO_SMALLBANK_BASE="${EXP_PATH}/results/smallbank/dco/benchmarks"
mkdir -p "${DCO_SMALLBANK_BASE}"
mkdir -p "${EXP_PATH}/out/db_layer/DCo-results"

export RUN_ID="$(date +%Y%m%d_%H%M%S)"

bench_lock "${EXP_PATH}"

CMDADCo="${EXP_PATH}/scripts/common/db_layer/exp0_ADCo/runExperiment0.sh"

# $1=subdir $2=tag $3=per-benchmark base dir $4=benchmark (aliases keep -<model> suffix)
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
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-Db-ADCo.sh"
SMALLBANK_RESULTS="${DCO_SMALLBANK_BASE}"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

run_dco_smallbank_tool() {
    if ! "$CMDADCo" DCo "${MODEL}" "${DBMS}" smallbank; then
        echo "ERROR: DCo tuning failed; skipping post-DCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline smallbank <<-----------------"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> DCo smallbank <<-----------------"
bench_arm_from_seed "dco" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_dco_smallbank_tool
legacy_sync "${SMALLBANK_RESULTS}" "dco" "${DCO_SMALLBANK_BASE}" "smallbank"

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${EXP_PATH}/results/smallbank" "${EXP_PATH}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
