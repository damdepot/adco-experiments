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

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Clean results and output directories (aco ONLY)
rm -rf results/tpcc/aco
mkdir -p results/tpcc/aco/benchmarks
rm -rf out/app_layer/ACo-results
mkdir -p out/app_layer/ACo-results

# Define variables and command paths
CMDADCo=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunTPCC=./scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

model="${MODEL:-gemini-3.5-flash-lite}"

SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"

### ACo
### **********
echo '-------------------<< ACo >>-------------------'
echo '-------------------<< Generating ACo rewrite for TPCC >>-------------------'
if $CMDADCo ACo ${model} postgres tpcc; then
    echo '-------------------<< Running ACo TPCC workload >>-------------------'
    bench_restore "tpcc" "${SEED_DB_TPCC}"
    PHASE=execute $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc aco
else
    echo 'WARNING: ACo TPCC rewrite failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport tpcc postgres
