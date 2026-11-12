#!/usr/bin/env bash
# TPC-C robustness sweep for a rewrite arm.
# Usage: run_robustness.sh <naive-llm|aco|adco|py-dbridge> [runs] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
ARM="${1:-}"
if [ -z "${ARM}" ]; then
    echo "Usage: $0 <naive-llm|aco|adco|py-dbridge> [runs] [dbms=postgres] [model]" >&2
    exit 2
fi
shift
exec "${ROOT}/scripts/tpcc/exp3_Robustness/run_arm_robustness.sh" "${ARM}" "$@"
