#!/bin/bash
# Full-scale AgentTune + Naive-LLM SmallBank robustness: tune once, then verify
# on the performance seed/load.
# Usage: run_agenttune-naive-llm-robustness-full-scale.sh [runs=1] [dbms] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export FULL_SCALE=1
exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" smallbank agenttune-naive-llm "$@"
