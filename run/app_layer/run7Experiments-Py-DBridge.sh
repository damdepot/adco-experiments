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

# clean original results
rm -rf results/app_layer/py-dbridge
mkdir -p results/app_layer/py-dbridge/benchmarks

rm -rf out/app_layer/Py-DBridge-results
mkdir -p out/app_layer/Py-DBridge-results

export result_dir="results/app_layer/py-dbridge"
export result_benchmark_path="results/app_layer/py-dbridge/benchmarks"
export result_output_path="out/app_layer/Py-DBridge-results"

CMDPyDBridge=./scripts/app_layer/exp1_Baselines/runExperiment1-Py-DBridge.sh
CMDRunSmallbank=./scripts/app_layer/exp1_Baselines/runExperiment1-Workload-Smallbank-Py-DBridge.sh
CMDRunTPCC=./scripts/app_layer/exp1_Baselines/runExperiment1-Workload-TPCC-Py-DBridge.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/app_layer/exp2_Reports/run_report.sh

db_container="adcoexp-db"
db_service="pgdb"

# Cold buffers + settled data before every measure. No seed/snapshot/restore
# here: each workload self-loads (test/--reset), then measures.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}


###  Rewrite + Workload: Smallbank
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/smallbank"
source_file="drivers/postgresdriver.py"
if $CMDPyDBridge ${workload_path} ${source_file} postgres smallbank; then
    echo '-------------------<< Running the Smallbank workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunSmallbank postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank
    PHASE=execute $CMDRunSmallbank postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}" smallbank
else
    echo 'WARNING: Py-DBridge Smallbank rewrite failed; skipping its measurement.' >&2
fi

###  Rewrite + Workload: TPCC
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/tpcc"
source_file="drivers/postgresdriver.py"
if $CMDPyDBridge ${workload_path} ${source_file} postgres tpcc; then
    echo '-------------------<< Running the TPCC workload >>-------------------'
    measure_prep
    PHASE=load $CMDRunTPCC postgres "${WAREHOUSES}" "${CLIENTS}" tpcc
    PHASE=execute $CMDRunTPCC postgres "${WAREHOUSES}" "${CLIENTS}" tpcc
else
    echo 'WARNING: Py-DBridge TPCC rewrite failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport all postgres
