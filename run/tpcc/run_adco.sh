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

# clean adco results ONCE at top (do NOT wipe between app and db phases)
rm -rf results/tpcc/adco
mkdir -p results/tpcc/adco/benchmarks
rm -rf out/app_layer/ADCo-results
mkdir -p out/app_layer/ADCo-results
mkdir -p "${EXP_PATH}/out/db_layer/ADCo-results"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Define variables and command paths (app ADCo phase)
CMDADCo=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunTPCC=./scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

model="${MODEL}"
db_container="adcoexp-db"
db_service="pgdb"

# Cold buffers + settled data before every measure. No seed/snapshot/restore
# here: each workload self-loads (test/--reset), then measures.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

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

# ── TPC-C (db layer first: with REPS=1 its alias shares the app log name,
# and the later phase always wins) ─────────────────────────────────────────
CMDADCo="${EXP_PATH}/scripts/common/db_layer/exp0_ADCo/runExperiment0.sh"
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-Db-ADCo.sh"
ADCO_TPCC_BASE="${EXP_PATH}/results/tpcc/adco/benchmarks"
TPCC_RESULTS="${ADCO_TPCC_BASE}"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"

run_adco_tpcc_tool() {
    if ! "$CMDADCo" ADCo "${MODEL}" "${DBMS}" tpcc; then
        echo "ERROR: ADCo tuning failed; skipping post-ADCo TPCC measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> ADCo tpcc <<-----------------"
bench_arm_from_seed "adco" "baseline" "tpcc" "${SEED_DB_TPCC}" run_adco_tpcc_tool
legacy_sync "${TPCC_RESULTS}" "adco" "${ADCO_TPCC_BASE}" "tpcc"

### ADCo (app layer, last so its logs survive alongside the db files)
### **********
echo '-------------------<< ADCo >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for TPCC >>-------------------'
if $CMDADCo ADCo ${model} postgres tpcc; then
    echo '-------------------<< Running ADCo TPCC workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc adco
    PHASE=execute $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc adco
else
    echo 'WARNING: ADCo TPCC generation failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport tpcc postgres

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${EXP_PATH}/results/tpcc" "${EXP_PATH}/scripts/_lib/run_comparison.sh"
