#!/usr/bin/env bash
# List every recorded naive-llm robustness sweep (out/app_layer/robustness/naive-llm/).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "${ROOT}/scripts/tpcc/exp3_Robustness/log_robustness_runs.py" naive-llm "$@"
