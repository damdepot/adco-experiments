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

# clean baseline results
rm -rf results/app_layer/baseline
mkdir -p results/app_layer/baseline/benchmarks

CMDRunSmallbank=./scripts/app_layer/exp1_Baselines/runExperiment1-Workload-Smallbank.sh
CMDRunTPCC=./scripts/app_layer/exp1_Baselines/runExperiment1-Workload-TPCC.sh
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

### Workload: Smallbank
### **********
echo '-------------------<< Running the Smallbank workload >>-------------------'
measure_prep
PHASE=load $CMDRunSmallbank postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}"
PHASE=execute $CMDRunSmallbank postgres "${ACCOUNTS:-1000000}" "${TRANSACTIONS:-60000}"

### Workload: TPCC
### **********
echo '-------------------<< Running the TPCC workload >>-------------------'
measure_prep
PHASE=load $CMDRunTPCC postgres "${WAREHOUSES}" "${CLIENTS}"
PHASE=execute $CMDRunTPCC postgres "${WAREHOUSES}" "${CLIENTS}"

echo '-------------------<< Comparison >>-------------------'
$CMDReport all postgres
