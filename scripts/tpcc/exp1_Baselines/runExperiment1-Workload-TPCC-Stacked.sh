#!/usr/bin/env bash
#
# Stacked baseline arms: Naive-LLM app rewrite + AgentTune knob tuning in the
# order given by STACK_ORDER, measured on the rewritten app with the tuned
# knobs. Each arm runs its own rewrite and its own tuning (no reuse).
#
#   naive-first:     rewrite, then tune
#   agenttune-first: tune, then rewrite
#
# A retry after a failed arm skips the phases already done (markers + validated
# artifacts in results/tpcc/<arm>/state) and runs only the missing ones.
# Force a full re-run: rm -rf results/tpcc/<arm>/state (and optionally the
# rewrite root).
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

export MODEL

if [ ! -x "${EXP_PATH}/baselines/AgentTune/venv/bin/python" ]; then
    echo "ERROR: missing ${EXP_PATH}/baselines/AgentTune/venv/bin/python." >&2
    echo "Run db-setup-baselines.sh inside adcoexp to provision the AgentTune venv." >&2
    exit 1
fi

# Single-writer: never Restart the DB under a concurrent run.
bench_lock "${EXP_PATH}"
bench_timer "tpcc/run_${STACK_ARM}" "results/tpcc/${STACK_ARM}" "${STACK_ARM}"

mkdir -p "results/tpcc/${STACK_ARM}/benchmarks"
STATE_DIR="${EXP_PATH}/results/tpcc/${STACK_ARM}/state"
mkdir -p "${STATE_DIR}"
export ARM="${STACK_ARM}" NAIVE_REWRITE_ROOT
export BENCH_RESULTS_DIR="${EXP_PATH}/results/tpcc/${STACK_ARM}/benchmarks"

CMDNAIVE=./scripts/common/app_layer/exp1_Baselines/runExperiment1-NaiveLLM.sh
CMDRUNTPCC=./scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-NaiveLLM.sh
CMDDOCKER=./scripts/_lib/docker.sh
CMDAGENTTUNE=./scripts/common/db_layer/exp1_Baselines/runExperiment1-AgentTune.sh

# bench_ensure_seed loads via BENCH_CMDRUNTPCC (bench_lib's default points at a
# nonexistent scripts/_lib/tpcc.sh); point it at the canonical DB runner.
export BENCH_CMDRUNTPCC="${EXP_PATH}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Db.sh"

SEED_DB_TPCC="tpcc_seed"
export BENCH_REP_DB="tpcc" BENCH_REP_SEED="${SEED_DB_TPCC}"

AGENTTUNE_ITERATIONS="${AGENTTUNE_ITERATIONS:-}"

# A marker alone is not proof: the phase's artifact must still be there.
phase_naive_done() {
    if [ -f "${STATE_DIR}/naive.done" ] \
        && [ -f "${EXP_PATH}/${NAIVE_REWRITE_ROOT}/Rewrite/postgres/tpcc-NaiveLLM/tpcc.py" ]; then
        return 0
    fi
    rm -f "${STATE_DIR}/naive.done"
    return 1
}

phase_agenttune_done() {
    # An empty auto.conf is a valid outcome (no candidate beat the defaults);
    # the markers are the proof that tuning + snapshotting completed.
    if [ -f "${STATE_DIR}/agenttune.done" ] \
        && [ -f "${STATE_DIR}/agenttune.auto.conf" ] \
        && [ -f "${STATE_DIR}/agenttune.knobs.txt" ]; then
        return 0
    fi
    rm -f "${STATE_DIR}/agenttune.done"
    return 1
}

# Save/restore the tuned knobs so a resume can skip AgentTune but still measure
# under the same configuration.
capture_tuned_config() {
    local pgdata
    pgdata="$(docker exec "${BENCH_DB_CONTAINER}" printenv PGDATA)"
    docker exec -u postgres "${BENCH_DB_CONTAINER}" cat "${pgdata:-/var/lib/postgresql/data}/postgresql.auto.conf" > "${STATE_DIR}/agenttune.auto.conf"
    # Readable snapshot of the tuned values + units for the run log.
    python3 "${EXP_PATH}/tools/check_knobs.py" > "${STATE_DIR}/agenttune.knobs.txt"
}

apply_tuned_config() {
    local pgdata
    pgdata="$(docker exec "${BENCH_DB_CONTAINER}" printenv PGDATA)"
    if grep -qE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_.]*[[:space:]]*=' "${STATE_DIR}/agenttune.auto.conf"; then
        docker exec -i -u postgres "${BENCH_DB_CONTAINER}" sh -c "cat > '${pgdata:-/var/lib/postgresql/data}/postgresql.auto.conf'" < "${STATE_DIR}/agenttune.auto.conf"
        "${CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
        "${CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    else
        # No overrides were tuned: the arm's config is the DB defaults.
        restore_defaults
    fi
    # Prove the restore landed: the applied knobs must match the snapshot.
    python3 "${EXP_PATH}/tools/check_knobs.py" > "${STATE_DIR}/agenttune.knobs.applied.txt"
    if ! diff -q "${STATE_DIR}/agenttune.knobs.txt" "${STATE_DIR}/agenttune.knobs.applied.txt" >/dev/null; then
        echo "ERROR: re-applied AgentTune knobs differ from the saved snapshot:" >&2
        diff -u "${STATE_DIR}/agenttune.knobs.txt" "${STATE_DIR}/agenttune.knobs.applied.txt" >&2 || true
        exit 1
    fi
}

