#!/usr/bin/env bash
#
# Canonical TPC-C workload runner (OtterTune).
# Canonical (bench_lib): <dir> <file> [reps], PHASE=load|execute (default execute).
# Legacy: <dbms> <warehouses> <clients> <benchmark>
#
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/tpcc"

WAREHOUSES="${WAREHOUSES:-32}"
CLIENTS="${CLIENTS:-8}"
DURATION="${DURATION:-180}"
WARMUP="${WARMUP:-30}"
REPS_DEFAULT="${REPS:-2}"
TOOL_RESULTS="${exp_path}/results/tpcc/ottertune/benchmarks"

if [[ "${2:-}" == *.csv* ]]; then
    dir="${1}"
    file_name="${2}"
    reps="${3:-${REPS_DEFAULT}}"
    phase="${PHASE:-execute}"
    dbms="postgres"
    warehouses="${WAREHOUSES}"
    clients="${CLIENTS}"
    duration="${DURATION}"
    warmup="${WARMUP}"
    case "${phase}" in
        load|execute) ;;
        *) echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2; exit 2 ;;
    esac
    results_dir="${RESULTS_DIR:-${result_benchmark_path:-${TOOL_RESULTS}}}"
    mkdir -p "${results_dir}"
    cd "${workload_path}"
    # shellcheck disable=SC1091
    source venv/bin/activate
    if [ "${dir}" != "baseline" ]; then
        output_path="${exp_path}/out/${dir}"
        [ -d "${output_path}" ] || output_path="${workload_path}"
    else
        output_path="${workload_path}"
    fi
    base_cmd="python tpcc.py ${dbms} --config=${workload_path}/db.config \
                --clients=${clients} --warehouses=${warehouses} --duration=${duration}"
    if [ "${phase}" = "load" ]; then
        # shellcheck disable=SC2086
        $base_cmd --reset --no-execute
        exit 0
    fi
    echo "------->>${output_path}<<-------"
    cd "${output_path}"
    for (( rep = 1; rep <= reps; rep++ )); do
        if [ "${reps}" -eq 1 ]; then
            rep_file="${file_name}"
        elif [[ "${file_name}" == *.* ]]; then
            rep_file="${file_name%.*}_r${rep}.${file_name##*.}"
        else
            rep_file="${file_name}_r${rep}"
        fi
        log_fname="${results_dir}/${rep_file}"
        echo "----------------->> TPCC rep ${rep}/${reps} (${rep_file}) <<-----------------"
        if [ "${warmup}" -gt 0 ]; then
            # shellcheck disable=SC2086
            $base_cmd --duration="${warmup}" --no-load || true
        fi
        # shellcheck disable=SC2086
        $base_cmd --output-path="${log_fname}" --no-load
    done
    exit 0
fi

dbms="${1:-postgres}"
warehouses="${2:-${WAREHOUSES}}"
clients="${3:-${CLIENTS}}"
benchmark="${4:-tpcc}"
phase="${PHASE:-test}"
duration="${DURATION}"
warmup="${WARMUP}"
results_dir="${result_benchmark_path:-${TOOL_RESULTS}}"
mkdir -p "${results_dir}"
log_fname="${results_dir}/runExperiment1-${benchmark}-${dbms}-ottertune"
cd "${workload_path}"
# shellcheck disable=SC1091
source venv/bin/activate
reps="${REPS_DEFAULT}"
base_cmd="python tpcc.py ${dbms} --config=${workload_path}/db.config \
                --clients=${clients} --warehouses=${warehouses} --duration=${duration}"
case "${phase}" in
    load)
        # shellcheck disable=SC2086
        $base_cmd --reset --no-execute
        ;;
    execute)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then out="${log_fname}"; else out="${log_fname}_r${rep}"; fi
            if [ "${warmup}" -gt 0 ]; then
                # shellcheck disable=SC2086
                $base_cmd --duration="${warmup}" --no-load || true
            fi
            # shellcheck disable=SC2086
            $base_cmd --output-path="${out}" --no-load
        done
        if [ "${reps}" -gt 1 ]; then cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true; fi
        ;;
    test)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then out="${log_fname}"; else out="${log_fname}_r${rep}"; fi
            # shellcheck disable=SC2086
            $base_cmd --output-path="${out}" --reset
        done
        if [ "${reps}" -gt 1 ]; then cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true; fi
        ;;
    *) echo "Usage: PHASE must be 'load', 'execute' or 'test' (got '${phase}')" >&2; exit 2 ;;
esac
