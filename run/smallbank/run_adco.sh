#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
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

export RUN_ID="$(date +%Y%m%d_%H%M%S)"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Clean adco results ONCE at top (do NOT wipe between app and db phases)
rm -rf results/smallbank/adco
mkdir -p results/smallbank/adco/benchmarks
rm -rf out/app_layer/ADCo-results
mkdir -p out/app_layer/ADCo-results
mkdir -p "${ROOT}/out/db_layer/ADCo-results"

# Define variables and command paths
CMDADCoApp=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbankApp=./scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh
CMDADCoDb="${ROOT}/scripts/common/db_layer/exp0_ADCo/runExperiment0.sh"

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

### ADCo (db layer first: with REPS=1 its alias shares the app log name,
### and the later phase always wins)
### **********
export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-Db-ADCo.sh"
ADCO_SMALLBANK_BASE="${ROOT}/results/smallbank/adco/benchmarks"
SMALLBANK_RESULTS="${ADCO_SMALLBANK_BASE}"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

run_adco_smallbank_tool() {
    if ! "$CMDADCoDb" ADCo "${MODEL}" "${DBMS}" smallbank; then
        echo "ERROR: ADCo tuning failed; skipping post-ADCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline smallbank <<-----------------"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> ADCo smallbank <<-----------------"
bench_arm_from_seed "adco" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_adco_smallbank_tool
legacy_sync "${SMALLBANK_RESULTS}" "adco" "${ADCO_SMALLBANK_BASE}" "smallbank"

### ADCo (app layer, last so its logs survive alongside the db files)
### **********
echo '-------------------<< ADCo >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for Smallbank >>-------------------'
if $CMDADCoApp ADCo ${model} postgres smallbank; then
    echo '-------------------<< Running ADCo Smallbank workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunSmallbankApp ${model} postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank adco
    PHASE=execute $CMDRunSmallbankApp ${model} postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank adco
else
    echo 'WARNING: ADCo Smallbank generation failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport smallbank postgres

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${ROOT}/results/smallbank" "${ROOT}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
