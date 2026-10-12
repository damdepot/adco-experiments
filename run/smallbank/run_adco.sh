#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-5}"
export DURATION="${DURATION:-180}"
export WARMUP="${WARMUP:-30}"
export WAREHOUSES="${WAREHOUSES:-32}"
export CLIENTS="${CLIENTS:-16}"
export ACCOUNTS="${ACCOUNTS:-5000000}"
export TRANSACTIONS="${TRANSACTIONS:-300000}"
export SETTLE_SECS="${SETTLE_SECS:-5}"
export DBMS="${DBMS:-postgres}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Clean adco results ONCE at top
rm -rf results/smallbank/adco
mkdir -p results/smallbank/adco/benchmarks
rm -rf out/app_layer/ADCo-results
mkdir -p out/app_layer/ADCo-results

# Define variables and command paths
CMDADCoApp=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbankApp=./scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh
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

SEED_DB_SMALLBANK="smallbank_seed"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"

### ADCo (unified rewrite+tune, single run; rewritten-app arm measured only)
### **********
echo "----------------->> Restore seed for single ADCo run <<-----------------"
bench_restore "smallbank" "${SEED_DB_SMALLBANK}"

echo '-------------------<< ADCo (unified single run: ACo rewrite + DCo tune) >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for Smallbank >>-------------------'
if $CMDADCoApp ADCo ${model} postgres smallbank; then
    echo '-------------------<< Running ADCo Smallbank workload >>-------------------'
    measure_prep
    PHASE=execute $CMDRunSmallbankApp ${model} postgres "${ACCOUNTS:-5000000}" "${TRANSACTIONS:-300000}" smallbank adco
else
    echo 'WARNING: ADCo Smallbank generation failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport smallbank postgres

echo "----------------->> Comparison smallbank <<-----------------"
RESULTS_DIR="${ROOT}/results/smallbank" "${ROOT}/scripts/_lib/run_comparison.sh"
