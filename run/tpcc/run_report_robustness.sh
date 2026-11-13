#!/usr/bin/env bash
# TPC-C robustness-only report (all arm sweeps).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec python3 "${ROOT}/scripts/tpcc/exp3_Robustness/report_robustness.py" "$@"
