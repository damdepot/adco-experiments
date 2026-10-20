#!/bin/bash
set -euo pipefail

dbms="${1:-postgres}"
accounts="${2:-${ACCOUNTS:-5000000}}"
transactions="${3:-${TRANSACTIONS:-60000}}"
benchmark="${4:-smallbank}"

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
# Per-rep measurement hygiene (shared): reset DB state before each measured rep.
# shellcheck disable=SC1091
source "${exp_path}/scripts/_lib/bench_lib.sh"
benchmarks_dir="${exp_path}/results/${benchmark}/py-dbridge/benchmarks"
base_log_fname="${exp_path}/results/${benchmark}/py-dbridge/benchmarks/runExperiment1-${benchmark}-${dbms}"
rewrite_dir="${exp_path}/out/app_layer/Py-DBridge-results/Rewrite/${dbms}/${benchmark}-Py-DBridge"

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
    # Single warmup to avoid coldstart; measured reps follow.
    if [ "${WARMUP_TRANSACTIONS:-0}" -gt 0 ]; then
        echo "----------------->> Smallbank warmup (once before ${reps} reps) <<-----------------"
        python main.py run --driver "${dbms}" \
            --accounts "${WARMUP_ACCOUNTS:-${accounts}}" \
            --transactions "${WARMUP_TRANSACTIONS}"
    fi
    if declare -F bench_warmup_settle >/dev/null 2>&1; then bench_warmup_settle "smallbank"; fi
    for (( rep = 1; rep <= reps; rep++ )); do
        if declare -F bench_rep_prep >/dev/null 2>&1; then bench_rep_prep; fi
        if [ "${reps}" -eq 1 ]; then
            log_fname="${base_log_fname}"
            primary_fname="${benchmarks_dir}/py-dbridge.csv"
        else
            log_fname="${base_log_fname}_r${rep}"
            primary_fname="${benchmarks_dir}/py-dbridge_r${rep}.csv"
        fi
        echo "----------------->> Smallbank/Py-DBridge rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
        python main.py run \
                        --driver "${dbms}" \
                        --accounts "${accounts}" \
                        --transactions "${transactions}" \
                        --output-path "${primary_fname}"
        cp "${primary_fname}" "${log_fname}"
    done
fi
