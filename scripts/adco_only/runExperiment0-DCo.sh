#!/bin/bash
set -euo pipefail

codebase_path=$1
llm_model=$2
dbms=$3
benchmark=$4

exp_path="$(cd "$(dirname "$0")/../.." && pwd)"

output_path="${exp_path}/out/adco_only/DCo-results/Knob-Tune/${dbms}/${benchmark}-${llm_model}"
mkdir -p "${output_path}"

cd "${exp_path}/baselines/ADCo"

uv run python -m src.adco "${codebase_path}" \
    --model="${llm_model}" \
    --mode=tune-only \
    --production-db \
    --db-config="${exp_path}/baselines/ADCo/db.config" \
    --db-type="${dbms}" \
    --db-name="${benchmark}" \
    --cpu-cores=2 \
    --memory=8 \
    --knob-path="${output_path}" \
    --log-file="${output_path}/adco_tune.log" \
    --output-path="${output_path}/result.json" \
    --verbose

if [ ! -s "${output_path}/result.json" ]; then
    echo "ERROR: DCo tuning failed to produce valid result.json at ${output_path}/result.json" >&2
    exit 1
fi
