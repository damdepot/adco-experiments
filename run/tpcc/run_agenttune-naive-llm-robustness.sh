#!/bin/bash
# AgentTune + Naive-LLM robustness: tune once, then N rewrites, all verified.
# Usage: run_agenttune-naive-llm-robustness.sh [runs=10] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" tpcc agenttune-naive-llm "$@"
