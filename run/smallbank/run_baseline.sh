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

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# clean baseline results ONCE
rm -rf results/smallbank/baseline
mkdir -p results/smallbank/baseline/benchmarks

CMDRunSmallbank=./scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-App.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

db_container="adcoexp-db"
db_service="pgdb"

# Cold buffers + settled data before every measure. No seed/snapshot/restore
# here: each workload self-loads (test/--reset), then measures.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

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

### Baseline: Smallbank (db layer first: its log byproducts share names with
### the app phase logs below, and the later phase always wins)
### **********
export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"
SMALLBANK_RESULTS="${ROOT}/results/smallbank/baseline/benchmarks"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline smallbank <<-----------------"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"
legacy_sync "${SMALLBANK_RESULTS}" "baseline" "smallbank"

### Workload: Smallbank (app layer, last so its logs survive alongside the db files)
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
measure_prep
PHASE=load $CMDRunSmallbank postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}"
PHASE=execute $CMDRunSmallbank postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}"

echo '-------------------<< Comparison >>-------------------'
$CMDReport smallbank postgres

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${SMALLBANK_RESULTS}" "${ROOT}/scripts/_lib/run_comparison.sh"
