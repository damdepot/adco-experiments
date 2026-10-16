#!/bin/bash

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"
bench_lock "${ROOT}"
bench_timer "stats/run_r-bot" "results/stats/r-bot" "r-bot"
bench_snapshot_seed stats stats_seed ./run/setup/stats-prepare-postgres-remote.sh

rm -rf results/stats/r-bot
mkdir -p results/stats/r-bot/benchmarks

rm -rf out/query_layer/R-Bot-results
mkdir -p out/query_layer/R-Bot-results

export iteration=2
export result_dir="results/stats/r-bot"
export result_benchmark_path="results/stats/r-bot/benchmarks"
export result_output_path="out/query_layer/R-Bot-results"

CMDBaselineRBot=./scripts/common/query_layer/exp2_Baselines/runExperiment2-R-Bot.sh
CMDRunRBotVerify=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload-Verify-R-Bot.sh
CMDRunWorkload=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Workload.sh

model="gemini-3.5-flash-lite"

### Rewrite Stats with R-Bot
#**************************
echo "-------------------<< Running Stats-Lite R-Bot rewrites >>-------------------"
$CMDBaselineRBot stats PostgreSQL R-Bot ${model}

### Verify Stats R-Bot rewrites
#**************************
echo "-------------------<< Verifying R-Bot rewrites for Stats-Lite dataset >>-------------------"
$CMDRunRBotVerify stats PostgreSQL ${model}

### Run Stats R-Bot workload
#**************************
echo "-------------------<< Running Stats-Lite R-Bot workload >>-------------------"
bench_fresh_db stats stats_seed users "${STATS_USERS_ROWS:-40325}"
python3 "${ROOT}/tools/check_knobs.py"
$CMDRunWorkload stats PostgreSQL ${model}
