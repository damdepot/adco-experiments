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

# Fresh DB first: reuse must apply cached knobs on top of defaults
# (bench_fresh_db resets knobs), so it runs before the reuse check.
bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"

STATE_DIR="${ROOT}/results/tpch/gptuner/state"
mkdir -p "${STATE_DIR}"
if [ "${FORCE:-0}" = "1" ]; then
    rm -f "${STATE_DIR}/gptuner.done" "${STATE_DIR}/gptuner.auto.conf" "${STATE_DIR}/gptuner.knobs.txt"
fi

# clean original results (skipped on reuse so STATE_DIR survives)
if bench_knobs_reuse "${STATE_DIR}" "gptuner"; then
    echo "Reusing cached GPTuner knobs (FORCE=1 to retune)."
    mkdir -p results/tpch/gptuner/benchmarks
    SKIP_TUNE=1
else
    rm -rf results/tpch/gptuner
    mkdir -p results/tpch/gptuner/benchmarks
    mkdir -p "${STATE_DIR}"
    SKIP_TUNE=0
fi

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

if [ "${SKIP_TUNE}" = "1" ]; then
    TUNE_OK=1
elif gptuner_tune; then
    bench_knobs_save "${STATE_DIR}" "gptuner"
    TUNE_OK=1
else
    echo 'WARNING: GPTuner tuning failed; skipping its workload measurement.' >&2
    TUNE_OK=0
fi
if [ "${TUNE_OK}" = "1" ]; then
    echo '-------------------<< Running workload for TPCH dataset (GPTuner) >>-------------------'
    $CMDDocker Restart ${db_container}
    $CMDDocker WaitFor ${db_container}
    python3 "${ROOT}/tools/check_knobs.py"
    $CMDMeasure tpch PostgreSQL gptuner ${model}
fi
$CMDDocker Restart ${db_container}
$CMDDocker WaitFor ${db_container}
