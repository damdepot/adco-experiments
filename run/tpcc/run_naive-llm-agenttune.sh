#!/bin/bash
# Thin wrapper: Naive-LLM rewrite first, then AgentTune knob tuning.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

ARM="naive-llm-agenttune"
STACK_ARM="${ARM}"
STACK_ORDER="naive-first"
NAIVE_REWRITE_ROOT="out/app_layer/NaiveLLM-results/naive-llm-agenttune"
export ARM STACK_ARM STACK_ORDER NAIVE_REWRITE_ROOT

exec "${ROOT}/scripts/tpcc/exp1_Baselines/runExperiment1-Workload-TPCC-Stacked.sh" "$@"
