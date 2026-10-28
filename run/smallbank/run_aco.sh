#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"


# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "smallbank/run_aco" "results/smallbank/aco" "aco"

# Clean results and output directories (aco only)
rm -rf results/smallbank/aco
mkdir -p results/smallbank/aco/benchmarks
rm -rf out/app_layer/ACo-results
mkdir -p out/app_layer/ACo-results

# Define variables and command paths
CMDADCo=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbank=./scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

model="${MODEL:-gemini-3.5-flash-lite}"

SEED_DB_SMALLBANK="smallbank_seed"
export BENCH_REP_DB="smallbank" BENCH_REP_SEED="${SEED_DB_SMALLBANK}"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"

### ACo
### **********
echo '-------------------<< ACo >>-------------------'
bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
# Fresh data + default knobs verified before rewrite execute (abort on failure).
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "smallbank" "accounts" "${SMALLBANK_ACCOUNTS}"
echo '-------------------<< Generating ACo rewrite for Smallbank >>-------------------'
if $CMDADCo ACo ${model} postgres smallbank; then
    echo '-------------------<< Running ACo Smallbank workload >>-------------------'
    bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
    "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    bench_settle
    PHASE=execute $CMDRunSmallbank ${model} postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_TRANSACTIONS}" smallbank aco
else
    echo 'WARNING: ACo Smallbank rewrite failed; skipping its measurement.' >&2
fi


