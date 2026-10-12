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
export TRANSACTIONS="${TRANSACTIONS:-300000}"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Clean results and output directories (aco only)
rm -rf results/smallbank/aco
mkdir -p results/smallbank/aco/benchmarks
rm -rf out/app_layer/ACo-results
mkdir -p out/app_layer/ACo-results

# Define variables and command paths
CMDADCo=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbank=./scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

model="${MODEL:-gemini-3.5-flash-lite}"

SEED_DB_SMALLBANK="smallbank_seed"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"

### ACo
### **********
echo '-------------------<< ACo >>-------------------'
echo '-------------------<< Generating ACo rewrite for Smallbank >>-------------------'
if $CMDADCo ACo ${model} postgres smallbank; then
    echo '-------------------<< Running ACo Smallbank workload >>-------------------'
    bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    PHASE=execute $CMDRunSmallbank ${model} postgres "${ACCOUNTS:-5000000}" "${TRANSACTIONS:-300000}" smallbank aco
else
    echo 'WARNING: ACo Smallbank rewrite failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport smallbank postgres
