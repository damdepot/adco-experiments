#!/usr/bin/env bash
# ADCo SmallBank robustness (thin wrapper; see run_arm_robustness.sh).
# Usage: run_adco-robustness.sh [runs=10] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/scripts/smallbank/exp3_Robustness/run_arm_robustness.sh" adco "$@"
