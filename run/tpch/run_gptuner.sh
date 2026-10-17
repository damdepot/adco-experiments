#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"

export TARGET_MEMORY_GB="${TARGET_MEMORY_GB:-${MEMORY_GB}}"
export TARGET_CPU_CORES="${TARGET_CPU_CORES:-${CPU_CORES}}"

# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpch/run_gptuner" "results/tpch/gptuner" "gptuner"
cd "${ROOT}"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

# clean original results
rm -rf results/tpch/gptuner
mkdir -p results/tpch/gptuner/benchmarks

rm -rf out/query_layer/GPTuner-results
mkdir -p out/query_layer/GPTuner-results

export iteration=2
export result_dir="results/tpch/gptuner"
export result_benchmark_path="results/tpch/gptuner/benchmarks"
export result_output_path="out/query_layer/GPTuner-results"

CMGPTuner=./scripts/common/db_layer/exp1_Baselines/runExperiment1-GPTuner.sh
CMDMeasure=./scripts/common/query_layer/exp2_Baselines/runExperiment2-TunedBaseline.sh
CMDDocker=./scripts/common/db_layer/exp1_Baselines/runExperiment1-Production-Docker.sh

model="gemini-3.5-flash-lite"
db_container="adcoexp-db"


### GPTuner (knob-only tuning)
### *************************
gptuner_tune() {
    echo '-------------------<< Tuning TPCH knobs (GPTuner) >>-------------------'
    python3 "${ROOT}/tools/check_knobs.py"
    "$CMGPTuner" "${DBMS}" tpch "${TARGET_MEMORY_GB}" "${TARGET_CPU_CORES}"
}

bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
if gptuner_tune; then
    echo '-------------------<< Running workload for TPCH dataset (GPTuner) >>-------------------'
    $CMDDocker Restart ${db_container}
    $CMDDocker WaitFor ${db_container}
    python3 "${ROOT}/tools/check_knobs.py"
    $CMDMeasure tpch PostgreSQL gptuner ${model}
else
    echo 'WARNING: GPTuner tuning failed; skipping its workload measurement.' >&2
fi
$CMDDocker Restart ${db_container}
$CMDDocker WaitFor ${db_container}
