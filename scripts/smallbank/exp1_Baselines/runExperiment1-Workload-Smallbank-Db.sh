#!/usr/bin/env bash
#
# Canonical SmallBank workload runner (baseline).
#
# Two modes:
#   Canonical (called by bench_lib via BENCH_CMDRUNTPCC):
#     runExperiment1-Workload-Smallbank.sh <dir> <file> [reps]
#     PHASE=load|execute selects the phase (default: execute).
#     <dir> is 'baseline' or an out/<dir> rewritten app (sandbox switch).
#     <file> is the CSV name; reps default to $REPS (benchmarks scale: 3).
#     Scale defaults to benchmarks scale, env-overridable:
#       ACCOUNTS=1000000 TRANSACTIONS=60000 LOAD_THREADS=8 REPS=3
#   Legacy (standalone):
#     runExperiment1-Workload-Smallbank.sh <dbms> <accounts> <transactions>
#     PHASE unset => legacy `test` (reset+load+run) with reps loop + CHECKPOINT.
#     PHASE=load|execute forces that phase only.
#
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/smallbank"
BENCH_CMDDOCKER="${BENCH_CMDDOCKER:-${exp_path}/scripts/_lib/docker.sh}"
DB_CONTAINER="${DB_CONTAINER:-${BENCH_DB_CONTAINER:-adcoexp-db}}"

ACCOUNTS="${ACCOUNTS:-1000000}"
TRANSACTIONS="${TRANSACTIONS:-60000}"
LOAD_THREADS="${LOAD_THREADS:-8}"
REPS_DEFAULT="${REPS:-3}"

# ── Canonical mode: $2 looks like a CSV file ─────────────────────────────
if [[ "${2:-}" == *.csv* ]]; then
    dir="${1}"
    file_name="${2}"
    reps="${3:-${REPS_DEFAULT}}"
    phase="${PHASE:-execute}"
    dbms="${DBMS:-postgres}"
    accounts="${ACCOUNTS}"
    transactions="${TRANSACTIONS}"

    case "${phase}" in
        load|execute) ;;
        *) echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2; exit 2 ;;
    esac

    results_dir="${RESULTS_DIR:-${result_benchmark_path:-${exp_path}/results/smallbank/baseline/benchmarks}}"
    mkdir -p "${results_dir}"

    cd "${workload_path}"
    # shellcheck disable=SC1091
    source venv/bin/activate

    if [ "${phase}" = "load" ]; then
        python main.py load \
            --driver "${dbms}" \
            --threads "${LOAD_THREADS}" \
            --accounts "${accounts}" \
            --reset
        exit 0
    fi

    if [ "${dir}" != "baseline" ]; then
        workdir="${exp_path}/out/${dir}"
        [ -d "${workdir}" ] || workdir="${workload_path}"
    else
        workdir="${workload_path}"
    fi
    echo "------->>${workdir}<<-------"

    for (( rep = 1; rep <= reps; rep++ )); do
        if [ "${reps}" -eq 1 ]; then
            rep_file="${file_name}"
        elif [[ "${file_name}" == *.* ]]; then
            rep_file="${file_name%.*}_r${rep}.${file_name##*.}"
        else
            rep_file="${file_name}_r${rep}"
        fi
        log_fname="${results_dir}/${rep_file}"
        echo "----------------->> SMALLBANK rep ${rep}/${reps} (${rep_file}) <<-----------------"
        "${BENCH_CMDDOCKER}" Checkpoint "${DB_CONTAINER}"
        cd "${workdir}"
        python main.py run \
            --driver "${dbms}" \
            --accounts "${accounts}" \
            --transactions "${transactions}" \
            --output-path "${log_fname}"
        cd "${workload_path}"
    done
    exit 0
fi

# ── Legacy mode: <dbms> <accounts> <transactions> ─────────────────────────
dbms="${1:-${DBMS:-postgres}}"
accounts="${2:-${ACCOUNTS}}"
transactions="${3:-${TRANSACTIONS}}"
phase="${PHASE:-test}"

results_dir="${result_benchmark_path:-${exp_path}/results/smallbank/baseline/benchmarks}"
mkdir -p "${results_dir}"
log_fname="${results_dir}/runExperiment1-smallbank-${dbms}"

cd "${workload_path}"
# shellcheck disable=SC1091
source venv/bin/activate

reps="${REPS_DEFAULT}"
case "${phase}" in
    load)
        python main.py load \
            --driver "${dbms}" \
            --threads "${LOAD_THREADS}" \
            --accounts "${accounts}" \
            --reset
        ;;
    execute)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                rep_file="runExperiment1-smallbank-${dbms}"
            else
                rep_file="runExperiment1-smallbank-${dbms}_r${rep}"
            fi
            echo "----------------->> SMALLBANK legacy rep ${rep}/${reps} (${rep_file}) <<-----------------"
            "${BENCH_CMDDOCKER}" Checkpoint "${DB_CONTAINER}"
            python main.py run \
                --driver "${dbms}" \
                --accounts "${accounts}" \
                --transactions "${transactions}" \
                --output-path "${results_dir}/${rep_file}"
        done
        cp "${results_dir}/runExperiment1-smallbank-${dbms}_r${reps}" "${log_fname}" 2>/dev/null || true
        ;;
    test)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                out="${log_fname}"
            else
                out="${log_fname}_r${rep}"
            fi
            echo "----------------->> SMALLBANK legacy test rep ${rep}/${reps} <<-----------------"
            python main.py test \
                --driver "${dbms}" \
                --threads 8 \
                --accounts "${accounts}" \
                --transactions "${transactions}" \
                --output-path "${out}"
        done
        if [ "${reps}" -gt 1 ]; then
            cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true
        fi
        ;;
    *)
        echo "Usage: PHASE must be 'load', 'execute' or 'test' (got '${phase}')" >&2
        exit 2
        ;;
esac
