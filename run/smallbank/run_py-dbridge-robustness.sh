#!/usr/bin/env bash
# Py-DBridge SmallBank robustness (thin wrapper; see run_arm_robustness.sh).
# Usage: run_py-dbridge-robustness.sh [runs=1] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/scripts/smallbank/exp3_Robustness/run_arm_robustness.sh" py-dbridge "$@"
