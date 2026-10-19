#!/usr/bin/env bash
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

MODEL="${MODEL:-gemini-3.5-flash-lite}"

# shellcheck disable=SC1090
source "${LIB}"

DCO_TPCC_BASE="${EXP_PATH}/results/tpcc/dco/benchmarks"
mkdir -p "${DCO_TPCC_BASE}"
mkdir -p "${EXP_PATH}/out/db_layer/DCo-results"

bench_lock "${EXP_PATH}"
bench_timer "tpcc/run_dco" "results/tpcc/dco" "dco"

CMDADCo="${EXP_PATH}/scripts/common/db_layer/exp0_ADCo/runExperiment0.sh"

# $1=subdir $2=tag $3=per-benchmark base dir $4=benchmark (aliases keep -<model> suffix)
legacy_sync() {
    local subdir="$1" tag="$2" base="$3" benchmark="$4"
    local prefix="${base}/runExperiment1-${benchmark}-${DBMS}-${MODEL}"
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

# ── TPC-C ─────────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-Db-ADCo.sh"
TPCC_RESULTS="${DCO_TPCC_BASE}"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"
export BENCH_REP_DB="tpcc" BENCH_REP_SEED="${SEED_DB_TPCC}"

run_dco_tpcc_tool() {
    if ! "$CMDADCo" DCo "${MODEL}" "${DBMS}" tpcc; then
        echo "ERROR: DCo tuning failed; skipping post-DCo TPCC measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"
bench_assert_seed "${SEED_DB_TPCC}"

echo "----------------->> DCo tpcc <<-----------------"
bench_restore "tpcc" "${SEED_DB_TPCC}"
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "tpcc" "warehouse" "${WAREHOUSES}"
run_dco_tpcc_tool
"${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
"${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
bench_measure "baseline" "dco.csv"
legacy_sync "${TPCC_RESULTS}" "dco" "${DCO_TPCC_BASE}" "tpcc"


