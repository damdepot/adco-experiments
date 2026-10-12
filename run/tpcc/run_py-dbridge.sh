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

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# clean original results
rm -rf results/tpcc/py-dbridge
mkdir -p results/tpcc/py-dbridge/benchmarks

rm -rf out/app_layer/Py-DBridge-results
mkdir -p out/app_layer/Py-DBridge-results

export result_output_path="out/app_layer/Py-DBridge-results"

CMDPyDBridge=./scripts/common/app_layer/exp1_Baselines/runExperiment1-Py-DBridge.sh
CMDRunTPCC=./scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Py-DBridge.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

db_container="adcoexp-db"
db_service="pgdb"

# Restart (NOT restore: Py-DBridge is rewrite-only, data identical), then cold
# buffers + settled data before measure; execute uses existing data.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"

# Single restore for the run: fresh snapshot before the rewrite.
bench_restore "tpcc" "${SEED_DB_TPCC}"


###  Rewrite + Workload: TPCC
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/tpcc"
source_file="drivers/postgresdriver.py"
if $CMDPyDBridge ${workload_path} ${source_file} postgres tpcc; then
    echo '-------------------<< Running the TPCC workload >>-------------------'
    measure_prep
    PHASE=execute $CMDRunTPCC postgres "${WAREHOUSES}" "${CLIENTS}" tpcc
else
    echo 'WARNING: Py-DBridge TPCC rewrite failed; skipping its measurement.' >&2
fi

echo '-------------------<< Comparison >>-------------------'
$CMDReport tpcc postgres
