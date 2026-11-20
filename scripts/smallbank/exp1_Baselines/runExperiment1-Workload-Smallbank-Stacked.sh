#!/usr/bin/env bash
#
# Stacked baseline arms: Naive-LLM app rewrite + AgentTune knob tuning in the
# order given by STACK_ORDER, measured on the rewritten app with the tuned
# knobs. Each arm runs its own rewrite and its own tuning (no reuse).
#
#   naive-first:     rewrite, then tune
#   agenttune-first: tune, then rewrite
#
# The Naive-LLM rewrite always re-runs; only AgentTune tuning is cached/skipped
# (markers + validated artifacts in results/smallbank/<arm>/state).
# FORCE=1 clears both for a full re-run.
#
# Env: STACK_ORDER, STACK_ARM (results dir + CSV tag), NAIVE_REWRITE_ROOT.
# Optional: AGENTTUNE_ITERATIONS pins config.ini's iteration count.
#
set -euo pipefail

EXP_PATH="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# shellcheck disable=SC1091
source "${EXP_PATH}/scripts/_lib/bench_lib.sh"
export BENCH_DB_CONTAINER

MODEL="${MODEL:-gemini-3.5-flash-lite}"

STACK_ORDER="${STACK_ORDER:-}"
STACK_ARM="${STACK_ARM:-}"
NAIVE_REWRITE_ROOT="${NAIVE_REWRITE_ROOT:-}"
case "${STACK_ORDER}" in
    naive-first|agenttune-first) ;;
    *)
        echo "ERROR: STACK_ORDER must be 'naive-first' or 'agenttune-first' (got '${STACK_ORDER}')." >&2
        exit 2
        ;;
esac
if [ -z "${STACK_ARM}" ] || [ -z "${NAIVE_REWRITE_ROOT}" ]; then
    echo "ERROR: STACK_ARM and NAIVE_REWRITE_ROOT must be set." >&2
    exit 2
fi

# TEMPERATURE/TEMP are inherited unchanged by the rewrite runner below.
export MODEL

if [ ! -x "${EXP_PATH}/baselines/AgentTune/venv/bin/python" ]; then
    echo "ERROR: missing ${EXP_PATH}/baselines/AgentTune/venv/bin/python." >&2
    echo "Run db-setup-baselines.sh inside adcoexp to provision the AgentTune venv." >&2
    exit 1
fi

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${EXP_PATH}"
bench_timer "smallbank/run_${STACK_ARM}" "results/smallbank/${STACK_ARM}" "${STACK_ARM}"

mkdir -p "results/smallbank/${STACK_ARM}/benchmarks"
STATE_DIR="${EXP_PATH}/results/smallbank/${STACK_ARM}/state"
mkdir -p "${STATE_DIR}"
if [ "${FORCE:-0}" = "1" ]; then
    echo "FORCE=1: clearing ${STATE_DIR} and ${EXP_PATH}/${NAIVE_REWRITE_ROOT}/Rewrite/postgres/smallbank-NaiveLLM for full re-run."
    rm -rf "${STATE_DIR}" "${EXP_PATH}/${NAIVE_REWRITE_ROOT}/Rewrite/postgres/smallbank-NaiveLLM"
    mkdir -p "${STATE_DIR}"
fi
export ARM="${STACK_ARM}" NAIVE_REWRITE_ROOT
export BENCH_RESULTS_DIR="${EXP_PATH}/results/smallbank/${STACK_ARM}/benchmarks"

CMDNAIVE=./scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh
CMDRUNSMALLBANK=./scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh
CMDDOCKER=./scripts/_lib/docker.sh
CMDAGENTTUNE=./scripts/common/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh

# bench_ensure_seed loads via BENCH_CMDRUNTPCC (bench_lib's default points at a
# nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"

SEED_DB_SMALLBANK="smallbank_seed"
export BENCH_REP_DB="smallbank" BENCH_REP_SEED="${SEED_DB_SMALLBANK}"

AGENTTUNE_ITERATIONS="${AGENTTUNE_ITERATIONS:-}"

# A marker alone is not proof: the phase's artifact must still be there.
phase_agenttune_done() {
    # An empty auto.conf is a valid outcome (no candidate beat the defaults);
    # the markers are the proof that tuning + snapshotting completed.
    if [ -f "${STATE_DIR}/agenttune.done" ] \
        && [ -f "${STATE_DIR}/agenttune.auto.conf" ]; then
        return 0
    fi
    rm -f "${STATE_DIR}/agenttune.done"
    return 1
}

