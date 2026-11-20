#!/bin/bash
# Thin wrapper: [runs=10] [dbms=postgres] [model]; TEMP=<float> sets rewrite temperature
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" tpcc naive-llm "$@"
