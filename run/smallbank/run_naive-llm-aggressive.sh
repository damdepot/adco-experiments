#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export ARM="naive-llm-aggressive"
export NAIVE_REWRITE_ROOT="out/app_layer/NaiveLLM-aggressive-results"
export PROMPT_FILE="${ROOT}/baselines/NaiveLLM/prompts/selected-smallbank.txt"

if [ ! -f "${PROMPT_FILE}" ]; then
    echo "ERROR: missing selected prompt ${PROMPT_FILE}" >&2
    echo "Run scripts/common/app_layer/exp3_PromptSearch/run_prompt_search.sh smallbank first (an empty file is valid)." >&2
    exit 1
fi

exec "${ROOT}/run/smallbank/run_naive-llm.sh" "$@"
