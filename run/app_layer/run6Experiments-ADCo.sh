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
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Clean results and output directories
rm -rf results/app_layer/adco results/app_layer/aco
mkdir -p results/app_layer/adco/benchmarks results/app_layer/aco/benchmarks
rm -rf out/app_layer/ADCo-results out/app_layer/ACo-results
mkdir -p out/app_layer/ADCo-results out/app_layer/ACo-results

# Define variables and command paths
CMDADCo=./scripts/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbank=./scripts/app_layer/exp0_ADCo/runExperiment0-Workload-Smallbank-ADCo.sh
CMDRunTPCC=./scripts/app_layer/exp0_ADCo/runExperiment0-Workload-TPCC-ADCo.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/app_layer/exp2_Reports/run_report.sh

model="${MODEL:-gemini-3.5-flash-lite}"
db_container="adcoexp-db"
db_service="pgdb"

# Cold buffers + settled data before every measure. No seed/snapshot/restore
# here: each workload self-loads (test/--reset), then measures.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

### ACo
### **********
echo '-------------------<< ACo >>-------------------'
echo '-------------------<< Generating ACo rewrite for Smallbank >>-------------------'
if $CMDADCo ACo ${model} postgres smallbank; then
    echo '-------------------<< Running ACo Smallbank workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunSmallbank ${model} postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank aco
    PHASE=execute $CMDRunSmallbank ${model} postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank aco
else
    echo 'WARNING: ACo Smallbank rewrite failed; skipping its measurement.' >&2
fi

echo '-------------------<< Generating ACo rewrite for TPCC >>-------------------'
if $CMDADCo ACo ${model} postgres tpcc; then
    echo '-------------------<< Running ACo TPCC workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc aco
    PHASE=execute $CMDRunTPCC ${model} postgres "${WAREHOUSES}" "${CLIENTS}" tpcc aco
else
    echo 'WARNING: ACo TPCC rewrite failed; skipping its measurement.' >&2
fi


### ADCo
### **********
echo '-------------------<< ADCo >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for Smallbank >>-------------------'
if $CMDADCo ADCo ${model} postgres smallbank; then
    echo '-------------------<< Running ADCo Smallbank workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunSmallbank ${model} postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank adco
    PHASE=execute $CMDRunSmallbank ${model} postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank adco
else
    echo 'WARNING: ADCo Smallbank generation failed; skipping its measurement.' >&2
fi

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
$CMDReport all postgres