phase_naive() {
    echo '-------------------<< Naive-LLM rewrite (SmallBank) >>-------------------'
    # This arm owns its rewrite tree: start it empty so no stale rewrite leaks in.
    rm -rf "${EXP_PATH}/${NAIVE_REWRITE_ROOT}/Rewrite/postgres/smallbank-NaiveLLM"
    mkdir -p "${EXP_PATH}/${NAIVE_REWRITE_ROOT}"
    if ! "$CMDNAIVE" workload/apps/smallbank postgres smallbank "${MODEL}"; then
        echo "ERROR: Naive-LLM SmallBank rewrite failed." >&2
        exit 1
    fi
    touch "${STATE_DIR}/naive.done"
}

phase_agenttune() {
    echo '-------------------<< AgentTune tuning (SmallBank) >>-------------------'
    # baselines/AgentTune/config.ini is shared state: a TPCH run leaves
    # DB_Name=tpch/benchmark=JOB behind. Pin this arm's values at launch.
    # benchmark stays SYSBENCH: AgentTune tunes via its sysbench proxy
    # workload (no smallbank branch exists in its benchmark switch); the tuned
    # knobs are then measured with the real SmallBank workload.
    python3 - "${EXP_PATH}/baselines/AgentTune/config.ini" "${AGENTTUNE_ITERATIONS}" <<'PY'
import configparser, sys
cfg, iterations = sys.argv[1], sys.argv[2]
c = configparser.ConfigParser()
c.optionxform = str
c.read(cfg)
rec = c['configuration recommender']
rec['DB_Name'] = 'smallbank'
rec['benchmark'] = 'SYSBENCH'
if iterations:
    rec['iteration'] = iterations
with open(cfg, 'w') as f:
    c.write(f)
print('AgentTune config.ini: DB_Name=%s benchmark=%s iteration=%s'
      % (rec['DB_Name'], rec['benchmark'], rec.get('iteration')))
PY
    if ! "$CMDAGENTTUNE" "${DBMS}" smallbank; then
        echo "ERROR: AgentTune SmallBank tuning failed." >&2
        exit 1
    fi
    bench_knobs_save "${STATE_DIR}" "agenttune"
}

# Restore the snapshot before measuring: the rewrite's smoke run and tuning
# leave writes behind, so the measured reps must start from the pristine seed.
# Then cold buffers + settled data; execute uses existing data.
measure_prep() {
    bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    "${CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}" || "${CMDDOCKER}" Up "${BENCH_DB_CONTAINER}" "${BENCH_DB_SERVICE}"
    "${CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    bench_settle
}

echo "----------------->> Seed smallbank (load once + snapshot) <<-----------------"
bench_ensure_seed "smallbank" "${SEED_DB_SMALLBANK}"
bench_assert_seed "${SEED_DB_SMALLBANK}"

AGENTTUNE_DONE=0
if phase_agenttune_done; then
    AGENTTUNE_DONE=1
fi

if [ "${AGENTTUNE_DONE}" = "1" ]; then
    echo "Resume: re-applying saved AgentTune config"
    bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    bench_knobs_apply "${STATE_DIR}" "agenttune"
    bench_print_knobs
else
    bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    restore_defaults
    bench_assert_fresh_knobs
fi
bench_assert_rows "smallbank" "accounts" "${SMALLBANK_ACCOUNTS}"

if [ "${AGENTTUNE_DONE}" = "1" ]; then
    echo "Resume: skipping AgentTune (already done)"
fi

if [ "${STACK_ORDER}" = "naive-first" ]; then
    phase_naive
    if [ "${AGENTTUNE_DONE}" = "0" ]; then
        phase_agenttune
    fi
else
    TUNED_NOW=0
    if [ "${AGENTTUNE_DONE}" = "0" ]; then
        phase_agenttune
        TUNED_NOW=1
    fi
    # AgentTune's SYSBENCH path ends with DROP SCHEMA public CASCADE;
    # restore the data but keep the tuned knobs.
    if [ "${TUNED_NOW}" = "1" ]; then
        bench_restore "smallbank" "${SEED_DB_SMALLBANK}"
    fi
    phase_naive
fi

# run_verify.sh has no arm spec for the stacked arms; VERIFY_REWRITE_ROOT maps
# the arm to its own rewrite tree (VERIFY_CSV keeps the smoke CSV out of the
# measured dir naming).
BENCH_LOCK_HELD=1 REVERIFY=1 VERIFY_KEEP_KNOBS=1 \
    VERIFY_REWRITE_ROOT="${NAIVE_REWRITE_ROOT}" \
    VERIFY_CSV="results/smallbank/${STACK_ARM}/benchmarks/${STACK_ARM}.csv" \
    "${EXP_PATH}/run/smallbank/run_verify.sh" "${STACK_ARM}"
measure_prep
PHASE=execute "$CMDRUNSMALLBANK" postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_DURATION}" smallbank "${STACK_ARM}" "${NAIVE_REWRITE_ROOT}"
