#!/usr/bin/env bash
set -euo pipefail

exp_path="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
workload_path="${exp_path}/workload/apps/tpcc"
docker_script="${BENCH_CMDDOCKER:-${exp_path}/scripts/_lib/docker.sh}"
db_container="${DB_CONTAINER:-${BENCH_DB_CONTAINER:-adcoexp-db}}"

# Dispatch: new bench protocol (<dir> <file> [reps], optionally with
# PHASE=load|execute) vs legacy (<dbms> <warehouses> <clients>).
is_bench=0
if [ "${PHASE:-}" = "load" ] || [ "${PHASE:-}" = "execute" ]; then
    is_bench=1
elif [ $# -ge 2 ]; then
    case "${1:-}" in
        baseline) is_bench=1 ;;
        *)
            case "${2:-}" in
                *.csv) is_bench=1 ;;
            esac
            case "${1:-}" in
                */*) is_bench=1 ;;
            esac
            ;;
    esac
fi

if [ "${is_bench}" -eq 1 ]; then
    dir="${1:-}"
    file_name="${2:-}"
    # Repetitions: positional arg wins over env. Load phase always runs once.
    reps="${3:-${REPS:-3}}"

    if [ -z "${dir}" ] || [ -z "${file_name}" ]; then
        echo "Usage: $(basename "$0") <dir> <file_name> [reps]" >&2
        exit 2
    fi
    if ! [[ "${reps}" =~ ^[1-9][0-9]*$ ]]; then
        echo "Usage: reps must be a positive integer (got '${reps}')" >&2
        exit 2
    fi

    phase="${PHASE:-execute}"
    case "${phase}" in
        load|execute) ;;
        *)
            echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2
            exit 2
            ;;
    esac

    dbms="${DBMS:-postgres}"
    # Benchmarks-scale defaults, env-overridable.
    warehouses="${WAREHOUSES:-6}"
    clients="${CLIENTS:-6}"
    duration="${DURATION:-60}"
    # Seconds of throwaway workload before each measured rep; 0 disables.
    warmup="${WARMUP:-10}"
    if ! [[ "${warmup}" =~ ^[0-9]+$ ]]; then
        echo "Usage: warmup must be a non-negative integer (got '${warmup}')" >&2
        exit 2
    fi
    results_dir="${RESULTS_DIR:-${exp_path}/results/adco_only/baseline/benchmarks}"

    cd "${workload_path}"
    source venv/bin/activate

    if [ "${dir}" != "baseline" ]; then
        output_path="${exp_path}/out/${dir}"
        cd "${output_path}"
        echo "------->>${output_path}<<-------"
    fi

    CMD="python tpcc.py ${dbms} \
                    --config=${workload_path}/db.config \
                    --clients=${clients} \
                    --warehouses=${warehouses} \
                    --duration=${duration}"

    if [ "${phase}" = "load" ]; then
        CMD="${CMD} \
                    --reset \
                    --no-execute"
        $CMD
    else
        mkdir -p "${results_dir}"
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
            "${docker_script}" Checkpoint "${db_container}"
            if [ "${warmup}" -gt 0 ]; then
                echo "----------------->> TPCC warmup ${warmup}s (rep ${rep}/${reps}) <<-----------------"
                $CMD --duration="${warmup}" --no-load
            fi
            $CMD --output-path="${log_fname}" --no-load
        done
    fi
    exit 0
fi

# Legacy CLI: <dbms> <warehouses> <clients> (old callers keep working; args
# map to env, benchmarks scale when absent).
dbms="${1:-${DBMS:-postgres}}"
warehouses="${2:-${WAREHOUSES:-6}}"
clients="${3:-${CLIENTS:-6}}"
duration="${DURATION:-60}"

log_fname="${exp_path}/results/adco_only/baseline/benchmarks/runExperiment1-tpcc-${dbms}"

cd "${workload_path}"
source venv/bin/activate

CMD="python tpcc.py ${dbms} \
                --config=${workload_path}/db.config \
                --clients=${clients} \
                --warehouses=${warehouses} \
                --duration=${duration} \
                --output-path=${log_fname} \
                --reset"
$CMD
