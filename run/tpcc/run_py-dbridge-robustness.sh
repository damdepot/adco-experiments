#!/usr/bin/env bash
# Py-DBridge TPC-C robustness (thin wrapper; see run_arm_robustness.sh).
# Usage: run_py-dbridge-robustness.sh [runs=1] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/scripts/common/app_layer/exp3_Robustness/run_arm_robustness.sh" tpcc py-dbridge "$@"
