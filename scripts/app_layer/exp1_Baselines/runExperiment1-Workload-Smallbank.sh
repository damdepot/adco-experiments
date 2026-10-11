#!/bin/bash
set -euo pipefail

dbms="${1:-postgres}"
accounts="${2:-${ACCOUNTS:-1000000}}"
transactions="${3:-${TRANSACTIONS:-60000}}"

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
db_container="${DB_CONTAINER:-adcoexp-db}"

exp_path="$(cd "$(dirname "$0")/../../.." && pwd)"
base_log_fname="${exp_path}/results/app_layer/baseline/benchmarks/runExperiment1-smallbank-${dbms}"
CMDDocker="${CMDDOCKER:-${exp_path}/scripts/_lib/docker.sh}"

cd "${exp_path}/workload/apps/smallbank"
source venv/bin/activate

if [ "${phase}" = "load" ]; then
    python main.py load \
                    --driver "${dbms}" \
                    --threads "${LOAD_THREADS:-8}" \
                    --accounts "${accounts}" \
                    --reset
else
    for (( rep = 1; rep <= reps; rep++ )); do
        if [ "${reps}" -eq 1 ]; then
            log_fname="${base_log_fname}"
        else
            log_fname="${base_log_fname}_r${rep}"
        fi
        echo "----------------->> Smallbank rep ${rep}/${reps} (${log_fname##*/}) <<-----------------"
        "${CMDDocker}" Checkpoint "${db_container}"
        python main.py test \
                        --driver "${dbms}" \
                        --threads "${LOAD_THREADS:-8}" \
                        --accounts "${accounts}" \
                        --transactions "${transactions}" \
                        --output-path "${log_fname}"
    done
fi
