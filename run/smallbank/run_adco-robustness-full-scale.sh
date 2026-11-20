#!/usr/bin/env bash
# Full-scale ADCo SmallBank robustness: same seed/load as the performance run.
# Usage: run_adco-robustness-full-scale.sh [runs=1] [dbms=postgres] [model]
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export FULL_SCALE=1
exec "${ROOT}/scripts/smallbank/exp3_Robustness/run_arm_robustness.sh" adco "$@"
