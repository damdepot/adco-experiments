#!/bin/bash
set -euo pipefail

llm_model="${1:-${MODEL:-gemini-3.5-flash-lite}}"
dbms="${2:-postgres}"
warehouses="${3:-${WAREHOUSES:-32}}"
clients="${4:-${CLIENTS:-8}}"
benchmark="${5:-tpcc}"
dir_name="${6:-adco}"
duration="${DURATION:-180}"

if [ "$dir_name" == "aco" ] || [ "$dir_name" == "ACo" ]; then
    out_name="ACo-results"
    res_name="aco"
else
    out_name="ADCo-results"
    res_name="adco"
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
reps="${REPS:-2}"
if ! [[ "${reps}" =~ ^[1-9][0-9]*$ ]]; then
    echo "Usage: REPS must be a positive integer (got '${reps}')" >&2
    exit 2
fi
# Seconds of throwaway workload before each measured rep; 0 disables
# (canonical bench protocol).
warmup="${WARMUP:-30}"
if ! [[ "${warmup}" =~ ^[0-9]+$ ]]; then
    echo "Usage: warmup must be a non-negative integer (got '${warmup}')" >&2
    exit 2
fi

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
workload_path="${exp_path}/workload/apps/${benchmark}"
benchmarks_dir="${exp_path}/results/${benchmark}/${res_name}/benchmarks"
base_log_fname="${exp_path}/results/${benchmark}/${res_name}/benchmarks/runExperiment1-${benchmark}-${dbms}-${llm_model}"
rewrite_dir="${exp_path}/out/app_layer/${out_name}/Rewrite/${dbms}/${benchmark}-${llm_model}"

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
            primary_fname="${benchmarks_dir}/${res_name}.csv"
        else
            log_fname="${base_log_fname}_r${rep}"
            primary_fname="${benchmarks_dir}/${res_name}_r${rep}.csv"
        fi
        echo "----------------->> TPCC/${res_name} rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
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
                    --output-path="${primary_fname}" \
                    --no-load
        cp "${primary_fname}" "${log_fname}"
    done
fi
