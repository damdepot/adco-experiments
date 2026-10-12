#!/bin/bash
set -euo pipefail

dbms="${1:-postgres}"
warehouses="${2:-${WAREHOUSES:-32}}"
clients="${3:-${CLIENTS:-8}}"
duration="${DURATION:-180}"
# Seconds of throwaway workload before each measured rep; 0 disables.
warmup="${WARMUP:-30}"
if ! [[ "${warmup}" =~ ^[0-9]+$ ]]; then
    echo "Usage: warmup must be a non-negative integer (got '${warmup}')" >&2
    exit 2
fi

# Harness contract (benchmarks scale, env-overridable). Legacy CLI above wins.
phase="${PHASE:-execute}"
case "${phase}" in
    load|execute) ;;
    *)
        echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2
        exit 2
        ;;
esac
reps="${REPS:-5}"
if ! [[ "${reps}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: REPS must be a positive integer (got '${reps}')" >&2
    exit 2
fi

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/tpcc"
base_log_fname="${exp_path}/results/tpcc/baseline/benchmarks/runExperiment1-tpcc-${dbms}"

cd "${workload_path}"
source venv/bin/activate

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
    for (( rep = 1; rep <= reps; rep++ )); do
        if [ "${reps}" -eq 1 ]; then
            log_fname="${base_log_fname}"
        else
            log_fname="${base_log_fname}_r${rep}"
        fi
        echo "----------------->> TPCC rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
        if [ "${warmup}" -gt 0 ]; then
            echo "----------------->> TPCC warmup ${warmup}s (rep ${rep}/${reps}) <<-----------------"
            $CMD --duration="${warmup}" --no-load
        fi
        $CMD --output-path="${log_fname}" --no-load
    done
fi
