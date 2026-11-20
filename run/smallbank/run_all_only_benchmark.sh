#!/usr/bin/env bash
#
# Benchmark every SmallBank arm from its existing artifacts only. Never
# regenerates rewrites, never tunes, never verifies, never rm -rf's
# results/state/rewrite trees.
#
# Usage: run_all_only_benchmark.sh [arm ...]
#
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "${ROOT}"
source "${ROOT}/scripts/_lib/bench_lib.sh"

MODEL="${MODEL:-gemini-3.5-flash-lite}"

bench_lock "${ROOT}"
bench_timer "smallbank/run_all_only_benchmark" "results/smallbank" "benchmark_only"

ALL=(baseline py-dbridge naive-llm aco ottertune gptuner agenttune naive-llm-agenttune agenttune-naive-llm dco adco)
ARMS=("${ALL[@]}")
if [ "$#" -gt 0 ]; then
    ARMS=("$@")
fi

RUN_TS="$(date '+%Y-%m-%d-%H-%M-%S')"
LOG_DIR="${ROOT}/out/logs/smallbank"
RESULT_JSON="${ROOT}/results/smallbank/result_benchmark_only.json"
mkdir -p "${LOG_DIR}" "$(dirname "${RESULT_JSON}")"
LOG="${LOG_DIR}/${RUN_TS}-benchmark-only.log"
: > "${LOG}"

python3 - "${RESULT_JSON}" "${RUN_TS}" "${ARMS[@]}" <<'PY'
import json, sys
path, run_ts, names = sys.argv[1], sys.argv[2], sys.argv[3:]
data = {"run_started": run_ts}
data.update({name: "pending" for name in names})
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY

record_status() {
    python3 - "${RESULT_JSON}" "$1" "$2" <<'PY'
import json, sys
path, name, status = sys.argv[1], sys.argv[2], sys.argv[3]
with open(path) as f:
    data = json.load(f)
data[name] = status
with open(path, "w") as f:
    json.dump(data, f, indent=2)
PY
}

# Copy canonical rep CSVs to single-file aliases for report.py compat.
# $1=subdir $2=tag $3=benchmark $4=suffix ("" = no suffix, e.g. baseline).
# No-op when the tag CSV is absent (runners without one skip silently).
legacy_sync() {
    local subdir="$1" tag="$2" benchmark="$3" suffix="${4-${MODEL}}"
    local prefix
    if [ -n "${suffix}" ]; then
        prefix="${subdir}/runExperiment1-${benchmark}-${DBMS}-${suffix}"
    else
        prefix="${subdir}/runExperiment1-${benchmark}-${DBMS}"
    fi
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

# Seed loader needs the canonical DB runner (bench_lib default tpcc.sh path
# does not exist); per-arm measures override BENCH_CMDRUNTPCC as needed.
export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"
echo "----------------->> Seed smallbank (ensure once) <<-----------------" | tee -a "${LOG}"
bench_ensure_seed smallbank smallbank_seed 2>&1 | tee -a "${LOG}"
export BENCH_REP_DB="smallbank" BENCH_REP_SEED="smallbank_seed"

# (1) Artifact gate: return 0 iff the arm's existing artifacts suffice.
gate_arm() {
    local arm="$1" f
    case "${arm}" in
        baseline) return 0 ;;
        dco)
            bench_knob_cache_hit "results/smallbank/dco/state" "dco" && return 0
            echo "MISSING knob cache results/smallbank/dco/state/dco.*"
            return 1 ;;
        adco)
            f="out/app_layer/ADCo-results/Rewrite/postgres/smallbank-${MODEL}/drivers/postgresdriver.py"
            [ -f "${f}" ] || { echo "MISSING ${f}"; return 1; }
            bench_knob_cache_hit "results/smallbank/adco/state" "adco" && return 0
            echo "MISSING knob cache results/smallbank/adco/state/adco.*"
            return 1 ;;
        aco) f="out/app_layer/ACo-results/Rewrite/postgres/smallbank-${MODEL}/drivers/postgresdriver.py" ;;
        naive-llm) f="out/app_layer/NaiveLLM-results/Rewrite/postgres/smallbank-NaiveLLM/drivers/postgresdriver.py" ;;
        py-dbridge) f="out/app_layer/Py-DBridge-results/Rewrite/postgres/smallbank-Py-DBridge/drivers/postgresdriver.py" ;;
        agenttune|gptuner|ottertune)
            bench_knob_cache_hit "results/smallbank/${arm}/state" "${arm}" && return 0
            echo "MISSING knob cache results/smallbank/${arm}/state/${arm}.*"
            return 1 ;;
        naive-llm-agenttune|agenttune-naive-llm)
            f="out/app_layer/NaiveLLM-results/${arm}/Rewrite/postgres/smallbank-NaiveLLM/drivers/postgresdriver.py"
            [ -f "${f}" ] || { echo "MISSING ${f}"; return 1; }
            bench_knob_cache_hit "results/smallbank/${arm}/state" "agenttune" && return 0
            echo "MISSING knob cache results/smallbank/${arm}/state/agenttune.*"
            return 1 ;;
        *) echo "MISSING unknown arm ${arm}"; return 1 ;;
    esac
    [ -f "${f}" ] && return 0
    echo "MISSING ${f}"
    return 1
}

