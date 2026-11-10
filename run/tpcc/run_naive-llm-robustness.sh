#!/bin/bash
# Thin wrapper: [runs=10] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${ROOT}/scripts/tpcc/exp3_Robustness/run_naive-llm-robustness.sh" "$@"
