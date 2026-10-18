#!/bin/bash
# Naive-LLM rewrite driver.
# Usage: runExperiment1-NaiveLLM.sh <source_path> <dbms> <benchmark> [model]

set -euo pipefail

source_path=$1
dbms=$2
benchmark=$3

if [ -z "${source_path:-}" ] || [ -z "${dbms:-}" ] || [ -z "${benchmark:-}" ]; then
    echo "Usage: $0 <source_path> <dbms> <benchmark> [model]" >&2
    exit 2
fi

exp_path="$(cd "$(dirname "$0")/../../../.." && pwd)"

# Resolve source dir robustly (caller passes a repo-relative path; accept absolute too).
case "${source_path}" in
    /*) src_dir="${source_path}" ;;
    *) src_dir="${exp_path}/${source_path}" ;;
esac

# Rewrite
output_path="${exp_path}/out/app_layer/NaiveLLM-results/Rewrite/${dbms}/${benchmark}-NaiveLLM"
mkdir -p "$(dirname "${output_path}")"

llm_model="${4:-${MODEL:-gemini-3.5-flash-lite}}"

cd "${exp_path}/baselines/NaiveLLM"
if [ -f venv/bin/activate ]; then
    # shellcheck disable=SC1091
    source venv/bin/activate || echo "WARNING: venv activation failed; continuing with system python." >&2
else
    echo "WARNING: venv not found at baselines/NaiveLLM/venv; using current python." >&2
    exit 1
fi

python -m src.cli --source-dir "${src_dir}" --output-dir "${output_path}" --db "${dbms}" --model "${llm_model}"

# Smoke: short throwaway run in the rewritten app catches runtime breakage
# (bad SQL, bad imports) before the paid measurement reps. tpcc.py exits 0
# even when transactions fail (the executor logs and continues), so the log —
# not the exit code — is the signal. Any failure fails the arm loudly.
smoke_log="$(dirname "${output_path}")/smoke.log"
(
    cd "${exp_path}/workload/apps/${benchmark}" && source venv/bin/activate
    cd "${output_path}"
    timeout 120 python tpcc.py "${dbms}" \
        --config="${exp_path}/workload/apps/${benchmark}/db.config" \
        --clients=1 \
        --warehouses="${WAREHOUSES:-32}" \
        --duration=10 \
        --no-load >"${smoke_log}" 2>&1
)
if grep -q "Failed to execute Transaction\|Traceback" "${smoke_log}"; then
    echo "ERROR: rewrite smoke test failed (see ${smoke_log})" >&2
    exit 1
fi
