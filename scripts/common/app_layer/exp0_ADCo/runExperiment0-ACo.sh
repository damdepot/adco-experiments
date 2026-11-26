#!/bin/bash

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../../../.." && pwd)"

# ACo Rewrite
output_path="${exp_path}/out/app_layer/ACo-results/Rewrite/${dbms}/${benchmark}-${llm_model}"
mkdir -p "${output_path}"

# Upstream copy_to_sandbox may skip: pre-populate the sandbox so optimizer
# tools always find the files. Managed marker lets a later upstream copy
# still recognise (and refresh) the dir.
if [ ! -f "${output_path}/.adco_sandbox" ]; then
    ( cd "${codebase_path}" && tar --exclude=.git --exclude=__pycache__ --exclude=.venv --exclude=venv -cf - . ) | ( cd "${output_path}" && tar -xf - )
    printf '%s' "adco-managed-sandbox-v1" > "${output_path}/.adco_sandbox"
fi

# Upstream ADCo regression: optimizer tools resolve sandbox-relative paths
# against CWD (state["sandbox"] unset). Run from the sandbox root so
# relative paths resolve; invoke the project venv python directly with
# PYTHONPATH instead of `uv run` (which would mutate/recreate .venv).
adco_venv="${exp_path}/baselines/ADCo/.venv/bin/python"
[ -x "${adco_venv}" ] || adco_venv="${exp_path}/baselines/ADCo/venv/bin/python"
mkdir -p "${output_path}/out/adco"
cd "${output_path}"
PYTHONPATH="${exp_path}/baselines/ADCo" "${adco_venv}" -m src.adco "${codebase_path}" \
    --model="${llm_model}" \
    --mode=rewrite-only \
    --db-type="${dbms}" \
    --db-name="${benchmark}" \
    --sandbox-dir="${output_path}" \
    --intent-output="${output_path}/out/adco/intent_result.json" \
    --rewriter-output="${output_path}/out/adco/rewriter_result.json" \
    --output-path="${output_path}/result.json" \
    --verbose
rc=$?
if [ $rc -ne 0 ]; then
    echo "--- ${output_path}/logs/adco.log (tail) ---" >&2
    tail -n 50 "${output_path}/logs/adco.log" >&2 || true
    exit $rc
fi
