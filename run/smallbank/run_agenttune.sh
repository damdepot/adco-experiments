#!/usr/bin/env bash
#
# AgentTune experiments (SmallBank only) — canonical seed-once +
# bench_arm_from_seed pattern (cf. benchmarks/run0_smallbank.sh).
#
# bench_lock, SEED_DB, bench_ensure_seed, per-arm bench_arm_from_seed
# with tool fns, comparison call per benchmark.
#
# Baseline compat: the existing
#   scripts/common/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh
# entrypoint is kept callable standalone AND is invoked as the tool fn here.
# Post-tool bench_restore scrubs tool screening writes; Restart/WaitFor gives
# cold buffers before measure. The optimized arm runs the baseline app path
# (knob-only delta).
#
# NOTE on comparison: scripts/_lib/run_comparison.sh tabulates its default
# labels (baseline/aco/dco/adco); the `agenttune` tag is therefore not shown
# there — use scripts/common/db_layer/exp2_Reports for the cross-tool view. The
# comparison call below still runs (baseline arm) and exits 0.
#
# Canonical rep CSVs: results/<benchmark>/agenttune/benchmarks/
#   <tag>.csv (tags: baseline, agenttune)
# Single-file aliases (report.py compat): results/<benchmark>/agenttune/
#   benchmarks/runExperiment1-<bm>-postgres-<model>
#
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

export CPU_CORES="${CPU_CORES:-2}"
export MEMORY_GB="${MEMORY_GB:-4}"
export REPS="${REPS:-2}"
export DURATION="${DURATION:-180}"
export WARMUP="${WARMUP:-30}"
export WAREHOUSES="${WAREHOUSES:-32}"
export CLIENTS="${CLIENTS:-8}"
export ACCOUNTS="${ACCOUNTS:-5000000}"
export TRANSACTIONS="${TRANSACTIONS:-300000}"
export SETTLE_SECS="${SETTLE_SECS:-5}"
export DBMS="${DBMS:-postgres}"
MODEL="${MODEL:-gemini-3.5-flash-lite}"

# shellcheck disable=SC1090
source "${LIB}"

SMALLBANK_TOOL_BASE="${EXP_PATH}/results/smallbank/agenttune/benchmarks"
mkdir -p "${SMALLBANK_TOOL_BASE}"
mkdir -p "${EXP_PATH}/out/db_layer/AgentTune-results"

bench_lock "${EXP_PATH}"

CMDAgentTune="${EXP_PATH}/scripts/common/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh"

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

# ── SmallBank ─────────────────────────────────────────────────────────────
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/smallbank/exp1_Baselines/runExperiment0-Workload-Smallbank-AgentTune.sh"
SMALLBANK_RESULTS="${SMALLBANK_TOOL_BASE}"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

run_agenttune_smallbank_tool() {
    if ! "$CMDAgentTune" "${DBMS}" smallbank; then
        echo "ERROR: AgentTune tuning failed; skipping post-AgentTune SmallBank measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"
bench_assert_rows "${SEED_DB_SMALLBANK}" "accounts" "${ACCOUNTS}"

echo "----------------->> AgentTune smallbank <<-----------------"
bench_arm_from_seed "agenttune" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_agenttune_smallbank_tool
legacy_sync "${SMALLBANK_RESULTS}" "agenttune" "smallbank"


