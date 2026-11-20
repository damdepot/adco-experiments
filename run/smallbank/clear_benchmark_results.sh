#!/usr/bin/env bash
# Clear SmallBank benchmark outputs so the next run starts empty.
# Shared implementation: run/tpcc/clear_benchmark_results.sh (WORKLOAD).
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"

export WORKLOAD=smallbank
exec "${ROOT}/run/tpcc/clear_benchmark_results.sh" "$@"
