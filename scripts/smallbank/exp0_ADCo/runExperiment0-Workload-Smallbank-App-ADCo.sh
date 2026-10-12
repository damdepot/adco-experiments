#!/bin/bash
set -euo pipefail

llm_model="${1:-${MODEL:-gemini-3.5-flash-lite}}"
dbms="${2:-postgres}"
accounts="${3:-${ACCOUNTS:-5000000}}"
transactions="${4:-${TRANSACTIONS:-60000}}"
benchmark="${5:-smallbank}"
dir_name="${6:-adco}"

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
# Benchmarks-scale load parallelism, env-overridable (canonical bench protocol).
load_threads="${LOAD_THREADS:-4}"

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
benchmarks_dir="${exp_path}/results/${benchmark}/${res_name}/benchmarks"
base_log_fname="${exp_path}/results/${benchmark}/${res_name}/benchmarks/runExperiment1-${benchmark}-${dbms}-${llm_model}"
rewrite_dir="${exp_path}/out/app_layer/${out_name}/Rewrite/${dbms}/${benchmark}-${llm_model}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

cd "${rewrite_dir}"

if [ "${phase}" = "load" ]; then
    python main.py load \
                    --driver "${dbms}" \
                    --threads "${load_threads}" \
                    --accounts "${accounts}" \
                    --reset
else
    for (( rep = 1; rep <= reps; rep++ )); do
        if [ "${reps}" -eq 1 ]; then
            log_fname="${base_log_fname}"
            primary_fname="${benchmarks_dir}/${res_name}.csv"
        else
            log_fname="${base_log_fname}_r${rep}"
            primary_fname="${benchmarks_dir}/${res_name}_r${rep}.csv"
        fi
        echo "----------------->> Smallbank/${res_name} rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
        python main.py run \
                        --driver "${dbms}" \
                        --accounts "${accounts}" \
                        --transactions "${transactions}" \
                        --output-path "${primary_fname}"
        cp "${primary_fname}" "${log_fname}"
    done
fi
