#!/bin/bash
# Naive-LLM + AgentTune robustness: tune once, then N rewrites, all verified.
# Usage: run_naive-llm-agenttune-robustness.sh [runs=10] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" tpcc naive-llm-agenttune "$@"
