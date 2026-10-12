#!/usr/bin/env bash
#
# Canonical SmallBank workload runner (OtterTune).
# Canonical (bench_lib): <dir> <file> [reps], PHASE=load|execute (default execute).
# Legacy: <dbms> <accounts> <transactions> <benchmark>
#
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/smallbank"

ACCOUNTS="${ACCOUNTS:-5000000}"
TRANSACTIONS="${TRANSACTIONS:-300000}"
LOAD_THREADS="${LOAD_THREADS:-4}"
REPS_DEFAULT="${REPS:-5}"
TOOL_RESULTS="${exp_path}/results/smallbank/ottertune/benchmarks"

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
    results_dir="${RESULTS_DIR:-${result_benchmark_path:-${TOOL_RESULTS}}}"
    mkdir -p "${results_dir}"
    cd "${workload_path}"
    # shellcheck disable=SC1091
    source venv/bin/activate
    if [ "${phase}" = "load" ]; then
        python main.py load --driver "${dbms}" --threads "${LOAD_THREADS}" \
            --accounts "${accounts}" --reset
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
        cd "${workdir}"
        python main.py run --driver "${dbms}" --accounts "${accounts}" \
            --transactions "${transactions}" --output-path "${log_fname}"
        cd "${workload_path}"
    done
    exit 0
fi

dbms="${1:-${DBMS:-postgres}}"
accounts="${2:-${ACCOUNTS}}"
transactions="${3:-${TRANSACTIONS}}"
benchmark="${4:-smallbank}"
phase="${PHASE:-test}"
results_dir="${result_benchmark_path:-${TOOL_RESULTS}}"
mkdir -p "${results_dir}"
log_fname="${results_dir}/runExperiment1-${benchmark}-${dbms}-ottertune"
cd "${workload_path}"
# shellcheck disable=SC1091
source venv/bin/activate
reps="${REPS_DEFAULT}"
case "${phase}" in
    load)
        python main.py load --driver "${dbms}" --threads "${LOAD_THREADS}" \
            --accounts "${accounts}" --reset
        ;;
    execute)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then out="${log_fname}"; else out="${log_fname}_r${rep}"; fi
            python main.py run --driver "${dbms}" --accounts "${accounts}" \
                --transactions "${transactions}" --output-path "${out}"
        done
        if [ "${reps}" -gt 1 ]; then cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true; fi
        ;;
    test)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then out="${log_fname}"; else out="${log_fname}_r${rep}"; fi
            python main.py test --driver "${dbms}" --threads "${LOAD_THREADS}" \
                --accounts "${accounts}" --transactions "${transactions}" --output-path "${out}"
        done
        if [ "${reps}" -gt 1 ]; then cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true; fi
        ;;
    *) echo "Usage: PHASE must be 'load', 'execute' or 'test' (got '${phase}')" >&2; exit 2 ;;
esac
