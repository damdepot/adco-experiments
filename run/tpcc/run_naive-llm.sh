#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpcc/run_naive-llm" "results/tpcc/naive-llm" "naive-llm"

# clean original results
rm -rf results/tpcc/naive-llm
mkdir -p results/tpcc/naive-llm/benchmarks

rm -rf out/app_layer/NaiveLLM-results
mkdir -p out/app_layer/NaiveLLM-results

export result_output_path="out/app_layer/NaiveLLM-results"

CMDNaive=./scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh
CMDRunTPCC=./scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh
CMDDocker=./scripts/_lib/docker.sh

# bench_ensure_seed loads the seed via BENCH_CMDRUNTPCC (bench_lib default points
# at a nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"

db_container="adcoexp-db"
db_service="pgdb"

model="${MODEL:-gemini-3.5-flash-lite}"

# Restart (NOT restore: Naive-LLM is rewrite-only, data identical), then cold
# buffers + settled data before measure; execute uses existing data.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

SEED_DB_TPCC="tpcc_seed"

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"
bench_assert_seed "${SEED_DB_TPCC}"

# Single restore for the run: fresh snapshot + default knobs before the rewrite.
bench_restore "tpcc" "${SEED_DB_TPCC}"
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "tpcc" "warehouse" "${WAREHOUSES}"


###  Rewrite + Workload: TPCC
### **********
echo '-------------------<< Generating rewrite app >>-------------------'
workload_path="workload/apps/tpcc"
source_file="drivers/postgresdriver.py"
if $CMDNaive workload/apps/tpcc postgres tpcc ${model}; then
    echo '-------------------<< Running the TPCC workload >>-------------------'
    measure_prep
    PHASE=execute $CMDRunTPCC postgres "${WAREHOUSES}" "${CLIENTS}" tpcc
else
    echo 'WARNING: Naive-LLM TPCC rewrite failed; skipping its measurement.' >&2
fi
