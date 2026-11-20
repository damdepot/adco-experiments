#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP_PATH="${ROOT}"
cd "${ROOT}"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

MODEL="${MODEL:-gemini-3.5-flash-lite}"

# shellcheck disable=SC1090
source "${LIB}"

# results CSVs are overwritten by the workload script; state must survive
mkdir -p results/tpcc/adco
mkdir -p results/tpcc/adco/benchmarks
mkdir -p out/app_layer/ADCo-results

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpcc/run_adco" "results/tpcc/adco" "adco"

# Define variables and command paths (app ADCo phase)
CMDADCoApp=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunTPCC=./scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh
CMDDocker=./scripts/_lib/docker.sh

model="${MODEL}"
db_container="adcoexp-db"
db_service="pgdb"

# Restore from seed snapshot (data identical; scrubs tuner screening writes),
# then cold buffers + settled data before every measure; execute uses existing data.
measure_prep() {
    bench_restore "tpcc" "${SEED_DB_TPCC}"
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

# ── TPC-C (single unified ADCo run: rewrite+tune, app arm measured) ─────
SEED_DB_TPCC="tpcc_seed"
STATE_DIR="${EXP_PATH}/results/tpcc/adco/state"
mkdir -p "${STATE_DIR}"
REWRITE_DRIVER="out/app_layer/ADCo-results/Rewrite/postgres/tpcc-${model}/drivers/postgresdriver.py"
export BENCH_REP_DB="tpcc" BENCH_REP_SEED="${SEED_DB_TPCC}"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"
bench_assert_seed "${SEED_DB_TPCC}"

echo "----------------->> ADCo tpcc (unified single run) <<-----------------"
bench_restore "tpcc" "${SEED_DB_TPCC}"
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "tpcc" "warehouse" "${TPCC_WAREHOUSES}"

### ADCo (single unified run: ACo rewrite + DCo tune, rewritten-app arm measured)
### **********
echo '-------------------<< ADCo (unified single run) >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for TPCC >>-------------------'
if [ "${FORCE:-0}" = "1" ]; then
    rm -f "${STATE_DIR}/adco.done" "${STATE_DIR}/adco.auto.conf"
    rm -rf "out/app_layer/ADCo-results/Rewrite/postgres/tpcc-${model}"
fi
ADCO_OK=0
if bench_knobs_reuse "${STATE_DIR}" "adco" && [ -f "${REWRITE_DRIVER}" ]; then
    echo "Reusing cached ADCo knobs + rewrite (FORCE=1 to regenerate)."
    ADCO_OK=1
else
    rm -rf "out/app_layer/ADCo-results/Rewrite/postgres/tpcc-${model}"
    if $CMDADCoApp ADCo ${model} postgres tpcc; then
        bench_knobs_save "${STATE_DIR}" "adco"
        ADCO_OK=1
    else
        echo 'WARNING: ADCo TPCC generation failed; skipping its measurement.' >&2
    fi
fi
if [ "${ADCO_OK}" = "1" ]; then
    BENCH_LOCK_HELD=1 REVERIFY=1 VERIFY_KEEP_KNOBS=1 ./run/tpcc/run_verify.sh adco
    echo '-------------------<< Running ADCo TPCC workload >>-------------------'
    measure_prep
    PHASE=execute $CMDRunTPCC ${model} postgres "${TPCC_WAREHOUSES}" "${TPCC_CLIENTS}" tpcc adco
fi

