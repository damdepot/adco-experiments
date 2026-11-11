#!/bin/bash
# TPC-C prompt-repair entry point.
# Usage: run_prompt_search.sh [dbms=postgres] [model]
# The benchmark is implicit; the shared loop lives in
# scripts/common/app_layer/exp3_PromptSearch/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

# Tolerate the old invocation (`run_prompt_search.sh tpcc ...`); the
# benchmark is implicit here.
if [ "${1:-}" = "tpcc" ]; then
    shift
fi

exec "${ROOT}/scripts/common/app_layer/exp3_PromptSearch/run_prompt_search.sh" tpcc "$@"
