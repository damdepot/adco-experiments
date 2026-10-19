#!/usr/bin/env bash
#
# DCo experiments (SmallBank only) — canonical seed-once + restore ->
# tune -> restart -> measure (cf. benchmarks/run0_smallbank.sh,
# run2_dco_smallbank.sh).
#
#   bench_lock, SEED_DB, bench_ensure_seed, inline restore/reset/asserts/
#   tool/restart/measure, comparison call per benchmark.
#
# Resource/workload contract: scripts/_lib/bench_lib.sh (single place).
# Smallbank-only knobs, still env-overridable:
#   ACCOUNTS=5000000 TRANSACTIONS=60000
#
# No post-tool restore: the DB is measured as the tuner left it, followed
# by Restart/WaitFor cold buffers before measure. Knob settings live in
# postgresql.auto.conf and survive the restart.
#
# Optimized arms run the baseline app path (knob-only delta, as in
# run2_dco_smallbank.sh); DCo's rewritten sandbox is retained under
# out/db_layer/DCo-results for inspection.
#
# Canonical rep CSVs: results/<benchmark>/dco/benchmarks/
#   <tag>.csv  (tags: baseline, dco)
# Single-file aliases (report.py compat) are refreshed alongside the rep CSVs:
#   results/<benchmark>/dco/benchmarks/runExperiment1-<bm>-postgres-<model>
#
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
LIB="${EXP_PATH}/scripts/_lib/bench_lib.sh"

MODEL="${MODEL:-gemini-3.5-flash-lite}"

# shellcheck disable=SC1090
source "${LIB}"

DCO_SMALLBANK_BASE="${EXP_PATH}/results/smallbank/dco/benchmarks"
mkdir -p "${DCO_SMALLBANK_BASE}"
mkdir -p "${EXP_PATH}/out/db_layer/DCo-results"

bench_lock "${EXP_PATH}"
bench_timer "smallbank/run_dco" "results/smallbank/dco" "dco"

CMDADCo="${EXP_PATH}/scripts/common/db_layer/exp0_ADCo/runExperiment0.sh"

# $1=subdir $2=tag $3=per-benchmark base dir $4=benchmark (aliases keep -<model> suffix)
legacy_sync() {
    local subdir="$1" tag="$2" base="$3" benchmark="$4"
    local prefix="${base}/runExperiment1-${benchmark}-${DBMS}-${MODEL}"
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
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-Db-ADCo.sh"
SMALLBANK_RESULTS="${DCO_SMALLBANK_BASE}"
mkdir -p "${SMALLBANK_RESULTS}"
export RESULTS_DIR="${SMALLBANK_RESULTS}"
SEED_DB_SMALLBANK="smallbank_seed"
export BENCH_REP_DB="smallbank" BENCH_REP_SEED="${SEED_DB_SMALLBANK}"

run_dco_smallbank_tool() {
    if ! "$CMDADCo" DCo "${MODEL}" "${DBMS}" smallbank; then
        echo "ERROR: DCo tuning failed; skipping post-DCo SmallBank measurement and CSV." >&2
        return 1
    fi
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"

echo "----------------->> DCo smallbank <<-----------------"
bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
# Fresh data + default knobs verified before tool (abort on failure).
restore_defaults
bench_assert_fresh_knobs
bench_assert_rows "smallbank" "accounts" "${ACCOUNTS}"
run_dco_smallbank_tool
"${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
"${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
bench_measure "baseline" "dco.csv"
legacy_sync "${SMALLBANK_RESULTS}" "dco" "${DCO_SMALLBANK_BASE}" "smallbank"


