#!/usr/bin/env bash
#
# Canonical TPC-C workload runner (baseline).
#
# Two modes:
#   Canonical (called by bench_lib via BENCH_CMDRUNTPCC):
#     runExperiment1-Workload-TPCC.sh <dir> <file> [reps]
#     PHASE=load|execute selects the phase (default: execute).
#     <dir> is 'baseline' or an out/<dir> rewritten app (sandbox switch).
#     Scale defaults to benchmarks scale, env-overridable:
#       WAREHOUSES=32 CLIENTS=8 DURATION=180 WARMUP=30 REPS=2
#   Legacy (standalone):
#     runExperiment1-Workload-TPCC.sh <dbms> <warehouses> <clients>
#     PHASE unset => full reset+execute with reps loop + CHECKPOINT + warmup.
#
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
# Per-rep measurement hygiene (shared): reset DB state before each measured rep.
# shellcheck disable=SC1091
source "${exp_path}/scripts/_lib/bench_lib.sh"
workload_path="${exp_path}/workload/apps/tpcc"

WAREHOUSES="${WAREHOUSES:-32}"
CLIENTS="${CLIENTS:-8}"
DURATION="${DURATION:-180}"
WARMUP="${WARMUP:-30}"
REPS_DEFAULT="${REPS:-2}"

# ── Canonical mode: $2 looks like a CSV file ─────────────────────────────
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

    results_dir="${RESULTS_DIR:-${result_benchmark_path:-${exp_path}/results/tpcc/baseline/benchmarks}}"
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

    base_cmd="python tpcc.py ${dbms} \
                --config=${workload_path}/db.config \
                --clients=${clients} \
                --warehouses=${warehouses} \
                --duration=${duration}"

    if [ "${phase}" = "load" ]; then
        # shellcheck disable=SC2086
        $base_cmd --reset --no-execute
        exit 0
    fi

    echo "------->>${output_path}<<-------"
    cd "${output_path}"
    for (( rep = 1; rep <= reps; rep++ )); do
        if declare -F bench_rep_prep >/dev/null 2>&1; then bench_rep_prep; fi
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
            echo "----------------->> TPCC warmup ${warmup}s (rep ${rep}/${reps}) <<-----------------"
            # shellcheck disable=SC2086
            $base_cmd --duration="${warmup}" --no-load || true
        fi
        # shellcheck disable=SC2086
        $base_cmd --output-path="${log_fname}" --no-load
    done
    exit 0
fi

# ── Legacy mode: <dbms> <warehouses> <clients> ────────────────────────────
dbms="${1:-postgres}"
warehouses="${2:-${WAREHOUSES}}"
clients="${3:-${CLIENTS}}"
phase="${PHASE:-test}"
duration="${DURATION}"
warmup="${WARMUP}"

results_dir="${result_benchmark_path:-${exp_path}/results/tpcc/baseline/benchmarks}"
mkdir -p "${results_dir}"
log_fname="${results_dir}/runExperiment1-tpcc-${dbms}"

cd "${workload_path}"
# shellcheck disable=SC1091
source venv/bin/activate

reps="${REPS_DEFAULT}"
base_cmd="python tpcc.py ${dbms} \
                --config=${workload_path}/db.config \
                --clients=${clients} \
                --warehouses=${warehouses} \
                --duration=${duration}"

case "${phase}" in
    load)
        # shellcheck disable=SC2086
        $base_cmd --reset --no-execute
        ;;
    execute)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                out="${log_fname}"
            else
                out="${log_fname}_r${rep}"
            fi
            echo "----------------->> TPCC legacy execute rep ${rep}/${reps} <<-----------------"
            if [ "${warmup}" -gt 0 ]; then
                # shellcheck disable=SC2086
                $base_cmd --duration="${warmup}" --no-load || true
            fi
            # shellcheck disable=SC2086
            $base_cmd --output-path="${out}" --no-load
        done
        if [ "${reps}" -gt 1 ]; then
            cp "${log_fname}_r${reps}" "${log_fname}" 2>/dev/null || true
        fi
        ;;
    test)
        for (( rep = 1; rep <= reps; rep++ )); do
            if [ "${reps}" -eq 1 ]; then
                out="${log_fname}"
            else
                out="${log_fname}_r${rep}"
            fi
            echo "----------------->> TPCC legacy test rep ${rep}/${reps} <<-----------------"
            # shellcheck disable=SC2086
            $base_cmd --output-path="${out}" --reset
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
