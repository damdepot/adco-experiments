#!/usr/bin/env bash
# Thin entry point: the verify driver lives in scripts/tpcc/exp2_Correctness/.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
exec "${ROOT}/scripts/tpcc/exp2_Correctness/run_verify.sh" "$@"
