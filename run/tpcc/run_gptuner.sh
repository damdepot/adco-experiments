#!/usr/bin/env bash
#
# GPTuner experiments — canonical seed-once + bench_arm_from_seed pattern
# (cf. benchmarks/run0_smallbank.sh).
#
# bench_lock, SEED_DB, bench_seed_once, per-arm bench_arm_from_seed
# with tool fns, comparison call per benchmark.
#
# Baseline compat: the existing
#   scripts/common/db_layer/exp1_Baselines/runExperiment1-GPTuner.sh
# entrypoint is kept callable standalone AND is invoked as the tool fn here.
# Post-tool bench_restore scrubs tool screening writes; Restart/WaitFor gives
# cold buffers before measure. The optimized arm runs the baseline app path
# (knob-only delta).
#
# NOTE on comparison: scripts/_lib/run_comparison.sh tabulates its default
# labels (baseline/aco/dco/adco); the `gptuner` tag is therefore not shown
# there — use scripts/common/db_layer/exp2_Reports for the cross-tool view.
#
# Canonical rep CSVs: results/<benchmark>/gptuner/benchmarks/
#   <tag>.csv (tags: baseline, gptuner)
# Single-file aliases (report.py compat): results/<benchmark>/gptuner/
#   benchmarks/runExperiment1-<bm>-postgres-<model>
#
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-8}"
export REPS="${REPS:-3}"
export DURATION="${DURATION:-60}"
export WARMUP="${WARMUP:-10}"
export WAREHOUSES="${WAREHOUSES:-6}"
export CLIENTS="${CLIENTS:-6}"
export ACCOUNTS="${ACCOUNTS:-1000000}"
export TRANSACTIONS="${TRANSACTIONS:-60000}"
export SETTLE_SECS="${SETTLE_SECS:-5}"
export DBMS="${DBMS:-postgres}"
export TARGET_MEMORY_GB="${TARGET_MEMORY_GB:-${MEMORY_GB}}"
export TARGET_CPU_CORES="${TARGET_CPU_CORES:-${CPU_CORES}}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"

# shellcheck disable=SC1090
source "${LIB}"

TPCC_TOOL_BASE="${EXP_PATH}/results/tpcc/gptuner/benchmarks"
mkdir -p "${TPCC_TOOL_BASE}"
mkdir -p "${EXP_PATH}/out/db_layer/GPTuner-results"

bench_lock "${EXP_PATH}"

CMGPTuner="${EXP_PATH}/scripts/common/db_layer/exp1_Baselines/runExperiment1-GPTuner.sh"

legacy_sync() {
    local subdir="$1" tag="$2" benchmark="$3"
    local prefix="${subdir}/runExperiment1-${benchmark}-${DBMS}-${MODEL}"
    local f last=""
    for f in "${subdir}/${tag}.csv"; do
        if [ ! -e "$f" ]; then
            continue
        fi
        cp "$f" "${prefix}-$(basename "$f" .csv).csv"
        last="$f"
    done
    if [ -n "${last}" ]; then
        cp "${last}" "${prefix}"
    fi
}

# ── TPC-C ─────────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/tpcc/exp1_Baselines/runExperiment0-Workload-TPCC-GPTuner.sh"
TPCC_RESULTS="${TPCC_TOOL_BASE}"
mkdir -p "${TPCC_RESULTS}"
export RESULTS_DIR="${TPCC_RESULTS}"
SEED_DB_TPCC="tpcc_seed"

run_gptuner_tpcc_tool() {
    if ! "$CMGPTuner" "${DBMS}" tpcc "${TARGET_MEMORY_GB}" "${TARGET_CPU_CORES}"; then
        echo "ERROR: GPTuner tuning failed; skipping post-GPTuner TPCC measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"

echo "----------------->> GPTuner tpcc <<-----------------"
bench_arm_from_seed "gptuner" "baseline" "tpcc" "${SEED_DB_TPCC}" run_gptuner_tpcc_tool
legacy_sync "${TPCC_RESULTS}" "gptuner" "tpcc"

echo "----------------->> Comparison tpcc <<-----------------"
RESULTS_DIR="${TPCC_RESULTS}" "${EXP_PATH}/scripts/_lib/run_comparison.sh" || true
