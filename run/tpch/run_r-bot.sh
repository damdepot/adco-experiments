#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_lock "${ROOT}"
bench_timer "tpch/run_r-bot" "results/tpch/r-bot" "r-bot"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

rm -rf results/tpch/r-bot
mkdir -p results/tpch/r-bot/benchmarks

rm -rf out/query_layer/R-Bot-results
mkdir -p out/query_layer/R-Bot-results

export iteration=2
export result_dir="results/tpch/r-bot"
export result_benchmark_path="results/tpch/r-bot/benchmarks"
export result_output_path="out/query_layer/R-Bot-results"

CMDBaselineRBot=./scripts/common/query_layer/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-R-Bot.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

### Rewrite TPCH with R-Bot
#**************************
echo "-------------------<< Running TPCH R-Bot rewrites >>-------------------"
$CMDBaselineRBot tpch PostgreSQL R-Bot ${model}

### Verify TPCH R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for TPCH dataset >>-------------------"
$CMDRunRBotVerify tpch PostgreSQL ${model}

### Run TPCH R-Bot workload
#**************************
echo "-------------------<< Running TPCH R-Bot workload >>-------------------"
bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
python3 "${ROOT}/tools/check_knobs.py"
$CMDRunWorkload tpch PostgreSQL ${model}
