#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

MODEL="${MODEL:-gemini-3.5-flash-lite}"

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${ROOT}"
bench_timer "smallbank/run_adco" "results/smallbank/adco" "adco"

# Clean adco results ONCE at top
rm -rf results/smallbank/adco
mkdir -p results/smallbank/adco/benchmarks
rm -rf out/app_layer/ADCo-results
mkdir -p out/app_layer/ADCo-results

# Define variables and command paths
CMDADCoApp=./scripts/common/app_layer/exp0_ADCo/runExperiment0.sh
CMDRunSmallbankApp=./scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh
CMDDocker=./scripts/_lib/docker.sh
CMDReport=./scripts/common/app_layer/exp2_Reports/run_report.sh

model="${MODEL}"
db_container="adcoexp-db"
db_service="pgdb"

# Restore-from-snapshot + cold buffers before every measure; workloads run
# PHASE=execute against pristine seed data.
measure_prep() {
    "${CMDDocker}" Restart "${db_container}" || "${CMDDocker}" Up "${db_container}" "${db_service}"
    "${CMDDocker}" WaitFor "${db_container}"
    bench_settle
}

SEED_DB_SMALLBANK="smallbank_seed"
export BENCH_REP_DB="smallbank" BENCH_REP_SEED="${SEED_DB_SMALLBANK}"

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"

### ADCo (unified rewrite+tune, single run; rewritten-app arm measured only)
### **********
echo "----------------->> Restore seed for single ADCo run <<-----------------"
bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
# Fresh data + default knobs verified before tool (abort on failure).
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "smallbank" "accounts" "${SMALLBANK_ACCOUNTS}"

echo '-------------------<< ADCo (unified single run: ACo rewrite + DCo tune) >>-------------------'
echo '-------------------<< Generating ADCo (ACo + DCo) for Smallbank >>-------------------'
if $CMDADCoApp ADCo ${model} postgres smallbank; then
    echo '-------------------<< Running ADCo Smallbank workload >>-------------------'
    measure_prep
    PHASE=execute $CMDRunSmallbankApp ${model} postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_TRANSACTIONS}" smallbank adco
else
    echo 'WARNING: ADCo Smallbank generation failed; skipping its measurement.' >&2
fi

