#!/usr/bin/env bash
# SmallBank robustness sweep for a rewrite arm.
# Usage: run_all_robustness.sh <naive-llm|naive-llm-agenttune|agenttune-naive-llm|aco|adco|py-dbridge> [runs] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARM="${1:-}"
if [ -z "${ARM}" ]; then
    echo "Usage: $0 <naive-llm|naive-llm-agenttune|agenttune-naive-llm|aco|adco|py-dbridge> [runs] [dbms=postgres] [model]" >&2
    exit 2
fi
shift
exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" smallbank "${ARM}" "$@"
