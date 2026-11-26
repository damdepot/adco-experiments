#!/usr/bin/env bash
# ACo TPC-C robustness (thin wrapper; see run_arm_robustness.sh).
# Usage: run_aco-robustness.sh [runs=10] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" tpcc aco "$@"
