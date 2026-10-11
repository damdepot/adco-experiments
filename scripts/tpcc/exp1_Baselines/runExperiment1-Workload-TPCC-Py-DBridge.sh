#!/bin/bash
set -euo pipefail

dbms="${1:-postgres}"
warehouses="${2:-${WAREHOUSES:-6}}"
clients="${3:-${CLIENTS:-6}}"
benchmark="${4:-tpcc}"
duration="${DURATION:-60}"

# Harness contract (benchmarks scale, env-overridable). Legacy CLI above wins.
phase="${PHASE:-execute}"
case "${phase}" in
    load|execute) ;;
    *)
        echo "Usage: PHASE must be 'load' or 'execute' (got '${phase}')" >&2
        exit 2
        ;;
esac
reps="${REPS:-3}"
if ! [[ "${reps}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: REPS must be a positive integer (got '${reps}')" >&2
    exit 2
fi
# Seconds of throwaway workload before each measured rep; 0 disables
# (canonical bench protocol).
warmup="${WARMUP:-10}"
if ! [[ "${warmup}" =~ ^[0-9]+$ ]]; then
    echo "Usage: warmup must be a non-negative integer (got '${warmup}')" >&2
    exit 2
fi
db_container="${DB_CONTAINER:-adcoexp-db}"

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/${benchmark}"
base_log_fname="${exp_path}/results/${benchmark}/py-dbridge/benchmarks/runExperiment1-${benchmark}-${dbms}"
rewrite_dir="${exp_path}/out/app_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"
CMDDocker="${CMDDOCKER:-${exp_path}/scripts/_lib/docker.sh}"

cd "${workload_path}"
source venv/bin/activate

cd "${rewrite_dir}"

if [ "${phase}" = "load" ]; then
    python tpcc.py "${dbms}" \
                --config="${workload_path}/db.config" \
                --warehouses="${warehouses}" \
                --reset \
                --no-execute
else
    for (( rep = 1; rep <= reps; rep++ )); do
        if [ "${reps}" -eq 1 ]; then
            log_fname="${base_log_fname}"
        else
            log_fname="${base_log_fname}_r${rep}"
        fi
        echo "----------------->> TPCC/Py-DBridge rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
        "${CMDDocker}" Checkpoint "${db_container}"
        if [ "${warmup}" -gt 0 ]; then
            echo "----------------->> TPCC warmup ${warmup}s (rep ${rep}/${reps}) <<-----------------"
            python tpcc.py "${dbms}" \
                        --config="${workload_path}/db.config" \
                        --clients="${clients}" \
                        --warehouses="${warehouses}" \
                        --duration="${warmup}" \
                        --no-load
        fi
        python tpcc.py "${dbms}" \
                    --config="${workload_path}/db.config" \
                    --clients="${clients}" \
                    --warehouses="${warehouses}" \
                    --duration="${duration}" \
                    --output-path="${log_fname}" \
                    --no-load
    done
fi
