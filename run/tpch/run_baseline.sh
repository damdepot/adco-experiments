#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never reset the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "tpch/run_baseline" "results/tpch/baseline" "baseline"
cd "${ROOT}"
bench_snapshot_seed tpch tpch_seed ./run/setup/tpch-prepare-postgres-remote.sh

# clean baseline results
rm -rf results/tpch/baseline
mkdir -p results/tpch/baseline/benchmarks

export iteration=2
CMDBaseline=./scripts/common/query_layer/exp2_Baselines/runExperiment2-Baseline.sh

## Run the baseline experiments
#***************
echo '-------------------<< Running the baseline experiments for TPCH dataset >>-------------------'
bench_fresh_db tpch tpch_seed lineitem "${TPCH_LINEITEM_ROWS:-6001215}"
python3 "${ROOT}/tools/check_knobs.py"
$CMDBaseline tpch PostgreSQL 1
