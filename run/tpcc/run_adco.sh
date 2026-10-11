#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
EXP_PATH="${ROOT}"
cd "${ROOT}"
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

# clean adco results ONCE at top
rm -rf results/tpcc/adco
mkdir -p results/tpcc/adco/benchmarks
rm -rf out/app_layer/ADCo-results
mkdir -p out/app_layer/ADCo-results

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Define variables and command paths (app ADCo phase)
CMDADCoApp=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunTPCC=./scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

model="${MODEL}"
db_container="adcoexp-db"
db_service="pgdb"

# Restore from seed snapshot (data identical; scrubs tuner screening writes),
# then cold buffers + settled data before every measure; execute uses existing data.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

# ── TPC-C (single unified ADCo run: rewrite+tune, app arm measured) ─────
SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> ADCo tpcc (unified single run) <<-----------------"
bench_restore "tpcc" "${SEED_DB_TPCC}"

### ADCo (single unified run: ACo rewrite + DCo tune, rewritten-app arm measured)
### **********
echo '-------------------<< ADCo (unified single run) >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for TPCC >>-------------------'
if $CMDADCoApp ADCo ${model} postgres tpcc; then
    echo '-------------------<< Running ADCo TPCC workload >>-------------------'
    measure_prep
    PHASE=execute $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc adco
else
    echo 'WARNING: ADCo TPCC generation failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport tpcc postgres

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${EXP_PATH}/results/tpcc" "${EXP_PATH}/scripts/_lib/run_comparison.sh"
