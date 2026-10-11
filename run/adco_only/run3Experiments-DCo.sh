#!/usr/bin/env bash
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

CMDRunDCo="${ROOT}/scripts/adco_only/runExperiment0-DCo.sh"

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

# ── SmallBank: shared baseline (measured) + DCo (knobs only) ──
echo "----------------->> Seed SmallBank (load once + snapshot) <<-----------------"
bench_seed_once "smallbank" "${SEED_DB_SMALLBANK}"

echo "----------------->> Baseline SmallBank <<-----------------"
export RESULTS_DIR="${RESULTS_SB}"
bench_arm_from_seed "baseline" "baseline" "smallbank" "${SEED_DB_SMALLBANK}"

# DCo's optimized arm runs the original app; only the knobs change.
echo "----------------->> DCo SmallBank <<-----------------"
export RESULTS_DIR="${RESULTS_SB}"
bench_arm_from_seed "dco" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_dco_smallbank_tool || \
    echo "WARNING: DCo SmallBank arm failed; continuing with remaining arms." >&2

# ── TPCC: shared baseline (measured) + DCo (knobs only) ──
export BENCH_CMDRUNTPCC="${ROOT}/scripts/adco_only/runExperiment1-Workload-TPCC.sh"

echo "----------------->> Seed TPCC (load once + snapshot) <<-----------------"
bench_seed_once "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> Baseline TPCC <<-----------------"
export RESULTS_DIR="${RESULTS_TPCC}"
bench_arm_from_seed "baseline" "baseline" "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> DCo TPCC <<-----------------"
export RESULTS_DIR="${RESULTS_TPCC}"
bench_arm_from_seed "dco" "baseline" "tpcc" "${SEED_DB_TPCC}" run_dco_tpcc_tool || \
    echo "WARNING: DCo TPCC arm failed; continuing with remaining arms." >&2

echo "----------------->> Comparison <<-----------------"
RESULTS_DIR="${RESULTS_SB}" "${ROOT}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
RESULTS_DIR="${RESULTS_TPCC}" "${ROOT}/scripts/_lib/run_comparison.sh" "${RUN_ID}"
