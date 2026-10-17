#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "stats/run_baseline" "results/stats/baseline" "baseline"
cd "${ROOT}"
bench_snapshot_seed stats stats_seed ./run/setup/stats-prepare-postgres-remote.sh

# clean baseline results
rm -rf results/stats/baseline
mkdir -p results/stats/baseline/benchmarks

export iteration=2
CMDBaseline=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Baseline.sh

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for Stats-Lite dataset >>-------------------'
bench_fresh_db stats stats_seed users "${STATS_USERS_ROWS:-40325}"
python3 "${ROOT}/tools/check_knobs.py"
$CMDBaseline stats PostgreSQL 1
