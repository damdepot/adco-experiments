#!/usr/bin/env bash
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

DCO_TPCC_BASE="${EXP_PATH}/results/tpcc/dco/benchmarks"
mkdir -p "${DCO_TPCC_BASE}"
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

# ── TPC-C ─────────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-Db-ADCo.sh"
TPCC_RESULTS="${DCO_TPCC_BASE}"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"

run_dco_tpcc_tool() {
    if ! "$CMDADCo" DCo "${MODEL}" "${DBMS}" tpcc; then
        echo "ERROR: DCo tuning failed; skipping post-DCo TPCC measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_seed_once "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> Baseline tpcc <<-----------------"
bench_arm_from_seed "baseline" "baseline" "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> DCo tpcc <<-----------------"
bench_arm_from_seed "dco" "baseline" "tpcc" "${SEED_DB_TPCC}" run_dco_tpcc_tool
legacy_sync "${TPCC_RESULTS}" "dco" "${DCO_TPCC_BASE}" "tpcc"

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${EXP_PATH}/results/tpcc" "${EXP_PATH}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
