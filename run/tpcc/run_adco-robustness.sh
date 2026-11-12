#!/usr/bin/env bash
# ADCo TPC-C robustness (thin wrapper; see run_arm_robustness.sh).
# Usage: run_adco-robustness.sh [runs=10] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/scripts/tpcc/exp3_Robustness/run_arm_robustness.sh" adco "$@"
