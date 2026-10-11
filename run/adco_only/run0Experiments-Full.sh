#!/usr/bin/env bash
# Full adco_only matrix: baseline + ACo + DCo + ADCo under one RUN_ID so a
# single comparison table covers all four arms (mirrors benchmarks/run0_*).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Resource + workload contract (same defaults as the shared bench lib).
export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-8}"
export REPS="${REPS:-3}"
export DURATION="${DURATION:-60}"
export WARMUP="${WARMUP:-10}"
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"
export SETTLE_SECS="${SETTLE_SECS:-5}"

# Workload-runner override must be exported before sourcing the shared lib.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/adco_only/runExperiment1-Workload-Smallbank.sh"
export BENCH_CMDDOCKER="${BENCH_CMDDOCKER:-${ROOT}/scripts/_lib/docker.sh}"

source "${ROOT}/scripts/_lib/bench_lib.sh"

CMDRunACo="${ROOT}/scripts/adco_only/runExperiment0-ACo.sh"
CMDRunDCo="${ROOT}/scripts/adco_only/runExperiment0-DCo.sh"
CMDRunADCo="${ROOT}/scripts/adco_only/runExperiment0-ADCo.sh"

model="${MODEL:-gemini-3.5-flash-lite}"
dbms="postgres"

RESULTS_SB="${ROOT}/results/adco_only/smallbank"
RESULTS_TPCC="${ROOT}/results/adco_only/tpcc"
mkdir -p "${RESULTS_SB}" "${RESULTS_TPCC}"
RUN_ID="$(date +%Y%m%d_%H%M%S)"
export RUN_ID

# Single-writer: never Down/Restart the DB under a concurrent run.
bench_lock "${ROOT}"

# Pristine dataset snapshots: loaded once per workload, restored per arm in
# seconds. Knob settings live in postgresql.auto.conf and survive the
# restore, so the restore resets data only, not tuning.
SEED_DB_SMALLBANK="smallbank_seed"
SEED_DB_TPCC="tpcc_seed"

# Rewrite locations (relative to ${ROOT}/out); the workload runner switches
# into them for non-baseline dirs.
ACo_SB_DIR="adco_only/ACo-results/Rewrite/postgres/smallbank-${model}"
ACo_TPCC_DIR="adco_only/ACo-results/Rewrite/postgres/tpcc-${model}"
ADCo_SB_DIR="adco_only/ADCo-results/Rewrite/postgres/smallbank-${model}"
ADCo_TPCC_DIR="adco_only/ADCo-results/Rewrite/postgres/tpcc-${model}"

run_aco_smallbank_tool() {
    "${CMDRunACo}" "${ROOT}/workload/apps/smallbank" "${model}" "${dbms}" "smallbank"
}

run_aco_tpcc_tool() {
    "${CMDRunACo}" "${ROOT}/workload/apps/tpcc" "${model}" "${dbms}" "tpcc"
}

run_dco_smallbank_tool() {
    if ! "${CMDRunDCo}" "${ROOT}/workload/apps/smallbank" "${model}" "${dbms}" "smallbank" "${CPU_CORES}" "${MEMORY_GB}"; then
        echo "ERROR: DCo tuning failed; skipping post-DCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

run_dco_tpcc_tool() {
    if ! "${CMDRunDCo}" "${ROOT}/workload/apps/tpcc" "${model}" "${dbms}" "tpcc" "${CPU_CORES}" "${MEMORY_GB}"; then
        echo "ERROR: DCo tuning failed; skipping post-DCo TPCC measurement and CSV." >&2
        return 1
    fi
}

run_adco_smallbank_tool() {
    if ! "${CMDRunADCo}" "${ROOT}/workload/apps/smallbank" "${model}" "${dbms}" "smallbank" "${CPU_CORES}" "${MEMORY_GB}"; then
        echo "ERROR: ADCo tuning failed; skipping post-ADCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

run_adco_tpcc_tool() {
    if ! "${CMDRunADCo}" "${ROOT}/workload/apps/tpcc" "${model}" "${dbms}" "tpcc" "${CPU_CORES}" "${MEMORY_GB}"; then
        echo "ERROR: ADCo tuning failed; skipping post-ADCo TPCC measurement and CSV." >&2
        return 1
    fi
}

# ── SmallBank: baseline + ACo + DCo + ADCo from one snapshot ──
echo "----------------->> Seed SmallBank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline SmallBank <<-----------------"
export RESULTS_DIR="${RESULTS_SB}"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> ACo SmallBank <<-----------------"
export RESULTS_DIR="${RESULTS_SB}"
bench_arm_from_seed "aco" "${ACo_SB_DIR}" "smallbank" "${SEED_DB_SMALLBANK}" run_aco_smallbank_tool || \
    echo "WARNING: ACo SmallBank arm failed; continuing with remaining arms." >&2

echo "----------------->> DCo SmallBank <<-----------------"
export RESULTS_DIR="${RESULTS_SB}"
bench_arm_from_seed "dco" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_dco_smallbank_tool || \
    echo "WARNING: DCo SmallBank arm failed; continuing with remaining arms." >&2

echo "----------------->> ADCo SmallBank <<-----------------"
export RESULTS_DIR="${RESULTS_SB}"
bench_arm_from_seed "adco" "${ADCo_SB_DIR}" "smallbank" "${SEED_DB_SMALLBANK}" run_adco_smallbank_tool || \
    echo "WARNING: ADCo SmallBank arm failed; continuing with remaining arms." >&2

# ── TPCC: baseline + ACo + DCo + ADCo from one snapshot ──
export BENCH_CMDRUNTPCC="${ROOT}/scripts/adco_only/runExperiment1-Workload-TPCC.sh"

echo "----------------->> Seed TPCC (load once + snapshot) <<-----------------"
bench_seed_once "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> Baseline TPCC <<-----------------"
export RESULTS_DIR="${RESULTS_TPCC}"
bench_arm_from_seed "baseline" "baseline" "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> ACo TPCC <<-----------------"
export RESULTS_DIR="${RESULTS_TPCC}"
bench_arm_from_seed "aco" "${ACo_TPCC_DIR}" "tpcc" "${SEED_DB_TPCC}" run_aco_tpcc_tool || \
    echo "WARNING: ACo TPCC arm failed; continuing with remaining arms." >&2

echo "----------------->> DCo TPCC <<-----------------"
export RESULTS_DIR="${RESULTS_TPCC}"
bench_arm_from_seed "dco" "baseline" "tpcc" "${SEED_DB_TPCC}" run_dco_tpcc_tool || \
    echo "WARNING: DCo TPCC arm failed; continuing with remaining arms." >&2

echo "----------------->> ADCo TPCC <<-----------------"
export RESULTS_DIR="${RESULTS_TPCC}"
bench_arm_from_seed "adco" "${ADCo_TPCC_DIR}" "tpcc" "${SEED_DB_TPCC}" run_adco_tpcc_tool || \
    echo "WARNING: ADCo TPCC arm failed; continuing with remaining arms." >&2

echo "----------------->> Comparison <<-----------------"
RESULTS_DIR="${RESULTS_SB}" "${ROOT}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
RESULTS_DIR="${RESULTS_TPCC}" "${ROOT}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