# Pristine-DB prep shared by the app-layer arms (restore keeps rewrite files
# on disk untouched; no verify step here).
measure_prep() {
    bench_restore smallbank smallbank_seed
    restore_defaults
    bench_assert_fresh_knobs
    bench_assert_rows smallbank accounts "${SMALLBANK_ACCOUNTS}"
    "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
    "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
    bench_settle
}

# (2) Benchmark-only measurement; never calls tune/rewrite/verify entrypoints.
measure_arm() {
    local arm="$1" results suffix="${MODEL}"
    case "${arm}" in
        baseline)
            export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Db.sh"
            results="${ROOT}/results/smallbank/baseline/benchmarks"
            mkdir -p "${results}"; export RESULTS_DIR="${results}"
            restore_defaults
            bench_assert_fresh_knobs
            bench_assert_rows smallbank_seed accounts "${SMALLBANK_ACCOUNTS}"
            bench_arm_from_seed baseline baseline smallbank smallbank_seed
            legacy_sync "${results}" baseline smallbank "" ;;
        agenttune)
            export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment0-Workload-Smallbank-AgentTune.sh" ;;
        gptuner)
            export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment0-Workload-Smallbank-GPTuner.sh" ;;
        ottertune)
            export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp1_Baselines/runExperiment0-Workload-Smallbank-OtterTune.sh" ;;
    esac
    case "${arm}" in
        agenttune|gptuner|ottertune)
            results="${ROOT}/results/smallbank/${arm}/benchmarks"
            mkdir -p "${results}"; export RESULTS_DIR="${results}"
            bench_knobs_apply "results/smallbank/${arm}/state" "${arm}"
            bench_arm_from_seed "${arm}" baseline smallbank smallbank_seed
            [ "${arm}" = "ottertune" ] && suffix="ottertune"
            legacy_sync "${results}" "${arm}" smallbank "${suffix}" ;;
        aco)
            measure_prep
            PHASE=execute scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh "${MODEL}" postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_DURATION}" smallbank aco ;;
        naive-llm)
            measure_prep
            PHASE=execute scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_DURATION}" smallbank naive-llm out/app_layer/NaiveLLM-results ;;
        naive-llm-agenttune|agenttune-naive-llm)
            bench_restore smallbank smallbank_seed
            bench_knobs_apply "results/smallbank/${arm}/state" agenttune
            "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
            "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
            bench_settle
            PHASE=execute scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-NaiveLLM.sh postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_DURATION}" smallbank "${arm}" "out/app_layer/NaiveLLM-results/${arm}" ;;
        py-dbridge)
            measure_prep
            PHASE=execute scripts/smallbank/exp1_Baselines/runExperiment1-Workload-Smallbank-Py-DBridge.sh postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_DURATION}" smallbank ;;
        dco)
            export BENCH_CMDRUNTPCC="${ROOT}/scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-Db-ADCo.sh"
            results="${ROOT}/results/smallbank/dco/benchmarks"
            mkdir -p "${results}"; export RESULTS_DIR="${results}"
            bench_knobs_apply "results/smallbank/dco/state" "dco"
            bench_restore smallbank smallbank_seed
            "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
            "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
            bench_settle
            bench_measure "baseline" "dco.csv"
            legacy_sync "${results}" dco smallbank "${MODEL}" ;;
        adco)
            bench_restore smallbank smallbank_seed
            bench_knobs_apply "results/smallbank/adco/state" "adco"
            "${BENCH_CMDDOCKER}" Restart "${BENCH_DB_CONTAINER}"
            "${BENCH_CMDDOCKER}" WaitFor "${BENCH_DB_CONTAINER}"
            bench_settle
            PHASE=execute scripts/smallbank/exp0_ADCo/runExperiment0-Workload-Smallbank-App-ADCo.sh "${MODEL}" postgres "${SMALLBANK_ACCOUNTS}" "${SMALLBANK_DURATION}" smallbank adco ;;
    esac
}

for name in "${ARMS[@]}"; do
    echo "----------------->> ${name} (started $(date '+%Y-%m-%d %H:%M:%S')) <<-----------------" | tee -a "${LOG}"
    if ! gate_arm "${name}" 2>&1 | tee -a "${LOG}"; then
        echo "----------------->> ${name}: skipped-no-artifact <<-----------------" | tee -a "${LOG}"
        record_status "${name}" "skipped-no-artifact"
        continue
    fi
    if measure_arm "${name}" 2>&1 | tee -a "${LOG}"; then
        status="success"
    else
        status="fail"
    fi
    echo "----------------->> ${name}: ${status} <<-----------------" | tee -a "${LOG}"
    record_status "${name}" "${status}"
done

echo "Benchmark-only done; statuses in ${RESULT_JSON}" | tee -a "${LOG}"
