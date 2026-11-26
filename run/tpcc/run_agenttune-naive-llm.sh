#!/bin/bash
# Thin wrapper: AgentTune knob tuning first, then Naive-LLM rewrite.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ARM="agenttune-naive-llm"
STACK_ARM="${ARM}"
STACK_ORDER="agenttune-first"
NAIVE_REWRITE_ROOT="out/app_layer/NaiveLLM-results/agenttune-naive-llm"
export ARM STACK_ARM STACK_ORDER NAIVE_REWRITE_ROOT

exec "${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Stacked.sh" "$@"
