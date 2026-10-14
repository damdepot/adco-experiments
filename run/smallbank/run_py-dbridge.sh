#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-2}"
export DURATION="${DURATION:-180}"
export WARMUP="${WARMUP:-30}"
export WAREHOUSES="${WAREHOUSES:-32}"
export CLIENTS="${CLIENTS:-8}"
export ACCOUNTS="${ACCOUNTS:-5000000}"
export TRANSACTIONS="${TRANSACTIONS:-60000}"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "smallbank/run_py-dbridge" "results/smallbank/py-dbridge" "py-dbridge"

# clean original results
rm -rf results/smallbank/py-dbridge
mkdir -p results/smallbank/py-dbridge/benchmarks

rm -rf out/app_layer/Py-DBridge-results
mkdir -p out/app_layer/Py-DBridge-results

export result_output_path="out/app_layer/Py-DBridge-results"

CMDPyDBridge=./scripts/common/app_layer/exp1_Baselines/runExperiment1-Py-DBridge.sh
CMDRunSmallbank=./scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Py-DBridge.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

SEED_DB_SMALLBANK="smallbank_seed"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"


###  Rewrite + Workload: Smallbank
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/smallbank"
source_file="drivers/postgresdriver.py"
if $CMDPyDBridge ${workload_path} ${source_file} postgres smallbank; then
    echo '-------------------<< Running the Smallbank workload >>-------------------'
    bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    # Fresh data + default knobs verified before rewrite execute (abort on failure).
    restore_defaults
    bench_assert_fresh_knobs
    bench_assert_rows "smallbank" "accounts" "${ACCOUNTS}"
    PHASE=execute $CMDRunSmallbank postgres "${ACCOUNTS:-5000000}" "${TRANSACTIONS:-60000}" smallbank
else
    echo 'WARNING: Py-DBridge Smallbank rewrite failed; skipping its measurement.' >&2
fi


