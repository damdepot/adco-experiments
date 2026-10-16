#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"

# Fixed resource + workload contract (matches benchmarks harness).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-3}"
export DURATION="${DURATION:-60}"
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"

# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpch/run_naive-llm" "results/tpch/naive-llm" "naive-llm"
cd "${ROOT}"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

# clean original results
rm -rf results/tpch/naive-llm
mkdir -p results/tpch/naive-llm/benchmarks

rm -rf out/query_layer/NaiveLLM-results
mkdir -p out/query_layer/NaiveLLM-results

export iteration=2
export result_dir="results/tpch/naive-llm"
export result_benchmark_path="results/tpch/naive-llm/benchmarks"
export result_output_path="out/query_layer/NaiveLLM-results"

CMDNaive=./scripts/common/query_layer/exp2_Baselines/runExperiment2-NaiveLLM.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"


### Naive-LLM (single-shot rewrite)
### *******************************
naive_pipeline() {
    echo '-------------------<< Compiling TPCH dataset (Naive-LLM) >>-------------------'
    $CMDNaive Compile tpch PostgreSQL 1 ${model}
    echo '-------------------<< Generating Naive-LLM rewrite queries for TPCH dataset >>-------------------'
    $CMDNaive Rewrite tpch PostgreSQL 1 ${model}
    echo '-------------------<< Decompiling rewrite queries for TPCH dataset (Naive-LLM) >>-------------------'
    $CMDNaive Decompile tpch PostgreSQL 1 ${model}
    echo '-------------------<< Verifying rewrite queries for TPCH dataset (Naive-LLM) >>-------------------'
    $CMDNaive Verify tpch PostgreSQL 1 ${model}
}

if naive_pipeline; then
    echo '-------------------<< Running workload for TPCH dataset (Naive-LLM) >>-------------------'
    bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
    python3 "${ROOT}/tools/check_knobs.py"
    $CMDRunWorkload tpch PostgreSQL ${model} naive-llm
else
    echo 'WARNING: Naive-LLM rewrite pipeline failed; skipping its workload measurement.' >&2
fi
