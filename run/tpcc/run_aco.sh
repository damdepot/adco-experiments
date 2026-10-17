#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpcc/run_aco" "results/tpcc/aco" "aco"

# Clean results and output directories (aco ONLY)
rm -rf results/tpcc/aco
mkdir -p results/tpcc/aco/benchmarks
rm -rf out/app_layer/ACo-results
mkdir -p out/app_layer/ACo-results

# Define variables and command paths
CMDADCo=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunTPCC=./scripts/tpcc/exp0_ADCo/runExperiment0-Workload-TPCC-App-ADCo.sh

model="${MODEL:-gemini-3.5-flash-lite}"

SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"
bench_assert_seed "${SEED_DB_TPCC}"

### ACo
### **********
echo '-------------------<< ACo >>-------------------'
bench_restore "tpcc" "${SEED_DB_TPCC}"
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "tpcc" "warehouse" "${WAREHOUSES}"
echo '-------------------<< Generating ACo rewrite for TPCC >>-------------------'
if $CMDADCo ACo ${model} postgres tpcc; then
    echo '-------------------<< Running ACo TPCC workload >>-------------------'
    PHASE=execute $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc aco
else
    echo 'WARNING: ACo TPCC rewrite failed; skipping its measurement.' >&2
fi
