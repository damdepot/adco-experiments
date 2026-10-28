#!/bin/bash
set -euo pipefail

dbms="${1:-postgres}"
accounts="${2:-${SMALLBANK_ACCOUNTS:-5000000}}"
transactions="${3:-${SMALLBANK_TRANSACTIONS:-60000}}"

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
exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
# shellcheck disable=SC1091
source "${exp_path}/scripts/_lib/bench_lib.sh"
base_log_fname="${exp_path}/results/smallbank/baseline/benchmarks/runExperiment1-smallbank-${dbms}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

if [ "${phase}" = "load" ]; then
    python main.py load \
                    --driver "${dbms}" \
                    --threads "${LOAD_THREADS:-4}" \
                    --accounts "${accounts}" \
                    --reset
else
    # Single warmup to avoid coldstart; measured reps follow.
    if [ "${SMALLBANK_WARMUP_TRANSACTIONS:-0}" -gt 0 ]; then
        echo "----------------->> Smallbank warmup (once before ${reps} reps) <<-----------------"
        python main.py run --driver "${dbms}" \
            --clients "${SMALLBANK_CLIENTS:-1}" \
            --accounts "${SMALLBANK_WARMUP_ACCOUNTS:-${accounts}}" \
            --transactions "${SMALLBANK_WARMUP_TRANSACTIONS}"
    fi
    if declare -F bench_warmup_settle >/dev/null 2>&1; then bench_warmup_settle "smallbank"; fi
    for (( rep = 1; rep <= reps; rep++ )); do
        if declare -F bench_rep_prep >/dev/null 2>&1; then bench_rep_prep; fi
        if [ "${reps}" -eq 1 ]; then
            log_fname="${base_log_fname}"
        else
            log_fname="${base_log_fname}_r${rep}"
        fi
        echo "----------------->> Smallbank rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
        python main.py run \
                        --clients "${SMALLBANK_CLIENTS:-1}" \
                        --driver "${dbms}" \
                        --accounts "${accounts}" \
                        --transactions "${transactions}" \
                        --output-path "${log_fname}"
    done
fi