phase_naive() {
    echo '-------------------<< Naive-LLM rewrite (TPCC) >>-------------------'
    # This arm owns its rewrite tree: start it empty so no stale rewrite leaks in.
    rm -rf "${EXP_PATH}/${NAIVE_REWRITE_ROOT}"
    mkdir -p "${EXP_PATH}/${NAIVE_REWRITE_ROOT}"
    if ! "$CMDNAIVE" workload/apps/tpcc postgres tpcc "${MODEL}"; then
        echo "ERROR: Naive-LLM TPCC rewrite failed." >&2
        exit 1
    fi
    touch "${STATE_DIR}/naive.done"
}

phase_agenttune() {
    echo '-------------------<< AgentTune tuning (TPCC) >>-------------------'
    # baselines/AgentTune/config.ini is shared state: a TPCH run leaves
    # DB_Name=tpch/benchmark=JOB behind. Pin this arm's values at launch.
    # benchmark stays SYSBENCH: AgentTune tunes via its sysbench proxy
    # workload (no tpcc branch exists in its benchmark switch); the tuned
    # knobs are then measured with the real TPC-C workload.
    python3 - "${EXP_PATH}/baselines/AgentTune/config.ini" "${AGENTTUNE_ITERATIONS}" <<'PY'
import configparser, sys
cfg, iterations = sys.argv[1], sys.argv[2]
c = configparser.ConfigParser()
c.optionxform = str
c.read(cfg)
rec = c['configuration recommender']
rec['DB_Name'] = 'tpcc'
rec['benchmark'] = 'SYSBENCH'
if iterations:
    rec['iteration'] = iterations
with open(cfg, 'w') as f:
    c.write(f)
print('AgentTune config.ini: DB_Name=%s benchmark=%s iteration=%s'
      % (rec['DB_Name'], rec['benchmark'], rec.get('iteration')))
PY
    if ! "$CMDAGENTTUNE" postgres tpcc; then
        echo "ERROR: AgentTune TPCC tuning failed." >&2
        exit 1
    fi
    capture_tuned_config
    touch "${STATE_DIR}/agenttune.done"
}

# Restore the snapshot before measuring: the rewrite's smoke run and tuning
# leave writes behind, so the measured reps must start from the pristine seed.
# Then cold buffers + settled data; execute uses existing data.
measure_prep() {
    bench_restore "tpcc" "${SEED_DB_TPCC}"
    "${CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}" || "${CMDDOCKER}" Up "${BENCH_DB_CONTAINER}" "${BENCH_DB_SERVICE}"
    "${CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    bench_settle
}

echo "----------------->> Seed tpcc (load once + snapshot) <<-----------------"
bench_ensure_seed "tpcc" "${SEED_DB_TPCC}"
bench_assert_seed "${SEED_DB_TPCC}"

NAIVE_DONE=0
AGENTTUNE_DONE=0
if phase_naive_done; then
    NAIVE_DONE=1
fi
if phase_agenttune_done; then
    AGENTTUNE_DONE=1
fi

if [ "${AGENTTUNE_DONE}" = "1" ]; then
    echo "Resume: re-applying saved AgentTune config"
    bench_restore "tpcc" "${SEED_DB_TPCC}"
    apply_tuned_config
    cat "${STATE_DIR}/agenttune.knobs.txt"
else
    bench_restore "tpcc" "${SEED_DB_TPCC}"
    restore_defaults
    bench_assert_fresh_knobs
fi
bench_assert_rows "tpcc" "warehouse" "${TPCC_WAREHOUSES}"

if [ "${NAIVE_DONE}" = "1" ]; then
    echo "Resume: skipping Naive-LLM (already done)"
fi
if [ "${AGENTTUNE_DONE}" = "1" ]; then
    echo "Resume: skipping AgentTune (already done)"
fi

if [ "${STACK_ORDER}" = "naive-first" ]; then
    if [ "${NAIVE_DONE}" = "0" ]; then
        phase_naive
    fi
    if [ "${AGENTTUNE_DONE}" = "0" ]; then
        phase_agenttune
    fi
else
    TUNED_NOW=0
    if [ "${AGENTTUNE_DONE}" = "0" ]; then
        phase_agenttune
        TUNED_NOW=1
    fi
    if [ "${NAIVE_DONE}" = "0" ]; then
        # AgentTune's SYSBENCH path ends with DROP SCHEMA public CASCADE;
        # restore the data but keep the tuned knobs.
        if [ "${TUNED_NOW}" = "1" ]; then
            bench_restore "tpcc" "${SEED_DB_TPCC}"
        fi
        phase_naive
    fi
fi

measure_prep
PHASE=execute "$CMDRUNTPCC" postgres "${TPCC_WAREHOUSES}" "${TPCC_CLIENTS}" tpcc "${STACK_ARM}" "${NAIVE_REWRITE_ROOT}"
