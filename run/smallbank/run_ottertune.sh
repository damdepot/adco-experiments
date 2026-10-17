#!/usr/bin/env bash
#
# OtterTune experiments (SmallBank only) — canonical seed-once +
# bench_arm_from_seed pattern (cf. benchmarks/run0_smallbank.sh).
#
# bench_lock, SEED_DB, bench_ensure_seed, per-arm bench_arm_from_seed
# with tool fns, comparison call per benchmark.
#
# Baseline compat: the existing
#   scripts/common/db_layer/exp1_Baselines/runExperiment1-OtterTune.sh <dbms> <benchmark> <iterations> <warmup>
# entrypoint is kept callable standalone AND is invoked as the tool fn here
# (defaults OTTERTUNE_ITERATIONS=40 OTTERTUNE_WARMUP=10; env-overridable).
# Post-tool bench_restore scrubs tool screening writes; Restart/WaitFor gives
# cold buffers before measure. The optimized arm runs the baseline app path
# (knob-only delta).
#
# NOTE on comparison: scripts/_lib/run_comparison.sh tabulates its default
# labels (baseline/aco/dco/adco); the `ottertune` tag is therefore not shown
# there — use scripts/common/db_layer/exp2_Reports for the cross-tool view.
#
# Canonical rep CSVs: results/<benchmark>/ottertune/benchmarks/
#   <tag>.csv (tags: baseline, ottertune)
# Single-file aliases (report.py compat): results/<benchmark>/ottertune/
#   benchmarks/runExperiment1-<bm>-postgres-ottertune
#
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

export ACCOUNTS="${ACCOUNTS:-5000000}"
export TRANSACTIONS="${TRANSACTIONS:-60000}"
OTTERTUNE_ITERATIONS="${OTTERTUNE_ITERATIONS:-40}"
OTTERTUNE_WARMUP="${OTTERTUNE_WARMUP:-10}"

# shellcheck disable=SC1090
source "${LIB}"

SMALLBANK_TOOL_BASE="${EXP_PATH}/results/smallbank/ottertune/benchmarks"
mkdir -p "${SMALLBANK_TOOL_BASE}"

bench_lock "${EXP_PATH}"
bench_timer "smallbank/run_ottertune" "results/smallbank/ottertune" "ottertune"

CMOtterTune="${EXP_PATH}/scripts/common/db_layer/exp1_Baselines/runExperiment1-OtterTune.sh"

legacy_sync() {
    local subdir="$1" tag="$2" benchmark="$3"
    local prefix="${subdir}/runExperiment1-${benchmark}-${DBMS}-ottertune"
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
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/smallbank/exp1_Baselines/runExperiment0-Workload-Smallbank-OtterTune.sh"
SMALLBANK_RESULTS="${SMALLBANK_TOOL_BASE}"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"

run_ottertune_smallbank_tool() {
    if ! "$CMOtterTune" "${DBMS}" smallbank "${OTTERTUNE_ITERATIONS}" "${OTTERTUNE_WARMUP}"; then
        echo "ERROR: OtterTune tuning failed; skipping post-OtterTune SmallBank measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"
bench_assert_rows "${SEED_DB_SMALLBANK}" "accounts" "${ACCOUNTS}"

echo "----------------->> OtterTune smallbank <<-----------------"
bench_arm_from_seed "ottertune" "baseline" "smallbank" "${SEED_DB_SMALLBANK}" run_ottertune_smallbank_tool
legacy_sync "${SMALLBANK_RESULTS}" "ottertune" "smallbank"

